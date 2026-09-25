local addonName, addon = ...
sfui = sfui or {}
sfui.tracker = sfui.tracker or {}
sfui.tracker.layout = sfui.tracker.layout or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/quests/engine/layout.lua
--  Vertical Stack Layout, Height Budgeting & Priority Stacking Engine
-- ══════════════════════════════════════════════════════════════════════════════

local _G = _G
local UIParent = _G.UIParent
local GetScreenHeight = _G.GetScreenHeight
local type, tostring = _G.type, _G.tostring
local math_max, math_min, math_abs, math_floor = _G.math.max, _G.math.min, _G.math.abs, _G.math.floor
local C_QuestLog = _G.C_QuestLog
local C_ContentTracking = _G.C_ContentTracking
local C_PerksActivities = _G.C_PerksActivities
local C_NeighborhoodInitiative = _G.C_NeighborhoodInitiative
local C_TradeSkillUI = _G.C_TradeSkillUI
local C_EventScheduler = _G.C_EventScheduler
local C_SuperTrack = _G.C_SuperTrack
local Enum = _G.Enum

local Layout = sfui.tracker.layout
local Blocks = sfui.tracker.blocks

local SPACING_SECTION = 10
local SPACING_BLOCK   = 6
local SPACING_LINE    = 2

--- Untrack all items in a given section
--- @param sec table Section table containing id and blocks
local function UntrackSection(sec)
    if not sec then return end

    if sec.OnShiftClick then
        sec.OnShiftClick()
        return
    end

    local st = SfuiDB and SfuiDB.questlog
    local expandedQuests = st and st.expandedQuests

    -- 1. Untrack all blocks currently listed in this section
    if sec.blocks then
        for _, b in ipairs(sec.blocks) do
            -- Quests & World Quests
            if b.questID and b.questID > 0 then
                local qID = b.questID
                if C_QuestLog and C_QuestLog.RemoveQuestWatch then
                    C_QuestLog.RemoveQuestWatch(qID)
                end
                if C_QuestLog and C_QuestLog.RemoveWorldQuestWatch then
                    C_QuestLog.RemoveWorldQuestWatch(qID)
                end
                if _G.RemoveQuestWatch then
                    local idx = b.questLogIndex
                    if not idx or idx <= 0 then
                        if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
                            idx = C_QuestLog.GetLogIndexForQuestID(qID)
                        elseif _G.GetQuestLogIndexByID then
                            idx = _G.GetQuestLogIndexByID(qID)
                        end
                    end
                    if idx and idx > 0 then
                        _G.RemoveQuestWatch(idx)
                    end
                end
                if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.SetSuperTrackedQuestID then
                    local curSuper = C_SuperTrack.GetSuperTrackedQuestID()
                    if curSuper and curSuper == qID then
                        pcall(C_SuperTrack.SetSuperTrackedQuestID, 0)
                    end
                end
                if expandedQuests then
                    expandedQuests[qID] = nil
                    expandedQuests["wq_" .. tostring(qID)] = nil
                end
            end

            -- Achievements
            if b.achievementID and b.achievementID > 0 then
                local achID = b.achievementID
                if C_ContentTracking and C_ContentTracking.StopTracking then
                    local trackType = (Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Achievement) or 2
                    local stopType = (Enum and Enum.ContentTrackingStopType and Enum.ContentTrackingStopType.Manual) or 2
                    C_ContentTracking.StopTracking(trackType, achID, stopType)
                end
                if _G.RemoveTrackedAchievement then
                    _G.RemoveTrackedAchievement(achID)
                end
                if expandedQuests then
                    expandedQuests["ach_" .. tostring(achID)] = nil
                end
            end

            -- Perks Activities
            if b.isPerksActivity or b.activityID then
                local actID = b.activityID
                if actID and C_PerksActivities and C_PerksActivities.RemoveTrackedPerksActivity then
                    C_PerksActivities.RemoveTrackedPerksActivity(actID)
                end
            end

            -- Housing Tasks / Initiatives
            if b.isHousingTask or b.housingTaskID then
                local taskID = b.housingTaskID
                if taskID and C_NeighborhoodInitiative and C_NeighborhoodInitiative.RemoveTrackedInitiativeTask then
                    C_NeighborhoodInitiative.RemoveTrackedInitiativeTask(taskID)
                end
                if expandedQuests and taskID then
                    expandedQuests["house_" .. tostring(taskID)] = nil
                end
            end

            -- Trade Skill Recipes
            if b.isRecipe or b.recipeID then
                local recID = b.recipeID
                if recID and C_TradeSkillUI and C_TradeSkillUI.SetRecipeTracked then
                    C_TradeSkillUI.SetRecipeTracked(recID, false, b.isRecraft or false)
                end
                if expandedQuests and recID then
                    expandedQuests["rec_" .. tostring(recID)] = nil
                end
            end

            -- Collectables (Decor, Appearances)
            if b.isCollectable or (b.trackableType and b.trackableID) then
                local tType = b.trackableType
                local tID = b.trackableID
                if tType and tID and C_ContentTracking and C_ContentTracking.StopTracking then
                    local stopType = (Enum and Enum.ContentTrackingStopType and Enum.ContentTrackingStopType.Manual) or 2
                    C_ContentTracking.StopTracking(tType, tID, stopType)
                end
                if expandedQuests and tID then
                    expandedQuests["coll_" .. tostring(tType) .. "_" .. tostring(tID)] = nil
                end
            end

            -- World Events
            if b.curEventKey and C_EventScheduler and C_EventScheduler.ClearReminder then
                C_EventScheduler.ClearReminder(b.curEventKey)
            end
        end
    end

    -- 2. Category-level bulk untracking fallback
    local secID = sec.id
    if secID == "achievements" then
        if _G.RemoveTrackedAchievement and _G.GetTrackedAchievements then
            local tracked = { _G.GetTrackedAchievements() }
            for _, id in ipairs(tracked) do
                if id and type(id) == "number" and id > 0 then
                    _G.RemoveTrackedAchievement(id)
                end
            end
        end
        if C_ContentTracking and C_ContentTracking.GetTrackedIDs and C_ContentTracking.StopTracking then
            local trackType = (Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Achievement) or 2
            local stopType = (Enum and Enum.ContentTrackingStopType and Enum.ContentTrackingStopType.Manual) or 2
            local ids = C_ContentTracking.GetTrackedIDs(trackType)
            if ids and type(ids) == "table" then
                for _, id in ipairs(ids) do
                    C_ContentTracking.StopTracking(trackType, id, stopType)
                end
            end
        end
        if _G.AchievementFrameAchievements_ForceUpdate then
            _G.AchievementFrameAchievements_ForceUpdate()
        end
    elseif secID == "activities" then
        if C_PerksActivities and C_PerksActivities.RemoveTrackedPerksActivity and C_PerksActivities.GetTrackedPerksActivities then
            local tracked = C_PerksActivities.GetTrackedPerksActivities()
            if tracked and tracked.trackedIDs then
                for _, id in ipairs(tracked.trackedIDs) do
                    C_PerksActivities.RemoveTrackedPerksActivity(id)
                end
            end
        end
        if C_NeighborhoodInitiative and C_NeighborhoodInitiative.RemoveTrackedInitiativeTask and C_NeighborhoodInitiative.GetTrackedInitiativeTasks then
            local tracked = C_NeighborhoodInitiative.GetTrackedInitiativeTasks()
            if tracked and tracked.trackedIDs then
                for _, id in ipairs(tracked.trackedIDs) do
                    C_NeighborhoodInitiative.RemoveTrackedInitiativeTask(id)
                end
            end
        end
    elseif secID == "recipes" then
        if C_TradeSkillUI and C_TradeSkillUI.SetRecipeTracked and C_TradeSkillUI.GetRecipesTracked then
            for _, isRecraft in ipairs({ false, true }) do
                local recipes = C_TradeSkillUI.GetRecipesTracked(isRecraft)
                if recipes then
                    for _, rID in ipairs(recipes) do
                        C_TradeSkillUI.SetRecipeTracked(rID, false, isRecraft)
                    end
                end
            end
        end
    elseif secID == "collectables" then
        if C_ContentTracking and C_ContentTracking.GetTrackedIDs and C_ContentTracking.StopTracking then
            local stopType = (Enum and Enum.ContentTrackingStopType and Enum.ContentTrackingStopType.Manual) or 2
            local decorType = (Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Decor) or 3
            local appType = (Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Appearance) or 1
            for _, tType in ipairs({ decorType, appType }) do
                local ids = C_ContentTracking.GetTrackedIDs(tType)
                if ids and type(ids) == "table" then
                    for _, id in ipairs(ids) do
                        C_ContentTracking.StopTracking(tType, id, stopType)
                    end
                end
            end
        end
    elseif secID == "world" or secID == "worldquests" then
        if C_QuestLog and C_QuestLog.GetNumWorldQuestWatches and C_QuestLog.GetQuestIDForWorldQuestWatchIndex then
            local numW = C_QuestLog.GetNumWorldQuestWatches() or 0
            for w = numW, 1, -1 do
                local qID = C_QuestLog.GetQuestIDForWorldQuestWatchIndex(w)
                if qID and qID > 0 then
                    if C_QuestLog.RemoveWorldQuestWatch then
                        C_QuestLog.RemoveWorldQuestWatch(qID)
                    end
                    if C_QuestLog.RemoveQuestWatch then
                        C_QuestLog.RemoveQuestWatch(qID)
                    end
                end
            end
        end
    end

    -- 3. Quest Log scan for category match (fallback for quests)
    if secID == "campaign" or secID == "important" or secID == "meta" or secID == "zone" or secID == "quests" or (type(secID) == "string" and secID:find("^zone")) then
        local numEntries = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries())
            or (_G.GetNumQuestLogEntries and _G.GetNumQuestLogEntries())
            or 0
        local currentHeader = "Miscellaneous"
        for i = 1, numEntries do
            local qID, isH, isWatched = nil, false, false
            local info = C_QuestLog and C_QuestLog.GetInfo and C_QuestLog.GetInfo(i)
            if info then
                isH = info.isHeader
                qID = info.questID
                if isH then
                    currentHeader = info.title or "Miscellaneous"
                end
            elseif _G.GetQuestLogTitle then
                local qTitle, _, _, qHeader, _, _, _, questID = _G.GetQuestLogTitle(i)
                isH = qHeader
                qID = questID
                if isH then
                    currentHeader = qTitle or "Miscellaneous"
                end
            end

            if not isH and qID and qID > 0 then
                if C_QuestLog and C_QuestLog.IsQuestWatched then
                    isWatched = C_QuestLog.IsQuestWatched(qID)
                elseif _G.IsQuestWatched then
                    isWatched = _G.IsQuestWatched(i)
                end
                if isWatched then
                    local match = false
                    local QC = Enum and Enum.QuestClassification
                    if secID == "campaign" and info and (info.campaignID and info.campaignID > 0 or info.questClassification == (QC and QC.Campaign)) then
                        match = true
                    elseif secID == "meta" and info and (info.questClassification == (QC and QC.Meta) or (C_QuestLog.IsMetaQuest and C_QuestLog.IsMetaQuest(qID))) then
                        match = true
                    elseif secID == "important" and info and (info.questClassification == (QC and QC.Important) or (C_QuestLog.IsImportantQuest and C_QuestLog.IsImportantQuest(qID))) then
                        match = true
                    elseif (secID == "zone" or secID == "quests") and (not info or (
                           not (info.campaignID and info.campaignID > 0) and
                           not (info.questClassification == (QC and QC.Campaign)) and
                           not (info.questClassification == (QC and QC.Meta)) and
                           not (info.questClassification == (QC and QC.Important)))) then
                        match = true
                    elseif type(secID) == "string" and secID:find("^zone_") then
                        local targetZone = secID:sub(6):lower()
                        if currentHeader:lower() == targetZone then
                            match = true
                        end
                    end
                    if match then
                        if C_QuestLog and C_QuestLog.RemoveQuestWatch then C_QuestLog.RemoveQuestWatch(qID) end
                        if _G.RemoveQuestWatch then _G.RemoveQuestWatch(i) end
                        if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.SetSuperTrackedQuestID then
                            local curSuper = C_SuperTrack.GetSuperTrackedQuestID()
                            if curSuper and curSuper == qID then
                                pcall(C_SuperTrack.SetSuperTrackedQuestID, 0)
                            end
                        end
                        if expandedQuests then expandedQuests[qID] = nil end
                    end
                end
            end
        end
    end
end
Layout.UntrackSection = UntrackSection

--- Build the visual layout for a list of sections and their blocks
--- @param container Frame The tracker container frame
--- @param sections table Array of { id, title, color, count, blocks = { ... } }
--- @return number Total rendered height
function Layout.BuildLayout(container, sections)
    if not container or not sections then return 0 end

    -- Reset all pools to recycle frames
    Blocks.ResetAll()

    local cfg = (sfui.config and sfui.config.questlog) or {}
    local width = cfg.width or 280
    local screenH = (UIParent and UIParent:GetHeight()) or (GetScreenHeight and GetScreenHeight()) or 1080
    local maxAllowedHeight = screenH * (cfg.maxScreenHeight or 0.45)

    local content = container.content or container
    local scrollBar = container.scrollBar
    local scrollClip = container.scrollClip
    local savedScroll = (scrollBar and scrollBar:GetValue()) or 0

    local initialW = (scrollBar and scrollBar:IsShown()) and (width - 7) or width
    content:SetWidth(initialW)

    local collapsedMap = SfuiDB and SfuiDB.questlogSectionsCollapsed or {}
    local yOffset = -4
    local hasAnyVisibleContent = false

    for _, sec in ipairs(sections) do
        if sec.blocks and #sec.blocks > 0 then
            local isCollapsed = collapsedMap[sec.id] or false

            -- 1. Acquire Section Header
            local header = Blocks.AcquireHeader(content)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOffset)
            header:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOffset)

            local col = sec.color or { 1, 1, 1 }
            local r, g, b = col[1] or 1, col[2] or 1, col[3] or 1
            local titleText = (sec.title or sec.id or ""):lower()

            header.defColor = col
            header.defLabel = titleText
            header.capFormatted = sec.capFormatted

            if header.accent then
                header.accent:SetColorTexture(r, g, b, 1)
            end

            header.title:SetText(titleText)
            header.title:SetTextColor(r, g, b, 1)

            local countVal = sec.count or (sec.blocks and #sec.blocks) or 0
            if isCollapsed then
                header.count:SetText(tostring(countVal) .. "  +")
            else
                header.count:SetText(tostring(countVal))
            end
            header.count:SetTextColor(r * 0.50, g * 0.50, b * 0.50, 1)

            local secID = sec.id
            header.secID = secID
            local currentSec = sec
            header:SetScript("OnClick", function(self, button)
                local IsShiftKeyDown = _G.IsShiftKeyDown
                if IsShiftKeyDown and IsShiftKeyDown() then
                    UntrackSection(currentSec)
                    if sfui.tracker and sfui.tracker.modules then
                        for _, mod in ipairs(sfui.tracker.modules) do
                            if mod.MarkDirty then mod:MarkDirty() end
                        end
                    end
                    if sfui.tracker and sfui.tracker.RequestRefresh then
                        sfui.tracker.RequestRefresh(0.01)
                    end
                    return
                end
                SfuiDB.questlogSectionsCollapsed = SfuiDB.questlogSectionsCollapsed or {}
                SfuiDB.questlogSectionsCollapsed[secID] = not SfuiDB.questlogSectionsCollapsed[secID]
                if sfui.tracker and sfui.tracker.RequestRefresh then
                    sfui.tracker.RequestRefresh(0.01)
                end
            end)

            yOffset = yOffset - (header:GetHeight() or 20) - 2
            hasAnyVisibleContent = true

            -- 2. Layout Blocks inside Section (if not collapsed)
            if not isCollapsed then
                yOffset = yOffset - 2

                for _, bData in ipairs(sec.blocks) do
                    local block = Blocks.AcquireBlock(content)
                    block:ClearAllPoints()
                    block:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOffset)
                    block:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOffset)

                    -- Setup SuperTrack dot, POI icon & Quest Item Button on the Left
                    local leftOffset = 2

                    -- 1. SuperTrack indicator dot & Glow
                    if bData.isSuperTracked then
                        block.stGlow:Show()
                        if block.dot then
                            block.dot:ClearAllPoints()
                            block.dot:SetPoint("LEFT", block, "LEFT", leftOffset, 0)
                            block.dot:Show()
                            leftOffset = leftOffset + 6
                        end
                    else
                        block.stGlow:Hide()
                        if block.dot then block.dot:Hide() end
                    end

                    -- 2. Left POI / Waypoint Icon
                    if bData.poiIcon then
                        block.poi:ClearAllPoints()
                        block.poi:SetPoint("LEFT", block, "LEFT", leftOffset, 0)
                        block.poi:SetTexture(bData.poiIcon)
                        block.poi:Show()
                        leftOffset = leftOffset + 18
                    else
                        block.poi:Hide()
                    end

                    -- 3. Usable Quest Item Button (placed directly to the left of the title)
                    local hasItem = false
                    if bData.itemInfo and bData.questLogIndex then
                        local itemsHelper = sfui.tracker.helpers and sfui.tracker.helpers.items
                        if itemsHelper then
                            if not block.itemButton then
                                block.itemButton = (itemsHelper.AcquireItemButton and itemsHelper.AcquireItemButton(block)) or itemsHelper.CreateItemButton(block)
                            end
                            itemsHelper.SetupItemButton(block.itemButton, bData.questLogIndex, bData.questID, bData.itemInfo)
                            block.itemButton:ClearAllPoints()
                            block.itemButton:SetPoint("LEFT", block, "LEFT", leftOffset, 0)
                            block.itemButton:Show()
                            local itemW = (block.itemButton:GetWidth() or 16)
                            leftOffset = leftOffset + itemW + 4
                            hasItem = true
                        end
                    end
                    if not hasItem and block.itemButton then
                        local itemsHelper = sfui.tracker.helpers and sfui.tracker.helpers.items
                        if itemsHelper then
                            itemsHelper.ReleaseItemButton(block.itemButton)
                        else
                            block.itemButton:Hide()
                        end
                        block.itemButton = nil
                    end

                    -- 4. Find Group (LFG) button (placed on the right edge of the title row)
                    local hasFindGroup = false
                    if bData.canFindGroup and bData.questID then
                        local findGroupHelper = sfui.tracker.helpers and sfui.tracker.helpers.findgroup
                        if findGroupHelper then
                            if not block.findGroupBtn then
                                block.findGroupBtn = findGroupHelper.CreateFindGroupButton(block)
                            end
                            findGroupHelper.SetupFindGroupButton(block.findGroupBtn, bData.questID, bData.rawTitle or bData.title)
                            block.findGroupBtn:ClearAllPoints()
                            block.findGroupBtn:SetPoint("RIGHT", block, "RIGHT", -2, 0)
                            block.findGroupBtn:Show()
                            hasFindGroup = true
                        end
                    end
                    if not hasFindGroup and block.findGroupBtn then
                        local findGroupHelper = sfui.tracker.helpers and sfui.tracker.helpers.findgroup
                        if findGroupHelper then
                            findGroupHelper.ReleaseFindGroupButton(block.findGroupBtn)
                        else
                            block.findGroupBtn:Hide()
                        end
                        block.findGroupBtn = nil
                    end

                    -- 5. Title FontString (stretches to the right edge of block, offset if findGroupBtn exists)
                    local titleX = math.max(8, leftOffset)
                    local rightOffset = hasFindGroup and -22 or -4
                    block.title:ClearAllPoints()
                    block.title:SetPoint("LEFT", block, "LEFT", titleX, 0)
                    block.title:SetPoint("RIGHT", block, "RIGHT", rightOffset, 0)

                    block.title:SetText(bData.title or "")
                    if bData.titleColor then
                        block.title:SetTextColor(unpack(bData.titleColor))
                    else
                        block.title:SetTextColor(1, 1, 1, 1)
                    end

                    -- Mouse handlers for block
                    block:SetScript("OnClick", function(self, btn)
                        if bData.OnClick then
                            bData.OnClick(self, btn)
                        end
                    end)
                    block:SetScript("OnEnter", function(self)
                        if self.hl then self.hl:SetColorTexture(1, 1, 1, 0.05) end
                        local tooltipHelper = sfui.tracker.helpers and sfui.tracker.helpers.tooltip
                        if tooltipHelper and tooltipHelper.ShowBlockTooltip then
                            tooltipHelper.ShowBlockTooltip(self, bData)
                        end
                        if bData.OnEnter then
                            bData.OnEnter(self)
                        end
                    end)
                    block:SetScript("OnLeave", function(self)
                        if self.hl then self.hl:SetColorTexture(1, 1, 1, 0) end
                        local tooltipHelper = sfui.tracker.helpers and sfui.tracker.helpers.tooltip
                        if tooltipHelper and tooltipHelper.HideBlockTooltip then
                            tooltipHelper.HideBlockTooltip(self, bData)
                        else
                            local tip = _G.GameTooltip
                            if tip then tip:Hide() end
                        end
                        if bData.OnLeave then
                            bData.OnLeave(self)
                        end
                    end)

                    local minH = (hasItem or hasFindGroup) and 18 or 14
                    local blockH = math.max(minH, (block.title:GetStringHeight() or 14) + 4)
                    block:SetHeight(blockH)
                    yOffset = yOffset - blockH

                    -- 3. Objective Lines
                    if bData.lines and #bData.lines > 0 then
                        for _, lData in ipairs(bData.lines) do
                            local line = Blocks.AcquireLine(content)
                            line:ClearAllPoints()
                            line:SetPoint("TOPLEFT", content, "TOPLEFT", 12, yOffset)
                            line:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOffset)

                            line.text:SetText(lData.text or "")
                            if lData.color then
                                line.text:SetTextColor(unpack(lData.color))
                            elseif lData.completed then
                                line.text:SetTextColor(0.5, 0.9, 0.5, 1)
                            else
                                line.text:SetTextColor(0.85, 0.85, 0.85, 1)
                            end

                            if lData.completed then
                                line.bullet:SetText((Blocks.ICONS and Blocks.ICONS.COMPLETED) or "")
                            else
                                line.bullet:SetText((Blocks.ICONS and Blocks.ICONS.BULLET) or "-")
                                line.bullet:SetTextColor(0.6, 0.6, 0.6, 1)
                            end

                            line:EnableMouse(true)
                            line:EnableMouseWheel(true)
                            line:SetScript("OnMouseWheel", function(self, delta)
                                if sfui.tracker and sfui.tracker.OnMouseWheel then
                                    sfui.tracker.OnMouseWheel(self, delta)
                                end
                            end)
                            line:SetScript("OnEnter", function()
                                if block.hl then block.hl:SetColorTexture(1, 1, 1, 0.05) end
                                local tooltipHelper = sfui.tracker.helpers and sfui.tracker.helpers.tooltip
                                if tooltipHelper and tooltipHelper.ShowBlockTooltip then
                                    tooltipHelper.ShowBlockTooltip(block, bData)
                                end
                            end)
                            line:SetScript("OnLeave", function()
                                if block.hl then block.hl:SetColorTexture(1, 1, 1, 0) end
                                local tooltipHelper = sfui.tracker.helpers and sfui.tracker.helpers.tooltip
                                if tooltipHelper and tooltipHelper.HideBlockTooltip then
                                    tooltipHelper.HideBlockTooltip(block, bData)
                                else
                                    local tip = _G.GameTooltip
                                    if tip then tip:Hide() end
                                end
                            end)
                            line:SetScript("OnMouseUp", function(_, btn)
                                if bData.OnClick then
                                    bData.OnClick(block, btn)
                                end
                            end)

                            local lineH = (line.text:GetStringHeight() or 13) + SPACING_LINE
                            line:SetHeight(lineH)
                            yOffset = yOffset - lineH
                        end
                    end

                    -- 4. Progress Status Bar (if any)
                    if bData.progressBar then
                        local pBar = Blocks.AcquireBar(content)
                        pBar:ClearAllPoints()
                        pBar:SetPoint("TOPLEFT", content, "TOPLEFT", 12, yOffset - 2)
                        pBar:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, yOffset - 2)

                        local minV = bData.progressBar.min or 0
                        local maxV = bData.progressBar.max or 100
                        local curV = bData.progressBar.value or 0
                        pBar:SetMinMaxValues(minV, maxV)
                        pBar:SetValue(curV)

                        if bData.progressBar.color then
                            pBar:SetStatusBarColor(unpack(bData.progressBar.color))
                        else
                            pBar:SetStatusBarColor(0.40, 0.00, 1.00, 0.90) -- #6600ff signature purple
                        end

                        pBar.text:SetShadowOffset(0, 0)
                        pBar.text:SetShadowColor(0, 0, 0, 0)
                        if bData.progressBar.text then
                            pBar.text:SetText(bData.progressBar.text)
                        elseif maxV > 0 then
                            local pct = math.floor((curV / maxV) * 100 + 0.5)
                            pBar.text:SetText(string.format("%d%%", pct))
                        end

                        pBar:EnableMouse(true)
                        pBar:EnableMouseWheel(true)
                        pBar:SetScript("OnMouseWheel", function(self, delta)
                            if sfui.tracker and sfui.tracker.OnMouseWheel then
                                sfui.tracker.OnMouseWheel(self, delta)
                            end
                        end)
                        pBar:SetScript("OnEnter", function()
                            if block.hl then block.hl:SetColorTexture(1, 1, 1, 0.05) end
                            local tooltipHelper = sfui.tracker.helpers and sfui.tracker.helpers.tooltip
                            if tooltipHelper and tooltipHelper.ShowBlockTooltip then
                                tooltipHelper.ShowBlockTooltip(block, bData)
                            end
                        end)
                        pBar:SetScript("OnLeave", function()
                            if block.hl then block.hl:SetColorTexture(1, 1, 1, 0) end
                            local tooltipHelper = sfui.tracker.helpers and sfui.tracker.helpers.tooltip
                            if tooltipHelper and tooltipHelper.HideBlockTooltip then
                                tooltipHelper.HideBlockTooltip(block, bData)
                            else
                                local tip = _G.GameTooltip
                                if tip then tip:Hide() end
                            end
                        end)
                        pBar:SetScript("OnMouseUp", function(_, btn)
                            if bData.OnClick then
                                bData.OnClick(block, btn)
                            end
                        end)

                        local barH = 12
                        pBar:SetHeight(barH)
                        yOffset = yOffset - barH - 4
                    end

                    -- 5. Countdown Timer Bar (if any)
                    if bData.timerBar and bData.timerBar.timeTotal then
                        local timerHelper = sfui.tracker.helpers and sfui.tracker.helpers.timerbars
                        if timerHelper and timerHelper.CanShowTimerBar() then
                            if not block.timerBarFrame then
                                block.timerBarFrame = (timerHelper.AcquireTimerBar and timerHelper.AcquireTimerBar(content)) or timerHelper.CreateTimerBar(content)
                            else
                                block.timerBarFrame:SetParent(content)
                            end
                            timerHelper.SetupTimerBar(block.timerBarFrame, bData.timerBar.timeTotal, bData.timerBar.timeElapsed)
                            block.timerBarFrame:ClearAllPoints()
                            block.timerBarFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 12, yOffset - 2)
                            block.timerBarFrame:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, yOffset - 2)
                            block.timerBarFrame:EnableMouseWheel(true)
                            block.timerBarFrame:SetScript("OnMouseWheel", function(self, delta)
                                if sfui.tracker and sfui.tracker.OnMouseWheel then
                                    sfui.tracker.OnMouseWheel(self, delta)
                                end
                            end)
                            local barH = 5
                            block.timerBarFrame:SetHeight(barH)
                            yOffset = yOffset - barH - 4
                        end
                    end

                    yOffset = yOffset - SPACING_BLOCK
                end
            end

            yOffset = yOffset - SPACING_SECTION
        end
    end

    local totalH = math.abs(yOffset)
    if not hasAnyVisibleContent then
        totalH = 0
    end

    local contentH = math_max(totalH, 20)
    content:SetHeight(contentH)

    if scrollBar and scrollClip then
        local clipH = math.min(contentH, maxAllowedHeight)
        container:SetSize(width, clipH)
        scrollClip:SetHeight(clipH)

        local scrollMax = math_max(0, contentH - clipH)
        scrollBar:SetMinMaxValues(0, scrollMax)

        if scrollMax == 0 then
            scrollBar:SetValue(0)
            scrollBar:Hide()
            scrollClip:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
            content:SetWidth(width)
            content:SetPoint("TOPLEFT", scrollClip, "TOPLEFT", 0, 0)
        else
            scrollBar:Show()
            scrollClip:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -7, 0)
            content:SetWidth(width - 7)
            local targetScroll = math.min(savedScroll, scrollMax)
            scrollBar:SetValue(targetScroll)
            content:SetPoint("TOPLEFT", scrollClip, "TOPLEFT", 0, math.floor(targetScroll + 0.5))
        end
    else
        container:SetSize(width, contentH)
    end

    return totalH
end
