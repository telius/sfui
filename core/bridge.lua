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

local isClassicGame = (sfui.isClassic == true or sfui.isCamelot == true)

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

local function isClassicGameClient()
    if sfui.isRetail == true or (sfui.version and sfui.version.retail) or (sfui.compat and not sfui.compat.is_classic) then
        return false
    end
    return (sfui.isClassic == true or sfui.isEra == true or sfui.isCamelot == true)
end

function sfui.gear.IsClassicSpec(specID)
    if not isClassicGameClient() then return false end
    if not specID then return false end
    local num = tonumber(specID)
    if num then
        if num >= 1482 and num <= 1491 then return true end
        if num >= 14821 and num <= 14913 then return true end
    end
    local b = SPEC_BRIDGE[specID]
    if b and b.camelotID and (b.camelotID == specID or b.camelotID == num) then
        return true
    end
    return false
end

function sfui.gear.GetClassicRole(specID, db)
    if not isClassicGameClient() then
        local b = SPEC_BRIDGE[specID]
        return (b and b.role and b.role:lower()) or "dps"
    end

    local numID = tonumber(specID) or 0
    local classID = sfui.gear.GetClassicClassID(numID) or numID

    local rawRole = nil
    if db and db.user_selected_role and db.classic_role then
        rawRole = db.classic_role
    elseif db and db.classic_role then
        rawRole = db.classic_role
    elseif db and db.role then
        if db.role == "TANK" then rawRole = "tank"
        elseif db.role == "HEALER" then rawRole = "heal"
        elseif db.role == "DAMAGER" then rawRole = "dps"
        end
    elseif db and (db.is_tank or db.armor_ilvl_prio) then
        rawRole = "tank"
    elseif db and db.is_healer then
        rawRole = "heal"
    else
        local b = SPEC_BRIDGE[specID]
        if b and b.role then
            rawRole = b.role:lower()
        end
    end

    local r = rawRole and rawRole:lower()

    if classID == 1484 or (numID >= 14841 and numID <= 14843) then -- Druid: cat bear moon resto
        if r == "cat" or r == "bear" or r == "moon" or r == "resto" then
            return r
        elseif r == "tank" then
            return "bear"
        elseif r == "heal" or r == "healer" then
            return "resto"
        elseif r == "dps" or r == "damager" then
            if numID == 14841 or specID == 102 then
                return "moon"
            else
                return "cat"
            end
        end
        return (numID == 14843 and "resto") or (numID == 14841 and "moon") or "cat"
    elseif classID == 1486 or (numID >= 14861 and numID <= 14863) then -- Paladin: prot ret holy
        if r == "prot" or r == "ret" or r == "holy" then
            return r
        elseif r == "tank" then
            return "prot"
        elseif r == "heal" or r == "healer" then
            return "holy"
        elseif r == "dps" or r == "damager" then
            return "ret"
        end
        return (numID == 14862 and "prot") or (numID == 14861 and "holy") or "ret"
    elseif classID == 1491 or (numID >= 14911 and numID <= 14913) then -- Warrior: arms fury prot
        if r == "arms" or r == "fury" or r == "prot" then
            return r
        elseif r == "tank" then
            return "prot"
        elseif r == "dps" or r == "damager" then
            if numID == 14912 or specID == 72 then return "fury" else return "arms" end
        end
        return (numID == 14913 and "prot") or (numID == 14912 and "fury") or "arms"
    elseif classID == 1489 or (numID >= 14891 and numID <= 14893) then -- Shaman: ele enh resto
        if r == "ele" or r == "enh" or r == "resto" then
            return r
        elseif r == "heal" or r == "healer" then
            return "resto"
        elseif r == "dps" or r == "damager" then
            if numID == 14892 or specID == 263 then return "enh" else return "ele" end
        end
        return (numID == 14893 and "resto") or (numID == 14892 and "enh") or "ele"
    elseif classID == 1487 or (numID >= 14871 and numID <= 14873) then -- Priest: disc holy shad
        if r == "disc" or r == "holy" or r == "shad" or r == "shadow" then
            return (r == "shadow" and "shad") or r
        elseif r == "heal" or r == "healer" then
            return (numID == 14871 and "disc") or "holy"
        elseif r == "dps" or r == "damager" then
            return "shad"
        end
        return (numID == 14873 and "shad") or (numID == 14871 and "disc") or "holy"
    elseif classID == 1488 or (numID >= 14881 and numID <= 14883) then -- Rogue: sin combat sub
        if r == "sin" or r == "combat" or r == "sub" then
            return r
        elseif r == "assa" or r == "assassination" then
            return "sin"
        elseif r == "subtlety" then
            return "sub"
        end
        return (numID == 14882 and "combat") or (numID == 14883 and "sub") or "sin"
    elseif classID == 1482 or (numID >= 14821 and numID <= 14823) then -- Mage: arc fire frost
        if r == "arc" or r == "fire" or r == "frost" then
            return r
        elseif r == "arcane" then
            return "arc"
        end
        return (numID == 14822 and "fire") or (numID == 14823 and "frost") or "arc"
    elseif classID == 1490 or (numID >= 14901 and numID <= 14903) then -- Warlock: aff demo destro
        if r == "aff" or r == "demo" or r == "destro" then
            return r
        elseif r == "affliction" then
            return "aff"
        elseif r == "demonology" then
            return "demo"
        elseif r == "destruction" then
            return "destro"
        end
        return (numID == 14902 and "demo") or (numID == 14903 and "destro") or "aff"
    elseif classID == 1485 or (numID >= 14851 and numID <= 14853) then -- Hunter: bm mm surv
        if r == "bm" or r == "mm" or r == "surv" then
            return r
        elseif r == "beastmastery" or r == "beast mastery" then
            return "bm"
        elseif r == "marksmanship" then
            return "mm"
        elseif r == "survival" then
            return "surv"
        end
        return (numID == 14852 and "mm") or (numID == 14853 and "surv") or "bm"
    end

    return r or "dps"
end

function sfui.gear.IsTankSpec(specID, db)
    if not isClassicGameClient() then
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

    if not db and specID and _G.SfuiDB and _G.SfuiDB.gear then
        local b = SPEC_BRIDGE[specID]
        db = _G.SfuiDB.gear[specID] or (b and b.camelotID and _G.SfuiDB.gear[b.camelotID]) or (b and b.classID and _G.SfuiDB.gear[b.classID])
    end
    if db and (db.classic_role or db.role) then
        local cRole = db.classic_role and db.classic_role:lower()
        if cRole == "tank" or cRole == "bear" or cRole == "prot" or db.role == "TANK" then
            return true
        end
        if cRole then
            return false
        end
    end
    if db and (db.is_tank or db.armor_ilvl_prio or db.role == "TANK") then
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
    if not isClassicGameClient() then
        local b = SPEC_BRIDGE[specID]
        if b then return b.isHealer or false end
        local num = tonumber(specID)
        if num and num ~= specID then
            b = SPEC_BRIDGE[num]
            if b then return b.isHealer or false end
        end
        return false
    end

    if not db and specID and _G.SfuiDB and _G.SfuiDB.gear then
        local b = SPEC_BRIDGE[specID]
        db = _G.SfuiDB.gear[specID] or (b and b.camelotID and _G.SfuiDB.gear[b.camelotID]) or (b and b.classID and _G.SfuiDB.gear[b.classID])
    end
    if db and (db.classic_role or db.role) then
        local cRole = db.classic_role and db.classic_role:lower()
        if cRole == "heal" or cRole == "resto" or cRole == "holy" or cRole == "disc" or db.role == "HEALER" then
            return true
        end
        if cRole then
            return false
        end
    end
    if db and (db.is_healer or db.role == "HEALER") then
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
        if role and b.roleStats then
            local rLower = role:lower()
            if b.roleStats[role] then return b.roleStats[role] end
            if b.roleStats[rLower] then return b.roleStats[rLower] end
            local rUpper = role:upper()
            if b.roleStats[rUpper] then return b.roleStats[rUpper] end
            local aliasMap = {
                ["cat"] = "DPS", ["bear"] = "TANK", ["moon"] = "DPS", ["resto"] = "HEAL",
                ["prot"] = "TANK", ["ret"] = "DPS", ["holy"] = "HEAL", ["disc"] = "HEAL",
                ["arms"] = "DPS", ["fury"] = "DPS", ["ele"] = "DPS", ["enh"] = "DPS",
                ["shad"] = "DPS", ["shadow"] = "DPS",
                ["sin"] = "DPS", ["combat"] = "DPS", ["sub"] = "DPS",
                ["arc"] = "DPS", ["fire"] = "DPS", ["frost"] = "DPS",
                ["aff"] = "DPS", ["demo"] = "DPS", ["destro"] = "DPS",
                ["bm"] = "DPS", ["mm"] = "DPS", ["surv"] = "DPS",
            }
            local mapped = aliasMap[rLower]
            if mapped and b.roleStats[mapped] then return b.roleStats[mapped] end
        end
        if b.defaultStats then
            return b.defaultStats
        end
    end
    local raw = rawget(sfui.default_stats, specID) or (type(specID) == "string" and tonumber(specID) and rawget(sfui.default_stats, tonumber(specID)))
    if raw then return raw end
    return sfui.default_stats[specID]
end

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

    role = role or (isTank and "prot" or sfui.gear.GetClassicRole(specID))
    local rLower = role and role:lower() or "dps"
    if isTank == nil then
        isTank = (rLower == "tank" or rLower == "bear" or rLower == "prot")
    end

    if isTank or rLower == "tank" or rLower == "bear" or rLower == "prot" then
        if classID == 1484 then -- Druid Bear Tank (cannot block or parry)
            return { "Arm", "Stam", "Def", "Dodge", "Agi", "Str", "Hit", "AP" }
        elseif classID == 1486 then -- Paladin Tank (uses shield & SP/healing)
            return { "Def", "Stam", "Arm", "Dodge", "Parry", "Block", "SP", "Hit", "Str" }
        else -- Warrior Tank
            return { "Def", "Stam", "Arm", "Dodge", "Parry", "Block", "Hit", "Str", "Agi" }
        end
    end

    if rLower == "heal" or rLower == "resto" or rLower == "holy" or rLower == "disc" then
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
    elseif classID == 1484 then -- Druid (Cat / Moon / Feral / Balance DPS)
        if rLower == "moon" or specID == 102 or specID == 14841 then
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
        if rLower == "ele" or specID == 262 or specID == 14891 then
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
