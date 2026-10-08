local addonName, addon = ...
local sfui = _G.sfui or {}

sfui.tracker = sfui.tracker or {}
sfui.tracker.helpers = sfui.tracker.helpers or {}

local Tooltip = {}
sfui.tracker.helpers.tooltip = Tooltip

local _G = _G
local GameTooltip = sfui.common.get_tooltip()
local UIParent = _G.UIParent
local type = type
local tostring = tostring
local ipairs = ipairs
local math_floor = math.floor
local string_format = string.format

local table_insert = table.insert
local pcall = pcall
local select = select

local issecretvalue = sfui.common.issecretvalue

local ICON_CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t "
local ICON_BULLET = "|cff888888-|r "

local function PickAnchor(owner)
    if not owner then return "ANCHOR_LEFT" end
    local cx = owner:GetCenter()
    if not cx or not UIParent then return "ANCHOR_LEFT" end
    local ownerPx = cx * (owner:GetEffectiveScale() or 1)
    local screenMid = (UIParent:GetWidth() * (UIParent:GetEffectiveScale() or 1)) / 2
    return ownerPx > screenMid and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
end
Tooltip.PickAnchor = PickAnchor

local function SafeGetQuestLogChoiceInfo(i, questID)
    if not _G.GetQuestLogChoiceInfo then return end
    if questID then
        local ok, n, t, c, q, u, id = pcall(_G.GetQuestLogChoiceInfo, i, questID)
        if ok and n then return n, t, c, q, u, id end
    end
    local ok, n, t, c, q, u, id = pcall(_G.GetQuestLogChoiceInfo, i)
    if ok and n then return n, t, c, q, u, id end
end

local function SafeGetQuestLogRewardInfo(i, questID)
    if not _G.GetQuestLogRewardInfo then return end
    if questID then
        local ok, n, t, c, q, u, id = pcall(_G.GetQuestLogRewardInfo, i, questID)
        if ok and n then return n, t, c, q, u, id end
    end
    local ok, n, t, c, q, u, id = pcall(_G.GetQuestLogRewardInfo, i)
    if ok and n then return n, t, c, q, u, id end
end

local function SafeGetQuestLogItemLink(rewardType, i, questID)
    if not _G.GetQuestLogItemLink then return nil end
    if questID then
        local ok, link = pcall(_G.GetQuestLogItemLink, rewardType, i, questID)
        if ok and link then return link end
    end
    local ok, link = pcall(_G.GetQuestLogItemLink, rewardType, i)
    if ok and link then return link end
    return nil
end

local function SafeGetNumQuestLogChoices(questID)
    if not _G.GetNumQuestLogChoices then return 0 end
    if questID then
        local ok, count = pcall(_G.GetNumQuestLogChoices, questID)
        if ok and type(count) == "number" then return count end
    end
    local ok, count = pcall(_G.GetNumQuestLogChoices)
    if ok and type(count) == "number" then return count end
    return 0
end

local function SafeGetNumQuestLogRewards(questID)
    if not _G.GetNumQuestLogRewards then return 0 end
    if questID then
        local ok, count = pcall(_G.GetNumQuestLogRewards, questID)
        if ok and type(count) == "number" then return count end
    end
    local ok, count = pcall(_G.GetNumQuestLogRewards)
    if ok and type(count) == "number" then return count end
    return 0
end

local function GetQuestRewardItems(questID, questLogIndex)
    local choices = {}
    local rewards = {}

    local qIndex = questLogIndex
    if questID and _G.GetNumQuestLogEntries and _G.GetQuestLogTitle then
        local ok, numEntries = pcall(_G.GetNumQuestLogEntries)
        if ok and type(numEntries) == "number" then
            local okTitle, curID
            if not qIndex or qIndex < 1 or qIndex > numEntries then
                qIndex = nil
            else
                okTitle, curID = pcall(function() return select(8, _G.GetQuestLogTitle(qIndex)) end)
                if not okTitle or curID ~= questID then
                    qIndex = nil
                end
            end
            if not qIndex then
                for idx = 1, numEntries do
                    local okEntry, _, _, _, isHeader, _, _, _, entryID = pcall(_G.GetQuestLogTitle, idx)
                    if okEntry and not isHeader and entryID == questID then
                        qIndex = idx
                        break
                    end
                end
            end
        end
    end

    local prevSelection
    local needRestore = false

    if qIndex and _G.SelectQuestLogEntry and _G.GetQuestLogSelection then
        local okSel, sel = pcall(_G.GetQuestLogSelection)
        if okSel and sel ~= qIndex then
            prevSelection = sel
            pcall(_G.SelectQuestLogEntry, qIndex)
            needRestore = true
        end
    end

    -- Query choices
    local numChoices = SafeGetNumQuestLogChoices(questID)
    if numChoices > 0 and _G.GetQuestLogChoiceInfo then
        for i = 1, numChoices do
            local name, texture, numItems, quality, isUsable, itemID = SafeGetQuestLogChoiceInfo(i, questID)
            local link = SafeGetQuestLogItemLink("choice", i, questID)

            if (not link or not name or not texture) and itemID and _G.GetItemInfo then
                local iName, iLink, iQuality, _, _, _, _, _, _, iTexture = _G.GetItemInfo(itemID)
                if not link then link = iLink end
                if not name then name = iName end
                if not texture then texture = iTexture end
                if not quality then quality = iQuality end
            end

            if name or link then
                table_insert(choices, {
                    name     = name,
                    texture  = texture,
                    numItems = numItems or 1,
                    quality  = quality or 1,
                    isUsable = isUsable,
                    itemID   = itemID,
                    link     = link,
                })
            end
        end
    end

    -- Query fixed rewards
    local numRewards = SafeGetNumQuestLogRewards(questID)
    if numRewards > 0 and _G.GetQuestLogRewardInfo then
        for i = 1, numRewards do
            local name, texture, numItems, quality, isUsable, itemID = SafeGetQuestLogRewardInfo(i, questID)
            local link = SafeGetQuestLogItemLink("reward", i, questID)

            if (not link or not name or not texture) and itemID and _G.GetItemInfo then
                local iName, iLink, iQuality, _, _, _, _, _, _, iTexture = _G.GetItemInfo(itemID)
                if not link then link = iLink end
                if not name then name = iName end
                if not texture then texture = iTexture end
                if not quality then quality = iQuality end
            end

            if name or link then
                table_insert(rewards, {
                    name     = name,
                    texture  = texture,
                    numItems = numItems or 1,
                    quality  = quality or 1,
                    isUsable = isUsable,
                    itemID   = itemID,
                    link     = link,
                })
            end
        end
    end

    if needRestore and prevSelection and prevSelection > 0 and _G.SelectQuestLogEntry then
        pcall(_G.SelectQuestLogEntry, prevSelection)
    end

    return choices, rewards
end

local function FormatItemRewardLine(item)
    if not item then return "" end

    local iconStr = ""
    if item.texture and item.texture ~= "" and not issecretvalue(item.texture) then
        iconStr = string_format("|T%s:14:14:0:0:64:64:4:60:4:60|t ", tostring(item.texture))
    else
        iconStr = ICON_BULLET
    end

    local itemText = ""
    if item.link and item.link ~= "" and not issecretvalue(item.link) then
        itemText = string.gsub(item.link, "(%b[])", function(bracketed)
            return bracketed:lower()
        end)
    else
        local dName = item.name or "reward item"
        if not issecretvalue(dName) then
            dName = tostring(dName):lower()
        else
            dName = "reward item"
        end
        local q = item.quality or 1
        if _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[q] then
            local qc = _G.ITEM_QUALITY_COLORS[q]
            itemText = string_format("|c%s[%s]|r", qc.hex or "ffffffff", dName)
        else
            itemText = string_format("[%s]", dName)
        end
    end

    if item.numItems and item.numItems > 1 and not issecretvalue(item.numItems) then
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
            elseif not obj and _G.SelectQuestLogEntry and _G.GetQuestLogSelection then
                local prev = _G.GetQuestLogSelection()
                _G.SelectQuestLogEntry(bData.questLogIndex)
                local d, o = _G.GetQuestLogQuestText()
                if prev and prev > 0 then _G.SelectQuestLogEntry(prev) end
                if o and o ~= "" and not issecretvalue(o) then
                    questDesc = o
                elseif d and d ~= "" and not issecretvalue(d) then
                    questDesc = d
                end
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

        -- Quest item rewards (choice items and fixed rewards)
        local choices, rewards = GetQuestRewardItems(bData.questID, bData.questLogIndex)
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
        if _G.IsInGroup and _G.IsInGroup() and tip.SetQuestPartyProgress then
            pcall(tip.SetQuestPartyProgress, tip, bData.questID)
        end

        -- Click hints
        tip:AddLine(" ")
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
