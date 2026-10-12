local addonName, addon = ...
sfui = sfui or {}
sfui.map = sfui.map or {}
local map = sfui.map

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/core/map.lua
--  Protected Map Navigation & Taint Boundary Engine
--
--  Defers map, quest log, and waypoint frame transitions outside of hardware
--  click execution stacks via C_Timer.After(0).
--  This completely prevents Blizzard MapCanvas data providers and pins from
--  executing in tainted addon stacks, eliminating Action Blocked errors on
--  protected methods such as Button:SetPassThroughButtons().
-- ══════════════════════════════════════════════════════════════════════════════

local _G = _G
local InCombatLockdown = _G.InCombatLockdown
local C_Timer          = _G.C_Timer
local C_QuestLog       = _G.C_QuestLog
local C_SuperTrack     = _G.C_SuperTrack
local C_Map            = _G.C_Map
local pcall            = _G.pcall
local type             = _G.type

--- Checks whether the player is in combat via central state or engine APIs.
--- @return boolean inCombat
local function is_in_combat()
    if sfui.common and sfui.common.is_in_combat and sfui.common.is_in_combat() then
        return true
    end
    if InCombatLockdown and InCombatLockdown() then
        return true
    end
    if _G.UnitAffectingCombat and _G.UnitAffectingCombat("player") then
        return true
    end
    return false
end
map.IsInCombat = is_in_combat

--- Retrieves the active map canvas container frame across game versions.
--- @return table|nil canvas
function map.GetCanvas()
    local wmf = _G.WorldMapFrame
    if not wmf then return nil end
    if type(wmf.GetCanvas) == "function" then
        local ok, canvas = pcall(wmf.GetCanvas, wmf)
        if ok and canvas then return canvas end
    end
    if wmf.ScrollContainer then
        return wmf.ScrollContainer.Child or wmf.ScrollContainer
    end
    return wmf
end

--- Retrieves the currently viewed mapID or player location mapID.
--- @return number|nil mapID
function map.GetCurrentMapID()
    local wmf = _G.WorldMapFrame
    if wmf and wmf.GetMapID then
        local ok, id = pcall(wmf.GetMapID, wmf)
        if ok and id then return id end
    end
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
        if ok and id then return id end
    end
    return nil
end

--- Safely opens quest details in the WorldMap / QuestMapFrame or Classic QuestLog.
--- Execution is deferred to the next tick via C_Timer.After(0) to break hardware click taint stacks.
--- @param questID number
--- @param questLogIndex number|nil optional quest log index fallback for classic clients
--- @param superTrack boolean|nil optional flag to supertrack the quest (defaults to true)
function map.OpenToQuest(questID, questLogIndex, superTrack)
    if not questID or is_in_combat() then return end

    C_Timer.After(0, function()
        if is_in_combat() then return end

        if C_QuestLog and C_QuestLog.SetSelectedQuest and questID then
            pcall(C_QuestLog.SetSelectedQuest, questID)
        end

        if superTrack ~= false and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID and questID then
            pcall(C_SuperTrack.SetSuperTrackedQuestID, questID)
        end

        if _G.QuestMapFrame_OpenToQuestDetails and questID then
            pcall(_G.QuestMapFrame_OpenToQuestDetails, questID)
        elseif _G.QuestLog_OpenToQuest and questLogIndex then
            pcall(_G.QuestLog_OpenToQuest, questLogIndex)
        elseif _G.OpenQuestLog then
            pcall(_G.OpenQuestLog)
        elseif _G.ToggleWorldMap then
            pcall(_G.ToggleWorldMap)
        end
    end)
end

--- Safely toggles the WorldMap frame.
--- Execution is deferred to the next tick via C_Timer.After(0) to break hardware click taint stacks.
function map.ToggleWorldMap()
    if is_in_combat() then return end

    C_Timer.After(0, function()
        if is_in_combat() then return end
        if _G.ToggleWorldMap then
            pcall(_G.ToggleWorldMap)
        end
    end)
end

--- Safely opens the WorldMap to a specific mapID, optionally focusing a waypoint.
--- Execution is deferred to the next tick via C_Timer.After(0) to break hardware click taint stacks.
--- @param mapID number|nil
--- @param hasWaypoint boolean|nil optional flag indicating if a waypoint was set
--- @param onOpenCallback function|nil optional callback executed after map is opened
function map.OpenWorldMap(mapID, hasWaypoint, onOpenCallback)
    if is_in_combat() then return end

    C_Timer.After(0, function()
        if is_in_combat() then return end

        if hasWaypoint and _G.OpenMapToUserWaypoint then
            pcall(_G.OpenMapToUserWaypoint)
        elseif _G.OpenWorldMap and mapID then
            pcall(_G.OpenWorldMap, mapID)
        else
            local wmf = _G.WorldMapFrame
            if wmf then
                if not wmf:IsShown() then
                    if _G.ShowUIPanel then
                        pcall(_G.ShowUIPanel, wmf)
                    else
                        wmf:Show()
                    end
                end
                if mapID and wmf.SetMapID then
                    pcall(wmf.SetMapID, wmf, mapID)
                end
            end
        end

        if onOpenCallback then
            pcall(onOpenCallback)
        end
    end)
end

--- Safely opens the WorldMap to a specific event POI (world boss / event).
--- Execution is deferred to the next tick via C_Timer.After(0) to break hardware click taint stacks.
--- @param poiID number|nil
function map.OpenToEventPoi(poiID)
    if not poiID or is_in_combat() then return end

    C_Timer.After(0, function()
        if is_in_combat() then return end
        if _G.OpenMapToEventPoi then
            pcall(_G.OpenMapToEventPoi, poiID)
        elseif _G.ToggleWorldMap then
            pcall(_G.ToggleWorldMap)
        end
    end)
end

-- Export convenience aliases to sfui.common
sfui.common = sfui.common or {}
sfui.common.open_quest_map     = map.OpenToQuest
sfui.common.toggle_world_map   = map.ToggleWorldMap
sfui.common.open_world_map     = map.OpenWorldMap
sfui.common.open_map_event_poi = map.OpenToEventPoi
sfui.common.get_map_canvas     = map.GetCanvas
sfui.common.get_current_map_id = map.GetCurrentMapID

