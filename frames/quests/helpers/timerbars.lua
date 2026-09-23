--[[
    SFUI Tracker Helper: Timer Bars
    frames/quests/helpers/timerbars.lua

    Modular quest and event countdown timer bar controller.
    Handles:
      - C_QuestLog.GetTimeAllowed inspection
      - Camelot rule compliance (timer bars suppressed on WoW: Forever)
      - Throttled OnUpdate via sfui.events.RegisterUpdate (4Hz / 0.25s)
      - Dynamic visual styling and time countdown formatting
]]

local addonName, addon = ...
sfui = sfui or {}
sfui.tracker = sfui.tracker or {}
sfui.tracker.helpers = sfui.tracker.helpers or {}

local TimerBars = {}
sfui.tracker.helpers.timerbars = TimerBars

-- Backward compatibility aliases
sfui.questlog = sfui.questlog or {}
sfui.questlog.timerbars = TimerBars

local _G = _G
local C_QuestLog = _G.C_QuestLog
local GetTime = _G.GetTime
local SecondsToClock = _G.SecondsToClock or function(s)
    s = math.max(0, math.floor(s))
    local m = math.floor(s / 60)
    local sec = s % 60
    return string.format("%d:%02d", m, sec)
end
local pairs, next, math_max = _G.pairs, _G.next, math.max

local activeTimerBars = {}
local isTimerWatcherActive = false

-- ─────────────────────────────────────────────────────────
--  CAMELOT / CLIENT RULES
-- ─────────────────────────────────────────────────────────
function TimerBars.CanShowTimerBar()
    -- Blizzard explicitly disables timer bars on Camelot (WoW: Forever)
    -- via Camelot/Blizzard_QuestObjectiveTrackerOverride.lua:
    --   function QuestObjectiveTrackerMixin:CanShowTimerBar() return false; end
    if sfui.isForever or (sfui.compat and sfui.compat.is_wow_forever) then
        return false
    end
    return true
end

-- ─────────────────────────────────────────────────────────
--  TIME QUERY
-- ─────────────────────────────────────────────────────────
function TimerBars.GetQuestTimeAllowed(questID)
    if not questID or not TimerBars.CanShowTimerBar() then return nil end
    if not C_QuestLog or not C_QuestLog.GetTimeAllowed then return nil end

    local timeTotal, timeElapsed = C_QuestLog.GetTimeAllowed(questID)
    if timeTotal and timeElapsed and timeTotal > 0 and timeElapsed < timeTotal then
        return timeTotal, timeElapsed
    end
    return nil
end

-- ─────────────────────────────────────────────────────────
--  THROTTLED UPDATE LOOP (4Hz / 0.25s)
-- ─────────────────────────────────────────────────────────
local function OnTimerBarsUpdate()
    if not next(activeTimerBars) then
        if isTimerWatcherActive then
            sfui.events.UnregisterUpdate("QuestTimerBars")
            isTimerWatcherActive = false
        end
        return
    end

    local now = GetTime()
    for bar in pairs(activeTimerBars) do
        if not bar:IsShown() or not bar.timeTotal or not bar.startTime then
            activeTimerBars[bar] = nil
        else
            local elapsed = now - bar.startTime
            local remaining = math_max(0, bar.timeTotal - elapsed)
            bar:SetValue(remaining)

            local timeStr = SecondsToClock(remaining)
            if bar.TimeFS then
                bar.TimeFS:SetText(timeStr)
            end

            -- Color transition: white/cyan -> yellow -> red when low (<25%)
            local pct = (bar.timeTotal > 0) and (remaining / bar.timeTotal) or 0
            if pct <= 0.20 then
                bar:SetStatusBarColor(1.0, 0.25, 0.25, 0.85)
                if bar.TimeFS then bar.TimeFS:SetTextColor(1.0, 0.3, 0.3, 1) end
            elseif pct <= 0.40 then
                bar:SetStatusBarColor(1.0, 0.75, 0.20, 0.85)
                if bar.TimeFS then bar.TimeFS:SetTextColor(1.0, 0.8, 0.2, 1) end
            else
                bar:SetStatusBarColor(0.20, 0.80, 1.00, 0.80)
                if bar.TimeFS then bar.TimeFS:SetTextColor(0.85, 0.85, 0.85, 1) end
            end

            if remaining <= 0 and not bar.hasExpired then
                bar.hasExpired = true
                if sfui.tracker and sfui.tracker.RequestRefresh then
                    sfui.tracker.RequestRefresh()
                elseif sfui.questlog and sfui.questlog.Refresh and sfui.questlog.Refresh.Request then
                    sfui.questlog.Refresh:Request()
                end
            end
        end
    end
end

local function StartTimerWatcher()
    if not isTimerWatcherActive then
        sfui.events.RegisterUpdate("QuestTimerBars", 0.25, OnTimerBarsUpdate)
        isTimerWatcherActive = true
    end
end

-- ─────────────────────────────────────────────────────────
--  TIMER BAR FACTORY
-- ─────────────────────────────────────────────────────────
function TimerBars.CreateTimerBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(4)

    local statusTex = (sfui.widgets and sfui.widgets.get_bar_texture and sfui.widgets.get_bar_texture())
        or (sfui.config and sfui.config.barTexture)
        or "Interface/Buttons/WHITE8X8"
    bar:SetStatusBarTexture(statusTex)
    bar:SetStatusBarColor(0.20, 0.80, 1.00, 0.80)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.06, 0.06, 0.80)
    bar.BG = bg

    if sfui.common and sfui.common.create_border then
        sfui.common.create_border(bar, 1, { 0, 0, 0, 1 })
    end

    local fs = bar:CreateFontString(nil, "OVERLAY")
    local fontPath = (sfui.config and sfui.config.fontFile)
        or (_G.STANDARD_TEXT_FONT and _G.STANDARD_TEXT_FONT ~= "" and _G.STANDARD_TEXT_FONT)
        or (_G.GameFontNormal and _G.GameFontNormal.GetFont and _G.GameFontNormal:GetFont())
        or "Fonts\\FRIZQT__.TTF"
    fs:SetFont(fontPath, 9, "")
    fs:SetShadowOffset(0, 0)
    fs:SetShadowColor(0, 0, 0, 0)
    fs:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
    fs:SetTextColor(0.85, 0.85, 0.85, 1)
    bar.TimeFS = fs

    bar:EnableMouseWheel(true)
    bar:SetScript("OnMouseWheel", function(self, delta)
        if sfui.tracker and sfui.tracker.OnMouseWheel then
            sfui.tracker.OnMouseWheel(self, delta)
        end
    end)

    bar:Hide()
    return bar
end

-- ─────────────────────────────────────────────────────────
--  SETUP & RELEASE
-- ─────────────────────────────────────────────────────────
function TimerBars.SetupTimerBar(bar, timeTotal, timeElapsed)
    if not bar or not timeTotal or timeTotal <= 0 then return end

    local statusTex = (sfui.widgets and sfui.widgets.get_bar_texture and sfui.widgets.get_bar_texture())
        or (sfui.config and sfui.config.barTexture)
        or "Interface/Buttons/WHITE8X8"
    bar:SetStatusBarTexture(statusTex)

    local now = GetTime()
    bar.timeTotal = timeTotal
    bar.startTime = now - (timeElapsed or 0)
    bar.hasExpired = false

    bar:SetMinMaxValues(0, timeTotal)
    local remaining = math_max(0, timeTotal - (timeElapsed or 0))
    bar:SetValue(remaining)

    if bar.TimeFS then
        bar.TimeFS:SetShadowOffset(0, 0)
        bar.TimeFS:SetShadowColor(0, 0, 0, 0)
        bar.TimeFS:SetText(SecondsToClock(remaining))
    end

    bar:Show()
    activeTimerBars[bar] = true
    StartTimerWatcher()
end

function TimerBars.ReleaseTimerBar(bar)
    if not bar then return end
    activeTimerBars[bar] = nil
    bar.timeTotal = nil
    bar.startTime = nil
    bar.hasExpired = nil
    bar:Hide()

    if not next(activeTimerBars) and isTimerWatcherActive then
        sfui.events.UnregisterUpdate("QuestTimerBars")
        isTimerWatcherActive = false
    end
end

function TimerBars.GetPoolStats()
    local act = 0
    for bar in pairs(activeTimerBars) do
        if bar and bar:IsShown() then
            act = act + 1
        end
    end
    return {
        activeBars      = act,
        isWatcherActive = isTimerWatcherActive,
    }
end

return TimerBars
