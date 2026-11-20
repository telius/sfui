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
local table = _G.table
local math = _G.math
local tonumber = _G.tonumber
local wipe = (sfui.common and sfui.common.wipe) or _G.wipe or table.wipe

local show_tooltip = sfui.gear.show_tooltip -- defined in engine.lua

local hide_tooltip = sfui.common.hide_tooltip
local set_square_icon_coords = (sfui.common and sfui.common.set_square_icon_coords)
    or function(tex) if tex and tex.SetTexCoord then tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) end end

-- -------------------------------------------------------------------------
-- CENTRALIZED DOCK & LAYOUT PARAMETERS (Option C)
-- -------------------------------------------------------------------------
local DOCK_ICON_SIZE    = 26
local DOCK_ICON_SPACING = 3
local ROLE_ICON_SIZE    = DOCK_ICON_SIZE
local ROLE_ICON_SPACING = DOCK_ICON_SPACING
local ROLE_ICON_Y       = -56

sfui.gear.HasQuickDock      = true
sfui.gear.ROLE_ICON_SIZE    = ROLE_ICON_SIZE
sfui.gear.ROLE_ICON_SPACING = ROLE_ICON_SPACING
sfui.gear.ROLE_ICON_Y       = ROLE_ICON_Y

function sfui.gear.GetHeaderHeight()
    return 34
end

function sfui.gear.GetHeaderWidth()
    return 148
end

function sfui.gear.GetCollapsedHeight()
    return 78
end

function sfui.gear.GetContentTopOffset()
    return 76
end

function sfui.gear.GetCardHeight()
    return 146
end

function sfui.gear.GetStatRowY()
    return -120
end

function sfui.gear.GetLockBaseY()
    return -40
end

function sfui.gear.GetDropdownWidth()
    return 140
end

local FALLBACK_RESIST_SCHOOLS = {
    { key = "fire",   label = "fire",   damageClass = 2, color = { 1.0, 0.55, 0.25 }, atlas = "UI-Character-Info-Resistance-Fire",   fallbackIcon = "Interface\\Icons\\Spell_Fire_FireArmor" },
    { key = "nature", label = "nature", damageClass = 3, color = { 0.45, 0.9, 0.35 }, atlas = "UI-Character-Info-Resistance-Nature", fallbackIcon = "Interface\\Icons\\Spell_Nature_ResistNature" },
    { key = "frost",  label = "frost",  damageClass = 4, color = { 0.55, 0.8, 1.0 },  atlas = "UI-Character-Info-Resistance-Frost",  fallbackIcon = "Interface\\Icons\\Spell_Frost_FrostWard" },
    { key = "shadow", label = "shadow", damageClass = 5, color = { 0.7, 0.5, 1.0 },   atlas = "UI-Character-Info-Resistance-Shadow", fallbackIcon = "Interface\\Icons\\Spell_Shadow_AntiShadow" },
    { key = "arcane", label = "arcane", damageClass = 6, color = { 0.95, 0.7, 1.0 },  atlas = "UI-Character-Info-Resistance-Arcane", fallbackIcon = "Interface\\Icons\\Spell_Nature_WispSplode" },
}

local function getResistSchools()
    return (common and common.RESIST_SCHOOLS) or FALLBACK_RESIST_SCHOOLS
end

local function getResistSchoolByKey(key)
    if common and common.RESIST_SCHOOL_BY_KEY and key then
        return common.RESIST_SCHOOL_BY_KEY[key]
    end
    for _, def in ipairs(FALLBACK_RESIST_SCHOOLS) do
        if def.key == key then return def end
    end
    return nil
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
-- CLASSIC STAT CLEANSE (Scrubs ArP, Exp & BlockVal)
-- -------------------------------------------------------------------------
function sfui.gear.SanitizeStatOrder(specID, rawOrder, pool, isTank)
    local numStats = #pool
    local clean = {}
    local seen = {}
    local dirty = false
    local statAbbrv = sfui.gear.statAbbrv or {}

    if rawOrder then
        for i = 1, #rawOrder do
            local st = rawOrder[i]
            local isInvalid = not st
                or (not isTank and sfui.gear.DEFENSIVE_STATS and sfui.gear.DEFENSIVE_STATS[st])
                or st == "ArP" or st == "Exp" or st == "ArmorPenetration" or st == "Expertise"
                or st == "BlockVal" or st == "BlockValue" or st == "blockval"
                or statAbbrv[st] == "arp" or statAbbrv[st] == "exp" or statAbbrv[st] == "bv" or statAbbrv[st] == "blockval"
            if isInvalid or seen[st] then
                dirty = true
            elseif #clean < numStats then
                seen[st] = true
                clean[#clean + 1] = st
            else
                dirty = true
            end
        end
    end

    if #clean < numStats then
        for _, cand in ipairs(pool) do
            if not seen[cand] then
                seen[cand] = true
                clean[#clean + 1] = cand
                if #clean >= numStats then break end
            end
        end
        while #clean < numStats do
            clean[#clean + 1] = pool[#clean + 1] or "none"
        end
    end

    if (dirty or (rawOrder and #rawOrder ~= numStats)) and SfuiDB and SfuiDB.gear and SfuiDB.gear[specID] and SfuiDB.gear[specID].stat_order then
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

local function applyInactiveDockButtonBorder(btn, bgAlpha)
    local isCamelotTheme = sfui.theme and sfui.theme.IsCamelotActive and sfui.theme.IsCamelotActive()
    if isCamelotTheme then
        btn:SetBackdropBorderColor(0.28, 0.22, 0.14, 0.85)
    else
        btn:SetBackdropBorderColor(0, 0, 0, 0.8)
    end
    btn:SetBackdropColor(0, 0, 0, bgAlpha or 0.7)
end

local function createDockDivider(parent, w, h)
    local div = parent:CreateTexture(nil, "ARTWORK")
    div:SetSize(w or 1, h or 20)
    if div.SetColorTexture then
        div:SetColorTexture(1, 1, 1, 0.14)
    else
        div:SetTexture("Interface\\Buttons\\WHITE8x8")
        if div.SetVertexColor then div:SetVertexColor(1, 1, 1, 0.14) end
    end
    return div
end

local function styleRoleButton(btn, isSelected, modeDimmed)
    if not btn then return end
    btn.isSelected = isSelected
    btn.modeDimmed = modeDimmed == true
    if btn.tex then
        btn.tex:SetDesaturated(not isSelected)
        btn:SetAlpha(isSelected and (btn.modeDimmed and 0.65 or 1.0) or 0.40)
        if isSelected then
            local c = btn.roleColor or { 0.95, 0.85, 0.55 }
            btn:SetBackdropBorderColor(c[1], c[2], c[3], 1.0)
            btn:SetBackdropColor(c[1] * 0.25, c[2] * 0.25, c[3] * 0.25, 0.9)
        else
            applyInactiveDockButtonBorder(btn, 0.7)
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
            applyInactiveDockButtonBorder(btn, 0.7)
        end
    end
end

local function styleResistButton(btn, isActive, maxResist)
    if not btn then return end
    btn.isSelected = isActive == true
    btn.maxResist = maxResist or 0
    if btn.tex then
        btn.tex:SetDesaturated(not isActive and btn.maxResist <= 0)
    end
    if isActive then
        local c = btn.schoolColor or { 0.95, 0.85, 0.55 }
        btn:SetAlpha(1.0)
        btn:SetBackdropBorderColor(c[1], c[2], c[3], 1.0)
        btn:SetBackdropColor(c[1] * 0.28, c[2] * 0.28, c[3] * 0.28, 0.95)
    elseif btn.maxResist > 0 then
        btn:SetAlpha(0.78)
        applyInactiveDockButtonBorder(btn, 0.7)
    else
        btn:SetAlpha(0.30)
        applyInactiveDockButtonBorder(btn, 0.7)
    end
    if btn.countFS then
        if btn.maxResist > 0 then
            btn.countFS:SetText(tostring(btn.maxResist))
            if btn.countFS.SetTextColor then
                if isActive then
                    btn.countFS:SetTextColor(1.0, 1.0, 1.0)
                else
                    btn.countFS:SetTextColor(0.90, 0.88, 0.80)
                end
            end
            btn.countFS:Show()
        else
            btn.countFS:SetText("")
            btn.countFS:Hide()
        end
    end
end

local function updateResistSummaryText(ui, gFrame)
    if not ui or not ui.resistLine1 or not ui.resistLine2 then return end
    local frame = gFrame or sfui.gear.frame or _G.SfuiGearManagerFrame
    local hoveredKey = frame and frame._hoveredResistSchool
    local activeKey = sfui.gear.GetActiveResistSchool and sfui.gear.GetActiveResistSchool()
    local previewKey = hoveredKey or activeKey

    if previewKey then
        local def = getResistSchoolByKey(previewKey)
        local label = (def and def.label) or previewKey
        local c = (def and def.color) or { 0.95, 0.85, 0.55 }
        local summary = sfui.highest and sfui.highest.GetResistSummary and sfui.highest.GetResistSummary(previewKey)
        local curR = summary and summary.currentResist or 0
        local maxR = summary and summary.targetResist or 0
        local delta = summary and summary.delta or 0
        local suffix = (activeKey == previewKey) and " (locked)"
            or (delta > 0 and (" (+" .. delta .. ")")) or ""
        ui.resistLine1:SetText(string.format("%s: %d / %d%s", label, curR, maxR, suffix))
        ui.resistLine1:SetTextColor(c[1], c[2], c[3])

        if summary and (summary.swapCount or 0) > 0 then
            ui.resistLine2:SetText(string.format("%d swap(s) · r-click: upgrades", summary.swapCount))
        elseif activeKey == previewKey then
            ui.resistLine2:SetText("locked · click element to unlock")
        else
            ui.resistLine2:SetText("right-click element: upgrades")
        end
        ui.resistLine2:SetTextColor(0.72, 0.72, 0.75)
    else
        ui.resistLine1:SetText("click element above to lock")
        ui.resistLine1:SetTextColor(0.68, 0.65, 0.58)
        ui.resistLine2:SetText("right-click element: upgrades")
        ui.resistLine2:SetTextColor(0.52, 0.50, 0.45)
    end
end

function sfui.gear.UpdateResistSummaryUI(gFrame)
    local frame = gFrame or sfui.gear.frame or _G.SfuiGearManagerFrame
    if not frame or not frame.specUIs then return end
    local specID = frame.activeSpecID or (common and common.get_current_spec_id and common.get_current_spec_id())
    local ui = specID and frame.specUIs[specID]
    if ui then
        updateResistSummaryText(ui, frame)
    end
end

function sfui.gear.ToggleResistSchool(schoolKey)
    if InCombatLockdown() then
        sfui.common.print("cannot change resistance gear while in combat.")
        return
    end
    if type(schoolKey) ~= "string" then return end
    local keyLower = schoolKey:lower()
    if not getResistSchoolByKey(keyLower) then return end

    local activeSchool = sfui.gear.GetActiveResistSchool and sfui.gear.GetActiveResistSchool()
    if activeSchool == keyLower then
        if sfui.gear.SetActiveResistSchool then
            sfui.gear.SetActiveResistSchool(nil)
        end
        if sfui.highest then
            if sfui.highest.ClearValidationCache then sfui.highest.ClearValidationCache() end
            if sfui.highest.ClearCache then sfui.highest.ClearCache() end
        end
        sfui.gear.UpdateStatUI()
        sfui.gear.Update(true)
        if sfui.highest and sfui.highest.EquipHighestILvl then
            sfui.highest.EquipHighestILvl(sfui.gear.isCurrentlyPvP and sfui.gear.isCurrentlyPvP() or false)
        end
        sfui.common.print(keyLower .. " resist: disabled; restoring normal gear.")
    else
        if sfui.highest and sfui.highest.ClearCache then
            sfui.highest.ClearCache()
        end
        local ok = sfui.highest and sfui.highest.EquipMaxResist and sfui.highest.EquipMaxResist(keyLower)
        if ok and sfui.gear.SetActiveResistSchool then
            sfui.gear.SetActiveResistSchool(keyLower)
        end
    end
end

-- -------------------------------------------------------------------------
-- CENTRALIZED ROLE SELECTION ACTION
-- -------------------------------------------------------------------------
function sfui.gear.SelectClassicRole(specID, rKey)
    local numID = tonumber(specID) or 0
    if sfui.gear.SetNakedPaused then sfui.gear.SetNakedPaused(false, true) end
    if sfui.gear.SetActiveResistSchool then sfui.gear.SetActiveResistSchool(nil, true) end
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
        if bridge.retailID and bridge.retailID ~= specID and SfuiDB.gear[bridge.retailID] then
            local rb = SfuiDB.gear[bridge.retailID]
            rb.user_selected_role = true
            rb.classic_role = rKey
            rb.role = sdb.role
            rb.is_tank = sdb.is_tank
            rb.armor_ilvl_prio = sdb.armor_ilvl_prio
            rb.is_healer = sdb.is_healer
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
    if sfui.talents and sfui.talents.invalidate_protection_paladin_cache then
        sfui.talents.invalidate_protection_paladin_cache()
    end
    if sfui.buffs and sfui.buffs.scan and sfui.buffs.scan.RefreshSpellKnowledge then
        sfui.buffs.scan.RefreshSpellKnowledge()
        sfui.buffs.scan.RequestScan()
    end
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_GEAR_ROLE_CHANGED", specID, rKey)
        sfui.events.SendMessage("SFUI_ROLE_CONTEXT_CHANGED", rKey, specID)
    end
    sfui.gear.UpdateStatUI()
    sfui.gear.Update()

    local curSpec = common.get_current_spec_id()
    local isMatch = (not curSpec) or (curSpec == specID)
        or (tonumber(curSpec) and tonumber(specID) and tonumber(curSpec) == tonumber(specID))
        or (sfui.gear.is_spec_match and sfui.gear.is_spec_match(curSpec, specID))
    if isMatch then
        C_Timer.After(0.18, function()
            local isResistLocked = sfui.gear.isResistLocked and sfui.gear.isResistLocked()
            if not sfui.gear.isNakedPaused() and not isResistLocked and sfui.highest and sfui.highest.EquipHighestILvl then
                sfui.highest.EquipHighestILvl(sfui.gear.isCurrentlyPvP())
            end
        end)
    end
end

-- -------------------------------------------------------------------------
-- PERSISTENT QUICK-ACTION DOCK (Roles + 5 Element Resists + Naked + Modes)
-- -------------------------------------------------------------------------
local function createDockRoleButton(dock, gearFrame, classID, rKey)
    local rLabel = ROLE_LABELS[rKey] or rKey:lower()
    local rBtn = CreateFrame("Button", nil, dock, "BackdropTemplate")
    rBtn:SetSize(DOCK_ICON_SIZE, DOCK_ICON_SIZE)
    rBtn:SetFrameLevel(dock:GetFrameLevel() + 2)
    local t = rBtn:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    t:SetTexture(sfui.gear.GetClassicRoleIcon(classID, rKey))
    set_square_icon_coords(t)
    rBtn.tex = t
    rBtn:SetBackdrop(sfui.widgets.FLAT_BACKDROP)
    applyInactiveDockButtonBorder(rBtn, 0.7)
    rBtn:SetAlpha(0.40)
    rBtn.roleKey = rKey
    rBtn.roleColor = ROLE_COLORS[rKey] or { 0.6, 0.6, 0.6 }
    local capturedRole = rKey
    rBtn:SetScript("OnClick", function()
        local activeSpec = gearFrame.activeSpecID or common.get_current_spec_id()
        sfui.gear.SelectClassicRole(activeSpec, capturedRole)
    end)
    rBtn:SetScript("OnEnter", function(b)
        b:SetAlpha(1.0)
        local desc = getRoleDescription(capturedRole:lower())
        show_tooltip(b, "ANCHOR_TOP", rLabel, {
            { desc, 0.8, 0.8, 0.8, true },
        })
    end)
    rBtn:SetScript("OnLeave", function(b)
        styleRoleButton(b, b.isSelected, b.modeDimmed)
        hide_tooltip()
    end)
    return rBtn
end

local function createDockResistButton(dock, gearFrame, def)
    local rBtn = CreateFrame("Button", nil, dock, "BackdropTemplate")
    rBtn:SetSize(DOCK_ICON_SIZE, DOCK_ICON_SIZE)
    rBtn:SetFrameLevel(dock:GetFrameLevel() + 2)
    rBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local t = rBtn:CreateTexture(nil, "ARTWORK")
    t:SetPoint("TOPLEFT", rBtn, "TOPLEFT", 2, -2)
    t:SetPoint("BOTTOMRIGHT", rBtn, "BOTTOMRIGHT", -2, 2)
    if t.SetAtlas and _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo(def.atlas) then
        t:SetAtlas(def.atlas)
        rBtn._usesAtlas = true
    else
        t:SetTexture(def.fallbackIcon)
        set_square_icon_coords(t)
        rBtn._usesAtlas = false
    end
    rBtn.tex = t

    local countFS = rBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if countFS.SetFont then
        local fontPath = (sfui.config and sfui.config.fontFile) or "Fonts\\FRIZQT__.TTF"
        countFS:SetFont(fontPath, 9, "OUTLINE")
    end
    countFS:SetPoint("BOTTOMRIGHT", rBtn, "BOTTOMRIGHT", -1, 1)
    countFS:SetJustifyH("RIGHT")
    if countFS.SetShadowOffset then countFS:SetShadowOffset(1, -1) end
    countFS:SetText("")
    countFS:Hide()
    rBtn.countFS = countFS

    rBtn:SetBackdrop(sfui.widgets.FLAT_BACKDROP)
    rBtn.schoolKey = def.key
    rBtn.schoolColor = def.color or { 0.95, 0.85, 0.55 }
    styleResistButton(rBtn, false, 0)

    local capturedDef = def
    rBtn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if sfui.upgrades and sfui.upgrades.Open then
                sfui.upgrades.Open(capturedDef.key)
            end
        else
            sfui.gear.ToggleResistSchool(capturedDef.key)
        end
    end)

    rBtn:SetScript("OnEnter", function(b)
        b:SetAlpha(1.0)
        gearFrame._hoveredResistSchool = capturedDef.key
        sfui.gear.UpdateResistSummaryUI(gearFrame)

        local activeSchool = sfui.gear.GetActiveResistSchool and sfui.gear.GetActiveResistSchool()
        local isActive = (activeSchool == capturedDef.key)
        local summary = sfui.highest and sfui.highest.GetResistSummary and sfui.highest.GetResistSummary(capturedDef.key)
        local curR = summary and summary.currentResist or 0
        local maxR = summary and summary.targetResist or 0
        local delta = summary and summary.delta or 0

        local title = capturedDef.label .. " resistance" .. (isActive and " [locked]" or "")
        local lines = {}
        if maxR > 0 then
            local sumLine = (delta > 0)
                and string.format("equipped: %d | max in bags: %d (+%d)", curR, maxR, delta)
                or string.format("equipped: %d | max in bags: %d", curR, maxR)
            lines[#lines + 1] = { sumLine, capturedDef.color[1], capturedDef.color[2], capturedDef.color[3], true }
        else
            lines[#lines + 1] = { "no " .. capturedDef.label .. " resist gear in bags or equipped", 0.65, 0.65, 0.65, true }
        end

        if summary and summary.swaps and #summary.swaps > 0 then
            local shown = 0
            for _, sw in ipairs(summary.swaps) do
                if shown >= 6 then break end
                local slotName = (common and common.get_slot_name and common.get_slot_name(sw.slotID) or ("slot " .. tostring(sw.slotID))):lower()
                local newName = sw.newLink and ((common.get_item_info and select(1, common.get_item_info(sw.newLink))) or sw.newLink) or "empty"
                if type(newName) == "string" then
                    newName = newName:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower()
                else
                    newName = "item"
                end
                local gain = (sw.newResist or 0) - (sw.oldResist or 0)
                local gainStr = (gain > 0 and (" (+" .. gain .. ")")) or (gain < 0 and (" (" .. gain .. ")")) or ""
                lines[#lines + 1] = { slotName .. ": " .. newName .. gainStr, 0.8, 0.8, 0.8, true }
                shown = shown + 1
            end
            if #summary.swaps > 6 then
                lines[#lines + 1] = { "+" .. tostring(#summary.swaps - 6) .. " more swaps", 0.65, 0.65, 0.65, true }
            end
        elseif isActive and maxR > 0 then
            lines[#lines + 1] = { "wearing max available " .. capturedDef.label .. " resist", 0.6, 0.9, 0.6, true }
        end

        lines[#lines + 1] = {
            isActive and "left-click: unlock & restore normal gear" or ("left-click: equip max " .. capturedDef.label .. " resist & lock"),
            0.4, 0.8, 1.0, true,
        }
        lines[#lines + 1] = { "right-click: browse " .. capturedDef.label .. " resist upgrades", 0.7, 0.7, 0.75, true }
        show_tooltip(b, "ANCHOR_TOP", title, lines)
    end)

    rBtn:SetScript("OnLeave", function(b)
        gearFrame._hoveredResistSchool = nil
        styleResistButton(b, b.isSelected, b.maxResist)
        sfui.gear.UpdateResistSummaryUI(gearFrame)
        hide_tooltip()
    end)
    return rBtn
end

local function createDockNakedButton(dock)
    local btnNaked = CreateFrame("Button", nil, dock, "BackdropTemplate")
    btnNaked:SetSize(DOCK_ICON_SIZE, DOCK_ICON_SIZE)
    btnNaked:SetFrameLevel(dock:GetFrameLevel() + 2)
    local t = btnNaked:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    t:SetTexture("Interface\\Icons\\inv_chest_cloth_17")
    set_square_icon_coords(t)
    btnNaked.tex = t
    btnNaked:SetBackdrop(sfui.widgets.FLAT_BACKDROP)
    applyInactiveDockButtonBorder(btnNaked, 0.7)
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
            { "pauses gear manager auto-equip until clicked again or role/pve/pvp/resist is clicked.", 0.4, 0.8, 1.0, true },
        })
    end)
    btnNaked:SetScript("OnLeave", function(b)
        styleNakedButton(b, b.isSelected)
        hide_tooltip()
    end)
    return btnNaked
end

function sfui.gear.BuildQuickDock(gearFrame)
    if not gearFrame then return nil end
    if gearFrame.quickDock then return gearFrame.quickDock end

    local dock = CreateFrame("Frame", nil, gearFrame, "BackdropTemplate")
    dock:SetPoint("TOPLEFT", gearFrame, "TOPLEFT", 8, -34)
    dock:SetPoint("TOPRIGHT", gearFrame, "TOPRIGHT", -8, -34)
    dock:SetHeight(36)
    dock:SetFrameLevel((gearFrame:GetFrameLevel() or 1) + 4)
    if sfui.theme and sfui.theme.ApplyContainerStyle then
        sfui.theme.ApplyContainerStyle(dock)
    end
    dock:Show()

    dock.roleBtns = {}
    dock.resistBtns = {}
    dock.div1 = createDockDivider(dock, 1, 20)
    dock.div2 = createDockDivider(dock, 1, 20)

    local schools = getResistSchools()
    for _, def in ipairs(schools) do
        dock.resistBtns[def.key] = createDockResistButton(dock, gearFrame, def)
    end

    dock.btnNaked = createDockNakedButton(dock)
    gearFrame.quickDock = dock
    return dock
end

function sfui.gear.UpdateQuickDock(gearFrame)
    if not gearFrame then return end
    if gearFrame.collapsedRoleBar then gearFrame.collapsedRoleBar:Hide() end
    local dock = gearFrame.quickDock or sfui.gear.BuildQuickDock(gearFrame)
    if not dock then return end
    dock:Show()

    local specID = gearFrame.activeSpecID or (common and common.get_current_spec_id and common.get_current_spec_id())
    local numID = tonumber(specID) or 0
    local classID = (sfui.gear.GetClassicClassID and sfui.gear.GetClassicClassID(numID)) or numID
    local classicRoles = sfui.gear.CLASSIC_ROLES_BY_SPEC and
        (sfui.gear.CLASSIC_ROLES_BY_SPEC[numID] or (classID and sfui.gear.CLASSIC_ROLES_BY_SPEC[classID]))

    local activeSchool = sfui.gear.GetActiveResistSchool and sfui.gear.GetActiveResistSchool()
    local isNaked = sfui.gear.isNakedPaused and sfui.gear.isNakedPaused() or false
    local modeDimmed = (activeSchool ~= nil) or isNaked

    local db = SfuiDB and SfuiDB.gear and SfuiDB.gear[specID]
    local curRole = sfui.gear.GetClassicRole and sfui.gear.GetClassicRole(specID, db)
    local curRoleLower = curRole and curRole:lower()

    local curX = 8
    dock.roleBtns = dock.roleBtns or {}
    local activeRoleMap = {}
    if classicRoles and #classicRoles > 0 then
        for _, rKey in ipairs(classicRoles) do
            activeRoleMap[rKey] = true
            local rBtn = dock.roleBtns[rKey]
            if not rBtn then
                rBtn = createDockRoleButton(dock, gearFrame, classID, rKey)
                dock.roleBtns[rKey] = rBtn
            else
                rBtn.tex:SetTexture(sfui.gear.GetClassicRoleIcon(classID, rKey))
            end
            rBtn:ClearAllPoints()
            rBtn:SetPoint("LEFT", dock, "LEFT", curX, 0)
            rBtn:Show()
            local isSelected = (curRoleLower == (rKey and rKey:lower()))
            styleRoleButton(rBtn, isSelected, modeDimmed)
            curX = curX + DOCK_ICON_SIZE + DOCK_ICON_SPACING
        end
        dock.div1:ClearAllPoints()
        dock.div1:SetPoint("LEFT", dock, "LEFT", curX + 6 - DOCK_ICON_SPACING, 0)
        dock.div1:Show()
        curX = curX + 13 - DOCK_ICON_SPACING
    else
        dock.div1:Hide()
    end

    for k, b in pairs(dock.roleBtns) do
        if not activeRoleMap[k] then b:Hide() end
    end

    local schools = getResistSchools()
    for _, def in ipairs(schools) do
        local rBtn = dock.resistBtns and dock.resistBtns[def.key]
        if rBtn then
            local summary = sfui.highest and sfui.highest.GetResistSummary and sfui.highest.GetResistSummary(def.key)
            local maxR = summary and summary.targetResist or 0
            rBtn:ClearAllPoints()
            rBtn:SetPoint("LEFT", dock, "LEFT", curX, 0)
            rBtn:Show()
            styleResistButton(rBtn, activeSchool == def.key, maxR)
            curX = curX + DOCK_ICON_SIZE + DOCK_ICON_SPACING
        end
    end

    dock.div2:ClearAllPoints()
    dock.div2:SetPoint("LEFT", dock, "LEFT", curX + 6 - DOCK_ICON_SPACING, 0)
    dock.div2:Show()
    curX = curX + 13 - DOCK_ICON_SPACING

    if dock.btnNaked then
        dock.btnNaked:ClearAllPoints()
        dock.btnNaked:SetPoint("LEFT", dock, "LEFT", curX, 0)
        dock.btnNaked:Show()
        styleNakedButton(dock.btnNaked, isNaked)
    end
end

function sfui.gear.UpdateCollapsedRoleBar(gearFrame)
    if gearFrame and gearFrame.collapsedRoleBar then
        gearFrame.collapsedRoleBar:Hide()
    end
    sfui.gear.UpdateQuickDock(gearFrame)
end

-- -------------------------------------------------------------------------
-- CONFIG DRAWER RIGHT PANEL (Off-Armor Toggle & Live Resist Readout)
-- -------------------------------------------------------------------------
local function styleOffArmorButton(btn, enabled)
    if not btn then return end
    local useAH = sfui.theme and sfui.theme.IsAuctionHouseButtonActive and sfui.theme.IsAuctionHouseButtonActive()
    if enabled then
        btn:SetText("|cff66ff66off-armor: on|r")
        if useAH then
            sfui.theme.SetButtonSelected(btn, true)
            btn:SetBackdropBorderColor(0, 0, 0, 0)
            btn:SetBackdropColor(0, 0, 0, 0)
        else
            local p = sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()
            local acc = p and p.accentColor or { 0.95, 0.85, 0.55 }
            btn:SetBackdropBorderColor(acc[1], acc[2], acc[3], 0.9)
            btn:SetBackdropColor(acc[1] * 0.25, acc[2] * 0.25, acc[3] * 0.25, 0.95)
        end
    else
        btn:SetText("|cff888888off-armor: off|r")
        if useAH then
            sfui.theme.SetButtonSelected(btn, false)
            btn:SetBackdropBorderColor(0, 0, 0, 0)
            btn:SetBackdropColor(0, 0, 0, 0)
        else
            local isCamelot = sfui.theme and sfui.theme.IsCamelotActive and sfui.theme.IsCamelotActive()
            if isCamelot then
                btn:SetBackdropBorderColor(0.28, 0.22, 0.14, 0.85)
                btn:SetBackdropColor(0.12, 0.10, 0.08, 0.95)
            else
                btn:SetBackdropBorderColor(0, 0, 0, 1)
                btn:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
            end
        end
    end
end

function sfui.gear.BuildCardModifiers(card, ui, specID, curLockX)
    if not card or not ui then return end

    local vDiv = createDockDivider(card, 1, 68)
    vDiv:SetPoint("TOPLEFT", card, "TOPLEFT", 297, -40)
    ui.lockRightDivider = vDiv

    local offArmorBtn = common.create_flat_button(card, "off-armor: on", 158, 22)
    offArmorBtn:SetPoint("TOPLEFT", card, "TOPLEFT", 308, -44)
    function offArmorBtn:UpdateState(enabled)
        styleOffArmorButton(self, enabled)
    end
    offArmorBtn:SetScript("OnClick", function()
        if sfui.gear.SetResistOffArmorEnabled and sfui.gear.IsResistOffArmorEnabled then
            sfui.gear.SetResistOffArmorEnabled(not sfui.gear.IsResistOffArmorEnabled())
        end
    end)
    offArmorBtn:SetScript("OnEnter", function(b)
        if sfui.theme and sfui.theme.IsAuctionHouseButtonActive and sfui.theme.IsAuctionHouseButtonActive() then
            if b._sfuiAHHighlight then b._sfuiAHHighlight:Show() end
            if b.SetBackdropBorderColor then b:SetBackdropBorderColor(0, 0, 0, 0) end
            if b.SetBackdropColor then b:SetBackdropColor(0, 0, 0, 0) end
        else
            local p = sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()
            local hl = (p and p.highlightColor) or (sfui.config and sfui.config.colors and sfui.config.colors.cyan) or { 0, 1, 1 }
            b:SetBackdropBorderColor(hl[1], hl[2], hl[3], 1)
        end
        show_tooltip(b, "ANCHOR_TOP", "off-armor resist gear", {
            { "on: include lower wearable armor types in bags (e.g. leather or mail for plate classes).", 0.8, 0.8, 0.8, true },
            { "off: restrict resist gear to your primary armor class (neck, rings, trinkets, cloak unchanged).", 0.8, 0.8, 0.8, true },
        })
    end)
    offArmorBtn:SetScript("OnLeave", function(b)
        hide_tooltip()
        if sfui.theme and sfui.theme.IsAuctionHouseButtonActive and sfui.theme.IsAuctionHouseButtonActive() then
            if b._sfuiAHHighlight then b._sfuiAHHighlight:Hide() end
        end
        b:UpdateState(sfui.gear.IsResistOffArmorEnabled and sfui.gear.IsResistOffArmorEnabled() or false)
    end)
    ui.offArmorBtn = offArmorBtn

    local line1 = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    line1:SetPoint("TOPLEFT", card, "TOPLEFT", 308, -72)
    line1:SetWidth(158)
    line1:SetJustifyH("LEFT")
    line1:SetWordWrap(false)
    line1:SetShadowOffset(0, 0)
    ui.resistLine1 = line1

    local line2 = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    line2:SetPoint("TOPLEFT", card, "TOPLEFT", 308, -88)
    line2:SetWidth(158)
    line2:SetJustifyH("LEFT")
    line2:SetWordWrap(false)
    line2:SetShadowOffset(0, 0)
    ui.resistLine2 = line2

    offArmorBtn:UpdateState(sfui.gear.IsResistOffArmorEnabled and sfui.gear.IsResistOffArmorEnabled() or true)
    updateResistSummaryText(ui)
end

-- -------------------------------------------------------------------------
-- UI FLAVOR REFRESH (Off-armor toggle, resist readout, quick dock)
-- -------------------------------------------------------------------------
function sfui.gear.UpdateFlavorUI(ui, specID, db)
    if ui and ui.offArmorBtn and ui.offArmorBtn.UpdateState then
        local enabled = (sfui.gear.IsResistOffArmorEnabled == nil) or sfui.gear.IsResistOffArmorEnabled()
        ui.offArmorBtn:UpdateState(enabled)
    end

    local gFrame = sfui.gear.frame or _G.SfuiGearManagerFrame
    if ui then
        updateResistSummaryText(ui, gFrame)
    end
    if gFrame and sfui.gear.UpdateQuickDock then
        sfui.gear.UpdateQuickDock(gFrame)
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

local cachedWeaponInfo = {
    [16] = {},
    [17] = {},
    [18] = {},
}
sfui.gear._cachedWeaponInfo = cachedWeaponInfo
sfui.gear._weaponSubclassToSkillID = WEAPON_SUBCLASS_TO_SKILL_ID

local function get_classic_slot_attack_skill(slotID)
    if slotID == 16 or slotID == 17 then
        if _G.UnitAttackBothHands then
            local mhBase, mhMod, ohBase, ohMod = _G.UnitAttackBothHands("player")
            if slotID == 16 then
                return tonumber(mhBase), tonumber(mhMod) or 0
            else
                return tonumber(ohBase), tonumber(ohMod) or 0
            end
        end
    elseif slotID == 18 then
        if _G.UnitRangedAttack then
            local rBase, rMod = _G.UnitRangedAttack("player")
            return tonumber(rBase), tonumber(rMod) or 0
        end
    end
    return nil, nil
end

local function get_skill_line_info_by_id(targetSkillID, slotID, fallbackSubClassID)
    if targetSkillID then
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
    end

    local slotRank, slotMod = get_classic_slot_attack_skill(slotID)
    local subClassName = fallbackSubClassID and C_Item and C_Item.GetItemSubClassInfo and C_Item.GetItemSubClassInfo(2, fallbackSubClassID)
    if _G.GetNumSkillLines and _G.GetSkillLineInfo and subClassName then
        local count = _G.GetNumSkillLines() or 0
        local targetLower = subClassName:lower()
        for i = 1, count do
            local name, isHeader, _, rank, _, modifier, maxRank = _G.GetSkillLineInfo(i)
            if not isHeader and name and name:lower() == targetLower then
                return slotRank or rank or 0, (slotRank and slotMod) or modifier or 0, maxRank or 0, name
            end
        end
    end

    if slotRank and slotRank > 0 then
        return slotRank, slotMod or 0, nil, subClassName
    end
    return nil, nil, nil, subClassName
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
        local rank, modifier, maxRank, skillName = get_skill_line_info_by_id(3014, 16) -- FERAL_WEAPON_SKILL
        local totalSkill = (rank and (rank + (modifier or 0))) or baseSkill
        targetTable.name = "feral combat"
        targetTable.skillName = skillName or "feral combat"
        targetTable.skill = totalSkill
        targetTable.baseSkill = rank or baseSkill
        targetTable.skillMod = modifier or 0
        targetTable.maxSkill = (maxRank and maxRank > 0 and maxRank) or baseSkill
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
            local rank, modifier, maxRank, skillName = get_skill_line_info_by_id(162, 16, 13)
            local totalSkill = (rank and (rank + (modifier or 0))) or baseSkill
            targetTable.name = "unarmed"
            targetTable.skillName = skillName or "unarmed"
            targetTable.skill = totalSkill
            targetTable.baseSkill = rank or baseSkill
            targetTable.skillMod = modifier or 0
            targetTable.maxSkill = (maxRank and maxRank > 0 and maxRank) or baseSkill
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
    local rank, modifier, maxRank, skillName = get_skill_line_info_by_id(skillID, slotID, itemSubClassID)
    local totalSkill = (rank and (rank + (modifier or 0))) or baseSkill

    local resolvedSkillName = skillName
    if not resolvedSkillName and itemSubClassID then
        resolvedSkillName = C_Item and C_Item.GetItemSubClassInfo and C_Item.GetItemSubClassInfo(2, itemSubClassID)
    end

    targetTable.name = itemName and itemName:lower() or "weapon"
    targetTable.skillName = (resolvedSkillName and resolvedSkillName:lower()) or (itemSubClassID and "weapon") or "unarmed"
    targetTable.skill = totalSkill
    targetTable.baseSkill = rank or baseSkill
    targetTable.skillMod = modifier or 0
    targetTable.maxSkill = (maxRank and maxRank > 0 and maxRank) or baseSkill
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

if sfui.gear.frame and sfui.gear.frame.EnsureFlavorLayout then
    sfui.gear.frame:EnsureFlavorLayout()
end
