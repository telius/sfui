local addonName, addon = ...
sfui.trackedoptions = {}

local frame
local scrollFrame
local scrollChild
local content -- The list of tracked bars
local UpdateCooldownsList
local issecretvalue = sfui.common.issecretvalue
-- Forward declaration
local CreateFlatButton = sfui.common.create_flat_button
local g = sfui.config
local c = g.options_panel

local function select_tab(frame, id)
    if not frame.tabs then return end
    for i, tab in ipairs(frame.tabs) do
        local btn = tab.button
        if i == id then
            tab.panel:Show()
            btn.text:SetTextColor(g.colors.cyan[1], g.colors.cyan[2], g.colors.cyan[3])
        else
            tab.panel:Hide()
            btn.text:SetTextColor(g.colors.purple[1], g.colors.purple[2], g.colors.purple[3])
        end
    end
    frame.selectedTabId = id
    SfuiDB.lastSelectedTabId = id -- Persist tab selection

    if id == 2 or id == 3 then
        sfui.trackedoptions.UpdateEditor()
    end

    -- Refresh icons to apply visibility override
    if sfui.trackedicons and sfui.trackedicons.Update then
        sfui.trackedicons.Update()
    end
end

local function CreateNavButton(parent, name, id)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(60, 22)
    local t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("CENTER")
    t:SetText(name)
    b.text = t

    b:SetScript("OnClick", function() select_tab(parent, id) end)
    b:SetScript("OnEnter", function()
        t:SetTextColor(1, 1, 1)
    end)
    b:SetScript("OnLeave", function()
        if parent.selectedTabId == id then
            t:SetTextColor(g.colors.cyan[1], g.colors.cyan[2], g.colors.cyan[3])
        else
            t:SetTextColor(g.colors.purple[1], g.colors.purple[2], g.colors.purple[3])
        end
    end)
    return b
end

local function CreateNumericEditBox(parent, w, h, callback)
    local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    eb:SetSize(w, h)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetAutoFocus(false)
    eb:SetJustifyH("CENTER")
    eb:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    eb:SetBackdropColor(0.2, 0.2, 0.2, 1)
    eb:SetBackdropBorderColor(0, 0, 0, 1)
    eb:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if callback then callback(val) end
        self:ClearFocus()
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return eb
end

local function CreateCooldownsFrame()
    if frame then return end

    local create_slider_input = sfui.common.create_slider_input

    frame = CreateFrame("Frame", "SfuiCooldownsViewer", UIParent, "BackdropTemplate")
    local winCfg = sfui.config.trackedOptionsWindow or { width = 1100, height = 650 }
    frame:SetSize(winCfg.width, winCfg.height)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    frame:SetBackdrop({ bgFile = g.textures.white, tile = true, tileSize = 32 })
    frame:SetBackdropColor(c.backdrop_color.r, c.backdrop_color.g, c.backdrop_color.b, c.backdrop_color.a)

    -- Close (X)
    local close_button = CreateFlatButton(frame, "X", 24, 24)
    close_button:SetPoint("TOPRIGHT", -5, -5)
    close_button:SetScript("OnClick", function() frame:Hide() end)

    frame:SetScript("OnHide", function()
        if sfui.trackedicons and sfui.trackedicons.Update then
            sfui.trackedicons.Update()
        end
    end)



    -- Options (Left)
    local optionsBtn = CreateFlatButton(frame, "options", 80, 22)
    optionsBtn:SetPoint("TOPLEFT", 10, -5)
    optionsBtn:SetScript("OnClick", function()
        if sfui.toggle_options_panel then
            sfui.toggle_options_panel()

            -- Cycle breaker: Ensure 'frame' (Tracking Manager) is not dependent on options frame
            local left = frame:GetLeft()
            local top = frame:GetTop()
            if left and top then
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            end

            -- Attach options frame to the LEFT of this tracking manager frame
            if sfui_options_frame and sfui_options_frame:IsShown() then
                sfui_options_frame:ClearAllPoints()
                sfui_options_frame:SetPoint("TOPRIGHT", frame, "TOPLEFT", -5, 0)
            end
        end
    end)

    -- CooldownViewer (Header)
    local blizBtn = CreateFlatButton(frame, "cooldownviewer", 100, 22)
    blizBtn:SetPoint("LEFT", optionsBtn, "RIGHT", 5, 0)
    blizBtn:SetScript("OnClick", function()
        if CooldownViewerSettings then
            if CooldownViewerSettings:IsShown() then CooldownViewerSettings:Hide() else CooldownViewerSettings:Show() end
        end
    end)

    -- Tabs Container (Header)
    frame.tabs = {}

    -- Tab 1: Global Settings
    local globalBtn = CreateNavButton(frame, "global", 1)
    globalBtn:SetPoint("LEFT", blizBtn, "RIGHT", 5, 0)

    -- Tab 2: Bars
    local barsBtn = CreateNavButton(frame, "bars", 2)
    barsBtn:SetPoint("LEFT", globalBtn, "RIGHT", 5, 0)

    -- Tab 3: Icons
    local iconsBtn = CreateNavButton(frame, "icons", 3)
    iconsBtn:SetPoint("LEFT", barsBtn, "RIGHT", 5, 0)

    sfui.trackedoptions.selectedPanelIndex = 1

    -- ═══════════════════════════════════════
    -- Tab 1: Global Settings Panel
    -- ═══════════════════════════════════════
    local globalPanel = CreateFrame("Frame", nil, frame)
    globalPanel:SetPoint("TOPLEFT", 10, -35)
    globalPanel:SetPoint("BOTTOMRIGHT", -10, 10)
    globalPanel:Hide()

    local globScroll = CreateFrame("ScrollFrame", nil, globalPanel, "UIPanelScrollFrameTemplate")
    globScroll:SetPoint("TOPLEFT", 0, 0)
    globScroll:SetPoint("BOTTOMRIGHT", -25, 0)
    local globContent = CreateFrame("Frame", nil, globScroll)
    globContent:SetSize(800, 600)
    globScroll:SetScrollChild(globContent)

    -- Initialize global settings if not present
    SfuiDB.iconGlobalSettings = SfuiDB.iconGlobalSettings or {}
    local globalCfg = SfuiDB.iconGlobalSettings

    -- Two-column layout
    local leftCol = 10   -- Left column X position
    local rightCol = 390 -- Right column X position
    local gy = -10       -- Y position tracker
    local colWidth = 350 -- Column width

    local function AddGlobalHeader(text, xPos)
        local h = globContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        h:SetPoint("TOPLEFT", xPos, gy)
        h:SetText(text)
        h:SetTextColor(g.colors.cyan[1], g.colors.cyan[2], g.colors.cyan[3])
        return h
    end

    -- ===== LEFT COLUMN: GLOW SETTINGS =====
    AddGlobalHeader("ready glow settings", leftCol)
    gy = gy - 25

    -- Glow Preview Icon (create early so UpdateGlowPreview can reference it)
    local previewIcon = CreateFrame("Button", "SfuiGlowPreviewIcon", globContent)
    previewIcon:SetSize(64, 64)
    previewIcon:SetPoint("TOPLEFT", leftCol, gy)

    local previewTex = previewIcon:CreateTexture(nil, "ARTWORK")
    previewTex:SetAllPoints()
    previewTex:SetTexture(136145) -- Death Coil icon
    previewIcon.texture = previewTex

    -- Preview label
    local previewLabel = globContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    previewLabel:SetPoint("LEFT", previewIcon, "RIGHT", 10, 0)
    previewLabel:SetText("preview →")

    gy = gy - 80

    -- Update function for preview glow (defined early so callbacks can use it)
    local function UpdateGlowPreview()
        if not sfui.glows then return end

        -- Stop existing glow
        sfui.glows.stop_glow(previewIcon)

        -- Start new glow if enabled
        if globalCfg.readyGlow then
            local glowColor = globalCfg.glowColor or g.icon_panel_global_defaults.glowColor
            local useSpecColor = (globalCfg.useSpecColor ~= nil) and globalCfg.useSpecColor or
                g.icon_panel_global_defaults.useSpecColor

            if useSpecColor then
                local specIndex = GetSpecialization()
                if specIndex and specIndex > 0 then
                    local specID = GetSpecializationInfo(specIndex)
                    if specID and sfui.config.spec_colors and sfui.config.spec_colors[specID] then
                        glowColor = sfui.config.spec_colors[specID]
                    end
                end
            end

            local glowCfg = {
                glowType = globalCfg.glowType or g.icon_panel_global_defaults.glowType,
                glowColor = glowColor,
                glowScale = globalCfg.glowScale or g.icon_panel_global_defaults.glowScale,
                glowIntensity = globalCfg.glowIntensity or g.icon_panel_global_defaults.glowIntensity,
                glowSpeed = globalCfg.glowSpeed or g.icon_panel_global_defaults.glowSpeed,
                glowLines = globalCfg.glowLines or g.icon_panel_global_defaults.glowLines,
                glowThickness = globalCfg.glowThickness or g.icon_panel_global_defaults.glowThickness,
                glowParticles = globalCfg.glowParticles or g.icon_panel_global_defaults.glowParticles
            }
            sfui.glows.start_glow(previewIcon, glowCfg)
        end
    end

    local glowChk = sfui.common.create_checkbox(globContent, "enable ready glow", nil, function(val)
        globalCfg.readyGlow = val
        UpdateGlowPreview()
        if sfui.trackedicons and sfui.trackedicons.ForceRefreshGlows then sfui.trackedicons.ForceRefreshGlows() end
        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
    end)
    glowChk:SetPoint("TOPLEFT", leftCol, gy)
    glowChk:SetChecked(globalCfg.readyGlow ~= nil and globalCfg.readyGlow or g.icon_panel_global_defaults.readyGlow)
    gy = gy - 30

    -- Initial preview
    UpdateGlowPreview()
    gy = gy - 10

    -- Glow Type Dropdown
    local glowTypeLabel = globContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    glowTypeLabel:SetPoint("TOPLEFT", leftCol, gy)
    glowTypeLabel:SetText("glow type")
    gy = gy - 20

    local glowTypeDrop = CreateFrame("Frame", "SfuiGlobalGlowTypeDropdown", globContent, "UIDropDownMenuTemplate")
    glowTypeDrop:SetPoint("TOPLEFT", leftCol - 10, gy)
    UIDropDownMenu_SetWidth(glowTypeDrop, 150)
    UIDropDownMenu_SetText(glowTypeDrop, globalCfg.glowType or g.icon_panel_global_defaults.glowType)
    UIDropDownMenu_Initialize(glowTypeDrop, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, type in ipairs({ "pixel", "autocast", "proc", "button" }) do
            info.text = type
            info.func = function()
                globalCfg.glowType = type
                UIDropDownMenu_SetText(glowTypeDrop, type)
                UpdateGlowPreview()
                if sfui.trackedicons and sfui.trackedicons.ForceRefreshGlows then sfui.trackedicons.ForceRefreshGlows() end
                if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    gy = gy - 40

    -- Glow Color Picker
    local glowColorLabel = globContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    glowColorLabel:SetPoint("TOPLEFT", leftCol, gy)
    glowColorLabel:SetText("glow color")

    local glowSwatch = sfui.common.create_color_swatch(globContent,
        globalCfg.glowColor or g.icon_panel_global_defaults.glowColor,
        function(r, gb, b)
            globalCfg.glowColor = { r = r, g = gb, b = b }
            UpdateGlowPreview()
            if sfui.trackedicons and sfui.trackedicons.ForceRefreshGlows then sfui.trackedicons.ForceRefreshGlows() end
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end)
    glowSwatch:SetPoint("LEFT", glowColorLabel, "RIGHT", 10, 0)

    local specColorChk = sfui.common.create_checkbox(globContent, "use spec color", nil, function(val)
        globalCfg.useSpecColor = val
        UpdateGlowPreview()
        if sfui.trackedicons and sfui.trackedicons.ForceRefreshGlows then sfui.trackedicons.ForceRefreshGlows() end
        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
    end)
    specColorChk:SetPoint("LEFT", glowSwatch, "RIGHT", 20, 0)
    gy = gy - 35

    -- Glow Sliders (2 per row)
    local halfW = 165
    local glowScale = sfui.common.create_slider_input(globContent, "scale:",
        function() return SfuiDB.iconGlobalSettings.glowScale or 1.0 end,
        0.5, 2.0, 0.1, function(val)
            globalCfg.glowScale = val
            UpdateGlowPreview()
            if sfui.trackedicons and sfui.trackedicons.ForceRefreshGlows then sfui.trackedicons.ForceRefreshGlows() end
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end, halfW)
    glowScale:SetPoint("TOPLEFT", leftCol, gy)

    local glowIntensity = sfui.common.create_slider_input(globContent, "intensity:",
        function() return SfuiDB.iconGlobalSettings.glowIntensity or 1.0 end,
        0.1, 2.0, 0.1, function(val)
            globalCfg.glowIntensity = val
            UpdateGlowPreview()
            if sfui.trackedicons and sfui.trackedicons.ForceRefreshGlows then sfui.trackedicons.ForceRefreshGlows() end
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end, halfW)
    glowIntensity:SetPoint("TOPLEFT", leftCol + halfW + 10, gy)
    gy = gy - 40

    local glowSpeed = sfui.common.create_slider_input(globContent, "speed:",
        function() return SfuiDB.iconGlobalSettings.glowSpeed or 1.0 end,
        0.05, 1.0, 0.05, function(val)
            globalCfg.glowSpeed = val
            UpdateGlowPreview()
            if sfui.trackedicons and sfui.trackedicons.ForceRefreshGlows then sfui.trackedicons.ForceRefreshGlows() end
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end, halfW)
    glowSpeed:SetPoint("TOPLEFT", leftCol, gy)

    local glowLines = sfui.common.create_slider_input(globContent, "lines:",
        function() return SfuiDB.iconGlobalSettings.glowLines or 4 end,
        4, 16, 1, function(val)
            globalCfg.glowLines = val
            UpdateGlowPreview()
            if sfui.trackedicons and sfui.trackedicons.ForceRefreshGlows then sfui.trackedicons.ForceRefreshGlows() end
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end, halfW)
    glowLines:SetPoint("TOPLEFT", leftCol + halfW + 10, gy)
    gy = gy - 40

    local glowThickness = sfui.common.create_slider_input(globContent, "thickness:",
        function() return SfuiDB.iconGlobalSettings.glowThickness or 1 end,
        1, 4, 0.5, function(val)
            globalCfg.glowThickness = val
            UpdateGlowPreview()
            if sfui.trackedicons and sfui.trackedicons.ForceRefreshGlows then sfui.trackedicons.ForceRefreshGlows() end
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end, halfW)
    glowThickness:SetPoint("TOPLEFT", leftCol, gy)

    local glowParticles = sfui.common.create_slider_input(globContent, "particles:",
        function() return SfuiDB.iconGlobalSettings.glowParticles or 4 end,
        2, 8, 1, function(val)
            globalCfg.glowParticles = val
            UpdateGlowPreview()
            if sfui.trackedicons and sfui.trackedicons.ForceRefreshGlows then sfui.trackedicons.ForceRefreshGlows() end
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end, halfW)
    glowParticles:SetPoint("TOPLEFT", leftCol + halfW + 10, gy)

    -- Reset Y for right column
    local rightY = -10

    -- ===== RIGHT COLUMN: VISIBILITY SETTINGS =====
    local function UpdateIconVisibility(key, val)
        SfuiDB.iconGlobalSettings = SfuiDB.iconGlobalSettings or {}
        SfuiDB.iconGlobalSettings[key] = val
        -- Force update icons
        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
    end

    local chk_icon_ooc = sfui.common.create_checkbox(globContent, "hide icons out of combat", nil,
        function(val) UpdateIconVisibility("hideOOC", val) end)
    chk_icon_ooc:SetPoint("TOPLEFT", rightCol, rightY)
    chk_icon_ooc:SetChecked(globalCfg.hideOOC or false)
    rightY = rightY - 30

    local chk_icon_dragon = sfui.common.create_checkbox(globContent, "hide icons dragonriding", nil,
        function(val) UpdateIconVisibility("hideDragonriding", val) end)
    chk_icon_dragon:SetPoint("TOPLEFT", rightCol, rightY)
    chk_icon_dragon:SetChecked(globalCfg.hideDragonriding or false)
    rightY = rightY - 30

    -- ===== COOLDOWN TEXT & VISUALS =====
    local desatChk = sfui.common.create_checkbox(globContent, "desaturate on cooldown", nil, function(val)
        globalCfg.cooldownDesat = val
        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
    end)
    desatChk:SetPoint("TOPLEFT", rightCol, rightY)
    desatChk:SetChecked(globalCfg.cooldownDesat ~= nil and globalCfg.cooldownDesat or
        g.icon_panel_global_defaults.cooldownDesat)
    rightY = rightY - 30

    local textChk = sfui.common.create_checkbox(globContent, "show countdown text", nil, function(val)
        globalCfg.textEnabled = val
        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
    end)
    textChk:SetPoint("TOPLEFT", rightCol, rightY)
    textChk:SetChecked(globalCfg.textEnabled ~= nil and globalCfg.textEnabled or g.icon_panel_global_defaults
        .textEnabled)
    rightY = rightY - 30

    local resourceChk = sfui.common.create_checkbox(globContent, "enable resource check", nil, function(val)
        globalCfg.useResourceCheck = val
        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
    end)
    resourceChk:SetPoint("TOPLEFT", rightCol, rightY)
    resourceChk:SetChecked(globalCfg.useResourceCheck ~= nil and globalCfg.useResourceCheck or
        g.icon_panel_global_defaults.useResourceCheck)
    rightY = rightY - 30

    local textColorLabel = globContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    textColorLabel:SetPoint("TOPLEFT", rightCol, rightY)
    textColorLabel:SetText("text color")

    local textSwatch = sfui.common.create_color_swatch(globContent,
        globalCfg.textColor or g.icon_panel_global_defaults.textColor,
        function(r, gb, b)
            globalCfg.textColor = { r = r, g = gb, b = b }
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end)
    textSwatch:SetPoint("LEFT", textColorLabel, "RIGHT", 10, 0)
    rightY = rightY - 35

    local alphaSlider = sfui.common.create_slider_input(globContent, "alpha on cooldown:",
        function() return SfuiDB.iconGlobalSettings.alphaOnCooldown or 1.0 end,
        0.1, 1.0, 0.1, function(val)
            globalCfg.alphaOnCooldown = val
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end, colWidth)
    alphaSlider:SetPoint("TOPLEFT", rightCol, rightY)
    rightY = rightY - 40

    globContent:SetHeight(400)


    -- Function to update all UI controls from current globalCfg
    local function UpdateGlobalControls()
        -- Glow settings
        if glowChk and glowChk.SetChecked then
            glowChk:SetChecked(globalCfg.readyGlow)
        end

        if SfuiGlobalGlowTypeDropdown then
            UIDropDownMenu_SetText(SfuiGlobalGlowTypeDropdown, globalCfg.glowType or "pixel")
        end

        if specColorChk and specColorChk.SetChecked then
            specColorChk:SetChecked(globalCfg.useSpecColor ~= nil and globalCfg.useSpecColor or
                g.icon_panel_global_defaults.useSpecColor)
        end

        -- Sliders
        if glowScale and glowScale.SetSliderValue then glowScale:SetSliderValue(globalCfg.glowScale or 1.0) end
        if glowIntensity and glowIntensity.SetSliderValue then
            glowIntensity:SetSliderValue(globalCfg.glowIntensity or
                1.0)
        end
        if glowSpeed and glowSpeed.SetSliderValue then glowSpeed:SetSliderValue(globalCfg.glowSpeed or 1.0) end
        if glowLines and glowLines.SetSliderValue then glowLines:SetSliderValue(globalCfg.glowLines or 4) end
        if glowThickness and glowThickness.SetSliderValue then glowThickness:SetSliderValue(globalCfg.glowThickness or 1) end
        if glowParticles and glowParticles.SetSliderValue then glowParticles:SetSliderValue(globalCfg.glowParticles or 4) end

        -- Vis settings (Icons)
        if chk_icon_ooc and chk_icon_ooc.SetChecked then chk_icon_ooc:SetChecked(globalCfg.hideOOC) end
        if chk_icon_dragon and chk_icon_dragon.SetChecked then chk_icon_dragon:SetChecked(globalCfg.hideDragonriding) end

        -- Text/Visual settings
        if desatChk and desatChk.SetChecked then desatChk:SetChecked(globalCfg.cooldownDesat) end
        if textChk and textChk.SetChecked then textChk:SetChecked(globalCfg.textEnabled) end
        if resourceChk and resourceChk.SetChecked then resourceChk:SetChecked(globalCfg.useResourceCheck) end

        -- Refresh preview
        UpdateGlowPreview()

        -- Update Alpha Slider
        UpdateGlowPreview()

        -- Update Alpha Slider
        if alphaSlider and alphaSlider.SetSliderValue then
            alphaSlider:SetSliderValue(globalCfg.alphaOnCooldown or 1.0)
        end
    end

    -- Update controls when panel is shown (fixes reset bug)
    globalPanel:SetScript("OnShow", UpdateGlobalControls)


    -- ═══════════════════════════════════════
    -- Tab 2: Bars Panel
    -- ═══════════════════════════════════════
    local barsPanel = CreateFrame("Frame", nil, frame)
    barsPanel:SetPoint("TOPLEFT", 10, -50)
    barsPanel:SetPoint("BOTTOMRIGHT", -10, 10)
    barsPanel:Hide()

    local barsScroll = CreateFrame("ScrollFrame", "SfuiTrackingBarsScroll", barsPanel, "UIPanelScrollFrameTemplate")
    barsScroll:SetPoint("TOPLEFT", 0, 0)
    barsScroll:SetPoint("BOTTOMRIGHT", -25, 0)
    local barsContent = CreateFrame("Frame", nil, barsScroll)
    barsContent:SetSize(800, 1000)
    barsScroll:SetScrollChild(barsContent)

    table.insert(frame.tabs, { button = globalBtn, panel = globalPanel, scrollChild = globContent })
    table.insert(frame.tabs, { button = barsBtn, panel = barsPanel, scrollChild = barsContent })

    local iconsPanel = CreateFrame("Frame", "SfuiIconsTab", frame)
    iconsPanel:SetPoint("TOPLEFT", 10, -50)
    iconsPanel:SetPoint("BOTTOMRIGHT", -10, 10)
    iconsPanel:Hide()

    table.insert(frame.tabs, { button = iconsBtn, panel = iconsPanel })

    -- Global Header within Bars Tab
    local global_header = barsContent:CreateFontString(nil, "OVERLAY", g.font)
    global_header:SetPoint("TOPLEFT", 10, -10)
    global_header:SetTextColor(1, 1, 1)
    global_header:SetText("visibility and positioning")

    -- Global Visibility Settings (Bars Only)
    local function UpdateBarsVisibility(key, val)
        SfuiDB = SfuiDB or {}
        SfuiDB[key] = val
        -- REMOVED: BuffBarCooldownViewer interaction to prevent taint/blocked actions in combat/M+
        if sfui.trackedbars and sfui.trackedbars.UpdateVisibility then sfui.trackedbars.UpdateVisibility() end
    end

    local chk_ooc = sfui.common.create_checkbox(barsContent, "hide bar out of combat", nil,
        function(val) UpdateBarsVisibility("hideOOC", val) end)
    chk_ooc:SetPoint("TOPLEFT", global_header, "BOTTOMLEFT", 0, -10)
    chk_ooc:SetChecked(SfuiDB and SfuiDB.hideOOC or false)

    local chk_inactive = sfui.common.create_checkbox(barsContent, "hide when inactive", nil,
        function(val) UpdateBarsVisibility("hideInactive", val) end)
    chk_inactive:SetPoint("TOPLEFT", chk_ooc, "BOTTOMLEFT", 0, -5)
    chk_inactive:SetChecked(SfuiDB and SfuiDB.hideInactive or false)

    local chk_dragon = sfui.common.create_checkbox(barsContent, "hide while dragonriding", nil,
        function(val) UpdateBarsVisibility("hideDragonriding", val) end)
    chk_dragon:SetPoint("TOPLEFT", chk_inactive, "BOTTOMLEFT", 0, -5)
    chk_dragon:SetChecked(SfuiDB and SfuiDB.hideDragonriding or false)


    -- Positioning Sliders (stay on top line, anchored to first checkbox)
    local sliderX = sfui.common.create_slider_input(barsContent, "posX:", "trackedBarsX", -1000, 1000, 1, function(val)
        if sfui.trackedbars and sfui.trackedbars.UpdatePosition then sfui.trackedbars.UpdatePosition() end
    end)
    sliderX:SetPoint("LEFT", chk_ooc, "RIGHT", 180, 0)

    local sliderY = sfui.common.create_slider_input(barsContent, "posY:", "trackedBarsY", -1000, 1000, 1, function(val)
        if sfui.trackedbars and sfui.trackedbars.UpdatePosition then sfui.trackedbars.UpdatePosition() end
    end)
    sliderY:SetPoint("LEFT", sliderX, "RIGHT", 10, 0)

    local colHeader = CreateFrame("Frame", nil, barsContent)
    colHeader:SetSize(800, 25)
    colHeader:SetPoint("TOPLEFT", chk_inactive, "BOTTOMLEFT", 0, -25)

    local tableHeader = colHeader:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    tableHeader:SetPoint("TOPLEFT", 0, 0)
    tableHeader:SetTextColor(0.8, 0.8, 0.8)
    tableHeader:SetText("tracked bars")

    local function CreateHeader(point, text, subText)
        local h = colHeader:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", point, 0)
        h:SetTextColor(0.7, 0.7, 0.7)
        h:SetText(text)
        if subText then
            local s = colHeader:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            s:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -2)
            s:SetTextColor(0.5, 0.5, 0.5)
            s:SetText(subText)
            sfui.common.style_text(s, nil, 9, nil)
        end
        return h
    end

    -- Align headers starting after "tracked bars" title
    CreateHeader(320, "attach", "to hp")
    CreateHeader(400, "mode", "stack bar")
    CreateHeader(480, "max", "stacks")
    CreateHeader(560, "text", "show stacks")
    CreateHeader(640, "text", "show title")
    CreateHeader(720, "color")

    content = CreateFrame("Frame", "SfuiTrackedBarsContent", barsContent)
    content:SetSize(800, 210)
    content:SetPoint("TOPLEFT", colHeader, "BOTTOMLEFT", 0, 0)

    -- === ICON EDITOR SECTION ===
    -- LEFT: Panel List
    local leftPanel = CreateFrame("Frame", nil, iconsPanel, "BackdropTemplate")
    leftPanel:SetPoint("TOPLEFT", 0, 0)
    leftPanel:SetPoint("BOTTOMLEFT", 0, 0)
    leftPanel:SetWidth(120) -- Reduced from 150
    leftPanel:SetBackdrop({ bgFile = g.textures.white })
    leftPanel:SetBackdropColor(0.05, 0.05, 0.05, 0.9)

    local lpScroll = CreateFrame("ScrollFrame", nil, leftPanel, "UIPanelScrollFrameTemplate")
    lpScroll:SetPoint("TOPLEFT", 5, -5)
    lpScroll:SetPoint("BOTTOMRIGHT", -25, 45)
    local lpContent = CreateFrame("Frame", nil, lpScroll)
    lpContent:SetSize(1, 1)
    lpScroll:SetScrollChild(lpContent)
    sfui.trackedoptions.lpContent = lpContent

    local addBtn = CreateFlatButton(leftPanel, "+ add", 85, 22)
    addBtn:SetPoint("BOTTOMLEFT", 5, 5)
    addBtn:SetScript("OnClick", function()
        local panels = sfui.common.get_cooldown_panels()
        table.insert(panels, {
            name = "Panel " .. (#panels + 1),
            enabled = true,
            entries = {},
            size = 50,
            spacing = 2,
            x = 0,
            y = 250,
            columns = 10,
            textEnabled = true,
            textColor = { r = 1, g = 1, b = 1 }
        })
        sfui.common.set_cooldown_panels(panels)
        sfui.trackedoptions.UpdateEditor()
        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
    end)

    local resetGlobalBtn = CreateFlatButton(globContent, "reset defaults", 100, 22)
    resetGlobalBtn:SetScript("OnClick", function()
        globalCfg.readyGlow = true
        globalCfg.useSpecColor = true
        globalCfg.glowType = "autocast"
        globalCfg.glowColor = { r = 1, g = 1, b = 0 }
        globalCfg.glowScale = 2.0
        globalCfg.glowIntensity = 1.0
        globalCfg.glowSpeed = 0.5
        globalCfg.glowLines = 4
        globalCfg.glowThickness = 1
        globalCfg.glowParticles = 4
        globalCfg.hideOOC = true
        globalCfg.hideDragonriding = true
        globalCfg.cooldownDesat = true
        globalCfg.textEnabled = true
        globalCfg.useResourceCheck = true
        globalCfg.alphaOnCooldown = 1.0

        UpdateGlobalControls()
        if sfui.trackedicons and sfui.trackedicons.ForceRefreshGlows then sfui.trackedicons.ForceRefreshGlows() end
        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
    end)
    resetGlobalBtn:SetPoint("TOPRIGHT", globContent, "TOPRIGHT", -10, -10)

    local delBtn = CreateFlatButton(leftPanel, "- del", 80, 22)
    delBtn:SetPoint("BOTTOMRIGHT", -5, 5)
    delBtn:SetScript("OnClick", function()
        local idx = sfui.trackedoptions.selectedPanelIndex
        local panels = sfui.common.get_cooldown_panels()
        if idx and panels[idx] then
            table.remove(panels, idx)
            sfui.common.set_cooldown_panels(panels)
            sfui.trackedoptions.selectedPanelIndex = 1
            sfui.trackedoptions.UpdateEditor()
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end
    end)

    -- MIDDLE: Preview / Drop area
    local midPanel = CreateFrame("Frame", nil, iconsPanel, "BackdropTemplate")
    midPanel:SetBackdrop({ bgFile = g.textures.white })
    midPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.6)
    midPanel:EnableMouse(true)

    local midHeader = midPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    midHeader:SetPoint("TOPLEFT", 5, -5)
    midHeader:SetText("icon preview / drop area")

    local previewChild = CreateFrame("Frame", nil, midPanel, "BackdropTemplate")
    previewChild:SetPoint("CENTER", midPanel, "CENTER", 0, 0)
    previewChild:SetSize(1, 1)
    previewChild:SetBackdrop({ bgFile = g.textures.white, edgeFile = g.textures.white, edgeSize = 1 })
    previewChild:SetBackdropColor(1, 1, 1, 0.05)
    previewChild:SetBackdropBorderColor(1, 1, 1, 0.05)
    sfui.trackedoptions.previewChild = previewChild

    -- Drop Logic
    local function OnReceiveDrag()
        -- NEW: Check if dragging from Cooldown Viewer
        local cooldownID
        if CooldownViewerSettings and CooldownViewerSettings.GetReorderSourceItem then
            local sourceItem = CooldownViewerSettings:GetReorderSourceItem()
            if sourceItem and sourceItem.GetCooldownID then
                cooldownID = sourceItem:GetCooldownID()
            end
        end

        if cooldownID and C_CooldownViewer then
            local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
            if info and info.isKnown then
                local idx = sfui.trackedoptions.selectedPanelIndex or 1
                local panels = sfui.common.get_cooldown_panels()
                local panel = panels and panels[idx]
                if panel then
                    panel.entries = panel.entries or {}
                    table.insert(panel.entries, {
                        type = "cooldown",
                        cooldownID = cooldownID,
                        spellID = info.spellID,
                        id = info.spellID, -- For compatibility
                        settings = { showText = true }
                    })
                    ClearCursor()
                    sfui.trackedoptions.UpdateEditor()
                    if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
                    return
                end
            end
        end

        -- Existing spell/item/macro handling
        local infoType, id, _, spellID = GetCursorInfo()
        if not infoType then return end

        local dragId, dragType = id, infoType
        if infoType == "spell" then
            dragId = spellID
        elseif infoType == "macro" then
            local sId = GetMacroSpell(id)
            if sId then
                dragId = sId; dragType = "spell"
            else
                local _, link = GetMacroItem(id)
                if link then
                    dragId = tonumber(link:match("item:(%d+)")); dragType = "item"
                end
            end
        end

        if dragId and (dragType == "spell" or dragType == "item") then
            local idx = sfui.trackedoptions.selectedPanelIndex or 1
            local panels = sfui.common.get_cooldown_panels()
            local panel = panels and panels[idx]
            if panel then
                panel.entries = panel.entries or {}
                table.insert(panel.entries, { type = dragType, id = dragId, settings = { showText = true } })
                ClearCursor()
                sfui.trackedoptions.UpdateEditor()
                if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
            end
        end
    end
    midPanel:SetScript("OnMouseUp", OnReceiveDrag)
    midPanel:SetScript("OnReceiveDrag", OnReceiveDrag)

    -- RIGHT 1: General Options Panel
    local genPanel = CreateFrame("Frame", nil, iconsPanel, "BackdropTemplate")
    genPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 5, 0)
    genPanel:SetPoint("BOTTOMLEFT", leftPanel, "BOTTOMRIGHT", 5, 0)
    genPanel:SetWidth(300)
    genPanel:SetBackdrop({ bgFile = g.textures.white })
    genPanel:SetBackdropColor(0.05, 0.05, 0.05, 0.9)

    local gpScroll = CreateFrame("ScrollFrame", nil, genPanel, "UIPanelScrollFrameTemplate")
    gpScroll:SetPoint("TOPLEFT", 5, -5)
    gpScroll:SetPoint("BOTTOMRIGHT", -25, 5)
    local gpContent = CreateFrame("Frame", nil, gpScroll)
    gpContent:SetSize(1, 1)
    gpScroll:SetScrollChild(gpContent)
    sfui.trackedoptions.gpContent = gpContent

    -- Anchoring Expanded Preview (midPanel) to the right of General Options
    midPanel:SetPoint("TOPLEFT", genPanel, "TOPRIGHT", 5, 0)
    midPanel:SetPoint("BOTTOMRIGHT", iconsPanel, "BOTTOMRIGHT", 0, 0)
    sfui.trackedoptions.iconsPanel = iconsPanel

    frame.StartMoving = function() frame:StartMoving() end
    frame.StopMovingOrSizing = function() frame:StopMovingOrSizing() end

    frame:SetScript("OnShow", function()
        if InCombatLockdown() then
            print("|cffFF0000SFUI:|r Cannot configure tracked bars in combat.")
            frame:Hide()
            return
        end
        -- Select last tab immediately to avoid blank frame
        local startTab = SfuiDB.lastSelectedTabId or 3
        select_tab(frame, startTab)

        -- Retry checking for panels until specced info is available
        local attempts = 0
        local ticker
        ticker = C_Timer.NewTicker(0.1, function()
            attempts = attempts + 1
            local panels = sfui.common.get_cooldown_panels()
            local dataProvider = CooldownViewerSettings and CooldownViewerSettings.GetDataProvider and
                CooldownViewerSettings:GetDataProvider()

            if #panels > 0 and dataProvider then
                UpdateCooldownsList() -- Updates content list
                ticker:Cancel()
            elseif attempts > 30 then
                -- Give up after 3 seconds
                UpdateCooldownsList()
                ticker:Cancel()
            end
        end)

        if not C_AddOns.IsAddOnLoaded("Blizzard_CooldownViewer") then C_AddOns.LoadAddOn("Blizzard_CooldownViewer") end
    end)
end

UpdateCooldownsList = function()
    if not frame then return end
    if not CooldownViewerSettings then return end

    local dataProvider = CooldownViewerSettings:GetDataProvider()
    if not dataProvider then return end

    local cooldownIDs = dataProvider:GetOrderedCooldownIDs()
    local groupedCooldowns = {}

    for _, cooldownID in ipairs(cooldownIDs) do
        if not issecretvalue(cooldownID) then
            local info = dataProvider:GetCooldownInfoForID(cooldownID)
            if info then
                -- We only care about Default Tracks for this list
                local groupID = info.category or 0
                if not groupedCooldowns[groupID] then groupedCooldowns[groupID] = {} end

                local effectiveSpellID = info.overrideTooltipSpellID or info.overrideSpellID or info.spellID
                if effectiveSpellID and not issecretvalue(effectiveSpellID) then
                    local iconTexture = C_Spell.GetSpellTexture(effectiveSpellID)

                    table.insert(groupedCooldowns[groupID], {
                        cooldownID = cooldownID,
                        name = C_Spell.GetSpellName(effectiveSpellID) or "Unknown",
                        icon = iconTexture,
                        spellID = effectiveSpellID, -- Capture ID for tooltip
                        isKnown = info.isKnown
                    })
                end
            end
        end
    end

    for _, child in ipairs({ content:GetChildren() }) do
        child:Hide(); child:SetParent(nil)
    end

    local yOffset = 0
    local sortedGroups = {}
    for groupID in pairs(groupedCooldowns) do
        if groupID == 3 then table.insert(sortedGroups, groupID) end
    end
    table.sort(sortedGroups)

    for _, groupID in ipairs(sortedGroups) do
        for i, cd in ipairs(groupedCooldowns[groupID]) do
            local row = CreateFrame("Frame", nil, content)
            row:SetSize(780, 24) -- Use more width
            row:SetPoint("TOPLEFT", 0, yOffset)

            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(20, 20)
            icon:SetPoint("LEFT", 0, 0) -- Leftmost column
            icon:SetTexture(cd.icon or 134400)
            if not cd.isKnown then icon:SetDesaturated(true) end



            local nameText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            nameText:SetPoint("LEFT", icon, "RIGHT", 5, 0)
            nameText:SetJustifyH("LEFT")
            nameText:SetText(cd.name)

            -- Tooltip (HIT RECT) - must be after nameText exists
            local hitRect = CreateFrame("Frame", nil, row)
            hitRect:SetPoint("TOPLEFT", icon, "TOPLEFT")
            hitRect:SetPoint("BOTTOMRIGHT", nameText, "BOTTOMRIGHT")
            hitRect:EnableMouse(true)
            hitRect:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetSpellByID(cd.spellID or 0)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("CooldownID: " .. (cd.cooldownID or "nil"), 1, 1, 1)
                GameTooltip:AddLine("SpellID: " .. (cd.spellID or "nil"), 1, 1, 1)
                GameTooltip:Show()
            end)
            hitRect:SetScript("OnLeave", function() GameTooltip:Hide() end)

            local attachChk = sfui.common.create_checkbox(row, "", nil, function(val)
                local barDB = sfui.common.ensure_tracked_bar_db(cd.cooldownID)
                SfuiDB.trackedBars[cd.cooldownID].stackAboveHealth = val
                if sfui.trackedbars and sfui.trackedbars.ForceLayoutUpdate then sfui.trackedbars.ForceLayoutUpdate() end
            end)
            attachChk:SetPoint("LEFT", row, "LEFT", 320, 0)
            local attachVal = false
            if sfui.trackedbars and sfui.trackedbars.GetConfig then
                local cfg = sfui.trackedbars.GetConfig(cd.cooldownID)
                if cfg and cfg.stackAboveHealth then attachVal = true end
            end
            attachChk:SetChecked(attachVal)

            local stackChk = sfui.common.create_checkbox(row, "", nil, function(val)
                local barDB = sfui.common.ensure_tracked_bar_db(cd.cooldownID)
                SfuiDB.trackedBars[cd.cooldownID].stackMode = val
                if sfui.trackedbars and sfui.trackedbars.ForceLayoutUpdate then sfui.trackedbars.ForceLayoutUpdate() end
            end)
            stackChk:SetPoint("LEFT", row, "LEFT", 400, 0)
            local stackVal = false
            if sfui.trackedbars and sfui.trackedbars.GetConfig then
                local cfg = sfui.trackedbars.GetConfig(cd.cooldownID)
                if cfg and cfg.stackMode then stackVal = true end
            end
            stackChk:SetChecked(stackVal)

            local maxInput = CreateNumericEditBox(row, 30, 18, function(val)
                local barDB = sfui.common.ensure_tracked_bar_db(cd.cooldownID)
                if val and val > 0 then SfuiDB.trackedBars[cd.cooldownID].maxStacks = val else SfuiDB.trackedBars[cd.cooldownID].maxStacks = nil end
                if sfui.trackedbars and sfui.trackedbars.ForceLayoutUpdate then sfui.trackedbars.ForceLayoutUpdate() end
            end)
            maxInput:SetPoint("LEFT", row, "LEFT", 480, 0)
            local dbVal = SfuiDB.trackedBars and SfuiDB.trackedBars[cd.cooldownID] and
                SfuiDB.trackedBars[cd.cooldownID].maxStacks
            if dbVal then maxInput:SetText(dbVal) end


            local textChk = sfui.common.create_checkbox(row, "", nil, function(val)
                local barDB = sfui.common.ensure_tracked_bar_db(cd.cooldownID)
                SfuiDB.trackedBars[cd.cooldownID].showStacksText = val
                if sfui.trackedbars and sfui.trackedbars.ForceLayoutUpdate then sfui.trackedbars.ForceLayoutUpdate() end
            end)
            textChk:SetPoint("LEFT", row, "LEFT", 560, 0)
            local showStacksTextVal = false
            if sfui.trackedbars and sfui.trackedbars.GetConfig then
                local cfg = sfui.trackedbars.GetConfig(cd.cooldownID)
                if cfg and cfg.showStacksText then showStacksTextVal = true end
            end
            textChk:SetChecked(showStacksTextVal)

            local titleChk = sfui.common.create_checkbox(row, "", nil, function(val)
                local barDB = sfui.common.ensure_tracked_bar_db(cd.cooldownID)
                SfuiDB.trackedBars[cd.cooldownID].showName = val
                if sfui.trackedbars and sfui.trackedbars.ForceLayoutUpdate then sfui.trackedbars.ForceLayoutUpdate() end
            end)
            titleChk:SetPoint("LEFT", row, "LEFT", 640, 0)
            local showNameVal = true
            if sfui.trackedbars and sfui.trackedbars.GetConfig then
                local cfg = sfui.trackedbars.GetConfig(cd.cooldownID)
                if cfg and cfg.showName == false then showNameVal = false end
            end
            titleChk:SetChecked(showNameVal)

            local initialColor = sfui.config.colors.purple
            if sfui.trackedbars and sfui.trackedbars.GetConfig then
                local cfg = sfui.trackedbars.GetConfig(cd.cooldownID)
                if cfg and cfg.color then initialColor = cfg.color end
            end
            local swatch = sfui.common.create_color_swatch(row, initialColor, function(r, g, b)
                if sfui.trackedbars and sfui.trackedbars.SetColor then sfui.trackedbars.SetColor(cd.cooldownID, r, g, b) end
            end)
            swatch:SetPoint("LEFT", row, "LEFT", 720, 0)

            yOffset = yOffset - 26
        end
    end

    content:SetHeight(math.max(math.abs(yOffset), 210)) -- Minimum height for 8 bars
    sfui.trackedoptions.UpdateEditor()
end

function sfui.trackedoptions.UpdateEditor()
    sfui.trackedoptions.UpdatePanelList()
    sfui.trackedoptions.UpdatePreview()
    sfui.trackedoptions.UpdateSettings()

    -- Update Scroll Heights
    if frame and frame.tabs then
        local barsTab = frame.tabs[1]
        if barsTab.scrollChild then
            barsTab.scrollChild:SetHeight(content:GetHeight() + 100)
        end
        -- Icons tab no longer has a main scrollChild to update
    end
end

function sfui.trackedoptions.UpdatePanelList()
    local lpContent = sfui.trackedoptions.lpContent
    if not lpContent then return end
    for _, child in ipairs({ lpContent:GetChildren() }) do
        child:Hide(); child:SetParent(nil)
    end

    local panels = sfui.common.get_cooldown_panels()
    local y = 0
    for i, panel in ipairs(panels) do
        local btn = CreateFlatButton(lpContent, panel.name or ("Panel " .. i), 120, 20)
        btn:SetPoint("TOPLEFT", 0, y)
        if i == sfui.trackedoptions.selectedPanelIndex then
            btn:SetBackdropBorderColor(g.colors.purple[1], g.colors.purple[2], g.colors.purple[3], 1)
        end
        btn:SetScript("OnClick", function()
            sfui.trackedoptions.selectedPanelIndex = i
            sfui.trackedoptions.UpdateEditor()
        end)
        y = y - 22
    end
    lpContent:SetHeight(math.abs(y))
end

local function GetGridIndexFromMouse(parent, panel, size, spacing)
    local mx, my = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    mx, my = mx / s, my / s
    if not parent then return nil end

    local entries = panel.entries or {}
    local dragIdx = sfui.trackedoptions.draggingIndex
    local children = { parent:GetChildren() }

    local bestDist = math.huge
    local targetChildIndex = nil
    local isAfter = false

    local growthH = panel.growthH or "Right"
    local growthV = panel.growthV or "Down"

    for i, child in ipairs(children) do
        -- Ignore the dragged icon itself for targeting to prevent jitter
        if i ~= dragIdx then
            local l, b, w, h = child:GetRect()
            if l then
                local cx, cy = l + w / 2, b + h / 2
                local dx = math.abs(mx - cx)
                local dy = math.abs(my - cy)

                -- Horizontal layouts: Priority to current row
                if growthH == "Center" or growthH == "Right" or growthH == "Left" then
                    if my > b and my < b + h then dy = 0 end
                end

                local dist = dx + dy * 10 -- Vertical priority weighting
                if dist < bestDist then
                    bestDist = dist
                    targetChildIndex = i
                    -- Determine before/after based on growth direction
                    if growthH == "Center" or growthH == "Right" or growthH == "Left" then
                        isAfter = (mx > cx)
                        if growthH == "Left" then isAfter = (mx < cx) end
                    else
                        isAfter = (my < cy)
                        if growthV == "Up" then isAfter = (my > cy) end
                    end
                end
            end
        end
    end

    if not targetChildIndex then return nil end

    -- Map targetChildIndex to visual list position
    local visualPosOfTarget = 0
    for i, _ in ipairs(entries) do
        if i ~= dragIdx then
            visualPosOfTarget = visualPosOfTarget + 1
            if i == targetChildIndex then
                break
            end
        end
    end

    local dropIdx = isAfter and (visualPosOfTarget + 1) or visualPosOfTarget
    return dropIdx, targetChildIndex, isAfter
end
sfui.trackedoptions.GetGridIndexFromMouse = GetGridIndexFromMouse

local function UpdatePreviewLayout(dropIdx)
    local parent = sfui.trackedoptions.previewChild
    if not parent then return end

    local idx = sfui.trackedoptions.selectedPanelIndex or 1
    local panels = sfui.common.get_cooldown_panels()
    local panel = panels and panels[idx]
    if not panel then return end

    local entries = panel.entries or {}
    local size = panel.size or 50
    local spacing = panel.spacing or 2
    local dragIdx = sfui.trackedoptions.draggingIndex

    -- Create visual list order
    local visualList = {}

    -- 1. Add all non-dragged items
    for i, _ in ipairs(entries) do
        if i ~= dragIdx then
            table.insert(visualList, i)
        end
    end

    -- 2. Insert dragIdx at dropIdx (simulated)
    if dragIdx then
        local insertPos = dropIdx or #visualList + 1
        -- Boundary clamp
        if insertPos > #visualList + 1 then insertPos = #visualList + 1 end
        table.insert(visualList, insertPos, dragIdx)
    end

    -- 3. Position children
    local children = { parent:GetChildren() }

    local maxW, maxH = 0, 0
    local numColumns = panel.columns or 10
    local growthH = panel.growthH or "Center"
    local growthV = panel.growthV or "Down"
    local hSign = (growthH == "Left") and -1 or 1
    local vSign = (growthV == "Up") and 1 or -1

    for pos, originalIdx in ipairs(visualList) do
        local child = children[originalIdx]
        if child then
            local col = (pos - 1) % numColumns
            local row = math.floor((pos - 1) / numColumns)

            local ox, oy, anchorPoint

            if growthH == "Center" then
                local totalIcons = #visualList
                local startIdx = row * numColumns + 1
                local endIdx = math.min((row + 1) * numColumns, totalIcons)
                local numInRow = endIdx - startIdx + 1
                local centerOffset = col - (numInRow - 1) / 2
                ox = centerOffset * (size + spacing)
                oy = row * (size + spacing) * vSign
                anchorPoint = "CENTER"
            else
                ox = col * (size + spacing) * hSign
                oy = row * (size + spacing) * vSign
                local isLeft = (panel.x or 0) < 0
                local rawAnchor = panel.anchor or (isLeft and "topright" or "topleft")
                anchorPoint = string.upper(rawAnchor)
            end

            child:ClearAllPoints()
            child:SetPoint(anchorPoint, parent, anchorPoint, ox, oy)

            -- Ghost Visibility
            if originalIdx == dragIdx then
                child:SetAlpha(0)
            else
                child:SetAlpha(1)
            end

            child:Show()

            maxW = math.max(maxW, (col + 1) * (size + spacing))
            maxH = math.max(maxH, (row + 1) * (size + spacing))
        end
    end
    parent:SetSize(math.max(maxW, 10), math.max(maxH, 10))
end
sfui.trackedoptions.UpdatePreviewLayout = UpdatePreviewLayout

function sfui.trackedoptions.UpdatePreview()
    local parent = sfui.trackedoptions.previewChild
    if not parent then return end
    for _, child in ipairs({ parent:GetChildren() }) do
        if sfui.trackedicons and sfui.trackedicons.StopGlow then
            sfui.trackedicons.StopGlow(child)
        end
        child:Hide(); child:SetParent(nil)
    end

    local idx = sfui.trackedoptions.selectedPanelIndex or 1
    local panels = sfui.common.get_cooldown_panels()
    local panel = panels and panels[idx]
    if not panel then return end

    local entries = panel.entries or {}
    local size = panel.size or 50
    local spacing = panel.spacing or 2
    local maxW, maxH = 0, 0

    for i, entry in ipairs(entries) do
        local icon = CreateFrame("Button", nil, parent, "BackdropTemplate")
        icon:SetSize(size, size)
        icon:RegisterForClicks("AnyUp")
        local tex = icon:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        local iconTexture
        if entry.type == "cooldown" and entry.cooldownID then
            local cdInfo = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo(entry.cooldownID)
            if cdInfo then
                local spellID = cdInfo.overrideSpellID or cdInfo.spellID
                iconTexture = C_Spell.GetSpellTexture(spellID)
            else
                iconTexture = C_Spell.GetSpellTexture(entry.spellID or entry.id)
            end
        elseif entry.type == "item" then
            iconTexture = C_Item.GetItemIconByID(entry.id)
        else
            iconTexture = C_Spell.GetSpellTexture(entry.id)
        end
        tex:SetTexture(iconTexture or 134400) -- Fallback to generic question mark if nil

        -- Preview panel layout logic
        local growthH = panel.growthH or "Center" -- Default to Center for preview if not set
        local growthV = panel.growthV or "Down"

        -- Force Center growth for better preview experience if requested,
        -- or just ensure Center works if selected.

        local hSign = (growthH == "Left") and -1 or 1
        local vSign = (growthV == "Up") and 1 or -1
        local numColumns = panel.columns or 10
        icon.originalIndex = i         -- Store original index for drag operations
        icon.iconTexture = iconTexture -- Store texture for ghost icon

        -- Enhanced tooltip for all icons
        icon:SetScript("OnEnter", function(self)
            if sfui.trackedoptions.draggingIndex then return end -- Suppression
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if entry.type == "cooldown" and entry.cooldownID then
                local cdInfo = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo(entry.cooldownID)
                if cdInfo then
                    local spellID = cdInfo.overrideSpellID or cdInfo.spellID
                    GameTooltip:SetSpellByID(spellID)
                else
                    GameTooltip:SetSpellByID(entry.spellID or entry.id)
                end
            elseif entry.type == "item" then
                GameTooltip:SetItemByID(entry.id)
            else
                GameTooltip:SetSpellByID(entry.id)
            end
            GameTooltip:Show()
        end)
        icon:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        -- Right-Click to Remove
        icon:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                table.remove(entries, i)
                sfui.trackedoptions.UpdateEditor()
                if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
            end
        end)

        -- Drag to Reorder
        icon:RegisterForDrag("LeftButton")
        icon:SetScript("OnDragStart", function(self)
            if InCombatLockdown() then return end
            sfui.trackedoptions.draggingIndex = self.originalIndex
            GameTooltip:Hide() -- Preemptive hide

            -- Ghost Icon
            local ghost = sfui.trackedoptions.ghostIcon
            if not ghost then
                ghost = CreateFrame("Frame", nil, UIParent)
                ghost:SetSize(size, size)
                ghost:SetFrameStrata("TOOLTIP")
                ghost.tex = ghost:CreateTexture(nil, "ARTWORK")
                ghost.tex:SetAllPoints()
                ghost:SetAlpha(0.6)
                sfui.trackedoptions.ghostIcon = ghost
            end
            ghost:SetSize(size, size)
            ghost.tex:SetTexture(self.iconTexture or 134400)
            ghost:Show()

            -- Start following cursor
            ghost:SetScript("OnUpdate", function(self)
                local cx, cy = GetCursorPosition()
                local scale = UIParent:GetEffectiveScale() or 1
                self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)

                -- Update Insertion Marker logic
                local marker = sfui.trackedoptions.insertionMarker
                if not marker then
                    marker = parent:CreateTexture(nil, "OVERLAY", nil, 7)
                    marker:SetTexture("Interface\\ChatFrame\\UI-ChatFrame-DockHighlight")
                    marker:SetBlendMode("ADD")
                    marker:SetVertexColor(0, 1, 1, 0.8) -- Cyan glow
                    sfui.trackedoptions.insertionMarker = marker
                end

                local dropIdx, targetChildIndex, isAfter = sfui.trackedoptions.GetGridIndexFromMouse(parent, panel, size,
                    spacing)
                sfui.trackedoptions.dropTargetIndex = dropIdx

                if dropIdx then
                    -- Restore Live Spacing
                    sfui.trackedoptions.UpdatePreviewLayout(dropIdx)

                    -- Position marker relative to the target child's edge
                    local children = { parent:GetChildren() }
                    local targetFrame = targetChildIndex and children[targetChildIndex]

                    if targetFrame then
                        marker:ClearAllPoints()
                        -- Horizontal/Vertical orientation
                        if panel.growthH == "Center" or panel.growthH == "Left" or panel.growthH == "Right" then
                            marker:SetSize(8, size + 10)
                            local point = isAfter and "RIGHT" or "LEFT"
                            local relPoint = isAfter and "RIGHT" or "LEFT"
                            marker:SetPoint("CENTER", targetFrame, point, (isAfter and 1 or -1) * (spacing / 2), 0)
                        else
                            marker:SetSize(size + 10, 8)
                            local point = isAfter and "BOTTOM" or "TOP"
                            local relPoint = isAfter and "BOTTOM" or "TOP"
                            marker:SetPoint("CENTER", targetFrame, point, 0, (isAfter and -1 or 1) * (spacing / 2))
                        end
                        marker:Show()
                    else
                        marker:Hide()
                    end
                else
                    sfui.trackedoptions.UpdatePreviewLayout(nil)
                    marker:Hide()
                end
            end)

            -- Global Drop Logic
            parent:RegisterEvent("GLOBAL_MOUSE_UP")
            parent:SetScript("OnEvent", function(p, event, button)
                if event == "GLOBAL_MOUSE_UP" and button == "LeftButton" then
                    p:UnregisterEvent("GLOBAL_MOUSE_UP")
                    p:SetScript("OnEvent", nil)

                    local ghost = sfui.trackedoptions.ghostIcon
                    if ghost then
                        ghost:Hide()
                        ghost:SetScript("OnUpdate", nil)
                    end

                    local marker = sfui.trackedoptions.insertionMarker
                    if marker then marker:Hide() end

                    local fromIdx = sfui.trackedoptions.draggingIndex
                    local toIdx = sfui.trackedoptions.dropTargetIndex

                    if fromIdx and toIdx and fromIdx ~= toIdx then
                        -- Correction for shifting indices if moving forward
                        if fromIdx < toIdx then toIdx = toIdx - 1 end
                        -- Boundary check
                        if toIdx > #entries + 1 then toIdx = #entries + 1 end

                        local item = table.remove(entries, fromIdx)
                        table.insert(entries, toIdx, item)

                        sfui.trackedoptions.UpdateEditor()
                        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
                    end

                    sfui.trackedoptions.draggingIndex = nil
                    sfui.trackedoptions.dropTargetIndex = nil
                    sfui.trackedoptions.UpdatePreviewLayout(nil)
                end
            end)
        end)
    end

    -- Call default layout
    if sfui.trackedoptions.UpdatePreviewLayout then
        sfui.trackedoptions.UpdatePreviewLayout(nil)
    end
end

function sfui.trackedoptions.UpdateSettings()
    local gpContent = sfui.trackedoptions.gpContent
    if not gpContent then return end

    -- Clear panel
    for _, child in ipairs({ gpContent:GetChildren() }) do
        child:Hide(); child:SetParent(nil)
    end
    for _, reg in ipairs({ gpContent:GetRegions() }) do reg:Hide() end

    local idx = sfui.trackedoptions.selectedPanelIndex or 1
    local panels = sfui.common.get_cooldown_panels()
    local panel = panels and panels[idx]
    if not panel then return end

    -- Panel-wide y-offset
    local gy = -10
    local fullW = 275
    local halfW = 135

    local function AddGeneralHeader(text)
        gy = gy - 5
        local h = gpContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        h:SetPoint("TOPLEFT", 5, gy)
        h:SetText(text)
        h:SetTextColor(g.colors.cyan[1], g.colors.cyan[2], g.colors.cyan[3])
        gy = gy - 20
        return h
    end

    local function AddGeneralLabel(text)
        local l = gpContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        l:SetPoint("TOPLEFT", 5, gy)
        l:SetText(text)
        gy = gy - 15
        return l
    end

    -- POPULATE GENERAL PANEL
    AddGeneralHeader("Panel: " .. (panel.name or "Unnamed"))
    AddGeneralLabel("panel name")
    local nameEB = CreateNumericEditBox(gpContent, 160, 18, function(val) end)
    nameEB:SetScript("OnEnterPressed", function(self)
        panel.name = self:GetText(); sfui.trackedoptions.UpdateEditor()
    end)
    nameEB:SetPoint("TOPLEFT", 5, gy)
    nameEB:SetText(panel.name or "")
    gy = gy - 30

    local xSlider = sfui.common.create_slider_input(gpContent, "pos x", function() return panel.x end, -1000, 1000,
        1, function(v)
            panel.x = v; if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end, halfW)
    xSlider:SetPoint("TOPLEFT", 5, gy); xSlider:SetSliderValue(panel.x or 0)

    local ySlider = sfui.common.create_slider_input(gpContent, "pos y", function() return panel.y end, -1000, 1000,
        1, function(v)
            panel.y = v; if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end, halfW)
    ySlider:SetPoint("TOPLEFT", 5 + halfW + 10, gy); ySlider:SetSliderValue(panel.y or 0)
    gy = gy - 45

    -- Icon Size Input directly below Pos X/Y
    AddGeneralLabel("icon size")
    local sizeEB = CreateNumericEditBox(gpContent, 60, 18, function(val)
        panel.size = tonumber(val) or panel.size
        sfui.trackedoptions.UpdatePreview()
        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
    end)
    sizeEB:SetPoint("TOPLEFT", 5, gy)
    sizeEB:SetText(panel.size or 50)
    gy = gy - 30

    local spacingSlider = sfui.common.create_slider_input(gpContent, "spacing", function() return panel.spacing end, 0,
        50, 1, function(v)
            panel.spacing = v; sfui.trackedoptions.UpdatePreview()
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end, halfW)
    spacingSlider:SetPoint("TOPLEFT", 5, gy); spacingSlider:SetSliderValue(panel.spacing or 2)

    if key ~= "center" then
        local columnsSlider = sfui.common.create_slider_input(gpContent, "columns", function() return panel.columns end,
            1,
            20,
            1, function(v)
                panel.columns = v; sfui.trackedoptions.UpdatePreview()
                if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
            end, halfW)
        columnsSlider:SetPoint("TOPLEFT", 5 + halfW + 10, gy); columnsSlider:SetSliderValue(panel.columns or 10)
    end
    gy = gy - 30

    local spanChk = sfui.common.create_checkbox(gpContent, "auto-span width (center)", nil, function(v)
        panel.spanWidth = v
        sfui.trackedoptions.UpdatePreview()
        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
    end)
    spanChk:SetPoint("TOPLEFT", 5, gy)
    -- For panel settings, nil usually means inherit, but checkbox needs state.
    -- Default to unchecked if nil? Or check global?
    -- Let's just use boolean logic.
    spanChk:SetChecked(panel.spanWidth or false)
    gy = gy - 30

    local bgChk = sfui.common.create_checkbox(gpContent, "show panel background", nil, function(v)
        panel.showBackground = v
        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
    end)
    bgChk:SetPoint("TOPLEFT", 5, gy)
    bgChk:SetChecked(panel.showBackground == nil and g.icon_panel_global_defaults.showBackground or panel.showBackground)
    gy = gy - 30

    local bgAlphaS = sfui.common.create_slider_input(gpContent, "bg alpha",
        function() return panel.backgroundAlpha or 0.5 end, 0.1, 1.0, 0.1, function(v)
            panel.backgroundAlpha = v
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end, halfW)
    bgAlphaS:SetPoint("TOPLEFT", 5, gy)
    bgAlphaS:SetSliderValue(panel.backgroundAlpha or 0.5)
    gy = gy - 40

    local function StyleSelection(btn, isActive)
        btn.isActive = isActive
        if isActive then
            btn:SetBackdropBorderColor(g.colors.purple[1], g.colors.purple[2], g.colors.purple[3], 1)
            btn:GetFontString():SetTextColor(g.colors.purple[1], g.colors.purple[2], g.colors.purple[3], 1)
        else
            btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
            btn:GetFontString():SetTextColor(0.6, 0.6, 0.6, 1)
        end
    end

    local function ApplyPlacementHover(btn)
        btn:SetScript("OnEnter", function(self)
            if self.isActive then
                self:SetBackdropBorderColor(g.colors.purple[1], g.colors.purple[2], g.colors.purple[3], 1)
                self:GetFontString():SetTextColor(g.colors.purple[1], g.colors.purple[2], g.colors.purple[3], 1)
            else
                self:SetBackdropBorderColor(g.colors.cyan[1], g.colors.cyan[2], g.colors.cyan[3], 1)
                self:GetFontString():SetTextColor(g.colors.cyan[1], g.colors.cyan[2], g.colors.cyan[3], 1)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            StyleSelection(self, self.isActive)
        end)
    end

    AddGeneralHeader("Placement & Growth")

    local anchorLabel = gpContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    anchorLabel:SetPoint("TOPLEFT", 5, gy)
    anchorLabel:SetText("anchor")

    local growthLabel = gpContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    growthLabel:SetPoint("TOPLEFT", 110, gy)
    growthLabel:SetText("growth")

    gy = gy - 20

    -- Anchor Grid (3x3)
    local anchorGrid = CreateFrame("Frame", nil, gpContent)
    anchorGrid:SetSize(65, 65)
    anchorGrid:SetPoint("TOPLEFT", 5, gy)

    local anchorBtns = {}
    local function CreateAnchorBtn(name, anchorKey, x, y)
        local b = CreateFlatButton(anchorGrid, name, 20, 20)
        b:SetPoint("TOPLEFT", x, y)
        b:SetScript("OnClick", function()
            panel.anchor = anchorKey
            for _, btn in pairs(anchorBtns) do StyleSelection(btn, btn.key == anchorKey) end
            sfui.trackedoptions.UpdatePreview()
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end)
        b.key = anchorKey
        anchorBtns[anchorKey] = b
        ApplyPlacementHover(b)
        StyleSelection(b, (panel.anchor or "topleft") == anchorKey)
        return b
    end

    CreateAnchorBtn("TL", "topleft", 0, 0)
    CreateAnchorBtn("T", "top", 22, 0)
    CreateAnchorBtn("TR", "topright", 44, 0)

    CreateAnchorBtn("L", "left", 0, -22)
    CreateAnchorBtn("C", "center", 22, -22)
    CreateAnchorBtn("R", "right", 44, -22)

    CreateAnchorBtn("BL", "bottomleft", 0, -44)
    CreateAnchorBtn("B", "bottom", 22, -44)
    CreateAnchorBtn("BR", "bottomright", 44, -44)

    -- Growth Grid (Cross Pattern)
    local growthGrid = CreateFrame("Frame", nil, gpContent)
    growthGrid:SetSize(65, 65)
    growthGrid:SetPoint("TOPLEFT", 110, gy)

    local hBtns = {}
    local function CreateHGrowthBtn(name, val, x, y)
        local b = CreateFlatButton(growthGrid, name, 20, 20)
        b:SetPoint("TOPLEFT", x, y)
        b:SetScript("OnClick", function()
            panel.growthH = val
            for _, btn in pairs(hBtns) do StyleSelection(btn, btn.val == val) end
            sfui.trackedoptions.UpdatePreview()
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end)
        b.val = val
        hBtns[val] = b
        ApplyPlacementHover(b)
        StyleSelection(b, (panel.growthH or "Right") == val)
    end

    local vBtns = {}
    local function CreateVGrowthBtn(name, val, x, y)
        local b = CreateFlatButton(growthGrid, name, 20, 20)
        b:SetPoint("TOPLEFT", x, y)
        b:SetScript("OnClick", function()
            panel.growthV = val
            for _, btn in pairs(vBtns) do StyleSelection(btn, btn.val == val) end
            sfui.trackedoptions.UpdatePreview()
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end)
        b.val = val
        vBtns[val] = b
        ApplyPlacementHover(b)
        StyleSelection(b, (panel.growthV or "Down") == val)
    end

    -- Cross Pattern:
    --    UP
    -- L  C  R
    --   DOWN
    CreateVGrowthBtn("U", "Up", 22, 0)
    CreateHGrowthBtn("L", "Left", 0, -22)
    CreateHGrowthBtn("C", "Center", 22, -22)
    CreateHGrowthBtn("R", "Right", 44, -22)
    CreateVGrowthBtn("D", "Down", 22, -44)

    gy = gy - 85

    -- Anchor To Frame (moved row down)
    local anchorToOptions = { "UIParent", "Health Bar", "Tracked Bars" }
    -- Add other panels to the list (excluding self)
    if sfui.config and sfui.config.cooldown_panel_defaults then
        for pName, pCfg in pairs(sfui.config.cooldown_panel_defaults) do
            if pName ~= key and pName ~= "global" and type(pCfg) == "table" then
                if pCfg.name then
                    table.insert(anchorToOptions, pCfg.name)
                end
            end
        end
    end

    local anchorDrop = CreateFrame("Frame", "SfuiAnchorToDropdown", gpContent, "UIDropDownMenuTemplate")
    anchorDrop:SetPoint("TOPLEFT", -15, gy)
    UIDropDownMenu_SetWidth(anchorDrop, 120)
    UIDropDownMenu_SetText(anchorDrop, panel.anchorTo or "UIParent")
    UIDropDownMenu_Initialize(anchorDrop, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, opt in ipairs(anchorToOptions) do
            info.text = opt
            info.checked = (panel.anchorTo == opt)
            info.func = function()
                panel.anchorTo = opt
                UIDropDownMenu_SetText(anchorDrop, opt)

                -- Auto-Snap Logic: If anchoring center/utility panel to HUD or another panel, snap to correct offset
                local isHudCenter = (opt == "Health Bar") and (panel.name == "CENTER" or panel.placement == "center")
                local isPanelStack = (opt ~= "UIParent" and opt ~= "Health Bar" and opt ~= "Tracked Bars")

                if isHudCenter or isPanelStack then
                    local snapY = -2
                    panel.y = snapY
                    if ySlider and ySlider.SetSliderValue then
                        ySlider:SetSliderValue(snapY)
                    end
                end

                if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local atLabel = gpContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    atLabel:SetPoint("BOTTOMLEFT", anchorDrop, "TOPLEFT", 20, 4)
    atLabel:SetText("anchor to frame")
    atLabel:SetTextColor(0.6, 0.6, 0.6)

    gy = gy - 40

    gy = gy - 40

    AddGeneralHeader("Panel Defaults")


    gpContent:SetHeight(math.abs(gy) + 20)
end

function sfui.trackedoptions.toggle_viewer()
    if not frame then
        CreateCooldownsFrame()
        frame:Show()
        UpdateCooldownsList()
        return
    end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        UpdateCooldownsList()
    end
end

function sfui.trackedoptions.RefreshList()
    if frame and frame:IsShown() then UpdateCooldownsList() end
end
