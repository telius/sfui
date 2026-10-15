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
        local create_dropdown = common.create_dropdown
        local white = sfui.config.colors.white

        local minimap_header = minimap_panel:CreateFontString(nil, "OVERLAY", g.font)
        minimap_header:SetPoint("TOPLEFT", 15, -15)
        minimap_header:SetTextColor(white[1], white[2], white[3])
        minimap_header:SetText("minimap settings")

        local square_cb = create_checkbox(minimap_panel, "square minimap", "minimap_square", function(checked)
            if sfui.map and sfui.map.square and sfui.map.square.SetEnabled then
                sfui.map.square:SetEnabled(checked)
            end
        end, "forces the minimap into a sleek, lean square with 1px border.")
        square_cb:SetPoint("TOPLEFT", minimap_header, "BOTTOMLEFT", 0, -10)

        local collect_cb = create_checkbox(minimap_panel, "collect buttons", "minimap_collect_buttons", function(checked)
            sfui.minimap.enable_button_manager(checked)
        end, "collects minimap buttons into a bar.")
        collect_cb:SetPoint("TOPLEFT", square_cb, "BOTTOMLEFT", 0, -10)

        local mouseover_cb = create_checkbox(minimap_panel, "mouseover only", "minimap_buttons_mouseover", function(checked)
            if SfuiDB.minimap_collect_buttons then
                C_Timer.After(0.1, function()
                    sfui.minimap.enable_button_manager(false)
                    sfui.minimap.enable_button_manager(true)
                end)
            end
        end, "only show the button bar when hovering the minimap. also moves group finder eye to top left.")
        mouseover_cb:SetPoint("TOPLEFT", collect_cb, "BOTTOMLEFT", 0, -10)

        local last_anchor = mouseover_cb
        if sfui.isCamelot then
            local status_cb = create_checkbox(minimap_panel, "show status indicators", "minimap_show_status", function(checked)
                sfui.minimap.update_status()
            end, "shows resting and pvp status icons beside the clock.")
            status_cb:SetPoint("TOPLEFT", mouseover_cb, "BOTTOMLEFT", 0, -10)
            last_anchor = status_cb
        end

        if _G.C_Weather then
            local weather_cb = create_checkbox(minimap_panel, "show weather indicator", "minimap_show_weather", function(checked)
                sfui.minimap.update_status()
            end, "shows ambient weather icon (rain, snow, sandstorm) beside the clock.")
            weather_cb:SetPoint("TOPLEFT", last_anchor, "BOTTOMLEFT", 0, -10)
            last_anchor = weather_cb
        end

        local autozoom_cb = create_checkbox(minimap_panel, "enable autozoom", "minimap_auto_zoom", function(checked)
            sfui.minimap.reset_zoom_timer()
        end, "automatically resets minimap zoom after a delay.")
        autozoom_cb:SetPoint("TOPLEFT", last_anchor, "BOTTOMLEFT", 0, -10)

        local autozoom_delay = create_slider_input(minimap_panel, "autozoom delay:", "minimap_auto_zoom_delay", 1, 30, 1,
            function(val)
                sfui.minimap.reset_zoom_timer()
            end, "seconds to wait before automatically zooming out.")
        autozoom_delay:SetPoint("TOPLEFT", autozoom_cb, "BOTTOMLEFT", 0, -15)

        if SfuiDB then
            if SfuiDB.minimap_width == nil then
                SfuiDB.minimap_width = (sfui.config.minimap and (sfui.config.minimap.width or sfui.config.minimap.default_size)) or 220
            end
            if SfuiDB.minimap_height == nil then
                SfuiDB.minimap_height = (sfui.config.minimap and (sfui.config.minimap.height or sfui.config.minimap.default_size)) or 220
            end
            if SfuiDB.minimap_x == nil then
                SfuiDB.minimap_x = (sfui.config.minimap and sfui.config.minimap.x) or 0
            end
            if SfuiDB.minimap_y == nil then
                SfuiDB.minimap_y = (sfui.config.minimap and sfui.config.minimap.y) or 0
            end
            if SfuiDB.minimap_point == nil then
                SfuiDB.minimap_point = (sfui.config.minimap and sfui.config.minimap.point) or "TOPRIGHT"
            end
        end

        local dim_header = minimap_panel:CreateFontString(nil, "OVERLAY", g.font)
        dim_header:SetPoint("TOPLEFT", autozoom_delay, "BOTTOMLEFT", 0, -18)
        dim_header:SetTextColor(white[1], white[2], white[3])
        dim_header:SetText("minimap dimensions")

        local width_slider = create_slider_input(minimap_panel, "minimap width:", "minimap_width", 100, 600, 1,
            function(val)
                sfui.minimap.update_dimensions(val, nil)
            end, "exact width of the minimap in pixels.")
        width_slider:SetPoint("TOPLEFT", dim_header, "BOTTOMLEFT", 0, -10)

        local height_slider = create_slider_input(minimap_panel, "minimap height:", "minimap_height", 100, 600, 1,
            function(val)
                sfui.minimap.update_dimensions(nil, val)
            end, "exact height of the minimap in pixels.")
        height_slider:SetPoint("LEFT", width_slider, "RIGHT", 10, 0)

        local reset_dim_btn = CreateFlatButton(minimap_panel, "reset dimensions", 120, 22)
        reset_dim_btn:SetPoint("TOPLEFT", width_slider, "BOTTOMLEFT", 0, -10)
        reset_dim_btn:SetScript("OnClick", function()
            local defW = (sfui.config.minimap and (sfui.config.minimap.width or sfui.config.minimap.default_size)) or 220
            local defH = (sfui.config.minimap and (sfui.config.minimap.height or sfui.config.minimap.default_size)) or 220
            SfuiDB.minimap_width = defW
            SfuiDB.minimap_height = defH
            width_slider:SetSliderValue(defW)
            height_slider:SetSliderValue(defH)
            sfui.minimap.update_dimensions(defW, defH)
        end)

        local pos_header = minimap_panel:CreateFontString(nil, "OVERLAY", g.font)
        pos_header:SetPoint("TOPLEFT", reset_dim_btn, "BOTTOMLEFT", 0, -18)
        pos_header:SetTextColor(white[1], white[2], white[3])
        pos_header:SetText("minimap position")

        local anchor_label = minimap_panel:CreateFontString(nil, "OVERLAY", g.font)
        anchor_label:SetPoint("TOPLEFT", pos_header, "BOTTOMLEFT", 0, -10)
        anchor_label:SetTextColor(white[1], white[2], white[3])
        anchor_label:SetText("anchor point:")

        local anchor_options = {
            { text = "top right (default)", value = "TOPRIGHT" },
            { text = "top left", value = "TOPLEFT" },
            { text = "top", value = "TOP" },
            { text = "bottom right", value = "BOTTOMRIGHT" },
            { text = "bottom left", value = "BOTTOMLEFT" },
            { text = "bottom", value = "BOTTOM" },
            { text = "center", value = "CENTER" },
        }

        local cur_anchor = (SfuiDB and SfuiDB.minimap_point) or (sfui.config.minimap and sfui.config.minimap.point) or "TOPRIGHT"
        local anchor_dropdown = create_dropdown(minimap_panel, 180, anchor_options, function(val)
            SfuiDB.minimap_point = val
            SfuiDB.minimap_relative_point = val
            sfui.minimap.update_position()
        end, cur_anchor)
        anchor_dropdown:SetPoint("LEFT", anchor_label, "RIGHT", 10, 0)
        anchor_dropdown.tooltip = "screen anchor corner for the minimap."

        local map_x_slider = create_slider_input(minimap_panel, "offset x:", "minimap_x", -2500, 2500, 1,
            function(val)
                sfui.minimap.update_position(val, nil)
            end, "horizontal offset of the minimap.")
        map_x_slider:SetPoint("TOPLEFT", anchor_label, "BOTTOMLEFT", 0, -14)

        local map_y_slider = create_slider_input(minimap_panel, "offset y:", "minimap_y", -2500, 2500, 1,
            function(val)
                sfui.minimap.update_position(nil, val)
            end, "vertical offset of the minimap.")
        map_y_slider:SetPoint("LEFT", map_x_slider, "RIGHT", 10, 0)

        local reset_map_pos_btn = CreateFlatButton(minimap_panel, "reset position", 120, 22)
        reset_map_pos_btn:SetPoint("TOPLEFT", map_x_slider, "BOTTOMLEFT", 0, -10)
        reset_map_pos_btn:SetScript("OnClick", function()
            local defPoint = (sfui.config.minimap and sfui.config.minimap.point) or "TOPRIGHT"
            local defX = (sfui.config.minimap and sfui.config.minimap.x) or 0
            local defY = (sfui.config.minimap and sfui.config.minimap.y) or 0
            SfuiDB.minimap_point = defPoint
            SfuiDB.minimap_relative_point = defPoint
            SfuiDB.minimap_x = defX
            SfuiDB.minimap_y = defY
            if anchor_dropdown and anchor_dropdown.SetSelectedValue then
                anchor_dropdown:SetSelectedValue(defPoint)
            end
            map_x_slider:SetSliderValue(defX)
            map_y_slider:SetSliderValue(defY)
            sfui.minimap.update_position(defX, defY, defPoint, defPoint)
        end)

        local bar_header = minimap_panel:CreateFontString(nil, "OVERLAY", g.font)
        bar_header:SetPoint("TOPLEFT", reset_map_pos_btn, "BOTTOMLEFT", 0, -18)
        bar_header:SetTextColor(white[1], white[2], white[3])
        bar_header:SetText("button collection position")

        local pos_x_slider = create_slider_input(minimap_panel, "offset x:", "minimap_button_x", -1000, 1000, 1,
            function(val)
                sfui.minimap.update_button_bar_position()
            end, "horizontal offset of the button collection frame.")
        pos_x_slider:SetPoint("TOPLEFT", bar_header, "BOTTOMLEFT", 0, -10)

        local pos_y_slider = create_slider_input(minimap_panel, "offset y:", "minimap_button_y", -1000, 1000, 1,
            function(val)
                sfui.minimap.update_button_bar_position()
            end, "vertical offset from bottom of minimap (0 = stacked directly underneath).")
        pos_y_slider:SetPoint("LEFT", pos_x_slider, "RIGHT", 10, 0)

        local reset_pos_btn = CreateFlatButton(minimap_panel, "reset position", 120, 22)
        reset_pos_btn:SetPoint("TOPLEFT", pos_x_slider, "BOTTOMLEFT", 0, -10)
        reset_pos_btn:SetScript("OnClick", function()
            local def = sfui.config.minimap.button_bar
            SfuiDB.minimap_button_x = def.defaultX
            SfuiDB.minimap_button_y = def.defaultY
            pos_x_slider:SetSliderValue(def.defaultX)
            pos_y_slider:SetSliderValue(def.defaultY)
            sfui.minimap.update_button_bar_position()
        end)
    end,
})
