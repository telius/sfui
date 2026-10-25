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
local UNTAINT_BARS = {
    "MultiBar5", "MultiBar6", "MultiBar7", "MultiBarLeft", "MultiBarRight",
    "MultiBarBottomLeft", "MultiBarBottomRight", "MicroButtonAndBagsBar",
    "OverrideActionBar", "MainMenuBar", "MainActionBar", "StanceBar",
    "PetActionBar", "PossessActionBar", "MainMenuBarArtFrame",
    "ShapeshiftBarFrame", "StanceBarFrame", "PetActionBarFrame",
    "PossessBarFrame", "MultiCastActionBarFrame",
}

local function suppress_blizzard_actionbars()
    if InCombatLockdown and InCombatLockdown() then
        if sfui.common and sfui.common.run_after_combat then
            sfui.common.run_after_combat(suppress_blizzard_actionbars)
        end
        return
    end

    for _, name in ipairs(UNTAINT_BARS) do
        local bar = _G[name]
        if bar then
            if bar.SetAlpha then
                bar:SetAlpha(0)
            end
            local isProtected = bar.IsProtected and bar:IsProtected()
            if not isProtected and bar.EnableMouse and not InCombatLockdown() then
                pcall(bar.EnableMouse, bar, false)
            end
        end
    end

    -- StatusTrackingBarManager
    local stbm = _G.StatusTrackingBarManager
    if stbm and stbm.SetAlpha then
        stbm:SetAlpha(0)
    end
end

if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("ADDON_LOADED", function(event, addonLoaded)
        if addonLoaded == "Blizzard_ActionBar" then
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


