local addonName, addon = ...
sfui = sfui or {}
sfui.bars = {}
local cfg = sfui.config
local common = sfui.common
local issecretvalue = common.issecretvalue or _G.issecretvalue

do
    local bar_minus_1
    local bar1
    local bar0
    local vigor_bar
    local mount_speed_bar
    local rune_bar
    local get_bar0
    local get_bar_minus_1
    local get_bar1
    local get_vigor_bar
    local get_mount_speed_bar
    local update_mount_speed_bar_internal
    local update_bar_minus_1
    local update_bar0
    local update_bar1
    local update_rune_bar
    local update_vigor_bar

    -- 5-Second Rule (MP5 Regen Timer) for Vanilla / Classic / Camelot
    local fsrEndTime = 0
    local start_fsr_timer
    local stop_fsr_timer

    -- Throttling system for high-frequency events
    local tCfg = cfg.throttle
    local throttle = {
        bar0 = { lastUpdate = 0, interval = tCfg.health },
        bar_minus_1 = { lastUpdate = 0, interval = tCfg.power },
        absorb = { lastUpdate = 0, interval = tCfg.absorb },
        visibility = { lastUpdate = 0, interval = tCfg.visibility },
        runes = { lastUpdate = 0, interval = 0.05 },
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

    local function is_player_spell(id)
        if IsPlayerSpell then return IsPlayerSpell(id) end
        return (C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id, Enum.SpellBookSpellBank.Player)) or false
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
        if resource == "FURY" then
            local current = UnitPower("player", Enum.PowerType.Fury)
            local max = UnitPowerMax("player", Enum.PowerType.Fury)
            if max <= 0 then return nil, nil end
            return max, current
        end
        local current = UnitPower("player", resource)
        local max = UnitPowerMax("player", resource)
        if max <= 0 then return nil, nil end
        return max, current
    end

    local is_dragonflying = common.is_dragonflying
    local is_in_vehicle = common.is_in_vehicle
    local invalidate_dragonflying_cache = common.invalidate_dragonflying_cache

    local function update_bar_positions()
        local spacing = cfg.barLayout.spacing

        if bar0 and bar0.backdrop then
            bar0.backdrop:ClearAllPoints()
            local cfg = sfui.config.healthBar
            bar0.backdrop:SetPoint("BOTTOM", UIParent, "BOTTOM", SfuiDB.healthBarX or cfg.pos.x,
                SfuiDB.healthBarY or cfg.pos.y)
        end

        if is_dragonflying() then
            if mount_speed_bar and mount_speed_bar.backdrop and vigor_bar and vigor_bar.backdrop then
                mount_speed_bar.backdrop:ClearAllPoints()
                mount_speed_bar.backdrop:SetPoint("TOP", vigor_bar.backdrop, "BOTTOM", 0, -spacing) -- Stack under and center with vigor bar

                if vigor_bar.whirlingSurgeIcon and vigor_bar.secondWindIcon then
                    local iconCfg = cfg.vigorBar.icons
                    local gap = iconCfg.gap
                    vigor_bar.whirlingSurgeIcon:ClearAllPoints()
                    vigor_bar.whirlingSurgeIcon:SetPoint("TOPRIGHT", mount_speed_bar.backdrop, "BOTTOM", -gap / 2,
                        iconCfg.offsetY)
                    vigor_bar.secondWindIcon:ClearAllPoints()
                    vigor_bar.secondWindIcon:SetPoint("TOPLEFT", mount_speed_bar.backdrop, "BOTTOM", gap / 2,
                        iconCfg.offsetY)

                    if vigor_bar.staticChargeIcon then
                        vigor_bar.staticChargeIcon:ClearAllPoints()
                        vigor_bar.staticChargeIcon:SetPoint("LEFT", vigor_bar.backdrop, "RIGHT", iconCfg.sideOffset, 0)
                    end
                end
            end
            if vigor_bar and vigor_bar.backdrop and bar0 and bar0.backdrop then
                vigor_bar.backdrop:ClearAllPoints()
                vigor_bar.backdrop:SetPoint("BOTTOM", bar0.backdrop, "TOP", 0, spacing)
            end
        else
            if bar_minus_1 and bar_minus_1.backdrop and bar0 and bar0.backdrop then
                bar_minus_1.backdrop:ClearAllPoints()
                bar_minus_1.backdrop:SetPoint("TOP", bar0.backdrop, "BOTTOM", 0, -spacing)
            end
            if bar1 and bar1.backdrop and bar0 and bar0.backdrop then
                bar1.backdrop:ClearAllPoints()
                bar1.backdrop:SetPoint("BOTTOM", bar0.backdrop, "TOP", 0, spacing)
            end
            if rune_bar and bar0 and bar0.backdrop then
                rune_bar:ClearAllPoints()
                rune_bar:SetPoint("BOTTOM", bar0.backdrop, "TOP", 0, spacing)
            end

            -- Swing Timer Bars (slotting below power bar at -2, or below health at -1 if no power bar)
            if sfui.swing and sfui.swing.UpdatePositions then
                local anchor = (bar_minus_1 and bar_minus_1.backdrop and (bar_minus_1.backdrop:IsShown() or (SfuiDB == nil or SfuiDB.enablePowerBar ~= false))) and bar_minus_1.backdrop or (bar0 and bar0.backdrop)
                sfui.swing.UpdatePositions(anchor, spacing)
            end
        end
        if sfui.soulfragments and sfui.soulfragments.UpdatePosition then
            sfui.soulfragments:UpdatePosition()
        end
        if sfui.trackedbars and sfui.trackedbars.ForceLayoutUpdate then
            sfui.trackedbars.ForceLayoutUpdate()
        end
        if sfui.trackedicons and sfui.trackedicons.ForceLayoutUpdate then
            sfui.trackedicons.ForceLayoutUpdate()
        elseif sfui.trackedicons and sfui.trackedicons.MarkDirty then
            sfui.trackedicons.MarkDirty(true)
        end
    end

    local function update_bar_visibility()
        local isDragonflying = is_dragonflying()
        local inVehicle = is_in_vehicle()
        local inCombat = UnitAffectingCombat("player")
        local hasEnemyTarget = UnitCanAttack("player", "target")
        local isFsrActive = sfui.isClassic and (fsrEndTime and fsrEndTime > GetTime()) or false
        local showCoreBars = (not inVehicle) and (inCombat or hasEnemyTarget or isFsrActive)

        if isDragonflying then
            local showVigor = (SfuiDB == nil or SfuiDB.enableVigorBar ~= false)
            if showVigor then
                local bar = get_vigor_bar()
                bar.backdrop:Show()
            elseif vigor_bar then
                vigor_bar.backdrop:Hide()
            end

            local showSpeed = (SfuiDB == nil or SfuiDB.enableMountSpeedBar ~= false)
            if showSpeed then
                local bar = get_mount_speed_bar()
                bar.backdrop:Show()
            elseif mount_speed_bar then
                mount_speed_bar.backdrop:Hide()
            end
            if bar0 then bar0.backdrop:Hide() end
            if bar_minus_1 then bar_minus_1.backdrop:Hide() end
            if bar1 then bar1.backdrop:Hide() end
            if rune_bar then rune_bar:Hide() end
        elseif inVehicle then
            if vigor_bar then vigor_bar.backdrop:Hide() end
            if mount_speed_bar then mount_speed_bar.backdrop:Hide() end
            if bar0 then bar0.backdrop:Hide() end
            if bar_minus_1 then bar_minus_1.backdrop:Hide() end
            if bar1 then bar1.backdrop:Hide() end
            if rune_bar then rune_bar:Hide() end
        else
            local specID = common.get_current_spec_id()

            -- Core Bars Visibility (Health, Power, Secondary Power)
            if showCoreBars then
                -- Health Bar (bar0)
                if bar0 and SfuiDB.enableHealthBar then
                    bar0.backdrop:Show()
                elseif bar0 then
                    bar0.backdrop:Hide()
                end

                -- Primary Power Bar (bar_minus_1)
                local hidePower = cfg.powerBar.hiddenSpecs and cfg.powerBar.hiddenSpecs[specID]
                local showPower = (SfuiDB == nil or SfuiDB.enablePowerBar ~= false) and not hidePower
                if showPower then
                    local bar = get_bar_minus_1()
                    bar.backdrop:Show()
                elseif bar_minus_1 then
                    bar_minus_1.backdrop:Hide()
                end

                -- Secondary Power Bar (bar1)
                local hideSecondary = cfg.secondaryPowerBar.hiddenSpecs and
                    cfg.secondaryPowerBar.hiddenSpecs[specID]
                local secResource = common.get_secondary_resource()
                local showSecondary = (SfuiDB == nil or SfuiDB.enableSecondaryPowerBar ~= false) and not hideSecondary and secResource and secResource ~= Enum.PowerType.Runes

                if showSecondary then
                    local bar = get_bar1()
                    bar.backdrop:Show()
                elseif bar1 then
                    bar1.backdrop:Hide()
                end

                -- Rune Bar
                local isRune = (secResource == Enum.PowerType.Runes)
                if rune_bar and isRune and SfuiDB.enableSecondaryPowerBar then
                    rune_bar:Show()
                    update_rune_bar()
                elseif rune_bar then
                    rune_bar:Hide()
                end

                -- Refresh shown bars so values are immediately accurate
                if bar0 and bar0.backdrop and bar0.backdrop:IsShown() then
                    local max, current = UnitHealthMax("player"), UnitHealth("player")
                    update_bar0(current, max)
                end
                if bar_minus_1 and bar_minus_1.backdrop and bar_minus_1.backdrop:IsShown() then
                    update_bar_minus_1()
                end
                if bar1 and bar1.backdrop and bar1.backdrop:IsShown() then
                    update_bar1()
                end
            else
                if bar0 then bar0.backdrop:Hide() end
                if bar_minus_1 then bar_minus_1.backdrop:Hide() end
                if bar1 then bar1.backdrop:Hide() end
                if rune_bar then rune_bar:Hide() end
            end
        end

        if sfui.swing and sfui.swing.UpdateVisibility then
            sfui.swing.UpdateVisibility(inCombat, hasEnemyTarget, isDragonflying, inVehicle)
        end

        update_bar_positions()
    end

    function get_bar_minus_1()
        if bar_minus_1 then return bar_minus_1 end
        local bar = common.create_bar("bar_minus_1", "StatusBar", UIParent, nil, "powerBar")

        local marker = bar:CreateTexture(nil, "OVERLAY")
        marker:SetColorTexture(1, 1, 1, 0.8)
        marker:SetWidth(2)
        marker:SetPoint("TOP", bar, "TOP")
        marker:SetPoint("BOTTOM", bar, "BOTTOM")
        marker:Hide()
        bar.marker = marker

        -- Vanilla / Camelot: 5-Second Rule (MP5 regen) countdown timer (no outline, no shadow, 1 decimal)
        if sfui.isClassic then
            local fsrText = bar:CreateFontString(nil, "OVERLAY")
            local fontSize = (cfg.powerBar and cfg.powerBar.fontSize) or 10
            fsrText:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "")
            fsrText:SetShadowOffset(0, 0)
            fsrText:SetPoint("CENTER", bar, "CENTER", 0, 0)
            fsrText:SetTextColor(1, 1, 1, 0.9)
            fsrText:Hide()
            bar.fsrTimerText = fsrText
        end

        bar_minus_1 = bar
        return bar
    end

    local function spell_costs_mana(spellID)
        if not spellID then return false end
        local getCost = (C_Spell and C_Spell.GetSpellPowerCost) or _G.GetSpellPowerCost
        if not getCost then return false end

        local costTable = getCost(spellID)
        if not costTable or type(costTable) ~= "table" then return false end

        for _, costInfo in pairs(costTable) do
            local costType = costInfo.type or costInfo.powerType
            local isMana = (costType == 0 or costType == Enum.PowerType.Mana or costInfo.name == "MANA")
            if isMana then
                local reqAura = costInfo.requiredAuraID
                local hasAura = costInfo.hasRequiredAura
                if not (reqAura and reqAura > 0 and hasAura == false) then
                    local cost = costInfo.cost or costInfo.minCost or costInfo.costPercent or costInfo.costPerSec or 0
                    if (type(cost) == "number" and cost > 0) or (common.issecretvalue and common.issecretvalue(cost)) then
                        return true
                    end
                end
            end
        end
        return false
    end

    function stop_fsr_timer()
        local wasActive = fsrEndTime > 0
        fsrEndTime = 0
        if bar_minus_1 then
            if bar_minus_1._fsrOnUpdateActive then
                bar_minus_1:SetScript("OnUpdate", nil)
                bar_minus_1._fsrOnUpdateActive = false
            end
            if bar_minus_1.fsrTimerText then
                bar_minus_1.fsrTimerText:SetText("")
                bar_minus_1.fsrTimerText:Hide()
            end
        end
        if wasActive then
            update_bar_visibility()
        end
    end

    local function on_fsr_update(self, elapsed)
        self._fsrThrottle = (self._fsrThrottle or 0) + elapsed
        if self._fsrThrottle < 0.05 then return end
        self._fsrThrottle = 0

        local now = GetTime()
        local remaining = fsrEndTime - now

        local isClassic = sfui.isClassic or (sfui.compat and (sfui.compat.has.wow_forever or sfui.compat.is_classic_era or sfui.compat.is_classic))
        local resource = common.get_primary_resource()
        if resource == nil and UnitPowerType then
            resource = UnitPowerType("player")
        end

        local isMana = (resource == 0 or resource == Enum.PowerType.Mana)

        if not isClassic or not isMana or remaining <= 0 then
            stop_fsr_timer()
            return
        end

        if self.fsrTimerText then
            self.fsrTimerText:SetFormattedText("%.1f", remaining)
            if not self.fsrTimerText:IsShown() then
                self.fsrTimerText:Show()
            end
        end
    end

    function start_fsr_timer()
        local isClassic = sfui.isClassic or (sfui.compat and (sfui.compat.has.wow_forever or sfui.compat.is_classic_era or sfui.compat.is_classic))
        if not isClassic then return end

        local resource = common.get_primary_resource()
        if resource == nil and UnitPowerType then
            resource = UnitPowerType("player")
        end
        local isMana = (resource == 0 or resource == Enum.PowerType.Mana)
        if not isMana then return end

        fsrEndTime = GetTime() + 5.0
        local bar = get_bar_minus_1()
        if bar then
            bar._fsrThrottle = 0
            if bar.fsrTimerText then
                bar.fsrTimerText:SetFormattedText("%.1f", 5.0)
                bar.fsrTimerText:Show()
            end
            if not bar._fsrOnUpdateActive then
                bar:SetScript("OnUpdate", on_fsr_update)
                bar._fsrOnUpdateActive = true
            end
            update_bar_visibility()
        end
    end

    function update_bar_minus_1()
        local cfg = sfui.config.powerBar
        local specID = common.get_current_spec_id()
        local hide = cfg.hiddenSpecs and cfg.hiddenSpecs[specID]

        if not cfg.enabled or is_dragonflying() or hide then
            if bar_minus_1 and bar_minus_1.backdrop then bar_minus_1.backdrop:Hide() end
            stop_fsr_timer()
            return
        end
        local bar = get_bar_minus_1()
        local resource = common.get_primary_resource()
        if resource == nil and UnitPowerType then
            resource = UnitPowerType("player")
        end
        resource = resource or 0
        if resource ~= 0 and resource ~= Enum.PowerType.Mana then
            stop_fsr_timer()
        end
        local max, current = UnitPowerMax("player", resource), UnitPower("player", resource)
        if not max or (not (common.issecretvalue and common.issecretvalue(max)) and max <= 0) then return end
        -- Note: UnitPower/UnitPowerMax return secret values in vehicle/M+ contexts.
        -- Comparing them with == taints execution. SetValue handles secret values
        -- internally in the C engine, so we always pass them through unconditionally.
        bar:SetMinMaxValues(0, max)
        bar:SetValue(current)
        local color
        if cfg.useClassColor then
            color = common.get_class_or_spec_color()
        else
            color = common.get_resource_color(resource)
        end
        if color then
            local r, g, b = common.unpack_color(color)
            bar:SetStatusBarColor(r, g, b)
        end

        -- Marker logic
        if specID == 258 then -- Shadow Priest (55% threshold)
            bar.marker:ClearAllPoints()
            bar.marker:SetPoint("LEFT", bar, "LEFT", bar:GetWidth() * 0.55, 0)
            bar.marker:SetHeight(bar:GetHeight())
            bar.marker:Show()
        elseif specID == 1480 and max and max > 99 then -- Devourer Demon Hunter (100 value)
            bar.marker:ClearAllPoints()
            local width = bar:GetWidth()
            local pct = 100 / max
            bar.marker:SetPoint("LEFT", bar, "LEFT", width * pct, 0)
            bar.marker:SetHeight(bar:GetHeight())
            bar.marker:Show()
        else
            bar.marker:Hide()
        end
    end

    -- UpdateFillPosition removed (Secret Values cannot be used in arithmetic).
    -- We rely on StatusBar:SetValue() to handle secure values internally.

    function get_bar0()
        if bar0 then return bar0 end
        local bar = common.create_bar("bar0", "StatusBar", UIParent, nil, "healthBar")
        bar0 = bar

        local textureName = SfuiDB and SfuiDB.barTexture
        local LSM = LibStub("LibSharedMedia-3.0", true)
        local texturePath
        if LSM and textureName then
            texturePath = LSM:Fetch("statusbar", textureName)
        end
        if not texturePath or texturePath == "" then
            texturePath = cfg.barTexture
        end
        if texturePath and texturePath ~= "" then
            bar:SetStatusBarTexture(texturePath)
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

    function update_bar0(current, maxVal)
        local cfg = sfui.config.healthBar
        if not cfg.enabled then return end
        local bar = get_bar0()
        -- current and max are passed in now
        if not maxVal or maxVal <= 0 then return end
        bar:SetMinMaxValues(0, maxVal)
        bar:SetValue(current)

        local fgColor = SfuiDB.healthBarColor or cfg.color
        if fgColor then
            bar:SetStatusBarColor(fgColor[1], fgColor[2], fgColor[3], fgColor[4] or 1)
        end

        local bgColor = SfuiDB.healthBarBackdropColor or cfg.backdrop.color
        if bgColor and bar.backdrop then
            bar.backdrop:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.5)
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
        local color = SfuiDB.absorbBarColor or (cfg and cfg.absorbBarColor)
        absorbBar:SetStatusBarColor(common.unpack_color(color))
    end

    local function get_rune_bar()
        if rune_bar then return rune_bar end
        local container = CreateFrame("Frame", "sfui_runeBar", UIParent)
        container:SetHeight(20)

        container.runes = {}

        -- Resolve texture once
        local textureName = SfuiDB.barTexture
        local LSM = LibStub("LibSharedMedia-3.0", true)
        local texturePath
        if LSM then
            texturePath = LSM:Fetch("statusbar", textureName)
        end
        if not texturePath or texturePath == "" then
            texturePath = cfg.barTexture
        end

        for i = 1, 6 do
            local rune = CreateFrame("StatusBar", nil, container, "BackdropTemplate")
            rune:SetStatusBarTexture(texturePath)
            rune:SetStatusBarColor(1, 1, 1) -- Set later

            rune:SetBackdrop({
                bgFile = "Interface/Buttons/WHITE8X8",
                edgeFile = "Interface/Buttons/WHITE8X8",
                edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 }
            })
            rune:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
            rune:SetBackdropBorderColor(0, 0, 0, 1)

            container.runes[i] = rune
        end

        -- Rune updates are handled by RUNE_POWER_UPDATE event (line 716, 737-740)
        -- OnUpdate removed to eliminate 20fps polling overhead

        rune_bar = container
        return rune_bar
    end

    -- Pre-allocated comparator to avoid closure allocation on every table.sort call
    local function runeInfoComparator(a, b)
        if a.ready and not b.ready then return true end
        if not a.ready and b.ready then return false end
        if not a.ready and not b.ready then
            return a.expiration < b.expiration
        end
        return a.id < b.id
    end

    function update_rune_bar()
        local secResource = common.get_secondary_resource()
        if secResource ~= Enum.PowerType.Runes then
            if rune_bar then rune_bar:Hide() end
            return
        end

        local bar = get_rune_bar()

        local healthWidth = cfg.healthBar.width
        local maxTotalWidth = healthWidth * 0.8
        local spacing = 2
        local numRunes = 6

        -- Integer division for perfect pixel alignment
        local runeWidth = math.floor((maxTotalWidth - (spacing * (numRunes - 1))) / numRunes)
        local usedWidth = (runeWidth * numRunes) + (spacing * (numRunes - 1))

        local runeHeight = 10

        bar:SetSize(usedWidth, runeHeight)

        -- Update tracked bars layout to respect Rune Bar presence
        if sfui.trackedbars and sfui.trackedbars.ForceLayoutUpdate then
            sfui.trackedbars.ForceLayoutUpdate()
        end

        -- Sorting Logic — reuse pre-allocated table to avoid GC pressure
        local runeInfo = bar._runeInfo
        if not runeInfo then
            runeInfo = {}
            for i = 1, 6 do runeInfo[i] = { id = i, ready = false, expiration = 0, start = 0, duration = 0 } end
            bar._runeInfo = runeInfo
        end
        for i = 1, 6 do
            local start, duration, ready = GetRuneCooldown(i)
            local entry = runeInfo[i]
            entry.id = i
            entry.ready = ready
            entry.start = start or 0
            entry.duration = duration or 0
            entry.expiration = (not ready) and (start + duration) or 0
        end

        table.sort(runeInfo, runeInfoComparator)


        local specColor = common.get_class_or_spec_color()

        -- Position frames according to sorted order
        for pos = 1, 6 do
            local info = runeInfo[pos]
            local rune = bar.runes[info.id] -- Get the actual frame for this rune ID

            rune:SetSize(runeWidth, runeHeight)
            rune:ClearAllPoints()
            if pos == 1 then
                rune:SetPoint("LEFT", bar, "LEFT", 0, 0)
            else
                -- Point to the previously positioned rune
                local prevInfo = runeInfo[pos - 1]
                local prevRune = bar.runes[prevInfo.id]
                rune:SetPoint("LEFT", prevRune, "RIGHT", spacing, 0)
            end

            -- Store state on the frame for OnUpdate
            rune.start = info.start
            rune.duration = info.duration
            rune.ready = info.ready

            -- Set Colors
            if info.ready then
                if specColor then
                    local r, g, b = common.unpack_color(specColor)
                    rune:SetStatusBarColor(r, g, b)
                else
                    rune:SetStatusBarColor(1, 0.2, 0.3)
                end
                rune:SetMinMaxValues(0, 1)
                rune:SetValue(1)
            else
                -- Charging: #444444 (Lighter Grey)
                rune:SetStatusBarColor(0.266, 0.266, 0.266)
                rune:SetMinMaxValues(0, info.duration)
                local current = GetTime() - info.start
                rune:SetValue(current)
            end
        end
    end

    function get_bar1()
        if bar1 then return bar1 end
        local bar = common.create_bar("bar1", "StatusBar", UIParent, nil, "secondaryPowerBar")
        bar.TextValue = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bar.TextValue:SetFont("Fonts\\FRIZQT__.TTF", cfg.secondaryPowerBar.fontSize, "")
        bar.TextValue:SetShadowOffset(1, -1)
        bar.TextValue:SetPoint("CENTER")
        bar1 = bar
        return bar
    end

    function update_bar1()
        local cfg = sfui.config.secondaryPowerBar
        local specID = common.get_current_spec_id()
        local hide = cfg.hiddenSpecs and cfg.hiddenSpecs[specID]

        if not cfg.enabled or is_dragonflying() or hide then
            if bar1 and bar1.backdrop then bar1.backdrop:Hide() end
            return
        end

        local resource = common.get_secondary_resource()

        if resource == Enum.PowerType.Runes then
            if bar1 and bar1.backdrop then bar1.backdrop:Hide() end
            return
        end

        if not resource then
            if bar1 and bar1.backdrop then bar1.backdrop:Hide() end
            return
        end

        local max, current = get_secondary_resource_value(resource)
        if not max or max <= 0 then
            if bar1 and bar1.backdrop then bar1.backdrop:Hide() end
            return
        end

        -- Note: secondary resource values (e.g. Fury, Stagger) may also be
        -- secret in some contexts. Always pass through to SetValue unconditionally.
        local bar = get_bar1()
        bar.TextValue:SetText(current)
        bar:SetMinMaxValues(0, max)
        bar:SetValue(current)

        local color
        if cfg.useClassColor then
            color = common.get_class_or_spec_color()
        else
            color = common.get_resource_color(resource)
        end
        if color then
            local r, g, b = common.unpack_color(color)
            bar:SetStatusBarColor(r, g, b)
        end
    end

    local function create_icon(parent, name, size, spellID)
        local frame = CreateFrame("Frame", name, parent)
        frame:SetSize(size, size)

        local texture = frame:CreateTexture(nil, "BACKGROUND")
        texture:SetAllPoints()
        local spellTexture = common.get_spell_icon(spellID)
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

    get_vigor_bar = function()
        if vigor_bar then return vigor_bar end
        local bar = common.create_bar("vigorBar", "StatusBar", UIParent)
        bar.TextValue = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bar.TextValue:SetFont("Fonts\\FRIZQT__.TTF", cfg.secondaryPowerBar.fontSize, "")
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

    function update_vigor_bar()
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
            if bar._lastCharges ~= chargesInfo.currentCharges then
                bar._lastCharges = chargesInfo.currentCharges
                bar.TextValue:SetFormattedText("%d", chargesInfo.currentCharges)
            end
        end

        if cfg.color then
            bar:SetStatusBarColor(cfg.color[1], cfg.color[2], cfg.color[3])
        end

        local surgeSpellID = is_player_spell(418592) and 418592 or 361584

        local surgeTexture = common.get_spell_icon(surgeSpellID)
        bar.whirlingSurgeIcon.texture:SetTexture(surgeTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
        bar.whirlingSurgeIcon.texture:SetDesaturated(false)
        bar.whirlingSurgeIcon.countText:SetText("")

        local wsStart, wsDur = common.get_spell_cooldown(surgeSpellID)
        if wsStart > 0 and wsDur > 0 and not (issecretvalue and (issecretvalue(wsStart) or issecretvalue(wsDur))) then
            bar.whirlingSurgeIcon.cooldown:SetCooldown(wsStart, wsDur)
        else
            bar.whirlingSurgeIcon.cooldown:Clear()
        end

        local scAura = C_UnitAuras.GetPlayerAuraBySpellID(418590)
        if scAura and (issecretvalue(scAura.applications) or (type(scAura.applications) == "number" and scAura.applications > 0)) then
            bar.staticChargeIcon:Show(); bar.staticChargeIcon.countText:SetText(scAura.applications)
        else
            bar.staticChargeIcon:Hide()
        end

        local swStart, swDur = common.get_spell_cooldown(425782)
        local swCharges = C_Spell.GetSpellCharges(425782)
        if swStart > 0 and swDur > 0 and not (issecretvalue and (issecretvalue(swStart) or issecretvalue(swDur))) then
            bar.secondWindIcon.cooldown:SetCooldown(swStart, swDur)
        else
            bar.secondWindIcon.cooldown:Clear()
        end
        bar.secondWindIcon.countText:SetText(swCharges and swCharges.currentCharges or "")
    end

    get_mount_speed_bar = function()
        if mount_speed_bar then return mount_speed_bar end
        local bar = common.create_bar("mountSpeedBar", "StatusBar", UIParent)
        bar.TextValue = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bar.TextValue:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
        bar.TextValue:SetShadowOffset(1, -1)
        bar.TextValue:SetPoint("CENTER")
        bar.lastSpeed = 0 -- Cache for change detection
        bar:SetMinMaxValues(0, 1200)
        bar:SetValue(0)

        -- Speed requires polling as there is no gliding speed event.
        -- OnUpdate is installed/removed dynamically by update_mount_speed_bar_internal
        -- to avoid permanent 20fps polling when not dragonflying.
        bar._onUpdate = function(self, elapsed)
            self.timer = (self.timer or 0) + elapsed
            if self.timer > 0.05 then -- Throttled to 20fps
                self.timer = 0
                update_mount_speed_bar_internal()
            end
        end

        mount_speed_bar = bar
        return bar
    end

    update_mount_speed_bar_internal = function()
        local cfg = sfui.config.mountSpeedBar
        if not cfg.enabled or not is_dragonflying() then
            if mount_speed_bar then
                mount_speed_bar.backdrop:Hide()
                if mount_speed_bar._onUpdateActive then
                    if sfui.events and sfui.events.UnregisterUpdate then
                        sfui.events.UnregisterUpdate("MountSpeedBar")
                    end
                    mount_speed_bar:SetScript("OnUpdate", nil)
                    mount_speed_bar._onUpdateActive = false
                end
            end
            return
        end
        local bar = mount_speed_bar or get_mount_speed_bar()

        -- Install update loop only when actually dragonflying
        if not bar._onUpdateActive then
            if sfui.events and sfui.events.RegisterUpdate then
                sfui.events.RegisterUpdate("MountSpeedBar", 0.05, update_mount_speed_bar_internal)
            else
                bar:SetScript("OnUpdate", bar._onUpdate)
            end
            bar._onUpdateActive = true
        end

        local forwardSpeed
        if C_PlayerInfo and C_PlayerInfo.GetGlidingInfo then
            local _, _, fs = C_PlayerInfo.GetGlidingInfo()
            forwardSpeed = fs
        end

        if not forwardSpeed then
            bar:SetValue(0)
            if bar.lastSpeed ~= 0 then
                bar.TextValue:SetText("0")
                bar.lastSpeed = 0
            end
            return
        end

        if issecretvalue and issecretvalue(forwardSpeed) then
            bar:SetValue(forwardSpeed)
            return
        end

        local num = tonumber(forwardSpeed)
        if num and num == num and num >= -3.4e38 and num <= 3.4e38 then
            local speed = num * 14.286
            if speed == speed and speed >= -3.4e38 and speed <= 3.4e38 then
                bar:SetValue(speed)
                if math.abs(speed - (bar.lastSpeed or 0)) > 5 then
                    bar.TextValue:SetFormattedText("%d", speed)
                    bar.lastSpeed = speed
                end
            else
                bar:SetValue(0)
            end
        else
            bar:SetValue(0)
        end

        local aura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and C_UnitAuras.GetPlayerAuraBySpellID(377234)
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
    sfui.bars.get_bar0 = get_bar0
    sfui.bars.get_bar_minus_1 = get_bar_minus_1
    sfui.bars.get_bar1 = get_bar1
    sfui.bars.update_bar_positions = update_bar_positions
    sfui.bars.UpdatePositions = update_bar_positions
    sfui.bars.update_bar_visibility = update_bar_visibility
    sfui.bars.UpdateVisibility = update_bar_visibility

    function sfui.bars.set_bar_texture(arg1, arg2)
        local texturePath = (type(arg1) == "string") and arg1 or arg2
        if not texturePath then return end

        if bar_minus_1 then bar_minus_1:SetStatusBarTexture(texturePath) end
        if bar0 then
            bar0:SetStatusBarTexture(texturePath)
            if bar0.healPredBar then bar0.healPredBar:SetStatusBarTexture(texturePath) end
            if bar0.absorbBar then bar0.absorbBar:SetStatusBarTexture(texturePath) end
            if bar0.lossBar then bar0.lossBar:SetStatusBarTexture(texturePath) end
        end
        if bar1 then bar1:SetStatusBarTexture(texturePath) end
        if vigor_bar then vigor_bar:SetStatusBarTexture(texturePath) end
        if mount_speed_bar then mount_speed_bar:SetStatusBarTexture(texturePath) end
        if sfui.swing and sfui.swing.SetBarTexture then
            sfui.swing.SetBarTexture(texturePath)
        end
    end

    function sfui.bars:on_state_changed()
        update_bar_minus_1()
        local max, current = UnitHealthMax("player"), UnitHealth("player")
        update_bar0(current, max)
        update_bar1()
        update_vigor_bar()
        update_rune_bar()
        update_mount_speed_bar_internal()
        update_bar_visibility()
    end

    function sfui.bars.update_settings()
        sfui.bars:on_state_changed()
    end

    function sfui.bars:update_health_bar_position()
        update_bar_positions()
    end

    local function on_event(event, unit, ...)
        if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_TALENT_UPDATE" or event == "CHARACTER_POINTS_CHANGED" or event == "TRAIT_CONFIG_UPDATED" or event == "TRAIT_TREE_CURRENCY_INFO_UPDATED" or event == "ACTIVE_TALENT_GROUP_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM" or event == "PLAYER_MOUNT_DISPLAY_CHANGED" or event == "PLAYER_ENTERING_WORLD" or event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" or event == "VEHICLE_UPDATE" or event == "UPDATE_VEHICLE_ACTIONBAR" or event == "UPDATE_OVERRIDE_ACTIONBAR" or event == "UPDATE_POSSESS_BAR" or event == "UPDATE_BONUS_ACTIONBAR" then
            invalidate_dragonflying_cache()
            sfui.bars:on_state_changed()
        elseif event == "PLAYER_CAN_GLIDE_CHANGED" or event == "PLAYER_IS_GLIDING_CHANGED" then
            invalidate_dragonflying_cache()
            update_vigor_bar()
            update_mount_speed_bar_internal()
            update_bar_visibility()
        elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_TARGET_CHANGED" then
            if not should_throttle("visibility") then
                update_bar_visibility()
            end
        elseif event == "SPELL_UPDATE_CHARGES" then
            update_vigor_bar()
        elseif event == "RUNE_POWER_UPDATE" then
            if not should_throttle("runes") then
                update_rune_bar()
            end
        end
    end

    -- Unit events: player-only via the central unit-event frame.
    local function on_unit_power()
        local pShown = bar_minus_1 and bar_minus_1.backdrop and bar_minus_1.backdrop:IsShown()
        local sShown = bar1 and bar1.backdrop and bar1.backdrop:IsShown()
        if not pShown and not sShown then return end

        if not should_throttle("bar_minus_1") then
            if pShown then update_bar_minus_1() end
            if sShown then update_bar1() end
        end
    end

    local function on_spellcast(event, unit, castGUID, spellID)
        if unit ~= "player" then return end
        local isClassic = sfui.isClassic or (sfui.compat and (sfui.compat.has.wow_forever or sfui.compat.is_classic_era or sfui.compat.is_classic))
        if not isClassic then return end

        local resource = common.get_primary_resource()
        if resource == nil and UnitPowerType then
            resource = UnitPowerType("player")
        end
        if resource ~= 0 and resource ~= Enum.PowerType.Mana then return end

        if not spellID then
            if UnitCastingInfo then
                spellID = select(9, UnitCastingInfo("player"))
            end
            if not spellID and UnitChannelInfo then
                spellID = select(8, UnitChannelInfo("player"))
            end
        end

        if spellID and spell_costs_mana(spellID) then
            start_fsr_timer()
        end
    end

    local function on_unit_health()
        if not bar0 or not bar0.backdrop or not bar0.backdrop:IsShown() then return end

        if not should_throttle("bar0") then
            local max, current = UnitHealthMax("player"), UnitHealth("player")
            update_bar0(current, max)
        end
    end

    -- UNIT_HEALTH, UNIT_MAXHEALTH, and UNIT_ABSORB_AMOUNT_CHANGED share the same handler.
    sfui.events.RegisterUnitEvents(
        {"UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_ABSORB_AMOUNT_CHANGED"},
        "player", on_unit_health
    )
    sfui.events.RegisterUnitEvents(
        {"UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER"},
        "player", on_unit_power
    )

    -- 5-Second Rule (MP5 Regen) events: strictly registered on Classic / Camelot only
    if sfui.isClassic then
        sfui.events.RegisterUnitEvents(
            {"UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_CHANNEL_START"},
            "player", on_spellcast
        )
        sfui.events.RegisterEvent("PLAYER_DEAD", function() stop_fsr_timer() end)
    end

    sfui.events.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", on_event)
    sfui.events.RegisterEvent("PLAYER_TALENT_UPDATE", on_event)
    sfui.events.RegisterEvent("CHARACTER_POINTS_CHANGED", on_event)
    sfui.events.RegisterEvent("TRAIT_CONFIG_UPDATED", on_event)
    sfui.events.RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", on_event)
    sfui.events.RegisterEvent("UPDATE_SHAPESHIFT_FORM", on_event)
    sfui.events.RegisterEvent("PLAYER_CAN_GLIDE_CHANGED", on_event)
    sfui.events.RegisterEvent("PLAYER_IS_GLIDING_CHANGED", on_event)
    sfui.events.RegisterEvent("SPELL_UPDATE_CHARGES", on_event)
    sfui.events.RegisterEvent("PLAYER_REGEN_DISABLED", on_event)
    sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", on_event)
    sfui.events.RegisterEvent("PLAYER_TARGET_CHANGED", on_event)
    sfui.events.RegisterEvent("RUNE_POWER_UPDATE", on_event)
    sfui.events.RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED", on_event)
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", on_event)
    sfui.events.RegisterUnitEvents({"UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE"}, "player", on_event)
    sfui.events.RegisterEvent("VEHICLE_UPDATE", on_event)
    sfui.events.RegisterEvent("UPDATE_VEHICLE_ACTIONBAR", on_event)
    sfui.events.RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR", on_event)
    sfui.events.RegisterEvent("UPDATE_POSSESS_BAR", on_event)
    sfui.events.RegisterEvent("UPDATE_BONUS_ACTIONBAR", on_event)

    function sfui.bars_debug_info()
        return {
            bar0Created = bar0 ~= nil,
            bar0Shown = bar0 and bar0:IsShown() or false,
            bar1Created = bar1 ~= nil,
            bar1Shown = bar1 and bar1:IsShown() or false,
            barMinus1Created = bar_minus_1 ~= nil,
            barMinus1Shown = bar_minus_1 and bar_minus_1:IsShown() or false,
            vigorCreated = vigor_bar ~= nil,
            mountSpeedActive = mount_speed_bar and mount_speed_bar:GetScript("OnUpdate") ~= nil or false,
            runeBarCreated = rune_bar ~= nil,
        }
    end

    if sfui.RegisterModule then
        sfui.bars.OnEnable = function(self) self:on_state_changed() end
        sfui.bars.OnSettingsChanged = function(self, k, v) self:on_state_changed() end
        sfui.bars.OnSpecChanged = function(self, specID) self:on_state_changed() end
        sfui.bars.GetDebugInfo = sfui.bars_debug_info
        sfui.RegisterModule("bars", sfui.bars)
    end
end

