local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.sets_camelot = sfui.sets_camelot or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/data/sets_camelot.lua
--  In-game Armor & Dungeon Set Registry for WoW Forever / Classic
--  Covers Tier 0 (9 classes), Forever Tier 0.5 (18 multi-role variants + 4-stage
--  quest exchanges), and all 17 Classic + Forever dungeon sets.
-- ══════════════════════════════════════════════════════════════════════════════

if sfui.isRetail then return end

local _G = _G
local ipairs = _G.ipairs
local pairs = _G.pairs
local type = _G.type
local tonumber = _G.tonumber
local table_concat = _G.table.concat

local M = sfui.sets_camelot

M.SLOT_ORDER = { "head", "shoulder", "chest", "wrist", "hands", "waist", "legs", "feet" }

M.CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

M.CLASS_ARMOR = {
    WARRIOR = "plate",
    PALADIN = "plate",
    HUNTER  = "mail",
    SHAMAN  = "mail",
    ROGUE   = "leather",
    DRUID   = "leather",
    PRIEST  = "cloth",
    MAGE    = "cloth",
    WARLOCK = "cloth",
}

M.T05_PIECE_STAGE = { 4, 3, 4, 1, 2, 2, 3, 3 } -- head=4, shoulder=3, chest=4, wrist=1, hands=2, waist=2, legs=3, feet=3

M.T05_STAGES = {
    [1] = {
        name = "an earnest proposition",
        slots = "wrist",
        dungeon = "blackrock_depths",
        alliance = { DRUID = 8905, HUNTER = 8906, MAGE = 8907, PALADIN = 8908, PRIEST = 8909, ROGUE = 8910, WARLOCK = 8911, WARRIOR = 8912 },
        horde    = { DRUID = 8913, HUNTER = 8914, MAGE = 8915, PRIEST = 8916, ROGUE = 8917, SHAMAN = 8918, WARLOCK = 8919, WARRIOR = 8920 },
    },
    [2] = {
        name = "just compensation",
        slots = "hands & waist",
        dungeon = "stratholme_main",
        alliance = { DRUID = 8926, HUNTER = 8931, MAGE = 8932, PALADIN = 8933, PRIEST = 8934, ROGUE = 8935, WARLOCK = 8936, WARRIOR = 8937 },
        horde    = { DRUID = 8927, HUNTER = 8938, MAGE = 8939, PRIEST = 8940, ROGUE = 8941, SHAMAN = 8942, WARLOCK = 8943, WARRIOR = 8944 },
    },
    [3] = {
        name = "anthion's parting words",
        slots = "shoulder, legs & feet",
        dungeon = "stratholme_main",
        alliance = { DRUID = 8951, HUNTER = 8952, MAGE = 8953, PALADIN = 8954, PRIEST = 8955, ROGUE = 8956, WARLOCK = 8958, WARRIOR = 8959 },
        horde    = { DRUID = 9016, HUNTER = 9017, MAGE = 9018, PRIEST = 9019, ROGUE = 9020, SHAMAN = 8957, WARLOCK = 9021, WARRIOR = 9022 },
    },
    [4] = {
        name = "saving the best for last",
        slots = "head & chest",
        dungeon = "upper_blackrock_spire",
        alliance = { DRUID = 8999, HUNTER = 9000, MAGE = 9001, PALADIN = 9002, PRIEST = 9003, ROGUE = 9004, WARLOCK = 9005, WARRIOR = 9006 },
        horde    = { DRUID = 9007, HUNTER = 9008, MAGE = 9014, PRIEST = 9009, ROGUE = 9010, SHAMAN = 9011, WARLOCK = 9012, WARRIOR = 9013 },
    },
}

M.DUNGEON_NAMES = {
    ruins_of_lordaeron          = "ruins of lordaeron",
    the_deadmines               = "the deadmines",
    wailing_caverns             = "wailing caverns",
    city_of_dalaran             = "city of dalaran",
    scarlet_monastery_graveyard = "scarlet monastery: graveyard",
    scarlet_monastery_library   = "scarlet monastery: library",
    scarlet_monastery_armory    = "scarlet monastery: armory",
    scarlet_monastery_cathedral = "scarlet monastery: cathedral",
    kroldok_stronghold          = "krol'dok stronghold",
    alcaz_prison                = "alcaz prison",
    blackrock_depths            = "blackrock depths",
    dire_maul_east              = "dire maul: east",
    lower_blackrock_spire       = "lower blackrock spire",
    scholomance                 = "scholomance",
    stratholme_main             = "stratholme",
    upper_blackrock_spire       = "upper blackrock spire",
}

M.DUNGEON_SHORT = {
    ruins_of_lordaeron          = "lordaeron",
    the_deadmines               = "deadmines",
    wailing_caverns             = "wailing",
    city_of_dalaran             = "dalaran",
    scarlet_monastery_graveyard = "sm gy",
    scarlet_monastery_library   = "sm lib",
    scarlet_monastery_armory    = "sm arm",
    scarlet_monastery_cathedral = "sm cath",
    kroldok_stronghold          = "krol'dok",
    alcaz_prison                = "alcaz",
    blackrock_depths            = "brd",
    dire_maul_east              = "dm east",
    lower_blackrock_spire       = "lbrs",
    scholomance                 = "scholo",
    stratholme_main             = "strat",
    upper_blackrock_spire       = "ubrs",
}

local SLOT_ORDER = M.SLOT_ORDER

M.sets = {
    -- ── Tier 0 (Dungeon Set 1, 9 classes x 8 pieces) ─────────────────────────
    { id = "t0_warrior", setID = 189, name = "battlegear of valor",     category = "t0", class = "WARRIOR", armor = "plate",   minLevel = 55, maxLevel = 60, pieces = { 16731, 16733, 16730, 16735, 16737, 16736, 16732, 16734 }, slots = SLOT_ORDER },
    { id = "t0_paladin", setID = 188, name = "lightforge armor",        category = "t0", class = "PALADIN", armor = "plate",   minLevel = 55, maxLevel = 60, pieces = { 16727, 16729, 16726, 16722, 16724, 16723, 16728, 16725 }, slots = SLOT_ORDER },
    { id = "t0_hunter",  setID = 186, name = "beaststalker armor",      category = "t0", class = "HUNTER",  armor = "mail",    minLevel = 55, maxLevel = 60, pieces = { 16677, 16679, 16674, 16681, 16676, 16680, 16678, 16675 }, slots = SLOT_ORDER },
    { id = "t0_rogue",   setID = 184, name = "shadowcraft armor",       category = "t0", class = "ROGUE",   armor = "leather", minLevel = 55, maxLevel = 60, pieces = { 16707, 16708, 16721, 16710, 16712, 16713, 16709, 16711 }, slots = SLOT_ORDER },
    { id = "t0_priest",  setID = 182, name = "vestments of the devout", category = "t0", class = "PRIEST",  armor = "cloth",   minLevel = 55, maxLevel = 60, pieces = { 16693, 16695, 16690, 16697, 16692, 16696, 16694, 16691 }, slots = SLOT_ORDER },
    { id = "t0_shaman",  setID = 187, name = "the elements",            category = "t0", class = "SHAMAN",  armor = "mail",    minLevel = 55, maxLevel = 60, pieces = { 16667, 16669, 16666, 16671, 16672, 16673, 16668, 16670 }, slots = SLOT_ORDER },
    { id = "t0_mage",    setID = 181, name = "magister's regalia",      category = "t0", class = "MAGE",    armor = "cloth",   minLevel = 55, maxLevel = 60, pieces = { 16686, 16689, 16688, 16683, 16684, 16685, 16687, 16682 }, slots = SLOT_ORDER },
    { id = "t0_warlock", setID = 183, name = "dreadmist raiment",       category = "t0", class = "WARLOCK", armor = "cloth",   minLevel = 55, maxLevel = 60, pieces = { 16698, 16701, 16700, 16703, 16705, 16702, 16699, 16704 }, slots = SLOT_ORDER },
    { id = "t0_druid",   setID = 185, name = "wildheart raiment",       category = "t0", class = "DRUID",   armor = "leather", minLevel = 55, maxLevel = 60, pieces = { 16720, 16718, 16706, 16714, 16717, 16716, 16719, 16715 }, slots = SLOT_ORDER },

    -- ── Tier 0.5 Forever (Dungeon Set 2, 18 role-specific variants) ──────────
    { id = "t05_warrior_melee",  name = "battlegear of heroism",     category = "t05", class = "WARRIOR", role = "melee",  armor = "plate",   minLevel = 60, maxLevel = 60, isForever = true, upgradeFrom = "t0_warrior", pieces = { 226860, 226858, 226862, 226863, 226861, 226864, 226859, 226857 }, slots = SLOT_ORDER },
    { id = "t05_warrior_tank",   name = "battlegear of heroism",     category = "t05", class = "WARRIOR", role = "tank",   armor = "plate",   minLevel = 60, maxLevel = 60, isForever = true, upgradeFrom = "t0_warrior", pieces = { 226869, 226867, 226872, 226865, 226870, 226866, 226868, 226871 }, slots = SLOT_ORDER },
    { id = "t05_paladin_melee",  name = "soulforge armor",           category = "t05", class = "PALADIN", role = "melee",  armor = "plate",   minLevel = 60, maxLevel = 60, isForever = true, upgradeFrom = "t0_paladin", pieces = { 226976, 226969, 226973, 226970, 226975, 226971, 226972, 226974 }, slots = SLOT_ORDER },
    { id = "t05_paladin_healer", name = "soulforge armor",           category = "t05", class = "PALADIN", role = "healer", armor = "plate",   minLevel = 60, maxLevel = 60, isForever = true, upgradeFrom = "t0_paladin", pieces = { 226981, 226979, 226984, 226977, 226982, 226978, 226980, 226983 }, slots = SLOT_ORDER },
    { id = "t05_paladin_tank",   name = "soulforge armor",           category = "t05", class = "PALADIN", role = "tank",   armor = "plate",   minLevel = 60, maxLevel = 60, isForever = true, upgradeFrom = "t0_paladin", pieces = { 226989, 226987, 226992, 226985, 226990, 226986, 226988, 226991 }, slots = SLOT_ORDER },
    { id = "t05_hunter",         name = "beastmaster armor",         category = "t05", class = "HUNTER",                  armor = "mail",    minLevel = 60, maxLevel = 60, isForever = true, upgradeFrom = "t0_hunter",  pieces = { 226887, 226884, 226886, 226885, 226883, 226888, 226882, 226881 }, slots = SLOT_ORDER },
    { id = "t05_rogue",          name = "darkmantle armor",          category = "t05", class = "ROGUE",                   armor = "leather", minLevel = 60, maxLevel = 60, isForever = true, upgradeFrom = "t0_rogue",   pieces = { 226829, 226826, 226825, 226830, 226828, 226832, 226827, 226831 }, slots = SLOT_ORDER },
    { id = "t05_priest_healer",  name = "vestments of the virtuous", category = "t05", class = "PRIEST",  role = "healer", armor = "cloth",   minLevel = 60, maxLevel = 60, isForever = true, upgradeFrom = "t0_priest",  pieces = { 226947, 226951, 226945, 226949, 226950, 226948, 226946, 226952 }, slots = SLOT_ORDER },
    { id = "t05_priest_caster",  name = "vestments of the virtuous", category = "t05", class = "PRIEST",  role = "caster", armor = "cloth",   minLevel = 60, maxLevel = 60, isForever = true, upgradeFrom = "t0_priest",  pieces = { 226957, 226955, 226960, 226953, 226958, 226954, 226956, 226959 }, slots = SLOT_ORDER },
    { id = "t05_shaman_caster",  name = "the five thunders",         category = "t05", class = "SHAMAN",  role = "caster", armor = "mail",    minLevel = 60, maxLevel = 60, isForever = true, upgradeFrom = "t0_shaman",  pieces = { 227002, 227003, 227004, 227001, 227006, 227008, 227005, 227007 }, slots = SLOT_ORDER },
    { id = "t05_shaman_healer",  name = "the five thunders",         category = "t05", class = "SHAMAN",  role = "healer", armor = "mail",    minLevel = 60, maxLevel = 60, isForever = true, upgradeFrom = "t0_shaman",  pieces = { 227013, 227011, 227016, 227009, 227014, 227010, 227012, 227015 }, slots = SLOT_ORDER },
    { id = "t05_shaman_melee",   name = "the five thunders",         category = "t05", class = "SHAMAN",  role = "melee",  armor = "mail",    minLevel = 60, maxLevel = 60, isForever = true, upgradeFrom = "t0_shaman",  pieces = { 227021, 227019, 227024, 227017, 227022, 227018, 227020, 227023 }, slots = SLOT_ORDER },
    { id = "t05_mage",           name = "sorcerer's regalia",        category = "t05", class = "MAGE",                    armor = "cloth",   minLevel = 60, maxLevel = 60, isForever = true, upgradeFrom = "t0_mage",    pieces = { 226935, 226936, 226932, 226929, 226930, 226934, 226933, 226931 }, slots = SLOT_ORDER },
    { id = "t05_warlock",        name = "deathmist raiment",         category = "t05", class = "WARLOCK",                 armor = "cloth",   minLevel = 60, maxLevel = 60, isForever = true, upgradeFrom = "t0_warlock", pieces = { 226909, 226912, 226906, 226907, 226911, 226905, 226910, 226908 }, slots = SLOT_ORDER },
    { id = "t05_druid_caster",   name = "feralheart raiment",        category = "t05", class = "DRUID",   role = "caster", armor = "leather", minLevel = 60, maxLevel = 60, isForever = true, upgradeFrom = "t0_druid",   pieces = { 226773, 226778, 226776, 226775, 226777, 226772, 226779, 226774 }, slots = SLOT_ORDER },
    { id = "t05_druid_healer",   name = "feralheart raiment",        category = "t05", class = "DRUID",   role = "healer", armor = "leather", minLevel = 60, maxLevel = 60, isForever = true, upgradeFrom = "t0_druid",   pieces = { 226786, 226785, 226783, 226782, 226784, 226780, 226787, 226781 }, slots = SLOT_ORDER },
    { id = "t05_druid_melee",    name = "feralheart raiment",        category = "t05", class = "DRUID",   role = "melee",  armor = "leather", minLevel = 60, maxLevel = 60, isForever = true, upgradeFrom = "t0_druid",   pieces = { 226792, 226790, 226795, 226788, 226793, 226789, 226791, 226794 }, slots = SLOT_ORDER },
    { id = "t05_druid_tank",     name = "feralheart raiment",        category = "t05", class = "DRUID",   role = "tank",   armor = "leather", minLevel = 60, maxLevel = 60, isForever = true, upgradeFrom = "t0_druid",   pieces = { 226801, 226798, 226804, 226796, 226802, 226797, 226799, 226803 }, slots = SLOT_ORDER },

    -- ── Dungeon Sets (All Classic + Forever sets, ordered by minLevel) ───────
    { id = "rotmenders_raiment",          setID = 2133, name = "rotmender's raiment",          category = "dungeon", armor = "cloth",   minLevel = 18, maxLevel = 22, isForever = true, dungeonID = "ruins_of_lordaeron",          pieces = { 286978, 286979, 286980, 271207, 271214 },                         slots = { "chest", "hands", "waist", "legs", "feet" } },
    { id = "defias_leather",              setID = 161,  name = "defias leather",               category = "dungeon", armor = "leather", minLevel = 18, maxLevel = 22,                   dungeonID = "the_deadmines",               pieces = { 10399, 10401, 10403, 10400, 10402 },                              slots = { "chest", "hands", "waist", "legs", "feet" } },
    { id = "partners_in_crime",           setID = 2131, name = "partners in crime",            category = "dungeon", armor = "ring",    minLevel = 19, maxLevel = 23, isForever = true, dungeonID = "the_deadmines",               pieces = { 284715, 284716 },                                                   slots = { "finger", "finger" } },
    { id = "embrace_of_the_viper",        setID = 162,  name = "embrace of the viper",         category = "dungeon", armor = "leather", minLevel = 18, maxLevel = 24,                   dungeonID = "wailing_caverns",             pieces = { 6473, 10413, 10412, 10410, 10411 },                               slots = { "chest", "hands", "waist", "legs", "feet" } },
    { id = "violet_sorcerers_vestments",  setID = 2134, name = "violet sorcerer's vestments",  category = "dungeon", armor = "cloth",   minLevel = 30, maxLevel = 35, isForever = true, dungeonID = "city_of_dalaran",             pieces = { 273051, 273044, 286989, 286988, 286987 },                         slots = { "shoulder", "chest", "hands", "legs", "feet" } },
    { id = "chain_of_the_scarlet_crusade",setID = 163,  name = "chain of the scarlet crusade", category = "dungeon", armor = "mail",    minLevel = 32, maxLevel = 42,                   dungeonID = "scarlet_monastery_armory",    pieces = { 10328, 10333, 10331, 10329, 10330, 10332 },                       slots = { "chest", "wrist", "hands", "waist", "legs", "feet" } },
    { id = "kroldok_battlegear",          setID = 2135, name = "krol'dok battlegear",          category = "dungeon", armor = "plate",   minLevel = 41, maxLevel = 46, isForever = true, dungeonID = "kroldok_stronghold",          pieces = { 275006, 287014, 275005, 287012, 287013 },                         slots = { "head", "shoulder", "chest", "hands", "legs" } },
    { id = "defias_enforcers_garb",       setID = 2136, name = "defias enforcer's garb",       category = "dungeon", armor = "leather", minLevel = 46, maxLevel = 51, isForever = true, dungeonID = "alcaz_prison",                pieces = { 287019, 276741, 287020, 276746, 287021 },                         slots = { "head", "shoulder", "chest", "legs", "feet" } },
    { id = "the_gladiator",               setID = 1,    name = "the gladiator",                category = "dungeon", armor = "mail",    minLevel = 52, maxLevel = 58,                   dungeonID = "blackrock_depths",            pieces = { 11729, 277117, 11726, 11730, 11728, 11731 },                      slots = { "head", "shoulder", "chest", "hands", "legs", "feet" } },
    { id = "spiders_kiss",                setID = 65,   name = "spider's kiss",                category = "dungeon", armor = "weapon",  minLevel = 55, maxLevel = 60,                   dungeonID = "lower_blackrock_spire",       pieces = { 13183, 13218 },                                                     slots = { "one-hand", "one-hand" } },
    { id = "the_postmaster",              setID = 81,   name = "the postmaster",               category = "dungeon", armor = "cloth",   minLevel = 56, maxLevel = 60,                   dungeonID = "stratholme_main",             pieces = { 13390, 13388, 13389, 13391, 13392 },                              slots = { "head", "chest", "legs", "feet", "finger" } },
    { id = "cadaverous_garb",             setID = 121,  name = "cadaverous garb",              category = "dungeon", armor = "leather", minLevel = 56, maxLevel = 60,                   dungeonID = "scholomance",                 pieces = { 14637, 14640, 14636, 14638, 14641 },                              slots = { "chest", "hands", "waist", "legs", "feet" } },
    { id = "necropile_raiment",           setID = 122,  name = "necropile raiment",            category = "dungeon", armor = "cloth",   minLevel = 56, maxLevel = 60,                   dungeonID = "scholomance",                 pieces = { 14633, 14626, 14629, 14632, 14631 },                              slots = { "shoulder", "chest", "wrist", "legs", "feet" } },
    { id = "bloodmail_regalia",           setID = 123,  name = "bloodmail regalia",            category = "dungeon", armor = "mail",    minLevel = 56, maxLevel = 60,                   dungeonID = "scholomance",                 pieces = { 14611, 14615, 14614, 14612, 14616 },                              slots = { "chest", "hands", "waist", "legs", "feet" } },
    { id = "deathbone_guardian",          setID = 124,  name = "deathbone guardian",           category = "dungeon", armor = "plate",   minLevel = 56, maxLevel = 60,                   dungeonID = "scholomance",                 pieces = { 14624, 14622, 14620, 14623, 14621 },                              slots = { "chest", "hands", "waist", "legs", "feet" } },
    { id = "dalrends_arms",               setID = 41,   name = "dal'rend's arms",              category = "dungeon", armor = "weapon",  minLevel = 58, maxLevel = 60,                   dungeonID = "upper_blackrock_spire",       pieces = { 12940, 12939 },                                                     slots = { "main hand", "off hand" } },
    { id = "ironweave_battlesuit",        setID = 520,  name = "ironweave battlesuit",         category = "dungeon", armor = "cloth",   minLevel = 58, maxLevel = 60,                   dungeonID = "upper_blackrock_spire",       pieces = { 22302, 22305, 22301, 22313, 22304, 22306, 22303, 22311 },           slots = SLOT_ORDER },
}

-- Supplemental drop sources for trash BoEs, Rivendare/missing T0 bosses, Scarlet SM drops,
-- BRD Ring of Law arena bosses, Ironweave T0.5 summoned bosses, and Forever custom trash/bosses.
local EXTRA_SOURCES = {
    -- T0 non-dj_camelot boss & BoE trash pieces
    [16735] = { { dungeonID = "lower_blackrock_spire", bossName = "Quartermaster Zigris" }, { dungeonID = "upper_blackrock_spire", trash = true, boe = true } }, -- Bracers of Valor
    [16736] = { { dungeonID = "stratholme_main", trash = true, boe = true, mobs = "patchwork horror / venom belcher / bile spewer" }, { dungeonID = "upper_blackrock_spire", trash = true, boe = true } }, -- Belt of Valor
    [16732] = { { dungeonID = "stratholme_main", bossName = "Baron Rivendare" } }, -- Legplates of Valor
    [16724] = { { dungeonID = "stratholme_main", bossName = "Timmy the Cruel" } }, -- Lightforge Gauntlets
    [16723] = { { dungeonID = "stratholme_main", trash = true, boe = true, mobs = "crimson guardsman / rockwing gargoyle" } }, -- Lightforge Belt
    [16728] = { { dungeonID = "stratholme_main", bossName = "Baron Rivendare" } }, -- Lightforge Legplates
    [16681] = { { dungeonID = "stratholme_main", trash = true, boe = true, mobs = "crimson defender / ghoul ravener / fleshflayer ghoul" }, { dungeonID = "upper_blackrock_spire", trash = true, boe = true } }, -- Beaststalker's Bindings
    [16680] = { { dungeonID = "lower_blackrock_spire", bossName = "Quartermaster Zigris" }, { dungeonID = "upper_blackrock_spire", trash = true, boe = true } }, -- Beaststalker's Belt
    [16678] = { { dungeonID = "stratholme_main", bossName = "Baron Rivendare" } }, -- Beaststalker's Pants
    [16708] = { { dungeonID = "stratholme_main", bossName = "Willey Hopebreaker", displayBoss = "cannon master willey" } }, -- Shadowcraft Spaulders
    [16710] = { { dungeonID = "scholomance", bossName = "Instructor Malicia" }, { dungeonID = "scholomance", trash = true, boe = true, mobs = "scholomance occultist / risen construct" }, { dungeonID = "stratholme_main", trash = true, boe = true, mobs = "plague ghoul" } }, -- Shadowcraft Bracers
    [16713] = { { dungeonID = "lower_blackrock_spire", bossName = "Quartermaster Zigris" }, { dungeonID = "upper_blackrock_spire", trash = true, boe = true } }, -- Shadowcraft Belt
    [16709] = { { dungeonID = "stratholme_main", bossName = "Baron Rivendare" } }, -- Shadowcraft Pants
    [16697] = { { dungeonID = "stratholme_main", trash = true, boe = true, mobs = "crimson conjuror / crimson priest / thuzadin necromancer" } }, -- Devout Bracers
    [16696] = { { dungeonID = "lower_blackrock_spire", bossName = "Quartermaster Zigris" }, { dungeonID = "upper_blackrock_spire", trash = true, boe = true } }, -- Devout Belt
    [16694] = { { dungeonID = "stratholme_main", bossName = "Baron Rivendare" } }, -- Devout Skirt
    [16691] = { { dungeonID = "stratholme_main", bossName = "Maleki the Pallid" } }, -- Devout Sandals
    [16671] = { { dungeonID = "scholomance", trash = true, boe = true, mobs = "splintered skeleton" }, { dungeonID = "stratholme_main", trash = true, boe = true, mobs = "crimson monk / crypt crawler" } }, -- Bindings of Elements
    [16673] = { { dungeonID = "lower_blackrock_spire", bossName = "Quartermaster Zigris" }, { dungeonID = "upper_blackrock_spire", trash = true, boe = true } }, -- Cord of Elements
    [16668] = { { dungeonID = "stratholme_main", bossName = "Baron Rivendare" } }, -- Kilt of Elements
    [16683] = { { dungeonID = "lower_blackrock_spire", bossName = "Quartermaster Zigris" }, { dungeonID = "upper_blackrock_spire", trash = true, boe = true } }, -- Magister's Bindings
    [16685] = { { dungeonID = "scholomance", trash = true, boe = true, mobs = "scholomance adept" }, { dungeonID = "stratholme_main", trash = true, boe = true, mobs = "crimson sorcerer / thuzadin shadowcaster" } }, -- Magister's Belt
    [16687] = { { dungeonID = "stratholme_main", bossName = "Baron Rivendare" } }, -- Magister's Leggings
    [16703] = { { dungeonID = "lower_blackrock_spire", bossName = "Quartermaster Zigris" }, { dungeonID = "upper_blackrock_spire", trash = true, boe = true } }, -- Dreadmist Bracers
    [16702] = { { dungeonID = "scholomance", trash = true, boe = true, mobs = "scholomance necromancer" }, { dungeonID = "stratholme_main", trash = true, boe = true, mobs = "crimson sorcerer / thuzadin necromancer" } }, -- Dreadmist Belt
    [16699] = { { dungeonID = "stratholme_main", bossName = "Baron Rivendare" } }, -- Dreadmist Leggings
    [16714] = { { dungeonID = "scholomance", trash = true, boe = true, mobs = "diseased ghoul" }, { dungeonID = "stratholme_main", trash = true, boe = true, mobs = "crimson inquisitor / shrieking banshee" } }, -- Wildheart Bracers
    [16717] = { { dungeonID = "stratholme_main", bossName = "The Unforgiven" }, { dungeonID = "upper_blackrock_spire", trash = true, boe = true } }, -- Wildheart Gloves
    [16716] = { { dungeonID = "scholomance", bossName = "The Ravenian" }, { dungeonID = "lower_blackrock_spire", bossName = "Quartermaster Zigris" }, { dungeonID = "scholomance", trash = true, boe = true, mobs = "spectral researcher / spectral teacher" } }, -- Wildheart Belt
    [16719] = { { dungeonID = "stratholme_main", bossName = "Baron Rivendare" } }, -- Wildheart Kilt

    -- Chain of the Scarlet Crusade (all 6 pieces across SM wings)
    [10328] = { { dungeonID = "scarlet_monastery_cathedral", trash = true, boe = true, mobs = "scarlet champion" } }, -- Scarlet Chestpiece
    [10329] = { { dungeonID = "scarlet_monastery_armory", trash = true, boe = true, mobs = "scarlet defender / scarlet myrmidon" } }, -- Scarlet Belt
    [10330] = { { dungeonID = "scarlet_monastery_armory", bossName = "Herod" }, { dungeonID = "scarlet_monastery_cathedral", bossName = "Scarlet Commander Mograine" } }, -- Scarlet Leggings
    [10331] = { { dungeonID = "scarlet_monastery_cathedral", trash = true, boe = true, mobs = "scarlet centurion" } }, -- Scarlet Gauntlets
    [10332] = { { dungeonID = "scarlet_monastery_armory", trash = true, boe = true, mobs = "scarlet monastery trash" }, { dungeonID = "scarlet_monastery_cathedral", trash = true, boe = true, mobs = "scarlet monastery trash" }, { dungeonID = "scarlet_monastery_graveyard", trash = true, boe = true, mobs = "scarlet monastery trash" }, { dungeonID = "scarlet_monastery_library", trash = true, boe = true, mobs = "scarlet monastery trash" } }, -- Scarlet Boots
    [10333] = { { dungeonID = "scarlet_monastery_graveyard", trash = true, boe = true, mobs = "scarlet monastery trash" }, { dungeonID = "scarlet_monastery_library", trash = true, boe = true, mobs = "scarlet monastery trash" } }, -- Scarlet Wristguards

    -- Defias Leather & Embrace of the Viper trash drops
    [10400] = { { dungeonID = "the_deadmines", trash = true, mobs = "defias overseer / defias taskmaster" } }, -- Blackened Defias Leggings
    [10401] = { { dungeonID = "the_deadmines", trash = true, mobs = "defias overseer / defias taskmaster" } }, -- Blackened Defias Gloves
    [10402] = { { dungeonID = "the_deadmines", trash = true, mobs = "defias strip miner" } }, -- Blackened Defias Boots
    [10413] = { { dungeonID = "wailing_caverns", trash = true, mobs = "druid of the fang" } }, -- Gloves of the Fang

    -- The Gladiator (6 pieces, BRD Ring of Law arena bosses)
    [11726]  = { { dungeonID = "blackrock_depths", bossName = "Ring of Law", displayBoss = "gorosh the dervish (ring of law)" } }, -- Savage Gladiator Chain
    [277117] = { { dungeonID = "blackrock_depths", bossName = "Ring of Law", displayBoss = "grizzle (ring of law)" } }, -- Savage Gladiator Shoulders
    [11728]  = { { dungeonID = "blackrock_depths", bossName = "Ring of Law", displayBoss = "ok'thor the breaker (ring of law)" } }, -- Savage Gladiator Leggings
    [11729]  = { { dungeonID = "blackrock_depths", bossName = "Ring of Law", displayBoss = "hedrum the creeper (ring of law)" } }, -- Savage Gladiator Helm
    [11730]  = { { dungeonID = "blackrock_depths", bossName = "Ring of Law", displayBoss = "eviscerator (ring of law)" } }, -- Savage Gladiator Grips
    [11731]  = { { dungeonID = "blackrock_depths", bossName = "Ring of Law", displayBoss = "anub'shiah (ring of law)" } }, -- Savage Gladiator Greaves

    -- Spider's Kiss (LBRS Crystal Fang)
    [13218] = { { dungeonID = "lower_blackrock_spire", bossName = "Mother Smolderweb", displayBoss = "crystal fang (rare)" } }, -- Fang of the Crystal Spider

    -- Ironweave Battlesuit summoned Dungeon Set 2 bosses (and BRD Theldren)
    [22301] = { { dungeonID = "stratholme_main", bossName = "Balnazzar", displayBoss = "jarien & sothos (summoned)" , summoned = true } }, -- Ironweave Robe
    [22303] = { { dungeonID = "scholomance", bossName = "Ras Frostwhisper", displayBoss = "kormok (summoned)", summoned = true } }, -- Ironweave Pants
    [22304] = { { dungeonID = "dire_maul_east", bossName = "Alzzin the Wildshaper", displayBoss = "isalien (summoned)", summoned = true } }, -- Ironweave Gloves
    [22306] = { { dungeonID = "lower_blackrock_spire", bossName = "Shadow Hunter Vosh'gajin", displayBoss = "mor grayhoof (summoned)", summoned = true } }, -- Ironweave Belt

    -- Forever custom dungeon sets
    [284716] = { { trash = true, displayBoss = "quest / world drop" } }, -- Band of the Better Half (Partners in Crime)
    [286978] = { { dungeonID = "ruins_of_lordaeron", trash = true, mobs = "all ruins of lordaeron trash" } }, -- Rotmender's Garb
    [286979] = { { dungeonID = "ruins_of_lordaeron", trash = true, mobs = "all ruins of lordaeron trash" } }, -- Rotmender's Gloves
    [286980] = { { dungeonID = "ruins_of_lordaeron", trash = true, mobs = "all ruins of lordaeron trash" } }, -- Rotmender's Sash
    [273044] = { { dungeonID = "city_of_dalaran", bossName = "Arcanic Enigma" } }, -- Violet Sorcerer's Robes
    [286987] = { { dungeonID = "city_of_dalaran", trash = true, mobs = "dark caster / kirin tor necromancer" } }, -- Violet Sorcerer's Sandals
    [286988] = { { dungeonID = "city_of_dalaran", trash = true, mobs = "fallen mage / dark caster" } }, -- Violet Sorcerer's Leggings
    [286989] = { { dungeonID = "city_of_dalaran", trash = true, mobs = "kirin tor necromancer / fallen mage" } }, -- Violet Sorcerer's Wraps
    [287012] = { { dungeonID = "kroldok_stronghold", trash = true, mobs = "krol'dok stronghold trash" } }, -- Krol'dok Warplate Gauntlets
    [287013] = { { dungeonID = "kroldok_stronghold", trash = true, mobs = "krol'dok stronghold trash" } }, -- Krol'dok Warplate Legplates
    [287014] = { { dungeonID = "kroldok_stronghold", trash = true, mobs = "krol'dok stronghold trash" } }, -- Krol'dok Warplate Pauldrons
    [276746] = { { dungeonID = "alcaz_prison", bossName = "Blazeroar" } }, -- Defias Enforcer's Legguards
    [287019] = { { dungeonID = "alcaz_prison", trash = true, mobs = "alcaz prison trash" } }, -- Defias Enforcer's Mask
    [287020] = { { dungeonID = "alcaz_prison", trash = true, mobs = "alcaz prison trash" } }, -- Defias Enforcer's Chest
    [287021] = { { dungeonID = "alcaz_prison", trash = true, mobs = "alcaz prison trash" } }, -- Defias Enforcer's Prowlers
}

local setByID = nil
local itemSetCache = nil
local t0ToT05Cache = nil
local djMultiSourceCache = nil
local itemSourcesCache = {}

local BADGE_STYLES = {
    t0      = { tag = "t0",   color = "55aaff" },
    t05     = { tag = "t0.5", color = "c077ff" },
    dungeon = { tag = "set",  color = "44ddaa" },
}

local function BuildIndexes()
    if setByID and itemSetCache and t0ToT05Cache then return end
    setByID = {}
    itemSetCache = {}
    t0ToT05Cache = {}

    for _, s in ipairs(M.sets) do
        setByID[s.id] = s
        if s.setID then
            setByID[s.setID] = s
        end
        local badge = BADGE_STYLES[s.category] or BADGE_STYLES.dungeon
        local slots = s.slots or SLOT_ORDER
        for idx, itemID in ipairs(s.pieces or {}) do
            itemSetCache[itemID] = {
                set        = s,
                pieceIdx   = idx,
                slotName   = slots[idx] or "slot",
                badgeTag   = badge.tag,
                badgeColor = badge.color,
                category   = s.category,
            }
        end
    end

    for _, s in ipairs(M.sets) do
        if s.category == "t05" and s.upgradeFrom then
            local baseSet = setByID[s.upgradeFrom]
            if baseSet and baseSet.pieces then
                for idx, t0ItemID in ipairs(baseSet.pieces) do
                    local entry = t0ToT05Cache[t0ItemID]
                    if not entry then
                        local stage = M.T05_PIECE_STAGE[idx] or 1
                        local stInfo = M.T05_STAGES[stage]
                        entry = {
                            t0Set        = baseSet,
                            t05Sets      = {},
                            pieceIdx     = idx,
                            slotName     = (baseSet.slots and baseSet.slots[idx]) or SLOT_ORDER[idx],
                            stage        = stage,
                            stageName    = stInfo and stInfo.name or "",
                            stageDungeon = stInfo and stInfo.dungeon or "stratholme_main",
                            classToken   = baseSet.class,
                        }
                        t0ToT05Cache[t0ItemID] = entry
                    end
                    entry.t05Sets[#entry.t05Sets + 1] = s
                end
            end
        end
    end
end

local function EnsureDJMultiSourceCache()
    if djMultiSourceCache then return djMultiSourceCache end
    djMultiSourceCache = {}
    local dj = sfui.dj_camelot
    if not dj then return djMultiSourceCache end

    local lists = { dj.dungeons or {}, dj.raids or {} }
    for _, list in ipairs(lists) do
        for _, dungeon in ipairs(list) do
            for _, boss in ipairs(dungeon.bosses or {}) do
                for _, itemID in ipairs(boss.items or {}) do
                    local rawID = type(itemID) == "table" and (itemID.id or itemID[1]) or itemID
                    local numID = tonumber(rawID)
                    if numID then
                        local arr = djMultiSourceCache[numID]
                        if not arr then
                            arr = {}
                            djMultiSourceCache[numID] = arr
                        end
                        arr[#arr + 1] = {
                            dungeonID   = dungeon.id,
                            dungeonName = (dungeon.name or M.DUNGEON_NAMES[dungeon.id] or dungeon.id):lower(),
                            bossName    = boss.name,
                            displayBoss = (boss.name or ""):lower(),
                            dropRate    = boss.dropRates and boss.dropRates[numID] or nil,
                        }
                    end
                end
            end
        end
    end
    return djMultiSourceCache
end

function M.GetAllSets()
    return M.sets
end

function M.GetSetByID(idOrSetID)
    if not idOrSetID then return nil end
    BuildIndexes()
    return setByID[idOrSetID]
end

function M.GetItemSetInfo(itemID)
    local id = tonumber(itemID)
    if not id then return nil end
    BuildIndexes()
    return itemSetCache[id]
end

function M.GetT05QuestID(classToken, stage, faction)
    if not classToken or not stage then return nil end
    local st = M.T05_STAGES[stage]
    if not st then return nil end
    local cls = classToken:upper()
    local fac = type(faction) == "string" and faction:lower() or nil
    if not fac and sfui.common and sfui.common.get_player_faction then
        local pf = sfui.common.get_player_faction()
        if type(pf) == "string" then
            fac = pf:lower()
        end
    end
    if not fac and _G.UnitFactionGroup then
        local uf = _G.UnitFactionGroup("player")
        if type(uf) == "string" then
            fac = uf:lower()
        end
    end
    if fac == "horde" then
        return (st.horde and st.horde[cls]) or (st.alliance and st.alliance[cls])
    end
    return (st.alliance and st.alliance[cls]) or (st.horde and st.horde[cls])
end

function M.GetT0UpgradeInfo(t0ItemID)
    local id = tonumber(t0ItemID)
    if not id then return nil end
    BuildIndexes()
    return t0ToT05Cache[id]
end

function M.GetDungeonDisplayName(dungeonID, short)
    if not dungeonID then return "dungeon" end
    if short and M.DUNGEON_SHORT[dungeonID] then
        return M.DUNGEON_SHORT[dungeonID]
    end
    if M.DUNGEON_NAMES[dungeonID] then
        return M.DUNGEON_NAMES[dungeonID]
    end
    local d = sfui.dj_camelot and sfui.dj_camelot.GetDungeonByName and sfui.dj_camelot.GetDungeonByName(dungeonID)
    if d and d.name then
        return d.name:lower()
    end
    return tostring(dungeonID):gsub("_", " "):lower()
end

function M.GetPieceSources(itemID)
    local id = tonumber(itemID)
    if not id then return {} end
    if itemSourcesCache[id] then
        return itemSourcesCache[id]
    end

    local results = {}
    local seen = {}

    local function AddEntry(src)
        local key = table_concat({
            tostring(src.dungeonID or ""),
            tostring(src.displayBoss or src.bossName or (src.trash and "trash" or "")),
        }, ":")
        if seen[key] then return end
        seen[key] = true
        results[#results + 1] = {
            dungeonID   = src.dungeonID,
            dungeonName = (src.dungeonName or M.GetDungeonDisplayName(src.dungeonID, false)):lower(),
            bossName    = src.bossName,
            displayBoss = (src.displayBoss or (src.bossName and src.bossName:lower()) or (src.trash and "trash drops") or "unknown"),
            dropRate    = src.dropRate,
            trash       = src.trash and true or false,
            mobs        = src.mobs,
            boe         = src.boe and true or false,
            summoned    = src.summoned and true or false,
        }
    end

    local djCache = EnsureDJMultiSourceCache()
    local djHits = djCache[id]
    if djHits then
        for _, src in ipairs(djHits) do
            AddEntry(src)
        end
    end

    local extra = EXTRA_SOURCES[id]
    if extra then
        for _, src in ipairs(extra) do
            AddEntry(src)
        end
    end

    if #results == 0 then
        local info = M.GetItemSetInfo(id)
        if info and info.set and info.set.category == "t05" then
            local baseSet = info.set.upgradeFrom and M.GetSetByID(info.set.upgradeFrom)
            local stage = M.T05_PIECE_STAGE[info.pieceIdx] or 1
            local st = M.T05_STAGES[stage]
            if st then
                AddEntry({
                    dungeonID   = st.dungeon,
                    dungeonName = M.GetDungeonDisplayName(st.dungeon, false),
                    displayBoss = st.name,
                })
            elseif baseSet then
                AddEntry({ displayBoss = "t0.5 quest upgrade" })
            end
        end
    end

    itemSourcesCache[id] = results
    return results
end

local ARMOR_PROFICIENCY = {
    plate = { WARRIOR = true, PALADIN = true },
    mail = { WARRIOR = true, PALADIN = true, HUNTER = true, SHAMAN = true },
    leather = { WARRIOR = true, PALADIN = true, HUNTER = true, SHAMAN = true, ROGUE = true, DRUID = true },
    cloth = { WARRIOR = true, PALADIN = true, HUNTER = true, SHAMAN = true, ROGUE = true, DRUID = true, PRIEST = true, MAGE = true, WARLOCK = true },
    ring = { WARRIOR = true, PALADIN = true, HUNTER = true, SHAMAN = true, ROGUE = true, DRUID = true, PRIEST = true, MAGE = true, WARLOCK = true },
}

local WEAPON_SET_CLASSES = {
    dalrends_arms = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, MAGE = true, WARLOCK = true }, -- 1h swords
    spiders_kiss  = { WARRIOR = true, ROGUE = true, PRIEST = true, SHAMAN = true, DRUID = true }, -- 1h mace / dagger
}

function M.CanClassWearSet(set, classToken)
    if not set or not classToken then return true end
    local cls = classToken:upper()
    if set.class then
        return set.class == cls
    end
    if WEAPON_SET_CLASSES[set.id] then
        return WEAPON_SET_CLASSES[set.id][cls] == true
    end
    local prof = ARMOR_PROFICIENCY[set.armor]
    if prof then
        return prof[cls] == true
    end
    return true
end
