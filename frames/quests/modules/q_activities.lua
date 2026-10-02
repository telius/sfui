--[[
    SFUI Tracker Module: Activities (Traveler's Log & Neighborhood Initiatives)
    frames/quests/modules/activities.lua

    Pluggable tracker module for:
      - Trading Post / Traveler's Log (C_PerksActivities)
      - Player Housing Neighborhood Initiatives (C_NeighborhoodInitiative)
]]

local addonName, addon = ...
local sfui = _G.sfui or {}
sfui.tracker = sfui.tracker or {}
sfui.questlog = sfui.questlog or {}

local _G = _G
local C_PerksActivities = _G.C_PerksActivities
local C_NeighborhoodInitiative = _G.C_NeighborhoodInitiative
local InCombatLockdown = _G.InCombatLockdown
local IsShiftKeyDown = _G.IsShiftKeyDown
local ChatEdit_GetActiveWindow = _G.ChatEdit_GetActiveWindow
local ChatEdit_InsertLink = _G.ChatEdit_InsertLink
local ChatFrameUtil = _G.ChatFrameUtil
local MonthlyActivitiesFrame_OpenFrameToActivity = _G.MonthlyActivitiesFrame_OpenFrameToActivity

local ipairs, pairs, type, tonumber, tostring = _G.ipairs, _G.pairs, _G.type, _G.tonumber, _G.tostring
local table_insert = _G.table.insert
local string_format = string.format

local issecretvalue = sfui.common.issecretvalue

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

local ActivitiesModule = {
    id       = "activities",
    priority = 45,
    events   = {
        "PERKS_ACTIVITIES_UPDATED",
        "PERKS_ACTIVITY_COMPLETED",
    },
}

function ActivitiesModule:Init(engine)
    self.engine = engine
end

function ActivitiesModule:IsEnabled()
    return (C_PerksActivities ~= nil or C_NeighborhoodInitiative ~= nil)
end

function ActivitiesModule:BuildBlocks(container)
    local blocks = {}
    local state = GetQLState()
    local expandedQuests = state.expandedQuests or {}

    -- 1. Scan Traveler's Log (Perks Activities)
    if C_PerksActivities and C_PerksActivities.GetTrackedPerksActivities and C_PerksActivities.GetPerksActivityInfo then
        local tracked = C_PerksActivities.GetTrackedPerksActivities()
        local ids = tracked and tracked.trackedIDs
        if ids and #ids > 0 then
            for _, actID in ipairs(ids) do
                if type(actID) == "number" and actID > 0 then
                    local info = C_PerksActivities.GetPerksActivityInfo(actID)
                    if info and not info.completed and info.activityName and info.activityName ~= "" then
                        local lines = {}
                        local isExpanded = (expandedQuests["perk_" .. tostring(actID)] ~= false)

                        if isExpanded and info.requirementsList then
                            for _, req in ipairs(info.requirementsList) do
                                if req.requirementText and req.requirementText ~= "" and not issecretvalue(req.requirementText) then
                                    local cleanReq = req.requirementText:gsub(" / ", "/")
                                    table_insert(lines, {
                                        text      = cleanReq,
                                        completed = (req.completed == true),
                                    })
                                end
                            end
                        end

                        table_insert(blocks, {
                            title           = "[Log] " .. info.activityName,
                            titleColor      = { 0.20, 0.85, 0.95, 1 },
                            isPerksActivity = true,
                            activityID      = actID,
                            description     = info.description,
                            lines           = lines,
                            OnClick    = function(block, btn)
                                if IsShiftKeyDown and IsShiftKeyDown() then
                                    local activeChat = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow())
                                        or (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
                                        or _G.ACTIVE_CHAT_EDIT_BOX
                                    local isChatOpen = (activeChat and (activeChat:IsShown() or activeChat:IsVisible()))
                                        or (_G.MacroFrameText and _G.MacroFrameText:IsShown())
                                        or (_G.CommunitiesFrame and _G.CommunitiesFrame.ChatEditBox and _G.CommunitiesFrame.ChatEditBox:IsShown())

                                    if isChatOpen and C_PerksActivities.GetPerksActivityChatLink then
                                        local link = C_PerksActivities.GetPerksActivityChatLink(actID)
                                        if link then
                                            if ChatFrameUtil and ChatFrameUtil.InsertLink and ChatFrameUtil.InsertLink(link) then return end
                                            if ChatEdit_InsertLink and ChatEdit_InsertLink(link) then return end
                                            if activeChat and activeChat.Insert then
                                                activeChat:Insert(link)
                                                if activeChat.SetFocus then
                                                    activeChat:SetFocus()
                                                end
                                                return
                                            end
                                        end
                                    end

                                    if C_PerksActivities.RemoveTrackedPerksActivity then
                                        C_PerksActivities.RemoveTrackedPerksActivity(actID)
                                    end
                                    sfui.tracker.RequestRefresh(0.05)
                                    return
                                end

                                if btn == "RightButton" then
                                    local st = GetQLState()
                                    st.expandedQuests = st.expandedQuests or {}
                                    local key = "perk_" .. tostring(actID)
                                    st.expandedQuests[key] = not st.expandedQuests[key]
                                    sfui.tracker.RequestRefresh(0.05)
                                    return
                                end

                                if not (InCombatLockdown and InCombatLockdown()) then
                                    if not _G.EncounterJournal and _G.EncounterJournal_LoadUI then
                                        _G.EncounterJournal_LoadUI()
                                    end
                                    if MonthlyActivitiesFrame_OpenFrameToActivity then
                                        MonthlyActivitiesFrame_OpenFrameToActivity(actID)
                                    end
                                end
                            end,
                        })
                    end
                end
            end
        end
    end

    -- 2. Scan Neighborhood Initiatives (Housing Tasks)
    if C_NeighborhoodInitiative and C_NeighborhoodInitiative.GetTrackedInitiativeTasks and C_NeighborhoodInitiative.GetInitiativeTaskInfo then
        local tracked = C_NeighborhoodInitiative.GetTrackedInitiativeTasks()
        local ids = tracked and tracked.trackedIDs
        if ids and #ids > 0 then
            for _, taskID in ipairs(ids) do
                if type(taskID) == "number" and taskID > 0 then
                    local info = C_NeighborhoodInitiative.GetInitiativeTaskInfo(taskID)
                    if info and not info.completed and info.taskName and info.taskName ~= "" then
                        local lines = {}
                        local isExpanded = (expandedQuests["house_" .. tostring(taskID)] ~= false)

                        if isExpanded and info.requirementsList then
                            for _, req in ipairs(info.requirementsList) do
                                if req.requirementText and req.requirementText ~= "" and not issecretvalue(req.requirementText) then
                                    local cleanReq = req.requirementText:gsub(" / ", "/")
                                    table_insert(lines, {
                                        text      = cleanReq,
                                        completed = (req.completed == true),
                                    })
                                end
                            end
                        end

                        table_insert(blocks, {
                            title         = "[Initiative] " .. info.taskName,
                            titleColor    = { 0.40, 0.90, 0.60, 1 },
                            isHousingTask = true,
                            housingTaskID = taskID,
                            lines         = lines,
                            OnClick    = function(block, btn)
                                if IsShiftKeyDown and IsShiftKeyDown() then
                                    local activeChat = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow())
                                        or (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
                                        or _G.ACTIVE_CHAT_EDIT_BOX
                                    local isChatOpen = (activeChat and (activeChat:IsShown() or activeChat:IsVisible()))
                                        or (_G.MacroFrameText and _G.MacroFrameText:IsShown())
                                        or (_G.CommunitiesFrame and _G.CommunitiesFrame.ChatEditBox and _G.CommunitiesFrame.ChatEditBox:IsShown())

                                    if isChatOpen and C_NeighborhoodInitiative.GetInitiativeTaskChatLink then
                                        local link = C_NeighborhoodInitiative.GetInitiativeTaskChatLink(taskID)
                                        if link then
                                            if ChatFrameUtil and ChatFrameUtil.InsertLink and ChatFrameUtil.InsertLink(link) then return end
                                            if ChatEdit_InsertLink and ChatEdit_InsertLink(link) then return end
                                            if activeChat and activeChat.Insert then
                                                activeChat:Insert(link)
                                                if activeChat.SetFocus then
                                                    activeChat:SetFocus()
                                                end
                                                return
                                            end
                                        end
                                    end

                                    if C_NeighborhoodInitiative.RemoveTrackedInitiativeTask then
                                        C_NeighborhoodInitiative.RemoveTrackedInitiativeTask(taskID)
                                    end
                                    sfui.tracker.RequestRefresh(0.05)
                                    return
                                end

                                if btn == "RightButton" then
                                    local st = GetQLState()
                                    st.expandedQuests = st.expandedQuests or {}
                                    local key = "house_" .. tostring(taskID)
                                    st.expandedQuests[key] = not st.expandedQuests[key]
                                    sfui.tracker.RequestRefresh(0.05)
                                    return
                                end

                                if not (InCombatLockdown and InCombatLockdown()) and _G.HousingFramesUtil and _G.HousingFramesUtil.OpenFrameToTaskID then
                                    _G.HousingFramesUtil.OpenFrameToTaskID(taskID)
                                end
                            end,
                        })
                    end
                end
            end
        end
    end

    if #blocks > 0 then
        return {
            {
                id     = "activities",
                title  = "activities",
                color  = { 0.00, 1.00, 1.00 },
                blocks = blocks,
            }
        }
    end

    return nil
end

sfui.tracker.RegisterModule(ActivitiesModule)
return ActivitiesModule
