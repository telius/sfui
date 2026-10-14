local addonName, addon = ...
sfui = sfui or {}
sfui.ring = sfui.ring or {}

local C_Container             = _G.C_Container
local C_Item                  = _G.C_Item
local C_QuestLog              = _G.C_QuestLog
local GetQuestLogSpecialItemInfo = _G.GetQuestLogSpecialItemInfo
local GetNumQuestLogEntries   = _G.GetNumQuestLogEntries
local UseQuestLogSpecialItem  = _G.UseQuestLogSpecialItem
local InCombatLockdown        = _G.InCombatLockdown
local GetTime                 = _G.GetTime
local tonumber                = _G.tonumber
local tostring                = _G.tostring
local table_sort              = table.sort
local table_wipe              = _G.wipe or table.wipe or function(t) for k in pairs(t) do t[k] = nil end end

local function get_container_quest_info(bag, slot)
    if C_Container and C_Container.GetContainerItemQuestInfo then
        local iqi = C_Container.GetContainerItemQuestInfo(bag, slot)
        if iqi then
            return iqi.isQuestItem, iqi.questID, iqi.isActive
        end
    end
    return false, nil, false
end

local function is_quest_completed(questID)
    if not questID then return false end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        return C_QuestLog.IsQuestFlaggedCompleted(questID)
    end
    return false
end

local function get_quest_distance(questID)
    if questID and C_QuestLog and C_QuestLog.GetDistanceSqToQuest then
        local distSq, onContinent = C_QuestLog.GetDistanceSqToQuest(questID)
        if distSq and onContinent then
            return distSq
        end
    end
    return 999999999
end

local cachedResult = {}
local lastScanTime = 0

sfui.ring.register_provider("questitems", {
    name   = "quest items",
    title  = "quest items",
    events = { "QUEST_LOG_UPDATE", "BAG_UPDATE_DELAYED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" },
    build  = function(out)
        -- in combat: never perform heavy 180-slot bag scanning or map distance queries
        if InCombatLockdown and InCombatLockdown() then
            for i = 1, #cachedResult do
                out[#out + 1] = cachedResult[i]
            end
            return
        end

        -- throttle out-of-combat scans to at most once per 2.0s
        local now = GetTime()
        if (now - lastScanTime) < 2.0 and #cachedResult > 0 then
            for i = 1, #cachedResult do
                out[#out + 1] = cachedResult[i]
            end
            return
        end
        lastScanTime = now

        local seen = {}
        local items = {}

        -- 1. scan player bags for usable quest items or items that start quests
        local maxBags = (sfui.isRetail or (select(4, _G.GetBuildInfo()) >= 100000)) and 5 or 4
        if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID then
            for bag = 0, maxBags do
                local numSlots = C_Container.GetContainerNumSlots(bag) or 0
                for slot = 1, numSlots do
                    local itemID = C_Container.GetContainerItemID(bag, slot)
                    if itemID and not seen[itemID] then
                        local isQuest, startQuestID, isQuestActive = get_container_quest_info(bag, slot)
                        local hasSpell = C_Item and C_Item.GetItemSpell and C_Item.GetItemSpell(itemID)
                        local startsQuest = startQuestID and not isQuestActive and not is_quest_completed(startQuestID)

                        if (isQuest and hasSpell) or startsQuest then
                            seen[itemID] = true
                            local itemName = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)) or ("item " .. itemID)
                            local itemIcon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)) or 134400
                            local count = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(itemID)) or 1
                            local dist = startQuestID and get_quest_distance(startQuestID) or 900000000

                            items[#items + 1] = {
                                id       = "qi_" .. itemID,
                                itemID   = itemID,
                                label    = itemName:lower(),
                                icon     = itemIcon,
                                count    = count,
                                dist     = dist,
                                attrs    = {
                                    type = "item",
                                    item = "item:" .. itemID,
                                },
                            }
                        end
                    end
                end
            end
        end

        -- 2. scan quest log for quest special action items
        local numQuests = 0
        if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
            numQuests = C_QuestLog.GetNumQuestLogEntries()
        elseif GetNumQuestLogEntries then
            numQuests = GetNumQuestLogEntries()
        end

        if GetQuestLogSpecialItemInfo then
            for i = 1, numQuests do
                local qInfo
                if C_QuestLog and C_QuestLog.GetInfo then
                    qInfo = C_QuestLog.GetInfo(i)
                end

                local isHeader = qInfo and qInfo.isHeader
                local isComplete = qInfo and qInfo.isComplete
                local questID = qInfo and qInfo.questID

                if not isHeader then
                    local link, icon, charges, showWhenComplete = GetQuestLogSpecialItemInfo(i)
                    if link and (showWhenComplete or not isComplete) then
                        local itemID = tonumber(link:match("item:(%d+)"))
                        if itemID and not seen[itemID] then
                            seen[itemID] = true
                            local rawName = link:match("%[(.-)%]") or ("quest item " .. itemID)
                            local dist = get_quest_distance(questID)

                            local qIndex = i
                            items[#items + 1] = {
                                id            = "qi_" .. itemID,
                                itemID        = itemID,
                                label         = rawName:lower(),
                                icon          = icon,
                                count         = charges or 0,
                                dist          = dist,
                                attrs         = {
                                    type = "item",
                                    item = "item:" .. itemID,
                                },
                                insecure_func = function()
                                    if UseQuestLogSpecialItem and qIndex then
                                        UseQuestLogSpecialItem(qIndex)
                                    end
                                end,
                            }
                        end
                    end
                end
            end
        end

        -- 3. sort items: nearest quest first
        table_sort(items, function(a, b)
            if a.dist ~= b.dist then
                return a.dist < b.dist
            end
            return a.label < b.label
        end)

        -- 4. emit to output (cap at 12 nearest items to prevent clutter) and update cache
        table_wipe(cachedResult)
        local cap = 12
        for i = 1, math.min(#items, cap) do
            cachedResult[#cachedResult + 1] = items[i]
            out[#out + 1] = items[i]
        end
    end,
})
