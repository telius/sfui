--[[
    SFUI Tracker Module: Classic Forever / Camelot Quests Engine
    frames/quests/modules/q_camelot.lua

    Pluggable quest log scanner for sfui.tracker on Warcraft Forever (Camelot) & Classic Era.
    - Grouped by Zone sections with Current Zone floating to top
    - Class Quests (spec color header, top rank)
    - Dungeon Quests (blue header, rank 2)
    - Profession Quests (orange header, rank 3)
    - Current Zone (cyan header `[Zone]`, capacity badge `[16/20]`)
    - Other Zones (alphabetical)
    - Level brackets [14], [18D] via Difficulty.FormatTitle
    - Suppressed timer bars
    - Progress-driven smart expansion with diminishing finished objectives
]]

local addonName, addon                        = ...
sfui                                          = sfui or {}
sfui.tracker                                  = sfui.tracker or {}
sfui.questlog                                 = sfui.questlog or {}

-- Guard: Classic / Camelot only (Exclude Retail)
local isRetail = sfui.isRetail
if isRetail == nil then
    local projectID = _G.WOW_PROJECT_ID or 1
    local _, _, _, tocVersionNum = _G.GetBuildInfo()
    tocVersionNum = tonumber(tocVersionNum) or 0
    local isForever = (tocVersionNum >= 16000 and tocVersionNum < 20000)
    isRetail = (projectID == 1) and not isForever
end

if isRetail then
    return
end

local _G                                      = _G
local C_QuestLog                              = _G.C_QuestLog
local C_TaskQuest                             = _G.C_TaskQuest
local C_SuperTrack                            = _G.C_SuperTrack
local C_ClassColor                            = _G.C_ClassColor
local C_TradeSkillUI                          = _G.C_TradeSkillUI
local Enum                                    = _G.Enum
local Constants                               = _G.Constants
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
local UnitClass                               = _G.UnitClass

local ipairs, pairs, type, tonumber, tostring = _G.ipairs, _G.pairs, _G.type, _G.tonumber, _G.tostring
local math_floor                              = math.floor
local table_insert, table_sort                = _G.table.insert, _G.table.sort
local string_format                           = string.format

local issecretvalue                           = (sfui.common and sfui.common.issecretvalue) or _G.issecretvalue or
function() return false end

-- ─────────────────────────────────────────────────────────
--  HELPERS & CACHE
-- ─────────────────────────────────────────────────────────
local Difficulty                              = sfui.tracker.helpers and sfui.tracker.helpers.difficulty
local Waypoints                               = sfui.tracker.helpers and sfui.tracker.helpers.waypoints
local Items                                   = sfui.tracker.helpers and sfui.tracker.helpers.items
local FindGroup                               = sfui.tracker.helpers and sfui.tracker.helpers.findgroup

local wipe                                    = _G.wipe or function(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

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

    local hasProgress = false
    local inlineTag = ""

    -- 1. Progress bar percent (if supported on modern quest formats)
    if GetQuestProgressBarPercent then
        local pct = GetQuestProgressBarPercent(questID)
        if pct and pct > 0 then
            hasProgress = true
            inlineTag = string_format(" |cffa0a0a0(%d%%)|r", math_floor(pct + 0.5))
            return hasProgress, inlineTag
        end
    end

    -- 2. Modern C_QuestLog objectives (if available on Camelot)
    if objs and #objs > 0 then
        local total = #objs
        local finished = 0
        local anyFulfilled = false
        local singleProg = nil

        for _, obj in ipairs(objs) do
            if obj.finished then
                finished = finished + 1
                anyFulfilled = true
            elseif obj.numFulfilled and obj.numFulfilled > 0 then
                anyFulfilled = true
                if total == 1 and obj.numRequired and obj.numRequired > 0 then
                    singleProg = string_format(" |cffa0a0a0(%d/%d)|r", obj.numFulfilled, obj.numRequired)
                end
            elseif obj.text then
                local cur, req = obj.text:match("(%d+)%s*/%s*(%d+)")
                if cur and tonumber(cur) and tonumber(cur) > 0 then
                    anyFulfilled = true
                    if total == 1 and req then
                        singleProg = string_format(" |cffa0a0a0(%s/%s)|r", cur, req)
                    end
                end
            end
        end

        hasProgress = anyFulfilled
        if total == 1 then
            if finished == 1 then
                inlineTag = " |cff33ff33(1/1)|r"
            elseif singleProg then
                inlineTag = singleProg
            else
                inlineTag = " |cffa0a0a0(0/1)|r"
            end
        else
            inlineTag = string_format(" |cffa0a0a0(%d/%d)|r", finished, total)
        end

        return hasProgress, inlineTag
    end

    -- 3. Classic / Classic Era leaderboards
    if questLogIndex and _G.GetNumQuestLeaderBoards and _G.GetQuestLogLeaderBoard then
        local num = _G.GetNumQuestLeaderBoards(questLogIndex) or 0
        if num > 0 then
            local finished = 0
            local anyFulfilled = false
            local singleProg = nil

            for objIndex = 1, num do
                local desc, _, isFinished = _G.GetQuestLogLeaderBoard(objIndex, questLogIndex)
                if isFinished then
                    finished = finished + 1
                    anyFulfilled = true
                elseif desc then
                    local cur, req = desc:match("(%d+)%s*/%s*(%d+)")
                    if cur and tonumber(cur) and tonumber(cur) > 0 then
                        anyFulfilled = true
                        if num == 1 and req then
                            singleProg = string_format(" |cffa0a0a0(%s/%s)|r", cur, req)
                        end
                    end
                end
            end

            hasProgress = anyFulfilled
            if num == 1 then
                if finished == 1 then
                    inlineTag = " |cff33ff33(1/1)|r"
                elseif singleProg then
                    inlineTag = singleProg
                else
                    inlineTag = " |cffa0a0a0(0/1)|r"
                end
            else
                inlineTag = string_format(" |cffa0a0a0(%d/%d)|r", finished, num)
            end

            return hasProgress, inlineTag
        end
    end

    return false, ""
end

-- ─────────────────────────────────────────────────────────
--  LEAN API-DRIVEN QUEST CLASSIFICATION
-- ─────────────────────────────────────────────────────────
local playerClass = nil
local function GetPlayerClass()
    if not playerClass and UnitClass then
        playerClass = UnitClass("player")
    end
    return playerClass
end


local function IsClassQuest(questID, questLogIndex, headerTitle)
    if type(questLogIndex) == "string" and not headerTitle then
        headerTitle = questLogIndex
        questLogIndex = nil
    end

    local pClass = GetPlayerClass()
    if not pClass then return false end

    if headerTitle and headerTitle:lower() == pClass:lower() then
        return true
    end

    if questID and C_QuestLog and C_QuestLog.GetHeaderIndexForQuest then
        local hIdx = C_QuestLog.GetHeaderIndexForQuest(questID)
        if hIdx then
            local hInfo = C_QuestLog.GetInfo(hIdx)
            if hInfo and hInfo.title and hInfo.title:lower() == pClass:lower() then
                return true
            end
        end
    end

    return false
end

local function IsDungeonQuest(questID, questLogIndex, headerTitle)
    if _G.QuestUtils_IsQuestDungeonQuest and questID and _G.QuestUtils_IsQuestDungeonQuest(questID) then
        return true
    end

    if C_QuestLog and C_QuestLog.GetQuestTagInfo and questID then
        local tagInfo = C_QuestLog.GetQuestTagInfo(questID)
        if tagInfo then
            local QT = Enum and Enum.QuestTag
            local QTT = Enum and Enum.QuestTagType
            if (QT and (tagInfo.tagID == QT.Dungeon or tagInfo.tagID == QT.Raid or tagInfo.tagID == QT.Raid10 or tagInfo.tagID == QT.Raid25))
               or (QTT and (tagInfo.worldQuestType == QTT.Dungeon or tagInfo.worldQuestType == QTT.Raid)) then
                return true
            end
        end
    end

    if questLogIndex and type(questLogIndex) == "number" and GetQuestLogTitle then
        local _, _, questTag = GetQuestLogTitle(questLogIndex)
        if questTag and (questTag == _G.DUNGEON or questTag == _G.RAID or questTag == "Dungeon" or questTag == "Raid") then
            return true
        end
    end

    return false
end

local professionHeaders = nil
local function IsProfessionQuest(questID, questLogIndex, headerTitle)
    if type(questLogIndex) == "string" and not headerTitle then
        headerTitle = questLogIndex
        questLogIndex = nil
    end

    -- 1. Native Quest Tag Info
    if C_QuestLog and C_QuestLog.GetQuestTagInfo and questID then
        local tagInfo = C_QuestLog.GetQuestTagInfo(questID)
        if tagInfo then
            if (tagInfo.tradeskillLineID and tagInfo.tradeskillLineID > 0)
               or (Enum and Enum.QuestTagType and tagInfo.worldQuestType == Enum.QuestTagType.Profession) then
                return true
            end
        end
    end

    -- 2. Header match against native profession names
    if headerTitle then
        if not professionHeaders then
            professionHeaders = {}
            if _G.WORLD_QUEST_ICONS_BY_PROFESSION and C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
                for lineID in pairs(_G.WORLD_QUEST_ICONS_BY_PROFESSION) do
                    local pInfo = C_TradeSkillUI.GetProfessionInfoBySkillLineID(lineID)
                    if pInfo and pInfo.professionName then
                        professionHeaders[pInfo.professionName:lower()] = true
                    end
                end
            elseif Enum and Enum.Profession and C_TradeSkillUI and C_TradeSkillUI.GetProfessionSkillLineID and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
                for _, profEnum in pairs(Enum.Profession) do
                    local lineID = C_TradeSkillUI.GetProfessionSkillLineID(profEnum)
                    if lineID and lineID > 0 then
                        local pInfo = C_TradeSkillUI.GetProfessionInfoBySkillLineID(lineID)
                        if pInfo and pInfo.professionName then
                            professionHeaders[pInfo.professionName:lower()] = true
                        end
                    end
                end
            end
        end

        local hLower = headerTitle:lower()
        if professionHeaders[hLower] then
            return true
        end

        -- Player's learned professions fallback (Classic / Era)
        if _G.GetProfessions and _G.GetProfessionInfo then
            for _, pIdx in ipairs({ _G.GetProfessions() }) do
                local name = _G.GetProfessionInfo(pIdx)
                if name and name:lower() == hLower then
                    professionHeaders[hLower] = true
                    return true
                end
            end
        end
    end

    return false
end

sfui.questlog.IsClassQuest = IsClassQuest
sfui.questlog.IsDungeonQuest = IsDungeonQuest
sfui.questlog.IsProfessionQuest = IsProfessionQuest

local function GetQLState()
    if not SfuiDB then SfuiDB = {} end
    if not SfuiDB.questlog then
        SfuiDB.questlog = {
            collapsed    = {},
            hiddenQuests = {},
            hidden       = false,
        }
    end
    if SfuiDB.questlog.expandedQuests then SfuiDB.questlog.expandedQuests = nil end
    if SfuiDB.questlog.manualExpandedQuests then SfuiDB.questlog.manualExpandedQuests = nil end
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

local pendingChangedQuests = {}

local function AutoTrackQuest(questID, questLogIndex)
    if not questID or questID <= 0 then return false end
    if InCombatLockdown and InCombatLockdown() then
        pendingChangedQuests[questID] = questLogIndex or true
        return false
    end
    if IsWorldQuest(questID) then return false end

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
                C_QuestLog.AddQuestWatch(questID)
            end
        end
    end

    return true
end

local function GetQuestCapacityInfo()
    local numEntries, numQuests = 0, 0
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        numEntries, numQuests = C_QuestLog.GetNumQuestLogEntries()
    elseif GetNumQuestLogEntries then
        numEntries, numQuests = GetNumQuestLogEntries()
    end
    numQuests = numQuests or 0

    local maxQuests = (Constants and Constants.QuestLogConsts and Constants.QuestLogConsts.MAXIMUM_NUM_QUESTS_LOG_CAN_ACCEPT)
        or (C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept())
        or (C_QuestLog and C_QuestLog.GetMaxNumQuests and C_QuestLog.GetMaxNumQuests())
        or 20

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
local function OnQuestBlockClick(block, mouseButton, questID, questLogIndex, questTitle, isAutoOffer, isCurrentlyExpanded,
                                 isClickToComplete)
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

    -- 4. Alt-Click: Share Quest with Party
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

    -- 5. Shift-Click: Untrack or Insert Link into Chat
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
        manualExpanded[questID] = nil
        if C_QuestLog and C_QuestLog.RemoveQuestWatch then
            C_QuestLog.RemoveQuestWatch(questID)
        elseif _G.RemoveQuestWatch and questLogIndex then
            _G.RemoveQuestWatch(questLogIndex)
        end
        if sfui.tracker and sfui.tracker.RequestRefresh then
            sfui.tracker.RequestRefresh(0.05)
        end
        return
    end

    -- 6. Right-Click: Toggle Criteria Expanded / Collapsed
    if mouseButton == "RightButton" then
        if InCombatLockdown and InCombatLockdown() then return end
        manualExpanded[questID] = not isCurrentlyExpanded
        if sfui.tracker and sfui.tracker.RequestRefresh then
            sfui.tracker.RequestRefresh(0.01)
        end
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
local CamelotQuestsModule = {
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
        "ZONE_CHANGED",
        "ZONE_CHANGED_INDOORS",
        "UNIT_QUEST_LOG_CHANGED",
        "PLAYER_REGEN_ENABLED",
        "PLAYER_TALENT_UPDATE",
        "CHARACTER_POINTS_CHANGED",
        "TRAIT_CONFIG_UPDATED",
        "ACTIVE_TALENT_GROUP_CHANGED",
    },
}

function CamelotQuestsModule:Init(engine)
    self.engine = engine
end

function CamelotQuestsModule:OnEvent(event, ...)
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
            if sfui.tracker and sfui.tracker.RequestRefresh then
                sfui.tracker.RequestRefresh(0.05)
            end
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

function CamelotQuestsModule:IsEnabled()
    return true
end

function CamelotQuestsModule:BuildBlocks(container)
    local state = GetQLState()

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

    -- Scan Quest Log Entries
    local currentHeaderTitle = "Miscellaneous"

    for i = 1, numEntries do
        local questID = nil
        local title = nil
        local isHeader = false
        local isCollapsed = false
        local isComplete = false
        local isAutoComplete = false
        local frequency = nil
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
        elseif questID and questID > 0 and not IsWorldQuest(questID) and IsQuestWatched(questID, i) then
            if C_QuestLog and C_QuestLog.IsComplete then
                isComplete = C_QuestLog.IsComplete(questID) or isComplete
            end
            local isFailed = (C_QuestLog and C_QuestLog.IsFailed and C_QuestLog.IsFailed(questID)) or false
            local canClickToComplete = isComplete and isAutoComplete

            -- Format Title: Difficulty Bracket [14], [18D]
            local entryStub = {
                level          = level,
                questID        = questID,
                questLogIndex  = i,
                suggestedGroup = suggestedGroup,
            }

            local displayTitle = title or "Quest"
            if Difficulty and Difficulty.FormatTitle then
                displayTitle = Difficulty.FormatTitle(entryStub, displayTitle)
            end

            -- Determine Section ID
            local secID, secTitle, secColor
            local isZoneSec = false
            local isCurZone = false

            if IsClassQuest(questID, i, currentHeaderTitle) then
                secID = "class"
                secTitle = "class"
                secColor = sfui.common.get_class_or_spec_color()
            elseif IsDungeonQuest(questID, i, currentHeaderTitle) then
                secID = "dungeons"
                secTitle = "dungeons"
                secColor = { 0.25, 0.65, 1.00 }
            elseif IsProfessionQuest(questID, i, currentHeaderTitle) then
                secID = "professions"
                secTitle = "professions"
                secColor = { 0.90, 0.65, 0.25 }
            else
                local zName = currentHeaderTitle or "Miscellaneous"
                local isCur = (currentZoneName ~= "" and zName:lower() == currentZoneName:lower())
                secID       = "zone_" .. zName
                secTitle    = zName:lower() .. (isCur and " [Zone]" or "")
                secColor    = isCur and { 0.00, 1.00, 1.00 } or { 1.00, 1.00, 1.00 }
                isZoneSec   = true
                isCurZone   = isCur
            end

            local section = GetOrCreateSection(secID, secTitle, secColor)
            if isZoneSec then
                section.isZoneSection = true
                if isCurZone then
                    section.isCurrentZone = true
                end
            end

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

            -- Solution 1: Inline progress on collapsed titles
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
                                -- Solution 2: Diminishing objectives (hide completed sub-objectives)
                                if not obj.finished then
                                    local cleanTxt = (obj.text or ""):gsub(" / ", "/")
                                    table_insert(lines, {
                                        text      = cleanTxt,
                                        completed = false,
                                    })
                                end
                            end
                        end
                    elseif _G.GetNumQuestLeaderBoards and _G.GetQuestLogLeaderBoard then
                        local numLeaderBoards = _G.GetNumQuestLeaderBoards(i) or 0
                        for objIndex = 1, numLeaderBoards do
                            local desc, _, isFinished = _G.GetQuestLogLeaderBoard(objIndex, i)
                            if desc and desc ~= "" then
                                -- Solution 2: Diminishing objectives (hide completed sub-objectives)
                                if not isFinished then
                                    local cleanTxt = desc:gsub(" / ", "/")
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

            -- Group Finder (LFG) support through API (disabled on Classic/Forever)
            local findGroupHelper = FindGroup or (sfui.tracker.helpers and sfui.tracker.helpers.findgroup)
            local canFindGroup = findGroupHelper and findGroupHelper.CanFindGroup and
            findGroupHelper.CanFindGroup(questID) or false

            -- SuperTracked state
            local isSuper = (superTrackedQuestID == questID)

            local titleColor = { 1, 1, 1, 1 }
            if canClickToComplete then
                titleColor = { 1.0, 0.0, 1.0, 1 } -- #FF00FF
            elseif isComplete then
                titleColor = { 0.2, 1.0, 0.2, 1 }
            elseif isFailed then
                titleColor = { 1.0, 0.2, 0.2, 1 }
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
                isRepeatable       = false,
                isWarbandCompleted = false,
                itemInfo           = itemInfo,
                timerBar           = nil, -- Suppressed on Camelot
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

    -- Camelot sorting: Class -> Dungeons -> Professions -> Current Zone -> Other Zones (alphabetical)
    local numQ, maxQ, capBadge = GetQuestCapacityInfo()
    local sectionRanks = {
        class       = 1,
        dungeons    = 2,
        professions = 3,
    }
    table_sort(sectionOrder, function(a, b)
        local rA = sectionRanks[a.id] or 99
        local rB = sectionRanks[b.id] or 99
        if rA ~= rB then
            return rA < rB
        end
        local aIsCur = a.isCurrentZone or (a.title and a.title:find("%[Zone%]") ~= nil)
        local bIsCur = b.isCurrentZone or (b.title and b.title:find("%[Zone%]") ~= nil)
        if aIsCur ~= bIsCur then
            return aIsCur
        end
        return (a.title or "") < (b.title or "")
    end)

    if #sectionOrder > 0 and capBadge then
        local targetSec = nil
        for _, sec in ipairs(sectionOrder) do
            if sec.isCurrentZone then
                targetSec = sec
                break
            end
        end
        targetSec = targetSec or sectionOrder[1]
        if targetSec then
            targetSec.capFormatted = capBadge
        end
    end

    return sectionOrder
end

sfui.tracker.RegisterModule(CamelotQuestsModule)
return CamelotQuestsModule
