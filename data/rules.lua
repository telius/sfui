local addonName, addon = ...
sfui = sfui or {}
sfui.highest = sfui.highest or {}

-- ══════════════════════════════════════════════════════════════════════════════
-- SFUI Spec Equipment & Scoring Rules Database
--
-- Defines weapon subclass proficiencies and gear scoring criteria for all
-- Retail and Classic Forever specializations.
--
-- Armor types: 1 = Cloth, 2 = Leather, 3 = Mail, 4 = Plate
-- Primary stats: 1 = Strength, 2 = Agility, 4 = Intellect
-- ══════════════════════════════════════════════════════════════════════════════

-- Weapon Subclasses (classID == 2, numeric subclassID)
-- 0: 1H Axe, 1: 2H Axe, 2: Bow, 3: Gun, 4: 1H Mace, 5: 2H Mace, 6: Polearm,
-- 7: 1H Sword, 8: 2H Sword, 9: Warglaive, 10: Staff, 13: Fist, 15: Dagger, 18: Crossbow, 19: Wand
local WEAPONS_DH               = { [0] = true, [7] = true, [9] = true, [13] = true } -- Havoc & Vengeance: 1H Axes, 1H Swords, Warglaives, Fist (CANNOT use Daggers [15] or 1H Maces [4]!)
local WEAPONS_DH_DEVOURER      = { [0] = true, [7] = true, [9] = true, [13] = true, [15] = true } -- Devourer: Warglaives, Swords, Axes, Fist Weapons, Daggers (Intellect)
local WEAPONS_DK               = { [0] = true, [1] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true }
local WEAPONS_DRUID            = { [4] = true, [5] = true, [6] = true, [10] = true, [13] = true, [15] = true }
local WEAPONS_EVOKER           = { [0] = true, [1] = true, [4] = true, [5] = true, [7] = true, [8] = true, [10] = true, [13] = true, [15] = true }
local WEAPONS_HUNTER_RANGED    = { [2] = true, [3] = true, [18] = true }
local WEAPONS_HUNTER_MELEE     = { [1] = true, [6] = true, [8] = true, [10] = true }
local WEAPONS_MAGE             = { [7] = true, [10] = true, [15] = true, [19] = true }
local WEAPONS_MONK             = { [0] = true, [4] = true, [6] = true, [7] = true, [10] = true, [13] = true }
local WEAPONS_PALADIN          = { [0] = true, [1] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true }
local WEAPONS_PRIEST           = { [4] = true, [10] = true, [15] = true, [19] = true }
local WEAPONS_ROGUE_ASSASSIN   = { [15] = true } -- Assassination requires Daggers in both hands
local WEAPONS_ROGUE_ALL        = { [0] = true, [4] = true, [7] = true, [13] = true, [15] = true }
local WEAPONS_SHAMAN_CASTER    = { [0] = true, [1] = true, [4] = true, [5] = true, [10] = true, [13] = true, [15] = true }
local WEAPONS_SHAMAN_ENH       = { [0] = true, [4] = true, [13] = true } -- Enhancement cannot use daggers for Stormstrike
local WEAPONS_WARLOCK          = { [7] = true, [10] = true, [15] = true, [19] = true }
local WEAPONS_WARRIOR          = { [0] = true, [1] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [10] = true, [13] = true, [15] = true }
local WEAPONS_WARRIOR_CLASSIC  = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [10] = true, [13] = true, [15] = true, [16] = true, [18] = true }
local WEAPONS_ROGUE_CLASSIC    = { [2] = true, [3] = true, [4] = true, [7] = true, [13] = true, [15] = true, [16] = true, [18] = true }
local WEAPONS_HUNTER_CLASSIC   = { [0] = true, [1] = true, [2] = true, [3] = true, [6] = true, [7] = true, [8] = true, [10] = true, [13] = true, [15] = true, [18] = true }

sfui.highest.rules = {
    -- Death Knight
    [250] = { armor = 4, stat = 1, weaps = { ["2H"] = true }, allowedWeapons = WEAPONS_DK },
    [251] = { armor = 4, stat = 1, weaps = { ["2H"] = true, ["1H_Dual"] = true }, allowedWeapons = WEAPONS_DK },
    [252] = { armor = 4, stat = 1, weaps = { ["2H"] = true }, allowedWeapons = WEAPONS_DK },
    -- Demon Hunter
    [577] = { armor = 2, stat = 2, weaps = { ["1H_Dual"] = true }, allowedWeapons = WEAPONS_DH },          -- Havoc (Agility; NO Daggers)
    [581] = { armor = 2, stat = 2, weaps = { ["1H_Dual"] = true }, allowedWeapons = WEAPONS_DH },          -- Vengeance (Agility; NO Daggers)
    [1480] = { armor = 2, stat = 4, weaps = { ["1H_Dual"] = true }, allowedWeapons = WEAPONS_DH_DEVOURER }, -- Devourer (Intellect; CAN use Daggers)
    -- Druid
    [102] = { armor = 2, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_DRUID },
    [103] = { armor = 2, stat = 2, weaps = { ["2H"] = true }, allowedWeapons = WEAPONS_DRUID },
    [104] = { armor = 2, stat = 2, weaps = { ["2H"] = true }, allowedWeapons = WEAPONS_DRUID },
    [105] = { armor = 2, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_DRUID },
    -- Evoker
    [1467] = { armor = 3, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_EVOKER },
    [1468] = { armor = 3, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_EVOKER },
    [1473] = { armor = 3, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_EVOKER },
    -- Hunter
    [253] = { armor = 3, stat = 2, weaps = { ["Ranged"] = true }, allowedWeapons = WEAPONS_HUNTER_RANGED },
    [254] = { armor = 3, stat = 2, weaps = { ["Ranged"] = true }, allowedWeapons = WEAPONS_HUNTER_RANGED },
    [255] = { armor = 3, stat = 2, weaps = { ["2H"] = true }, allowedWeapons = WEAPONS_HUNTER_MELEE },
    -- Mage
    [62] = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_MAGE },
    [63] = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_MAGE },
    [64] = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_MAGE },
    -- Monk
    [268] = { armor = 2, stat = 2, weaps = { ["2H"] = true, ["1H_Dual"] = true }, allowedWeapons = WEAPONS_MONK },
    [269] = { armor = 2, stat = 2, weaps = { ["2H"] = true, ["1H_Dual"] = true }, allowedWeapons = WEAPONS_MONK },
    [270] = { armor = 2, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_MONK },
    -- Paladin
    [65] = { armor = 4, stat = 4, weaps = { ["2H"] = true, ["1H_Shield"] = true }, allowedWeapons = WEAPONS_PALADIN },
    [66] = { armor = 4, stat = 1, weaps = { ["1H_Shield"] = true }, allowedWeapons = WEAPONS_PALADIN },
    [70] = { armor = 4, stat = 1, weaps = { ["2H"] = true }, allowedWeapons = WEAPONS_PALADIN },
    -- Priest
    [256] = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_PRIEST },
    [257] = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_PRIEST },
    [258] = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_PRIEST },
    -- Rogue
    [259] = { armor = 2, stat = 2, weaps = { ["1H_Dual"] = true }, allowedWeapons = WEAPONS_ROGUE_ASSASSIN },
    [260] = { armor = 2, stat = 2, weaps = { ["1H_Dual"] = true }, allowedWeapons = WEAPONS_ROGUE_ALL },
    [261] = { armor = 2, stat = 2, weaps = { ["1H_Dual"] = true }, allowedWeapons = WEAPONS_ROGUE_ALL },
    -- Shaman
    [262] = { armor = 3, stat = 4, weaps = { ["2H"] = true, ["1H_Shield"] = true }, allowedWeapons = WEAPONS_SHAMAN_CASTER },
    [263] = { armor = 3, stat = 2, weaps = { ["2H"] = true, ["1H_Dual"] = true }, allowedWeapons = WEAPONS_SHAMAN_ENH },
    [264] = { armor = 3, stat = 4, weaps = { ["2H"] = true, ["1H_Shield"] = true }, allowedWeapons = WEAPONS_SHAMAN_CASTER },
    -- Warlock
    [265] = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_WARLOCK },
    [266] = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_WARLOCK },
    [267] = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_WARLOCK },
    -- Warrior
    [71] = { armor = 4, stat = 1, weaps = { ["2H"] = true }, allowedWeapons = WEAPONS_WARRIOR },
    [72] = { armor = 4, stat = 1, weaps = { ["2H_Dual"] = true, ["1H_Dual"] = true }, allowedWeapons = WEAPONS_WARRIOR },
    [73] = { armor = 4, stat = 1, weaps = { ["1H_Shield"] = true }, allowedWeapons = WEAPONS_WARRIOR },
    -- Classic Forever / Camelot Specs (1482–1491)
    [1482] = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_MAGE }, -- Mage
    [1484] = { armor = 2, stat = 2, weaps = { ["2H"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_DRUID }, -- Druid
    [1485] = { armor = 3, stat = 2, weaps = { ["Ranged"] = true, ["2H"] = true, ["1H_Dual"] = true }, allowedWeapons = WEAPONS_HUNTER_CLASSIC }, -- Hunter
    [1486] = { armor = 4, stat = 1, weaps = { ["2H"] = true, ["1H_Shield"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_PALADIN }, -- Paladin
    [1487] = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_PRIEST }, -- Priest
    [1488] = { armor = 2, stat = 2, weaps = { ["1H_Dual"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_ROGUE_CLASSIC }, -- Rogue
    [1489] = { armor = 3, stat = 4, weaps = { ["2H"] = true, ["1H_Shield"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_SHAMAN_CASTER }, -- Shaman
    [1490] = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_WARLOCK }, -- Warlock
    [1491] = { armor = 4, stat = 1, weaps = { ["2H"] = true, ["1H_Dual"] = true, ["1H_Shield"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_WARRIOR_CLASSIC }, -- Warrior
}
