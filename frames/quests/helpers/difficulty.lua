--[[
    SFUI Tracker Helper: Difficulty
    frames/quests/helpers/difficulty.lua

    Consolidates level difficulty coloring, bracket formatting ([14], [18D], [60R]),
    and player-relative content difficulty calculations across Retail and Camelot/Classic.
]]

local addonName, addon = ...
sfui = sfui or {}
sfui.tracker = sfui.tracker or {}
sfui.tracker.helpers = sfui.tracker.helpers or {}

local Difficulty = {}
sfui.tracker.helpers.difficulty = Difficulty

-- Backward compatibility aliases
sfui.questlog = sfui.questlog or {}
sfui.questlog.difficulty = Difficulty

local _G = _G
local UnitLevel = _G.UnitLevel
local UnitEffectiveLevel = _G.UnitEffectiveLevel or _G.UnitLevel
local C_QuestLog = _G.C_QuestLog
local C_PlayerInfo = _G.C_PlayerInfo
local GetDifficultyColor = _G.GetDifficultyColor
local DifficultyUtil = _G.DifficultyUtil
local Enum = _G.Enum
local string_format = string.format
local math_floor = math.floor

-- ─────────────────────────────────────────────────────────
--  DIFFICULTY COLOR RESOLVER
-- ─────────────────────────────────────────────────────────
function Difficulty.GetDifficultyColorCode(questLevel, questID)
    -- 1. Modern content difficulty resolution (Retail & modern client branches)
    if questID and questID > 0 and C_PlayerInfo and C_PlayerInfo.GetContentDifficultyQuestForPlayer and GetDifficultyColor then
        local diff = C_PlayerInfo.GetContentDifficultyQuestForPlayer(questID)
        if diff then
            local c = GetDifficultyColor(diff)
            if c and c.r and c.g and c.b then
                return string_format("|cff%02x%02x%02x", math_floor(c.r * 255 + 0.5), math_floor(c.g * 255 + 0.5), math_floor(c.b * 255 + 0.5))
            end
        end
    end

    local playerLevel = UnitEffectiveLevel("player") or UnitLevel("player") or 1

    -- 2. DifficultyUtil relative calculation
    if DifficultyUtil and DifficultyUtil.GetRelativeDifficultyColor and questLevel and questLevel > 0 then
        local c = DifficultyUtil.GetRelativeDifficultyColor(playerLevel, questLevel)
        if c and c.r and c.g and c.b then
            return string_format("|cff%02x%02x%02x", math_floor(c.r * 255 + 0.5), math_floor(c.g * 255 + 0.5), math_floor(c.b * 255 + 0.5))
        end
    end

    -- 3. Fallback level bracket delta
    if questLevel and questLevel > 0 then
        local levelDiff = questLevel - playerLevel
        if levelDiff >= 5 then
            return "|cffff2020" -- Red (impossible / very high)
        elseif levelDiff >= 3 then
            return "|cffff8020" -- Orange (very difficult)
        elseif levelDiff >= -2 then
            return "|cffffff20" -- Yellow (normal / fair)
        elseif levelDiff >= -6 then
            return "|cff40c040" -- Green (easy)
        else
            return "|cff808080" -- Gray (trivial, no XP)
        end
    end

    return "|cffffffff"
end

-- ─────────────────────────────────────────────────────────
--  LEVEL BRACKET FORMATTER: [14], [18D], [60R], [20+]
-- ─────────────────────────────────────────────────────────
function Difficulty.FormatTitle(entry, rawTitle)
    if not entry then return rawTitle end

    local qLevel = entry.level
    if (not qLevel or qLevel <= 0) and entry.questID and C_QuestLog and C_QuestLog.GetQuestDifficultyLevel then
        qLevel = C_QuestLog.GetQuestDifficultyLevel(entry.questID)
    end
    if not qLevel or qLevel <= 0 then
        return rawTitle
    end

    -- Determine Type Tag: + (Elite), D (Dungeon), R (Raid), G# (Group), H (Heroic)
    local tag = ""
    local sGroup = entry.suggestedGroup
    if (not sGroup or sGroup <= 1) and entry.questLogIndex and C_QuestLog and C_QuestLog.GetInfo then
        local qInfo = C_QuestLog.GetInfo(entry.questLogIndex)
        if qInfo then sGroup = qInfo.suggestedGroup end
    end

    if sGroup and sGroup > 1 then
        tag = "G" .. sGroup
    elseif entry.isDungeon or entry.questTag == "Dungeon" then
        tag = "D"
    elseif entry.isRaid or entry.questTag == "Raid" then
        tag = "R"
    elseif entry.isElite or entry.questTag == "Elite" then
        tag = "+"
    elseif entry.questID and C_QuestLog and C_QuestLog.GetQuestTagInfo then
        local tagInfo = C_QuestLog.GetQuestTagInfo(entry.questID)
        if tagInfo then
            local tID = tagInfo.tagID
            local eq = Enum and Enum.QuestTag
            if eq and (tID == eq.Dungeon) then
                tag = "D"
            elseif eq and (tID == eq.Raid or tID == eq.Raid10 or tID == eq.Raid25) then
                tag = "R"
            elseif eq and (tID == eq.Heroic) then
                tag = "H"
            elseif eq and (tID == eq.Delve) then
                tag = "Delve"
            elseif eq and (tID == eq.PvP) then
                tag = "PvP"
            elseif eq and (tID == eq.Group) then
                tag = (sGroup and sGroup > 1) and ("G" .. sGroup) or "+"
            end
        end
    end

    local diffColor = Difficulty.GetDifficultyColorCode(qLevel, entry.questID)
    local bracket = string_format("%s[%d%s]|r", diffColor, qLevel, tag)
    return bracket .. " " .. rawTitle
end

return Difficulty
