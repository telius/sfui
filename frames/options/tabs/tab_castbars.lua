local addonName, addon = ...
sfui = sfui or {}
sfui.options = sfui.options or {}

local g = sfui.config
local common = sfui.common

sfui.options.RegisterTab({
    id = "castbars",
    name = "castbars",
    build = function(castbar_panel, tab_button, options_frame)
        local CreateFlatButton = common.create_flat_button
        local create_checkbox = common.create_checkbox
        local create_slider_input = common.create_slider_input
        local white = sfui.config.colors.white
        local notify_setting_changed = sfui.options.notify_setting_changed

        local castbar_header = castbar_panel:CreateFontString(nil, "OVERLAY", g.font)
        castbar_header:SetPoint("TOPLEFT", 15, -15)
        castbar_header:SetTextColor(white[1], white[2], white[3])
        castbar_header:SetText("castbar settings")

        -- Player Castbar
        local player_header = castbar_panel:CreateFontString(nil, "OVERLAY", g.font)
        player_header:SetPoint("TOPLEFT", castbar_header, "BOTTOMLEFT", 0, -20)
        player_header:SetTextColor(white[1], white[2], white[3])
        player_header:SetText("player castbar")

        local enable_player_cb = create_checkbox(castbar_panel, "enable", "castBarEnabled", function(checked)
            notify_setting_changed("castbar", "castBarEnabled", checked)
        end, "toggles the player castbar.")
        enable_player_cb:SetPoint("TOPLEFT", player_header, "BOTTOMLEFT", 0, -10)

        local player_x_slider = create_slider_input(castbar_panel, "x:", "castBarX", -1000, 1000, 1, function(val)
            notify_setting_changed("castbar", "castBarX", val)
        end)
        player_x_slider:SetPoint("TOPLEFT", enable_player_cb, "BOTTOMLEFT", 0, -10)

        local player_y_slider = create_slider_input(castbar_panel, "y:", "castBarY", -1000, 1000, 1, function(val)
            notify_setting_changed("castbar", "castBarY", val)
        end)
        player_y_slider:SetPoint("LEFT", player_x_slider, "RIGHT", 10, 0)

        local reset_player_cast_btn = CreateFlatButton(castbar_panel, "reset position", 120, 20)
        reset_player_cast_btn:SetPoint("TOPLEFT", player_x_slider, "BOTTOMLEFT", 0, -10)
        reset_player_cast_btn:SetScript("OnClick", function()
            local def = sfui.config.castBar.pos
            SfuiDB.castBarX = def.x
            SfuiDB.castBarY = def.y
            player_x_slider:SetSliderValue(def.x)
            player_y_slider:SetSliderValue(def.y)
            notify_setting_changed("castbar", "castBarX", def.x)
            notify_setting_changed("castbar", "castBarY", def.y)
        end)

        -- Target Castbar
        local target_header = castbar_panel:CreateFontString(nil, "OVERLAY", g.font)
        target_header:SetPoint("TOPLEFT", reset_player_cast_btn, "BOTTOMLEFT", 0, -20)
        target_header:SetTextColor(white[1], white[2], white[3])
        target_header:SetText("target castbar")

        local enable_target_cb = create_checkbox(castbar_panel, "enable", "targetCastBarEnabled", function(checked)
            notify_setting_changed("castbar", "targetCastBarEnabled", checked)
        end, "toggles the target castbar.")
        enable_target_cb:SetPoint("TOPLEFT", target_header, "BOTTOMLEFT", 0, -10)

        local target_x_slider = create_slider_input(castbar_panel, "x:", "targetCastBarX", -1000, 1000, 1, function(val)
            notify_setting_changed("castbar", "targetCastBarX", val)
        end)
        target_x_slider:SetPoint("TOPLEFT", enable_target_cb, "BOTTOMLEFT", 0, -10)

        local target_y_slider = create_slider_input(castbar_panel, "y:", "targetCastBarY", -1000, 1000, 1, function(val)
            notify_setting_changed("castbar", "targetCastBarY", val)
        end)
        target_y_slider:SetPoint("LEFT", target_x_slider, "RIGHT", 10, 0)

        local reset_target_cast_btn = CreateFlatButton(castbar_panel, "reset position", 120, 20)
        reset_target_cast_btn:SetPoint("TOPLEFT", target_x_slider, "BOTTOMLEFT", 0, -10)
        reset_target_cast_btn:SetScript("OnClick", function()
            local def = sfui.config.targetCastBar.pos
            SfuiDB.targetCastBarX = def.x
            SfuiDB.targetCastBarY = def.y
            target_x_slider:SetSliderValue(def.x)
            target_y_slider:SetSliderValue(def.y)
            notify_setting_changed("castbar", "targetCastBarX", def.x)
            notify_setting_changed("castbar", "targetCastBarY", def.y)
        end)
    end,
})
