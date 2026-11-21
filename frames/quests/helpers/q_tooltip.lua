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
local tonumber = tonumber
local pairs = pairs
local ipairs = ipairs
local setmetatable = setmetatable
local math_floor = math.floor
local string_format = string.format
local string_lower = string.lower
local string_match = string.match
local string_gsub = string.gsub
local string_byte = string.byte
local string_sub = string.sub

local table_insert = table.insert
local table_concat = table.concat
local select = select

local issecretvalue = sfui.common.issecretvalue

local ICON_CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t "
local ICON_DONE = "|TInterface\\RaidFrame\\ReadyCheck-Ready:11:11:0:0|t"
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

local MAX_DOUBLE_LINE_CHARS = 56

local function StripColorCodes(text)
    if type(text) ~= "string" then return "" end
    local clean = string_gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    clean = string_gsub(clean, "|r", "")
    clean = string_gsub(clean, "|T.-|t", "")
    return clean
end

local function AddCompactRow(tip, leftText, rightText, lr, lg, lb, rr, rg, rb)
    local visibleLen = #StripColorCodes(leftText) + #StripColorCodes(rightText)
    if tip.AddDoubleLine and visibleLen <= MAX_DOUBLE_LINE_CHARS then
        tip:AddDoubleLine(leftText, rightText, lr, lg, lb, rr, rg, rb)
    else
        tip:AddLine(leftText, lr, lg, lb, true)
        tip:AddLine("    " .. rightText, rr, rg, rb, true)
    end
end

local function IsObjectiveFinished(txt, finFlag)
    local qHelper = sfui.tracker and sfui.tracker.helpers and sfui.tracker.helpers.quest
    if qHelper and qHelper.IsObjectiveTextFinished then
        return qHelper.IsObjectiveTextFinished(txt, finFlag)
    end
    if finFlag == 1 or finFlag == true then return true end
    if type(txt) ~= "string" then return false end
    local cur, max = string_match(txt, "(%d+)%s*/%s*(%d+)")
    if cur and max then
        local nCur, nMax = tonumber(cur), tonumber(max)
        if nCur and nMax and nMax > 0 and nCur >= nMax then
            return true
        end
    end
    return false
end

local function HasObjectiveProgress(txt, finFlag)
    if IsObjectiveFinished(txt, finFlag) then return true end
    if type(txt) ~= "string" then return false end
    local cur = string_match(txt, "(%d+)%s*/%s*%d+")
    if cur and (tonumber(cur) or 0) > 0 then return true end
    local pct = string_match(txt, "(%d+)%%")
    if pct and (tonumber(pct) or 0) > 0 then return true end
    return false
end

local function MakeParsedFraction(label, cur, max)
    local cleanLabel = string_gsub(label or "", "[:%s]+$", "")
    if cleanLabel == "" then return nil end
    local low = string_lower(cleanLabel)
    return {
        key       = low,
        label     = low,
        kind      = "fraction",
        cur       = tonumber(cur),
        max       = tonumber(max),
        valueText = cur .. "/" .. max,
        shortVal  = tostring(tonumber(cur) or cur),
    }
end

local function MakeParsedPercent(label, pct)
    local cleanLabel = string_gsub(label or "", "[:%s]+$", "")
    if cleanLabel == "" then return nil end
    local low = string_lower(cleanLabel)
    return {
        key       = low,
        label     = low,
        kind      = "percent",
        cur       = tonumber(pct),
        valueText = pct .. "%",
        shortVal  = pct .. "%",
    }
end

local function ParseObjectiveProgress(rawText)
    local clean = string_gsub(tostring(rawText or ""), " / ", "/")
    clean = string_gsub(clean, "^%s+", "")
    clean = string_gsub(clean, "^[%-•*]%s*", "")
    clean = string_gsub(clean, "%s+$", "")

    local sLabel, sCur, sMax = string_match(clean, "^(.-)%s*:?%s*(%d+)%s*/%s*(%d+)%s*$")
    local parsed = sLabel and MakeParsedFraction(sLabel, sCur, sMax)
    if parsed then return parsed end

    local pCur, pMax, pRest = string_match(clean, "^(%d+)%s*/%s*(%d+)%s+(.+)$")
    parsed = pCur and MakeParsedFraction(pRest, pCur, pMax)
    if parsed then return parsed end

    local pctLabel, pctVal = string_match(clean, "^(.-)%s*%((%d+)%%%)$")
    if not pctLabel then
        pctLabel, pctVal = string_match(clean, "^(.-)%s*:%s*(%d+)%%$")
    end
    parsed = pctLabel and MakeParsedPercent(pctLabel, pctVal)
    if parsed then return parsed end

    local leadPct, leadLabel = string_match(clean, "^(%d+)%%%s+(.+)$")
    parsed = leadPct and MakeParsedPercent(leadLabel, leadPct)
    if parsed then return parsed end

    local low = string_lower(clean)
    return {
        key   = low,
        label = low,
        kind  = "plain",
    }
end

local function BuildSyncedPeerSummary(peerStatuses, reqClass, isRemotePeerQuest, localIsComplete)
    if not peerStatuses or #peerStatuses == 0 then return nil end

    local missingPeers = {}
    local readyPeers = {}
    local completedPeers = {}
    local inLogPeers = {}
    local objGroups = {}
    local objGroupByKey = {}
    local partyTotal = 0
    local partyReady = 0
    local syncedInPartyCount = 0

    local function add_obj_group(peerName, parsed)
        if not parsed or parsed.key == "" then return end
        local g = objGroupByKey[parsed.key]
        if not g then
            g = {
                key      = parsed.key,
                label    = parsed.label,
                kind     = parsed.kind,
                max      = parsed.max,
                sameMax  = (parsed.max ~= nil),
                allSame  = true,
                firstVal = parsed.valueText,
                entries  = {},
            }
            objGroupByKey[parsed.key] = g
            objGroups[#objGroups + 1] = g
        else
            if g.kind ~= parsed.kind then
                g.kind = "mixed"
                g.sameMax = false
            elseif g.max ~= parsed.max then
                g.sameMax = false
            end
            if g.firstVal ~= parsed.valueText then
                g.allSame = false
            end
        end
        g.entries[#g.entries + 1] = {
            name      = peerName,
            valueText = parsed.valueText,
            shortVal  = parsed.shortVal,
            cur       = parsed.cur,
        }
    end

    for _, peer in ipairs(peerStatuses) do
        if peer.inParty then
            syncedInPartyCount = syncedInPartyCount + 1
        end
        local includePeer = (peer.status ~= "missing")
            or (peer.inParty == true and (not reqClass or peer.class == reqClass))
        if includePeer then
            local pLabel = peer.coloredName or (peer.name and string_lower(peer.name)) or "?"
            if peer.inParty then
                partyTotal = partyTotal + 1
            end

            if peer.status == "missing" then
                missingPeers[#missingPeers + 1] = pLabel
            elseif peer.status == "completed" then
                completedPeers[#completedPeers + 1] = pLabel
                if peer.inParty then partyReady = partyReady + 1 end
            elseif peer.status == "ready" then
                readyPeers[#readyPeers + 1] = pLabel
                if peer.inParty then partyReady = partyReady + 1 end
            else
                local unfinished = {}
                local hasObjTable = false
                if type(peer.unfinishedObjs) == "table" and #peer.unfinishedObjs > 0 then
                    hasObjTable = true
                    for _, oTxt in ipairs(peer.unfinishedObjs) do
                        if not IsObjectiveFinished(oTxt, nil) then
                            unfinished[#unfinished + 1] = oTxt
                        end
                    end
                elseif type(peer.objs) == "table" and #peer.objs > 0 then
                    hasObjTable = true
                    for idx, oTxt in ipairs(peer.objs) do
                        local finFlag = type(peer.objFinished) == "table" and peer.objFinished[idx] or nil
                        if not IsObjectiveFinished(oTxt, finFlag) then
                            unfinished[#unfinished + 1] = oTxt
                        end
                    end
                end

                local peerHasProgress
                if peer.hasProgress ~= nil then
                    peerHasProgress = (peer.hasProgress == true)
                else
                    peerHasProgress = false
                    local scanList = (type(peer.objs) == "table" and #peer.objs > 0 and peer.objs) or peer.unfinishedObjs
                    if type(scanList) == "table" then
                        for idx, oTxt in ipairs(scanList) do
                            local finFlag = type(peer.objFinished) == "table" and peer.objFinished[idx] or nil
                            if HasObjectiveProgress(oTxt, finFlag) then
                                peerHasProgress = true
                                break
                            end
                        end
                    end
                end

                if hasObjTable and #unfinished == 0 then
                    readyPeers[#readyPeers + 1] = pLabel
                    if peer.inParty then partyReady = partyReady + 1 end
                elseif #unfinished == 0 or (not isRemotePeerQuest and not peerHasProgress) then
                    inLogPeers[#inLogPeers + 1] = pLabel
                else
                    for _, oTxt in ipairs(unfinished) do
                        add_obj_group(pLabel, ParseObjectiveProgress(oTxt))
                    end
                end
            end
        end
    end

    local hasAny = (#missingPeers > 0)
        or (#readyPeers > 0)
        or (#completedPeers > 0)
        or (#inLogPeers > 0)
        or (#objGroups > 0)

    return {
        missingPeers       = missingPeers,
        readyPeers         = readyPeers,
        completedPeers     = completedPeers,
        inLogPeers         = inLogPeers,
        objGroups          = objGroups,
        partyTotal         = partyTotal,
        partyReady         = partyReady,
        syncedInPartyCount = syncedInPartyCount,
        hasAny             = hasAny,
    }
end
Tooltip.BuildSyncedPeerSummary = BuildSyncedPeerSummary

local function FormatGroupRightText(group)
    if group.kind == "plain" or group.allSame then
        local names = {}
        for i = 1, #group.entries do
            names[i] = group.entries[i].name
        end
        return table_concat(names, ", ")
    end
    local parts = {}
    for i = 1, #group.entries do
        local entry = group.entries[i]
        local val = (group.sameMax and entry.shortVal) or entry.valueText or ""
        if val ~= "" then
            parts[i] = entry.name .. " |cffffd100" .. val .. "|r"
        else
            parts[i] = entry.name
        end
    end
    return table_concat(parts, ", ")
end

local function AppendSyncedPeersSection(tip, summary, isRemotePeerQuest, localIsComplete)
    if not summary or not summary.hasAny then return end

    tip:AddLine(" ")

    local nonEmptyBucket = nil
    local bucketCount = 0
    local staticBuckets = {
        { list = summary.missingPeers,   row = "  missing", single = "synced (missing)", r = 1.00, g = 0.35, b = 0.35 },
        { list = summary.readyPeers,     row = "  ready",   single = "ready",            r = 0.27, g = 1.00, b = 0.27, isReady = true },
        { list = summary.completedPeers, row = "  done",    single = "synced (done)",    r = 0.40, g = 0.85, b = 0.45 },
        { list = summary.inLogPeers,     row = "  in log",  single = "synced (in log)",  r = 1.00, g = 0.82, b = 0.00 },
    }
    for _, b in ipairs(staticBuckets) do
        if #b.list > 0 then
            bucketCount = bucketCount + 1
            nonEmptyBucket = b
        end
    end

    if #summary.objGroups == 0 and bucketCount == 1 and nonEmptyBucket then
        local label = nonEmptyBucket.single
        if nonEmptyBucket.isReady then
            if (isRemotePeerQuest or localIsComplete) and summary.partyTotal > 0 then
                label = "synced (all ready)"
            elseif not isRemotePeerQuest and summary.partyTotal > 0 then
                label = string_format("synced (%d/%d ready)", summary.partyReady, summary.partyTotal + 1)
            else
                label = "synced (ready)"
            end
        end
        AddCompactRow(tip, label, table_concat(nonEmptyBucket.list, ", "),
            nonEmptyBucket.r, nonEmptyBucket.g, nonEmptyBucket.b, 1, 1, 1)
        return
    end

    if summary.partyTotal > 0 then
        local total = isRemotePeerQuest and summary.partyTotal or (summary.partyTotal + 1)
        local ready = summary.partyReady + ((not isRemotePeerQuest and localIsComplete) and 1 or 0)
        tip:AddLine(string_format("synced (%d/%d ready):", ready, total), 1, 0.82, 0)
    else
        tip:AddLine("synced peers:", 1, 0.82, 0)
    end

    for _, b in ipairs(staticBuckets) do
        if #b.list > 0 then
            AddCompactRow(tip, b.row, table_concat(b.list, ", "), b.r, b.g, b.b, 1, 1, 1)
        end
    end

    for _, group in ipairs(summary.objGroups) do
        local leftText
        if group.kind == "plain" or (#group.entries == 1 and not group.entries[1].valueText) then
            leftText = "  • " .. group.label
        elseif group.allSame and group.firstVal then
            leftText = string_format("  • %s (%s)", group.label, group.firstVal)
        elseif group.kind == "fraction" and group.sameMax and group.max then
            leftText = string_format("  • %s (/%d)", group.label, group.max)
        else
            leftText = "  • " .. group.label
        end
        AddCompactRow(tip, leftText, FormatGroupRightText(group), 0.78, 0.85, 0.92, 1, 1, 1)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Unit / Object Tooltip Party Quest Progress Condenser
-- ─────────────────────────────────────────────────────────────────────────────

local function Utf8Prefix(str, count)
    if type(str) ~= "string" or str == "" or count <= 0 then return "" end
    local len = #str
    local pos = 1
    local cp = 0
    while pos <= len and cp < count do
        local b = string_byte(str, pos)
        if not b then break end
        local charLen = (b >= 240 and 4) or (b >= 224 and 3) or (b >= 192 and 2) or 1
        pos = pos + charLen
        cp = cp + 1
    end
    return string_sub(str, 1, pos - 1)
end

local function SplitCharacterName(rawName)
    local clean = StripColorCodes(tostring(rawName or ""))
    clean = string_match(clean, "^([^%-]+)") or clean
    clean = string_gsub(clean, "^%s+", "")
    clean = string_gsub(clean, "%s+$", "")
    local fullLower = string_lower(clean)
    local firstLower = string_match(fullLower, "^(%S+)") or fullLower
    local secondLower = string_match(fullLower, "^%S+%s+(%S+)")
    return fullLower, firstLower, secondLower
end

local function BuildUniqueAbbreviations(players)
    local abbr = {}
    for i, p in ipairs(players) do
        abbr[i] = Utf8Prefix(p.first, 1)
    end

    local function countAbbrs()
        local counts = {}
        for i = 1, #players do
            local a = abbr[i]
            counts[a] = (counts[a] or 0) + 1
        end
        return counts
    end

    for len = 1, 4 do
        local counts = countAbbrs()
        local anyAdvanced = false
        for i, p in ipairs(players) do
            if counts[abbr[i]] > 1 then
                local longer = Utf8Prefix(p.first, len + 1)
                if longer ~= abbr[i] then
                    abbr[i] = longer
                    anyAdvanced = true
                end
            end
        end
        if not anyAdvanced then break end
    end

    local counts = countAbbrs()
    for i, p in ipairs(players) do
        if counts[abbr[i]] > 1 and p.second and p.second ~= "" then
            abbr[i] = Utf8Prefix(p.first, 1) .. Utf8Prefix(p.second, 1)
        end
    end

    local map = {}
    for i, p in ipairs(players) do
        map[p.key] = abbr[i] ~= "" and abbr[i] or "?"
    end
    return map
end
Tooltip.BuildUniqueAbbreviations = BuildUniqueAbbreviations

local function SpecTableToHex(t)
    if type(t) ~= "table" then return nil end
    local r = t[1] or t.r
    local g = t[2] or t.g
    local b = t[3] or t.b
    if not (r and g and b) then return nil end
    if sfui.colors and sfui.colors.rgb_to_hex then
        return "ff" .. sfui.colors.rgb_to_hex(r, g, b)
    end
    local ri = math_floor(r * 255 + 0.5)
    local gi = math_floor(g * 255 + 0.5)
    local bi = math_floor(b * 255 + 0.5)
    return string_format("ff%02x%02x%02x", ri, gi, bi)
end

local PARTY_UNIT_TOKENS = { "player", "party1", "party2", "party3", "party4" }

local function BuildPartyUnitCache()
    local byFull = {}
    local byFirst = {}
    local localName = nil
    local unitExists = _G.UnitExists
    local unitNameFn = _G.UnitName
    local unitGuidFn = _G.UnitGUID
    local unitClassFn = _G.UnitClass

    if unitExists and unitNameFn then
        for _, unit in ipairs(PARTY_UNIT_TOKENS) do
            local exists = unitExists(unit)
            if not issecretvalue(exists) and exists then
                local rawName = unitNameFn(unit)
                if IsSafeVal(rawName) and type(rawName) == "string" and rawName ~= "" then
                    local guid = unitGuidFn and unitGuidFn(unit) or nil
                    if issecretvalue(guid) then guid = nil end
                    local classFile = nil
                    if unitClassFn then
                        local _, cls = unitClassFn(unit)
                        if not issecretvalue(cls) and type(cls) == "string" then
                            classFile = cls
                        end
                    end
                    local fullLower, firstLower = SplitCharacterName(rawName)
                    if fullLower ~= "" then
                        local info = {
                            unit    = unit,
                            guid    = guid,
                            class   = classFile,
                            isLocal = (unit == "player"),
                        }
                        if not byFull[fullLower] then byFull[fullLower] = info end
                        if not byFirst[firstLower] then byFirst[firstLower] = info end
                        if unit == "player" then
                            localName = rawName
                        end
                    end
                end
            end
        end
    end

    return {
        byFull    = byFull,
        byFirst   = byFirst,
        localName = localName,
    }
end

local function FindAltByName(fullLower, firstLower)
    local alts = _G.SfuiDB and _G.SfuiDB.alts
    if type(alts) ~= "table" then return nil end

    local bestExact = nil
    local bestExactSeen = -1
    local bestFirst = nil
    local bestFirstSeen = -1

    for _, alt in pairs(alts) do
        if type(alt) == "table" then
            local candidateName = alt.fullName or alt.name
            if type(candidateName) == "string" and candidateName ~= "" then
                local aFull, aFirst = SplitCharacterName(candidateName)
                local seen = tonumber(alt.lastUpdate) or 0
                if aFull == fullLower and seen >= bestExactSeen then
                    bestExact = alt
                    bestExactSeen = seen
                elseif aFirst == firstLower and seen >= bestFirstSeen then
                    bestFirst = alt
                    bestFirstSeen = seen
                end
            end
        end
    end

    return bestExact or bestFirst
end

local function ResolvePlayerSpecHex(rawName, partyCache)
    local fullLower, firstLower = SplitCharacterName(rawName)
    local unitInfo = partyCache and ((partyCache.byFull and partyCache.byFull[fullLower]) or (partyCache.byFirst and partyCache.byFirst[firstLower]))
    local getSpecColor = sfui.colors and sfui.colors.get_spec_color_table
    local getClassColor = (sfui.colors and sfui.colors.get_class_color) or (sfui.common and sfui.common.get_class_color)

    if unitInfo and unitInfo.isLocal then
        local specID = sfui.talents and sfui.talents.get_current_spec_id and sfui.talents.get_current_spec_id()
        if specID and specID > 0 and getSpecColor then
            local hex = SpecTableToHex(getSpecColor(specID))
            if hex then return hex end
        end
        if unitInfo.class and getClassColor then
            return select(4, getClassColor(unitInfo.class))
        end
    end

    local alts = _G.SfuiDB and _G.SfuiDB.alts
    local alt = (unitInfo and unitInfo.guid and type(alts) == "table" and alts[unitInfo.guid])
        or FindAltByName(fullLower, firstLower)

    local altSpec = alt and tonumber(alt.spec)
    if altSpec and altSpec > 0 and getSpecColor then
        local hex = SpecTableToHex(getSpecColor(altSpec))
        if hex then return hex end
    end

    local classToken = (unitInfo and unitInfo.class) or (alt and alt.class)
    if classToken and getClassColor then
        return select(4, getClassColor(classToken))
    end

    return "ffcccccc"
end
Tooltip.ResolvePlayerSpecHex = ResolvePlayerSpecHex

local function IsPartyPlayerLineFallback(cleanText, nextLine, partyCache, LINE_QUEST_OBJ)
    if cleanText == "" then return false end
    if nextLine and not issecretvalue(nextLine) and not issecretvalue(nextLine.type) and nextLine.type == LINE_QUEST_OBJ then
        return true
    end
    local fullLower, firstLower = SplitCharacterName(cleanText)
    if partyCache and ((partyCache.byFull and partyCache.byFull[fullLower]) or (partyCache.byFirst and partyCache.byFirst[firstLower])) then
        return true
    end
    return false
end

local function ParseUnitQuestLines(lines, partyCache)
    local LINE_TYPE = _G.Enum and _G.Enum.TooltipDataLineType
    if not LINE_TYPE or type(lines) ~= "table" or #lines == 0 then return nil end

    local LINE_NONE = LINE_TYPE.None
    local LINE_QUEST_TITLE = LINE_TYPE.QuestTitle
    local LINE_QUEST_PLAYER = LINE_TYPE.QuestPlayer
    local LINE_QUEST_OBJ = LINE_TYPE.QuestObjective
    if not (LINE_QUEST_TITLE and LINE_QUEST_PLAYER and LINE_QUEST_OBJ) then return nil end

    local consumed = {}
    local players = {}
    local playerByKey = {}
    local objGroups = {}
    local objGroupByKey = {}
    local questSeq = 0
    local inQuestBlock = false
    local hasQuestPlayer = false
    local currentPlayer = (partyCache and partyCache.localName) or (_G.UnitName and _G.UnitName("player")) or "player"
    if issecretvalue(currentPlayer) or type(currentPlayer) ~= "string" or currentPlayer == "" then
        currentPlayer = "player"
    end

    local function ensurePlayer(rawName)
        local fullLower, firstLower, secondLower = SplitCharacterName(rawName)
        local pKey = fullLower ~= "" and fullLower or string_lower(tostring(rawName or "?"))
        if not playerByKey[pKey] then
            local rec = {
                key    = pKey,
                raw    = rawName,
                first  = firstLower ~= "" and firstLower or pKey,
                second = secondLower,
            }
            playerByKey[pKey] = rec
            players[#players + 1] = rec
        end
        return pKey
    end

    local function addObjEntry(pKey, parsed, isDone)
        if not parsed or parsed.key == "" then return end
        local gKey = tostring(questSeq) .. "|" .. parsed.key
        local g = objGroupByKey[gKey]
        if not g then
            g = {
                key         = parsed.key,
                label       = parsed.label,
                kind        = parsed.kind,
                max         = parsed.max,
                sameMax     = (parsed.max ~= nil),
                allSame     = true,
                firstVal    = parsed.valueText,
                entries     = {},
                seenPlayers = {},
            }
            objGroupByKey[gKey] = g
            objGroups[#objGroups + 1] = g
        elseif not g.seenPlayers[pKey] then
            if g.kind ~= parsed.kind then
                g.kind = "mixed"
                g.sameMax = false
            elseif g.max ~= parsed.max then
                g.sameMax = false
            end
            if g.firstVal ~= parsed.valueText then
                g.allSame = false
            end
        end
        if not g.seenPlayers[pKey] then
            g.seenPlayers[pKey] = true
            g.entries[#g.entries + 1] = {
                playerKey = pKey,
                valueText = parsed.valueText,
                shortVal  = parsed.shortVal,
                cur       = parsed.cur,
                completed = isDone == true,
            }
        end
    end

    for idx, line in ipairs(lines) do
        if issecretvalue(line) or type(line) ~= "table" then
            if inQuestBlock then return nil end
        else
            local ltype = line.type
            local isQuestTyped = not issecretvalue(ltype)
                and (ltype == LINE_QUEST_TITLE or ltype == LINE_QUEST_PLAYER or ltype == LINE_QUEST_OBJ)
            if (inQuestBlock or isQuestTyped) and (issecretvalue(ltype) or issecretvalue(line.leftText) or issecretvalue(line.completed)) then
                return nil
            end

            if not issecretvalue(ltype) then
                local rawText = not issecretvalue(line.leftText) and line.leftText or ""
                local cleanText = StripColorCodes(type(rawText) == "string" and rawText or "")
                cleanText = string_gsub(string_gsub(cleanText, "^%s+", ""), "%s+$", "")

                if ltype == LINE_QUEST_TITLE then
                    questSeq = questSeq + 1
                    inQuestBlock = true
                    currentPlayer = (partyCache and partyCache.localName) or currentPlayer
                    consumed[line] = true
                elseif inQuestBlock then
                    if ltype == LINE_QUEST_PLAYER then
                        currentPlayer = cleanText ~= "" and cleanText or currentPlayer
                        hasQuestPlayer = true
                        consumed[line] = true
                    elseif ltype == LINE_QUEST_OBJ then
                        local pKey = ensurePlayer(currentPlayer)
                        local parsed = ParseObjectiveProgress(cleanText)
                        local isDone = IsObjectiveFinished(cleanText, line.completed == true)
                        addObjEntry(pKey, parsed, isDone)
                        consumed[line] = true
                    elseif ltype == LINE_NONE or ltype == nil then
                        if IsPartyPlayerLineFallback(cleanText, lines[idx + 1], partyCache, LINE_QUEST_OBJ) then
                            currentPlayer = cleanText
                            hasQuestPlayer = true
                            consumed[line] = true
                        else
                            inQuestBlock = false
                        end
                    else
                        inQuestBlock = false
                    end
                end
            end
        end
    end

    if not hasQuestPlayer or #objGroups == 0 then
        return nil
    end

    return {
        consumed  = consumed,
        players   = players,
        objGroups = objGroups,
    }
end
Tooltip.ParseUnitQuestLines = ParseUnitQuestLines

local UNIT_PLAYER_SEP = " |cff888888·|r "

local function RenderCondensedUnitQuestLines(tip, state, partyCache)
    if not tip or not state or #state.objGroups == 0 then return end

    local abbrMap = BuildUniqueAbbreviations(state.players)
    local hexByKey = {}
    for _, p in ipairs(state.players) do
        hexByKey[p.key] = ResolvePlayerSpecHex(p.raw, partyCache)
    end

    local function coloredTag(pKey)
        local hex = hexByKey[pKey] or "ffcccccc"
        local abbr = abbrMap[pKey] or "?"
        return string_format("|c%s%s|r", hex, abbr)
    end

    for _, group in ipairs(state.objGroups) do
        local allDone = true
        local anyDone = false
        for _, e in ipairs(group.entries) do
            if e.completed then
                anyDone = true
            else
                allDone = false
            end
        end

        local allSameUnfinished = (not anyDone) and group.allSame and (group.firstVal ~= nil)
        local lr, lg, lb = 1.00, 0.85, 0.35
        if allDone then
            lr, lg, lb = 0.40, 0.90, 0.45
        end

        local leftText
        local rightText
        if allDone then
            leftText = (group.firstVal and group.allSame)
                and string_format("%s (%s)", group.label, group.firstVal)
                or group.label
            local tags = {}
            for i, e in ipairs(group.entries) do
                tags[i] = coloredTag(e.playerKey)
            end
            rightText = table_concat(tags, UNIT_PLAYER_SEP) .. " " .. ICON_DONE
        elseif group.kind == "plain" then
            leftText = group.label
            local parts = {}
            for i, e in ipairs(group.entries) do
                parts[i] = e.completed and (coloredTag(e.playerKey) .. " " .. ICON_DONE) or coloredTag(e.playerKey)
            end
            rightText = table_concat(parts, UNIT_PLAYER_SEP)
        elseif allSameUnfinished then
            leftText = string_format("%s (%s)", group.label, group.firstVal)
            local tags = {}
            for i, e in ipairs(group.entries) do
                tags[i] = coloredTag(e.playerKey)
            end
            rightText = table_concat(tags, UNIT_PLAYER_SEP)
        elseif #group.entries == 1 then
            local e = group.entries[1]
            if e.completed then
                leftText = group.label
                rightText = coloredTag(e.playerKey) .. " " .. ICON_DONE
            else
                leftText = e.valueText and string_format("%s (%s)", group.label, e.valueText) or group.label
                rightText = coloredTag(e.playerKey)
            end
        else
            local useShort = (group.kind == "fraction" and group.sameMax and group.max ~= nil)
            if useShort then
                leftText = string_format("%s (/%d)", group.label, group.max)
            else
                leftText = group.label
            end
            local parts = {}
            for i, e in ipairs(group.entries) do
                local tag = coloredTag(e.playerKey)
                if e.completed then
                    parts[i] = tag .. " " .. ICON_DONE
                else
                    local val = useShort and (e.shortVal or e.valueText or "") or (e.valueText or "")
                    if val ~= "" then
                        parts[i] = tag .. " |cffffffff" .. val .. "|r"
                    else
                        parts[i] = tag
                    end
                end
            end
            rightText = table_concat(parts, UNIT_PLAYER_SEP)
        end

        AddCompactRow(tip, leftText, rightText, lr, lg, lb, 1, 1, 1)
    end
end
Tooltip.RenderCondensedUnitQuestLines = RenderCondensedUnitQuestLines

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

        -- Objective lines (exclude synced peer lines injected into tracker blocks)
        if not bData.isRemotePeerQuest then
            local localObjs = {}
            local function pushLocalObj(text, done)
                if text and text ~= "" and not issecretvalue(text) then
                    localObjs[#localObjs + 1] = { text = tostring(text), done = (done == true) }
                end
            end

            if bData.lines and #bData.lines > 0 then
                for _, line in ipairs(bData.lines) do
                    if not line.isSynced then
                        pushLocalObj(line.text, line.completed)
                    end
                end
            end

            if #localObjs == 0 and _G.C_QuestLog and _G.C_QuestLog.GetQuestObjectives then
                local objs = _G.C_QuestLog.GetQuestObjectives(bData.questID)
                if objs and #objs > 0 then
                    for _, obj in ipairs(objs) do
                        pushLocalObj(obj.text, obj.finished)
                    end
                end
            end

            if #localObjs == 0 and bData.questLogIndex and _G.GetNumQuestLeaderBoards and _G.GetQuestLogLeaderBoard then
                local numObj = _G.GetNumQuestLeaderBoards(bData.questLogIndex)
                if IsSafeVal(numObj) and type(numObj) == "number" and numObj > 0 then
                    for objIndex = 1, numObj do
                        local desc, _, isFinished = _G.GetQuestLogLeaderBoard(objIndex, bData.questLogIndex)
                        pushLocalObj(desc, isFinished)
                    end
                end
            end

            if #localObjs > 0 then
                tip:AddLine(" ")
                for _, item in ipairs(localObjs) do
                    local r, g, b = 0.75, 0.75, 0.75
                    if item.done then r, g, b = 0.30, 0.80, 0.30 end
                    tip:AddLine("  " .. (item.done and ICON_CHECK or ICON_BULLET) .. item.text, r, g, b, true)
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

        -- Synced Party / Linked Peer Progress (computed first to avoid duplicating Blizzard party progress)
        local syncSummary = nil
        if bData.questID and sfui.sync and sfui.sync.GetQuestPeerStatuses then
            local peerStatuses = sfui.sync.GetQuestPeerStatuses(bData.questID, false)
            local reqClass = bData.isClassQuest and bData.classToken or nil
            syncSummary = BuildSyncedPeerSummary(peerStatuses, reqClass, bData.isRemotePeerQuest == true, isComplete == true)
        end

        local skipBlizzPartyProgress = false
        if syncSummary and syncSummary.syncedInPartyCount > 0 and not (_G.IsInRaid and _G.IsInRaid()) then
            local otherPartyMembers = 0
            if _G.GetNumSubgroupMembers then
                local sub = _G.GetNumSubgroupMembers()
                if IsSafeVal(sub) and type(sub) == "number" then
                    otherPartyMembers = sub
                end
            elseif _G.GetNumGroupMembers then
                local grp = _G.GetNumGroupMembers()
                if IsSafeVal(grp) and type(grp) == "number" and grp > 1 then
                    otherPartyMembers = grp - 1
                end
            end
            if otherPartyMembers > 0 and syncSummary.syncedInPartyCount >= otherPartyMembers then
                skipBlizzPartyProgress = true
            end
        end

        -- Group Party Progress (only when non-synced party/raid members exist)
        if not skipBlizzPartyProgress and not bData.isRemotePeerQuest and IsSafeVal(bData.questID) and _G.IsInGroup and _G.IsInGroup() and tip.SetQuestPartyProgress then
            tip:SetQuestPartyProgress(bData.questID)
        end

        if syncSummary and syncSummary.hasAny then
            AppendSyncedPeersSection(tip, syncSummary, bData.isRemotePeerQuest == true, isComplete == true)
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

local pendingUnitCondensed = setmetatable({}, { __mode = "k" })
local _unitQuestHooked = false

local function InitUnitQuestTooltipCondenser()
    if _unitQuestHooked then return end
    local dp = _G.TooltipDataProcessor
    local dt = _G.Enum and _G.Enum.TooltipDataType
    local lt = _G.Enum and _G.Enum.TooltipDataLineType
    if not (dp and dp.AddTooltipPreCall and dp.AddLinePreCall and dp.AddTooltipPostCall and dt and lt) then
        return
    end
    if not (lt.QuestTitle and lt.QuestPlayer and lt.QuestObjective) then
        return
    end
    _unitQuestHooked = true

    local function onPreUnitOrObject(tooltip, tooltipData)
        pendingUnitCondensed[tooltip] = nil
        if tooltip ~= _G.GameTooltip or not tooltipData or issecretvalue(tooltipData) then
            return false
        end
        if issecretvalue(tooltipData.lines) or type(tooltipData.lines) ~= "table" then
            return false
        end
        local partyCache = BuildPartyUnitCache()
        local state = ParseUnitQuestLines(tooltipData.lines, partyCache)
        if state then
            pendingUnitCondensed[tooltip] = {
                state      = state,
                partyCache = partyCache,
            }
        end
        return false
    end

    local function onLinePreCall(tooltip, lineData)
        local pending = pendingUnitCondensed[tooltip]
        if pending and pending.state and pending.state.consumed[lineData] then
            return true
        end
        return false
    end

    local function onPostUnitOrObject(tooltip)
        local pending = pendingUnitCondensed[tooltip]
        pendingUnitCondensed[tooltip] = nil
        if pending and pending.state then
            RenderCondensedUnitQuestLines(tooltip, pending.state, pending.partyCache)
        end
    end

    for _, tipType in ipairs({ dt.Unit, dt.Object }) do
        if tipType then
            dp.AddTooltipPreCall(tipType, onPreUnitOrObject)
            dp.AddTooltipPostCall(tipType, onPostUnitOrObject)
        end
    end

    for _, lineType in ipairs({ lt.QuestTitle, lt.QuestPlayer, lt.QuestObjective, lt.None }) do
        if lineType ~= nil then
            dp.AddLinePreCall(lineType, onLinePreCall)
        end
    end

    local gameTip = _G.GameTooltip
    if gameTip and gameTip.HookScript then
        gameTip:HookScript("OnTooltipCleared", function(self)
            pendingUnitCondensed[self] = nil
        end)
    end
end
Tooltip.InitUnitQuestTooltipCondenser = InitUnitQuestTooltipCondenser
InitUnitQuestTooltipCondenser()

return Tooltip
