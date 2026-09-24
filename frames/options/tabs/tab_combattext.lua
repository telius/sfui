local addonName, addon = ...
sfui = sfui or {}
sfui.options = sfui.options or {}

local g = sfui.config
local common = sfui.common

sfui.options.RegisterTab({
    id = "combattext",
    name = "combat text",
    build = function(sct_panel, tab_button, options_frame)
        local create_cvar_checkbox = common.create_cvar_checkbox
        local white = sfui.config.colors.white

        local sct_header = sct_panel:CreateFontString(nil, "OVERLAY", g.font)
        sct_header:SetPoint("TOPLEFT", 15, -15)
        sct_header:SetTextColor(white[1], white[2], white[3])
        sct_header:SetText("blizzard combat text settings")

        local master_cb = create_cvar_checkbox(sct_panel, "enable floating combat text", "enableFloatingCombatText",
            "master toggle for blizzard's floating combat text.")
        master_cb:SetPoint("TOPLEFT", sct_header, "BOTTOMLEFT", 0, -10)

        local damage_cb = create_cvar_checkbox(sct_panel, "show damage", "floatingCombatTextCombatDamage",
            "toggles display of damage numbers over targets.")
        damage_cb:SetPoint("TOPLEFT", master_cb, "BOTTOMLEFT", 0, -5)

        local periodic_cb = create_cvar_checkbox(sct_panel, "show periodic damage (dots)",
            "floatingCombatTextCombatLogPeriodicSpells", "toggles display of periodic damage (dots) numbers.")
        periodic_cb:SetPoint("TOPLEFT", damage_cb, "BOTTOMLEFT", 0, -5)

        local healing_cb = create_cvar_checkbox(sct_panel, "show healing", "floatingCombatTextCombatHealing",
            "toggles display of healing numbers over targets.")
        healing_cb:SetPoint("TOPLEFT", periodic_cb, "BOTTOMLEFT", 0, -5)

        local pet_melee_cb = create_cvar_checkbox(sct_panel, "show pet melee damage", "floatingCombatTextPetMeleeDamage",
            "toggles display of pet melee damage numbers.")
        pet_melee_cb:SetPoint("TOPLEFT", healing_cb, "BOTTOMLEFT", 0, -5)

        local pet_spell_cb = create_cvar_checkbox(sct_panel, "show pet spell damage", "floatingCombatTextPetSpellDamage",
            "toggles display of pet spell damage numbers.")
        pet_spell_cb:SetPoint("TOPLEFT", pet_melee_cb, "BOTTOMLEFT", 0, -5)

        local avoid_cb = create_cvar_checkbox(sct_panel, "show dodge/parry/miss", "floatingCombatTextDodgeParryMiss_v2",
            "toggles display of avoidances.")
        avoid_cb:SetPoint("TOPLEFT", pet_spell_cb, "BOTTOMLEFT", 0, -5)

        local reduction_cb = create_cvar_checkbox(sct_panel, "show resist/block/absorb", "floatingCombatTextDamageReduction_v2",
            "toggles display of damage reduction.")
        reduction_cb:SetPoint("TOPLEFT", avoid_cb, "BOTTOMLEFT", 0, -5)

        local energy_cb = create_cvar_checkbox(sct_panel, "show energy gains/runes", "floatingCombatTextEnergyGains_v2",
            "toggles display of energy gains and runes.")
        energy_cb:SetPoint("TOPLEFT", reduction_cb, "BOTTOMLEFT", 0, -5)

        local auras_cb = create_cvar_checkbox(sct_panel, "show auras", "floatingCombatTextAuras_v2",
            "toggles display of aura gains/losses.")
        auras_cb:SetPoint("TOPLEFT", energy_cb, "BOTTOMLEFT", 0, -5)

        local state_cb = create_cvar_checkbox(sct_panel, "show combat state", "floatingCombatTextCombatState_v2",
            "toggles display of entering/leaving combat.")
        state_cb:SetPoint("TOPLEFT", auras_cb, "BOTTOMLEFT", 0, -5)
    end,
})
