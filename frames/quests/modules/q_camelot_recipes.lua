--[[
    SFUI Tracker Module: Camelot Tracked Recipes & Shopping List
    frames/quests/modules/q_camelot_recipes.lua

    Pluggable tracker module for Warcraft Forever (Camelot) & Classic Era.
    Displays pinned recipes with live reagent bag counts, acquisition source info,
    waypoint tracking, Blizzard C_TradeSkillUI integration, and direct router to the SFUI Recipe Catalog.
--]]

local addonName, addon = ...
local sfui = _G.sfui or {}
sfui.tracker = sfui.tracker or {}
sfui.questlog = sfui.questlog or {}
sfui.recipes = sfui.recipes or {}

-- Guard: Classic / Camelot only (Exclude Retail)
local isRetail = sfui.isRetail
if isRetail == nil then
    local projectID = _G.WOW_PROJECT_ID or 1
    local _, _, _, tocVersionNum = _G.GetBuildInfo()
    tocVersionNum = tonumber(tocVersionNum) or 0
    local isCamelot = (tocVersionNum >= 16000 and tocVersionNum < 20000) or (projectID == 18)
    isRetail = (projectID == 1) and not isCamelot
end

if isRetail then
    return
end

local _G = _G
local C_Item = _G.C_Item
local C_Timer = _G.C_Timer
local C_TradeSkillUI = _G.C_TradeSkillUI
local GetItemCount = _G.GetItemCount
local GetItemInfo = _G.GetItemInfo
local GetTime = _G.GetTime
local UnitName = _G.UnitName
local UnitClass = _G.UnitClass
local PlaySound = _G.PlaySound
local SOUNDKIT = _G.SOUNDKIT
local IsShiftKeyDown = _G.IsShiftKeyDown
local InCombatLockdown = _G.InCombatLockdown

local ipairs, pairs, type, tonumber, tostring = _G.ipairs, _G.pairs, _G.type, _G.tonumber, _G.tostring
local next = _G.next
local table_insert, table_sort, table_concat = _G.table.insert, _G.table.sort, _G.table.concat
local string_format, string_lower, string_match = string.format, string.lower, string.match

local ScheduleRecipesSyncBroadcast
local CamelotRecipesModule

-- ─────────────────────────────────────────────────────────
--  STORAGE & PUBLIC API
-- ─────────────────────────────────────────────────────────
local function GetPinnedStorage()
    SfuiDB = SfuiDB or {}
    SfuiDB.pinned_recipes = SfuiDB.pinned_recipes or {}
    return SfuiDB.pinned_recipes
end

function sfui.recipes.GetPinnedRecipes()
    return GetPinnedStorage()
end

function sfui.recipes.IsRecipePinned(spellID)
    if not spellID then return false end
    local pinned = GetPinnedStorage()
    if pinned[spellID] == true or pinned[tostring(spellID)] == true then
        return true
    end
    if C_TradeSkillUI and C_TradeSkillUI.IsRecipeTracked then
        local numID = tonumber(spellID)
        if numID and (C_TradeSkillUI.IsRecipeTracked(numID, false) or C_TradeSkillUI.IsRecipeTracked(numID, true)) then
            return true
        end
    end
    return false
end

function sfui.recipes.TogglePinRecipe(spellID)
    spellID = tonumber(spellID) or spellID
    if not spellID then return false end
    local pinned = GetPinnedStorage()
    local isCurrentlyPinned = sfui.recipes.IsRecipePinned(spellID)
    local isPinned = not isCurrentlyPinned

    if isPinned then
        pinned[spellID] = true
        pinned[tostring(spellID)] = nil
        if C_TradeSkillUI and C_TradeSkillUI.SetRecipeTracked and C_TradeSkillUI.IsRecipeProfessionLearned then
            if C_TradeSkillUI.IsRecipeProfessionLearned(spellID) then
                pcall(C_TradeSkillUI.SetRecipeTracked, spellID, true, false)
            end
        end
    else
        pinned[spellID] = nil
        pinned[tostring(spellID)] = nil
        if C_TradeSkillUI and C_TradeSkillUI.SetRecipeTracked and C_TradeSkillUI.IsRecipeTracked then
            if C_TradeSkillUI.IsRecipeTracked(spellID, false) then
                pcall(C_TradeSkillUI.SetRecipeTracked, spellID, false, false)
            end
            if C_TradeSkillUI.IsRecipeTracked(spellID, true) then
                pcall(C_TradeSkillUI.SetRecipeTracked, spellID, false, true)
            end
        end
    end

    if PlaySound and SOUNDKIT then
        if isPinned then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
        else
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or 857)
        end
    end

    if CamelotRecipesModule and CamelotRecipesModule.MarkDirty then
        CamelotRecipesModule:MarkDirty(0)
    end
    if sfui.tracker and sfui.tracker.RequestRefresh then
        sfui.tracker.RequestRefresh(0)
    end

    if sfui.recipes.browser and sfui.recipes.browser.UpdateList then
        sfui.recipes.browser.UpdateList()
    end

    if ScheduleRecipesSyncBroadcast then
        ScheduleRecipesSyncBroadcast(true, false)
    end

    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_RECIPE_PINNED_CHANGED", spellID, isPinned)
    end

    return isPinned
end

function sfui.recipes.ClearPinnedRecipes()
    local pinned = GetPinnedStorage()
    local count = 0
    for k in pairs(pinned) do
        pinned[k] = nil
        count = count + 1
    end
    if C_TradeSkillUI and C_TradeSkillUI.GetRecipesTracked and C_TradeSkillUI.SetRecipeTracked then
        for _, isRecraft in ipairs({ false, true }) do
            local tracked = C_TradeSkillUI.GetRecipesTracked(isRecraft)
            if tracked then
                for _, spellID in ipairs(tracked) do
                    pcall(C_TradeSkillUI.SetRecipeTracked, spellID, false, isRecraft)
                    count = count + 1
                end
            end
        end
    end
    if CamelotRecipesModule and CamelotRecipesModule.MarkDirty then
        CamelotRecipesModule:MarkDirty(0)
    end
    if sfui.tracker and sfui.tracker.RequestRefresh then
        sfui.tracker.RequestRefresh(0)
    end
    if sfui.recipes.browser and sfui.recipes.browser.UpdateList then
        sfui.recipes.browser.UpdateList()
    end
    if ScheduleRecipesSyncBroadcast then
        ScheduleRecipesSyncBroadcast(true, false)
    end
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_RECIPE_PINNED_CHANGED", nil, false)
    end
    return count
end

-- ─────────────────────────────────────────────────────────
--  REAGENT RESOLUTION & CROSS-CLIENT SYNC
-- ─────────────────────────────────────────────────────────
local remotePeerRecipes      = {} -- [peerKey] = { name, class, pins = { { id, name, rec, reqs }, ... }, mats = { [itemID] = count } }
local lastSentRecipesSig     = nil
local recipesBroadcastQueued = false

local function CleanPeerKey(name)
    if type(name) ~= "string" or name == "" then return "" end
    if sfui.sync and sfui.sync.multibox and sfui.sync.multibox.CleanKey then
        return sfui.sync.multibox.CleanKey(name)
    end
    local short = string_match(name, "^([^%-]+)") or name
    return string_lower(short)
end

local function FormatColoredName(name, classToken)
    local raw = tostring(name or "player")
    if sfui.sync and sfui.sync.CommandName then
        raw = sfui.sync.CommandName(raw) or raw
    else
        raw = string_match(raw, "^([^%-]+)") or raw
    end
    local clean = string_lower(raw)
    if classToken and sfui.common and sfui.common.class_color_name then
        return sfui.common.class_color_name(clean, classToken)
    end
    if classToken and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classToken] then
        local c = _G.RAID_CLASS_COLORS[classToken]
        local hex = c.colorStr or string_format("ff%02x%02x%02x", math.floor((c.r or 1) * 255), math.floor((c.g or 1) * 255), math.floor((c.b or 1) * 255))
        return "|c" .. hex .. clean .. "|r"
    end
    return clean
end

local function IsSyncActive()
    local sync = sfui.sync
    if not sync or not sync.GetSettings then return false end
    local s = sync.GetSettings()
    return (s and s.enabled == true and s.syncRecipes ~= false) or false
end

local function IsPeerRecipesVisible(peerKey, peer)
    if not IsSyncActive() or not peer then return false end
    local myFull = (sfui.sync and sfui.sync.FullName and sfui.sync.FullName("player"))
        or (UnitName and UnitName("player"))
        or ""
    local myKey = CleanPeerKey(myFull)
    if peerKey == "" or peerKey == myKey then
        return false
    end
    local sync = sfui.sync
    if sync and sync.IsPeerOffline and sync.IsPeerOffline(peer.name) then
        return false
    end
    if sync and sync.IsPeerOnline and not sync.IsPeerOnline(peer.name) then
        local mb = sync.multibox
        if not (mb and mb.FindPartyUnitByName and mb.FindPartyUnitByName(peer.name)) then
            return false
        end
    end
    return true
end

local function GetLocalItemCount(itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then return 0 end
    if sfui.inventory and sfui.inventory.GetCount then
        local bagCnt = sfui.inventory.GetCount(itemID) or 0
        local myGUID = _G.UnitGUID and _G.UnitGUID("player")
        local bankCnt = (myGUID and SfuiDB and SfuiDB.alts and SfuiDB.alts[myGUID] and SfuiDB.alts[myGUID].bankItems and SfuiDB.alts[myGUID].bankItems[itemID]) or 0
        if bagCnt + bankCnt > 0 then
            return bagCnt + bankCnt
        end
    end
    if C_Item and C_Item.GetItemCount then
        return tonumber(C_Item.GetItemCount(itemID, true)) or 0
    end
    if GetItemCount then
        return tonumber(GetItemCount(itemID, true)) or 0
    end
    return 0
end

local function ResolveItemName(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID))
        or (GetItemInfo and GetItemInfo(itemID))
    return name or ("item #" .. tostring(itemID))
end

local function CollectLocalTrackedMap()
    local trackedMap = {}
    local pinned = GetPinnedStorage()
    if pinned then
        for id, isPinned in pairs(pinned) do
            if isPinned then
                local numID = tonumber(id)
                if numID and numID > 0 then
                    trackedMap[numID] = trackedMap[numID] or { recipeID = numID }
                    trackedMap[numID].isSfuiPinned = true
                end
            end
        end
    end

    if C_TradeSkillUI and C_TradeSkillUI.GetRecipesTracked then
        for _, isRecraft in ipairs({ false, true }) do
            local blizzTracked = C_TradeSkillUI.GetRecipesTracked(isRecraft)
            if blizzTracked and #blizzTracked > 0 then
                for _, rID in ipairs(blizzTracked) do
                    local numID = tonumber(rID)
                    if numID and numID > 0 then
                        trackedMap[numID] = trackedMap[numID] or { recipeID = numID }
                        trackedMap[numID].isBlizzTracked = true
                        trackedMap[numID].isRecraft = isRecraft
                    end
                end
            end
        end
    end
    return trackedMap
end

local function ExtractRecipeReagents(spellID, rData, isRecraft, fallbackReqs)
    local out = {}
    local seen = {}
    local schematic = nil
    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic then
        schematic = C_TradeSkillUI.GetRecipeSchematic(spellID, isRecraft or false)
    end

    if schematic and schematic.reagentSlotSchematics and #schematic.reagentSlotSchematics > 0 then
        for _, slot in ipairs(schematic.reagentSlotSchematics) do
            local req = tonumber(slot.quantityRequired) or 1
            local reagent = slot.reagents and slot.reagents[1]
            if reagent then
                local itemID = tonumber(reagent.itemID)
                local currencyID = tonumber(reagent.currencyID)
                if itemID and itemID > 0 and not seen[itemID] then
                    seen[itemID] = true
                    table_insert(out, { itemID = itemID, req = req })
                elseif currencyID and currencyID > 0 then
                    table_insert(out, { currencyID = currencyID, req = req })
                end
            end
        end
    elseif rData and type(rData.reagents) == "table" and next(rData.reagents) then
        local matIDs = {}
        for matID in pairs(rData.reagents) do
            local nMat = tonumber(matID)
            if nMat and nMat > 0 then
                table_insert(matIDs, nMat)
            end
        end
        table_sort(matIDs)
        for _, matID in ipairs(matIDs) do
            local req = tonumber(rData.reagents[matID] or rData.reagents[tostring(matID)]) or 1
            table_insert(out, { itemID = matID, req = req })
        end
    elseif type(fallbackReqs) == "table" and next(fallbackReqs) then
        local matIDs = {}
        for matID in pairs(fallbackReqs) do
            local nMat = tonumber(matID)
            if nMat and nMat > 0 then
                table_insert(matIDs, nMat)
            end
        end
        table_sort(matIDs)
        for _, matID in ipairs(matIDs) do
            local req = tonumber(fallbackReqs[matID] or fallbackReqs[tostring(matID)]) or 1
            table_insert(out, { itemID = matID, req = req })
        end
    end

    return out, schematic
end

sfui.recipes = sfui.recipes or {}

function sfui.recipes.GetPinnedReagentDeficits()
    local trackedMap = CollectLocalTrackedMap()
    local db = sfui.recipes_camelot and sfui.recipes_camelot.recipes
    local totals = {}
    for spellID, entry in pairs(trackedMap) do
        local rData = db and db[spellID]
        local reagents = ExtractRecipeReagents(spellID, rData, entry.isRecraft)
        for _, rg in ipairs(reagents) do
            if rg.itemID and rg.itemID > 0 then
                totals[rg.itemID] = (totals[rg.itemID] or 0) + (rg.req or 1)
            end
        end
    end

    local myGUID = _G.UnitGUID and _G.UnitGUID("player")
    if myGUID and SfuiDB then
        SfuiDB.altPinnedReagents = SfuiDB.altPinnedReagents or {}
        SfuiDB.altPinnedReagents[myGUID] = next(totals) and totals or nil
    end

    local deficits = {}
    for itemID, needed in pairs(totals) do
        local have = GetLocalItemCount(itemID)
        local def = needed - have
        if def > 0 then
            deficits[itemID] = {
                needed  = needed,
                have    = have,
                deficit = def,
            }
        end
    end
    return deficits
end

local function BroadcastPinnedRecipes(force, isInit)
    if not IsSyncActive() then return end
    local sync = sfui.sync
    if not sync or not sync.Broadcast then return end

    local db = sfui.recipes_camelot and sfui.recipes_camelot.recipes
    local localTracked = CollectLocalTrackedMap()
    local ids = {}
    for numID in pairs(localTracked) do
        table_insert(ids, numID)
    end
    table_sort(ids)

    local neededItemIDs = {}
    local pinsPayload = {}
    local sigParts = {}

    for _, spellID in ipairs(ids) do
        local entry = localTracked[spellID]
        local rData = db and db[spellID]
        local isRecraft = entry.isRecraft or false
        local reagents, schematic = ExtractRecipeReagents(spellID, rData, isRecraft, nil)
        local recipeName = (rData and rData.name)
            or (schematic and schematic.name and schematic.name ~= "" and schematic.name)
            or (C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(spellID) and C_TradeSkillUI.GetRecipeInfo(spellID).name)
            or nil

        local reqMap = nil
        for _, rg in ipairs(reagents) do
            if rg.itemID then
                neededItemIDs[rg.itemID] = true
                reqMap = reqMap or {}
                reqMap[rg.itemID] = rg.req
            end
        end

        table_insert(pinsPayload, {
            id   = spellID,
            name = recipeName,
            rec  = isRecraft and 1 or nil,
            reqs = reqMap,
        })
        table_insert(sigParts, string_format("p:%d:%d", spellID, isRecraft and 1 or 0))
    end

    -- Also count reagents in our bags/bank for any recipes pinned by active synced peers
    for peerKey, peer in pairs(remotePeerRecipes) do
        if IsPeerRecipesVisible(peerKey, peer) and type(peer.pins) == "table" then
            for _, remPin in ipairs(peer.pins) do
                local spellID = tonumber(remPin.id)
                if spellID then
                    local rData = db and db[spellID]
                    local reagents = ExtractRecipeReagents(spellID, rData, remPin.rec == 1, remPin.reqs)
                    for _, rg in ipairs(reagents) do
                        if rg.itemID then
                            neededItemIDs[rg.itemID] = true
                        end
                    end
                end
            end
        end
    end

    local matIDs = {}
    for itemID in pairs(neededItemIDs) do
        table_insert(matIDs, itemID)
    end
    table_sort(matIDs)

    local matsPayload = {}
    for _, itemID in ipairs(matIDs) do
        local cnt = GetLocalItemCount(itemID)
        if cnt > 0 then
            matsPayload[itemID] = cnt
        end
        table_insert(sigParts, string_format("m:%d=%d", itemID, cnt))
    end

    local _, classToken = UnitClass and UnitClass("player")
    local sig = tostring(classToken or "") .. "|" .. table_concat(sigParts, ",")
    if not force and sig == lastSentRecipesSig then
        return
    end
    lastSentRecipesSig = sig

    local s = sync.GetSettings and sync.GetSettings()
    local senderFull = (sync.FullName and sync.FullName("player")) or (UnitName and UnitName("player")) or nil
    sync.Broadcast("DELTA_PINNED_RECIPES", {
        pass  = (s and s.passcode ~= "" and s.passcode) or nil,
        init  = isInit and 1 or nil,
        name  = senderFull,
        class = classToken,
        pins  = pinsPayload,
        mats  = next(matsPayload) and matsPayload or nil,
    }, true, false)
end

ScheduleRecipesSyncBroadcast = function(force, isInit)
    if not IsSyncActive() then return end
    if force then
        lastSentRecipesSig = nil
    end
    if recipesBroadcastQueued then return end
    recipesBroadcastQueued = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.35, function()
            recipesBroadcastQueued = false
            BroadcastPinnedRecipes(force, isInit)
        end)
    else
        recipesBroadcastQueued = false
        BroadcastPinnedRecipes(force, isInit)
    end
end

local function RequestRemoteRecipeUnpin(peerKey, spellID)
    spellID = tonumber(spellID)
    if not spellID then return end
    local peer = peerKey and remotePeerRecipes[peerKey]
    if peer and type(peer.pins) == "table" then
        for i = #peer.pins, 1, -1 do
            if tonumber(peer.pins[i].id) == spellID then
                table.remove(peer.pins, i)
            end
        end
    end
    if IsSyncActive() and sfui.sync and sfui.sync.Broadcast then
        local s = sfui.sync.GetSettings and sfui.sync.GetSettings()
        sfui.sync.Broadcast("DELTA_RECIPE_UNPIN", {
            pass   = (s and s.passcode ~= "" and s.passcode) or nil,
            target = peer and peer.name or peerKey,
            id     = spellID,
        }, true, false)
    end
    if CamelotRecipesModule and CamelotRecipesModule.MarkDirty then
        CamelotRecipesModule:MarkDirty(0)
    end
    if sfui.tracker and sfui.tracker.RequestRefresh then
        sfui.tracker.RequestRefresh(0)
    end
end

local function HandleRecipesSyncMessage(sender, msgType, data)
    if type(data) ~= "table" then return end
    if msgType == "DELTA_PINNED_RECIPES" then
        local displaySender = (type(data.name) == "string" and data.name ~= "") and data.name or sender
        local peerKey = CleanPeerKey(displaySender)
        if peerKey == "" then return end

        local prevPeer = remotePeerRecipes[peerKey]
        local prevPinCount = (prevPeer and type(prevPeer.pins) == "table") and #prevPeer.pins or 0

        local cleanPins = {}
        if type(data.pins) == "table" then
            for _, p in ipairs(data.pins) do
                local id = tonumber(p and p.id)
                if id and id > 0 then
                    local cleanReqs = nil
                    if type(p.reqs) == "table" then
                        for k, v in pairs(p.reqs) do
                            local itemID = tonumber(k)
                            local reqCnt = tonumber(v)
                            if itemID and reqCnt and reqCnt > 0 then
                                cleanReqs = cleanReqs or {}
                                cleanReqs[itemID] = reqCnt
                            end
                        end
                    end
                    table_insert(cleanPins, {
                        id   = id,
                        name = p.name and tostring(p.name) or nil,
                        rec  = (tonumber(p.rec) == 1) and 1 or nil,
                        reqs = cleanReqs,
                    })
                end
            end
        end

        local cleanMats = {}
        if type(data.mats) == "table" then
            for k, v in pairs(data.mats) do
                local itemID = tonumber(k)
                local cnt = tonumber(v)
                if itemID and cnt and cnt > 0 then
                    cleanMats[itemID] = cnt
                end
            end
        end

        remotePeerRecipes[peerKey] = {
            name      = displaySender,
            class     = data.class,
            pins      = cleanPins,
            mats      = cleanMats,
            updatedAt = (GetTime and GetTime()) or 0,
        }

        if CamelotRecipesModule and CamelotRecipesModule.MarkDirty then
            CamelotRecipesModule:MarkDirty(0)
        end
        if sfui.tracker and sfui.tracker.RequestRefresh then
            sfui.tracker.RequestRefresh(0.02)
        end

        -- Reply if peer initialized or added new pinned recipes so they receive our bag/bank reagent counts
        if tonumber(data.init) == 1 or #cleanPins > prevPinCount then
            ScheduleRecipesSyncBroadcast(false, false)
        end
    elseif msgType == "DELTA_RECIPE_UNPIN" then
        local spellID = tonumber(data.id)
        if not spellID then return end
        local myFull = (sfui.sync and sfui.sync.FullName and sfui.sync.FullName("player"))
            or (UnitName and UnitName("player"))
            or ""
        local myKey = CleanPeerKey(myFull)
        local targetKey = data.target and CleanPeerKey(data.target) or ""
        if (targetKey == "" or targetKey == myKey) and sfui.recipes.IsRecipePinned(spellID) then
            sfui.recipes.TogglePinRecipe(spellID)
        end
    end
end

sfui.recipes.BroadcastPinnedRecipes = function(force)
    ScheduleRecipesSyncBroadcast(force == true, force == true)
end
sfui.recipes.HandleSyncMessage = HandleRecipesSyncMessage

-- ─────────────────────────────────────────────────────────
--  OBJECTIVE TRACKER MODULE
-- ─────────────────────────────────────────────────────────
CamelotRecipesModule = {
    id       = "camelot_recipes",
    priority = 61,
    events   = {
        "BAG_UPDATE_DELAYED",
        "PLAYER_ENTERING_WORLD",
        "GROUP_ROSTER_UPDATE",
        "TRACKED_RECIPE_UPDATE",
        "CURRENCY_DISPLAY_UPDATE",
        "TRADE_SKILL_SHOW",
    },
}

function CamelotRecipesModule:Init(engine)
    self.engine = engine
    if sfui.events and sfui.events.RegisterMessage then
        sfui.events.RegisterMessage("SFUI_RECIPE_PINNED_CHANGED", function()
            self:MarkDirty(0)
            sfui.tracker.RequestRefresh(0)
        end)
        sfui.events.RegisterMessage("SFUI_SYNC_STATUS_UPDATED", function(_, key)
            if key == "PACKET" then return end
            self:MarkDirty(0.02)
            sfui.tracker.RequestRefresh(0.02)
            ScheduleRecipesSyncBroadcast(true, false)
        end)
    end

    if sfui.sync and sfui.sync.multibox and sfui.sync.multibox.RegisterPartySubmodule then
        sfui.sync.multibox.RegisterPartySubmodule({
            Enable = function()
                ScheduleRecipesSyncBroadcast(true, true)
                self:MarkDirty(0.02)
                sfui.tracker.RequestRefresh(0.02)
            end,
            Disable = function()
                self:MarkDirty(0.02)
                sfui.tracker.RequestRefresh(0.02)
            end,
            Refresh = function()
                ScheduleRecipesSyncBroadcast(false, false)
                self:MarkDirty(0.02)
                sfui.tracker.RequestRefresh(0.02)
            end,
        })
    end
end

function CamelotRecipesModule:IsEnabled()
    return not (SfuiDB and SfuiDB.recipesTrackPinned == false)
end

function CamelotRecipesModule:OnEvent(event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        if C_Timer and C_Timer.After then
            C_Timer.After(2.5, function()
                ScheduleRecipesSyncBroadcast(true, true)
            end)
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        ScheduleRecipesSyncBroadcast(true, true)
    elseif event == "BAG_UPDATE_DELAYED" or event == "TRACKED_RECIPE_UPDATE" then
        ScheduleRecipesSyncBroadcast(false, false)
    end

    self:MarkDirty(0.05)
    sfui.tracker.RequestRefresh(0.05)
    if event == "TRACKED_RECIPE_UPDATE" then
        if sfui.recipes.browser and sfui.recipes.browser.UpdateList then
            sfui.recipes.browser.UpdateList()
        end
    end
end

function CamelotRecipesModule:BuildBlocks(container)
    local db = sfui.recipes_camelot and sfui.recipes_camelot.recipes

    -- 1. Gather local pinned recipes
    local trackedMap = CollectLocalTrackedMap()
    local myFull = (sfui.sync and sfui.sync.FullName and sfui.sync.FullName("player"))
        or (UnitName and UnitName("player"))
        or "player"
    local _, myClass = UnitClass and UnitClass("player")
    local myColoredName = FormatColoredName(myFull, myClass)

    for _, entry in pairs(trackedMap) do
        entry.hasLocal = true
        entry.owners = { myColoredName }
    end

    -- 2. Merge active synced peers' pinned recipes & collect visible peers for reagent counts
    local visiblePeers = {}
    if IsSyncActive() and next(remotePeerRecipes) then
        local peerKeys = {}
        for k, peer in pairs(remotePeerRecipes) do
            if IsPeerRecipesVisible(k, peer) then
                table_insert(peerKeys, k)
            end
        end
        table_sort(peerKeys)

        for _, peerKey in ipairs(peerKeys) do
            local peer = remotePeerRecipes[peerKey]
            local peerColored = FormatColoredName(peer.name, peer.class)
            table_insert(visiblePeers, {
                key         = peerKey,
                peer        = peer,
                coloredName = peerColored,
            })
            if type(peer.pins) == "table" then
                for _, remPin in ipairs(peer.pins) do
                    local numID = tonumber(remPin.id)
                    if numID and numID > 0 then
                        local entry = trackedMap[numID]
                        if not entry then
                            entry = {
                                recipeID       = numID,
                                hasLocal       = false,
                                isRecraft      = (remPin.rec == 1),
                                remoteName     = remPin.name,
                                remoteReqs     = remPin.reqs,
                                primaryPeerKey = peerKey,
                                owners         = {},
                            }
                            trackedMap[numID] = entry
                        else
                            if not entry.remoteName and remPin.name then
                                entry.remoteName = remPin.name
                            end
                            if not entry.remoteReqs and remPin.reqs then
                                entry.remoteReqs = remPin.reqs
                            end
                        end
                        entry.hasRemote = true
                        table_insert(entry.owners, peerColored)
                    end
                end
            end
        end
    end

    if not next(trackedMap) then
        return nil
    end

    local recipeList = {}
    for numID, entry in pairs(trackedMap) do
        entry.recipeData = db and db[numID]
        table_insert(recipeList, entry)
    end

    if #recipeList == 0 then
        return nil
    end

    table_sort(recipeList, function(a, b)
        local nameA = (a.recipeData and a.recipeData.name) or a.remoteName or ""
        local nameB = (b.recipeData and b.recipeData.name) or b.remoteName or ""
        if nameA == "" and C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic then
            local schA = C_TradeSkillUI.GetRecipeSchematic(a.recipeID, a.isRecraft or false)
            nameA = (schA and schA.name) or ""
        end
        if nameB == "" and C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic then
            local schB = C_TradeSkillUI.GetRecipeSchematic(b.recipeID, b.isRecraft or false)
            nameB = (schB and schB.name) or ""
        end
        return nameA:lower() < nameB:lower()
    end)

    local blocks = {}

    for _, entry in ipairs(recipeList) do
        local spellID = entry.recipeID
        local r = entry.recipeData
        local isRecraft = entry.isRecraft or false
        local reagents, schematic = ExtractRecipeReagents(spellID, r, isRecraft, entry.remoteReqs)

        local recipeName = (r and r.name)
            or (schematic and schematic.name and schematic.name ~= "" and schematic.name)
            or (C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(spellID) and C_TradeSkillUI.GetRecipeInfo(spellID).name)
            or entry.remoteName
            or ("recipe #" .. tostring(spellID))

        local lines = {}
        local tooltipBreakdowns = {}
        local allReagentsMet = true
        local hasReagents = false

        -- 1. Source Line (show vendor / trainer / drop if unlearned on local character and pinned locally)
        local isLearned = C_TradeSkillUI and C_TradeSkillUI.IsRecipeProfessionLearned and C_TradeSkillUI.IsRecipeProfessionLearned(spellID)
        local firstSource = r and sfui.recipes.GetFirstNonHostileSource and sfui.recipes.GetFirstNonHostileSource(r)
        if not firstSource and r and r.sources and r.sources[1] then
            firstSource = r.sources[1]
        end

        if entry.hasLocal and firstSource and not isLearned then
            local st = firstSource.type or "source"
            local sName = firstSource.name or firstSource.desc or st
            local loc = firstSource.zone or ""
            local srcText = ""
            if st == "trainer" then
                srcText = "trainer: " .. (sName ~= "trainer" and sName or (loc ~= "" and loc or "major city"))
            elseif st == "vendor" then
                srcText = "vendor: " .. sName .. (loc ~= "" and (" (" .. loc .. ")") or "")
            elseif st == "drop" then
                srcText = "drop: " .. sName .. (loc ~= "" and (" (" .. loc .. ")") or "")
            elseif st == "quest" then
                srcText = "quest: " .. sName
            else
                srcText = st .. ": " .. sName .. (loc ~= "" and (" (" .. loc .. ")") or "")
            end

            table_insert(lines, {
                text  = srcText:lower(),
                color = { 0.70, 0.70, 0.75, 1.0 },
            })

            if firstSource.mapID and firstSource.x and firstSource.y then
                local coordText = string_format("coords: %.1f, %.1f", firstSource.x * 100, firstSource.y * 100)
                table_insert(lines, {
                    text  = coordText,
                    color = { 0.55, 0.80, 0.95, 1.0 },
                })
            end
        end

        -- 2. Reagents List with Combined Local + Synced Peer Bag/Bank Counts
        for _, rg in ipairs(reagents) do
            local req = rg.req or 1
            local itemID = rg.itemID
            local currencyID = rg.currencyID
            local rName = nil
            local localCount = 0
            local peerCount = 0
            local holderParts = nil

            if itemID then
                localCount = GetLocalItemCount(itemID)
                rName = ResolveItemName(itemID)
                if localCount > 0 then
                    holderParts = { string_format("%s: %d", myColoredName, localCount) }
                end
                for _, vp in ipairs(visiblePeers) do
                    local pCnt = vp.peer.mats and tonumber(vp.peer.mats[itemID]) or 0
                    if pCnt > 0 then
                        peerCount = peerCount + pCnt
                        holderParts = holderParts or {}
                        table_insert(holderParts, string_format("%s: %d", vp.coloredName, pCnt))
                    end
                end
                if (localCount + peerCount) < req and sfui.alts and sfui.alts.GetAccountItemSummary then
                    local altSum = sfui.alts.GetAccountItemSummary(itemID, true)
                    if altSum and altSum.totalAlts and altSum.totalAlts > 0 then
                        rg._altCount = altSum.totalAlts
                        holderParts = holderParts or {}
                        for _, aEntry in ipairs(altSum.alts or {}) do
                            table_insert(holderParts, string_format("%s (alt): %d", aEntry.coloredName, aEntry.total))
                        end
                    else
                        rg._altCount = nil
                    end
                else
                    rg._altCount = nil
                end
            elseif currencyID then
                local cInfo = sfui.common.get_currency_info(currencyID)
                if cInfo then
                    rName = cInfo.name
                    localCount = cInfo.quantity or 0
                else
                    rName = "currency #" .. tostring(currencyID)
                end
            end

            if rName and rName ~= "" then
                hasReagents = true
                local totalCount = localCount + peerCount
                local isDone = (totalCount >= req)
                if not isDone then
                    allReagentsMet = false
                end

                local lineText
                if peerCount > 0 then
                    lineText = string_format("%s (%d/%d · %d+%d)", rName:lower(), totalCount, req, localCount, peerCount)
                elseif rg._altCount and rg._altCount > 0 then
                    lineText = string_format("%s (%d/%d · +%d alts)", rName:lower(), totalCount, req, rg._altCount)
                else
                    lineText = string_format("%s (%d/%d)", rName:lower(), totalCount, req)
                end

                table_insert(lines, {
                    text      = lineText,
                    completed = isDone,
                })
                table_insert(tooltipBreakdowns, {
                    name      = rName:lower(),
                    total     = totalCount,
                    req       = req,
                    completed = isDone,
                    holders   = holderParts and table_concat(holderParts, ", ") or nil,
                })
            end
        end

        local isComplete = (hasReagents and allReagentsMet)
        local titleColor = isComplete and { 0.20, 1.00, 0.35, 1.0 } or { 1.00, 0.72, 0.35, 1.0 }
        local prefix = isComplete and "[ready] " or (isRecraft and "[recraft] " or "[recipe] ")
        local ownerSuffix = ""
        if not entry.hasLocal and entry.owners and #entry.owners > 0 then
            ownerSuffix = " · " .. table_concat(entry.owners, ", ")
        end
        local displayName = prefix .. recipeName:lower() .. ownerSuffix

        table_insert(blocks, {
            id         = "rec_" .. tostring(spellID) .. (isRecraft and "_r" or ""),
            title      = displayName,
            titleColor = titleColor,
            lines      = lines,
            OnClick    = function(block, btn)
                if btn == "RightButton" or (IsShiftKeyDown and IsShiftKeyDown()) then
                    if entry.hasLocal then
                        if entry.isSfuiPinned then
                            sfui.recipes.TogglePinRecipe(spellID)
                        end
                        if entry.isBlizzTracked and C_TradeSkillUI and C_TradeSkillUI.SetRecipeTracked then
                            C_TradeSkillUI.SetRecipeTracked(spellID, false, isRecraft)
                        end
                    elseif entry.primaryPeerKey then
                        RequestRemoteRecipeUnpin(entry.primaryPeerKey, spellID)
                    end
                    sfui.tracker.RequestRefresh(0.05)
                    return
                end

                if not (InCombatLockdown and InCombatLockdown()) then
                    if isLearned and C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then
                        C_TradeSkillUI.OpenRecipe(spellID)
                    elseif sfui.recipes and sfui.recipes.OpenBrowserToRecipe then
                        sfui.recipes.OpenBrowserToRecipe(spellID)
                    end
                end
            end,
            tooltip    = function(tip, owner, bData)
                tip:AddLine(recipeName:lower(), titleColor[1], titleColor[2], titleColor[3])
                local profName = (r and r.profession) or (r and r.skillID and sfui.recipes.GetProfessionName and sfui.recipes.GetProfessionName(r.skillID))
                if profName then
                    local minSkill = r.minSkill or (r.colors and r.colors[1]) or 0
                    tip:AddLine(string_format("%s (rank %d)", profName:lower(), minSkill), 0.70, 0.70, 0.70)
                end
                if entry.owners and #entry.owners > 0 and (entry.hasRemote or #entry.owners > 1) then
                    tip:AddLine("pinned by: " .. table_concat(entry.owners, ", "), 0.80, 0.85, 0.95)
                end
                if isComplete then
                    tip:AddLine("all required crafting materials collected", 0.20, 1.00, 0.35, true)
                elseif hasReagents then
                    tip:AddLine("crafting materials incomplete", 1.00, 0.72, 0.35, true)
                end
                if #tooltipBreakdowns > 0 then
                    tip:AddLine(" ")
                    for _, bd in ipairs(tooltipBreakdowns) do
                        local rCol, gCol, bCol = 0.85, 0.85, 0.85
                        if bd.completed then rCol, gCol, bCol = 0.30, 0.90, 0.35 end
                        local rightTxt = string_format("%d / %d", bd.total, bd.req)
                        tip:AddDoubleLine("  • " .. bd.name, rightTxt, rCol, gCol, bCol, rCol, gCol, bCol)
                        if bd.holders then
                            tip:AddLine("      " .. bd.holders, 0.70, 0.78, 0.88, true)
                        end
                    end
                end
                tip:AddLine(" ")
                tip:AddLine("|cff888888left-click: open recipe / catalogue|r", 1, 1, 1)
                tip:AddLine("|cff888888shift-click or right-click: unpin recipe|r", 1, 1, 1)
            end,
        })
    end

    if #blocks > 0 then
        return {
            {
                id     = "camelot_recipes",
                title  = "tracked recipes",
                color  = { 1.00, 0.75, 0.35 },
                blocks = blocks,
            }
        }
    end

    return nil
end

sfui.tracker.RegisterModule(CamelotRecipesModule)
return CamelotRecipesModule
