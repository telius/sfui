local addonName, addon = ...
sfui = sfui or {}
sfui.items = sfui.items or {}
sfui.common = sfui.common or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/core/items.lua
--  Item Engine, Equipment Slots, Weapon Scanners, Dedicated Tooltip Frame
-- ══════════════════════════════════════════════════════════════════════════════

local C_Item                          = _G.C_Item or {}
local C_Item_GetItemInfo              = C_Item.GetItemInfo or _G.GetItemInfo
local C_Item_GetItemInfoInstant       = C_Item.GetItemInfoInstant or _G.GetItemInfoInstant
local C_Item_GetDetailedItemLevelInfo = C_Item.GetDetailedItemLevelInfo or _G.GetDetailedItemLevelInfo
local C_Item_GetItemStats             = C_Item.GetItemStats or _G.GetItemStats
local C_Item_GetItemQualityColor      = C_Item.GetItemQualityColor or _G.GetItemQualityColor
local C_Item_GetItemQualityByID       = C_Item.GetItemQualityByID
local C_Item_RequestLoadItemDataByID  = C_Item.RequestLoadItemDataByID
local C_Item_GetItemCount             = C_Item.GetItemCount or _G.GetItemCount
local C_Item_GetItemSpecInfo          = C_Item.GetItemSpecInfo

-- Dedicated Addon Tooltip Frame (Zero global GameTooltip taint, zero UIWidgetManager registration)
local sfuiTooltip = CreateFrame("GameTooltip", "SfuiGameTooltip", UIParent, "GameTooltipTemplate")
if not sfuiTooltip.sfuiBG then
    local bg = sfuiTooltip:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.04, 0.06, 0.94)
    sfuiTooltip.sfuiBG = bg
end
sfuiTooltip:SetFrameStrata("TOOLTIP")
sfui.tooltip = sfuiTooltip
sfui.common.tooltip = sfuiTooltip

local INVENTORY_SLOT_NAMES = {
    [1]  = "Head",
    [2]  = "Neck",
    [3]  = "Shoulders",
    [4]  = "Shirt",
    [5]  = "Chest",
    [6]  = "Waist",
    [7]  = "Legs",
    [8]  = "Feet",
    [9]  = "Wrists",
    [10] = "Hands",
    [11] = "Ring 1",
    [12] = "Ring 2",
    [13] = "Trinket 1",
    [14] = "Trinket 2",
    [15] = "Back",
    [16] = "Main Hand",
    [17] = "Off Hand",
    [18] = "Ranged",
    [19] = "Tabard",
}

local SLOT_KEY_NAMES = {
    head = "Head", neck = "Neck", shoulder = "Shoulder", back = "Back",
    chest = "Chest", wrist = "Wrist", hands = "Hands", waist = "Waist",
    legs = "Legs", feet = "Feet", weapon = "Weapon", ranged = "Ranged", ring = "Ring",
    trinket = "Trinket", other = "Other", token = "Other",
}

local STAT_NAME_MAP = {
    [1] = "ITEM_MOD_STRENGTH_SHORT",
    [2] = "ITEM_MOD_AGILITY_SHORT",
    [4] = "ITEM_MOD_INTELLECT_SHORT",
}

function sfui.items.get_slot_name(slot)
    if type(slot) == "number" then
        return INVENTORY_SLOT_NAMES[slot] or ("Slot " .. slot)
    elseif type(slot) == "string" then
        return SLOT_KEY_NAMES[slot:lower()] or slot
    end
    return "Unknown"
end
sfui.common.get_slot_name = sfui.items.get_slot_name

function sfui.items.get_stat_name(statID)
    local key = STAT_NAME_MAP[statID]
    return key and _G[key] or nil
end
sfui.common.get_stat_name = sfui.items.get_stat_name

function sfui.items.get_stat_key(statID)
    return STAT_NAME_MAP[statID]
end
sfui.common.get_stat_key = sfui.items.get_stat_key

function sfui.items.get_slots_for_invtype(equipLoc, canDualWield1H, canDualWield2H)
    if not equipLoc then return 0 end
    if equipLoc == "INVTYPE_HEAD" then return 1, 1
    elseif equipLoc == "INVTYPE_NECK" then return 1, 2
    elseif equipLoc == "INVTYPE_SHOULDER" then return 1, 3
    elseif equipLoc == "INVTYPE_BODY" or equipLoc == "INVTYPE_SHIRT" then return 1, 4
    elseif equipLoc == "INVTYPE_CHEST" or equipLoc == "INVTYPE_ROBE" then return 1, 5
    elseif equipLoc == "INVTYPE_WAIST" then return 1, 6
    elseif equipLoc == "INVTYPE_LEGS" then return 1, 7
    elseif equipLoc == "INVTYPE_FEET" then return 1, 8
    elseif equipLoc == "INVTYPE_WRIST" then return 1, 9
    elseif equipLoc == "INVTYPE_HAND" or equipLoc == "INVTYPE_HANDS" then return 1, 10
    elseif equipLoc == "INVTYPE_FINGER" then return 2, 11, 12
    elseif equipLoc == "INVTYPE_TRINKET" then return 2, 13, 14
    elseif equipLoc == "INVTYPE_CLOAK" then return 1, 15
    elseif equipLoc == "INVTYPE_WEAPON" then
        if canDualWield1H then return 2, 16, 17 else return 1, 16 end
    elseif equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" or equipLoc == "INVTYPE_WEAPONOFFHAND" then
        return 1, 17
    elseif equipLoc == "INVTYPE_2HWEAPON" then
        if canDualWield2H then return 2, 16, 17 else return 1, 16 end
    elseif equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT" or equipLoc == "INVTYPE_THROWN" or equipLoc == "INVTYPE_RELIC" then
        if sfui.isRetail then
            return 1, 16
        end
        return 1, 18
    elseif equipLoc == "INVTYPE_WEAPONMAINHAND" then
        return 1, 16
    elseif equipLoc == "INVTYPE_TABARD" then
        return 1, 19
    end
    return 0
end
sfui.common.get_slots_for_invtype = sfui.items.get_slots_for_invtype

function sfui.items.populate_slots_for_invtype(targetTable, equipLoc, canDualWield1H, canDualWield2H)
    local n, s1, s2 = sfui.items.get_slots_for_invtype(equipLoc, canDualWield1H, canDualWield2H)
    if targetTable then
        targetTable[1] = s1
        targetTable[2] = s2
    end
    return n, s1, s2
end
sfui.common.populate_slots_for_invtype = sfui.items.populate_slots_for_invtype

function sfui.items.get_item_id(item)
    if not item then return nil end
    if type(item) == "number" then return item end
    if type(item) == "string" then
        local id = tonumber(item:match("item:(%d+)"))
        if id then return id end
        if item:find("keystone:", 1, true) then return 180653 end
        local numeric = tonumber(item)
        if numeric then return numeric end
        if C_Item_GetItemInfoInstant then
            local instantID = C_Item_GetItemInfoInstant(item)
            if instantID then return instantID end
        end
    end
    return nil
end
sfui.items.get_item_id_from_link = sfui.items.get_item_id
sfui.common.get_item_id = sfui.items.get_item_id
sfui.common.get_item_id_from_link = sfui.items.get_item_id

function sfui.items.get_item_level(itemLinkOrID)
    if not itemLinkOrID then return 0 end
    local ilvl = C_Item_GetDetailedItemLevelInfo and C_Item_GetDetailedItemLevelInfo(itemLinkOrID)
    if not ilvl or ilvl == 0 then
        if C_Item_GetItemInfo then
            ilvl = select(4, C_Item_GetItemInfo(itemLinkOrID))
        end
    end
    return ilvl or 0
end
sfui.common.get_item_level = sfui.items.get_item_level

function sfui.items.get_item_instant_info(item)
    if not item then return end
    if C_Item_GetItemInfoInstant then
        return C_Item_GetItemInfoInstant(item)
    end
end
sfui.common.get_item_instant_info = sfui.items.get_item_instant_info

function sfui.items.get_item_info(item)
    if not item then return end
    if C_Item_GetItemInfo then
        return C_Item_GetItemInfo(item)
    end
end
sfui.common.get_item_info = sfui.items.get_item_info

function sfui.items.get_item_stats(itemLink)
    if not itemLink then return nil end
    if C_Item_GetItemStats then
        return C_Item_GetItemStats(itemLink)
    end
    return nil
end
sfui.common.get_item_stats = sfui.items.get_item_stats

local weaponStatsCache = {}
local weaponStatsCacheCount = 0
local WEAPON_STATS_CACHE_MAX = 300

function sfui.items.get_weapon_stats(itemLink)
    if sfui.isRetail then
        return 0, 0, 0, 0
    end
    if not itemLink then return 0, 0, 0, 0 end
    if weaponStatsCache[itemLink] then
        local c = weaponStatsCache[itemLink]
        return c[1], c[2], c[3], c[4]
    end

    local dps, speed, minDmg, maxDmg = 0, 0, 0, 0

    if C_Item_GetItemStats then
        local stats = C_Item_GetItemStats(itemLink)
        if stats then
            local apiDps = stats["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] or stats[_G.ITEM_MOD_DAMAGE_PER_SECOND_SHORT]
            if apiDps and apiDps > 0 then
                dps = apiDps
            end
        end
    end

    local foundTooltip = false
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local tData = C_TooltipInfo.GetHyperlink(itemLink)
        if tData and tData.lines then
            foundTooltip = true
            local dpsTmpl = _G.DPS_TEMPLATE
            local dpsPat = dpsTmpl and ("^" .. dpsTmpl:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1"):gsub("%%%%s", "([%%d%%.,]+)") .. "$")
            for _, line in ipairs(tData.lines) do
                local left = line.leftText
                local right = line.rightText
                if left and type(left) == "string" then
                    local cleanLeft = left:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
                    if dps == 0 then
                        local m = dpsPat and cleanLeft:match(dpsPat)
                        if not m then
                            m = cleanLeft:match("%(([%d%.,]+)%s+[Dd][Aa][Mm][Aa][Gg][Ee]%s+[Pp][Ee][Rr]%s+[Ss][Ee][Cc][Oo][Nn][Dd]%)")
                                or cleanLeft:match("([%d%.,]+)%s+[Dd][Aa][Mm][Aa][Gg][Ee]%s+[Pp][Ee][Rr]%s+[Ss][Ee][Cc][Oo][Nn][Dd]")
                                or cleanLeft:match("%(([%d%.,]+)%s+[Dd][Pp][Ss]%)")
                                or cleanLeft:match("([%d%.,]+)%s+[Dd][Pp][Ss]")
                        end
                        if m then
                            local val = tonumber((m:gsub(",", ".")))
                            if val and val > 0 then dps = val end
                        end
                    end
                    if minDmg == 0 then
                        local minVal, maxVal = cleanLeft:match("(%d+)%s*%-?%s*(%d+)")
                        if minVal and maxVal then
                            if cleanLeft:lower():find("damage") or (right and tostring(right):lower():find("speed")) then
                                minDmg = tonumber(minVal) or 0
                                maxDmg = tonumber(maxVal) or 0
                            end
                        end
                    end
                end
                if right and type(right) == "string" and speed == 0 then
                    local cleanRight = right:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
                    local spdVal = cleanRight:match("([%d]+[%.%d]*)")
                    if spdVal and (cleanRight:lower():find("speed") or cleanRight:find("%d+%.%d%d")) then
                        speed = tonumber((spdVal:gsub(",", "."))) or 0
                    end
                end
            end
        end
    end

    if (dps == 0 or speed == 0) and not foundTooltip then
        local scanTip = _G.SfuiHighestScanTooltip
        if not scanTip then
            scanTip = CreateFrame("GameTooltip", "SfuiHighestScanTooltip", nil, "GameTooltipTemplate")
            scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
        end
        scanTip:ClearLines()
        scanTip:SetHyperlink(itemLink)
        local numLines = scanTip:NumLines()
        if numLines and numLines > 0 then
            local dpsTmpl = _G.DPS_TEMPLATE
            local dpsPat = dpsTmpl and ("^" .. dpsTmpl:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1"):gsub("%%%%s", "([%%d%%.,]+)") .. "$")
            for i = 1, numLines do
                local leftObj = _G["SfuiHighestScanTooltipTextLeft" .. i]
                local rightObj = _G["SfuiHighestScanTooltipTextRight" .. i]
                local left = leftObj and leftObj:GetText()
                local right = rightObj and rightObj:GetText()
                if left and type(left) == "string" then
                    local cleanLeft = left:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
                    if dps == 0 then
                        local m = dpsPat and cleanLeft:match(dpsPat)
                        if not m then
                            m = cleanLeft:match("%(([%d%.,]+)%s+[Dd][Aa][Mm][Aa][Gg][Ee]%s+[Pp][Ee][Rr]%s+[Ss][Ee][Cc][Oo][Nn][Dd]%)")
                                or cleanLeft:match("([%d%.,]+)%s+[Dd][Aa][Mm][Aa][Gg][Ee]%s+[Pp][Ee][Rr]%s+[Ss][Ee][Cc][Oo][Nn][Dd]")
                                or cleanLeft:match("%(([%d%.,]+)%s+[Dd][Pp][Ss]%)")
                                or cleanLeft:match("([%d%.,]+)%s+[Dd][Pp][Ss]")
                        end
                        if m then
                            local val = tonumber((m:gsub(",", ".")))
                            if val and val > 0 then dps = val end
                        end
                    end
                    if minDmg == 0 then
                        local minVal, maxVal = cleanLeft:match("(%d+)%s*%-?%s*(%d+)")
                        if minVal and maxVal then
                            if cleanLeft:lower():find("damage") or (right and tostring(right):lower():find("speed")) then
                                minDmg = tonumber(minVal) or 0
                                maxDmg = tonumber(maxVal) or 0
                            end
                        end
                    end
                end
                if right and type(right) == "string" and speed == 0 then
                    local cleanRight = right:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
                    local spdVal = cleanRight:match("([%d]+[%.%d]*)")
                    if spdVal and (cleanRight:lower():find("speed") or cleanRight:find("%d+%.%d%d")) then
                        speed = tonumber((spdVal:gsub(",", "."))) or 0
                    end
                end
            end
        end
    end

    if dps == 0 and minDmg > 0 and maxDmg > 0 and speed > 0 then
        dps = ((minDmg + maxDmg) / 2) / speed
        dps = math.floor(dps * 10 + 0.5) / 10
    end

    if weaponStatsCacheCount >= WEAPON_STATS_CACHE_MAX then
        _G.wipe(weaponStatsCache)
        weaponStatsCacheCount = 0
    end
    weaponStatsCacheCount = weaponStatsCacheCount + 1
    weaponStatsCache[itemLink] = { dps, speed, minDmg, maxDmg }

    return dps, speed, minDmg, maxDmg
end
sfui.common.get_weapon_stats = sfui.items.get_weapon_stats

function sfui.items.get_item_quality(item)
    if not item then return 1 end
    local itemID = type(item) == "number" and item or tonumber(type(item) == "string" and item:match("item:(%d+)"))
    if itemID and C_Item_GetItemQualityByID then
        local q = C_Item_GetItemQualityByID(itemID)
        if q then return q end
    end
    if C_Item_GetItemInfo then
        local _, _, quality = C_Item_GetItemInfo(item)
        if quality then return quality end
    end
    return 1
end
sfui.common.get_item_quality = sfui.items.get_item_quality

function sfui.items.get_item_quality_color(quality)
    quality = tonumber(quality) or 1
    if C_Item_GetItemQualityColor then
        local r, g, b, hex = C_Item_GetItemQualityColor(quality)
        if r then return r, g, b, hex end
    end
    return 1, 1, 1, "ffffffff"
end
sfui.common.get_item_quality_color = sfui.items.get_item_quality_color

function sfui.items.request_item_load(item)
    local itemID = sfui.items.get_item_id(item)
    if itemID and C_Item_RequestLoadItemDataByID then
        C_Item_RequestLoadItemDataByID(itemID)
    end
end
sfui.common.request_item_load = sfui.items.request_item_load

function sfui.items.get_item_count(item, includeBank)
    if not item then return 0 end
    if C_Item_GetItemCount then
        return C_Item_GetItemCount(item, includeBank) or 0
    end
    return 0
end
sfui.common.get_item_count = sfui.items.get_item_count

function sfui.items.get_item_spec_info(itemLinkOrID)
    if not itemLinkOrID then return nil end
    if not C_Item_GetItemSpecInfo then return nil end

    local specList = C_Item_GetItemSpecInfo(itemLinkOrID)
    if (not specList or #specList == 0) and type(itemLinkOrID) ~= "number" then
        local itemID = sfui.items.get_item_id(itemLinkOrID)
        if itemID and itemID > 0 then
            specList = C_Item_GetItemSpecInfo(itemID)
        end
    end
    return (specList and #specList > 0) and specList or nil
end
sfui.common.get_item_spec_info = sfui.items.get_item_spec_info

function sfui.items.get_trinket_role_type(itemLinkOrID)
    if not itemLinkOrID then return "GENERIC" end
    local stats = sfui.items.get_item_stats(itemLinkOrID)
    if stats then
        if stats["ITEM_MOD_EXTRA_ARMOR_SHORT"] or stats["ITEM_MOD_ARMOR_SHORT"]
            or stats["ITEM_MOD_PARRY_RATING_SHORT"] or stats["ITEM_MOD_DODGE_RATING_SHORT"]
            or stats["ITEM_MOD_BLOCK_RATING_SHORT"] then
            return "TANK"
        end
        if stats["ITEM_MOD_MANA_REGENERATION_SHORT"] or stats["ITEM_MOD_SPIRIT_SHORT"] then
            return "HEALER"
        end
    end

    local specList = sfui.items.get_item_spec_info(itemLinkOrID)
    if specList and #specList > 0 then
        local hasTank, hasHealer, hasDamager = false, false, false
        for _, sID in ipairs(specList) do
            local role = (sfui.talents and sfui.talents.get_spec_role and sfui.talents.get_spec_role(sID))
                or (sfui.common and sfui.common.get_spec_role and sfui.common.get_spec_role(sID))
            if role == "TANK" then
                hasTank = true
            elseif role == "HEALER" then
                hasHealer = true
            elseif role == "DAMAGER" then
                hasDamager = true
            end
        end

        if hasTank and not hasHealer and not hasDamager then
            return "TANK"
        elseif hasHealer and not hasTank and not hasDamager then
            return "HEALER"
        elseif hasDamager and not hasTank and not hasHealer then
            return "DAMAGER"
        end
    end

    return "GENERIC"
end
sfui.common.get_trinket_role_type = sfui.items.get_trinket_role_type

function sfui.items.get_trinket_value_multiplier(itemLinkOrID, specID)
    if not itemLinkOrID or not specID then return 1.0 end
    local role = (sfui.talents and sfui.talents.get_spec_role and sfui.talents.get_spec_role(specID))
        or (sfui.common and sfui.common.get_spec_role and sfui.common.get_spec_role(specID))
    if role == "HEALER" then
        local tRole = sfui.items.get_trinket_role_type(itemLinkOrID)
        if tRole == "DAMAGER" or tRole == "GENERIC" then
            return 0.5
        end
    end
    return 1.0
end
sfui.common.get_trinket_value_multiplier = sfui.items.get_trinket_value_multiplier

function sfui.items.is_trinket_valid_for_spec(itemLinkOrID, specID)
    if not itemLinkOrID or not specID or specID <= 0 then return true end

    local targetRole = (sfui.talents and sfui.talents.get_spec_role and sfui.talents.get_spec_role(specID))
        or (sfui.common and sfui.common.get_spec_role and sfui.common.get_spec_role(specID))
    local trinketRole = sfui.items.get_trinket_role_type(itemLinkOrID)
    local specList = sfui.items.get_item_spec_info(itemLinkOrID)

    if targetRole == "DAMAGER" then
        if trinketRole == "TANK" or trinketRole == "HEALER" then
            return false
        end
        if specList then
            for _, sID in ipairs(specList) do
                if sID == specID then return true end
            end
            return false
        end
        return true
    end

    if targetRole == "TANK" then
        if trinketRole == "HEALER" then
            return false
        end
        if trinketRole == "TANK" then
            if specList then
                for _, sID in ipairs(specList) do
                    if sID == specID then return true end
                end
                return false
            end
            return true
        end
        local stats = sfui.items.get_item_stats(itemLinkOrID)
        if stats and (stats["ITEM_MOD_INTELLECT_SHORT"] or 0) > 0
            and not stats["ITEM_MOD_STRENGTH_SHORT"] and not stats["ITEM_MOD_AGILITY_SHORT"] then
            return false
        end
        return true
    end

    if targetRole == "HEALER" then
        if trinketRole == "TANK" then
            return false
        end
        if trinketRole == "HEALER" then
            if specList then
                for _, sID in ipairs(specList) do
                    if sID == specID then return true end
                end
                return false
            end
            return true
        end

        local stats = sfui.items.get_item_stats(itemLinkOrID)
        local hasInt = stats and (stats["ITEM_MOD_INTELLECT_SHORT"] or 0) > 0
        local hasStr = stats and (stats["ITEM_MOD_STRENGTH_SHORT"] or 0) > 0
        local hasAgi = stats and (stats["ITEM_MOD_AGILITY_SHORT"] or 0) > 0
        if hasStr or hasAgi then
            return false
        end

        if hasInt then
            return true
        end

        if specList then
            for _, sID in ipairs(specList) do
                if sID == specID then return true end
                local r = (sfui.talents and sfui.talents.get_spec_role and sfui.talents.get_spec_role(sID))
                    or (sfui.common and sfui.common.get_spec_role and sfui.common.get_spec_role(sID))
                if r == "DAMAGER" then
                    local sRule = sfui.highest and sfui.highest.rules and sfui.highest.rules[sID]
                    if sRule and sRule.stat == 4 then
                        return true
                    end
                end
            end
            return false
        end

        return true
    end

    return true
end
sfui.common.is_trinket_valid_for_spec = sfui.items.is_trinket_valid_for_spec
