local addonName, addon = ...
---@diagnostic disable: undefined-global
-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/tracking/tracking_classic.lua
--  Classic Era Tracking Driver for Tracked Bars & Tracked Icons
--  Loaded only on [AllowLoadGameType classic].
-- ══════════════════════════════════════════════════════════════════════════════

if not (sfui and sfui.isEra) then return end

sfui = sfui or {}
sfui.tracking = sfui.tracking or {}
sfui.trackedbars = sfui.trackedbars or {}
sfui.trackedicons = sfui.trackedicons or {}

local common = sfui.common
local cfg = sfui.config
local C_Spell = _G.C_Spell
local C_UnitAuras = _G.C_UnitAuras
local GetTime = _G.GetTime
local GetTotemInfo = _G.GetTotemInfo
local issecretvalue = _G.issecretvalue or (common and common.issecretvalue)
local UnitExists = _G.UnitExists
local UnitHasVehicleUI = _G.UnitHasVehicleUI
local UnitInVehicle = _G.UnitInVehicle
local wipe = _G.wipe or table.wipe
local pairs, type, tonumber, tostring = pairs, type, tonumber, tostring
local math, string = math, string

-- ────────────────────────────────────────────────────────────────────────────
-- 1. Classic Multi-Rank Spell & Aura Resolution
-- ────────────────────────────────────────────────────────────────────────────

local highestRankCache = {}
local scratchTotemAura = {}
local activeClassicBarIDs = {}

--- Resolves a spellID to the highest known rank's spellID in the player's spellbook.
--- In Classic, each rank of a spell has a distinct spellID; querying by spell name
--- returns the highest rank currently learned by the player.
--- @param spellID number|nil
--- @return number|nil
function sfui.tracking.ResolveClassicSpellID(spellID)
    local sid = tonumber(spellID)
    if not sid or sid <= 0 then return spellID end

    local cached = highestRankCache[sid]
    if cached then return cached end

    local name = common.get_spell_name and common.get_spell_name(sid)
    if not name or name == "" then
        return sid
    end

    local resolvedID = nil
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(name)
        if info and info.spellID and info.spellID > 0 then
            resolvedID = info.spellID
        end
    end
    if not resolvedID and _G.GetSpellInfo then
        local _, _, _, _, _, _, rID = _G.GetSpellInfo(name)
        if rID and rID > 0 then
            resolvedID = rID
        end
    end

    if resolvedID and resolvedID > 0 then
        highestRankCache[sid] = resolvedID
        return resolvedID
    end

    highestRankCache[sid] = sid
    return sid
end

function sfui.tracking.InvalidateClassicSpellCache()
    wipe(highestRankCache)
end

local function find_unit_aura(unit, filter, spellID, altSpellID, spellName)
    if not unit or (unit ~= "player" and (not UnitExists or not UnitExists(unit))) then
        return nil
    end

    if unit == "player" and filter == "HELPFUL" and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        if spellID then
            local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
            if aura then return aura end
        end
        if altSpellID and altSpellID ~= spellID then
            local aura = C_UnitAuras.GetPlayerAuraBySpellID(altSpellID)
            if aura then return aura end
        end
    end

    if _G.C_Secrets and _G.C_Secrets.ShouldAurasBeSecret and _G.C_Secrets.ShouldAurasBeSecret() then
        return nil
    end

    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local fallbackAura = nil
        for i = 1, 40 do
            local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
            if not aura or (issecretvalue and issecretvalue(aura)) then break end
            local sID = aura.spellId
            local aName = aura.name
            if not (issecretvalue and (issecretvalue(sID) or issecretvalue(aName))) then
                if (spellID and sID == spellID) or (altSpellID and sID == altSpellID) or (spellName and aName == spellName) then
                    local srcUnit = aura.sourceUnit
                    local isFromPlayer = aura.isFromPlayerOrPlayerPet
                    local fromMe = (not (issecretvalue and issecretvalue(srcUnit)) and srcUnit == "player")
                        or (not (issecretvalue and issecretvalue(isFromPlayer)) and isFromPlayer == true)
                    if unit ~= "target" or fromMe then
                        return aura
                    elseif not fallbackAura then
                        fallbackAura = aura
                    end
                end
            end
        end
        if fallbackAura then return fallbackAura end
    elseif _G.UnitAura then
        local fallbackAura = nil
        for i = 1, 40 do
            local name, icon, count, dispelType, duration, expirationTime, source, _, _, sID = _G.UnitAura(unit, i, filter)
            if issecretvalue and (issecretvalue(name) or issecretvalue(sID)) then break end
            if not name then break end
            if (spellID and sID == spellID) or (altSpellID and sID == altSpellID) or (spellName and name == spellName) then
                local auraTable = {
                    name = name,
                    icon = icon,
                    applications = (not (issecretvalue and issecretvalue(count)) and count) or 0,
                    dispelName = dispelType,
                    duration = (not (issecretvalue and issecretvalue(duration)) and duration) or 0,
                    expirationTime = (not (issecretvalue and issecretvalue(expirationTime)) and expirationTime) or 0,
                    sourceUnit = source,
                    spellId = sID,
                }
                if unit ~= "target" or (not (issecretvalue and issecretvalue(source)) and source == "player") then
                    return auraTable
                elseif not fallbackAura then
                    fallbackAura = auraTable
                end
            end
        end
        if fallbackAura then return fallbackAura end
    end

    return nil
end

local function find_totem_aura(spellName)
    if not spellName or (issecretvalue and issecretvalue(spellName)) or spellName == "" then return nil end
    if GetTotemInfo then
        for slot = 1, 4 do
            local haveTotem, totemName, startTime, duration, icon = GetTotemInfo(slot)
            if not (issecretvalue and (issecretvalue(haveTotem) or issecretvalue(totemName) or issecretvalue(startTime) or issecretvalue(duration) or issecretvalue(icon))) then
                if haveTotem and totemName and totemName ~= "" and duration and duration > 0 then
                    if totemName == spellName or string.find(totemName, "^" .. spellName, 1, false) then
                        local now = GetTime()
                        local exp = (startTime or 0) + duration
                        if exp > now then
                            scratchTotemAura.name = spellName
                            scratchTotemAura.icon = icon
                            scratchTotemAura.duration = duration
                            scratchTotemAura.expirationTime = exp
                            scratchTotemAura.applications = 1
                            return scratchTotemAura
                        end
                    end
                end
            end
        end
    end
    if sfui.totembar and sfui.totembar.GetActiveTotemByName then
        local fallback = sfui.totembar.GetActiveTotemByName(spellName)
        if fallback then
            scratchTotemAura.name = fallback.name
            scratchTotemAura.icon = fallback.icon
            scratchTotemAura.duration = fallback.duration
            scratchTotemAura.expirationTime = fallback.expirationTime
            scratchTotemAura.applications = fallback.applications or 1
            return scratchTotemAura
        end
    end
    return nil
end

--- Finds an active Classic aura matching spellID or any rank of its spellName.
--- Checks player HELPFUL auras first; if checkTargetAndTotems is true, also checks
--- target HARMFUL debuffs (preferring player-cast) and active Shaman totems.
--- @param spellID number|nil
--- @param checkTargetAndTotems boolean|nil
--- @return table|nil
function sfui.tracking.FindClassicAura(spellID, checkTargetAndTotems)
    local sid = tonumber(spellID)
    if not sid or sid <= 0 then return nil end

    local resolvedID = sfui.tracking.ResolveClassicSpellID(sid) or sid
    local spellName = common.get_spell_name and (common.get_spell_name(resolvedID) or common.get_spell_name(sid))

    -- 1. Player Buff (HELPFUL)
    local aura = find_unit_aura("player", "HELPFUL", resolvedID, sid, spellName)
    if aura then return aura end

    if checkTargetAndTotems then
        -- 2. Target Debuff (HARMFUL, preferring player-cast with fallback for shared debuffs like Sunder Armor)
        aura = find_unit_aura("target", "HARMFUL", resolvedID, sid, spellName)
        if aura then return aura end

        -- 3. Active Shaman Totem
        aura = find_totem_aura(spellName)
        if aura then return aura end
    end

    return nil
end

-- ────────────────────────────────────────────────────────────────────────────
-- 2. Classic Tracked Bars Engine
-- ────────────────────────────────────────────────────────────────────────────

local CLASSIC_PANDEMIC_GLOW_OPTS = {
    glowType = "pixel",
    glowColor = { 1, 0.85, 0.2, 1 },
    glowThickness = 2,
    glowLines = 6,
    glowSpeed = 0.35,
}
local DEFAULT_PANDEMIC_COLOR = { 1, 0, 1, 1 }
local _emptyTable = {}

local function format_bar_duration(remaining)
    if not remaining or remaining <= 0 then return "" end
    if remaining < 10 then
        return string.format("%.1f", remaining)
    elseif remaining < 60 then
        return string.format("%d", math.ceil(remaining))
    else
        return string.format("%dm", math.ceil(remaining / 60))
    end
end

local function resolve_classic_text_flags(config)
    if sfui.trackedbars.ResolveTextFlags then
        return sfui.trackedbars.ResolveTextFlags(config)
    end
    local db = (SfuiDB and SfuiDB.trackedBars) or _emptyTable
    local isStackMode = (config and config.stackMode) or false
    local isAttached = (config and config.stackAboveHealth) or false
    local showStacksText = (config and config.showStacksText) or false
    local showDurationEnabled = not (db.showDuration == false or (config and config.showDuration == false))
    local showNameCfg = (config and config.showName ~= nil) and config.showName or db.showName
    local showNameEnabled = (showNameCfg ~= false)
    local showStacks = (config and config.showStacks ~= nil) and config.showStacks or (db.showStacks == true)
    local wantCenteredStacks = isStackMode or showStacksText
    local isTimerAndStacks = wantCenteredStacks and showDurationEnabled
    return isStackMode, isAttached, showStacksText, showDurationEnabled, showNameEnabled, showStacks, wantCenteredStacks, isTimerAndStacks
end

local function SyncClassicBarData(myBar, config, isStackMode, id, resolvedID, aura)
    myBar.spellID = resolvedID or id
    myBar._config = config
    myBar._classicAura = aura

    local _, isAttached, showStacksText, showDurationEnabled, showNameEnabled, showStacks, wantCenteredStacks, isTimerAndStacks = resolve_classic_text_flags(config)

    local spellName = (aura and aura.name) or (common.get_spell_name and common.get_spell_name(myBar.spellID)) or ("Spell " .. tostring(id))
    local spellIcon = (aura and aura.icon) or (common.get_spell_icon and common.get_spell_icon(myBar.spellID)) or 134400

    myBar.icon:SetTexture(spellIcon)
    myBar.icon:SetDesaturated(aura == nil)

    local needStacks = isStackMode or showStacksText or (showStacks and not isAttached)
    local maxStacks = isStackMode and ((sfui.trackedbars.GetMaxStacks and sfui.trackedbars.GetMaxStacks(id, config, myBar.spellID)) or 5) or (myBar._maxStacks or 5)
    myBar._maxStacks = maxStacks

    local currentStacks = 0
    if needStacks then
        if aura then
            local apps = tonumber(aura.applications) or 0
            currentStacks = (apps > 0) and apps or 1
        elseif C_Spell and C_Spell.GetSpellCharges and myBar.spellID and not (issecretvalue and issecretvalue(myBar.spellID)) then
            local chargeInfo = C_Spell.GetSpellCharges(myBar.spellID)
            if chargeInfo and chargeInfo.maxCharges and not (issecretvalue and issecretvalue(chargeInfo.maxCharges)) and chargeInfo.maxCharges > 1 then
                currentStacks = tonumber(chargeInfo.currentCharges) or 0
            end
        end
    end
    myBar.currentStacks = currentStacks

    if isTimerAndStacks then
        myBar.name:Show()
        myBar.time:Show()
    else
        if showNameEnabled then
            myBar.name:Show()
        else
            myBar.name:Hide()
        end

        if not showDurationEnabled and not wantCenteredStacks then
            myBar.time:Hide()
        else
            myBar.time:Show()
        end
    end

    if not showStacks or isStackMode or isAttached or showStacksText or currentStacks <= 1 then
        myBar.count:Hide()
    else
        myBar.count:SetText(tostring(currentStacks))
        myBar.count:Show()
    end

    if not isTimerAndStacks then
        local displayName = (config and config.name) or spellName
        common.SafeSetText(myBar.name, displayName)
    end

    local duration = (aura and tonumber(aura.duration)) or 0
    local expirationTime = (aura and tonumber(aura.expirationTime)) or 0
    local remaining = (duration > 0 and expirationTime > 0) and math.max(0, expirationTime - GetTime()) or 0
    local durText = (duration > 0) and format_bar_duration(remaining) or ""

    if isStackMode then
        local maxVal = (type(maxStacks) == "number" and maxStacks > 0) and maxStacks or 5
        myBar.status:SetMinMaxValues(0, maxVal)
        myBar.status:SetValue(math.min(maxVal, math.max(0, currentStacks)))
    else
        if duration > 0 and remaining > 0 then
            myBar.status:SetMinMaxValues(0, duration)
            myBar.status:SetValue(remaining)
        elseif aura then
            -- Aura with no duration (permanent buff like Inner Fire / Aspect / Stance)
            myBar.status:SetMinMaxValues(0, 1)
            myBar.status:SetValue(1)
        else
            myBar.status:SetMinMaxValues(0, 1)
            myBar.status:SetValue(0)
        end
    end

    if isTimerAndStacks then
        local stackStr = currentStacks > 0 and tostring(currentStacks) or ""
        myBar._lastStackNameText = stackStr
        myBar.name:SetText(stackStr)
        myBar._lastDurationText = durText
        myBar.time:SetText(durText)
    elseif showStacksText and not showDurationEnabled then
        local stackStr = currentStacks > 0 and tostring(currentStacks) or ""
        myBar._lastStackTimeText = stackStr
        myBar.time:SetText(stackStr)
    else
        myBar._lastDurationText = durText
        myBar.time:SetText(durText)
    end
end

function sfui.trackedbars.ClassicSync()
    local bars = sfui.trackedbars._bars
    if not bars then return end

    wipe(activeClassicBarIDs)
    local layoutNeeded = false

    local mustHide = false
    local db = (SfuiDB and SfuiDB.trackedBars) or (cfg and cfg.trackedBars and cfg.trackedBars.defaults) or _emptyTable
    local inCombat = common.is_in_combat()
    local isMoving = (sfui.movers and sfui.movers.isUnlocked) == true

    if not isMoving then
        if db.hideOOC and not inCombat then
            mustHide = true
        elseif not inCombat then
            if db.hideMounted and common.is_mounted_or_travel_form() then
                mustHide = true
            elseif db.hideInVehicle and ((UnitHasVehicleUI and UnitHasVehicleUI("player")) or (UnitInVehicle and UnitInVehicle("player"))) then
                mustHide = true
            end
        end
    end

    if mustHide then
        for _, bar in pairs(bars) do
            if bar:IsShown() then
                bar:Hide()
                layoutNeeded = true
            end
        end
        if layoutNeeded and sfui.trackedbars.ForceLayoutUpdate then
            sfui.trackedbars.ForceLayoutUpdate()
        end
        return
    end

    local specBars = common.get_tracked_bars and common.get_tracked_bars()
    if specBars then
        for id, entryCfg in pairs(specBars) do
            local numID = tonumber(id)
            if numID and entryCfg then
                activeClassicBarIDs[numID] = true

                if not bars[numID] and sfui.trackedbars.AcquireBar then
                    bars[numID] = sfui.trackedbars.AcquireBar(numID)
                    layoutNeeded = true
                end

                local myBar = bars[numID]
                if myBar then
                    local config = sfui.trackedbars.GetConfig and sfui.trackedbars.GetConfig(numID)
                    local isStackMode = (config and config.stackMode) or false
                    local resolvedID = sfui.tracking.ResolveClassicSpellID(numID) or numID
                    local aura = sfui.tracking.FindClassicAura(resolvedID, true)

                    SyncClassicBarData(myBar, config, isStackMode, numID, resolvedID, aura)

                    local hideInactive = (db.hideInactive ~= false)
                    local isStackModeWithStacks = isStackMode and (myBar.currentStacks and myBar.currentStacks > 0)
                    local shouldShow = isStackModeWithStacks or (not hideInactive) or (aura ~= nil)

                    if shouldShow then
                        if not myBar:IsShown() then
                            myBar:Show()
                            layoutNeeded = true
                        end
                    else
                        if myBar:IsShown() then
                            myBar:Hide()
                            layoutNeeded = true
                        end
                    end
                end
            end
        end
    end

    for id in pairs(bars) do
        if not activeClassicBarIDs[id] then
            if sfui.trackedbars.RemoveBar then
                sfui.trackedbars.RemoveBar(id, true)
                layoutNeeded = true
            end
        end
    end

    if layoutNeeded and sfui.trackedbars.ForceLayoutUpdate then
        sfui.trackedbars.ForceLayoutUpdate()
    end
end

function sfui.trackedbars.ClassicUpdateState()
    local bars = sfui.trackedbars._bars
    if not bars then return end

    local tBarsCfg = (sfui.config and sfui.config.trackedBars) or _emptyTable
    local now = GetTime()

    for id, myBar in pairs(bars) do
        if myBar:IsShown() then
            local config = myBar._config or (sfui.trackedbars.GetConfig and sfui.trackedbars.GetConfig(id))
            local isStackMode, _, showStacksText, showDurationEnabled, _, _, _, isTimerAndStacks = resolve_classic_text_flags(config)
            local aura = myBar._classicAura
            local duration = (aura and tonumber(aura.duration)) or 0
            local expirationTime = (aura and tonumber(aura.expirationTime)) or 0
            local remaining = 0

            if duration > 0 and expirationTime > 0 then
                remaining = math.max(0, expirationTime - now)
                if remaining <= 0 then
                    sfui.trackedbars.isDirty = true
                end
            end

            if not isStackMode and duration > 0 then
                myBar.status:SetMinMaxValues(0, duration)
                myBar.status:SetValue(remaining)
            end

            if isTimerAndStacks then
                local cs = tonumber(myBar.currentStacks) or 0
                local stackStr = cs > 0 and tostring(cs) or ""
                if stackStr ~= myBar._lastStackNameText then
                    myBar._lastStackNameText = stackStr
                    myBar.name:SetText(stackStr)
                end
            end

            if showStacksText and not showDurationEnabled then
                local cs = tonumber(myBar.currentStacks) or 0
                local stackStr = cs > 0 and tostring(cs) or ""
                if stackStr ~= myBar._lastStackTimeText then
                    myBar._lastStackTimeText = stackStr
                    myBar.time:SetText(stackStr)
                end
            elseif showDurationEnabled then
                local durText = (duration > 0) and format_bar_duration(remaining) or ""
                if durText ~= myBar._lastDurationText then
                    myBar._lastDurationText = durText
                    myBar.time:SetText(durText)
                end
            end

            -- Classic Pandemic Window (<= 30% remaining on timed buffs/debuffs)
            local inPandemic = (duration > 0 and remaining > 0 and (remaining / duration) <= 0.30)
            local wasPandemic = myBar._inPandemic == true
            local showGlow = (tBarsCfg.pandemicGlow ~= false) and (not config or config.pandemicGlow ~= false)

            if inPandemic and showGlow then
                if not wasPandemic and sfui.glows and sfui.glows.start_glow then
                    sfui.glows.start_glow(myBar.iconFrame, CLASSIC_PANDEMIC_GLOW_OPTS)
                end
            elseif wasPandemic and not inPandemic then
                if sfui.glows and sfui.glows.stop_glow then
                    sfui.glows.stop_glow(myBar.iconFrame)
                end
            end

            local shouldRecolor = (config and config.pandemicEnabled ~= nil) and config.pandemicEnabled or (tBarsCfg.pandemicRecolor ~= false)
            if shouldRecolor then
                if inPandemic and not wasPandemic then
                    local pColor = (config and config.pandemicColor) or tBarsCfg.pandemicColor or DEFAULT_PANDEMIC_COLOR
                    myBar.status:SetStatusBarColor(common.unpack_color(pColor))
                elseif wasPandemic and not inPandemic then
                    local defColor = (sfui.trackedbars.GetBarNormalColor and sfui.trackedbars.GetBarNormalColor(config)) or sfui.config.colors.purple
                    myBar.status:SetStatusBarColor(common.unpack_color(defColor))
                end
            end
            myBar._inPandemic = inPandemic
        end
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- 3. Classic Events (Spell Rank Learning, Target Debuffs, Shaman Totems)
-- ────────────────────────────────────────────────────────────────────────────

if sfui.events and sfui.events.RegisterEvent then
    local function on_spells_updated()
        sfui.tracking.InvalidateClassicSpellCache()
        if sfui.trackedicons and sfui.trackedicons.MarkDirty then
            sfui.trackedicons.MarkDirty(true)
        end
        sfui.trackedbars.isDirty = true
    end

    sfui.events.RegisterEvent("SPELLS_CHANGED", on_spells_updated)
    sfui.events.RegisterEvent("LEARNED_SPELL_IN_TAB", on_spells_updated)

    sfui.events.RegisterEvent("PLAYER_TARGET_CHANGED", function()
        sfui.trackedbars.isDirty = true
    end)

    sfui.events.RegisterEvent("PLAYER_TOTEM_UPDATE", function()
        sfui.trackedbars.isDirty = true
    end)

    if sfui.events.RegisterUnitEvent then
        sfui.events.RegisterUnitEvent("UNIT_AURA", "target", function()
            sfui.trackedbars.isDirty = true
        end)
    end
end

