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

    local cluster = _G.MinimapCluster
    local map = _G.Minimap
    local target = cluster or map

    if target then
        local clearPoints = target.ClearAllPointsBase or target.ClearAllPoints
        clearPoints(target)
        local setPoint = target.SetPointBase or target.SetPoint
        setPoint(target, "TOPRIGHT", MinimapHolder, "TOPRIGHT", 0, 0)
    end

    local isSquare = sfui.map and sfui.map.square and sfui.map.square.IsEnabled and sfui.map.square:IsEnabled()

    if isSquare then
        if cluster then
            cluster:EnableMouse(false)
            cluster:SetSize(width, height)
            if cluster.MinimapContainer then
                cluster.MinimapContainer:SetScale(1)
                cluster.MinimapContainer:SetSize(width, height)
                cluster.MinimapContainer:ClearAllPoints()
                cluster.MinimapContainer:SetPoint("CENTER", cluster, "CENTER", 0, 0)
            end
        end

        if map then
            map:SetFrameStrata("LOW")
            map:SetSize(width, height)
            local anchorTarget = (cluster and cluster.MinimapContainer) or cluster
            if anchorTarget then
                map:ClearAllPoints()
                map:SetPoint("CENTER", anchorTarget, "CENTER", 0, 0)
            end
        end

        if _G.MinimapBackdrop then
            _G.MinimapBackdrop:SetSize(width, height)
        end
    else
        -- Blizzard Camelot / Round Minimap:
        -- Native geometry:
        --   MinimapContainer & MinimapCompassTexture: 215 x 226
        --   Minimap aperture: 192 x 192 (sized safely inside the ~194px inner bronze rim)
        --   Optical centering: texture bounds have top arrow & right bracket; offset (-4, 4) centers aperture
        local baseSize = 220
        local scale = width / baseSize
        if scale <= 0.2 then scale = 1.0 end

        if cluster then
            cluster:EnableMouse(false)
            if cluster.MinimapContainer then
                -- Restore native container points (account for scale)
                cluster.MinimapContainer:ClearAllPoints()
                cluster.MinimapContainer:SetPoint("TOP", cluster, "TOP", 10 / scale, -30 / scale)
                cluster.MinimapContainer:SetScale(scale)
                if cluster.TrackingFrame then
                    cluster.TrackingFrame:SetScale(scale)
                end
            end
        end

        -- Ensure Blizzard native atlas configuration is applied
        if cluster and cluster.UpdateMinimapConfig then
            cluster:UpdateMinimapConfig()
        end

        if map then
            map:SetFrameStrata("LOW")
            map:SetSize(192, 192)
            local anchorTarget = (cluster and cluster.MinimapContainer) or cluster
            if anchorTarget then
                map:ClearAllPoints()
                -- Optically centered inside the circular compass aperture
                map:SetPoint("CENTER", anchorTarget, "CENTER", -4, 4)
            end
        end

        if _G.MinimapCompassTexture and map then
            _G.MinimapCompassTexture:ClearAllPoints()
            _G.MinimapCompassTexture:SetPoint("CENTER", map, "CENTER", 4, -4)
        end
        if _G.MinimapCompassTextureUnderlay and map then
            _G.MinimapCompassTextureUnderlay:ClearAllPoints()
            _G.MinimapCompassTextureUnderlay:SetPoint("CENTER", map, "CENTER", 4, -4)
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


function sfui.minimap_debug_info()
    local button_bar = sfui.minimap.button_bar
    local bm = sfui.minimap.ButtonManager
    return {
        isInitialized = isInitialized,
        buttonCount = (bm and bm.collectedButtons and #bm.collectedButtons) or 0,
        autoZoomActive = zoom_timer ~= nil,
    }
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
sfui.minimap.refresh()

