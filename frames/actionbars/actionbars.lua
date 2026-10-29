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
--  Offscreen Blizzard Action Bars Suppression (Bartender4 Pattern)
-- ─────────────────────────────────────────────────────────────────────────────
--  Blizzard Action Bar Suppression (ElvUI Untaint Pattern)
-- ─────────────────────────────────────────────────────────────────────────────
-- ─────────────────────────────────────────────────────────────────────────────
--  Blizzard Action Bar Full Disposal & Edit Mode Decoupling
-- ─────────────────────────────────────────────────────────────────────────────
local hiddenParent = (sfui.hide and sfui.hide.HiddenFrame)
if not hiddenParent then
    hiddenParent = CreateFrame("Frame", "SfuiActionBarsHiddenDump", UIParent)
    hiddenParent:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 0, -10000)
    hiddenParent:SetSize(1, 1)
    hiddenParent:Hide()
end

local _editModeCallbacksRegistered = false

local function SilenceSelection(selection)
    if not selection then return end
    if selection.SetAlpha then selection:SetAlpha(0) end
    if selection.EnableMouse then selection:EnableMouse(false) end
    if selection.EnableMouseClicks then selection:EnableMouseClicks(false) end
    if selection.EnableMouseMotion then selection:EnableMouseMotion(false) end
end

local function KillPagerMouse(bar)
    local pager = bar and bar.ActionBarPageNumber
    if not pager then return end
    local function killOne(f)
        if not f or type(f.IsMouseEnabled) ~= "function" then return end
        f:EnableMouse(false)
        if f.EnableMouseClicks then f:EnableMouseClicks(false) end
        if f.EnableMouseMotion then f:EnableMouseMotion(false) end
    end
    killOne(pager)
    killOne(pager.UpButton)
    killOne(pager.DownButton)
    if type(pager.GetChildren) == "function" then
        for i = 1, pager:GetNumChildren() do
            killOne((select(i, pager:GetChildren())))
        end
    end
end

local function QuietButton(btn)
    if not btn then return end
    if btn.UnregisterAllEvents then btn:UnregisterAllEvents() end
    if btn.EnableMouse then btn:EnableMouse(false) end
    if btn.EnableMouseClicks then btn:EnableMouseClicks(false) end
    if btn.EnableMouseMotion then btn:EnableMouseMotion(false) end
    if btn.SetAlpha then btn:SetAlpha(0) end
end

local function QuietContainer(container)
    if not container then return end
    if container.EnableMouse then container:EnableMouse(false) end
    if container.EnableMouseClicks then container:EnableMouseClicks(false) end
    if container.EnableMouseMotion then container:EnableMouseMotion(false) end
    if container.SetAlpha then container:SetAlpha(0) end
end

local BAR_BUTTON_PATTERNS = {
    { bar = "MainActionBar", prefix = "ActionButton", count = 12 },
    { bar = "MultiBarBottomLeft", prefix = "MultiBarBottomLeftButton", count = 12 },
    { bar = "MultiBarBottomRight", prefix = "MultiBarBottomRightButton", count = 12 },
    { bar = "MultiBarLeft", prefix = "MultiBarLeftButton", count = 12 },
    { bar = "MultiBarRight", prefix = "MultiBarRightButton", count = 12 },
    { bar = "MultiBar5", prefix = "MultiBar5Button", count = 12 },
    { bar = "MultiBar6", prefix = "MultiBar6Button", count = 12 },
    { bar = "MultiBar7", prefix = "MultiBar7Button", count = 12 },
    { bar = "StanceBar", prefix = "StanceButton", count = 10 },
    { bar = "PetActionBar", prefix = "PetActionButton", count = 10 },
    { bar = "PossessActionBar", prefix = "PossessButton", count = 10 },
}

local UNTAINT_BARS = {
    "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight",
    "MultiBar5", "MultiBar6", "MultiBar7", "MultiBarLeft", "MultiBarRight",
    "MicroButtonAndBagsBar", "OverrideActionBar", "MainMenuBar", "StanceBar",
    "PetActionBar", "PossessActionBar", "MainMenuBarArtFrame",
    "ShapeshiftBarFrame", "StanceBarFrame", "PetActionBarFrame",
    "PossessBarFrame", "MultiCastActionBarFrame", "MainMenuBarVehicleLeaveButton",
}

local function suppress_blizzard_actionbars()
    if InCombatLockdown and InCombatLockdown() then
        if sfui.common and sfui.common.run_after_combat then
            sfui.common.run_after_combat(suppress_blizzard_actionbars)
        end
        return
    end

    -- 1. MainActionBar
    local mainBar = _G.MainActionBar
    if mainBar then
        if mainBar.SetAlpha then mainBar:SetAlpha(0) end
        if mainBar.EnableMouse then mainBar:EnableMouse(false) end
        if mainBar.EnableMouseClicks then mainBar:EnableMouseClicks(false) end
        if mainBar.EnableMouseMotion then mainBar:EnableMouseMotion(false) end
        KillPagerMouse(mainBar)
        if mainBar.Selection then SilenceSelection(mainBar.Selection) end
        if mainBar.BorderArt and mainBar.BorderArt.SetAlpha then mainBar.BorderArt:SetAlpha(0) end
        if mainBar.QuickKeybindGlow and mainBar.QuickKeybindGlow.SetAlpha then mainBar.QuickKeybindGlow:SetAlpha(0) end
        if mainBar.QuickKeybindBottomShadow and mainBar.QuickKeybindBottomShadow.SetAlpha then mainBar.QuickKeybindBottomShadow:SetAlpha(0) end
        if mainBar.QuickKeybindRightShadow and mainBar.QuickKeybindRightShadow.SetAlpha then mainBar.QuickKeybindRightShadow:SetAlpha(0) end

        local caps = mainBar.EndCaps
        if caps then
            if caps.SetAlpha then caps:SetAlpha(0) end
            if caps.LeftEndCap and caps.LeftEndCap.Selection then
                SilenceSelection(caps.LeftEndCap.Selection)
            end
            if caps.RightEndCap and caps.RightEndCap.Selection then
                SilenceSelection(caps.RightEndCap.Selection)
            end
        end

        if mainBar:GetParent() ~= hiddenParent then
            mainBar:SetParent(hiddenParent)
        end
    end

    -- 2. Reparent to hiddenParent and silence all secondary action bars without mutating anchor points
    for _, name in ipairs(UNTAINT_BARS) do
        local bar = _G[name]
        if bar then
            if bar.SetAlpha then bar:SetAlpha(0) end
            if bar.EnableMouse then bar:EnableMouse(false) end
            if bar.EnableMouseClicks then bar:EnableMouseClicks(false) end
            if bar.EnableMouseMotion then bar:EnableMouseMotion(false) end
            if bar.Selection then SilenceSelection(bar.Selection) end

            if bar:GetParent() ~= hiddenParent then
                bar:SetParent(hiddenParent)
            end
        end
    end

    -- 3. Silence all buttons and containers for all bars (explicit global + bar.actionButtons)
    for _, info in ipairs(BAR_BUTTON_PATTERNS) do
        for i = 1, info.count do
            QuietButton(_G[info.prefix .. i])
            QuietContainer(_G[info.bar .. "ButtonContainer" .. i])
        end
        local bar = _G[info.bar]
        if bar and bar.actionButtons and type(bar.actionButtons) == "table" then
            for _, btn in pairs(bar.actionButtons) do
                QuietButton(btn)
                if btn.container then
                    QuietContainer(btn.container)
                end
            end
        end
    end

    -- 4. StatusTrackingBarManager (XP, Rep, Honor bars in center of screen)
    local stbm = _G.StatusTrackingBarManager
    if stbm then
        if stbm.SetAlpha then stbm:SetAlpha(0) end
        if stbm.EnableMouse then stbm:EnableMouse(false) end
        if stbm.Selection then SilenceSelection(stbm.Selection) end

        local subContainers = { _G.MainStatusTrackingBarContainer, _G.SecondaryStatusTrackingBarContainer }
        for _, sub in ipairs(subContainers) do
            if sub then
                if sub.SetAlpha then sub:SetAlpha(0) end
                if sub.EnableMouse then sub:EnableMouse(false) end
            end
        end
    end
end

local function HookEditModeActionBars()
    if _editModeCallbacksRegistered then return end
    if _G.EventRegistry and _G.EventRegistry.RegisterCallback then
        _editModeCallbacksRegistered = true
        _G.EventRegistry:RegisterCallback("EditMode.Enter", function()
            C_Timer.After(0, suppress_blizzard_actionbars)
        end, sfui.actionbars)
        _G.EventRegistry:RegisterCallback("EditMode.Exit", function()
            C_Timer.After(0, suppress_blizzard_actionbars)
        end, sfui.actionbars)
    end
end
HookEditModeActionBars()

if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", function()
        C_Timer.After(0, suppress_blizzard_actionbars)
    end)
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        C_Timer.After(0, suppress_blizzard_actionbars)
    end)
    sfui.events.RegisterEvent("UPDATE_BINDINGS", function()
        C_Timer.After(0, suppress_blizzard_actionbars)
    end)
    sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", function()
        suppress_blizzard_actionbars()
    end)
    sfui.events.RegisterEvent("ADDON_LOADED", function(event, addonLoaded)
        if addonLoaded == "Blizzard_ActionBar" or addonLoaded == "Blizzard_EditMode" then
            HookEditModeActionBars()
            C_Timer.After(0, suppress_blizzard_actionbars)
        end
    end)
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


