local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
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
local FRAME_W       = 860
local FRAME_H       = 600
local SIDEBAR_W     = 200
local CONTENT_X     = SIDEBAR_W + 10
local CONTENT_W     = FRAME_W - SIDEBAR_W - 24 -- ~636
local HEADER_H      = 46
local TAB_H         = 28
local INNER_PAD     = 10

-- ─── Locals ───────────────────────────────────────────────────────────────────
local pairs, ipairs, type, tostring = pairs, ipairs, type, tostring
local math_floor                    = math.floor
local table_insert                  = table.insert

local common  = sfui.common
local theme   = sfui.theme

local frame            = nil   -- main window (lazy-created)
local sidebarFrame     = nil
local bossPanel        = nil
local questPanel       = nil

local selectedDungeonID = nil  -- dungeon id string
local selectedMode      = "bosses"  -- "bosses" | "quests"
local selectedTab       = "dungeons" -- "dungeons" | "raids"

-- ─── SavedVariables helpers ───────────────────────────────────────────────────
sfui.db.RegisterDefaults("dungeonjournal", {
    lastDungeon         = nil,
    lastMode            = "bosses",
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
})

local function GetPlayerKey()
    if sfui.common and sfui.common.get_player_unique_key then
        return sfui.common.get_player_unique_key()
    end
    local guid = _G.UnitGUID and _G.UnitGUID("player")
    if guid and guid ~= "" then return guid end
    local name = _G.UnitName and _G.UnitName("player") or "player"
    local getRealm = _G.GetNormalizedRealmName or _G.GetRealmName
    local realm = getRealm and getRealm() or "global"
    return name .. "-" .. realm
end

local function GetCharHidden()
    SfuiDB.dungeonjournal = SfuiDB.dungeonjournal or {}
    local dj = SfuiDB.dungeonjournal
    dj.charHidden = dj.charHidden or {}

    local charKey = GetPlayerKey()
    if not dj.charHidden[charKey] then
        dj.charHidden[charKey] = {
            hiddenDungeons      = {},
            hiddenPins          = {},
            hiddenQuestPins     = {},
            showHiddenInSidebar = dj.showHiddenInSidebar or false,
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
    return data
end
sfui.dungeonjournal.GetCharHidden = GetCharHidden

local function DJ_DB()
    SfuiDB.dungeonjournal = SfuiDB.dungeonjournal or {}
    SfuiDB.dungeonjournal.wishlist = SfuiDB.dungeonjournal.wishlist or {}
    local charData = GetCharHidden()
    SfuiDB.dungeonjournal.hiddenDungeons = charData.hiddenDungeons
    SfuiDB.dungeonjournal.hiddenPins = charData.hiddenPins
    SfuiDB.dungeonjournal.hiddenQuestPins = charData.hiddenQuestPins
    if charData.showHiddenInSidebar ~= nil then
        SfuiDB.dungeonjournal.showHiddenInSidebar = charData.showHiddenInSidebar
    end
    return SfuiDB.dungeonjournal
end
sfui.dungeonjournal.GetDB = DJ_DB
sfui.dungeonjournal.DB    = DJ_DB

function sfui.dungeonjournal.IsWishlisted(itemID)
    if not itemID then return false end
    local id = tonumber(itemID)
    if not id then return false end
    local db = DJ_DB()
    return db.wishlist and db.wishlist[id] == true
end

function sfui.dungeonjournal.ToggleWishlist(itemID)
    if not itemID then return false end
    local id = tonumber(itemID)
    if not id then return false end
    local db = DJ_DB()
    db.wishlist = db.wishlist or {}
    local newState = not db.wishlist[id]
    if newState then
        db.wishlist[id] = true
    else
        db.wishlist[id] = nil
    end
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_DJ_WISHLIST_UPDATED", id, newState)
    end
    if sfui.print then
        local _, link = common.get_item_info(id)
        local name = link or ("Item #" .. id)
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

local function FindDungeon(id)
    local db = GetData()
    for _, d in ipairs(db.dungeons or {}) do
        if d.id == id then return d, "dungeons" end
    end
    for _, r in ipairs(db.raids or {}) do
        if r.id == id then return r, "raids" end
    end
    return nil, nil
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
    if not link then return false end

    if _G.ChatFrameUtil and _G.ChatFrameUtil.InsertLink and _G.ChatFrameUtil.InsertLink(link) then
        return true
    end
    if _G.ChatEdit_InsertLink and _G.ChatEdit_InsertLink(link) then
        return true
    end

    if _G.HandleModifiedItemClick and _G.HandleModifiedItemClick(link) then
        return true
    end

    local activeChat = (_G.ChatFrameUtil and _G.ChatFrameUtil.GetActiveWindow and _G.ChatFrameUtil.GetActiveWindow())
        or (_G.ChatEdit_GetActiveWindow and _G.ChatEdit_GetActiveWindow())
        or _G.ACTIVE_CHAT_EDIT_BOX
        or (_G.LAST_ACTIVE_CHAT_EDIT_BOX and (_G.LAST_ACTIVE_CHAT_EDIT_BOX:IsShown() or _G.LAST_ACTIVE_CHAT_EDIT_BOX:IsVisible()) and _G.LAST_ACTIVE_CHAT_EDIT_BOX)

    if activeChat and (activeChat:IsShown() or activeChat:IsVisible()) and activeChat.Insert then
        activeChat:Insert(link)
        if activeChat.SetFocus then
            activeChat:SetFocus()
        end
        return true
    end

    if _G.MacroFrameText and _G.MacroFrameText:IsShown() and _G.MacroFrameText:HasFocus() then
        _G.MacroFrameText:Insert(link)
        return true
    end
    if _G.CommunitiesFrame and _G.CommunitiesFrame.ChatEditBox and _G.CommunitiesFrame.ChatEditBox:IsShown() and _G.CommunitiesFrame.ChatEditBox:HasFocus() then
        _G.CommunitiesFrame.ChatEditBox:Insert(link)
        return true
    end

    return false
end
sfui.dungeonjournal.InsertItemLinkIntoChat = InsertItemLinkIntoChat

local function ResolveItemLink(btn, fallbackItemID)
    local itemID = (btn and btn.itemID) or fallbackItemID
    local itemLink = btn and btn.link

    if not (itemLink and type(itemLink) == "string" and itemLink:find("|Hitem:")) and itemID then
        if common and common.get_item_info then
            local _, l = common.get_item_info(itemID)
            itemLink = l
        end
        if not itemLink and _G.GetItemInfo then
            local _, l = _G.GetItemInfo(itemID)
            itemLink = l
        end
        if not itemLink and _G.C_Item and _G.C_Item.GetItemInfo then
            local _, l = _G.C_Item.GetItemInfo(itemID)
            itemLink = l
        end
        if itemLink and btn then
            btn.link = itemLink
        end
    end

    if not (itemLink and type(itemLink) == "string" and itemLink:find("|Hitem:")) and itemID then
        local rawName = (btn and btn.nameText and btn.nameText.GetText and btn.nameText:GetText()) or ("item #" .. itemID)
        local cleanName = rawName:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        local quality = 1
        if common and common.get_item_instant_info then
            local _, _, q = common.get_item_instant_info(itemID)
            quality = q or 1
        elseif _G.C_Item and _G.C_Item.GetItemInfoInstant then
            local _, _, q = _G.C_Item.GetItemInfoInstant(itemID)
            quality = q or 1
        end
        local r, g, b = GetQualityColor(quality)
        local hex = string.format("ff%02x%02x%02x", math_floor((r or 1) * 255 + 0.5), math_floor((g or 1) * 255 + 0.5), math_floor((b or 1) * 255 + 0.5))
        itemLink = string.format("|c%s|Hitem:%d:0:0:0:0:0:0:0:0:0:0:0:0|h[%s]|h|r", hex, itemID, cleanName)
        if btn then
            btn.link = itemLink
        end
    end

    return itemLink
end
sfui.dungeonjournal.ResolveItemLink = ResolveItemLink

local function HandleItemClick(btn, mouseBtn, itemID)
    if mouseBtn == "LeftButton" then
        local isChatLink = (_G.IsModifiedClick and _G.IsModifiedClick("CHATLINK")) or (_G.IsShiftKeyDown and _G.IsShiftKeyDown())
        local isDressUp  = (_G.IsModifiedClick and _G.IsModifiedClick("DRESSUP")) or (_G.IsControlKeyDown and _G.IsControlKeyDown())

        if isChatLink or isDressUp then
            local itemLink = ResolveItemLink(btn, itemID)
            if not itemLink then return end

            if isChatLink then
                InsertItemLinkIntoChat(itemLink)
            elseif isDressUp then
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
    if _G.C_QuestLog and _G.C_QuestLog.IsQuestFlaggedCompleted then
        local ok, done = pcall(_G.C_QuestLog.IsQuestFlaggedCompleted, questID)
        if ok and done then return true end
    end
    if _G.IsQuestFlaggedCompleted then
        local ok, done = pcall(_G.IsQuestFlaggedCompleted, questID)
        if ok and done then return true end
    end
    return false
end
sfui.dungeonjournal.IsQuestCompleted = IsQuestCompleted
sfui.dungeonjournal.IsQuestDone      = IsQuestCompleted

local function IsQuestActive(questID)
    if not questID then return false end
    if _G.C_QuestLog and _G.C_QuestLog.IsOnQuest then
        local ok, on = pcall(_G.C_QuestLog.IsOnQuest, questID)
        if ok and on then return true end
    end
    if _G.C_QuestLog and _G.C_QuestLog.GetLogIndexForQuestID then
        local ok, idx = pcall(_G.C_QuestLog.GetLogIndexForQuestID, questID)
        if ok and type(idx) == "number" and idx > 0 then return true end
    end
    if _G.GetQuestLogIndexByID then
        local ok, idx = pcall(_G.GetQuestLogIndexByID, questID)
        if ok and type(idx) == "number" and idx > 0 then return true end
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


function sfui.dungeonjournal.GetQuestChainInfo(quest)
    if not quest then return nil end
    local rawChain = quest.chain
    if not rawChain and quest.chainStart then
        rawChain = { quest.chainStart }
    end
    if not rawChain or #rawChain == 0 then return nil end

    local steps = {}
    for _, s in ipairs(rawChain) do
        local coords = s.coords or (sfui.dj_camelot and sfui.dj_camelot.questCoords and sfui.dj_camelot.questCoords[s.id])
        steps[#steps + 1] = {
            id = s.id,
            name = s.name,
            pickup = s.pickup,
            coords = coords,
            level = s.level,
            minLevel = s.minLevel,
            faction = s.faction,
            objective = s.objective,
            isDungeonQuest = s.isDungeonQuest or (s.id == quest.id),
        }
    end
    if steps[#steps].id ~= quest.id then
        local qCoords = (sfui.dj_camelot and sfui.dj_camelot.questCoords and sfui.dj_camelot.questCoords[quest.id]) or quest.coords
        steps[#steps + 1] = {
            id = quest.id,
            name = quest.name,
            pickup = quest.pickup,
            coords = qCoords,
            level = quest.level,
            minLevel = quest.minLevel,
            faction = quest.faction,
            objective = quest.objective,
            isDungeonQuest = true,
        }
    end

    local currentStep = nil
    local currentStepIndex = nil

    for i, s in ipairs(steps) do
        local isDone = s.id and sfui.dungeonjournal.IsQuestCompleted(s.id)
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

function sfui.dungeonjournal._registerSidebar(fn)  RefreshSidebar  = fn  end
function sfui.dungeonjournal._registerBosses(fn)   RefreshBossView  = fn  end
function sfui.dungeonjournal._registerQuests(fn)   RefreshQuestView = fn  end

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
    if sfui.dungeonjournal.UpdatePins then sfui.dungeonjournal.UpdatePins(true) end
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_DJ_SETTING_CHANGED", "hiddenDungeons", dungeonID)
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
    if sfui.dungeonjournal.UpdatePins then sfui.dungeonjournal.UpdatePins(true) end
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_DJ_SETTING_CHANGED", "hiddenPins", dungeonID)
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
    if sfui.dungeonjournal.UpdatePins then sfui.dungeonjournal.UpdatePins(true) end
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_DJ_SETTING_CHANGED", "hiddenQuestPins", questID)
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
    if sfui.dungeonjournal.UpdatePins then sfui.dungeonjournal.UpdatePins(true) end
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_DJ_SETTING_CHANGED", "restoreAll", total)
    end
    if sfui.print and total > 0 then
        sfui.print(string.format("restored %d hidden item%s (dungeons and map pins).", total, (total > 1 and "s" or "")))
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
    local grayDiff = 0
    if pLvl <= 5 then
        grayDiff = 0
    elseif pLvl <= 39 then
        grayDiff = 5 + math.floor(pLvl / 10)
    elseif pLvl <= 59 then
        grayDiff = 1 + math.floor(pLvl / 5)
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
                    sfui.print(string.format("restored |cffffd100%s|r to dungeon journal and map.", d and d.name or idStr))
                end
            elseif kind == "pins" then
                sfui.dungeonjournal.SetDungeonPinsHidden(idStr, false)
                local d = sfui.dungeonjournal.FindDungeon(idStr)
                if sfui.print then
                    sfui.print(string.format("restored map pins for |cffffd100%s|r.", d and d.name or idStr))
                end
            elseif kind == "quest" then
                local qid = tonumber(idStr) or idStr
                sfui.dungeonjournal.SetQuestPinHidden(qid, false)
                if sfui.print then
                    sfui.print(string.format("restored quest pin |cffffd100#%s|r to map.", tostring(qid)))
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
        f:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        f:SetBackdropColor(0.08, 0.08, 0.11, 0.98)
        f:SetBackdropBorderColor(1, 0.78, 0.2, 0.8)

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
    f.title:SetText(title or "Options")

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

        dlg:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        dlg:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
        dlg:SetBackdropBorderColor(1, 0.78, 0.2, 0.8)

        local title = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", dlg, "TOPLEFT", 14, -12)
        title:SetText("Hidden Dungeons & Pins")
        title:SetTextColor(1, 0.82, 0, 1)

        local closeBtn = CreateFrame("Button", nil, dlg, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", dlg, "TOPRIGHT", -4, -4)
        closeBtn:SetScript("OnClick", function() dlg:Hide() end)

        local sub = dlg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        sub:SetText("Manage hidden dungeons, entrance pins, and quest pins.")
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
        restoreBtn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        restoreBtn:SetBackdropColor(0.12, 0.12, 0.16, 0.95)
        restoreBtn:SetBackdropBorderColor(0.24, 0.24, 0.28, 1)
        local rText = restoreBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        rText:SetPoint("CENTER")
        rText:SetText("Restore All")
        rText:SetTextColor(0.4, 1.0, 0.4, 1)
        restoreBtn:SetScript("OnClick", function()
            sfui.dungeonjournal.RestoreAllHidden()
            dlg.Refresh()
        end)

        local bClose = CreateFrame("Button", nil, dlg, "BackdropTemplate")
        bClose:SetSize(80, 24)
        bClose:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -12, 10)
        bClose:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        bClose:SetBackdropColor(0.12, 0.12, 0.16, 0.95)
        bClose:SetBackdropBorderColor(0.24, 0.24, 0.28, 1)
        local cText = bClose:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cText:SetPoint("CENTER")
        cText:SetText("Close")
        bClose:SetScript("OnClick", function() dlg:Hide() end)

        local emptyMsg = dlg:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        dlg.emptyMsg = emptyMsg
        emptyMsg:SetPoint("CENTER", scroll, "CENTER", 0, 0)
        emptyMsg:SetText("No dungeons or pins are currently hidden.")

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
                    row:SetBackdrop({
                        bgFile   = "Interface\\Buttons\\WHITE8x8",
                        edgeFile = "Interface\\Buttons\\WHITE8x8",
                        edgeSize = 1,
                    })
                    row:SetBackdropColor(0.08, 0.08, 0.10, 0.6)
                    row:SetBackdropBorderColor(0.2, 0.2, 0.24, 0.6)

                    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.label = fs
                    fs:SetPoint("LEFT", row, "LEFT", 6, 0)
                    fs:SetPoint("RIGHT", row, "RIGHT", -74, 0)
                    fs:SetJustifyH("LEFT")

                    local btn = CreateFrame("Button", nil, row, "BackdropTemplate")
                    row.actionBtn = btn
                    btn:SetSize(66, 18)
                    btn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                    btn:SetBackdrop({
                        bgFile   = "Interface\\Buttons\\WHITE8x8",
                        edgeFile = "Interface\\Buttons\\WHITE8x8",
                        edgeSize = 1,
                    })
                    btn:SetBackdropColor(0.14, 0.14, 0.18, 0.95)
                    btn:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
                    local bt = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    btn.text = bt
                    bt:SetPoint("CENTER")
                    bt:SetText("Unhide")
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
                    AddHeader("Hidden Dungeons (Journal & Pins):")
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
                    AddHeader("Hidden Map Pins (Dungeon visible):")
                    hasPins = true
                end
                local d = sfui.dungeonjournal.FindDungeon(dID)
                local dName = d and d.name or dID
                AddItemRow(dName, "Pins Only", function()
                    sfui.dungeonjournal.SetDungeonPinsHidden(dID, false)
                end)
            end

            local hasQuestPins = false
            for qID in pairs(charData.hiddenQuestPins or {}) do
                if not hasQuestPins then
                    if y > 0 then y = y + 6 end
                    AddHeader("Hidden Quest Pins:")
                    hasQuestPins = true
                end
                local qName = "Quest #" .. tostring(qID)
                local cData = sfui.dj_camelot or (sfui.data and sfui.data.dj_camelot)
                if cData then
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
                AddItemRow(qName, "Quest Pin", function()
                    sfui.dungeonjournal.SetQuestPinHidden(qID, false)
                end)
            end

            content:SetHeight(math.max(1, y))
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

local function UpdateTabHighlights()
    if not frame then return end
    if theme.ApplyTabStyle then
        theme.ApplyTabStyle(frame.dungeonTabBtn, selectedTab == "dungeons")
        theme.ApplyTabStyle(frame.raidTabBtn,    selectedTab == "raids")
        theme.ApplyTabStyle(frame.bossesTab,     selectedMode == "bosses")
        theme.ApplyTabStyle(frame.questsTab,     selectedMode == "quests")
    else
        local pal    = theme.GetPalette()
        local accent = pal and pal.accentColor or { 1, 0.78, 0.2, 1 }
        local dim    = pal and pal.tabNormal   or { 0.6, 0.6, 0.6, 1 }

        if frame.dungeonTabBtn then
            local da = (selectedTab == "dungeons") and accent or dim
            SetTabButtonTextColor(frame.dungeonTabBtn, da)
        end
        if frame.raidTabBtn then
            local ra = (selectedTab == "raids") and accent or dim
            SetTabButtonTextColor(frame.raidTabBtn, ra)
        end
        if frame.bossesTab then
            local ba = (selectedMode == "bosses") and accent or dim
            SetTabButtonTextColor(frame.bossesTab, ba)
        end
        if frame.questsTab then
            local qa = (selectedMode == "quests") and accent or dim
            SetTabButtonTextColor(frame.questsTab, qa)
        end
    end
end

-- ─── Mode switching ──────────────────────────────────────────────────────────
local function SetMode(mode)
    selectedMode = mode or "bosses"
    DJ_DB().lastMode = selectedMode

    if not frame then return end

    if bossPanel  then bossPanel:SetShown(selectedMode == "bosses")  end
    if questPanel then questPanel:SetShown(selectedMode == "quests") end

    UpdateTabHighlights()

    if selectedMode == "bosses" and RefreshBossView then
        RefreshBossView()
    elseif selectedMode == "quests" and RefreshQuestView then
        RefreshQuestView()
    end
end

local function SetTab(tab)
    selectedTab = tab or "dungeons"
    DJ_DB().lastTab = selectedTab

    -- Only reset selectedDungeonID if it does not belong to the newly selected tab
    local currentEntry = selectedDungeonID and FindDungeon(selectedDungeonID)
    local list = GetList()
    local isValidInTab = false
    if currentEntry then
        for _, entry in ipairs(list) do
            if entry.id == selectedDungeonID then
                isValidInTab = true
                break
            end
        end
    end
    if not isValidInTab then
        selectedDungeonID = (list and list[1] and list[1].id) or nil
        DJ_DB().lastDungeon = selectedDungeonID
    end

    UpdateTabHighlights()

    if RefreshSidebar then RefreshSidebar() end
    if selectedMode == "bosses" and RefreshBossView then
        RefreshBossView()
    elseif selectedMode == "quests" and RefreshQuestView then
        RefreshQuestView()
    end
end

local function GetCurrentInstanceDungeon()
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
function sfui.dungeonjournal.SelectDungeon(dungeonID, mode)
    local entry, tab = FindDungeon(dungeonID)
    if tab and tab ~= selectedTab then
        selectedTab = tab
        DJ_DB().lastTab = tab
    end

    if mode and (mode == "bosses" or mode == "quests") then
        selectedMode = mode
        DJ_DB().lastMode = mode
    end

    selectedDungeonID   = dungeonID
    DJ_DB().lastDungeon = dungeonID
    DJ_DB().lastBoss    = 1
    DJ_DB().lastQuest   = 1

    if not frame then sfui.dungeonjournal.CreateFrame() end
    if not frame:IsShown() then frame:Show() end

    UpdateTabHighlights()
    if bossPanel  then bossPanel:SetShown(selectedMode == "bosses")  end
    if questPanel then questPanel:SetShown(selectedMode == "quests") end

    if RefreshSidebar then RefreshSidebar() end
    if selectedMode == "bosses" and RefreshBossView then
        RefreshBossView()
    elseif selectedMode == "quests" and RefreshQuestView then
        RefreshQuestView()
    end
end

function sfui.dungeonjournal.OpenToDungeon(dungeonID, mode)
    sfui.dungeonjournal.SelectDungeon(dungeonID, mode)
end

function sfui.dungeonjournal.OpenToQuest(questID)
    local qData = sfui.dj_camelot and sfui.dj_camelot.GetQuestDungeon and sfui.dj_camelot.GetQuestDungeon(questID)
    if qData and qData.dungeon then
        sfui.dungeonjournal.SelectDungeon(qData.dungeon.id, "quests")
    end
end

function sfui.dungeonjournal.GetSelectedDungeonID()
    return selectedDungeonID
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
        sfui.dungeonjournal.SelectDungeon(dungeonID, "quests")
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
    selectedDungeonID = saved.lastDungeon or nil
    selectedMode      = saved.lastMode    or "bosses"
    selectedTab       = saved.lastTab     or "dungeons"

    -- ── Main window ───────────────────────────────────────────────────────────
    frame = CreateFrame("Frame", "SfuiDungeonJournalFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)

    if _G.UISpecialFrames then
        table.insert(_G.UISpecialFrames, "SfuiDungeonJournalFrame")
    end

    frame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.05, 0.05, 0.07, 0.97)
    frame:SetBackdropBorderColor(0.12, 0.12, 0.14, 1)

    -- ── Header bar ────────────────────────────────────────────────────────────
    local headerBar = (theme.CreateWindowHeader or sfui.theme.CreateWindowHeader)(frame, "dungeon journal")

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
    mapOptBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    mapOptBtn:SetBackdropColor(0.08, 0.08, 0.10, 0.9)
    mapOptBtn:SetBackdropBorderColor(0.2, 0.2, 0.24, 1)

    local mapIco = mapOptBtn:CreateTexture(nil, "ARTWORK")
    mapIco:SetSize(14, 14)
    mapIco:SetPoint("CENTER")
    mapIco:SetTexture("Interface\\Icons\\INV_Misc_Map02")
    mapIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local mapHi = mapOptBtn:CreateTexture(nil, "HIGHLIGHT")
    mapHi:SetAllPoints()
    mapHi:SetColorTexture(1, 1, 1, 0.2)

    mapOptBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine("Map Pin Options", 1, 0.82, 0)
        GameTooltip:AddLine("Configure dungeon entrance and quest icons on the World Map.", 0.8, 0.8, 0.8, true)
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
    navWpBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    navWpBtn:SetBackdropColor(0.08, 0.08, 0.10, 0.9)
    navWpBtn:SetBackdropBorderColor(0.2, 0.2, 0.24, 1)

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
        GameTooltip:AddLine("Set Waypoint", 1, 0.82, 0)
        GameTooltip:AddLine("Set an in-game navigation waypoint and supertrack the entrance to this dungeon.", 0.8, 0.8, 0.8, true)
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
        if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
            pcall(function()
                C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(dungeon.entrance.mapID, dungeon.entrance.x, dungeon.entrance.y))
            end)
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
            end
            if common and common.print then
                common.print("waypoint set for " .. (dungeon.name or "dungeon entrance"))
            end
        end
    end)

    -- ── Navigation: Show on World Map Button ──────────────────────────────────
    local showMapBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    frame.showMapBtn = showMapBtn
    showMapBtn:SetPoint("RIGHT", navWpBtn, "LEFT", -4, 0)
    showMapBtn:SetSize(22, 22)
    showMapBtn:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
    showMapBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    showMapBtn:SetBackdropColor(0.08, 0.08, 0.10, 0.9)
    showMapBtn:SetBackdropBorderColor(0.2, 0.2, 0.24, 1)

    local showMapIco = showMapBtn:CreateTexture(nil, "ARTWORK")
    showMapIco:SetSize(14, 14)
    showMapIco:SetPoint("CENTER")
    showMapIco:SetTexture("Interface\\Icons\\INV_Misc_Map08")
    showMapIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local showMapHi = showMapBtn:CreateTexture(nil, "HIGHLIGHT")
    showMapHi:SetAllPoints()
    showMapHi:SetColorTexture(1, 1, 1, 0.2)

    showMapBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine("Show on World Map", 1, 0.82, 0)
        GameTooltip:AddLine("Open the World Map centered on this dungeon's entrance pin and zone.", 0.8, 0.8, 0.8, true)
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
        if not WorldMapFrame:IsShown() then
            ShowUIPanel(WorldMapFrame)
        end
        if WorldMapFrame.SetMapID then
            WorldMapFrame:SetMapID(mapID)
        end
        if sfui.dungeonjournal and sfui.dungeonjournal.HighlightEntrancePin then
            sfui.dungeonjournal.HighlightEntrancePin(dungeon.id)
        end
    end)

    local mapMenu = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.mapMenu = mapMenu
    mapMenu:SetFrameStrata("DIALOG")
    mapMenu:SetFrameLevel(frame:GetFrameLevel() + 20)
    mapMenu:SetSize(230, 102)
    mapMenu:SetPoint("TOPRIGHT", mapOptBtn, "BOTTOMRIGHT", 2, -4)
    mapMenu:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    mapMenu:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
    mapMenu:SetBackdropBorderColor(0.24, 0.24, 0.28, 1)
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

    local rowEnt  = MakeMenuCheckbox("Dungeon Entrances", "showEntrancePins", "Show dungeon and raid entrance icons on the World Map.", -28)
    local rowQ    = MakeMenuCheckbox("Dungeon Quests", "showQuestPins", "Show quest pickup icons on the World Map.", -50)
    local rowLvl  = MakeMenuCheckbox("Filter Quests by Level", "questPinsRequireLevel", "When enabled (default), shows all quests with a lower or equal level requirement (including gray/trivial quests), hiding only quests that require a higher level than your character. Uncheck to show higher-level locked quests as well.", -72)
    local rowTriv = MakeMenuCheckbox("Hide Outleveled Entrances", "autoHideTrivialPins", "Automatically hides map pins for dungeon entrances whose recommended level is gray/trivial for your character. (Quest pins are never hidden by this setting; all quests of lower level requirement remain visible).", -94)

    mapMenu:SetSize(230, 180)

    local mDiv = mapMenu:CreateTexture(nil, "ARTWORK")
    mDiv:SetHeight(1)
    mDiv:SetPoint("TOPLEFT", mapMenu, "TOPLEFT", 10, -118)
    mDiv:SetPoint("TOPRIGHT", mapMenu, "TOPRIGHT", -10, -118)
    mDiv:SetColorTexture(0.24, 0.24, 0.28, 1)

    local manageBtn = CreateFrame("Button", nil, mapMenu, "BackdropTemplate")
    manageBtn:SetSize(210, 22)
    manageBtn:SetPoint("TOPLEFT", mapMenu, "TOPLEFT", 10, -124)
    manageBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    manageBtn:SetBackdropColor(0.10, 0.10, 0.14, 0.9)
    manageBtn:SetBackdropBorderColor(0.24, 0.24, 0.28, 1)

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
            manageText:SetText("Manage Hidden Items...")
            manageText:SetTextColor(1, 0.82, 0, 1)
            manageCount:SetText(string.format("(%d)", total))
            manageCount:SetTextColor(0.4, 1.0, 0.4, 1)
            manageBtn:Enable()
        else
            manageText:SetText("No Hidden Items")
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
    restoreBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    restoreBtn:SetBackdropColor(0.10, 0.10, 0.14, 0.9)
    restoreBtn:SetBackdropBorderColor(0.24, 0.24, 0.28, 1)

    local rText = restoreBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rText:SetPoint("CENTER")
    rText:SetText("Restore All Hidden")

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

    -- ── Dungeon / Raids top-level tabs (left group) ───────────────────────────
    local function MakeTopTab(text, anchor, anchorRef)
        local btn = CreateFrame("Button", nil, frame, "BackdropTemplate")
        btn:SetSize(90, TAB_H)
        if anchorRef then
            btn:SetPoint("LEFT", anchorRef, "RIGHT", 4, 0)
        else
            btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -(HEADER_H + 4))
        end
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("CENTER")
        fs:SetText(text)
        btn.fs = fs
        if btn.SetFontString then btn:SetFontString(fs) end
        if theme.ApplyTabStyle then
            theme.ApplyTabStyle(btn, false)
        else
            btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            btn:SetBackdropColor(0.08, 0.08, 0.10, 0.9)
            btn:SetBackdropBorderColor(0.18, 0.18, 0.20, 1)
            fs:SetTextColor(0.6, 0.6, 0.6, 1)
        end
        return btn
    end

    frame.dungeonTabBtn = MakeTopTab("dungeons", "TOPLEFT")
    frame.raidTabBtn    = MakeTopTab("raids", "LEFT", frame.dungeonTabBtn)

    frame.dungeonTabBtn:SetScript("OnClick", function() SetTab("dungeons") end)
    frame.raidTabBtn:SetScript("OnClick",    function() SetTab("raids")    end)

    -- ── Boss / Quest mode tabs (right group, top aligned with dungeon tabs) ───
    local function MakeModeTab(text, anchorRef, width)
        local btn = CreateFrame("Button", nil, frame, "BackdropTemplate")
        btn:SetSize(width or 100, TAB_H)
        if anchorRef then
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
            btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            btn:SetBackdropColor(0.08, 0.08, 0.10, 0.9)
            btn:SetBackdropBorderColor(0.18, 0.18, 0.20, 1)
            fs:SetTextColor(0.6, 0.6, 0.6, 1)
        end
        return btn
    end

    frame.bossesTab = MakeModeTab("bosses & loot", nil, 106)
    frame.questsTab = MakeModeTab("quests", frame.bossesTab, 80)

    frame.bossesTab:SetScript("OnClick", function() SetMode("bosses") end)
    frame.questsTab:SetScript("OnClick", function() SetMode("quests") end)

    -- ── Sidebar (dungeon list) ─────────────────────────────────────────────────
    local sidebarY = -(HEADER_H + TAB_H + 8)
    sidebarFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.sidebarFrame = sidebarFrame
    sidebarFrame:SetPoint("TOPLEFT",    frame, "TOPLEFT",    8,  sidebarY)
    sidebarFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8,  8)
    sidebarFrame:SetWidth(SIDEBAR_W)
    theme.ApplyContainerStyle(sidebarFrame)

    -- ── Content area ──────────────────────────────────────────────────────────
    local contentArea = CreateFrame("Frame", nil, frame)
    frame.contentArea = contentArea
    contentArea:SetPoint("TOPLEFT",     frame, "TOPLEFT",     SIDEBAR_W + 16, sidebarY)
    contentArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)

    -- ── Boss panel container ───────────────────────────────────────────────────
    bossPanel = CreateFrame("Frame", nil, contentArea)
    frame.bossPanel = bossPanel
    bossPanel:SetAllPoints(contentArea)
    bossPanel:Show()

    -- ── Quest panel container ──────────────────────────────────────────────────
    questPanel = CreateFrame("Frame", nil, contentArea)
    frame.questPanel = questPanel
    questPanel:SetAllPoints(contentArea)
    questPanel:Hide()

    -- ── Theme registration ─────────────────────────────────────────────────────
    theme.ApplyWindowStyle(frame)
    theme.RegisterWindow(frame, function(f, pal)
        if not pal then pal = theme.GetPalette() end
        if f.headerBar then
            theme.ApplyHeaderStyle(f.headerBar, "dungeon journal")
        end
        if f.sidebarFrame then
            theme.ApplyContainerStyle(f.sidebarFrame)
        end
        UpdateTabHighlights()
    end)

    frame:Hide()
    sfui.dungeonjournal.frame = frame

    -- Signal submodules to bind to these panels
    local payload = {
        frame        = frame,
        sidebarFrame = sidebarFrame,
        bossPanel    = bossPanel,
        questPanel   = questPanel,
    }

    if sfui.dungeonjournal._initSidebar then sfui.dungeonjournal._initSidebar(payload) end
    if sfui.dungeonjournal._initBosses  then sfui.dungeonjournal._initBosses(payload)  end
    if sfui.dungeonjournal._initQuests  then sfui.dungeonjournal._initQuests(payload)  end

    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_DJ_FRAME_CREATED", payload)
    end

    return frame
end

-- ─── Public API ───────────────────────────────────────────────────────────────
function sfui.dungeonjournal.Toggle()
    if not frame then sfui.dungeonjournal.CreateFrame() end
    if not frame then return end

    -- Self-heal in case submodules were not initialized
    if not RefreshSidebar then
        local payload = {
            frame        = frame,
            sidebarFrame = frame.sidebarFrame or sidebarFrame,
            bossPanel    = frame.bossPanel or bossPanel,
            questPanel   = frame.questPanel or questPanel,
        }
        if sfui.dungeonjournal._initSidebar then sfui.dungeonjournal._initSidebar(payload) end
        if sfui.dungeonjournal._initBosses  then sfui.dungeonjournal._initBosses(payload)  end
        if sfui.dungeonjournal._initQuests  then sfui.dungeonjournal._initQuests(payload)  end
    end

    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()

        -- In-Instance Auto-Detection
        if DJ_DB().autoDetectInstance ~= false then
            local activeDungeon = GetCurrentInstanceDungeon()
            if activeDungeon then
                selectedDungeonID = activeDungeon.id
                selectedTab = (activeDungeon.category == "camelot_raid" or activeDungeon.category == "classic_raid") and "raids" or "dungeons"
                DJ_DB().lastDungeon = selectedDungeonID
                DJ_DB().lastTab     = selectedTab
            end
        end

        local list = GetList()
        local currentEntry = selectedDungeonID and FindDungeon(selectedDungeonID)
        local isValidInTab = false
        if currentEntry then
            for _, entry in ipairs(list) do
                if entry.id == selectedDungeonID then
                    isValidInTab = true
                    break
                end
            end
        end
        if not isValidInTab then
            selectedDungeonID = (list and list[1] and list[1].id) or nil
            DJ_DB().lastDungeon = selectedDungeonID
        end

        UpdateTabHighlights()
        if bossPanel  then bossPanel:SetShown(selectedMode == "bosses")  end
        if questPanel then questPanel:SetShown(selectedMode == "quests") end

        if RefreshSidebar then RefreshSidebar() end
        if selectedMode == "bosses" and RefreshBossView then
            RefreshBossView()
        elseif selectedMode == "quests" and RefreshQuestView then
            RefreshQuestView()
        end
    end
end

function sfui.dungeonjournal.Open()
    if not frame then sfui.dungeonjournal.CreateFrame() end
    if not frame then return end

    -- Self-heal in case submodules were not initialized
    if not RefreshSidebar then
        local payload = {
            frame        = frame,
            sidebarFrame = frame.sidebarFrame or sidebarFrame,
            bossPanel    = frame.bossPanel or bossPanel,
            questPanel   = frame.questPanel or questPanel,
        }
        if sfui.dungeonjournal._initSidebar then sfui.dungeonjournal._initSidebar(payload) end
        if sfui.dungeonjournal._initBosses  then sfui.dungeonjournal._initBosses(payload)  end
        if sfui.dungeonjournal._initQuests  then sfui.dungeonjournal._initQuests(payload)  end
    end

    if not frame:IsShown() then
        frame:Show()

        -- In-Instance Auto-Detection
        if DJ_DB().autoDetectInstance ~= false then
            local activeDungeon = GetCurrentInstanceDungeon()
            if activeDungeon then
                selectedDungeonID = activeDungeon.id
                selectedTab = (activeDungeon.category == "camelot_raid" or activeDungeon.category == "classic_raid") and "raids" or "dungeons"
                DJ_DB().lastDungeon = selectedDungeonID
                DJ_DB().lastTab     = selectedTab
            end
        end

        local list = GetList()
        local currentEntry = selectedDungeonID and FindDungeon(selectedDungeonID)
        local isValidInTab = false
        if currentEntry then
            for _, entry in ipairs(list) do
                if entry.id == selectedDungeonID then
                    isValidInTab = true
                    break
                end
            end
        end
        if not isValidInTab then
            selectedDungeonID = (list and list[1] and list[1].id) or nil
            DJ_DB().lastDungeon = selectedDungeonID
        end

        UpdateTabHighlights()
        if bossPanel  then bossPanel:SetShown(selectedMode == "bosses")  end
        if questPanel then questPanel:SetShown(selectedMode == "quests") end

        if RefreshSidebar then RefreshSidebar() end
        if selectedMode == "bosses" and RefreshBossView then
            RefreshBossView()
        elseif selectedMode == "quests" and RefreshQuestView then
            RefreshQuestView()
        end
    end
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
    end
    return saved[key]
end

function sfui.dungeonjournal.SetOption(key, val)
    local saved = DJ_DB()
    saved[key] = val
    if sfui.dungeonjournal.UpdatePins then
        sfui.dungeonjournal.UpdatePins()
    end
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_DJ_SETTING_CHANGED", key, val)
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
    if RefreshSidebar  then RefreshSidebar()  end
    if selectedMode == "bosses" and RefreshBossView then
        RefreshBossView()
    elseif selectedMode == "quests" and RefreshQuestView then
        RefreshQuestView()
    end
end

-- ─── Backward compatibility aliases ──────────────────────────────────────────
sfui.lootviewer_camelot = sfui.dungeonjournal
sfui.ToggleLootViewer   = sfui.dungeonjournal.Toggle

-- ─── Module telemetry & registration ──────────────────────────────────────────
local _djDebug = {}
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

-- ─── Live Theme Synchronization ──────────────────────────────────────────────
if sfui.events and sfui.events.RegisterMessage then
    sfui.events.RegisterMessage("SFUI_THEME_CHANGED", function()
        if frame and frame:IsShown() then
            UpdateTabHighlights()
            if sfui.theme and sfui.theme.ApplyWindowStyle then
                sfui.theme.ApplyWindowStyle(frame)
            end
            if RefreshSidebar then RefreshSidebar() end
            if selectedMode == "bosses" and RefreshBossView then
                RefreshBossView()
            elseif selectedMode == "quests" and RefreshQuestView then
                RefreshQuestView()
            end
        end
    end)
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
