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

-- Helper to check if player knows any of the provided spell IDs
local function IsAnySpellKnown(spellIDs)
    if not spellIDs then return false end
    for i = 1, #spellIDs do
        local id = spellIDs[i]
        if (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) then
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

--- Determines the best spell name to cast for click-to-cast
--- @param entry table
--- @return string|nil
local function GetBestCastSpell(entry)
    if not entry then return nil end
    if entry.castSpell then
        if type(entry.castSpell) == "function" then
            return entry.castSpell(entry)
        elseif type(entry.castSpell) == "string" then
            return entry.castSpell
        end
    end

    if entry.spellIDs then
        -- Search in reverse to find highest known rank
        for i = #entry.spellIDs, 1, -1 do
            local id = entry.spellIDs[i]
            if (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) then
                if GetSpellInfo then
                    local name = GetSpellInfo(id)
                    if name and name ~= "" then
                        return name
                    end
                end
            end
        end
    end

    if entry.names and #entry.names > 0 then
        return entry.names[1]
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
            spellIDs = { 883 }, -- Call Pet
            fallbackIcon = "Interface\\Icons\\Ability_Hunter_Pet_Cat",
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
            spellIDs = { 8017, 8024, 8033, 8232 }, -- Rockbiter, Flametongue, Frostbrand, Windfury
            fallbackIcon = "Interface\\Icons\\Spell_Nature_Cyclone",
        },
        {
            key = "weapon_oh",
            name = "off hand weapon imbue",
            type = "weapon_enchant",
            slot = 17,
            threshold = 300,
            spellIDs = { 8017, 8024, 8033, 8232 },
            fallbackIcon = "Interface\\Icons\\Spell_Nature_Cyclone",
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
            spellIDs = { 688, 697, 712, 691 }, -- Summon Imp, Voidwalker, Succubus, Felhunter
            fallbackIcon = "Interface\\Icons\\Spell_Shadow_SummonImp",
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

--- Returns the buff entries configured for the active player's class
--- @return table
function sfui.buffs.data.GetClassEntries()
    return CLASS_BUFFS[playerClass] or {}
end

--- Returns combined list of class buffs and enabled consumables
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

    return result
end

