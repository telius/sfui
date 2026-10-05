sfui = sfui or {}
sfui.options = sfui.options or {}

local g = sfui.config
local common = sfui.common
local _G = _G
local tonumber, tostring, pairs, ipairs = _G.tonumber, _G.tostring, _G.pairs, _G.ipairs
local GetCVar = _G.GetCVar
local SetCVar = _G.SetCVar
local C_CVar = _G.C_CVar

local defaultCVars = {
    enableFloatingCombatText = "1",
    floatingCombatTextCombatDamage = "1",
    floatingCombatTextCombatLogPeriodicSpells = "1",
    floatingCombatTextCombatHealing = "1",
    floatingCombatTextPetMeleeDamage = "1",
    floatingCombatTextPetSpellDamage = "1",
    floatingCombatTextDodgeParryMiss_v2 = "1",
    floatingCombatTextDamageReduction_v2 = "0",
    floatingCombatTextEnergyGains_v2 = "0",
    floatingCombatTextAuras_v2 = "1",
    floatingCombatTextCombatState_v2 = "0",
    floatingCombatTextReactives_v2 = "1",
    floatingCombatTextLowManaHealth_v2 = "1",
    floatingCombatTextRepChanges_v2 = "0",
    floatingCombatTextHonorGains_v2 = "0",
    floatingCombatTextComboPoints_v2 = "0",
    floatingCombatTextFloatMode_v2 = "1",
    WorldTextScale = "1",
}

local function set_cvar(cvar, val)
    if sfui.common and sfui.common.set_cvar then
        sfui.common.set_cvar(cvar, tostring(val))
    elseif (not InCombatLockdown or not InCombatLockdown()) then
        local set = (C_CVar and C_CVar.SetCVar) or SetCVar
        if set then set(cvar, tostring(val)) end
    end
    if SfuiDB then
        if val == "1" or val == "0" then
            SfuiDB[cvar] = (val == "1")
        else
            SfuiDB[cvar] = val
        end
    end
end

local function get_cvar(cvar)
    if sfui.common and sfui.common.get_cvar then
        return sfui.common.get_cvar(cvar)
    end
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    return get and get(cvar)
end

-- Refresh handle populated during build
local refreshTabUI = nil

sfui.options.RegisterTab({
    id = "combattext",
    name = "combat text",
    resetDefaults = function()
        for cvar, val in pairs(defaultCVars) do
            set_cvar(cvar, val)
        end
        if refreshTabUI then
            refreshTabUI()
        end
    end,
    onShow = function()
        if refreshTabUI then
            refreshTabUI()
        end
    end,
    build = function(sct_panel, _tab_button, _options_frame)
        local create_checkbox = common.create_checkbox
        local create_cvar_checkbox = common.create_cvar_checkbox
        local create_slider_input = common.create_slider_input
        local create_dropdown = common.create_dropdown
        local white = sfui.config.colors.white

        local COL_OFFSET_X = 265
        local SECTION_GAP = 22
        local ITEM_GAP = 6

        local childControls = {}
        local allCheckboxes = {}

        local function registerChild(ctrl)
            childControls[#childControls + 1] = ctrl
            return ctrl
        end

        local function registerCheckbox(cb)
            allCheckboxes[#allCheckboxes + 1] = cb
            return cb
        end

        -- Helper to build standard section headers
        local function createSectionHeader(panel, text, anchor, relPoint, x, y)
            local header = panel:CreateFontString(nil, "OVERLAY", g.font)
            header:SetPoint(relPoint or "TOPLEFT", anchor, x or 0, y or 0)
            header:SetTextColor(white[1], white[2], white[3])
            header:SetText(text)
            return header
        end

        -- ── Column 1: Damage, Healing & Pets ─────────────────────────────────
        local dmg_header = createSectionHeader(sct_panel, "damage, healing & pets", sct_panel, "TOPLEFT", 15, -15)

        -- Master toggle
        local master_cb
        master_cb = create_checkbox(sct_panel, "enable floating combat text", function()
            return get_cvar("enableFloatingCombatText") == "1"
        end, function(checked)
            set_cvar("enableFloatingCombatText", checked and "1" or "0")
            if refreshTabUI then refreshTabUI() end
        end, "master toggle for blizzard's floating combat text engine.")
        master_cb:SetPoint("TOPLEFT", dmg_header, "BOTTOMLEFT", 0, -10)
        registerCheckbox(master_cb)

        local damage_cb = registerChild(registerCheckbox(create_cvar_checkbox(sct_panel, "show damage",
            "floatingCombatTextCombatDamage", "toggles display of damage numbers over targets.")))
        damage_cb:SetPoint("TOPLEFT", master_cb, "BOTTOMLEFT", 0, -ITEM_GAP)

        local periodic_cb = registerChild(registerCheckbox(create_cvar_checkbox(sct_panel, "show periodic damage (dots)",
            "floatingCombatTextCombatLogPeriodicSpells", "toggles display of periodic damage (dots) numbers.")))
        periodic_cb:SetPoint("TOPLEFT", damage_cb, "BOTTOMLEFT", 0, -ITEM_GAP)

        local healing_cb = registerChild(registerCheckbox(create_cvar_checkbox(sct_panel, "show healing",
            "floatingCombatTextCombatHealing", "toggles display of healing numbers over targets.")))
        healing_cb:SetPoint("TOPLEFT", periodic_cb, "BOTTOMLEFT", 0, -ITEM_GAP)

        local pet_melee_cb = registerChild(registerCheckbox(create_cvar_checkbox(sct_panel, "show pet melee damage",
            "floatingCombatTextPetMeleeDamage", "toggles display of pet melee damage numbers.")))
        pet_melee_cb:SetPoint("TOPLEFT", healing_cb, "BOTTOMLEFT", 0, -ITEM_GAP)

        local pet_spell_cb = registerChild(registerCheckbox(create_cvar_checkbox(sct_panel, "show pet spell damage",
            "floatingCombatTextPetSpellDamage", "toggles display of pet spell damage numbers.")))
        pet_spell_cb:SetPoint("TOPLEFT", pet_melee_cb, "BOTTOMLEFT", 0, -ITEM_GAP)

        -- ── Column 1 (Bottom): Display & Animation ───────────────────────────
        local display_header = createSectionHeader(sct_panel, "display & animation", pet_spell_cb, "BOTTOMLEFT", 0, -SECTION_GAP)

        -- Float Mode Dropdown
        local float_label = sct_panel:CreateFontString(nil, "OVERLAY", g.font)
        float_label:SetPoint("TOPLEFT", display_header, "BOTTOMLEFT", 0, -10)
        float_label:SetTextColor(0.8, 0.8, 0.8)
        float_label:SetText("scroll style")

        local floatModeOptions = {
            { text = "scroll up", value = "1" },
            { text = "scroll down", value = "2" },
            { text = "arc / fountain", value = "3" },
        }

        local curFloatMode = get_cvar("floatingCombatTextFloatMode_v2") or "1"
        local float_dd = create_dropdown(sct_panel, 180, floatModeOptions, function(val)
            set_cvar("floatingCombatTextFloatMode_v2", val)
        end, curFloatMode, nil, 180)
        float_dd:SetPoint("TOPLEFT", float_label, "BOTTOMLEFT", 0, -4)
        float_dd.tooltip = "direction and trajectory of floating combat text numbers."
        registerChild(float_dd)

        -- World Text Scale Slider
        local scale_slider = create_slider_input(sct_panel, "world combat text scale", function()
            return tonumber(get_cvar("WorldTextScale")) or 1.0
        end, 0.5, 2.5, 0.1, function(val)
            set_cvar("WorldTextScale", string.format("%.1f", val))
        end, "adjusts the font size and scale of combat text numbers floating in the 3d world.")
        scale_slider:SetPoint("TOPLEFT", float_dd, "BOTTOMLEFT", 0, -14)
        registerChild(scale_slider)

        -- ── Column 2: Combat Events & Auras ──────────────────────────────────
        local events_header = createSectionHeader(sct_panel, "combat events & auras", dmg_header, "LEFT", COL_OFFSET_X, 0)

        local avoid_cb = registerChild(registerCheckbox(create_cvar_checkbox(sct_panel, "show dodge/parry/miss",
            "floatingCombatTextDodgeParryMiss_v2", "toggles display of avoidances.")))
        avoid_cb:SetPoint("TOPLEFT", events_header, "BOTTOMLEFT", 0, -10)

        local reduction_cb = registerChild(registerCheckbox(create_cvar_checkbox(sct_panel, "show resist/block/absorb",
            "floatingCombatTextDamageReduction_v2", "toggles display of damage reduction.")))
        reduction_cb:SetPoint("TOPLEFT", avoid_cb, "BOTTOMLEFT", 0, -ITEM_GAP)

        local energy_cb = registerChild(registerCheckbox(create_cvar_checkbox(sct_panel, "show energy gains/runes",
            "floatingCombatTextEnergyGains_v2", "toggles display of energy gains and runes.")))
        energy_cb:SetPoint("TOPLEFT", reduction_cb, "BOTTOMLEFT", 0, -ITEM_GAP)

        local auras_cb = registerChild(registerCheckbox(create_cvar_checkbox(sct_panel, "show auras",
            "floatingCombatTextAuras_v2", "toggles display of aura gains/losses.")))
        auras_cb:SetPoint("TOPLEFT", energy_cb, "BOTTOMLEFT", 0, -ITEM_GAP)

        local reactives_cb = registerChild(registerCheckbox(create_cvar_checkbox(sct_panel, "show spell procs / reactive",
            "floatingCombatTextReactives_v2", "toggles display of spell procs and reactive ability alerts.")))
        reactives_cb:SetPoint("TOPLEFT", auras_cb, "BOTTOMLEFT", 0, -ITEM_GAP)

        local low_cb = registerChild(registerCheckbox(create_cvar_checkbox(sct_panel, "show low health/mana alerts",
            "floatingCombatTextLowManaHealth_v2", "toggles alerts when your health or mana falls to critical levels.")))
        low_cb:SetPoint("TOPLEFT", reactives_cb, "BOTTOMLEFT", 0, -ITEM_GAP)

        local state_cb = registerChild(registerCheckbox(create_cvar_checkbox(sct_panel, "show combat state",
            "floatingCombatTextCombatState_v2", "toggles display of entering/leaving combat notifications.")))
        state_cb:SetPoint("TOPLEFT", low_cb, "BOTTOMLEFT", 0, -ITEM_GAP)

        local combo_cb = registerChild(registerCheckbox(create_cvar_checkbox(sct_panel, "show combo points",
            "floatingCombatTextComboPoints_v2", "toggles display of combo point gains.")))
        combo_cb:SetPoint("TOPLEFT", state_cb, "BOTTOMLEFT", 0, -ITEM_GAP)

        local rep_cb = registerChild(registerCheckbox(create_cvar_checkbox(sct_panel, "show reputation changes",
            "floatingCombatTextRepChanges_v2", "toggles display of reputation gains and losses.")))
        rep_cb:SetPoint("TOPLEFT", combo_cb, "BOTTOMLEFT", 0, -ITEM_GAP)

        local honor_cb = registerChild(registerCheckbox(create_cvar_checkbox(sct_panel, "show honor gains",
            "floatingCombatTextHonorGains_v2", "toggles display of honor earned in pvp.")))
        honor_cb:SetPoint("TOPLEFT", rep_cb, "BOTTOMLEFT", 0, -ITEM_GAP)

        -- ── Master Toggle State Synchronization ──────────────────────────────
        local function UpdateChildStates()
            local masterEnabled = (get_cvar("enableFloatingCombatText") == "1")
            local alpha = masterEnabled and 1.0 or 0.35

            float_label:SetAlpha(alpha)

            for _, ctrl in ipairs(childControls) do
                ctrl:SetAlpha(alpha)
                if ctrl.EnableMouse then
                    ctrl:EnableMouse(masterEnabled)
                end
                if ctrl.slider and ctrl.slider.EnableMouse then
                    ctrl.slider:EnableMouse(masterEnabled)
                end
                if ctrl.editbox and ctrl.editbox.EnableMouse then
                    ctrl.editbox:EnableMouse(masterEnabled)
                end
            end
        end

        -- Unified UI Refresh Handler
        refreshTabUI = function()
            -- Sync all checkboxes with current CVars
            for _, cb in ipairs(allCheckboxes) do
                local onShow = cb:GetScript("OnShow")
                if onShow then
                    pcall(onShow, cb)
                end
            end

            -- Sync Dropdown
            local mode = get_cvar("floatingCombatTextFloatMode_v2") or "1"
            if float_dd.SetSelectedValue then
                float_dd:SetSelectedValue(mode)
            end

            -- Sync Scale Slider
            local scaleVal = tonumber(get_cvar("WorldTextScale")) or 1.0
            if scale_slider.slider then
                scale_slider.slider:SetValue(scaleVal)
            end
            if scale_slider.editbox then
                scale_slider.editbox:SetText(string.format("%.1f", scaleVal))
            end

            -- Apply master dependency dimming
            UpdateChildStates()
        end

        -- Initial sync
        refreshTabUI()
    end,
})

