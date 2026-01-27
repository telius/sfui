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

    local CreateFlatButton = sfui.common.CreateFlatButton

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

    local function CreateCheckbox(parent, label, dbKey, onClickFunc, tooltip)
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

    local function CreateSlider(parent, label, dbKey, minVal, maxVal, step, onValueChangedFunc)
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

    local function OnTabClick(self)
        select_tab(self)
    end

    local function OnTabEnter(self)
        self:GetFontString():SetTextColor(c.tabs.highlight_color.r, c.tabs.highlight_color.g, c.tabs.highlight_color.b)
    end

    local function OnTabLeave(self)
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

        tab_button:SetScript("OnClick", OnTabClick)
        tab_button:SetScript("OnEnter", OnTabEnter)
        tab_button:SetScript("OnLeave", OnTabLeave)

        table.insert(frame.tabs, { button = tab_button, panel = content_panel })
        return content_panel, tab_button
    end

    local last_tab_button
    local main_panel, main_tab_button = create_tab("main")
    main_tab_button:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -40)
    last_tab_button = main_tab_button

    local currency_items_panel, currency_tab_button = create_tab("currency/items")
    currency_tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, 5)
    last_tab_button = currency_tab_button

    local bars_panel, bars_tab_button = create_tab("bars")
    bars_tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, 5)
    last_tab_button = bars_tab_button

    local minimap_panel, minimap_tab_button = create_tab("minimap")
    minimap_tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, 5)
    last_tab_button = minimap_tab_button

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

    local hide_minimap_icon_cb = CreateCheckbox(main_panel, "Hide Minimap Icon", "minimap_icon.hide", function(checked)
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

    local disable_vehicle_cb = CreateCheckbox(main_panel, "Disable Vehicle UI", "disableVehicle", nil,
        "Restores the default WoW vehicle/overlay bar.")
    disable_vehicle_cb:SetPoint("TOPLEFT", vehicle_header, "BOTTOMLEFT", 0, -10)

    local merchant_header = main_panel:CreateFontString(nil, "OVERLAY", g.font)
    merchant_header:SetPoint("TOPLEFT", disable_vehicle_cb, "BOTTOMLEFT", 0, -30)
    merchant_header:SetTextColor(white[1], white[2], white[3])
    merchant_header:SetText("Merchant Settings")

    local auto_sell_cb = CreateCheckbox(main_panel, "Auto-Sell Greys", "autoSellGreys", nil,
        "Automatically sells all grey items when opening a merchant.")
    auto_sell_cb:SetPoint("TOPLEFT", merchant_header, "BOTTOMLEFT", 0, -10)

    local disable_merchant_cb = CreateCheckbox(main_panel, "Disable Merchant Frame", "disableMerchant", nil,
        "Restores the default WoW merchant frame.")
    disable_merchant_cb:SetPoint("TOPLEFT", auto_sell_cb, "BOTTOMLEFT", 0, -10)

    local auto_repair_cb = CreateCheckbox(main_panel, "Auto-Repair", "autoRepair", nil,
        "Automatically repairs gear (guild first, skips if blacksmith hammer available).")
    auto_repair_cb:SetPoint("TOPLEFT", disable_merchant_cb, "BOTTOMLEFT", 0, -10)

    local minimap_header = minimap_panel:CreateFontString(nil, "OVERLAY", g.font)
    minimap_header:SetPoint("TOPLEFT", 15, -15)
    minimap_header:SetTextColor(white[1], white[2], white[3])
    minimap_header:SetText("Minimap Settings")

    local collect_cb = CreateCheckbox(minimap_panel, "Collect Buttons", "minimap_collect_buttons", function(checked)
        if sfui.minimap and sfui.minimap.EnableButtonManager then
            sfui.minimap.EnableButtonManager(checked)
        end
    end, "Collects minimap buttons into a bar.")
    collect_cb:SetPoint("TOPLEFT", minimap_header, "BOTTOMLEFT", 0, -10)

    local mouseover_cb = CreateCheckbox(minimap_panel, "Mouseover Only", "minimap_buttons_mouseover", function(checked)
        if sfui.minimap and sfui.minimap.EnableButtonManager and SfuiDB.minimap_collect_buttons then
            -- Re-enable to refresh logic
            sfui.minimap.EnableButtonManager(false)
            sfui.minimap.EnableButtonManager(true)
        end
    end, "Only show the button bar when hovering the minimap. Also moves Group Finder eye to Top Left.")
    mouseover_cb:SetPoint("TOPLEFT", collect_cb, "BOTTOMLEFT", 0, -10)




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

        if sfui.common.GetPrimaryResource then
            primary_power_value:SetText(get_power_type_name(sfui.common.GetPrimaryResource()))
        end
        if sfui.common.GetSecondaryResource then
            secondary_power_value:SetText(get_power_type_name(sfui.common.GetSecondaryResource()))
        end
    end

    -- Pet Warning Status
    local pet_warning_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    pet_warning_label:SetPoint("TOPLEFT", secondary_power_label, "BOTTOMLEFT", 0, -15)
    pet_warning_label:SetText("Pet Warning Status:")
    local pet_warning_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    pet_warning_value:SetPoint("LEFT", pet_warning_label, "RIGHT", 5, 0)



    local debug_refresh_button = CreateFlatButton(debug_panel, "Refresh", 100, 22)
    debug_refresh_button:SetPoint("BOTTOM", debug_panel, "BOTTOM", 0, 10)

    -- Update update_debug_info to include pet warning status
    local original_update_debug_info = update_debug_info
    function update_debug_info()
        original_update_debug_info() -- Call original function

        if sfui.warnings and sfui.warnings.GetStatus then
            pet_warning_value:SetText(sfui.warnings.GetStatus())
        else
            pet_warning_value:SetText("N/A (Module Missing)")
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



    local bars_header = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
    bars_header:SetPoint("TOPLEFT", 15, -15)
    bars_header:SetTextColor(white[1], white[2], white[3])
    bars_header:SetText("Bar Settings")

    local texture_label = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
    texture_label:SetPoint("TOPLEFT", bars_header, "BOTTOMLEFT", 0, -10)
    texture_label:SetText("Bar Texture:")

    local dropdown = CreateFrame("Frame", "sfui_options_texture_dropdown", bars_panel, "UIDropDownMenuTemplate")
    dropdown:SetPoint("LEFT", texture_label, "RIGHT", 10, 0)

    local function OnTextureSelect(self)
        local textureName = self.value
        SfuiDB.barTexture = textureName

        local LSM = LibStub("LibSharedMedia-3.0", true)
        local texturePath = LSM and LSM:Fetch("statusbar", textureName) or "Interface/Buttons/WHITE8X8"

        if sfui.bars and sfui.bars.SetBarTexture then
            sfui.bars:SetBarTexture(texturePath)
        end
        UIDropDownMenu_SetSelectedValue(dropdown, textureName)
    end

    local function InitializeTextureDropdown(self, level)
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
            info.func = OnTextureSelect
            info.checked = (SfuiDB.barTexture == name)
            UIDropDownMenu_AddButton(info)
        end
    end

    UIDropDownMenu_Initialize(dropdown, InitializeTextureDropdown)
    UIDropDownMenu_SetSelectedValue(dropdown, SfuiDB.barTexture)
    UIDropDownMenu_SetWidth(dropdown, 150)
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
