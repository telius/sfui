local addonName, addon = ...
sfui = sfui or {}
sfui.options = sfui.options or {}

local g = sfui.config
local common = sfui.common

local tostring = _G.tostring
local pairs = _G.pairs
local Enum = _G.Enum
local GetShapeshiftFormID = _G.GetShapeshiftFormID
local GetShapeshiftForm = _G.GetShapeshiftForm
local IsStealthed = _G.IsStealthed

sfui.options.RegisterTab({
    id = "debug",
    name = "debug",
    build = function(debug_panel, tab_button, options_frame)
        local CreateFlatButton = common.create_flat_button
        local white = sfui.config.colors.white

        local function get_power_type_name(power_enum)
            if not power_enum then return "None" end
            if type(power_enum) ~= "number" then return tostring(power_enum) end
            if Enum and Enum.PowerType then
                for name, value in pairs(Enum.PowerType) do
                    if value == power_enum then return name end
                end
            end
            return tostring(power_enum)
        end

        local debug_header = debug_panel:CreateFontString(nil, "OVERLAY", g.font_large)
        debug_header:SetPoint("TOPLEFT", 15, -15)
        debug_header:SetTextColor(white[1], white[2], white[3])
        debug_header:SetText("diagnostics & debug")

        local debug_refresh_button = CreateFlatButton(debug_panel, "refresh", 100, 22)
        debug_refresh_button:SetPoint("TOPLEFT", debug_header, "BOTTOMLEFT", 0, -10)

        local memory_button = CreateFlatButton(debug_panel, "memory profiler", 130, 22)
        memory_button:SetPoint("LEFT", debug_refresh_button, "RIGHT", 10, 0)
        memory_button:SetScript("OnClick", function()
            if sfui.mem and sfui.mem.ToggleGUI then
                sfui.mem.ToggleGUI()
            end
        end)

        -- Column 1: Character & Spec
        local col1_header = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        col1_header:SetPoint("TOPLEFT", debug_refresh_button, "BOTTOMLEFT", 0, -20)
        col1_header:SetTextColor(0, 1, 1, 1)
        col1_header:SetText("character & spec")

        local spec_id_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        spec_id_label:SetPoint("TOPLEFT", col1_header, "BOTTOMLEFT", 0, -12)
        spec_id_label:SetText("spec id:")

        local spec_id_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        spec_id_value:SetPoint("LEFT", spec_id_label, "RIGHT", 5, 0)

        local color_swatch = debug_panel:CreateTexture(nil, "ARTWORK")
        color_swatch:SetSize(16, 16)
        color_swatch:SetPoint("LEFT", spec_id_value, "RIGHT", 8, 0)
        color_swatch:SetTexture("Interface/Buttons/WHITE8X8")

        local primary_power_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        primary_power_label:SetPoint("TOPLEFT", spec_id_label, "BOTTOMLEFT", 0, -12)
        primary_power_label:SetText("primary power:")
        local primary_power_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        primary_power_value:SetPoint("LEFT", primary_power_label, "RIGHT", 5, 0)

        local secondary_power_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        secondary_power_label:SetPoint("TOPLEFT", primary_power_label, "BOTTOMLEFT", 0, -12)
        secondary_power_label:SetText("secondary power:")
        local secondary_power_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        secondary_power_value:SetPoint("LEFT", secondary_power_label, "RIGHT", 5, 0)

        local form_id_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        form_id_label:SetPoint("TOPLEFT", secondary_power_label, "BOTTOMLEFT", 0, -12)
        form_id_label:SetText("current form id:")
        local form_id_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        form_id_value:SetPoint("LEFT", form_id_label, "RIGHT", 5, 0)

        -- Column 2: Modules & Automation
        local col2_header = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        col2_header:SetPoint("TOPLEFT", debug_panel, "TOPLEFT", 280, -78)
        col2_header:SetTextColor(0, 1, 1, 1)
        col2_header:SetText("modules & automation")

        local pet_warning_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        pet_warning_label:SetPoint("TOPLEFT", col2_header, "BOTTOMLEFT", 0, -12)
        pet_warning_label:SetText("pet warning status:")
        local pet_warning_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        pet_warning_value:SetPoint("LEFT", pet_warning_label, "RIGHT", 5, 0)

        local hammer_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        hammer_label:SetPoint("TOPLEFT", pet_warning_label, "BOTTOMLEFT", 0, -12)
        hammer_label:SetText("master's hammer:")
        local hammer_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        hammer_value:SetPoint("LEFT", hammer_label, "RIGHT", 5, 0)

        local hammer_id_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        hammer_id_label:SetPoint("TOPLEFT", hammer_label, "BOTTOMLEFT", 0, -12)
        hammer_id_label:SetText("hammer item id:")
        local hammer_id_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        hammer_id_value:SetPoint("LEFT", hammer_id_label, "RIGHT", 5, 0)

        local function update_debug_info()
            local specID = common.get_current_spec_id()
            spec_id_value:SetText(specID > 0 and tostring(specID) or "N/A")

            local color = common.get_class_or_spec_color()
            if color then color_swatch:SetColorTexture(color[1], color[2], color[3]) end

            if common.get_primary_resource then
                primary_power_value:SetText(get_power_type_name(common.get_primary_resource()))
            end
            if common.get_secondary_resource then
                secondary_power_value:SetText(get_power_type_name(common.get_secondary_resource()))
            end

            if sfui.reminders and sfui.reminders.get_status then
                pet_warning_value:SetText(sfui.reminders.get_status())
            else
                pet_warning_value:SetText("N/A (Module Missing)")
            end

            local hammer = sfui.hammer or sfui.automation
            if hammer and hammer.has_repair_hammer then
                local found, name, _, itemID = hammer.has_repair_hammer(true)
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

            local formID = (GetShapeshiftFormID and GetShapeshiftFormID()) or (GetShapeshiftForm and GetShapeshiftForm()) or 0
            local isStealthed = (IsStealthed and IsStealthed()) or false
            form_id_value:SetText(tostring(formID) .. (isStealthed and " |cff00ffff(Stealthed)|r" or ""))
        end

        debug_refresh_button:SetScript("OnClick", update_debug_info)

        debug_panel.update_debug_info = update_debug_info
        update_debug_info()
    end,
    onShow = function(debug_panel, tab_button, options_frame)
        if debug_panel and debug_panel.update_debug_info then
            debug_panel.update_debug_info()
        end
    end,
})
