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
        classicStats = { "Str", "AP", "Hit", "Crit", "Agi", "Stam", "H", "Arm" },
        roleStats = {
            ["arms"] = { "Str", "AP", "Hit", "Crit", "Agi", "Stam", "H", "Arm" },
            ["fury"] = { "AP", "Hit", "Crit", "Str", "Agi", "Stam", "H", "Arm" },
            ["prot"] = { "Def", "Stam", "Arm", "BlockVal", "Block", "Dodge", "Parry", "Hit", "Str" },
            ["DPS"]  = { "Str", "AP", "Hit", "Crit", "Agi", "Stam", "H", "Arm" },
            ["TANK"] = { "Def", "Stam", "Arm", "BlockVal", "Block", "Dodge", "Parry", "Hit" },
        },
    },
    {
        camelotID = 14912, retailID = 72, classID = 1491, class = "WARRIOR", classFile = "WARRIOR",
        treeIndex = 2, name = "fury", icon = 132347, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "M", "H", "C", "V" },
        classicStats = { "AP", "Hit", "Crit", "Str", "Agi", "Stam", "H", "Arm" },
        roleStats = {
            ["fury"] = { "AP", "Hit", "Crit", "Str", "Agi", "Stam", "H", "Arm" },
            ["arms"] = { "Str", "AP", "Hit", "Crit", "Agi", "Stam", "H", "Arm" },
            ["prot"] = { "Def", "Stam", "Arm", "BlockVal", "Block", "Dodge", "Parry", "Hit", "Str" },
            ["DPS"]  = { "AP", "Hit", "Crit", "Str", "Agi", "Stam", "H", "Arm" },
            ["TANK"] = { "Def", "Stam", "Arm", "BlockVal", "Block", "Dodge", "Parry", "Hit" },
        },
    },
    {
        camelotID = 14913, retailID = 73, classID = 1491, class = "WARRIOR", classFile = "WARRIOR",
        treeIndex = 3, name = "protection", icon = 132341, role = "TANK", isTank = true, isHealer = false, isClassic = true,
        retailStats  = { "H", "C", "V", "M" },
        classicStats = { "Def", "Stam", "Arm", "BlockVal", "Block", "Dodge", "Parry", "Hit", "Str" },
        roleStats = {
            ["prot"] = { "Def", "Stam", "Arm", "BlockVal", "Block", "Dodge", "Parry", "Hit", "Str" },
            ["arms"] = { "Str", "AP", "Hit", "Crit", "Agi", "Stam", "H", "Arm" },
            ["fury"] = { "AP", "Hit", "Crit", "Str", "Agi", "Stam", "H", "Arm" },
            ["TANK"] = { "Def", "Stam", "Arm", "BlockVal", "Block", "Dodge", "Parry", "Hit", "Str" },
            ["DPS"]  = { "Str", "AP", "Hit", "Crit", "Agi", "Stam", "H", "Arm" },
        },
    },
    -- PALADIN (1486)
    {
        camelotID = 14861, retailID = 65, classID = 1486, class = "PALADIN", classFile = "PALADIN",
        treeIndex = 1, name = "holy", icon = 135920, role = "HEAL", isTank = false, isHealer = true, isClassic = true,
        retailStats  = { "M", "C", "H", "V" },
        classicStats = { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "H" },
        roleStats = {
            ["holy"] = { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "H" },
            ["prot"] = { "Def", "Stam", "Arm", "BlockVal", "Block", "Dodge", "Parry", "SP", "Hit" },
            ["ret"]  = { "Str", "AP", "Hit", "Crit", "Agi", "Stam", "SP", "H" },
            ["HEAL"] = { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "H" },
            ["DPS"]  = { "SP", "Int", "Crit", "Hit", "MP5", "Stam" },
            ["TANK"] = { "Def", "Stam", "Arm", "BlockVal", "Block", "Dodge", "Parry", "SP", "Hit" },
        },
    },
    {
        camelotID = 14862, retailID = 66, classID = 1486, class = "PALADIN", classFile = "PALADIN",
        treeIndex = 2, name = "protection", icon = 236264, role = "TANK", isTank = true, isHealer = false, isClassic = true,
        retailStats  = { "H", "V", "C", "M" },
        classicStats = { "Def", "Stam", "Arm", "BlockVal", "Block", "Dodge", "Parry", "SP", "Hit" },
        roleStats = {
            ["prot"] = { "Def", "Stam", "Arm", "BlockVal", "Block", "Dodge", "Parry", "SP", "Hit" },
            ["ret"]  = { "Str", "AP", "Hit", "Crit", "Agi", "Stam", "SP", "H" },
            ["holy"] = { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "H" },
            ["TANK"] = { "Def", "Stam", "Arm", "BlockVal", "Block", "Dodge", "Parry", "SP", "Hit" },
            ["DPS"]  = { "Str", "AP", "Hit", "Crit", "SP" },
            ["HEAL"] = { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "H" },
        },
    },
    {
        camelotID = 14863, retailID = 70, classID = 1486, class = "PALADIN", classFile = "PALADIN",
        treeIndex = 3, name = "retribution", icon = 135873, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "M", "H", "C", "V" },
        classicStats = { "Str", "AP", "Hit", "Crit", "Agi", "Stam", "SP", "H" },
        roleStats = {
            ["ret"]  = { "Str", "AP", "Hit", "Crit", "Agi", "Stam", "SP", "H" },
            ["prot"] = { "Def", "Stam", "Arm", "BlockVal", "Block", "Dodge", "Parry", "SP", "Hit" },
            ["holy"] = { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "H" },
            ["DPS"]  = { "Str", "AP", "Hit", "Crit", "Agi", "Stam", "SP", "H" },
            ["HEAL"] = { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "H" },
            ["TANK"] = { "Def", "Stam", "Arm", "BlockVal", "Block", "Dodge", "Parry", "SP", "Hit" },
        },
    },
    -- HUNTER (1485)
    {
        camelotID = 14851, retailID = 253, classID = 1485, class = "HUNTER", classFile = "HUNTER",
        treeIndex = 1, name = "beast mastery", icon = 132222, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "M", "C", "V", "H" },
        classicStats = { "Agi", "RAP", "Hit", "Crit", "AP", "Stam", "Int", "H" },
        roleStats = {
            ["bm"]   = { "Agi", "RAP", "Hit", "Crit", "AP", "Stam", "Int", "H" },
            ["mm"]   = { "Agi", "RAP", "Hit", "Crit", "AP", "Stam", "Int", "H" },
            ["surv"] = { "Agi", "RAP", "Hit", "Crit", "AP", "Stam", "Int", "H" },
            ["DPS"]  = { "Agi", "RAP", "Hit", "Crit", "AP", "Stam", "Int", "H" },
        },
    },
    {
        camelotID = 14852, retailID = 254, classID = 1485, class = "HUNTER", classFile = "HUNTER",
        treeIndex = 2, name = "marksmanship", icon = 132218, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "C", "M", "H", "V" },
        classicStats = { "Agi", "RAP", "Hit", "Crit", "AP", "Stam", "Int", "H" },
        roleStats = {
            ["mm"]   = { "Agi", "RAP", "Hit", "Crit", "AP", "Stam", "Int", "H" },
            ["bm"]   = { "Agi", "RAP", "Hit", "Crit", "AP", "Stam", "Int", "H" },
            ["surv"] = { "Agi", "RAP", "Hit", "Crit", "AP", "Stam", "Int", "H" },
            ["DPS"]  = { "Agi", "RAP", "Hit", "Crit", "AP", "Stam", "Int", "H" },
        },
    },
    {
        camelotID = 14853, retailID = 255, classID = 1485, class = "HUNTER", classFile = "HUNTER",
        treeIndex = 3, name = "survival", icon = 132215, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "M", "C", "H", "V" },
        classicStats = { "Agi", "RAP", "Hit", "Crit", "AP", "Stam", "Int", "H" },
        roleStats = {
            ["surv"] = { "Agi", "RAP", "Hit", "Crit", "AP", "Stam", "Int", "H" },
            ["bm"]   = { "Agi", "RAP", "Hit", "Crit", "AP", "Stam", "Int", "H" },
            ["mm"]   = { "Agi", "RAP", "Hit", "Crit", "AP", "Stam", "Int", "H" },
            ["DPS"]  = { "Agi", "RAP", "Hit", "Crit", "AP", "Stam", "Int", "H" },
        },
    },
    -- ROGUE (1488)
    {
        camelotID = 14881, retailID = 259, classID = 1488, class = "ROGUE", classFile = "ROGUE",
        treeIndex = 1, name = "assassination", icon = 132292, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "C", "H", "M", "V" },
        classicStats = { "Agi", "AP", "Hit", "Crit", "Str", "Stam", "H", "Arm" },
        roleStats = {
            ["sin"]    = { "Agi", "AP", "Hit", "Crit", "Str", "Stam", "H", "Arm" },
            ["combat"] = { "Hit", "Agi", "AP", "Crit", "Str", "Stam", "H", "Arm" },
            ["sub"]    = { "Agi", "AP", "Crit", "Hit", "Str", "Stam", "H", "Arm" },
            ["DPS"]    = { "Agi", "AP", "Hit", "Crit", "Str", "Stam", "H", "Arm" },
        },
    },
    {
        camelotID = 14882, retailID = 260, classID = 1488, class = "ROGUE", classFile = "ROGUE",
        treeIndex = 2, name = "combat", icon = 132309, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "H", "C", "V", "M" },
        classicStats = { "Hit", "Agi", "AP", "Crit", "Str", "Stam", "H", "Arm" },
        roleStats = {
            ["combat"] = { "Hit", "Agi", "AP", "Crit", "Str", "Stam", "H", "Arm" },
            ["sin"]    = { "Agi", "AP", "Hit", "Crit", "Str", "Stam", "H", "Arm" },
            ["sub"]    = { "Agi", "AP", "Crit", "Hit", "Str", "Stam", "H", "Arm" },
            ["DPS"]    = { "Hit", "Agi", "AP", "Crit", "Str", "Stam", "H", "Arm" },
        },
    },
    {
        camelotID = 14883, retailID = 261, classID = 1488, class = "ROGUE", classFile = "ROGUE",
        treeIndex = 3, name = "subtlety", icon = 132320, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "M", "H", "C", "V" },
        classicStats = { "Agi", "AP", "Crit", "Hit", "Str", "Stam", "H", "Arm" },
        roleStats = {
            ["sub"]    = { "Agi", "AP", "Crit", "Hit", "Str", "Stam", "H", "Arm" },
            ["sin"]    = { "Agi", "AP", "Hit", "Crit", "Str", "Stam", "H", "Arm" },
            ["combat"] = { "Hit", "Agi", "AP", "Crit", "Str", "Stam", "H", "Arm" },
            ["DPS"]    = { "Agi", "AP", "Crit", "Hit", "Str", "Stam", "H", "Arm" },
        },
    },
    -- PRIEST (1487)
    {
        camelotID = 14871, retailID = 256, classID = 1487, class = "PRIEST", classFile = "PRIEST",
        treeIndex = 1, name = "discipline", icon = 135940, role = "HEAL", isTank = false, isHealer = true, isClassic = true,
        retailStats  = { "H", "C", "V", "M" },
        classicStats = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Hit", "Stam" },
        roleStats = {
            ["disc"] = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Hit", "Stam" },
            ["holy"] = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Hit", "Stam" },
            ["shad"] = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
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
            ["holy"] = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Hit", "Stam" },
            ["disc"] = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Hit", "Stam" },
            ["shad"] = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
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
            ["shad"] = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
            ["holy"] = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Hit", "Stam" },
            ["disc"] = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Hit", "Stam" },
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
            ["ele"]   = { "SP", "Hit", "Crit", "Int", "MP5", "Spi", "Stam", "H" },
            ["enh"]   = { "AP", "Str", "Agi", "Hit", "Crit", "SP", "Int", "Stam" },
            ["resto"] = { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "H" },
            ["DPS"]   = { "SP", "Hit", "Crit", "Int", "MP5", "Spi", "Stam", "H" },
            ["HEAL"]  = { "Heal", "SP", "MP5", "Int", "Crit" },
        },
    },
    {
        camelotID = 14892, retailID = 263, classID = 1489, class = "SHAMAN", classFile = "SHAMAN",
        treeIndex = 2, name = "enhancement", icon = 136051, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "M", "H", "C", "V" },
        classicStats = { "AP", "Str", "Agi", "Hit", "Crit", "SP", "Int", "Stam" },
        roleStats = {
            ["enh"]   = { "AP", "Str", "Agi", "Hit", "Crit", "SP", "Int", "Stam" },
            ["ele"]   = { "SP", "Hit", "Crit", "Int", "MP5", "Spi", "Stam", "H" },
            ["resto"] = { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "H" },
            ["DPS"]   = { "AP", "Str", "Agi", "Hit", "Crit", "SP", "Int", "Stam" },
            ["HEAL"]  = { "Heal", "SP", "MP5", "Int" },
        },
    },
    {
        camelotID = 14893, retailID = 264, classID = 1489, class = "SHAMAN", classFile = "SHAMAN",
        treeIndex = 3, name = "restoration", icon = 136052, role = "HEAL", isTank = false, isHealer = true, isClassic = true,
        retailStats  = { "C", "V", "M", "H" },
        classicStats = { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "H" },
        roleStats = {
            ["resto"] = { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "H" },
            ["ele"]   = { "SP", "Hit", "Crit", "Int", "MP5", "Spi", "Stam", "H" },
            ["enh"]   = { "AP", "Str", "Agi", "Hit", "Crit", "SP", "Int", "Stam" },
            ["HEAL"]  = { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "H" },
            ["DPS"]   = { "SP", "Hit", "Crit", "MP5", "AP" },
        },
    },
    -- MAGE (1482)
    {
        camelotID = 14821, retailID = 62, classID = 1482, class = "MAGE", classFile = "MAGE",
        treeIndex = 1, name = "arcane", icon = 135932, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "M", "H", "C", "V" },
        classicStats = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
        roleStats = {
            ["arc"]   = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
            ["fire"]  = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
            ["frost"] = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
            ["DPS"]   = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
        },
    },
    {
        camelotID = 14822, retailID = 63, classID = 1482, class = "MAGE", classFile = "MAGE",
        treeIndex = 2, name = "fire", icon = 135810, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "H", "M", "V", "C" },
        classicStats = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
        roleStats = {
            ["fire"]  = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
            ["frost"] = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
            ["arc"]   = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
            ["DPS"]   = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
        },
    },
    {
        camelotID = 14823, retailID = 64, classID = 1482, class = "MAGE", classFile = "MAGE",
        treeIndex = 3, name = "frost", icon = 135846, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "M", "C", "H", "V" },
        classicStats = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
        roleStats = {
            ["frost"] = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
            ["fire"]  = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
            ["arc"]   = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
            ["DPS"]   = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
        },
    },
    -- WARLOCK (1490)
    {
        camelotID = 14901, retailID = 265, classID = 1490, class = "WARLOCK", classFile = "WARLOCK",
        treeIndex = 1, name = "affliction", icon = 136145, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "M", "C", "H", "V" },
        classicStats = { "SP", "Hit", "Crit", "Stam", "Int", "Spi", "H", "Arm" },
        roleStats = {
            ["aff"]    = { "SP", "Hit", "Crit", "Stam", "Int", "Spi", "H", "Arm" },
            ["demo"]   = { "SP", "Hit", "Crit", "Stam", "Int", "Spi", "H", "Arm" },
            ["destro"] = { "SP", "Hit", "Crit", "Int", "Stam", "Spi", "H", "Arm" },
            ["DPS"]    = { "SP", "Hit", "Crit", "Stam", "Int", "Spi", "H", "Arm" },
        },
    },
    {
        camelotID = 14902, retailID = 266, classID = 1490, class = "WARLOCK", classFile = "WARLOCK",
        treeIndex = 2, name = "demonology", icon = 136172, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "H", "C", "M", "V" },
        classicStats = { "SP", "Hit", "Crit", "Stam", "Int", "Spi", "H", "Arm" },
        roleStats = {
            ["demo"]   = { "SP", "Hit", "Crit", "Stam", "Int", "Spi", "H", "Arm" },
            ["aff"]    = { "SP", "Hit", "Crit", "Stam", "Int", "Spi", "H", "Arm" },
            ["destro"] = { "SP", "Hit", "Crit", "Int", "Stam", "Spi", "H", "Arm" },
            ["DPS"]    = { "SP", "Hit", "Crit", "Stam", "Int", "Spi", "H", "Arm" },
        },
    },
    {
        camelotID = 14903, retailID = 267, classID = 1490, class = "WARLOCK", classFile = "WARLOCK",
        treeIndex = 3, name = "destruction", icon = 136186, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "H", "M", "C", "V" },
        classicStats = { "SP", "Hit", "Crit", "Int", "Stam", "Spi", "H", "Arm" },
        roleStats = {
            ["destro"] = { "SP", "Hit", "Crit", "Int", "Stam", "Spi", "H", "Arm" },
            ["aff"]    = { "SP", "Hit", "Crit", "Stam", "Int", "Spi", "H", "Arm" },
            ["demo"]   = { "SP", "Hit", "Crit", "Stam", "Int", "Spi", "H", "Arm" },
            ["DPS"]    = { "SP", "Hit", "Crit", "Int", "Stam", "Spi", "H", "Arm" },
        },
    },
    -- DRUID (1484)
    {
        camelotID = 14841, retailID = 102, classID = 1484, class = "DRUID", classFile = "DRUID",
        treeIndex = 1, name = "balance", icon = 136096, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "M", "H", "C", "V" },
        classicStats = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
        roleStats = {
            ["cat"]   = { "Str", "Agi", "AP", "Crit", "Hit", "Stam", "Int", "Arm" },
            ["bear"]  = { "Arm", "Stam", "Def", "Dodge", "Agi", "Str", "Hit", "AP" },
            ["moon"]  = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
            ["resto"] = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Stam", "H" },
            ["DPS"]   = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
            ["HEAL"]  = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Stam", "H" },
            ["MOON"]  = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
            ["RESTO"] = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Stam", "H" },
            ["CAT"]   = { "Str", "Agi", "AP", "Crit", "Hit", "Stam", "Int", "Arm" },
            ["BEAR"]  = { "Arm", "Stam", "Def", "Dodge", "Agi", "Str", "Hit", "AP" },
        },
    },
    {
        camelotID = 14842, retailID = 103, classID = 1484, class = "DRUID", classFile = "DRUID",
        treeIndex = 2, name = "feral", icon = 132242, role = "DPS", isTank = false, isHealer = false, isClassic = true,
        retailStats  = { "M", "H", "C", "V" },
        classicStats = { "Str", "Agi", "AP", "Crit", "Hit", "Stam", "Int", "Arm" },
        roleStats = {
            ["cat"]   = { "Str", "Agi", "AP", "Crit", "Hit", "Stam", "Int", "Arm" },
            ["bear"]  = { "Arm", "Stam", "Def", "Dodge", "Agi", "Str", "Hit", "AP" },
            ["moon"]  = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
            ["resto"] = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Stam", "H" },
            ["DPS"]   = { "Str", "Agi", "AP", "Crit", "Hit", "Stam", "Int", "Arm" },
            ["TANK"]  = { "Arm", "Stam", "Def", "Dodge", "Agi", "Str", "Hit", "AP" },
            ["CAT"]   = { "Str", "Agi", "AP", "Crit", "Hit", "Stam", "Int", "Arm" },
            ["BEAR"]  = { "Arm", "Stam", "Def", "Dodge", "Agi", "Str", "Hit", "AP" },
            ["MOON"]  = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
            ["RESTO"] = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Stam", "H" },
        },
    },
    {
        camelotID = 14843, retailID = 105, classID = 1484, class = "DRUID", classFile = "DRUID",
        treeIndex = 3, name = "restoration", icon = 136041, role = "HEAL", isTank = false, isHealer = true, isClassic = true,
        retailStats  = { "H", "M", "V", "C" },
        classicStats = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Stam", "H" },
        roleStats = {
            ["resto"] = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Stam", "H" },
            ["moon"]  = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
            ["cat"]   = { "Str", "Agi", "AP", "Crit", "Hit", "Stam", "Int", "Arm" },
            ["bear"]  = { "Arm", "Stam", "Def", "Dodge", "Agi", "Str", "Hit", "AP" },
            ["HEAL"]  = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Stam", "H" },
            ["DPS"]   = { "SP", "Int", "Crit", "Hit", "Str", "Agi" },
            ["RESTO"] = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Stam", "H" },
            ["MOON"]  = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
            ["CAT"]   = { "Str", "Agi", "AP", "Crit", "Hit", "Stam", "Int", "Arm" },
            ["BEAR"]  = { "Arm", "Stam", "Def", "Dodge", "Agi", "Str", "Hit", "AP" },
        },
    },
    {
        camelotID = 14844, retailID = 104, classID = 1484, class = "DRUID", classFile = "DRUID",
        treeIndex = 2, name = "guardian", icon = 132276, role = "TANK", isTank = true, isHealer = false, isClassic = true,
        retailStats  = { "V", "M", "H", "C" },
        classicStats = { "Arm", "Stam", "Def", "Dodge", "Agi", "Str", "Hit", "AP" },
        roleStats = {
            ["bear"]  = { "Arm", "Stam", "Def", "Dodge", "Agi", "Str", "Hit", "AP" },
            ["cat"]   = { "Str", "Agi", "AP", "Crit", "Hit", "Stam", "Int", "Arm" },
            ["moon"]  = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
            ["resto"] = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Stam", "H" },
            ["TANK"]  = { "Arm", "Stam", "Def", "Dodge", "Agi", "Str", "Hit", "AP" },
            ["DPS"]   = { "Str", "Agi", "AP", "Crit", "Hit", "Stam", "Int", "Arm" },
            ["BEAR"]  = { "Arm", "Stam", "Def", "Dodge", "Agi", "Str", "Hit", "AP" },
            ["CAT"]   = { "Str", "Agi", "AP", "Crit", "Hit", "Stam", "Int", "Arm" },
            ["MOON"]  = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
            ["RESTO"] = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Stam", "H" },
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
        classicStats = { "Str", "AP", "Hit", "Crit", "Agi", "Stam", "H", "Arm" },
        roleStats = {
            ["arms"] = { "Str", "AP", "Hit", "Crit", "Agi", "Stam", "H", "Arm" },
            ["fury"] = { "AP", "Hit", "Crit", "Str", "Agi", "Stam", "H", "Arm" },
            ["prot"] = { "Def", "Stam", "Arm", "BlockVal", "Block", "Dodge", "Parry", "Hit", "Str" },
            ["DPS"]  = { "Str", "AP", "Hit", "Crit", "Agi", "Stam", "H", "Arm" },
            ["TANK"] = { "Def", "Stam", "Arm", "BlockVal", "Block", "Dodge", "Parry", "Hit", "Str" },
        },
    },
    [1486] = {
        classID = 1486, class = "PALADIN", classFile = "PALADIN", name = "paladin", role = "DPS", isTank = false, isHealer = false, isClassic = true,
        classicStats = { "Str", "AP", "Hit", "Crit", "Stam", "SP", "Heal", "MP5", "Int" },
        roleStats = {
            ["prot"] = { "Def", "Stam", "Arm", "BlockVal", "Block", "Dodge", "Parry", "SP", "Hit" },
            ["ret"]  = { "Str", "AP", "Hit", "Crit", "Agi", "Stam", "SP", "H" },
            ["holy"] = { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "H" },
            ["DPS"]  = { "Str", "AP", "Hit", "Crit", "Agi", "Stam", "SP", "H" },
            ["HEAL"] = { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "H" },
            ["TANK"] = { "Def", "Stam", "Arm", "BlockVal", "Block", "Dodge", "Parry", "SP", "Hit" },
        },
    },
    [1485] = {
        classID = 1485, class = "HUNTER", classFile = "HUNTER", name = "hunter", role = "DPS", isTank = false, isHealer = false, isClassic = true,
        classicStats = { "Agi", "RAP", "Hit", "Crit", "AP", "Stam", "Int", "H" },
        roleStats = {
            ["bm"]   = { "Agi", "RAP", "Hit", "Crit", "AP", "Stam", "Int", "H" },
            ["mm"]   = { "Agi", "RAP", "Hit", "Crit", "AP", "Stam", "Int", "H" },
            ["surv"] = { "Agi", "RAP", "Hit", "Crit", "AP", "Stam", "Int", "H" },
            ["DPS"]  = { "Agi", "RAP", "Hit", "Crit", "AP", "Stam", "Int", "H" },
        },
    },
    [1488] = {
        classID = 1488, class = "ROGUE", classFile = "ROGUE", name = "rogue", role = "DPS", isTank = false, isHealer = false, isClassic = true,
        classicStats = { "Agi", "AP", "Hit", "Crit", "Str", "Stam", "H", "Arm" },
        roleStats = {
            ["sin"]    = { "Agi", "AP", "Hit", "Crit", "Str", "Stam", "H", "Arm" },
            ["combat"] = { "Hit", "Agi", "AP", "Crit", "Str", "Stam", "H", "Arm" },
            ["sub"]    = { "Agi", "AP", "Crit", "Hit", "Str", "Stam", "H", "Arm" },
            ["DPS"]    = { "Agi", "AP", "Hit", "Crit", "Str", "Stam", "H", "Arm" },
        },
    },
    [1487] = {
        classID = 1487, class = "PRIEST", classFile = "PRIEST", name = "priest", role = "HEAL", isTank = false, isHealer = true, isClassic = true,
        classicStats = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Hit", "Stam" },
        roleStats = {
            ["disc"]   = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Hit", "Stam" },
            ["holy"]   = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Hit", "Stam" },
            ["shad"]   = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
            ["shadow"] = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
            ["HEAL"]   = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Hit", "Stam" },
            ["DPS"]    = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
        },
    },
    [1489] = {
        classID = 1489, class = "SHAMAN", classFile = "SHAMAN", name = "shaman", role = "DPS", isTank = false, isHealer = false, isClassic = true,
        classicStats = { "SP", "Heal", "Hit", "Crit", "MP5", "AP", "Str", "Agi" },
        roleStats = {
            ["ele"]   = { "SP", "Hit", "Crit", "Int", "MP5", "Spi", "Stam", "H" },
            ["enh"]   = { "AP", "Str", "Agi", "Hit", "Crit", "SP", "Int", "Stam" },
            ["resto"] = { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "H" },
            ["DPS"]   = { "SP", "Hit", "Crit", "MP5", "AP", "Str", "Agi", "Int" },
            ["HEAL"]  = { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "H" },
        },
    },
    [1482] = {
        classID = 1482, class = "MAGE", classFile = "MAGE", name = "mage", role = "DPS", isTank = false, isHealer = false, isClassic = true,
        classicStats = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
        roleStats = {
            ["arc"]   = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
            ["fire"]  = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
            ["frost"] = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
            ["DPS"]   = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
        },
    },
    [1490] = {
        classID = 1490, class = "WARLOCK", classFile = "WARLOCK", name = "warlock", role = "DPS", isTank = false, isHealer = false, isClassic = true,
        classicStats = { "SP", "Hit", "Crit", "Stam", "Int", "Spi", "H", "Arm" },
        roleStats = {
            ["aff"]    = { "SP", "Hit", "Crit", "Stam", "Int", "Spi", "H", "Arm" },
            ["demo"]   = { "SP", "Hit", "Crit", "Stam", "Int", "Spi", "H", "Arm" },
            ["destro"] = { "SP", "Hit", "Crit", "Int", "Stam", "Spi", "H", "Arm" },
            ["DPS"]    = { "SP", "Hit", "Crit", "Stam", "Int", "Spi", "H", "Arm" },
        },
    },
    [1484] = {
        classID = 1484, class = "DRUID", classFile = "DRUID", name = "druid", role = "DPS", isTank = false, isHealer = false, isClassic = true,
        classicStats = { "Str", "Agi", "AP", "Crit", "Hit", "Stam", "Int", "Arm" },
        roleStats = {
            ["cat"]   = { "Str", "Agi", "AP", "Crit", "Hit", "Stam", "Int", "Arm" },
            ["bear"]  = { "Arm", "Stam", "Def", "Dodge", "Agi", "Str", "Hit", "AP" },
            ["moon"]  = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
            ["resto"] = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Stam", "H" },
            ["DPS"]   = { "Str", "Agi", "AP", "Crit", "Hit", "Stam", "Int", "Arm" },
            ["HEAL"]  = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Stam", "H" },
            ["TANK"]  = { "Arm", "Stam", "Def", "Dodge", "Agi", "Str", "Hit", "AP" },
            ["CAT"]   = { "Str", "Agi", "AP", "Crit", "Hit", "Stam", "Int", "Arm" },
            ["BEAR"]  = { "Arm", "Stam", "Def", "Dodge", "Agi", "Str", "Hit", "AP" },
            ["MOON"]  = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
            ["RESTO"] = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Stam", "H" },
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
-- Camelot / Classic Combat Stat Formulas & Calculations
-- Single source of truth for combat-table math (consumed by frames/character/infopanel.lua).
-- Authoritatively grounded in Blizzard_UIPanels_Game/Camelot/PaperDollFrameStats.lua,
-- PaperDollFrame.lua and SkillsFrame.lua. Native C APIs are preferred; formulas are fallbacks.
-- ══════════════════════════════════════════════════════════════════════════════

sfui.stats = sfui.stats or {}

local math_max = math.max
local math_min = math.min
local tonumber = tonumber
local InCombatLockdown = _G.InCombatLockdown
local _issecret = _G.issecretvalue

local SKILL_PER_LEVEL    = 5 -- SKILL_RANKS_PER_SKILL_LEVEL
local FIRST_SPELL_SCHOOL = 2 -- GetSpellBonusDamage luaIndex: 1 physical, 2 holy .. 7 arcane
local LAST_SPELL_SCHOOL  = 7

--- Coerce an API return into a plain number. Secret / nil values collapse to `fallback`
--- without ever being inspected, compared or formatted.
local function num(v, fallback)
    if fallback == nil then fallback = 0 end
    if v == nil or (_issecret and _issecret(v)) then return fallback end
    return tonumber(v) or fallback
end
sfui.stats.num = num

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function player_level()
    return (_G.UnitLevel and _G.UnitLevel("player")) or 60
end

-- ─── Defense & Incoming Attacks ──────────────────────────────────────────────

--- Returns effective defense skill and breakdown (effective, base, modifier, maxDefense, excess)
function sfui.stats.GetEffectiveDefense(unit)
    unit = unit or "player"
    local lvl = (_G.UnitLevel and _G.UnitLevel(unit)) or 60
    local maxDef = lvl * SKILL_PER_LEVEL
    if InCombatLockdown and InCombatLockdown() then
        return maxDef, maxDef, 0, maxDef, 0
    end
    if not _G.UnitDefenseSkill then return 0, 0, 0, 0, 0 end
    local base, mod = _G.UnitDefenseSkill(unit)
    base = num(base)
    mod = num(mod)
    local effective = math_max(0, base + mod)
    local excess = math_max(0, effective - maxDef)
    return effective, base, mod, maxDef, excess
end

--- Incoming melee table for an attacker with `enemyWeaponSkill` against the player's `defenseSkill`.
--- Writes into `out` so hot callers can reuse a single table.
--- @return table out { skillDiff, missChance, critChance, crushingChance, avoidanceMod }
function sfui.stats.GetIncomingCombatTable(enemyWeaponSkill, defenseSkill, isPlayerAttacker, out)
    out = out or {}
    local levelCap = player_level() * SKILL_PER_LEVEL
    local skillDiff = enemyWeaponSkill - defenseSkill
    out.skillDiff = skillDiff
    out.missChance = clamp(5.0 - skillDiff * 0.04, 0, 100)
    out.critChance = clamp(5.0 + skillDiff * 0.04, 0, 100)
    -- crushing blows: creatures only, attacker skill must exceed (capped) defense by 15+
    local crushDiff = enemyWeaponSkill - math_min(defenseSkill, levelCap)
    out.crushingChance = (not isPlayerAttacker and crushDiff >= 15) and clamp(crushDiff * 2.0 - 15.0, 0, 100) or 0
    -- dodge / parry / block shrink by 0.04% per attacker skill point above the player's level cap
    out.avoidanceMod = (levelCap - enemyWeaponSkill) * 0.04
    return out
end

--- Computes enemy combat table chances against the player based on level offset (e.g. 3 for boss)
--- and player's defense skill. Also provides glancing blow damage penalties.
function sfui.stats.GetEnemyCombatTable(levelOffset, defenseSkill)
    levelOffset = levelOffset or 3
    if not defenseSkill then
        defenseSkill = sfui.stats.GetEffectiveDefense("player")
    end
    local enemyWeaponSkill = (player_level() + levelOffset) * SKILL_PER_LEVEL
    local t = sfui.stats.GetIncomingCombatTable(enemyWeaponSkill, defenseSkill, false, {})
    t.enemyWeaponSkill = enemyWeaponSkill
    t.glancingLow = math_max(0.01, math_min(1.2, 1.30 - (t.skillDiff * 0.05)))
    t.glancingHigh = math_max(0.01, math_min(0.99, 1.20 - (t.skillDiff * 0.03)))
    return t
end

--- Physical damage reduction from armor (percent, 75% cap).
--- Uses C_PaperDollInfo (PaperDollFrame_GetArmorReduction*) with the Classic formula as fallback.
function sfui.stats.GetArmorReduction(armor, attackerLevel, againstTarget)
    armor = num(armor)
    if armor <= 0 then return 0 end
    attackerLevel = attackerLevel or (player_level() + 3)
    local C = _G.C_PaperDollInfo
    if C then
        if againstTarget and C.GetArmorEffectivenessAgainstTarget then
            local eff = num(C.GetArmorEffectivenessAgainstTarget(armor))
            if eff > 0 then return math_min(75.0, eff * 100) end
        end
        if C.GetArmorEffectiveness then
            local eff = num(C.GetArmorEffectiveness(armor, attackerLevel))
            if eff > 0 then return math_min(75.0, eff * 100) end
        end
    end
    local k = (attackerLevel >= 60) and (400 + 85 * (attackerLevel + 4.5 * (attackerLevel - 59)))
        or (400 + 85 * attackerLevel)
    return math_min(75.0, armor / (armor + k) * 100)
end

--- Average magic damage resisted (percent, 75% cap) for a resistance value against a caster level.
--- Mirrors ExpectedSpellResistance() in Blizzard_UIPanels_Game/Camelot/PaperDollFrameStats.lua.
function sfui.stats.GetResistanceReduction(resistance, casterLevel)
    casterLevel = math_max(1, casterLevel or player_level())
    local expected = _G.ExpectedSpellResistance
    local frac = expected and num(expected(casterLevel, resistance))
        or (0.75 * resistance / (casterLevel * SKILL_PER_LEVEL))
    return clamp(frac * 100, 0, 75)
end

--- Player resistance in one school.
--- @param damageClass number Enum.Damageclass (2 fire, 3 nature, 4 frost, 5 shadow, 6 arcane)
--- @param casterLevel number|nil level of the attacking caster for the mitigation estimate
--- @return number effective, number bonus, number reductionPct
function sfui.stats.GetResistance(damageClass, casterLevel)
    if not _G.UnitResistance then return 0, 0, 0 end
    local _, _, effective, bonus = _G.UnitResistance("player", damageClass)
    effective, bonus = num(effective), num(bonus)
    return effective, bonus, sfui.stats.GetResistanceReduction(effective, casterLevel)
end

-- ─── Outgoing Attacks ────────────────────────────────────────────────────────

--- Calculates Hit Chance across Melee, Ranged, and Spell
function sfui.stats.GetHitChance(unit)
    unit = unit or "player"
    local meleeHit, rangedHit, spellHit = 0, 0, 0
    if unit == "player" then
        local CR = _G.GetCombatRatingBonus
        local crMelee = num(CR and _G.CR_HIT_MELEE and CR(_G.CR_HIT_MELEE))
        local modHit = num(_G.GetHitModifier and _G.GetHitModifier())
        meleeHit = crMelee + modHit

        local crRanged = num(CR and _G.CR_HIT_RANGED and CR(_G.CR_HIT_RANGED))
        local modRanged = num(_G.GetRangedHitModifier and _G.GetRangedHitModifier())
        rangedHit = crRanged + modRanged

        local crSpell = num(CR and _G.CR_HIT_SPELL and CR(_G.CR_HIT_SPELL))
        local modSpell = num(_G.GetSpellHitModifier and _G.GetSpellHitModifier())
        spellHit = crSpell + modSpell
    elseif unit == "pet" then
        meleeHit = num(_G.GetPetHitChanceModifier and _G.GetPetHitChanceModifier())
        rangedHit = meleeHit
        spellHit = num(_G.GetPetSpellHitChanceModifier and _G.GetPetSpellHitChanceModifier())
    end
    local maxHit = math_max(meleeHit, rangedHit, spellHit)
    return maxHit, meleeHit, rangedHit, spellHit
end

--- Calculates Critical Strike Chance across Melee, Ranged, and Spell
function sfui.stats.GetCritChance()
    local meleeCrit = num(_G.GetCritChance and _G.GetCritChance())
    local rangedCrit = num(_G.GetRangedCritChance and _G.GetRangedCritChance())
    local spellCrit = num(_G.GetSpellCritChance and _G.GetSpellCritChance())
    local maxCrit = math_max(meleeCrit, rangedCrit, spellCrit)
    return maxCrit, meleeCrit, rangedCrit, spellCrit
end

--- Melee / ranged miss chance for a weapon skill against a target defense.
--- @return number miss   base miss on special (yellow) attacks, percent
--- @return number cap    hit needed to never miss specials (includes the >10 skill-gap hit suppression)
--- @return number dwCap  hit needed to remove the dual-wield white-swing miss
function sfui.stats.GetMeleeMissChance(weaponSkill, targetDefense, isPlayerTarget)
    local diff = targetDefense - weaponSkill
    local miss, suppression = nil, 0
    if isPlayerTarget or diff <= 0 then
        miss = 5.0 + diff * 0.04
    elseif diff > 10 then
        miss, suppression = 5.0 + diff * 0.2, 1.0
    else
        miss = 5.0 + diff * 0.1
    end
    miss = clamp(miss, 0, 100)
    return miss, miss + suppression, clamp(miss * 0.8 + 20.0, 0, 100) + suppression
end

--- Spell miss chance by level difference (target - player). 1% of spells always miss.
--- @return number miss, number cap
function sfui.stats.GetSpellMissChance(levelDelta, isPlayerTarget)
    local miss
    if levelDelta <= 2 then
        miss = 4 + levelDelta
    elseif isPlayerTarget then
        miss = 13 + (levelDelta - 3) * 7
    else
        miss = 17 + (levelDelta - 3) * 11
    end
    miss = clamp(miss, 1, 99)
    return miss, miss - 1
end

--- Glancing blows on white melee swings (creatures at or above the player's level only).
--- Prefers GetGlancingBlowChance / GetGlancingBlowPenalty as used by Camelot SkillsFrame.lua.
--- @return number chance, number penalty (percent)
function sfui.stats.GetGlancingBlow(weaponSkill, targetLevel, isPlayerTarget)
    local pLevel = player_level()
    if isPlayerTarget or targetLevel < pLevel then return 0, 0 end
    local targetDefense = targetLevel * SKILL_PER_LEVEL
    local diff = targetDefense - weaponSkill

    local GetChance, GetPenalty = _G.GetGlancingBlowChance, _G.GetGlancingBlowPenalty
    local chance = GetChance and num(GetChance(weaponSkill, targetDefense), -1) or -1
    if chance >= 0 then
        chance = chance * 100
    else
        chance = clamp(10.0 + (targetDefense - math_min(weaponSkill, pLevel * SKILL_PER_LEVEL)) * 2.0, 0, 100)
    end

    local penalty = GetPenalty and num(GetPenalty(weaponSkill, targetDefense), -1) or -1
    if penalty >= 0 then
        penalty = penalty * 100
    else
        local low = clamp(1.30 - diff * 0.05, 0.01, 0.91)
        local high = clamp(1.20 - diff * 0.03, 0.20, 0.99)
        penalty = math_max(0, (1 - (low + high) / 2) * 100)
    end
    return chance, penalty
end

--- Attack power (melee or ranged).
--- @return number effective, number base, number posBuff, number negBuff
function sfui.stats.GetAttackPower(ranged)
    local fn = ranged and _G.UnitRangedAttackPower or _G.UnitAttackPower
    if not fn then return 0, 0, 0, 0 end
    local base, pos, neg = fn("player")
    base, pos, neg = num(base), num(pos), num(neg)
    return math_max(0, base + pos + neg), base, pos, neg
end

--- Ranged weapon damage (bows, guns, thrown, wands). Mirrors GetRangedDamage() in Camelot PaperDollFrame.lua.
--- @return number dps, number minDamage, number maxDamage, number speed
function sfui.stats.GetRangedDamage()
    if not _G.UnitRangedDamage then return 0, 0, 0, 0 end
    local speed, minDamage, maxDamage = _G.UnitRangedDamage("player")
    speed, minDamage, maxDamage = num(speed), num(minDamage), num(maxDamage)
    local dps = (speed > 0) and ((minDamage + maxDamage) / 2 / speed) or 0
    return dps, minDamage, maxDamage, speed
end

-- ─── Spellcasting ────────────────────────────────────────────────────────────

--- Spell damage per school and bonus healing.
--- Mirrors PaperDollFrame_SetSpellBonusDamage / CharacterSpellBonusDamage_OnEnter.
--- @param out table|nil reusable table filled with [schoolLuaIndex] = bonus (2 holy .. 7 arcane)
--- @return number minDamage, number maxDamage, number maxSchool, number healing
function sfui.stats.GetSpellPower(out)
    local GetDmg = _G.GetSpellBonusDamage
    local minD, maxD, maxSchool = 0, 0, FIRST_SPELL_SCHOOL
    if GetDmg then
        minD = num(GetDmg(FIRST_SPELL_SCHOOL))
        maxD = minD
        if out then out[FIRST_SPELL_SCHOOL] = minD end
        for school = FIRST_SPELL_SCHOOL + 1, LAST_SPELL_SCHOOL do
            local v = num(GetDmg(school))
            if out then out[school] = v end
            if v < minD then minD = v end
            if v > maxD then maxD, maxSchool = v, school end
        end
    end
    local healing = num(_G.GetSpellBonusHealing and _G.GetSpellBonusHealing())
    return minD, maxD, maxSchool, healing
end

--- Mana regeneration per 5 seconds (not casting, while casting).
function sfui.stats.GetManaRegen()
    if not _G.GetManaRegen then return 0, 0 end
    local base, casting = _G.GetManaRegen()
    return math.floor(num(base) * 5.0), math.floor(num(casting) * 5.0)
end

--- Calculates Haste percentage across Melee, Ranged, and Spell
function sfui.stats.GetHaste(unit)
    unit = unit or "player"
    local meleeHaste = 0
    local rangedHaste = 0
    local spellHaste = num(_G.UnitSpellHaste and _G.UnitSpellHaste(unit))
    if unit == "player" then
        meleeHaste = num(_G.GetMeleeHaste and _G.GetMeleeHaste())
        if _G.GetRangedHaste then
            local baseRanged, ammoHaste = _G.GetRangedHaste()
            rangedHaste = num(baseRanged) + num(ammoHaste)
        end
    elseif unit == "pet" then
        meleeHaste = num(_G.GetPetMeleeHaste and _G.GetPetMeleeHaste())
    end
    local maxHaste = math_max(meleeHaste, rangedHaste, spellHaste)
    return maxHaste, meleeHaste, rangedHaste, spellHaste
end

--- Returns Armor Penetration
function sfui.stats.GetArmorPenetration(unit)
    if unit and unit ~= "player" then return 0 end
    return num(_G.GetArmorPenetration and _G.GetArmorPenetration())
end

--- Returns Expertise breakdown (maxExpertise, mainHand, offHand, ranged)
function sfui.stats.GetExpertise(unit)
    if (unit and unit ~= "player") or not _G.GetExpertise then return 0, 0, 0, 0 end
    local exp, ohExp, rangedExp = _G.GetExpertise()
    exp = num(exp)
    ohExp = num(ohExp)
    rangedExp = num(rangedExp)
    local maxExp = math_max(exp, ohExp, rangedExp)
    return maxExp, exp, ohExp, rangedExp
end

--- Returns Shield Block chance and Block value
function sfui.stats.GetBlockInfo(unit)
    if unit and unit ~= "player" then return 0, 0 end
    local chance = num(_G.GetBlockChance and _G.GetBlockChance())
    local val = num(_G.GetShieldBlock and _G.GetShieldBlock())
    return chance, val
end
