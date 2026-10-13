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
    local Hider = CreateFrame("Frame", "sfui_ActionBarHider", UIParent)
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

    for _, name in ipairs(blizzardBarNames) do
        local bar = _G[name]
        if bar then
            bar:SetParent(Hider)
            bar:ClearAllPoints()
            bar:SetPoint("BOTTOM", Hider, "BOTTOM", 0, 0)
            bar:SetAlpha(0)
            if bar.EnableMouse then
                pcall(bar.EnableMouse, bar, false)
            end
            if bar.HideBase then
                bar:HideBase()
            else
                bar:Hide()
            end
        end
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

    -- Keep only ExtraActionButtons in ActionBarButtonEventsFrame
    if _G.ActionBarButtonEventsFrame and _G.ActionBarButtonEventsFrame.frames then
        hooksecurefunc(_G.ActionBarButtonEventsFrame, "RegisterFrame", function(added)
            local frames = _G.ActionBarButtonEventsFrame.frames
            if not frames then return end
            for index = #frames, 1, -1 do
                local frame = frames[index]
                if not added or frame == added then
                    local name = frame and frame.GetName and frame:GetName()
                    if name and not name:match("^ExtraActionButton%d") then
                        frames[index] = nil
                    end
                    if added and frame == added then break end
                end
            end
        end)

        local frames = _G.ActionBarButtonEventsFrame.frames
        for index = #frames, 1, -1 do
            local frame = frames[index]
            local name = frame and frame.GetName and frame:GetName()
            if name and not name:match("^ExtraActionButton%d") then
                frames[index] = nil
            end
        end
    end
    -- NOTE: ActionBarActionEventsFrame and ActionBarController are intentionally
    -- kept active so game engine spell overrides, procs, and icon events continue!
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Module Registration & Lifecycle
-- ─────────────────────────────────────────────────────────────────────────────
local ActionBarsModule = sfui.RegisterModule("actionbars", {
    OnInit = function(self)
        if sfui.db and sfui.db.RegisterDefaults and sfui.config.actionbars then
            sfui.db.RegisterDefaults("actionbars", sfui.config.actionbars)
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
        local bars = sfui.actionbars.bars
        if not bars then return end

        for i = 1, 6 do
            sfui.actionbars.ApplyBarLayout(i)
        end

        if sfui.actionbars.ApplyPetBarLayout then
            sfui.actionbars.ApplyPetBarLayout()
        end

        if sfui.actionbars.mouseover and sfui.actionbars.mouseover.UpdateAllBars then
            sfui.actionbars.mouseover.UpdateAllBars(true)
        end
    end,

    GetDebugInfo = function(self)
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
        }
    end,
})

sfui.actionbars.GetDebugInfo = function()
    return ActionBarsModule:GetDebugInfo()
end

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

