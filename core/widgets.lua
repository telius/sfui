local addonName, addon = ...
sfui = sfui or {}
sfui.widgets = sfui.widgets or {}
sfui.common = sfui.common or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/core/widgets.lua
--  Standardized UI Factory: Panels, Borders, Buttons, Inputs, Dropdowns
-- ══════════════════════════════════════════════════════════════════════════════

local CreateFrame = _G.CreateFrame
local UIParent    = _G.UIParent
local unpack      = _G.unpack or table.unpack

function sfui.widgets.create_panel(parent, width, height)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetSize(width, height)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    panel:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    panel:SetBackdropBorderColor(0, 0, 0, 1)
    return panel
end
sfui.common.create_panel = sfui.widgets.create_panel

function sfui.widgets.create_border(frame, thickness, color, g, b, a)
    local mult = sfui.pixelScale or 1
    thickness = (thickness or 1) * mult

    if not frame.borders then
        frame.borders = {}
        for i = 1, 4 do
            frame.borders[i] = frame:CreateTexture(nil, "BACKGROUND")
            frame.borders[i]:SetTexture("Interface\\Buttons\\WHITE8x8")
        end
    end

    local top, bottom, left, right = unpack(frame.borders)
    local r_val, g_val, b_val, a_val = 0, 0, 0, 1
    if type(color) == "table" then
        r_val = color[1] or color.r or 0
        g_val = color[2] or color.g or 0
        b_val = color[3] or color.b or 0
        a_val = color[4] or color.a or 1
    elseif type(color) == "number" then
        r_val = color
        g_val = g or 0
        b_val = b or 0
        a_val = (a ~= nil and a) or 1
    end

    for _, border in ipairs(frame.borders) do
        border:SetVertexColor(r_val, g_val, b_val, a_val)
    end

    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    top:SetHeight(thickness)

    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(thickness)

    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    left:SetWidth(thickness)

    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(thickness)
end
sfui.common.create_border = sfui.widgets.create_border

function sfui.widgets.apply_square_icon_style(frame, texture)
    if not frame or not texture then return end

    texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    texture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)

    if not frame.borderBackdrop then
        frame.borderBackdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        frame.borderBackdrop:SetAllPoints(frame)
        frame.borderBackdrop:SetFrameLevel(math.max(1, frame:GetFrameLevel() - 1))

        frame.borderBackdrop:SetBackdrop({
            bgFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
            edgeFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
            tile = false,
            tileSize = 0,
            edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        })
    end
    frame.borderBackdrop:SetBackdropColor(0, 0, 0, 0)
    frame.borderBackdrop:SetBackdropBorderColor(0, 0, 0, 1)
    frame.borderBackdrop:Show()
end
sfui.common.apply_square_icon_style = sfui.widgets.apply_square_icon_style

function sfui.widgets.create_fade_animations(frame)
    local fadeInGroup = frame:CreateAnimationGroup()
    local fadeIn = fadeInGroup:CreateAnimation("Alpha")
    fadeIn:SetDuration(0.5)
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetScript("OnPlay", function() frame:Show() end)

    local fadeOutGroup = frame:CreateAnimationGroup()
    local fadeOut = fadeOutGroup:CreateAnimation("Alpha")
    fadeOut:SetDuration(0.5)
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetScript("OnFinished", function() frame:Hide() end)

    return fadeInGroup, fadeOutGroup
end
sfui.common.create_fade_animations = sfui.widgets.create_fade_animations

function sfui.widgets.create_bar(name, frameType, parent, template, configName)
    local cfg = sfui.config[configName or name]
    local mult = sfui.pixelScale or 1
    local backdrop = CreateFrame("Frame", "sfui_" .. name .. "_Backdrop", parent, "BackdropTemplate")
    backdrop:SetFrameStrata("MEDIUM")
    local padding = cfg.backdrop.padding * mult
    backdrop:SetSize(cfg.width + padding * 2, cfg.height + padding * 2)

    backdrop:SetBackdrop({
        bgFile = (sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
        tile = true,
        tileSize = 32,
    })
    backdrop:SetBackdropColor(cfg.backdrop.color[1], cfg.backdrop.color[2], cfg.backdrop.color[3], cfg.backdrop.color[4])

    local bar = CreateFrame(frameType, "sfui_" .. name, backdrop, template)
    bar:SetSize(cfg.width, cfg.height)
    bar:SetPoint("CENTER")
    if bar.SetStatusBarTexture then
        bar:SetStatusBarTexture(sfui.widgets.get_bar_texture())
    end
    bar.backdrop = backdrop
    bar.fadeInAnim, bar.fadeOutAnim = sfui.widgets.create_fade_animations(backdrop)
    return bar
end
sfui.common.create_bar = sfui.widgets.create_bar

function sfui.widgets.get_bar_texture()
    local textureName = SfuiDB and SfuiDB.barTexture
    local LSM = _G.LibStub and _G.LibStub("LibSharedMedia-3.0", true)
    local texturePath
    if LSM and textureName then
        texturePath = LSM:Fetch("statusbar", textureName)
    end
    if not texturePath and sfui.config and sfui.config.blizzard_bar_textures and textureName then
        texturePath = sfui.config.blizzard_bar_textures[textureName]
        if not texturePath and type(textureName) == "string" then
            local normName = textureName:gsub("\\", "/"):lower()
            for name, path in pairs(sfui.config.blizzard_bar_textures) do
                if name:lower() == normName or path:gsub("\\", "/"):lower() == normName then
                    texturePath = path
                    break
                end
            end
        end
    end
    if not texturePath and type(textureName) == "string" and textureName:find("^[iI]nterface[/\\]") then
        texturePath = textureName
    end
    if not texturePath or texturePath == "" then
        texturePath = (sfui.config and sfui.config.barTexture) or "Interface/Buttons/WHITE8X8"
    end
    if sfui.config then
        sfui.config.barTexture = texturePath
    end
    return texturePath
end
sfui.common.get_bar_texture = sfui.widgets.get_bar_texture

function sfui.widgets.style_text(fs, fontObj, size, flags)
    if not fs then return end
    if fontObj then fs:SetFontObject(fontObj) end
    if size or flags then
        local font, curSize, curFlags = fs:GetFont()
        fs:SetFont(font, size or curSize, flags or "")
    end
    fs:SetShadowOffset(0, 0)
    fs:SetTextColor(1, 1, 1, 1)
end
sfui.common.style_text = sfui.widgets.style_text

function sfui.widgets.create_flat_button(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)

    btn:SetNormalFontObject("GameFontHighlightSmall")
    btn:SetText(text)
    local fs = btn:GetFontString()
    if fs then
        local fontFile = (sfui.config and sfui.config.fontFile) or "Fonts\\FRIZQT__.TTF"
        fs:SetFont(fontFile, 11, "")
        fs:SetTextColor(1, 1, 1, 1)
    end

    if sfui.theme and sfui.theme.ApplyButtonStyle then
        sfui.theme.ApplyButtonStyle(btn, false)
        sfui.theme.RegisterButton(btn, false)
    else
        local mult = sfui.pixelScale or 1
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = mult,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        })
        btn:SetBackdropColor(0, 0, 0, 1)
        btn:SetBackdropBorderColor(0, 0, 0, 1)

        btn:SetScript("OnEnter", function(self)
            local purple = (sfui.config and sfui.config.colors and sfui.config.colors.purple) or { 0.4, 0, 1 }
            self:SetBackdropBorderColor(purple[1], purple[2], purple[3], 1)
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(0, 0, 0, 1)
        end)
    end

    return btn
end
sfui.common.create_flat_button = sfui.widgets.create_flat_button

function sfui.widgets.create_styled_button(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 120, height or 25)

    btn.text = btn:CreateFontString(nil, "OVERLAY", sfui.config and sfui.config.font or "GameFontNormal")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(text or "")
    sfui.widgets.style_text(btn.text)

    if sfui.theme and sfui.theme.ApplyButtonStyle then
        sfui.theme.ApplyButtonStyle(btn, true)
        sfui.theme.RegisterButton(btn, true)
    else
        btn:SetBackdrop({
            bgFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
            edgeFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        })
        btn:SetBackdropColor(0.2, 0.2, 0.2, 1)
        btn:SetBackdropBorderColor(0, 0, 0, 1)

        btn:SetScript("OnEnter", function(self)
            local purple = (sfui.config and sfui.config.colors and sfui.config.colors.purple) or { 0.4, 0, 1 }
            self:SetBackdropBorderColor(purple[1], purple[2], purple[3], 1)
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(0, 0, 0, 1)
        end)
    end

    return btn
end
sfui.common.create_styled_button = sfui.widgets.create_styled_button

function sfui.widgets.create_close_button(parent, onClickFunc, size)
    size = size or 24
    local btn = sfui.widgets.create_flat_button(parent, "X", size, size)
    btn.isCloseButton = true
    btn:SetPoint("TOPRIGHT", -5, -5)
    btn:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)
    local fs = btn:GetFontString()
    if fs then
        local fontFile = (sfui.config and sfui.config.fontFile) or "Fonts\\FRIZQT__.TTF"
        fs:SetFont(fontFile, math.max(10, math.floor(size * 0.5)), "")
        fs:SetTextColor(1, 1, 1, 1)
    end
    btn:SetScript("OnClick", onClickFunc or function()
        if parent and parent.Hide then parent:Hide() end
    end)

    if sfui.theme and sfui.theme.ApplyCloseButtonStyle then
        sfui.theme.ApplyCloseButtonStyle(btn)
        sfui.theme.RegisterCloseButton(btn)
    end

    btn:SetScript("OnEnter", function(self)
        if not self.isThemedClose then
            self:SetBackdropBorderColor(1, 0.2, 0.2, 1)
            local fString = self:GetFontString()
            if fString then fString:SetTextColor(1, 0.3, 0.3, 1) end
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if not self.isThemedClose then
            self:SetBackdropBorderColor(0, 0, 0, 1)
            local fString = self:GetFontString()
            if fString then fString:SetTextColor(1, 1, 1, 1) end
        end
    end)
    return btn
end
sfui.common.create_close_button = sfui.widgets.create_close_button

function sfui.widgets.create_remove_button(parent, onClickFunc, width, height, tooltip)
    local btn = sfui.widgets.create_flat_button(parent, "X", width or 20, height or 20)
    local fs = btn:GetFontString()
    if fs then
        local fontFile = (sfui.config and sfui.config.fontFile) or "Fonts\\FRIZQT__.TTF"
        fs:SetFont(fontFile, math.max(9, math.floor((height or 20) * 0.5)), "")
        fs:SetTextColor(1, 1, 1, 1)
    end
    if onClickFunc then
        btn:SetScript("OnClick", onClickFunc)
    end
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1, 0.2, 0.2, 1)
        local fString = self:GetFontString()
        if fString then fString:SetTextColor(1, 0.3, 0.3, 1) end
        if tooltip then
            local tip = sfui.tooltip or _G.GameTooltip
            if tip then
                tip:SetOwner(self, "ANCHOR_RIGHT")
                tip:SetText(tooltip, 1, 0.3, 0.3)
                tip:Show()
            end
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0, 0, 0, 1)
        local fString = self:GetFontString()
        if fString then fString:SetTextColor(1, 1, 1, 1) end
        local tip = sfui.tooltip or _G.GameTooltip
        if tip then tip:Hide() end
    end)
    return btn
end
sfui.common.create_remove_button = sfui.widgets.create_remove_button

function sfui.widgets.create_checkbox(parent, label, dbKeyOrGetter, onClickFunc, tooltip)
    local cb = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
    cb:SetSize(20, 20)

    cb:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    local app = sfui.config.appearance
    cb:SetBackdropColor(app.widgetBackdropColor[1], app.widgetBackdropColor[2], app.widgetBackdropColor[3], app.widgetBackdropColor[4])
    cb:SetBackdropBorderColor(0, 0, 0, 1)

    cb:SetCheckedTexture("Interface/Buttons/WHITE8X8")
    cb:GetCheckedTexture():SetVertexColor(app.highlightColor[1], app.highlightColor[2], app.highlightColor[3], 1)
    cb:GetCheckedTexture():SetPoint("TOPLEFT", 2, -2)
    cb:GetCheckedTexture():SetPoint("BOTTOMRIGHT", -2, 2)

    cb:SetHighlightTexture("Interface/Buttons/WHITE8X8")
    cb:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.1)

    cb.text = cb:CreateFontString(nil, "OVERLAY", sfui.config.font)
    cb.text:SetPoint("LEFT", cb, "RIGHT", 5, 0)
    cb.text:SetText(label)
    cb.label = cb.text

    local function updateChecked()
        if type(dbKeyOrGetter) == "string" then
            if SfuiDB and SfuiDB[dbKeyOrGetter] ~= nil then cb:SetChecked(SfuiDB[dbKeyOrGetter]) end
        elseif type(dbKeyOrGetter) == "function" then
            cb:SetChecked(dbKeyOrGetter())
        end
    end

    cb:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        if type(dbKeyOrGetter) == "string" and SfuiDB then SfuiDB[dbKeyOrGetter] = checked end
        if onClickFunc then onClickFunc(checked) end
    end)
    cb:SetScript("OnShow", updateChecked)
    updateChecked()

    if tooltip then
        cb:SetScript("OnEnter", function(self)
            local tip = sfui.tooltip or _G.GameTooltip
            if tip then
                tip:SetOwner(self, "ANCHOR_RIGHT")
                tip:SetText(tooltip)
                tip:Show()
            end
        end)
        cb:SetScript("OnLeave", function(self)
            local tip = sfui.tooltip or _G.GameTooltip
            if tip then tip:Hide() end
        end)
    end
    return cb
end
sfui.common.create_checkbox = sfui.widgets.create_checkbox

function sfui.widgets.create_cvar_checkbox(parent, label, cvar, tooltip)
    return sfui.widgets.create_checkbox(parent, label, function()
        return (GetCVar and GetCVar(cvar) == "1") or (C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(cvar) == "1")
    end, function(checked)
        local setCVar = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
        if setCVar then setCVar(cvar, checked and "1" or "0") end
        if SfuiDB then SfuiDB[cvar] = checked end
    end, tooltip)
end
sfui.common.create_cvar_checkbox = sfui.widgets.create_cvar_checkbox

function sfui.widgets.create_color_swatch(parent, initialColor, onSetFunc)
    local swatch = CreateFrame("Button", nil, parent, "BackdropTemplate")
    swatch:SetSize(16, 16)
    swatch:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    swatch:SetBackdropBorderColor(0, 0, 0, 1)

    local app = sfui.config.appearance
    if initialColor then
        local r = initialColor.r or initialColor[1] or app.highlightColor[1]
        local g = initialColor.g or initialColor[2] or app.highlightColor[2]
        local b = initialColor.b or initialColor[3] or app.highlightColor[3]
        swatch:SetBackdropColor(r, g, b, 1)
    else
        swatch:SetBackdropColor(app.highlightColor[1], app.highlightColor[2], app.highlightColor[3], 1)
    end

    swatch:SetScript("OnClick", function()
        local r, g, b = swatch:GetBackdropColor()
        if ColorPickerFrame then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = r, g = g, b = b,
                swatchFunc = function()
                    local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                    swatch:SetBackdropColor(nr, ng, nb, 1)
                    if onSetFunc then onSetFunc(nr, ng, nb) end
                end,
                cancelFunc = function()
                    swatch:SetBackdropColor(r, g, b, 1)
                    if onSetFunc then onSetFunc(r, g, b) end
                end,
            })
        end
    end)
    return swatch
end
sfui.common.create_color_swatch = sfui.widgets.create_color_swatch

function sfui.widgets.create_slider_input(parent, label, dbKeyOrGetter, minVal, maxVal, step, onValueChangedFunc, tooltip, width)
    local container = CreateFrame("Frame", nil, parent)
    local w = 160
    if type(width) == "number" then
        w = width
    elseif type(tooltip) == "number" then
        w = tooltip
        tooltip = nil
    end

    container:SetSize(w, 40)

    if tooltip then
        container:SetScript("OnEnter", function(self)
            local tip = sfui.tooltip or _G.GameTooltip
            if tip then
                tip:SetOwner(self, "ANCHOR_RIGHT")
                tip:SetText(tooltip)
                tip:Show()
            end
        end)
        container:SetScript("OnLeave", function(self)
            local tip = sfui.tooltip or _G.GameTooltip
            if tip then tip:Hide() end
        end)
    end

    local title = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText(label)
    title:SetTextColor(1, 1, 1, 0.8)

    local slider = CreateFrame("Slider", nil, container, "BackdropTemplate")
    slider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    slider:SetSize(w - 60, 10)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    slider:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    local app = sfui.config.appearance
    slider:SetBackdropColor(app.sliderBackdropColor[1], app.sliderBackdropColor[2], app.sliderBackdropColor[3], app.sliderBackdropColor[4])
    slider:SetBackdropBorderColor(0, 0, 0, 1)

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(6, 12)
    thumb:SetColorTexture(app.highlightColor[1], app.highlightColor[2], app.highlightColor[3], 1)
    slider:SetThumbTexture(thumb)

    local editbox = CreateFrame("EditBox", nil, container, "BackdropTemplate")
    editbox:SetSize(45, 16)
    editbox:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    editbox:SetAutoFocus(false)
    editbox:SetFontObject("GameFontHighlightSmall")
    editbox:SetJustifyH("CENTER")
    editbox:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    editbox:SetBackdropColor(app.editBoxColor[1], app.editBoxColor[2], app.editBoxColor[3], app.editBoxColor[4])
    editbox:SetBackdropBorderColor(0, 0, 0, 1)

    editbox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editbox:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then
            if val < minVal then val = minVal end
            if val > maxVal then val = maxVal end
            slider:SetValue(val)
            if type(dbKeyOrGetter) == "string" and SfuiDB then SfuiDB[dbKeyOrGetter] = val end
            if onValueChangedFunc then onValueChangedFunc(val) end
        end
        self:ClearFocus()
    end)
    editbox:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(app.highlightColor[1], app.highlightColor[2], app.highlightColor[3], 1)
    end)
    editbox:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(0, 0, 0, 1)
    end)

    local lastUpdate = 0
    local throttle = 0.05

    slider:SetScript("OnValueChanged", function(self, value)
        local stepped = math.floor((value - minVal) / step + 0.5) * step + minVal
        if type(dbKeyOrGetter) == "string" and SfuiDB then SfuiDB[dbKeyOrGetter] = stepped end
        local displayVal = math.floor(stepped * 100) / 100
        editbox:SetText(tostring(displayVal))

        local now = GetTime()
        if now - lastUpdate > throttle then
            lastUpdate = now
            if onValueChangedFunc then onValueChangedFunc(stepped) end
        end
    end)

    slider:SetScript("OnMouseUp", function(self)
        local value = self:GetValue()
        local stepped = math.floor((value - minVal) / step + 0.5) * step + minVal
        if type(dbKeyOrGetter) == "string" and SfuiDB then SfuiDB[dbKeyOrGetter] = stepped end
        if onValueChangedFunc then onValueChangedFunc(stepped) end
        lastUpdate = GetTime()
    end)

    container.slider = slider
    container.editbox = editbox
    container.label = title

    slider:SetScript("OnShow", function(self)
        local val
        if type(dbKeyOrGetter) == "string" and SfuiDB then
            val = SfuiDB[dbKeyOrGetter]
        elseif type(dbKeyOrGetter) == "function" then
            val = dbKeyOrGetter()
        end
        if val == nil then val = minVal end
        self:SetValue(val)
        editbox:SetText(tostring(math.floor(val * 100) / 100))
    end)

    local initVal
    if type(dbKeyOrGetter) == "string" and SfuiDB then
        initVal = SfuiDB[dbKeyOrGetter]
    elseif type(dbKeyOrGetter) == "function" then
        initVal = dbKeyOrGetter()
    end
    if initVal == nil then initVal = minVal end
    slider:SetValue(initVal)
    editbox:SetText(tostring(math.floor(initVal * 100) / 100))

    function container:SetSliderValue(val)
        slider:SetValue(val)
        editbox:SetText(tostring(val))
    end

    return container
end
sfui.common.create_slider_input = sfui.widgets.create_slider_input

function sfui.widgets.create_font_string(parent, font, point, x, y, colorName)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    if point then
        fs:SetPoint(point, x or 0, y or 0)
    end
    if colorName and sfui.common and sfui.common.set_color then
        sfui.common.set_color(fs, colorName)
    end
    return fs
end
sfui.common.create_font_string = sfui.widgets.create_font_string

function sfui.widgets.create_label(parent, text, font, r, g, b)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    label:SetText(text)
    if r and g and b then
        label:SetTextColor(r, g, b)
    else
        label:SetTextColor(1, 1, 1)
    end
    label:SetShadowOffset(0, 0)
    return label
end
sfui.common.create_label = sfui.widgets.create_label

function sfui.widgets.style_scrollbar(scrollBar)
    if not scrollBar then return end
    local name = scrollBar.GetName and scrollBar:GetName()
    local upBtn = (name and _G[name .. "ScrollUpButton"]) or scrollBar.ScrollUpButton
    local downBtn = (name and _G[name .. "ScrollDownButton"]) or scrollBar.ScrollDownButton

    if upBtn and upBtn.Hide then
        upBtn:Hide()
        upBtn:SetAlpha(0)
        upBtn:EnableMouse(false)
    end
    if downBtn and downBtn.Hide then
        downBtn:Hide()
        downBtn:SetAlpha(0)
        downBtn:EnableMouse(false)
    end
    if scrollBar.Track and scrollBar.Track.Hide then
        scrollBar.Track:Hide()
    end
    if scrollBar.GetNumRegions then
        for i = 1, scrollBar:GetNumRegions() do
            local region = select(i, scrollBar:GetRegions())
            if region and region:IsObjectType("Texture") and region ~= scrollBar:GetThumbTexture() then
                region:SetTexture(nil)
            end
        end
    end
    scrollBar:SetWidth(6)
    if not scrollBar.SetBackdrop and BackdropTemplateMixin then
        Mixin(scrollBar, BackdropTemplateMixin)
    end
    if scrollBar.SetBackdrop then
        scrollBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        scrollBar:SetBackdropColor(0, 0, 0, 0.3)
    end
    local thumb = scrollBar:GetThumbTexture()
    if not thumb and scrollBar.CreateTexture then
        thumb = scrollBar:CreateTexture(nil, "ARTWORK")
        scrollBar:SetThumbTexture(thumb)
    end
    if thumb then
        thumb:SetSize(6, 30)
        thumb:SetColorTexture(1, 1, 1, 0.75)
    end
    local parent = scrollBar:GetParent()
    if parent and scrollBar.ClearAllPoints then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, -2)
        scrollBar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -2, 2)
    end
end
sfui.common.style_scrollbar = sfui.widgets.style_scrollbar

function sfui.widgets.create_scroll_frame(parent, name, childWidth, childHeight)
    local sf = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    sf:EnableMouseWheel(true)
    if sf.ScrollBar and sfui.widgets.style_scrollbar then
        sfui.widgets.style_scrollbar(sf.ScrollBar)
    end

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetSize(childWidth or 1, childHeight or 1)
    sf:SetScrollChild(sc)
    sf.scrollChild = sc

    return sf, sc
end
sfui.common.create_scroll_frame = sfui.widgets.create_scroll_frame

local activeDropdown = nil

-- Global hook on CloseDropDownMenus to dismiss custom dropdown menus
if not sfui._dropdownCloseHooked and hooksecurefunc then
    sfui._dropdownCloseHooked = true
    hooksecurefunc("CloseDropDownMenus", function()
        if activeDropdown then
            activeDropdown:Hide()
            activeDropdown = nil
        end
    end)
end

function sfui.widgets.create_dropdown(parent, width, options, onSelectFunc, initialValue, fixedText, menuWidth)
    local actualOptions = (type(options) == "function") and options() or options or {}
    local initialText = fixedText or "Select..."
    local currentValue = initialValue
    if not fixedText then
        if initialValue ~= nil then
            for _, opt in ipairs(actualOptions) do
                if opt.value == initialValue or opt.text == initialValue then
                    initialText = opt.text or opt.label or tostring(initialValue)
                    currentValue = opt.value
                    break
                end
            end
        elseif #actualOptions > 0 and actualOptions[1].text then
            initialText = actualOptions[1].text
            currentValue = actualOptions[1].value
        end
    end

    local btn = sfui.widgets.create_flat_button(parent, initialText, width or 120, 20)

    -- Fullscreen catcher to dismiss dropdown on any click outside
    if not sfui._dropdownCatcher then
        local catcher = CreateFrame("Button", "sfui_DropdownCatcher", UIParent)
        catcher:SetFrameStrata("TOOLTIP")
        catcher:SetFrameLevel(90)
        catcher:SetAllPoints(UIParent)
        catcher:EnableMouse(true)
        catcher:RegisterForClicks("AnyUp", "AnyDown")
        catcher:SetScript("OnClick", function()
            if activeDropdown then
                activeDropdown:Hide()
                activeDropdown = nil
            end
            catcher:Hide()
        end)
        catcher:Hide()
        sfui._dropdownCatcher = catcher
    end

    -- Float on UIParent with high strata so it is never clipped by parent dialogs/scrollframes
    local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu:SetFrameStrata("TOOLTIP")
    menu:SetFrameLevel(100)
    menu:EnableMouse(true)
    menu:SetClampedToScreen(true)
    menu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    menu:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    menu:SetBackdropBorderColor(0, 0, 0, 1)
    menu:Hide()

    menu:SetScript("OnHide", function()
        if activeDropdown == menu then
            activeDropdown = nil
        end
        if sfui._dropdownCatcher and sfui._dropdownCatcher:IsShown() then
            sfui._dropdownCatcher:Hide()
        end
    end)

    btn.menu = menu
    menu.dropdownButton = btn
    menu.buttons = {}
    menu.scrollOffset = 0

    local MAX_VISIBLE_ROWS = 14
    local ROW_HEIGHT = 20
    local PADDING = 4

    local function updateMenuSizeAndPosition()
        local currentOptions = (type(options) == "function") and options() or options or {}
        local numOptions = #currentOptions
        local maxW = menuWidth or (width and width > 40 and width) or 120

        if not menuWidth then
            for _, opt in ipairs(currentOptions) do
                local txt = opt.text or opt.label
                if txt then
                    local textWidth = #txt * 8 + 24
                    if textWidth > maxW then maxW = textWidth end
                end
            end
        end

        local visibleCount = math.min(numOptions, MAX_VISIBLE_ROWS)
        local totalH = PADDING + (visibleCount * ROW_HEIGHT) + PADDING
        menu:SetSize(maxW, math.max(totalH, 24))

        menu:ClearAllPoints()
        local screenW = UIParent:GetWidth() or 1000
        local btnRight = btn:GetRight() or 0
        local btnBottom = btn:GetBottom() or 0

        local point = "TOPLEFT"
        local relPoint = "BOTTOMLEFT"
        local yOffset = -2

        if btnBottom < (totalH + 10) then
            point = "BOTTOMLEFT"
            relPoint = "TOPLEFT"
            yOffset = 2
        end

        local xOffset = 0
        if (width and width <= 40) or (btnRight + maxW > screenW - 20) or (btnRight > screenW * 0.6) then
            if point == "TOPLEFT" then
                point = "TOPRIGHT"
                relPoint = "BOTTOMRIGHT"
            else
                point = "BOTTOMRIGHT"
                relPoint = "TOPRIGHT"
            end
        end

        menu:SetPoint(point, btn, relPoint, xOffset, yOffset)
    end

    local function fillOptions()
        local currentOptions = (type(options) == "function") and options() or options or {}
        local numOptions = #currentOptions
        local visibleCount = math.min(numOptions, MAX_VISIBLE_ROWS)
        local maxOffset = math.max(0, numOptions - visibleCount)

        if menu.scrollOffset > maxOffset then
            menu.scrollOffset = maxOffset
        end
        if menu.scrollOffset < 0 then
            menu.scrollOffset = 0
        end

        local hasScroll = numOptions > visibleCount
        local menuW = menu:GetWidth()
        if not menuW or menuW < 20 then
            menuW = menuWidth or (width and width > 40 and width) or 120
        end
        local btnWidth = menuW - (hasScroll and 12 or 8)

        -- Hide all existing buttons and clear sub-button states
        for _, b in ipairs(menu.buttons) do
            b:Hide()
            if b.xBtn then
                b.xBtn:Hide()
                b.xBtn:ClearAllPoints()
            end
            if b.hBtn then
                b.hBtn:Hide()
                b.hBtn:ClearAllPoints()
            end
        end

        local y = -PADDING
        for i = 1, visibleCount do
            local optIndex = menu.scrollOffset + i
            local opt = currentOptions[optIndex]
            if not opt then break end

            local optBtn = menu.buttons[i]
            if not optBtn then
                optBtn = CreateFrame("Button", nil, menu)
                optBtn:SetNormalFontObject("GameFontHighlightSmall")

                local ts = optBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                ts:SetPoint("LEFT", optBtn, "LEFT", 4, 0)
                ts:SetPoint("RIGHT", optBtn, "RIGHT", -4, 0)
                ts:SetJustifyH("LEFT")
                optBtn.textString = ts

                optBtn:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
                optBtn:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.1)

                menu.buttons[i] = optBtn
            end

            optBtn:SetSize(btnWidth, ROW_HEIGHT)
            optBtn:ClearAllPoints()
            optBtn:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, y)
            optBtn:SetFrameLevel(menu:GetFrameLevel() + 5)
            optBtn:RegisterForClicks("LeftButtonUp", "LeftButtonDown")

            local displayText = opt.text or opt.label or tostring(opt.value or "")

            if opt.onRender then
                optBtn.textString:ClearAllPoints()
                optBtn.textString:SetPoint("LEFT", optBtn, "LEFT", 4, 0)
                optBtn.textString:SetPoint("RIGHT", optBtn, "RIGHT", -46, 0)
                optBtn.textString:SetJustifyH("LEFT")
                optBtn.textString:SetText(displayText)
                optBtn.textString:Show()

                optBtn:SetScript("OnEnter", nil)
                optBtn:SetScript("OnLeave", nil)
                optBtn:SetScript("OnClick", function(self, button, down)
                    if button and button ~= "LeftButton" then return end
                    if down then return end

                    if opt.onClick then
                        pcall(opt.onClick, opt)
                    end
                    if onSelectFunc and opt.value ~= nil then
                        currentValue = opt.value
                        if not fixedText then
                            btn:SetText(displayText)
                            local btnFs = btn:GetFontString()
                            if btnFs then btnFs:SetText(displayText) end
                        end
                        local ok, err = pcall(onSelectFunc, opt.value)
                        if not ok then
                            print("|cffff0000[SFUI Dropdown Error]|r", err)
                        end
                    end
                    if not opt.keepOpen then
                        menu:Hide()
                        activeDropdown = nil
                    else
                        fillOptions()
                    end
                end)

                opt.onRender(optBtn, opt)
            else
                optBtn.textString:ClearAllPoints()
                optBtn.textString:SetPoint("LEFT", optBtn, "LEFT", 4, 0)
                optBtn.textString:SetPoint("RIGHT", optBtn, "RIGHT", -4, 0)
                optBtn.textString:SetJustifyH("LEFT")
                optBtn.textString:SetText(displayText)

                local isSelected = (currentValue ~= nil and opt.value ~= nil and opt.value == currentValue)
                if isSelected then
                    optBtn.textString:SetTextColor(0.3, 0.8, 1)
                else
                    optBtn.textString:SetTextColor(1, 1, 1)
                end
                optBtn.textString:Show()

                optBtn:SetScript("OnEnter", function(self)
                    if self.textString then self.textString:SetTextColor(1, 0.82, 0) end
                end)
                optBtn:SetScript("OnLeave", function(self)
                    if self.textString then
                        if isSelected then
                            self.textString:SetTextColor(0.3, 0.8, 1)
                        else
                            self.textString:SetTextColor(1, 1, 1)
                        end
                    end
                end)

                optBtn:SetScript("OnClick", function(self, button, down)
                    if button and button ~= "LeftButton" then return end
                    if down then return end

                    currentValue = opt.value
                    if not fixedText then
                        btn:SetText(displayText)
                        local btnFs = btn:GetFontString()
                        if btnFs then btnFs:SetText(displayText) end
                    end
                    if onSelectFunc then
                        local ok, err = pcall(onSelectFunc, opt.value)
                        if not ok then
                            print("|cffff0000[SFUI Dropdown Error]|r", err)
                        end
                    end
                    if not opt.keepOpen then
                        menu:Hide()
                        activeDropdown = nil
                    else
                        fillOptions()
                    end
                end)
            end

            -- Forward mouse wheel on buttons so scrolling while hovering over items works smoothly
            optBtn:EnableMouseWheel(true)
            optBtn:SetScript("OnMouseWheel", function(self, delta)
                if not hasScroll then return end
                if delta > 0 then
                    menu.scrollOffset = math.max(0, menu.scrollOffset - 2)
                else
                    menu.scrollOffset = math.min(maxOffset, menu.scrollOffset + 2)
                end
                fillOptions()
            end)

            optBtn:Show()
            y = y - ROW_HEIGHT
        end

        -- Update scrollbar track & thumb
        if hasScroll then
            if not menu.scrollBar then
                local bar = CreateFrame("Frame", nil, menu, "BackdropTemplate")
                bar:SetWidth(4)
                bar:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -2, -PADDING)
                bar:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -2, PADDING)
                bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
                bar:SetBackdropColor(0.2, 0.2, 0.2, 0.5)

                local thumb = bar:CreateTexture(nil, "OVERLAY")
                thumb:SetColorTexture(0.5, 0.5, 0.5, 0.8)
                bar.thumb = thumb
                menu.scrollBar = bar
            end

            menu.scrollBar:Show()
            local trackH = (visibleCount * ROW_HEIGHT)
            local thumbH = math.max(12, math.floor(trackH * (visibleCount / numOptions)))
            local thumbY = -(trackH - thumbH) * (menu.scrollOffset / maxOffset)
            menu.scrollBar.thumb:ClearAllPoints()
            menu.scrollBar.thumb:SetPoint("TOPLEFT", menu.scrollBar, "TOPLEFT", 0, thumbY)
            menu.scrollBar.thumb:SetSize(4, thumbH)
        else
            if menu.scrollBar then
                menu.scrollBar:Hide()
            end
        end
    end

    menu:EnableMouseWheel(true)
    menu:SetScript("OnMouseWheel", function(self, delta)
        local curOpts = (type(options) == "function") and options() or options or {}
        local num = #curOpts
        local vis = math.min(num, MAX_VISIBLE_ROWS)
        local maxOff = math.max(0, num - vis)
        if maxOff <= 0 then return end

        if delta > 0 then
            menu.scrollOffset = math.max(0, (menu.scrollOffset or 0) - 2)
        else
            menu.scrollOffset = math.min(maxOff, (menu.scrollOffset or 0) + 2)
        end
        fillOptions()
    end)

    btn:SetScript("OnClick", function()
        if menu:IsShown() then
            menu:Hide()
            activeDropdown = nil
            if sfui._dropdownCatcher then sfui._dropdownCatcher:Hide() end
        else
            if activeDropdown and activeDropdown ~= menu then
                activeDropdown:Hide()
            end
            local curOpts = (type(options) == "function") and options() or options or {}
            local num = #curOpts
            local vis = math.min(num, MAX_VISIBLE_ROWS)
            local maxOff = math.max(0, num - vis)
            -- Position scroll so current value is in view
            local selIdx = nil
            for idx, opt in ipairs(curOpts) do
                if opt.value == currentValue or (currentValue and (opt.text == currentValue or opt.label == currentValue)) then
                    selIdx = idx
                    break
                end
            end
            if selIdx and selIdx > vis then
                menu.scrollOffset = math.min(maxOff, selIdx - math.floor(vis / 2))
            else
                menu.scrollOffset = 0
            end

            updateMenuSizeAndPosition()
            menu:Show()
            if sfui._dropdownCatcher then
                sfui._dropdownCatcher:SetFrameLevel(math.max(1, menu:GetFrameLevel() - 1))
                sfui._dropdownCatcher:Show()
            end
            fillOptions()
            activeDropdown = menu
        end
    end)

    function btn:SetSelectedValue(val)
        currentValue = val
        local opts = (type(options) == "function") and options() or options or {}
        local found = false
        for _, opt in ipairs(opts) do
            if opt.value == val or opt.text == val or opt.label == val then
                currentValue = opt.value
                if not fixedText then
                    local text = opt.text or opt.label or tostring(val)
                    btn:SetText(text)
                    local fs = btn:GetFontString()
                    if fs then fs:SetText(text) end
                end
                found = true
                break
            end
        end
        if not found and not fixedText and val ~= nil then
            btn:SetText(tostring(val))
            local fs = btn:GetFontString()
            if fs then fs:SetText(tostring(val)) end
        end
    end

    -- Auto-dismiss floating menu when button or parent frame hides
    btn:HookScript("OnHide", function()
        if menu:IsShown() then
            menu:Hide()
            if activeDropdown == menu then activeDropdown = nil end
        end
    end)

    if parent and parent.HookScript then
        parent:HookScript("OnHide", function()
            if menu:IsShown() then
                menu:Hide()
                if activeDropdown == menu then activeDropdown = nil end
            end
        end)
    end

    return btn
end
sfui.common.create_dropdown = sfui.widgets.create_dropdown
