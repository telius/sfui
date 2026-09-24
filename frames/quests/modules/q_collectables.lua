--[[
    SFUI Tracker Module: Collectables (Transmog, Mounts, Housing Decor)
    frames/quests/modules/collectables.lua

    Pluggable tracker module for Content Tracking (Appearances, Mounts, Decor).
]]

local addonName, addon = ...
sfui = sfui or {}
sfui.tracker = sfui.tracker or {}
sfui.questlog = sfui.questlog or {}

local _G = _G
local C_ContentTracking = _G.C_ContentTracking
local C_HousingDecor = _G.C_HousingDecor
local C_TransmogCollection = _G.C_TransmogCollection
local C_MountJournal = _G.C_MountJournal
local C_SuperTrack = _G.C_SuperTrack
local C_Item = _G.C_Item
local Enum = _G.Enum

local select, ipairs, type, tostring = _G.select, _G.ipairs, _G.type, _G.tostring
local IsModifiedClick = _G.IsModifiedClick
local IsShiftKeyDown = _G.IsShiftKeyDown
local ChatEdit_GetActiveWindow = _G.ChatEdit_GetActiveWindow
local ChatEdit_InsertLink = _G.ChatEdit_InsertLink
local DressUpVisual = _G.DressUpVisual
local ShowAchievementFrameForAchievement = _G.ShowAchievementFrameForAchievement
local table_insert = _G.table.insert

local TYPE_APPEARANCE = (Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Appearance) or 0
local TYPE_MOUNT      = (Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Mount) or 1
local TYPE_ACHIEVE    = (Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Achievement) or 2
local TYPE_DECOR      = (Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Decor) or 3

local TARGET_ENCOUNTER  = (Enum and Enum.ContentTrackingTargetType and Enum.ContentTrackingTargetType.JournalEncounter) or 0
local TARGET_VENDOR     = (Enum and Enum.ContentTrackingTargetType and Enum.ContentTrackingTargetType.Vendor) or 1
local TARGET_ACHIEVE    = (Enum and Enum.ContentTrackingTargetType and Enum.ContentTrackingTargetType.Achievement) or 2
local TARGET_PROFESSION = (Enum and Enum.ContentTrackingTargetType and Enum.ContentTrackingTargetType.Profession) or 3
local TARGET_QUEST      = (Enum and Enum.ContentTrackingTargetType and Enum.ContentTrackingTargetType.Quest) or 4

local STOP_MANUAL = (Enum and Enum.ContentTrackingStopType and Enum.ContentTrackingStopType.Manual) or 2

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

local CollectablesModule = {
    id       = "collectables",
    priority = 50,
    events   = {
        "CONTENT_TRACKING_LIST_UPDATE",
        "SUPER_TRACKING_CHANGED",
    },
}

function CollectablesModule:Init(engine)
    self.engine = engine
end

function CollectablesModule:IsEnabled()
    return (C_ContentTracking ~= nil and C_ContentTracking.GetCollectableSourceTypes ~= nil)
end

function CollectablesModule:BuildBlocks(container)
    if not C_ContentTracking or not C_ContentTracking.GetCollectableSourceTypes or not C_ContentTracking.GetTrackedIDs then
        return nil
    end

    if C_ContentTracking.GetCollectableSourceTrackingEnabled and not C_ContentTracking.GetCollectableSourceTrackingEnabled() then
        return nil
    end

    local sourceTypes = C_ContentTracking.GetCollectableSourceTypes()
    if not sourceTypes or #sourceTypes == 0 then return nil end

    local superTrackedType, superTrackedID = nil, nil
    if C_SuperTrack and C_SuperTrack.GetSuperTrackedContent then
        superTrackedType, superTrackedID = C_SuperTrack.GetSuperTrackedContent()
    end

    local blocks = {}
    local state = GetQLState()
    local expandedQuests = state.expandedQuests or {}

    for _, trackableType in ipairs(sourceTypes) do
        local trackedIDs = C_ContentTracking.GetTrackedIDs(trackableType)
        if trackedIDs and #trackedIDs > 0 then
            for _, trackableID in ipairs(trackedIDs) do
                local title = C_ContentTracking.GetTitle and C_ContentTracking.GetTitle(trackableType, trackableID)
                if not title or title == "" then
                    if trackableType == TYPE_DECOR and C_HousingDecor and C_HousingDecor.GetDecorName then
                        title = C_HousingDecor.GetDecorName(trackableID)
                    elseif trackableType == TYPE_APPEARANCE and C_TransmogCollection and C_TransmogCollection.GetSourceInfo then
                        local sInfo = C_TransmogCollection.GetSourceInfo(trackableID)
                        title = sInfo and sInfo.name
                    elseif trackableType == TYPE_MOUNT and C_MountJournal and C_MountJournal.GetMountInfoByID then
                        title = C_MountJournal.GetMountInfoByID(trackableID)
                    end
                end

                local targetType, targetID = nil, nil
                if C_ContentTracking.GetCurrentTrackingTarget then
                    targetType, targetID = C_ContentTracking.GetCurrentTrackingTarget(trackableType, trackableID)
                end

                local objectiveText = nil
                if targetType and targetID and C_ContentTracking.GetObjectiveText then
                    objectiveText = C_ContentTracking.GetObjectiveText(targetType, targetID)
                end

                local isSuper = (superTrackedType == trackableType and superTrackedID == trackableID)
                local waypointText = nil
                if isSuper and C_ContentTracking.GetWaypointText then
                    waypointText = C_ContentTracking.GetWaypointText(trackableType, trackableID)
                end

                local lines = {}
                local key = "ct_" .. tostring(trackableType) .. "_" .. tostring(trackableID)
                local isExpanded = (expandedQuests[key] ~= false)

                if isExpanded then
                    if objectiveText and objectiveText ~= "" then
                        table_insert(lines, {
                            text      = objectiveText,
                            completed = false,
                        })
                    end
                    if waypointText and waypointText ~= "" then
                        table_insert(lines, {
                            text      = waypointText,
                            completed = false,
                            color     = { 0.0, 1.0, 0.8, 1 },
                        })
                    end
                end

                -- Formatting
                local prefix = "[Item] "
                local titleColor = { 0.7, 0.5, 1.0, 1 }
                if trackableType == TYPE_DECOR then
                    prefix = "[Decor] "
                    titleColor = { 0.7, 0.5, 1.0, 1 }
                elseif trackableType == TYPE_APPEARANCE then
                    prefix = "[Appearance] "
                    titleColor = { 1.0, 0.55, 0.8, 1 }
                elseif trackableType == TYPE_MOUNT then
                    prefix = "[Mount] "
                    titleColor = { 0.4, 0.8, 1.0, 1 }
                end

                table_insert(blocks, {
                    title          = prefix .. (title or "Collectable"),
                    titleColor     = titleColor,
                    isSuperTracked = isSuper,
                    isCollectable  = true,
                    trackableType  = trackableType,
                    trackableID    = trackableID,
                    lines          = lines,
                    OnClick        = function(block, btn)
                        -- 1. Shift-Click: Chat link or stop tracking
                        if IsShiftKeyDown and IsShiftKeyDown() then
                            local activeChat = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
                            if activeChat and activeChat:IsShown() and activeChat:HasFocus() and ChatEdit_InsertLink then
                                local link = nil
                                if trackableType == TYPE_DECOR and C_HousingDecor and C_HousingDecor.GetDecorHyperlink then
                                    link = C_HousingDecor.GetDecorHyperlink(trackableID)
                                elseif trackableType == TYPE_APPEARANCE and C_TransmogCollection and C_TransmogCollection.GetSourceInfo then
                                    local sInfo = C_TransmogCollection.GetSourceInfo(trackableID)
                                    if sInfo and sInfo.itemID and C_Item and C_Item.GetItemInfo then
                                        link = select(2, C_Item.GetItemInfo(sInfo.itemID))
                                    end
                                end
                                if link and ChatEdit_InsertLink(link) then return end
                            end

                            if C_ContentTracking.StopTracking then
                                C_ContentTracking.StopTracking(trackableType, trackableID, STOP_MANUAL)
                            end
                            if sfui.tracker and sfui.tracker.RequestRefresh then
                                sfui.tracker.RequestRefresh(0.05)
                            end
                            return
                        end

                        -- 2. Right-Click: Toggle Criteria
                        if btn == "RightButton" then
                            local st = GetQLState()
                            st.expandedQuests = st.expandedQuests or {}
                            st.expandedQuests[key] = not st.expandedQuests[key]
                            if sfui.tracker and sfui.tracker.RequestRefresh then
                                sfui.tracker.RequestRefresh(0.05)
                            end
                            return
                        end

                        -- 3. Left-Click: DressUp / Profession / Achievement / Housing
                        if trackableType == TYPE_APPEARANCE and IsModifiedClick and IsModifiedClick("DRESSUP") and DressUpVisual then
                            DressUpVisual(trackableID)
                            return
                        end

                        if targetType == TARGET_ACHIEVE and targetID and ShowAchievementFrameForAchievement then
                            ShowAchievementFrameForAchievement(targetID)
                            return
                        end

                        if targetType == TARGET_PROFESSION and targetID and _G.ProfessionsUtil and _G.ProfessionsUtil.OpenProfessionFrameToRecipe then
                            _G.ProfessionsUtil.OpenProfessionFrameToRecipe(targetID)
                            return
                        end

                        if trackableType == TYPE_DECOR and _G.HousingFramesUtil and _G.HousingFramesUtil.PreviewHousingDecorID then
                            _G.HousingFramesUtil.PreviewHousingDecorID(trackableID)
                        end

                        if C_SuperTrack and C_SuperTrack.SetSuperTrackedContent then
                            C_SuperTrack.SetSuperTrackedContent(trackableType, trackableID)
                        end
                    end,
                })
            end
        end
    end

    if #blocks > 0 then
        return {
            {
                id     = "collectables",
                title  = "collectables",
                color  = { 0.70, 0.55, 1.00 },
                blocks = blocks,
            }
        }
    end

    return nil
end

sfui.tracker.RegisterModule(CollectablesModule)
return CollectablesModule
