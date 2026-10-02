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

        local test_all_btn = CreateFlatButton(castbar_panel, "test preview (both)", 150, 22)
        test_all_btn:SetPoint("LEFT", castbar_header, "RIGHT", 25, 0)
        test_all_btn:SetScript("OnClick", function()
            sfui.castbar.show_test_preview(8)
        end)

        -- Helper to ensure position update is applied immediately to previewed bar
        local function on_pos_changed(unit, key, val)
            notify_setting_changed("castbar", key, val)
            local bar = sfui.castbar and sfui.castbar.bars and sfui.castbar.bars[unit]
            if bar and bar.backdrop and bar.backdrop:IsShown() then
                local cfg = (unit == "player") and (g.castBar or {}) or (g.targetCastBar or {})
                local posX = (unit == "player") and (SfuiDB and SfuiDB.castBarX or cfg.pos.x) or (SfuiDB and SfuiDB.targetCastBarX or cfg.pos.x)
                local posY = (unit == "player") and (SfuiDB and SfuiDB.castBarY or cfg.pos.y) or (SfuiDB and SfuiDB.targetCastBarY or cfg.pos.y)
                bar.backdrop:ClearAllPoints()
                bar.backdrop:SetPoint("BOTTOM", UIParent, "BOTTOM", posX, posY)
            end
        end

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
            on_pos_changed("player", "castBarX", val)
        end)
        player_x_slider:SetPoint("TOPLEFT", enable_player_cb, "BOTTOMLEFT", 0, -10)

        local player_y_slider = create_slider_input(castbar_panel, "y:", "castBarY", -1000, 1000, 1, function(val)
            on_pos_changed("player", "castBarY", val)
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
            on_pos_changed("player", "castBarX", def.x)
            on_pos_changed("player", "castBarY", def.y)
        end)

        local test_player_btn = CreateFlatButton(castbar_panel, "test preview", 100, 20)
        test_player_btn:SetPoint("LEFT", reset_player_cast_btn, "RIGHT", 10, 0)
        test_player_btn:SetScript("OnClick", function()
            sfui.castbar.show_test_preview(8)
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
            on_pos_changed("target", "targetCastBarX", val)
        end)
        target_x_slider:SetPoint("TOPLEFT", enable_target_cb, "BOTTOMLEFT", 0, -10)

        local target_y_slider = create_slider_input(castbar_panel, "y:", "targetCastBarY", -1000, 1000, 1, function(val)
            on_pos_changed("target", "targetCastBarY", val)
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
            on_pos_changed("target", "targetCastBarX", def.x)
            on_pos_changed("target", "targetCastBarY", def.y)
        end)

        local test_target_btn = CreateFlatButton(castbar_panel, "test preview", 100, 20)
        test_target_btn:SetPoint("LEFT", reset_target_cast_btn, "RIGHT", 10, 0)
        test_target_btn:SetScript("OnClick", function()
            sfui.castbar.show_test_preview(8)
        end)
    end,
})
