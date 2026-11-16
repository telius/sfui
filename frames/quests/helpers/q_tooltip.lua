local addonName, addon = ...
local sfui = _G.sfui or {}

sfui.tracker = sfui.tracker or {}
sfui.tracker.helpers = sfui.tracker.helpers or {}

local Tooltip = {}
sfui.tracker.helpers.tooltip = Tooltip

local _G = _G
local UIParent = _G.UIParent
local CreateFrame = _G.CreateFrame
local C_Timer = _G.C_Timer
local type = type
local tostring = tostring
local ipairs = ipairs
local string_format = string.format

local table_insert = table.insert
local select = select

local issecretvalue = sfui.common.issecretvalue

local ICON_CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t "
local ICON_BULLET = "|cff888888-|r "

local function IsSafeVal(v)
    return v ~= nil and not (issecretvalue and issecretvalue(v))
end

local function PickAnchor(owner)
    if not owner then return "ANCHOR_LEFT" end
    local cx = owner:GetCenter()
    if not cx or not UIParent then return "ANCHOR_LEFT" end
    local ownerPx = cx * (owner:GetEffectiveScale() or 1)
    local screenMid = (UIParent:GetWidth() * (UIParent:GetEffectiveScale() or 1)) / 2
    return ownerPx > screenMid and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
end
Tooltip.PickAnchor = PickAnchor

local MAX_REWARD_REFRESHES = 4
local rewardLoadFrame = nil
local activeHoverOwner = nil
local activeHoverData = nil
local hoverRefreshCount = 0
local refreshTimerPending = false
local isInternalRefresh = false

local function StopPendingRewardWatch()
    activeHoverOwner = nil
    activeHoverData = nil
    refreshTimerPending = false
    if rewardLoadFrame then
        rewardLoadFrame:UnregisterAllEvents()
    end
end

local function RegisterEventIfValid(frame, eventName)
    if _G.C_EventUtils and _G.C_EventUtils.IsEventValid and not _G.C_EventUtils.IsEventValid(eventName) then
        return
    end
    frame:RegisterEvent(eventName)
end

local function EnsureRewardLoadFrame()
    if rewardLoadFrame or not CreateFrame then return rewardLoadFrame end
    rewardLoadFrame = CreateFrame("Frame")
    rewardLoadFrame:SetScript("OnEvent", function()
        if not activeHoverOwner or not activeHoverData or refreshTimerPending then return end
        refreshTimerPending = true
        if C_Timer and C_Timer.After then
            C_Timer.After(0.05, function()
                refreshTimerPending = false
                local owner = activeHoverOwner
                local data = activeHoverData
                if not owner or not data then return end
                if hoverRefreshCount >= MAX_REWARD_REFRESHES then
                    StopPendingRewardWatch()
                    return
                end
                local tip = sfui.common.get_tooltip()
                if not tip or not tip:IsShown() or (tip.IsOwned and not tip:IsOwned(owner)) then
                    StopPendingRewardWatch()
                    return
                end
                hoverRefreshCount = hoverRefreshCount + 1
                isInternalRefresh = true
                Tooltip.ShowBlockTooltip(owner, data)
                isInternalRefresh = false
            end)
        end
    end)
    return rewardLoadFrame
end

local function StartPendingRewardWatch(owner, bData)
    if not owner or not bData then return end
    local f = EnsureRewardLoadFrame()
    if not f then return end
    activeHoverOwner = owner
    activeHoverData = bData
    RegisterEventIfValid(f, "ITEM_DATA_LOAD_RESULT")
    RegisterEventIfValid(f, "GET_ITEM_INFO_RECEIVED")
    RegisterEventIfValid(f, "QUEST_DATA_LOAD_RESULT")
    RegisterEventIfValid(f, "QUEST_LOG_UPDATE")
end

local function ResolveQuestLogIndex(questID, hintIndex)
    if _G.C_QuestLog and _G.C_QuestLog.GetLogIndexForQuestID then
        local idx = _G.C_QuestLog.GetLogIndexForQuestID(questID)
        if IsSafeVal(idx) and type(idx) == "number" and idx > 0 then
            return idx
        end
    end
    if _G.GetQuestLogIndexByID then
        local idx = _G.GetQuestLogIndexByID(questID)
        if IsSafeVal(idx) and type(idx) == "number" and idx > 0 then
            return idx
        end
    end

    if not _G.GetNumQuestLogEntries then
        return (type(hintIndex) == "number" and hintIndex > 0) and hintIndex or nil
    end

    local numEntries = _G.GetNumQuestLogEntries()
    if not IsSafeVal(numEntries) or type(numEntries) ~= "number" or numEntries <= 0 then
        return nil
    end

    if _G.C_QuestLog and _G.C_QuestLog.GetInfo then
        if type(hintIndex) == "number" and hintIndex >= 1 and hintIndex <= numEntries then
            local info = _G.C_QuestLog.GetInfo(hintIndex)
            if info and not info.isHeader and info.questID == questID then
                return hintIndex
            end
        end
        for idx = 1, numEntries do
            local info = _G.C_QuestLog.GetInfo(idx)
            if info and not info.isHeader and info.questID == questID then
                return idx
            end
        end
    elseif _G.GetQuestLogTitle then
        if type(hintIndex) == "number" and hintIndex >= 1 and hintIndex <= numEntries then
            local curID = select(8, _G.GetQuestLogTitle(hintIndex))
            if curID == questID then
                return hintIndex
            end
        end
        for idx = 1, numEntries do
            local _, _, _, isHeader, _, _, _, entryID = _G.GetQuestLogTitle(idx)
            if not isHeader and entryID == questID then
                return idx
            end
        end
    end

    return nil
end

local function BuildRewardItemRecord(rewardType, index, questID, hasModernQuestLog, selectedMatchesQuest)
    local getter = (rewardType == "choice") and _G.GetQuestLogChoiceInfo or _G.GetQuestLogRewardInfo
    if not getter then return nil, false end

    if rewardType == "choice" and selectedMatchesQuest and _G.GetQuestLogChoiceInfoLootType then
        local lootType = _G.GetQuestLogChoiceInfoLootType(index)
        if IsSafeVal(lootType) and lootType ~= 0 then
            return nil, false
        end
    end

    local name, texture, numItems, quality, isUsable, itemID
    if hasModernQuestLog then
        name, texture, numItems, quality, isUsable, itemID = getter(index, questID)
        if not IsSafeVal(name) and not IsSafeVal(itemID) and selectedMatchesQuest then
            name, texture, numItems, quality, isUsable, itemID = getter(index)
        end
    elseif selectedMatchesQuest then
        name, texture, numItems, quality, isUsable, itemID = getter(index)
    end

    if not IsSafeVal(name) or name == "" then name = nil end
    if not IsSafeVal(texture) or texture == "" then texture = nil end
    if not IsSafeVal(numItems) then numItems = nil end
    if not IsSafeVal(quality) then quality = nil end
    if not IsSafeVal(isUsable) then isUsable = nil end
    if not IsSafeVal(itemID) or type(itemID) ~= "number" or itemID <= 0 then itemID = nil end

    local link = nil
    if _G.GetQuestLogItemLink then
        if hasModernQuestLog then
            link = _G.GetQuestLogItemLink(rewardType, index, questID)
            if (not IsSafeVal(link) or link == "") and selectedMatchesQuest then
                link = _G.GetQuestLogItemLink(rewardType, index)
            end
        elseif selectedMatchesQuest then
            link = _G.GetQuestLogItemLink(rewardType, index)
        end
        if not IsSafeVal(link) or link == "" then link = nil end
    end

    local needsItemLoad = false
    if itemID then
        if not texture then
            local instIcon = (sfui.common and sfui.common.get_item_instant_info and select(5, sfui.common.get_item_instant_info(itemID)))
                or (_G.C_Item and _G.C_Item.GetItemIconByID and _G.C_Item.GetItemIconByID(itemID))
                or (_G.GetItemIcon and _G.GetItemIcon(itemID))
            if IsSafeVal(instIcon) and instIcon ~= "" and instIcon ~= 0 then
                texture = instIcon
            end
        end

        if not link or not name or not texture or not quality then
            local getItemInfo = (_G.C_Item and _G.C_Item.GetItemInfo) or _G.GetItemInfo
            if getItemInfo then
                local iName, iLink, iQuality, _, _, _, _, _, _, iTexture = getItemInfo(itemID)
                if not link and IsSafeVal(iLink) and iLink ~= "" then link = iLink end
                if not name and IsSafeVal(iName) and iName ~= "" then name = iName end
                if not texture and IsSafeVal(iTexture) and iTexture ~= "" then texture = iTexture end
                if not quality and IsSafeVal(iQuality) then quality = iQuality end
            end
        end

        if not name and not link then
            needsItemLoad = true
            if _G.C_Item and _G.C_Item.RequestLoadItemDataByID then
                _G.C_Item.RequestLoadItemDataByID(itemID)
            end
        end
    end

    if name or link or itemID then
        return {
            name     = name,
            texture  = texture,
            numItems = numItems or 1,
            quality  = quality or 1,
            isUsable = isUsable,
            itemID   = itemID,
            link     = link,
        }, needsItemLoad
    end

    return nil, needsItemLoad
end

local function QueryQuestRewardCount(countFn, questID, hasModernQuestLog, selectedMatchesQuest)
    if not countFn then return 0 end
    if hasModernQuestLog then
        local c = countFn(questID)
        if IsSafeVal(c) and type(c) == "number" and c > 0 then
            return c
        end
        return 0
    elseif selectedMatchesQuest then
        local sc = countFn()
        if IsSafeVal(sc) and type(sc) == "number" and sc > 0 then
            return sc
        end
    end
    return 0
end

local function CollectRewardType(out, rewardType, countFn, questID, hasModernQuestLog, selectedMatchesQuest)
    local count = QueryQuestRewardCount(countFn, questID, hasModernQuestLog, selectedMatchesQuest)
    local anyNeedsItemLoad = false
    for i = 1, count do
        local record, needsLoad = BuildRewardItemRecord(rewardType, i, questID, hasModernQuestLog, selectedMatchesQuest)
        if needsLoad then anyNeedsItemLoad = true end
        if record then table_insert(out, record) end
    end
    return anyNeedsItemLoad
end

local function GetQuestRewardItems(questID, questLogIndex)
    local choices = {}
    local rewards = {}

    if not IsSafeVal(questID) or type(questID) ~= "number" or questID <= 0 then
        return choices, rewards, false
    end

    local waitingForQuestData = false
    if _G.HaveQuestRewardData and not _G.HaveQuestRewardData(questID) then
        waitingForQuestData = true
        if _G.C_TaskQuest and _G.C_TaskQuest.RequestPreloadRewardData
            and _G.C_QuestLog and _G.C_QuestLog.IsWorldQuest and _G.C_QuestLog.IsWorldQuest(questID) then
            _G.C_TaskQuest.RequestPreloadRewardData(questID)
        end
        if _G.C_QuestLog and _G.C_QuestLog.RequestLoadQuestByID then
            _G.C_QuestLog.RequestLoadQuestByID(questID)
        end
    end

    local qIndex = ResolveQuestLogIndex(questID, questLogIndex)
    local hasModernQuestLog = (_G.C_QuestLog and _G.C_QuestLog.SetSelectedQuest and _G.C_QuestLog.GetSelectedQuest) ~= nil

    local prevSelectedQuestID = nil
    local prevSelectedIndex = nil
    local needRestoreModern = false
    local needRestoreClassic = false
    local selectedMatchesQuest = false

    if qIndex and qIndex > 0 then
        if hasModernQuestLog then
            prevSelectedQuestID = _G.C_QuestLog.GetSelectedQuest()
            if prevSelectedQuestID ~= questID then
                _G.C_QuestLog.SetSelectedQuest(questID)
                needRestoreModern = true
            end
            selectedMatchesQuest = (_G.C_QuestLog.GetSelectedQuest() == questID)
        elseif _G.SelectQuestLogEntry and _G.GetQuestLogSelection then
            prevSelectedIndex = _G.GetQuestLogSelection()
            if prevSelectedIndex ~= qIndex then
                _G.SelectQuestLogEntry(qIndex)
                needRestoreClassic = true
            end
            selectedMatchesQuest = (_G.GetQuestLogSelection() == qIndex)
        end
    elseif hasModernQuestLog then
        selectedMatchesQuest = (_G.C_QuestLog.GetSelectedQuest() == questID)
    end

    local choicesNeedLoad = CollectRewardType(
        choices, "choice", _G.GetNumQuestLogChoices, questID, hasModernQuestLog, selectedMatchesQuest
    )
    local rewardsNeedLoad = CollectRewardType(
        rewards, "reward", _G.GetNumQuestLogRewards, questID, hasModernQuestLog, selectedMatchesQuest
    )

    if needRestoreModern and prevSelectedQuestID and prevSelectedQuestID > 0 then
        _G.C_QuestLog.SetSelectedQuest(prevSelectedQuestID)
    end
    if needRestoreClassic and prevSelectedIndex and prevSelectedIndex > 0 then
        _G.SelectQuestLogEntry(prevSelectedIndex)
    end

    return choices, rewards, (waitingForQuestData or choicesNeedLoad or rewardsNeedLoad)
end

local function FormatItemRewardLine(item)
    if not item then return "" end

    local iconStr = ""
    if IsSafeVal(item.texture) and item.texture ~= "" then
        iconStr = string_format("|T%s:14:14:0:0:64:64:4:60:4:60|t ", tostring(item.texture))
    else
        iconStr = ICON_BULLET
    end

    local itemText = ""
    if IsSafeVal(item.link) and item.link ~= "" then
        itemText = string.gsub(item.link, "(%b[])", function(bracketed)
            return bracketed:lower()
        end)
    else
        local dName = item.name
        if IsSafeVal(dName) and dName ~= "" then
            dName = tostring(dName):lower()
        else
            dName = item.itemID and "loading..." or "reward item"
        end
        local q = item.quality or 1
        if _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[q] then
            local qc = _G.ITEM_QUALITY_COLORS[q]
            local rawHex = qc.hex or "ffffffff"
            local colorPrefix = (rawHex:sub(1, 2) == "|c") and rawHex or ("|c" .. rawHex)
            itemText = string_format("%s[%s]|r", colorPrefix, dName)
        else
            itemText = string_format("[%s]", dName)
        end
    end

    if IsSafeVal(item.numItems) and item.numItems > 1 then
        itemText = string_format("%s |cffffffffx%d|r", itemText, item.numItems)
    end

    return "  " .. iconStr .. itemText
end

Tooltip.GetQuestRewardItems = GetQuestRewardItems
Tooltip.FormatItemRewardLine = FormatItemRewardLine

local function check_and_append_alt_id(tip, idType, id)
    if not tip or not idType or not id then return end
    tip._sfuiCurrentType = idType
    tip._sfuiCurrentID = id

    local isAltEnabled = true
    if sfui.automation and sfui.automation.is_alt_tooltip_enabled then
        isAltEnabled = sfui.automation.is_alt_tooltip_enabled()
    elseif SfuiDB and SfuiDB.tooltipAltIDs ~= nil then
        isAltEnabled = SfuiDB.tooltipAltIDs
    elseif sfui.config and sfui.config.automation and sfui.config.automation.tooltip_alt_ids ~= nil then
        isAltEnabled = sfui.config.automation.tooltip_alt_ids
    end

    if isAltEnabled and _G.IsAltKeyDown and _G.IsAltKeyDown() then
        if sfui.automation and sfui.automation.append_tooltip_id then
            sfui.automation.append_tooltip_id(tip, idType, id)
        else
            local prefix = (idType == "item") and "item id:" or ((idType == "quest") and "quest id:" or ((idType == "achievement") and "achievement id:" or "spell id:"))
            if tip.AddDoubleLine then
                tip:AddDoubleLine("|cff00ffff" .. prefix .. "|r", "|cffffffff" .. tostring(id) .. "|r", 0, 1, 1, 1, 1, 1)
            elseif tip.AddLine then
                tip:AddLine("|cff00ffff" .. prefix .. "|r |cffffffff" .. tostring(id) .. "|r")
            end
            tip._sfuiAltIDAppended = true
        end
    end
end
Tooltip.CheckAndAppendAltID = check_and_append_alt_id

function Tooltip.ShowBlockTooltip(owner, bData)
    local tip = sfui.common.get_tooltip()
    if not tip or not bData then return end

    if not isInternalRefresh then
        hoverRefreshCount = 0
        StopPendingRewardWatch()
    end

    local anchor = PickAnchor(owner)
    tip:SetOwner(owner, anchor)
    tip:ClearLines()
    tip._sfuiAltIDAppended = nil
    tip._sfuiCurrentID = nil
    tip._sfuiCurrentType = nil
    tip._sfuiCurrentHyperlink = nil

    -- 1. Custom tooltip function or string
    if type(bData.tooltip) == "function" then
        bData.tooltip(tip, owner, bData)
        tip:Show()
        return
    elseif type(bData.tooltip) == "string" and bData.tooltip ~= "" then
        tip:AddLine(bData.title or "Objective", 1, 1, 1)
        tip:AddLine(bData.tooltip, 0.85, 0.85, 0.85, true)
        tip:Show()
        return
    end

    -- 2. Achievement
    if bData.isAchievement and bData.achievementID then
        tip:AddLine(bData.title or "Achievement", 0.95, 0.75, 0.3)
        if bData.description and bData.description ~= "" and not issecretvalue(bData.description) then
            tip:AddLine(bData.description, 0.85, 0.85, 0.85, true)
        end
        if bData.points and bData.points > 0 and not issecretvalue(bData.points) then
            tip:AddLine(tostring(bData.points) .. " Achievement Points", 0.3, 0.9, 0.4)
        end
        if bData.lines and #bData.lines > 0 then
            tip:AddLine(" ")
            for _, line in ipairs(bData.lines) do
                if line.text and line.text ~= "" and not issecretvalue(line.text) then
                    local r, g, b = 0.75, 0.75, 0.75
                    if line.completed then r, g, b = 0.30, 0.80, 0.30 end
                    tip:AddLine("  " .. (line.completed and ICON_CHECK or ICON_BULLET) .. tostring(line.text), r, g, b, true)
                end
            end
        end
        tip:AddLine(" ")
        tip:AddLine("|cff888888left-click: open achievement panel|r", 1, 1, 1)
        tip:AddLine("|cff888888right-click: collapse/expand criteria|r", 1, 1, 1)
        tip:AddLine("|cff888888shift-click: untrack achievement|r", 1, 1, 1)
        tip:Show()
        return
    end

    -- 3. Traveler's Log (Activities)
    if bData.isPerksActivity and bData.activityID then
        tip:AddLine(bData.title or "Traveler's Log", 0.20, 0.85, 0.95)
        tip:AddLine("trading post - traveler's log", 0.85, 0.85, 0.85)
        if bData.description and bData.description ~= "" and not issecretvalue(bData.description) then
            tip:AddLine(bData.description, 0.85, 0.85, 0.85, true)
        end
        if bData.lines and #bData.lines > 0 then
            tip:AddLine(" ")
            for _, line in ipairs(bData.lines) do
                if line.text and line.text ~= "" and not issecretvalue(line.text) then
                    local r, g, b = 0.75, 0.75, 0.75
                    if line.completed then r, g, b = 0.30, 0.80, 0.30 end
                    tip:AddLine("  " .. (line.completed and ICON_CHECK or ICON_BULLET) .. tostring(line.text), r, g, b, true)
                end
            end
        end
        tip:AddLine(" ")
        tip:AddLine("|cff888888left-click: open traveler's log|r", 1, 1, 1)
        tip:AddLine("|cff888888right-click: collapse/expand requirements|r", 1, 1, 1)
        tip:AddLine("|cff888888shift-click: untrack activity|r", 1, 1, 1)
        tip:Show()
        return
    end

    -- 4. Housing Endeavor
    if bData.isHousingTask and bData.housingTaskID then
        tip:AddLine(bData.title or "Housing Endeavor", 0.55, 0.85, 0.35)
        tip:AddLine("player housing neighborhood initiative", 0.85, 0.85, 0.85)
        if bData.lines and #bData.lines > 0 then
            tip:AddLine(" ")
            for _, line in ipairs(bData.lines) do
                if line.text and line.text ~= "" and not issecretvalue(line.text) then
                    local r, g, b = 0.75, 0.75, 0.75
                    if line.completed then r, g, b = 0.30, 0.80, 0.30 end
                    tip:AddLine("  " .. (line.completed and ICON_CHECK or ICON_BULLET) .. tostring(line.text), r, g, b, true)
                end
            end
        end
        tip:AddLine(" ")
        tip:AddLine("|cff888888left-click: open endeavors tab|r", 1, 1, 1)
        tip:AddLine("|cff888888right-click: collapse/expand requirements|r", 1, 1, 1)
        tip:AddLine("|cff888888shift-click: untrack task|r", 1, 1, 1)
        tip:Show()
        return
    end

    -- 5. Tracked Recipe
    if bData.isRecipe and bData.recipeID then
        tip:AddLine(bData.title or "Tracked Recipe", 0.90, 0.65, 0.30)
        tip:AddLine(bData.isRecraft and "Recrafting Recipe" or "Crafting Recipe", 0.85, 0.85, 0.85)
        if bData.lines and #bData.lines > 0 then
            tip:AddLine(" ")
            for _, line in ipairs(bData.lines) do
                if line.text and line.text ~= "" and not issecretvalue(line.text) then
                    local r, g, b = 0.75, 0.75, 0.75
                    if line.completed then r, g, b = 0.30, 0.80, 0.30 end
                    tip:AddLine("  " .. (line.completed and ICON_CHECK or ICON_BULLET) .. tostring(line.text), r, g, b, true)
                end
            end
        end
        tip:AddLine(" ")
        tip:AddLine("|cff888888left-click: open recipe in profession window|r", 1, 1, 1)
        tip:AddLine("|cff888888right-click: collapse/expand reagents|r", 1, 1, 1)
        tip:AddLine("|cff888888shift-click: untrack recipe|r", 1, 1, 1)
        tip:Show()
        return
    end

    -- 6. Collectables (Mounts, Appearances, Decor)
    if bData.isCollectable then
        tip:AddLine(bData.title or "Collectable", 0.85, 0.55, 0.95)
        if bData.lines and #bData.lines > 0 then
            tip:AddLine(" ")
            for _, line in ipairs(bData.lines) do
                if line.text and line.text ~= "" and not issecretvalue(line.text) then
                    tip:AddLine("  " .. tostring(line.text), 0.85, 0.85, 0.85, true)
                end
            end
        end
        tip:AddLine(" ")
        tip:AddLine("|cff888888left-click: preview in wardrobe / collections|r", 1, 1, 1)
        tip:AddLine("|cff888888shift-click: stop tracking|r", 1, 1, 1)
        tip:Show()
        return
    end

    -- 7. Scenario / Delve / World Event
    if bData.isScenario or bData.isWorldEvent or bData.questID == -1 then
        local r, g, b = 1.00, 0.60, 0.10
        if bData.isWorldEvent then
            if bData.isOngoing then
                r, g, b = 1.00, 0.75, 0.10
            else
                r, g, b = 0.90, 0.45, 0.90
            end
        end
        tip:AddLine(bData.title or "Event", r, g, b)
        if bData.zoneName and bData.zoneName ~= "" and not issecretvalue(bData.zoneName) then
            tip:AddLine(bData.zoneName, 0.70, 0.70, 0.70)
        end
        if bData.timeLeftText and not issecretvalue(bData.timeLeftText) then
            tip:AddLine(bData.timeLeftText, 0.20, 0.85, 0.95)
        end
        if bData.hasReminder then
            tip:AddLine("event reminder: active", 0.0, 1.0, 0.8)
        end
        if bData.lines and #bData.lines > 0 then
            tip:AddLine(" ")
            for _, line in ipairs(bData.lines) do
                if line.text and line.text ~= "" and not issecretvalue(line.text) then
                    local lr, lg, lb = 0.75, 0.75, 0.75
                    if line.completed then lr, lg, lb = 0.30, 0.80, 0.30 end
                    tip:AddLine("  " .. (line.completed and ICON_CHECK or ICON_BULLET) .. tostring(line.text), lr, lg, lb, true)
                end
            end
        end
        tip:AddLine(" ")
        if bData.isWorldEvent then
            tip:AddLine("|cff888888left-click: track & show on map|r", 1, 1, 1)
            tip:AddLine("|cff888888right-click: collapse/expand objectives|r", 1, 1, 1)
            tip:AddLine("|cff888888shift-click: toggle reminder|r", 1, 1, 1)
        else
            tip:AddLine("|cff888888left-click: show on world map|r", 1, 1, 1)
            tip:AddLine("|cff888888right-click: collapse/expand objectives|r", 1, 1, 1)
        end
        if bData.questID and bData.questID > 0 then
            check_and_append_alt_id(tip, "quest", bData.questID)
        end
        tip:Show()
        return
    end

    -- 8. Standard Quest or World Quest
    if bData.questID and bData.questID > 0 then
        local isComplete = bData.isComplete
        if isComplete == nil and _G.C_QuestLog and _G.C_QuestLog.IsComplete then
            isComplete = _G.C_QuestLog.IsComplete(bData.questID)
        end

        local titleText = bData.rawTitle or bData.title or (_G.C_QuestLog and _G.C_QuestLog.GetTitleForQuestID and _G.C_QuestLog.GetTitleForQuestID(bData.questID)) or "Quest"
        if isComplete then
            tip:AddLine(titleText, 0.2, 1.0, 0.2)
            tip:AddLine("|cff33ff33ready for turn-in|r", 0.2, 1.0, 0.2)
        elseif bData.isFailed then
            tip:AddLine(titleText, 1.0, 0.2, 0.2)
            tip:AddLine("|cffff3333failed|r", 1.0, 0.2, 0.2)
        else
            tip:AddLine(titleText, 1, 1, 1)
        end

        if bData.zoneName and bData.zoneName ~= "" and not issecretvalue(bData.zoneName) then
            tip:AddLine(bData.zoneName, 0.70, 0.70, 0.70)
        end

        if bData.suggestedGroup and bData.suggestedGroup > 1 then
            tip:AddLine(string_format("suggested players: %d", bData.suggestedGroup), 0.30, 0.80, 1.00)
        end

        if bData.timeLeftText and not issecretvalue(bData.timeLeftText) then
            tip:AddLine(bData.timeLeftText, 0.20, 0.85, 0.95)
        end

        local isWarband = bData.isWarbandCompleted
        if (isWarband == nil or isWarband == false) and bData.questID and _G.C_QuestLog and _G.C_QuestLog.IsQuestFlaggedCompletedOnAccount then
            isWarband = (_G.C_QuestLog.IsQuestFlaggedCompletedOnAccount(bData.questID) == true)
        end

        if bData.isRepeatable and not isWarband then
            tip:AddLine("repeatable quest", 0.00, 1.00, 1.00)
        elseif isWarband then
            tip:AddLine("warband completed", 0.75, 0.15, 0.15)
        end

        -- Quest Description / Summary (Classic/Camelot & Retail)
        local questDesc = nil
        if bData.questLogIndex and _G.GetQuestLogQuestText then
            local desc, obj = _G.GetQuestLogQuestText(bData.questLogIndex)
            if obj and obj ~= "" and not issecretvalue(obj) then
                questDesc = obj
            elseif desc and desc ~= "" and not issecretvalue(desc) then
                questDesc = desc
            end
        end
        if not questDesc and _G.C_QuestLog and _G.C_QuestLog.GetQuestDescription then
            local desc = _G.C_QuestLog.GetQuestDescription(bData.questID)
            if desc and desc ~= "" and not issecretvalue(desc) then
                questDesc = desc
            end
        end
        if questDesc then
            tip:AddLine(" ")
            tip:AddLine(questDesc, 0.85, 0.85, 0.85, true)
        end

        -- Objective lines
        if not bData.isRemotePeerQuest then
            if bData.lines and #bData.lines > 0 then
                tip:AddLine(" ")
                for _, line in ipairs(bData.lines) do
                    if line.text and line.text ~= "" and not issecretvalue(line.text) then
                        local r, g, b = 0.75, 0.75, 0.75
                        if line.completed then r, g, b = 0.30, 0.80, 0.30 end
                        tip:AddLine("  " .. (line.completed and ICON_CHECK or ICON_BULLET) .. tostring(line.text), r, g, b, true)
                    end
                end
            elseif _G.C_QuestLog and _G.C_QuestLog.GetQuestObjectives then
                local objs = _G.C_QuestLog.GetQuestObjectives(bData.questID)
                if objs and #objs > 0 then
                    tip:AddLine(" ")
                    for _, obj in ipairs(objs) do
                        if obj.text and obj.text ~= "" and not issecretvalue(obj.text) then
                            local r, g, b = 0.75, 0.75, 0.75
                            if obj.finished then r, g, b = 0.30, 0.80, 0.30 end
                            tip:AddLine("  " .. (obj.finished and ICON_CHECK or ICON_BULLET) .. tostring(obj.text), r, g, b, true)
                        end
                    end
                end
            end
        end

        -- Quest item rewards (choice items and fixed rewards)
        local choices, rewards, pendingRewardLoad = GetQuestRewardItems(bData.questID, bData.questLogIndex)
        if pendingRewardLoad and hoverRefreshCount < MAX_REWARD_REFRESHES then
            StartPendingRewardWatch(owner, bData)
        else
            StopPendingRewardWatch()
        end
        if #choices > 0 or #rewards > 0 then
            if #choices > 0 then
                tip:AddLine(" ")
                tip:AddLine("choose one:", 1, 0.82, 0)
                for _, item in ipairs(choices) do
                    tip:AddLine(FormatItemRewardLine(item), 1, 1, 1)
                end
            end
            if #rewards > 0 then
                tip:AddLine(" ")
                tip:AddLine("rewards:", 1, 0.82, 0)
                for _, item in ipairs(rewards) do
                    tip:AddLine(FormatItemRewardLine(item), 1, 1, 1)
                end
            end
        end

        -- Group Party Progress
        if not bData.isRemotePeerQuest and IsSafeVal(bData.questID) and _G.IsInGroup and _G.IsInGroup() and tip.SetQuestPartyProgress then
            tip:SetQuestPartyProgress(bData.questID)
        end

        -- Synced Party / Linked Peer Progress
        if bData.questID and sfui.sync and sfui.sync.GetQuestPeerStatuses then
            local peerStatuses = sfui.sync.GetQuestPeerStatuses(bData.questID, false)
            if peerStatuses and #peerStatuses > 0 then
                local reqClass = bData.isClassQuest and bData.classToken or nil
                local anyShown = false
                for _, peer in ipairs(peerStatuses) do
                    if peer.status ~= "missing" or not reqClass or peer.class == reqClass then
                        if not anyShown then
                            anyShown = true
                            tip:AddLine(" ")
                            tip:AddLine("synced peers:", 1, 0.82, 0)
                        end
                        local pLabel = "  " .. (peer.coloredName or peer.name or "?")
                        if peer.status == "missing" then
                            tip:AddDoubleLine(pLabel, "|cffff5555missing quest|r", 1, 1, 1, 1, 0.35, 0.35)
                        elseif peer.status == "completed" then
                            tip:AddDoubleLine(pLabel, "|cff44ff44completed|r", 1, 1, 1, 0.27, 1, 0.27)
                        elseif peer.status == "ready" then
                            tip:AddDoubleLine(pLabel, "|cff44ff44ready for turn-in|r", 1, 1, 1, 0.27, 1, 0.27)
                        else
                            if peer.objs and #peer.objs > 0 then
                                tip:AddDoubleLine(pLabel, "|cffffd100in progress|r", 1, 1, 1, 1, 0.82, 0)
                                local isFinFn = sfui.tracker and sfui.tracker.helpers and sfui.tracker.helpers.quest and sfui.tracker.helpers.quest.IsObjectiveTextFinished
                                for idx, oTxt in ipairs(peer.objs) do
                                    local finFlag = type(peer.objFinished) == "table" and peer.objFinished[idx] or nil
                                    local isFin = isFinFn and isFinFn(oTxt, finFlag) or false
                                    local r, g, b = 0.78, 0.85, 0.92
                                    if isFin then r, g, b = 0.30, 0.80, 0.30 end
                                    tip:AddLine("    • " .. tostring(oTxt):lower(), r, g, b, true)
                                end
                            else
                                tip:AddDoubleLine(pLabel, "|cffffd100in log|r", 1, 1, 1, 1, 0.82, 0)
                            end
                        end
                    end
                end
            end
        end

        -- Click hints
        tip:AddLine(" ")
        if bData.isRemotePeerQuest then
            tip:AddLine("|cff888888left/right-click: collapse/expand objectives|r", 1, 1, 1)
            tip:AddLine("|cff888888ctrl-click: link quest in chat|r", 1, 1, 1)
            tip:AddLine("|cff888888shift-click: hide from tracker|r", 1, 1, 1)
        else
            tip:AddLine("|cff888888left-click: open quest details / map|r", 1, 1, 1)
            tip:AddLine("|cff888888right-click: collapse/expand objectives|r", 1, 1, 1)
            tip:AddLine("|cff888888shift-click: untrack quest|r", 1, 1, 1)
            if not bData.isWorldQuest then
                tip:AddLine("|cff888888alt-click: share quest|r", 1, 1, 1)
                tip:AddLine("|cff888888ctrl-click: abandon quest|r", 1, 1, 1)
            end
            if bData.canFindGroup then
                tip:AddLine("|cff00ff88eye button: find group in group finder|r", 1, 1, 1)
            end
        end

        if bData.questID and bData.questID > 0 then
            check_and_append_alt_id(tip, "quest", bData.questID)
        end

        tip:Show()
        return
    end

    -- 9. Generic fallback if block has a title
    if bData.title and bData.title ~= "" then
        tip:AddLine(bData.title, 1, 1, 1)
        if bData.lines and #bData.lines > 0 then
            tip:AddLine(" ")
            for _, line in ipairs(bData.lines) do
                if line.text and line.text ~= "" and not issecretvalue(line.text) then
                    tip:AddLine("  - " .. tostring(line.text), 0.85, 0.85, 0.85, true)
                end
            end
        end
        if bData.questID and bData.questID > 0 then
            check_and_append_alt_id(tip, "quest", bData.questID)
        end
        tip:Show()
    end
end

function Tooltip.HideBlockTooltip(owner, bData)
    StopPendingRewardWatch()
    local tip = sfui.common.get_tooltip()
    if tip then
        tip._sfuiAltIDAppended = nil
        tip._sfuiCurrentID = nil
        tip._sfuiCurrentType = nil
        tip._sfuiCurrentHyperlink = nil
        tip:Hide()
    end
end

return Tooltip
