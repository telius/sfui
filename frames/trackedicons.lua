local addonName, addon = ...
sfui.trackedicons = {}

local panels = {} -- Active icon panels
local issecretvalue = sfui.common.issecretvalue

local function GetLCG()
    if LibStub then
        return LibStub("LibCustomGlow-1.0", true)
    end
end
sfui.trackedicons.GetLCG = GetLCG

-- STATIC REUSE (Memory Optimization)
local _tempGlowCfg = {}
local _defaultColor = { r = 1, g = 1, b = 0 }
local _emptyTable = {}

local function GetIconValue(entrySettings, panelConfig, key, default)
    if entrySettings and entrySettings[key] ~= nil then return entrySettings[key] end
    if panelConfig and panelConfig[key] ~= nil then return panelConfig[key] end
    return default
end

-- Static pcall targets
local function pcall_item_cd(icon)
    local s, d, e = C_Item.GetItemCooldown(icon.id)
    icon._start, icon._duration, icon._isEnabled = s, d, e
    CooldownFrame_Set(icon.cooldown, s, d, e)
    if icon.shadowCooldown then icon.shadowCooldown:SetCooldown(s, d) end
    return C_Item.GetItemCount(icon.id)
end

local function pcall_spell_cd(icon)
    local ci = C_Spell.GetSpellCooldown(icon.id)
    if ci then
        icon._start, icon._duration, icon._isEnabled, icon._modRate = ci.startTime, ci.duration, ci.isEnabled, ci
            .modRate
        return ci.isEnabled
    end
end

local function pcall_sync_swipe(icon, durObj)
    icon.cooldown:SetCooldownFromDurationObject(durObj)
    if icon.shadowCooldown then icon.shadowCooldown:SetCooldownFromDurationObject(durObj) end
end

local function StopGlow(icon)
    if ActionButton_HideOverlayGlow then
        ActionButton_HideOverlayGlow(icon)
    end
    local lcg = GetLCG()
    if lcg then
        pcall(lcg.PixelGlow_Stop, icon)
        pcall(lcg.AutoCastGlow_Stop, icon)
        pcall(lcg.ButtonGlow_Stop, icon)
    end
    icon._glowActive = false
    icon._lastGlowType = nil
    icon._lastGlowCfg = nil
end
sfui.trackedicons.StopGlow = StopGlow

local function StartGlow(icon, cfg)
    local gType = cfg.glowType or "blizzard"
    local color = cfg.glowColor or { r = 1, g = 1, b = 0 }
    local scale = cfg.glowScale or 1.0
    local intensity = cfg.glowIntensity or 1.0
    local speed = cfg.glowSpeed or 0.25
    local lcg = GetLCG()
    local frameLevel = icon:GetFrameLevel() + 30

    if gType == "pixel" and lcg then
        -- PixelGlow args: (frame, color, N, frequency, length, th, xOffset, yOffset, border, key, frameLevel)
        pcall(lcg.PixelGlow_Start, icon, { color.r, color.g, color.b, intensity }, nil, speed, nil, scale, nil, nil, nil,
            nil, frameLevel)
    elseif gType == "autocast" and lcg then
        pcall(lcg.AutoCastGlow_Start, icon, { color.r, color.g, color.b, intensity }, nil, speed, scale, nil, nil, nil,
            frameLevel)
    elseif lcg then
        -- Use LCG's version of Blizzard glow for better frame level control
        pcall(lcg.ButtonGlow_Start, icon, { color.r, color.g, color.b, intensity }, speed, frameLevel)
    else
        -- Fallback to Blizzard or if LCG is missing
        if ActionButton_ShowOverlayGlow then
            ActionButton_ShowOverlayGlow(icon)
        end
    end
    icon._glowActive = true
    icon._lastGlowType = gType
    icon._lastGlowCfg = sfui.common.copy(cfg) -- Need a shallow/deep copy for comparison
end
sfui.trackedicons.StartGlow = StartGlow



-- Helper to create count text (stacks/charges)
local function CreateCountText(icon)
    if icon.count then return end

    local count = icon:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    count:SetPoint("BOTTOMRIGHT", -2, 2)
    count:SetJustifyH("RIGHT")
    icon.count = count
end

-- Helper to safely check if icon is on active cooldown (avoiding secret value taint)
local function IsCooldownActive(cooldownFrame, hasCharges, icon)
    if not cooldownFrame then return false end

    -- 1. Try Duration Object evaluation (Best for Spells in M+)
    -- sfui.common.EvaluateCooldown uses Curve evaluation which is secret-safe
    if icon and icon.id and not icon._isItem then
        local durObj = sfui.common.GetCooldownDurationObj(icon.id)
        if durObj then
            local cdValue = sfui.common.EvaluateCooldown(durObj)
            if cdValue > 0 then
                -- Check for GCD to avoid desaturating during it
                local ok_gcd, cdInfo = pcall(C_Spell.GetSpellCooldown, icon.id)
                if ok_gcd and cdInfo and cdInfo.isOnGCD then
                    return false
                end
                return not hasCharges
            end
            return false -- durObj exists but says spell is ready
        end
    end

    -- 2. Frame Polling Fallback (For items and fallback cases)
    local ok, durationMs = pcall(function() return cooldownFrame:GetCooldownDuration() end)

    if not ok then return false end

    if issecretvalue(durationMs) then
        -- In protected context (M+), assume ON COOLDOWN if it's secret (and no charges)
        return not hasCharges
    end

    if not durationMs or durationMs == 0 then
        return false
    end

    -- Duration is in milliseconds, check if > 1500ms (1.5s) to exclude GCD
    return (durationMs > 1500) and not hasCharges
end

-- Helper to update count text value
local function UpdateCountText(icon, count)
    if not icon.count then CreateCountText(icon) end

    local isSecret = issecretvalue(count)
    local hasCount = sfui.common.SafeGT(count, 1)

    if isSecret or hasCount then
        sfui.common.SafeSetText(icon.count, count, 0)
        icon.count:Show()
    else
        icon.count:Hide()
    end
end

-- Helper to update icon state (visibility, cooldown, charges)
local function UpdateIconState(icon, panelConfig)
    if not icon.id or not icon.entry then return false end
    local entrySettings = icon.entry.settings or _emptyTable
    local durObj = nil
    local count = 0
    local isEnabled = true

    if icon.type == "item" then
        local ok, countVal = pcall(pcall_item_cd, icon)
        if ok then
            count = countVal or 0
            isEnabled = icon._isEnabled
        end
    else
        durObj = sfui.common.GetCooldownDurationObj(icon.id)
        local ok, enabledVal = pcall(pcall_spell_cd, icon)
        if ok then isEnabled = enabledVal end

        if not issecretvalue(icon.id) then
            local charges = C_Spell.GetSpellCharges(icon.id)
            if charges then
                count = sfui.common.SafeValue(charges.currentCharges, 0)
            end
        end

        if durObj then
            pcall(pcall_sync_swipe, icon, durObj)
        else
            -- No duration object = Ready (Clear cooldown)
            icon.cooldown:Clear()
            if icon.shadowCooldown then icon.shadowCooldown:Clear() end
        end
    end

    icon._isItem = (icon.type == "item")

    -- Readiness Logic (Native Safe)
    local isReady = true
    local safeEnabled = sfui.common.SafeNotFalse(isEnabled)

    if icon.type == "item" then
        local s, d = icon._start or 0, icon._duration or 0
        local safeS = sfui.common.SafeValue(s, 0)
        local safeD = sfui.common.SafeValue(d, 0)
        isReady = (safeS == 0 or (GetTime() - safeS) >= safeD or safeD <= 1.5) and safeEnabled
    else
        local countSafe = sfui.common.SafeGT(count, 0)
        isReady = (durObj == nil or countSafe) and safeEnabled
    end

    -- Visibility Decision: Icons are always shown if they exist in the panel,
    -- but they might be desaturated or have alpha.
    local shouldShow = true
    local isVisible = shouldShow -- In simple panel mode, all icons are visible holders

    if isVisible then
        if not icon:IsShown() then
            if not InCombatLockdown() then
                icon:Show()
            end
            icon:SetAlpha(1)
        end

        -- Update Count Text
        UpdateCountText(icon, count)

        -- Visibility / Settings check
        icon.cooldown:SetHideCountdownNumbers(not GetIconValue(entrySettings, panelConfig, "textEnabled", true))

        -- Visuals
        local showGlow = GetIconValue(entrySettings, panelConfig, "readyGlow", true)
        local useDesat = GetIconValue(entrySettings, panelConfig, "cooldownDesat", true)
        local cdAlpha = GetIconValue(entrySettings, panelConfig, "cooldownAlpha", 1.0)
        local glowType = GetIconValue(entrySettings, panelConfig, "glowType", "blizzard")

        -- Desaturation & Opacity Logic (Strictly Cooldown-based, taint-safe)
        local countSafe = sfui.common.SafeGT(count, 0)
        local isOnCooldown = IsCooldownActive(icon.cooldown, countSafe, icon)

        if icon.texture then
            icon.texture:SetDesaturated(useDesat and isOnCooldown)
        end
        icon:SetAlpha(isOnCooldown and cdAlpha or 1)

        -- Glow Logic with 5s duration limit
        if isReady and showGlow then
            -- Check if glow has been active for too long
            local maxDuration = sfui.config.cooldown_panel_defaults.glow_max_duration or 5.0
            local now = GetTime()

            if not icon._glowStartTime then
                icon._glowStartTime = now
            end

            local elapsed = now - icon._glowStartTime

            if elapsed < maxDuration then
                -- Resolved config for glow (REUSED TABLE)
                _tempGlowCfg.glowType = glowType
                _tempGlowCfg.glowColor = GetIconValue(entrySettings, panelConfig, "glowColor", _defaultColor)
                _tempGlowCfg.glowScale = GetIconValue(entrySettings, panelConfig, "glowScale", 1.0)
                _tempGlowCfg.glowIntensity = GetIconValue(entrySettings, panelConfig, "glowIntensity", 1.0)
                _tempGlowCfg.glowSpeed = GetIconValue(entrySettings, panelConfig, "glowSpeed", 0.25)

                -- Restart if type or parameters changed
                local needsRestart = false
                if not icon._glowActive then
                    needsRestart = true
                elseif icon._lastGlowType ~= glowType then
                    needsRestart = true
                elseif not icon._lastGlowCfg then
                    needsRestart = true
                else
                    local prev = icon._lastGlowCfg
                    if math.abs(prev.glowColor.r - _tempGlowCfg.glowColor.r) > 0.01 or
                        math.abs(prev.glowColor.g - _tempGlowCfg.glowColor.g) > 0.01 or
                        math.abs(prev.glowColor.b - _tempGlowCfg.glowColor.b) > 0.01 or
                        math.abs(prev.glowScale - _tempGlowCfg.glowScale) > 0.01 or
                        math.abs(prev.glowIntensity - _tempGlowCfg.glowIntensity) > 0.01 or
                        math.abs(prev.glowSpeed - _tempGlowCfg.glowSpeed) > 0.01 then
                        needsRestart = true
                    end
                end

                if needsRestart then
                    if icon._glowActive then StopGlow(icon) end
                    StartGlow(icon, _tempGlowCfg)
                end
            else
                -- Exceeded duration, stop glow
                if icon._glowActive then
                    StopGlow(icon)
                end
            end
        else
            -- Reset start time when not ready
            icon._glowStartTime = nil
            if icon._glowActive then
                StopGlow(icon)
            end
        end
    else
        if InCombatLockdown() then
            icon:SetAlpha(0)
        else
            icon:Hide()
        end
    end

    return isVisible
end

-- Create a single icon frame (Standard Button for Taint Isolation)
local function CreateIconFrame(parent, id, entry)
    local name = "SfuiTrackedIcon_" .. (entry.type or "spell") .. "_" .. id .. "_" .. GetTime() -- Unique basic name
    local f = CreateFrame("Button", name, parent)
    f:SetSize(50, 50)

    -- Icon Texture
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    f.texture = tex

    local iconTexture
    if entry.type == "item" then
        iconTexture = C_Item.GetItemIconByID(id)
    else
        iconTexture = C_Spell.GetSpellTexture(id)
    end
    tex:SetTexture(iconTexture or 134400)

    -- Main Cooldown Frame (Blizzard Native Countdown)
    local cd = CreateFrame("Cooldown", name .. "_CD", f, "CooldownFrameTemplate")
    cd:SetAllPoints(tex)
    cd:SetDrawEdge(true)
    cd:SetHideCountdownNumbers(false) -- SHOW NATIVE COUNTDOWN
    f.cooldown = cd

    -- Shadow Cooldown Frame (Invisible, drives desaturation safely)
    local shadow = CreateFrame("Cooldown", name .. "_ShadowCD", f, "CooldownFrameTemplate")
    shadow:SetAllPoints(tex)
    shadow:SetDrawSwipe(false)
    shadow:SetDrawEdge(false)
    shadow:SetDrawBling(false)
    shadow:SetHideCountdownNumbers(true)
    shadow:SetAlpha(0)
    f.shadowCooldown = shadow

    -- Main cooldown frames handle countdown numbers natively

    -- Border/Overlay (optional visual polish)
    f.PushedTexture = f:CreateTexture(nil, "OVERLAY")
    f.PushedTexture:SetTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    f.PushedTexture:SetAllPoints()
    f:SetPushedTexture(f.PushedTexture)

    f.HighlightTexture = f:CreateTexture(nil, "HIGHLIGHT")
    f.HighlightTexture:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    f.HighlightTexture:SetAllPoints()
    f:SetHighlightTexture(f.HighlightTexture)

    f.id = id
    f.entry = entry

    f:RegisterForClicks("AnyUp", "AnyDown")

    f:SetScript("OnEnter", function(self)
        if GameTooltip and self.id and not issecretvalue(self.id) then
            pcall(function()
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if self.entry.type == "item" then
                    GameTooltip:SetItemByID(self.id)
                else
                    GameTooltip:SetSpellByID(self.id)
                end
                GameTooltip:Show()
            end)
        end
    end)
    f:SetScript("OnLeave", function()
        if GameTooltip then pcall(GameTooltip.Hide, GameTooltip) end
    end)

    -- Initial State
    if InCombatLockdown() then
        f:SetAlpha(1)
        -- Cannot Show() in combat if hidden, so we assume created visible or managed before combat
    else
        f:Show()
    end

    f:SetScript("OnUpdate", nil)

    return f
end

function sfui.trackedicons.UpdatePanelLayout(panelFrame, panelConfig)
    if not panelFrame or not panelConfig then return end
    if InCombatLockdown() then return end
    panelFrame.config = panelConfig

    -- PROTECT: Cannot move frames in combat!
    if InCombatLockdown() then return end

    local size = panelConfig.size or 50
    local spacing = panelConfig.spacing or 5

    -- Ensure panel position is updated from Config with Dynamic Anchoring
    panelFrame:ClearAllPoints()
    local isLeft = (panelConfig.x or 0) < 0
    local rawAnchor = panelConfig.anchor or (isLeft and "topright" or "topleft")
    local anchor = string.upper(rawAnchor)

    local targetFrame = UIParent
    local targetPoint = "BOTTOM"
    local anchorTo = panelConfig.anchorTo or "UIParent"

    if anchorTo == "Health Bar" and _G["sfui_bar0_Backdrop"] then
        targetFrame = _G["sfui_bar0_Backdrop"]
        targetPoint = "TOP" -- Default to top when anchoring to bars
    elseif anchorTo == "Tracked Bars" and _G["SfuiTrackedBarsContainer"] then
        targetFrame = _G["SfuiTrackedBarsContainer"]
        targetPoint = "TOP"
    end

    panelFrame:SetPoint(anchor, targetFrame, targetPoint, panelConfig.x or 0, panelConfig.y or 0)

    -- Hide all known icons first (full redraw of state)
    -- Safe out of combat
    if panelFrame.icons then
        for _, icon in pairs(panelFrame.icons) do
            if icon._glowActive then StopGlow(icon) end
            icon:Hide()
            icon:ClearAllPoints()
        end
    else
        panelFrame.icons = {}
    end

    local activeIcons = {}
    local entries = panelConfig.entries or {}

    for i, entry in ipairs(entries) do
        local id = entry.id
        if id then
            if not panelFrame.icons[i] then
                panelFrame.icons[i] = CreateIconFrame(panelFrame, id, entry)
            end

            local icon = panelFrame.icons[i]
            if icon then
                -- Update attributes (safe out of combat)
                icon.id = id
                icon.type = entry.type
                icon.entry = entry


                local isVisibleValue = UpdateIconState(icon, panelConfig)
                if isVisibleValue then
                    table.insert(activeIcons, icon)
                end
            end
        end
    end

    -- Layout Active Icons
    local numColumns = panelConfig.columns or #activeIcons
    if numColumns < 1 then numColumns = 1 end

    local growthH = panelConfig.growthH or (rawAnchor == "topright" and "Left" or "Right")
    local growthV = panelConfig.growthV or "Down"
    local hSign = (growthH == "Left") and -1 or 1
    local vSign = (growthV == "Up") and 1 or -1

    local maxWidth, maxHeight = 0, 0

    for i, icon in ipairs(activeIcons) do
        icon:ClearAllPoints()
        icon:SetSize(size, size)

        local col = (i - 1) % numColumns
        local row = math.floor((i - 1) / numColumns)

        local ox = col * (size + spacing) * hSign
        local oy = row * (size + spacing) * vSign

        icon:SetPoint(anchor, panelFrame, anchor, ox, oy)

        maxWidth = math.max(maxWidth, (col + 1) * (size + spacing) - spacing)
        maxHeight = math.max(maxHeight, (row + 1) * (size + spacing) - spacing)
    end

    panelFrame:SetSize(math.max(maxWidth, 1), math.max(maxHeight, 1))
end

function sfui.trackedicons.Update()
    -- Per-spec DB Migration / Initialization
    local specID = sfui.common.get_current_spec_id()
    if not specID or specID == 0 then return end -- No spec yet

    SfuiDB.iconsInitializedBySpec = SfuiDB.iconsInitializedBySpec or {}

    if not SfuiDB.iconsInitializedBySpec[specID] then
        local panels = sfui.common.get_cooldown_panels()
        SfuiDB.iconsInitializedBySpec[specID] = true

        local leftEntries = {}
        local rightEntries = {}

        -- Migrate legacy trackedIcons if present
        if SfuiDB.trackedIcons then
            for id, cfg in pairs(SfuiDB.trackedIcons) do
                if type(id) == "number" then
                    table.insert(leftEntries, { id = id, settings = cfg })
                end
            end
            SfuiDB.trackedIcons = nil -- Clear old
        end

        -- Get defaults from config
        local leftDefaults = sfui.config.cooldown_panel_defaults.left
        local rightDefaults = sfui.config.cooldown_panel_defaults.right

        -- Deep copy helper
        local function CopyDefaults(src)
            local copy = {}
            for k, v in pairs(src) do
                if type(v) == "table" then
                    copy[k] = {}
                    for tk, tv in pairs(v) do
                        copy[k][tk] = tv
                    end
                else
                    copy[k] = v
                end
            end
            return copy
        end

        -- Default Left Panel for this spec
        local leftPanel = CopyDefaults(leftDefaults)
        leftPanel.entries = leftEntries -- Add migrated icons
        table.insert(panels, leftPanel)

        -- Default Right Panel for this spec
        local rightPanel = CopyDefaults(rightDefaults)
        rightPanel.entries = rightEntries -- Add migrated icons
        table.insert(panels, rightPanel)

        -- Save panels to spec
        sfui.common.set_cooldown_panels(panels)
    end

    local panelConfigs = sfui.common.get_cooldown_panels()
    if not panelConfigs then return end

    -- Render Panels
    for i, panelConfig in ipairs(panelConfigs) do
        if panelConfig.enabled then
            if not panels[i] then
                panels[i] = CreateFrame("Frame", "SfuiIconPanel_" .. i, UIParent)
            end
            sfui.trackedicons.UpdatePanelLayout(panels[i], panelConfig)
        elseif panels[i] then
            if not InCombatLockdown() then
                panels[i]:Hide()
            end
        end
    end
end

function sfui.trackedicons.initialize()
    -- Event handling
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")          -- To retry layout updates
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED") -- Reload panels on spec change
    eventFrame:SetScript("OnEvent", function(self, event, unitTarget, updateInfo)
        if event == "PLAYER_REGEN_ENABLED" then
            sfui.trackedicons.Update()
        elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SPECIALIZATION_CHANGED" then
            -- Force a sync of spell data before UI refresh
            if sfui.common.SyncTrackedSpells then
                sfui.common.SyncTrackedSpells()
            end
            sfui.trackedicons.Update()
        elseif event == "UNIT_AURA" and unitTarget == "player" then
            -- NEW: Use updateInfo for targeted updates (12.0.1.65867+)
            if updateInfo and not InCombatLockdown() then
                local needsFullUpdate = false

                -- Process added auras
                if updateInfo.addedAuras and #updateInfo.addedAuras > 0 then
                    needsFullUpdate = true -- Full update needed to add new icons
                end

                -- Process updated auras (cooldown/stack changes)
                if updateInfo.updatedAuraInstanceIDs and not needsFullUpdate then
                    for _, instanceID in ipairs(updateInfo.updatedAuraInstanceIDs) do
                        pcall(function()
                            -- Update icons tracking this instance
                            local panelConfigs = sfui.common.get_cooldown_panels()
                            for i, panel in pairs(panels) do
                                local config = panelConfigs[i]
                                if panel.icons then
                                    for _, icon in pairs(panel.icons) do
                                        if icon.auraInstanceID == instanceID then
                                            UpdateIconState(icon, config)
                                        end
                                    end
                                end
                            end
                        end)
                    end
                end

                -- Process removed auras
                if updateInfo.removedAuraInstanceIDs and #updateInfo.removedAuraInstanceIDs > 0 then
                    needsFullUpdate = true -- Full update needed to remove icons
                end

                -- Do full update if needed
                if needsFullUpdate then
                    sfui.trackedicons.Update()
                end
            else
                -- Fallback: Generic update (backwards compatibility or combat)
                if InCombatLockdown() then
                    local panelConfigs = sfui.common.get_cooldown_panels()
                    for i, panel in pairs(panels) do
                        local config = panelConfigs[i]
                        if panel.icons then
                            for _, icon in pairs(panel.icons) do
                                UpdateIconState(icon, config)
                            end
                        end
                    end
                else
                    sfui.trackedicons.Update()
                end
            end
        else
            -- Other events: use existing logic
            if InCombatLockdown() then
                -- Iterate existing panels and just update states/cooldowns
                local panelConfigs = sfui.common.get_cooldown_panels()
                for i, panel in pairs(panels) do
                    local config = panelConfigs[i]
                    if panel.icons then
                        for _, icon in pairs(panel.icons) do
                            UpdateIconState(icon, config)
                        end
                    end
                end
            else
                sfui.trackedicons.Update()
            end
        end
    end)

    -- Throttled OnUpdate to ensure snappy "Ready" state transitions (Glow/Alpha)
    local lastUpdate = 0
    eventFrame:SetScript("OnUpdate", function(self, elapsed)
        lastUpdate = lastUpdate + elapsed
        if lastUpdate > 0.1 then
            lastUpdate = 0
            local panelConfigs = sfui.common.get_cooldown_panels()
            if not InCombatLockdown() or panelConfigs then
                for i, panel in pairs(panels) do
                    local config = panelConfigs[i]
                    if panel.icons then
                        for _, icon in pairs(panel.icons) do
                            UpdateIconState(icon, config)
                        end
                    end
                end
            end
        end
    end)

    sfui.trackedicons.Update()
end
