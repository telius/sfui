local addonName, addon = ...
sfui = sfui or {}
sfui.gear = sfui.gear or {}
sfui.gear.engine = {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/gear/engine.lua
--  Unified Gear Stat Evaluation, Role Resolution & Upgrade Engine
-- ══════════════════════════════════════════════════════════════════════════════

local common = sfui.common

sfui.gear.TANK_SPECS = sfui.gear.TANK_SPECS or {}
local TANK_SPECS = sfui.gear.TANK_SPECS

-- ────────────────────────────────────────────────────────────────────────────
-- High-Performance Spec, Role & Stat Queries (Zero-allocation SPEC_BRIDGE)
-- ────────────────────────────────────────────────────────────────────────────
sfui.gear.engine.GetClassicClassID = sfui.gear.GetClassicClassID
sfui.gear.engine.IsClassicSpec     = sfui.gear.IsClassicSpec
sfui.gear.engine.GetClassicRole    = sfui.gear.GetClassicRole
sfui.gear.engine.IsTankSpec        = sfui.gear.IsTankSpec
sfui.gear.engine.IsHealerSpec      = sfui.gear.IsHealerSpec
sfui.gear.engine.GetDefaultStats   = sfui.gear.GetDefaultStats

--- Returns available stat tokens eligible for weighting on a given spec & role
--- @param specID number|string
--- @param isTank boolean|nil
--- @param role string|nil
--- @return table array of stat token strings
function sfui.gear.GetStatPool(specID, isTank, role)
    specID = tonumber(specID) or 0
    local classID = sfui.gear.GetClassicClassID(specID) or specID
    local isClassic = sfui.gear.IsClassicSpec(specID) or (classID >= 1482 and classID <= 1491)

    if not isClassic then
        return { "H", "M", "V", "C" }
    end

    role = role or (isTank and "TANK" or sfui.gear.GetClassicRole(specID))
    if isTank == nil then
        isTank = (role == "TANK")
    end

    if isTank or role == "TANK" then
        if classID == 1484 then -- Druid Bear Tank (cannot block or parry)
            return { "Arm", "Stam", "Def", "Dodge", "Agi", "Str", "Hit", "AP" }
        elseif classID == 1486 then -- Paladin Tank (uses shield & SP/healing)
            return { "Def", "Stam", "Arm", "Dodge", "Parry", "Block", "SP", "Hit", "Str" }
        else -- Warrior Tank
            return { "Def", "Stam", "Arm", "Dodge", "Parry", "Block", "Hit", "Str", "Agi" }
        end
    end

    if role == "HEAL" then
        if classID == 1484 then -- Resto Druid
            return { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Stam", "Arm", "H" }
        elseif classID == 1486 then -- Holy Paladin
            return { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "Arm", "H" }
        elseif classID == 1487 then -- Holy/Disc Priest
            return { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Hit", "Stam", "Arm", "H" }
        elseif classID == 1489 then -- Resto Shaman
            return { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "Arm", "H" }
        end
    end

    -- Strictly DPS (NO defense, NO dodge, NO parry, NO block)
    if classID == 1482 then -- Mage (Caster DPS)
        return { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H", "Arm" }
    elseif classID == 1484 then -- Druid (Feral / Balance DPS)
        -- 102 = retail Balance; 14841 = Camelot Balance (tree 1)
        if specID == 102 or specID == 14841 then
            return { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "Arm", "H" }
        end
        return { "AP", "Hit", "Crit", "Str", "Agi", "SP", "Int", "Stam", "Arm", "H" }
    elseif classID == 1485 then -- Hunter (Ranged Physical DPS)
        return { "RAP", "Hit", "Crit", "Agi", "AP", "Int", "Stam", "Arm", "H" }
    elseif classID == 1486 then -- Paladin (Retribution Melee DPS)
        return { "AP", "Hit", "Crit", "Str", "Agi", "SP", "Int", "Stam", "Arm", "H" }
    elseif classID == 1487 then -- Priest (Shadow DPS)
        return { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "Arm", "H" }
    elseif classID == 1488 then -- Rogue (Melee Physical DPS)
        return { "AP", "Hit", "Crit", "Agi", "Str", "Stam", "Arm", "H" }
    elseif classID == 1489 then -- Shaman (Enhancement / Elemental DPS)
        -- 262 = retail Elemental; 14891 = Camelot Elemental (tree 1)
        if specID == 262 or specID == 14891 then
            return { "SP", "Hit", "Crit", "Int", "MP5", "Spi", "Stam", "Arm", "H" }
        end
        return { "AP", "Hit", "Crit", "Str", "Agi", "SP", "Int", "MP5", "Stam", "Arm", "H" }
    elseif classID == 1490 then -- Warlock (Caster DPS)
        return { "SP", "Hit", "Crit", "Int", "Stam", "Spi", "Arm", "H" }
    elseif classID == 1491 then -- Warrior (Arms / Fury DPS)
        return { "AP", "Hit", "Crit", "Str", "Agi", "Stam", "Arm", "H" }
    end

    return { "SP", "AP", "Hit", "Crit", "Str", "Agi", "Int", "Stam", "Arm", "H" }
end
sfui.gear.engine.GetStatPool = sfui.gear.GetStatPool
