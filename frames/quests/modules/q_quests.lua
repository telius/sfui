--[[
    SFUI Tracker Module: Retail Quests Engine
    frames/quests/modules/q_quests.lua

    Pluggable quest log scanner for sfui.tracker on World of Warcraft (Retail).
    Grouped by Classification:
      - Important (orange/red)
      - Campaign (gold)
      - Meta (cyan)
      - Activities (cyan)
      - Quests / Zone (white)
    Supports Warband completion badges, auto-quest popups, progress bar objectives,
    and timer countdown bars.
]]

local addonName, addon = ...
local sfui             = _G.sfui or {}
sfui.tracker           = sfui.tracker or {}
sfui.questlog          = sfui.questlog or {}

-- Guard: Retail only
if not sfui.isRetail then
    return
end

local _G                                      = _G
local C_QuestLog                              = _G.C_QuestLog
local C_TaskQuest                             = _G.C_TaskQuest
local C_SuperTrack                            = _G.C_SuperTrack
local C_PlayerInfo                            = _G.C_PlayerInfo
local Enum                                    = _G.Enum
local Constants                               = _G.Constants
local GetNumAutoQuestPopUps                   = _G.GetNumAutoQuestPopUps
local GetAutoQuestPopUp                       = _G.GetAutoQuestPopUp
local GetQuestLogTitle                        = _G.GetQuestLogTitle
local GetNumQuestLogEntries                   = _G.GetNumQuestLogEntries
local GetQuestProgressBarPercent              = _G.GetQuestProgressBarPercent
local GetRealZoneText                         = _G.GetRealZoneText
local GetZoneText                             = _G.GetZoneText
local IsInGroup                               = _G.IsInGroup
local InCombatLockdown                        = _G.InCombatLockdown
local IsShiftKeyDown                          = _G.IsShiftKeyDown
local IsControlKeyDown                        = _G.IsControlKeyDown
local IsAltKeyDown                            = _G.IsAltKeyDown
local ChatEdit_GetActiveWindow                = _G.ChatEdit_GetActiveWindow
local ChatEdit_InsertLink                     = _G.ChatEdit_InsertLink
local ChatFrameUtil                           = _G.ChatFrameUtil
local QuestMapFrame_OpenToQuestDetails        = _G.QuestMapFrame_OpenToQuestDetails

local ipairs, pairs, type, tonumber, tostring = _G.ipairs, _G.pairs, _G.type, _G.tonumber, _G.tostring
local math_floor                              = math.floor
local table_insert, table_sort                = _G.table.insert, _G.table.sort
local string_format                           = string.format

local issecretvalue                           = sfui.common.issecretvalue

-- ─────────────────────────────────────────────────────────
--  HELPERS & CACHE
-- ─────────────────────────────────────────────────────────
local Difficulty                              = sfui.tracker.helpers.difficulty
local Waypoints                               = sfui.tracker.helpers.waypoints
local TimerBars                               = sfui.tracker.helpers.timerbars
local Items                                   = sfui.tracker.helpers.items
local FindGroup                               = sfui.tracker.helpers.findgroup
local QuestCommon                             = sfui.tracker.helpers.quest

local wipe                                    = _G.wipe or function(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

-- Fallback stubs for legacy references
sfui.questlog.IsClassQuest                    = sfui.questlog.IsClassQuest or function() return false end
sfui.questlog.IsDungeonQuest                  = sfui.questlog.IsDungeonQuest or function() return false end
sfui.questlog.IsProfessionQuest               = sfui.questlog.IsProfessionQuest or function() return false end

-- ─────────────────────────────────────────────────────────
--  EXPANSION & WATCH CACHE
-- ─────────────────────────────────────────────────────────
local recentlyWatched                         = {}
local manualExpanded                          = {}

local function GetQuestProgressDetails(questID, questLogIndex, isComplete, objs, canClickToComplete)
    if isComplete then
        local tag = canClickToComplete and " |cffff00ff(Complete)|r" or " |cff33ff33(Complete)|r"
        return true, tag
    end

    -- 1. Progress bar percent (modern quests / bonus objectives)
    if GetQuestProgressBarPercent then
        local pct = GetQuestProgressBarPercent(questID)
        if pct and pct > 0 then
            return true, string_format(" |cffa0a0a0(%d%%)|r", math_floor(pct + 0.5))
        end
    end

    -- 2. Modern C_QuestLog objectives
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

    return false, ""
end

local function GetQLState()
    return sfui.questlog.GetState()
end

local function IsQuestWatched(questID, questLogIndex)
    return QuestCommon.IsQuestWatched(questID, questLogIndex, recentlyWatched)
end

local IsWorldQuest = QuestCommon.IsWorldQuest

--- Automatically track a quest when objectives update or progress occurs
local pendingChangedQuests = {}

--- @param questID number Quest ID to track
--- @param questLogIndex number|nil Optional quest log index for classic clients
local function AutoTrackQuest(questID, questLogIndex)
    return QuestCommon.AutoTrackQuest(questID, questLogIndex, recentlyWatched, pendingChangedQuests)
end

local seasonalWeeklySet = nil
local function BuildSeasonalWeeklySet()
    seasonalWeeklySet = {}
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

local TryInsertQuestLink = QuestCommon.TryInsertQuestLink

-- ─────────────────────────────────────────────────────────
--  QUEST CLICK HANDLER
-- ─────────────────────────────────────────────────────────
local function OnQuestBlockClick(block, mouseButton, questID, questLogIndex, questTitle, isAutoOffer, isCurrentlyExpanded,
                                 isClickToComplete)
    if not questID then return end

    -- 0. Middle-Click or Shift-Right-Click: Open in Dungeon Journal for dungeon quests
    if mouseButton == "MiddleButton" or (mouseButton == "RightButton" and IsShiftKeyDown and IsShiftKeyDown()) then
        if sfui.dungeonjournal and sfui.dungeonjournal.SelectQuest then
            local isDJ = (sfui.dj_camelot and sfui.dj_camelot.IsDungeonQuest and sfui.dj_camelot.IsDungeonQuest(questID))
                or (sfui.questlog and sfui.questlog.IsDungeonQuest and sfui.questlog.IsDungeonQuest(questID, questLogIndex))
            if isDJ then
                local ok = sfui.dungeonjournal.SelectQuest(nil, questID)
                if ok then return end
            end
        end
    end

    -- 1. Auto-Quest Offer Click
    if isAutoOffer then
        if IsShiftKeyDown and IsShiftKeyDown() then
            if _G.RemoveAutoQuestPopUp then
                _G.RemoveAutoQuestPopUp(questID)
                sfui.tracker.RequestRefresh(0.05)
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
            _G.RemoveAutoQuestPopUp(questID)
        end
        if _G.ShowQuestComplete then
            _G.ShowQuestComplete(questID)
            return
        end
    end

    -- 3. Ctrl-Click: Abandon Quest
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

            local title = questTitle or (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)) or
                "Quest"
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
        local inGroup = (IsInGroup and IsInGroup())
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

        -- Untrack quest
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
        "UNIT_QUEST_LOG_CHANGED",
        "PLAYER_REGEN_ENABLED",
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
    elseif event == "QUEST_TURNED_IN" or event == "QUEST_REMOVED" then
        if questID and questID > 0 then
            recentlyWatched[questID] = nil
            manualExpanded[questID] = nil
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
    local state = GetQLState()

    local superTrackedQuestID = nil
    if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
        superTrackedQuestID = C_SuperTrack.GetSuperTrackedQuestID()
    end

    local numEntries = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries())
        or (GetNumQuestLogEntries and GetNumQuestLogEntries())
        or 0

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
    if GetNumAutoQuestPopUps and GetAutoQuestPopUp then
        local numPopups = GetNumAutoQuestPopUps() or 0
        for i = 1, numPopups do
            local qID, popUpType = GetAutoQuestPopUp(i)
            if qID and qID > 0 then
                local popTitle = (C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(qID)) or
                    "Quest"
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

            -- Format Title: Warband Tag
            local isWarband = false
            if C_QuestLog and C_QuestLog.IsQuestFlaggedCompletedOnAccount then
                isWarband = (C_QuestLog.IsQuestFlaggedCompletedOnAccount(questID) == true)
            end

            local displayTitle = title or "Quest"
            local isWeekly = IsWeeklyQuest(questID, frequency)
            local isRepeatable = isWeekly or IsRepeatableQuest(questID, frequency)

            -- Determine Section ID (Retail Classification)
            local secID, secTitle, secColor
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

            local section = GetOrCreateSection(secID, secTitle, secColor)
            local objs = C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(questID)

            -- If quest is complete, reset manual expansion override so it defaults to collapsed
            if isComplete and manualExpanded[questID] ~= nil then
                manualExpanded[questID] = nil
            end

            -- Smart progress-based expansion & inline tag
            local hasProgress, inlineTag = GetQuestProgressDetails(questID, i, isComplete, objs, canClickToComplete)
            local defaultExpanded = (hasProgress and not isComplete)
            local isExpanded
            if manualExpanded[questID] ~= nil then
                isExpanded = (manualExpanded[questID] == true)
            else
                isExpanded = defaultExpanded
            end

            -- Inline progress on collapsed titles
            if not isExpanded and inlineTag ~= "" then
                displayTitle = displayTitle .. inlineTag
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
                                -- Diminishing objectives (hide completed sub-objectives)
                                if not obj.finished then
                                    local cleanTxt = (obj.text or ""):gsub(" / ", "/")
                                    table_insert(lines, {
                                        text      = cleanTxt,
                                        completed = false,
                                    })
                                end
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

                    -- If all individual objectives are finished but quest not yet flagged complete
                    if #lines == 0 and not progressBar then
                        local compText = (Waypoints and Waypoints.GetCompletionText(i, canClickToComplete))
                            or (canClickToComplete and (QUEST_WATCH_QUEST_COMPLETE or "Click to complete quest"))
                            or "Ready for turn-in"
                        table_insert(lines, {
                            text      = compText,
                            completed = true,
                            color     = canClickToComplete and { 1.0, 0.0, 1.0, 1 } or { 0.2, 1.0, 0.2, 1 },
                        })
                    end
                end
            end

            -- Usable Quest Item
            local itemInfo = Items and Items.GetQuestItemInfo(i, isComplete)

            -- Countdown Timer Bar
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
            local canFindGroup = FindGroup and FindGroup.CanFindGroup and
                FindGroup.CanFindGroup(questID) or false

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

    -- Retail sorting: Important -> Campaign -> Meta -> Activities -> Zone
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

    return sectionOrder
end

sfui.tracker.RegisterModule(QuestsModule)
return QuestsModule
