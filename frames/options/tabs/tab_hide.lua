local addonName, addon = ...
sfui = sfui or {}
sfui.options = sfui.options or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/options/tabs/tab_hide.lua
--  Options Tab: Action Bar Mouseover & Blizzard Unitframe Suppression
-- ══════════════════════════════════════════════════════════════════════════════

local g = sfui.config
local common = sfui.common

sfui.options.RegisterTab({
    id = "hide",
    name = "hide",
    build = function(panel, tab_button, options_frame)
        local CreateFlatButton = common.create_flat_button
        local create_checkbox = common.create_checkbox
        local create_slider_input = common.create_slider_input
        local white = sfui.config.colors.white

        local function notify_change(key, val)
            if sfui.options and sfui.options.notify_setting_changed then
                sfui.options.notify_setting_changed("hide", key, val)
            elseif sfui.hide and sfui.hide.OnSettingsChanged then
                sfui.hide:OnSettingsChanged(key, val)
            end
        end

        -- ─────────────────────────────────────────────────────────────────────
        -- 1. Main Header
        -- ─────────────────────────────────────────────────────────────────────
        local main_header = panel:CreateFontString(nil, "OVERLAY", g.font)
        main_header:SetPoint("TOPLEFT", 15, -15)
        main_header:SetTextColor(white[1], white[2], white[3])
        main_header:SetText("hide & mouseover settings")

        -- ─────────────────────────────────────────────────────────────────────
        -- 2. Action Bars Mouseover
        -- ─────────────────────────────────────────────────────────────────────
        local ab_header = panel:CreateFontString(nil, "OVERLAY", g.font)
        ab_header:SetPoint("TOPLEFT", main_header, "BOTTOMLEFT", 0, -20)
        ab_header:SetTextColor(white[1], white[2], white[3])
        ab_header:SetText("action bars mouseover")

        local master_cb = create_checkbox(
            panel,
            "enable action bar mouseover",
            "actionbars_mouseover_enabled",
            function(checked)
                notify_change("actionbars_mouseover_enabled", checked)
                if sfui.hide and sfui.hide.RefreshActionBars then
                    sfui.hide.RefreshActionBars()
                end
            end,
            "hides action bars by default and smoothly reveals them on mouse hover."
        )
        master_cb:SetPoint("TOPLEFT", ab_header, "BOTTOMLEFT", 0, -10)

        -- Sliders: Resting Alpha, Mouseover Alpha, Fade Duration
        local resting_slider = create_slider_input(
            panel,
            "resting alpha:",
            "actionbars_resting_alpha",
            0.0, 1.0, 0.05,
            function(val)
                notify_change("actionbars_resting_alpha", val)
                if sfui.hide and sfui.hide.RefreshActionBars then
                    sfui.hide.RefreshActionBars()
                end
            end,
            "opacity of action bars when the mouse is NOT hovering (0% is completely hidden)."
        )
        resting_slider:SetPoint("TOPLEFT", master_cb, "BOTTOMLEFT", 0, -15)

        local active_slider = create_slider_input(
            panel,
            "hover alpha:",
            "actionbars_active_alpha",
            0.1, 1.0, 0.05,
            function(val)
                notify_change("actionbars_active_alpha", val)
                if sfui.hide and sfui.hide.RefreshActionBars then
                    sfui.hide.RefreshActionBars()
                end
            end,
            "opacity of action bars when hovering over them."
        )
        active_slider:SetPoint("LEFT", resting_slider, "RIGHT", 10, 0)

        local fade_slider = create_slider_input(
            panel,
            "fade speed (sec):",
            "actionbars_fade_duration",
            0.05, 1.0, 0.05,
            function(val)
                notify_change("actionbars_fade_duration", val)
            end,
            "duration in seconds for the bar fade-in and fade-out animation."
        )
        fade_slider:SetPoint("TOPLEFT", resting_slider, "BOTTOMLEFT", 0, -15)

        -- ─────────────────────────────────────────────────────────────────────
        -- 3. Per-Bar Toggles
        -- ─────────────────────────────────────────────────────────────────────
        local bars_header = panel:CreateFontString(nil, "OVERLAY", g.font)
        bars_header:SetPoint("TOPLEFT", fade_slider, "BOTTOMLEFT", 0, -20)
        bars_header:SetTextColor(white[1], white[2], white[3])
        bars_header:SetText("bars enabled for mouseover")

        local barEntriesCol1 = {
            { key = "actionbars_bar_main",      label = "main action bar" },
            { key = "actionbars_bar_bar2",      label = "action bar 2 (bottom left)" },
            { key = "actionbars_bar_bar3",      label = "action bar 3 (bottom right)" },
            { key = "actionbars_bar_bar4",      label = "action bar 4 (right 1)" },
            { key = "actionbars_bar_bar5",      label = "action bar 5 (right 2)" },
            { key = "actionbars_bar_bar6",      label = "action bar 6" },
        }

        local barEntriesCol2 = {
            { key = "actionbars_bar_bar7",      label = "action bar 7" },
            { key = "actionbars_bar_bar8",      label = "action bar 8" },
            { key = "actionbars_bar_pet",       label = "pet action bar" },
            { key = "actionbars_bar_stance",    label = "stance / shapeshift bar" },
            { key = "actionbars_bar_possess",   label = "possess bar" },
        }

        local prevCol1 = bars_header
        for i, b in ipairs(barEntriesCol1) do
            local cb = create_checkbox(
                panel,
                b.label,
                b.key,
                function(checked)
                    notify_change(b.key, checked)
                    if sfui.hide and sfui.hide.RefreshActionBars then sfui.hide.RefreshActionBars() end
                end,
                "enables mouseover fading on this bar."
            )
            cb:SetPoint("TOPLEFT", prevCol1, "BOTTOMLEFT", 0, -10)
            prevCol1 = cb
        end

        local prevCol2 = nil
        for i, b in ipairs(barEntriesCol2) do
            local cb = create_checkbox(
                panel,
                b.label,
                b.key,
                function(checked)
                    notify_change(b.key, checked)
                    if sfui.hide and sfui.hide.RefreshActionBars then sfui.hide.RefreshActionBars() end
                end,
                "enables mouseover fading on this bar."
            )
            if i == 1 then
                cb:SetPoint("TOPLEFT", bars_header, "BOTTOMLEFT", 220, -10)
            else
                cb:SetPoint("TOPLEFT", prevCol2, "BOTTOMLEFT", 0, -10)
            end
            prevCol2 = cb
        end

        -- ─────────────────────────────────────────────────────────────────────
        -- 4. Unit & HUD Frames Suppression
        -- ─────────────────────────────────────────────────────────────────────
        local uf_header = panel:CreateFontString(nil, "OVERLAY", g.font)
        uf_header:SetPoint("TOPLEFT", prevCol1, "BOTTOMLEFT", 0, -25)
        uf_header:SetTextColor(white[1], white[2], white[3])
        uf_header:SetText("blizzard unit & hud frames")

        local uf_desc = panel:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
        uf_desc:SetPoint("TOPLEFT", uf_header, "BOTTOMLEFT", 0, -4)
        uf_desc:SetTextColor(0.7, 0.7, 0.7)
        uf_desc:SetText("safely hide default blizzard frames with zero combat taint or errors.")

        local ufEntriesCol1 = {
            { key = "hide_player_frame", label = "hide player frame", tooltip = "hides the default blizzard player frame." },
            { key = "hide_target_frame", label = "hide target frame", tooltip = "hides the default blizzard target frame." },
            { key = "hide_micromenu",    label = "hide game menu",    tooltip = "hides the default blizzard game menu (micro menu)." },
        }

        local ufEntriesCol2 = {
            { key = "hide_pet_frame",    label = "hide pet frame",    tooltip = "hides the default blizzard pet frame." },
            { key = "hide_focus_frame",  label = "hide focus frame",  tooltip = "hides the default blizzard focus frame." },
            { key = "hide_bagsbar",      label = "hide bags bar",     tooltip = "hides the default blizzard bags bar." },
        }

        local prevUFCol1 = uf_desc
        for i, u in ipairs(ufEntriesCol1) do
            local cb = create_checkbox(
                panel,
                u.label,
                u.key,
                function(checked)
                    notify_change(u.key, checked)
                    if sfui.hide and sfui.hide.ApplyAllUnitFrames then
                        sfui.hide.ApplyAllUnitFrames()
                    end
                end,
                u.tooltip
            )
            cb:SetPoint("TOPLEFT", prevUFCol1, "BOTTOMLEFT", 0, (i == 1) and -12 or -10)
            prevUFCol1 = cb
        end

        local prevUFCol2 = nil
        for i, u in ipairs(ufEntriesCol2) do
            local cb = create_checkbox(
                panel,
                u.label,
                u.key,
                function(checked)
                    notify_change(u.key, checked)
                    if sfui.hide and sfui.hide.ApplyAllUnitFrames then
                        sfui.hide.ApplyAllUnitFrames()
                    end
                end,
                u.tooltip
            )
            if i == 1 then
                cb:SetPoint("TOPLEFT", uf_desc, "BOTTOMLEFT", 220, -12)
            else
                cb:SetPoint("TOPLEFT", prevUFCol2, "BOTTOMLEFT", 0, -10)
            end
            prevUFCol2 = cb
        end

        panel.customContentHeight = 650
    end,
})
