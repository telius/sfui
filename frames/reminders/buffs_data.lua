local addonName, addon = ...
sfui = sfui or {}
sfui.buffs = sfui.buffs or {}
sfui.buffs.data = {}

local _G = _G
local ipairs, pairs = _G.ipairs, _G.pairs
local UnitClass = _G.UnitClass
local IsPlayerSpell = _G.IsPlayerSpell
local IsSpellKnown = _G.IsSpellKnown
local GetSpellInfo = _G.GetSpellInfo
local GetSpellTexture = _G.GetSpellTexture
local C_Spell = _G.C_Spell

local playerClass = sfui.common.get_player_class()
sfui.buffs.playerClass = playerClass

-- Helper to safely get spell texture
local function ResolveTexture(spellID, fallback)
    if spellID then
        if sfui.api and sfui.api.GetSpellTexture then
            local tex = sfui.api.GetSpellTexture(spellID)
            if tex then return tex end
        end
        if C_Spell and C_Spell.GetSpellTexture then
            local tex = C_Spell.GetSpellTexture(spellID)
            if tex then return tex end
        end
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(spellID)
            if info and (info.iconID or info.originalIconID) then
                return info.iconID or info.originalIconID
            end
        end
        if GetSpellInfo then
            local _, _, tex = GetSpellInfo(spellID)
            if tex then return tex end
        end
        if GetSpellTexture then
            local tex = GetSpellTexture(spellID)
            if tex then return tex end
        end
    end
    return fallback or "Interface\\Icons\\INV_Misc_QuestionMark"
end
sfui.buffs.data.ResolveTexture = ResolveTexture

local function CheckFlyoutSlot(flyoutID, targetSpellID)
    if not flyoutID then return false end
    local getInfo = _G.GetFlyoutInfo or (_G.C_SpellBook and _G.C_SpellBook.GetFlyoutInfo)
    local getSlot = _G.GetFlyoutSlotInfo or (_G.C_SpellBook and _G.C_SpellBook.GetFlyoutSlotInfo)
    if not getInfo or not getSlot then return false end
    local info1, _, info3 = getInfo(flyoutID)
    local numSlots = (type(info1) == "table" and info1.numSlots) or info3 or 0
    for i = 1, numSlots do
        local r1, r2, r3 = getSlot(flyoutID, i)
        local sID, isKnown
        if type(r1) == "table" then
            sID = r1.spellID or r1.overrideSpellID
            isKnown = r1.isKnown
        else
            sID = r1
            local overrideID = r2
            isKnown = r3
            if overrideID == targetSpellID then sID = overrideID end
        end
        if sID == targetSpellID and isKnown then
            return true
        end
    end
    return false
end

-- Helper to check if player knows a specific spell ID across all WoW clients and engines
local function IsSpellActuallyKnown(targetSpellID)
    if not targetSpellID or targetSpellID <= 0 then return false end

    -- Verify player level requirement first if available from spell APIs
    local minLevel = nil
    if _G.C_Spell and _G.C_Spell.GetSpellLevelLearned then
        minLevel = _G.C_Spell.GetSpellLevelLearned(targetSpellID)
    elseif _G.GetSpellLevelLearned then
        minLevel = _G.GetSpellLevelLearned(targetSpellID)
    end
    if minLevel and minLevel > 0 then
        local pLevel = (_G.UnitLevel and _G.UnitLevel("player")) or 1
        if pLevel < minLevel then
            return false
        end
    end

    local talents = sfui.talents
    if talents and talents._talentKnownResolver then
        if talents._talentKnownResolver(targetSpellID) then return true end
    end

    local cBook = _G.C_SpellBook
    local bank = (_G.Enum and _G.Enum.SpellBookSpellBank and _G.Enum.SpellBookSpellBank.Player) or 1
    if cBook then
        if cBook.IsSpellKnown and cBook.IsSpellKnown(targetSpellID, bank) then return true end
        if cBook.FindSpellBookSlotForSpell then
            local slotIndex, spellBank = cBook.FindSpellBookSlotForSpell(targetSpellID, false, true, false, false)
            if slotIndex and spellBank then
                local itemType, actionID = cBook.GetSpellBookItemType and cBook.GetSpellBookItemType(slotIndex, spellBank)
                local futureType = _G.Enum and _G.Enum.SpellBookItemType and _G.Enum.SpellBookItemType.FutureSpell
                local flyoutType = _G.Enum and _G.Enum.SpellBookItemType and _G.Enum.SpellBookItemType.Flyout
                local isOffSpec = cBook.IsSpellBookItemOffSpec and cBook.IsSpellBookItemOffSpec(slotIndex, spellBank)
                if not isOffSpec then
                    if futureType and itemType == futureType then
                        return false
                    elseif flyoutType and itemType == flyoutType then
                        if CheckFlyoutSlot(actionID, targetSpellID) then
                            return true
                        end
                    elseif not futureType or itemType ~= futureType then
                        return true
                    end
                end
            end
        end
    end

    local cSpell = _G.C_Spell
    if cSpell then
        if cSpell.IsSpellLearned and cSpell.IsSpellLearned(targetSpellID) then return true end
        if cSpell.IsSpellKnown and cSpell.IsSpellKnown(targetSpellID) then return true end
        if cSpell.IsSpellKnownOrOverridesKnown and cSpell.IsSpellKnownOrOverridesKnown(targetSpellID) then return true end
    end

    if _G.IsPlayerSpell and _G.IsPlayerSpell(targetSpellID) then return true end

    -- Never call legacy IsSpellKnown / IsSpellKnownOrOverridesKnown if C_SpellBook is present,
    -- because in 11.0+ Blizzard maps them to C_SpellBook.IsSpellInSpellBook which returns true for unlearned future spells.
    if not cBook then
        local isKnownOrOverrides = _G.IsSpellKnownOrOverridesKnown
        if isKnownOrOverrides and isKnownOrOverrides(targetSpellID) then return true end
        if _G.IsSpellKnown and _G.IsSpellKnown(targetSpellID) then return true end
    end

    return false
end
sfui.buffs.data.IsSpellActuallyKnown = IsSpellActuallyKnown

-- Helper to check if player knows any of the provided spell IDs
local function IsAnySpellKnown(spellIDs)
    if not spellIDs then return false end
    for i = 1, #spellIDs do
        local id = spellIDs[i]
        if IsSpellActuallyKnown(id) then
            return true, id
        end
    end
    return false, nil
end
sfui.buffs.data.IsAnySpellKnown = IsAnySpellKnown

--- Checks whether the current character is a Protection Paladin (spec ID 14862 from resolver)
local function IsProtectionPaladin()
    local talents = sfui.talents
    if talents then
        local specID = (talents.get_current_spec_id and talents.get_current_spec_id())
            or (talents._specResolver and talents._specResolver())
        return specID == 14862
    end
    return false
end
sfui.buffs.data.IsProtectionPaladin = IsProtectionPaladin

local GetInventoryItemLink = _G.GetInventoryItemLink
local select = _G.select

local function GetItemEquipLoc(itemLink)
    if not itemLink then return nil end
    local common = sfui.common
    if common and common.get_item_equip_loc then
        local loc = common.get_item_equip_loc(itemLink)
        if loc and loc ~= "" then return loc end
    end
    if common and common.get_item_instant_info then
        local loc = select(4, common.get_item_instant_info(itemLink))
        if loc and loc ~= "" then return loc end
    end
    if common and common.get_item_info then
        local loc = select(9, common.get_item_info(itemLink))
        if loc and loc ~= "" then return loc end
    end
    local cItem = _G.C_Item
    local getInstant = (cItem and cItem.GetItemInfoInstant) or _G.GetItemInfoInstant
    if getInstant then
        local loc = select(4, getInstant(itemLink))
        if loc and loc ~= "" then return loc end
    end
    local getInfo = (cItem and cItem.GetItemInfo) or _G.GetItemInfo
    if getInfo then
        local loc = select(9, getInfo(itemLink))
        if loc and loc ~= "" then return loc end
    end
    return nil
end
sfui.buffs.data.GetItemEquipLoc = GetItemEquipLoc

local SHAMAN_IMBUE_DATA = {
    rockbiter = {
        key = "rockbiter",
        name = "Rockbiter Weapon",
        displayName = "rockbiter",
        ids = { 8017, 8018, 8019, 10399, 16314, 16315, 16316, 25479, 25485 },
        icon = "Interface\\Icons\\Spell_Nature_RockBiter",
    },
    flametongue = {
        key = "flametongue",
        name = "Flametongue Weapon",
        displayName = "flametongue",
        ids = { 8024, 8027, 8030, 16339, 16341, 16342, 25489, 58785, 58789, 58790, 318038 },
        icon = "Interface\\Icons\\Spell_Fire_FlameTounge",
    },
    frostbrand = {
        key = "frostbrand",
        name = "Frostbrand Weapon",
        displayName = "frostbrand",
        ids = { 8033, 8038, 10459, 16355, 16356, 25500, 58794, 58795, 58796, 196834 },
        icon = "Interface\\Icons\\Spell_Frost_FrostBrand",
    },
    windfury = {
        key = "windfury",
        name = "Windfury Weapon",
        displayName = "windfury",
        ids = { 8232, 8235, 10486, 16362, 25505, 58801, 58803, 58804, 33757 },
        icon = "Interface\\Icons\\Spell_Nature_Windfury",
    },
    earthliving = {
        key = "earthliving",
        name = "Earthliving Weapon",
        displayName = "earthliving",
        ids = { 51730, 51988, 51991, 51992, 51993, 51994, 382021 },
        icon = "Interface\\Icons\\Spell_Shaman_EarthlivingWeapon",
    },
}
sfui.buffs.data.SHAMAN_IMBUE_DATA = SHAMAN_IMBUE_DATA
sfui.buffs.data.SHAMAN_IMBUE_KEYS = { "auto", "rockbiter", "flametongue", "frostbrand", "windfury", "earthliving" }

local function GetHighestKnownRank(spellInfoTable)
    if not spellInfoTable or not spellInfoTable.ids then return nil end
    local ids = spellInfoTable.ids
    for i = #ids, 1, -1 do
        local id = ids[i]
        if IsSpellActuallyKnown(id) then
            local name = GetSpellInfo and GetSpellInfo(id)
            if not name or name == "" then
                name = spellInfoTable.name
            end
            local icon = ResolveTexture(id, spellInfoTable.icon)
            return name, icon, id
        end
    end
    return nil
end
sfui.buffs.data.GetHighestKnownRank = GetHighestKnownRank

function sfui.buffs.data.GetBestShamanImbue(slot, activeEnchantName)
    local cfg = SfuiDB and SfuiDB.buffReminders
    local pref = (slot == 17) and (cfg and cfg.shamanImbueOH) or (cfg and cfg.shamanImbueMH)

    -- 1. Explicit user preference
    if pref and pref ~= "auto" and SHAMAN_IMBUE_DATA[pref] then
        local name, icon, id = GetHighestKnownRank(SHAMAN_IMBUE_DATA[pref])
        if name then return name, icon, id end
    end

    -- 2. If an enchant is currently active/expiring on the weapon, match it!
    if not activeEnchantName and sfui.buffs.scan and sfui.buffs.scan.GetActiveWeaponEnchantName then
        activeEnchantName = sfui.buffs.scan.GetActiveWeaponEnchantName(slot or 16)
    end

    if activeEnchantName then
        local lowerActive = activeEnchantName:lower()
        for key, info in pairs(SHAMAN_IMBUE_DATA) do
            if lowerActive:find(key, 1, true) then
                local name, icon, id = GetHighestKnownRank(info)
                if name then
                    return name, icon, id
                else
                    return info.name, info.icon, info.ids[1]
                end
            end
        end
    end

    -- 3. Automatic detection:
    -- If 2-Handed weapon equipped in MH: prefer Windfury > Rockbiter
    local itemLink = GetInventoryItemLink and GetInventoryItemLink("player", slot or 16)
    local equipLoc = itemLink and GetItemEquipLoc(itemLink)
    if equipLoc == "INVTYPE_2HWEAPON" then
        local wfName, wfIcon, wfId = GetHighestKnownRank(SHAMAN_IMBUE_DATA.windfury)
        if wfName then return wfName, wfIcon, wfId end
        local rbName, rbIcon, rbId = GetHighestKnownRank(SHAMAN_IMBUE_DATA.rockbiter)
        if rbName then return rbName, rbIcon, rbId end
    end

    -- 4. General priority: Windfury > Flametongue > Rockbiter > Frostbrand > Earthliving
    -- Low-level characters who only know Rockbiter will cleanly resolve Rockbiter!
    local order = { "windfury", "flametongue", "rockbiter", "frostbrand", "earthliving" }
    for i = 1, #order do
        local key = order[i]
        local name, icon, id = GetHighestKnownRank(SHAMAN_IMBUE_DATA[key])
        if name then return name, icon, id end
    end

    return "Rockbiter Weapon", "Interface\\Icons\\Spell_Nature_RockBiter", 8017
end

-- ─────────────────────────────────────────────────────────────
--  PET REMINDER MANAGEMENT (HUNTER & WARLOCK)
-- ─────────────────────────────────────────────────────────────
sfui.buffs.pets = sfui.buffs.pets or {}

local HUNTER_PET_SPELLS = {
    { id = 883, fallbackName = "Call Pet 1", fallbackIcon = "Interface\\Icons\\Ability_Hunter_Pet_Cat", index = 1, minLevel = 10 },
    { id = 83242, fallbackName = "Call Pet 2", fallbackIcon = "Interface\\Icons\\Ability_Hunter_Pet_Cat", index = 2, minLevel = 18 },
    { id = 83243, fallbackName = "Call Pet 3", fallbackIcon = "Interface\\Icons\\Ability_Hunter_Pet_Cat", index = 3, minLevel = 42 },
    { id = 83244, fallbackName = "Call Pet 4", fallbackIcon = "Interface\\Icons\\Ability_Hunter_Pet_Cat", index = 4, minLevel = 62 },
    { id = 83245, fallbackName = "Call Pet 5", fallbackIcon = "Interface\\Icons\\Ability_Hunter_Pet_Cat", index = 5, minLevel = 82 },
}

local WARLOCK_PET_SPELLS = {
    { id = 688, fallbackName = "Summon Imp", cleanName = "imp", fallbackIcon = "Interface\\Icons\\Spell_Shadow_SummonImp", minLevel = 1 },
    { id = 697, fallbackName = "Summon Voidwalker", cleanName = "voidwalker", fallbackIcon = "Interface\\Icons\\Spell_Shadow_SummonVoidWalker", minLevel = 8 },
    { id = 712, fallbackName = "Summon Succubus", cleanName = "succubus", fallbackIcon = "Interface\\Icons\\Spell_Shadow_SummonSuccubus", minLevel = 20 },
    { id = 691, fallbackName = "Summon Felhunter", cleanName = "felhunter", fallbackIcon = "Interface\\Icons\\Spell_Shadow_SummonFelHunter", minLevel = 30 },
    { id = 30146, fallbackName = "Summon Felguard", cleanName = "felguard", fallbackIcon = "Interface\\Icons\\Spell_Shadow_SummonFelGuard", minLevel = 10, demonologyOnly = true },
}

local function IsDemonologyWarlock()
    if playerClass ~= "WARLOCK" then return false end
    local talents = sfui.talents
    if talents then
        local specID = (talents.get_current_spec_id and talents.get_current_spec_id())
            or (talents._specResolver and talents._specResolver())
        if specID == 266 or specID == 14902 then
            return true
        end
        local specIdx = talents.get_current_spec_index and talents.get_current_spec_index()
        if specIdx == 2 then
            return true
        end
    end
    if _G.GetSpecialization then
        local specIdx = _G.GetSpecialization()
        if specIdx == 2 then
            return true
        end
    end
    return false
end

local function GetHunterPetInfo(spellDef)
    local id = spellDef.id
    local name = GetSpellInfo and GetSpellInfo(id)
    if not name or name == "" then
        name = spellDef.fallbackName
    end
    local icon = ResolveTexture(id, spellDef.fallbackIcon)
    local petName = nil
    if _G.GetCallPetSpellInfo then
        local _, pName = _G.GetCallPetSpellInfo(id)
        if (not pName or pName == "") and spellDef.index then
            local _, pName2 = _G.GetCallPetSpellInfo(spellDef.index)
            if pName2 and pName2 ~= "" then
                pName = pName2
            end
        end
        if pName and pName ~= "" then
            petName = pName
        end
    end
    local displayName = name:lower()
    if petName then
        displayName = string.format("%s (%s)", petName:lower(), name:lower())
    end
    return {
        id = id,
        spellName = name,
        displayName = displayName,
        petName = petName,
        icon = icon,
    }
end

local function GetWarlockPetInfo(spellDef)
    local id = spellDef.id
    local name = GetSpellInfo and GetSpellInfo(id)
    if not name or name == "" then
        name = spellDef.fallbackName
    end
    local icon = ResolveTexture(id, spellDef.fallbackIcon)
    local clean = spellDef.cleanName
    if not clean or clean == "" then
        clean = name:gsub("^[Ss][Uu][Mm][Mm][Oo][Nn]%s+", "")
    end
    clean = clean:lower()
    return {
        id = id,
        spellName = name,
        cleanName = clean,
        displayName = clean,
        icon = icon,
    }
end

local petsDirty = true
local cachedAvailablePets = {}
local cachedSelectedPet = nil

function sfui.buffs.pets.InvalidatePetCache()
    petsDirty = true
    cachedSelectedPet = nil
end

function sfui.buffs.pets.GetAvailablePets()
    if not petsDirty and #cachedAvailablePets > 0 then
        return cachedAvailablePets
    end

    _G.wipe(cachedAvailablePets)
    local playerLevel = (_G.UnitLevel and _G.UnitLevel("player")) or 1
    if playerClass == "HUNTER" then
        for i = 1, #HUNTER_PET_SPELLS do
            local spellDef = HUNTER_PET_SPELLS[i]
            local minLvl = spellDef.minLevel or 0
            if playerLevel >= minLvl and IsSpellActuallyKnown(spellDef.id) then
                cachedAvailablePets[#cachedAvailablePets + 1] = GetHunterPetInfo(spellDef)
            end
        end
    elseif playerClass == "WARLOCK" then
        local isDemonology = IsDemonologyWarlock()
        for i = 1, #WARLOCK_PET_SPELLS do
            local spellDef = WARLOCK_PET_SPELLS[i]
            local allow = true
            if spellDef.demonologyOnly and not isDemonology then
                allow = false
            end
            local minLvl = spellDef.minLevel or 0
            if allow and playerLevel >= minLvl and IsSpellActuallyKnown(spellDef.id) then
                cachedAvailablePets[#cachedAvailablePets + 1] = GetWarlockPetInfo(spellDef)
            end
        end
    end
    petsDirty = false
    return cachedAvailablePets
end

function sfui.buffs.pets.GetSelectedPet()
    local all = sfui.buffs.pets.GetAvailablePets()
    if not all or #all == 0 then
        cachedSelectedPet = nil
        return nil, all
    end

    if cachedSelectedPet and not petsDirty then
        return cachedSelectedPet, all
    end

    local db = SfuiDB and SfuiDB.buffReminders
    local savedID = nil
    if db and db.selectedPet then
        if type(db.selectedPet) == "table" then
            savedID = db.selectedPet[playerClass]
        elseif type(db.selectedPet) == "number" or type(db.selectedPet) == "string" then
            savedID = db.selectedPet
        end
    end

    if savedID then
        for i = 1, #all do
            if all[i].id == savedID or all[i].spellName == savedID then
                cachedSelectedPet = all[i]
                return cachedSelectedPet, all
            end
        end
    end

    cachedSelectedPet = all[1]
    return cachedSelectedPet, all
end

function sfui.buffs.pets.CyclePet(delta)
    local cur, all = sfui.buffs.pets.GetSelectedPet()
    if not all or #all <= 1 then
        return cur
    end

    local curIndex = 1
    if cur then
        for i = 1, #all do
            if all[i].id == cur.id then
                curIndex = i
                break
            end
        end
    end

    local nextIndex = curIndex + (delta > 0 and 1 or -1)
    if nextIndex > #all then
        nextIndex = 1
    elseif nextIndex < 1 then
        nextIndex = #all
    end

    local chosen = all[nextIndex]
    if chosen then
        cachedSelectedPet = chosen
        SfuiDB = SfuiDB or {}
        SfuiDB.buffReminders = SfuiDB.buffReminders or {}
        if type(SfuiDB.buffReminders.selectedPet) ~= "table" then
            SfuiDB.buffReminders.selectedPet = {}
        end
        SfuiDB.buffReminders.selectedPet[playerClass] = chosen.id

        if sfui.buffs and sfui.buffs.UpdateDisplay then
            sfui.buffs.UpdateDisplay()
        end
        return chosen
    end
    return cur
end

--- Determines the best spell name to cast for click-to-cast
--- @param entry table
--- @param activeEnchantName string|nil
--- @return string|nil, string|nil, number|nil
local function GetBestCastSpell(entry, activeEnchantName)
    if not entry then return nil end
    if entry.castSpell then
        if type(entry.castSpell) == "function" then
            return entry.castSpell(entry, activeEnchantName)
        elseif type(entry.castSpell) == "string" then
            return entry.castSpell, entry.fallbackIcon, nil
        end
    end

    if playerClass == "SHAMAN" and (entry.key == "weapon_mh" or entry.key == "weapon_oh") then
        local spellName, spellIcon, spellID = sfui.buffs.data.GetBestShamanImbue(entry.slot or 16, activeEnchantName)
        if spellName then
            return spellName, spellIcon, spellID
        end
    end

    if entry.type == "pet" and (playerClass == "HUNTER" or playerClass == "WARLOCK") then
        if sfui.buffs.pets and sfui.buffs.pets.GetSelectedPet then
            local selectedPet = sfui.buffs.pets.GetSelectedPet()
            if selectedPet then
                return selectedPet.spellName, selectedPet.icon, selectedPet.id
            end
        end
    end

    if entry.spellIDs then
        -- Search in reverse to find highest known rank
        for i = #entry.spellIDs, 1, -1 do
            local id = entry.spellIDs[i]
            if IsSpellActuallyKnown(id) then
                local name = GetSpellInfo and GetSpellInfo(id)
                if name and name ~= "" then
                    local icon = ResolveTexture(id, entry.fallbackIcon)
                    return name, icon, id
                end
            end
        end
    end

    if entry.names and #entry.names > 0 then
        return entry.names[1], entry.fallbackIcon, nil
    end

    return nil
end
sfui.buffs.data.GetBestCastSpell = GetBestCastSpell

-- ─────────────────────────────────────────────────────────────
--  CLASS REMINDER DEFINITIONS (CAMELOT / CLASSIC FOREVER)
-- ─────────────────────────────────────────────────────────────
-- Entry fields:
--   key: unique string identifier
--   name: display label for tooltips
--   type: "aura" | "stance" | "weapon_enchant" | "pet"
--   spellIDs: array of rank spell IDs to check
--   names: array of localized spell names to match active buffs
--   threshold: seconds remaining before warning (e.g. 300 for 5 min)
--   slot: 16 (MH) or 17 (OH) for weapon enchants
--   fallbackIcon: texture path if spell info lookup fails
--   isKnownCheck: custom function(entry) returning bool (optional)

local CLASS_BUFFS = {
    WARRIOR = {
        {
            key = "stance",
            name = "stance",
            type = "stance",
            spellIDs = { 2457, 71, 2458 }, -- Battle, Defensive, Berserker
            fallbackIcon = "Interface\\Icons\\Ability_Warrior_OffensiveStance",
        },
    },

    PALADIN = {
        {
            key = "aura",
            name = "paladin aura",
            type = "aura_group",
            -- Devotion, Retribution, Concentration, Shadow, Frost, Fire, Sanctity, Crusader
            spellIDs = {
                465, 10290, 643, 10291, 10292, 10293, 27149, -- Devotion
                7294, 10298, 10299, 10300, 10301, 27150,     -- Retribution
                19746,                                         -- Concentration
                19876, 19895, 19896, 27151,                   -- Shadow Res
                19888, 19897, 19898, 27152,                   -- Frost Res
                19891, 19899, 19900, 27153,                   -- Fire Res
                20218,                                         -- Sanctity
                32223,                                         -- Crusader
            },
            names = {
                "Devotion Aura", "Retribution Aura", "Concentration Aura",
                "Shadow Resistance Aura", "Frost Resistance Aura", "Fire Resistance Aura",
                "Sanctity Aura", "Crusader Aura"
            },
            fallbackIcon = "Interface\\Icons\\Spell_Holy_DevotionAura",
        },
        {
            key = "blessing",
            name = "blessing",
            type = "aura_group",
            -- Might, Wisdom, Kings, Sanctuary, Light, Salvation
            spellIDs = {
                19740, 19834, 19835, 19836, 19837, 19838, 25291, 27140, 25782, 25916, -- Might
                19742, 19850, 19852, 19853, 19854, 25290, 27142, 25894, 25918, 27143, -- Wisdom
                20217, 25898,                                                           -- Kings
                20911, 20912, 20913, 20914, 27168, 25899, 27169,                       -- Sanctuary
                19977, 19978, 19979, 27144, 25890, 27145,                               -- Light
                1038, 25895,                                                            -- Salvation
            },
            names = {
                "Blessing of Might", "Greater Blessing of Might",
                "Blessing of Wisdom", "Greater Blessing of Wisdom",
                "Blessing of Kings", "Greater Blessing of Kings",
                "Blessing of Sanctuary", "Greater Blessing of Sanctuary",
                "Blessing of Light", "Greater Blessing of Light",
                "Blessing of Salvation", "Greater Blessing of Salvation",
            },
            threshold = 300,
            fallbackIcon = "Interface\\Icons\\Spell_Holy_FistOfJustice",
        },
        {
            key = "righteous_fury",
            name = "righteous fury",
            type = "aura",
            spellIDs = { 25780 },
            names = { "Righteous Fury" },
            threshold = 300,
            fallbackIcon = "Interface\\Icons\\Spell_Holy_SealOfFury",
            isKnownCheck = function(entry)
                if not IsAnySpellKnown(entry.spellIDs) then
                    return false
                end
                return IsProtectionPaladin()
            end,
        },
    },

    HUNTER = {
        {
            key = "aspect",
            name = "aspect",
            type = "aura_group",
            spellIDs = {
                13165, 14318, 14319, 14320, 14321, 14322, 25296, 27044, -- Hawk
                13163,                                                   -- Monkey
                13159,                                                   -- Pack
                5118,                                                    -- Cheetah
                13161,                                                   -- Beast
                20043, 20190, 27045,                                     -- Wild
                34074,                                                   -- Viper
            },
            names = {
                "Aspect of the Hawk", "Aspect of the Monkey", "Aspect of the Pack",
                "Aspect of the Cheetah", "Aspect of the Beast", "Aspect of the Wild", "Aspect of the Viper"
            },
            fallbackIcon = "Interface\\Icons\\Spell_Nature_RavenForm",
        },
        {
            key = "pet",
            name = "pet missing",
            type = "pet",
            spellIDs = { 883, 83242, 83243, 83244, 83245 }, -- Call Pet 1-5
            fallbackIcon = "Interface\\Icons\\Ability_Hunter_Pet_Cat",
            isKnownCheck = function(entry)
                return sfui.buffs.pets and sfui.buffs.pets.GetAvailablePets and #sfui.buffs.pets.GetAvailablePets() > 0
            end,
        },
        {
            key = "trueshot_aura",
            name = "trueshot aura",
            type = "aura",
            spellIDs = { 19506, 20905, 20906, 27066 },
            names = { "Trueshot Aura" },
            fallbackIcon = "Interface\\Icons\\Ability_TrueShot",
        },
    },

    ROGUE = {
        {
            key = "poison_mh",
            name = "main hand poison",
            type = "weapon_enchant",
            slot = 16,
            threshold = 300,
            spellIDs = { 2842 }, -- Poisons skill
            fallbackIcon = "Interface\\Icons\\Trade_BrewPoison",
        },
        {
            key = "poison_oh",
            name = "off hand poison",
            type = "weapon_enchant",
            slot = 17,
            threshold = 300,
            spellIDs = { 2842 }, -- Poisons skill
            fallbackIcon = "Interface\\Icons\\Trade_BrewPoison",
        },
    },

    PRIEST = {
        {
            key = "inner_fire",
            name = "inner fire",
            type = "aura",
            spellIDs = { 588, 7128, 602, 1006, 10951, 10952, 25431 },
            names = { "Inner Fire" },
            threshold = 300,
            fallbackIcon = "Interface\\Icons\\Spell_Holy_InnerFire",
        },
        {
            key = "fortitude",
            name = "power word: fortitude",
            type = "aura",
            spellIDs = { 1243, 1244, 1245, 2791, 10937, 10938, 25389, 21562, 21564 },
            names = { "Power Word: Fortitude", "Prayer of Fortitude" },
            threshold = 300,
            fallbackIcon = "Interface\\Icons\\Spell_Holy_WordFortitude",
        },
        {
            key = "shadowform",
            name = "shadowform",
            type = "aura",
            spellIDs = { 15473 },
            names = { "Shadowform" },
            fallbackIcon = "Interface\\Icons\\Spell_Shadow_Shadowform",
        },
        {
            key = "divine_spirit",
            name = "divine spirit",
            type = "aura",
            spellIDs = { 14752, 14818, 14819, 27841, 32999, 27681, 32998 },
            names = { "Divine Spirit", "Prayer of Spirit" },
            threshold = 300,
            fallbackIcon = "Interface\\Icons\\Spell_Holy_DivineSpirit",
        },
        {
            key = "shadow_protection",
            name = "shadow protection",
            type = "aura",
            spellIDs = { 976, 10957, 10958, 25433, 27683, 39374 },
            names = { "Shadow Protection", "Prayer of Shadow Protection" },
            threshold = 300,
            fallbackIcon = "Interface\\Icons\\Spell_Shadow_AntiShadow",
            isDefaultDisabled = true,
        },
    },

    SHAMAN = {
        {
            key = "shield",
            name = "shaman shield",
            type = "aura_group",
            spellIDs = {
                324, 325, 905, 945, 8134, 10431, 10432, 25469, 25472, -- Lightning Shield
                24398, 33736, 33737,                                   -- Water Shield
                974, 32593, 32594,                                     -- Earth Shield
            },
            names = { "Lightning Shield", "Water Shield", "Earth Shield" },
            threshold = 60,
            fallbackIcon = "Interface\\Icons\\Spell_Nature_LightningShield",
        },
        {
            key = "weapon_mh",
            name = "main hand weapon imbue",
            type = "weapon_enchant",
            slot = 16,
            threshold = 300,
            spellIDs = {
                -- Rockbiter Weapon (Ranks 1 - 9)
                8017, 8018, 8019, 10399, 16314, 16315, 16316, 25479, 25485,
                -- Flametongue Weapon (Ranks 1 - 10 + Retail)
                8024, 8027, 8030, 16339, 16341, 16342, 25489, 58785, 58789, 58790, 318038,
                -- Frostbrand Weapon (Ranks 1 - 9 + Retail)
                8033, 8038, 10459, 16355, 16356, 25500, 58794, 58795, 58796, 196834,
                -- Windfury Weapon (Ranks 1 - 8 + Retail)
                8232, 8235, 10486, 16362, 25505, 58801, 58803, 58804, 33757,
                -- Earthliving Weapon (Ranks 1 - 6 + Retail)
                51730, 51988, 51991, 51992, 51993, 51994, 382021,
            },
            names = {
                "Rockbiter Weapon", "Flametongue Weapon", "Frostbrand Weapon", "Windfury Weapon", "Earthliving Weapon"
            },
            fallbackIcon = "Interface\\Icons\\Spell_Nature_RockBiter",
            isKnownCheck = function(entry)
                if playerClass == "SHAMAN" and (sfui.isCamelot or sfui.isClassic) then
                    return true
                end
                return IsAnySpellKnown(entry.spellIDs)
            end,
        },
        {
            key = "weapon_oh",
            name = "off hand weapon imbue",
            type = "weapon_enchant",
            slot = 17,
            threshold = 300,
            spellIDs = {
                -- Rockbiter Weapon (Ranks 1 - 9)
                8017, 8018, 8019, 10399, 16314, 16315, 16316, 25479, 25485,
                -- Flametongue Weapon (Ranks 1 - 10 + Retail)
                8024, 8027, 8030, 16339, 16341, 16342, 25489, 58785, 58789, 58790, 318038,
                -- Frostbrand Weapon (Ranks 1 - 9 + Retail)
                8033, 8038, 10459, 16355, 16356, 25500, 58794, 58795, 58796, 196834,
                -- Windfury Weapon (Ranks 1 - 8 + Retail)
                8232, 8235, 10486, 16362, 25505, 58801, 58803, 58804, 33757,
                -- Earthliving Weapon (Ranks 1 - 6 + Retail)
                51730, 51988, 51991, 51992, 51993, 51994, 382021,
            },
            names = {
                "Rockbiter Weapon", "Flametongue Weapon", "Frostbrand Weapon", "Windfury Weapon", "Earthliving Weapon"
            },
            fallbackIcon = "Interface\\Icons\\Spell_Nature_RockBiter",
            isKnownCheck = function(entry)
                if sfui.isCamelot or sfui.isClassic then
                    return false
                end
                return IsAnySpellKnown(entry.spellIDs)
            end,
        },
    },

    MAGE = {
        {
            key = "armor",
            name = "mage armor",
            type = "aura_group",
            spellIDs = {
                168, 7300, 7301, 7320, 10219, 10220, -- Frost/Ice Armor
                6117, 22782, 22783, 27125,           -- Mage Armor
                30482,                               -- Molten Armor
            },
            names = { "Frost Armor", "Ice Armor", "Mage Armor", "Molten Armor" },
            threshold = 300,
            fallbackIcon = "Interface\\Icons\\Spell_Frost_FrostArmor02",
        },
        {
            key = "intellect",
            name = "arcane intellect",
            type = "aura",
            spellIDs = { 1459, 1460, 1461, 10156, 10157, 27126, 23028, 27127 },
            names = { "Arcane Intellect", "Arcane Brilliance" },
            threshold = 300,
            fallbackIcon = "Interface\\Icons\\Spell_Holy_MagicalSentry",
        },
    },

    WARLOCK = {
        {
            key = "armor",
            name = "warlock armor",
            type = "aura_group",
            spellIDs = {
                687, 696, 706, 1086, 11733, 11734, 11735, 27260, -- Demon Skin / Demon Armor
                28176, 28189,                                      -- Fel Armor
            },
            names = { "Demon Skin", "Demon Armor", "Fel Armor" },
            threshold = 300,
            fallbackIcon = "Interface\\Icons\\Spell_Shadow_RagingScream",
        },
        {
            key = "pet",
            name = "pet missing",
            type = "pet",
            spellIDs = { 688, 697, 712, 691, 30146 }, -- Summon Imp, Voidwalker, Succubus, Felhunter, Felguard
            fallbackIcon = "Interface\\Icons\\Spell_Shadow_SummonImp",
            isKnownCheck = function(entry)
                return sfui.buffs.pets and sfui.buffs.pets.GetAvailablePets and #sfui.buffs.pets.GetAvailablePets() > 0
            end,
        },
        {
            key = "soul_link",
            name = "soul link",
            type = "aura",
            spellIDs = { 19028 },
            names = { "Soul Link" },
            fallbackIcon = "Interface\\Icons\\Spell_Shadow_SoulLeech_3",
        },
    },

    DRUID = {
        {
            key = "mark_of_the_wild",
            name = "mark of the wild",
            type = "aura",
            spellIDs = { 1126, 5232, 6756, 5234, 8907, 9884, 9885, 26990, 21849, 21850 },
            names = { "Mark of the Wild", "Gift of the Wild" },
            threshold = 300,
            fallbackIcon = "Interface\\Icons\\Spell_Nature_Regeneration",
        },
        {
            key = "thorns",
            name = "thorns",
            type = "aura",
            spellIDs = { 467, 782, 1075, 8914, 9756, 9910, 26992 },
            names = { "Thorns" },
            threshold = 300,
            fallbackIcon = "Interface\\Icons\\Spell_Nature_Thorns",
        },
        {
            key = "omen_of_clarity",
            name = "omen of clarity",
            type = "aura",
            spellIDs = { 16864 },
            names = { "Omen of Clarity" },
            threshold = 60,
            fallbackIcon = "Interface\\Icons\\Spell_Nature_CrystalBall",
        },
    },
}

sfui.buffs.data.CLASS_BUFFS = CLASS_BUFFS

local function IsTrackingLearned(spellID, spellName)
    if IsSpellActuallyKnown(spellID) then
        return true
    end
    local targetLower = spellName and string.lower(spellName)
    local cMinimap = _G.C_Minimap
    if cMinimap and cMinimap.GetNumTrackingTypes and cMinimap.GetTrackingInfo then
        local count = cMinimap.GetNumTrackingTypes() or 0
        for i = 1, count do
            local info = cMinimap.GetTrackingInfo(i)
            if info then
                if spellID and info.spellID and info.spellID == spellID then
                    return true
                end
                if targetLower and info.name and string.lower(info.name) == targetLower then
                    return true
                end
            end
        end
    elseif _G.GetNumTrackingTypes and _G.GetTrackingInfo then
        local count = _G.GetNumTrackingTypes() or 0
        for i = 1, count do
            local tName = _G.GetTrackingInfo(i)
            if targetLower and tName and string.lower(tName) == targetLower then
                return true
            end
        end
    end
    return false
end
sfui.buffs.data.IsTrackingLearned = IsTrackingLearned

local TRACKING_SPELLS = {
    minerals = {
        key = "tracking_minerals",
        name = "find minerals",
        displayName = "minerals",
        type = "tracking",
        spellIDs = { 2580 },
        names = { "Find Minerals" },
        fallbackIcon = "Interface\\Icons\\Spell_Nature_Earthquake",
        isTracking = true,
        isKnownCheck = function()
            return IsTrackingLearned(2580, "Find Minerals")
        end,
    },
    herbs = {
        key = "tracking_herbs",
        name = "find herbs",
        displayName = "herbs",
        type = "tracking",
        spellIDs = { 2383 },
        names = { "Find Herbs" },
        fallbackIcon = "Interface\\Icons\\Spell_Nature_NatureTouchGrow",
        isTracking = true,
        isKnownCheck = function()
            return IsTrackingLearned(2383, "Find Herbs")
        end,
    },
}
sfui.buffs.data.TRACKING_SPELLS = TRACKING_SPELLS

function sfui.buffs.data.GetActiveTrackingEntries()
    local cfg = SfuiDB and SfuiDB.buffReminders
    local entries = {}
    local trackMin = not cfg or (cfg.trackMinerals ~= false)
    local trackHerb = not cfg or (cfg.trackHerbs ~= false)

    if trackMin and IsTrackingLearned(2580, "Find Minerals") then
        entries[#entries + 1] = TRACKING_SPELLS.minerals
    end
    if trackHerb and IsTrackingLearned(2383, "Find Herbs") then
        entries[#entries + 1] = TRACKING_SPELLS.herbs
    end
    return entries
end

--- Returns the buff entries configured for the active player's class
--- @return table
function sfui.buffs.data.GetClassEntries()
    return CLASS_BUFFS[playerClass] or {}
end

--- Returns combined list of class buffs, enabled consumables, and tracking spells
--- @return table
function sfui.buffs.data.GetAllEntries()
    local result = {}
    local classList = CLASS_BUFFS[playerClass] or {}
    for i = 1, #classList do
        result[#result + 1] = classList[i]
    end

    if sfui.buffs.consumables and sfui.buffs.consumables.GetActiveConsumableEntries then
        local consumablesList = sfui.buffs.consumables.GetActiveConsumableEntries()
        for i = 1, #consumablesList do
            result[#result + 1] = consumablesList[i]
        end
    end

    local trackingList = sfui.buffs.data.GetActiveTrackingEntries()
    for i = 1, #trackingList do
        result[#result + 1] = trackingList[i]
    end

    return result
end

