local addonName, addon = ...
sfui = sfui or {}
sfui.spells_db = {}

-- ══════════════════════════════════════════════════════════════════════════════
-- SFUI Spell & Aura Database
--
-- Centralized definitions for:
--   1. Known class buff / aura regex patterns (Vanilla / Classic / Retail)
--   2. Bidirectional spell rank and aura ID mappings for O(1) combat lookups
--   3. Dynamic out-of-combat aura learning registry
-- ══════════════════════════════════════════════════════════════════════════════

-- ─── 1. Aura Pattern Matching ────────────────────────────────────────────────
sfui.spells_db.AURA_PATTERNS = {
    "^Blessing of ", "^Greater Blessing of ", "^Seal of ", " Aura$",
    "^Righteous Fury", "^Holy Shield",
    "^Power Word: Fortitude", "^Prayer of Fortitude", "^Shadow Protection", "^Prayer of Shadow Protection",
    "^Inner Fire", "^Divine Spirit", "^Prayer of Spirit", "^Touch of Weakness", "^Shadowform",
    "^Arcane Intellect", "^Arcane Brilliance", "^Mage Armor", "^Ice Armor", "^Frost Armor", "^Molten Armor",
    "^Dampen Magic", "^Amplify Magic", "^Mana Shield", "^Ice Barrier",
    "^Mark of the Wild", "^Gift of the Wild", "^Thorns", "^Omen of Clarity", "^Barkskin", "^Nature's Grasp",
    "^Demon Skin", "^Demon Armor", "^Fel Armor", "^Soul Link", "^Detect Lesser Invisibility", "^Detect Invisibility", "^Unending Breath",
    "^Lightning Shield", "^Water Shield", "^Earth Shield",
    "^Rockbiter Weapon", "^Windfury Weapon", "^Flametongue Weapon", "^Frostbrand Weapon",
    "^Battle Shout", "^Commanding Shout", "^Bloodrage", "^Berserker Rage",
    "^Blade Flurry", "^Adrenaline Rush", "^Slice and Dice",
    "^Aspect of the ", "^Trueshot Aura",
}

-- ─── 2. Class Rank & Aura SpellID Groups ─────────────────────────────────────
-- Maps spellbook cast IDs, player buff aura IDs, and all ranks together.
sfui.spells_db.RANK_GROUPS = {
    -- ── Paladin ──
    -- Seals
    { names = { "Seal of Righteousness" }, ids = { 20154, 21084, 20287, 20288, 20289, 20290, 20291, 20292, 20293, 27155 } },
    { names = { "Seal of the Crusader" },  ids = { 20162, 21082, 20305, 20306, 20307, 20308, 27158 } },
    { names = { "Seal of Command" },       ids = { 20375, 20915, 20918, 20919, 20920, 27170 } },
    { names = { "Seal of Light" },         ids = { 20165, 20332, 20333, 20334, 27160 } },
    { names = { "Seal of Wisdom" },        ids = { 20166, 20356, 20357, 27166 } },
    { names = { "Seal of Justice" },       ids = { 20164, 27167 } },

    -- Blessings (Standard + Greater)
    { names = { "Blessing of Might", "Greater Blessing of Might" }, ids = { 19740, 19834, 19835, 19836, 19837, 19838, 25291, 27140, 25782, 25916 } },
    { names = { "Blessing of Wisdom", "Greater Blessing of Wisdom" }, ids = { 19742, 19850, 19852, 19853, 19854, 25290, 27142, 25894, 25918, 27143 } },
    { names = { "Blessing of Kings", "Greater Blessing of Kings" }, ids = { 20217, 25898 } },
    { names = { "Blessing of Sanctuary", "Greater Blessing of Sanctuary" }, ids = { 20911, 20912, 20913, 20914, 27168, 25899, 27169 } },
    { names = { "Blessing of Light", "Greater Blessing of Light" }, ids = { 19977, 19978, 19979, 27144, 25890, 27145 } },
    { names = { "Blessing of Salvation", "Greater Blessing of Salvation" }, ids = { 1038, 25895 } },
    { names = { "Blessing of Freedom" },    ids = { 1044 } },
    { names = { "Blessing of Protection" }, ids = { 1022, 5599, 10278 } },
    { names = { "Blessing of Sacrifice" },  ids = { 6940, 20729 } },

    -- Paladin Auras & Self-Buffs
    { names = { "Devotion Aura" },          ids = { 465, 10290, 643, 10291, 10292, 10293, 27149 } },
    { names = { "Retribution Aura" },       ids = { 7294, 10298, 10299, 10300, 10301, 27150 } },
    { names = { "Concentration Aura" },     ids = { 19746 } },
    { names = { "Shadow Resistance Aura" }, ids = { 19876, 19895, 19896, 27151 } },
    { names = { "Frost Resistance Aura" },  ids = { 19888, 19897, 19898, 27152 } },
    { names = { "Fire Resistance Aura" },   ids = { 19891, 19899, 19900, 27153 } },
    { names = { "Sanctity Aura" },          ids = { 20218 } },
    { names = { "Righteous Fury" },         ids = { 25780 } },
    { names = { "Holy Shield" },            ids = { 20925, 20927, 20928, 27179 } },
    { names = { "Divine Protection" },      ids = { 498, 5573 } },
    { names = { "Divine Shield" },          ids = { 642, 1020 } },

    -- ── Priest ──
    { names = { "Power Word: Fortitude", "Prayer of Fortitude" }, ids = { 1243, 1244, 1245, 2791, 10937, 10938, 25389, 21562, 21564 } },
    { names = { "Divine Spirit", "Prayer of Spirit" },           ids = { 14752, 14818, 14819, 27841, 32999, 27681, 32998 } },
    { names = { "Shadow Protection", "Prayer of Shadow Protection" }, ids = { 976, 10957, 10958, 25433, 27683, 39374 } },
    { names = { "Inner Fire" },        ids = { 588, 7128, 602, 1006, 10951, 10952, 25431 } },
    { names = { "Shadowform" },        ids = { 15473 } },
    { names = { "Power Infusion" },    ids = { 10060 } },
    { names = { "Fear Ward" },         ids = { 6346 } },
    { names = { "Touch of Weakness" }, ids = { 2652, 19261, 19262, 19264, 19265, 25461 } },

    -- ── Mage ──
    { names = { "Arcane Intellect", "Arcane Brilliance" }, ids = { 1459, 1460, 1461, 10156, 10157, 27126, 23028, 27127 } },
    { names = { "Frost Armor", "Ice Armor" },              ids = { 168, 7300, 7301, 7320, 10219, 10220 } },
    { names = { "Mage Armor" },    ids = { 6117, 22782, 22783, 27125 } },
    { names = { "Molten Armor" },   ids = { 30482 } },
    { names = { "Ice Barrier" },    ids = { 11426, 13043, 13044, 27134, 33405 } },
    { names = { "Mana Shield" },    ids = { 1463, 8494, 8495, 10191, 10192, 10193, 27131 } },
    { names = { "Dampen Magic" },   ids = { 604, 8450, 8451, 10173, 10174 } },
    { names = { "Amplify Magic" },  ids = { 1008, 8455, 10169, 10170 } },

    -- ── Druid ──
    { names = { "Mark of the Wild", "Gift of the Wild" }, ids = { 1126, 5232, 6756, 5234, 8907, 9884, 9885, 26990, 21849, 21850 } },
    { names = { "Thorns" },         ids = { 467, 782, 1075, 8914, 9756, 9910, 26992 } },
    { names = { "Omen of Clarity" }, ids = { 16864 } },
    { names = { "Barkskin" },       ids = { 22812 } },
    { names = { "Nature's Grasp" }, ids = { 16689, 16810, 16811, 16812, 16813, 17329 } },
    { names = { "Tiger's Fury" },   ids = { 5217, 6793, 9845, 9846 } },

    -- ── Warrior ──
    { names = { "Battle Shout" },     ids = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 } },
    { names = { "Bloodrage" },        ids = { 2687 } },
    { names = { "Berserker Rage" },   ids = { 18499 } },
    { names = { "Shield Wall" },      ids = { 871 } },
    { names = { "Last Stand" },       ids = { 12975 } },
    { names = { "Retaliation" },      ids = { 20230 } },
    { names = { "Recklessness" },     ids = { 1719 } },
    { names = { "Death Wish" },       ids = { 12292 } },
    { names = { "Sweeping Strikes" }, ids = { 12328 } },

    -- ── Warlock ──
    { names = { "Demon Skin", "Demon Armor", "Fel Armor" }, ids = { 687, 696, 706, 1086, 11733, 11734, 11735, 27260, 28176, 28189 } },
    { names = { "Soul Link" },       ids = { 19028 } },
    { names = { "Unending Breath" }, ids = { 5697 } },
    { names = { "Shadow Ward" },     ids = { 6229, 11739, 11740, 28610 } },

    -- ── Shaman ──
    { names = { "Lightning Shield" }, ids = { 324, 325, 905, 945, 8134, 10431, 10432, 25469, 25472 } },
    { names = { "Water Shield" },     ids = { 24398, 33736, 33737 } },
    { names = { "Earth Shield" },     ids = { 974, 32593, 32594 } },
    { names = { "Rockbiter Weapon" }, ids = { 8017, 8018, 8019, 10399, 16314, 16315, 16316 } },
    { names = { "Flametongue Weapon" }, ids = { 8024, 8027, 8030, 16339, 16341, 16342 } },
    { names = { "Frostbrand Weapon" }, ids = { 8033, 8038, 10459, 16355, 16356 } },
    { names = { "Windfury Weapon" },  ids = { 8232, 8235, 10486, 16362 } },

    -- ── Rogue ──
    { names = { "Blade Flurry" },     ids = { 13877 } },
    { names = { "Adrenaline Rush" },  ids = { 13750 } },
    { names = { "Slice and Dice" },   ids = { 5171, 6774 } },
    { names = { "Evasion" },          ids = { 5277, 26669 } },
    { names = { "Sprint" },           ids = { 2983, 8696, 11305 } },

    -- ── Hunter ──
    { names = { "Aspect of the Monkey" }, ids = { 13163 } },
    { names = { "Aspect of the Hawk" },   ids = { 13165, 14318, 14319, 14320, 14321, 14322, 25296, 27044 } },
    { names = { "Aspect of the Cheetah" }, ids = { 5118 } },
    { names = { "Aspect of the Pack" },   ids = { 13159 } },
    { names = { "Aspect of the Beast" },  ids = { 13161 } },
    { names = { "Aspect of the Wild" },   ids = { 20043, 20190, 27045 } },
    { names = { "Trueshot Aura" },        ids = { 19506, 20905, 20906, 27066 } },
    { names = { "Rapid Fire" },           ids = { 3045 } },
}

-- ─── 3. Compiled Fast Lookups ────────────────────────────────────────────────
local _spellIDToGroup = {}
local _nameToGroup    = {}

local function RegisterGroup(names, ids)
    local group = {}
    for _, id in ipairs(ids) do
        table.insert(group, id)
    end
    for _, id in ipairs(group) do
        _spellIDToGroup[id] = group
    end
    if type(names) == "string" then
        names = { names }
    end
    if type(names) == "table" then
        for _, name in ipairs(names) do
            _nameToGroup[name] = group
            _nameToGroup[name:lower()] = group
        end
    end
end

for _, def in ipairs(sfui.spells_db.RANK_GROUPS) do
    RegisterGroup(def.names, def.ids)
end

-- ─── 4. Public API Helpers ───────────────────────────────────────────────────

--- Returns rank group array of spell IDs for a given spell ID, or nil.
--- @param spellID number
--- @return number[]|nil
function sfui.spells_db.GetRanksByID(spellID)
    if not spellID then return nil end
    return _spellIDToGroup[spellID]
end

--- Returns rank group array of spell IDs for a given spell name, or nil.
--- @param spellName string
--- @return number[]|nil
function sfui.spells_db.GetRanksByName(spellName)
    if not spellName or spellName == "" then return nil end
    return _nameToGroup[spellName] or _nameToGroup[spellName:lower()]
end

--- Fast query to test if a spell ID is part of a registered aura/rank group.
--- @param spellID number
--- @return boolean
function sfui.spells_db.IsKnownAuraSpellID(spellID)
    if not spellID then return false end
    return _spellIDToGroup[spellID] ~= nil
end

--- Checks whether a spell name matches any known aura naming pattern.
--- @param spellName string
--- @return boolean
function sfui.spells_db.MatchesAuraPattern(spellName)
    if not spellName or spellName == "" then return false end
    for _, pat in ipairs(sfui.spells_db.AURA_PATTERNS) do
        if spellName:find(pat) then
            return true
        end
    end
    return false
end

--- Dynamically registers an observed aura into the runtime database.
--- Ensures future combat queries can look up this spell without index scans.
--- @param targetID number|nil
--- @param auraSpellID number
--- @param name string|nil
function sfui.spells_db.LearnAuraMapping(targetID, auraSpellID, name)
    if not auraSpellID then return end
    local aName = name
    if aName then
        local group = _nameToGroup[aName] or _nameToGroup[aName:lower()]
        if not group then
            group = {}
            _nameToGroup[aName] = group
            _nameToGroup[aName:lower()] = group
        end
        local foundAura = false
        for _, id in ipairs(group) do
            if id == auraSpellID then foundAura = true; break end
        end
        if not foundAura then table.insert(group, auraSpellID) end
        _spellIDToGroup[auraSpellID] = group

        if targetID then
            local foundTarget = false
            for _, id in ipairs(group) do
                if id == targetID then foundTarget = true; break end
            end
            if not foundTarget then table.insert(group, targetID) end
            _spellIDToGroup[targetID] = group
        end
    elseif targetID then
        local group = _spellIDToGroup[targetID]
        if not group then
            group = { targetID }
            _spellIDToGroup[targetID] = group
        end
        local foundAura = false
        for _, id in ipairs(group) do
            if id == auraSpellID then foundAura = true; break end
        end
        if not foundAura then table.insert(group, auraSpellID) end
        _spellIDToGroup[auraSpellID] = group
    end
end
