--[[
    SFUI Tracker Module: Tracked Achievements
    frames/quests/modules/achievements.lua

    Pluggable tracker module for player, account, and guild tracked achievements and criteria.
    Supports modern Retail (C_ContentTracking) and Classic/Camelot (GetTrackedAchievements).
]]

local addonName, addon = ...
sfui = sfui or {}
sfui.tracker = sfui.tracker or {}
sfui.questlog = sfui.questlog or {}

local _G = _G
local GetTrackedAchievements = _G.GetTrackedAchievements
local GetAchievementInfo = _G.GetAchievementInfo
local GetAchievementNumCriteria = _G.GetAchievementNumCriteria
local GetAchievementCriteriaInfo = _G.GetAchievementCriteriaInfo
local RemoveTrackedAchievement = _G.RemoveTrackedAchievement
local AddTrackedAchievement = _G.AddTrackedAchievement
local ShowAchievementFrameForAchievement = _G.ShowAchievementFrameForAchievement
local C_ContentTracking = _G.C_ContentTracking
local C_SuperTrack = _G.C_SuperTrack
local Enum = _G.Enum
local IsShiftKeyDown = _G.IsShiftKeyDown
local ChatEdit_GetActiveWindow = _G.ChatEdit_GetActiveWindow
local ChatEdit_InsertLink = _G.ChatEdit_InsertLink
local GetAchievementLink = _G.GetAchievementLink
local hooksecurefunc = _G.hooksecurefunc

local ipairs, pairs, type, tonumber, tostring = _G.ipairs, _G.pairs, _G.type, _G.tonumber, _G.tostring
local bit_band = _G.bit and _G.bit.band or function(a, b) return 0 end
local math_floor = math.floor
local table_insert = _G.table.insert
local string_format = string.format

local issecretvalue = (sfui.common and sfui.common.issecretvalue) or _G.issecretvalue or function() return false end

-- Evaluation flag for achievement criteria progress bar (0x1)
local EVAL_FLAG_PROGRESS_BAR = 1
local CRITERIA_TYPE_ACHIEVEMENT = 8

local function GetAchievementTrackingType()
    if Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Achievement then
        return Enum.ContentTrackingType.Achievement
    end
    return 2 -- ContentTrackingType.Achievement
end

local function GetManualStopType()
    if Enum and Enum.ContentTrackingStopType and Enum.ContentTrackingStopType.Manual then
        return Enum.ContentTrackingStopType.Manual
    end
    return 2 -- ContentTrackingStopType.Manual
end

local function GetQLState()
    if not SfuiDB then SfuiDB = {} end
    if not SfuiDB.questlog then
        SfuiDB.questlog = {
            collapsed      = {},
            expandedQuests = {},
            hiddenQuests   = {},
            hidden         = false,
        }
    end
    return SfuiDB.questlog
end

local AchievementsModule = {
    id            = "achievements",
    priority      = 40,
    timedCriteria = {},
    events        = {
        "CONTENT_TRACKING_UPDATE",
        "CONTENT_TRACKING_LIST_UPDATE",
        "TRACKED_ACHIEVEMENT_LIST_CHANGED",
        "TRACKED_ACHIEVEMENT_UPDATE",
        "ACHIEVEMENT_EARNED",
        "ACHIEVEMENT_SEARCH_UPDATED",
        "PLAYER_ENTERING_WORLD",
    },
}

function AchievementsModule:Init(engine)
    self.engine = engine
    self:SetupHooks()
end

function AchievementsModule:IsEnabled()
    return (GetTrackedAchievements ~= nil or C_ContentTracking ~= nil)
end

function AchievementsModule:OnEvent(event, ...)
    if event == "CONTENT_TRACKING_UPDATE" then
        local trackableType, id, added = ...
        if not trackableType or trackableType == GetAchievementTrackingType() then
            self:MarkDirty()
            if sfui.tracker and sfui.tracker.RequestRefresh then
                sfui.tracker.RequestRefresh(0.01)
            end
        end
    elseif event == "TRACKED_ACHIEVEMENT_UPDATE" then
        local achievementID, criteriaID, elapsed, duration = ...
        if achievementID and elapsed and duration and GetAchievementNumCriteria then
            local numCriteria = GetAchievementNumCriteria(achievementID) or 0
            if numCriteria == 0 then
                self.timedCriteria = self.timedCriteria or {}
                self.timedCriteria[achievementID] = {
                    startTime = (_G.GetTime and _G.GetTime() or 0) - elapsed,
                    duration  = duration,
                }
            end
        end
        self:MarkDirty()
        if sfui.tracker and sfui.tracker.RequestRefresh then
            sfui.tracker.RequestRefresh(0.05)
        end
    else
        self:MarkDirty()
        if sfui.tracker and sfui.tracker.RequestRefresh then
            sfui.tracker.RequestRefresh(0.05)
        end
    end
end

function AchievementsModule:SetupHooks()
    if self.hooksInstalled then return end
    self.hooksInstalled = true

    -- Hook modern Retail Content Tracking
    if C_ContentTracking and C_ContentTracking.StartTracking then
        hooksecurefunc(C_ContentTracking, "StartTracking", function(trackableType, id)
            if not trackableType or trackableType == GetAchievementTrackingType() then
                self:MarkDirty()
                if sfui.tracker and sfui.tracker.RequestRefresh then
                    sfui.tracker.RequestRefresh(0.01)
                end
            end
        end)
    end

    if C_ContentTracking and C_ContentTracking.StopTracking then
        hooksecurefunc(C_ContentTracking, "StopTracking", function(trackableType, id)
            if not trackableType or trackableType == GetAchievementTrackingType() then
                self:MarkDirty()
                if sfui.tracker and sfui.tracker.RequestRefresh then
                    sfui.tracker.RequestRefresh(0.01)
                end
            end
        end)
    end

    -- Hook legacy tracking APIs
    if AddTrackedAchievement then
        hooksecurefunc("AddTrackedAchievement", function()
            self:MarkDirty()
            if sfui.tracker and sfui.tracker.RequestRefresh then
                sfui.tracker.RequestRefresh(0.01)
            end
        end)
    end

    if RemoveTrackedAchievement then
        hooksecurefunc("RemoveTrackedAchievement", function()
            self:MarkDirty()
            if sfui.tracker and sfui.tracker.RequestRefresh then
                sfui.tracker.RequestRefresh(0.01)
            end
        end)
    end
end

local function UntrackAchievement(achID)
    if not achID or achID <= 0 then return end

    if C_ContentTracking and C_ContentTracking.StopTracking then
        C_ContentTracking.StopTracking(GetAchievementTrackingType(), achID, GetManualStopType())
    end

    if RemoveTrackedAchievement then
        RemoveTrackedAchievement(achID)
    end

    if _G.AchievementFrameAchievements_ForceUpdate then
        _G.AchievementFrameAchievements_ForceUpdate()
    end

    if sfui.tracker and sfui.tracker.RequestRefresh then
        sfui.tracker.RequestRefresh(0.01)
    end
end

local function OpenAchievementInUI(achID)
    if not achID or achID <= 0 then return end

    if not _G.AchievementFrame and _G.AchievementFrame_LoadUI then
        _G.AchievementFrame_LoadUI()
    end

    if _G.ShowAchievementFrameForAchievement then
        _G.ShowAchievementFrameForAchievement(achID)
    elseif _G.AchievementFrame_SelectAchievement then
        if _G.AchievementFrame and not _G.AchievementFrame:IsShown() and _G.AchievementFrame_ToggleAchievementFrame then
            _G.AchievementFrame_ToggleAchievementFrame()
        end
        _G.AchievementFrame_SelectAchievement(achID)
    end
end

function AchievementsModule:BuildBlocks(container)
    -- Install hooks on first run if not already set
    self:SetupHooks()

    local trackedIDs = {}
    local seen = {}

    local function addID(id)
        if type(id) == "number" and id > 0 and not seen[id] then
            seen[id] = true
            table_insert(trackedIDs, id)
        end
    end

    -- 1. Modern Retail Content Tracking
    if C_ContentTracking and C_ContentTracking.GetTrackedIDs then
        local ids = C_ContentTracking.GetTrackedIDs(GetAchievementTrackingType())
        if ids and type(ids) == "table" then
            for _, id in ipairs(ids) do
                addID(id)
            end
        end
    end

    -- 2. Classic / Fallback Tracked Achievements
    if GetTrackedAchievements then
        local ids = { GetTrackedAchievements() }
        for _, id in ipairs(ids) do
            addID(id)
        end
    end

    if #trackedIDs == 0 then return nil end

    local blocks = {}
    local state = GetQLState()
    local expandedQuests = state.expandedQuests or {}

    local superTrackedType, superTrackedID = nil, nil
    if C_SuperTrack and C_SuperTrack.GetSuperTrackedContent then
        superTrackedType, superTrackedID = C_SuperTrack.GetSuperTrackedContent()
    end

    for _, achID in ipairs(trackedIDs) do
        local id, name, points, completed, month, day, year, description, flags, icon, rewardText, isGuild, wasEarnedByMe = nil
        if GetAchievementInfo then
            id, name, points, completed, month, day, year, description, flags, icon, rewardText, isGuild, wasEarnedByMe = GetAchievementInfo(achID)
        end

        -- Check filters: Only hide if completed by the current character.
        -- Warband/account-wide achievements earned by alts (wasEarnedByMe == false) still show for this character!
        local showAchievement = true
        if wasEarnedByMe == true then
            showAchievement = false
        elseif wasEarnedByMe == nil and (completed == true or completed == 1) then
            showAchievement = false
        end

        if name and name ~= "" and showAchievement then
            local lines = {}
            local progressBar = nil
            local timerBar = nil

            local numCriteria = 0
            if GetAchievementNumCriteria then
                numCriteria = GetAchievementNumCriteria(achID) or 0
            end

            local isExpanded = (expandedQuests["ach_" .. tostring(achID)] ~= false) -- expanded by default

            if numCriteria > 0 and GetAchievementCriteriaInfo then
                for criteriaIndex = 1, numCriteria do
                    local criteriaString, criteriaType, criteriaCompleted, quantity, totalQuantity, cName, cFlags, assetID, quantityString, criteriaID, eligible, duration, elapsed = GetAchievementCriteriaInfo(achID, criteriaIndex)
                    local finished = (criteriaCompleted == true or criteriaCompleted == 1)

                    -- Resolve sub-achievement title for meta criteria
                    if (criteriaType == CRITERIA_TYPE_ACHIEVEMENT and assetID) then
                        local _, subName = GetAchievementInfo(assetID)
                        if subName and subName ~= "" then
                            criteriaString = subName
                        end
                    end

                    -- Check for progress bar flag
                    local isProgressBar = (cFlags and bit_band(cFlags, EVAL_FLAG_PROGRESS_BAR) == EVAL_FLAG_PROGRESS_BAR)
                    if isProgressBar and totalQuantity and totalQuantity > 1 and not progressBar then
                        local curVal = tonumber(quantity) or 0
                        local maxVal = tonumber(totalQuantity) or 1
                        progressBar = {
                            min   = 0,
                            max   = maxVal,
                            value = curVal,
                            text  = string_format("%d / %d", curVal, maxVal),
                        }
                    end

                    -- Format criteria text
                    local txt = criteriaString
                    if not txt or txt == "" then
                        txt = quantityString
                    end
                    if not txt or txt == "" then
                        txt = cName
                    end

                    if txt and txt ~= "" and not issecretvalue(txt) then
                        if not isProgressBar then
                            local q = tonumber(quantity)
                            local tq = tonumber(totalQuantity)
                            if q and tq and tq > 1 then
                                txt = string_format("%s (%d/%d)", txt, q, tq)
                            end
                        end

                        if isExpanded then
                            table_insert(lines, {
                                text      = txt:gsub(" / ", "/"),
                                completed = finished,
                            })
                        end
                    end

                    -- Timed criteria bar
                    if duration and elapsed and elapsed < duration and not timerBar then
                        timerBar = {
                            timeTotal   = duration,
                            timeElapsed = elapsed,
                        }
                    end
                end
            elseif description and description ~= "" and not issecretvalue(description) then
                if isExpanded then
                    table_insert(lines, {
                        text      = description,
                        completed = false,
                        color     = { 0.85, 0.85, 0.85, 1 },
                    })
                end

                -- Single-criteria timed achievement check
                local timed = self.timedCriteria and self.timedCriteria[achID]
                if timed then
                    local curElapsed = (_G.GetTime and _G.GetTime() or 0) - timed.startTime
                    if curElapsed <= timed.duration then
                        timerBar = {
                            timeTotal   = timed.duration,
                            timeElapsed = curElapsed,
                        }
                    end
                end
            end

            local isSuper = (superTrackedType == GetAchievementTrackingType() and superTrackedID == achID)

            table_insert(blocks, {
                title          = name,
                titleColor     = { 1.0, 0.82, 0.0, 1 }, -- Golden achievement yellow
                isSuperTracked = isSuper,
                isAchievement  = true,
                achievementID  = achID,
                description    = description,
                points         = points,
                lines          = lines,
                progressBar    = progressBar,
                timerBar       = timerBar,
                OnClick        = function(block, btn)
                    -- Shift-Click: insert link if chat focused, otherwise untrack
                    if IsShiftKeyDown and IsShiftKeyDown() then
                        local activeChat = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
                        if activeChat and activeChat:IsShown() and activeChat:HasFocus() then
                            local link = GetAchievementLink and GetAchievementLink(achID)
                            if link and ChatEdit_InsertLink and ChatEdit_InsertLink(link) then
                                return
                            end
                        end

                        UntrackAchievement(achID)
                        return
                    end

                    -- Right-Click: Toggle Criteria Collapse/Expand
                    if btn == "RightButton" then
                        local st = GetQLState()
                        st.expandedQuests = st.expandedQuests or {}
                        local key = "ach_" .. tostring(achID)
                        local curExpanded = (st.expandedQuests[key] ~= false)
                        st.expandedQuests[key] = not curExpanded
                        if sfui.tracker and sfui.tracker.RequestRefresh then
                            sfui.tracker.RequestRefresh(0.01)
                        end
                        return
                    end

                    -- Left-Click: Open Achievement Frame to this achievement
                    OpenAchievementInUI(achID)
                end,
            })
        end
    end

    if #blocks > 0 then
        return {
            {
                id     = "achievements",
                title  = "achievements",
                color  = { 0.90, 0.75, 0.20 },
                blocks = blocks,
            }
        }
    end

    return nil
end

sfui.tracker.RegisterModule(AchievementsModule)
return AchievementsModule
