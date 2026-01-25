sfui = sfui or {}
sfui.castbar = {}

local function CreateCastBar(configName, unit)
    local bar = sfui.common.CreateBar(configName, "StatusBar", UIParent)
    bar.unit, bar.configName = unit, configName

    bar.backdrop:SetScript("OnShow", function(self) self:SetAlpha(1) end)

    bar.Text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bar.Text:SetPoint("CENTER", 0, 0)

    bar.TimerText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bar.TimerText:SetPoint("RIGHT", -5, 0)

    bar.Spark = bar:CreateTexture(nil, "OVERLAY")
    bar.Spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    bar.Spark:SetBlendMode("ADD")
    bar.Spark:SetSize(20, bar:GetHeight() * 2.5)

    bar.Icon = bar.backdrop:CreateTexture(nil, "ARTWORK")
    bar.Icon:SetSize(bar:GetHeight() + 4, bar:GetHeight() + 4)
    bar.Icon:SetPoint("RIGHT", bar.backdrop, "LEFT", -5, 0)
    bar.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Setup Texture (Inherit from Options Panel)
    local textureName = SfuiDB.barTexture
    local LSM = LibStub("LibSharedMedia-3.0", true)
    local texturePath
    if LSM then
        texturePath = LSM:Fetch("statusbar", textureName)
    end
    if not texturePath or texturePath == "" then
        texturePath = sfui.config.barTexture -- Defaults to Flat (WHITE8X8)
    end
    bar:SetStatusBarTexture(texturePath)

    local cfg = sfui.config[configName]
    bar.backdrop:ClearAllPoints()
    if unit == "player" then bar.backdrop:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 110) end
    bar.backdrop:Hide()
    return bar
end

local function UpdateCastBarColor(bar, state)
    local cfg = sfui.config[bar.configName]
    local color = cfg.color -- Default

    if state == "CHANNEL" then
        color = cfg.channelColor or { 0, 1, 0 }
    elseif state == "INTERRUPTED" then
        color = cfg.interruptedColor or { 1, 0, 0 }
    elseif state == "EMPOWER" then
        color = cfg.empoweredColor or { 0.4, 0, 1 }
    end

    bar:SetStatusBarColor(color[1], color[2], color[3])
end

local function StartLinger(self)
    self.casting = nil
    self.channeling = nil
    self.empowering = nil
    self.isLingering = true
    self.lingerTime = 1.0 -- Linger for 1 second
    self.fadeTime = 0.5   -- Fade over 0.5 seconds
    self.backdrop:Show()  -- Ensure it stays shown
    self.backdrop:SetAlpha(1)
end

local function OnUpdate(self, elapsed)
    if self.casting then
        self.value = self.value + elapsed
        if self.value >= self.maxValue then
            self:SetValue(self.maxValue)
            StartLinger(self)
            return
        end
        self:SetValue(self.value)
        self.TimerText:SetFormattedText("%.1f", self.maxValue - self.value)

        -- Spark Logic
        local sparkPosition = (self.value / self.maxValue) * self:GetWidth()
        self.Spark:SetPoint("CENTER", self, "LEFT", sparkPosition, 0)
    elseif self.channeling then
        self.value = self.value - elapsed
        if self.value <= 0 then
            self.value = 0
            StartLinger(self)
            return
        end
        self:SetValue(self.value)
        self.TimerText:SetFormattedText("%.1f", self.value)

        -- Spark Logic
        local sparkPosition = (self.value / self.maxValue) * self:GetWidth()
        self.Spark:SetPoint("CENTER", self, "LEFT", sparkPosition, 0)
    elseif self.empowering then
        self.value = self.value + elapsed
        if self.value >= self.maxValue then
            self:SetValue(self.maxValue); StartLinger(self); return
        end
        self:SetValue(self.value)
        self.TimerText:SetFormattedText("%.1f", self.maxValue - self.value)

        if self.numStages and self.numStages > 0 then
            local progress = self.value / self.maxValue
            local currentStage = math.min(math.floor(progress * self.numStages) + 1, self.numStages)

            if currentStage ~= self.empowerStage then
                self.empowerStage = currentStage
                local stageColors = sfui.config[self.configName].empoweredStageColors
                local c = stageColors and stageColors[currentStage]
                if c then self:SetStatusBarColor(c[1], c[2], c[3]) end
            end
        end
        local sparkPosition = (self.value / self.maxValue) * self:GetWidth()
        self.Spark:SetPoint("CENTER", self, "LEFT", sparkPosition, 0)
    elseif self.isLingering then
        self.lingerTime = self.lingerTime - elapsed
        if self.lingerTime <= 0 then
            self.fadeTime = self.fadeTime - elapsed
            if self.fadeTime <= 0 then
                self.isLingering = nil; self.backdrop:Hide(); self.backdrop:SetAlpha(1)
            else
                self.backdrop:SetAlpha(self.fadeTime / 0.5)
            end
        end
    else
        self.value = 0; self.backdrop:Hide(); self.backdrop:SetAlpha(1)
    end
end

local function CreateStageDividers(bar, numStages)
    if not bar.stageDividers then bar.stageDividers = {} end

    -- Hide all existing
    for _, div in ipairs(bar.stageDividers) do div:Hide() end

    if numStages and numStages > 0 then
        local width = bar:GetWidth()
        local step = width / numStages

        for i = 1, numStages - 1 do
            local div = bar.stageDividers[i]
            if not div then
                div = bar:CreateTexture(nil, "OVERLAY")
                div:SetColorTexture(0, 0, 0, 0.8)
                div:SetSize(1, bar:GetHeight())
                bar.stageDividers[i] = div
            end

            div:ClearAllPoints()
            div:SetPoint("LEFT", bar, "LEFT", step * i, 0)
            div:Show()
        end
    end
end

local function OnEvent(self, event, unit, ...)
    if unit ~= self.unit then return end

    if event == "UNIT_SPELLCAST_START" then
        local name, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible, spellID = UnitCastingInfo(
            unit)
        if not name or not startTime or not endTime or not castID then return end

        self.backdrop:Show()
        self.backdrop:SetAlpha(1)
        self.value = (GetTime() - (startTime / 1000))
        self.maxValue = (endTime - startTime) / 1000
        self:SetMinMaxValues(0, self.maxValue)
        self:SetValue(self.value)

        self.Text:SetText(text)
        self.Icon:SetTexture(texture)

        self.casting = true
        self.channeling = nil
        self.empowering = nil
        self.castID = castID

        UpdateCastBarColor(self, "CAST")
        self.Spark:Show()
        CreateStageDividers(self, 0)
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_EMPOWER_START" then
        local name, text, texture, startTime, endTime, isTradeSkill, notInterruptible, spellID, _, numStages =
            UnitChannelInfo(unit)
        if not name or not startTime or not endTime or not spellID then return end

        self.backdrop:Show()
        self.backdrop:SetAlpha(1)
        self.Icon:SetTexture(texture)
        self.Text:SetText(name)

        local isEmpowered = numStages and numStages > 0
        if isEmpowered then
            local holdTime = GetUnitEmpowerHoldAtMaxTime and GetUnitEmpowerHoldAtMaxTime(unit) or 0
            endTime = endTime + holdTime
            self.value = (GetTime() - (startTime / 1000))
            self.maxValue = (endTime - startTime) / 1000
            self.casting, self.channeling, self.empowering = nil, nil, true
            self.numStages, self.empowerStage = numStages, 0

            local stageColors = sfui.config[self.configName].empoweredStageColors
            local c = stageColors and stageColors[1]
            if c then self:SetStatusBarColor(c[1], c[2], c[3]) else UpdateCastBarColor(self, "EMPOWER") end
            CreateStageDividers(self, numStages)
        else
            self.value = ((endTime / 1000) - GetTime())
            self.maxValue = (endTime - startTime) / 1000
            self.casting, self.channeling, self.empowering = nil, true, nil
            UpdateCastBarColor(self, "CHANNEL"); CreateStageDividers(self, 0)
        end

        self:SetMinMaxValues(0, self.maxValue)
        self:SetValue(self.value)
        self.Spark:Show()
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        if self.casting and event == "UNIT_SPELLCAST_STOP" then
            local castID = select(1, ...)
            if castID ~= self.castID then return end -- Ignore unrelated cast stops
        end

        -- Channel stops usually pass spellID

        if not self.casting and not self.channeling and not self.empowering then
            StartLinger(self)
        end

        if not UnitCastingInfo(unit) and not UnitChannelInfo(unit) then
            StartLinger(self)
        end
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        local castID = select(1, ...)

        -- Only process if it matches our current cast
        if self.casting and castID == self.castID then
            self:SetValue(self.maxValue)
            UpdateCastBarColor(self, "INTERRUPTED")
            self.Text:SetText(FAILED)
            if event == "UNIT_SPELLCAST_INTERRUPTED" then
                self.Text:SetText(INTERRUPTED)
            end

            self.casting = nil
            self.channeling = nil
            self.empowering = nil

            C_Timer.After(0.5, function()
                if not self.casting and not self.channeling and not self.empowering then
                    StartLinger(self)
                end
            end)
        elseif (self.channeling or self.empowering) and (event == "UNIT_SPELLCAST_INTERRUPTED") then
            -- Channels don't always use castID, but if interrupted, we should check availability
            -- If UnitChannelInfo is gone, it's gone.
            if not UnitChannelInfo(unit) then
                self:SetValue(self.maxValue)
                UpdateCastBarColor(self, "INTERRUPTED")
                self.Text:SetText(INTERRUPTED)

                self.casting = nil
                self.channeling = nil
                self.empowering = nil

                C_Timer.After(0.5, function()
                    if not self.casting and not self.channeling and not self.empowering then
                        StartLinger(self)
                    end
                end)
            end
        end
    elseif event == "UNIT_SPELLCAST_DELAYED" then
        local name, _, _, startTime, endTime, _, castID = UnitCastingInfo(unit)
        if not name or not startTime or not endTime or not castID then return end
        self.value = (GetTime() - (startTime / 1000))
        self.maxValue = (endTime - startTime) / 1000
        self:SetMinMaxValues(0, self.maxValue)
    elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" or event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
        local name, _, _, startTime, endTime, _, _, spellID = UnitChannelInfo(unit)
        if not name or not startTime or not endTime or not spellID then return end
        self.value = ((endTime / 1000) - GetTime())
        self.maxValue = (endTime - startTime) / 1000
        self:SetMinMaxValues(0, self.maxValue)
    end
end

local event_frame = CreateFrame("Frame")
event_frame:RegisterEvent("PLAYER_LOGIN")

local function SetupBar(configName, unit)
    local bar = CreateCastBar(configName, unit)
    bar:SetScript("OnUpdate", OnUpdate)

    bar:RegisterUnitEvent("UNIT_SPELLCAST_START", unit)
    bar:RegisterUnitEvent("UNIT_SPELLCAST_STOP", unit)
    bar:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", unit)
    bar:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", unit)
    bar:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", unit)
    bar:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", unit)
    bar:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", unit)
    bar:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", unit)
    bar:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", unit)
    bar:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_UPDATE", unit)
    bar:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", unit)

    bar:SetScript("OnEvent", OnEvent)
    return bar
end

event_frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        SetupBar("castBar", "player")
        if _G.PlayerCastingBarFrame then
            _G.PlayerCastingBarFrame:SetAlpha(0); _G.PlayerCastingBarFrame:UnregisterAllEvents(); _G
                .PlayerCastingBarFrame:Hide()
        end
    end
end)
