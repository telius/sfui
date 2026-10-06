local addonName, addon = ...
sfui = sfui or {}
sfui.buffs = sfui.buffs or {}
sfui.buffs.scan = {}

local _G = _G
local string_lower = string.lower
local wipe = _G.wipe
local UnitExists = _G.UnitExists
local UnitIsDead = _G.UnitIsDead
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local IsMounted = _G.IsMounted
local UnitOnTaxi = _G.UnitOnTaxi
local GetWeaponEnchantInfo = _G.GetWeaponEnchantInfo
local GetInventoryItemLink = _G.GetInventoryItemLink
local GetShapeshiftForm = _G.GetShapeshiftForm
local GetTime = _G.GetTime
local GetSpellInfo = _G.GetSpellInfo
local C_Timer = _G.C_Timer
local C_UnitAuras = _G.C_UnitAuras
local AuraUtil = _G.AuraUtil

local data = sfui.buffs.data
local entries = nil

-- Caches & Table Pools
local knownCache = {}
local activeResults = {}
local auraRecordPool = {}
local activeAuraList = {}
local activeAurasBySpellID = {}
local activeAurasByName = {}
local dirty = true
local throttleTimer = nil

local function RefreshSpellKnowledge()
    entries = (data.GetAllEntries and data.GetAllEntries()) or data.GetClassEntries()
    for i = 1, #entries do
        local entry = entries[i]
        local known = false
        if entry.isConsumable then
            known = true
        elseif entry.isKnownCheck then
            known = entry.isKnownCheck(entry)
        elseif entry.spellIDs then
            known = data.IsAnySpellKnown(entry.spellIDs)
        else
            known = true
        end
        knownCache[entry.key] = known

        -- Pre-compute lowercased name lookups once to eliminate string allocations during scan loops
        if not entry._cachedLookups then
            entry._cachedLookups = true
            if entry.name then
                entry.lowerName = string_lower(entry.name)
            end
            if entry.names then
                entry.lowerNames = {}
                for j = 1, #entry.names do
                    entry.lowerNames[j] = string_lower(entry.names[j])
                end
            end
            if entry.spellIDs and GetSpellInfo then
                entry.spellbookNames = {}
                for j = 1, #entry.spellIDs do
                    local sName = GetSpellInfo(entry.spellIDs[j])
                    if sName and sName ~= "" then
                        entry.spellbookNames[#entry.spellbookNames + 1] = string_lower(sName)
                    end
                end
            end
        end
    end
    dirty = true
end
sfui.buffs.scan.RefreshSpellKnowledge = RefreshSpellKnowledge

local function ReleasePlayerAuras()
    wipe(activeAurasBySpellID)
    wipe(activeAurasByName)
    for i = #activeAuraList, 1, -1 do
        local r = table.remove(activeAuraList, i)
        wipe(r)
        auraRecordPool[#auraRecordPool + 1] = r
    end
end

local function RecordActiveAura(name, spellId, duration, expirationTime, applications, icon)
    local r = table.remove(auraRecordPool) or {}
    r.name = name
    r.spellId = spellId
    r.duration = duration or 0
    r.expirationTime = expirationTime or 0
    r.applications = applications or 0
    r.icon = icon

    if spellId then
        activeAurasBySpellID[spellId] = r
    end
    if name then
        activeAurasByName[string_lower(name)] = r
    end
    activeAuraList[#activeAuraList + 1] = r
    return r
end

local function CollectPlayerAuras()
    ReleasePlayerAuras()

    if AuraUtil and AuraUtil.ForEachAura then
        AuraUtil.ForEachAura("player", "HELPFUL", nil, function(auraData)
            if auraData then
                RecordActiveAura(
                    auraData.name,
                    auraData.spellId,
                    auraData.duration,
                    auraData.expirationTime,
                    auraData.applications,
                    auraData.icon
                )
            end
        end, true)
    elseif C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not aura then break end
            RecordActiveAura(
                aura.name,
                aura.spellId,
                aura.duration,
                aura.expirationTime,
                aura.applications,
                aura.icon
            )
        end
    elseif _G.UnitAura then
        for i = 1, 40 do
            local name, icon, count, _, duration, expTime, _, _, _, sID = _G.UnitAura("player", i, "HELPFUL")
            if not name then break end
            RecordActiveAura(name, sID, duration, expTime, count, icon)
        end
    end
end

local function ScanPlayerAura(entry)
    local spellIDs = entry.spellIDs

    -- 1. Fast path: check C_UnitAuras.GetPlayerAuraBySpellID directly if available
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and spellIDs then
        for i = 1, #spellIDs do
            local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellIDs[i])
            if aura then
                return true, aura.duration or 0, aura.expirationTime or 0, aura.applications or 0, aura.icon
            end
        end
    end

    -- 2. O(1) Hash lookup by Spell ID
    if spellIDs then
        for i = 1, #spellIDs do
            local a = activeAurasBySpellID[spellIDs[i]]
            if a then
                return true, a.duration, a.expirationTime, a.applications, a.icon
            end
        end
    end

    -- 3. O(1) Hash lookup by Pre-lowercased configured names
    local lowerNames = entry.lowerNames
    if lowerNames then
        for i = 1, #lowerNames do
            local a = activeAurasByName[lowerNames[i]]
            if a then
                return true, a.duration, a.expirationTime, a.applications, a.icon
            end
        end
    end

    -- 4. O(1) Hash lookup by Pre-lowercased entry name
    if entry.lowerName then
        local a = activeAurasByName[entry.lowerName]
        if a then
            return true, a.duration, a.expirationTime, a.applications, a.icon
        end
    end

    -- 5. O(1) Hash lookup by Pre-lowercased spellbook names
    local spellbookNames = entry.spellbookNames
    if spellbookNames then
        for i = 1, #spellbookNames do
            local a = activeAurasByName[spellbookNames[i]]
            if a then
                return true, a.duration, a.expirationTime, a.applications, a.icon
            end
        end
    end

    -- 6. Fallback: AuraUtil.FindAuraByName / C_UnitAuras.GetAuraDataBySpellName
    local spellNames = entry.names
    if spellNames then
        for j = 1, #spellNames do
            local sName = spellNames[j]
            if AuraUtil and AuraUtil.FindAuraByName then
                local name, icon, count, _, duration, expTime = AuraUtil.FindAuraByName(sName, "player", "HELPFUL")
                if name then
                    return true, duration or 0, expTime or 0, count or 0, icon
                end
            elseif C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
                local aura = C_UnitAuras.GetAuraDataBySpellName("player", sName, "HELPFUL")
                if aura then
                    return true, aura.duration or 0, aura.expirationTime or 0, aura.applications or 0, aura.icon
                end
            end
        end
    end

    return false, 0, 0, 0, nil
end

local function ScanStance(entry)
    local form = GetShapeshiftForm and GetShapeshiftForm()
    if form and form > 0 then
        return true, 0, 0, 0, nil
    end
    return false, 0, 0, 0, nil
end

local function ScanWeaponEnchant(entry)
    if not GetWeaponEnchantInfo then
        return true, 0, 0, 0, nil
    end

    local slot = entry.slot or 16
    local itemLink = GetInventoryItemLink("player", slot)
    if not itemLink then
        -- No weapon equipped in this slot: nothing to remind
        return true, 0, 0, 0, nil
    end

    local hasMH, expMH, chargesMH, _, hasOH, expOH, chargesOH = GetWeaponEnchantInfo()
    if slot == 16 then
        if not hasMH then
            return false, 0, 0, 0, nil
        end
        local expSec = expMH and (expMH / 1000) or 0
        local now = GetTime()
        return true, 1800, now + expSec, chargesMH or 0, nil
    elseif slot == 17 then
        if not hasOH then
            return false, 0, 0, 0, nil
        end
        local expSec = expOH and (expOH / 1000) or 0
        local now = GetTime()
        return true, 1800, now + expSec, chargesOH or 0, nil
    end

    return true, 0, 0, 0, nil
end

local function ScanPet(entry)
    if IsMounted and IsMounted() then
        return true, 0, 0, 0, nil
    end
    if UnitOnTaxi and UnitOnTaxi("player") then
        return true, 0, 0, 0, nil
    end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
        return true, 0, 0, 0, nil
    end

    local hasPet = UnitExists("pet") and not (UnitIsDead and UnitIsDead("pet"))
    if hasPet then
        return true, 0, 0, 0, nil
    end
    return false, 0, 0, 0, nil
end

--- Scans all registered class buffs and populates activeResults
--- @return table array of scanned reminder records
function sfui.buffs.scan.RunScan()
    -- Bypass Blizzard API queries completely during combat or death
    if (_G.InCombatLockdown and _G.InCombatLockdown()) or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player")) then
        dirty = true
        return activeResults
    end

    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
        dirty = true
        return activeResults
    end

    if not entries then
        RefreshSpellKnowledge()
    end

    CollectPlayerAuras()

    local count = 0
    local now = GetTime()

    local cfg = SfuiDB and SfuiDB.buffReminders
    local disabledBuffs = cfg and cfg.disabledBuffs
    local allowExpiring = not cfg or (cfg.showExpiring ~= false)
    local thresholdLong = (cfg and cfg.thresholdLong) or 300
    local thresholdShort = (cfg and cfg.thresholdShort) or 60

    for i = 1, #entries do
        local entry = entries[i]
        local isKnown = knownCache[entry.key]
        local isBuffDisabled = disabledBuffs and disabledBuffs[entry.key]

        if isKnown and not isBuffDisabled then
            local hasBuff, duration, expTime, charges, icon = false, 0, 0, 0, nil

            if entry.type == "aura" or entry.type == "aura_group" then
                hasBuff, duration, expTime, charges, icon = ScanPlayerAura(entry)
            elseif entry.type == "stance" then
                hasBuff, duration, expTime, charges, icon = ScanStance(entry)
            elseif entry.type == "weapon_enchant" then
                hasBuff, duration, expTime, charges, icon = ScanWeaponEnchant(entry)
            elseif entry.type == "pet" then
                hasBuff, duration, expTime, charges, icon = ScanPet(entry)
            end

            local baseThreshold = entry.threshold or 300
            local effectiveThreshold = (baseThreshold > 60) and thresholdLong or thresholdShort

            local isExpiring = false
            if allowExpiring and hasBuff and expTime and expTime > 0 and effectiveThreshold > 0 then
                local remaining = expTime - now
                if remaining > 0 and remaining <= effectiveThreshold then
                    isExpiring = true
                end
            end

            local isMissing = not hasBuff
            local shouldInclude = isMissing or isExpiring

            if shouldInclude then
                count = count + 1
                local rec = activeResults[count]
                if not rec then
                    rec = {}
                    activeResults[count] = rec
                end

                rec.entry = entry
                rec.hasBuff = hasBuff
                rec.isMissing = isMissing
                rec.isExpiring = isExpiring
                rec.expirationTime = expTime or 0
                rec.duration = duration or 0
                rec.charges = charges or 0
                rec.icon = icon or (entry.spellIDs and data.ResolveTexture(entry.spellIDs[1], entry.fallbackIcon)) or entry.fallbackIcon
            end
        end
    end

    -- Trim surplus reusable entries
    for i = count + 1, #activeResults do
        activeResults[i] = nil
    end

    dirty = false
    return activeResults
end

--- Returns cached results without rescanning if clean
function sfui.buffs.scan.GetResults()
    if dirty then
        return sfui.buffs.scan.RunScan()
    end
    return activeResults
end

--- Marks the scan state dirty and schedules a throttled update
function sfui.buffs.scan.RequestScan()
    if (_G.InCombatLockdown and _G.InCombatLockdown()) or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player")) then
        dirty = true
        return
    end

    dirty = true
    if throttleTimer then return end

    throttleTimer = C_Timer.After(0.08, function()
        throttleTimer = nil
        if (_G.InCombatLockdown and _G.InCombatLockdown()) or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player")) then
            dirty = true
            return
        end
        sfui.buffs.scan.RunScan()
        if sfui.buffs.UpdateDisplay then
            sfui.buffs.UpdateDisplay()
        end
    end)
end

-- ─────────────────────────────────────────────────────────────
--  CENTRAL EVENT ROUTING (sfui.events)
-- ─────────────────────────────────────────────────────────────
local function InitScanEvents()
    -- Only active on Camelot / Classic clients
    if not sfui.isCamelot and not sfui.isClassic then return end
    if not sfui.events then return end

    local function on_player_unit_change()
        sfui.buffs.scan.RequestScan()
    end

    local function on_knowledge_change()
        RefreshSpellKnowledge()
        sfui.buffs.scan.RequestScan()
    end

    -- C-level unit filtered events: only invoke Lua when the player token updates
    sfui.events.RegisterUnitEvent("UNIT_AURA", "player", on_player_unit_change)
    sfui.events.RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player", on_player_unit_change)
    sfui.events.RegisterUnitEvent("UNIT_PET", "player", on_player_unit_change)

    -- Global state events
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", on_player_unit_change)
    sfui.events.RegisterEvent("PLAYER_ALIVE", on_player_unit_change)
    sfui.events.RegisterEvent("PLAYER_UNGHOST", on_player_unit_change)
    sfui.events.RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED", on_player_unit_change)
    sfui.events.RegisterEvent("PLAYER_UPDATE_RESTING", on_player_unit_change)

    -- Talent & spell changes
    sfui.events.RegisterEvent("SPELLS_CHANGED", on_knowledge_change)
    sfui.events.RegisterEvent("PLAYER_TALENT_UPDATE", on_knowledge_change)
    sfui.events.RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", on_knowledge_change)
    sfui.events.RegisterEvent("CHARACTER_POINTS_CHANGED", on_knowledge_change)
    sfui.events.RegisterEvent("TRAIT_CONFIG_UPDATED", on_knowledge_change)

    -- Combat state transitions
    sfui.events.RegisterEvent("PLAYER_REGEN_DISABLED", function()
        if sfui.buffs and sfui.buffs.OnCombatEnter then
            sfui.buffs.OnCombatEnter()
        end
    end)
    sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if sfui.buffs and sfui.buffs.OnCombatLeave then
            sfui.buffs.OnCombatLeave()
        end
        sfui.buffs.scan.RequestScan()
    end)

    -- Spec changes broadcasted by sfui.talents (talents_camelot.lua)
    if sfui.events.RegisterMessage then
        sfui.events.RegisterMessage("SFUI_SPEC_CHANGED", on_knowledge_change)
    end
end
InitScanEvents()


