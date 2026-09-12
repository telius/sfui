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
local TYPE_STATUS_BAR        = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.StatusBar) or 2
local TYPE_DOUBLE_STATUS_BAR = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.DoubleStatusBar) or 3
local TYPE_CAPTURE_BAR       = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.CaptureBar) or 1
local TYPE_FILL_UP_FRAMES    = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.FillUpFrames) or 24
local TYPE_DISCRETE_STEPS    = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.DiscreteProgressSteps) or 19
local TYPE_SCENARIO_TIMER    = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.ScenarioHeaderTimer) or 20
local TYPE_TEXT_WITH_STATE   = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.TextWithState) or 8
local TYPE_ICON_AND_TEXT     = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.IconAndText) or 0

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

    -- If name, zoneName, or wSet are missing or unresolved, query C_AreaPoiInfo fresh
    if not name or not zoneName or not wSet or wSet <= 0 then
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
        if wSet and wSet > 0 then
            poiWidgetSetCache[areaPoiID] = wSet
        end
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
        locObj.finished = false
        table_insert(objs, locObj)

        local timeObj = Alloc()
        local timeCol = ev.isOngoing and "|cff00ff88" or "|cff33d9f2"
        local remStr  = ev.remText or "now"
        timeObj.text = string_format("%sTime remaining: %s|r", timeCol, remStr)
        timeObj.finished = false
        table_insert(objs, timeObj)

        -- Progress Widgets (Status Bars, Double Status Bars, Steps, Timers, Text)
        local widgetCandidates = AcquireTable()
        if ev.widgetSetID and ev.widgetSetID > 0 then
            table_insert(widgetCandidates, ev.widgetSetID)
        end
        if ev.isOngoing and C_UIWidgetManager then
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
        end

        local seenWidgets = AcquireTable()

        for _, wSetID in ipairs(widgetCandidates) do
            if C_UIWidgetManager and C_UIWidgetManager.GetAllWidgetsBySetID then
                local widgets = C_UIWidgetManager.GetAllWidgetsBySetID(wSetID)
                if widgets and type(widgets) == "table" then
                    for _, w in ipairs(widgets) do
                        local wID = (type(w) == "table" and w.widgetID) or (type(w) == "number" and w)
                        local wType = (type(w) == "table" and w.widgetType)
                        if wID and not seenWidgets[wID] then
                            seenWidgets[wID] = true
                            local inCombat = InCombatLockdown and InCombatLockdown()

                            -- 1. Single StatusBar
                            if (wType == nil or wType == TYPE_STATUS_BAR) and C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo then
                                local sInfo = C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo(wID)
                                if sInfo and sInfo.shownState ~= 0 and sInfo.shownState ~= Enum.WidgetShownState.Hidden then
                                    local barLabel = (sInfo.text and sInfo.text ~= "" and not issecretvalue(sInfo.text) and sInfo.text)
                                                  or (sInfo.tooltip and sInfo.tooltip ~= "" and not issecretvalue(sInfo.tooltip) and sInfo.tooltip:match("^[^\n]+"))
                                                  or (ev.name and not issecretvalue(ev.name) and ev.name)
                                                  or "Progress"

                                    local isSecret = issecretvalue(sInfo.barValue) or issecretvalue(sInfo.barMin) or issecretvalue(sInfo.barMax)

                                    local pObj = Alloc()
                                    pObj.type = "progressbar"

                                    local overrideText = (sInfo.overrideBarText and sInfo.overrideBarText ~= "" and not issecretvalue(sInfo.overrideBarText) and sInfo.overrideBarText)

                                    if isSecret or (inCombat and issecretvalue(sInfo.barValue)) then
                                        -- Combat lockdown / Protected values: ZERO Lua arithmetic or comparisons
                                        pObj.text = barLabel
                                        pObj.numFulfilled = sInfo.barValue
                                        pObj.numRequired = (sInfo.barMax and not issecretvalue(sInfo.barMax) and sInfo.barMax > 0) and sInfo.barMax or 100
                                        pObj.finished = false
                                        pObj.barText = overrideText or ""
                                    else
                                        local minVal = sInfo.barMin or 0
                                        local maxVal = sInfo.barMax or 100
                                        local curVal = sInfo.barValue or 0

                                        if minVal > 0 and minVal == maxVal and curVal == maxVal then
                                            minVal, maxVal, curVal = 0, 1, 1
                                        end

                                        local pct = 0
                                        local explicitPct = overrideText and overrideText:match("(%d+)%%")

                                        if explicitPct then
                                            pct = math_min(100, math_max(0, tonumber(explicitPct) or 0))
                                        elseif maxVal == 1000 then
                                            if curVal > 100 then
                                                pct = math_min(100, math_max(0, math_floor(curVal / 10)))
                                            else
                                                pct = math_min(100, math_max(0, math_floor(curVal)))
                                            end
                                        elseif maxVal == 10000 then
                                            if curVal > 100 then
                                                pct = math_min(100, math_max(0, math_floor(curVal / 100)))
                                            else
                                                pct = math_min(100, math_max(0, math_floor(curVal)))
                                            end
                                        else
                                            local range = maxVal - minVal
                                            if range > 0 then
                                                pct = math_min(100, math_max(0, math_floor(((curVal - minVal) / range) * 100)))
                                            elseif curVal > 0 then
                                                pct = math_min(100, math_max(0, math_floor(curVal)))
                                            end
                                        end

                                        local valText = nil
                                        if overrideText then
                                            valText = overrideText
                                        elseif sInfo.barValueTextType == Enum.StatusBarValueTextType.Percentage then
                                            valText = tostring(pct) .. "%"
                                        elseif sInfo.barValueTextType == Enum.StatusBarValueTextType.ValueOverMax then
                                            valText = string_format("%d/%d", curVal, maxVal)
                                        elseif sInfo.barValueTextType == Enum.StatusBarValueTextType.ValueOverMaxNormalized then
                                            valText = string_format("%d/%d", curVal - minVal, maxVal - minVal)
                                        elseif sInfo.barValueTextType == Enum.StatusBarValueTextType.Value then
                                            valText = tostring(curVal)
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
                                        pObj.finished = (pct >= 100)
                                    end

                                    table_insert(objs, pObj)
                                end
                            end

                            -- 2. Double StatusBar
                            if (wType == nil or wType == TYPE_DOUBLE_STATUS_BAR) and C_UIWidgetManager.GetDoubleStatusBarWidgetVisualizationInfo then
                                local dInfo = C_UIWidgetManager.GetDoubleStatusBarWidgetVisualizationInfo(wID)
                                if dInfo and dInfo.shownState ~= 0 and dInfo.shownState ~= Enum.WidgetShownState.Hidden then
                                    local lbl = (dInfo.text and dInfo.text ~= "" and not issecretvalue(dInfo.text) and dInfo.text)
                                             or (dInfo.leftBarTooltip and not issecretvalue(dInfo.leftBarTooltip) and dInfo.leftBarTooltip:match("^[^\n]+"))
                                             or (ev.name and not issecretvalue(ev.name) and ev.name)
                                             or "Progress"

                                    local isSec = issecretvalue(dInfo.leftBarValue) or issecretvalue(dInfo.leftBarMin) or issecretvalue(dInfo.leftBarMax)
                                    local pObj = Alloc()
                                    pObj.type = "progressbar"

                                    if isSec or (inCombat and issecretvalue(dInfo.leftBarValue)) then
                                        pObj.text = lbl
                                        pObj.numFulfilled = dInfo.leftBarValue
                                        pObj.numRequired = (dInfo.leftBarMax and not issecretvalue(dInfo.leftBarMax) and dInfo.leftBarMax > 0) and dInfo.leftBarMax or 100
                                        pObj.finished = false
                                        pObj.barText = ""
                                    else
                                        local lMin = dInfo.leftBarMin or 0
                                        local lMax = dInfo.leftBarMax or 100
                                        local lCur = dInfo.leftBarValue or 0
                                        local pct = 0
                                        if lMax == 1000 then
                                            if lCur > 100 then
                                                pct = math_min(100, math_max(0, math_floor(lCur / 10)))
                                            else
                                                pct = math_min(100, math_max(0, math_floor(lCur)))
                                            end
                                        elseif lMax == 10000 then
                                            if lCur > 100 then
                                                pct = math_min(100, math_max(0, math_floor(lCur / 100)))
                                            else
                                                pct = math_min(100, math_max(0, math_floor(lCur)))
                                            end
                                        else
                                            local lRange = lMax - lMin
                                            if lRange > 0 then
                                                pct = math_min(100, math_max(0, math_floor(((lCur - lMin) / lRange) * 100)))
                                            elseif lCur > 0 then
                                                pct = math_min(100, math_max(0, math_floor(lCur)))
                                            end
                                        end

                                        pObj.text = string_format("%s (%d%%)", lbl, pct)
                                        pObj.barText = tostring(pct) .. "%"
                                        pObj.numFulfilled = pct
                                        pObj.numRequired = 100
                                        pObj.finished = (pct >= 100)
                                    end
                                    table_insert(objs, pObj)
                                end
                            end

                            -- 3. CaptureBar
                            if (wType == nil or wType == TYPE_CAPTURE_BAR) and C_UIWidgetManager.GetCaptureBarWidgetVisualizationInfo then
                                local cbInfo = C_UIWidgetManager.GetCaptureBarWidgetVisualizationInfo(wID)
                                if cbInfo and cbInfo.shownState ~= 0 and cbInfo.shownState ~= Enum.WidgetShownState.Hidden then
                                    local isSec = issecretvalue(cbInfo.barValue) or issecretvalue(cbInfo.neutralZoneCenterPosition)
                                    local pObj = Alloc()
                                    pObj.type = "progressbar"
                                    pObj.text = "Control Point"
                                    if isSec or inCombat then
                                        pObj.numFulfilled = cbInfo.barValue or 50
                                        pObj.numRequired = 100
                                        pObj.barText = ""
                                        pObj.finished = false
                                    else
                                        local pct = math_min(100, math_max(0, math_floor(cbInfo.barValue or 50)))
                                        pObj.numFulfilled = pct
                                        pObj.numRequired = 100
                                        pObj.barText = tostring(pct) .. "%"
                                        pObj.finished = false
                                    end
                                    table_insert(objs, pObj)
                                end
                            end

                            -- 4. FillUpFrames
                            if (wType == nil or wType == TYPE_FILL_UP_FRAMES or wType == 7 or wType == 24) and C_UIWidgetManager.GetFillUpFramesWidgetVisualizationInfo then
                                local fInfo = C_UIWidgetManager.GetFillUpFramesWidgetVisualizationInfo(wID)
                                if fInfo and fInfo.shownState ~= 0 and fInfo.shownState ~= Enum.WidgetShownState.Hidden then
                                    local lbl = (fInfo.tooltip and not issecretvalue(fInfo.tooltip) and fInfo.tooltip:match("^[^\n]+"))
                                             or (ev.name and not issecretvalue(ev.name) and ev.name)
                                             or "Progress"
                                    local isSec = issecretvalue(fInfo.fillValue) or issecretvalue(fInfo.numFullFrames) or issecretvalue(fInfo.fillMax) or issecretvalue(fInfo.numTotalFrames)

                                    local pObj = Alloc()
                                    pObj.type = "progressbar"

                                    if isSec or (inCombat and (issecretvalue(fInfo.fillValue) or issecretvalue(fInfo.numFullFrames))) then
                                        pObj.text = lbl
                                        pObj.numFulfilled = fInfo.fillValue or fInfo.numFullFrames or 0
                                        pObj.numRequired = fInfo.fillMax or fInfo.numTotalFrames or 100
                                        pObj.finished = false
                                        pObj.barText = ""
                                    else
                                        local full = fInfo.numFullFrames or 0
                                        local totalF = fInfo.numTotalFrames or 0
                                        local val = fInfo.fillValue or full
                                        local maxV = fInfo.fillMax or totalF
                                        local pct = 0
                                        if maxV > 0 then
                                            pct = math_min(100, math_max(0, math_floor((val / maxV) * 100)))
                                        end
                                        pObj.text = string_format("%s (%d%%)", lbl, pct)
                                        pObj.barText = string_format("%d/%d (%d%%)", val, maxV, pct)
                                        pObj.numFulfilled = pct
                                        pObj.numRequired = 100
                                        pObj.finished = (pct >= 100)
                                    end
                                    table_insert(objs, pObj)
                                end
                            end

                            -- 5. DiscreteProgressSteps
                            if (wType == nil or wType == TYPE_DISCRETE_STEPS or wType == 12 or wType == 19) and C_UIWidgetManager.GetDiscreteProgressStepsVisualizationInfo then
                                local dpInfo = C_UIWidgetManager.GetDiscreteProgressStepsVisualizationInfo(wID)
                                if dpInfo and dpInfo.shownState ~= 0 and dpInfo.shownState ~= Enum.WidgetShownState.Hidden then
                                    local lbl = (dpInfo.tooltip and not issecretvalue(dpInfo.tooltip) and dpInfo.tooltip:match("^[^\n]+"))
                                             or (ev.name and not issecretvalue(ev.name) and ev.name)
                                             or "Progress"
                                    local isSec = issecretvalue(dpInfo.progressVal) or issecretvalue(dpInfo.progressMax) or issecretvalue(dpInfo.numSteps)

                                    local pObj = Alloc()
                                    pObj.type = "progressbar"

                                    if isSec or (inCombat and issecretvalue(dpInfo.progressVal)) then
                                        pObj.text = lbl
                                        pObj.numFulfilled = dpInfo.progressVal or 0
                                        pObj.numRequired = dpInfo.progressMax or dpInfo.numSteps or 100
                                        pObj.finished = false
                                        pObj.barText = ""
                                    else
                                        local pVal = dpInfo.progressVal or 0
                                        local pMax = dpInfo.progressMax or dpInfo.numSteps or 0
                                        local pct = 0
                                        if pMax > 0 then
                                            pct = math_min(100, math_max(0, math_floor((pVal / pMax) * 100)))
                                        end
                                        pObj.text = string_format("%s (%d%%)", lbl, pct)
                                        pObj.barText = string_format("%d/%d (%d%%)", pVal, pMax, pct)
                                        pObj.numFulfilled = pct
                                        pObj.numRequired = 100
                                        pObj.finished = (pct >= 100)
                                    end
                                    table_insert(objs, pObj)
                                end
                            end

                            -- 6. ScenarioHeaderTimer (Stage Countdown Timers)
                            if (wType == nil or wType == TYPE_SCENARIO_TIMER or wType == 17 or wType == 20) and C_UIWidgetManager.GetScenarioHeaderTimerWidgetVisualizationInfo then
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
                                end
                            end

                            -- 7. TextWithState (Stage Instructions / Status)
                            if (wType == nil or wType == TYPE_TEXT_WITH_STATE or wType == 8 or wType == 14) and C_UIWidgetManager.GetTextWithStateWidgetVisualizationInfo then
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

                            -- 8. IconAndText
                            if (wType == nil or wType == TYPE_ICON_AND_TEXT or wType == 0) and C_UIWidgetManager.GetIconAndTextWidgetVisualizationInfo then
                                local itInfo = C_UIWidgetManager.GetIconAndTextWidgetVisualizationInfo(wID)
                                if itInfo and itInfo.shownState ~= 0 and itInfo.shownState ~= Enum.WidgetShownState.Hidden then
                                    local txt = (itInfo.text and itInfo.text ~= "" and not issecretvalue(itInfo.text) and itInfo.text)
                                    if txt and txt ~= "" then
                                        local iObj = Alloc()
                                        iObj.text = txt
                                        iObj.finished = false
                                        table_insert(objs, iObj)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        ReleaseTable(widgetCandidates)
        ReleaseTable(seenWidgets)

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
        isDirty      = isDirty,
        lastUpdate   = lastUpdateTime,
    }
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

    sfui.events.RegisterEvent("AREA_POIS_UPDATED", function()
        sfui.worldevents.RequestUpdate()
    end)

    local function HasActiveWidgetSet(setID)
        if not setID then return false end
        if issecretvalue(setID) then return true end
        if setID <= 0 then return false end
        for _, ev in ipairs(cachedEvents) do
            if ev.widgetSetID and not issecretvalue(ev.widgetSetID) and ev.widgetSetID == setID then return true end
        end
        if C_UIWidgetManager then
            if C_UIWidgetManager.GetObjectiveTrackerWidgetSetID then
                local s = C_UIWidgetManager.GetObjectiveTrackerWidgetSetID()
                if s and not issecretvalue(s) and s == setID then return true end
            end
            if C_UIWidgetManager.GetTopCenterWidgetSetID then
                local s = C_UIWidgetManager.GetTopCenterWidgetSetID()
                if s and not issecretvalue(s) and s == setID then return true end
            end
            if C_UIWidgetManager.GetBelowMinimapWidgetSetID then
                local s = C_UIWidgetManager.GetBelowMinimapWidgetSetID()
                if s and not issecretvalue(s) and s == setID then return true end
            end
        end
        return false
    end

    -- Decoupled widget updates: do NOT re-query C_EventScheduler.
    -- Simply refresh the quest log so ScanEvents reads updated values from C_UIWidgetManager.
    sfui.events.RegisterEvent("UPDATE_UI_WIDGET", function(event, widgetInfo)
        if not sfui.worldevents.is_enabled() or #cachedEvents == 0 then return end
        local setID = widgetInfo and widgetInfo.widgetSetID
        if not setID or HasActiveWidgetSet(setID) then
            if sfui.questlog and sfui.questlog.RequestRefresh then
                sfui.questlog.RequestRefresh()
            end
        end
    end)

    sfui.events.RegisterEvent("UPDATE_ALL_UI_WIDGETS", function()
        if not sfui.worldevents.is_enabled() or #cachedEvents == 0 then return end
        if sfui.questlog and sfui.questlog.RequestRefresh then
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

