local addonName, addon   = ...
local _addonName, _addon = addonName, addon

sfui                     = sfui or {}
sfui.hide                = sfui.hide or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/hide.lua
--  Blizzard Unit & HUD Frame Suppression & UI Error Filtering
--
--  Supports: Retail (Midnight 12.x / TWW 11.x), Camelot (Classic Forever),
--  and Classic Era.
--
--  Features:
--  - Safe Frame Suppression: Uses SetAlpha(0) and EnableMouse(false).
--    Never calls :Hide() inside OnShow hooks to guarantee 100% taint-free execution.
--  - Error Frame Filtering: Suppresses repetitive "spell is not ready yet" spam.
-- ══════════════════════════════════════════════════════════════════════════════

-- Localized APIs
local _G                 = _G
local InCombatLockdown   = _G.InCombatLockdown
local pairs              = _G.pairs
local ipairs             = _G.ipairs
local type               = _G.type
local pcall              = _G.pcall
local table_insert       = table.insert
local hooksecurefunc     = _G.hooksecurefunc
local CreateFrame        = _G.CreateFrame
local UIParent           = _G.UIParent
local GetTime            = _G.GetTime

-- Action Bars One-Time Alpha Recovery (ensures bars are 100% visible and untouched)
local ACTION_BAR_NAMES   = {
    "MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight",
    "MultiBarRight", "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7",
    "PetActionBar", "PetActionBarFrame", "StanceBar", "StanceBarFrame",
    "ShapeshiftBarFrame", "PossessActionBar", "PossessBarFrame",
}

local function RestoreAllBarsAlpha()
    if InCombatLockdown and InCombatLockdown() then return end
    local abMod = sfui.config and sfui.config.actionbars
    if SfuiDB and SfuiDB.actionbars and SfuiDB.actionbars.enabled ~= nil then
        if SfuiDB.actionbars.enabled then return end
    elseif abMod and abMod.enabled then
        return
    end
    for _, name in ipairs(ACTION_BAR_NAMES) do
        local bar = _G[name]
        if bar and bar.SetAlpha and bar.GetAlpha and bar:GetAlpha() ~= 1.0 then
            bar:SetAlpha(1.0)
        end
    end
end
sfui.hide.RefreshActionBars = RestoreAllBarsAlpha

-- Unit & HUD Frame Permanent Suppression Configurations
local HIDE_FRAMES           = {
    { key = "hide_player_frame", name = "PlayerFrame",        unit = "player",                                       label = "Player Frame" },
    { key = "hide_target_frame", name = "TargetFrame",        unit = "target",                                       label = "Target Frame" },
    { key = "hide_pet_frame",    name = "PetFrame",           unit = "pet",                                          label = "Pet Frame" },
    { key = "hide_focus_frame",  name = "FocusFrame",         unit = "focus",                                        label = "Focus Frame" },
    { key = "hide_micromenu",    name = "MicroMenuContainer", altNames = { "MicroMenu", "MainMenuBarMicroButtons" }, label = "Game Menu (Micro Menu)" },
    { key = "hide_bagsbar",      name = "BagsBar",            altNames = { "MainMenuBarBagButtons" },                label = "Bags Bar" },
    { key = "hide_totem_bar",    name = "TotemFrame",         altNames = { "MultiCastActionBarFrame", "TotemBar" },  label = "Totem Bar",             noAutoShow = true },
}

local defaults              = {
    hide_player_frame    = false,
    hide_target_frame    = false,
    hide_pet_frame       = false,
    hide_focus_frame     = false,
    hide_micromenu       = false,
    hide_bagsbar         = false,
    hide_totem_bar       = false,
    hide_cooldown_errors = true,
}

local function InitDB()
    SfuiDB = SfuiDB or {}
    for k, v in pairs(defaults) do
        if SfuiDB[k] == nil then
            SfuiDB[k] = v
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Blizzard Unit & HUD Frames Permanent Suppression (Taint-Free Alpha Pattern)
-- ─────────────────────────────────────────────────────────────────────────────
local HiddenFrame = CreateFrame("Frame", nil, UIParent)
HiddenFrame:SetPoint("BOTTOM")
HiddenFrame:SetSize(1, 1)
HiddenFrame:Hide()
sfui.hide.HiddenFrame = HiddenFrame

local function GetFramesForEntry(entry)
    local list = {}
    if entry.name and _G[entry.name] then
        table_insert(list, _G[entry.name])
    end
    if entry.altNames then
        for _, n in ipairs(entry.altNames) do
            local f = _G[n]
            if f and f ~= _G[entry.name] then
                table_insert(list, f)
            end
        end
    elseif entry.altName and _G[entry.altName] and _G[entry.altName] ~= _G[entry.name] then
        table_insert(list, _G[entry.altName])
    end
    return list
end

local hookedMultiCast = false

local function ShouldHide(key)
    if not SfuiDB then return false end
    if key == "hide_target_frame" then
        return (SfuiDB.hide_target_frame == true) or (SfuiDB.enableTargetBar ~= false)
    end
    return SfuiDB[key] == true
end

local function SilenceSelection(selection)
    if not selection then return end
    selection:Hide()
    if selection.SetAlpha then selection:SetAlpha(0) end
    if selection.EnableMouse then selection:EnableMouse(false) end
    if selection.EnableMouseClicks then selection:EnableMouseClicks(false) end
    if selection.EnableMouseMotion then selection:EnableMouseMotion(false) end
    if not selection._sfuiHooked then
        selection._sfuiHooked = true
        hooksecurefunc(selection, "Show", function(self)
            C_Timer.After(0, function()
                self:SetAlpha(0)
                self:EnableMouse(false)
            end)
        end)
    end
end

local function SuppressFrame(frame, entry)
    if not frame then return end
    frame.defaultHideSelection = true
    if frame.SetAlpha and (not frame.GetAlpha or frame:GetAlpha() ~= 0) then
        frame:SetAlpha(0)
    end
    local isProtected = frame.IsProtected and frame:IsProtected()
    if not isProtected and frame.EnableMouse and not (InCombatLockdown and InCombatLockdown()) then
        pcall(frame.EnableMouse, frame, false)
        if frame.EnableMouseClicks then pcall(frame.EnableMouseClicks, frame, false) end
        if frame.EnableMouseMotion then pcall(frame.EnableMouseMotion, frame, false) end
    end
    if frame.Selection then
        SilenceSelection(frame.Selection)
    end
    if frame.totFrame then
        frame.totFrame.defaultHideSelection = true
        if frame.totFrame.SetAlpha and (not frame.totFrame.GetAlpha or frame.totFrame:GetAlpha() ~= 0) then
            frame.totFrame:SetAlpha(0)
        end
        if not isProtected and frame.totFrame.EnableMouse and not (InCombatLockdown and InCombatLockdown()) then
            pcall(frame.totFrame.EnableMouse, frame.totFrame, false)
            if frame.totFrame.EnableMouseClicks then pcall(frame.totFrame.EnableMouseClicks, frame.totFrame, false) end
            if frame.totFrame.EnableMouseMotion then pcall(frame.totFrame.EnableMouseMotion, frame.totFrame, false) end
        end
        if frame.totFrame.Selection then
            SilenceSelection(frame.totFrame.Selection)
        end
    end
end

local function RestoreFrame(frame, entry)
    if not frame then return end
    frame.defaultHideSelection = false
    if frame.GetAlpha and frame:GetAlpha() ~= 1.0 then
        frame:SetAlpha(1.0)
    end
    local isProtected = frame.IsProtected and frame:IsProtected()
    if not isProtected and frame.EnableMouse and not (InCombatLockdown and InCombatLockdown()) then
        pcall(frame.EnableMouse, frame, true)
        if frame.EnableMouseClicks then pcall(frame.EnableMouseClicks, frame, true) end
        if frame.EnableMouseMotion then pcall(frame.EnableMouseMotion, frame, true) end
    end
    if frame.totFrame then
        frame.totFrame.defaultHideSelection = false
        if frame.totFrame.GetAlpha and frame.totFrame:GetAlpha() ~= 1.0 then
            frame.totFrame:SetAlpha(1.0)
        end
        if not isProtected and frame.totFrame.EnableMouse and not (InCombatLockdown and InCombatLockdown()) then
            pcall(frame.totFrame.EnableMouse, frame.totFrame, true)
            if frame.totFrame.EnableMouseClicks then pcall(frame.totFrame.EnableMouseClicks, frame.totFrame, true) end
            if frame.totFrame.EnableMouseMotion then pcall(frame.totFrame.EnableMouseMotion, frame.totFrame, true) end
        end
    end
end

local function ApplyUnitFrame(entry)
    local frames = GetFramesForEntry(entry)
    if #frames == 0 then return end

    local shouldHide = ShouldHide(entry.key)

    for _, frame in ipairs(frames) do
        if shouldHide then
            SuppressFrame(frame, entry)
        else
            RestoreFrame(frame, entry)
        end
    end
end

local function HookUnitFrames()
    -- MultiCastActionBarFrame for Classic / Camelot only
    if not sfui.isRetail and hooksecurefunc and _G.MultiCastActionBarFrame_Update and not hookedMultiCast then
        hookedMultiCast = true
        hooksecurefunc("MultiCastActionBarFrame_Update", function(self)
            if SfuiDB and SfuiDB.hide_totem_bar and self then
                self:SetAlpha(0)
                local isProtected = self.IsProtected and self:IsProtected()
                if not isProtected and self.EnableMouse and not InCombatLockdown() then
                    pcall(self.EnableMouse, self, false)
                end
            end
        end)
    end
end

-- Stubs & helpers for external modules
sfui.hide.SuppressFrame = SuppressFrame
sfui.hide.RestoreFrame = RestoreFrame

function sfui.hide.SuppressTargetFrame()
    local tf = _G.TargetFrame
    if tf then
        SuppressFrame(tf, { key = "hide_target_frame" })
    end
end

function sfui.hide.RestoreTargetFrame()
    local tf = _G.TargetFrame
    if tf then
        RestoreFrame(tf, { key = "hide_target_frame" })
    end
end


function sfui.hide.ApplyAllUnitFrames()
    HookUnitFrames()
    for _, entry in ipairs(HIDE_FRAMES) do
        ApplyUnitFrame(entry)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  UI Errors Frame Filtering (Spell/Ability Cooldown Spam)
-- ─────────────────────────────────────────────────────────────────────────────
function sfui.hide.ApplyErrorFilters()
    local enabled = SfuiDB and (SfuiDB.hide_cooldown_errors ~= false)
    local bl = _G.BLACK_LISTED_MESSAGE_TYPES

    local types = {
        _G.LE_GAME_ERR_SPELL_COOLDOWN,
        _G.LE_GAME_ERR_ABILITY_COOLDOWN,
        _G.LE_GAME_ERR_ITEM_COOLDOWN,
        _G.LE_GAME_ERR_OUT_OF_ENERGY,
    }

    local uie = _G.UIErrorsFrame
    for _, msgType in ipairs(types) do
        if msgType then
            if bl then
                bl[msgType] = enabled or nil
            end
            if uie and uie.SetMessageTypeEnabled then
                uie:SetMessageTypeEnabled(msgType, not enabled)
            end
        end
    end

    if uie and not uie._sfuiFiltered then
        uie._sfuiFiltered = true
        if uie.TryDisplayMessage then
            local origTryDisplay = uie.TryDisplayMessage
            uie.TryDisplayMessage = function(self, messageType, message, r, g, b)
                if SfuiDB and SfuiDB.hide_cooldown_errors then
                    if messageType and (
                            (_G.LE_GAME_ERR_SPELL_COOLDOWN and messageType == _G.LE_GAME_ERR_SPELL_COOLDOWN) or
                            (_G.LE_GAME_ERR_ABILITY_COOLDOWN and messageType == _G.LE_GAME_ERR_ABILITY_COOLDOWN) or
                            (_G.LE_GAME_ERR_ITEM_COOLDOWN and messageType == _G.LE_GAME_ERR_ITEM_COOLDOWN) or
                            (_G.LE_GAME_ERR_OUT_OF_ENERGY and messageType == _G.LE_GAME_ERR_OUT_OF_ENERGY)
                        ) then
                        return
                    end
                    if message and type(message) == "string" then
                        local lower = message:lower()
                        if message == _G.ERR_SPELL_COOLDOWN or
                            message == _G.ERR_ABILITY_COOLDOWN or
                            message == _G.ERR_ITEM_COOLDOWN or
                            message == _G.ERR_OUT_OF_ENERGY or
                            lower:find("not ready yet", 1, true) or
                            lower:find("not enough energy", 1, true) then
                            return
                        end
                    end
                end
                return origTryDisplay(self, messageType, message, r, g, b)
            end
        end

        if uie.AddMessage then
            local origAddMessage = uie.AddMessage
            uie.AddMessage = function(self, msg, r, g, b, a, messageType)
                if SfuiDB and SfuiDB.hide_cooldown_errors then
                    if messageType and (
                            (_G.LE_GAME_ERR_SPELL_COOLDOWN and messageType == _G.LE_GAME_ERR_SPELL_COOLDOWN) or
                            (_G.LE_GAME_ERR_ABILITY_COOLDOWN and messageType == _G.LE_GAME_ERR_ABILITY_COOLDOWN) or
                            (_G.LE_GAME_ERR_ITEM_COOLDOWN and messageType == _G.LE_GAME_ERR_ITEM_COOLDOWN) or
                            (_G.LE_GAME_ERR_OUT_OF_ENERGY and messageType == _G.LE_GAME_ERR_OUT_OF_ENERGY)
                        ) then
                        return
                    end
                    if msg and type(msg) == "string" then
                        local lower = msg:lower()
                        if msg == _G.ERR_SPELL_COOLDOWN or
                            msg == _G.ERR_ABILITY_COOLDOWN or
                            msg == _G.ERR_ITEM_COOLDOWN or
                            msg == _G.ERR_OUT_OF_ENERGY or
                            lower:find("not ready yet", 1, true) or
                            lower:find("not enough energy", 1, true) then
                            return
                        end
                    end
                end
                return origAddMessage(self, msg, r, g, b, a, messageType)
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Blizzard Edit Mode Exit Watcher & Reload Prompt
-- ─────────────────────────────────────────────────────────────────────────────
local _lastEditModeCloseTime = 0
local _pendingReloadPrompt   = false
local reloadPopupFrame       = nil

local function PurgeSfuiBug()
    if _G.sfuibug and _G.sfuibug.Clear then
        _G.sfuibug.Clear()
    elseif _G.SfuiBugDB then
        _G.SfuiBugDB.errors = {}
        _G.SfuiBugDB.order = {}
    end
end
sfui.hide.PurgeSfuiBug = PurgeSfuiBug

if _G.StaticPopupDialogs then
    _G.StaticPopupDialogs["SFUI_EDITMODE_RELOAD"] = {
        text = "blizzard edit mode was closed.\nreload ui to apply layout cleanly and prevent taint?",
        button1 = "reload ui",
        button2 = "later",
        OnAccept = function()
            PurgeSfuiBug()
            if _G.C_UI and _G.C_UI.Reload then
                _G.C_UI.Reload()
            elseif _G.ReloadUI then
                _G.ReloadUI()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

local function CreatePopupButton(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, h)
    b:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    b:SetBackdropColor(0.12, 0.12, 0.16, 0.95)
    b:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
    if onClick then b:SetScript("OnClick", onClick) end

    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER")
    fs:SetText(text)
    b.fs = fs

    b:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.20, 0.20, 0.28, 1)
        self:SetBackdropBorderColor(1, 1, 1, 1)
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.12, 0.12, 0.16, 0.95)
        local c = self._borderColor or { 0.3, 0.3, 0.35 }
        self:SetBackdropBorderColor(c[1], c[2], c[3], 1)
    end)

    if sfui.theme and sfui.theme.ApplyButtonStyle then
        pcall(sfui.theme.ApplyButtonStyle, b, false)
    end

    return b
end

local function GetOrCreateReloadPopup()
    if reloadPopupFrame then return reloadPopupFrame end

    local popup = CreateFrame("Frame", "sfui_EditModeReloadPopup", UIParent, "BackdropTemplate")
    popup:SetSize(400, 130)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    popup:SetFrameStrata("DIALOG")
    popup:SetFrameLevel(500)
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:SetMovable(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
    popup:Hide()

    popup:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    popup:SetBackdropColor(0.05, 0.05, 0.07, 0.95)

    local pal = (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()) or sfui.config.appearance or {}
    local accent = pal.accentColor or { 0.40, 0.00, 1.00, 1 }
    popup:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)

    if sfui.common and sfui.common.apply_flat_backdrop then
        pcall(sfui.common.apply_flat_backdrop, popup, { 0.05, 0.05, 0.07, 0.95 }, { accent[1], accent[2], accent[3], 1 })
    end

    if _G.UISpecialFrames then
        local exists = false
        for _, name in ipairs(_G.UISpecialFrames) do
            if name == "sfui_EditModeReloadPopup" then
                exists = true
                break
            end
        end
        if not exists then
            table_insert(_G.UISpecialFrames, "sfui_EditModeReloadPopup")
        end
    end

    local title = popup:CreateFontString(nil, "OVERLAY", (sfui.config and sfui.config.font) or "GameFontNormal")
    title:SetPoint("TOPLEFT", popup, "TOPLEFT", 14, -12)
    title:SetText("|cff9966ffsfui|r |cffffffffedit mode|r")

    local closeBtn = CreateFrame("Button", nil, popup)
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -6, -6)
    local closeFs = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    closeFs:SetPoint("CENTER")
    closeFs:SetText("|cffaaaaaax|r")
    closeBtn:SetScript("OnClick", function()
        popup:Hide()
    end)

    local msg = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    msg:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    msg:SetPoint("RIGHT", popup, "RIGHT", -14, 0)
    msg:SetJustifyH("LEFT")
    msg:SetSpacing(3)
    msg:SetText("blizzard edit mode was closed.\na ui reload is required to apply layout cleanly and prevent taint.\n|cff55ff55sfuibug error log has been purged.|r")

    local reloadBtn = CreatePopupButton(popup, "reload ui", 100, 24, function()
        PurgeSfuiBug()
        popup:Hide()
        if _G.C_UI and _G.C_UI.Reload then
            _G.C_UI.Reload()
        elseif _G.ReloadUI then
            _G.ReloadUI()
        end
    end)
    reloadBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -8, 14)
    reloadBtn._borderColor = { 0.2, 0.8, 0.3 }
    reloadBtn:SetBackdropBorderColor(0.2, 0.8, 0.3, 1)

    local laterBtn = CreatePopupButton(popup, "later", 80, 24, function()
        popup:Hide()
    end)
    laterBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOM", 8, 14)

    reloadPopupFrame = popup
    return popup
end

function sfui.hide.ShowEditModeReloadPopup()
    if InCombatLockdown and InCombatLockdown() then
        _pendingReloadPrompt = true
        return
    end

    local popup = GetOrCreateReloadPopup()
    if popup then
        local pal = (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()) or sfui.config.appearance or {}
        local accent = pal.accentColor or { 0.40, 0.00, 1.00, 1 }
        popup:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
        popup:Show()
    elseif _G.StaticPopup_Show then
        _G.StaticPopup_Show("SFUI_EDITMODE_RELOAD")
    end
end

function sfui.hide.OnBlizzardEditModeClosed()
    local now = (GetTime and GetTime()) or 0
    if now - _lastEditModeCloseTime < 0.8 then return end
    _lastEditModeCloseTime = now

    PurgeSfuiBug()

    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, function()
            if InCombatLockdown and InCombatLockdown() then
                _pendingReloadPrompt = true
            else
                sfui.hide.ShowEditModeReloadPopup()
            end
        end)
    else
        if InCombatLockdown and InCombatLockdown() then
            _pendingReloadPrompt = true
        else
            sfui.hide.ShowEditModeReloadPopup()
        end
    end
end

local function HookEditModeFrame()
    local emm = _G.EditModeManagerFrame
    if emm and not emm._sfuiCloseHooked then
        emm._sfuiCloseHooked = true
        hooksecurefunc(emm, "Hide", function()
            sfui.hide.OnBlizzardEditModeClosed()
        end)
        hooksecurefunc(emm, "ExitEditMode", function()
            sfui.hide.OnBlizzardEditModeClosed()
        end)
        emm:HookScript("OnHide", function()
            sfui.hide.OnBlizzardEditModeClosed()
        end)
    end
end

HookEditModeFrame()

if _G.EventRegistry and _G.EventRegistry.RegisterCallback then
    pcall(function()
        _G.EventRegistry:RegisterCallback("EditMode.Exit", function()
            sfui.hide.OnBlizzardEditModeClosed()
        end)
    end)
end

if _G.HideUIPanel then
    hooksecurefunc("HideUIPanel", function(frame)
        if frame and (frame == _G.EditModeManagerFrame or (frame.GetName and frame:GetName() == "EditModeManagerFrame")) then
            sfui.hide.OnBlizzardEditModeClosed()
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Module Registration & Lifecycle Protocol
-- ─────────────────────────────────────────────────────────────────────────────
sfui.hide.HIDE_FRAMES = HIDE_FRAMES

local function on_regen_enabled()
    -- When leaving combat, apply any deferred unitframe hide/show calls safely
    sfui.hide.ApplyAllUnitFrames()
    if _pendingReloadPrompt then
        _pendingReloadPrompt = false
        sfui.hide.ShowEditModeReloadPopup()
    end
end

local function on_player_entering_world()
    InitDB()
    RestoreAllBarsAlpha()
    HookUnitFrames()
    HookEditModeFrame()
    sfui.hide.ApplyAllUnitFrames()
    sfui.hide.ApplyErrorFilters()
end

local function init_module(self)
    local _ = self
    InitDB()
    RestoreAllBarsAlpha()
    HookUnitFrames()
    HookEditModeFrame()
    sfui.hide.ApplyAllUnitFrames()
    sfui.hide.ApplyErrorFilters()

    local function HookEditModeSelections()
        local emm = _G.EditModeManagerFrame
        if emm and not emm._sfuiSelectionsHooked then
            emm._sfuiSelectionsHooked = true
            hooksecurefunc(emm, "ShowSystemSelections", function()
                sfui.hide.ApplyAllUnitFrames()
            end)
            hooksecurefunc(emm, "UpdateSystems", function()
                sfui.hide.ApplyAllUnitFrames()
            end)
        end
    end
    HookEditModeSelections()

    sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", on_regen_enabled)
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", on_player_entering_world)
    sfui.events.RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", function()
        C_Timer.After(0, function()
            sfui.hide.ApplyAllUnitFrames()
        end)
    end)
    sfui.events.RegisterEvent("ADDON_LOADED", function(event, loadedAddon)
        if loadedAddon == "Blizzard_EditMode" then
            HookEditModeFrame()
            HookEditModeSelections()
            C_Timer.After(0, function()
                sfui.hide.ApplyAllUnitFrames()
            end)
        elseif loadedAddon == "Blizzard_Minimap" or loadedAddon == "Blizzard_ObjectiveTracker" then
            C_Timer.After(0, function()
                sfui.hide.ApplyAllUnitFrames()
            end)
        end
    end)
end

sfui.hide.OnInit = function(self)
    local _ = self
    InitDB()
end

sfui.hide.OnEnable = function(self)
    init_module(self)
end

sfui.hide.OnSettingsChanged = function(self, key, value)
    local _s, _k, _v = self, key, value
    sfui.hide.ApplyAllUnitFrames()
    sfui.hide.ApplyErrorFilters()
end

sfui.hide.GetDebugInfo = function(self)
    local _ = self
    local hiddenUnits = 0
    for _, u in ipairs(HIDE_FRAMES) do
        if SfuiDB and SfuiDB[u.key] then hiddenUnits = hiddenUnits + 1 end
    end
    return {
        hiddenUnitFrames = hiddenUnits,
        errorFilter      = SfuiDB and (SfuiDB.hide_cooldown_errors ~= false),
    }
end
function sfui.hide_debug_info()
    return sfui.hide:GetDebugInfo()
end

if sfui.RegisterModule then
    sfui.RegisterModule("hide", sfui.hide)
end
