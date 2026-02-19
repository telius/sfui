local addonName, addon = ...
sfui.trackedicons = {}

local C_Spell = C_Spell
local C_Item = C_Item
local C_CooldownViewer = C_CooldownViewer
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame
local UIParent = UIParent
local hooksecurefunc = hooksecurefunc
local C_Timer = C_Timer

local panels = {} -- Active icon panels
local issecretvalue = sfui.common.issecretvalue
-- STATIC REUSE (Memory Optimization)
local _tempGlowCfg = {}
local _defaultColor = { 1, 1, 0, 1 }
local _emptyTable = {}
local _iconCounter = 0

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

-- pcall_spell_cd and pcall_sync_swipe removed — no longer needed
-- SetCooldown handles secret values natively at C++ level

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
    -- Track config for comparison without allocating a new table
    if not icon._lastGlowCfg then icon._lastGlowCfg = {} end
    local t = icon._lastGlowCfg
    t.glowType = cfg.glowType
    t.glowColor = cfg.glowColor -- Shared ref is fine for comparison
    t.glowScale = cfg.glowScale
    t.glowIntensity = cfg.glowIntensity
    t.glowSpeed = cfg.glowSpeed
    t.glowLines = cfg.glowLines
    t.glowThickness = cfg.glowThickness
    t.glowParticles = cfg.glowParticles
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

    if isSecret then
        sfui.common.SafeSetText(icon.count, count, 0)
        icon.count:Show()
    elseif type(count) == "number" and count > 0 then
        icon.count:SetText(tostring(count))
        icon.count:Show()
    else
        icon.count:Hide()
    end
end

-- IsDragonriding: use sfui.common.IsDragonriding() (single source of truth)

-- Lightweight cooldown logic (CooldownCompanion + TweaksUI pattern):
--   • SetCooldown() accepts secret values natively (C++ level)
--   • isOnGCD is NeverSecret — always safe to branch on
--   • Scratch cooldown probe only when values are secret (M+ combat)
--   • Zero closures — all pcall uses the no-allocation form
local scratchParent = CreateFrame("Frame")
scratchParent:Hide()
local scratchCooldown = CreateFrame("Cooldown", nil, scratchParent, "CooldownFrameTemplate")

local function UpdateIconCooldown(icon, activeID)
    local count = 0
    local isEnabled = true
    local isUsable, notEnoughPower = true, false
    local isOnCooldown = false

    if icon.type == "item" then
        local ok, countVal = pcall(pcall_item_cd, icon)
        if ok then
            count = countVal or 0
            isEnabled = icon._isEnabled
            local d = icon._duration
            if d ~= nil and d > 0 then isOnCooldown = true end
        end
    else
        -- Spell: officially supports tainted spellIdentifiers
        local ok_cd, cdInfo = pcall(C_Spell.GetSpellCooldown, activeID)

        if ok_cd and cdInfo ~= nil then
            -- SetCooldown handles secret values natively
            icon.cooldown:SetCooldown(cdInfo.startTime, cdInfo.duration)
            if icon.shadowCooldown then
                icon.shadowCooldown:SetCooldown(cdInfo.startTime, cdInfo.duration)
            end

            -- isOnGCD is NeverSecret (safe to branch)
            local isOnGCD = cdInfo.isOnGCD
            local d = cdInfo.duration
            if d ~= nil then
                if not issecretvalue(d) then
                    -- Readable: d > 1.5 catches real CDs, skips GCD
                    isOnCooldown = (type(d) == "number" and d > 1.5)
                else
                    -- Secret: scratch probe
                    scratchCooldown:Hide()
                    scratchCooldown:SetCooldown(cdInfo.startTime or 0, cdInfo.duration or 0)
                    isOnCooldown = scratchCooldown:IsShown() and not isOnGCD
                    scratchCooldown:Hide()
                end
            end

            -- Clear swipe only when confirmed GCD-only
            if not isOnCooldown and isOnGCD then
                icon.cooldown:Clear()
                if icon.shadowCooldown then icon.shadowCooldown:Clear() end
            end

            -- isEnabled can be secret
            local en = cdInfo.isEnabled
            if en ~= nil and not issecretvalue(en) then
                isEnabled = en
            end
        else
            icon.cooldown:Clear()
            if icon.shadowCooldown then icon.shadowCooldown:Clear() end
        end

        -- Charges: supports tainted activeID
        local ok_ch, charges = pcall(C_Spell.GetSpellCharges, activeID)
        if ok_ch and charges ~= nil then
            local cc = charges.currentCharges
            if cc ~= nil and not issecretvalue(cc) then
                count = cc
            end
        end
    end

    -- Glow arming
    if icon._wasOnCooldown and not isOnCooldown then
        icon._pendingGlow = true
    end
    icon._wasOnCooldown = isOnCooldown

    -- Usability: supports tainted activeID
    if icon.type ~= "item" then
        local ok_u, u, p = pcall(C_Spell.IsSpellUsable, activeID)
        if ok_u then
            -- Guard results: if secret, assume true so we don't hide spells blindly
            isUsable = (u == nil or issecretvalue(u)) or u
            notEnoughPower = (p ~= nil and not issecretvalue(p)) and p
        end
        if not HasFullControl() and not isUsable then isUsable = true end
    end

    -- Readiness
    local isReady
    if icon.type == "item" then
        isReady = not isOnCooldown and (isEnabled ~= false)
    else
        -- count is plain number (guarded above)
        isReady = (not isOnCooldown or count > 0) and (isEnabled ~= false) and isUsable
    end

    return count, isReady, isUsable, notEnoughPower, isOnCooldown
end

-- Visuals: desaturation, alpha, resource tint
local function UpdateIconVisuals(icon, entrySettings, panelConfig, isUsable, isOnCooldown, notEnoughPower)
    if not icon.texture then return end

    -- Desaturate during cooldowns OR when unusable (Execute)
    local useDesat = GetIconValue(entrySettings, panelConfig, "cooldownDesat", true)
    local desaturate = (useDesat and isOnCooldown) or (not isUsable)
    if icon._currentDesaturated ~= desaturate then
        icon.texture:SetDesaturated(desaturate)
        icon._currentDesaturated = desaturate
    end

    -- Alpha: dim during cooldowns OR when unusable
    local baseAlpha = (not isUsable) and 0.5 or 1.0
    local alpha = isOnCooldown and GetIconValue(entrySettings, panelConfig, "alphaOnCooldown", 0.5) or baseAlpha
    if icon._currentAlpha ~= alpha then
        icon:SetAlpha(alpha)
        icon._currentAlpha = alpha
    end

    -- Resource check: blue tint when out of power
    local useResourceCheck = GetIconValue(entrySettings, panelConfig, "useResourceCheck", true)
    local targetColor = (notEnoughPower and useResourceCheck) and "blue" or "white"
    if icon._currentVertexColor ~= targetColor then
        if targetColor == "blue" then
            icon.texture:SetVertexColor(0.5, 0.5, 1.0)
        else
            local textColor = GetIconValue(entrySettings, panelConfig, "textColor", { 1, 1, 1, 1 })
            icon.texture:SetVertexColor(textColor[1] or 1, textColor[2] or 1, textColor[3] or 1)
        end
        icon._currentVertexColor = targetColor
    end
end

-- Helper: Update Glows
local function UpdateIconGlow(icon, entrySettings, panelConfig, isReady)
    local showGlow = GetIconValue(entrySettings, panelConfig, "readyGlow", true)

    -- Glow Logic (Permanent while ready)
    -- Logic:
    -- 1. Trigger if _pendingGlow is set (armed by previous valid cooldown)
    -- 2. Sustain if already active (and duration not exceeded)

    local shouldGlow = false
    if isReady and showGlow then
        if icon._pendingGlow then
            -- Trigger!
            shouldGlow = true
            icon._pendingGlow = false       -- Consume the trigger
            icon._glowStartTime = GetTime() -- Reset timer for new glow
        elseif icon._glowActive then
            -- Sustain
            shouldGlow = true
        end
    end

    if shouldGlow then
        -- Check if glow has been active for too long
        local maxDuration = GetIconValue(entrySettings, panelConfig, "glow_max_duration", 5.0)
        local now = GetTime()

        if not icon._glowStartTime then
            icon._glowStartTime = now
        end

        local elapsed = now - icon._glowStartTime

        if elapsed < maxDuration then
            -- Resolve glow configuration (Shared central logic)
            sfui.glows.resolve_config(entrySettings, panelConfig, _tempGlowCfg)
            local glowType = _tempGlowCfg.glowType

            local needsRestart = false
            if not icon._glowActive then
                needsRestart = true
            elseif icon._lastGlowType ~= glowType then
                needsRestart = true
            else
                local prev = icon._lastGlowCfg
                if prev and prev.glowColor then
                    if math.abs(prev.glowColor[1] - _tempGlowCfg.glowColor[1]) > 0.01 or
                        math.abs(prev.glowColor[2] - _tempGlowCfg.glowColor[2]) > 0.01 or
                        math.abs(prev.glowColor[3] - _tempGlowCfg.glowColor[3]) > 0.01 or
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
end

-- Helper to update icon state (visibility, cooldown, charges)
local function UpdateIconState(icon, panelConfig)
    if not icon.id or not icon.entry then return false end
    local entrySettings = icon.entry.settings or _emptyTable

    -- 1. Determine the Correct Spell/Item ID and Texture
    local iconTexture, activeID = sfui.trackedicons.GetIconTexture(icon.id, icon.type, icon.entry)

    -- 2. FORCE TEXTURE REFRESH (Fixes "Reload Required" for reordering)
    if icon.texture and iconTexture then
        if icon._currentTexture ~= iconTexture then
            icon.texture:SetTexture(iconTexture)
            icon._currentTexture = iconTexture
        end
    end
    icon._lastActiveID = activeID

    -- 3. Update Cooldown & Logic
    local count, isReady, isUsable, notEnoughPower, isOnCooldown = UpdateIconCooldown(icon, activeID)

    -- 4. Visibility Decision
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

        -- 5. Update Visuals
        UpdateIconVisuals(icon, entrySettings, panelConfig, isUsable, isOnCooldown, notEnoughPower)

        -- 5b. Update Border Style
        sfui.trackedicons.ApplyIconBorderStyle(icon, panelConfig)

        -- 5c. Update Hotkey Text
        sfui.trackedicons.UpdateIconHotkey(icon, panelConfig)

        -- 6. Update Glows
        UpdateIconGlow(icon, entrySettings, panelConfig, isReady)
    else
        -- Icon is not visible - hide it
        icon:Hide()
        if icon._glowActive then
            StopGlow(icon)
        end
    end


    return isVisible
end

-- Shared Helper for Texture Resolution
function sfui.trackedicons.GetIconTexture(id, type, entry)
    local activeID = id
    local iconTexture

    if type == "cooldown" and entry and entry.cooldownID then
        -- Get cooldown info from Blizzard's CDM
        local cdInfo = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo(entry.cooldownID)
        if cdInfo then
            activeID = cdInfo.overrideSpellID or cdInfo.spellID
            iconTexture = C_Spell.GetSpellTexture(activeID)
        else
            -- Fallback if cooldown no longer exists
            activeID = entry.spellID or id
            iconTexture = C_Spell.GetSpellTexture(activeID)
        end
    elseif type == "item" then
        iconTexture = C_Item.GetItemIconByID(activeID)
    else
        -- Smart Detection: if it's a simple ID, check if it exists in CooldownViewer categories
        local cdInfo = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo(activeID)
        if cdInfo then
            activeID = cdInfo.overrideSpellID or cdInfo.spellID
            iconTexture = C_Spell.GetSpellTexture(activeID)
        else
            iconTexture = C_Spell.GetSpellTexture(activeID)
            if not iconTexture then
                iconTexture = C_Item.GetItemIconByID(activeID)
            end
        end
    end

    return iconTexture, activeID
end

-- Apply square icon + border style from config
function sfui.trackedicons.ApplyIconBorderStyle(icon, panelConfig)
    if not icon or not icon.texture then return end

    local showBorder = GetIconValue(nil, panelConfig, "showBorder", false)
    local squareIcons = GetIconValue(nil, panelConfig, "squareIcons", false)

    -- TexCoord: square crops the round WoW icon edges
    if squareIcons then
        icon.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    else
        icon.texture:SetTexCoord(0, 1, 0, 1)
    end

    -- Border backdrop (2px black behind icon)
    if icon.borderBackdrop then
        if showBorder then
            icon.borderBackdrop:Show()
            icon.texture:ClearAllPoints()
            icon.texture:SetPoint("TOPLEFT", icon, "TOPLEFT", 2, -2)
            icon.texture:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 2)
        else
            icon.borderBackdrop:Hide()
            icon.texture:ClearAllPoints()
            icon.texture:SetAllPoints()
        end
    end
end

-- Update hotkey text on an icon from the hotkey cache
function sfui.trackedicons.UpdateIconHotkey(icon, panelConfig)
    if not icon or not icon.hotkeyText then return end

    local showHotkeys = GetIconValue(nil, panelConfig, "showHotkeys", true)
    if not showHotkeys or not sfui.hotkeys then
        icon.hotkeyText:Hide()
        return
    end

    -- Update font/anchor in case config changed
    local hkSize = GetIconValue(nil, panelConfig, "hotkeyFontSize", 12)
    local hkOutline = GetIconValue(nil, panelConfig, "hotkeyOutline", "OUTLINE")
    local hkAnchor = GetIconValue(nil, panelConfig, "hotkeyAnchor", "TOPLEFT")
    icon.hotkeyText:SetFont("Fonts\\FRIZQT__.TTF", hkSize, hkOutline)
    icon.hotkeyText:ClearAllPoints()
    icon.hotkeyText:SetPoint(hkAnchor, icon, hkAnchor, 2, -2)

    -- Lookup hotkey
    local hotkey = nil
    local activeID = icon._lastActiveID or icon.id
    if icon.entry and icon.entry.type == "item" then
        hotkey = sfui.hotkeys.get_for_item(activeID)
    else
        hotkey = sfui.hotkeys.get_for_spell(activeID)
    end

    if hotkey then
        icon.hotkeyText:SetText(hotkey)
        icon.hotkeyText:Show()
    else
        icon.hotkeyText:Hide()
    end
end

-- Shared Helper for Masque Sync
local function SyncIconMasque(icon)
    sfui.common.sync_masque(icon, { Icon = icon.texture, Cooldown = icon.cooldown })
end

-- Create a single icon frame (Standard Button for Taint Isolation)
local function CreateIconFrame(parent, id, entry, panelConfig)
    -- Normalize numeric entry (from new CDM) to table
    if type(entry) == "number" then
        entry = { id = entry, type = "spell" }
    end

    _iconCounter = _iconCounter + 1
    local name = "SfuiIcon" .. _iconCounter
    local f = CreateFrame("Button", name, parent)
    local initialSize = 40
    if panelConfig then
        initialSize = tonumber(panelConfig.size) or 40
    end
    f:SetSize(initialSize, initialSize)

    -- Border backdrop (black 2px behind icon, controlled by showBorder config)
    f.borderBackdrop = f:CreateTexture(nil, "BACKGROUND")
    f.borderBackdrop:SetAllPoints()
    f.borderBackdrop:SetColorTexture(0, 0, 0, 1)
    f.borderBackdrop:Hide() -- Hidden by default, shown via ApplyIconBorderStyle

    -- Icon Texture
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    f.texture = tex

    local iconTexture = sfui.trackedicons.GetIconTexture(id, entry.type, entry)
    tex:SetTexture(iconTexture or 134400)

    -- Apply initial border/square style
    sfui.trackedicons.ApplyIconBorderStyle(f, panelConfig)

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

    -- Hotkey text (keybinding display)
    f.hotkeyText = f:CreateFontString(nil, "OVERLAY")
    local hkSize = GetIconValue(nil, panelConfig, "hotkeyFontSize", 12)
    local hkOutline = GetIconValue(nil, panelConfig, "hotkeyOutline", "OUTLINE")
    local hkAnchor = GetIconValue(nil, panelConfig, "hotkeyAnchor", "TOPLEFT")
    f.hotkeyText:SetFont("Fonts\\FRIZQT__.TTF", hkSize, hkOutline)
    f.hotkeyText:SetPoint(hkAnchor, f, hkAnchor, 2, -2)
    f.hotkeyText:SetTextColor(1, 1, 1, 1)
    f.hotkeyText:Hide()

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
    f:SetScript("OnUpdate", nil)

    local msq = sfui.common.get_masque_group()
    if msq then
        msq:AddButton(f, { Icon = tex, Cooldown = cd })
        f._isMasqued = true
    end

    return f
end

-- Visibility Event Handler (Named function for better closure performance)
function sfui.trackedicons.OnVisibilityEvent(self, event)
    local panelFrame = self:GetParent()
    if not panelFrame then return end

    if not SfuiDB or not SfuiDB.iconGlobalSettings then return end

    local shouldShow = true
    local globalVis = SfuiDB.iconGlobalSettings

    -- Robust Combat Detection
    local inCombat = InCombatLockdown()
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    end

    -- Per-panel visibility mode (from panel config, falls back to global, then "always")
    local panelConfig = panelFrame.config
    local visMode = "always"
    if panelConfig and panelConfig.visibility then
        visMode = panelConfig.visibility
    elseif globalVis.visibility then
        visMode = globalVis.visibility
    end

    -- Apply visibility mode
    if visMode == "combat" then
        if not inCombat then shouldShow = false end
    elseif visMode == "noCombat" then
        if inCombat then shouldShow = false end
    else -- "always"
        -- Legacy hideOOC support for "always" mode
        if globalVis.hideOOC and not inCombat then
            shouldShow = false
        end
    end

    -- Check Dragonriding (applies to all modes)
    if shouldShow and globalVis.hideDragonriding then
        if sfui.common.IsDragonriding() and not inCombat then
            shouldShow = false
        end
    end

    -- OVERRIDE: Always show if Options Panel is open
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
end

-- Helper: Apply Auto-Span Logic to fit width
local function ApplyAutoSpan(panelConfig, activeIcons, size, spacing, numColumns, growthH, targetFrame)
    local spanWidth = GetIconValue(nil, panelConfig, "spanWidth", false)
    if spanWidth and #activeIcons > 0 then
        local targetWidth = 300
        if targetFrame and targetFrame.GetWidth then
            targetWidth = targetFrame:GetWidth()
        elseif _G["sfui_bar0_Backdrop"] then
            targetWidth = _G["sfui_bar0_Backdrop"]:GetWidth()
        end

        local iconsPerRow = math.min(numColumns, #activeIcons)
        if iconsPerRow <= 0 then return size, spacing end

        -- Calculate current width with configured size/spacing
        local currentWidth = (iconsPerRow * size) + (math.max(0, iconsPerRow - 1) * spacing)

        if currentWidth < targetWidth then
            -- Expand spacing to fill width
            if iconsPerRow > 1 then
                spacing = (targetWidth - (iconsPerRow * size)) / (iconsPerRow - 1)
            end
        else
            -- Shrink size to fit width (keeping spacing fixed)
            local newSize = (targetWidth - (math.max(0, iconsPerRow - 1) * spacing)) / iconsPerRow
            if newSize < 10 then newSize = 10 end -- Hard min size
            size = newSize
        end
    end
    return size, spacing
end

function sfui.trackedicons.UpdatePanelLayout(panelFrame, panelConfig)
    if not panelFrame or not panelConfig then return end
    panelFrame.config = panelConfig


    -- Register Event-Driven Visibility Handler for this panel
    if not panelFrame.visHandler then
        panelFrame.visHandler = CreateFrame("Frame", nil, panelFrame)
        panelFrame.visHandler:RegisterEvent("PLAYER_REGEN_DISABLED")
        panelFrame.visHandler:RegisterEvent("PLAYER_REGEN_ENABLED")
        panelFrame.visHandler:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
        panelFrame.visHandler:RegisterEvent("UNIT_POWER_BAR_SHOW")
        panelFrame.visHandler:RegisterEvent("UNIT_POWER_BAR_HIDE")

        panelFrame.visHandler:SetScript("OnEvent", sfui.trackedicons.OnVisibilityEvent)
    end



    -- Trigger initial visibility check IMMEDIATELY
    if panelFrame.visHandler then
        pcall(panelFrame.visHandler:GetScript("OnEvent"), panelFrame.visHandler)
    end



    -- Ensure panel position is updated from Config with Dynamic Anchoring
    panelFrame:ClearAllPoints()

    local anchorTo = panelConfig.anchorTo or "UIParent"
    local targetFrame = UIParent
    local targetPoint = "BOTTOM"
    local anchorPoint = panelConfig.anchorPoint or "BOTTOM"

    if anchorTo == "Health Bar" and _G["sfui_bar0_Backdrop"] then
        targetFrame = _G["sfui_bar0_Backdrop"]
        targetPoint = "BOTTOM"
        anchorPoint = "TOP"

        -- Smart Anchoring: Check if Power Bar (bar_minus_1) is visible and below health
        local powerBar = _G["sfui_bar_minus_1_Backdrop"]
        if powerBar and powerBar:IsShown() then
            targetFrame = powerBar
            targetPoint = "BOTTOM"
        end
    elseif anchorTo == "Tracked Bars" and _G["SfuiTrackedBarsContainer"] then
        targetFrame = _G["SfuiTrackedBarsContainer"]
        targetPoint = "TOP"
        anchorPoint = "BOTTOM"
    elseif anchorTo ~= "UIParent" then
        -- Check if anchoring to another panel by name
        for _, otherPanel in pairs(panels) do
            if otherPanel.config and otherPanel.config.name == anchorTo then
                -- SAFETY: Ensure we are not anchoring to ourselves
                if otherPanel ~= panelFrame then
                    targetFrame = otherPanel
                    targetPoint = "BOTTOM"
                    anchorPoint = "TOP"
                else
                    -- Fallback to UIParent if self-anchoring detected
                    targetFrame = UIParent
                    targetPoint = "BOTTOM"
                    anchorPoint = "BOTTOM"
                end
                break
            end
        end
    end

    -- Default local anchor for icon placement relative to panel
    local anchor = anchorPoint
    panelFrame:SetPoint(anchorPoint, targetFrame, targetPoint, panelConfig.x or 0, panelConfig.y or 0)

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
        -- Handle both new simple numeric IDs and legacy table entries
        local id = (type(entry) == "table" and entry.id) or entry
        if id then
            if not panelFrame.icons[i] then
                panelFrame.icons[i] = CreateIconFrame(panelFrame, id, entry, panelConfig)
            end

            local icon = panelFrame.icons[i]
            if icon then
                -- Update attributes (safe out of combat)
                icon.id = id
                if type(entry) == "table" then
                    icon.type = entry.type
                    icon.entry = entry
                else
                    icon.type = "spell" -- Default for simple IDs
                    icon.entry = { id = id, type = "spell" }
                end

                -- Sync Masque state immediately
                SyncIconMasque(icon)

                -- Always add icons to layout; errors in state update should not hide them
                local ok, isVisibleValue = pcall(UpdateIconState, icon, panelConfig)
                if not ok then
                    -- UpdateIconState errored — show icon anyway to prevent disappearing
                    icon:Show()
                    print("|cff6600ffsfui|r: UpdateIconState error:", isVisibleValue)
                end

                table.insert(activeIcons, icon)
            end
        end
    end

    -- Layout Active Icons
    local numColumns = panelConfig.columns or #activeIcons
    if numColumns < 1 then numColumns = 1 end

    -- Force Single Row ONLY for the main CENTER panel
    if panelConfig.name == "CENTER" then
        numColumns = #activeIcons
    end

    local growthH = panelConfig.growthH or "Right"
    local growthV = panelConfig.growthV or "Down"
    local hSign = (growthH == "Left") and -1 or 1
    local vSign = (growthV == "Up") and 1 or -1

    -- Ensure spacing is a number and size is a number
    local size = GetIconValue(nil, panelConfig, "size", 40)
    local spacing = GetIconValue(nil, panelConfig, "spacing", 2)
    size = tonumber(size) or 40
    spacing = tonumber(spacing) or 2

    local maxWidth, maxHeight = 0, 0

    -- Auto-Span Width Logic
    size, spacing = ApplyAutoSpan(panelConfig, activeIcons, size, spacing, numColumns, growthH, targetFrame)

    -- Layout icons based on growth mode
    -- Non-protected frames can be positioned freely even during combat
    if growthH == "Center" then
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

            local centerOffset = colInRow - (numInRow - 1) / 2
            local ox = centerOffset * (size + spacing)
            local oy = row * (size + spacing) * vSign

            -- Centered icons always use the panel's main anchor point as their 0,0 reference
            icon:SetPoint(anchor, panelFrame, anchor, ox, oy)

            local rowWidth = numInRow * size + math.max(0, numInRow - 1) * spacing
            maxWidth = math.max(maxWidth, rowWidth)
            maxHeight = math.max(maxHeight, (row + 1) * (size + spacing) - spacing)
        end
    else
        -- Standard growth
        for idx, icon in ipairs(activeIcons) do
            icon:ClearAllPoints()
            icon:SetSize(size, size)

            local col = (idx - 1) % numColumns
            local row = math.floor((idx - 1) / numColumns)

            local ox = col * (size + spacing) * hSign
            local oy = row * (size + spacing) * vSign

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

-- Helper to remove legacy defaults from panels so they use global settings
local function SanitizePanelConfig(panelConfig)
    if not panelConfig then return end

    -- Keys to purge from panel config (ensures fallback to Global settings)
    local keysToPurge = {
        "readyGlow", "useSpecColor", "glowType", "glowColor",
        "glowScale", "glowSpeed", "glowIntensity", "glow_max_duration",
        "glowLines", "glowParticles", "glowThickness",
        "cooldownDesat", "useResourceCheck", "showBackground",
        "textEnabled", "alphaOnCooldown", "backgroundAlpha",
        "textColor", "squareIcons", "showBorder"
    }

    -- Global Protection: Ensure Global Settings aren't corrupted
    local igs = SfuiDB and SfuiDB.iconGlobalSettings
    if igs and igs.alphaOnCooldown == 0 then
        igs.alphaOnCooldown = 1.0
    end

    for _, key in ipairs(keysToPurge) do
        panelConfig[key] = nil
    end

    -- ALSO purge per-entry settings (legacy icon-specific overrides)
    if panelConfig.entries then
        for _, entry in ipairs(panelConfig.entries) do
            if type(entry) == "table" and entry.settings then
                for _, key in ipairs(keysToPurge) do
                    entry.settings[key] = nil
                end
            end
        end
    end
end

function sfui.trackedicons.Update()
    local panelConfigs = sfui.common.get_cooldown_panels()
    if not panelConfigs or #panelConfigs == 0 then return end


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

    -- Dirty-flag system: events set this flag, OnUpdate only processes when dirty
    local _needsStateUpdate = true -- Start dirty for initial render
    local _burstTimer = 0          -- Brief burst period after events for smooth transitions

    -- Helper: Mark icons as needing a state refresh
    local function MarkDirty(burstDuration)
        _needsStateUpdate = true
        _burstTimer = math.max(_burstTimer, burstDuration or 0.5)
    end

    -- Helper: Update only icon states (no layout rebuild) using cached panel.config
    local function UpdateAllIconStates()
        for _, panel in pairs(panels) do
            local config = panel.config
            if panel.icons and config then
                for _, icon in pairs(panel.icons) do
                    UpdateIconState(icon, config)
                end
            end
        end
    end

    -- Helper: Update only cooldown-type icon states
    local function UpdateCooldownIconStates()
        for _, panel in pairs(panels) do
            local config = panel.config
            if panel.icons and config then
                for _, icon in pairs(panel.icons) do
                    if icon.entry and icon.entry.type == "cooldown" then
                        UpdateIconState(icon, config)
                    end
                end
            end
        end
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
            MarkDirty(1.0) -- Longer burst for combat transitions
        elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SPECIALIZATION_CHANGED" then
            sfui.common.ensure_panels_initialized()
            if sfui.common.SyncTrackedSpells then
                sfui.common.SyncTrackedSpells()
            end
            sfui.trackedicons.Update()
            MarkDirty(2.0) -- Longer burst for world entry
        elseif event == "UNIT_AURA" and unitTarget == "player" then
            if updateInfo and not InCombatLockdown() then
                local needsFullUpdate = false

                if updateInfo.addedAuras and #updateInfo.addedAuras > 0 then
                    needsFullUpdate = true
                end

                if updateInfo.updatedAuraInstanceIDs and not needsFullUpdate then
                    for _, instanceID in ipairs(updateInfo.updatedAuraInstanceIDs) do
                        pcall(function()
                            for _, panel in pairs(panels) do
                                local config = panel.config
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

                if updateInfo.removedAuraInstanceIDs and #updateInfo.removedAuraInstanceIDs > 0 then
                    needsFullUpdate = true
                end

                if needsFullUpdate then
                    sfui.trackedicons.Update()
                end
            else
                if InCombatLockdown() then
                    UpdateAllIconStates()
                else
                    sfui.trackedicons.Update()
                end
            end
            MarkDirty(0.5)
        elseif event == "TRAIT_CONFIG_UPDATED" then
            if not InCombatLockdown() then
                UpdateCooldownIconStates()
            end
            MarkDirty(0.5)
        else
            -- SPELL_UPDATE_COOLDOWN, BAG_UPDATE_COOLDOWN
            if InCombatLockdown() then
                UpdateAllIconStates()
            else
                sfui.trackedicons.Update()
            end
            MarkDirty(0.5)
        end
    end)

    -- OnUpdate: Only process when dirty or during burst period (for smooth glow/alpha transitions)
    local lastUpdate = 0
    eventFrame:SetScript("OnUpdate", function(self, elapsed)
        lastUpdate = lastUpdate + elapsed
        if lastUpdate > 0.1 then
            lastUpdate = 0

            -- Decrement burst timer
            if _burstTimer > 0 then
                _burstTimer = _burstTimer - 0.1
            end

            -- Only update if dirty flag set or burst timer active or any glows are running
            if _needsStateUpdate or _burstTimer > 0 then
                _needsStateUpdate = false
                UpdateAllIconStates()
            else
                -- Even when idle, check icons with active glows for timeout
                for _, panel in pairs(panels) do
                    if panel.icons then
                        for _, icon in pairs(panel.icons) do
                            if icon._glowActive then
                                local config = panel.config
                                if config then
                                    UpdateIconGlow(icon, icon.entry and icon.entry.settings or _emptyTable, config, true)
                                end
                            end
                        end
                    end
                end
            end
        end
    end)

    -- Initial setup
    sfui.common.ensure_panels_initialized()

    -- Sanitize all panels once (skip if already done)
    if not SfuiDB._panelsSanitizedV2 then
        local panelConfigs = sfui.common.get_cooldown_panels()
        if panelConfigs then
            for _, panelConfig in ipairs(panelConfigs) do
                SanitizePanelConfig(panelConfig)
            end
        end
        SfuiDB._panelsSanitizedV2 = true
    end

    sfui.trackedicons.Update()
end
