local addonName, addon = ...
sfui = sfui or {}
sfui.talents = sfui.talents or {}
sfui.common = sfui.common or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/core/talents_camelot.lua
--  Classic Forever / Camelot Specialization & Dominant Talent Tree Solver
-- ══════════════════════════════════════════════════════════════════════════════

local isRetail = sfui.isRetail
if isRetail == nil then
    local projectID = _G.WOW_PROJECT_ID or 1
    local _, _, _, tocVersionNum = _G.GetBuildInfo()
    tocVersionNum = tonumber(tocVersionNum) or 0
    local isForever = (tocVersionNum >= 16000 and tocVersionNum < 20000)
    isRetail = (projectID == 1) and not isForever
end

if isRetail then
    return
end

local _G = _G
local UnitLevel = _G.UnitLevel
local UnitClass = _G.UnitClass
local GetTalentTabInfo = _G.GetTalentTabInfo
local C_SpecializationInfo = _G.C_SpecializationInfo
local GetSpecializationInfoByID = (_G.C_SpecializationInfo and _G.C_SpecializationInfo.GetSpecializationInfoByID) or _G.GetSpecializationInfoByID

local ipairs, pairs, type, tonumber, tostring = _G.ipairs, _G.pairs, _G.type, _G.tonumber, _G.tostring
local math_min = math.min

-- ────────────────────────────────────────────────────────────────────────────
-- Classic Class & Spec Mappings
-- ────────────────────────────────────────────────────────────────────────────
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

sfui.talents.CLASS_VANILLA_SPEC_MAP = CLASS_VANILLA_SPEC_MAP
sfui.common.CLASS_VANILLA_SPEC_MAP  = CLASS_VANILLA_SPEC_MAP
sfui.talents.CLASSIC_TREE_SPECS     = CLASSIC_TREE_SPECS
sfui.common.CLASSIC_TREE_SPECS      = CLASSIC_TREE_SPECS
sfui.talents.CLASSIC_SPEC_LOOKUP    = CLASSIC_SPEC_LOOKUP
sfui.common.CLASSIC_SPEC_LOOKUP     = CLASSIC_SPEC_LOOKUP

local _classicTreeScratch = {
    [1] = { name = nil, icon = nil, points = 0 },
    [2] = { name = nil, icon = nil, points = 0 },
    [3] = { name = nil, icon = nil, points = 0 },
}
local _classicGroupIDsScratch = {}

--- Predicts specialization, role, and dominant talent tree for Classic / Camelot.
--- Returns Class icon when untalented or level < 10, or dominant tree spec icon when points are spent.
local function get_classic_talent_spec_info(vSpecID, classFilename)
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

    if not vSpecID or vSpecID == 0 then
        vSpecID = (classFilename and CLASS_VANILLA_SPEC_MAP[classFilename])
    end

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

    local firstTreeMapping = CLASSIC_TREE_SPECS[vSpecID] and CLASSIC_TREE_SPECS[vSpecID][1]
    local fallbackSpecID = firstTreeMapping and firstTreeMapping.specID

    -- Below level 10: Untalented, use class icon and default role
    if playerLevel < 10 then
        return {
            name         = className,
            icon         = classIcon,
            classicRole  = defaultRole,
            role         = (defaultRole == "TANK" and "TANK") or (defaultRole == "HEAL" and "HEALER") or "DAMAGER",
            equivSpecID  = fallbackSpecID,
            totalPoints  = 0,
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
                    for i = 1, math_min(3, #displayInfos) do
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
            name         = className,
            icon         = classIcon,
            classicRole  = defaultRole,
            role         = (defaultRole == "TANK" and "TANK") or (defaultRole == "HEAL" and "HEALER") or "DAMAGER",
            equivSpecID  = fallbackSpecID,
            totalPoints  = 0,
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
    local equivSpecID = (mapping and mapping.specID) or fallbackSpecID

    if equivSpecID and (not treeName or not treeIcon) and GetSpecializationInfoByID then
        local _, sName, _, sIcon = GetSpecializationInfoByID(equivSpecID)
        treeName = treeName or sName
        treeIcon = treeIcon or sIcon
    end

    return {
        name         = treeName or className,
        icon         = treeIcon or classIcon,
        classicRole  = predictedRole,
        role         = (predictedRole == "TANK" and "TANK") or (predictedRole == "HEAL" and "HEALER") or "DAMAGER",
        equivSpecID  = equivSpecID,
        totalPoints  = totalPoints,
        dominantTree = dominantIdx,
    }
end

sfui.talents.get_classic_talent_spec_info = get_classic_talent_spec_info
sfui.common.get_classic_talent_spec_info  = get_classic_talent_spec_info

-- ────────────────────────────────────────────────────────────────────────────
-- Pluggable Providers Registration
-- ────────────────────────────────────────────────────────────────────────────

-- 1. Spec Resolver: Resolves active spec to the dominant tree spec ID (71, 72, 73, etc.)
local function CamelotSpecResolver()
    local specInfo = get_classic_talent_spec_info()
    if specInfo and specInfo.equivSpecID and specInfo.equivSpecID > 0 then
        return specInfo.equivSpecID, specInfo.dominantTree or 1, specInfo.role or "DAMAGER"
    end

    local classFilename, classID = sfui.talents.get_player_class()
    local vSpecID = (classFilename and CLASS_VANILLA_SPEC_MAP[classFilename]) or (classID and CLASS_VANILLA_SPEC_MAP[classID])
    local firstMapping = vSpecID and CLASSIC_TREE_SPECS[vSpecID] and CLASSIC_TREE_SPECS[vSpecID][1]
    if firstMapping and firstMapping.specID then
        return firstMapping.specID, 1, firstMapping.role or "DAMAGER"
    end
    return 0, 0, "DAMAGER"
end
sfui.talents._specResolver = CamelotSpecResolver

-- 2. Specs Cache Builder
local function CamelotSpecsCacheBuilder()
    local classFilename, classID = sfui.talents.get_player_class()
    local vSpecID = (classFilename and CLASS_VANILLA_SPEC_MAP[classFilename]) or (classID and CLASS_VANILLA_SPEC_MAP[classID])
    local treeSpecs = vSpecID and CLASSIC_TREE_SPECS[vSpecID]

    local specs = {}
    local specIDs = {}

    if treeSpecs then
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

                specs[sID] = {
                    id          = sID,
                    name        = name,
                    description = "",
                    icon        = icon or 134400,
                    role        = (entry.role == "TANK" and "TANK") or (entry.role == "HEAL" and "HEALER") or "DAMAGER",
                    classicRole = entry.role,
                    index       = treeIdx,
                }
                specIDs[#specIDs + 1] = sID
            end
        end
    end

    return specs, specIDs
end
sfui.talents._specsCacheBuilder = CamelotSpecsCacheBuilder

-- 3. Spec Color Options Builder (Returns specs and IDs for settings tab)
sfui.talents._specColorOptionsBuilder = CamelotSpecsCacheBuilder

-- 4. Talent Known Resolver (Classic spells)
local function CamelotTalentKnownResolver(targetSpellID)
    if not targetSpellID or targetSpellID <= 0 then return false end
    if _G.IsPlayerSpell and _G.IsPlayerSpell(targetSpellID) then return true end
    if _G.IsSpellKnown and _G.IsSpellKnown(targetSpellID) then return true end
    local C_Spell = _G.C_Spell
    if C_Spell and C_Spell.IsSpellLearned and C_Spell.IsSpellLearned(targetSpellID) then return true end
    return false
end
sfui.talents._talentKnownResolver = CamelotTalentKnownResolver
