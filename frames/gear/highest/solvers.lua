local addonName, addon = ...
sfui.highest = sfui.highest or {}

local _G = _G
local common = sfui.common
local GetItemInfo = sfui.common.get_item_info
local pairs = _G.pairs
local ipairs = _G.ipairs
local table = _G.table
local math = _G.math
local select = _G.select

local FROSTBANE_TALENT_ID = 455993

local function GetInventoryItemLink(unit, slotID)
    if sfui.common and sfui.common.get_inventory_item_link then
        return sfui.common.get_inventory_item_link(unit, slotID)
    end
    return _G.GetInventoryItemLink and _G.GetInventoryItemLink(unit, slotID)
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Tier Set Solver
-- ══════════════════════════════════════════════════════════════════════════════
function sfui.highest.SolveTierSets(best, finalPick, specDB)
    local force_2set = specDB and specDB.force_2set
    local force_4set = specDB and (specDB.force_4set ~= false) and not specDB.force_2set
    if not (force_2set or force_4set) then return end

    local targetCount = force_4set and 4 or 2
    local tierSlots = sfui.highest.tierSlots or { 1, 3, 5, 7, 10 } -- Head, Shoulder, Chest, Legs, Hands
    sfui.highest.tierSlots = tierSlots
    local setStats = {}

    for _, s in ipairs(tierSlots) do
        if best[s] then
            for _, itm in ipairs(best[s]) do
                local setID = itm.setID
                if setID and setID > 0 then
                    if not setStats[setID] then setStats[setID] = { setID = setID, count = 0, totalIlvl = 0, pieces = {} } end
                    if not setStats[setID].pieces[s] or itm.score > setStats[setID].pieces[s].score then
                        setStats[setID].pieces[s] = itm
                    end
                end
            end
        end
    end

    -- Rank candidate sets prioritizing newest tier (highest setID), with totalIlvl as tiebreaker
    local sortedSets = {}
    for setID, data in pairs(setStats) do
        local count = 0
        local totalIlvl = 0
        for s, itm in pairs(data.pieces) do
            count = count + 1
            totalIlvl = totalIlvl + itm.ilvl
        end
        data.count = count
        data.totalIlvl = totalIlvl
        table.insert(sortedSets, data)
    end

    table.sort(sortedSets, function(a, b)
        if a.setID ~= b.setID then
            return a.setID > b.setID
        end
        return a.totalIlvl > b.totalIlvl
    end)

    -- 1. Find the newest tier set (highest setID) that meets targetCount (4 or 2)
    local bestSet = nil
    local effectiveTargetCount = targetCount
    for _, data in ipairs(sortedSets) do
        if data.count >= targetCount then
            bestSet = data
            break
        end
    end

    -- 2. Fallback: if forcing 4-set but no single set has 4 pieces, fallback to the
    -- newest tier set with at least 2 pieces so the player still gets their 2-set bonus
    if not bestSet and targetCount == 4 then
        for _, data in ipairs(sortedSets) do
            if data.count >= 2 then
                bestSet = data
                effectiveTargetCount = 2
                break
            end
        end
    end

    if bestSet and bestSet.pieces then
        local costList = {}
        for s, tierItm in pairs(bestSet.pieces) do
            local bestOverallScore = (best[s] and best[s][1] and best[s][1].score) or 0
            local cost = bestOverallScore - tierItm.score
            if cost < 0 then cost = 0 end
            table.insert(costList, { slot = s, itm = tierItm, cost = cost })
        end

        table.sort(costList, function(a, b) return a.cost < b.cost end)

        for i = 1, effectiveTargetCount do
            if costList[i] then
                finalPick[costList[i].slot] = costList[i].itm
                costList[i].itm.isTier = true
                costList[i].itm.equipReason = (effectiveTargetCount >= 4) and "4-Set" or "2-Set"
            end
        end
    end
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Weapon Combinatorics Solver
-- ══════════════════════════════════════════════════════════════════════════════
function sfui.highest.SolveWeapons(best, finalPick, specID, rule, context)
    local isClassicSpec = context.isClassicSpec
    local classID = context.classID
    local isTank = context.isTank
    local isHeal = context.isHeal
    local isHunter = context.isHunter
    local isRetPaladin = context.isRetPaladin
    local isPvP = context.isPvP

    local isPaladinWeap = isClassicSpec and (classID == 1486 or specID == 1486 or (specID and specID >= 14861 and specID <= 14863))
    local isWarriorWeap = isClassicSpec and (classID == 1491 or specID == 1491 or (specID and specID >= 14911 and specID <= 14913))
    local isShamanWeap  = isClassicSpec and (classID == 1489 or specID == 1489 or (specID and specID >= 14891 and specID <= 14893))
    local isRogueWeap   = isClassicSpec and (classID == 1488 or specID == 1488 or (specID and specID >= 14881 and specID <= 14883))
    local isHunterWeap  = isHunter

    local best2H = nil

    if not finalPick[16] and not finalPick[17] then
        local hasFrostbane = (specID == 251) and common.is_talent_known(FROSTBANE_TALENT_ID)
        best2H = nil
        local best1H = nil
        local bestOH = nil

        if best[16] then
            for _, itm in ipairs(best[16]) do
                if itm.is2H and not best2H then best2H = itm end
                if not itm.is2H and not best1H then best1H = itm end
            end
        end
        if best[17] then
            for _, itm in ipairs(best[17]) do
                if not itm.is2H then
                    if not best1H or (best1H.physId ~= itm.physId) then
                        bestOH = itm; break
                    end
                end
            end
        end

        -- Frost DK with Frostbane: MUST equip the Rune of Razorice weapon in the Main Hand (slot 16)
        if hasFrostbane and best[16] then
            local bestRazor1H = nil
            for _, itm in ipairs(best[16]) do
                if not itm.is2H and sfui.highest.HasRazoriceEnchant(itm) then
                    bestRazor1H = itm
                    break
                end
            end

            if bestRazor1H then
                best1H = bestRazor1H
                bestOH = nil
                if best[17] then
                    for _, itm in ipairs(best[17]) do
                        if not itm.is2H and (bestRazor1H.physId ~= itm.physId) then
                            bestOH = itm
                            break
                        end
                    end
                end
            end
        end

        local isDualWield = bestOH and (bestOH.itemEquipLoc == "INVTYPE_WEAPON" or bestOH.itemEquipLoc == "INVTYPE_WEAPONOFFHAND" or (bestOH.itemEquipLoc == "INVTYPE_2HWEAPON" and rule.weaps["2H_Dual"]))
        local score2H = best2H and best2H.score or 0
        local scoreDual = 0

        if isClassicSpec and not isTank and not isHeal and bestOH and not isDualWield then
            -- For Classic physical DPS (Ret Paladin, Arms Warrior, Enhancement/leveling Shaman) considering 1H + Shield/Offhand vs 2H:
            -- An off-hand shield or frill does not deal weapon damage; evaluate based purely on weapon DPS and stats on the items.
            local ohStatScore = bestOH.statScore or 0
            scoreDual = (best1H and best1H.score or 0) + ohStatScore
        else
            if best2H and bestOH then
                local twoHandIlvlMult = isClassicSpec and 10 or (isPvP and 100 or 1000)
                score2H = score2H + (best2H.ilvl * twoHandIlvlMult)
                if isClassicSpec then
                    local q = best2H.quality or 1
                    local qBonus = (q == 5 and 2500)
                        or (q == 4 and 1200)
                        or (q == 3 and 600)
                        or (q == 2 and 250)
                        or (q == 1 and 20)
                        or 0
                    score2H = score2H + qBonus
                end
            end
            scoreDual = (best1H and best1H.score or 0) + (bestOH and bestOH.score or 0)
        end

        local prioMH_OH = (specID == 62 or specID == 63 or specID == 64 or specID == 265 or specID == 266 or specID == 267 or specID == 258) or (isClassicSpec and isHeal)
        local choose2H = false

        if not isClassicSpec and specID == 70 then
            -- Retail Retribution Paladin (70): ALWAYS use 2H weapons exclusively!
            choose2H = best2H ~= nil
        elseif best2H and not best1H then
            choose2H = true
        elseif best2H and best1H then
            local dps1H = sfui.highest.GetWeaponDPS(best1H)
            local dps2H = sfui.highest.GetWeaponDPS(best2H)

            if isHunter or isRetPaladin then
                -- Hunter & Ret Paladin in Classic / Camelot:
                -- Melee weapon choice prioritizes weapon DPS and overall combat value.
                -- If the 1-handed weapon has higher weapon DPS than the 2-handed weapon, ALWAYS prefer the 1-hander!
                -- Also if the 1-handed weapon (+ shield/offhand) overall score is equal or better than the 2-hander, prefer 1H!
                if dps1H > dps2H then
                    choose2H = false
                elseif scoreDual >= score2H then
                    choose2H = false
                elseif dps2H > dps1H then
                    choose2H = (score2H > scoreDual)
                else
                    choose2H = (score2H > scoreDual)
                end
            elseif prioMH_OH then
                -- For Mage, Warlock & Shadow Priest or Classic Healers: prioritize MH + OH if stats/score are equal or better
                if score2H > (scoreDual + 1.0) then
                    choose2H = true
                else
                    choose2H = false
                end
            elseif specID == 251 then
                -- Frost DK: dual wield is heavily favored (2 Runeforges, KM proc rate, dual strikes).
                if scoreDual >= (score2H * 0.80) then
                    choose2H = false
                else
                    choose2H = true
                end
            else
                if not bestOH and isClassicSpec and not isTank and not isHeal and dps1H > dps2H then
                    choose2H = false
                elseif score2H > scoreDual then
                    choose2H = true
                else
                    choose2H = false
                end
            end
        end

        -- Classic Hunter & Ret Paladin Weapon DPS / Upgrade Override:
        if (isHunterWeap or isRetPaladin) and best1H and best2H then
            local dps1H = sfui.highest.GetWeaponDPS(best1H)
            local dps2H = sfui.highest.GetWeaponDPS(best2H)
            if dps1H > dps2H or scoreDual >= score2H then
                choose2H = false
            end
        end

        -- Retail Retribution Paladin Override: ALWAYS use 2H weapons!
        if not isClassicSpec and specID == 70 and best2H then
            choose2H = true
        end

        -- Classic Tank Override: Classic Warrior (1491) and Paladin (1486) tanks NEVER use 2H weapons!
        if isClassicSpec and isTank and (isWarriorWeap or isPaladinWeap) then
            choose2H = false
        end

        -- Classic Healer Override: Classic Paladin and Shaman healers use 1H + Shield / Offhand when both are available!
        if isClassicSpec and isHeal and (isPaladinWeap or isShamanWeap) and best1H and bestOH then
            choose2H = false
        end

        if choose2H then
            finalPick[16] = best2H
            local currentOffhand = GetInventoryItemLink("player", 17)
            if currentOffhand then
                finalPick[17] = { isUnequip = true, isEquipped = false }
            end
        else
            if best1H and bestOH then
                local canOHGoMainHand = (bestOH.itemEquipLoc == "INVTYPE_WEAPON" or bestOH.itemEquipLoc == "INVTYPE_WEAPONMAINHAND" or (bestOH.itemEquipLoc == "INVTYPE_2HWEAPON" and rule.weaps["2H_Dual"]))
                local can1HGoOffHand = (best1H.itemEquipLoc == "INVTYPE_WEAPON" or best1H.itemEquipLoc == "INVTYPE_WEAPONOFFHAND" or (best1H.itemEquipLoc == "INVTYPE_2HWEAPON" and rule.weaps["2H_Dual"]))

                if canOHGoMainHand and can1HGoOffHand then
                    local preferOHinMH = false
                    if isRogueWeap then
                        -- Rogue Weapon Assignment:
                        local usesBackstab = sfui.highest.DoesRogueUseBackstab(specID)
                        local _, _, _, _, _, _, sub1 = common.get_item_instant_info(best1H.link)
                        local _, _, _, _, _, _, sub2 = common.get_item_instant_info(bestOH.link)
                        local w1Dagger = (sub1 == 15)
                        local w2Dagger = (sub2 == 15)

                        if usesBackstab and (w1Dagger ~= w2Dagger) then
                            preferOHinMH = w2Dagger
                        else
                            local dps1 = sfui.highest.GetWeaponDPS(best1H)
                            local dps2 = sfui.highest.GetWeaponDPS(bestOH)
                            local _, speed1, min1, max1 = common.get_weapon_stats(best1H.link)
                            local _, speed2, min2, max2 = common.get_weapon_stats(bestOH.link)
                            local avgDmg1 = (min1 > 0 and max1 > 0) and ((min1 + max1) / 2) or (dps1 * (speed1 or 2.0))
                            local avgDmg2 = (min2 > 0 and max2 > 0) and ((min2 + max2) / 2) or (dps2 * (speed2 or 2.0))

                            if math.abs(avgDmg1 - avgDmg2) > 0.05 then
                                preferOHinMH = (avgDmg2 > avgDmg1)
                            elseif math.abs((speed2 or 0) - (speed1 or 0)) > 0.05 then
                                preferOHinMH = ((speed2 or 0) > (speed1 or 0))
                            else
                                preferOHinMH = ((bestOH.score or 0) > (best1H.score or 0))
                            end
                        end
                    else
                        -- Dual Wielding two weapons:
                        local dps1 = sfui.highest.GetWeaponDPS(best1H)
                        local dps2 = sfui.highest.GetWeaponDPS(bestOH)
                        local isDpsEqual = (math.abs(dps1 - dps2) < 0.05)

                        if not isDpsEqual then
                            preferOHinMH = (dps2 > dps1)
                        else
                            local ilvl1 = best1H.ilvl or 0
                            local ilvl2 = bestOH.ilvl or 0
                            if ilvl2 ~= ilvl1 then
                                preferOHinMH = (ilvl2 > ilvl1)
                            else
                                if specID == 251 then
                                    local w1Razor = sfui.highest.HasRazoriceEnchant(best1H)
                                    local w2Razor = sfui.highest.HasRazoriceEnchant(bestOH)
                                    if hasFrostbane then
                                        preferOHinMH = (w2Razor and not w1Razor)
                                    else
                                        preferOHinMH = (w1Razor and not w2Razor)
                                    end
                                else
                                    preferOHinMH = ((bestOH.score or 0) > (best1H.score or 0))
                                end
                            end
                        end
                    end

                    if preferOHinMH then
                        finalPick[16] = bestOH
                        finalPick[17] = best1H
                    else
                        finalPick[16] = best1H
                        finalPick[17] = bestOH
                    end
                else
                    finalPick[16] = best1H
                    finalPick[17] = bestOH
                end
            else
                if best1H then finalPick[16] = best1H end
                if bestOH then finalPick[17] = bestOH end
            end
        end
    elseif finalPick[16] and not finalPick[17] then
        if not finalPick[16].is2H and best[17] then
            for _, itm in ipairs(best[17]) do
                if not itm.is2H and (finalPick[16].physId ~= itm.physId) then
                    local itemID = itm.itemID
                    local pickedID = finalPick[16].itemID
                    local isUnique = false
                    if itemID and pickedID and itemID == pickedID then
                        local unique = select(17, GetItemInfo(itm.link))
                        isUnique = unique or false
                    end
                    if not isUnique then
                        finalPick[17] = itm
                        break
                    end
                end
            end
        end
    elseif not finalPick[16] and finalPick[17] then
        local hasFrostbane = (specID == 251) and common.is_talent_known(FROSTBANE_TALENT_ID)
        if best[16] then
            local pickedItem = nil
            if hasFrostbane then
                for _, itm in ipairs(best[16]) do
                    if not itm.is2H and (finalPick[17].physId ~= itm.physId) and sfui.highest.HasRazoriceEnchant(itm) then
                        local itemID = itm.itemID
                        local pickedID = finalPick[17].itemID
                        local isUnique = false
                        if itemID and pickedID and itemID == pickedID then
                            local unique = select(17, GetItemInfo(itm.link))
                            isUnique = unique or false
                        end
                        if not isUnique then
                            pickedItem = itm
                            break
                        end
                    end
                end
            end
            if pickedItem then
                finalPick[16] = pickedItem
            else
                for _, itm in ipairs(best[16]) do
                    if not itm.is2H and (finalPick[17].physId ~= itm.physId) then
                        local itemID = itm.itemID
                        local pickedID = finalPick[17].itemID
                        local isUnique = false
                        if itemID and pickedID and itemID == pickedID then
                            local unique = select(17, GetItemInfo(itm.link))
                            isUnique = unique or false
                        end
                        if not isUnique then
                            finalPick[16] = itm
                            break
                        end
                    end
                end
            end
        end
    end

    -- Enforce Off Hand weapon safety: "One-Handed" or "Off Hand", never "Main-Hand Only"
    if finalPick[17] and finalPick[17].itemEquipLoc == "INVTYPE_WEAPONMAINHAND" then
        finalPick[17] = nil
    end

    -- Classic Rogue without Dual Wield: unequip any offhand weapon
    local isRogueClass = isClassicSpec and (classID == 1488 or specID == 1488 or (specID and specID >= 14881 and specID <= 14883))
    if isRogueClass then
        local hasDualWield = sfui.common.is_rogue_dual_wield_known and sfui.common.is_rogue_dual_wield_known() or false
        if not hasDualWield then
            finalPick[17] = nil
            local curOH = GetInventoryItemLink("player", 17)
            if curOH then
                local _, _, _, equipLoc = common.get_item_instant_info(curOH)
                if equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONOFFHAND" then
                    finalPick[17] = { isUnequip = true, isEquipped = false }
                end
            end
        end
    end

    if _G.SFUI_DEBUG_WEAPONS and best[16] then
        sfui.common.print("|cffffff00[debug] slot 16 evaluated:|r")
        for i, itm in ipairs(best[16]) do
            sfui.common.print("  [" .. i .. "]", itm.link, "score:", math.floor(itm.score), "is2h:", tostring(itm.is2H))
        end
        if best2H then sfui.common.print("  best2h:", best2H.link) end
        if finalPick[16] then sfui.common.print("  winner:", finalPick[16].link) else sfui.common.print("  winner: none") end
        _G.SFUI_DEBUG_WEAPONS = false
    end
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Embellishments Solver (force_2emb)
-- ══════════════════════════════════════════════════════════════════════════════
function sfui.highest.SolveEmbellishments(best, finalPick, specDB)
    local force_2emb = specDB and (specDB.force_2emb == true or specDB.force_2embellishments == true or specDB.force_embellishment == true)
    if not force_2emb then return end

    local currentEmbCount = 0
    for _, itm in pairs(finalPick) do
        if itm.isEmbellished then
            currentEmbCount = currentEmbCount + 1
        end
    end
    local embNeeded = 2 - currentEmbCount
    if embNeeded <= 0 then return end

    local embCandidates = {}
    for s = 1, 15 do
        if not finalPick[s] and best[s] then
            local bestOverallScore = (best[s][1] and best[s][1].score) or 0
            for _, itm in ipairs(best[s]) do
                if itm.isEmbellished then
                    local cost = bestOverallScore - itm.score
                    if cost < 0 then cost = 0 end
                    table.insert(embCandidates, { slot = s, itm = itm, cost = cost })
                end
            end
        end
    end

    table.sort(embCandidates, function(a, b) return a.cost < b.cost end)

    local embAssigned = 0
    for _, cand in ipairs(embCandidates) do
        if embAssigned >= embNeeded then break end
        if not finalPick[cand.slot] then
            local conflict = false
            local itemID = cand.itm.itemID
            for _, picked in pairs(finalPick) do
                if picked.physId == cand.itm.physId then
                    conflict = true; break
                end
                if itemID and picked.itemID and picked.itemID == itemID then
                    local isUnique = select(17, GetItemInfo(cand.itm.link))
                    if isUnique then
                        conflict = true; break
                    end
                end
            end
            if not conflict then
                finalPick[cand.slot] = cand.itm
                if not cand.itm.equipReason then
                    cand.itm.equipReason = "Embellishment"
                end
                embAssigned = embAssigned + 1
            end
        end
    end
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Remaining Slots & Unique Item Constraints Solver
-- ══════════════════════════════════════════════════════════════════════════════
function sfui.highest.SolveRemainingSlots(best, finalPick, isClassicSpec, usesAmmo)
    local totalEmbCount = 0
    for _, itm in pairs(finalPick) do
        if itm.isEmbellished then
            totalEmbCount = totalEmbCount + 1
        end
    end

    local maxNonWeaponSlot = isClassicSpec and 18 or 15
    for slotID = 1, maxNonWeaponSlot do
        if slotID ~= 16 and slotID ~= 17 then
            if not finalPick[slotID] then -- Skip slots already claimed
                local items = best[slotID]
                if items then
                    for _, itm in ipairs(items) do
                        local alreadyPicked = false
                        local itemID = itm.itemID

                        -- Hard game limit: maximum 2 active embellishments allowed
                        if itm.isEmbellished and totalEmbCount >= 2 then
                            alreadyPicked = true
                        end

                        if not alreadyPicked then
                            for _, picked in pairs(finalPick) do
                                if picked.physId == itm.physId then
                                    alreadyPicked = true; break
                                end
                                if itemID and picked.itemID and picked.itemID == itemID then
                                    local isUnique = select(17, GetItemInfo(itm.link))
                                    if isUnique then
                                        alreadyPicked = true; break
                                    end
                                end
                            end
                        end

                        if not alreadyPicked then
                            finalPick[slotID] = itm
                            if itm.isEmbellished then
                                totalEmbCount = totalEmbCount + 1
                            end
                            break
                        end
                    end
                end
            end
        end
    end

    -- Process slot 0 (Ammo) for Classic / Camelot specs that use ammo
    -- Ranged weapon (slot 18) is now determined, so ammo compatibility can be strictly verified
    if isClassicSpec and usesAmmo and not finalPick[0] and best[0] then
        local rangedLink = (finalPick[18] and finalPick[18].link) or GetInventoryItemLink("player", 18)
        local neededAmmoSubclass = nil
        if rangedLink then
            local _, _, _, _, _, rClassID, rSubclassID = common.get_item_instant_info(rangedLink)
            if rClassID == 2 then -- Weapon
                if rSubclassID == 2 or rSubclassID == 18 then
                    neededAmmoSubclass = 2 -- Bows / Crossbows need Arrows
                elseif rSubclassID == 3 then
                    neededAmmoSubclass = 3 -- Guns need Bullets
                end
            end
        end

        if not neededAmmoSubclass then
            local currentAmmoLink = GetInventoryItemLink("player", 0)
            if currentAmmoLink then
                local _, _, _, _, _, aClassID, aSubclassID = common.get_item_instant_info(currentAmmoLink)
                if aClassID == 6 and (aSubclassID == 2 or aSubclassID == 3) then
                    neededAmmoSubclass = aSubclassID
                end
            end
        end

        if neededAmmoSubclass then
            for _, itm in ipairs(best[0]) do
                local _, _, _, _, _, aClassID, aSubclassID = common.get_item_instant_info(itm.link)
                if aClassID == 6 and aSubclassID == neededAmmoSubclass then
                    finalPick[0] = itm
                    break
                end
            end
        end
    end
end
