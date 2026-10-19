--[[
    sfui/frames/bars/pet.lua
    hunter and warlock pet unit frame for camelot, positioned to the right of the healthbar.
    matches the exact style, theme, and padding of the player health and power bars.
]]

local addonName, addon = ...
sfui = sfui or {}
sfui.pet = sfui.pet or {}

-- strictly camelot and hunter/warlock only
local isCamelot = (sfui.isCamelot or (sfui.compat and sfui.compat.is_camelot))
if not isCamelot then return end

local _, playerClass = UnitClass("player")
if playerClass ~= "HUNTER" and playerClass ~= "WARLOCK" then return end

local cfg = sfui.config
local common = sfui.common

-- ─────────────────────────────────────────────────────────────────────────────
--  upvalues & localization
-- ─────────────────────────────────────────────────────────────────────────────
local _G                        = _G
local CreateFrame               = _G.CreateFrame
local UIParent                  = _G.UIParent
local GameTooltip               = sfui.common.get_tooltip()
local InCombatLockdown          = _G.InCombatLockdown
local RegisterStateDriver       = _G.RegisterStateDriver
local UnregisterStateDriver     = _G.UnregisterStateDriver
local RegisterUnitWatch         = _G.RegisterUnitWatch
local UnitExists                = _G.UnitExists
local UnitHealth                = _G.UnitHealth
local UnitHealthMax             = _G.UnitHealthMax
local UnitIsDead                = _G.UnitIsDead
local UnitIsGhost               = _G.UnitIsGhost
local UnitPower                 = _G.UnitPower
local UnitPowerMax              = _G.UnitPowerMax
local UnitPowerType             = _G.UnitPowerType
local UnitName                  = _G.UnitName
local UnitLevel                 = _G.UnitLevel
local UnitCreatureFamily        = _G.UnitCreatureFamily
local UnitGetIncomingHeals      = _G.UnitGetIncomingHeals
local UnitGetTotalAbsorbs       = _G.UnitGetTotalAbsorbs
local PowerBarColor             = _G.PowerBarColor
local GetPetHappiness           = _G.GetPetHappiness or (_G.C_PetInfo and _G.C_PetInfo.GetPetHappiness)
local math_floor                = math.floor
local tostring                  = _G.tostring
local string_format             = string.format
local type                      = _G.type

local issecretvalue             = (common and common.issecretvalue) or _G.issecretvalue or function() return false end

-- ─────────────────────────────────────────────────────────────────────────────
--  frame elements
-- ─────────────────────────────────────────────────────────────────────────────
local container
local healthBackdrop
local healthBar
local healPredBar
local absorbBar
local nameText
local hpText
local happinessDot
local powerBackdrop
local powerBar
local powerText
local levelText

local function get_bar_texture()
    local tex = sfui.widgets and sfui.widgets.get_bar_texture and sfui.widgets.get_bar_texture()
    if not tex or tex == "" then
        local textureName = SfuiDB and SfuiDB.barTexture
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if LSM and textureName then
            tex = LSM:Fetch("statusbar", textureName)
        end
    end
    if not tex or tex == "" then
        tex = (cfg and cfg.barTexture) or "Interface\\Buttons\\WHITE8x8"
    end
    return tex
end

local function get_font_path()
    return (sfui.widgets and sfui.widgets.get_font and sfui.widgets.get_font()) or "Fonts\\FRIZQT__.TTF"
end

-- ─────────────────────────────────────────────────────────────────────────────
--  data & state updates
-- ─────────────────────────────────────────────────────────────────────────────
local function update_health()
    if not healthBar then return end
    if not UnitExists("pet") then return end

    local curHp = UnitHealth("pet")
    local maxHp = UnitHealthMax("pet")
    if not curHp or not maxHp then return end

    healthBar:SetMinMaxValues(0, maxHp)
    healthBar:SetValue(curHp)

    -- matching player healthbar color
    local fgColor = (SfuiDB and SfuiDB.healthBarColor)
        or (sfui.config and sfui.config.healthBar and sfui.config.healthBar.color)
        or { 0.2, 0.2, 0.2 }
    healthBar:SetStatusBarColor(fgColor[1], fgColor[2], fgColor[3], fgColor[4] or 1)

    local isDead = UnitIsDead("pet") or UnitIsGhost("pet")
    if isDead then
        hpText:SetText("|cffff3333dead|r")
        healthBar:SetValue(0)
    else
        hpText:SetText("")
    end

    -- heal prediction
    local width, height = healthBar:GetSize()
    if healPredBar then
        healPredBar:SetSize(width, height)
        healPredBar:SetMinMaxValues(0, maxHp)
        healPredBar:ClearAllPoints()
        healPredBar:SetPoint("TOPLEFT", healthBar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        local incoming = (UnitGetIncomingHeals and UnitGetIncomingHeals("pet")) or 0
        healPredBar:SetValue(incoming)
    end

    -- absorb bar
    if absorbBar then
        absorbBar:SetSize(width, height)
        absorbBar:SetMinMaxValues(0, maxHp)
        absorbBar:ClearAllPoints()
        local anchor = (healPredBar and healPredBar:GetStatusBarTexture()) or healthBar:GetStatusBarTexture()
        absorbBar:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 0, 0)
        local totalAbsorb = (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs("pet")) or 0
        absorbBar:SetValue(totalAbsorb)
        local absorbCol = (SfuiDB and SfuiDB.absorbBarColor)
            or (sfui.config and sfui.config.healthBar and sfui.config.healthBar.absorbBarColor)
        absorbBar:SetStatusBarColor(common.unpack_color(absorbCol))
    end
end

local function update_power()
    if not powerBar then return end
    if not UnitExists("pet") then return end

    local powerType, powerToken = UnitPowerType("pet")
    local curPwr = UnitPower("pet")
    local maxPwr = UnitPowerMax("pet")
    if not curPwr or not maxPwr then return end

    powerBar:SetMinMaxValues(0, maxPwr)
    powerBar:SetValue(curPwr)

    local color = (powerToken and PowerBarColor and PowerBarColor[powerToken])
        or (PowerBarColor and PowerBarColor[powerType])
    if color then
        powerBar:SetStatusBarColor(color.r, color.g, color.b)
    elseif powerType == 2 then -- focus
        powerBar:SetStatusBarColor(1.0, 0.5, 0.25)
    else -- mana
        powerBar:SetStatusBarColor(0.3, 0.5, 0.85)
    end

    powerText:SetText(curPwr)
end

local function update_name_and_happiness()
    if not nameText then return end
    if not UnitExists("pet") then return end

    local petName = UnitName("pet")
    nameText:SetText(petName or "pet")

    if playerClass == "HUNTER" and happinessDot then
        local happ = GetPetHappiness and GetPetHappiness()
        if issecretvalue(happ) then
            happ = nil
        end
        if happ == 3 then
            happinessDot:SetText("|cff33ff33•|r")
            happinessDot:Show()
        elseif happ == 2 then
            happinessDot:SetText("|cffffff33•|r")
            happinessDot:Show()
        elseif happ == 1 then
            happinessDot:SetText("|cffff3333•|r")
            happinessDot:Show()
        else
            happinessDot:Hide()
        end
    end

    if levelText then
        local lvl = UnitLevel("pet")
        if issecretvalue(lvl) then
            levelText:SetText("")
        elseif lvl and lvl > 0 then
            levelText:SetFormattedText("lvl %d", lvl)
        else
            levelText:SetText("")
        end
    end
end

local function update_all()
    if not UnitExists("pet") then return end
    update_health()
    update_power()
    update_name_and_happiness()
end

local function get_visibility_driver()
    local petEnabled = (SfuiDB == nil or SfuiDB.enablePetBar ~= false)
    local healthEnabled = (SfuiDB == nil or SfuiDB.enableHealthBar ~= false)
    if not petEnabled or not healthEnabled then
        return "hide"
    end

    local bar0 = sfui.bars and sfui.bars.get_bar0 and sfui.bars.get_bar0()
    local healthShown = bar0 and bar0.backdrop and bar0.backdrop:IsShown()

    local vcfg = (sfui.config and sfui.config.barVisibility) or {}
    local alwaysShow = (SfuiDB and (SfuiDB.bars_oocAlways or SfuiDB.bars_alwaysShow)) or vcfg.oocAlways
    local showFriendly = ((SfuiDB and SfuiDB.bars_showFriendlyTarget) or (vcfg.showFriendlyTarget and (SfuiDB == nil or SfuiDB.bars_showFriendlyTarget ~= false)))
    local targetRule = showFriendly and "[@target,exists,nodead] show;" or "[@target,harm,nodead] show;"

    local oocRule = (healthShown or alwaysShow) and "show" or "hide"

    return string_format("[@pet,noexists] hide; [canexitvehicle] hide; [vehicleui] hide; [possessbar] hide; [overridebar] hide; [combat] show; %s %s", targetRule, oocRule)
end

local lastVisibilityDriver
local function update_visibility()
    if not container then return end

    local petEnabled = (SfuiDB == nil or SfuiDB.enablePetBar ~= false)
    local healthEnabled = (SfuiDB == nil or SfuiDB.enableHealthBar ~= false)

    if not InCombatLockdown or not InCombatLockdown() then
        local driver = get_visibility_driver()
        if driver ~= lastVisibilityDriver then
            lastVisibilityDriver = driver
            if _G.UnregisterUnitWatch then
                _G.UnregisterUnitWatch(container)
            end
            if RegisterStateDriver then
                RegisterStateDriver(container, "visibility", driver)
            end
        end
        if not petEnabled or not healthEnabled then
            container:Hide()
        end
    end

    -- follow healthbar backdrop visibility (handles vehicle, dragonflying, and custom hiding)
    local bar0 = sfui.bars and sfui.bars.get_bar0 and sfui.bars.get_bar0()
    if not petEnabled or not healthEnabled then
        container:SetAlpha(0)
    elseif InCombatLockdown and InCombatLockdown() then
        container:SetAlpha(1)
    elseif bar0 and bar0.backdrop then
        if bar0.backdrop:IsShown() then
            container:SetAlpha(1)
        else
            container:SetAlpha(0)
        end
    else
        container:SetAlpha(1)
    end
end

local function update_position()
    if not container then return end
    if InCombatLockdown and InCombatLockdown() then return end

    local pcfg = (sfui.config and sfui.config.petBar) or {}
    local hcfg = (sfui.config and sfui.config.healthBar) or {}
    local pwrcfg = (sfui.config and sfui.config.powerBar) or {}

    local barW    = (SfuiDB and SfuiDB.petBar_width) or pcfg.width or 110
    local barH    = (SfuiDB and SfuiDB.petBar_height) or pcfg.height or hcfg.height or 20
    local pwrH    = (SfuiDB and SfuiDB.petBar_powerHeight) or pcfg.powerHeight or pwrcfg.height or 10
    local pad     = (pcfg.backdrop and pcfg.backdrop.padding) or (hcfg.backdrop and hcfg.backdrop.padding) or 2
    local spacing = (sfui.config and sfui.config.barLayout and sfui.config.barLayout.spacing) or 2

    local totalW = barW + pad * 2
    local totalH = barH + pad * 2 + spacing + pwrH + pad * 2

    container:SetSize(totalW, totalH)
    if healthBackdrop then healthBackdrop:SetSize(barW + pad * 2, barH + pad * 2) end
    if healthBar then healthBar:SetSize(barW, barH) end
    if powerBackdrop then powerBackdrop:SetSize(barW + pad * 2, pwrH + pad * 2) end
    if powerBar then powerBar:SetSize(barW, pwrH) end

    local hW = (SfuiDB and SfuiDB.healthBar_width) or hcfg.width or 220
    local hPad = (hcfg.backdrop and hcfg.backdrop.padding) or 2
    local hX = (SfuiDB and SfuiDB.healthBarX) or (hcfg.pos and hcfg.pos.x) or 0
    local hY = (SfuiDB and SfuiDB.healthBarY) or (hcfg.pos and hcfg.pos.y) or 160
    local hH = (SfuiDB and SfuiDB.healthBar_height) or hcfg.height or 20

    local totalHealthBackdropW = hW + hPad * 2
    local totalHealthBackdropH = hH + hPad * 2

    -- anchor directly to UIParent to prevent propagating secure taint to bar0.backdrop
    local petX = hX + (totalHealthBackdropW / 2) + spacing
    local petY = hY + totalHealthBackdropH

    container:ClearAllPoints()
    container:SetPoint("TOPLEFT", UIParent, "BOTTOM", petX, petY)
end

local function set_bar_texture(texturePath)
    if not texturePath or texturePath == "" then return end
    if healthBar then healthBar:SetStatusBarTexture(texturePath) end
    if healPredBar then healPredBar:SetStatusBarTexture(texturePath) end
    if absorbBar then absorbBar:SetStatusBarTexture(texturePath) end
    if powerBar then powerBar:SetStatusBarTexture(texturePath) end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  frame creation & initialization
-- ─────────────────────────────────────────────────────────────────────────────
local function init_pet_frame()
    if container then return end

    local pcfg = (sfui.config and sfui.config.petBar) or {}
    local hcfg = (sfui.config and sfui.config.healthBar) or {}
    local pwrcfg = (sfui.config and sfui.config.powerBar) or {}

    local barW    = (SfuiDB and SfuiDB.petBar_width) or pcfg.width or 110
    local barH    = (SfuiDB and SfuiDB.petBar_height) or pcfg.height or hcfg.height or 20
    local pwrH    = (SfuiDB and SfuiDB.petBar_powerHeight) or pcfg.powerHeight or pwrcfg.height or 10
    local pad     = (pcfg.backdrop and pcfg.backdrop.padding) or (hcfg.backdrop and hcfg.backdrop.padding) or 2
    local spacing = (sfui.config and sfui.config.barLayout and sfui.config.barLayout.spacing) or 2
    local bgCol   = (pcfg.backdrop and pcfg.backdrop.color) or (hcfg.backdrop and hcfg.backdrop.color) or { 0, 0, 0, 0.5 }

    local totalW = barW + pad * 2
    local totalH = barH + pad * 2 + spacing + pwrH + pad * 2

    -- secure action button container
    container = CreateFrame("Button", "SfuiPetFrame", UIParent, "SecureActionButtonTemplate")
    container:SetSize(totalW, totalH)
    container:SetFrameStrata("MEDIUM")
    container:SetClampedToScreen(true)
    container:SetAttribute("unit", "pet")
    container:SetAttribute("*type1", "target")
    container:SetAttribute("*type2", "togglemenu")
    container:RegisterForClicks("AnyUp", "AnyDown")

    local function find_edible_pet_food()
        local C_PetInfo = _G.C_PetInfo
        local C_Container = _G.C_Container
        local numBags = _G.NUM_BAG_SLOTS or 4
        for bag = 0, numBags do
            local numSlots = (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag))
                             or (_G.GetContainerNumSlots and _G.GetContainerNumSlots(bag)) or 0
            for slot = 1, numSlots do
                local itemID = (C_Container and C_Container.GetContainerItemID and C_Container.GetContainerItemID(bag, slot))
                               or (_G.GetContainerItemID and _G.GetContainerItemID(bag, slot))
                if itemID and C_PetInfo and C_PetInfo.CanPetEatItem and C_PetInfo.CanPetEatItem(itemID) then
                    return bag, slot, itemID
                end
            end
        end
        return nil, nil, nil
    end

    local function fast_feed_pet()
        if InCombatLockdown and InCombatLockdown() then
            if _G.UIErrorsFrame and _G.ERR_NOT_IN_COMBAT then
                _G.UIErrorsFrame:AddMessage(_G.ERR_NOT_IN_COMBAT, 1, 0.1, 0.1)
            end
            return
        end
        if not UnitExists("pet") or (UnitIsDead and UnitIsDead("pet")) then return end

        local bag, slot, itemID = find_edible_pet_food()
        if not bag or not slot then
            if _G.UIErrorsFrame then
                _G.UIErrorsFrame:AddMessage("no suitable pet food in bags", 1, 0.5, 0.2)
            end
            return
        end

        local itemName
        local C_Item = _G.C_Item
        if C_Item and C_Item.GetItemNameByID then
            itemName = C_Item.GetItemNameByID(itemID)
        elseif _G.GetItemInfo then
            itemName = _G.GetItemInfo(itemID)
        end

        _G.ClearCursor()
        local C_Container = _G.C_Container
        if C_Container and C_Container.PickupContainerItem then
            C_Container.PickupContainerItem(bag, slot)
        elseif _G.PickupContainerItem then
            _G.PickupContainerItem(bag, slot)
        end

        if _G.CursorHasItem and _G.CursorHasItem() then
            local dropFn = (C_Item and C_Item.DropItemOnUnit) or _G.DropItemOnUnit
            if dropFn then
                dropFn("pet")
            end
            _G.ClearCursor()
            if sfui.common and sfui.common.print and itemName then
                sfui.common.print("fed pet: " .. itemName:lower())
            end
        end
    end
    sfui.pet.fast_feed = fast_feed_pet

    container:HookScript("OnMouseUp", function(self, button)
        if button == "MiddleButton" then
            fast_feed_pet()
        end
    end)

    -- mouseover tooltip
    container:SetScript("OnEnter", function(self)
        if not UnitExists("pet") then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 4, 0)
        GameTooltip:SetUnit("pet")
        if playerClass == "HUNTER" then
            local happ, dmgPct = GetPetHappiness and GetPetHappiness()
            if happ then
                local happText = (happ == 3 and "happy") or (happ == 2 and "content") or "unhappy"
                local happColor = (happ == 3 and "|cff33ff33") or (happ == 2 and "|cffffff33") or "|cffff3333"
                GameTooltip:AddLine(string_format("happiness: %s%s|r (%d%% damage)", happColor, happText, dmgPct or 100), 1, 1, 1)
            end

            local C_PetInfo = _G.C_PetInfo
            local loyalty = C_PetInfo and C_PetInfo.GetPetLoyalty and C_PetInfo.GetPetLoyalty()
            if loyalty and loyalty ~= "" then
                GameTooltip:AddDoubleLine("loyalty:", loyalty:lower(), 0.8, 0.8, 0.8, 1, 1, 1)
            end

            local totalTP, usedTP = 0, 0
            if C_PetInfo and C_PetInfo.GetPetTrainingPoints then
                totalTP, usedTP = C_PetInfo.GetPetTrainingPoints()
            end
            local unspent = totalTP - usedTP
            if unspent > 0 then
                GameTooltip:AddDoubleLine("training points:", unspent .. " tp available", 0.8, 0.8, 0.8, 0.2, 0.9, 0.2)
            end

            local diet = C_PetInfo and C_PetInfo.GetPetFoodTypes and C_PetInfo.GetPetFoodTypes()
            if diet and #diet > 0 then
                GameTooltip:AddDoubleLine("diet:", table.concat(diet, ", "):lower(), 0.8, 0.8, 0.8, 0.9, 0.9, 0.9)
            end
        end
        GameTooltip:AddLine("<left-click: target | right-click: menu>", 0.7, 0.7, 0.7)
        if playerClass == "HUNTER" then
            GameTooltip:AddLine("<middle-click: fast feed pet>", 0.2, 0.9, 0.2)
        end
        GameTooltip:Show()
    end)
    container:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    -- health bar backdrop
    healthBackdrop = CreateFrame("Frame", "SfuiPetHealthBackdrop", container, "BackdropTemplate")
    sfui.common.set_pixel_snapping(healthBackdrop)
    healthBackdrop:SetSize(barW + pad * 2, barH + pad * 2)
    healthBackdrop:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    healthBackdrop:SetBackdrop({
        bgFile   = (sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
        tile     = true,
        tileSize = 32,
    })
    healthBackdrop:SetBackdropColor(bgCol[1], bgCol[2], bgCol[3], bgCol[4] or 0.5)

    -- health bar statusbar
    healthBar = CreateFrame("StatusBar", "SfuiPetHealthBar", healthBackdrop)
    sfui.common.set_pixel_snapping(healthBar)
    healthBar:SetSize(barW, barH)
    healthBar:SetPoint("CENTER", healthBackdrop, "CENTER", 0, 0)
    healthBar:SetStatusBarTexture(get_bar_texture())
    healthBar.backdrop = healthBackdrop

    -- register with theme engine (applies camelot bronze bezel/well automatically)
    if sfui.theme and sfui.theme.RegisterBar then
        sfui.theme.RegisterBar(healthBar, "health")
    end

    -- heal prediction
    healPredBar = CreateFrame("StatusBar", nil, healthBar)
    healPredBar:SetFrameLevel(healthBar:GetFrameLevel() + 1)
    healPredBar:SetStatusBarTexture(get_bar_texture())
    healPredBar:SetStatusBarColor(0.0, 0.8, 0.6, 0.5)
    healPredBar:SetPoint("TOPLEFT", healthBar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    if healPredBar.GetStatusBarTexture then
        healPredBar:GetStatusBarTexture():SetBlendMode("ADD")
    end
    healthBar.healPredBar = healPredBar

    -- absorbs
    absorbBar = CreateFrame("StatusBar", nil, healthBar)
    absorbBar:SetFrameLevel(healthBar:GetFrameLevel() + 2)
    absorbBar:SetStatusBarTexture(get_bar_texture())
    if absorbBar.GetStatusBarTexture then
        absorbBar:GetStatusBarTexture():SetBlendMode("ADD")
    end
    healthBar.absorbBar = absorbBar

    local fontPath = get_font_path()

    -- hunter happiness pip
    if playerClass == "HUNTER" then
        happinessDot = healthBar:CreateFontString(nil, "OVERLAY", nil, 6)
        happinessDot:SetFont(fontPath, 11, "")
        happinessDot:SetShadowOffset(1, -1)
        happinessDot:SetShadowColor(0, 0, 0, 0.9)
        happinessDot:SetPoint("LEFT", healthBar, "LEFT", 3, 0)
        happinessDot:SetText("|cff33ff33•|r")
    end

    -- pet name
    nameText = healthBar:CreateFontString(nil, "OVERLAY", nil, 5)
    nameText:SetFont(fontPath, 10, "")
    nameText:SetShadowOffset(1, -1)
    nameText:SetShadowColor(0, 0, 0, 0.9)
    if happinessDot then
        nameText:SetPoint("LEFT", happinessDot, "RIGHT", 1, 0)
    else
        nameText:SetPoint("LEFT", healthBar, "LEFT", 4, 0)
    end
    nameText:SetPoint("RIGHT", healthBar, "RIGHT", -36, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    nameText:SetTextColor(1, 1, 1, 0.95)

    -- pet health percentage
    hpText = healthBar:CreateFontString(nil, "OVERLAY", nil, 5)
    hpText:SetFont(fontPath, 10, "")
    hpText:SetShadowOffset(1, -1)
    hpText:SetShadowColor(0, 0, 0, 0.9)
    hpText:SetPoint("RIGHT", healthBar, "RIGHT", -4, 0)
    hpText:SetJustifyH("RIGHT")
    hpText:SetTextColor(1, 1, 1, 0.95)

    -- power bar backdrop
    powerBackdrop = CreateFrame("Frame", "SfuiPetPowerBackdrop", container, "BackdropTemplate")
    sfui.common.set_pixel_snapping(powerBackdrop)
    powerBackdrop:SetSize(barW + pad * 2, pwrH + pad * 2)
    powerBackdrop:SetPoint("TOPLEFT", healthBackdrop, "BOTTOMLEFT", 0, -spacing)
    powerBackdrop:SetBackdrop({
        bgFile   = (sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
        tile     = true,
        tileSize = 32,
    })
    powerBackdrop:SetBackdropColor(bgCol[1], bgCol[2], bgCol[3], bgCol[4] or 0.5)

    -- power bar statusbar
    powerBar = CreateFrame("StatusBar", "SfuiPetPowerBar", powerBackdrop)
    sfui.common.set_pixel_snapping(powerBar)
    powerBar:SetSize(barW, pwrH)
    powerBar:SetPoint("CENTER", powerBackdrop, "CENTER", 0, 0)
    powerBar:SetStatusBarTexture(get_bar_texture())
    powerBar.backdrop = powerBackdrop

    if sfui.theme and sfui.theme.RegisterBar then
        sfui.theme.RegisterBar(powerBar, "power")
    end

    -- pet level text on power bar
    levelText = powerBar:CreateFontString(nil, "OVERLAY", nil, 5)
    levelText:SetFont(fontPath, 9, "")
    levelText:SetShadowOffset(1, -1)
    levelText:SetShadowColor(0, 0, 0, 0.9)
    levelText:SetPoint("LEFT", powerBar, "LEFT", 4, 0)
    levelText:SetJustifyH("LEFT")
    levelText:SetTextColor(0.8, 0.8, 0.8, 0.85)

    -- current power numeric text
    powerText = powerBar:CreateFontString(nil, "OVERLAY", nil, 5)
    powerText:SetFont(fontPath, 9, "")
    powerText:SetShadowOffset(1, -1)
    powerText:SetShadowColor(0, 0, 0, 0.9)
    powerText:SetPoint("RIGHT", powerBar, "RIGHT", -4, 0)
    powerText:SetJustifyH("RIGHT")
    powerText:SetTextColor(1, 1, 1, 0.85)

    update_position()
    update_all()
    update_visibility()
end

-- ─────────────────────────────────────────────────────────────────────────────
--  events registration
-- ─────────────────────────────────────────────────────────────────────────────
if sfui.events and sfui.events.RegisterUnitEvents then
    sfui.events.RegisterUnitEvents({
        "UNIT_HEALTH",
        "UNIT_MAXHEALTH",
        "UNIT_HEAL_PREDICTION",
        "UNIT_ABSORB_AMOUNT_CHANGED",
    }, "pet", update_health)

    sfui.events.RegisterUnitEvents({
        "UNIT_POWER_UPDATE",
        "UNIT_MAXPOWER",
        "UNIT_DISPLAYPOWER",
    }, "pet", update_power)

    sfui.events.RegisterUnitEvents({
        "UNIT_NAME_UPDATE",
        "UNIT_LEVEL",
        "UNIT_HAPPINESS",
    }, "pet", update_name_and_happiness)

    sfui.events.RegisterUnitEvent("UNIT_PET", "player", function()
        update_all()
        update_visibility()
    end)
end

if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("PET_UI_UPDATE", function()
        update_all()
        update_visibility()
    end)

    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        init_pet_frame()
        update_position()
        update_all()
        update_visibility()
    end)

    sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", function()
        update_position()
        update_visibility()
    end)

    sfui.events.RegisterEvent("PLAYER_REGEN_DISABLED", function()
        update_visibility()
    end)

    sfui.events.RegisterEvent("PLAYER_TARGET_CHANGED", function()
        update_visibility()
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
--  module exports
-- ─────────────────────────────────────────────────────────────────────────────
sfui.pet.Init             = init_pet_frame
sfui.pet.Update           = update_all
sfui.pet.UpdatePosition   = update_position
sfui.pet.UpdateVisibility = update_visibility
sfui.pet.SetBarTexture    = set_bar_texture

init_pet_frame()
