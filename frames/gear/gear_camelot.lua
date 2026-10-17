local addonName, addon = ...
sfui = sfui or {}
sfui.gear = sfui.gear or {}

-- Guard: Classic & Camelot only (Exclude Retail)
if sfui.isRetail then
    return
end

local common = sfui.common
local _G = _G
local CreateFrame = _G.CreateFrame
local InCombatLockdown = _G.InCombatLockdown
local C_Timer = _G.C_Timer
local C_Container = _G.C_Container
local GetInventoryItemID = _G.GetInventoryItemID
local GetInventoryItemDurability = _G.GetInventoryItemDurability
local PickupInventoryItem = _G.PickupInventoryItem
local ClearCursor = _G.ClearCursor
local CursorHasItem = _G.CursorHasItem
local IsInventoryItemLocked = _G.IsInventoryItemLocked
local ipairs = _G.ipairs
local pairs = _G.pairs
local type = _G.type
local table = _G.table
local string = _G.string
local math = _G.math
local tonumber = _G.tonumber
local tostring = _G.tostring
local wipe = _G.wipe or function(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

local function show_tooltip(owner, anchor, title, lines)
    local tip = sfui.common.get_tooltip()
    if not tip or not owner then return end
    tip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    if title then
        tip:SetText(tostring(title):lower())
    end
    if lines then
        for _, line in ipairs(lines) do
            if type(line) == "table" then
                local txt = line[1] and tostring(line[1]):lower() or ""
                tip:AddLine(txt, line[2], line[3], line[4], line[5])
            else
                tip:AddLine(tostring(line):lower())
            end
        end
    end
    tip:Show()
end

local hide_tooltip = sfui.common.hide_tooltip

-- -------------------------------------------------------------------------
-- CENTRALIZED ROLE & NAKED ICON PARAMETERS
-- -------------------------------------------------------------------------
local ROLE_ICON_SIZE    = 28
local ROLE_ICON_SPACING = 4
local ROLE_ICON_Y       = -56

sfui.gear.ROLE_ICON_SIZE    = ROLE_ICON_SIZE
sfui.gear.ROLE_ICON_SPACING = ROLE_ICON_SPACING
sfui.gear.ROLE_ICON_Y       = ROLE_ICON_Y

-- Header height for Classic/Camelot (compact title bar)
function sfui.gear.GetHeaderHeight()
    return 34
end

-- -------------------------------------------------------------------------
-- CLASSIC ROLES & ICONS DEFINITION
-- -------------------------------------------------------------------------
sfui.gear.CLASSIC_ROLES_BY_SPEC = {
    -- Druid
    [1484]  = { "cat", "bear", "moon", "resto" },
    [14841] = { "cat", "bear", "moon", "resto" },
    [14842] = { "cat", "bear", "moon", "resto" },
    [14843] = { "cat", "bear", "moon", "resto" },
    [14844] = { "cat", "bear", "moon", "resto" },
    -- Paladin
    [1486]  = { "prot", "ret", "holy" },
    [14861] = { "prot", "ret", "holy" },
    [14862] = { "prot", "ret", "holy" },
    [14863] = { "prot", "ret", "holy" },
    -- Warrior
    [1491]  = { "arms", "fury", "prot" },
    [14911] = { "arms", "fury", "prot" },
    [14912] = { "arms", "fury", "prot" },
    [14913] = { "arms", "fury", "prot" },
    -- Shaman
    [1489]  = { "ele", "enh", "resto" },
    [14891] = { "ele", "enh", "resto" },
    [14892] = { "ele", "enh", "resto" },
    [14893] = { "ele", "enh", "resto" },
    -- Priest
    [1487]  = { "disc", "holy", "shad" },
    [14871] = { "disc", "holy", "shad" },
    [14872] = { "disc", "holy", "shad" },
    [14873] = { "disc", "holy", "shad" },
    -- Rogue
    [1488]  = { "sin", "combat", "sub" },
    [14881] = { "sin", "combat", "sub" },
    [14882] = { "sin", "combat", "sub" },
    [14883] = { "sin", "combat", "sub" },
    -- Mage
    [1482]  = { "arc", "fire", "frost" },
    [14821] = { "arc", "fire", "frost" },
    [14822] = { "arc", "fire", "frost" },
    [14823] = { "arc", "fire", "frost" },
    -- Warlock
    [1490]  = { "aff", "demo", "destro" },
    [14901] = { "aff", "demo", "destro" },
    [14902] = { "aff", "demo", "destro" },
    [14903] = { "aff", "demo", "destro" },
    -- Hunter
    [1485]  = { "bm", "mm", "surv" },
    [14851] = { "bm", "mm", "surv" },
    [14852] = { "bm", "mm", "surv" },
    [14853] = { "bm", "mm", "surv" },
}

sfui.gear.CLASSIC_ROLE_ICONS = {
    -- Druid
    [1484]  = { cat = "Interface\\Icons\\Ability_Druid_CatForm", bear = "Interface\\Icons\\Ability_Racial_BearForm", moon = 136096, resto = 136041 },
    [14841] = { cat = "Interface\\Icons\\Ability_Druid_CatForm", bear = "Interface\\Icons\\Ability_Racial_BearForm", moon = 136096, resto = 136041 },
    [14842] = { cat = "Interface\\Icons\\Ability_Druid_CatForm", bear = "Interface\\Icons\\Ability_Racial_BearForm", moon = 136096, resto = 136041 },
    [14843] = { cat = "Interface\\Icons\\Ability_Druid_CatForm", bear = "Interface\\Icons\\Ability_Racial_BearForm", moon = 136096, resto = 136041 },
    [14844] = { cat = "Interface\\Icons\\Ability_Druid_CatForm", bear = "Interface\\Icons\\Ability_Racial_BearForm", moon = 136096, resto = 136041 },
    [11]    = { cat = "Interface\\Icons\\Ability_Druid_CatForm", bear = "Interface\\Icons\\Ability_Racial_BearForm", moon = 136096, resto = 136041 },
    -- Paladin
    [1486]  = { prot = 236264, ret = 135873, holy = 135920 },
    [14861] = { prot = 236264, ret = 135873, holy = 135920 },
    [14862] = { prot = 236264, ret = 135873, holy = 135920 },
    [14863] = { prot = 236264, ret = 135873, holy = 135920 },
    [2]     = { prot = 236264, ret = 135873, holy = 135920 },
    -- Warrior
    [1491]  = { arms = 132355, fury = 132347, prot = 132341 },
    [14911] = { arms = 132355, fury = 132347, prot = 132341 },
    [14912] = { arms = 132355, fury = 132347, prot = 132341 },
    [14913] = { arms = 132355, fury = 132347, prot = 132341 },
    [1]     = { arms = 132355, fury = 132347, prot = 132341 },
    -- Shaman
    [1489]  = { ele = 136048, enh = 136051, resto = 136052 },
    [14891] = { ele = 136048, enh = 136051, resto = 136052 },
    [14892] = { ele = 136048, enh = 136051, resto = 136052 },
    [14893] = { ele = 136048, enh = 136051, resto = 136052 },
    [7]     = { ele = 136048, enh = 136051, resto = 136052 },
    -- Priest
    [1487]  = { disc = 135940, holy = 237542, shad = 136207, shadow = 136207 },
    [14871] = { disc = 135940, holy = 237542, shad = 136207, shadow = 136207 },
    [14872] = { disc = 135940, holy = 237542, shad = 136207, shadow = 136207 },
    [14873] = { disc = 135940, holy = 237542, shad = 136207, shadow = 136207 },
    [5]     = { disc = 135940, holy = 237542, shad = 136207, shadow = 136207 },
    -- Rogue
    [1488]  = { sin = 132292, combat = 132309, sub = 132320 },
    [14881] = { sin = 132292, combat = 132309, sub = 132320 },
    [14882] = { sin = 132292, combat = 132309, sub = 132320 },
    [14883] = { sin = 132292, combat = 132309, sub = 132320 },
    [4]     = { sin = 132292, combat = 132309, sub = 132320 },
    -- Mage
    [1482]  = { arc = 135932, fire = 135810, frost = 135846 },
    [14821] = { arc = 135932, fire = 135810, frost = 135846 },
    [14822] = { arc = 135932, fire = 135810, frost = 135846 },
    [14823] = { arc = 135932, fire = 135810, frost = 135846 },
    [8]     = { arc = 135932, fire = 135810, frost = 135846 },
    -- Warlock
    [1490]  = { aff = 136145, demo = 136172, destro = 136186 },
    [14901] = { aff = 136145, demo = 136172, destro = 136186 },
    [14902] = { aff = 136145, demo = 136172, destro = 136186 },
    [14903] = { aff = 136145, demo = 136172, destro = 136186 },
    [9]     = { aff = 136145, demo = 136172, destro = 136186 },
    -- Hunter
    [1485]  = { bm = 132222, mm = 132218, surv = 132215 },
    [14851] = { bm = 132222, mm = 132218, surv = 132215 },
    [14852] = { bm = 132222, mm = 132218, surv = 132215 },
    [14853] = { bm = 132222, mm = 132218, surv = 132215 },
    [3]     = { bm = 132222, mm = 132218, surv = 132215 },
}

function sfui.gear.GetClassicRoleIcon(classID, roleKey)
    local rLow = roleKey and roleKey:lower()
    local icons = sfui.gear.CLASSIC_ROLE_ICONS
    if classID and icons[classID] and icons[classID][rLow] then
        return icons[classID][rLow]
    end
    if rLow == "cat" then
        return "Interface\\Icons\\Ability_Druid_CatForm"
    elseif rLow == "bear" then
        return "Interface\\Icons\\Ability_Racial_BearForm"
    elseif rLow == "moon" then
        return 136096
    elseif rLow == "resto" then
        return 136041
    elseif rLow == "prot" or rLow == "tank" then
        return 132341
    elseif rLow == "holy" or rLow == "heal" then
        return 135920
    elseif rLow == "ret" then
        return 135873
    elseif rLow == "arms" or rLow == "dps" then
        return 132355
    elseif rLow == "fury" then
        return 132347
    elseif rLow == "ele" then
        return 136048
    elseif rLow == "enh" then
        return 136051
    elseif rLow == "disc" then
        return 135940
    elseif rLow == "shad" or rLow == "shadow" then
        return 136207
    elseif rLow == "sin" then
        return 132292
    elseif rLow == "combat" then
        return 132309
    elseif rLow == "sub" then
        return 132320
    elseif rLow == "arc" then
        return 135932
    elseif rLow == "fire" then
        return 135810
    elseif rLow == "frost" then
        return 135846
    elseif rLow == "aff" then
        return 136145
    elseif rLow == "demo" then
        return 136172
    elseif rLow == "destro" then
        return 136186
    elseif rLow == "bm" then
        return 132222
    elseif rLow == "mm" then
        return 132218
    elseif rLow == "surv" then
        return 132215
    elseif rLow == "naked" then
        return "Interface\\Icons\\inv_chest_cloth_17"
    end
    return 132355
end

-- -------------------------------------------------------------------------
-- DURABILITY UNEQUIP ENGINE (CORPSE RUN / DEATH RUN UTILITY)
-- -------------------------------------------------------------------------
local unequipRunning = false
local reservedBagSlots = {}

function sfui.gear.StopUnequipDurabilityItems()
    if unequipRunning then
        unequipRunning = false
        wipe(reservedBagSlots)
        if CursorHasItem() then ClearCursor() end
    end
end

local function getNumBagSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag) or 0
    elseif _G.GetContainerNumSlots then
        return _G.GetContainerNumSlots(bag) or 0
    end
    return 0
end

local function getBagNumFreeSlots(bag)
    if C_Container and C_Container.GetContainerNumFreeSlots then
        return C_Container.GetContainerNumFreeSlots(bag)
    elseif _G.GetContainerNumFreeSlots then
        return _G.GetContainerNumFreeSlots(bag)
    end
    return 0, 0
end

local function getBagItemID(bag, slot)
    if C_Container and C_Container.GetContainerItemID then
        return C_Container.GetContainerItemID(bag, slot)
    elseif _G.GetContainerItemID then
        return _G.GetContainerItemID(bag, slot)
    end
    return nil
end

local function pickupBagItem(bag, slot)
    if C_Container and C_Container.PickupContainerItem then
        C_Container.PickupContainerItem(bag, slot)
    elseif _G.PickupContainerItem then
        _G.PickupContainerItem(bag, slot)
    end
end

local function findFreeBagSlot()
    for bag = 0, 4 do
        local numFree, bagType = getBagNumFreeSlots(bag)
        if (bagType == nil or bagType == 0) and numFree and numFree > 0 then
            local numSlots = getNumBagSlots(bag)
            for slot = 1, numSlots do
                local key = bag .. ":" .. slot
                if not reservedBagSlots[key] then
                    local itemID = getBagItemID(bag, slot)
                    if not itemID then
                        reservedBagSlots[key] = true
                        return bag, slot
                    end
                end
            end
        end
    end
    return nil, nil
end

function sfui.gear.UnequipDurabilityItems()
    if unequipRunning then return end

    if InCombatLockdown() then
        local msg = _G.ERR_NOT_IN_COMBAT or "Cannot unequip items in combat."
        if _G.UIErrorsFrame and _G.UIErrorsFrame.AddMessage then
            _G.UIErrorsFrame:AddMessage(msg, 1.0, 0.1, 0.1, 1.0)
        end
        sfui.common.print("cannot unequip items in combat.")
        return
    end

    local slotsToUnequip = {}
    local seen = {}

    -- 1. Weapons and armor slots (strictly excluding shirt [4] and tabard [19])
    -- Note: slot 18 (ranged/relic) is excluded from unconditional strip because relics
    -- (totems, librams, idols, sigils) have no durability. Ranged weapons with durability
    -- are dynamically caught by step 2 below.
    local nakedSlots = {
        16, 17,
        1, 3, 5, 6, 7, 8, 9, 10, 15,
    }
    for _, slot in ipairs(nakedSlots) do
        if GetInventoryItemID("player", slot) then
            table.insert(slotsToUnequip, slot)
            seen[slot] = true
        end
    end

    -- 2. Any other slot with durability (never touch shirt [4] or tabard [19])
    for slot = 1, 18 do
        if slot ~= 4 and not seen[slot] and GetInventoryItemID("player", slot) then
            local _, maxDur = GetInventoryItemDurability(slot)
            if maxDur and maxDur > 0 then
                table.insert(slotsToUnequip, slot)
                seen[slot] = true
            end
        end
    end

    if #slotsToUnequip == 0 then
        sfui.common.print("no gear equipped to unequip.")
        return
    end

    if not sfui.gear.isNakedPaused() then
        sfui.gear.SetNakedPaused(true, true)
    end

    unequipRunning = true
    wipe(reservedBagSlots)
    local index = 1
    local retryCount = 0

    local function step()
        if not unequipRunning then
            if CursorHasItem() then ClearCursor() end
            wipe(reservedBagSlots)
            return
        end

        if InCombatLockdown() then
            if CursorHasItem() then ClearCursor() end
            unequipRunning = false
            wipe(reservedBagSlots)
            return
        end

        if index > #slotsToUnequip then
            unequipRunning = false
            wipe(reservedBagSlots)
            sfui.common.print("gear unequipped.")
            return
        end

        local slotID = slotsToUnequip[index]
        if not GetInventoryItemID("player", slotID) then
            index = index + 1
            retryCount = 0
            C_Timer.After(0.02, step)
            return
        end

        if IsInventoryItemLocked(slotID) then
            retryCount = retryCount + 1
            if retryCount <= 10 then
                C_Timer.After(0.05, step)
                return
            else
                index = index + 1
                retryCount = 0
                C_Timer.After(0.02, step)
                return
            end
        end

        local bag, bagSlot = findFreeBagSlot()
        if not bag or not bagSlot then
            local msg = _G.INVENTORY_FULL or "Inventory is full."
            if _G.UIErrorsFrame and _G.UIErrorsFrame.AddMessage then
                _G.UIErrorsFrame:AddMessage(msg, 1.0, 0.1, 0.1, 1.0)
            end
            sfui.common.print("bags full; stopped unequipping gear.")
            unequipRunning = false
            wipe(reservedBagSlots)
            return
        end

        ClearCursor()
        PickupInventoryItem(slotID)
        if CursorHasItem() then
            pickupBagItem(bag, bagSlot)
            if CursorHasItem() then
                if _G.PutItemInBackpack then _G.PutItemInBackpack() end
                if CursorHasItem() and _G.PutItemInBag then
                    local offset = _G.CONTAINER_BAG_OFFSET or 30
                    for b = 1, 4 do
                        if CursorHasItem() then _G.PutItemInBag(b + offset) end
                    end
                end
                if CursorHasItem() then
                    PickupInventoryItem(slotID)
                    if CursorHasItem() then ClearCursor() end
                end
            end
        end

        index = index + 1
        retryCount = 0
        C_Timer.After(0.04, step)
    end

    step()
end

function sfui.gear.ToggleNaked()
    if sfui.gear.isNakedPaused() then
        sfui.gear.SetNakedPaused(false)
        if sfui.highest then
            sfui.highest.ClearValidationCache()
            sfui.highest.ClearCache()
        end
        sfui.gear.UpdateStatUI()
        sfui.gear.Update(true)
        if sfui.highest and sfui.highest.EquipHighestILvl then
            sfui.highest.EquipHighestILvl(sfui.gear.isCurrentlyPvP())
        end
        sfui.common.print("naked: auto-equip resumed; equipping gear.")
    else
        sfui.gear.SetNakedPaused(true)
        sfui.gear.UnequipDurabilityItems()
        sfui.common.print("naked: auto-equip paused.")
    end
end

-- -------------------------------------------------------------------------
-- LOCK SLOTS EXTENSION (Adds Ranged & Ammo)
-- -------------------------------------------------------------------------
function sfui.gear.GetLockSlots(specID)
    local relicLabel = "rg"
    local relicName = "ranged"
    local playerClass = select(2, UnitClass("player"))
    if playerClass == "SHAMAN" then
        relicLabel = "tt"
        relicName = "totem"
    elseif playerClass == "PALADIN" then
        relicLabel = "lb"
        relicName = "libram"
    elseif playerClass == "DRUID" then
        relicLabel = "id"
        relicName = "idol"
    elseif playerClass == "DEATHKNIGHT" then
        relicLabel = "sg"
        relicName = "sigil"
    end

    local slots = {
        { label = "t1", slot = 13, name = "trinket 1" },
        { label = "t2", slot = 14, name = "trinket 2" },
        { label = "r1", slot = 11, name = "ring 1" },
        { label = "r2", slot = 12, name = "ring 2" },
        { label = "nk", slot = 2,  name = "neck" },
        { label = "w1", slot = 16, name = "main hand" },
        { label = "w2", slot = 17, name = "off hand" },
        { label = relicLabel, slot = 18, name = relicName },
    }
    local usesAmmo = sfui.api and sfui.api.UnitUsesAmmo and sfui.api.UnitUsesAmmo("player")
    if usesAmmo then
        table.insert(slots, { label = "am", slot = 0, name = "ammo" })
    end
    return slots
end

-- -------------------------------------------------------------------------
-- CLASSIC STAT CLEANSE (Scrubs ArP & Exp)
-- -------------------------------------------------------------------------
function sfui.gear.SanitizeStatOrder(specID, rawOrder, pool, isTank)
    local numStats = #pool
    local clean = {}
    local dirty = false
    local statAbbrv = sfui.gear.statAbbrv or {}

    for i = 1, numStats do
        local st = rawOrder and rawOrder[i]
        local isInvalid = not st or (not isTank and sfui.gear.DEFENSIVE_STATS and sfui.gear.DEFENSIVE_STATS[st])
        if st == "ArP" or st == "Exp" or st == "ArmorPenetration" or st == "Expertise"
            or (statAbbrv[st] == "arp" or statAbbrv[st] == "exp") then
            isInvalid = true
            dirty = true
        end
        if isInvalid then
            for _, cand in ipairs(pool) do
                local inUse = false
                for k = 1, #clean do
                    if clean[k] == cand then inUse = true; break end
                end
                if not inUse then
                    st = cand
                    break
                end
            end
        end
        clean[i] = st or pool[i] or "none"
    end

    if dirty and SfuiDB and SfuiDB.gear and SfuiDB.gear[specID] and SfuiDB.gear[specID].stat_order then
        SfuiDB.gear[specID].stat_order = {}
        for cIdx = 1, numStats do
            SfuiDB.gear[specID].stat_order[cIdx] = clean[cIdx]
        end
    end

    return clean
end

-- -------------------------------------------------------------------------
-- CENTRALIZED ROLE DEFINITIONS & STYLING HELPERS
-- -------------------------------------------------------------------------
local COLLAPSED_ROLE_SIZE    = 24
local COLLAPSED_ROLE_SPACING = 4

local ROLE_COLORS = {
    ["tank"]   = { 0.4, 0.7, 1.0 },
    ["bear"]   = { 0.4, 0.7, 1.0 },
    ["prot"]   = { 0.4, 0.7, 1.0 },
    ["heal"]   = { 0.3, 1.0, 0.4 },
    ["resto"]  = { 0.3, 1.0, 0.4 },
    ["holy"]   = { 0.3, 1.0, 0.4 },
    ["disc"]   = { 0.90, 0.90, 0.95 },
    ["dps"]    = { 1.0, 0.4, 0.3 },
    ["cat"]    = { 1.0, 0.49, 0.04 },
    ["moon"]   = { 0.40, 0.75, 1.0 },
    ["ret"]    = { 0.96, 0.55, 0.73 },
    ["arms"]   = { 0.78, 0.61, 0.43 },
    ["fury"]   = { 1.0, 0.45, 0.25 },
    ["ele"]    = { 0.0, 0.44, 0.87 },
    ["enh"]    = { 1.0, 0.50, 0.25 },
    ["shad"]   = { 0.60, 0.40, 0.85 },
    ["shadow"] = { 0.60, 0.40, 0.85 },
    ["sin"]    = { 1.0, 0.96, 0.41 },
    ["combat"] = { 1.0, 0.82, 0.35 },
    ["sub"]    = { 0.85, 0.70, 0.95 },
    ["arc"]    = { 0.70, 0.50, 1.0 },
    ["fire"]   = { 1.0, 0.40, 0.20 },
    ["frost"]  = { 0.40, 0.75, 1.0 },
    ["aff"]    = { 0.58, 0.51, 0.79 },
    ["demo"]   = { 0.80, 0.40, 0.60 },
    ["destro"] = { 1.0, 0.45, 0.20 },
    ["bm"]     = { 0.67, 0.83, 0.45 },
    ["mm"]     = { 0.55, 0.78, 0.40 },
    ["surv"]   = { 0.80, 0.80, 0.50 },
}

local ROLE_LABELS = {
    ["tank"]   = "tank",
    ["bear"]   = "bear",
    ["prot"]   = "prot",
    ["heal"]   = "heal",
    ["resto"]  = "resto",
    ["holy"]   = "holy",
    ["disc"]   = "disc",
    ["dps"]    = "dps",
    ["cat"]    = "cat",
    ["moon"]   = "moon",
    ["ret"]    = "ret",
    ["arms"]   = "arms",
    ["fury"]   = "fury",
    ["ele"]    = "ele",
    ["enh"]    = "enh",
    ["shad"]   = "shad",
    ["shadow"] = "shad",
    ["sin"]    = "sin",
    ["combat"] = "combat",
    ["sub"]    = "sub",
    ["arc"]    = "arc",
    ["fire"]   = "fire",
    ["frost"]  = "frost",
    ["aff"]    = "aff",
    ["demo"]   = "demo",
    ["destro"] = "destro",
    ["bm"]     = "bm",
    ["mm"]     = "mm",
    ["surv"]   = "surv",
}

local function getRoleDescription(rLow)
    return (rLow == "tank" and "configure stat priority, defensive stats, and armor item level prioritization for tanking.")
        or (rLow == "prot" and "configure stat priority, defensive stats, and armor item level prioritization for protection tanking.")
        or (rLow == "bear" and "configure stat priority, defensive stats, and armor item level prioritization for bear form tanking.")
        or (rLow == "heal" and "configure stat priority and gear optimization for healing.")
        or (rLow == "resto" and "configure stat priority and gear optimization for restoration healing.")
        or (rLow == "holy" and "configure stat priority and gear optimization for holy healing.")
        or (rLow == "disc" and "configure stat priority and gear optimization for discipline healing and shielding.")
        or (rLow == "ret" and "configure stat priority and gear optimization for retribution melee damage.")
        or (rLow == "arms" and "configure stat priority and gear optimization for arms melee damage.")
        or (rLow == "fury" and "configure stat priority and gear optimization for fury melee damage.")
        or (rLow == "ele" and "configure stat priority and gear optimization for elemental spell damage.")
        or (rLow == "enh" and "configure stat priority and gear optimization for enhancement melee damage.")
        or (rLow == "shad" and "configure stat priority and gear optimization for shadow spell damage.")
        or (rLow == "cat" and "configure stat priority and gear optimization for cat form melee damage.")
        or (rLow == "moon" and "configure stat priority and gear optimization for balance moonkin spell damage.")
        or (rLow == "sin" and "configure stat priority and gear optimization for assassination damage.")
        or (rLow == "combat" and "configure stat priority and gear optimization for combat damage.")
        or (rLow == "sub" and "configure stat priority and gear optimization for subtlety damage.")
        or (rLow == "arc" and "configure stat priority and gear optimization for arcane spell damage.")
        or (rLow == "fire" and "configure stat priority and gear optimization for fire spell damage.")
        or (rLow == "frost" and "configure stat priority and gear optimization for frost spell damage.")
        or (rLow == "aff" and "configure stat priority and gear optimization for affliction spell damage.")
        or (rLow == "demo" and "configure stat priority and gear optimization for demonology damage.")
        or (rLow == "destro" and "configure stat priority and gear optimization for destruction spell damage.")
        or (rLow == "bm" and "configure stat priority and gear optimization for beast mastery ranged damage.")
        or (rLow == "mm" and "configure stat priority and gear optimization for marksmanship ranged damage.")
        or (rLow == "surv" and "configure stat priority and gear optimization for survival ranged damage.")
        or "configure stat priority and gear optimization for damage dealing."
end

local function styleRoleButton(btn, isSelected)
    if not btn then return end
    btn.isSelected = isSelected
    if btn.tex then
        btn.tex:SetDesaturated(not isSelected)
        btn:SetAlpha(isSelected and 1.0 or 0.40)
        if isSelected then
            local c = btn.roleColor or { 0.95, 0.85, 0.55 }
            btn:SetBackdropBorderColor(c[1], c[2], c[3], 1.0)
            btn:SetBackdropColor(c[1] * 0.25, c[2] * 0.25, c[3] * 0.25, 0.9)
        else
            local isCamelotTheme = sfui.theme and sfui.theme.IsCamelotActive and sfui.theme.IsCamelotActive()
            if isCamelotTheme then
                btn:SetBackdropBorderColor(0.28, 0.22, 0.14, 0.85)
            else
                btn:SetBackdropBorderColor(0, 0, 0, 0.8)
            end
            btn:SetBackdropColor(0, 0, 0, 0.7)
        end
    end
end

local function styleNakedButton(btn, isNaked)
    if not btn then return end
    btn.isSelected = isNaked
    if btn.tex then
        btn.tex:SetDesaturated(not isNaked)
        btn:SetAlpha(isNaked and 1.0 or 0.40)
        if isNaked then
            btn:SetBackdropBorderColor(1.0, 0.65, 0.2, 1.0)
            btn:SetBackdropColor(0.35, 0.2, 0.05, 0.9)
        else
            local isCamelotTheme = sfui.theme and sfui.theme.IsCamelotActive and sfui.theme.IsCamelotActive()
            if isCamelotTheme then
                btn:SetBackdropBorderColor(0.28, 0.22, 0.14, 0.85)
            else
                btn:SetBackdropBorderColor(0, 0, 0, 0.8)
            end
            btn:SetBackdropColor(0, 0, 0, 0.7)
        end
    end
end

-- -------------------------------------------------------------------------
-- CENTRALIZED ROLE SELECTION ACTION
-- -------------------------------------------------------------------------
function sfui.gear.SelectClassicRole(specID, rKey)
    local numID = tonumber(specID) or 0
    if sfui.gear.SetNakedPaused then sfui.gear.SetNakedPaused(false, true) end
    if sfui.gear.pauseAutoEquip then sfui.gear.pauseAutoEquip(0) end
    SfuiDB = SfuiDB or {}
    SfuiDB.gear = SfuiDB.gear or {}
    SfuiDB.gear[specID] = SfuiDB.gear[specID] or {}
    local sdb = SfuiDB.gear[specID]
    sdb.user_selected_role = true
    sdb.classic_role = rKey
    local rLower = rKey:lower()
    local isTankRole = (rLower == "tank" or rLower == "bear" or rLower == "prot")
    local isHealRole = (rLower == "heal" or rLower == "resto" or rLower == "holy" or rLower == "disc")
    sdb.role = isTankRole and "TANK" or (isHealRole and "HEALER" or "DAMAGER")
    sdb.is_tank = isTankRole
    sdb.armor_ilvl_prio = isTankRole
    sdb.is_healer = isHealRole

    local bridge = sfui.talents and sfui.talents.SPEC_BRIDGE and (sfui.talents.SPEC_BRIDGE[specID] or sfui.talents.SPEC_BRIDGE[numID])
    if bridge then
        if bridge.camelotID and bridge.camelotID ~= specID then
            SfuiDB.gear[bridge.camelotID] = SfuiDB.gear[bridge.camelotID] or {}
            local cb = SfuiDB.gear[bridge.camelotID]
            cb.user_selected_role = true
            cb.classic_role = rKey
            cb.role = sdb.role
            cb.is_tank = sdb.is_tank
            cb.armor_ilvl_prio = sdb.armor_ilvl_prio
            cb.is_healer = sdb.is_healer
        end
        if bridge.classID and bridge.classID ~= specID then
            SfuiDB.gear[bridge.classID] = SfuiDB.gear[bridge.classID] or {}
            local clb = SfuiDB.gear[bridge.classID]
            clb.user_selected_role = true
            clb.classic_role = rKey
            clb.role = sdb.role
            clb.is_tank = sdb.is_tank
            clb.armor_ilvl_prio = sdb.armor_ilvl_prio
            clb.is_healer = sdb.is_healer
        end
    end

    local defOrder = sfui.gear.GetDefaultStats and sfui.gear.GetDefaultStats(numID, rKey)
    if defOrder then
        sdb.stat_order = {}
        for sIdx, st in ipairs(defOrder) do sdb.stat_order[sIdx] = st end
        sdb.stat_equals = nil
        sdb.pawn_weights = nil
    end

    local _, allSpecIDs = common.get_player_specs()
    if allSpecIDs then
        for _, sID in ipairs(allSpecIDs) do
            if sID ~= specID then
                SfuiDB.gear[sID] = SfuiDB.gear[sID] or {}
                local sb = SfuiDB.gear[sID]
                sb.user_selected_role = true
                sb.classic_role = rKey
                sb.role = sdb.role
                sb.is_tank = sdb.is_tank
                sb.armor_ilvl_prio = sdb.armor_ilvl_prio
                sb.is_healer = sdb.is_healer
                if defOrder then
                    sb.stat_order = {}
                    for sIdx, st in ipairs(defOrder) do sb.stat_order[sIdx] = st end
                    sb.stat_equals = nil
                    sb.pawn_weights = nil
                end
            end
        end
    end

    if sfui.highest then
        sfui.highest.ClearValidationCache()
        sfui.highest.ClearCache()
    end
    sfui.gear.UpdateStatUI()
    sfui.gear.Update()

    local curSpec = common.get_current_spec_id()
    local isMatch = (not curSpec) or (curSpec == specID)
        or (tonumber(curSpec) and tonumber(specID) and tonumber(curSpec) == tonumber(specID))
        or (sfui.gear.is_spec_match and sfui.gear.is_spec_match(curSpec, specID))
    if isMatch then
        C_Timer.After(0.18, function()
            if not sfui.gear.isNakedPaused() and sfui.highest and sfui.highest.EquipHighestILvl then
                sfui.highest.EquipHighestILvl(sfui.gear.isCurrentlyPvP())
            end
        end)
    end
end

-- -------------------------------------------------------------------------
-- CARD MODIFIERS BUILDER (Role Buttons & Naked Button on Row 2B)
-- -------------------------------------------------------------------------
function sfui.gear.BuildCardModifiers(card, ui, specID, curLockX)
    local numID = tonumber(specID) or 0
    local classID = (sfui.gear.GetClassicClassID and sfui.gear.GetClassicClassID(numID)) or numID
    local classicRoles = sfui.gear.CLASSIC_ROLES_BY_SPEC and
        (sfui.gear.CLASSIC_ROLES_BY_SPEC[numID] or (classID and sfui.gear.CLASSIC_ROLES_BY_SPEC[classID]))

    -- Center the role and naked icons in the free space between the lock row and the right frame margin
    local lockRight = (curLockX and curLockX > 27) and (curLockX - 3) or 259
    local cardW = (card and card:GetWidth() and card:GetWidth() > 0 and card:GetWidth())
        or (card and card:GetParent() and card:GetParent():GetWidth() and card:GetParent():GetWidth() > 0 and card:GetParent():GetWidth())
        or 480
    local rightMargin = 10
    local rightEdge = cardW - rightMargin

    local numRoleBtns = classicRoles and #classicRoles or 0
    local totalButtons = numRoleBtns + 1
    local totalWidth = (totalButtons * ROLE_ICON_SIZE) + ((totalButtons - 1) * ROLE_ICON_SPACING)

    local freeSpace = rightEdge - lockRight
    local startX = lockRight + math.floor((freeSpace - totalWidth) / 2)
    startX = math.max(lockRight + 6, startX)

    local curX = startX
    local lastRoleBtn = nil
    ui.roleStartX = startX

    if classicRoles then
        ui.roleBtns = {}

        for _, rKey in ipairs(classicRoles) do
            local rLabel = ROLE_LABELS[rKey] or rKey:lower()
            local rIcon = sfui.gear.GetClassicRoleIcon(classID, rKey)
            local rBtn = CreateFrame("Button", nil, card, "BackdropTemplate")
            rBtn:SetSize(ROLE_ICON_SIZE, ROLE_ICON_SIZE)
            rBtn:SetPoint("TOPLEFT", card, "TOPLEFT", curX, ROLE_ICON_Y)
            local t = rBtn:CreateTexture(nil, "ARTWORK")
            t:SetAllPoints()
            t:SetTexture(rIcon)
            t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            rBtn.tex = t
            rBtn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            local isCamelotTheme = sfui.theme and sfui.theme.IsCamelotActive and sfui.theme.IsCamelotActive()
            rBtn:SetBackdropColor(0, 0, 0, 0.7)
            rBtn:SetBackdropBorderColor(isCamelotTheme and 0.28 or 0, isCamelotTheme and 0.22 or 0,
                isCamelotTheme and 0.14 or 0, 0.85)
            rBtn:SetAlpha(0.40)
            rBtn.roleKey = rKey
            rBtn.roleColor = ROLE_COLORS[rKey] or { 0.6, 0.6, 0.6 }
            local capturedRole = rKey
            rBtn:SetScript("OnClick", function()
                sfui.gear.SelectClassicRole(specID, capturedRole)
            end)

            rBtn:SetScript("OnEnter", function(b)
                b:SetAlpha(1.0)
                local desc = getRoleDescription(capturedRole:lower())
                show_tooltip(b, "ANCHOR_TOP", rLabel, {
                    { desc, 0.8, 0.8, 0.8, true },
                })
            end)
            rBtn:SetScript("OnLeave", function(b)
                if not b.isSelected then
                    b:SetAlpha(0.40)
                end
                hide_tooltip()
            end)
            ui.roleBtns[rKey] = rBtn
            lastRoleBtn = rBtn
            curX = curX + ROLE_ICON_SIZE + ROLE_ICON_SPACING
        end
    end

    -- Naked Mode Button (Chest wardrobe icon)
    local btnNaked = CreateFrame("Button", nil, card, "BackdropTemplate")
    btnNaked:SetSize(ROLE_ICON_SIZE, ROLE_ICON_SIZE)
    if lastRoleBtn then
        btnNaked:SetPoint("TOPLEFT", lastRoleBtn, "TOPRIGHT", ROLE_ICON_SPACING, 0)
    else
        btnNaked:SetPoint("TOPLEFT", card, "TOPLEFT", curX, ROLE_ICON_Y)
    end
    local t = btnNaked:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    t:SetTexture("Interface\\Icons\\inv_chest_cloth_17")
    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btnNaked.tex = t
    btnNaked:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    local isCamelotTheme = sfui.theme and sfui.theme.IsCamelotActive and sfui.theme.IsCamelotActive()
    btnNaked:SetBackdropColor(0, 0, 0, 0.7)
    btnNaked:SetBackdropBorderColor(isCamelotTheme and 0.28 or 0, isCamelotTheme and 0.22 or 0,
        isCamelotTheme and 0.14 or 0, 0.85)
    btnNaked:SetAlpha(0.40)
    btnNaked:SetScript("OnClick", function()
        sfui.gear.ToggleNaked()
    end)
    btnNaked:SetScript("OnEnter", function(b)
        b:SetAlpha(1.0)
        local isNaked = sfui.gear.isNakedPaused()
        local title = isNaked and "naked (active - auto-equip paused)" or "naked (unequip gear)"
        show_tooltip(b, "ANCHOR_TOP", title, {
            { isNaked and "click to resume auto-equip and re-equip your gear." or "unequips all weapons and armor into your bags.", 0.8, 0.8, 0.8, true },
            { "leaves non-durability items (jewelry, relics/totems, shirt, tabard) equipped.", 0.6, 0.9, 0.6, true },
            { "pauses gear manager auto-equip until clicked again or role/pve/pvp is clicked.", 0.4, 0.8, 1.0, true },
        })
    end)
    btnNaked:SetScript("OnLeave", function(b)
        if not b.isSelected then
            b:SetAlpha(0.40)
        end
        hide_tooltip()
    end)
    ui.btnNaked = btnNaked
end

-- -------------------------------------------------------------------------
-- COLLAPSED ROLE BAR (Role Icons + Naked Button in Header)
-- -------------------------------------------------------------------------
function sfui.gear.UpdateCollapsedRoleBar(gearFrame)
    if not gearFrame then return end
    local bar = gearFrame.collapsedRoleBar
    if not bar then return end

    local specID = gearFrame.activeSpecID or common.get_current_spec_id()
    local numID = tonumber(specID) or 0
    local classID = (sfui.gear.GetClassicClassID and sfui.gear.GetClassicClassID(numID)) or numID
    local classicRoles = sfui.gear.CLASSIC_ROLES_BY_SPEC and
        (sfui.gear.CLASSIC_ROLES_BY_SPEC[numID] or (classID and sfui.gear.CLASSIC_ROLES_BY_SPEC[classID]))

    if not classicRoles or #classicRoles == 0 then
        bar:Hide()
        return
    end

    local totalButtons = #classicRoles + 1
    local totalWidth = (totalButtons * COLLAPSED_ROLE_SIZE) + ((totalButtons - 1) * COLLAPSED_ROLE_SPACING)

    bar:SetSize(totalWidth, COLLAPSED_ROLE_SIZE)
    bar:ClearAllPoints()
    bar:SetPoint("CENTER", gearFrame, "TOP", 0, -17)

    bar.roleBtns = bar.roleBtns or {}

    local curX = 0
    for _, rKey in ipairs(classicRoles) do
        local rBtn = bar.roleBtns[rKey]
        if not rBtn then
            rBtn = CreateFrame("Button", nil, bar, "BackdropTemplate")
            rBtn:SetSize(COLLAPSED_ROLE_SIZE, COLLAPSED_ROLE_SIZE)
            rBtn:SetFrameLevel(bar:GetFrameLevel() + 2)
            local t = rBtn:CreateTexture(nil, "ARTWORK")
            t:SetAllPoints()
            t:SetTexture(sfui.gear.GetClassicRoleIcon(classID, rKey))
            t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            rBtn.tex = t
            rBtn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            rBtn.roleKey = rKey
            rBtn.roleColor = ROLE_COLORS[rKey] or { 0.6, 0.6, 0.6 }
            local capturedRole = rKey

            rBtn:SetScript("OnClick", function()
                local activeSpec = gearFrame.activeSpecID or common.get_current_spec_id()
                sfui.gear.SelectClassicRole(activeSpec, capturedRole)
            end)
            rBtn:SetScript("OnEnter", function(b)
                b:SetAlpha(1.0)
                local rLabel = ROLE_LABELS[capturedRole] or capturedRole:lower()
                local desc = getRoleDescription(capturedRole:lower())
                show_tooltip(b, "ANCHOR_TOP", rLabel, {
                    { desc, 0.8, 0.8, 0.8, true },
                })
            end)
            rBtn:SetScript("OnLeave", function(b)
                if not b.isSelected then b:SetAlpha(0.40) end
                hide_tooltip()
            end)
            bar.roleBtns[rKey] = rBtn
        else
            rBtn.tex:SetTexture(sfui.gear.GetClassicRoleIcon(classID, rKey))
        end

        rBtn:ClearAllPoints()
        rBtn:SetPoint("LEFT", bar, "LEFT", curX, 0)
        rBtn:Show()
        curX = curX + COLLAPSED_ROLE_SIZE + COLLAPSED_ROLE_SPACING
    end

    for k, b in pairs(bar.roleBtns) do
        local found = false
        for _, rKey in ipairs(classicRoles) do
            if rKey == k then found = true; break end
        end
        if not found then b:Hide() end
    end

    local btnNaked = bar.btnNaked
    if not btnNaked then
        btnNaked = CreateFrame("Button", nil, bar, "BackdropTemplate")
        btnNaked:SetSize(COLLAPSED_ROLE_SIZE, COLLAPSED_ROLE_SIZE)
        btnNaked:SetFrameLevel(bar:GetFrameLevel() + 2)
        local t = btnNaked:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints()
        t:SetTexture("Interface\\Icons\\inv_chest_cloth_17")
        t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btnNaked.tex = t
        btnNaked:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btnNaked:SetScript("OnClick", function()
            sfui.gear.ToggleNaked()
        end)
        btnNaked:SetScript("OnEnter", function(b)
            b:SetAlpha(1.0)
            local isNaked = sfui.gear.isNakedPaused()
            local title = isNaked and "naked (active - auto-equip paused)" or "naked (unequip gear)"
            show_tooltip(b, "ANCHOR_TOP", title, {
                { isNaked and "click to resume auto-equip and re-equip your gear." or "unequips all weapons and armor into your bags.", 0.8, 0.8, 0.8, true },
                { "leaves jewelry (rings, trinkets, neck), shirt, and tabard equipped.", 0.6, 0.9, 0.6, true },
                { "pauses gear manager auto-equip until clicked again or role/pve/pvp is clicked.", 0.4, 0.8, 1.0, true },
            })
        end)
        btnNaked:SetScript("OnLeave", function(b)
            if not b.isSelected then b:SetAlpha(0.40) end
            hide_tooltip()
        end)
        bar.btnNaked = btnNaked
    end
    btnNaked:ClearAllPoints()
    btnNaked:SetPoint("LEFT", bar, "LEFT", curX, 0)
    btnNaked:Show()

    local db = SfuiDB and SfuiDB.gear and SfuiDB.gear[specID]
    local curRole = sfui.gear.GetClassicRole and sfui.gear.GetClassicRole(specID, db)
    local curRoleLower = curRole and curRole:lower()
    for rKey, rBtn in pairs(bar.roleBtns) do
        if rBtn:IsShown() then
            local isSelected = (curRoleLower == (rKey and rKey:lower()))
            styleRoleButton(rBtn, isSelected)
        end
    end
    styleNakedButton(btnNaked, sfui.gear.isNakedPaused())
end

-- -------------------------------------------------------------------------
-- UI FLAVOR REFRESH (Role buttons & naked button state)
-- -------------------------------------------------------------------------
function sfui.gear.UpdateFlavorUI(ui, specID, db)
    if ui and ui.roleBtns then
        local curRole = sfui.gear.GetClassicRole and sfui.gear.GetClassicRole(specID, db)
        local curRoleLower = curRole and curRole:lower()
        for rKey, rBtn in pairs(ui.roleBtns) do
            local isSelected = (curRoleLower == (rKey and rKey:lower()))
            styleRoleButton(rBtn, isSelected)
        end
    end

    if ui and ui.btnNaked then
        local isNaked = sfui.gear.isNakedPaused()
        styleNakedButton(ui.btnNaked, isNaked)
    end

    local gFrame = sfui.gear.frame or _G.SfuiGearManagerFrame
    if gFrame and gFrame.collapsedRoleBar and sfui.gear.UpdateCollapsedRoleBar then
        sfui.gear.UpdateCollapsedRoleBar(gFrame)
    end
end

-- -------------------------------------------------------------------------
-- WEAPON & COMBAT SKILL TELEMETRY (Camelot / Classic)
-- -------------------------------------------------------------------------
local WEAPON_SUBCLASS_TO_SKILL_ID = {
    [0]  = 44,  -- Axes (1H)
    [1]  = 172, -- Two-Handed Axes
    [2]  = 45,  -- Bows
    [3]  = 46,  -- Guns
    [4]  = 54,  -- Maces (1H)
    [5]  = 160, -- Two-Handed Maces
    [6]  = 229, -- Polearms
    [7]  = 43,  -- Swords (1H)
    [8]  = 55,  -- Two-Handed Swords
    [10] = 136, -- Staves
    [13] = 162, -- Fist Weapons / Unarmed
    [15] = 173, -- Daggers
    [16] = 176, -- Thrown
    [18] = 226, -- Crossbows
    [19] = 228, -- Wands
    [20] = 356, -- Fishing Poles
}
if Enum and Enum.ItemWeaponSubclass then
    if Enum.ItemWeaponSubclass.Axe1H then WEAPON_SUBCLASS_TO_SKILL_ID[Enum.ItemWeaponSubclass.Axe1H] = 44 end
    if Enum.ItemWeaponSubclass.Axe2H then WEAPON_SUBCLASS_TO_SKILL_ID[Enum.ItemWeaponSubclass.Axe2H] = 172 end
    if Enum.ItemWeaponSubclass.Bows then WEAPON_SUBCLASS_TO_SKILL_ID[Enum.ItemWeaponSubclass.Bows] = 45 end
    if Enum.ItemWeaponSubclass.Guns then WEAPON_SUBCLASS_TO_SKILL_ID[Enum.ItemWeaponSubclass.Guns] = 46 end
    if Enum.ItemWeaponSubclass.Mace1H then WEAPON_SUBCLASS_TO_SKILL_ID[Enum.ItemWeaponSubclass.Mace1H] = 54 end
    if Enum.ItemWeaponSubclass.Mace2H then WEAPON_SUBCLASS_TO_SKILL_ID[Enum.ItemWeaponSubclass.Mace2H] = 160 end
    if Enum.ItemWeaponSubclass.Polearm then WEAPON_SUBCLASS_TO_SKILL_ID[Enum.ItemWeaponSubclass.Polearm] = 229 end
    if Enum.ItemWeaponSubclass.Sword1H then WEAPON_SUBCLASS_TO_SKILL_ID[Enum.ItemWeaponSubclass.Sword1H] = 43 end
    if Enum.ItemWeaponSubclass.Sword2H then WEAPON_SUBCLASS_TO_SKILL_ID[Enum.ItemWeaponSubclass.Sword2H] = 55 end
    if Enum.ItemWeaponSubclass.Staff then WEAPON_SUBCLASS_TO_SKILL_ID[Enum.ItemWeaponSubclass.Staff] = 136 end
    if Enum.ItemWeaponSubclass.Unarmed then WEAPON_SUBCLASS_TO_SKILL_ID[Enum.ItemWeaponSubclass.Unarmed] = 162 end
    if Enum.ItemWeaponSubclass.Dagger then WEAPON_SUBCLASS_TO_SKILL_ID[Enum.ItemWeaponSubclass.Dagger] = 173 end
    if Enum.ItemWeaponSubclass.Thrown then WEAPON_SUBCLASS_TO_SKILL_ID[Enum.ItemWeaponSubclass.Thrown] = 176 end
    if Enum.ItemWeaponSubclass.Crossbow then WEAPON_SUBCLASS_TO_SKILL_ID[Enum.ItemWeaponSubclass.Crossbow] = 226 end
    if Enum.ItemWeaponSubclass.Wand then WEAPON_SUBCLASS_TO_SKILL_ID[Enum.ItemWeaponSubclass.Wand] = 228 end
    if Enum.ItemWeaponSubclass.Fishingpole then WEAPON_SUBCLASS_TO_SKILL_ID[Enum.ItemWeaponSubclass.Fishingpole] = 356 end
end

local cachedWeaponInfo = {
    [16] = {},
    [17] = {},
    [18] = {},
}

local function get_skill_line_info_by_id(targetSkillID)
    if not targetSkillID then return nil, nil, nil, nil end
    local C_SkillInfo = _G.C_SkillInfo
    if C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID then
        local info = C_SkillInfo.GetSkillLineInfoByID(targetSkillID)
        if info then
            return info.rank or 0, info.modifier or 0, info.maxRank or 0, info.name
        end
    end
    if C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo then
        local count = C_SkillInfo.GetNumSkillLines()
        for i = 1, count do
            local info = C_SkillInfo.GetSkillLineInfo(i)
            if info and info.skillID == targetSkillID then
                return info.rank or 0, info.modifier or 0, info.maxRank or 0, info.name
            end
        end
    end
    return nil, nil, nil, nil
end

--- Return equipped weapon details and effective skill without dynamic table churn
--- @param slotID number 16: main hand, 17: off hand, 18: ranged
--- @return table|nil
function sfui.gear.get_equipped_weapon_info(slotID)
    local pLevel = UnitLevel("player") or 60
    local baseSkill = pLevel * 5
    local targetTable = cachedWeaponInfo[slotID]
    if not targetTable then return nil end

    local pClass = (common and common.get_player_class and common.get_player_class()) or _G.UnitClassBase("player")
    local isDruidInForm = (pClass == "DRUID") and (_G.GetShapeshiftForm and _G.GetShapeshiftForm() ~= 0)
    if isDruidInForm and slotID == 16 then
        local rank, modifier, maxRank, skillName = get_skill_line_info_by_id(3014) -- FERAL_WEAPON_SKILL
        local totalSkill = (rank and (rank + (modifier or 0))) or baseSkill
        targetTable.name = "feral combat"
        targetTable.skillName = skillName or "feral combat"
        targetTable.skill = totalSkill
        targetTable.maxSkill = maxRank or baseSkill
        targetTable.skillID = 3014
        targetTable.subclassID = nil
        targetTable.classID = nil
        targetTable.link = nil
        targetTable.itemID = nil
        targetTable.isRanged = false
        targetTable.isDualWield = false
        return targetTable
    end

    local itemID = _G.GetInventoryItemID and _G.GetInventoryItemID("player", slotID)
    if not itemID then
        if slotID == 16 then
            local rank, modifier, maxRank, skillName = get_skill_line_info_by_id(162)
            local totalSkill = (rank and (rank + (modifier or 0))) or baseSkill
            targetTable.name = "unarmed"
            targetTable.skillName = skillName or "unarmed"
            targetTable.skill = totalSkill
            targetTable.maxSkill = maxRank or baseSkill
            targetTable.skillID = 162
            targetTable.subclassID = 13
            targetTable.classID = 2
            targetTable.link = nil
            targetTable.itemID = nil
            targetTable.isRanged = false
            targetTable.isDualWield = false
            return targetTable
        end
        return nil
    end

    local link = _G.GetInventoryItemLink and _G.GetInventoryItemLink("player", slotID)
    local itemName = link and (C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(link)) or (C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(itemID))
    local itemClassID, itemSubClassID
    if C_Item and C_Item.GetItemInfoInstant then
        _, _, _, _, _, itemClassID, itemSubClassID = C_Item.GetItemInfoInstant(itemID)
    end
    if not itemClassID and _G.GetItemInfo then
        local _, _, _, _, _, _, _, _, _, _, _, cID, scID = _G.GetItemInfo(itemID)
        itemClassID = cID
        itemSubClassID = scID
    end

    local weaponClass = (Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2
    if itemClassID and itemClassID ~= weaponClass then
        return nil -- Shield, off-hand frill, relic, etc.
    end

    local skillID = (itemSubClassID and WEAPON_SUBCLASS_TO_SKILL_ID[itemSubClassID]) or 162
    local rank, modifier, maxRank, skillName = get_skill_line_info_by_id(skillID)
    local totalSkill = (rank and (rank + (modifier or 0))) or baseSkill

    targetTable.name = itemName and itemName:lower() or "weapon"
    targetTable.skillName = skillName or (itemSubClassID and "weapon") or "unarmed"
    targetTable.skill = totalSkill
    targetTable.maxSkill = maxRank or baseSkill
    targetTable.skillID = skillID
    targetTable.subclassID = itemSubClassID
    targetTable.classID = itemClassID
    targetTable.link = link
    targetTable.itemID = itemID
    targetTable.isRanged = (slotID == 18)
    targetTable.isDualWield = (slotID == 17)
    return targetTable
end

sfui.gear.GetEquippedWeaponInfo = sfui.gear.get_equipped_weapon_info
