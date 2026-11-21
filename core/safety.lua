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
    if _issecretvalue then
        return not not _issecretvalue(val)
    end
    if val == nil then return false end
    if C_Secrets and C_Secrets.HasSecretRestrictions and not C_Secrets.HasSecretRestrictions() then
        return false
    end
    return false
end
sfui.safety.issecretvalue = issecretvalue
sfui.common.issecretvalue = issecretvalue

local wipe = _G.wipe or (_G.table and _G.table.wipe) or function(t)
    if type(t) ~= "table" then return t end
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end
sfui.safety.wipe = wipe
sfui.common.wipe = wipe

-- Robust helper to check if an aura/ID is present, even if it's a secret value
function sfui.safety.HasAuraInstanceID(value)
    if issecretvalue(value) then return true end
    if value == nil then return false end
    if type(value) == "number" and value == 0 then return false end
    return true
end
sfui.common.HasAuraInstanceID = sfui.safety.HasAuraInstanceID

-- Safe numeric comparison
function sfui.safety.IsNumericAndPositive(value)
    if issecretvalue(value) then return false end
    if value == nil then return false end
    return type(value) == "number" and value > 0
end
sfui.common.IsNumericAndPositive = sfui.safety.IsNumericAndPositive

-- Safe attack speed validation (handles secret values when combat haste buffs are active)
function sfui.safety.IsAttackSpeedValid(speed)
    if issecretvalue(speed) then return true end
    if speed == nil then return false end
    return type(speed) == "number" and speed > 0
end
sfui.common.IsAttackSpeedValid = sfui.safety.IsAttackSpeedValid

-- Safe typed secret-value validators (never compare/inspect secret values)
function sfui.safety.IsPlainNumber(val)
    return val ~= nil and not issecretvalue(val) and type(val) == "number"
end
sfui.common.IsPlainNumber = sfui.safety.IsPlainNumber

function sfui.safety.IsPlainPositiveNumber(val)
    return val ~= nil and not issecretvalue(val) and type(val) == "number" and val > 0
end
sfui.common.IsPlainPositiveNumber = sfui.safety.IsPlainPositiveNumber

function sfui.safety.IsPlainNonEmptyString(val)
    return val ~= nil and not issecretvalue(val) and type(val) == "string" and val ~= ""
end
sfui.common.IsPlainNonEmptyString = sfui.safety.IsPlainNonEmptyString

function sfui.safety.IsPlainTable(val)
    return val ~= nil and not issecretvalue(val) and type(val) == "table"
end
sfui.common.IsPlainTable = sfui.safety.IsPlainTable

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
    if issecretvalue(val) then return val end
    local t = type(val)
    if t == "number" then
        local floorVal = math.floor(val)
        return INT_STR_LUT[floorVal] or tostring(floorVal)
    elseif t == "string" then
        return val
    end
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
--- @param secs number|nil seconds
--- @param fallback string|nil optional fallback when secs <= 0 (defaults to "0:00")
--- @param compact boolean|nil if true, formats < 60s as "S" rather than "0:SS"
--- @return string|nil formattedClock
function sfui.safety.format_timer_clock(secs, fallback, compact)
    local defaultFallback = compact and "" or "0:00"
    local fb = (fallback ~= nil) and fallback or defaultFallback
    if not secs then return fb end
    local num = tonumber(secs)
    if not num then return fb end
    if num <= 0 then
        return fb
    end
    num = math.floor(num + 0.5)
    local h = math.floor(num / 3600)
    local m = math.floor((num % 3600) / 60)
    local s = num % 60
    if h > 0 then
        return string.format("%d:%02d:%02d", h, m, s)
    elseif m > 0 then
        return string.format("%d:%02d", m, s)
    elseif compact then
        return string.format("%d", s)
    else
        return string.format("%d:%02d", m, s)
    end
end
sfui.common.format_timer_clock = sfui.safety.format_timer_clock

-- Helper: Check if Mounted OR in Druid Travel Form (Spell 783)
function sfui.safety.is_mounted_or_travel_form()
    local cur = sfui.state and sfui.state.current
    if cur and cur.revision > 0 then
        return cur.isMountedOrTravel
    end
    if IsMounted() then return true end
    if sfui.common.get_player_class() == "DRUID" and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        return C_UnitAuras.GetPlayerAuraBySpellID(783) ~= nil
    end
    return false
end
sfui.common.is_mounted_or_travel_form = sfui.safety.is_mounted_or_travel_form

-- Helper: Check for Dragonriding state (Vigor)
function sfui.safety.IsDragonriding()
    local cur = sfui.state and sfui.state.current
    if cur and cur.revision > 0 then
        return cur.isDragonriding
    end
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
        if ci then
            if issecretvalue and issecretvalue(ci.duration) then
                return ci.isActive == true, 0
            elseif ci.duration and ci.duration > 0 then
                return true, ci.duration
            end
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


-- Safely set text on a fontstring (SetText accepts raw and secret values directly)
function sfui.safety.SafeSetText(fontString, text, decimals)
    if not fontString or not fontString.SetText or text == nil then return end
    if decimals and type(text) == "number" then
        fontString:SetText(sfui.safety.SafeFormatDuration(text, decimals) or text)
    else
        fontString:SetText(text)
    end
end
sfui.common.SafeSetText = sfui.safety.SafeSetText

-- Safely set value on a statusbar (SetValue accepts raw and secret values directly)
function sfui.safety.SafeSetValue(bar, value)
    if not bar or not bar.SetValue or value == nil then return end
    bar:SetValue(value)
end
sfui.common.SafeSetValue = sfui.safety.SafeSetValue

-- Safely set min/max values on a statusbar (SetMinMaxValues accepts raw and secret values directly)
function sfui.safety.SafeSetMinMaxValues(bar, minVal, maxVal)
    if not bar or not bar.SetMinMaxValues or minVal == nil or maxVal == nil then return end
    bar:SetMinMaxValues(minVal, maxVal)
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
sfui.safety.format_money = FormatCoinString
sfui.common.format_money = FormatCoinString

--- Format copper amount into compact plain text (e.g. "12g 34s", "45s", "80c")
--- @param copper number?
--- @param opts table?
--- @return string?
function sfui.safety.FormatMoneyShort(copper, opts)
    local nilOnZero = opts and opts.nil_on_zero
    if copper == nil or issecretvalue(copper) or type(copper) ~= "number" or copper <= 0 then
        if nilOnZero then return nil end
        return "0c"
    end
    local total = math.floor(copper + 0.5)
    local g = math.floor(total / 10000)
    local s = math.floor((total % 10000) / 100)
    local c = total % 100
    if g > 0 then
        if s == 0 or (opts and opts.compact_gold and g >= 100) then
            return string.format("%dg", g)
        end
        return string.format("%dg %ds", g, s)
    elseif s > 0 then
        if c > 0 and not (opts and opts.omit_copper_with_silver) then
            return string.format("%ds %dc", s, c)
        end
        return string.format("%ds", s)
    end
    return string.format("%dc", c)
end
sfui.safety.format_money_short = sfui.safety.FormatMoneyShort
sfui.common.FormatMoneyShort = sfui.safety.FormatMoneyShort
sfui.common.format_money_short = sfui.safety.FormatMoneyShort

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

-- Safely compare units (UnitIsUnit returns secret booleans on restricted maps / compound tokens)
function sfui.safety.SafeUnitIsUnit(unit1, unit2)
    if not unit1 or not unit2 then return false end
    if issecretvalue(unit1) or issecretvalue(unit2) then
        return false
    end
    if unit1 == unit2 then
        return true
    end
    local cSecrets = _G.C_Secrets
    if cSecrets then
        if cSecrets.CanCompareUnitTokens and not cSecrets.CanCompareUnitTokens(unit1, unit2) then
            return false
        end
        if cSecrets.ShouldUnitComparisonBeSecret and cSecrets.ShouldUnitComparisonBeSecret(unit1, unit2) then
            return false
        end
    end
    if UnitIsUnit then
        local res = UnitIsUnit(unit1, unit2)
        if issecretvalue(res) then
            return false
        end
        return res or false
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

--- Return true if frame can safely have regions/points modified right now
function sfui.safety.CanModifyRegion(f)
    if not f then return false end
    local icl = _G.InCombatLockdown
    if not (icl and icl()) then
        return true
    end
    if f.IsProtected then
        local prot = f:IsProtected()
        if issecretvalue(prot) or prot then
            return false
        end
    end
    if f.IsAnchoringRestricted then
        local rest = f:IsAnchoringRestricted()
        if issecretvalue(rest) or rest then
            return false
        end
    end
    return true
end
sfui.common.CanModifyRegion = sfui.safety.CanModifyRegion
sfui.common.can_modify_region = sfui.safety.CanModifyRegion

-- ─────────────────────────────────────────────────────────────────────────────
-- Priority-Budgeted Out-of-Combat Execution Queue (P0 / P1 / P2)
-- ─────────────────────────────────────────────────────────────────────────────
sfui.combat = sfui.combat or {}

local OOC_P0 = 0 -- Immediate synchronous on PLAYER_REGEN_ENABLED (secure frames, unitwatches, bindings, rings)
local OOC_P1 = 1 -- Same-frame up to 4.0ms budget (HUD visibility & layout)
local OOC_P2 = 2 -- Background frame-sliced <= 2.5ms/frame (alt scans, sync deltas, scoring, triage)

sfui.safety.OOC_P0 = OOC_P0
sfui.safety.OOC_P1 = OOC_P1
sfui.safety.OOC_P2 = OOC_P2
sfui.combat.P0 = OOC_P0
sfui.combat.P1 = OOC_P1
sfui.combat.P2 = OOC_P2

local oocItemsByKey = {}
local oocOrderByTier = {
    [0] = {},
    [1] = {},
    [2] = {},
}
local oocReadIdx = {
    [0] = 1,
    [1] = 1,
    [2] = 1,
}
local _oocAnonSeq = 0
local _oocSliceScheduled = false
local _inCombatLockdown = _G.InCombatLockdown
local _unitAffectingCombat = _G.UnitAffectingCombat
local _debugprofilestop = _G.debugprofilestop
local _cTimer = _G.C_Timer

local function is_in_combat()
    if _inCombatLockdown and _inCombatLockdown() then return true end
    if sfui.common and sfui.common.is_in_combat and sfui.common.is_in_combat() then return true end
    if _unitAffectingCombat and _unitAffectingCombat("player") then return true end
    return false
end

local function execute_ooc_item(item, contextLabel)
    if not item or type(item.fn) ~= "function" then return end
    local argc = item.argc or 0
    if sfui.events and sfui.events.SafeCall then
        if argc > 0 then
            sfui.events.SafeCall(item.fn, "ooc", "PLAYER_REGEN_ENABLED", contextLabel, unpack(item.args, 1, argc))
        else
            sfui.events.SafeCall(item.fn, "ooc", "PLAYER_REGEN_ENABLED", contextLabel)
        end
    else
        if argc > 0 then
            pcall(item.fn, unpack(item.args, 1, argc))
        else
            pcall(item.fn)
        end
    end
end

local function compact_tier_if_empty(tier)
    local list = oocOrderByTier[tier]
    if oocReadIdx[tier] > #list then
        for i = #list, 1, -1 do list[i] = nil end
        oocReadIdx[tier] = 1
        return true
    end
    return false
end

local function drain_tier_unbounded(tier, labelPrefix)
    local list = oocOrderByTier[tier]
    while oocReadIdx[tier] <= #list do
        if is_in_combat() then return false end
        local idx = oocReadIdx[tier]
        local key = list[idx]
        list[idx] = nil
        oocReadIdx[tier] = idx + 1
        local item = key and oocItemsByKey[key]
        if item and item.tier == tier then
            oocItemsByKey[key] = nil
            execute_ooc_item(item, labelPrefix .. tostring(key))
        end
    end
    compact_tier_if_empty(tier)
    return true
end

local function drain_tier_budgeted(tier, budgetMs, labelPrefix)
    local list = oocOrderByTier[tier]
    local startMs = _debugprofilestop and _debugprofilestop() or nil
    local ranAny = false
    while oocReadIdx[tier] <= #list do
        if is_in_combat() then return false end
        if ranAny and startMs and budgetMs and (_debugprofilestop() - startMs) >= budgetMs then
            return false
        end
        local idx = oocReadIdx[tier]
        local key = list[idx]
        list[idx] = nil
        oocReadIdx[tier] = idx + 1
        local item = key and oocItemsByKey[key]
        if item and item.tier == tier then
            oocItemsByKey[key] = nil
            ranAny = true
            execute_ooc_item(item, labelPrefix .. tostring(key))
        end
    end
    compact_tier_if_empty(tier)
    return true
end

local function schedule_ooc_slice()
    if _oocSliceScheduled then return end
    if not (_cTimer and _cTimer.After) then
        drain_tier_unbounded(OOC_P1, "ooc:p1:")
        drain_tier_unbounded(OOC_P2, "ooc:p2:")
        return
    end
    _oocSliceScheduled = true
    _cTimer.After(0, function()
        _oocSliceScheduled = false
        if is_in_combat() then return end

        -- Always clear any P0 that arrived between frames first
        if not drain_tier_unbounded(OOC_P0, "ooc:p0:") then return end
        if not drain_tier_budgeted(OOC_P1, 3.0, "ooc:p1:") then
            schedule_ooc_slice()
            return
        end
        if not drain_tier_budgeted(OOC_P2, 2.5, "ooc:p2:") then
            schedule_ooc_slice()
            return
        end
    end)
end

local function drain_combat_queue()
    if is_in_combat() then return end

    -- P0: 100% synchronous on PLAYER_REGEN_ENABLED (secure frames, bindings, unitwatches)
    if not drain_tier_unbounded(OOC_P0, "ooc:p0:") then return end

    -- P1: same-frame HUD/layout updates up to 4.0ms
    local p1Done = drain_tier_budgeted(OOC_P1, 4.0, "ooc:p1:")

    -- P2 (or remaining P1): sliced cleanly across subsequent frames
    local p2Empty = compact_tier_if_empty(OOC_P2)
    if not p1Done or not p2Empty then
        schedule_ooc_slice()
    end
end

--- Queue an action to run immediately if out of combat, or deferred to PLAYER_REGEN_ENABLED.
--- Deduplicates by key and supports 3 priority tiers (`0` = P0 immediate, `1` = P1 HUD, `2` = P2 background).
--- @param key string|nil Unique identifier for deduplication (nil generates an anonymous unique slot)
--- @param priority number|function Priority tier (0, 1, 2) or callback if omitted
--- @param func function|any Callback when priority is numeric
function sfui.safety.DeferOutOfCombat(key, priority, func, ...)
    local tier = OOC_P1
    local cb = func
    local argc
    local args

    if type(key) == "function" then
        cb = key
        key = nil
        tier = OOC_P1
        argc = select("#", priority, func, ...)
        if argc > 0 then args = { priority, func, ... } end
    elseif type(priority) == "function" then
        cb = priority
        tier = OOC_P0
        argc = select("#", func, ...)
        if argc > 0 then args = { func, ... } end
    else
        if priority == OOC_P0 or priority == OOC_P1 or priority == OOC_P2 then
            tier = priority
        end
        argc = select("#", ...)
        if argc > 0 then args = { ... } end
    end

    if type(cb) ~= "function" then return end
    if sfui.events and sfui.events.RecordCaller then
        sfui.events.RecordCaller(cb, nil, "ooc")
    end

    if not is_in_combat() then
        local label = "ooc:immediate:" .. tostring(key or "anon")
        if sfui.events and sfui.events.SafeCall then
            if argc and argc > 0 then
                sfui.events.SafeCall(cb, "ooc", "DeferOutOfCombat", label, unpack(args, 1, argc))
            else
                sfui.events.SafeCall(cb, "ooc", "DeferOutOfCombat", label)
            end
        else
            if argc and argc > 0 then
                cb(unpack(args, 1, argc))
            else
                cb()
            end
        end
        return
    end

    if key == nil then
        _oocAnonSeq = _oocAnonSeq + 1
        key = "_anon_" .. _oocAnonSeq
    else
        key = tostring(key)
    end

    local existing = oocItemsByKey[key]
    if existing then
        -- Promote priority if re-queued at a higher priority (lower tier number)
        if tier < existing.tier then
            existing.tier = tier
            local list = oocOrderByTier[tier]
            list[#list + 1] = key
        end
        existing.fn = cb
        existing.args = args
        existing.argc = argc or 0
    else
        oocItemsByKey[key] = {
            tier = tier,
            fn   = cb,
            args = args,
            argc = argc or 0,
        }
        local list = oocOrderByTier[tier]
        list[#list + 1] = key
    end
end

function sfui.combat.after_combat(key, func, ...)
    if type(key) == "function" then
        return sfui.safety.DeferOutOfCombat(nil, OOC_P1, key, func, ...)
    end
    return sfui.safety.DeferOutOfCombat(key, OOC_P0, func, ...)
end

sfui.combat.DeferOutOfCombat = sfui.safety.DeferOutOfCombat
sfui.common.DeferOutOfCombat = sfui.safety.DeferOutOfCombat
sfui.combat.run_after_combat = sfui.combat.after_combat
sfui.common.after_combat = sfui.combat.after_combat
sfui.common.run_after_combat = sfui.combat.after_combat

sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", drain_combat_queue)

-- ─────────────────────────────────────────────────────────────────────────────
-- Consolidated Secure Unit Watch & State Driver Helpers
-- ─────────────────────────────────────────────────────────────────────────────
local RegisterUnitWatch     = _G.RegisterUnitWatch
local UnregisterUnitWatch   = _G.UnregisterUnitWatch
local RegisterStateDriver   = _G.RegisterStateDriver
local UnregisterStateDriver = _G.UnregisterStateDriver

--- Safely register a frame with Blizzard's RegisterUnitWatch without taint errors.
--- Automatically defers to after combat if currently in combat lockdown.
--- @param frame Frame
--- @param asState boolean|nil
function sfui.safety.register_unit_watch(frame, asState)
    if not frame then return end
    if is_in_combat() then
        local key = "unitwatch_" .. tostring(frame:GetName() or frame)
        sfui.combat.after_combat(key, function()
            sfui.safety.register_unit_watch(frame, asState)
        end)
        return
    end
    if RegisterUnitWatch then
        RegisterUnitWatch(frame, asState)
    end
end

--- Safely unregister a frame from Blizzard's RegisterUnitWatch.
--- @param frame Frame
function sfui.safety.unregister_unit_watch(frame)
    if not frame then return end
    if is_in_combat() then
        local key = "un_unitwatch_" .. tostring(frame:GetName() or frame)
        sfui.combat.after_combat(key, function()
            sfui.safety.unregister_unit_watch(frame)
        end)
        return
    end
    if UnregisterUnitWatch then
        UnregisterUnitWatch(frame)
    end
end

--- Safely register a state driver on a frame.
--- @param frame Frame
--- @param state string
--- @param conditional string
function sfui.safety.register_state_driver(frame, state, conditional)
    if not frame or not state or not conditional then return end
    if is_in_combat() then
        local key = "statedriver_" .. tostring(frame:GetName() or frame) .. "_" .. state
        sfui.combat.after_combat(key, function()
            sfui.safety.register_state_driver(frame, state, conditional)
        end)
        return
    end
    if RegisterStateDriver then
        RegisterStateDriver(frame, state, conditional)
    end
end

--- Safely unregister a state driver from a frame.
--- @param frame Frame
--- @param state string
function sfui.safety.unregister_state_driver(frame, state)
    if not frame or not state then return end
    if is_in_combat() then
        local key = "un_statedriver_" .. tostring(frame:GetName() or frame) .. "_" .. state
        sfui.combat.after_combat(key, function()
            sfui.safety.unregister_state_driver(frame, state)
        end)
        return
    end
    if UnregisterStateDriver then
        UnregisterStateDriver(frame, state)
    end
end

sfui.common.register_unit_watch = sfui.safety.register_unit_watch
sfui.common.unregister_unit_watch = sfui.safety.unregister_unit_watch
sfui.common.register_state_driver = sfui.safety.register_state_driver
sfui.common.unregister_state_driver = sfui.safety.unregister_state_driver

-- ─────────────────────────────────────────────────────────────────────────────
-- Centralized Duration, Money, Text & Realm Formatting Helpers
-- ─────────────────────────────────────────────────────────────────────────────

local DURATION_DEFAULT_FALLBACK = {
    compact       = "-",
    timer         = "now",
    long          = "n/a",
    ago           = "never",
    clock_ms      = "0:00",
    clock_compact = "0s",
}

--- Shared duration formatter supporting multiple UI display styles.
--- @param seconds number|nil
--- @param style string|nil "compact"|"short"|"timer"|"long"|"cooldown"|"cooldown_bare"|"cooldown_hm"|"eta"|"ago"|"clock"|"clock_ms"|"clock_compact"
--- @param fallback string|boolean|nil explicit fallback (pass false to receive nil on <=0/invalid)
--- @return string|nil
function sfui.safety.format_duration(seconds, style, fallback)
    local st = style or "compact"
    if st == "clock" then
        return sfui.safety.format_timer_clock(seconds, (fallback == false) and "" or fallback)
    end

    local fb
    if fallback == false then
        fb = nil
    elseif fallback ~= nil then
        fb = fallback
    else
        fb = DURATION_DEFAULT_FALLBACK[st] or ""
    end

    if seconds == nil or issecretvalue(seconds) or type(seconds) ~= "number" then
        return fb
    end
    if st == "clock_ms" then
        local sec = math.max(0, math.floor(seconds + 0.5))
        return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
    end
    if seconds <= 0 then
        return fb
    end

    if st == "compact" then
        local d = math.floor(seconds / 86400)
        local h = math.floor((seconds % 86400) / 3600)
        local m = math.floor((seconds % 3600) / 60)
        if d > 0 then
            return string.format("%dd %dh", d, h)
        elseif h > 0 then
            return string.format("%dh %dm", h, m)
        elseif m > 0 then
            return string.format("%dm", m)
        end
        return "< 1m"
    elseif st == "short" then
        if seconds >= 86400 then
            return string.format("%dd", math.floor(seconds / 86400))
        elseif seconds >= 3600 then
            return string.format("%dh", math.floor(seconds / 3600))
        elseif seconds >= 60 then
            return string.format("%dm", math.ceil(seconds / 60))
        end
        return string.format("%ds", math.max(1, math.floor(seconds)))
    elseif st == "timer" then
        local sec = math.floor(seconds)
        if sec <= 0 then return fb end
        if sec >= 3600 then
            local h = math.floor(sec / 3600)
            local m = math.floor((sec % 3600) / 60)
            return (m > 0) and string.format("%dh %dm", h, m) or string.format("%dh", h)
        elseif sec >= 60 then
            return string.format("%dm", math.floor(sec / 60))
        end
        return string.format("%ds", sec)
    elseif st == "long" then
        local s = math.floor(seconds)
        if s <= 0 then return fb end
        local h = math.floor(s / 3600)
        local m = math.floor((s % 3600) / 60)
        local sec = s % 60
        if h > 0 then
            return string.format("%dh %02dm", h, m)
        elseif m > 0 then
            return string.format("%dm %02ds", m, sec)
        end
        return string.format("%ds", sec)
    elseif st == "cooldown" then
        if seconds > 86400 then
            return string.format("%dd", math.ceil(seconds / 86400))
        elseif seconds > 3600 then
            return string.format("%dh", math.ceil(seconds / 3600))
        elseif seconds > 90 then
            return string.format("%dm", math.ceil(seconds / 60))
        elseif seconds >= 10 then
            return string.format("%ds", math.ceil(seconds))
        end
        return string.format("%.1fs", seconds)
    elseif st == "cooldown_bare" then
        if seconds < 10 then
            return string.format("%.1f", seconds)
        elseif seconds < 60 then
            return string.format("%d", math.ceil(seconds))
        end
        return string.format("%dm", math.ceil(seconds / 60))
    elseif st == "cooldown_hm" then
        if seconds > 3600 then
            return string.format("%.1fh", seconds / 3600)
        elseif seconds > 60 then
            return string.format("%dm", math.floor(seconds / 60))
        end
        return string.format("%ds", math.floor(seconds))
    elseif st == "eta" then
        if seconds < 60 then
            return "<1m"
        end
        local totalMin = math.floor((seconds / 60) + 0.5)
        if totalMin < 60 then
            return string.format("%dm", math.max(1, totalMin))
        end
        return string.format("%dh%02dm", math.floor(totalMin / 60), totalMin % 60)
    elseif st == "ago" then
        if seconds < 5 then return "just now" end
        if seconds < 60 then return string.format("%ds ago", math.floor(seconds)) end
        if seconds < 3600 then return string.format("%dm ago", math.floor(seconds / 60)) end
        if seconds < 86400 then return string.format("%dh ago", math.floor(seconds / 3600)) end
        return string.format("%dd ago", math.floor(seconds / 86400))
    elseif st == "clock_compact" then
        local total = math.floor(seconds + 0.5)
        local m = math.floor(total / 60)
        local s = total % 60
        return (m > 0) and string.format("%d:%02d", m, s) or string.format("%ds", s)
    end

    return sfui.safety.format_timer_clock(seconds, fb)
end
sfui.common.format_duration = sfui.safety.format_duration

--- Format copper into colored gold/silver string (used by compact HUD badges).
--- @param copper number|nil
--- @return string
function sfui.safety.format_money_colored(copper)
    if copper == nil or issecretvalue(copper) or type(copper) ~= "number" or copper <= 0 then
        return "|cffc7c7cf0s|r"
    end
    local total = math.floor(copper + 0.5)
    local g = math.floor(total / 10000)
    local s = math.floor((total % 10000) / 100)
    if g >= 1000 then
        return string.format("|cffffd100%dg|r", g)
    elseif g > 0 then
        return string.format("|cffffd100%dg|r |cffc7c7cf%ds|r", g, s)
    end
    return string.format("|cffc7c7cf%ds|r", s)
end
sfui.common.format_money_colored = sfui.safety.format_money_colored

local COIN_TEX_GOLD   = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:1:0|t"
local COIN_TEX_SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:1:0|t"
local COIN_TEX_COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:1:0|t"

--- Format copper into abbreviated M/K gold, with optional inline coin textures.
--- @param copper number|nil
--- @param useIcons boolean|nil
--- @return string
function sfui.safety.format_money_abbreviated(copper, useIcons)
    local gTag = useIcons and COIN_TEX_GOLD or "g"
    local sTag = useIcons and COIN_TEX_SILVER or "s"
    local cTag = useIcons and COIN_TEX_COPPER or "c"
    if copper == nil or issecretvalue(copper) or type(copper) ~= "number" or copper <= 0 then
        return "0" .. cTag
    end
    local total = math.floor(copper + 0.5)
    local g = math.floor(total / 10000)
    if g >= 1000000 then
        return string.format("%.2fM", g / 1000000) .. gTag
    elseif g >= 1000 then
        return string.format("%.1fK", g / 1000) .. gTag
    elseif g > 0 then
        return tostring(g) .. gTag
    end
    local s = math.floor((total % 10000) / 100)
    if s > 0 then
        return tostring(s) .. sTag
    end
    return tostring(total % 100) .. cTag
end
sfui.common.format_money_abbreviated = sfui.safety.format_money_abbreviated

--- Strip WoW color escape sequences (|c..., |cn...:, |r) and optionally trim whitespace or textures.
--- @param str string|nil
--- @param trim boolean|nil
--- @param stripTextures boolean|nil
--- @return string
function sfui.safety.strip_colors(str, trim, stripTextures)
    if str == nil or issecretvalue(str) or type(str) ~= "string" then
        return ""
    end
    local clean = str:gsub("|cn[^:]+:", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    if stripTextures then
        clean = clean:gsub("|T.-|t", "")
    end
    if trim then
        clean = clean:match("^%s*(.-)%s*$") or ""
    end
    return clean
end
sfui.common.strip_colors = sfui.safety.strip_colors

--- Escape all Lua pattern metacharacters in a literal string.
--- @param str string|nil
--- @return string
function sfui.safety.escape_pattern(str)
    if str == nil or issecretvalue(str) or type(str) ~= "string" then
        return ""
    end
    return (str:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1"))
end
sfui.common.escape_pattern = sfui.safety.escape_pattern

--- Strip the "-Realm" suffix from a player/unit name (preserving multi-word Camelot surnames).
--- @param fullName string|nil
--- @return string
function sfui.safety.short_name(fullName)
    if fullName == nil or issecretvalue(fullName) or type(fullName) ~= "string" then
        return ""
    end
    return (fullName:gsub("%-.+$", ""))
end
sfui.common.short_name = sfui.safety.short_name

--- Normalize a realm token for case/space/hyphen/apostrophe-insensitive matching.
--- @param realm string|nil
--- @return string
function sfui.safety.normalize_realm(realm)
    local r = realm
    if r == nil then
        r = (_G.GetNormalizedRealmName and _G.GetNormalizedRealmName())
            or (_G.GetRealmName and _G.GetRealmName())
            or (_G.GetCVar and _G.GetCVar("realmName"))
            or ""
    end
    if issecretvalue(r) or type(r) ~= "string" or r == "" then
        return ""
    end
    return (r:gsub("[%s%-']", ""):lower())
end
sfui.common.normalize_realm = sfui.safety.normalize_realm

--- Determine whether a string token represents a server/realm name rather than a Camelot surname.
--- @param name string|nil
--- @return boolean
function sfui.safety.is_server_realm_name(name)
    if name == nil or issecretvalue(name) or type(name) ~= "string" or name == "" then
        return false
    end
    local norm = sfui.safety.normalize_realm(name)
    if norm == "" then return false end
    if norm:find("^camwow") or norm:find("realm") or norm:find("%d") then
        return true
    end
    local r1 = _G.GetRealmName and _G.GetRealmName()
    if r1 and sfui.safety.normalize_realm(r1) == norm then return true end
    local r2 = _G.GetNormalizedRealmName and _G.GetNormalizedRealmName()
    if r2 and sfui.safety.normalize_realm(r2) == norm then return true end
    local r3 = _G.GetCVar and _G.GetCVar("realmName")
    if r3 and sfui.safety.normalize_realm(r3) == norm then return true end
    if norm == "forever" or norm == "camelot" or norm == "global" then
        return true
    end
    return false
end
sfui.common.is_server_realm_name = sfui.safety.is_server_realm_name




