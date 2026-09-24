local addonName, addon = ...
sfui = sfui or {}
sfui.options = sfui.options or {}

local g = sfui.config
local common = sfui.common

local CreateFrame = _G.CreateFrame
local isClassic = (sfui.compat and sfui.compat.is_classic)

sfui.options.RegisterTab({
    id = "automation",
    name = "automation",
    build = function(automation_panel, tab_button, options_frame)
        local CreateFlatButton = common.create_flat_button
        local create_checkbox = common.create_checkbox
        local create_slider_input = common.create_slider_input
        local white = sfui.config.colors.white

        local COL_OFFSET_X = 265
        local SECTION_GAP = 22

        -- ── 1. General Automation ─────────────────────────────────────────────
        local general_header = automation_panel:CreateFontString(nil, "OVERLAY", g.font)
        general_header:SetPoint("TOPLEFT", 15, -15)
        general_header:SetTextColor(white[1], white[2], white[3])
        general_header:SetText("general automation")

        local auto_role_cb = create_checkbox(automation_panel, "auto confirm role checks", "auto_role_check", nil,
            "automatically selects and accepts the role check when a group leader signs up.")
        auto_role_cb:SetPoint("TOPLEFT", general_header, "BOTTOMLEFT", 0, -10)

        local auto_sell_cb = create_checkbox(automation_panel, "auto-sell greys", "autoSellGreys", nil,
            "automatically sells all grey items when opening a merchant.")
        auto_sell_cb:SetPoint("LEFT", auto_role_cb, "LEFT", COL_OFFSET_X, 0)

        local auto_sign_cb = create_checkbox(automation_panel, "auto sign lfg", "auto_sign_lfg", nil,
            "enables double-click signing for premade groups in the lfg tool. hold shift to bypass.")
        auto_sign_cb:SetPoint("TOPLEFT", auto_role_cb, "BOTTOMLEFT", 0, -10)

        local auto_repair_cb = create_checkbox(automation_panel, "auto-repair", "autoRepair", nil,
            "automatically repairs gear (guild first, skips if blacksmith hammer available).")
        auto_repair_cb:SetPoint("LEFT", auto_sign_cb, "LEFT", COL_OFFSET_X, 0)

        -- ── 2. Dungeons, Raids & Grouping ─────────────────────────────────────
        local dungeon_header = automation_panel:CreateFontString(nil, "OVERLAY", g.font)
        dungeon_header:SetPoint("TOPLEFT", auto_sign_cb, "BOTTOMLEFT", 0, -SECTION_GAP)
        dungeon_header:SetTextColor(white[1], white[2], white[3])
        dungeon_header:SetText("dungeons, raids & grouping")

        local auto_log_cb = create_checkbox(automation_panel, "auto combat log", "autoCombatLog", function(checked)
            if sfui.logs and sfui.logs.set_enabled then
                sfui.logs.set_enabled(checked)
            end
        end, isClassic and "automatically start/stop combat logging when entering raids." or "automatically start/stop combat logging when entering mythic+ and raids.")
        auto_log_cb:SetPoint("TOPLEFT", dungeon_header, "BOTTOMLEFT", 0, -10)

        local last_dungeon_anchor = auto_log_cb

        if not isClassic then
            if SfuiDB.keystoneReminder == nil then SfuiDB.keystoneReminder = true end
            local keystone_cb = create_checkbox(automation_panel, "keystone location reminder", "keystoneReminder", nil,
                "prints the dungeon name and key level to chat when a mythic+ invite is accepted, and again when the group fills.")
            keystone_cb:SetPoint("LEFT", auto_log_cb, "LEFT", COL_OFFSET_X, 0)

            if SfuiDB.autoLfgDungeonDefaults == nil then SfuiDB.autoLfgDungeonDefaults = true end
            local lfg_dungeon_cb = create_checkbox(automation_panel, "LFG: auto M+ & Competitive", "autoLfgDungeonDefaults", nil,
                "automatically selects Mythic+ Keystone difficulty and Competitive playstyle when creating a dungeon group in Group Finder.")
            lfg_dungeon_cb:SetPoint("TOPLEFT", auto_log_cb, "BOTTOMLEFT", 0, -10)

            if SfuiDB.ahCurrentExpansionFilter == nil then SfuiDB.ahCurrentExpansionFilter = true end
            local ah_expansion_cb = create_checkbox(automation_panel, "AH: current expansion only", "ahCurrentExpansionFilter", nil,
                "automatically enables the \"current expansion only\" filter every time you open the auction house.")
            ah_expansion_cb:SetPoint("LEFT", lfg_dungeon_cb, "LEFT", COL_OFFSET_X, 0)

            if SfuiDB.autoDungeonPortalPopup == nil then SfuiDB.autoDungeonPortalPopup = true end
            local portal_popup_cb = create_checkbox(automation_panel, "dungeon teleport popup", "autoDungeonPortalPopup", nil,
                "shows a clickable dungeon teleport popup when a mythic+ group is formed.")
            portal_popup_cb:SetPoint("TOPLEFT", lfg_dungeon_cb, "BOTTOMLEFT", 0, -10)

            local test_portal_btn = CreateFlatButton(automation_panel, "test preview", 100, 20)
            test_portal_btn:SetPoint("LEFT", portal_popup_cb, "LEFT", COL_OFFSET_X, 0)
            test_portal_btn:SetScript("OnClick", function()
                if sfui.portals and sfui.portals.TestPortalPopup then
                    sfui.portals.TestPortalPopup()
                end
            end)

            if SfuiDB.portalPopupOnlyWhenFull == nil then SfuiDB.portalPopupOnlyWhenFull = true end
            local portal_full_cb = create_checkbox(automation_panel, "only when group is full (5/5)", "portalPopupOnlyWhenFull", nil,
                "when enabled, the teleport popup only appears when the 5th member joins; otherwise it also shows immediately upon accepting an invite.")
            portal_full_cb:SetPoint("TOPLEFT", portal_popup_cb, "BOTTOMLEFT", 0, -10)

            local portal_x_slider = create_slider_input(automation_panel, "teleport popup x:", "dungeonPortalPopupX", -1000, 1000, 1, function(val)
                local portals = sfui.portals
                if portals and portals.UpdatePortalPopupPosition then
                    portals.UpdatePortalPopupPosition()
                end
            end, "horizontal offset from screen center", 220)
            portal_x_slider:SetPoint("TOPLEFT", portal_full_cb, "BOTTOMLEFT", 0, -12)

            local portal_y_slider = create_slider_input(automation_panel, "teleport popup y:", "dungeonPortalPopupY", -1000, 1000, 1, function(val)
                local portals = sfui.portals
                if portals and portals.UpdatePortalPopupPosition then
                    portals.UpdatePortalPopupPosition()
                end
            end, "vertical offset from screen center", 220)
            portal_y_slider:SetPoint("LEFT", portal_x_slider, "LEFT", COL_OFFSET_X, 0)

            local reset_portal_pos_btn = CreateFlatButton(automation_panel, "reset position", 120, 22)
            reset_portal_pos_btn:SetPoint("TOPLEFT", portal_x_slider, "BOTTOMLEFT", 0, -12)
            reset_portal_pos_btn:SetScript("OnClick", function()
                local def = (sfui.config.portals and sfui.config.portals.defaultPopupPosition) or { x = 0, y = 200 }
                SfuiDB.dungeonPortalPopupX = def.x
                SfuiDB.dungeonPortalPopupY = def.y
                portal_x_slider:SetSliderValue(def.x)
                portal_y_slider:SetSliderValue(def.y)
                local portals = sfui.portals
                if portals and portals.UpdatePortalPopupPosition then
                    portals.UpdatePortalPopupPosition()
                end
            end)

            last_dungeon_anchor = reset_portal_pos_btn
        end

        -- ── 3. Master's Hammer Settings (Retail Only) ─────────────────────────
        if not isClassic then
            local hammer_header = automation_panel:CreateFontString(nil, "OVERLAY", g.font)
            hammer_header:SetPoint("TOPLEFT", last_dungeon_anchor, "BOTTOMLEFT", 0, -SECTION_GAP)
            hammer_header:SetTextColor(white[1], white[2], white[3])
            hammer_header:SetText("master's hammer settings")

            local enable_hammer_cb = create_checkbox(automation_panel, "enable master's hammer", "enableMasterHammer", function(checked)
                local hammer = sfui.hammer or sfui.automation
                if hammer and hammer.update_hammer_popup then
                    hammer.update_hammer_popup()
                end
            end, "enables master's hammer prompt when durability drops below threshold.")
            enable_hammer_cb:SetPoint("TOPLEFT", hammer_header, "BOTTOMLEFT", 0, -10)

            local function GetHammerModeOptions()
                return {
                    { text = "Popup Button Only", value = "popup" },
                    { text = "Automatic Use", value = "auto" },
                    { text = "Popup + Auto Fallback", value = "both" },
                }
            end

            local mode_label = automation_panel:CreateFontString(nil, "OVERLAY", g.font)
            mode_label:SetPoint("LEFT", enable_hammer_cb, "LEFT", COL_OFFSET_X, 0)
            mode_label:SetText("hammer mode:")

            local mode_dropdown = common.create_dropdown(automation_panel, 140, GetHammerModeOptions, function(val)
                SfuiDB.hammerMode = val
                local hammer = sfui.hammer or sfui.automation
                if hammer and hammer.update_hammer_popup then
                    hammer.update_hammer_popup()
                end
            end, SfuiDB.hammerMode or "popup")
            mode_dropdown:SetPoint("LEFT", mode_label, "RIGHT", 5, 0)

            local threshold_slider = create_slider_input(automation_panel, "durability threshold:", "hammerThreshold", 10, 80, 5, function(val)
                local hammer = sfui.hammer or sfui.automation
                if hammer and hammer.update_hammer_popup then
                    hammer.update_hammer_popup()
                end
            end, "prompt or auto-use hammer when durability falls below this percentage", 220)
            threshold_slider:SetPoint("TOPLEFT", enable_hammer_cb, "BOTTOMLEFT", 0, -12)

            local icon_size_slider = create_slider_input(automation_panel, "repair icon size:", "repairIconSize", 20, 64, 2, function(val)
                local hammer = sfui.hammer or sfui.automation
                if hammer and hammer.update_popup_style then
                    hammer.update_popup_style()
                end
            end, "size of the repair button in pixels", 220)
            icon_size_slider:SetPoint("LEFT", threshold_slider, "LEFT", COL_OFFSET_X, 0)

            local icon_x_slider = create_slider_input(automation_panel, "icon x:", "repairIconX", -1000, 1000, 1, function(val)
                local hammer = sfui.hammer or sfui.automation
                if hammer and hammer.update_popup_style then
                    hammer.update_popup_style()
                end
            end, "horizontal offset of the repair icon", 220)
            icon_x_slider:SetPoint("TOPLEFT", threshold_slider, "BOTTOMLEFT", 0, -12)

            local icon_y_slider = create_slider_input(automation_panel, "icon y:", "repairIconY", -1000, 1000, 1, function(val)
                local hammer = sfui.hammer or sfui.automation
                if hammer and hammer.update_popup_style then
                    hammer.update_popup_style()
                end
            end, "vertical offset of the repair icon", 220)
            icon_y_slider:SetPoint("LEFT", icon_x_slider, "LEFT", COL_OFFSET_X, 0)

            local reset_hammer_pos_btn = CreateFlatButton(automation_panel, "reset position", 120, 22)
            reset_hammer_pos_btn:SetPoint("TOPLEFT", icon_x_slider, "BOTTOMLEFT", 0, -12)
            reset_hammer_pos_btn:SetScript("OnClick", function()
                local def = (sfui.config.masterHammer and sfui.config.masterHammer.defaultPosition) or { x = 0, y = 0 }
                SfuiDB.repairIconX = def.x
                SfuiDB.repairIconY = def.y
                icon_x_slider:SetSliderValue(def.x)
                icon_y_slider:SetSliderValue(def.y)
                local hammer = sfui.hammer or sfui.automation
                if hammer and hammer.update_popup_style then
                    hammer.update_popup_style()
                end
                if sfui.common and sfui.common.print then
                    sfui.common.print("sfui: repair button position reset to center (" .. def.x .. ", " .. def.y .. ").")
                end
            end)

            local test_hammer_btn = CreateFlatButton(automation_panel, "test preview", 120, 22)
            test_hammer_btn:SetPoint("LEFT", reset_hammer_pos_btn, "RIGHT", 10, 0)
            test_hammer_btn:SetScript("OnClick", function(self)
                local hammer = sfui.hammer or sfui.automation
                if hammer and hammer.toggle_test_popup then
                    local active = hammer.toggle_test_popup()
                    self:SetText(active and "hide preview" or "test preview")
                end
            end)
            test_hammer_btn:SetScript("OnShow", function(self)
                local hammer = sfui.hammer or sfui.automation
                local active = hammer and hammer.is_test_mode and hammer.is_test_mode()
                self:SetText(active and "hide preview" or "test preview")
            end)

            sfui.options = sfui.options or {}
            sfui.options.sync_hammer_sliders = function(x, y)
                if icon_x_slider and icon_x_slider.SetSliderValue then
                    icon_x_slider:SetSliderValue(x)
                end
                if icon_y_slider and icon_y_slider.SetSliderValue then
                    icon_y_slider:SetSliderValue(y)
                end
            end

            local color_label = automation_panel:CreateFontString(nil, "OVERLAY", g.font)
            color_label:SetPoint("TOPLEFT", reset_hammer_pos_btn, "BOTTOMLEFT", 0, -14)
            color_label:SetTextColor(white[1], white[2], white[3])
            color_label:SetText("color (#hex):")

            local color_input = CreateFrame("EditBox", nil, automation_panel, "InputBoxTemplate")
            color_input:SetPoint("LEFT", color_label, "RIGHT", 8, 0)
            color_input:SetSize(75, 20)
            color_input:SetAutoFocus(false)
            color_input:SetScript("OnShow", function(self) self:SetText(SfuiDB.repairIconColor or "00FFFF") end)
            color_input:SetScript("OnEnterPressed", function(self)
                local val = self:GetText()
                SfuiDB.repairIconColor = val
                local hammer = sfui.hammer or sfui.automation
                if hammer and hammer.update_popup_style then
                    hammer.update_popup_style()
                end
                self:ClearFocus()
            end)
        end
    end,
})
