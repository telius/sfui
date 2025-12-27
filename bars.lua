-- bars.lua for sfui
-- author: teli
-- Adapted from NephUI's resource bar implementation.

sfui = sfui or {}
sfui.bars = {}

do
    local primary_power_bar
    local secondary_power_bar
    local health_bar
    local vigor_bar
    local mount_speed_bar
    local UpdateMountSpeedBarInternal

    local function GetSecondaryResourceValue(resource)
        if not resource then return nil, nil end
        if resource == "STAGGER" then
            local stagger = UnitStagger("player") or 0
            local maxHealth = UnitHealthMax("player") or 1
            return maxHealth, stagger
        end
        -- For Runes, we just show the count, not individual cooldowns.
        if resource == Enum.PowerType.Runes then
            local current, max = 0, UnitPowerMax("player", resource)
            if max <= 0 then return nil, nil end
            for i = 1, max do
                local _, _, ready = GetRuneCooldown(i)
                if ready then current = current + 1 end
            end
            return max, current
        end
        local current = UnitPower("player", resource)
        local max = UnitPowerMax("player", resource)
        if max <= 0 then return nil, nil end
        return max, current
    end

    local function IsDragonflying()
        local isFlying, canGlide, _ = C_PlayerInfo.GetGlidingInfo()
        local hasSkyridingBar = (GetBonusBarIndex() == 11 and GetBonusBarOffset() == 5)
        return isFlying or (canGlide and hasSkyridingBar)
    end

    local function UpdateBarPositions()
        if health_bar and health_bar.backdrop then
            health_bar.backdrop:ClearAllPoints()
            health_bar.backdrop:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 300)
        end

        if IsDragonflying() then
            if mount_speed_bar and mount_speed_bar.backdrop and vigor_bar and vigor_bar.backdrop then
                mount_speed_bar.backdrop:ClearAllPoints()
                mount_speed_bar.backdrop:SetPoint("TOP", vigor_bar.backdrop, "BOTTOM", 0, -5) -- Stack under and center with vigor bar

                -- Position icons below Mount Speed Bar if they exist
                if vigor_bar.whirlingSurgeIcon and vigor_bar.secondWindIcon then
                    local gap = 5
                    vigor_bar.whirlingSurgeIcon:ClearAllPoints()
                    vigor_bar.whirlingSurgeIcon:SetPoint("TOPRIGHT", mount_speed_bar.backdrop, "BOTTOM", -gap / 2, -5)

                    vigor_bar.secondWindIcon:ClearAllPoints()
                    vigor_bar.secondWindIcon:SetPoint("TOPLEFT", mount_speed_bar.backdrop, "BOTTOM", gap / 2, -5)

                    if vigor_bar.staticChargeIcon then
                        vigor_bar.staticChargeIcon:ClearAllPoints()
                        vigor_bar.staticChargeIcon:SetPoint("LEFT", vigor_bar.backdrop, "RIGHT", 5, 0)
                    end
                end
            end
            if vigor_bar and vigor_bar.backdrop and health_bar and health_bar.backdrop then
                vigor_bar.backdrop:ClearAllPoints()
                vigor_bar.backdrop:SetPoint("BOTTOM", health_bar.backdrop, "TOP", 0, 5)
            end
        else
            if primary_power_bar and primary_power_bar.backdrop and health_bar and health_bar.backdrop then
                primary_power_bar.backdrop:ClearAllPoints()
                primary_power_bar.backdrop:SetPoint("TOP", health_bar.backdrop, "BOTTOM", 0, -5)
            end
            if secondary_power_bar and secondary_power_bar.backdrop and health_bar and health_bar.backdrop then
                secondary_power_bar.backdrop:ClearAllPoints()
                secondary_power_bar.backdrop:SetPoint("BOTTOM", health_bar.backdrop, "TOP", 0, 5)
            end
        end
    end

    local function UpdateBarVisibility()
        local isDragonflying = IsDragonflying()
        local inCombat = UnitAffectingCombat("player")
        local hasEnemyTarget = UnitCanAttack("player", "target")
        local showCoreBars = inCombat or hasEnemyTarget

        -- Vigor and Mount Speed bars (instant show/hide)
        if isDragonflying then
            if vigor_bar then vigor_bar.backdrop:Show() end
            if mount_speed_bar then mount_speed_bar.backdrop:Show() end
        else
            if vigor_bar then vigor_bar.backdrop:Hide() end
            if mount_speed_bar then mount_speed_bar.backdrop:Hide() end
        end

        -- Core bars (health, primary, secondary)
        if isDragonflying then
            -- When dragonflying, core bars are always hidden.
            if health_bar then health_bar.backdrop:Hide() end
            if primary_power_bar then primary_power_bar.backdrop:Hide() end
            if secondary_power_bar then secondary_power_bar.backdrop:Hide() end
        else
            local spec = C_SpecializationInfo.GetSpecialization()
            local specID = 0
            if spec then
                specID = select(1, C_SpecializationInfo.GetSpecializationInfo(spec))
            end

            -- Secondary Power Bar visibility for non-dragonflying
            if secondary_power_bar then
                if IsMounted() then       -- Hide if mounted
                    secondary_power_bar.backdrop:Hide()
                elseif specID == 270 then -- Mistweaver Monk
                    secondary_power_bar.backdrop:Hide()
                elseif showCoreBars and sfui.common.GetSecondaryResource() then
                    secondary_power_bar.backdrop:Show()
                else
                    secondary_power_bar.backdrop:Hide()
                end
            end

            -- Health and Primary Power Bar visibility for non-dragonflying
            if showCoreBars then
                if health_bar then health_bar.backdrop:Show() end

                local hidePowerBar = false
                if sfui.config.powerBar.hiddenSpecs and sfui.config.powerBar.hiddenSpecs[specID] then
                    hidePowerBar = true
                end

                if primary_power_bar then
                    if hidePowerBar then
                        primary_power_bar.backdrop:Hide()
                    else
                        primary_power_bar.backdrop:Show()
                    end
                end
            else
                if health_bar then health_bar.backdrop:Hide() end
                if primary_power_bar then primary_power_bar.backdrop:Hide() end
            end
        end

        UpdateBarPositions()
    end

    local function GetPrimaryPowerBar()
        if primary_power_bar then return primary_power_bar end
        local bar = sfui.common.CreateBar("powerBar", "StatusBar", UIParent)
        bar:GetStatusBarTexture():SetHorizTile(true)
        primary_power_bar = bar
        return bar
    end

    local function UpdatePrimaryPowerBar()
        local cfg = sfui.config.powerBar
        if not cfg.enabled or IsDragonflying() then
            if primary_power_bar and primary_power_bar.backdrop then primary_power_bar.backdrop:Hide() end
            return
        end
        local bar = GetPrimaryPowerBar()
        local resource = sfui.common.GetPrimaryResource()
        if not resource then return end
        local max, current = UnitPowerMax("player", resource), UnitPower("player", resource)
        if not max or max <= 0 then return end
        bar:SetMinMaxValues(0, max)
        bar:SetValue(current)
        local color = sfui.common.GetClassOrSpecColor()
        if color then bar:SetStatusBarColor(color.r, color.g, color.b) end
    end

    -- UpdateFillPosition removed (Secret Values cannot be used in arithmetic).
    -- We rely on StatusBar:SetValue() to handle secure values internally.

    local function GetHealthBar()
        if health_bar then return health_bar end
        local bar = sfui.common.CreateBar("healthBar", "StatusBar", UIParent)
        bar:GetStatusBarTexture():SetHorizTile(true)
        health_bar = bar

        local cfg = sfui.config.healthBar -- Need this to get height

        local textureName = SfuiDB.barTexture
        local LSM = LibStub("LibSharedMedia-3.0", true)
        local texturePath
        if LSM then
            texturePath = LSM:Fetch("statusbar", textureName)
        end
        if not texturePath or texturePath == "" then
            texturePath = sfui.config.barTexture
        end

        -- Heal Prediction (StatusBar)
        local healPredBar = CreateFrame("StatusBar", "sfui_HealthBar_HealPred", health_bar)
        healPredBar:SetFrameLevel(bar:GetFrameLevel() + 1)
        healPredBar:SetStatusBarTexture(texturePath)
        healPredBar:SetStatusBarColor(0.0, 0.8, 0.6, 0.5)     -- Teal-Green with transparency
        healPredBar:GetStatusBarTexture():SetBlendMode("ADD") -- Glow effect
        bar.healPredBar = healPredBar

        -- Absorb (StatusBar)
        local absorbBar = CreateFrame("StatusBar", "sfui_HealthBar_Absorb", health_bar)
        absorbBar:SetFrameLevel(bar:GetFrameLevel() + 2)
        absorbBar:SetStatusBarTexture(texturePath)
        absorbBar:GetStatusBarTexture():SetBlendMode("ADD") -- Glow effect
        bar.absorbBar = absorbBar

        return bar
    end

    local function UpdateHealthBar(current, maxVal)
        local cfg = sfui.config.healthBar
        if not cfg.enabled then return end
        local bar = GetHealthBar()
        -- current and max are passed in now
        if not maxVal or maxVal <= 0 then return end
        bar:SetMinMaxValues(0, maxVal)
        bar:SetValue(current)
        bar:SetStatusBarColor(0.2, 0.2, 0.2) -- Set to very dark grey

        local width, height = bar:GetSize()

        -- Secure Stacking Logic:
        -- 1. Anchor HealPredBar to the end of HealthBar's TEXTURE.
        -- 2. Set HealPredBar Width to FULL width of the parent (so SetValue works correctly relative to full bar).
        -- 3. SetValue(incoming) -> The engine calculates the texture width securely.

        local healPred = bar.healPredBar
        healPred:SetSize(width, height)
        healPred:SetMinMaxValues(0, maxVal)

        healPred:ClearAllPoints()
        healPred:SetPoint("TOPLEFT", bar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)

        local incomingHeals = UnitGetIncomingHeals("player") or 0
        healPred:SetValue(incomingHeals)

        -- Absorb Logic
        -- Anchor AbsorbBar to the end of HealPredBar's TEXTURE.
        local absorbBar = bar.absorbBar
        absorbBar:SetSize(width, height)
        absorbBar:SetMinMaxValues(0, maxVal)

        absorbBar:ClearAllPoints()
        absorbBar:SetPoint("TOPLEFT", healPred:GetStatusBarTexture(), "TOPRIGHT", 0, 0)

        local absorbAmount = UnitGetTotalAbsorbs("player") or 0
        absorbBar:SetValue(absorbAmount)

        local color = SfuiDB.absorbBarColor or (sfui.config and sfui.config.absorbBarColor)
        if color then
            absorbBar:SetStatusBarColor(color.r, color.g, color.b, color.a)
        end
    end

    local function GetSecondaryPowerBar()
        if secondary_power_bar then return secondary_power_bar end
        local bar = sfui.common.CreateBar("secondaryPowerBar", "StatusBar", UIParent)
        bar.TextValue = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bar.TextValue:SetFont("Fonts\\FRIZQT__.TTF", sfui.config.secondaryPowerBar.fontSize, "NONE")
        bar.TextValue:SetShadowOffset(1, -1)
        bar.TextValue:SetPoint("CENTER")
        secondary_power_bar = bar
        return bar
    end

    local function UpdateSecondaryPowerBar()
        local cfg = sfui.config.secondaryPowerBar
        if not cfg.enabled or IsDragonflying() then
            if secondary_power_bar and secondary_power_bar.backdrop then secondary_power_bar.backdrop:Hide() end
            return
        end

        local resource = sfui.common.GetSecondaryResource()
        -- Return early if no resource or invalid stats, preventing Bar creation
        if not resource then
            if secondary_power_bar and secondary_power_bar.backdrop then secondary_power_bar.backdrop:Hide() end
            return
        end

        local max, current = GetSecondaryResourceValue(resource)
        if not max or max <= 0 then
            if secondary_power_bar and secondary_power_bar.backdrop then secondary_power_bar.backdrop:Hide() end
            return
        end

        local bar = GetSecondaryPowerBar() -- Create ONLY if we have valid data

        if bar.backdrop then bar.backdrop:Show() end
        bar.TextValue:SetText(current)
        bar:SetMinMaxValues(0, max)
        bar:SetValue(current)
        local color
        if cfg.useClassColor then
            color = sfui.common.GetClassOrSpecColor()
        else
            color = sfui.common.GetResourceColor(resource)
        end
        if color then
            bar:SetStatusBarColor(color.r, color.g, color.b)
        end
    end

    local function CreateIcon(parent, name, size, spellID)
        local frame = CreateFrame("Frame", name, parent)
        frame:SetSize(size, size)

        local texture = frame:CreateTexture(nil, "BACKGROUND")
        texture:SetAllPoints()
        local spellTexture = C_Spell.GetSpellTexture(spellID)
        texture:SetTexture(spellTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- Zoom in slightly to remove borders
        frame.texture = texture

        local cd = CreateFrame("Cooldown", name .. "Cooldown", frame, "CooldownFrameTemplate")
        cd:SetAllPoints()
        frame.cooldown = cd

        -- Text for charges
        local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        text:SetPoint("TOP", frame, "BOTTOM", 0, -2) -- Below the icon
        frame.countText = text

        return frame
    end

    local function GetVigorBar()
        if vigor_bar then return vigor_bar end
        local bar = sfui.common.CreateBar("vigorBar", "StatusBar", UIParent)
        bar.TextValue = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bar.TextValue:SetFont("Fonts\\FRIZQT__.TTF", sfui.config.secondaryPowerBar.fontSize, "NONE")
        bar.TextValue:SetShadowOffset(1, -1)
        bar.TextValue:SetPoint("CENTER")

        local iconSize = 40
        -- Icons created but not positioned here anymore (handled in UpdateBarPositions)
        -- Whirling Surge Icon (Spell ID 361584)
        local wsIcon = CreateIcon(bar, "sfui_WhirlingSurgeIcon", iconSize, 361584)
        bar.whirlingSurgeIcon = wsIcon

        -- Second Wind Icon (Spell ID 425782)
        local swIcon = CreateIcon(bar, "sfui_SecondWindIcon", iconSize, 425782)
        bar.secondWindIcon = swIcon

        -- Static Charge Icon (Spell ID 418590)
        local scIcon = CreateIcon(bar, "sfui_StaticChargeIcon", iconSize, 418590)
        scIcon.countText:ClearAllPoints()
        scIcon.countText:SetPoint("CENTER", scIcon, "CENTER", 0, 0) -- Center text for this one
        bar.staticChargeIcon = scIcon
        bar.staticChargeIcon:Hide()                                 -- Hidden by default

        vigor_bar = bar
        return bar
    end

    local function UpdateVigorBar()
        local cfg = sfui.config.vigorBar
        if not cfg.enabled or not IsDragonflying() then
            if vigor_bar then
                vigor_bar.backdrop:Hide()
            end
            return
        end
        local bar = GetVigorBar()
        local chargesInfo = C_Spell.GetSpellCharges(372608)

        -- Update Charges
        if chargesInfo then
            bar:SetMinMaxValues(0, chargesInfo.maxCharges)
            bar:SetValue(chargesInfo.currentCharges)
            bar.TextValue:SetText(chargesInfo.currentCharges)
        end

        if cfg.color then
            bar:SetStatusBarColor(cfg.color[1], cfg.color[2], cfg.color[3])
        end

        -- Update Whirling Surge (361584) or Lightning Rush (418592)
        local surgeSpellID = 361584
        local isLightningRush = IsPlayerSpell(418592)

        if isLightningRush then
            surgeSpellID = 418592
        end

        -- Update Icon Texture dynamically
        local surgeTexture = C_Spell.GetSpellTexture(surgeSpellID)
        bar.whirlingSurgeIcon.texture:SetTexture(surgeTexture or "Interface\\Icons\\INV_Misc_QuestionMark")

        -- Revert desaturation logic (always saturated)
        bar.whirlingSurgeIcon.texture:SetDesaturated(false)
        -- Clear stack text from surge icon if any
        bar.whirlingSurgeIcon.countText:SetText("")

        local wsInfo = C_Spell.GetSpellCooldown(surgeSpellID)
        if wsInfo then
            bar.whirlingSurgeIcon.cooldown:SetCooldown(wsInfo.startTime, wsInfo.duration)
        end

        -- Update Static Charge (418590)
        local scAura = C_UnitAuras.GetPlayerAuraBySpellID(418590)
        if scAura and scAura.applications > 0 then
            bar.staticChargeIcon:Show()
            bar.staticChargeIcon.countText:SetText(scAura.applications)
        else
            bar.staticChargeIcon:Hide()
        end

        -- Update Second Wind Cooldown (425782)
        local swInfo = C_Spell.GetSpellCooldown(425782)
        local swCharges = C_Spell.GetSpellCharges(425782)
        if swInfo then
            bar.secondWindIcon.cooldown:SetCooldown(swInfo.startTime, swInfo.duration)
        end
        if swCharges then
            bar.secondWindIcon.countText:SetText(swCharges.currentCharges)
        else
            bar.secondWindIcon.countText:SetText("")
        end
    end

    local function GetMountSpeedBar()
        if mount_speed_bar then return mount_speed_bar end
        local bar = sfui.common.CreateBar("mountSpeedBar", "StatusBar", UIParent)
        bar.TextValue = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bar.TextValue:SetFont("Fonts\\FRIZQT__.TTF", 12, "NONE")
        bar.TextValue:SetShadowOffset(1, -1)
        bar.TextValue:SetPoint("CENTER")
        local elapsedSince = 0
        bar:SetScript("OnUpdate", function(self, elapsed)
            elapsedSince = elapsedSince + elapsed
            if elapsedSince > 0.1 then
                UpdateMountSpeedBarInternal()
                elapsedSince = 0
            end
        end)
        mount_speed_bar = bar
        return bar
    end

    UpdateMountSpeedBarInternal = function()
        local cfg = sfui.config.mountSpeedBar
        if not cfg.enabled or not IsDragonflying() then
            if mount_speed_bar then mount_speed_bar.backdrop:Hide() end
            return
        end
        local bar = mount_speed_bar or GetMountSpeedBar()
        local _, _, forwardSpeed = C_PlayerInfo.GetGlidingInfo()
        if not forwardSpeed then return end
        local speed = forwardSpeed * 14.286
        local maxSpeed = 1200
        bar:SetMinMaxValues(0, maxSpeed)
        bar:SetValue(speed)
        bar.TextValue:SetFormattedText("%d", speed)

        -- Thrill of the Skies check (377234)
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(377234)
        if aura then
            bar:SetStatusBarColor(1, 0, 1) -- #ff00ff (Magenta)
        else
            if cfg.color then
                bar:SetStatusBarColor(cfg.color[1], cfg.color[2], cfg.color[3])
            else
                bar:SetStatusBarColor(1, 1, 1) -- Default to White
            end
        end
    end

    sfui.bars.UpdateMountSpeedBar = UpdateMountSpeedBarInternal

    function sfui.bars:SetBarTexture(texturePath)
        if primary_power_bar then primary_power_bar:SetStatusBarTexture(texturePath) end
        if health_bar then
            health_bar:SetStatusBarTexture(texturePath)
            if health_bar.healPredBar then health_bar.healPredBar:SetStatusBarTexture(texturePath) end
            if health_bar.absorbBar then health_bar.absorbBar:SetStatusBarTexture(texturePath) end
        end
        if secondary_power_bar then secondary_power_bar:SetStatusBarTexture(texturePath) end
        if vigor_bar then vigor_bar:SetStatusBarTexture(texturePath) end
        if mount_speed_bar then mount_speed_bar:SetStatusBarTexture(texturePath) end
    end

    function sfui.bars:OnStateChanged()
        UpdatePrimaryPowerBar()
        local max, current = UnitHealthMax("player"), UnitHealth("player")
        UpdateHealthBar(current, max)
        UpdateSecondaryPowerBar()
        UpdateVigorBar()
        sfui.bars:UpdateMountSpeedBar() -- this one is public for the OnUpdate script
        UpdateBarVisibility()
    end

    local event_frame = CreateFrame("Frame")
    event_frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    event_frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    event_frame:RegisterEvent("UNIT_POWER_UPDATE")
    event_frame:RegisterEvent("UNIT_HEALTH")
    event_frame:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
    event_frame:RegisterEvent("PLAYER_CAN_GLIDE_CHANGED")
    event_frame:RegisterEvent("PLAYER_IS_GLIDING_CHANGED")
    event_frame:RegisterEvent("SPELL_UPDATE_CHARGES")
    event_frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    event_frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    event_frame:RegisterEvent("PLAYER_TARGET_CHANGED")

    event_frame:SetScript("OnEvent", function(self, event, unit, ...)
        if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM" or event == "PLAYER_CAN_GLIDE_CHANGED" or event == "PLAYER_IS_GLIDING_CHANGED" then
            sfui.bars:OnStateChanged()
        elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_TARGET_CHANGED" then
            UpdateBarVisibility()
        elseif event == "UNIT_POWER_UPDATE" and (not unit or unit == "player") then
            UpdatePrimaryPowerBar()
            UpdateSecondaryPowerBar()
        elseif (event == "UNIT_HEALTH" or event == "UNIT_ABSORB_AMOUNT_CHANGED") and (not unit or unit == "player") then
            local max, current = UnitHealthMax("player"), UnitHealth("player")
            UpdateHealthBar(current, max)
        elseif event == "SPELL_UPDATE_CHARGES" then
            UpdateVigorBar()
        end
    end)
end
