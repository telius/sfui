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

local function SuppressFrame(frame, entry)
    if not frame then return end
    if frame.SetAlpha and (not frame.GetAlpha or frame:GetAlpha() ~= 0) then
        frame:SetAlpha(0)
    end
    local isProtected = frame.IsProtected and frame:IsProtected()
    if not isProtected and frame.EnableMouse and not (InCombatLockdown and InCombatLockdown()) then
        pcall(frame.EnableMouse, frame, false)
    end
    if frame.totFrame then
        if frame.totFrame.SetAlpha and (not frame.totFrame.GetAlpha or frame.totFrame:GetAlpha() ~= 0) then
            frame.totFrame:SetAlpha(0)
        end
        if not isProtected and frame.totFrame.EnableMouse and not (InCombatLockdown and InCombatLockdown()) then
            pcall(frame.totFrame.EnableMouse, frame.totFrame, false)
        end
    end
end

local function RestoreFrame(frame, entry)
    if not frame then return end
    if frame.GetAlpha and frame:GetAlpha() ~= 1.0 then
        frame:SetAlpha(1.0)
    end
    local isProtected = frame.IsProtected and frame:IsProtected()
    if not isProtected and frame.EnableMouse and not (InCombatLockdown and InCombatLockdown()) then
        pcall(frame.EnableMouse, frame, true)
    end
    if frame.totFrame then
        if frame.totFrame.GetAlpha and frame.totFrame:GetAlpha() ~= 1.0 then
            frame.totFrame:SetAlpha(1.0)
        end
        if not isProtected and frame.totFrame.EnableMouse and not (InCombatLockdown and InCombatLockdown()) then
            pcall(frame.totFrame.EnableMouse, frame.totFrame, true)
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
--  Module Registration & Lifecycle Protocol
-- ─────────────────────────────────────────────────────────────────────────────
sfui.hide.HIDE_FRAMES = HIDE_FRAMES

local function on_regen_enabled()
    -- When leaving combat, apply any deferred unitframe hide/show calls safely
    sfui.hide.ApplyAllUnitFrames()
end

local function on_player_entering_world()
    InitDB()
    RestoreAllBarsAlpha()
    HookUnitFrames()
    sfui.hide.ApplyAllUnitFrames()
    sfui.hide.ApplyErrorFilters()
end

local function init_module(self)
    local _ = self
    InitDB()
    RestoreAllBarsAlpha()
    HookUnitFrames()
    sfui.hide.ApplyAllUnitFrames()
    sfui.hide.ApplyErrorFilters()

    sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", on_regen_enabled)
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", on_player_entering_world)
    sfui.events.RegisterEvent("ADDON_LOADED", function(event, loadedAddon)
        if loadedAddon == "Blizzard_Minimap" or loadedAddon == "Blizzard_ObjectiveTracker" then
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
