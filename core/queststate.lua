local addonName, addon = ...
sfui = sfui or {}
sfui.queststate = sfui.queststate or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/core/queststate.lua
--  single-pass coalesced quest log & completion cache (`sfui.queststate`).
--  eliminates redundant `QUEST_LOG_UPDATE` walks across quests, dungeonjournal,
--  map pins, ring_questitems, target indicator, and party sync.
-- ══════════════════════════════════════════════════════════════════════════════

local _G = _G
local pairs = _G.pairs
local type = _G.type
local wipe = _G.wipe or table.wipe
local string_lower = string.lower
local C_QuestLog = _G.C_QuestLog
local C_Timer = _G.C_Timer

local issecretvalue = (sfui.common and sfui.common.issecretvalue) or _G.issecretvalue or function() return false end

local QS = sfui.queststate
QS.hidden = true

local _initialized = false
local _pendingRefresh = false
local _pendingReason = "init"
local _pendingQuestID = nil
local _revision = 0
local _activeCount = 0

local activeByQuestID = {}
local activeByTitle = {}
local completedCache = {}
local _recordPool = {}
local _debugInfo = {}

local function AcquireRecord()
    local n = #_recordPool
    if n > 0 then
        local r = _recordPool[n]
        _recordPool[n] = nil
        return r
    end
    return {}
end

local function ClearActiveTables()
    for _, rec in pairs(activeByQuestID) do
        wipe(rec)
        _recordPool[#_recordPool + 1] = rec
    end
    wipe(activeByQuestID)
    wipe(activeByTitle)
    _activeCount = 0
end

local function CheckQuestCompletedRaw(questID)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        local res = C_QuestLog.IsQuestFlaggedCompleted(questID)
        if not issecretvalue(res) then
            return res == true
        end
    elseif _G.IsQuestFlaggedCompleted then
        return _G.IsQuestFlaggedCompleted(questID) == true
    end
    return false
end

local function ScanActiveQuestLog()
    ClearActiveTables()

    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local numEntries = C_QuestLog.GetNumQuestLogEntries()
        if not issecretvalue(numEntries) and type(numEntries) == "number" then
            for i = 1, numEntries do
                local info = C_QuestLog.GetInfo(i)
                if not issecretvalue(info) and info and not info.isHeader and not info.isHidden then
                    local qID = info.questID
                    if not issecretvalue(qID) and type(qID) == "number" and qID > 0 then
                        local rec = AcquireRecord()
                        local title = (not issecretvalue(info.title) and type(info.title) == "string" and info.title) or ""
                        local lowerTitle = (title ~= "") and string_lower(title) or nil
                        rec.questID = qID
                        rec.title = title
                        rec.lowerTitle = lowerTitle
                        rec.level = (not issecretvalue(info.level) and info.level) or 0
                        rec.frequency = info.frequency
                        rec.campaignID = info.campaignID
                        rec.logIndex = i
                        rec.isComplete = (C_QuestLog.IsComplete and C_QuestLog.IsComplete(qID) == true) or false
                        rec.isFailed = (C_QuestLog.IsFailed and C_QuestLog.IsFailed(qID) == true) or false

                        activeByQuestID[qID] = rec
                        if lowerTitle then
                            activeByTitle[lowerTitle] = rec
                        end
                        _activeCount = _activeCount + 1
                    end
                end
            end
        end
    elseif _G.GetNumQuestLogEntries and _G.GetQuestLogTitle then
        local numEntries = _G.GetNumQuestLogEntries()
        if type(numEntries) == "number" then
            for i = 1, numEntries do
                local title, level, _, isHeader, _, isComplete, frequency, questID = _G.GetQuestLogTitle(i)
                if not isHeader and type(questID) == "number" and questID > 0 then
                    local rec = AcquireRecord()
                    local cleanTitle = type(title) == "string" and title or ""
                    local lowerTitle = (cleanTitle ~= "") and string_lower(cleanTitle) or nil
                    rec.questID = questID
                    rec.title = cleanTitle
                    rec.lowerTitle = lowerTitle
                    rec.level = level or 0
                    rec.frequency = frequency
                    rec.logIndex = i
                    rec.isComplete = (isComplete == 1 or isComplete == true)
                    rec.isFailed = (isComplete == -1)

                    activeByQuestID[questID] = rec
                    if lowerTitle then
                        activeByTitle[lowerTitle] = rec
                    end
                    _activeCount = _activeCount + 1
                end
            end
        end
    end

    _initialized = true
    _revision = _revision + 1
end

local function FlushQuestRefresh()
    _pendingRefresh = false
    local reason = _pendingReason or "update"
    local qID = _pendingQuestID
    _pendingReason = nil
    _pendingQuestID = nil

    ScanActiveQuestLog()
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_QUEST_STATE_UPDATED", reason, qID, _revision)
    end
end

local function ScheduleQuestRefresh(reason, questID)
    _pendingReason = reason or _pendingReason or "update"
    if questID and not issecretvalue(questID) and type(questID) == "number" then
        _pendingQuestID = questID
    end
    if _pendingRefresh then return end
    if C_Timer and C_Timer.After then
        _pendingRefresh = true
        C_Timer.After(0.05, FlushQuestRefresh)
    else
        FlushQuestRefresh()
    end
end

local function EnsureInitialized()
    if not _initialized then
        ScanActiveQuestLog()
    end
end

-- ─── Public O(1) Read API ────────────────────────────────────────────────────

function QS.IsActive(questID)
    if issecretvalue(questID) or type(questID) ~= "number" then return false end
    EnsureInitialized()
    return activeByQuestID[questID] ~= nil
end

function QS.GetActive(questID)
    if issecretvalue(questID) or type(questID) ~= "number" then return nil end
    EnsureInitialized()
    return activeByQuestID[questID]
end

function QS.GetActiveByTitle(title)
    if issecretvalue(title) or type(title) ~= "string" or title == "" then return nil end
    EnsureInitialized()
    return activeByTitle[string_lower(title)]
end

function QS.IsActiveByTitle(title)
    return QS.GetActiveByTitle(title) ~= nil
end

function QS.GetAllActive()
    EnsureInitialized()
    return activeByQuestID
end

function QS.GetActiveCount()
    EnsureInitialized()
    return _activeCount
end

function QS.IsCompleted(questID)
    if issecretvalue(questID) or type(questID) ~= "number" or questID <= 0 then return false end
    local cached = completedCache[questID]
    if cached ~= nil then
        return cached
    end
    local done = CheckQuestCompletedRaw(questID)
    completedCache[questID] = done
    return done
end

function QS.InvalidateCompleted(questID)
    if questID and not issecretvalue(questID) and type(questID) == "number" then
        completedCache[questID] = nil
    else
        wipe(completedCache)
    end
end

function QS.GetRevision()
    EnsureInitialized()
    return _revision
end

function QS.ForceRefresh()
    ScanActiveQuestLog()
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_QUEST_STATE_UPDATED", "force", nil, _revision)
    end
end

function QS.GetDebugInfo()
    local compCount = 0
    for _ in pairs(completedCache) do compCount = compCount + 1 end
    _debugInfo.revision = _revision
    _debugInfo.activeQuests = _activeCount
    _debugInfo.cachedCompleted = compCount
    _debugInfo.pooledRecords = #_recordPool
    return _debugInfo
end

-- ─── Event Wiring ────────────────────────────────────────────────────────────

if sfui.events then
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        wipe(completedCache)
        ScheduleQuestRefresh("entering_world")
    end)

    sfui.events.RegisterEvent("QUEST_LOG_UPDATE", function()
        ScheduleQuestRefresh("log_update")
    end)

    sfui.events.RegisterEvent("QUEST_ACCEPTED", function(_, arg1, arg2)
        local qID = (type(arg2) == "number" and arg2) or (type(arg1) == "number" and arg1) or nil
        if qID then completedCache[qID] = false end
        ScheduleQuestRefresh("accepted", qID)
    end)

    sfui.events.RegisterEvent("QUEST_REMOVED", function(_, questID)
        if not issecretvalue(questID) and type(questID) == "number" then
            completedCache[questID] = nil
        end
        ScheduleQuestRefresh("removed", questID)
    end)

    sfui.events.RegisterEvent("QUEST_TURNED_IN", function(_, questID)
        if not issecretvalue(questID) and type(questID) == "number" then
            completedCache[questID] = true
        end
        ScheduleQuestRefresh("turned_in", questID)
    end)
end

if sfui.RegisterModule then
    sfui.RegisterModule("queststate", QS)
end

