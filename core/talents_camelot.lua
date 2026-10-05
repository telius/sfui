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

-- Key signature talents and iconic spells for Classic talent trees
local CLASSIC_TREE_SIGNATURE_SPELLS = {
    [1491] = { -- Warrior
        [1] = { 12294, 12328, 46924 },               -- Arms: Mortal Strike, Sweeping Strikes, Bladestorm
        [2] = { 23881, 12292, 46917 },               -- Fury: Bloodthirst, Death Wish, Titan's Grip
        [3] = { 23922, 12809, 20243, 46968, 12975 }, -- Protection: Shield Slam, Concussion Blow, Devastate, Shockwave, Last Stand
    },
    [1486] = { -- Paladin
        [1] = { 20473, 20216, 53563, 20210, 20257 },                         -- Holy: Holy Shock, Divine Favor, Beacon of Light, Illumination, Divine Intellect
        [2] = { 20925, 20911, 25899, 31935, 53600, 53595, 20127, 31850, 20468, 20196 }, -- Protection: Holy Shield, Blessing of Sanctuary, Greater Blessing of Sanctuary, Avenger's Shield, Shield of the Righteous, Hammer of the Righteous, Redoubt, Ardent Defender, Imp Righteous Fury, 1H Weapon Spec
        [3] = { 20066, 20375, 35395, 53385, 20218, 31892, 20049 },          -- Retribution: Repentance, Seal of Command, Crusader Strike, Divine Storm, Sanctity Aura, Seal of Blood, Vengeance
    },
    [1485] = { -- Hunter
        [1] = { 19574, 19577, 34692 },               -- Beast Mastery: Bestial Wrath, Intimidation, The Beast Within
        [2] = { 19434, 53209, 19506, 34490 },        -- Marksmanship: Aimed Shot, Chimera Shot, Trueshot Aura, Silencing Shot
        [3] = { 53301, 19386, 3674, 19503 },         -- Survival: Explosive Shot, Wyvern Sting, Black Arrow, Scatter Shot
    },
    [1488] = { -- Rogue
        [1] = { 1329, 14177, 51662 },                -- Assassination: Mutilate, Cold Blood, Hunger For Blood
        [2] = { 13750, 13877, 51690 },               -- Combat: Adrenaline Rush, Blade Flurry, Killing Spree
        [3] = { 36554, 14183, 51713, 14278, 16511 }, -- Subtlety: Shadowstep, Premeditation, Shadow Dance, Ghostly Strike, Hemorrhage
    },
    [1487] = { -- Priest
        [1] = { 47540, 10060, 33206, 14751 },        -- Discipline: Penance, Power Infusion, Pain Suppression, Inner Focus
        [2] = { 34861, 15237, 47788, 20711 },        -- Holy: Circle of Healing, Holy Nova, Guardian Spirit, Spirit of Redemption
        [3] = { 15473, 34914, 15407, 47585 },        -- Shadow: Shadowform, Vampiric Touch, Mind Flay, Dispersion
    },
    [1489] = { -- Shaman
        [1] = { 16166, 51505, 51490 },               -- Elemental: Elemental Mastery, Lava Burst, Thunderstorm
        [2] = { 17364, 60103, 30823, 51533 },        -- Enhancement: Stormstrike, Lava Lash, Shamanistic Rage, Feral Spirit
        [3] = { 16190, 61295, 16188, 974 },          -- Restoration: Mana Tide Totem, Riptide, Nature's Swiftness, Earth Shield
    },
    [1482] = { -- Mage
        [1] = { 12042, 12043, 44425 },               -- Arcane: Arcane Power, Presence of Mind, Arcane Barrage
        [2] = { 11366, 11129, 44457, 11113 },        -- Fire: Pyroblast, Combustion, Living Bomb, Blast Wave
        [3] = { 11426, 11958, 44572, 31687 },        -- Frost: Ice Barrier, Cold Snap, Deep Freeze, Summon Water Elemental
    },
    [1490] = { -- Warlock
        [1] = { 30108, 18220, 48181, 18265 },        -- Affliction: Unstable Affliction, Dark Pact, Haunt, Siphon Life
        [2] = { 59672, 19028, 47193, 30146 },        -- Demonology: Metamorphosis, Soul Link, Demonic Empowerment, Summon Felguard
        [3] = { 50796, 17962, 17877 },               -- Destruction: Chaos Bolt, Conflagrate, Shadowburn
    },
    [1484] = { -- Druid
        [1] = { 24858, 48505, 5570, 50516 },         -- Balance: Moonkin Form, Starfall, Insect Swarm, Typhoon
        [2] = { 17007, 33876, 33878, 50334, 61336 }, -- Feral: Leader of the Pack, Mangle, Berserk, Survival Instincts
        [3] = { 33891, 18562, 48438, 17116 },        -- Restoration: Tree of Life, Swiftmend, Wild Growth, Nature's Swiftness
    },
}

local function get_tree_by_signature_spells(vSpecID)
    local sigTrees = CLASSIC_TREE_SIGNATURE_SPELLS and CLASSIC_TREE_SIGNATURE_SPELLS[vSpecID]
    if not sigTrees then return nil end
    local bestTree, maxSpells = nil, 0
    for treeIdx = 1, 3 do
        local spells = sigTrees[treeIdx]
        if spells then
            local count = 0
            for _, sID in ipairs(spells) do
                if CamelotTalentKnownResolver(sID) then
                    count = count + 1
                end
            end
            if count > maxSpells then
                maxSpells = count
                bestTree = treeIdx
            end
        end
    end
    return bestTree
end

local _classicTreeScratch = {
    [1] = { name = nil, icon = nil, points = 0 },
    [2] = { name = nil, icon = nil, points = 0 },
    [3] = { name = nil, icon = nil, points = 0 },
}

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

    local activeGroup = (C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup and C_SpecializationInfo.GetActiveSpecGroup())
        or (_G.GetActiveTalentGroup and _G.GetActiveTalentGroup()) or 1

    local curSpecIdx = nil
    local pClassID = sfui.talents.get_player_class_id()
    local specSelectionEnabled = C_SpecializationInfo and C_SpecializationInfo.IsSpecSelectionEnabled and pClassID and C_SpecializationInfo.IsSpecSelectionEnabled(pClassID)
    if specSelectionEnabled then
        if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
            curSpecIdx = C_SpecializationInfo.GetSpecialization(false, false, activeGroup)
                or C_SpecializationInfo.GetSpecialization()
        end
        if (not curSpecIdx or curSpecIdx == 0) and _G.GetSpecialization then
            curSpecIdx = _G.GetSpecialization(false, false, activeGroup)
                or _G.GetSpecialization()
        end
        if curSpecIdx and (curSpecIdx < 1 or curSpecIdx > 3) then
            curSpecIdx = nil
        end
    end

    local inspectSpecID
    if C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization then
        inspectSpecID = C_SpecializationInfo.GetInspectSpecialization("player")
    end
    local inspectTreeIdx = nil
    if inspectSpecID and inspectSpecID > 0 and CLASSIC_TREE_SPECS[vSpecID] then
        for idx = 1, 3 do
            if CLASSIC_TREE_SPECS[vSpecID][idx].specID == inspectSpecID then
                inspectTreeIdx = idx
                break
            end
        end
    end

    local sigTree = get_tree_by_signature_spells(vSpecID)

    local assignedRole = _G.UnitGroupRolesAssigned and _G.UnitGroupRolesAssigned("player")
    local roleTreeIdx = nil
    if assignedRole == "TANK" then
        if vSpecID == 1486 then roleTreeIdx = 2 -- Paladin Protection
        elseif vSpecID == 1491 then roleTreeIdx = 3 -- Warrior Protection
        elseif vSpecID == 1484 then roleTreeIdx = 2 -- Druid Feral
        end
    elseif assignedRole == "HEALER" then
        if vSpecID == 1486 then roleTreeIdx = 1 -- Paladin Holy
        elseif vSpecID == 1487 then roleTreeIdx = 1 -- Priest Discipline
        elseif vSpecID == 1489 then roleTreeIdx = 3 -- Shaman Restoration
        elseif vSpecID == 1484 then roleTreeIdx = 3 -- Druid Restoration
        end
    end

    local activeTree = sigTree or roleTreeIdx or inspectTreeIdx or curSpecIdx or 1

    local selectedTreeMapping = CLASSIC_TREE_SPECS[vSpecID] and CLASSIC_TREE_SPECS[vSpecID][activeTree]
    local fallbackSpecID = selectedTreeMapping and selectedTreeMapping.specID

    -- Below level 10: Untalented, use class icon and default role
    if playerLevel < 10 then
        return {
            name         = className,
            icon         = classIcon,
            classicRole  = defaultRole,
            role         = (defaultRole == "TANK" and "TANK") or (defaultRole == "HEAL" and "HEALER") or "DAMAGER",
            equivSpecID  = fallbackSpecID,
            totalPoints  = 0,
            dominantTree = activeTree,
        }
    end

    local totalPoints = 0
    local foundData = false

    -- Method 1: Classic Era / Camelot GetTalentTabInfo or C_SpecializationInfo (Instant, native 3-call API)
    if GetTalentTabInfo or (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) then
        for i = 1, 3 do
            local tName, tIcon, tPoints, tRole
            if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
                local sID, sName, _, sIcon, sRole, _, sPoints = C_SpecializationInfo.GetSpecializationInfo(i, false, false, nil, nil, activeGroup)
                if not sName and not sPoints then
                    sID, sName, _, sIcon, sRole, _, sPoints = C_SpecializationInfo.GetSpecializationInfo(i)
                end
                if sName or sIcon or (sPoints and sPoints > 0) then
                    tName = sName
                    tIcon = sIcon
                    tPoints = sPoints or 0
                    tRole = sRole
                end
            end
            if (not tPoints or tPoints == 0) and GetTalentTabInfo then
                local r1, r2, r3, r4, r5 = GetTalentTabInfo(i, false, false, activeGroup)
                if not r1 and not r3 then
                    r1, r2, r3, r4, r5 = GetTalentTabInfo(i)
                end
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

    -- Method 2: Camelot C_Traits group display & currency info (Fallback when native tab API is not populated)
    if not foundData then
        local C_Traits = _G.C_Traits
        local C_ClassTalents = _G.C_ClassTalents
        if C_Traits and C_Traits.GetGroupDisplayInfoByTreeID then
            local configID = (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID())
                or (C_SpecializationInfo and C_SpecializationInfo.GetCombatConfigIDForSpecGroup and C_SpecializationInfo.GetCombatConfigIDForSpecGroup(activeGroup))
                or (C_SpecializationInfo and C_SpecializationInfo.GetCombatConfigIDForSpecGroup and C_SpecializationInfo.GetCombatConfigIDForSpecGroup(1))
                or (C_Traits.GetConfigIDBySystemID and C_Traits.GetConfigIDBySystemID(activeGroup))
                or (C_Traits.GetConfigIDBySystemID and C_Traits.GetConfigIDBySystemID(1))
                or (C_Traits.GetConfigsByType and C_Traits.GetConfigsByType(1) and (C_Traits.GetConfigsByType(1)[activeGroup] or C_Traits.GetConfigsByType(1)[1]))
            if configID then
                local configInfo = C_Traits.GetConfigInfo(configID)
                local treeIDs = configInfo and configInfo.treeIDs
                if treeIDs and #treeIDs > 0 then
                    local traitTotal = 0
                    for _, treeID in ipairs(treeIDs) do
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
                            local function findGroupInfo(gid)
                                if not groupInfos or not gid then return nil end
                                for _, gi in ipairs(groupInfos) do
                                    if (gi.traitNodeGroupID and gi.traitNodeGroupID == gid) or (gi.groupID and gi.groupID == gid) then
                                        return gi
                                    end
                                end
                                return nil
                            end

                            for i, di in ipairs(displayInfos) do
                                local gid = di.groupID or di.traitNodeGroupID
                                local gi = findGroupInfo(gid)
                                local spent = 0
                                if gi then
                                    local cInfo = gi.currencyInfos and gi.currencyInfos[1]
                                    spent = (cInfo and cInfo.spent) or gi.spent or 0
                                end
                                if spent == 0 then
                                    spent = (di.spent and di.spent > 0 and di.spent)
                                        or (di.spentInTree and di.spentInTree > 0 and di.spentInTree)
                                        or (di.currencyInfos and di.currencyInfos[1] and di.currencyInfos[1].spent)
                                        or 0
                                end

                                -- Match display group to tree index (1..3)
                                local dName = di.displayName and di.displayName:lower() or ""
                                local matchedIdx = nil
                                if dName ~= "" and CLASSIC_TREE_SPECS[vSpecID] then
                                    for idx = 1, 3 do
                                        local t = CLASSIC_TREE_SPECS[vSpecID][idx]
                                        if t and t.name and (dName == t.name:lower() or dName:find(t.name:lower(), 1, true)) then
                                            matchedIdx = idx
                                            break
                                        end
                                    end
                                end
                                if not matchedIdx and i >= 1 and i <= 3 then
                                    matchedIdx = i
                                end
                                if not matchedIdx and di.orderIndex ~= nil then
                                    matchedIdx = di.orderIndex + 1
                                end

                                if matchedIdx and _classicTreeScratch[matchedIdx] then
                                    _classicTreeScratch[matchedIdx].name = di.displayName or _classicTreeScratch[matchedIdx].name
                                    _classicTreeScratch[matchedIdx].icon = di.icon or _classicTreeScratch[matchedIdx].icon
                                    _classicTreeScratch[matchedIdx].points = (_classicTreeScratch[matchedIdx].points or 0) + spent
                                    traitTotal = traitTotal + spent
                                    foundData = true
                                end
                            end
                        end
                    end

                    if traitTotal > 0 then
                        totalPoints = traitTotal
                    end
                end
            end
        end
    end

    local dominantIdx = sigTree or roleTreeIdx or inspectTreeIdx or curSpecIdx or activeTree
    local maxPoints = 0
    if foundData and totalPoints > 0 then
        for i = 1, 3 do
            local data = _classicTreeScratch[i]
            if data.points > maxPoints then
                maxPoints = data.points
                dominantIdx = i
            end
        end
    end

    if not foundData or totalPoints == 0 or maxPoints == 0 then
        local chosenTree = sigTree or roleTreeIdx or inspectTreeIdx or curSpecIdx or activeTree
        local untalentedMapping = CLASSIC_TREE_SPECS[vSpecID] and CLASSIC_TREE_SPECS[vSpecID][chosenTree]
        local untalentedEquiv = untalentedMapping and untalentedMapping.specID or fallbackSpecID
        local untalentedRole = untalentedMapping and untalentedMapping.role or defaultRole
        return {
            name         = (untalentedMapping and untalentedMapping.name and untalentedMapping.name:gsub("^%l", string.upper)) or className,
            icon         = (untalentedMapping and untalentedMapping.icon) or classIcon,
            classicRole  = untalentedRole,
            role         = (untalentedRole == "TANK" and "TANK") or (untalentedRole == "HEAL" and "HEALER") or "DAMAGER",
            equivSpecID  = untalentedEquiv,
            totalPoints  = totalPoints,
            dominantTree = chosenTree,
        }
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
    local camelotID = vSpecID * 10 + dominantTree
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
    local treeSpecs = vSpecID and CLASSIC_TREE_SPECS[vSpecID]

    local specs = {}
    local specIDs = {}

    if treeSpecs then
        for treeIdx = 1, 3 do
            local entry = treeSpecs[treeIdx]
            if entry then
                -- Canonical Camelot ID: never collides with retail spec IDs or class IDs
                local sID = vSpecID * 10 + treeIdx
                local name = entry.name
                local icon = entry.icon
                local retailSpecID = entry.specID -- kept for name/icon fallback only

                if GetTalentTabInfo then
                    local activeGroup = (_G.GetActiveTalentGroup and _G.GetActiveTalentGroup()) or 1
                    local r1, r2, r3, r4 = GetTalentTabInfo(treeIdx, false, false, activeGroup)
                    if not r1 and not r2 then
                        r1, r2, r3, r4 = GetTalentTabInfo(treeIdx)
                    end
                    local tabName = (type(r1) == "string" and r1) or (type(r2) == "string" and r2)
                    local tabIcon = (type(r2) == "number" and r2) or (type(r4) == "number" and r4)
                    if tabName and tabName ~= "" then name = tabName end
                    if tabIcon and tabIcon > 0 then icon = tabIcon end
                end

                -- Fallback: pull name/icon from the retail spec ID via game API
                if retailSpecID and (not name or not icon) and GetSpecializationInfoByID then
                    local _, sName, _, sIcon = GetSpecializationInfoByID(retailSpecID)
                    name = name or sName
                    icon = icon or sIcon
                end

                name = name and string.lower(name) or ("tree " .. treeIdx)

                specs[sID] = {
                    id           = sID,
                    name         = name,
                    description  = "",
                    icon         = icon or 134400,
                    role         = (entry.role == "TANK" and "TANK") or (entry.role == "HEAL" and "HEALER") or "DAMAGER",
                    classicRole  = entry.role,
                    index        = treeIdx,
                    classID      = vSpecID,
                    treeIndex    = treeIdx,
                    retailSpecID = retailSpecID, -- for icon/API lookups only
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

