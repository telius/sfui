local c = sfui.config.options_panel
local g = sfui.config
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
        end)
        cb:SetScript("OnShow", function(self)
            self:SetChecked(C_CVar.GetCVarBool(cvar))
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

    local bars_panel, bars_tab_button = create_tab("bars")
    bars_tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, 5)
    last_tab_button = bars_tab_button

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
    debug_tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, 5)
    last_tab_button = debug_tab_button

    local main_text = main_panel:CreateFontString(nil, "OVERLAY", g.font)
    main_text:SetPoint("TOPLEFT", 15, -15)
    local white = sfui.config.colors.white
    main_text:SetTextColor(white[1], white[2], white[3])
    main_text:SetText("welcome to sfui. please select a category on the left.")



    local reload_button = CreateFlatButton(main_panel, "Reload UI", 100, 22)
    reload_button:SetPoint("TOPLEFT", main_text, "BOTTOMLEFT", 0, -20)
    reload_button:SetScript("OnClick", function() C_UI.Reload() end)

    local hide_minimap_icon_cb = create_checkbox(main_panel, "Hide Minimap Icon", "minimap_icon.hide", function(checked)
        local icon = LibStub:GetLibrary("LibDBIcon-1.0", true)
        if icon then
            if checked then
                icon:Hide("sfui")
            else
                icon:Show("sfui")
            end
        end
    end, "Hides the sfui minimap icon.")
    hide_minimap_icon_cb:SetPoint("TOPLEFT", reload_button, "BOTTOMLEFT", 0, -20)

    local vehicle_header = main_panel:CreateFontString(nil, "OVERLAY", g.font)
    vehicle_header:SetPoint("TOPLEFT", hide_minimap_icon_cb, "BOTTOMLEFT", 0, -30)
    vehicle_header:SetTextColor(white[1], white[2], white[3])
    vehicle_header:SetText("Vehicle Settings")

    local disable_vehicle_cb = create_checkbox(main_panel, "Disable Vehicle UI", "disableVehicle", nil,
        "Restores the default WoW vehicle/overlay bar.")
    disable_vehicle_cb:SetPoint("TOPLEFT", vehicle_header, "BOTTOMLEFT", 0, -10)


    -- 2. Bars Panel
    local bars_header = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
    bars_header:SetPoint("TOPLEFT", 15, -15)
    bars_header:SetTextColor(white[1], white[2], white[3])
    bars_header:SetText("Bar Settings")

    local texture_label = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
    texture_label:SetPoint("TOPLEFT", bars_header, "BOTTOMLEFT", 0, -10)
    texture_label:SetText("Bar Texture:")

    local dropdown = CreateFrame("Frame", "sfui_options_texture_dropdown", bars_panel, "UIDropDownMenuTemplate")
    dropdown:SetPoint("LEFT", texture_label, "RIGHT", 10, 0)

    local function on_texture_select(self)
        local textureName = self.value
        SfuiDB.barTexture = textureName

        local LSM = LibStub("LibSharedMedia-3.0", true)
        local texturePath = LSM and LSM:Fetch("statusbar", textureName) or "Interface/Buttons/WHITE8X8"

        if sfui.bars and sfui.bars.set_bar_texture then
            sfui.bars:set_bar_texture(texturePath)
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

    -- Bar Toggles
    local toggles_header = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
    toggles_header:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", -10, -20)
    toggles_header:SetTextColor(white[1], white[2], white[3])
    toggles_header:SetText("Bar Visibility")

    local health_bar_cb = create_checkbox(bars_panel, "Enable Health Bar", "enableHealthBar", function(checked)
        if sfui.bars and sfui.bars.on_state_changed then sfui.bars:on_state_changed() end
    end, "Toggles the health bar.")
    health_bar_cb:SetPoint("TOPLEFT", toggles_header, "BOTTOMLEFT", 0, -10)

    local power_bar_cb = create_checkbox(bars_panel, "Enable Power Bar", "enablePowerBar", function(checked)
        if sfui.bars and sfui.bars.on_state_changed then sfui.bars:on_state_changed() end
    end, "Toggles the primary power bar.")
    power_bar_cb:SetPoint("TOPLEFT", health_bar_cb, "BOTTOMLEFT", 0, -10)

    local secondary_power_cb = create_checkbox(bars_panel, "Enable Secondary Power Bar", "enableSecondaryPowerBar",
        function(checked)
            if sfui.bars and sfui.bars.on_state_changed then sfui.bars:on_state_changed() end
        end, "Toggles the secondary power bar (e.g., Chi, Holy Power).")
    secondary_power_cb:SetPoint("TOPLEFT", power_bar_cb, "BOTTOMLEFT", 0, -10)

    local vigor_bar_cb = create_checkbox(bars_panel, "Enable Vigor Bar", "enableVigorBar", function(checked)
        if sfui.bars and sfui.bars.on_state_changed then sfui.bars:on_state_changed() end
    end, "Toggles the vigor bar (Dragonriding).")
    vigor_bar_cb:SetPoint("TOPLEFT", secondary_power_cb, "BOTTOMLEFT", 0, -10)

    local mount_speed_cb = create_checkbox(bars_panel, "Enable Mount Speed Bar", "enableMountSpeedBar", function(checked)
        if sfui.bars and sfui.bars.on_state_changed then sfui.bars:on_state_changed() end
    end, "Toggles the mount speed bar (Dragonriding).")
    mount_speed_cb:SetPoint("TOPLEFT", vigor_bar_cb, "BOTTOMLEFT", 0, -10)

    -- Health Bar Position
    local position_header = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
    position_header:SetPoint("TOPLEFT", mount_speed_cb, "BOTTOMLEFT", 0, -20)
    position_header:SetTextColor(white[1], white[2], white[3])
    position_header:SetText("Health Bar Position")

    local health_x_label = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
    health_x_label:SetPoint("TOPLEFT", position_header, "BOTTOMLEFT", 0, -10)
    health_x_label:SetText("X:")
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
    health_y_label:SetText("Y:")
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
    reset_health_pos_btn:SetText("Reset Position")
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
    sct_header:SetText("Blizzard Combat Text Settings")

    local master_cb = create_cvar_checkbox(sct_panel, "Enable Floating Combat Text", "enableFloatingCombatText",
        "Master toggle for Blizzard's floating combat text.")
    master_cb:SetPoint("TOPLEFT", sct_header, "BOTTOMLEFT", 0, -10)

    local damage_cb = create_cvar_checkbox(sct_panel, "Show Damage", "floatingCombatTextCombatDamage",
        "Toggles display of damage numbers over targets.")
    damage_cb:SetPoint("TOPLEFT", master_cb, "BOTTOMLEFT", 0, -5)

    local periodic_cb = create_cvar_checkbox(sct_panel, "Show Periodic Damage (DoTs)",
        "floatingCombatTextCombatLogPeriodicSpells", "Toggles display of periodic damage (DoTs) numbers.")
    periodic_cb:SetPoint("TOPLEFT", damage_cb, "BOTTOMLEFT", 0, -5)

    local healing_cb = create_cvar_checkbox(sct_panel, "Show Healing", "floatingCombatTextCombatHealing",
        "Toggles display of healing numbers over targets.")
    healing_cb:SetPoint("TOPLEFT", periodic_cb, "BOTTOMLEFT", 0, -5)

    local pet_melee_cb = create_cvar_checkbox(sct_panel, "Show Pet Melee Damage", "floatingCombatTextPetMeleeDamage",
        "Toggles display of pet melee damage numbers.")
    pet_melee_cb:SetPoint("TOPLEFT", healing_cb, "BOTTOMLEFT", 0, -5)

    local pet_spell_cb = create_cvar_checkbox(sct_panel, "Show Pet Spell Damage", "floatingCombatTextPetSpellDamage",
        "Toggles display of pet spell damage numbers.")
    pet_spell_cb:SetPoint("TOPLEFT", pet_melee_cb, "BOTTOMLEFT", 0, -5)

    local avoid_cb = create_cvar_checkbox(sct_panel, "Show Dodge/Parry/Miss", "floatingCombatTextDodgeParryMiss",
        "Toggles display of avoidances.")
    avoid_cb:SetPoint("TOPLEFT", pet_spell_cb, "BOTTOMLEFT", 0, -5)

    local reduction_cb = create_cvar_checkbox(sct_panel, "Show Resist/Block/Absorb", "floatingCombatTextDamageReduction",
        "Toggles display of damage reduction.")
    reduction_cb:SetPoint("TOPLEFT", avoid_cb, "BOTTOMLEFT", 0, -5)

    local energy_cb = create_cvar_checkbox(sct_panel, "Show Energy Gains/Runes", "floatingCombatTextEnergyGains",
        "Toggles display of energy gains and runes.")
    energy_cb:SetPoint("TOPLEFT", reduction_cb, "BOTTOMLEFT", 0, -5)

    local auras_cb = create_cvar_checkbox(sct_panel, "Show Auras", "floatingCombatTextAuras",
        "Toggles display of aura gains/losses.")
    auras_cb:SetPoint("TOPLEFT", energy_cb, "BOTTOMLEFT", 0, -5)

    local state_cb = create_cvar_checkbox(sct_panel, "Show Combat State", "floatingCombatTextCombatState",
        "Toggles display of entering/leaving combat.")
    state_cb:SetPoint("TOPLEFT", auras_cb, "BOTTOMLEFT", 0, -5)

    -- 4. Currency / Items Panel
    local currency_header = currency_items_panel:CreateFontString(nil, "OVERLAY", g.font)
    currency_header:SetPoint("TOPLEFT", 15, -15)
    currency_header:SetTextColor(white[1], white[2], white[3])
    currency_header:SetText("Currency Display Settings")

    local currency_info_text = currency_items_panel:CreateFontString(nil, "OVERLAY", g.font)
    currency_info_text:SetPoint("TOPLEFT", currency_header, "BOTTOMLEFT", 0, -10)
    currency_info_text:SetPoint("RIGHT", -15, 0)
    currency_info_text:SetJustifyH("LEFT")
    currency_info_text:SetText(
        "The currency display is automatic. To add or remove currencies, open the default Character panel, go to the Currencies tab, and check 'Show on Backpack' for any currency you wish to track. Opening and closing the Character Panel will also update the display.")

    local item_header = currency_items_panel:CreateFontString(nil, "OVERLAY", g.font)
    item_header:SetPoint("TOPLEFT", currency_info_text, "BOTTOMLEFT", 0, -20)
    item_header:SetTextColor(white[1], white[2], white[3])
    item_header:SetText("Item Tracking Settings")

    local item_id_label = currency_items_panel:CreateFontString(nil, "OVERLAY", g.font)
    item_id_label:SetPoint("TOPLEFT", item_header, "BOTTOMLEFT", 0, -10)
    item_id_label:SetText("Add Item by ID:")

    local item_id_input = CreateFrame("EditBox", nil, currency_items_panel, "InputBoxTemplate")
    item_id_input:SetPoint("LEFT", item_id_label, "RIGHT", 10, 0)
    item_id_input:SetSize(100, 32)
    item_id_input:SetAutoFocus(false)

    local add_button = CreateFlatButton(currency_items_panel, "Add", 50, 22)
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
    drop_label:SetText("Drop Item Here")
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
    merchant_header:SetText("Merchant Settings")

    local auto_sell_cb = create_checkbox(merchant_panel, "Auto-Sell Greys", "autoSellGreys", nil,
        "Automatically sells all grey items when opening a merchant.")
    auto_sell_cb:SetPoint("TOPLEFT", merchant_header, "BOTTOMLEFT", 0, -10)

    local disable_merchant_cb = create_checkbox(merchant_panel, "Disable Merchant Frame", "disableMerchant", nil,
        "Restores the default WoW merchant frame.")
    disable_merchant_cb:SetPoint("TOPLEFT", auto_sell_cb, "BOTTOMLEFT", 0, -10)

    local auto_repair_cb = create_checkbox(merchant_panel, "Auto-Repair", "autoRepair", nil,
        "Automatically repairs gear (guild first, skips if blacksmith hammer available).")
    auto_repair_cb:SetPoint("TOPLEFT", disable_merchant_cb, "BOTTOMLEFT", 0, -10)

    -- 6. Minimap Panel
    local minimap_header = minimap_panel:CreateFontString(nil, "OVERLAY", g.font)
    minimap_header:SetPoint("TOPLEFT", 15, -15)
    minimap_header:SetTextColor(white[1], white[2], white[3])
    minimap_header:SetText("Minimap Settings")

    local collect_cb = create_checkbox(minimap_panel, "Collect Buttons", "minimap_collect_buttons", function(checked)
        if sfui.minimap and sfui.minimap.enable_button_manager then
            sfui.minimap.enable_button_manager(checked)
        end
    end, "Collects minimap buttons into a bar.")
    collect_cb:SetPoint("TOPLEFT", minimap_header, "BOTTOMLEFT", 0, -10)

    local mouseover_cb = create_checkbox(minimap_panel, "Mouseover Only", "minimap_buttons_mouseover", function(checked)
        if sfui.minimap and sfui.minimap.enable_button_manager and SfuiDB.minimap_collect_buttons then
            C_Timer.After(0.1, function()
                sfui.minimap.enable_button_manager(false)
                sfui.minimap.enable_button_manager(true)
            end)
        end
    end, "Only show the button bar when hovering the minimap. Also moves Group Finder eye to Top Left.")
    mouseover_cb:SetPoint("TOPLEFT", collect_cb, "BOTTOMLEFT", 0, -10)

    -- Position X input
    local pos_x_label = minimap_panel:CreateFontString(nil, "OVERLAY", g.font)
    pos_x_label:SetPoint("TOPLEFT", mouseover_cb, "BOTTOMLEFT", 0, -15)
    pos_x_label:SetText("Position X:")
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
    pos_y_label:SetText("Y:")
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
    reset_pos_btn:SetText("Reset Position")
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
    reminders_header:SetText("Reminders & Warnings")

    local enable_reminders_cb = create_checkbox(reminders_panel, "Enable Buff Reminders", "enableReminders",
        function(checked)
            if sfui.reminders and sfui.reminders.on_state_changed then sfui.reminders.on_state_changed(checked) end
        end, "Toggles the buff reminders frame.")
    enable_reminders_cb:SetPoint("TOPLEFT", reminders_header, "BOTTOMLEFT", 0, -10)

    local reminders_everywhere_cb = create_checkbox(reminders_panel, "Show outside Instances", "remindersEverywhere",
        function(checked)
            if sfui.reminders and sfui.reminders.update_visibility then sfui.reminders.update_visibility() end
        end, "Shows the reminders frame even when not in an instance.")
    reminders_everywhere_cb:SetPoint("TOPLEFT", enable_reminders_cb, "BOTTOMLEFT", 0, -10)

    local reminders_solo_cb = create_checkbox(reminders_panel, "Show while Solo", "remindersSolo",
        function(checked)
            if sfui.reminders and sfui.reminders.update_visibility then sfui.reminders.update_visibility() end
        end, "Shows the reminders frame even when not in a group.")
    reminders_solo_cb:SetPoint("TOPLEFT", reminders_everywhere_cb, "BOTTOMLEFT", 0, -10)

    local reminders_x_label = reminders_panel:CreateFontString(nil, "OVERLAY", g.font)
    reminders_x_label:SetPoint("TOPLEFT", reminders_solo_cb, "BOTTOMLEFT", 0, -20)
    reminders_x_label:SetText("Position X:")

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
    reminders_y_label:SetText("Y:")

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
    warnings_header:SetText("Warning Settings")

    local enable_pet_warning_cb = create_checkbox(reminders_panel, "Enable Pet Warning", "enablePetWarning",
        function(checked)
            if sfui.reminders and sfui.reminders.update_warnings then sfui.reminders.update_warnings() end
        end, "Warns you if your pet is missing (for pet classes).")
    enable_pet_warning_cb:SetPoint("TOPLEFT", warnings_header, "BOTTOMLEFT", 0, -10)

    local enable_rune_warning_cb = create_checkbox(reminders_panel, "Enable Rune Warning", "enableRuneWarning",
        function(checked)
            if sfui.reminders and sfui.reminders.update_warnings then sfui.reminders.update_warnings() end
        end, "Warns you if you are missing an Augment Rune buff but have runes in your bags.")
    enable_rune_warning_cb:SetPoint("TOPLEFT", enable_pet_warning_cb, "BOTTOMLEFT", 0, -10)

    -- 8. Research Viewer Panel
    local research_header = research_panel:CreateFontString(nil, "OVERLAY", g.font)
    research_header:SetPoint("TOPLEFT", 15, -15)
    research_header:SetTextColor(white[1], white[2], white[3])
    research_header:SetText("Research Viewer Settings")

    local research_info = research_panel:CreateFontString(nil, "OVERLAY", g.font)
    research_info:SetPoint("TOPLEFT", research_header, "BOTTOMLEFT", 0, -10)
    research_info:SetPoint("RIGHT", -15, 0)
    research_info:SetJustifyH("LEFT")
    research_info:SetText(
        "The Research Viewer allows you to view various talent and research trees (Order Halls, Dragonriding, Delves, etc.) from anywhere. You can also open it by middle-clicking the sfui minimap icon.")

    local toggle_research_button = CreateFlatButton(research_panel, "Open Research Viewer", 160, 22)
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
    custom_header:SetText("Manual Tree Entry")

    local custom_id_label = research_panel:CreateFontString(nil, "OVERLAY", g.font)
    custom_id_label:SetPoint("TOPLEFT", custom_header, "BOTTOMLEFT", 0, -10)
    custom_id_label:SetText("Enter Tree ID:")

    local custom_id_input = CreateFrame("EditBox", nil, research_panel, "InputBoxTemplate")
    custom_id_input:SetPoint("LEFT", custom_id_label, "RIGHT", 10, 0)
    custom_id_input:SetSize(80, 32)
    custom_id_input:SetAutoFocus(false)

    local add_trait_button = CreateFlatButton(research_panel, "Trait", 60, 22)
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
        GameTooltip:SetText("Trait Tree (Dragonriding, Delves, etc.)")
        GameTooltip:Show()
    end)
    add_trait_button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local add_garr_button = CreateFlatButton(research_panel, "Garr", 60, 22)
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
        GameTooltip:SetText("Garrison Tree (Class Halls, Covenants, etc.)")
        GameTooltip:Show()
    end)
    add_garr_button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- 9. Debug Panel
    local spec_id_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    spec_id_label:SetPoint("TOPLEFT", 15, -15)
    spec_id_label:SetText("Spec ID:")
    local spec_id_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    spec_id_value:SetPoint("LEFT", spec_id_label, "RIGHT", 5, 0)

    local color_swatch = debug_panel:CreateTexture(nil, "ARTWORK")
    color_swatch:SetSize(20, 20)
    color_swatch:SetPoint("LEFT", spec_id_value, "RIGHT", 10, 0)
    color_swatch:SetTexture("Interface/Buttons/WHITE8X8")

    local primary_power_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    primary_power_label:SetPoint("TOPLEFT", spec_id_label, "BOTTOMLEFT", 0, -15)
    primary_power_label:SetText("Primary Power:")
    local primary_power_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    primary_power_value:SetPoint("LEFT", primary_power_label, "RIGHT", 5, 0)

    local secondary_power_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    secondary_power_label:SetPoint("TOPLEFT", primary_power_label, "BOTTOMLEFT", 0, -15)
    secondary_power_label:SetText("Secondary Power:")
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
        local spec = C_SpecializationInfo.GetSpecialization()
        local specID = spec and C_SpecializationInfo.GetSpecializationInfo(spec) or "N/A"
        spec_id_value:SetText(tostring(specID))

        local color
        if specID and g.spec_colors[specID] then
            local c = g.spec_colors[specID]
            color = { r = c.r, g = c.g, b = c.b }
        elseif specID then
            local _, _, _, r, g, b = C_SpecializationInfo.GetSpecializationInfo(specID)
            if r then color = { r = r, g = g, b = b } end
        end
        if not color then
            local _, class = UnitClass("player"); color = RAID_CLASS_COLORS[class]
        end
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
    pet_warning_label:SetText("Pet Warning Status:")
    local pet_warning_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    pet_warning_value:SetPoint("LEFT", pet_warning_label, "RIGHT", 5, 0)

    local decor_cache_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    decor_cache_label:SetPoint("TOPLEFT", pet_warning_label, "BOTTOMLEFT", 0, -15)
    decor_cache_label:SetText("Decor Cache:")
    local decor_cache_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    decor_cache_value:SetPoint("LEFT", decor_cache_label, "RIGHT", 5, 0)

    local debug_refresh_button = CreateFlatButton(debug_panel, "Refresh", 100, 22)
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
