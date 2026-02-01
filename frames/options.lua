local c = sfui.config.options_panel
local g = sfui.config

local UIDropDownMenu_Initialize = UIDropDownMenu_Initialize
local UIDropDownMenu_CreateInfo = UIDropDownMenu_CreateInfo
local UIDropDownMenu_AddButton = UIDropDownMenu_AddButton
local UIDropDownMenu_SetSelectedValue = UIDropDownMenu_SetSelectedValue
local UIDropDownMenu_SetWidth = UIDropDownMenu_SetWidth
local wipe = wipe
local LibStub = LibStub
local CreateFrame = CreateFrame
local UIParent = UIParent

local frame
local function select_tab(selected_tab_button)
    if not frame or not frame.tabs then return end

    for _, tab_data in ipairs(frame.tabs) do
        tab_data.button:GetFontString():SetTextColor(c.tabs.color.r, c.tabs.color.g, c.tabs.color.b)
        tab_data.panel:Hide()
    end
    selected_tab_button.panel:Show()
    selected_tab_button:GetFontString():SetTextColor(c.tabs.selected_color.r, c.tabs.selected_color.g,
        c.tabs.selected_color.b)
    frame.selected_tab = selected_tab_button
end

function sfui.create_options_panel()
    if frame then return end

    local CreateFlatButton = sfui.common.create_flat_button
    local white = sfui.config.colors.white

    frame = CreateFrame("Frame", "sfui_options_frame", UIParent, "BackdropTemplate")
    frame:SetSize(c.width, c.height)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({ bgFile = g.textures.white, tile = true, tileSize = 32 })
    frame:SetBackdropColor(c.backdrop_color.r, c.backdrop_color.g, c.backdrop_color.b, c.backdrop_color.a)
    frame:Hide(); frame.tabs = {}

    local header_text = frame:CreateFontString(nil, "OVERLAY", g.font_large)
    header_text:SetPoint("TOP", frame, "TOP", 0, -10)
    header_text:SetTextColor(g.header_color[1], g.header_color[2], g.header_color[3])
    header_text:SetText(g.title .. " v" .. g.version)

    local addon_icon = frame:CreateTexture(nil, "ARTWORK")
    addon_icon:SetSize(32, 32); addon_icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -5)
    addon_icon:SetTexture("Interface\\Icons\\Spell_shadow_deathcoil")

    local close_button = CreateFlatButton(frame, "X", 24, 24)
    close_button:SetPoint("TOPRIGHT", -5, -5)
    close_button:SetScript("OnClick", function()
        frame:Hide()
    end)

    local function create_checkbox(parent, label, dbKey, onClickFunc, tooltip)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetHitRectInsets(0, -100, 0, 0)
        cb.text:SetText(label)
        cb:SetScript("OnClick", function(self)
            local checked = self:GetChecked()
            SfuiDB[dbKey] = checked
            if onClickFunc then onClickFunc(checked) end
        end)
        cb:SetScript("OnShow", function(self)
            self:SetChecked(SfuiDB[dbKey])
        end)
        if tooltip then
            cb:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(tooltip)
                GameTooltip:Show()
            end)
            cb:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
        end
        return cb
    end

    local function create_cvar_checkbox(parent, label, cvar, tooltip)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetHitRectInsets(0, -100, 0, 0)
        cb.text:SetText(label)
        cb:SetScript("OnClick", function(self)
            local checked = self:GetChecked()
            C_CVar.SetCVar(cvar, checked and "1" or "0")
            SfuiDB[cvar] = checked -- Persist to DB
        end)
        cb:SetScript("OnShow", function(self)
            -- Check DB first for persistence, fallback to current CVar state
            if SfuiDB[cvar] ~= nil then
                self:SetChecked(SfuiDB[cvar])
            else
                self:SetChecked(C_CVar.GetCVarBool(cvar))
            end
        end)
        if tooltip then
            cb:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(tooltip)
                GameTooltip:Show()
            end)
            cb:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
        end
        return cb
    end

    local function create_slider(parent, label, dbKey, minVal, maxVal, step, onValueChangedFunc)
        local name = "sfui_option_slider_" .. dbKey
        local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
        slider:SetOrientation("HORIZONTAL")
        slider:SetHeight(20)
        slider:SetWidth(150)
        slider:SetMinMaxValues(minVal, maxVal)
        slider:SetValueStep(step)
        slider:SetObeyStepOnDrag(true)

        getglobal(slider:GetName() .. 'Low'):SetText(minVal)
        getglobal(slider:GetName() .. 'High'):SetText(maxVal)
        getglobal(slider:GetName() .. 'Text'):SetText(label)

        slider:SetScript("OnValueChanged", function(self, value)
            SfuiDB[dbKey] = value
            if onValueChangedFunc then onValueChangedFunc(value) end
        end)

        slider:SetScript("OnShow", function(self)
            self:SetValue(SfuiDB[dbKey] or minVal) -- Default to minVal if nil, or handle specifically
        end)
        return slider
    end

    local function on_tab_click(self)
        select_tab(self)
    end

    local function on_tab_enter(self)
        self:GetFontString():SetTextColor(c.tabs.highlight_color.r, c.tabs.highlight_color.g, c.tabs.highlight_color.b)
    end

    local function on_tab_leave(self)
        if self == frame.selected_tab then
            self:GetFontString():SetTextColor(c.tabs.selected_color.r, c.tabs.selected_color.g, c.tabs.selected_color.b)
        else
            self:GetFontString():SetTextColor(c.tabs.color.r, c.tabs.color.g, c.tabs.color.b)
        end
    end

    local function create_tab(name)
        local tab_button = CreateFrame("Button", "sfui_options_tab_" .. name, frame)
        tab_button:SetSize(c.tabs.width, c.tabs.height)
        tab_button:SetText(name)

        local font_string = tab_button:GetFontString()
        font_string:SetFontObject(g.font)
        font_string:SetJustifyH("LEFT")
        font_string:SetJustifyV("MIDDLE")
        font_string:SetPoint("LEFT", tab_button, "LEFT", 5, 0)
        font_string:SetTextColor(c.tabs.color.r, c.tabs.color.g, c.tabs.color.b)

        local content_panel = CreateFrame("Frame", "sfui_options_panel_" .. name, frame, "BackdropTemplate")
        content_panel:SetPoint("TOPLEFT", frame, "TOPLEFT", c.tabs.width + 20, -40)
        content_panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 5)
        content_panel:SetBackdrop({ bgFile = g.textures.white, tile = true, tileSize = 32 })
        content_panel:SetBackdropColor(0, 0, 0, 0.5)
        content_panel:Hide()

        tab_button.panel = content_panel

        tab_button:SetScript("OnClick", on_tab_click)
        tab_button:SetScript("OnEnter", on_tab_enter)
        tab_button:SetScript("OnLeave", on_tab_leave)

        table.insert(frame.tabs, { button = tab_button, panel = content_panel })
        return content_panel, tab_button
    end

    local last_tab_button
    local main_panel, main_tab_button = create_tab("main")
    main_tab_button:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -40)
    last_tab_button = main_tab_button

    local automation_panel, automation_tab_button = create_tab("automation")
    automation_tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, -10) -- distinct gap from main
    last_tab_button = automation_tab_button

    local bars_panel, bars_tab_button = create_tab("bars")
    bars_tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, 5)
    last_tab_button = bars_tab_button

    local castbar_panel, castbar_tab_button = create_tab("castbars")
    castbar_tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, 5)
    last_tab_button = castbar_tab_button

    local castbar_header = castbar_panel:CreateFontString(nil, "OVERLAY", g.font)
    castbar_header:SetPoint("TOPLEFT", 15, -15)
    castbar_header:SetTextColor(white[1], white[2], white[3])
    castbar_header:SetText("castbar settings")

    -- Player Castbar --
    local player_header = castbar_panel:CreateFontString(nil, "OVERLAY", g.font)
    player_header:SetPoint("TOPLEFT", castbar_header, "BOTTOMLEFT", 0, -20)
    player_header:SetText("player castbar")

    local enable_player_cb = create_checkbox(castbar_panel, "enable", "castBarEnabled", function(checked)
        if sfui.castbar and sfui.castbar.update_settings then sfui.castbar.update_settings() end
    end, "toggles the player castbar.")
    enable_player_cb:SetPoint("TOPLEFT", player_header, "BOTTOMLEFT", 0, -10)

    local player_x_label = castbar_panel:CreateFontString(nil, "OVERLAY", g.font)
    player_x_label:SetPoint("TOPLEFT", enable_player_cb, "BOTTOMLEFT", 0, -10)
    player_x_label:SetText("x:")

    local player_x_input = CreateFrame("EditBox", nil, castbar_panel, "InputBoxTemplate")
    player_x_input:SetSize(60, 20)
    player_x_input:SetPoint("LEFT", player_x_label, "RIGHT", 5, 0)
    player_x_input:SetAutoFocus(false)
    player_x_input:SetText(tostring(SfuiDB.castBarX or 0))
    player_x_input:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then
            SfuiDB.castBarX = val
            if sfui.castbar and sfui.castbar.update_settings then sfui.castbar.update_settings() end
        end
        self:ClearFocus()
    end)

    local player_y_label = castbar_panel:CreateFontString(nil, "OVERLAY", g.font)
    player_y_label:SetPoint("LEFT", player_x_input, "RIGHT", 15, 0)
    player_y_label:SetText("y:")

    local player_y_input = CreateFrame("EditBox", nil, castbar_panel, "InputBoxTemplate")
    player_y_input:SetSize(60, 20)
    player_y_input:SetPoint("LEFT", player_y_label, "RIGHT", 5, 0)
    player_y_input:SetAutoFocus(false)
    player_y_input:SetText(tostring(SfuiDB.castBarY or 140))
    player_y_input:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then
            SfuiDB.castBarY = val
            if sfui.castbar and sfui.castbar.update_settings then sfui.castbar.update_settings() end
        end
        self:ClearFocus()
    end)

    -- Target Castbar --
    local target_header = castbar_panel:CreateFontString(nil, "OVERLAY", g.font)
    target_header:SetPoint("TOPLEFT", player_x_label, "BOTTOMLEFT", 0, -30)
    target_header:SetText("target castbar")

    local enable_target_cb = create_checkbox(castbar_panel, "enable", "targetCastBarEnabled", function(checked)
        if sfui.castbar and sfui.castbar.update_settings then sfui.castbar.update_settings() end
    end, "toggles the target castbar.")
    enable_target_cb:SetPoint("TOPLEFT", target_header, "BOTTOMLEFT", 0, -10)

    local target_x_label = castbar_panel:CreateFontString(nil, "OVERLAY", g.font)
    target_x_label:SetPoint("TOPLEFT", enable_target_cb, "BOTTOMLEFT", 0, -10)
    target_x_label:SetText("x:")

    local target_x_input = CreateFrame("EditBox", nil, castbar_panel, "InputBoxTemplate")
    target_x_input:SetSize(60, 20)
    target_x_input:SetPoint("LEFT", target_x_label, "RIGHT", 5, 0)
    target_x_input:SetAutoFocus(false)
    target_x_input:SetText(tostring(SfuiDB.targetCastBarX or 0))
    target_x_input:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then
            SfuiDB.targetCastBarX = val
            if sfui.castbar and sfui.castbar.update_settings then sfui.castbar.update_settings() end
        end
        self:ClearFocus()
    end)

    local target_y_label = castbar_panel:CreateFontString(nil, "OVERLAY", g.font)
    target_y_label:SetPoint("LEFT", target_x_input, "RIGHT", 15, 0)
    target_y_label:SetText("y:")

    local target_y_input = CreateFrame("EditBox", nil, castbar_panel, "InputBoxTemplate")
    target_y_input:SetSize(60, 20)
    target_y_input:SetPoint("LEFT", target_y_label, "RIGHT", 5, 0)
    target_y_input:SetAutoFocus(false)
    target_y_input:SetText(tostring(SfuiDB.targetCastBarY or 480))
    target_y_input:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then
            SfuiDB.targetCastBarY = val
            if sfui.castbar and sfui.castbar.update_settings then sfui.castbar.update_settings() end
        end
        self:ClearFocus()
    end)

    local sct_panel, sct_tab_button = create_tab("combat text")
    sct_tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, 5)
    last_tab_button = sct_tab_button

    local currency_items_panel, currency_tab_button = create_tab("currency/items")
    currency_tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, 5)
    last_tab_button = currency_tab_button

    local merchant_panel, merchant_tab_button = create_tab("merchant")
    merchant_tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, 5)
    last_tab_button = merchant_tab_button

    local minimap_panel, minimap_tab_button = create_tab("minimap")
    minimap_tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, 5)
    last_tab_button = minimap_tab_button

    local reminders_panel, reminders_tab_button = create_tab("reminders")
    reminders_tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, 5)
    last_tab_button = reminders_tab_button

    local research_panel, research_tab_button = create_tab("research")
    research_tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, 5)
    last_tab_button = research_tab_button

    local debug_panel, debug_tab_button = create_tab("debug")
    debug_tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, -10) -- distinct gap before debug
    last_tab_button = debug_tab_button

    local main_text = main_panel:CreateFontString(nil, "OVERLAY", g.font)
    main_text:SetPoint("TOPLEFT", 15, -15)
    main_text:SetTextColor(white[1], white[2], white[3])
    main_text:SetText("welcome to sfui. please select a category on the left.")



    local reload_button = CreateFlatButton(main_panel, "reload ui", 100, 22)
    reload_button:SetPoint("TOPLEFT", main_text, "BOTTOMLEFT", 0, -20)
    reload_button:SetScript("OnClick", function() C_UI.Reload() end)

    local hide_minimap_icon_cb = create_checkbox(main_panel, "hide minimap icon", "minimap_icon.hide", function(checked)
        local icon = LibStub:GetLibrary("LibDBIcon-1.0", true)
        if icon then
            if checked then
                icon:Hide("sfui")
            else
                icon:Show("sfui")
            end
        end
    end, "hides the sfui minimap icon.")
    hide_minimap_icon_cb:SetPoint("TOPLEFT", reload_button, "BOTTOMLEFT", 0, -20)

    local vehicle_header = main_panel:CreateFontString(nil, "OVERLAY", g.font)
    vehicle_header:SetPoint("TOPLEFT", hide_minimap_icon_cb, "BOTTOMLEFT", 0, -30)
    vehicle_header:SetTextColor(white[1], white[2], white[3])
    vehicle_header:SetText("vehicle settings")

    local disable_vehicle_cb = create_checkbox(main_panel, "disable vehicle ui", "disableVehicle", nil,
        "restores the default wow vehicle/overlay bar.")
    disable_vehicle_cb:SetPoint("TOPLEFT", vehicle_header, "BOTTOMLEFT", 0, -10)

    local texture_label = main_panel:CreateFontString(nil, "OVERLAY", g.font)
    texture_label:SetPoint("TOPLEFT", disable_vehicle_cb, "BOTTOMLEFT", 0, -20)
    texture_label:SetText("bar texture:")

    local dropdown = CreateFrame("Frame", "sfui_options_texture_dropdown", main_panel, "UIDropDownMenuTemplate")
    dropdown:SetPoint("LEFT", texture_label, "RIGHT", 10, 0)

    local function on_texture_select(self)
        local textureName = self.value
        SfuiDB.barTexture = textureName

        local LSM = LibStub("LibSharedMedia-3.0", true)
        local texturePath = LSM and LSM:Fetch("statusbar", textureName) or "Interface/Buttons/WHITE8X8"

        if sfui.bars and sfui.bars.set_bar_texture then
            sfui.bars.set_bar_texture(texturePath)
        end
        if sfui.castbar and sfui.castbar.set_bar_texture then
            sfui.castbar.set_bar_texture(texturePath)
        end

        UIDropDownMenu_SetSelectedValue(dropdown, textureName)
    end

    local function initialize_texture_dropdown(self, level)
        local LSM = LibStub("LibSharedMedia-3.0", true)
        local info = UIDropDownMenu_CreateInfo()

        local sortedTextures = {}
        local seen = { ["Flat"] = true }
        table.insert(sortedTextures, "Flat")

        if LSM then
            local textures = LSM:HashTable("statusbar")
            for name, _ in pairs(textures) do
                if not seen[name] then
                    table.insert(sortedTextures, name)
                    seen[name] = true
                end
            end
        end
        table.sort(sortedTextures)

        for _, name in ipairs(sortedTextures) do
            info.text = name
            info.value = name
            info.func = on_texture_select
            info.checked = (SfuiDB.barTexture == name)
            UIDropDownMenu_AddButton(info)
        end
    end

    UIDropDownMenu_Initialize(dropdown, initialize_texture_dropdown)
    UIDropDownMenu_SetSelectedValue(dropdown, SfuiDB.barTexture)
    UIDropDownMenu_SetWidth(dropdown, 150)


    -- 2. Bars Panel
    local bars_header = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
    bars_header:SetPoint("TOPLEFT", 15, -15)
    bars_header:SetTextColor(white[1], white[2], white[3])
    bars_header:SetText("bar settings")

    -- Bar Toggles
    local toggles_header = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
    toggles_header:SetPoint("TOPLEFT", bars_header, "BOTTOMLEFT", 0, -20)
    toggles_header:SetTextColor(white[1], white[2], white[3])
    toggles_header:SetText("bar visibility")

    local health_bar_cb = create_checkbox(bars_panel, "enable health bar", "enableHealthBar", function(checked)
        if sfui.bars and sfui.bars.on_state_changed then sfui.bars:on_state_changed() end
    end, "toggles the health bar.")
    health_bar_cb:SetPoint("TOPLEFT", toggles_header, "BOTTOMLEFT", 0, -10)

    local power_bar_cb = create_checkbox(bars_panel, "enable power bar", "enablePowerBar", function(checked)
        if sfui.bars and sfui.bars.on_state_changed then sfui.bars:on_state_changed() end
    end, "toggles the primary power bar.")
    power_bar_cb:SetPoint("TOPLEFT", health_bar_cb, "BOTTOMLEFT", 0, -10)

    local secondary_power_cb = create_checkbox(bars_panel, "enable secondary power bar", "enableSecondaryPowerBar",
        function(checked)
            if sfui.bars and sfui.bars.on_state_changed then sfui.bars:on_state_changed() end
        end, "toggles the secondary power bar (e.g., chi, holy power).")
    secondary_power_cb:SetPoint("TOPLEFT", power_bar_cb, "BOTTOMLEFT", 0, -10)

    local vigor_bar_cb = create_checkbox(bars_panel, "enable vigor bar", "enableVigorBar", function(checked)
        if sfui.bars and sfui.bars.on_state_changed then sfui.bars:on_state_changed() end
    end, "toggles the vigor bar (skyriding).")
    vigor_bar_cb:SetPoint("TOPLEFT", secondary_power_cb, "BOTTOMLEFT", 0, -10)

    local mount_speed_cb = create_checkbox(bars_panel, "enable mount speed bar", "enableMountSpeedBar", function(checked)
        if sfui.bars and sfui.bars.on_state_changed then sfui.bars:on_state_changed() end
    end, "toggles the mount speed bar (skyriding).")
    mount_speed_cb:SetPoint("TOPLEFT", vigor_bar_cb, "BOTTOMLEFT", 0, -10)

    -- Health Bar Position
    local position_header = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
    position_header:SetPoint("TOPLEFT", mount_speed_cb, "BOTTOMLEFT", 0, -20)
    position_header:SetTextColor(white[1], white[2], white[3])
    position_header:SetText("health bar position")

    local health_x_label = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
    health_x_label:SetPoint("TOPLEFT", position_header, "BOTTOMLEFT", 0, -10)
    health_x_label:SetText("x:")
    health_x_label:SetTextColor(white[1], white[2], white[3])

    local health_x_input = CreateFrame("EditBox", nil, bars_panel, "InputBoxTemplate")
    health_x_input:SetSize(60, 20)
    health_x_input:SetPoint("LEFT", health_x_label, "RIGHT", 5, 0)
    health_x_input:SetAutoFocus(false)
    health_x_input:SetText(tostring(SfuiDB.healthBarX or 0))
    health_x_input:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then
            SfuiDB.healthBarX = val
            if sfui.bars and sfui.bars.update_health_bar_position then
                sfui.bars:update_health_bar_position()
            end
        end
        self:ClearFocus()
    end)

    local health_y_label = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
    health_y_label:SetPoint("LEFT", health_x_input, "RIGHT", 15, 0)
    health_y_label:SetText("y:")
    health_y_label:SetTextColor(white[1], white[2], white[3])

    local health_y_input = CreateFrame("EditBox", nil, bars_panel, "InputBoxTemplate")
    health_y_input:SetSize(60, 20)
    health_y_input:SetPoint("LEFT", health_y_label, "RIGHT", 5, 0)
    health_y_input:SetAutoFocus(false)
    health_y_input:SetText(tostring(SfuiDB.healthBarY or 300))
    health_y_input:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then
            SfuiDB.healthBarY = val
            if sfui.bars and sfui.bars.update_health_bar_position then
                sfui.bars:update_health_bar_position()
            end
        end
        self:ClearFocus()
    end)

    local reset_health_pos_btn = CreateFrame("Button", nil, bars_panel, "UIPanelButtonTemplate")
    reset_health_pos_btn:SetSize(120, 22)
    reset_health_pos_btn:SetPoint("TOPLEFT", health_x_label, "BOTTOMLEFT", 0, -10)
    reset_health_pos_btn:SetText("reset position")
    reset_health_pos_btn:SetScript("OnClick", function()
        SfuiDB.healthBarX = 0
        SfuiDB.healthBarY = 300
        health_x_input:SetText("0")
        health_y_input:SetText("300")
        if sfui.bars and sfui.bars.update_health_bar_position then
            sfui.bars:update_health_bar_position()
        end
    end)

    -- 3. Combat Text Panel (SCT)
    local sct_header = sct_panel:CreateFontString(nil, "OVERLAY", g.font)
    sct_header:SetPoint("TOPLEFT", 15, -15)
    sct_header:SetTextColor(white[1], white[2], white[3])
    sct_header:SetText("blizzard combat text settings")

    local master_cb = create_cvar_checkbox(sct_panel, "enable floating combat text", "enableFloatingCombatText",
        "master toggle for blizzard's floating combat text.")
    master_cb:SetPoint("TOPLEFT", sct_header, "BOTTOMLEFT", 0, -10)

    local damage_cb = create_cvar_checkbox(sct_panel, "show damage", "floatingCombatTextCombatDamage",
        "toggles display of damage numbers over targets.")
    damage_cb:SetPoint("TOPLEFT", master_cb, "BOTTOMLEFT", 0, -5)

    local periodic_cb = create_cvar_checkbox(sct_panel, "show periodic damage (dots)",
        "floatingCombatTextCombatLogPeriodicSpells", "toggles display of periodic damage (dots) numbers.")
    periodic_cb:SetPoint("TOPLEFT", damage_cb, "BOTTOMLEFT", 0, -5)

    local healing_cb = create_cvar_checkbox(sct_panel, "show healing", "floatingCombatTextCombatHealing",
        "toggles display of healing numbers over targets.")
    healing_cb:SetPoint("TOPLEFT", periodic_cb, "BOTTOMLEFT", 0, -5)

    local pet_melee_cb = create_cvar_checkbox(sct_panel, "show pet melee damage", "floatingCombatTextPetMeleeDamage",
        "toggles display of pet melee damage numbers.")
    pet_melee_cb:SetPoint("TOPLEFT", healing_cb, "BOTTOMLEFT", 0, -5)

    local pet_spell_cb = create_cvar_checkbox(sct_panel, "show pet spell damage", "floatingCombatTextPetSpellDamage",
        "toggles display of pet spell damage numbers.")
    pet_spell_cb:SetPoint("TOPLEFT", pet_melee_cb, "BOTTOMLEFT", 0, -5)

    local avoid_cb = create_cvar_checkbox(sct_panel, "show dodge/parry/miss", "floatingCombatTextDodgeParryMiss",
        "toggles display of avoidances.")
    avoid_cb:SetPoint("TOPLEFT", pet_spell_cb, "BOTTOMLEFT", 0, -5)

    local reduction_cb = create_cvar_checkbox(sct_panel, "show resist/block/absorb", "floatingCombatTextDamageReduction",
        "toggles display of damage reduction.")
    reduction_cb:SetPoint("TOPLEFT", avoid_cb, "BOTTOMLEFT", 0, -5)

    local energy_cb = create_cvar_checkbox(sct_panel, "show energy gains/runes", "floatingCombatTextEnergyGains",
        "toggles display of energy gains and runes.")
    energy_cb:SetPoint("TOPLEFT", reduction_cb, "BOTTOMLEFT", 0, -5)

    local auras_cb = create_cvar_checkbox(sct_panel, "show auras", "floatingCombatTextAuras",
        "toggles display of aura gains/losses.")
    auras_cb:SetPoint("TOPLEFT", energy_cb, "BOTTOMLEFT", 0, -5)

    local state_cb = create_cvar_checkbox(sct_panel, "show combat state", "floatingCombatTextCombatState",
        "toggles display of entering/leaving combat.")
    state_cb:SetPoint("TOPLEFT", auras_cb, "BOTTOMLEFT", 0, -5)

    -- 4. Currency / Items Panel
    local currency_header = currency_items_panel:CreateFontString(nil, "OVERLAY", g.font)
    currency_header:SetPoint("TOPLEFT", 15, -15)
    currency_header:SetTextColor(white[1], white[2], white[3])
    currency_header:SetText("currency display settings")

    local currency_info_text = currency_items_panel:CreateFontString(nil, "OVERLAY", g.font)
    currency_info_text:SetPoint("TOPLEFT", currency_header, "BOTTOMLEFT", 0, -10)
    currency_info_text:SetPoint("RIGHT", -15, 0)
    currency_info_text:SetJustifyH("LEFT")
    currency_info_text:SetText(
        "the currency display is automatic. to add or remove currencies, open the default character panel, go to the currencies tab, and check 'show on backpack' for any currency you wish to track. opening and closing the character panel will also update the display.")

    local item_header = currency_items_panel:CreateFontString(nil, "OVERLAY", g.font)
    item_header:SetPoint("TOPLEFT", currency_info_text, "BOTTOMLEFT", 0, -20)
    item_header:SetTextColor(white[1], white[2], white[3])
    item_header:SetText("item tracking settings")

    local item_id_label = currency_items_panel:CreateFontString(nil, "OVERLAY", g.font)
    item_id_label:SetPoint("TOPLEFT", item_header, "BOTTOMLEFT", 0, -10)
    item_id_label:SetText("add item by id:")

    local item_id_input = CreateFrame("EditBox", nil, currency_items_panel, "InputBoxTemplate")
    item_id_input:SetPoint("LEFT", item_id_label, "RIGHT", 10, 0)
    item_id_input:SetSize(100, 32)
    item_id_input:SetAutoFocus(false)

    local add_button = CreateFlatButton(currency_items_panel, "add", 50, 22)
    add_button:SetPoint("LEFT", item_id_input, "RIGHT", 5, 0)
    add_button:SetScript("OnClick", function()
        local id = tonumber(item_id_input:GetText())
        if id and sfui.add_item then
            sfui.add_item(id)
            item_id_input:SetText("")
        end
    end)

    local drop_frame = CreateFrame("Frame", "sfui_item_drop_frame", currency_items_panel, "BackdropTemplate")
    drop_frame:SetPoint("TOPLEFT", item_id_label, "BOTTOMLEFT", 0, -20)
    drop_frame:SetSize(250, 50)
    local drop_frame_backdrop = {
        bgFile = g.textures.tooltip,
        tile = true,
        tileSize = 16,
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    }
    drop_frame:SetBackdrop(drop_frame_backdrop)
    drop_frame:SetBackdropColor(0.3, 0.3, 0.3, 0.7) -- Lighter background
    drop_frame:SetBackdropBorderColor(0, 0, 0, 1)   -- 100% black border

    local drop_label = drop_frame:CreateFontString(nil, "OVERLAY", g.font)
    drop_label:SetAllPoints()
    drop_label:SetText("drop item here")
    drop_label:EnableMouse(false)

    drop_frame:EnableMouse(true)
    drop_frame:RegisterForDrag("LeftButton")
    drop_frame:SetScript("OnReceiveDrag", function(self)
        local type, id, link = GetCursorInfo()
        if type == "item" and link then
            local itemID = GetItemInfoFromHyperlink(link)
            if itemID and sfui.add_item then
                sfui.add_item(itemID)
            end
        end
    end)

    -- 5. Merchant Panel
    local merchant_header = merchant_panel:CreateFontString(nil, "OVERLAY", g.font)
    merchant_header:SetPoint("TOPLEFT", 15, -15)
    merchant_header:SetTextColor(white[1], white[2], white[3])
    merchant_header:SetText("merchant settings")

    local disable_merchant_cb = create_checkbox(merchant_panel, "disable merchant frame", "disableMerchant", nil,
        "restores the default wow merchant frame.")
    disable_merchant_cb:SetPoint("TOPLEFT", merchant_header, "BOTTOMLEFT", 0, -10)

    local disable_decor_cb = create_checkbox(merchant_panel, "disable decor filter", "disableDecor", function(checked)
        if checked and SfuiDecorDB then
            wipe(SfuiDecorDB)
            print("|cff00ff00Sfui: Decor cache cleared.|r")
        end
        if sfui.merchant and sfui.merchant.reset_scroll_and_rebuild then
            sfui.merchant.reset_scroll_and_rebuild()
        end
    end, "disables the caching and filtering of merchant items. clears existing cache when enabled.")
    disable_decor_cb:SetPoint("TOPLEFT", disable_merchant_cb, "BOTTOMLEFT", 0, -10)

    -- 6. automation panel
    local automation_header = automation_panel:CreateFontString(nil, "OVERLAY", g.font)
    automation_header:SetPoint("TOPLEFT", 15, -15)
    automation_header:SetTextColor(white[1], white[2], white[3])
    automation_header:SetText("automation settings")

    local auto_role_cb = create_checkbox(automation_panel, "auto confirm role checks", "auto_role_check", nil,
        "automatically selects and accepts the role check when a group leader signs up.")
    auto_role_cb:SetPoint("TOPLEFT", automation_header, "BOTTOMLEFT", 0, -10)

    local auto_sign_cb = create_checkbox(automation_panel, "auto sign lfg", "auto_sign_lfg", nil,
        "enables double-click signing for premade groups in the lfg tool. hold shift to bypass.")
    auto_sign_cb:SetPoint("TOPLEFT", auto_role_cb, "BOTTOMLEFT", 0, -10)

    local auto_sell_cb = create_checkbox(automation_panel, "auto-sell greys", "autoSellGreys", nil,
        "Automatically sells all grey items when opening a merchant.")
    auto_sell_cb:SetPoint("TOPLEFT", auto_sign_cb, "BOTTOMLEFT", 0, -10)

    local auto_repair_cb = create_checkbox(automation_panel, "auto-repair", "autoRepair", nil,
        "Automatically repairs gear (guild first, skips if blacksmith hammer available).")
    auto_repair_cb:SetPoint("TOPLEFT", auto_sell_cb, "BOTTOMLEFT", 0, -10)

    -- Master's Hammer Settings
    local aesthetic_header = automation_panel:CreateFontString(nil, "OVERLAY", g.font)
    aesthetic_header:SetPoint("TOPLEFT", auto_repair_cb, "BOTTOMLEFT", 0, -20)
    aesthetic_header:SetTextColor(white[1], white[2], white[3])
    aesthetic_header:SetText("master's hammer settings")

    -- Enable Toggle
    local enable_hammer_cb = create_checkbox(automation_panel, "master's hammer", "enableMasterHammer", function(checked)
        if sfui.automation and sfui.automation.update_hammer_popup then
            sfui.automation.update_hammer_popup()
        end
    end, "Enables the automated Master's Hammer repair popup.")
    enable_hammer_cb:SetPoint("TOPLEFT", aesthetic_header, "BOTTOMLEFT", 0, -10)

    -- Threshold
    local threshold_label = automation_panel:CreateFontString(nil, "OVERLAY", g.font)
    threshold_label:SetPoint("TOPLEFT", enable_hammer_cb, "BOTTOMLEFT", 0, -10)
    threshold_label:SetText("repair threshold (%):")
    threshold_label:SetTextColor(white[1], white[2], white[3])

    local threshold_input = CreateFrame("EditBox", nil, automation_panel, "InputBoxTemplate")
    threshold_input:SetSize(40, 20)
    threshold_input:SetPoint("LEFT", threshold_label, "RIGHT", 5, 0)
    threshold_input:SetAutoFocus(false)
    threshold_input:SetNumeric(true)
    threshold_input:SetScript("OnShow", function(self)
        self:SetText(tostring(SfuiDB.repairThreshold or 90))
    end)
    threshold_input:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then
            if val < 0 then val = 0 end
            if val > 100 then val = 100 end
            SfuiDB.repairThreshold = val
            self:SetText(tostring(val))
            if sfui.automation and sfui.automation.update_hammer_popup then
                sfui.automation.update_hammer_popup()
            end
        end
        self:ClearFocus()
    end)

    -- Aesthetics Inputs
    local icon_x_label = automation_panel:CreateFontString(nil, "OVERLAY", g.font)
    icon_x_label:SetPoint("TOPLEFT", threshold_label, "BOTTOMLEFT", 0, -15)
    icon_x_label:SetText("x:")

    local icon_x_input = CreateFrame("EditBox", nil, automation_panel, "InputBoxTemplate")
    icon_x_input:SetPoint("LEFT", icon_x_label, "RIGHT", 5, 0)
    icon_x_input:SetSize(50, 20)
    icon_x_input:SetAutoFocus(false)
    icon_x_input:SetScript("OnShow", function(self) self:SetText(tostring(SfuiDB.repairIconX or 880)) end)
    icon_x_input:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText()) or 880
        SfuiDB.repairIconX = val
        if sfui.automation and sfui.automation.update_popup_style then
            sfui.automation.update_popup_style()
        end
        self:ClearFocus()
    end)

    local icon_y_label = automation_panel:CreateFontString(nil, "OVERLAY", g.font)
    icon_y_label:SetPoint("LEFT", icon_x_input, "RIGHT", 10, 0)
    icon_y_label:SetText("y:")

    local icon_y_input = CreateFrame("EditBox", nil, automation_panel, "InputBoxTemplate")
    icon_y_input:SetPoint("LEFT", icon_y_label, "RIGHT", 5, 0)
    icon_y_input:SetSize(50, 20)
    icon_y_input:SetAutoFocus(false)
    icon_y_input:SetScript("OnShow", function(self) self:SetText(tostring(SfuiDB.repairIconY or 397)) end)
    icon_y_input:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText()) or 397
        SfuiDB.repairIconY = val
        if sfui.automation and sfui.automation.update_popup_style then
            sfui.automation.update_popup_style()
        end
        self:ClearFocus()
    end)

    local color_label = automation_panel:CreateFontString(nil, "OVERLAY", g.font)
    color_label:SetPoint("LEFT", icon_y_input, "RIGHT", 15, 0)
    color_label:SetText("color (#hex):")

    local color_input = CreateFrame("EditBox", nil, automation_panel, "InputBoxTemplate")
    color_input:SetPoint("LEFT", color_label, "RIGHT", 5, 0)
    color_input:SetSize(70, 20)
    color_input:SetAutoFocus(false)
    color_input:SetScript("OnShow", function(self) self:SetText(SfuiDB.repairIconColor or "00FFFF") end)
    color_input:SetScript("OnEnterPressed", function(self)
        local val = self:GetText()
        SfuiDB.repairIconColor = val
        if sfui.automation and sfui.automation.update_popup_style then
            sfui.automation.update_popup_style()
        end
        self:ClearFocus()
    end)

    -- 7. Minimap Panel
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

    -- Position X input
    local pos_x_label = minimap_panel:CreateFontString(nil, "OVERLAY", g.font)
    pos_x_label:SetPoint("TOPLEFT", mouseover_cb, "BOTTOMLEFT", 0, -15)
    pos_x_label:SetText("position x:")
    pos_x_label:SetTextColor(white[1], white[2], white[3])

    local pos_x_input = CreateFrame("EditBox", nil, minimap_panel, "InputBoxTemplate")
    pos_x_input:SetSize(60, 20)
    pos_x_input:SetPoint("LEFT", pos_x_label, "RIGHT", 5, 0)
    pos_x_input:SetAutoFocus(false)
    pos_x_input:SetText(tostring(SfuiDB.minimap_button_x or 0))
    pos_x_input:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then
            SfuiDB.minimap_button_x = val
            if sfui.minimap and sfui.minimap.update_button_bar_position then
                sfui.minimap.update_button_bar_position()
            end
        end
        self:ClearFocus()
    end)

    -- Position Y input
    local pos_y_label = minimap_panel:CreateFontString(nil, "OVERLAY", g.font)
    pos_y_label:SetPoint("LEFT", pos_x_input, "RIGHT", 15, 0)
    pos_y_label:SetText("y:")
    pos_y_label:SetTextColor(white[1], white[2], white[3])

    local pos_y_input = CreateFrame("EditBox", nil, minimap_panel, "InputBoxTemplate")
    pos_y_input:SetSize(60, 20)
    pos_y_input:SetPoint("LEFT", pos_y_label, "RIGHT", 5, 0)
    pos_y_input:SetAutoFocus(false)
    pos_y_input:SetText(tostring(SfuiDB.minimap_button_y or 35))
    pos_y_input:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then
            SfuiDB.minimap_button_y = val
            if sfui.minimap and sfui.minimap.update_button_bar_position then
                sfui.minimap.update_button_bar_position()
            end
        end
        self:ClearFocus()
    end)

    -- Reset button
    local reset_pos_btn = CreateFrame("Button", nil, minimap_panel, "UIPanelButtonTemplate")
    reset_pos_btn:SetSize(120, 22)
    reset_pos_btn:SetPoint("TOPLEFT", pos_x_label, "BOTTOMLEFT", 0, -10)
    reset_pos_btn:SetText("reset position")
    reset_pos_btn:SetScript("OnClick", function()
        SfuiDB.minimap_button_x = 0
        SfuiDB.minimap_button_y = 35
        pos_x_input:SetText("0")
        pos_y_input:SetText("35")
        if sfui.minimap and sfui.minimap.update_button_bar_position then
            sfui.minimap.update_button_bar_position()
        end
    end)

    -- 7. Reminders Panel
    local reminders_header = reminders_panel:CreateFontString(nil, "OVERLAY", g.font)
    reminders_header:SetPoint("TOPLEFT", 15, -15)
    reminders_header:SetTextColor(white[1], white[2], white[3])
    reminders_header:SetText("reminders & warnings")

    local enable_reminders_cb = create_checkbox(reminders_panel, "enable buff reminders", "enableReminders",
        function(checked)
            if sfui.reminders and sfui.reminders.on_state_changed then sfui.reminders.on_state_changed(checked) end
        end, "toggles the buff reminders frame.")
    enable_reminders_cb:SetPoint("TOPLEFT", reminders_header, "BOTTOMLEFT", 0, -10)

    local reminders_everywhere_cb = create_checkbox(reminders_panel, "show outside instances", "remindersEverywhere",
        function(checked)
            if sfui.reminders and sfui.reminders.update_visibility then sfui.reminders.update_visibility() end
        end, "shows the reminders frame even when not in an instance.")
    reminders_everywhere_cb:SetPoint("TOPLEFT", enable_reminders_cb, "BOTTOMLEFT", 0, -10)

    local reminders_solo_cb = create_checkbox(reminders_panel, "show while solo", "remindersSolo",
        function(checked)
            if sfui.reminders and sfui.reminders.update_visibility then sfui.reminders.update_visibility() end
        end, "shows the reminders frame even when not in a group.")
    reminders_solo_cb:SetPoint("TOPLEFT", reminders_everywhere_cb, "BOTTOMLEFT", 0, -10)

    local reminders_x_label = reminders_panel:CreateFontString(nil, "OVERLAY", g.font)
    reminders_x_label:SetPoint("TOPLEFT", reminders_solo_cb, "BOTTOMLEFT", 0, -20)
    reminders_x_label:SetText("position x:")

    local reminders_x_input = CreateFrame("EditBox", nil, reminders_panel, "InputBoxTemplate")
    reminders_x_input:SetPoint("LEFT", reminders_x_label, "RIGHT", 10, 0)
    reminders_x_input:SetSize(60, 32)
    reminders_x_input:SetAutoFocus(false)
    reminders_x_input:SetNumeric(true)
    reminders_x_input:SetScript("OnShow", function(self) self:SetText(tostring(SfuiDB.remindersX)) end)
    reminders_x_input:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText()) or 0
        SfuiDB.remindersX = val
        if sfui.reminders and sfui.reminders.update_position then sfui.reminders.update_position() end
        self:ClearFocus()
    end)

    local reminders_y_label = reminders_panel:CreateFontString(nil, "OVERLAY", g.font)
    reminders_y_label:SetPoint("LEFT", reminders_x_input, "RIGHT", 20, 0)
    reminders_y_label:SetText("y:")

    local reminders_y_input = CreateFrame("EditBox", nil, reminders_panel, "InputBoxTemplate")
    reminders_y_input:SetPoint("LEFT", reminders_y_label, "RIGHT", 10, 0)
    reminders_y_input:SetSize(60, 32)
    reminders_y_input:SetAutoFocus(false)
    reminders_y_input:SetNumeric(true)
    reminders_y_input:SetScript("OnShow", function(self) self:SetText(tostring(SfuiDB.remindersY)) end)
    reminders_y_input:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText()) or 0
        SfuiDB.remindersY = val
        if sfui.reminders and sfui.reminders.update_position then sfui.reminders.update_position() end
        self:ClearFocus()
    end)

    local warnings_header = reminders_panel:CreateFontString(nil, "OVERLAY", g.font)
    warnings_header:SetPoint("TOPLEFT", reminders_x_label, "BOTTOMLEFT", 0, -30)
    warnings_header:SetTextColor(white[1], white[2], white[3])
    warnings_header:SetText("warning settings")

    local enable_pet_warning_cb = create_checkbox(reminders_panel, "enable pet warning", "enablePetWarning",
        function(checked)
            if sfui.reminders and sfui.reminders.update_warnings then sfui.reminders.update_warnings() end
        end, "warns you if your pet is missing (for pet classes).")
    enable_pet_warning_cb:SetPoint("TOPLEFT", warnings_header, "BOTTOMLEFT", 0, -10)

    local enable_rune_warning_cb = create_checkbox(reminders_panel, "enable rune warning", "enableRuneWarning",
        function(checked)
            if sfui.reminders and sfui.reminders.update_warnings then sfui.reminders.update_warnings() end
        end, "warns you if you are missing an augment rune buff but have runes in your bags.")
    enable_rune_warning_cb:SetPoint("TOPLEFT", enable_pet_warning_cb, "BOTTOMLEFT", 0, -10)

    -- 8. Research Viewer Panel
    local research_header = research_panel:CreateFontString(nil, "OVERLAY", g.font)
    research_header:SetPoint("TOPLEFT", 15, -15)
    research_header:SetTextColor(white[1], white[2], white[3])
    research_header:SetText("research viewer settings")

    local research_info = research_panel:CreateFontString(nil, "OVERLAY", g.font)
    research_info:SetPoint("TOPLEFT", research_header, "BOTTOMLEFT", 0, -10)
    research_info:SetPoint("RIGHT", -15, 0)
    research_info:SetJustifyH("LEFT")
    research_info:SetText(
        "the research viewer allows you to view various talent and research trees (skyriding, delves, etc.) from anywhere. you can also open it by middle-clicking the sfui minimap icon.")

    local toggle_research_button = CreateFlatButton(research_panel, "open research viewer", 160, 22)
    toggle_research_button:SetPoint("TOPLEFT", research_info, "BOTTOMLEFT", 0, -20)
    toggle_research_button:SetScript("OnClick", function()
        if sfui.research and sfui.research.toggle_selection then
            sfui.research.toggle_selection()
            frame:Hide()
        end
    end)

    local custom_header = research_panel:CreateFontString(nil, "OVERLAY", g.font)
    custom_header:SetPoint("TOPLEFT", toggle_research_button, "BOTTOMLEFT", 0, -30)
    custom_header:SetTextColor(white[1], white[2], white[3])
    custom_header:SetText("manual tree entry")

    local custom_id_label = research_panel:CreateFontString(nil, "OVERLAY", g.font)
    custom_id_label:SetPoint("TOPLEFT", custom_header, "BOTTOMLEFT", 0, -10)
    custom_id_label:SetText("enter tree id:")

    local custom_id_input = CreateFrame("EditBox", nil, research_panel, "InputBoxTemplate")
    custom_id_input:SetPoint("LEFT", custom_id_label, "RIGHT", 10, 0)
    custom_id_input:SetSize(80, 32)
    custom_id_input:SetAutoFocus(false)

    local add_trait_button = CreateFlatButton(research_panel, "trait", 60, 22)
    add_trait_button:SetPoint("LEFT", custom_id_input, "RIGHT", 5, 0)
    add_trait_button:SetScript("OnClick", function()
        local id = tonumber(custom_id_input:GetText())
        if id and sfui.research and sfui.research.open_tree then
            sfui.research.open_tree({ id = id, isTraitTree = true, name = "Custom " .. id })
            frame:Hide()
        end
    end)
    add_trait_button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("trait tree (skyriding, delves, etc.)")
        GameTooltip:Show()
    end)
    add_trait_button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local add_garr_button = CreateFlatButton(research_panel, "garr", 60, 22)
    add_garr_button:SetPoint("LEFT", add_trait_button, "RIGHT", 5, 0)
    add_garr_button:SetScript("OnClick", function()
        local id = tonumber(custom_id_input:GetText())
        if id and sfui.research and sfui.research.open_tree then
            sfui.research.open_tree({ id = id, isTraitTree = false, type = 111, name = "Custom " .. id })
            frame:Hide()
        end
    end)
    add_garr_button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("garrison tree (class halls, covenants, etc.)")
        GameTooltip:Show()
    end)
    add_garr_button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- 9. Debug Panel
    local spec_id_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    spec_id_label:SetPoint("TOPLEFT", 15, -15)
    spec_id_label:SetText("spec id:")
    local spec_id_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    spec_id_value:SetPoint("LEFT", spec_id_label, "RIGHT", 5, 0)

    local color_swatch = debug_panel:CreateTexture(nil, "ARTWORK")
    color_swatch:SetSize(20, 20)
    color_swatch:SetPoint("LEFT", spec_id_value, "RIGHT", 10, 0)
    color_swatch:SetTexture("Interface/Buttons/WHITE8X8")

    local primary_power_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    primary_power_label:SetPoint("TOPLEFT", spec_id_label, "BOTTOMLEFT", 0, -15)
    primary_power_label:SetText("primary power:")
    local primary_power_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    primary_power_value:SetPoint("LEFT", primary_power_label, "RIGHT", 5, 0)

    local secondary_power_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    secondary_power_label:SetPoint("TOPLEFT", primary_power_label, "BOTTOMLEFT", 0, -15)
    secondary_power_label:SetText("secondary power:")
    local secondary_power_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    secondary_power_value:SetPoint("LEFT", secondary_power_label, "RIGHT", 5, 0)

    local function get_power_type_name(power_enum)
        if not power_enum then return "None" end
        if type(power_enum) ~= "number" then return tostring(power_enum) end
        for name, value in pairs(Enum.PowerType) do
            if value == power_enum then return name end
        end
        return "Unknown"
    end

    local function update_debug_info()
        local specID = sfui.common.get_current_spec_id()
        spec_id_value:SetText(specID > 0 and tostring(specID) or "N/A")

        local color = sfui.common.get_class_or_spec_color()
        if color then color_swatch:SetColorTexture(color.r, color.g, color.b) end

        if sfui.common.get_primary_resource then
            primary_power_value:SetText(get_power_type_name(sfui.common.get_primary_resource()))
        end
        if sfui.common.get_secondary_resource then
            secondary_power_value:SetText(get_power_type_name(sfui.common.get_secondary_resource()))
        end
    end

    -- Pet Warning Status
    local pet_warning_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    pet_warning_label:SetPoint("TOPLEFT", secondary_power_label, "BOTTOMLEFT", 0, -15)
    pet_warning_label:SetText("pet warning status:")
    local pet_warning_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    pet_warning_value:SetPoint("LEFT", pet_warning_label, "RIGHT", 5, 0)

    local decor_cache_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    decor_cache_label:SetPoint("TOPLEFT", pet_warning_label, "BOTTOMLEFT", 0, -15)
    decor_cache_label:SetText("decor cache:")
    local decor_cache_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    decor_cache_value:SetPoint("LEFT", decor_cache_label, "RIGHT", 5, 0)

    -- Hammer Status
    local hammer_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    hammer_label:SetPoint("TOPLEFT", decor_cache_label, "BOTTOMLEFT", 0, -15)
    hammer_label:SetText("master's hammer:")
    local hammer_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    hammer_value:SetPoint("LEFT", hammer_label, "RIGHT", 5, 0)

    local hammer_id_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    hammer_id_label:SetPoint("TOPLEFT", hammer_label, "BOTTOMLEFT", 0, -15)
    hammer_id_label:SetText("hammer item id:")
    local hammer_id_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    hammer_id_value:SetPoint("LEFT", hammer_id_label, "RIGHT", 5, 0)

    local debug_refresh_button = CreateFlatButton(debug_panel, "refresh", 100, 22)
    debug_refresh_button:SetPoint("BOTTOM", debug_panel, "BOTTOM", 0, 10)

    -- Update update_debug_info to include pet warning status
    local original_update_debug_info = update_debug_info
    function update_debug_info()
        original_update_debug_info() -- Call original function

        if sfui.reminders and sfui.reminders.get_status then
            pet_warning_value:SetText(sfui.reminders.get_status())
        else
            pet_warning_value:SetText("N/A (Module Missing)")
        end

        if sfui.merchant and sfui.merchant.decorCacheStatus then
            decor_cache_value:SetText(sfui.merchant.decorCacheStatus)
        else
            decor_cache_value:SetText("N/A (Not Populated)")
        end

        if sfui.automation and sfui.automation.has_repair_hammer then
            local found, name, icon, itemID = sfui.automation.has_repair_hammer(true)
            if found then
                hammer_value:SetText("|cff00ff00Found|r (" .. (name or "Unknown") .. ")")
                hammer_id_value:SetText(tostring(itemID))
            else
                hammer_value:SetText("|cffff0000Not Found|r")
                hammer_id_value:SetText("None")
            end
        else
            hammer_value:SetText("N/A")
            hammer_id_value:SetText("N/A")
        end
    end

    debug_refresh_button:SetScript("OnClick", update_debug_info)

    -- Hook into the debug tab's OnClick to refresh info when selected
    local original_on_click_debug = debug_tab_button:GetScript("OnClick")
    debug_tab_button:SetScript("OnClick", function(self)
        original_on_click_debug(self) -- Call original select_tab logic
        update_debug_info()
    end)

    update_debug_info()
end

function sfui.toggle_options_panel()
    if not frame then sfui.create_options_panel() end

    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        if not frame.selected_tab then select_tab(frame.tabs[1].button) end
    end
end
