local addonName, addon = ...
sfui = sfui or {}
sfui.talents = sfui.talents or {}
sfui.common = sfui.common or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/core/talents.lua
--  Specialization, Class Discovery & Talent/Trait Inspection Engine
-- ══════════════════════════════════════════════════════════════════════════════

local CLASS_NAMES_TO_ID = {
    WARRIOR      = 1,
    PALADIN      = 2,
    HUNTER       = 3,
    ROGUE        = 4,
    PRIEST       = 5,
    DEATHKNIGHT  = 6,
    SHAMAN       = 7,
    MAGE         = 8,
    WARLOCK      = 9,
    MONK         = 10,
    DRUID        = 11,
    DEMONHUNTER  = 12,
    EVOKER       = 13,
}

local cachedPlayerClass   = nil
local cachedPlayerClassID = 0

-- Returns the authoritative player class ID (1..13)
function sfui.talents.get_player_class_id()
    if cachedPlayerClassID > 0 then return cachedPlayerClassID end
    local _, eng, cid = UnitClass("player")
    if cid and cid > 0 then
        cachedPlayerClassID = cid
        cachedPlayerClass   = eng
        return cid
    end
    if eng and CLASS_NAMES_TO_ID[eng] then
        cachedPlayerClassID = CLASS_NAMES_TO_ID[eng]
        cachedPlayerClass   = eng
        return cachedPlayerClassID
    end
    return 0
end
sfui.common.get_player_class_id = sfui.talents.get_player_class_id

-- Returns the cached player class filename and ID (e.g., "WARRIOR", 1)
function sfui.talents.get_player_class()
    if not cachedPlayerClass or cachedPlayerClassID == 0 then
        sfui.talents.get_player_class_id()
    end
    return cachedPlayerClass, cachedPlayerClassID
end
sfui.common.get_player_class = sfui.talents.get_player_class

local C_Spec                    = _G.C_SpecializationInfo or {}
local GetSpecialization         = C_Spec.GetSpecialization or _G.GetSpecialization
local GetSpecializationInfo     = C_Spec.GetSpecializationInfo or _G.GetSpecializationInfo
local GetSpecializationInfoByID = C_Spec.GetSpecializationInfoByID or _G.GetSpecializationInfoByID
local GetSpecializationRole     = C_Spec.GetSpecializationRole or _G.GetSpecializationRole
local GetNumSpecializations     = C_Spec.GetNumSpecializations or _G.GetNumSpecializations
local GetLootSpecialization     = C_Spec.GetLootSpecialization or _G.GetLootSpecialization

local cachedSpecID        = 0
local cachedSpecIndex     = 0
local cachedPlayerSpecs   = nil
local cachedPlayerSpecIDs = nil

local CLASS_VANILLA_SPEC_MAP = {
    ["MAGE"]     = 1482, [8]  = 1482,
    ["DRUID"]    = 1484, [11] = 1484,
    ["HUNTER"]   = 1485, [3]  = 1485,
    ["PALADIN"]  = 1486, [2]  = 1486,
    ["PRIEST"]   = 1487, [5]  = 1487,
    ["ROGUE"]    = 1488, [4]  = 1488,
    ["SHAMAN"]   = 1489, [7]  = 1489,
    ["WARLOCK"]  = 1490, [9]  = 1490,
    ["WARRIOR"]  = 1491, [1]  = 1491,
}

local CLASS_ICON_FILEIDS = {
    ["WARRIOR"] = 626008,
    ["PALADIN"] = 626003,
    ["HUNTER"]  = 626000,
    ["ROGUE"]   = 626005,
    ["PRIEST"]  = 626004,
    ["SHAMAN"]  = 626006,
    ["MAGE"]    = 626001,
    ["WARLOCK"] = 626007,
    ["DRUID"]   = 625999,
}

local CLASSIC_TREE_SPECS = {
    [1491] = { -- Warrior
        [1] = { name = "arms",         icon = 132355, role = "DPS",  specID = 71 },
        [2] = { name = "fury",         icon = 132347, role = "DPS",  specID = 72 },
        [3] = { name = "protection",   icon = 132341, role = "TANK", specID = 73 },
    },
    [1486] = { -- Paladin
        [1] = { name = "holy",         icon = 135920, role = "HEAL", specID = 65 },
        [2] = { name = "protection",   icon = 236264, role = "TANK", specID = 66 },
        [3] = { name = "retribution",  icon = 135873, role = "DPS",  specID = 70 },
    },
    [1485] = { -- Hunter
        [1] = { name = "beast mastery", icon = 132222, role = "DPS", specID = 253 },
        [2] = { name = "marksmanship",  icon = 132218, role = "DPS", specID = 254 },
        [3] = { name = "survival",      icon = 132215, role = "DPS", specID = 255 },
    },
    [1488] = { -- Rogue
        [1] = { name = "assassination", icon = 132292, role = "DPS", specID = 259 },
        [2] = { name = "combat",        icon = 132309, role = "DPS", specID = 260 },
        [3] = { name = "subtlety",      icon = 132320, role = "DPS", specID = 261 },
    },
    [1487] = { -- Priest
        [1] = { name = "discipline",   icon = 135940, role = "HEAL", specID = 256 },
        [2] = { name = "holy",         icon = 237542, role = "HEAL", specID = 257 },
        [3] = { name = "shadow",       icon = 136207, role = "DPS",  specID = 258 },
    },
    [1489] = { -- Shaman
        [1] = { name = "elemental",    icon = 136048, role = "DPS",  specID = 262 },
        [2] = { name = "enhancement",  icon = 136051, role = "DPS",  specID = 263 },
        [3] = { name = "restoration",  icon = 136052, role = "HEAL", specID = 264 },
    },
    [1482] = { -- Mage
        [1] = { name = "arcane",       icon = 135932, role = "DPS",  specID = 62 },
        [2] = { name = "fire",         icon = 135810, role = "DPS",  specID = 63 },
        [3] = { name = "frost",        icon = 135846, role = "DPS",  specID = 64 },
    },
    [1490] = { -- Warlock
        [1] = { name = "affliction",   icon = 136145, role = "DPS",  specID = 265 },
        [2] = { name = "demonology",   icon = 136172, role = "DPS",  specID = 266 },
        [3] = { name = "destruction",  icon = 136186, role = "DPS",  specID = 267 },
    },
    [1484] = { -- Druid
        [1] = { name = "balance",      icon = 136096, role = "DPS",  specID = 102 },
        [2] = { name = "feral",        icon = 132242, role = "DPS",  specID = 103 },
        [3] = { name = "restoration",  icon = 136041, role = "HEAL", specID = 105 },
    },
}

local CLASSIC_SPEC_LOOKUP = {}
for _, trees in pairs(CLASSIC_TREE_SPECS) do
    for _, info in ipairs(trees) do
        if info.specID then
            CLASSIC_SPEC_LOOKUP[info.specID] = info
        end
    end
end

local _classicTreeScratch = {
    [1] = { name = nil, icon = nil, points = 0 },
    [2] = { name = nil, icon = nil, points = 0 },
    [3] = { name = nil, icon = nil, points = 0 },
}
local _classicGroupIDsScratch = {}

--- Predicts specialization, role, and dominant talent tree for Classic / Camelot.
--- Returns Class icon when untalented or level < 10, or dominant tree spec icon when points are spent.
--- Zero execution on Retail.
function sfui.talents.get_classic_talent_spec_info(vSpecID, classFilename)
    if sfui.isRetail then
        return nil
    end

    if not classFilename or classFilename == "" or type(classFilename) ~= "string" then
        local pClass = sfui.talents.get_player_class()
        if type(pClass) == "string" and pClass ~= "" then
            classFilename = pClass
        elseif UnitClass then
            local _, eng = UnitClass("player")
            classFilename = eng
        end
    end
    classFilename = classFilename and tostring(classFilename):upper() or ""

    local playerLevel = (UnitLevel and UnitLevel("player")) or 1

    local classIcon = (classFilename and CLASS_ICON_FILEIDS[classFilename])
        or (classFilename ~= "" and ("Interface\\Icons\\ClassIcon_" .. classFilename:sub(1,1):upper() .. classFilename:sub(2):lower()))
        or 134400

    local defaultRole = "DPS"
    if classFilename == "PRIEST" then
        defaultRole = "HEAL"
    end

    local className = (UnitClass and select(1, UnitClass("player"))) or classFilename

    for i = 1, 3 do
        local entry = _classicTreeScratch[i]
        entry.name = nil
        entry.icon = nil
        entry.points = 0
        entry.role = nil
    end

    -- Below level 10: Untalented, use class icon and default role
    if playerLevel < 10 then
        return {
            name        = className,
            icon        = classIcon,
            classicRole = defaultRole,
            role        = (defaultRole == "TANK" and "TANK") or (defaultRole == "HEAL" and "HEALER") or "DAMAGER",
            equivSpecID = nil,
            totalPoints = 0,
            dominantTree = 1,
        }
    end

    local totalPoints = 0
    local foundData = false

    -- Method 1: Camelot C_Traits group display & currency info
    local C_Traits = _G.C_Traits
    local C_ClassTalents = _G.C_ClassTalents
    if C_Traits and C_Traits.GetGroupDisplayInfoByTreeID and C_Traits.GetGroupCurrencyInfo then
        local configID = (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID())
            or (C_SpecializationInfo and C_SpecializationInfo.GetCombatConfigIDForSpecGroup and C_SpecializationInfo.GetCombatConfigIDForSpecGroup(1))
            or (C_Traits.GetConfigIDBySystemID and C_Traits.GetConfigIDBySystemID(1))
        if configID then
            local configInfo = C_Traits.GetConfigInfo(configID)
            local treeID = configInfo and configInfo.treeIDs and configInfo.treeIDs[1]
            if treeID then
                local displayInfos = C_Traits.GetGroupDisplayInfoByTreeID(treeID)
                if displayInfos and #displayInfos > 0 then
                    table.wipe(_classicGroupIDsScratch)
                    for _, di in ipairs(displayInfos) do
                        _classicGroupIDsScratch[#_classicGroupIDsScratch + 1] = di.groupID
                    end
                    local groupInfos = C_Traits.GetGroupCurrencyInfo(configID, _classicGroupIDsScratch)
                    local traitTotal = 0
                    for i = 1, math.min(3, #displayInfos) do
                        local di = displayInfos[i]
                        local spent = 0
                        if groupInfos then
                            for _, gi in ipairs(groupInfos) do
                                if gi.traitNodeGroupID == di.groupID and gi.currencyInfos and gi.currencyInfos[1] then
                                    spent = gi.currencyInfos[1].spent or 0
                                    break
                                end
                            end
                        end
                        _classicTreeScratch[i].name = di.displayName
                        _classicTreeScratch[i].icon = di.icon
                        _classicTreeScratch[i].points = spent
                        traitTotal = traitTotal + spent
                    end
                    if traitTotal > 0 then
                        totalPoints = traitTotal
                        foundData = true
                    end
                end
            end
        end
    end

    -- Method 2: Classic Era / Camelot C_SpecializationInfo or GetTalentTabInfo
    if not foundData or totalPoints == 0 then
        for i = 1, 3 do
            local tName, tIcon, tPoints, tRole
            if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
                local _, sName, _, sIcon, sRole, _, sPoints = C_SpecializationInfo.GetSpecializationInfo(i)
                if sName or sIcon or (sPoints and sPoints > 0) then
                    tName = sName
                    tIcon = sIcon
                    tPoints = sPoints or 0
                    tRole = sRole
                end
            end
            if (not tPoints or tPoints == 0) and GetTalentTabInfo then
                local r1, r2, r3, r4, r5 = GetTalentTabInfo(i)
                if type(r1) == "string" then
                    tName = tName or r1
                    tIcon = tIcon or r2
                    tPoints = (tPoints and tPoints > 0) and tPoints or (tonumber(r3) or 0)
                elseif type(r1) == "number" then
                    tName = tName or r2
                    tIcon = tIcon or r4
                    tPoints = (tPoints and tPoints > 0) and tPoints or (tonumber(r5) or 0)
                end
            end
            if tName or tIcon or (tPoints and tPoints > 0) then
                local pts = tPoints or 0
                _classicTreeScratch[i].name = tName or _classicTreeScratch[i].name
                _classicTreeScratch[i].icon = tIcon or _classicTreeScratch[i].icon
                _classicTreeScratch[i].points = pts
                _classicTreeScratch[i].role = tRole or _classicTreeScratch[i].role
                totalPoints = totalPoints + pts
                foundData = true
            end
        end
    end

    if not foundData or totalPoints == 0 then
        return {
            name        = className,
            icon        = classIcon,
            classicRole = defaultRole,
            role        = (defaultRole == "TANK" and "TANK") or (defaultRole == "HEAL" and "HEALER") or "DAMAGER",
            equivSpecID = nil,
            totalPoints = 0,
            dominantTree = 1,
        }
    end

    local maxPoints = -1
    local dominantIdx = 1
    for i = 1, 3 do
        local data = _classicTreeScratch[i]
        if data.points > maxPoints then
            maxPoints = data.points
            dominantIdx = i
        end
    end

    local domData = _classicTreeScratch[dominantIdx]
    local treeName = domData and domData.name
    local treeIcon = domData and domData.icon
    local mapping = CLASSIC_TREE_SPECS[vSpecID] and CLASSIC_TREE_SPECS[vSpecID][dominantIdx]
    local predictedRole = (mapping and mapping.role) or (domData and domData.role) or defaultRole
    local equivSpecID = mapping and mapping.specID

    if equivSpecID and (not treeName or not treeIcon) and GetSpecializationInfoByID then
        local _, sName, _, sIcon = GetSpecializationInfoByID(equivSpecID)
        treeName = treeName or sName
        treeIcon = treeIcon or sIcon
    end

    return {
        name        = treeName or className,
        icon        = treeIcon or classIcon,
        classicRole = predictedRole,
        role        = (predictedRole == "TANK" and "TANK") or (predictedRole == "HEAL" and "HEALER") or "DAMAGER",
        equivSpecID = equivSpecID,
        totalPoints = totalPoints,
        dominantTree = dominantIdx,
    }
end
sfui.common.get_classic_talent_spec_info = sfui.talents.get_classic_talent_spec_info

function sfui.talents.invalidate_player_specs_cache()
    cachedPlayerSpecs   = nil
    cachedPlayerSpecIDs = nil
end
sfui.common.invalidate_player_specs_cache = sfui.talents.invalidate_player_specs_cache

local function build_player_specs_cache()
    if cachedPlayerSpecs and cachedPlayerSpecIDs and #cachedPlayerSpecIDs > 0 then
        return cachedPlayerSpecs, cachedPlayerSpecIDs
    end

    cachedPlayerSpecs   = {}
    cachedPlayerSpecIDs = {}

    local isClassic = sfui.isClassic or not (sfui.has and sfui.has.specializations)

    if isClassic then
        local classFilename, classID = sfui.talents.get_player_class()
        if not classFilename or classFilename == "" or type(classFilename) ~= "string" then
            local _, eng, cid = UnitClass("player")
            classFilename = eng
            classID = cid or classID
        end
        local vSpecID = (classFilename and CLASS_VANILLA_SPEC_MAP[classFilename])
            or (classID and CLASS_VANILLA_SPEC_MAP[classID])
        if vSpecID then
            local specInfo = sfui.talents.get_classic_talent_spec_info(vSpecID, classFilename)
            cachedPlayerSpecs[vSpecID] = {
                id          = vSpecID,
                name        = (specInfo and specInfo.name) or classFilename,
                icon        = (specInfo and specInfo.icon) or 134400,
                role        = (specInfo and specInfo.role) or "DAMAGER",
                classicRole = (specInfo and specInfo.classicRole) or "DPS",
                equivSpecID = (specInfo and specInfo.equivSpecID) or nil,
                primaryStat = 1,
                index       = 1,
            }
            cachedPlayerSpecIDs[1] = vSpecID
            return cachedPlayerSpecs, cachedPlayerSpecIDs
        end
    end

    local numSpecs = GetNumSpecializations and GetNumSpecializations() or 0
    for i = 1, numSpecs do
        local specID, name, description, icon, role, primaryStat = GetSpecializationInfo(i)
        if specID and specID > 0 then
            cachedPlayerSpecs[specID] = {
                id          = specID,
                name        = name,
                description = description,
                icon        = icon,
                role        = role,
                primaryStat = primaryStat,
                index       = i,
            }
            cachedPlayerSpecIDs[#cachedPlayerSpecIDs + 1] = specID
        end
    end

    return cachedPlayerSpecs, cachedPlayerSpecIDs
end

local function update_cached_spec_id()
    local isClassic = sfui.isClassic or not (sfui.has and sfui.has.specializations)

    if isClassic then
        local classFilename, classID = sfui.talents.get_player_class()
        if not classFilename or classFilename == "" or type(classFilename) ~= "string" then
            local _, eng, cid = UnitClass("player")
            classFilename = eng
            classID = cid or classID
        end
        local vSpecID = (classFilename and CLASS_VANILLA_SPEC_MAP[classFilename])
            or (classID and CLASS_VANILLA_SPEC_MAP[classID])
        if vSpecID and vSpecID > 0 then
            if vSpecID ~= cachedSpecID then
                cachedSpecID = vSpecID
                if sfui.colors and sfui.colors.invalidate_spec_color_cache then
                    sfui.colors.invalidate_spec_color_cache()
                elseif sfui.common and sfui.common.invalidate_spec_color_cache then
                    sfui.common.invalidate_spec_color_cache()
                end
                if sfui.common and sfui.common.invalidate_panels_cache then
                    sfui.common.invalidate_panels_cache()
                end
            end
            return
        end
    end

    local spec = GetSpecialization and GetSpecialization()
    cachedSpecIndex = spec or 0
    if spec and spec > 0 then
        local specID = select(1, GetSpecializationInfo(spec))
        if specID and specID > 0 then
            if specID ~= cachedSpecID then
                cachedSpecID = specID
                if sfui.colors and sfui.colors.invalidate_spec_color_cache then
                    sfui.colors.invalidate_spec_color_cache()
                elseif sfui.common and sfui.common.invalidate_spec_color_cache then
                    sfui.common.invalidate_spec_color_cache()
                end
                if sfui.common and sfui.common.invalidate_panels_cache then
                    sfui.common.invalidate_panels_cache()
                end
            end
            return
        end
    end

    -- Fallback for low-level characters without a chosen specialization
    local classFilename, classID = sfui.talents.get_player_class()
    if not classFilename or classFilename == "" or type(classFilename) ~= "string" then
        local _, eng, cid = UnitClass("player")
        classFilename = eng
        classID = cid or classID
    end
    local fallbackSpecID = (classFilename and CLASS_VANILLA_SPEC_MAP[classFilename])
        or (classID and CLASS_VANILLA_SPEC_MAP[classID])
    if fallbackSpecID and fallbackSpecID > 0 then
        if fallbackSpecID ~= cachedSpecID then
            cachedSpecID = fallbackSpecID
            if sfui.colors and sfui.colors.invalidate_spec_color_cache then
                sfui.colors.invalidate_spec_color_cache()
            elseif sfui.common and sfui.common.invalidate_spec_color_cache then
                sfui.common.invalidate_spec_color_cache()
            end
            if sfui.common and sfui.common.invalidate_panels_cache then
                sfui.common.invalidate_panels_cache()
            end
        end
        return
    end

    cachedSpecID = 0
end
sfui.talents.update_cached_spec_id = update_cached_spec_id
sfui.common.update_cached_spec_id = update_cached_spec_id

function sfui.talents.invalidate_spec_cache()
    cachedSpecID = 0
    cachedSpecIndex = 0
    if sfui.common and sfui.common.invalidate_panels_cache then
        sfui.common.invalidate_panels_cache()
    end
    update_cached_spec_id()
end
sfui.common.invalidate_spec_cache = sfui.talents.invalidate_spec_cache

function sfui.talents.get_current_spec_id()
    local isClassic = sfui.isClassic or not (sfui.has and sfui.has.specializations)
    if not isClassic then
        local spec = (GetSpecialization and GetSpecialization()) or 0
        if (spec > 0 and spec ~= cachedSpecIndex) or cachedSpecID == 0 then
            update_cached_spec_id()
        end
    elseif cachedSpecID == 0 then
        update_cached_spec_id()
    end
    return cachedSpecID
end
sfui.common.get_current_spec_id = sfui.talents.get_current_spec_id

function sfui.talents.get_current_spec_index()
    local isClassic = sfui.isClassic or not (sfui.has and sfui.has.specializations)
    if not isClassic then
        local spec = (GetSpecialization and GetSpecialization()) or 0
        if (spec > 0 and spec ~= cachedSpecIndex) or cachedSpecIndex == 0 then
            update_cached_spec_id()
        end
    elseif cachedSpecIndex == 0 then
        update_cached_spec_id()
    end
    return cachedSpecIndex
end
sfui.common.get_current_spec_index = sfui.talents.get_current_spec_index

function sfui.talents.get_effective_loot_spec_id()
    local lootSpec = GetLootSpecialization and GetLootSpecialization() or 0
    if lootSpec and lootSpec > 0 then
        return lootSpec, false
    end
    return sfui.talents.get_current_spec_id(), true
end
sfui.common.get_effective_loot_spec_id = sfui.talents.get_effective_loot_spec_id

function sfui.talents.get_player_specs()
    local specs, specIDs = build_player_specs_cache()
    return specs, specIDs
end
sfui.common.get_player_specs = sfui.talents.get_player_specs

--- Returns spec options specifically for spec colors UI.
function sfui.talents.get_spec_color_options()
    local isClassic = sfui.isClassic or not (sfui.has and sfui.has.specializations)

    if not isClassic then
        return sfui.talents.get_player_specs()
    end

    local classFilename, classID = sfui.talents.get_player_class()
    if not classFilename or classFilename == "" or type(classFilename) ~= "string" then
        local _, eng, cid = UnitClass("player")
        classFilename = eng
        classID = cid or classID
    end
    local vSpecID = (classFilename and CLASS_VANILLA_SPEC_MAP[classFilename])
        or (classID and CLASS_VANILLA_SPEC_MAP[classID])
    local treeSpecs = vSpecID and CLASSIC_TREE_SPECS[vSpecID]
    if not treeSpecs then
        return sfui.talents.get_player_specs()
    end

    local resultSpecs = {}
    local resultIDs = {}
    for treeIdx = 1, 3 do
        local entry = treeSpecs[treeIdx]
        if entry and entry.specID then
            local sID = entry.specID
            local name = entry.name
            local icon = entry.icon

            if GetTalentTabInfo then
                local r1, r2, r3, r4 = GetTalentTabInfo(treeIdx)
                local tabName = (type(r1) == "string" and r1) or (type(r2) == "string" and r2)
                local tabIcon = (type(r2) == "number" and r2) or (type(r4) == "number" and r4)
                if tabName and tabName ~= "" then name = tabName end
                if tabIcon and tabIcon > 0 then icon = tabIcon end
            end

            name = name and string.lower(name) or ("tree " .. treeIdx)

            resultSpecs[sID] = {
                id          = sID,
                name        = name,
                icon        = icon or 134400,
                role        = (entry.role == "TANK" and "TANK") or (entry.role == "HEAL" and "HEALER") or "DAMAGER",
                classicRole = entry.role,
                treeIndex   = treeIdx,
            }
            resultIDs[#resultIDs + 1] = sID
        end
    end
    return resultSpecs, resultIDs
end
sfui.common.get_spec_color_options = sfui.talents.get_spec_color_options

function sfui.talents.get_spec_info(specID)
    if not specID or specID == 0 then return nil end
    local specs = sfui.talents.get_player_specs()
    if specs and specs[specID] then
        local s = specs[specID]
        return s.id, s.name, nil, s.icon, s.role, s.primaryStat
    end
    if CLASSIC_SPEC_LOOKUP[specID] then
        local c = CLASSIC_SPEC_LOOKUP[specID]
        return c.specID, c.name, nil, c.icon, (c.role == "TANK" and "TANK") or (c.role == "HEAL" and "HEALER") or "DAMAGER", 1
    end
    return GetSpecializationInfoByID(specID)
end
sfui.common.get_spec_info = sfui.talents.get_spec_info

function sfui.talents.get_spec_name(specID)
    if not specID or specID == 0 then return "Current Spec" end
    local specs = sfui.talents.get_player_specs()
    if specs and specs[specID] and specs[specID].name then
        return specs[specID].name
    end
    if CLASSIC_SPEC_LOOKUP[specID] then
        return CLASSIC_SPEC_LOOKUP[specID].name
    end
    local _, name = GetSpecializationInfoByID(specID)
    return name or ("Spec " .. specID)
end
sfui.common.get_spec_name = sfui.talents.get_spec_name

function sfui.talents.get_spec_icon(specID)
    if not specID or specID == 0 then return nil end
    local specs = sfui.talents.get_player_specs()
    if specs and specs[specID] and specs[specID].icon then
        return specs[specID].icon
    end
    if CLASSIC_SPEC_LOOKUP[specID] then
        return CLASSIC_SPEC_LOOKUP[specID].icon
    end
    local _, _, _, icon = GetSpecializationInfoByID(specID)
    return icon
end
sfui.common.get_spec_icon = sfui.talents.get_spec_icon

function sfui.talents.get_spec_role(specIDorIndex)
    if not specIDorIndex or specIDorIndex == 0 or specIDorIndex == "NONE" then
        return "DAMAGER"
    end
    if SfuiDB and SfuiDB.gear and SfuiDB.gear[specIDorIndex] then
        local sdb = SfuiDB.gear[specIDorIndex]
        if sdb.role and sdb.role ~= "" and sdb.role ~= "NONE" then
            return sdb.role
        elseif sdb.classic_role then
            if sdb.classic_role == "TANK" then return "TANK"
            elseif sdb.classic_role == "HEAL" then return "HEALER"
            elseif sdb.classic_role == "DPS" then return "DAMAGER"
            end
        elseif sdb.is_tank or sdb.armor_ilvl_prio then
            return "TANK"
        elseif sdb.is_healer then
            return "HEALER"
        end
    end
    if type(specIDorIndex) == "number" and specIDorIndex <= 4 then
        if GetSpecializationRole then
            local role = GetSpecializationRole(specIDorIndex)
            if role and role ~= "NONE" then return role end
        end
        local _, _, _, _, role = GetSpecializationInfo(specIDorIndex)
        if role and role ~= "NONE" then return role end
    else
        local specs = sfui.talents.get_player_specs()
        if specs and specs[specIDorIndex] and specs[specIDorIndex].role then
            return specs[specIDorIndex].role
        end
        local _, _, _, _, role = GetSpecializationInfoByID(specIDorIndex)
        if role and role ~= "NONE" then return role end
    end
    return "DAMAGER"
end
sfui.common.get_spec_role = sfui.talents.get_spec_role

-- ────────────────────────────────────────────────────────────────────────────
-- Talent & Trait Inspection Engine
-- ────────────────────────────────────────────────────────────────────────────
local _talentCache = {}
local _talentCacheConfigID = nil

local function invalidate_talent_cache()
    table.wipe(_talentCache)
    _talentCacheConfigID = nil

    cachedSpecID = 0
    cachedSpecIndex = 0
    update_cached_spec_id()

    if sfui.highest and sfui.highest.ClearValidationCache then
        sfui.highest.ClearValidationCache()
    end
    if sfui.common and sfui.common.invalidate_panels_cache then
        sfui.common.invalidate_panels_cache()
    end
    if sfui.colors and sfui.colors.invalidate_spec_color_cache then
        sfui.colors.invalidate_spec_color_cache()
    elseif sfui.common and sfui.common.invalidate_spec_color_cache then
        sfui.common.invalidate_spec_color_cache()
    end

    if sfui.isClassic then
        sfui.talents.invalidate_player_specs_cache()
        sfui.talents.get_player_specs()
        if sfui.gear and sfui.gear.UpdateStatUI then
            sfui.gear.UpdateStatUI()
        end
        if SfuiGearManagerFrame and SfuiGearManagerFrame.tabBtns and sfui.talents.get_spec_icon then
            for id, btn in pairs(SfuiGearManagerFrame.tabBtns) do
                if btn.tex then
                    local ic = sfui.talents.get_spec_icon(id)
                    if ic then
                        btn.tex:SetTexture(ic)
                    end
                end
            end
        end
    end
end

sfui.events.RegisterEvent("PLAYER_TALENT_UPDATE", invalidate_talent_cache)
sfui.events.RegisterEvent("TRAIT_CONFIG_UPDATED", invalidate_talent_cache)
sfui.events.RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", invalidate_talent_cache)
sfui.events.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", invalidate_talent_cache)
sfui.events.RegisterEvent("SPEC_INVOLUNTARILY_CHANGED", invalidate_talent_cache)
sfui.events.RegisterEvent("CHARACTER_POINTS_CHANGED", invalidate_talent_cache)
sfui.events.RegisterEvent("TRAIT_TREE_CURRENCY_INFO_UPDATED", invalidate_talent_cache)
sfui.events.RegisterEvent("PLAYER_LEVEL_UP", invalidate_talent_cache)

--- Checks if a talent or spell is active/known by the player.
function sfui.talents.is_talent_known(targetSpellID)
    if not targetSpellID or targetSpellID <= 0 then return false end

    -- 1. Direct spellbook / known checks
    if IsPlayerSpell and IsPlayerSpell(targetSpellID) then return true end
    if IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(targetSpellID) then return true end
    if IsSpellKnown and IsSpellKnown(targetSpellID) then return true end
    if C_Spell and C_Spell.IsSpellLearned and C_Spell.IsSpellLearned(targetSpellID) then return true end

    -- 2. Trait / Class Talent tree inspection for passive talents
    local C_ClassTalents = _G.C_ClassTalents
    local C_Traits = _G.C_Traits
    if not C_ClassTalents or not C_ClassTalents.GetActiveConfigID or not C_Traits or not C_Traits.GetConfigInfo then
        return false
    end

    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID or configID <= 0 then return false end

    if _talentCacheConfigID ~= configID then
        table.wipe(_talentCache)
        _talentCacheConfigID = configID

        local configInfo = C_Traits.GetConfigInfo(configID)
        if configInfo and configInfo.treeIDs then
            for _, treeID in ipairs(configInfo.treeIDs) do
                local nodes = C_Traits.GetTreeNodes and C_Traits.GetTreeNodes(treeID)
                if nodes then
                    for _, nodeID in ipairs(nodes) do
                        local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
                        if nodeInfo and ((nodeInfo.activeRank and nodeInfo.activeRank > 0) or (nodeInfo.currentRank and nodeInfo.currentRank > 0)) then
                            if nodeInfo.activeEntry then
                                local entryInfo = C_Traits.GetEntryInfo(configID, nodeInfo.activeEntry.entryID)
                                if entryInfo and entryInfo.definitionID then
                                    local defInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
                                    if defInfo and defInfo.spellID and defInfo.spellID > 0 then
                                        _talentCache[defInfo.spellID] = true
                                    end
                                end
                            end
                            if nodeInfo.entryIDsWithCommittedRanks then
                                for _, entryID in ipairs(nodeInfo.entryIDsWithCommittedRanks) do
                                    local entry = C_Traits.GetEntryInfo(configID, entryID)
                                    if entry and entry.definitionID then
                                        local defInfo = C_Traits.GetDefinitionInfo(entry.definitionID)
                                        if defInfo and defInfo.spellID and defInfo.spellID > 0 then
                                            _talentCache[defInfo.spellID] = true
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return _talentCache[targetSpellID] == true
end
sfui.common.is_talent_known = sfui.talents.is_talent_known

local function on_login_or_enter()
    sfui.talents.get_player_class()
    cachedSpecID = 0
    cachedSpecIndex = 0
    update_cached_spec_id()
    build_player_specs_cache()
end
sfui.events.RegisterEvent("PLAYER_LOGIN", on_login_or_enter)
sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", on_login_or_enter)
