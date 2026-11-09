local addonName, addon = ...
---@diagnostic disable: undefined-global
-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/bars/swing_classic.lua
--  Classic Era (1.15.x) Swing Timer Driver
--  Builds directly upon frames/bars/swing.lua by driving sfui.swing.OnSwingEvent
--  and providing sfui.swing._classicTimer for range checks.
--  Loaded only on [AllowLoadGameType classic].
-- ══════════════════════════════════════════════════════════════════════════════

if not (sfui and sfui.isEra) or _G.C_SwingTimer then
    return
end

sfui.swing = sfui.swing or {}

local common = sfui.common
local GetTime = _G.GetTime
local UnitGUID = _G.UnitGUID
local UnitExists = _G.UnitExists
local UnitCanAttack = _G.UnitCanAttack
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local UnitAttackSpeed = _G.UnitAttackSpeed
local UnitRangedDamage = _G.UnitRangedDamage
local C_CombatLog = _G.C_CombatLog
local C_Spell = _G.C_Spell
local Enum = _G.Enum
local issecretvalue = _G.issecretvalue or (common and common.issecretvalue)
local select, pairs, ipairs, tonumber = select, pairs, ipairs, tonumber

local SWING_MAIN_HAND = (Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.MainHand) or 0
local SWING_OFF_HAND  = (Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.OffHand)  or 1
local SWING_RANGED    = (Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.Ranged)   or 2

local function GetCurrentCombatLogEventInfo()
    if C_CombatLog and C_CombatLog.GetCurrentEventInfo then
        return C_CombatLog.GetCurrentEventInfo()
    elseif _G.CombatLogGetCurrentEventInfo then
        return _G.CombatLogGetCurrentEventInfo()
    end
end

-- ─── 1. Spell Tables (On-Next-Swing, Cast-Reset, Ranged, & Range Check) ─────

-- On-next-swing melee spells that replace the main-hand auto-attack on SPELL_DAMAGE / SPELL_MISSED
local ON_NEXT_SWING_SPELL_IDS = {
    -- Heroic Strike (Ranks 1-9 + AQ)
    [78] = true, [284] = true, [285] = true, [1608] = true, [11564] = true,
    [11565] = true, [11566] = true, [11567] = true, [25286] = true,
    -- Cleave (Ranks 1-5)
    [845] = true, [7369] = true, [11608] = true, [11609] = true, [20569] = true,
    -- Maul (Ranks 1-7)
    [6807] = true, [6808] = true, [6809] = true, [8972] = true, [9745] = true,
    [9880] = true, [9881] = true,
    -- Raptor Strike (Ranks 1-8)
    [2973] = true, [14260] = true, [14261] = true, [14262] = true, [14263] = true,
    [14264] = true, [14265] = true, [14266] = true,
}

-- Cast-time melee spells that reset the main-hand swing timer on UNIT_SPELLCAST_SUCCEEDED
local CAST_RESET_MELEE_SPELL_IDS = {
    -- Slam (Ranks 1-4)
    [1464] = true, [8820] = true, [11604] = true, [11605] = true,
}

-- Ranged auto-shot / wand / throw spells on UNIT_SPELLCAST_SUCCEEDED
local RANGED_SWING_SPELL_IDS = {
    [75]   = true, -- Auto Shot
    [5019] = true, -- Shoot (Wand)
    [3018] = true, -- Shoot (Bow / Gun / Crossbow)
    [2764] = true, -- Throw
}

local onNextSwingNames = {}
local castResetMeleeNames = {}
local rangedSwingNames = {}
local spellNamesBuilt = false

local function GetSpellNameSafe(spellID)
    if common and common.get_spell_name then
        local n = common.get_spell_name(spellID)
        if n and n ~= "" then return n end
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info and info.name and info.name ~= "" then return info.name end
    end
    if _G.GetSpellInfo then
        local n = _G.GetSpellInfo(spellID)
        if n and n ~= "" then return n end
    end
    return nil
end

local function EnsureSpellNameLookups()
    if spellNamesBuilt then return end
    for _, baseID in ipairs({ 78, 845, 6807, 2973 }) do
        local name = GetSpellNameSafe(baseID)
        if name then onNextSwingNames[name] = true end
    end
    local slamName = GetSpellNameSafe(1464)
    if slamName then castResetMeleeNames[slamName] = true end

    for _, baseID in ipairs({ 75, 5019, 3018, 2764 }) do
        local name = GetSpellNameSafe(baseID)
        if name then rangedSwingNames[name] = true end
    end
    if next(onNextSwingNames) ~= nil then
        spellNamesBuilt = true
    end
end

-- ─── 2. Classic Range Check Provider (sfui.swing._classicTimer) ─────────────

local MELEE_RANGE_CANDIDATE_SPELLS = {
    78,    -- Heroic Strike (Warrior)
    1715,  -- Hamstring (Warrior)
    1752,  -- Sinister Strike (Rogue)
    2973,  -- Raptor Strike (Hunter)
    2974,  -- Wing Clip (Hunter)
    6807,  -- Maul (Druid Bear)
    1082,  -- Claw (Druid Cat)
    17364, -- Stormstrike (Shaman)
    6603,  -- Attack
}

local RANGED_RANGE_CANDIDATE_SPELLS = {
    75,   -- Auto Shot
    5019, -- Shoot (Wand)
    3018, -- Shoot (Bow/Gun/Crossbow)
    2764, -- Throw
}

local activeRangeChecks = {
    [SWING_MAIN_HAND] = false,
    [SWING_OFF_HAND]  = false,
    [SWING_RANGED]    = false,
}
local lastRangeState = {
    [SWING_MAIN_HAND] = nil,
    [SWING_OFF_HAND]  = nil,
    [SWING_RANGED]    = nil,
}

local function QuerySpellRange(spellID)
    if C_Spell and C_Spell.IsSpellInRange then
        local res = C_Spell.IsSpellInRange(spellID, "target")
        if res ~= nil then return res == true end
        local name = GetSpellNameSafe(spellID)
        if name then
            res = C_Spell.IsSpellInRange(name, "target")
            if res ~= nil then return res == true end
        end
    elseif _G.IsSpellInRange then
        local name = GetSpellNameSafe(spellID)
        if name then
            local res = _G.IsSpellInRange(name, "target")
            if res ~= nil then return res == 1 or res == true end
        end
    end
    return nil
end

local function ClassicIsTargetWithinSwingRange(swingType)
    if not UnitExists or not UnitExists("target") then return true end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("target") then return true end
    if UnitCanAttack and not UnitCanAttack("player", "target") then return true end

    local list = (swingType == SWING_RANGED) and RANGED_RANGE_CANDIDATE_SPELLS or MELEE_RANGE_CANDIDATE_SPELLS
    for i = 1, #list do
        local inRange = QuerySpellRange(list[i])
        if inRange ~= nil then
            return inRange
        end
    end

    return true
end

local rangeTickerActive = false
local function PollClassicSwingRanges()
    local anyActive = false
    for sType, enabled in pairs(activeRangeChecks) do
        if enabled then
            anyActive = true
            local inRange = ClassicIsTargetWithinSwingRange(sType)
            if lastRangeState[sType] ~= inRange then
                lastRangeState[sType] = inRange
                if sfui.swing and sfui.swing.OnSwingEvent then
                    sfui.swing.OnSwingEvent("PLAYER_SWING_RANGE_UPDATE", sType, inRange, true)
                end
            end
        else
            lastRangeState[sType] = nil
        end
    end

    if not anyActive and rangeTickerActive and sfui.events and sfui.events.UnregisterUpdate then
        sfui.events.UnregisterUpdate("ClassicSwingRange")
        rangeTickerActive = false
    end
end

local function ClassicEnableRangeCheck(swingType, shouldCheck)
    activeRangeChecks[swingType] = shouldCheck and true or false
    if not shouldCheck then
        lastRangeState[swingType] = nil
    end

    local anyActive = activeRangeChecks[SWING_MAIN_HAND] or activeRangeChecks[SWING_OFF_HAND] or activeRangeChecks[SWING_RANGED]
    if anyActive and not rangeTickerActive and sfui.events and sfui.events.RegisterUpdate then
        rangeTickerActive = true
        sfui.events.RegisterUpdate("ClassicSwingRange", 0.10, PollClassicSwingRanges)
    elseif not anyActive and rangeTickerActive and sfui.events and sfui.events.UnregisterUpdate then
        sfui.events.UnregisterUpdate("ClassicSwingRange")
        rangeTickerActive = false
    end
end

sfui.swing._classicTimer = {
    EnableRangeCheck = ClassicEnableRangeCheck,
    IsTargetWithinSwingRange = ClassicIsTargetWithinSwingRange,
}

-- ─── 3. Classic Swing Timer Engine (Combat Log, Casts, Parry Haste, Speed) ──

local playerGUID = nil
local lastMainHandSpeed = nil
local lastOffHandSpeed  = nil
local lastRangedSpeed   = nil
local lastRangedTriggerTime = 0

local function GetPlayerGUID()
    if not playerGUID and UnitGUID then
        playerGUID = UnitGUID("player")
    end
    return playerGUID
end

local function GetMainAndOffHandSpeeds()
    if not UnitAttackSpeed then return nil, nil end
    local mh, oh = UnitAttackSpeed("player")
    if mh and mh > 0 then lastMainHandSpeed = mh end
    if oh and oh > 0 then lastOffHandSpeed = oh else lastOffHandSpeed = nil end
    return mh or lastMainHandSpeed, oh
end

local function GetRangedWeaponSpeed()
    if not UnitRangedDamage then return lastRangedSpeed end
    local rSpeed = UnitRangedDamage("player")
    if rSpeed and rSpeed > 0 then
        lastRangedSpeed = rSpeed
    end
    return rSpeed or lastRangedSpeed
end

local function TriggerSwing(swingType, duration)
    if not duration or duration <= 0 then return end
    if sfui.swing and sfui.swing.OnSwingEvent then
        sfui.swing.OnSwingEvent("PLAYER_SWING", duration, swingType)
    end
end

local function ApplyParryHaste()
    local bars = sfui.swing and sfui.swing._bars
    local mhBar = bars and bars[SWING_MAIN_HAND]
    if not mhBar or not mhBar.endTime or not mhBar.duration or mhBar.duration <= 0 then
        return
    end

    local now = GetTime()
    local dur = mhBar.duration
    local remaining = mhBar.endTime - now
    if remaining <= 0 then return end

    local pct = remaining / dur
    if pct > 0.60 then
        mhBar.endTime = now + (remaining - 0.40 * dur)
    elseif pct > 0.20 then
        mhBar.endTime = now + (0.20 * dur)
    end
end

local function RescaleActiveBarSpeed(swingType, newSpeed)
    if not newSpeed or newSpeed <= 0 then return end
    local bars = sfui.swing and sfui.swing._bars
    local bar = bars and bars[swingType]
    if not bar or not bar.endTime or not bar.duration or bar.duration <= 0 then
        return
    end
    if bar.duration == newSpeed then return end

    local now = GetTime()
    local remaining = bar.endTime - now
    if remaining > 0 then
        local ratio = newSpeed / bar.duration
        bar.duration = newSpeed
        bar.endTime = now + (remaining * ratio)
    end
end

local function OnClassicCombatLogEvent()
    local pGUID = GetPlayerGUID()
    if not pGUID then return end

    local _, subevent, _, sourceGUID, _, _, _, destGUID = GetCurrentCombatLogEventInfo()
    if not subevent then return end

    if sourceGUID == pGUID then
        if subevent == "SWING_DAMAGE" then
            local isOffHand = select(21, GetCurrentCombatLogEventInfo())
            local mhSpeed, ohSpeed = GetMainAndOffHandSpeeds()
            if isOffHand and ohSpeed and ohSpeed > 0 then
                TriggerSwing(SWING_OFF_HAND, ohSpeed)
            else
                TriggerSwing(SWING_MAIN_HAND, mhSpeed)
            end
        elseif subevent == "SWING_MISSED" then
            local _, isOffHand = select(12, GetCurrentCombatLogEventInfo())
            local mhSpeed, ohSpeed = GetMainAndOffHandSpeeds()
            if isOffHand and ohSpeed and ohSpeed > 0 then
                TriggerSwing(SWING_OFF_HAND, ohSpeed)
            else
                TriggerSwing(SWING_MAIN_HAND, mhSpeed)
            end
        elseif subevent == "SPELL_DAMAGE" or subevent == "SPELL_MISSED" then
            EnsureSpellNameLookups()
            local spellID, spellName = select(12, GetCurrentCombatLogEventInfo())
            if (spellID and ON_NEXT_SWING_SPELL_IDS[spellID]) or (spellName and onNextSwingNames[spellName]) then
                local mhSpeed = GetMainAndOffHandSpeeds()
                TriggerSwing(SWING_MAIN_HAND, mhSpeed)
            end
        elseif subevent == "SPELL_EXTRA_ATTACKS" then
            local mhSpeed = GetMainAndOffHandSpeeds()
            TriggerSwing(SWING_MAIN_HAND, mhSpeed)
        elseif subevent == "RANGE_DAMAGE" or subevent == "RANGE_MISSED" then
            local now = GetTime()
            if (now - lastRangedTriggerTime) > 0.25 then
                lastRangedTriggerTime = now
                TriggerSwing(SWING_RANGED, GetRangedWeaponSpeed())
            end
        end
    elseif destGUID == pGUID and subevent == "SWING_MISSED" then
        local missType = select(12, GetCurrentCombatLogEventInfo())
        if missType == "PARRY" then
            ApplyParryHaste()
        end
    end
end

local function OnClassicSpellcastSucceeded(_, unitTarget, _, spellID)
    if issecretvalue and (issecretvalue(unitTarget) or issecretvalue(spellID)) then return end
    if unitTarget and unitTarget ~= "player" then return end
    local sid = tonumber(spellID)
    if not sid then return end

    EnsureSpellNameLookups()
    local spellName = GetSpellNameSafe(sid)

    if RANGED_SWING_SPELL_IDS[sid] or (spellName and rangedSwingNames[spellName]) then
        lastRangedTriggerTime = GetTime()
        TriggerSwing(SWING_RANGED, GetRangedWeaponSpeed())
    elseif CAST_RESET_MELEE_SPELL_IDS[sid] or (spellName and castResetMeleeNames[spellName]) then
        local mhSpeed = GetMainAndOffHandSpeeds()
        TriggerSwing(SWING_MAIN_HAND, mhSpeed)
    end
end

local function OnClassicAttackSpeedChanged()
    local mhSpeed, ohSpeed = GetMainAndOffHandSpeeds()
    local rSpeed = GetRangedWeaponSpeed()
    RescaleActiveBarSpeed(SWING_MAIN_HAND, mhSpeed)
    if ohSpeed then
        RescaleActiveBarSpeed(SWING_OFF_HAND, ohSpeed)
    end
    if rSpeed then
        RescaleActiveBarSpeed(SWING_RANGED, rSpeed)
    end
end

if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", OnClassicCombatLogEvent)
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        playerGUID = UnitGUID and UnitGUID("player") or nil
        EnsureSpellNameLookups()
        GetMainAndOffHandSpeeds()
        GetRangedWeaponSpeed()
    end)
    if sfui.events.RegisterUnitEvent then
        sfui.events.RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", OnClassicSpellcastSucceeded)
        sfui.events.RegisterUnitEvent("UNIT_ATTACK_SPEED", "player", OnClassicAttackSpeedChanged)
    else
        sfui.events.RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", OnClassicSpellcastSucceeded)
        sfui.events.RegisterEvent("UNIT_ATTACK_SPEED", OnClassicAttackSpeedChanged)
    end
end

