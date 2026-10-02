--[[
    SFUI Tracker Module: World Quests & Bonus Objectives
    frames/quests/modules/worldquests.lua

    Pluggable tracker module for active and tracked World Quests & Bonus Objectives.
]]

local addonName, addon = ...
local sfui = _G.sfui or {}
sfui.tracker = sfui.tracker or {}
sfui.questlog = sfui.questlog or {}

local _G = _G
local C_QuestLog = _G.C_QuestLog
local C_TaskQuest = _G.C_TaskQuest
local C_SuperTrack = _G.C_SuperTrack
local GetNumQuestLogEntries = _G.GetNumQuestLogEntries
local GetQuestProgressBarPercent = _G.GetQuestProgressBarPercent
local IsShiftKeyDown = _G.IsShiftKeyDown
local QuestMapFrame_OpenToQuestDetails = _G.QuestMapFrame_OpenToQuestDetails
local ChatEdit_GetActiveWindow = _G.ChatEdit_GetActiveWindow
local ChatEdit_InsertLink = _G.ChatEdit_InsertLink
local ChatFrameUtil = _G.ChatFrameUtil

local ipairs, pairs, type, tonumber, tostring = _G.ipairs, _G.pairs, _G.type, _G.tonumber, _G.tostring
local math_floor = math.floor
local table_insert = _G.table.insert
local string_format = string.format

local issecretvalue = sfui.common.issecretvalue

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

local function FormatTimeLeft(minutes)
    if not minutes or minutes <= 0 then return nil end
    if minutes >= 1440 then
        return string_format("%dd", math_floor(minutes / 1440))
    elseif minutes >= 60 then
        return string_format("%dh", math_floor(minutes / 60))
    else
        return string_format("%dm", minutes)
    end
end

local lastWQProgress = {}
local initialWQScanDone = false

local function TryInsertQuestLink(questID, questLogIndex, questTitle)
    if not questID then return false end

    -- 1. Try Blizzard modern API
    if ChatFrameUtil and ChatFrameUtil.TryInsertQuestLinkForQuestID then
        if ChatFrameUtil.TryInsertQuestLinkForQuestID(questID) then
            return true
        end
    end

    -- 2. Detect if an active chat edit box or input box is open
    local activeChat = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow())
        or (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
        or _G.ACTIVE_CHAT_EDIT_BOX
    local isChatOpen = (activeChat and (activeChat:IsShown() or activeChat:IsVisible()))
        or (_G.MacroFrameText and _G.MacroFrameText:IsShown())
        or (_G.CommunitiesFrame and _G.CommunitiesFrame.ChatEditBox and _G.CommunitiesFrame.ChatEditBox:IsShown())

    if not isChatOpen then
        return false
    end

    -- 3. Resolve quest link
    local link = (_G.GetQuestLink and _G.GetQuestLink(questID))
        or (questLogIndex and _G.GetQuestLink and _G.GetQuestLink(questLogIndex))

    if not link then
        local title = questTitle or (C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID))
        if title and title ~= "" then
            local level = (C_QuestLog and C_QuestLog.GetQuestDifficultyLevel and C_QuestLog.GetQuestDifficultyLevel(questID)) or 0
            link = string_format("|cffffff00|Hquest:%d:%d|h[%s]|h|r", questID, level, title)
        end
    end

    if not link then
        return false
    end

    -- 4. Insert link into active chat / edit box
    if ChatFrameUtil and ChatFrameUtil.InsertLink and ChatFrameUtil.InsertLink(link) then
        return true
    end
    if ChatEdit_InsertLink and ChatEdit_InsertLink(link) then
        return true
    end
    if activeChat and activeChat.Insert then
        activeChat:Insert(link)
        if activeChat.SetFocus then
            activeChat:SetFocus()
        end
        return true
    end

    return false
end

local WorldQuestsModule = {
    id       = "worldquests",
    priority = 30,
    events   = {
        "QUEST_LOG_UPDATE",
        "QUEST_WATCH_LIST_CHANGED",
        "TASK_PROGRESS_UPDATE",
        "SUPER_TRACKING_CHANGED",
    },
}

function WorldQuestsModule:Init(engine)
    self.engine = engine
end

function WorldQuestsModule:IsEnabled()
    return (C_TaskQuest ~= nil)
end

function WorldQuestsModule:BuildBlocks(container)
    local state = GetQLState()
    local expandedQuests = state.expandedQuests or {}
    local activeWQs = {}
    local numEntries = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries())
        or (GetNumQuestLogEntries and GetNumQuestLogEntries())
        or 0

    local superTrackedQuestID = nil
    if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
        superTrackedQuestID = C_SuperTrack.GetSuperTrackedQuestID()
    end

    local blocks = {}

    for i = 1, numEntries do
        local questID = nil
        local title = nil
        local isTask = false

        if C_QuestLog and C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader then
                questID = info.questID
                title = info.title
                isTask = info.isTask or info.isBounty
            end
        end

        local isWQ = false
        if questID and questID > 0 then
            if C_QuestLog and C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(questID) then
                isWQ = true
            elseif isTask then
                isWQ = true
            end
        end

        local isWatched = false
        if isWQ and C_QuestLog and C_QuestLog.GetQuestWatchType then
            isWatched = (C_QuestLog.GetQuestWatchType(questID) ~= nil)
        end
        if not isWatched and isWQ and C_QuestLog and C_QuestLog.IsQuestWatched then
            isWatched = C_QuestLog.IsQuestWatched(questID)
        end

        if isWQ and isWatched then
            activeWQs[questID] = true
            local displayTitle = title or "World Quest"

            -- Time left indicator
            local timeLeftMin = C_TaskQuest and C_TaskQuest.GetQuestTimeLeftMinutes and C_TaskQuest.GetQuestTimeLeftMinutes(questID)
            local timeStr = FormatTimeLeft(timeLeftMin)
            if timeStr then
                displayTitle = displayTitle .. " |cffbbbbbb(" .. timeStr .. ")|r"
            end

            local expandKey = "wq_" .. tostring(questID)
            local isExpanded = (expandedQuests[expandKey] ~= false)

            -- Objectives & Progress Bar
            local lines = {}
            local progressBar = nil

            local pct = 0
            if GetQuestProgressBarPercent then
                pct = GetQuestProgressBarPercent(questID) or 0
            elseif C_TaskQuest and C_TaskQuest.GetQuestProgressBarInfo then
                pct = C_TaskQuest.GetQuestProgressBarInfo(questID) or 0
            end

            if pct and pct > 0 then
                progressBar = {
                    min   = 0,
                    max   = 100,
                    value = pct,
                    text  = string_format("%d%%", math_floor(pct + 0.5)),
                }
            end

            local objs = C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(questID)
            if isExpanded and objs and #objs > 0 then
                for _, obj in ipairs(objs) do
                    local isBar = (obj.type == "progressbar" or obj.type == 8)
                    if not isBar and obj.text and obj.text ~= "" and not issecretvalue(obj.text) then
                        local cleanTxt = obj.text:gsub(" / ", "/")
                        table_insert(lines, {
                            text      = cleanTxt,
                            completed = (obj.finished == true),
                        })
                    end
                end
            end

            local isSuper = (superTrackedQuestID == questID)

            -- Waypoint direction text
            local waypointsHelper = sfui.tracker.helpers.waypoints
            local wpText = waypointsHelper and waypointsHelper.GetWaypointText and waypointsHelper.GetWaypointText(questID, isSuper)
            if isExpanded and wpText and wpText ~= "" then
                table_insert(lines, {
                    text      = wpText,
                    completed = false,
                    color     = { 0.0, 1.0, 0.8, 1 },
                })
            end

            -- Focus World Quest when its progress changes
            local currentSig = tostring(pct or 0)
            if objs and #objs > 0 then
                for _, obj in ipairs(objs) do
                    currentSig = currentSig .. ";" .. (obj.finished and "1" or "0") .. ":" .. (obj.text or "")
                end
            end
            local prevSig = lastWQProgress[questID]
            if initialWQScanDone and prevSig and prevSig ~= currentSig then
                if not InCombatLockdown or not InCombatLockdown() then
                    if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
                        C_SuperTrack.SetSuperTrackedQuestID(questID)
                        superTrackedQuestID = questID
                    end
                end
            end
            lastWQProgress[questID] = currentSig

            local findGroupHelper = sfui.tracker.helpers.findgroup
            local canFindGroup = findGroupHelper and findGroupHelper.CanFindGroup and findGroupHelper.CanFindGroup(questID) or false

            table_insert(blocks, {
                title          = displayTitle,
                rawTitle       = title,
                titleColor     = { 0.95, 0.65, 0.95, 1 },
                isSuperTracked = isSuper,
                questID        = questID,
                isWorldQuest   = true,
                timeLeftText   = timeStr,
                canFindGroup   = canFindGroup,
                isExpanded     = isExpanded,
                lines          = lines,
                progressBar    = progressBar,
                OnClick        = function(block, btn)
                    -- Shift-Click: Untrack or Insert Link into Chat
                    if IsShiftKeyDown and IsShiftKeyDown() then
                        if InCombatLockdown and InCombatLockdown() then return end
                        if TryInsertQuestLink(questID, nil, title) then
                            return
                        end
                        if C_QuestLog and C_QuestLog.RemoveQuestWatch then
                            C_QuestLog.RemoveQuestWatch(questID)
                        end
                        sfui.tracker.RequestRefresh(0.05)
                        return
                    end

                    -- Right-Click: Toggle Objectives Collapse/Expand
                    if btn == "RightButton" then
                        local st = GetQLState()
                        st.expandedQuests = st.expandedQuests or {}
                        st.expandedQuests[expandKey] = not isExpanded
                        sfui.tracker.RequestRefresh(0.01)
                        return
                    end

                    -- Left-Click: Open details or map
                    if InCombatLockdown and InCombatLockdown() then return end
                    if QuestMapFrame_OpenToQuestDetails then
                        QuestMapFrame_OpenToQuestDetails(questID)
                    elseif _G.ToggleWorldMap then
                        _G.ToggleWorldMap()
                    end

                    if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
                        C_SuperTrack.SetSuperTrackedQuestID(questID)
                    end
                end,
            })
        end
    end

    -- Clean up untracked or expired world quests from snapshot cache
    for qID in pairs(lastWQProgress) do
        if not activeWQs[qID] then
            lastWQProgress[qID] = nil
        end
    end

    initialWQScanDone = true

    if #blocks > 0 then
        return {
            {
                id     = "worldquests",
                title  = "world quests",
                color  = { 0.20, 0.85, 0.95 },
                blocks = blocks,
            }
        }
    end

    return nil
end

sfui.tracker.RegisterModule(WorldQuestsModule)
return WorldQuestsModule
