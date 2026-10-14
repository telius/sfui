local addonName, addon = ...
sfui = sfui or {}
sfui.ring = sfui.ring or {}
sfui.ring.utility = sfui.ring.utility or {}

local u = sfui.ring.utility

local _G = _G
local UnitClass = _G.UnitClass
local C_SpellBook = _G.C_SpellBook
local C_Spell = _G.C_Spell
local C_Item = _G.C_Item
local C_ToyBox = _G.C_ToyBox
local C_MountJournal = _G.C_MountJournal
local GetItemCount = _G.GetItemCount
local PlayerHasToy = _G.PlayerHasToy
local pcall = _G.pcall
local tostring = _G.tostring
local tonumber = _G.tonumber
local pairs = _G.pairs
local ipairs = _G.ipairs
local Enum = _G.Enum

-- ── 1. Spell & Item Resolution Helpers ───────────────────────────────────────

local function is_spell_known(spellID)
    if not spellID then return false end
    if C_SpellBook and C_SpellBook.IsSpellKnown and Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID, Enum.SpellBookSpellBank.Player)
        if ok and known then return true end
    end
    if C_SpellBook and C_SpellBook.IsSpellInSpellBook and Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player then
        local ok, known = pcall(C_SpellBook.IsSpellInSpellBook, spellID, Enum.SpellBookSpellBank.Player, true)
        if ok and known then return true end
    end
    if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook then
        local ok, known = pcall(C_SpellBook.IsSpellKnownOrInSpellBook, spellID)
        if ok and known then return true end
    end
    if _G.IsPlayerSpell then
        local ok, known = pcall(_G.IsPlayerSpell, spellID)
        if ok and known then return true end
    end
    if C_Spell and C_Spell.IsSpellKnown then
        local ok, known = pcall(C_Spell.IsSpellKnown, spellID)
        if ok and known then return true end
    end
    if C_Spell and C_Spell.IsSpellKnownOrOverridesKnown then
        local ok, known = pcall(C_Spell.IsSpellKnownOrOverridesKnown, spellID)
        if ok and known then return true end
    end
    if _G.IsSpellKnown then
        local ok, known = pcall(_G.IsSpellKnown, spellID)
        if ok and known then return true end
    end
    return false
end
u.is_spell_known = is_spell_known

local function get_spell_details(spellID)
    local name, icon
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and info then
            name = info.name
            icon = info.iconID
        end
    end
    if not name and C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, spellID)
        if ok then name = n end
    end
    if not icon and C_Spell and C_Spell.GetSpellTexture then
        local ok, i = pcall(C_Spell.GetSpellTexture, spellID)
        if ok then icon = i end
    end
    if not name and _G.GetSpellInfo then
        local n, _, i = _G.GetSpellInfo(spellID)
        name = n
        icon = icon or i
    end
    return name, icon
end
u.get_spell_details = get_spell_details

local function get_item_details(itemID)
    local name, icon
    if C_Item and C_Item.GetItemInfo then
        local ok, n, _, _, _, _, _, _, _, _, i = pcall(C_Item.GetItemInfo, itemID)
        if ok then
            name = n
            icon = i
        end
    end
    if not icon and C_Item and C_Item.GetItemIconByID then
        local ok, i = pcall(C_Item.GetItemIconByID, itemID)
        if ok then icon = i end
    end
    if not name and _G.GetItemInfo then
        local n, _, _, _, _, _, _, _, _, i = _G.GetItemInfo(itemID)
        name = n
        icon = icon or i
    end
    return name, icon
end
u.get_item_details = get_item_details

local function get_toy_details(toyID)
    if C_ToyBox and C_ToyBox.GetToyInfo then
        local ok, _, name, icon = pcall(C_ToyBox.GetToyInfo, toyID)
        if ok and (name or icon) then
            return name, icon
        end
    end
    return get_item_details(toyID)
end
u.get_toy_details = get_toy_details

local function get_macro_details(macroID)
    if _G.GetMacroInfo then
        local ok, name, icon = pcall(_G.GetMacroInfo, macroID)
        if ok and (name or icon) then
            return name, icon
        end
    end
    return tostring(macroID), nil
end
u.get_macro_details = get_macro_details

-- ── 2. Class Default Utility & Pet Spells ───────────────────────────────────

local CLASS_DEFAULT_SPELLS = {
    WARLOCK = {
        688,    -- Summon Imp
        697,    -- Summon Voidwalker
        691,    -- Summon Felhunter
        366228, -- Summon Sayaad (Retail)
        712,    -- Summon Succubus (Classic/Camelot)
        30146,  -- Summon Felguard (Demonology)
        6201,   -- Create Healthstone
        29893,  -- Create Soulwell
        20707,  -- Soulstone
        698,    -- Ritual of Summoning
        111771, -- Demonic Gateway
        126,    -- Eye of Kilrogg
        5697,   -- Unending Breath
    },
    HUNTER = {
        883,    -- Call Pet 1
        83242,  -- Call Pet 2
        83243,  -- Call Pet 3
        83244,  -- Call Pet 4
        83245,  -- Call Pet 5
        2641,   -- Dismiss Pet
        982,    -- Revive Pet
        136,    -- Mend Pet
        1462,   -- Beast Lore
        6197,   -- Eagle Eye
        5384,   -- Feign Death
        1543,   -- Flare
        199483, -- Camouflage
        34477,  -- Misdirection
    },
    MAGE = {
        1459,   -- Arcane Intellect
        130,    -- Slow Fall
        190336, -- Conjure Refreshment
        42955,  -- Conjure Refreshment (rank)
        108978, -- Alter Time
        55342,  -- Mirror Image
        45438,  -- Ice Block
        66,     -- Invisibility
        110959, -- Greater Invisibility
    },
    DRUID = {
        5487,   -- Bear Form
        768,    -- Cat Form
        783,    -- Travel Form
        24858,  -- Moonkin Form
        114282, -- Treant Form
        5215,   -- Prowl
        1126,   -- Mark of the Wild
        20484,  -- Rebirth
        50769,  -- Revive
        193753, -- Dreamwalk
        18960,  -- Teleport: Moonglade
        1850,   -- Dash
    },
    PALADIN = {
        465,    -- Devotion Aura
        32223,  -- Crusader Aura
        183435, -- Retribution Aura
        317920, -- Concentration Aura
        190784, -- Divine Steed
        1044,   -- Blessing of Freedom
        1022,   -- Blessing of Protection
        633,    -- Lay on Hands
        7328,   -- Redemption
        391054, -- Intercession
    },
    PRIEST = {
        21562,  -- Power Word: Fortitude
        1706,   -- Levitate
        13877,  -- Shadowform
        32375,  -- Mass Dispel
        73325,  -- Leap of Faith
        2096,   -- Mind Vision
        2006,   -- Resurrection
        212036, -- Mass Resurrection
        19236,  -- Desperate Prayer
    },
    ROGUE = {
        1784,   -- Stealth
        1856,   -- Vanish
        114018, -- Shroud of Concealment
        921,    -- Pick Pocket
        1804,   -- Pick Lock
        1725,   -- Distract
        6770,   -- Sap
        2983,   -- Sprint
        185311, -- Crimson Vial
    },
    DEATHKNIGHT = {
        61999,  -- Raise Ally
        50977,  -- Death Gate
        111673, -- Control Undead
        3714,   -- Path of Frost
        42650,  -- Army of the Dead
        46584,  -- Raise Dead
        48707,  -- Anti-Magic Shell
    },
    SHAMAN = {
        556,    -- Astral Recall
        2645,   -- Ghost Wolf
        546,    -- Water Walking
        6196,   -- Far Sight
        2008,   -- Ancestral Spirit
        198103, -- Earth Elemental
        8512,   -- Windfury Totem
        8143,   -- Tremor Totem
        192058, -- Capacitor Totem
    },
    MONK = {
        125883, -- Zen Flight
        101643, -- Transcendence
        119996, -- Transcendence: Transfer
        115450, -- Detox
        115178, -- Resuscitate
        212051, -- Reawaken
        116670, -- Vivify
        109132, -- Roll
    },
    DEMONHUNTER = {
        188501, -- Spectral Sight
        258920, -- Immolation Aura
        191427, -- Metamorphosis
        195072, -- Fel Rush
        189110, -- Infernal Strike
        196718, -- Darkness
    },
    EVOKER = {
        358267, -- Hover
        364342, -- Blessing of the Bronze
        361227, -- Return
        83968,  -- Mass Return
        369459, -- Source of Magic
        370665, -- Rescue
    },
    WARRIOR = {
        6673,   -- Battle Shout
        97462,  -- Rallying Cry
        18499,  -- Berserker Rage
        6544,   -- Heroic Leap
        100,    -- Charge
        3411,   -- Intervene
    },
}

function u.get_default_spells(playerClass)
    return CLASS_DEFAULT_SPELLS[playerClass] or {}
end

local function get_class_and_spec()
    local cls = (sfui.talents and sfui.talents.get_player_class and sfui.talents.get_player_class())
    if not cls or cls == "" then
        local _, eng = UnitClass("player")
        cls = eng or "WARRIOR"
    end
    local specID = (sfui.talents and sfui.talents.get_current_spec_id and sfui.talents.get_current_spec_id()) or 0
    return cls, specID
end
u.get_class_and_spec = get_class_and_spec

-- ── 3. Profile & Slot Persistence ───────────────────────────────────────────

--- build pure default slots for a class and spec, filtering strictly by known spells.
--- @param playerClass string
--- @return table
function u.build_default_slots(playerClass)
    local list = CLASS_DEFAULT_SPELLS[playerClass] or {}
    local slots = {}
    for i = 1, #list do
        local spellID = list[i]
        if is_spell_known(spellID) then
            local name, icon = get_spell_details(spellID)
            slots[#slots + 1] = {
                type = "spell",
                id   = spellID,
                name = name or tostring(spellID),
                icon = icon,
            }
        end
    end
    return slots
end

--- retrieve configured slots for a class & spec.
--- if user has not customized, seeds default known spells into an array of up to 12 slots.
--- @param playerClass string
--- @param specID number
--- @return table slots, boolean isCustomized
function u.get_spec_slots(playerClass, specID)
    local allCustom = sfui.db.Get("ring", "custom_slots", {}) or {}
    local classCustom = allCustom[playerClass]
    local specCustom = classCustom and classCustom[specID]

    if specCustom then
        return specCustom, true
    end

    local defaults = u.build_default_slots(playerClass)
    local slots = {}
    for i = 1, 12 do
        slots[i] = defaults[i]
    end
    return slots, false
end

--- update a specific slot index for class and spec.
--- @param playerClass string
--- @param specID number
--- @param slotIdx number
--- @param slotData table|nil
function u.set_spec_slot(playerClass, specID, slotIdx, slotData)
    local allCustom = sfui.db.Get("ring", "custom_slots", {}) or {}
    allCustom[playerClass] = allCustom[playerClass] or {}
    local currentSlots, isCustom = u.get_spec_slots(playerClass, specID)

    local newSlots = {}
    for i = 1, 12 do
        if i == slotIdx then
            newSlots[i] = slotData
        else
            newSlots[i] = currentSlots[i]
        end
    end

    allCustom[playerClass][specID] = newSlots
    sfui.db.Set("ring", "custom_slots", allCustom)
    sfui.ring.rebuild("utility")
end

--- clear a slot index back to nil/empty.
--- @param playerClass string
--- @param specID number
--- @param slotIdx number
function u.clear_spec_slot(playerClass, specID, slotIdx)
    u.set_spec_slot(playerClass, specID, slotIdx, nil)
end

--- reset custom slots for class & spec to pure defaults.
--- @param playerClass string
--- @param specID number
function u.reset_spec_to_defaults(playerClass, specID)
    local allCustom = sfui.db.Get("ring", "custom_slots", {}) or {}
    if allCustom[playerClass] then
        allCustom[playerClass][specID] = nil
    end
    sfui.db.Set("ring", "custom_slots", allCustom)
    sfui.ring.rebuild("utility")
end

--- wipe all slots for class & spec.
--- @param playerClass string
--- @param specID number
function u.clear_all_spec_slots(playerClass, specID)
    local allCustom = sfui.db.Get("ring", "custom_slots", {}) or {}
    allCustom[playerClass] = allCustom[playerClass] or {}
    allCustom[playerClass][specID] = {}
    sfui.db.Set("ring", "custom_slots", allCustom)
    sfui.ring.rebuild("utility")
end

-- ── 4. Provider Registration ────────────────────────────────────────────────

sfui.ring.register_provider("utility", {
    name   = "utility",
    title  = "class utility & custom",
    events = {
        "SPELLS_CHANGED",
        "PLAYER_SPECIALIZATION_CHANGED",
        "TRAIT_CONFIG_UPDATED",
        "ACTIVE_TALENT_GROUP_CHANGED",
        "PLAYER_ENTERING_WORLD",
    },
    build  = function(out)
        local playerClass, specID = get_class_and_spec()
        local slots, isCustom = u.get_spec_slots(playerClass, specID)

        local seen = {}
        for i = 1, 12 do
            local item = slots[i]
            if item and item.type and item.id then
                if item.type == "spell" then
                    -- strict filter: only display when actually known
                    if is_spell_known(item.id) then
                        local name, icon = get_spell_details(item.id)
                        local sName = (name or item.name or tostring(item.id)):lower()
                        local key = "spell:" .. tostring(item.id)
                        if not seen[key] then
                            seen[key] = true
                            out[#out + 1] = {
                                id    = "util_spell_" .. tostring(item.id),
                                label = sName,
                                icon  = icon or item.icon or "Interface\\Icons\\INV_Misc_QuestionMark",
                                attrs = {
                                    type  = "spell",
                                    spell = item.id,
                                },
                            }
                        end
                    end
                elseif item.type == "item" then
                    local count = GetItemCount(item.id)
                    local name, icon = get_item_details(item.id)
                    local iName = (name or item.name or tostring(item.id)):lower()
                    local key = "item:" .. tostring(item.id)
                    if not seen[key] then
                        seen[key] = true
                        out[#out + 1] = {
                            id    = "util_item_" .. tostring(item.id),
                            label = iName,
                            icon  = icon or item.icon or "Interface\\Icons\\INV_Misc_QuestionMark",
                            count = count,
                            attrs = {
                                type = "item",
                                item = name or item.id,
                            },
                        }
                    end
                elseif item.type == "toy" then
                    if PlayerHasToy(item.id) then
                        local name, icon = get_toy_details(item.id)
                        local tName = (name or item.name or tostring(item.id)):lower()
                        local key = "toy:" .. tostring(item.id)
                        if not seen[key] then
                            seen[key] = true
                            out[#out + 1] = {
                                id    = "util_toy_" .. tostring(item.id),
                                label = tName,
                                icon  = icon or item.icon or "Interface\\Icons\\INV_Misc_QuestionMark",
                                attrs = {
                                    type = "toy",
                                    toy  = item.id,
                                },
                            }
                        end
                    end
                elseif item.type == "macro" then
                    local name, icon = get_macro_details(item.id)
                    local mName = (name or item.name or tostring(item.id)):lower()
                    local key = "macro:" .. tostring(item.id)
                    if not seen[key] then
                        seen[key] = true
                        out[#out + 1] = {
                            id    = "util_macro_" .. tostring(item.id),
                            label = mName,
                            icon  = icon or item.icon or "Interface\\Icons\\INV_Misc_QuestionMark",
                            attrs = {
                                type  = "macro",
                                macro = item.id,
                            },
                        }
                    end
                end
            end
        end
    end,
})
