sfui = sfui or {}
sfui.bars = {}

do
    local primary_power_bar
    local secondary_power_bar
    local health_bar
    local vigor_bar
    local mount_speed_bar
    local UpdateMountSpeedBarInternal

    -- Throttling system for high-frequency events
    local throttle = {
        health = { lastUpdate = 0, interval = 0.05 },    -- 50ms throttle for health updates
        power = { lastUpdate = 0, interval = 0.05 },     -- 50ms throttle for power updates
        absorb = { lastUpdate = 0, interval = 0.1 },     -- 100ms throttle for absorb updates
        visibility = { lastUpdate = 0, interval = 0.1 }, -- 100ms throttle for visibility checks
    }

    local function should_throttle(key)
        local now = GetTime()
        local t = throttle[key]
        if now - t.lastUpdate >= t.interval then
            t.lastUpdate = now
            return false
        end
        return true
    end

    local function get_secondary_resource_value(resource)
        if not resource then return nil, nil end
        if resource == "STAGGER" then
            local stagger = UnitStagger("player") or 0
            local maxHealth = UnitHealthMax("player") or 1
            return maxHealth, stagger
        end
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

    local function is_dragonflying()
        local isFlying, canGlide, _ = C_PlayerInfo.GetGlidingInfo()
        local hasSkyridingBar = (GetBonusBarIndex() == 11 and GetBonusBarOffset() == 5)
        return isFlying or (canGlide and hasSkyridingBar)
    end

    local function update_bar_positions()
        local spacing = sfui.config.barLayout.spacing or 1

        if health_bar and health_bar.backdrop then
            health_bar.backdrop:ClearAllPoints()
            health_bar.backdrop:SetPoint("BOTTOM", UIParent, "BOTTOM", SfuiDB.healthBarX or 0, SfuiDB.healthBarY or 300)
        end

        if is_dragonflying() then
            if mount_speed_bar and mount_speed_bar.backdrop and vigor_bar and vigor_bar.backdrop then
                mount_speed_bar.backdrop:ClearAllPoints()
                mount_speed_bar.backdrop:SetPoint("TOP", vigor_bar.backdrop, "BOTTOM", 0, -spacing) -- Stack under and center with vigor bar

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
                vigor_bar.backdrop:SetPoint("BOTTOM", health_bar.backdrop, "TOP", 0, spacing)
            end
        else
            if primary_power_bar and primary_power_bar.backdrop and health_bar and health_bar.backdrop then
                primary_power_bar.backdrop:ClearAllPoints()
                primary_power_bar.backdrop:SetPoint("TOP", health_bar.backdrop, "BOTTOM", 0, -spacing)
            end
            if secondary_power_bar and secondary_power_bar.backdrop and health_bar and health_bar.backdrop then
                secondary_power_bar.backdrop:ClearAllPoints()
                secondary_power_bar.backdrop:SetPoint("BOTTOM", health_bar.backdrop, "TOP", 0, spacing)
            end
        end
    end

    local function update_bar_visibility()
        local isDragonflying = is_dragonflying()
        local inCombat = UnitAffectingCombat("player")
        local hasEnemyTarget = UnitCanAttack("player", "target")
        local showCoreBars = inCombat or hasEnemyTarget

        if isDragonflying then
            if vigor_bar and SfuiDB.enableVigorBar then
                vigor_bar.backdrop:Show()
            else
                if vigor_bar then
                    vigor_bar
                        .backdrop:Hide()
                end
            end
            if mount_speed_bar and SfuiDB.enableMountSpeedBar then
                mount_speed_bar.backdrop:Show()
            else
                if mount_speed_bar then
                    mount_speed_bar.backdrop:Hide()
                end
            end
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
            if secondary_power_bar and SfuiDB.enableSecondaryPowerBar then
                local hideSecondary = sfui.config.secondaryPowerBar.hiddenSpecs and
                    sfui.config.secondaryPowerBar.hiddenSpecs[specID]
                if IsMounted() or hideSecondary then
                    secondary_power_bar.backdrop:Hide()
                elseif showCoreBars and sfui.common.get_secondary_resource() then
                    secondary_power_bar.backdrop:Show()
                else
                    secondary_power_bar.backdrop:Hide()
                end
            elseif secondary_power_bar then
                secondary_power_bar.backdrop:Hide()
            end

            -- Health and Primary Power Bar visibility for non-dragonflying
            if showCoreBars then
                if health_bar and SfuiDB.enableHealthBar then
                    health_bar.backdrop:Show()
                elseif health_bar then
                    health_bar.backdrop:Hide()
                end
                local hide = sfui.config.powerBar.hiddenSpecs and sfui.config.powerBar.hiddenSpecs[specID]
                if primary_power_bar and SfuiDB.enablePowerBar then
                    if hide then
                        primary_power_bar.backdrop:Hide()
                    else
                        primary_power_bar.backdrop
                            :Show()
                    end
                elseif primary_power_bar then
                    primary_power_bar.backdrop:Hide()
                end
            else
                if health_bar then health_bar.backdrop:Hide() end
                if primary_power_bar then primary_power_bar.backdrop:Hide() end
            end
        end

        update_bar_positions()
    end

    local function get_primary_power_bar()
        if primary_power_bar then return primary_power_bar end
        local bar = sfui.common.create_bar("powerBar", "StatusBar", UIParent)
        bar:GetStatusBarTexture():SetHorizTile(true)

        local marker = bar:CreateTexture(nil, "OVERLAY")
        marker:SetColorTexture(1, 1, 1, 0.8)
        marker:SetWidth(2)
        marker:SetPoint("TOP", bar, "TOP")
        marker:SetPoint("BOTTOM", bar, "BOTTOM")
        marker:Hide()
        bar.marker = marker

        primary_power_bar = bar
        return bar
    end

    local function update_primary_power_bar()
        local cfg = sfui.config.powerBar
        local spec = C_SpecializationInfo.GetSpecialization()
        local specID = spec and select(1, C_SpecializationInfo.GetSpecializationInfo(spec)) or 0
        local hide = cfg.hiddenSpecs and cfg.hiddenSpecs[specID]

        if not cfg.enabled or is_dragonflying() or hide then
            if primary_power_bar and primary_power_bar.backdrop then primary_power_bar.backdrop:Hide() end
            return
        end
        local bar = get_primary_power_bar()
        local resource = sfui.common.get_primary_resource()
        if not resource then return end
        local max, current = UnitPowerMax("player", resource), UnitPower("player", resource)
        if not max or max <= 0 then return end
        bar:SetMinMaxValues(0, max)
        bar:SetValue(current)
        local color = sfui.common.get_class_or_spec_color()
        if color then bar:SetStatusBarColor(color.r, color.g, color.b) end

        -- Marker logic (Shadow Priest 55% threshold)
        if specID == 258 then
            bar.marker:ClearAllPoints()
            bar.marker:SetPoint("LEFT", bar, "LEFT", bar:GetWidth() * 0.55, 0)
            bar.marker:SetHeight(bar:GetHeight())
            bar.marker:Show()
        else
            bar.marker:Hide()
        end
    end

    -- UpdateFillPosition removed (Secret Values cannot be used in arithmetic).
    -- We rely on StatusBar:SetValue() to handle secure values internally.

    local function get_health_bar()
        if health_bar then return health_bar end
        local bar = sfui.common.create_bar("healthBar", "StatusBar", UIParent)
        bar:GetStatusBarTexture():SetHorizTile(true)
        health_bar = bar

        local textureName = SfuiDB.barTexture
        local LSM = LibStub("LibSharedMedia-3.0", true)
        local texturePath
        if LSM then
            texturePath = LSM:Fetch("statusbar", textureName)
        end
        if not texturePath or texturePath == "" then
            texturePath = sfui.config.barTexture
        end

        local healPredBar = CreateFrame("StatusBar", nil, bar)
        healPredBar:SetFrameLevel(bar:GetFrameLevel() + 1)
        healPredBar:SetStatusBarTexture(texturePath)
        healPredBar:SetStatusBarColor(0.0, 0.8, 0.6, 0.5)
        healPredBar:GetStatusBarTexture():SetBlendMode("ADD")
        bar.healPredBar = healPredBar

        local absorbBar = CreateFrame("StatusBar", nil, bar)
        absorbBar:SetFrameLevel(bar:GetFrameLevel() + 2)
        absorbBar:SetStatusBarTexture(texturePath)
        absorbBar:GetStatusBarTexture():SetBlendMode("ADD")
        bar.absorbBar = absorbBar
        return bar
    end

    local function update_health_bar(current, maxVal)
        local cfg = sfui.config.healthBar
        if not cfg.enabled then return end
        local bar = get_health_bar()
        -- current and max are passed in now
        if not maxVal or maxVal <= 0 then return end
        bar:SetMinMaxValues(0, maxVal)
        bar:SetValue(current)

        if cfg.color then
            bar:SetStatusBarColor(cfg.color[1], cfg.color[2], cfg.color[3], cfg.color[4] or 1)
        end

        local width, height = bar:GetSize()
        local healPred = bar.healPredBar
        healPred:SetSize(width, height)
        healPred:SetMinMaxValues(0, maxVal)
        healPred:ClearAllPoints()
        healPred:SetPoint("TOPLEFT", bar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)

        local incomingHeals = UnitGetIncomingHeals("player") or 0
        healPred:SetValue(incomingHeals)

        local absorbBar = bar.absorbBar
        absorbBar:SetSize(width, height); absorbBar:SetMinMaxValues(0, maxVal)
        absorbBar:ClearAllPoints()
        absorbBar:SetPoint("TOPLEFT", healPred:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        local absorbAmount = UnitGetTotalAbsorbs("player") or 0
        absorbBar:SetValue(absorbAmount)
        local color = SfuiDB.absorbBarColor or (sfui.config and sfui.config.absorbBarColor)
        if color then absorbBar:SetStatusBarColor(color.r, color.g, color.b, color.a) end
    end

    local function get_secondary_power_bar()
        if secondary_power_bar then return secondary_power_bar end
        local bar = sfui.common.create_bar("secondaryPowerBar", "StatusBar", UIParent)
        bar.TextValue = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bar.TextValue:SetFont("Fonts\\FRIZQT__.TTF", sfui.config.secondaryPowerBar.fontSize, "NONE")
        bar.TextValue:SetShadowOffset(1, -1)
        bar.TextValue:SetPoint("CENTER")
        secondary_power_bar = bar
        return bar
    end

    local function update_secondary_power_bar()
        local cfg = sfui.config.secondaryPowerBar
        local spec = C_SpecializationInfo.GetSpecialization()
        local specID = spec and select(1, C_SpecializationInfo.GetSpecializationInfo(spec)) or 0
        local hide = cfg.hiddenSpecs and cfg.hiddenSpecs[specID]

        if not cfg.enabled or is_dragonflying() or hide then
            if secondary_power_bar and secondary_power_bar.backdrop then secondary_power_bar.backdrop:Hide() end
            return
        end

        local resource = sfui.common.get_secondary_resource()
        if not resource then
            if secondary_power_bar and secondary_power_bar.backdrop then secondary_power_bar.backdrop:Hide() end
            return
        end

        local max, current = get_secondary_resource_value(resource)
        if not max or max <= 0 then
            if secondary_power_bar and secondary_power_bar.backdrop then secondary_power_bar.backdrop:Hide() end
            return
        end

        local bar = get_secondary_power_bar()
        if bar.backdrop then bar.backdrop:Show() end
        bar.TextValue:SetText(current)
        bar:SetMinMaxValues(0, max)
        bar:SetValue(current)
        local color
        if cfg.useClassColor then
            color = sfui.common.get_class_or_spec_color()
        else
            color = sfui.common.get_resource_color(resource)
        end
        if color then
            bar:SetStatusBarColor(color.r, color.g, color.b)
        end
    end

    local function create_icon(parent, name, size, spellID)
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

        local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        text:SetPoint("TOP", frame, "BOTTOM", 0, -2)
        frame.countText = text

        return frame
    end

    local function get_vigor_bar()
        if vigor_bar then return vigor_bar end
        local bar = sfui.common.create_bar("vigorBar", "StatusBar", UIParent)
        bar.TextValue = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bar.TextValue:SetFont("Fonts\\FRIZQT__.TTF", sfui.config.secondaryPowerBar.fontSize, "NONE")
        bar.TextValue:SetShadowOffset(1, -1); bar.TextValue:SetPoint("CENTER")
        local iconSize = 40
        bar.whirlingSurgeIcon = create_icon(bar, "sfui_WhirlingSurgeIcon", iconSize, 361584)
        bar.secondWindIcon = create_icon(bar, "sfui_SecondWindIcon", iconSize, 425782)
        bar.staticChargeIcon = create_icon(bar, "sfui_StaticChargeIcon", iconSize, 418590)
        bar.staticChargeIcon.countText:ClearAllPoints()
        bar.staticChargeIcon.countText:SetPoint("CENTER", bar.staticChargeIcon, "CENTER", 0, 0)
        bar.staticChargeIcon:Hide()
        vigor_bar = bar
        return bar
    end

    local function update_vigor_bar()
        local cfg = sfui.config.vigorBar
        if not cfg.enabled or not is_dragonflying() then
            if vigor_bar then
                vigor_bar.backdrop:Hide()
            end
            return
        end
        local bar = get_vigor_bar()
        local chargesInfo = C_Spell.GetSpellCharges(372608)
        if chargesInfo then
            bar:SetMinMaxValues(0, chargesInfo.maxCharges)
            bar:SetValue(chargesInfo.currentCharges)
            bar.TextValue:SetText(chargesInfo.currentCharges)
        end

        if cfg.color then
            bar:SetStatusBarColor(cfg.color[1], cfg.color[2], cfg.color[3])
        end

        local surgeSpellID = IsPlayerSpell(418592) and 418592 or 361584

        local surgeTexture = C_Spell.GetSpellTexture(surgeSpellID)
        bar.whirlingSurgeIcon.texture:SetTexture(surgeTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
        bar.whirlingSurgeIcon.texture:SetDesaturated(false)
        bar.whirlingSurgeIcon.countText:SetText("")

        local wsInfo = C_Spell.GetSpellCooldown(surgeSpellID)
        if wsInfo then
            bar.whirlingSurgeIcon.cooldown:SetCooldown(wsInfo.startTime, wsInfo.duration)
        end

        local scAura = C_UnitAuras.GetPlayerAuraBySpellID(418590)
        if scAura and scAura.applications > 0 then
            bar.staticChargeIcon:Show(); bar.staticChargeIcon.countText:SetText(scAura.applications)
        else
            bar.staticChargeIcon:Hide()
        end

        local swInfo = C_Spell.GetSpellCooldown(425782)
        local swCharges = C_Spell.GetSpellCharges(425782)
        if swInfo then bar.secondWindIcon.cooldown:SetCooldown(swInfo.startTime, swInfo.duration) end
        bar.secondWindIcon.countText:SetText(swCharges and swCharges.currentCharges or "")
    end

    local function get_mount_speed_bar()
        if mount_speed_bar then return mount_speed_bar end
        local bar = sfui.common.create_bar("mountSpeedBar", "StatusBar", UIParent)
        bar.TextValue = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bar.TextValue:SetFont("Fonts\\FRIZQT__.TTF", 12, "NONE")
        bar.TextValue:SetShadowOffset(1, -1)
        bar.TextValue:SetPoint("CENTER")
        local elapsedSince = 0
        bar:SetScript("OnUpdate", function(self, elapsed)
            elapsedSince = elapsedSince + elapsed
            if elapsedSince > 0.1 then
                update_mount_speed_bar_internal()
                elapsedSince = 0
            end
        end)
        mount_speed_bar = bar
        return bar
    end

    update_mount_speed_bar_internal = function()
        local cfg = sfui.config.mountSpeedBar
        if not cfg.enabled or not is_dragonflying() then
            if mount_speed_bar then mount_speed_bar.backdrop:Hide() end
            return
        end
        local bar = mount_speed_bar or get_mount_speed_bar()
        local _, _, forwardSpeed = C_PlayerInfo.GetGlidingInfo()
        if not forwardSpeed then return end
        local speed = forwardSpeed * 14.286
        local maxSpeed = 1200
        bar:SetMinMaxValues(0, maxSpeed)
        bar:SetValue(speed)
        bar.TextValue:SetFormattedText("%d", speed)

        local aura = C_UnitAuras.GetPlayerAuraBySpellID(377234)
        if aura then
            bar:SetStatusBarColor(1, 0, 1)
        else
            if cfg.color then
                bar:SetStatusBarColor(cfg.color[1], cfg.color[2], cfg.color[3])
            else
                bar:SetStatusBarColor(1, 1, 1) -- Default to White
            end
        end
    end

    sfui.bars.update_mount_speed_bar = update_mount_speed_bar_internal

    function sfui.bars:set_bar_texture(texturePath)
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

    function sfui.bars:on_state_changed()
        update_primary_power_bar()
        local max, current = UnitHealthMax("player"), UnitHealth("player")
        update_health_bar(current, max)
        update_secondary_power_bar()
        update_vigor_bar()
        sfui.bars:update_mount_speed_bar()
        update_bar_visibility()
    end

    function sfui.bars:update_health_bar_position()
        update_bar_positions()
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
            sfui.bars:on_state_changed()
        elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_TARGET_CHANGED" then
            if not should_throttle("visibility") then
                update_bar_visibility()
            end
        elseif event == "UNIT_POWER_UPDATE" and (not unit or unit == "player") then
            if not should_throttle("power") then
                update_primary_power_bar()
                update_secondary_power_bar()
            end
        elseif (event == "UNIT_HEALTH" or event == "UNIT_ABSORB_AMOUNT_CHANGED") and (not unit or unit == "player") then
            if not should_throttle("health") then
                local max, current = UnitHealthMax("player"), UnitHealth("player")
                update_health_bar(current, max)
            end
        elseif event == "SPELL_UPDATE_CHARGES" then
            update_vigor_bar()
        end
    end)
end
