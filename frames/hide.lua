local addonName, addon   = ...
local _addonName, _addon = addonName, addon

sfui                     = sfui or {}
sfui.hide                = sfui.hide or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/hide.lua
--  Action Bars Mouseover Fading & Blizzard Unit/HUD Suppression
--
--  Supports: Retail (Midnight 12.x / TWW 11.x), Camelot (Classic Forever),
--  and Classic Era.
--
--  Features:
--  - Action Bars (MainActionBar, MultiBars, PetBar, StanceBar, PossessBar)
--    pure mouseover fading.
--  - Option to hide Player, Target, Pet, Focus unitframes, Game Menu, and Bags Bar.
--  - 100% Taint-Free: Action bar fading is performed via SetAlpha().
--  - Zero Action Button Hooking: Hover detection uses non-secure boundary checks.
--  - Safe Frame Suppression: Uses SetAlpha(0), EnableMouse(false), and
--    out-of-combat :Hide() with synchronous OnShow guards (§3.4 & §3.5).
--  - Ultra-Low CPU Architecture:
--    * Cursor position caching (GetCursorPosition): immediate early exit when
--      mouse is stationary and no animation is active.
--    * Adaptive tick rate: 12.5 FPS (0.08s) idle polling, switching to 50 FPS
--      (0.02s) only during active alpha transitions (~0.2s).
--    * Unregisters update loop completely when mouseover fading is disabled.
--    * Direct bar frame boundary check :IsMouseOver(6, -6, -6, 6) avoiding
--      redundant iterations across hundreds of action buttons.
--    * Zero global spellcast or combat event flooding.
-- ══════════════════════════════════════════════════════════════════════════════

-- Localized APIs
local _G                 = _G
local InCombatLockdown   = _G.InCombatLockdown
local UnitExists         = _G.UnitExists
local GetCursorPosition  = _G.GetCursorPosition
local tonumber           = _G.tonumber
local pairs              = _G.pairs
local ipairs             = _G.ipairs
local type               = _G.type
local pcall              = _G.pcall
local table_insert       = table.insert
local math_min           = math.min
local math_max           = math.max
local math_abs           = math.abs

-- Action Bar Configurations (Mouseover Fading)
local BARS               = {
    { key = "main",    dbKey = "actionbars_bar_main",    label = "Main Action Bar",         frames = { "MainActionBar", "MainMenuBar" } },
    { key = "bar2",    dbKey = "actionbars_bar_bar2",    label = "Action Bar 2 (Bottom L)", frames = { "MultiBarBottomLeft" } },
    { key = "bar3",    dbKey = "actionbars_bar_bar3",    label = "Action Bar 3 (Bottom R)", frames = { "MultiBarBottomRight" } },
    { key = "bar4",    dbKey = "actionbars_bar_bar4",    label = "Action Bar 4 (Right 1)",  frames = { "MultiBarRight" } },
    { key = "bar5",    dbKey = "actionbars_bar_bar5",    label = "Action Bar 5 (Right 2)",  frames = { "MultiBarLeft" } },
    { key = "bar6",    dbKey = "actionbars_bar_bar6",    label = "Action Bar 6",            frames = { "MultiBar5" } },
    { key = "bar7",    dbKey = "actionbars_bar_bar7",    label = "Action Bar 7",            frames = { "MultiBar6" } },
    { key = "bar8",    dbKey = "actionbars_bar_bar8",    label = "Action Bar 8",            frames = { "MultiBar7" } },
    { key = "pet",     dbKey = "actionbars_bar_pet",     label = "Pet Action Bar",          frames = { "PetActionBar", "PetActionBarFrame" } },
    { key = "stance",  dbKey = "actionbars_bar_stance",  label = "Stance / Shapeshift Bar", frames = { "StanceBar", "StanceBarFrame", "ShapeshiftBarFrame" } },
    { key = "possess", dbKey = "actionbars_bar_possess", label = "Possess Bar",             frames = { "PossessActionBar", "PossessBarFrame" } },
}

-- Unit & HUD Frame Permanent Suppression Configurations
local HIDE_FRAMES        = {
    { key = "hide_player_frame", name = "PlayerFrame",        unit = "player",                                       label = "Player Frame" },
    { key = "hide_target_frame", name = "TargetFrame",        unit = "target",                                       label = "Target Frame" },
    { key = "hide_pet_frame",    name = "PetFrame",           unit = "pet",                                          label = "Pet Frame" },
    { key = "hide_focus_frame",  name = "FocusFrame",         unit = "focus",                                        label = "Focus Frame" },
    { key = "hide_micromenu",    name = "MicroMenuContainer", altNames = { "MicroMenu", "MainMenuBarMicroButtons" }, label = "Game Menu (Micro Menu)" },
    { key = "hide_bagsbar",      name = "BagsBar",            altNames = { "MainMenuBarBagButtons" },                label = "Bags Bar" },
}

local defaults           = {
    actionbars_mouseover_enabled = true,
    actionbars_resting_alpha     = 0.0,
    actionbars_active_alpha      = 1.0,
    actionbars_fade_duration     = 0.2,

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

    hide_player_frame            = true,
    hide_target_frame            = true,
    hide_pet_frame               = false,
    hide_focus_frame             = false,
    hide_micromenu               = false,
    hide_bagsbar                 = false,
    hide_cooldown_errors         = true,
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
--  Action Bar Resolution
-- ─────────────────────────────────────────────────────────────────────────────
local function GetBarFrame(barDef)
    if barDef.frame then
        return barDef.frame
    end

    for _, name in ipairs(barDef.frames) do
        local f = _G[name]
        if f and type(f) == "table" and f.GetObjectType and f.IsShown then
            barDef.frame = f
            return f
        end
    end
    return nil
end

local function InitBars()
    for i = 1, #BARS do
        GetBarFrame(BARS[i])
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Action Bar Mouseover Fading Engine
-- ─────────────────────────────────────────────────────────────────────────────
local INTERVAL_IDLE   = 0.08 -- ~12.5 fps when idle (polling cursor hover)
local INTERVAL_FADING = 0.02 -- ~50 fps during active fade animation
local currentInterval = nil
local isLoopActive    = false
local isFading        = false
local lastCursorX     = -1
local lastCursorY     = -1

local UpdateActionBars

local function StartUpdateLoop(interval)
    if not isLoopActive or currentInterval ~= interval then
        sfui.events.RegisterUpdate("HideActionBars", interval, UpdateActionBars)
        currentInterval = interval
        isLoopActive = true
    end
end

local function StopUpdateLoop()
    if isLoopActive then
        sfui.events.UnregisterUpdate("HideActionBars")
        currentInterval = nil
        isLoopActive = false
    end
end

local function RestoreAllBarsAlpha()
    for i = 1, #BARS do
        local barDef = BARS[i]
        local bar = barDef.frame or GetBarFrame(barDef)
        if bar and bar.SetAlpha and bar.GetAlpha and bar:GetAlpha() ~= 1.0 then
            bar:SetAlpha(1.0)
        end
    end
end

UpdateActionBars = function(elapsed)
    if not SfuiDB or not SfuiDB.actionbars_mouseover_enabled then
        RestoreAllBarsAlpha()
        StopUpdateLoop()
        return
    end

    local curX, curY = GetCursorPosition()

    -- Early exit: if cursor has not moved and no fade transition is in progress, skip all work
    if curX == lastCursorX and curY == lastCursorY and not isFading then
        return
    end
    lastCursorX, lastCursorY = curX, curY

    local restingAlpha       = tonumber(SfuiDB.actionbars_resting_alpha) or 0.0
    local activeAlpha        = tonumber(SfuiDB.actionbars_active_alpha) or 1.0
    local duration           = tonumber(SfuiDB.actionbars_fade_duration) or 0.20
    if duration <= 0 then duration = 0.01 end
    local fadeSpeed = (math_max(activeAlpha, restingAlpha) - math_min(activeAlpha, restingAlpha)) / duration
    if fadeSpeed <= 0 then fadeSpeed = 10 end
    local step        = fadeSpeed * (elapsed or 0.02)

    local stillFading = false

    for i = 1, #BARS do
        local barDef = BARS[i]
        local isEnabled = SfuiDB[barDef.dbKey] ~= false
        local bar = barDef.frame or GetBarFrame(barDef)

        if bar and bar.IsShown and bar.SetAlpha and bar.GetAlpha then
            if isEnabled and bar:IsShown() then
                local isHovered = bar:IsMouseOver(6, -6, -6, 6)
                local targetAlpha = isHovered and activeAlpha or restingAlpha
                local curAlpha = bar:GetAlpha()
                local diff = targetAlpha - curAlpha
                local absDiff = math_abs(diff)

                if absDiff > 0.005 then
                    if step >= absDiff then
                        bar:SetAlpha(targetAlpha)
                    else
                        stillFading = true
                        if diff > 0 then
                            bar:SetAlpha(curAlpha + step)
                        else
                            bar:SetAlpha(curAlpha - step)
                        end
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

    -- Throttle dispatcher interval dynamically: 50 fps while fading, 12.5 fps when idle
    if stillFading ~= isFading then
        isFading = stillFading
        local neededInterval = isFading and INTERVAL_FADING or INTERVAL_IDLE
        if currentInterval ~= neededInterval then
            StartUpdateLoop(neededInterval)
        end
    end
end

function sfui.hide.RefreshActionBars()
    lastCursorX, lastCursorY = -1, -1
    isFading = true
    if SfuiDB and SfuiDB.actionbars_mouseover_enabled then
        StartUpdateLoop(INTERVAL_FADING)
        UpdateActionBars(0.5)
    else
        RestoreAllBarsAlpha()
        StopUpdateLoop()
    end
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
        local isProtected = frame.IsProtected and frame:IsProtected()
        if shouldHide then
            frame:SetAlpha(0)
            if not isProtected and frame.EnableMouse then
                pcall(frame.EnableMouse, frame, false)
            end

            if not InCombatLockdown() and frame:IsShown() then
                frame:Hide()
            end
        else
            frame:SetAlpha(1)

            if not isProtected and frame.EnableMouse then
                pcall(frame.EnableMouse, frame, true)
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
                        if not (self.IsProtected and self:IsProtected()) and self.EnableMouse then
                            pcall(self.EnableMouse, self, false)
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
--  UI Errors Frame Filtering (Spell/Ability Cooldown Spam)
-- ─────────────────────────────────────────────────────────────────────────────
function sfui.hide.ApplyErrorFilters()
    local enabled = SfuiDB and (SfuiDB.hide_cooldown_errors ~= false)
    local bl = _G.BLACK_LISTED_MESSAGE_TYPES

    local types = {
        _G.LE_GAME_ERR_SPELL_COOLDOWN,
        _G.LE_GAME_ERR_ABILITY_COOLDOWN,
        _G.LE_GAME_ERR_ITEM_COOLDOWN,
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
                            (_G.LE_GAME_ERR_ITEM_COOLDOWN and messageType == _G.LE_GAME_ERR_ITEM_COOLDOWN)
                        ) then
                        return
                    end
                    if message and type(message) == "string" and (
                            message == _G.ERR_SPELL_COOLDOWN or
                            message == _G.ERR_ABILITY_COOLDOWN or
                            message == _G.ERR_ITEM_COOLDOWN or
                            message:find("not ready yet", 1, true)
                        ) then
                        return
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
                            (_G.LE_GAME_ERR_ITEM_COOLDOWN and messageType == _G.LE_GAME_ERR_ITEM_COOLDOWN)
                        ) then
                        return
                    end
                    if msg and type(msg) == "string" and (
                            msg == _G.ERR_SPELL_COOLDOWN or
                            msg == _G.ERR_ABILITY_COOLDOWN or
                            msg == _G.ERR_ITEM_COOLDOWN or
                            msg:find("not ready yet", 1, true)
                        ) then
                        return
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
sfui.hide.BARS = BARS
sfui.hide.HIDE_FRAMES = HIDE_FRAMES

local function on_regen_enabled()
    -- When leaving combat, apply any deferred unitframe hide/show calls safely
    sfui.hide.ApplyAllUnitFrames()
end

local function on_player_entering_world()
    InitDB()
    InitBars()
    HookUnitFrames()
    sfui.hide.ApplyAllUnitFrames()
    sfui.hide.RefreshActionBars()
    sfui.hide.ApplyErrorFilters()
end

local function init_module(self)
    local _ = self
    InitDB()
    InitBars()
    HookUnitFrames()
    sfui.hide.ApplyAllUnitFrames()
    sfui.hide.ApplyErrorFilters()

    if SfuiDB and SfuiDB.actionbars_mouseover_enabled then
        StartUpdateLoop(INTERVAL_IDLE)
        sfui.hide.RefreshActionBars()
    end

    sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", on_regen_enabled)
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", on_player_entering_world)
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
    sfui.hide.RefreshActionBars()
    sfui.hide.ApplyErrorFilters()
end

sfui.hide.GetDebugInfo = function(self)
    local _ = self
    local hiddenUnits = 0
    for _, u in ipairs(HIDE_FRAMES) do
        if SfuiDB and SfuiDB[u.key] then hiddenUnits = hiddenUnits + 1 end
    end
    return {
        mouseoverEnabled = SfuiDB and SfuiDB.actionbars_mouseover_enabled or false,
        hiddenUnitFrames = hiddenUnits,
        isLoopActive     = isLoopActive,
        currentInterval  = currentInterval,
        isFading         = isFading,
    }
end

if sfui.RegisterModule then
    sfui.RegisterModule("hide", sfui.hide)
end
