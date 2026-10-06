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
