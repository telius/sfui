local addonName, addon = ...
sfui = sfui or {}
sfui.actionbars = sfui.actionbars or {}

local _G = _G
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local hooksecurefunc = _G.hooksecurefunc
local ipairs = _G.ipairs
local pairs = _G.pairs

-- ─────────────────────────────────────────────────────────────────────────────
--  Offscreen Blizzard Action Bars Suppression (ElvUI / Bartender Pattern)
-- ─────────────────────────────────────────────────────────────────────────────
local function suppress_blizzard_actionbars()
    local Hider = CreateFrame("Frame", "sfui_ActionBarHider", UIParent, "SecureFrameTemplate")
    Hider:Hide()
    Hider:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, -9999)
    Hider:SetSize(1, 1)
    sfui.actionbars.Hider = Hider

    -- List of Blizzard action bar containers to move offscreen
    local blizzardBarNames = {
        "MainActionBar",
        "MainMenuBar",
        "MultiBarBottomLeft",
        "MultiBarBottomRight",
        "MultiBarRight",
        "MultiBarLeft",
        "MultiBar5",
        "MultiBar6",
        "MultiBar7",
        "OverrideActionBar",
        "StanceBar",
        "PetActionBar",
        "PossessActionBar",
        "StatusTrackingBarManager",
        "MainMenuBarArtFrame",
        "ShapeshiftBarFrame",
        "StanceBarFrame",
        "PetActionBarFrame",
        "PossessBarFrame",
        "GamepadMainActionBarFrame",
        "GamepadPetActionFlyout",
        "GamepadPetSpellFlyout",
        "GamepadSpellFlyout",
        "BagsBar",
        "MainMenuBarBagButtons",
        "MicroMenuContainer",
        "MicroMenu",
        "MainMenuBarMicroButtons",
    }

    -- Unload Blizzard ActionBarController to prevent Blizzard from attempting to update
    -- its bars and calling protected methods (SetAttribute) during combat shapeshifts / page transitions.
    if _G.ActionBarController and _G.ActionBarController.UnregisterAllEvents then
        _G.ActionBarController:UnregisterAllEvents()
        if _G.ActionBarController.RegisterEvent then
            _G.ActionBarController:RegisterEvent("SETTINGS_LOADED")
            _G.ActionBarController:RegisterEvent("UPDATE_EXTRA_ACTIONBAR")
        end
    end

    for _, name in ipairs(blizzardBarNames) do
        local bar = _G[name]
        if bar then
            bar:SetParent(Hider)
            if bar.HideBase then
                bar:HideBase()
            else
                bar:Hide()
            end
            if bar.UnregisterAllEvents and name ~= "MainActionBar" and name ~= "MainMenuBar" and name ~= "PetActionBar" and name ~= "PetActionBarFrame" then
                bar:UnregisterAllEvents()
            end
        end
    end

    -- Reparent Blizzard's default MainMenuBarVehicleLeaveButton to UIParent so it is
    -- not suppressed alongside MainActionBar
    if _G.MainMenuBarVehicleLeaveButton then
        _G.MainMenuBarVehicleLeaveButton:SetParent(UIParent)
    end

    -- Reparent Blizzard's default QueueStatusButton (LFG eye) to UIParent so it is
    -- not suppressed alongside MicroMenuContainer in retail
    if _G.QueueStatusButton then
        _G.QueueStatusButton:SetParent(UIParent)
    end

    if _G.PetActionBar then
        _G.PetActionBar:SetAlpha(0)
        if _G.PetActionBar.EnableMouse then _G.PetActionBar:EnableMouse(false) end
    end
    if _G.PetActionBarFrame then
        _G.PetActionBarFrame:SetAlpha(0)
        if _G.PetActionBarFrame.EnableMouse then _G.PetActionBarFrame:EnableMouse(false) end
    end

    local offscreenFrames = {
        "BagsBar",
        "MainMenuBarBagButtons",
        "MicroMenuContainer",
        "MicroMenu",
        "MainMenuBarMicroButtons",
    }
    for _, name in ipairs(offscreenFrames) do
        local frame = _G[name]
        if frame and frame.HookScript then
            frame:HookScript("OnShow", function(self)
                self:SetAlpha(0)
                if self.EnableMouse then
                    pcall(self.EnableMouse, self, false)
                end
            end)
        end
    end
    if _G.MicroMenu and hooksecurefunc then
        hooksecurefunc(_G.MicroMenu, "Layout", function(self)
            self:ClearAllPoints()
            self:SetPoint("BOTTOM", Hider, "BOTTOM", 0, 0)
        end)
    end
    if _G.BagsBar and hooksecurefunc then
        hooksecurefunc(_G.BagsBar, "Layout", function(self)
            self:ClearAllPoints()
            self:SetPoint("BOTTOM", Hider, "BOTTOM", 0, 0)
        end)
    end

    -- Suppress Gamepad action bar child page unit and flyout buttons (Camelot / Classic)
    local function suppressGamepadButtons()
        local gmb = _G.GamepadMainActionBarFrame
        local pageUnit = gmb and gmb.PageUnit
        if pageUnit then
            pageUnit:UnregisterAllEvents()
            local left = pageUnit.LeftClassAction
            if left then
                left:Hide()
                left:UnregisterAllEvents()
                if left.flashTicker then
                    left.flashTicker:Cancel()
                    left.flashTicker = nil
                end
                if left.Flash then left.Flash:Hide() end
            end
            local right = pageUnit.RightClassAction
            if right then
                right:Hide()
                right:UnregisterAllEvents()
                if right.rangeTicker then
                    right.rangeTicker:Cancel()
                    right.rangeTicker = nil
                end
            end
        end
    end
    suppressGamepadButtons()
    if _G.EventUtil and _G.EventUtil.ContinueOnPlayerLogin then
        _G.EventUtil.ContinueOnPlayerLogin(suppressGamepadButtons)
    end

    -- Disable individual Blizzard action buttons so they don't consume events or clicks
    -- NOTE: PetActionButton1..10 are NOT disabled here because they are managed on sfui_PetBar!
    local buttonPrefixes = {
        "ActionButton",
        "MultiBarBottomLeftButton",
        "MultiBarBottomRightButton",
        "MultiBarRightButton",
        "MultiBarLeftButton",
        "MultiBar5Button",
        "MultiBar6Button",
        "MultiBar7Button",
        "StanceButton",
    }
    for _, prefix in ipairs(buttonPrefixes) do
        for i = 1, 12 do
            local btn = _G[prefix .. i]
            if btn then
                btn:Hide()
                btn:UnregisterAllEvents()
                btn:SetAttribute("statehidden", true)
            end
        end
    end

    -- NOTE: ActionBarButtonEventsFrame and ActionBarActionEventsFrame are intentionally
    -- left untouched so Blizzard native cooldowns (secret values in 12.0+) and proc glows
    -- continue to execute in pure untainted Blizzard context without secret value errors.
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Module Registration & Lifecycle
-- ─────────────────────────────────────────────────────────────────────────────
local function get_actionbars_debug_info()
    local activeBars = 0
    local totalButtons = 0
    local allBars = sfui.actionbars.GetAllBars and sfui.actionbars.GetAllBars()
    if allBars then
        for _, bar in ipairs(allBars) do
            if bar and bar:IsShown() then
                activeBars = activeBars + 1
                if bar.buttons then
                    totalButtons = totalButtons + #bar.buttons
                end
            end
        end
    end
    return {
        activeBars = activeBars,
        totalButtons = totalButtons,
        unlocked = sfui.actionbars.moversUnlocked,
        petActive = sfui.actionbars.petBar and sfui.actionbars.petBar:IsShown() or false,
        mouseover = sfui.actionbars.mouseover and sfui.actionbars.mouseover.IsEnabled and sfui.actionbars.mouseover.IsEnabled() or false,
    }
end

function sfui.actionbars_debug_info()
    return get_actionbars_debug_info()
end

local ActionBarsModule = sfui.RegisterModule("actionbars", {
    OnInit = function(self)
        if sfui.db and sfui.db.RegisterDefaults and sfui.config.actionbars then
            sfui.db.RegisterDefaults("actionbars", sfui.config.actionbars)
        end

        -- Auto-migrate default bar settings for existing profiles:
        -- - bars 1-6 enabled by default
        -- - fade out on mouseover disabled by default
        if SfuiDB and not SfuiDB._actionbarsDefaultsV2 then
            if SfuiDB.actionbars and SfuiDB.actionbars.bars then
                local b = SfuiDB.actionbars.bars
                if b.bar5 and b.bar5.enabled == false and not SfuiDB._bar5Customized then
                    b.bar5.enabled = true
                end
                if b.bar6 and b.bar6.enabled == false and not SfuiDB._bar6Customized then
                    b.bar6.enabled = true
                end
                if b.bar3 and b.bar3.mouseover == true and not SfuiDB._bar3MouseoverCustomized then
                    b.bar3.mouseover = false
                end
                if b.bar4 and b.bar4.mouseover == true and not SfuiDB._bar4MouseoverCustomized then
                    b.bar4.mouseover = false
                end
            end
            SfuiDB._actionbarsDefaultsV2 = true
        end
    end,

    OnEnable = function(self)
        local modCfg = (sfui.db and sfui.db.Get and sfui.db.Get("actionbars")) or (sfui.config and sfui.config.actionbars) or {}
        if modCfg.enabled == false then return end

        suppress_blizzard_actionbars()
        sfui.actionbars.CreateBars()
    end,

    OnDisable = function(self)
        local allBars = sfui.actionbars.GetAllBars and sfui.actionbars.GetAllBars()
        if allBars then
            for _, bar in ipairs(allBars) do
                if bar then bar:Hide() end
            end
        end
    end,

    OnSettingsChanged = function(self, key, value)
        if key == "lockButtons" then
            if sfui.actionbars and sfui.actionbars.SetButtonsLocked then
                sfui.actionbars.SetButtonsLocked(value)
            end
            return
        end

        local bars = sfui.actionbars.bars
        if not bars then return end

        for i = 1, 10 do
            sfui.actionbars.ApplyBarLayout(i)
        end

        if sfui.actionbars.ApplyPetBarLayout then
            sfui.actionbars.ApplyPetBarLayout()
        end

        if sfui.actionbars.mouseover and sfui.actionbars.mouseover.UpdateAllBars then
            sfui.actionbars.mouseover.UpdateAllBars(true)
        end
    end,

    GetDebugInfo = get_actionbars_debug_info,
})

sfui.actionbars.GetDebugInfo = get_actionbars_debug_info

-- Convenience Global Aliases
function sfui.actionbars.ToggleMovers(forceState)
    if sfui.actionbars.movers and sfui.actionbars.movers.ToggleMovers then
        sfui.actionbars.movers.ToggleMovers(forceState)
    end
end

function sfui.actionbars.ResetPosition(barIndex)
    if sfui.actionbars.movers and sfui.actionbars.movers.ResetBarPosition then
        sfui.actionbars.movers.ResetBarPosition(barIndex)
    end
end

function sfui.actionbars.Apply3x4Preset(barIndex)
    if sfui.actionbars.bars and sfui.actionbars.ApplyBarLayout then
        local barKey = "bar" .. tostring(barIndex)
        if SfuiDB and SfuiDB.actionbars and SfuiDB.actionbars.bars and SfuiDB.actionbars.bars[barKey] then
            local cfg = SfuiDB.actionbars.bars[barKey]
            cfg.buttons = 12
            cfg.buttonsPerRow = 3
            cfg.buttonSize = 28
            cfg.spacing = 4
        end
        sfui.actionbars.ApplyBarLayout(barIndex)
    end
end

if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if sfui.actionbars and sfui.actionbars.ProcessDeferredLayouts then
            sfui.actionbars.ProcessDeferredLayouts()
        end
    end)
end


