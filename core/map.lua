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
local pairs            = _G.pairs
local ipairs           = _G.ipairs
local rawget           = _G.rawget

local safe_nop = _G.nop or function() end
map.ProtectPin   = safe_nop
map.SweepAllMaps = safe_nop

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

--- Safely sets or clears the supertracked quest ID outside hardware click / event taint stacks.
--- @param questID number|nil quest ID to supertrack, or 0/nil to clear
function map.SetSuperTrackedQuestID(questID)
    if is_in_combat() then return end
    local qID = tonumber(questID) or 0
    C_Timer.After(0, function()
        if is_in_combat() then return end
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
            pcall(C_SuperTrack.SetSuperTrackedQuestID, qID)
        end
    end)
end

--- Safely enables or disables user waypoint supertracking outside hardware click / event taint stacks.
--- @param enabled boolean
function map.SetSuperTrackedUserWaypoint(enabled)
    if is_in_combat() then return end
    local state = enabled and true or false
    C_Timer.After(0, function()
        if is_in_combat() then return end
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, state)
        end
    end)
end

--- Safely sets or clears a supertracked map pin outside hardware click / event taint stacks.
--- @param pinType number Enum.SuperTrackingMapPinType
--- @param pinID number|nil pin ID or nil/0 to clear
function map.SetSuperTrackedMapPin(pinType, pinID)
    if is_in_combat() then return end
    C_Timer.After(0, function()
        if is_in_combat() then return end
        if not C_SuperTrack then return end
        if pinID and pinID > 0 and C_SuperTrack.SetSuperTrackedMapPin then
            pcall(C_SuperTrack.SetSuperTrackedMapPin, pinType, pinID)
        elseif C_SuperTrack.ClearSuperTrackedMapPin then
            pcall(C_SuperTrack.ClearSuperTrackedMapPin, pinType)
        end
    end)
end

--- Safely sets supertracked content (achievements, transmog, etc.) outside taint stacks.
--- @param trackableType number
--- @param trackableID number
function map.SetSuperTrackedContent(trackableType, trackableID)
    if is_in_combat() then return end
    C_Timer.After(0, function()
        if is_in_combat() then return end
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedContent then
            pcall(C_SuperTrack.SetSuperTrackedContent, trackableType, trackableID)
        end
    end)
end

--- Safely sets a user waypoint on the map and supertracks it outside taint stacks.
--- Defers C_Map.SetUserWaypoint via C_Timer.After(0) to prevent
--- Button:SetPassThroughButtons() action blocked errors in Blizzard waypoint data providers.
--- @param mapID number
--- @param x number
--- @param y number
--- @param label string|nil optional waypoint name for confirmation chat message
--- @return boolean isSuccess
function map.SetUserWaypoint(mapID, x, y, label)
    if not mapID or not x or not y or is_in_combat() then return false end
    local UiMapPoint = _G.UiMapPoint
    if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
        return false
    end

    C_Timer.After(0, function()
        if is_in_combat() then return end
        local ok, pt = pcall(UiMapPoint.CreateFromCoordinates, mapID, x, y)
        if ok and pt then
            pcall(C_Map.SetUserWaypoint, pt)
        end
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
        end
    end)

    if label and sfui.common and sfui.common.print then
        sfui.common.print("waypoint set for " .. label)
    end
    return true
end

-- ────────────────────────────────────────────────────────────────────────────
-- MapCanvas Protected Method Combat Guards
-- ────────────────────────────────────────────────────────────────────────────
-- In modern WoW (11.0 / 12.0+), Button:SetPassThroughButtons() and
-- Frame:SetPropagateMouseClicks() are protected widget methods.
-- During combat lockdown, if the world map is opened, MapCanvasPinMixin and
-- SuperTrackablePinMixin attempt to invoke these methods on every acquired pin.
-- If any addon execution or taint exists in the UI environment, Blizzard's C
-- engine blocks these calls, spawning dozens of Action Blocked errors.
--
-- We neutralize this by gating pin passthrough and mouse propagation updates
-- behind not InCombatLockdown(). When combat ends (PLAYER_REGEN_ENABLED),
-- any open map is cleanly refreshed outside combat lockdown to synchronize state.
local TARGET_PIN_MIXINS = {
    "MapCanvasPinMixin",
    "SuperTrackablePinMixin",
    "BaseMapPoiPinMixin",
    "AreaPOIPinMixin",
    "SuperTrackablePoiPinMixin",
    "SuperTrackableVignettePinMixin",
    "QuestOfferPinMixin",
    "QuestPinMixin",
    "WorldQuestPinMixin",
    "WorldQuestSpellEffectPinMixin",
    "BonusObjectivePinMixin",
    "VignettePinBaseMixin",
    "ScenarioPinMixin",
    "WaypointLocationPinMixin",
    "SuperTrackWaypointPinMixin",
    "GroupMembersPinMixin",
    "MapExplorationPinMixin",
    "FlightMap_FlightPointPinMixin",
    "EncounterJournalPinMixin",
    "ContentTrackingPinMixin",
    "DungeonEntrancePinMixin",
    "DelveEntrancePinMixin",
}

local function guard_mixin(mixin)
    if not mixin or type(mixin) ~= "table" then return end

    if mixin.CheckMouseButtonPassthrough and not mixin._sfuiGuardedPassthrough then
        local orig = mixin.CheckMouseButtonPassthrough
        mixin.CheckMouseButtonPassthrough = function(self, ...)
            if InCombatLockdown and InCombatLockdown() then return end
            return orig(self, ...)
        end
        mixin._sfuiGuardedPassthrough = true
    end

    if mixin.UpdateMousePropagation and not mixin._sfuiGuardedPropagation then
        local orig = mixin.UpdateMousePropagation
        mixin.UpdateMousePropagation = function(self, ...)
            if InCombatLockdown and InCombatLockdown() then return end
            return orig(self, ...)
        end
        mixin._sfuiGuardedPropagation = true
    end
end

local function guard_pin_instance(pin)
    if not pin or type(pin) ~= "table" then return end

    if rawget(pin, "CheckMouseButtonPassthrough") and not pin._sfuiGuardedPassthrough then
        local orig = pin.CheckMouseButtonPassthrough
        pin.CheckMouseButtonPassthrough = function(self, ...)
            if InCombatLockdown and InCombatLockdown() then return end
            return orig(self, ...)
        end
        pin._sfuiGuardedPassthrough = true
    end

    if rawget(pin, "UpdateMousePropagation") and not pin._sfuiGuardedPropagation then
        local orig = pin.UpdateMousePropagation
        pin.UpdateMousePropagation = function(self, ...)
            if InCombatLockdown and InCombatLockdown() then return end
            return orig(self, ...)
        end
        pin._sfuiGuardedPropagation = true
    end
end

local function guard_all_map_pin_mixins()
    -- 1. Explicit target Blizzard mixins
    for _, name in ipairs(TARGET_PIN_MIXINS) do
        local mixin = _G[name]
        if type(mixin) == "table" then
            guard_mixin(mixin)
        end
    end

    -- 2. Dynamically guard any other pin mixin in _G ending with PinMixin
    for k, v in pairs(_G) do
        if type(k) == "string" and type(v) == "table" and k:find("PinMixin$") then
            guard_mixin(v)
        end
    end

    -- 3. Guard any active pins already created in WorldMapFrame pools
    local wmf = _G.WorldMapFrame
    if wmf and wmf.pinPools then
        for _, pool in pairs(wmf.pinPools) do
            if type(pool) == "table" and pool.EnumerateActive then
                for pin in pool:EnumerateActive() do
                    guard_pin_instance(pin)
                end
            end
        end
    end
end

local guardFrame = _G.CreateFrame and _G.CreateFrame("Frame")
if guardFrame then
    guardFrame:RegisterEvent("ADDON_LOADED")
    guardFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    guardFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    guardFrame:SetScript("OnEvent", function(_, event, arg1)
        if event == "ADDON_LOADED" then
            if arg1 and (arg1 == "Blizzard_MapCanvas" or arg1 == "Blizzard_SharedMapDataProviders" or arg1 == "Blizzard_WorldMap") then
                guard_all_map_pin_mixins()
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            guard_all_map_pin_mixins()
        elseif event == "PLAYER_REGEN_ENABLED" then
            local wmf = _G.WorldMapFrame
            if wmf and wmf:IsShown() and wmf.RefreshAllDataProviders then
                pcall(wmf.RefreshAllDataProviders, wmf)
            end
        end
    end)
end

-- Run immediately on load for already registered mixins
guard_all_map_pin_mixins()

-- Export convenience aliases to sfui.common
sfui.common = sfui.common or {}
sfui.common.open_quest_map            = map.OpenToQuest
sfui.common.toggle_world_map          = map.ToggleWorldMap
sfui.common.open_world_map            = map.OpenWorldMap
sfui.common.open_map_event_poi        = map.OpenToEventPoi
sfui.common.get_map_canvas            = map.GetCanvas
sfui.common.get_current_map_id        = map.GetCurrentMapID
sfui.common.set_super_tracked_quest_id = map.SetSuperTrackedQuestID
sfui.common.set_super_tracked_waypoint = map.SetSuperTrackedUserWaypoint
sfui.common.set_super_tracked_map_pin  = map.SetSuperTrackedMapPin
sfui.common.set_super_tracked_content  = map.SetSuperTrackedContent
sfui.common.set_user_waypoint         = map.SetUserWaypoint
