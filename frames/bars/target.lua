local addonName, addon = ...
sfui = sfui or {}
sfui.target = sfui.target or {}

local g      = sfui.config
local common = sfui.common
local cfg    = (g and g.targetBar) or {}

-- ─── Client Gate ─────────────────────────────────────────────────────────────
-- Per requirement: Camelot / Classic only, do not load or execute on Retail
if not (sfui.isCamelot or sfui.isForever or sfui.isClassic or (sfui.compat and (sfui.compat.is_camelot or sfui.compat.is_wow_forever or sfui.compat.is_classic))) then
    return
end

-- ─── Localized Globals ───────────────────────────────────────────────────────
local CreateFrame                  = _G.CreateFrame
local UIParent                     = _G.UIParent
local InCombatLockdown             = _G.InCombatLockdown
local UnitExists                   = _G.UnitExists
local UnitIsDeadOrGhost            = _G.UnitIsDeadOrGhost
local UnitIsConnected              = _G.UnitIsConnected
local UnitHealth                   = _G.UnitHealth
local UnitHealthMax                = _G.UnitHealthMax
local UnitPower                    = _G.UnitPower
local UnitPowerMax                 = _G.UnitPowerMax
local UnitPowerType                = _G.UnitPowerType
local UnitName                     = _G.UnitName
local UnitLevel                    = _G.UnitLevel
local UnitIsPlayer                 = _G.UnitIsPlayer
local UnitClass                    = _G.UnitClass
local UnitReaction                 = _G.UnitReaction
local UnitCanAttack                = _G.UnitCanAttack
local UnitIsTapDenied              = _G.UnitIsTapDenied
local UnitPlayerControlled         = _G.UnitPlayerControlled
local UnitGetIncomingHeals         = _G.UnitGetIncomingHeals
local UnitGetTotalAbsorbs          = _G.UnitGetTotalAbsorbs
local GetCreatureDifficultyColor   = _G.GetCreatureDifficultyColor
local PowerBarColor                = _G.PowerBarColor
local RAID_CLASS_COLORS            = _G.RAID_CLASS_COLORS
local IsShiftKeyDown               = _G.IsShiftKeyDown
local type                         = _G.type
local tonumber                     = _G.tonumber
local tostring                     = _G.tostring
local math_floor                   = math.floor
local UnitIsFriend                 = _G.UnitIsFriend
local UnitIsUnit                   = _G.UnitIsUnit
local UnitClassification           = _G.UnitClassification
local GetRaidTargetIndex           = _G.GetRaidTargetIndex
local SetRaidTargetIconTexture     = _G.SetRaidTargetIconTexture
local GameTooltip                  = _G.GameTooltip
local issecretvalue                = common.issecretvalue
local GetUnitName                  = _G.GetUnitName
local NameUtil                     = _G.NameUtil
local C_Spell                      = _G.C_Spell
local GetSpellInfo                 = _G.GetSpellInfo

-- ─── Secure Unit Watch Helpers ───────────────────────────────────────────────
local function SafeRegisterUnitWatch(frame)
    if not frame then return end
    if _G.RegisterUnitWatch then
        _G.RegisterUnitWatch(frame)
    elseif _G.RegisterStateDriver then
        _G.RegisterStateDriver(frame, "visibility", "[@target,exists] show; hide")
    end
end

local function SafeUnregisterUnitWatch(frame)
    if not frame then return end
    if _G.UnregisterUnitWatch then
        _G.UnregisterUnitWatch(frame)
    end
    if _G.UnregisterStateDriver then
        _G.UnregisterStateDriver(frame, "visibility")
    end
end

local function IsUnitWatchRegistered(frame)
    if not frame then return false end
    if _G.UnitWatchRegistered then
        return _G.UnitWatchRegistered(frame)
    end
    return false
end

-- ─── Module Frame Storage ────────────────────────────────────────────────────
local targetContainer
local healthBar
local healPredBar
local absorbBar
local powerBar
local nameText
local levelFrame
local levelText
local skullIcon
local hpText
local raidTargetIcon
local questIcon
local buffContainer
local debuffContainer

-- ─── Forward Declarations ────────────────────────────────────────────────────
local ApplyTargetPosition
local InvalidateTargetCaches
local UpdateTargetLevel
local ApplyTargetStyle

-- ─── Primary Texture Resolver ────────────────────────────────────────────────
local function GetBarTexture()
    local tex = sfui.widgets and sfui.widgets.get_bar_texture and sfui.widgets.get_bar_texture()
    if not tex or tex == "" then
        local textureName = SfuiDB and SfuiDB.barTexture
        local LSM = _G.LibStub and _G.LibStub("LibSharedMedia-3.0", true)
        if LSM and textureName then
            tex = LSM:Fetch("statusbar", textureName, true)
        end
    end
    if not tex or tex == "" then
        tex = (sfui.config and sfui.config.barTexture) or "Interface\\Buttons\\WHITE8X8"
    end
    return tex
end

function sfui.target.SetBarTexture(texturePath)
    if not texturePath or texturePath == "" then
        texturePath = GetBarTexture()
    end
    if healthBar and healthBar.SetStatusBarTexture then
        healthBar:SetStatusBarTexture(texturePath)
    end
    if powerBar and powerBar.SetStatusBarTexture then
        powerBar:SetStatusBarTexture(texturePath)
    end
    if healPredBar and healPredBar.SetStatusBarTexture then
        healPredBar:SetStatusBarTexture(texturePath)
    end
    if absorbBar and absorbBar.SetStatusBarTexture then
        absorbBar:SetStatusBarTexture(texturePath)
    end
end

-- ─── Font Path Resolver ───────────────────────────────────────────────────────
local function GetFontPath()
    local f = sfui.config and sfui.config.fontFile
    if f and f ~= "" and f ~= "GameFontNormal" then
        return f
    end
    if _G.GameFontNormal and _G.GameFontNormal.GetFont then
        local blizzFont = _G.GameFontNormal:GetFont()
        if blizzFont and blizzFont ~= "" and blizzFont ~= "GameFontNormal" then
            return blizzFont
        end
    end
    return "Fonts\\FRIZQT__.TTF"
end

-- ─── Health Color Resolver ───────────────────────────────────────────────────
local cachedHealthR, cachedHealthG, cachedHealthB

local function InvalidateHealthColorCache()
    cachedHealthR, cachedHealthG, cachedHealthB = nil, nil, nil
end

local function GetTargetHealthColor()
    if cachedHealthR then
        return cachedHealthR, cachedHealthG, cachedHealthB
    end

    if not UnitIsConnected("target") then
        cachedHealthR, cachedHealthG, cachedHealthB = 0.50, 0.50, 0.50
        return 0.50, 0.50, 0.50
    end
    if UnitIsPlayer("target") then
        local _, class = UnitClass("target")
        if class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
            local c = RAID_CLASS_COLORS[class]
            cachedHealthR, cachedHealthG, cachedHealthB = c.r, c.g, c.b
            return c.r, c.g, c.b
        end
    end
    local isTapDenied = UnitIsTapDenied("target")
    local isPlayerControlled = UnitPlayerControlled("target")
    if not issecretvalue(isTapDenied) and not issecretvalue(isPlayerControlled) and isTapDenied and not isPlayerControlled then
        cachedHealthR, cachedHealthG, cachedHealthB = 0.55, 0.55, 0.55
        return 0.55, 0.55, 0.55
    end
    local reaction = UnitReaction("target", "player")
    if reaction and not issecretvalue(reaction) then
        if reaction <= 2 then
            cachedHealthR, cachedHealthG, cachedHealthB = 0.85, 0.22, 0.22 -- Hostile Red
        elseif reaction <= 4 then
            cachedHealthR, cachedHealthG, cachedHealthB = 0.90, 0.72, 0.15 -- Neutral Amber / Yellow
        else
            cachedHealthR, cachedHealthG, cachedHealthB = 0.20, 0.75, 0.25 -- Friendly Green
        end
        return cachedHealthR, cachedHealthG, cachedHealthB
    end
    cachedHealthR, cachedHealthG, cachedHealthB = 0.85, 0.22, 0.22
    return 0.85, 0.22, 0.22
end

-- ─── Blizzard TargetFrame Clean Suppression ──────────────────────────────────
local function SuppressBlizzardTargetFrame()
    if SfuiDB and SfuiDB.enableTargetBar == false then return end
    local tf = _G.TargetFrame
    if not tf then return end
    tf:SetAlpha(0)
    if tf.EnableMouse and not InCombatLockdown() then
        tf:EnableMouse(false)
    end
    if not InCombatLockdown() and tf:IsShown() then
        tf:Hide()
    end
end

local function HookBlizzardTargetFrame()
    local tf = _G.TargetFrame
    if not tf or tf._sfuiTargetHooked then return end
    tf._sfuiTargetHooked = true
    if tf.HookScript then
        tf:HookScript("OnShow", SuppressBlizzardTargetFrame)
    end
    SuppressBlizzardTargetFrame()
end

-- ─── Native AuraContainer Button Initializers ────────────────────────────────
local function InitializeBuffButton(frame)
    local size = (cfg.auras and cfg.auras.size) or 18
    frame:SetSize(size, size)

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.15, 0.15, 0.15, 0.9)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame:SetIcon(icon)

    local count = frame:CreateFontString(nil, "OVERLAY")
    count:SetFont(GetFontPath(), 9, "OUTLINE")
    count:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    count:SetTextColor(1, 1, 1, 1)
    frame:SetApplicationCount(count)

    local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cd:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    cd:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    cd:SetReverse(true)
    cd:SetHideCountdownNumbers(true)
    frame:SetDurationCooldown(cd)
end

local function InitializeDebuffButton(frame)
    local size = (cfg.auras and cfg.auras.size) or 18
    frame:SetSize(size, size)

    local border = frame:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetTexture("Interface\\Buttons\\WHITE8X8")

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame:SetIcon(icon)

    local count = frame:CreateFontString(nil, "OVERLAY")
    count:SetFont(GetFontPath(), 9, "OUTLINE")
    count:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    count:SetTextColor(1, 1, 1, 1)
    frame:SetApplicationCount(count)

    local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cd:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    cd:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    cd:SetReverse(true)
    cd:SetHideCountdownNumbers(true)
    frame:SetDurationCooldown(cd)

    local dispelStyle = (_G.Enum and _G.Enum.CustomAuraButtonDispelTypeTextureStyle and _G.Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset) or 3
    frame:AddDispelTypeTexture(border, {
        showWhenHarmful = true,
        showWithoutDispelType = true,
        style = dispelStyle,
    })
end

-- ─── Frame Factory Helper (Clean Bar Matching bars.lua) ───────────────────────
local function CreateCleanBar(name, parent, width, height, padding, bgColor)
    local backdrop = CreateFrame("Frame", name .. "_Backdrop", parent, "BackdropTemplate")
    backdrop:SetSize(width + padding * 2, height + padding * 2)
    backdrop:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        tile     = true,
        tileSize = 32,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    backdrop:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.5)
    backdrop:SetBackdropBorderColor(0, 0, 0, 1)

    local bar = CreateFrame("StatusBar", name, backdrop)
    bar:SetPoint("TOPLEFT", backdrop, "TOPLEFT", padding, -padding)
    bar:SetPoint("BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", -padding, padding)
    bar:SetStatusBarTexture(GetBarTexture())
    bar.backdrop = backdrop

    return bar
end

-- ─── Target Frame Theming (Camelot Nameplate Bezel vs Modern Minimalist Clean) ─
ApplyTargetStyle = function(hBar, lFrame)
    if InCombatLockdown and InCombatLockdown() then return end
    hBar = hBar or healthBar
    lFrame = lFrame or levelFrame
    if not hBar or not hBar.backdrop then return end

    local isCamelot = sfui.theme and sfui.theme.IsCamelotActive and sfui.theme.IsCamelotActive()
    local hasNameplateAtlas = sfui.theme and sfui.theme.HasAtlas and sfui.theme.HasAtlas("UI-HUD-CoolDownManager-Selected-yellow")
    local useCamelotArtwork = isCamelot and hasNameplateAtlas

    local bd = hBar.backdrop
    local pal = (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()) or (sfui.config and sfui.config.appearance) or {}
    local bgCol = pal.backdropColor or { 0.05, 0.05, 0.05, 0.85 }
    local bdCol = pal.borderColor or { 0, 0, 0, 1 }

    if useCamelotArtwork then
        -- ═════════════════════════════════════════════════════════════════════
        -- CAMELOT THEME: Authentic Heavy Bronze Nameplate Bezel & Badge
        -- ═════════════════════════════════════════════════════════════════════
        -- 1. Nameplate Bevel Background Texture
        if not bd.nameplateBG then
            bd.nameplateBG = bd:CreateTexture(nil, "BACKGROUND", nil, -5)
        end
        bd.nameplateBG:SetAtlas("UI-HUD-CoolDownManager-Bar-BG", false)
        bd.nameplateBG:ClearAllPoints()
        bd.nameplateBG:SetPoint("TOPLEFT", bd, "TOPLEFT", -2, 3)
        bd.nameplateBG:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", 6, -6)
        bd.nameplateBG:Show()

        -- 2. Nameplate Golden Selected Bezel Border
        if not bd.nameplateBorder then
            bd.nameplateBorder = bd:CreateTexture(nil, "OVERLAY", nil, 4)
        end
        bd.nameplateBorder:SetAtlas("UI-HUD-CoolDownManager-Selected-yellow", false)
        bd.nameplateBorder:ClearAllPoints()
        -- Offsets from Blizzard NamePlateConstants.SELECTED_BORDER_OFFSETS: topLeftX = -3, topLeftY = 2, bottomRightX = 0, bottomRightY = 2
        bd.nameplateBorder:SetPoint("TOPLEFT", bd.nameplateBG, "TOPLEFT", -3, 2)
        bd.nameplateBorder:SetPoint("BOTTOMRIGHT", bd.nameplateBG, "BOTTOMRIGHT", 0, 2)
        bd.nameplateBorder:Show()

        -- Suppress standard flat backdrop border when nameplate border is shown
        if bd.SetBackdropBorderColor then
            bd:SetBackdropBorderColor(0, 0, 0, 0)
        end

        -- 3. Dedicated Level Frame Badge (Top-Right, no borders or backdrop)
        if lFrame then
            lFrame:Show()
            lFrame:ClearAllPoints()
            lFrame:SetPoint("BOTTOMRIGHT", bd, "TOPRIGHT", 0, 4)
            lFrame:SetSize(32, 14)

            -- Hide Camelot atlas textures (no borders, no backdrop)
            if lFrame.bg then lFrame.bg:Hide() end
            if lFrame.border then lFrame.border:Hide() end

            -- Remove any frame backdrop
            if lFrame.SetBackdrop then
                lFrame:SetBackdrop(nil)
            end
            if lFrame.SetBackdropColor then
                lFrame:SetBackdropColor(0, 0, 0, 0)
            end
            if lFrame.SetBackdropBorderColor then
                lFrame:SetBackdropBorderColor(0, 0, 0, 0)
            end

            -- Align level text & skull to the right
            if levelText then
                levelText:ClearAllPoints()
                levelText:SetPoint("RIGHT", lFrame, "RIGHT", 0, 0)
                levelText:SetJustifyH("RIGHT")
            end
            if skullIcon then
                skullIcon:ClearAllPoints()
                skullIcon:SetPoint("RIGHT", lFrame, "RIGHT", 0, 0)
            end
        end
    else
        -- ═════════════════════════════════════════════════════════════════════
        -- MODERN MINIMALIST: Clean Flat Bars Matching bars.lua (bar0)
        -- ═════════════════════════════════════════════════════════════════════
        -- Hide all Camelot nameplate artwork
        if bd.nameplateBG then bd.nameplateBG:Hide() end
        if bd.nameplateBorder then bd.nameplateBorder:Hide() end
        if lFrame and lFrame.border then lFrame.border:Hide() end
        if lFrame and lFrame.bg then lFrame.bg:Hide() end

        -- Apply crisp 1px solid black border & dark slate backdrop (identical to bars.lua)
        if bd.SetBackdrop then
            bd:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
                insets   = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            bd:SetBackdropColor(bgCol[1], bgCol[2], bgCol[3], bgCol[4] or 0.85)
            bd:SetBackdropBorderColor(bdCol[1], bdCol[2], bdCol[3], bdCol[4] or 1)
        end

        -- Clean flat level badge matching the healthbar style
        if lFrame then
            lFrame:ClearAllPoints()
            lFrame:SetPoint("LEFT", bd, "RIGHT", 2, 0)
            local barH = (SfuiDB and SfuiDB.targetBar_height) or (sfui.config and sfui.config.targetBar and sfui.config.targetBar.height) or 13
            local pad = (sfui.config and sfui.config.targetBar and sfui.config.targetBar.backdrop and sfui.config.targetBar.backdrop.padding) or 1
            lFrame:SetSize(24, barH + pad * 2)

            if lFrame.SetBackdrop then
                lFrame:SetBackdrop({
                    bgFile   = "Interface\\Buttons\\WHITE8X8",
                    edgeFile = "Interface\\Buttons\\WHITE8X8",
                    edgeSize = 1,
                    insets   = { left = 0, right = 0, top = 0, bottom = 0 },
                })
                lFrame:SetBackdropColor(bgCol[1], bgCol[2], bgCol[3], bgCol[4] or 0.85)
                lFrame:SetBackdropBorderColor(bdCol[1], bdCol[2], bdCol[3], bdCol[4] or 1)
            end

            if levelText then
                levelText:ClearAllPoints()
                levelText:SetPoint("CENTER", lFrame, "CENTER", 0, 0)
                levelText:SetJustifyH("CENTER")
            end
            if skullIcon then
                skullIcon:ClearAllPoints()
                skullIcon:SetPoint("CENTER", lFrame, "CENTER", 0, 0)
            end
        end
    end

    -- Style the power bar backdrop to match
    if powerBar and powerBar.backdrop and powerBar.backdrop.SetBackdrop then
        powerBar.backdrop:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets   = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        powerBar.backdrop:SetBackdropColor(bgCol[1], bgCol[2], bgCol[3], bgCol[4] or 0.85)
        powerBar.backdrop:SetBackdropBorderColor(bdCol[1], bdCol[2], bdCol[3], bdCol[4] or 1)
    end

    -- Ensure health bar is centered horizontally inside container
    if hBar and hBar.backdrop and targetContainer then
        hBar.backdrop:ClearAllPoints()
        hBar.backdrop:SetPoint("TOP", targetContainer, "TOP", 0, -22)
    end

    -- Symmetrical container width matching health bar backdrop
    if targetContainer and not (_G.InCombatLockdown and _G.InCombatLockdown()) then
        local barW = (SfuiDB and SfuiDB.targetBar_width) or (sfui.config and sfui.config.targetBar and sfui.config.targetBar.width) or 230
        local pad = (sfui.config and sfui.config.targetBar and sfui.config.targetBar.backdrop and sfui.config.targetBar.backdrop.padding) or 1
        targetContainer:SetWidth(barW + pad * 2)
    end

    -- Re-apply current bar texture (e.g. Flat for Modern, Blizzard Nameplate for Camelot)
    sfui.target.SetBarTexture()

    -- Refresh level display so skull icon / text updates
    if UpdateTargetLevel then
        UpdateTargetLevel()
    end
end

-- ─── Player Health Bar Anchor Helper ─────────────────────────────────────────
local cachedPlayerHealthBar
local function GetPlayerHealthBar()
    if cachedPlayerHealthBar then return cachedPlayerHealthBar end
    local bar = sfui.bars.get_bar0()
    if bar and bar.backdrop then
        cachedPlayerHealthBar = bar.backdrop
        return bar.backdrop
    end
    local bar0 = _G.sfui_bar0_Backdrop or _G.sfui_bar0
    cachedPlayerHealthBar = bar0
    return bar0
end

ApplyTargetPosition = function()
    if not targetContainer or InCombatLockdown() then return end
    targetContainer:ClearAllPoints()

    local savedPos = SfuiDB and SfuiDB.targetBar_pos

    if savedPos and savedPos.isCustom and savedPos.point == "TOP" and savedPos.x and savedPos.y then
        targetContainer:SetPoint("TOP", UIParent, "TOP", savedPos.x, savedPos.y)
    else
        local tCfg = (sfui.config and sfui.config.targetBar) or cfg
        local pos = (tCfg and tCfg.pos) or { point = "TOP", x = 0, y = -35 }
        targetContainer:SetPoint("TOP", UIParent, "TOP", pos.x or 0, pos.y or -35)
    end
end

-- ─── Layout Anchoring ────────────────────────────────────────────────────────
local lastLayoutPowerShown = nil
local function UpdateLayoutAnchors(force)
    if not healthBar or not healthBar.backdrop then return end

    local isPowerShown = powerBar and powerBar.backdrop and powerBar.backdrop:IsShown()
    if not force and isPowerShown == lastLayoutPowerShown then return end
    lastLayoutPowerShown = isPowerShown

    local lastAnchor = healthBar.backdrop

    if isPowerShown then
        powerBar.backdrop:ClearAllPoints()
        powerBar.backdrop:SetPoint("TOPLEFT", lastAnchor, "BOTTOMLEFT", 0, -2)
        powerBar.backdrop:SetPoint("TOPRIGHT", lastAnchor, "BOTTOMRIGHT", 0, -2)
        lastAnchor = powerBar.backdrop
    end

    if buffContainer then
        buffContainer:ClearAllPoints()
        buffContainer:SetPoint("TOPLEFT", lastAnchor, "BOTTOMLEFT", 0, -5)
    end
    if debuffContainer then
        debuffContainer:ClearAllPoints()
        debuffContainer:SetPoint("TOPRIGHT", lastAnchor, "BOTTOMRIGHT", 0, -5)
    end
end

-- ─── Aura Row Refresh ────────────────────────────────────────────────────────
local function UpdateAuras()
    if buffContainer then
        buffContainer:UpdateAllAuras()
    end
    if debuffContainer then
        debuffContainer:UpdateAllAuras()
    end
end

-- ─── Target Classification & Level Cache ─────────────────────────────────────
local cachedLvlPrefix
local lastPctFormatted, lastDeadOrGhost, lastConnected
local lastHealthVal, lastHealthMaxVal
local lastBarR, lastBarG, lastBarB
local lastAbsorbAnchor

local function InvalidateTargetLevelCache()
    cachedLvlPrefix = nil
    lastPctFormatted = nil
    lastDeadOrGhost = nil
    lastConnected = nil
    lastHealthVal = nil
    lastHealthMaxVal = nil
end

local function GetTargetLvlPrefix()
    if cachedLvlPrefix then return cachedLvlPrefix end

    local classTag = ""
    if UnitClassification then
        local c = UnitClassification("target")
        if c == "worldboss" then
            classTag = " |cffff2222[Boss]|r"
        elseif c == "rareelite" then
            classTag = " |cffffcc00[Rare+]|r"
        elseif c == "elite" then
            classTag = " |cffffcc00+|r"
        elseif c == "rare" then
            classTag = " |cffcccccc[Rare]|r"
        end
    end

    local lvl = UnitLevel("target")
    local isLvlSecret = issecretvalue(lvl)
    if not lvl or isLvlSecret or (type(lvl) == "number" and lvl <= 0) then
        cachedLvlPrefix = "|cffff3333??|r" .. classTag
    else
        local diff = GetCreatureDifficultyColor and GetCreatureDifficultyColor(lvl)
        local diffColor = diff and string.format("|cff%02x%02x%02x", diff.r * 255, diff.g * 255, diff.b * 255) or ""
        cachedLvlPrefix = diffColor .. tostring(lvl) .. "|r" .. classTag
    end
    return cachedLvlPrefix
end

-- ─── Unit Data Refresh (Matching bars.lua HealthBar Logic) ────────────────────
local function UpdateTargetHealth()
    if not healthBar or not UnitExists("target") then return end

    local curHp = UnitHealth("target")
    local maxHp = UnitHealthMax("target")
    if not curHp or not maxHp then return end

    local isSecret = issecretvalue(curHp) or issecretvalue(maxHp)
    if not isSecret and (type(maxHp) == "number" and maxHp <= 0) then return end

    healthBar:SetMinMaxValues(0, maxHp)
    healthBar:SetValue(curHp)

    local r, g, b = GetTargetHealthColor()
    if r ~= lastBarR or g ~= lastBarG or b ~= lastBarB then
        lastBarR, lastBarG, lastBarB = r, g, b
        healthBar:SetStatusBarColor(r, g, b)
    end

    local width, height = healthBar:GetSize()

    -- Incoming Heals Prediction Bar (Identical to bars.lua lines 518-527)
    if healPredBar then
        healPredBar:SetSize(width, height)
        healPredBar:SetMinMaxValues(0, maxHp)
        healPredBar:ClearAllPoints()
        healPredBar:SetPoint("TOPLEFT", healthBar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        local incomingHeals = (UnitGetIncomingHeals and UnitGetIncomingHeals("target")) or 0
        healPredBar:SetValue(incomingHeals)
    end

    -- Absorbs Bar (Identical to bars.lua lines 528-536)
    if absorbBar then
        local anchor = (healPredBar and healPredBar:GetStatusBarTexture()) or healthBar:GetStatusBarTexture()
        absorbBar:SetSize(width, height)
        absorbBar:SetMinMaxValues(0, maxHp)
        absorbBar:ClearAllPoints()
        absorbBar:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 0, 0)
        local absorbAmount = (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs("target")) or 0
        absorbBar:SetValue(absorbAmount)
        local absorbColor = SfuiDB and SfuiDB.absorbBarColor or (sfui.config and sfui.config.healthBar and sfui.config.healthBar.absorbBarColor)
        if absorbColor then
            absorbBar:SetStatusBarColor(common.unpack_color(absorbColor))
        else
            absorbBar:SetStatusBarColor(0.85, 0.80, 0.65, 0.70)
        end
    end

    -- Target Status & Health Text
    if hpText then
        if UnitIsDeadOrGhost("target") then
            hpText:SetText("|cffff3333Dead|r")
        elseif not UnitIsConnected("target") then
            hpText:SetText("|cff888888Offline|r")
        else
            local pctFormatted
            if not isSecret then
                local cur = type(curHp) == "number" and curHp or tonumber(curHp)
                local max = type(maxHp) == "number" and maxHp or tonumber(maxHp)
                if cur and max and max > 0 then
                    pctFormatted = math_floor((cur / max) * 100 + 0.5)
                end
            end
            if pctFormatted then
                hpText:SetFormattedText("%d%%", pctFormatted)
            else
                hpText:SetText("")
            end
        end
    end
end

UpdateTargetLevel = function()
    if not levelFrame or not UnitExists("target") then return end

    local lvl = UnitLevel("target")
    local isLvlSecret = issecretvalue(lvl)
    local classification = UnitClassification and UnitClassification("target")

    local isCamelot = sfui.theme and sfui.theme.IsCamelotActive and sfui.theme.IsCamelotActive()
    local hasNameplateAtlas = sfui.theme and sfui.theme.HasAtlas and sfui.theme.HasAtlas("ui-hud-nameplates-levelindicator-skull")
    local useCamelotSkull = isCamelot and hasNameplateAtlas

    if isLvlSecret or not lvl or (type(lvl) == "number" and lvl <= 0) or classification == "worldboss" then
        if skullIcon then
            if useCamelotSkull then
                skullIcon:SetAtlas("ui-hud-nameplates-levelindicator-skull", false)
            else
                skullIcon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
            end
            skullIcon:Show()
            if levelText then levelText:SetText("") end
        else
            if levelText then
                levelText:SetText("|cffff3333??|r")
                levelText:SetTextColor(1, 0.2, 0.2)
            end
        end
    else
        if skullIcon then skullIcon:Hide() end
        if levelText then
            local diff = GetCreatureDifficultyColor and GetCreatureDifficultyColor(lvl)
            local r, g, b = (diff and diff.r) or 1, (diff and diff.g) or 1, (diff and diff.b) or 1
            local classTag = ""
            if classification == "elite" or classification == "rareelite" then
                classTag = "+"
            end
            levelText:SetFormattedText("%d%s", lvl, classTag)
            levelText:SetTextColor(r, g, b)
        end
    end
end

local lastPowerType, lastPowerToken

local function InvalidatePowerCache()
    lastPowerType = nil
    lastPowerToken = nil
end

local function UpdateTargetPower()
    if not powerBar or not powerBar.backdrop or not UnitExists("target") then return end

    local curPower = UnitPower("target")
    local maxPower = UnitPowerMax("target")
    if not curPower or not maxPower then return end

    local isPowerSecret = issecretvalue(curPower) or issecretvalue(maxPower)
    if not isPowerSecret and (type(maxPower) == "number" and maxPower <= 0) then
        if powerBar.backdrop:IsShown() then
            powerBar.backdrop:Hide()
            UpdateLayoutAnchors(false)
        end
        return
    end

    if not powerBar.backdrop:IsShown() then
        powerBar.backdrop:Show()
        UpdateLayoutAnchors(false)
    end

    powerBar:SetMinMaxValues(0, maxPower)
    powerBar:SetValue(curPower)

    local powerType, powerToken = UnitPowerType("target")
    if powerType ~= lastPowerType or powerToken ~= lastPowerToken then
        lastPowerType, lastPowerToken = powerType, powerToken
        local pColor = (powerToken and PowerBarColor and PowerBarColor[powerToken])
            or (powerType and PowerBarColor and PowerBarColor[powerType])

        if pColor then
            powerBar:SetStatusBarColor(pColor.r, pColor.g, pColor.b)
        else
            powerBar:SetStatusBarColor(0.20, 0.50, 0.90) -- Fallback Mana Blue
        end
    end
end

-- ─── Classification, Raid Target & Quest Indicators ─────────────────────────
local scanTooltip
local scanTooltipLines = {}
local lastQuestState = nil

local function IsTargetQuestObjective()
    if _G.UnitIsQuestBoss and _G.UnitIsQuestBoss("target") then
        return true
    end
    if _G.C_TooltipInfo and _G.C_TooltipInfo.GetUnit then
        local data = _G.C_TooltipInfo.GetUnit("target")
        if data and data.lines then
            for i = 1, #data.lines do
                local line = data.lines[i]
                if line.type == 8 or line.type == 17 then
                    return true
                end
                if line.leftText and not issecretvalue(line.leftText) and (line.leftText:find("%d+/%d+") or line.leftText:find("%d+%%")) then
                    return true
                end
            end
        end
        return false
    end
    if not scanTooltip then
        scanTooltip = CreateFrame("GameTooltip", "SfuiTargetScanTooltip", nil, "GameTooltipTemplate")
        scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    scanTooltip:ClearLines()
    scanTooltip:SetUnit("target")
    for i = 2, scanTooltip:NumLines() do
        local fs = scanTooltipLines[i]
        if not fs then
            fs = _G["SfuiTargetScanTooltipTextLeft" .. i]
            scanTooltipLines[i] = fs
        end
        local txt = fs and fs:GetText()
        if txt and not issecretvalue(txt) and (txt:find("%d+/%d+") or txt:find("%d+%%")) then
            return true
        end
    end
    return false
end

local function UpdateQuestIndicator()
    if not questIcon then return end
    if not UnitExists("target") or UnitIsPlayer("target") or UnitIsDeadOrGhost("target") then
        if lastQuestState ~= false then
            lastQuestState = false
            questIcon:Hide()
        end
        return
    end

    local isQuest = IsTargetQuestObjective()
    if isQuest ~= lastQuestState then
        lastQuestState = isQuest
        if isQuest then
            questIcon:Show()
        else
            questIcon:Hide()
        end
    end
end

local lastRaidIndex

local function UpdateRaidTargetMarker()
    if not raidTargetIcon then return end
    if not UnitExists("target") then
        if lastRaidIndex ~= nil then
            raidTargetIcon:Hide()
            lastRaidIndex = nil
        end
        return
    end
    local index = GetRaidTargetIndex and GetRaidTargetIndex("target")
    if issecretvalue(index) then return end
    if index ~= lastRaidIndex then
        lastRaidIndex = index
        if index and index >= 1 and index <= 8 then
            if SetRaidTargetIconTexture then
                SetRaidTargetIconTexture(raidTargetIcon, index)
            else
                local col = (index - 1) % 4
                local row = math_floor((index - 1) / 4)
                raidTargetIcon:SetTexCoord(col * 0.25, (col + 1) * 0.25, row * 0.25, (row + 1) * 0.25)
            end
            raidTargetIcon:Show()
        else
            raidTargetIcon:Hide()
        end
    end
end

-- ─── Range & Distance Check ──────────────────────────────────────────────────
local HARM_SPELLS_BY_CLASS = {
    WARRIOR = {
        57755, -- Heroic Throw (30yd)
        355,   -- Taunt (30yd / 5yd)
        3018,  -- Shoot (30yd)
        2764,  -- Throw (30yd)
        1715,  -- Hamstring (5yd melee)
        772,   -- Rend (5yd melee)
        78,    -- Heroic Strike (5yd melee)
        "Heroic Throw", "Taunt", "Shoot", "Throw", "Hamstring", "Rend", "Heroic Strike",
    },
    PALADIN = {
        20271,  -- Judgement (10-30yd)
        62124,  -- Hand of Reckoning (30yd)
        879,    -- Exorcism (30yd)
        20473,  -- Holy Shock (20-40yd)
        24275,  -- Hammer of Wrath (30yd)
        35395,  -- Crusader Strike (melee)
        "Judgement", "Hand of Reckoning", "Exorcism", "Holy Shock", "Hammer of Wrath", "Crusader Strike",
    },
    HUNTER = {
        75,     -- Auto Shot (35-40yd)
        3044,   -- Arcane Shot (35-40yd)
        1978,   -- Serpent Sting (35-40yd)
        193455, -- Cobra Shot (40yd)
        56641,  -- Steady Shot (40yd)
        2974,   -- Wing Clip (5yd melee)
        "Auto Shot", "Arcane Shot", "Serpent Sting", "Cobra Shot", "Steady Shot", "Wing Clip",
    },
    ROGUE = {
        3018,   -- Shoot (30yd)
        2764,   -- Throw (30yd)
        185763, -- Pistol Shot (20yd)
        36554,  -- Shadowstep (25yd)
        2094,   -- Blind (15yd)
        1752,   -- Sinister Strike (5yd melee)
        8676,   -- Ambush (5yd melee)
        1833,   -- Cheap Shot (5yd melee)
        "Shoot", "Throw", "Pistol Shot", "Shadowstep", "Blind", "Sinister Strike", "Ambush", "Cheap Shot",
    },
    PRIEST = {
        589,    -- Shadow Word: Pain (30-40yd)
        585,    -- Smite (30-40yd)
        5019,   -- Shoot (30yd)
        8092,   -- Mind Blast (30yd)
        "Shadow Word: Pain", "Smite", "Shoot", "Mind Blast",
    },
    DEATHKNIGHT = {
        45477,  -- Icy Touch (30yd)
        47541,  -- Death Coil (40yd)
        49576,  -- Death Grip (30yd)
        "Icy Touch", "Death Coil", "Death Grip",
    },
    SHAMAN = {
        403,    -- Lightning Bolt (30yd)
        8042,   -- Earth Shock (20yd)
        8044,   -- Flame Shock (20yd)
        188196, -- Lightning Bolt (modern ID)
        "Lightning Bolt", "Earth Shock", "Flame Shock",
    },
    MAGE = {
        133,    -- Fireball (35yd)
        116,    -- Frostbolt (30-40yd)
        5143,   -- Arcane Missiles (30-40yd)
        5019,   -- Shoot (30yd)
        "Fireball", "Frostbolt", "Arcane Missiles", "Shoot",
    },
    WARLOCK = {
        686,    -- Shadow Bolt (30-40yd)
        172,    -- Corruption (30-40yd)
        348,    -- Immolate (30yd)
        5019,   -- Shoot (30yd)
        "Shadow Bolt", "Corruption", "Immolate", "Shoot",
    },
    DRUID = {
        5176,   -- Wrath (30yd)
        8921,   -- Moonfire (30yd)
        6795,   -- Growl (30yd / 5-8yd)
        1822,   -- Rake (5yd melee)
        1082,   -- Claw (5yd melee)
        6807,   -- Maul (5yd melee)
        "Wrath", "Moonfire", "Growl", "Rake", "Claw", "Maul",
    },
    MONK = {
        117952, -- Crackling Jade Lightning (40yd)
        115546, -- Provoke (30yd)
        100780, -- Tiger Palm (melee)
        "Crackling Jade Lightning", "Provoke", "Tiger Palm",
    },
    DEMONHUNTER = {
        185123, -- Throw Glaive (30yd)
        185245, -- Torment (30yd)
        "Throw Glaive", "Torment",
    },
    EVOKER = {
        361469, -- Living Flame (25yd)
        356995, -- Disintegrate (25yd)
        362969, -- Azure Strike (25yd)
        "Living Flame", "Disintegrate", "Azure Strike",
    },
}

local HELP_SPELLS_BY_CLASS = {
    PALADIN = {
        635,    -- Holy Light (40yd)
        19750,  -- Flash of Light (40yd)
        19740,  -- Blessing of Might (30yd)
        20217,  -- Blessing of Kings (30yd)
        1044,   -- Blessing of Freedom (30yd)
        "Holy Light", "Flash of Light", "Blessing of Might", "Blessing of Kings", "Blessing of Freedom",
    },
    PRIEST = {
        2050,   -- Lesser Heal (40yd)
        2061,   -- Flash Heal (40yd)
        17,     -- Power Word: Shield (40yd)
        139,    -- Renew (40yd)
        2054,   -- Heal (40yd)
        "Lesser Heal", "Flash Heal", "Power Word: Shield", "Renew", "Heal",
    },
    DRUID = {
        5185,   -- Healing Touch (40yd)
        774,    -- Rejuvenation (40yd)
        8936,   -- Regrowth (40yd)
        1126,   -- Mark of the Wild (30yd)
        "Healing Touch", "Rejuvenation", "Regrowth", "Mark of the Wild",
    },
    SHAMAN = {
        331,    -- Healing Wave (40yd)
        8004,   -- Lesser Healing Wave (40yd)
        1064,   -- Chain Heal (40yd)
        "Healing Wave", "Lesser Healing Wave", "Chain Heal",
    },
    MAGE = {
        1459,   -- Arcane Intellect (30yd)
        475,    -- Remove Lesser Curse (30yd)
        130,    -- Slow Fall (40yd)
        "Arcane Intellect", "Remove Lesser Curse", "Slow Fall",
    },
    WARLOCK = {
        5697,   -- Unending Breath (30yd)
        20707,  -- Soulstone (40yd)
        "Unending Breath", "Soulstone",
    },
    DEATHKNIGHT = {
        47541,  -- Death Coil (40yd, friendly undead)
        61999,  -- Raise Ally (40yd)
        "Death Coil", "Raise Ally",
    },
    MONK = {
        116670, -- Vivify (40yd)
        115175, -- Soothing Mist (40yd)
        115450, -- Detox (40yd)
        "Vivify", "Soothing Mist", "Detox",
    },
    EVOKER = {
        361469, -- Living Flame (25yd)
        355913, -- Emerald Blossom (25yd)
        "Living Flame", "Emerald Blossom",
    },
    HUNTER = {
        34477,  -- Misdirection (100yd)
        "Misdirection",
    },
    ROGUE = {
        57934,  -- Tricks of the Trade (100yd)
        "Tricks of the Trade",
    },
    WARRIOR = {},
    DEMONHUNTER = {},
}

local cachedPlayerClass
local cachedHarmSpell
local cachedHelpSpell

local function ResetRangeSpellCache()
    cachedHarmSpell = nil
    cachedHelpSpell = nil
end

local function SafeIsSpellInRange(spell, unit)
    if not spell or not unit then return nil end
    if C_Spell and C_Spell.IsSpellInRange then
        local ok, inRange = pcall(C_Spell.IsSpellInRange, spell, unit)
        if ok and inRange ~= nil and not issecretvalue(inRange) then
            return inRange
        end
    elseif _G.IsSpellInRange then
        local spellName = spell
        if type(spell) == "number" then
            if C_Spell and C_Spell.GetSpellName then
                spellName = C_Spell.GetSpellName(spell) or spell
            elseif GetSpellInfo then
                spellName = GetSpellInfo(spell) or spell
            end
        end
        local ok, inRange = pcall(_G.IsSpellInRange, spellName, unit)
        if ok and inRange ~= nil and not issecretvalue(inRange) then
            if inRange == 1 then return true end
            if inRange == 0 then return false end
        end
    end
    return nil
end

local function IsTargetInRange()
    if not UnitExists("target") then return true end
    if UnitIsUnit("target", "player") then return true end
    if UnitIsDeadOrGhost("target") then return true end

    if not cachedPlayerClass then
        local _, class = UnitClass("player")
        cachedPlayerClass = class
    end

    local isFriend = UnitIsFriend("player", "target")

    if isFriend then
        -- Friendly Range Check
        if cachedHelpSpell then
            local inRange = SafeIsSpellInRange(cachedHelpSpell, "target")
            if inRange ~= nil then
                return inRange
            end
            cachedHelpSpell = nil
        end

        local helpList = cachedPlayerClass and HELP_SPELLS_BY_CLASS[cachedPlayerClass]
        if helpList then
            for i = 1, #helpList do
                local spell = helpList[i]
                local inRange = SafeIsSpellInRange(spell, "target")
                if inRange ~= nil then
                    cachedHelpSpell = spell
                    return inRange
                end
            end
        end

        -- If class has no friendly check spell or friendly target is not healable/buffable (e.g. NPC), default to in-range (no dim)
        return true
    else
        -- Hostile / Neutral Range Check
        if cachedHarmSpell then
            local inRange = SafeIsSpellInRange(cachedHarmSpell, "target")
            if inRange ~= nil then
                return inRange
            end
            cachedHarmSpell = nil
        end

        local harmList = cachedPlayerClass and HARM_SPELLS_BY_CLASS[cachedPlayerClass]
        if harmList then
            for i = 1, #harmList do
                local spell = harmList[i]
                local inRange = SafeIsSpellInRange(spell, "target")
                if inRange ~= nil then
                    cachedHarmSpell = spell
                    return inRange
                end
            end
        end

        -- If no hostile spell known or available, default to in-range (no dim)
        return true
    end
end

local lastTargetAlpha
local function UpdateTargetRange()
    if not targetContainer then return end
    if sfui.target.unlocked or not UnitExists("target") then
        if lastTargetAlpha ~= 1.0 then
            targetContainer:SetAlpha(1.0)
            lastTargetAlpha = 1.0
        end
        return
    end
    local inRange = IsTargetInRange()
    local targetAlpha = 1.0
    if not issecretvalue(inRange) and not inRange then
        targetAlpha = 0.55
    end
    if targetAlpha ~= lastTargetAlpha then
        targetContainer:SetAlpha(targetAlpha)
        lastTargetAlpha = targetAlpha
    end
end

local function GetTargetDisplayName()
    if not UnitExists("target") then return "" end

    local fullName
    if NameUtil and NameUtil.FormatUnitNameForDisplay then
        local displayName = NameUtil.FormatUnitNameForDisplay("target")
        if displayName and not issecretvalue(displayName) and displayName ~= "" then
            fullName = displayName
        end
    end

    if not fullName and GetUnitName then
        local displayName = GetUnitName("target", true)
        if displayName and not issecretvalue(displayName) and displayName ~= "" then
            fullName = displayName
        end
    end

    if not fullName then
        local name, surname = UnitName("target")
        if not name then return "" end
        if issecretvalue(name) then
            return name
        end
        if name == "" then return "" end

        if surname and not issecretvalue(surname) and surname ~= "" then
            local sep = (_G.Constants and _G.Constants.CharacterNameSeparatorConsts and _G.Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR) or " "
            fullName = name .. sep .. surname
        else
            fullName = name
        end
    end

    local c = UnitClassification and UnitClassification("target")
    if c == "rare" then
        fullName = fullName .. " |cffcccccc[Rare]|r"
    elseif c == "rareelite" then
        fullName = fullName .. " |cffffcc00[Rare+]|r"
    elseif c == "worldboss" then
        fullName = fullName .. " |cffff2222[Boss]|r"
    end

    return fullName
end

local lastDisplayName, lastTapDeniedState
local function UpdateTargetInfo()
    if not UnitExists("target") or not nameText then return end

    local name = GetTargetDisplayName()
    local isNameSecret = issecretvalue(name)
    if isNameSecret or name ~= lastDisplayName then
        nameText:SetText(name)
        lastDisplayName = not isNameSecret and name or nil
    end

    local isDenied = UnitIsTapDenied("target")
    local isPlayerControlled = UnitPlayerControlled("target")
    local isGrey = not issecretvalue(isDenied) and not issecretvalue(isPlayerControlled) and isDenied and not isPlayerControlled
    if isGrey ~= lastTapDeniedState then
        lastTapDeniedState = isGrey
        if isGrey then
            nameText:SetTextColor(0.55, 0.55, 0.55)
        else
            nameText:SetTextColor(1, 1, 1)
        end
    end
end

InvalidateTargetCaches = function()
    InvalidateHealthColorCache()
    InvalidateTargetLevelCache()
    InvalidatePowerCache()
    lastQuestState = nil
    lastRaidIndex = nil
    lastDisplayName = nil
    lastTapDeniedState = nil
    lastBarR, lastBarG, lastBarB = nil, nil, nil
    lastAbsorbAnchor = nil
end

local function UpdateAll(isTargetChange)
    if not targetContainer or sfui.target.unlocked then return end
    if not UnitExists("target") then
        return
    end

    if isTargetChange then
        InvalidateTargetCaches()
    end

    UpdateTargetInfo()
    UpdateTargetHealth()
    UpdateTargetLevel()
    UpdateTargetPower()
    UpdateRaidTargetMarker()
    UpdateQuestIndicator()
    UpdateTargetRange()
    UpdateAuras()
end

-- ─── Event Handlers ──────────────────────────────────────────────────────────
local function OnTargetUnitEvent(event, unit)
    if not targetContainer or not UnitExists("target") then return end

    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_HEAL_PREDICTION" or event == "UNIT_ABSORB_AMOUNT_CHANGED" then
        UpdateTargetHealth()
    elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
        UpdateTargetPower()
    elseif event == "UNIT_AURA" then
        UpdateAuras()
    elseif event == "UNIT_NAME_UPDATE" or event == "UNIT_LEVEL" or event == "UNIT_FACTION" or event == "UNIT_CLASSIFICATION_CHANGED" then
        if event == "UNIT_FACTION" then
            InvalidateHealthColorCache()
        end
        if event == "UNIT_LEVEL" or event == "UNIT_CLASSIFICATION_CHANGED" then
            InvalidateTargetLevelCache()
        end
        UpdateTargetInfo()
        UpdateTargetHealth()
        UpdateTargetLevel()
    end
end

local function OnPlayerTargetChanged()
    if UnitExists("target") then
        UpdateAll(true)
    end
end

local function OnPlayerEnteringWorld()
    cachedPlayerHealthBar = nil
    HookBlizzardTargetFrame()
    ApplyTargetPosition()
    if targetContainer and not (SfuiDB and SfuiDB.enableTargetBar == false) then
        if not IsUnitWatchRegistered(targetContainer) then
            SafeRegisterUnitWatch(targetContainer)
        end
    end
    if UnitExists("target") then
        UpdateAll(true)
    end
end

-- ─── Frame Construction ──────────────────────────────────────────────────────
local function CreateTargetFrame()
    if targetContainer then return targetContainer end

    local tCfg = (sfui.config and sfui.config.targetBar) or cfg
    local barW = (SfuiDB and SfuiDB.targetBar_width) or tCfg.width or 230
    if barW == 190 or barW == 200 or barW == 300 or barW == 400 then
        barW = 230
        if SfuiDB then SfuiDB.targetBar_width = 230 end
    end
    local barH = (SfuiDB and SfuiDB.targetBar_height) or tCfg.height or 13
    if barH == 12 or barH == 16 or barH == 20 then
        barH = 13
        if SfuiDB then SfuiDB.targetBar_height = 13 end
    end
    local pwrH = (SfuiDB and SfuiDB.targetBar_powerHeight) or tCfg.powerHeight or 3
    if pwrH == 5 then
        pwrH = 3
        if SfuiDB then SfuiDB.targetBar_powerHeight = 3 end
    end
    local pad  = (tCfg.backdrop and tCfg.backdrop.padding) or 1
    local bgCol = (tCfg.backdrop and tCfg.backdrop.color) or { 0, 0, 0, 0.5 }
    local barTex = GetBarTexture()

    -- 1. Main Secure Action Button Container
    -- Matches healthBar backdrop width exactly: barW + pad * 2
    local totalW = barW + pad * 2
    local f = CreateFrame("Button", "SfuiTargetFrame", UIParent, "SecureActionButtonTemplate")
    f:SetSize(totalW, barH + pwrH + 54)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)

    f:SetAttribute("unit", "target")
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")
    f:RegisterForClicks("AnyUp", "AnyDown")

    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        if IsShiftKeyDown() or sfui.target.unlocked then
            self:StartMoving()
            self.isMoving = true
        end
    end)
    f:SetScript("OnDragStop", function(self)
        if self.isMoving then
            self:StopMovingOrSizing()
            self.isMoving = false
            local cx = self:GetCenter()
            local top = self:GetTop()
            local uiWidth = UIParent:GetWidth()
            local uiTop = UIParent:GetTop()
            local x = (cx and uiWidth) and math_floor(cx - (uiWidth / 2) + 0.5) or 0
            local y = (top and uiTop) and math_floor(top - uiTop + 0.5) or -35
            -- Snap to exact center if dragged within 6 pixels of horizontal center
            if math.abs(x) <= 6 then
                x = 0
            end
            self:ClearAllPoints()
            self:SetPoint("TOP", UIParent, "TOP", x, y)
            SfuiDB = SfuiDB or {}
            SfuiDB.targetBar_pos = {
                point = "TOP",
                x = x,
                y = y,
                isCustom = true,
            }
        end
    end)

    targetContainer = f

    -- Migrate legacy coordinates to new center-top default
    if SfuiDB and SfuiDB.targetBar_pos then
        local p = SfuiDB.targetBar_pos
        if not p.isCustom or
           p.point ~= "TOP" or
           p.y == -200 or
           p.y == -100 or
           (p.x and math.abs(p.x) <= 20 and p.x ~= 0) then
            SfuiDB.targetBar_pos = nil
        end
    end

    ApplyTargetPosition()

    -- 2. Clean Health Bar (Centered horizontally inside container)
    healthBar = CreateCleanBar("SfuiTargetHealthBar", f, barW, barH, pad, bgCol)
    healthBar.backdrop:SetPoint("TOP", f, "TOP", 0, -22)

    -- Heal Prediction Bar (Identical logic to bars.lua)
    healPredBar = CreateFrame("StatusBar", nil, healthBar)
    healPredBar:SetFrameLevel(healthBar:GetFrameLevel() + 1)
    healPredBar:SetStatusBarTexture(barTex)
    healPredBar:SetStatusBarColor(0.0, 0.8, 0.6, 0.5)
    healPredBar:SetPoint("TOPLEFT", healthBar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    if healPredBar.GetStatusBarTexture then
        healPredBar:GetStatusBarTexture():SetBlendMode("ADD")
    end

    -- Absorb Bar (Identical logic to bars.lua)
    absorbBar = CreateFrame("StatusBar", nil, healthBar)
    absorbBar:SetFrameLevel(healthBar:GetFrameLevel() + 2)
    absorbBar:SetStatusBarTexture(barTex)
    if absorbBar.GetStatusBarTexture then
        absorbBar:GetStatusBarTexture():SetBlendMode("ADD")
    end

    -- 3. Dedicated Level Frame Badge
    levelFrame = CreateFrame("Button", "SfuiTargetLevelFrame", f, "SecureActionButtonTemplate,BackdropTemplate")
    levelFrame:SetSize(24, barH + pad * 2)
    levelFrame:SetPoint("LEFT", healthBar.backdrop, "RIGHT", 2, 0)
    levelFrame:SetAttribute("unit", "target")
    levelFrame:SetAttribute("*type1", "target")
    levelFrame:SetAttribute("*type2", "togglemenu")
    levelFrame:RegisterForClicks("AnyUp", "AnyDown")

    levelText = levelFrame:CreateFontString(nil, "OVERLAY", nil, 5)
    levelText:SetFont(GetFontPath(), 11, "OUTLINE")
    levelText:SetShadowOffset(1, -1)
    levelText:SetShadowColor(0, 0, 0, 0.8)
    levelText:SetPoint("CENTER", levelFrame, "CENTER", 0, 0)
    levelText:SetJustifyH("CENTER")
    levelText:SetTextColor(1, 1, 1)

    skullIcon = levelFrame:CreateTexture(nil, "OVERLAY", nil, 5)
    skullIcon:SetSize(14, 14)
    skullIcon:SetPoint("CENTER", levelFrame, "CENTER", 0, 0)
    if sfui.theme.HasAtlas("ui-hud-nameplates-levelindicator-skull") then
        skullIcon:SetAtlas("ui-hud-nameplates-levelindicator-skull", false)
    else
        skullIcon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
    end
    skullIcon:Hide()

    -- 4. Health Percentage Text (Inside Health Bar)
    hpText = healthBar:CreateFontString(nil, "OVERLAY", nil, 5)
    hpText:SetFont(GetFontPath(), 10, "OUTLINE")
    hpText:SetShadowOffset(1, -1)
    hpText:SetShadowColor(0, 0, 0, 0.8)
    hpText:SetPoint("CENTER", healthBar, "CENTER", 0, 0)
    hpText:SetJustifyH("CENTER")
    hpText:SetTextColor(1, 1, 1)

    -- 5. Target Name (Centered above health bar)
    nameText = f:CreateFontString(nil, "OVERLAY", nil, 2)
    nameText:SetFont(GetFontPath(), 11, "OUTLINE")
    nameText:SetShadowOffset(1, -1)
    nameText:SetShadowColor(0, 0, 0, 0.8)
    nameText:SetPoint("BOTTOM", healthBar.backdrop, "TOP", 0, 4)
    nameText:SetJustifyH("CENTER")
    nameText:SetWordWrap(false)
    nameText:SetTextColor(1, 1, 1)

    -- 6. Clean Power Bar (Underneath Health Bar)
    powerBar = CreateCleanBar("SfuiTargetPowerBar", f, barW, pwrH, pad, bgCol)
    powerBar.backdrop:SetPoint("TOPLEFT", healthBar.backdrop, "BOTTOMLEFT", 0, -2)
    powerBar.backdrop:SetPoint("TOPRIGHT", healthBar.backdrop, "BOTTOMRIGHT", 0, -2)

    -- 7. Raid Target Marker (Centered above target name)
    raidTargetIcon = f:CreateTexture(nil, "OVERLAY", nil, 7)
    raidTargetIcon:SetSize(16, 16)
    raidTargetIcon:SetPoint("BOTTOM", nameText, "TOP", 0, 2)
    raidTargetIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    raidTargetIcon:Hide()

    -- 8. Quest Mob Indicator (Left of centered target name)
    questIcon = f:CreateTexture(nil, "OVERLAY", nil, 6)
    questIcon:SetSize(14, 14)
    questIcon:SetTexture("Interface\\TargetingFrame\\PortraitQuestBadge")
    questIcon:SetPoint("RIGHT", nameText, "LEFT", -4, 0)
    questIcon:Hide()

    -- Apply theme styling (Clean flat bars for Modern Minimalist, Nameplate bezel for Camelot)
    ApplyTargetStyle(healthBar, levelFrame)

    -- 9. Aura Containers (Native AuraContainer - Positive & Negative Buckets)
    local auraCfg = cfg.auras or {}
    local spacing = auraCfg.spacing or 2
    local size = auraCfg.size or 18
    local maxBuffs = auraCfg.maxBuffs or 6
    local maxDebuffs = auraCfg.maxDebuffs or 6
    local flowDirRight = (_G.AnchorUtil and _G.AnchorUtil.FlowDirection and _G.AnchorUtil.FlowDirection.Right) or 1
    local flowDirLeft  = (_G.AnchorUtil and _G.AnchorUtil.FlowDirection and _G.AnchorUtil.FlowDirection.Left) or -1
    local flowDirDown  = (_G.AnchorUtil and _G.AnchorUtil.FlowDirection and _G.AnchorUtil.FlowDirection.Down) or -1

    buffContainer = CreateFrame("AuraContainer", "SfuiTargetBuffs", f, "CustomAuraContainerTemplate")
    buffContainer:SetUnit("target")
    buffContainer:SetFlowLayoutAnchorPoint("TOPLEFT")
    buffContainer:SetFlowLayoutGrowthDirection(flowDirRight, flowDirDown)
    buffContainer:AddAuraGroup("Buffs", "HELPFUL", {
        maxFrameCount = maxBuffs,
        initializeFrame = InitializeBuffButton,
        layout = {
            elementSpacing = spacing,
            lineSpacing = spacing,
            elementWidth = size,
            elementHeight = size,
        },
    })
    buffContainer:Show()

    debuffContainer = CreateFrame("AuraContainer", "SfuiTargetDebuffs", f, "CustomAuraContainerTemplate")
    debuffContainer:SetUnit("target")
    debuffContainer:SetFlowLayoutAnchorPoint("TOPRIGHT")
    debuffContainer:SetFlowLayoutGrowthDirection(flowDirLeft, flowDirDown)
    debuffContainer:AddAuraGroup("Debuffs", "HARMFUL", {
        maxFrameCount = maxDebuffs,
        initializeFrame = InitializeDebuffButton,
        layout = {
            elementSpacing = spacing,
            lineSpacing = spacing,
            elementWidth = size,
            elementHeight = size,
        },
    })
    debuffContainer:Show()

    -- 10. Range Ticker (Out-of-range alpha dimming)
    local rangeElapsed = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        rangeElapsed = rangeElapsed + elapsed
        if rangeElapsed >= 0.15 then
            rangeElapsed = 0
            UpdateTargetRange()
        end
    end)

    targetContainer = f

    if f.HookScript then
        f:HookScript("OnShow", function()
            UpdateAll(false)
        end)
    end

    if not (SfuiDB and SfuiDB.enableTargetBar == false) then
        SafeRegisterUnitWatch(targetContainer)
    else
        if not InCombatLockdown() then
            targetContainer:Hide()
        end
    end

    UpdateLayoutAnchors()

    -- Register health & power bars with the theme engine
    sfui.theme.RegisterBar(healthBar, "target")
    sfui.theme.RegisterBar(powerBar, "target")

    return f
end

-- ─── Public API ──────────────────────────────────────────────────────────────
function sfui.target.Unlock()
    if InCombatLockdown() then return end
    sfui.target.unlocked = true
    if targetContainer then
        SafeUnregisterUnitWatch(targetContainer)
        targetContainer:Show()
        nameText:SetText("|cff00ff00target bar (drag to move)|r")
        if hpText then hpText:SetText("70%") end
        if levelText then
            levelText:SetText("20")
            levelText:SetTextColor(1, 0.82, 0)
        end
        if skullIcon then skullIcon:Hide() end
        healthBar:SetMinMaxValues(0, 100)
        healthBar:SetValue(70)
        healthBar:SetStatusBarColor(0.85, 0.22, 0.22)
        powerBar.backdrop:Show()
        powerBar:SetMinMaxValues(0, 100)
        powerBar:SetValue(60)
        powerBar:SetStatusBarColor(0.20, 0.50, 0.90)
        UpdateLayoutAnchors()
    end
end

function sfui.target.Lock()
    if InCombatLockdown() then return end
    sfui.target.unlocked = false
    if targetContainer then
        if not (SfuiDB and SfuiDB.enableTargetBar == false) then
            SafeRegisterUnitWatch(targetContainer)
        else
            targetContainer:Hide()
        end
        if UnitExists("target") then
            UpdateAll(true)
        end
    end
end

function sfui.target.ToggleLock()
    if sfui.target.unlocked then
        sfui.target.Lock()
    else
        sfui.target.Unlock()
    end
end

function sfui.target.ResetPosition()
    if InCombatLockdown() then return end
    SfuiDB = SfuiDB or {}
    SfuiDB.targetBar_pos = nil
    ApplyTargetPosition()
end

function sfui.target.UpdateTheme()
    if healthBar and healthBar.backdrop then
        ApplyTargetStyle(healthBar, levelFrame)
    end
end

sfui.events.RegisterMessage("SFUI_THEME_CHANGED", function()
    sfui.target.UpdateTheme()
end)

function sfui.target.UpdateVisibility()
    if InCombatLockdown() then return end
    if SfuiDB and SfuiDB.enableTargetBar == false then
        if targetContainer then
            SafeUnregisterUnitWatch(targetContainer)
            targetContainer:Hide()
        end
        local tf = _G.TargetFrame
        if tf and not InCombatLockdown() then
            tf:SetAlpha(1)
            if tf.EnableMouse then tf:EnableMouse(true) end
            if UnitExists("target") then tf:Show() end
        end
    else
        if targetContainer then
            SafeRegisterUnitWatch(targetContainer)
            if UnitExists("target") then
                UpdateAll(true)
            end
        end
        SuppressBlizzardTargetFrame()
    end
end

-- ─── Initialization ──────────────────────────────────────────────────────────
local function Initialize()
    CreateTargetFrame()
    HookBlizzardTargetFrame()

    -- Register unit events with dispatcher
    sfui.events.RegisterUnitEvents(
        {
            "UNIT_HEALTH",
            "UNIT_MAXHEALTH",
            "UNIT_POWER_UPDATE",
            "UNIT_MAXPOWER",
            "UNIT_DISPLAYPOWER",
            "UNIT_AURA",
            "UNIT_NAME_UPDATE",
            "UNIT_LEVEL",
            "UNIT_FACTION",
            "UNIT_CLASSIFICATION_CHANGED",
            "UNIT_HEAL_PREDICTION",
            "UNIT_ABSORB_AMOUNT_CHANGED",
        },
        "target",
        OnTargetUnitEvent
    )

    -- Register global target change, combat, raid marker, and spell book events
    sfui.events.RegisterEvent("PLAYER_TARGET_CHANGED", OnPlayerTargetChanged)
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", OnPlayerEnteringWorld)
    sfui.events.RegisterEvent("RAID_TARGET_UPDATE", UpdateRaidTargetMarker)
    sfui.events.RegisterEvent("QUEST_LOG_UPDATE", UpdateQuestIndicator)
    sfui.events.RegisterEvent("SPELLS_CHANGED", ResetRangeSpellCache)
    sfui.events.RegisterEvent("LEARNED_SPELL_IN_TAB", ResetRangeSpellCache)

    if UnitExists("target") then
        UpdateAll(true)
    end
end

-- Defer initialization until PLAYER_LOGIN
sfui.events.RegisterEvent("PLAYER_LOGIN", Initialize)
