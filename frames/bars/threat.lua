local addonName, addon = ...
sfui = sfui or {}
sfui.threat = sfui.threat or {}

local g      = sfui.config
local common = sfui.common
local cfg    = (g and g.threatBar) or {}

-- ─── Client Gate ─────────────────────────────────────────────────────────────
-- Per requirement: Camelot / Classic only, do not load or execute on Retail
if not (sfui.isCamelot or sfui.isClassic or (sfui.compat and (sfui.compat.is_camelot or sfui.compat.is_classic))) then
    return
end

-- ─── Localized Globals ───────────────────────────────────────────────────────
local CreateFrame                  = _G.CreateFrame
local UIParent                     = _G.UIParent
local UnitExists                   = _G.UnitExists
local UnitCanAttack                = _G.UnitCanAttack
local UnitIsDeadOrGhost            = _G.UnitIsDeadOrGhost
local UnitDetailedThreatSituation  = _G.UnitDetailedThreatSituation
local GetThreatStatusColor         = _G.GetThreatStatusColor
local math_floor                   = math.floor
local type                         = _G.type
local issecretvalue                = common.issecretvalue

-- ─── Frame Storage ───────────────────────────────────────────────────────────
local threatBar

-- ─── Primary Texture Resolver ────────────────────────────────────────────────
local GetBarTexture = sfui.widgets.get_bar_texture

function sfui.threat.SetBarTexture(texturePath)
    if not texturePath or texturePath == "" then
        texturePath = GetBarTexture()
    end
    if threatBar and threatBar.SetStatusBarTexture then
        threatBar:SetStatusBarTexture(texturePath)
    end
end

-- ─── Threat Color Resolver ───────────────────────────────────────────────────
local function GetThreatColor(status, pct)
    if GetThreatStatusColor and status then
        local tr, tg, tb = GetThreatStatusColor(status)
        if tr then return tr, tg, tb end
    end
    if status == 3 then
        return 0.90, 0.20, 0.20 -- Aggro / Red
    elseif status == 2 then
        return 1.00, 0.55, 0.15 -- Insecure / Orange
    elseif status == 1 then
        return 1.00, 0.85, 0.20 -- High Threat / Yellow
    end
    if pct and pct > 50 then
        return 0.85, 0.75, 0.25 -- Amber
    else
        return 0.25, 0.65, 0.90 -- Blue/Cyan
    end
end

-- ─── Cache State ─────────────────────────────────────────────────────────────
local cachedAnchor, cachedBar0
local lastThreatW, lastThreatH, lastPad, lastAnchorFrame
local lastThreatPct, lastThreatR, lastThreatG, lastThreatB

-- ─── Anchor & Dimension Helper ───────────────────────────────────────────────
local function GetPlayerHealthBar()
    if cachedAnchor and cachedBar0 then
        return cachedAnchor, cachedBar0
    end
    local bar = sfui.bars.get_bar0()
    if bar and bar.backdrop then
        cachedAnchor, cachedBar0 = bar.backdrop, bar
        return cachedAnchor, cachedBar0
    end
    local bar0 = _G.sfui_bar0
    local bd = _G.sfui_bar0_Backdrop or (bar0 and bar0.backdrop) or bar0
    cachedAnchor, cachedBar0 = bd, bar0
    return bd, bar0
end

local function InvalidateAnchorCache()
    cachedAnchor, cachedBar0 = nil, nil
    lastAnchorFrame = nil
end

local function UpdateDimensionsAndPosition(force)
    if not threatBar or not threatBar.backdrop then return end

    local anchor, bar0 = GetPlayerHealthBar()
    if not anchor then return end

    local healthW = (bar0 and bar0:GetWidth())
        or (anchor and anchor:GetWidth() and anchor:GetWidth() > 0 and (anchor:GetWidth() - 4))
        or (sfui.config and sfui.config.healthBar and sfui.config.healthBar.width)
        or 300

    -- Width: Exactly 80% of player health bar width
    local threatW = math_floor(healthW * 0.8)
    local height = (SfuiDB and SfuiDB.threatBar_height) or (cfg and cfg.height) or 4
    local pad = (cfg and cfg.backdrop and cfg.backdrop.padding) or 1

    if force or threatW ~= lastThreatW or height ~= lastThreatH or pad ~= lastPad or anchor ~= lastAnchorFrame then
        lastThreatW, lastThreatH, lastPad, lastAnchorFrame = threatW, height, pad, anchor
        threatBar:SetSize(threatW, height)
        threatBar.backdrop:SetSize(threatW + pad * 2, height + pad * 2)

        -- Anchor: Directly on top of player health bar (+1px offset)
        threatBar.backdrop:ClearAllPoints()
        threatBar.backdrop:SetPoint("BOTTOM", anchor, "TOP", 0, 1)
    end
end

-- ─── Group & Pet Auto-Enable Checkers ─────────────────────────────────────────
local function IsPlayerInGroup()
    if _G.IsInGroup then
        return _G.IsInGroup()
    elseif _G.GetNumGroupMembers then
        return _G.GetNumGroupMembers() > 0
    elseif _G.GetNumSubgroupMembers then
        return _G.GetNumSubgroupMembers() > 0
    end
    return false
end

local function HasActivePet()
    return UnitExists("pet") and not UnitIsDeadOrGhost("pet")
end

local function ShouldShowThreatBar()
    if SfuiDB and SfuiDB.enableThreatBar == false then
        return false
    end

    local inGroup = IsPlayerInGroup()
    local hasPet = HasActivePet()
    local autoGroup = (SfuiDB == nil or SfuiDB.threatBarGroup ~= false)
    local autoPet = (SfuiDB == nil or SfuiDB.threatBarPet ~= false)
    local allowSolo = (SfuiDB and SfuiDB.threatBarSolo == true)

    if allowSolo then
        return true
    end
    if inGroup and autoGroup then
        return true
    end
    if hasPet and autoPet then
        return true
    end

    return false
end

local function SetThreatBarShown(show)
    if not threatBar or not threatBar.backdrop then return end
    local wasShown = threatBar.backdrop:IsShown()
    if show and not wasShown then
        threatBar.backdrop:Show()
        if sfui.bars and sfui.bars.update_bar_positions then
            sfui.bars:update_bar_positions()
        end
    elseif not show and wasShown then
        threatBar.backdrop:Hide()
        if sfui.bars and sfui.bars.update_bar_positions then
            sfui.bars:update_bar_positions()
        end
    end
end

-- ─── Threat State Update ─────────────────────────────────────────────────────
local function UpdateThreat()
    if not threatBar or not threatBar.backdrop then return end

    if not ShouldShowThreatBar() then
        SetThreatBarShown(false)
        return
    end

    if not UnitExists("target") or not UnitCanAttack("player", "target") or UnitIsDeadOrGhost("target") then
        SetThreatBarShown(false)
        return
    end

    local anchor = GetPlayerHealthBar()
    if anchor and not anchor:IsShown() then
        SetThreatBarShown(false)
        return
    end

    SetThreatBarShown(true)

    if not lastThreatW then
        UpdateDimensionsAndPosition(false)
    end

    local _, status, scaledPct = UnitDetailedThreatSituation("player", "target")
    local isThreatSecret = issecretvalue(scaledPct)

    if scaledPct and (isThreatSecret or (type(scaledPct) == "number" and scaledPct > 0)) then
        if isThreatSecret or scaledPct ~= lastThreatPct then
            threatBar:SetValue(scaledPct)
            lastThreatPct = not isThreatSecret and scaledPct or nil
        end
        local r, g, b = GetThreatColor(status, not isThreatSecret and scaledPct or nil)
        if r ~= lastThreatR or g ~= lastThreatG or b ~= lastThreatB then
            threatBar:SetStatusBarColor(r, g, b)
            lastThreatR, lastThreatG, lastThreatB = r, g, b
        end
    else
        if lastThreatPct ~= 0 then
            threatBar:SetValue(0)
            lastThreatPct = 0
        end
        if lastThreatR ~= 0.25 or lastThreatG ~= 0.25 or lastThreatB ~= 0.25 then
            threatBar:SetStatusBarColor(0.25, 0.25, 0.25, 0.6)
            lastThreatR, lastThreatG, lastThreatB = 0.25, 0.25, 0.25
        end
    end
end

-- ─── Frame Construction ──────────────────────────────────────────────────────
local function CreateThreatFrame()
    if threatBar then return threatBar end

    local anchor, bar0 = GetPlayerHealthBar()
    local healthW = (bar0 and bar0:GetWidth()) or (sfui.config and sfui.config.healthBar and sfui.config.healthBar.width) or 300
    local threatW = math_floor(healthW * 0.8)
    local height  = (SfuiDB and SfuiDB.threatBar_height) or (cfg and cfg.height) or 4
    local pad     = (cfg and cfg.backdrop and cfg.backdrop.padding) or 1
    local bgCol   = (cfg and cfg.backdrop and cfg.backdrop.color) or { 0, 0, 0, 0.5 }
    local barTex  = GetBarTexture()

    local backdrop = CreateFrame("Frame", "SfuiThreatBar_Backdrop", UIParent, "BackdropTemplate")
    backdrop:SetSize(threatW + pad * 2, height + pad * 2)
    backdrop:SetFrameStrata("MEDIUM")
    backdrop:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        tile = true,
        tileSize = 32,
    })
    backdrop:SetBackdropColor(bgCol[1], bgCol[2], bgCol[3], bgCol[4] or 0.5)

    local bar = CreateFrame("StatusBar", "SfuiThreatBar", backdrop)
    bar:SetSize(threatW, height)
    bar:SetPoint("CENTER")
    bar:SetStatusBarTexture(barTex)
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)
    bar:SetStatusBarColor(0.25, 0.25, 0.25, 0.6)
    bar.backdrop = backdrop

    threatBar = bar
    threatBar.backdrop:Hide()

    if anchor then
        threatBar.backdrop:SetPoint("BOTTOM", anchor, "TOP", 0, 1)
    end

    return bar
end

-- ─── Public API ──────────────────────────────────────────────────────────────
function sfui.threat.GetFrame()
    return threatBar
end

function sfui.threat.GetAnchorFrame()
    return threatBar and threatBar.backdrop
end

function sfui.threat.IsShown()
    return threatBar and threatBar.backdrop and threatBar.backdrop:IsShown()
end

function sfui.threat.UpdatePosition()
    InvalidateAnchorCache()
    UpdateDimensionsAndPosition(true)
end

function sfui.threat.UpdateVisibility()
    UpdateThreat()
end

function sfui.threat.Update()
    UpdateThreat()
end

-- ─── Event Handlers ──────────────────────────────────────────────────────────
local function OnThreatUnitEvent(event, unit)
    if event == "UNIT_THREAT_SITUATION_UPDATE" or event == "UNIT_THREAT_LIST_UPDATE" then
        UpdateThreat()
    end
end

local function OnTargetChanged()
    UpdateThreat()
end

local function OnPlayerRegen()
    UpdateThreat()
end

local function OnPlayerEnteringWorld()
    InvalidateAnchorCache()
    UpdateDimensionsAndPosition(true)
    UpdateThreat()
end

-- ─── Initialization ──────────────────────────────────────────────────────────
local function Initialize()
    local bar = CreateThreatFrame()
    UpdateDimensionsAndPosition()

    -- Register with theme engine so the backdrop gets restyled on theme switches
    if bar and sfui.theme and sfui.theme.RegisterBar then
        sfui.theme.RegisterBar(bar, "threat")
    end

    -- Register unit threat events
    sfui.events.RegisterUnitEvents(
        {
            "UNIT_THREAT_SITUATION_UPDATE",
            "UNIT_THREAT_LIST_UPDATE",
        },
        "target",
        OnThreatUnitEvent
    )

    sfui.events.RegisterUnitEvents(
        {
            "UNIT_THREAT_SITUATION_UPDATE",
        },
        "player",
        OnThreatUnitEvent
    )

    -- Register pet unit events (for auto-enabling with pet)
    sfui.events.RegisterUnitEvents(
        {
            "UNIT_PET",
        },
        "player",
        function()
            UpdateThreat()
        end
    )

    sfui.events.RegisterUnitEvents(
        {
            "UNIT_THREAT_SITUATION_UPDATE",
        },
        "pet",
        OnThreatUnitEvent
    )

    -- Register global combat, target, and group roster events
    sfui.events.RegisterEvent("GROUP_ROSTER_UPDATE", UpdateThreat)
    sfui.events.RegisterEvent("PLAYER_TARGET_CHANGED", OnTargetChanged)
    sfui.events.RegisterEvent("PLAYER_REGEN_DISABLED", OnPlayerRegen)
    sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", OnPlayerRegen)
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", OnPlayerEnteringWorld)

    UpdateThreat()
end

sfui.events.RegisterEvent("PLAYER_LOGIN", Initialize)

-- ─── Diagnostics & Memory Watcher Telemetry ──────────────────────────────────
local _threatDebug = {}
function sfui.threat_debug_info()
    _threatDebug.created = (threatBar ~= nil)
    _threatDebug.shown = (threatBar ~= nil and threatBar:IsShown() == true)
    _threatDebug.status = (threatBar and threatBar.status) or 0
    _threatDebug.pct = (threatBar and threatBar.pct) or 0
    _threatDebug.inGroup = IsPlayerInGroup()
    _threatDebug.hasPet = HasActivePet()
    _threatDebug.shouldShow = ShouldShowThreatBar()
    return _threatDebug
end
sfui.threat.GetDebugInfo = sfui.threat_debug_info

if sfui.RegisterModule then
    sfui.RegisterModule("threat", sfui.threat)
end
