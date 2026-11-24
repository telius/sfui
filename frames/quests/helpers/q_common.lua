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
local math_min = math.min
local string_format = string.format
local string_lower = string.lower
local C_QuestLog = _G.C_QuestLog
local InCombatLockdown = _G.InCombatLockdown
local ChatFrameUtil = _G.ChatFrameUtil
local GetQuestProgressBarPercent = _G.GetQuestProgressBarPercent
local issecretvalue = sfui.common and sfui.common.issecretvalue

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

function QuestCommon.AreAllLocalObjectivesFinished(questID, questLogIndex, objs)
    if objs == nil and questID and C_QuestLog and C_QuestLog.GetQuestObjectives then
        objs = C_QuestLog.GetQuestObjectives(questID)
    end
    if type(objs) == "table" and #objs > 0 then
        local sawObj = false
        for _, obj in ipairs(objs) do
            if type(obj) == "table" then
                if obj.type == "progressbar" or obj.type == 8 then
                    return false
                end
                if obj.text and obj.text ~= "" then
                    sawObj = true
                    if not obj.finished then
                        return false
                    end
                end
            end
        end
        return sawObj
    end
    if questLogIndex and _G.GetNumQuestLeaderBoards and _G.GetQuestLogLeaderBoard then
        local num = _G.GetNumQuestLeaderBoards(questLogIndex) or 0
        if num > 0 then
            local sawObj = false
            for objIndex = 1, num do
                local desc, _, isFinished = _G.GetQuestLogLeaderBoard(objIndex, questLogIndex)
                if desc and desc ~= "" then
                    sawObj = true
                    if not isFinished then
                        return false
                    end
                end
            end
            return sawObj
        end
    end
    return false
end

function QuestCommon.FormatCollapsedCompleteTag(canClickToComplete, syncInfo)
    local color = canClickToComplete and "|cffff00ff" or "|cff33ff33"
    if syncInfo and syncInfo.allPeersReady then
        return " " .. color .. "(all complete)|r"
    end
    return " " .. color .. "(Complete)|r"
end

function QuestCommon.GetSyncedQuestTrackerInfo(questID, requiredClass, peerSnapshot)
    if not questID or not sfui.sync then
        return nil
    end
    local peerStatuses
    if peerSnapshot and sfui.sync.GetQuestPeerStatusesFromSnapshot then
        peerStatuses = sfui.sync.GetQuestPeerStatusesFromSnapshot(peerSnapshot, questID, false)
    elseif sfui.sync.GetQuestPeerStatuses then
        peerStatuses = sfui.sync.GetQuestPeerStatuses(questID, false)
    end
    if not peerStatuses or #peerStatuses == 0 then
        return nil
    end

    local missingPeers = nil
    local readyPeers = nil
    local donePeers = nil
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
            local list = peer.unfinishedObjs
            local addedUnfinished = false
            if type(list) == "table" and #list > 0 then
                for _, oTxt in ipairs(list) do
                    if not QuestCommon.IsObjectiveTextFinished(oTxt, nil) then
                        add_peer_obj(pLabel, oTxt)
                        addedUnfinished = true
                    end
                end
            elseif type(peer.objs) == "table" and #peer.objs > 0 then
                for idx, oTxt in ipairs(peer.objs) do
                    local finFlag = type(peer.objFinished) == "table" and peer.objFinished[idx] or nil
                    if not QuestCommon.IsObjectiveTextFinished(oTxt, finFlag) then
                        add_peer_obj(pLabel, oTxt)
                        addedUnfinished = true
                    end
                end
            else
                add_peer_obj(pLabel, "in progress")
                addedUnfinished = true
            end
            if addedUnfinished then
                hasIncompletePeers = true
                if peer.hasProgress then
                    hasProgress = true
                end
            elseif type(peer.objs) == "table" and #peer.objs > 0 then
                hasProgress = true
                readyPeers = readyPeers or {}
                readyPeers[#readyPeers + 1] = pLabel
            end
        elseif peer.status == "ready" then
            hasActivePeers = true
            hasProgress = true
            readyPeers = readyPeers or {}
            readyPeers[#readyPeers + 1] = pLabel
        elseif peer.status == "completed" then
            hasActivePeers = true
            hasProgress = true
            donePeers = donePeers or {}
            donePeers[#donePeers + 1] = pLabel
        end
    end

    local hasMissingParty = (missingPeers ~= nil and #missingPeers > 0)
    local allPeersReady = (not hasIncompletePeers) and (not hasMissingParty)
        and ((readyPeers ~= nil and #readyPeers > 0) or (donePeers ~= nil and #donePeers > 0))
    if not hasMissingParty and not objOrder and not readyPeers and not donePeers then
        return nil
    end

    return {
        missingPeers       = missingPeers,
        hasMissingParty    = hasMissingParty,
        peerObjLines       = objOrder,
        readyPeers         = readyPeers,
        donePeers          = donePeers,
        hasIncompletePeers = hasIncompletePeers,
        hasActivePeers     = hasActivePeers,
        hasProgress        = hasProgress,
        allPeersReady      = allPeersReady,
    }
end

function QuestCommon.PrependMissingQuestLine(lines, syncInfo)
    if not syncInfo or not syncInfo.hasMissingParty or not syncInfo.missingPeers then return end
    table_insert(lines, {
        text      = "! missing: " .. table_concat(syncInfo.missingPeers, ", "),
        completed = false,
        color     = { 1.0, 0.35, 0.35, 1 },
        isSynced  = true,
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
                isSynced  = true,
            })
        end
    end
    if syncInfo.readyPeers and #syncInfo.readyPeers > 0 then
        table_insert(lines, {
            text      = "ready: " .. table_concat(syncInfo.readyPeers, ", "),
            completed = true,
            color     = { 0.35, 0.95, 0.35, 1 },
            isSynced  = true,
        })
    end
    if syncInfo.donePeers and #syncInfo.donePeers > 0 then
        table_insert(lines, {
            text      = "done: " .. table_concat(syncInfo.donePeers, ", "),
            completed = true,
            color     = { 0.40, 0.85, 0.45, 1 },
            isSynced  = true,
        })
    end
end

--- Open quest in the Dungeon Journal if it is a known dungeon quest.
--- @return boolean handled
function QuestCommon.OpenDungeonJournalQuest(questID, questLogIndex, isDungeonQuestFn)
    if not questID or not (sfui.dungeonjournal and sfui.dungeonjournal.SelectQuest) then
        return false
    end
    local isDJ = (sfui.dj_camelot and sfui.dj_camelot.IsDungeonQuest and sfui.dj_camelot.IsDungeonQuest(questID))
        or (isDungeonQuestFn and isDungeonQuestFn(questID, questLogIndex))
        or (sfui.questlog and sfui.questlog.IsDungeonQuest and sfui.questlog.IsDungeonQuest(questID, questLogIndex))
    if isDJ and sfui.dungeonjournal.SelectQuest(nil, questID) then
        return true
    end
    return false
end

--- Abandon a quest via C_QuestLog / StaticPopup with combat guard.
function QuestCommon.AbandonQuest(questID, questTitle, prepareSelection)
    if InCombatLockdown and InCombatLockdown() then return end
    if C_QuestLog and C_QuestLog.CanAbandonQuest and C_QuestLog.CanAbandonQuest(questID) then
        if prepareSelection then
            if C_QuestLog.SetSelectedQuest then
                C_QuestLog.SetSelectedQuest(questID)
            end
            if C_QuestLog.SetAbandonQuest then
                C_QuestLog.SetAbandonQuest()
            end
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
        sfui.common.print("quest cannot be abandoned.")
    end
end

local function ResolveQuestLogIndexByID(questID)
    if not questID or (issecretvalue and issecretvalue(questID)) or type(questID) ~= "number" or questID <= 0 then
        return nil
    end
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        local idx = C_QuestLog.GetLogIndexForQuestID(questID)
        if idx and (not issecretvalue or not issecretvalue(idx)) and type(idx) == "number" and idx > 0 then
            return idx
        end
    end
    if _G.GetQuestLogIndexByID then
        local idx = _G.GetQuestLogIndexByID(questID)
        if idx and (not issecretvalue or not issecretvalue(idx)) and type(idx) == "number" and idx > 0 then
            return idx
        end
    end
    if _G.GetNumQuestLogEntries and _G.GetQuestLogTitle then
        local numEntries = _G.GetNumQuestLogEntries()
        if type(numEntries) == "number" and numEntries > 0 then
            for i = 1, numEntries do
                local _, _, _, isHeader, _, _, _, qID = _G.GetQuestLogTitle(i)
                if not isHeader and qID == questID then
                    return i
                end
            end
        end
    end
    return nil
end

local function CanAbandonQuestID(questID)
    if not questID or (issecretvalue and issecretvalue(questID)) or type(questID) ~= "number" or questID <= 0 then
        return false
    end
    if C_QuestLog and C_QuestLog.CanAbandonQuest then
        return C_QuestLog.CanAbandonQuest(questID) == true
    elseif _G.CanAbandonQuest then
        return _G.CanAbandonQuest(questID) == true
    end
    local idx = ResolveQuestLogIndexByID(questID)
    return idx ~= nil and idx > 0
end
QuestCommon.CanAbandonQuest = CanAbandonQuestID

local function ExtractBlockQuestID(b)
    if not b or b.isRemotePeerQuest or b.isWorldQuest or b._isAutoOffer then
        return nil
    end
    local qID = b.questID or (b._isClickToComplete and b._popQuestID or nil)
    if not qID or (issecretvalue and issecretvalue(qID)) or type(qID) ~= "number" or qID <= 0 then
        return nil
    end
    return qID
end

--- Fast check for whether a tracker section contains at least one abandonable local quest.
--- @param blocks table|nil
--- @return boolean
function QuestCommon.HasAbandonableQuests(blocks)
    if not blocks then return false end
    for _, b in ipairs(blocks) do
        local qID = ExtractBlockQuestID(b)
        if qID and CanAbandonQuestID(qID) then
            return true
        end
    end
    return false
end

--- Collect deduplicated abandonable quests and non-abandonable count for a tracker section.
--- @param blocks table|nil
--- @return table abandonable, number nonAbandonableCount, boolean hasLocalQuestBlocks
function QuestCommon.GetAbandonableQuests(blocks)
    local abandonable = {}
    local nonAbandonableCount = 0
    local hasLocalQuestBlocks = false
    if not blocks then
        return abandonable, nonAbandonableCount, hasLocalQuestBlocks
    end

    local seen = {}
    for _, b in ipairs(blocks) do
        local qID = ExtractBlockQuestID(b)
        if qID and not seen[qID] then
            seen[qID] = true
            hasLocalQuestBlocks = true
            if CanAbandonQuestID(qID) then
                local rawTitle = b.rawTitle or b._popTitle
                    or (C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(qID))
                    or b.title
                    or ("quest " .. tostring(qID))
                local displayTitle = (sfui.common and sfui.common.strip_colors and sfui.common.strip_colors(rawTitle, true, true))
                    or tostring(rawTitle)
                if displayTitle == "" then
                    displayTitle = "quest " .. tostring(qID)
                end
                table_insert(abandonable, {
                    questID             = qID,
                    rawTitle            = rawTitle,
                    displayTitle        = displayTitle,
                    isComplete          = (b.isComplete == true or b._isClickToComplete == true),
                    isAutoCompletePopup = (b._isClickToComplete == true),
                })
            else
                nonAbandonableCount = nonAbandonableCount + 1
            end
        end
    end

    return abandonable, nonAbandonableCount, hasLocalQuestBlocks
end

local function CollectDestroyedItemsForQuests(quests)
    local items = {}
    local itemSet = {}
    if not quests or #quests == 0 then
        return items
    end

    local function AddItemName(name)
        if not name or (issecretvalue and issecretvalue(name)) or type(name) ~= "string" then
            return
        end
        local trimmed = name:match("^%s*(.-)%s*$") or ""
        if trimmed == "" then return end
        local lowerName = string_lower(trimmed)
        if not itemSet[lowerName] then
            itemSet[lowerName] = true
            table_insert(items, lowerName)
        end
    end

    if C_QuestLog and C_QuestLog.SetSelectedQuest and C_QuestLog.SetAbandonQuest and C_QuestLog.GetAbandonQuestItems then
        local oldSelected = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest() or nil
        for _, q in ipairs(quests) do
            C_QuestLog.SetSelectedQuest(q.questID)
            C_QuestLog.SetAbandonQuest()
            if not C_QuestLog.GetAbandonQuest or C_QuestLog.GetAbandonQuest() == q.questID then
                local itemIDs = C_QuestLog.GetAbandonQuestItems()
                if type(itemIDs) == "table" then
                    for _, itemID in ipairs(itemIDs) do
                        local itemName = (_G.C_Item and _G.C_Item.GetItemNameByID and _G.C_Item.GetItemNameByID(itemID))
                            or (_G.GetItemInfo and _G.GetItemInfo(itemID))
                        AddItemName(itemName)
                    end
                end
            end
        end
        if oldSelected and (not issecretvalue or not issecretvalue(oldSelected)) and type(oldSelected) == "number" and oldSelected > 0 then
            C_QuestLog.SetSelectedQuest(oldSelected)
        end
    elseif _G.SelectQuestLogEntry and _G.SetAbandonQuest and _G.GetAbandonQuestItems then
        local oldSelected = _G.GetQuestLogSelection and _G.GetQuestLogSelection() or nil
        for _, q in ipairs(quests) do
            local idx = ResolveQuestLogIndexByID(q.questID)
            if idx and idx > 0 then
                _G.SelectQuestLogEntry(idx)
                _G.SetAbandonQuest()
                local rawItems = _G.GetAbandonQuestItems()
                if rawItems and (not issecretvalue or not issecretvalue(rawItems)) and type(rawItems) == "string" and rawItems ~= "" then
                    for entry in rawItems:gmatch("[^,]+") do
                        AddItemName(entry)
                    end
                end
            end
        end
        if oldSelected and type(oldSelected) == "number" and oldSelected > 0 then
            local numEntries = _G.GetNumQuestLogEntries and _G.GetNumQuestLogEntries()
            if type(numEntries) == "number" and oldSelected <= numEntries then
                _G.SelectQuestLogEntry(oldSelected)
            end
        end
    end

    return items
end

local function AbandonQuestBatch(quests, sectionLabel)
    if InCombatLockdown and InCombatLockdown() then
        if sfui.common and sfui.common.print then
            sfui.common.print("cannot abandon quests in combat.")
        end
        return 0
    end
    if not quests or #quests == 0 then
        return 0
    end

    local abandonedIDs = {}
    local abandonedCount = 0

    if C_QuestLog and C_QuestLog.SetSelectedQuest and C_QuestLog.SetAbandonQuest and C_QuestLog.AbandonQuest then
        local oldSelected = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest() or nil
        for _, q in ipairs(quests) do
            local qID = q.questID
            local inLog = (not C_QuestLog.GetLogIndexForQuestID) or (C_QuestLog.GetLogIndexForQuestID(qID) ~= nil)
            if inLog and CanAbandonQuestID(qID) then
                C_QuestLog.SetSelectedQuest(qID)
                C_QuestLog.SetAbandonQuest()
                if not C_QuestLog.GetAbandonQuest or C_QuestLog.GetAbandonQuest() == qID then
                    C_QuestLog.AbandonQuest()
                    abandonedIDs[qID] = true
                    abandonedCount = abandonedCount + 1
                    sharedRecentlyWatched[qID] = nil
                    if q.isAutoCompletePopup and _G.RemoveAutoQuestPopUp then
                        _G.RemoveAutoQuestPopUp(qID)
                    end
                end
            end
        end
        if oldSelected and (not issecretvalue or not issecretvalue(oldSelected))
            and type(oldSelected) == "number" and oldSelected > 0
            and not abandonedIDs[oldSelected]
            and (not C_QuestLog.GetLogIndexForQuestID or C_QuestLog.GetLogIndexForQuestID(oldSelected) ~= nil) then
            C_QuestLog.SetSelectedQuest(oldSelected)
        end
    elseif _G.SelectQuestLogEntry and _G.SetAbandonQuest and _G.AbandonQuest then
        local oldSelected = _G.GetQuestLogSelection and _G.GetQuestLogSelection() or nil
        for _, q in ipairs(quests) do
            local idx = ResolveQuestLogIndexByID(q.questID)
            if idx and idx > 0 and CanAbandonQuestID(q.questID) then
                _G.SelectQuestLogEntry(idx)
                _G.SetAbandonQuest()
                local pendingName = _G.GetAbandonQuestName and _G.GetAbandonQuestName() or nil
                if not pendingName or not q.rawTitle or pendingName == q.rawTitle then
                    _G.AbandonQuest()
                    abandonedIDs[q.questID] = true
                    abandonedCount = abandonedCount + 1
                    sharedRecentlyWatched[q.questID] = nil
                end
            end
        end
        if oldSelected and type(oldSelected) == "number" and oldSelected > 0 then
            local numEntries = _G.GetNumQuestLogEntries and _G.GetNumQuestLogEntries()
            if type(numEntries) == "number" and oldSelected <= numEntries then
                _G.SelectQuestLogEntry(oldSelected)
            end
        end
    end

    if abandonedCount > 0 then
        if _G.QuestLogPopupDetailFrame and _G.QuestLogPopupDetailFrame:IsShown() and _G.HideUIPanel then
            _G.HideUIPanel(_G.QuestLogPopupDetailFrame)
        end
        if _G.StaticPopup_Hide then
            _G.StaticPopup_Hide("ABANDON_QUEST")
            _G.StaticPopup_Hide("ABANDON_QUEST_WITH_ITEMS")
        end
        if _G.PlaySound and _G.SOUNDKIT and _G.SOUNDKIT.IG_QUEST_LOG_ABANDON_QUEST then
            _G.PlaySound(_G.SOUNDKIT.IG_QUEST_LOG_ABANDON_QUEST)
        end

        local curSuper = _G.C_SuperTrack and _G.C_SuperTrack.GetSuperTrackedQuestID and _G.C_SuperTrack.GetSuperTrackedQuestID()
        if curSuper and abandonedIDs[curSuper] then
            if sfui.map and sfui.map.SetSuperTrackedQuestID then
                sfui.map.SetSuperTrackedQuestID(0)
            elseif _G.C_SuperTrack and _G.C_SuperTrack.SetSuperTrackedQuestID then
                _G.C_SuperTrack.SetSuperTrackedQuestID(0)
            end
        end

        if sfui.tracker then
            for _, mod in ipairs(sfui.tracker.modules or {}) do
                if mod.MarkDirty then mod:MarkDirty() end
            end
            if sfui.tracker.RequestRefresh then
                sfui.tracker.RequestRefresh(0.05)
            end
        end

        local label = (type(sectionLabel) == "string" and sectionLabel ~= "") and string_lower(sectionLabel) or "section"
        if sfui.common and sfui.common.print then
            sfui.common.print(string_format("abandoned %d %s in %s.",
                abandonedCount, (abandonedCount == 1) and "quest" or "quests", label))
        end
    end

    return abandonedCount
end

if _G.StaticPopupDialogs then
    _G.StaticPopupDialogs["SFUI_ABANDON_SECTION_QUESTS"] = {
        text = "%s",
        button1 = "abandon",
        button2 = "cancel",
        OnAccept = function(_, data)
            if data and data.quests then
                AbandonQuestBatch(data.quests, data.sectionLabel)
            end
        end,
        timeout = 0,
        whileDead = true,
        exclusive = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

--- Prompt confirmation and abandon all abandonable quests in a tracker section.
--- @param sec table|nil Section table containing id, title, and blocks
--- @return boolean handled
function QuestCommon.AbandonSectionQuests(sec)
    if InCombatLockdown and InCombatLockdown() then return false end
    if not sec or not sec.blocks or #sec.blocks == 0 then return false end

    local quests, skippedCount, hasLocalQuests = QuestCommon.GetAbandonableQuests(sec.blocks)
    if not hasLocalQuests then
        return false
    end

    local rawLabel = sec.title or sec.id or "section"
    local cleanLabel = (sfui.common and sfui.common.strip_colors and sfui.common.strip_colors(tostring(rawLabel), true, true))
        or tostring(rawLabel)
    cleanLabel = string_lower(cleanLabel):gsub("%s*%[zone%]%s*$", "")
    cleanLabel = cleanLabel:match("^%s*(.-)%s*$") or cleanLabel
    if cleanLabel == "" then cleanLabel = "section" end

    if #quests == 0 then
        if sfui.common and sfui.common.print then
            sfui.common.print("no abandonable quests in " .. cleanLabel .. ".")
        end
        return true
    end

    local parts = {
        string_format("abandon %d %s in |cff00ffff%s|r?",
            #quests, (#quests == 1) and "quest" or "quests", cleanLabel),
        "",
    }
    local maxList = 8
    local showCount = math_min(#quests, maxList)
    for i = 1, showCount do
        local q = quests[i]
        local line = "- " .. string_lower(q.displayTitle)
        if q.isComplete then
            line = line .. " |cff33ff33(complete)|r"
        end
        table_insert(parts, line)
    end
    if #quests > maxList then
        table_insert(parts, string_format("...and %d more", #quests - maxList))
    end
    if skippedCount > 0 then
        table_insert(parts, "")
        table_insert(parts, string_format("|cff888888(%d %s cannot be abandoned and will be kept)|r",
            skippedCount, (skippedCount == 1) and "quest" or "quests"))
    end

    local destroyedItems = CollectDestroyedItemsForQuests(quests)
    if #destroyedItems > 0 then
        local itemLines = {}
        local maxItems = 5
        for i = 1, math_min(#destroyedItems, maxItems) do
            table_insert(itemLines, destroyedItems[i])
        end
        local itemText = table_concat(itemLines, ", ")
        if #destroyedItems > maxItems then
            itemText = itemText .. string_format(" ...and %d more", #destroyedItems - maxItems)
        end
        table_insert(parts, "")
        table_insert(parts, "|cffff6666destroys items:|r " .. itemText)
    end

    local msg = table_concat(parts, "\n")
    if _G.StaticPopup_Hide then
        _G.StaticPopup_Hide("ABANDON_QUEST")
        _G.StaticPopup_Hide("ABANDON_QUEST_WITH_ITEMS")
    end
    if _G.StaticPopup_Show then
        _G.StaticPopup_Show("SFUI_ABANDON_SECTION_QUESTS", msg, nil, {
            quests = quests,
            sectionLabel = cleanLabel,
        })
    end
    return true
end

--- Share a quest with the player's group with combat & pushability guards.
function QuestCommon.ShareQuest(questID, questLogIndex, questTitle)
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
end
