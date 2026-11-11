local addonName, addon = ...
sfui = sfui or {}
sfui.buffs = sfui.buffs or {}
sfui.buffs.consumables = {}

local _G = _G
local ipairs = _G.ipairs
local select = _G.select
local tostring = _G.tostring
local type = _G.type

-- ─────────────────────────────────────────────────────────────
--  CONSUMABLE REMINDER DEFINITIONS (CAMELOT / CLASSIC FOREVER)
-- ─────────────────────────────────────────────────────────────

local CONSUMABLES = {
    food = {
        key = "consumable_food",
        name = "well fed",
        type = "aura",
        spellIDs = { 19705, 19706, 19708, 19709, 19710, 19711, 24800, 25661, 25941 },
        names = { "Well Fed" },
        threshold = 300,
        fallbackIcon = "Interface\\Icons\\Spell_Misc_Food",
        isConsumable = true,
    },
    flask = {
        key = "consumable_flask",
        name = "flask / elixir",
        type = "aura_group",
        spellIDs = {
            17628, 17626, 17627, 17629, 17624, -- Flasks (Supreme Power, Titans, Distilled Wisdom, Chromatic Res, Petrification)
            17539, 17538, 11405, 11406, 17535, -- Greater Arcane, Mongoose, Greater Agility, Giants, Sages
            17537, 17533, 3593, 26276, 11474,  -- Brute Force, Superior Defense, Fortitude, Greater Firepower, Shadow Power
            21920, 24363, 17038, 16323, 16329, -- Frost Power, Mageblood, Winterfall Firewater, Juju Power, Juju Might
        },
        names = {
            "Flask of Supreme Power", "Flask of the Titans", "Flask of Distilled Wisdom",
            "Flask of Chromatic Resistance", "Flask of Petrification",
            "Greater Arcane Elixir", "Elixir of the Mongoose", "Elixir of Greater Agility",
            "Elixir of Giants", "Elixir of Greater Strength",
            "Elixir of the Sages", "Elixir of Sages", "Elixir of Brute Force",
            "Elixir of Superior Defense", "Elixir of Greater Defense",
            "Elixir of Fortitude", "Elixir of Greater Fortitude",
            "Elixir of Greater Firepower", "Elixir of Holy Power", "Elixir of Nature Power",
            "Elixir of Shadow Power", "Elixir of Frost Power",
            "Mageblood Potion", "Mageblood Elixir", "Greater Mageblood Elixir", "Lesser Mageblood Elixir",
            "Elixir of Greater Spirit", "Greater Cleric's Elixir",
            "Elixir of the Phalanx", "Elixir of Wicked Regeneration",
            "Winterfall Firewater", "Juju Power", "Juju Might"
        },
        threshold = 300,
        fallbackIcon = "Interface\\Icons\\INV_Potion_41",
        isConsumable = true,
    },
    weapon_oil_mh = {
        key = "consumable_weapon_mh",
        name = "stone / oil (main hand)",
        type = "weapon_enchant",
        slot = 16,
        threshold = 300,
        fallbackIcon = "Interface\\Icons\\INV_Stone_SharpeningStone_04",
        isConsumable = true,
    },
    weapon_oil_oh = {
        key = "consumable_weapon_oh",
        name = "stone / oil (off hand)",
        type = "weapon_enchant",
        slot = 17,
        threshold = 300,
        fallbackIcon = "Interface\\Icons\\INV_Stone_SharpeningStone_04",
        isConsumable = true,
    },
    fishing_lure = {
        key = "consumable_fishing_lure",
        name = "fishing lure",
        type = "weapon_enchant",
        slot = 16,
        isFishingLure = true,
        threshold = 60,
        fallbackIcon = "Interface\\Icons\\INV_Misc_Fish_02",
        isConsumable = true,
        isKnownCheck = function()
            return sfui.fishing and sfui.fishing.IsFishingPoleEquipped and sfui.fishing.IsFishingPoleEquipped()
        end,
    },
}

sfui.buffs.consumables.DEFINITIONS = CONSUMABLES

--- Returns list of enabled consumable entries
--- @return table
function sfui.buffs.consumables.GetActiveConsumableEntries()
    local result = {}
    local db = SfuiDB and SfuiDB.buffReminders
    if not db then return result end

    if db.trackFood then
        result[#result + 1] = CONSUMABLES.food
    end

    if db.trackFlask then
        result[#result + 1] = CONSUMABLES.flask
    end

    if db.trackFishingLure ~= false then
        result[#result + 1] = CONSUMABLES.fishing_lure
    end

    if db.trackWeaponOil then
        local pClass = sfui.buffs.playerClass
        -- Rogue and Shaman already track class-specific weapon enchants (poisons & weapon imbues)
        if pClass ~= "ROGUE" and pClass ~= "SHAMAN" then
            result[#result + 1] = CONSUMABLES.weapon_oil_mh
            result[#result + 1] = CONSUMABLES.weapon_oil_oh
        end
    end

    return result
end

-- ─────────────────────────────────────────────────────────────
--  SHARED ITEM METADATA & ICON HELPERS
-- ─────────────────────────────────────────────────────────────

local function IsValidTexture(tex)
    return tex ~= nil and tex ~= "" and tex ~= 0
end

local function ResolveItemIcon(itemID, itemLink, texture, info, fallback)
    if IsValidTexture(texture) then
        return texture
    end
    if info and IsValidTexture(info.iconFileID) then
        return info.iconFileID
    end
    if sfui.common and sfui.common.get_item_instant_info then
        local instantIcon = select(5, sfui.common.get_item_instant_info(itemLink or itemID))
        if IsValidTexture(instantIcon) then
            return instantIcon
        end
    end
    local cItem = _G.C_Item
    if cItem and cItem.GetItemIconByID and itemID then
        local cIcon = cItem.GetItemIconByID(itemID)
        if IsValidTexture(cIcon) then
            return cIcon
        end
    end
    if _G.GetItemIcon and itemID then
        local gIcon = _G.GetItemIcon(itemID)
        if IsValidTexture(gIcon) then
            return gIcon
        end
    end
    return fallback
end

local function ExtractLinkBracketName(link)
    if type(link) ~= "string" then return nil end
    local n = link:match("%[(.-)%]")
    if n and n ~= "" then
        return n
    end
    return nil
end

local function ResolveItemName(name, itemLink, info, itemID)
    if type(name) == "string" and name ~= "" then
        return name, false
    end
    local linkName = ExtractLinkBracketName(itemLink) or (info and ExtractLinkBracketName(info.hyperlink))
    if linkName then
        return linkName, false
    end
    local cItem = _G.C_Item
    if cItem and cItem.GetItemNameByID and itemID then
        local cName = cItem.GetItemNameByID(itemID)
        if type(cName) == "string" and cName ~= "" then
            return cName, false
        end
    end
    if cItem and cItem.RequestLoadItemDataByID and itemID then
        cItem.RequestLoadItemDataByID(itemID)
    end
    return nil, true
end

local function MatchesSavedItem(entry, saved)
    if not entry or saved == nil then return false end
    if entry.itemID and entry.itemID == saved then
        return true
    end
    if type(saved) == "string" and saved ~= "" and entry.name and entry.name ~= "" and entry.name == saved then
        return true
    end
    return false
end

local function FindCurrentItemIndex(all, cur)
    if not cur then return 1 end
    for i, item in ipairs(all) do
        if (cur.itemID and item.itemID == cur.itemID)
            or (cur.name and cur.name ~= "" and not cur.isCold and item.name == cur.name) then
            return i
        end
    end
    return 1
end

local function SyncRecordIcon(matchFn, newIcon)
    if not newIcon or not sfui.buffs.scan or not sfui.buffs.scan.GetResults then return end
    local results = sfui.buffs.scan.GetResults()
    if not results then return end
    for i = 1, #results do
        local rec = results[i]
        if rec and rec.entry and matchFn(rec.entry) then
            rec.icon = newIcon
        end
    end
end

-- Forward declarations for cold-item retry scheduling
local ScanInventoryFoods
local ScanInventoryFlasks
local ScanInventoryWeaponOils
local isFoodScanDirty = true
local isFlaskScanDirty = true
local isOilScanDirty = true

local function ScheduleColdConsumableRetry()
    if not (sfui.common and sfui.common.debounce) then return end
    sfui.common.debounce("sfui_consumable_cold_retry", 0.35, function()
        if sfui.common.is_in_combat() then return end
        local cSecrets = _G.C_Secrets
        if cSecrets and cSecrets.ShouldAurasBeSecret and cSecrets.ShouldAurasBeSecret() then return end
        local refreshed = false
        if isFoodScanDirty then
            ScanInventoryFoods()
            refreshed = true
        end
        if isFlaskScanDirty then
            ScanInventoryFlasks()
            refreshed = true
        end
        if isOilScanDirty then
            ScanInventoryWeaponOils()
            refreshed = true
        end
        if refreshed and sfui.buffs and sfui.buffs.UpdateDisplay then
            sfui.buffs.UpdateDisplay()
        end
    end)
end

-- ─────────────────────────────────────────────────────────────
--  INVENTORY FOOD SCANNING & CYCLING
-- ─────────────────────────────────────────────────────────────

local availableFoods = {}
local scratchCounts = {}
local scratchOrder = {}
local scratchItemData = {}

local function ClearFoodCache()
    if sfui.items and sfui.items.clear_food_drink_cache then
        sfui.items.clear_food_drink_cache()
    end
    isFoodScanDirty = true
end
sfui.buffs.consumables.ClearFoodCache = ClearFoodCache

local function IsBuffFood(bag, slot, itemID, itemLink)
    if not itemID then return false end
    if sfui.items and sfui.items.is_buff_food then
        return sfui.items.is_buff_food(bag, slot, itemID, itemLink) and true or false
    elseif sfui.items and sfui.items.get_food_drink_info then
        local _, _, hasWellFed = sfui.items.get_food_drink_info(bag, slot, itemID, itemLink)
        return hasWellFed and true or false
    end
    return false
end

ScanInventoryFoods = function()
    if sfui.common.is_in_combat() then
        isFoodScanDirty = true
        return availableFoods
    end

    _G.wipe(scratchCounts)
    _G.wipe(scratchOrder)
    local anyCold = false

    if sfui.common and sfui.common.for_each_bag_item then
        sfui.common.for_each_bag_item(function(bag, slot, itemID, itemLink, info)
            if not itemID then return end
            local rawName, _, _, ilvl, _, _, _, _, _, texture, _, classID = sfui.common.get_item_info(itemLink or itemID)
            if not rawName and classID == nil then
                local instClassID = sfui.common.get_item_instant_info and select(6, sfui.common.get_item_instant_info(itemLink or itemID))
                if instClassID == nil or instClassID == 0 then
                    anyCold = true
                    if _G.C_Item and _G.C_Item.RequestLoadItemDataByID then
                        _G.C_Item.RequestLoadItemDataByID(itemID)
                    end
                end
            end

            if IsBuffFood(bag, slot, itemID, itemLink) then
                local count = (info and info.stackCount) or 1
                if not scratchCounts[itemID] then
                    scratchCounts[itemID] = count
                    scratchOrder[#scratchOrder + 1] = itemID
                    local entry = scratchItemData[itemID]
                    if not entry then
                        entry = {}
                        scratchItemData[itemID] = entry
                    end
                    local resolvedName, isCold = ResolveItemName(rawName, itemLink, info, itemID)
                    if isCold then anyCold = true end
                    entry.itemID   = itemID
                    entry.itemLink = itemLink or (info and info.hyperlink)
                    entry.name     = resolvedName or ("item " .. tostring(itemID))
                    entry.isCold   = isCold
                    entry.ilvl     = ilvl or 0
                    entry.icon     = ResolveItemIcon(itemID, itemLink, texture, info, "Interface\\Icons\\Spell_Misc_Food")
                else
                    scratchCounts[itemID] = scratchCounts[itemID] + count
                end
            end
        end, true, true, true)
    end

    _G.wipe(availableFoods)
    for _, id in ipairs(scratchOrder) do
        local d = scratchItemData[id]
        if d then
            d.count = scratchCounts[id] or 0
            availableFoods[#availableFoods + 1] = d
        end
    end

    table.sort(availableFoods, function(a, b)
        if (a.ilvl or 0) ~= (b.ilvl or 0) then
            return (a.ilvl or 0) > (b.ilvl or 0)
        end
        return (a.name or "") < (b.name or "")
    end)

    isFoodScanDirty = anyCold
    if anyCold then
        ScheduleColdConsumableRetry()
    end
    return availableFoods
end
sfui.buffs.consumables.ScanInventoryFoods = ScanInventoryFoods
sfui.buffs.consumables.IsBuffFood = IsBuffFood

function sfui.buffs.consumables.GetAvailableFoods()
    if isFoodScanDirty or #availableFoods == 0 then
        ScanInventoryFoods()
    end
    return availableFoods
end

function sfui.buffs.consumables.GetSelectedFood()
    local all = sfui.buffs.consumables.GetAvailableFoods()
    if not all or #all == 0 then
        return nil, all
    end

    local db = SfuiDB and SfuiDB.buffReminders
    local saved = db and db.selectedFood

    if saved then
        for _, f in ipairs(all) do
            if MatchesSavedItem(f, saved) then
                return f, all
            end
        end
    end

    return all[1], all
end

function sfui.buffs.consumables.CycleFood(delta)
    if isFoodScanDirty then
        ScanInventoryFoods()
    end
    local cur, all = sfui.buffs.consumables.GetSelectedFood()
    if not all or #all <= 1 then
        ClearFoodCache()
        ScanInventoryFoods()
        cur, all = sfui.buffs.consumables.GetSelectedFood()
    end
    if not all or #all <= 1 then
        if cur then
            SyncRecordIcon(function(e) return e.key == "consumable_food" end, cur.icon)
            if sfui.buffs and sfui.buffs.UpdateDisplay then
                sfui.buffs.UpdateDisplay()
            end
        end
        return cur
    end

    local curIndex = FindCurrentItemIndex(all, cur)
    local nextIndex = curIndex + (delta > 0 and 1 or -1)
    if nextIndex > #all then
        nextIndex = 1
    elseif nextIndex < 1 then
        nextIndex = #all
    end

    local chosen = all[nextIndex]
    if chosen then
        SfuiDB = SfuiDB or {}
        SfuiDB.buffReminders = SfuiDB.buffReminders or {}
        SfuiDB.buffReminders.selectedFood = chosen.itemID or chosen.name

        SyncRecordIcon(function(e) return e.key == "consumable_food" end, chosen.icon)
        if sfui.buffs and sfui.buffs.UpdateDisplay then
            sfui.buffs.UpdateDisplay()
        end
        if sfui.ring and sfui.ring.request_rebuild then
            sfui.ring.request_rebuild("specs")
        end
        return chosen
    end
    return cur
end

-- ─────────────────────────────────────────────────────────────
--  INVENTORY FLASK / ELIXIR SCANNING & CYCLING
-- ─────────────────────────────────────────────────────────────

local KNOWN_FLASK_ELIXIR_IDS = {
    -- Flasks
    [13510] = true, [13511] = true, [13512] = true, [13513] = true, [13506] = true,
    -- Classic / Camelot Elixirs & Jujus
    [9155]  = true, [13452] = true, [9187]  = true, [9206]  = true, [13447] = true,
    [13453] = true, [13445] = true, [3825]  = true, [21546] = true, [9264]  = true,
    [17708] = true, [20007] = true, [12820] = true, [12451] = true, [12460] = true,
    [6373]  = true, [3389]  = true, [8951]  = true, [9224]  = true, [8949]  = true,
}

local isFlaskCache = {}
local availableFlasks = {}
local flaskScratchCounts = {}
local flaskScratchOrder = {}
local flaskScratchData = {}

local function ClearFlaskCache()
    _G.wipe(isFlaskCache)
    isFlaskScanDirty = true
end
sfui.buffs.consumables.ClearFlaskCache = ClearFlaskCache

local function IsFlaskOrElixir(itemID, name, classID, subClassID)
    if not itemID then return false end
    local cached = isFlaskCache[itemID]
    if cached ~= nil then
        return cached
    end
    if KNOWN_FLASK_ELIXIR_IDS[itemID] then
        isFlaskCache[itemID] = true
        return true
    end
    if classID == 0 and (subClassID == 2 or subClassID == 3) then
        isFlaskCache[itemID] = true
        return true
    end
    if not name or name == "" then
        return false -- cold item; do not cache false
    end
    local ln = name:lower()
    local match = (ln:find("^flask of ") ~= nil)
        or (ln:find("elixir", 1, true) ~= nil)
        or (ln == "winterfall firewater")
        or (ln == "juju power")
        or (ln == "juju might")
        or (ln == "mageblood potion")
    isFlaskCache[itemID] = match
    return match
end

ScanInventoryFlasks = function()
    if sfui.common.is_in_combat() then
        isFlaskScanDirty = true
        return availableFlasks
    end

    _G.wipe(flaskScratchCounts)
    _G.wipe(flaskScratchOrder)
    local anyCold = false
    local pLevel = (_G.UnitLevel and _G.UnitLevel("player")) or 1

    if sfui.common and sfui.common.for_each_bag_item then
        sfui.common.for_each_bag_item(function(_, _, itemID, itemLink, info)
            if not itemID then return end
            local rawName, _, _, ilvl, minLevel, _, _, _, _, texture, _, classID, subClassID = sfui.common.get_item_info(itemLink or itemID)
            if (classID == nil or subClassID == nil) and sfui.common.get_item_instant_info then
                local _, _, _, _, instantTex, instClassID, instSubClassID = sfui.common.get_item_instant_info(itemLink or itemID)
                texture = texture or instantTex
                classID = classID or instClassID
                subClassID = subClassID or instSubClassID
            end
            local resolvedName, isCold = ResolveItemName(rawName, itemLink, info, itemID)
            if isCold and (classID == nil or classID == 0) then
                anyCold = true
            end
            if IsFlaskOrElixir(itemID, resolvedName, classID, subClassID) and pLevel >= (minLevel or 0) then
                local count = (info and info.stackCount) or 1
                if not flaskScratchCounts[itemID] then
                    flaskScratchCounts[itemID] = count
                    flaskScratchOrder[#flaskScratchOrder + 1] = itemID
                    local entry = flaskScratchData[itemID]
                    if not entry then
                        entry = {}
                        flaskScratchData[itemID] = entry
                    end
                    entry.itemID   = itemID
                    entry.itemLink = itemLink or (info and info.hyperlink)
                    entry.name     = resolvedName or ("item " .. tostring(itemID))
                    entry.isCold   = isCold
                    entry.ilvl     = ilvl or 0
                    entry.icon     = ResolveItemIcon(itemID, itemLink, texture, info, "Interface\\Icons\\INV_Potion_41")
                else
                    flaskScratchCounts[itemID] = flaskScratchCounts[itemID] + count
                end
            end
        end, true, true, true)
    end

    _G.wipe(availableFlasks)
    for _, id in ipairs(flaskScratchOrder) do
        local d = flaskScratchData[id]
        if d then
            d.count = flaskScratchCounts[id] or 0
            availableFlasks[#availableFlasks + 1] = d
        end
    end

    table.sort(availableFlasks, function(a, b)
        if (a.ilvl or 0) ~= (b.ilvl or 0) then
            return (a.ilvl or 0) > (b.ilvl or 0)
        end
        return (a.name or "") < (b.name or "")
    end)

    isFlaskScanDirty = anyCold
    if anyCold then
        ScheduleColdConsumableRetry()
    end
    return availableFlasks
end
sfui.buffs.consumables.ScanInventoryFlasks = ScanInventoryFlasks

function sfui.buffs.consumables.GetAvailableFlasks()
    if isFlaskScanDirty or #availableFlasks == 0 then
        ScanInventoryFlasks()
    end
    return availableFlasks
end

function sfui.buffs.consumables.GetSelectedFlask()
    local all = sfui.buffs.consumables.GetAvailableFlasks()
    if not all or #all == 0 then
        return nil, all
    end

    local db = SfuiDB and SfuiDB.buffReminders
    local saved = db and db.selectedFlask
    if saved then
        for _, fl in ipairs(all) do
            if MatchesSavedItem(fl, saved) then
                return fl, all
            end
        end
    end

    return all[1], all
end

function sfui.buffs.consumables.CycleFlask(delta)
    if isFlaskScanDirty then
        ScanInventoryFlasks()
    end
    local cur, all = sfui.buffs.consumables.GetSelectedFlask()
    if not all or #all <= 1 then
        ClearFlaskCache()
        ScanInventoryFlasks()
        cur, all = sfui.buffs.consumables.GetSelectedFlask()
    end
    if not all or #all <= 1 then
        if cur then
            SyncRecordIcon(function(e) return e.key == "consumable_flask" end, cur.icon)
            if sfui.buffs and sfui.buffs.UpdateDisplay then
                sfui.buffs.UpdateDisplay()
            end
        end
        return cur
    end

    local curIndex = FindCurrentItemIndex(all, cur)
    local nextIndex = curIndex + (delta > 0 and 1 or -1)
    if nextIndex > #all then
        nextIndex = 1
    elseif nextIndex < 1 then
        nextIndex = #all
    end

    local chosen = all[nextIndex]
    if chosen then
        SfuiDB = SfuiDB or {}
        SfuiDB.buffReminders = SfuiDB.buffReminders or {}
        SfuiDB.buffReminders.selectedFlask = chosen.itemID or chosen.name

        SyncRecordIcon(function(e) return e.key == "consumable_flask" end, chosen.icon)
        if sfui.buffs and sfui.buffs.UpdateDisplay then
            sfui.buffs.UpdateDisplay()
        end
        if sfui.ring and sfui.ring.request_rebuild then
            sfui.ring.request_rebuild("specs")
        end
        return chosen
    end
    return cur
end

-- ─────────────────────────────────────────────────────────────
--  INVENTORY WEAPON STONE / OIL / POISON SCANNING & CYCLING
-- ─────────────────────────────────────────────────────────────
local KNOWN_WEAPON_OIL_IDS = {
    -- Wizard & Mana Oils
    [20744] = true, [20746] = true, [20750] = true, [20749] = true, [23123] = true, [22522] = true,
    [20745] = true, [20747] = true, [20748] = true, [22521] = true,
    -- Shadow & Frost Oils
    [3824]  = true, [3829]  = true,
    -- Sharpening Stones
    [2862]  = true, [2863]  = true, [2871]  = true, [7964]  = true, [12404] = true,
    [18262] = true, [23122] = true, [23528] = true, [23529] = true,
    -- Weightstones
    [3239]  = true, [3240]  = true, [3241]  = true, [7965]  = true, [12643] = true,
    [28420] = true, [28421] = true,
}

local KNOWN_ROGUE_POISON_IDS = {
    -- Instant Poison I - VII
    [6947]  = true, [6949]  = true, [6950]  = true, [8926]  = true, [8927]  = true, [8928]  = true, [21927] = true,
    -- Deadly Poison I - VII
    [2892]  = true, [2893]  = true, [8984]  = true, [8985]  = true, [20844] = true, [22053] = true, [22054] = true,
    -- Crippling Poison I - II
    [3775]  = true, [3776]  = true,
    -- Mind-numbing Poison I - III
    [5237]  = true, [6951]  = true, [9186]  = true,
    -- Wound Poison I - V
    [10918] = true, [10920] = true, [10921] = true, [10922] = true, [22055] = true,
    -- Anesthetic Poison
    [21835] = true,
}

local isWeaponOilCache = {}
local availableWeaponOils = {}
local oilScratchCounts = {}
local oilScratchOrder = {}
local oilScratchData = {}

local function ClearWeaponOilCache()
    _G.wipe(isWeaponOilCache)
    isOilScanDirty = true
end
sfui.buffs.consumables.ClearWeaponOilCache = ClearWeaponOilCache

local function HasTemporaryWeaponTooltip(bag, slot, itemID, itemLink)
    local cTip = _G.C_TooltipInfo
    if cTip then
        local data = (bag and slot and cTip.GetBagItem and cTip.GetBagItem(bag, slot))
            or (cTip.GetHyperlink and cTip.GetHyperlink(itemLink or ("item:" .. tostring(itemID))))
        if data and data.lines then
            local sawUse = false
            for i = 1, #data.lines do
                local left = data.lines[i] and data.lines[i].leftText
                if type(left) == "string" and left ~= "" then
                    local ln = left:lower()
                    if ln:find("use:", 1, true) then sawUse = true end
                    if ln:find("while applied to target weapon", 1, true)
                        or ln:find("applied to a melee weapon", 1, true)
                        or ln:find("sharpen a bladed weapon", 1, true)
                        or ln:find("increase the damage of a blunt weapon", 1, true)
                        or ln:find("coat a weapon with poison", 1, true) then
                        return true, true
                    end
                end
            end
            return false, sawUse
        end
    end
    return false, true
end

local function IsWeaponOilOrStone(bag, slot, itemID, itemLink, name, classID)
    if not itemID then return false end
    local cached = isWeaponOilCache[itemID]
    if cached ~= nil then
        return cached
    end
    local isRogue = (sfui.buffs.playerClass == "ROGUE")
    if KNOWN_WEAPON_OIL_IDS[itemID] or (isRogue and KNOWN_ROGUE_POISON_IDS[itemID]) then
        isWeaponOilCache[itemID] = true
        return true
    end
    if not name or name == "" then
        return false -- cold item; do not cache false
    end
    local ln = name:lower()
    if ln:find("sharpening stone", 1, true)
        or ln:find("weightstone", 1, true)
        or ln:find("wizard oil", 1, true)
        or ln:find("mana oil", 1, true)
        or ln == "shadow oil"
        or ln == "frost oil"
        or (isRogue and ln:find("poison", 1, true) ~= nil and not ln:find("anti-venom", 1, true)) then
        isWeaponOilCache[itemID] = true
        return true
    end
    if classID == 0 or classID == 7 then
        local isTempWeapon, tooltipLoaded = HasTemporaryWeaponTooltip(bag, slot, itemID, itemLink)
        if isTempWeapon then
            isWeaponOilCache[itemID] = true
            return true
        end
        if not tooltipLoaded then
            return false -- tooltip still streaming; do not cache false
        end
    end
    isWeaponOilCache[itemID] = false
    return false
end

ScanInventoryWeaponOils = function()
    if sfui.common.is_in_combat() then
        isOilScanDirty = true
        return availableWeaponOils
    end

    _G.wipe(oilScratchCounts)
    _G.wipe(oilScratchOrder)
    local anyCold = false

    local pLevel = (_G.UnitLevel and _G.UnitLevel("player")) or 1
    if sfui.common and sfui.common.for_each_bag_item then
        sfui.common.for_each_bag_item(function(bag, slot, itemID, itemLink, info)
            if not itemID then return end
            local rawName, _, _, ilvl, minLevel, _, _, _, _, texture, _, classID = sfui.common.get_item_info(itemLink or itemID)
            if classID == nil and sfui.common.get_item_instant_info then
                local _, _, _, _, instantTex, instClassID = sfui.common.get_item_instant_info(itemLink or itemID)
                texture = texture or instantTex
                classID = instClassID
            end
            local resolvedName, isCold = ResolveItemName(rawName, itemLink, info, itemID)
            if isCold and (classID == nil or classID == 0 or classID == 7 or KNOWN_WEAPON_OIL_IDS[itemID] or KNOWN_ROGUE_POISON_IDS[itemID]) then
                anyCold = true
            end
            if IsWeaponOilOrStone(bag, slot, itemID, itemLink, resolvedName, classID) and pLevel >= (minLevel or 0) then
                local count = (info and info.stackCount) or 1
                if not oilScratchCounts[itemID] then
                    oilScratchCounts[itemID] = count
                    oilScratchOrder[#oilScratchOrder + 1] = itemID
                    local entry = oilScratchData[itemID]
                    if not entry then
                        entry = {}
                        oilScratchData[itemID] = entry
                    end
                    entry.itemID   = itemID
                    entry.itemLink = itemLink or (info and info.hyperlink)
                    entry.name     = resolvedName or ("item " .. tostring(itemID))
                    entry.isCold   = isCold
                    entry.icon     = ResolveItemIcon(itemID, itemLink, texture, info, "Interface\\Icons\\INV_Stone_SharpeningStone_04")
                    entry.ilvl     = ilvl or 0
                else
                    oilScratchCounts[itemID] = oilScratchCounts[itemID] + count
                end
            end
        end, true, true, true)
    end

    _G.wipe(availableWeaponOils)
    for _, id in ipairs(oilScratchOrder) do
        local d = oilScratchData[id]
        if d then
            d.count = oilScratchCounts[id] or 0
            availableWeaponOils[#availableWeaponOils + 1] = d
        end
    end

    table.sort(availableWeaponOils, function(a, b)
        if (a.ilvl or 0) ~= (b.ilvl or 0) then
            return (a.ilvl or 0) > (b.ilvl or 0)
        end
        return (a.name or "") < (b.name or "")
    end)

    isOilScanDirty = anyCold
    if anyCold then
        ScheduleColdConsumableRetry()
    end
    return availableWeaponOils
end
sfui.buffs.consumables.ScanInventoryWeaponOils = ScanInventoryWeaponOils

function sfui.buffs.consumables.GetAvailableWeaponOils()
    if isOilScanDirty or #availableWeaponOils == 0 then
        ScanInventoryWeaponOils()
    end
    return availableWeaponOils
end

function sfui.buffs.consumables.GetSelectedWeaponOil(slot)
    local all = sfui.buffs.consumables.GetAvailableWeaponOils()
    if not all or #all == 0 then
        return nil, all
    end

    local db = SfuiDB and SfuiDB.buffReminders
    local saved = nil
    if db then
        if slot == 17 then
            saved = db.selectedWeaponOilOH or db.selectedWeaponOil
        else
            saved = db.selectedWeaponOilMH or db.selectedWeaponOil
        end
    end

    if saved then
        for _, o in ipairs(all) do
            if MatchesSavedItem(o, saved) then
                return o, all
            end
        end
    end

    return all[1], all
end

function sfui.buffs.consumables.CycleWeaponOil(slot, delta)
    if isOilScanDirty then
        ScanInventoryWeaponOils()
    end
    local cur, all = sfui.buffs.consumables.GetSelectedWeaponOil(slot)
    if not all or #all <= 1 then
        ClearWeaponOilCache()
        ScanInventoryWeaponOils()
        cur, all = sfui.buffs.consumables.GetSelectedWeaponOil(slot)
    end
    if not all or #all <= 1 then
        if cur then
            local targetSlot = slot or 16
            SyncRecordIcon(function(e)
                return (e.key == "consumable_weapon_mh" or e.key == "consumable_weapon_oh" or e.key == "poison_mh" or e.key == "poison_oh")
                    and (e.slot or 16) == targetSlot
            end, cur.icon)
            if sfui.buffs and sfui.buffs.UpdateDisplay then
                sfui.buffs.UpdateDisplay()
            end
        end
        return cur
    end

    local curIndex = FindCurrentItemIndex(all, cur)
    local nextIndex = curIndex + (delta > 0 and 1 or -1)
    if nextIndex > #all then
        nextIndex = 1
    elseif nextIndex < 1 then
        nextIndex = #all
    end

    local chosen = all[nextIndex]
    if chosen then
        local savedKey = chosen.itemID or chosen.name
        SfuiDB = SfuiDB or {}
        SfuiDB.buffReminders = SfuiDB.buffReminders or {}
        if slot == 17 then
            SfuiDB.buffReminders.selectedWeaponOilOH = savedKey
        else
            SfuiDB.buffReminders.selectedWeaponOilMH = savedKey
            SfuiDB.buffReminders.selectedWeaponOil = savedKey
        end

        local targetSlot = slot or 16
        SyncRecordIcon(function(e)
            return (e.key == "consumable_weapon_mh" or e.key == "consumable_weapon_oh" or e.key == "poison_mh" or e.key == "poison_oh")
                and (e.slot or 16) == targetSlot
        end, chosen.icon)
        if sfui.buffs and sfui.buffs.UpdateDisplay then
            sfui.buffs.UpdateDisplay()
        end
        if sfui.ring and sfui.ring.request_rebuild then
            sfui.ring.request_rebuild("specs")
        end
        return chosen
    end
    return cur
end

local function ShouldTrackWeaponOils(db)
    if not db then return false end
    return db.trackWeaponOil or sfui.buffs.playerClass == "ROGUE"
end

if (sfui.isCamelot or sfui.isClassic) and sfui.events then
    sfui.events.RegisterEvent("BAG_UPDATE_DELAYED", function()
        local db = SfuiDB and SfuiDB.buffReminders
        local trackOils = ShouldTrackWeaponOils(db)
        if not (db and db.enabled ~= false and (db.trackFood or db.trackFlask or trackOils)) then return end
        if db.trackFood then isFoodScanDirty = true end
        if db.trackFlask then isFlaskScanDirty = true end
        if trackOils then isOilScanDirty = true end
        if sfui.common.is_in_combat() or (_G.C_Secrets and _G.C_Secrets.ShouldAurasBeSecret and _G.C_Secrets.ShouldAurasBeSecret()) then return end
        if sfui.common.debounce then
            sfui.common.debounce("sfui_food_scan", 0.1, function()
                if sfui.common.is_in_combat() or (_G.C_Secrets and _G.C_Secrets.ShouldAurasBeSecret and _G.C_Secrets.ShouldAurasBeSecret()) then return end
                if db.trackFood then ScanInventoryFoods() end
                if db.trackFlask then ScanInventoryFlasks() end
                if trackOils then ScanInventoryWeaponOils() end
                if sfui.buffs and sfui.buffs.UpdateDisplay then
                    sfui.buffs.UpdateDisplay()
                end
            end)
        else
            if db.trackFood then ScanInventoryFoods() end
            if db.trackFlask then ScanInventoryFlasks() end
            if trackOils then ScanInventoryWeaponOils() end
            if sfui.buffs and sfui.buffs.UpdateDisplay then
                sfui.buffs.UpdateDisplay()
            end
        end
    end)
    sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if isFoodScanDirty or isFlaskScanDirty or isOilScanDirty then
            local db = SfuiDB and SfuiDB.buffReminders
            local trackOils = ShouldTrackWeaponOils(db)
            if not (db and db.enabled ~= false and (db.trackFood or db.trackFlask or trackOils)) then
                isFoodScanDirty = false
                isFlaskScanDirty = false
                isOilScanDirty = false
                return
            end
            if sfui.common.is_in_combat() or (_G.C_Secrets and _G.C_Secrets.ShouldAurasBeSecret and _G.C_Secrets.ShouldAurasBeSecret()) then
                return
            end
            if isFoodScanDirty and db.trackFood then ScanInventoryFoods() end
            if isFlaskScanDirty and db.trackFlask then ScanInventoryFlasks() end
            if isOilScanDirty and trackOils then ScanInventoryWeaponOils() end
            if sfui.buffs and sfui.buffs.scan and sfui.buffs.scan.RequestScan then
                sfui.buffs.scan.RequestScan()
            elseif sfui.buffs and sfui.buffs.UpdateDisplay then
                sfui.buffs.UpdateDisplay()
            end
        end
    end)
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        local db = SfuiDB and SfuiDB.buffReminders
        if db and db.enabled ~= false then
            if db.trackFood then
                isFoodScanDirty = true
                ScanInventoryFoods()
            end
            if db.trackFlask then
                isFlaskScanDirty = true
                ScanInventoryFlasks()
            end
            if ShouldTrackWeaponOils(db) then
                isOilScanDirty = true
                ScanInventoryWeaponOils()
            end
        end
    end)
end

-- ─────────────────────────────────────────────────────────────
--  CONSUMABLE PROVIDER REGISTRATIONS
-- ─────────────────────────────────────────────────────────────
local P = sfui.buffs.providers
if P and P.Register then
    local string_format = string.format
    local GetTime = _G.GetTime

    local function ResolveConsumableCountText(selected, rec)
        if selected and selected.count and selected.count > 0 then
            return tostring(selected.count)
        elseif rec and rec.isMissing then
            return "0"
        end
        return ""
    end

    local function RegisterConsumableProvider(id, spec)
        P.Register(id, {
            scanType = spec.scanType,
            resolveScanIcon = function(entry, icon)
                local selected = spec.getSelected(entry)
                return (selected and selected.icon) or icon
            end,
            resolveVisual = function(rec)
                local selected = spec.getSelected(rec and rec.entry)
                local tex = (selected and selected.icon) or (rec and rec.icon) or P.QUESTION_MARK_ICON
                return tex, ResolveConsumableCountText(selected, rec)
            end,
            resolveAction = function(rec)
                local entry = rec and rec.entry
                local selected = spec.getSelected(entry)
                if not selected or (selected.count or 0) <= 0 then
                    return nil
                end
                if spec.useSlot then
                    if not selected.itemID then return nil end
                    local targetSlot = (entry and entry.slot) or 16
                    return "item", "item:" .. selected.itemID, targetSlot, nil
                end
                local itemRef = selected.itemID and ("item:" .. selected.itemID) or selected.name
                if not itemRef then return nil end
                return "item", itemRef, nil, nil
            end,
            cycle = function(rec, delta)
                spec.cycle(rec and rec.entry, delta)
                return true
            end,
            populateTooltip = function(tip, rec)
                local entry = rec and rec.entry
                local selected, all = spec.getSelected(entry)
                if (not selected or not all or #all == 0) and spec.clearCache then
                    spec.clearCache()
                    selected, all = spec.getSelected(entry)
                end

                local hasValidItem = selected and (spec.allowWithoutID or selected.itemLink or selected.itemID)
                if hasValidItem then
                    tip:ClearLines()
                    if tip.SetHyperlink and (selected.itemLink or selected.itemID) then
                        tip:SetHyperlink(selected.itemLink or ("item:" .. selected.itemID))
                    end
                    if (tip:NumLines() or 0) == 0 then
                        tip:AddLine((selected.name or spec.fallbackLabel):lower(), 1, 1, 1)
                    end
                    tip:AddLine(" ")

                    local slotLabel = spec.useSlot and (((entry and entry.slot) == 17) and "off hand" or "main hand") or nil
                    local missingLabel = slotLabel and ("missing " .. slotLabel .. " enchant") or spec.missingLabel
                    local expiringLabel = slotLabel and ("expiring " .. slotLabel) or spec.expiringLabel
                    local activeLabel = slotLabel and (slotLabel .. " active") or spec.activeLabel

                    if rec.isMissing then
                        tip:AddLine("|cffff4444[" .. missingLabel .. "]|r", 1, 0.4, 0.4)
                    elseif rec.isExpiring then
                        local rem = (rec.expirationTime and rec.expirationTime > 0) and (rec.expirationTime - GetTime()) or 0
                        if rem > 0 then
                            tip:AddLine(string_format("|cffffcc00[%s]|r remaining: |cffffd100%s|r", expiringLabel, P.FormatTime(rem)), 1, 0.8, 0)
                        else
                            tip:AddLine("|cffffcc00[" .. expiringLabel .. "]|r", 1, 0.8, 0)
                        end
                    else
                        tip:AddLine("|cff00ff00[" .. activeLabel .. "]|r", 0.4, 1, 0.4)
                    end

                    if selected.count and selected.count > 0 then
                        if _G.InCombatLockdown and _G.InCombatLockdown() then
                            tip:AddLine("|cff888888[combat locked]|r", 0.6, 0.6, 0.6)
                        else
                            local suffix = slotLabel and (" (" .. slotLabel .. ")") or ""
                            tip:AddLine("|cff55ff55[click to " .. spec.verb .. "]|r " .. (selected.name or spec.fallbackLabel):lower() .. suffix, 0.3, 1, 0.3)
                        end
                    else
                        tip:AddLine("|cffff5555" .. spec.emptyMessage .. "|r", 0.9, 0.4, 0.4)
                    end

                    P.AddItemChoiceList(tip, spec.scrollPrompt, all, selected)
                    return
                end

                P.AddStatusHeader(tip, rec)
                if spec.emptySubtitle then
                    tip:AddLine(spec.emptySubtitle, 0.6, 0.6, 0.6)
                end
                tip:AddLine(" ")
                tip:AddLine("|cffff5555" .. spec.emptyMessage .. "|r", 0.9, 0.4, 0.4)
            end,
        })
    end

    RegisterConsumableProvider("consumable_food", {
        scanType = "aura",
        fallbackLabel = "food",
        verb = "eat",
        missingLabel = "missing well fed buff",
        expiringLabel = "expiring well fed",
        activeLabel = "well fed active",
        emptyMessage = "no food with buff in bags",
        scrollPrompt = "scroll wheel to select food:",
        getSelected = function()
            return sfui.buffs.consumables.GetSelectedFood()
        end,
        clearCache = ClearFoodCache,
        cycle = function(_, delta)
            return sfui.buffs.consumables.CycleFood(delta)
        end,
    })

    RegisterConsumableProvider("consumable_flask", {
        scanType = "aura",
        fallbackLabel = "flask / elixir",
        verb = "drink",
        missingLabel = "missing flask / elixir",
        expiringLabel = "expiring flask / elixir",
        activeLabel = "flask / elixir active",
        emptyMessage = "no flask / elixir in bags",
        scrollPrompt = "scroll wheel to select flask / elixir:",
        getSelected = function()
            return sfui.buffs.consumables.GetSelectedFlask()
        end,
        clearCache = ClearFlaskCache,
        cycle = function(_, delta)
            return sfui.buffs.consumables.CycleFlask(delta)
        end,
    })

    RegisterConsumableProvider("consumable_oil", {
        scanType = "weapon_enchant",
        useSlot = true,
        allowWithoutID = true,
        fallbackLabel = "weapon oil",
        verb = "apply",
        emptySubtitle = "apply weapon temporary enchant / poison",
        emptyMessage = "no weapon oil / stone in bags",
        scrollPrompt = "scroll wheel to select oil / stone:",
        getSelected = function(entry)
            return sfui.buffs.consumables.GetSelectedWeaponOil((entry and entry.slot) or 16)
        end,
        clearCache = ClearWeaponOilCache,
        cycle = function(entry, delta)
            return sfui.buffs.consumables.CycleWeaponOil((entry and entry.slot) or 16, delta)
        end,
    })
end

