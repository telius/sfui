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
local hooksecurefunc   = _G.hooksecurefunc

-- ────────────────────────────────────────────────────────────────────────────
-- MapCanvas Pin Protection (prevents Blizzard MapCanvas protected API taint)
-- In Retail 11.0 / 12.0, Button:SetPassThroughButtons, Frame:SetPropagateMouseClicks,
-- and Frame:SetPropagateMouseMotion are protected widget methods. Blizzard's
-- MapCanvasPinMixin:CheckMouseButtonPassthrough calls self:SetPassThroughButtons(),
-- and SuperTrackablePinMixin:UpdateMousePropagation calls self:SetPropagateMouseClicks(),
-- which trigger ADDON_ACTION_BLOCKED whenever a map pin is acquired or updated
-- while an addon taint is present on the execution stack.
-- Stubbing these methods on mixins and frame instances safely intercepts the calls
-- with a no-op, preventing the protected C methods from ever being invoked.
-- ────────────────────────────────────────────────────────────────────────────
local safe_nop = _G.nop or function() end

local protected_mixins = {}

local function protect_pin(pin)
    if pin and (type(pin) == "table" or type(pin) == "userdata") then
        pin.SetPassThroughButtons   = safe_nop
        pin.SetPropagateMouseClicks = safe_nop
        pin.SetPropagateMouseMotion = safe_nop
    end
end
map.ProtectPin = protect_pin

local function protect_mixin(mixin)
    if not mixin or type(mixin) ~= "table" or protected_mixins[mixin] then
        return
    end
    protected_mixins[mixin] = true
    mixin.SetPassThroughButtons   = safe_nop
    mixin.SetPropagateMouseClicks = safe_nop
    mixin.SetPropagateMouseMotion = safe_nop

    if type(mixin.SetOwningMap) == "function" then
        pcall(hooksecurefunc, mixin, "SetOwningMap", protect_pin)
    end
    if type(mixin.OnAcquired) == "function" then
        pcall(hooksecurefunc, mixin, "OnAcquired", protect_pin)
    end
    if type(mixin.OnLoad) == "function" then
        pcall(hooksecurefunc, mixin, "OnLoad", protect_pin)
    end
    if type(mixin.CheckMouseButtonPassthrough) == "function" then
        pcall(hooksecurefunc, mixin, "CheckMouseButtonPassthrough", protect_pin)
    end
    if type(mixin.UpdateMousePropagation) == "function" then
        pcall(hooksecurefunc, mixin, "UpdateMousePropagation", protect_pin)
    end
end

local function scan_and_protect_all_pin_mixins()
    if _G.MapCanvasPinMixin then
        protect_mixin(_G.MapCanvasPinMixin)
    end
    if _G.SuperTrackablePinMixin then
        protect_mixin(_G.SuperTrackablePinMixin)
    end
    if _G.SuperTrackablePoiPinMixin then
        protect_mixin(_G.SuperTrackablePoiPinMixin)
    end
    if _G.WatchedFactionToggleFrameMixin then
        protect_mixin(_G.WatchedFactionToggleFrameMixin)
    end
    for k, v in pairs(_G) do
        if type(k) == "string" and type(v) == "table" and not protected_mixins[v] then
            if k:find("PinMixin$") or k:find("MapCanvas.*Pin")
                or type(v.CheckMouseButtonPassthrough) == "function"
                or type(v.UpdateMousePropagation) == "function"
                or (type(v.SetOwningMap) == "function" and type(v.GetOwningMap) == "function") then
                protect_mixin(v)
            end
        end
    end
end

local function protect_pool(pool)
    if not pool or type(pool) ~= "table" then return end
    if pool.activeObjects and type(pool.activeObjects) == "table" then
        for obj in pairs(pool.activeObjects) do
            protect_pin(obj)
        end
    end
    if pool.inactiveObjects and type(pool.inactiveObjects) == "table" then
        for _, obj in ipairs(pool.inactiveObjects) do
            protect_pin(obj)
        end
    end
end

local function sweep_canvas_pins(canvas)
    if not canvas or type(canvas) ~= "table" then return end
    if canvas.pinPools and type(canvas.pinPools) == "table" then
        for _, pool in pairs(canvas.pinPools) do
            protect_pool(pool)
        end
    end
    if type(canvas.ExecuteOnAllPins) == "function" then
        pcall(canvas.ExecuteOnAllPins, canvas, protect_pin)
    end
end

local function sweep_all_maps()
    scan_and_protect_all_pin_mixins()
    if _G.WorldMapFrame then
        sweep_canvas_pins(_G.WorldMapFrame)
    end
    if _G.FlightMapFrame then
        sweep_canvas_pins(_G.FlightMapFrame)
    end
end
map.SweepAllMaps = sweep_all_maps

if _G.MapCanvasMixin and type(_G.MapCanvasMixin.AcquirePin) == "function" then
    pcall(hooksecurefunc, _G.MapCanvasMixin, "AcquirePin", function(self)
        sweep_canvas_pins(self)
    end)
end

if _G.WorldMapFrame and type(_G.WorldMapFrame.HookScript) == "function" then
    pcall(_G.WorldMapFrame.HookScript, _G.WorldMapFrame, "OnShow", sweep_all_maps)
end

local mapCanvasEventFrame = _G.CreateFrame and _G.CreateFrame("Frame")
if mapCanvasEventFrame then
    mapCanvasEventFrame:RegisterEvent("ADDON_LOADED")
    mapCanvasEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    mapCanvasEventFrame:SetScript("OnEvent", function()
        sweep_all_maps()
    end)
end

sweep_all_maps()

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

    sweep_all_maps()
    C_Timer.After(0, function()
        if is_in_combat() then return end
        sweep_all_maps()

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

    sweep_all_maps()
    C_Timer.After(0, function()
        if is_in_combat() then return end
        sweep_all_maps()
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

    sweep_all_maps()
    C_Timer.After(0, function()
        if is_in_combat() then return end
        sweep_all_maps()

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

    sweep_all_maps()
    C_Timer.After(0, function()
        if is_in_combat() then return end
        sweep_all_maps()
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
    sweep_all_maps()
    C_Timer.After(0, function()
        if is_in_combat() then return end
        sweep_all_maps()
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
    sweep_all_maps()
    C_Timer.After(0, function()
        if is_in_combat() then return end
        sweep_all_maps()
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
    sweep_all_maps()
    C_Timer.After(0, function()
        if is_in_combat() then return end
        sweep_all_maps()
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
    sweep_all_maps()
    C_Timer.After(0, function()
        if is_in_combat() then return end
        sweep_all_maps()
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedContent then
            pcall(C_SuperTrack.SetSuperTrackedContent, trackableType, trackableID)
        end
    end)
end

--- Safely sets a user waypoint on the map and supertracks it outside taint stacks.
--- Sweeps map pins and defers C_Map.SetUserWaypoint via C_Timer.After(0) to prevent
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

    sweep_all_maps()

    C_Timer.After(0, function()
        if is_in_combat() then return end
        sweep_all_maps()
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


