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
    [0]  = "Ammo",
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
    ammo = "Ammo", head = "Head", neck = "Neck", shoulder = "Shoulder", back = "Back",
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
    elseif equipLoc == "INVTYPE_AMMO" then
        return 1, 0
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

local issecretvalue = (sfui.safety and sfui.safety.issecretvalue)
    or (sfui.common and sfui.common.issecretvalue)
    or _G.issecretvalue
    or function() return false end

local function normalize_item_arg(item)
    if not item then return nil end
    if issecretvalue and issecretvalue(item) then return nil end
    local t = type(item)
    if t == "table" then
        item = item.link or item.itemLink or item.hyperlink or item.itemID or item.id or item[1]
        if not item or (issecretvalue and issecretvalue(item)) then
            return nil
        end
        t = type(item)
    end
    if t == "number" then
        if item > 0 and item == item then
            return item
        end
        return nil
    elseif t == "string" then
        if item ~= "" then
            return item
        end
        return nil
    end
    return nil
end

function sfui.items.get_item_id(item)
    item = normalize_item_arg(item)
    if not item then return nil end
    if type(item) == "number" then return item end
    if type(item) == "string" then
        local id = tonumber(item:match("item:(%d+)"))
        if id then return id end
        if item:find("keystone:", 1, true) then return 180653 end
        local numeric = tonumber(item)
        if numeric and numeric > 0 then return numeric end
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
    itemLinkOrID = normalize_item_arg(itemLinkOrID)
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
    item = normalize_item_arg(item)
    if not item then return end
    if C_Item_GetItemInfoInstant then
        return C_Item_GetItemInfoInstant(item)
    end
end
sfui.common.get_item_instant_info = sfui.items.get_item_instant_info

function sfui.items.get_item_info(item)
    item = normalize_item_arg(item)
    if not item then return end
    if C_Item_GetItemInfo then
        return C_Item_GetItemInfo(item)
    end
end
sfui.common.get_item_info = sfui.items.get_item_info

function sfui.items.get_item_equip_loc(item)
    item = normalize_item_arg(item)
    if not item then return end
    if C_Item_GetItemInfoInstant then
        local equipLoc = select(4, C_Item_GetItemInfoInstant(item))
        if equipLoc and equipLoc ~= "" then return equipLoc end
    end
    if C_Item_GetItemInfo then
        local equipLoc = select(9, C_Item_GetItemInfo(item))
        if equipLoc and equipLoc ~= "" then return equipLoc end
    end
end
sfui.common.get_item_equip_loc = sfui.items.get_item_equip_loc

function sfui.items.get_inventory_item_link(unit, slotID)
    if not slotID then return nil end
    unit = unit or "player"
    local link = _G.GetInventoryItemLink and _G.GetInventoryItemLink(unit, slotID)
    if link and link ~= "" then return link end

    if unit == "player" then
        if _G.C_TooltipInfo and _G.C_TooltipInfo.GetInventoryItem then
            local data = _G.C_TooltipInfo.GetInventoryItem("player", slotID)
            if data and data.hyperlink and data.hyperlink ~= "" then
                return data.hyperlink
            end
        end

        local itemID = _G.GetInventoryItemID and _G.GetInventoryItemID("player", slotID)
        if itemID and itemID > 0 then
            if _G.C_Item and _G.C_Item.RequestLoadItemDataByID then
                _G.C_Item.RequestLoadItemDataByID(itemID)
            end
            local l = (_G.C_Item and _G.C_Item.GetItemLinkByItemID and _G.C_Item.GetItemLinkByItemID(itemID))
                or (C_Item_GetItemInfo and select(2, C_Item_GetItemInfo(itemID)))
                or ("item:" .. itemID)
            if l and l ~= "" then return l end
        end

        local scanTip = (sfui.common and sfui.common.get_scan_tooltip and sfui.common.get_scan_tooltip())
        if scanTip and scanTip.SetInventoryItem then
            local hasItem = scanTip:SetInventoryItem("player", slotID)
            if hasItem then
                local _, tipLink = scanTip:GetItem()
                if tipLink and tipLink ~= "" then
                    return tipLink
                end
            end
        end

        if _G.ItemLocation and _G.C_Item and _G.C_Item.GetItemLink then
            local loc = _G.ItemLocation:CreateFromEquipmentSlot(slotID)
            if loc and loc:IsValid() then
                local l = _G.C_Item.GetItemLink(loc)
                if l and l ~= "" then return l end
            end
        end
    end

    return nil
end
sfui.common.get_inventory_item_link = sfui.items.get_inventory_item_link

local RESIST_SCHOOLS
local RESIST_SCHOOL_BY_KEY
do
    local dmg = (_G.Enum and _G.Enum.Damageclass) or {}
    RESIST_SCHOOLS = {
        { key = "fire",   label = "fire",   damageClass = dmg.Fire or 2,   statKey = "RESISTANCE2_NAME", color = { 1.0, 0.55, 0.25 }, atlas = "UI-Character-Info-Resistance-Fire",   fallbackIcon = "Interface\\Icons\\Spell_Fire_FireArmor" },
        { key = "nature", label = "nature", damageClass = dmg.Nature or 3, statKey = "RESISTANCE3_NAME", color = { 0.45, 0.9, 0.35 }, atlas = "UI-Character-Info-Resistance-Nature", fallbackIcon = "Interface\\Icons\\Spell_Nature_ResistNature" },
        { key = "frost",  label = "frost",  damageClass = dmg.Frost or 4,  statKey = "RESISTANCE4_NAME", color = { 0.55, 0.8, 1.0 },  atlas = "UI-Character-Info-Resistance-Frost",  fallbackIcon = "Interface\\Icons\\Spell_Frost_FrostWard" },
        { key = "shadow", label = "shadow", damageClass = dmg.Shadow or 5, statKey = "RESISTANCE5_NAME", color = { 0.7, 0.5, 1.0 },   atlas = "UI-Character-Info-Resistance-Shadow", fallbackIcon = "Interface\\Icons\\Spell_Shadow_AntiShadow" },
        { key = "arcane", label = "arcane", damageClass = dmg.Arcane or 6, statKey = "RESISTANCE6_NAME", color = { 0.95, 0.7, 1.0 },  atlas = "UI-Character-Info-Resistance-Arcane", fallbackIcon = "Interface\\Icons\\Spell_Nature_WispSplode" },
    }
    RESIST_SCHOOL_BY_KEY = {}
    for i = 1, #RESIST_SCHOOLS do
        local def = RESIST_SCHOOLS[i]
        RESIST_SCHOOL_BY_KEY[def.key] = def
    end
end
sfui.items.RESIST_SCHOOLS = RESIST_SCHOOLS
sfui.items.RESIST_SCHOOL_BY_KEY = RESIST_SCHOOL_BY_KEY
sfui.common.RESIST_SCHOOLS = RESIST_SCHOOLS
sfui.common.RESIST_SCHOOL_BY_KEY = RESIST_SCHOOL_BY_KEY

local function safe_wipe(t)
    if not t then return nil end
    local w = (sfui.safety and sfui.safety.wipe) or _G.wipe
    if w then
        return w(t)
    end
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end

local itemStatsCache = {}
local itemStatsCacheCount = 0
local ITEM_STATS_CACHE_MAX = 2500
local randomEnchantCache = {}

local resistCache = {}
local resistCacheCount = 0
local RESIST_CACHE_MAX = 4000
local resistBaseScratch = {}
local resistEquipScratch = {}
local resistLineBaseScratch = {}
local resistLineEquipScratch = {}

local shieldStatsCache = {}
local shieldStatsCacheCount = 0
local SHIELD_STATS_CACHE_MAX = 600

local weaponStatsCache = {}
local weaponStatsCacheCount = 0
local WEAPON_STATS_CACHE_MAX = 1000

function sfui.items.clear_item_stats_cache()
    safe_wipe(itemStatsCache)
    safe_wipe(randomEnchantCache)
    itemStatsCacheCount = 0
    safe_wipe(resistCache)
    resistCacheCount = 0
    safe_wipe(shieldStatsCache)
    shieldStatsCacheCount = 0
    safe_wipe(weaponStatsCache)
    weaponStatsCacheCount = 0
end
sfui.common.clear_item_stats_cache = sfui.items.clear_item_stats_cache

local function parse_resist_tooltip_line(clean, baseOut, equipOut, isGreenLine)
    if not clean or clean == "" then return end
    local lower = clean:lower()
    if not lower:find("resist", 1, true) then return end
    if lower:match("^use:") or lower:match("^chance on hit:") or lower:match("^%(%d+%)%s*set:") then
        return
    end

    local hadEnchantPrefix = lower:match("^enchanted:%s*") ~= nil
    if hadEnchantPrefix then
        lower = lower:gsub("^enchanted:%s*", "")
    end
    local isEnchant = (isGreenLine == true) or hadEnchantPrefix

    if lower:match("^equip:") then
        local allEquip = lower:match("all%s+magical%s+resistances?%s+by%s+(%d+)")
            or lower:match("all%s+resistances?%s+by%s+(%d+)")
            or lower:match("resistance%s+to%s+all%s+schools.-by%s+(%d+)")
            or lower:match("%+(%d+)%s+to%s+all%s+resistances?")
            or lower:match("%+(%d+)%s+all%s+resistances?")
        if allEquip then
            local v = tonumber(allEquip)
            if v and v > 0 then
                for i = 1, #RESIST_SCHOOLS do
                    local key = RESIST_SCHOOLS[i].key
                    equipOut[key] = (equipOut[key] or 0) + v
                end
            end
            return
        end

        for i = 1, #RESIST_SCHOOLS do
            local key = RESIST_SCHOOLS[i].key
            local matched = lower:match(key .. "%s+resistance%s+by%s+(%d+)")
                or lower:match("%+(%d+)%s+" .. key .. "%s+resistance")
                or lower:match(key .. "%s+resistance%s*%+(%d+)")
            if matched then
                local v = tonumber(matched)
                if v and v > 0 then
                    equipOut[key] = (equipOut[key] or 0) + v
                end
                return
            end
        end
        return
    end

    local target = isEnchant and equipOut or baseOut
    local allBase = lower:match("^%+(%d+)%s+to%s+all%s+resistances?")
        or lower:match("^%+(%d+)%s+all%s+magical%s+resistances?")
        or lower:match("^%+(%d+)%s+all%s+resistances?")
        or lower:match("^%+(%d+)%s+resistance%s+to%s+all%s+schools")
        or lower:match("^all%s+magical%s+resistances?%s*%+(%d+)")
        or lower:match("^all%s+resistances?%s*%+(%d+)")
        or lower:match("^resist%s+all%s*%+(%d+)")
    if allBase then
        local v = tonumber(allBase)
        if v and v > 0 then
            for i = 1, #RESIST_SCHOOLS do
                local key = RESIST_SCHOOLS[i].key
                target[key] = (target[key] or 0) + v
            end
        end
        return
    end

    for i = 1, #RESIST_SCHOOLS do
        local key = RESIST_SCHOOLS[i].key
        local matched = lower:match("^%+(%d+)%s+" .. key .. "%s+resistance")
            or lower:match("^" .. key .. "%s+resistance%s*%+(%d+)")
        if matched then
            local v = tonumber(matched)
            if v and v > 0 then
                target[key] = (target[key] or 0) + v
            end
            return
        end
    end
end

function sfui.items.parse_tooltip_stat_line(lineText, stats)
    if not lineText or type(lineText) ~= "string" or not stats then return false end
    local clean = lineText:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
    if not clean or clean == "" then return false end

    if (_G.ITEM_RANDOM_ENCHANT and _G.ITEM_RANDOM_ENCHANT ~= "" and clean:find(_G.ITEM_RANDOM_ENCHANT, 1, true))
        or clean:lower():find("random enchantment", 1, true)
    then
        return true
    end

    -- 1. Classic Spell Power / Spell Damage and Healing (e.g. Scepter of the Abandoned)
    local sp = clean:match("[Ii]ncreases damage and healing .-by up to (%d+)")
        or clean:match("[Ii]ncreases damage and healing .-by (%d+)")
        or clean:match("%+(%d+)%s+[Ss]pell%s+[Dd]amage%s+and%s+[Hh]ealing")
        or clean:match("%+(%d+)%s+[Dd]amage%s+and%s+[Hh]ealing%s+[Ss]pells")
        or clean:match("%+(%d+)%s+[Ss]pell%s+[Pp]ower")
    if sp then
        local v = tonumber(sp)
        if v and v > 0 then
            stats["ITEM_MOD_SPELL_POWER_SHORT"] = math.max(stats["ITEM_MOD_SPELL_POWER_SHORT"] or 0, v)
        end
    end

    -- 2. Pure healing done
    if not sp then
        local heal = clean:match("[Ii]ncreases healing .-by up to (%d+)")
            or clean:match("[Ii]ncreases healing .-by (%d+)")
            or clean:match("%+(%d+)%s+[Hh]ealing%s+[Ss]pells")
            or clean:match("%+(%d+)%s+[Hh]ealing$")
        if heal then
            local v = tonumber(heal)
            if v and v > 0 then
                stats["ITEM_MOD_SPELL_HEALING_DONE_SHORT"] = math.max(stats["ITEM_MOD_SPELL_HEALING_DONE_SHORT"] or 0, v)
            end
        end
    end

    -- 3. TBC hybrid style (healing X and damage Y)
    local tbcHeal, tbcDmg = clean:match("[Ii]ncreases healing .-by up to (%d+).-and damage .-by up to (%d+)")
    if tbcHeal and tbcDmg then
        local vH = tonumber(tbcHeal)
        local vD = tonumber(tbcDmg)
        if vH and vH > 0 then
            stats["ITEM_MOD_SPELL_HEALING_DONE_SHORT"] = math.max(stats["ITEM_MOD_SPELL_HEALING_DONE_SHORT"] or 0, vH)
        end
        if vD and vD > 0 then
            stats["ITEM_MOD_SPELL_DAMAGE_DONE_SHORT"] = math.max(stats["ITEM_MOD_SPELL_DAMAGE_DONE_SHORT"] or 0, vD)
        end
    end

    -- 4. MP5 (Restores X mana per 5 sec)
    local mp5 = clean:match("[Rr]estores (%d+) mana")
        or clean:match("%+(%d+)%s+[Mm]ana%s+[Pp]er%s+5")
        or clean:match("%+(%d+)%s+[Mm]ana%s+[Ee]very%s+5")
    if mp5 then
        local v = tonumber(mp5)
        if v and v > 0 then
            stats["ITEM_MOD_MANA_REGENERATION_SHORT"] = math.max(stats["ITEM_MOD_MANA_REGENERATION_SHORT"] or 0, v)
        end
    end

    -- 5. School-specific spell damage (Shadow, Fire, Frost, Holy, Nature, Arcane)
    local schoolDmg = clean:match("[Ii]ncreases damage done by %a+ spells .-by up to (%d+)")
        or clean:match("[Ii]ncreases damage done by %a+ spells .-by (%d+)")
        or clean:match("%+(%d+)%s+%a+%s+[Ss]pell%s+[Dd]amage")
    if schoolDmg then
        local v = tonumber(schoolDmg)
        if v and v > 0 then
            stats["ITEM_MOD_SPELL_DAMAGE_DONE_SHORT"] = math.max(stats["ITEM_MOD_SPELL_DAMAGE_DONE_SHORT"] or 0, v)
        end
    end

    -- 6. Spell Critical Strike
    local spellCritPct = clean:match("[Ii]mproves your chance to get a critical strike with spells by (%d+)%%")
        or clean:match("[Ii]mproves your chance to get a critical strike with spells by up to (%d+)%%")
        or clean:match("%+(%d+)%%%s+[Ss]pell%s+[Cc]rit")
    local spellCritFlat = (not spellCritPct) and clean:match("%+(%d+)%s+[Ss]pell%s+[Cc]rit")
    local spellCritVal = (spellCritPct and (tonumber(spellCritPct) * 10)) or tonumber(spellCritFlat)
    if spellCritVal and spellCritVal > 0 then
        stats["ITEM_MOD_CRIT_SPELL_RATING_SHORT"] = math.max(stats["ITEM_MOD_CRIT_SPELL_RATING_SHORT"] or 0, spellCritVal)
    end

    -- 7. Spell Hit
    local spellHitPct = clean:match("[Ii]mproves your chance to hit with spells by (%d+)%%")
        or clean:match("[Ii]mproves your chance to hit with spells by up to (%d+)%%")
        or clean:match("%+(%d+)%%%s+[Ss]pell%s+[Hh]it")
    local spellHitFlat = (not spellHitPct) and clean:match("%+(%d+)%s+[Ss]pell%s+[Hh]it")
    local spellHitVal = (spellHitPct and (tonumber(spellHitPct) * 10)) or tonumber(spellHitFlat)
    if spellHitVal and spellHitVal > 0 then
        stats["ITEM_MOD_HIT_SPELL_RATING_SHORT"] = math.max(stats["ITEM_MOD_HIT_SPELL_RATING_SHORT"] or 0, spellHitVal)
    end

    -- 8. Armor Penetration
    local arp = clean:match("[Yy]our attacks ignore (%d+) of your opponent's armor")
        or clean:match("[Ii]ncreases armor penetration by (%d+)")
        or clean:match("%+(%d+)%s+[Aa]rmor%s+[Pp]enetration")
    if arp then
        local v = tonumber(arp)
        if v and v > 0 then
            stats["ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT"] = math.max(stats["ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT"] or 0, v)
        end
    end

    -- 9. Haste
    local hastePct = clean:match("[Ii]ncreases attack speed by (%d+)%%")
        or clean:match("[Ii]ncreases your attack speed by (%d+)%%")
    local hasteFlat = (not hastePct) and (
        clean:match("[Ii]ncreases haste by (%d+)")
        or clean:match("%+(%d+)%s+[Hh]aste%s+[Rr]ating")
        or clean:match("%+(%d+)%s+[Hh]aste")
    )
    local hasteVal = (hastePct and (tonumber(hastePct) * 10)) or tonumber(hasteFlat)
    if hasteVal and hasteVal > 0 then
        stats["ITEM_MOD_HASTE_RATING_SHORT"] = math.max(stats["ITEM_MOD_HASTE_RATING_SHORT"] or 0, hasteVal)
    end

    -- 10. Expertise
    local exp = clean:match("[Ii]ncreases your expertise by (%d+)")
        or clean:match("[Ii]ncreases expertise by (%d+)")
        or clean:match("%+(%d+)%s+[Ee]xpertise%s+[Rr]ating")
        or clean:match("%+(%d+)%s+[Ee]xpertise")
    if exp then
        local v = tonumber(exp)
        if v and v > 0 then
            stats["ITEM_MOD_EXPERTISE_RATING_SHORT"] = math.max(stats["ITEM_MOD_EXPERTISE_RATING_SHORT"] or 0, v)
        end
    end

    -- 11. Defense
    local def = clean:match("[Ii]ncreased [Dd]efense %+(%d+)")
        or clean:match("[Ii]ncreases defense rating by (%d+)")
        or clean:match("%+(%d+)%s+[Dd]efense%s+[Rr]ating")
        or clean:match("%+(%d+)%s+[Dd]efense$")
    if def then
        local v = tonumber(def)
        if v and v > 0 then
            stats["ITEM_MOD_DEFENSE_SKILL_RATING_SHORT"] = math.max(stats["ITEM_MOD_DEFENSE_SKILL_RATING_SHORT"] or 0, v)
        end
    end

    -- 12. Shield Block Value
    local bval = clean:match("^(%d+)%s+[Bb]lock")
        or clean:match("[Ii]ncreases the block value of your shield by (%d+)")
        or clean:match("%+(%d+)%s+[Bb]lock%s+[Vv]alue")
    if bval then
        local v = tonumber(bval)
        if v and v > 0 then
            stats["ITEM_MOD_BLOCK_VALUE_SHORT"] = math.max(stats["ITEM_MOD_BLOCK_VALUE_SHORT"] or 0, v)
        end
    end

    -- 12b. Armor (Base Armor & Bonus Armor)
    local arm = clean:match("^(%d+)%s+[Aa]rmor")
        or clean:match("%+(%d+)%s+[Aa]rmor")
        or clean:match("[Ee]quip:%s*Increases armor by (%d+)")
    if arm then
        local v = tonumber(arm)
        if v and v > 0 then
            stats["ITEM_MOD_ARMOR_SHORT"] = math.max(stats["ITEM_MOD_ARMOR_SHORT"] or 0, v)
        end
    end

    -- 13. Block Rating / Chance
    local blockPct = clean:match("[Ii]ncreases your chance to block .-by (%d+)%%")
        or clean:match("%+(%d+)%%%s+[Bb]lock%s+[Rr]ating")
        or clean:match("%+(%d+)%%%s+[Bb]lock$")
    local blockFlat = (not blockPct) and (
        clean:match("[Ii]ncreases your block rating by (%d+)")
        or clean:match("[Ii]ncreases block rating by (%d+)")
        or clean:match("%+(%d+)%s+[Bb]lock%s+[Rr]ating")
        or clean:match("%+(%d+)%s+[Bb]lock$")
    )
    local blockVal = (blockPct and (tonumber(blockPct) * 5)) or tonumber(blockFlat)
    if blockVal and blockVal > 0 then
        stats["ITEM_MOD_BLOCK_RATING_SHORT"] = math.max(stats["ITEM_MOD_BLOCK_RATING_SHORT"] or 0, blockVal)
    end

    -- 14. Physical / General Hit
    if not spellHitVal then
        local hitPct = clean:match("[Ii]mproves your chance to hit by (%d+)%%")
            or clean:match("%+(%d+)%%%s+[Hh]it%s+[Rr]ating")
            or clean:match("%+(%d+)%%%s+[Hh]it$")
        local hitFlat = (not hitPct) and (
            clean:match("%+(%d+)%s+[Hh]it%s+[Rr]ating")
            or clean:match("%+(%d+)%s+[Hh]it$")
        )
        local hitVal = (hitPct and (tonumber(hitPct) * 10)) or tonumber(hitFlat)
        if hitVal and hitVal > 0 then
            stats["ITEM_MOD_HIT_RATING_SHORT"] = math.max(stats["ITEM_MOD_HIT_RATING_SHORT"] or 0, hitVal)
        end
    end

    -- 15. Physical / General Crit
    if not spellCritVal then
        local critPct = clean:match("[Ii]mproves your chance to get a critical strike by (%d+)%%")
            or clean:match("%+(%d+)%%%s+[Cc]rit%s+[Rr]ating")
            or clean:match("%+(%d+)%%%s+[Cc]ritical%s+[Ss]trike")
            or clean:match("%+(%d+)%%%s+[Cc]rit$")
        local critFlat = (not critPct) and (
            clean:match("%+(%d+)%s+[Cc]rit%s+[Rr]ating")
            or clean:match("%+(%d+)%s+[Cc]ritical%s+[Ss]trike")
            or clean:match("%+(%d+)%s+[Cc]rit$")
        )
        local critVal = (critPct and (tonumber(critPct) * 10)) or tonumber(critFlat)
        if critVal and critVal > 0 then
            stats["ITEM_MOD_CRIT_RATING_SHORT"] = math.max(stats["ITEM_MOD_CRIT_RATING_SHORT"] or 0, critVal)
        end
    end

    -- 16. Attack Power / Ranged Attack Power
    local rap = clean:match("%+(%d+)%s+[Rr]anged%s+[Aa]ttack%s+[Pp]ower")
        or clean:match("[Ii]ncreases ranged attack power by (%d+)")
    if rap then
        local v = tonumber(rap)
        if v and v > 0 then
            stats["ITEM_MOD_RANGED_ATTACK_POWER_SHORT"] = math.max(stats["ITEM_MOD_RANGED_ATTACK_POWER_SHORT"] or 0, v)
        end
    else
        local ap = clean:match("%+(%d+)%s+[Aa]ttack%s+[Pp]ower")
            or clean:match("[Ii]ncreases attack power by (%d+)")
        if ap then
            local v = tonumber(ap)
            if v and v > 0 then
                stats["ITEM_MOD_ATTACK_POWER_SHORT"] = math.max(stats["ITEM_MOD_ATTACK_POWER_SHORT"] or 0, v)
            end
        end
    end

    -- 17. Dodge Rating / Chance
    local dodgePct = clean:match("[Ii]ncreases your chance to dodge .-by (%d+)%%")
        or clean:match("%+(%d+)%%%s+[Dd]odge%s+[Rr]ating")
        or clean:match("%+(%d+)%%%s+[Dd]odge$")
    local dodgeFlat = (not dodgePct) and (
        clean:match("[Ii]ncreases your dodge rating by (%d+)")
        or clean:match("[Ii]ncreases dodge rating by (%d+)")
        or clean:match("%+(%d+)%s+[Dd]odge%s+[Rr]ating")
        or clean:match("%+(%d+)%s+[Dd]odge$")
    )
    local dodgeVal = (dodgePct and (tonumber(dodgePct) * 10)) or tonumber(dodgeFlat)
    if dodgeVal and dodgeVal > 0 then
        stats["ITEM_MOD_DODGE_RATING_SHORT"] = math.max(stats["ITEM_MOD_DODGE_RATING_SHORT"] or 0, dodgeVal)
    end

    -- 18. Parry Rating / Chance
    local parryPct = clean:match("[Ii]ncreases your chance to parry .-by (%d+)%%")
        or clean:match("%+(%d+)%%%s+[Pp]arry%s+[Rr]ating")
        or clean:match("%+(%d+)%%%s+[Pp]arry$")
    local parryFlat = (not parryPct) and (
        clean:match("[Ii]ncreases your parry rating by (%d+)")
        or clean:match("[Ii]ncreases parry rating by (%d+)")
        or clean:match("%+(%d+)%s+[Pp]arry%s+[Rr]ating")
        or clean:match("%+(%d+)%s+[Pp]arry$")
    )
    local parryVal = (parryPct and (tonumber(parryPct) * 10)) or tonumber(parryFlat)
    if parryVal and parryVal > 0 then
        stats["ITEM_MOD_PARRY_RATING_SHORT"] = math.max(stats["ITEM_MOD_PARRY_RATING_SHORT"] or 0, parryVal)
    end

    -- 19. Elemental & All Resistances (passive lines only)
    if clean:lower():find("resist", 1, true) then
        safe_wipe(resistLineBaseScratch)
        safe_wipe(resistLineEquipScratch)
        parse_resist_tooltip_line(clean, resistLineBaseScratch, resistLineEquipScratch)
        for i = 1, #RESIST_SCHOOLS do
            local def = RESIST_SCHOOLS[i]
            local baseVal = resistLineBaseScratch[def.key]
            if baseVal and baseVal > 0 then
                stats[def.statKey] = math.max(stats[def.statKey] or 0, baseVal)
            end
            local equipVal = resistLineEquipScratch[def.key]
            if equipVal and equipVal > 0 then
                stats[def.statKey] = (stats[def.statKey] or 0) + equipVal
            end
        end
    end

    return false
end
sfui.common.parse_tooltip_stat_line = sfui.items.parse_tooltip_stat_line

function sfui.items.get_item_stats(itemLink)
    if not itemLink then return nil end
    if itemStatsCache[itemLink] then
        return itemStatsCache[itemLink]
    end

    local raw = C_Item_GetItemStats and C_Item_GetItemStats(itemLink)
    local stats = {}
    if raw then
        for k, v in pairs(raw) do stats[k] = v end
    end

    if sfui.isRetail then
        itemStatsCache[itemLink] = raw or {}
        randomEnchantCache[itemLink] = false
        return raw or {}
    end

    local isClassic = sfui.isClassic or sfui.isCamelot
        or (sfui.compat and (sfui.compat.has.camelot or sfui.compat.is_classic_era or sfui.compat.is_classic))
        or (sfui.version and not sfui.version.retail)

    local isRandomEnchant = false
    if isClassic then
        local foundTooltip = false
        local C_TooltipInfo = _G.C_TooltipInfo
        if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
            local tData = C_TooltipInfo.GetHyperlink(itemLink)
            if tData and tData.lines then
                foundTooltip = true
                for _, line in ipairs(tData.lines) do
                    local left = line.leftText
                    if left and type(left) == "string" then
                        if sfui.items.parse_tooltip_stat_line(left, stats) then
                            isRandomEnchant = true
                        end
                    end
                end
            end
        end

        if not foundTooltip then
            local tip, tipName = nil, "SfuiGameTooltip"
            if sfui.common and sfui.common.get_scan_tooltip then
                tip, tipName = sfui.common.get_scan_tooltip()
            end
            tip = tip or sfuiTooltip
            if tip then
                tip:ClearLines()
                tip:SetHyperlink(itemLink)
                local numLines = tip:NumLines() or 0
                for i = 1, numLines do
                    local fsL = _G[tipName .. "TextLeft" .. i]
                    if fsL then
                        local txt = fsL:GetText()
                        if txt then
                            if sfui.items.parse_tooltip_stat_line(txt, stats) then
                                isRandomEnchant = true
                            end
                        end
                    end
                end
            end
        end
    end

    if itemStatsCacheCount >= ITEM_STATS_CACHE_MAX then
        _G.wipe(itemStatsCache)
        _G.wipe(randomEnchantCache)
        itemStatsCacheCount = 0
    end
    itemStatsCacheCount = itemStatsCacheCount + 1
    itemStatsCache[itemLink] = stats
    randomEnchantCache[itemLink] = isRandomEnchant

    return stats
end
sfui.common.get_item_stats = sfui.items.get_item_stats

function sfui.items.is_random_enchant_item(itemLink)
    local link = normalize_item_arg(itemLink)
    if not link then return false end
    if randomEnchantCache[link] == nil then
        sfui.items.get_item_stats(link)
    end
    return randomEnchantCache[link] == true
end
sfui.common.is_random_enchant_item = sfui.items.is_random_enchant_item

local function parse_tooltip_resist_texts(link, baseOut, equipOut)
    local foundTooltip = false
    local C_TooltipInfo = _G.C_TooltipInfo
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local tData = C_TooltipInfo.GetHyperlink(link)
        if tData and tData.lines then
            foundTooltip = true
            for _, line in ipairs(tData.lines) do
                local left = line.leftText
                if left and not issecretvalue(left) and type(left) == "string" then
                    local clean = left:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
                    if clean and clean ~= "" and clean:lower():find("resist", 1, true) then
                        local clr = line.leftColor
                        local isGreen = clr and clr.r and clr.g and clr.b
                            and (clr.r < 0.25 and clr.g > 0.85 and clr.b < 0.25) or false
                        parse_resist_tooltip_line(clean, baseOut, equipOut, isGreen)
                    end
                end
            end
        end
    end

    if not foundTooltip then
        local tip, tipName = nil, "SfuiGameTooltip"
        if sfui.common and sfui.common.get_scan_tooltip then
            tip, tipName = sfui.common.get_scan_tooltip()
        end
        tip = tip or sfuiTooltip
        if tip then
            tip:ClearLines()
            tip:SetHyperlink(link)
            local numLines = tip:NumLines() or 0
            for i = 1, numLines do
                local fsL = _G[tipName .. "TextLeft" .. i]
                if fsL then
                    local txt = fsL:GetText()
                    if txt and not issecretvalue(txt) and type(txt) == "string" then
                        local clean = txt:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
                        if clean and clean ~= "" and clean:lower():find("resist", 1, true) then
                            local r, g, b
                            if fsL.GetTextColor then
                                r, g, b = fsL:GetTextColor()
                            end
                            local isGreen = r and g and b and (r < 0.25 and g > 0.85 and b < 0.25) or false
                            parse_resist_tooltip_line(clean, baseOut, equipOut, isGreen)
                        end
                    end
                end
            end
        end
    end
end

local get_item_id = sfui.items.get_item_id

local function get_resist_cache_key(id, safeLink, link)
    if safeLink then
        local ench, g1, g2, g3, g4, suf = safeLink:match(
            "item:%d+:([^:|]*):?([^:|]*):?([^:|]*):?([^:|]*):?([^:|]*):?([^:|]*)"
        )
        local hasMod = (ench and ench ~= "" and ench ~= "0")
            or (g1 and g1 ~= "" and g1 ~= "0")
            or (g2 and g2 ~= "" and g2 ~= "0")
            or (g3 and g3 ~= "" and g3 ~= "0")
            or (g4 and g4 ~= "" and g4 ~= "0")
            or (suf and suf ~= "" and suf ~= "0")
        if hasMod then
            return tostring(id or "") .. ":" .. (ench or "") .. ":" .. (g1 or "") .. ":"
                .. (g2 or "") .. ":" .. (g3 or "") .. ":" .. (g4 or "") .. ":" .. (suf or "")
        end
    end
    return id or link
end

function sfui.items.get_item_resistances(itemID, itemLink)
    local id = nil
    if itemID and not issecretvalue(itemID) then
        if type(itemID) == "number" and itemID > 0 then
            id = itemID
        elseif type(itemID) == "string" and itemID ~= "" then
            if not itemLink then itemLink = itemID end
            id = get_item_id(itemID)
        end
    end
    local safeLink = (type(itemLink) == "string" and not issecretvalue(itemLink) and itemLink ~= "") and itemLink or nil
    local link = safeLink or (id and ("item:" .. tostring(id))) or nil
    if not id and link then
        id = get_item_id(link)
    end
    if not link then return nil end

    local cacheKey = get_resist_cache_key(id, safeLink, link)
    local cached = resistCache[cacheKey]
    if cached ~= nil then
        return cached or nil
    end

    local raw = C_Item_GetItemStats and C_Item_GetItemStats(link)
    if issecretvalue(raw) or type(raw) ~= "table" then
        raw = nil
    end
    safe_wipe(resistBaseScratch)
    safe_wipe(resistEquipScratch)

    local isClassic = sfui.isClassic or sfui.isCamelot
        or (sfui.compat and (sfui.compat.has.camelot or sfui.compat.is_classic_era or sfui.compat.is_classic))
        or (sfui.version and not sfui.version.retail)
        or (sfui.isRetail ~= true)

    if isClassic then
        parse_tooltip_resist_texts(link, resistBaseScratch, resistEquipScratch)
    end

    local result = nil
    for i = 1, #RESIST_SCHOOLS do
        local def = RESIST_SCHOOLS[i]
        local rawVal = raw and raw[def.statKey]
        if type(rawVal) ~= "number" or issecretvalue(rawVal) or rawVal < 0 then
            rawVal = 0
        end
        local baseVal = math.max(rawVal, resistBaseScratch[def.key] or 0)
        local totalVal = baseVal + (resistEquipScratch[def.key] or 0)
        if totalVal > 0 then
            if not result then result = {} end
            result[def.key] = totalVal
        end
    end

    if resistCacheCount >= RESIST_CACHE_MAX then
        safe_wipe(resistCache)
        resistCacheCount = 0
    end
    resistCacheCount = resistCacheCount + 1
    resistCache[cacheKey] = result or false

    return result
end
sfui.common.get_item_resistances = sfui.items.get_item_resistances

function sfui.items.get_weapon_stats(itemLink)
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
                            local val
                            if m:find(",") and m:find("%.") then
                                if m:find(",") < m:find("%.") then
                                    val = tonumber((m:gsub(",", ""))) or 0
                                else
                                    val = tonumber((m:gsub("%.", ""):gsub(",", "."))) or 0
                                end
                            elseif m:find(",") then
                                val = tonumber((m:gsub(",", "."))) or 0
                            else
                                val = tonumber(m) or 0
                            end
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
        local scanTip, tipName = nil, "SfuiScanTooltip"
        if sfui.common and sfui.common.get_scan_tooltip then
            scanTip, tipName = sfui.common.get_scan_tooltip()
        end
        if scanTip then
            scanTip:SetHyperlink(itemLink)
            local numLines = scanTip:NumLines()
            if numLines and numLines > 0 then
                local dpsTmpl = _G.DPS_TEMPLATE
                local dpsPat = dpsTmpl and ("^" .. dpsTmpl:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1"):gsub("%%%%s", "([%%d%%.,]+)") .. "$")
                for i = 1, numLines do
                    local leftObj = _G[tipName .. "TextLeft" .. i]
                    local rightObj = _G[tipName .. "TextRight" .. i]
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

function sfui.items.get_shield_stats(itemLink)
    if not itemLink then return 0, 0 end
    if shieldStatsCache[itemLink] then
        local c = shieldStatsCache[itemLink]
        return c[1], c[2]
    end

    local armor, block = 0, 0

    local foundTooltip = false
    local C_TooltipInfo = _G.C_TooltipInfo
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local tData = C_TooltipInfo.GetHyperlink(itemLink)
        if tData and tData.lines then
            foundTooltip = true
            for _, line in ipairs(tData.lines) do
                local left = line.leftText
                if left and type(left) == "string" then
                    local clean = left:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
                    if clean and clean ~= "" then
                        if armor == 0 then
                            local a = clean:match("^(%d+)%s+[Aa]rmor")
                                or clean:match("%+(%d+)%s+[Aa]rmor")
                            if a then armor = tonumber(a) or 0 end
                        end
                        if block == 0 then
                            local b = clean:match("^(%d+)%s+[Bb]lock")
                                or clean:match("[Ii]ncreases the block value of your shield by (%d+)")
                                or clean:match("%+(%d+)%s+[Bb]lock%s+[Vv]alue")
                            if b then block = tonumber(b) or 0 end
                        end
                    end
                end
            end
        end
    end

    if not foundTooltip then
        local tip, tipName = nil, "SfuiGameTooltip"
        if sfui.common and sfui.common.get_scan_tooltip then
            tip, tipName = sfui.common.get_scan_tooltip()
        end
        tip = tip or sfuiTooltip
        if tip then
            tip:ClearLines()
            tip:SetHyperlink(itemLink)
            local numLines = tip:NumLines() or 0
            for i = 1, numLines do
                local fsL = _G[tipName .. "TextLeft" .. i]
                if fsL then
                    local txt = fsL:GetText()
                    if txt and type(txt) == "string" then
                        local clean = txt:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
                        if clean and clean ~= "" then
                            if armor == 0 then
                                local a = clean:match("^(%d+)%s+[Aa]rmor")
                                    or clean:match("%+(%d+)%s+[Aa]rmor")
                                if a then armor = tonumber(a) or 0 end
                            end
                            if block == 0 then
                                local b = clean:match("^(%d+)%s+[Bb]lock")
                                    or clean:match("[Ii]ncreases the block value of your shield by (%d+)")
                                    or clean:match("%+(%d+)%s+[Bb]lock%s+[Vv]alue")
                                if b then block = tonumber(b) or 0 end
                            end
                        end
                    end
                end
            end
        end
    end

    if shieldStatsCacheCount >= SHIELD_STATS_CACHE_MAX then
        _G.wipe(shieldStatsCache)
        shieldStatsCacheCount = 0
    end
    shieldStatsCacheCount = shieldStatsCacheCount + 1
    shieldStatsCache[itemLink] = { armor, block }

    return armor, block
end
sfui.common.get_shield_stats = sfui.items.get_shield_stats

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
            local role = sfui.talents.get_spec_role(sID)
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
    local role = sfui.talents.get_spec_role(specID)
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

    local targetRole = sfui.talents.get_spec_role(specID)
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
                local r = sfui.talents.get_spec_role(sID)
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

-- ─────────────────────────────────────────────────────────────────────────────
--  Food & Drink / Well Fed Scanner
-- ─────────────────────────────────────────────────────────────────────────────

local foodDrinkInfoCache = {}

--- Clears the cached food and drink info table (e.g. on inventory / scan refreshes)
function sfui.items.clear_food_drink_cache()
    _G.wipe(foodDrinkInfoCache)
end
sfui.common.clear_food_drink_cache = sfui.items.clear_food_drink_cache

local function GetSafeSpellName(spellID)
    if not spellID then return nil end
    if sfui.common and sfui.common.get_spell_name then
        local name = sfui.common.get_spell_name(spellID)
        if name and name ~= "" then return name end
    end
    if _G.C_Spell and _G.C_Spell.GetSpellName then
        local name = _G.C_Spell.GetSpellName(spellID)
        if name and name ~= "" then return name end
    end
    if _G.GetSpellInfo then
        local name = _G.GetSpellInfo(spellID)
        if name and name ~= "" then return name end
    end
    return nil
end

local function ExtractTooltipLineTexts(data, out)
    if not (data and data.lines) then return 0 end
    local count = #out
    for i = 1, #data.lines do
        local line = data.lines[i]
        if line then
            if line.leftText and line.leftText ~= "" then
                count = count + 1
                out[count] = line.leftText
            end
            if line.rightText and line.rightText ~= "" then
                count = count + 1
                out[count] = line.rightText
            end
            if line.args then
                for _, arg in ipairs(line.args) do
                    if arg.stringVal and arg.stringVal ~= "" then
                        count = count + 1
                        out[count] = arg.stringVal
                    end
                end
            end
        end
    end
    return count
end

local function ExtractTooltipFrameTexts(tip, bag, slot, itemID, itemLink, out)
    if not (tip and (tip.SetBagItem or tip.SetHyperlink)) then return #out end
    local tipName = tip:GetName()
    if tip.SetOwner and _G.UIParent then tip:SetOwner(_G.UIParent, "ANCHOR_NONE") end

    local link = itemLink or (itemID and ("item:" .. itemID))
    if link and tip.SetHyperlink then
        tip:ClearLines()
        pcall(tip.SetHyperlink, tip, link)
        local numLines = (tip.NumLines and tip:NumLines()) or 0
        for i = 1, numLines do
            local fsL = tipName and _G[tipName .. "TextLeft" .. i]
            if fsL then
                local txt = fsL:GetText()
                if txt and txt ~= "" then
                    out[#out + 1] = txt
                end
            end
            local fsR = tipName and _G[tipName .. "TextRight" .. i]
            if fsR then
                local txt = fsR:GetText()
                if txt and txt ~= "" then
                    out[#out + 1] = txt
                end
            end
        end
    end

    if bag and slot and tip.SetBagItem then
        tip:ClearLines()
        pcall(tip.SetBagItem, tip, bag, slot)
        local numLines = (tip.NumLines and tip:NumLines()) or 0
        for i = 1, numLines do
            local fsL = tipName and _G[tipName .. "TextLeft" .. i]
            if fsL then
                local txt = fsL:GetText()
                if txt and txt ~= "" then
                    out[#out + 1] = txt
                end
            end
            local fsR = tipName and _G[tipName .. "TextRight" .. i]
            if fsR then
                local txt = fsR:GetText()
                if txt and txt ~= "" then
                    out[#out + 1] = txt
                end
            end
        end
    end

    return #out
end

local scratchTooltipTexts = {}

--- Inspects an item to determine whether it is consumable food (restores health),
--- consumable drink (restores mana), and whether it grants the "Well Fed" buff.
--- Uses C_Item.GetItemSpell, C_TooltipInfo, and dedicated sfuiTooltip (zero GameTooltip taint).
--- @param bag number|nil
--- @param slot number|nil
--- @param itemID number|nil
--- @param itemLink string|nil
--- @return boolean isFood, boolean isDrink, boolean hasWellFed
function sfui.items.get_food_drink_info(bag, slot, itemID, itemLink)
    if not itemID and not itemLink then return false, false, false end
    itemID = itemID or sfui.items.get_item_id(itemLink)
    if not itemID then return false, false, false end

    local cached = foodDrinkInfoCache[itemID]
    if cached ~= nil then
        return cached.isFood, cached.isDrink, cached.hasWellFed
    end

    local name, _, _, _, _, _, _, _, _, _, _, classID, subClassID = sfui.items.get_item_info(itemLink or itemID)
    if not name then
        if C_Item_RequestLoadItemDataByID and itemID then
            C_Item_RequestLoadItemDataByID(itemID)
        end
        return false, false, false -- item info not yet loaded; do not cache false
    end

    local isConsumableClass = (classID == 0) or (_G.Enum and _G.Enum.ItemClass and classID == _G.Enum.ItemClass.Consumable)
    if classID ~= nil and not isConsumableClass then
        foodDrinkInfoCache[itemID] = { isFood = false, isDrink = false, hasWellFed = false }
        return false, false, false
    end

    _G.wipe(scratchTooltipTexts)

    -- 1. Direct spell inspection via C_Item.GetItemSpell / GetItemSpell
    local itemSpellName, itemSpellID = nil, nil
    if C_Item and C_Item.GetItemSpell then
        itemSpellName, itemSpellID = C_Item.GetItemSpell(itemLink or itemID)
    elseif _G.GetItemSpell then
        itemSpellName, itemSpellID = _G.GetItemSpell(itemLink or itemID)
    end
    if itemSpellID then
        local spellDesc = (_G.C_Spell and _G.C_Spell.GetSpellDescription and _G.C_Spell.GetSpellDescription(itemSpellID))
            or (_G.GetSpellDescription and _G.GetSpellDescription(itemSpellID))
        if spellDesc and spellDesc ~= "" then
            scratchTooltipTexts[#scratchTooltipTexts + 1] = spellDesc
        end
        if itemSpellName and itemSpellName ~= "" then
            scratchTooltipTexts[#scratchTooltipTexts + 1] = itemSpellName
        end
    end

    -- 2. Modern C_TooltipInfo inspection
    local C_TooltipInfo = _G.C_TooltipInfo
    if C_TooltipInfo then
        if bag and slot and C_TooltipInfo.GetBagItem then
            local bagData = C_TooltipInfo.GetBagItem(bag, slot)
            if bagData then
                ExtractTooltipLineTexts(bagData, scratchTooltipTexts)
            end
        end
        if C_TooltipInfo.GetHyperlink then
            local linkData = C_TooltipInfo.GetHyperlink(itemLink or ("item:" .. itemID))
            if linkData then
                ExtractTooltipLineTexts(linkData, scratchTooltipTexts)
            end
        end
        if itemSpellID and C_TooltipInfo.GetSpellByID then
            local spellData = C_TooltipInfo.GetSpellByID(itemSpellID)
            if spellData then
                ExtractTooltipLineTexts(spellData, scratchTooltipTexts)
            end
        end
    end

    -- 3. Dedicated scan tooltip inspection (fallback only if C_TooltipInfo was unavailable or yielded 0 lines)
    if #scratchTooltipTexts == 0 then
        local scanTip = (sfui.common and sfui.common.get_scan_tooltip and sfui.common.get_scan_tooltip()) or sfuiTooltip
        if scanTip then
            ExtractTooltipFrameTexts(scanTip, bag, slot, itemID, itemLink, scratchTooltipTexts)
        end
    end

    local wellFedSpellName = GetSafeSpellName(19705) or GetSafeSpellName(25941)
    local wellFedLower = wellFedSpellName and wellFedSpellName:lower()

    local eatingSpellName = GetSafeSpellName(433)
    local eatingLower = eatingSpellName and eatingSpellName:lower() or "eating"

    local drinkingSpellName = GetSafeSpellName(430)
    local drinkingLower = drinkingSpellName and drinkingSpellName:lower() or "drinking"

    local healthStr = _G.HEALTH and _G.HEALTH:lower() or "health"
    local manaStr = _G.MANA and _G.MANA:lower() or "mana"

    local isFood = false
    local isDrink = false
    local hasWellFed = false
    local hasUseOrEffect = false

    for i = 1, #scratchTooltipTexts do
        local txt = scratchTooltipTexts[i]
        if type(txt) == "string" and txt ~= "" then
            local lower = txt:lower()

            -- Use / effect marker indicating tooltip has finished streaming its spell description
            if lower:find("use:", 1, true) or lower:find("use :", 1, true)
               or lower:find("restores", 1, true) or lower:find("eating", 1, true)
               or lower:find("drinking", 1, true) or lower:find("seated while", 1, true) then
                hasUseOrEffect = true
            end

            -- Well Fed / stat food effect criteria (English only)
            if lower:find("well fed", 1, true)
               or lower:find("well%-fed")
               or lower:find("wellfed")
               or (wellFedLower and lower:find(wellFedLower, 1, true))
               or lower:find("become well fed", 1, true)
               or lower:find("become well%-fed", 1, true)
               or lower:find("spend at least %d+%s*sec")
               or lower:find("spend at least %d+%s*second")
               or lower:find("eating you will gain", 1, true)
               or lower:find("eating, you will gain", 1, true) then
                hasWellFed = true
                isFood = true
                hasUseOrEffect = true
            end

            -- Food / Drink generic inspection (English only)
            if lower:find(eatingLower, 1, true) or lower:find("eating", 1, true)
               or lower:find("seated while eating", 1, true)
               or lower:find(healthStr, 1, true) or lower:find("health", 1, true) then
                isFood = true
            end
            if lower:find(drinkingLower, 1, true) or lower:find("drinking", 1, true)
               or lower:find("seated while drinking", 1, true)
               or lower:find(manaStr, 1, true) or lower:find("mana", 1, true) then
                isDrink = true
            end
        end
    end

    -- If no Use/Restores/Eating effect was found and no Well Fed was detected,
    -- the tooltip spell data was not yet populated by the client. Do NOT cache false.
    if not hasUseOrEffect and not hasWellFed and not isFood and not isDrink then
        if C_Item_RequestLoadItemDataByID and itemID then
            C_Item_RequestLoadItemDataByID(itemID)
        end
        return false, false, false
    end

    if hasWellFed then
        isFood = true
    elseif not isFood and not isDrink and (subClassID == 5) then
        isFood = true
    end

    local res = { isFood = isFood, isDrink = isDrink, hasWellFed = hasWellFed }
    foodDrinkInfoCache[itemID] = res
    return isFood, isDrink, hasWellFed
end
sfui.common.get_food_drink_info = sfui.items.get_food_drink_info

--- Determines whether an item is a consumable food that grants the "Well Fed" buff.
--- @param bag number|nil
--- @param slot number|nil
--- @param itemID number|nil
--- @param itemLink string|nil
--- @return boolean hasWellFed
function sfui.items.is_buff_food(bag, slot, itemID, itemLink)
    local _, _, hasWellFed = sfui.items.get_food_drink_info(bag, slot, itemID, itemLink)
    return hasWellFed
end
sfui.common.is_buff_food = sfui.items.is_buff_food
sfui.items.has_well_fed = sfui.items.is_buff_food
