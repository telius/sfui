local addonName, addon = ...
sfui = sfui or {}
sfui.inventory = sfui.inventory or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/core/inventory.lua
--  single-pass incremental bag & equipment delta index (`sfui.inventory`).
--  tracks dirty bag ids via `BAG_UPDATE(bagID)`, rescans only dirty bags on
--  `BAG_UPDATE_DELAYED`, maintains o(1) item counts/slots/equipped/quest/gear
--  tables, and broadcasts `SFUI_INVENTORY_DELTA` & `SFUI_EQUIPMENT_DELTA`.
-- ══════════════════════════════════════════════════════════════════════════════

local _G = _G
local pairs = _G.pairs
local type = _G.type
local wipe = _G.wipe or table.wipe
local C_Container = _G.C_Container
local C_Item = _G.C_Item
local GetInventoryItemID = _G.GetInventoryItemID
local GetInventoryItemLink = _G.GetInventoryItemLink
local GetInventoryItemTexture = _G.GetInventoryItemTexture
local GetInventoryItemQuality = _G.GetInventoryItemQuality

local issecretvalue = (sfui.common and sfui.common.issecretvalue) or _G.issecretvalue or function() return false end

local INV = sfui.inventory
INV.hidden = true

local MAX_BAG_ID = (_G.Enum and _G.Enum.BagIndex and _G.Enum.BagIndex.ReagentBag) or (_G.NUM_TOTAL_EQUIPPED_BAG_SLOTS) or (_G.NUM_BAG_SLOTS) or 4
if type(MAX_BAG_ID) ~= "number" or MAX_BAG_ID < 4 then
    MAX_BAG_ID = 4
end

local _initialized = false
local _dirtyAllBags = true
local _dirtyBags = {}
local _revision = 0

-- Per-bag caches: _bagCounts[bag][itemID] = count, _bagEntries[bag] = { entry1, ... }
local _bagCounts = {}
local _bagEntries = {}
local _entryPool = {}

-- Canonical aggregated O(1) indexes
local countsByItemID = {}
local equippedCountsByItemID = {}
local equippedBySlot = {}
local firstSlotByItemID = {}
local questItems = {}
local equippableItems = {}
local _changedItems = {}
local _touchedItems = {}
local _debugInfo = {}

local function AcquireEntry()
    local n = #_entryPool
    if n > 0 then
        local e = _entryPool[n]
        _entryPool[n] = nil
        return e
    end
    return {}
end

local function ReleaseBagEntries(list)
    if not list then return end
    for i = #list, 1, -1 do
        local e = list[i]
        list[i] = nil
        if e then
            wipe(e)
            _entryPool[#_entryPool + 1] = e
        end
    end
end

local function GetNumBagSlots(bagID)
    if C_Container and C_Container.GetContainerNumSlots then
        local n = C_Container.GetContainerNumSlots(bagID)
        if not issecretvalue(n) and type(n) == "number" and n > 0 then
            return n
        end
        return 0
    elseif _G.GetContainerNumSlots then
        local n = _G.GetContainerNumSlots(bagID)
        if type(n) == "number" and n > 0 then
            return n
        end
    end
    return 0
end

local function ReadSlotInfo(bagID, slotID)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bagID, slotID)
        if not issecretvalue(info) and info then
            local itemID = info.itemID
            if issecretvalue(itemID) or type(itemID) ~= "number" or itemID <= 0 then
                return nil
            end
            local stack = info.stackCount
            if issecretvalue(stack) or type(stack) ~= "number" or stack < 1 then
                stack = 1
            end
            local link = (not issecretvalue(info.hyperlink) and info.hyperlink) or nil
            local icon = (not issecretvalue(info.iconFileID) and info.iconFileID) or nil
            local quality = (not issecretvalue(info.quality) and info.quality) or nil
            local isQuestItem = false
            local startQuestID = nil
            local isActiveQuest = false
            if C_Container.GetContainerItemQuestInfo then
                local qi = C_Container.GetContainerItemQuestInfo(bagID, slotID)
                if not issecretvalue(qi) and qi then
                    isQuestItem = (not issecretvalue(qi.isQuestItem) and qi.isQuestItem == true) or false
                    startQuestID = (not issecretvalue(qi.questID) and qi.questID) or nil
                    isActiveQuest = (not issecretvalue(qi.isActive) and qi.isActive == true) or false
                end
            end
            return itemID, stack, link, icon, quality, isQuestItem, startQuestID, isActiveQuest
        end
        return nil
    elseif _G.GetContainerItemInfo then
        local icon, itemCount, _, quality, _, _, itemLink, _, _, itemID = _G.GetContainerItemInfo(bagID, slotID)
        if not itemID and itemLink and sfui.items and sfui.items.get_item_id then
            itemID = sfui.items.get_item_id(itemLink)
        end
        if type(itemID) ~= "number" or itemID <= 0 then
            return nil
        end
        local isQuestItem, startQuestID, isActiveQuest = false, nil, false
        if _G.GetContainerItemQuestInfo then
            local qItem, qID, qActive = _G.GetContainerItemQuestInfo(bagID, slotID)
            isQuestItem = qItem == true
            startQuestID = qID
            isActiveQuest = qActive == true
        end
        return itemID, (type(itemCount) == "number" and itemCount > 0 and itemCount) or 1, itemLink, icon, quality, isQuestItem, startQuestID, isActiveQuest
    end
    return nil
end

local function ResolveEquipLocAndQuestClass(itemID, link)
    local equipLoc = nil
    local classID = nil
    if sfui.items and sfui.items.get_item_instant_info then
        local _, _, _, eqLoc, _, cID = sfui.items.get_item_instant_info(link or itemID)
        if not issecretvalue(eqLoc) and type(eqLoc) == "string" and eqLoc ~= "" and eqLoc ~= "INVTYPE_NON_EQUIP" and eqLoc ~= "INVTYPE_NON_EQUIP_IGNORE" and eqLoc ~= "INVTYPE_BAG" then
            equipLoc = eqLoc
        end
        if not issecretvalue(cID) and type(cID) == "number" then
            classID = cID
        end
    end
    return equipLoc, classID
end

local function ScanSingleBag(bagID)
    local prevCounts = _bagCounts[bagID]
    if not prevCounts then
        prevCounts = {}
        _bagCounts[bagID] = prevCounts
    end
    for itemID, oldBagCount in pairs(prevCounts) do
        local cur = (countsByItemID[itemID] or 0) - oldBagCount
        countsByItemID[itemID] = (cur > 0) and cur or nil
        _touchedItems[itemID] = oldBagCount
        prevCounts[itemID] = nil
    end

    local entries = _bagEntries[bagID]
    if not entries then
        entries = {}
        _bagEntries[bagID] = entries
    else
        ReleaseBagEntries(entries)
    end

    local numSlots = GetNumBagSlots(bagID)
    for slotID = 1, numSlots do
        local itemID, stack, link, icon, quality, isQuestItem, startQuestID, isActiveQuest = ReadSlotInfo(bagID, slotID)
        if itemID then
            if _touchedItems[itemID] == nil then
                _touchedItems[itemID] = 0
            end
            prevCounts[itemID] = (prevCounts[itemID] or 0) + stack
            countsByItemID[itemID] = (countsByItemID[itemID] or 0) + stack

            local equipLoc, classID = ResolveEquipLocAndQuestClass(itemID, link)
            local isQuest = isQuestItem or (startQuestID ~= nil) or (classID == 12)

            local entry = AcquireEntry()
            entry.bag = bagID
            entry.slot = slotID
            entry.itemID = itemID
            entry.count = stack
            entry.link = link
            entry.icon = icon
            entry.quality = quality
            entry.equipLoc = equipLoc
            entry.isQuest = isQuest
            entry.startQuestID = startQuestID
            entry.isActiveQuest = isActiveQuest
            entries[#entries + 1] = entry
        end
    end
end

local function RebuildDerivedBagViews()
    wipe(firstSlotByItemID)
    for i = #questItems, 1, -1 do questItems[i] = nil end
    for i = #equippableItems, 1, -1 do equippableItems[i] = nil end

    for bagID = 0, MAX_BAG_ID do
        local entries = _bagEntries[bagID]
        if entries then
            for i = 1, #entries do
                local e = entries[i]
                local id = e.itemID
                if not firstSlotByItemID[id] then
                    firstSlotByItemID[id] = e
                end
                if e.isQuest then
                    questItems[#questItems + 1] = e
                end
                if e.equipLoc then
                    equippableItems[#equippableItems + 1] = e
                end
            end
        end
    end
end

local function RefreshEquippedSlot(slotID)
    if issecretvalue(slotID) or type(slotID) ~= "number" or slotID < 0 or slotID > 19 then
        return nil, nil
    end
    local prev = equippedBySlot[slotID]
    local oldID = prev and prev.itemID or nil
    if oldID then
        local c = (equippedCountsByItemID[oldID] or 0) - 1
        equippedCountsByItemID[oldID] = (c > 0) and c or nil
    end

    local newID = GetInventoryItemID and GetInventoryItemID("player", slotID) or nil
    if issecretvalue(newID) or type(newID) ~= "number" or newID <= 0 then
        newID = nil
    end

    if newID then
        if not prev then
            prev = {}
            equippedBySlot[slotID] = prev
        end
        local link = (sfui.items and sfui.items.get_inventory_item_link and sfui.items.get_inventory_item_link("player", slotID))
            or (GetInventoryItemLink and GetInventoryItemLink("player", slotID))
            or nil
        if issecretvalue(link) then link = nil end
        local icon = GetInventoryItemTexture and GetInventoryItemTexture("player", slotID) or nil
        if issecretvalue(icon) then icon = nil end
        local quality = GetInventoryItemQuality and GetInventoryItemQuality("player", slotID) or nil
        if issecretvalue(quality) then quality = nil end
        local equipLoc = ResolveEquipLocAndQuestClass(newID, link)

        prev.slot = slotID
        prev.itemID = newID
        prev.link = link
        prev.icon = icon
        prev.quality = quality
        prev.equipLoc = equipLoc
        equippedCountsByItemID[newID] = (equippedCountsByItemID[newID] or 0) + 1
    elseif prev then
        wipe(prev)
        equippedBySlot[slotID] = nil
    end

    return oldID, newID
end

local function ScanAllEquipment()
    wipe(equippedCountsByItemID)
    for slotID = 0, 19 do
        RefreshEquippedSlot(slotID)
    end
end

local function FlushDirtyBags(broadcast)
    wipe(_changedItems)
    wipe(_touchedItems)

    -- Capture pre-scan totals for dirty bags so multi-bag stack moves compute exact net delta
    local preTotals = {}
    if _dirtyAllBags then
        for id, cnt in pairs(countsByItemID) do
            preTotals[id] = cnt
        end
        for bagID = 0, MAX_BAG_ID do
            ScanSingleBag(bagID)
        end
        _dirtyAllBags = false
        wipe(_dirtyBags)
    else
        local anyBag = false
        for bagID in pairs(_dirtyBags) do
            anyBag = true
            local bagMap = _bagCounts[bagID]
            if bagMap then
                for id in pairs(bagMap) do
                    if preTotals[id] == nil then
                        preTotals[id] = countsByItemID[id] or 0
                    end
                end
            end
        end
        if not anyBag then return false end
        for bagID in pairs(_dirtyBags) do
            _dirtyBags[bagID] = nil
            ScanSingleBag(bagID)
        end
    end

    RebuildDerivedBagViews()

    local hasDelta = false
    for itemID in pairs(_touchedItems) do
        local before = preTotals[itemID] or 0
        local after = countsByItemID[itemID] or 0
        if before ~= after then
            _changedItems[itemID] = after
            hasDelta = true
        end
    end

    _revision = _revision + 1
    if broadcast and sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_INVENTORY_DELTA", _changedItems, false, _revision)
    end
    return hasDelta
end

local function EnsureInitialized()
    if _initialized then return end
    _initialized = true
    _dirtyAllBags = true
    ScanAllEquipment()
    FlushDirtyBags(false)
end

-- ─── Public O(1) Read API ────────────────────────────────────────────────────

function INV.GetCount(itemID, includeEquipped)
    if issecretvalue(itemID) or not itemID then return 0 end
    if type(itemID) ~= "number" and sfui.items and sfui.items.get_item_id then
        itemID = sfui.items.get_item_id(itemID)
    end
    if type(itemID) ~= "number" or itemID <= 0 then return 0 end
    EnsureInitialized()
    local total = countsByItemID[itemID] or 0
    if includeEquipped then
        total = total + (equippedCountsByItemID[itemID] or 0)
    end
    if total == 0 and C_Item and C_Item.GetItemCount and _dirtyAllBags then
        local fb = C_Item.GetItemCount(itemID, false, false, false, false)
        if not issecretvalue(fb) and type(fb) == "number" then
            return fb
        end
    end
    return total
end

function INV.GetFirstSlot(itemID)
    if issecretvalue(itemID) or type(itemID) ~= "number" then return nil end
    EnsureInitialized()
    return firstSlotByItemID[itemID]
end

function INV.GetEquipped(slotID)
    if issecretvalue(slotID) or type(slotID) ~= "number" then return nil end
    EnsureInitialized()
    return equippedBySlot[slotID]
end

function INV.GetEquippedLink(slotID)
    if issecretvalue(slotID) or type(slotID) ~= "number" then return nil end
    EnsureInitialized()
    local entry = equippedBySlot[slotID]
    return entry and entry.link or nil
end

function INV.IsEquipped(itemID)
    if issecretvalue(itemID) or type(itemID) ~= "number" then return false end
    EnsureInitialized()
    return (equippedCountsByItemID[itemID] or 0) > 0
end

function INV.GetQuestItems()
    EnsureInitialized()
    return questItems
end

function INV.GetEquippableItems()
    EnsureInitialized()
    return equippableItems
end

function INV.GetAllBagCounts()
    EnsureInitialized()
    return countsByItemID
end

function INV.GetRevision()
    EnsureInitialized()
    return _revision
end

function INV.ForceRescan()
    _initialized = true
    _dirtyAllBags = true
    ScanAllEquipment()
    FlushDirtyBags(true)
end

function INV.GetDebugInfo()
    local uniqueItems = 0
    for _ in pairs(countsByItemID) do uniqueItems = uniqueItems + 1 end
    _debugInfo.revision = _revision
    _debugInfo.uniqueBagItems = uniqueItems
    _debugInfo.questItems = #questItems
    _debugInfo.equippableBagItems = #equippableItems
    _debugInfo.pooledEntries = #_entryPool
    return _debugInfo
end

-- ─── Event Wiring ────────────────────────────────────────────────────────────

if sfui.events then
    sfui.events.RegisterEvent("BAG_UPDATE", function(_, bagID)
        if not issecretvalue(bagID) and type(bagID) == "number" and bagID >= 0 and bagID <= MAX_BAG_ID then
            _dirtyBags[bagID] = true
        else
            _dirtyAllBags = true
        end
    end)

    sfui.events.RegisterEvent("BAG_UPDATE_DELAYED", function()
        if not _initialized then
            EnsureInitialized()
            if sfui.events.SendMessage then
                sfui.events.SendMessage("SFUI_INVENTORY_READY", _revision)
                sfui.events.SendMessage("SFUI_INVENTORY_DELTA", _changedItems, false, _revision)
            end
            return
        end
        FlushDirtyBags(true)
    end)

    sfui.events.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function(_, slotID)
        EnsureInitialized()
        local oldID, newID = RefreshEquippedSlot(slotID)
        if oldID ~= newID then
            wipe(_changedItems)
            if oldID then _changedItems[oldID] = countsByItemID[oldID] or 0 end
            if newID then _changedItems[newID] = countsByItemID[newID] or 0 end
            _revision = _revision + 1
            if sfui.events.SendMessage then
                sfui.events.SendMessage("SFUI_EQUIPMENT_DELTA", slotID, oldID, newID, _revision)
                sfui.events.SendMessage("SFUI_INVENTORY_DELTA", _changedItems, true, _revision)
            end
        end
    end)

    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        _initialized = true
        _dirtyAllBags = true
        ScanAllEquipment()
        FlushDirtyBags(false)
        if sfui.events.SendMessage then
            sfui.events.SendMessage("SFUI_INVENTORY_READY", _revision)
        end
    end)
end

if sfui.RegisterModule then
    sfui.RegisterModule("inventory", INV)
end

