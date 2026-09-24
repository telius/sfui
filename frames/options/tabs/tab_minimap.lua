local addonName, addon = ...
sfui = sfui or {}
sfui.options = sfui.options or {}

local g = sfui.config
local common = sfui.common
local C_Timer = _G.C_Timer

sfui.options.RegisterTab({
    id = "minimap",
    name = "minimap",
    build = function(minimap_panel, tab_button, options_frame)
        local CreateFlatButton = common.create_flat_button
        local create_checkbox = common.create_checkbox
        local create_slider_input = common.create_slider_input
        local white = sfui.config.colors.white

        local minimap_header = minimap_panel:CreateFontString(nil, "OVERLAY", g.font)
        minimap_header:SetPoint("TOPLEFT", 15, -15)
        minimap_header:SetTextColor(white[1], white[2], white[3])
        minimap_header:SetText("minimap settings")

        local collect_cb = create_checkbox(minimap_panel, "collect buttons", "minimap_collect_buttons", function(checked)
            if sfui.minimap and sfui.minimap.enable_button_manager then
                sfui.minimap.enable_button_manager(checked)
            end
        end, "collects minimap buttons into a bar.")
        collect_cb:SetPoint("TOPLEFT", minimap_header, "BOTTOMLEFT", 0, -10)

        local mouseover_cb = create_checkbox(minimap_panel, "mouseover only", "minimap_buttons_mouseover", function(checked)
            if sfui.minimap and sfui.minimap.enable_button_manager and SfuiDB.minimap_collect_buttons then
                C_Timer.After(0.1, function()
                    sfui.minimap.enable_button_manager(false)
                    sfui.minimap.enable_button_manager(true)
                end)
            end
        end, "only show the button bar when hovering the minimap. also moves group finder eye to top left.")
        mouseover_cb:SetPoint("TOPLEFT", collect_cb, "BOTTOMLEFT", 0, -10)

        local autozoom_cb = create_checkbox(minimap_panel, "enable autozoom", "minimap_auto_zoom", function(checked)
            if sfui.minimap and sfui.minimap.reset_zoom_timer then
                sfui.minimap.reset_zoom_timer()
            end
        end, "automatically resets minimap zoom after a delay.")
        autozoom_cb:SetPoint("TOPLEFT", mouseover_cb, "BOTTOMLEFT", 0, -10)

        local autozoom_delay = create_slider_input(minimap_panel, "autozoom delay:", "minimap_auto_zoom_delay", 1, 30, 1,
            function(val)
                if sfui.minimap and sfui.minimap.reset_zoom_timer then
                    sfui.minimap.reset_zoom_timer()
                end
            end, "seconds to wait before automatically zooming out.")
        autozoom_delay:SetPoint("TOPLEFT", autozoom_cb, "BOTTOMLEFT", 0, -15)

        local pos_x_slider = create_slider_input(minimap_panel, "minimap x:", "minimap_button_x", -1000, 1000, 1,
            function(val)
                if sfui.minimap and sfui.minimap.update_button_bar_position then
                    sfui.minimap.update_button_bar_position()
                end
            end)
        pos_x_slider:SetPoint("TOPLEFT", autozoom_delay, "BOTTOMLEFT", 0, -15)

        local pos_y_slider = create_slider_input(minimap_panel, "minimap y:", "minimap_button_y", -1000, 1000, 1,
            function(val)
                if sfui.minimap and sfui.minimap.update_button_bar_position then
                    sfui.minimap.update_button_bar_position()
                end
            end)
        pos_y_slider:SetPoint("LEFT", pos_x_slider, "RIGHT", 10, 0)

        local reset_pos_btn = CreateFlatButton(minimap_panel, "reset position", 120, 22)
        reset_pos_btn:SetPoint("TOPLEFT", pos_x_slider, "BOTTOMLEFT", 0, -10)
        reset_pos_btn:SetScript("OnClick", function()
            local def = sfui.config.minimap.button_bar
            SfuiDB.minimap_button_x = def.defaultX
            SfuiDB.minimap_button_y = def.defaultY
            pos_x_slider:SetSliderValue(def.defaultX)
            pos_y_slider:SetSliderValue(def.defaultY)
            if sfui.minimap and sfui.minimap.update_button_bar_position then
                sfui.minimap.update_button_bar_position()
            end
        end)
    end,
})
