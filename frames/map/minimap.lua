local addonName, addon = ...
sfui = sfui or {}
sfui.minimap = sfui.minimap or {}

-- ========================
-- Localization
-- ========================
local _G = _G
local ipairs = _G.ipairs
local InCombatLockdown = _G.InCombatLockdown
local hooksecurefunc = _G.hooksecurefunc
local C_Timer = _G.C_Timer
local UIParent = _G.UIParent
local Minimap = _G.Minimap
local MinimapCluster = _G.MinimapCluster
local math_floor = _G.math.floor

-- ========================
-- Local Variables & State
-- ========================
local isInitialized = false
local zoom_timer = nil
local DEFAULT_ZOOM = (sfui.config and sfui.config.minimap and sfui.config.minimap.defaultZoom) or 0
local isRepositioning = false
local startup_scans = 0

local MinimapHolder = CreateFrame("Frame", "sfui_MinimapHolder", UIParent)
MinimapHolder:SetSize(220, 220)
MinimapHolder:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 35)
sfui.minimap.Holder = MinimapHolder

-- ------------------------------------------------------------------------------
-- Minimap Zoom Management
-- ------------------------------------------------------------------------------
local function set_default_zoom()
    if zoom_timer then
        zoom_timer:Cancel()
        zoom_timer = nil
    end
    if Minimap and Minimap.SetZoom then
        Minimap:SetZoom(DEFAULT_ZOOM)
    end
end

function sfui.minimap.reset_zoom_timer()
    if zoom_timer then
        zoom_timer:Cancel()
        zoom_timer = nil
    end
    if SfuiDB and SfuiDB.minimap_auto_zoom and Minimap and Minimap.GetZoom and Minimap:GetZoom() ~= DEFAULT_ZOOM then
        zoom_timer = C_Timer.NewTimer(SfuiDB.minimap_auto_zoom_delay or 5, set_default_zoom)
    end
end

-- ------------------------------------------------------------------------------
-- Strata Configuration (Minimap kept in natural LOW strata above backdrop)
-- ------------------------------------------------------------------------------
function sfui.minimap.lock_minimap_strata()
    local map = _G.Minimap
    if map then
        map:SetFrameStrata("LOW")
    end
end

-- ------------------------------------------------------------------------------
-- Sub-Module Refresh Coordinator
-- ------------------------------------------------------------------------------
function sfui.minimap.refresh()
    if sfui.minimap.update_button_bar_position then sfui.minimap.update_button_bar_position() end
    if sfui.minimap.update_clock_position then sfui.minimap.update_clock_position() end
    if sfui.minimap.update_indicator_positions then sfui.minimap.update_indicator_positions() end
    if sfui.minimap.update_location_bar then sfui.minimap.update_location_bar() end
    if sfui.minimap.update_queue_status_position then sfui.minimap.update_queue_status_position() end
    if sfui.minimap.update_status then sfui.minimap.update_status() end
end

-- ------------------------------------------------------------------------------
-- Decouple Minimap from Blizzard Edit Mode
-- ------------------------------------------------------------------------------
local function decouple_minimap()
    if InCombatLockdown() then return end
    local map = _G.Minimap
    if not map then return end

    if map:GetParent() ~= UIParent then
        map:SetParent(UIParent)
    end

    if not sfui.minimap._parentHooked then
        sfui.minimap._parentHooked = true
        hooksecurefunc(map, "SetParent", function(self, parent)
            if parent ~= UIParent and not InCombatLockdown() then
                self:SetParent(UIParent)
            end
        end)
    end

    if map.SetFixedFrameStrata then map:SetFixedFrameStrata(true) end
    if map.SetFixedFrameLevel then map:SetFixedFrameLevel(true) end
    map:SetFrameStrata("LOW")
    map:SetFrameLevel(10)

    -- Suppress Blizzard MinimapCluster & its Edit Mode selection outline completely
    local cluster = _G.MinimapCluster
    if cluster then
        cluster:SetAlpha(0)
        cluster:EnableMouse(false)
        if cluster.Selection then
            cluster.Selection:SetAlpha(0)
            cluster.Selection:EnableMouse(false)
            if cluster.Selection.EnableMouseClicks then cluster.Selection:EnableMouseClicks(false) end
            if cluster.Selection.EnableMouseMotion then cluster.Selection:EnableMouseMotion(false) end
        end
    end
end
sfui.minimap.decouple_minimap = decouple_minimap

if _G.EventRegistry and _G.EventRegistry.RegisterCallback then
    _G.EventRegistry:RegisterCallback("EditMode.Enter", function()
        C_Timer.After(0, decouple_minimap)
    end, sfui.minimap)
end

-- ------------------------------------------------------------------------------
-- Positioning & Dimensions
-- ------------------------------------------------------------------------------
function sfui.minimap.update_position(x, y, point, relPoint)
    local posX = x or (SfuiDB and SfuiDB.minimap_x) or (sfui.config and sfui.config.minimap and sfui.config.minimap.x) or
        0
    local posY = y or (SfuiDB and SfuiDB.minimap_y) or (sfui.config and sfui.config.minimap and sfui.config.minimap.y) or
        35
    local pt = point or (SfuiDB and SfuiDB.minimap_point) or
        (sfui.config and sfui.config.minimap and sfui.config.minimap.point) or "BOTTOMRIGHT"
    local rel = relPoint or (SfuiDB and SfuiDB.minimap_relative_point) or pt

    if SfuiDB then
        SfuiDB.minimap_x = posX
        SfuiDB.minimap_y = posY
        SfuiDB.minimap_point = pt
        SfuiDB.minimap_relative_point = rel
    end

    if InCombatLockdown() then
        sfui.minimap.pendingPosition = { x = posX, y = posY, point = pt, relPoint = rel }
        return
    end

    local width = (SfuiDB and SfuiDB.minimap_width)
        or (sfui.config and sfui.config.minimap and (sfui.config.minimap.width or sfui.config.minimap.default_size))
        or 220
    local height = (SfuiDB and SfuiDB.minimap_height)
        or (sfui.config and sfui.config.minimap and (sfui.config.minimap.height or sfui.config.minimap.default_size))
        or 220

    MinimapHolder:ClearAllPoints()
    MinimapHolder:SetPoint(pt, UIParent, rel, posX, posY)
    MinimapHolder:SetSize(width, height)

    if isRepositioning then return end
    isRepositioning = true

    decouple_minimap()

    local cluster = _G.MinimapCluster
    local map = _G.Minimap
    local isSquare = sfui.map and sfui.map.square and sfui.map.square.IsEnabled and sfui.map.square:IsEnabled()

    if isSquare then
        if map then
            map:ClearAllPoints()
            map:SetPoint("CENTER", MinimapHolder, "CENTER", 0, 0)
            map:SetSize(width, height)
        end
        if _G.MinimapCompassTexture then
            _G.MinimapCompassTexture:SetAlpha(0)
            _G.MinimapCompassTexture:Hide()
        end
        if _G.MinimapCompassTextureUnderlay then
            _G.MinimapCompassTextureUnderlay:SetAlpha(0)
            _G.MinimapCompassTextureUnderlay:Hide()
        end
        if _G.MinimapBackdrop then
            _G.MinimapBackdrop:SetSize(width, height)
        end
        if cluster and cluster.DielFrame then
            cluster.DielFrame:SetAlpha(0)
        end
    else
        -- Blizzard Camelot / Round Minimap:
        -- Native geometry:
        --   MinimapCompassTexture: queried via C_Texture.GetAtlasInfo (default 215 x 226)
        --   Minimap aperture: 192 x 192 (sized safely inside the ~194px inner bronze rim)
        --   Optical centering: texture bounds have top arrow & right Diel socket; offset (-4, 4) centers aperture
        local baseSize = 220
        local scale = width / baseSize
        if scale <= 0.2 then scale = 1.0 end

        if cluster and cluster.UpdateMinimapConfig then
            cluster:UpdateMinimapConfig()
            if not cluster._sfuiConfigHooked and hooksecurefunc then
                cluster._sfuiConfigHooked = true
                hooksecurefunc(cluster, "UpdateMinimapConfig", function()
                    if not isRepositioning and not InCombatLockdown() then
                        sfui.minimap.update_position()
                    end
                end)
            end
        end

        local compass = _G.MinimapCompassTexture
        local atlasName = (compass and compass.GetAtlas and compass:GetAtlas()) or "UI-HUD-Minimap-Frame"
        local atlasInfo = _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo(atlasName)
        local compassW = (atlasInfo and atlasInfo.width and atlasInfo.width > 0) and atlasInfo.width or 215
        local compassH = (atlasInfo and atlasInfo.height and atlasInfo.height > 0) and atlasInfo.height or 226

        local aperture = 192 * scale
        local offX = 4 * scale
        local offY = -4 * scale

        if map then
            map:ClearAllPoints()
            map:SetPoint("CENTER", MinimapHolder, "CENTER", -offX, -offY)
            map:SetSize(aperture, aperture)
        end

        if _G.MinimapBackdrop then
            _G.MinimapBackdrop:SetSize(compassW * scale, compassH * scale)
        end

        if compass and map then
            compass:ClearAllPoints()
            compass:SetPoint("CENTER", map, "CENTER", offX, offY)
            compass:SetSize(compassW * scale, compassH * scale)
            compass:SetAlpha(1)
            compass:Show()
        end

        local underlay = _G.MinimapCompassTextureUnderlay
        if underlay and map then
            underlay:ClearAllPoints()
            underlay:SetPoint("CENTER", map, "CENTER", offX, offY)
            underlay:SetSize(compassW * scale, compassH * scale)
            underlay:SetAlpha(1)
        end

        if cluster and cluster.DielFrame and map then
            local diel = cluster.DielFrame
            if diel:GetParent() ~= map then
                diel:SetParent(map)
            end
            diel:SetFrameStrata("LOW")
            diel:SetFrameLevel((map:GetFrameLevel() or 10) + 5)
            diel:SetScale(scale)
            diel:ClearAllPoints()
            diel:SetPoint("CENTER", compass or map, "CENTER", 55, 86)
            diel:EnableMouse(false)
            diel:SetAlpha(1)
            diel:Show()
        end
    end

    if sfui.minimap.hook_queue_status then sfui.minimap.hook_queue_status() end
    sfui.minimap.refresh()

    if sfui.tracker and sfui.tracker.boons and sfui.tracker.boons.UpdateAnchor then
        sfui.tracker.boons.UpdateAnchor()
    end

    if not (_G.HybridMinimap and _G.HybridMinimap:IsShown()) and _G.C_Minimap and _G.C_Minimap.SetDrawGroundTextures then
        _G.C_Minimap.SetDrawGroundTextures(true)
    end

    isRepositioning = false
end

function sfui.minimap.update_dimensions(w, h)
    local width = w or (SfuiDB and SfuiDB.minimap_width)
        or (sfui.config and sfui.config.minimap and (sfui.config.minimap.width or sfui.config.minimap.default_size))
        or 220
    local height = h or (SfuiDB and SfuiDB.minimap_height)
        or (sfui.config and sfui.config.minimap and (sfui.config.minimap.height or sfui.config.minimap.default_size))
        or 220

    if SfuiDB then
        SfuiDB.minimap_width = width
        SfuiDB.minimap_height = height
    end

    if InCombatLockdown() then
        sfui.minimap.pendingDimensions = { width = width, height = height }
        return
    end

    sfui.minimap.update_position()
    if sfui.minimap.ButtonManager and sfui.minimap.ButtonManager.arrange_buttons then
        sfui.minimap.ButtonManager:arrange_buttons()
    end
end

-- ------------------------------------------------------------------------------
-- Theme Updates
-- ------------------------------------------------------------------------------
function sfui.minimap.UpdateMinimapTheme()
    if sfui.map and sfui.map.square and sfui.map.square.UpdateTheme then
        sfui.map.square:UpdateTheme()
    end
    local button_bar = sfui.minimap.button_bar
    if button_bar and sfui.theme and sfui.theme.ApplyMinimapButtonBarStyle then
        sfui.theme.ApplyMinimapButtonBarStyle(button_bar)
    end
    local bm = sfui.minimap.ButtonManager
    if bm and bm.collectedButtons then
        for _, btn in ipairs(bm.collectedButtons) do
            bm:skin_button(btn)
        end
        bm:arrange_buttons()
    end
    if sfui.minimap.update_status then
        sfui.minimap.update_status()
    end
end

-- ------------------------------------------------------------------------------
-- World Entry & Lifecycle
-- ------------------------------------------------------------------------------
local function on_minimap_entering_world(event)
    isInitialized = true
    decouple_minimap()
    if sfui.minimap.initialize_masque then sfui.minimap.initialize_masque() end
    if sfui.minimap.hook_location_bar then sfui.minimap.hook_location_bar() end
    if sfui.minimap.hook_queue_status then sfui.minimap.hook_queue_status() end
    sfui.minimap.update_dimensions()
    if SfuiDB and SfuiDB.minimap_auto_zoom then
        set_default_zoom()
    end
    if sfui.minimap.enable_button_manager then
        sfui.minimap.enable_button_manager(SfuiDB and SfuiDB.minimap_collect_buttons)
    end
    sfui.minimap.UpdateMinimapTheme()

    -- Startup timer to catch late-loading buttons and clock
    if SfuiDB and SfuiDB.minimap_collect_buttons then
        C_Timer.NewTicker(2, function(self)
            startup_scans = startup_scans + 1
            if startup_scans > 5 then
                self:Cancel()
            else
                local bm = sfui.minimap.ButtonManager
                if bm and bm:collect_buttons() then
                    bm:arrange_buttons()
                end
                sfui.minimap.refresh()
            end
        end)
    end

    -- One-shot: unregister after first world entry
    sfui.events.UnregisterEvent("PLAYER_ENTERING_WORLD", on_minimap_entering_world)
end
sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", on_minimap_entering_world)

-- Re-assert decoupling if Blizzard Edit Mode updates layouts
sfui.events.RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", function()
    if not InCombatLockdown() then
        decouple_minimap()
        sfui.minimap.update_position()
    end
end)

-- Autozoom on manual zoom changes
sfui.events.RegisterEvent("MINIMAP_UPDATE_ZOOM", function()
    if SfuiDB and SfuiDB.minimap_auto_zoom and Minimap and Minimap.GetZoom and Minimap:GetZoom() ~= DEFAULT_ZOOM then
        if zoom_timer then
            zoom_timer:Cancel()
        end
        zoom_timer = C_Timer.NewTimer((SfuiDB and SfuiDB.minimap_auto_zoom_delay) or 5, set_default_zoom)
    end
end)

-- Process pending button arranges, dimension, and position updates when dropping combat
sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    decouple_minimap()
    if sfui.minimap.pendingDimensions then
        local d = sfui.minimap.pendingDimensions
        sfui.minimap.pendingDimensions = nil
        sfui.minimap.update_dimensions(d.width, d.height)
    end
    if sfui.minimap.pendingPosition then
        local p = sfui.minimap.pendingPosition
        sfui.minimap.pendingPosition = nil
        sfui.minimap.update_position(p.x, p.y, p.point, p.relPoint)
    end
    local bm = sfui.minimap.ButtonManager
    if bm and bm.pendingArrange then
        bm:arrange_buttons()
    end
end)


local _miniDebug = {}
function sfui.minimap_debug_info()
    local bm = sfui.minimap.ButtonManager
    _miniDebug.isInitialized  = isInitialized
    _miniDebug.buttonCount    = (bm and bm.collectedButtons and #bm.collectedButtons) or 0
    _miniDebug.autoZoomActive = zoom_timer ~= nil
    return _miniDebug
end

sfui.minimap.GetDebugInfo = sfui.minimap_debug_info
sfui.RegisterModule("minimap", sfui.minimap)

if sfui.movers and sfui.movers.Register then
    sfui.movers.Register(MinimapHolder, {
        key = "minimap",
        label = "minimap",
        preferredPoint = "BOTTOMRIGHT",
        customSize = function()
            local w = (SfuiDB and SfuiDB.minimap_width)
                or (sfui.config and sfui.config.minimap and (sfui.config.minimap.width or sfui.config.minimap.default_size))
                or 220
            local h = (SfuiDB and SfuiDB.minimap_height)
                or (sfui.config and sfui.config.minimap and (sfui.config.minimap.height or sfui.config.minimap.default_size))
                or 220
            return w, h
        end,
        getPoint = function()
            local p = (SfuiDB and SfuiDB.minimap_point) or (sfui.config and sfui.config.minimap and sfui.config.minimap.point) or "BOTTOMRIGHT"
            local rel = (SfuiDB and SfuiDB.minimap_relative_point) or p
            local x = (SfuiDB and SfuiDB.minimap_x) or (sfui.config and sfui.config.minimap and sfui.config.minimap.x) or 0
            local y = (SfuiDB and SfuiDB.minimap_y) or (sfui.config and sfui.config.minimap and sfui.config.minimap.y) or 35
            return p, UIParent, rel, x, y
        end,
        setPoint = function(point, relTo, relPoint, x, y)
            sfui.minimap.update_position(x, y, point, relPoint)
        end,
        resetPosition = function()
            local defPoint = (sfui.config and sfui.config.minimap and sfui.config.minimap.point) or "BOTTOMRIGHT"
            local defX = (sfui.config and sfui.config.minimap and sfui.config.minimap.x) or 0
            local defY = (sfui.config and sfui.config.minimap and sfui.config.minimap.y) or 35
            sfui.minimap.update_position(defX, defY, defPoint, defPoint)
        end,
        isEnabled = function() return true end,
    })
end

if sfui.minimap.hook_location_bar then sfui.minimap.hook_location_bar() end
C_Timer.After(0, decouple_minimap)
sfui.minimap.refresh()

