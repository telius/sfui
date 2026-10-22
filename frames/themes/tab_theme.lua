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
    icon = "Interface\\Icons\\Spell_Shadow_AntiShadow",
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
        desc:SetText("choose between camelot's heavy bronze fantasy style and retail's minimalist dark slate. settings are saved account-wide.")

        -- ─── Status Text Indicator ───────────────────────────────────────────
        local status_text = theme_panel:CreateFontString(nil, "OVERLAY", g.font_small or "GameFontHighlightSmall")
        status_text:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -12)

        local function update_status_text()
            local activeID = sfui.theme.GetActiveThemeID()
            local mode = (SfuiDB and (SfuiDB.themeMode or (SfuiDB.theme and SfuiDB.theme.mode))) or "auto"
            local pal = sfui.theme.GetPalette()
            local isCamelotSupported = sfui.theme.IsCamelotSupported()
            local clientName = isCamelotSupported and "classic forever / camelot" or (sfui.isClassic and "classic era" or "retail")
            local supported = isCamelotSupported and "|cff00ff00available|r" or "|cffff3333restricted to camelot|r"
            local palName = tostring(pal.name or activeID):lower()

            if not isCamelotSupported then
                status_text:SetText(string.format("current style: |cff%02x%02x%02x%s|r  •  client: |cffffffff%s|r  •  bronze: %s",
                    math.floor(pal.headerColor[1] * 255),
                    math.floor(pal.headerColor[2] * 255),
                    math.floor(pal.headerColor[3] * 255),
                    palName,
                    clientName,
                    supported
                ))
            elseif mode == "auto" then
                status_text:SetText(string.format("current style: |cff%02x%02x%02x%s|r  •  auto-detected: |cffffffff%s|r  •  bronze: %s",
                    math.floor(pal.headerColor[1] * 255),
                    math.floor(pal.headerColor[2] * 255),
                    math.floor(pal.headerColor[3] * 255),
                    palName,
                    clientName,
                    supported
                ))
            else
                status_text:SetText(string.format("current style: |cff%02x%02x%02x%s|r (forced %s)  •  client: |cffffffff%s|r",
                    math.floor(pal.headerColor[1] * 255),
                    math.floor(pal.headerColor[2] * 255),
                    math.floor(pal.headerColor[3] * 255),
                    palName,
                    tostring(mode):lower(),
                    clientName
                ))
            end
        end

        -- ─── Dynamic Theme Mode Toggle Buttons ────────────────────────────────
        local toggle_label = theme_panel:CreateFontString(nil, "OVERLAY", g.font)
        toggle_label:SetPoint("TOPLEFT", status_text, "BOTTOMLEFT", 0, -16)
        toggle_label:SetTextColor(white[1], white[2], white[3])
        toggle_label:SetText("select theme mode (account-wide):")

        local toggleButtons = {}
        local lastBtn = nil

        -- 1. Auto-Detect Button
        -- uniform grid sized to the options content width (~540px usable)
        local THEME_BTN_GAP, THEME_BTN_H, THEME_BTNS_PER_ROW = 6, 26, 4
        local gridW = math.max(400, (theme_panel:GetWidth() or 0) - 30)
        if gridW > 540 then gridW = 540 end
        local THEME_BTN_W = math.floor((gridW - THEME_BTN_GAP * (THEME_BTNS_PER_ROW - 1)) / THEME_BTNS_PER_ROW)
        local btnAuto = CreateFlatButton(theme_panel, "auto-detect", THEME_BTN_W, THEME_BTN_H)
        btnAuto:SetPoint("TOPLEFT", toggle_label, "BOTTOMLEFT", 0, -8)
        btnAuto.themeMode = "auto"
        btnAuto.baseLabel = "auto-detect"
        table_insert(toggleButtons, btnAuto)
        lastBtn = btnAuto
        local rowFirstBtn, countInRow = btnAuto, 1

        -- 2. Dynamically instantiate a button for each registered theme
        local registeredThemes, themeOrder = sfui.theme.GetRegisteredThemes()
        for _, themeID in ipairs(themeOrder) do
            local themeDef = registeredThemes[themeID]
            if themeDef then
                local isBronzeTheme = (themeID == "camelot" or themeID == "bronze" or themeDef.id == "camelot" or themeDef.id == "bronze")
                local label = isBronzeTheme and "bronze" or (themeDef.name or themeID):lower()
                local btn = CreateFlatButton(theme_panel, label, THEME_BTN_W, THEME_BTN_H)
                if countInRow >= THEME_BTNS_PER_ROW then
                    btn:SetPoint("TOPLEFT", rowFirstBtn, "BOTTOMLEFT", 0, -THEME_BTN_GAP)
                    rowFirstBtn, countInRow = btn, 1
                else
                    btn:SetPoint("LEFT", lastBtn, "RIGHT", THEME_BTN_GAP, 0)
                    countInRow = countInRow + 1
                end
                btn.themeMode = isBronzeTheme and "bronze" or themeID
                btn.baseLabel = label
                local tooltipDesc = (themeDef.desc or ""):lower()
                if tooltipDesc ~= "" then
                    sfui.common.attach_tooltip(btn, label, tooltipDesc)
                end
                table_insert(toggleButtons, btn)
                lastBtn = btn
            end
        end

        -- grow the scrollable content height by the extra button rows
        local themeRows = math.ceil(#toggleButtons / THEME_BTNS_PER_ROW)
        theme_panel.customContentHeight = 575 + (themeRows - 1) * (THEME_BTN_H + THEME_BTN_GAP)

        for _, btn in ipairs(toggleButtons) do
            btn:SetScript("OnClick", function()
                if not sfui.theme.IsThemeAvailable(btn.themeMode) then
                    if btn.themeMode == "camelot" or btn.themeMode == "bronze" then
                        sfui.common.print("|cffff3333the bronze theme is exclusive to camelot/forever (bronze assets are not present in retail).|r")
                    else
                        sfui.common.print("|cffff3333the art for this theme is not available on this client.|r")
                    end
                    return
                end
                sfui.theme.SetTheme(btn.themeMode)
                theme_panel:RefreshThemeControls()
                local pal = sfui.theme.GetPalette()
                sfui.common.print("theme mode set to '" .. btn.themeMode .. "' (active: " .. tostring(pal.name):lower() .. ").")
            end)
        end

        -- ─── Camelot Style Detail Checkboxes ──────────────────────────────────
        local brackets_cb = create_checkbox(theme_panel, "enable ornate corner brackets", function()
            if sfui.db and sfui.db.Get then
                local v = sfui.db.Get("theme", "cornerBrackets")
                if v ~= nil then return v ~= false end
            end
            if SfuiDB and SfuiDB.theme and SfuiDB.theme.cornerBrackets ~= nil then
                return SfuiDB.theme.cornerBrackets ~= false
            end
            return SfuiDB and SfuiDB.themeCornerBrackets ~= false
        end, function(checked)
            SfuiDB.themeCornerBrackets = checked
            SfuiDB.theme = SfuiDB.theme or {}
            SfuiDB.theme.cornerBrackets = checked
            if sfui.db and sfui.db.Set then
                sfui.db.Set("theme", "cornerBrackets", checked)
            end
            sfui.theme.ApplyCurrentTheme()
            theme_panel:RefreshThemeControls()
        end, "displays sculpted heavy bronze corner brackets clamped onto window frames in bronze mode.")
        brackets_cb:SetPoint("TOPLEFT", rowFirstBtn, "BOTTOMLEFT", 0, -18)

        local textured_bg_cb = create_checkbox(theme_panel, "use textured parchment & metal backgrounds", function()
            if sfui.db and sfui.db.Get then
                local v = sfui.db.Get("theme", "texturedBackdrop")
                if v ~= nil then return v ~= false end
            end
            if SfuiDB and SfuiDB.theme and SfuiDB.theme.texturedBackdrop ~= nil then
                return SfuiDB.theme.texturedBackdrop ~= false
            end
            return SfuiDB and SfuiDB.themeTexturedBackdrop ~= false
        end, function(checked)
            SfuiDB.themeTexturedBackdrop = checked
            SfuiDB.theme = SfuiDB.theme or {}
            SfuiDB.theme.texturedBackdrop = checked
            if sfui.db and sfui.db.Set then
                sfui.db.Set("theme", "texturedBackdrop", checked)
            end
            sfui.theme.ApplyCurrentTheme()
            theme_panel:RefreshThemeControls()
        end, "enables rich textured dark parchment and slate background art on windows instead of flat dark fills.")
        textured_bg_cb:SetPoint("TOPLEFT", brackets_cb, "BOTTOMLEFT", 0, -8)

        local flat_btn_cb = create_checkbox(theme_panel, "use flat button styling", function()
            return sfui.theme.IsFlatButtonActive()
        end, function(checked)
            sfui.theme.SetFlatButtons(checked)
            sfui.theme.ApplyCurrentTheme()
            theme_panel:RefreshThemeControls()
        end, "switches to minimalist flat dark slate buttons instead of the default auction house beveled buttons.")
        flat_btn_cb:SetPoint("TOPLEFT", textured_bg_cb, "BOTTOMLEFT", 0, -8)

        local square_bronze_cb = create_checkbox(theme_panel, "use bronze square minimap", function()
            if sfui.map and sfui.map.square and sfui.map.square.IsBronzeTheme then
                return sfui.map.square:IsBronzeTheme()
            end
            if sfui.db and sfui.db.Get then
                local v = sfui.db.Get("theme", "minimapArt")
                if v ~= nil then return v ~= false end
            end
            return SfuiDB and SfuiDB.minimap_square_bronze ~= false
        end, function(checked)
            SfuiDB._minimapSquareBronzeCustomized = true
            SfuiDB.minimap_square_bronze = checked
            SfuiDB.theme = SfuiDB.theme or {}
            SfuiDB.theme.minimapArt = checked
            if sfui.db and sfui.db.Set then
                sfui.db.Set("theme", "minimapArt", checked)
            end
            if sfui.map and sfui.map.square and sfui.map.square.SetBronzeTheme then
                sfui.map.square:SetBronzeTheme(checked)
            end
            theme_panel:RefreshThemeControls()
        end, "applies authentic heavy bronze borders and corner brackets to the square minimap.")
        square_bronze_cb:SetPoint("TOPLEFT", flat_btn_cb, "BOTTOMLEFT", 0, -8)

        -- ─── Old Gods Detail Checkboxes ───────────────────────────────────────
        local oldgod_bg_cb = create_checkbox(theme_panel, "use textured void nebula background", function()
            return sfui.theme.IsOldGodBackdropActive and sfui.theme.IsOldGodBackdropActive()
        end, function(checked)
            if sfui.theme.SetOldGodBackdrop then
                sfui.theme.SetOldGodBackdrop(checked)
            end
            sfui.theme.ApplyCurrentTheme()
            theme_panel:RefreshThemeControls()
        end, "opt in to the cosmic purple void nebula texture backdrop on windows (disabled by default for clean visibility).")
        oldgod_bg_cb:SetPoint("TOPLEFT", rowFirstBtn, "BOTTOMLEFT", 0, -18)

        -- ─── Fallen Sanctum Detail Checkboxes ─────────────────────────────────
        local fallensanctum_bg_cb = create_checkbox(theme_panel, "use textured crypt background", function()
            return sfui.theme.IsFallenSanctumBackdropActive and sfui.theme.IsFallenSanctumBackdropActive()
        end, function(checked)
            if sfui.theme.SetFallenSanctumBackdrop then
                sfui.theme.SetFallenSanctumBackdrop(checked)
            end
            sfui.theme.ApplyCurrentTheme()
            theme_panel:RefreshThemeControls()
        end, "opt in to the charred torghast crypt stone backdrop on windows (disabled by default for clean visibility).")
        fallensanctum_bg_cb:SetPoint("TOPLEFT", rowFirstBtn, "BOTTOMLEFT", 0, -18)

        -- ─── Maw Detail Checkboxes ────────────────────────────────────────────
        local maw_bg_cb = create_checkbox(theme_panel, "use textured soul-slate background", function()
            return sfui.theme.IsMawBackdropActive and sfui.theme.IsMawBackdropActive()
        end, function(checked)
            if sfui.theme.SetMawBackdrop then
                sfui.theme.SetMawBackdrop(checked)
            end
            sfui.theme.ApplyCurrentTheme()
            theme_panel:RefreshThemeControls()
        end, "opt in to the cold swirling soul-slate anima fog backdrop on windows (disabled by default for clean visibility).")
        maw_bg_cb:SetPoint("TOPLEFT", rowFirstBtn, "BOTTOMLEFT", 0, -18)

        -- ─── Necrolord Detail Checkboxes ──────────────────────────────────────
        local necrolord_bg_cb = create_checkbox(theme_panel, "use textured crypt moss background", function()
            return sfui.theme.IsNecrolordBackdropActive and sfui.theme.IsNecrolordBackdropActive()
        end, function(checked)
            if sfui.theme.SetNecrolordBackdrop then
                sfui.theme.SetNecrolordBackdrop(checked)
            end
            sfui.theme.ApplyCurrentTheme()
            theme_panel:RefreshThemeControls()
        end, "opt in to the deep crypt moss and bone texture backdrop on windows (disabled by default for clean visibility).")
        necrolord_bg_cb:SetPoint("TOPLEFT", rowFirstBtn, "BOTTOMLEFT", 0, -18)
        -- ─── Color Palette Swatches ───────────────────────────────────────────
        local palette_header = theme_panel:CreateFontString(nil, "OVERLAY", g.font)
        palette_header:SetPoint("TOPLEFT", square_bronze_cb, "BOTTOMLEFT", 0, -20)
        palette_header:SetTextColor(white[1], white[2], white[3])
        palette_header:SetText("accent & highlight colors")

        -- Accent Color
        local accent_label = theme_panel:CreateFontString(nil, "OVERLAY", g.font_small or "GameFontHighlightSmall")
        accent_label:SetPoint("TOPLEFT", palette_header, "BOTTOMLEFT", 0, -12)
        accent_label:SetTextColor(0.8, 0.8, 0.8, 1)
        accent_label:SetText("primary accent:")

        local accent_swatch = create_color_swatch(theme_panel, sfui.config.appearance.accentColor, function(r, g, b)
            local col = { r, g, b, 1 }
            sfui.config.appearance.accentColor = col
            SfuiDB.customAccentColor = col
            SfuiDB.theme = SfuiDB.theme or {}
            SfuiDB.theme.accentColor = col
            if sfui.db and sfui.db.Set then
                sfui.db.Set("theme", "accentColor", col)
            end
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
            local col = { r, g, b, 1 }
            sfui.config.appearance.highlightColor = col
            SfuiDB.customHighlightColor = col
            SfuiDB.theme = SfuiDB.theme or {}
            SfuiDB.theme.highlightColor = col
            if sfui.db and sfui.db.Set then
                sfui.db.Set("theme", "highlightColor", col)
            end
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
            if SfuiDB.theme then
                SfuiDB.theme.accentColor = nil
                SfuiDB.theme.highlightColor = nil
            end
            if sfui.db and sfui.db.Set then
                sfui.db.Set("theme", "accentColor", nil)
                sfui.db.Set("theme", "highlightColor", nil)
            end
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

        local sample_button = CreateFlatButton(preview_card, "sample button", 110, 22)
        sample_button:SetPoint("BOTTOMLEFT", preview_card, "BOTTOMLEFT", 16, 14)

        local sample_selected = CreateFlatButton(preview_card, "selected button", 110, 22)
        sample_selected:SetPoint("LEFT", sample_button, "RIGHT", 10, 0)
        sample_selected.isSelected = true

        function preview_card:Refresh()
            sfui.theme.ApplyWindowStyle(preview_card, { cornerBrackets = (SfuiDB.themeCornerBrackets ~= false) })
            sfui.theme.ApplyCloseButtonStyle(sample_close)
            sfui.theme.ApplyQuestHeaderStyle(sample_header)
            sfui.theme.ApplyButtonStyle(sample_button, false)
            sfui.theme.ApplyButtonStyle(sample_selected, false)
            if sfui.theme.SetButtonSelected then
                sfui.theme.SetButtonSelected(sample_selected, true)
            end

            local pal = sfui.theme.GetPalette()
            preview_title:SetTextColor(pal.headerColor[1], pal.headerColor[2], pal.headerColor[3])
            preview_title:SetText(tostring(pal.name or ""):lower() .. " preview window")

            local isC = sfui.theme.IsCamelotActive()
            local activeID = sfui.theme.GetActiveThemeID()
            if isC then
                preview_body:SetTextColor(pal.tabNormal[1], pal.tabNormal[2], pal.tabNormal[3])
                if sfui.theme.IsAuctionHouseButtonActive() then
                    preview_body:SetText("tactile cast-bronze window, ornate corner brackets, embossed banners, auction house beveled buttons with blue hover glow and gold selection, and red/gold close button.")
                else
                    preview_body:SetText("tactile cast-bronze window, ornate corner brackets, embossed banners, clean flat dark buttons, and red/gold close button.")
                end
            elseif activeID == "oldgod" then
                preview_body:SetTextColor(pal.tabNormal[1], pal.tabNormal[2], pal.tabNormal[3])
                preview_body:SetText("authentic chonky old gods theme: sculpted blackened void alloy, curling tentacles, glowing void eye crest, side tentacle pillars, and soft void amethyst.")
            elseif activeID == "fallensanctum" then
                preview_body:SetTextColor(pal.tabNormal[1], pal.tabNormal[2], pal.tabNormal[3])
                preview_body:SetText("bespoke torghast crypt stone: horned gargoyle skull crest, hanging soul chains, blood crimson crypt iron, and soul-fire teal accents.")
            elseif activeID == "maw" then
                preview_body:SetTextColor(pal.tabNormal[1], pal.tabNormal[2], pal.tabNormal[3])
                preview_body:SetText("authentic bespoke maw theme: sculpted saronite maw spikes, horned domination crown crest, frost-rimmed soul chains, icy soul-chill blue glow (#65e6f2), and dark soul-slate.")
            elseif activeID == "necrolord" then
                preview_body:SetTextColor(pal.tabNormal[1], pal.tabNormal[2], pal.tabNormal[3])
                preview_body:SetText("authentic bespoke necrolord theme: carved bone-plate chitin, horned beast skull crest, ribbed vertebrae spine columns, toxic necrotic slime green (#59d98c), and bone ivory headers.")
            else
                preview_body:SetTextColor(0.8, 0.8, 0.8, 1)
                local activeDef = sfui.theme.GetTheme(activeID)
                if activeDef and activeDef.window and activeDef.window.style == "nineslice" and activeDef.desc then
                    preview_body:SetText(activeDef.desc:lower())
                else
                    preview_body:SetText("clean, flat minimalist black border with electric cyan/purple accents and flat buttons.")
                end
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

            -- Dynamic theme-specific checkboxes
            local activeID = sfui.theme.GetActiveThemeID()
            local isOldGod = (activeID == "oldgod")
            local isFallenSanctum = (activeID == "fallensanctum")
            local isMaw = (activeID == "maw")
            local isNecrolord = (activeID == "necrolord")

            if isCamelotSupported and isCamelot then
                brackets_cb:Show()
                textured_bg_cb:Show()
                flat_btn_cb:Show()
                square_bronze_cb:Show()
                oldgod_bg_cb:Hide()
                fallensanctum_bg_cb:Hide()
                maw_bg_cb:Hide()
                necrolord_bg_cb:Hide()
                palette_header:ClearAllPoints()
                palette_header:SetPoint("TOPLEFT", square_bronze_cb, "BOTTOMLEFT", 0, -20)
            elseif isOldGod then
                brackets_cb:Hide()
                textured_bg_cb:Hide()
                flat_btn_cb:Hide()
                square_bronze_cb:Hide()
                oldgod_bg_cb:Show()
                fallensanctum_bg_cb:Hide()
                maw_bg_cb:Hide()
                necrolord_bg_cb:Hide()
                oldgod_bg_cb:ClearAllPoints()
                oldgod_bg_cb:SetPoint("TOPLEFT", rowFirstBtn, "BOTTOMLEFT", 0, -18)
                palette_header:ClearAllPoints()
                palette_header:SetPoint("TOPLEFT", oldgod_bg_cb, "BOTTOMLEFT", 0, -20)
            elseif isFallenSanctum then
                brackets_cb:Hide()
                textured_bg_cb:Hide()
                flat_btn_cb:Hide()
                square_bronze_cb:Hide()
                oldgod_bg_cb:Hide()
                fallensanctum_bg_cb:Show()
                maw_bg_cb:Hide()
                necrolord_bg_cb:Hide()
                fallensanctum_bg_cb:ClearAllPoints()
                fallensanctum_bg_cb:SetPoint("TOPLEFT", rowFirstBtn, "BOTTOMLEFT", 0, -18)
                palette_header:ClearAllPoints()
                palette_header:SetPoint("TOPLEFT", fallensanctum_bg_cb, "BOTTOMLEFT", 0, -20)
            elseif isMaw then
                brackets_cb:Hide()
                textured_bg_cb:Hide()
                flat_btn_cb:Hide()
                square_bronze_cb:Hide()
                oldgod_bg_cb:Hide()
                fallensanctum_bg_cb:Hide()
                maw_bg_cb:Show()
                necrolord_bg_cb:Hide()
                maw_bg_cb:ClearAllPoints()
                maw_bg_cb:SetPoint("TOPLEFT", rowFirstBtn, "BOTTOMLEFT", 0, -18)
                palette_header:ClearAllPoints()
                palette_header:SetPoint("TOPLEFT", maw_bg_cb, "BOTTOMLEFT", 0, -20)
            elseif isNecrolord then
                brackets_cb:Hide()
                textured_bg_cb:Hide()
                flat_btn_cb:Hide()
                square_bronze_cb:Hide()
                oldgod_bg_cb:Hide()
                fallensanctum_bg_cb:Hide()
                maw_bg_cb:Hide()
                necrolord_bg_cb:Show()
                necrolord_bg_cb:ClearAllPoints()
                necrolord_bg_cb:SetPoint("TOPLEFT", rowFirstBtn, "BOTTOMLEFT", 0, -18)
                palette_header:ClearAllPoints()
                palette_header:SetPoint("TOPLEFT", necrolord_bg_cb, "BOTTOMLEFT", 0, -20)
            else
                brackets_cb:Hide()
                textured_bg_cb:Hide()
                flat_btn_cb:Hide()
                square_bronze_cb:Hide()
                oldgod_bg_cb:Hide()
                fallensanctum_bg_cb:Hide()
                maw_bg_cb:Hide()
                necrolord_bg_cb:Hide()
                palette_header:ClearAllPoints()
                palette_header:SetPoint("TOPLEFT", rowFirstBtn, "BOTTOMLEFT", 0, -20)
            end

            if square_bronze_cb then
                local isBronze = sfui.map and sfui.map.square and sfui.map.square.IsBronzeTheme and sfui.map.square:IsBronzeTheme()
                square_bronze_cb:SetChecked(isBronze and true or false)
            end

            -- Update Dynamically Created Toggle Buttons
            local hexAccent = string.format("%02x%02x%02x",
                math.floor(pal.accentColor[1] * 255),
                math.floor(pal.accentColor[2] * 255),
                math.floor(pal.accentColor[3] * 255)
            )

            for _, btn in ipairs(toggleButtons) do
                local isSelected = (btn.themeMode == savedMode) or
                    ((btn.themeMode == "camelot" or btn.themeMode == "bronze") and (savedMode == "camelot" or savedMode == "bronze"))
                btn.isSelected = isSelected
                local fs = btn:GetFontString()

                if not sfui.theme.IsThemeAvailable(btn.themeMode) then
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
                        -- buttons are narrow: grey the label, explain in the tooltip
                        fs:SetText(btn.baseLabel)
                        local reason = (btn.themeMode == "camelot" or btn.themeMode == "bronze") and "only available on camelot / forever."
                            or "the art for this theme is not available on this client."
                        sfui.common.attach_tooltip(btn, btn.baseLabel, "|cffff5555" .. reason .. "|r")
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
                        elseif btn.themeMode == "oldgod" then
                            btn:SetBackdropColor(0.22, 0.12, 0.35, 0.98)
                            btn:SetBackdropBorderColor(pal.accentColor[1], pal.accentColor[2], pal.accentColor[3], 1)
                        elseif btn.themeMode == "fallensanctum" then
                            btn:SetBackdropColor(0.24, 0.08, 0.10, 0.98)
                            btn:SetBackdropBorderColor(pal.accentColor[1], pal.accentColor[2], pal.accentColor[3], 1)
                        elseif btn.themeMode == "maw" then
                            btn:SetBackdropColor(0.08, 0.14, 0.18, 0.98)
                            btn:SetBackdropBorderColor(pal.accentColor[1], pal.accentColor[2], pal.accentColor[3], 1)
                        elseif btn.themeMode == "necrolord" then
                            btn:SetBackdropColor(0.06, 0.14, 0.08, 0.98)
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
                        elseif btn.themeMode == "oldgod" then
                            btn:SetBackdropColor(0.08, 0.05, 0.12, 0.90)
                            btn:SetBackdropBorderColor(0.28, 0.18, 0.38, 0.85)
                        else
                            btn:SetBackdropColor(0.04, 0.04, 0.04, 0.90)
                            btn:SetBackdropBorderColor(0.16, 0.16, 0.16, 1)
                        end
                    end
                    if fs then
                        fs:SetText(btn.baseLabel)
                        if btn.themeMode == "oldgod" then
                            fs:SetTextColor(0.68, 0.58, 0.80, 1)
                        else
                            fs:SetTextColor(0.60, 0.60, 0.60, 1)
                        end
                    end
                end
            end

            -- Update Swatches
            local curAccent = (SfuiDB and (SfuiDB.customAccentColor or (SfuiDB.theme and SfuiDB.theme.accentColor))) or pal.accentColor
            local curHl = (SfuiDB and (SfuiDB.customHighlightColor or (SfuiDB.theme and SfuiDB.theme.highlightColor))) or pal.highlightColor
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
