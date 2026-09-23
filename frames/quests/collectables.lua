local addonName, addon = ...
sfui = sfui or {}
sfui.questlog = sfui.questlog or {}
sfui.questlog.collectables = sfui.questlog.collectables or {}

local Collectables = sfui.questlog.collectables

-- ─── Localize Globals & Core C-APIs ────────────────────────
local _G = _G
local C_ContentTracking     = _G.C_ContentTracking
local C_HousingDecor        = _G.C_HousingDecor
local C_TransmogCollection  = _G.C_TransmogCollection
local C_MountJournal        = _G.C_MountJournal
local C_SuperTrack          = _G.C_SuperTrack
local C_Item                = _G.C_Item
local Enum                  = _G.Enum

local select, ipairs, type, tostring = _G.select, _G.ipairs, _G.type, _G.tostring
local IsModifiedClick       = _G.IsModifiedClick
local IsShiftKeyDown        = _G.IsShiftKeyDown
local ChatEdit_GetActiveWindow = _G.ChatEdit_GetActiveWindow
local ChatEdit_InsertLink   = _G.ChatEdit_InsertLink
local DressUpVisual         = _G.DressUpVisual
local ShowAchievementFrameForAchievement = _G.ShowAchievementFrameForAchievement
local OpenWorldMap          = _G.OpenWorldMap

-- ─── Enum Constants (with nil-safe fallbacks) ───────────────
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

-- Color palette matching SFUI aesthetic
local COLOR_DECOR      = "|cffb088ff" -- Soft lavender / violet
local COLOR_APPEARANCE = "|cffff88cc" -- Soft rose pink
local COLOR_MOUNT      = "|cff66ccff" -- Soft celestial sky blue
local COLOR_RESET      = "|r"

Collectables.Colors = {
    Decor      = COLOR_DECOR,
    Appearance = COLOR_APPEARANCE,
    Mount      = COLOR_MOUNT,
}

-- ─── Scanner ────────────────────────────────────────────────
function Collectables.Scan(intoList, AcquireTable)
    if not C_ContentTracking or not C_ContentTracking.GetCollectableSourceTypes or not C_ContentTracking.GetTrackedIDs then
        return
    end

    if C_ContentTracking.GetCollectableSourceTrackingEnabled and not C_ContentTracking.GetCollectableSourceTrackingEnabled() then
        return
    end

    local sourceTypes = C_ContentTracking.GetCollectableSourceTypes()
    if not sourceTypes or #sourceTypes == 0 then return end

    local superTrackedType, superTrackedID = nil, nil
    if C_SuperTrack and C_SuperTrack.GetSuperTrackedContent then
        superTrackedType, superTrackedID = C_SuperTrack.GetSuperTrackedContent()
    end

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

                -- Build synthetic objectives for dropdown expansion
                local objs = nil
                if objectiveText and objectiveText ~= "" then
                    objs = AcquireTable()
                    local sObj = AcquireTable()
                    sObj.text = objectiveText
                    sObj.finished = false
                    objs[#objs + 1] = sObj
                end

                if waypointText and waypointText ~= "" then
                    if not objs then objs = AcquireTable() end
                    local wObj = AcquireTable()
                    wObj.text = "|cff00ffcc" .. waypointText .. "|r"
                    wObj.finished = false
                    objs[#objs + 1] = wObj
                end

                local entry = AcquireTable()
                entry.isContentTracking   = true
                entry.contentTrackingType = trackableType
                entry.contentTrackingID   = trackableID
                entry.targetType          = targetType
                entry.targetID            = targetID
                entry.title               = title or "Tracked Collectable"
                entry.objectives          = objs
                entry._syntheticObjs      = (objs ~= nil)
                entry.isSuperTracked      = isSuper
                entry.isComplete          = false
                entry.waypointText        = waypointText

                intoList[#intoList + 1]   = entry
            end
        end
    end
end

-- ─── Title Formatter ─────────────────────────────────────────
function Collectables.FormatTitle(entry)
    local rawTitle = entry.title or "Collectable"
    local tType = entry.contentTrackingType
    local prefix = "[Item] "
    local col = COLOR_DECOR

    if tType == TYPE_DECOR then
        col = COLOR_DECOR
        prefix = "[Decor] "
    elseif tType == TYPE_APPEARANCE then
        col = COLOR_APPEARANCE
        prefix = "[Appearance] "
    elseif tType == TYPE_MOUNT then
        col = COLOR_MOUNT
        prefix = "[Mount] "
    end

    return col .. prefix .. COLOR_RESET .. rawTitle
end

-- ─── Untrack Actions ─────────────────────────────────────────
function Collectables.Untrack(trackableType, trackableID)
    if not C_ContentTracking or not C_ContentTracking.StopTracking then return end
    C_ContentTracking.StopTracking(trackableType, trackableID, STOP_MANUAL)
end

function Collectables.UntrackAll()
    if not C_ContentTracking or not C_ContentTracking.GetCollectableSourceTypes or not C_ContentTracking.GetTrackedIDs or not C_ContentTracking.StopTracking then
        return
    end
    local sourceTypes = C_ContentTracking.GetCollectableSourceTypes()
    if not sourceTypes then return end
    for _, trackableType in ipairs(sourceTypes) do
        local tracked = C_ContentTracking.GetTrackedIDs(trackableType)
        if tracked then
            for _, id in ipairs(tracked) do
                C_ContentTracking.StopTracking(trackableType, id, STOP_MANUAL)
            end
        end
    end
end

-- ─── User Interaction (Click Handler) ────────────────────────
function Collectables.OnClick(row, btn, refreshFn, getQLStateFn)
    if not row or not row.isContentTracking or not row.contentTrackingID then return false end

    local trackableType = row.contentTrackingType
    local trackableID   = row.contentTrackingID
    local targetType    = row.targetType
    local targetID      = row.targetID

    -- 1. Shift-Click: Insert chat hyperlink or stop tracking
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
            if link and ChatEdit_InsertLink(link) then
                return true
            end
        end

        Collectables.Untrack(trackableType, trackableID)
        if refreshFn then refreshFn() end
        return true
    end

    -- 2. Right-Click: Toggle objective/criteria collapse
    if btn == "RightButton" then
        if getQLStateFn then
            local state = getQLStateFn()
            state.expandedQuests = state.expandedQuests or {}
            local key = "ct_" .. tostring(trackableType) .. "_" .. tostring(trackableID)
            state.expandedQuests[key] = not state.expandedQuests[key]
            if refreshFn then refreshFn() end
        end
        return true
    end

    -- 3. Left-Click: DressUp / Profession / Achievement / Housing Preview / Map
    if trackableType == TYPE_APPEARANCE and IsModifiedClick and IsModifiedClick("DRESSUP") and DressUpVisual then
        DressUpVisual(trackableID)
        return true
    end

    if targetType == TARGET_ACHIEVE and targetID and ShowAchievementFrameForAchievement then
        ShowAchievementFrameForAchievement(targetID)
        return true
    end

    if targetType == TARGET_PROFESSION and targetID and _G.ProfessionsUtil and _G.ProfessionsUtil.OpenProfessionFrameToRecipe then
        _G.ProfessionsUtil.OpenProfessionFrameToRecipe(targetID)
        return true
    end

    if trackableType == TYPE_DECOR and _G.HousingFramesUtil and _G.HousingFramesUtil.PreviewHousingDecorID then
        _G.HousingFramesUtil.PreviewHousingDecorID(trackableID)
    end

    -- Set supertrack
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedContent then
        C_SuperTrack.SetSuperTrackedContent(trackableType, trackableID)
    end

    -- Open Map to navigation waypoint
    if _G.ContentTrackingUtil and _G.ContentTrackingUtil.OpenMapToTrackable then
        _G.ContentTrackingUtil.OpenMapToTrackable(trackableType, trackableID)
    elseif C_ContentTracking and C_ContentTracking.GetBestMapForTrackable then
        local _, uiMapID = C_ContentTracking.GetBestMapForTrackable(trackableType, trackableID)
        if uiMapID and OpenWorldMap then
            OpenWorldMap(uiMapID)
        end
    end

    if refreshFn then refreshFn() end
    return true
end

-- ─── Tooltip Handler ─────────────────────────────────────────
function Collectables.OnEnter(row, tip, anchor)
    if not row or not row.isContentTracking or not tip then return false end

    local trackableType = row.contentTrackingType
    local trackableID   = row.contentTrackingID
    local title         = row.questTitle or "Tracked Collectable"

    tip:SetOwner(row, anchor or "ANCHOR_RIGHT")
    tip:ClearLines()

    if trackableType == TYPE_DECOR then
        tip:AddLine(title, 0.70, 0.55, 1.00)
        tip:AddLine("Player Housing Decor Blueprint / Catalog", 0.85, 0.85, 0.85)
    elseif trackableType == TYPE_APPEARANCE then
        tip:AddLine(title, 1.00, 0.55, 0.80)
        tip:AddLine("Transmog Appearance Source", 0.85, 0.85, 0.85)
    elseif trackableType == TYPE_MOUNT then
        tip:AddLine(title, 0.40, 0.80, 1.00)
        tip:AddLine("Mount Journal", 0.85, 0.85, 0.85)
    else
        tip:AddLine(title, 1.00, 0.85, 0.20)
        tip:AddLine("Tracked Collectable", 0.85, 0.85, 0.85)
    end

    if row.objectives and #row.objectives > 0 then
        tip:AddLine(" ")
        for _, obj in ipairs(row.objectives) do
            if obj.text and obj.text ~= "" then
                tip:AddLine("  - " .. tostring(obj.text), 0.80, 0.80, 0.80, true)
            end
        end
    end

    tip:AddLine(" ")
    if trackableType == TYPE_DECOR then
        tip:AddLine("|cff888888Left-click: Preview Decor / Set Map Waypoint|r", 1, 1, 1)
    elseif trackableType == TYPE_APPEARANCE then
        tip:AddLine("|cff888888Left-click: Set Map Waypoint / View Source|r", 1, 1, 1)
        tip:AddLine("|cff888888Ctrl-click: Preview in Dressing Room|r", 1, 1, 1)
    else
        tip:AddLine("|cff888888Left-click: Set Map Waypoint / View Source|r", 1, 1, 1)
    end
    tip:AddLine("|cff888888Right-click / Arrow: Collapse/Expand source|r", 1, 1, 1)
    tip:AddLine("|cff888888Shift-click: Untrack Collectable|r", 1, 1, 1)

    tip:Show()
    return true
end
