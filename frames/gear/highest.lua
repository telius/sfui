local addonName, addon = ...
sfui.highest = sfui.highest or {}

-- BoE items: track last attempt time so we don't spam the bind dialog
local boeAttemptedAt = {}
local BOE_RETRY_DELAY = 30 -- seconds before re-offering the bind dialog

local _G = _G
local common = sfui.common
local GetItemInfo = (_G.C_Item and _G.C_Item.GetItemInfo) or _G.GetItemInfo
local C_Item = _G.C_Item
local C_TooltipInfo = _G.C_TooltipInfo
local GetInventoryItemLink = _G.GetInventoryItemLink
local C_Container = _G.C_Container
local C_Container_GetContainerItemInfo = (_G.C_Container and _G.C_Container.GetContainerItemInfo) or _G.GetContainerItemInfo
local C_Container_GetContainerItemLink = (_G.C_Container and _G.C_Container.GetContainerItemLink) or _G.GetContainerItemLink
local C_Container_PickupContainerItem  = (_G.C_Container and _G.C_Container.PickupContainerItem) or _G.PickupContainerItem
local EquipItemByName = _G.EquipItemByName
local tonumber = _G.tonumber
local UnitLevel = _G.UnitLevel
local pairs = _G.pairs
local ipairs = _G.ipairs
local print = _G.print
local string = _G.string
local table = _G.table

-- Cached print helper — avoids repeated nil-checks on sfui.common.print throughout
local function sfprint(msg)
    if sfui.common and sfui.common.print then
        sfui.common.print(msg)
    else
        print("|cff6600ffsfui:|r " .. msg)
    end
end

-- Debug helper: set _G.SFUI_DEBUG_SLOT = <inventory slot number> in-game
-- to see a full score/validation breakdown for that slot.
-- Example: /run SFUI_DEBUG_SLOT = 3   (shoulders)
local function dbgSlotPrint(msg)
    sfprint("|cffffff00[SFUI DBG]|r " .. tostring(msg))
end



local TANK_SPECS = {
    [250]  = true, -- Blood DK
    [581]  = true, -- Vengeance DH
    [104]  = true, -- Guardian Druid
    [268]  = true, -- Brewmaster Monk
    [66]   = true, -- Protection Paladin
    [73]   = true, -- Protection Warrior
}

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

local FROSTBANE_TALENT_ID = 455993
local RAZORICE_SPELL_ID = 53343
local cachedRazoriceName = nil
local function HasRazoriceEnchant(itemData)
    if not itemData or not itemData.link then return false end
    local link = itemData.link

    -- 1. Direct enchantID check (3370 = Rune of Razorice)
    local enchantID = tonumber(link:match("item:%d+:(%d+):"))
    if enchantID == 3370 then
        return true
    end

    if not cachedRazoriceName then
        local spellName = common.get_spell_name(RAZORICE_SPELL_ID) or "Razorice"
        if spellName and spellName ~= "" then
            cachedRazoriceName = spellName:lower()
        end
    end

    -- 2. Tooltip scan for Runeforged enchant text
    if C_TooltipInfo then
        local data
        if itemData.bag and itemData.slot then
            data = C_TooltipInfo.GetBagItem(itemData.bag, itemData.slot)
        elseif itemData.equippedSlot then
            data = C_TooltipInfo.GetInventoryItem("player", itemData.equippedSlot)
        else
            data = C_TooltipInfo.GetHyperlink(link)
        end
        if data and data.lines then
            for _, line in ipairs(data.lines) do
                local txt = line.leftText
                if txt and type(txt) == "string" and txt ~= "" then
                    local lowerTxt = txt:lower()
                    if (cachedRazoriceName and lowerTxt:find(cachedRazoriceName, 1, true)) or lowerTxt:find("razorice", 1, true) then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local embellishCache = {}
local embellishCacheCount = 0
local EMBELLISH_CACHE_MAX = 300

local function HasEmbellishment(itemData)
    if not itemData or not itemData.link then return false end
    local link = itemData.link
    if embellishCache[link] ~= nil then
        return embellishCache[link]
    end

    local isEmbellished = false
    local embCat = _G["ITEM_LIMIT_CATEGORY_EMBELLISHED"]
    local embPattern = embCat and embCat:lower()

    if C_TooltipInfo then
        local data
        if itemData.bag and itemData.slot then
            data = C_TooltipInfo.GetBagItem(itemData.bag, itemData.slot)
        elseif itemData.equippedSlot then
            data = C_TooltipInfo.GetInventoryItem("player", itemData.equippedSlot)
        else
            data = C_TooltipInfo.GetHyperlink(link)
        end

        if data and data.lines then
            for _, line in ipairs(data.lines) do
                local txt = line.leftText
                if txt and type(txt) == "string" and txt ~= "" then
                    local ltxt = txt:lower()
                    if (embPattern and ltxt:find(embPattern, 1, true))
                        or ltxt:find("embellish", 1, true)
                        or ltxt:find("verziert", 1, true)
                        or ltxt:find("orné", 1, true)
                        or ltxt:find("adornad", 1, true)
                        or ltxt:find("украшен", 1, true)
                        or ltxt:find("美化", 1, true)
                        or ltxt:find("장식", 1, true) then
                        isEmbellished = true
                        break
                    end
                end
            end
        end
    end

    if embellishCacheCount >= EMBELLISH_CACHE_MAX then
        _G.wipe(embellishCache)
        embellishCacheCount = 0
    end
    embellishCacheCount = embellishCacheCount + 1
    embellishCache[link] = isEmbellished
    return isEmbellished
end

-- Spec scoring criteria and weapon proficiencies (sfui.highest.rules) are loaded from data/rules.lua

-- Checks if the item matches the primary stat
local function HasPrimaryStat(itemLink, primaryStatName, specID)
    local _, _, _, equipLoc = common.get_item_instant_info(itemLink)
    -- Shields and Relics never require primary stats in Classic
    if equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_RELIC" then return true end

    local stats = common.get_item_stats(itemLink)
    -- Fast-path mathematically sound API match
    if stats and stats[primaryStatName] then return true end

    local isClassic = sfui.isClassic or (specID and specID >= 1482 and specID <= 1491)
    if not isClassic and (specID == nil or specID == 0) then
        local curSpecID = sfui.common and sfui.common.get_current_spec_id and sfui.common.get_current_spec_id()
        if curSpecID and curSpecID >= 1482 and curSpecID <= 1491 then
            isClassic = true
            specID = curSpecID
        end
    end

    if isClassic then
        if specID == 1488 or specID == 1491 or specID == 1485 then -- Rogue, Warrior, Hunter
            if stats and (stats["ITEM_MOD_INTELLECT_SHORT"] or 0) > 0 and (stats["ITEM_MOD_STRENGTH_SHORT"] or 0) == 0 and (stats["ITEM_MOD_AGILITY_SHORT"] or 0) == 0 and (stats["ITEM_MOD_ATTACK_POWER_SHORT"] or 0) == 0 and (stats["ITEM_MOD_RANGED_ATTACK_POWER_SHORT"] or 0) == 0 then
                return false
            end
        elseif specID == 1482 or specID == 1487 or specID == 1490 then -- Mage, Priest, Warlock
            if stats and ((stats["ITEM_MOD_STRENGTH_SHORT"] or 0) > 0 or (stats["ITEM_MOD_AGILITY_SHORT"] or 0) > 0) and (stats["ITEM_MOD_INTELLECT_SHORT"] or 0) == 0 and (stats["ITEM_MOD_SPELL_POWER_SHORT"] or 0) == 0 and (stats["ITEM_MOD_SPELL_HEALING_DONE_SHORT"] or 0) == 0 then
                return false
            end
        end
        return true
    end

    -- Tooltip Fallback Check for Deceptive Base Items or un-cached stat structures
    local tooltipData = C_TooltipInfo and C_TooltipInfo.GetHyperlink(itemLink)
    if tooltipData and tooltipData.lines then
        local primaryString = _G[primaryStatName] or ""
        if primaryStatName == "ITEM_MOD_INTELLECT_SHORT" then
            primaryString = primaryString ~= "" and primaryString or "Intellect"
        elseif primaryStatName == "ITEM_MOD_AGILITY_SHORT" then
            primaryString = primaryString ~= "" and primaryString or "Agility"
        elseif primaryStatName == "ITEM_MOD_STRENGTH_SHORT" then
            primaryString = primaryString ~= "" and primaryString or "Strength"
        end

        if primaryString ~= "" then
            for _, line in ipairs(tooltipData.lines) do
                local text = line.leftText
                if text and type(text) == "string" then
                    -- If the dynamic tooltip clearly broadcasts the primary stat or main stat, we know it's there
                    if text:find(primaryString, 1, true) or text:find("Primary Stat", 1, true) or text:find("Main Stat", 1, true) then
                        return true
                    end
                end
            end
        end
    end

    -- If there's literally NO primary stats on the item, we allow it for genuine statless slots (generic trinkets/rings/necks/cloaks)
    -- and for starting area / low-level items (where items have no stats yet)
    local isStatlessSlot = (equipLoc == "INVTYPE_FINGER" or equipLoc == "INVTYPE_NECK" or equipLoc == "INVTYPE_CLOAK" or equipLoc == "INVTYPE_TRINKET")
    local hasAnyPrimary = stats and ((stats["ITEM_MOD_STRENGTH_SHORT"] or 0) > 0 or (stats["ITEM_MOD_AGILITY_SHORT"] or 0) > 0 or (stats["ITEM_MOD_INTELLECT_SHORT"] or 0) > 0)
    if not hasAnyPrimary then
        if isStatlessSlot or isClassic or (UnitLevel and UnitLevel("player") and UnitLevel("player") <= 15) then
            return true
        end
    end

    return false
end


local function GetPrimaryStatValue(itemLink, primaryStatName)
    local stats = common.get_item_stats(itemLink)
    if not stats then return 0 end
    return stats[primaryStatName] or 0
end

local pvpIlvlCache = {}
local pvpIlvlCacheCount = 0
local PVP_CACHE_MAX = 200

local function pvpCacheSet(link, val)
    if not pvpIlvlCache[link] then
        pvpIlvlCacheCount = pvpIlvlCacheCount + 1
        if pvpIlvlCacheCount > PVP_CACHE_MAX then
            -- Evict: wipe and restart
            pvpIlvlCache = {}
            pvpIlvlCacheCount = 1
        end
    end
    pvpIlvlCache[link] = val
end

local validationCache = {}
local validationCacheCount = 0
local VALIDATION_CACHE_MAX = 300

function sfui.highest.ClearCache()
    _G.wipe(validationCache)
    validationCacheCount = 0
    _G.wipe(embellishCache)
    embellishCacheCount = 0
end
sfui.highest.ClearValidationCache = sfui.highest.ClearCache

local scanTip = nil
local function GetScanTooltip()
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "SfuiHighestScanTooltip", nil, "GameTooltipTemplate")
        scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    return scanTip
end

-- Verifies if the player currently meets requirements to equip/use the item
-- (checks unlearned weapon skills, unmet class/race/level requirements via red tooltip text)
local function CanPlayerUseItem(itemLink, itemID, ignorePlayerLevel)
    if not itemLink and not itemID then return true end
    if not itemID and itemLink then
        itemID = common.get_item_id(itemLink)
    end

    if itemID and C_PlayerInfo and C_PlayerInfo.CanPlayerUseItem then
        local canUse = C_PlayerInfo.CanPlayerUseItem(itemID)
        if canUse == false then
            return false
        end
    end

    if itemLink then
        if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
            local tData = C_TooltipInfo.GetHyperlink(itemLink)
            if tData and tData.lines then
                if TooltipUtil and TooltipUtil.SurfaceArgs then
                    TooltipUtil.SurfaceArgs(tData)
                end
                for _, line in ipairs(tData.lines) do
                    local clr = line.leftColor
                    if clr and clr.r and clr.g and clr.b then
                        if clr.r > 0.85 and clr.g < 0.25 and clr.b < 0.25 then
                            local txt = line.leftText
                            local isDurability = txt and (type(txt) == "string") and (txt:find("Durability") or txt:find("Haltbarkeit") or (ITEM_DURABILITY and txt:find(ITEM_DURABILITY, 1, true)))
                            local isLevelReq = ignorePlayerLevel and txt and (type(txt) == "string") and (txt:find("Level") or (ITEM_MIN_LEVEL and txt:find(ITEM_MIN_LEVEL:match("%%d") and ITEM_MIN_LEVEL:gsub("%%d", "") or "Level", 1, true)))
                            if not isDurability and not isLevelReq then
                                return false
                            end
                        end
                    end
                    local rclr = line.rightColor
                    if rclr and rclr.r and rclr.g and rclr.b then
                        if rclr.r > 0.85 and rclr.g < 0.25 and rclr.b < 0.25 then
                            local txt = line.rightText
                            local isDurability = txt and (type(txt) == "string") and (txt:find("Durability") or txt:find("Haltbarkeit") or (ITEM_DURABILITY and txt:find(ITEM_DURABILITY, 1, true)))
                            local isLevelReq = ignorePlayerLevel and txt and (type(txt) == "string") and (txt:find("Level") or (ITEM_MIN_LEVEL and txt:find(ITEM_MIN_LEVEL:match("%%d") and ITEM_MIN_LEVEL:gsub("%%d", "") or "Level", 1, true)))
                            if not isDurability and not isLevelReq then
                                return false
                            end
                        end
                    end
                end
            end
        else
            local tip = GetScanTooltip()
            if tip then
                tip:ClearLines()
                tip:SetHyperlink(itemLink)
                local numLines = tip:NumLines() or 0
                for i = 1, numLines do
                    local fsL = _G["SfuiHighestScanTooltipTextLeft" .. i]
                    if fsL then
                        local r, g, b = fsL:GetTextColor()
                        if r and g and b and r > 0.85 and g < 0.25 and b < 0.25 then
                            local txt = fsL:GetText()
                            local isDurability = txt and (txt:find("Durability") or txt:find("Haltbarkeit") or (ITEM_DURABILITY and txt:find(ITEM_DURABILITY, 1, true)))
                            local isLevelReq = ignorePlayerLevel and txt and (txt:find("Level") or (ITEM_MIN_LEVEL and txt:find(ITEM_MIN_LEVEL:match("%%d") and ITEM_MIN_LEVEL:gsub("%%d", "") or "Level", 1, true)))
                            if not isDurability and not isLevelReq then
                                return false
                            end
                        end
                    end
                    local fsR = _G["SfuiHighestScanTooltipTextRight" .. i]
                    if fsR then
                        local r, g, b = fsR:GetTextColor()
                        if r and g and b and r > 0.85 and g < 0.25 and b < 0.25 then
                            local txt = fsR:GetText()
                            local isDurability = txt and (txt:find("Durability") or txt:find("Haltbarkeit") or (ITEM_DURABILITY and txt:find(ITEM_DURABILITY, 1, true)))
                            local isLevelReq = ignorePlayerLevel and txt and (txt:find("Level") or (ITEM_MIN_LEVEL and txt:find(ITEM_MIN_LEVEL:match("%%d") and ITEM_MIN_LEVEL:gsub("%%d", "") or "Level", 1, true)))
                            if not isDurability and not isLevelReq then
                                return false
                            end
                        end
                    end
                end
            end
        end
    end
    return true
end

-- Returns true, itemLevel, statVal, itemEquipLoc if the item is valid for the spec rules
local function IsItemValidForSpec_Internal(itemLink, specID, ignorePlayerLevel, ignoreTalents)
    local rule = sfui.highest.rules[specID]
    if not rule then return false end

    local isClassic = (sfui.compat and (sfui.compat.has.wow_forever or sfui.compat.is_classic_era or sfui.compat.is_classic))
        or (specID and specID >= 1482 and specID <= 1491)
        or (sfui.version and (sfui.version.classic_era or sfui.version.wow_forever or not sfui.version.retail))

    -- Dynamic Frost DK Talent Overrides (ignored for general loot eligibility)
    if not ignoreTalents and specID == 251 then
        if common.is_talent_known(FROSTBANE_TALENT_ID) then
            rule = { armor = rule.armor, stat = rule.stat, weaps = { ["1H_Dual"] = true, ["2H"] = false }, allowedWeapons = rule.allowedWeapons }
        end
    end

    -- Classic Role Weapon & Stat Override: Warrior/Paladin tanks & Paladin/Shaman/Druid/Priest healers
    local isTank = false
    local isHeal = false
    if isClassic then
        local specDB = SfuiDB and SfuiDB.gear and SfuiDB.gear[specID]
        isTank = (sfui.gear and sfui.gear.IsTankSpec and sfui.gear.IsTankSpec(specID, specDB)) or false
        isHeal = (sfui.gear and sfui.gear.IsHealerSpec and sfui.gear.IsHealerSpec(specID, specDB)) or false
        if isTank and (specID == 1491 or specID == 1486) then
            rule = {
                armor = rule.armor,
                stat = rule.stat,
                weaps = { ["1H_Shield"] = true, ["Ranged"] = (specID == 1491) },
                allowedWeapons = rule.allowedWeapons,
            }
        elseif isHeal then
            if specID == 1486 or specID == 1489 then -- Paladin, Shaman (Healer: 1H + Shield/Offhand or 2H, Intellect)
                rule = {
                    armor = rule.armor,
                    stat = 4, -- Intellect / Spell
                    weaps = { ["1H_Shield"] = true, ["1H_Off"] = true, ["2H"] = true },
                    allowedWeapons = rule.allowedWeapons,
                }
            elseif specID == 1484 then -- Druid (Healer: 1H + Offhand or 2H Mace/Staff, Intellect)
                rule = {
                    armor = rule.armor,
                    stat = 4,
                    weaps = { ["1H_Off"] = true, ["2H"] = true },
                    allowedWeapons = rule.allowedWeapons,
                }
            elseif specID == 1487 then -- Priest (Healer: 1H + Offhand or 2H Staff, Wand, Intellect)
                rule = {
                    armor = rule.armor,
                    stat = 4,
                    weaps = { ["1H_Off"] = true, ["2H"] = true, ["Ranged"] = true },
                    allowedWeapons = rule.allowedWeapons,
                }
            end
        end
    end

    local primaryStatName = common.get_stat_key(rule.stat)
    local optimalArmor = rule.armor

    local itemID, itemType, itemSubType, itemEquipLoc, _, classID, subclassID = common.get_item_instant_info(itemLink)
    if not itemEquipLoc or itemEquipLoc == "" then return false end

    -- Check if player can actually use/equip the item (unlearned weapon skills, unmet class, unmet level, etc.)
    if not CanPlayerUseItem(itemLink, itemID, ignorePlayerLevel) then
        return false
    end

    local itemName, _, itemQuality, baseLevel, itemMinLevel = GetItemInfo(itemLink)
    local itemLevel = common.get_item_level(itemLink)
    if itemLevel == 0 then itemLevel = baseLevel or 1 end

    -- Never auto-equip grey (0) or white (1) quality items in Retail — these are cosmetic,
    -- transmog pieces, or vendor junk and should never beat real gear in scoring.
    -- In Vanilla / Classic Forever, grey and white items are valid starting and leveling equipment.
    if not isClassic and itemQuality and itemQuality < 2 then return false end

    -- Check if the player meets the required level for the item
    if not ignorePlayerLevel and itemMinLevel and itemMinLevel > UnitLevel("player") then return false end

    -- Use robust numeric ID checks instead of localized strings. classID 4 = Armor
    if classID == 4 then
        if itemEquipLoc ~= "INVTYPE_CLOAK" and itemEquipLoc ~= "INVTYPE_FINGER" and itemEquipLoc ~= "INVTYPE_TRINKET" and itemEquipLoc ~= "INVTYPE_NECK" and itemEquipLoc ~= "INVTYPE_HOLDABLE" and itemEquipLoc ~= "INVTYPE_SHIELD" and itemEquipLoc ~= "INVTYPE_RELIC" then
            if isClassic then
                local playerLvl = UnitLevel("player") or 1
                if subclassID == 5 then
                    -- Cosmetic is always equippable
                elseif optimalArmor == 4 then
                    -- Paladins/Warriors in Vanilla:
                    -- Level < 40: Wear Mail, Leather, and at low levels (<20) starting Cloth.
                    -- Level >= 40: Plate, Mail, Leather (Tanks prefer Plate at 50+)
                    local maxSubclass = (playerLvl < 40 and not ignorePlayerLevel) and 3 or 4
                    local minSubclass = (playerLvl < 20 or ignorePlayerLevel) and 1 or 2
                    if isTank and playerLvl >= 50 and not ignorePlayerLevel then
                        minSubclass = 4
                    end
                    if subclassID > maxSubclass or subclassID < minSubclass then return false end
                elseif optimalArmor == 3 then
                    -- Hunters/Shamans in Vanilla:
                    -- Level < 40: Wear Leather, and at low levels (<20) starting Cloth.
                    -- Level >= 40: Mail and Leather
                    local maxSubclass = (playerLvl < 40 and not ignorePlayerLevel) and 2 or 3
                    local minSubclass = (playerLvl < 20 or ignorePlayerLevel) and 1 or 2
                    if subclassID > maxSubclass or subclassID < minSubclass then return false end
                elseif optimalArmor == 2 then
                    -- Rogues/Druids in Vanilla: Leather (and starting Cloth at low levels)
                    if playerLvl < 20 then
                        if subclassID > 2 or subclassID < 1 then return false end
                    else
                        if subclassID ~= 2 then return false end
                    end
                elseif optimalArmor == 1 then
                    -- Mages/Priests/Warlocks in Vanilla: strictly Cloth only
                    if subclassID ~= 1 then return false end
                end
            else
                if subclassID ~= optimalArmor and subclassID ~= 5 then return false end -- subclassID 5 is Cosmetic
            end
        end
    end

    -- Weapon restriction rules
    if classID == 2 then
        -- Enforce class/spec weapon proficiencies (e.g. Demon Hunters cannot use Daggers [15] or 1H Maces [4])
        if rule.allowedWeapons and subclassID and not rule.allowedWeapons[subclassID] then
            return false
        end

        if itemEquipLoc == "INVTYPE_RANGED" or itemEquipLoc == "INVTYPE_RANGEDRIGHT" or itemEquipLoc == "INVTYPE_THROWN" then
            if not rule.weaps["Ranged"] then return false end
        elseif itemEquipLoc == "INVTYPE_2HWEAPON" then
            if not rule.weaps["2H"] and not rule.weaps["2H_Dual"] then return false end
        elseif itemEquipLoc == "INVTYPE_WEAPON" or itemEquipLoc == "INVTYPE_WEAPONMAINHAND" then
            if not rule.weaps["1H_Dual"] and not rule.weaps["1H_Off"] and not rule.weaps["1H_Shield"] then return false end
        elseif itemEquipLoc == "INVTYPE_WEAPONOFFHAND" then
            if not rule.weaps["1H_Dual"] and not rule.weaps["1H_Off"] then return false end
        else
            return false
        end
    elseif classID == 4 then
        if itemEquipLoc == "INVTYPE_SHIELD" then
            if not rule.weaps["1H_Shield"] then return false end
        elseif itemEquipLoc == "INVTYPE_HOLDABLE" then
            if not rule.weaps["1H_Off"] then return false end
        elseif itemEquipLoc == "INVTYPE_WEAPONOFFHAND" then
            if not rule.weaps["1H_Dual"] and not rule.weaps["1H_Off"] then return false end
        elseif itemEquipLoc == "INVTYPE_RELIC" then
            -- In Classic / Vanilla / Camelot, Relics occupy slot 18:
            -- Druid: Idols (8/11), Paladin: Librams (7/11), Shaman: Totems (9/11), DK: Sigils (10/11)
            if specID == 1484 or specID == 102 or specID == 103 or specID == 104 or specID == 105 then
                if subclassID ~= 8 and subclassID ~= 11 then return false end
            elseif specID == 1486 or specID == 65 or specID == 66 or specID == 70 then
                if subclassID ~= 7 and subclassID ~= 11 then return false end
            elseif specID == 1489 or specID == 262 or specID == 263 or specID == 264 then
                if subclassID ~= 9 and subclassID ~= 11 then return false end
            elseif specID == 250 or specID == 251 or specID == 252 then
                if subclassID ~= 10 and subclassID ~= 11 then return false end
            else
                return false
            end
        end
    end

    local isNonDynamicStatPiece = isClassic or (classID == 2 or itemEquipLoc == "INVTYPE_TRINKET" or itemEquipLoc == "INVTYPE_CLOAK" or itemEquipLoc == "INVTYPE_NECK" or itemEquipLoc == "INVTYPE_FINGER" or itemEquipLoc == "INVTYPE_HOLDABLE" or itemEquipLoc == "INVTYPE_SHIELD" or itemEquipLoc == "INVTYPE_RELIC")

    if isNonDynamicStatPiece then
        if not HasPrimaryStat(itemLink, primaryStatName, specID) then return false end
    end

    -- Role and spec eligibility check for trinkets (prevents tank trinkets on DPS/Healers, healer trinkets on DPS/Tanks)
    if itemEquipLoc == "INVTYPE_TRINKET" then
        if not common.is_trinket_valid_for_spec(itemLink, specID) then
            return false
        end
    end

    local statVal = GetPrimaryStatValue(itemLink, primaryStatName)
    return true, itemLevel, statVal, itemEquipLoc, itemQuality
end

function sfui.highest.IsItemValidForSpec(itemLink, specID, ignorePlayerLevel, ignoreTalents)
    local playerLvlKey = ignorePlayerLevel and "ign" or tostring(UnitLevel("player") or 1)
    local cacheKey = itemLink .. ":" .. tostring(specID) .. ":" .. playerLvlKey .. (ignoreTalents and ":igntal" or "")
    if validationCache[cacheKey] ~= nil then
        local c = validationCache[cacheKey]
        return c[1], c[2], c[3], c[4], c[5]
    end
    local isValid, itemLevel, statVal, itemEquipLoc, itemQuality = IsItemValidForSpec_Internal(itemLink, specID, ignorePlayerLevel, ignoreTalents)
    if validationCacheCount >= VALIDATION_CACHE_MAX then
        _G.wipe(validationCache)
        validationCacheCount = 0
    end
    validationCacheCount = validationCacheCount + 1
    validationCache[cacheKey] = { isValid, itemLevel, statVal, itemEquipLoc, itemQuality }
    return isValid, itemLevel, statVal, itemEquipLoc, itemQuality
end

-- Returns: isUpgrade, isOffSpec
function sfui.highest.EvaluateItemUpgrade(itemLink, overrideIlvl, currentEquippedIlvl)
    if not itemLink then return false, false end
    local activeSpecID = sfui.common.get_current_spec_id()
    if not activeSpecID or activeSpecID == 0 then return false, false end

    local function CheckSpecUpgrade(specID)
        local isValid, baseIlvl = sfui.highest.IsItemValidForSpec(itemLink, specID)
        if not isValid then return false end

        local itemLevel = overrideIlvl or baseIlvl
        local effectiveILvl = common.get_item_level(itemLink)
        if effectiveILvl and not overrideIlvl then itemLevel = effectiveILvl end

        -- Tooltip override for heavily scaled Event/Timewalking items
        if not overrideIlvl and C_TooltipInfo and C_TooltipInfo.GetHyperlink then
            local tooltipData = C_TooltipInfo.GetHyperlink(itemLink)
            if tooltipData and tooltipData.lines then
                for _, line in ipairs(tooltipData.lines) do
                    local text = line.leftText
                    if text and type(text) == "string" then
                        local tVal = tonumber(text:match("Item Level (%d+)"))
                        if tVal and tVal > itemLevel then
                            itemLevel = tVal
                        end
                        if tVal then break end
                    end
                end
            end
        end

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

-- Scan bags and return a table mapping slotId -> {link, ilvl} of best possible items
function sfui.highest.GetBestItems(isPvP)
    local specID = sfui.common.get_current_spec_id()
    if not specID or specID == 0 then return nil end
    local rule = sfui.highest.rules[specID]
    if not rule then return nil end

    -- Dynamic Frost DK Talent Overrides
    if specID == 251 then
        if common.is_talent_known(FROSTBANE_TALENT_ID) then
            rule = { armor = rule.armor, stat = rule.stat, weaps = { ["1H_Dual"] = true, ["2H"] = false }, allowedWeapons = rule.allowedWeapons }
        end
    end

    local isClassicSpec = (specID and specID >= 1482 and specID <= 1491)
        or (sfui.compat and (sfui.compat.has.wow_forever or sfui.compat.is_classic_era or sfui.compat.is_classic))
        or (sfui.version and not sfui.version.retail)

    local specDB = SfuiDB and SfuiDB.gear and SfuiDB.gear[specID]
    local isTank = (sfui.gear and sfui.gear.IsTankSpec and sfui.gear.IsTankSpec(specID, specDB)) or false
    local isHeal = (sfui.gear and sfui.gear.IsHealerSpec and sfui.gear.IsHealerSpec(specID, specDB)) or false

    -- Classic Role Weapon & Stat Override: Warrior/Paladin tanks & Paladin/Shaman/Druid/Priest healers
    if isClassicSpec then
        if isTank and (specID == 1491 or specID == 1486) then
            rule = {
                armor = rule.armor,
                stat = rule.stat,
                weaps = { ["1H_Shield"] = true, ["Ranged"] = (specID == 1491) },
                allowedWeapons = rule.allowedWeapons,
            }
        elseif isHeal then
            if specID == 1486 or specID == 1489 then -- Paladin, Shaman (Healer: 1H + Shield/Offhand or 2H, Intellect)
                rule = {
                    armor = rule.armor,
                    stat = 4, -- Intellect / Spell
                    weaps = { ["1H_Shield"] = true, ["1H_Off"] = true, ["2H"] = true },
                    allowedWeapons = rule.allowedWeapons,
                }
            elseif specID == 1484 then -- Druid (Healer: 1H + Offhand or 2H Mace/Staff, Intellect)
                rule = {
                    armor = rule.armor,
                    stat = 4,
                    weaps = { ["1H_Off"] = true, ["2H"] = true },
                    allowedWeapons = rule.allowedWeapons,
                }
            elseif specID == 1487 then -- Priest (Healer: 1H + Offhand or 2H Staff, Wand, Intellect)
                rule = {
                    armor = rule.armor,
                    stat = 4,
                    weaps = { ["1H_Off"] = true, ["2H"] = true, ["Ranged"] = true },
                    allowedWeapons = rule.allowedWeapons,
                }
            end
        end
    end

    local primaryStatName = common.get_stat_key(rule.stat)
    local optimalArmor = rule.armor

    -- Persistent GC Table Pooling
    sfui.highest.itemDataPool = sfui.highest.itemDataPool or {}
    sfui.highest.pooledBest = sfui.highest.pooledBest or {}
    local itemDataPool = sfui.highest.itemDataPool
    local poolIndex = 0

    local best = sfui.highest.pooledBest
    for i = 1, 19 do
        best[i] = best[i] or {}
        wipe(best[i])
    end

    local pooledTargetSlots = {}
    local evaluateIndex = 0

    local function evaluate(itemLink, isEquipped, slotOverride, bag, slot)
        evaluateIndex = evaluateIndex + 1
        local isValid, baseIlvl, statVal, itemEquipLoc, itemQuality = sfui.highest.IsItemValidForSpec(itemLink, specID)
        if not isValid then return end

        -- Slot lock evaluation (context-aware: PvE / PvP dual tables)
        local isLockedItem = false
        do
            local itemID = common.get_item_id(itemLink)
            local specGear = itemID and SfuiDB and SfuiDB.gear and SfuiDB.gear[specID]
            local lockTable = specGear and (isPvP and specGear.locked_items_pvp or specGear.locked_items_pve)
            -- Legacy fallback: old unified locked_items table
            if not lockTable and specGear then lockTable = specGear.locked_items end
            if lockTable and lockTable[itemID] then
                if isEquipped then
                    return -- skip: prevent equipped locked items from being mathematically duplicated into alternate slots
                else
                    isLockedItem = true
                end
            end
        end

        local itemLevel = baseIlvl

        -- Use true effective item level from the server
        local effectiveILvl = common.get_item_level(itemLink)
        if effectiveILvl and effectiveILvl > 0 then itemLevel = effectiveILvl end
        if not itemLevel or itemLevel == 0 then itemLevel = 1 end

        -- Tooltip override for heavily scaled Event/Timewalking items
        if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
            local tooltipData = C_TooltipInfo.GetHyperlink(itemLink)
            if tooltipData and tooltipData.lines then
                for _, line in ipairs(tooltipData.lines) do
                    local text = line.leftText
                    if text and type(text) == "string" then
                        local tVal = tonumber(text:match("Item Level (%d+)"))
                        if tVal and tVal > itemLevel then
                            itemLevel = tVal
                        end
                        if tVal then break end
                    end
                end
            end
        end

        -- Locked items retain their true ilvl; sorting priority is handled via itm.score

        -- PvP Tooltip parsing for scaled ilvls
        if isPvP then
            local cachedIlvl = pvpIlvlCache[itemLink]
            if cachedIlvl then
                if cachedIlvl > 0 and cachedIlvl > itemLevel then
                    itemLevel = cachedIlvl
                end
            else
                local foundScaling = false
                local tooltipData = C_TooltipInfo.GetHyperlink(itemLink)
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
                                    local maxScaled = (sfui.config and sfui.config.gear and sfui.config.gear.maxScaledILvl) or
                                        1000
                                    if scaledIlvl and scaledIlvl > itemLevel and scaledIlvl < maxScaled then
                                        itemLevel = scaledIlvl
                                        pvpCacheSet(itemLink, scaledIlvl)
                                        foundScaling = true
                                    end
                                end
                            end
                        end
                    end
                end

                if not foundScaling and tooltipData and tooltipData.lines and #tooltipData.lines > 1 then
                    pvpCacheSet(itemLink, -1)
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
        itemData.ilvl           = itemLevel
        itemData.quality        = itemQuality or common.get_item_quality(itemLink) or 1
        itemData.statVal        = statVal
        itemData.is2H           = ((itemEquipLoc == "INVTYPE_2HWEAPON" and not rule.weaps["2H_Dual"]) or ((not isClassicSpec) and (itemEquipLoc == "INVTYPE_RANGED" or itemEquipLoc == "INVTYPE_RANGEDRIGHT")))
        itemData.isEquipped     = isEquipped
        itemData.equippedSlot   = isEquipped and slotOverride or nil
        itemData.physId         = isEquipped and (-slotOverride) or evaluateIndex
        itemData.itemEquipLoc   = itemEquipLoc
        itemData.bag            = bag
        itemData.slot           = slot
        itemData.score          = nil
        itemData.isEmbellished  = HasEmbellishment(itemData)
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
            elseif itemEquipLoc == "INVTYPE_WEAPON" or itemEquipLoc == "INVTYPE_2HWEAPON" or itemEquipLoc == "INVTYPE_WEAPONMAINHAND" or itemEquipLoc == "INVTYPE_WEAPONOFFHAND" or itemEquipLoc == "INVTYPE_SHIELD" or itemEquipLoc == "INVTYPE_HOLDABLE" or itemEquipLoc == "INVTYPE_RANGED" or itemEquipLoc == "INVTYPE_RANGEDRIGHT" or itemEquipLoc == "INVTYPE_THROWN" or itemEquipLoc == "INVTYPE_RELIC" then
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
    for slotID = 1, maxEquippedSlot do
        if slotID ~= 4 then -- skip shirt
            local link = GetInventoryItemLink("player", slotID)
            if link then evaluate(link, true, slotID) end
        end
    end

    -- 2. Scan bags
    sfui.common.for_each_bag_item(function(bag, slot, itemID, link)
        if link then evaluate(link, false, nil, bag, slot) end
    end, true, true, false)

    -- Quad-Tier Engine: Hero Spec -> Pawn Math -> Manual Priority -> Default DB Priority
    local specDB = SfuiDB and SfuiDB.gear and SfuiDB.gear[specID]
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
        -- P1 fallback hierarchy: pawn weights > explicitly saved manual stats > stats.lua default dictionary stats > hardcoded generic "H,M,V,C" fallback failover
        local classicRole = specDB and (specDB.classic_role or (specDB.role == "HEALER" and "HEAL") or (specDB.role == "TANK" and "TANK") or (specDB.is_tank and "TANK") or (specDB.is_healer and "HEAL"))
        local order = (hd and hd.stat_order) or (specDB and specDB.stat_order) or
            (sfui.gear and sfui.gear.GetDefaultStats and sfui.gear.GetDefaultStats(tonumber(specID), classicRole)) or
            (sfui.default_stats and sfui.default_stats[tonumber(specID)]) or
            { "H", "M", "V", "C" }
        local equals = (hd and hd.stat_equals) or (specDB and specDB.stat_equals) or { true, false, false }

        local statKeys = sfui.highest.statKeys
        if not statKeys then
            statKeys = {
                -- Retail
                ["Crit"] = "ITEM_MOD_CRIT_RATING_SHORT",
                ["C"] = "ITEM_MOD_CRIT_RATING_SHORT",
                ["Haste"] = "ITEM_MOD_HASTE_RATING_SHORT",
                ["H"] = "ITEM_MOD_HASTE_RATING_SHORT",
                ["Mastery"] = "ITEM_MOD_MASTERY_RATING_SHORT",
                ["M"] = "ITEM_MOD_MASTERY_RATING_SHORT",
                ["Versatility"] = "ITEM_MOD_VERSATILITY",
                ["V"] = "ITEM_MOD_VERSATILITY",
                -- Classic / General
                ["SP"] = "ITEM_MOD_SPELL_POWER_SHORT",
                ["SpellPower"] = "ITEM_MOD_SPELL_POWER_SHORT",
                ["Heal"] = "ITEM_MOD_SPELL_HEALING_DONE_SHORT",
                ["Healing"] = "ITEM_MOD_SPELL_HEALING_DONE_SHORT",
                ["Hit"] = "ITEM_MOD_HIT_RATING_SHORT",
                ["AP"] = "ITEM_MOD_ATTACK_POWER_SHORT",
                ["AttackPower"] = "ITEM_MOD_ATTACK_POWER_SHORT",
                ["RAP"] = "ITEM_MOD_RANGED_ATTACK_POWER_SHORT",
                ["RangedAP"] = "ITEM_MOD_RANGED_ATTACK_POWER_SHORT",
                ["MP5"] = "ITEM_MOD_MANA_REGENERATION_SHORT",
                ["ManaRegen"] = "ITEM_MOD_MANA_REGENERATION_SHORT",
                ["Str"] = "ITEM_MOD_STRENGTH_SHORT",
                ["Strength"] = "ITEM_MOD_STRENGTH_SHORT",
                ["Agi"] = "ITEM_MOD_AGILITY_SHORT",
                ["Agility"] = "ITEM_MOD_AGILITY_SHORT",
                ["Int"] = "ITEM_MOD_INTELLECT_SHORT",
                ["Intellect"] = "ITEM_MOD_INTELLECT_SHORT",
                ["Spi"] = "ITEM_MOD_SPIRIT_SHORT",
                ["Spirit"] = "ITEM_MOD_SPIRIT_SHORT",
                ["Stam"] = "ITEM_MOD_STAMINA_SHORT",
                ["Stamina"] = "ITEM_MOD_STAMINA_SHORT",
                -- Tank Only
                ["Def"] = "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT",
                ["Defense"] = "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT",
                ["Dodge"] = "ITEM_MOD_DODGE_RATING_SHORT",
                ["Parry"] = "ITEM_MOD_PARRY_RATING_SHORT",
                ["Block"] = "ITEM_MOD_BLOCK_RATING_SHORT",
                ["Arm"] = "ITEM_MOD_ARMOR_SHORT",
                ["Armor"] = "ITEM_MOD_ARMOR_SHORT",
            }
            sfui.highest.statKeys = statKeys
        end

        statWeights = sfui.highest.statWeights or {}
        sfui.highest.statWeights = statWeights
        for k in pairs(statWeights) do statWeights[k] = nil end

        local isClassicSpec = (specID and specID >= 1482 and specID <= 1491)
            or (sfui.compat and (sfui.compat.has.wow_forever or sfui.compat.is_classic_era or sfui.compat.is_classic))
            or (sfui.version and not sfui.version.retail)
        local isForever = (sfui.compat and (sfui.compat.has.wow_forever or sfui.compat.is_wow_forever))
            or (sfui.version and sfui.version.wow_forever)
        if isClassicSpec then
            if classicRole == "HEAL" or (rule.stat == 4 and classicRole ~= "DPS") then
                statWeights["ITEM_MOD_INTELLECT_SHORT"] = 2.0
                statWeights["ITEM_MOD_SPELL_POWER_SHORT"] = 2.5
                statWeights["ITEM_MOD_SPELL_HEALING_DONE_SHORT"] = 2.5
                statWeights["ITEM_MOD_SPIRIT_SHORT"] = 1.0
                statWeights["ITEM_MOD_MANA_REGENERATION_SHORT"] = 2.0
                statWeights["ITEM_MOD_STAMINA_SHORT"] = 1.0
            elseif rule.stat == 1 or (classicRole == "TANK" and specID == 1484) then -- Strength (Warrior, Paladin, Druid Bear)
                statWeights["ITEM_MOD_STRENGTH_SHORT"] = 2.0
                statWeights["ITEM_MOD_ATTACK_POWER_SHORT"] = 1.0
                statWeights["ITEM_MOD_AGILITY_SHORT"] = 1.5
                statWeights["ITEM_MOD_STAMINA_SHORT"] = 1.0
            elseif rule.stat == 2 then -- Agility (Rogue, Hunter, Druid Cat)
                statWeights["ITEM_MOD_AGILITY_SHORT"] = 2.0
                statWeights["ITEM_MOD_ATTACK_POWER_SHORT"] = 1.0
                statWeights["ITEM_MOD_RANGED_ATTACK_POWER_SHORT"] = 1.0
                statWeights["ITEM_MOD_STRENGTH_SHORT"] = 1.0
                statWeights["ITEM_MOD_STAMINA_SHORT"] = 1.0
            elseif rule.stat == 4 then -- Intellect / Caster (Mage, Priest, Warlock, Shaman)
                statWeights["ITEM_MOD_INTELLECT_SHORT"] = 2.0
                statWeights["ITEM_MOD_SPELL_POWER_SHORT"] = 2.5
                -- In WoW Forever / Camelot, bonus healing converts 1/3 to spell damage.
                -- In Classic Era (Vanilla), bonus healing gives 0 spell damage.
                statWeights["ITEM_MOD_SPELL_HEALING_DONE_SHORT"] = isForever and (2.5 / 3) or 0
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
            isTankForWeights = (sfui.gear and sfui.gear.IsTankSpec and sfui.gear.IsTankSpec(specID, specDB))
                or ((specDB and (specDB.classic_role == "TANK" or specDB.is_tank or specDB.armor_ilvl_prio)) and true or false)
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
            if classicRole == "HEAL" or (rule.stat == 4 and classicRole ~= "DPS") then
                -- Healers: 1 Spell Power = 1 Healing (100% 1:1 parity)
                local healW = statWeights["ITEM_MOD_SPELL_HEALING_DONE_SHORT"] or 0
                local spW = statWeights["ITEM_MOD_SPELL_POWER_SHORT"] or 0
                if healW > spW then
                    statWeights["ITEM_MOD_SPELL_POWER_SHORT"] = healW
                end
            elseif rule.stat == 4 and classicRole == "DPS" then
                -- Caster DPS: bonus healing converts at 1/3 on Forever/Camelot, or 0 on Classic Era
                local spW = statWeights["ITEM_MOD_SPELL_POWER_SHORT"] or 2.5
                statWeights["ITEM_MOD_SPELL_HEALING_DONE_SHORT"] = isForever and (spW / 3) or 0
            end
        end
    end

    local isClassicSpec = (sfui.gear and sfui.gear.IsClassicSpec and sfui.gear.IsClassicSpec(specID))
        or (specID and specID >= 1482 and specID <= 1491)
        or (sfui.compat and (sfui.compat.has.wow_forever or sfui.compat.is_classic_era or sfui.compat.is_classic))
        or (sfui.version and not sfui.version.retail)
    local isTank = sfui.gear and sfui.gear.IsTankSpec and sfui.gear.IsTankSpec(specID, specDB)
    local isHeal = sfui.gear and sfui.gear.IsHealerSpec and sfui.gear.IsHealerSpec(specID, specDB)
    if isClassicSpec then
        if not isTank then
            isTank = (specDB and (specDB.classic_role == "TANK" or specDB.is_tank or specDB.armor_ilvl_prio)) and true or false
        end
        if not isHeal then
            local classicRole = (specDB and specDB.classic_role) or (sfui.common and sfui.common.get_spec_role and sfui.common.get_spec_role(specID))
            isHeal = (classicRole == "HEAL") or (specDB and (specDB.is_healer or specDB.role == "HEALER" or specDB.classic_role == "HEAL"))
        end
    else
        isTank = TANK_SPECS[specID] == true
    end
    local armorIlvlPrio = (specDB and specDB.armor_ilvl_prio)
    if armorIlvlPrio == nil then
        armorIlvlPrio = isTank
    end

    -- Precalculate scores to avoid heavy math directly inside table.sort
    for slotID, items in pairs(best) do
        local isArmor = ARMOR_SLOTS[slotID] == true
        local isWeaponSlot = (slotID == 16 or slotID == 17 or (isClassicSpec and slotID == 18))
        local prioritizeIlvl = (isArmor and armorIlvlPrio) or isWeaponSlot

        for _, itm in ipairs(items) do
            if itm.isLockedItem then
                itm.score = 9000000 + (itm.ilvl or 0)
            else
                local baseMultiplier
                if isClassicSpec then
                    baseMultiplier = isPvP and 20 or 10
                else
                    baseMultiplier = isPvP and 100 or (prioritizeIlvl and 1000 or 10)
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
                        or (q == 1 and 50)
                        or 0
                    score = score + qBonus

                    -- Feature 0b: Weapon DPS & Speed Evaluation for Classic
                    if isWeapon then
                        local wDps, wSpeed = common.get_weapon_stats(itm.link)
                        if wDps and wDps > 0 then
                            local isHunter = (specID == 1485)
                            local isPhysical = (rule.stat == 1 or rule.stat == 2)
                            local isCaster = (rule.stat == 4)

                            local dpsWeight = 0
                            if isHeal then
                                dpsWeight = (slotID == 18 and 25) or 0 -- Wand DPS for wand users, 0 weapon melee damage for healers
                            elseif isHunter then
                                if slotID == 18 then
                                    dpsWeight = 35 -- Main damage weapon for Hunter
                                else
                                    dpsWeight = 10 -- Melee stat stick
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
                                    dpsWeight = 5 -- Caster melee weapon
                                end
                            else
                                dpsWeight = 15
                            end

                            score = score + (wDps * dpsWeight)

                            -- Slower 2H weapons hit much harder for Ret Paladin & Arms Warrior (Seal of Command, Mortal Strike)
                            if not isHeal and itm.is2H and wSpeed and wSpeed > 2.0 and (specID == 1486 or specID == 1491) then
                                score = score + (wSpeed * 15)
                            end
                        end
                    end

                    -- Tank & Shield-Healer shield bonus: Strongly value shields (even grey/white starting shields) for tank spec and classic shield-healers (Paladin/Shaman)
                    if (isTank or (isHeal and (specID == 1486 or specID == 1489))) and itm.itemEquipLoc == "INVTYPE_SHIELD" then
                        score = score + 500
                    end

                    -- Subclass preference for starting/leveling armor (Plate 4 > Mail 3 > Leather 2 > Cloth 1)
                    if ARMOR_SLOTS[slotID] and itm.itemEquipLoc ~= "INVTYPE_SHIELD" and itm.itemEquipLoc ~= "INVTYPE_CLOAK" then
                        local _, _, _, _, _, _, subclassID = common.get_item_instant_info(itm.link)
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
                    local _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, setID = GetItemInfo(itm.link)
                    if setID and setID > 0 then
                        score = score + 150 -- +150 score protection for equipped tier sets to dissuade breaking sets
                    end
                end

                -- Feature 2: Socket Valuation & Stat Priority
                local itemStats = common.get_item_stats(itm.link)
                if itemStats then
                    -- Prismatic socket bonus
                    if itemStats["EMPTY_SOCKET_PRISMATIC"] then
                        score = score + (prioritizeIlvl and 500 or 150)
                    end

                    -- Secondary stat weights derived directly from Pawn string parsing, or fallback to relative Tier weights
                    if pweights then
                        for statName, statAmount in pairs(itemStats) do
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
                                    local isForever = (sfui.compat and (sfui.compat.has.wow_forever or sfui.compat.is_wow_forever))
                                        or (sfui.version and sfui.version.wow_forever)
                                    if isForever and simName == "Healing" and not isHeal then
                                        -- On WoW Forever / Camelot, bonus healing converts 1/3 to spell damage
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
                                    score = score + (statAmount * weight)
                                end
                            end

                            -- Tertiary stat modifiers
                            if statName == "ITEM_MOD_CR_LIFESTEAL_SHORT" or statName == "ITEM_MOD_CR_SPEED_SHORT" then
                                score = score + statAmount
                            end
                        end
                    elseif statWeights then
                        for statName, statAmount in pairs(itemStats) do
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
                                elseif not isClassicSpec and (statName == "ITEM_MOD_INTELLECT_SHORT" or statName == "ITEM_MOD_AGILITY_SHORT" or statName == "ITEM_MOD_STRENGTH_SHORT") then
                                    mappedStatName = common.get_stat_key(rule.stat) or statName
                                end

                                if statWeights[mappedStatName] then
                                    score = score + (statAmount * statWeights[mappedStatName])
                                end
                            end

                            -- Tertiary stat modifiers
                            if statName == "ITEM_MOD_CR_LIFESTEAL_SHORT" or statName == "ITEM_MOD_CR_SPEED_SHORT" then
                                score = score + statAmount
                            end
                        end
                    end
                end
                if itm.itemEquipLoc == "INVTYPE_TRINKET" then
                    local mult = common.get_trinket_value_multiplier(itm.link, specID)
                    if mult and mult ~= 1.0 then
                        score = score * mult
                    end
                end
                itm.score = score
            end
        end
    end

    -- Sort individual slots using the new score system
    for slotID, items in pairs(best) do
        table.sort(items, function(a, b) return a.score > b.score end)
        if _G.SFUI_DEBUG_SLOT and slotID == _G.SFUI_DEBUG_SLOT then
            dbgSlotPrint("=== Slot " .. slotID .. " candidates after scoring ===")
            for rank, itm in ipairs(items) do
                local nm = GetItemInfo(itm.link) or itm.link
                dbgSlotPrint(string.format("  #%d %s | ilvl=%.0f | emb=%s | score=%.1f | equipped=%s",
                    rank, tostring(nm), itm.ilvl, tostring(itm.isEmbellished), itm.score, tostring(itm.isEquipped)))
            end
            _G.SFUI_DEBUG_SLOT = nil -- auto-clear after one scan
        end
    end

    local finalPick = {}

    -- Protect locked slots: retain equipped locked items directly in finalPick so
    -- they are never replaced, and clear them from candidate consideration in best[slotID].
    -- Covers trinkets (13,14), rings (11,12), neck (2), weapons (16,17).
    local lockedSlotIDs = isClassicSpec and { 2, 11, 12, 13, 14, 16, 17, 18 } or { 2, 11, 12, 13, 14, 16, 17 }
    for _, slotID in ipairs(lockedSlotIDs) do
        local link = GetInventoryItemLink("player", slotID)
        if link then
            local itemID = common.get_item_id(link)
            local specGear = itemID and SfuiDB and SfuiDB.gear and SfuiDB.gear[specID]
            local lockTable = specGear and (isPvP and specGear.locked_items_pvp or specGear.locked_items_pve)
            -- Legacy fallback
            if not lockTable and specGear then lockTable = specGear.locked_items end
            if lockTable and lockTable[itemID] then
                local _, _, _, itemEquipLoc = common.get_item_instant_info(link)
                local effectiveILvl = common.get_item_level(link)
                local itmObj = {
                    link = link,
                    ilvl = effectiveILvl,
                    statVal = 0,
                    is2H = ((itemEquipLoc == "INVTYPE_2HWEAPON" and not rule.weaps["2H_Dual"]) or ((not isClassicSpec) and (itemEquipLoc == "INVTYPE_RANGED" or itemEquipLoc == "INVTYPE_RANGEDRIGHT"))),
                    isEquipped = true,
                    equippedSlot = slotID,
                    physId = -slotID,
                    itemEquipLoc = itemEquipLoc,
                    score = 9999999,
                    isLockedItem = true,
                    equipReason = (slotID == 13 or slotID == 14) and "Locked Trinket"
                        or (slotID == 11 or slotID == 12) and "Locked Ring"
                        or (slotID == 2) and "Locked Neck"
                        or (slotID == 16 or slotID == 17 or slotID == 18) and "Locked Weapon"
                        or "Locked Item",
                }
                itmObj.isEmbellished = HasEmbellishment(itmObj)
                finalPick[slotID] = itmObj
                best[slotID] = nil
            end
        end
    end

    -- Feature: Dynamic Tier Set Drafting (Prioritizes Highest setID / Latest Tier)
    local force_2set = specDB and specDB.force_2set
    local force_4set = specDB and (specDB.force_4set ~= false) and not specDB.force_2set
    if force_2set or force_4set then
        local targetCount = force_4set and 4 or 2
        local tierSlots = sfui.highest.tierSlots or { 1, 3, 5, 7, 10 } -- Head, Shoulder, Chest, Legs, Hands
        sfui.highest.tierSlots = tierSlots
        local setStats = {}

        for _, s in ipairs(tierSlots) do
            if best[s] then
                for _, itm in ipairs(best[s]) do
                    local _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, setID = GetItemInfo(itm.link)
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

    -- Resolve Weapons (combinatorics based on primary stat)
    if not finalPick[16] and not finalPick[17] then
        local hasFrostbane = (specID == 251) and common.is_talent_known(FROSTBANE_TALENT_ID)
        local best2H = nil
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
                if not itm.is2H and HasRazoriceEnchant(itm) then
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
            -- For Classic physical DPS (Ret Paladin, Arms Warrior) considering 1H + Shield/Offhand vs 2H:
            -- An off-hand shield or frill does not deal weapon damage; evaluate based purely on weapon DPS and stats on the items.
            local ohQ = bestOH.quality or 1
            local ohQBonus = (ohQ == 5 and 2500)
                or (ohQ == 4 and 1200)
                or (ohQ == 3 and 600)
                or (ohQ == 2 and 250)
                or (ohQ == 1 and 50)
                or 0
            local ohBase = (bestOH.ilvl * (isPvP and 20 or 10)) + ohQBonus
            local ohStatScore = math.max(0, (bestOH.score or 0) - ohBase)

            scoreDual = (best1H and best1H.score or 0) + ohStatScore
            -- score2H is best2H.score (1 weapon base + 2H weapon DPS + 2H speed bonus + 2H stats)
            -- Both score2H and scoreDual now have exactly 1 weapon slot base, so weapon DPS and item stats decide naturally!
        else
            if best2H then
                -- A 2H weapon occupies two slots, so its base ilvl component must be doubled to compare
                -- against the sum of a 1H + OH score (which organically adds two item levels together).
                local twoHandIlvlMult = isClassicSpec and 10 or (isPvP and 100 or 1000)
                score2H = score2H + (best2H.ilvl * twoHandIlvlMult)
                if isClassicSpec and bestOH then
                    local q = best2H.quality or 1
                    local qBonus = (q == 5 and 2500)
                        or (q == 4 and 1200)
                        or (q == 3 and 600)
                        or (q == 2 and 250)
                        or (q == 1 and 50)
                        or 0
                    score2H = score2H + qBonus
                end
            end
            scoreDual = (best1H and best1H.score or 0) + (bestOH and bestOH.score or 0)
        end

        local prioMH_OH = (specID == 62 or specID == 63 or specID == 64 or specID == 265 or specID == 266 or specID == 267 or specID == 258)
        local choose2H = false

        if best2H and (not best1H or not bestOH) then
            choose2H = true
        elseif best2H and best1H and bestOH then
            if prioMH_OH then
                -- For Mage, Warlock & Shadow Priest: prioritize MH + OH if stats/score are equal or better
                -- 2H is only chosen if it genuinely beats the combined dual set beyond rounding margin
                if score2H > (scoreDual + 1.0) then
                    choose2H = true
                else
                    choose2H = false
                end
            else
                if score2H > scoreDual then
                    choose2H = true
                else
                    choose2H = false
                end
            end
        end

        -- Classic Tank Override: Classic Warrior (1491) and Paladin (1486) tanks NEVER use 2H weapons!
        if isClassicSpec and isTank and (specID == 1491 or specID == 1486) then
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
                    -- Dual Wielding two weapons
                    if specID == 251 then
                        local w1Razor = HasRazoriceEnchant(best1H)
                        local w2Razor = HasRazoriceEnchant(bestOH)
                        if hasFrostbane then
                            -- Frost DK with Frostbane: ALWAYS put Rune of Razorice in Main Hand
                            if w2Razor and not w1Razor then
                                finalPick[16] = bestOH
                                finalPick[17] = best1H
                            elseif w1Razor and not w2Razor then
                                finalPick[16] = best1H
                                finalPick[17] = bestOH
                            else
                                -- Both or neither have Razorice: put highest ilvl in Main Hand
                                if bestOH.ilvl > best1H.ilvl then
                                    finalPick[16] = bestOH
                                    finalPick[17] = best1H
                                else
                                    finalPick[16] = best1H
                                    finalPick[17] = bestOH
                                end
                            end
                        else
                            -- Standard Frost DK without Frostbane:
                            -- Put Rune of the Fallen Crusader (non-Razorice) in Main Hand,
                            -- and Rune of Razorice in Off Hand.
                            if w1Razor and not w2Razor then
                                finalPick[16] = bestOH
                                finalPick[17] = best1H
                            elseif w2Razor and not w1Razor then
                                finalPick[16] = best1H
                                finalPick[17] = bestOH
                            else
                                if bestOH.ilvl > best1H.ilvl then
                                    finalPick[16] = bestOH
                                    finalPick[17] = best1H
                                else
                                    finalPick[16] = best1H
                                    finalPick[17] = bestOH
                                end
                            end
                        end
                    else
                        -- General Dual Wield: Always put highest scoring weapon in Main Hand
                        if (bestOH.score or bestOH.ilvl) > (best1H.score or best1H.ilvl) then
                            finalPick[16] = bestOH
                            finalPick[17] = best1H
                        else
                            finalPick[16] = best1H
                            finalPick[17] = bestOH
                        end
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
        -- Main hand is locked; resolve offhand if mainhand is not 2H
        if not finalPick[16].is2H and best[17] then
            for _, itm in ipairs(best[17]) do
                if not itm.is2H and (finalPick[16].physId ~= itm.physId) then
                    local itemID = common.get_item_id(itm.link)
                    local pickedID = common.get_item_id(finalPick[16].link)
                    local isUnique = false
                    if itemID and pickedID and itemID == pickedID then
                        local _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, unique = GetItemInfo(itm.link)
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
        -- Offhand is locked; resolve 1H mainhand
        local hasFrostbane = (specID == 251) and common.is_talent_known(FROSTBANE_TALENT_ID)
        if best[16] then
            local pickedItem = nil
            if hasFrostbane then
                for _, itm in ipairs(best[16]) do
                    if not itm.is2H and (finalPick[17].physId ~= itm.physId) and HasRazoriceEnchant(itm) then
                        local itemID = common.get_item_id(itm.link)
                        local pickedID = common.get_item_id(finalPick[17].link)
                        local isUnique = false
                        if itemID and pickedID and itemID == pickedID then
                            local _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, unique = GetItemInfo(itm.link)
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
                        local itemID = common.get_item_id(itm.link)
                        local pickedID = common.get_item_id(finalPick[17].link)
                        local isUnique = false
                        if itemID and pickedID and itemID == pickedID then
                            local _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, unique = GetItemInfo(itm.link)
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

    if _G.SFUI_DEBUG_WEAPONS and best[16] then
        sfui.common.print("|cffffff00[SFUI Debug] Slot 16 evaluated:|r")
        for i, itm in ipairs(best[16]) do
            sfui.common.print("  [" .. i .. "]", itm.link, "Score:", math.floor(itm.score), "is2H:", tostring(itm.is2H))
        end
        if best2H then sfui.common.print("  best2H:", best2H.link) end
        if finalPick[16] then sfui.common.print("  WINNER:", finalPick[16].link) else sfui.common.print("  WINNER: None") end
        _G.SFUI_DEBUG_WEAPONS = false
    end

    -- Feature: Dynamic Embellishment Drafting (force_2emb)
    local force_2emb = specDB and (specDB.force_2emb == true or specDB.force_2embellishments == true)
    if force_2emb then
        local currentEmbCount = 0
        for _, itm in pairs(finalPick) do
            if itm.isEmbellished then
                currentEmbCount = currentEmbCount + 1
            end
        end
        local embNeeded = 2 - currentEmbCount
        if embNeeded > 0 then
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
                    local itemID = common.get_item_id(cand.itm.link)
                    for _, picked in pairs(finalPick) do
                        if picked.physId == cand.itm.physId then
                            conflict = true; break
                        end
                        if itemID and picked.link and common.get_item_id(picked.link) == itemID then
                            local _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, isUnique = GetItemInfo(cand.itm.link)
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
    end

    -- Process all other slots
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
                    local itemID = common.get_item_id(itm.link)

                    -- Hard game limit: maximum 2 active embellishments allowed
                    if itm.isEmbellished and totalEmbCount >= 2 then
                        alreadyPicked = true
                    end

                    if not alreadyPicked then
                        for _, picked in pairs(finalPick) do
                            if picked.physId == itm.physId then
                                alreadyPicked = true; break
                            end
                            if itemID and picked.link and common.get_item_id(picked.link) == itemID then
                                local _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, isUnique = GetItemInfo(itm.link)
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

    return finalPick
end

local isEquippingInProgress = false
local pendingEquipRequest   = nil

function sfui.highest.EquipHighestILvl(isPvP, silent)
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        if not silent then sfprint("Cannot equip gear while in combat.") end
        return
    end

    -- Mutex lock: if an equip sequence is already actively swapping items, queue a follow-up request instead of spawning parallel loops
    if isEquippingInProgress then
        pendingEquipRequest = { isPvP = isPvP, silent = silent }
        return
    end

    local best = sfui.highest.GetBestItems(isPvP)
    if not best then return end

    local equipQueue = {}
    for slotID, item in pairs(best) do
        local isAlreadyEquippedHere = (item.isEquipped and item.equippedSlot == slotID)
        if not isAlreadyEquippedHere then
            local oldLink = _G.GetInventoryItemLink("player", slotID)
            local oldIlvl = oldLink and common.get_item_level(oldLink) or 0
            local oldScore = 0
            if sfui.highest.pooledBest and sfui.highest.pooledBest[slotID] then
                for _, itm in ipairs(sfui.highest.pooledBest[slotID]) do
                    if itm.isEquipped and itm.equippedSlot == slotID then
                        oldScore = itm.score or 0
                        break
                    end
                end
            end
            table.insert(equipQueue, {
                slotID   = slotID,
                item     = item,
                oldLink  = oldLink,
                oldIlvl  = oldIlvl,
                oldScore = oldScore,
            })
        end
    end

    -- Ensure deterministic equip order (Main Hand 16 before Off Hand 17) Titan's Grip constraints
    table.sort(equipQueue, function(a, b) return a.slotID < b.slotID end)

    local totalToEquip = #equipQueue
    if totalToEquip == 0 then
        if not silent then sfprint("Already wearing your best gear.") end
        return
    end

    isEquippingInProgress = true

    local function onEquipFinished()
        isEquippingInProgress = false
        if pendingEquipRequest then
            local req = pendingEquipRequest
            pendingEquipRequest = nil
            sfui.highest.EquipHighestILvl(req.isPvP, req.silent)
        end
    end

    -- Equip sequentially with lock detection to avoid dropped items or cursor collisions.
    local function equipNext(index, retryCount)
        if index > #equipQueue then
            if totalToEquip > 0 then
                if not silent then sfprint("Equipped " .. totalToEquip .. " upgrade(s)!") end
            end
            onEquipFinished()
            return
        end

        if InCombatLockdown() then
            if not silent then sfprint("Equip canceled: cannot change equipment in combat.") end
            onEquipFinished()
            return
        end

        local entry = equipQueue[index]
        local slotID, item = entry.slotID, entry.item
        local oldLink = entry.oldLink
        local oldIlvl = entry.oldIlvl or 0
        local newLink = item.link
        local newIlvl = item.effectiveIlvl or item.ilvl or (newLink and common.get_item_level(newLink)) or 0
        if oldIlvl == 0 and oldLink then
            oldIlvl = common.get_item_level(oldLink)
        end
        if newIlvl == 0 and newLink then
            newIlvl = common.get_item_level(newLink)
        end
        local slotName = common.get_slot_name(slotID)
        retryCount = retryCount or 0

        if item.isUnequip then
            if retryCount == 0 and not silent then
                sfprint(string.format("-> %s (%d) to Empty (2H Weapon)",
                    oldLink or "Item", oldIlvl))
            end
            if _G.ClearCursor then _G.ClearCursor() end
            if _G.PickupInventoryItem then _G.PickupInventoryItem(slotID) end
            _G.C_Timer.After(0.08, function()
                if _G.PutItemInBackpack then _G.PutItemInBackpack() end
                _G.C_Timer.After(0.05, function()
                    if _G.CursorHasItem and _G.CursorHasItem() then
                        if _G.PutItemInBag then
                            for b = 1, 4 do
                                if _G.CursorHasItem and _G.CursorHasItem() then
                                    _G.PutItemInBag(19 + b)
                                end
                            end
                        end
                        if _G.CursorHasItem and _G.CursorHasItem() and _G.ClearCursor then
                            _G.ClearCursor()
                        end
                    end
                    equipNext(index + 1)
                end)
            end)
            return
        end

        -- Print swap details on first attempt of each queued upgrade
        if retryCount == 0 and not silent then
            local reason = ""
            if oldLink and oldLink ~= "" then
                local diff = newIlvl - oldIlvl
                if item.equipReason then
                    if diff > 0 then
                        reason = string.format("%s (+%d ilvl)", item.equipReason, diff)
                    elseif diff < 0 then
                        reason = string.format("%s (%d ilvl)", item.equipReason, diff)
                    else
                        reason = item.equipReason
                    end
                else
                    if diff > 0 then
                        reason = string.format("+%d ilvl", diff)
                    elseif diff < 0 then
                        reason = string.format("%d ilvl, Stat Weights", diff)
                    else
                        reason = "Stat Weights"
                    end
                end
                sfprint(string.format("-> %s (%d) to %s (%d) (%s)",
                    oldLink, oldIlvl, newLink, newIlvl, reason))
            else
                if item.equipReason then
                    reason = string.format("%s (+%d ilvl)", item.equipReason, newIlvl)
                else
                    reason = string.format("+%d ilvl", newIlvl)
                end
                sfprint(string.format("-> Empty to %s (%d) (%s)",
                    newLink, newIlvl, reason))
            end
        end

        if item.bag and item.slot then
            local info = C_Container_GetContainerItemInfo(item.bag, item.slot)
            if info and info.isLocked and retryCount < 10 then
                -- Container slot is locked by a previous item swap in flight: wait 50ms and retry
                _G.C_Timer.After(0.05, function() equipNext(index, retryCount + 1) end)
                return
            end

            -- Ensure container item still matches what we expect
            local currentLink = C_Container_GetContainerItemLink(item.bag, item.slot)
            if currentLink and currentLink == item.link then
                if _G.ClearCursor then _G.ClearCursor() end
                C_Container_PickupContainerItem(item.bag, item.slot)
                if _G.CursorHasItem and _G.CursorHasItem() then
                    if _G.EquipCursorItem then _G.EquipCursorItem(slotID) end
                else
                    EquipItemByName(item.link, slotID)
                end
                boeAttemptedAt[item.link] = _G.GetTime()
                local watchBag, watchSlot, watchLink = item.bag, item.slot, item.link
                _G.C_Timer.After(2, function()
                    local stillThere = C_Container_GetContainerItemLink(watchBag, watchSlot)
                    if stillThere == watchLink then
                        boeAttemptedAt[watchLink] = _G.GetTime() + 3570
                    end
                end)
            else
                -- Bag slot contents shifted: equip by item link directly
                EquipItemByName(item.link, slotID)
            end
        elseif item.isEquipped and item.equippedSlot and item.equippedSlot ~= slotID then
            -- Item is already equipped in another slot (e.g. swapping Main Hand and Off Hand)
            local currentTargetLink = _G.GetInventoryItemLink("player", slotID)
            if currentTargetLink ~= item.link then
                if _G.ClearCursor then _G.ClearCursor() end
                if _G.PickupInventoryItem then
                    _G.PickupInventoryItem(item.equippedSlot)
                    if _G.CursorHasItem and _G.CursorHasItem() then
                        _G.PickupInventoryItem(slotID)
                        if _G.CursorHasItem and _G.CursorHasItem() then
                            _G.PickupInventoryItem(item.equippedSlot)
                        end
                        if _G.ClearCursor then _G.ClearCursor() end
                    else
                        EquipItemByName(item.link, slotID)
                    end
                else
                    EquipItemByName(item.link, slotID)
                end
            end
        else
            EquipItemByName(item.link, slotID)
        end

        _G.C_Timer.After(0.08, function() equipNext(index + 1) end)
    end

    equipNext(1)
end
