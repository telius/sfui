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
local issecretvalue                = (common and common.issecretvalue) or _G.issecretvalue or function() return false end
local GetUnitName                  = _G.GetUnitName
local NameUtil                     = _G.NameUtil
local C_Spell                      = _G.C_Spell
local GetSpellInfo                 = _G.GetSpellInfo
local CheckInteractDistance        = _G.CheckInteractDistance

-- ─── Module Frame Storage ────────────────────────────────────────────────────
local targetContainer
local healthBar
local healPredBar
local absorbBar
local powerBar
local nameText
local levelText
local raidTargetIcon
local questIcon
local buffContainer
local debuffContainer

-- ─── Forward Declarations ────────────────────────────────────────────────────
local ApplyTargetPosition
local InvalidateTargetCaches

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
        bgFile = "Interface\\Buttons\\WHITE8X8",
        tile = true,
        tileSize = 32,
    })
    backdrop:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.5)

    local bar = CreateFrame("StatusBar", name, backdrop)
    bar:SetSize(width, height)
    bar:SetPoint("CENTER")
    bar:SetStatusBarTexture(GetBarTexture())
    bar.backdrop = backdrop

    return bar
end

-- ─── Player Health Bar Anchor Helper ─────────────────────────────────────────
local cachedPlayerHealthBar
local function GetPlayerHealthBar()
    if cachedPlayerHealthBar then return cachedPlayerHealthBar end
    if sfui.bars and sfui.bars.get_bar0 then
        local bar = sfui.bars.get_bar0()
        if bar and bar.backdrop then
            cachedPlayerHealthBar = bar.backdrop
            return bar.backdrop
        end
    end
    local bar0 = _G.sfui_bar0_Backdrop or _G.sfui_bar0
    cachedPlayerHealthBar = bar0
    return bar0
end

ApplyTargetPosition = function()
    if not targetContainer then return end
    targetContainer:ClearAllPoints()

    local playerBar = GetPlayerHealthBar()
    local savedPos = SfuiDB and SfuiDB.targetBar_pos

    if savedPos and savedPos.isCustom and savedPos.point and savedPos.x and savedPos.y then
        targetContainer:SetPoint(savedPos.point, UIParent, savedPos.point, savedPos.x, savedPos.y)
    elseif playerBar then
        targetContainer:SetPoint("TOPLEFT", playerBar, "TOPRIGHT", 8, 18)
    else
        local pos = cfg.pos or { point = "CENTER", x = 160, y = 0 }
        targetContainer:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 160, pos.y or 0)
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
        buffContainer:SetPoint("TOPLEFT", lastAnchor, "BOTTOMLEFT", 0, -4)
    end
    if debuffContainer then
        debuffContainer:ClearAllPoints()
        debuffContainer:SetPoint("TOPRIGHT", lastAnchor, "BOTTOMRIGHT", 0, -4)
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
        if absorbColor and common and common.unpack_color then
            absorbBar:SetStatusBarColor(common.unpack_color(absorbColor))
        else
            absorbBar:SetStatusBarColor(0.85, 0.80, 0.65, 0.70)
        end
    end

    -- Target Status, Classification & Health Text
    if levelText then
        if UnitIsDeadOrGhost("target") then
            levelText:SetText("|cffff3333Dead|r")
        elseif not UnitIsConnected("target") then
            levelText:SetText("|cff888888Offline|r")
        else
            local prefix = GetTargetLvlPrefix()
            local pctFormatted
            if not isSecret then
                local cur = type(curHp) == "number" and curHp or tonumber(curHp)
                local max = type(maxHp) == "number" and maxHp or tonumber(maxHp)
                if cur and max and max > 0 then
                    pctFormatted = math_floor((cur / max) * 100 + 0.5)
                end
            end
            if pctFormatted then
                levelText:SetFormattedText("%s (%d%%)", prefix, pctFormatted)
            else
                levelText:SetText(prefix)
            end
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
    if not questIcon or not nameText or not healthBar or not healthBar.backdrop then return end
    if not UnitExists("target") or UnitIsPlayer("target") or UnitIsDeadOrGhost("target") then
        if lastQuestState ~= false then
            lastQuestState = false
            questIcon:Hide()
            nameText:ClearAllPoints()
            nameText:SetPoint("BOTTOMLEFT", healthBar.backdrop, "TOPLEFT", 0, 3)
            if levelText then
                nameText:SetPoint("RIGHT", levelText, "LEFT", -4, 0)
            end
        end
        return
    end

    local isQuest = IsTargetQuestObjective()
    if isQuest ~= lastQuestState then
        lastQuestState = isQuest
        if isQuest then
            questIcon:Show()
            nameText:ClearAllPoints()
            nameText:SetPoint("BOTTOMLEFT", questIcon, "BOTTOMRIGHT", 2, 0)
            if levelText then
                nameText:SetPoint("RIGHT", levelText, "LEFT", -4, 0)
            end
        else
            questIcon:Hide()
            nameText:ClearAllPoints()
            nameText:SetPoint("BOTTOMLEFT", healthBar.backdrop, "TOPLEFT", 0, 3)
            if levelText then
                nameText:SetPoint("RIGHT", levelText, "LEFT", -4, 0)
            end
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
local SPELLS_BY_CLASS = {
    WARRIOR     = { 100, 3018, 2764, "Charge", "Shoot", "Throw" },
    PALADIN     = { 20271, 635, 879, "Judgement", "Holy Shock", "Exorcism", "Holy Light" },
    HUNTER      = { 75, 3044, "Auto Shot", "Arcane Shot" },
    ROGUE       = { 3018, 2764, 1752, "Shoot", "Throw", "Sinister Strike" },
    PRIEST      = { 589, 585, 2050, "Shadow Word: Pain", "Smite", "Flash Heal" },
    DEATHKNIGHT = { 45477, 47541, "Icy Touch", "Death Coil" },
    SHAMAN      = { 403, 8042, 331, "Lightning Bolt", "Earth Shock", "Healing Wave" },
    MAGE        = { 133, 116, "Fireball", "Frostbolt" },
    WARLOCK     = { 686, "Shadow Bolt" },
    DRUID       = { 8921, 5176, 5185, "Moonfire", "Wrath", "Healing Touch" },
}

local cachedRangeSpell
local function ResetRangeSpellCache()
    cachedRangeSpell = nil
end

local function GetClassRangeSpell()
    if cachedRangeSpell ~= nil then
        return cachedRangeSpell or nil
    end
    local _, class = UnitClass("player")
    local list = class and SPELLS_BY_CLASS[class]
    if list then
        for i = 1, #list do
            local spell = list[i]
            if (C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spell)) or (GetSpellInfo and GetSpellInfo(spell)) then
                cachedRangeSpell = spell
                return spell
            end
        end
    end
    cachedRangeSpell = false
    return nil
end

local function IsTargetInRange()
    if not UnitExists("target") then return true end
    if UnitIsUnit("target", "player") then return true end

    -- Friendly Range
    if UnitIsFriend("player", "target") then
        if CheckInteractDistance then
            local inDist = CheckInteractDistance("target", 4)
            if not issecretvalue(inDist) then
                return inDist or false
            end
        end
        return false
    end

    -- Hostile Range via class spell
    local spell = GetClassRangeSpell()
    if spell then
        if C_Spell and C_Spell.IsSpellInRange then
            local inRange = C_Spell.IsSpellInRange(spell, "target")
            if inRange ~= nil and not issecretvalue(inRange) then
                return inRange
            end
        elseif _G.IsSpellInRange then
            local inRange = _G.IsSpellInRange(spell, "target")
            if not issecretvalue(inRange) then
                if inRange == 1 then return true end
                if inRange == 0 then return false end
            end
        end
    end

    -- Fallback: 28yd interact check
    if CheckInteractDistance then
        local inDist = CheckInteractDistance("target", 4)
        if not issecretvalue(inDist) then
            return inDist or false
        end
    end

    return true
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

    if NameUtil and NameUtil.FormatUnitNameForDisplay then
        local displayName = NameUtil.FormatUnitNameForDisplay("target")
        if displayName then
            if issecretvalue(displayName) then
                return displayName
            elseif displayName ~= "" then
                return displayName
            end
        end
    end

    if GetUnitName then
        local displayName = GetUnitName("target", true)
        if displayName then
            if issecretvalue(displayName) then
                return displayName
            elseif displayName ~= "" then
                return displayName
            end
        end
    end

    local name, surname = UnitName("target")
    if not name then return "" end
    if issecretvalue(name) then
        return name
    end
    if name == "" then return "" end

    if surname and not issecretvalue(surname) and surname ~= "" then
        local sep = (_G.Constants and _G.Constants.CharacterNameSeparatorConsts and _G.Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR) or " "
        return name .. sep .. surname
    end

    return name
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
    if not targetContainer then return end
    if not UnitExists("target") then
        if targetContainer:IsShown() then
            targetContainer:Hide()
        end
        return
    end

    if isTargetChange then
        InvalidateTargetCaches()
    end

    if not targetContainer:IsShown() then
        targetContainer:Show()
    end
    UpdateTargetInfo()
    UpdateTargetHealth()
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
    end
end

local function OnPlayerTargetChanged()
    UpdateAll(true)
end

local function OnPlayerEnteringWorld()
    cachedPlayerHealthBar = nil
    HookBlizzardTargetFrame()
    ApplyTargetPosition()
    UpdateAll(true)
end

-- ─── Frame Construction ──────────────────────────────────────────────────────
local function CreateTargetFrame()
    if targetContainer then return targetContainer end

    local barW = (SfuiDB and SfuiDB.targetBar_width) or cfg.width or 200
    if barW == 300 then
        barW = 200
        if SfuiDB then SfuiDB.targetBar_width = 200 end
    end
    local barH = (SfuiDB and SfuiDB.targetBar_height) or cfg.height or 20
    local pwrH = (SfuiDB and SfuiDB.targetBar_powerHeight) or cfg.powerHeight or 5
    local pad  = (cfg.backdrop and cfg.backdrop.padding) or 2
    local bgCol = (cfg.backdrop and cfg.backdrop.color) or { 0, 0, 0, 0.5 }
    local barTex = GetBarTexture()

    -- 1. Main Secure Action Button Container
    local f = CreateFrame("Button", "SfuiTargetFrame", UIParent, "SecureActionButtonTemplate")
    f:SetSize(barW + pad * 2, barH + pwrH + 48)
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
            local pt, _, _, x, y = self:GetPoint()
            SfuiDB = SfuiDB or {}
            SfuiDB.targetBar_pos = {
                point = pt or "CENTER",
                x = math_floor(x + 0.5),
                y = math_floor(y + 0.5),
                isCustom = true,
            }
        end
    end)

    targetContainer = f

    -- Migrate legacy coordinates from previous defaults
    if SfuiDB and SfuiDB.targetBar_pos and (SfuiDB.targetBar_pos.y == -200 or SfuiDB.targetBar_pos.y == -100 or not SfuiDB.targetBar_pos.isCustom) then
        SfuiDB.targetBar_pos = nil
    end

    ApplyTargetPosition()

    -- 2. Clean Health Bar (Matching bar0 in bars.lua)
    healthBar = CreateCleanBar("SfuiTargetHealthBar", f, barW, barH, pad, bgCol)
    healthBar.backdrop:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -18)

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

    -- 3. Level & Status Text (Top Right above bar)
    levelText = f:CreateFontString(nil, "OVERLAY", nil, 2)
    levelText:SetFont(GetFontPath(), 11, "")
    levelText:SetShadowOffset(0, 0)
    levelText:SetShadowColor(0, 0, 0, 0)
    levelText:SetPoint("BOTTOMRIGHT", healthBar.backdrop, "TOPRIGHT", 0, 3)
    levelText:SetTextColor(1, 1, 1)

    -- 4. Target Name (Top Left above bar, constrained to avoid overlapping level text)
    nameText = f:CreateFontString(nil, "OVERLAY", nil, 2)
    nameText:SetFont(GetFontPath(), 11, "")
    nameText:SetShadowOffset(0, 0)
    nameText:SetShadowColor(0, 0, 0, 0)
    nameText:SetPoint("BOTTOMLEFT", healthBar.backdrop, "TOPLEFT", 0, 3)
    nameText:SetPoint("RIGHT", levelText, "LEFT", -4, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    nameText:SetTextColor(1, 1, 1)

    -- 5. Clean Power Bar (Underneath Health Bar)
    powerBar = CreateCleanBar("SfuiTargetPowerBar", f, barW, pwrH, pad, bgCol)
    powerBar.backdrop:SetPoint("TOPLEFT", healthBar.backdrop, "BOTTOMLEFT", 0, -2)

    -- 6. Raid Target Marker (Centered on top of health bar)
    raidTargetIcon = healthBar:CreateTexture(nil, "OVERLAY", nil, 7)
    raidTargetIcon:SetSize(16, 16)
    raidTargetIcon:SetPoint("CENTER", healthBar, "TOP", 0, 1)
    raidTargetIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    raidTargetIcon:Hide()

    -- 7. Quest Mob Indicator (Left of target name)
    questIcon = f:CreateTexture(nil, "OVERLAY", nil, 6)
    questIcon:SetSize(14, 14)
    questIcon:SetTexture("Interface\\TargetingFrame\\PortraitQuestBadge")
    questIcon:SetPoint("BOTTOMLEFT", healthBar.backdrop, "TOPLEFT", 0, 2)
    questIcon:Hide()

    -- 8. Aura Containers (Native AuraContainer - Positive & Negative Buckets)
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

    -- 9. Range Ticker (Out-of-range alpha dimming)
    local rangeElapsed = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        rangeElapsed = rangeElapsed + elapsed
        if rangeElapsed >= 0.15 then
            rangeElapsed = 0
            UpdateTargetRange()
        end
    end)

    targetContainer = f
    targetContainer:Hide()

    UpdateLayoutAnchors()

    return f
end

-- ─── Public API ──────────────────────────────────────────────────────────────
function sfui.target.Unlock()
    sfui.target.unlocked = true
    if targetContainer then
        targetContainer:Show()
        nameText:SetText("|cff00ff00[Target Bar - Drag to Move]|r")
        levelText:SetText("|cff00ff00(Shift+Drag)|r")
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
    sfui.target.unlocked = false
    UpdateAll()
end

function sfui.target.ToggleLock()
    if sfui.target.unlocked then
        sfui.target.Lock()
    else
        sfui.target.Unlock()
    end
end

function sfui.target.ResetPosition()
    SfuiDB = SfuiDB or {}
    SfuiDB.targetBar_pos = nil
    ApplyTargetPosition()
end

function sfui.target.UpdateVisibility()
    if SfuiDB and SfuiDB.enableTargetBar == false then
        if targetContainer then targetContainer:Hide() end
        local tf = _G.TargetFrame
        if tf and not InCombatLockdown() then
            tf:SetAlpha(1)
            if tf.EnableMouse then tf:EnableMouse(true) end
            if UnitExists("target") then tf:Show() end
        end
    else
        HookBlizzardTargetFrame()
        UpdateAll()
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

    UpdateAll(true)
end

-- Defer initialization until PLAYER_LOGIN
sfui.events.RegisterEvent("PLAYER_LOGIN", Initialize)
