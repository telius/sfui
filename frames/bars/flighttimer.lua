local addonName, addon = ...
sfui = sfui or {}
sfui.flighttimer = sfui.flighttimer or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/bars/flighttimer.lua
--  Self-Calibrating Flight Timer Bar (Camelot / Classic)
--
--  * Measures route lengths from sfui.flight_routes (yards per hop) and learns
--    actual flight speed via weighted updates after each normal landing.
--  * Respects Forever's "Frequent Flier" Adventure Legacy perk (+20% speed).
--  * Renders intermediate stops scrolling smoothly across a center "you" marker.
--  * Includes a one-click early landing button (TaxiRequestEarlyLanding) that
--    dynamically retargets the ETA and bar to the next flight point.
-- ══════════════════════════════════════════════════════════════════════════════

if sfui.isRetail then return end

local _G                      = _G
local CreateFrame             = _G.CreateFrame
local UIParent                = _G.UIParent
local GetTime                 = _G.GetTime
local GetNumRoutes            = _G.GetNumRoutes
local TaxiGetNodeSlot         = _G.TaxiGetNodeSlot
local TaxiNodeName            = _G.TaxiNodeName
local GetTaxiMapID            = _G.GetTaxiMapID
local TaxiRequestEarlyLanding = _G.TaxiRequestEarlyLanding
local UnitOnTaxi              = _G.UnitOnTaxi
local UnitFactionGroup        = _G.UnitFactionGroup
local C_TaxiMap               = _G.C_TaxiMap
local C_Traits                = _G.C_Traits
local C_DurationUtil          = _G.C_DurationUtil
local C_Timer                 = _G.C_Timer
local Enum                    = _G.Enum
local hooksecurefunc          = _G.hooksecurefunc
local ipairs                  = _G.ipairs
local math_floor              = _G.math.floor
local math_max                = _G.math.max
local math_min                = _G.math.min
local string_format           = _G.string.format
local string_lower            = _G.string.lower

local DEFAULT_SPEED    = 30.4
local PREVIEW_SECONDS  = 20
local PREVIEW_HOLD     = 2
local LOOKAHEAD        = 60
local SLIDE_STEP       = 1.25
local PIN_SIZE         = 13
local EXIT_SIZE        = 22
local WHITE            = "Interface\\Buttons\\WHITE8x8"
local STOP_ICON        = "Interface\\Minimap\\Tracking\\FlightMaster"
local EXIT_ICON        = "Interface\\Icons\\Spell_Magic_FeatherFall"

local PREVIEW_ROUTES = {
    Horde    = { 80, "ratchet", 25, "crossroads", 30, "freewind post", 40, "gadgetzan" },
    Alliance = { 6, "ironforge", 74, "thorium point", 71, "morgan's vigil", 5, "lakeshire" },
}

local bar, events, ticker
local hooked = false
local pending = nil
local flight = nil
local previewActive = false
local previewHoldUntil = 0

local function Cfg()
    return (sfui.config and sfui.config.flighttimer) or {}
end

local function IsEnabled()
    return _G.SfuiDB == nil or _G.SfuiDB.enableFlightTimer ~= false
end

local function GetSpeed()
    if _G.SfuiDB and _G.SfuiDB.flightTimerSpeed and _G.SfuiDB.flightTimerSpeed > 5 then
        return _G.SfuiDB.flightTimerSpeed
    end
    return Cfg().defaultSpeed or DEFAULT_SPEED
end

-- Frequent Flier (Adventure Legacy tree 1188, node 110300): +20% taxi speed
local function GetSpeedMultiplier()
    if C_Traits and C_Traits.GetConfigIDByTreeID and C_Traits.GetNodeInfo then
        local configID = C_Traits.GetConfigIDByTreeID(1188)
        local node = configID and C_Traits.GetNodeInfo(configID, 110300)
        if node and (node.activeRank or 0) > 0 then
            return 1.2
        end
    end
    return 1.0
end

local function FormatTime(sec)
    sec = math_max(0, math_floor(sec + 0.5))
    return string_format("%d:%02d", math_floor(sec / 60), sec % 60)
end

local function TimeLeftText(fl, elapsed)
    local left = FormatTime(fl.eta - elapsed)
    if Cfg().showTotal then
        return left .. " / " .. FormatTime(fl.eta)
    end
    return left
end

local function LowerName(raw)
    if not raw or raw == "" then return "" end
    return string_lower(raw)
end

local function RouteInfo(slot)
    local routes = sfui.flight_routes or {}
    if not (GetNumRoutes and TaxiGetNodeSlot and TaxiNodeName) then return nil end
    local hops = GetNumRoutes(slot)
    if not hops or hops < 1 then return nil end

    local mapID = GetTaxiMapID and GetTaxiMapID()
    local nodes = mapID and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and C_TaxiMap.GetAllTaxiNodes(mapID)
    local idBySlot = {}
    if nodes then
        for _, node in ipairs(nodes) do
            idBySlot[node.slotIndex] = node.nodeID
        end
    end

    local yards = 0
    local startName = TaxiNodeName(TaxiGetNodeSlot(slot, 1, true))
    local points = { { name = LowerName(startName), yards = 0 } }
    for hop = 1, hops do
        local toSlot = TaxiGetNodeSlot(slot, hop, false)
        local from = idBySlot[TaxiGetNodeSlot(slot, hop, true)]
        local to = idBySlot[toSlot]
        local hopYards = from and to and routes[from * 10000 + to]
        yards = (yards and hopYards) and (yards + hopYards) or nil
        points[#points + 1] = { name = LowerName(TaxiNodeName(toSlot)), yards = yards }
    end

    local destName = points[#points] and points[#points].name or ""
    return (yards and yards > 0) and yards or nil, points, destName
end

local function NewStopMark(parent)
    local m = {
        icon  = parent:CreateTexture(nil, "OVERLAY"),
        label = parent:CreateFontString(nil, "OVERLAY", (sfui.config and sfui.config.font_small) or "GameFontNormalSmall"),
    }
    m.icon:SetTexture(STOP_ICON)
    m.icon:SetSize(PIN_SIZE, PIN_SIZE)
    m.label:SetWordWrap(false)
    m.label:SetShadowOffset(1, -1)
    m.label:SetShadowColor(0, 0, 0, 1)
    m.label:SetTextColor(0.92, 0.92, 0.92, 1)
    return m
end

local function ApplyBarPosition()
    if not bar then return end
    local p = (_G.SfuiDB and _G.SfuiDB.flightTimerPos) or Cfg().pos or { point = "TOP", relPoint = "TOP", x = 0, y = -140 }
    bar:ClearAllPoints()
    bar:SetPoint(p.point or "TOP", UIParent, p.relPoint or p.point or "TOP", p.x or 0, p.y or -140)
end

local function ApplyThemeStyling()
    if not bar then return end
    local track = bar.track
    if sfui.widgets and sfui.widgets.get_bar_texture then
        local tex = sfui.widgets.get_bar_texture()
        if tex then track:SetStatusBarTexture(tex) end
    else
        track:SetStatusBarTexture(WHITE)
    end

    local col = (sfui.common and sfui.common.get_class_or_spec_color and sfui.common.get_class_or_spec_color())
        or { 0.4, 0.0, 1.0 }
    local alpha = (flight and not flight.eta) and 0 or 0.95
    track:SetStatusBarColor(col[1] or 0.4, col[2] or 0.0, col[3] or 1.0, alpha)

    if sfui.theme and sfui.theme.ApplyStatusBarStyle then
        sfui.theme.ApplyStatusBarStyle(track, "castbar")
    end
end

local function ScrollStrip(fl, elapsed)
    if not (bar and bar.clip and bar.clip:IsShown()) then return end
    local g = bar.clip.glide
    g:Stop()
    bar.clip.strip:ClearAllPoints()
    bar.clip.strip:SetPoint("CENTER", bar.backdrop, "CENTER", -elapsed * bar.clip.pps, 0)
    if fl.eta and elapsed < fl.eta then
        g.move:SetOffset(-SLIDE_STEP * bar.clip.pps, 0)
        g:Play()
    end
    if fl.eta and fl.yards and fl.points then
        local flown = elapsed / fl.eta * fl.yards
        for k = 1, #fl.points - 2 do
            local stop = bar.stops[k]
            local y = fl.points[k + 1] and fl.points[k + 1].yards
            if stop and y then
                local passed = (y <= flown)
                stop.icon:SetAlpha(passed and 0.4 or 1)
                stop.label:SetAlpha(passed and 0.4 or 1)
            end
        end
    end
end

local function LayoutRoute(fl)
    if not bar then return end
    local points = fl and fl.points
    local n = points and #points or 0
    local startName = (n >= 1 and points[1].name) or ""
    local destName = (fl and fl.dest) or (n >= 1 and points[n].name) or ""

    bar.startLabel:SetText(startName)
    bar.destLabel:SetText(fl and fl.early and (destName .. " (landing)") or destName)

    local showStops = Cfg().showStops ~= false
    local moving = showStops and points and fl.eta and fl.yards and not fl.early and n > 2
    bar.clip:SetShown(moving == true)
    bar.youMark:SetShown(moving == true)
    bar.youLabel:SetShown(moving == true)

    if moving then
        bar.clip.pps = bar.backdrop:GetWidth() / 2 / (fl.lookahead or LOOKAHEAD)
        for k = 1, math_max(n - 2, #bar.stops) do
            local stopYards = (k <= n - 2) and points[k + 1] and points[k + 1].yards
            local m = bar.stops[k]
            if stopYards and not m then
                m = NewStopMark(bar.clip.strip)
                bar.stops[k] = m
            end
            if m then
                if stopYards then
                    m.icon:SetAlpha(1)
                    m.icon:Show()
                    m.label:SetAlpha(1)
                    m.label:SetText(points[k + 1].name or "")
                    m.label:Show()
                    m.icon:ClearAllPoints()
                    m.icon:SetPoint("CENTER", bar.clip.strip, "CENTER", stopYards / fl.yards * fl.eta * bar.clip.pps, 0)
                    m.label:ClearAllPoints()
                    m.label:SetPoint("TOP", m.icon, "BOTTOM", 0, -2)
                else
                    m.icon:Hide()
                    m.label:Hide()
                end
            end
        end
        ScrollStrip(fl, math_max(0, math_min(GetTime() - fl.start, fl.eta)))
    end

    if bar.exitBtn then
        local showExit = (Cfg().showEarlyBtn ~= false)
        bar.exitBtn:SetShown(showExit)
        local done = fl and fl.early
        bar.exitBtn:SetEnabled(not done)
        bar.exitBtn:SetAlpha(done and 0.4 or 1)
    end
end

local function ArmTimer(fl)
    if not (bar and fl and fl.eta) then return end
    local track = bar.track
    if C_DurationUtil and C_DurationUtil.CreateDuration and track.SetTimerDuration
        and Enum and Enum.StatusBarInterpolation and Enum.StatusBarTimerDirection then
        local dur = C_DurationUtil.CreateDuration()
        dur:SetTimeFromStart(fl.start, fl.eta)
        track:SetTimerDuration(dur, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.ElapsedTime)
    else
        track:SetMinMaxValues(0, fl.eta)
        track:SetValue(math_max(0, math_min(GetTime() - fl.start, fl.eta)))
    end
end

local RequestEarlyLanding

local function EnsureBar()
    if bar then return bar end
    local w = Cfg().width or 280
    local h = Cfg().height or 12

    bar = CreateFrame("Frame", "SfuiFlightTimer", UIParent)
    bar:SetSize(w, 48)
    bar:Hide()

    local backdrop = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    backdrop:SetSize(w, h + 2)
    backdrop:SetPoint("CENTER", bar, "CENTER", 0, 4)
    backdrop:SetBackdrop({
        bgFile   = WHITE,
        edgeFile = WHITE,
        edgeSize = 1,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    backdrop:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
    backdrop:SetBackdropBorderColor(0, 0, 0, 1)
    bar.backdrop = backdrop

    local track = CreateFrame("StatusBar", nil, backdrop)
    track:SetPoint("TOPLEFT", backdrop, "TOPLEFT", 1, -1)
    track:SetPoint("BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", -1, 1)
    track:SetMinMaxValues(0, 1)
    track:SetValue(0)
    track.backdrop = backdrop
    bar.track = track

    local over = CreateFrame("Frame", nil, bar)
    over:SetAllPoints(backdrop)
    over:SetFrameLevel(backdrop:GetFrameLevel() + 4)
    bar.over = over

    local fontSmall = (sfui.config and sfui.config.font_small) or "GameFontNormalSmall"
    local fontNorm = (sfui.config and sfui.config.font) or "GameFontNormal"

    bar.startLabel = over:CreateFontString(nil, "OVERLAY", fontSmall)
    bar.startLabel:SetPoint("BOTTOMLEFT", backdrop, "TOPLEFT", 2, 4)
    bar.startLabel:SetJustifyH("LEFT")
    bar.startLabel:SetWidth(w * 0.45)
    bar.startLabel:SetWordWrap(false)
    bar.startLabel:SetTextColor(0.82, 0.82, 0.82, 1)
    bar.startLabel:SetShadowOffset(1, -1)
    bar.startLabel:SetShadowColor(0, 0, 0, 1)

    bar.destLabel = over:CreateFontString(nil, "OVERLAY", fontNorm)
    bar.destLabel:SetPoint("BOTTOMRIGHT", backdrop, "TOPRIGHT", -2, 4)
    bar.destLabel:SetJustifyH("RIGHT")
    bar.destLabel:SetWidth(w * 0.48)
    bar.destLabel:SetWordWrap(false)
    bar.destLabel:SetTextColor(1, 1, 1, 1)
    bar.destLabel:SetShadowOffset(1, -1)
    bar.destLabel:SetShadowColor(0, 0, 0, 1)

    bar.timeLabel = over:CreateFontString(nil, "OVERLAY", fontNorm)
    bar.timeLabel:SetPoint("RIGHT", backdrop, "LEFT", -8, 0)
    bar.timeLabel:SetJustifyH("RIGHT")
    bar.timeLabel:SetTextColor(0, 1, 1, 1)
    bar.timeLabel:SetShadowOffset(1, -1)
    bar.timeLabel:SetShadowColor(0, 0, 0, 1)

    bar.youMark = over:CreateTexture(nil, "OVERLAY")
    bar.youMark:SetTexture(WHITE)
    bar.youMark:SetSize(2, h + 6)
    bar.youMark:SetPoint("CENTER", backdrop, "CENTER", 0, 0)
    bar.youMark:SetVertexColor(1, 1, 1, 0.95)
    bar.youMark:Hide()

    bar.youLabel = over:CreateFontString(nil, "OVERLAY", fontSmall)
    bar.youLabel:SetPoint("BOTTOM", bar.youMark, "TOP", 0, 2)
    bar.youLabel:SetText("you")
    bar.youLabel:SetTextColor(0, 1, 1, 1)
    bar.youLabel:SetShadowOffset(1, -1)
    bar.youLabel:SetShadowColor(0, 0, 0, 1)
    bar.youLabel:Hide()

    local clip = CreateFrame("Frame", nil, bar)
    clip:SetPoint("TOPLEFT", backdrop, "BOTTOMLEFT", 2, -2)
    clip:SetPoint("TOPRIGHT", backdrop, "BOTTOMRIGHT", -2, -2)
    clip:SetHeight(28)
    clip:SetClipsChildren(true)
    clip.strip = CreateFrame("Frame", nil, clip)
    clip.strip:SetSize(1, 1)
    clip.glide = clip.strip:CreateAnimationGroup()
    clip.glide.move = clip.glide:CreateAnimation("Translation")
    clip.glide.move:SetSmoothing("NONE")
    clip.glide.move:SetDuration(SLIDE_STEP)
    clip:Hide()
    bar.clip = clip
    bar.stops = {}

    local exitBtn = CreateFrame("Button", nil, bar, "BackdropTemplate")
    exitBtn:SetSize(EXIT_SIZE, EXIT_SIZE)
    exitBtn:SetPoint("LEFT", backdrop, "RIGHT", 6, 0)
    exitBtn:SetBackdrop({
        bgFile   = WHITE,
        edgeFile = WHITE,
        edgeSize = 1,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    exitBtn:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    exitBtn:SetBackdropBorderColor(0, 0, 0, 1)
    local icon = exitBtn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexture(EXIT_ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    exitBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    exitBtn:SetScript("OnClick", function()
        if RequestEarlyLanding then RequestEarlyLanding() end
    end)
    exitBtn:SetScript("OnEnter", function(self)
        local tip = _G.GameTooltip
        if tip then
            tip:SetOwner(self, "ANCHOR_RIGHT")
            tip:SetText("land at next flight point", 1, 1, 1)
            tip:Show()
        end
    end)
    exitBtn:SetScript("OnLeave", function()
        local tip = _G.GameTooltip
        if tip then tip:Hide() end
    end)
    bar.exitBtn = exitBtn

    if sfui.theme and sfui.theme.RegisterBar then
        sfui.theme.RegisterBar(track, "flighttimer")
    end
    ApplyThemeStyling()
    ApplyBarPosition()

    if sfui.movers and sfui.movers.Register then
        sfui.movers.Register(bar, {
            key = "flighttimer",
            label = "flight timer",
            preferredPoint = "TOP",
            customSize = function()
                return w, 48
            end,
            getPoint = function()
                local p = (_G.SfuiDB and _G.SfuiDB.flightTimerPos) or Cfg().pos
                if p and p.point and p.x and p.y then
                    return p.point, UIParent, p.relPoint or p.point, p.x, p.y
                end
                return "TOP", UIParent, "TOP", 0, -140
            end,
            setPoint = function(point, _, relPoint, x, y)
                _G.SfuiDB = _G.SfuiDB or {}
                _G.SfuiDB.flightTimerPos = {
                    point    = point or "TOP",
                    relPoint = relPoint or point or "TOP",
                    x        = math_floor((x or 0) + 0.5),
                    y        = math_floor((y or -140) + 0.5),
                }
                ApplyBarPosition()
            end,
            resetPosition = function()
                if _G.SfuiDB then _G.SfuiDB.flightTimerPos = nil end
                ApplyBarPosition()
            end,
            isEnabled = function()
                return IsEnabled()
            end,
        })
    end

    return bar
end

local function EndFlight()
    flight = nil
    previewActive = false
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    if bar then
        if bar.clip and bar.clip.glide then bar.clip.glide:Stop() end
        bar:Hide()
    end
end

local function Land()
    if flight and flight.yards and not flight.early then
        local elapsed = GetTime() - flight.start
        if elapsed > 0 then
            local measured = flight.yards / elapsed / (flight.mult or 1)
            local speed = GetSpeed()
            if measured > speed * 0.75 and measured < speed * 1.33 then
                _G.SfuiDB = _G.SfuiDB or {}
                _G.SfuiDB.flightTimerSpeed = speed + (measured - speed) * 0.25
            end
        end
    end
    EndFlight()
end

local function Retarget(fl)
    if not (fl and not fl.early) then return end
    fl.early = true
    local points = fl.points
    if points and fl.yards and fl.eta then
        local elapsed = GetTime() - fl.start
        local flown = elapsed / fl.eta * fl.yards
        for i, p in ipairs(points) do
            if p.yards and p.yards > flown then
                for j = #points, i + 1, -1 do points[j] = nil end
                fl.eta = fl.eta * p.yards / fl.yards
                fl.yards = p.yards
                fl.dest = p.name or fl.dest
                ArmTimer(fl)
                break
            end
        end
    end
    LayoutRoute(fl)
end

local StartPreviewFlight

local function UpdateText()
    if not flight or not bar then return end
    local now = GetTime()
    local elapsed = now - flight.start

    if previewActive then
        if flight.eta and elapsed >= flight.eta then
            if previewHoldUntil == 0 then
                previewHoldUntil = now + PREVIEW_HOLD
            elseif now >= previewHoldUntil then
                previewHoldUntil = 0
                StartPreviewFlight()
                return
            end
            elapsed = flight.eta
        end
    elseif elapsed > 2 and UnitOnTaxi and not UnitOnTaxi("player") then
        flight.early = true
        Land()
        return
    end

    if flight.eta then
        bar.timeLabel:SetText(TimeLeftText(flight, elapsed))
        if not (C_DurationUtil and bar.track.SetTimerDuration) then
            bar.track:SetMinMaxValues(0, flight.eta)
            bar.track:SetValue(math_max(0, math_min(elapsed, flight.eta)))
        end
        ScrollStrip(flight, elapsed)
    else
        bar.timeLabel:SetText(FormatTime(elapsed))
    end
end

local function StartFlight(data)
    previewActive = false
    flight = {
        yards  = data.yards,
        start  = GetTime(),
        points = data.points,
        dest   = data.destName,
    }
    if data.yards then
        flight.mult = GetSpeedMultiplier()
        flight.eta = data.yards / (GetSpeed() * flight.mult)
    end

    EnsureBar()
    ApplyThemeStyling()
    ArmTimer(flight)
    LayoutRoute(flight)
    bar:Show()
    UpdateText()
    if not ticker then
        ticker = C_Timer.NewTicker(1, UpdateText)
    end
end

StartPreviewFlight = function()
    local faction = (UnitFactionGroup and UnitFactionGroup("player")) or "Alliance"
    local raw = PREVIEW_ROUTES[faction] or PREVIEW_ROUTES.Alliance
    local routes = sfui.flight_routes or {}
    local points, totalYards = {}, 0
    for i = 1, #raw, 2 do
        if i > 1 then
            local hop = routes[raw[i - 2] * 10000 + raw[i]] or 4500
            totalYards = totalYards + hop
        end
        points[#points + 1] = { name = raw[i + 1], yards = totalYards }
    end

    previewActive = true
    previewHoldUntil = 0
    flight = {
        yards     = totalYards,
        start     = GetTime(),
        points    = points,
        dest      = points[#points] and points[#points].name or "",
        eta       = PREVIEW_SECONDS,
        mult      = 1,
        lookahead = LOOKAHEAD * PREVIEW_SECONDS / (totalYards / GetSpeed()),
    }

    EnsureBar()
    ApplyThemeStyling()
    ArmTimer(flight)
    LayoutRoute(flight)
    bar:Show()
    UpdateText()
    if not ticker then
        ticker = C_Timer.NewTicker(1, UpdateText)
    end
end

RequestEarlyLanding = function()
    if previewActive and flight then
        Retarget(flight)
        UpdateText()
        return
    end
    if flight and not flight.early and TaxiRequestEarlyLanding then
        TaxiRequestEarlyLanding()
    end
end

function sfui.flighttimer.TogglePreview()
    if not IsEnabled() then return false end
    if previewActive then
        EndFlight()
        return false
    end
    StartPreviewFlight()
    return true
end

function sfui.flighttimer.IsPreviewActive()
    return previewActive
end

function sfui.flighttimer.ResetPosition()
    if _G.SfuiDB then _G.SfuiDB.flightTimerPos = nil end
    ApplyBarPosition()
end

local function OnTakeTaxiNode(slot)
    if not IsEnabled() then return end
    local yards, points, destName = RouteInfo(slot)
    pending = {
        yards    = yards,
        points   = points,
        destName = destName,
        clicked  = GetTime(),
    }
end

local function OnEvent(_, event)
    if event == "PLAYER_CONTROL_LOST" then
        if pending and (GetTime() - pending.clicked) < 5 then
            StartFlight(pending)
        end
        pending = nil
    elseif event == "PLAYER_CONTROL_GAINED" then
        if flight and not previewActive and UnitOnTaxi and not UnitOnTaxi("player") then
            Land()
        end
    end
end

function sfui.flighttimer.Apply()
    EnsureBar()
    if IsEnabled() then
        if not hooked then
            hooked = true
            if _G.TakeTaxiNode then
                hooksecurefunc("TakeTaxiNode", OnTakeTaxiNode)
            end
            if _G.TaxiRequestEarlyLanding then
                hooksecurefunc("TaxiRequestEarlyLanding", function()
                    if flight and not previewActive then
                        Retarget(flight)
                        UpdateText()
                    end
                end)
            end
        end
        if not events then
            events = CreateFrame("Frame")
            events:SetScript("OnEvent", OnEvent)
        end
        events:RegisterEvent("PLAYER_CONTROL_LOST")
        events:RegisterEvent("PLAYER_CONTROL_GAINED")
    else
        if events then events:UnregisterAllEvents() end
        pending = nil
        if flight then EndFlight() end
    end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    sfui.flighttimer.Apply()
end)

