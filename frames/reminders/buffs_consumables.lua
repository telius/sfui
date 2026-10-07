local addonName, addon = ...
sfui = sfui or {}
sfui.buffs = sfui.buffs or {}
sfui.buffs.consumables = {}

local _G = _G
local GetInventoryItemLink = _G.GetInventoryItemLink

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
            "Elixir of Giants", "Elixir of the Sages", "Elixir of Brute Force",
            "Elixir of Superior Defense", "Elixir of Fortitude", "Elixir of Greater Firepower",
            "Elixir of Shadow Power", "Elixir of Frost Power", "Mageblood Potion",
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

    if db.trackWeaponOil then
        local pClass = sfui.buffs.playerClass
        -- Rogue and Shaman already track class-specific weapon enchants (poisons & weapon imbues)
        if pClass ~= "ROGUE" and pClass ~= "SHAMAN" then
            if GetInventoryItemLink and GetInventoryItemLink("player", 16) then
                result[#result + 1] = CONSUMABLES.weapon_oil_mh
            end
            if GetInventoryItemLink and GetInventoryItemLink("player", 17) then
                result[#result + 1] = CONSUMABLES.weapon_oil_oh
            end
        end
    end

    return result
end

-- ─────────────────────────────────────────────────────────────
--  INVENTORY FOOD SCANNING & CYCLING
-- ─────────────────────────────────────────────────────────────

local isBuffFoodCache = {}
local availableFoods = {}
local isFoodScanDirty = true

local function IsBuffFood(bag, slot, itemID, itemLink)
    if not itemID then return false end
    if isBuffFoodCache[itemID] ~= nil then
        return isBuffFoodCache[itemID]
    end

    local name, _, _, _, _, _, _, _, _, _, _, classID, subClassID = sfui.common.get_item_info(itemLink or itemID)
    if not name then
        return false -- metadata not yet loaded; do not cache false
    end

    local isConsumableClass = (classID == 0) or (_G.Enum and _G.Enum.ItemClass and classID == _G.Enum.ItemClass.Consumable)
    local isFoodDrink = (subClassID == 5) or (_G.Enum and _G.Enum.ItemConsumableSubclass and subClassID == _G.Enum.ItemConsumableSubclass.Fooddrink)
    if not (isConsumableClass and isFoodDrink) then
        isBuffFoodCache[itemID] = false
        return false
    end

    local wellFedText = _G.GetSpellInfo and _G.GetSpellInfo(19705)
    local wellFedLower = wellFedText and wellFedText:lower() or "well fed"

    local tip = sfui.tooltip or _G.SfuiGameTooltip
    if tip and tip.SetOwner and (tip.SetBagItem or tip.SetHyperlink) then
        if _G.UIParent then tip:SetOwner(_G.UIParent, "ANCHOR_NONE") end
        tip:ClearLines()
        if bag and slot and tip.SetBagItem then
            tip:SetBagItem(bag, slot)
        else
            tip:SetHyperlink("item:" .. itemID)
        end
        local numLines = tip:NumLines() or 0
        if numLines <= 1 then
            return false -- tooltip lines not yet populated
        end
        for i = 1, numLines do
            local fsL = _G["SfuiGameTooltipTextLeft" .. i]
            if fsL then
                local txt = fsL:GetText()
                if txt then
                    local lower = txt:lower()
                    if lower:find(wellFedLower, 1, true) or lower:find("well fed", 1, true) then
                        isBuffFoodCache[itemID] = true
                        return true
                    end
                end
            end
        end
        isBuffFoodCache[itemID] = false
        return false
    end

    return false
end

local function ScanInventoryFoods()
    local counts = {}
    local order = {}
    local itemData = {}

    if sfui.common and sfui.common.for_each_bag_item then
        sfui.common.for_each_bag_item(function(bag, slot, itemID, itemLink, info)
            if itemID and IsBuffFood(bag, slot, itemID, itemLink) then
                local count = (info and info.stackCount) or 1
                if not counts[itemID] then
                    counts[itemID] = count
                    order[#order + 1] = itemID
                    local name, _, _, _, _, _, _, _, _, texture = sfui.common.get_item_info(itemLink or itemID)
                    itemData[itemID] = {
                        itemID   = itemID,
                        itemLink = itemLink,
                        name     = name or ("item " .. itemID),
                        icon     = texture or "Interface\\Icons\\Spell_Misc_Food",
                    }
                else
                    counts[itemID] = counts[itemID] + count
                end
            end
        end, false, true, true)
    end

    _G.wipe(availableFoods)
    for _, id in ipairs(order) do
        local d = itemData[id]
        if d then
            d.count = counts[id] or 0
            availableFoods[#availableFoods + 1] = d
        end
    end

    table.sort(availableFoods, function(a, b)
        return (a.name or "") < (b.name or "")
    end)

    isFoodScanDirty = false
    return availableFoods
end
sfui.buffs.consumables.ScanInventoryFoods = ScanInventoryFoods

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
            if f.name == saved or f.itemID == saved then
                return f, all
            end
        end
    end

    return all[1], all
end

function sfui.buffs.consumables.CycleFood(delta)
    local cur, all = sfui.buffs.consumables.GetSelectedFood()
    if not all or #all <= 1 then
        return cur
    end

    local curIndex = 1
    if cur then
        for i, f in ipairs(all) do
            if f.name == cur.name or f.itemID == cur.itemID then
                curIndex = i
                break
            end
        end
    end

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
        SfuiDB.buffReminders.selectedFood = chosen.name

        if sfui.buffs and sfui.buffs.UpdateDisplay then
            sfui.buffs.UpdateDisplay()
        end
        return chosen
    end
    return cur
end

if sfui.events then
    sfui.events.RegisterEvent("BAG_UPDATE_DELAYED", function()
        isFoodScanDirty = true
        ScanInventoryFoods()
        if sfui.buffs and sfui.buffs.UpdateDisplay then
            sfui.buffs.UpdateDisplay()
        end
    end)
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        isFoodScanDirty = true
        ScanInventoryFoods()
    end)
end
