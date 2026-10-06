local addonName, addon        = ...
sfui                          = sfui or {}
sfui.highest                  = sfui.highest or {}

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
local WEAPONS_DH              = { [0] = true, [7] = true, [9] = true, [13] = true }               -- Havoc & Vengeance: 1H Axes, 1H Swords, Warglaives, Fist (CANNOT use Daggers [15] or 1H Maces [4]!)
local WEAPONS_DH_DEVOURER     = { [0] = true, [7] = true, [9] = true, [13] = true, [15] = true }  -- Devourer: Warglaives, Swords, Axes, Fist Weapons, Daggers (Intellect)
local WEAPONS_DK              = { [0] = true, [1] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true }
local WEAPONS_DRUID           = { [4] = true, [5] = true, [6] = true, [10] = true, [13] = true, [15] = true }
local WEAPONS_EVOKER          = { [0] = true, [1] = true, [4] = true, [5] = true, [7] = true, [8] = true, [10] = true,
    [13] = true, [15] = true }
local WEAPONS_HUNTER_RANGED   = { [2] = true, [3] = true, [18] = true }
local WEAPONS_HUNTER_MELEE    = { [1] = true, [6] = true, [8] = true, [10] = true }
local WEAPONS_MAGE            = { [7] = true, [10] = true, [15] = true, [19] = true }
local WEAPONS_MONK            = { [0] = true, [4] = true, [6] = true, [7] = true, [10] = true, [13] = true }
local WEAPONS_PALADIN         = { [0] = true, [1] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true }
local WEAPONS_PRIEST          = { [4] = true, [10] = true, [15] = true, [19] = true }
local WEAPONS_ROGUE_ASSASSIN  = { [15] = true }  -- Assassination requires Daggers in both hands
local WEAPONS_ROGUE_ALL       = { [0] = true, [4] = true, [7] = true, [13] = true, [15] = true }
local WEAPONS_SHAMAN_CASTER   = { [0] = true, [1] = true, [4] = true, [5] = true, [10] = true, [13] = true, [15] = true }
local WEAPONS_SHAMAN_ENH      = { [0] = true, [4] = true, [13] = true }  -- Enhancement cannot use daggers for Stormstrike
local WEAPONS_WARLOCK         = { [7] = true, [10] = true, [15] = true, [19] = true }
local WEAPONS_WARRIOR         = { [0] = true, [1] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true,
    [10] = true, [13] = true, [15] = true }
local WEAPONS_WARRIOR_CLASSIC = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true,
    [8] = true, [10] = true, [13] = true, [15] = true, [16] = true, [18] = true }
local WEAPONS_ROGUE_CLASSIC   = { [2] = true, [3] = true, [4] = true, [7] = true, [13] = true, [15] = true, [16] = true,
    [18] = true }
local WEAPONS_HUNTER_CLASSIC  = { [0] = true, [1] = true, [2] = true, [3] = true, [6] = true, [7] = true, [8] = true,
    [10] = true, [13] = true, [15] = true, [18] = true }

sfui.highest.rules            = {
    -- Death Knight
    [250] = { armor = 4, stat = 1, weaps = { ["2H"] = true }, allowedWeapons = WEAPONS_DK },
    [251] = { armor = 4, stat = 1, weaps = { ["2H"] = true, ["1H_Dual"] = true }, allowedWeapons = WEAPONS_DK },
    [252] = { armor = 4, stat = 1, weaps = { ["2H"] = true }, allowedWeapons = WEAPONS_DK },
    -- Demon Hunter
    [577] = { armor = 2, stat = 2, weaps = { ["1H_Dual"] = true }, allowedWeapons = WEAPONS_DH },           -- Havoc (Agility; NO Daggers)
    [581] = { armor = 2, stat = 2, weaps = { ["1H_Dual"] = true }, allowedWeapons = WEAPONS_DH },           -- Vengeance (Agility; NO Daggers)
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
    [1482] = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_MAGE },                                   -- Mage
    [1484] = { armor = 2, stat = 2, weaps = { ["2H"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_DRUID },                                                     -- Druid
    [1485] = { armor = 3, stat = 2, weaps = { ["Ranged"] = true, ["2H"] = true, ["1H_Dual"] = true }, allowedWeapons = WEAPONS_HUNTER_CLASSIC },                        -- Hunter
    [1486] = { armor = 4, stat = 1, weaps = { ["2H"] = true, ["1H_Shield"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_PALADIN },                             -- Paladin
    [1487] = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_PRIEST },                                 -- Priest
    [1488] = { armor = 2, stat = 2, weaps = { ["1H_Dual"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_ROGUE_CLASSIC },                                        -- Rogue
    [1489] = { armor = 3, stat = 4, weaps = { ["2H"] = true, ["1H_Shield"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_SHAMAN_CASTER },                       -- Shaman
    [1490] = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_WARLOCK },                                -- Warlock
    [1491] = { armor = 4, stat = 1, weaps = { ["2H"] = true, ["1H_Dual"] = true, ["1H_Shield"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_WARRIOR_CLASSIC }, -- Warrior
}

-- ────────────────────────────────────────────────────────────────────────────
-- Solution A: Authentic Classic Spec Rules Database (Tree Specs & Class Specs)
-- ────────────────────────────────────────────────────────────────────────────
sfui.highest.classic_rules    = {
    -- Warrior (1491): Arms, Fury, Prot (all can equip Ranged weapons in Classic)
    [71]   = { armor = 4, stat = 1, weaps = { ["2H"] = true, ["1H_Dual"] = true, ["1H_Shield"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_WARRIOR_CLASSIC }, -- Arms
    [72]   = { armor = 4, stat = 1, weaps = { ["2H"] = true, ["1H_Dual"] = true, ["1H_Shield"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_WARRIOR_CLASSIC }, -- Fury
    [73]   = { armor = 4, stat = 1, weaps = { ["1H_Shield"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_WARRIOR_CLASSIC },                                    -- Protection
    [1491] = { armor = 4, stat = 1, weaps = { ["2H"] = true, ["1H_Dual"] = true, ["1H_Shield"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_WARRIOR_CLASSIC }, -- Warrior

    -- Paladin (1486): Holy (Int), Prot (Tank/Str), Ret (Str)
    [65]   = { armor = 4, stat = 4, weaps = { ["2H"] = true, ["1H_Shield"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_PALADIN }, -- Holy
    [66]   = { armor = 4, stat = 1, weaps = { ["1H_Shield"] = true }, allowedWeapons = WEAPONS_PALADIN },                                   -- Protection
    [70]   = { armor = 4, stat = 1, weaps = { ["2H"] = true, ["1H_Shield"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_PALADIN }, -- Retribution
    [1486] = { armor = 4, stat = 1, weaps = { ["2H"] = true, ["1H_Shield"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_PALADIN }, -- Paladin

    -- Hunter (1485): BM, MM, Surv (Ranged Slot 18 + 2H/Dual Wield Melee)
    [253]  = { armor = 3, stat = 2, weaps = { ["Ranged"] = true, ["2H"] = true, ["1H_Dual"] = true }, allowedWeapons = WEAPONS_HUNTER_CLASSIC }, -- Beast Mastery
    [254]  = { armor = 3, stat = 2, weaps = { ["Ranged"] = true, ["2H"] = true, ["1H_Dual"] = true }, allowedWeapons = WEAPONS_HUNTER_CLASSIC }, -- Marksmanship
    [255]  = { armor = 3, stat = 2, weaps = { ["Ranged"] = true, ["2H"] = true, ["1H_Dual"] = true }, allowedWeapons = WEAPONS_HUNTER_CLASSIC }, -- Survival
    [1485] = { armor = 3, stat = 2, weaps = { ["Ranged"] = true, ["2H"] = true, ["1H_Dual"] = true }, allowedWeapons = WEAPONS_HUNTER_CLASSIC }, -- Hunter

    -- Rogue (1488): Assassination, Combat, Subtlety (Dual Wield + Ranged Slot 18)
    [259]  = { armor = 2, stat = 2, weaps = { ["1H_Dual"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_ROGUE_CLASSIC }, -- Assassination
    [260]  = { armor = 2, stat = 2, weaps = { ["1H_Dual"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_ROGUE_CLASSIC }, -- Combat
    [261]  = { armor = 2, stat = 2, weaps = { ["1H_Dual"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_ROGUE_CLASSIC }, -- Subtlety
    [1488] = { armor = 2, stat = 2, weaps = { ["1H_Dual"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_ROGUE_CLASSIC }, -- Rogue

    -- Priest (1487): Discipline, Holy, Shadow (1H/OH/Staff + Wand Slot 18)
    [256]  = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_PRIEST }, -- Discipline
    [257]  = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_PRIEST }, -- Holy
    [258]  = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_PRIEST }, -- Shadow
    [1487] = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_PRIEST }, -- Priest

    -- Shaman (1489): Elemental, Enhancement, Restoration
    [262]  = { armor = 3, stat = 4, weaps = { ["2H"] = true, ["1H_Shield"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_SHAMAN_CASTER }, -- Elemental
    [263]  = { armor = 3, stat = 1, weaps = { ["2H"] = true, ["1H_Shield"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_SHAMAN_CASTER }, -- Enhancement
    [264]  = { armor = 3, stat = 4, weaps = { ["2H"] = true, ["1H_Shield"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_SHAMAN_CASTER }, -- Restoration
    [1489] = { armor = 3, stat = 4, weaps = { ["2H"] = true, ["1H_Shield"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_SHAMAN_CASTER }, -- Shaman

    -- Mage (1482): Arcane, Fire, Frost (1H/OH/Staff + Wand Slot 18)
    [62]   = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_MAGE }, -- Arcane
    [63]   = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_MAGE }, -- Fire
    [64]   = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_MAGE }, -- Frost
    [1482] = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_MAGE }, -- Mage

    -- Warlock (1490): Affliction, Demonology, Destruction (1H/OH/Staff + Wand Slot 18)
    [265]  = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_WARLOCK }, -- Affliction
    [266]  = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_WARLOCK }, -- Demonology
    [267]  = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_WARLOCK }, -- Destruction
    [1490] = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_WARLOCK }, -- Warlock

    -- Druid (1484): Balance, Feral, Resto
    [102]  = { armor = 2, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_DRUID }, -- Balance (Caster)
    [103]  = { armor = 2, stat = 2, weaps = { ["2H"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_DRUID }, -- Feral
    [104]  = { armor = 2, stat = 2, weaps = { ["2H"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_DRUID }, -- Guardian
    [105]  = { armor = 2, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_DRUID }, -- Restoration
    [1484] = { armor = 2, stat = 2, weaps = { ["2H"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_DRUID }, -- Druid

    -- ── Camelot per-tree spec IDs (classID * 10 + treeIndex, range 14821-14913) ──
    -- These are the primary keys Camelot resolves to; classic_rules must have them
    -- for correct per-tree weapon/armor scoring (Druid Resto≠Feral, Paladin Holy≠Ret, etc.)
    -- Mage (1482)
    [14821] = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_MAGE }, -- Arcane
    [14822] = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_MAGE }, -- Fire
    [14823] = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_MAGE }, -- Frost
    -- Druid (1484)
    [14841] = { armor = 2, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_DRUID }, -- Balance (Caster: stat=4 Int)
    [14842] = { armor = 2, stat = 2, weaps = { ["2H"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_DRUID }, -- Feral Cat (stat=2 Agi)
    [14843] = { armor = 2, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_DRUID }, -- Restoration (stat=4 Int)
    [14844] = { armor = 2, stat = 1, weaps = { ["2H"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_DRUID }, -- Guardian Bear (Tank: stat=1 Str/Armor)
    -- Hunter (1485)
    [14851] = { armor = 3, stat = 2, weaps = { ["Ranged"] = true, ["2H"] = true, ["1H_Dual"] = true }, allowedWeapons = WEAPONS_HUNTER_CLASSIC }, -- Beast Mastery
    [14852] = { armor = 3, stat = 2, weaps = { ["Ranged"] = true, ["2H"] = true, ["1H_Dual"] = true }, allowedWeapons = WEAPONS_HUNTER_CLASSIC }, -- Marksmanship
    [14853] = { armor = 3, stat = 2, weaps = { ["Ranged"] = true, ["2H"] = true, ["1H_Dual"] = true }, allowedWeapons = WEAPONS_HUNTER_CLASSIC }, -- Survival
    -- Paladin (1486)
    [14861] = { armor = 4, stat = 4, weaps = { ["2H"] = true, ["1H_Shield"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_PALADIN }, -- Holy (stat=4 Int)
    [14862] = { armor = 4, stat = 1, weaps = { ["2H"] = true, ["1H_Shield"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_PALADIN }, -- Protection (stat=1 Str)
    [14863] = { armor = 4, stat = 1, weaps = { ["2H"] = true, ["1H_Shield"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_PALADIN }, -- Retribution (stat=1 Str)
    -- Priest (1487)
    [14871] = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_PRIEST }, -- Discipline
    [14872] = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_PRIEST }, -- Holy
    [14873] = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_PRIEST }, -- Shadow
    -- Rogue (1488)
    [14881] = { armor = 2, stat = 2, weaps = { ["1H_Dual"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_ROGUE_CLASSIC }, -- Assassination
    [14882] = { armor = 2, stat = 2, weaps = { ["1H_Dual"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_ROGUE_CLASSIC }, -- Combat
    [14883] = { armor = 2, stat = 2, weaps = { ["1H_Dual"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_ROGUE_CLASSIC }, -- Subtlety
    -- Shaman (1489)
    [14891] = { armor = 3, stat = 4, weaps = { ["2H"] = true, ["1H_Shield"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_SHAMAN_CASTER }, -- Elemental (stat=4 Int)
    [14892] = { armor = 3, stat = 1, weaps = { ["2H"] = true, ["1H_Shield"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_SHAMAN_ENH },    -- Enhancement (stat=1 Str)
    [14893] = { armor = 3, stat = 4, weaps = { ["2H"] = true, ["1H_Shield"] = true, ["1H_Off"] = true }, allowedWeapons = WEAPONS_SHAMAN_CASTER }, -- Restoration (stat=4 Int)
    -- Warlock (1490)
    [14901] = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_WARLOCK }, -- Affliction
    [14902] = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_WARLOCK }, -- Demonology
    [14903] = { armor = 1, stat = 4, weaps = { ["2H"] = true, ["1H_Off"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_WARLOCK }, -- Destruction
    -- Warrior (1491)
    [14911] = { armor = 4, stat = 1, weaps = { ["2H"] = true, ["1H_Dual"] = true, ["1H_Shield"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_WARRIOR_CLASSIC }, -- Arms
    [14912] = { armor = 4, stat = 1, weaps = { ["2H"] = true, ["1H_Dual"] = true, ["1H_Shield"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_WARRIOR_CLASSIC }, -- Fury
    [14913] = { armor = 4, stat = 1, weaps = { ["2H"] = true, ["1H_Dual"] = true, ["1H_Shield"] = true, ["Ranged"] = true }, allowedWeapons = WEAPONS_WARRIOR_CLASSIC }, -- Protection
}

