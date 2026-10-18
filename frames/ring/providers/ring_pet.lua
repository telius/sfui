local addonName, addon = ...
sfui = sfui or {}
sfui.ring = sfui.ring or {}

local _G = _G
local UnitClass = _G.UnitClass
local tonumber = _G.tonumber
local tostring = _G.tostring
local pcall = _G.pcall

local function is_hunter_in_camelot()
    local isCam = (sfui.isCamelot or (sfui.compat and sfui.compat.is_camelot))
    local pClass = (sfui.common and sfui.common.get_player_class and sfui.common.get_player_class())
                   or (UnitClass and select(2, UnitClass("player")))
    return not not (isCam and pClass == "HUNTER")
end

local function is_spell_known(spellID)
    if sfui.common and sfui.common.is_spell_known then
        return sfui.common.is_spell_known(spellID)
    end
    if _G.IsSpellKnown then
        local ok, known = pcall(_G.IsSpellKnown, spellID)
        if ok and known then return true end
    end
    if _G.IsPlayerSpell then
        local ok, known = pcall(_G.IsPlayerSpell, spellID)
        if ok and known then return true end
    end
    return false
end

local function get_spell_details(spellID)
    local C_Spell = _G.C_Spell
    local name, icon
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and info then
            name = info.name
            icon = info.iconID
        end
    end
    if not name and _G.GetSpellInfo then
        local ok, n, _, i = pcall(_G.GetSpellInfo, spellID)
        if ok then
            name = n
            icon = i
        end
    end
    return name, icon
end

local function build_pet_ring(out)
    if not is_hunter_in_camelot() then return end

    local seen = {}

    local function add_spell(spellID, fallbackName, fallbackIcon, macrotext)
        local idNum = tonumber(spellID) or spellID
        local name, icon = get_spell_details(idNum)
        local sName = (name or fallbackName or tostring(idNum)):lower()
        local sIcon = icon or fallbackIcon or "Interface\\Icons\\INV_Misc_QuestionMark"

        local key = "spell:" .. tostring(idNum)
        if seen[key] then return end
        seen[key] = true

        local slot = {
            id      = "pet_spell_" .. tostring(idNum),
            spellID = tonumber(idNum),
            label   = sName,
            icon    = sIcon,
            color   = { 0.2, 0.9, 0.4 },
        }

        if macrotext then
            slot.attrs = {
                type      = "macro",
                macrotext = macrotext,
            }
        else
            slot.attrs = {
                type  = "spell",
                spell = idNum,
            }
        end
        out[#out + 1] = slot
    end

    local function add_macro(id, label, icon, macrotext, insecureFunc, color)
        if seen[id] then return end
        seen[id] = true

        local slot = {
            id      = "pet_" .. id,
            label   = label:lower(),
            icon    = icon,
            color   = color or { 0.8, 0.8, 0.8 },
        }

        if insecureFunc then
            slot.allow_combat_insecure = false
            slot.insecure_func = insecureFunc
            slot.attrs = {
                type      = "macro",
                macrotext = macrotext or "",
            }
        else
            slot.attrs = {
                type      = "macro",
                macrotext = macrotext,
            }
        end
        out[#out + 1] = slot
    end

    -- 1. Mend Pet (136)
    if is_spell_known(136) then
        add_spell(136, "mend pet", "Interface\\Icons\\Ability_Hunter_MendPet")
    end

    -- 2. Call Pet Spells
    -- Call Pet 1 (883)
    if is_spell_known(883) then
        add_spell(883, "call pet", "Interface\\Icons\\Ability_Hunter_BeastCall")
    end
    -- Call Pet 2..5 (if known)
    local callPets = { 83242, 83243, 83244, 83245 }
    for i = 1, #callPets do
        local cpID = callPets[i]
        if is_spell_known(cpID) then
            add_spell(cpID, "call pet " .. (i + 1), "Interface\\Icons\\Ability_Hunter_PetCall" .. (i + 1))
        end
    end

    -- 3. Dismiss Pet (2641)
    if is_spell_known(2641) then
        add_spell(2641, "dismiss pet", "Interface\\Icons\\Spell_Nature_SpiritWolf")
    else
        add_macro("dismiss", "dismiss pet", "Interface\\Icons\\Spell_Nature_SpiritWolf", "/run PetDismiss()", nil, { 0.9, 0.3, 0.3 })
    end

    -- 4. Revive Pet (982)
    if is_spell_known(982) then
        add_spell(982, "revive pet", "Interface\\Icons\\Ability_Hunter_BeastSoothe")
    end

    -- 5. Eyes of the Beast (1002)
    if is_spell_known(1002) then
        add_spell(1002, "eyes of the beast", "Interface\\Icons\\Ability_EyeOfTheOwl")
    end

    -- 6. Beast Training (5149)
    if is_spell_known(5149) then
        add_spell(5149, "beast training", "Interface\\Icons\\Ability_Hunter_BeastTraining")
    else
        add_macro("beasttraining", "beast training", "Interface\\Icons\\Ability_Hunter_BeastTraining", "/cast Beast Training", nil, { 0.88, 0.62, 0.14 })
    end

    -- 7. Fast Feed Pet (Action / Macro)
    add_macro("feed", "feed pet", "Interface\\Icons\\Ability_Hunter_BeastTraining", "/cast Feed Pet", function()
        if sfui.pet and sfui.pet.fast_feed then
            sfui.pet.fast_feed()
        end
    end, { 0.3, 0.9, 0.3 })

    -- 8. Beast Lore (1462)
    if is_spell_known(1462) then
        add_spell(1462, "beast lore", "Interface\\Icons\\Ability_Physical_Taunt")
    end

    -- 9. Pet Command: Attack
    add_macro("attack", "pet attack", "Interface\\Icons\\Ability_GhoulFrenzy", "/petattack", nil, { 1.0, 0.3, 0.3 })

    -- 10. Pet Command: Follow
    add_macro("follow", "pet follow", "Interface\\Icons\\Ability_Tracking", "/petfollow", nil, { 0.3, 0.8, 1.0 })

    -- 11. Pet Command: Stay
    add_macro("stay", "pet stay", "Interface\\Icons\\Spell_Nature_TimeStop", "/petstay", nil, { 0.9, 0.9, 0.2 })

    -- 12. Pet Command: Passive
    add_macro("passive", "pet passive", "Interface\\Icons\\Ability_Defend", "/petpassive", nil, { 0.7, 0.7, 0.7 })
end

sfui.ring.register_provider("pet", {
    name   = "hunter pet",
    title  = "hunter pet",
    events = {
        "UNIT_PET_TRAINING_POINTS",
        "UNIT_PET_EXPERIENCE",
        "SPELLS_CHANGED",
        "PLAYER_ENTERING_WORLD",
        "UNIT_PET",
        "PET_BAR_UPDATE",
        "BAG_UPDATE_DELAYED",
    },
    build  = build_pet_ring,
})
