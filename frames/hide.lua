local addonName, addon = ...
sfui = sfui or {}
sfui.hide = sfui.hide or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/hide.lua
--  Action Bars & Menus Mouseover Fading & Blizzard Unit/HUD Suppression
--
--  Supports: Retail (Midnight 12.x / TWW 11.x), Camelot (Classic Forever),
--  and Classic Era.
--
--  Features:
--  - Action Bars & Menus (MainActionBar, MultiBars, PetBar, StanceBar,
--    PossessBar, Game Menu / MicroMenu, BagsBar) mouseover fading.
--  - Option to hide Player, Target, Pet, Focus unitframes, Game Menu, and Bags Bar.
--  - 100% Taint-Free: Action bar and menu fading is performed via SetAlpha().
--  - Zero Action Button Hooking: Hover detection uses non-secure boundary checks.
--  - Safe Frame Suppression: Uses SetAlpha(0), EnableMouse(false), and
--    out-of-combat :Hide() with synchronous OnShow guards (§3.4 & §3.5).
-- ══════════════════════════════════════════════════════════════════════════════

local g      = sfui.config
local common = sfui.common

-- Localized APIs
local _G                 = _G
local CreateFrame        = _G.CreateFrame
local InCombatLockdown   = _G.InCombatLockdown
local UnitExists         = _G.UnitExists
local UnitCastingInfo    = _G.UnitCastingInfo or (_G.C_Spell and _G.C_Spell.GetSpellCastInfo)
local UnitChannelInfo    = _G.UnitChannelInfo or (_G.C_Spell and _G.C_Spell.GetSpellChannelInfo)
local GetCursorInfo      = _G.GetCursorInfo
local select             = _G.select
local tonumber           = _G.tonumber
local pairs              = _G.pairs
local ipairs             = _G.ipairs
local type               = _G.type
local table_insert       = table.insert
local math_min           = math.min
local math_max           = math.max
local math_abs           = math.abs

-- Action Bar Configurations (Mouseover Fading)
local BARS = {
    { key = "main",      label = "Main Action Bar",         frames = { "MainActionBar", "MainMenuBar" } },
    { key = "bar2",      label = "Action Bar 2 (Bottom L)", frames = { "MultiBarBottomLeft" } },
    { key = "bar3",      label = "Action Bar 3 (Bottom R)", frames = { "MultiBarBottomRight" } },
    { key = "bar4",      label = "Action Bar 4 (Right 1)",  frames = { "MultiBarRight" } },
    { key = "bar5",      label = "Action Bar 5 (Right 2)",  frames = { "MultiBarLeft" } },
    { key = "bar6",      label = "Action Bar 6",            frames = { "MultiBar5" } },
    { key = "bar7",      label = "Action Bar 7",            frames = { "MultiBar6" } },
    { key = "bar8",      label = "Action Bar 8",            frames = { "MultiBar7" } },
    { key = "pet",       label = "Pet Action Bar",          frames = { "PetActionBar", "PetActionBarFrame" } },
    { key = "stance",    label = "Stance / Shapeshift Bar", frames = { "StanceBar", "StanceBarFrame", "ShapeshiftBarFrame" } },
    { key = "possess",   label = "Possess Bar",             frames = { "PossessActionBar", "PossessBarFrame" } },
}

-- Unit & HUD Frame Permanent Suppression Configurations
local HIDE_FRAMES = {
    { key = "hide_player_frame", name = "PlayerFrame",        unit = "player", label = "Player Frame" },
    { key = "hide_target_frame", name = "TargetFrame",        unit = "target", label = "Target Frame" },
    { key = "hide_pet_frame",    name = "PetFrame",           unit = "pet",    label = "Pet Frame" },
    { key = "hide_focus_frame",  name = "FocusFrame",         unit = "focus",  label = "Focus Frame" },
    { key = "hide_micromenu",    name = "MicroMenuContainer", altNames = { "MicroMenu", "MainMenuBarMicroButtons" }, label = "Game Menu (Micro Menu)" },
    { key = "hide_bagsbar",      name = "BagsBar",            altNames = { "MainMenuBarBagButtons" }, label = "Bags Bar" },
}

local resolvedBars = {}
local defaults = {
    actionbars_mouseover_enabled = true,
    actionbars_resting_alpha     = 0.0,
    actionbars_active_alpha      = 1.0,
    actionbars_fade_duration     = 0.2,
    actionbars_show_combat       = true,
    actionbars_show_target       = false,
    actionbars_show_cast         = false,

    actionbars_bar_main          = true,
    actionbars_bar_bar2          = true,
    actionbars_bar_bar3          = true,
    actionbars_bar_bar4          = true,
    actionbars_bar_bar5          = true,
    actionbars_bar_bar6          = true,
    actionbars_bar_bar7          = true,
    actionbars_bar_bar8          = true,
    actionbars_bar_pet           = true,
    actionbars_bar_stance        = true,
    actionbars_bar_possess       = true,

    hide_player_frame            = false,
    hide_target_frame            = false,
    hide_pet_frame               = false,
    hide_focus_frame             = false,
    hide_micromenu               = false,
    hide_bagsbar                 = false,
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
--  Action Bar Resolution & Boundary Detection
-- ─────────────────────────────────────────────────────────────────────────────
local function GetBarFrame(barDef)
    local cached = resolvedBars[barDef.key]
    if cached and cached.GetName and _G[cached:GetName()] then
        return cached
    end

    for _, name in ipairs(barDef.frames) do
        local f = _G[name]
        if f and type(f) == "table" and f.GetObjectType and f.IsShown then
            resolvedBars[barDef.key] = f
            return f
        end
    end
    return nil
end

local function IsMouseOverBar(bar)
    if not bar or not bar:IsShown() then return false end

    -- 6px margin to bridge gaps cleanly without flicker
    if bar:IsMouseOver(6, -6, -6, 6) then
        return true
    end

    -- Direct button check if bar buttons are managed in an array
    if bar.actionButtons and type(bar.actionButtons) == "table" then
        for i = 1, #bar.actionButtons do
            local btn = bar.actionButtons[i]
            if btn and btn.IsShown and btn:IsShown() and btn.IsMouseOver and btn:IsMouseOver() then
                return true
            end
        end
    end

    return false
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Action Bar & Menu Mouseover Fading Engine
-- ─────────────────────────────────────────────────────────────────────────────
local pendingRestores = false

local function UpdateActionBars(elapsed)
    if not SfuiDB or not SfuiDB.actionbars_mouseover_enabled then
        if pendingRestores then
            pendingRestores = false
            for _, barDef in ipairs(BARS) do
                local bar = GetBarFrame(barDef)
                if bar and bar.SetAlpha then
                    bar:SetAlpha(1.0)
                end
            end
        end
        return
    end

    pendingRestores = true

    local restingAlpha = tonumber(SfuiDB.actionbars_resting_alpha) or 0.0
    local activeAlpha  = tonumber(SfuiDB.actionbars_active_alpha) or 1.0
    local duration     = tonumber(SfuiDB.actionbars_fade_duration) or 0.20
    if duration <= 0 then duration = 0.01 end
    local fadeSpeed    = (math_max(activeAlpha, restingAlpha) - math_min(activeAlpha, restingAlpha)) / duration
    if fadeSpeed <= 0 then fadeSpeed = 10 end

    local inCombat     = InCombatLockdown()
    local hasTarget    = UnitExists("target")
    local isCasting    = false
    if UnitCastingInfo and UnitCastingInfo("player") then
        isCasting = true
    elseif UnitChannelInfo and UnitChannelInfo("player") then
        isCasting = true
    end
    local isCursorHolding = (GetCursorInfo and GetCursorInfo() ~= nil)

    local globalShow = (inCombat and SfuiDB.actionbars_show_combat)
                    or (hasTarget and SfuiDB.actionbars_show_target)
                    or (isCasting and SfuiDB.actionbars_show_cast)
                    or isCursorHolding

    for _, barDef in ipairs(BARS) do
        local bar = GetBarFrame(barDef)
        if bar and bar.IsShown and bar.SetAlpha and bar.GetAlpha then
            local isEnabled = SfuiDB["actionbars_bar_" .. barDef.key] ~= false

            if isEnabled and bar:IsShown() then
                local isHovered = IsMouseOverBar(bar)
                local targetAlpha = (isHovered or globalShow) and activeAlpha or restingAlpha
                local curAlpha = bar:GetAlpha()

                if math_abs(curAlpha - targetAlpha) > 0.01 then
                    local step = fadeSpeed * (elapsed or 0.02)
                    if curAlpha < targetAlpha then
                        bar:SetAlpha(math_min(targetAlpha, curAlpha + step))
                    else
                        bar:SetAlpha(math_max(targetAlpha, curAlpha - step))
                    end
                elseif curAlpha ~= targetAlpha then
                    bar:SetAlpha(targetAlpha)
                end
            elseif not isEnabled then
                if bar:GetAlpha() ~= 1.0 then
                    bar:SetAlpha(1.0)
                end
            end
        end
    end
end

function sfui.hide.RefreshActionBars()
    UpdateActionBars(0.5)
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Blizzard Unit & HUD Frames Permanent Suppression
-- ─────────────────────────────────────────────────────────────────────────────
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

local function ApplyUnitFrame(entry)
    local frames = GetFramesForEntry(entry)
    if #frames == 0 then return end

    local shouldHide = SfuiDB and (SfuiDB[entry.key] == true)

    for _, frame in ipairs(frames) do
        if shouldHide then
            frame:SetAlpha(0)
            if frame.EnableMouse then
                frame:EnableMouse(false)
            end

            if not InCombatLockdown() and frame:IsShown() then
                frame:Hide()
            end
        else
            frame:SetAlpha(1)

            if frame.EnableMouse then
                frame:EnableMouse(true)
            end

            if not InCombatLockdown() and not frame:IsShown() then
                if entry.unit == "player" or (entry.unit and UnitExists(entry.unit)) or not entry.unit then
                    frame:Show()
                end
            end
        end
    end
end

function sfui.hide.ApplyAllUnitFrames()
    for _, entry in ipairs(HIDE_FRAMES) do
        ApplyUnitFrame(entry)
    end
end

local function HookUnitFrames()
    for _, entry in ipairs(HIDE_FRAMES) do
        local frames = GetFramesForEntry(entry)
        for _, frame in ipairs(frames) do
            if frame and frame.HookScript and not frame._sfuiHideHooked then
                frame._sfuiHideHooked = true
                frame:HookScript("OnShow", function(self)
                    if SfuiDB and SfuiDB[entry.key] == true then
                        self:SetAlpha(0)
                        if self.EnableMouse then
                            self:EnableMouse(false)
                        end
                        if not InCombatLockdown() then
                            self:Hide()
                        end
                    end
                end)
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Module Registration & Lifecycle Protocol
-- ─────────────────────────────────────────────────────────────────────────────
sfui.hide.BARS = BARS
sfui.hide.HIDE_FRAMES = HIDE_FRAMES

local function on_regen_enabled()
    -- When leaving combat, apply any deferred unitframe hide/show calls safely
    sfui.hide.ApplyAllUnitFrames()
end

local function on_player_entering_world()
    InitDB()
    HookUnitFrames()
    sfui.hide.ApplyAllUnitFrames()
    sfui.hide.RefreshActionBars()
end

local function on_combat_state()
    sfui.hide.RefreshActionBars()
end

local function init_module(self)
    InitDB()
    HookUnitFrames()
    sfui.hide.ApplyAllUnitFrames()

    -- Register throttled action bar & menu mouseover updater (~50fps)
    sfui.events.RegisterUpdate("HideActionBars", 0.02, UpdateActionBars)

    -- Register combat and state change listeners
    sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED",  on_regen_enabled)
    sfui.events.RegisterEvent("PLAYER_REGEN_DISABLED", on_combat_state)
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", on_player_entering_world)
    sfui.events.RegisterEvent("PLAYER_TARGET_CHANGED", on_combat_state)
    sfui.events.RegisterEvent("UNIT_SPELLCAST_START",  on_combat_state)
    sfui.events.RegisterEvent("UNIT_SPELLCAST_STOP",   on_combat_state)
    sfui.events.RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", on_combat_state)
    sfui.events.RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP",  on_combat_state)
    sfui.events.RegisterEvent("CURSOR_CHANGED",        on_combat_state)
end

sfui.hide.OnInit = function(self)
    InitDB()
end

sfui.hide.OnEnable = function(self)
    init_module(self)
end

sfui.hide.OnSettingsChanged = function(self, key, value)
    sfui.hide.ApplyAllUnitFrames()
    sfui.hide.RefreshActionBars()
end

sfui.hide.GetDebugInfo = function(self)
    local hiddenUnits = 0
    for _, u in ipairs(HIDE_FRAMES) do
        if SfuiDB and SfuiDB[u.key] then hiddenUnits = hiddenUnits + 1 end
    end
    return {
        mouseoverEnabled = SfuiDB and SfuiDB.actionbars_mouseover_enabled or false,
        hiddenUnitFrames = hiddenUnits,
    }
end

if sfui.RegisterModule then
    sfui.RegisterModule("hide", sfui.hide)
end
