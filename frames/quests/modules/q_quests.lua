--[[
    SFUI Tracker Module: Core Quests Engine
    frames/quests/modules/quests.lua

    Pluggable quest log scanner for sfui.tracker.
    Seamlessly adapts between:
      - Retail Mode: Grouped by Classification (Important, Campaign, Meta, Quests) with Warband badges.
      - Camelot Mode: Grouped by Zone sections with Current Zone floating to top,
                      Level brackets [14], [18D], capacity badge [16/20], and suppressed timer bars.
]]

local addonName, addon = ...
sfui = sfui or {}
sfui.tracker = sfui.tracker or {}
sfui.questlog = sfui.questlog or {}

local _G = _G
local C_QuestLog = _G.C_QuestLog
local C_TaskQuest = _G.C_TaskQuest
local C_SuperTrack = _G.C_SuperTrack
local C_PlayerInfo = _G.C_PlayerInfo
local Enum = _G.Enum
local Constants = _G.Constants
local GetNumAutoQuestPopUps = _G.GetNumAutoQuestPopUps
local GetAutoQuestPopUp = _G.GetAutoQuestPopUp
local GetQuestLogTitle = _G.GetQuestLogTitle
local GetNumQuestLogEntries = _G.GetNumQuestLogEntries
local GetQuestProgressBarPercent = _G.GetQuestProgressBarPercent
local GetRealZoneText = _G.GetRealZoneText
local GetZoneText = _G.GetZoneText
local IsInGroup = _G.IsInGroup
local InCombatLockdown = _G.InCombatLockdown
local IsShiftKeyDown = _G.IsShiftKeyDown
local IsControlKeyDown = _G.IsControlKeyDown
local IsAltKeyDown = _G.IsAltKeyDown
local ChatEdit_GetActiveWindow = _G.ChatEdit_GetActiveWindow
local ChatEdit_InsertLink = _G.ChatEdit_InsertLink
local ChatFrameUtil = _G.ChatFrameUtil
local QuestMapFrame_OpenToQuestDetails = _G.QuestMapFrame_OpenToQuestDetails

local ipairs, pairs, type, tonumber, tostring = _G.ipairs, _G.pairs, _G.type, _G.tonumber, _G.tostring
local math_floor = math.floor
local table_insert, table_sort = _G.table.insert, _G.table.sort
local string_format = string.format

local issecretvalue = (sfui.common and sfui.common.issecretvalue) or _G.issecretvalue or function() return false end

-- ─────────────────────────────────────────────────────────
--  HELPERS & CACHE
-- ─────────────────────────────────────────────────────────
local Difficulty = sfui.tracker.helpers and sfui.tracker.helpers.difficulty
local Waypoints  = sfui.tracker.helpers and sfui.tracker.helpers.waypoints
local TimerBars  = sfui.tracker.helpers and sfui.tracker.helpers.timerbars
local Items      = sfui.tracker.helpers and sfui.tracker.helpers.items
local FindGroup  = sfui.tracker.helpers and sfui.tracker.helpers.findgroup

local wipe = _G.wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

-- ─────────────────────────────────────────────────────────
--  PROGRESS SNAPSHOT (Used to detect progress changes)
-- ─────────────────────────────────────────────────────────
local lastQuestProgress = {}
local initialScanDone = false
local snapshotParts = {}

local recentlyWatched = {}

local function GetQuestProgressSnapshot(questID, questLogIndex, isComplete, objs)
    wipe(snapshotParts)
    table_insert(snapshotParts, isComplete and "1" or "0")

    if GetQuestProgressBarPercent then
        local pct = GetQuestProgressBarPercent(questID)
        table_insert(snapshotParts, "P:" .. tostring(pct or 0))
    end

    if objs and #objs > 0 then
        for idx, obj in ipairs(objs) do
            local fin = obj.finished and "1" or "0"
            local cur = obj.numFulfilled or ""
            local req = obj.numRequired or ""
            local txt = obj.text or ""
            table_insert(snapshotParts, idx .. ":" .. fin .. ":" .. cur .. "/" .. req .. ":" .. txt)
        end
    elseif questLogIndex and _G.GetNumQuestLeaderBoards and _G.GetQuestLogLeaderBoard then
        local numLeaderBoards = _G.GetNumQuestLeaderBoards(questLogIndex) or 0
        for objIndex = 1, numLeaderBoards do
            local desc, _, isFinished = _G.GetQuestLogLeaderBoard(objIndex, questLogIndex)
            local fin = isFinished and "1" or "0"
            local txt = desc or ""
            table_insert(snapshotParts, objIndex .. ":" .. fin .. ":" .. txt)
        end
    end

    return table.concat(snapshotParts, ";")
end

local function IsCamelotClient()
    return sfui.isForever or (sfui.compat and (sfui.compat.is_wow_forever or sfui.compat.is_classic_era or sfui.compat.is_classic))
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

local function IsQuestWatched(questID, questLogIndex)
    if not questID or questID <= 0 then return false end
    if recentlyWatched[questID] then return true end
    if C_QuestLog and C_QuestLog.GetQuestWatchType then
        local wt = C_QuestLog.GetQuestWatchType(questID)
        if wt ~= nil then return true end
    end
    if C_QuestLog and C_QuestLog.IsQuestWatched then
        if C_QuestLog.IsQuestWatched(questID) then return true end
        if questLogIndex and C_QuestLog.IsQuestWatched(questLogIndex) then return true end
    end
    if _G.IsQuestWatched then
        if questLogIndex and _G.IsQuestWatched(questLogIndex) then return true end
    end
    return false
end

local function IsWorldQuest(questID)
    if not questID or questID <= 0 then return false end
    if C_QuestLog and C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(questID) then
        return true
    end
    if _G.QuestUtils_IsQuestWorldQuest and _G.QuestUtils_IsQuestWorldQuest(questID) then
        return true
    end
    return false
end

--- Automatically track a quest when objectives update or progress occurs
--- @param questID number Quest ID to track
--- @param questLogIndex number|nil Optional quest log index for classic clients
local function AutoTrackQuest(questID, questLogIndex)
    if not questID or questID <= 0 then return false end
    if IsWorldQuest(questID) then return false end

    -- Avoid tracking task quests or bounties as persistent watches
    if C_QuestLog and ((C_QuestLog.IsQuestBounty and C_QuestLog.IsQuestBounty(questID))
        or (C_QuestLog.IsQuestTask and C_QuestLog.IsQuestTask(questID))) then
        return false
    end

    local alreadyWatched = IsQuestWatched(questID, questLogIndex)

    if not alreadyWatched then
        local maxWatches = (Constants and Constants.QuestWatchConsts and Constants.QuestWatchConsts.MAX_QUEST_WATCHES)
            or _G.MAX_WATCHABLE_QUESTS
            or 25

        local canWatch = true
        if C_QuestLog and C_QuestLog.GetNumQuestWatches then
            canWatch = (C_QuestLog.GetNumQuestWatches() < maxWatches)
        elseif _G.GetNumQuestWatches then
            canWatch = (_G.GetNumQuestWatches() < maxWatches)
        end

        if canWatch then
            recentlyWatched[questID] = true
            if C_QuestLog and C_QuestLog.AddQuestWatch then
                pcall(C_QuestLog.AddQuestWatch, questID)
            elseif _G.AddQuestWatch then
                local idx = questLogIndex
                if not idx or idx <= 0 then
                    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
                        idx = C_QuestLog.GetLogIndexForQuestID(questID)
                    elseif _G.GetQuestLogIndexByID then
                        idx = _G.GetQuestLogIndexByID(questID)
                    end
                end
                if idx and idx > 0 then
                    pcall(_G.AddQuestWatch, idx)
                end
            end
        end
    end

    local state = GetQLState()
    state.expandedQuests = state.expandedQuests or {}
    state.expandedQuests[questID] = true

    return true
end

local seasonalWeeklySet = nil
local function BuildSeasonalWeeklySet()
    seasonalWeeklySet = {}
    if sfui.season then
        if sfui.season.WEEKLY_QUESTS then
            for _, def in ipairs(sfui.season.WEEKLY_QUESTS) do
                if def.questID then seasonalWeeklySet[def.questID] = true end
                if def.wrapperID then seasonalWeeklySet[def.wrapperID] = true end
                if def.pool then
                    for _, pid in ipairs(def.pool) do
                        seasonalWeeklySet[pid] = true
                    end
                end
            end
        end
        if sfui.season.PROF_KP_SOURCES then
            for _, src in pairs(sfui.season.PROF_KP_SOURCES) do
                if src.quest then
                    for _, qid in ipairs(src.quest) do
                        seasonalWeeklySet[qid] = true
                    end
                end
            end
        end
    end
end

local function IsWeeklyQuest(questID, frequency)
    if frequency == 2 then return true end
    if Enum and Enum.QuestFrequency and frequency == Enum.QuestFrequency.Weekly then
        return true
    end
    if C_QuestLog then
        if C_QuestLog.IsQuestWeekly and C_QuestLog.IsQuestWeekly(questID) then
            return true
        end
        if C_QuestLog.IsWeeklyQuest and C_QuestLog.IsWeeklyQuest(questID) then
            return true
        end
    end
    if not seasonalWeeklySet then
        BuildSeasonalWeeklySet()
    end
    if questID and seasonalWeeklySet and seasonalWeeklySet[questID] then
        return true
    end
    return false
end

local function IsRepeatableQuest(questID, frequency)
    if not questID then return false end
    if C_QuestLog and C_QuestLog.IsRepeatableQuest and C_QuestLog.IsRepeatableQuest(questID) then
        return true
    end
    if frequency and frequency > 0 then
        return true
    end
    if C_QuestLog then
        if C_QuestLog.IsQuestDaily and C_QuestLog.IsQuestDaily(questID) then
            return true
        end
        if C_QuestLog.IsDailyQuest and C_QuestLog.IsDailyQuest(questID) then
            return true
        end
    end
    return false
end

local function GetQuestCapacityInfo()
    local numQuests = 0
    local numEntries = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries())
        or (GetNumQuestLogEntries and GetNumQuestLogEntries())
        or 0

    for i = 1, numEntries do
        local isHeader = false
        if C_QuestLog and C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(i)
            if info then isHeader = info.isHeader end
        elseif GetQuestLogTitle then
            local _, _, _, tHeader = GetQuestLogTitle(i)
            isHeader = tHeader
        end
        if not isHeader then
            numQuests = numQuests + 1
        end
    end

    local maxQuests = (C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept()) or 20
    local color = "|cffffffff"
    if numQuests >= maxQuests then
        color = "|cffff2020" -- Full!
    elseif numQuests >= (maxQuests - 2) then
        color = "|cffff9900" -- Near cap
    end

    local formatted = string_format("%s[%d/%d]|r", color, numQuests, maxQuests)
    return numQuests, maxQuests, formatted
end

-- ─────────────────────────────────────────────────────────
--  QUEST CLICK HANDLER
-- ─────────────────────────────────────────────────────────
local function OnQuestBlockClick(block, mouseButton, questID, questLogIndex, questTitle, isAutoOffer, isCurrentlyExpanded, isClickToComplete)
    if not questID then return end

    -- 1. Auto-Quest Offer Click
    if isAutoOffer then
        if IsShiftKeyDown and IsShiftKeyDown() then
            if _G.RemoveAutoQuestPopUp then
                _G.RemoveAutoQuestPopUp(questID)
                if sfui.tracker and sfui.tracker.RequestRefresh then
                    sfui.tracker.RequestRefresh(0.05)
                end
            end
            return
        end
        if _G.ShowQuestOffer then
            _G.ShowQuestOffer(questID)
        end
        return
    end

    -- 2. Click to Complete Quest (Auto-Complete / Turn-in by clicking)
    if isClickToComplete and mouseButton ~= "RightButton" and not (IsControlKeyDown and IsControlKeyDown()) and not (IsAltKeyDown and IsAltKeyDown()) and not (IsShiftKeyDown and IsShiftKeyDown()) then
        if _G.RemoveAutoQuestPopUp then
            pcall(_G.RemoveAutoQuestPopUp, questID)
        end
        if _G.ShowQuestComplete then
            local param = (IsCamelotClient() and questLogIndex) or questID
            local ok = pcall(_G.ShowQuestComplete, param)
            if not ok and questLogIndex and param ~= questLogIndex then
                pcall(_G.ShowQuestComplete, questLogIndex)
            end
            return
        end
    end

    -- 2. Ctrl-Click: Abandon Quest
    if IsControlKeyDown and IsControlKeyDown() then
        if InCombatLockdown and InCombatLockdown() then return end
        if C_QuestLog and C_QuestLog.CanAbandonQuest and C_QuestLog.CanAbandonQuest(questID) then
            if C_QuestLog.SetSelectedQuest then
                C_QuestLog.SetSelectedQuest(questID)
            end
            if C_QuestLog.SetAbandonQuest then
                C_QuestLog.SetAbandonQuest()
            end
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
            print("|cff8888ff[SFUI]|r Quest cannot be abandoned.")
        end
        return
    end

    -- 3. Alt-Click: Share Quest with Party
    if IsAltKeyDown and IsAltKeyDown() then
        if InCombatLockdown and InCombatLockdown() then return end
        if C_QuestLog and C_QuestLog.IsPushableQuest and C_QuestLog.IsPushableQuest(questID) then
            C_QuestLog.PushQuestToParty(questID)
            print("|cff8888ff[SFUI]|r Shared quest: " .. (questTitle or "Quest"))
        else
            print("|cff8888ff[SFUI]|r Quest cannot be shared.")
        end
        return
    end

    -- 4. Shift-Click: Untrack or Insert Link into Chat
    if IsShiftKeyDown and IsShiftKeyDown() then
        local activeChat = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
        if activeChat and activeChat:IsShown() and activeChat:HasFocus() then
            local link = (C_QuestLog and C_QuestLog.GetQuestLink and C_QuestLog.GetQuestLink(questID))
                       or (_G.GetQuestLink and _G.GetQuestLink(questLogIndex or questID))
            if link then
                if ChatFrameUtil and ChatFrameUtil.InsertLink and ChatFrameUtil.InsertLink(link) then return end
                if ChatEdit_InsertLink and ChatEdit_InsertLink(link) then return end
            end
        end

        -- Untrack quest
        recentlyWatched[questID] = nil
        if C_QuestLog and C_QuestLog.RemoveQuestWatch then
            C_QuestLog.RemoveQuestWatch(questID)
        elseif _G.RemoveQuestWatch and questLogIndex then
            _G.RemoveQuestWatch(questLogIndex)
        end
        local state = GetQLState()
        if state and state.expandedQuests then
            state.expandedQuests[questID] = nil
        end
        if sfui.tracker and sfui.tracker.RequestRefresh then
            sfui.tracker.RequestRefresh(0.05)
        end
        return
    end

    -- 5. Right-Click: Toggle Criteria Expanded / Collapsed
    if mouseButton == "RightButton" then
        local state = GetQLState()
        state.expandedQuests = state.expandedQuests or {}
        state.expandedQuests[questID] = not isCurrentlyExpanded
        if sfui.tracker and sfui.tracker.RequestRefresh then
            sfui.tracker.RequestRefresh(0.05)
        end
        return
    end

    -- 6. Left-Click: Open Quest Details in World Map / SuperTrack
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
--  SCANNER IMPLEMENTATION
-- ─────────────────────────────────────────────────────────
local QuestsModule = {
    id       = "quests",
    priority = 20,
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
        "ZONE_CHANGED_NEW_AREA",
        "UNIT_QUEST_LOG_CHANGED",
    },
}

function QuestsModule:Init(engine)
    self.engine = engine
end

function QuestsModule:OnEvent(event, ...)
    local arg1, arg2 = ...
    local questID = tonumber(arg1)
    local added = arg2
    if not questID and tonumber(arg2) then
        questID = tonumber(arg2)
        added = select(3, ...)
    end

    if event == "QUEST_ACCEPTED" then
        if questID and questID > 0 then
            AutoTrackQuest(questID)
        end
    elseif event == "QUEST_WATCH_UPDATE" or event == "QUEST_LOG_CRITERIA_UPDATE" or event == "QUEST_CRITERIA_UPDATE" or event == "QUEST_AUTOCOMPLETE" then
        if questID and questID > 0 then
            AutoTrackQuest(questID)
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
                pcall(C_SuperTrack.SetSuperTrackedQuestID, questID)
            end
        end
    elseif event == "QUEST_WATCH_LIST_CHANGED" then
        if questID and questID > 0 then
            if added == false then
                recentlyWatched[questID] = nil
            elseif added == true or added == nil then
                local state = GetQLState()
                state.expandedQuests = state.expandedQuests or {}
                state.expandedQuests[questID] = true
            end
        end
    elseif event == "QUEST_TURNED_IN" or event == "QUEST_REMOVED" then
        if questID and questID > 0 then
            recentlyWatched[questID] = nil
            local state = GetQLState()
            if state and state.expandedQuests then
                state.expandedQuests[questID] = nil
            end
            lastQuestProgress[questID] = nil
        end
    end

    if event == "QUEST_WATCH_LIST_CHANGED" or event == "QUEST_WATCH_UPDATE" or event == "QUEST_LOG_CRITERIA_UPDATE" or event == "QUEST_CRITERIA_UPDATE" or event == "QUEST_ACCEPTED" then
        self:MarkDirty(0.01)
    else
        self:MarkDirty()
    end
end

function QuestsModule:IsEnabled()
    return true
end

function QuestsModule:BuildBlocks(container)
    local isCamelot = IsCamelotClient()
    local state = GetQLState()
    local expandedQuests = state.expandedQuests or {}

    local superTrackedQuestID = nil
    if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
        superTrackedQuestID = C_SuperTrack.GetSuperTrackedQuestID()
    end

    local numEntries = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries())
        or (GetNumQuestLogEntries and GetNumQuestLogEntries())
        or 0

    local currentZoneName = (GetRealZoneText and GetRealZoneText())
        or (GetZoneText and GetZoneText())
        or ""

    -- ─────────────────────────────────────────────────────────
    --  PROGRESS MONITOR: Pre-pass to detect quest progress change
    -- ─────────────────────────────────────────────────────────
    local currentActiveQuests = {}
    local changedQuests = {}

    for i = 1, numEntries do
        local qID = nil
        local isHeader = false
        local isComplete = false

        if C_QuestLog and C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(i)
            if info then
                qID = info.questID
                isHeader = info.isHeader
                isComplete = (info.isComplete == true)
            end
        elseif GetQuestLogTitle then
            local _, _, _, isH, _, isC, _, questID = GetQuestLogTitle(i)
            qID = questID
            isHeader = isH
            isComplete = (isC == 1 or isC == true)
        end

        if qID and qID > 0 and not isHeader and not IsWorldQuest(qID) then
            currentActiveQuests[qID] = true
            local objs = C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(qID)
            local currentSig = GetQuestProgressSnapshot(qID, i, isComplete, objs)
            local prevSig = lastQuestProgress[qID]

            if initialScanDone and prevSig and prevSig ~= currentSig then
                changedQuests[qID] = i
            end
            lastQuestProgress[qID] = currentSig
        end
    end

    -- Clean up untracked or abandoned quests from snapshot cache
    for qID in pairs(lastQuestProgress) do
        if not currentActiveQuests[qID] then
            lastQuestProgress[qID] = nil
        end
    end

    -- When any quest's progress has changed, automatically track it and super-track it
    for cQID, cIdx in pairs(changedQuests) do
        AutoTrackQuest(cQID, cIdx)
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
            pcall(C_SuperTrack.SetSuperTrackedQuestID, cQID)
            superTrackedQuestID = cQID
        end
    end

    -- Sections accumulator
    local sectionMap = {}
    local sectionOrder = {}

    local function GetOrCreateSection(secID, title, color)
        if not sectionMap[secID] then
            local sec = {
                id     = secID,
                title  = title,
                color  = color or { 1, 1, 1 },
                blocks = {},
            }
            sectionMap[secID] = sec
            table_insert(sectionOrder, sec)
        end
        return sectionMap[secID]
    end

    -- 1. Scan Auto-Quest Popups (Retail Mode)
    local autoCompletePopups = {}
    if not isCamelot and GetNumAutoQuestPopUps and GetAutoQuestPopUp then
        local numPopups = GetNumAutoQuestPopUps() or 0
        for i = 1, numPopups do
            local qID, popUpType = GetAutoQuestPopUp(i)
            if qID and qID > 0 then
                local popTitle = (C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(qID)) or "Quest"
                if popUpType == "OFFER" then
                    local sec = GetOrCreateSection("important", "Important", { 1.0, 0.4, 0.2 })
                    table_insert(sec.blocks, {
                        title      = "[Offer] " .. popTitle,
                        titleColor = { 1.0, 0.75, 0.2, 1 },
                        lines      = {
                            { text = "Click to view quest offer", completed = false, color = { 0.7, 0.8, 1, 1 } }
                        },
                        OnClick    = function(block, btn)
                            OnQuestBlockClick(block, btn, qID, nil, popTitle, true, false, false)
                        end,
                    })
                elseif popUpType == "COMPLETE" then
                    autoCompletePopups[qID] = true
                    local sec = GetOrCreateSection("important", "Important", { 1.0, 0.0, 1.0 })
                    table_insert(sec.blocks, {
                        title      = "[Complete] " .. popTitle,
                        titleColor = { 1.0, 0.0, 1.0, 1 }, -- #FF00FF
                        lines      = {
                            { text = (QUEST_WATCH_QUEST_COMPLETE or "Click to complete quest"), completed = true, color = { 1.0, 0.0, 1.0, 1 } }
                        },
                        OnClick    = function(block, btn)
                            OnQuestBlockClick(block, btn, qID, nil, popTitle, false, false, true)
                        end,
                    })
                end
            end
        end
    end

    -- 2. Scan Quest Log Entries
    local currentHeaderTitle = "Miscellaneous"

    for i = 1, numEntries do
        local questID = nil
        local title = nil
        local isHeader = false
        local isCollapsed = false
        local isComplete = false
        local isAutoComplete = false
        local frequency = nil
        local questClassification = nil
        local campaignID = nil
        local suggestedGroup = 1
        local level = 0

        if C_QuestLog and C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(i)
            if info then
                isHeader = info.isHeader
                questID = info.questID
                title = info.title
                isCollapsed = info.isCollapsed
                frequency = info.frequency
                questClassification = info.questClassification
                campaignID = info.campaignID
                suggestedGroup = info.suggestedGroup or 1
                level = info.level or 0
                isAutoComplete = (info.isAutoComplete == true)
            end
        elseif GetQuestLogTitle then
            local qTitle, qLevel, qTag, qHeader, qColl, qComp, qFreq, qID = GetQuestLogTitle(i)
            title = qTitle
            level = qLevel or 0
            isHeader = qHeader
            isCollapsed = qColl
            isComplete = (qComp == 1)
            frequency = qFreq
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
        elseif questID and questID > 0 and not IsWorldQuest(questID) and IsQuestWatched(questID, i) and not autoCompletePopups[questID] then
            if C_QuestLog and C_QuestLog.IsComplete then
                isComplete = C_QuestLog.IsComplete(questID) or isComplete
            end
            local isFailed = (C_QuestLog and C_QuestLog.IsFailed and C_QuestLog.IsFailed(questID)) or false
            local canClickToComplete = (isComplete and isAutoComplete) or (autoCompletePopups[questID] == true)

            -- Format Title: Difficulty Bracket or Warband Tag
            local entryStub = {
                level          = level,
                questID        = questID,
                questLogIndex  = i,
                suggestedGroup = suggestedGroup,
            }

            local isRetail = (sfui.isRetail == true) and not isCamelot
            local isWarband = false
            if isRetail and C_QuestLog and C_QuestLog.IsQuestFlaggedCompletedOnAccount then
                isWarband = (C_QuestLog.IsQuestFlaggedCompletedOnAccount(questID) == true)
            end

            local displayTitle = title or "Quest"
            if isCamelot and Difficulty and Difficulty.FormatTitle then
                displayTitle = Difficulty.FormatTitle(entryStub, displayTitle)
            end

            local isWeekly = IsWeeklyQuest(questID, frequency)
            local isRepeatable = isWeekly or IsRepeatableQuest(questID, frequency)

            -- Determine Section ID
            local secID, secTitle, secColor
            if isCamelot then
                local zName = currentHeaderTitle or "Miscellaneous"
                local isCur = (currentZoneName ~= "" and zName:lower() == currentZoneName:lower())
                secID    = "zone_" .. zName
                secTitle = zName:lower() .. (isCur and " [Zone]" or "")
                secColor = isCur and { 0.00, 1.00, 1.00 } or { 1.00, 1.00, 1.00 }
            else
                local QC = Enum and Enum.QuestClassification
                if isWeekly then
                    secID, secTitle, secColor = "activities", "activities", { 0.00, 1.00, 1.00 }
                elseif campaignID and campaignID > 0 or (questClassification == (QC and QC.Campaign)) then
                    secID, secTitle, secColor = "campaign", "campaign", { 0.90, 0.75, 0.10 }
                elseif questClassification == (QC and QC.Meta) or (C_QuestLog and C_QuestLog.IsMetaQuest and C_QuestLog.IsMetaQuest(questID)) then
                    secID, secTitle, secColor = "meta", "meta", { 0.00, 1.00, 1.00 }
                elseif questClassification == (QC and QC.Important) or (C_QuestLog and C_QuestLog.IsImportantQuest and C_QuestLog.IsImportantQuest(questID)) then
                    secID, secTitle, secColor = "important", "important", { 1.00, 0.40, 0.35 }
                else
                    secID, secTitle, secColor = "zone", "quests", { 1.00, 1.00, 1.00 }
                end
            end

            local section = GetOrCreateSection(secID, secTitle, secColor)

            local objs = C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(questID)

            local isExpanded
            if expandedQuests[questID] ~= nil then
                isExpanded = (expandedQuests[questID] == true)
            else
                isExpanded = true -- When a quest is added or tracked, expand it by default
            end

            -- Objectives lines
            local lines = {}
            local progressBar = nil

            if isExpanded then
                if isComplete then
                    local compText = (Waypoints and Waypoints.GetCompletionText(i, canClickToComplete))
                        or (canClickToComplete and (QUEST_WATCH_QUEST_COMPLETE or "Click to complete quest"))
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
                                local cleanTxt = (obj.text or ""):gsub(" / ", "/")
                                table_insert(lines, {
                                    text      = cleanTxt,
                                    completed = (obj.finished == true),
                                })
                            end
                        end
                    elseif _G.GetNumQuestLeaderBoards and _G.GetQuestLogLeaderBoard then
                        local numLeaderBoards = _G.GetNumQuestLeaderBoards(i) or 0
                        for objIndex = 1, numLeaderBoards do
                            local desc, _, isFinished = _G.GetQuestLogLeaderBoard(objIndex, i)
                            if desc and desc ~= "" then
                                local cleanTxt = desc:gsub(" / ", "/")
                                table_insert(lines, {
                                    text      = cleanTxt,
                                    completed = (isFinished == true),
                                })
                            end
                        end
                    end

                    -- Waypoint direction text
                    local wpText = Waypoints and Waypoints.GetWaypointText(questID, (superTrackedQuestID == questID))
                    if wpText and wpText ~= "" then
                        table_insert(lines, {
                            text      = wpText,
                            completed = false,
                            color     = { 0.0, 1.0, 0.8, 1 },
                        })
                    end
                end
            end

            -- Usable Quest Item
            local itemInfo = Items and Items.GetQuestItemInfo(i, isComplete)

            -- Countdown Timer Bar (suppressed on Camelot)
            local timerBar = nil
            if TimerBars and TimerBars.CanShowTimerBar() then
                local total, elapsed = TimerBars.GetQuestTimeAllowed(questID)
                if total and total > 0 then
                    timerBar = {
                        timeTotal   = total,
                        timeElapsed = elapsed or 0,
                    }
                end
            end

            -- Group Finder (LFG) support through API
            local findGroupHelper = FindGroup or (sfui.tracker.helpers and sfui.tracker.helpers.findgroup)
            local canFindGroup = findGroupHelper and findGroupHelper.CanFindGroup and findGroupHelper.CanFindGroup(questID) or false

            -- SuperTracked state
            local isSuper = (superTrackedQuestID == questID)

            local titleColor = { 1, 1, 1, 1 }
            if canClickToComplete then
                titleColor = { 1.0, 0.0, 1.0, 1 } -- #FF00FF for click-to-complete quests
            elseif isComplete then
                titleColor = { 0.2, 1.0, 0.2, 1 }
            elseif isFailed then
                titleColor = { 1.0, 0.2, 0.2, 1 }
            elseif isRepeatable then
                titleColor = { 0.00, 1.00, 1.00, 1 } -- #00FFFF for repeatable / daily quests
            elseif isWarband then
                titleColor = { 0.75, 0.15, 0.15, 1 } -- Dark red
            end

            table_insert(section.blocks, {
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
                isRepeatable       = isRepeatable,
                isWarbandCompleted = isWarband,
                itemInfo           = itemInfo,
                timerBar           = timerBar,
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

    -- Camelot sorting: Current zone first, then alphabetical. Add capacity badge to current zone.
    if isCamelot then
        local numQ, maxQ, capBadge = GetQuestCapacityInfo()
        table_sort(sectionOrder, function(a, b)
            local aIsCur = a.title:find("%[Zone%]") ~= nil
            local bIsCur = b.title:find("%[Zone%]") ~= nil
            if aIsCur ~= bIsCur then
                return aIsCur
            end
            return a.title < b.title
        end)

        if #sectionOrder > 0 and capBadge then
            sectionOrder[1].capFormatted = capBadge
        end
    else
        local sectionRanks = {
            important  = 1,
            campaign   = 2,
            meta       = 3,
            activities = 4,
            zone       = 5,
        }
        table_sort(sectionOrder, function(a, b)
            local rA = sectionRanks[a.id] or 99
            local rB = sectionRanks[b.id] or 99
            return rA < rB
        end)
    end

    initialScanDone = true
    return sectionOrder
end

sfui.tracker.RegisterModule(QuestsModule)
return QuestsModule
