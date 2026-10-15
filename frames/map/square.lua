local addonName, addon = ...
local _addonName, _addon = addonName, addon

sfui = sfui or {}
sfui.map = sfui.map or {}
sfui.map.square = sfui.map.square or {}
sfui.minimap = sfui.minimap or {}
sfui.minimap.square = sfui.map.square

local square = sfui.map.square

-- ==============================================================================
--  sfui/frames/map/square.lua
--  Lean, 100% Taint-Free Square Minimap Module
--
--  Features:
--    - Engine-level square mask (130937 / ChatFrameBackground) on Minimap
--    - Global GetMinimapShape hook for LibDBIcon & community addon edge alignment
--    - Taint-free circular Blizzard clutter suppression (SetAlpha 0, no :Hide calls)
--    - Support for HybridMinimap (indoor / cave exploration canvas)
--    - Pixel-snapped 1px backdrop border integrated with sfui theme palette
--    - Zero-taint mousewheel zooming for classic and retail
--    - InCombatLockdown deferral to guarantee no combat action-blocked errors
-- ==============================================================================

local _G = _G
local Minimap = _G.Minimap
local MinimapCluster = _G.MinimapCluster
local CreateFrame = _G.CreateFrame
local InCombatLockdown = _G.InCombatLockdown
local hooksecurefunc = _G.hooksecurefunc
local pcall = _G.pcall
local type = _G.type
local ipairs = _G.ipairs
local math_max = _G.math.max

-- Texture / FileID Constants
local MASK_SQUARE = 130937
local MASK_ROUND = 186178
local MASK_SQUARE_PATH = "Interface\\ChatFrame\\ChatFrameBackground"
local MASK_ROUND_PATH = "Textures\\MinimapMask"

local isInitialized = false
local pendingApply = false
local backdropFrame = nil

-- ------------------------------------------------------------------------------
-- Global Addon Contract: GetMinimapShape
-- ------------------------------------------------------------------------------
-- LibDBIcon, GatherMate, HandyNotes, Questie, TomTom, etc. query GetMinimapShape.
-- Returning "SQUARE" causes them to calculate icons along square bounding edges.
function _G.GetMinimapShape()
    if square and square.IsEnabled and square:IsEnabled() then
        return "SQUARE"
    end
    return "ROUND"
end

-- ------------------------------------------------------------------------------
-- Helper: Safe Frame / Texture Suppression (Zero Taint)
-- ------------------------------------------------------------------------------
-- Never call :Hide() on Blizzard frames or hook OnShow to Hide(), which taints
-- UIParent_ManageFramePositions and Edit Mode. SetAlpha(0) and EnableMouse(false).
local function suppress_frame(f)
    if not f then return end
    if f.SetAlpha then
        f:SetAlpha(0)
    end
    if f.EnableMouse then
        f:EnableMouse(false)
    end
end

local function restore_frame(f)
    if not f then return end
    if f.SetAlpha then
        f:SetAlpha(1)
    end
    if f.EnableMouse then
        f:EnableMouse(true)
    end
end

-- ------------------------------------------------------------------------------
-- Circular Clutter Management
-- ------------------------------------------------------------------------------
local function get_suppressed_frames()
    local frames = {
        _G.MinimapCompassTexture,
        _G.MinimapNorthTag,
        _G.MinimapBorder,
        _G.MinimapBorderTop,
        _G.MinimapZoomIn,
        _G.MinimapZoomOut,
        _G.MinimapToggleButton,
        _G.MiniMapWorldMapButton,
        _G.MinimapCompassTextureUnderlay,
        _G.MiniMapTrackingBorder,
        _G.MiniMapTrackingBackground,
    }

    if Minimap then
        if Minimap.ZoomIn then frames[#frames + 1] = Minimap.ZoomIn end
        if Minimap.ZoomOut then frames[#frames + 1] = Minimap.ZoomOut end
    end

    if MinimapCluster then
        if MinimapCluster.BorderTop then frames[#frames + 1] = MinimapCluster.BorderTop end
        if MinimapCluster.DielFrame then frames[#frames + 1] = MinimapCluster.DielFrame end
        if MinimapCluster.Tracking and MinimapCluster.Tracking.Background then
            frames[#frames + 1] = MinimapCluster.Tracking.Background
        end
    end

    local backdrop = _G.MinimapBackdrop
    if backdrop then
        if backdrop.MinimapCompassTexture then
            frames[#frames + 1] = backdrop.MinimapCompassTexture
        end
        if backdrop.StaticOverlayTexture then
            frames[#frames + 1] = backdrop.StaticOverlayTexture
        end
    end

    return frames
end

local function apply_circular_suppression(enableSquare)
    local list = get_suppressed_frames()
    for _, f in ipairs(list) do
        if enableSquare then
            suppress_frame(f)
        else
            restore_frame(f)
        end
    end

    -- Suppress retail archaeology & quest blob boundary rings on square minimap
    if Minimap then
        if Minimap.SetArchBlobRingAlpha then
            Minimap:SetArchBlobRingAlpha(enableSquare and 0 or 1)
            Minimap:SetArchBlobRingScalar(enableSquare and 0 or 1)
        end
        if Minimap.SetQuestBlobRingAlpha then
            Minimap:SetQuestBlobRingAlpha(enableSquare and 0 or 1)
            Minimap:SetQuestBlobRingScalar(enableSquare and 0 or 1)
        end
    end
end

-- ------------------------------------------------------------------------------
-- Mask Texture Application
-- ------------------------------------------------------------------------------
local function apply_minimap_mask(isSquare)
    if not Minimap or not Minimap.SetMaskTexture then return end

    if isSquare then
        local ok = pcall(Minimap.SetMaskTexture, Minimap, MASK_SQUARE)
        if not ok then
            pcall(Minimap.SetMaskTexture, Minimap, MASK_SQUARE_PATH)
        end
    else
        local ok = pcall(Minimap.SetMaskTexture, Minimap, MASK_ROUND)
        if not ok then
            pcall(Minimap.SetMaskTexture, Minimap, MASK_ROUND_PATH)
        end
    end
end

-- ------------------------------------------------------------------------------
-- HybridMinimap (Caves / Indoor Maps)
-- ------------------------------------------------------------------------------
local function setup_hybrid_minimap(isSquare)
    local hybrid = _G.HybridMinimap
    if not hybrid then return end

    if hybrid.CircleMask and hybrid.CircleMask.SetTexture then
        if isSquare then
            local ok = pcall(hybrid.CircleMask.SetTexture, hybrid.CircleMask, MASK_SQUARE)
            if not ok then
                pcall(hybrid.CircleMask.SetTexture, hybrid.CircleMask, MASK_SQUARE_PATH)
            end
        else
            local ok = pcall(hybrid.CircleMask.SetTexture, hybrid.CircleMask, MASK_ROUND)
            if not ok then
                pcall(hybrid.CircleMask.SetTexture, hybrid.CircleMask, MASK_ROUND_PATH)
            end
        end
    end

    local canvas = hybrid.MapCanvas
    if canvas and canvas.SetMaskTexture and hybrid.CircleMask then
        canvas:SetMaskTexture(hybrid.CircleMask)
    end
end

-- ------------------------------------------------------------------------------
-- 1px Square Backdrop Frame
-- ------------------------------------------------------------------------------
local function get_or_create_backdrop()
    if backdropFrame then return backdropFrame end
    if not Minimap then return nil end

    local parent = Minimap:GetParent() or MinimapCluster or UIParent
    backdropFrame = CreateFrame("Frame", "sfui_SquareMinimapBackdrop", parent)
    backdropFrame:SetFrameStrata("BACKGROUND")
    backdropFrame:SetFrameLevel(0)
    backdropFrame:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -1, 1)
    backdropFrame:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 1, -1)
    backdropFrame:EnableMouse(false)

    square:UpdateTheme()

    return backdropFrame
end

function square:UpdateTheme()
    if not backdropFrame then return end

    local pal = sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()
    local bCol = (pal and pal.borderColor) or { 0, 0, 0, 1 }

    if sfui.widgets and sfui.widgets.create_border then
        sfui.widgets.create_border(backdropFrame, 1, bCol)
    end
end

-- ------------------------------------------------------------------------------
-- Mouse Wheel Zooming
-- ------------------------------------------------------------------------------
local function setup_mouse_wheel()
    if not Minimap or not Minimap.EnableMouseWheel then return end
    Minimap:EnableMouseWheel(true)

    -- If Blizzard XML already defined OnMouseWheel (e.g. retail MinimapMixin), keep it
    if not Minimap:GetScript("OnMouseWheel") then
        Minimap:SetScript("OnMouseWheel", function(self, delta)
            if delta > 0 then
                if _G.Minimap_ZoomIn then
                    _G.Minimap_ZoomIn()
                elseif self.ZoomIn and self.ZoomIn.Click then
                    self.ZoomIn:Click()
                else
                    local cur = self:GetZoom()
                    local maxZoom = (self.GetZoomLevels and self:GetZoomLevels()) or 5
                    if cur < maxZoom then
                        self:SetZoom(cur + 1)
                    end
                end
            else
                if _G.Minimap_ZoomOut then
                    _G.Minimap_ZoomOut()
                elseif self.ZoomOut and self.ZoomOut.Click then
                    self.ZoomOut:Click()
                else
                    local cur = self:GetZoom()
                    if cur > 0 then
                        self:SetZoom(cur - 1)
                    end
                end
            end
        end)
    end
end

-- ------------------------------------------------------------------------------
-- Public API & State Control
-- ------------------------------------------------------------------------------
function square:IsEnabled()
    if SfuiDB and SfuiDB.minimap_square ~= nil then
        return SfuiDB.minimap_square
    end
    local cfg = sfui.config and sfui.config.minimap
    if cfg and cfg.square ~= nil then
        return cfg.square
    end
    return true
end

function square:SetEnabled(enabled)
    SfuiDB = SfuiDB or {}
    SfuiDB.minimap_square = enabled and true or false
    self:Apply()
end

function square:Apply()
    if InCombatLockdown() then
        pendingApply = true
        return
    end
    pendingApply = false

    local isSquare = self:IsEnabled()

    -- 1. Apply or revert mask texture
    apply_minimap_mask(isSquare)

    -- 2. Hybrid minimap mask sync
    setup_hybrid_minimap(isSquare)

    -- 3. Taint-free suppression of circular art and buttons
    apply_circular_suppression(isSquare)

    -- 4. 1px backdrop frame
    local backdrop = get_or_create_backdrop()
    if backdrop then
        backdrop:SetShown(isSquare)
        if isSquare then
            self:UpdateTheme()
        end
    end

    -- 5. Mousewheel zoom
    setup_mouse_wheel()

    -- 6. Lock Minimap strata and frame level; prevent MinimapCluster click elevation
    if Minimap then
        Minimap:SetFrameStrata("LOW")
        Minimap:SetFrameLevel(10)
    end
    if MinimapCluster then
        MinimapCluster:EnableMouse(false)
    end

    -- 7. Notify LibDBIcon to refresh button positions if present
    local ldbi = _G.LibStub and _G.LibStub("LibDBIcon-1.0", true)
    if ldbi and ldbi.Refresh then
        pcall(ldbi.Refresh, ldbi)
    end

    -- 8. Synchronize mail/crafting indicators and queue status (dungeon finder) positions
    if sfui.minimap then
        if sfui.minimap.update_indicator_positions then
            sfui.minimap.update_indicator_positions()
        end
        if sfui.minimap.update_queue_status_position then
            sfui.minimap.update_queue_status_position()
        end
    end
end

-- ------------------------------------------------------------------------------
-- Lifecycle Initialization
-- ------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("ADDON_LOADED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_ENTERING_WORLD" then
        if not isInitialized then
            isInitialized = true
            square:Apply()
        else
            -- Re-apply on reload or zone change to ensure textures remain suppressed
            square:Apply()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingApply then
            square:Apply()
        end
    elseif event == "ADDON_LOADED" then
        if arg1 == "Blizzard_HybridMinimap" then
            setup_hybrid_minimap(square:IsEnabled())
        elseif arg1 == "Blizzard_TimeManager" then
            -- Re-suppress if TimeManager restored any circular elements
            if square:IsEnabled() then
                apply_circular_suppression(true)
            end
        end
    end
end)

-- Safe hook: If Minimap size changes, backdrop auto-sizes via anchors
if Minimap and hooksecurefunc then
    hooksecurefunc(Minimap, "SetMaskTexture", function(self, mask)
        if square and square._internalMaskChange then return end
        if square:IsEnabled() and mask ~= MASK_SQUARE and mask ~= MASK_SQUARE_PATH then
            square._internalMaskChange = true
            apply_minimap_mask(true)
            square._internalMaskChange = nil
        end
    end)
end
