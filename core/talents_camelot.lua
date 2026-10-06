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
    local isCamelot = (tocVersionNum >= 16000 and tocVersionNum < 20000) or (projectID == 18)
    isRetail = (projectID == 1) and not isCamelot
end

if isRetail then
    return
end

local _G = _G
local UnitLevel = _G.UnitLevel
local UnitClass = _G.UnitClass
local C_SpecializationInfo = _G.C_SpecializationInfo

local ipairs, pairs, type, tostring = _G.ipairs, _G.pairs, _G.type, _G.tostring

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
for classSpecID, trees in pairs(CLASSIC_TREE_SPECS) do
    for treeIdx, info in ipairs(trees) do
        local camelotID = classSpecID * 10 + treeIdx
        local entry = {
            specID      = info.specID,
            camelotID   = camelotID,
            classSpecID = classSpecID,
            name        = info.name,
            icon        = info.icon,
            role        = info.role,
        }
        if info.specID then
            CLASSIC_SPEC_LOOKUP[info.specID] = entry
        end
        CLASSIC_SPEC_LOOKUP[camelotID] = entry
    end
end

-- Dedicated 4th pseudo-spec for Druid Guardian Bear (mirrors retail spec 104)
CLASSIC_SPEC_LOOKUP[14844] = {
    specID      = 104,
    camelotID   = 14844,
    classSpecID = 1484,
    name        = "guardian",
    icon        = 132276,
    role        = "TANK",
}
CLASSIC_SPEC_LOOKUP[104] = CLASSIC_SPEC_LOOKUP[14844]

sfui.talents.CLASS_VANILLA_SPEC_MAP = CLASS_VANILLA_SPEC_MAP
sfui.common.CLASS_VANILLA_SPEC_MAP  = CLASS_VANILLA_SPEC_MAP
sfui.talents.CLASSIC_TREE_SPECS     = CLASSIC_TREE_SPECS
sfui.common.CLASSIC_TREE_SPECS      = CLASSIC_TREE_SPECS
sfui.talents.CLASSIC_SPEC_LOOKUP    = CLASSIC_SPEC_LOOKUP
sfui.common.CLASSIC_SPEC_LOOKUP     = CLASSIC_SPEC_LOOKUP

-- 4. Talent Known Resolver (Classic / Camelot spells)
local function CamelotTalentKnownResolver(targetSpellID)
    if not targetSpellID or targetSpellID <= 0 then return false end
    local C_SpellBook = _G.C_SpellBook
    local bank = (_G.Enum and _G.Enum.SpellBookSpellBank and _G.Enum.SpellBookSpellBank.Player) or 1
    if C_SpellBook then
        if C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(targetSpellID, bank) then return true end
        if C_SpellBook.IsSpellInSpellBook and C_SpellBook.IsSpellInSpellBook(targetSpellID, bank, false) then return true end
        if C_SpellBook.IsSpellInSpellBook and C_SpellBook.IsSpellInSpellBook(targetSpellID, bank, true) then return true end
        if C_SpellBook.IsSpellKnownOrInSpellBook and C_SpellBook.IsSpellKnownOrInSpellBook(targetSpellID, bank, true) then return true end
        if C_SpellBook.FindSpellBookSlotForSpell and C_SpellBook.FindSpellBookSlotForSpell(targetSpellID, true, true, false, false) then return true end
    end
    if _G.IsPlayerSpell and _G.IsPlayerSpell(targetSpellID) then return true end
    if _G.IsSpellKnown and _G.IsSpellKnown(targetSpellID) then return true end
    local C_Spell = _G.C_Spell
    if C_Spell and C_Spell.IsSpellLearned and C_Spell.IsSpellLearned(targetSpellID) then return true end
    return false
end
sfui.talents._talentKnownResolver = CamelotTalentKnownResolver

local _classicTreeScratch = {
    [1] = { name = nil, icon = nil, points = 0, role = nil, specID = nil },
    [2] = { name = nil, icon = nil, points = 0, role = nil, specID = nil },
    [3] = { name = nil, icon = nil, points = 0, role = nil, specID = nil },
}

--- Predicts specialization, role, and dominant talent tree for Classic / Camelot.
--- Uses Blizzard's Camelot talent system (C_SpecializationInfo config IDs + C_Traits group currency).
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
        entry.specID = nil
    end

    local activeGroup = (C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup and C_SpecializationInfo.GetActiveSpecGroup()) or 1
    local configID = C_SpecializationInfo and C_SpecializationInfo.GetCombatConfigIDForSpecGroup and C_SpecializationInfo.GetCombatConfigIDForSpecGroup(activeGroup)

    local curSpecIdx = nil
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
        curSpecIdx = C_SpecializationInfo.GetSpecialization(false, false, activeGroup)
            or C_SpecializationInfo.GetSpecialization()
        if curSpecIdx and (curSpecIdx < 1 or curSpecIdx > 3) then
            curSpecIdx = nil
        end
    end

    local totalPoints = 0
    local maxPoints = 0
    local dominantTree = curSpecIdx or 1

    -- Query Camelot trait tree & currency info (Blizzard's native implementation on Camelot)
    local C_Traits = _G.C_Traits
    if configID and C_Traits and C_Traits.GetConfigInfo and C_Traits.GetGroupDisplayInfoByTreeID then
        local configInfo = C_Traits.GetConfigInfo(configID)
        local treeIDs = configInfo and configInfo.treeIDs
        local treeID = treeIDs and treeIDs[1]
        if treeID then
            local displayInfos = C_Traits.GetGroupDisplayInfoByTreeID(treeID)
            if displayInfos and #displayInfos > 0 then
                local groupIDs = {}
                for _, di in ipairs(displayInfos) do
                    local gid = di.groupID or di.traitNodeGroupID
                    if gid then
                        table.insert(groupIDs, gid)
                    end
                end

                local groupInfos = C_Traits.GetGroupCurrencyInfo and C_Traits.GetGroupCurrencyInfo(configID, groupIDs)
                local function findGroupSpent(gid)
                    if not groupInfos or not gid then return 0 end
                    for _, gi in ipairs(groupInfos) do
                        if (gi.traitNodeGroupID and gi.traitNodeGroupID == gid) or (gi.groupID and gi.groupID == gid) then
                            local cInfo = gi.currencyInfos and gi.currencyInfos[1]
                            return (cInfo and cInfo.spent) or 0
                        end
                    end
                    return 0
                end

                for i, di in ipairs(displayInfos) do
                    local gid = di.groupID or di.traitNodeGroupID
                    local spent = findGroupSpent(gid)
                    local treeIdx = i
                    if di.orderIndex then
                        if di.orderIndex >= 0 and di.orderIndex <= 2 then
                            treeIdx = di.orderIndex + 1
                        elseif di.orderIndex >= 1 and di.orderIndex <= 3 then
                            treeIdx = di.orderIndex
                        end
                    end

                    if treeIdx and _classicTreeScratch[treeIdx] then
                        local entry = _classicTreeScratch[treeIdx]
                        entry.name = di.displayName
                        entry.icon = di.icon
                        entry.points = spent
                        totalPoints = totalPoints + spent

                        if spent > maxPoints then
                            maxPoints = spent
                            dominantTree = treeIdx
                        end
                    end
                end
            end
        end
    end

    -- Tie-breaking: if multiple trees have the same maxPoints, prefer curSpecIdx if it matches
    if curSpecIdx and _classicTreeScratch[curSpecIdx] and _classicTreeScratch[curSpecIdx].points == maxPoints and maxPoints > 0 then
        dominantTree = curSpecIdx
    end

    -- Untalented (level < 10 or 0 talent points spent): return class-level defaults
    if playerLevel < 10 or totalPoints == 0 then
        return {
            name         = className,
            icon         = classIcon,
            classicRole  = defaultRole,
            role         = (defaultRole == "TANK" and "TANK") or (defaultRole == "HEAL" and "HEALER") or "DAMAGER",
            equivSpecID  = nil,
            totalPoints  = totalPoints,
            dominantTree = curSpecIdx or dominantTree or 1,
        }
    end

    local domData = _classicTreeScratch[dominantTree]
    local treeName = domData and domData.name
    local treeIcon = domData and domData.icon

    local treeDef = CLASSIC_TREE_SPECS[vSpecID] and CLASSIC_TREE_SPECS[vSpecID][dominantTree]
    local treeRole = (treeDef and treeDef.role) or defaultRole

    -- Druid Feral (tree 2): differentiate between bear (TANK) and cat (DPS)
    if vSpecID == 1484 and dominantTree == 2 then
        local isBear = sfui.talents.is_bear_form_spec and sfui.talents.is_bear_form_spec()
        if isBear then
            treeRole = "TANK"
        else
            treeRole = "DPS"
        end
    end

    local assignedRole = _G.UnitGroupRolesAssigned and _G.UnitGroupRolesAssigned("player")
    local predictedRole = treeRole
    if assignedRole and assignedRole ~= "NONE" then
        if assignedRole == "TANK" then
            predictedRole = "TANK"
        elseif assignedRole == "HEALER" then
            predictedRole = "HEAL"
        end
    end

    local finalRole = (predictedRole == "TANK" and "TANK") or (predictedRole == "HEAL" and "HEALER") or "DAMAGER"
    local classicRole = predictedRole
    local resolvedEquivID = treeDef and treeDef.specID
    if vSpecID == 1484 and dominantTree == 2 then
        if finalRole == "TANK" then
            classicRole = "bear"
            treeName = "guardian"
            treeIcon = 132276
            resolvedEquivID = 104
        else
            classicRole = "cat"
        end
    end

    return {
        name         = treeName or className,
        icon         = treeIcon or classIcon,
        classicRole  = classicRole,
        role         = finalRole,
        equivSpecID  = resolvedEquivID,
        totalPoints  = totalPoints,
        dominantTree = dominantTree,
    }
end

sfui.talents.get_classic_talent_spec_info = get_classic_talent_spec_info
sfui.common.get_classic_talent_spec_info  = get_classic_talent_spec_info

-- ────────────────────────────────────────────────────────────────────────────
-- Pluggable Providers Registration
-- ────────────────────────────────────────────────────────────────────────────

-- 1. Spec Resolver: Resolves active spec to a Camelot tree spec ID (classID * 10 + treeIdx).
-- e.g. Warlock with most points in Affliction (tree 1) → 14901
local function CamelotSpecResolver()
    local classFilename, _ = sfui.talents.get_player_class()
    local vSpecID = classFilename and CLASS_VANILLA_SPEC_MAP[classFilename]
    if not vSpecID then return 0, 0, "DAMAGER" end

    local specInfo = get_classic_talent_spec_info()
    local dominantTree = (specInfo and specInfo.dominantTree) or 1
    local role = (specInfo and specInfo.role) or "DAMAGER"

    -- Camelot canonical ID: classID * 10 + treeIndex (e.g. 14901 = Warlock Affliction)
    -- For Druid Feral (tree 2): if resolved to Bear Tank, use dedicated 14844 ID
    local camelotID = vSpecID * 10 + dominantTree
    if vSpecID == 1484 and dominantTree == 2 and role == "TANK" then
        camelotID = 14844
    end
    return camelotID, dominantTree, role
end
sfui.talents._specResolver = CamelotSpecResolver

-- 2. Specs Cache Builder
-- Returns Camelot tree spec IDs in the form classID * 10 + treeIndex.
-- e.g. Warlock → { [14901]=Affliction, [14902]=Demonology, [14903]=Destruction }
-- retailSpecID is stored as metadata for icon/name resolution only.
local function CamelotSpecsCacheBuilder()
    local classFilename, _ = sfui.talents.get_player_class()
    local vSpecID = classFilename and CLASS_VANILLA_SPEC_MAP[classFilename]
    if not vSpecID then return {}, {} end

    local specs = {}
    local specIDs = {}

    local C_Traits = _G.C_Traits
    local activeGroup = (C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup and C_SpecializationInfo.GetActiveSpecGroup()) or 1
    local configID = C_SpecializationInfo and C_SpecializationInfo.GetCombatConfigIDForSpecGroup and C_SpecializationInfo.GetCombatConfigIDForSpecGroup(activeGroup)

    if configID and C_Traits and C_Traits.GetConfigInfo and C_Traits.GetGroupDisplayInfoByTreeID then
        local configInfo = C_Traits.GetConfigInfo(configID)
        local treeID = configInfo and configInfo.treeIDs and configInfo.treeIDs[1]
        if treeID then
            local displayInfos = C_Traits.GetGroupDisplayInfoByTreeID(treeID)
            if displayInfos then
                for i, di in ipairs(displayInfos) do
                    local treeIdx = i
                    if di.orderIndex then
                        if di.orderIndex >= 0 and di.orderIndex <= 2 then
                            treeIdx = di.orderIndex + 1
                        elseif di.orderIndex >= 1 and di.orderIndex <= 3 then
                            treeIdx = di.orderIndex
                        end
                    end
                    local sID = vSpecID * 10 + treeIdx
                    local name = di.displayName and string.lower(di.displayName) or ("tree " .. treeIdx)
                    local icon = di.icon or 134400
                    local treeDef = CLASSIC_TREE_SPECS[vSpecID] and CLASSIC_TREE_SPECS[vSpecID][treeIdx]
                    local tRole = (treeDef and treeDef.role) or "DPS"
                    if vSpecID == 1484 and treeIdx == 2 then
                        local isBear = sfui.talents.is_bear_form_spec and sfui.talents.is_bear_form_spec()
                        if isBear then
                            tRole = "TANK"
                        end
                    end
                    local stdRole = (tRole == "TANK" and "TANK") or (tRole == "HEAL" and "HEALER") or "DAMAGER"

                    specs[sID] = {
                        id           = sID,
                        name         = name,
                        description  = "",
                        icon         = icon,
                        role         = stdRole,
                        classicRole  = tRole,
                        index        = treeIdx,
                        classID      = vSpecID,
                        treeIndex    = treeIdx,
                        retailSpecID = treeDef and treeDef.specID,
                    }
                    specIDs[#specIDs + 1] = sID

                    -- Add dedicated 14844 spec profile for Guardian Bear
                    if vSpecID == 1484 and treeIdx == 2 then
                        specs[14844] = {
                            id           = 14844,
                            name         = "guardian",
                            description  = "",
                            icon         = 132276,
                            role         = "TANK",
                            classicRole  = "bear",
                            index        = 2,
                            classID      = 1484,
                            treeIndex    = 2,
                            retailSpecID = 104,
                        }
                        specIDs[#specIDs + 1] = 14844
                    end
                end
            end
        end
    end

    -- Add dedicated 1484 spec profile for Druid Humanoid / Mana
    if vSpecID == 1484 and not specs[1484] then
        specs[1484] = {
            id           = 1484,
            name         = "mana (humanoid)",
            description  = "",
            icon         = 136096,
            role         = "HEALER",
            classicRole  = "mana",
            index        = 0,
            classID      = 1484,
            treeIndex    = 0,
            retailSpecID = 1484,
        }
        specIDs[#specIDs + 1] = 1484
    end

    return specs, specIDs
end
sfui.talents._specsCacheBuilder = CamelotSpecsCacheBuilder

-- 3. Spec Color Options Builder (Returns specs and IDs for settings tab)
sfui.talents._specColorOptionsBuilder = CamelotSpecsCacheBuilder


