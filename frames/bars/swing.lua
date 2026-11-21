local addonName, addon = ...
sfui = sfui or {}
sfui.bars = sfui.bars or {}

-- Strictly enabled ONLY on Classic Era and Classic Forever (never in Retail)
if sfui.isRetail or (not C_SwingTimer and not sfui.isEra) then
    return
end

sfui.swing               = sfui.swing or {}

local cfg                = sfui.config
local common             = sfui.common
local issecretvalue      = sfui.common.issecretvalue
local IsAttackSpeedValid = common.IsAttackSpeedValid or function(speed)
    if speed == nil then return false end
    if issecretvalue and issecretvalue(speed) then
        return true
    end
    return type(speed) == "number" and speed > 0
end
local CreateFrame        = CreateFrame
local UIParent           = UIParent
local GetTime            = GetTime
local GetInventoryItemID = GetInventoryItemID
local UnitClass          = UnitClass
local C_SwingTimer       = C_SwingTimer
local Enum               = Enum

local GetItemInfoInstant       = sfui.common.get_item_instant_info
local INVSLOT_OFFHAND          = _G.INVSLOT_OFFHAND or 17
local INVSLOT_RANGED           = _G.INVSLOT_RANGED or 18
local ITEM_CLASS_WEAPON        = (Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2
local ITEM_WEAPON_SUBCLASS_WAND = (Enum and Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Wand) or 19

local SWING_MAIN_HAND          = (Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.MainHand) or 0
local SWING_OFF_HAND           = (Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.OffHand) or 1
local SWING_RANGED             = (Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.Ranged) or 2
local SWING_TYPES              = { SWING_MAIN_HAND, SWING_OFF_HAND, SWING_RANGED }

local OUT_OF_RANGE_ALPHA       = 0.4

local swingBars                = {}
sfui.swing._bars               = swingBars
local swingContainer           = nil
local DEFAULT_ORDER            = { SWING_MAIN_HAND, SWING_OFF_HAND, SWING_RANGED }
local HUNTER_ORDER             = { SWING_RANGED, SWING_MAIN_HAND, SWING_OFF_HAND }
local _activeBars              = {}

local playerClass
local function GetPlayerClass()
    if not playerClass then
        local class = (sfui.common and sfui.common.get_player_class and sfui.common.get_player_class())
            or (UnitClass and select(2, UnitClass("player")))
        if class and class ~= "" then
            playerClass = class
        end
    end
    return playerClass
end

local function IsWandCaster()
    local class = GetPlayerClass()
    return class == "WARLOCK" or class == "MAGE" or class == "PRIEST"
end

local isAutoRepeating      = false
local isAttacking          = false
local hasOffHandWeapon     = false
local hasRangedWeapon      = false
local hasWandEquipped      = false
local lastPrimarySwingType = SWING_MAIN_HAND
local isUpdatingVisibility = false
local _wantBar             = {}
local _suppressedBar       = {}
local ClearSwingTimer

local function IsWandMode()
    return IsWandCaster() or hasWandEquipped
end

local function SharesMainHandSlot()
    return IsWandMode() or (GetPlayerClass() ~= "HUNTER")
end
sfui.swing.SharesMainHandSlot = SharesMainHandSlot

local function IsMeleeAttacking()
    if isAttacking then return true end
    if C_Spell and C_Spell.IsCurrentSpell then
        local ok, cur = pcall(C_Spell.IsCurrentSpell, 6603)
        if ok and cur then return true end
    elseif _G.IsCurrentSpell then
        local ok, cur = pcall(_G.IsCurrentSpell, 6603)
        if ok and cur then return true end
    end
    return false
end

-- ─── Helper: Cache equipped weapon states ───────────────────────────────────
local function UpdateEquippedWeapons()
    local offHandSpeed, rangedSpeed
    if _G.UnitAttackSpeed then
        local _, oh, rng = _G.UnitAttackSpeed("player")
        offHandSpeed, rangedSpeed = oh, rng
    end
    if not rangedSpeed and _G.UnitRangedDamage then
        rangedSpeed = _G.UnitRangedDamage("player")
    end
    hasOffHandWeapon = IsAttackSpeedValid(offHandSpeed)
    hasRangedWeapon = IsAttackSpeedValid(rangedSpeed)

    if not hasOffHandWeapon and GetInventoryItemID and GetItemInfoInstant then
        local offHandID = GetInventoryItemID("player", INVSLOT_OFFHAND)
        if offHandID and not (issecretvalue and issecretvalue(offHandID)) then
            local classID = select(6, GetItemInfoInstant(offHandID))
            if classID and not (issecretvalue and issecretvalue(classID)) then
                hasOffHandWeapon = (classID == ITEM_CLASS_WEAPON or classID == 2)
            end
        end
    end

    hasWandEquipped = false
    local rangedID = GetInventoryItemID and GetInventoryItemID("player", INVSLOT_RANGED)
    if rangedID and not (issecretvalue and issecretvalue(rangedID)) and GetItemInfoInstant then
        local classID, subClassID = select(6, GetItemInfoInstant(rangedID))
        if classID and not (issecretvalue and issecretvalue(classID)) then
            local isWeapon = (classID == ITEM_CLASS_WEAPON or classID == 2)
            if subClassID and not (issecretvalue and issecretvalue(subClassID)) then
                hasWandEquipped = isWeapon and (subClassID == ITEM_WEAPON_SUBCLASS_WAND or subClassID == 19)
            end
            if not hasRangedWeapon then
                hasRangedWeapon = isWeapon
            end
        end
    end
end

local function HasActiveSwingTimer(bar)
    if not bar or bar.duration == nil or bar.endTime == nil then
        return false
    end
    if issecretvalue and (issecretvalue(bar.endTime) or issecretvalue(bar.duration)) then
        return false
    end
    -- Hidden/suppressed bars pause OnUpdate in WoW, so expire elapsed timers lazily here
    if bar.endTime <= GetTime() then
        ClearSwingTimer(bar)
        return false
    end
    return true
end

-- ─── Helper: Can player swing this weapon type? ─────────────────────────────
local function CanSwing(swingType)
    if swingType == SWING_MAIN_HAND then
        if HasActiveSwingTimer(swingBars[SWING_MAIN_HAND]) then
            return true
        end
        return IsMeleeAttacking()
    elseif swingType == SWING_OFF_HAND then
        if not hasOffHandWeapon then
            return false
        end
        if HasActiveSwingTimer(swingBars[SWING_OFF_HAND]) then
            return true
        end
        return IsMeleeAttacking()
    elseif swingType == SWING_RANGED then
        if not hasRangedWeapon then
            return false
        end
        if HasActiveSwingTimer(swingBars[SWING_RANGED]) then
            return true
        end
        return isAutoRepeating
    end
    return false
end

-- ─── Range Checking Presentation ────────────────────────────────────────────
local function UpdateContainerAlpha()
    if not swingContainer then return end
    local shownCount = 0
    local outOfRangeCount = 0
    for i = 1, 3 do
        local bar = swingBars[SWING_TYPES[i]]
        if bar and bar:IsShown() then
            shownCount = shownCount + 1
            if bar.isOutOfRange then
                outOfRangeCount = outOfRangeCount + 1
            end
        end
    end

    if shownCount == 0 then
        swingContainer:SetAlpha(1.0)
        return
    end

    -- Apply alpha on container only when every visible bar is out of range (avoids double-dimming);
    -- otherwise keep container opaque and dim individual out-of-range lanes (e.g. Hunter melee weave).
    if outOfRangeCount == shownCount then
        swingContainer:SetAlpha(OUT_OF_RANGE_ALPHA)
        for i = 1, 3 do
            local bar = swingBars[SWING_TYPES[i]]
            if bar and bar:IsShown() then
                bar:SetAlpha(1.0)
            end
        end
    else
        swingContainer:SetAlpha(1.0)
        for i = 1, 3 do
            local bar = swingBars[SWING_TYPES[i]]
            if bar and bar:IsShown() then
                bar:SetAlpha(bar.isOutOfRange and OUT_OF_RANGE_ALPHA or 1.0)
            end
        end
    end
end

local function SetOutOfRange(bar, isOutOfRange)
    if bar.isOutOfRange == isOutOfRange then return end
    bar.isOutOfRange = isOutOfRange
    UpdateContainerAlpha()
end

local function GetSwingTimerProvider()
    return C_SwingTimer or _G.C_SwingTimer or sfui.swing._classicTimer
end

local function UpdateRangeCheckRegistration(bar)
    local shouldCheck = bar:IsShown() and CanSwing(bar.swingType)
    if shouldCheck == bar.isRangeCheckEnabled then return end
    bar.isRangeCheckEnabled = shouldCheck
    local provider = GetSwingTimerProvider()
    if provider and provider.EnableRangeCheck then
        provider.EnableRangeCheck(bar.swingType, shouldCheck)
    end
end

local function UpdateRangeState(bar)
    local provider = GetSwingTimerProvider()
    if not bar.isRangeCheckEnabled or not provider or not provider.IsTargetWithinSwingRange then
        SetOutOfRange(bar, false)
        return
    end
    local isInRange = provider.IsTargetWithinSwingRange(bar.swingType)
    SetOutOfRange(bar, isInRange == false)
end

-- ─── Swing Timer State & Tick ───────────────────────────────────────────────
ClearSwingTimer = function(bar)
    bar.duration = nil
    bar.endTime = nil
    bar.statusBar:SetValue(0)
    bar.pip:Hide()
    bar:SetScript("OnUpdate", nil)

    local shouldHide
    if bar.swingType == SWING_RANGED then
        shouldHide = not isAutoRepeating
    else
        shouldHide = not IsMeleeAttacking()
    end

    if shouldHide and bar:IsShown() then
        bar:Hide()
        if not isUpdatingVisibility and sfui.swing.UpdateVisibility then
            sfui.swing.UpdateVisibility()
        end
    end
end

local function OnUpdateBar(bar)
    local endTime = bar.endTime
    if not endTime then
        ClearSwingTimer(bar)
        return
    end

    if issecretvalue and (issecretvalue(endTime) or issecretvalue(bar.duration)) then
        ClearSwingTimer(bar)
        return
    end

    local remaining = endTime - GetTime()
    if remaining <= 0 then
        ClearSwingTimer(bar)
        return
    end

    bar.statusBar:SetValue((bar.duration - remaining) / bar.duration)
end

local function ResetSwingTimer(bar, duration)
    if not duration then return end
    if issecretvalue and issecretvalue(duration) then return end
    if duration <= 0 then return end
    bar.duration = duration
    bar.endTime = GetTime() + duration
    bar.statusBar:SetValue(0)
    bar.pip:Show()
    bar:SetScript("OnUpdate", OnUpdateBar)
end

local function GetBarColor(colorKey, swingType)
    local barCfg = cfg.swingBar or {}
    local colors = barCfg.colors or {}

    if swingType == SWING_RANGED and IsWandMode() then
        return colors.wand or { 0.4, 0.0, 1.0, 1.0 }
    end

    return colors[colorKey] or { 0.4, 0.8, 1.0, 1.0 }
end

local function UpdateBarColors()
    for _, sType in ipairs(SWING_TYPES) do
        local bar = swingBars[sType]
        if bar and bar.statusBar and bar.colorKey then
            local col = GetBarColor(bar.colorKey, sType)
            bar.statusBar:SetStatusBarColor(unpack(col))
        end
    end
end
sfui.swing.UpdateBarColors = UpdateBarColors

local function GetBarMetrics()
    local barCfg = cfg.swingBar or {}
    local width = barCfg.width or 300
    local height = barCfg.height or 8
    local spacing = barCfg.spacing or 2
    local mult = sfui.pixelScale or 1
    local padding = (barCfg.backdrop and barCfg.backdrop.padding or 1) * mult
    return width, height, padding, spacing, mult
end

-- ─── Bar Construction ───────────────────────────────────────────────────────
local function EnsureContainerCreated()
    if swingContainer then return swingContainer end

    local barCfg = cfg.swingBar or {}
    local width, height, padding = GetBarMetrics()

    local backdrop = CreateFrame("Frame", "sfui_SwingBar_Backdrop", UIParent, "BackdropTemplate")
    backdrop:SetFrameStrata("MEDIUM")
    backdrop:SetSize(width + padding * 2, height + padding * 2)
    backdrop:SetBackdrop({
        bgFile = cfg.textures.white,
        tile = true,
        tileSize = 32,
    })
    local bgColor = (barCfg.backdrop and barCfg.backdrop.color) or { 0, 0, 0, 0.6 }
    backdrop:SetBackdropColor(unpack(bgColor))
    backdrop:Hide()

    swingContainer = backdrop
    sfui.swing._container = swingContainer
    return swingContainer
end

local function CreateSwingBar(name, swingType, colorKey)
    local backdrop = EnsureContainerCreated()
    local width, height = GetBarMetrics()

    local statusBar = CreateFrame("StatusBar", "sfui_" .. name, backdrop)
    statusBar:SetSize(width, height)
    statusBar:SetPoint("TOP", backdrop, "TOP", 0, 0)
    statusBar:SetMinMaxValues(0, 1)
    statusBar:SetValue(0)
    statusBar:Hide()
    if sfui.common and sfui.common.set_pixel_snapping then
        sfui.common.set_pixel_snapping(statusBar)
    end

    -- Status bar texture
    local texturePath = (sfui.widgets and sfui.widgets.get_bar_texture and sfui.widgets.get_bar_texture())
    if not texturePath or texturePath == "" then
        local textureName = SfuiDB and SfuiDB.barTexture
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        texturePath = (LSM and textureName and LSM:Fetch("statusbar", textureName)) or cfg.barTexture
    end
    statusBar:SetStatusBarTexture(texturePath)

    -- Bar color
    local col = GetBarColor(colorKey, swingType)
    statusBar:SetStatusBarColor(unpack(col))

    -- Leading Pip (spark) anchored directly to the status bar texture
    local pip = statusBar:CreateTexture(nil, "OVERLAY")
    pip:SetColorTexture(1, 1, 1, 0.9)
    pip:SetSize(2, height + 2)
    local barTex = statusBar:GetStatusBarTexture()
    if barTex then
        pip:SetPoint("CENTER", barTex, "RIGHT", 0, 0)
    end
    pip:Hide()

    local bar = statusBar
    bar.backdrop = backdrop
    bar.statusBar = statusBar
    bar.pip = pip
    bar.swingType = swingType
    bar.colorKey = colorKey

    swingBars[swingType] = bar
    return bar
end

-- ─── Initialization ─────────────────────────────────────────────────────────
local function EnsureBarsCreated()
    EnsureContainerCreated()
    local created = false
    if not swingBars[SWING_MAIN_HAND] then
        local bar = CreateSwingBar("MainHandSwingBar", SWING_MAIN_HAND, "mainHand")
        sfui.theme.RegisterBar(bar, "swing")
        created = true
    end
    if not swingBars[SWING_OFF_HAND] then
        CreateSwingBar("OffHandSwingBar", SWING_OFF_HAND, "offHand")
        created = true
    end
    if not swingBars[SWING_RANGED] then
        CreateSwingBar("RangedSwingBar", SWING_RANGED, "ranged")
        created = true
    end
    if created then
        UpdateBarColors()
    end

    if swingContainer and not swingContainer._moverRegistered and sfui.movers and sfui.movers.Register then
        swingContainer._moverRegistered = true
        sfui.movers.Register(swingContainer, {
            key = "swing",
            label = "swing bars",
            preferredPoint = "BOTTOM",
            customSize = function()
                local w = (swingContainer and swingContainer:GetWidth()) or 302
                local h = math.max(16, (swingContainer and swingContainer:GetHeight()) or 10)
                return w, h
            end,
            getPoint = function()
                local cp = SfuiDB and SfuiDB.swingBarPos
                if cp and cp.point and cp.x and cp.y then
                    return cp.point, UIParent, cp.relPoint or cp.point, cp.x, cp.y
                end
                local bd = swingContainer
                if bd and bd:GetLeft() and bd:GetBottom() and sfui.movers.CalculateRelativeCoordinates then
                    local pt, rPt, x, y = sfui.movers.CalculateRelativeCoordinates(bd:GetLeft(), bd:GetBottom(),
                        bd:GetWidth(), bd:GetHeight(), "BOTTOM")
                    return pt, UIParent, rPt, x, y
                end
                local hX = (SfuiDB and SfuiDB.healthBarX) or 0
                local hY = ((SfuiDB and SfuiDB.healthBarY) or 160) - 24
                return "BOTTOM", UIParent, "BOTTOM", hX, hY
            end,
            setPoint = function(point, _, relPoint, x, y)
                local pt = point or "BOTTOM"
                local rPt = relPoint or pt
                local sx = math.floor((x or 0) + 0.5)
                local sy = math.floor((y or 136) + 0.5)
                SfuiDB = SfuiDB or {}
                SfuiDB.swingBarPos = { point = pt, relPoint = rPt, x = sx, y = sy }
                sfui.swing.UpdatePositions()
            end,
            resetPosition = function()
                if SfuiDB then SfuiDB.swingBarPos = nil end
                sfui.swing.UpdatePositions()
            end,
            isEnabled = function()
                return sfui.swing.IsPossible()
            end,
        })
    end
end

-- ─── Suppression of Blizzard's Native Swing Timer Frames ───────────────────
local BLIZZARD_FRAME_NAMES = {
    "SwingTimerMainHandFrame",
    "SwingTimerOffHandFrame",
    "SwingTimerRangedFrame",
}

local function SuppressBlizzardSwingTimer()
    if not C_SwingTimer then return end
    if SfuiDB and SfuiDB.enableSwingBars == false then return end

    -- Keep CVar enabled so the client engine dispatches PLAYER_SWING events
    if sfui.common and sfui.common.set_cvar then
        sfui.common.set_cvar("showSwingTimer", 1)
    elseif (not InCombatLockdown or not InCombatLockdown()) then
        local set = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
        local get = (C_CVar and C_CVar.GetCVar) or _G.GetCVar
        if get and set and get("showSwingTimer") == "0" then
            set("showSwingTimer", 1)
        end
    end

    local mgr = _G["SwingTimerManagerFrame"]
    if mgr and mgr.SetAlpha and (not mgr.GetAlpha or mgr:GetAlpha() ~= 0) then
        mgr:SetAlpha(0)
    end

    for i = 1, 3 do
        local f = _G[BLIZZARD_FRAME_NAMES[i]]
        if f then
            if f.SetAlpha and (not f.GetAlpha or f:GetAlpha() ~= 0) then
                f:SetAlpha(0)
            end
            if f.Selection and f.Selection.SetAlpha then
                f.Selection:SetAlpha(0)
            end
            local isProtected = f.IsProtected and f:IsProtected()
            if not isProtected and f.EnableMouse and not (InCombatLockdown and InCombatLockdown()) then
                pcall(f.EnableMouse, f, false)
                if f.EnableMouseClicks then pcall(f.EnableMouseClicks, f, false) end
                if f.EnableMouseMotion then pcall(f.EnableMouseMotion, f, false) end
            end
            if not f._sfuiSuppressed then
                f._sfuiSuppressed = true
                if _G.hooksecurefunc and f.SetAlpha then
                    _G.hooksecurefunc(f, "SetAlpha", function(self, alpha)
                        if alpha and alpha > 0 and not (SfuiDB and SfuiDB.enableSwingBars == false) then
                            self:SetAlpha(0)
                        end
                    end)
                end
                if f.HookScript then
                    f:HookScript("OnShow", function(self)
                        if not (SfuiDB and SfuiDB.enableSwingBars == false) then
                            if self.SetAlpha then self:SetAlpha(0) end
                            if self.SetScript then self:SetScript("OnUpdate", nil) end
                        end
                    end)
                end
            end
        end
    end
end

--- Checks if swing bar tracking is possible on the current client, settings, and character
function sfui.swing.IsPossible()
    if sfui.isRetail or (not C_SwingTimer and not sfui.isEra) then return false end
    if SfuiDB and SfuiDB.enableSwingBars == false then return false end

    return true
end

local lastAnchorFrame, lastSpacing

--- Returns the fixed single-row swing bar container frame for anchoring (whether shown or hidden)
function sfui.swing.GetLowestPossibleBar()
    EnsureBarsCreated()
    if not sfui.swing.IsPossible() then return nil end
    if not lastAnchorFrame then
        sfui.swing.UpdatePositions()
    end
    return swingContainer
end

-- ─── External Public API for bars.lua ───────────────────────────────────────

local function PositionSplitBar(bar, barWidth, height, anchorPoint, yOffset, isSingle)
    bar.statusBar:SetSize(barWidth, height)
    bar.statusBar:ClearAllPoints()
    bar.statusBar:SetPoint(anchorPoint, swingContainer, anchorPoint, 0, yOffset)
    if bar.pip then
        bar.pip:SetSize(2, isSingle and (height + 2) or height)
    end
end

local function LayoutVisibleBars()
    if not swingContainer then return end

    local barWidth, barHeight, padding, _, mult = GetBarMetrics()
    local order = (GetPlayerClass() == "HUNTER" and not IsWandMode()) and HUNTER_ORDER or DEFAULT_ORDER

    local count = 0
    for i = 1, 3 do
        local bar = swingBars[order[i]]
        if bar and bar:IsShown() then
            count = count + 1
            _activeBars[count] = bar
        end
    end
    for i = count + 1, #_activeBars do
        _activeBars[i] = nil
    end

    if count == 0 then
        swingContainer:Hide()
        swingContainer:SetAlpha(1.0)
        return
    end

    swingContainer:Show()
    local gap = math.max(1, math.floor(1 * mult + 0.5))

    if count == 1 then
        PositionSplitBar(_activeBars[1], barWidth, barHeight, "TOP", -padding, true)
    elseif count == 2 then
        local avail = math.max(2, barHeight - gap)
        local h1 = math.ceil(avail / 2)
        local h2 = avail - h1
        PositionSplitBar(_activeBars[1], barWidth, h1, "TOP", -padding, false)
        PositionSplitBar(_activeBars[2], barWidth, h2, "BOTTOM", padding, false)
    else
        local avail = math.max(3, barHeight - gap * 2)
        local h1 = math.ceil(avail / 3)
        local rem = avail - h1
        local h2 = math.ceil(rem / 2)
        local h3 = rem - h2
        PositionSplitBar(_activeBars[1], barWidth, h1, "TOP", -padding, false)
        PositionSplitBar(_activeBars[2], barWidth, h2, "TOP", -(padding + h1 + gap), false)
        PositionSplitBar(_activeBars[3], barWidth, h3, "BOTTOM", padding, false)
    end

    UpdateContainerAlpha()
end

--- Docks the fixed single-row swing bar container below anchorFrame (bar_minus_1 at -2, or bar0 at -1)
function sfui.swing.UpdatePositions(anchorFrame, spacing)
    EnsureBarsCreated()
    if anchorFrame then
        lastAnchorFrame = anchorFrame
    else
        anchorFrame = lastAnchorFrame
    end
    if spacing then
        lastSpacing = spacing
    else
        spacing = lastSpacing
    end
    if not anchorFrame then
        local barMinus1 = _G["sfui_bar_minus_1_Backdrop"] or _G["sfui_bar-1_Backdrop"]
            or (sfui.bars and sfui.bars.get_bar_minus_1 and sfui.bars.get_bar_minus_1().backdrop)
        local bar0 = _G["sfui_bar0_Backdrop"] or (sfui.bars and sfui.bars.get_bar0 and sfui.bars.get_bar0().backdrop)
        if not bar0 and sfui.bars and sfui.bars.get_bar0 then
            local b0 = sfui.bars.get_bar0()
            bar0 = b0 and b0.backdrop
        end
        anchorFrame = (barMinus1 and (barMinus1:IsShown() or (SfuiDB == nil or SfuiDB.enablePowerBar ~= false))) and
            barMinus1 or bar0
    end

    local customPos = SfuiDB and SfuiDB.swingBarPos
    local hasCustomPos = customPos and customPos.point and customPos.x and customPos.y
    if not anchorFrame and not hasCustomPos then return end

    local _, _, _, swingSpacing = GetBarMetrics()
    if swingContainer then
        swingContainer:ClearAllPoints()
        if hasCustomPos then
            swingContainer:SetPoint(customPos.point, UIParent, customPos.relPoint or customPos.point, customPos.x,
                customPos.y)
        else
            local primarySpacing = spacing or swingSpacing
            swingContainer:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -primarySpacing)
        end
    end

    LayoutVisibleBars()
end

--- Updates visibility of the swing bars based on combat, weapons, and vehicles
function sfui.swing.UpdateVisibility(inCombat, hasEnemyTarget, isDragonflying, inVehicle)
    EnsureBarsCreated()

    local enabled = not (SfuiDB and SfuiDB.enableSwingBars == false)
    if not enabled then
        isUpdatingVisibility = true
        for _, bar in pairs(swingBars) do
            bar:Hide()
            ClearSwingTimer(bar)
            UpdateRangeCheckRegistration(bar)
        end
        if swingContainer then
            swingContainer:Hide()
            swingContainer:SetAlpha(1.0)
        end
        isUpdatingVisibility = false
        return
    end
    if isDragonflying == nil and common.is_dragonflying then isDragonflying = common.is_dragonflying() end
    if inVehicle == nil and common.is_in_vehicle then inVehicle = common.is_in_vehicle() end

    if isDragonflying or inVehicle then
        isUpdatingVisibility = true
        for i = 1, 3 do
            local bar = swingBars[SWING_TYPES[i]]
            if bar then
                bar:Hide()
                ClearSwingTimer(bar)
                UpdateRangeCheckRegistration(bar)
            end
        end
        if swingContainer then
            swingContainer:Hide()
            swingContainer:SetAlpha(1.0)
        end
        isUpdatingVisibility = false
        return
    end

    local shouldShow = (IsMeleeAttacking() or isAutoRepeating or (SfuiDB and SfuiDB.swingBarVisibility == "always"))

    for i = 1, 3 do
        local sType = SWING_TYPES[i]
        _wantBar[sType] = shouldShow and CanSwing(sType) or false
        _suppressedBar[sType] = false
    end

    -- Mutually exclusive ownership between ranged and melee for non-hunter classes & wand users
    local wantMelee = _wantBar[SWING_MAIN_HAND] or _wantBar[SWING_OFF_HAND]
    if SharesMainHandSlot() and _wantBar[SWING_RANGED] and wantMelee then
        local meleeActive = IsMeleeAttacking()
        local keepRanged
        if isAutoRepeating and not meleeActive then
            keepRanged = true
        elseif meleeActive and not isAutoRepeating then
            keepRanged = false
        else
            keepRanged = (lastPrimarySwingType == SWING_RANGED)
        end

        if keepRanged then
            _suppressedBar[SWING_MAIN_HAND] = _wantBar[SWING_MAIN_HAND]
            _suppressedBar[SWING_OFF_HAND]  = _wantBar[SWING_OFF_HAND]
            _wantBar[SWING_MAIN_HAND] = false
            _wantBar[SWING_OFF_HAND]  = false
        else
            _suppressedBar[SWING_RANGED] = true
            _wantBar[SWING_RANGED] = false
        end
    end

    isUpdatingVisibility = true
    local now = GetTime()
    for i = 1, 3 do
        local sType = SWING_TYPES[i]
        local bar = swingBars[sType]
        if bar then
            if _wantBar[sType] then
                if bar.endTime and bar.duration and not (issecretvalue and (issecretvalue(bar.endTime) or issecretvalue(bar.duration))) and bar.duration > 0 then
                    local remaining = bar.endTime - now
                    local pct = math.max(0, math.min(1, (bar.duration - remaining) / bar.duration))
                    bar.statusBar:SetValue(pct)
                end
                bar:Show()
                UpdateRangeCheckRegistration(bar)
                UpdateRangeState(bar)
            else
                bar:Hide()
                if not _suppressedBar[sType] then
                    ClearSwingTimer(bar)
                end
                UpdateRangeCheckRegistration(bar)
            end
        end
    end
    isUpdatingVisibility = false

    sfui.swing.UpdatePositions()
end

--- Updates status bar textures for all swing bars
function sfui.swing.SetBarTexture(texturePath)
    if not texturePath then return end
    for i = 1, 3 do
        local bar = swingBars[SWING_TYPES[i]]
        if bar and bar.statusBar then
            bar.statusBar:SetStatusBarTexture(texturePath)
            local barTex = bar.statusBar:GetStatusBarTexture()
            if bar.pip and barTex then
                bar.pip:ClearAllPoints()
                bar.pip:SetPoint("CENTER", barTex, "RIGHT", 0, 0)
            end
        end
    end
end

--- Returns the swing bar container frame (for any bottom-docking modules)
function sfui.swing.GetLowestBar(includeHidden)
    if swingContainer and (swingContainer:IsShown() or includeHidden) then
        return swingContainer
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
            if swingType == SWING_MAIN_HAND or swingType == SWING_OFF_HAND then
                isAttacking = true
                lastPrimarySwingType = SWING_MAIN_HAND
            elseif swingType == SWING_RANGED then
                isAutoRepeating = true
                lastPrimarySwingType = SWING_RANGED
            end
            ResetSwingTimer(bar, duration)
            if not bar:IsShown() or not (swingContainer and swingContainer:IsShown()) then
                if sfui.bars and sfui.bars.UpdateVisibility then
                    sfui.bars.UpdateVisibility()
                else
                    sfui.swing.UpdateVisibility()
                end
            else
                UpdateRangeCheckRegistration(bar)
                UpdateRangeState(bar)
                sfui.swing.UpdatePositions()
            end
        end
    elseif event == "PLAYER_SWING_RANGE_UPDATE" then
        local swingType, isInRange, checksRange = ...
        local bar = swingBars[swingType]
        if bar then
            SetOutOfRange(bar, checksRange and not isInRange)
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        for i = 1, 3 do
            local bar = swingBars[SWING_TYPES[i]]
            if bar and bar:IsShown() then
                UpdateRangeState(bar)
            end
        end
        if sfui.bars and sfui.bars.UpdateVisibility then
            sfui.bars.UpdateVisibility()
        else
            sfui.swing.UpdateVisibility()
        end
    elseif event == "PLAYER_ENTER_COMBAT" then
        isAttacking = true
        lastPrimarySwingType = SWING_MAIN_HAND
        if sfui.bars and sfui.bars.UpdateVisibility then
            sfui.bars.UpdateVisibility()
        else
            sfui.swing.UpdateVisibility()
        end
        sfui.swing.UpdatePositions()
    elseif event == "PLAYER_LEAVE_COMBAT" then
        isAttacking = false
        if sfui.bars and sfui.bars.UpdateVisibility then
            sfui.bars.UpdateVisibility()
        else
            sfui.swing.UpdateVisibility()
        end
        sfui.swing.UpdatePositions()
    elseif event == "START_AUTOREPEAT_SPELL" then
        isAutoRepeating = true
        lastPrimarySwingType = SWING_RANGED
        if sfui.bars and sfui.bars.UpdateVisibility then
            sfui.bars.UpdateVisibility()
        else
            sfui.swing.UpdateVisibility()
        end
        sfui.swing.UpdatePositions()
    elseif event == "STOP_AUTOREPEAT_SPELL" then
        isAutoRepeating = false
        if sfui.bars and sfui.bars.UpdateVisibility then
            sfui.bars.UpdateVisibility()
        else
            sfui.swing.UpdateVisibility()
        end
        sfui.swing.UpdatePositions()
    elseif event == "PLAYER_DEAD" then
        isAttacking = false
        isAutoRepeating = false
        lastPrimarySwingType = SWING_MAIN_HAND
        if sfui.bars and sfui.bars.UpdateVisibility then
            sfui.bars.UpdateVisibility()
        else
            sfui.swing.UpdateVisibility()
        end
        sfui.swing.UpdatePositions()
    elseif event == "PLAYER_IN_COMBAT_CHANGED" then
        if sfui.bars and sfui.bars.UpdateVisibility then
            sfui.bars.UpdateVisibility()
        else
            sfui.swing.UpdateVisibility()
        end
    elseif event == "UNIT_ATTACK_SPEED" or event == "UNIT_INVENTORY_CHANGED" or event == "WEAPON_SLOT_CHANGED" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LOGIN" then
        if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LOGIN" then
            isAttacking = false
            isAutoRepeating = false
            lastPrimarySwingType = SWING_MAIN_HAND
            playerClass = nil
        end
        UpdateEquippedWeapons()
        UpdateBarColors()
        SuppressBlizzardSwingTimer()
        if sfui.bars and sfui.bars.UpdateVisibility then
            sfui.bars.UpdateVisibility()
        else
            sfui.swing.UpdateVisibility()
        end
        sfui.swing.UpdatePositions()
        if sfui.trackedicons and sfui.trackedicons.ForceLayoutUpdate then
            sfui.trackedicons.ForceLayoutUpdate()
        end
    end
end

sfui.swing.OnSwingEvent = OnSwingEvent

if C_SwingTimer then
    sfui.events.RegisterEvent("PLAYER_SWING", OnSwingEvent)
    sfui.events.RegisterEvent("PLAYER_SWING_RANGE_UPDATE", OnSwingEvent)
end
sfui.events.RegisterEvent("PLAYER_TARGET_CHANGED", OnSwingEvent)
sfui.events.RegisterEvent("WEAPON_SLOT_CHANGED", OnSwingEvent)
sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", OnSwingEvent)
sfui.events.RegisterEvent("PLAYER_LOGIN", OnSwingEvent)
sfui.events.RegisterUnitEvents({ "UNIT_ATTACK_SPEED", "UNIT_INVENTORY_CHANGED" }, "player", OnSwingEvent)
sfui.events.RegisterEvent("PLAYER_IN_COMBAT_CHANGED", OnSwingEvent)
sfui.events.RegisterEvent("PLAYER_ENTER_COMBAT", OnSwingEvent)
sfui.events.RegisterEvent("PLAYER_LEAVE_COMBAT", OnSwingEvent)
sfui.events.RegisterEvent("START_AUTOREPEAT_SPELL", OnSwingEvent)
sfui.events.RegisterEvent("STOP_AUTOREPEAT_SPELL", OnSwingEvent)
sfui.events.RegisterEvent("PLAYER_DEAD", OnSwingEvent)
sfui.events.RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", SuppressBlizzardSwingTimer)
if _G.EventRegistry and _G.EventRegistry.RegisterCallback then
    _G.EventRegistry:RegisterCallback("EditMode.Enter", SuppressBlizzardSwingTimer, sfui.swing)
    _G.EventRegistry:RegisterCallback("EditMode.Exit", SuppressBlizzardSwingTimer, sfui.swing)
end

UpdateEquippedWeapons()
SuppressBlizzardSwingTimer()

-- ─── Diagnostics & Memory Watcher Telemetry ──────────────────────────────────
local _swingDebug = {}
function sfui.swing_debug_info()
    local barCount = 0
    local shownCount = 0
    for _, b in pairs(swingBars) do
        barCount = barCount + 1
        if b:IsShown() then shownCount = shownCount + 1 end
    end
    local mhBar = swingBars[SWING_MAIN_HAND]
    local ohBar = swingBars[SWING_OFF_HAND]
    local rBar = swingBars[SWING_RANGED]
    local mhSpeed, ohSpeed, rSpeed = UnitAttackSpeed("player")
    if not rSpeed and _G.UnitRangedDamage then
        rSpeed = _G.UnitRangedDamage("player")
    end
    _swingDebug.isPossible = (sfui.swing.IsPossible and sfui.swing.IsPossible()) or false
    _swingDebug.barCount = barCount
    _swingDebug.shownCount = shownCount
    _swingDebug.isAttacking = IsMeleeAttacking() or isAutoRepeating
    _swingDebug.isMelee = IsMeleeAttacking()
    _swingDebug.isAutoRepeating = isAutoRepeating
    _swingDebug.hasMainHand = IsAttackSpeedValid(mhSpeed)
    _swingDebug.hasOffHand = hasOffHandWeapon
    _swingDebug.hasRanged = hasRangedWeapon
    _swingDebug.mainHandSpeed = (mhSpeed and not (issecretvalue and issecretvalue(mhSpeed))) and mhSpeed or 0
    _swingDebug.offHandSpeed = (ohSpeed and not (issecretvalue and issecretvalue(ohSpeed))) and ohSpeed or 0
    _swingDebug.rangedSpeed = (rSpeed and not (issecretvalue and issecretvalue(rSpeed))) and rSpeed or 0
    _swingDebug.mainShown = (mhBar and mhBar:IsShown()) or false
    _swingDebug.offShown = (ohBar and ohBar:IsShown()) or false
    _swingDebug.rangedShown = (rBar and rBar:IsShown()) or false
    return _swingDebug
end

sfui.swing.GetDebugInfo = sfui.swing_debug_info

if sfui.RegisterModule then
    sfui.RegisterModule("swing", sfui.swing)
end
