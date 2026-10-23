local addonName, addon = ...
sfui = sfui or {}
sfui.actionbars = sfui.actionbars or {}

local _G = _G
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local hooksecurefunc = _G.hooksecurefunc
local InCombatLockdown = _G.InCombatLockdown
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
            if bar.UnregisterAllEvents then
                bar:UnregisterAllEvents()
            end
            if bar.SetScript then
                bar:SetScript("OnEvent", nil)
                bar:SetScript("OnUpdate", nil)
                bar:SetScript("OnShow", nil)
                bar:SetScript("OnHide", nil)
            end
            if bar.UpdateShownButtons then
                bar.UpdateShownButtons = function() end
            end
            if bar.UpdateFrameStrata then
                bar.UpdateFrameStrata = function() end
            end
            if bar.SetShowGrid then
                bar.SetShowGrid = function() end
            end
            if bar.UpdateVisibility then
                bar.UpdateVisibility = function() end
            end
            if bar.IsInDefaultPosition then
                bar.IsInDefaultPosition = function() return false end
            end
        end
    end

    -- Reparent Blizzard's default MainMenuBarVehicleLeaveButton to UIParent so it is
    -- not suppressed alongside MainActionBar
    if _G.MainMenuBarVehicleLeaveButton then
        _G.MainMenuBarVehicleLeaveButton:SetParent(UIParent)
        if _G.MainMenuBarVehicleLeaveButton.IsInDefaultPosition then
            _G.MainMenuBarVehicleLeaveButton.IsInDefaultPosition = function() return false end
        end
    end

    -- Reparent Blizzard's default QueueStatusButton (LFG eye) to UIParent so it is
    -- not suppressed alongside MicroMenuContainer in retail
    if _G.QueueStatusButton then
        _G.QueueStatusButton:SetParent(UIParent)
    end

    -- Defuse MainActionBar and PetActionBar visibility/layout cascades.
    -- In retail, MainMenuBarVehicleLeaveButton:Update() calls PetActionBar:Show() whenever
    -- PetHasActionBar() is true. PetActionBar:Show() -> UpdateVisibility() ->
    -- EditModeManagerFrame:UpdateActionBarLayout() -> UpdateBottomActionBarPositions() ->
    -- MainActionBar:ClearAllPoints(), triggering [Blocked] MainActionBar:ClearAllPointsBase()
    -- in combat. Neutralizing Show/ShowOverride/UpdateVisibility and IsInDefaultPosition
    -- halts this cascade completely.
    if _G.MainActionBar then
        if _G.MainActionBar.UnregisterAllEvents then
            _G.MainActionBar:UnregisterAllEvents()
        end
        if _G.MainActionBar.SetScript then
            _G.MainActionBar:SetScript("OnEvent", nil)
            _G.MainActionBar:SetScript("OnUpdate", nil)
        end
        _G.MainActionBar.Show = function() end
        _G.MainActionBar.ShowOverride = function() end
        _G.MainActionBar.UpdateVisibility = function() end
        _G.MainActionBar.UpdateShownButtons = function() end
        _G.MainActionBar.UpdateFrameStrata = function() end
        _G.MainActionBar.SetShowGrid = function() end
        _G.MainActionBar.IsInDefaultPosition = function() return false end
    end

    if _G.PetActionBar then
        if _G.PetActionBar.UnregisterAllEvents then
            _G.PetActionBar:UnregisterAllEvents()
        end
        _G.PetActionBar:SetScript("OnEvent", nil)
        _G.PetActionBar:SetScript("OnUpdate", nil)
        _G.PetActionBar:SetScript("OnShow", nil)
        _G.PetActionBar:SetScript("OnHide", nil)
        _G.PetActionBar:SetAlpha(0)
        if _G.PetActionBar.EnableMouse then _G.PetActionBar:EnableMouse(false) end
        if _G.PetActionBar.UpdateShownButtons then
            _G.PetActionBar.UpdateShownButtons = function() end
        end
        _G.PetActionBar.Show = function() end
        _G.PetActionBar.ShowOverride = function() end
        _G.PetActionBar.UpdateVisibility = function() end
        _G.PetActionBar.IsInDefaultPosition = function() return false end
    end
    if _G.PetActionBarFrame then
        if _G.PetActionBarFrame.UnregisterAllEvents then
            _G.PetActionBarFrame:UnregisterAllEvents()
        end
        _G.PetActionBarFrame:SetScript("OnEvent", nil)
        _G.PetActionBarFrame:SetScript("OnUpdate", nil)
        _G.PetActionBarFrame:SetScript("OnShow", nil)
        _G.PetActionBarFrame:SetScript("OnHide", nil)
        _G.PetActionBarFrame:SetAlpha(0)
        if _G.PetActionBarFrame.EnableMouse then _G.PetActionBarFrame:EnableMouse(false) end
        if _G.PetActionBarFrame.UpdateShownButtons then
            _G.PetActionBarFrame.UpdateShownButtons = function() end
        end
        _G.PetActionBarFrame.Show = function() end
        _G.PetActionBarFrame.ShowOverride = function() end
        _G.PetActionBarFrame.UpdateVisibility = function() end
        _G.PetActionBarFrame.IsInDefaultPosition = function() return false end
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
        if frame and hooksecurefunc then
            hooksecurefunc(frame, "Show", function(self)
                self:SetAlpha(0)
                if self.EnableMouse then
                    pcall(self.EnableMouse, self, false)
                end
            end)
        end
    end

    -- Silence Blizzard's centralized action button event and update dispatchers so
    -- hidden native action buttons do not process events, waste CPU, or trigger
    -- secret value errors (e.g. cooldown:SetCooldown on ActionButton.lua:891).
    -- sfui uses LibActionButton-1.0 and its own pet bar engine which manage events independently.
    local actionDispatchers = {
        "ActionBarActionEventsFrame",
        "ActionBarButtonEventsFrame",
        "ActionBarButtonRangeCheckFrame",
        "ActionBarButtonUsableWatcherFrame",
    }
    local function silenceDispatchers()
        for _, name in ipairs(actionDispatchers) do
            local dispatcher = _G[name]
            if dispatcher then
                if dispatcher.UnregisterAllEvents then
                    dispatcher:UnregisterAllEvents()
                end
                dispatcher:SetScript("OnEvent", nil)
            end
        end
        if _G.ActionBarButtonUpdateFrame then
            _G.ActionBarButtonUpdateFrame:SetScript("OnUpdate", nil)
        end
    end
    silenceDispatchers()

    -- Camelot gamepad pet flyout guard (hunter / warlock):
    -- Blizzard_GamepadActionBars mixes PetActionFlyoutButtonMixin into
    -- GamepadMainActionBarFrame.PageUnit.LeftClassAction at login, but its popup
    -- (GamepadPetActionFlyout) is only assigned when ActionBarButtonEventsFrame
    -- relays PLAYER_ENTERING_WORLD -> UpdateAction -> UpdateFlyout. With the
    -- dispatcher silenced above, the popup stays nil and the button's own
    -- UNIT_FLAGS / PET_BAR_UPDATE handlers crash in ToggleFlash
    -- (PetActionFlyout.lua:156) whenever the pet attacks. Only its flash events
    -- are dropped (no fields or attributes written, so nothing is tainted), and only
    -- while the popup is actually missing.
    local function defuseGamepadPetFlash()
        local bar = _G.GamepadMainActionBarFrame
        local page = bar and bar.PageUnit
        local btn = page and page.LeftClassAction
        if not btn or not btn.IsPetAttacking or btn.popup then return end
        btn:UnregisterEvent("UNIT_FLAGS")
        btn:UnregisterEvent("PET_BAR_UPDATE")
    end

    if _G.EventUtil and _G.EventUtil.ContinueOnPlayerLogin then
        _G.EventUtil.ContinueOnPlayerLogin(function()
            silenceDispatchers()
            defuseGamepadPetFlash()
        end)
    end
    -- PLAYER_ENTERING_WORLD fires after every PLAYER_LOGIN callback, so Blizzard's
    -- mixin is guaranteed to be applied by then regardless of callback order.
    if sfui.events and sfui.events.RegisterEvent then
        sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", defuseGamepadPetFlash)
    end

    -- Hide native Blizzard action buttons
    -- NOTE: PetActionButton1..10 are NOT hidden here because they are managed on sfui_PetBar!
    -- NOTE: Do NOT call SetAttribute("statehidden", true) or UnregisterAllEvents() here,
    -- as modifying attributes on ActionButtonTemplate buttons taints execution and causes
    -- secret value errors during level up and combat.
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
            if btn and btn.Hide then
                btn:Hide()
            end
        end
    end
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


