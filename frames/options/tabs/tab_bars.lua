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

        bars_panel.customContentHeight = 360
    end,
})
