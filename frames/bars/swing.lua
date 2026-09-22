local addonName, addon = ...
sfui = sfui or {}
sfui.bars = sfui.bars or {}

-- Strictly enabled ONLY on Classic Era and Classic Forever (never in Retail)
if sfui.isRetail or not C_SwingTimer then
    return
end

sfui.swing = {}

local cfg = sfui.config
local common = sfui.common
local CreateFrame = CreateFrame
local UIParent = UIParent
local GetTime = GetTime
local UnitAttackSpeed = UnitAttackSpeed
local UnitAffectingCombat = UnitAffectingCombat
local UnitCanAttack = UnitCanAttack
local C_SwingTimer = C_SwingTimer
local Enum = Enum

local SWING_MAIN_HAND = (Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.MainHand) or 0
local SWING_OFF_HAND  = (Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.OffHand)  or 1
local SWING_RANGED    = (Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.Ranged)   or 2

local OUT_OF_RANGE_ALPHA = 0.4

local swingBars = {}

-- ─── Helper: Can player swing this weapon type? ─────────────────────────────
local function CanSwing(swingType)
    local mainSpeed, offSpeed, rangedSpeed = UnitAttackSpeed("player")
    if swingType == SWING_MAIN_HAND then
        return true
    elseif swingType == SWING_OFF_HAND then
        return offSpeed ~= nil and offSpeed > 0
    elseif swingType == SWING_RANGED then
        return rangedSpeed ~= nil and rangedSpeed > 0
    end
    return false
end

-- ─── Range Checking Presentation ────────────────────────────────────────────
local function SetOutOfRange(bar, isOutOfRange)
    if bar.isOutOfRange == isOutOfRange then return end
    bar.isOutOfRange = isOutOfRange

    local alpha = isOutOfRange and OUT_OF_RANGE_ALPHA or 1.0
    bar.backdrop:SetAlpha(alpha)

    if isOutOfRange then
        if bar.typeLabel then bar.typeLabel:SetTextColor(1, 0.25, 0.25, 1) end
        bar.timeLabel:SetTextColor(1, 0.25, 0.25, 1)
    else
        if bar.typeLabel then bar.typeLabel:SetTextColor(1, 1, 1, 0.9) end
        bar.timeLabel:SetTextColor(1, 1, 1, 0.9)
    end
end

local function UpdateRangeCheckRegistration(bar)
    local shouldCheck = bar.backdrop:IsShown() and CanSwing(bar.swingType)
    if shouldCheck == bar.isRangeCheckEnabled then return end
    bar.isRangeCheckEnabled = shouldCheck
    if C_SwingTimer and C_SwingTimer.EnableRangeCheck then
        C_SwingTimer.EnableRangeCheck(bar.swingType, shouldCheck)
    end
end

local function UpdateRangeState(bar)
    if not bar.isRangeCheckEnabled or not C_SwingTimer or not C_SwingTimer.IsTargetWithinSwingRange then
        SetOutOfRange(bar, false)
        return
    end
    local isInRange = C_SwingTimer.IsTargetWithinSwingRange(bar.swingType)
    SetOutOfRange(bar, isInRange == false)
end

-- ─── Swing Timer State & Tick ───────────────────────────────────────────────
local function ClearSwingTimer(bar)
    bar.duration = nil
    bar.endTime = nil
    bar.statusBar:SetValue(0)
    bar.pip:Hide()
    bar.timeLabel:SetText("")
    bar:SetScript("OnUpdate", nil)
end

local function OnUpdateBar(bar, elapsed)
    if not bar.endTime or not bar.duration then
        ClearSwingTimer(bar)
        return
    end

    local remaining = bar.endTime - GetTime()
    if remaining <= 0 then
        ClearSwingTimer(bar)
        return
    end

    local progress = (bar.duration - remaining) / bar.duration
    bar.statusBar:SetValue(progress)

    local barW = bar.statusBar:GetWidth()
    if barW and barW > 0 then
        bar.pip:ClearAllPoints()
        bar.pip:SetPoint("CENTER", bar.statusBar, "LEFT", barW * progress, 0)
    end
    bar.timeLabel:SetFormattedText("%.1fs", remaining)
end

local function ResetSwingTimer(bar, duration)
    if not duration or duration <= 0 then return end
    bar.duration = duration
    bar.endTime = GetTime() + duration
    bar.statusBar:SetValue(0)
    bar.pip:Show()
    bar.timeLabel:SetFormattedText("%.1fs", duration)
    bar:SetScript("OnUpdate", OnUpdateBar)
end

-- ─── Bar Construction ───────────────────────────────────────────────────────
local function CreateSwingBar(name, swingType, colorKey)
    local barCfg = cfg.swingBar or {
        width = 300,
        height = 8,
        spacing = 2,
        colors = {
            mainHand = { 0.4, 0.8, 1.0, 1.0 },
            offHand  = { 1.0, 0.65, 0.2, 1.0 },
            ranged   = { 0.3, 0.9, 0.4, 1.0 },
        },
        backdrop = {
            padding = 1,
            color = { 0, 0, 0, 0.6 },
        },
    }

    local mult = sfui.pixelScale or 1
    local padding = (barCfg.backdrop and barCfg.backdrop.padding or 1) * mult

    local backdrop = CreateFrame("Frame", "sfui_" .. name .. "_Backdrop", UIParent, "BackdropTemplate")
    backdrop:SetFrameStrata("MEDIUM")
    backdrop:SetSize(barCfg.width + padding * 2, barCfg.height + padding * 2)
    backdrop:SetBackdrop({
        bgFile = cfg.textures.white,
        tile = true,
        tileSize = 32,
    })
    local bgColor = (barCfg.backdrop and barCfg.backdrop.color) or { 0, 0, 0, 0.6 }
    backdrop:SetBackdropColor(unpack(bgColor))
    backdrop:Hide()

    local statusBar = CreateFrame("StatusBar", "sfui_" .. name, backdrop)
    statusBar:SetSize(barCfg.width, barCfg.height)
    statusBar:SetPoint("CENTER")
    statusBar:SetMinMaxValues(0, 1)
    statusBar:SetValue(0)

    -- Status bar texture
    local textureName = SfuiDB and SfuiDB.barTexture
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local texturePath = (LSM and textureName and LSM:Fetch("statusbar", textureName)) or cfg.barTexture
    statusBar:SetStatusBarTexture(texturePath)

    -- Bar color
    local col = (barCfg.colors and barCfg.colors[colorKey]) or { 0.4, 0.8, 1.0, 1.0 }
    statusBar:SetStatusBarColor(unpack(col))

    -- Leading Pip (spark)
    local pip = statusBar:CreateTexture(nil, "OVERLAY")
    pip:SetColorTexture(1, 1, 1, 0.9)
    pip:SetSize(2, barCfg.height + 2)
    pip:Hide()

    -- Time Label
    local timeLabel = statusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timeLabel:SetPoint("RIGHT", -4, 0)
    timeLabel:SetText("")
    timeLabel:SetTextColor(1, 1, 1, 0.9)

    local bar = statusBar
    bar.backdrop = backdrop
    bar.statusBar = statusBar
    bar.pip = pip
    bar.timeLabel = timeLabel
    bar.swingType = swingType
    bar.colorKey = colorKey

    swingBars[swingType] = bar
    return bar
end

-- ─── Initialization ─────────────────────────────────────────────────────────
local function EnsureBarsCreated()
    if not swingBars[SWING_MAIN_HAND] then
        CreateSwingBar("MainHandSwingBar", SWING_MAIN_HAND, "mainHand")
    end
    if not swingBars[SWING_OFF_HAND] then
        CreateSwingBar("OffHandSwingBar", SWING_OFF_HAND, "offHand")
    end
    if not swingBars[SWING_RANGED] then
        CreateSwingBar("RangedSwingBar", SWING_RANGED, "ranged")
    end
end

-- ─── Suppression of Blizzard's Native Swing Timer Frames ───────────────────
local function SuppressBlizzardSwingTimer()
    local frames = {
        _G["SwingTimerMainHandFrame"],
        _G["SwingTimerOffHandFrame"],
        _G["SwingTimerRangedFrame"],
    }
    for _, f in ipairs(frames) do
        if f then
            f:UnregisterAllEvents()
            f:Hide()
            f:SetScript("OnShow", function(self) self:Hide() end)
        end
    end
end

--- Checks if swing bar tracking is possible on the current client, settings, and character
function sfui.swing.IsPossible()
    if sfui.isRetail or not C_SwingTimer then return false end
    if SfuiDB and SfuiDB.enableSwingBars == false then return false end

    return CanSwing(SWING_MAIN_HAND) or CanSwing(SWING_RANGED)
end

--- Returns the lowest swing bar backdrop frame for anchoring (whether shown or hidden)
function sfui.swing.GetLowestPossibleBar()
    EnsureBarsCreated()
    if not sfui.swing.IsPossible() then return nil end

    -- Ranged/wand is always docked lowest when player has a ranged weapon or wand equipped
    if CanSwing(SWING_RANGED) then
        local rBar = swingBars[SWING_RANGED]
        if rBar and rBar.backdrop then
            return rBar.backdrop
        end
    end

    if CanSwing(SWING_OFF_HAND) then
        local oBar = swingBars[SWING_OFF_HAND]
        if oBar and oBar.backdrop then
            return oBar.backdrop
        end
    end

    if CanSwing(SWING_MAIN_HAND) then
        local mBar = swingBars[SWING_MAIN_HAND]
        if mBar and mBar.backdrop then
            return mBar.backdrop
        end
    end

    return nil
end

-- ─── External Public API for bars.lua ───────────────────────────────────────

--- Docks the active swing bars below anchorFrame (bar_minus_1 at -2, or bar0 at -1)
function sfui.swing.UpdatePositions(anchorFrame, spacing)
    EnsureBarsCreated()
    if not anchorFrame then return end

    local barCfg = cfg.swingBar or {}
    local swingSpacing = barCfg.spacing or 2
    local currentAnchor = anchorFrame

    local order = { SWING_MAIN_HAND, SWING_OFF_HAND, SWING_RANGED }
    local isFirst = true
    for _, sType in ipairs(order) do
        local bar = swingBars[sType]
        if bar and bar.backdrop and CanSwing(sType) then
            bar.backdrop:ClearAllPoints()
            local currentSpacing = isFirst and (spacing or swingSpacing) or swingSpacing
            bar.backdrop:SetPoint("TOP", currentAnchor, "BOTTOM", 0, -currentSpacing)
            currentAnchor = bar.backdrop
            isFirst = false
        end
    end
end

--- Updates visibility of the swing bars based on combat, weapons, and vehicles
function sfui.swing.UpdateVisibility(inCombat, hasEnemyTarget, isDragonflying, inVehicle)
    EnsureBarsCreated()

    local enabled = (SfuiDB and SfuiDB.enableSwingBars ~= false)
    if not enabled then
        for _, bar in pairs(swingBars) do
            bar.backdrop:Hide()
            ClearSwingTimer(bar)
            UpdateRangeCheckRegistration(bar)
        end
        return
    end

    if inCombat == nil then inCombat = UnitAffectingCombat("player") end
    if hasEnemyTarget == nil then hasEnemyTarget = UnitCanAttack("player", "target") end
    if isDragonflying == nil and common.is_dragonflying then isDragonflying = common.is_dragonflying() end
    if inVehicle == nil and common.is_in_vehicle then inVehicle = common.is_in_vehicle() end

    if isDragonflying or inVehicle then
        for _, bar in pairs(swingBars) do
            bar.backdrop:Hide()
            ClearSwingTimer(bar)
            UpdateRangeCheckRegistration(bar)
        end
        return
    end

    local shouldShow = (inCombat or hasEnemyTarget or (SfuiDB and SfuiDB.swingBarVisibility == "always"))

    for sType, bar in pairs(swingBars) do
        local canSwing = CanSwing(sType)
        if shouldShow and canSwing then
            bar.backdrop:Show()
            UpdateRangeCheckRegistration(bar)
            UpdateRangeState(bar)
        else
            bar.backdrop:Hide()
            ClearSwingTimer(bar)
            UpdateRangeCheckRegistration(bar)
        end
    end

    SuppressBlizzardSwingTimer()
end

--- Updates status bar textures for all swing bars
function sfui.swing.SetBarTexture(texturePath)
    if not texturePath then return end
    for _, bar in pairs(swingBars) do
        if bar.statusBar then
            bar.statusBar:SetStatusBarTexture(texturePath)
        end
    end
end

--- Returns the lowest visible swing bar backdrop (for any bottom-docking modules)
function sfui.swing.GetLowestBar(includeHidden)
    local order = { SWING_RANGED, SWING_OFF_HAND, SWING_MAIN_HAND }
    for _, sType in ipairs(order) do
        local bar = swingBars[sType]
        if bar and bar.backdrop and CanSwing(sType) and (bar.backdrop:IsShown() or includeHidden) then
            return bar.backdrop
        end
    end
    return nil
end

-- ─── Event Handling via sfui.events ─────────────────────────────────────────
local function OnSwingEvent(event, ...)
    EnsureBarsCreated()

    if event == "PLAYER_SWING" then
        local duration, swingType = ...
        local bar = swingBars[swingType]
        if bar then
            if not bar.backdrop:IsShown() and sfui.bars and sfui.bars.UpdateVisibility then
                sfui.bars.UpdateVisibility()
            end
            if bar.backdrop:IsShown() then
                ResetSwingTimer(bar, duration)
            end
        end
    elseif event == "PLAYER_SWING_RANGE_UPDATE" then
        local swingType, isInRange, checksRange = ...
        local bar = swingBars[swingType]
        if bar then
            SetOutOfRange(bar, checksRange and not isInRange)
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        for _, bar in pairs(swingBars) do
            if bar.backdrop:IsShown() then
                UpdateRangeState(bar)
            end
        end
    elseif event == "PLAYER_IN_COMBAT_CHANGED" or event == "PLAYER_ENTER_COMBAT" or event == "PLAYER_LEAVE_COMBAT"
        or event == "START_AUTOREPEAT_SPELL" or event == "STOP_AUTOREPEAT_SPELL" then
        if sfui.bars and sfui.bars.UpdateVisibility then
            sfui.bars.UpdateVisibility()
        else
            sfui.swing.UpdateVisibility()
        end
    elseif event == "WEAPON_SLOT_CHANGED" or event == "UNIT_ATTACK_SPEED" or event == "PLAYER_ENTERING_WORLD" then
        SuppressBlizzardSwingTimer()
        if sfui.bars and sfui.bars.UpdateVisibility then
            sfui.bars.UpdateVisibility()
        else
            sfui.swing.UpdateVisibility()
        end
        if sfui.trackedicons and sfui.trackedicons.ForceLayoutUpdate then
            sfui.trackedicons.ForceLayoutUpdate()
        elseif sfui.trackedicons and sfui.trackedicons.MarkDirty then
            sfui.trackedicons.MarkDirty(true)
        end
    end
end

sfui.events.RegisterEvent("PLAYER_SWING", OnSwingEvent)
sfui.events.RegisterEvent("PLAYER_SWING_RANGE_UPDATE", OnSwingEvent)
sfui.events.RegisterEvent("PLAYER_TARGET_CHANGED", OnSwingEvent)
sfui.events.RegisterEvent("WEAPON_SLOT_CHANGED", OnSwingEvent)
sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", OnSwingEvent)
sfui.events.RegisterEvent("PLAYER_IN_COMBAT_CHANGED", OnSwingEvent)
sfui.events.RegisterEvent("PLAYER_ENTER_COMBAT", OnSwingEvent)
sfui.events.RegisterEvent("PLAYER_LEAVE_COMBAT", OnSwingEvent)
sfui.events.RegisterEvent("START_AUTOREPEAT_SPELL", OnSwingEvent)
sfui.events.RegisterEvent("STOP_AUTOREPEAT_SPELL", OnSwingEvent)
sfui.events.RegisterUnitEvent("UNIT_ATTACK_SPEED", "player", function(event, ...)
    OnSwingEvent(event, ...)
end)
