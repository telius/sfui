local addonName, addon = ...
sfui = sfui or {}
sfui.options = sfui.options or {}

local g = sfui.config
local common = sfui.common

local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local LibStub = _G.LibStub
local ipairs = _G.ipairs
local pairs = _G.pairs
local tostring = _G.tostring
local string_lower = string.lower

sfui.options.RegisterTab({
    id = "main",
    name = "main",
    build = function(main_panel, tab_button, options_frame)
        local CreateFlatButton = common.create_flat_button
        local create_checkbox = common.create_checkbox
        local create_slider_input = common.create_slider_input
        local white = sfui.config.colors.white
        local notify_spec_colors_updated = sfui.options.notify_spec_colors_updated

        local main_text = main_panel:CreateFontString(nil, "OVERLAY", g.font)
        main_text:SetPoint("TOPLEFT", 15, -15)
        main_text:SetTextColor(white[1], white[2], white[3])
        main_text:SetText("welcome to sfui. please select a category on the left.")

        local reload_button = CreateFlatButton(main_panel, "reload ui", 100, 22)
        reload_button:SetPoint("TOPLEFT", main_text, "BOTTOMLEFT", 0, -20)
        reload_button:SetScript("OnClick", function()
            if C_UI and C_UI.Reload then
                C_UI.Reload()
            elseif _G.ReloadUI then
                _G.ReloadUI()
            end
        end)

        local open_cv_main = CreateFlatButton(main_panel, "tracking manager", 140, 22)
        open_cv_main:SetPoint("LEFT", reload_button, "RIGHT", 10, 0)
        open_cv_main:SetScript("OnClick", function()
            sfui.trackedoptions.toggle_viewer()

            if SfuiCooldownsViewer and SfuiCooldownsViewer:IsShown() and options_frame then
                local _, rel = options_frame:GetPoint()
                if rel == SfuiCooldownsViewer then
                    local left = options_frame:GetLeft()
                    local top = options_frame:GetTop()
                    options_frame:ClearAllPoints()
                    options_frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
                end

                SfuiCooldownsViewer:ClearAllPoints()
                SfuiCooldownsViewer:SetPoint("TOPLEFT", options_frame, "TOPRIGHT", 5, 0)
            end
        end)

        local enable_tracking_manager_cb = create_checkbox(main_panel, "enable tracking manager", function()
            if SfuiDB.enableTrackingManager ~= nil then return SfuiDB.enableTrackingManager end
            return true
        end, function(checked)
            SfuiDB.enableTrackingManager = checked
            if open_cv_main then
                if checked then open_cv_main:Enable() else open_cv_main:Disable() end
            end
            if not checked and SfuiCooldownsViewer and SfuiCooldownsViewer:IsShown() then
                SfuiCooldownsViewer:Hide()
            end
        end, "Enables or disables the tracking manager module.")
        enable_tracking_manager_cb:SetPoint("LEFT", open_cv_main, "RIGHT", 15, 0)

        if SfuiDB.enableTrackingManager == false then
            open_cv_main:Disable()
        end

        local open_gear_main = CreateFlatButton(main_panel, "gear manager", 110, 22)
        open_gear_main:SetPoint("TOPLEFT", reload_button, "BOTTOMLEFT", 0, -10)
        open_gear_main:SetScript("OnClick", function()
            sfui.gear.toggle()
        end)

        local open_alts_main = CreateFlatButton(main_panel, "alts viewer", 100, 22)
        open_alts_main:SetPoint("LEFT", open_gear_main, "RIGHT", 10, 0)
        open_alts_main:SetScript("OnClick", function()
            sfui.alts.Toggle()
        end)

        local prevBtn = open_alts_main
        if sfui.isRetail or sfui.lootviewer then
            local open_loot_main = CreateFlatButton(main_panel, "loot viewer", 100, 22)
            open_loot_main:SetPoint("LEFT", prevBtn, "RIGHT", 10, 0)
            open_loot_main:SetScript("OnClick", function()
                sfui.lootviewer.Toggle()
            end)
            prevBtn = open_loot_main
        end

        local open_pets_main = CreateFlatButton(main_panel, "pet manager", 100, 22)
        open_pets_main:SetPoint("LEFT", prevBtn, "RIGHT", 10, 0)
        open_pets_main:SetScript("OnClick", function()
            sfui.select_options_tab("pets")
        end)

        local hide_minimap_icon_cb = create_checkbox(main_panel, "hide minimap icon", function()
            return (SfuiDB.minimap_icon and SfuiDB.minimap_icon.hide) or false
        end, function(checked)
            SfuiDB.minimap_icon = SfuiDB.minimap_icon or {}
            SfuiDB.minimap_icon.hide = checked
            local icon = LibStub and LibStub:GetLibrary("LibDBIcon-1.0", true)
            if icon then
                if checked then
                    icon:Hide("sfui")
                else
                    icon:Show("sfui")
                end
            end
        end, "hides the sfui minimap icon.")
        hide_minimap_icon_cb:SetPoint("TOPLEFT", open_gear_main, "BOTTOMLEFT", 0, -15)

        local enable_questlog_cb = create_checkbox(main_panel, "enable quest log", function()
            return sfui.questlog.is_enabled()
        end, function(checked)
            SfuiDB.questlogEnabled = checked
            SfuiDB.enableQuestLog = checked
            sfui.questlog.set_enabled(checked)
        end, "toggles the sfui custom quest log and objectives tracker (enabled by default).")
        enable_questlog_cb:SetPoint("LEFT", hide_minimap_icon_cb, "RIGHT", 150, 0)

        local enable_ring_cursor_cb = create_checkbox(main_panel, "enable ring cursor", "enableCursorRing", function(checked)
            sfui.cursor.toggle(checked)
        end, "toggles the ring cursor around the mouse.")
        enable_ring_cursor_cb:SetPoint("TOPLEFT", hide_minimap_icon_cb, "BOTTOMLEFT", 0, -10)

        local cursor_scale_slider = create_slider_input(main_panel, "cursor ring scale:", "cursorRingScale", 0.5, 2.0, 0.05,
            function(val)
                sfui.cursor.update_scale()
            end)
        cursor_scale_slider:SetPoint("LEFT", enable_ring_cursor_cb, "RIGHT", 150, 0)

        local enable_auto_compare_cb = create_checkbox(main_panel, "enable auto compare", "enableAutoCompare",
            function(checked)
                sfui.compare.init()
            end, "automatically sets 'alwaysCompareItems' cvar.")
        enable_auto_compare_cb:SetPoint("TOPLEFT", enable_ring_cursor_cb, "BOTTOMLEFT", 0, -10)

        local use_spec_color_cb = create_checkbox(main_panel, "use spec color", "useSpecColor", function(checked)
            notify_spec_colors_updated()
        end, "toggles whether the UI uses specialization/class based colors globally.")
        use_spec_color_cb:SetPoint("TOPLEFT", enable_auto_compare_cb, "BOTTOMLEFT", 0, -20)

        local fallback_label = main_panel:CreateFontString(nil, "OVERLAY", g.font)
        fallback_label:SetPoint("LEFT", use_spec_color_cb, "RIGHT", 150, 0)
        fallback_label:SetText("fallback:")

        local fallback_swatch = common.create_color_swatch(main_panel, SfuiDB.specColorFallback or { 1, 1, 1, 1 },
            function(r, green, b)
                SfuiDB.specColorFallback = { r, green, b, 1 }
                notify_spec_colors_updated()
            end)
        fallback_swatch:SetPoint("LEFT", fallback_label, "RIGHT", 5, 0)

        -- ─── Primary Texture Dropdown (ElvUI / SharedMedia Style) ───────────────
        local initialTexture = SfuiDB.barTexture or "Flat"
        if sfui.config.blizzard_bar_textures then
            local normInit = type(initialTexture) == "string" and initialTexture:gsub("\\", "/"):lower() or ""
            for name, path in pairs(sfui.config.blizzard_bar_textures) do
                if initialTexture == name or normInit == path:gsub("\\", "/"):lower() then
                    initialTexture = name
                    SfuiDB.barTexture = name
                    break
                end
            end
        end

        local function on_texture_selected(val, texturePath)
            SfuiDB._barTextureCustomized = true
            sfui.theme.ApplyThemeBarTexture(val)
        end

        local texture_dropdown = common.create_texture_dropdown(
            main_panel,
            200,
            on_texture_selected,
            initialTexture,
            "Primary Texture"
        )
        texture_dropdown:SetPoint("TOPLEFT", use_spec_color_cb, "BOTTOMLEFT", 0, -20)
        main_panel.texture_dropdown = texture_dropdown
        sfui.options.mainTab = sfui.options.mainTab or {}
        sfui.options.mainTab.texture_dropdown = texture_dropdown

        main_panel:HookScript("OnShow", function()
            if texture_dropdown and texture_dropdown.SetSelectedTexture then
                texture_dropdown:SetSelectedTexture(SfuiDB.barTexture or "Flat")
            end
        end)

        -- Spec Colors Customization
        local spec_header = main_panel:CreateFontString(nil, "OVERLAY", g.font)
        spec_header:SetPoint("TOPLEFT", texture_dropdown, "BOTTOMLEFT", 0, -25)
        spec_header:SetTextColor(white[1], white[2], white[3])
        spec_header:SetText("specialization colors:")

        local spec_swatches = {}
        local specs, specIDs = common.get_spec_color_options()
        local prevAnchor = spec_header

        for i, specID in ipairs(specIDs or {}) do
            local spec = specs and specs[specID]
            local specName = spec and spec.name or ("spec " .. i)
            local icon = spec and spec.icon
            if specID then
                local iconTex = main_panel:CreateTexture(nil, "ARTWORK")
                iconTex:SetSize(16, 16)
                if i == 1 then
                    iconTex:SetPoint("TOPLEFT", spec_header, "BOTTOMLEFT", 0, -10)
                else
                    iconTex:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 0, -8)
                end
                iconTex:SetTexture(icon)
                iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                local specText = main_panel:CreateFontString(nil, "OVERLAY", g.font)
                specText:SetPoint("LEFT", iconTex, "RIGHT", 6, 0)
                specText:SetTextColor(1, 1, 1, 1)
                specText:SetText(specName and string_lower(specName) or "")

                local curCol = (SfuiDB and SfuiDB.spec_colors and SfuiDB.spec_colors[specID])
                    or (sfui.config and sfui.config.spec_colors and sfui.config.spec_colors[specID])
                    or (common.get_spec_color_table and common.get_spec_color_table(specID))
                    or { 1, 1, 1, 1 }
                local swatch = common.create_color_swatch(main_panel, curCol, function(r, green, b)
                    SfuiDB.spec_colors = SfuiDB.spec_colors or {}
                    SfuiDB.spec_colors[specID] = { r, green, b, 1 }
                    local equivSpecID = (common.to_retail_spec_id and common.to_retail_spec_id(specID)) or (spec and spec.retailSpecID)
                    if equivSpecID and equivSpecID ~= specID then
                        SfuiDB.spec_colors[equivSpecID] = { r, green, b, 1 }
                    end
                    local camelotID = common.to_camelot_spec_id and common.to_camelot_spec_id(specID)
                    if camelotID and camelotID ~= specID then
                        SfuiDB.spec_colors[camelotID] = { r, green, b, 1 }
                    end
                    notify_spec_colors_updated()
                end)
                swatch:SetPoint("LEFT", iconTex, "LEFT", 150, 0)
                spec_swatches[specID] = swatch

                prevAnchor = iconTex
            end
        end

        local reset_spec_btn = CreateFlatButton(main_panel, "reset spec colors", 130, 20)
        if prevAnchor ~= spec_header then
            reset_spec_btn:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 0, -12)
        else
            reset_spec_btn:SetPoint("TOPLEFT", spec_header, "BOTTOMLEFT", 0, -12)
        end
        reset_spec_btn:SetScript("OnClick", function()
            for _, specID in ipairs(specIDs or {}) do
                if specID then
                    local equivSpecID = common.to_retail_spec_id and common.to_retail_spec_id(specID)
                    local camelotID   = common.to_camelot_spec_id and common.to_camelot_spec_id(specID)
                    if SfuiDB.spec_colors then
                        SfuiDB.spec_colors[specID] = nil
                        if equivSpecID then SfuiDB.spec_colors[equivSpecID] = nil end
                        if camelotID then SfuiDB.spec_colors[camelotID] = nil end
                    end
                    local baseColor = (sfui.config and sfui.config.spec_colors and sfui.config.spec_colors[specID])
                        or (common.get_spec_color_table and common.get_spec_color_table(specID))
                    local r, green, b = 1, 1, 1
                    if baseColor then
                        r, green, b = baseColor[1] or baseColor.r or 1, baseColor[2] or baseColor.g or 1, baseColor[3] or baseColor.b or 1
                    end
                    if spec_swatches[specID] then
                        spec_swatches[specID]:SetBackdropColor(r, green, b, 1)
                    end
                end
            end
            notify_spec_colors_updated()
        end)
    end,
})
