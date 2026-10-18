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
local issecretvalue = _G.issecretvalue

local FROSTBANE_TALENT_ID = 455993

local function sfprint(msg)
    sfui.common.print(msg)
end

local function dbgSlotPrint(msg)
    sfprint("|cffffff00[debug]|r " .. tostring(msg))
end

local function GetInventoryItemLink(unit, slotID)
    if sfui.common and sfui.common.get_inventory_item_link then
        return sfui.common.get_inventory_item_link(unit, slotID)
    end
    return _G.GetInventoryItemLink and _G.GetInventoryItemLink(unit, slotID)
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Item Upgrade Evaluator (Loot / Feed / Tooltips)
-- ══════════════════════════════════════════════════════════════════════════════
function sfui.highest.EvaluateItemUpgrade(itemLink, overrideIlvl, currentEquippedIlvl)
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
            if mult and mult < 1.0 then
                itemLevel = itemLevel * mult
            end
        end

        if itemLevel and itemLevel > currentEquippedIlvl then
            return true
        end
        return false
    end

    -- Check Main Spec
    if CheckSpecUpgrade(activeSpecID) then return true, false end

    -- Check Off Specs
    local specs, specIDs = sfui.common.get_player_specs()
    if specIDs and #specIDs > 1 then
        for _, offSpecID in ipairs(specIDs) do
            if offSpecID ~= activeSpecID then
                if CheckSpecUpgrade(offSpecID) then return true, true end
            end
        end
    end
    return false, false
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
        if common.is_talent_known(FROSTBANE_TALENT_ID) then
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
