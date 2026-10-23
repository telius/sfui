local addonName, addon = ...
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

-- Texture / Atlas / FileID Constants
local MASK_SQUARE_ATLAS = "SquareMask"
local MASK_SQUARE_FILEID = 130937
local MASK_SQUARE_PATH = "Interface\\ChatFrame\\ChatFrameBackground"
local MASK_ROUND_ATLAS = "ui-hud-minimap-frame-generic-mask"
local MASK_ROUND_PATH = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local MASK_ROUND_LEGACY = 186178

local isInitialized = false
local pendingApply = false
local backdropFrame = nil

-- ------------------------------------------------------------------------------
-- Ground Textures Watchdog
-- ------------------------------------------------------------------------------
-- Blizzard's HybridMinimap calls C_Minimap.SetDrawGroundTextures(false) on show.
-- If desynced or hidden irregularly, ground textures remain disabled in the C++
-- engine until character logout. Assert true whenever HybridMinimap is inactive.
local function ensure_ground_textures()
    if _G.C_Minimap and _G.C_Minimap.SetDrawGroundTextures then
        local hybrid = _G.HybridMinimap
        if not (hybrid and hybrid:IsShown()) then
            _G.C_Minimap.SetDrawGroundTextures(true)
        end
    end
end

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
    if f.EnableMouse and f.IsObjectType and f:IsObjectType("Button") then
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
        local ok = pcall(Minimap.SetMaskTexture, Minimap, MASK_SQUARE_ATLAS)
        if not ok then
            ok = pcall(Minimap.SetMaskTexture, Minimap, MASK_SQUARE_FILEID)
            if not ok then
                pcall(Minimap.SetMaskTexture, Minimap, MASK_SQUARE_PATH)
            end
        end
    else
        if sfui.isCamelot and MinimapCluster and MinimapCluster.UpdateMinimapConfig then
            MinimapCluster:UpdateMinimapConfig()
        else
            local ok = pcall(Minimap.SetMaskTexture, Minimap, MASK_ROUND_ATLAS)
            if not ok then
                ok = pcall(Minimap.SetMaskTexture, Minimap, MASK_ROUND_PATH)
                if not ok then
                    pcall(Minimap.SetMaskTexture, Minimap, MASK_ROUND_LEGACY)
                end
            end
        end
    end
end

-- ------------------------------------------------------------------------------
-- HybridMinimap (Caves / Indoor Maps)
-- ------------------------------------------------------------------------------
local function setup_hybrid_minimap(isSquare)
    local hybrid = _G.HybridMinimap
    if not hybrid then return end

    local canvas = hybrid.MapCanvas
    if isSquare then
        -- On square minimap, HybridMinimap already clips all children to the square frame
        -- via native clipChildren="true". Disabling canvas mask texture completely avoids
        -- shader alpha evaluation bugs where non-alpha masks turn cave/scenario tiles pitch black.
        if canvas and canvas.SetUseMaskTexture then
            pcall(canvas.SetUseMaskTexture, canvas, false)
        end
        if hybrid.CircleMask and hybrid.CircleMask.SetAtlas then
            pcall(hybrid.CircleMask.SetAtlas, hybrid.CircleMask, MASK_SQUARE_ATLAS)
        end
    else
        -- Restore circular masking for default Blizzard layout
        if hybrid.CircleMask and hybrid.CircleMask.SetTexture then
            pcall(hybrid.CircleMask.SetTexture, hybrid.CircleMask, MASK_ROUND_PATH)
        end
        if canvas and canvas.SetMaskTexture and hybrid.CircleMask then
            canvas:SetMaskTexture(hybrid.CircleMask)
            if canvas.SetUseMaskTexture then
                pcall(canvas.SetUseMaskTexture, canvas, true)
            end
        end
    end

    -- Hook HybridMinimap lifecycle once to guard ground textures and canvas masking
    if not hybrid._sfuiHybridHooked and hybrid.HookScript then
        hybrid._sfuiHybridHooked = true
        hybrid:HookScript("OnShow", function(self)
            if square and square:IsEnabled() then
                if self.MapCanvas and self.MapCanvas.SetUseMaskTexture then
                    pcall(self.MapCanvas.SetUseMaskTexture, self.MapCanvas, false)
                end
            end
        end)
        hybrid:HookScript("OnHide", function()
            ensure_ground_textures()
        end)
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

local bronzeOverlay = nil

local function get_or_create_bronze_overlay()
    if bronzeOverlay then return bronzeOverlay end
    if not Minimap then return nil end

    local parent = MinimapCluster or Minimap:GetParent() or UIParent
    bronzeOverlay = CreateFrame("Frame", "sfui_SquareMinimapBronzeOverlay", parent)
    sfui.common.set_pixel_snapping(bronzeOverlay)
    bronzeOverlay:SetFrameStrata("LOW")
    bronzeOverlay:SetFrameLevel(math_max(5, (Minimap:GetFrameLevel() or 1) + 5))
    bronzeOverlay:SetAllPoints(Minimap)
    bronzeOverlay:EnableMouse(false)

    -- Heavy bronze frame basic texture if supported
    local nativeBorder = bronzeOverlay:CreateTexture(nil, "BORDER", nil, 2)
    nativeBorder:SetPoint("TOPLEFT", bronzeOverlay, "TOPLEFT", -8, 8)
    nativeBorder:SetPoint("BOTTOMRIGHT", bronzeOverlay, "BOTTOMRIGHT", 8, -8)
    bronzeOverlay.nativeBorder = nativeBorder

    -- 4 Sculpted corner brackets
    bronzeOverlay.corners = {}
    local bracketDefs = {
        { key = "TL", point = "TOPLEFT",     x = -2, y = 2 },
        { key = "TR", point = "TOPRIGHT",    x = 2,  y = 2 },
        { key = "BL", point = "BOTTOMLEFT",  x = -2, y = -2 },
        { key = "BR", point = "BOTTOMRIGHT", x = 2,  y = -2 },
    }
    for _, b in ipairs(bracketDefs) do
        local tex = bronzeOverlay:CreateTexture(nil, "OVERLAY", nil, 6)
        tex.bracketKey = b.key
        tex.bracketPoint = b.point
        tex.offsetX = b.x
        tex.offsetY = b.y
        bronzeOverlay.corners[b.key] = tex
    end

    return bronzeOverlay
end

function square:IsBronzeTheme()
    if SfuiDB and SfuiDB.minimap_square_bronze ~= nil then
        return SfuiDB.minimap_square_bronze
    end
    if sfui.config and sfui.config.minimap and sfui.config.minimap.square_bronze ~= nil then
        return sfui.config.minimap.square_bronze
    end
    local isBronzeCamelot = (sfui.isCamelot or (sfui.compat and sfui.compat.is_camelot))
        and (sfui.theme and sfui.theme.IsCamelotActive and sfui.theme.IsCamelotActive())
    return isBronzeCamelot and true or false
end

function square:SetBronzeTheme(enabled)
    SfuiDB = SfuiDB or {}
    SfuiDB.minimap_square_bronze = enabled and true or false
    SfuiDB._minimapSquareBronzeCustomized = true
    self:UpdateTheme()
end

function square:UpdateTheme()
    if not backdropFrame then return end

    local isSquare = self:IsEnabled()
    local isBronze = isSquare and self:IsBronzeTheme()
    local pal = sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()
    local bCol = (pal and pal.borderColor) or { 0, 0, 0, 1 }

    if isBronze then
        -- Burnished antique bronze 1px border on the backdrop
        local bronzeBorderCol = { 0.82, 0.65, 0.32, 1.0 }
        if sfui.widgets and sfui.widgets.create_border then
            sfui.widgets.create_border(backdropFrame, 1, bronzeBorderCol)
        end

        local overlay = get_or_create_bronze_overlay()
        if overlay then
            overlay:SetAllPoints(Minimap)
            overlay:Show()

            local camelotDef = sfui.theme and sfui.theme.GetTheme and sfui.theme.GetTheme("camelot")
            local atlases = camelotDef and camelotDef.atlases or {}

            -- 1. Sculpted native frame texture
            local frameAtlas = atlases.frameBorderNative or "heavybronze-frame-basic"
            if sfui.theme and sfui.theme.HasAtlas and sfui.theme.HasAtlas(frameAtlas) then
                overlay.nativeBorder:SetAtlas(frameAtlas)
                overlay.nativeBorder:Show()
            else
                overlay.nativeBorder:Hide()
            end

            -- 2. Four sculpted corner brackets
            local bSize = 16
            for key, tex in pairs(overlay.corners) do
                local atlas = (sfui.theme and sfui.theme.GetCornerBracketAtlas and sfui.theme.GetCornerBracketAtlas(key, camelotDef))
                    or (atlases and atlases["corner" .. key .. "Native"])
                    or ("heavybronze-horz-cornerbracket-" .. key)
                if sfui.theme and sfui.theme.HasAtlas and sfui.theme.HasAtlas(atlas) then
                    tex:SetAtlas(atlas, false)
                    tex:ClearAllPoints()
                    tex:SetPoint(tex.bracketPoint, overlay, tex.bracketPoint, tex.offsetX, tex.offsetY)
                    tex:SetSize(bSize, bSize)
                    tex:Show()
                else
                    tex:Hide()
                end
            end
        end
    else
        -- Standard minimalist flat border
        if sfui.widgets and sfui.widgets.create_border then
            sfui.widgets.create_border(backdropFrame, 1, bCol)
        end
        if bronzeOverlay then
            bronzeOverlay:Hide()
        end
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
    local isBronzeCamelot = (sfui.isCamelot or (sfui.compat and sfui.compat.is_camelot))
        and (sfui.theme and sfui.theme.IsCamelotActive and sfui.theme.IsCamelotActive())

    if SfuiDB and SfuiDB.minimap_square ~= nil then
        if isBronzeCamelot and not SfuiDB._minimapSquareCustomized then
            return false
        end
        return SfuiDB.minimap_square
    end
    local cfg = sfui.config and sfui.config.minimap
    if cfg and cfg.square ~= nil then
        if isBronzeCamelot and not (SfuiDB and SfuiDB._minimapSquareCustomized) then
            return false
        end
        return cfg.square
    end
    if isBronzeCamelot then
        return false
    end
    return true
end

function square:SetEnabled(enabled)
    SfuiDB = SfuiDB or {}
    SfuiDB.minimap_square = enabled and true or false
    SfuiDB._minimapSquareCustomized = true
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
        else
            if bronzeOverlay then
                bronzeOverlay:Hide()
            end
        end
    end

    -- 5. Mousewheel zoom
    setup_mouse_wheel()

    -- 6. Keep Minimap in its natural LOW strata above backdrop, with backdrop behind it
    if Minimap then
        Minimap:SetFrameStrata("LOW")
    end
    if MinimapCluster then
        MinimapCluster:EnableMouse(false)
        if MinimapCluster.DielFrame then
            MinimapCluster.DielFrame:SetAlpha(1)
            MinimapCluster.DielFrame:Show()
        end
    end

    -- 7. Notify LibDBIcon to refresh button positions if present
    local ldbi = _G.LibStub and _G.LibStub("LibDBIcon-1.0", true)
    if ldbi and ldbi.Refresh then
        pcall(ldbi.Refresh, ldbi)
    end

    -- 8. Synchronize position, dimensions, and sub-modules
    if sfui.minimap and sfui.minimap.update_position then
        sfui.minimap.update_position()
    end
    if sfui.minimap and sfui.minimap.refresh then
        sfui.minimap.refresh()
    end

    -- 9. Guarantee ground textures are restored if HybridMinimap is not shown
    ensure_ground_textures()
end

-- ------------------------------------------------------------------------------
-- Lifecycle Initialization
-- ------------------------------------------------------------------------------
sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    ensure_ground_textures()
    if not isInitialized then
        isInitialized = true
        square:Apply()
    else
        -- Re-apply on reload or zone change to ensure textures remain suppressed
        square:Apply()
    end
end)

sfui.events.RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
    ensure_ground_textures()
end)

sfui.events.RegisterEvent("ZONE_CHANGED", function()
    ensure_ground_textures()
end)

sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if pendingApply then
        square:Apply()
    end
end)

sfui.events.RegisterEvent("ADDON_LOADED", function(_, arg1)
    if arg1 == "Blizzard_HybridMinimap" then
        setup_hybrid_minimap(square:IsEnabled())
    elseif arg1 == "Blizzard_TimeManager" then
        -- Re-suppress if TimeManager restored any circular elements
        if square:IsEnabled() then
            apply_circular_suppression(true)
        end
    end
end)

-- Safe hook: If Minimap size changes, backdrop auto-sizes via anchors
if Minimap and hooksecurefunc then
    hooksecurefunc(Minimap, "SetMaskTexture", function(self, mask)
        if square and square._internalMaskChange then return end
        if square:IsEnabled() and mask ~= MASK_SQUARE_ATLAS and mask ~= MASK_SQUARE_FILEID and mask ~= MASK_SQUARE_PATH then
            square._internalMaskChange = true
            apply_minimap_mask(true)
            square._internalMaskChange = nil
        end
    end)
end
