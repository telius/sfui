local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
local GameTooltip = sfui.common.get_tooltip() -- private addon tooltip (methods.md §3.7.2)
sfui.dungeonjournal = sfui.dungeonjournal or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/dungeonjournal/dungeonjournal.lua
--  Classic Forever / Camelot Dungeon Journal — main window orchestrator.
--
--  Layout (860 × 600 px):
--    Left sidebar   (200 px)  – scrollable dungeon/raid list, level badges
--    Right content  (640 px)  – tab-switched boss view / quest view
--      Each view: left sub-panel (list) + right detail pane
--
--  Public API:
--    sfui.dungeonjournal.Toggle()
--    sfui.dungeonjournal.Open()
--    sfui.dungeonjournal.SelectDungeon(dungeonID)
--    sfui.dungeonjournal.Rebuild()
--    sfui.dungeonjournal.ClearCache()
--
--  Theme: sfui.theme.ApplyWindowStyle / ApplyHeaderStyle / RegisterWindow
--  DB:    sfui.db.RegisterDefaults  / SfuiDB.dungeonjournal
--  Data:  sfui.dj_camelot  (data/dj_camelot.lua)
-- ══════════════════════════════════════════════════════════════════════════════

-- Guard: Camelot / Classic only
if sfui.isRetail then
    return
end

-- ─── Constants ────────────────────────────────────────────────────────────────
local FRAME_W                       = 860
local FRAME_H                       = 600
local SIDEBAR_W                     = 200
local HEADER_H                      = 46
local TAB_H                         = 28

-- ─── Locals ───────────────────────────────────────────────────────────────────
local CreateFrame                   = _G.CreateFrame
local UIParent                      = _G.UIParent
local GetTime                       = _G.GetTime
local InCombatLockdown              = _G.InCombatLockdown
local pairs, ipairs, next           = _G.pairs, _G.ipairs, _G.next
local set_square_icon_coords        = (sfui.common and sfui.common.set_square_icon_coords)
    or function(tex) if tex and tex.SetTexCoord then tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) end end
local pcall, type, tostring, tonumber = _G.pcall, _G.type, _G.tostring, _G.tonumber
local math_floor, math_max          = math.floor, math.max
local string_format                 = string.format

local common                        = sfui.common
local theme                         = sfui.theme

local frame                         = nil -- main window (lazy-created)
local sidebarFrame                  = nil
local mapPanel                      = nil
local bossPanel                     = nil
local questPanel                    = nil
local externalPanels                = {}
local externalMounted               = {}
local externalThemeDirty            = {}
local bossesInitialized             = false
local questsInitialized             = false
local initPayload                   = nil
local journalThemeDirty             = false

local lastSfuiDBRef                 = nil
local cachedDJDB                    = nil
local cachedCharHidden              = nil
local cachedCharKey                 = nil
local syncedWishlistUnion           = false
local cachedDataRef                 = nil
local dungeonByID                   = nil
local dungeonTabByID                = nil

local EXTERNAL_TAB_ORDER = { "upgrades", "sets", "recipes", "fishing" }
local EXTERNAL_TAB_DEFS = {
    upgrades = {
        label      = "upgrades",
        width      = 84,
        btnField   = "upgradesTabBtn",
        panelField = "upgradesPanel",
        getModule  = function() return sfui.upgrades end,
        onRebuild  = function(mod)
            if mod.MarkDirty then mod.MarkDirty() end
        end,
    },
    sets = {
        label      = "sets",
        width      = 62,
        btnField   = "setsTabBtn",
        panelField = "setsPanel",
        getModule  = function() return sfui.sets end,
        onRebuild  = function(mod)
            if mod.OnPanelShown then mod.OnPanelShown() end
        end,
    },
    recipes = {
        label      = "recipes",
        width      = 76,
        btnField   = "recipesTabBtn",
        panelField = "recipesPanel",
        getModule  = function() return sfui.recipes and sfui.recipes.browser end,
        onRebuild  = function(mod)
            if mod.OnPanelShown then mod.OnPanelShown() end
        end,
    },
    fishing = {
        label      = "fishing",
        width      = 76,
        btnField   = "fishingTabBtn",
        panelField = "fishingPanel",
        getModule  = function() return sfui.fishing and sfui.fishing.atlas end,
        onRebuild  = function(mod)
            if mod.Update then mod.Update() end
        end,
    },
}

local selectedDungeonID             = nil -- dungeon id string
local selectedMode                  = "map" -- "map" | "bosses" | "quests"
local selectedTab                   = "dungeons" -- "dungeons" | "raids" | "upgrades" | "recipes" | "fishing"
local lastJournalTab                = "dungeons" -- last active "dungeons" | "raids"

local function HasExternalTab(tabKey)
    local def = EXTERNAL_TAB_DEFS[tabKey]
    if not def then return false end
    local mod = def.getModule()
    return mod ~= nil and type(mod.MountPanel) == "function"
end

local function IsExternalTab(tabKey)
    local key = tabKey or selectedTab
    return EXTERNAL_TAB_DEFS[key] ~= nil and HasExternalTab(key)
end

local function IsValidTab(tabKey)
    return tabKey == "dungeons" or tabKey == "raids" or IsExternalTab(tabKey)
end

-- ─── SavedVariables helpers ───────────────────────────────────────────────────
sfui.db.RegisterDefaults("dungeonjournal", {
    lastDungeon         = nil,
    lastMode            = "map",
    lastTab             = "dungeons",
    questFaction        = "all",
    lastBoss            = 1,
    lastQuest           = 1,
    autoDetectInstance  = true,
    showItemTooltips    = true,
    wishlist            = {},
    charHidden          = {},
    showHiddenInSidebar = false,
    autoHideTrivialPins = false,
    showAllDungeons     = false,
})

local GetPlayerKey = sfui.common.get_player_unique_key

local function ResetDBCacheIfNeeded()
    local cur = _G.SfuiDB
    if cur ~= lastSfuiDBRef then
        lastSfuiDBRef = cur
        cachedDJDB = nil
        cachedCharHidden = nil
        cachedCharKey = nil
        syncedWishlistUnion = false
    end
end

local function GetCharHidden()
    ResetDBCacheIfNeeded()
    local charKey = GetPlayerKey()
    if cachedCharHidden and cachedCharKey == charKey then
        return cachedCharHidden
    end

    SfuiDB = SfuiDB or {}
    lastSfuiDBRef = SfuiDB
    SfuiDB.dungeonjournal = SfuiDB.dungeonjournal or {}
    local dj = SfuiDB.dungeonjournal
    dj.charHidden = dj.charHidden or {}

    if not dj.charHidden[charKey] then
        dj.charHidden[charKey] = {
            hiddenDungeons      = {},
            hiddenPins          = {},
            hiddenQuestPins     = {},
            showHiddenInSidebar = dj.showHiddenInSidebar or false,
            showAllDungeons     = dj.showAllDungeons or false,
        }
        -- Migrate legacy global hidden settings on first load if present
        if dj.hiddenDungeons and next(dj.hiddenDungeons) then
            for k, v in pairs(dj.hiddenDungeons) do
                dj.charHidden[charKey].hiddenDungeons[k] = v
            end
        end
        if dj.hiddenPins and next(dj.hiddenPins) then
            for k, v in pairs(dj.hiddenPins) do
                dj.charHidden[charKey].hiddenPins[k] = v
            end
        end
        if dj.hiddenQuestPins and next(dj.hiddenQuestPins) then
            for k, v in pairs(dj.hiddenQuestPins) do
                dj.charHidden[charKey].hiddenQuestPins[k] = v
            end
        end
        -- Clear legacy global tables so they don't persist or leak to other characters
        dj.hiddenDungeons = nil
        dj.hiddenPins = nil
        dj.hiddenQuestPins = nil
    end

    local data = dj.charHidden[charKey]
    data.hiddenDungeons = data.hiddenDungeons or {}
    data.hiddenPins = data.hiddenPins or {}
    data.hiddenQuestPins = data.hiddenQuestPins or {}
    cachedCharHidden = data
    cachedCharKey = charKey
    return data
end
sfui.dungeonjournal.GetCharHidden = GetCharHidden

local function DJ_DB()
    ResetDBCacheIfNeeded()
    if cachedDJDB then
        return cachedDJDB
    end

    SfuiDB = SfuiDB or {}
    lastSfuiDBRef = SfuiDB
    SfuiDB.dungeonjournal = SfuiDB.dungeonjournal or {}
    local dj = SfuiDB.dungeonjournal
    dj.wishlist = dj.wishlist or {}
    if not syncedWishlistUnion then
        syncedWishlistUnion = true
        if type(dj.charWishlist) == "table" then
            for _, charMap in pairs(dj.charWishlist) do
                if type(charMap) == "table" then
                    for id, flag in pairs(charMap) do
                        if flag == true then
                            dj.wishlist[id] = true
                        end
                    end
                end
            end
        end
    end
    local charData = GetCharHidden()
    dj.hiddenDungeons = charData.hiddenDungeons
    dj.hiddenPins = charData.hiddenPins
    dj.hiddenQuestPins = charData.hiddenQuestPins
    if charData.showHiddenInSidebar ~= nil then
        dj.showHiddenInSidebar = charData.showHiddenInSidebar
    end
    if charData.showAllDungeons ~= nil then
        dj.showAllDungeons = charData.showAllDungeons
    end
    cachedDJDB = dj
    return dj
end
sfui.dungeonjournal.GetDB = DJ_DB
sfui.dungeonjournal.DB    = DJ_DB

-- per-character options mirrored into charHidden so alts keep independent filters
local CHAR_SCOPED_OPTIONS = { showHiddenInSidebar = true, showAllDungeons = true }

local function PersistCharOption(key, val)
    DJ_DB()[key] = val
    if CHAR_SCOPED_OPTIONS[key] then
        GetCharHidden()[key] = val
    end
end

function sfui.dungeonjournal.IsWishlisted(itemID)
    if not itemID then return false end
    local id = tonumber(itemID)
    if not id then return false end
    local db = DJ_DB()
    return db.wishlist ~= nil and db.wishlist[id] == true
end

function sfui.dungeonjournal.GetWishlistCharacters(itemID)
    if not itemID then return nil end
    local id = tonumber(itemID)
    if not id then return nil end
    local db = DJ_DB()
    local names = nil
    local seen = {}
    local myGUID = _G.UnitGUID and _G.UnitGUID("player")
    if type(db.charWishlist) == "table" then
        for guid, charMap in pairs(db.charWishlist) do
            if type(charMap) == "table" and charMap[id] == true then
                local alt = SfuiDB and SfuiDB.alts and SfuiDB.alts[guid]
                local sameRuleset = (guid == myGUID) or not alt or not (sfui.alts and sfui.alts.IsSameRuleset) or sfui.alts.IsSameRuleset(alt, guid)
                local rawName = sameRuleset and ((alt and alt.name) or (guid == myGUID and (_G.UnitName and _G.UnitName("player")))) or nil
                if rawName and rawName ~= "" then
                    local clean = (rawName:match("^([^%-]+)") or rawName):lower()
                    if not seen[clean] then
                        seen[clean] = true
                        local classToken = (alt and alt.class) or (guid == myGUID and select(2, _G.UnitClass("player")))
                        local cTbl = classToken and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classToken]
                        if cTbl then
                            local rgbHex = (sfui.colors and sfui.colors.rgb_to_hex) and sfui.colors.rgb_to_hex(cTbl.r, cTbl.g, cTbl.b)
                                or string.format("%02x%02x%02x", math.floor((cTbl.r or 1) * 255), math.floor((cTbl.g or 1) * 255), math.floor((cTbl.b or 1) * 255))
                            local hex = cTbl.colorStr or ("ff" .. rgbHex)
                            clean = "|c" .. hex .. clean .. "|r"
                        end
                        names = names or {}
                        names[#names + 1] = clean
                    end
                end
            end
        end
    end
    return names
end

function sfui.dungeonjournal.ToggleWishlist(itemID)
    if not itemID then return false end
    local id = tonumber(itemID)
    if not id then return false end
    local db = DJ_DB()
    db.wishlist = db.wishlist or {}
    db.charWishlist = db.charWishlist or {}
    db.charWishlistRev = db.charWishlistRev or {}
    local myGUID = _G.UnitGUID and _G.UnitGUID("player")
    local newState
    if myGUID then
        db.charWishlist[myGUID] = db.charWishlist[myGUID] or {}
        if db.charWishlist[myGUID][id] ~= nil then
            newState = not db.charWishlist[myGUID][id]
        else
            newState = not db.wishlist[id]
        end
        if newState then
            db.charWishlist[myGUID][id] = true
        else
            db.charWishlist[myGUID][id] = nil
        end
        db.charWishlistRev[myGUID] = (_G.time and _G.time()) or 1
    else
        newState = not db.wishlist[id]
    end
    if newState then
        db.wishlist[id] = true
    else
        local stillWanted = false
        for _, charMap in pairs(db.charWishlist) do
            if type(charMap) == "table" and charMap[id] == true then
                stillWanted = true
                break
            end
        end
        db.wishlist[id] = stillWanted and true or nil
    end
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_DJ_WISHLIST_UPDATED", id, newState)
    end
    if sfui.print then
        local _, link = common.get_item_info(id)
        local name = link or ("item #" .. id)
        if newState then
            sfui.print("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:14:14:0:0|t |cffcc44ffwishlist added:|r " .. name)
        else
            sfui.print("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:14:14:0:0|t |cff888888wishlist removed:|r " .. name)
        end
    end
    return newState
end

function sfui.dungeonjournal.GetWishlist()
    local db = DJ_DB()
    return db.wishlist or {}
end

function sfui.dungeonjournal.AddWishlistItem(itemID, silent, deferBroadcast)
    local id = tonumber(itemID)
    if not id then return false end
    local db = DJ_DB()
    db.wishlist = db.wishlist or {}
    db.charWishlist = db.charWishlist or {}
    db.charWishlistRev = db.charWishlistRev or {}
    local myGUID = _G.UnitGUID and _G.UnitGUID("player")
    if myGUID then
        db.charWishlist[myGUID] = db.charWishlist[myGUID] or {}
        if db.charWishlist[myGUID][id] == true then
            db.wishlist[id] = true
            return false
        end
        db.charWishlist[myGUID][id] = true
        db.charWishlistRev[myGUID] = (_G.time and _G.time()) or 1
    elseif db.wishlist[id] == true then
        return false
    end
    db.wishlist[id] = true
    if not deferBroadcast and sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_DJ_WISHLIST_UPDATED", id, true)
    end
    if not silent and sfui.print then
        local _, link = common.get_item_info(id)
        sfui.print("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:14:14:0:0|t |cffcc44ffwishlist added:|r " .. (link or ("item #" .. id)))
    end
    return true
end

function sfui.dungeonjournal.AddWishlistItemsBatch(itemIDs, silent)
    if type(itemIDs) ~= "table" or #itemIDs == 0 then return 0 end
    local db = DJ_DB()
    db.wishlist = db.wishlist or {}
    db.charWishlist = db.charWishlist or {}
    db.charWishlistRev = db.charWishlistRev or {}
    local myGUID = _G.UnitGUID and _G.UnitGUID("player")
    local myMap = nil
    if myGUID then
        db.charWishlist[myGUID] = db.charWishlist[myGUID] or {}
        myMap = db.charWishlist[myGUID]
    end
    local added = 0
    local lastAddedID = nil
    for i = 1, #itemIDs do
        local id = tonumber(itemIDs[i])
        if id then
            if myMap then
                if myMap[id] ~= true then
                    myMap[id] = true
                    db.wishlist[id] = true
                    added = added + 1
                    lastAddedID = id
                else
                    db.wishlist[id] = true
                end
            elseif db.wishlist[id] ~= true then
                db.wishlist[id] = true
                added = added + 1
                lastAddedID = id
            end
        end
    end
    if added > 0 then
        if myGUID then
            db.charWishlistRev[myGUID] = (_G.time and _G.time()) or 1
        end
        if sfui.events and sfui.events.SendMessage then
            sfui.events.SendMessage("SFUI_DJ_WISHLIST_UPDATED", lastAddedID, true)
        end
        if not silent and sfui.print then
            sfui.print(string_format("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:14:14:0:0|t |cffcc44ffadded %d items to wishlist.|r", added))
        end
    end
    return added
end

function sfui.dungeonjournal.FulfillWishlistItem(itemID)
    local id = tonumber(itemID)
    if not id then return false end
    local db = DJ_DB()
    local myGUID = _G.UnitGUID and _G.UnitGUID("player")
    if not myGUID or type(db.charWishlist) ~= "table" or not db.charWishlist[myGUID] or not db.charWishlist[myGUID][id] then
        return false
    end
    db.charWishlist[myGUID][id] = nil
    db.charWishlistRev = db.charWishlistRev or {}
    db.charWishlistRev[myGUID] = (_G.time and _G.time()) or 1
    local stillWanted = false
    for _, charMap in pairs(db.charWishlist) do
        if type(charMap) == "table" and charMap[id] == true then
            stillWanted = true
            break
        end
    end
    if db.wishlist then
        db.wishlist[id] = stillWanted and true or nil
    end
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_DJ_WISHLIST_UPDATED", id, false)
    end
    if sfui.print then
        local _, link = common.get_item_info(id)
        sfui.print("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:14:14:0:0|t |cff33ff88wishlist fulfilled:|r " .. (link or ("item #" .. id)))
    end
    return true
end

-- ─── Data access ─────────────────────────────────────────────────────────────
local function GetData()
    return sfui.dj_camelot
        or (sfui.data and sfui.data.dj_camelot)
        or {}
end
sfui.dungeonjournal.GetData = GetData

local function GetList()
    local db = GetData()
    if selectedTab == "raids" then
        return db.raids or {}
    end
    return db.dungeons or {}
end
sfui.dungeonjournal.GetList = GetList

local function EnsureDungeonLookup()
    local db = GetData()
    if cachedDataRef == db and dungeonByID then return end
    cachedDataRef = db
    dungeonByID = {}
    dungeonTabByID = {}
    for _, d in ipairs(db.dungeons or {}) do
        if d.id then
            dungeonByID[d.id] = d
            dungeonTabByID[d.id] = "dungeons"
        end
    end
    for _, r in ipairs(db.raids or {}) do
        if r.id then
            dungeonByID[r.id] = r
            dungeonTabByID[r.id] = "raids"
        end
    end
end

local function FindDungeon(id)
    if not id then return nil, nil end
    EnsureDungeonLookup()
    return dungeonByID[id], dungeonTabByID[id]
end
sfui.dungeonjournal.FindDungeon = FindDungeon

local function GetCurrentDungeon()
    if selectedDungeonID then
        local d = FindDungeon(selectedDungeonID)
        if d then return d end
    end
    local list = GetList()
    if list and #list > 0 then
        return list[1]
    end
    return nil
end
sfui.dungeonjournal.GetCurrentDungeon = GetCurrentDungeon

-- ─── Item & Quality Helpers ───────────────────────────────────────────────────
local function GetItemInfo(itemID)
    return common.get_item_info(itemID)
end

local function GetItemQuality(itemID)
    return common.get_item_quality(itemID) or 3
end

local function GetQualityColor(quality)
    if common and common.get_item_quality_color then
        local r, g, b = common.get_item_quality_color(quality)
        return r, g, b
    end
    local q = quality or 1
    if _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[q] then
        local c = _G.ITEM_QUALITY_COLORS[q]
        return c.r, c.g, c.b
    end
    if _G.GetItemQualityColor then
        local r, g, b = _G.GetItemQualityColor(q)
        if r then return r, g, b end
    end
    return 0.8, 0.8, 0.8
end
sfui.dungeonjournal.GetQualityColor = GetQualityColor

local function InsertItemLinkIntoChat(link)
    return sfui.common.insert_link_to_chat(link)
end
sfui.dungeonjournal.InsertItemLinkIntoChat = InsertItemLinkIntoChat

local function ResolveItemLink(btn, fallbackItemID)
    local itemID = (btn and btn.itemID) or fallbackItemID
    local itemLink = btn and btn.link

    if not (itemLink and type(itemLink) == "string" and itemLink:find("|Hitem:")) and itemID then
        local _, l = common.get_item_info(itemID)
        itemLink = l
        if itemLink and btn then
            btn.link = itemLink
        end
    end

    if not (itemLink and type(itemLink) == "string" and itemLink:find("|Hitem:")) and itemID then
        local rawName = (btn and btn.nameText and btn.nameText.GetText and btn.nameText:GetText()) or ("item #" .. itemID)
        local cleanName = sfui.common.strip_colors(rawName)
        local quality = common.get_item_quality(itemID) or 1
        local r, g, b = GetQualityColor(quality)
        local hex = "ff" .. sfui.colors.rgb_to_hex(r, g, b)
        itemLink = string_format("|c%s|Hitem:%d:0:0:0:0:0:0:0:0:0:0:0:0|h[%s]|h|r", hex, itemID, cleanName)
        if btn then
            btn.link = itemLink
        end
    end

    return itemLink
end
sfui.dungeonjournal.ResolveItemLink = ResolveItemLink

local function HandleItemClick(btn, mouseBtn, itemID)
    if mouseBtn == "LeftButton" then
        local isChatLink = (_G.IsModifiedClick and _G.IsModifiedClick("CHATLINK"))
            or (_G.IsShiftKeyDown and _G.IsShiftKeyDown())
        local isDressUp  = (_G.IsModifiedClick and _G.IsModifiedClick("DRESSUP"))
            or (_G.IsControlKeyDown and _G.IsControlKeyDown())

        if isChatLink or isDressUp then
            local itemLink = ResolveItemLink(btn, itemID)
            if not itemLink then return end

            if isChatLink then
                InsertItemLinkIntoChat(itemLink)
            elseif isDressUp then
                local targetID = (btn and btn.itemID) or itemID or itemLink
                if sfui.nav and sfui.nav.OpenRecipeOrFishing and sfui.nav.OpenRecipeOrFishing(itemLink or targetID) then
                    return
                end
                if not (_G.HandleModifiedItemClick and _G.HandleModifiedItemClick(itemLink)) then
                    if _G.DressUpItemLink then
                        _G.DressUpItemLink(itemLink)
                    elseif _G.DressUpLink then
                        _G.DressUpLink(itemLink)
                    end
                end
            end
        end
    end
end
sfui.dungeonjournal.HandleItemClick = HandleItemClick

local function IsQuestCompleted(questID)
    if not questID then return false end
    local qs = sfui.queststate
    if qs and qs.IsCompleted then
        return qs.IsCompleted(questID) == true
    end
    return sfui.common.is_quest_completed(questID) == true
end
sfui.dungeonjournal.IsQuestCompleted = IsQuestCompleted
sfui.dungeonjournal.IsQuestDone      = IsQuestCompleted

local function IsQuestActive(questID)
    if not questID then return false end
    local qs = sfui.queststate
    if qs and qs.IsActive then
        return qs.IsActive(questID) == true
    end
    if sfui.pins and sfui.pins.IsQuestActive then
        return sfui.pins.IsQuestActive(questID)
    end
    if _G.C_QuestLog and _G.C_QuestLog.IsOnQuest then
        local on = _G.C_QuestLog.IsOnQuest(questID)
        if on then return true end
    end
    if _G.C_QuestLog and _G.C_QuestLog.GetLogIndexForQuestID then
        local idx = _G.C_QuestLog.GetLogIndexForQuestID(questID)
        if type(idx) == "number" and idx > 0 then return true end
    end
    if _G.GetQuestLogIndexByID then
        local idx = _G.GetQuestLogIndexByID(questID)
        if type(idx) == "number" and idx > 0 then return true end
    end
    return false
end
sfui.dungeonjournal.IsQuestActive = IsQuestActive
sfui.dungeonjournal.IsQuestInLog  = IsQuestActive

local function ReleaseAll(pool)
    if not pool then return end
    for _, btn in ipairs(pool) do
        btn:Hide()
    end
end
sfui.dungeonjournal.ReleaseAll = ReleaseAll

local function GetPlayerFaction()
    local _, faction = sfui.common.get_player_faction()
    return faction == "horde" and "horde" or "alliance"
end
sfui.dungeonjournal.GetPlayerFaction = GetPlayerFaction

local cachedPlayerClass = nil
local cachedPlayerRace  = nil

local function GetCachedPlayerClass()
    if cachedPlayerClass then return cachedPlayerClass end
    local playerClass = nil
    if _G.UnitClassBase then
        local c = _G.UnitClassBase("player")
        if c and not (_G.issecretvalue and _G.issecretvalue(c)) and type(c) == "string" then
            playerClass = c
        end
    end
    if not playerClass and _G.UnitClass then
        local _, c = _G.UnitClass("player")
        if c and not (_G.issecretvalue and _G.issecretvalue(c)) and type(c) == "string" then
            playerClass = c
        end
    end
    if playerClass and playerClass ~= "" then
        cachedPlayerClass = playerClass:upper()
    end
    return cachedPlayerClass
end

local function GetCachedPlayerRace()
    if cachedPlayerRace then return cachedPlayerRace end
    if _G.UnitRace then
        local raceName, raceFile = _G.UnitRace("player")
        local pRace = nil
        if raceFile and not (_G.issecretvalue and _G.issecretvalue(raceFile)) and type(raceFile) == "string" then
            pRace = raceFile:lower()
        elseif raceName and not (_G.issecretvalue and _G.issecretvalue(raceName)) and type(raceName) == "string" then
            pRace = raceName:lower()
        end
        if pRace and pRace ~= "" then
            cachedPlayerRace = pRace
        end
    end
    return cachedPlayerRace
end

local function IsQuestClassRaceEligible(quest)
    if not quest then return true end

    local classReq = quest.classOnly or quest.class or quest.classes
    if classReq then
        local pClass = GetCachedPlayerClass()
        if pClass then
            if type(classReq) == "string" then
                if classReq:upper() ~= pClass then return false end
            elseif type(classReq) == "table" then
                local matched = false
                for _, token in ipairs(classReq) do
                    if type(token) == "string" and token:upper() == pClass then
                        matched = true
                        break
                    end
                end
                if not matched then return false end
            end
        end
    end

    local raceReq = quest.races or quest.race
    if raceReq then
        local pRace = GetCachedPlayerRace()
        if pRace then
            local isUndead = (pRace == "scourge" or pRace == "undead")
            if type(raceReq) == "string" then
                local r = raceReq:lower()
                local rUndead = (r == "scourge" or r == "undead")
                if r ~= pRace and not (isUndead and rUndead) then return false end
            elseif type(raceReq) == "table" then
                local matched = false
                for _, token in ipairs(raceReq) do
                    if type(token) == "string" then
                        local r = token:lower()
                        local rUndead = (r == "scourge" or r == "undead")
                        if r == pRace or (isUndead and rUndead) then
                            matched = true
                            break
                        end
                    end
                end
                if not matched then return false end
            end
        end
    end

    return true
end
sfui.dungeonjournal.IsQuestClassRaceEligible = IsQuestClassRaceEligible

function sfui.dungeonjournal.GetQuestChainInfo(quest)
    if not quest then return nil end
    local steps = quest._cachedChainSteps
    if steps == false then return nil end
    if not steps then
        local rawChain = quest.chain
        if not rawChain and quest.chainStart then
            rawChain = { quest.chainStart }
        end
        if not rawChain or #rawChain == 0 then
            quest._cachedChainSteps = false
            return nil
        end

        steps = {}
        local questCoordsDB = sfui.dj_camelot and sfui.dj_camelot.questCoords
        for _, s in ipairs(rawChain) do
            local inDung = (s.pickedUpInDungeon == true or s.inDungeon == true)
            local coords = (not inDung) and (
                s.coords
                or (questCoordsDB and s.id and questCoordsDB[s.id])
            ) or nil
            steps[#steps + 1] = {
                id = s.id,
                name = s.name,
                pickup = s.pickup,
                coords = coords,
                entranceCoords = s.entranceCoords,
                level = s.level,
                minLevel = s.minLevel,
                faction = s.faction,
                objective = s.objective,
                pickedUpInDungeon = inDung or (s.id == quest.id and quest.pickedUpInDungeon == true) or nil,
                acceptOnly = s.acceptOnly or nil,
                classOnly = s.classOnly or nil,
                races = s.races or nil,
                isDungeonQuest = s.isDungeonQuest or (s.id == quest.id),
            }
        end
        if steps[#steps].id ~= quest.id then
            local qInDung = (quest.pickedUpInDungeon == true or quest.inDungeon == true)
            local qCoords = (not qInDung) and (
                (questCoordsDB and quest.id and questCoordsDB[quest.id])
                or quest.coords
            ) or nil
            steps[#steps + 1] = {
                id = quest.id,
                name = quest.name,
                pickup = quest.pickup,
                coords = qCoords,
                entranceCoords = quest.entranceCoords,
                level = quest.level,
                minLevel = quest.minLevel,
                faction = quest.faction,
                objective = quest.objective,
                pickedUpInDungeon = qInDung or nil,
                classOnly = quest.classOnly or nil,
                races = quest.races or nil,
                isDungeonQuest = true,
            }
        end
        quest._cachedChainSteps = steps
    end

    local currentStep = nil
    local currentStepIndex = nil

    for i, s in ipairs(steps) do
        local isDone = s.id and (
            sfui.dungeonjournal.IsQuestCompleted(s.id)
            or (s.acceptOnly and sfui.dungeonjournal.IsQuestActive(s.id))
        )
        if not isDone then
            currentStep = s
            currentStepIndex = i
            break
        end
    end

    local allDone = (currentStep == nil)
    return steps, currentStep, currentStepIndex, allDone
end

-- ─── Forwarded submodule functions (set by dj_sidebar, dj_bosses, dj_quests) ─
local RefreshSidebar   = nil
local RefreshBossView  = nil
local RefreshQuestView = nil

function sfui.dungeonjournal._registerSidebar(fn)
    RefreshSidebar = fn
    sfui.dungeonjournal.RefreshSidebar = fn
end

function sfui.dungeonjournal._registerBosses(fn) RefreshBossView = fn end

function sfui.dungeonjournal._registerQuests(fn) RefreshQuestView = fn end

-- ─── Level Range Filter Helper ───────────────────────────────────────────────
function sfui.dungeonjournal.IsDungeonInLevelRange(dungeon, playerLevel)
    if not dungeon then return false end
    local pLvl = playerLevel or (UnitLevel and UnitLevel("player")) or 1
    local minLvl = dungeon.minLevel
    local maxLvl = dungeon.maxLevel
    if not minLvl or not maxLvl then
        if dungeon.level then
            local low, high = tostring(dungeon.level):match("^(%d+)%s*-%s*(%d+)$")
            if low and high then
                minLvl = minLvl or tonumber(low)
                maxLvl = maxLvl or tonumber(high)
            else
                local single = tonumber(dungeon.level)
                if single then
                    minLvl = minLvl or single
                    maxLvl = maxLvl or single
                end
            end
        end
    end
    minLvl = minLvl or 1
    maxLvl = maxLvl or 60
    return pLvl >= minLvl and pLvl <= maxLvl
end

-- ─── Hiding System API ────────────────────────────────────────────────────────
function sfui.dungeonjournal.IsDungeonHidden(dungeonID)
    if not dungeonID then return false end
    local charData = GetCharHidden()
    return charData.hiddenDungeons and charData.hiddenDungeons[dungeonID] == true
end

function sfui.dungeonjournal.AreDungeonPinsHidden(dungeonID)
    if not dungeonID then return false end
    local charData = GetCharHidden()
    if charData.hiddenDungeons and charData.hiddenDungeons[dungeonID] == true then return true end
    if charData.hiddenPins and charData.hiddenPins[dungeonID] == true then return true end
    return false
end

function sfui.dungeonjournal.IsQuestPinHidden(questID, dungeonID)
    if not questID then return false end
    local charData = GetCharHidden()
    if charData.hiddenQuestPins and charData.hiddenQuestPins[questID] == true then return true end
    if dungeonID and sfui.dungeonjournal.AreDungeonPinsHidden(dungeonID) then return true end
    return false
end

function sfui.dungeonjournal.SetDungeonHidden(dungeonID, hidden)
    if not dungeonID then return end
    local charData = GetCharHidden()
    if hidden then
        charData.hiddenDungeons[dungeonID] = true
    else
        charData.hiddenDungeons[dungeonID] = nil
    end
    if RefreshSidebar then RefreshSidebar() end
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_DJ_SETTING_CHANGED", "hiddenDungeons", dungeonID)
    elseif sfui.dungeonjournal.UpdatePins then
        sfui.dungeonjournal.UpdatePins(true)
    end
end

function sfui.dungeonjournal.SetDungeonPinsHidden(dungeonID, hidden)
    if not dungeonID then return end
    local charData = GetCharHidden()
    if hidden then
        charData.hiddenPins[dungeonID] = true
    else
        charData.hiddenPins[dungeonID] = nil
    end
    if RefreshSidebar then RefreshSidebar() end
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_DJ_SETTING_CHANGED", "hiddenPins", dungeonID)
    elseif sfui.dungeonjournal.UpdatePins then
        sfui.dungeonjournal.UpdatePins(true)
    end
end

function sfui.dungeonjournal.SetQuestPinHidden(questID, hidden)
    if not questID then return end
    local charData = GetCharHidden()
    if hidden then
        charData.hiddenQuestPins[questID] = true
    else
        charData.hiddenQuestPins[questID] = nil
    end
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_DJ_SETTING_CHANGED", "hiddenQuestPins", questID)
    elseif sfui.dungeonjournal.UpdatePins then
        sfui.dungeonjournal.UpdatePins(true)
    end
end

function sfui.dungeonjournal.GetHiddenCounts()
    local charData = GetCharHidden()
    local dCount = 0
    for _ in pairs(charData.hiddenDungeons or {}) do dCount = dCount + 1 end
    local pCount = 0
    for _ in pairs(charData.hiddenPins or {}) do pCount = pCount + 1 end
    local qCount = 0
    for _ in pairs(charData.hiddenQuestPins or {}) do qCount = qCount + 1 end
    return dCount, pCount, qCount, (dCount + pCount + qCount)
end

function sfui.dungeonjournal.RestoreAllHidden()
    local charData = GetCharHidden()
    local _, _, _, total = sfui.dungeonjournal.GetHiddenCounts()
    charData.hiddenDungeons = {}
    charData.hiddenPins = {}
    charData.hiddenQuestPins = {}
    if SfuiDB and SfuiDB.dungeonjournal then
        SfuiDB.dungeonjournal.hiddenDungeons = charData.hiddenDungeons
        SfuiDB.dungeonjournal.hiddenPins = charData.hiddenPins
        SfuiDB.dungeonjournal.hiddenQuestPins = charData.hiddenQuestPins
    end
    if RefreshSidebar then RefreshSidebar() end
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_DJ_SETTING_CHANGED", "restoreAll", total)
    elseif sfui.dungeonjournal.UpdatePins then
        sfui.dungeonjournal.UpdatePins(true)
    end
    if sfui.print and total > 0 then
        sfui.print(string_format("restored %d hidden item%s (dungeons and map pins).", total, (total > 1 and "s" or "")))
    end
end

sfui.dungeonjournal.RestoreHiddenDungeons = sfui.dungeonjournal.RestoreAllHidden

function sfui.dungeonjournal.IsDungeonTrivial(dungeon, playerLevel)
    if not dungeon then return false end
    local pLvl = playerLevel or (UnitLevel and UnitLevel("player")) or 1
    local maxLvl = dungeon.maxLevel
    if not maxLvl and dungeon.level then
        local _, high = tostring(dungeon.level):match("^(%d+)%s*-%s*(%d+)$")
        if high then
            maxLvl = tonumber(high)
        else
            maxLvl = tonumber(dungeon.level)
        end
    end
    if not maxLvl then return false end
    local grayDiff
    if pLvl <= 5 then
        grayDiff = 0
    elseif pLvl <= 39 then
        grayDiff = 5 + math_floor(pLvl / 10)
    elseif pLvl <= 59 then
        grayDiff = 1 + math_floor(pLvl / 5)
    else
        grayDiff = 9
    end
    return (pLvl - maxLvl) > grayDiff
end

-- ─── Chat Undo Hyperlink Hook ─────────────────────────────────────────────────
if _G.hooksecurefunc then
    pcall(_G.hooksecurefunc, "SetItemRef", function(link, text, button, chatFrame)
        if not link or type(link) ~= "string" then return end
        if link:sub(1, 10) == "sfui_undo:" then
            local tag, kind, idStr = strsplit(":", link)
            if tag ~= "sfui_undo" or not kind or not idStr then return end

            if kind == "dungeon" then
                sfui.dungeonjournal.SetDungeonHidden(idStr, false)
                local d = sfui.dungeonjournal.FindDungeon(idStr)
                if sfui.print then
                    sfui.print(string_format("restored |cffffd100%s|r to adventure guide and map.", d and d.name or idStr))
                end
            elseif kind == "pins" then
                sfui.dungeonjournal.SetDungeonPinsHidden(idStr, false)
                local d = sfui.dungeonjournal.FindDungeon(idStr)
                if sfui.print then
                    sfui.print(string_format("restored map pins for |cffffd100%s|r.", d and d.name or idStr))
                end
            elseif kind == "quest" then
                local qid = tonumber(idStr) or idStr
                sfui.dungeonjournal.SetQuestPinHidden(qid, false)
                if sfui.print then
                    sfui.print(string_format("restored quest pin |cffffd100#%s|r to map.", tostring(qid)))
                end
            end
        end
    end)
end

-- ─── Shared Context Menu Helper ───────────────────────────────────────────────
local sharedContextMenu = nil

function sfui.dungeonjournal.ShowContextMenu(owner, title, items)
    if not items or #items == 0 then return end

    if MenuUtil and MenuUtil.CreateContextMenu then
        local ok = pcall(function()
            MenuUtil.CreateContextMenu(owner, function(ownerFrame, rootDescription)
                rootDescription:SetTag("MENU_SFUI_DJ")
                if title then
                    rootDescription:CreateTitle(title)
                end
                for _, it in ipairs(items) do
                    if it.isDivider then
                        rootDescription:CreateDivider()
                    else
                        rootDescription:CreateButton(it.text, function()
                            if it.func then it.func() end
                        end)
                    end
                end
            end)
        end)
        if ok then return end
    end

    if not sharedContextMenu then
        local f = CreateFrame("Frame", "SFUI_DJ_ContextMenu", UIParent, "BackdropTemplate")
        sharedContextMenu = f
        f:SetFrameStrata("TOOLTIP")
        f:SetFrameLevel(100)
        f:SetClampedToScreen(true)
        common.apply_flat_backdrop(f, { 0.08, 0.08, 0.11, 0.98 }, { 1, 0.78, 0.2, 0.8 })

        local t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.title = t
        t:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
        t:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -8)
        t:SetJustifyH("LEFT")
        t:SetTextColor(1, 0.82, 0, 1)

        f.menuButtons = {}

        local dismiss = CreateFrame("Button", nil, UIParent)
        dismiss:SetFrameStrata("TOOLTIP")
        dismiss:SetFrameLevel(f:GetFrameLevel() - 1)
        dismiss:SetAllPoints()
        dismiss:SetScript("OnClick", function()
            f:Hide()
            dismiss:Hide()
        end)
        dismiss:Hide()
        f.dismiss = dismiss

        f:SetScript("OnHide", function()
            dismiss:Hide()
        end)
    end

    local f = sharedContextMenu
    f.title:SetText(title or "options")

    local itemY = 26
    local btnW = 220
    local btnH = 22

    for idx, it in ipairs(items) do
        local btn = f.menuButtons[idx]
        if not btn then
            btn = CreateFrame("Button", nil, f)
            btn:SetHeight(btnH)
            local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.text = fs
            fs:SetPoint("LEFT", btn, "LEFT", 10, 0)
            fs:SetPoint("RIGHT", btn, "RIGHT", -10, 0)
            fs:SetJustifyH("LEFT")

            local hi = btn:CreateTexture(nil, "HIGHLIGHT")
            hi:SetAllPoints()
            hi:SetColorTexture(1, 1, 1, 0.12)

            f.menuButtons[idx] = btn
        end

        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -itemY)
        btn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -itemY)
        btn.text:SetText(it.text)
        if it.color then
            btn.text:SetTextColor(it.color[1], it.color[2], it.color[3], 1)
        else
            btn.text:SetTextColor(0.9, 0.9, 0.9, 1)
        end

        btn:SetScript("OnClick", function()
            f:Hide()
            if f.dismiss then f.dismiss:Hide() end
            if it.func then it.func() end
        end)

        btn:Show()
        itemY = itemY + btnH + 2
    end

    for i = #items + 1, #f.menuButtons do
        f.menuButtons[i]:Hide()
    end

    f:SetSize(btnW, itemY + 8)

    local cursorX, cursorY = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale() or 1
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (cursorX / scale) + 2, (cursorY / scale) + 2)

    if f.dismiss then f.dismiss:Show() end
    f:Show()
end

-- ─── Centralized Hidden Manager Frame ─────────────────────────────────────────
local hiddenManagerFrame = nil

local function OpenHiddenManager()
    if not hiddenManagerFrame then
        local dlg = CreateFrame("Frame", "SFUI_DJ_HiddenManager", frame or UIParent, "BackdropTemplate")
        hiddenManagerFrame = dlg
        dlg:SetFrameStrata("DIALOG")
        dlg:SetFrameLevel((frame and frame:GetFrameLevel() or 50) + 30)
        dlg:SetSize(360, 420)
        if frame then
            dlg:SetPoint("CENTER", frame, "CENTER", 0, 0)
        else
            dlg:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        dlg:SetMovable(true)
        dlg:EnableMouse(true)
        dlg:RegisterForDrag("LeftButton")
        dlg:SetScript("OnDragStart", dlg.StartMoving)
        dlg:SetScript("OnDragStop", dlg.StopMovingOrSizing)

        common.apply_flat_backdrop(dlg, { 0.06, 0.06, 0.08, 0.98 }, { 1, 0.78, 0.2, 0.8 })

        local title = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", dlg, "TOPLEFT", 14, -12)
        title:SetText("hidden dungeons & pins")
        title:SetTextColor(1, 0.82, 0, 1)

        local closeBtn = CreateFrame("Button", nil, dlg, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", dlg, "TOPRIGHT", -4, -4)
        closeBtn:SetScript("OnClick", function() dlg:Hide() end)

        local sub = dlg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        sub:SetText("manage hidden dungeons, entrance pins, and quest pins.")
        sub:SetTextColor(0.65, 0.65, 0.65, 1)

        local scroll = CreateFrame("ScrollFrame", nil, dlg, "UIPanelScrollFrameTemplate")
        dlg.scroll = scroll
        scroll:SetPoint("TOPLEFT", dlg, "TOPLEFT", 12, -48)
        scroll:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -30, 44)

        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(318, 1)
        scroll:SetScrollChild(content)
        dlg.content = content

        dlg.rows = {}

        local restoreBtn = CreateFrame("Button", nil, dlg, "BackdropTemplate")
        dlg.restoreBtn = restoreBtn
        restoreBtn:SetSize(130, 24)
        restoreBtn:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 12, 10)
        common.apply_flat_backdrop(restoreBtn, { 0.12, 0.12, 0.16, 0.95 }, { 0.24, 0.24, 0.28, 1 })
        local rText = restoreBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        rText:SetPoint("CENTER")
        rText:SetText("restore all")
        rText:SetTextColor(0.4, 1.0, 0.4, 1)
        restoreBtn:SetScript("OnClick", function()
            sfui.dungeonjournal.RestoreAllHidden()
            dlg.Refresh()
        end)

        local bClose = CreateFrame("Button", nil, dlg, "BackdropTemplate")
        bClose:SetSize(80, 24)
        bClose:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -12, 10)
        common.apply_flat_backdrop(bClose, { 0.12, 0.12, 0.16, 0.95 }, { 0.24, 0.24, 0.28, 1 })
        local cText = bClose:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cText:SetPoint("CENTER")
        cText:SetText("close")
        bClose:SetScript("OnClick", function() dlg:Hide() end)

        local emptyMsg = dlg:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        dlg.emptyMsg = emptyMsg
        emptyMsg:SetPoint("CENTER", scroll, "CENTER", 0, 0)
        emptyMsg:SetText("no dungeons or pins are currently hidden.")

        local function RefreshDialog()
            local charData = GetCharHidden()
            for _, r in ipairs(dlg.rows) do r:Hide() end

            local y = 0
            local rowIndex = 0

            local function AddHeader(text)
                rowIndex = rowIndex + 1
                local row = dlg.rows[rowIndex]
                if not row then
                    row = CreateFrame("Frame", nil, content)
                    row:SetSize(318, 20)
                    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    row.label = fs
                    fs:SetPoint("LEFT", row, "LEFT", 4, 0)
                    dlg.rows[rowIndex] = row
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                row.label:SetText(text)
                row.label:SetTextColor(1, 0.82, 0, 1)
                if row.actionBtn then row.actionBtn:Hide() end
                row:Show()
                y = y + 22
            end

            local function AddItemRow(labelText, subText, onUnhide)
                rowIndex = rowIndex + 1
                local row = dlg.rows[rowIndex]
                if not row then
                    row = CreateFrame("Frame", nil, content, "BackdropTemplate")
                    row:SetSize(318, 24)
                    common.apply_flat_backdrop(row, { 0.08, 0.08, 0.10, 0.6 }, { 0.2, 0.2, 0.24, 0.6 })

                    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.label = fs
                    fs:SetPoint("LEFT", row, "LEFT", 6, 0)
                    fs:SetPoint("RIGHT", row, "RIGHT", -74, 0)
                    fs:SetJustifyH("LEFT")

                    local btn = CreateFrame("Button", nil, row, "BackdropTemplate")
                    row.actionBtn = btn
                    btn:SetSize(66, 18)
                    btn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                    common.apply_flat_backdrop(btn, { 0.14, 0.14, 0.18, 0.95 }, { 0.3, 0.3, 0.35, 1 })
                    local bt = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    btn.text = bt
                    bt:SetPoint("CENTER")
                    bt:SetText("unhide")
                    bt:SetTextColor(0.4, 1.0, 0.4, 1)

                    local hi = btn:CreateTexture(nil, "HIGHLIGHT")
                    hi:SetAllPoints()
                    hi:SetColorTexture(1, 1, 1, 0.15)

                    dlg.rows[rowIndex] = row
                end

                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                local fullText = labelText
                if subText and subText ~= "" then
                    fullText = fullText .. "  |cff777777(" .. subText .. ")|r"
                end
                row.label:SetText(fullText)
                row.label:SetTextColor(0.9, 0.9, 0.9, 1)

                row.actionBtn:Show()
                row.actionBtn:SetScript("OnClick", function()
                    if onUnhide then onUnhide() end
                    RefreshDialog()
                end)

                row:Show()
                y = y + 26
            end

            local hasDungeons = false
            for dID in pairs(charData.hiddenDungeons or {}) do
                if not hasDungeons then
                    AddHeader("hidden dungeons (journal & pins):")
                    hasDungeons = true
                end
                local d = sfui.dungeonjournal.FindDungeon(dID)
                local dName = d and d.name or dID
                local dLvl = d and d.level or ""
                AddItemRow(dName, dLvl, function()
                    sfui.dungeonjournal.SetDungeonHidden(dID, false)
                end)
            end

            local hasPins = false
            for dID in pairs(charData.hiddenPins or {}) do
                if not hasPins then
                    if y > 0 then y = y + 6 end
                    AddHeader("hidden map pins (dungeon visible):")
                    hasPins = true
                end
                local d = sfui.dungeonjournal.FindDungeon(dID)
                local dName = d and d.name or dID
                AddItemRow(dName, "pins only", function()
                    sfui.dungeonjournal.SetDungeonPinsHidden(dID, false)
                end)
            end

            local hasQuestPins = false
            for qID in pairs(charData.hiddenQuestPins or {}) do
                if not hasQuestPins then
                    if y > 0 then y = y + 6 end
                    AddHeader("hidden quest pins:")
                    hasQuestPins = true
                end
                local qName = "quest #" .. tostring(qID)
                local cData = sfui.dj_camelot or (sfui.data and sfui.data.dj_camelot)
                if cData and cData.GetQuestDungeon then
                    local qData = cData.GetQuestDungeon(qID)
                    if qData and qData.quest and qData.quest.name then
                        qName = qData.quest.name
                    end
                elseif cData then
                    for _, d in ipairs(cData.dungeons or {}) do
                        for _, q in ipairs(d.quests or {}) do
                            if q.id == qID or (q.chain and q.chainStart and q.chainStart.id == qID) then
                                qName = q.name
                                break
                            end
                            if q.chain then
                                for _, step in ipairs(q.chain) do
                                    if step.id == qID then
                                        qName = step.name
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
                AddItemRow(qName, "quest pin", function()
                    sfui.dungeonjournal.SetQuestPinHidden(qID, false)
                end)
            end

            content:SetHeight(math_max(1, y))
            local total = (hasDungeons or hasPins or hasQuestPins) and y > 0
            if total then
                dlg.emptyMsg:Hide()
                dlg.restoreBtn:Enable()
                dlg.restoreBtn:SetAlpha(1.0)
            else
                dlg.emptyMsg:Show()
                dlg.restoreBtn:Disable()
                dlg.restoreBtn:SetAlpha(0.4)
            end
        end

        dlg.Refresh = RefreshDialog
        dlg:SetScript("OnShow", RefreshDialog)
    end

    hiddenManagerFrame.Refresh()
    hiddenManagerFrame:Show()
end
sfui.dungeonjournal.OpenHiddenManager = OpenHiddenManager

local function SetTabButtonTextColor(btn, color)
    if not btn or not color then return end
    local fs = btn.fs or (btn.GetFontString and btn:GetFontString())
    if fs and fs.SetTextColor then
        fs:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end
end

local function HasDungeonMap(dungeon)
    local d = dungeon or GetCurrentDungeon()
    return (d and sfui.dj_map and sfui.dj_map.HasMap and sfui.dj_map.HasMap(d)) == true
end

local function GetEffectiveMode()
    if selectedMode == "map" and not HasDungeonMap() then
        return "bosses"
    end
    return selectedMode
end

local function RefreshMapView(forcedFloor)
    if not mapPanel or not mapPanel:IsShown() then return end
    if sfui.dj_map and sfui.dj_map.Render then
        sfui.dj_map.Render(frame, GetCurrentDungeon(), forcedFloor)
    end
end

local EnsureExternalTabButtons
local EnsureExternalPanelMounted
local EnsureBossesInitialized
local EnsureQuestsInitialized

local function UpdateTabHighlights()
    if not frame then return end
    local effMode = GetEffectiveMode()
    local hasMap  = HasDungeonMap()
    if frame.mapTab then
        frame.mapTab:SetAlpha(hasMap and 1.0 or 0.35)
        if hasMap then
            frame.mapTab:Enable()
        else
            frame.mapTab:Disable()
        end
    end
    if theme.ApplyTabStyle then
        theme.ApplyTabStyle(frame.dungeonTabBtn, selectedTab == "dungeons")
        theme.ApplyTabStyle(frame.raidTabBtn, selectedTab == "raids")
        for _, key in ipairs(EXTERNAL_TAB_ORDER) do
            local btn = frame[EXTERNAL_TAB_DEFS[key].btnField]
            if btn then
                theme.ApplyTabStyle(btn, selectedTab == key)
            end
        end
        if frame.mapTab then
            theme.ApplyTabStyle(frame.mapTab, effMode == "map")
        end
        theme.ApplyTabStyle(frame.bossesTab, effMode == "bosses")
        theme.ApplyTabStyle(frame.questsTab, effMode == "quests")
    else
        local pal    = theme.GetPalette()
        local accent = pal and pal.accentColor or { 1, 0.78, 0.2, 1 }
        local dim    = pal and pal.tabNormal or { 0.6, 0.6, 0.6, 1 }

        if frame.dungeonTabBtn then
            local da = (selectedTab == "dungeons") and accent or dim
            SetTabButtonTextColor(frame.dungeonTabBtn, da)
        end
        if frame.raidTabBtn then
            local ra = (selectedTab == "raids") and accent or dim
            SetTabButtonTextColor(frame.raidTabBtn, ra)
        end
        for _, key in ipairs(EXTERNAL_TAB_ORDER) do
            local btn = frame[EXTERNAL_TAB_DEFS[key].btnField]
            if btn then
                local ea = (selectedTab == key) and accent or dim
                SetTabButtonTextColor(btn, ea)
            end
        end
        if frame.mapTab then
            local ma = (effMode == "map") and accent or dim
            SetTabButtonTextColor(frame.mapTab, ma)
        end
        if frame.bossesTab then
            local ba = (effMode == "bosses") and accent or dim
            SetTabButtonTextColor(frame.bossesTab, ba)
        end
        if frame.questsTab then
            local qa = (effMode == "quests") and accent or dim
            SetTabButtonTextColor(frame.questsTab, qa)
        end
    end
end

local function SyncActivePanel(forcedFloor)
    if not frame then return end
    local onExternal = IsExternalTab()

    if sidebarFrame then sidebarFrame:SetShown(not onExternal) end
    if frame.contentArea then frame.contentArea:SetShown(not onExternal) end
    if frame.mapTab then frame.mapTab:SetShown(not onExternal) end
    if frame.bossesTab then frame.bossesTab:SetShown(not onExternal) end
    if frame.questsTab then frame.questsTab:SetShown(not onExternal) end
    if frame.showMapBtn then frame.showMapBtn:SetShown(not onExternal) end
    if frame.navWpBtn then frame.navWpBtn:SetShown(not onExternal) end
    if frame.mapOptBtn then frame.mapOptBtn:SetShown(not onExternal) end

    for _, key in ipairs(EXTERNAL_TAB_ORDER) do
        local p = externalPanels[key]
        if p and (not onExternal or key ~= selectedTab) and p:IsShown() then
            p:Hide()
        end
    end

    if onExternal then
        if EnsureExternalTabButtons then EnsureExternalTabButtons() end
        if EnsureExternalPanelMounted then EnsureExternalPanelMounted(selectedTab) end
        if frame.mapMenu and frame.mapMenu:IsShown() then frame.mapMenu:Hide() end
        if mapPanel then mapPanel:Hide() end
        if bossPanel then bossPanel:Hide() end
        if questPanel then questPanel:Hide() end

        local activePanel = externalPanels[selectedTab]
        if activePanel and not activePanel:IsShown() then
            activePanel:Show()
        end

        UpdateTabHighlights()

        local def = EXTERNAL_TAB_DEFS[selectedTab]
        local mod = def and def.getModule()
        if mod and mod.OnPanelShown then
            mod.OnPanelShown()
        end
        return
    end

    local effMode = GetEffectiveMode()
    if mapPanel then mapPanel:SetShown(effMode == "map") end
    if bossPanel then bossPanel:SetShown(effMode == "bosses") end
    if questPanel then questPanel:SetShown(effMode == "quests") end

    if effMode == "bosses" and EnsureBossesInitialized then
        EnsureBossesInitialized()
    elseif effMode == "quests" and EnsureQuestsInitialized then
        EnsureQuestsInitialized()
    end

    UpdateTabHighlights()

    if effMode == "map" then
        RefreshMapView(forcedFloor)
    elseif effMode == "bosses" and RefreshBossView then
        RefreshBossView()
    elseif effMode == "quests" and RefreshQuestView then
        RefreshQuestView()
    end
end

-- ─── Mode switching ──────────────────────────────────────────────────────────
local function SetMode(mode)
    if IsExternalTab() then
        selectedTab = (lastJournalTab == "raids") and "raids" or "dungeons"
        DJ_DB().lastTab = selectedTab
        if RefreshSidebar then RefreshSidebar() end
    end
    selectedMode = mode or "map"
    DJ_DB().lastMode = selectedMode
    SyncActivePanel()
end

local function EnsureValidDungeonSelection(db)
    local currentEntry, currentTab
    if selectedDungeonID then
        currentEntry, currentTab = FindDungeon(selectedDungeonID)
    end
    local list = GetList()
    local showAll = db.showAllDungeons == true
    local isValidInTab = (currentEntry ~= nil) and (currentTab == selectedTab)
        and (showAll or sfui.dungeonjournal.IsDungeonInLevelRange(currentEntry))
    if not isValidInTab then
        local fallbackID = nil
        if not showAll and list then
            for _, entry in ipairs(list) do
                if sfui.dungeonjournal.IsDungeonInLevelRange(entry) then
                    fallbackID = entry.id
                    break
                end
            end
        end
        selectedDungeonID = fallbackID or (list and list[1] and list[1].id) or nil
        db.lastDungeon = selectedDungeonID
    end
end

local function SetTab(tab)
    local db = DJ_DB()
    if EXTERNAL_TAB_DEFS[tab] then
        if HasExternalTab(tab) then
            if EnsureExternalTabButtons and frame then
                EnsureExternalTabButtons()
            end
            if EnsureExternalPanelMounted and frame then
                EnsureExternalPanelMounted(tab)
            end
            selectedTab = tab
            db.lastTab = tab
            SyncActivePanel()
            return
        end
        tab = "dungeons"
    end

    selectedTab = (tab == "raids") and "raids" or "dungeons"
    lastJournalTab = selectedTab
    db.lastTab = selectedTab

    -- Only reset selectedDungeonID if it does not belong to the newly selected tab
    EnsureValidDungeonSelection(db)

    if RefreshSidebar then RefreshSidebar() end
    SyncActivePanel()
end
sfui.dungeonjournal.SetTab = SetTab

local function MakeTopTab(parent, text, anchorRef, width)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 84, TAB_H)
    if anchorRef then
        btn:SetPoint("LEFT", anchorRef, "RIGHT", 4, 0)
    else
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -(HEADER_H + 4))
    end
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER")
    fs:SetText(text)
    btn.fs = fs
    if btn.SetFontString then btn:SetFontString(fs) end
    if theme.ApplyTabStyle then
        theme.ApplyTabStyle(btn, false)
    else
        common.apply_flat_backdrop(btn, { 0.08, 0.08, 0.10, 0.9 }, { 0.18, 0.18, 0.20, 1 })
        fs:SetTextColor(0.6, 0.6, 0.6, 1)
    end
    return btn
end

EnsureExternalTabButtons = function()
    if not frame or not frame.raidTabBtn then return end
    local sidebarY = -(HEADER_H + TAB_H + 8)
    local prevBtn = frame.raidTabBtn
    for _, key in ipairs(EXTERNAL_TAB_ORDER) do
        local def = EXTERNAL_TAB_DEFS[key]
        if HasExternalTab(key) then
            local btn = frame[def.btnField]
            if not btn then
                btn = MakeTopTab(frame, def.label, prevBtn, def.width)
                btn:SetScript("OnClick", function() SetTab(key) end)
                frame[def.btnField] = btn
            else
                btn:ClearAllPoints()
                btn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
            end
            prevBtn = btn

            local panel = externalPanels[key]
            if not panel then
                panel = CreateFrame("Frame", nil, frame)
                panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, sidebarY)
                panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
                panel:Hide()
                externalPanels[key] = panel
                frame[def.panelField] = panel
            end
        end
    end
end

EnsureExternalPanelMounted = function(key)
    if not frame or externalMounted[key] then return end
    local def = EXTERNAL_TAB_DEFS[key]
    if not def then return end
    if not externalPanels[key] then
        EnsureExternalTabButtons()
    end
    local panel = externalPanels[key]
    local mod = def.getModule()
    if panel and mod and mod.MountPanel then
        externalMounted[key] = true
        mod.MountPanel(panel, frame)
        if externalThemeDirty[key] and mod.ApplyTheme then
            local pal = externalThemeDirty[key]
            externalThemeDirty[key] = nil
            mod.ApplyTheme(pal)
        end
    end
end

EnsureBossesInitialized = function()
    if bossesInitialized or not frame then return end
    bossesInitialized = true
    if sfui.dungeonjournal._initBosses and initPayload then
        sfui.dungeonjournal._initBosses(initPayload)
    end
end

EnsureQuestsInitialized = function()
    if questsInitialized or not frame then return end
    questsInitialized = true
    if sfui.dungeonjournal._initQuests and initPayload then
        sfui.dungeonjournal._initQuests(initPayload)
    end
end

local function GetCurrentInstanceDungeon()
    if sfui.dj_camelot and sfui.dj_camelot.GetCurrentInstanceDungeon then
        local dID, flIdx = sfui.dj_camelot.GetCurrentInstanceDungeon()
        if dID then
            local d = FindDungeon(dID) or (sfui.dj_camelot.GetDungeonByName and sfui.dj_camelot.GetDungeonByName(dID))
            if d then return d, flIdx end
        end
    end
    if not IsInInstance then return nil end
    local inInstance, instanceType = IsInInstance()
    if not inInstance or (instanceType ~= "party" and instanceType ~= "raid") then
        return nil
    end

    local instName = GetInstanceInfo()
    if not instName or instName == "" then return nil end

    if sfui.dj_camelot and sfui.dj_camelot.GetDungeonByName then
        return sfui.dj_camelot.GetDungeonByName(instName)
    end
    return nil
end
sfui.dungeonjournal.GetCurrentInstanceDungeon = GetCurrentInstanceDungeon

-- ─── Public SelectDungeon & Navigation ───────────────────────────────────────
function sfui.dungeonjournal.SelectDungeon(dungeonID, mode, forceShowAll)
    local db = DJ_DB()
    local entry, tab = FindDungeon(dungeonID)
    if tab and tab ~= selectedTab then
        selectedTab = tab
        lastJournalTab = tab
        db.lastTab = tab
    elseif IsExternalTab() then
        selectedTab = (lastJournalTab == "raids") and "raids" or "dungeons"
        db.lastTab = selectedTab
    end

    if mode and (mode == "map" or mode == "bosses" or mode == "quests") then
        selectedMode = mode
        db.lastMode = mode
    end

    selectedDungeonID = dungeonID
    db.lastDungeon = dungeonID
    db.lastBoss    = 1
    db.lastQuest   = 1

    if forceShowAll and entry and sfui.dungeonjournal.IsDungeonInLevelRange and not sfui.dungeonjournal.IsDungeonInLevelRange(entry) then
        sfui.dungeonjournal.SetOption("showAllDungeons", true)
    end

    if not frame then sfui.dungeonjournal.CreateFrame() end
    if not frame:IsShown() then frame:Show() end

    if RefreshSidebar then RefreshSidebar() end
    SyncActivePanel()
end

function sfui.dungeonjournal.OpenToDungeon(dungeonID, mode)
    sfui.dungeonjournal.SelectDungeon(dungeonID, mode, true)
end

function sfui.dungeonjournal.OpenToQuest(questID)
    local qData = sfui.dj_camelot and sfui.dj_camelot.GetQuestDungeon and sfui.dj_camelot.GetQuestDungeon(questID)
    if qData and qData.dungeon then
        sfui.dungeonjournal.SelectDungeon(qData.dungeon.id, "quests", true)
    end
end

function sfui.dungeonjournal.OpenToBoss(bossNameOrID, dungeonID)
    if not bossNameOrID and not dungeonID then return false end
    local dj = sfui.dj_camelot
    if not dj then return false end

    local targetBossName = bossNameOrID and tostring(bossNameOrID):lower()
    local targetDungeon, targetBossIdx

    -- 1. If dungeonID is given, search that specific dungeon
    if dungeonID then
        local d = dj.GetDungeonByName and dj.GetDungeonByName(dungeonID)
        if d and d.bosses and targetBossName then
            for idx, b in ipairs(d.bosses) do
                if b.name and (b.name:lower() == targetBossName or b.name:lower():find(targetBossName, 1, true)) then
                    targetDungeon = d
                    targetBossIdx = idx
                    break
                end
            end
        end
        targetDungeon = targetDungeon or d
    end

    -- 2. Otherwise search all dungeons and raids for boss
    if not targetDungeon and targetBossName then
        local allLists = { dj.dungeons or {}, dj.raids or {} }
        for _, list in ipairs(allLists) do
            for _, d in ipairs(list) do
                for idx, b in ipairs(d.bosses or {}) do
                    if b.name and (b.name:lower() == targetBossName or b.name:lower():find(targetBossName, 1, true) or targetBossName:find(b.name:lower(), 1, true)) then
                        targetDungeon = d
                        targetBossIdx = idx
                        break
                    end
                end
                if targetDungeon then break end
            end
            if targetDungeon then break end
        end
    end

    if not targetDungeon then return false end

    sfui.dungeonjournal.SelectDungeon(targetDungeon.id, "bosses", true)
    if targetBossIdx and sfui.dungeonjournal.SelectBoss then
        sfui.dungeonjournal.SelectBoss(targetBossIdx)
    end
    if frame and not frame:IsShown() then
        frame:Show()
    end
    return true
end

function sfui.dungeonjournal.GetSelectedDungeonID()
    return selectedDungeonID
end

function sfui.dungeonjournal.SetSelectedDungeonID(dungeonID)
    local db = DJ_DB()
    selectedDungeonID = dungeonID
    db.lastDungeon = dungeonID
    db.lastBoss    = 1
    db.lastQuest   = 1
    SyncActivePanel()
end

function sfui.dungeonjournal.GetSelectedMode()
    return selectedMode
end

sfui.dungeonjournal.SetMode = SetMode

function sfui.dungeonjournal.SelectQuest(dungeonID, questID)
    if not dungeonID and questID then
        local dj = sfui.dj_camelot or (sfui.data and sfui.data.dj_camelot)
        if dj and dj.GetQuestDungeon then
            local qData = dj.GetQuestDungeon(questID)
            if qData and qData.dungeon then
                dungeonID = qData.dungeon.id
            end
        end
    end

    if not dungeonID and not questID then return false end

    if dungeonID then
        sfui.dungeonjournal.SelectDungeon(dungeonID, "quests", true)
    else
        if not frame then sfui.dungeonjournal.CreateFrame() end
        if not frame:IsShown() then frame:Show() end
        SetMode("quests")
    end

    if sfui.dungeonjournal.FocusQuest and questID then
        sfui.dungeonjournal.FocusQuest(questID)
    end
    return true
end

function sfui.dungeonjournal.GetSelectedTab()
    return selectedTab
end

local itemHelpers = {
    GetItemInfo        = GetItemInfo,
    GetItemInstantInfo = common.get_item_instant_info,
    RequestItemLoad    = common.request_item_load,
    GetItemQuality     = GetItemQuality,
    FindDungeon        = FindDungeon,
    GetList            = GetList,
}

function sfui.dungeonjournal.GetItemHelpers()
    return itemHelpers
end

-- ─── Frame Creation ──────────────────────────────────────────────────────────
function sfui.dungeonjournal.CreateFrame()
    if frame then return frame end

    local saved = DJ_DB()
    if not saved.mapTabMigrated then
        saved.mapTabMigrated = true
        saved.lastMode = "map"
    end
    selectedDungeonID = saved.lastDungeon or nil
    selectedMode      = saved.lastMode or "map"
    selectedTab       = saved.lastTab or "dungeons"
    if not IsValidTab(selectedTab) then
        selectedTab = "dungeons"
    end
    if selectedTab == "dungeons" or selectedTab == "raids" then
        lastJournalTab = selectedTab
    else
        lastJournalTab = "dungeons"
    end

    -- ── Main window ───────────────────────────────────────────────────────────
    frame             = CreateFrame("Frame", "SfuiDungeonJournalFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    if sfui.common and sfui.common.register_special_frame then
        sfui.common.register_special_frame(frame)
    end

    common.apply_flat_backdrop(frame, { 0.05, 0.05, 0.07, 0.97 }, { 0.12, 0.12, 0.14, 1 })

    -- ── Header bar ────────────────────────────────────────────────────────────
    local createHeader = (theme and theme.CreateWindowHeader) or (sfui.theme and sfui.theme.CreateWindowHeader)
    if createHeader then
        frame.headerBar = createHeader(frame, "adventure guide")
    end

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.closeBtn = closeBtn
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
    closeBtn:SetSize(28, 28)
    closeBtn:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    theme.ApplyCloseButtonStyle(closeBtn)

    -- ── Map Pin Options Button & Dropdown Menu ────────────────────────────────
    local mapOptBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    frame.mapOptBtn = mapOptBtn
    mapOptBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    mapOptBtn:SetSize(22, 22)
    mapOptBtn:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
    common.apply_flat_backdrop(mapOptBtn, { 0.08, 0.08, 0.10, 0.9 }, { 0.2, 0.2, 0.24, 1 })

    local mapIco = mapOptBtn:CreateTexture(nil, "ARTWORK")
    mapIco:SetSize(14, 14)
    mapIco:SetPoint("CENTER")
    mapIco:SetTexture("Interface\\Icons\\INV_Misc_Map02")
    set_square_icon_coords(mapIco)

    local mapHi = mapOptBtn:CreateTexture(nil, "HIGHLIGHT")
    mapHi:SetAllPoints()
    mapHi:SetColorTexture(1, 1, 1, 0.2)

    mapOptBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine("map pin options", 1, 0.82, 0)
        GameTooltip:AddLine("configure dungeon entrance and quest icons on the world map.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff00ff00<click to toggle pin options>|r", 0, 1, 0)
        GameTooltip:Show()
    end)
    mapOptBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ── Navigation: Set Waypoint Button ───────────────────────────────────────
    local navWpBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    frame.navWpBtn = navWpBtn
    navWpBtn:SetPoint("RIGHT", mapOptBtn, "LEFT", -4, 0)
    navWpBtn:SetSize(22, 22)
    navWpBtn:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
    common.apply_flat_backdrop(navWpBtn, { 0.08, 0.08, 0.10, 0.9 }, { 0.2, 0.2, 0.24, 1 })

    local navWpIco = navWpBtn:CreateTexture(nil, "ARTWORK")
    navWpIco:SetSize(14, 14)
    navWpIco:SetPoint("CENTER")
    navWpIco:SetTexture("Interface\\Minimap\\TRACKING\\FlightMaster")
    navWpIco:SetTexCoord(0.1, 0.9, 0.1, 0.9)

    local navWpHi = navWpBtn:CreateTexture(nil, "HIGHLIGHT")
    navWpHi:SetAllPoints()
    navWpHi:SetColorTexture(1, 1, 1, 0.2)

    navWpBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine("set waypoint", 1, 0.82, 0)
        GameTooltip:AddLine("set an in-game navigation waypoint and supertrack the entrance to this dungeon.", 0.8, 0.8,
            0.8, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff00ff00<click to set navigation waypoint>|r", 0, 1, 0)
        GameTooltip:Show()
    end)
    navWpBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    navWpBtn:SetScript("OnClick", function()
        local dungeon = FindDungeon(selectedDungeonID)
        if not dungeon or not dungeon.entrance or not dungeon.entrance.mapID or not dungeon.entrance.x or not dungeon.entrance.y then
            if common and common.print then common.print("no waypoint coordinates found for this dungeon.") end
            return
        end
        local dungeonName = dungeon.name or "dungeon entrance"
        if sfui.map and sfui.map.SetUserWaypoint then
            sfui.map.SetUserWaypoint(dungeon.entrance.mapID, dungeon.entrance.x,
                dungeon.entrance.y, dungeonName)
        end
    end)

    -- ── Navigation: Show on World Map Button ──────────────────────────────────
    local showMapBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    frame.showMapBtn = showMapBtn
    showMapBtn:SetPoint("RIGHT", navWpBtn, "LEFT", -4, 0)
    showMapBtn:SetSize(22, 22)
    showMapBtn:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
    common.apply_flat_backdrop(showMapBtn, { 0.08, 0.08, 0.10, 0.9 }, { 0.2, 0.2, 0.24, 1 })

    local showMapIco = showMapBtn:CreateTexture(nil, "ARTWORK")
    showMapIco:SetSize(14, 14)
    showMapIco:SetPoint("CENTER")
    showMapIco:SetTexture("Interface\\Icons\\INV_Misc_Map08")
    set_square_icon_coords(showMapIco)

    local showMapHi = showMapBtn:CreateTexture(nil, "HIGHLIGHT")
    showMapHi:SetAllPoints()
    showMapHi:SetColorTexture(1, 1, 1, 0.2)

    showMapBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine("show on world map", 1, 0.82, 0)
        GameTooltip:AddLine("open the world map centered on this dungeon's entrance pin and zone.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff00ff00<click to view map>|r", 0, 1, 0)
        GameTooltip:Show()
    end)
    showMapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    showMapBtn:SetScript("OnClick", function()
        if InCombatLockdown and InCombatLockdown() then return end
        local dungeon = FindDungeon(selectedDungeonID)
        local mapID = dungeon and dungeon.entrance and dungeon.entrance.mapID
        if not mapID then
            if common and common.print then common.print("no map zone registered for this dungeon.") end
            return
        end
        if sfui.map and sfui.map.OpenWorldMap then
            sfui.map.OpenWorldMap(mapID, false, function()
                if sfui.dungeonjournal and sfui.dungeonjournal.HighlightEntrancePin then
                    sfui.dungeonjournal.HighlightEntrancePin(dungeon.id)
                end
            end)
        end
    end)

    local mapMenu = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.mapMenu = mapMenu
    mapMenu:SetFrameStrata("DIALOG")
    mapMenu:SetFrameLevel(frame:GetFrameLevel() + 20)
    mapMenu:SetSize(230, 102)
    mapMenu:SetPoint("TOPRIGHT", mapOptBtn, "BOTTOMRIGHT", 2, -4)
    common.apply_flat_backdrop(mapMenu, { 0.06, 0.06, 0.08, 0.98 }, { 0.24, 0.24, 0.28, 1 })
    mapMenu:Hide()

    local menuDismiss = CreateFrame("Button", nil, UIParent)
    menuDismiss:SetFrameStrata("DIALOG")
    menuDismiss:SetFrameLevel(mapMenu:GetFrameLevel() - 1)
    menuDismiss:SetAllPoints()
    menuDismiss:Hide()
    menuDismiss:SetScript("OnClick", function()
        mapMenu:Hide()
        menuDismiss:Hide()
    end)
    mapMenu:SetScript("OnHide", function()
        menuDismiss:Hide()
    end)

    local mTitle = mapMenu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mTitle:SetPoint("TOPLEFT", mapMenu, "TOPLEFT", 10, -8)
    mTitle:SetText("world map pin options")
    mTitle:SetTextColor(1, 0.82, 0, 1)

    local function MakeMenuCheckbox(label, key, tipText, yOffset)
        local row = CreateFrame("Button", nil, mapMenu)
        row:SetSize(210, 22)
        row:SetPoint("TOPLEFT", mapMenu, "TOPLEFT", 10, yOffset)

        local check = row:CreateTexture(nil, "ARTWORK")
        check:SetSize(14, 14)
        check:SetPoint("LEFT", row, "LEFT", 0, 0)
        check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")

        local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", check, "RIGHT", 6, 0)
        text:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        text:SetJustifyH("LEFT")
        text:SetText(label)

        local hi = row:CreateTexture(nil, "HIGHLIGHT")
        hi:SetAllPoints()
        hi:SetColorTexture(1, 1, 1, 0.08)

        local function RefreshState()
            local enabled = sfui.dungeonjournal.GetOption(key)
            if enabled then
                check:Show()
                text:SetTextColor(0.95, 0.95, 0.95, 1)
            else
                check:Hide()
                text:SetTextColor(0.5, 0.5, 0.5, 1)
            end
        end
        row.RefreshState = RefreshState

        row:SetScript("OnClick", function()
            local cur = sfui.dungeonjournal.GetOption(key)
            sfui.dungeonjournal.SetOption(key, not cur)
            RefreshState()
        end)

        row:SetScript("OnEnter", function(self)
            if tipText then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(label, 1, 0.82, 0)
                GameTooltip:AddLine(tipText, 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        return row
    end

    local rowEnt  = MakeMenuCheckbox("dungeon entrances", "showEntrancePins",
        "show dungeon and raid entrance icons on the world map.", -28)
    local rowQ    = MakeMenuCheckbox("dungeon quests", "showQuestPins", "show quest pickup icons on the world map.", -50)
    local rowLvl  = MakeMenuCheckbox("filter quests by level", "questPinsRequireLevel",
        "when enabled (default), shows all quests with a lower or equal level requirement (including gray/trivial quests), hiding only quests that require a higher level than your character. uncheck to show higher-level locked quests as well.",
        -72)
    local rowTriv = MakeMenuCheckbox("hide outleveled entrances", "autoHideTrivialPins",
        "automatically hides map pins for dungeon entrances whose recommended level is gray/trivial for your character. (quest pins are never hidden by this setting; all quests of lower level requirement remain visible).",
        -94)

    mapMenu:SetSize(230, 180)

    local mDiv = mapMenu:CreateTexture(nil, "ARTWORK")
    mDiv:SetHeight(1)
    mDiv:SetPoint("TOPLEFT", mapMenu, "TOPLEFT", 10, -118)
    mDiv:SetPoint("TOPRIGHT", mapMenu, "TOPRIGHT", -10, -118)
    mDiv:SetColorTexture(0.24, 0.24, 0.28, 1)

    local manageBtn = CreateFrame("Button", nil, mapMenu, "BackdropTemplate")
    manageBtn:SetSize(210, 22)
    manageBtn:SetPoint("TOPLEFT", mapMenu, "TOPLEFT", 10, -124)
    common.apply_flat_backdrop(manageBtn, { 0.10, 0.10, 0.14, 0.9 }, { 0.24, 0.24, 0.28, 1 })

    local manageText = manageBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    manageText:SetPoint("LEFT", manageBtn, "LEFT", 8, 0)
    manageText:SetJustifyH("LEFT")

    local manageCount = manageBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    manageCount:SetPoint("RIGHT", manageBtn, "RIGHT", -8, 0)
    manageCount:SetJustifyH("RIGHT")

    local mHi = manageBtn:CreateTexture(nil, "HIGHLIGHT")
    mHi:SetAllPoints()
    mHi:SetColorTexture(1, 1, 1, 0.08)

    local function RefreshManageState()
        local _, _, _, total = sfui.dungeonjournal.GetHiddenCounts()
        if total > 0 then
            manageText:SetText("manage hidden items...")
            manageText:SetTextColor(1, 0.82, 0, 1)
            manageCount:SetText(string_format("(%d)", total))
            manageCount:SetTextColor(0.4, 1.0, 0.4, 1)
            manageBtn:Enable()
        else
            manageText:SetText("no hidden items")
            manageText:SetTextColor(0.5, 0.5, 0.5, 1)
            manageCount:SetText("")
            manageBtn:Disable()
        end
    end
    manageBtn.RefreshState = RefreshManageState

    manageBtn:SetScript("OnClick", function()
        mapMenu:Hide()
        menuDismiss:Hide()
        sfui.dungeonjournal.OpenHiddenManager()
    end)

    local restoreBtn = CreateFrame("Button", nil, mapMenu, "BackdropTemplate")
    restoreBtn:SetSize(210, 22)
    restoreBtn:SetPoint("TOPLEFT", mapMenu, "TOPLEFT", 10, -150)
    common.apply_flat_backdrop(restoreBtn, { 0.10, 0.10, 0.14, 0.9 }, { 0.24, 0.24, 0.28, 1 })

    local rText = restoreBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rText:SetPoint("CENTER")
    rText:SetText("restore all hidden")

    local rHi = restoreBtn:CreateTexture(nil, "HIGHLIGHT")
    rHi:SetAllPoints()
    rHi:SetColorTexture(1, 1, 1, 0.08)

    local function RefreshRestoreState()
        local _, _, _, total = sfui.dungeonjournal.GetHiddenCounts()
        if total > 0 then
            rText:SetTextColor(0.4, 1.0, 0.4, 1)
            restoreBtn:Enable()
            restoreBtn:Show()
        else
            restoreBtn:Hide()
        end
    end
    restoreBtn.RefreshState = RefreshRestoreState

    restoreBtn:SetScript("OnClick", function()
        mapMenu:Hide()
        menuDismiss:Hide()
        sfui.dungeonjournal.RestoreAllHidden()
    end)

    mapOptBtn:SetScript("OnClick", function()
        if mapMenu:IsShown() then
            mapMenu:Hide()
            menuDismiss:Hide()
        else
            rowEnt:RefreshState()
            rowQ:RefreshState()
            rowLvl:RefreshState()
            rowTriv:RefreshState()
            manageBtn:RefreshState()
            restoreBtn:RefreshState()
            mapMenu:Show()
            menuDismiss:Show()
        end
    end)

    -- ── Dungeons / Raids / External top-level tabs (left group) ──────────────
    frame.dungeonTabBtn = MakeTopTab(frame, "dungeons", nil, 84)
    frame.raidTabBtn    = MakeTopTab(frame, "raids", frame.dungeonTabBtn, 70)

    frame.dungeonTabBtn:SetScript("OnClick", function() SetTab("dungeons") end)
    frame.raidTabBtn:SetScript("OnClick", function() SetTab("raids") end)

    -- ── Map / Boss / Quest mode tabs (right group, top aligned with top tabs)
    local function MakeModeTab(text, anchorRef, width, rightAligned)
        local btn = CreateFrame("Button", nil, frame, "BackdropTemplate")
        btn:SetSize(width or 100, TAB_H)
        if rightAligned then
            if anchorRef then
                btn:SetPoint("RIGHT", anchorRef, "LEFT", -4, 0)
            else
                btn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -(HEADER_H + 4))
            end
        elseif anchorRef then
            btn:SetPoint("LEFT", anchorRef, "RIGHT", 4, 0)
        else
            btn:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDEBAR_W + 16, -(HEADER_H + 4))
        end
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("CENTER")
        fs:SetText(text)
        btn.fs = fs
        if btn.SetFontString then btn:SetFontString(fs) end
        if theme.ApplyTabStyle then
            theme.ApplyTabStyle(btn, false)
        else
            common.apply_flat_backdrop(btn, { 0.08, 0.08, 0.10, 0.9 }, { 0.18, 0.18, 0.20, 1 })
            fs:SetTextColor(0.6, 0.6, 0.6, 1)
        end
        return btn
    end

    frame.questsTab = MakeModeTab("quests", nil, 80, true)
    frame.bossesTab = MakeModeTab("bosses & loot", frame.questsTab, 106, true)
    frame.mapTab    = MakeModeTab("map", frame.bossesTab, 68, true)

    frame.mapTab:SetScript("OnClick", function()
        if HasDungeonMap() then
            SetMode("map")
        end
    end)
    frame.bossesTab:SetScript("OnClick", function() SetMode("bosses") end)
    frame.questsTab:SetScript("OnClick", function() SetMode("quests") end)

    -- ── Sidebar (dungeon list) ─────────────────────────────────────────────────
    local sidebarY = -(HEADER_H + TAB_H + 8)
    sidebarFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.sidebarFrame = sidebarFrame
    sidebarFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, sidebarY)
    sidebarFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 8)
    sidebarFrame:SetWidth(SIDEBAR_W)
    theme.ApplyContainerStyle(sidebarFrame)

    -- ── Content area ──────────────────────────────────────────────────────────
    local contentArea = CreateFrame("Frame", nil, frame)
    frame.contentArea = contentArea
    contentArea:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDEBAR_W + 16, sidebarY)
    contentArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)

    -- ── Map panel container ────────────────────────────────────────────────────
    mapPanel = CreateFrame("Frame", nil, contentArea)
    frame.mapPanel = mapPanel
    mapPanel:SetAllPoints(contentArea)
    mapPanel:Hide()

    -- ── Boss panel container ───────────────────────────────────────────────────
    bossPanel = CreateFrame("Frame", nil, contentArea)
    frame.bossPanel = bossPanel
    bossPanel:SetAllPoints(contentArea)
    bossPanel:Hide()

    -- ── Quest panel container ──────────────────────────────────────────────────
    questPanel = CreateFrame("Frame", nil, contentArea)
    frame.questPanel = questPanel
    questPanel:SetAllPoints(contentArea)
    questPanel:Hide()

    -- ── External full-body tabs (upgrades / recipes / fishing) ─────────────────
    EnsureExternalTabButtons()

    frame:HookScript("OnShow", function()
        if journalThemeDirty then
            journalThemeDirty = false
            if not IsExternalTab() then
                if RefreshSidebar then RefreshSidebar() end
                SyncActivePanel()
            end
        end
    end)

    frame:HookScript("OnHide", function()
        if mapMenu and mapMenu:IsShown() then
            mapMenu:Hide()
        end
        for _, key in ipairs(EXTERNAL_TAB_ORDER) do
            local p = externalPanels[key]
            if p and p:IsShown() then
                p:Hide()
            end
        end
    end)

    -- ── Theme registration ─────────────────────────────────────────────────────
    theme.ApplyWindowStyle(frame)
    theme.RegisterWindow(frame, function(f, pal)
        if not pal then pal = theme.GetPalette() end
        if f.headerBar then
            theme.ApplyHeaderStyle(f.headerBar, "adventure guide")
        end
        if f.sidebarFrame then
            theme.ApplyContainerStyle(f.sidebarFrame)
        end
        for _, key in ipairs(EXTERNAL_TAB_ORDER) do
            if externalMounted[key] then
                local def = EXTERNAL_TAB_DEFS[key]
                local mod = def and def.getModule()
                if mod and mod.ApplyTheme then
                    mod.ApplyTheme(pal)
                end
            elseif externalPanels[key] then
                externalThemeDirty[key] = pal
            end
        end
        UpdateTabHighlights()
        if not IsExternalTab() then
            if f:IsShown() then
                if RefreshSidebar then RefreshSidebar() end
                SyncActivePanel()
            else
                journalThemeDirty = true
            end
        end
    end)

    frame:Hide()
    sfui.dungeonjournal.frame = frame

    -- Signal sidebar submodule to bind immediately; bosses & quests mount lazily on first visit
    initPayload = {
        frame         = frame,
        sidebarFrame  = sidebarFrame,
        bossPanel     = bossPanel,
        questPanel    = questPanel,
        upgradesPanel = externalPanels.upgrades,
        recipesPanel  = externalPanels.recipes,
        fishingPanel  = externalPanels.fishing,
    }

    if sfui.dungeonjournal._initSidebar then sfui.dungeonjournal._initSidebar(initPayload) end

    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_DJ_FRAME_CREATED", initPayload)
    end

    return frame
end

local lastDJToggleTime = 0

local function EnsureSubmodulesInitialized()
    if not frame then return end
    EnsureExternalTabButtons()
    if not RefreshSidebar and initPayload then
        initPayload.upgradesPanel = frame.upgradesPanel or externalPanels.upgrades
        initPayload.recipesPanel  = frame.recipesPanel or externalPanels.recipes
        initPayload.fishingPanel  = frame.fishingPanel or externalPanels.fishing
        if sfui.dungeonjournal._initSidebar then sfui.dungeonjournal._initSidebar(initPayload) end
    end
end

local function OpenJournalFromHidden()
    frame:Show()

    local db = DJ_DB()
    -- In-Instance Auto-Detection
    local activeFloor = nil
    local autoDetected = false
    if db.autoDetectInstance ~= false then
        local activeDungeon, flIdx = GetCurrentInstanceDungeon()
        if activeDungeon then
            autoDetected      = true
            selectedDungeonID = activeDungeon.id
            activeFloor       = flIdx
            selectedTab       = (activeDungeon.category == "camelot_raid" or activeDungeon.category == "classic_raid") and
                "raids" or "dungeons"
            lastJournalTab    = selectedTab
            db.lastDungeon    = selectedDungeonID
            db.lastTab        = selectedTab
        end
    end

    if not autoDetected and IsExternalTab() then
        SyncActivePanel()
        return
    end

    if not IsValidTab(selectedTab) then
        selectedTab = "dungeons"
        lastJournalTab = "dungeons"
        db.lastTab = "dungeons"
    end

    EnsureValidDungeonSelection(db)

    -- Default to map tab when opening a mapped dungeon
    selectedMode = "map"
    db.lastMode = "map"

    if RefreshSidebar then RefreshSidebar() end
    SyncActivePanel(activeFloor)
end

-- ─── Public API ───────────────────────────────────────────────────────────────
function sfui.dungeonjournal.Toggle()
    local now = GetTime()
    if (now - lastDJToggleTime) < 0.15 then return end
    lastDJToggleTime = now

    if not frame then sfui.dungeonjournal.CreateFrame() end
    if not frame then return end

    EnsureSubmodulesInitialized()

    if frame:IsShown() then
        frame:Hide()
    else
        OpenJournalFromHidden()
    end
end

function sfui.dungeonjournal.Open()
    if not frame then sfui.dungeonjournal.CreateFrame() end
    if not frame then return end

    EnsureSubmodulesInitialized()

    if not frame:IsShown() then
        OpenJournalFromHidden()
    end
end

function sfui.dungeonjournal.OpenTab(tab)
    if not frame then sfui.dungeonjournal.CreateFrame() end
    if not frame then return end

    EnsureSubmodulesInitialized()

    if not frame:IsShown() then
        frame:Show()
    end
    SetTab(tab or "dungeons")
end

function sfui.dungeonjournal.GetOption(key)
    local saved = DJ_DB()
    if key == "showEntrancePins" then
        return saved.showEntrancePins ~= false
    elseif key == "showQuestPins" then
        return saved.showQuestPins ~= false
    elseif key == "questPinsRequireLevel" then
        return saved.questPinsRequireLevel ~= false
    elseif key == "autoDetectInstance" then
        return saved.autoDetectInstance ~= false
    elseif key == "showItemTooltips" then
        return saved.showItemTooltips ~= false
    elseif key == "showHiddenInSidebar" then
        return saved.showHiddenInSidebar == true
    elseif key == "autoHideTrivialPins" then
        return saved.autoHideTrivialPins == true
    elseif key == "showAllDungeons" then
        return saved.showAllDungeons == true
    end
    return saved[key]
end

function sfui.dungeonjournal.SetOption(key, val)
    PersistCharOption(key, val)
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_DJ_SETTING_CHANGED", key, val)
    elseif sfui.dungeonjournal.UpdatePins then
        sfui.dungeonjournal.UpdatePins()
    end
end

function sfui.dungeonjournal.GetFrame()
    return frame
end

function sfui.dungeonjournal.Close()
    if frame and frame:IsShown() then
        frame:Hide()
    end
end

function sfui.dungeonjournal.ClearCache()
    -- Forwarded to submodules via message
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_DJ_CLEAR_CACHE")
    end
end

function sfui.dungeonjournal.Rebuild()
    if IsExternalTab() then
        local def = EXTERNAL_TAB_DEFS[selectedTab]
        local mod = def and def.getModule()
        if mod and def.onRebuild then
            def.onRebuild(mod)
        end
        return
    end
    if RefreshSidebar then RefreshSidebar() end
    SyncActivePanel()
end

-- ─── Backward compatibility aliases ──────────────────────────────────────────
sfui.lootviewer_camelot = sfui.dungeonjournal
sfui.ToggleLootViewer   = sfui.dungeonjournal.Toggle

-- ─── Module telemetry & registration ──────────────────────────────────────────
local _djDebug          = {}
function sfui.dungeonjournal_debug_info()
    _djDebug.isCreated       = (frame ~= nil)
    _djDebug.isShown         = (frame ~= nil and frame:IsShown() == true)
    _djDebug.selectedMode    = selectedMode
    _djDebug.selectedTab     = selectedTab
    _djDebug.selectedDungeon = selectedDungeonID
    return _djDebug
end

sfui.dungeonjournal.GetDebugInfo = sfui.dungeonjournal_debug_info

if sfui.RegisterModule then
    sfui.dungeonjournal.OnSpecChanged = function(self)
        if frame and frame:IsShown() and self.Rebuild then
            self.Rebuild()
        end
    end
    sfui.RegisterModule("dungeonjournal", sfui.dungeonjournal)
end

-- ─── Safe Logout Persistence Guard ──────────────────────────────────────────
local function OnLogoutPersistence()
    if SfuiDB and SfuiDB.dungeonjournal then
        local charData = GetCharHidden()
        if SfuiDB.dungeonjournal.showHiddenInSidebar ~= nil then
            charData.showHiddenInSidebar = SfuiDB.dungeonjournal.showHiddenInSidebar
        end
        SfuiDB.dungeonjournal.hiddenDungeons = nil
        SfuiDB.dungeonjournal.hiddenPins = nil
        SfuiDB.dungeonjournal.hiddenQuestPins = nil
    end
end
if sfui.events then
    if sfui.events.RegisterEvent then
        sfui.events.RegisterEvent("PLAYER_LOGOUT", OnLogoutPersistence)
    end
    if sfui.events.RegisterMessage then
        sfui.events.RegisterMessage("SFUI_PERSISTENCE_FLUSH", OnLogoutPersistence)
    end
end
