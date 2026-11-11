local addonName, addon = ...
sfui = sfui or {}
sfui.trackedicons = sfui.trackedicons or {}
sfui.trackedicons._cooldown = sfui.trackedicons._cooldown or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/tracking/icon_cooldown.lua
--  pure cooldown, charge/count badge, usability tint, and glow pipeline for
--  tracked icons. consumes precompiled `icon._desc` from entry.lua.
-- ══════════════════════════════════════════════════════════════════════════════

local IC = sfui.trackedicons._cooldown

local C_Spell = C_Spell
local C_DurationUtil = _G.C_DurationUtil
local GetTime = GetTime
local GetInventoryItemCooldown = GetInventoryItemCooldown
local GetInventoryItemID = GetInventoryItemID
local HasFullControl = HasFullControl
local NumberFontNormal = NumberFontNormal
local select = select
local type = type
local wipe = wipe or table.wipe
local issecretvalue = sfui.common.issecretvalue

local _tempGlowCfg = {}
local _defaultTextColor = { 1, 1, 1, 1 }
local _spellMaxCharges = {}

function IC.InvalidateChargeCache()
    wipe(_spellMaxCharges)
end

local function RestoreNormalCooldownSwipe(icon)
    if icon._chargeSwipeHidden then
        icon._chargeSwipeHidden = nil
        icon.cooldown:SetDrawSwipe(true)
    end
end

-- forwards category cooldown source straight into spell cooldown sinks without inspecting secret values
local function forward_category_cooldown(icon, auraActive, ...)
    if select("#", ...) == 0 then return false, true end
    local scd = C_Spell.GetSpellCooldown((...))
    if not scd then return false, true end
    local enabled = scd.isEnabled ~= false
    if not scd.isActive or scd.isOnGCD then return false, enabled end
    if auraActive then
        return true, enabled
    end
    local durationObj = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration((...), true)
    if durationObj and icon.cooldown.SetCooldownFromDurationObject then
        RestoreNormalCooldownSwipe(icon)
        icon.cooldown:SetCooldownFromDurationObject(durationObj)
        return true, enabled
    end
    return false, enabled
end

local function apply_plain_item_cooldown(icon, s, d, auraActive)
    if not (s and d and s > 0 and d > 0 and (s + d) > GetTime()) then
        return false
    end
    if auraActive then
        return true
    end
    RestoreNormalCooldownSwipe(icon)
    if icon.cooldown.SetCooldownFromDurationObject and C_DurationUtil and C_DurationUtil.CreateDuration then
        local dObj = icon._durationObj or C_DurationUtil.CreateDuration()
        icon._durationObj = dObj
        dObj:SetTimeFromStart(s, d, 1)
        icon.cooldown:SetCooldownFromDurationObject(dObj)
    else
        icon.cooldown:SetCooldown(s, d)
    end
    return true
end

local function update_item_cd(icon, desc, auraActive)
    local equipSlot = desc.equipSlot
    local spellCategoryID = desc.spellCategoryID
    local itemID = desc.itemID

    local count = 0
    local onCooldown, enabled = false, true

    if equipSlot then
        count = "" -- equipped items do not show stack badges
        local s, d, e = GetInventoryItemCooldown("player", equipSlot)
        enabled = (e ~= 0 and e ~= false)
        onCooldown = apply_plain_item_cooldown(icon, s, d, auraActive)
    elseif spellCategoryID then
        local catData = sfui.tracking and sfui.tracking.SPELL_CATEGORY_METADATA and sfui.tracking.SPELL_CATEGORY_METADATA[spellCategoryID]
        if C_Spell and C_Spell.GetLastCategoryCooldownSource then
            onCooldown, enabled = forward_category_cooldown(icon, auraActive, C_Spell.GetLastCategoryCooldownSource(spellCategoryID))
        end
        local plainItemID = itemID or (catData and catData.fallbackItemID)
        if plainItemID and sfui.api then
            if not onCooldown and sfui.api.GetItemCooldown then
                local s, d = sfui.api.GetItemCooldown(plainItemID)
                onCooldown = apply_plain_item_cooldown(icon, s, d, auraActive)
            end
            if sfui.api.GetItemCount then
                count = sfui.api.GetItemCount(plainItemID) or 0
            end
        end
    else
        local targetID = itemID or desc.id
        if targetID and sfui.api and sfui.api.GetItemCooldown then
            local s, d, e = sfui.api.GetItemCooldown(targetID)
            enabled = (e ~= 0 and e ~= false)
            onCooldown = apply_plain_item_cooldown(icon, s, d, auraActive)
            count = (sfui.api.GetItemCount and sfui.api.GetItemCount(targetID)) or 0
        end
    end

    if not onCooldown and not auraActive then
        RestoreNormalCooldownSwipe(icon)
        icon.cooldown:Clear()
    end

    icon._itemOnCooldown = onCooldown
    icon._isEnabled = enabled
    return count
end

local function CreateCountText(icon)
    if icon.count then return end
    local count = icon:CreateFontString(nil, "OVERLAY")
    if NumberFontNormal then
        count:SetFontObject(NumberFontNormal)
    else
        count:SetFont("Fonts\\ARIALN.TTF", 12, "OUTLINE")
    end
    count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -3, 1)
    count:SetJustifyH("RIGHT")
    icon.count = count
end

function IC.UpdateCountText(icon, displayStr)
    if not icon.count then CreateCountText(icon) end

    if issecretvalue(displayStr) then
        icon._lastCount = nil
        icon.count:SetText(displayStr)
        icon.count:Show()
    else
        local str = (displayStr ~= nil and displayStr ~= 0) and sfui.common.get_cached_int_string(displayStr) or ""
        if str ~= "" and str ~= "0" then
            if icon._lastCount ~= str then
                icon._lastCount = str
                icon.count:SetText(str)
            end
            icon.count:Show()
        else
            if icon._lastCount ~= nil then icon._lastCount = nil end
            icon.count:Hide()
        end
    end
end

local function IsFallbackNeeded(val)
    if issecretvalue(val) then return false end
    return val == ""
end

local function ResolveSpellChargeState(activeID)
    if not C_Spell or not C_Spell.GetSpellCharges then
        return 0, nil
    end
    local maxCh = _spellMaxCharges[activeID]
    if maxCh == nil then
        local ch = C_Spell.GetSpellCharges(activeID)
        local rawMax = ch and ch.maxCharges
        if rawMax ~= nil and not issecretvalue(rawMax) and type(rawMax) == "number" then
            maxCh = rawMax
            _spellMaxCharges[activeID] = maxCh
        else
            maxCh = 0
        end
        return maxCh, ch
    elseif maxCh > 1 then
        return maxCh, C_Spell.GetSpellCharges(activeID)
    end
    return maxCh, nil
end

-- evaluates item/spell cooldown, charges/counts, usability, and readiness.
-- when `auraActive` is true, preserves the aura swipe already set on `icon.cooldown`.
function IC.Evaluate(icon, desc, auraActive)
    local activeID = desc.activeID
    local isItem = desc.isItem
    local count
    local isEnabled = true
    local isUsable, notEnoughPower = true, false
    local isOnCooldown = false

    if isItem then
        local countVal = update_item_cd(icon, desc, auraActive)
        count = countVal or 0
        isEnabled = icon._isEnabled
        isOnCooldown = (icon._itemOnCooldown == true)
        if desc.equipSlot then
            local invID = GetInventoryItemID and GetInventoryItemID("player", desc.equipSlot)
            isUsable = (invID ~= nil)
        elseif desc.spellCategoryID then
            local catData = sfui.tracking and sfui.tracking.SPELL_CATEGORY_METADATA and sfui.tracking.SPELL_CATEGORY_METADATA[desc.spellCategoryID]
            if catData and not catData.fallbackItemID and count == 0 and not isOnCooldown then
                isUsable = true
            else
                isUsable = (count ~= "" and count ~= 0) or isOnCooldown
            end
        else
            isUsable = (count ~= "" and count ~= 0) or (isEnabled ~= false)
        end
    else
        local maxCh, chargeInfo = ResolveSpellChargeState(activeID)
        local cdInfo = C_Spell.GetSpellCooldown(activeID)
        if cdInfo ~= nil then
            local isActive = cdInfo.isActive
            local isOnGCD = cdInfo.isOnGCD

            if isActive and not isOnGCD then
                isOnCooldown = true
                icon._secretGCDDropTime = nil
                if not auraActive then
                    RestoreNormalCooldownSwipe(icon)
                    if icon.cooldown.SetCooldownFromDurationObject and C_Spell.GetSpellCooldownDuration then
                        local durationObj = C_Spell.GetSpellCooldownDuration(activeID, true)
                        if durationObj then
                            icon.cooldown:SetCooldownFromDurationObject(durationObj)
                        else
                            icon.cooldown:Clear()
                        end
                    elseif not (issecretvalue and (issecretvalue(cdInfo.startTime) or issecretvalue(cdInfo.duration))) then
                        icon.cooldown:SetCooldown(cdInfo.startTime, cdInfo.duration)
                    else
                        icon.cooldown:Clear()
                    end
                end
            else
                isOnCooldown = false
                icon._secretGCDDropTime = nil
                if not auraActive then
                    -- Partial charge recharge: show edge progress + countdown while >= 1 charge remains
                    if maxCh > 1 and chargeInfo and chargeInfo.isActive then
                        if not icon._chargeSwipeHidden then
                            icon._chargeSwipeHidden = true
                            icon.cooldown:SetDrawSwipe(false)
                            icon.cooldown:SetDrawEdge(true)
                        end
                        if icon.cooldown.SetCooldownFromDurationObject and C_Spell.GetSpellChargeDuration then
                            local chargeDur = C_Spell.GetSpellChargeDuration(activeID)
                            if chargeDur then
                                icon.cooldown:SetCooldownFromDurationObject(chargeDur)
                            else
                                RestoreNormalCooldownSwipe(icon)
                                icon.cooldown:Clear()
                            end
                        elseif not (issecretvalue(chargeInfo.cooldownStartTime) or issecretvalue(chargeInfo.cooldownDuration)) then
                            icon.cooldown:SetCooldown(chargeInfo.cooldownStartTime, chargeInfo.cooldownDuration)
                        else
                            RestoreNormalCooldownSwipe(icon)
                            icon.cooldown:Clear()
                        end
                    else
                        RestoreNormalCooldownSwipe(icon)
                        icon.cooldown:Clear()
                    end
                end
            end

            isEnabled = (cdInfo.isEnabled ~= false)
        elseif not auraActive then
            RestoreNormalCooldownSwipe(icon)
            icon.cooldown:Clear()
        end

        local displayStr = ""
        local hasNativeDisplayCount = (C_Spell.GetSpellDisplayCount ~= nil)
        if hasNativeDisplayCount then
            local dc = C_Spell.GetSpellDisplayCount(activeID)
            if dc ~= nil then
                displayStr = dc
            end
        end

        -- Only run Lua fallbacks when GetSpellDisplayCount is absent (Classic Era) or plain empty
        if not hasNativeDisplayCount and IsFallbackNeeded(displayStr) then
            if maxCh > 1 and chargeInfo then
                local curCh = chargeInfo.currentCharges
                if curCh ~= nil and not issecretvalue(curCh) then
                    displayStr = curCh
                end
            end
            if IsFallbackNeeded(displayStr) and C_Spell.GetSpellCastCount then
                local cc = C_Spell.GetSpellCastCount(activeID)
                if cc ~= nil and not issecretvalue(cc) and type(cc) == "number" and cc > 0 then
                    displayStr = cc
                end
            end
        end

        count = displayStr
    end

    if icon._wasOnCooldown and not isOnCooldown then
        icon._pendingGlow = true
    end
    icon._wasOnCooldown = isOnCooldown

    if not isItem then
        if C_Spell and C_Spell.IsSpellUsable then
            local u, p = C_Spell.IsSpellUsable(activeID)
            if issecretvalue(u) then
                isUsable = true
            else
                isUsable = (u ~= false)
            end
            if issecretvalue(p) then
                notEnoughPower = false
            else
                notEnoughPower = (p == true)
            end
        end
        if not HasFullControl() and not isUsable then
            isUsable = true
        end
    end

    local isReady
    if isItem then
        isReady = not isOnCooldown and (isEnabled ~= false)
    else
        isReady = not isOnCooldown and (isEnabled ~= false) and isUsable
    end

    return count, isReady, isUsable, notEnoughPower, isOnCooldown
end

function IC.UpdateVisuals(icon, entrySettings, panelConfig, getIconValueFn, isUsable, isOnCooldown, notEnoughPower)
    if not icon.texture then return end

    local actuallyUnusable = (not isUsable) and not notEnoughPower
    local useDesat = getIconValueFn(entrySettings, panelConfig, "cooldownDesat", true)
    local desaturate = (useDesat and isOnCooldown) or actuallyUnusable
    if icon._currentDesaturated ~= desaturate then
        icon.texture:SetDesaturated(desaturate)
        icon._currentDesaturated = desaturate
    end

    local baseAlpha = actuallyUnusable and 0.5 or 1.0
    local alpha = isOnCooldown and getIconValueFn(entrySettings, panelConfig, "alphaOnCooldown", 0.5) or baseAlpha
    if icon._currentAlpha ~= alpha then
        icon:SetAlpha(alpha)
        icon._currentAlpha = alpha
    end

    local useResourceCheck = getIconValueFn(entrySettings, panelConfig, "useResourceCheck", true)
    local targetColor = (notEnoughPower and useResourceCheck) and "blue" or "white"
    if icon._currentVertexColor ~= targetColor then
        if targetColor == "blue" then
            icon.texture:SetVertexColor(0.5, 0.5, 1.0)
        else
            local textColor = getIconValueFn(entrySettings, panelConfig, "textColor", _defaultTextColor)
            if type(textColor) == "table" then
                icon.texture:SetVertexColor(textColor[1] or 1, textColor[2] or 1, textColor[3] or 1)
            else
                icon.texture:SetVertexColor(1, 1, 1)
            end
        end
        icon._currentVertexColor = targetColor
    end
end

local function IsGlowCfgChanged(prev, nextCfg)
    if not prev then return true end
    if prev.glowType ~= nextCfg.glowType then return true end
    local nr, ng, nb = sfui.common.unpack_color(nextCfg.glowColor)
    if math.abs((prev.r or 1) - nr) > 0.01
        or math.abs((prev.g or 1) - ng) > 0.01
        or math.abs((prev.b or 1) - nb) > 0.01
        or math.abs((prev.glowScale or 1) - (nextCfg.glowScale or 1)) > 0.01
        or math.abs((prev.glowIntensity or 1) - (nextCfg.glowIntensity or 1)) > 0.01
        or math.abs((prev.glowSpeed or 0.25) - (nextCfg.glowSpeed or 0.25)) > 0.01
        or math.abs((prev.glowLines or 8) - (nextCfg.glowLines or 8)) > 0.01
        or math.abs((prev.glowThickness or 2) - (nextCfg.glowThickness or 2)) > 0.01
        or math.abs((prev.glowParticles or 4) - (nextCfg.glowParticles or 4)) > 0.01 then
        return true
    end
    return false
end

function IC.UpdateGlow(icon, entrySettings, panelConfig, getIconValueFn, isReady, missingAlert, startGlowFn, stopGlowFn)
    local entryMod = sfui.tracking and sfui.tracking.entry
    local cfgRev = (entryMod and entryMod.GetConfigRevision and entryMod.GetConfigRevision()) or 0

    if missingAlert then
        if not icon._glowActive or icon._glowConfigRev ~= cfgRev then
            sfui.glows.resolve_config(entrySettings, panelConfig, _tempGlowCfg)
            if not icon._glowActive or IsGlowCfgChanged(icon._lastGlowCfg, _tempGlowCfg) then
                if icon._glowActive then stopGlowFn(icon) end
                startGlowFn(icon, _tempGlowCfg)
            end
            icon._glowConfigRev = cfgRev
        end
        icon._missingGlow = true
        return
    elseif icon._missingGlow then
        icon._missingGlow = false
        icon._pendingGlow = false
        icon._glowStartTime = nil
        icon._glowConfigRev = nil
        if icon._glowActive then stopGlowFn(icon) end
    end

    local showGlow = getIconValueFn(entrySettings, panelConfig, "readyGlow", true)
    local shouldGlow = false
    if isReady and showGlow then
        if icon._pendingGlow then
            shouldGlow = true
            icon._pendingGlow = false
            icon._glowStartTime = GetTime()
        elseif icon._glowActive then
            shouldGlow = true
        end
    end

    if shouldGlow then
        local maxDuration = getIconValueFn(entrySettings, panelConfig, "glow_max_duration", 5.0)
        local now = GetTime()
        if not icon._glowStartTime then
            icon._glowStartTime = now
        end

        if (now - icon._glowStartTime) < maxDuration then
            if not icon._glowActive or icon._glowConfigRev ~= cfgRev then
                sfui.glows.resolve_config(entrySettings, panelConfig, _tempGlowCfg)
                if not icon._glowActive or IsGlowCfgChanged(icon._lastGlowCfg, _tempGlowCfg) then
                    if icon._glowActive then stopGlowFn(icon) end
                    startGlowFn(icon, _tempGlowCfg)
                end
                icon._glowConfigRev = cfgRev
            end
        elseif icon._glowActive then
            icon._glowConfigRev = nil
            stopGlowFn(icon)
        end
    else
        icon._glowStartTime = nil
        icon._glowConfigRev = nil
        if icon._glowActive then
            stopGlowFn(icon)
        end
    end
end
