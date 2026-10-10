local addonName, addon = ...
sfui = sfui or {}
sfui.experience = sfui.experience or {}
sfui.experience.data = {}

local data = sfui.experience.data

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/experience/data.lua
--  Data queries, calculations, reputation parsing, and session analytics
-- ══════════════════════════════════════════════════════════════════════════════

local _G = _G
local math_min = math.min
local math_max = math.max
local math_floor = math.floor
local string_format = string.format
local string_lower = string.lower
local table_insert = table.insert
local table_remove = table.remove
local pairs = _G.pairs
local pcall = _G.pcall
local GetTime = _G.GetTime
local UnitXP = _G.UnitXP
local UnitXPMax = _G.UnitXPMax
local UnitLevel = _G.UnitLevel
local GetXPExhaustion = _G.GetXPExhaustion
local GetRestState = _G.GetRestState
local IsXPUserDisabled = _G.IsXPUserDisabled
local UnitTrialXP = _G.UnitTrialXP
local UnitTrialBankedLevels = _G.UnitTrialBankedLevels
local GameRulesUtil = _G.GameRulesUtil
local C_QuestLog = _G.C_QuestLog
local GetQuestLogRewardXP = _G.GetQuestLogRewardXP
local C_Reputation = _G.C_Reputation
local C_MajorFactions = _G.C_MajorFactions
local C_GossipInfo = _G.C_GossipInfo
local GetWatchedFactionInfo = _G.GetWatchedFactionInfo
local FACTION_BAR_COLORS = _G.FACTION_BAR_COLORS

-- ─── Session State ────────────────────────────────────────────────────────────
local sessionStartTime = nil
local sessionXP = 0
local recentKillXPs = {}
local MAX_RECENT_KILLS = 10

--- Initialize or reset session analytics
function data.InitSession()
    sessionStartTime = GetTime()
    sessionXP = 0
    recentKillXPs = {}
end

--- Record an XP gain event
--- @param amount number
--- @param isKill boolean|nil
function data.RecordXPGain(amount, isKill)
    if not amount or amount <= 0 then return end
    if not sessionStartTime then
        sessionStartTime = GetTime()
    end
    sessionXP = sessionXP + amount
    if isKill then
        table_insert(recentKillXPs, amount)
        if #recentKillXPs > MAX_RECENT_KILLS then
            table_remove(recentKillXPs, 1)
        end
    end
end

-- ─── Level & Max Level Status ────────────────────────────────────────────────
--- Check if player is at effective max level
--- @return boolean
function data.IsMaxLevel()
    if GameRulesUtil and GameRulesUtil.IsPlayerAtEffectiveMaxLevel then
        local ok, isMax = pcall(GameRulesUtil.IsPlayerAtEffectiveMaxLevel)
        if ok and isMax ~= nil then
            return isMax
        end
    end
    local maxLevel = (_G.GetMaxPlayerLevel and _G.GetMaxPlayerLevel()) or 80
    return UnitLevel("player") >= maxLevel
end

--- Check if XP gain is disabled for character
--- @return boolean
function data.IsXPDisabled()
    if IsXPUserDisabled then
        local ok, disabled = pcall(IsXPUserDisabled)
        if ok and disabled then return true end
    end
    return false
end

-- ─── Static Output Cache Tables (Zero-allocation on hot path) ───────────────
local _xpData = {}
local _restedData = {}
local _questData = {}
local _repData = {}
local _sessionData = {}
local _repColor = { 0, 0, 0, 1 }

-- ─── Experience Data ──────────────────────────────────────────────────────────
--- Query active experience values
--- @return table
function data.GetXPData()
    local isMax = data.IsMaxLevel()
    local isTrial = (UnitTrialXP and UnitTrialXP("player") > 0)
    local currXP = (isTrial and UnitTrialXP("player")) or UnitXP("player") or 0
    local maxXP = UnitXPMax("player") or 1
    if maxXP <= 0 then maxXP = 1 end

    local remaining = math_max(0, maxXP - currXP)
    local percent = math_min(100, math_max(0, (currXP / maxXP) * 100))
    local level = UnitLevel("player") or 1
    local bankedLevels = (UnitTrialBankedLevels and UnitTrialBankedLevels("player")) or 0

    _xpData.current = currXP
    _xpData.max = maxXP
    _xpData.remaining = remaining
    _xpData.percent = percent
    _xpData.level = level
    _xpData.isMaxLevel = isMax
    _xpData.isTrial = isTrial
    _xpData.bankedLevels = bankedLevels
    _xpData.isXPDisabled = data.IsXPDisabled()

    return _xpData
end

-- ─── Rested Exhaustion Data ───────────────────────────────────────────────────
--- Query rested bonus data
--- @param maxXP number|nil
--- @return table
function data.GetRestedData(maxXP)
    maxXP = maxXP or UnitXPMax("player") or 1
    if maxXP <= 0 then maxXP = 1 end

    local exhaustion = (GetXPExhaustion and GetXPExhaustion()) or 0
    local restState = (GetRestState and GetRestState()) or 0
    local restedPercent = math_max(0, (exhaustion / maxXP) * 100)

    _restedData.restedXP = exhaustion
    _restedData.restedPercent = restedPercent
    _restedData.isRested = (exhaustion > 0)
    _restedData.restState = restState

    return _restedData
end

-- ─── Quest Log Turn-In Preview Data ───────────────────────────────────────────
--- Calculate experience pending from completed quests in quest log
--- @param maxXP number|nil
--- @return table
function data.GetQuestXPData(maxXP)
    maxXP = maxXP or UnitXPMax("player") or 1
    if maxXP <= 0 then maxXP = 1 end

    local totalQuestXP = 0
    local completedCount = 0

    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        local numEntries = C_QuestLog.GetNumQuestLogEntries() or 0
        for i = 1, numEntries do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and not info.isHidden then
                local qID = info.questID
                if qID and C_QuestLog.IsComplete(qID) then
                    local xp = (GetQuestLogRewardXP and GetQuestLogRewardXP(qID)) or 0
                    if xp > 0 then
                        totalQuestXP = totalQuestXP + xp
                        completedCount = completedCount + 1
                    end
                end
            end
        end
    elseif _G.GetNumQuestLogEntries and _G.GetQuestLogTitle then
        local numEntries = _G.GetNumQuestLogEntries() or 0
        for i = 1, numEntries do
            local title, _, _, isHeader, _, isComplete, _, questID = _G.GetQuestLogTitle(i)
            if not isHeader and questID and (isComplete == 1 or isComplete == true) then
                local xp = (GetQuestLogRewardXP and GetQuestLogRewardXP(questID)) or 0
                if xp > 0 then
                    totalQuestXP = totalQuestXP + xp
                    completedCount = completedCount + 1
                end
            end
        end
    end

    local questPercent = (totalQuestXP / maxXP) * 100

    _questData.totalQuestXP = totalQuestXP
    _questData.completedCount = completedCount
    _questData.questPercent = questPercent

    return _questData
end

-- ─── Reputation & Renown Data ─────────────────────────────────────────────────
--- Query watched faction, renown, or friendship progress
--- @return table
function data.GetReputationData()
    -- 1. Retail / Midnight API: C_Reputation.GetWatchedFactionData()
    if C_Reputation and C_Reputation.GetWatchedFactionData then
        local watched = C_Reputation.GetWatchedFactionData()
        if watched and watched.factionID and watched.factionID > 0 then
            local factionID = watched.factionID
            local name = watched.name or "faction"
            local currentVal = watched.currentStanding or 0
            local minVal = watched.currentReactionThreshold or 0
            local maxVal = watched.nextReactionThreshold or 1
            local reaction = watched.reaction or 4

            local standingText = _G["FACTION_STANDING_LABEL" .. reaction] or "neutral"
            local isParagon = false
            local isRenown = false
            local isFriendship = false
            local hasRewardPending = false

            -- Check Paragon
            if C_Reputation.IsFactionParagonForCurrentPlayer and C_Reputation.IsFactionParagonForCurrentPlayer(factionID) then
                local cur, threshold, _, rewardPending = C_Reputation.GetFactionParagonInfo(factionID)
                if threshold and threshold > 0 then
                    isParagon = true
                    currentVal = cur % threshold
                    minVal = 0
                    maxVal = threshold
                    standingText = "paragon"
                    hasRewardPending = rewardPending or false
                end
            -- Check Major Faction / Renown
            elseif C_Reputation.IsMajorFaction and C_Reputation.IsMajorFaction(factionID) and C_MajorFactions then
                local majorData = C_MajorFactions.GetMajorFactionData(factionID)
                if majorData then
                    isRenown = true
                    currentVal = majorData.renownReputationEarned or 0
                    minVal = 0
                    maxVal = majorData.renownLevelThreshold or 2500
                    standingText = string_format("renown %d", majorData.renownLevel or 1)
                end
            -- Check Friendship
            elseif C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
                local friendInfo = C_GossipInfo.GetFriendshipReputation(factionID)
                if friendInfo and friendInfo.friendshipFactionID and friendInfo.friendshipFactionID > 0 then
                    isFriendship = true
                    standingText = friendInfo.reaction or "friend"
                    if friendInfo.nextThreshold then
                        minVal = friendInfo.reactionThreshold or 0
                        maxVal = friendInfo.nextThreshold
                        currentVal = friendInfo.standing or 0
                    else
                        -- Max rank friendship behaves as full/capped
                        minVal = 0
                        maxVal = 1
                        currentVal = 1
                    end
                end
            end

            -- Normalize values
            local range = maxVal - minVal
            if range <= 0 then range = 1 end
            local normalizedVal = math_max(0, currentVal - minVal)
            if isParagon or isRenown then
                normalizedVal = currentVal
            end
            local percent = math_min(100, math_max(0, (normalizedVal / range) * 100))
            local remaining = math_max(0, range - normalizedVal)

            -- Color resolution
            if isRenown then
                _repColor[1], _repColor[2], _repColor[3], _repColor[4] = 0.15, 0.55, 0.95, 1.0
            elseif isParagon then
                _repColor[1], _repColor[2], _repColor[3], _repColor[4] = 0.90, 0.70, 0.15, 1.0
            elseif FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction] then
                local c = FACTION_BAR_COLORS[reaction]
                _repColor[1], _repColor[2], _repColor[3], _repColor[4] = c.r, c.g, c.b, 1.0
            else
                _repColor[1], _repColor[2], _repColor[3], _repColor[4] = 0.0, 0.60, 0.35, 1.0
            end

            _repData.hasRep = true
            _repData.factionID = factionID
            _repData.name = name
            _repData.standingText = standingText
            _repData.current = normalizedVal
            _repData.max = range
            _repData.remaining = remaining
            _repData.percent = percent
            _repData.isParagon = isParagon
            _repData.isRenown = isRenown
            _repData.isFriendship = isFriendship
            _repData.hasRewardPending = hasRewardPending
            _repData.color = _repColor

            return _repData
        end
    end

    -- 2. Classic / Forever API: GetWatchedFactionInfo()
    if GetWatchedFactionInfo then
        local name, standingID, barMin, barMax, barValue, factionID = GetWatchedFactionInfo()
        if name and barMax and barMax > barMin then
            local range = barMax - barMin
            local current = math_max(0, barValue - barMin)
            local percent = math_min(100, math_max(0, (current / range) * 100))
            local standingText = _G["FACTION_STANDING_LABEL" .. standingID] or "neutral"

            if FACTION_BAR_COLORS and FACTION_BAR_COLORS[standingID] then
                local c = FACTION_BAR_COLORS[standingID]
                _repColor[1], _repColor[2], _repColor[3], _repColor[4] = c.r, c.g, c.b, 1.0
            else
                _repColor[1], _repColor[2], _repColor[3], _repColor[4] = 0.0, 0.60, 0.35, 1.0
            end

            _repData.hasRep = true
            _repData.factionID = factionID
            _repData.name = name
            _repData.standingText = standingText
            _repData.current = current
            _repData.max = range
            _repData.remaining = math_max(0, range - current)
            _repData.percent = percent
            _repData.isParagon = false
            _repData.isRenown = false
            _repData.isFriendship = false
            _repData.hasRewardPending = false
            _repData.color = _repColor

            return _repData
        end
    end

    _repData.hasRep = false
    _repData.name = nil
    _repData.current = 0
    _repData.max = 1
    _repData.percent = 0
    _repData.remaining = 1
    return _repData
end

-- ─── Faction Lookup & Watched Faction Switching ──────────────────────────────
local factionCache = {}

--- Clear faction lookup cache
function data.ClearFactionCache()
    for k in pairs(factionCache) do
        factionCache[k] = nil
    end
end

--- Find a faction ID and index by localized or clean name
--- @param targetName string
--- @return number|nil factionID, number|nil factionIndex
function data.FindFactionByName(targetName)
    if not targetName or targetName == "" then return nil, nil end
    local cleanTarget = string_lower(targetName):gsub("^%s*[\"']*(.-)[\"']*%s*$", "%1")
    if cleanTarget == "" then return nil, nil end

    -- 1. Check cache first
    local cached = factionCache[cleanTarget]
    if cached then
        return cached.factionID, cached.index
    end

    -- 2. Modern C_Reputation API (Retail / Midnight / Camelot)
    if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
        local num = C_Reputation.GetNumFactions() or 0
        for i = 1, num do
            local fData = C_Reputation.GetFactionDataByIndex(i)
            if fData and fData.name then
                local clean = string_lower(fData.name):gsub("^%s*[\"']*(.-)[\"']*%s*$", "%1")
                factionCache[clean] = { factionID = fData.factionID, index = i }
                if clean == cleanTarget then
                    return fData.factionID, i
                end
            end
        end

        -- Check Major Factions / Renown
        if C_MajorFactions and C_MajorFactions.GetMajorFactionIDs then
            local majorIDs = C_MajorFactions.GetMajorFactionIDs()
            if majorIDs then
                for _, id in ipairs(majorIDs) do
                    local mData = C_MajorFactions.GetMajorFactionData(id)
                    if mData and mData.name then
                        local clean = string_lower(mData.name):gsub("^%s*[\"']*(.-)[\"']*%s*$", "%1")
                        factionCache[clean] = { factionID = id, index = nil }
                        if clean == cleanTarget then
                            return id, nil
                        end
                    end
                end
            end
        end
    end

    -- 3. Classic / Forever API (GetNumFactions / GetFactionInfo)
    local getNumFactions = _G.GetNumFactions
    local getFactionInfo = _G.GetFactionInfo
    if getNumFactions and getFactionInfo then
        local num = getNumFactions() or 0
        for i = 1, num do
            local name, _, _, _, _, _, _, _, _, _, _, _, _, fID = getFactionInfo(i)
            if name then
                local clean = string_lower(name):gsub("^%s*[\"']*(.-)[\"']*%s*$", "%1")
                factionCache[clean] = { factionID = fID, index = i }
                if clean == cleanTarget then
                    return fID, i
                end
            end
        end
    end

    return nil, nil
end

--- Set the watched reputation faction across modern and classic clients
--- @param factionID number|nil
--- @param factionIndex number|nil
--- @param factionName string|nil
--- @return boolean success
function data.SetWatchedFaction(factionID, factionIndex, factionName)
    local success = false

    -- Unwatch currently watched faction if 0 or nil passed
    if (not factionID or factionID == 0) and (not factionIndex or factionIndex == 0) then
        if C_Reputation and C_Reputation.SetWatchedFactionByID then
            pcall(C_Reputation.SetWatchedFactionByID, 0)
        end
        if C_Reputation and C_Reputation.SetWatchedFactionByIndex then
            pcall(C_Reputation.SetWatchedFactionByIndex, 0)
        end
        if _G.SetWatchedFactionIndex then
            pcall(_G.SetWatchedFactionIndex, 0)
        end
        return true
    end

    -- Modern Retail / Live: C_Reputation.SetWatchedFactionByID
    if C_Reputation and C_Reputation.SetWatchedFactionByID and factionID and factionID > 0 then
        local ok = pcall(C_Reputation.SetWatchedFactionByID, factionID)
        if ok then
            success = true
        end
    end

    -- Modern Camelot / Fallback: C_Reputation.SetWatchedFactionByIndex
    if not success and C_Reputation and C_Reputation.SetWatchedFactionByIndex and factionIndex and factionIndex > 0 then
        local ok = pcall(C_Reputation.SetWatchedFactionByIndex, factionIndex)
        if ok then
            success = true
        end
    end

    -- Classic / Forever: SetWatchedFactionIndex
    local setWatchedIndex = _G.SetWatchedFactionIndex
    if not success and setWatchedIndex and factionIndex and factionIndex > 0 then
        local ok = pcall(setWatchedIndex, factionIndex)
        if ok then
            success = true
        end
    end

    return success
end

--- Look up faction by name and set it as watched
--- @param factionName string
--- @return boolean success
function data.SetWatchedFactionByName(factionName)
    if not factionName or factionName == "" then return false end

    -- Check if already watched
    local curRep = data.GetReputationData()
    if curRep and curRep.hasRep and curRep.name then
        local curClean = string_lower(curRep.name):gsub("^%s*[\"']*(.-)[\"']*%s*$", "%1")
        local newClean = string_lower(factionName):gsub("^%s*[\"']*(.-)[\"']*%s*$", "%1")
        if curClean == newClean then
            return true
        end
    end

    local factionID, factionIndex = data.FindFactionByName(factionName)

    -- If not found, clear cache and re-scan once (in case faction was just discovered)
    if not factionID and not factionIndex then
        data.ClearFactionCache()
        factionID, factionIndex = data.FindFactionByName(factionName)
    end

    if factionID or factionIndex then
        return data.SetWatchedFaction(factionID, factionIndex, factionName)
    end

    return false
end


-- ─── Session Rate & Time-To-Level Analytics ───────────────────────────────────
--- Calculate current session metrics
--- @param remainingXP number
--- @return table
function data.GetSessionStats(remainingXP)
    remainingXP = remainingXP or 1
    local now = GetTime()
    local elapsed = (sessionStartTime and (now - sessionStartTime)) or 0
    if elapsed < 1 then elapsed = 1 end

    local xpHour = 0
    if sessionXP > 0 and elapsed > 0 then
        xpHour = math_floor((sessionXP / elapsed) * 3600)
    end

    local ttlSeconds = nil
    if xpHour > 0 and remainingXP > 0 then
        ttlSeconds = math_floor((remainingXP / xpHour) * 3600)
    end

    -- Average mob kill XP
    local avgKill = 0
    local killsToLevel = nil
    if #recentKillXPs > 0 then
        local sum = 0
        for _, kxp in ipairs(recentKillXPs) do
            sum = sum + kxp
        end
        avgKill = math_floor(sum / #recentKillXPs)
        if avgKill > 0 and remainingXP > 0 then
            killsToLevel = math.ceil(remainingXP / avgKill)
        end
    end

    _sessionData.sessionTime = elapsed
    _sessionData.sessionXP = sessionXP
    _sessionData.xpHour = xpHour
    _sessionData.ttlSeconds = ttlSeconds
    _sessionData.killsToLevel = killsToLevel
    _sessionData.averageKillXP = avgKill

    return _sessionData
end

-- ─── Formatting Helpers ───────────────────────────────────────────────────────
--- Format a number into compact string notation (e.g. 1.2k, 3.4m)
--- @param val number
--- @return string
function data.FormatNumber(val)
    if not val then return "0" end
    val = math_floor(val)
    if val >= 1000000 then
        return string_format("%.1fm", val / 1000000)
    elseif val >= 1000 then
        return string_format("%.1fk", val / 1000)
    else
        return tostring(val)
    end
end

--- Format a number with standard commas (e.g. 1,234,567)
--- @param val number
--- @return string
function data.FormatCommas(val)
    if not val then return "0" end
    local left, num, right = string.match(tostring(math_floor(val)), '^([^%d]*%d)(%d*)(.-)$')
    return left .. (num:reverse():gsub('(%d%d%d)', '%1,'):reverse()) .. right
end

--- Format seconds into clean human-readable duration (e.g. "1h 24m", "45m")
--- @param seconds number|nil
--- @return string
function data.FormatTime(seconds)
    if not seconds or seconds <= 0 then return "n/a" end
    local s = math_floor(seconds)
    local h = math_floor(s / 3600)
    local m = math_floor((s % 3600) / 60)
    local sec = s % 60

    if h > 0 then
        return string_format("%dh %02dm", h, m)
    elseif m > 0 then
        return string_format("%dm %02ds", m, sec)
    else
        return string_format("%ds", sec)
    end
end
