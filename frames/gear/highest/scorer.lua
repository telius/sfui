local addonName, addon = ...
sfui.highest = sfui.highest or {}

local _G = _G
local common = sfui.common
local C_ClassTalents = _G.C_ClassTalents
local UnitLevel = _G.UnitLevel
local pairs = _G.pairs
local ipairs = _G.ipairs
local math = _G.math

local TANK_SPECS = (sfui.gear and sfui.gear.TANK_SPECS) or {
    [250]  = true, -- Blood DK
    [581]  = true, -- Vengeance DH
    [104]  = true, -- Guardian Druid
    [268]  = true, -- Brewmaster Monk
    [66]   = true, -- Protection Paladin
    [73]   = true, -- Protection Warrior
}
sfui.highest.TANK_SPECS = TANK_SPECS

local STATIC_CLASSIC_FALLBACK_ORDER = { "AP", "SP", "Hit", "Crit", "Str", "Agi", "Int", "Stam" }
local STATIC_RETAIL_FALLBACK_ORDER  = { "H", "M", "V", "C" }
local STATIC_DEFAULT_EQUALS         = { true, false, false }

local ARMOR_SLOTS = {
    [1]  = true, -- Head
    [3]  = true, -- Shoulder
    [5]  = true, -- Chest
    [6]  = true, -- Waist
    [7]  = true, -- Legs
    [8]  = true, -- Feet
    [9]  = true, -- Wrist
    [10] = true, -- Hands
}
sfui.highest.ARMOR_SLOTS = ARMOR_SLOTS

-- ══════════════════════════════════════════════════════════════════════════════
-- Stat Weights Resolution
-- ══════════════════════════════════════════════════════════════════════════════
function sfui.highest.ResolveStatWeights(specID, rule, specDB)
    local hd = nil
    if specDB and C_ClassTalents and C_ClassTalents.GetActiveHeroTalentSpec then
        local activeHero = C_ClassTalents.GetActiveHeroTalentSpec()
        if activeHero and specDB.hero and specDB.hero[activeHero] then
            hd = specDB.hero[activeHero]
        end
    end

    local pweights = (hd and hd.pawn_weights) or (specDB and specDB.pawn_weights)
    local statWeights = nil

    if pweights then
        -- Auto-inject main stats equal to highest secondary stat if missing
        local maxW = 0
        for _, w in pairs(pweights) do
            if w > maxW then maxW = w end
        end
        if maxW > 0 then
            local activePWeights = sfui.highest.activePWeights or {}
            sfui.highest.activePWeights = activePWeights
            for k in pairs(activePWeights) do activePWeights[k] = nil end
            for k, v in pairs(pweights) do activePWeights[k] = v end

            activePWeights["Intellect"] = activePWeights["Intellect"] or (maxW * 2.0)
            activePWeights["Agility"]   = activePWeights["Agility"] or (maxW * 2.0)
            activePWeights["Strength"]  = activePWeights["Strength"] or (maxW * 2.0)
            pweights                    = activePWeights
        end
    else
        -- P1 fallback hierarchy: pawn weights > explicitly saved manual stats > stats.lua default dictionary stats > hardcoded generic fallback failover
        local isClassicSpec = sfui.highest.isClassicOrVanilla()
        local classicRole = isClassicSpec and ((specDB and specDB.classic_role)
            or (sfui.gear and sfui.gear.GetClassicRole and sfui.gear.GetClassicRole(specID, specDB))) or nil
        local cRoleLower = classicRole and classicRole:lower()
        local isHealRole = (cRoleLower == "heal" or cRoleLower == "resto" or cRoleLower == "holy" or cRoleLower == "disc")
        local isTankRole = (cRoleLower == "tank" or cRoleLower == "bear" or cRoleLower == "prot")
        local isCasterDps = (cRoleLower == "moon" or cRoleLower == "ele" or cRoleLower == "shad" or cRoleLower == "shadow"
            or cRoleLower == "arc" or cRoleLower == "fire" or cRoleLower == "frost"
            or cRoleLower == "aff" or cRoleLower == "demo" or cRoleLower == "destro")
        local isMeleeDps = (cRoleLower == "cat" or cRoleLower == "arms" or cRoleLower == "fury" or cRoleLower == "ret" or cRoleLower == "enh")

        local order = (hd and hd.stat_order) or (specDB and specDB.stat_order) or
            (sfui.gear and sfui.gear.GetDefaultStats and sfui.gear.GetDefaultStats(specID, classicRole)) or
            (sfui.default_stats and sfui.default_stats[specID]) or
            (isClassicSpec and STATIC_CLASSIC_FALLBACK_ORDER or STATIC_RETAIL_FALLBACK_ORDER)
        local equals = (hd and hd.stat_equals) or (specDB and specDB.stat_equals) or STATIC_DEFAULT_EQUALS

        local statKeys = sfui.highest.statKeys or sfui.stat_keys or (sfui.data and sfui.data.STAT_KEYS)
        sfui.highest.statKeys = statKeys

        statWeights = sfui.highest.statWeights or {}
        sfui.highest.statWeights = statWeights
        for k in pairs(statWeights) do statWeights[k] = nil end

        local isCamelot = sfui.isCamelot or (sfui.compat and (sfui.compat.has.camelot or sfui.compat.is_camelot))
            or (sfui.version and sfui.version.camelot)
        local classID = isClassicSpec and ((sfui.gear and sfui.gear.GetClassicClassID and sfui.gear.GetClassicClassID(specID)) or (specID and specID >= 1482 and specID <= 1491 and specID)) or nil

        if isClassicSpec then
            if isHealRole or (rule.stat == 4 and not isCasterDps and not isMeleeDps and cRoleLower ~= "dps") then
                statWeights["ITEM_MOD_INTELLECT_SHORT"] = 2.0
                statWeights["ITEM_MOD_SPELL_POWER_SHORT"] = 2.5
                statWeights["ITEM_MOD_SPELL_HEALING_DONE_SHORT"] = 2.5
                statWeights["ITEM_MOD_SPIRIT_SHORT"] = 1.0
                statWeights["ITEM_MOD_MANA_REGENERATION_SHORT"] = 2.0
                statWeights["ITEM_MOD_STAMINA_SHORT"] = 1.0
            elseif rule.stat == 1 or (isTankRole and classID == 1484) or isMeleeDps then -- Strength / Melee
                if rule.stat == 2 or (cRoleLower == "cat" and classID == 1484) then
                    statWeights["ITEM_MOD_AGILITY_SHORT"] = 2.0
                    statWeights["ITEM_MOD_ATTACK_POWER_SHORT"] = 1.0
                    statWeights["ITEM_MOD_RANGED_ATTACK_POWER_SHORT"] = 1.0
                    statWeights["ITEM_MOD_STRENGTH_SHORT"] = 1.0
                    statWeights["ITEM_MOD_STAMINA_SHORT"] = 1.0
                else
                    statWeights["ITEM_MOD_STRENGTH_SHORT"] = 2.0
                    statWeights["ITEM_MOD_ATTACK_POWER_SHORT"] = 1.0
                    statWeights["ITEM_MOD_AGILITY_SHORT"] = 1.5
                    statWeights["ITEM_MOD_STAMINA_SHORT"] = 1.0
                end
            elseif rule.stat == 2 then -- Agility (Rogue, Hunter)
                statWeights["ITEM_MOD_AGILITY_SHORT"] = 2.0
                statWeights["ITEM_MOD_ATTACK_POWER_SHORT"] = 1.0
                statWeights["ITEM_MOD_RANGED_ATTACK_POWER_SHORT"] = 1.0
                statWeights["ITEM_MOD_STRENGTH_SHORT"] = 1.0
                statWeights["ITEM_MOD_STAMINA_SHORT"] = 1.0
            elseif rule.stat == 4 or isCasterDps then -- Intellect / Caster (Mage, Priest, Warlock, Shaman, Moonkin)
                statWeights["ITEM_MOD_INTELLECT_SHORT"] = 2.0
                statWeights["ITEM_MOD_SPELL_POWER_SHORT"] = 2.5
                -- In Camelot, bonus healing converts 1/3 to spell damage.
                -- In Classic Era (Vanilla), bonus healing gives 0 spell damage.
                statWeights["ITEM_MOD_SPELL_HEALING_DONE_SHORT"] = isCamelot and (2.5 / 3) or 0
                statWeights["ITEM_MOD_SPIRIT_SHORT"] = 1.0
                statWeights["ITEM_MOD_MANA_REGENERATION_SHORT"] = 2.0
                statWeights["ITEM_MOD_STAMINA_SHORT"] = 1.0
            end
        else
            statWeights["ITEM_MOD_INTELLECT_SHORT"] = 6.0
            statWeights["ITEM_MOD_AGILITY_SHORT"] = 6.0
            statWeights["ITEM_MOD_STRENGTH_SHORT"] = 6.0
        end

        local isTankForWeights = false
        if isClassicSpec then
            isTankForWeights = isTankRole
                or (sfui.gear and sfui.gear.IsTankSpec and sfui.gear.IsTankSpec(specID, specDB))
                or ((specDB and (specDB.is_tank or specDB.armor_ilvl_prio)) and true or false)
        else
            isTankForWeights = TANK_SPECS[specID] == true
        end

        local numStats = isClassicSpec and math.min(#order, 8) or 4
        local curWeight = isClassicSpec and (numStats * 1.0) or 4.0
        local step = 1.0

        for i = 1, numStats do
            local stat = order[i]
            if stat and statKeys[stat] then
                if not isTankForWeights and (stat == "Def" or stat == "Defense" or stat == "Dodge" or stat == "Parry" or stat == "Block" or stat == "Arm" or stat == "Armor") then
                    statWeights[statKeys[stat]] = 0
                else
                    statWeights[statKeys[stat]] = (statWeights[statKeys[stat]] or 0) + curWeight
                end
            end
            if i < numStats and not equals[i] then
                curWeight = math.max(0.5, curWeight - step)
            end
        end

        -- Spell Power parity & healing conversion reconciliation
        if isClassicSpec then
            if isHealRole or (rule.stat == 4 and not isCasterDps and not isMeleeDps and cRoleLower ~= "dps") then
                -- Healers: 1 Spell Power = 1 Healing (100% 1:1 parity)
                local healW = statWeights["ITEM_MOD_SPELL_HEALING_DONE_SHORT"] or 0
                local spW = statWeights["ITEM_MOD_SPELL_POWER_SHORT"] or 0
                if healW > spW then
                    statWeights["ITEM_MOD_SPELL_POWER_SHORT"] = healW
                end
            elseif (rule.stat == 4 or isCasterDps) and not isHealRole then
                -- Caster DPS: bonus healing converts at 1/3 on Camelot, or 0 on Classic Era
                local spW = statWeights["ITEM_MOD_SPELL_POWER_SHORT"] or 2.5
                statWeights["ITEM_MOD_SPELL_HEALING_DONE_SHORT"] = isCamelot and (spW / 3) or 0
            end
        end
    end

    return pweights, statWeights
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Item Scoring Logic
-- ══════════════════════════════════════════════════════════════════════════════
function sfui.highest.ScoreItem(itm, slotID, specID, rule, pweights, statWeights, context)
    if itm.isLockedItem then
        itm.score = 9000000 + (itm.ilvl or 0)
        return
    end

    local isClassicSpec = context.isClassicSpec
    local isPvP = context.isPvP
    local forceIlvl = context.forceIlvl
    local isTank = context.isTank
    local isHeal = context.isHeal
    local isHunter = context.isHunter
    local classID = context.classID
    local playerClass = context.playerClass
    local usesAmmo = context.usesAmmo
    local prioritizeIlvl = context.prioritizeIlvl

    local baseMultiplier
    if isClassicSpec then
        baseMultiplier = isPvP and 20 or 10
    else
        baseMultiplier = forceIlvl and 100000 or (isPvP and 100 or (prioritizeIlvl and 1000 or 10))
    end
    local score = itm.ilvl * baseMultiplier

    local isWeapon = (slotID == 16 or slotID == 17 or (isClassicSpec and slotID == 18 and (itm.itemEquipLoc == "INVTYPE_RANGED" or itm.itemEquipLoc == "INVTYPE_RANGEDRIGHT" or itm.itemEquipLoc == "INVTYPE_THROWN")))

    -- Feature 0: Classic / Vanilla Quality & Weapon DPS Weighting
    -- Ensures: Epic > Rare > Uncommon > Common > Poor
    if isClassicSpec then
        local q = itm.quality or 1
        local qBonus = (q == 5 and 2500)
            or (q == 4 and 1200)
            or (q == 3 and 600)
            or (q == 2 and 250)
            or (q == 1 and 20)
            or 0
        score = score + qBonus

        -- Feature 0b: Weapon DPS & Speed Evaluation for Classic
        if isWeapon then
            local wDps, wSpeed = common.get_weapon_stats(itm.link)
            if wDps and wDps > 0 then
                local isHunterSpec = isHunter or (classID == 1485) or usesAmmo or (playerClass == "HUNTER")
                local isPhysical = (rule.stat == 1 or rule.stat == 2)
                local isCaster = (rule.stat == 4)

                local dpsWeight = 0
                if isHeal then
                    dpsWeight = (slotID == 18 and 25) or 0 -- Wand DPS for wand users, 0 weapon melee damage for healers
                elseif isHunterSpec then
                    if slotID == 18 then
                        dpsWeight = 35 -- Main damage weapon for Hunter
                    else
                        dpsWeight = isClassicSpec and 25 or 10 -- Melee weapon (Classic: melee combat / Raptor Strike / stat stick)
                    end
                elseif isPhysical then
                    if slotID == 18 then
                        dpsWeight = 5 -- Ranged stat stick for Warrior/Rogue
                    else
                        dpsWeight = isClassicSpec and 60 or 30 -- Main/Off/2H weapon for melee physical (Classic: 1 DPS = 14 AP = 7 Str)
                    end
                elseif isCaster then
                    if slotID == 18 then
                        dpsWeight = 25 -- Wand DPS is very valuable for leveling casters
                    else
                        local playerLvl = isClassicSpec and (UnitLevel("player") or 1) or 99
                        if isClassicSpec and playerLvl < 20 and (classID == 1489 or classID == 1484 or classID == 1486) then
                            dpsWeight = 40 -- In Classic, wandless hybrid casters (Shaman/Druid/Paladin) melee aggressively at low level
                        else
                            dpsWeight = 5 -- Caster melee weapon
                        end
                    end
                else
                    dpsWeight = 15
                end

                score = score + (wDps * dpsWeight)

                -- Slower 2H weapons hit much harder for Ret Paladin, Arms Warrior & Shaman (Windfury, Rockbiter, Seal of Command, Mortal Strike)
                if not isHeal and itm.is2H and wSpeed and wSpeed > 2.0 and (classID == 1486 or classID == 1491 or classID == 1489) then
                    score = score + (wSpeed * 15)
                end

                -- Classic Rogue Weapon Optimization:
                -- Main Hand (slot 16): Slowest, highest-damage-per-hit weapon (Sinister Strike / Backstab scaling).
                -- If Backstab is used: Main Hand MUST be a Dagger (subclassID == 15).
                -- Off Hand (slot 17): Fast one-handed weapon for poison procs (50% reduced base auto-attack damage).
                local isRogue = (classID == 1488 or specID == 1488 or (specID and specID >= 14881 and specID <= 14883))
                if isClassicSpec and isRogue then
                    local _, _, _, _, _, _, subclassID = common.get_item_instant_info(itm.link)
                    local isDagger = (subclassID == 15)
                    local _, rwSpeed, minDmg, maxDmg = common.get_weapon_stats(itm.link)
                    local avgDmg = (minDmg > 0 and maxDmg > 0) and ((minDmg + maxDmg) / 2) or (wDps * (rwSpeed or 2.0))
                    local usesBackstab = sfui.highest.DoesRogueUseBackstab(specID)

                    if slotID == 16 then
                        if usesBackstab then
                            if isDagger then
                                score = score + 50000 -- Backstab requires a dagger in Main Hand
                            else
                                score = score - 50000
                            end
                        end
                        -- Main Hand scales heavily on damage-per-hit & slower speed (Sinister Strike / Backstab)
                        if avgDmg and avgDmg > 0 then
                            score = score + (avgDmg * 20)
                        end
                        if rwSpeed and rwSpeed > 0 then
                            score = score + (rwSpeed * 80)
                        end
                    elseif slotID == 17 then
                        -- Off Hand: Fast secondary weapon generates poison procs faster
                        if rwSpeed and rwSpeed > 0 then
                            score = score + ((3.5 - rwSpeed) * 40)
                        end
                    end
                end
            end
        end

        -- Shield Evaluation (Armor and Block Value for all shield wearers):
        if itm.itemEquipLoc == "INVTYPE_SHIELD" then
            local sArmor, sBlock = common.get_shield_stats(itm.link)
            local itemStats = common.get_item_stats(itm.link)
            if (not sArmor or sArmor == 0) and itemStats then sArmor = itemStats["ITEM_MOD_ARMOR_SHORT"] or 0 end
            if (not sBlock or sBlock == 0) and itemStats then sBlock = itemStats["ITEM_MOD_BLOCK_VALUE_SHORT"] or 0 end

            if isClassicSpec then
                -- Armor on shields: In Classic, base armor on shields is a primary defensive attribute
                if sArmor and sArmor > 0 then
                    score = score + (sArmor * 3.0)
                end
                -- Block on shields: 1 Block absorbs 1 physical damage per blocked attack
                if sBlock and sBlock > 0 then
                    score = score + (sBlock * 25.0)
                end
                -- Shield baseline bonus: Value shields for tanks and healers
                if isTank or isHeal then
                    score = score + 500
                end
            else
                if sArmor and sArmor > 0 then
                    score = score + sArmor
                end
                if sBlock and sBlock > 0 then
                    score = score + (sBlock * 10.0)
                end
                if isTank or isHeal then
                    score = score + 500
                end
            end
        end

        -- Subclass preference for starting/leveling armor (Plate 4 > Mail 3 > Leather 2 > Cloth 1)
        if ARMOR_SLOTS[slotID] and itm.itemEquipLoc ~= "INVTYPE_SHIELD" and itm.itemEquipLoc ~= "INVTYPE_CLOAK" then
            local _, _, _, _, _, _, subclassID = common.get_item_instant_info(itm.link)
            local optimalArmor = rule.armor
            if subclassID and optimalArmor then
                if optimalArmor == 4 then -- Warrior/Paladin: Mail (3) > Leather (2) > Cloth (1)
                    score = score + (subclassID * 50)
                elseif optimalArmor == 3 then -- Hunter/Shaman: Leather (2) > Cloth (1)
                    score = score + ((subclassID == 3 and 150) or (subclassID == 2 and 100) or 50)
                elseif optimalArmor == 2 then -- Rogue/Druid: Leather (2) > Cloth (1)
                    score = score + ((subclassID == 2 and 100) or 50)
                end
            end
        end
    end

    -- Feature 1: Tier Set Protection
    if itm.isEquipped then
        local setID = itm.setID
        if setID and setID > 0 then
            score = score + 150 -- +150 score protection for equipped tier sets to dissuade breaking sets
        end
    end

    -- Feature 2: Socket Valuation & Stat Priority
    local itemStats = common.get_item_stats(itm.link)
    local statScore = 0
    if itemStats then
        -- Prismatic socket bonus
        if itemStats["EMPTY_SOCKET_PRISMATIC"] then
            score = score + (prioritizeIlvl and 500 or 150)
        end

        -- Secondary stat weights derived directly from Pawn string parsing, or fallback to relative Tier weights
        if pweights then
            for statName, statAmount in pairs(itemStats) do
                -- Shields already evaluate base armor and block value above with exact shield coefficients
                if not (itm.itemEquipLoc == "INVTYPE_SHIELD" and (statName == "ITEM_MOD_ARMOR_SHORT" or statName == "ITEM_MOD_EXTRA_ARMOR_SHORT" or statName == "ITEM_MOD_BLOCK_VALUE_SHORT")) then
                    local simName = "None"
                    if statName == "ITEM_MOD_CRIT_RATING_SHORT" or statName == "ITEM_MOD_CRIT_SPELL_RATING_SHORT" or statName == "ITEM_MOD_CRIT_MELEE_RATING_SHORT" or statName == "ITEM_MOD_CRIT_RANGED_RATING_SHORT" then
                        simName = "Crit"
                    elseif statName == "ITEM_MOD_HASTE_RATING_SHORT" or statName == "ITEM_MOD_HASTE_SPELL_RATING_SHORT" or statName == "ITEM_MOD_HASTE_MELEE_RATING_SHORT" then
                        simName = "Haste"
                    elseif statName == "ITEM_MOD_MASTERY_RATING_SHORT" then
                        simName = "Mastery"
                    elseif statName == "ITEM_MOD_VERSATILITY" then
                        simName = "Versatility"
                    elseif statName == "ITEM_MOD_SPELL_POWER_SHORT" or statName == "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT" then
                        simName = "SpellPower"
                    elseif statName == "ITEM_MOD_SPELL_HEALING_DONE_SHORT" then
                        simName = "Healing"
                    elseif statName == "ITEM_MOD_HIT_RATING_SHORT" or statName == "ITEM_MOD_HIT_SPELL_RATING_SHORT" or statName == "ITEM_MOD_HIT_MELEE_RATING_SHORT" or statName == "ITEM_MOD_HIT_RANGED_RATING_SHORT" then
                        simName = "Hit"
                    elseif statName == "ITEM_MOD_ATTACK_POWER_SHORT" then
                        simName = "AttackPower"
                    elseif statName == "ITEM_MOD_RANGED_ATTACK_POWER_SHORT" then
                        simName = "RangedAP"
                    elseif statName == "ITEM_MOD_MANA_REGENERATION_SHORT" then
                        simName = "ManaRegen"
                    elseif statName == "ITEM_MOD_SPIRIT_SHORT" then
                        simName = "Spirit"
                    elseif statName == "ITEM_MOD_STAMINA_SHORT" then
                        simName = "Stamina"
                    elseif statName == "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT" then
                        simName = isTank and "Defense" or "None"
                    elseif statName == "ITEM_MOD_DODGE_RATING_SHORT" then
                        simName = isTank and "Dodge" or "None"
                    elseif statName == "ITEM_MOD_PARRY_RATING_SHORT" then
                        simName = isTank and "Parry" or "None"
                    elseif statName == "ITEM_MOD_BLOCK_RATING_SHORT" then
                        simName = isTank and "Block" or "None"
                    elseif statName == "ITEM_MOD_BLOCK_VALUE_SHORT" then
                        simName = isTank and "BlockValue" or "None"
                    elseif statName == "ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT" then
                        simName = "ArmorPenetration"
                    elseif statName == "ITEM_MOD_EXPERTISE_RATING_SHORT" then
                        simName = "Expertise"
                    elseif statName == "ITEM_MOD_ARMOR_SHORT" or statName == "ITEM_MOD_EXTRA_ARMOR_SHORT" then
                        simName = isTank and "Armor" or "None"
                    elseif statName == "ITEM_MOD_INTELLECT_SHORT" or statName == "ITEM_MOD_AGILITY_SHORT" or statName == "ITEM_MOD_STRENGTH_SHORT" then
                        if rule.stat == 4 then
                            simName = "Intellect"
                        elseif rule.stat == 2 then
                            simName = "Agility"
                        elseif rule.stat == 1 then
                            simName = "Strength"
                        end
                    end

                    if simName ~= "None" then
                        local weight = pweights[simName]
                        if not weight and isClassicSpec then
                            local isCamelot = sfui.isCamelot or (sfui.compat and (sfui.compat.has.camelot or sfui.compat.is_camelot))
                                or (sfui.version and sfui.version.camelot)
                            if isCamelot and simName == "Healing" and not isHeal then
                                -- On Camelot, bonus healing converts 1/3 to spell damage
                                weight = (pweights["SpellPower"] or 0) / 3
                            elseif simName == "SpellPower" and isHeal then
                                -- Spell Power converts 1:1 to healing for healers
                                weight = pweights["Healing"]
                            end
                        elseif weight and isClassicSpec and simName == "SpellPower" and isHeal and pweights["Healing"] and pweights["Healing"] > weight then
                            -- Ensure Spell Power is worth at least full Healing for healers
                            weight = pweights["Healing"]
                        end
                        if weight and weight > 0 then
                            local add = (statAmount * weight)
                            score = score + add
                            statScore = statScore + add
                        end
                    end

                    -- Tertiary stat modifiers
                    if statName == "ITEM_MOD_CR_LIFESTEAL_SHORT" or statName == "ITEM_MOD_CR_SPEED_SHORT" then
                        score = score + statAmount
                        statScore = statScore + statAmount
                    end
                end
            end
        elseif statWeights then
            for statName, statAmount in pairs(itemStats) do
                if not (itm.itemEquipLoc == "INVTYPE_SHIELD" and (statName == "ITEM_MOD_ARMOR_SHORT" or statName == "ITEM_MOD_EXTRA_ARMOR_SHORT" or statName == "ITEM_MOD_BLOCK_VALUE_SHORT")) then
                    -- Strictly exclude defensive stats if not a tank
                    local isDefensive = (statName == "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT" or
                                         statName == "ITEM_MOD_DODGE_RATING_SHORT" or
                                         statName == "ITEM_MOD_PARRY_RATING_SHORT" or
                                         statName == "ITEM_MOD_BLOCK_RATING_SHORT" or
                                         statName == "ITEM_MOD_BLOCK_VALUE_SHORT")
                    if not (not isTank and isDefensive) then
                        local mappedStatName = statName
                        if statName == "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT" then
                            mappedStatName = "ITEM_MOD_SPELL_POWER_SHORT"
                        elseif statName == "ITEM_MOD_CRIT_SPELL_RATING_SHORT" or statName == "ITEM_MOD_CRIT_MELEE_RATING_SHORT" or statName == "ITEM_MOD_CRIT_RANGED_RATING_SHORT" then
                            mappedStatName = "ITEM_MOD_CRIT_RATING_SHORT"
                        elseif statName == "ITEM_MOD_HIT_SPELL_RATING_SHORT" or statName == "ITEM_MOD_HIT_MELEE_RATING_SHORT" or statName == "ITEM_MOD_HIT_RANGED_RATING_SHORT" then
                            mappedStatName = "ITEM_MOD_HIT_RATING_SHORT"
                        elseif statName == "ITEM_MOD_EXTRA_ARMOR_SHORT" then
                            mappedStatName = "ITEM_MOD_ARMOR_SHORT"
                        elseif statName == "ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT" then
                            mappedStatName = "ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT"
                        elseif statName == "ITEM_MOD_EXPERTISE_RATING_SHORT" then
                            mappedStatName = "ITEM_MOD_EXPERTISE_RATING_SHORT"
                        elseif not isClassicSpec and (statName == "ITEM_MOD_INTELLECT_SHORT" or statName == "ITEM_MOD_AGILITY_SHORT" or statName == "ITEM_MOD_STRENGTH_SHORT") then
                            mappedStatName = common.get_stat_key(rule.stat) or statName
                        end

                        if statWeights[mappedStatName] then
                            local add = (statAmount * statWeights[mappedStatName])
                            score = score + add
                            statScore = statScore + add
                        end
                    end

                    -- Tertiary stat modifiers
                    if statName == "ITEM_MOD_CR_LIFESTEAL_SHORT" or statName == "ITEM_MOD_CR_SPEED_SHORT" then
                        score = score + statAmount
                        statScore = statScore + statAmount
                    end
                end
            end
        end
    end
    if itm.itemEquipLoc == "INVTYPE_TRINKET" then
        local mult = common.get_trinket_value_multiplier(itm.link, specID)
        if mult and mult ~= 1.0 then
            score = score * mult
            statScore = statScore * mult
        end
    end
    itm.statScore = statScore
    itm.score = score
end
