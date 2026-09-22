local addonName, addon = ...
sfui = sfui or {}
sfui.gear = sfui.gear or {}
sfui.gear.engine = {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/gear/engine.lua
--  Unified Gear Stat Evaluation, Role Resolution & Upgrade Engine
-- ══════════════════════════════════════════════════════════════════════════════

local common = sfui.common

sfui.gear.TANK_SPECS = {
    [250] = true, -- Blood DK
    [581] = true, -- Vengeance DH
    [104] = true, -- Guardian Druid
    [268] = true, -- Brewmaster Monk
    [66]  = true, -- Protection Paladin
    [73]  = true, -- Protection Warrior
}

--- Resolves the authoritative Classic / Camelot role ("TANK", "HEAL", "DPS")
--- @param specID number|string
--- @param db table|nil Optional character or spec DB override
--- @return string "TANK"|"HEAL"|"DPS"
function sfui.gear.GetClassicRole(specID, db)
    specID = tonumber(specID) or 0
    if db and db.user_selected_role and db.classic_role then
        return db.classic_role
    end
    if common and common.get_player_specs then
        local specs = common.get_player_specs()
        if specs and specs[specID] and specs[specID].classicRole then
            return specs[specID].classicRole
        end
    end
    if db and db.classic_role then
        return db.classic_role
    end
    if db and db.role then
        if db.role == "TANK" then return "TANK" end
        if db.role == "HEALER" then return "HEAL" end
        if db.role == "DAMAGER" then return "DPS" end
    end
    if db and (db.is_tank or db.armor_ilvl_prio) then
        return "TANK"
    end
    if db and db.is_healer then
        return "HEAL"
    end
    if specID == 1487 then -- Priest default stats start with Heal in stats.lua
        return "HEAL"
    end
    return "DPS"
end
sfui.gear.engine.GetClassicRole = sfui.gear.GetClassicRole

--- Determines if a given spec is currently configured as a tank
--- @param specID number|string
--- @param db table|nil
--- @return boolean
function sfui.gear.IsTankSpec(specID, db)
    if not specID then return false end
    specID = tonumber(specID) or 0
    if specID >= 1482 and specID <= 1491 then
        if db and db.classic_role then
            return db.classic_role == "TANK"
        end
        return sfui.gear.GetClassicRole(specID, db) == "TANK"
    end
    return (sfui.gear.TANK_SPECS and sfui.gear.TANK_SPECS[specID]) or false
end
sfui.gear.engine.IsTankSpec = sfui.gear.IsTankSpec

--- Determines if a given spec is currently configured as a healer
--- @param specID number|string
--- @param db table|nil
--- @return boolean
function sfui.gear.IsHealerSpec(specID, db)
    if not specID then return false end
    specID = tonumber(specID) or 0
    if specID >= 1482 and specID <= 1491 then
        if db and db.classic_role then
            return db.classic_role == "HEAL"
        end
        return sfui.gear.GetClassicRole(specID, db) == "HEAL"
    end
    local role = common and common.get_spec_role and common.get_spec_role(specID)
    return role == "HEALER" or role == "HEAL"
end
sfui.gear.engine.IsHealerSpec = sfui.gear.IsHealerSpec

--- Returns default stat priority table for a spec and role
--- @param specID number|string
--- @param role string|nil
--- @return table|nil
function sfui.gear.GetDefaultStats(specID, role)
    specID = tonumber(specID) or 0
    role = role or "DPS"
    if sfui.classic_default_stats and sfui.classic_default_stats[specID] then
        local rStats = sfui.classic_default_stats[specID][role]
        if rStats then return rStats end
    end
    return sfui.default_stats and sfui.default_stats[specID]
end
sfui.gear.engine.GetDefaultStats = sfui.gear.GetDefaultStats

--- Returns available stat tokens eligible for weighting on a given spec & role
--- @param specID number|string
--- @param isTank boolean|nil
--- @param role string|nil
--- @return table array of stat token strings
function sfui.gear.GetStatPool(specID, isTank, role)
    specID = tonumber(specID) or 0
    local isClassic = sfui.isClassic or (specID >= 1482 and specID <= 1491)

    if not isClassic then
        return { "H", "M", "V", "C" }
    end

    role = role or (isTank and "TANK" or "DPS")

    if isTank or role == "TANK" then
        if specID == 1484 then -- Druid Bear Tank (cannot block or parry)
            return { "Arm", "Stam", "Def", "Dodge", "Agi", "Str", "Hit", "AP" }
        elseif specID == 1486 then -- Paladin Tank (uses shield & SP/healing)
            return { "Def", "Stam", "Arm", "Dodge", "Parry", "Block", "SP", "Hit", "Str" }
        else -- Warrior Tank
            return { "Def", "Stam", "Arm", "Dodge", "Parry", "Block", "Hit", "Str", "Agi" }
        end
    end

    if role == "HEAL" then
        if specID == 1484 then -- Resto Druid
            return { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Stam", "Arm", "H" }
        elseif specID == 1486 then -- Holy Paladin
            return { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "Arm", "H" }
        elseif specID == 1487 then -- Holy/Disc Priest
            return { "Heal", "SP", "MP5", "Spi", "Int", "Crit", "Hit", "Stam", "Arm", "H" }
        elseif specID == 1489 then -- Resto Shaman
            return { "Heal", "SP", "MP5", "Int", "Crit", "Spi", "Stam", "Arm", "H" }
        end
    end

    -- Strictly DPS (NO defense, NO dodge, NO parry, NO block)
    if specID == 1482 then -- Mage (Caster DPS)
        return { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "H", "Arm" }
    elseif specID == 1484 then -- Druid (Feral / Balance DPS)
        return { "AP", "Hit", "Crit", "Str", "Agi", "SP", "Int", "Stam", "Arm", "H" }
    elseif specID == 1485 then -- Hunter (Ranged Physical DPS)
        return { "RAP", "Hit", "Crit", "Agi", "AP", "Int", "Stam", "Arm", "H" }
    elseif specID == 1486 then -- Paladin (Retribution Melee DPS)
        return { "AP", "Hit", "Crit", "Str", "Agi", "SP", "Int", "Stam", "Arm", "H" }
    elseif specID == 1487 then -- Priest (Shadow DPS)
        return { "SP", "Hit", "Crit", "Int", "Spi", "MP5", "Stam", "Arm", "H" }
    elseif specID == 1488 then -- Rogue (Melee Physical DPS)
        return { "AP", "Hit", "Crit", "Agi", "Str", "Stam", "Arm", "H" }
    elseif specID == 1489 then -- Shaman (Enhancement / Elemental DPS)
        return { "AP", "Hit", "Crit", "Str", "Agi", "SP", "Int", "MP5", "Stam", "Arm", "H" }
    elseif specID == 1490 then -- Warlock (Caster DPS)
        return { "SP", "Hit", "Crit", "Int", "Stam", "Spi", "Arm", "H" }
    elseif specID == 1491 then -- Warrior (Arms / Fury DPS)
        return { "AP", "Hit", "Crit", "Str", "Agi", "Stam", "Arm", "H" }
    end

    return { "SP", "AP", "Hit", "Crit", "Str", "Agi", "Int", "Stam", "Arm", "H" }
end
sfui.gear.engine.GetStatPool = sfui.gear.GetStatPool
