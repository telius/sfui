local addonName, addon = ...
sfui = sfui or {}
sfui.actionbars = sfui.actionbars or {}
sfui.actionbars.style = {}

local style = sfui.actionbars.style
local _G = _G
local CreateFrame = _G.CreateFrame
local C_Timer = _G.C_Timer
local math_max = math.max
local wipe = _G.wipe or table.wipe

-- ─────────────────────────────────────────────────────────────────────────────
--  Keydown / Keyup Press & Click Animation
-- ─────────────────────────────────────────────────────────────────────────────
function style.SetupPressAnimation(button)
    if not button or button._sfuiPressSetup then return end
    button._sfuiPressSetup = true

    -- 1. Pushed Overlay (illuminates while button is depressed)
    local pushedOverlay = button:CreateTexture(nil, "OVERLAY", nil, 2)
    pushedOverlay:SetColorTexture(1, 1, 1, 0.25)
    pushedOverlay:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    pushedOverlay:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    pushedOverlay:Hide()
    button._sfuiPushedOverlay = pushedOverlay

    -- 2. Release Flash Animation (plays on keyup / click release)
    local flashFrame = CreateFrame("Frame", nil, button)
    flashFrame:SetAllPoints(button)
    flashFrame:SetFrameLevel((button:GetFrameLevel() or 1) + 8)
    flashFrame:Hide()

    local flashTex = flashFrame:CreateTexture(nil, "OVERLAY")
    flashTex:SetColorTexture(1, 1, 1, 0.45)
    flashTex:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    flashTex:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)

    local ag = flashFrame:CreateAnimationGroup()
    local alphaAnim = ag:CreateAnimation("Alpha")
    alphaAnim:SetFromAlpha(1)
    alphaAnim:SetToAlpha(0)
    alphaAnim:SetDuration(0.18)
    ag:SetScript("OnFinished", function()
        flashFrame:Hide()
    end)
    flashFrame.ag = ag
    button._sfuiFlashFrame = flashFrame

    -- 3. Mouseover Hover Highlight Animation
    local hoverFrame = CreateFrame("Frame", nil, button)
    hoverFrame:SetAllPoints(button)
    hoverFrame:SetFrameLevel((button:GetFrameLevel() or 1) + 4)
    hoverFrame:Hide()

    local hoverTex = hoverFrame:CreateTexture(nil, "OVERLAY")
    hoverTex:SetBlendMode("ADD")
    hoverTex:SetColorTexture(1, 1, 1, 0.20)
    hoverTex:SetPoint("TOPLEFT", hoverFrame, "TOPLEFT", 1, -1)
    hoverTex:SetPoint("BOTTOMRIGHT", hoverFrame, "BOTTOMRIGHT", -1, 1)

    local hoverAgIn = hoverFrame:CreateAnimationGroup()
    local hoverAlphaIn = hoverAgIn:CreateAnimation("Alpha")
    hoverAlphaIn:SetFromAlpha(0)
    hoverAlphaIn:SetToAlpha(1)
    hoverAlphaIn:SetDuration(0.12)
    hoverAlphaIn:SetSmoothing("OUT")

    local hoverAgOut = hoverFrame:CreateAnimationGroup()
    local hoverAlphaOut = hoverAgOut:CreateAnimation("Alpha")
    hoverAlphaOut:SetFromAlpha(1)
    hoverAlphaOut:SetToAlpha(0)
    hoverAlphaOut:SetDuration(0.16)
    hoverAlphaOut:SetSmoothing("IN")
    hoverAgOut:SetScript("OnFinished", function()
        hoverFrame:Hide()
    end)

    button._sfuiHoverFrame = hoverFrame
    button._sfuiHoverAgIn = hoverAgIn
    button._sfuiHoverAgOut = hoverAgOut

    function button:AnimateEnter()
        local modCfg = (sfui.db and sfui.db.Get and sfui.db.Get("actionbars")) or (sfui.config and sfui.config.actionbars) or {}
        local hasAction = false
        if self.HasAction then
            hasAction = self:HasAction()
        elseif self.GetID and _G.GetPetActionInfo then
            local name, texture = _G.GetPetActionInfo(self:GetID())
            hasAction = (name ~= nil) or (texture ~= nil)
        elseif self.action then
            hasAction = _G.HasAction and _G.HasAction(self.action)
        end

        local isDragging = (_G.GetCursorInfo and _G.GetCursorInfo() ~= nil)
        if not hasAction and not modCfg.showGrid and not isDragging then
            return
        end

        if self._sfuiHoverAgOut and self._sfuiHoverAgOut:IsPlaying() then
            self._sfuiHoverAgOut:Stop()
        end
        if self._sfuiHoverFrame and self._sfuiHoverAgIn then
            self._sfuiHoverFrame:Show()
            self._sfuiHoverAgIn:Stop()
            self._sfuiHoverAgIn:Play()
        end

        if self.borders then
            local app = sfui.config and sfui.config.appearance
            local hlCol = (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette().highlightColor)
                or (app and app.highlightColor)
                or { 0.4, 0.0, 1.0, 1 }
            for _, b in ipairs(self.borders) do
                b:SetVertexColor(hlCol[1], hlCol[2], hlCol[3], 0.9)
                b:Show()
            end
        end
    end

    function button:AnimateLeave()
        if self._sfuiHoverAgIn and self._sfuiHoverAgIn:IsPlaying() then
            self._sfuiHoverAgIn:Stop()
        end
        if self._sfuiHoverFrame and self._sfuiHoverFrame:IsShown() and self._sfuiHoverAgOut then
            self._sfuiHoverAgOut:Stop()
            self._sfuiHoverAgOut:Play()
        end

        if self.borders then
            local app = sfui.config and sfui.config.appearance
            local bCol = (app and app.borderColor) or { 0, 0, 0, 1 }
            local modCfg = (sfui.db and sfui.db.Get and sfui.db.Get("actionbars")) or (sfui.config and sfui.config.actionbars) or {}
            local hasAction = false
            if self.HasAction then
                hasAction = self:HasAction()
            elseif self.GetID and _G.GetPetActionInfo then
                local name, texture = _G.GetPetActionInfo(self:GetID())
                hasAction = (name ~= nil) or (texture ~= nil)
            elseif self.action then
                hasAction = _G.HasAction and _G.HasAction(self.action)
            end
            local isDragging = (sfui.actionbars and sfui.actionbars.mouseover and sfui.actionbars.mouseover.isDragging) or (_G.GetCursorInfo and _G.GetCursorInfo() ~= nil)
            local showBorder = hasAction or modCfg.showGrid or isDragging
            for _, b in ipairs(self.borders) do
                b:SetVertexColor(bCol[1], bCol[2], bCol[3], bCol[4] or 1)
                b:SetShown(showBorder)
            end
        end
    end

    -- Mouse Hover Interaction Hooks
    button:HookScript("OnEnter", function(self)
        self:AnimateEnter()
    end)
    button:HookScript("OnLeave", function(self)
        self:AnimateLeave()
    end)

    -- Tactile Button Down
    function button:AnimateDown()
        if self._isAnimateDown then return end
        self._isAnimateDown = true
        self:SetButtonState("PUSHED")

        -- Skip layout shifts and texture operations on invisible mouseover bars
        if self:GetEffectiveAlpha() <= 0 then return end

        local icon = self.icon or self.Icon
        if icon then
            icon:SetPoint("TOPLEFT", self, "TOPLEFT", 2, -2)
            icon:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
        end
        if self.cooldown then
            self.cooldown:SetPoint("TOPLEFT", self, "TOPLEFT", 2, -2)
            self.cooldown:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
        end
        if self._sfuiPushedOverlay then
            self._sfuiPushedOverlay:Show()
        end
    end

    -- Tactile Button Up & Release Flash
    function button:AnimateUp()
        if not self._isAnimateDown then return end
        self._isAnimateDown = false
        self:SetButtonState("NORMAL")

        if self._sfuiPushedOverlay then
            self._sfuiPushedOverlay:Hide()
        end

        local icon = self.icon or self.Icon
        if icon then
            icon:SetPoint("TOPLEFT", self, "TOPLEFT", 1, -1)
            icon:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -1, 1)
        end
        if self.cooldown then
            self.cooldown:SetPoint("TOPLEFT", self, "TOPLEFT", 1, -1)
            self.cooldown:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -1, 1)
        end

        -- Play crisp release flash only when visible
        if self._sfuiFlashFrame and self:IsVisible() and self:GetEffectiveAlpha() > 0 then
            self._sfuiFlashFrame:Show()
            self._sfuiFlashFrame.ag:Stop()
            self._sfuiFlashFrame.ag:Play()
        end
    end

    -- Mouse Press Interaction Hooks
    button:HookScript("OnMouseDown", function(self)
        self:AnimateDown()
    end)
    button:HookScript("OnMouseUp", function(self)
        self:AnimateUp()
    end)
    button:HookScript("PreClick", function(self)
        self:AnimateDown()
    end)
    button:HookScript("PostClick", function(self)
        C_Timer.After(0.08, function()
            self:AnimateUp()
        end)
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Hotkey Text Formatter & Memoization Cache
-- ─────────────────────────────────────────────────────────────────────────────
local hotkeyCache = {}
local updatingHotkey = false

function style.ClearHotkeyCache()
    wipe(hotkeyCache)
end

function style.FormatHotkeyText(text)
    if not text or text == "" or text == _G.RANGE_INDICATOR or text == "●" or text == "•" or text == "*" then
        return text
    end

    local cached = hotkeyCache[text]
    if cached then
        return cached
    end

    local s = tostring(text):lower()

    -- Strip "key_" prefix if returned by engine key chords
    s = s:gsub("^key_", "")

    -- Modifiers: 1 character for modifiers - a, c, s, m
    s = s:gsub("alt%-?", "a")
    s = s:gsub("control%-?", "c")
    s = s:gsub("ctrl%-?", "c")
    s = s:gsub("strg%-?", "c")
    s = s:gsub("shift%-?", "s")
    s = s:gsub("meta%-?", "m")
    s = s:gsub("cmd%-?", "m")
    s = s:gsub("command%-?", "m")

    -- Clean up legacy hyphenated prefixes (e.g., "s-1" -> "s1", "c-1" -> "c1", "a-1" -> "a1")
    s = s:gsub("^([acsm])%-([^-])", "%1%2")
    s = s:gsub("^([acsm])%-%-", "%1-")
    s = s:gsub("([acsm])%-([acsm])%-", "%1%2")
    s = s:gsub("([acsm])%-([^-])", "%1%2")

    -- Mouse buttons and mouse wheel
    s = s:gsub("mousewheelup", "mu")
    s = s:gsub("mousewheeldown", "md")
    s = s:gsub("wheelup", "mu")
    s = s:gsub("wheeldown", "md")
    s = s:gsub("middlemouse", "m3")
    s = s:gsub("middlebutton", "m3")
    s = s:gsub("leftbutton", "m1")
    s = s:gsub("rightbutton", "m2")
    s = s:gsub("button(%d+)", "m%1")
    s = s:gsub("mouse(%d+)", "m%1")

    -- Numpad keys
    s = s:gsub("numpadplus", "n+")
    s = s:gsub("numpadminus", "n-")
    s = s:gsub("numpadmultiply", "n*")
    s = s:gsub("numpaddivide", "n/")
    s = s:gsub("numpaddecimal", "n.")
    s = s:gsub("numpad(%d+)", "n%1")
    s = s:gsub("numpad", "n")
    s = s:gsub("num(%d+)", "n%1")

    -- Common special keys
    s = s:gsub("spacebar", "sp")
    s = s:gsub("space", "sp")
    s = s:gsub("pageup", "pu")
    s = s:gsub("pagedown", "pd")
    s = s:gsub("insert", "ins")
    s = s:gsub("delete", "del")
    s = s:gsub("home", "hm")
    s = s:gsub("end", "end")
    s = s:gsub("backspace", "bs")
    s = s:gsub("capslock", "caps")
    s = s:gsub("escape", "esc")
    s = s:gsub("downarrow", "dn")
    s = s:gsub("uparrow", "up")
    s = s:gsub("leftarrow", "lt")
    s = s:gsub("rightarrow", "rt")

    -- Function keys: F1..F12 (uppercase "F" followed by digits, e.g. "F1", "sF1", "cF1", "aF1")
    s = s:gsub("(%a*)f(%d+)", "%1F%2")

    hotkeyCache[text] = s
    return s
end

local function hook_hotkey(hotkey)
    if not hotkey or hotkey._sfuiHooked then return end
    hotkey._sfuiHooked = true

    _G.hooksecurefunc(hotkey, "SetText", function(self, text)
        if updatingHotkey then return end
        if not text or text == "" or text == _G.RANGE_INDICATOR or text == "●" or text == "•" or text == "*" then return end
        local formatted = style.FormatHotkeyText(text)
        if formatted and formatted ~= text then
            updatingHotkey = true
            self:SetText(formatted)
            updatingHotkey = false
        end
    end)
end

-- Hook or stub LibKeyBound-1.0 so LibActionButton formats hotkeys directly on the first pass
local LibStub = _G.LibStub
if LibStub then
    local lkb = LibStub("LibKeyBound-1.0", true)
    if lkb then
        lkb.ToShortKey = function(_, key)
            return style.FormatHotkeyText(key)
        end
    else
        local stub = LibStub:NewLibrary("LibKeyBound-1.0", 1)
        if stub then
            function stub:ToShortKey(key)
                return style.FormatHotkeyText(key)
            end
            function stub:Set() end
        end
    end
end

-- Clear hotkey cache when bindings update
local bindingEventFrame = _G.CreateFrame and _G.CreateFrame("Frame")
if bindingEventFrame then
    bindingEventFrame:RegisterEvent("UPDATE_BINDINGS")
    bindingEventFrame:SetScript("OnEvent", function()
        style.ClearHotkeyCache()
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Button Skinning & Backdrop
-- ─────────────────────────────────────────────────────────────────────────────
function style.SkinButton(button)
    if not button or button._sfuiSkinned then return end
    button._sfuiSkinned = true

    -- Prevent LibActionButton from applying default round masque / border
    button.MasqueSkinned = true

    -- Hide Blizzard / LAB slot backgrounds and masks
    if button.SlotBackground then
        button.SlotBackground:Hide()
    end
    if button.IconMask then
        if button.icon and button.icon.RemoveMaskTexture then
            button.icon:RemoveMaskTexture(button.IconMask)
        end
        button.IconMask:Hide()
    end

    -- Clear default normal texture
    local normal = button.NormalTexture or (button.GetNormalTexture and button:GetNormalTexture())
    if normal then
        normal:SetTexture(nil)
        normal:Hide()
        normal:SetAlpha(0)
    end

    -- Clean 1px dark slot background & 1px border
    local app = sfui.config and sfui.config.appearance
    local bgCol = (app and app.backdropColor) or { 0.05, 0.05, 0.05, 0.85 }
    local bCol = (app and app.borderColor) or { 0, 0, 0, 1 }

    if not button.sfuiSlotBg then
        local slotBg = button:CreateTexture(nil, "BACKGROUND", nil, -8)
        slotBg:SetAllPoints(button)
        slotBg:SetColorTexture(bgCol[1], bgCol[2], bgCol[3], bgCol[4] or 0.85)
        button.sfuiSlotBg = slotBg
    end

    if sfui.common and sfui.common.create_border then
        sfui.common.create_border(button, 1, bCol)
        if button.borders then
            for _, b in ipairs(button.borders) do
                b:SetDrawLayer("OVERLAY", 2)
            end
        end
    end

    -- Clean up legacy sfuiBackdrop child frame if present (prevents darkening the icon)
    if button.sfuiBackdrop and button.sfuiBackdrop.GetObjectType and button.sfuiBackdrop:GetObjectType() == "Frame" then
        button.sfuiBackdrop:Hide()
        button.sfuiBackdrop:SetAlpha(0)
    end

    -- Compatibility wrapper for button.sfuiBackdrop
    button.sfuiBackdrop = {
        Show = function()
            if button.sfuiSlotBg then button.sfuiSlotBg:Show() end
            if button.borders then
                for _, b in ipairs(button.borders) do b:Show() end
            end
        end,
        Hide = function()
            if button.sfuiSlotBg then button.sfuiSlotBg:Hide() end
            if button.borders then
                for _, b in ipairs(button.borders) do b:Hide() end
            end
        end,
        SetShown = function(_, show)
            if button.sfuiSlotBg then button.sfuiSlotBg:SetShown(show) end
            if button.borders then
                for _, b in ipairs(button.borders) do b:SetShown(show) end
            end
        end,
    }

    -- Icon styling: zoom / crop edges to remove rounded Blizzard border
    local icon = button.icon or button.Icon
    if icon then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        icon:SetDrawLayer("ARTWORK", 0)
    end

    -- Cooldown frame styling
    local cd = button.cooldown
    if cd then
        cd:ClearAllPoints()
        cd:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        cd:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    end

    -- Suppress default static highlight texture (replaced by animated hoverFrame)
    local hl = button.HighlightTexture or (button.GetHighlightTexture and button:GetHighlightTexture())
    if hl then
        hl:SetTexture(nil)
        hl:SetAlpha(0)
        hl:Hide()
    end

    -- Pushed texture
    local push = button.PushedTexture or (button.GetPushedTexture and button:GetPushedTexture())
    if push then
        push:SetColorTexture(1, 1, 1, 0.3)
        push:ClearAllPoints()
        push:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        push:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    end

    -- Checked texture
    local checked = button.CheckedTexture or (button.GetCheckedTexture and button:GetCheckedTexture())
    if checked then
        checked:SetColorTexture(0.2, 0.8, 1.0, 0.3)
        checked:ClearAllPoints()
        checked:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        checked:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    end

    local hotkeyFont = (sfui.config and sfui.config.fontFile)
        or (_G.NumberFontNormalSmallGray and _G.NumberFontNormalSmallGray:GetFont())
        or (sfui.common and sfui.common.get_font_file and sfui.common.get_font_file())
        or "Fonts\\ARIALN.TTF"
    local fontFile = (sfui.common and sfui.common.get_font_file and sfui.common.get_font_file()) or "Fonts\\FRIZQT__.TTF"
    local modCfg = (sfui.db and sfui.db.Get and sfui.db.Get("actionbars")) or (sfui.config and sfui.config.actionbars) or {}
    local hotkeySize = modCfg.hotkeyFontSize or 10

    -- Typography: Hotkey (top-right, compact 10px, no font shadows, lowercase modifiers)
    local hotkey = button.HotKey
    if hotkey then
        hotkey:SetFont(hotkeyFont, hotkeySize, "OUTLINE")
        hotkey:SetShadowOffset(0, 0)
        hotkey:SetShadowColor(0, 0, 0, 0)
        hotkey:SetTextColor(1, 1, 1, 0.9)
        hotkey:ClearAllPoints()
        hotkey:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)
        -- Template size (32x10) truncates long labels into "..."; 0x0 auto-sizes to the full string
        hotkey:SetSize(0, 0)
        hotkey:SetWordWrap(false)
        hotkey:SetJustifyH("RIGHT")
        hotkey:SetJustifyV("TOP")
        hotkey:SetDrawLayer("OVERLAY", 1)

        hook_hotkey(hotkey)

        local key = (button.GetHotkey and button:GetHotkey())
        local current = key or hotkey:GetText()
        local isRangeIndicator = (not current) or current == "" or current == _G.RANGE_INDICATOR or current == "●" or current == "•" or current == "*"
        if isRangeIndicator then
            hotkey:Hide()
        else
            local formatted = style.FormatHotkeyText(current)
            if formatted and hotkey:GetText() ~= formatted then
                updatingHotkey = true
                hotkey:SetText(formatted)
                updatingHotkey = false
            end
            hotkey:Show()
        end
    end

    -- Typography: Count / Charges (bottom-right, compact 11px, no font shadows)
    local count = button.Count
    if count then
        count:SetFont(fontFile, 11, "OUTLINE")
        count:SetShadowOffset(0, 0)
        count:SetShadowColor(0, 0, 0, 0)
        count:ClearAllPoints()
        count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
        count:SetJustifyH("RIGHT")
        count:SetDrawLayer("OVERLAY", 1)
    end

    -- Typography: Macro Name (bottom-center, compact 9px, no font shadows)
    local name = button.Name
    if name then
        name:SetFont(fontFile, 9, "OUTLINE")
        name:SetShadowOffset(0, 0)
        name:SetShadowColor(0, 0, 0, 0)
        name:ClearAllPoints()
        name:SetPoint("BOTTOM", button, "BOTTOM", 0, 2)
        name:SetJustifyH("CENTER")
        name:SetDrawLayer("OVERLAY", 1)
    end

    -- Wire up keydown / click animations
    style.SetupPressAnimation(button)
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Dynamic Config Sync (Toggling Hotkeys, Counts, Macros, Grid)
-- ─────────────────────────────────────────────────────────────────────────────
function style.UpdateElements(button, cfg)
    if not button then return end
    cfg = cfg or (sfui.db and sfui.db.Get and sfui.db.Get("actionbars")) or (sfui.config and sfui.config.actionbars) or {}
    local hotkeyFont = (sfui.config and sfui.config.fontFile)
        or (_G.NumberFontNormalSmallGray and _G.NumberFontNormalSmallGray:GetFont())
        or (sfui.common and sfui.common.get_font_file and sfui.common.get_font_file())
        or "Fonts\\ARIALN.TTF"
    local fontFile = (sfui.common and sfui.common.get_font_file and sfui.common.get_font_file()) or "Fonts\\FRIZQT__.TTF"
    local hotkeySize = cfg.hotkeyFontSize or 10

    if button.HotKey then
        button.HotKey:SetFont(hotkeyFont, hotkeySize, "OUTLINE")
        button.HotKey:SetShadowOffset(0, 0)
        button.HotKey:SetShadowColor(0, 0, 0, 0)
        button.HotKey:SetTextColor(1, 1, 1, 0.9)

        local key = (button.GetHotkey and button:GetHotkey())
        local current = key or button.HotKey:GetText()
        local isRangeIndicator = (not current) or current == "" or current == _G.RANGE_INDICATOR or current == "●" or current == "•" or current == "*"
        if cfg.showHotkeys == false or isRangeIndicator then
            button.HotKey:Hide()
        else
            local formatted = style.FormatHotkeyText(current)
            if formatted and button.HotKey:GetText() ~= formatted then
                updatingHotkey = true
                button.HotKey:SetText(formatted)
                updatingHotkey = false
            end
            button.HotKey:Show()
        end
    end

    if button.Count then
        button.Count:SetFont(fontFile, 11, "OUTLINE")
        button.Count:SetShadowOffset(0, 0)
        button.Count:SetShadowColor(0, 0, 0, 0)

        if cfg.showCounts == false then
            button.Count:Hide()
        else
            button.Count:Show()
        end
    end

    if button.Name then
        button.Name:SetFont(fontFile, 9, "OUTLINE")
        button.Name:SetShadowOffset(0, 0)
        button.Name:SetShadowColor(0, 0, 0, 0)

        if cfg.showMacroNames then
            button.Name:Show()
        else
            button.Name:Hide()
        end
    end

    style.UpdateGrid(button, cfg)
end

function style.UpdateGrid(button, cfg)
    if not button then return end
    cfg = cfg or (sfui.db and sfui.db.Get and sfui.db.Get("actionbars")) or (sfui.config and sfui.config.actionbars) or {}
    local showGrid = (cfg.showGrid == true)
    local hasAction = false
    if button.HasAction then
        hasAction = button:HasAction()
    elseif button.GetID and _G.GetPetActionInfo then
        local name, texture = _G.GetPetActionInfo(button:GetID())
        hasAction = (name ~= nil) or (texture ~= nil)
    elseif button.action then
        hasAction = _G.HasAction and _G.HasAction(button.action)
    end
    local isDragging = (sfui.actionbars and sfui.actionbars.mouseover and sfui.actionbars.mouseover.isDragging) or (_G.GetCursorInfo and _G.GetCursorInfo() ~= nil)
    local showBg = hasAction or showGrid or isDragging

    if button.sfuiSlotBg then
        button.sfuiSlotBg:SetShown(showBg)
    end
    if button.borders then
        for _, b in ipairs(button.borders) do
            b:SetShown(showBg)
        end
    end
    if button.sfuiBackdrop and button.sfuiBackdrop.SetShown then
        button.sfuiBackdrop:SetShown(showBg)
    end
end
