local _, _ = ...
sfui = sfui or {}
sfui.map = sfui.map or {}
sfui.map.overlay = sfui.map.overlay or {}

if sfui.isRetail then return end

local overlay = sfui.map.overlay

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/map/overlay.lua
--  ARPG-Style Minimap Overlay (Camelot / Classic)
--
--  Renders pre-baked BLP2 (DXT5) contour/wall-hatch tiles from `sfui_overlay_maps`
--  beneath a click-through, groundless `_G.Minimap` so Blizzard C++ blips,
--  active-quest Questie/LibQuestieDB pins, and waypoint/corpse directional
--  chevrons render crisply over gameplay, with automatic combat dimming,
--  UI-panel fading, `Alt+Scroll` live zoom/opacity, and `sfui.movers` support.
-- ══════════════════════════════════════════════════════════════════════════════

local _G               = _G
local CreateFrame      = _G.CreateFrame
local CreateVector2D   = _G.CreateVector2D
local UIParent         = _G.UIParent
local Minimap          = _G.Minimap
local C_Timer          = _G.C_Timer
local InCombatLockdown = _G.InCombatLockdown
local UnitPosition     = _G.UnitPosition
local UnitFactionGroup = _G.UnitFactionGroup
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local GetPlayerFacing  = _G.GetPlayerFacing
local GetCVar          = _G.GetCVar
local SetCVar          = _G.SetCVar
local IsAltKeyDown     = _G.IsAltKeyDown
local IsShiftKeyDown   = _G.IsShiftKeyDown
local IsIndoors        = _G.IsIndoors
local IsInInstance     = _G.IsInInstance
local GetInstanceInfo  = _G.GetInstanceInfo

local math_abs   = math.abs
local math_sin   = math.sin
local math_cos   = math.cos
local math_sqrt  = math.sqrt
local math_atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local math_pi    = math.pi
local math_floor = math.floor
local math_ceil  = math.ceil
local math_min   = math.min
local math_max   = math.max
local string_format = string.format
local ipairs     = ipairs
local pairs      = pairs
local next       = next
local type       = type
local tostring   = tostring
local tonumber   = tonumber
local pcall      = pcall
local setmetatable = setmetatable

local is_secret = (sfui.safety and sfui.safety.issecretvalue)
    or _G.issecretvalue
    or function() return false end

local ZOOM_RADII_OUTDOOR = { [0] = 233.33, [1] = 200.0, [2] = 166.67, [3] = 133.33, [4] = 100.0, [5] = 66.67 }
local ZOOM_RADII_INDOOR  = { [0] = 116.67, [1] = 100.0, [2] = 83.33, [3] = 66.67, [4] = 50.0, [5] = 33.33 }

local DEFAULTS = {
    overlay_size            = 560,
    overlay_alpha           = 0.85,
    overlay_combat_alpha    = 0.22,
    overlay_instance_alpha  = 0.35,
    overlay_hide_on_panels  = true,
    overlay_x               = 0,
    overlay_y               = 0,
    overlay_zoom            = 1,
    overlay_pins_mode       = "auto",
    overlay_alt_interactive = true,
    overlay_rotate          = true,
    overlay_pin_scale       = 1.0,
    overlay_compass         = true,
}

local MAPS_ADDON_NAME  = "sfui_overlay_maps"
local MASK_PATH        = "Interface\\AddOns\\sfui\\media\\overlay\\radial_mask.tga"
local CHEVRON_PATH     = "Interface\\AddOns\\sfui\\media\\overlay\\chevron_arrow.tga"
local ICON_QUEST_TURNIN = "Interface\\GossipFrame\\ActiveQuestIcon"
local ICON_OBJECTIVE   = "Interface\\Cursor\\Attack"
local ICON_BOSS        = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local ICON_PORTAL      = "Interface\\Icons\\Spell_Shadow_Teleport"

-- Full UI panels that temporarily fade the overlay out; excludes SfuiOptionsFrame for live previewing.
local AUTO_HIDE_PANELS = {
    "WorldMapFrame", "CharacterFrame", "SpellBookFrame",
    "PlayerTalentFrame", "TalentFrame", "MerchantFrame",
    "GossipFrame", "MailFrame", "AuctionFrame", "AuctionHouseFrame",
    "BankFrame", "QuestLogFrame", "QuestFrame", "TradeSkillFrame",
    "CraftFrame", "ClassTrainerFrame", "TaxiFrame", "GuildFrame",
    "FriendsFrame", "CommunitiesFrame", "MacroFrame",
    "GameMenuFrame", "SettingsPanel", "InterfaceOptionsFrame",
}

local function round_num(val, dec)
    if sfui.common and sfui.common.round then
        return sfui.common.round(val, dec)
    end
    local mult = 10 ^ (dec or 0)
    return math_floor(val * mult + 0.5) / mult
end

local function can_modify_region(f)
    if not f then return false end
    if not (InCombatLockdown and InCombatLockdown()) then
        return true
    end
    if f.IsProtected then
        local prot = f:IsProtected()
        if is_secret(prot) or prot then
            return false
        end
    end
    if f.IsAnchoringRestricted then
        local rest = f:IsAnchoringRestricted()
        if is_secret(rest) or rest then
            return false
        end
    end
    return true
end

local function is_alt_down_clean()
    local rawAlt = IsAltKeyDown and IsAltKeyDown()
    return (not is_secret(rawAlt)) and (rawAlt and true or false) or false
end

-- ── Runtime & Cached Draw State ───────────────────────────────────────────────
local isActive                 = false
local pendingCombatSync        = false
local pendingMouseSync         = false
local hybridHooked             = false
local clusterHooked            = false
local zoomButtonsHooked        = false
local moverRegistered          = false
local eventsWired              = false
local lastOverlayInteractive   = false
local savedZoom                = nil
local savedRotate              = nil
local overlayHiddenQuestiePins = setmetatable({}, { __mode = "k" })
local hookedPanels             = setmetatable({}, { __mode = "k" })
local hbdFilterModeApplied     = "restore"
local hbdFilterDirty           = true
local hbdFilterAccum           = 0
local groundSuppressed         = nil
local nudgingZoom              = false
local lastUsingNativeGround    = false
local panelHidden              = false
local mapPackLoadReason        = nil

local holderFrame  = nil
local canvasFrame  = nil
local pinFrame     = nil
local wheelCatcher = nil
local radialMask   = nil

local tilePool         = {}
local activeTiles      = {}
local pinPool          = {}
local activePinButtons = {}
local directPinCache   = {}
local instPinCache     = {}
local directPinsDirty  = true
local lastPinCont      = nil
local lastInstPinCont  = nil

local alphaState = {
    curCanvas = 0, tgtCanvas = 0, appCanvas = nil,
    curMini   = 1, tgtMini   = 1, appMini   = nil,
    curPins   = 0, tgtPins   = 0, appPins   = nil,
}

local navTargets = {
    waypoint = nil,
    corpse   = nil,
    rev      = 0,
}

local viewCache = {
    dirty     = true,
    hasData   = false,
    wx        = nil,
    wy        = nil,
    cont      = nil,
    mapID     = nil,
    facing    = 0,
    viewRad   = 100,
    size      = 560,
    alt       = false,
    mode      = "auto",
    pinScale  = 1,
    questRev  = -1,
    navRev    = -1,
    rotate    = true,
    noWorld   = false,
    idleSkips = 0,
    draws     = 0,
}

local lastFacingForPins = 0
local _debugInfo        = {}

local update_view
local update_effective_alphas
local apply_pin_mouse_state
local pin_on_enter

local function sync_compass()
    if sfui.map and sfui.map.compass and sfui.map.compass.SyncState then
        sfui.map.compass:SyncState()
    end
end

-- ── Options & Data Pack Accessors ─────────────────────────────────────────────
local function ensure_db()
    if not _G.SfuiDB then return DEFAULTS end
    for k, v in pairs(DEFAULTS) do
        if _G.SfuiDB[k] == nil then
            _G.SfuiDB[k] = v
        end
    end
    return _G.SfuiDB
end

local function get_opt(key)
    if _G.SfuiDB and _G.SfuiDB[key] ~= nil then
        return _G.SfuiDB[key]
    end
    return DEFAULTS[key]
end

local function get_map_data()
    return sfui.overlay_maps_data or sfui.overlay_poc_data
end

local function ensure_data_indices(data)
    if not data or data._indexed then return end
    data._indexed = true
    local byMap = {}
    local unmappedByCont = {}
    if data.caves then
        for _, cave in ipairs(data.caves) do
            if cave.uiMapID ~= nil then
                byMap[cave.uiMapID] = cave
            else
                local c = cave.cont or 0
                local bucket = unmappedByCont[c]
                if not bucket then
                    bucket = {}
                    unmappedByCont[c] = bucket
                end
                bucket[#bucket + 1] = cave
            end
        end
    end
    data._cavesByMapID = byMap
    data._unmappedCavesByCont = unmappedByCont
end

local function ensure_map_pack_loaded()
    if get_map_data() ~= nil then
        mapPackLoadReason = nil
        return true
    end
    if sfui.common and sfui.common.ensure_addon_loaded then
        local loaded, reason = sfui.common.ensure_addon_loaded(MAPS_ADDON_NAME)
        mapPackLoadReason = reason
        return loaded and get_map_data() ~= nil
    end
    local cAddOns = _G.C_AddOns
    local loadFn = (cAddOns and cAddOns.LoadAddOn) or _G.LoadAddOn
    if loadFn then
        local ok, loaded, reason = pcall(loadFn, MAPS_ADDON_NAME)
        mapPackLoadReason = ok and reason or "LOAD_ERR"
        return ok and loaded and get_map_data() ~= nil
    end
    mapPackLoadReason = "NO_LOADER"
    return false
end

local function in_combat_now()
    if sfui.state and sfui.state.Is then
        return sfui.state.Is("inCombat") == true
    end
    return (InCombatLockdown and InCombatLockdown()) and true or false
end

local function is_dead_or_ghost_now()
    if sfui.state and sfui.state.Is then
        if sfui.state.Is("isDeadOrGhost") then return true end
    end
    return (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) and true or false
end

-- ── Alpha, Combat Dim & Panel Auto-Hide ───────────────────────────────────────
local function has_blocking_panel_open()
    if not get_opt("overlay_hide_on_panels") then
        return false
    end
    for _, name in ipairs(AUTO_HIDE_PANELS) do
        local f = _G[name]
        if f and f.IsShown then
            local shown = f:IsShown()
            if not is_secret(shown) and shown then
                return true
            end
        end
    end
    return false
end

local function apply_alphas_to_widgets()
    if canvasFrame and alphaState.appCanvas ~= alphaState.curCanvas then
        alphaState.appCanvas = alphaState.curCanvas
        canvasFrame:SetAlpha(alphaState.curCanvas)
    end
    if pinFrame and alphaState.appPins ~= alphaState.curPins then
        alphaState.appPins = alphaState.curPins
        pinFrame:SetAlpha(alphaState.curPins)
    end
    if Minimap and Minimap.SetAlpha and alphaState.appMini ~= alphaState.curMini then
        alphaState.appMini = alphaState.curMini
        Minimap:SetAlpha(alphaState.curMini)
    end
end

update_effective_alphas = function(immediate)
    if not isActive then
        alphaState.tgtCanvas = 0
        alphaState.tgtPins   = 0
        alphaState.tgtMini   = 1
        alphaState.curCanvas = 0
        alphaState.curPins   = 0
        alphaState.curMini   = 1
        apply_alphas_to_widgets()
        return
    end

    if panelHidden then
        alphaState.tgtCanvas = 0
        alphaState.tgtPins   = 0
        alphaState.tgtMini   = 0
    else
        local baseAlpha = lastUsingNativeGround
            and (get_opt("overlay_instance_alpha") or 0.35)
            or (get_opt("overlay_alpha") or 0.85)
        local combatCap = in_combat_now() and (get_opt("overlay_combat_alpha") or 0.22) or 1.0
        local eff = math_min(baseAlpha, combatCap)

        if lastUsingNativeGround then
            alphaState.tgtCanvas = 0
            alphaState.tgtMini   = eff
            alphaState.tgtPins   = math_max(0.35, eff)
        else
            alphaState.tgtCanvas = eff
            alphaState.tgtMini   = in_combat_now() and math_max(0.45, eff) or 1
            alphaState.tgtPins   = in_combat_now() and math_max(0.45, eff) or 1
        end
    end

    if immediate then
        alphaState.curCanvas = alphaState.tgtCanvas
        alphaState.curPins   = alphaState.tgtPins
        alphaState.curMini   = alphaState.tgtMini
        apply_alphas_to_widgets()
    end
end

local function step_alphas(elapsed)
    local rate = math_min(1, (elapsed or 0.016) * 12)
    local function approach(cur, tgt)
        local diff = tgt - cur
        if math_abs(diff) <= 0.005 then return tgt end
        return cur + diff * rate
    end
    alphaState.curCanvas = approach(alphaState.curCanvas, alphaState.tgtCanvas)
    alphaState.curPins   = approach(alphaState.curPins,   alphaState.tgtPins)
    alphaState.curMini   = approach(alphaState.curMini,   alphaState.tgtMini)
    apply_alphas_to_widgets()
end

local function refresh_panel_visibility()
    local nextHidden = has_blocking_panel_open()
    if nextHidden ~= panelHidden then
        panelHidden = nextHidden
        viewCache.dirty = true
        update_effective_alphas(true)
        if isActive and apply_pin_mouse_state then
            apply_pin_mouse_state()
        end
        sync_compass()
    elseif nextHidden and isActive then
        update_effective_alphas(true)
    end
end

local function hook_ui_panels()
    for _, name in ipairs(AUTO_HIDE_PANELS) do
        local f = _G[name]
        if f and not hookedPanels[f] and f.HookScript then
            hookedPanels[f] = true
            f:HookScript("OnShow", refresh_panel_visibility)
            f:HookScript("OnHide", refresh_panel_visibility)
        end
    end
end

-- ── Questie HBD Pin Filter & Mouse/Wheel Control ──────────────────────────────
local function get_questie_hbd_pins()
    if not _G.QuestieLoader or not _G.QuestieLoader.ImportModule then return nil end
    local loader = _G.QuestieLoader
    if loader._modules and not loader._modules["HBDPins"] then
        return nil
    end
    local ok, mod = pcall(loader.ImportModule, loader, "HBDPins")
    if ok and type(mod) == "table" then
        return mod
    end
    return nil
end

local function is_questie_pins_active()
    local q = _G.Questie
    if not (q and q.started) then return false end
    local prof = q.db and q.db.profile
    if prof and prof.enableMiniMapIcons == false then return false end
    return get_questie_hbd_pins() ~= nil
end

local function is_questie_pin_active(pin)
    if pin.isManualIcon then return false end
    local d = pin.data
    if type(d) ~= "table" then return true end
    local t = d.Type
    return (t == "complete" or t == "monster" or t == "object" or t == "item" or t == "event")
end

local function hide_questie_pin(pin)
    if not pin then return end
    if pin.FakeHide then
        if not pin.hidden then
            overlayHiddenQuestiePins[pin] = pin.data or true
            pin:FakeHide()
        end
    elseif pin.SetAlpha then
        overlayHiddenQuestiePins[pin] = true
        pin:SetAlpha(0)
    end
end

local function restore_questie_pin(pin, savedData)
    if not pin then return end
    if pin.FakeShow then
        if (savedData == true or pin.data == savedData) and pin.hidden then
            local keepHidden = (pin.ShouldBeHidden and pin:ShouldBeHidden()) or false
            if not keepHidden then
                pin:FakeShow()
            end
        end
    elseif pin.SetAlpha then
        pin:SetAlpha(1)
    end
end

local function sync_questie_hbd_filter(filterMode, fullScan)
    if filterMode == "restore" then
        for pin, savedData in pairs(overlayHiddenQuestiePins) do
            restore_questie_pin(pin, savedData)
            if pin and pin.EnableMouse and can_modify_region(pin) then
                pin:EnableMouse(true)
            end
            overlayHiddenQuestiePins[pin] = nil
        end
        hbdFilterModeApplied = "restore"
        hbdFilterDirty = false
        return
    end

    local hbdPins = get_questie_hbd_pins()
    if not hbdPins then
        hbdFilterModeApplied = filterMode
        hbdFilterDirty = false
        return
    end

    if hbdFilterModeApplied ~= filterMode then
        fullScan = true
        hbdFilterModeApplied = filterMode
    end

    if filterMode == "hide_all" then
        local src = fullScan and hbdPins.minimapPins or (hbdPins.activeMinimapPins or hbdPins.minimapPins)
        if src then
            for pin in pairs(src) do
                hide_questie_pin(pin)
            end
        end
    elseif filterMode == "active_only" then
        local altOpt = get_opt("overlay_alt_interactive") ~= false
        local interactive = (not isActive) or (altOpt and is_alt_down_clean() and not panelHidden)
        if fullScan then
            for pin, savedData in pairs(overlayHiddenQuestiePins) do
                if pin.data ~= savedData and savedData ~= true then
                    overlayHiddenQuestiePins[pin] = nil
                elseif is_questie_pin_active(pin) then
                    restore_questie_pin(pin, savedData)
                    overlayHiddenQuestiePins[pin] = nil
                end
            end
        end
        local src = fullScan and hbdPins.minimapPins or (hbdPins.activeMinimapPins or hbdPins.minimapPins)
        if src then
            for pin in pairs(src) do
                if not is_questie_pin_active(pin) then
                    hide_questie_pin(pin)
                elseif not pin.hidden and pin.EnableMouse and can_modify_region(pin) then
                    pin:EnableMouse(interactive)
                end
            end
        end
    end

    hbdFilterDirty = false
end

local function handle_overlay_wheel(_, delta)
    if not (isActive and (get_opt("overlay_alt_interactive") ~= false) and is_alt_down_clean() and not panelHidden) then
        return
    end
    local step = (delta and delta > 0) and 1 or -1
    local rawShift = IsShiftKeyDown and IsShiftKeyDown()
    local shiftNow = (not is_secret(rawShift)) and (rawShift and true or false) or false

    if shiftNow then
        local key = lastUsingNativeGround and "overlay_instance_alpha" or "overlay_alpha"
        local cur = get_opt(key) or (lastUsingNativeGround and 0.35 or 0.85)
        local nxt = math_max(0.15, math_min(1.0, round_num(cur + step * 0.05, 2)))
        if _G.SfuiDB then
            _G.SfuiDB[key] = nxt
        end
        viewCache.dirty = true
        update_effective_alphas(true)
    else
        local curZ = get_opt("overlay_zoom") or 1
        local nxtZ = math_max(0, math_min(5, math_floor(curZ + 0.5) + step))
        if _G.SfuiDB then
            _G.SfuiDB.overlay_zoom = nxtZ
        end
        if Minimap and Minimap.SetZoom then
            Minimap:SetZoom(nxtZ)
        end
        viewCache.dirty = true
        if update_view then
            update_view(0)
        end
    end
end

local function is_generic_minimap_pin(ch, hbdMap)
    if not ch or (ch.IsForbidden and ch:IsForbidden()) then
        return false
    end
    if ch == _G.MinimapBackdrop or ch == _G.HybridMinimap or ch == _G.sfuiMinimapPinsContainer then
        return false
    end
    if Minimap and (ch == Minimap.ZoomIn or ch == Minimap.ZoomOut or ch == Minimap.ZoomHitArea) then
        return false
    end
    local name = ch.GetName and ch:GetName()
    if type(name) == "string" and name:find("^sfui") then
        return false
    end
    if hbdMap and hbdMap[ch] ~= nil then
        return false
    end
    return (ch.IsObjectType and ch:IsObjectType("Button"))
        or (ch.GetScript and ch:GetScript("OnEnter") ~= nil)
end

local function trigger_minimap_native_hover()
    if not (Minimap and Minimap.IsShown and Minimap:IsShown() and Minimap.IsMouseOver and Minimap:IsMouseOver()) then
        return
    end
    local me = Minimap.GetScript and Minimap:GetScript("OnEnter")
    if me then
        me(Minimap)
        local ou = Minimap.GetScript and Minimap:GetScript("OnUpdate")
        if ou then
            ou(Minimap, 0)
        end
    end
    if Minimap.ZoomIn and Minimap.ZoomIn.Hide then Minimap.ZoomIn:Hide() end
    if Minimap.ZoomOut and Minimap.ZoomOut.Hide then Minimap.ZoomOut:Hide() end
end

local function trigger_hovered_pin_on_enter(hbdPins, minimapChildren)
    for _, btn in ipairs(activePinButtons) do
        if btn and btn.IsShown and btn:IsShown() and btn.IsMouseOver and btn:IsMouseOver() then
            if pin_on_enter then
                pin_on_enter(btn)
                return true
            end
        end
    end
    if sfui.map and sfui.map.pins and sfui.map.pins.TriggerHoveredMinimapPinEnter
        and sfui.map.pins.TriggerHoveredMinimapPinEnter() then
        return true
    end
    if hbdPins then
        local src = hbdPins.activeMinimapPins or hbdPins.minimapPins
        if src then
            for pin in pairs(src) do
                if pin and not pin.hidden and pin.IsShown and pin:IsShown()
                    and pin.IsMouseOver and pin:IsMouseOver() then
                    local onEnter = pin.GetScript and pin:GetScript("OnEnter")
                    if onEnter then
                        onEnter(pin)
                        return true
                    end
                end
            end
        end
    end
    if minimapChildren then
        for _, ch in ipairs(minimapChildren) do
            if ch and ch.IsShown and ch:IsShown() and ch.IsMouseOver and ch:IsMouseOver() then
                local onEnter = ch.GetScript and ch:GetScript("OnEnter")
                if onEnter then
                    onEnter(ch)
                    return true
                end
            end
        end
    end
    return false
end

apply_pin_mouse_state = function()
    local altOpt = get_opt("overlay_alt_interactive") ~= false
    local altNow = is_alt_down_clean()
    local overlayInteractive = (isActive and altOpt and altNow and not panelHidden) and true or false
    local becameInteractive = overlayInteractive and not lastOverlayInteractive
    local leftInteractive = lastOverlayInteractive and not overlayInteractive
    lastOverlayInteractive = overlayInteractive
    local interactive = (not isActive) or overlayInteractive
    local wheelActive = overlayInteractive
    local blocked = false

    if Minimap then
        if can_modify_region(Minimap) then
            if not isActive then
                if Minimap.EnableMouse then Minimap:EnableMouse(true) end
                if Minimap.SetMouseClickEnabled then Minimap:SetMouseClickEnabled(true) end
                if Minimap.SetMouseMotionEnabled then Minimap:SetMouseMotionEnabled(true) end
            elseif overlayInteractive then
                if Minimap.SetMouseClickEnabled and Minimap.SetMouseMotionEnabled then
                    Minimap:SetMouseClickEnabled(false)
                    Minimap:SetMouseMotionEnabled(true)
                elseif Minimap.EnableMouseMotion then
                    if Minimap.EnableMouse then Minimap:EnableMouse(false) end
                    Minimap:EnableMouseMotion(true)
                elseif Minimap.EnableMouse then
                    Minimap:EnableMouse(true)
                end
            else
                if leftInteractive then
                    local ml = Minimap.GetScript and Minimap:GetScript("OnLeave")
                    if ml then ml(Minimap) end
                    if Minimap.SetScript and Minimap.GetScript and Minimap:GetScript("OnUpdate") then
                        Minimap:SetScript("OnUpdate", nil)
                    end
                end
                if Minimap.EnableMouse then Minimap:EnableMouse(false) end
                if Minimap.SetMouseClickEnabled then Minimap:SetMouseClickEnabled(false) end
                if Minimap.SetMouseMotionEnabled then Minimap:SetMouseMotionEnabled(false) end
            end
        else
            blocked = true
        end
    end

    local hbdPins = get_questie_hbd_pins()
    local hbdMap = hbdPins and hbdPins.minimapPins
    if hbdMap then
        for pin in pairs(hbdMap) do
            if pin and pin.EnableMouse then
                if can_modify_region(pin) then
                    pin:EnableMouse(interactive)
                else
                    blocked = true
                end
            end
        end
    end

    if sfui.map and sfui.map.pins and sfui.map.pins.SetMinimapPinsMouseEnabled then
        sfui.map.pins.SetMinimapPinsMouseEnabled(interactive)
    end

    for _, btn in ipairs(activePinButtons) do
        if btn then
            if btn.EnableMouse then
                if can_modify_region(btn) then
                    btn:EnableMouse(interactive)
                else
                    blocked = true
                end
            end
            if btn.EnableMouseWheel and can_modify_region(btn) then
                btn:EnableMouseWheel(wheelActive)
            end
        end
    end

    local genericChildren = nil
    if Minimap and Minimap.GetChildren then
        local rawChildren = { Minimap:GetChildren() }
        for _, ch in ipairs(rawChildren) do
            if is_generic_minimap_pin(ch, hbdMap) then
                genericChildren = genericChildren or {}
                genericChildren[#genericChildren + 1] = ch
                if ch.EnableMouse then
                    if can_modify_region(ch) then
                        ch:EnableMouse(interactive)
                    else
                        blocked = true
                    end
                end
            end
        end
    end

    if wheelCatcher and wheelCatcher.EnableMouseWheel then
        if can_modify_region(wheelCatcher) then
            wheelCatcher:EnableMouseWheel(wheelActive)
        else
            blocked = true
        end
    end

    if isActive and becameInteractive then
        if not trigger_hovered_pin_on_enter(hbdPins, genericChildren) then
            trigger_minimap_native_hover()
        end
    elseif leftInteractive then
        if sfui.common and sfui.common.hide_tooltip then
            sfui.common.hide_tooltip()
        end
        if _G.GameTooltip and _G.GameTooltip.IsShown and _G.GameTooltip:IsShown() then
            _G.GameTooltip:Hide()
        end
    end

    pendingMouseSync = blocked
end

local function force_hbd_reposition()
    local hbdPins = get_questie_hbd_pins()
    if hbdPins and Minimap then
        if hbdPins.SetMinimapObject then
            hbdPins:SetMinimapObject(Minimap)
        elseif hbdPins.UpdateMinimapPins then
            hbdPins:UpdateMinimapPins(true)
        end
    end
    if sfui.map and sfui.map.pins and sfui.map.pins.RequestMinimapRefresh then
        sfui.map.pins.RequestMinimapRefresh(0)
    end
end

-- ── Minimap CVar & Surround Sync ──────────────────────────────────────────────
local function get_rotate_cvar()
    local rv = (sfui.common and sfui.common.get_cvar and sfui.common.get_cvar("rotateMinimap"))
        or (_G.C_CVar and _G.C_CVar.GetCVar and _G.C_CVar.GetCVar("rotateMinimap"))
        or (GetCVar and GetCVar("rotateMinimap"))
    if rv == nil or is_secret(rv) or type(rv) ~= "string" then
        if _G.CVarCallbackRegistry and _G.CVarCallbackRegistry.GetCVarValueBool then
            local b = _G.CVarCallbackRegistry:GetCVarValueBool("rotateMinimap")
            if not is_secret(b) then
                return b and "1" or "0"
            end
        end
        return "0"
    end
    return rv
end

-- Direct CVar write so rotateMinimap still switches immediately in combat lockdown.
local function set_rotate_cvar(val)
    if _G.C_CVar and _G.C_CVar.SetCVar then
        _G.C_CVar.SetCVar("rotateMinimap", val)
    elseif SetCVar then
        SetCVar("rotateMinimap", val)
    end
end

local function sync_rotate_cvar(wantRotate)
    if wantRotate then
        if savedRotate == nil and (_G.SfuiDB == nil or _G.SfuiDB._overlaySavedRotate == nil) then
            local cur = get_rotate_cvar()
            savedRotate = cur
            if _G.SfuiDB then
                _G.SfuiDB._overlaySavedRotate = cur
            end
        end
        if get_rotate_cvar() ~= "1" then
            set_rotate_cvar("1")
        end
    else
        local restore = savedRotate or (_G.SfuiDB and _G.SfuiDB._overlaySavedRotate)
        if restore ~= nil then
            savedRotate = nil
            if _G.SfuiDB then
                _G.SfuiDB._overlaySavedRotate = nil
            end
            if get_rotate_cvar() ~= restore then
                set_rotate_cvar(restore)
            end
        end
    end
end

local function sync_blob_rings(suppress)
    if not Minimap then return end
    local ringA = suppress and 0 or 1
    local fillA = suppress and 0 or 0.3
    if Minimap.SetQuestBlobRingAlpha then Minimap:SetQuestBlobRingAlpha(ringA) end
    if Minimap.SetQuestBlobInsideAlpha then Minimap:SetQuestBlobInsideAlpha(fillA) end
    if Minimap.SetQuestBlobOutsideAlpha then Minimap:SetQuestBlobOutsideAlpha(fillA) end
    if Minimap.SetArchBlobRingAlpha then Minimap:SetArchBlobRingAlpha(ringA) end
end

local function nudge_minimap_zoom()
    if nudgingZoom or not (Minimap and Minimap.GetZoom and Minimap.SetZoom) then
        return
    end
    local z = Minimap:GetZoom()
    if is_secret(z) or type(z) ~= "number" then
        return
    end
    nudgingZoom = true
    local altZ = (z > 0) and (z - 1) or 1
    Minimap:SetZoom(altZ)
    Minimap:SetZoom(z)
    nudgingZoom = false
end

local function sync_ground_textures(suppress)
    local wantDraw = not (suppress and true or false)
    local cMini = _G.C_Minimap
    local curDraw = cMini and cMini.GetDrawGroundTextures and cMini.GetDrawGroundTextures()
    if is_secret(curDraw) or type(curDraw) ~= "boolean" then
        curDraw = nil
    end
    if groundSuppressed == (not wantDraw) and (curDraw == nil or curDraw == wantDraw) then
        return false
    end
    local wasSuppressed = (groundSuppressed == true) or (curDraw == false)
    groundSuppressed = not wantDraw
    if cMini and cMini.SetDrawGroundTextures then
        cMini.SetDrawGroundTextures(wantDraw)
    end
    if wantDraw and wasSuppressed then
        nudge_minimap_zoom()
    end
    return true
end

-- ── Frame Holder, Mover & Canvas Layout ───────────────────────────────────────
local function ensure_holder()
    if holderFrame then return end
    holderFrame = CreateFrame("Frame", "sfui_MapOverlayHolder", UIParent)
    holderFrame:SetSize(220, 220)
    holderFrame:EnableMouse(false)
    holderFrame:SetPoint("CENTER", UIParent, "CENTER", get_opt("overlay_x") or 0, get_opt("overlay_y") or 0)
end

local function apply_holder_position()
    if not holderFrame or not can_modify_region(holderFrame) then return end
    local ox = get_opt("overlay_x") or 0
    local oy = get_opt("overlay_y") or 0
    holderFrame:ClearAllPoints()
    holderFrame:SetPoint("CENTER", UIParent, "CENTER", ox, oy)
end

local function register_mover()
    if moverRegistered or not (sfui.movers and sfui.movers.Register) then return end
    ensure_holder()
    moverRegistered = true
    sfui.movers.Register(holderFrame, {
        key = "map_overlay",
        label = "minimap overlay",
        preferredPoint = "CENTER",
        customSize = function()
            local s = math_min(get_opt("overlay_size") or 560, 260)
            return s, s
        end,
        getPoint = function()
            return "CENTER", UIParent, "CENTER", get_opt("overlay_x") or 0, get_opt("overlay_y") or 0
        end,
        setPoint = function(_, _, _, x, y)
            if _G.SfuiDB then
                _G.SfuiDB.overlay_x = round_num(x or 0, 0)
                _G.SfuiDB.overlay_y = round_num(y or 0, 0)
            end
            apply_holder_position()
            overlay:RefreshLayout()
        end,
        resetPosition = function()
            if _G.SfuiDB then
                _G.SfuiDB.overlay_x = 0
                _G.SfuiDB.overlay_y = 0
            end
            apply_holder_position()
            overlay:RefreshLayout()
        end,
        isEnabled = function() return true end,
    })
end

local function ensure_frames()
    ensure_holder()
    if canvasFrame then return end

    canvasFrame = CreateFrame("Frame", "sfui_MapOverlayCanvas", UIParent)
    canvasFrame:SetFrameStrata("LOW")
    canvasFrame:SetFrameLevel(6)
    canvasFrame:EnableMouse(false)
    canvasFrame:SetClipsChildren(true)
    canvasFrame:Hide()

    radialMask = canvasFrame:CreateMaskTexture()
    radialMask:SetAllPoints(canvasFrame)
    radialMask:SetTexture(MASK_PATH, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")

    wheelCatcher = CreateFrame("Frame", "sfui_MapOverlayWheel", UIParent)
    wheelCatcher:SetFrameStrata("LOW")
    wheelCatcher:SetFrameLevel(5)
    wheelCatcher:SetAllPoints(canvasFrame)
    wheelCatcher:EnableMouse(false)
    wheelCatcher:EnableMouseWheel(false)
    wheelCatcher:SetScript("OnMouseWheel", handle_overlay_wheel)
    wheelCatcher:Hide()

    pinFrame = CreateFrame("Frame", "sfui_MapOverlayPins", UIParent)
    pinFrame:SetFrameStrata("LOW")
    pinFrame:SetFrameLevel(14)
    pinFrame:EnableMouse(false)
    pinFrame:SetClipsChildren(true)
    pinFrame:Hide()
end

local function refresh_canvas_layout()
    if not canvasFrame then return end
    apply_holder_position()

    local sz = get_opt("overlay_size") or 560
    canvasFrame:ClearAllPoints()
    canvasFrame:SetPoint("CENTER", holderFrame, "CENTER", 0, 0)
    canvasFrame:SetSize(sz, sz)

    if pinFrame then
        pinFrame:ClearAllPoints()
        pinFrame:SetPoint("CENTER", holderFrame, "CENTER", 0, 0)
        pinFrame:SetSize(sz, sz)
    end

    viewCache.dirty = true
    update_effective_alphas(true)

    if isActive and Minimap then
        if can_modify_region(Minimap) then
            Minimap:ClearAllPoints()
            Minimap:SetPoint("CENTER", canvasFrame, "CENTER", 0, 0)
            Minimap:SetSize(sz, sz)
            force_hbd_reposition()
        else
            pendingCombatSync = true
        end
    end
end

local function hook_hybrid_minimap()
    if hybridHooked then return end
    local hybrid = _G.HybridMinimap
    if not hybrid or not hybrid.HookScript then return end
    hybridHooked = true
    hybrid:HookScript("OnShow", function(self)
        if isActive then
            self:SetAlpha(0)
            groundSuppressed = nil
            sync_ground_textures(not lastUsingNativeGround)
            if _G.C_Minimap and _G.C_Minimap.SetIgnoreRotateMinimap then
                _G.C_Minimap.SetIgnoreRotateMinimap(false)
            end
        end
    end)
    hybrid:HookScript("OnHide", function()
        if isActive then
            groundSuppressed = nil
            sync_ground_textures(not lastUsingNativeGround)
        end
    end)
end

local function hook_minimap_zoom_buttons()
    if zoomButtonsHooked or not Minimap then return end
    if Minimap.ZoomIn or Minimap.ZoomOut then
        zoomButtonsHooked = true
    end
    for _, zb in ipairs({ Minimap.ZoomIn, Minimap.ZoomOut }) do
        if zb and zb.HookScript then
            zb:HookScript("OnShow", function(self)
                if isActive and self.Hide then
                    self:Hide()
                end
            end)
        end
    end
end

local function suppress_blizzard_surround(active)
    hook_minimap_zoom_buttons()

    local frames = {
        _G.MinimapCompassTexture,
        _G.MinimapCompassTextureUnderlay,
        _G.sfui_SquareMinimapBackdrop,
        _G.sfui_SquareMinimapBronzeOverlay,
    }
    if _G.MinimapCluster and _G.MinimapCluster.DielFrame then
        frames[#frames + 1] = _G.MinimapCluster.DielFrame
    end
    for _, f in ipairs(frames) do
        if f and f.SetAlpha then
            f:SetAlpha(active and 0 or 1)
        end
        if f and f.EnableMouse and active and can_modify_region(f) then
            f:EnableMouse(false)
        end
    end

    if Minimap then
        for _, zb in ipairs({ Minimap.ZoomIn, Minimap.ZoomOut }) do
            if zb then
                if zb.SetAlpha then zb:SetAlpha(active and 0 or 1) end
                if active and zb.Hide then zb:Hide() end
                if zb.EnableMouse and can_modify_region(zb) then
                    zb:EnableMouse(not active)
                end
            end
        end
        if Minimap.ZoomHitArea then
            if Minimap.ZoomHitArea.SetAlpha then Minimap.ZoomHitArea:SetAlpha(active and 0 or 1) end
            if Minimap.ZoomHitArea.EnableMouse and can_modify_region(Minimap.ZoomHitArea) then
                Minimap.ZoomHitArea:EnableMouse(not active)
            end
        end
    end

    local mb = _G.MinimapBackdrop
    if mb then
        if active and mb.EnableMouse and can_modify_region(mb) then
            mb:EnableMouse(false)
        end
        if mb.ExternalEventURLButton then
            if mb.ExternalEventURLButton.SetAlpha then
                mb.ExternalEventURLButton:SetAlpha(active and 0 or 1)
            end
            if mb.ExternalEventURLButton.EnableMouse and can_modify_region(mb.ExternalEventURLButton) then
                mb.ExternalEventURLButton:EnableMouse(not active)
            end
        end
    end

    if _G.HybridMinimap then
        hook_hybrid_minimap()
        if _G.HybridMinimap.SetAlpha then
            _G.HybridMinimap:SetAlpha(active and 0 or 1)
        end
    end
end

local function apply_overlay_mask()
    if not (Minimap and Minimap.SetMaskTexture) then return end
    if sfui.map and sfui.map.square then
        sfui.map.square._internalMaskChange = true
    end
    pcall(Minimap.SetMaskTexture, Minimap, MASK_PATH)
    if sfui.map and sfui.map.square then
        sfui.map.square._internalMaskChange = nil
    end
    suppress_blizzard_surround(true)
end

local function hook_minimap_cluster()
    if clusterHooked then return end
    local cluster = _G.MinimapCluster
    if not cluster or not cluster.UpdateMinimapConfig or not _G.hooksecurefunc then return end
    clusterHooked = true
    _G.hooksecurefunc(cluster, "UpdateMinimapConfig", function()
        if isActive then
            apply_overlay_mask()
            refresh_canvas_layout()
        end
    end)
end

local function restore_corner_minimap_immediate()
    local isSquare = sfui.map and sfui.map.square and sfui.map.square.IsEnabled and sfui.map.square:IsEnabled()
    local holder = sfui.minimap and sfui.minimap.Holder
    local w = (holder and holder.GetWidth and holder:GetWidth() and holder:GetWidth() > 0 and holder:GetWidth())
        or (_G.SfuiDB and _G.SfuiDB.minimap_width)
        or 220
    local h = (holder and holder.GetHeight and holder:GetHeight() and holder:GetHeight() > 0 and holder:GetHeight())
        or (_G.SfuiDB and _G.SfuiDB.minimap_height)
        or 220

    if Minimap and Minimap.SetMaskTexture then
        if sfui.map and sfui.map.square then
            sfui.map.square._internalMaskChange = true
        end
        if isSquare then
            local ok = pcall(Minimap.SetMaskTexture, Minimap, "SquareMask")
            if not ok then
                ok = pcall(Minimap.SetMaskTexture, Minimap, 130937)
                if not ok then
                    pcall(Minimap.SetMaskTexture, Minimap, "Interface\\ChatFrame\\ChatFrameBackground")
                end
            end
        elseif sfui.isCamelot and _G.MinimapCluster and _G.MinimapCluster.UpdateMinimapConfig then
            _G.MinimapCluster:UpdateMinimapConfig()
        else
            local ok = pcall(Minimap.SetMaskTexture, Minimap, "ui-hud-minimap-frame-generic-mask")
            if not ok then
                pcall(Minimap.SetMaskTexture, Minimap, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
            end
        end
        if sfui.map and sfui.map.square then
            sfui.map.square._internalMaskChange = nil
        end
    end

    if Minimap and holder and can_modify_region(Minimap) then
        if isSquare then
            Minimap:ClearAllPoints()
            Minimap:SetPoint("CENTER", holder, "CENTER", 0, 0)
            Minimap:SetSize(w, h)
            if _G.sfui_SquareMinimapBackdrop then
                _G.sfui_SquareMinimapBackdrop:SetAlpha(1)
                _G.sfui_SquareMinimapBackdrop:Show()
            end
            if _G.sfui_SquareMinimapBronzeOverlay then
                _G.sfui_SquareMinimapBronzeOverlay:SetAlpha(1)
                _G.sfui_SquareMinimapBronzeOverlay:SetShown(_G.SfuiDB and _G.SfuiDB.minimap_square_bronze == true or false)
            end
            if _G.MinimapCompassTexture then _G.MinimapCompassTexture:SetAlpha(0) end
            if _G.MinimapCompassTextureUnderlay then _G.MinimapCompassTextureUnderlay:SetAlpha(0) end
            if _G.MinimapCluster and _G.MinimapCluster.DielFrame then _G.MinimapCluster.DielFrame:SetAlpha(0) end
        else
            local baseScale = w / 220
            local scale = (baseScale > 0.2) and baseScale or 1.0
            local aperture = 192 * scale
            local offX = 4 * scale
            local offY = -4 * scale
            Minimap:ClearAllPoints()
            Minimap:SetPoint("CENTER", holder, "CENTER", -offX, -offY)
            Minimap:SetSize(aperture, aperture)
            if _G.sfui_SquareMinimapBackdrop then _G.sfui_SquareMinimapBackdrop:Hide() end
            if _G.sfui_SquareMinimapBronzeOverlay then _G.sfui_SquareMinimapBronzeOverlay:Hide() end
        end
    elseif Minimap and not can_modify_region(Minimap) then
        pendingCombatSync = true
    end
end

local function apply_minimap_state()
    pendingCombatSync = false
    ensure_frames()

    if isActive then
        hook_minimap_cluster()
        hook_ui_panels()
        sync_rotate_cvar(get_opt("overlay_rotate") ~= false)
        sync_blob_rings(true)

        lastUsingNativeGround = false
        hbdFilterDirty = true
        panelHidden = has_blocking_panel_open()
        viewCache.dirty = true

        if Minimap then
            if savedZoom == nil and Minimap.GetZoom then
                savedZoom = Minimap:GetZoom()
            end
            if Minimap.SetZoom then
                local targetZoom = math_max(0, math_min(5, math_floor((get_opt("overlay_zoom") or 1) + 0.5)))
                Minimap:SetZoom(targetZoom)
            end
            if can_modify_region(Minimap) then
                if Minimap.SetFixedFrameStrata then Minimap:SetFixedFrameStrata(false) end
                if Minimap.SetFixedFrameLevel then Minimap:SetFixedFrameLevel(false) end
                if Minimap.GetParent and Minimap:GetParent() ~= UIParent then
                    Minimap:SetParent(UIParent)
                end
                Minimap:SetFrameStrata("LOW")
                Minimap:SetFrameLevel(10)
                if Minimap.EnableMouse then Minimap:EnableMouse(false) end
                if Minimap.EnableMouseWheel then Minimap:EnableMouseWheel(false) end
            else
                pendingCombatSync = true
            end
            apply_overlay_mask()
        else
            suppress_blizzard_surround(true)
        end

        groundSuppressed = nil
        if _G.C_Minimap and _G.C_Minimap.SetIgnoreRotateMinimap then
            _G.C_Minimap.SetIgnoreRotateMinimap(false)
        end

        canvasFrame:Show()
        if wheelCatcher then wheelCatcher:Show() end
        refresh_canvas_layout()
    else
        canvasFrame:Hide()
        if wheelCatcher then wheelCatcher:Hide() end
        pinFrame:Hide()
        sync_rotate_cvar(false)
        sync_questie_hbd_filter("restore", true)
        suppress_blizzard_surround(false)
        sync_blob_rings(false)
        groundSuppressed = nil
        lastUsingNativeGround = false
        panelHidden = false
        alphaState.appCanvas, alphaState.appMini, alphaState.appPins = nil, nil, nil
        update_effective_alphas(true)

        local hybridShown = (_G.HybridMinimap and _G.HybridMinimap.IsShown and _G.HybridMinimap:IsShown())
        if _G.C_Minimap and _G.C_Minimap.SetDrawGroundTextures then
            _G.C_Minimap.SetDrawGroundTextures(not hybridShown)
        end
        if _G.C_Minimap and _G.C_Minimap.SetIgnoreRotateMinimap then
            _G.C_Minimap.SetIgnoreRotateMinimap(hybridShown and true or false)
        end

        if Minimap then
            if Minimap.SetAlpha then Minimap:SetAlpha(1) end
            if savedZoom ~= nil and Minimap.SetZoom then
                Minimap:SetZoom(savedZoom)
                savedZoom = nil
            end
            if can_modify_region(Minimap) then
                if Minimap.EnableMouse then Minimap:EnableMouse(true) end
                if Minimap.EnableMouseWheel then Minimap:EnableMouseWheel(true) end
            else
                pendingCombatSync = true
            end
        end

        if InCombatLockdown and InCombatLockdown() then
            restore_corner_minimap_immediate()
        end

        if sfui.map and sfui.map.square and sfui.map.square.Apply then
            sfui.map.square:Apply()
        elseif sfui.minimap and sfui.minimap.update_position then
            sfui.minimap.update_position()
        end
    end

    if sfui.minimap and sfui.minimap.refresh then
        sfui.minimap.refresh()
    end
    apply_pin_mouse_state()
    force_hbd_reposition()
end

-- ── Player State, Waypoint & Corpse Navigation Targets ────────────────────────
local function get_player_world_state()
    local bestMapID = _G.C_Map and _G.C_Map.GetBestMapForUnit and _G.C_Map.GetBestMapForUnit("player")
    if is_secret(bestMapID) or type(bestMapID) ~= "number" then
        bestMapID = nil
    end

    local wx, wy, cont
    if UnitPosition then
        local ux, uy, _, ucont = UnitPosition("player")
        if ux ~= nil and uy ~= nil and not is_secret(ux) and not is_secret(uy) and not is_secret(ucont) then
            wx, wy, cont = ux, uy, ucont
        end
    end

    if (not wx or not wy) and bestMapID and _G.C_Map and _G.C_Map.GetPlayerMapPosition and _G.C_Map.GetWorldPosFromMapPos then
        local pos = _G.C_Map.GetPlayerMapPosition(bestMapID, "player")
        if pos and not is_secret(pos) and pos.GetXY then
            local c, wpos = _G.C_Map.GetWorldPosFromMapPos(bestMapID, pos)
            if c ~= nil and wpos ~= nil and not is_secret(c) and not is_secret(wpos) and wpos.GetXY then
                local pwX, pwY = wpos:GetXY()
                if pwX ~= nil and pwY ~= nil and not is_secret(pwX) and not is_secret(pwY) then
                    wx, wy, cont = pwX, pwY, c
                end
            end
        end
    end

    if cont == nil and GetInstanceInfo then
        local _, _, _, _, _, _, _, instID = GetInstanceInfo()
        if instID ~= nil and not is_secret(instID) and type(instID) == "number" and instID > 0 then
            cont = instID
        end
    end

    local viewRadius = _G.C_Minimap and _G.C_Minimap.GetViewRadius and _G.C_Minimap.GetViewRadius()
    if is_secret(viewRadius) or type(viewRadius) ~= "number" or viewRadius <= 0 then
        local z = (Minimap and Minimap.GetZoom and Minimap:GetZoom()) or 0
        if is_secret(z) or type(z) ~= "number" then z = 0 end
        local rawIndoors = IsIndoors and IsIndoors()
        local indoors = (not is_secret(rawIndoors)) and rawIndoors or false
        local inInst = sfui.state and sfui.state.Is and sfui.state.Is("inInstance")
        if inInst == nil and IsInInstance then
            local r = IsInInstance()
            inInst = (not is_secret(r)) and (r and true or false) or false
        end
        if inInst then indoors = true end
        viewRadius = (indoors and ZOOM_RADII_INDOOR[z] or ZOOM_RADII_OUTDOOR[z]) or 100
    end

    local rotate = (get_rotate_cvar() == "1")
    local facing = 0
    if rotate and GetPlayerFacing then
        local f = GetPlayerFacing()
        if f ~= nil and not is_secret(f) and type(f) == "number" then
            facing = f
        end
    end

    return wx, wy, cont, bestMapID, facing, viewRadius, rotate
end

local function refresh_nav_targets()
    local newWP = nil
    local cMap = _G.C_Map
    if cMap and cMap.GetUserWaypoint and cMap.GetWorldPosFromMapPos then
        local hasWP = (cMap.HasUserWaypoint == nil) or cMap.HasUserWaypoint()
        if not is_secret(hasWP) and hasWP then
            local wp = cMap.GetUserWaypoint()
            if wp and not is_secret(wp) and type(wp) == "table" then
                local mapID = wp.uiMapID
                local pos = wp.position
                if not is_secret(mapID) and type(mapID) == "number"
                    and pos and not is_secret(pos) and pos.GetXY then
                    local c, wpos = cMap.GetWorldPosFromMapPos(mapID, pos)
                    if c ~= nil and wpos ~= nil and not is_secret(c) and not is_secret(wpos) and wpos.GetXY then
                        local twx, twy = wpos:GetXY()
                        if twx ~= nil and twy ~= nil and not is_secret(twx) and not is_secret(twy) then
                            newWP = {
                                cont = c, wx = twx, wy = twy,
                                kind = "waypoint", title = "user waypoint",
                                r = 0.35, g = 0.85, b = 1.0,
                            }
                        end
                    end
                end
            end
        end
    end

    local newCorpse = nil
    local cDeath = _G.C_DeathInfo
    if is_dead_or_ghost_now() and cDeath and cDeath.GetCorpseMapPosition
        and cMap and cMap.GetBestMapForUnit and cMap.GetWorldPosFromMapPos then
        local bMap = cMap.GetBestMapForUnit("player")
        if not is_secret(bMap) and type(bMap) == "number" then
            local candidateMaps = { bMap }
            if cMap.GetMapInfo then
                local mInfo = cMap.GetMapInfo(bMap)
                if mInfo and not is_secret(mInfo) and type(mInfo.parentMapID) == "number" and mInfo.parentMapID > 0 then
                    candidateMaps[#candidateMaps + 1] = mInfo.parentMapID
                end
            end
            for _, mid in ipairs(candidateMaps) do
                local cpos = cDeath.GetCorpseMapPosition(mid)
                if cpos and not is_secret(cpos) and cpos.GetXY then
                    local cx, cy = cpos:GetXY()
                    if cx and cy and not is_secret(cx) and not is_secret(cy) and (cx > 0 or cy > 0) then
                        local c, wpos = cMap.GetWorldPosFromMapPos(mid, cpos)
                        if c ~= nil and wpos ~= nil and not is_secret(c) and not is_secret(wpos) and wpos.GetXY then
                            local cwx, cwy = wpos:GetXY()
                            if cwx ~= nil and cwy ~= nil and not is_secret(cwx) and not is_secret(cwy) then
                                newCorpse = {
                                    cont = c, wx = cwx, wy = cwy,
                                    kind = "corpse", title = "corpse",
                                    r = 1.0, g = 0.32, b = 0.32,
                                }
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    navTargets.waypoint = newWP
    navTargets.corpse = newCorpse
    navTargets.rev = navTargets.rev + 1
    viewCache.dirty = true
end

-- ── Lean Active-Quest-Only Direct LibQuestieDB Pin Engine ─────────────────────
local function release_pin_cache(cache)
    local rel = sfui.pool and sfui.pool.release_table
    for i = #cache, 1, -1 do
        local rec = cache[i]
        cache[i] = nil
        if rel and type(rec) == "table" then
            rel(rec)
        end
    end
end

local function new_pin_record()
    local acq = sfui.pool and sfui.pool.acquire_table
    return acq and acq() or {}
end

local function get_active_quests_map()
    local qs = sfui.queststate
    if qs and qs.GetAllActive then
        return qs.GetAllActive()
    end
    local inLog = {}
    local num = (_G.C_QuestLog and _G.C_QuestLog.GetNumQuestLogEntries and _G.C_QuestLog.GetNumQuestLogEntries())
        or (_G.GetNumQuestLogEntries and _G.GetNumQuestLogEntries())
        or 0
    if is_secret(num) or type(num) ~= "number" then num = 0 end
    for i = 1, num do
        local info = _G.C_QuestLog and _G.C_QuestLog.GetInfo and _G.C_QuestLog.GetInfo(i)
        if info and info.questID and not info.isHeader then
            local qid = info.questID
            local isComp = _G.C_QuestLog.IsComplete and _G.C_QuestLog.IsComplete(qid)
            inLog[qid] = { isComplete = (not is_secret(isComp)) and (isComp == true), title = info.title }
        elseif _G.GetQuestLogTitle then
            local title, _, _, isHeader, _, complete, _, qid = _G.GetQuestLogTitle(i)
            if qid and not isHeader and qid > 0 then
                inLog[qid] = { isComplete = (complete == 1 or complete == true), title = title }
            end
        end
    end
    return inLog
end

local function get_quest_revision()
    local qs = sfui.queststate
    if qs and qs.GetRevision then
        return qs.GetRevision()
    end
    local qCount = _G.C_QuestLog and _G.C_QuestLog.GetNumQuestLogEntries and _G.C_QuestLog.GetNumQuestLogEntries()
    if is_secret(qCount) or type(qCount) ~= "number" then return 0 end
    return qCount
end

local function project_zone_percent_to_world(uiMapID, xPct, yPct, expectedCont)
    if not (_G.C_Map and _G.C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil, nil end
    local c, wpos = _G.C_Map.GetWorldPosFromMapPos(uiMapID, CreateVector2D(xPct / 100, yPct / 100))
    if c == nil or not wpos or is_secret(c) or is_secret(wpos) or not wpos.GetXY then return nil, nil end
    if expectedCont ~= nil and c ~= expectedCont then return nil, nil end
    local wx, wy = wpos:GetXY()
    if wx == nil or wy == nil or is_secret(wx) or is_secret(wy) then return nil, nil end
    return wx, wy
end

local function resolve_area_to_uimap(areaId, subToUi)
    local m = subToUi and subToUi[areaId]
    if m and m > 0 then return m end
    local loader = _G.QuestieLoader
    if loader and loader._modules and loader._modules["ZoneDB"] and loader.ImportModule then
        local ok, zdb = pcall(loader.ImportModule, loader, "ZoneDB")
        if ok and zdb and zdb.GetUiMapIdByAreaId then
            local zm = zdb:GetUiMapIdByAreaId(areaId)
            if type(zm) == "number" and zm > 0 then
                return zm
            end
        end
    end
    return nil
end

local function get_player_faction_code()
    local faction = (sfui.common and sfui.common.get_player_faction and sfui.common.get_player_faction())
        or (UnitFactionGroup and UnitFactionGroup("player"))
    if is_secret(faction) then return "AH" end
    return (faction == "Alliance" and "A") or (faction == "Horde" and "H") or "AH"
end

local function rebuild_direct_pins(activeCont)
    release_pin_cache(directPinCache)
    directPinsDirty = false
    lastPinCont = activeCont

    local data = get_map_data()
    local QuestDB = _G.QuestDB
    local NpcDB = _G.NpcDB
    local ObjectDB = _G.ObjectDB
    if not (data and QuestDB and NpcDB and ObjectDB and activeCont ~= nil) then return end

    local inLog = get_active_quests_map()
    if next(inLog) == nil then return end

    local ItemDB = _G.ItemDB
    local subToUi = data.subZoneToUiMapId or {}
    local CLUSTER_DIST_SQ = 32 * 32
    local MAX_COORDS = 16
    local MAX_CLUSTERS = 6

    local function add_clustered_spawns(spawns, icon, title, subtitle, kind, size, clusterBase)
        if type(spawns) ~= "table" then return end
        for areaId, list in pairs(spawns) do
            local uiMapID = resolve_area_to_uimap(areaId, subToUi)
            if uiMapID and type(list) == "table" then
                local limit = math_min(#list, MAX_COORDS)
                for i = 1, limit do
                    local coord = list[i]
                    if type(coord) == "table" and coord[1] and coord[2] then
                        local pwx, pwy = project_zone_percent_to_world(uiMapID, coord[1], coord[2], activeCont)
                        if pwx and pwy then
                            local merged = false
                            for j = clusterBase, #directPinCache do
                                local cPin = directPinCache[j]
                                local dx = pwx - cPin.wx
                                local dy = pwy - cPin.wy
                                if (dx * dx + dy * dy) <= CLUSTER_DIST_SQ then
                                    local n = cPin._count + 1
                                    cPin.wx = cPin.wx + (dx / n)
                                    cPin.wy = cPin.wy + (dy / n)
                                    cPin._count = n
                                    merged = true
                                    break
                                end
                            end
                            if (not merged) and ((#directPinCache - clusterBase + 1) < MAX_CLUSTERS) then
                                local rec = new_pin_record()
                                rec.wx = pwx
                                rec.wy = pwy
                                rec.icon = icon
                                rec.title = title
                                rec.subtitle = subtitle
                                rec.kind = kind
                                rec.size = size or 15
                                rec._count = 1
                                directPinCache[#directPinCache + 1] = rec
                            end
                        end
                    end
                end
            end
        end
    end

    for qid, entry in pairs(inLog) do
        local qRow = QuestDB.GetAll(qid, { "name", "objectives", "finishedBy", "triggerEnd" })
        local qTitle = (qRow and qRow[1]) or entry.title or ("quest #" .. tostring(qid))

        if entry.isComplete then
            local fin = qRow and qRow[3]
            if type(fin) == "table" then
                if type(fin[1]) == "table" then
                    for _, nid in ipairs(fin[1]) do
                        local base = #directPinCache + 1
                        local sp = NpcDB.spawns and NpcDB.spawns(nid)
                        local nm = (NpcDB.name and NpcDB.name(nid)) or "npc"
                        add_clustered_spawns(sp, ICON_QUEST_TURNIN, qTitle, nm .. " (turn-in)", "turnin", 17, base)
                    end
                end
                if type(fin[2]) == "table" then
                    for _, oid in ipairs(fin[2]) do
                        local base = #directPinCache + 1
                        local sp = ObjectDB.spawns and ObjectDB.spawns(oid)
                        local nm = (ObjectDB.name and ObjectDB.name(oid)) or "object"
                        add_clustered_spawns(sp, ICON_QUEST_TURNIN, qTitle, nm .. " (turn-in)", "turnin", 17, base)
                    end
                end
            end
        else
            local byType = nil
            local rawObjs = _G.C_QuestLog and _G.C_QuestLog.GetQuestObjectives and _G.C_QuestLog.GetQuestObjectives(qid)
            if type(rawObjs) == "table" and not is_secret(rawObjs) then
                byType = { monster = {}, object = {}, item = {}, event = {} }
                for _, o in ipairs(rawObjs) do
                    if type(o) == "table" and not is_secret(o) then
                        local ot = o.type
                        local finFlag = o.finished
                        if not is_secret(ot) and byType[ot] then
                            local arr = byType[ot]
                            arr[#arr + 1] = (not is_secret(finFlag)) and (finFlag == true) or false
                        end
                    end
                end
            end

            local function is_obj_done(kindKey, idx, total)
                if not byType then return false end
                local arr = byType[kindKey]
                if not arr or #arr == 0 then return false end
                if #arr == total then
                    return arr[idx] == true
                end
                for k = 1, #arr do
                    if not arr[k] then return false end
                end
                return true
            end

            local objsGrp = qRow and qRow[2]
            if type(objsGrp) == "table" then
                if type(objsGrp[1]) == "table" then
                    local total = #objsGrp[1]
                    for idx, pair in ipairs(objsGrp[1]) do
                        local nid = type(pair) == "table" and pair[1]
                        if nid and not is_obj_done("monster", idx, total) then
                            local base = #directPinCache + 1
                            local sp = NpcDB.spawns and NpcDB.spawns(nid)
                            local nName = (pair[2] and pair[2] ~= "" and pair[2]) or (NpcDB.name and NpcDB.name(nid)) or qTitle
                            add_clustered_spawns(sp, ICON_OBJECTIVE, qTitle, nName, "objective", 14, base)
                        end
                    end
                end
                if type(objsGrp[2]) == "table" then
                    local total = #objsGrp[2]
                    for idx, pair in ipairs(objsGrp[2]) do
                        local oid = type(pair) == "table" and pair[1]
                        if oid and not is_obj_done("object", idx, total) then
                            local base = #directPinCache + 1
                            local sp = ObjectDB.spawns and ObjectDB.spawns(oid)
                            local oName = (pair[2] and pair[2] ~= "" and pair[2]) or (ObjectDB.name and ObjectDB.name(oid)) or qTitle
                            add_clustered_spawns(sp, ICON_OBJECTIVE, qTitle, oName, "objective", 14, base)
                        end
                    end
                end
                if ItemDB and type(objsGrp[3]) == "table" then
                    local total = #objsGrp[3]
                    for idx, pair in ipairs(objsGrp[3]) do
                        local itemId = type(pair) == "table" and pair[1]
                        if itemId and not is_obj_done("item", idx, total) then
                            local base = #directPinCache + 1
                            local itemName = (pair[2] and pair[2] ~= "" and pair[2]) or (ItemDB.name and ItemDB.name(itemId)) or qTitle
                            local npcs = ItemDB.npcDrops and ItemDB.npcDrops(itemId)
                            if type(npcs) == "table" then
                                for i = 1, math_min(#npcs, 4) do
                                    local sp = NpcDB.spawns and NpcDB.spawns(npcs[i])
                                    add_clustered_spawns(sp, ICON_OBJECTIVE, qTitle, itemName, "objective", 14, base)
                                end
                            end
                            local objs = ItemDB.objectDrops and ItemDB.objectDrops(itemId)
                            if type(objs) == "table" then
                                for i = 1, math_min(#objs, 4) do
                                    local sp = ObjectDB.spawns and ObjectDB.spawns(objs[i])
                                    add_clustered_spawns(sp, ICON_OBJECTIVE, qTitle, itemName, "objective", 14, base)
                                end
                            end
                        end
                    end
                end
                if type(objsGrp[5]) == "table" then
                    local total = #objsGrp[5]
                    for idx, tup in ipairs(objsGrp[5]) do
                        if type(tup) == "table" and type(tup[1]) == "table" and not is_obj_done("monster", idx, total) then
                            local base = #directPinCache + 1
                            local kName = (tup[3] and tup[3] ~= "" and tup[3])
                                or (tup[2] and NpcDB.name and NpcDB.name(tup[2]))
                                or qTitle
                            local ids = tup[1]
                            for i = 1, math_min(#ids, 6) do
                                local sp = NpcDB.spawns and NpcDB.spawns(ids[i])
                                add_clustered_spawns(sp, ICON_OBJECTIVE, qTitle, kName, "objective", 14, base)
                            end
                        end
                    end
                end
            end

            local trig = qRow and qRow[4]
            if type(trig) == "table" and type(trig[2]) == "table" and not is_obj_done("event", 1, 1) then
                local base = #directPinCache + 1
                add_clustered_spawns(trig[2], ICON_OBJECTIVE, qTitle, trig[1] or "explore", "objective", 14, base)
            end
        end
    end
end

local function rebuild_instance_pins(instData, contID)
    release_pin_cache(instPinCache)
    lastInstPinCont = contID
    if not (instData and instData.pins) then return end

    local inLog = get_active_quests_map()
    local factionCode = get_player_faction_code()
    for _, p in ipairs(instData.pins) do
        local show = false
        local icon = ICON_BOSS
        local size = 16
        if p.kind == "boss" then
            show = true
            icon = ICON_BOSS
            size = 16
        elseif not p.faction or factionCode == "AH" or p.faction == factionCode then
            local qid = p.questId
            if qid and inLog[qid] then
                if p.kind == "quest_start" and inLog[qid].isComplete then
                    show = true
                    icon = ICON_QUEST_TURNIN
                    size = 16
                elseif p.kind == "quest_obj" and not inLog[qid].isComplete then
                    show = true
                    icon = ICON_OBJECTIVE
                    size = 14
                end
            end
        end
        if show and p.wx and p.wy then
            local rec = new_pin_record()
            rec.wx = p.wx
            rec.wy = p.wy
            rec.icon = icon
            rec.tc = nil
            rec.title = p.title
            rec.subtitle = p.subtitle
            rec.kind = p.kind
            rec.size = size
            instPinCache[#instPinCache + 1] = rec
        end
    end
end

-- ── Pooled Tile & Pin Renderers ───────────────────────────────────────────────
local function acquire_tile(idx)
    local tex = tilePool[idx]
    if not tex then
        tex = canvasFrame:CreateTexture(nil, "ARTWORK")
        tex:SetTexCoord(0, 1, 0, 1)
        tex:AddMaskTexture(radialMask)
        tilePool[idx] = tex
    end
    tex:Show()
    return tex
end

pin_on_enter = function(self)
    if isActive and Minimap and Minimap.GetScript and Minimap:GetScript("OnUpdate") then
        local ml = Minimap:GetScript("OnLeave")
        if ml then
            ml(Minimap)
        else
            Minimap:SetScript("OnUpdate", nil)
        end
    end
    local tip = (sfui.common and sfui.common.get_tooltip and sfui.common.get_tooltip()) or _G.GameTooltip
    if not tip then return end
    tip:SetOwner(self, "ANCHOR_RIGHT")
    if tip.SetFrameStrata then
        tip:SetFrameStrata("TOOLTIP")
    end
    tip:SetText(tostring(self.pinTitle or "pin"):lower(), 1, 0.85, 0.25)
    if self.pinSubtitle and self.pinSubtitle ~= "" then
        tip:AddLine(tostring(self.pinSubtitle):lower(), 0.85, 0.85, 0.85, true)
    end
    tip:Show()
end

local function pin_on_leave(self)
    if sfui.common and sfui.common.hide_tooltip then
        sfui.common.hide_tooltip()
    end
    if _G.GameTooltip and _G.GameTooltip.Hide then
        if not self or not _G.GameTooltip.IsOwned or _G.GameTooltip:IsOwned(self) then
            _G.GameTooltip:Hide()
        end
    end
    if lastOverlayInteractive then
        trigger_minimap_native_hover()
    end
end

local function acquire_pin_button(idx, interactive, wheelActive)
    local btn = pinPool[idx]
    if not btn then
        btn = CreateFrame("Button", nil, pinFrame)
        btn:SetSize(16, 16)
        btn.tex = btn:CreateTexture(nil, "OVERLAY")
        btn.tex:SetAllPoints(btn)
        btn:SetScript("OnEnter", pin_on_enter)
        btn:SetScript("OnLeave", pin_on_leave)
        btn:SetScript("OnMouseWheel", handle_overlay_wheel)
        pinPool[idx] = btn
    end
    if can_modify_region(btn) then
        if btn.EnableMouse then btn:EnableMouse(interactive and true or false) end
        if btn.EnableMouseWheel then btn:EnableMouseWheel(wheelActive and true or false) end
    end
    btn:Show()
    activePinButtons[idx] = btn
    return btn
end

local function set_pin_texture(btn, iconPath, tc, rot, r, g, b, a)
    local t = btn.tex
    if btn._lastIcon ~= iconPath then
        btn._lastIcon = iconPath
        t:SetTexture(iconPath)
    end
    local tc1, tc2, tc3, tc4
    if tc then
        tc1, tc2, tc3, tc4 = tc[1], tc[2], tc[3], tc[4]
    else
        tc1, tc2, tc3, tc4 = 0, 1, 0, 1
    end
    if btn._lastTC1 ~= tc1 or btn._lastTC2 ~= tc2 or btn._lastTC3 ~= tc3 or btn._lastTC4 ~= tc4 then
        btn._lastTC1, btn._lastTC2, btn._lastTC3, btn._lastTC4 = tc1, tc2, tc3, tc4
        t:SetTexCoord(tc1, tc2, tc3, tc4)
    end
    if btn._lastRot ~= rot and t.SetRotation then
        btn._lastRot = rot
        t:SetRotation(rot)
    end
    local rr, gg, bb, aa = r or 1, g or 1, b or 1, a or 1
    if btn._lastR ~= rr or btn._lastG ~= gg or btn._lastB ~= bb or btn._lastA ~= aa then
        btn._lastR, btn._lastG, btn._lastB, btn._lastA = rr, gg, bb, aa
        if t.SetVertexColor then
            t:SetVertexColor(rr, gg, bb, aa)
        end
    end
end

local function project_pin_list(pinList, pinIdx, interactive, wheelActive, pinScale, wx, wy, cosF, sinF, ppy, viewRadius, defaultIcon, defaultSize)
    for _, p in ipairs(pinList) do
        local dx = wy - p.wy
        local dy = wx - p.wx
        local rx = dx * cosF - dy * sinF
        local ry = dx * sinF + dy * cosF
        local normR = math_sqrt(rx * rx + ry * ry) / viewRadius
        if normR <= 0.96 then
            pinIdx = pinIdx + 1
            local btn = acquire_pin_button(pinIdx, interactive, wheelActive)
            local pSize = (p.size or defaultSize or 16) * pinScale
            btn:SetSize(pSize, pSize)
            set_pin_texture(btn, p.icon or defaultIcon, p.tc, 0, 1, 1, 1, 1)
            btn.pinTitle = p.title
            btn.pinSubtitle = p.subtitle
            btn:ClearAllPoints()
            btn:SetPoint("CENTER", pinFrame, "CENTER", rx * ppy, -ry * ppy)
            local alpha = 1
            if normR > 0.80 then
                alpha = math_max(0, 1 - (normR - 0.80) / 0.16)
            elseif normR < 0.08 then
                alpha = 0.55 + 0.45 * (normR / 0.08)
            end
            btn:SetAlpha(alpha)
        end
    end
    return pinIdx
end

local function project_nav_marker(target, cont, pinIdx, interactive, wheelActive, pinScale, wx, wy, cosF, sinF, ppy, halfSz, viewRadius)
    if not (target and cont ~= nil and target.cont == cont and target.wx and target.wy) then
        return pinIdx
    end
    local dx = wy - target.wy
    local dy = wx - target.wx
    local rx = dx * cosF - dy * sinF
    local ry = dx * sinF + dy * cosF
    local distYds = math_sqrt(rx * rx + ry * ry)
    local normR = distYds / viewRadius

    pinIdx = pinIdx + 1
    local btn = acquire_pin_button(pinIdx, interactive, wheelActive)
    local px, py, pSize, iconPath, rot

    if normR > 0.88 and distYds > 0.001 then
        local edgePx = 0.88 * halfSz
        px = (rx / distYds) * edgePx
        py = (-ry / distYds) * edgePx
        iconPath = CHEVRON_PATH
        rot = math_atan2(-rx, -ry)
        pSize = (target.kind == "corpse" and 20 or 18) * pinScale
    else
        px = rx * ppy
        py = -ry * ppy
        if target.kind == "corpse" then
            iconPath = ICON_BOSS
            rot = 0
            pSize = 16 * pinScale
        else
            iconPath = CHEVRON_PATH
            rot = math_pi
            pSize = 16 * pinScale
        end
    end

    btn:SetSize(pSize, pSize)
    set_pin_texture(btn, iconPath, nil, rot, target.r, target.g, target.b, 1)
    btn.pinTitle = target.title
    btn.pinSubtitle = string_format("%d yd", math_floor(distYds + 0.5))
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", pinFrame, "CENTER", px, py)
    btn:SetAlpha(0.95)
    return pinIdx
end

local function update_hbd_filter_throttled(targetHbdFilter, elapsed)
    hbdFilterAccum = hbdFilterAccum + (elapsed or 0.016)
    if hbdFilterDirty or hbdFilterModeApplied ~= targetHbdFilter then
        sync_questie_hbd_filter(targetHbdFilter, true)
        hbdFilterAccum = 0
    elseif hbdFilterAccum >= 0.5 then
        sync_questie_hbd_filter(targetHbdFilter, false)
        hbdFilterAccum = 0
    end
end

local function is_view_unchanged(hasData, wx, wy, cont, bestMapID, facing, viewRadius, rotate, sz, interactive, mode, pinScale, questRev, navRev)
    if viewCache.dirty or viewCache.hasData ~= hasData then
        return false
    end
    if not wx or not wy then
        return viewCache.noWorld == true
            and viewCache.cont == cont
            and viewCache.mapID == bestMapID
            and viewCache.size == sz
            and math_abs(viewRadius - viewCache.viewRad) < 0.01
            and viewCache.navRev == navRev
    end
    if viewCache.noWorld or viewCache.wx == nil or viewCache.wy == nil then
        return false
    end
    return viewCache.cont == cont
        and viewCache.mapID == bestMapID
        and viewCache.size == sz
        and viewCache.alt == interactive
        and viewCache.mode == mode
        and viewCache.pinScale == pinScale
        and viewCache.questRev == questRev
        and viewCache.navRev == navRev
        and viewCache.rotate == rotate
        and math_abs(wx - viewCache.wx) < 0.02
        and math_abs(wy - viewCache.wy) < 0.02
        and math_abs(facing - viewCache.facing) < 0.0005
        and math_abs(viewRadius - viewCache.viewRad) < 0.01
end

local function record_view_snapshot(hasData, noWorld, wx, wy, cont, bestMapID, facing, viewRadius, rotate, sz, interactive, mode, pinScale, questRev, navRev)
    viewCache.dirty    = false
    viewCache.hasData  = hasData
    viewCache.noWorld  = noWorld
    viewCache.wx       = wx
    viewCache.wy       = wy
    viewCache.cont     = cont
    viewCache.mapID    = bestMapID
    viewCache.facing   = facing
    viewCache.viewRad  = viewRadius
    viewCache.rotate   = rotate
    viewCache.size     = sz
    viewCache.alt      = interactive
    viewCache.mode     = mode
    viewCache.pinScale = pinScale
    viewCache.questRev = questRev
    viewCache.navRev   = navRev
    viewCache.draws    = viewCache.draws + 1
end

update_view = function(elapsed)
    if not isActive or not canvasFrame then return end

    local data = get_map_data()
    local hasData = (data ~= nil)
    local sz = get_opt("overlay_size") or 560
    local wx, wy, cont, bestMapID, facing, viewRadius, rotate = get_player_world_state()
    local mode = get_opt("overlay_pins_mode") or "auto"
    local altNow = is_alt_down_clean()
    local altOpt = get_opt("overlay_alt_interactive") ~= false
    local interactive = (altOpt and altNow and not panelHidden) and true or false
    local wheelActive = interactive
    local pinScale = get_opt("overlay_pin_scale") or 1.0
    local questRev = get_quest_revision()
    local navRev = navTargets.rev

    -- Resolve target Questie HBD filter mode every pass while respecting the 0.5s throttle
    local useDirectQDB = false
    local targetHbdFilter = "hide_all"
    if not wx or not wy then
        targetHbdFilter = (mode == "auto" and is_questie_pins_active()) and "active_only" or "hide_all"
    elseif mode == "questiedb" then
        useDirectQDB = (_G.QuestDB ~= nil and _G.NpcDB ~= nil)
        targetHbdFilter = "hide_all"
    elseif mode == "auto" then
        if is_questie_pins_active() then
            useDirectQDB = false
            targetHbdFilter = "active_only"
        else
            useDirectQDB = (_G.QuestDB ~= nil and _G.NpcDB ~= nil)
            targetHbdFilter = "hide_all"
        end
    end
    update_hbd_filter_throttled(targetHbdFilter, elapsed)

    if is_view_unchanged(hasData, wx, wy, cont, bestMapID, facing, viewRadius, rotate, sz, interactive, mode, pinScale, questRev, navRev) then
        viewCache.idleSkips = viewCache.idleSkips + 1
        return
    end

    if not wx or not wy then
        for i = 1, #activeTiles do
            activeTiles[i]:Hide()
            activeTiles[i] = nil
        end
        for i = 1, #pinPool do
            pinPool[i]:Hide()
            activePinButtons[i] = nil
        end
        local changedNative = (lastUsingNativeGround ~= true)
        lastUsingNativeGround = true
        sync_ground_textures(false)
        update_effective_alphas(changedNative)
        if pinFrame then pinFrame:Hide() end
        record_view_snapshot(hasData, true, nil, nil, cont, bestMapID, facing, viewRadius, rotate, sz, interactive, mode, pinScale, questRev, navRev)
        return
    end

    if rotate and math_abs(facing - lastFacingForPins) > 0.0005 then
        lastFacingForPins = facing
        if sfui.map and sfui.map.pins and sfui.map.pins.UpdateMinimapPins then
            sfui.map.pins.UpdateMinimapPins(false)
        end
    end

    local ppy = sz / (2 * viewRadius)
    local cosF = math_cos(facing)
    local sinF = math_sin(facing)
    local halfSz = sz * 0.5

    local tileIdx = 0
    local function place_tile(texBase, texName, cx, cy, sideYards)
        tileIdx = tileIdx + 1
        local tex = acquire_tile(tileIdx)
        activeTiles[tileIdx] = tex
        local fullPath = texBase .. texName
        if tex._lastPath ~= fullPath then
            tex._lastPath = fullPath
            tex:SetTexture(fullPath, "CLAMP", "CLAMP", "TRILINEAR")
        end
        local dx = wy - cy
        local dy = wx - cx
        local rx = dx * cosF - dy * sinF
        local ry = dx * sinF + dy * cosF
        tex:SetRotation(-facing)
        local pxSize = sideYards * ppy
        tex:SetSize(pxSize, pxSize)
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", canvasFrame, "CENTER", rx * ppy, -ry * ppy)
    end

    local function place_grid(texBase, tiles, maxX, maxY, cols, rows, step, stride)
        if not tiles then return end
        local rMaxSq = (viewRadius + step * 0.78) ^ 2
        for col = 0, cols - 1 do
            for row = 0, rows - 1 do
                local fname = tiles[col * stride + row]
                if fname then
                    local cx = maxX - (row + 0.5) * step
                    local cy = maxY - (col + 0.5) * step
                    local dxC, dyC = wx - cx, wy - cy
                    if (dxC * dxC + dyC * dyC) <= rMaxSq then
                        place_tile(texBase, fname, cx, cy, step)
                    end
                end
            end
        end
    end

    local instData = data and cont and data.instances and data.instances[cont]
    if data then
        ensure_data_indices(data)
        if instData and instData.wings then
            for _, wing in ipairs(instData.wings) do
                if wx >= (wing.minX - viewRadius) and wx <= (wing.maxX + viewRadius)
                    and wy >= (wing.minY - viewRadius) and wy <= (wing.maxY + viewRadius) then
                    place_grid(data.texBase, wing.tiles, wing.gridMaxX, wing.gridMaxY,
                        wing.cols or 1, wing.rows or 1, wing.stepYards or 96, 64)
                end
            end
        else
            local city = (bestMapID and data.cities and data.cities[bestMapID])
                or (bestMapID == 1458 and data.undercity) or nil
            if city and city.tiles then
                place_grid(data.texBase, city.tiles, city.maxX, city.maxY,
                    city.cols or 6, city.rows or 6, city.stepYards or 128, 16)
            else
                local cave = bestMapID and data._cavesByMapID and data._cavesByMapID[bestMapID]
                if not cave then
                    local rawIndoors = IsIndoors and IsIndoors()
                    local indoors = (not is_secret(rawIndoors)) and rawIndoors or false
                    local bucket = indoors and cont ~= nil and data._unmappedCavesByCont
                        and data._unmappedCavesByCont[cont]
                    if bucket then
                        for _, c in ipairs(bucket) do
                            if wx >= c.minX and wx <= c.maxX and wy >= c.minY and wy <= c.maxY then
                                cave = c
                                break
                            end
                        end
                    end
                end
                if cave then
                    if cave.tiles then
                        place_grid(data.texBase, cave.tiles, cave.gridMaxX, cave.gridMaxY,
                            cave.cols or 2, cave.rows or 2, cave.stepYards or 256, 16)
                    elseif cave.tex then
                        local cx = (cave.texMinX + cave.texMaxX) * 0.5
                        local cy = (cave.texMinY + cave.texMaxY) * 0.5
                        local side = cave.texMaxX - cave.texMinX
                        place_tile(data.texBase, cave.tex, cx, cy, side)
                    end
                else
                    local contTiles = (data.continents and cont ~= nil and data.continents[cont])
                        or (cont == 0 and data.outdoor) or nil
                    if contTiles then
                        local tileYds = data.tileYards or (1600 / 3)
                        local ptx = math_floor(32 - wy / tileYds)
                        local pty = math_floor(32 - wx / tileYds)
                        local span = math_max(1, math_ceil(viewRadius / tileYds))
                        local rMaxSq = (viewRadius + tileYds * 0.78) ^ 2
                        for tx = ptx - span, ptx + span do
                            for ty = pty - span, pty + span do
                                local fname = contTiles[tx * 64 + ty]
                                if fname then
                                    local cx = (31.5 - ty) * tileYds
                                    local cy = (31.5 - tx) * tileYds
                                    local dxC, dyC = wx - cx, wy - cy
                                    if (dxC * dxC + dyC * dyC) <= rMaxSq then
                                        place_tile(data.texBase, fname, cx, cy, tileYds)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    local prevNative = lastUsingNativeGround
    local usingNativeGround = (tileIdx == 0)
    lastUsingNativeGround = usingNativeGround
    sync_ground_textures(not usingNativeGround)
    update_effective_alphas(usingNativeGround ~= prevNative)

    for i = tileIdx + 1, #tilePool do
        tilePool[i]:Hide()
        activeTiles[i] = nil
    end

    -- 2. Pins + Waypoint/Corpse Chevrons
    if viewCache.questRev ~= questRev then
        directPinsDirty = true
        lastInstPinCont = nil
    end

    local pinIdx = 0
    local showCustomPins = (mode ~= "blizzard" and mode ~= "off")
    local showInstPins = showCustomPins and (instData ~= nil) and (instData.pins ~= nil)
    local nearVestibule = showCustomPins and data and (cont == 0) and (data.vestibulePins ~= nil)
        and (bestMapID == 19 or (wx >= 2750 and wx <= 3000 and wy >= -920 and wy <= -640))

    if showInstPins then
        if lastInstPinCont ~= cont then
            rebuild_instance_pins(instData, cont)
            directPinsDirty = false
        end
        pinIdx = project_pin_list(instPinCache, pinIdx, interactive, wheelActive, pinScale, wx, wy, cosF, sinF, ppy, viewRadius, ICON_BOSS, 16)
    elseif useDirectQDB and cont ~= nil then
        if directPinsDirty or lastPinCont ~= cont then
            rebuild_direct_pins(cont)
        end
        pinIdx = project_pin_list(directPinCache, pinIdx, interactive, wheelActive, pinScale, wx, wy, cosF, sinF, ppy, viewRadius, ICON_OBJECTIVE, 14)
    end

    if nearVestibule then
        pinIdx = project_pin_list(data.vestibulePins, pinIdx, interactive, wheelActive, pinScale, wx, wy, cosF, sinF, ppy, viewRadius, ICON_PORTAL, 14)
    end

    -- Corpse and User Waypoint markers (critical navigation aids stay active even when pins mode == "blizzard")
    if mode ~= "off" then
        pinIdx = project_nav_marker(navTargets.corpse, cont, pinIdx, interactive, wheelActive, pinScale, wx, wy, cosF, sinF, ppy, halfSz, viewRadius)
        pinIdx = project_nav_marker(navTargets.waypoint, cont, pinIdx, interactive, wheelActive, pinScale, wx, wy, cosF, sinF, ppy, halfSz, viewRadius)
    end

    if pinIdx > 0 then
        pinFrame:Show()
    else
        pinFrame:Hide()
    end

    for i = pinIdx + 1, #pinPool do
        pinPool[i]:Hide()
        activePinButtons[i] = nil
    end

    record_view_snapshot(hasData, false, wx, wy, cont, bestMapID, facing, viewRadius, rotate, sz, interactive, mode, pinScale, questRev, navRev)
end

local function on_overlay_tick(elapsed)
    if not isActive or not canvasFrame then return end
    step_alphas(elapsed)
    if panelHidden and alphaState.curCanvas <= 0.005 and alphaState.curMini <= 0.005 then
        return
    end
    update_view(elapsed)
end

-- ── Transition & Lifecycle Handlers ───────────────────────────────────────────
local function handle_zone_or_portal_transition(isEnteringWorld)
    directPinsDirty = true
    hbdFilterDirty = true
    lastInstPinCont = nil
    viewCache.dirty = true
    refresh_nav_targets()
    if not isActive then
        if isEnteringWorld then
            sync_rotate_cvar(false)
        end
        return
    end
    sync_rotate_cvar(get_opt("overlay_rotate") ~= false)
    sync_blob_rings(true)
    groundSuppressed = nil
    apply_overlay_mask()
    refresh_canvas_layout()
    update_view(0)
    if lastUsingNativeGround then
        nudge_minimap_zoom()
    end
    if isEnteringWorld and C_Timer and C_Timer.After then
        C_Timer.After(0.35, function()
            if not isActive then return end
            apply_overlay_mask()
            groundSuppressed = nil
            viewCache.dirty = true
            update_view(0)
            if lastUsingNativeGround then
                nudge_minimap_zoom()
            end
        end)
    end
end

local function ensure_events_wired()
    if eventsWired or not sfui.events then return end
    eventsWired = true

    local function reg_ev(ev, fn)
        if overlay.RegisterEvent then
            overlay:RegisterEvent(ev, fn)
        elseif sfui.events.RegisterEvent then
            sfui.events.RegisterEvent(ev, fn)
        end
    end

    local function reg_msg(msg, fn)
        if overlay.RegisterMessage then
            overlay:RegisterMessage(msg, fn)
        elseif sfui.events.RegisterMessage then
            sfui.events.RegisterMessage(msg, fn)
        end
    end

    reg_ev("PLAYER_ENTERING_WORLD", function()
        handle_zone_or_portal_transition(true)
    end)
    reg_ev("PLAYER_LOGOUT", function()
        if isActive then
            sync_rotate_cvar(false)
        end
    end)
    reg_ev("PLAYER_REGEN_ENABLED", function()
        if pendingCombatSync then
            apply_minimap_state()
        elseif pendingMouseSync then
            apply_pin_mouse_state()
        end
    end)
    reg_ev("MODIFIER_STATE_CHANGED", function()
        if isActive then
            apply_pin_mouse_state()
            viewCache.dirty = true
        end
    end)
    reg_ev("ZONE_CHANGED_NEW_AREA", function()
        handle_zone_or_portal_transition(false)
    end)
    reg_ev("ZONE_CHANGED_INDOORS", function()
        directPinsDirty = true
        viewCache.dirty = true
        if isActive then
            apply_overlay_mask()
            update_view(0)
            if lastUsingNativeGround then
                nudge_minimap_zoom()
            end
        end
    end)
    reg_ev("NEW_WMO_CHUNK", function()
        directPinsDirty = true
        viewCache.dirty = true
        if isActive then
            apply_overlay_mask()
            update_view(0)
            if lastUsingNativeGround then
                nudge_minimap_zoom()
            end
        end
    end)
    reg_ev("MINIMAP_UPDATE_ZOOM", function()
        if isActive and not nudgingZoom then
            viewCache.dirty = true
            update_view(0)
        end
    end)
    reg_ev("USER_WAYPOINT_UPDATED", function()
        refresh_nav_targets()
        if isActive then update_view(0) end
    end)
    reg_ev("SUPER_TRACKING_CHANGED", function()
        refresh_nav_targets()
        if isActive then update_view(0) end
    end)
    reg_ev("PLAYER_DEAD", function()
        refresh_nav_targets()
        if isActive then update_view(0) end
    end)
    reg_ev("PLAYER_ALIVE", function()
        refresh_nav_targets()
        if isActive then update_view(0) end
    end)
    reg_ev("PLAYER_UNGHOST", function()
        refresh_nav_targets()
        if isActive then update_view(0) end
    end)
    reg_ev("ADDON_LOADED", function(_, arg1)
        hook_ui_panels()
        if arg1 == "Blizzard_HybridMinimap" and isActive then
            suppress_blizzard_surround(true)
            groundSuppressed = nil
            viewCache.dirty = true
            update_view(0)
        end
    end)

    reg_msg("SFUI_STATE_CHANGED", function(_, changed)
        if not changed then return end
        if changed.isDeadOrGhost or changed.inInstance then
            refresh_nav_targets()
        end
        if isActive and changed.inCombat then
            update_effective_alphas(false)
            sync_compass()
        end
    end)
    reg_msg("SFUI_QUEST_STATE_UPDATED", function()
        directPinsDirty = true
        hbdFilterDirty = true
        viewCache.dirty = true
    end)

    -- Fallback quest listeners only if sfui.queststate isn't present in a standalone harness
    if not sfui.queststate then
        local function mark_q_dirty()
            directPinsDirty = true
            hbdFilterDirty = true
            viewCache.dirty = true
        end
        reg_ev("QUEST_LOG_UPDATE", mark_q_dirty)
        reg_ev("QUEST_ACCEPTED", mark_q_dirty)
        reg_ev("QUEST_TURNED_IN", mark_q_dirty)
        reg_ev("QUEST_REMOVED", mark_q_dirty)
    end
end

-- ── Public API & Module Lifecycle ─────────────────────────────────────────────
function overlay:IsActive()
    return isActive
end

function overlay:IsPanelHidden()
    return panelHidden
end

function overlay:IsInCombat()
    return in_combat_now()
end

function overlay:SetActive(state)
    ensure_db()
    local nextState = state and true or false
    if isActive == nextState then return end

    if nextState then
        ensure_events_wired()
        ensure_map_pack_loaded()
    end

    isActive = nextState
    directPinsDirty = true
    lastInstPinCont = nil
    viewCache.dirty = true
    refresh_nav_targets()
    apply_minimap_state()

    if isActive then
        if sfui.events and sfui.events.RegisterUpdate then
            sfui.events.RegisterUpdate("MapOverlay", 0.016, on_overlay_tick)
        end
        update_view(0)
        update_effective_alphas(true)
    else
        if sfui.events and sfui.events.UnregisterUpdate then
            sfui.events.UnregisterUpdate("MapOverlay")
        end
    end
    sync_compass()
end

function overlay:Toggle()
    self:SetActive(not isActive)
end

function overlay:RefreshLayout()
    viewCache.dirty = true
    if isActive then
        hook_minimap_cluster()
        sync_rotate_cvar(get_opt("overlay_rotate") ~= false)
        panelHidden = has_blocking_panel_open()
        apply_overlay_mask()
        refresh_canvas_layout()
        apply_pin_mouse_state()
        update_view(0)
        update_effective_alphas(true)
    end
    sync_compass()
end

function overlay:OnInit()
    ensure_db()
    ensure_holder()
end

function overlay:OnEnable()
    ensure_db()
    ensure_holder()
    register_mover()
    hook_ui_panels()
    ensure_events_wired()
    refresh_nav_targets()
end

function overlay:OnDisable()
    if isActive then
        self:SetActive(false)
    elseif sfui.events and sfui.events.UnregisterUpdate then
        sfui.events.UnregisterUpdate("MapOverlay")
    end
    sync_compass()
    eventsWired = false
end

function overlay:OnSettingsChanged(key)
    if type(key) ~= "string" then return end
    if key:sub(1, 8) == "overlay_" then
        viewCache.dirty = true
        self:RefreshLayout()
    end
end

function overlay:GetDebugInfo()
    local modeStr = (not isActive) and "off"
        or (lastUsingNativeGround and "native-minimap" or "custom-tiles")
    _debugInfo.enabled      = isActive
    _debugInfo.active       = isActive
    _debugInfo.mode         = modeStr
    _debugInfo.packLoaded   = get_map_data() ~= nil
    _debugInfo.packReason   = mapPackLoadReason
    _debugInfo.combatDimmed = isActive and in_combat_now()
    _debugInfo.panelHidden  = isActive and panelHidden
    _debugInfo.activeTiles  = #activeTiles
    _debugInfo.pooledTiles  = #tilePool
    _debugInfo.activePins   = #activePinButtons
    _debugInfo.pooledPins   = #pinPool
    _debugInfo.idleSkips    = viewCache.idleSkips
    _debugInfo.draws        = viewCache.draws
    _debugInfo.hasWaypoint  = navTargets.waypoint ~= nil
    _debugInfo.hasCorpse    = navTargets.corpse ~= nil
    return _debugInfo
end

sfui.overlay_debug_info = function()
    return overlay:GetDebugInfo()
end

function overlay:HandleSlash(msg)
    ensure_db()
    local clean = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if clean == "" or clean == "toggle" then
        self:Toggle()
        return
    end
    local sub, val = clean:match("^(%S+)%s*(.*)$")
    if sub == "rotate" and _G.SfuiDB then
        if val == "" or val == "toggle" then
            _G.SfuiDB.overlay_rotate = (_G.SfuiDB.overlay_rotate == false)
        elseif val == "on" or val == "1" or val == "true" then
            _G.SfuiDB.overlay_rotate = true
        elseif val == "off" or val == "0" or val == "false" then
            _G.SfuiDB.overlay_rotate = false
        end
        self:RefreshLayout()
        if sfui.common and sfui.common.print then
            sfui.common.print("overlay rotation: " .. (_G.SfuiDB.overlay_rotate ~= false and "on" or "off"))
        end
    elseif sub == "panels" and _G.SfuiDB then
        if val == "" or val == "toggle" then
            _G.SfuiDB.overlay_hide_on_panels = (_G.SfuiDB.overlay_hide_on_panels == false)
        elseif val == "on" or val == "1" or val == "true" then
            _G.SfuiDB.overlay_hide_on_panels = true
        elseif val == "off" or val == "0" or val == "false" then
            _G.SfuiDB.overlay_hide_on_panels = false
        end
        refresh_panel_visibility()
        if sfui.common and sfui.common.print then
            sfui.common.print("overlay hide on panels: " .. (_G.SfuiDB.overlay_hide_on_panels ~= false and "on" or "off"))
        end
    elseif sub == "compass" and _G.SfuiDB then
        if val == "" or val == "toggle" then
            _G.SfuiDB.overlay_compass = (_G.SfuiDB.overlay_compass == false)
        elseif val == "on" or val == "1" or val == "true" then
            _G.SfuiDB.overlay_compass = true
        elseif val == "off" or val == "0" or val == "false" then
            _G.SfuiDB.overlay_compass = false
        end
        sync_compass()
        if sfui.common and sfui.common.print then
            sfui.common.print("overlay compass: " .. (_G.SfuiDB.overlay_compass ~= false and "on" or "off"))
        end
    elseif sub == "resetpos" then
        if _G.SfuiDB then
            _G.SfuiDB.overlay_x = 0
            _G.SfuiDB.overlay_y = 0
            _G.SfuiDB.overlay_compass_pos = nil
            _G.SfuiDB.overlay_compass_x = nil
            _G.SfuiDB.overlay_compass_y = nil
        end
        apply_holder_position()
        if sfui.map and sfui.map.compass and sfui.map.compass.UpdatePosition then
            sfui.map.compass:UpdatePosition()
        end
        self:RefreshLayout()
    elseif sub == "size" then
        local n = tonumber(val)
        if n and n >= 240 and n <= 1000 and _G.SfuiDB then
            _G.SfuiDB.overlay_size = n
            self:RefreshLayout()
        end
    elseif sub == "alpha" then
        local n = tonumber(val)
        if n and n >= 0.1 and n <= 1.0 and _G.SfuiDB then
            _G.SfuiDB.overlay_alpha = n
            self:RefreshLayout()
        end
    elseif sub == "combatalpha" then
        local n = tonumber(val)
        if n and n >= 0.05 and n <= 1.0 and _G.SfuiDB then
            _G.SfuiDB.overlay_combat_alpha = n
            self:RefreshLayout()
        end
    elseif sub == "instalpha" then
        local n = tonumber(val)
        if n and n >= 0.1 and n <= 1.0 and _G.SfuiDB then
            _G.SfuiDB.overlay_instance_alpha = n
            self:RefreshLayout()
        end
    elseif sub == "zoom" then
        local n = tonumber(val)
        if n and n >= 0 and n <= 5 and _G.SfuiDB then
            _G.SfuiDB.overlay_zoom = math_floor(n)
            if isActive and Minimap and Minimap.SetZoom then
                Minimap:SetZoom(_G.SfuiDB.overlay_zoom)
            end
            self:RefreshLayout()
        end
    elseif sub == "pins" and (val == "auto" or val == "questiedb" or val == "blizzard" or val == "off") and _G.SfuiDB then
        _G.SfuiDB.overlay_pins_mode = val
        directPinsDirty = true
        hbdFilterDirty = true
        self:RefreshLayout()
    elseif sub == "diag" then
        local ux, uy = UnitPosition and UnitPosition("player")
        local coordState
        if is_secret(ux) or is_secret(uy) then
            coordState = "secret"
        elseif ux ~= nil and uy ~= nil then
            coordState = "ok"
        else
            coordState = "nil"
        end

        local inInstRaw = IsInInstance and IsInInstance()
        local inInstStr = is_secret(inInstRaw) and "secret" or tostring(inInstRaw and true or false)

        local rawInstID = nil
        if GetInstanceInfo then
            local _, _, _, _, _, _, _, iid = GetInstanceInfo()
            rawInstID = iid
        end
        local instStr = is_secret(rawInstID) and "secret" or tostring(rawInstID)

        local bMap = _G.C_Map and _G.C_Map.GetBestMapForUnit and _G.C_Map.GetBestMapForUnit("player")
        local mapStr = is_secret(bMap) and "secret" or tostring(bMap)

        local drawG = _G.C_Minimap and _G.C_Minimap.GetDrawGroundTextures and _G.C_Minimap.GetDrawGroundTextures()
        local gStr = is_secret(drawG) and "secret" or tostring(drawG)

        local mAlpha = (Minimap and Minimap.GetAlpha and Minimap:GetAlpha()) or 1
        local aStr = is_secret(mAlpha) and "secret" or (type(mAlpha) == "number" and string_format("%.2f", mAlpha) or tostring(mAlpha))

        local curZ = Minimap and Minimap.GetZoom and Minimap:GetZoom()
        local zStr = is_secret(curZ) and "secret" or tostring(curZ)

        local info = self:GetDebugInfo()
        local modeStr = (not isActive) and "off"
            or (lastUsingNativeGround and "native-minimap" or ("custom-tiles(" .. tostring(info.activeTiles) .. ")"))

        if sfui.common and sfui.common.print then
            sfui.common.print(
                "overlay diag: mode=" .. modeStr
                .. " pack=" .. (info.packLoaded and "loaded" or tostring(info.packReason or "missing"))
                .. " in_inst=" .. inInstStr
                .. " inst_id=" .. instStr
                .. " uimap=" .. mapStr
                .. " coords=" .. coordState
                .. " ground=" .. gStr
                .. " mm_alpha=" .. aStr
                .. " zoom=" .. zStr
                .. " combat_dim=" .. (info.combatDimmed and "yes" or "no")
                .. " panel_hidden=" .. (info.panelHidden and "yes" or "no")
                .. " skips=" .. tostring(info.idleSkips)
                .. " draws=" .. tostring(info.draws)
                .. " wp=" .. (info.hasWaypoint and "yes" or "no")
                .. " corpse=" .. (info.hasCorpse and "yes" or "no")
            )
        end
    elseif sfui.common and sfui.common.print then
        sfui.common.print("overlay: /sfoverlay [toggle | compass <on|off> | rotate <on|off> | panels <on|off> | size <240-1000> | alpha <0.1-1.0> | combatalpha <0.05-1.0> | instalpha <0.1-1.0> | zoom <0-5> | pins <auto|questiedb|blizzard|off> | resetpos | diag]")
    end
end

if sfui.RegisterModule and sfui.GetModule then
    sfui.RegisterModule("overlay", overlay)
else
    if sfui.RegisterModule then
        sfui.RegisterModule("overlay", overlay)
    end
    overlay:OnInit()
    overlay:OnEnable()
end
