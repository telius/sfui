local addonName, addon = ...
sfui = sfui or {}
sfui.options = sfui.options or {}

local g = sfui.config
local common = sfui.common
local _G = _G
local ipairs = _G.ipairs
local pairs = _G.pairs
local type = _G.type
local tostring = _G.tostring
local tonumber = _G.tonumber
local string_format = string.format

local refreshTabUI = nil

sfui.options.RegisterTab({
    id = "actionbars",
    name = "action bars",
    icon = "Interface\\Icons\\Spell_Shadow_ShadowBolt",
    resetDefaults = function()
        if SfuiDB and sfui.config and sfui.config.actionbars then
            local defaults = sfui.config.actionbars
            SfuiDB.actionbars = sfui.common.copy and sfui.common.copy(defaults) or defaults
            if sfui.actionbars and sfui.actionbars.bars then
                for i = 1, 10 do
                    sfui.actionbars.ApplyBarLayout(i)
                end
                if sfui.actionbars.ApplyPetBarLayout then
                    sfui.actionbars.ApplyPetBarLayout()
                end
                if sfui.actionbars.mouseover and sfui.actionbars.mouseover.UpdateAllBars then
                    sfui.actionbars.mouseover.UpdateAllBars(true)
                end
                if sfui.actionbars.SetButtonsLocked then
                    sfui.actionbars.SetButtonsLocked(defaults.lockButtons ~= false)
                end
            end
            if refreshTabUI then
                refreshTabUI()
            end
        end
    end,
    onShow = function()
        if refreshTabUI then
            refreshTabUI()
        end
    end,
    build = function(panel)
        local CreateFlatButton = common.create_flat_button
        local create_checkbox = common.create_checkbox
        local create_slider_input = common.create_slider_input
        local white = (sfui.config and sfui.config.colors and sfui.config.colors.white) or { 1, 1, 1 }

        local selectedBarKey = "bar1"
        local selectedBarIndex = 1
        local all_mouseover_cb
        local lock_cb

        local function get_mod_cfg()
            if not SfuiDB then return (sfui.config and sfui.config.actionbars) or {} end
            if not SfuiDB.actionbars then
                SfuiDB.actionbars = (sfui.common.copy and sfui.common.copy(sfui.config.actionbars)) or sfui.config.actionbars or {}
            end
            return SfuiDB.actionbars
        end

        local function get_bar_cfg(barKeyOrIdx)
            local mod = get_mod_cfg()
            local key = type(barKeyOrIdx) == "number" and ("bar" .. tostring(barKeyOrIdx)) or tostring(barKeyOrIdx)
            if not mod.bars then mod.bars = {} end
            if not mod.bars[key] then
                local def = sfui.config and sfui.config.actionbars and sfui.config.actionbars.bars and sfui.config.actionbars.bars[key]
                if def then
                    mod.bars[key] = (sfui.common.copy and sfui.common.copy(def)) or def
                elseif key == "pet" then
                    mod.bars[key] = {
                        enabled = true,
                        mouseover = false,
                        buttons = 10,
                        buttonsPerRow = 10,
                        buttonSize = 28,
                        spacing = 4,
                        point = "BOTTOM",
                        relPoint = "BOTTOM",
                        x = 0,
                        y = 168,
                    }
                else
                    mod.bars[key] = {
                        enabled = true,
                        mouseover = false,
                        buttons = 12,
                        buttonsPerRow = 3,
                        buttonSize = 28,
                        spacing = 4,
                        point = "BOTTOM",
                        relPoint = "BOTTOM",
                        x = 0,
                        y = 50,
                    }
                end
            end
            return mod.bars[key]
        end

        -- ─────────────────────────────────────────────────────────────────────
        --  Header & Overview
        -- ─────────────────────────────────────────────────────────────────────
        local header = panel:CreateFontString(nil, "OVERLAY", g.font_large or g.font)
        header:SetPoint("TOPLEFT", 15, -15)
        header:SetTextColor(white[1], white[2], white[3])
        header:SetText("action bars")

        local desc = panel:CreateFontString(nil, "OVERLAY", g.font)
        desc:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
        desc:SetPoint("RIGHT", -15, 0)
        desc:SetJustifyH("LEFT")
        desc:SetTextColor(0.8, 0.8, 0.8, 1)
        desc:SetText("modular 3x4 action bars 1-10 with stance paging, smooth mouseover fading, and dynamic proc updates.")

        -- ─────────────────────────────────────────────────────────────────────
        --  COLUMN 1: General & Visibility Settings (Left Column, x = 15, width = 250)
        -- ─────────────────────────────────────────────────────────────────────
        local col1_x = 15
        local col2_x = 295

        local sec1 = panel:CreateFontString(nil, "OVERLAY", g.font)
        sec1:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -14)
        sec1:SetTextColor(0.4, 0.9, 1.0)
        sec1:SetText("general settings")

        local enable_cb = create_checkbox(panel, "enable action bars", function()
            local cfg = get_mod_cfg()
            return cfg.enabled ~= false
        end, function(val)
            local cfg = get_mod_cfg()
            cfg.enabled = val
            if sfui.actionbars and sfui.actionbars.bars then
                for i = 1, 10 do
                    sfui.actionbars.ApplyBarLayout(i)
                end
            end
        end, "replaces blizzard action bars with modular sfui bars 1-10.")
        enable_cb:SetPoint("TOPLEFT", sec1, "BOTTOMLEFT", 0, -8)

        lock_cb = create_checkbox(panel, "lock actionbars", function()
            local cfg = get_mod_cfg()
            return cfg.lockButtons ~= false
        end, function(val)
            local cfg = get_mod_cfg()
            cfg.lockButtons = val
            if sfui.db and sfui.db.Set then
                sfui.db.Set("actionbars", "lockButtons", val)
            end
            if sfui.actionbars and sfui.actionbars.SetButtonsLocked then
                sfui.actionbars.SetButtonsLocked(val)
            end
        end, "prevents abilities from dragging unless holding shift, preventing accidental casts while moving abilities.")
        lock_cb:SetPoint("TOPLEFT", enable_cb, "BOTTOMLEFT", 0, -8)

        local mover_btn = CreateFlatButton(panel, "unlock / move bars", 125, 22, function(self)
            if sfui.actionbars and sfui.actionbars.ToggleMovers then
                sfui.actionbars.ToggleMovers()
                local unlocked = sfui.actionbars.moversUnlocked
                self:SetText(unlocked and "lock bars" or "unlock / move bars")
            end
        end)
        mover_btn:SetPoint("TOPLEFT", lock_cb, "BOTTOMLEFT", 0, -8)

        local keybind_btn = CreateFlatButton(panel, "quick keybind mode", 125, 22, function()
            if sfui.options and sfui.options.Toggle then
                sfui.options.Toggle()
            end
            if sfui.actionbars and sfui.actionbars.ActivateBindMode then
                sfui.actionbars.ActivateBindMode()
            end
        end)
        keybind_btn:SetPoint("LEFT", mover_btn, "RIGHT", 6, 0)

        local sec2 = panel:CreateFontString(nil, "OVERLAY", g.font)
        sec2:SetPoint("TOPLEFT", mover_btn, "BOTTOMLEFT", 0, -14)
        sec2:SetTextColor(0.4, 0.9, 1.0)
        sec2:SetText("visibility & mouseover")

        all_mouseover_cb = create_checkbox(panel, "enable mouseover on all bars", function()
            local cfg = get_mod_cfg()
            return cfg.allBarsMouseover == true
        end, function(val)
            local cfg = get_mod_cfg()
            cfg.allBarsMouseover = val
            if sfui.db and sfui.db.Set then
                sfui.db.Set("actionbars", "allBarsMouseover", val)
            end
            for i = 1, 10 do
                local b = get_bar_cfg("bar" .. i)
                if b then b.mouseover = val end
                local barObj = sfui.actionbars and sfui.actionbars.barsByKey and sfui.actionbars.barsByKey["bar" .. i]
                if barObj and barObj.barConfig then barObj.barConfig.mouseover = val end
            end
            local petCfg = get_bar_cfg("pet")
            if petCfg then petCfg.mouseover = val end
            local petBar = sfui.actionbars and sfui.actionbars.barsByKey and sfui.actionbars.barsByKey["pet"]
            if petBar and petBar.barConfig then petBar.barConfig.mouseover = val end

            if sfui.actionbars and sfui.actionbars.mouseover and sfui.actionbars.mouseover.UpdateAllBars then
                sfui.actionbars.mouseover.UpdateAllBars(true)
            end
            if update_pill_highlights then
                update_pill_highlights()
            end
        end, "fades out all action bars and the pet bar until hovered.")
        all_mouseover_cb:SetPoint("TOPLEFT", sec2, "BOTTOMLEFT", 0, -8)

        local resting_slider = create_slider_input(panel, "resting alpha (hidden state)", function()
            local cfg = get_mod_cfg()
            return cfg.restingAlpha or 0.0
        end, 0.0, 1.0, 0.05, function(val)
            local cfg = get_mod_cfg()
            cfg.restingAlpha = val
            if sfui.db and sfui.db.Set then
                sfui.db.Set("actionbars", "restingAlpha", val)
            end
            if sfui.actionbars and sfui.actionbars.mouseover and sfui.actionbars.mouseover.UpdateAllBars then
                sfui.actionbars.mouseover.UpdateAllBars()
            end
        end, "transparency level when mouse is not hovering (0 for completely hidden).", 250)
        resting_slider:SetPoint("TOPLEFT", all_mouseover_cb, "BOTTOMLEFT", 0, -8)

        local active_slider = create_slider_input(panel, "hover alpha (active state)", function()
            local cfg = get_mod_cfg()
            return cfg.activeAlpha or 1.0
        end, 0.1, 1.0, 0.05, function(val)
            local cfg = get_mod_cfg()
            cfg.activeAlpha = val
            if sfui.db and sfui.db.Set then
                sfui.db.Set("actionbars", "activeAlpha", val)
            end
            if sfui.actionbars and sfui.actionbars.mouseover and sfui.actionbars.mouseover.UpdateAllBars then
                sfui.actionbars.mouseover.UpdateAllBars()
            end
        end, "transparency level when hovering.", 250)
        active_slider:SetPoint("TOPLEFT", resting_slider, "BOTTOMLEFT", 0, -10)

        local sec3 = panel:CreateFontString(nil, "OVERLAY", g.font)
        sec3:SetPoint("TOPLEFT", active_slider, "BOTTOMLEFT", 0, -14)
        sec3:SetTextColor(0.4, 0.9, 1.0)
        sec3:SetText("button display")

        local grid_cb = create_checkbox(panel, "show empty button grid", function()
            local cfg = get_mod_cfg()
            return cfg.showGrid == true
        end, function(val)
            local cfg = get_mod_cfg()
            cfg.showGrid = val
            if sfui.actionbars and sfui.actionbars.bars then
                for i = 1, 10 do
                    sfui.actionbars.ApplyBarLayout(i)
                end
            end
        end, "always shows empty action button backdrops even without actions assigned.")
        grid_cb:SetPoint("TOPLEFT", sec3, "BOTTOMLEFT", 0, -8)

        local hotkeys_cb = create_checkbox(panel, "show keybind labels", function()
            local cfg = get_mod_cfg()
            return cfg.showHotkeys ~= false
        end, function(val)
            local cfg = get_mod_cfg()
            cfg.showHotkeys = val
            if sfui.actionbars and sfui.actionbars.bars then
                for i = 1, 10 do
                    sfui.actionbars.ApplyBarLayout(i)
                end
            end
            if sfui.actionbars and sfui.actionbars.ApplyPetBarLayout then
                sfui.actionbars.ApplyPetBarLayout()
            end
        end, "displays keybind abbreviations in the top-right corner of each button.")
        hotkeys_cb:SetPoint("TOPLEFT", grid_cb, "BOTTOMLEFT", 0, -8)

        local hotkey_size_slider = create_slider_input(panel, "hotkey font size (pixels)", function()
            local cfg = get_mod_cfg()
            return cfg.hotkeyFontSize or 10
        end, 8, 16, 1, function(val)
            local cfg = get_mod_cfg()
            cfg.hotkeyFontSize = val
            if sfui.actionbars and sfui.actionbars.bars then
                for i = 1, 10 do
                    sfui.actionbars.ApplyBarLayout(i)
                end
            end
            if sfui.actionbars and sfui.actionbars.ApplyPetBarLayout then
                sfui.actionbars.ApplyPetBarLayout()
            end
        end, "font size of hotkey shortcuts (default: 10).", 250)
        hotkey_size_slider:SetPoint("TOPLEFT", hotkeys_cb, "BOTTOMLEFT", 0, -8)

        local counts_cb = create_checkbox(panel, "show stack & charge counts", function()
            local cfg = get_mod_cfg()
            return cfg.showCounts ~= false
        end, function(val)
            local cfg = get_mod_cfg()
            cfg.showCounts = val
            if sfui.actionbars and sfui.actionbars.bars then
                for i = 1, 10 do
                    sfui.actionbars.ApplyBarLayout(i)
                end
            end
            if sfui.actionbars and sfui.actionbars.ApplyPetBarLayout then
                sfui.actionbars.ApplyPetBarLayout()
            end
        end, "displays consumable item stacks and spell charges in the bottom-right corner.")
        counts_cb:SetPoint("TOPLEFT", hotkey_size_slider, "BOTTOMLEFT", 0, -8)

        local macros_cb = create_checkbox(panel, "show macro names", function()
            local cfg = get_mod_cfg()
            return cfg.showMacroNames == true
        end, function(val)
            local cfg = get_mod_cfg()
            cfg.showMacroNames = val
            if sfui.actionbars and sfui.actionbars.bars then
                for i = 1, 10 do
                    sfui.actionbars.ApplyBarLayout(i)
                end
            end
        end, "displays macro title text at the bottom of the button.")
        macros_cb:SetPoint("TOPLEFT", counts_cb, "BOTTOMLEFT", 0, -8)

        local range_cb = create_checkbox(panel, "tint red when out of range", function()
            local cfg = get_mod_cfg()
            return cfg.outOfRangeColoring ~= "none"
        end, function(val)
            local cfg = get_mod_cfg()
            cfg.outOfRangeColoring = val and "button" or "none"
            if sfui.actionbars and sfui.actionbars.bars then
                for i = 1, 10 do
                    sfui.actionbars.ApplyBarLayout(i)
                end
            end
        end, "tints the button red when your target is out of range.")
        range_cb:SetPoint("TOPLEFT", macros_cb, "BOTTOMLEFT", 0, -8)

        -- ─────────────────────────────────────────────────────────────────────
        --  COLUMN 2: Bar Layout Controls (Bars 1-6) (Right Column, x = 295, width = 250)
        -- ─────────────────────────────────────────────────────────────────────
        local sec_bar = panel:CreateFontString(nil, "OVERLAY", g.font)
        sec_bar:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", col2_x - col1_x, -14)
        sec_bar:SetTextColor(0.4, 0.9, 1.0)
        sec_bar:SetText("bar layout (bars 1-10 & pet bar)")

        -- Bar Selector Pills
        local pillButtons = {}
        for b = 1, 10 do
            local pill = CreateFlatButton(panel, string_format("bar %d", b), 44, 20)
            if b == 1 then
                pill:SetPoint("TOPLEFT", sec_bar, "BOTTOMLEFT", 0, -8)
            elseif b == 6 then
                pill:SetPoint("TOPLEFT", pillButtons[1], "BOTTOMLEFT", 0, -4)
            else
                pill:SetPoint("LEFT", pillButtons[b - 1], "RIGHT", 4, 0)
            end
            pillButtons[b] = pill
        end

        local petPill = CreateFlatButton(panel, "pet bar", 80, 20)
        petPill:SetPoint("TOPLEFT", pillButtons[6], "BOTTOMLEFT", 0, -6)

        local barStatusText = panel:CreateFontString(nil, "OVERLAY", g.font)
        barStatusText:SetPoint("TOPLEFT", petPill, "BOTTOMLEFT", 0, -8)
        barStatusText:SetTextColor(1, 0.85, 0.2, 1)

        -- Controls forward declaration for right column sync
        local bar_enabled_cb, bar_mouseover_cb
        local grid_preset_btn
        local buttons_slider, per_row_slider, size_slider, spacing_slider

        local function apply_selected_bar_layout()
            if selectedBarKey == "pet" then
                if sfui.actionbars and sfui.actionbars.ApplyPetBarLayout then
                    sfui.actionbars.ApplyPetBarLayout()
                end
            else
                if sfui.actionbars and sfui.actionbars.ApplyBarLayout and selectedBarIndex then
                    sfui.actionbars.ApplyBarLayout(selectedBarIndex)
                end
            end
        end

        local function update_pill_highlights()
            for b = 1, 10 do
                local pill = pillButtons[b]
                if selectedBarKey == ("bar" .. b) then
                    pill:GetFontString():SetTextColor(0, 1, 1, 1)
                else
                    pill:GetFontString():SetTextColor(0.7, 0.7, 0.7, 1)
                end
            end
            if selectedBarKey == "pet" then
                petPill:GetFontString():SetTextColor(0, 1, 1, 1)
                barStatusText:SetText("editing: pet bar")
                if grid_preset_btn and grid_preset_btn.SetText then
                    grid_preset_btn:SetText("preset: 1x10 row")
                end
                if buttons_slider and buttons_slider.slider then
                    buttons_slider.slider:SetMinMaxValues(1, 10)
                end
                if per_row_slider and per_row_slider.slider then
                    per_row_slider.slider:SetMinMaxValues(1, 10)
                end
            else
                petPill:GetFontString():SetTextColor(0.7, 0.7, 0.7, 1)
                barStatusText:SetText(string_format("editing: bar %d", selectedBarIndex or 1))
                if grid_preset_btn and grid_preset_btn.SetText then
                    grid_preset_btn:SetText("preset: 3x4 grid")
                end
                if buttons_slider and buttons_slider.slider then
                    buttons_slider.slider:SetMinMaxValues(1, 12)
                end
                if per_row_slider and per_row_slider.slider then
                    per_row_slider.slider:SetMinMaxValues(1, 12)
                end
            end

            local bCfg = get_bar_cfg(selectedBarKey)
            local modCfg = get_mod_cfg()
            if bar_enabled_cb then bar_enabled_cb:SetChecked(bCfg.enabled ~= false) end
            if bar_mouseover_cb then
                local isMo = (modCfg.allBarsMouseover == true) or (bCfg.mouseover == true)
                bar_mouseover_cb:SetChecked(isMo)
            end
            if buttons_slider and buttons_slider.slider then
                buttons_slider.slider:SetValue(bCfg.buttons or (selectedBarKey == "pet" and 10 or 12))
            end
            if per_row_slider and per_row_slider.slider then
                per_row_slider.slider:SetValue(bCfg.buttonsPerRow or (selectedBarKey == "pet" and 10 or 3))
            end
            if size_slider and size_slider.slider then
                size_slider.slider:SetValue(bCfg.buttonSize or 28)
            end
            if spacing_slider and spacing_slider.slider then
                spacing_slider.slider:SetValue(bCfg.spacing or 4)
            end
        end

        for b = 1, 10 do
            pillButtons[b]:SetScript("OnClick", function()
                selectedBarIndex = b
                selectedBarKey = "bar" .. b
                update_pill_highlights()
            end)
        end

        petPill:SetScript("OnClick", function()
            selectedBarIndex = nil
            selectedBarKey = "pet"
            update_pill_highlights()
        end)

        bar_enabled_cb = create_checkbox(panel, "enable this bar", function()
            local bCfg = get_bar_cfg(selectedBarKey)
            return bCfg.enabled ~= false
        end, function(val)
            local bCfg = get_bar_cfg(selectedBarKey)
            bCfg.enabled = val
            if SfuiDB then
                SfuiDB["_" .. selectedBarKey .. "Customized"] = true
            end
            apply_selected_bar_layout()
        end, "shows or hides this action bar.")
        bar_enabled_cb:SetPoint("TOPLEFT", barStatusText, "BOTTOMLEFT", 0, -8)

        bar_mouseover_cb = create_checkbox(panel, "fade out on mouseover", function()
            local bCfg = get_bar_cfg(selectedBarKey)
            local modCfg = get_mod_cfg()
            return (modCfg.allBarsMouseover == true) or (bCfg.mouseover == true)
        end, function(val)
            local bCfg = get_bar_cfg(selectedBarKey)
            local modCfg = get_mod_cfg()
            bCfg.mouseover = val
            local selectedBar = sfui.actionbars and sfui.actionbars.barsByKey and sfui.actionbars.barsByKey[selectedBarKey]
            if selectedBar and selectedBar.barConfig then
                selectedBar.barConfig.mouseover = val
            end
            if SfuiDB then
                SfuiDB["_" .. selectedBarKey .. "MouseoverCustomized"] = true
            end
            if not val and modCfg.allBarsMouseover == true then
                modCfg.allBarsMouseover = false
                if sfui.db and sfui.db.Set then
                    sfui.db.Set("actionbars", "allBarsMouseover", false)
                end
                for i = 1, 10 do
                    local k = "bar" .. i
                    if k ~= selectedBarKey then
                        local otherCfg = get_bar_cfg(k)
                        if otherCfg then otherCfg.mouseover = true end
                        local otherBar = sfui.actionbars and sfui.actionbars.barsByKey and sfui.actionbars.barsByKey[k]
                        if otherBar and otherBar.barConfig then otherBar.barConfig.mouseover = true end
                    end
                end
                if selectedBarKey ~= "pet" then
                    local petCfg = get_bar_cfg("pet")
                    if petCfg then petCfg.mouseover = true end
                    local petBar = sfui.actionbars and sfui.actionbars.barsByKey and sfui.actionbars.barsByKey["pet"]
                    if petBar and petBar.barConfig then petBar.barConfig.mouseover = true end
                end
                if all_mouseover_cb and all_mouseover_cb.SetChecked then
                    all_mouseover_cb:SetChecked(false)
                end
            end
            if sfui.actionbars and sfui.actionbars.mouseover and sfui.actionbars.mouseover.UpdateAllBars then
                sfui.actionbars.mouseover.UpdateAllBars(true)
            end
            update_pill_highlights()
        end, "keeps this bar hidden until hovered (automatically active when 'enable mouseover on all bars' is checked).")
        bar_mouseover_cb:SetPoint("TOPLEFT", bar_enabled_cb, "BOTTOMLEFT", 0, -6)

        grid_preset_btn = CreateFlatButton(panel, "preset: 3x4 grid", 250, 22, function()
            if selectedBarKey == "pet" then
                local bCfg = get_bar_cfg("pet")
                bCfg.buttons = 10
                bCfg.buttonsPerRow = 10
                bCfg.buttonSize = 28
                bCfg.spacing = 4
                if sfui.actionbars and sfui.actionbars.ApplyPetBarLayout then
                    sfui.actionbars.ApplyPetBarLayout()
                end
                update_pill_highlights()
                if sfui.common and sfui.common.print then
                    sfui.common.print("pet bar reset to 1x10 row (10 buttons, 28px).")
                end
            else
                if sfui.actionbars and sfui.actionbars.Apply3x4Preset and selectedBarIndex then
                    sfui.actionbars.Apply3x4Preset(selectedBarIndex)
                    update_pill_highlights()
                    if sfui.common and sfui.common.print then
                        sfui.common.print(string_format("bar %d reset to 3x4 grid (12 buttons, 3 per row, 28px).", selectedBarIndex))
                    end
                end
            end
        end)
        grid_preset_btn:SetPoint("TOPLEFT", bar_mouseover_cb, "BOTTOMLEFT", 0, -10)

        buttons_slider = create_slider_input(panel, "number of buttons (1-12)", function()
            local bCfg = get_bar_cfg(selectedBarKey)
            return bCfg.buttons or (selectedBarKey == "pet" and 10 or 12)
        end, 1, 12, 1, function(val)
            local bCfg = get_bar_cfg(selectedBarKey)
            bCfg.buttons = val
            apply_selected_bar_layout()
        end, "how many action buttons to show on this bar.", 250)
        buttons_slider:SetPoint("TOPLEFT", grid_preset_btn, "BOTTOMLEFT", 0, -10)

        per_row_slider = create_slider_input(panel, "buttons per row (cols: 3 for 3x4)", function()
            local bCfg = get_bar_cfg(selectedBarKey)
            return bCfg.buttonsPerRow or (selectedBarKey == "pet" and 10 or 3)
        end, 1, 12, 1, function(val)
            local bCfg = get_bar_cfg(selectedBarKey)
            bCfg.buttonsPerRow = val
            apply_selected_bar_layout()
        end, "how many buttons wide each row is (set 3 for a 3x4 grid).", 250)
        per_row_slider:SetPoint("TOPLEFT", buttons_slider, "BOTTOMLEFT", 0, -10)

        size_slider = create_slider_input(panel, "button size (pixels)", function()
            local bCfg = get_bar_cfg(selectedBarKey)
            return bCfg.buttonSize or 28
        end, 20, 60, 1, function(val)
            local bCfg = get_bar_cfg(selectedBarKey)
            bCfg.buttonSize = val
            apply_selected_bar_layout()
        end, "width and height of each action button.", 250)
        size_slider:SetPoint("TOPLEFT", per_row_slider, "BOTTOMLEFT", 0, -10)

        spacing_slider = create_slider_input(panel, "button spacing (pixels)", function()
            local bCfg = get_bar_cfg(selectedBarKey)
            return bCfg.spacing or 4
        end, 0, 16, 1, function(val)
            local bCfg = get_bar_cfg(selectedBarKey)
            bCfg.spacing = val
            apply_selected_bar_layout()
        end, "gap between adjacent action buttons.", 250)
        spacing_slider:SetPoint("TOPLEFT", size_slider, "BOTTOMLEFT", 0, -10)

        local reset_pos_btn = CreateFlatButton(panel, "reset bar position", 250, 22, function()
            if sfui.actionbars and sfui.actionbars.ResetPosition then
                if selectedBarKey == "pet" then
                    sfui.actionbars.ResetPosition("pet")
                    if sfui.common and sfui.common.print then
                        sfui.common.print("pet bar position reset to default anchor.")
                    end
                elseif selectedBarIndex then
                    sfui.actionbars.ResetPosition(selectedBarIndex)
                    if sfui.common and sfui.common.print then
                        sfui.common.print(string_format("bar %d position reset to default anchor.", selectedBarIndex))
                    end
                end
            end
        end)
        reset_pos_btn:SetPoint("TOPLEFT", spacing_slider, "BOTTOMLEFT", 0, -10)

        refreshTabUI = function()
            if enable_cb and enable_cb.SetChecked then
                local cfg = get_mod_cfg()
                enable_cb:SetChecked(cfg.enabled ~= false)
            end
            if lock_cb and lock_cb.SetChecked then
                local cfg = get_mod_cfg()
                lock_cb:SetChecked(cfg.lockButtons ~= false)
            end
            if all_mouseover_cb and all_mouseover_cb.SetChecked then
                local cfg = get_mod_cfg()
                all_mouseover_cb:SetChecked(cfg.allBarsMouseover == true)
            end
            if mover_btn and mover_btn.SetText then
                local unlocked = sfui.actionbars and sfui.actionbars.moversUnlocked
                mover_btn:SetText(unlocked and "lock bars" or "unlock / move bars")
            end
            update_pill_highlights()
        end

        update_pill_highlights()
    end,
})
