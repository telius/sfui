local addonName, addon = ...
sfui = sfui or {}
sfui.safety = sfui.safety or {}
sfui.common = sfui.common or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/core/safety.lua
--  Taint Boundaries, Secret-Value Guards, Safe Arithmetic & Formatters
-- ══════════════════════════════════════════════════════════════════════════════

local _issecretvalue = _G.issecretvalue
local C_Secrets      = _G.C_Secrets

local function issecretvalue(val)
    if val == nil then return false end
    if _issecretvalue then
        return _issecretvalue(val)
    end
    if C_Secrets and C_Secrets.HasSecretRestrictions and not C_Secrets.HasSecretRestrictions() then
        return false
    end
    return false
end
sfui.safety.issecretvalue = issecretvalue
sfui.common.issecretvalue = issecretvalue

-- Robust helper to check if an aura/ID is present, even if it's a secret value
function sfui.safety.HasAuraInstanceID(value)
    if value == nil then return false end
    if issecretvalue(value) then return true end
    if type(value) == "number" and value == 0 then return false end
    return true
end
sfui.common.HasAuraInstanceID = sfui.safety.HasAuraInstanceID

-- Safe numeric comparison
function sfui.safety.IsNumericAndPositive(value)
    if value == nil then return false end
    return type(value) == "number" and value > 0
end
sfui.common.IsNumericAndPositive = sfui.safety.IsNumericAndPositive

-- ────────────────────────────────────────────────────────────────────────────
-- Pre-computed String Lookup Tables (Zero-Allocation Hot Path)
-- ────────────────────────────────────────────────────────────────────────────
local INT_STR_LUT = {}
for i = 0, 200 do
    INT_STR_LUT[i] = tostring(i)
end

local DEC_STR_LUT = {}
for i = 1, 50 do
    DEC_STR_LUT[i] = string.format("%.1f", i / 10)
end

local FMT_PATTERNS = {
    [0] = "%.0f",
    [1] = "%.1f",
    [2] = "%.2f",
}

--- Fast zero-allocation integer-to-string lookup for numbers 0-200.
--- Falls back to tostring for larger values and handles secret values safely.
function sfui.safety.get_cached_int_string(val)
    if val == nil then return "" end
    local t = type(val)
    if t == "number" then
        local floorVal = math.floor(val)
        return INT_STR_LUT[floorVal] or tostring(floorVal)
    elseif t == "string" then
        return val
    end
    if issecretvalue(val) then return val end
    return tostring(val)
end
sfui.common.get_cached_int_string = sfui.safety.get_cached_int_string

--- Safe zero-allocation duration formatting.
--- Utilizes pre-computed LUT for integer seconds (0-200s) and fast sub-5s decimals (0.1-5.0s).
function sfui.safety.SafeFormatDuration(value, decimals)
    if value == nil then return "" end
    if issecretvalue(value) then return value end

    local num = tonumber(value)
    if not num then return tostring(value) end

    decimals = decimals or 0
    if decimals == 0 then
        local intVal = math.floor(num + 0.5)
        if intVal >= 0 and intVal <= 200 then
            return INT_STR_LUT[intVal]
        end
    elseif decimals == 1 and num >= 0.1 and num <= 5.0 then
        local decKey = math.floor(num * 10 + 0.5)
        if decKey >= 1 and decKey <= 50 then
            return DEC_STR_LUT[decKey]
        end
    end

    local fmt = FMT_PATTERNS[decimals] or ("%." .. decimals .. "f")
    return string.format(fmt, num)
end
sfui.common.SafeFormatDuration = sfui.safety.SafeFormatDuration

--- Formats seconds into digital clock format: "H:MM:SS" or "M:SS".
function sfui.safety.format_timer_clock(secs)
    if not secs or secs <= 0 then return nil end
    secs = math.floor(secs)
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    local s = secs % 60
    if h > 0 then
        return string.format("%d:%02d:%02d", h, m, s)
    else
        return string.format("%d:%02d", m, s)
    end
end
sfui.common.format_timer_clock = sfui.safety.format_timer_clock

-- Helper: Check if Mounted OR in Druid Travel Form (Spell 783)
function sfui.safety.is_mounted_or_travel_form()
    if IsMounted() then return true end
    if sfui.common.get_player_class and sfui.common.get_player_class() == "DRUID" and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        return C_UnitAuras.GetPlayerAuraBySpellID(783) ~= nil
    end
    return false
end
sfui.common.is_mounted_or_travel_form = sfui.safety.is_mounted_or_travel_form

-- Helper: Check for Dragonriding state (Vigor)
function sfui.safety.IsDragonriding()
    if not sfui.safety.is_mounted_or_travel_form() then return false end

    -- Check for Vigor (Enum.PowerType.AlternateMount = 29)
    if UnitPowerMax("player", 29) > 0 then
        return true
    end

    -- Fallback: Check for Gliding Info
    if C_PlayerInfo and C_PlayerInfo.GetGlidingInfo then
        local _, canGlide = C_PlayerInfo.GetGlidingInfo()
        if canGlide then return true end
    end
    return false
end
sfui.common.IsDragonriding = sfui.safety.IsDragonriding

-- Safe helper to check if player is on GCD and get the duration
function sfui.safety.GetGCDInfo()
    if C_Spell and C_Spell.GetSpellCooldown then
        local ci = C_Spell.GetSpellCooldown(61304)
        if ci and ci.duration and ci.duration > 0 then
            return true, ci.duration
        end
    end
    return false, 0
end
sfui.common.GetGCDInfo = sfui.safety.GetGCDInfo

-- Safe helper to get a duration object for a spell (nil check is non-secret)
function sfui.safety.GetCooldownDurationObj(spellID)
    if not spellID then return nil end
    local obj
    if C_Spell and C_Spell.GetSpellChargeDuration then
        obj = C_Spell.GetSpellChargeDuration(spellID)
    end
    if not obj and C_Spell and C_Spell.GetSpellCooldownDuration then
        obj = C_Spell.GetSpellCooldownDuration(spellID)
    end
    return obj
end
sfui.common.GetCooldownDurationObj = sfui.safety.GetCooldownDurationObj

-- Check if a cooldown frame is showing an active cooldown
function sfui.safety.IsCooldownFrameActive(cooldownFrame)
    if not cooldownFrame or not cooldownFrame.GetCooldownDuration then return false end

    local duration = cooldownFrame:GetCooldownDuration()
    if not duration then return false end

    -- If duration is secret, check if it's just GCD
    if issecretvalue(duration) then
        local onGCD = sfui.safety.GetGCDInfo()
        if onGCD then return false end
        return true
    end

    if duration == 0 then
        return false
    end

    local onGCD, gcdDur = sfui.safety.GetGCDInfo()
    if onGCD and duration <= (gcdDur * 1000 + 10) then
        return false
    end

    local threshold = (sfui.config and sfui.config.castBar and sfui.config.castBar.gcdThreshold) or 1510
    return duration > threshold
end
sfui.common.IsCooldownFrameActive = sfui.safety.IsCooldownFrameActive

function sfui.safety.SafeValue(val, fallback)
    if issecretvalue and issecretvalue(val) then return val end
    if val == nil then return fallback end
    return val
end
sfui.common.SafeValue = sfui.safety.SafeValue


-- Safely set text on a fontstring (SetText accepts secret values)
function sfui.safety.SafeSetText(fontString, text, decimals)
    if not fontString then return end
    if decimals == nil and type(text) == "string" then
        fontString:SetText(text)
    else
        fontString:SetText(sfui.safety.SafeFormatDuration(text, decimals) or "")
    end
end
sfui.common.SafeSetText = sfui.safety.SafeSetText

-- Safely set value on a statusbar (SetValue accepts secret values)
function sfui.safety.SafeSetValue(bar, value)
    if not bar or not bar.SetValue then return end
    if issecretvalue and issecretvalue(value) then
        local ok = pcall(bar.SetValue, bar, value)
        if not ok then bar:SetValue(0) end
        return
    end
    local num = type(value) == "number" and value or tonumber(value)
    if num and num == num and num >= -3.4e38 and num <= 3.4e38 then
        bar:SetValue(num)
    else
        bar:SetValue(0)
    end
end
sfui.common.SafeSetValue = sfui.safety.SafeSetValue

-- Safely set min/max values on a statusbar
function sfui.safety.SafeSetMinMaxValues(bar, minVal, maxVal)
    if not bar or not bar.SetMinMaxValues then return end
    if issecretvalue and (issecretvalue(minVal) or issecretvalue(maxVal)) then
        bar:SetMinMaxValues(minVal, maxVal)
        return
    end
    local nMin = type(minVal) == "number" and minVal or tonumber(minVal) or 0
    local nMax = type(maxVal) == "number" and maxVal or tonumber(maxVal) or 1
    if nMin ~= nMin or nMin < -3.4e38 or nMin > 3.4e38 then nMin = 0 end
    if nMax ~= nMax or nMax < -3.4e38 or nMax > 3.4e38 then nMax = 1 end
    if nMin > nMax then nMax = nMin end
    bar:SetMinMaxValues(nMin, nMax)
end
sfui.common.SafeSetMinMaxValues = sfui.safety.SafeSetMinMaxValues

-- Helper to format money amount using the best available engine API or manual formatting
local function FormatCoinString(amount)
    if amount == nil then return "" end
    local num = type(amount) == "number" and amount or tonumber(amount)
    if not num then return "" end

    -- Both Retail and Camelot support C_CurrencyInfo.GetCoinTextureString.
    -- It does not throw; it returns nil or "" for bad input.
    if _G.C_CurrencyInfo and _G.C_CurrencyInfo.GetCoinTextureString then
        local str = _G.C_CurrencyInfo.GetCoinTextureString(num)
        if str and str ~= "" then return str end
    end

    local gold = math.floor(num / 10000)
    local silver = math.floor((num % 10000) / 100)
    local copper = num % 100
    local parts = {}
    if gold > 0 then
        table.insert(parts, string.format("%d|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t", gold))
    end
    if silver > 0 then
        table.insert(parts, string.format("%d|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t", silver))
    end
    if copper > 0 or #parts == 0 then
        table.insert(parts, string.format("%d|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t", copper))
    end
    return table.concat(parts, " ")
end
sfui.safety.FormatCoinString = FormatCoinString
sfui.common.FormatCoinString = FormatCoinString

-- Safely get a coin texture string
function sfui.safety.SafeGetCoinTextureString(amount)
    if amount == nil then return "" end
    if issecretvalue(amount) then return "|cff00ffff[Protected]|r" end
    local str = FormatCoinString(amount)
    if str and str ~= "" then
        return str
    end
    return "0|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t"
end
sfui.common.SafeGetCoinTextureString = sfui.safety.SafeGetCoinTextureString

-- Safely set money display in a tooltip using securecall to avoid arithmetic taint.
function sfui.safety.SafeSetTooltipMoney(tooltip, amount, label)
    if not tooltip or amount == nil then return end
    local coinStr = sfui.safety.SafeGetCoinTextureString(amount)
    if label then
        tooltip:AddDoubleLine(label, coinStr, 1, 1, 1, 1, 1, 1)
    else
        tooltip:AddLine(coinStr)
    end
end
sfui.common.SafeSetTooltipMoney = sfui.safety.SafeSetTooltipMoney

-- Safely add a money line using FormatCoinString
function sfui.safety.SafeAddMoneyLine(tooltip, label, amount)
    if not tooltip or amount == nil then return end
    if issecretvalue(amount) then
        tooltip:AddLine((label or "") .. "|cff00ffff[Protected Data]|r")
        return
    end
    local coinStr = FormatCoinString(amount)
    if coinStr and coinStr ~= "" then
        tooltip:AddLine((label or "") .. coinStr)
    else
        tooltip:AddLine((label or "") .. "0|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t")
    end
end
sfui.common.SafeAddMoneyLine = sfui.safety.SafeAddMoneyLine

-- Safely compare units (UnitIsUnit crashes on secret values if execution is tainted)
function sfui.safety.SafeUnitIsUnit(unit1, unit2)
    if not unit1 or not unit2 then return false end
    if issecretvalue(unit1) or issecretvalue(unit2) then
        if type(unit1) == "string" and type(unit2) == "string" then
            return unit1 == unit2
        end
        return false
    end
    if UnitIsUnit then
        return UnitIsUnit(unit1, unit2) or false
    end
    return false
end
sfui.common.SafeUnitIsUnit = sfui.safety.SafeUnitIsUnit

function sfui.safety.copy(t)
    if type(t) ~= "table" then return t end
    local res = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            res[k] = sfui.safety.copy(v)
        else
            res[k] = v
        end
    end
    return res
end
sfui.common.copy = sfui.safety.copy
