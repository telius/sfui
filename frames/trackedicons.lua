local addonName, addon = ...
sfui.trackedicons = {}

local C_Spell = C_Spell
local C_Item = C_Item
local GetTime = GetTime

local panels = {} -- Active icon panels
local issecretvalue = sfui.common.issecretvalue

-- STATIC REUSE (Memory Optimization)
local _tempGlowCfg = {}
local _defaultColor = { r = 1, g = 1, b = 0 }
local _emptyTable = {}

-- Helper: Get value from entry → panel → global → hardcoded default (M+ safe)
-- All sources are safe tables (user config, SfuiDB, config.lua) - no secret values
local function GetIconValue(entrySettings, panelConfig, key, default)
    if entrySettings and entrySettings[key] ~= nil then return entrySettings[key] end
    if panelConfig and panelConfig[key] ~= nil then return panelConfig[key] end
    -- Check global settings (M+ safe: no secret values in SfuiDB)
    local globalCfg = SfuiDB and SfuiDB.iconGlobalSettings
    if globalCfg and globalCfg[key] ~= nil then return globalCfg[key] end
    -- Check config.lua defaults (M+ safe: static config)
    local g = sfui.config
    local configDefault = g and g.icon_panel_global_defaults
    if configDefault and configDefault[key] ~= nil then return configDefault[key] end
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

sfui.trackedicons.StopGlow = sfui.glows.stop_glow

-- Local wrapper to ensure state cleanup
-- Local wrapper to ensure state cleanup
local function StopGlow(icon)
    sfui.glows.stop_glow(icon)
    -- Do NOT clear _glowStartTime here, as it breaks the timeout logic (infinite restart loop)
    -- _glowStartTime is cleared explicitly when the icon is no longer ready.
    icon._lastGlowCfg = nil
end


local function StartGlow(icon, cfg)
    sfui.glows.start_glow(icon, cfg)
    -- Track config for comparison (needed by existing code)
    icon._lastGlowCfg = sfui.common.copy(cfg)
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

local function IsDragonriding()
    if not IsMounted() then return false end

    local isDragonriding = false
    -- Native API check (might be protected/restricted?)
    pcall(function()
        isDragonriding = (C_PlayerInfo and C_PlayerInfo.IsDragonriding and C_PlayerInfo.IsDragonriding("player"))
    end)
    return isDragonriding
end

-- Helper to update icon state (visibility, cooldown, charges)
local function UpdateIconState(icon, panelConfig)
    if not icon.id or not icon.entry then return false end
    local entrySettings = icon.entry.settings or _emptyTable
    local count = 0
    local isEnabled = true

    -- Resolve actual spell/item ID for cooldown types
    local activeID = icon.id
    local entry = icon.entry

    -- 1. Determine the Correct Spell/Item ID and Texture
    local iconTexture
    if icon.type == "cooldown" and entry and entry.cooldownID then
        local cdInfo = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo(entry.cooldownID)
        if cdInfo then
            activeID = cdInfo.overrideSpellID or cdInfo.spellID
            iconTexture = C_Spell.GetSpellTexture(activeID)
        else
            activeID = entry.spellID or icon.id
            iconTexture = C_Spell.GetSpellTexture(activeID)
        end
    elseif icon.type == "item" then
        iconTexture = C_Item.GetItemIconByID(activeID)
    else
        iconTexture = C_Spell.GetSpellTexture(activeID)
    end

    -- 2. FORCE TEXTURE REFRESH (Fixes "Reload Required" for reordering)
    -- This ensures that when frames are reused, the visual representation matches the new ID.
    if icon.texture and iconTexture then
        icon.texture:SetTexture(iconTexture)
    end
    icon._lastActiveID = activeID

    if icon.type == "item" then
        local ok, countVal = pcall(pcall_item_cd, icon)
        if ok then
            count = countVal or 0
            isEnabled = icon._isEnabled
        end
    else
        -- Use resolved activeID for spell/cooldown types
        local tempIcon = { id = activeID }
        local ok, enabledVal = pcall(pcall_spell_cd, tempIcon)
        if ok then isEnabled = enabledVal end

        if not issecretvalue(activeID) then
            local charges = C_Spell.GetSpellCharges(activeID)
            if charges then
                count = sfui.common.SafeValue(charges.currentCharges, 0)
            end
        end

        -- CooldownCompanion Pattern: Use DurationObject API with IsShown() signal
        icon._durationObj = nil

        if activeID and not issecretvalue(activeID) then
            -- Get cooldown info for GCD detection (isOnGCD is NeverSecret)
            local ok_cd, cdInfo = pcall(C_Spell.GetSpellCooldown, activeID)
            local isOnGCD = ok_cd and cdInfo and cdInfo.isOnGCD

            -- Get DurationObject for cooldown tracking
            local ok_dur, spellCooldownDuration = pcall(C_Spell.GetSpellCooldownDuration, activeID)

            if ok_dur and spellCooldownDuration then
                -- GCD filter - don't show GCD swipes or store durObj for GCD
                if not isOnGCD then
                    local useIt = false

                    -- Check if DurationObject has secret values
                    local ok_secret, hasSecrets = pcall(function()
                        return spellCooldownDuration:HasSecretValues()
                    end)

                    if ok_secret and not hasSecrets then
                        -- No secrets: use IsZero() to filter ready spells
                        local ok_zero, isZero = pcall(function()
                            return spellCooldownDuration:IsZero()
                        end)
                        if ok_zero and not isZero then
                            useIt = true
                        end
                    else
                        -- Secret values: Use IsShown() as C++ signal
                        -- SetCooldown auto-shows frame only when duration > 0
                        local ok_set = pcall(function()
                            icon.cooldown:SetCooldownFromDurationObject(spellCooldownDuration)
                        end)
                        if ok_set and icon.cooldown:IsShown() then
                            useIt = true
                        end
                    end

                    if useIt then
                        icon._durationObj = spellCooldownDuration
                        pcall(function()
                            icon.cooldown:SetCooldownFromDurationObject(spellCooldownDuration)
                            if icon.shadowCooldown then
                                icon.shadowCooldown:SetCooldownFromDurationObject(spellCooldownDuration)
                            end
                        end)
                    else
                        -- No cooldown - clear frames
                        icon.cooldown:Clear()
                        if icon.shadowCooldown then icon.shadowCooldown:Clear() end
                    end
                else
                    -- On GCD - clear swipe frames (don't store durObj)
                    icon.cooldown:Clear()
                    if icon.shadowCooldown then icon.shadowCooldown:Clear() end
                end
            else
                -- No duration object - spell is ready
                icon.cooldown:Clear()
                if icon.shadowCooldown then icon.shadowCooldown:Clear() end
            end
            -- If activeID is secret but we have GetCooldownDurationObj fallback, use it
        elseif activeID and issecretvalue(activeID) then
            local fallbackDurObj = sfui.common.GetCooldownDurationObj(activeID)
            if fallbackDurObj then
                local tempCDIcon = { cooldown = icon.cooldown, shadowCooldown = icon.shadowCooldown }
                pcall(pcall_sync_swipe, tempCDIcon, fallbackDurObj)
                icon._durationObj = fallbackDurObj
            end
        else
            -- No duration object = Ready (Clear cooldown)
            icon.cooldown:Clear()
            if icon.shadowCooldown then icon.shadowCooldown:Clear() end
        end
    end

    icon._isItem = (icon.type == "item")

    -- Usability Logic (Execute, Procs, Resource constraints)
    local isUsable, notEnoughPower = true, false
    if activeID and not issecretvalue(activeID) and icon.type ~= "item" then
        isUsable, notEnoughPower = C_Spell.IsSpellUsable(activeID)
    end

    -- Readiness Logic (Native Safe)
    -- Ready Check: Based on stored duration object AND usability
    local isReady = true
    local safeS, safeD, safeEnabled = 0, 0, true
    local countSafe = count

    if icon.type == "item" then
        -- Item CD uses old method
        safeS, safeD, safeEnabled = icon._start or 0, icon._duration or 0, icon._isEnabled or true
        isReady = (safeS == 0 or (GetTime() - safeS) >= safeD or safeD <= 1.5) and safeEnabled
    else
        -- Spell/Cooldown uses DurationObject (_durationObj)
        -- If we have a stored duration object, spell is NOT ready
        -- If no duration object, spell IS ready (or has charges available)
        -- FIXED: Explicitly check count > 0 because Lua treats 0 as true
        -- TAINT FIX: Check for secret value before comparing
        local hasCharges = false
        if countSafe and not issecretvalue(countSafe) then
            hasCharges = (countSafe > 0)
        end
        -- Spell is only "Ready" if it's off cooldown (or has charges) AND is usable
        isReady = (icon._durationObj == nil or hasCharges) and (icon._isEnabled ~= false) and isUsable
    end

    -- Visibility Decision: Icons are always shown if they exist in the panel,
    -- but they might be desaturated or have alpha.
    local shouldShow = true
    local isVisible = shouldShow -- In simple panel mode, all icons are visible holders

    if isVisible then
        if not icon:IsShown() then
            -- Non-protected frames can Show() freely during combat
            icon:Show()
        end

        -- Update Count Text
        UpdateCountText(icon, count)

        -- Visibility / Settings check
        icon.cooldown:SetHideCountdownNumbers(not GetIconValue(entrySettings, panelConfig, "textEnabled", true))

        -- Visuals
        local showGlow = GetIconValue(entrySettings, panelConfig, "readyGlow", true)
        local useDesat = GetIconValue(entrySettings, panelConfig, "cooldownDesat", true)

        -- Desaturation Logic: Use stored duration object (CooldownCompanion pattern)
        local isOnCooldown = false
        if icon._durationObj then
            -- We have a duration object (non-GCD cooldown)
            isOnCooldown = true
        end

        if icon.texture then
            -- Desaturate if on cooldown (if enabled) OR if the spell is unusable (health, proc, etc)
            local desaturate = (useDesat and isOnCooldown) or (not isUsable)
            icon.texture:SetDesaturated(desaturate)

            -- Alpha logic: use cooldown alpha if on CD, otherwise dim if unusable
            local alpha = 1.0
            if isOnCooldown then
                alpha = GetIconValue(entrySettings, panelConfig, "alphaOnCooldown", 1.0)
            elseif not isUsable then
                -- Dim unusable icons slightly more than default to distinguish from "ready"
                alpha = 0.5
            end
            icon:SetAlpha(alpha)

            -- Color tinting: Use Blizzard's choice for power-restricted spells
            local useResourceCheck = GetIconValue(entrySettings, panelConfig, "useResourceCheck", true)
            if notEnoughPower and useResourceCheck then
                icon.texture:SetVertexColor(0.5, 0.5, 1.0) -- Blue tint for out of mana/power
            else
                icon.texture:SetVertexColor(1, 1, 1)
            end
        end

        -- Glow Logic (Permanent while ready)
        if isReady and showGlow then
            -- Check if glow has been active for too long
            local maxDuration = sfui.config.cooldown_panel_defaults.glow_max_duration or 5.0
            local now = GetTime()

            if not icon._glowStartTime then
                icon._glowStartTime = now
            end

            local elapsed = now - icon._glowStartTime

            if elapsed < maxDuration then
                -- Build glow configuration
                local glowType = GetIconValue(entrySettings, panelConfig, "glowType", "pixel")

                _tempGlowCfg.glowType = glowType
                _tempGlowCfg.glowColor = GetIconValue(entrySettings, panelConfig, "glowColor", _defaultColor)
                _tempGlowCfg.glowScale = GetIconValue(entrySettings, panelConfig, "glowScale", 1.0)
                _tempGlowCfg.glowIntensity = GetIconValue(entrySettings, panelConfig, "glowIntensity", 1.0)
                _tempGlowCfg.glowSpeed = GetIconValue(entrySettings, panelConfig, "glowSpeed", 0.25)
                _tempGlowCfg.glowLines = GetIconValue(entrySettings, panelConfig, "glowLines", 8)
                _tempGlowCfg.glowThickness = GetIconValue(entrySettings, panelConfig, "glowThickness", 2)
                _tempGlowCfg.glowParticles = GetIconValue(entrySettings, panelConfig, "glowParticles", 4)

                local needsRestart = false
                if not icon._glowActive then
                    needsRestart = true
                elseif icon._lastGlowType ~= glowType then
                    needsRestart = true
                else
                    local prev = icon._lastGlowCfg
                    if prev and prev.glowColor then
                        if math.abs(prev.glowColor.r - _tempGlowCfg.glowColor.r) > 0.01 or
                            math.abs(prev.glowColor.g - _tempGlowCfg.glowColor.g) > 0.01 or
                            math.abs(prev.glowColor.b - _tempGlowCfg.glowColor.b) > 0.01 or
                            math.abs(prev.glowScale - _tempGlowCfg.glowScale) > 0.01 or
                            math.abs(prev.glowIntensity - _tempGlowCfg.glowIntensity) > 0.01 or
                            math.abs(prev.glowSpeed - _tempGlowCfg.glowSpeed) > 0.01 or
                            math.abs((prev.glowLines or 8) - _tempGlowCfg.glowLines) > 0.01 or
                            math.abs((prev.glowThickness or 2) - _tempGlowCfg.glowThickness) > 0.01 or
                            math.abs((prev.glowParticles or 4) - _tempGlowCfg.glowParticles) > 0.01 then
                            needsRestart = true
                        end
                    end
                end

                if needsRestart then
                    if icon._glowActive then StopGlow(icon) end
                    StartGlow(icon, _tempGlowCfg)
                end
            else
                -- Duration exceeded - stop glow (keep timer to prevent restart)
                if icon._glowActive then
                    StopGlow(icon)
                end
            end
        else
            -- Reset start time when not ready (ensures it triggers fresh next time)
            icon._glowStartTime = nil
            if icon._glowActive then
                StopGlow(icon)
            end
        end
    else
        -- Icon is not visible - hide it
        icon:Hide()
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
    if entry.type == "cooldown" and entry.cooldownID then
        -- Get cooldown info from Blizzard's CDM
        local cdInfo = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo(entry.cooldownID)
        if cdInfo then
            local spellID = cdInfo.overrideSpellID or cdInfo.spellID
            iconTexture = C_Spell.GetSpellTexture(spellID)
        else
            -- Fallback if cooldown no longer exists
            iconTexture = entry.spellID and C_Spell.GetSpellTexture(entry.spellID)
        end
    elseif entry.type == "item" then
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

    -- DO NOT register for clicks - this makes frames "protected" and causes combat taint
    -- User doesn't need clickable icons, just visibility and cooldown tracking
    -- Tooltips still work via OnEnter/OnLeave scripts below

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

    -- Initial State: Show immediately
    -- Non-protected frames can be shown/hidden freely even during combat
    f:Show()

    f:SetScript("OnUpdate", nil)

    return f
end

function sfui.trackedicons.UpdatePanelLayout(panelFrame, panelConfig)
    if not panelFrame or not panelConfig then return end
    panelFrame.config = panelConfig

    local size = panelConfig.size or 50
    local spacing = panelConfig.spacing or 5

    -- Register Event-Driven Visibility Handler for this panel
    if not panelFrame.visHandler then
        panelFrame.visHandler = CreateFrame("Frame", nil, panelFrame)
        panelFrame.visHandler:RegisterEvent("PLAYER_REGEN_DISABLED")
        panelFrame.visHandler:RegisterEvent("PLAYER_REGEN_ENABLED")
        panelFrame.visHandler:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
        panelFrame.visHandler:RegisterEvent("UNIT_POWER_BAR_SHOW")
        panelFrame.visHandler:RegisterEvent("UNIT_POWER_BAR_HIDE")

        panelFrame.visHandler:SetScript("OnEvent", function(self, event)
            if not SfuiDB or not SfuiDB.iconGlobalSettings then return end

            local shouldShow = true
            local globalVis = SfuiDB.iconGlobalSettings

            -- Robust Combat Detection
            -- PLAYER_REGEN_DISABLED = We are entering combat (InCombatLockdown might lag slightly)
            local inCombat = InCombatLockdown()
            if event == "PLAYER_REGEN_DISABLED" then
                inCombat = true
            elseif event == "PLAYER_REGEN_ENABLED" then
                inCombat = false
            end

            -- Debug
            -- print("SFUI Vis Check:", event, "InCombat:", inCombat, "IsMounted:", IsMounted())

            -- 1. Check OOC
            if globalVis.hideOOC and not inCombat then
                shouldShow = false
            end

            -- 2. Check Dragonriding
            if shouldShow and globalVis.hideDragonriding then
                -- Only apply Dragonriding Hide if we are NOT in combat
                -- Combat visibility always takes priority
                if sfui.common.IsDragonriding() and not inCombat then
                    shouldShow = false
                end
            end

            -- OVERRIDE: Always show if Options Panel (Global/Icons tabs) is open
            if _G["SfuiCooldownsViewer"] and _G["SfuiCooldownsViewer"]:IsShown() then
                local tabId = _G["SfuiCooldownsViewer"].selectedTabId
                if tabId == 1 or tabId == 3 then
                    shouldShow = true
                end
            end

            -- Apply Visibility State
            if shouldShow then
                if not panelFrame:IsShown() then
                    panelFrame:Show()
                end
            else
                if panelFrame:IsShown() then
                    panelFrame:Hide()
                end
            end
        end)
    end



    -- Trigger initial visibility check IMMEDIATELY
    if panelFrame.visHandler then
        pcall(panelFrame.visHandler:GetScript("OnEvent"), panelFrame.visHandler)
    end



    -- Ensure panel position is updated from Config with Dynamic Anchoring
    panelFrame:ClearAllPoints()

    -- Center placement uses BOTTOM anchor for proper centering
    local rawAnchor = panelConfig.anchor
    if panelConfig.placement == "center" then
        rawAnchor = "bottom"
    elseif not rawAnchor then
        local isLeft = (panelConfig.x or 0) < 0
        rawAnchor = isLeft and "topright" or "topleft"
    end
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
    else
        -- Check if anchoring to another panel by name
        for _, otherPanel in pairs(panels) do
            if otherPanel.config and otherPanel.config.name == anchorTo then
                targetFrame = otherPanel
                targetPoint = "BOTTOM" -- Default stacking direction
                break
            end
        end
    end

    panelFrame:SetPoint(anchor, targetFrame, targetPoint, panelConfig.x or 0, panelConfig.y or 0)

    -- Hide all icons first (full redraw of state)
    -- Non-protected frames can be manipulated freely during combat
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

    -- Force Single Row for Center Panel
    if panelConfig.placement == "center" or panelConfig.growthH == "Center" then
        numColumns = #activeIcons
    end

    local growthH = panelConfig.growthH or (rawAnchor == "topright" and "Left" or "Right")
    local growthV = panelConfig.growthV or "Down"
    local hSign = (growthH == "Left") and -1 or 1
    local vSign = (growthV == "Up") and 1 or -1

    local maxWidth, maxHeight = 0, 0

    -- Auto-Span Width Logic
    local spanWidth = GetIconValue(nil, panelConfig, "spanWidth", false)
    if spanWidth and (panelConfig.placement == "center" or growthH == "Center") and #activeIcons > 0 then
        local targetWidth = sfui.config.healthBar.width or 300
        local iconsPerRow = math.min(numColumns, #activeIcons)

        -- Calculate current width with configured size/spacing
        local currentWidth = (iconsPerRow * size) + (math.max(0, iconsPerRow - 1) * spacing)

        if currentWidth < targetWidth then
            -- Expand spacing to fill width
            if iconsPerRow > 1 then
                spacing = (targetWidth - (iconsPerRow * size)) / (iconsPerRow - 1)
            end
        else
            -- Shrink size to fit width (keeping spacing fixed)
            -- size * N + spacing * (N-1) = targetWidth
            -- size * N = targetWidth - spacing * (N-1)
            local newSize = (targetWidth - (math.max(0, iconsPerRow - 1) * spacing)) / iconsPerRow
            if newSize < 10 then newSize = 10 end -- Hard min size
            size = newSize
        end
    end

    -- Layout icons based on growth mode
    -- Non-protected frames can be positioned freely even during combat
    if panelConfig.placement == "center" or growthH == "Center" then
        local totalIcons = #activeIcons
        for i, icon in ipairs(activeIcons) do
            icon:ClearAllPoints()
            icon:SetSize(size, size)

            local row = math.floor((i - 1) / numColumns)
            local colInRow = (i - 1) % numColumns

            -- Calculate icons in this specific row for centering
            local startIdx = row * numColumns + 1
            local endIdx = math.min((row + 1) * numColumns, totalIcons)
            local numInRow = endIdx - startIdx + 1

            -- Midpoint-based centering: [col] - ([count]-1)/2
            -- Result: 1 icon = 0, 2 icons = -0.5 and 0.5, etc.
            -- This naturally handles spacing when multiplied by (size + spacing)
            local centerOffset = colInRow - (numInRow - 1) / 2

            local ox = centerOffset * (size + spacing)
            local oy = row * (size + spacing) * vSign

            icon:SetPoint(anchor, panelFrame, anchor, ox, oy)

            -- Calculate panel bounds
            local rowWidth = numInRow * size + math.max(0, numInRow - 1) * spacing
            maxWidth = math.max(maxWidth, rowWidth)
            maxHeight = math.max(maxHeight, (row + 1) * (size + spacing) - spacing)
        end
    else
        -- Standard left-to-right, top-to-bottom layout
        for idx, icon in ipairs(activeIcons) do
            local col = (idx - 1) % numColumns
            local row = math.floor((idx - 1) / numColumns)

            local ox = col * (size + spacing) * hSign
            local oy = row * (size + spacing) * vSign

            icon:SetSize(size, size)
            icon:SetPoint(anchor, panelFrame, anchor, ox, oy)

            maxWidth = math.max(maxWidth, (col + 1) * size + col * spacing)
            maxHeight = math.max(maxHeight, (row + 1) * size + row * spacing)
        end
    end

    -- Background Frame Logic (Universal for all panels)
    local showBG = GetIconValue(nil, panelConfig, "showBackground", true)
    local bgAlpha = GetIconValue(nil, panelConfig, "backgroundAlpha", 0.5)

    if showBG and #activeIcons > 0 then
        if not panelFrame.bg then
            panelFrame.bg = CreateFrame("Frame", nil, panelFrame, "BackdropTemplate")
            panelFrame.bg:SetFrameStrata("BACKGROUND")
            panelFrame.bg:SetBackdrop({
                bgFile = "Interface/Buttons/WHITE8X8",
                insets = { left = 0, right = 0, top = 0, bottom = 0 }
            })
            panelFrame.bg:SetBackdropColor(0, 0, 0, bgAlpha)
        else
            panelFrame.bg:SetBackdropColor(0, 0, 0, bgAlpha)
            panelFrame.bg:Show()
        end

        local bgW = maxWidth
        local bgH = maxHeight
        panelFrame.bg:SetSize(bgW, bgH)

        panelFrame.bg:ClearAllPoints()
        if panelConfig.placement == "center" or growthH == "Center" then
            -- For centered layouts, the icons are horizontally centered on the anchor
            -- but vertically they usually grow from the anchor (TOP or BOTTOM)
            panelFrame.bg:SetPoint(anchor, panelFrame, anchor, 0, 0)
        else
            -- Standard growth
            panelFrame.bg:SetPoint(anchor, panelFrame, anchor, 0, 0)
        end
    elseif panelFrame.bg then
        panelFrame.bg:Hide()
    end

    panelFrame:SetSize(math.max(maxWidth, 1), math.max(maxHeight, 1))
end

-- Force refresh all glows (called when global settings change)
function sfui.trackedicons.ForceRefreshGlows()
    for _, panel in pairs(panels) do
        if panel.icons then
            for _, icon in pairs(panel.icons) do
                if icon._glowActive then
                    StopGlow(icon)
                end
            end
        end
    end
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

    -- Helper to remove legacy defaults from panels so they use global settings
    local function SanitizePanelConfig(panelConfig)
        if not panelConfig then return end

        -- Keys to purge from panel config (ensures fallback to Global settings)
        local keysToPurge = {
            "readyGlow", "cooldownDesat",
            "glowType", "glowColor",
            "glowScale", "glowIntensity", "glowSpeed",
            "glowLines", "glowThickness", "glowParticles"
        }

        for _, key in ipairs(keysToPurge) do
            -- Only purge if it matches the OLD "blizzard" default or simple values
            -- But honestly, since there's no UI for per-panel settings, it's safe to purge all
            -- to unblock the user. User can override in global settings anyway.
            panelConfig[key] = nil
        end

        -- ALSO purge per-entry settings (legacy icon-specific overrides)
        if panelConfig.entries then
            for _, entry in ipairs(panelConfig.entries) do
                if entry.settings then
                    for _, key in ipairs(keysToPurge) do
                        entry.settings[key] = nil
                    end
                end
            end
        end
    end

    -- Render Panels
    for i, panelConfig in ipairs(panelConfigs) do
        -- Sanitize configuration to fix "invisible defaults" bug
        SanitizePanelConfig(panelConfig)

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

-- Hook to hide specific categories from Blizzard's CooldownViewer
local function SyncBlizzardVisibility()
    if not BuffBarCooldownViewer or not BuffBarCooldownViewer.itemFramePool then return end

    pcall(function()
        for blizzFrame in BuffBarCooldownViewer.itemFramePool:EnumerateActive() do
            if blizzFrame.cooldownID then
                local shouldHide = false
                -- Check category via C_CooldownViewer (if available)
                if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(blizzFrame.cooldownID)
                    if info then
                        -- Category 0 = Essential, 1 = Utility
                        -- Hide these as we track them with icons
                        if info.category == 0 or info.category == 1 then
                            shouldHide = true
                        end
                    end
                end

                if shouldHide then
                    blizzFrame:SetAlpha(0)
                    if blizzFrame.SetAlpha then -- Ensure interaction is disabled too?
                        blizzFrame:EnableMouse(false)
                    end
                end
            end
        end
    end)
end

function sfui.trackedicons.initialize()
    -- Ensure Blizzard addon is loaded so we can hook it
    local loaded, reason = C_AddOns.LoadAddOn("Blizzard_CooldownViewer")

    -- Register hooks if available
    if BuffBarCooldownViewer then
        if BuffBarCooldownViewer.RefreshData then
            hooksecurefunc(BuffBarCooldownViewer, "RefreshData", SyncBlizzardVisibility)
        end
        if BuffBarCooldownViewer.RefreshApplications then
            hooksecurefunc(BuffBarCooldownViewer, "RefreshApplications", SyncBlizzardVisibility)
        end
        if BuffBarCooldownViewer.SetAuraInstanceInfo then
            hooksecurefunc(BuffBarCooldownViewer, "SetAuraInstanceInfo", SyncBlizzardVisibility)
        end
        -- Initial sync
        SyncBlizzardVisibility()
    end

    -- Hide Blizzard Cooldown Frames
    if sfui.common.hide_blizzard_cooldown_viewers then
        sfui.common.hide_blizzard_cooldown_viewers()
    end

    -- Event handling
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")          -- To retry layout updates
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")         -- Visibility trigger
    eventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")  -- Dragonriding trigger
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED") -- Reload panels on spec change
    eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")          -- Talent changes (for cooldown overrideSpellID)
    eventFrame:SetScript("OnEvent", function(self, event, unitTarget, updateInfo)
        if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
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
                            for _, panel in pairs(panels) do
                                local config = panel.config -- Use stored config from UpdatePanelLayout
                                if panel.icons and config then
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
                    for _, panel in pairs(panels) do
                        local config = panel.config -- Use stored config
                        if panel.icons and config then
                            for _, icon in pairs(panel.icons) do
                                UpdateIconState(icon, config)
                            end
                        end
                    end
                else
                    sfui.trackedicons.Update()
                end
            end
        elseif event == "TRAIT_CONFIG_UPDATED" then
            -- Talent changes: refresh cooldown-type icons for overrideSpellID updates
            if not InCombatLockdown() then
                local panelConfigs = sfui.common.get_cooldown_panels()
                for _, panel in pairs(panels) do
                    local config = panel.config -- Use stored config
                    if panel.icons and config then
                        for _, icon in pairs(panel.icons) do
                            -- Only refresh cooldown-type icons (they use overrideSpellID)
                            if icon.entry and icon.entry.type == "cooldown" then
                                UpdateIconState(icon, config)
                            end
                        end
                    end
                end
            end
        else
            -- Other events: use existing logic
            if InCombatLockdown() then
                -- Iterate existing panels and just update states/cooldowns
                local panelConfigs = sfui.common.get_cooldown_panels()
                for _, panel in pairs(panels) do
                    local config = panel.config -- Use stored config
                    if panel.icons and config then
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
                for _, panel in pairs(panels) do
                    local config = panel.config -- Use stored config
                    if panel.icons and config then
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
