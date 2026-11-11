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
        icon.cooldown:SetCooldownFromDurationObject(durationObj)
        if icon.shadowCooldown and icon.shadowCooldown.SetCooldownFromDurationObject then
            icon.shadowCooldown:SetCooldownFromDurationObject(durationObj)
        end
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
    if icon.cooldown.SetCooldownFromDurationObject and C_DurationUtil and C_DurationUtil.CreateDuration then
        local dObj = icon._durationObj or C_DurationUtil.CreateDuration()
        icon._durationObj = dObj
        dObj:SetTimeFromStart(s, d, 1)
        icon.cooldown:SetCooldownFromDurationObject(dObj)
        if icon.shadowCooldown and icon.shadowCooldown.SetCooldownFromDurationObject then
            icon.shadowCooldown:SetCooldownFromDurationObject(dObj)
        end
    else
        icon.cooldown:SetCooldown(s, d)
        if icon.shadowCooldown then icon.shadowCooldown:SetCooldown(s, d) end
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
        icon.cooldown:Clear()
        if icon.shadowCooldown then icon.shadowCooldown:Clear() end
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
        count:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    end
    count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -3, 1)
    count:SetJustifyH("RIGHT")
    icon.count = count
end

function IC.UpdateCountText(icon, displayStr)
    if not icon.count then CreateCountText(icon) end

    if issecretvalue(displayStr) then
        sfui.common.SafeSetText(icon.count, displayStr, 0)
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
        local cdInfo = C_Spell.GetSpellCooldown(activeID)
        if cdInfo ~= nil then
            local isActive = cdInfo.isActive
            local isOnGCD = cdInfo.isOnGCD

            if isActive and not isOnGCD then
                isOnCooldown = true
                icon._secretGCDDropTime = nil
                if not auraActive then
                    if icon.cooldown.SetCooldownFromDurationObject and C_Spell.GetSpellCooldownDuration then
                        local durationObj = C_Spell.GetSpellCooldownDuration(activeID, true)
                        if durationObj then
                            icon.cooldown:SetCooldownFromDurationObject(durationObj)
                            if icon.shadowCooldown then
                                icon.shadowCooldown:SetCooldownFromDurationObject(durationObj)
                            end
                        else
                            icon.cooldown:Clear()
                            if icon.shadowCooldown then icon.shadowCooldown:Clear() end
                        end
                    elseif not (issecretvalue and (issecretvalue(cdInfo.startTime) or issecretvalue(cdInfo.duration))) then
                        icon.cooldown:SetCooldown(cdInfo.startTime, cdInfo.duration)
                        if icon.shadowCooldown then
                            icon.shadowCooldown:SetCooldown(cdInfo.startTime, cdInfo.duration)
                        end
                    else
                        icon.cooldown:Clear()
                        if icon.shadowCooldown then icon.shadowCooldown:Clear() end
                    end
                end
            else
                isOnCooldown = false
                icon._secretGCDDropTime = nil
                if not auraActive then
                    icon.cooldown:Clear()
                    if icon.shadowCooldown then icon.shadowCooldown:Clear() end
                end
            end

            isEnabled = (cdInfo.isEnabled ~= false)
        elseif not auraActive then
            icon.cooldown:Clear()
            if icon.shadowCooldown then icon.shadowCooldown:Clear() end
        end

        local displayStr = ""
        if C_Spell.GetSpellDisplayCount then
            local dc = C_Spell.GetSpellDisplayCount(activeID)
            if dc ~= nil then
                displayStr = dc
            end
        end

        if IsFallbackNeeded(displayStr) and C_Spell.GetSpellCharges then
            local maxCh = _spellMaxCharges[activeID]
            if maxCh == nil then
                local ch = C_Spell.GetSpellCharges(activeID)
                maxCh = (ch and ch.maxCharges) or 0
                _spellMaxCharges[activeID] = maxCh
                if maxCh > 1 and ch.currentCharges then
                    displayStr = ch.currentCharges or ""
                end
            elseif maxCh > 1 then
                local ch = C_Spell.GetSpellCharges(activeID)
                if ch and ch.currentCharges then
                    displayStr = ch.currentCharges or ""
                end
            end
        end

        if IsFallbackNeeded(displayStr) and C_Spell.GetSpellCastCount then
            local cc = C_Spell.GetSpellCastCount(activeID)
            if cc ~= nil then
                if issecretvalue(cc) then
                    displayStr = cc
                elseif type(cc) == "number" and cc > 0 then
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
            isUsable = sfui.common.SafeValue(u, true)
            notEnoughPower = sfui.common.SafeValue(p, false)
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

function IC.UpdateGlow(icon, entrySettings, panelConfig, getIconValueFn, isReady, missingAlert, startGlowFn, stopGlowFn)
    if missingAlert then
        sfui.glows.resolve_config(entrySettings, panelConfig, _tempGlowCfg)
        local prev = icon._lastGlowCfg
        if not icon._glowActive or not prev or prev.glowType ~= _tempGlowCfg.glowType
            or prev.glowColor ~= _tempGlowCfg.glowColor then
            if icon._glowActive then stopGlowFn(icon) end
            startGlowFn(icon, _tempGlowCfg)
        end
        icon._missingGlow = true
        return
    elseif icon._missingGlow then
        icon._missingGlow = false
        icon._pendingGlow = false
        icon._glowStartTime = nil
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
            sfui.glows.resolve_config(entrySettings, panelConfig, _tempGlowCfg)
            local glowType = _tempGlowCfg.glowType
            local needsRestart = false
            if not icon._glowActive then
                needsRestart = true
            elseif icon._lastGlowType ~= glowType then
                needsRestart = true
            else
                local prev = icon._lastGlowCfg
                if prev and prev.glowColor and _tempGlowCfg.glowColor then
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
                if icon._glowActive then stopGlowFn(icon) end
                startGlowFn(icon, _tempGlowCfg)
            end
        elseif icon._glowActive then
            stopGlowFn(icon)
        end
    else
        icon._glowStartTime = nil
        if icon._glowActive then
            stopGlowFn(icon)
        end
    end
end
