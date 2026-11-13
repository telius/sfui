local addonName, addon = ...
sfui.highest = sfui.highest or {}

local _G = _G
local common = sfui.common
local GetItemInfo = sfui.common.get_item_info
local C_TooltipInfo = _G.C_TooltipInfo
local tonumber = _G.tonumber
local tostring = _G.tostring
local pairs = _G.pairs
local ipairs = _G.ipairs
local string = _G.string
local table = _G.table
local wipe = _G.wipe
local issecretvalue = sfui.common.issecretvalue

local FROSTBANE_TALENT_ID = 455993
local BREATH_OF_SINDRAGOSA_ID_1 = 1249658
local BREATH_OF_SINDRAGOSA_ID_2 = 152279

local function sfprint(msg)
    sfui.common.print(msg)
end

local function dbgSlotPrint(msg)
    sfprint("|cffffff00[debug]|r " .. tostring(msg))
end

local GetInventoryItemLink = sfui.common.get_inventory_item_link

-- ══════════════════════════════════════════════════════════════════════════════
-- Rich Stat-Weighted Item Upgrade Evaluator (Tooltips / DJ / Lootfeed / Quests)
-- ══════════════════════════════════════════════════════════════════════════════
sfui.gear = sfui.gear or {}

local _upgradeEvalCache = {}
local _upgradeEvalCount = 0
local UPGRADE_EVAL_CACHE_MAX = 400
local _evalTargetSlots = {}

local function InvalidateUpgradeEvalCache()
    wipe(_upgradeEvalCache)
    _upgradeEvalCount = 0
end
sfui.highest.InvalidateUpgradeEvalCache = InvalidateUpgradeEvalCache

local function ResolveEffectiveSpecContext(specID, isPvP)
    if not specID or specID == 0 then return nil end
    local rule = (sfui.highest.GetRule and sfui.highest.GetRule(specID)) or (sfui.highest.rules and sfui.highest.rules[specID])
    if not rule then return nil end

    local isClassicSpec = sfui.highest.isClassicOrVanilla()
    local playerClass, pClassID = sfui.talents.get_player_class()
    local classID = isClassicSpec and ((sfui.gear and sfui.gear.GetClassicClassID and sfui.gear.GetClassicClassID(specID)) or (specID >= 1482 and specID <= 1491 and specID)) or pClassID

    local isPaladin = (playerClass == "PALADIN" or classID == 1486 or specID == 1486 or specID == 65 or specID == 66 or specID == 70 or (specID >= 14861 and specID <= 14863))
    local isWarrior = (playerClass == "WARRIOR" or classID == 1491 or specID == 1491 or specID == 71 or specID == 72 or specID == 73 or (specID >= 14911 and specID <= 14913))
    local isShaman  = (playerClass == "SHAMAN" or classID == 1489 or specID == 1489 or specID == 262 or specID == 263 or specID == 264 or (specID >= 14891 and specID <= 14893))
    local isDruid   = (playerClass == "DRUID" or classID == 1484 or specID == 1484 or specID == 102 or specID == 103 or specID == 104 or specID == 105 or (specID >= 14841 and specID <= 14844))
    local isPriest  = (playerClass == "PRIEST" or classID == 1487 or specID == 1487 or specID == 256 or specID == 257 or specID == 258 or (specID >= 14871 and specID <= 14873))
    local isRogue   = (playerClass == "ROGUE" or classID == 1488 or specID == 1488 or specID == 259 or specID == 260 or specID == 261 or (specID >= 14881 and specID <= 14883))
    local isHunter  = (playerClass == "HUNTER" or classID == 1485 or specID == 1485 or specID == 253 or specID == 254 or specID == 255 or (specID >= 14851 and specID <= 14853))

    if not isClassicSpec and specID == 251 then
        if common.is_talent_known(FROSTBANE_TALENT_ID) or common.is_talent_known(BREATH_OF_SINDRAGOSA_ID_1) or common.is_talent_known(BREATH_OF_SINDRAGOSA_ID_2) then
            rule = { armor = rule.armor, stat = rule.stat, weaps = { ["1H_Dual"] = true, ["2H"] = false }, allowedWeapons = rule.allowedWeapons }
        end
    elseif not isClassicSpec and specID == 70 then
        rule = { armor = rule.armor, stat = rule.stat, weaps = { ["2H"] = true }, allowedWeapons = rule.allowedWeapons }
    end

    local b = sfui.talents and sfui.talents.SPEC_BRIDGE and sfui.talents.SPEC_BRIDGE[specID]
    local specDB
    if isClassicSpec then
        specDB = SfuiDB and SfuiDB.gear and (SfuiDB.gear[specID] or (b and b.camelotID and SfuiDB.gear[b.camelotID]) or (b and b.classID and SfuiDB.gear[b.classID]))
    else
        specDB = SfuiDB and SfuiDB.gear and SfuiDB.gear[specID]
    end
    local classicRole = (specDB and specDB.classic_role) or (sfui.gear and sfui.gear.GetClassicRole and sfui.gear.GetClassicRole(specID, specDB))
    local cRoleLower = classicRole and classicRole:lower()
    local isTank = (specDB and (specDB.is_tank or specDB.armor_ilvl_prio))
        or (cRoleLower == "tank" or cRoleLower == "bear" or cRoleLower == "prot")
        or (sfui.gear and sfui.gear.IsTankSpec and sfui.gear.IsTankSpec(specID, specDB)) or false
    local isHeal = (specDB and specDB.is_healer)
        or (cRoleLower == "heal" or cRoleLower == "resto" or cRoleLower == "holy" or cRoleLower == "disc")
        or (sfui.gear and sfui.gear.IsHealerSpec and sfui.gear.IsHealerSpec(specID, specDB)) or false
    local isRetPaladin = isClassicSpec and (isPaladin or classID == 1486) and not isTank and not isHeal

    if isClassicSpec then
        if isRogue then
            local hasDualWield = sfui.common.is_rogue_dual_wield_known and sfui.common.is_rogue_dual_wield_known() or false
            if not hasDualWield then
                rule = { armor = rule.armor, stat = rule.stat, weaps = { ["1H_Main"] = true, ["1H_Dual"] = false, ["Ranged"] = true }, allowedWeapons = rule.allowedWeapons }
            end
        end
        if isTank and (isWarrior or isPaladin) then
            rule = { armor = rule.armor, stat = rule.stat, weaps = { ["1H_Shield"] = true, ["Ranged"] = isWarrior }, allowedWeapons = rule.allowedWeapons }
        elseif isHeal then
            if isPaladin or isShaman then
                rule = { armor = rule.armor, stat = 4, weaps = { ["1H_Shield"] = true, ["1H_Off"] = true, ["2H"] = true }, allowedWeapons = rule.allowedWeapons }
            elseif isDruid then
                rule = { armor = rule.armor, stat = 4, weaps = { ["1H_Off"] = true, ["2H"] = true }, allowedWeapons = rule.allowedWeapons }
            elseif isPriest then
                rule = { armor = rule.armor, stat = 4, weaps = { ["1H_Off"] = true, ["2H"] = true, ["Ranged"] = true }, allowedWeapons = rule.allowedWeapons }
            end
        else
            if isPaladin then
                rule = { armor = rule.armor, stat = 1, weaps = { ["2H"] = true, ["1H_Shield"] = true, ["1H_Off"] = true }, allowedWeapons = rule.allowedWeapons }
            elseif isWarrior then
                rule = { armor = rule.armor, stat = 1, weaps = { ["2H"] = true, ["1H_Dual"] = true, ["1H_Shield"] = true, ["Ranged"] = true }, allowedWeapons = rule.allowedWeapons }
            elseif isDruid then
                local isMoon = (cRoleLower == "moon" or specID == 14841 or specID == 102)
                rule = { armor = rule.armor, stat = isMoon and 4 or (cRoleLower == "cat" and 2 or 1), weaps = { ["2H"] = true, ["1H_Off"] = true }, allowedWeapons = rule.allowedWeapons }
            elseif isShaman then
                local isEle = (cRoleLower == "ele" or specID == 14891 or specID == 262)
                rule = { armor = rule.armor, stat = isEle and 4 or 1, weaps = { ["2H"] = true, ["1H_Shield"] = true, ["1H_Off"] = true }, allowedWeapons = rule.allowedWeapons }
            end
        end
    end

    local pweights, statWeights = sfui.highest.ResolveStatWeights(specID, rule, specDB)
    local forceIlvl = specDB and (specDB.force_ilvl == true)
    local armorIlvlPrio = (specDB and specDB.armor_ilvl_prio)
    if armorIlvlPrio == nil then armorIlvlPrio = isTank end
    local usesAmmo = sfui.api and sfui.api.UnitUsesAmmo and sfui.api.UnitUsesAmmo("player")

    local roleLabel = cRoleLower
    if not roleLabel or roleLabel == "" then
        local spName = common.get_spec_name and common.get_spec_name(specID)
        if spName and spName ~= "" then
            roleLabel = spName:lower()
        elseif isTank then
            roleLabel = "tank"
        elseif isHeal then
            roleLabel = "heal"
        else
            roleLabel = "dps"
        end
    end

    return {
        rule = rule,
        specDB = specDB,
        pweights = pweights,
        statWeights = statWeights,
        forceIlvl = forceIlvl,
        armorIlvlPrio = armorIlvlPrio,
        roleLabel = roleLabel,
        context = {
            isClassicSpec = isClassicSpec,
            isPvP = isPvP == true,
            forceIlvl = forceIlvl,
            isTank = isTank,
            isHeal = isHeal,
            isHunter = isHunter,
            isRetPaladin = isRetPaladin,
            classID = classID,
            playerClass = playerClass,
            usesAmmo = usesAmmo,
            prioritizeIlvl = false,
        },
    }
end

local function BuildScoredItemObj(link, slotID, specID, st, isEquipped)
    local _, _, itemQuality, baseIlvl, minLvl, _, _, _, instEquipLoc = GetItemInfo(link)
    if not instEquipLoc or instEquipLoc == "" then
        local _, _, _, eqLoc = common.get_item_instant_info(link)
        instEquipLoc = eqLoc
    end
    if not instEquipLoc or instEquipLoc == "" then return nil end

    local ilvl = common.get_item_level(link)
    if not ilvl or ilvl <= 0 then ilvl = baseIlvl or 1 end

    local rule = st.rule
    local isClassicSpec = st.context.isClassicSpec
    local primaryStatKey = common.get_stat_key(rule.stat)
    local statVal = sfui.highest.GetPrimaryStatValue and sfui.highest.GetPrimaryStatValue(link, primaryStatKey) or 0
    local obj = {
        link = link,
        itemID = common.get_item_id(link),
        setID = select(16, GetItemInfo(link)),
        ilvl = ilvl,
        minLevel = minLvl or 0,
        quality = itemQuality or common.get_item_quality(link) or 1,
        statVal = statVal,
        is2H = ((instEquipLoc == "INVTYPE_2HWEAPON" and not rule.weaps["2H_Dual"]) or ((not isClassicSpec) and (instEquipLoc == "INVTYPE_RANGED" or instEquipLoc == "INVTYPE_RANGEDRIGHT"))),
        isEquipped = isEquipped == true,
        equippedSlot = isEquipped and slotID or nil,
        itemEquipLoc = instEquipLoc,
        score = 0,
        statScore = 0,
        isEmbellished = sfui.highest.HasEmbellishment and sfui.highest.HasEmbellishment({ link = link, equippedSlot = isEquipped and slotID or nil }) or false,
        isLockedItem = false,
    }
    local ARMOR_SLOTS = sfui.highest.ARMOR_SLOTS
    local isArmor = ARMOR_SLOTS and ARMOR_SLOTS[slotID] == true
    local isWeaponSlot = (slotID == 16 or slotID == 17 or (isClassicSpec and slotID == 18))
    st.context.prioritizeIlvl = st.forceIlvl or (isArmor and st.armorIlvlPrio) or isWeaponSlot
    sfui.highest.ScoreItem(obj, slotID, specID, rule, st.pweights, st.statWeights, st.context)
    return obj
end

local function GetTwoHandPairBonus(itm, isClassicSpec, isPvP)
    local mult = isClassicSpec and 10 or (isPvP and 100 or 1000)
    local bonus = (itm.ilvl or 1) * mult
    if isClassicSpec then
        local q = itm.quality or 1
        local qBonus = (q == 5 and 2500)
            or (q == 4 and 1200)
            or (q == 3 and 600)
            or (q == 2 and 250)
            or (q == 1 and 20)
            or 0
        bonus = bonus + qBonus
    end
    return bonus
end

local function GetEquippedSlotLink(slotID)
    if sfui.inventory then
        if sfui.inventory.GetEquippedLink then
            local link = sfui.inventory.GetEquippedLink(slotID)
            if link and link ~= "" then
                return link
            end
        elseif sfui.inventory.GetEquipped then
            local eq = sfui.inventory.GetEquipped(slotID)
            if type(eq) == "table" and eq.link and eq.link ~= "" then
                return eq.link
            elseif type(eq) == "string" and eq ~= "" then
                return eq
            end
        end
    end
    return GetInventoryItemLink("player", slotID)
end

local function EvaluateCandidateAgainstSpec(itemLink, specID, ignorePlayerLevel, isOffSpec)
    local isValid, _, _, itemEquipLoc = sfui.highest.IsItemValidForSpec(itemLink, specID, ignorePlayerLevel)
    if not isValid or not itemEquipLoc or itemEquipLoc == "" then
        return nil
    end

    local st = ResolveEffectiveSpecContext(specID, false)
    if not st or not st.rule then return nil end

    local numSlots = common.populate_slots_for_invtype(_evalTargetSlots, itemEquipLoc, st.rule.weaps["1H_Dual"], st.rule.weaps["2H_Dual"])
    if not numSlots or numSlots <= 0 then return nil end

    local candID = common.get_item_id(itemLink)
    local isUnique = select(17, GetItemInfo(itemLink))
    local lockedSlotMatch = nil
    if candID and isUnique then
        for i = 1, numSlots do
            local s = _evalTargetSlots[i]
            local eqLink = GetEquippedSlotLink(s)
            if eqLink and common.get_item_id(eqLink) == candID then
                lockedSlotMatch = s
                break
            end
        end
    end

    local bestGainPct = nil
    local bestScoreDelta = 0
    local bestIlvlDelta = 0
    local bestSlot = nil
    local requiresHigherLevel = false
    local playerLvl = _G.UnitLevel and _G.UnitLevel("player") or 1

    for i = 1, numSlots do
        local slotID = _evalTargetSlots[i]
        if not lockedSlotMatch or lockedSlotMatch == slotID then
            local candObj = BuildScoredItemObj(itemLink, slotID, specID, st, false)
            if candObj and (candObj.score or 0) > 0 then
                if (candObj.minLevel or 0) > playerLvl then
                    requiresHigherLevel = true
                end

                local eqLink = GetEquippedSlotLink(slotID)
                if eqLink ~= itemLink then
                    local candEff = candObj.score or 0
                    local eqEff = 0
                    local eqIlvl = 0

                    if slotID == 16 and candObj.is2H then
                        local eq16 = eqLink and BuildScoredItemObj(eqLink, 16, specID, st, true)
                        local eq17Link = GetEquippedSlotLink(17)
                        local eq17 = eq17Link and BuildScoredItemObj(eq17Link, 17, specID, st, true)
                        if eq16 and eq17 and not eq16.is2H then
                            candEff = candEff + GetTwoHandPairBonus(candObj, st.context.isClassicSpec, false)
                            eqEff = (eq16.score or 0) + (eq17.score or 0)
                            eqIlvl = ((eq16.ilvl or 0) + (eq17.ilvl or 0)) * 0.5
                        elseif eq16 then
                            eqEff = eq16.score or 0
                            eqIlvl = eq16.ilvl or 0
                        end
                    elseif (slotID == 16 or slotID == 17) and not candObj.is2H then
                        local eq16Link = GetEquippedSlotLink(16)
                        local eq16 = eq16Link and BuildScoredItemObj(eq16Link, 16, specID, st, true)
                        if eq16 and eq16.is2H then
                            eqEff = ((eq16.score or 0) + GetTwoHandPairBonus(eq16, st.context.isClassicSpec, false)) * 0.5
                            eqIlvl = eq16.ilvl or 0
                        elseif eqLink then
                            local eqObj = BuildScoredItemObj(eqLink, slotID, specID, st, true)
                            eqEff = eqObj and eqObj.score or 0
                            eqIlvl = eqObj and eqObj.ilvl or 0
                        end
                    elseif eqLink then
                        local eqObj = BuildScoredItemObj(eqLink, slotID, specID, st, true)
                        eqEff = eqObj and eqObj.score or 0
                        eqIlvl = eqObj and eqObj.ilvl or 0
                    end

                    local delta = candEff - eqEff
                    if delta > 0.5 then
                        local pct = (eqEff > 0) and ((delta / eqEff) * 100) or 100
                        if pct >= 0.2 and (not bestGainPct or pct > bestGainPct) then
                            bestGainPct = pct
                            bestScoreDelta = delta
                            bestIlvlDelta = (candObj.ilvl or 0) - eqIlvl
                            bestSlot = slotID
                        end
                    end
                end
            end
        end
    end

    if bestGainPct and bestSlot then
        return {
            isUpgrade = true,
            pctGain = bestGainPct,
            scoreDelta = bestScoreDelta,
            ilvlDelta = bestIlvlDelta,
            isOffSpec = isOffSpec == true,
            slotID = bestSlot,
            specID = specID,
            roleLabel = st.roleLabel,
            requiresHigherLevel = requiresHigherLevel,
        }
    end
    return nil
end

function sfui.gear.EvaluateItemUpgrade(itemLinkOrID, explicitSpecID, ignorePlayerLevel)
    if not itemLinkOrID then return nil end
    if issecretvalue and issecretvalue(itemLinkOrID) then return nil end

    local itemLink = itemLinkOrID
    if type(itemLinkOrID) == "number" then
        if itemLinkOrID <= 0 or itemLinkOrID ~= itemLinkOrID then
            return nil
        end
        local _, resolved = GetItemInfo(itemLinkOrID)
        itemLink = resolved or ("item:" .. tostring(itemLinkOrID))
    elseif type(itemLinkOrID) ~= "string" or itemLinkOrID == "" then
        return nil
    end

    local name = GetItemInfo(itemLink)
    if not name then
        local id = common.get_item_id(itemLink)
        if id and common.request_item_load then
            common.request_item_load(id)
        end
        return nil
    end

    local ignoreLvl = (ignorePlayerLevel ~= false)
    local activeSpecID = explicitSpecID or sfui.common.get_current_spec_id()
    if not activeSpecID or activeSpecID == 0 then return nil end

    local cacheKey = itemLink .. ":" .. tostring(activeSpecID) .. ":" .. (explicitSpecID and "x" or "a") .. ":" .. (ignoreLvl and "1" or "0")
    local cached = _upgradeEvalCache[cacheKey]
    if cached ~= nil then
        return cached ~= false and cached or nil
    end

    local res = EvaluateCandidateAgainstSpec(itemLink, activeSpecID, ignoreLvl, false)
    if not res and not explicitSpecID then
        local _, specIDs = sfui.common.get_player_specs()
        if specIDs and #specIDs > 1 then
            for _, offSpecID in ipairs(specIDs) do
                if offSpecID ~= activeSpecID then
                    local offRes = EvaluateCandidateAgainstSpec(itemLink, offSpecID, ignoreLvl, true)
                    if offRes then
                        res = offRes
                        break
                    end
                end
            end
        end
    end

    if _upgradeEvalCount >= UPGRADE_EVAL_CACHE_MAX then
        wipe(_upgradeEvalCache)
        _upgradeEvalCount = 0
    end
    _upgradeEvalCount = _upgradeEvalCount + 1
    _upgradeEvalCache[cacheKey] = res or false
    return res
end
sfui.highest.EvaluateDetailedUpgrade = sfui.gear.EvaluateItemUpgrade

function sfui.highest.EvaluateItemUpgrade(itemLink, overrideIlvl, currentEquippedIlvl)
    if type(currentEquippedIlvl) == "number" then
        if not itemLink then return false, false end
        local activeSpecID = sfui.common.get_current_spec_id()
        if not activeSpecID or activeSpecID == 0 then return false, false end
        local function CheckSpecUpgrade(specID)
            local isValid, baseIlvl = sfui.highest.IsItemValidForSpec(itemLink, specID)
            if not isValid then return false end
            local itemLevel = overrideIlvl or baseIlvl or 1
            local _, _, _, itemEquipLoc = common.get_item_instant_info(itemLink)
            if itemEquipLoc == "INVTYPE_TRINKET" then
                local mult = common.get_trinket_value_multiplier(itemLink, specID)
                if mult and mult < 1.0 then itemLevel = itemLevel * mult end
            end
            return itemLevel and itemLevel > currentEquippedIlvl or false
        end
        if CheckSpecUpgrade(activeSpecID) then return true, false end
        local _, specIDs = sfui.common.get_player_specs()
        if specIDs and #specIDs > 1 then
            for _, offSpecID in ipairs(specIDs) do
                if offSpecID ~= activeSpecID and CheckSpecUpgrade(offSpecID) then
                    return true, true
                end
            end
        end
        return false, false
    end

    local res = sfui.gear.EvaluateItemUpgrade(itemLink, nil, false)
    if res and res.isUpgrade then
        return true, res.isOffSpec == true, res
    end
    return false, false, nil
end

if sfui.events then
    local function onGearContextChanged()
        InvalidateUpgradeEvalCache()
    end
    if sfui.events.RegisterMessage then
        sfui.events.RegisterMessage("SFUI_EQUIPMENT_DELTA", onGearContextChanged)
        sfui.events.RegisterMessage("SFUI_ROLE_CONTEXT_CHANGED", onGearContextChanged)
    end
    if sfui.events.RegisterEvent then
        sfui.events.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", onGearContextChanged)
        sfui.events.RegisterEvent("PLAYER_LEVEL_UP", onGearContextChanged)
        if sfui.isRetail then
            sfui.events.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", onGearContextChanged)
            sfui.events.RegisterEvent("TRAIT_CONFIG_UPDATED", onGearContextChanged)
        else
            sfui.events.RegisterEvent("CHARACTER_POINTS_CHANGED", onGearContextChanged)
            sfui.events.RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", onGearContextChanged)
        end
    end
end

if sfui.tooltips and sfui.tooltips.RegisterItemProvider then
    sfui.tooltips.RegisterItemProvider("gear_upgrade", 10, function(tooltip, ctx)
        if SfuiDB and SfuiDB.enableUpgradeTooltips == false then return end
        if not ctx.itemLink and not ctx.itemID then return end
        if not ctx.equipLoc or ctx.equipLoc == "" or ctx.equipLoc == "INVTYPE_NON_EQUIP" or ctx.equipLoc == "INVTYPE_BAG" then
            return
        end

        -- Skip when hovering currently equipped CharacterFrame slots so Ring 1 never claims to upgrade Ring 2
        local owner = tooltip.GetOwner and tooltip:GetOwner()
        if owner and owner.GetParent and _G.PaperDollItemsFrame and owner:GetParent() == _G.PaperDollItemsFrame then
            return
        end

        local eval = sfui.gear.EvaluateItemUpgrade(ctx.itemLink or ctx.itemID, nil, true)
        if not eval or not eval.isUpgrade then return end

        local pctStr = (eval.pctGain >= 99.5) and "empty slot" or string.format("+%.1f%%", eval.pctGain)
        local roleSuffix = (eval.roleLabel and eval.roleLabel ~= "") and (" (" .. eval.roleLabel .. ")") or ""
        local lvlNote = eval.requiresHigherLevel and " · higher lvl" or ""

        if eval.isOffSpec then
            tooltip:AddLine(string.format("|cff66ccffoff-spec upgrade:|r %s%s%s", pctStr, roleSuffix, lvlNote))
        else
            tooltip:AddLine(string.format("|cff33ff88upgrade:|r %s%s%s", pctStr, roleSuffix, lvlNote))
        end
    end)
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Best Items Engine Coordinator
-- ══════════════════════════════════════════════════════════════════════════════
function sfui.highest.GetBestItems(isPvP)
    local specID = sfui.common.get_current_spec_id()
    if not specID or specID == 0 then return nil end
    local rule = (sfui.highest.GetRule and sfui.highest.GetRule(specID)) or sfui.highest.rules[specID]
    if not rule then return nil end

    local isClassicSpec = sfui.highest.isClassicOrVanilla()
    local playerClass, pClassID = sfui.talents.get_player_class()
    local classID = isClassicSpec and ((sfui.gear and sfui.gear.GetClassicClassID and sfui.gear.GetClassicClassID(specID)) or (specID and specID >= 1482 and specID <= 1491 and specID)) or pClassID

    local isPaladin = (playerClass == "PALADIN" or classID == 1486 or specID == 1486 or specID == 65 or specID == 66 or specID == 70 or (specID and specID >= 14861 and specID <= 14863))
    local isWarrior = (playerClass == "WARRIOR" or classID == 1491 or specID == 1491 or specID == 71 or specID == 72 or specID == 73 or (specID and specID >= 14911 and specID <= 14913))
    local isShaman  = (playerClass == "SHAMAN" or classID == 1489 or specID == 1489 or specID == 262 or specID == 263 or specID == 264 or (specID and specID >= 14891 and specID <= 14893))
    local isDruid   = (playerClass == "DRUID" or classID == 1484 or specID == 1484 or specID == 102 or specID == 103 or specID == 104 or specID == 105 or (specID and specID >= 14841 and specID <= 14844))
    local isPriest  = (playerClass == "PRIEST" or classID == 1487 or specID == 1487 or specID == 256 or specID == 257 or specID == 258 or (specID and specID >= 14871 and specID <= 14873))
    local isRogue   = (playerClass == "ROGUE" or classID == 1488 or specID == 1488 or specID == 259 or specID == 260 or specID == 261 or (specID and specID >= 14881 and specID <= 14883))
    local isDK      = (playerClass == "DEATHKNIGHT" or classID == 1483 or specID == 1483 or specID == 250 or specID == 251 or specID == 252 or (specID and specID >= 14831 and specID <= 14833))
    local isHunter  = (playerClass == "HUNTER" or classID == 1485 or specID == 1485 or specID == 253 or specID == 254 or specID == 255 or (specID and specID >= 14851 and specID <= 14853))

    -- Dynamic Frost DK Talent Overrides
    if not isClassicSpec and specID == 251 then
        if common.is_talent_known(FROSTBANE_TALENT_ID) or common.is_talent_known(BREATH_OF_SINDRAGOSA_ID_1) or common.is_talent_known(BREATH_OF_SINDRAGOSA_ID_2) then
            rule = { armor = rule.armor, stat = rule.stat, weaps = { ["1H_Dual"] = true, ["2H"] = false }, allowedWeapons = rule.allowedWeapons }
        end
    end

    -- Retail Retribution Paladin (70): ALWAYS use 2H weapons exclusively
    if not isClassicSpec and specID == 70 then
        rule = { armor = rule.armor, stat = rule.stat, weaps = { ["2H"] = true }, allowedWeapons = rule.allowedWeapons }
    end

    local b = sfui.talents.SPEC_BRIDGE[specID]
    local specDB = nil
    if isClassicSpec then
        specDB = SfuiDB and SfuiDB.gear and (SfuiDB.gear[specID] or (b and b.camelotID and SfuiDB.gear[b.camelotID]) or (b and b.classID and SfuiDB.gear[b.classID]))
    else
        specDB = SfuiDB and SfuiDB.gear and SfuiDB.gear[specID]
    end
    local classicRole = (specDB and specDB.classic_role) or (sfui.gear and sfui.gear.GetClassicRole and sfui.gear.GetClassicRole(specID, specDB))
    local cRoleLower = classicRole and classicRole:lower()
    local isTank = (specDB and (specDB.is_tank or specDB.armor_ilvl_prio))
        or (cRoleLower == "tank" or cRoleLower == "bear" or cRoleLower == "prot")
        or (sfui.gear and sfui.gear.IsTankSpec and sfui.gear.IsTankSpec(specID, specDB)) or false
    local isHeal = (specDB and specDB.is_healer)
        or (cRoleLower == "heal" or cRoleLower == "resto" or cRoleLower == "holy" or cRoleLower == "disc")
        or (sfui.gear and sfui.gear.IsHealerSpec and sfui.gear.IsHealerSpec(specID, specDB)) or false
    local isRetPaladin = isClassicSpec and (isPaladin or classID == 1486) and not isTank and not isHeal

    -- Classic Role Weapon & Stat Override: Warrior/Paladin tanks & Paladin/Shaman/Druid/Priest healers
    if isClassicSpec then
        if isRogue then
            local hasDualWield = sfui.common.is_rogue_dual_wield_known and sfui.common.is_rogue_dual_wield_known() or false
            if not hasDualWield then
                rule = {
                    armor = rule.armor,
                    stat = rule.stat,
                    weaps = { ["1H_Main"] = true, ["1H_Dual"] = false, ["Ranged"] = true },
                    allowedWeapons = rule.allowedWeapons,
                }
            end
        end

        if isTank and (isWarrior or isPaladin) then
            rule = {
                armor = rule.armor,
                stat = rule.stat,
                weaps = { ["1H_Shield"] = true, ["Ranged"] = isWarrior },
                allowedWeapons = rule.allowedWeapons,
            }
        elseif isHeal then
            if isPaladin or isShaman then
                rule = {
                    armor = rule.armor,
                    stat = 4,
                    weaps = { ["1H_Shield"] = true, ["1H_Off"] = true, ["2H"] = true },
                    allowedWeapons = rule.allowedWeapons,
                }
            elseif isDruid then
                rule = {
                    armor = rule.armor,
                    stat = 4,
                    weaps = { ["1H_Off"] = true, ["2H"] = true },
                    allowedWeapons = rule.allowedWeapons,
                }
            elseif isPriest then
                rule = {
                    armor = rule.armor,
                    stat = 4,
                    weaps = { ["1H_Off"] = true, ["2H"] = true, ["Ranged"] = true },
                    allowedWeapons = rule.allowedWeapons,
                }
            end
        else
            if isPaladin then
                rule = {
                    armor = rule.armor,
                    stat = 1,
                    weaps = { ["2H"] = true, ["1H_Shield"] = true, ["1H_Off"] = true },
                    allowedWeapons = rule.allowedWeapons,
                }
            elseif isWarrior then
                rule = {
                    armor = rule.armor,
                    stat = 1,
                    weaps = { ["2H"] = true, ["1H_Dual"] = true, ["1H_Shield"] = true, ["Ranged"] = true },
                    allowedWeapons = rule.allowedWeapons,
                }
            elseif isDruid then
                local isMoon = (cRoleLower == "moon" or specID == 14841 or specID == 102)
                rule = {
                    armor = rule.armor,
                    stat = isMoon and 4 or (cRoleLower == "cat" and 2 or 1),
                    weaps = { ["2H"] = true, ["1H_Off"] = true },
                    allowedWeapons = rule.allowedWeapons,
                }
            elseif isShaman then
                local isEle = (cRoleLower == "ele" or specID == 14891 or specID == 262)
                rule = {
                    armor = rule.armor,
                    stat = isEle and 4 or 1,
                    weaps = { ["2H"] = true, ["1H_Shield"] = true, ["1H_Off"] = true },
                    allowedWeapons = rule.allowedWeapons,
                }
            end
        end
    end

    -- Persistent GC Table Pooling
    sfui.highest.itemDataPool = sfui.highest.itemDataPool or {}
    sfui.highest.pooledBest = sfui.highest.pooledBest or {}
    local itemDataPool = sfui.highest.itemDataPool
    local poolIndex = 0

    local best = sfui.highest.pooledBest
    local usesAmmo = sfui.api.UnitUsesAmmo and sfui.api.UnitUsesAmmo("player")
    local startSlot = (isClassicSpec and usesAmmo) and 0 or 1
    for i = startSlot, 19 do
        best[i] = best[i] or {}
        wipe(best[i])
    end

    local pooledTargetSlots = {}
    local evaluateIndex = 0

    local function evaluate(itemLink, isEquipped, slotOverride, bag, slot)
        evaluateIndex = evaluateIndex + 1
        local isValid, baseIlvl, statVal, itemEquipLoc, itemQuality = sfui.highest.IsItemValidForSpec(itemLink, specID)
        if not isValid then return end

        -- Slot lock evaluation
        local isLockedItem = false
        do
            local itemID = common.get_item_id(itemLink)
            local specGear = itemID and SfuiDB and SfuiDB.gear and SfuiDB.gear[specID]
            local lockTable = specGear and (isPvP and specGear.locked_items_pvp or specGear.locked_items_pve)
            if not lockTable and specGear then lockTable = specGear.locked_items end
            if lockTable and lockTable[itemID] then
                if isEquipped then
                    return
                else
                    isLockedItem = true
                end
            end
        end

        local itemLevel = baseIlvl or 1

        -- PvP Tooltip parsing for scaled ilvls
        if isPvP then
            local cachedIlvl = sfui.highest.pvpIlvlCache[itemLink]
            if cachedIlvl then
                if cachedIlvl > 0 and cachedIlvl > itemLevel then
                    itemLevel = cachedIlvl
                end
            else
                local foundScaling = false
                local tooltipData = C_TooltipInfo and C_TooltipInfo.GetHyperlink and C_TooltipInfo.GetHyperlink(itemLink)
                if tooltipData then
                    for _, line in ipairs(tooltipData.lines) do
                        local leftText = line.leftText
                        if leftText then
                            local cleanText = leftText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                            local ltext = cleanText:lower()
                            if ltext:find("level") and (ltext:find("pvp") or ltext:find("arena") or ltext:find("battleground")) then
                                local pvpMatch = cleanText:match("(%d%d%d)")
                                if pvpMatch then
                                    local scaledIlvl = tonumber(pvpMatch)
                                    local maxScaled = (sfui.config and sfui.config.gear and sfui.config.gear.maxScaledILvl) or 1000
                                    if scaledIlvl and scaledIlvl > itemLevel and scaledIlvl < maxScaled then
                                        itemLevel = scaledIlvl
                                        sfui.highest.pvpCacheSet(itemLink, scaledIlvl)
                                        foundScaling = true
                                    end
                                end
                            end
                        end
                    end
                end

                if not foundScaling and tooltipData and tooltipData.lines and #tooltipData.lines > 1 then
                    sfui.highest.pvpCacheSet(itemLink, -1)
                end
            end
        end

        local numSlots = 0
        if slotOverride then
            numSlots = 1
            pooledTargetSlots[1] = slotOverride
        else
            numSlots = common.populate_slots_for_invtype(pooledTargetSlots, itemEquipLoc, rule.weaps["1H_Dual"], rule.weaps["2H_Dual"])
        end

        poolIndex               = poolIndex + 1
        itemDataPool[poolIndex] = itemDataPool[poolIndex] or {}
        local itemData          = itemDataPool[poolIndex]

        itemData.link           = itemLink
        itemData.itemID         = common.get_item_id(itemLink)
        itemData.setID          = select(16, GetItemInfo(itemLink))
        itemData.ilvl           = itemLevel
        itemData.quality        = itemQuality or common.get_item_quality(itemLink) or 1
        itemData.statVal        = statVal
        itemData.is2H           = ((itemEquipLoc == "INVTYPE_2HWEAPON" and not rule.weaps["2H_Dual"]) or ((not isClassicSpec) and (itemEquipLoc == "INVTYPE_RANGED" or itemEquipLoc == "INVTYPE_RANGEDRIGHT")))
        itemData.isEquipped     = isEquipped
        itemData.equippedSlot   = isEquipped and slotOverride or nil
        itemData.physId         = isEquipped and (-(slotOverride + 1000)) or evaluateIndex
        itemData.itemEquipLoc   = itemEquipLoc
        itemData.bag            = bag
        itemData.slot           = slot
        itemData.score          = nil
        itemData.statScore      = 0
        itemData.isEmbellished  = sfui.highest.HasEmbellishment(itemData)
        itemData.isLockedItem   = isLockedItem
        itemData.isTier         = nil
        itemData.equipReason    = nil

        if isLockedItem then
            if itemEquipLoc == "INVTYPE_TRINKET" then
                itemData.equipReason = "Locked Trinket"
            elseif itemEquipLoc == "INVTYPE_FINGER" then
                itemData.equipReason = "Locked Ring"
            elseif itemEquipLoc == "INVTYPE_NECK" then
                itemData.equipReason = "Locked Neck"
            elseif itemEquipLoc == "INVTYPE_AMMO" then
                itemData.equipReason = "Locked Ammo"
            elseif itemEquipLoc == "INVTYPE_RELIC" then
                if isShaman then
                    itemData.equipReason = "Locked Totem"
                elseif isPaladin then
                    itemData.equipReason = "Locked Libram"
                elseif isDruid then
                    itemData.equipReason = "Locked Idol"
                elseif isDK then
                    itemData.equipReason = "Locked Sigil"
                else
                    itemData.equipReason = "Locked Relic"
                end
            elseif itemEquipLoc == "INVTYPE_WEAPON" or itemEquipLoc == "INVTYPE_2HWEAPON" or itemEquipLoc == "INVTYPE_WEAPONMAINHAND" or itemEquipLoc == "INVTYPE_WEAPONOFFHAND" or itemEquipLoc == "INVTYPE_SHIELD" or itemEquipLoc == "INVTYPE_HOLDABLE" or itemEquipLoc == "INVTYPE_RANGED" or itemEquipLoc == "INVTYPE_RANGEDRIGHT" or itemEquipLoc == "INVTYPE_THROWN" then
                itemData.equipReason = "Locked Weapon"
            else
                itemData.equipReason = "Locked Item"
            end
        end

        for i = 1, numSlots do
            local s = pooledTargetSlots[i]
            table.insert(best[s], itemData)
            if _G.SFUI_DEBUG_SLOT and s == _G.SFUI_DEBUG_SLOT then
                local nameStr = GetItemInfo(itemLink) or itemLink
                dbgSlotPrint(string.format("[slot%d] ADDED %s | ilvl=%.0f | emb=%s | equipped=%s | bag=%s,slot=%s",
                    s, tostring(nameStr), itemLevel, tostring(itemData.isEmbellished), tostring(isEquipped),
                    tostring(bag), tostring(slot)))
            end
        end
    end

    -- 1. Scan equipped
    local maxEquippedSlot = isClassicSpec and 18 or 17
    local minEquippedSlot = (isClassicSpec and usesAmmo) and 0 or 1
    for slotID = minEquippedSlot, maxEquippedSlot do
        if slotID ~= 4 then -- skip shirt
            local link = GetInventoryItemLink("player", slotID)
            if link then
                if slotID == 0 then
                    local count = _G.GetInventoryItemCount and _G.GetInventoryItemCount("player", 0) or 0
                    if issecretvalue and issecretvalue(count) then count = 0 end
                    if type(count) == "number" and count > 0 then
                        evaluate(link, true, slotID)
                    end
                else
                    evaluate(link, true, slotID)
                end
            end
        end
    end

    -- 2. Scan bags
    sfui.common.for_each_bag_item(function(bag, slot, itemID, link)
        if link then evaluate(link, false, nil, bag, slot) end
    end, true, true, false)

    -- Resolve Stat Weights
    local pweights, statWeights = sfui.highest.ResolveStatWeights(specID, rule, specDB)

    local forceIlvl = specDB and (specDB.force_ilvl == true)
    local armorIlvlPrio = (specDB and specDB.armor_ilvl_prio)
    if armorIlvlPrio == nil then
        armorIlvlPrio = isTank
    end

    local context = {
        isClassicSpec = isClassicSpec,
        isPvP = isPvP,
        forceIlvl = forceIlvl,
        isTank = isTank,
        isHeal = isHeal,
        isHunter = isHunter,
        isRetPaladin = isRetPaladin,
        classID = classID,
        playerClass = playerClass,
        usesAmmo = usesAmmo,
        prioritizeIlvl = false,
    }

    -- Score all items
    local ARMOR_SLOTS = sfui.highest.ARMOR_SLOTS
    for slotID, items in pairs(best) do
        local isArmor = ARMOR_SLOTS[slotID] == true
        local isWeaponSlot = (slotID == 16 or slotID == 17 or (isClassicSpec and slotID == 18))
        context.prioritizeIlvl = forceIlvl or (isArmor and armorIlvlPrio) or isWeaponSlot

        for _, itm in ipairs(items) do
            sfui.highest.ScoreItem(itm, slotID, specID, rule, pweights, statWeights, context)
        end
    end

    -- Sort candidates per slot
    for slotID, items in pairs(best) do
        table.sort(items, function(a, b)
            if a.score ~= b.score then return a.score > b.score end
            if a.isEquipped ~= b.isEquipped then return a.isEquipped == true end
            return (a.physId or 0) < (b.physId or 0)
        end)
        if _G.SFUI_DEBUG_SLOT and slotID == _G.SFUI_DEBUG_SLOT then
            dbgSlotPrint("=== Slot " .. slotID .. " candidates after scoring ===")
            for rank, itm in ipairs(items) do
                local nm = GetItemInfo(itm.link) or itm.link
                dbgSlotPrint(string.format("  #%d %s | ilvl=%.0f | emb=%s | score=%.1f | equipped=%s",
                    rank, tostring(nm), itm.ilvl, tostring(itm.isEmbellished), itm.score, tostring(itm.isEquipped)))
            end
            _G.SFUI_DEBUG_SLOT = nil
        end
    end

    local finalPick = {}

    -- Protect locked slots: retain equipped locked items directly in finalPick
    local lockedSlotIDs = isClassicSpec and (usesAmmo and { 2, 11, 12, 13, 14, 16, 17, 18, 0 } or { 2, 11, 12, 13, 14, 16, 17, 18 }) or { 2, 11, 12, 13, 14, 16, 17 }
    for _, slotID in ipairs(lockedSlotIDs) do
        local link = GetInventoryItemLink("player", slotID)
        local count = (slotID == 0) and (_G.GetInventoryItemCount and _G.GetInventoryItemCount("player", 0) or 0) or 1
        if issecretvalue and issecretvalue(count) then count = 0 end
        if link and (slotID ~= 0 or (type(count) == "number" and count > 0)) then
            local itemID = common.get_item_id(link)
            local specGear = itemID and SfuiDB and SfuiDB.gear and SfuiDB.gear[specID]
            local lockTable = specGear and (isPvP and specGear.locked_items_pvp or specGear.locked_items_pve)
            if not lockTable and specGear then lockTable = specGear.locked_items end
            if lockTable and lockTable[itemID] then
                local _, _, _, itemEquipLoc = common.get_item_instant_info(link)
                local effectiveILvl = common.get_item_level(link)
                local itmObj = {
                    link = link,
                    itemID = itemID,
                    setID = select(16, GetItemInfo(link)),
                    ilvl = effectiveILvl,
                    statVal = 0,
                    is2H = ((itemEquipLoc == "INVTYPE_2HWEAPON" and not rule.weaps["2H_Dual"]) or ((not isClassicSpec) and (itemEquipLoc == "INVTYPE_RANGED" or itemEquipLoc == "INVTYPE_RANGEDRIGHT"))),
                    isEquipped = true,
                    equippedSlot = slotID,
                    physId = -(slotID + 1000),
                    itemEquipLoc = itemEquipLoc,
                    score = 9999999,
                    isLockedItem = true,
                    equipReason = (slotID == 13 or slotID == 14) and "Locked Trinket"
                        or (slotID == 11 or slotID == 12) and "Locked Ring"
                        or (slotID == 2) and "Locked Neck"
                        or (slotID == 18 and itemEquipLoc == "INVTYPE_RELIC") and (
                            isShaman and "Locked Totem"
                            or isPaladin and "Locked Libram"
                            or isDruid and "Locked Idol"
                            or isDK and "Locked Sigil"
                            or "Locked Relic"
                        )
                        or (slotID == 16 or slotID == 17 or slotID == 18) and "Locked Weapon"
                        or (slotID == 0) and "Locked Ammo"
                        or "Locked Item",
                }
                itmObj.isEmbellished = sfui.highest.HasEmbellishment(itmObj)
                finalPick[slotID] = itmObj
                best[slotID] = nil
            end
        end
    end

    -- Run Solver Pipeline
    sfui.highest.SolveTierSets(best, finalPick, specDB)
    sfui.highest.SolveWeapons(best, finalPick, specID, rule, context)
    sfui.highest.SolveEmbellishments(best, finalPick, specDB)
    sfui.highest.SolveRemainingSlots(best, finalPick, isClassicSpec, usesAmmo)

    return finalPick
end
