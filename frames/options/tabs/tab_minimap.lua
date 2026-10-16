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

        local height_slider = nil
        local width_slider = nil

        local function update_dim_controls()
            local isSquare = sfui.map and sfui.map.square and sfui.map.square.IsEnabled and sfui.map.square:IsEnabled()
            if isSquare then
                if height_slider then height_slider:Show() end
                if width_slider and width_slider.label then
                    width_slider.label:SetText("minimap width:")
                end
                if width_slider then
                    width_slider.tooltip = "exact width of the minimap in pixels."
                end
            else
                if height_slider then height_slider:Hide() end
                if width_slider and width_slider.label then
                    width_slider.label:SetText("minimap size:")
                end
                if width_slider then
                    width_slider.tooltip = "overall diameter of the circular minimap in pixels."
                end
            end
        end

        local square_cb = create_checkbox(minimap_panel, "square minimap", "minimap_square", function(checked)
            SfuiDB._minimapSquareCustomized = true
            if sfui.map and sfui.map.square and sfui.map.square.SetEnabled then
                sfui.map.square:SetEnabled(checked)
            end
            update_dim_controls()
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

        local dock_mail_cb = create_checkbox(minimap_panel, "dock mail icon", "minimap_dock_mail", function(checked)
            if sfui.minimap.update_indicator_positions then
                sfui.minimap.update_indicator_positions()
            end
            if sfui.minimap.arrange_buttons then
                sfui.minimap.arrange_buttons()
            end
        end, "docks the mail notification icon into the minimap button collection frame.")
        dock_mail_cb:SetPoint("TOPLEFT", mouseover_cb, "BOTTOMLEFT", 0, -10)

        local last_anchor = dock_mail_cb
        if sfui.isCamelot then
            local status_cb = create_checkbox(minimap_panel, "show status indicators", "minimap_show_status", function(checked)
                sfui.minimap.update_location_bar()
            end, "shows resting (zzz) and pvp tags in the location text.")
            status_cb:SetPoint("TOPLEFT", last_anchor, "BOTTOMLEFT", 0, -10)
            last_anchor = status_cb
        end

        if _G.C_Weather then
            local weather_cb = create_checkbox(minimap_panel, "show weather indicator", "minimap_show_weather", function(checked)
                sfui.minimap.update_status()
            end, "shows ambient weather icon (rain, snow, sandstorm) beside the day/night indicator.")
            weather_cb:SetPoint("TOPLEFT", last_anchor, "BOTTOMLEFT", 0, -10)
            last_anchor = weather_cb
        end

        local location_cb = create_checkbox(minimap_panel, "show location text", "minimap_show_location", function(checked)
            sfui.minimap.update_location_bar()
        end, "shows the zone name location text above the minimap.")
        location_cb:SetPoint("TOPLEFT", last_anchor, "BOTTOMLEFT", 0, -10)
        last_anchor = location_cb

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
            local isBronzeCamelot = (sfui.isCamelot or (sfui.compat and sfui.compat.is_camelot))
                and (sfui.theme and sfui.theme.IsCamelotActive and sfui.theme.IsCamelotActive())
            if SfuiDB.minimap_square == nil then
                SfuiDB.minimap_square = not isBronzeCamelot
            elseif isBronzeCamelot and SfuiDB.minimap_square == true and not SfuiDB._minimapSquareCustomized then
                SfuiDB.minimap_square = false
            end
            if SfuiDB.minimap_show_location == nil then
                SfuiDB.minimap_show_location = true
            end
            if SfuiDB.minimap_dock_mail == nil then
                SfuiDB.minimap_dock_mail = true
            end
            if SfuiDB.minimap_zone_x == nil then
                SfuiDB.minimap_zone_x = (sfui.config.minimap and sfui.config.minimap.zone_x) or 0
            end
            if SfuiDB.minimap_zone_y == nil then
                SfuiDB.minimap_zone_y = (sfui.config.minimap and sfui.config.minimap.zone_y) or 35
            end
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
                SfuiDB.minimap_y = (sfui.config.minimap and sfui.config.minimap.y) or 35
            end
            if SfuiDB.minimap_point == nil then
                SfuiDB.minimap_point = (sfui.config.minimap and sfui.config.minimap.point) or "BOTTOMRIGHT"
            end
        end

        local dim_header = minimap_panel:CreateFontString(nil, "OVERLAY", g.font)
        dim_header:SetPoint("TOPLEFT", autozoom_delay, "BOTTOMLEFT", 0, -18)
        dim_header:SetTextColor(white[1], white[2], white[3])
        dim_header:SetText("minimap dimensions")

        width_slider = create_slider_input(minimap_panel, "minimap width:", "minimap_width", 100, 600, 1,
            function(val)
                sfui.minimap.update_dimensions(val, nil)
            end, "exact width of the minimap in pixels.")
        width_slider:SetPoint("TOPLEFT", dim_header, "BOTTOMLEFT", 0, -10)

        height_slider = create_slider_input(minimap_panel, "minimap height:", "minimap_height", 100, 600, 1,
            function(val)
                sfui.minimap.update_dimensions(nil, val)
            end, "exact height of the minimap in pixels.")
        height_slider:SetPoint("LEFT", width_slider, "RIGHT", 10, 0)

        update_dim_controls()

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
            update_dim_controls()
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
            { text = "bottom right (default)", value = "BOTTOMRIGHT" },
            { text = "bottom left", value = "BOTTOMLEFT" },
            { text = "bottom", value = "BOTTOM" },
            { text = "top right", value = "TOPRIGHT" },
            { text = "top left", value = "TOPLEFT" },
            { text = "top", value = "TOP" },
            { text = "center", value = "CENTER" },
        }

        local cur_anchor = (SfuiDB and SfuiDB.minimap_point) or (sfui.config.minimap and sfui.config.minimap.point) or "BOTTOMRIGHT"
        local anchor_dropdown = create_dropdown(minimap_panel, 180, anchor_options, function(val)
            SfuiDB._minimapPositionCustomized = true
            SfuiDB.minimap_point = val
            SfuiDB.minimap_relative_point = val
            sfui.minimap.update_position()
        end, cur_anchor)
        anchor_dropdown:SetPoint("LEFT", anchor_label, "RIGHT", 10, 0)
        anchor_dropdown.tooltip = "screen anchor corner for the minimap."

        local map_x_slider = create_slider_input(minimap_panel, "offset x:", "minimap_x", -2500, 2500, 1,
            function(val)
                SfuiDB._minimapPositionCustomized = true
                sfui.minimap.update_position(val, nil)
            end, "horizontal offset of the minimap.")
        map_x_slider:SetPoint("TOPLEFT", anchor_label, "BOTTOMLEFT", 0, -14)

        local map_y_slider = create_slider_input(minimap_panel, "offset y:", "minimap_y", -2500, 2500, 1,
            function(val)
                SfuiDB._minimapPositionCustomized = true
                sfui.minimap.update_position(nil, val)
            end, "vertical offset of the minimap.")
        map_y_slider:SetPoint("LEFT", map_x_slider, "RIGHT", 10, 0)

        local reset_map_pos_btn = CreateFlatButton(minimap_panel, "reset position", 120, 22)
        reset_map_pos_btn:SetPoint("TOPLEFT", map_x_slider, "BOTTOMLEFT", 0, -10)
        reset_map_pos_btn:SetScript("OnClick", function()
            local defPoint = (sfui.config.minimap and sfui.config.minimap.point) or "BOTTOMRIGHT"
            local defX = (sfui.config.minimap and sfui.config.minimap.x) or 0
            local defY = (sfui.config.minimap and sfui.config.minimap.y) or 35
            SfuiDB._minimapPositionCustomized = nil
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
            local def = sfui.config.minimap and sfui.config.minimap.button_bar
            local defX = (def and def.defaultX) or 0
            local defY = (def and def.defaultY) or 30
            SfuiDB.minimap_button_x = defX
            SfuiDB.minimap_button_y = defY
            pos_x_slider:SetSliderValue(defX)
            pos_y_slider:SetSliderValue(defY)
            sfui.minimap.update_button_bar_position()
        end)

        local loc_header = minimap_panel:CreateFontString(nil, "OVERLAY", g.font)
        loc_header:SetPoint("TOPLEFT", reset_pos_btn, "BOTTOMLEFT", 0, -18)
        loc_header:SetTextColor(white[1], white[2], white[3])
        loc_header:SetText("location text position")

        local loc_x_slider = create_slider_input(minimap_panel, "offset x:", "minimap_zone_x", -500, 500, 1,
            function(val)
                if SfuiDB then SfuiDB._minimapZoneCustomized = true end
                sfui.minimap.update_location_bar(val, nil)
            end, "horizontal offset of the location text.")
        loc_x_slider:SetPoint("TOPLEFT", loc_header, "BOTTOMLEFT", 0, -10)

        local loc_y_slider = create_slider_input(minimap_panel, "offset y:", "minimap_zone_y", -500, 500, 1,
            function(val)
                if SfuiDB then SfuiDB._minimapZoneCustomized = true end
                sfui.minimap.update_location_bar(nil, val)
            end, "vertical offset of the location text from the top of the minimap.")
        loc_y_slider:SetPoint("LEFT", loc_x_slider, "RIGHT", 10, 0)

        local reset_loc_btn = CreateFlatButton(minimap_panel, "reset position", 120, 22)
        reset_loc_btn:SetPoint("TOPLEFT", loc_x_slider, "BOTTOMLEFT", 0, -10)
        reset_loc_btn:SetScript("OnClick", function()
            local defX = (sfui.config.minimap and sfui.config.minimap.zone_x) or 0
            local defY = (sfui.config.minimap and sfui.config.minimap.zone_y) or 35
            if SfuiDB then
                SfuiDB._minimapZoneCustomized = nil
                SfuiDB.minimap_zone_x = defX
                SfuiDB.minimap_zone_y = defY
            end
            loc_x_slider:SetSliderValue(defX)
            loc_y_slider:SetSliderValue(defY)
            sfui.minimap.update_location_bar(defX, defY)
        end)
    end,
})
