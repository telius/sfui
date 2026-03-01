local addonName, addon = ...
sfui = sfui or {}
sfui.prey = {}
sfui.prey.debug = false -- Can be toggled for chat diagnostics

local Enum = Enum
local C_QuestLog = C_QuestLog
local C_TaskQuest = C_TaskQuest
local C_UIWidgetManager = C_UIWidgetManager
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local UIParent = UIParent
local GetTime = GetTime
local ipairs = ipairs
local lower = string.lower
local find = string.find
local match = string.match
local type = type
local tonumber = tonumber
local C_Timer = _G.C_Timer

-- Localized APIs for optimization
local GetActivePreyQuest = C_QuestLog.GetActivePreyQuest
local GetTitleForQuestID = C_QuestLog.GetTitleForQuestID
local GetQuestObjectives = C_QuestLog.GetQuestObjectives
local IsOnMap = C_QuestLog.IsOnMap
local issecretvalue = sfui.common.issecretvalue
local GetPreyHuntProgressWidgetVisualizationInfo = C_UIWidgetManager.GetPreyHuntProgressWidgetVisualizationInfo
local GetStatusBarWidgetVisualizationInfo = C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo
local GetQuestProgressBarInfo = C_TaskQuest.GetQuestProgressBarInfo

-- Helper to handle Blizzard's custom |n newlines and standard \n
local function CropToFirstLine(text)
    if not text or text == "" then return "" end
    local s = text:gsub("|n", "\n")
    s = s:match("([^\n]+)") or s
    -- User request: crop final confrontation text to "Ready."
    if lower(s):find("confrontation") then
        return "Ready."
    end
    return s
end

-- Map progress states to colors
local stateColors = {
    [0] = { 0.2, 0.2, 0.2 }, -- Cold
    [1] = { 0, 0.5, 0.5 },   -- Warm
    [2] = { 1, 0, 0.4 },     -- Hot
    [3] = { 1, 0, 1 },       -- Final
}

-- Cache for widget data to avoid iteration
local widgetCache = {
    title = nil,
    color = nil,
    progress = nil,
    progressState = nil,
    -- Gating variables
    lastTitle = nil,
    lastProgress = nil,
    lastColor = nil,
    lastQuestID = nil,
    lastObjectives = nil, -- Throttled scanning
}

local function CreatePreyBar()
    local cfg = sfui.config.preyBar
    local bar = sfui.common.create_bar("preyBar", "StatusBar", UIParent)

    bar.Text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.Text:SetPoint("CENTER", 0, 0)

    local textureName = SfuiDB.barTexture
    local LSM = LibStub("LibSharedMedia-3.0", true)
    local texturePath
    if LSM then
        texturePath = LSM:Fetch("statusbar", textureName)
    end
    if not texturePath or texturePath == "" then
        texturePath = sfui.config.barTexture
    end
    bar:SetStatusBarTexture(texturePath)

    bar.backdrop:ClearAllPoints()
    bar.backdrop:SetPoint("TOP", UIParent, "TOP", 0, -2) -- Enforce exact positioning
    bar.backdrop:Hide()

    return bar
end

function sfui.prey.UpdatePreyBar(bar)
    if not bar then return end
    if InCombatLockdown() then return end

    local cfg = sfui.config.preyBar
    if not cfg.enabled then
        bar.backdrop:Hide()
        return
    end

    local questID = GetActivePreyQuest()
    if not questID and not sfui.prey.preview then
        bar.backdrop:Hide()
        return
    end

    -- Zone Check (Pure API Only)
    if questID and not sfui.prey.preview then
        if not IsOnMap(questID) then
            bar.backdrop:Hide()
            return
        end
    end

    -- Calculate Progress
    local progress = 0

    -- Priority 1: Use the discrete state from the Prey widget (Type 31/84)
    if widgetCache.progressState then
        -- Map 4 states to "combo points" (25, 50, 75, 100)
        progress = (widgetCache.progressState + 1) * 25
    end

    -- Priority 2: Use cached numerical progress (Type 2/StatusBar)
    if (widgetCache.progress or 0) > progress then
        progress = widgetCache.progress
    end

    -- Priority 3: Quest API (ProgressBar)
    if progress == 0 and questID then
        progress = GetQuestProgressBarInfo(questID) or 0
    end

    -- Title Priority
    local title = widgetCache.title or ""
    if questID and (title == "" or title:find("^Prey:")) then
        local qTitle = GetTitleForQuestID(questID)
        if qTitle and qTitle ~= "" then title = qTitle end
    end

    -- Priority 4: Quest Objectives (The "API-Only" Secret Sauce)
    -- This handles the login/reload case where widgets haven't fired yet
    if questID and progress < 75 then
        -- Throttle: Only call GetQuestObjectives if quest ID changed or we have no objectives cached
        local objectives = (widgetCache.lastQuestID == questID and widgetCache.lastObjectives) or
            GetQuestObjectives(questID)
        widgetCache.lastObjectives = objectives
        widgetCache.lastQuestID = questID

        if objectives then
            for i, obj in ipairs(objectives) do
                local text = CropToFirstLine(obj.text)
                local lowerText = lower(text)
                if find(lowerText, "confrontation") then
                    progress = 100
                    title = text
                    break
                elseif find(lowerText, "revealed") then
                    progress = 75
                    title = text
                    break
                end
            end
        end
    end

    -- Fallback for Preview
    if progress == 0 and sfui.prey.preview then
        progress = 75
        title = "Your prey is nearly revealed (Preview)"
    end

    -- Set Color
    local color = widgetCache.color
    if not color then
        local stateIndex = 0
        if progress >= 100 then
            stateIndex = 3
        elseif progress >= 75 then
            stateIndex = 2
        elseif progress >= 50 then
            stateIndex = 1
        end
        color = stateColors[stateIndex]
    end

    -- Finalize values for gating
    local titleFirstLine = CropToFirstLine(title)

    -- Visibility Gating (User Request: show regardless of % when in zone)
    if titleFirstLine == "" and not sfui.prey.preview then
        bar.backdrop:Hide()
        widgetCache.lastTitle = nil
        widgetCache.lastProgress = nil
        return
    end

    -- Gating: Skip UI updates if values haven't changed
    if titleFirstLine == widgetCache.lastTitle and
        progress == widgetCache.lastProgress and
        color == widgetCache.lastColor then
        -- Ensure it's shown if we're not hidden
        bar.backdrop:Show()
        return
    end

    -- Cache for next update
    widgetCache.lastTitle = titleFirstLine
    widgetCache.lastProgress = progress
    widgetCache.lastColor = color

    -- Apply UI Updates
    bar.backdrop:Show()
    bar.backdrop:ClearAllPoints()
    bar.backdrop:SetPoint("TOP", UIParent, "TOP", 0, -2)
    bar.backdrop:SetAlpha(1)

    bar:SetMinMaxValues(0, 100)
    bar:SetValue(progress)
    bar.Text:SetText(titleFirstLine)
    bar:SetStatusBarColor(color[1], color[2], color[3], 1)

    if sfui.prey.debug then
        print("|cff00ffff[SFUI Prey Debug]|r UpdatePreyBar Detail:")
        print("  - QuestID:", questID or "nil")
        print("  - Title:", title)
        print("  - Progress State:", widgetCache.progressState or "nil")
        print("  - Final Progress:", progress)
    end
end

function sfui.prey.HandleWidget(widgetID)
    if not widgetID then return end

    pcall(function()
        local widgetInfo = GetPreyHuntProgressWidgetVisualizationInfo(widgetID)
        if widgetInfo then
            -- Update color state
            widgetCache.color = stateColors[widgetInfo.progressState]
            -- Store the discrete state (0-3)
            widgetCache.progressState = widgetInfo.progressState

            -- Capture title/tooltip if present
            local text = widgetInfo.tooltip or widgetInfo.text or widgetInfo.title
            if text and text ~= "" and not issecretvalue(text) then
                widgetCache.title = CropToFirstLine(text)
            end
            -- Capture progress if present
            widgetCache.progress = widgetInfo.barValue or widgetInfo.fillValue or widgetInfo.curValue
        else
            local barInfo = GetStatusBarWidgetVisualizationInfo(widgetID)
            if barInfo then
                local text = barInfo.tooltip or barInfo.text or ""
                -- Broaden search to support "Mordril Shadowfell" etc if we have an active hunt
                local hasHunt = GetActivePreyQuest() ~= nil
                if text and text ~= "" and not issecretvalue(text) then
                    local lowerText = lower(text)
                    if find(lowerText, "prey") or find(lowerText, "revealed") or (hasHunt) then
                        widgetCache.title = CropToFirstLine(text)
                        widgetCache.progress = barInfo.barValue or barInfo.curValue
                    end
                end
            end
        end
    end)
end

local event_frame = CreateFrame("Frame")
event_frame:RegisterEvent("PLAYER_ENTERING_WORLD")
event_frame:RegisterEvent("ZONE_CHANGED")
event_frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
event_frame:RegisterEvent("QUEST_ACCEPTED")
event_frame:RegisterEvent("QUEST_REMOVED")
event_frame:RegisterEvent("QUEST_LOG_UPDATE")
local lastQuestUpdate = 0
-- The magic event for API-only low CPU tracking
event_frame:RegisterEvent("UPDATE_UI_WIDGET")

local preyBar = nil

event_frame:SetScript("OnEvent", function(self, event, payload)
    if InCombatLockdown() then return end

    if event == "UPDATE_UI_WIDGET" and payload then
        local widgetID = payload.widgetID
        if not widgetID or issecretvalue(widgetID) then return end

        local widgetType = payload.widgetType
        local widgetSetID = payload.widgetSetID

        -- Explicitly ignore Warband world quests (1900) and other known protected sets
        if widgetSetID == 1900 or widgetSetID == 1611 then return end

        -- Only process types used by Prey hunts (31: PreyHunt, 2: StatusBar)
        if widgetType == 31 then
            sfui.prey.HandleWidget(widgetID)
            if preyBar then
                sfui.prey.UpdatePreyBar(preyBar)
            end
        elseif widgetType == 2 then
            local barInfo = GetStatusBarWidgetVisualizationInfo(widgetID)
            if barInfo then
                local text = barInfo.tooltip or barInfo.text or ""
                local lowerText = lower(text)
                if find(lowerText, "prey") or find(lowerText, "revealed") then
                    sfui.prey.HandleWidget(widgetID)
                    if preyBar then
                        sfui.prey.UpdatePreyBar(preyBar)
                    end
                end
            end
        end
    end

    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" then
        if not preyBar then
            preyBar = CreatePreyBar()
            sfui.prey.bar = preyBar
        end
        -- Reset and Update
        widgetCache.title = nil
        widgetCache.color = nil
        widgetCache.progress = nil
        widgetCache.progressState = nil
        widgetCache.lastTitle = nil
        widgetCache.lastProgress = nil
        widgetCache.lastColor = nil
        widgetCache.lastObjectives = nil

        sfui.prey.UpdatePreyBar(preyBar)
    elseif event == "QUEST_LOG_UPDATE" then
        -- Salt the objectives cache on Quest Log Update
        widgetCache.lastObjectives = nil
        if preyBar then sfui.prey.UpdatePreyBar(preyBar) end
    elseif preyBar then
        sfui.prey.UpdatePreyBar(preyBar)
    end
end)

function sfui.prey.initialize()
    if not preyBar then
        preyBar = CreatePreyBar()
        sfui.prey.bar = preyBar
    end

    -- Initial Update
    sfui.prey.UpdatePreyBar(preyBar)

    -- Small delay to catch lazy-loading quest data
    C_Timer.After(1, function()
        if preyBar then sfui.prey.UpdatePreyBar(preyBar) end
    end)
end
