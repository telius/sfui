local addonName, addon = ...
sfui.highest = sfui.highest or {}

local _G = _G
local common = sfui.common
local GetItemInfo = sfui.common.get_item_info
local C_TooltipInfo = _G.C_TooltipInfo
local UnitLevel = _G.UnitLevel
local tonumber = _G.tonumber
local tostring = _G.tostring
local type = _G.type
local pairs = _G.pairs
local ipairs = _G.ipairs
local rawget = _G.rawget
local setmetatable = _G.setmetatable
local wipe = _G.wipe

local FROSTBANE_TALENT_ID = 455993

local function isClassicOrVanilla()
    return not sfui.isRetail
end
sfui.highest.isClassicOrVanilla = isClassicOrVanilla

-- ══════════════════════════════════════════════════════════════════════════════
-- Authoritative Spec Equipment Scoring Rules & Engine Initialization
-- ══════════════════════════════════════════════════════════════════════════════
if sfui.highest.rules then
    if isClassicOrVanilla() then
        if sfui.highest.classic_rules then
            for sID, cRule in pairs(sfui.highest.classic_rules) do
                sfui.highest.rules[sID] = cRule
            end
        end
    end

    setmetatable(sfui.highest.rules, {
        __index = function(t, k)
            if isClassicOrVanilla() then
                local b = sfui.talents.SPEC_BRIDGE[k]
                if b and sfui.highest.classic_rules then
                    if b.camelotID and sfui.highest.classic_rules[b.camelotID] then return sfui.highest.classic_rules[b.camelotID] end
                    if b.retailID and sfui.highest.classic_rules[b.retailID] then return sfui.highest.classic_rules[b.retailID] end
                    if b.classID and sfui.highest.classic_rules[b.classID] then return sfui.highest.classic_rules[b.classID] end
                end
            end
            local nk = tonumber(k)
            if nk and rawget(t, nk) then return rawget(t, nk) end
            return nil
        end,
    })
end

--- Resolves the authoritative equipment scoring rule for a spec - Instant O(1)
--- @param specID number|string
--- @return table|nil
function sfui.highest.GetRule(specID)
    if not specID or not sfui.highest.rules then return nil end
    local r = sfui.highest.rules[specID]
    if r then return r end
    if isClassicOrVanilla() then
        local b = sfui.talents.SPEC_BRIDGE[specID]
        if b then
            if b.camelotID and sfui.highest.rules[b.camelotID] then return sfui.highest.rules[b.camelotID] end
            if b.retailID and sfui.highest.rules[b.retailID] then return sfui.highest.rules[b.retailID] end
            if b.classID and sfui.highest.rules[b.classID] then return sfui.highest.rules[b.classID] end
        end
    end
    local num = tonumber(specID)
    if num and num ~= specID then return sfui.highest.rules[num] end
    return nil
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Primary Stat Validation
-- ══════════════════════════════════════════════════════════════════════════════
local function HasPrimaryStat(itemLink, primaryStatName, specID)
    local _, _, _, equipLoc = common.get_item_instant_info(itemLink)
    -- Shields, Relics, and Ammo never require primary stats in Classic
    if equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_RELIC" or equipLoc == "INVTYPE_AMMO" then return true end

    local stats = common.get_item_stats(itemLink)
    -- Fast-path mathematically sound API match
    if stats and stats[primaryStatName] then return true end

    local isClassic = isClassicOrVanilla()

    -- Caster / Healer spell stat allowance (Classic / Camelot only):
    -- If Intellect is the primary stat, items with Spell Power, Healing, or MP5 satisfy the primary stat check
    if isClassic and primaryStatName == "ITEM_MOD_INTELLECT_SHORT" and stats then
        if (stats["ITEM_MOD_SPELL_POWER_SHORT"] or 0) > 0 or
           (stats["ITEM_MOD_SPELL_HEALING_DONE_SHORT"] or 0) > 0 or
           (stats["ITEM_MOD_SPELL_DAMAGE_DONE_SHORT"] or 0) > 0 or
           (stats["ITEM_MOD_MANA_REGENERATION_SHORT"] or 0) > 0 then
            return true
        end
    end

    local classID = isClassic and ((sfui.gear and sfui.gear.GetClassicClassID and sfui.gear.GetClassicClassID(specID)) or (specID and specID >= 1482 and specID <= 1491 and specID)) or nil
    if isClassic and (specID == nil or specID == 0) then
        local curSpecID = sfui.common.get_current_spec_id()
        if curSpecID then
            local curClassID = (sfui.gear and sfui.gear.GetClassicClassID and sfui.gear.GetClassicClassID(curSpecID)) or (curSpecID >= 1482 and curSpecID <= 1491 and curSpecID)
            if curClassID then
                specID = curSpecID
                classID = curClassID
            end
        end
    end

    if isClassic and classID then
        local b = sfui.talents.SPEC_BRIDGE[specID]
        local specDB = SfuiDB and SfuiDB.gear and (SfuiDB.gear[specID] or (b and b.camelotID and SfuiDB.gear[b.camelotID]) or (b and b.classID and SfuiDB.gear[b.classID]))
        local cRole = (specDB and specDB.classic_role and specDB.classic_role:lower())
        local isHeal = (cRole == "heal" or cRole == "resto" or cRole == "holy" or cRole == "disc" or (specDB and specDB.is_healer))
            or (sfui.gear and sfui.gear.IsHealerSpec and sfui.gear.IsHealerSpec(specID, specDB)) or false

        if classID == 1488 or classID == 1491 or classID == 1485 then -- Rogue, Warrior, Hunter
            if stats and (stats["ITEM_MOD_INTELLECT_SHORT"] or 0) > 0 and (stats["ITEM_MOD_STRENGTH_SHORT"] or 0) == 0 and (stats["ITEM_MOD_AGILITY_SHORT"] or 0) == 0 and (stats["ITEM_MOD_ATTACK_POWER_SHORT"] or 0) == 0 and (stats["ITEM_MOD_RANGED_ATTACK_POWER_SHORT"] or 0) == 0 then
                return false
            end
        elseif classID == 1482 or classID == 1487 or classID == 1490 then -- Mage, Priest, Warlock
            if stats and ((stats["ITEM_MOD_STRENGTH_SHORT"] or 0) > 0 or (stats["ITEM_MOD_AGILITY_SHORT"] or 0) > 0) and (stats["ITEM_MOD_INTELLECT_SHORT"] or 0) == 0 and (stats["ITEM_MOD_SPELL_POWER_SHORT"] or 0) == 0 and (stats["ITEM_MOD_SPELL_HEALING_DONE_SHORT"] or 0) == 0 then
                return false
            end
        elseif isHeal and (classID == 1486 or classID == 1489 or classID == 1484) then -- Paladin, Shaman, Druid in heal mode
            -- Pure melee items without any spell/healing/intellect/spirit stats should not be valid for heal mode
            if stats and ((stats["ITEM_MOD_STRENGTH_SHORT"] or 0) > 0 or (stats["ITEM_MOD_AGILITY_SHORT"] or 0) > 0) and (stats["ITEM_MOD_INTELLECT_SHORT"] or 0) == 0 and (stats["ITEM_MOD_SPELL_POWER_SHORT"] or 0) == 0 and (stats["ITEM_MOD_SPELL_HEALING_DONE_SHORT"] or 0) == 0 and (stats["ITEM_MOD_MANA_REGENERATION_SHORT"] or 0) == 0 and (stats["ITEM_MOD_SPIRIT_SHORT"] or 0) == 0 then
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
sfui.highest.HasPrimaryStat = HasPrimaryStat

local function GetPrimaryStatValue(itemLink, primaryStatName)
    local stats = common.get_item_stats(itemLink)
    if not stats then return 0 end
    return stats[primaryStatName] or 0
end
sfui.highest.GetPrimaryStatValue = GetPrimaryStatValue

-- ══════════════════════════════════════════════════════════════════════════════
-- Item Validation Engine
-- ══════════════════════════════════════════════════════════════════════════════
sfui.highest.validationCache = sfui.highest.validationCache or {}
local validationCache = sfui.highest.validationCache
local validationCacheCount = 0
local VALIDATION_CACHE_MAX = 300

-- Returns true, itemLevel, statVal, itemEquipLoc if the item is valid for the spec rules
local function IsItemValidForSpec_Internal(itemLink, specID, ignorePlayerLevel, ignoreTalents)
    local rule = (sfui.highest.GetRule and sfui.highest.GetRule(specID)) or sfui.highest.rules[specID]
    if not rule then return false end

    local isClassic = isClassicOrVanilla()
    local playerClass, pClassID = sfui.talents.get_player_class()
    local playerClassID = isClassic and ((sfui.gear and sfui.gear.GetClassicClassID and sfui.gear.GetClassicClassID(specID)) or (specID and specID >= 1482 and specID <= 1491 and specID)) or pClassID

    local isPaladin = (playerClass == "PALADIN" or playerClassID == 1486 or specID == 1486 or specID == 65 or specID == 66 or specID == 70 or (specID and specID >= 14861 and specID <= 14863))
    local isWarrior = (playerClass == "WARRIOR" or playerClassID == 1491 or specID == 1491 or specID == 71 or specID == 72 or specID == 73 or (specID and specID >= 14911 and specID <= 14913))
    local isShaman  = (playerClass == "SHAMAN" or playerClassID == 1489 or specID == 1489 or specID == 262 or specID == 263 or specID == 264 or (specID and specID >= 14891 and specID <= 14893))
    local isDruid   = (playerClass == "DRUID" or playerClassID == 1484 or specID == 1484 or specID == 102 or specID == 103 or specID == 104 or specID == 105 or (specID and specID >= 14841 and specID <= 14844))
    local isPriest  = (playerClass == "PRIEST" or playerClassID == 1487 or specID == 1487 or specID == 256 or specID == 257 or specID == 258 or (specID and specID >= 14871 and specID <= 14873))
    local isRogue   = (playerClass == "ROGUE" or playerClassID == 1488 or specID == 1488 or specID == 259 or specID == 260 or specID == 261 or (specID and specID >= 14881 and specID <= 14883))
    local isDK      = (playerClass == "DEATHKNIGHT" or playerClassID == 1483 or specID == 1483 or specID == 250 or specID == 251 or specID == 252 or (specID and specID >= 14831 and specID <= 14833))

    -- Dynamic Frost DK Talent Overrides (ignored for general loot eligibility)
    if not ignoreTalents and specID == 251 and not isClassic then
        if common.is_talent_known(FROSTBANE_TALENT_ID) then
            rule = { armor = rule.armor, stat = rule.stat, weaps = { ["1H_Dual"] = true, ["2H"] = false }, allowedWeapons = rule.allowedWeapons }
        end
    end

    -- Retail Retribution Paladin (70): ALWAYS use 2H weapons exclusively
    if not isClassic and specID == 70 then
        rule = { armor = rule.armor, stat = rule.stat, weaps = { ["2H"] = true }, allowedWeapons = rule.allowedWeapons }
    end

    -- Classic Rogue Dual Wield check (requires level 10 + trainer passive ability 674)
    if isClassic and isRogue then
        local hasDualWield = true
        if not ignoreTalents then
            hasDualWield = sfui.common.is_rogue_dual_wield_known and sfui.common.is_rogue_dual_wield_known() or false
        end
        if not hasDualWield then
            rule = {
                armor = rule.armor,
                stat = rule.stat,
                weaps = { ["1H_Main"] = true, ["1H_Dual"] = false, ["Ranged"] = true },
                allowedWeapons = rule.allowedWeapons,
            }
        end
    end

    -- Classic Role Weapon & Stat Override: Warrior/Paladin tanks & Paladin/Shaman/Druid/Priest healers
    local isTank = false
    local isHeal = false
    if isClassic then
        local b = sfui.talents.SPEC_BRIDGE[specID]
        local specDB = SfuiDB and SfuiDB.gear and (SfuiDB.gear[specID] or (b and b.camelotID and SfuiDB.gear[b.camelotID]) or (b and b.classID and SfuiDB.gear[b.classID]))
        local classicRole = (specDB and specDB.classic_role) or (sfui.gear and sfui.gear.GetClassicRole and sfui.gear.GetClassicRole(specID, specDB))
        local cRoleLower = classicRole and classicRole:lower()
        isTank = (specDB and (specDB.is_tank or specDB.armor_ilvl_prio))
            or (cRoleLower == "tank" or cRoleLower == "bear" or cRoleLower == "prot")
            or (sfui.gear and sfui.gear.IsTankSpec and sfui.gear.IsTankSpec(specID, specDB)) or false
        isHeal = (specDB and specDB.is_healer)
            or (cRoleLower == "heal" or cRoleLower == "resto" or cRoleLower == "holy" or cRoleLower == "disc")
            or (sfui.gear and sfui.gear.IsHealerSpec and sfui.gear.IsHealerSpec(specID, specDB)) or false

        if isTank and (isWarrior or isPaladin) then
            rule = {
                armor = rule.armor,
                stat = rule.stat,
                weaps = { ["1H_Shield"] = true, ["Ranged"] = isWarrior },
                allowedWeapons = rule.allowedWeapons,
            }
        elseif isHeal then
            if isPaladin or isShaman then -- Paladin, Shaman (Healer: 1H + Shield/Offhand or 2H, Intellect)
                rule = {
                    armor = rule.armor,
                    stat = 4, -- Intellect / Spell
                    weaps = { ["1H_Shield"] = true, ["1H_Off"] = true, ["2H"] = true },
                    allowedWeapons = rule.allowedWeapons,
                }
            elseif isDruid then -- Druid (Healer: 1H + Offhand or 2H Mace/Staff, Intellect)
                rule = {
                    armor = rule.armor,
                    stat = 4,
                    weaps = { ["1H_Off"] = true, ["2H"] = true },
                    allowedWeapons = rule.allowedWeapons,
                }
            elseif isPriest then -- Priest (Healer: 1H + Offhand or 2H Staff, Wand, Intellect)
                rule = {
                    armor = rule.armor,
                    stat = 4,
                    weaps = { ["1H_Off"] = true, ["2H"] = true, ["Ranged"] = true },
                    allowedWeapons = rule.allowedWeapons,
                }
            end
        else
            -- Classic / Camelot DPS Role:
            if isPaladin then
                rule = {
                    armor = rule.armor,
                    stat = 1, -- Strength
                    weaps = { ["2H"] = true, ["1H_Shield"] = true, ["1H_Off"] = true },
                    allowedWeapons = rule.allowedWeapons,
                }
            elseif isWarrior then
                rule = {
                    armor = rule.armor,
                    stat = 1, -- Strength
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

    local primaryStatName = common.get_stat_key(rule.stat)
    local optimalArmor = rule.armor

    local itemID, itemType, itemSubType, itemEquipLoc, _, itemClassID, subclassID = common.get_item_instant_info(itemLink)
    if not itemEquipLoc or itemEquipLoc == "" then return false end

    -- Check if player can actually use/equip the item (unlearned weapon skills, unmet class, unmet level, etc.)
    if not sfui.highest.CanPlayerUseItem(itemLink, itemID, ignorePlayerLevel) then
        return false
    end

    local itemName, _, itemQuality, baseLevel, itemMinLevel = GetItemInfo(itemLink)
    local itemLevel = common.get_item_level(itemLink)
    if itemLevel == 0 then itemLevel = baseLevel or 1 end

    -- Tooltip override for heavily scaled Event/Timewalking items (cached inside validationCache)
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

    -- Never auto-equip grey (0) or white (1) quality items in Retail — these are cosmetic,
    -- transmog pieces, or vendor junk and should never beat real gear in scoring.
    -- In Vanilla / Classic Forever, grey and white items are valid starting and leveling equipment.
    if not isClassic and itemQuality and itemQuality < 2 then return false end

    -- Check if the player meets the required level for the item
    if not ignorePlayerLevel and itemMinLevel and itemMinLevel > UnitLevel("player") then return false end

    -- Use robust numeric ID checks instead of localized strings. itemClassID 4 = Armor
    if itemClassID == 4 then
        if itemEquipLoc ~= "INVTYPE_CLOAK" and itemEquipLoc ~= "INVTYPE_FINGER" and itemEquipLoc ~= "INVTYPE_TRINKET" and itemEquipLoc ~= "INVTYPE_NECK" and itemEquipLoc ~= "INVTYPE_HOLDABLE" and itemEquipLoc ~= "INVTYPE_SHIELD" and itemEquipLoc ~= "INVTYPE_RELIC" then
            if isClassic then
                local playerLvl = UnitLevel("player") or 1
                if subclassID ~= 5 then
                    if optimalArmor == 4 then
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
                end
            else
                if subclassID ~= optimalArmor and subclassID ~= 5 then return false end -- subclassID 5 is Cosmetic
            end
        end
    end

    -- Weapon restriction rules
    if itemClassID == 2 then
        -- Enforce class/spec weapon proficiencies (e.g. Demon Hunters cannot use Daggers [15] or 1H Maces [4])
        if rule.allowedWeapons and subclassID and not rule.allowedWeapons[subclassID] then
            return false
        end

        if itemEquipLoc == "INVTYPE_RANGED" or itemEquipLoc == "INVTYPE_RANGEDRIGHT" or itemEquipLoc == "INVTYPE_THROWN" then
            if not rule.weaps["Ranged"] then return false end
        elseif itemEquipLoc == "INVTYPE_2HWEAPON" then
            if not rule.weaps["2H"] and not rule.weaps["2H_Dual"] then return false end
        elseif itemEquipLoc == "INVTYPE_WEAPON" or itemEquipLoc == "INVTYPE_WEAPONMAINHAND" then
            if not rule.weaps["1H_Dual"] and not rule.weaps["1H_Off"] and not rule.weaps["1H_Shield"] and not rule.weaps["1H_Main"] then return false end
        elseif itemEquipLoc == "INVTYPE_WEAPONOFFHAND" then
            if not rule.weaps["1H_Dual"] and not rule.weaps["1H_Off"] then return false end
        else
            return false
        end
    elseif itemClassID == 4 then
        if itemEquipLoc == "INVTYPE_SHIELD" then
            if not rule.weaps["1H_Shield"] then return false end
        elseif itemEquipLoc == "INVTYPE_HOLDABLE" then
            if not rule.weaps["1H_Off"] then return false end
        elseif itemEquipLoc == "INVTYPE_WEAPONOFFHAND" then
            if not rule.weaps["1H_Dual"] and not rule.weaps["1H_Off"] then return false end
        elseif itemEquipLoc == "INVTYPE_RELIC" then
            -- In Classic / Vanilla / Camelot, Relics occupy slot 18:
            -- Druid: Idols (8/11/0), Paladin: Librams (7/11/0), Shaman: Totems (9/11/0), DK: Sigils (10/11/0)
            if isDruid then
                if subclassID ~= 8 and subclassID ~= 11 and subclassID ~= 0 then return false end
            elseif isPaladin then
                if subclassID ~= 7 and subclassID ~= 11 and subclassID ~= 0 then return false end
            elseif isShaman then
                if subclassID ~= 9 and subclassID ~= 11 and subclassID ~= 0 then return false end
            elseif isDK then
                if subclassID ~= 10 and subclassID ~= 11 and subclassID ~= 0 then return false end
            else
                return false
            end
        end
    elseif itemClassID == 6 then
        -- Projectile / Ammo (Vanilla / Classic only)
        if not isClassic then return false end
        local usesAmmo = sfui.api.UnitUsesAmmo and sfui.api.UnitUsesAmmo("player")
        if not usesAmmo then return false end
        -- Subclass 2 = Arrow, Subclass 3 = Bullet
        if subclassID ~= 2 and subclassID ~= 3 then return false end
    end

    local isNonDynamicStatPiece = isClassic or (itemClassID == 2 or itemEquipLoc == "INVTYPE_TRINKET" or itemEquipLoc == "INVTYPE_CLOAK" or itemEquipLoc == "INVTYPE_NECK" or itemEquipLoc == "INVTYPE_FINGER" or itemEquipLoc == "INVTYPE_HOLDABLE" or itemEquipLoc == "INVTYPE_SHIELD" or itemEquipLoc == "INVTYPE_RELIC" or itemEquipLoc == "INVTYPE_AMMO")

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
    local isClassic = isClassicOrVanilla()
    local roleKey = ""
    if isClassic then
        local b = sfui.talents.SPEC_BRIDGE[specID]
        local specDB = SfuiDB and SfuiDB.gear and (SfuiDB.gear[specID] or (b and b.camelotID and SfuiDB.gear[b.camelotID]) or (b and b.classID and SfuiDB.gear[b.classID]))
        roleKey = (specDB and (specDB.classic_role or specDB.role)) or ""
    end
    local cacheKey = itemLink .. ":" .. tostring(specID) .. ":" .. playerLvlKey .. ":" .. roleKey .. (ignoreTalents and ":igntal" or "")
    if validationCache[cacheKey] ~= nil then
        local c = validationCache[cacheKey]
        return c[1], c[2], c[3], c[4], c[5]
    end
    local isValid, itemLevel, statVal, itemEquipLoc, itemQuality = IsItemValidForSpec_Internal(itemLink, specID, ignorePlayerLevel, ignoreTalents)
    if validationCacheCount >= VALIDATION_CACHE_MAX then
        wipe(validationCache)
        validationCacheCount = 0
    end
    validationCacheCount = validationCacheCount + 1
    validationCache[cacheKey] = { isValid, itemLevel, statVal, itemEquipLoc, itemQuality }
    return isValid, itemLevel, statVal, itemEquipLoc, itemQuality
end
