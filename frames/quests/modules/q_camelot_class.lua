--[[
    SFUI Tracker Module: Classic Forever / Camelot Class Quests Engine
    frames/quests/modules/q_camelot_class.lua

    Dedicated class quest scanner for sfui.tracker on Warcraft Forever (Camelot) & Classic Era.
    - Positioned between skills (priority 1) and dungeons (priority 20)
    - Styled with class-specific color header
    - Level brackets [14], [18D] via Difficulty.FormatTitle
    - Inline countdown timers after level bracket (e.g. [14] 0:12 Quest Title)
    - Full quest interactions (Click to view, Right-click to collapse, Shift-click to untrack/link)
    - Usable quest items & progress tracking
]]

local addonName, addon                        = ...
local sfui                                    = _G.sfui or {}
sfui.tracker                                  = sfui.tracker or {}
sfui.questlog                                 = sfui.questlog or {}

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

local _G                                      = _G
local C_QuestLog                              = _G.C_QuestLog
local C_TaskQuest                             = _G.C_TaskQuest
local C_SuperTrack                            = _G.C_SuperTrack
local Constants                               = _G.Constants
local GetQuestLogTitle                        = _G.GetQuestLogTitle
local GetNumQuestLogEntries                   = _G.GetNumQuestLogEntries
local GetQuestProgressBarPercent              = _G.GetQuestProgressBarPercent
local InCombatLockdown                        = _G.InCombatLockdown
local IsShiftKeyDown                          = _G.IsShiftKeyDown
local IsControlKeyDown                        = _G.IsControlKeyDown
local IsAltKeyDown                            = _G.IsAltKeyDown
local ChatEdit_GetActiveWindow                = _G.ChatEdit_GetActiveWindow
local ChatEdit_InsertLink                     = _G.ChatEdit_InsertLink
local ChatFrameUtil                           = _G.ChatFrameUtil
local QuestMapFrame_OpenToQuestDetails        = _G.QuestMapFrame_OpenToQuestDetails
local UnitClass                               = _G.UnitClass

local ipairs, pairs, type, tonumber, tostring = _G.ipairs, _G.pairs, _G.type, _G.tonumber, _G.tostring
local math_floor                              = math.floor
local table_insert                            = _G.table.insert
local string_format                           = string.format

-- ─────────────────────────────────────────────────────────
--  HELPERS & CACHE
-- ─────────────────────────────────────────────────────────
local Difficulty                              = sfui.tracker.helpers.difficulty
local Waypoints                               = sfui.tracker.helpers.waypoints
local Items                                   = sfui.tracker.helpers.items
local FindGroup                               = sfui.tracker.helpers.findgroup
local QuestCommon = sfui.tracker.helpers.quest

local wipe                                    = _G.wipe or function(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

local recentlyWatched                         = {}
local manualExpanded                          = {}
local pendingChangedQuests                    = {}

-- ─────────────────────────────────────────────────────────
--  CLASS DETECTION
-- ─────────────────────────────────────────────────────────
local GetPlayerClass = QuestCommon.GetPlayerClassLocalized

local IsClassQuest = QuestCommon.IsClassQuest

-- ─────────────────────────────────────────────────────────
--  WATCH STATE & PROGRESS DETAILS
-- ─────────────────────────────────────────────────────────
local function IsQuestWatched(questID, questLogIndex)
    return QuestCommon.IsQuestWatched(questID, questLogIndex, recentlyWatched)
end

local IsWorldQuest = QuestCommon.IsWorldQuest

local function AutoTrackQuest(questID, questLogIndex)
    return QuestCommon.AutoTrackQuest(questID, questLogIndex, recentlyWatched, pendingChangedQuests)
end

local function GetQuestProgressDetails(questID, questLogIndex, isComplete, objs, canClickToComplete)
    if isComplete then
        local tag = canClickToComplete and " |cffff00ff(Complete)|r" or " |cff33ff33(Complete)|r"
        return true, tag
    end

    if GetQuestProgressBarPercent then
        local pct = GetQuestProgressBarPercent(questID)
        if pct and pct > 0 then
            return true, string_format(" |cffa0a0a0(%d%%)|r", math_floor(pct + 0.5))
        end
    end

    if objs and #objs > 0 then
        local total = #objs
        local finished = 0
        local hasProgress = false

        for _, obj in ipairs(objs) do
            if obj.finished then
                finished = finished + 1
                hasProgress = true
            elseif obj.numFulfilled and obj.numFulfilled > 0 then
                hasProgress = true
            end
        end

        local inlineTag = ""
        if total > 1 and finished < total then
            inlineTag = string_format(" |cffa0a0a0(%d/%d)|r", finished, total)
        end

        return hasProgress, inlineTag
    end

    if questLogIndex and _G.GetNumQuestLeaderBoards and _G.GetQuestLogLeaderBoard then
        local num = _G.GetNumQuestLeaderBoards(questLogIndex) or 0
        if num > 0 then
            local finished = 0
            for objIndex = 1, num do
                local _, _, isFinished = _G.GetQuestLogLeaderBoard(objIndex, questLogIndex)
                if isFinished then
                    finished = finished + 1
                end
            end
            local inlineTag = ""
            if num > 1 and finished < num then
                inlineTag = string_format(" |cffa0a0a0(%d/%d)|r", finished, num)
            end
            return (finished > 0), inlineTag
        end
    end

    return false, ""
end

-- ─────────────────────────────────────────────────────────
--  TIMER WATCHER & FORMATTER
-- ─────────────────────────────────────────────────────────
local isTimerWatcherActive = false

local FormatQuestTimer = QuestCommon.FormatQuestTimer

-- ─────────────────────────────────────────────────────────
--  CHAT LINK & CLICK HANDLERS
-- ─────────────────────────────────────────────────────────
local TryInsertQuestLink = QuestCommon.TryInsertQuestLink

local function OnQuestBlockClick(block, mouseButton, questID, questLogIndex, questTitle, isWorldQuest, isCurrentlyExpanded, canClickToComplete)
    if not questID then return end

    -- 1. Click-to-complete (Auto-complete / Talk quests)
    if canClickToComplete then
        if InCombatLockdown and InCombatLockdown() then return end
        if _G.ShowQuestComplete then
            _G.ShowQuestComplete(questLogIndex or questID)
            return
        end
        if C_TaskQuest and C_TaskQuest.RequestPreloadRewardData then
            C_TaskQuest.RequestPreloadRewardData(questID)
        end
    end

    -- 2. Ctrl-Click: Insert Link into Chat Window
    if IsControlKeyDown and IsControlKeyDown() and not IsAltKeyDown() then
        if TryInsertQuestLink(questID, questLogIndex, questTitle) then
            return
        end
    end

    -- 3. Ctrl-Alt-Click: Abandon Quest
    if IsControlKeyDown and IsControlKeyDown() and IsAltKeyDown and IsAltKeyDown() then
        if InCombatLockdown and InCombatLockdown() then return end
        if C_QuestLog and C_QuestLog.CanAbandonQuest and C_QuestLog.CanAbandonQuest(questID) then
            if _G.QuestMapQuestOptions_AbandonQuest then
                _G.QuestMapQuestOptions_AbandonQuest(questID)
                return
            end

            local title = questTitle or (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)) or "Quest"
            local items = (C_QuestLog.GetAbandonQuestItems and C_QuestLog.GetAbandonQuestItems()) or nil
            if items and _G.StaticPopup_Show then
                _G.StaticPopup_Show("ABANDON_QUEST_WITH_ITEMS", title, items)
            elseif _G.StaticPopup_Show then
                _G.StaticPopup_Show("ABANDON_QUEST", title)
            elseif C_QuestLog.AbandonQuest then
                C_QuestLog.AbandonQuest()
            end
        else
            sfui.common.print("quest cannot be abandoned.")
        end
        return
    end

    -- 4. Alt-Click: Share Quest with Party
    if IsAltKeyDown and IsAltKeyDown() then
        if InCombatLockdown and InCombatLockdown() then return end
        local inGroup = (_G.IsInGroup and _G.IsInGroup())
            or (_G.GetNumGroupMembers and _G.GetNumGroupMembers() > 0)
            or (_G.GetNumSubgroupMembers and _G.GetNumSubgroupMembers() > 0)
        if not inGroup then
            sfui.common.print("you are not in a group.")
            return
        end

        local canPush = true
        if sfui.api and sfui.api.IsQuestPushable then
            canPush = sfui.api.IsQuestPushable(questID, questLogIndex)
        elseif C_QuestLog and C_QuestLog.IsPushableQuest then
            local ok, res = pcall(C_QuestLog.IsPushableQuest, questID)
            if ok and res ~= nil then canPush = res end
        end

        if not canPush then
            sfui.common.print("quest cannot be shared.")
            return
        end

        local shared = false
        if sfui.api and sfui.api.ShareQuest then
            shared = sfui.api.ShareQuest(questID, questLogIndex)
        elseif _G.QuestUtil and _G.QuestUtil.ShareQuest then
            shared = pcall(_G.QuestUtil.ShareQuest, questID)
        elseif _G.QuestLogPushQuest then
            if questLogIndex and _G.SelectQuestLogEntry then
                pcall(_G.SelectQuestLogEntry, questLogIndex)
            end
            shared = pcall(_G.QuestLogPushQuest, questLogIndex) or pcall(_G.QuestLogPushQuest)
        end

        if shared then
            sfui.common.print("shared quest: " .. (questTitle or "quest"))
        else
            sfui.common.print("quest cannot be shared.")
        end
        return
    end

    -- 5. Shift-Click: Untrack or Insert Link into Chat
    if IsShiftKeyDown and IsShiftKeyDown() then
        if TryInsertQuestLink(questID, questLogIndex, questTitle) then
            return
        end

        recentlyWatched[questID] = nil
        manualExpanded[questID] = nil
        if C_QuestLog and C_QuestLog.RemoveQuestWatch then
            C_QuestLog.RemoveQuestWatch(questID)
        elseif _G.RemoveQuestWatch and questLogIndex then
            _G.RemoveQuestWatch(questLogIndex)
        end
        sfui.tracker.RequestRefresh(0.05)
        return
    end

    -- 6. Right-Click: Toggle Criteria Expanded / Collapsed
    if mouseButton == "RightButton" then
        manualExpanded[questID] = not isCurrentlyExpanded
        sfui.tracker.RequestRefresh(0.01)
        return
    end

    -- 7. Left-Click: Open Quest Details in World Map / SuperTrack
    if InCombatLockdown and InCombatLockdown() then return end
    if QuestMapFrame_OpenToQuestDetails then
        QuestMapFrame_OpenToQuestDetails(questID)
    elseif _G.QuestLog_OpenToQuest and questLogIndex then
        _G.QuestLog_OpenToQuest(questLogIndex)
    end

    if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
        C_SuperTrack.SetSuperTrackedQuestID(questID)
    end
end

-- ─────────────────────────────────────────────────────────
--  OBJECTIVE TRACKER MODULE
-- ─────────────────────────────────────────────────────────
local CamelotClassQuestsModule = {
    id       = "camelot_class",
    priority = 10, -- Between skills (1) and dungeons (20)
    events   = {
        "QUEST_LOG_UPDATE",
        "QUEST_WATCH_LIST_CHANGED",
        "QUEST_WATCH_UPDATE",
        "QUEST_LOG_CRITERIA_UPDATE",
        "QUEST_CRITERIA_UPDATE",
        "QUEST_AUTOCOMPLETE",
        "QUEST_ACCEPTED",
        "QUEST_TURNED_IN",
        "QUEST_REMOVED",
        "SUPER_TRACKING_CHANGED",
        "WAYPOINT_RECIEVED",
        "QUEST_POI_UPDATE",
        "UNIT_QUEST_LOG_CHANGED",
        "PLAYER_REGEN_ENABLED",
    },
}

local function OnCamelotClassTimerTick()
    if CamelotClassQuestsModule.MarkDirty then
        CamelotClassQuestsModule:MarkDirty()
    end
    sfui.tracker.RequestRefresh(0.01)
end

local function UpdateTimerWatcher(hasAnyTimers)
    if hasAnyTimers and not isTimerWatcherActive then
        sfui.events.RegisterUpdate("CamelotClassQuestTimers", 1.0, OnCamelotClassTimerTick)
        isTimerWatcherActive = true
    elseif not hasAnyTimers and isTimerWatcherActive then
        sfui.events.UnregisterUpdate("CamelotClassQuestTimers")
        isTimerWatcherActive = false
    end
end

function CamelotClassQuestsModule:Init(engine)
    self.engine = engine
end

function CamelotClassQuestsModule:IsEnabled()
    local enabled = sfui.questlog and sfui.questlog.is_enabled and sfui.questlog.is_enabled()
    if enabled == nil then enabled = true end
    if not enabled then
        UpdateTimerWatcher(false)
        return false
    end
    return true
end

function CamelotClassQuestsModule:OnEvent(event, ...)
    local arg1, arg2 = ...
    local questID = tonumber(arg1)
    local added = arg2
    if not questID and tonumber(arg2) then
        questID = tonumber(arg2)
        added = select(3, ...)
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if next(pendingChangedQuests) then
            for qID, qIdx in pairs(pendingChangedQuests) do
                AutoTrackQuest(qID, type(qIdx) == "number" and qIdx or nil)
                if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
                    C_SuperTrack.SetSuperTrackedQuestID(qID)
                end
            end
            wipe(pendingChangedQuests)
            sfui.tracker.RequestRefresh(0.05)
        end
        return
    end

    if event == "QUEST_ACCEPTED" then
        if questID and questID > 0 then
            if not InCombatLockdown or not InCombatLockdown() then
                AutoTrackQuest(questID)
            else
                pendingChangedQuests[questID] = true
            end
        end
    elseif event == "QUEST_WATCH_UPDATE" or event == "QUEST_LOG_CRITERIA_UPDATE" or event == "QUEST_CRITERIA_UPDATE" or event == "QUEST_AUTOCOMPLETE" then
        if questID and questID > 0 then
            if not InCombatLockdown or not InCombatLockdown() then
                AutoTrackQuest(questID)
                if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
                    C_SuperTrack.SetSuperTrackedQuestID(questID)
                end
            else
                pendingChangedQuests[questID] = true
            end
        end
    elseif event == "QUEST_WATCH_LIST_CHANGED" then
        if questID and questID > 0 then
            if added == false then
                recentlyWatched[questID] = nil
                manualExpanded[questID] = nil
            end
        end
    elseif event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN" then
        if questID and questID > 0 then
            recentlyWatched[questID] = nil
            manualExpanded[questID] = nil
        end
    end

    self:MarkDirty()
end

function CamelotClassQuestsModule:BuildBlocks(container)
    if not self:IsEnabled() then
        UpdateTimerWatcher(false)
        return nil
    end

    local activeTimers = {}
    local hasAnyTimers = false
    if C_QuestLog and C_QuestLog.GetQuestTimers then
        local timers = C_QuestLog.GetQuestTimers()
        if timers then
            for _, info in ipairs(timers) do
                if info.questID and info.questTimer and info.questTimer > 0 then
                    activeTimers[info.questID] = info.questTimer
                    hasAnyTimers = true
                end
            end
        end
    end

    local superTrackedQuestID = nil
    if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
        superTrackedQuestID = C_SuperTrack.GetSuperTrackedQuestID()
    end

    local numEntries = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries())
        or (GetNumQuestLogEntries and GetNumQuestLogEntries())
        or 0

    local blocks = {}
    local currentHeaderTitle = "Miscellaneous"

    for i = 1, numEntries do
        local questID = nil
        local title = nil
        local isHeader = false
        local isComplete = false
        local level = 0
        local suggestedGroup = 0
        local isAutoComplete = false

        if C_QuestLog and C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(i)
            if info then
                title = info.title
                level = info.level or 0
                isHeader = info.isHeader
                isComplete = (info.isComplete == true)
                questID = info.questID
                suggestedGroup = info.suggestedGroup or 0
                isAutoComplete = (info.isAutoComplete == true)
            end
        elseif GetQuestLogTitle then
            local qTitle, qLevel, _, qHeader, _, qComp, _, qID = GetQuestLogTitle(i)
            title = qTitle
            level = qLevel or 0
            isHeader = qHeader
            isComplete = (qComp == 1)
            questID = qID
        end

        if not isAutoComplete and _G.GetQuestLogIsAutoComplete then
            isAutoComplete = (_G.GetQuestLogIsAutoComplete(i) == true)
        end
        if not isAutoComplete and _G.QuestCache and _G.QuestCache.Get and questID then
            local q = _G.QuestCache:Get(questID)
            if q and q.isAutoComplete then
                isAutoComplete = true
            end
        end

        if isHeader then
            currentHeaderTitle = title or "Miscellaneous"
        elseif questID and questID > 0 and not IsWorldQuest(questID) and IsQuestWatched(questID, i) then
            if IsClassQuest(questID, i, currentHeaderTitle) then
                if C_QuestLog and C_QuestLog.IsComplete then
                    isComplete = C_QuestLog.IsComplete(questID) or isComplete
                end
                local isFailed = (C_QuestLog and C_QuestLog.IsFailed and C_QuestLog.IsFailed(questID)) or false
                local canClickToComplete = isComplete and isAutoComplete

                local secondsLeft = activeTimers[questID]
                if not secondsLeft and C_QuestLog and C_QuestLog.GetTimeAllowed and questID then
                    local total, elapsed = C_QuestLog.GetTimeAllowed(questID)
                    if total and elapsed and total > 0 and elapsed < total then
                        secondsLeft = total - elapsed
                        hasAnyTimers = true
                    end
                end
                if not secondsLeft and _G.GetQuestLogTimeLeft then
                    local rem = _G.GetQuestLogTimeLeft(i)
                    if rem and rem > 0 then
                        secondsLeft = rem
                        hasAnyTimers = true
                    end
                end

                local timerText, rawClock = nil, nil
                if secondsLeft and secondsLeft > 0 then
                    timerText, rawClock = FormatQuestTimer(secondsLeft)
                end

                -- Format Title: Difficulty Bracket [14], [18D] and optional timer
                local entryStub = {
                    level          = level,
                    questID        = questID,
                    questLogIndex  = i,
                    suggestedGroup = suggestedGroup,
                    timer          = timerText,
                }

                local displayTitle = title or "Quest"
                if Difficulty and Difficulty.FormatTitle then
                    displayTitle = Difficulty.FormatTitle(entryStub, displayTitle)
                elseif timerText then
                    displayTitle = timerText .. " " .. displayTitle
                end

                local objs = C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(questID)

                if isComplete and manualExpanded[questID] ~= nil then
                    manualExpanded[questID] = nil
                end

                local hasProgress, inlineTag = GetQuestProgressDetails(questID, i, isComplete, objs, canClickToComplete)
                local defaultExpanded = (hasProgress and not isComplete)
                local isExpanded
                if manualExpanded[questID] ~= nil then
                    isExpanded = (manualExpanded[questID] == true)
                else
                    isExpanded = defaultExpanded
                end

                if not isExpanded and inlineTag ~= "" then
                    displayTitle = displayTitle .. inlineTag
                end

                -- Objectives lines
                local lines = {}
                local progressBar = nil

                if isExpanded then
                    if isComplete then
                        local compText = (Waypoints and Waypoints.GetCompletionText(i, canClickToComplete))
                            or (canClickToComplete and (_G.QUEST_WATCH_QUEST_COMPLETE or "Click to complete quest"))
                            or "Ready for turn-in"
                        table_insert(lines, {
                            text      = compText,
                            completed = true,
                            color     = canClickToComplete and { 1.0, 0.0, 1.0, 1 } or { 0.2, 1.0, 0.2, 1 },
                        })
                    else
                        if objs and #objs > 0 then
                            for _, obj in ipairs(objs) do
                                local isBar = (obj.type == "progressbar" or obj.type == 8)
                                if isBar then
                                    local pct = 0
                                    if GetQuestProgressBarPercent then
                                        pct = GetQuestProgressBarPercent(questID) or 0
                                    end
                                    progressBar = {
                                        min   = 0,
                                        max   = 100,
                                        value = pct,
                                        text  = string_format("%d%%", math_floor(pct + 0.5)),
                                    }
                                else
                                    if not obj.finished then
                                        local isDone = false
                                        local oColor = isDone and { 0.3, 0.8, 0.3, 1 } or { 0.85, 0.85, 0.85, 1 }
                                        table_insert(lines, {
                                            text      = obj.text or "",
                                            completed = isDone,
                                            color     = oColor,
                                        })
                                    end
                                end
                            end
                        elseif _G.GetNumQuestLeaderBoards and _G.GetQuestLogLeaderBoard then
                            local numObj = _G.GetNumQuestLeaderBoards(i) or 0
                            for objIndex = 1, numObj do
                                local lineText, _, isFinished = _G.GetQuestLogLeaderBoard(objIndex, i)
                                if lineText and not isFinished then
                                    local oColor = { 0.85, 0.85, 0.85, 1 }
                                    table_insert(lines, {
                                        text      = lineText,
                                        completed = false,
                                        color     = oColor,
                                    })
                                end
                            end
                        end
                    end
                end

                local isSuper = (superTrackedQuestID and superTrackedQuestID == questID)
                local itemInfo = Items and Items.GetQuestItemInfo and Items.GetQuestItemInfo(i, isComplete)
                local canFindGroup = FindGroup and FindGroup.CanFindGroup and FindGroup.CanFindGroup(questID) or false

                local titleColor = { 1, 1, 1, 1 }
                if canClickToComplete then
                    titleColor = { 1.0, 0.0, 1.0, 1 } -- #FF00FF
                elseif isComplete then
                    titleColor = { 0.2, 1.0, 0.2, 1 }
                elseif isFailed then
                    titleColor = { 1.0, 0.2, 0.2, 1 }
                end

                local isWarband = false
                if C_QuestLog and C_QuestLog.IsQuestFlaggedCompletedOnAccount then
                    isWarband = (C_QuestLog.IsQuestFlaggedCompletedOnAccount(questID) == true)
                end

                table_insert(blocks, {
                    title              = displayTitle,
                    rawTitle           = title,
                    titleColor         = titleColor,
                    isSuperTracked     = isSuper,
                    questID            = questID,
                    questLogIndex      = i,
                    zoneName           = currentHeaderTitle,
                    level              = level,
                    suggestedGroup     = suggestedGroup,
                    isComplete         = isComplete,
                    canClickToComplete = canClickToComplete,
                    isFailed           = isFailed,
                    isRepeatable       = false,
                    isWarbandCompleted = isWarband,
                    itemInfo           = itemInfo,
                    timerBar           = nil, -- Suppressed on Camelot
                    timeLeftText       = rawClock and ("time remaining: " .. rawClock) or nil,
                    canFindGroup       = canFindGroup,
                    isExpanded         = isExpanded,
                    lines              = lines,
                    progressBar        = progressBar,
                    OnClick            = function(block, btn)
                        OnQuestBlockClick(block, btn, questID, i, title, false, isExpanded, canClickToComplete)
                    end,
                })
            end
        end
    end

    UpdateTimerWatcher(hasAnyTimers)

    if #blocks > 0 then
        local pClass = GetPlayerClass()
        local classTitle = (pClass and pClass:lower()) or "class"
        return {
            {
                id           = "class",
                title        = classTitle,
                color        = sfui.common.get_class_or_spec_color(),
                count        = #blocks,
                blocks       = blocks,
                OnShiftClick = function()
                    for _, b in ipairs(blocks) do
                        if b.questID then
                            recentlyWatched[b.questID] = nil
                            manualExpanded[b.questID] = nil
                            if C_QuestLog and C_QuestLog.RemoveQuestWatch then
                                C_QuestLog.RemoveQuestWatch(b.questID)
                            elseif _G.RemoveQuestWatch and b.questLogIndex then
                                _G.RemoveQuestWatch(b.questLogIndex)
                            end
                        end
                    end
                    sfui.tracker.RequestRefresh(0.01)
                end,
            }
        }
    end

    return nil
end

sfui.tracker.RegisterModule(CamelotClassQuestsModule)
return CamelotClassQuestsModule
