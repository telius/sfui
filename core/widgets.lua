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
    panel:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
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
            edgeFile = "",
            tile = false,
            tileSize = 0,
            edgeSize = 0,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        })
        frame.borderBackdrop:SetBackdropColor(0, 0, 0, 1)
    end
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
    if not texturePath or texturePath == "" then
        texturePath = (sfui.config and sfui.config.barTexture) or "Interface/Buttons/WHITE8X8"
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

    local mult = sfui.pixelScale or 1
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = mult,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    btn:SetBackdropColor(0, 0, 0, 1)
    local gray = (sfui.config and sfui.config.colors and sfui.config.colors.gray) or { 0.5, 0.5, 0.5 }
    btn:SetBackdropBorderColor(gray[1], gray[2], gray[3], 1)

    btn:SetNormalFontObject("GameFontHighlightSmall")
    btn:SetText(text)
    local fs = btn:GetFontString()
    local white = (sfui.config and sfui.config.colors and sfui.config.colors.white) or { 1, 1, 1 }
    if fs then fs:SetTextColor(white[1], white[2], white[3], 1) end

    btn:SetScript("OnEnter", function(self)
        local purple = (sfui.config and sfui.config.colors and sfui.config.colors.purple) or { 0.4, 0, 1 }
        self:SetBackdropBorderColor(purple[1], purple[2], purple[3], 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(gray[1], gray[2], gray[3], 1)
    end)

    return btn
end
sfui.common.create_flat_button = sfui.widgets.create_flat_button

function sfui.widgets.create_styled_button(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 120, height or 25)
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

    btn.text = btn:CreateFontString(nil, "OVERLAY", sfui.config and sfui.config.font or "GameFontNormal")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(text or "")
    sfui.widgets.style_text(btn.text)

    return btn
end
sfui.common.create_styled_button = sfui.widgets.create_styled_button

function sfui.widgets.create_close_button(parent, onClickFunc, size)
    size = size or 20
    local btn = sfui.widgets.create_flat_button(parent, "✕", size, size)
    btn:SetPoint("TOPRIGHT", -6, -6)
    btn:SetScript("OnClick", onClickFunc or function()
        if parent and parent.Hide then parent:Hide() end
    end)
    return btn
end
sfui.common.create_close_button = sfui.widgets.create_close_button

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

    local app = sfui.config.appearance
    slider:SetBackdropColor(app.sliderBackdropColor[1], app.sliderBackdropColor[2], app.sliderBackdropColor[3], app.sliderBackdropColor[4])
    slider:SetBackdropBorderColor(0, 0, 0, 1)

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(6, 10)
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

local activeDropdown = nil
function sfui.widgets.create_dropdown(parent, width, options, onSelectFunc, initialValue, fixedText, menuWidth)
    local actualOptions = (type(options) == "function") and options() or options
    local initialText = fixedText or "Select..."
    if not fixedText and initialValue ~= nil then
        for _, opt in ipairs(actualOptions) do
            if opt.value == initialValue then
                initialText = opt.text
                break
            end
        end
    end

    local btn = sfui.widgets.create_flat_button(parent, initialText, width or 120, 20)
    local menu = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    menu:SetWidth(menuWidth or width or 120)
    menu:SetFrameStrata("DIALOG")
    menu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    menu:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    menu:SetBackdropBorderColor(0, 0, 0, 1)
    menu:Hide()

    local optionButtons = {}
    local function updateMenuSize()
        local opts = (type(options) == "function") and options() or options
        menu:SetHeight(#opts * 20 + 4)
    end

    local function fillOptions()
        local opts = (type(options) == "function") and options() or options
        for _, b in ipairs(optionButtons) do b:Hide() end
        local y = -2
        for i, opt in ipairs(opts) do
            local optBtn = optionButtons[i]
            if not optBtn then
                optBtn = CreateFrame("Button", nil, menu)
                optBtn:SetHeight(20)
                optBtn:SetPoint("LEFT", menu, "LEFT", 2, 0)
                optBtn:SetPoint("RIGHT", menu, "RIGHT", -2, 0)
                optBtn:SetNormalFontObject("GameFontHighlightSmall")
                local fs = optBtn:GetFontString()
                if fs then
                    fs:ClearAllPoints()
                    fs:SetPoint("LEFT", optBtn, "LEFT", 4, 0)
                    fs:SetPoint("RIGHT", optBtn, "RIGHT", -4, 0)
                    fs:SetJustifyH("LEFT")
                end
                optBtn:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
                optBtn:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.1)
                optionButtons[i] = optBtn
            end
            optBtn:SetPoint("TOP", menu, "TOP", 0, y)
            optBtn:SetText(opt.text)

            optBtn:SetScript("OnClick", function()
                if not fixedText then
                    btn:GetFontString():SetText(opt.text)
                end
                if onSelectFunc then onSelectFunc(opt.value) end
                if not opt.keepOpen then
                    menu:Hide()
                    activeDropdown = nil
                end
            end)
            optBtn:Show()
            y = y - 20
        end
    end

    btn:SetScript("OnClick", function()
        if menu:IsShown() then
            menu:Hide()
            activeDropdown = nil
        else
            if activeDropdown then activeDropdown:Hide() end
            updateMenuSize()
            fillOptions()
            menu:Show()
            activeDropdown = menu
        end
    end)

    return btn
end
sfui.common.create_dropdown = sfui.widgets.create_dropdown
