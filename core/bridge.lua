local addonName, addon = ...
sfui = sfui or {}
sfui.talents = sfui.talents or {}
sfui.gear    = sfui.gear or {}
sfui.common  = sfui.common or {}
sfui.data    = sfui.data or {}

-- ══════════════════════════════════════════════════════════════════════════════
-- SFUI Spec Secondary Stat Priorities & Authoritative Spec Bridge Engine
--
-- Compiles authoritative SPEC_BRIDGE, default stats, role resolution, and
-- bidirectional Retail <-> Classic Forever / Camelot translation from data/stats.lua.
-- ══════════════════════════════════════════════════════════════════════════════

local specDefinitions      = sfui.data.SPEC_DEFINITIONS or {}
local baseClassDefinitions = sfui.data.BASE_CLASS_DEFINITIONS or {}

-- Static fallbacks so queries never allocate a new table
local _defaultStatOrder        = { "H", "M", "C", "V" }
local _defaultClassicStatOrder = { "AP", "SP", "Hit", "Crit", "Str", "Agi", "Int", "Stam" }

local SPEC_BRIDGE           = {}
local CAMELOT_TO_RETAIL     = {}
local RETAIL_TO_CAMELOT     = {}
sfui.default_stats          = sfui.default_stats or {}
sfui.classic_default_stats  = sfui.classic_default_stats or {}
sfui.gear.TANK_SPECS        = sfui.gear.TANK_SPECS or {}

local isClassicGame = (sfui.isClassic == true or sfui.isForever == true)

for _, def in ipairs(specDefinitions) do
    if isClassicGame then
        def.defaultStats = def.classicStats or def.defaultStats or def.retailStats
    else
        def.defaultStats = def.retailStats or def.defaultStats or def.classicStats
    end

    if def.isTank then
        if def.retailID then sfui.gear.TANK_SPECS[def.retailID] = true end
        if def.camelotID then sfui.gear.TANK_SPECS[def.camelotID] = true end
    end

    local roleTable = def.roleStats or (def.classicStats and { [def.role or "DPS"] = def.classicStats })

    if def.retailID then
        SPEC_BRIDGE[def.retailID] = def
        SPEC_BRIDGE[tostring(def.retailID)] = def
        sfui.default_stats[def.retailID] = def.defaultStats
        if roleTable then
            sfui.classic_default_stats[def.retailID] = roleTable
        end
        if def.camelotID then
            RETAIL_TO_CAMELOT[def.retailID] = def.camelotID
        end
    end
    if def.camelotID then
        SPEC_BRIDGE[def.camelotID] = def
        SPEC_BRIDGE[tostring(def.camelotID)] = def
        sfui.default_stats[def.camelotID] = def.classicStats or def.defaultStats
        if roleTable then
            sfui.classic_default_stats[def.camelotID] = roleTable
        end
        if def.retailID then
            CAMELOT_TO_RETAIL[def.camelotID] = def.retailID
        end
    end
end

for classID, def in pairs(baseClassDefinitions) do
    if isClassicGame then
        def.defaultStats = def.classicStats or def.defaultStats
    else
        def.defaultStats = def.defaultStats or def.classicStats
    end

    SPEC_BRIDGE[classID] = def
    SPEC_BRIDGE[tostring(classID)] = def
    sfui.default_stats[classID] = def.defaultStats
    if def.roleStats then
        sfui.classic_default_stats[classID] = def.roleStats
    end
end

-- Fallback metatable for sfui.default_stats to ensure zero nil crashes
setmetatable(sfui.default_stats, {
    __index = function(t, k)
        if not k then return _defaultStatOrder end
        local b = SPEC_BRIDGE[k]
        if b and b.defaultStats then return b.defaultStats end
        local nk = tonumber(k)
        if nk and nk ~= k then
            local nb = SPEC_BRIDGE[nk]
            if nb and nb.defaultStats then return nb.defaultStats end
        end
        return (isClassicGame or (nk and nk >= 1482 and nk <= 1491)) and _defaultClassicStatOrder or _defaultStatOrder
    end
})

sfui.talents.SPEC_BRIDGE          = SPEC_BRIDGE
sfui.talents.CAMELOT_TO_RETAIL    = CAMELOT_TO_RETAIL
sfui.talents.RETAIL_TO_CAMELOT    = RETAIL_TO_CAMELOT
sfui.common.SPEC_BRIDGE           = SPEC_BRIDGE
sfui.gear.TREE_TO_CLASSIC_INFO    = SPEC_BRIDGE

-- ────────────────────────────────────────────────────────────────────────────
-- Bidirectional Spec ID Translators (O(1) Direct Lookup)
-- ────────────────────────────────────────────────────────────────────
function sfui.talents.to_retail_spec_id(specID)
    if not specID then return nil end
    local bridge = SPEC_BRIDGE[specID]
    if bridge then return bridge.retailID end
    local num = tonumber(specID)
    if num and num ~= specID then
        bridge = SPEC_BRIDGE[num]
        if bridge then return bridge.retailID end
    end
    return specID
end
sfui.common.to_retail_spec_id = sfui.talents.to_retail_spec_id
sfui.gear.to_retail_spec_id   = sfui.talents.to_retail_spec_id

function sfui.talents.to_camelot_spec_id(specID)
    if not specID then return nil end
    local bridge = SPEC_BRIDGE[specID]
    if bridge then return bridge.camelotID or bridge.retailID end
    local num = tonumber(specID)
    if num and num ~= specID then
        bridge = SPEC_BRIDGE[num]
        if bridge then return bridge.camelotID or bridge.retailID end
    end
    return specID
end
sfui.common.to_camelot_spec_id = sfui.talents.to_camelot_spec_id
sfui.gear.to_camelot_spec_id   = sfui.talents.to_camelot_spec_id

function sfui.talents.is_spec_match(specA, specB)
    if not specA or not specB then return false end
    if specA == specB then return true end
    local bA = SPEC_BRIDGE[specA]
    local bB = SPEC_BRIDGE[specB]
    if bA and bB then
        return bA == bB or bA.retailID == bB.retailID or bA.camelotID == bB.camelotID
    end
    if bA then
        return bA.retailID == specB or bA.camelotID == specB
    end
    if bB then
        return bB.retailID == specA or bB.camelotID == specA
    end
    local numA = tonumber(specA)
    local numB = tonumber(specB)
    if numA and numB and numA == numB then return true end
    return false
end
sfui.common.is_spec_match = sfui.talents.is_spec_match
sfui.gear.is_spec_match   = sfui.talents.is_spec_match

function sfui.talents.is_spec_in_list(list, specID)
    if not list or not specID then return false end
    if list[specID] ~= nil then return list[specID] end
    local b = SPEC_BRIDGE[specID]
    if b then
        if b.retailID and list[b.retailID] ~= nil then return list[b.retailID] end
        if b.camelotID and list[b.camelotID] ~= nil then return list[b.camelotID] end
        if b.classID and list[b.classID] ~= nil then return list[b.classID] end
    end
    local num = tonumber(specID)
    if num and num ~= specID and list[num] ~= nil then return list[num] end
    return false
end
sfui.common.is_spec_in_list = sfui.talents.is_spec_in_list
sfui.gear.is_spec_in_list   = sfui.talents.is_spec_in_list

-- ────────────────────────────────────────────────────────────────────────────
-- Unified Gear & Role Engine Lookups (Zero Allocations on Hot Paths)
-- ────────────────────────────────────────────────────────────────────────────
function sfui.gear.GetClassicClassID(specID)
    if not specID then return nil end
    local b = SPEC_BRIDGE[specID]
    if b then return b.classID end
    local num = tonumber(specID)
    if num and num ~= specID then
        b = SPEC_BRIDGE[num]
        if b then return b.classID end
    end
    return nil
end

function sfui.gear.IsClassicSpec(specID)
    if not specID then return false end
    local b = SPEC_BRIDGE[specID]
    if b then return b.isClassic or (b.classID and b.classID >= 1482 and b.classID <= 1491) or false end
    local num = tonumber(specID)
    if num then
        if num >= 1482 and num <= 1491 then return true end
        if num >= 14821 and num <= 14913 then return true end
    end
    return false
end

function sfui.gear.GetClassicRole(specID, db)
    if db and db.user_selected_role and db.classic_role then
        return db.classic_role
    end
    if db and db.classic_role then
        return db.classic_role
    end
    local b = SPEC_BRIDGE[specID]
    if b and b.role then
        return b.role
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
    return "DPS"
end

function sfui.gear.IsTankSpec(specID, db)
    if db and db.classic_role then
        return db.classic_role == "TANK"
    end
    if db and (db.is_tank or db.armor_ilvl_prio) then
        return true
    end
    if sfui.gear.TANK_SPECS and sfui.gear.TANK_SPECS[specID] then
        return true
    end
    local b = SPEC_BRIDGE[specID]
    if b then return b.isTank or false end
    local num = tonumber(specID)
    if num and num ~= specID then
        if sfui.gear.TANK_SPECS and sfui.gear.TANK_SPECS[num] then return true end
        b = SPEC_BRIDGE[num]
        if b then return b.isTank or false end
    end
    return false
end

function sfui.gear.IsHealerSpec(specID, db)
    if db and db.classic_role then
        return db.classic_role == "HEAL"
    end
    if db and db.is_healer then
        return true
    end
    local b = SPEC_BRIDGE[specID]
    if b then return b.isHealer or false end
    local num = tonumber(specID)
    if num and num ~= specID then
        b = SPEC_BRIDGE[num]
        if b then return b.isHealer or false end
    end
    return false
end

function sfui.gear.GetDefaultStats(specID, role)
    if not specID then return _defaultStatOrder end
    local b = SPEC_BRIDGE[specID]
    if b then
        if role and b.roleStats and b.roleStats[role] then
            return b.roleStats[role]
        end
        if b.defaultStats then
            return b.defaultStats
        end
    end
    local raw = rawget(sfui.default_stats, specID) or (type(specID) == "string" and tonumber(specID) and rawget(sfui.default_stats, tonumber(specID)))
    if raw then return raw end
    return sfui.default_stats[specID]
end

function sfui.stats_debug_info()
    local cCount, rCount = 0, 0
    for _ in pairs(CAMELOT_TO_RETAIL) do cCount = cCount + 1 end
    for _ in pairs(RETAIL_TO_CAMELOT) do rCount = rCount + 1 end
    return string.format("Camelot->Retail mapped: %d, Retail->Camelot mapped: %d", cCount, rCount)
end

sfui.stats = sfui.stats or {}
sfui.stats.spec_bridge = SPEC_BRIDGE
sfui.stats.camelot_to_retail = CAMELOT_TO_RETAIL
sfui.stats.retail_to_camelot = RETAIL_TO_CAMELOT
sfui.stats.GetDebugInfo = sfui.stats_debug_info

if sfui.RegisterModule then
    sfui.RegisterModule("stats", sfui.stats)
end
