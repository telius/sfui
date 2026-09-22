local addonName, addon = ...
sfui = sfui or {}
sfui.default_stats = {}

-- ══════════════════════════════════════════════════════════════════════════════
-- SFUI Spec Secondary Stat Priorities
--
-- Default stat weights used by gear comparison and stat tracking across
-- Retail and Classic Forever / Camelot specializations.
-- ══════════════════════════════════════════════════════════════════════════════

-- DEATH KNIGHT
sfui.default_stats[250] = { "H", "C", "M", "V" } -- Blood
sfui.default_stats[251] = { "M", "C", "H", "V" } -- Frost
sfui.default_stats[252] = { "M", "C", "H", "V" } -- Unholy

-- DEMON HUNTER
sfui.default_stats[577] = { "C", "M", "H", "V" }  -- Havoc
sfui.default_stats[581] = { "H", "C", "V", "M" }  -- Vengeance
sfui.default_stats[1480] = { "H", "M", "C", "V" } -- Devourer

-- DRUID
sfui.default_stats[102] = { "M", "H", "C", "V" } -- Balance
sfui.default_stats[103] = { "M", "H", "C", "V" } -- Feral
sfui.default_stats[104] = { "H", "V", "C", "M" } -- Guardian
sfui.default_stats[105] = { "H", "M", "V", "C" } -- Restoration

-- EVOKER
sfui.default_stats[1467] = { "C", "H", "M", "V" } -- Devastation
sfui.default_stats[1468] = { "M", "H", "C", "V" } -- Preservation
sfui.default_stats[1473] = { "C", "H", "M", "V" } -- Augmentation

-- HUNTER
sfui.default_stats[253] = { "M", "C", "V", "H" } -- Beast Mastery
sfui.default_stats[254] = { "C", "M", "H", "V" } -- Marksmanship
sfui.default_stats[255] = { "M", "C", "H", "V" } -- Survival

-- MAGE
sfui.default_stats[62] = { "M", "H", "C", "V" } -- Arcane
sfui.default_stats[63] = { "H", "M", "V", "C" } -- Fire
sfui.default_stats[64] = { "M", "C", "H", "V" } -- Frost

-- MONK
sfui.default_stats[268] = { "C", "M", "V", "H" } -- Brewmaster
sfui.default_stats[269] = { "H", "C", "M", "V" } -- Windwalker
sfui.default_stats[270] = { "H", "C", "V", "M" } -- Mistweaver

-- PALADIN
sfui.default_stats[65] = { "M", "C", "H", "V" } -- Holy
sfui.default_stats[66] = { "H", "V", "C", "M" } -- Protection
sfui.default_stats[70] = { "M", "H", "C", "V" } -- Retribution

-- PRIEST
sfui.default_stats[256] = { "H", "C", "V", "M" } -- Discipline
sfui.default_stats[257] = { "V", "C", "H", "M" } -- Holy
sfui.default_stats[258] = { "H", "M", "C", "V" } -- Shadow

-- ROGUE
sfui.default_stats[259] = { "C", "H", "M", "V" } -- Assassination
sfui.default_stats[260] = { "H", "C", "V", "M" } -- Outlaw
sfui.default_stats[261] = { "M", "H", "C", "V" } -- Subtlety

-- SHAMAN
sfui.default_stats[262] = { "H", "M", "C", "V" } -- Elemental
sfui.default_stats[263] = { "M", "H", "C", "V" } -- Enhancement
sfui.default_stats[264] = { "C", "V", "M", "H" } -- Restoration

-- WARLOCK
sfui.default_stats[265] = { "M", "C", "H", "V" } -- Affliction
sfui.default_stats[266] = { "H", "C", "M", "V" } -- Demonology
sfui.default_stats[267] = { "H", "M", "C", "V" } -- Destruction

-- WARRIOR
sfui.default_stats[71] = { "C", "H", "M", "V" } -- Arms
sfui.default_stats[72] = { "M", "H", "C", "V" } -- Fury
sfui.default_stats[73] = { "H", "C", "V", "M" } -- Protection

-- CLASSIC FOREVER / CAMELOT (Single class spec IDs - Pure DPS / Healer defaults, zero defense/dodge)
sfui.default_stats[1482] = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" }       -- Mage (Caster DPS)
sfui.default_stats[1484] = { "Str", "Agi", "AP", "Crit", "Hit", "Stam", "Int", "Arm" }      -- Druid (Feral DPS / Hybrid)
sfui.default_stats[1485] = { "Agi", "RAP", "Hit", "Crit", "AP", "Stam", "Int", "H" }       -- Hunter (Physical Ranged DPS)
sfui.default_stats[1486] = { "Str", "AP", "Hit", "Crit", "Stam", "SP", "Heal", "MP5", "Int" } -- Paladin (Ret DPS / Holy)
sfui.default_stats[1487] = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Hit", "Stam" }   -- Priest (Healer / Caster)
sfui.default_stats[1488] = { "Agi", "AP", "Hit", "Crit", "Str", "Stam", "H", "Arm" }       -- Rogue (Physical Melee DPS)
sfui.default_stats[1489] = { "SP", "Heal", "Hit", "Crit", "MP5", "AP", "Str", "Agi" }      -- Shaman (Caster / Healer)
sfui.default_stats[1490] = { "SP", "Hit", "Crit", "Stam", "Int", "Spi", "H", "Arm" }       -- Warlock (Caster DPS)
sfui.default_stats[1491] = { "Str", "AP", "Hit", "Crit", "Agi", "Stam", "H", "Arm" }       -- Warrior (Physical Melee DPS)

-- Static fallback so __index never allocates a new table
local _defaultStatOrder = { "H", "M", "C", "V" }
local _defaultClassicStatOrder = { "AP", "SP", "Hit", "Crit", "Str", "Agi", "Int", "Stam" }

setmetatable(sfui.default_stats, {
    __index = function(t, k)
        local nk = tonumber(k)
        if nk and rawget(t, nk) then return rawget(t, nk) end
        if nk and nk >= 1482 and nk <= 1491 then
            return _defaultClassicStatOrder
        end
        return _defaultStatOrder
    end
})

sfui.classic_default_stats = sfui.classic_default_stats or {
    [1482] = { -- Mage
        ["DPS"]  = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
    },
    [1484] = { -- Druid
        ["DPS"]  = { "Str", "Agi", "AP", "Crit", "Hit", "Stam", "Int", "Arm" },
        ["HEAL"] = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Stam", "H" },
        ["TANK"] = { "Arm", "Stam", "Def", "Dodge", "Agi", "Str", "Hit", "AP" },
    },
    [1485] = { -- Hunter
        ["DPS"]  = { "Agi", "RAP", "Hit", "Crit", "AP", "Stam", "Int", "H" },
    },
    [1486] = { -- Paladin
        ["DPS"]  = { "Str", "AP", "Hit", "Crit", "Agi", "Stam", "SP", "H" },
        ["HEAL"] = { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "H" },
        ["TANK"] = { "Def", "Stam", "Arm", "Dodge", "Parry", "Block", "SP", "Hit" },
    },
    [1487] = { -- Priest
        ["DPS"]  = { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H" },
        ["HEAL"] = { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Hit", "Stam" },
    },
    [1488] = { -- Rogue
        ["DPS"]  = { "Agi", "AP", "Hit", "Crit", "Str", "Stam", "H", "Arm" },
    },
    [1489] = { -- Shaman
        ["DPS"]  = { "SP", "Hit", "Crit", "MP5", "AP", "Str", "Agi", "Int" },
        ["HEAL"] = { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "H" },
    },
    [1490] = { -- Warlock
        ["DPS"]  = { "SP", "Hit", "Crit", "Stam", "Int", "Spi", "H", "Arm" },
    },
    [1491] = { -- Warrior
        ["DPS"]  = { "Str", "AP", "Hit", "Crit", "Agi", "Stam", "H", "Arm" },
        ["TANK"] = { "Def", "Stam", "Arm", "Dodge", "Parry", "Block", "Hit", "Str" },
    },
}

