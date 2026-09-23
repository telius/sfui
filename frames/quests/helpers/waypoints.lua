--[[
    SFUI Tracker Helper: Waypoints & Turn-In Text Engine
    frames/quests/helpers/waypoints.lua

    Modular helper for waypoint directions, turn-in descriptions,
    and quest money requirements.
    Handles:
      - C_QuestLog.GetNextWaypointText for supertracked/focused quests
      - GetQuestLogCompletionText for rich NPC turn-in instructions
      - Required money calculation and formatting
]]

local addonName, addon = ...
sfui = sfui or {}
sfui.tracker = sfui.tracker or {}
sfui.tracker.helpers = sfui.tracker.helpers or {}

local Waypoints = {}
sfui.tracker.helpers.waypoints = Waypoints

-- Backward compatibility aliases
sfui.questlog = sfui.questlog or {}
sfui.questlog.waypoints = Waypoints

local _G = _G
local C_QuestLog = _G.C_QuestLog
local C_SuperTrack = _G.C_SuperTrack
local GetQuestLogCompletionText = _G.GetQuestLogCompletionText
local GetMoney = _G.GetMoney
local GetMoneyString = _G.GetMoneyString
local QuestMapFrame_GetFocusedQuestID = _G.QuestMapFrame_GetFocusedQuestID

local WAYPOINT_OBJECTIVE_FORMAT_OPTIONAL = _G.WAYPOINT_OBJECTIVE_FORMAT_OPTIONAL or "Go to %s"
local QUEST_WATCH_QUEST_READY           = _G.QUEST_WATCH_QUEST_READY or "Ready for turn-in"
local QUEST_WATCH_QUEST_COMPLETE        = _G.QUEST_WATCH_QUEST_COMPLETE or "Quest Complete"

local issecretvalue = (sfui.common and sfui.common.issecretvalue) or _G.issecretvalue or function() return false end

-- ─────────────────────────────────────────────────────────
--  WAYPOINT NAVIGATION TEXT
-- ─────────────────────────────────────────────────────────
function Waypoints.GetWaypointText(questID, isSuperTracked)
    if not questID or not C_QuestLog or not C_QuestLog.GetNextWaypointText then
        return nil
    end

    local shouldShow = isSuperTracked
    if not shouldShow and C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
        shouldShow = (C_SuperTrack.GetSuperTrackedQuestID() == questID)
    end
    if not shouldShow and QuestMapFrame_GetFocusedQuestID then
        shouldShow = (QuestMapFrame_GetFocusedQuestID() == questID)
    end

    if not shouldShow then
        return nil
    end

    local wpText = C_QuestLog.GetNextWaypointText(questID)
    if wpText and wpText ~= "" and not issecretvalue(wpText) then
        return string.format(WAYPOINT_OBJECTIVE_FORMAT_OPTIONAL, wpText)
    end

    return nil
end

-- ─────────────────────────────────────────────────────────
--  COMPLETION / TURN-IN TEXT
-- ─────────────────────────────────────────────────────────
function Waypoints.GetCompletionText(questLogIndex, isAutoComplete)
    if isAutoComplete then
        return QUEST_WATCH_QUEST_COMPLETE
    end

    if questLogIndex and GetQuestLogCompletionText then
        local compText = GetQuestLogCompletionText(questLogIndex)
        if compText and compText ~= "" and not issecretvalue(compText) then
            return compText
        end
    end

    return QUEST_WATCH_QUEST_READY
end

-- ─────────────────────────────────────────────────────────
--  REQUIRED MONEY OBJECTIVE
-- ─────────────────────────────────────────────────────────
function Waypoints.GetRequiredMoneyText(requiredMoney)
    if not requiredMoney or requiredMoney <= 0 or not GetMoney then
        return nil
    end

    local playerMoney = GetMoney() or 0
    if requiredMoney > playerMoney then
        local currentStr = (GetMoneyString and GetMoneyString(playerMoney)) or tostring(playerMoney)
        local reqStr     = (GetMoneyString and GetMoneyString(requiredMoney)) or tostring(requiredMoney)
        return currentStr .. " / " .. reqStr
    end

    return nil
end

return Waypoints
