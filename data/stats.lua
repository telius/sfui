local addonName, addon = ...
sfui = sfui or {}
sfui.data = sfui.data or {}

-- ══════════════════════════════════════════════════════════════════════════════
-- SFUI Spec Secondary Stat Priorities & Spec Definitions Database
--
-- Plain data definitions for specs, stat weights, roles, and Retail / Camelot IDs.
-- Easily adjustable entries.
-- ══════════════════════════════════════════════════════════════════════════════

sfui.data.SPEC_DEFINITIONS = {
    -- WARRIOR (1491)
    {
        camelotID = 14911, retailID = 71, classID = 1491, class = "WARRIOR", classFile = "WARRIOR",
        treeIndex = 1, name = "arms", icon = 132355, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "C", "H", "M", "V" },
        classicStats = { "Str", "AP", "Hit", "Crit", "ArP", "Exp", "Agi", "Stam", "H", "Arm" },
        roleStats = {
            ["DPS"]  = { "Str", "AP", "Hit", "Crit", "ArP", "Exp", "Agi", "Stam", "H", "Arm" },
            ["TANK"] = { "Def", "Stam", "Arm", "BlockVal", "Block", "Dodge", "Parry", "Hit" },
        },
    },
    {
        camelotID = 14912, retailID = 72, classID = 1491, class = "WARRIOR", classFile = "WARRIOR",
        treeIndex = 2, name = "fury", icon = 132347, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "M", "H", "C", "V" },
        classicStats = { "AP", "Hit", "Crit", "ArP", "Exp", "Str", "Agi", "Stam", "H", "Arm" },
        roleStats = {
            ["DPS"]  = { "AP", "Hit", "Crit", "ArP", "Exp", "Str", "Agi", "Stam", "H", "Arm" },
            ["TANK"] = { "Def", "Stam", "Arm", "BlockVal", "Block", "Dodge", "Parry", "Hit" },
        },
    },
    {
        camelotID = 14913, retailID = 73, classID = 1491, class = "WARRIOR", classFile = "WARRIOR",
        treeIndex = 3, name = "protection", icon = 132341, role = "TANK", isTank = true, isHealer = false, isClassic = true,
        retailStats  = { "H", "C", "V", "M" },
        classicStats = { "Def", "Stam", "Arm", "BlockVal", "Block", "Dodge", "Parry", "Hit", "Str" },
        roleStats = {
            ["TANK"] = { "Def", "Stam", "Arm", "BlockVal", "Block", "Dodge", "Parry", "Hit", "Str" },
            ["DPS"]  = { "Str", "AP", "Hit", "Crit", "ArP", "Exp", "Agi", "Stam", "H", "Arm" },
        },
    },
    -- PALADIN (1486)
    {
        camelotID = 14861, retailID = 65, classID = 1486, class = "PALADIN", classFile = "PALADIN",
        treeIndex = 1, name = "holy", icon = 135920, role = "HEAL", isTank = false, isHealer = true, isClassic = true,
        retailStats  = { "M", "C", "H", "V" },
        classicStats = { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "H" },
        roleStats = {
            ["HEAL"] = { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "H" },
            ["DPS"]  = { "SP", "Int", "Crit", "Hit", "MP5", "Stam" },
        },
    },
    {
        camelotID = 14862, retailID = 66, classID = 1486, class = "PALADIN", classFile = "PALADIN",
        treeIndex = 2, name = "protection", icon = 236264, role = "TANK", isTank = true, isHealer = false, isClassic = true,
        retailStats  = { "H", "V", "C", "M" },
        classicStats = { "Def", "Stam", "Arm", "BlockVal", "Block", "Dodge", "Parry", "SP", "Hit" },
        roleStats = {
            ["TANK"] = { "Def", "Stam", "Arm", "BlockVal", "Block", "Dodge", "Parry", "SP", "Hit" },
            ["DPS"]  = { "Str", "AP", "Hit", "Crit", "SP" },
        },
    },
    {
        camelotID = 14863, retailID = 70, classID = 1486, class = "PALADIN", classFile = "PALADIN",
        treeIndex = 3, name = "retribution", icon = 135873, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "M", "H", "C", "V" },
        classicStats = { "Str", "AP", "Hit", "Crit", "ArP", "Exp", "Agi", "Stam", "SP", "H" },
        roleStats = {
            ["DPS"]  = { "Str", "AP", "Hit", "Crit", "ArP", "Exp", "Agi", "Stam", "SP", "H" },
            ["HEAL"] = { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "H" },
            ["TANK"] = { "Def", "Stam", "Arm", "BlockVal", "Block", "Dodge", "Parry", "SP", "Hit" },
        },
    },
    -- HUNTER (1485)
    {
        camelotID = 14851, retailID = 253, classID = 1485, class = "HUNTER", classFile = "HUNTER",
        treeIndex = 1, name = "beast mastery", icon = 132222, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "M", "C", "V", "H" },
        classicStats = { "Agi", "RAP", "Hit", "Crit", "ArP", "AP", "Stam", "Int", "H" },
    },
    {
        camelotID = 14852, retailID = 254, classID = 1485, class = "HUNTER", classFile = "HUNTER",
        treeIndex = 2, name = "marksmanship", icon = 132218, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "C", "M", "H", "V" },
        classicStats = { "Agi", "RAP", "Hit", "Crit", "ArP", "AP", "Stam", "Int", "H" },
    },
    {
        camelotID = 14853, retailID = 255, classID = 1485, class = "HUNTER", classFile = "HUNTER",
        treeIndex = 3, name = "survival", icon = 132215, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "M", "C", "H", "V" },
        classicStats = { "Agi", "RAP", "Hit", "Crit", "ArP", "AP", "Stam", "Int", "H" },
    },
    -- ROGUE (1488)
    {
        camelotID = 14881, retailID = 259, classID = 1488, class = "ROGUE", classFile = "ROGUE",
        treeIndex = 1, name = "assassination", icon = 132292, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "C", "H", "M", "V" },
        classicStats = { "Agi", "AP", "Hit", "Crit", "ArP", "Exp", "Str", "Stam", "H", "Arm" },
    },
    {
        camelotID = 14882, retailID = 260, classID = 1488, class = "ROGUE", classFile = "ROGUE",
        treeIndex = 2, name = "combat", icon = 132309, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "H", "C", "V", "M" },
        classicStats = { "Hit", "Exp", "Agi", "AP", "Crit", "ArP", "Str", "Stam", "H", "Arm" },
    },
    {
        camelotID = 14883, retailID = 261, classID = 1488, class = "ROGUE", classFile = "ROGUE",
        treeIndex = 3, name = "subtlety", icon = 132320, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "M", "H", "C", "V" },
        classicStats = { "Agi", "AP", "Crit", "Hit", "ArP", "Exp", "Str", "Stam", "H", "Arm" },
    },
    -- PRIEST (1487)
    {
        camelotID = 14871, retailID = 256, classID = 1487, class = "PRIEST", classFile = "PRIEST",
        treeIndex = 1, name = "discipline", icon = 135940, role = "HEAL", isTank = false, isHealer = true, isClassic = true,
        retailStats  = { "H", "C", "V", "M" },
        classicStats = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Hit", "Stam" },
        roleStats = {
            ["HEAL"] = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Hit", "Stam" },
            ["DPS"]  = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam" },
        },
    },
    {
        camelotID = 14872, retailID = 257, classID = 1487, class = "PRIEST", classFile = "PRIEST",
        treeIndex = 2, name = "holy", icon = 237542, role = "HEAL", isTank = false, isHealer = true, isClassic = true,
        retailStats  = { "V", "C", "H", "M" },
        classicStats = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Hit", "Stam" },
        roleStats = {
            ["HEAL"] = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Hit", "Stam" },
            ["DPS"]  = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam" },
        },
    },
    {
        camelotID = 14873, retailID = 258, classID = 1487, class = "PRIEST", classFile = "PRIEST",
        treeIndex = 3, name = "shadow", icon = 136207, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "H", "M", "C", "V" },
        classicStats = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
        roleStats = {
            ["DPS"]  = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
            ["HEAL"] = { "Heal", "SP", "MP5", "Spi", "Int", "Crit" },
        },
    },
    -- SHAMAN (1489)
    {
        camelotID = 14891, retailID = 262, classID = 1489, class = "SHAMAN", classFile = "SHAMAN",
        treeIndex = 1, name = "elemental", icon = 136048, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "H", "M", "C", "V" },
        classicStats = { "SP", "Hit", "Crit", "Int", "MP5", "Spi", "Stam", "H" },
        roleStats = {
            ["DPS"]  = { "SP", "Hit", "Crit", "Int", "MP5", "Spi", "Stam", "H" },
            ["HEAL"] = { "Heal", "SP", "MP5", "Int", "Crit" },
        },
    },
    {
        camelotID = 14892, retailID = 263, classID = 1489, class = "SHAMAN", classFile = "SHAMAN",
        treeIndex = 2, name = "enhancement", icon = 136051, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "M", "H", "C", "V" },
        classicStats = { "AP", "Str", "Agi", "Hit", "Crit", "SP", "Int", "Stam" },
        roleStats = {
            ["DPS"]  = { "AP", "Str", "Agi", "Hit", "Crit", "SP", "Int", "Stam" },
            ["HEAL"] = { "Heal", "SP", "MP5", "Int" },
        },
    },
    {
        camelotID = 14893, retailID = 264, classID = 1489, class = "SHAMAN", classFile = "SHAMAN",
        treeIndex = 3, name = "restoration", icon = 136052, role = "HEAL", isTank = false, isHealer = true, isClassic = true,
        retailStats  = { "C", "V", "M", "H" },
        classicStats = { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "H" },
        roleStats = {
            ["HEAL"] = { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "H" },
            ["DPS"]  = { "SP", "Hit", "Crit", "MP5", "AP" },
        },
    },
    -- MAGE (1482)
    {
        camelotID = 14821, retailID = 62, classID = 1482, class = "MAGE", classFile = "MAGE",
        treeIndex = 1, name = "arcane", icon = 135932, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "M", "H", "C", "V" },
        classicStats = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
    },
    {
        camelotID = 14822, retailID = 63, classID = 1482, class = "MAGE", classFile = "MAGE",
        treeIndex = 2, name = "fire", icon = 135810, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "H", "M", "V", "C" },
        classicStats = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
    },
    {
        camelotID = 14823, retailID = 64, classID = 1482, class = "MAGE", classFile = "MAGE",
        treeIndex = 3, name = "frost", icon = 135846, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "M", "C", "H", "V" },
        classicStats = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
    },
    -- WARLOCK (1490)
    {
        camelotID = 14901, retailID = 265, classID = 1490, class = "WARLOCK", classFile = "WARLOCK",
        treeIndex = 1, name = "affliction", icon = 136145, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "M", "C", "H", "V" },
        classicStats = { "SP", "Hit", "Crit", "Stam", "Int", "Spi", "H", "Arm" },
    },
    {
        camelotID = 14902, retailID = 266, classID = 1490, class = "WARLOCK", classFile = "WARLOCK",
        treeIndex = 2, name = "demonology", icon = 136172, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "H", "C", "M", "V" },
        classicStats = { "SP", "Hit", "Crit", "Stam", "Int", "Spi", "H", "Arm" },
    },
    {
        camelotID = 14903, retailID = 267, classID = 1490, class = "WARLOCK", classFile = "WARLOCK",
        treeIndex = 3, name = "destruction", icon = 136186, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "H", "M", "C", "V" },
        classicStats = { "SP", "Hit", "Crit", "Int", "Stam", "Spi", "H", "Arm" },
    },
    -- DRUID (1484)
    {
        camelotID = 14841, retailID = 102, classID = 1484, class = "DRUID", classFile = "DRUID",
        treeIndex = 1, name = "balance", icon = 136096, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "M", "H", "C", "V" },
        classicStats = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
        roleStats = {
            ["DPS"]  = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
            ["HEAL"] = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Stam", "H" },
        },
    },
    {
        camelotID = 14842, retailID = 103, classID = 1484, class = "DRUID", classFile = "DRUID",
        treeIndex = 2, name = "feral", icon = 132242, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "M", "H", "C", "V" },
        classicStats = { "Str", "Agi", "AP", "Crit", "Hit", "ArP", "Exp", "Stam", "Int", "Arm" },
        roleStats = {
            ["DPS"]  = { "Str", "Agi", "AP", "Crit", "Hit", "ArP", "Exp", "Stam", "Int", "Arm" },
            ["TANK"] = { "Arm", "Stam", "Def", "Dodge", "Agi", "Str", "Hit", "AP" },
        },
    },
    {
        camelotID = 14843, retailID = 105, classID = 1484, class = "DRUID", classFile = "DRUID",
        treeIndex = 3, name = "restoration", icon = 136041, role = "HEAL", isTank = false, isHealer = true, isClassic = true,
        retailStats  = { "H", "M", "V", "C" },
        classicStats = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Stam", "H" },
        roleStats = {
            ["HEAL"] = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Stam", "H" },
            ["DPS"]  = { "SP", "Int", "Crit", "Hit", "Str", "Agi" },
        },
    },
    -- RETAIL ONLY CLASSES / SPECS
    {
        retailID = 250, classID = 6, class = "DEATHKNIGHT", classFile = "DEATHKNIGHT",
        name = "blood", role = "TANK", isTank = true, isHealer = false, isClassic = false,
        retailStats = { "H", "C", "M", "V" },
    },
    {
        retailID = 251, classID = 6, class = "DEATHKNIGHT", classFile = "DEATHKNIGHT",
        name = "frost", role = "DPS", isTank = false, isHealer = false, isClassic = false,
        retailStats = { "M", "C", "H", "V" },
    },
    {
        retailID = 252, classID = 6, class = "DEATHKNIGHT", classFile = "DEATHKNIGHT",
        name = "unholy", role = "DPS", isTank = false, isHealer = false, isClassic = false,
        retailStats = { "M", "C", "H", "V" },
    },
    {
        retailID = 577, classID = 12, class = "DEMONHUNTER", classFile = "DEMONHUNTER",
        name = "havoc", role = "DPS", isTank = false, isHealer = false, isClassic = false,
        retailStats = { "C", "M", "H", "V" },
    },
    {
        retailID = 581, classID = 12, class = "DEMONHUNTER", classFile = "DEMONHUNTER",
        name = "vengeance", role = "TANK", isTank = true, isHealer = false, isClassic = false,
        retailStats = { "H", "C", "V", "M" },
    },
    {
        retailID = 1480, classID = 12, class = "DEMONHUNTER", classFile = "DEMONHUNTER",
        name = "devourer", role = "DPS", isTank = false, isHealer = false, isClassic = false,
        retailStats = { "H", "M", "C", "V" },
    },
    {
        retailID = 104, classID = 11, class = "DRUID", classFile = "DRUID",
        name = "guardian", role = "TANK", isTank = true, isHealer = false, isClassic = false,
        retailStats = { "H", "V", "C", "M" },
        classicStats = { "Arm", "Stam", "Def", "Dodge", "Agi", "Str", "Hit", "AP" },
        roleStats = {
            ["TANK"] = { "Arm", "Stam", "Def", "Dodge", "Agi", "Str", "Hit", "AP" },
        },
    },
    {
        retailID = 1467, classID = 13, class = "EVOKER", classFile = "EVOKER",
        name = "devastation", role = "DPS", isTank = false, isHealer = false, isClassic = false,
        retailStats = { "C", "H", "M", "V" },
    },
    {
        retailID = 1468, classID = 13, class = "EVOKER", classFile = "EVOKER",
        name = "preservation", role = "HEAL", isTank = false, isHealer = true, isClassic = false,
        retailStats = { "M", "H", "C", "V" },
    },
    {
        retailID = 1473, classID = 13, class = "EVOKER", classFile = "EVOKER",
        name = "augmentation", role = "DPS", isTank = false, isHealer = false, isClassic = false,
        retailStats = { "C", "H", "M", "V" },
    },
    {
        retailID = 268, classID = 10, class = "MONK", classFile = "MONK",
        name = "brewmaster", role = "TANK", isTank = true, isHealer = false, isClassic = false,
        retailStats = { "C", "M", "V", "H" },
    },
    {
        retailID = 269, classID = 10, class = "MONK", classFile = "MONK",
        name = "windwalker", role = "DPS", isTank = false, isHealer = false, isClassic = false,
        retailStats = { "H", "C", "M", "V" },
    },
    {
        retailID = 270, classID = 10, class = "MONK", classFile = "MONK",
        name = "mistweaver", role = "HEAL", isTank = false, isHealer = true, isClassic = false,
        retailStats = { "H", "C", "V", "M" },
    },
}

sfui.data.BASE_CLASS_DEFINITIONS = {
    [1491] = {
        classID = 1491, class = "WARRIOR", classFile = "WARRIOR", name = "warrior", role = "DPS", isTank = false, isHealer = false, isClassic = true,
        classicStats = { "Str", "AP", "Hit", "Crit", "ArP", "Exp", "Agi", "Stam", "H", "Arm" },
        roleStats = {
            ["DPS"]  = { "Str", "AP", "Hit", "Crit", "ArP", "Exp", "Agi", "Stam", "H", "Arm" },
            ["TANK"] = { "Def", "Stam", "Arm", "BlockVal", "Block", "Dodge", "Parry", "Hit", "Str" },
        },
    },
    [1486] = {
        classID = 1486, class = "PALADIN", classFile = "PALADIN", name = "paladin", role = "DPS", isTank = false, isHealer = false, isClassic = true,
        classicStats = { "Str", "AP", "Hit", "Crit", "Stam", "SP", "Heal", "MP5", "Int" },
        roleStats = {
            ["DPS"]  = { "Str", "AP", "Hit", "Crit", "ArP", "Exp", "Agi", "Stam", "SP", "H" },
            ["HEAL"] = { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "H" },
            ["TANK"] = { "Def", "Stam", "Arm", "BlockVal", "Block", "Dodge", "Parry", "SP", "Hit" },
        },
    },
    [1485] = {
        classID = 1485, class = "HUNTER", classFile = "HUNTER", name = "hunter", role = "DPS", isTank = false, isHealer = false, isClassic = true,
        classicStats = { "Agi", "RAP", "Hit", "Crit", "ArP", "AP", "Stam", "Int", "H" },
        roleStats = {
            ["DPS"]  = { "Agi", "RAP", "Hit", "Crit", "ArP", "AP", "Stam", "Int", "H" },
        },
    },
    [1488] = {
        classID = 1488, class = "ROGUE", classFile = "ROGUE", name = "rogue", role = "DPS", isTank = false, isHealer = false, isClassic = true,
        classicStats = { "Agi", "AP", "Hit", "Crit", "ArP", "Exp", "Str", "Stam", "H", "Arm" },
        roleStats = {
            ["DPS"]  = { "Agi", "AP", "Hit", "Crit", "ArP", "Exp", "Str", "Stam", "H", "Arm" },
        },
    },
    [1487] = {
        classID = 1487, class = "PRIEST", classFile = "PRIEST", name = "priest", role = "HEAL", isTank = false, isHealer = true, isClassic = true,
        classicStats = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Hit", "Stam" },
        roleStats = {
            ["HEAL"] = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Hit", "Stam" },
            ["DPS"]  = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
        },
    },
    [1489] = {
        classID = 1489, class = "SHAMAN", classFile = "SHAMAN", name = "shaman", role = "DPS", isTank = false, isHealer = false, isClassic = true,
        classicStats = { "SP", "Heal", "Hit", "Crit", "MP5", "AP", "Str", "Agi" },
        roleStats = {
            ["DPS"]  = { "SP", "Hit", "Crit", "MP5", "AP", "Str", "Agi", "Int" },
            ["HEAL"] = { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "H" },
        },
    },
    [1482] = {
        classID = 1482, class = "MAGE", classFile = "MAGE", name = "mage", role = "DPS", isTank = false, isHealer = false, isClassic = true,
        classicStats = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
        roleStats = {
            ["DPS"]  = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
        },
    },
    [1490] = {
        classID = 1490, class = "WARLOCK", classFile = "WARLOCK", name = "warlock", role = "DPS", isTank = false, isHealer = false, isClassic = true,
        classicStats = { "SP", "Hit", "Crit", "Stam", "Int", "Spi", "H", "Arm" },
        roleStats = {
            ["DPS"]  = { "SP", "Hit", "Crit", "Stam", "Int", "Spi", "H", "Arm" },
        },
    },
    [1484] = {
        classID = 1484, class = "DRUID", classFile = "DRUID", name = "druid", role = "DPS", isTank = false, isHealer = false, isClassic = true,
        classicStats = { "Str", "Agi", "AP", "Crit", "Hit", "ArP", "Exp", "Stam", "Int", "Arm" },
        roleStats = {
            ["DPS"]  = { "Str", "Agi", "AP", "Crit", "Hit", "ArP", "Exp", "Stam", "Int", "Arm" },
            ["HEAL"] = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Stam", "H" },
            ["TANK"] = { "Arm", "Stam", "Def", "Dodge", "Agi", "Str", "Hit", "AP" },
        },
    },
}

-- ══════════════════════════════════════════════════════════════════════════════
-- Stat Token to GlobalString Key Mappings
-- ══════════════════════════════════════════════════════════════════════════════

sfui.data.STAT_KEYS = {
    -- Retail
    ["Crit"]        = "ITEM_MOD_CRIT_RATING_SHORT",
    ["C"]           = "ITEM_MOD_CRIT_RATING_SHORT",
    ["Haste"]       = "ITEM_MOD_HASTE_RATING_SHORT",
    ["H"]           = "ITEM_MOD_HASTE_RATING_SHORT",
    ["Mastery"]     = "ITEM_MOD_MASTERY_RATING_SHORT",
    ["M"]           = "ITEM_MOD_MASTERY_RATING_SHORT",
    ["Versatility"] = "ITEM_MOD_VERSATILITY",
    ["V"]           = "ITEM_MOD_VERSATILITY",
    -- Classic / General
    ["SP"]          = "ITEM_MOD_SPELL_POWER_SHORT",
    ["SpellPower"]  = "ITEM_MOD_SPELL_POWER_SHORT",
    ["Heal"]        = "ITEM_MOD_SPELL_HEALING_DONE_SHORT",
    ["Healing"]     = "ITEM_MOD_SPELL_HEALING_DONE_SHORT",
    ["Hit"]         = "ITEM_MOD_HIT_RATING_SHORT",
    ["AP"]          = "ITEM_MOD_ATTACK_POWER_SHORT",
    ["AttackPower"] = "ITEM_MOD_ATTACK_POWER_SHORT",
    ["RAP"]         = "ITEM_MOD_RANGED_ATTACK_POWER_SHORT",
    ["RangedAP"]    = "ITEM_MOD_RANGED_ATTACK_POWER_SHORT",
    ["MP5"]         = "ITEM_MOD_MANA_REGENERATION_SHORT",
    ["ManaRegen"]   = "ITEM_MOD_MANA_REGENERATION_SHORT",
    ["Str"]         = "ITEM_MOD_STRENGTH_SHORT",
    ["Strength"]    = "ITEM_MOD_STRENGTH_SHORT",
    ["Agi"]         = "ITEM_MOD_AGILITY_SHORT",
    ["Agility"]     = "ITEM_MOD_AGILITY_SHORT",
    ["Int"]         = "ITEM_MOD_INTELLECT_SHORT",
    ["Intellect"]   = "ITEM_MOD_INTELLECT_SHORT",
    ["Spi"]         = "ITEM_MOD_SPIRIT_SHORT",
    ["Spirit"]      = "ITEM_MOD_SPIRIT_SHORT",
    ["Stam"]        = "ITEM_MOD_STAMINA_SHORT",
    ["Stamina"]     = "ITEM_MOD_STAMINA_SHORT",
    -- Tank Only
    ["Def"]         = "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT",
    ["Defense"]     = "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT",
    ["Dodge"]       = "ITEM_MOD_DODGE_RATING_SHORT",
    ["Parry"]       = "ITEM_MOD_PARRY_RATING_SHORT",
    ["Block"]       = "ITEM_MOD_BLOCK_RATING_SHORT",
    ["Arm"]         = "ITEM_MOD_ARMOR_SHORT",
    ["Armor"]       = "ITEM_MOD_ARMOR_SHORT",
    -- Camelot / Modernized Secondary Stats
    ["ArP"]              = "ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT",
    ["ArmorPenetration"] = "ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT",
    ["Exp"]              = "ITEM_MOD_EXPERTISE_RATING_SHORT",
    ["Expertise"]        = "ITEM_MOD_EXPERTISE_RATING_SHORT",
    ["BlockVal"]         = "ITEM_MOD_BLOCK_VALUE_SHORT",
    ["BlockValue"]       = "ITEM_MOD_BLOCK_VALUE_SHORT",
}

-- Aliases for convenience
sfui.spec_definitions       = sfui.data.SPEC_DEFINITIONS
sfui.base_class_definitions = sfui.data.BASE_CLASS_DEFINITIONS
sfui.stat_keys              = sfui.data.STAT_KEYS

-- ══════════════════════════════════════════════════════════════════════════════
-- Camelot / Classic Secondary Stat Formulas & Calculations
-- Authoritatively grounded in Blizzard_UIPanels_Game/Camelot/PaperDollFrameStats.lua
-- ══════════════════════════════════════════════════════════════════════════════

sfui.stats = sfui.stats or {}

local math_max = math.max
local math_min = math.min
local InCombatLockdown = _G.InCombatLockdown

--- Returns effective defense skill and breakdown (effective, base, modifier, maxDefense, excess)
function sfui.stats.GetEffectiveDefense(unit)
    unit = unit or "player"
    local lvl = (_G.UnitLevel and _G.UnitLevel(unit)) or 60
    local maxDef = lvl * 5
    if InCombatLockdown and InCombatLockdown() then
        return maxDef, maxDef, 0, maxDef, 0
    end
    if not _G.UnitDefenseSkill then return 0, 0, 0, 0, 0 end
    local base, mod = _G.UnitDefenseSkill(unit)
    base = base or 0
    mod = mod or 0
    local effective = math_max(0, base + mod)
    local excess = math_max(0, effective - maxDef)
    return effective, base, mod, maxDef, excess
end

--- Computes enemy combat table chances against the player based on level offset (e.g. 3 for boss)
--- and player's defense skill. Also provides glancing blow damage penalties.
function sfui.stats.GetEnemyCombatTable(levelOffset, defenseSkill)
    local playerLevel = (_G.UnitLevel and _G.UnitLevel("player")) or 60
    levelOffset = levelOffset or 3
    if not defenseSkill then
        local eff = sfui.stats.GetEffectiveDefense("player")
        defenseSkill = eff
    end
    local enemyWeaponSkill = (playerLevel + levelOffset) * 5
    local skillDiff = enemyWeaponSkill - defenseSkill
    local missChance = math_max(0.0, math_min(100.0, 5.0 - (skillDiff * 0.04)))
    local critChance = math_max(0.0, math_min(100.0, 5.0 + (skillDiff * 0.04)))
    local crushingChance = 0.0
    local crushingSkillDiff = enemyWeaponSkill - math_min(defenseSkill, playerLevel * 5)
    if crushingSkillDiff >= 15 then
        crushingChance = math_max(0.0, math_min(100.0, (crushingSkillDiff * 2.0) - 15.0))
    end
    -- Glancing blow damage penalty for melee attacks against higher level targets:
    -- Low penalty: low = 1.30 - 0.05 * skillDiff, capped between 0.01 and 1.2
    -- High penalty: high = 1.20 - 0.03 * skillDiff, capped at 0.99
    local glancingLow = math_max(0.01, math_min(1.2, 1.30 - (skillDiff * 0.05)))
    local glancingHigh = math_max(0.01, math_min(0.99, 1.20 - (skillDiff * 0.03)))

    return {
        enemyWeaponSkill = enemyWeaponSkill,
        skillDiff = skillDiff,
        missChance = missChance,
        critChance = critChance,
        crushingChance = crushingChance,
        glancingLow = glancingLow,
        glancingHigh = glancingHigh,
    }
end

--- Calculates Hit Chance across Melee, Ranged, and Spell
function sfui.stats.GetHitChance(unit)
    unit = unit or "player"
    local meleeHit, rangedHit, spellHit = 0, 0, 0
    if unit == "player" then
        local crMelee = (_G.GetCombatRatingBonus and _G.CR_HIT_MELEE and _G.GetCombatRatingBonus(_G.CR_HIT_MELEE)) or 0
        local modHit = (_G.GetHitModifier and _G.GetHitModifier()) or 0
        meleeHit = crMelee + modHit

        local crRanged = (_G.GetCombatRatingBonus and _G.CR_HIT_RANGED and _G.GetCombatRatingBonus(_G.CR_HIT_RANGED)) or 0
        local modRanged = (_G.GetRangedHitModifier and _G.GetRangedHitModifier()) or 0
        rangedHit = crRanged + modRanged

        local crSpell = (_G.GetCombatRatingBonus and _G.CR_HIT_SPELL and _G.GetCombatRatingBonus(_G.CR_HIT_SPELL)) or 0
        local modSpell = (_G.GetSpellHitModifier and _G.GetSpellHitModifier()) or 0
        spellHit = crSpell + modSpell
    elseif unit == "pet" then
        meleeHit = (_G.GetPetHitChanceModifier and _G.GetPetHitChanceModifier()) or 0
        rangedHit = meleeHit
        spellHit = (_G.GetPetSpellHitChanceModifier and _G.GetPetSpellHitChanceModifier()) or 0
    end
    local maxHit = math_max(meleeHit, rangedHit, spellHit)
    return maxHit, meleeHit, rangedHit, spellHit
end

--- Calculates Critical Strike Chance across Melee, Ranged, and Spell
function sfui.stats.GetCritChance(unit)
    unit = unit or "player"
    local meleeCrit = (_G.GetCritChance and _G.GetCritChance()) or 0
    local rangedCrit = (_G.GetRangedCritChance and _G.GetRangedCritChance()) or 0
    local spellCrit = (_G.GetSpellCritChance and _G.GetSpellCritChance()) or 0
    local maxCrit = math_max(meleeCrit, rangedCrit, spellCrit)
    return maxCrit, meleeCrit, rangedCrit, spellCrit
end

--- Calculates Haste percentage across Melee, Ranged, and Spell
function sfui.stats.GetHaste(unit)
    unit = unit or "player"
    local meleeHaste = 0
    local rangedHaste = 0
    local spellHaste = (_G.UnitSpellHaste and _G.UnitSpellHaste(unit)) or 0
    if unit == "player" then
        meleeHaste = (_G.GetMeleeHaste and _G.GetMeleeHaste()) or 0
        if _G.GetRangedHaste then
            local baseRanged, ammoHaste = _G.GetRangedHaste()
            local usesAmmo = sfui.api.UnitUsesAmmo and sfui.api.UnitUsesAmmo(unit)
            rangedHaste = (baseRanged or 0) + ((usesAmmo and ammoHaste) or ammoHaste or 0)
        end
    elseif unit == "pet" then
        meleeHaste = (_G.GetPetMeleeHaste and _G.GetPetMeleeHaste()) or 0
    end
    local maxHaste = math_max(meleeHaste, rangedHaste, spellHaste)
    return maxHaste, meleeHaste, rangedHaste, spellHaste
end

--- Returns Armor Penetration
function sfui.stats.GetArmorPenetration(unit)
    if unit and unit ~= "player" then return 0 end
    return (_G.GetArmorPenetration and _G.GetArmorPenetration()) or 0
end

--- Returns Expertise breakdown (maxExpertise, mainHand, offHand, ranged)
function sfui.stats.GetExpertise(unit)
    if (unit and unit ~= "player") or not _G.GetExpertise then return 0, 0, 0, 0 end
    local exp, ohExp, rangedExp = _G.GetExpertise()
    exp = exp or 0
    ohExp = ohExp or 0
    rangedExp = rangedExp or 0
    local maxExp = math_max(exp, ohExp, rangedExp)
    return maxExp, exp, ohExp, rangedExp
end

--- Returns Shield Block chance and Block value
function sfui.stats.GetBlockInfo(unit)
    if unit and unit ~= "player" then return 0, 0 end
    local chance = (_G.GetBlockChance and _G.GetBlockChance()) or 0
    local val = (_G.GetShieldBlock and _G.GetShieldBlock()) or 0
    return chance, val
end
