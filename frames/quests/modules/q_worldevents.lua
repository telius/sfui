local addonName, addon = ...
sfui = sfui or {}
sfui.worldevents = sfui.worldevents or {}

local g      = sfui.config
local common = sfui.common
local cfg    = g.worldevents or {}

-- ─── Localize Globals for Zero-Taint & High Performance ─────────────────────
local _G                   = _G
local C_EventScheduler     = _G.C_EventScheduler
local C_AreaPoiInfo        = _G.C_AreaPoiInfo
local C_SuperTrack         = _G.C_SuperTrack
local C_Map                = _G.C_Map
local C_Timer              = _G.C_Timer
local C_UIWidgetManager    = _G.C_UIWidgetManager
local Enum                 = _G.Enum
local InCombatLockdown     = _G.InCombatLockdown
local time                 = _G.time
local wipe                 = _G.wipe
local ipairs, pairs        = _G.ipairs, _G.pairs
local type                 = _G.type
local tostring, tonumber   = _G.tostring, _G.tonumber
local math_min, math_max   = math.min, math.max
local math_floor           = math.floor
local table_insert         = table.insert
local table_sort           = table.sort
local table_remove         = table.remove
local string_format        = string.format
local issecretvalue        = (common and common.issecretvalue) or _G.issecretvalue or function() return false end

-- ─── UIWidget Visualization Type Constants (Retail 12.1.0 & Fallbacks) ────────
local TYPE_ICON_AND_TEXT     = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.IconAndText) or 0
local TYPE_CAPTURE_BAR       = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.CaptureBar) or 1
local TYPE_STATUS_BAR        = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.StatusBar) or 2
local TYPE_DOUBLE_STATUS_BAR = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.DoubleStatusBar) or 3
local TYPE_TEXT_WITH_STATE   = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.TextWithState) or 8
local TYPE_BULLET_TEXT_LIST  = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.BulletTextList) or 10
local TYPE_TEXTURE_AND_TEXT  = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.TextureAndText) or 12
local TYPE_DISCRETE_STEPS    = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.DiscreteProgressSteps) or 19
local TYPE_SCENARIO_TIMER    = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.ScenarioHeaderTimer) or 20
local TYPE_UNIT_POWER_BAR    = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.UnitPowerBar) or 23
local TYPE_FILL_UP_FRAMES    = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.FillUpFrames) or 24
local TYPE_TEXT_WITH_SUBTEXT = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.TextWithSubtext) or 25
local TYPE_TUG_OF_WAR        = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.TugOfWar) or 28

-- ─── Zero-Allocation Table Pool ─────────────────────────────────────────────
local MAX_TABLE_POOL = 60
local tablePool      = {}

local function AcquireTable()
    local t = table_remove(tablePool) or {}
    wipe(t)
    return t
end

local function ReleaseTable(t)
    if type(t) ~= "table" then return end
    wipe(t)
    if #tablePool < MAX_TABLE_POOL then
        tablePool[#tablePool + 1] = t
    end
end

-- ─── Module State & Caching ─────────────────────────────────────────────────
local cachedEvents       = {}
local stagingEvents      = {}
local seenPoi            = {}
local poiNameCache       = {}
local poiAtlasCache      = {}
local poiZoneCache       = {}
local poiMapCache        = {}
local poiWidgetSetCache  = {}
local isDirty            = true
local lastUpdateTime     = 0
local reminderCount      = 0

local function FormatTimerSeconds(sec)
    if not sec or issecretvalue(sec) then return "now" end
    if sec <= 0 then return "now" end
    sec = math_floor(sec)
    if sec >= 3600 then
        local h = math_floor(sec / 3600)
        local m = math_floor((sec % 3600) / 60)
        return (m > 0) and string_format("%dh %dm", h, m) or string_format("%dh", h)
    elseif sec >= 60 then
        return string_format("%dm", math_floor(sec / 60))
    else
        return string_format("%ds", sec)
    end
end

-- ─── Multi-Tier Progress Extraction Helpers ─────────────────────────────────
-- Extracts clean percentage and values from widgets even if maxVal is 1000, 0, or missing.
-- Tier 1: Look for fractions (e.g. "2/8", "2 / 8", "25/100") in override text, tooltip, or label text
-- Tier 2: Look for explicit percentages (e.g. "25%") in override text, tooltip, or label text
-- Tier 3: Sanitize numeric barValue, barMin, barMax (preventing Lua 0-truthiness on max)
-- Tier 4: Fixed-point scaling (1000 or 10000) with curVal > 100 guard
local function CheckStringProgress(str)
    if not str or type(str) ~= "string" or issecretvalue(str) or str == "" then
        return nil, nil, nil, nil
    end
    -- 1. Fraction check (e.g. "2/8" or "2 / 8" or "25/100")
    local curStr, maxStr = str:match("(%d+)%s*/%s*(%d+)")
    if curStr and maxStr then
        local cNum = tonumber(curStr)
        local mNum = tonumber(maxStr)
        if cNum and mNum and mNum > 0 and cNum >= 0 then
            local fracPct = math_min(100, math_max(0, math_floor((cNum / mNum) * 100 + 0.5)))
            return fracPct, cNum, mNum, string_format("%d/%d", cNum, mNum)
        end
    end
    -- 2. Explicit percentage check (e.g. "25%" or "(25%)")
    local pctStr = str:match("(%d+)%%")
    if pctStr then
        local pNum = tonumber(pctStr)
        if pNum and pNum >= 0 and pNum <= 100 then
            return pNum, pNum, 100, tostring(pNum) .. "%"
        end
    end
    return nil, nil, nil, nil
end

local function ExtractProgressValues(curVal, minVal, maxVal, overrideText, text, tooltip)
    -- Check explicit override text first (Blizzard's overrideBarText)
    local pct, c, m, customText = CheckStringProgress(overrideText)
    if pct then
        return pct, c, m, customText
    end

    -- Numeric sanitization & calculation (matching Blizzard UIWidgetBaseStatusBarTemplateMixin)
    minVal = (minVal and not issecretvalue(minVal)) and minVal or 0
    maxVal = (maxVal and not issecretvalue(maxVal) and maxVal > 0) and maxVal or nil
    curVal = (curVal and not issecretvalue(curVal)) and curVal or 0

    if minVal > 0 and maxVal and minVal == maxVal and curVal == maxVal then
        minVal, maxVal, curVal = 0, 1, 1
    end

    if maxVal and maxVal > minVal then
        local range = maxVal - minVal
        local calcPct = math_min(100, math_max(0, math_floor(((curVal - minVal) / range) * 100 + 0.5)))
        return calcPct, curVal, maxVal, nil
    end

    -- Fallback to string matching on text / tooltip only if numeric maxVal was absent or zero
    pct, c, m, customText = CheckStringProgress(text)
    if not pct then
        pct, c, m, customText = CheckStringProgress(tooltip)
    end
    if pct then
        return pct, c, m, customText
    end

    maxVal = maxVal or 100
    local calcPct = math_min(100, math_max(0, math_floor(curVal)))
    return calcPct, curVal, maxVal, nil
end

local function FormatEventTime(ev, now)
    now = now or time()
    if ev.isOngoing then
        if ev.endTime and not issecretvalue(ev.endTime) and ev.endTime > now then
            local rem = ev.endTime - now
            local formatted = FormatTimerSeconds(rem)
            ev.remText = formatted
            return "Ends in " .. formatted, rem
        else
            ev.remText = "now"
            return "Active Now", 0
        end
    else
        local sTime = (ev.startTime and not issecretvalue(ev.startTime) and ev.startTime) or now
        local toStart = sTime - now
        if toStart <= 0 then
            ev.remText = "now"
            return "Active Now", 0
        else
            local formatted = FormatTimerSeconds(toStart)
            ev.remText = formatted
            return "Starts in " .. formatted, toStart
        end
    end
end

function sfui.worldevents.is_enabled()
    if SfuiDB and SfuiDB.worldevents and SfuiDB.worldevents.enabled ~= nil then
        return SfuiDB.worldevents.enabled
    end
    return cfg.enabled ~= false
end

-- ─── POI & Event Info Resolver (Zero-Allocation Flat Cache) ─────────────────
local function ResolvePoiDetails(areaPoiID, displayInfo)
    if not areaPoiID or areaPoiID <= 0 then return nil end

    local name     = poiNameCache[areaPoiID]
    local atlas    = (displayInfo and displayInfo.overrideAtlas and not issecretvalue(displayInfo.overrideAtlas) and displayInfo.overrideAtlas) or poiAtlasCache[areaPoiID]
    local zoneName = poiZoneCache[areaPoiID]
    local uiMapID  = poiMapCache[areaPoiID]
    local wSet     = (displayInfo and displayInfo.overrideTooltipWidgetSetID and not issecretvalue(displayInfo.overrideTooltipWidgetSetID) and displayInfo.overrideTooltipWidgetSetID) or poiWidgetSetCache[areaPoiID]

    -- If name, zoneName, or wSet are missing or unresolved, query C_AreaPoiInfo fresh.
    -- wSet == false means "already queried, no widget set exists" (sentinel): skip re-query.
    -- wSet == nil means "never queried yet": enter the block.
    -- wSet is a positive number means "resolved": skip re-query for wSet.
    local wSetResolved = (wSet ~= nil)  -- nil=never queried; false=queried+absent; number=queried+found
    if not name or not zoneName or not wSetResolved then
        if not uiMapID and C_EventScheduler and C_EventScheduler.GetEventUiMapID then
            uiMapID = C_EventScheduler.GetEventUiMapID(areaPoiID)
        end
        local poiInfo = nil
        if C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIInfo then
            if uiMapID then
                poiInfo = C_AreaPoiInfo.GetAreaPOIInfo(uiMapID, areaPoiID)
            end
            if not poiInfo then
                poiInfo = C_AreaPoiInfo.GetAreaPOIInfo(nil, areaPoiID)
            end
        end

        if poiInfo then
            if not name and poiInfo.name and not issecretvalue(poiInfo.name) then
                name = poiInfo.name
            end
            if not atlas and poiInfo.atlasName and not issecretvalue(poiInfo.atlasName) then
                atlas = poiInfo.atlasName
            end
            if not uiMapID and poiInfo.linkedUiMapID and poiInfo.linkedUiMapID > 0 then
                uiMapID = poiInfo.linkedUiMapID
            end
            if not wSet or wSet <= 0 then
                wSet = (poiInfo.tooltipWidgetSet and not issecretvalue(poiInfo.tooltipWidgetSet) and poiInfo.tooltipWidgetSet)
                    or (poiInfo.iconWidgetSet and not issecretvalue(poiInfo.iconWidgetSet) and poiInfo.iconWidgetSet)
            end
        end

        if not zoneName then
            zoneName = C_EventScheduler and C_EventScheduler.GetEventZoneName and C_EventScheduler.GetEventZoneName(areaPoiID)
            if not zoneName and uiMapID then
                zoneName = sfui.common.get_map_name(uiMapID)
            end
        end

        name = name or zoneName or "World Event"

        poiNameCache[areaPoiID]  = name
        poiAtlasCache[areaPoiID] = atlas
        poiZoneCache[areaPoiID]  = zoneName
        poiMapCache[areaPoiID]   = uiMapID
        -- Cache the result either way: 'false' is a sentinel meaning "no widget set" so
        -- we don't re-query C_AreaPoiInfo on every subsequent ScanEvents call.
        poiWidgetSetCache[areaPoiID] = (wSet and wSet > 0) and wSet or false
    end

    return name, atlas, zoneName, uiMapID, wSet
end

-- ─── Event Sort Comparator ──────────────────────────────────────────────────
local function EventSortComparator(a, b)
    -- 1. Ongoing active events first
    if a.isOngoing ~= b.isOngoing then
        return a.isOngoing == true
    end

    -- 2. Within ongoing, nearest ending time first
    if a.isOngoing and b.isOngoing then
        local aEnd = a.endTime or 0
        local bEnd = b.endTime or 0
        if aEnd ~= bEnd then return aEnd < bEnd end
    end

    -- 3. Reminders take precedence
    if a.hasReminder ~= b.hasReminder then
        return a.hasReminder == true
    end

    -- 4. Upcoming events sort by start time ascending
    local aStart = a.startTime or 0
    local bStart = b.startTime or 0
    if aStart ~= bStart then return aStart < bStart end

    return (a.name or "") < (b.name or "")
end

-- ─── Update Events Cache ────────────────────────────────────────────────────
function sfui.worldevents.UpdateEventsData()
    if not sfui.worldevents.is_enabled() then
        for i = #cachedEvents, 1, -1 do
            ReleaseTable(table_remove(cachedEvents, i))
        end
        reminderCount = 0
        isDirty = false
        return
    end

    if not C_EventScheduler or not C_EventScheduler.CanShowEvents or not C_EventScheduler.CanShowEvents() then
        if #cachedEvents > 0 then
            for i = #cachedEvents, 1, -1 do
                ReleaseTable(table_remove(cachedEvents, i))
            end
        end
        reminderCount = 0
        isDirty = false
        return
    end

    local inCombat = InCombatLockdown and InCombatLockdown()

    -- Request events from server if data isn't ready (only when out of combat to prevent network/throttle spikes)
    if not inCombat and C_EventScheduler.HasData and not C_EventScheduler.HasData() and C_EventScheduler.RequestEvents then
        C_EventScheduler.RequestEvents()
    end

    local remindersOnly = (cfg.show_reminders_only ~= false)
    if SfuiDB and SfuiDB.worldevents and SfuiDB.worldevents.show_reminders_only ~= nil then
        remindersOnly = SfuiDB.worldevents.show_reminders_only
    end

    local now = time()
    reminderCount = 0

    -- Query ongoing and scheduled lists
    local ongoingList = C_EventScheduler.GetOngoingEvents and C_EventScheduler.GetOngoingEvents()
    local scheduledList = C_EventScheduler.GetScheduledEvents and C_EventScheduler.GetScheduledEvents()

    -- If both returned nil (client/server query throttle active, MayReturnNothing = true):
    -- NEVER wipe existing cachedEvents! Retain current events safely.
    if ongoingList == nil and scheduledList == nil then
        if #cachedEvents > 0 then
            lastUpdateTime = now
            isDirty = false
            return
        end
    end

    -- Clear staging list for zero-allocation rebuild
    for i = #stagingEvents, 1, -1 do
        ReleaseTable(table_remove(stagingEvents, i))
    end

    -- Check if player has focused an event on the map
    local superTrackedPOI = 0
    if C_SuperTrack and C_SuperTrack.GetSuperTrackedMapPin and Enum and Enum.SuperTrackingMapPinType and Enum.SuperTrackingMapPinType.AreaPOI then
        local _, pID = C_SuperTrack.GetSuperTrackedMapPin(Enum.SuperTrackingMapPinType.AreaPOI)
        superTrackedPOI = pID or 0
    end

    local playerMap = sfui.common.get_player_map_id()
    local showOngoing    = not remindersOnly and (cfg.show_ongoing ~= false)
    local maxUpcomingSec = (cfg.max_upcoming_minutes or 60) * 60
    local maxLimit       = cfg.max_events or 5
    wipe(seenPoi)

    -- 1. Ongoing Events
    if ongoingList then
        for _, oEvent in ipairs(ongoingList) do
            local pID = oEvent.areaPoiID
            if pID and not seenPoi[pID] then
                local isFocused = (superTrackedPOI > 0 and pID == superTrackedPOI)
                local name, atlas, zoneName, uiMapID, widgetSetID = ResolvePoiDetails(pID, oEvent.displayInfo)
                local isCurrentZone = (uiMapID and playerMap and uiMapID == playerMap)
                local isEligible = showOngoing or isFocused or isCurrentZone
                if isEligible and name then
                    seenPoi[pID] = true
                    local item = AcquireTable()
                    item.eventKey     = "ongoing_" .. tostring(pID)
                    item.areaPoiID    = pID
                    item.uiMapID      = uiMapID
                    item.widgetSetID  = widgetSetID
                    item.name         = name
                    item.atlasName    = atlas
                    item.zoneName     = zoneName
                    item.isOngoing    = true
                    item.hasReminder  = false
                    item.startTime    = now

                    -- Accurate remaining time via C_AreaPoiInfo.GetAreaPOISecondsLeft (WoW 12.1.0)
                    local secLeft = C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOISecondsLeft and C_AreaPoiInfo.GetAreaPOISecondsLeft(pID)
                    if secLeft and not issecretvalue(secLeft) and secLeft > 0 then
                        item.endTime = now + secLeft
                    else
                        item.endTime = 0
                    end
                    item.timeLeftText = FormatEventTime(item, now)
                    table_insert(stagingEvents, item)
                end
            end
        end
    end

    -- 2. Scheduled Events (Upcoming & Reminded & Focused)
    if scheduledList then
        for _, sEvent in ipairs(scheduledList) do
            local hasReminder = (sEvent.hasReminder == true)
            if hasReminder then
                reminderCount = reminderCount + 1
            end

            local sTime = (sEvent.startTime and not issecretvalue(sEvent.startTime) and sEvent.startTime) or now
            local eTime = (sEvent.endTime and not issecretvalue(sEvent.endTime) and sEvent.endTime) or now
            local toStart = sTime - now
            local toEnd   = eTime - now
            local isCurrentlyActive = (toStart <= 0 and toEnd > 0)
            local isFocused = (superTrackedPOI > 0 and sEvent.areaPoiID == superTrackedPOI)

            local pID = sEvent.areaPoiID
            local name, atlas, zoneName, uiMapID, widgetSetID = nil, nil, nil, nil, nil
            if pID then
                name, atlas, zoneName, uiMapID, widgetSetID = ResolvePoiDetails(pID, sEvent.displayInfo)
            end
            local isCurrentZone = (uiMapID and playerMap and uiMapID == playerMap and isCurrentlyActive)

            local isEligible = false
            if remindersOnly then
                isEligible = hasReminder or isFocused or isCurrentZone
            else
                isEligible = hasReminder or isFocused or isCurrentZone or isCurrentlyActive or (toStart > 0 and toStart <= maxUpcomingSec)
            end

            if isEligible and pID and not seenPoi[pID] and name then
                seenPoi[pID] = true
                local item = AcquireTable()
                item.eventKey     = sEvent.eventKey or ("sched_" .. tostring(sEvent.eventID or pID))
                item.areaPoiID    = pID
                item.uiMapID      = uiMapID
                item.widgetSetID  = widgetSetID
                item.name         = name
                item.atlasName    = atlas
                item.zoneName     = zoneName
                item.startTime    = sEvent.startTime
                item.endTime      = sEvent.endTime
                item.hasReminder  = hasReminder
                item.isOngoing    = isCurrentlyActive
                item.timeLeftText = FormatEventTime(item, now)
                table_insert(stagingEvents, item)
            end
        end
    end

    -- 3. Sort & Trim Staging List
    if #stagingEvents > 1 then
        table_sort(stagingEvents, EventSortComparator)
    end

    while #stagingEvents > maxLimit do
        ReleaseTable(table_remove(stagingEvents))
    end

    -- 4. Swap Staged Events into cachedEvents Non-Destructively
    for i = #cachedEvents, 1, -1 do
        ReleaseTable(table_remove(cachedEvents, i))
    end

    for i = 1, #stagingEvents do
        cachedEvents[i] = stagingEvents[i]
        stagingEvents[i] = nil
    end

    lastUpdateTime = now
    isDirty = false
end

function sfui.worldevents.RequestUpdate()
    isDirty = true
    sfui.worldevents.UpdateEventsData()
    if sfui.questlog and sfui.questlog.RequestRefresh then
        sfui.questlog.RequestRefresh()
    end
end

-- ─── Throttled Update Loop (5-Second Timer Countdown Ticks) ─────────────────
function sfui.worldevents.OnTimerTick(elapsed)
    if not sfui.worldevents.is_enabled() or #cachedEvents == 0 then return end

    local now = time()
    local needsRebuild = false
    local anyTextChanged = false

    for _, ev in ipairs(cachedEvents) do
        local oldText = ev.timeLeftText
        local newText, remSec = FormatEventTime(ev, now)
        if oldText ~= newText then
            ev.timeLeftText = newText
            anyTextChanged = true
        end

        -- If an event transitions from upcoming to started, or ongoing to expired
        if ev.isOngoing and ev.endTime and not issecretvalue(ev.endTime) and ev.endTime > 0 and (ev.endTime - now <= 0) then
            needsRebuild = true
        elseif not ev.isOngoing and ev.startTime and not issecretvalue(ev.startTime) and ev.startTime > 0 and (ev.startTime - now <= 0) then
            needsRebuild = true
        end
    end

    if needsRebuild or isDirty then
        sfui.worldevents.RequestUpdate()
    elseif anyTextChanged and sfui.questlog and sfui.questlog.RequestRefresh then
        sfui.questlog.RequestRefresh()
    end
end

-- ─── Public Section Population for quests.lua ───────────────────────────────
function sfui.worldevents.ScanEvents(targetList, acquireFunc)
    if not sfui.worldevents.is_enabled() then return end
    if isDirty or (time() - lastUpdateTime > 30) then
        sfui.worldevents.UpdateEventsData()
    end

    if #cachedEvents == 0 then return end

    local Alloc = acquireFunc or AcquireTable
    local playerMap = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")

    for idx, ev in ipairs(cachedEvents) do
        local entry = Alloc()
        entry.questID      = 99980000 + idx
        entry.isWorldEvent = true
        entry.eventKey     = ev.eventKey
        entry.areaPoiID    = ev.areaPoiID
        entry.uiMapID      = ev.uiMapID
        entry.title        = ev.name
        entry.zoneName     = ev.zoneName
        entry.atlasName    = ev.atlasName
        entry.hasReminder  = ev.hasReminder
        entry.isOngoing    = ev.isOngoing
        entry.timeLeftText = ev.timeLeftText
        entry.isComplete   = false
        entry.isFailed     = false
        entry.done         = 0
        entry.total        = 1

        -- Sub-objectives: Location & Time Remaining & Active Progress Widgets
        local objs = Alloc()

        local locObj = Alloc()
        locObj.text = ev.zoneName or "World Event"
        locObj.cleanText = locObj.text
        locObj.finished = false
        table_insert(objs, locObj)

        local timeObj = Alloc()
        local timeCol = ev.isOngoing and "|cff00ff88" or "|cff33d9f2"
        local remStr  = ev.remText or "now"
        timeObj.text = string_format("%sTime remaining: %s|r", timeCol, remStr)
        timeObj.cleanText = timeObj.text
        timeObj.finished = false
        table_insert(objs, timeObj)

        -- Progress Widgets (Status Bars, Double Status Bars, Steps, Timers, Text)
        local isLocalZone = (not ev.uiMapID) or (playerMap and ev.uiMapID == playerMap)
        local widgetCandidates = AcquireTable()
        if ev.widgetSetID and ev.widgetSetID > 0 then
            table_insert(widgetCandidates, ev.widgetSetID)
        end
        -- When an outdoor scenario is active (e.g. Community Feast, Time Rifts),
        -- scenarios.lua scans and displays the generic container widget sets (TopCenter, BelowMinimap, etc.).
        -- Do not scan those sets here if an outdoor scenario is active, preventing duplicate progress bars.
        local hasActiveScenario = _G.C_Scenario and _G.C_Scenario.IsInScenario and _G.C_Scenario.IsInScenario()
        if ev.isOngoing and isLocalZone and not hasActiveScenario and C_UIWidgetManager then
            if C_UIWidgetManager.GetObjectiveTrackerWidgetSetID then
                local otSet = C_UIWidgetManager.GetObjectiveTrackerWidgetSetID()
                if otSet and otSet > 0 and otSet ~= ev.widgetSetID then
                    table_insert(widgetCandidates, otSet)
                end
            end
            if C_UIWidgetManager.GetTopCenterWidgetSetID then
                local tcSet = C_UIWidgetManager.GetTopCenterWidgetSetID()
                if tcSet and tcSet > 0 and tcSet ~= ev.widgetSetID then
                    table_insert(widgetCandidates, tcSet)
                end
            end
            if C_UIWidgetManager.GetBelowMinimapWidgetSetID then
                local bmSet = C_UIWidgetManager.GetBelowMinimapWidgetSetID()
                if bmSet and bmSet > 0 and bmSet ~= ev.widgetSetID then
                    table_insert(widgetCandidates, bmSet)
                end
            end
            if C_UIWidgetManager.GetPowerBarWidgetSetID then
                local pbSet = C_UIWidgetManager.GetPowerBarWidgetSetID()
                if pbSet and pbSet > 0 and pbSet ~= ev.widgetSetID then
                    table_insert(widgetCandidates, pbSet)
                end
            end
        end

        if #widgetCandidates > 0 then
            local seenWidgets = AcquireTable()
            -- Hoist InCombatLockdown: calling it per-widget inside a triple-nested loop is wasteful.
            local inCombat = InCombatLockdown and InCombatLockdown()

            for _, wSetID in ipairs(widgetCandidates) do
            if C_UIWidgetManager and C_UIWidgetManager.GetAllWidgetsBySetID then
                local widgets = C_UIWidgetManager.GetAllWidgetsBySetID(wSetID)
                if widgets and type(widgets) == "table" then
                    for _, w in ipairs(widgets) do
                        local wID = (type(w) == "table" and w.widgetID) or (type(w) == "number" and w)
                        local wType = (type(w) == "table" and w.widgetType)
                        if wID and not seenWidgets[wID] then
                            seenWidgets[wID] = true

                            -- Dispatch by widget type.
                            -- IMPORTANT: when wType==nil (untyped / plain number widget IDs), we must
                            -- query ALL types — not use elseif — because the first matching branch
                            -- would swallow the widget and every other type would be silently skipped.
                            -- When wType is known we use elseif for efficiency.
                            local wTypeHandled = false

                            -- 1. Single StatusBar & UnitPowerBar
                            if wType == nil or wType == TYPE_STATUS_BAR or wType == TYPE_UNIT_POWER_BAR then
                                local sInfo = nil
                                if wType == TYPE_UNIT_POWER_BAR and C_UIWidgetManager.GetUnitPowerBarWidgetVisualizationInfo then
                                    sInfo = C_UIWidgetManager.GetUnitPowerBarWidgetVisualizationInfo(wID)
                                elseif C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo then
                                    sInfo = C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo(wID)
                                end
                                if not sInfo and C_UIWidgetManager.GetUnitPowerBarWidgetVisualizationInfo then
                                    sInfo = C_UIWidgetManager.GetUnitPowerBarWidgetVisualizationInfo(wID)
                                end

                                if sInfo and sInfo.shownState ~= 0 and sInfo.shownState ~= Enum.WidgetShownState.Hidden then
                                    local rawText = (sInfo.text and sInfo.text ~= "" and not issecretvalue(sInfo.text)) and sInfo.text or nil
                                    local rawTooltip = (sInfo.tooltip and sInfo.tooltip ~= "" and not issecretvalue(sInfo.tooltip)) and sInfo.tooltip:match("^[^\n]+") or nil
                                    local overrideText = (sInfo.overrideBarText and sInfo.overrideBarText ~= "" and not issecretvalue(sInfo.overrideBarText)) and sInfo.overrideBarText or nil

                                    local barLabel = rawText
                                    if barLabel and (barLabel:match("^%s*%d+%%%s*$") or barLabel:match("^%s*%d+%s*/%s*%d+%s*$")) then
                                        barLabel = nil
                                    end
                                    barLabel = barLabel or rawTooltip or (ev.name and not issecretvalue(ev.name) and ev.name) or "Progress"

                                    local isSecret = issecretvalue(sInfo.barValue) or issecretvalue(sInfo.barMin) or issecretvalue(sInfo.barMax)
                                    local pObj = Alloc()
                                    pObj.type = "progressbar"

                                    if isSecret or (inCombat and issecretvalue(sInfo.barValue)) then
                                        -- Combat lockdown / Protected values: ZERO Lua arithmetic or comparisons
                                        pObj.text = barLabel
                                        pObj.numFulfilled = sInfo.barValue
                                        local maxVal = (sInfo.barMax and not issecretvalue(sInfo.barMax) and sInfo.barMax > 0) and sInfo.barMax or 100
                                        pObj.numRequired = maxVal
                                        pObj.finished = false
                                        pObj.barText = overrideText or ""
                                    else
                                        local pct, curVal, maxVal, customText = ExtractProgressValues(sInfo.barValue, sInfo.barMin, sInfo.barMax, overrideText, rawText, rawTooltip)

                                        local valText = nil
                                        if overrideText then
                                            valText = overrideText
                                        elseif customText then
                                            valText = customText
                                        elseif sInfo.barValueTextType == Enum.StatusBarValueTextType.Percentage then
                                            valText = tostring(pct) .. "%"
                                        elseif sInfo.barValueTextType == Enum.StatusBarValueTextType.ValueOverMax then
                                            valText = string_format("%d/%d", curVal, maxVal)
                                        elseif sInfo.barValueTextType == Enum.StatusBarValueTextType.ValueOverMaxNormalized then
                                            local minVal = (sInfo.barMin and not issecretvalue(sInfo.barMin)) and sInfo.barMin or 0
                                            valText = string_format("%d/%d", curVal - minVal, maxVal - minVal)
                                        elseif sInfo.barValueTextType == Enum.StatusBarValueTextType.Value then
                                            valText = tostring(curVal)
                                        elseif sInfo.barValueTextType == Enum.StatusBarValueTextType.Time or sInfo.barValueTextType == Enum.StatusBarValueTextType.TimeShowOneLevelOnly then
                                            valText = FormatTimerSeconds(curVal)
                                        elseif sInfo.barValueTextType == Enum.StatusBarValueTextType.Hidden then
                                            valText = ""
                                        end

                                        pObj.text = string_format("%s (%d%%)", barLabel, pct)
                                        if valText and valText ~= "" then
                                            if valText:find("%%") then
                                                pObj.barText = valText
                                            else
                                                pObj.barText = string_format("%s (%d%%)", valText, pct)
                                            end
                                        else
                                            pObj.barText = tostring(pct) .. "%"
                                        end

                                        pObj.numFulfilled = pct
                                        pObj.numRequired = 100
                                        pObj.finished = false
                                    end

                                    table_insert(objs, pObj)
                                    wTypeHandled = true
                                end
                            end

                            -- 2. Double StatusBar
                            if (not wTypeHandled or wType == nil) and wType ~= TYPE_STATUS_BAR and wType ~= TYPE_UNIT_POWER_BAR
                            and (wType == nil or wType == TYPE_DOUBLE_STATUS_BAR) and C_UIWidgetManager.GetDoubleStatusBarWidgetVisualizationInfo then
                                local dInfo = C_UIWidgetManager.GetDoubleStatusBarWidgetVisualizationInfo(wID)
                                if dInfo and dInfo.shownState ~= 0 and dInfo.shownState ~= Enum.WidgetShownState.Hidden then
                                    local rawText = (dInfo.text and dInfo.text ~= "" and not issecretvalue(dInfo.text)) and dInfo.text or nil
                                    local rawTooltip = (dInfo.leftBarTooltip and not issecretvalue(dInfo.leftBarTooltip)) and dInfo.leftBarTooltip:match("^[^\n]+") or nil

                                    local lbl = rawText
                                    if lbl and (lbl:match("^%s*%d+%%%s*$") or lbl:match("^%s*%d+%s*/%s*%d+%s*$")) then
                                        lbl = nil
                                    end
                                    lbl = lbl or rawTooltip or (ev.name and not issecretvalue(ev.name) and ev.name) or "Progress"

                                    local isSec = issecretvalue(dInfo.leftBarValue) or issecretvalue(dInfo.leftBarMin) or issecretvalue(dInfo.leftBarMax)
                                    local pObj = Alloc()
                                    pObj.type = "progressbar"

                                    if isSec or (inCombat and issecretvalue(dInfo.leftBarValue)) then
                                        pObj.text = lbl
                                        pObj.numFulfilled = dInfo.leftBarValue
                                        local maxVal = (dInfo.leftBarMax and not issecretvalue(dInfo.leftBarMax) and dInfo.leftBarMax > 0) and dInfo.leftBarMax or 100
                                        if maxVal == 1000 and dInfo.leftBarValue and not issecretvalue(dInfo.leftBarValue) and dInfo.leftBarValue <= 100 then
                                            maxVal = 100
                                        end
                                        pObj.numRequired = maxVal
                                        pObj.finished = false
                                        pObj.barText = ""
                                    else
                                        local pct, lCur, lMax, customText = ExtractProgressValues(dInfo.leftBarValue, dInfo.leftBarMin, dInfo.leftBarMax, nil, rawText, rawTooltip)

                                        pObj.text = string_format("%s (%d%%)", lbl, pct)
                                        pObj.barText = customText and string_format("%s (%d%%)", customText, pct) or (tostring(pct) .. "%")
                                        pObj.numFulfilled = pct
                                        pObj.numRequired = 100
                                        pObj.finished = false
                                    end
                                    table_insert(objs, pObj)
                                    wTypeHandled = true
                                end
                            end

                            -- 3. CaptureBar
                            if (not wTypeHandled or wType == nil) and (wType == nil or wType == TYPE_CAPTURE_BAR) and C_UIWidgetManager.GetCaptureBarWidgetVisualizationInfo then
                                local cbInfo = C_UIWidgetManager.GetCaptureBarWidgetVisualizationInfo(wID)
                                if cbInfo and cbInfo.shownState ~= 0 and cbInfo.shownState ~= Enum.WidgetShownState.Hidden then
                                    local rawTooltip = (cbInfo.tooltip and cbInfo.tooltip ~= "" and not issecretvalue(cbInfo.tooltip)) and cbInfo.tooltip:match("^[^\n]+") or nil
                                    local lbl = rawTooltip or "Control Point"
                                    local isSec = issecretvalue(cbInfo.barValue) or issecretvalue(cbInfo.barMinValue) or issecretvalue(cbInfo.barMaxValue)
                                    local pObj = Alloc()
                                    pObj.type = "progressbar"
                                    pObj.text = lbl
                                    if isSec or inCombat then
                                        pObj.numFulfilled = cbInfo.barValue or 50
                                        pObj.numRequired = (cbInfo.barMaxValue and not issecretvalue(cbInfo.barMaxValue) and cbInfo.barMaxValue > 0) and cbInfo.barMaxValue or 100
                                        pObj.barText = ""
                                        pObj.finished = false
                                    else
                                        local pct, curV, maxV, customText = ExtractProgressValues(cbInfo.barValue, cbInfo.barMinValue, cbInfo.barMaxValue, nil, nil, rawTooltip)
                                        pObj.numFulfilled = pct
                                        pObj.numRequired = 100
                                        pObj.barText = tostring(pct) .. "%"
                                        pObj.finished = false
                                    end
                                    table_insert(objs, pObj)
                                    wTypeHandled = true
                                end
                            end

                            -- 4. FillUpFrames
                            if (not wTypeHandled or wType == nil) and (wType == nil or wType == TYPE_FILL_UP_FRAMES) and C_UIWidgetManager.GetFillUpFramesWidgetVisualizationInfo then
                                local fInfo = C_UIWidgetManager.GetFillUpFramesWidgetVisualizationInfo(wID)
                                if fInfo and fInfo.shownState ~= 0 and fInfo.shownState ~= Enum.WidgetShownState.Hidden then
                                    local rawTooltip = (fInfo.tooltip and not issecretvalue(fInfo.tooltip)) and fInfo.tooltip:match("^[^\n]+") or nil
                                    local lbl = rawTooltip or (ev.name and not issecretvalue(ev.name) and ev.name) or "Progress"
                                    local isSec = issecretvalue(fInfo.fillValue) or issecretvalue(fInfo.numFullFrames) or issecretvalue(fInfo.fillMax) or issecretvalue(fInfo.numTotalFrames)

                                    local pObj = Alloc()
                                    pObj.type = "progressbar"

                                    if isSec or (inCombat and (issecretvalue(fInfo.fillValue) or issecretvalue(fInfo.numFullFrames))) then
                                        pObj.text = lbl
                                        pObj.numFulfilled = fInfo.numFullFrames or fInfo.fillValue or 0
                                        pObj.numRequired = (fInfo.numTotalFrames and not issecretvalue(fInfo.numTotalFrames) and fInfo.numTotalFrames > 0 and fInfo.numTotalFrames)
                                                        or (fInfo.fillMax and not issecretvalue(fInfo.fillMax) and fInfo.fillMax > 0 and fInfo.fillMax)
                                                        or 100
                                        pObj.finished = false
                                        pObj.barText = ""
                                    else
                                        local fullF  = fInfo.numFullFrames or 0
                                        local totalF = (fInfo.numTotalFrames and not issecretvalue(fInfo.numTotalFrames) and fInfo.numTotalFrames > 0 and fInfo.numTotalFrames)
                                                    or (fInfo.fillMax and not issecretvalue(fInfo.fillMax) and fInfo.fillMax > 0 and fInfo.fillMax)
                                                    or 0
                                        local pct = 0

                                        -- Check tooltip first for explicit percent or fraction
                                        local textPct, tC, tM, customText = CheckStringProgress(rawTooltip)
                                        if textPct then
                                            pct = textPct
                                            if tC and tM then
                                                fullF = tC
                                                totalF = tM
                                            end
                                        elseif totalF > 0 then
                                            local partial = 0
                                            local fMin = fInfo.fillMin or 0
                                            local fMax = fInfo.fillMax or 0
                                            local fVal = fInfo.fillValue or 0
                                            if fMax > fMin and fVal >= fMin then
                                                partial = (fVal - fMin) / (fMax - fMin)
                                            end
                                            pct = math_min(100, math_max(0, math_floor(((fullF + partial) / totalF) * 100 + 0.5)))
                                        elseif fullF > 0 then
                                            pct = math_min(100, math_max(0, math_floor(fullF)))
                                        end

                                        pObj.text = string_format("%s (%d%%)", lbl, pct)
                                        if totalF > 0 then
                                            pObj.barText = string_format("%d/%d (%d%%)", fullF, totalF, pct)
                                        else
                                            pObj.barText = tostring(pct) .. "%"
                                        end
                                        pObj.numFulfilled = pct
                                        pObj.numRequired = 100
                                        pObj.finished = false
                                    end
                                    table_insert(objs, pObj)
                                    wTypeHandled = true
                                end
                            end

                            -- 5. DiscreteProgressSteps
                            if (not wTypeHandled or wType == nil) and (wType == nil or wType == TYPE_DISCRETE_STEPS) and C_UIWidgetManager.GetDiscreteProgressStepsVisualizationInfo then
                                local dpInfo = C_UIWidgetManager.GetDiscreteProgressStepsVisualizationInfo(wID)
                                if dpInfo and dpInfo.shownState ~= 0 and dpInfo.shownState ~= Enum.WidgetShownState.Hidden then
                                    local rawTooltip = (dpInfo.tooltip and not issecretvalue(dpInfo.tooltip)) and dpInfo.tooltip:match("^[^\n]+") or nil
                                    local lbl = rawTooltip or (ev.name and not issecretvalue(ev.name) and ev.name) or "Progress"
                                    local isSec = issecretvalue(dpInfo.progressVal) or issecretvalue(dpInfo.progressMax) or issecretvalue(dpInfo.numSteps)

                                    local pObj = Alloc()
                                    pObj.type = "progressbar"

                                    local pMaxDef = (dpInfo.progressMax and not issecretvalue(dpInfo.progressMax) and dpInfo.progressMax > 0 and dpInfo.progressMax)
                                                 or (dpInfo.numSteps and not issecretvalue(dpInfo.numSteps) and dpInfo.numSteps > 0 and dpInfo.numSteps)
                                                 or 100

                                    if isSec or (inCombat and issecretvalue(dpInfo.progressVal)) then
                                        pObj.text = lbl
                                        pObj.numFulfilled = dpInfo.progressVal or 0
                                        pObj.numRequired = pMaxDef
                                        pObj.finished = false
                                        pObj.barText = ""
                                    else
                                        local pMin = dpInfo.progressMin or 0
                                        local pVal = dpInfo.progressVal or pMin
                                        local pct, curVal, maxVal, customText = ExtractProgressValues(pVal, pMin, pMaxDef, nil, nil, rawTooltip)

                                        pObj.text = string_format("%s (%d%%)", lbl, pct)
                                        if maxVal and maxVal > 1 and maxVal ~= 100 then
                                            pObj.barText = string_format("%d/%d (%d%%)", curVal, maxVal, pct)
                                        else
                                            pObj.barText = customText or (tostring(pct) .. "%")
                                        end
                                        pObj.numFulfilled = pct
                                        pObj.numRequired = 100
                                        pObj.finished = false
                                    end
                                    table_insert(objs, pObj)
                                    wTypeHandled = true
                                end
                            end

                            -- 6. TugOfWar
                            if (not wTypeHandled or wType == nil) and (wType == nil or wType == TYPE_TUG_OF_WAR) and C_UIWidgetManager.GetTugOfWarWidgetVisualizationInfo then
                                local towInfo = C_UIWidgetManager.GetTugOfWarWidgetVisualizationInfo(wID)
                                if towInfo and towInfo.shownState ~= 0 and towInfo.shownState ~= Enum.WidgetShownState.Hidden then
                                    local rawTooltip = (towInfo.tooltip and towInfo.tooltip ~= "" and not issecretvalue(towInfo.tooltip)) and towInfo.tooltip:match("^[^\n]+") or nil
                                    local lbl = rawTooltip or (ev.name and not issecretvalue(ev.name) and ev.name) or "Tug of War"
                                    local isSec = issecretvalue(towInfo.currentValue) or issecretvalue(towInfo.minValue) or issecretvalue(towInfo.maxValue)
                                    local pObj = Alloc()
                                    pObj.type = "progressbar"
                                    pObj.text = lbl
                                    if isSec or inCombat then
                                        pObj.numFulfilled = towInfo.currentValue or 50
                                        pObj.numRequired = (towInfo.maxValue and not issecretvalue(towInfo.maxValue) and towInfo.maxValue > 0) and towInfo.maxValue or 100
                                        pObj.finished = false
                                        pObj.barText = ""
                                    else
                                        local pct, curV, maxV, customText = ExtractProgressValues(towInfo.currentValue, towInfo.minValue, towInfo.maxValue, nil, nil, rawTooltip)
                                        pObj.text = string_format("%s (%d%%)", lbl, pct)
                                        pObj.barText = tostring(pct) .. "%"
                                        pObj.numFulfilled = pct
                                        pObj.numRequired = 100
                                        pObj.finished = false
                                    end
                                    table_insert(objs, pObj)
                                    wTypeHandled = true
                                end
                            end

                            -- 7. ScenarioHeaderTimer (Stage Countdown Timers)
                            if (not wTypeHandled or wType == nil) and (wType == nil or wType == TYPE_SCENARIO_TIMER) and C_UIWidgetManager.GetScenarioHeaderTimerWidgetVisualizationInfo then
                                local tInfo = C_UIWidgetManager.GetScenarioHeaderTimerWidgetVisualizationInfo(wID)
                                if tInfo and tInfo.shownState ~= 0 and tInfo.shownState ~= Enum.WidgetShownState.Hidden then
                                    local lbl = (tInfo.headerText and tInfo.headerText ~= "" and not issecretvalue(tInfo.headerText) and tInfo.headerText)
                                             or (tInfo.timerTooltip and tInfo.timerTooltip ~= "" and not issecretvalue(tInfo.timerTooltip) and tInfo.timerTooltip:match("^[^\n]+"))
                                             or "Stage Timer"

                                    local isSec = issecretvalue(tInfo.timerValue) or issecretvalue(tInfo.timerMin) or issecretvalue(tInfo.timerMax)
                                    local sObj = Alloc()
                                    if isSec or (inCombat and issecretvalue(tInfo.timerValue)) then
                                        sObj.text = lbl
                                        sObj.finished = false
                                    else
                                        local tMin = tInfo.timerMin or 0
                                        local tMax = tInfo.timerMax or 0
                                        local tVal = tInfo.timerValue or 0
                                        local rem = 0
                                        if tMax > tMin and tVal >= tMin then
                                            rem = math_max(0, tVal - tMin)
                                        elseif tVal > 0 then
                                            rem = tVal
                                        end
                                        local tStr = FormatTimerSeconds(rem)
                                        sObj.text = string_format("%s: %s", lbl, tStr or "now")
                                        sObj.finished = (rem <= 0)
                                    end
                                    table_insert(objs, sObj)
                                    wTypeHandled = true
                                end
                            end

                            -- 8. TextWithState / TextWithSubtext / BulletTextList
                            if (not wTypeHandled or wType == nil) and (wType == nil or wType == TYPE_TEXT_WITH_STATE or wType == TYPE_TEXT_WITH_SUBTEXT or wType == TYPE_BULLET_TEXT_LIST) then
                                local textHandled = false
                                if (wType == TYPE_TEXT_WITH_SUBTEXT or wType == nil) and C_UIWidgetManager.GetTextWithSubtextWidgetVisualizationInfo then
                                    local twsInfo = C_UIWidgetManager.GetTextWithSubtextWidgetVisualizationInfo(wID)
                                    if twsInfo and twsInfo.shownState ~= 0 and twsInfo.shownState ~= Enum.WidgetShownState.Hidden then
                                        local txt = (twsInfo.text and twsInfo.text ~= "" and not issecretvalue(twsInfo.text) and twsInfo.text)
                                        local sub = (twsInfo.subText and twsInfo.subText ~= "" and not issecretvalue(twsInfo.subText) and twsInfo.subText)
                                        local combined = txt
                                        if txt and sub then
                                            combined = string_format("%s: %s", txt, sub)
                                        elseif sub then
                                            combined = sub
                                        end
                                        if combined and combined ~= "" then
                                            local tObj = Alloc()
                                            tObj.text = combined
                                            tObj.finished = false
                                            table_insert(objs, tObj)
                                            textHandled = true
                                        end
                                    end
                                end
                                if not textHandled and (wType == TYPE_BULLET_TEXT_LIST or wType == nil) and C_UIWidgetManager.GetBulletTextListWidgetVisualizationInfo then
                                    local bInfo = C_UIWidgetManager.GetBulletTextListWidgetVisualizationInfo(wID)
                                    if bInfo and bInfo.shownState ~= 0 and bInfo.shownState ~= Enum.WidgetShownState.Hidden and bInfo.lines then
                                        for _, line in ipairs(bInfo.lines) do
                                            if line and line ~= "" and not issecretvalue(line) then
                                                local bObj = Alloc()
                                                bObj.text = line
                                                bObj.finished = false
                                                table_insert(objs, bObj)
                                                textHandled = true
                                            end
                                        end
                                    end
                                end
                                if not textHandled and (wType == TYPE_TEXT_WITH_STATE or wType == nil) and C_UIWidgetManager.GetTextWithStateWidgetVisualizationInfo then
                                    local twInfo = C_UIWidgetManager.GetTextWithStateWidgetVisualizationInfo(wID)
                                    if twInfo and twInfo.shownState ~= 0 and twInfo.shownState ~= Enum.WidgetShownState.Hidden then
                                        local txt = (twInfo.text and twInfo.text ~= "" and not issecretvalue(twInfo.text) and twInfo.text)
                                        if txt and txt ~= "" then
                                            local tObj = Alloc()
                                            tObj.text = txt
                                            tObj.finished = false
                                            table_insert(objs, tObj)
                                        end
                                    end
                                end
                            end

                            -- 9. IconAndText / TextureAndText
                            if (not wTypeHandled or wType == nil) and (wType == nil or wType == TYPE_ICON_AND_TEXT or wType == TYPE_TEXTURE_AND_TEXT) then
                                local txt = nil
                                if (wType == TYPE_TEXTURE_AND_TEXT or wType == nil) and C_UIWidgetManager.GetTextureAndTextVisualizationInfo then
                                    local ttInfo = C_UIWidgetManager.GetTextureAndTextVisualizationInfo(wID)
                                    if ttInfo and ttInfo.shownState ~= 0 and ttInfo.shownState ~= Enum.WidgetShownState.Hidden then
                                        txt = (ttInfo.text and ttInfo.text ~= "" and not issecretvalue(ttInfo.text) and ttInfo.text)
                                    end
                                end
                                if not txt and (wType == TYPE_ICON_AND_TEXT or wType == nil) and C_UIWidgetManager.GetIconAndTextWidgetVisualizationInfo then
                                    local itInfo = C_UIWidgetManager.GetIconAndTextWidgetVisualizationInfo(wID)
                                    if itInfo and itInfo.shownState ~= 0 and itInfo.shownState ~= Enum.WidgetShownState.Hidden then
                                        txt = (itInfo.text and itInfo.text ~= "" and not issecretvalue(itInfo.text) and itInfo.text)
                                    end
                                end
                                if txt and txt ~= "" then
                                    local iObj = Alloc()
                                    iObj.text = txt
                                    iObj.finished = false
                                    table_insert(objs, iObj)
                                end
                            end -- wType dispatch
                        end -- seenWidgets check
                    end -- for w
                end -- if widgets
            end -- if GetAllWidgetsBySetID
        end -- for wSetID
        ReleaseTable(seenWidgets)
    end -- if #widgetCandidates > 0

    ReleaseTable(widgetCandidates)

        entry.objectives = objs
        entry._syntheticObjs = true

        table_insert(targetList, entry)
    end
end

-- ─── Profiler Support for mem.lua ───────────────────────────────────────────
function sfui.worldevents_debug_info()
    local poiCount = 0
    for _ in pairs(poiNameCache) do poiCount = poiCount + 1 end
    return {
        activeEvents = #cachedEvents,
        tablePool    = #tablePool,
        reminders    = reminderCount,
        cachedPois   = poiCount,
        poiCount     = poiCount,
        isDirty      = isDirty,
        lastUpdate   = lastUpdateTime,
    }
end

if sfui.RegisterModule then
    sfui.worldevents = sfui.worldevents or {}
    sfui.worldevents.GetDebugInfo = sfui.worldevents_debug_info
    sfui.RegisterModule("worldevents", sfui.worldevents)
end

-- ─── Central Dispatcher Registration ────────────────────────────────────────
if sfui.events then
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        local inCombat = InCombatLockdown and InCombatLockdown()
        if not inCombat and C_EventScheduler and C_EventScheduler.RequestEvents then
            C_EventScheduler.RequestEvents()
        end
        C_Timer.After(2.0, sfui.worldevents.RequestUpdate)
    end)

    sfui.events.RegisterEvent("EVENT_SCHEDULER_UPDATE", function()
        sfui.worldevents.RequestUpdate()
    end)

    sfui.events.RegisterEvent("SUPER_TRACKING_CHANGED", function()
        sfui.worldevents.RequestUpdate()
    end)

    local function HasActiveWidgetSet(setID)
        if not setID or issecretvalue(setID) or type(setID) ~= "number" or setID <= 0 then return false end
        for _, ev in ipairs(cachedEvents) do
            -- Guard against secretvalue widgetSetID before numeric comparison
            if ev.widgetSetID and not issecretvalue(ev.widgetSetID) and type(ev.widgetSetID) == "number" and ev.widgetSetID == setID then
                return true
            end
        end
        return false
    end

    -- Decoupled widget updates: do NOT re-query C_EventScheduler.
    -- Simply refresh the quest log so ScanEvents reads updated values from C_UIWidgetManager.
    -- Strictly ignore unassociated city widgets (setID == nil or not in active world events)
    -- to prevent rapid GC churn while standing in city hubs (Dornogal, Valdrakken).
    sfui.events.RegisterThrottledEvent("UPDATE_UI_WIDGET", 0.5, function(event, widgetInfo)
        if not sfui.worldevents.is_enabled() or #cachedEvents == 0 then return end
        local setID = widgetInfo and widgetInfo.widgetSetID
        if setID and HasActiveWidgetSet(setID) then
            if sfui.questlog and sfui.questlog.RequestRefresh then
                sfui.questlog.RequestRefresh()
            end
        end
    end)

    sfui.events.RegisterThrottledEvent("UPDATE_ALL_UI_WIDGETS", 0.5, function()
        if not sfui.worldevents.is_enabled() or #cachedEvents == 0 then return end
        local hasActiveEventWidgets = false
        for _, ev in ipairs(cachedEvents) do
            if ev.isOngoing and ev.widgetSetID and not issecretvalue(ev.widgetSetID) and ev.widgetSetID > 0 then
                hasActiveEventWidgets = true
                break
            end
        end
        if hasActiveEventWidgets and sfui.questlog and sfui.questlog.RequestRefresh then
            sfui.questlog.RequestRefresh()
        end
    end)

    sfui.events.RegisterEvent("QUEST_LOG_UPDATE", function()
        local inCombat = InCombatLockdown and InCombatLockdown()
        if not inCombat and isDirty then
            sfui.worldevents.RequestUpdate()
        end
    end)

    sfui.events.RegisterUpdate("WorldEvents", 5.0, function(elapsed)
        sfui.worldevents.OnTimerTick(elapsed)
    end)
end



-- ─── Tracker Content Module Protocol ────────────────────────────────────────
local WorldEventsModule = {
    id       = "worldevents",
    priority = 15,
    events   = {
        "PLAYER_ENTERING_WORLD",
        "EVENT_SCHEDULER_UPDATE",
        "SUPER_TRACKING_CHANGED",
        "QUEST_LOG_UPDATE",
    },
}

function WorldEventsModule:Init(engine)
    self.engine = engine
end

function WorldEventsModule:IsEnabled()
    return sfui.worldevents.is_enabled()
end

local function GetQLState()
    if not SfuiDB then SfuiDB = {} end
    if not SfuiDB.questlog then
        SfuiDB.questlog = {
            collapsed      = {},
            expandedQuests = {},
            hiddenQuests   = {},
            hidden         = false,
        }
    end
    return SfuiDB.questlog
end

function WorldEventsModule:BuildBlocks(container)
    if not self:IsEnabled() then return {} end

    local entries = AcquireTable()
    sfui.worldevents.ScanEvents(entries, AcquireTable)

    if #entries == 0 then
        ReleaseTable(entries)
        return {}
    end

    local superTrackedPOI = 0
    if C_SuperTrack and C_SuperTrack.GetSuperTrackedMapPin and Enum and Enum.SuperTrackingMapPinType and Enum.SuperTrackingMapPinType.AreaPOI then
        local _, pID = C_SuperTrack.GetSuperTrackedMapPin(Enum.SuperTrackingMapPinType.AreaPOI)
        superTrackedPOI = pID or 0
    end

    local state = GetQLState()
    local expandedQuests = state.expandedQuests or {}

    local blocks = {}
    for _, entry in ipairs(entries) do
        local isSuper = (superTrackedPOI > 0 and entry.areaPoiID == superTrackedPOI)
        local titleColor = entry.isOngoing and { 1.00, 0.75, 0.10, 1 } or { 0.95, 0.70, 0.95, 1 }

        local curEventKey = entry.eventKey
        local curPoiID    = entry.areaPoiID
        local hasReminder = entry.hasReminder
        local expandKey   = "wevent_" .. tostring(curEventKey or curPoiID or entry.title or "event")
        local isExpanded  = (expandedQuests[expandKey] ~= false) -- Default expanded

        local lines = {}
        local progressBar = nil

        if isExpanded and entry.objectives and #entry.objectives > 0 then
            for _, obj in ipairs(entry.objectives) do
                if obj.type == "progressbar" and not progressBar then
                    local maxV = (obj.numRequired and not issecretvalue(obj.numRequired) and obj.numRequired > 0) and obj.numRequired or 100
                    local curV = (obj.numFulfilled and not issecretvalue(obj.numFulfilled)) and obj.numFulfilled or 0
                    local barTxt = obj.barText
                    if not barTxt or barTxt == "" then
                        barTxt = string_format("%d%%", math_floor((curV / maxV) * 100 + 0.5))
                    end
                    progressBar = {
                        min   = 0,
                        max   = maxV,
                        value = curV,
                        text  = barTxt,
                        color = { 0.90, 0.45, 0.90, 0.90 },
                    }
                elseif obj.text and obj.text ~= "" and not issecretvalue(obj.text) then
                    table_insert(lines, {
                        text      = obj.text,
                        completed = (obj.finished == true),
                    })
                end
            end
        end

        local block = {
            title          = entry.title,
            rawTitle       = entry.title,
            titleColor     = titleColor,
            isSuperTracked = isSuper,
            isWorldEvent   = true,
            isExpanded     = isExpanded,
            eventKey       = curEventKey,
            areaPoiID      = curPoiID,
            uiMapID        = entry.uiMapID,
            zoneName       = entry.zoneName,
            atlasName      = entry.atlasName,
            hasReminder    = hasReminder,
            isOngoing      = entry.isOngoing,
            timeLeftText   = entry.timeLeftText,
            lines          = lines,
            progressBar    = progressBar,
            OnClick        = function(self, btn)
                -- 1. Shift-Click: Toggle Reminder in Event Scheduler
                local IsShiftKeyDown = _G.IsShiftKeyDown
                if IsShiftKeyDown and IsShiftKeyDown() then
                    if curEventKey and C_EventScheduler then
                        if hasReminder then
                            if C_EventScheduler.ClearReminder then
                                C_EventScheduler.ClearReminder(curEventKey)
                            end
                        else
                            if C_EventScheduler.SetReminder then
                                C_EventScheduler.SetReminder(curEventKey)
                            end
                        end
                    end
                    sfui.worldevents.RequestUpdate()
                    return
                end

                -- 2. Right-Click: Toggle Collapse/Expand Objectives
                if btn == "RightButton" then
                    local st = GetQLState()
                    st.expandedQuests = st.expandedQuests or {}
                    st.expandedQuests[expandKey] = not isExpanded
                    if sfui.tracker and sfui.tracker.RequestRefresh then
                        sfui.tracker.RequestRefresh(0.01)
                    end
                    return
                end

                -- 3. Left-Click: Track & Show on Map
                if C_SuperTrack and C_SuperTrack.SetSuperTrackedMapPin and Enum and Enum.SuperTrackingMapPinType and Enum.SuperTrackingMapPinType.AreaPOI then
                    local _, pinID = C_SuperTrack.GetSuperTrackedMapPin(Enum.SuperTrackingMapPinType.AreaPOI)
                    if pinID == curPoiID then
                        C_SuperTrack.ClearSuperTrackedMapPin(Enum.SuperTrackingMapPinType.AreaPOI)
                    else
                        C_SuperTrack.SetSuperTrackedMapPin(Enum.SuperTrackingMapPinType.AreaPOI, curPoiID)
                        if _G.OpenMapToEventPoi then
                            _G.OpenMapToEventPoi(curPoiID)
                        elseif _G.ToggleWorldMap then
                            _G.ToggleWorldMap()
                        end
                    end
                end
            end,
        }

        table_insert(blocks, block)
    end

    -- Recycle raw entries back to table pool
    for i = #entries, 1, -1 do
        local entry = table_remove(entries, i)
        if entry.objectives then
            for j = #entry.objectives, 1, -1 do
                ReleaseTable(table_remove(entry.objectives, j))
            end
            ReleaseTable(entry.objectives)
        end
        ReleaseTable(entry)
    end
    ReleaseTable(entries)

    return {
        {
            id     = "events",
            title  = "events",
            color  = { 0.90, 0.45, 0.90 },
            blocks = blocks,
        }
    }
end

if sfui.tracker and sfui.tracker.RegisterModule then
    sfui.tracker.RegisterModule(WorldEventsModule)
end

return WorldEventsModule
