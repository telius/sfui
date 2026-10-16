local addonName, addon = ...
sfui = sfui or {}
sfui.actionbars = sfui.actionbars or {}
sfui.actionbars.bind = {}
local bind = sfui.actionbars.bind

local _G = _G
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local GetBindingKey = _G.GetBindingKey
local GetBindingAction = _G.GetBindingAction
local GetBindingName = _G.GetBindingName
local SetBinding = _G.SetBinding
local SaveBindings = _G.SaveBindings
local LoadBindings = _G.LoadBindings
local GetCurrentBindingSet = _G.GetCurrentBindingSet
local InCombatLockdown = _G.InCombatLockdown
local IsAltKeyDown = _G.IsAltKeyDown
local IsControlKeyDown = _G.IsControlKeyDown
local IsShiftKeyDown = _G.IsShiftKeyDown
local IsMetaKeyDown = _G.IsMetaKeyDown
local hooksecurefunc = _G.hooksecurefunc
local ipairs = _G.ipairs
local pairs = _G.pairs
local type = _G.type
local tostring = _G.tostring
local tinsert = _G.table.insert
local math_max = _G.math.max

local BINDING_SET_ACCOUNT = (_G.Enum and _G.Enum.BindingSet and _G.Enum.BindingSet.Account) or 1
local BINDING_SET_CHARACTER = (_G.Enum and _G.Enum.BindingSet and _G.Enum.BindingSet.Character) or 2

bind.isActive = false
bind.currentButton = nil
bind.handledButtons = {}

-- ─────────────────────────────────────────────────────────────────────────────
--  Key and Input Helpers
-- ─────────────────────────────────────────────────────────────────────────────
local IGNORED_KEYS = {
    ["UNKNOWN"] = true,
    ["LSHIFT"] = true,
    ["RSHIFT"] = true,
    ["LCTRL"] = true,
    ["RCTRL"] = true,
    ["LALT"] = true,
    ["RALT"] = true,
    ["LMETA"] = true,
    ["RMETA"] = true,
}

local function is_ignored_key(key)
    if _G.IsKeyPressIgnoredForBinding and _G.IsKeyPressIgnoredForBinding(key) then
        return true
    end
    return IGNORED_KEYS[key] or false
end

local function get_chord_string(key)
    if _G.CreateKeyChordStringUsingMetaKeyState then
        return _G.CreateKeyChordStringUsingMetaKeyState(key)
    end
    local alt = IsAltKeyDown() and "ALT-" or ""
    local ctrl = IsControlKeyDown() and "CTRL-" or ""
    local shift = IsShiftKeyDown() and "SHIFT-" or ""
    local meta = (IsMetaKeyDown and IsMetaKeyDown()) and "META-" or ""
    return alt .. ctrl .. shift .. meta .. key
end

local function convert_mouse_button(btn)
    if not btn then return nil end
    if btn == "MiddleButton" then return "BUTTON3" end
    if btn:find("^Button%d+$") then return btn:upper() end
    return btn
end

function bind:GetButtonLabel(btn)
    if not btn then return "unknown button" end
    local cmd = btn.commandName
    if cmd then
        local blizzName = GetBindingName(cmd)
        if blizzName and blizzName ~= "" and blizzName ~= cmd then
            return blizzName:lower()
        end
    end
    if btn.barIndex and btn.buttonIndex then
        return ("bar %d button %d"):format(btn.barIndex, btn.buttonIndex)
    elseif btn.barKey == "pet" then
        return ("pet bar button %d"):format(btn.index or btn.buttonIndex or 1)
    elseif btn.barKey == "vehicle" then
        return "vehicle exit button"
    end
    return (btn:GetName() or "button"):lower()
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Hover Overlay Frame
-- ─────────────────────────────────────────────────────────────────────────────
local overlay = CreateFrame("Frame", "sfui_KeybindOverlay", UIParent, "BackdropTemplate")
overlay:SetFrameStrata("DIALOG")
overlay:SetFrameLevel(99)
overlay:EnableMouse(true)
overlay:EnableKeyboard(true)
overlay:EnableMouseWheel(true)
overlay:Hide()
bind.overlay = overlay

if sfui.common and sfui.common.set_pixel_snapping then
    sfui.common.set_pixel_snapping(overlay)
end

overlay:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8X8",
    edgeFile = "Interface/Buttons/WHITE8X8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
})
overlay:SetBackdropColor(0, 0.4, 0.8, 0.15)
local accent = (sfui.config and sfui.config.colors and sfui.config.colors.accent) or { 0.4, 0.9, 1.0 }
overlay:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1.0)

-- ─────────────────────────────────────────────────────────────────────────────
--  Tooltip Frame
-- ─────────────────────────────────────────────────────────────────────────────
local tip = CreateFrame("Frame", "sfui_KeybindTooltip", UIParent, "BackdropTemplate")
tip:SetFrameStrata("TOOLTIP")
tip:SetFrameLevel(100)
tip:SetClampedToScreen(true)
tip:Hide()
bind.tooltip = tip

if sfui.common and sfui.common.set_pixel_snapping then
    sfui.common.set_pixel_snapping(tip)
end

tip:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8X8",
    edgeFile = "Interface/Buttons/WHITE8X8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
})
tip:SetBackdropColor(0.04, 0.04, 0.04, 0.95)
tip:SetBackdropBorderColor(0.15, 0.15, 0.15, 1.0)

local function get_font_file()
    return (sfui.common and sfui.common.get_font_file and sfui.common.get_font_file())
        or (_G.GameFontNormal and _G.GameFontNormal.GetFont and _G.GameFontNormal:GetFont())
        or "Fonts\\FRIZQT__.TTF"
end

local fontFile = get_font_file()

local titleFs = tip:CreateFontString(nil, "OVERLAY")
titleFs:SetFont(fontFile, 12, "OUTLINE")
titleFs:SetPoint("TOPLEFT", tip, "TOPLEFT", 8, -6)
titleFs:SetTextColor(accent[1], accent[2], accent[3], 1.0)
tip.title = titleFs

local cmdFs = tip:CreateFontString(nil, "OVERLAY")
cmdFs:SetFont(fontFile, 10, "")
cmdFs:SetPoint("TOPLEFT", titleFs, "BOTTOMLEFT", 0, -2)
cmdFs:SetTextColor(0.65, 0.65, 0.65, 1.0)
tip.cmd = cmdFs

local bindFs = tip:CreateFontString(nil, "OVERLAY")
bindFs:SetFont(fontFile, 11, "")
bindFs:SetPoint("TOPLEFT", cmdFs, "BOTTOMLEFT", 0, -4)
bindFs:SetTextColor(1, 1, 1, 1.0)
tip.bindings = bindFs

local hintFs = tip:CreateFontString(nil, "OVERLAY")
hintFs:SetFont(fontFile, 9, "")
hintFs:SetPoint("TOPLEFT", bindFs, "BOTTOMLEFT", 0, -4)
hintFs:SetTextColor(0.5, 0.5, 0.5, 1.0)
tip.hint = hintFs

function bind:UpdateTooltip()
    local btn = bind.currentButton
    if not btn or not bind.isActive then
        tip:Hide()
        return
    end

    local label = bind:GetButtonLabel(btn)
    local cmd = btn.commandName or "unknown"
    local k1, k2 = GetBindingKey(cmd)
    local bindText
    if k1 then
        bindText = "|cff00ff88bound to:|r " .. k1:lower() .. (k2 and (", " .. k2:lower()) or "")
    else
        bindText = "|cffff4444not bound|r"
    end

    tip.title:SetText(label)
    tip.cmd:SetText(cmd:lower())
    tip.bindings:SetText(bindText)
    tip.hint:SetText("press key to bind  |  escape to clear")

    local w1 = (tip.title:GetStringWidth() or 0)
    local w2 = (tip.cmd:GetStringWidth() or 0)
    local w3 = (tip.bindings:GetStringWidth() or 0)
    local w4 = (tip.hint:GetStringWidth() or 0)
    local maxW = math_max(w1, w2, w3, w4, 160) + 16
    local totalH = 8 + (tip.title:GetStringHeight() or 12) + 2 + (tip.cmd:GetStringHeight() or 10) + 4 + (tip.bindings:GetStringHeight() or 11) + 4 + (tip.hint:GetStringHeight() or 9) + 8

    tip:SetSize(maxW, totalH)
    tip:ClearAllPoints()

    local btnTop = btn:GetTop() or 0
    local screenH = UIParent:GetHeight() or 768
    if btnTop > (screenH * 0.7) then
        tip:SetPoint("TOP", btn, "BOTTOM", 0, -6)
    else
        tip:SetPoint("BOTTOM", btn, "TOP", 0, 6)
    end
    tip:Show()
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Input Processing
-- ─────────────────────────────────────────────────────────────────────────────
function bind:ProcessInputKey(key)
    if not bind.isActive or not bind.currentButton then return end
    local btn = bind.currentButton
    local cmd = btn.commandName
    if not cmd then return end

    if key == "ESCAPE" then
        local k1, k2 = GetBindingKey(cmd)
        if k1 then SetBinding(k1, nil) end
        if k2 then SetBinding(k2, nil) end

        if sfui.actionbars and sfui.actionbars.UpdateAllBindings then
            sfui.actionbars.UpdateAllBindings()
        end
        bind:UpdateTooltip()
        if sfui.common and sfui.common.print then
            sfui.common.print("cleared bindings for " .. bind:GetButtonLabel(btn))
        end
        return
    end

    if is_ignored_key(key) then return end

    local chord = get_chord_string(key)
    if not chord or chord == "" then return end

    local oldAction = GetBindingAction(chord)
    if oldAction and oldAction ~= "" and oldAction ~= cmd then
        local oldLabel = GetBindingName(oldAction) or oldAction
        if sfui.common and sfui.common.print then
            sfui.common.print("|cff66e0ff" .. chord:lower() .. "|r unbound from " .. oldLabel:lower())
        end
    end

    local k1, k2 = GetBindingKey(cmd)
    if k1 then SetBinding(k1, nil) end
    if k2 then SetBinding(k2, nil) end

    SetBinding(chord, cmd)

    if sfui.actionbars and sfui.actionbars.UpdateAllBindings then
        sfui.actionbars.UpdateAllBindings()
    end
    bind:UpdateTooltip()

    if sfui.common and sfui.common.print then
        sfui.common.print("bound |cff66e0ff" .. chord:lower() .. "|r to " .. bind:GetButtonLabel(btn))
    end
end

overlay:SetScript("OnKeyDown", function(self, key)
    bind:ProcessInputKey(key)
end)

overlay:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" or button == "RightButton" then
        return
    end
    local converted = convert_mouse_button(button)
    if converted then
        bind:ProcessInputKey(converted)
    end
end)

overlay:SetScript("OnMouseWheel", function(self, delta)
    local key = delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"
    bind:ProcessInputKey(key)
end)

overlay:SetScript("OnLeave", function(self)
    if not self:IsMouseOver() then
        self:Hide()
        if bind.tooltip then bind.tooltip:Hide() end
        bind.currentButton = nil
    end
end)

function bind.SetHoveredButton(button)
    if not bind.isActive or InCombatLockdown() then return end
    if not button or not button:IsShown() then return end

    bind.currentButton = button
    overlay:ClearAllPoints()
    overlay:SetAllPoints(button)
    overlay.button = button
    overlay:Show()
    bind:UpdateTooltip()
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Dialog Frame
-- ─────────────────────────────────────────────────────────────────────────────
local dialog = CreateFrame("Frame", "sfui_KeybindDialog", UIParent, "BackdropTemplate")
dialog:SetSize(340, 130)
dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
dialog:SetFrameStrata("DIALOG")
dialog:SetFrameLevel(98)
dialog:SetClampedToScreen(true)
dialog:EnableMouse(true)
dialog:SetMovable(true)
dialog:RegisterForDrag("LeftButton")
dialog:SetScript("OnDragStart", function(self) self:StartMoving() end)
dialog:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
dialog:Hide()
bind.dialog = dialog

if sfui.common and sfui.common.set_pixel_snapping then
    sfui.common.set_pixel_snapping(dialog)
end

dialog:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8X8",
    edgeFile = "Interface/Buttons/WHITE8X8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
})
dialog:SetBackdropColor(0.04, 0.04, 0.04, 0.95)
dialog:SetBackdropBorderColor(0.15, 0.15, 0.15, 1.0)

local headerText = dialog:CreateFontString(nil, "OVERLAY")
headerText:SetFont(fontFile, 13, "OUTLINE")
headerText:SetPoint("TOPLEFT", dialog, "TOPLEFT", 14, -12)
headerText:SetTextColor(accent[1], accent[2], accent[3], 1.0)
headerText:SetText("quick keybind mode")

local descText = dialog:CreateFontString(nil, "OVERLAY")
descText:SetFont(fontFile, 11, "")
descText:SetPoint("TOPLEFT", headerText, "BOTTOMLEFT", 0, -6)
descText:SetPoint("RIGHT", dialog, "RIGHT", -14, 0)
descText:SetJustifyH("LEFT")
descText:SetTextColor(0.75, 0.75, 0.75, 1.0)
descText:SetText("hover over any action button and press a key to bind it.\npress escape to clear bindings for hovered button.")

local CreateCheckbox = (sfui.common and sfui.common.create_checkbox) or (sfui.widgets and sfui.widgets.create_checkbox)
local perCharCB = CreateCheckbox(dialog, "character specific keybindings", function()
    return GetCurrentBindingSet() == BINDING_SET_CHARACTER
end, function(checked)
    local newSet = checked and BINDING_SET_CHARACTER or BINDING_SET_ACCOUNT
    LoadBindings(newSet)
    if sfui.actionbars and sfui.actionbars.UpdateAllBindings then
        sfui.actionbars.UpdateAllBindings()
    end
    if sfui.common and sfui.common.print then
        sfui.common.print(checked and "switched to character-specific keybindings." or "switched to account-wide keybindings.")
    end
end, "when enabled, keybinding changes are saved only for this character.")
perCharCB:SetPoint("TOPLEFT", descText, "BOTTOMLEFT", 0, -10)

local CreateFlatButton = (sfui.common and sfui.common.create_flat_button) or (sfui.widgets and sfui.widgets.create_flat_button)

local discardBtn = CreateFlatButton(dialog, "discard", 150, 22, function()
    sfui.actionbars.DeactivateBindMode(false)
end)
discardBtn:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 14, 12)

local saveBtn = CreateFlatButton(dialog, "save", 150, 22, function()
    sfui.actionbars.DeactivateBindMode(true)
end)
saveBtn:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -14, 12)

tinsert(_G.UISpecialFrames, "sfui_KeybindDialog")
dialog:SetScript("OnHide", function(self)
    if bind.isActive then
        sfui.actionbars.DeactivateBindMode(false)
    end
end)

-- ─────────────────────────────────────────────────────────────────────────────
--  Button Registration & Hooking
-- ─────────────────────────────────────────────────────────────────────────────
function bind.RegisterButton(button)
    if not button or bind.handledButtons[button] then return end
    bind.handledButtons[button] = true

    if button.HookScript then
        button:HookScript("OnEnter", function(self)
            if _G.KeybindFrames_InQuickKeybindMode and _G.KeybindFrames_InQuickKeybindMode() then
                if _G.QuickKeybindFrame and _G.QuickKeybindFrame.SetSelected then
                    _G.QuickKeybindFrame:SetSelected(self.commandName, self)
                    local blizzTip = _G.QuickKeybindTooltip
                    if blizzTip and self.commandName then
                        blizzTip:SetOwner(self, "ANCHOR_RIGHT")
                        local name = _G.GetBindingName(self.commandName) or self.commandName
                        if _G.GameTooltip_AddHighlightLine then
                            _G.GameTooltip_AddHighlightLine(blizzTip, name)
                        else
                            blizzTip:AddLine(name, 1, 1, 1)
                        end
                        local k1, k2 = GetBindingKey(self.commandName)
                        if k1 then
                            blizzTip:AddLine(k1:lower() .. (k2 and (", " .. k2:lower()) or ""), 0, 1, 0)
                            blizzTip:AddLine(_G.ESCAPE_TO_UNBIND or "press escape to unbind", 0.7, 0.7, 0.7)
                        else
                            blizzTip:AddLine(_G.NOT_BOUND or "not bound", 1, 0.2, 0.2)
                            blizzTip:AddLine(_G.PRESS_KEY_TO_BIND or "press key to bind", 0.7, 0.7, 0.7)
                        end
                        blizzTip:Show()
                    end
                end
            elseif bind.isActive then
                bind.SetHoveredButton(self)
            end
        end)

        button:HookScript("OnLeave", function(self)
            if _G.KeybindFrames_InQuickKeybindMode and _G.KeybindFrames_InQuickKeybindMode() then
                if _G.QuickKeybindFrame and _G.QuickKeybindFrame.SetSelected then
                    _G.QuickKeybindFrame:SetSelected(nil, nil)
                end
                if _G.QuickKeybindTooltip then
                    _G.QuickKeybindTooltip:Hide()
                end
            end
        end)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Mode Activation & Deactivation
-- ─────────────────────────────────────────────────────────────────────────────
function sfui.actionbars.ActivateBindMode()
    if InCombatLockdown and InCombatLockdown() then
        if sfui.common and sfui.common.print then
            sfui.common.print("cannot enter quick keybind mode in combat.")
        end
        return
    end

    bind.isActive = true

    local allBars = sfui.actionbars.GetAllBars and sfui.actionbars.GetAllBars()
    if allBars then
        for _, bar in ipairs(allBars) do
            if bar and bar.buttons then
                for _, b in ipairs(bar.buttons) do
                    bind.RegisterButton(b)
                end
            end
        end
    end
    if sfui.actionbars.vehicleLeaveButton then
        bind.RegisterButton(sfui.actionbars.vehicleLeaveButton)
    end

    if sfui.actionbars.mouseover and sfui.actionbars.mouseover.UpdateAllBars then
        sfui.actionbars.mouseover.UpdateAllBars()
    end

    dialog:Show()

    if sfui.common and sfui.common.print then
        sfui.common.print("quick keybind mode activated.")
    end
end

function sfui.actionbars.DeactivateBindMode(save)
    if not bind.isActive and not dialog:IsShown() then return end

    bind.isActive = false

    if save then
        SaveBindings(GetCurrentBindingSet())
        if sfui.common and sfui.common.print then
            sfui.common.print("keybindings saved.")
        end
    else
        LoadBindings(GetCurrentBindingSet())
        if sfui.common and sfui.common.print then
            sfui.common.print("keybinding changes discarded.")
        end
    end

    overlay:Hide()
    if bind.tooltip then bind.tooltip:Hide() end
    bind.currentButton = nil
    dialog:Hide()

    if sfui.actionbars and sfui.actionbars.UpdateAllBindings then
        sfui.actionbars.UpdateAllBindings()
    end
    if sfui.actionbars.mouseover and sfui.actionbars.mouseover.UpdateAllBars then
        sfui.actionbars.mouseover.UpdateAllBars()
    end
end

function sfui.actionbars.ToggleBindMode()
    if bind.isActive then
        sfui.actionbars.DeactivateBindMode(false)
    else
        sfui.actionbars.ActivateBindMode()
    end
end

function sfui.actionbars.IsBindModeActive()
    return bind.isActive == true
end
bind.IsActive = sfui.actionbars.IsBindModeActive

-- ─────────────────────────────────────────────────────────────────────────────
--  Combat Safety Watcher
-- ─────────────────────────────────────────────────────────────────────────────
local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:SetScript("OnEvent", function()
    if bind.isActive then
        sfui.actionbars.DeactivateBindMode(false)
        if sfui.common and sfui.common.print then
            sfui.common.print("quick keybind mode closed due to combat.")
        end
    end
end)

-- ─────────────────────────────────────────────────────────────────────────────
--  Blizzard QuickKeybind Mode Callbacks
-- ─────────────────────────────────────────────────────────────────────────────
if _G.EventRegistry and _G.EventRegistry.RegisterCallback then
    _G.EventRegistry:RegisterCallback("QuickKeybindFrame.QuickKeybindModeEnabled", function()
        if sfui.actionbars and sfui.actionbars.mouseover and sfui.actionbars.mouseover.UpdateAllBars then
            sfui.actionbars.mouseover.UpdateAllBars()
        end
    end)
    _G.EventRegistry:RegisterCallback("QuickKeybindFrame.QuickKeybindModeDisabled", function()
        if sfui.actionbars and sfui.actionbars.mouseover and sfui.actionbars.mouseover.UpdateAllBars then
            sfui.actionbars.mouseover.UpdateAllBars()
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Slash Commands
-- ─────────────────────────────────────────────────────────────────────────────
_G.SLASH_SFUIKEYBIND1 = "/kb"
_G.SLASH_SFUIKEYBIND2 = "/keybind"
_G.SLASH_SFUIKEYBIND3 = "/sfkeybind"
_G.SlashCmdList["SFUIKEYBIND"] = function()
    sfui.actionbars.ToggleBindMode()
end
