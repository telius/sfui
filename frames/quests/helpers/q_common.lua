local addonName, addon = ...
local sfui = _G.sfui or {}

-- ─────────────────────────────────────────────────────────
--  shared quest helpers (q_quests, q_camelot, q_camelot_class, q_worldquests)
--  each module keeps its own recentlyWatched / pending tables and passes them in.
-- ─────────────────────────────────────────────────────────
sfui.tracker = sfui.tracker or {}
sfui.tracker.helpers = sfui.tracker.helpers or {}

local QuestCommon = {}
sfui.tracker.helpers.quest = QuestCommon

local _G = _G
local type = type
local math_floor = math.floor
local string_format = string.format
local C_QuestLog = _G.C_QuestLog
local InCombatLockdown = _G.InCombatLockdown
local ChatFrameUtil = _G.ChatFrameUtil

--- @param questID number
--- @param questLogIndex number|nil classic quest log index
--- @param recentlyWatched table|nil module cache of watches added this session
function QuestCommon.IsQuestWatched(questID, questLogIndex, recentlyWatched)
    if not questID or questID <= 0 then return false end
    if recentlyWatched and recentlyWatched[questID] then return true end
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

function QuestCommon.IsWorldQuest(questID)
    if not questID or questID <= 0 then return false end
    if C_QuestLog and C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(questID) then
        return true
    end
    if _G.QuestUtils_IsQuestWorldQuest and _G.QuestUtils_IsQuestWorldQuest(questID) then
        return true
    end
    return false
end

--- automatically track a quest when objectives update or progress occurs.
--- @param recentlyWatched table module watch cache (written on success)
--- @param pending table module table of quests deferred until combat ends
--- @return boolean watched true when the quest is (now) watched
function QuestCommon.AutoTrackQuest(questID, questLogIndex, recentlyWatched, pending)
    if not questID or questID <= 0 then return false end
    if InCombatLockdown and InCombatLockdown() then
        if pending then pending[questID] = questLogIndex or true end
        return false
    end
    if QuestCommon.IsWorldQuest(questID) then return false end

    -- avoid tracking task quests or bounties as persistent watches
    if C_QuestLog and ((C_QuestLog.IsQuestBounty and C_QuestLog.IsQuestBounty(questID))
            or (C_QuestLog.IsQuestTask and C_QuestLog.IsQuestTask(questID))) then
        return false
    end

    if QuestCommon.IsQuestWatched(questID, questLogIndex, recentlyWatched) then
        return true
    end

    local maxWatches = (_G.Constants and _G.Constants.QuestWatchConsts and _G.Constants.QuestWatchConsts.MAX_QUEST_WATCHES)
        or _G.MAX_WATCHABLE_QUESTS
        or 25

    local canWatch = true
    if C_QuestLog and C_QuestLog.GetNumQuestWatches then
        canWatch = (C_QuestLog.GetNumQuestWatches() < maxWatches)
    elseif _G.GetNumQuestWatches then
        canWatch = (_G.GetNumQuestWatches() < maxWatches)
    end
    if not canWatch then return false end

    if C_QuestLog and C_QuestLog.AddQuestWatch then
        C_QuestLog.AddQuestWatch(questID)
    elseif _G.AddQuestWatch and questLogIndex then
        _G.AddQuestWatch(questLogIndex)
    end
    if recentlyWatched then recentlyWatched[questID] = true end
    return true
end

--- inserts a quest link into the active chat / macro / communities edit box.
--- @return boolean inserted
function QuestCommon.TryInsertQuestLink(questID, questLogIndex, questTitle)
    if not questID then return false end

    -- 1. blizzard modern api
    if ChatFrameUtil and ChatFrameUtil.TryInsertQuestLinkForQuestID then
        if ChatFrameUtil.TryInsertQuestLinkForQuestID(questID) then
            return true
        end
    end

    -- 2. detect an open chat / input box
    local activeChat = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow())
        or (_G.ChatEdit_GetActiveWindow and _G.ChatEdit_GetActiveWindow())
        or _G.ACTIVE_CHAT_EDIT_BOX
    local isChatOpen = (activeChat and (activeChat:IsShown() or activeChat:IsVisible()))
        or (_G.MacroFrameText and _G.MacroFrameText:IsShown())
        or (_G.CommunitiesFrame and _G.CommunitiesFrame.ChatEditBox and _G.CommunitiesFrame.ChatEditBox:IsShown())

    if not isChatOpen then
        return false
    end

    -- 3. resolve the quest link
    local link = (_G.GetQuestLink and _G.GetQuestLink(questID))
        or (questLogIndex and _G.GetQuestLink and _G.GetQuestLink(questLogIndex))
        or (C_QuestLog and C_QuestLog.GetQuestLink and C_QuestLog.GetQuestLink(questID))

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

    -- 4. insert into the active edit box
    if ChatFrameUtil and ChatFrameUtil.InsertLink and ChatFrameUtil.InsertLink(link) then
        return true
    end
    if _G.ChatEdit_InsertLink and _G.ChatEdit_InsertLink(link) then
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

--- formats a quest timer with urgency colouring.
--- @return string|nil coloured, string|nil plain
function QuestCommon.FormatQuestTimer(seconds)
    if not seconds or seconds <= 0 then return nil, nil end
    local timeStr
    local common = sfui.common
    if common and common.format_timer_clock then
        timeStr = common.format_timer_clock(seconds)
    else
        local m = math_floor(seconds / 60)
        local s = math_floor(seconds % 60)
        timeStr = string_format("%d:%02d", m, s)
    end
    if not timeStr then return nil, nil end

    local colorCode
    if seconds <= 60 then
        colorCode = "|cffff3333" -- urgent red (< 1 min)
    elseif seconds <= 180 then
        colorCode = "|cffffaa00" -- warning amber (< 3 min)
    else
        colorCode = "|cffffffff" -- clean white
    end

    return colorCode .. timeStr .. "|r", timeStr
end

-- localized player class name (quest log headers use localized class names)
local playerClassLocalized = nil
function QuestCommon.GetPlayerClassLocalized()
    if not playerClassLocalized and _G.UnitClass then
        playerClassLocalized = _G.UnitClass("player")
    end
    return playerClassLocalized
end

--- true when the quest sits under the player's class header in the quest log.
--- accepts (questID, headerTitle) as a legacy call form.
function QuestCommon.IsClassQuest(questID, questLogIndex, headerTitle)
    if type(questLogIndex) == "string" and not headerTitle then
        headerTitle = questLogIndex
        questLogIndex = nil
    end

    local pClass = QuestCommon.GetPlayerClassLocalized()
    if not pClass then return false end
    local pClassLower = pClass:lower()

    if headerTitle and headerTitle:lower() == pClassLower then
        return true
    end

    if questID and C_QuestLog and C_QuestLog.GetHeaderIndexForQuest then
        local hIdx = C_QuestLog.GetHeaderIndexForQuest(questID)
        if hIdx then
            local hInfo = C_QuestLog.GetInfo(hIdx)
            if hInfo and hInfo.title and hInfo.title:lower() == pClassLower then
                return true
            end
        end
    end

    return false
end
