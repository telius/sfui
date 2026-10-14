--[[
    SFUI Tracker Module: Classic Forever / Camelot Legacy Challenges Engine
    frames/quests/modules/q_camelot_challenges.lua

    Pluggable tracker module for Warcraft Forever (Camelot) & Classic Era.
    Tracks individual legacy challenges and points progress in the sfui quest log / objective tracker.
    - Category header with emerald green accent bar [legacy challenges (count)]
    - Challenge title with legacy points reward badge (+1, +2, etc.)
    - Criteria checklist, diminishing completed objectives, and progress bars
    - Timed criteria countdown bars
    - Shift-Click to share to chat or untrack
    - Left-Click to open Legacy System directly to this challenge
    - Right-Click to collapse / expand criteria
--]]

local addonName, addon = ...
local sfui             = _G.sfui or {}
sfui.tracker           = sfui.tracker or {}
sfui.questlog          = sfui.questlog or {}
sfui.challenges        = sfui.challenges or {}

-- Guard: Classic / Camelot only (Exclude Retail)
local isRetail = sfui.isRetail
if isRetail == nil then
    local projectID = _G.WOW_PROJECT_ID or 1
    local _, _, _, tocVersionNum = _G.GetBuildInfo()
    tocVersionNum = tonumber(tocVersionNum) or 0
    local isCamelot = (tocVersionNum >= 16000 and tocVersionNum < 20000) or (projectID == 18)
    isRetail = (projectID == 1) and not isCamelot
end

if isRetail then
    return
end

local _G                                      = _G
local GetTrackedAchievements                  = _G.GetTrackedAchievements
local GetAchievementInfo                      = _G.GetAchievementInfo
local GetAchievementNumCriteria               = _G.GetAchievementNumCriteria
local GetAchievementCriteriaInfo              = _G.GetAchievementCriteriaInfo
local GetAchievementCategory                  = _G.GetAchievementCategory
local GetCategoryInfo                         = _G.GetCategoryInfo
local RemoveTrackedAchievement                = _G.RemoveTrackedAchievement
local AddTrackedAchievement                   = _G.AddTrackedAchievement
local GetAchievementLink                      = _G.GetAchievementLink
local C_ContentTracking                       = _G.C_ContentTracking
local C_SuperTrack                            = _G.C_SuperTrack
local C_Traits                                = _G.C_Traits
local Enum                                    = _G.Enum
local Constants                               = _G.Constants
local IsShiftKeyDown                          = _G.IsShiftKeyDown
local hooksecurefunc                          = _G.hooksecurefunc
local pcall                                   = _G.pcall

local ipairs, pairs, type, tonumber, tostring = _G.ipairs, _G.pairs, _G.type, _G.tonumber, _G.tostring
local bit_band                                = _G.bit and _G.bit.band or function(a, b) return 0 end
local math_floor                              = math.floor
local table_insert                            = _G.table.insert
local string_format                           = string.format

local issecretvalue                           = sfui.common.issecretvalue

local EVAL_FLAG_PROGRESS_BAR                  = 1
local CRITERIA_TYPE_ACHIEVEMENT               = 8
local LEGACY_POINTS_TRAIT_CURRENCY_ID         = 4225

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

local GetQLState = sfui.questlog.GetState

--- Ensure Blizzard_LegacySystem is loaded so Constants and UI frames are accessible
local function EnsureLegacySystemLoaded()
    if not _G.LegacySystem then
        if _G.LegacySystemFrame_LoadUI then
            pcall(_G.LegacySystemFrame_LoadUI)
        elseif _G.C_AddOns and _G.C_AddOns.LoadAddOn then
            pcall(_G.C_AddOns.LoadAddOn, "Blizzard_LegacySystem")
        end
    end
end

--- Untrack an individual challenge
--- @param achID number
local function UntrackChallenge(achID)
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

    sfui.tracker.RequestRefresh(0.01)
end

--- Track an individual challenge
--- @param achID number
local function TrackChallenge(achID)
    if not achID or achID <= 0 then return end

    if C_ContentTracking and C_ContentTracking.StartTracking then
        C_ContentTracking.StartTracking(GetAchievementTrackingType(), achID)
    elseif AddTrackedAchievement then
        AddTrackedAchievement(achID)
    end

    if _G.AchievementFrameAchievements_ForceUpdate then
        _G.AchievementFrameAchievements_ForceUpdate()
    end

    sfui.tracker.RequestRefresh(0.01)
end

--- Open legacy challenges UI directly focused on the specified challenge
--- @param achID number
local function OpenChallengeInUI(achID)
    if not achID or achID <= 0 then return end

    EnsureLegacySystemLoaded()

    if _G.ShowLegacyChallenge then
        _G.ShowLegacyChallenge(achID, true)
    elseif _G.LegacySystemFrame then
        if not _G.LegacySystemFrame:IsShown() and _G.ToggleLegacyChallenges then
            _G.ToggleLegacyChallenges()
        end
        if _G.LegacySystemFrame.OpenToChallenge then
            _G.LegacySystemFrame:OpenToChallenge(achID, true)
        elseif _G.LegacySystemFrame.SelectChallenge then
            _G.LegacySystemFrame:SelectChallenge(achID)
        end
    elseif _G.ToggleLegacyChallenges then
        _G.ToggleLegacyChallenges()
    end
end

-- Export public methods
sfui.questlog.TrackChallenge       = TrackChallenge
sfui.questlog.UntrackChallenge     = UntrackChallenge
sfui.challenges.TrackChallenge     = TrackChallenge
sfui.challenges.UntrackChallenge   = UntrackChallenge

local CamelotChallengesModule = {
    id            = "camelot_challenges",
    priority      = 35,
    timedCriteria = {},
    events        = {
        "CONTENT_TRACKING_UPDATE",
        "CONTENT_TRACKING_LIST_UPDATE",
        "TRACKED_ACHIEVEMENT_LIST_CHANGED",
        "TRACKED_ACHIEVEMENT_UPDATE",
        "ACHIEVEMENT_EARNED",
        "CRITERIA_UPDATE",
        "MAJOR_FACTION_RENOWN_LEVEL_CHANGED",
        "PLAYER_ENTERING_WORLD",
    },
}

function CamelotChallengesModule:Init(engine)
    self.engine = engine
    self:SetupHooks()

    EnsureLegacySystemLoaded()

    if _G.EventRegistry and _G.EventRegistry.RegisterCallback then
        pcall(_G.EventRegistry.RegisterCallback, _G.EventRegistry, "Legacy.RefreshChallenges", function()
            self:MarkDirty()
            sfui.tracker.RequestRefresh(0.02)
        end, self)
        pcall(_G.EventRegistry.RegisterCallback, _G.EventRegistry, "Legacy.UnviewedChallengesUpdated", function()
            self:MarkDirty()
            sfui.tracker.RequestRefresh(0.02)
        end, self)
        pcall(_G.EventRegistry.RegisterCallback, _G.EventRegistry, "Legacy.UpdateCurrencyInfo", function()
            self:MarkDirty()
            sfui.tracker.RequestRefresh(0.02)
        end, self)
    end
end

function CamelotChallengesModule:IsEnabled()
    local isCamelotClient = sfui.isCamelot
        or (sfui.version and sfui.version.camelot)
        or (sfui.compat and sfui.compat.is_camelot)
        or (_G.ToggleLegacyChallenges ~= nil)
        or (_G.LegacySystemFrame_LoadUI ~= nil)
        or (_G.LegacySystem ~= nil)
        or (_G.Constants and _G.Constants.LegacyConsts ~= nil)

    if not isCamelotClient then return false end

    local enabled = (SfuiDB and SfuiDB.questlogTrackChallenges ~= false and SfuiDB.trackChallenges ~= false)
    if enabled == false then return false end

    return (GetTrackedAchievements ~= nil or C_ContentTracking ~= nil)
end

function CamelotChallengesModule:OnEvent(event, ...)
    if event == "CONTENT_TRACKING_UPDATE" then
        local trackableType, id, added = ...
        if not trackableType or trackableType == GetAchievementTrackingType() then
            self:MarkDirty()
            sfui.tracker.RequestRefresh(0.01)
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
        sfui.tracker.RequestRefresh(0.05)
    else
        self:MarkDirty()
        sfui.tracker.RequestRefresh(0.05)
    end
end

function CamelotChallengesModule:SetupHooks()
    if self.hooksInstalled then return end
    self.hooksInstalled = true

    if C_ContentTracking and C_ContentTracking.StartTracking then
        hooksecurefunc(C_ContentTracking, "StartTracking", function(trackableType, id)
            if not trackableType or trackableType == GetAchievementTrackingType() then
                self:MarkDirty()
                sfui.tracker.RequestRefresh(0.01)
            end
        end)
    end

    if C_ContentTracking and C_ContentTracking.StopTracking then
        hooksecurefunc(C_ContentTracking, "StopTracking", function(trackableType, id)
            if not trackableType or trackableType == GetAchievementTrackingType() then
                self:MarkDirty()
                sfui.tracker.RequestRefresh(0.01)
            end
        end)
    end

    if AddTrackedAchievement then
        hooksecurefunc("AddTrackedAchievement", function()
            self:MarkDirty()
            sfui.tracker.RequestRefresh(0.01)
        end)
    end

    if RemoveTrackedAchievement then
        hooksecurefunc("RemoveTrackedAchievement", function()
            self:MarkDirty()
            sfui.tracker.RequestRefresh(0.01)
        end)
    end
end

function CamelotChallengesModule:BuildBlocks(container)
    self:SetupHooks()

    local trackedIDs = {}
    local seen = {}

    local function addID(id)
        if type(id) == "number" and id > 0 and not seen[id] then
            seen[id] = true
            table_insert(trackedIDs, id)
        end
    end

    -- 1. Modern Content Tracking (Camelot/Retail shared engine)
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
    local st = GetQLState()
    local expandedBlocks = st.expandedBlocks or {}

    local superTrackedType = (C_SuperTrack and C_SuperTrack.GetSuperTrackedContent and C_SuperTrack.GetSuperTrackedContent())
    local superTrackedID = (C_SuperTrack and C_SuperTrack.GetSuperTrackedAchievementID and C_SuperTrack.GetSuperTrackedAchievementID())

    local traitCurrencyID = (Constants and Constants.LegacyConsts and Constants.LegacyConsts.LEGACY_POINTS_TRAIT_CURRENCY_ID) or LEGACY_POINTS_TRAIT_CURRENCY_ID

    for _, achID in ipairs(trackedIDs) do
        local id, name, points, completed, month, day, year, description, flags, icon, rewardText, isGuild, wasEarnedByMe = GetAchievementInfo(achID)

        if id and name and name ~= "" and not issecretvalue(name) then
            local lines = {}
            local progressBar = nil
            local timerBar = nil

            -- Query legacy points reward for this challenge
            local legacyPoints = 0
            if C_Traits and C_Traits.GetTraitCurrencyForAchievement then
                local ok, pts = pcall(C_Traits.GetTraitCurrencyForAchievement, traitCurrencyID, achID)
                if ok and pts and pts > 0 then
                    legacyPoints = pts
                end
            end
            if legacyPoints == 0 and points and points > 0 then
                legacyPoints = points
            end

            -- Query category name for rich tooltip
            local categoryName = nil
            if GetAchievementCategory and GetCategoryInfo then
                local catID = GetAchievementCategory(achID)
                if catID then
                    local cName = GetCategoryInfo(catID)
                    if cName and cName ~= "" then
                        categoryName = cName
                    end
                end
            end

            local isExpanded = (expandedBlocks["chal_" .. tostring(achID)] ~= false) -- expanded by default
            local numCriteria = 0
            if GetAchievementNumCriteria then
                numCriteria = GetAchievementNumCriteria(achID) or 0
            end

            if numCriteria > 0 and GetAchievementCriteriaInfo then
                for criteriaIndex = 1, numCriteria do
                    local criteriaString, criteriaType, criteriaCompleted, quantity, totalQuantity, cName, cFlags, assetID, quantityString, criteriaID, eligible, duration, elapsed = GetAchievementCriteriaInfo(achID, criteriaIndex)
                    local finished = (criteriaCompleted == true or criteriaCompleted == 1)

                    -- Resolve sub-challenge name for meta criteria
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
                            color = { 0.08, 0.72, 0.22, 1.0 },
                        }
                    end

                    -- Format criteria line text
                    local txt = criteriaString
                    if not txt or txt == "" then txt = quantityString end
                    if not txt or txt == "" then txt = cName end

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
                                text      = txt:lower():gsub(" / ", "/"),
                                completed = finished,
                                color     = finished and { 0.45, 0.45, 0.45, 1 } or { 0.88, 0.88, 0.88, 1 },
                            })
                        end
                    end

                    -- Timed criteria countdown bar
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
                        text      = description:lower(),
                        completed = (completed and wasEarnedByMe),
                        color     = { 0.85, 0.85, 0.85, 1 },
                    })
                end

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

            -- Format challenge title with points badge
            local titleFormatted = name:lower()
            if completed and wasEarnedByMe then
                titleFormatted = string_format("%s |cff33ff33(completed)|r", titleFormatted)
            elseif legacyPoints > 0 then
                titleFormatted = string_format("%s |cff14b83b(+%d)|r", titleFormatted, legacyPoints)
            end

            local isSuper = (superTrackedType == GetAchievementTrackingType() and superTrackedID == achID)

            table_insert(blocks, {
                id             = "chal_" .. tostring(achID),
                title          = titleFormatted,
                titleColor     = { 0.95, 0.95, 0.95, 1 },
                isSuperTracked = isSuper,
                isAchievement  = true,
                isChallenge    = true,
                achievementID  = achID,
                description    = description,
                points         = legacyPoints,
                lines          = lines,
                progressBar    = progressBar,
                timerBar       = timerBar,

                OnEnter = function(blockFrame)
                    local tip = sfui.common.get_tooltip()
                    if not tip then return end
                    tip:SetOwner(blockFrame, "ANCHOR_RIGHT")
                    tip:ClearLines()
                    local pointStr = (legacyPoints > 0) and string_format("+%d legacy points", legacyPoints) or "legacy challenge"
                    tip:AddDoubleLine(name:lower(), pointStr, 0.08, 0.72, 0.22, 0.08, 0.72, 0.22)
                    if categoryName and categoryName ~= "" then
                        tip:AddLine(categoryName:lower(), 0.7, 0.7, 0.7)
                    end
                    if description and description ~= "" then
                        tip:AddLine(" ")
                        tip:AddLine(description:lower(), 0.92, 0.92, 0.92, true)
                    end
                    tip:AddLine(" ")
                    tip:AddLine("|cff00ffffleft-click|r: open in legacy challenges", 0.6, 0.6, 0.6)
                    tip:AddLine("|cff00ffffright-click|r: collapse / expand criteria", 0.6, 0.6, 0.6)
                    tip:AddLine("|cff00ffffshift-click|r: share to chat or untrack", 0.6, 0.6, 0.6)
                    tip:Show()
                end,

                OnLeave = function(blockFrame)
                    local tip = sfui.common.get_tooltip()
                    if tip and tip:IsShown() then tip:Hide() end
                end,

                OnClick = function(block, btn)
                    -- Shift-Click: insert link if chat editbox open, otherwise untrack
                    if IsShiftKeyDown and IsShiftKeyDown() then
                        local link = GetAchievementLink and GetAchievementLink(achID)
                        if link and sfui.common.insert_link_to_chat(link) then
                            return
                        end

                        UntrackChallenge(achID)
                        return
                    end

                    -- Right-Click: Toggle Criteria Collapse/Expand
                    if btn == "RightButton" then
                        local state = GetQLState()
                        state.expandedBlocks = state.expandedBlocks or {}
                        local key = "chal_" .. tostring(achID)
                        local curExpanded = (state.expandedBlocks[key] ~= false)
                        state.expandedBlocks[key] = not curExpanded
                        sfui.tracker.RequestRefresh(0.01)
                        return
                    end

                    -- Left-Click: Open Legacy Challenges Frame directly to this challenge
                    OpenChallengeInUI(achID)
                end,
            })
        end
    end

    if #blocks > 0 then
        return {
            {
                id     = "challenges",
                title  = "legacy challenges",
                color  = { 0.08, 0.72, 0.22 }, -- Emerald green
                count  = #blocks,
                blocks = blocks,
            }
        }
    end

    return nil
end

sfui.tracker.RegisterModule(CamelotChallengesModule)
