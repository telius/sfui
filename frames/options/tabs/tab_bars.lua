local addonName, addon = ...
sfui = sfui or {}
sfui.options = sfui.options or {}

local g = sfui.config
local common = sfui.common

local CreateFrame = _G.CreateFrame
local ipairs = _G.ipairs

sfui.options.RegisterTab({
    id = "bars",
    name = "bars",
    build = function(bars_panel, tab_button, options_frame)
        local CreateFlatButton = common.create_flat_button
        local create_checkbox = common.create_checkbox
        local create_slider_input = common.create_slider_input
        local white = sfui.config.colors.white

        local bars_header = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
        bars_header:SetPoint("TOPLEFT", 15, -15)
        bars_header:SetTextColor(white[1], white[2], white[3])
        bars_header:SetText("bar settings")

        -- Bar Style Dropdown (Camelot & Modern)
        local barStyleOptions = {
            { text = "dark inset (castbar match)", value = "inset" },
            { text = "blizzard hud bezel",          value = "bezel" },
            { text = "dark bronze sculpted",        value = "darkbronze" },
            { text = "castbar replica (1:1 black)", value = "castbar" },
            { text = "chiseled heavy brackets",     value = "heavy" },
            { text = "minimalist thin (1px)",       value = "thin" },
            { text = "recessed amber glow",         value = "glow" },
        }

        local curBarStyle = (sfui.theme and sfui.theme.GetBarStyle and sfui.theme.GetBarStyle()) or "castbar"

        local style_label = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
        style_label:SetPoint("TOPLEFT", bars_header, "BOTTOMLEFT", 0, -14)
        style_label:SetTextColor(white[1], white[2], white[3])
        style_label:SetText("theme bar style:")

        local updatePreview

        local style_dropdown = common.create_dropdown(bars_panel, 220, barStyleOptions, function(val)
            if sfui.theme and sfui.theme.SetBarStyle then
                sfui.theme.SetBarStyle(val)
            end
            if updatePreview then
                updatePreview()
            end
        end, curBarStyle, nil, 220)
        style_dropdown:SetPoint("TOPLEFT", style_label, "BOTTOMLEFT", 0, -6)
        style_dropdown.tooltip = "selects the border and container framing style for health, power, and swing bars."

        -- Live Preview Bar placed right next to the style dropdown
        local preview_label = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
        preview_label:SetPoint("BOTTOMLEFT", style_dropdown, "TOPRIGHT", 25, 6)
        preview_label:SetTextColor(0.85, 0.75, 0.55)
        preview_label:SetText("live example:")

        local previewBackdrop = CreateFrame("Frame", nil, bars_panel, "BackdropTemplate")
        previewBackdrop:SetSize(210, 20)
        previewBackdrop:SetPoint("LEFT", style_dropdown, "RIGHT", 25, 0)
        previewBackdrop:EnableMouse(true)

        local previewBar = CreateFrame("StatusBar", nil, previewBackdrop)
        previewBar:SetPoint("TOPLEFT", previewBackdrop, "TOPLEFT", 1, -1)
        previewBar:SetPoint("BOTTOMRIGHT", previewBackdrop, "BOTTOMRIGHT", -1, 1)
        previewBar:SetMinMaxValues(0, 100)
        previewBar:SetValue(68)
        previewBar.backdrop = previewBackdrop

        local previewTextLeft = previewBar:CreateFontString(nil, "OVERLAY", g.font)
        previewTextLeft:SetPoint("LEFT", previewBar, "LEFT", 8, 0)
        previewTextLeft:SetTextColor(1, 1, 1, 0.95)
        previewTextLeft:SetShadowOffset(1, -1)
        previewTextLeft:SetShadowColor(0, 0, 0, 1)
        previewTextLeft:SetText("player health")

        local previewTextRight = previewBar:CreateFontString(nil, "OVERLAY", g.font)
        previewTextRight:SetPoint("RIGHT", previewBar, "RIGHT", -8, 0)
        previewTextRight:SetTextColor(1, 0.82, 0.20, 0.95)
        previewTextRight:SetShadowOffset(1, -1)
        previewTextRight:SetShadowColor(0, 0, 0, 1)
        previewTextRight:SetText("68%")

        updatePreview = function()
            local tex = sfui.widgets.get_bar_texture()
            if tex then previewBar:SetStatusBarTexture(tex) end
            local col = (sfui.common and sfui.common.get_class_or_spec_color and sfui.common.get_class_or_spec_color()) or { 0.85, 0.40, 0.15 }
            previewBar:SetStatusBarColor(col[1], col[2], col[3], 1)
            if sfui.theme and sfui.theme.ApplyStatusBarStyle then
                sfui.theme.ApplyStatusBarStyle(previewBar, "health")
            end
        end
        updatePreview()

        if sfui.theme and sfui.theme.RegisterBar then
            sfui.theme.RegisterBar(previewBar, "health")
        end

        previewBackdrop:SetScript("OnMouseDown", function()
            local styles = { "inset", "bezel", "darkbronze", "castbar", "heavy", "thin", "glow" }
            local cur = (sfui.theme and sfui.theme.GetBarStyle and sfui.theme.GetBarStyle()) or "castbar"
            local nextStyle = "castbar"
            for i, st in ipairs(styles) do
                if st == cur then
                    nextStyle = styles[(i % #styles) + 1]
                    break
                end
            end
            if sfui.theme and sfui.theme.SetBarStyle then
                sfui.theme.SetBarStyle(nextStyle)
            end
            if style_dropdown and style_dropdown.SetSelectedValue then
                style_dropdown:SetSelectedValue(nextStyle)
            end
            updatePreview()
        end)
        previewBackdrop:SetScript("OnEnter", function(self)
            local tip = sfui.common.get_tooltip()
            if tip then
                tip:SetOwner(self, "ANCHOR_TOP")
                tip:SetText("click to cycle through bar styles", 1, 1, 1)
                tip:Show()
            end
        end)
        previewBackdrop:SetScript("OnLeave", function()
            local tip = sfui.common.get_tooltip()
            if tip then tip:Hide() end
        end)

        bars_panel:HookScript("OnShow", function()
            local activeStyle = (sfui.theme and sfui.theme.GetBarStyle and sfui.theme.GetBarStyle()) or "castbar"
            if style_dropdown and style_dropdown.SetSelectedValue then
                style_dropdown:SetSelectedValue(activeStyle)
            end
            updatePreview()
        end)

        -- Bar Toggles
        local toggles_header = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
        toggles_header:SetPoint("TOPLEFT", style_dropdown, "BOTTOMLEFT", 0, -22)
        toggles_header:SetTextColor(white[1], white[2], white[3])
        toggles_header:SetText("bar visibility")

        local health_bar_cb = create_checkbox(bars_panel, "enable health bar", "enableHealthBar", function(checked)
            sfui.bars:on_state_changed()
        end, "toggles the health bar.")
        health_bar_cb:SetPoint("TOPLEFT", toggles_header, "BOTTOMLEFT", 0, -10)

        local power_bar_cb = create_checkbox(bars_panel, "enable power bar", "enablePowerBar", function(checked)
            sfui.bars:on_state_changed()
        end, "toggles the primary power bar.")
        power_bar_cb:SetPoint("TOPLEFT", health_bar_cb, "BOTTOMLEFT", 0, -10)

        local secondary_power_cb = create_checkbox(bars_panel, "enable secondary power bar", "enableSecondaryPowerBar",
            function(checked)
                sfui.bars:on_state_changed()
            end, "toggles the secondary power bar (e.g., chi, holy power).")
        secondary_power_cb:SetPoint("TOPLEFT", power_bar_cb, "BOTTOMLEFT", 0, -10)

        local vigor_bar_cb = create_checkbox(bars_panel, "enable vigor bar", "enableVigorBar", function(checked)
            sfui.bars:on_state_changed()
        end, "toggles the vigor bar (skyriding).")
        vigor_bar_cb:SetPoint("TOPLEFT", secondary_power_cb, "BOTTOMLEFT", 0, -10)

        local mount_speed_cb = create_checkbox(bars_panel, "enable mount speed bar", "enableMountSpeedBar", function(checked)
            sfui.bars:on_state_changed()
        end, "toggles the mount speed bar (skyriding).")
        mount_speed_cb:SetPoint("TOPLEFT", vigor_bar_cb, "BOTTOMLEFT", 0, -10)

        local last_toggle_cb = mount_speed_cb
        if not sfui.isRetail and sfui.swing then
            local swing_bar_cb = create_checkbox(bars_panel, "enable swing timer bars", "enableSwingBars", function(checked)
                sfui.bars.update_bar_visibility()
            end, "toggles the 3-weapon swing timer bars (Classic).")
            swing_bar_cb:SetPoint("TOPLEFT", last_toggle_cb, "BOTTOMLEFT", 0, -10)
            last_toggle_cb = swing_bar_cb
        end

        if not sfui.isRetail then
            if sfui.target then
                local target_bar_cb = create_checkbox(bars_panel, "enable target bar", "enableTargetBar", function(checked)
                    sfui.target.UpdateVisibility()
                end, "toggles the target bar.")
                target_bar_cb:SetPoint("TOPLEFT", last_toggle_cb, "BOTTOMLEFT", 0, -10)
                last_toggle_cb = target_bar_cb
            end

            if sfui.threat then
                local threat_bar_cb = create_checkbox(bars_panel, "enable threat bar", "enableThreatBar", function(checked)
                    sfui.threat.UpdateVisibility()
                end, "toggles the threat bar above the player health bar.")
                threat_bar_cb:SetPoint("TOPLEFT", last_toggle_cb, "BOTTOMLEFT", 0, -10)
                last_toggle_cb = threat_bar_cb
            end
        end

        -- Health Bar Position
        local position_header = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
        position_header:SetPoint("TOPLEFT", last_toggle_cb, "BOTTOMLEFT", 0, -20)
        position_header:SetTextColor(white[1], white[2], white[3])
        position_header:SetText("health bar position")

        local health_x_slider = create_slider_input(bars_panel, "x:", "healthBarX", -1000, 1000, 1, function(val)
            sfui.bars:update_health_bar_position()
        end)
        health_x_slider:SetPoint("TOPLEFT", position_header, "BOTTOMLEFT", 0, -10)

        local health_y_slider = create_slider_input(bars_panel, "y:", "healthBarY", -1000, 1000, 1, function(val)
            sfui.bars:update_health_bar_position()
        end)
        health_y_slider:SetPoint("LEFT", health_x_slider, "RIGHT", 10, 0)

        local reset_health_pos_btn = CreateFlatButton(bars_panel, "reset position", 120, 22)
        reset_health_pos_btn:SetPoint("TOPLEFT", health_x_slider, "BOTTOMLEFT", 0, -10)
        reset_health_pos_btn:SetScript("OnClick", function()
            local def = sfui.config.healthBar.pos
            SfuiDB.healthBarX = def.x
            SfuiDB.healthBarY = def.y
            health_x_slider:SetSliderValue(def.x)
            health_y_slider:SetSliderValue(def.y)
            sfui.bars:update_health_bar_position()
        end)

        -- Health Bar Colors
        local color_header = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
        color_header:SetPoint("TOPLEFT", reset_health_pos_btn, "BOTTOMLEFT", 0, -20)
        color_header:SetTextColor(white[1], white[2], white[3])
        color_header:SetText("health bar colors")

        local fg_color_label = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
        fg_color_label:SetPoint("TOPLEFT", color_header, "BOTTOMLEFT", 0, -10)
        fg_color_label:SetTextColor(white[1], white[2], white[3])
        fg_color_label:SetText("foreground:")

        local fg_color_swatch = common.create_color_swatch(bars_panel, SfuiDB.healthBarColor or sfui.config.healthBar.color,
            function(r, green, b)
                SfuiDB.healthBarColor = { r, green, b, 1 }
                sfui.bars:on_state_changed()
            end)
        fg_color_swatch:SetPoint("LEFT", fg_color_label, "RIGHT", 5, 0)

        local bg_color_label = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
        bg_color_label:SetPoint("LEFT", fg_color_swatch, "RIGHT", 15, 0)
        bg_color_label:SetTextColor(white[1], white[2], white[3])
        bg_color_label:SetText("backdrop:")

        local bg_color_swatch = common.create_color_swatch(bars_panel,
            SfuiDB.healthBarBackdropColor or sfui.config.healthBar.backdrop.color, function(r, green, b)
                SfuiDB.healthBarBackdropColor = { r, green, b, 0.5 }
                sfui.bars:on_state_changed()
            end)
        bg_color_swatch:SetPoint("LEFT", bg_color_label, "RIGHT", 5, 0)

        if not sfui.isRetail and sfui.totembar then
            -- ─────────────────────────────────────────────────────────────────
            -- Totem Bar Settings (Vanilla / Camelot only)
            -- ─────────────────────────────────────────────────────────────────
            local COL_OFFSET_X = 265

            local totem_header = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
            totem_header:SetPoint("TOPLEFT", fg_color_label, "BOTTOMLEFT", 0, -25)
            totem_header:SetTextColor(white[1], white[2], white[3])
            totem_header:SetText("totem bar settings")

            local totem_desc = bars_panel:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
            totem_desc:SetPoint("TOPLEFT", totem_header, "BOTTOMLEFT", 0, -4)
            totem_desc:SetTextColor(0.7, 0.7, 0.7)
            totem_desc:SetText("standalone totem bar with scroll selection and in-combat right-click destroy.")

            local totem_enable_cb = create_checkbox(
                bars_panel,
                "enable totem bar",
                function()
                    if SfuiDB and SfuiDB.totembar and SfuiDB.totembar.enabled ~= nil then
                        return SfuiDB.totembar.enabled
                    end
                    return sfui.config and sfui.config.totembar and sfui.config.totembar.enabled ~= false
                end,
                function(checked)
                    SfuiDB = SfuiDB or {}
                    SfuiDB.totembar = SfuiDB.totembar or {}
                    SfuiDB.totembar.enabled = checked
                    if sfui.totembar and sfui.totembar.ApplySettings then
                        sfui.totembar.ApplySettings()
                    end
                end,
                "toggles the standalone totem tracking bar."
            )
            totem_enable_cb:SetPoint("TOPLEFT", totem_desc, "BOTTOMLEFT", 0, -10)

            local totem_element_cb = create_checkbox(
                bars_panel,
                "color borders by element",
                function()
                    if SfuiDB and SfuiDB.totembar and SfuiDB.totembar.colorByElement ~= nil then
                        return SfuiDB.totembar.colorByElement
                    end
                    return sfui.config and sfui.config.totembar and sfui.config.totembar.colorByElement ~= false
                end,
                function(checked)
                    SfuiDB = SfuiDB or {}
                    SfuiDB.totembar = SfuiDB.totembar or {}
                    SfuiDB.totembar.colorByElement = checked
                    if sfui.totembar and sfui.totembar.ApplySettings then
                        sfui.totembar.ApplySettings()
                    end
                end,
                "colors button borders and active glows by element (earth, fire, water, air)."
            )
            totem_element_cb:SetPoint("LEFT", totem_enable_cb, "LEFT", COL_OFFSET_X, 0)

            local totem_timer_cb = create_checkbox(
                bars_panel,
                "show timer text",
                function()
                    if SfuiDB and SfuiDB.totembar and SfuiDB.totembar.showTimerText ~= nil then
                        return SfuiDB.totembar.showTimerText
                    end
                    return sfui.config and sfui.config.totembar and sfui.config.totembar.showTimerText ~= false
                end,
                function(checked)
                    SfuiDB = SfuiDB or {}
                    SfuiDB.totembar = SfuiDB.totembar or {}
                    SfuiDB.totembar.showTimerText = checked
                    if sfui.totembar and sfui.totembar.ApplySettings then
                        sfui.totembar.ApplySettings()
                    end
                end,
                "shows countdown duration text below the totem icon."
            )
            totem_timer_cb:SetPoint("TOPLEFT", totem_enable_cb, "BOTTOMLEFT", 0, -10)

            local totem_glow_cb = create_checkbox(
                bars_panel,
                "show active glow",
                function()
                    if SfuiDB and SfuiDB.totembar and SfuiDB.totembar.showGlow ~= nil then
                        return SfuiDB.totembar.showGlow
                    end
                    return sfui.config and sfui.config.totembar and sfui.config.totembar.showGlow ~= false
                end,
                function(checked)
                    SfuiDB = SfuiDB or {}
                    SfuiDB.totembar = SfuiDB.totembar or {}
                    SfuiDB.totembar.showGlow = checked
                    if sfui.totembar and sfui.totembar.ApplySettings then
                        sfui.totembar.ApplySettings()
                    end
                end,
                "shows an animated pixel glow around active totems."
            )
            totem_glow_cb:SetPoint("LEFT", totem_timer_cb, "LEFT", COL_OFFSET_X, 0)

            local totem_size_slider = create_slider_input(
                bars_panel,
                "icon size:",
                function() return SfuiDB and SfuiDB.totembar and SfuiDB.totembar.size or 36 end,
                24, 64, 2,
                function(val)
                    SfuiDB = SfuiDB or {}
                    SfuiDB.totembar = SfuiDB.totembar or {}
                    SfuiDB.totembar.size = val
                    if sfui.totembar and sfui.totembar.ApplySettings then
                        sfui.totembar.ApplySettings()
                    end
                end,
                "size of each totem button in pixels."
            )
            totem_size_slider:SetPoint("TOPLEFT", totem_timer_cb, "BOTTOMLEFT", 0, -12)

            local totem_spacing_slider = create_slider_input(
                bars_panel,
                "spacing:",
                function() return SfuiDB and SfuiDB.totembar and SfuiDB.totembar.spacing or 4 end,
                0, 16, 1,
                function(val)
                    SfuiDB = SfuiDB or {}
                    SfuiDB.totembar = SfuiDB.totembar or {}
                    SfuiDB.totembar.spacing = val
                    if sfui.totembar and sfui.totembar.ApplySettings then
                        sfui.totembar.ApplySettings()
                    end
                end,
                "spacing between totem buttons in pixels."
            )
            totem_spacing_slider:SetPoint("LEFT", totem_size_slider, "LEFT", COL_OFFSET_X, 0)

            local unlock_totem_btn = CreateFlatButton(bars_panel, "unlock totem bar", 140, 22)
            unlock_totem_btn:SetPoint("TOPLEFT", totem_size_slider, "BOTTOMLEFT", 0, -12)
            unlock_totem_btn:SetScript("OnClick", function(self)
                if sfui.totembar and sfui.totembar.ToggleUnlock then
                    local unlocked = sfui.totembar.ToggleUnlock()
                    self:SetText(unlocked and "lock totem bar" or "unlock totem bar")
                end
            end)

            local reset_totem_btn = CreateFlatButton(bars_panel, "reset position", 120, 22)
            reset_totem_btn:SetPoint("LEFT", unlock_totem_btn, "RIGHT", 10, 0)
            reset_totem_btn:SetScript("OnClick", function()
                if sfui.totembar and sfui.totembar.ResetPosition then
                    sfui.totembar.ResetPosition()
                end
            end)

            local seq_header = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
            seq_header:SetPoint("TOPLEFT", unlock_totem_btn, "BOTTOMLEFT", 0, -20)
            seq_header:SetTextColor(white[1], white[2], white[3])
            seq_header:SetText("cast sequence & keybind")

            local seq_desc = bars_panel:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
            seq_desc:SetPoint("TOPLEFT", seq_header, "BOTTOMLEFT", 0, -4)
            seq_desc:SetTextColor(0.7, 0.7, 0.7)
            seq_desc:SetText("automated /castsequence that casts your selected totems in order.")

            local keybind_label = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
            keybind_label:SetPoint("TOPLEFT", seq_desc, "BOTTOMLEFT", 0, -12)
            keybind_label:SetTextColor(0.9, 0.9, 0.9)
            keybind_label:SetText("sequence keybind:")

            local bind_btn = CreateFlatButton(bars_panel, "not bound", 130, 22)
            bind_btn:SetPoint("LEFT", keybind_label, "RIGHT", 10, 0)
            bind_btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

            local unbind_btn = CreateFlatButton(bars_panel, "clear", 60, 22)
            unbind_btn:SetPoint("LEFT", bind_btn, "RIGHT", 8, 0)

            local keybind_hint = bars_panel:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
            keybind_hint:SetPoint("LEFT", unbind_btn, "RIGHT", 10, 0)
            keybind_hint:SetTextColor(0.6, 0.6, 0.6)

            local is_listening = false
            local catcher = CreateFrame("Frame", nil, bars_panel)
            catcher:SetFrameStrata("DIALOG")
            catcher:SetAllPoints(_G.UIParent or bars_panel)
            catcher:EnableMouse(true)
            catcher:Hide()

            local function update_keybind_display()
                if is_listening then return end
                local rawKey, formatted
                if sfui.totembar and sfui.totembar.GetBoundKey then
                    rawKey, formatted = sfui.totembar.GetBoundKey()
                end
                formatted = (formatted and formatted ~= "") and formatted or rawKey
                if formatted and formatted ~= "" then
                    bind_btn:SetText("|cff00ffff" .. formatted:lower() .. "|r")
                    bind_btn:SetBackdropBorderColor(0, 0.8, 1, 0.85)
                    keybind_hint:SetText("|cff666666(right-click to clear)|r")
                else
                    bind_btn:SetText("|cff888888not bound|r")
                    bind_btn:SetBackdropBorderColor(0, 0, 0, 1)
                    keybind_hint:SetText("|cff666666(click to bind)|r")
                end
            end

            local function stop_listening()
                if not is_listening then return end
                is_listening = false
                catcher:EnableKeyboard(false)
                if catcher.EnableGamePadButton then
                    catcher:EnableGamePadButton(false)
                end
                catcher:Hide()
                bind_btn.lockColor = false
                bind_btn:SetBackdropBorderColor(0, 0, 0, 1)
                update_keybind_display()
            end

            local function start_listening()
                local InCombat = _G.InCombatLockdown
                if InCombat and InCombat() then return end
                is_listening = true
                bind_btn.lockColor = true
                bind_btn:SetText("|cffffff00press key...|r")
                bind_btn:SetBackdropBorderColor(0, 1, 1, 1)
                keybind_hint:SetText("|cffffff00press key or button (esc to cancel)|r")

                catcher:Show()
                catcher:EnableKeyboard(true)
                if catcher.EnableGamePadButton then
                    catcher:EnableGamePadButton(true)
                end
                if catcher.SetPropagateKeyboardInput then
                    catcher:SetPropagateKeyboardInput(false)
                end
            end

            bind_btn:SetScript("OnClick", function(_, button)
                local InCombat = _G.InCombatLockdown
                if InCombat and InCombat() then return end
                if button == "RightButton" then
                    if is_listening then
                        stop_listening()
                    else
                        if sfui.totembar and sfui.totembar.UnbindKey then
                            sfui.totembar.UnbindKey()
                        end
                        update_keybind_display()
                    end
                elseif button == "LeftButton" then
                    if is_listening then
                        stop_listening()
                    else
                        start_listening()
                    end
                end
            end)

            unbind_btn:SetScript("OnClick", function()
                local InCombat = _G.InCombatLockdown
                if InCombat and InCombat() then return end
                if is_listening then
                    stop_listening()
                end
                if sfui.totembar and sfui.totembar.UnbindKey then
                    sfui.totembar.UnbindKey()
                end
                update_keybind_display()
            end)

            bind_btn:HookScript("OnEnter", function(self)
                local tip = sfui.common.get_tooltip()
                if tip then
                    tip:SetOwner(self, "ANCHOR_TOP")
                    tip:SetText("totem sequence keybind", 1, 1, 1)
                    tip:AddLine("left-click: press any key, mouse button, or controller button to bind.", 0.8, 0.8, 0.8, true)
                    tip:AddLine("right-click: unbind active key.", 0.8, 0.8, 0.8, true)
                    tip:AddLine("press esc while listening to cancel.", 0.6, 0.6, 0.6, true)
                    tip:Show()
                end
            end)
            bind_btn:HookScript("OnLeave", function()
                local tip = sfui.common.get_tooltip()
                if tip then tip:Hide() end
            end)

            unbind_btn:HookScript("OnEnter", function(self)
                local tip = sfui.common.get_tooltip()
                if tip then
                    tip:SetOwner(self, "ANCHOR_TOP")
                    tip:SetText("clear keybind", 1, 1, 1)
                    tip:AddLine("removes the active totem sequence keybind.", 0.8, 0.8, 0.8, true)
                    tip:Show()
                end
            end)
            unbind_btn:HookScript("OnLeave", function()
                local tip = sfui.common.get_tooltip()
                if tip then tip:Hide() end
            end)

            update_keybind_display()

            local function is_meta_key(key)
                if _G.IsMetaKey then return _G.IsMetaKey(key) end
                return key == "LALT" or key == "RALT" or key == "ALT"
                    or key == "LCTRL" or key == "RCTRL" or key == "CTRL"
                    or key == "LSHIFT" or key == "RSHIFT" or key == "SHIFT"
                    or key == "LMETA" or key == "RMETA" or key == "META"
            end

            local function build_key_chord(key)
                if not key or key == "" then return nil end
                if _G.CreateKeyChordStringUsingMetaKeyState then
                    return _G.CreateKeyChordStringUsingMetaKeyState(key)
                end

                local chord = {}
                local IsAlt = _G.IsAltKeyDown
                local IsControl = _G.IsControlKeyDown
                local IsShift = _G.IsShiftKeyDown
                local IsMeta = _G.IsMetaKeyDown
                if IsAlt and IsAlt() then table.insert(chord, "ALT") end
                if IsControl and IsControl() then table.insert(chord, "CTRL") end
                if IsShift and IsShift() then table.insert(chord, "SHIFT") end
                if IsMeta and IsMeta() then table.insert(chord, "META") end
                table.insert(chord, key)
                return table.concat(chord, "-")
            end

            catcher:SetScript("OnKeyDown", function(_, key)
                if key == "ESCAPE" then
                    stop_listening()
                    return
                end

                if is_meta_key(key) or key == "UNKNOWN" or key == "PRINTSCREEN" then
                    return
                end

                local chord = build_key_chord(key)
                if chord and chord ~= "" then
                    if sfui.totembar and sfui.totembar.SetKeybind then
                        sfui.totembar.SetKeybind(chord)
                    end
                end
                stop_listening()
            end)

            catcher:SetScript("OnGamePadButtonDown", function(_, button)
                if button and button ~= "" then
                    if sfui.totembar and sfui.totembar.SetKeybind then
                        sfui.totembar.SetKeybind(button)
                    end
                end
                stop_listening()
            end)

            catcher:SetScript("OnMouseWheel", function(_, delta)
                local key = delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"
                local chord = build_key_chord(key)
                if chord and chord ~= "" then
                    if sfui.totembar and sfui.totembar.SetKeybind then
                        sfui.totembar.SetKeybind(chord)
                    end
                end
                stop_listening()
            end)

            local mouse_button_map = {
                MiddleButton = "BUTTON3",
                Button3      = "BUTTON3",
                Button4      = "BUTTON4",
                Button5      = "BUTTON5",
                Button6      = "BUTTON6",
                Button7      = "BUTTON7",
                Button8      = "BUTTON8",
            }

            catcher:SetScript("OnMouseDown", function(_, button)
                if button == "LeftButton" or button == "RightButton" then
                    stop_listening()
                else
                    local mapped = mouse_button_map[button] or (_G.GetConvertedKeyOrButton and _G.GetConvertedKeyOrButton(button))
                    if mapped and mapped ~= "BUTTON1" and mapped ~= "BUTTON2" then
                        local chord = build_key_chord(mapped)
                        if chord and chord ~= "" then
                            if sfui.totembar and sfui.totembar.SetKeybind then
                                sfui.totembar.SetKeybind(chord)
                            end
                        end
                    end
                    stop_listening()
                end
            end)

            local show_seq_cb = create_checkbox(
                bars_panel,
                "show sequence button on bar",
                function()
                    if SfuiDB and SfuiDB.totembar and SfuiDB.totembar.showSequenceButton ~= nil then
                        return SfuiDB.totembar.showSequenceButton
                    end
                    return sfui.config and sfui.config.totembar and sfui.config.totembar.showSequenceButton == true
                end,
                function(checked)
                    SfuiDB = SfuiDB or {}
                    SfuiDB.totembar = SfuiDB.totembar or {}
                    SfuiDB.totembar.showSequenceButton = checked
                    if sfui.totembar and sfui.totembar.ApplySettings then
                        sfui.totembar.ApplySettings()
                    end
                end,
                "displays a 5th button on the totem bar to click or monitor the sequence."
            )
            show_seq_cb:SetPoint("TOPLEFT", keybind_label, "BOTTOMLEFT", 0, -18)

            local seq_reset_slider = create_slider_input(
                bars_panel,
                "sequence reset (sec):",
                function() return SfuiDB and SfuiDB.totembar and SfuiDB.totembar.resetTimer or 15 end,
                5, 60, 1,
                function(val)
                    SfuiDB = SfuiDB or {}
                    SfuiDB.totembar = SfuiDB.totembar or {}
                    SfuiDB.totembar.resetTimer = val
                    if sfui.totembar and sfui.totembar.ApplySettings then
                        sfui.totembar.ApplySettings()
                    end
                end,
                "seconds of inactivity before the cast sequence resets to the first totem."
            )
            seq_reset_slider:SetPoint("TOPLEFT", show_seq_cb, "BOTTOMLEFT", 0, -12)

            bars_panel:HookScript("OnShow", function()
                update_keybind_display()
            end)
            bars_panel:HookScript("OnHide", function()
                stop_listening()
            end)
            if options_frame then
                options_frame:HookScript("OnHide", function()
                    stop_listening()
                end)
            end
            if sfui.events and sfui.events.RegisterEvent then
                sfui.events.RegisterEvent("UPDATE_BINDINGS", function()
                    if bars_panel:IsVisible() then
                        update_keybind_display()
                    end
                end)
                sfui.events.RegisterEvent("PLAYER_REGEN_DISABLED", function()
                    stop_listening()
                end)
            end

            bars_panel.customContentHeight = 780
        end
    end,
})
