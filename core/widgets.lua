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
function sfui.widgets.resolve_statusbar_texture(name)
    if not name or name == "" then
        return (sfui.config and sfui.config.barTexture) or "Interface/Buttons/WHITE8X8"
    end
    if type(name) == "number" then
        return name
    end
    local LSM = _G.LibStub and _G.LibStub("LibSharedMedia-3.0", true)
    local path
    if LSM then
        path = LSM:Fetch("statusbar", name, true)
    end
    if not path and sfui.config and sfui.config.blizzard_bar_textures then
        path = sfui.config.blizzard_bar_textures[name]
        if not path and type(name) == "string" then
            local norm = name:gsub("\\", "/"):lower()
            for k, v in pairs(sfui.config.blizzard_bar_textures) do
                if k:lower() == norm or v:gsub("\\", "/"):lower() == norm then
                    path = v
                    break
                end
            end
        end
    end
    if not path and type(name) == "string" then
        if name:find("^[iI]nterface[/\\]") then
            path = name
        elseif _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo(name) then
            path = name
        end
    end
    return path or (sfui.config and sfui.config.barTexture) or "Interface/Buttons/WHITE8X8"
end
sfui.common.resolve_statusbar_texture = sfui.widgets.resolve_statusbar_texture

function sfui.widgets.get_bar_texture(textureName)
    local name = textureName or (SfuiDB and SfuiDB.barTexture)
    local path = sfui.widgets.resolve_statusbar_texture(name)
    sfui.config.barTexture = path
    return path
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

    sfui.theme.ApplyButtonStyle(btn, false)
    sfui.theme.RegisterButton(btn, false)

    return btn
end
sfui.common.create_flat_button = sfui.widgets.create_flat_button

function sfui.widgets.create_submenu_button(parent, text, width, height)
    local btn = sfui.widgets.create_flat_button(parent, text or "", width or 18, height or 16)
    btn.isSubmenuButton = true
    btn.lockColor = true
    btn:SetFrameLevel((parent:GetFrameLevel() or 1) + 10)
    btn:RegisterForClicks("AnyUp")
    local fs = btn:GetFontString()
    if fs then
        local fontFile = (sfui.config and sfui.config.fontFile) or "Fonts\\FRIZQT__.TTF"
        fs:SetFont(fontFile, 10, "")
    end
    return btn
end
sfui.common.create_submenu_button = sfui.widgets.create_submenu_button

function sfui.widgets.create_styled_button(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 120, height or 25)

    btn.text = btn:CreateFontString(nil, "OVERLAY", sfui.config and sfui.config.font or "GameFontNormal")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(text or "")
    sfui.widgets.style_text(btn.text)

    sfui.theme.ApplyButtonStyle(btn, true)
    sfui.theme.RegisterButton(btn, true)

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

    sfui.theme.ApplyCloseButtonStyle(btn)
    sfui.theme.RegisterCloseButton(btn)

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
        if sfui.common and sfui.common.set_cvar then
            sfui.common.set_cvar(cvar, checked and "1" or "0")
        elseif (not InCombatLockdown or not InCombatLockdown()) then
            local setCVar = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
            if setCVar then setCVar(cvar, checked and "1" or "0") end
        end
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

    local function readValue()
        local val
        if type(dbKeyOrGetter) == "string" and SfuiDB then
            val = SfuiDB[dbKeyOrGetter]
        elseif type(dbKeyOrGetter) == "function" then
            val = dbKeyOrGetter()
        end
        return (val ~= nil) and val or minVal
    end

    local function syncValue()
        local val = readValue()
        slider:SetValue(val)
        editbox:SetText(tostring(math.floor(val * 100) / 100))
    end

    slider:SetScript("OnShow", syncValue)
    syncValue()

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
    if colorName then
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
    if sfui.theme and sfui.theme.ApplyScrollBarStyle then
        sfui.theme.ApplyScrollBarStyle(scrollBar)
        return
    end

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
    sf.scrollBarHideable = 1
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

-- ─────────────────────────────────────────────────────────────────────────────
--  Dropdown System (Clean & Modern Rebuild)
-- ─────────────────────────────────────────────────────────────────────────────
local activeDropdown = nil

-- Clean up any legacy blocking catcher frames from prior versions
if sfui._dropdownCatcher then
    sfui._dropdownCatcher:Hide()
    sfui._dropdownCatcher:EnableMouse(false)
    sfui._dropdownCatcher = nil
end

-- Hook CloseDropDownMenus so ESC / Blizzard UI closes active dropdown
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
                if opt.value == initialValue or opt.text == initialValue or opt.label == initialValue then
                    initialText = opt.text or opt.label or tostring(initialValue)
                    currentValue = opt.value
                    break
                end
            end
        elseif #actualOptions > 0 and (actualOptions[1].text or actualOptions[1].label) then
            initialText = actualOptions[1].text or actualOptions[1].label
            currentValue = actualOptions[1].value
        end
    end

    local mult = sfui.pixelScale or 1
    local btnH = (width and width <= 24) and width or 20
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn.isDropdownButton = true
    btn:SetSize(width or 120, btnH)
    btn:SetNormalFontObject("GameFontHighlightSmall")
    btn:SetText(initialText)

    local fontFile = (sfui.config and sfui.config.fontFile) or "Fonts\\FRIZQT__.TTF"
    local fs = btn:GetFontString()
    if fs then
        fs:SetFont(fontFile, (width and width <= 24) and 12 or 11, "")
        fs:SetTextColor(1, 1, 1, 1)
    end

    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = mult,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    btn:SetBackdropColor(0, 0, 0, 1)
    btn:SetBackdropBorderColor(0, 0, 0, 1)

    btn:SetScript("OnEnter", function(self)
        if sfui.theme and sfui.theme.IsAuctionHouseButtonActive and sfui.theme.IsAuctionHouseButtonActive() then
            if self._sfuiAHHighlight then self._sfuiAHHighlight:Show() end
            if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0, 0, 0, 0) end
            if self.SetBackdropColor then self:SetBackdropColor(0, 0, 0, 0) end
            local sfs = self:GetFontString()
            if sfs then sfs:SetTextColor(1.0, 1.0, 1.0, 1) end
        elseif self._sfuiCamelotBg and self._sfuiCamelotBg:IsShown() then
            self._sfuiCamelotBg:SetAtlas(self._sfuiAtlasHover or "common-dropdown-c-button-hover-1")
            local sfs = self:GetFontString()
            if sfs then sfs:SetTextColor(1.0, 0.95, 0.70, 1) end
        else
            local purple = (sfui.config and sfui.config.colors and sfui.config.colors.purple) or { 0.4, 0, 1 }
            self:SetBackdropBorderColor(purple[1], purple[2], purple[3], 1)
        end
        if self.tooltip then
            local tip = sfui.tooltip or _G.GameTooltip
            if tip then
                tip:SetOwner(self, "ANCHOR_TOP")
                tip:SetText(self.tooltip, 1, 1, 1)
                tip:Show()
            end
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if sfui.theme and sfui.theme.IsAuctionHouseButtonActive and sfui.theme.IsAuctionHouseButtonActive() then
            if self._sfuiAHHighlight then self._sfuiAHHighlight:Hide() end
            if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0, 0, 0, 0) end
            if self.SetBackdropColor then self:SetBackdropColor(0, 0, 0, 0) end
            local sfs = self:GetFontString()
            if sfs then
                local p = sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()
                local col = (p and (p.accentColor or p.tabNormal)) or { 0.95, 0.85, 0.55, 1 }
                sfs:SetTextColor(col[1], col[2], col[3], 1)
            end
        elseif self._sfuiCamelotBg and self._sfuiCamelotBg:IsShown() then
            if not (self.menu and self.menu:IsShown()) then
                self._sfuiCamelotBg:SetAtlas(self._sfuiAtlasNormal or "common-dropdown-c-button")
                local sfs = self:GetFontString()
                if sfs then
                    local p = sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()
                    local col = (p and p.tabNormal) or { 0.95, 0.85, 0.55, 1 }
                    sfs:SetTextColor(col[1], col[2], col[3], 1)
                end
            end
        else
            if not (self.menu and self.menu:IsShown()) then
                self:SetBackdropBorderColor(0, 0, 0, 1)
            end
        end
        local tip = sfui.tooltip or _G.GameTooltip
        if tip then tip:Hide() end
    end)

    if parent and parent.GetFrameLevel then
        btn:SetFrameLevel(parent:GetFrameLevel() + 20)
    end

    -- Menu Frame: parented to UIParent so it escapes ScrollFrame clipping in option panels
    local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu:SetFrameStrata("TOOLTIP")
    menu:SetFrameLevel(200)
    menu:EnableMouse(true)
    menu:SetClampedToScreen(true)
    menu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = mult,
    })
    menu:SetBackdropColor(0.06, 0.06, 0.06, 0.98)
    menu:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    menu:Hide()

    btn.menu = menu
    menu.dropdownButton = btn
    menu.rows = {}
    menu.scrollOffset = 0

    if sfui.theme and sfui.theme.ApplyDropdownStyle then
        sfui.theme.ApplyDropdownStyle(btn)
        sfui.theme.RegisterDropdown(btn)
    end

    menu:HookScript("OnShow", function()
        if sfui.theme and sfui.theme.ApplyDropdownStyle then
            sfui.theme.ApplyDropdownStyle(btn)
        end
    end)
    menu:HookScript("OnHide", function()
        if sfui.theme and sfui.theme.ApplyDropdownStyle then
            sfui.theme.ApplyDropdownStyle(btn)
        end
    end)

    local MAX_VISIBLE_ROWS = 14
    local ROW_HEIGHT = 20
    local PADDING = 4

    menu:SetScript("OnEvent", function(self, event, mouseButton)
        if event == "GLOBAL_MOUSE_DOWN" and (mouseButton == "LeftButton" or mouseButton == "RightButton") then
            if not self:IsShown() then return end
            C_Timer.After(0.01, function()
                if not self:IsShown() then return end
                if self:IsMouseOver() then return end
                if btn and btn:IsMouseOver() then return end
                if self.rows then
                    for _, r in ipairs(self.rows) do
                        if r:IsShown() and (r:IsMouseOver() or (r.rowBtn and r.rowBtn:IsMouseOver())) then
                            return
                        end
                    end
                end
                if DoesAncestryIncludeAny and GetMouseFoci then
                    local foci = GetMouseFoci()
                    if DoesAncestryIncludeAny(self, foci) then return end
                    if btn and DoesAncestryIncludeAny(btn, foci) then return end
                elseif GetMouseFocus and not GetMouseFoci then
                    local focus = GetMouseFocus()
                    if focus and (focus == self or focus == btn or (focus.IsDescendantOf and (focus:IsDescendantOf(self) or focus:IsDescendantOf(btn)))) then
                        return
                    end
                end
                self:Hide()
                if activeDropdown == self then
                    activeDropdown = nil
                end
            end)
        end
    end)

    menu:SetScript("OnShow", function(self)
        self:RegisterEvent("GLOBAL_MOUSE_DOWN")
        if btn._sfuiCamelotBg and btn._sfuiCamelotBg:IsShown() then
            btn._sfuiCamelotBg:SetAtlas(btn._sfuiAtlasPressed or "common-dropdown-c-button-pressed-1")
        else
            local purple = (sfui.config and sfui.config.colors and sfui.config.colors.purple) or { 0.4, 0, 1 }
            btn:SetBackdropBorderColor(purple[1], purple[2], purple[3], 1)
        end
    end)

    menu:SetScript("OnHide", function(self)
        self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        if activeDropdown == self then
            activeDropdown = nil
        end
        if btn._sfuiCamelotBg and btn._sfuiCamelotBg:IsShown() then
            btn._sfuiCamelotBg:SetAtlas(btn:IsMouseOver() and (btn._sfuiAtlasHover or "common-dropdown-c-button-hover-1") or (btn._sfuiAtlasNormal or "common-dropdown-c-button"))
            local sfs = btn:GetFontString()
            if sfs then
                if btn:IsMouseOver() then
                    sfs:SetTextColor(1.0, 0.95, 0.70, 1.0)
                else
                    local p = sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()
                    local col = (p and p.tabNormal) or { 0.95, 0.85, 0.55, 1 }
                    sfs:SetTextColor(col[1], col[2], col[3], 1)
                end
            end
        else
            if btn and btn.SetBackdropBorderColor then
                btn:SetBackdropBorderColor(0, 0, 0, 1)
            end
        end
    end)

    local function getOptionList()
        if type(options) == "function" then
            return options() or {}
        end
        return options or {}
    end

    local function updateMenuLayout()
        local curOptions = getOptionList()
        local numOptions = #curOptions
        local maxW = menuWidth or (width and width > 40 and width) or 140

        if not menuWidth then
            for _, opt in ipairs(curOptions) do
                local txt = opt.text or opt.label
                if txt then
                    local clean = txt:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                    local textWidth = #clean * 7 + 28
                    if opt.hasDelete then textWidth = textWidth + 24 end
                    if opt.isToggle or opt.checked ~= nil then textWidth = textWidth + 28 end
                    if textWidth > maxW then maxW = textWidth end
                end
            end
        end

        local visibleCount = math.min(numOptions, MAX_VISIBLE_ROWS)
        local totalH = PADDING + (visibleCount * ROW_HEIGHT) + PADDING
        menu:SetSize(maxW, math.max(totalH, 24))

        menu:ClearAllPoints()
        local btnRight = btn:GetRight() or 0
        local btnBottom = btn:GetBottom() or 0
        local screenW = UIParent:GetWidth() or 1000

        local point = "TOPLEFT"
        local relPoint = "BOTTOMLEFT"
        local yOffset = -2

        if btnBottom < (totalH + 20) then
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

    local fillOptions -- forward declaration

    -- Single shared onWheel handler across all rows, buttons, and scrollbar
    local function onWheel(self, delta)
        local curOpts = getOptionList()
        local num = #curOpts
        local vis = math.min(num, MAX_VISIBLE_ROWS)
        local maxOff = math.max(0, num - vis)
        if maxOff <= 0 then return end
        if delta > 0 then
            menu.scrollOffset = math.max(0, menu.scrollOffset - 2)
        else
            menu.scrollOffset = math.min(maxOff, menu.scrollOffset + 2)
        end
        fillOptions()
    end

    local function createRow(index)
        local row = CreateFrame("Frame", nil, menu)
        row:SetHeight(ROW_HEIGHT)

        -- 1. Main row button (Label / Click Area)
        local rowBtn = CreateFrame("Button", nil, row)
        rowBtn:RegisterForClicks("AnyUp")
        rowBtn:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
        rowBtn:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)

        local check = rowBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        check:SetPoint("LEFT", rowBtn, "LEFT", 4, 0)
        check:SetFont(fontFile, 11, "")
        check:SetText("|cffffcc00✓|r")
        check:Hide()

        local label = rowBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", rowBtn, "LEFT", 4, 0)
        label:SetPoint("RIGHT", rowBtn, "RIGHT", -4, 0)
        label:SetFont(fontFile, 11, "")
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)

        row.rowBtn = rowBtn
        row.check = check
        row.label = label
        row.textString = label -- backward compatibility

        -- 2. Delete button [X]
        local delBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
        delBtn:SetSize(18, 16)
        delBtn:RegisterForClicks("AnyUp")
        delBtn:SetNormalFontObject("GameFontHighlightSmall")
        delBtn:SetText("|cffff4444X|r")
        local delFs = delBtn:GetFontString()
        if delFs then delFs:SetFont(fontFile, 10, "") end
        delBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        delBtn:SetBackdropColor(0.12, 0.12, 0.12, 0.95)
        delBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        delBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(1, 0.3, 0.3, 1)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Delete from list", 1, 0.3, 0.3)
                GameTooltip:Show()
            end
        end)
        delBtn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
            if GameTooltip then GameTooltip:Hide() end
        end)
        delBtn:Hide()
        row.delBtn = delBtn
        row.xBtn = delBtn -- backward compatibility

        -- 3. Toggle button [V] / [H]
        local tglBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
        tglBtn:SetSize(22, 16)
        tglBtn:RegisterForClicks("AnyUp")
        tglBtn:SetNormalFontObject("GameFontHighlightSmall")
        local tglFs = tglBtn:GetFontString()
        if tglFs then tglFs:SetFont(fontFile, 10, "") end
        tglBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        tglBtn:SetBackdropColor(0.12, 0.12, 0.12, 0.95)
        tglBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        tglBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Toggle Visibility", 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        tglBtn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
            if GameTooltip then GameTooltip:Hide() end
        end)
        tglBtn:Hide()
        row.tglBtn = tglBtn
        row.hBtn = tglBtn -- backward compatibility

        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", onWheel)
        rowBtn:EnableMouseWheel(true)
        rowBtn:SetScript("OnMouseWheel", onWheel)
        delBtn:EnableMouseWheel(true)
        delBtn:SetScript("OnMouseWheel", onWheel)
        tglBtn:EnableMouseWheel(true)
        tglBtn:SetScript("OnMouseWheel", onWheel)

        menu.rows[index] = row
        return row
    end

    fillOptions = function()
        local curOptions = getOptionList()
        local numOptions = #curOptions
        local visibleCount = math.min(numOptions, MAX_VISIBLE_ROWS)
        local maxOffset = math.max(0, numOptions - visibleCount)

        if menu.scrollOffset > maxOffset then menu.scrollOffset = maxOffset end
        if menu.scrollOffset < 0 then menu.scrollOffset = 0 end

        local hasScroll = numOptions > visibleCount
        local menuW = menu:GetWidth()
        if not menuW or menuW < 20 then
            menuW = menuWidth or (width and width > 40 and width) or 140
        end

        for _, r in ipairs(menu.rows) do
            r:Hide()
            r.delBtn:Hide()
            r.delBtn:SetScript("OnClick", nil)
            r.tglBtn:Hide()
            r.tglBtn:SetScript("OnClick", nil)
            r.check:Hide()
            r.rowBtn:SetScript("OnClick", nil)
        end

        local y = -PADDING
        for i = 1, visibleCount do
            local optIndex = menu.scrollOffset + i
            local opt = curOptions[optIndex]
            if not opt then break end

            local row = menu.rows[i] or createRow(i)
            local rowW = menuW - (hasScroll and 16 or 8)

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, y)
            row:SetSize(rowW, ROW_HEIGHT)
            row:SetFrameLevel(menu:GetFrameLevel() + 5)
            row.rowBtn:SetFrameLevel(row:GetFrameLevel() + 2)
            row.tglBtn:SetFrameLevel(row:GetFrameLevel() + 4)
            row.delBtn:SetFrameLevel(row:GetFrameLevel() + 4)
            row.fillOptions = fillOptions

            local displayText = opt.text or opt.label or tostring(opt.value ~= nil and opt.value or "")

            -- Layout hitboxes with ZERO overlap
            local rightOffset = 0
            if opt.hasDelete then
                row.delBtn:ClearAllPoints()
                row.delBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
                row.delBtn:Show()
                row.delBtn:SetScript("OnClick", function()
                    menu:Hide()
                    if opt.onDelete then
                        opt.onDelete(opt)
                    end
                end)
                rightOffset = rightOffset + 22
            else
                row.delBtn:Hide()
            end

            local isToggle = (opt.isToggle or opt.checked ~= nil)
            if isToggle then
                row.tglBtn:ClearAllPoints()
                if opt.hasDelete then
                    row.tglBtn:SetPoint("RIGHT", row.delBtn, "LEFT", -3, 0)
                else
                    row.tglBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
                end
                row.tglBtn:Show()
                if opt.checked then
                    row.tglBtn:SetText("|cff00ff00V|r")
                else
                    row.tglBtn:SetText("|cffff4444H|r")
                end
                rightOffset = rightOffset + 26
            else
                row.tglBtn:Hide()
            end

            -- rowBtn covers remaining width
            row.rowBtn:ClearAllPoints()
            row.rowBtn:SetPoint("TOPLEFT", row, 0, 0)
            row.rowBtn:SetPoint("BOTTOMRIGHT", row, -rightOffset, 0)

            local isSelected = (currentValue ~= nil and (opt.value == currentValue or opt.text == currentValue or opt.label == currentValue))

            row.label:ClearAllPoints()
            if isSelected and not isToggle then
                row.check:Show()
                row.label:SetPoint("LEFT", row.rowBtn, "LEFT", 16, 0)
                row.label:SetPoint("RIGHT", row.rowBtn, "RIGHT", -4, 0)
                row.label:SetTextColor(1, 0.82, 0)
            else
                row.check:Hide()
                row.label:SetPoint("LEFT", row.rowBtn, "LEFT", 4, 0)
                row.label:SetPoint("RIGHT", row.rowBtn, "RIGHT", -4, 0)
                row.label:SetTextColor(1, 1, 1)
            end
            row.label:SetText(displayText)

            row.rowBtn:SetScript("OnEnter", function()
                if row.label then row.label:SetTextColor(1, 0.82, 0) end
            end)
            row.rowBtn:SetScript("OnLeave", function()
                if row.label then
                    if isSelected and not isToggle then
                        row.label:SetTextColor(1, 0.82, 0)
                    else
                        row.label:SetTextColor(1, 1, 1)
                    end
                end
            end)

            -- Click behavior
            if isToggle then
                local function doToggle()
                    if opt.onToggle then
                        opt.onToggle(opt)
                    elseif opt.onClick then
                        opt.onClick(opt)
                    end
                    fillOptions()
                end
                row.rowBtn:SetScript("OnClick", doToggle)
                row.tglBtn:SetScript("OnClick", doToggle)
            else
                row.rowBtn:SetScript("OnClick", function()
                    local val = opt.value ~= nil and opt.value or (opt.text or opt.label)
                    currentValue = val
                    if not fixedText then
                        btn:SetText(displayText)
                        local btnFs = btn:GetFontString()
                        if btnFs then btnFs:SetText(displayText) end
                    end
                    if opt.onClick then
                        opt.onClick(opt)
                    end
                    if onSelectFunc then
                        local ok, err = pcall(onSelectFunc, val)
                        if not ok then
                            print("|cffff0000[sfui dropdown error]|r", err)
                        end
                    end
                    if not opt.keepOpen then
                        menu:Hide()
                    else
                        fillOptions()
                    end
                end)
            end

            -- Legacy hook for onRender if defined
            if opt.onRender then
                opt.onRender(row, opt)
            end

            row:Show()
            y = y - ROW_HEIGHT
        end

        -- Scrollbar
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

                bar:EnableMouseWheel(true)
                bar:SetScript("OnMouseWheel", onWheel)

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
    menu:SetScript("OnMouseWheel", onWheel)

    btn:SetScript("OnClick", function()
        if menu:IsShown() then
            menu:Hide()
            activeDropdown = nil
        else
            if activeDropdown and activeDropdown ~= menu then
                activeDropdown:Hide()
            end
            if activeTextureMenu and activeTextureMenu:IsShown() then
                activeTextureMenu:Hide()
            end

            local curOpts = getOptionList()
            local num = #curOpts
            local vis = math.min(num, MAX_VISIBLE_ROWS)
            local maxOff = math.max(0, num - vis)

            local selIdx = nil
            for idx, opt in ipairs(curOpts) do
                if opt.value == currentValue or (currentValue ~= nil and (opt.text == currentValue or opt.label == currentValue)) then
                    selIdx = idx
                    break
                end
            end
            if selIdx and selIdx > vis then
                menu.scrollOffset = math.min(maxOff, selIdx - math.floor(vis / 2))
            else
                menu.scrollOffset = 0
            end

            updateMenuLayout()
            menu:Show()
            fillOptions()
            activeDropdown = menu
        end
    end)

    function btn:SetSelectedValue(val)
        currentValue = val
        local opts = getOptionList()
        local found = false
        for _, opt in ipairs(opts) do
            if opt.value == val or opt.text == val or opt.label == val then
                currentValue = opt.value
                if not fixedText then
                    local text = opt.text or opt.label or tostring(val)
                    btn:SetText(text)
                    local btnFs = btn:GetFontString()
                    if btnFs then btnFs:SetText(text) end
                end
                found = true
                break
            end
        end
        if not found and not fixedText and val ~= nil then
            btn:SetText(tostring(val))
            local btnFs = btn:GetFontString()
            if btnFs then btnFs:SetText(tostring(val)) end
        end
    end

    function btn:GetSelectedValue()
        return currentValue
    end

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

-- ─────────────────────────────────────────────────────────────────────────────
--  Texture Selection Dropdown (ElvUI / SharedMedia Style)
-- ─────────────────────────────────────────────────────────────────────────────
local activeTextureMenu = nil
local resolve_statusbar_texture = sfui.widgets.resolve_statusbar_texture


local function get_all_statusbar_textures()
    local list = {}
    local seen = {}
    local LSM = _G.LibStub and _G.LibStub("LibSharedMedia-3.0", true)

    if LSM then
        local lsmList = LSM:List("statusbar")
        if lsmList then
            for _, name in ipairs(lsmList) do
                if not seen[name] then
                    seen[name] = true
                    table.insert(list, name)
                end
            end
        else
            local hash = LSM:HashTable("statusbar")
            if hash then
                for name, _ in pairs(hash) do
                    if not seen[name] then
                        seen[name] = true
                        table.insert(list, name)
                    end
                end
            end
        end
    end

    if sfui.config.blizzard_bar_textures then
        for name, path in pairs(sfui.config.blizzard_bar_textures) do
            if not seen[name] then
                local isAtlas = type(path) == "string" and not path:find("^[iI]nterface[/\\]")
                if not isAtlas or (_G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo(path)) then
                    seen[name] = true
                    table.insert(list, name)
                end
            end
        end
    end

    table.sort(list, function(a, b)
        return string.upper(a) < string.upper(b)
    end)

    return list
end

function sfui.widgets.create_texture_dropdown(parent, width, onSelectFunc, initialValue, labelText)
    width = width or 200
    local ROW_HEIGHT = 20
    local MAX_VISIBLE = 12
    local PADDING = 4
    local SCROLL_WIDTH = 8
    local currentValue = initialValue or "Flat"

    -- Container frame (holds label + dropdown button)
    local container = CreateFrame("Frame", nil, parent)
    local hasLabel = (labelText and labelText ~= "")
    container:SetSize(width, hasLabel and 44 or 22)

    local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
    btn:SetSize(width, 22)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(0.12, 0.12, 0.12, 0.95)
    btn:SetBackdropBorderColor(0, 0, 0, 1)

    if hasLabel then
        local label = container:CreateFontString(nil, "OVERLAY")
        label:SetFontObject(sfui.config and sfui.config.font or "GameFontNormal")
        label:SetTextColor(1, 0.82, 0, 1) -- Golden yellow matching ElvUI
        label:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        label:SetText(labelText)
        container.label = label
        btn:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    else
        btn:SetAllPoints(container)
    end
    container.btn = btn

    -- Texture preview bar on the closed button
    local btnBar = btn:CreateTexture(nil, "BACKGROUND")
    btnBar:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    btnBar:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    btnBar:SetAlpha(0.35)
    btn.bar = btnBar

    -- Selected texture text
    local btnText = btn:CreateFontString(nil, "OVERLAY")
    btnText:SetFontObject("GameFontHighlightSmall")
    local fontPath, fontSize = btnText:GetFont()
    if fontPath then btnText:SetFont(fontPath, fontSize, "OUTLINE") end
    btnText:SetShadowColor(0, 0, 0, 1)
    btnText:SetShadowOffset(1, -1)
    btnText:SetPoint("LEFT", btn, "LEFT", 8, 0)
    btnText:SetPoint("RIGHT", btn, "RIGHT", -22, 0)
    btnText:SetJustifyH("LEFT")
    btnText:SetTextColor(1, 1, 1, 1)
    btn.text = btnText

    -- Down-arrow indicator
    local arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arrow:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    arrow:SetText("|cffffcc00▼|r")
    btn.arrow = arrow

    -- Highlight on hover
    btn:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
    local btnHl = btn:GetHighlightTexture()
    btnHl:SetVertexColor(1, 1, 1, 0.15)

    local function setTexturePreview(tex, path)
        if not tex then return end
        if type(path) == "string" and _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo(path) then
            tex:SetAtlas(path, false)
        else
            tex:SetTexCoord(0, 1, 0, 1)
            tex:SetTexture(path)
        end
    end

    local function updateButtonDisplay(val)
        currentValue = val
        btnText:SetText(tostring(val or "Flat"))
        local path = resolve_statusbar_texture(val)
        setTexturePreview(btnBar, path)
    end
    updateButtonDisplay(currentValue)

    -- Floating dropdown menu frame
    local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu:SetFrameStrata("TOOLTIP")
    menu:SetFrameLevel(250)
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    menu:SetBackdropColor(0.10, 0.10, 0.10, 0.98)
    menu:SetBackdropBorderColor(0, 0, 0, 1)
    menu:Hide()

    menu:SetScript("OnEvent", function(self, event, mouseButton)
        if event == "GLOBAL_MOUSE_DOWN" then
            if mouseButton == "LeftButton" or mouseButton == "RightButton" then
                if not self:IsShown() then return end
                C_Timer.After(0.01, function()
                    if not self:IsShown() then return end
                    if self:IsMouseOver() then return end
                    if btn and btn:IsMouseOver() then return end
                    if DoesAncestryIncludeAny and GetMouseFoci then
                        local foci = GetMouseFoci()
                        if DoesAncestryIncludeAny(self, foci) then return end
                        if btn and DoesAncestryIncludeAny(btn, foci) then return end
                    end
                    self:Hide()
                    if activeTextureMenu == self then
                        activeTextureMenu = nil
                    end
                end)
            end
        end
    end)

    menu:SetScript("OnShow", function(self)
        self:RegisterEvent("GLOBAL_MOUSE_DOWN")
    end)

    menu.scrollOffset = 0
    menu.rows = {}

    -- Scrollbar track
    local scrollbar = CreateFrame("Frame", nil, menu, "BackdropTemplate")
    scrollbar:SetWidth(SCROLL_WIDTH)
    scrollbar:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -3, -PADDING)
    scrollbar:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -3, PADDING)
    scrollbar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    scrollbar:SetBackdropColor(0.06, 0.06, 0.06, 0.9)
    scrollbar:SetBackdropBorderColor(0, 0, 0, 1)
    scrollbar:EnableMouse(true)
    menu.scrollbar = scrollbar

    -- Scrollbar thumb (bright yellow/gold, matching ElvUI)
    local thumb = CreateFrame("Frame", nil, scrollbar)
    thumb:SetWidth(SCROLL_WIDTH - 2)
    local thumbTex = thumb:CreateTexture(nil, "OVERLAY")
    thumbTex:SetAllPoints(thumb)
    thumbTex:SetColorTexture(1, 0.82, 0, 1) -- Golden yellow
    thumb:EnableMouse(true)
    scrollbar.thumb = thumb

    local allTextures = {}

    local function updateList()
        local numTextures = #allTextures
        local visibleCount = math.min(numTextures, MAX_VISIBLE)
        local maxOffset = math.max(0, numTextures - visibleCount)

        if menu.scrollOffset > maxOffset then menu.scrollOffset = maxOffset end
        if menu.scrollOffset < 0 then menu.scrollOffset = 0 end

        local hasScroll = numTextures > visibleCount
        if hasScroll then
            scrollbar:Show()
            local trackH = scrollbar:GetHeight()
            if trackH and trackH > 10 then
                local thumbH = math.max(14, math.floor(trackH * (visibleCount / numTextures)))
                local thumbY = -(trackH - thumbH) * (maxOffset > 0 and (menu.scrollOffset / maxOffset) or 0)
                thumb:ClearAllPoints()
                thumb:SetPoint("TOPLEFT", scrollbar, "TOPLEFT", 1, thumbY)
                thumb:SetSize(SCROLL_WIDTH - 2, thumbH)
            end
        else
            scrollbar:Hide()
        end

        local rowWidth = (menu:GetWidth() or width or 200) - (hasScroll and (SCROLL_WIDTH + 8) or 6)

        for i = 1, MAX_VISIBLE do
            local row = menu.rows[i]
            local idx = menu.scrollOffset + i
            local name = allTextures[idx]

            if name and i <= visibleCount then
                row.textureName = name
                row:SetWidth(rowWidth)

                local isSelected = (name == currentValue)
                if isSelected then
                    row.check:Show()
                else
                    row.check:Hide()
                end

                local path = resolve_statusbar_texture(name)
                setTexturePreview(row.bar, path)
                row.text:SetText(name)

                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", menu, "TOPLEFT", 3, -PADDING - ((i - 1) * ROW_HEIGHT))
                row:Show()
            else
                row.textureName = nil
                row:Hide()
            end
        end
    end

    local function onTextureWheel(_, delta)
        local maxOffset = math.max(0, #allTextures - MAX_VISIBLE)
        if maxOffset <= 0 then return end
        if delta > 0 then
            menu.scrollOffset = math.max(0, menu.scrollOffset - 3)
        else
            menu.scrollOffset = math.min(maxOffset, menu.scrollOffset + 3)
        end
        updateList()
    end

    -- Create reusable row frames
    for i = 1, MAX_VISIBLE do
        local row = CreateFrame("Button", nil, menu)
        row:SetHeight(ROW_HEIGHT)
        row:SetFrameLevel(menu:GetFrameLevel() + 2)
        row:RegisterForClicks("LeftButtonUp")

        local check = row:CreateFontString(nil, "OVERLAY")
        check:SetFontObject("GameFontHighlightSmall")
        check:SetText("|cffffcc00✓|r")
        check:SetSize(14, 14)
        check:SetPoint("LEFT", row, "LEFT", 2, 0)
        check:SetJustifyH("CENTER")
        check:Hide()
        row.check = check

        local bar = row:CreateTexture(nil, "ARTWORK")
        bar:SetHeight(16)
        bar:SetPoint("LEFT", check, "RIGHT", 2, 0)
        bar:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.bar = bar

        local text = row:CreateFontString(nil, "OVERLAY")
        text:SetFontObject("GameFontHighlightSmall")
        local fPath, fSize = text:GetFont()
        if fPath then text:SetFont(fPath, fSize, "OUTLINE") end
        text:SetShadowColor(0, 0, 0, 1)
        text:SetShadowOffset(1, -1)
        text:SetWordWrap(false)
        text:SetPoint("LEFT", bar, "LEFT", 4, 0)
        text:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
        text:SetJustifyH("LEFT")
        text:SetTextColor(1, 1, 1, 1)
        row.text = text

        row:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
        local rowHl = row:GetHighlightTexture()
        rowHl:SetVertexColor(1, 1, 1, 0.2)

        row:SetScript("OnClick", function()
            if row.textureName then
                local chosen = row.textureName
                updateButtonDisplay(chosen)
                menu:Hide()
                if onSelectFunc then
                    local path = resolve_statusbar_texture(chosen)
                    pcall(onSelectFunc, chosen, path)
                end
            end
        end)

        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", onTextureWheel)

        menu.rows[i] = row
    end

    -- Mousewheel on menu container
    menu:EnableMouseWheel(true)
    menu:SetScript("OnMouseWheel", onTextureWheel)

    -- Thumb dragging logic
    local isDragging = false
    local dragStartY = 0
    local dragStartOffset = 0

    thumb:SetScript("OnMouseDown", function(_, mouseBtn)
        if mouseBtn == "LeftButton" then
            isDragging = true
            dragStartY = select(2, _G.GetCursorPosition()) / (_G.UIParent:GetEffectiveScale() or 1)
            dragStartOffset = menu.scrollOffset
        end
    end)
    thumb:SetScript("OnMouseUp", function()
        isDragging = false
    end)
    menu:SetScript("OnUpdate", function()
        if not isDragging then return end
        local numTextures = #allTextures
        local maxOffset = math.max(0, numTextures - MAX_VISIBLE)
        if maxOffset <= 0 then return end

        local curY = select(2, _G.GetCursorPosition()) / (_G.UIParent:GetEffectiveScale() or 1)
        local dy = dragStartY - curY
        local trackH = scrollbar:GetHeight() - thumb:GetHeight()
        if trackH > 0 then
            local offsetDelta = (dy / trackH) * maxOffset
            local newOffset = math.floor(dragStartOffset + offsetDelta + 0.5)
            menu.scrollOffset = math.max(0, math.min(maxOffset, newOffset))
            updateList()
        end
    end)

    -- Scrollbar track clicking
    scrollbar:SetScript("OnMouseDown", function(_, mouseBtn)
        if mouseBtn ~= "LeftButton" then return end
        local curY = select(2, _G.GetCursorPosition()) / (_G.UIParent:GetEffectiveScale() or 1)
        local thumbTop = thumb:GetTop() or 0
        local thumbBottom = thumb:GetBottom() or 0
        local maxOffset = math.max(0, #allTextures - MAX_VISIBLE)
        if maxOffset <= 0 then return end

        if curY > thumbTop then
            menu.scrollOffset = math.max(0, menu.scrollOffset - MAX_VISIBLE)
        elseif curY < thumbBottom then
            menu.scrollOffset = math.min(maxOffset, menu.scrollOffset + MAX_VISIBLE)
        end
        updateList()
    end)

    menu:SetScript("OnHide", function(self)
        isDragging = false
        self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        if activeTextureMenu == self then
            activeTextureMenu = nil
        end
    end)

    -- Button toggle
    btn:SetScript("OnClick", function()
        if menu:IsShown() then
            menu:Hide()
            activeTextureMenu = nil
        else
            if activeTextureMenu and activeTextureMenu ~= menu then
                activeTextureMenu:Hide()
            end
            if activeDropdown then
                activeDropdown:Hide()
            end

            allTextures = get_all_statusbar_textures()
            local numTextures = #allTextures
            local visibleCount = math.min(numTextures, MAX_VISIBLE)
            local totalH = PADDING * 2 + (visibleCount * ROW_HEIGHT)
            local menuW = math.max(width or 200, 200)

            menu:SetSize(menuW, totalH)

            -- Scroll to selected item so it is immediately in view
            local selIdx = nil
            for idx, name in ipairs(allTextures) do
                if name == currentValue then
                    selIdx = idx
                    break
                end
            end
            local maxOffset = math.max(0, numTextures - visibleCount)
            if selIdx and selIdx > visibleCount then
                menu.scrollOffset = math.min(maxOffset, selIdx - math.floor(visibleCount / 2))
            else
                menu.scrollOffset = 0
            end

            menu:ClearAllPoints()
            local btnBottom = btn:GetBottom() or 0
            if btnBottom < (totalH + 20) then
                -- Open above
                menu:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, 2)
            else
                -- Open below
                menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
            end

            menu:Show()
            updateList()
            activeTextureMenu = menu
        end
    end)

    function container:SetSelectedTexture(val)
        updateButtonDisplay(val)
    end

    if parent and parent.HookScript then
        parent:HookScript("OnHide", function()
            if menu:IsShown() then
                menu:Hide()
            end
        end)
    end

    return container
end

sfui.common.create_texture_dropdown = sfui.widgets.create_texture_dropdown

