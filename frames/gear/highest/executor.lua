local addonName, addon = ...
sfui.highest = sfui.highest or {}

local _G = _G
local common = sfui.common
local C_Item = _G.C_Item
local C_Container = _G.C_Container
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local pairs = _G.pairs
local ipairs = _G.ipairs
local string = _G.string
local table = _G.table
local tonumber = _G.tonumber
local tostring = _G.tostring
local type = _G.type

local BOE_RETRY_DELAY = 30 -- seconds before re-offering the bind dialog
local boeAttemptedAt = sfui.highest.boeAttemptedAt or {}
sfui.highest.boeAttemptedAt = boeAttemptedAt

local function sfprint(msg)
    sfui.common.print(msg)
end

local GetInventoryItemLink = sfui.common.get_inventory_item_link

local C_Container_GetContainerItemInfo = (_G.C_Container and _G.C_Container.GetContainerItemInfo) or _G.GetContainerItemInfo
local C_Container_GetContainerItemLink = (_G.C_Container and _G.C_Container.GetContainerItemLink) or _G.GetContainerItemLink
local C_Container_PickupContainerItem  = (_G.C_Container and _G.C_Container.PickupContainerItem) or _G.PickupContainerItem

local function EquipItemByName(itemInfo, slotID, bag, slot)
    if not itemInfo then return end
    if _G.InCombatLockdown and _G.InCombatLockdown() then return end

    -- Slot 0 (INVSLOT_AMMO) cannot be used as dstSlot in EquipItemByName (causes "Invalid inventory dstSlot").
    if slotID == 0 or slotID == "0" then
        if bag and slot then
            if C_Container and C_Container.UseContainerItem then
                C_Container.UseContainerItem(bag, slot)
                return
            elseif _G.UseContainerItem then
                _G.UseContainerItem(bag, slot)
                return
            end
        end
        if sfui.common and sfui.common.for_each_bag_item then
            local foundBag, foundSlot
            sfui.common.for_each_bag_item(function(b, s, id, link)
                if link == itemInfo or id == itemInfo then
                    foundBag, foundSlot = b, s
                    return true
                end
            end, true, true, false)
            if foundBag and foundSlot then
                if C_Container and C_Container.UseContainerItem then
                    C_Container.UseContainerItem(foundBag, foundSlot)
                elseif _G.UseContainerItem then
                    _G.UseContainerItem(foundBag, foundSlot)
                end
                return
            end
        end
        return
    end

    local validSlotID = (type(slotID) == "number" and slotID >= 1 and slotID <= 19) and slotID or nil

    if C_Item and C_Item.EquipItemByName then
        if validSlotID then
            C_Item.EquipItemByName(itemInfo, validSlotID)
        else
            C_Item.EquipItemByName(itemInfo)
        end
    elseif _G.C_Item and _G.C_Item.EquipItemByName then
        if validSlotID then
            _G.C_Item.EquipItemByName(itemInfo, validSlotID)
        else
            _G.C_Item.EquipItemByName(itemInfo)
        end
    elseif _G.EquipItemByName then
        if validSlotID then
            _G.EquipItemByName(itemInfo, validSlotID)
        else
            _G.EquipItemByName(itemInfo)
        end
    elseif bag and slot then
        if C_Container and C_Container.UseContainerItem then
            C_Container.UseContainerItem(bag, slot)
        elseif _G.UseContainerItem then
            _G.UseContainerItem(bag, slot)
        end
    end
end
sfui.highest.EquipItemByName = EquipItemByName

-- ══════════════════════════════════════════════════════════════════════════════
-- Fishing Pole Safety
-- ══════════════════════════════════════════════════════════════════════════════
function sfui.highest.IsFishingPoleItem(itemID, itemLink)
    return sfui.fishing.IsFishingPoleItem(itemID, itemLink)
end
sfui.gear = sfui.gear or {}
sfui.gear.IsFishingPoleItem = sfui.highest.IsFishingPoleItem

function sfui.highest.IsFishingPoleEquipped()
    return sfui.fishing.IsFishingPoleEquipped()
end
sfui.gear.IsFishingPoleEquipped = sfui.highest.IsFishingPoleEquipped

-- ══════════════════════════════════════════════════════════════════════════════
-- Equip Execution Pipeline
-- ══════════════════════════════════════════════════════════════════════════════
local isEquippingInProgress = false
local pendingEquipRequest   = nil

function sfui.highest.EquipHighestILvl(isPvP, silent)
    if silent and sfui.gear and sfui.gear.isNakedPaused and sfui.gear.isNakedPaused() then
        return
    end

    local inCombat = _G.InCombatLockdown and _G.InCombatLockdown()
    if inCombat then
        if not silent then sfprint("cannot equip gear while in combat.") end
        return
    end

    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
        if not silent then sfprint("cannot equip gear while dead or ghost.") end
        return
    end

    -- Mutex lock: if an equip sequence is already actively swapping items, queue a follow-up request instead of spawning parallel loops
    if isEquippingInProgress then
        pendingEquipRequest = { isPvP = isPvP, silent = silent }
        return
    end

    local best = sfui.highest.GetBestItems(isPvP)
    if not best then return end

    local isFishingPole = sfui.highest.IsFishingPoleEquipped()
    local isFishingSession = (sfui.fishing and sfui.fishing.IsSessionActive and sfui.fishing.IsSessionActive())
    -- Out of combat, while a fishing session is active, a fishing pole is NEVER replaced by auto gear
    local skipWeaponsForFishing = isFishingPole and isFishingSession

    local equipQueue = {}
    for slotID, item in pairs(best) do
        if not (skipWeaponsForFishing and (slotID == 16 or slotID == 17)) then
            local isAlreadyEquippedHere = (item.isEquipped and item.equippedSlot == slotID)
            local isRecentlyAttempted = item.link and boeAttemptedAt[item.link] and (_G.GetTime() < (boeAttemptedAt[item.link] + BOE_RETRY_DELAY))
            if not isAlreadyEquippedHere and not isRecentlyAttempted then
                local oldLink = GetInventoryItemLink("player", slotID)
                local oldIlvl = oldLink and common.get_item_level(oldLink) or 0
                local oldScore = 0
                if sfui.highest.pooledBest and sfui.highest.pooledBest[slotID] then
                    for _, itm in ipairs(sfui.highest.pooledBest[slotID]) do
                        if itm.isEquipped and itm.equippedSlot == slotID then
                            oldScore = itm.score or 0
                            break
                        end
                    end
                end

                -- Guard against swapping identical items / stacks:
                if oldLink and item.link then
                    local oldID = common.get_item_id(oldLink)
                    local newID = common.get_item_id(item.link)
                    if oldID and newID and oldID == newID then
                        if slotID == 0 then
                            local eqCount = _G.GetInventoryItemCount and _G.GetInventoryItemCount("player", 0) or 0
                            if issecretvalue and issecretvalue(eqCount) then eqCount = 0 end
                            if type(eqCount) == "number" and eqCount > 0 then
                                isAlreadyEquippedHere = true
                            end
                        elseif (item.score or 0) <= oldScore then
                            isAlreadyEquippedHere = true
                        end
                    end
                end

                if not isAlreadyEquippedHere then
                    table.insert(equipQueue, {
                        slotID   = slotID,
                        item     = item,
                        oldLink  = oldLink,
                        oldIlvl  = oldIlvl,
                        oldScore = oldScore,
                    })
                end
            end
        end
    end

    -- Ensure deterministic equip order (Main Hand 16 before Off Hand 17) Titan's Grip constraints
    table.sort(equipQueue, function(a, b) return a.slotID < b.slotID end)

    local totalToEquip = #equipQueue
    if totalToEquip == 0 then
        if not silent then
            sfprint("already wearing your best gear.")
        end
        return
    end

    isEquippingInProgress = true

    local equipWatchdog
    if _G.C_Timer and _G.C_Timer.NewTimer then
        equipWatchdog = _G.C_Timer.NewTimer(8, function()
            if isEquippingInProgress then
                isEquippingInProgress = false
                pendingEquipRequest = nil
            end
        end)
    end

    local function onEquipFinished()
        isEquippingInProgress = false
        if equipWatchdog and equipWatchdog.Cancel then
            equipWatchdog:Cancel()
            equipWatchdog = nil
        end
        if pendingEquipRequest then
            local req = pendingEquipRequest
            pendingEquipRequest = nil
            _G.C_Timer.After(0.1, function()
                if _G.InCombatLockdown and _G.InCombatLockdown() then return end
                if not isEquippingInProgress then
                    sfui.highest.EquipHighestILvl(req.isPvP, req.silent)
                end
            end)
        end
    end

    -- Equip sequentially with lock detection to avoid dropped items or cursor collisions.
    local function equipNext(index, retryCount)
        if index > #equipQueue then
            if totalToEquip > 0 then
                if not silent then
                    sfprint("equipped " .. totalToEquip .. " upgrade(s)!")
                end
            end
            onEquipFinished()
            return
        end

        local currentInCombat = _G.InCombatLockdown and _G.InCombatLockdown()
        if currentInCombat then
            if not silent then sfprint("equip canceled: cannot change equipment in combat.") end
            onEquipFinished()
            return
        end

        local entry = equipQueue[index]
        local slotID, item = entry.slotID, entry.item
        local oldLink = entry.oldLink
        local oldIlvl = entry.oldIlvl or 0
        local newLink = item.link
        local newIlvl = item.effectiveIlvl or item.ilvl or (newLink and common.get_item_level(newLink)) or 0
        if oldIlvl == 0 and oldLink then
            oldIlvl = common.get_item_level(oldLink)
        end
        if newIlvl == 0 and newLink then
            newIlvl = common.get_item_level(newLink)
        end
        retryCount = retryCount or 0

        if item.isUnequip then
            if retryCount == 0 and not silent then
                sfprint(string.format("-> %s (%d) to empty (2h weapon)",
                    oldLink or "item", oldIlvl))
            end
            if _G.ClearCursor then _G.ClearCursor() end
            if _G.PickupInventoryItem then _G.PickupInventoryItem(slotID) end
            _G.C_Timer.After(0.08, function()
                if _G.InCombatLockdown and _G.InCombatLockdown() then
                    if _G.ClearCursor then _G.ClearCursor() end
                    onEquipFinished()
                    return
                end
                if _G.PutItemInBackpack then _G.PutItemInBackpack() end
                _G.C_Timer.After(0.05, function()
                    if _G.InCombatLockdown and _G.InCombatLockdown() then
                        if _G.ClearCursor then _G.ClearCursor() end
                        onEquipFinished()
                        return
                    end
                    if _G.CursorHasItem and _G.CursorHasItem() then
                        if _G.PutItemInBag then
                            for b = 1, 4 do
                                if _G.CursorHasItem and _G.CursorHasItem() then
                                    _G.PutItemInBag(19 + b)
                                end
                            end
                        end
                        if _G.CursorHasItem and _G.CursorHasItem() and _G.ClearCursor then
                            _G.ClearCursor()
                        end
                    end
                    equipNext(index + 1)
                end)
            end)
            return
        end

        -- Print swap details on first attempt of each queued upgrade
        if retryCount == 0 and not silent then
            local reason = ""
            if oldLink and oldLink ~= "" then
                local diff = newIlvl - oldIlvl
                if item.equipReason then
                    if diff > 0 then
                        reason = string.format("%s (+%d ilvl)", item.equipReason, diff)
                    elseif diff < 0 then
                        reason = string.format("%s (%d ilvl)", item.equipReason, diff)
                    else
                        reason = item.equipReason
                    end
                else
                    if diff > 0 then
                        reason = string.format("+%d ilvl", diff)
                    elseif diff < 0 then
                        reason = string.format("%d ilvl, stat weights", diff)
                    else
                        reason = "stat weights"
                    end
                end
                sfprint(string.format("-> %s (%d) to %s (%d) (%s)",
                    oldLink, oldIlvl, newLink, newIlvl, reason))
            else
                if item.equipReason then
                    reason = string.format("%s (+%d ilvl)", item.equipReason, newIlvl)
                else
                    reason = string.format("+%d ilvl", newIlvl)
                end
                sfprint(string.format("-> empty to %s (%d) (%s)",
                    newLink, newIlvl, reason))
            end
        end

        if item.bag and item.slot then
            local currentLink = C_Container_GetContainerItemLink(item.bag, item.slot)
            local targetBag, targetSlot = item.bag, item.slot
            if not (currentLink and currentLink == item.link) then
                targetBag, targetSlot = nil, nil
                for b = 0, 4 do
                    local numSlots = (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(b))
                        or (_G.GetContainerNumSlots and _G.GetContainerNumSlots(b)) or 0
                    for s = 1, numSlots do
                        local l = C_Container_GetContainerItemLink(b, s)
                        if l == item.link then
                            targetBag, targetSlot = b, s
                            break
                        end
                    end
                    if targetBag then break end
                end
            end

            if targetBag and targetSlot then
                local bagInfo = C_Container_GetContainerItemInfo(targetBag, targetSlot)
                local isLocked = (type(bagInfo) == "table" and bagInfo.isLocked)
                    or (type(bagInfo) ~= "table" and _G.GetContainerItemInfo and select(3, _G.GetContainerItemInfo(targetBag, targetSlot)))
                if isLocked and retryCount < 10 then
                    item.bag = targetBag
                    item.slot = targetSlot
                    _G.C_Timer.After(0.05, function()
                        if _G.InCombatLockdown and _G.InCombatLockdown() then
                            onEquipFinished()
                            return
                        end
                        equipNext(index, retryCount + 1)
                    end)
                    return
                end

                -- Special handling for Slot 0 (Ammo):
                if slotID == 0 then
                    if _G.ClearCursor then _G.ClearCursor() end
                    C_Container_PickupContainerItem(targetBag, targetSlot)
                    if _G.CursorHasItem and _G.CursorHasItem() then
                        if _G.PickupInventoryItem then
                            _G.PickupInventoryItem(0)
                        end
                        if _G.CursorHasItem and _G.CursorHasItem() then
                            C_Container_PickupContainerItem(targetBag, targetSlot)
                            if _G.CursorHasItem and _G.CursorHasItem() and _G.ClearCursor then
                                _G.ClearCursor()
                            end
                        end
                    end
                    _G.C_Timer.After(0.08, function()
                        if _G.InCombatLockdown and _G.InCombatLockdown() then
                            onEquipFinished()
                            return
                        end
                        equipNext(index + 1)
                    end)
                    return
                end

                local isBound = sfui.highest.IsBagItemBound(targetBag, targetSlot)
                if not isBound then
                    boeAttemptedAt[item.link] = _G.GetTime()
                    if _G.ClearCursor then _G.ClearCursor() end
                    EquipItemByName(item.link, slotID, targetBag, targetSlot)

                    -- Pause watchdog timer while awaiting player confirmation
                    if equipWatchdog and equipWatchdog.Cancel then
                        equipWatchdog:Cancel()
                        equipWatchdog = nil
                    end

                    -- Check if bind confirmation dialog is displayed
                    _G.C_Timer.After(0.06, function()
                        if _G.InCombatLockdown and _G.InCombatLockdown() then
                            onEquipFinished()
                            return
                        end
                        local isVis = (_G.StaticPopup_Visible and (_G.StaticPopup_Visible("EQUIP_BIND")
                            or _G.StaticPopup_Visible("EQUIP_BIND_TRADEABLE")
                            or _G.StaticPopup_Visible("EQUIP_BIND_REFUNDABLE")))

                        -- Fallback to UseContainerItem if dialog didn't show via EquipItemByName
                        if not isVis and targetBag and targetSlot then
                            if _G.InCombatLockdown and _G.InCombatLockdown() then
                                onEquipFinished()
                                return
                            end
                            if C_Container and C_Container.UseContainerItem then
                                C_Container.UseContainerItem(targetBag, targetSlot)
                            elseif _G.UseContainerItem then
                                _G.UseContainerItem(targetBag, targetSlot)
                            end
                            isVis = (_G.StaticPopup_Visible and (_G.StaticPopup_Visible("EQUIP_BIND")
                                or _G.StaticPopup_Visible("EQUIP_BIND_TRADEABLE")
                                or _G.StaticPopup_Visible("EQUIP_BIND_REFUNDABLE")))
                        end

                        if isVis then
                            local ticks = 0
                            local watchTicker
                            watchTicker = _G.C_Timer.NewTicker(0.2, function()
                                if _G.InCombatLockdown and _G.InCombatLockdown() then
                                    watchTicker:Cancel()
                                    onEquipFinished()
                                    return
                                end
                                ticks = ticks + 1
                                local stillVis = (_G.StaticPopup_Visible and (_G.StaticPopup_Visible("EQUIP_BIND")
                                    or _G.StaticPopup_Visible("EQUIP_BIND_TRADEABLE")
                                    or _G.StaticPopup_Visible("EQUIP_BIND_REFUNDABLE")))
                                if not stillVis or ticks > 300 then
                                    watchTicker:Cancel()
                                    _G.C_Timer.After(0.15, function()
                                        if _G.InCombatLockdown and _G.InCombatLockdown() then
                                            onEquipFinished()
                                            return
                                        end
                                        equipNext(index + 1)
                                    end)
                                end
                            end)
                        else
                            _G.C_Timer.After(0.08, function()
                                if _G.InCombatLockdown and _G.InCombatLockdown() then
                                    onEquipFinished()
                                    return
                                end
                                equipNext(index + 1)
                            end)
                        end
                    end)
                    return
                end

                -- Soulbound gear: use fast container swap into exact vacated slot
                if _G.InCombatLockdown and _G.InCombatLockdown() then
                    onEquipFinished()
                    return
                end
                if _G.ClearCursor then _G.ClearCursor() end
                C_Container_PickupContainerItem(targetBag, targetSlot)
                if _G.CursorHasItem and _G.CursorHasItem() then
                    if _G.InCombatLockdown and _G.InCombatLockdown() then
                        if _G.ClearCursor then _G.ClearCursor() end
                        onEquipFinished()
                        return
                    end
                    if slotID == 0 then
                        if _G.PickupInventoryItem then _G.PickupInventoryItem(0) end
                    elseif _G.EquipCursorItem then
                        _G.EquipCursorItem(slotID)
                    end
                    if _G.CursorHasItem and _G.CursorHasItem() then
                        C_Container_PickupContainerItem(targetBag, targetSlot)
                        if _G.CursorHasItem and _G.CursorHasItem() then
                            if _G.PutItemInBackpack then _G.PutItemInBackpack() end
                            if _G.CursorHasItem and _G.CursorHasItem() and _G.ClearCursor then
                                _G.ClearCursor()
                            end
                        end
                    end
                else
                    if _G.InCombatLockdown and _G.InCombatLockdown() then
                        onEquipFinished()
                        return
                    end
                    EquipItemByName(item.link, slotID, targetBag, targetSlot)
                end
            else
                EquipItemByName(item.link, slotID)
            end
        elseif item.isEquipped and item.equippedSlot and item.equippedSlot ~= slotID then
            local currentTargetLink = GetInventoryItemLink("player", slotID)
            if currentTargetLink ~= item.link then
                if _G.InCombatLockdown and _G.InCombatLockdown() then
                    onEquipFinished()
                    return
                end
                if _G.ClearCursor then _G.ClearCursor() end
                if _G.PickupInventoryItem then
                    _G.PickupInventoryItem(item.equippedSlot)
                    if _G.CursorHasItem and _G.CursorHasItem() then
                        _G.PickupInventoryItem(slotID)
                        if _G.CursorHasItem and _G.CursorHasItem() then
                            _G.PickupInventoryItem(item.equippedSlot)
                        end
                        if _G.ClearCursor then _G.ClearCursor() end
                    else
                        EquipItemByName(item.link, slotID)
                    end
                else
                    EquipItemByName(item.link, slotID)
                end
            end
        else
            EquipItemByName(item.link, slotID)
        end

        _G.C_Timer.After(0.08, function()
            if _G.InCombatLockdown and _G.InCombatLockdown() then
                onEquipFinished()
                return
            end
            equipNext(index + 1)
        end)
    end

    equipNext(1)
end
sfui.highest.toggle = sfui.highest.EquipHighestILvl

if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("PLAYER_REGEN_DISABLED", function()
        if isEquippingInProgress then
            isEquippingInProgress = false
            pendingEquipRequest = nil
            if _G.ClearCursor then _G.ClearCursor() end
        end
    end)
end
