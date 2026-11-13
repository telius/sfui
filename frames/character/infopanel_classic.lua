local addonName, addon = ...
sfui = sfui or {}

-- Guard: Classic Era (1.15.x) only
if not sfui.isEra then return end

sfui.character = sfui.character or {}
local panelModule = sfui.character.infopanel
if not panelModule then return end

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/character/infopanel_classic.lua
--  Classic Era (1.15.x) Character Info Panel Adapter
--
--  Builds upon frames/character/infopanel.lua:
--    1. Classic Era CharacterFrame geometry & Season of Discovery EngravingFrame
--       side-by-side anchoring (384x512 power-of-two texture inset alignment).
--    2. Classic Era unit combat stat event hooks (UNIT_ATTACK, UNIT_DAMAGE,
--       UNIT_RANGEDDAMAGE, UNIT_ATTACK_SPEED, UNIT_LEVEL).
-- ══════════════════════════════════════════════════════════════════════════════

local _G = _G
local hooksecurefunc = _G.hooksecurefunc

-- Classic Era CharacterFrame (384x512) has a 32px right texture inset, 13px top inset,
-- and 73px bottom inset (above CharacterFrameTab1..5).
-- When Season of Discovery's EngravingFrame is open (anchored at TOPRIGHT -34, -70, width 203),
-- shift the default anchor to the right of EngravingFrame so both panels remain visible.
function panelModule.ApplyDefaultAnchor(frame, charFrame)
    if not frame or not charFrame then return end
    local engraving = _G.EngravingFrame
    local xOffset = (engraving and engraving.IsShown and engraving:IsShown()) and 172 or -30
    frame:SetPoint("TOPLEFT", charFrame, "TOPRIGHT", xOffset, -13)
    frame:SetPoint("BOTTOMLEFT", charFrame, "BOTTOMRIGHT", xOffset, 73)
end

local engravingHooked = false
local function hook_engraving_frame()
    if engravingHooked then return end
    local engraving = _G.EngravingFrame
    if not engraving or not engraving.HookScript then return end
    engravingHooked = true

    local function on_engraving_toggle()
        local frame = panelModule.GetPanelFrame and panelModule.GetPanelFrame()
        if frame and frame:IsShown() and panelModule.RestorePosition then
            panelModule.RestorePosition(frame)
        end
        local trainerMod = sfui.character and sfui.character.trainer
        if trainerMod and trainerMod.OnEngravingToggle then
            trainerMod.OnEngravingToggle()
        end
    end

    engraving:HookScript("OnShow", on_engraving_toggle)
    engraving:HookScript("OnHide", on_engraving_toggle)
end

local CLASSIC_UNIT_EVENTS = {
    "UNIT_ATTACK",
    "UNIT_DAMAGE",
    "UNIT_RANGEDDAMAGE",
    "UNIT_ATTACK_SPEED",
    "UNIT_LEVEL",
}

local function init_classic_infopanel()
    hook_engraving_frame()

    local events = sfui.events
    if not events then return end

    if panelModule.RequestRefresh then
        events.RegisterUnitEvents(CLASSIC_UNIT_EVENTS, "player", panelModule.RequestRefresh)
    end

    events.RegisterEvent("ADDON_LOADED", function(_, loadedAddon)
        if loadedAddon == "Blizzard_EngravingUI" then
            hook_engraving_frame()
        end
    end)

    local frame = panelModule.GetPanelFrame and panelModule.GetPanelFrame()
    if frame and panelModule.RestorePosition then
        panelModule.RestorePosition(frame)
    end
end

if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("PLAYER_LOGIN", init_classic_infopanel)
end

