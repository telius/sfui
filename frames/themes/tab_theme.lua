local addonName, addon = ...
sfui = sfui or {}
sfui.options = sfui.options or {}

local g = sfui.config
local common = sfui.common
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local ipairs = _G.ipairs
local pairs = _G.pairs
local table_insert = _G.table.insert

sfui.options.RegisterTab({
    id = "theme",
    name = "theme",
    build = function(theme_panel, tab_button, options_frame)
        local CreateFlatButton = common.create_flat_button
        local create_checkbox = common.create_checkbox
        local create_color_swatch = common.create_color_swatch
        local white = sfui.config.colors.white

        theme_panel.customContentHeight = 545

        -- ─── Header ─────────────────────────────────────────────────────────
        local header = theme_panel:CreateFontString(nil, "OVERLAY", g.font)
        header:SetPoint("TOPLEFT", 15, -15)
        header:SetTextColor(white[1], white[2], white[3])
        header:SetText("theme & visual style")

        local desc = theme_panel:CreateFontString(nil, "OVERLAY", g.font_small or "GameFontHighlightSmall")
        desc:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
        desc:SetTextColor(0.7, 0.7, 0.7, 1)
        desc:SetText("choose between Camelot's heavy bronze fantasy style and Retail's minimalist dark slate.")

        -- ─── Status Text Indicator ───────────────────────────────────────────
        local status_text = theme_panel:CreateFontString(nil, "OVERLAY", g.font_small or "GameFontHighlightSmall")
        status_text:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -12)

        local function update_status_text()
            local activeID = sfui.theme.GetActiveThemeID()
            local mode = (SfuiDB and (SfuiDB.themeMode or (SfuiDB.theme and SfuiDB.theme.mode))) or "auto"
            local pal = sfui.theme.GetPalette()
            local isCamelotSupported = sfui.theme.IsCamelotSupported()
            local clientName = isCamelotSupported and "Classic Forever / Camelot" or (sfui.isClassic and "Classic Era" or "Retail")
            local supported = isCamelotSupported and "|cff00ff00Available|r" or "|cffff3333Restricted to Camelot|r"

            if not isCamelotSupported then
                status_text:SetText(string.format("Current Style: |cff%02x%02x%02x%s|r  •  Client: |cffffffff%s|r  •  Camelot Bronze: %s",
                    math.floor(pal.headerColor[1] * 255),
                    math.floor(pal.headerColor[2] * 255),
                    math.floor(pal.headerColor[3] * 255),
                    pal.name,
                    clientName,
                    supported
                ))
            elseif mode == "auto" then
                status_text:SetText(string.format("Current Style: |cff%02x%02x%02x%s|r  •  Auto-detected: |cffffffff%s|r  •  Camelot Bronze: %s",
                    math.floor(pal.headerColor[1] * 255),
                    math.floor(pal.headerColor[2] * 255),
                    math.floor(pal.headerColor[3] * 255),
                    pal.name,
                    clientName,
                    supported
                ))
            else
                status_text:SetText(string.format("Current Style: |cff%02x%02x%02x%s|r (Forced %s)  •  Client: |cffffffff%s|r",
                    math.floor(pal.headerColor[1] * 255),
                    math.floor(pal.headerColor[2] * 255),
                    math.floor(pal.headerColor[3] * 255),
                    pal.name,
                    mode,
                    clientName
                ))
            end
        end

        -- ─── Dynamic Theme Mode Toggle Buttons ────────────────────────────────
        local toggle_label = theme_panel:CreateFontString(nil, "OVERLAY", g.font)
        toggle_label:SetPoint("TOPLEFT", status_text, "BOTTOMLEFT", 0, -16)
        toggle_label:SetTextColor(white[1], white[2], white[3])
        toggle_label:SetText("select theme mode:")

        local toggleButtons = {}
        local lastBtn = nil

        -- 1. Auto-Detect Button
        local btnAuto = CreateFlatButton(theme_panel, "Auto-Detect", 115, 26)
        btnAuto:SetPoint("TOPLEFT", toggle_label, "BOTTOMLEFT", 0, -8)
        btnAuto.themeMode = "auto"
        btnAuto.baseLabel = "Auto-Detect"
        table_insert(toggleButtons, btnAuto)
        lastBtn = btnAuto

        -- 2. Dynamically instantiate a button for each registered theme
        local registeredThemes, themeOrder = sfui.theme.GetRegisteredThemes()
        for _, themeID in ipairs(themeOrder) do
            local themeDef = registeredThemes[themeID]
            if themeDef then
                local label = themeDef.name or themeID
                local btnW = math.max(120, #label * 8 + 20)
                local btn = CreateFlatButton(theme_panel, label, btnW, 26)
                btn:SetPoint("LEFT", lastBtn, "RIGHT", 6, 0)
                btn.themeMode = themeID
                btn.baseLabel = label
                table_insert(toggleButtons, btn)
                lastBtn = btn
            end
        end

        for _, btn in ipairs(toggleButtons) do
            btn:SetScript("OnClick", function()
                if btn.themeMode == "camelot" and not sfui.theme.IsCamelotSupported() then
                    sfui.common.print("|cffff3333The bronze Camelot theme is exclusive to Camelot/Forever (bronze assets are not present in Retail).|r")
                    return
                end
                sfui.theme.SetTheme(btn.themeMode)
                theme_panel:RefreshThemeControls()
                local pal = sfui.theme.GetPalette()
                sfui.common.print("theme mode set to '" .. btn.themeMode .. "' (active: " .. pal.name .. ").")
            end)
        end

        -- ─── Camelot Style Detail Checkboxes ──────────────────────────────────
        local brackets_cb = create_checkbox(theme_panel, "enable ornate corner brackets", function()
            return SfuiDB.themeCornerBrackets ~= false
        end, function(checked)
            SfuiDB.themeCornerBrackets = checked
            sfui.theme.ApplyCurrentTheme()
            theme_panel:RefreshThemeControls()
        end, "Displays sculpted heavy bronze corner brackets clamped onto window frames in Camelot mode.")
        brackets_cb:SetPoint("TOPLEFT", btnAuto, "BOTTOMLEFT", 0, -18)

        local textured_bg_cb = create_checkbox(theme_panel, "use textured parchment & metal backgrounds", function()
            return SfuiDB.themeTexturedBackdrop ~= false
        end, function(checked)
            SfuiDB.themeTexturedBackdrop = checked
            sfui.theme.ApplyCurrentTheme()
            theme_panel:RefreshThemeControls()
        end, "Enables rich textured dark parchment and slate background art on windows instead of flat dark fills.")
        textured_bg_cb:SetPoint("TOPLEFT", brackets_cb, "BOTTOMLEFT", 0, -8)

        local bronze_btn_cb = create_checkbox(theme_panel, "enable sculpted bronze buttons", function()
            return SfuiDB.themeBronzeButtons == true
        end, function(checked)
            SfuiDB.themeBronzeButtons = checked
            sfui.theme.ApplyCurrentTheme()
            theme_panel:RefreshThemeControls()
        end, "Enables sculpted bronze button and tab styling in Camelot mode instead of the default flat buttons.")
        bronze_btn_cb:SetPoint("TOPLEFT", textured_bg_cb, "BOTTOMLEFT", 0, -8)

        -- ─── Color Palette Swatches ───────────────────────────────────────────
        local palette_header = theme_panel:CreateFontString(nil, "OVERLAY", g.font)
        palette_header:SetPoint("TOPLEFT", bronze_btn_cb, "BOTTOMLEFT", 0, -20)
        palette_header:SetTextColor(white[1], white[2], white[3])
        palette_header:SetText("accent & highlight colors")

        -- Accent Color
        local accent_label = theme_panel:CreateFontString(nil, "OVERLAY", g.font_small or "GameFontHighlightSmall")
        accent_label:SetPoint("TOPLEFT", palette_header, "BOTTOMLEFT", 0, -12)
        accent_label:SetTextColor(0.8, 0.8, 0.8, 1)
        accent_label:SetText("primary accent:")

        local accent_swatch = create_color_swatch(theme_panel, sfui.config.appearance.accentColor, function(r, g, b)
            sfui.config.appearance.accentColor = { r, g, b, 1 }
            SfuiDB.customAccentColor = { r, g, b, 1 }
            sfui.theme.ApplyCurrentTheme()
            theme_panel:RefreshThemeControls()
        end)
        accent_swatch:SetPoint("LEFT", accent_label, "RIGHT", 15, 0)

        -- Highlight Color
        local hl_label = theme_panel:CreateFontString(nil, "OVERLAY", g.font_small or "GameFontHighlightSmall")
        hl_label:SetPoint("LEFT", accent_swatch, "RIGHT", 30, 0)
        hl_label:SetTextColor(0.8, 0.8, 0.8, 1)
        hl_label:SetText("highlight / selection:")

        local hl_swatch = create_color_swatch(theme_panel, sfui.config.appearance.highlightColor, function(r, g, b)
            sfui.config.appearance.highlightColor = { r, g, b, 1 }
            SfuiDB.customHighlightColor = { r, g, b, 1 }
            sfui.theme.ApplyCurrentTheme()
            theme_panel:RefreshThemeControls()
        end)
        hl_swatch:SetPoint("LEFT", hl_label, "RIGHT", 15, 0)

        -- Reset Colors Button
        local reset_colors_btn = CreateFlatButton(theme_panel, "reset to theme defaults", 160, 20)
        reset_colors_btn:SetPoint("LEFT", hl_swatch, "RIGHT", 25, 0)
        reset_colors_btn:SetScript("OnClick", function()
            SfuiDB.customAccentColor = nil
            SfuiDB.customHighlightColor = nil
            sfui.theme.ApplyCurrentTheme()
            theme_panel:RefreshThemeControls()
        end)

        -- ─── Live Visual Sample Card ──────────────────────────────────────────
        local preview_label = theme_panel:CreateFontString(nil, "OVERLAY", g.font)
        preview_label:SetPoint("TOPLEFT", accent_label, "BOTTOMLEFT", 0, -22)
        preview_label:SetTextColor(white[1], white[2], white[3])
        preview_label:SetText("live window & widget preview:")

        local preview_card = CreateFrame("Frame", nil, theme_panel, "BackdropTemplate")
        preview_card:SetSize(420, 145)
        preview_card:SetPoint("TOPLEFT", preview_label, "BOTTOMLEFT", 0, -10)
        theme_panel.previewCard = preview_card

        local preview_title = preview_card:CreateFontString(nil, "OVERLAY", g.font)
        preview_title:SetPoint("TOPLEFT", preview_card, "TOPLEFT", 16, -14)

        local sample_close = common.create_close_button(preview_card, function() end, 22)
        sample_close:SetPoint("TOPRIGHT", preview_card, "TOPRIGHT", -8, -8)

        local sample_header = CreateFrame("Button", nil, preview_card, "BackdropTemplate")
        sample_header:SetSize(388, 24)
        sample_header:SetPoint("TOPLEFT", preview_card, "TOPLEFT", 16, -42)
        sample_header.accent = sample_header:CreateTexture(nil, "ARTWORK")
        sample_header.accent:SetWidth(3)
        sample_header.accent:SetPoint("TOPLEFT", sample_header, "TOPLEFT", 0, 0)
        sample_header.accent:SetPoint("BOTTOMLEFT", sample_header, "BOTTOMLEFT", 0, 0)
        sample_header.accent:SetColorTexture(1, 1, 1, 1)

        sample_header.title = sample_header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sample_header.count = sample_header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sample_header.title:SetText("sample objective header")
        sample_header.count:SetText("3")

        local preview_body = preview_card:CreateFontString(nil, "OVERLAY", g.font_small or "GameFontHighlightSmall")
        preview_body:SetPoint("TOPLEFT", sample_header, "BOTTOMLEFT", 0, -10)
        preview_body:SetPoint("RIGHT", preview_card, "RIGHT", -20, 0)
        preview_body:SetJustifyH("LEFT")

        local sample_button = CreateFlatButton(preview_card, "sample button", 120, 22)
        sample_button:SetPoint("BOTTOMLEFT", preview_card, "BOTTOMLEFT", 16, 14)

        function preview_card:Refresh()
            sfui.theme.ApplyWindowStyle(preview_card, { cornerBrackets = (SfuiDB.themeCornerBrackets ~= false) })
            sfui.theme.ApplyCloseButtonStyle(sample_close)
            sfui.theme.ApplyQuestHeaderStyle(sample_header)
            sfui.theme.ApplyButtonStyle(sample_button, false)

            local pal = sfui.theme.GetPalette()
            preview_title:SetTextColor(pal.headerColor[1], pal.headerColor[2], pal.headerColor[3])
            preview_title:SetText(pal.name .. " Preview Window")

            local isC = sfui.theme.IsCamelotActive()
            if isC then
                preview_body:SetTextColor(pal.tabNormal[1], pal.tabNormal[2], pal.tabNormal[3])
                if sfui.theme.IsBronzeButtonActive() then
                    preview_body:SetText("Tactile cast-bronze window, ornate corner brackets, embossed banners, sculpted bronze panel buttons, and red/gold close button.")
                else
                    preview_body:SetText("Tactile cast-bronze window, ornate corner brackets, embossed banners, clean flat dark buttons, and red/gold close button.")
                end
            else
                preview_body:SetTextColor(0.8, 0.8, 0.8, 1)
                preview_body:SetText("Clean, flat minimalist black border with electric cyan/purple accents and flat buttons.")
            end
        end

        -- ─── Master Refresh Function ──────────────────────────────────────────
        function theme_panel:RefreshThemeControls()
            local savedMode = (SfuiDB and (SfuiDB.themeMode or (SfuiDB.theme and SfuiDB.theme.mode))) or "auto"
            local pal = sfui.theme.GetPalette()
            local isCamelot = sfui.theme.IsCamelotActive()
            local isCamelotSupported = sfui.theme.IsCamelotSupported()

            -- Update Status Text
            update_status_text()

            -- Hide Camelot-specific checkboxes on Retail
            if isCamelotSupported then
                brackets_cb:Show()
                textured_bg_cb:Show()
                bronze_btn_cb:Show()
            else
                brackets_cb:Hide()
                textured_bg_cb:Hide()
                bronze_btn_cb:Hide()
            end

            -- Update Dynamically Created Toggle Buttons
            local hexAccent = string.format("%02x%02x%02x",
                math.floor(pal.accentColor[1] * 255),
                math.floor(pal.accentColor[2] * 255),
                math.floor(pal.accentColor[3] * 255)
            )

            for _, btn in ipairs(toggleButtons) do
                local isSelected = (btn.themeMode == savedMode)
                btn.isSelected = isSelected
                local fs = btn:GetFontString()

                if btn.themeMode == "camelot" and not isCamelotSupported then
                    btn:Disable()
                    if btn.SetBackdrop then
                        btn:SetBackdrop({
                            bgFile   = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
                            edgeFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
                            edgeSize = 1,
                            insets   = { left = 0, right = 0, top = 0, bottom = 0 }
                        })
                        btn:SetBackdropColor(0.04, 0.04, 0.04, 0.40)
                        btn:SetBackdropBorderColor(0.12, 0.12, 0.12, 0.6)
                    end
                    if fs then
                        fs:SetText(btn.baseLabel .. " |cffff5555(Camelot Only)|r")
                        fs:SetTextColor(0.40, 0.40, 0.40, 1)
                    end
                elseif isSelected then
                    btn:Enable()
                    if btn.SetBackdrop then
                        btn:SetBackdrop({
                            bgFile   = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
                            edgeFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
                            edgeSize = 1,
                            insets   = { left = 0, right = 0, top = 0, bottom = 0 }
                        })
                        if isCamelot then
                            btn:SetBackdropColor(0.24, 0.18, 0.10, 0.98)
                            btn:SetBackdropBorderColor(pal.accentColor[1], pal.accentColor[2], pal.accentColor[3], 1)
                        else
                            btn:SetBackdropColor(0.18, 0.12, 0.28, 0.98)
                            btn:SetBackdropBorderColor(pal.accentColor[1], pal.accentColor[2], pal.accentColor[3], 1)
                        end
                    end
                    if fs then
                        fs:SetText("|cff" .. hexAccent .. "•|r " .. btn.baseLabel)
                        fs:SetTextColor(1, 1, 1, 1)
                    end
                else
                    btn:Enable()
                    if btn.SetBackdrop then
                        btn:SetBackdrop({
                            bgFile   = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
                            edgeFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
                            edgeSize = 1,
                            insets   = { left = 0, right = 0, top = 0, bottom = 0 }
                        })
                        if isCamelot then
                            btn:SetBackdropColor(0.09, 0.08, 0.06, 0.90)
                            btn:SetBackdropBorderColor(0.22, 0.18, 0.12, 0.8)
                        else
                            btn:SetBackdropColor(0.04, 0.04, 0.04, 0.90)
                            btn:SetBackdropBorderColor(0.16, 0.16, 0.16, 1)
                        end
                    end
                    if fs then
                        fs:SetText(btn.baseLabel)
                        fs:SetTextColor(0.60, 0.60, 0.60, 1)
                    end
                end
            end

            -- Update Swatches
            local curAccent = (SfuiDB and SfuiDB.customAccentColor) or pal.accentColor
            local curHl = (SfuiDB and SfuiDB.customHighlightColor) or pal.highlightColor
            if accent_swatch and accent_swatch.SetBackdropColor then
                accent_swatch:SetBackdropColor(curAccent[1], curAccent[2], curAccent[3], 1)
            end
            if hl_swatch and hl_swatch.SetBackdropColor then
                hl_swatch:SetBackdropColor(curHl[1], curHl[2], curHl[3], 1)
            end

            -- Refresh Preview Card
            if preview_card and preview_card.Refresh then
                preview_card:Refresh()
            end
        end

        -- Initial sync
        theme_panel:RefreshThemeControls()

        -- Auto-refresh when panel becomes visible
        theme_panel:HookScript("OnShow", function()
            theme_panel:RefreshThemeControls()
        end)

        -- Live sync on external theme change events (e.g. slash commands)
        sfui.events.RegisterMessage("SFUI_THEME_CHANGED", function()
            if theme_panel:IsVisible() then
                theme_panel:RefreshThemeControls()
            end
        end)
    end,
    onShow = function(container_panel, tab_button, options_frame)
        local content = tab_button and tab_button.content_panel
        if content and content.RefreshThemeControls then
            content:RefreshThemeControls()
        end
    end,
})
