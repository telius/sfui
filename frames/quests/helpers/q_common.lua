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
local ipairs = ipairs
local math_floor = math.floor
local string_format = string.format
local C_QuestLog = _G.C_QuestLog
local InCombatLockdown = _G.InCombatLockdown
local ChatFrameUtil = _G.ChatFrameUtil
local GetQuestProgressBarPercent = _G.GetQuestProgressBarPercent

--- formats progress indicators, inline objective counts, and completion tags for a quest.
--- @param questID number
--- @param questLogIndex number|nil optional classic quest log index
--- @param isComplete boolean
--- @param objs table|nil list of objective tables
--- @param canClickToComplete boolean|nil
--- @return boolean hasProgress, string tag
function QuestCommon.GetQuestProgressDetails(questID, questLogIndex, isComplete, objs, canClickToComplete)
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

    -- 3. Classic / Classic Era leaderboards
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

local sharedRecentlyWatched = {}
QuestCommon.recentlyWatched = sharedRecentlyWatched

--- @param questID number
--- @param questLogIndex number|nil classic quest log index
--- @param recentlyWatched table|nil module cache of watches added this session
function QuestCommon.IsQuestWatched(questID, questLogIndex, recentlyWatched)
    if not questID or questID <= 0 then return false end
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
    if (recentlyWatched and recentlyWatched[questID]) or sharedRecentlyWatched[questID] then
        return true
    end
    return false
end

function QuestCommon.UntrackQuest(questID, questLogIndex, recentlyWatched, manualExpanded)
    if not questID or questID <= 0 then return end
    sharedRecentlyWatched[questID] = nil
    if recentlyWatched then recentlyWatched[questID] = nil end
    if manualExpanded then manualExpanded[questID] = nil end

    if C_QuestLog and C_QuestLog.RemoveQuestWatch then
        C_QuestLog.RemoveQuestWatch(questID)
    end
    if C_QuestLog and C_QuestLog.RemoveWorldQuestWatch then
        C_QuestLog.RemoveWorldQuestWatch(questID)
    end
    if _G.RemoveQuestWatch then
        local idx = questLogIndex
        if not idx or idx <= 0 then
            if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
                idx = C_QuestLog.GetLogIndexForQuestID(questID)
            elseif _G.GetQuestLogIndexByID then
                idx = _G.GetQuestLogIndexByID(questID)
            end
        end
        if idx and idx > 0 then
            _G.RemoveQuestWatch(idx)
        end
    end
    if _G.C_SuperTrack and _G.C_SuperTrack.GetSuperTrackedQuestID and _G.C_SuperTrack.GetSuperTrackedQuestID() == questID then
        if sfui.map and sfui.map.SetSuperTrackedQuestID then
            sfui.map.SetSuperTrackedQuestID(0)
        elseif _G.C_SuperTrack.SetSuperTrackedQuestID then
            _G.C_SuperTrack.SetSuperTrackedQuestID(0)
        end
    end
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
    sharedRecentlyWatched[questID] = true
    if recentlyWatched then recentlyWatched[questID] = true end
    return true
end

--- inserts a quest link into the active chat / macro / communities edit box.
--- @return boolean inserted
function QuestCommon.TryInsertQuestLink(questID, questLogIndex, questTitle, questLevel)
    if not questID then return false end

    -- 1. blizzard modern api
    if ChatFrameUtil and ChatFrameUtil.TryInsertQuestLinkForQuestID then
        if ChatFrameUtil.TryInsertQuestLinkForQuestID(questID) then
            return true
        end
    end

    -- 2. detect an actively open & focused chat / input box
    -- note: CommunitiesFrame.ChatEditBox:IsShown() is true even when CommunitiesFrame is hidden;
    -- always check :IsVisible() and :HasFocus() so closed panels never swallow shift-clicks.
    local activeChat = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow())
        or (_G.ChatEdit_GetActiveWindow and _G.ChatEdit_GetActiveWindow())
        or _G.ACTIVE_CHAT_EDIT_BOX
    local isChatOpen = (activeChat and activeChat:IsVisible())
        or (_G.MacroFrameText and _G.MacroFrameText:IsVisible() and _G.MacroFrameText:HasFocus())
        or (_G.CommunitiesFrame and _G.CommunitiesFrame.ChatEditBox and _G.CommunitiesFrame.ChatEditBox:IsVisible() and _G.CommunitiesFrame.ChatEditBox:HasFocus())

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
            local level = tonumber(questLevel)
                or (C_QuestLog and C_QuestLog.GetQuestDifficultyLevel and C_QuestLog.GetQuestDifficultyLevel(questID))
                or 0
            link = string_format("|cffffff00|Hquest:%d:%d|h[%s]|h|r", questID, level, title)
        end
    end

    if not link then
        return false
    end

    -- 4. insert into the active edit box
    return sfui.common.insert_link_to_chat(link)
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
local playerClassToken = nil
function QuestCommon.GetPlayerClassLocalized()
    if not playerClassLocalized and _G.UnitClass then
        playerClassLocalized, playerClassToken = _G.UnitClass("player")
    end
    return playerClassLocalized, playerClassToken
end

local classHeaderToToken = nil
local function get_class_header_map()
    if classHeaderToToken then return classHeaderToToken end
    classHeaderToToken = {
        ["warrior"]      = "WARRIOR",
        ["paladin"]      = "PALADIN",
        ["hunter"]       = "HUNTER",
        ["rogue"]        = "ROGUE",
        ["priest"]       = "PRIEST",
        ["death knight"] = "DEATHKNIGHT",
        ["shaman"]       = "SHAMAN",
        ["mage"]         = "MAGE",
        ["warlock"]      = "WARLOCK",
        ["monk"]         = "MONK",
        ["druid"]        = "DRUID",
        ["demon hunter"] = "DEMONHUNTER",
        ["evoker"]       = "EVOKER",
    }
    if type(_G.LOCALIZED_CLASS_NAMES_MALE) == "table" then
        for token, locName in pairs(_G.LOCALIZED_CLASS_NAMES_MALE) do
            if type(token) == "string" and type(locName) == "string" and locName ~= "" then
                classHeaderToToken[locName:lower()] = token
            end
        end
    end
    if type(_G.LOCALIZED_CLASS_NAMES_FEMALE) == "table" then
        for token, locName in pairs(_G.LOCALIZED_CLASS_NAMES_FEMALE) do
            if type(token) == "string" and type(locName) == "string" and locName ~= "" then
                classHeaderToToken[locName:lower()] = token
            end
        end
    end
    local pClassLoc, pClassTok = QuestCommon.GetPlayerClassLocalized()
    if pClassLoc and pClassTok then
        classHeaderToToken[pClassLoc:lower()] = pClassTok
    end
    return classHeaderToToken
end

function QuestCommon.GetQuestClassToken(questID, questLogIndex, headerTitle)
    if type(questLogIndex) == "string" and not headerTitle then
        headerTitle = questLogIndex
        questLogIndex = nil
    end

    local map = get_class_header_map()
    if type(headerTitle) == "string" and headerTitle ~= "" then
        local tok = map[headerTitle:lower()]
        if tok then return tok end
    end

    if questID and C_QuestLog and C_QuestLog.GetHeaderIndexForQuest then
        local hIdx = C_QuestLog.GetHeaderIndexForQuest(questID)
        if hIdx then
            local hInfo = C_QuestLog.GetInfo(hIdx)
            if hInfo and type(hInfo.title) == "string" and hInfo.title ~= "" then
                local tok = map[hInfo.title:lower()]
                if tok then return tok end
            end
        end
    end

    return nil
end

--- true when the quest sits under a class header in the quest log.
--- accepts (questID, headerTitle) as a legacy call form.
function QuestCommon.IsClassQuest(questID, questLogIndex, headerTitle)
    return QuestCommon.GetQuestClassToken(questID, questLogIndex, headerTitle) ~= nil
end

local table_insert = table.insert
local table_concat = table.concat
local tonumber = tonumber
local tostring = tostring

function QuestCommon.IsObjectiveTextFinished(txt, isFinFlag)
    if isFinFlag == 1 or isFinFlag == true then return true end
    if type(txt) ~= "string" then return false end
    local cur, max = txt:match("(%d+)%s*/%s*(%d+)")
    if cur and max then
        local nCur, nMax = tonumber(cur), tonumber(max)
        if nCur and nMax and nMax > 0 and nCur >= nMax then
            return true
        end
    end
    return false
end

function QuestCommon.GetSyncedQuestTrackerInfo(questID, requiredClass)
    if not questID or not (sfui.sync and sfui.sync.GetQuestPeerStatuses) then
        return nil
    end
    local peerStatuses = sfui.sync.GetQuestPeerStatuses(questID, false)
    if not peerStatuses or #peerStatuses == 0 then
        return nil
    end

    local missingPeers = nil
    local readyPeers = nil
    local objOrder = nil
    local objByKey = nil
    local hasProgress = false
    local hasIncompletePeers = false
    local hasActivePeers = false

    local function add_peer_obj(peerLabel, objText)
        local clean = tostring(objText or ""):gsub(" / ", "/")
        if clean == "" then return end
        local key = clean:lower()
        objOrder = objOrder or {}
        objByKey = objByKey or {}
        local entry = objByKey[key]
        if not entry then
            entry = {
                text  = clean,
                names = { peerLabel },
            }
            objByKey[key] = entry
            objOrder[#objOrder + 1] = entry
        else
            entry.names[#entry.names + 1] = peerLabel
        end
    end

    for _, peer in ipairs(peerStatuses) do
        local pLabel = peer.coloredName or peer.name or "?"
        if peer.status == "missing" then
            if peer.inParty and (not requiredClass or peer.class == requiredClass) then
                missingPeers = missingPeers or {}
                missingPeers[#missingPeers + 1] = pLabel
            end
        elseif peer.status == "active" then
            hasActivePeers = true
            hasIncompletePeers = true
            if peer.hasProgress then
                hasProgress = true
            end
            local list = peer.unfinishedObjs
            if type(list) == "table" and #list > 0 then
                for _, oTxt in ipairs(list) do
                    add_peer_obj(pLabel, oTxt)
                end
            elseif type(peer.objs) == "table" and #peer.objs > 0 then
                for idx, oTxt in ipairs(peer.objs) do
                    local finFlag = type(peer.objFinished) == "table" and peer.objFinished[idx] or nil
                    if not QuestCommon.IsObjectiveTextFinished(oTxt, finFlag) then
                        add_peer_obj(pLabel, oTxt)
                    end
                end
            else
                add_peer_obj(pLabel, "in progress")
            end
        elseif peer.status == "ready" then
            hasActivePeers = true
            hasProgress = true
            readyPeers = readyPeers or {}
            readyPeers[#readyPeers + 1] = pLabel
        end
    end

    local hasMissingParty = (missingPeers ~= nil and #missingPeers > 0)
    if not hasMissingParty and not objOrder and not readyPeers then
        return nil
    end

    return {
        missingPeers       = missingPeers,
        hasMissingParty    = hasMissingParty,
        peerObjLines       = objOrder,
        readyPeers         = readyPeers,
        hasIncompletePeers = hasIncompletePeers,
        hasActivePeers     = hasActivePeers,
        hasProgress        = hasProgress,
    }
end

function QuestCommon.PrependMissingQuestLine(lines, syncInfo)
    if not syncInfo or not syncInfo.hasMissingParty or not syncInfo.missingPeers then return end
    table_insert(lines, {
        text      = "! missing: " .. table_concat(syncInfo.missingPeers, ", "),
        completed = false,
        color     = { 1.0, 0.35, 0.35, 1 },
    })
end

function QuestCommon.AppendSyncedQuestLines(lines, syncInfo)
    if not syncInfo then return end
    if syncInfo.peerObjLines then
        for _, entry in ipairs(syncInfo.peerObjLines) do
            table_insert(lines, {
                text      = table_concat(entry.names, ", ") .. ": " .. entry.text,
                completed = false,
                color     = { 0.78, 0.86, 0.95, 1 },
            })
        end
    end
    if syncInfo.readyPeers and #syncInfo.readyPeers > 0 then
        table_insert(lines, {
            text      = "ready: " .. table_concat(syncInfo.readyPeers, ", "),
            completed = true,
            color     = { 0.35, 0.95, 0.35, 1 },
        })
    end
end
