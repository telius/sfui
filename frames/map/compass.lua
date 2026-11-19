local _, _ = ...
sfui = sfui or {}
sfui.map = sfui.map or {}
sfui.map.compass = sfui.map.compass or {}

if sfui.isRetail then return end

local compass          = sfui.map.compass

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/map/compass.lua
--  Minimalist, Theme-Aware Compass for the ARPG Minimap Overlay
--
--  Renders an ultra-minimal horizontal heading ribbon docked 2px above the
--  experience bar by default while the overlay is active (with opt-out toggle
--  in minimap options and `/sfoverlay compass <on|off>`). Syncs automatically
--  with `sfui.theme`, auto-hides alongside UI panels, dims subtly in combat,
--  supports `/sfui` movers, and allocates zero frames/tables on update ticks.
-- ══════════════════════════════════════════════════════════════════════════════

local _G               = _G
local CreateFrame      = _G.CreateFrame
local UIParent         = _G.UIParent
local InCombatLockdown = _G.InCombatLockdown
local GetPlayerFacing  = _G.GetPlayerFacing
local hooksecurefunc   = _G.hooksecurefunc
local setmetatable     = setmetatable

local math_abs         = math.abs
local math_floor       = math.floor
local math_pi          = math.pi
local type             = type

local is_secret        = (sfui.safety and sfui.safety.issecretvalue)
    or _G.issecretvalue
    or function() return false end

local DEFAULTS         = {
    overlay_compass = true,
}

local WIDTH            = 200
local HEIGHT           = 18
local STRIP_WIDTH      = 200
local HALF_FOV_DEG     = 60
local PX_PER_DEG       = (STRIP_WIDTH * 0.5) / HALF_FOV_DEG
local TWO_PI           = math_pi * 2
local RAD_TO_DEG       = 180 / math_pi

local CARDINAL_LABELS  = {
    [0]   = "n",
    [90]  = "e",
    [180] = "s",
    [270] = "w",
}

local rootFrame        = nil
local baselineTex      = nil
local caretTex         = nil
local stripFrame       = nil
local marks            = {}

local eventsWired      = false
local moverRegistered  = false
local tickRegistered   = false
local inEditMode       = false
local themeApplied     = false
local lastFacing       = nil
local appliedAlpha     = nil
local expLayoutHooked  = false
local hookedExpFrames  = setmetatable({}, { __mode = "k" })

local function round_num(val, dec)
    if sfui.common and sfui.common.round then
        return sfui.common.round(val, dec)
    end
    local mult = 10 ^ (dec or 0)
    return math_floor(val * mult + 0.5) / mult
end

local function ensure_db()
    if not _G.SfuiDB then return DEFAULTS end
    for k, v in pairs(DEFAULTS) do
        if _G.SfuiDB[k] == nil then
            _G.SfuiDB[k] = v
        end
    end
    if _G.SfuiDB.overlay_compass_pos == nil
        and _G.SfuiDB.overlay_compass_x == 0
        and _G.SfuiDB.overlay_compass_y == -18 then
        _G.SfuiDB.overlay_compass_x = nil
        _G.SfuiDB.overlay_compass_y = nil
    end
    return _G.SfuiDB
end

local function get_opt(key)
    if _G.SfuiDB and _G.SfuiDB[key] ~= nil then
        return _G.SfuiDB[key]
    end
    return DEFAULTS[key]
end

local function is_bar_visible(f)
    if not f or not f.IsShown then return false end
    local shown = f:IsShown()
    if is_secret(shown) or not shown then return false end
    if f.GetAlpha then
        local a = f:GetAlpha()
        if is_secret(a) or (type(a) == "number" and a <= 0) then
            return false
        end
    end
    return true
end

local function hook_xp_frame(f)
    if not f or hookedExpFrames[f] or not f.HookScript then return end
    hookedExpFrames[f] = true
    local function on_xp_vis_change()
        if rootFrame and not (_G.SfuiDB and _G.SfuiDB.overlay_compass_pos) then
            compass:UpdatePosition()
        end
    end
    f:HookScript("OnShow", on_xp_vis_change)
    f:HookScript("OnHide", on_xp_vis_change)
end

local function resolve_xp_stack_anchor()
    local expMod  = sfui.experience
    local petBar  = expMod and expMod.pet and expMod.pet.GetFrame and expMod.pet.GetFrame()
    local chalBar = expMod and expMod.challenges and expMod.challenges.GetFrame and expMod.challenges.GetFrame()
    local repBar  = expMod and expMod.reputation and expMod.reputation.GetFrame and expMod.reputation.GetFrame()
    local expBar  = (expMod and expMod.bar and expMod.bar.GetFrame and expMod.bar.GetFrame()) or _G.SfuiExperienceBar

    hook_xp_frame(petBar)
    hook_xp_frame(chalBar)
    hook_xp_frame(repBar)
    hook_xp_frame(expBar)

    if not expLayoutHooked and hooksecurefunc and expMod and expMod.bar and expMod.bar.UpdateLayout then
        expLayoutHooked = true
        hooksecurefunc(expMod.bar, "UpdateLayout", function()
            if rootFrame and not (_G.SfuiDB and _G.SfuiDB.overlay_compass_pos) then
                compass:UpdatePosition()
            end
        end)
    end

    local cfg = (sfui.config and sfui.config.experience) or {}
    local repOnTop = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "repOnTop", cfg.repOnTop ~= false))
    if repOnTop == nil then repOnTop = true end

    if is_bar_visible(petBar) then return petBar end
    if is_bar_visible(chalBar) then return chalBar end
    if is_bar_visible(repBar) and (not is_bar_visible(expBar) or repOnTop) then return repBar end
    if is_bar_visible(expBar) then return expBar end
    return expBar or repBar
end

local function resolve_fallback_uiparent_point()
    local cfg = (sfui.config and sfui.config.experience) or {}
    local pos = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "pos", cfg.pos)) or cfg.pos or
        { point = "BOTTOM", x = 0, y = 4 }
    local h = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "height", cfg.height or 8)) or 8
    local pt = pos.point or "BOTTOM"
    local relPt = pos.relativePoint or pt
    return pt, UIParent, relPt, pos.x or 0, (pos.y or 4) + h + 2
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

local function resolve_theme_tokens()
    local themeMod = sfui.theme
    local activeID = (themeMod and themeMod.GetActiveThemeID and themeMod.GetActiveThemeID()) or "modern"
    local pal = (themeMod and themeMod.GetPalette and themeMod.GetPalette())
        or (sfui.config and sfui.config.appearance)
        or {}

    local accent = pal.accentColor or { 0, 1, 1, 1 }
    local highlight = pal.highlightColor or { 0.4, 0, 1, 1 }
    local header = pal.headerColor or { 1, 1, 1, 1 }
    local inter = pal.tabNormal or pal.dimTextColor or { 0.72, 0.72, 0.72, 1 }
    local dim = pal.dimTextColor or { 0.6, 0.6, 0.6, 1 }

    local lineCol = highlight
    local lineAlpha = 0.25
    if activeID == "camelot" or activeID == "bronze" then
        lineCol = pal.metalBottomColor or highlight
        lineAlpha = 0.30
    elseif pal.borderColor then
        local br, bgC, bb, ba = pal.borderColor[1] or 0, pal.borderColor[2] or 0, pal.borderColor[3] or 0,
            pal.borderColor[4] or 0
        if ba > 0.05 and (br + bgC + bb) > 0.05 then
            lineCol = pal.borderColor
            lineAlpha = 0.30
        end
    end

    return accent, header, inter, dim, lineCol, lineAlpha
end

local function ensure_frames()
    if rootFrame then return end

    rootFrame = CreateFrame("Frame", "sfui_MapOverlayCompass", UIParent)
    rootFrame:SetSize(WIDTH, HEIGHT)
    rootFrame:SetFrameStrata("LOW")
    rootFrame:SetFrameLevel(20)
    rootFrame:EnableMouse(false)
    rootFrame:Hide()

    baselineTex = rootFrame:CreateTexture(nil, "BORDER", nil, 0)
    baselineTex:SetSize(STRIP_WIDTH, 1)
    baselineTex:SetPoint("BOTTOM", rootFrame, "BOTTOM", 0, 4)
    baselineTex:SetColorTexture(0.5, 0.5, 0.5, 0.25)

    caretTex = rootFrame:CreateTexture(nil, "OVERLAY", nil, 2)
    caretTex:SetSize(2, 4)
    caretTex:SetPoint("TOP", baselineTex, "BOTTOM", 0, -1)
    caretTex:SetColorTexture(0, 1, 1, 1)

    stripFrame = CreateFrame("Frame", nil, rootFrame)
    stripFrame:SetSize(STRIP_WIDTH, HEIGHT)
    stripFrame:SetPoint("CENTER", rootFrame, "CENTER", 0, 0)
    stripFrame:SetClipsChildren(true)
    stripFrame:EnableMouse(false)

    local fontPath = (sfui.config and sfui.config.fontFile) or "Fonts\\FRIZQT__.TTF"
    for idx = 0, 15 do
        local deg = idx * 22.5
        local label = CARDINAL_LABELS[deg]
        local kind
        local tickW, tickH, fontSize
        if deg == 0 then
            kind = "north"
            fontSize = 11
        elseif label then
            kind = "cardinal"
            fontSize = 10
        elseif idx % 2 == 0 then
            kind = "inter"
            tickW, tickH = 1, 4
        else
            kind = "minor"
            tickW, tickH = 1, 2
        end

        local holder = CreateFrame("Frame", nil, stripFrame)
        holder:SetSize(20, HEIGHT)
        holder:EnableMouse(false)
        holder:Hide()

        local tick = nil
        local textFS = nil
        if label then
            textFS = holder:CreateFontString(nil, "OVERLAY")
            if textFS.SetFont then
                textFS:SetFont(fontPath, fontSize, "")
            end
            if textFS.SetShadowOffset then
                textFS:SetShadowOffset(0, 0)
            end
            if textFS.SetShadowColor then
                textFS:SetShadowColor(0, 0, 0, 0)
            end
            if textFS.SetJustifyH then textFS:SetJustifyH("CENTER") end
            if textFS.SetJustifyV then textFS:SetJustifyV("BOTTOM") end
            textFS:SetPoint("BOTTOM", holder, "BOTTOM", 0, 6)
            textFS:SetText(label)
        else
            tick = holder:CreateTexture(nil, "ARTWORK", nil, 0)
            tick:SetSize(tickW, tickH)
            tick:SetPoint("BOTTOM", holder, "BOTTOM", 0, 5)
            tick:SetColorTexture(1, 1, 1, 0.5)
        end

        marks[idx + 1] = {
            deg    = deg,
            kind   = kind,
            holder = holder,
            tick   = tick,
            text   = textFS,
            shown  = false,
        }
    end

    compass:UpdatePosition()
end

function compass:ApplyTheme()
    ensure_frames()
    themeApplied = true

    local accent, header, inter, dim, lineCol, lineAlpha = resolve_theme_tokens()

    baselineTex:SetColorTexture(lineCol[1] or 0.5, lineCol[2] or 0.5, lineCol[3] or 0.5, lineAlpha)
    caretTex:SetColorTexture(accent[1] or 0, accent[2] or 1, accent[3] or 1, 1)

    for i = 1, #marks do
        local m = marks[i]
        if m.kind == "north" then
            if m.text then
                m.text:SetTextColor(accent[1] or 0, accent[2] or 1, accent[3] or 1, 1)
            end
        elseif m.kind == "cardinal" then
            if m.text then
                m.text:SetTextColor(header[1] or 1, header[2] or 1, header[3] or 1, 0.92)
            end
        elseif m.kind == "inter" then
            if m.tick then
                m.tick:SetColorTexture(inter[1] or 0.72, inter[2] or 0.72, inter[3] or 0.72, 0.60)
            end
        else
            if m.tick then
                m.tick:SetColorTexture(dim[1] or 0.6, dim[2] or 0.6, dim[3] or 0.6, 0.35)
            end
        end
    end
end

function compass:UpdatePosition()
    if not rootFrame or not can_modify_region(rootFrame) then return end
    rootFrame:ClearAllPoints()
    local customPos = _G.SfuiDB and _G.SfuiDB.overlay_compass_pos
    if type(customPos) == "table" then
        local pt = customPos.point or "BOTTOM"
        rootFrame:SetPoint(pt, UIParent, customPos.relativePoint or pt, customPos.x or 0, customPos.y or 14)
    else
        local anchor = resolve_xp_stack_anchor()
        if anchor then
            rootFrame:SetPoint("BOTTOM", anchor, "TOP", 0, 2)
        else
            rootFrame:SetPoint(resolve_fallback_uiparent_point())
        end
    end
end

local function update_compass(force)
    if not stripFrame then return end
    local f = GetPlayerFacing and GetPlayerFacing()
    if f == nil or is_secret(f) or type(f) ~= "number" then
        return
    end
    if not force and lastFacing ~= nil and math_abs(f - lastFacing) < 0.0008 then
        return
    end
    lastFacing = f

    local headingDeg = ((TWO_PI - (f % TWO_PI)) * RAD_TO_DEG) % 360
    for i = 1, #marks do
        local m = marks[i]
        local delta = ((m.deg - headingDeg + 540) % 360) - 180
        local absDelta = math_abs(delta)
        if absDelta > HALF_FOV_DEG then
            if m.shown then
                m.holder:Hide()
                m.shown = false
            end
        else
            local x = delta * PX_PER_DEG
            local norm = absDelta / HALF_FOV_DEG
            local edgeAlpha = 1 - (norm * norm * 0.88)
            local becameShown = false
            if not m.shown then
                m.holder:Show()
                m.shown = true
                becameShown = true
            end
            if becameShown or m._lastX == nil or math_abs(x - m._lastX) > 0.02 then
                m._lastX = x
                m.holder:SetPoint("CENTER", stripFrame, "CENTER", x, 0)
            end
            if becameShown or m._lastAlpha == nil or math_abs(edgeAlpha - m._lastAlpha) > 0.005 then
                m._lastAlpha = edgeAlpha
                m.holder:SetAlpha(edgeAlpha)
            end
        end
    end
end

local function on_compass_tick()
    update_compass(false)
end

local function sync_ticker(active)
    if active == tickRegistered then return end
    tickRegistered = active
    if active then
        if sfui.events and sfui.events.RegisterUpdate then
            sfui.events.RegisterUpdate("MapOverlayCompass", 0.016, on_compass_tick)
        end
    else
        if sfui.events and sfui.events.UnregisterUpdate then
            sfui.events.UnregisterUpdate("MapOverlayCompass")
        end
    end
end

local function ensure_events_wired()
    if eventsWired then return end
    eventsWired = true
    if sfui.events and sfui.events.RegisterMessage then
        sfui.events.RegisterMessage("SFUI_THEME_CHANGED", function()
            if rootFrame then
                compass:ApplyTheme()
            end
        end)
    end
end

local function register_mover()
    if moverRegistered or not (sfui.movers and sfui.movers.Register) then return end
    ensure_frames()
    moverRegistered = true
    sfui.movers.Register(rootFrame, {
        key = "overlay_compass",
        label = "overlay compass",
        preferredPoint = "BOTTOM",
        customSize = function()
            return WIDTH, HEIGHT
        end,
        getPoint = function()
            local customPos = _G.SfuiDB and _G.SfuiDB.overlay_compass_pos
            if type(customPos) == "table" then
                local pt = customPos.point or "BOTTOM"
                return pt, UIParent, customPos.relativePoint or pt, customPos.x or 0, customPos.y or 14
            end
            local anchor = resolve_xp_stack_anchor()
            if anchor and anchor.GetCenter and anchor.GetTop and UIParent and UIParent.GetCenter and UIParent.GetBottom then
                local ax = anchor:GetCenter()
                local aTop = anchor:GetTop()
                local ux = UIParent:GetCenter()
                local uBot = UIParent:GetBottom()
                if not is_secret(ax) and not is_secret(aTop) and not is_secret(ux) and not is_secret(uBot)
                    and type(ax) == "number" and type(aTop) == "number"
                    and type(ux) == "number" and type(uBot) == "number" then
                    return "BOTTOM", UIParent, "BOTTOM", round_num(ax - ux, 0), round_num(aTop - uBot + 2, 0)
                end
            end
            return resolve_fallback_uiparent_point()
        end,
        setPoint = function(point, _, relPoint, x, y)
            if _G.SfuiDB then
                local pt = point or "BOTTOM"
                _G.SfuiDB.overlay_compass_pos = {
                    point         = pt,
                    relativePoint = relPoint or pt,
                    x             = round_num(x or 0, 0),
                    y             = round_num(y ~= nil and y or 14, 0),
                }
            end
            compass:UpdatePosition()
        end,
        resetPosition = function()
            if _G.SfuiDB then
                _G.SfuiDB.overlay_compass_pos = nil
                _G.SfuiDB.overlay_compass_x = nil
                _G.SfuiDB.overlay_compass_y = nil
            end
            compass:UpdatePosition()
        end,
        isEnabled = function()
            return get_opt("overlay_compass") ~= false
        end,
        onEnterEditMode = function()
            inEditMode = true
            compass:SyncState()
        end,
        onExitEditMode = function()
            inEditMode = false
            compass:SyncState()
        end,
    })
end

function compass:SyncState()
    ensure_db()
    ensure_events_wired()

    local enabledOpt = get_opt("overlay_compass") ~= false
    local moverUnlocked = inEditMode or ((sfui.movers and sfui.movers.isUnlocked) == true)
    local ov = sfui.map and sfui.map.overlay
    local ovActive = (ov and ov.IsActive and ov:IsActive() == true) or false
    local panelHidden = (ov and ov.IsPanelHidden and ov:IsPanelHidden() == true) or false

    local wantShown = enabledOpt and (moverUnlocked or (ovActive and not panelHidden))
    if wantShown then
        ensure_frames()
        if not themeApplied then
            self:ApplyTheme()
        end
        self:UpdatePosition()

        local inCombat = (not moverUnlocked) and (ov and ov.IsInCombat and ov:IsInCombat() == true) or false
        local targetAlpha = inCombat and 0.60 or 0.95
        if appliedAlpha ~= targetAlpha then
            appliedAlpha = targetAlpha
            rootFrame:SetAlpha(targetAlpha)
        end

        rootFrame:Show()
        update_compass(true)
        sync_ticker(true)
    else
        sync_ticker(false)
        lastFacing = nil
        if rootFrame then
            rootFrame:Hide()
        end
    end
end

function compass:IsShown()
    return rootFrame ~= nil and rootFrame:IsShown() == true
end

function compass:OnInit()
    ensure_db()
    ensure_frames()
end

function compass:OnEnable()
    ensure_db()
    ensure_frames()
    self:ApplyTheme()
    register_mover()
    ensure_events_wired()
    self:SyncState()
end

function compass:OnDisable()
    inEditMode = false
    sync_ticker(false)
    lastFacing = nil
    if rootFrame then
        rootFrame:Hide()
    end
end

function compass:OnSettingsChanged(key)
    if type(key) ~= "string" then return end
    if key == "overlay_compass" or key == "overlay_compass_pos" then
        self:UpdatePosition()
        self:SyncState()
    end
end

if sfui.RegisterModule and sfui.GetModule then
    sfui.RegisterModule("overlay_compass", compass)
else
    if sfui.RegisterModule then
        sfui.RegisterModule("overlay_compass", compass)
    end
    compass:OnInit()
    compass:OnEnable()
end
