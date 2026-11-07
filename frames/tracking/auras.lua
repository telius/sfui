local addonName, addon = ...
sfui = sfui or {}
sfui.tracking = sfui.tracking or {}
sfui.tracking.auras = sfui.tracking.auras or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/tracking/auras.lua
--  shared cdm aura resolver for tracked icons and tracked bars
--
--  mirrors blizzard's CheckCacheCooldownValuesFromAura (CooldownViewer.lua:854): while
--  an aura tied to a cdm item is up, its duration takes precedence over the spell
--  cooldown. covers "cover spell" items such as forever's paladin "seals" (one cdm item
--  whose linkedSpellIDs list every seal), self buffs, and linked auras.
--
--  in combat on 12.x / forever (1.60.1), C_Secrets.ShouldAurasBeSecret() is true:
--    - C_UnitAuras.GetPlayerAuraBySpellID and GetAuraDataBySpellName have
--      RequiresNonSecretAura = true and return nil for normal player buffs.
--    - aura.auraInstanceID on unit auras is secret, and C_UnitAuras.GetAuraDuration
--      only accepts secret arguments from untainted callers.
--    - UNIT_SPELLCAST_SUCCEEDED on "player", however, is never secret, and
--      C_DurationUtil.CreateDuration() creates a plain LuaDurationObject that drives
--      StatusBar:SetTimerDuration, DurationTextBinding:SetDuration, and
--      Cooldown:SetCooldownFromDurationObject natively.
-- ══════════════════════════════════════════════════════════════════════════════

local A = sfui.tracking.auras

local C_Spell = C_Spell
local C_UnitAuras = C_UnitAuras
local C_Secrets = _G.C_Secrets
local C_DurationUtil = _G.C_DurationUtil
local GetTime = GetTime
local wipe = wipe or table.wipe
local issecretvalue = sfui.common.issecretvalue

A.HIDE_AURA_FLAG = (Enum and Enum.CooldownSetSpellFlags and Enum.CooldownSetSpellFlags.HideAura) or 1
A.SEALS_COOLDOWN_ID = 200340
A.SEALS_SPELL_ID = 1323522
A.DEFAULT_SEAL_DURATION = 30

local _spellNameCache = {}
local _spellTexCache = {}
local _seenAuraNames = {}
local _learnedDurations = {} -- [spellID or spellName] = plain duration in seconds
local _castAurasBySpellID = {}
local _castAurasByName = {}
local _revision = 0
local _lastHelpfulCount = 0

local _activeSeal = {
    active = false,
    spellID = nil,
    name = nil,
    icon = nil,
    applications = 1,
    startTime = 0,
    duration = 0,
    expirationTime = 0,
    auraInstanceID = nil,
    durationObj = nil,
}

-- RequiresUnitAuraAccess (FailureMode = "Error") throws a Lua error if tainted code calls
-- GetUnitAuras, GetAuraDataByAuraInstanceID, or GetAuraDuration when auras are secret.
local function CanAccessUnitAuras()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
        return false
    end
    if InCombatLockdown and InCombatLockdown() then
        return false
    end
    return true
end
A.CanAccessUnitAuras = CanAccessUnitAuras

local function BumpRevision()
    _revision = _revision + 1
end

function A.GetRevision()
    return _revision
end

local function NotifyTrackingDirty()
    BumpRevision()
    if sfui.trackedbars then
        sfui.trackedbars.isDirty = true
    end
    if sfui.trackedicons and sfui.trackedicons.MarkDirty then
        sfui.trackedicons.MarkDirty(false)
    end
end

local function GetCachedSpellName(spellID)
    if not spellID or issecretvalue(spellID) or spellID == 0 then return nil end
    local name = _spellNameCache[spellID]
    if name == nil then
        local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
        if n and not issecretvalue(n) and n ~= "" then
            name = n
        else
            name = false
        end
        _spellNameCache[spellID] = name
    end
    return name or nil
end

local function GetCachedSpellTexture(spellID)
    if not spellID or issecretvalue(spellID) or spellID == 0 then return nil end
    local tex = _spellTexCache[spellID]
    if tex == nil then
        local t = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)
        if t and not issecretvalue(t) then
            tex = t
        else
            tex = false
        end
        _spellTexCache[spellID] = tex
    end
    return tex or nil
end

local function IsSealName(name)
    if not name or issecretvalue(name) or type(name) ~= "string" then return false end
    return string.find(name, "^Seal of ") ~= nil
end

local function EnsureDurationObj(holder, startTime, duration)
    if not C_DurationUtil or not C_DurationUtil.CreateDuration then return nil end
    local dObj = holder.durationObj
    if not dObj then
        dObj = C_DurationUtil.CreateDuration()
        holder.durationObj = dObj
    end
    if startTime and duration and duration > 0 then
        dObj:SetTimeFromStart(startTime, duration, 1)
    else
        dObj:Reset()
    end
    return dObj
end

-- plain (non-secret) field read from aura data, or nil
function A.PlainField(aura, key)
    local v = aura and aura[key]
    if v ~= nil and not issecretvalue(v) then
        return v
    end
    return nil
end

-- true for synthetic umbrella cdm entries (e.g. forever's paladin "seals" 200340 / 1323522)
-- whose base spell is never in the player's spellbook
function A.IsCoverSpell(cdInfo, cooldownID, spellID)
    local cid = cooldownID or (cdInfo and cdInfo.cooldownID)
    if cid and not issecretvalue(cid) and cid == A.SEALS_COOLDOWN_ID then
        return true
    end
    local sid = spellID or (cdInfo and (cdInfo.overrideSpellID or cdInfo.spellID))
    if sid and not issecretvalue(sid) and sid == A.SEALS_SPELL_ID then
        return true
    end
    return false
end

function A.IsSealSpell(spellID)
    if not spellID or issecretvalue(spellID) or spellID == 0 then return false end
    if spellID == A.SEALS_SPELL_ID then return true end
    return IsSealName(GetCachedSpellName(spellID))
end

-- true when a cdm entry should be treated as known by the player, even if blizzard's
-- C_CooldownViewer marks cdInfo.isKnown = false on a synthetic cover spell
function A.IsCooldownItemKnown(cdInfo, cooldownID)
    if not cdInfo then return true end
    if cdInfo.equipSlot ~= nil or cdInfo.spellCategoryID ~= nil or (cdInfo.itemID and cdInfo.itemID > 0) then
        return true
    end
    if cdInfo.isKnown ~= false then return true end
    if A.IsCoverSpell(cdInfo, cooldownID) then return true end

    local isKnownFn = sfui.common and sfui.common.is_spell_known
    local baseID = cdInfo.overrideSpellID or cdInfo.spellID
    if baseID and not issecretvalue(baseID) and baseID > 0 and isKnownFn and isKnownFn(baseID) then
        return true
    end

    local linked = cdInfo.linkedSpellIDs
    if linked and #linked > 0 then
        local getSpellInfo = C_Spell and C_Spell.GetSpellInfo
        for i = 1, #linked do
            local lid = linked[i]
            if lid and not issecretvalue(lid) and lid > 0 then
                if isKnownFn and isKnownFn(lid) then
                    return true
                end
                -- classic ranks: linkedSpellIDs may list rank 1 while the player knows rank 2+
                if getSpellInfo then
                    local name = GetCachedSpellName(lid)
                    if name and getSpellInfo(name) ~= nil then
                        return true
                    end
                end
            end
        end
    end

    return false
end

-- blizzard viewers whose item frames keep a live auraInstanceID (updated by secure code,
-- even while sfui keeps the viewers hidden). cooldown viewers set it too when an item's
-- aura takes precedence (e.g. the "seals" item sitting in the essential viewer).
local BLIZZ_VIEWERS = {
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
}

local function FindBlizzItem(cooldownID)
    if not cooldownID then return nil end
    for i = 1, #BLIZZ_VIEWERS do
        local viewer = _G[BLIZZ_VIEWERS[i]]
        local pool = viewer and viewer.itemFramePool
        if pool then
            for itemFrame in pool:EnumerateActive() do
                if itemFrame.cooldownID == cooldownID then
                    return itemFrame
                end
            end
        end
    end
    return nil
end
A.FindBlizzItem = FindBlizzItem

-- true when an entry should display its aura duration instead of / over its cooldown
function A.WantsAura(cdInfo, isAuraType, linkedSpellIDs, spellID, cooldownID)
    local checkID = spellID or (cdInfo and (cdInfo.overrideSpellID or cdInfo.spellID))
    local wants = isAuraType
        or A.IsCoverSpell(cdInfo, cooldownID, checkID)
        or A.IsSealSpell(checkID)
        or (cdInfo and (cdInfo.selfAura or cdInfo.hasAura or (linkedSpellIDs and #linkedSpellIDs > 0)))
        or (checkID and sfui.common and sfui.common.is_known_aura_spell and sfui.common.is_known_aura_spell(checkID))
    if wants and cdInfo and cdInfo.flags and bit and bit.band(cdInfo.flags, A.HIDE_AURA_FLAG) ~= 0 then
        return false
    end
    return wants and true or false
end

local function AddCandidate(list, seen, id)
    if id and not issecretvalue(id) and id ~= 0 and not seen[id] then
        seen[id] = true
        list[#list + 1] = id
    end
end

-- builds (and caches on `holder`) the spell ids that may carry the aura.
-- returns the list and whether it was rebuilt (holder re-used for a new entry).
function A.GetCandidates(holder, activeID, linkedSpellIDs, cdInfo)
    if holder._auraCandidates and holder._auraCandActive == activeID and holder._auraCandLinked == linkedSpellIDs then
        return holder._auraCandidates, false
    end
    local list, seen = {}, {}
    if linkedSpellIDs then
        for i = 1, #linkedSpellIDs do
            AddCandidate(list, seen, linkedSpellIDs[i])
        end
    end
    if cdInfo then
        AddCandidate(list, seen, cdInfo.overrideTooltipSpellID)
        AddCandidate(list, seen, cdInfo.overrideSpellID)
        AddCandidate(list, seen, cdInfo.spellID)
    end
    AddCandidate(list, seen, activeID)
    holder._auraCandidates = list
    holder._auraCandActive = activeID
    holder._auraCandLinked = linkedSpellIDs
    return list, true
end

local function HasCandidate(candidates, targetID)
    if not candidates or not targetID then return false end
    for i = 1, #candidates do
        if candidates[i] == targetID then return true end
    end
    return false
end

local function RecordCastAura(spellID, name, icon, startTime, duration, auraInstanceID, applications)
    if not duration or duration <= 0 then return nil end
    local entry = (spellID and _castAurasBySpellID[spellID]) or (name and _castAurasByName[name])
    if not entry then
        entry = {}
    end
    entry.active = true
    entry.spellID = spellID or entry.spellID
    entry.name = name or entry.name
    entry.icon = icon or entry.icon
    entry.applications = applications or 1
    entry.startTime = startTime
    entry.duration = duration
    entry.expirationTime = startTime + duration
    entry.auraInstanceID = auraInstanceID
    EnsureDurationObj(entry, startTime, duration)
    if spellID then _castAurasBySpellID[spellID] = entry end
    if name then _castAurasByName[name] = entry end
    return entry
end

-- synchronises _activeSeal and learned durations whenever player buffs are readable,
-- or validates combat expiration when player buffs are secret.
local function SyncPlayerBuffs(updateInfo)
    local now = GetTime()
    if not CanAccessUnitAuras() then
        -- in combat with secret aura data: never call RequiresUnitAuraAccess APIs
        if _activeSeal.active and _activeSeal.expirationTime and _activeSeal.expirationTime > 0 and now >= _activeSeal.expirationTime then
            _activeSeal.active = false
            _activeSeal.auraInstanceID = nil
            EnsureDurationObj(_activeSeal, nil, nil)
            BumpRevision()
        end
        return
    end

    if not C_UnitAuras or not C_UnitAuras.GetUnitAuras then return end
    local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
    if not auras then return end

    local count = #auras
    local readableAny = (count == 0)
    local foundSeal = nil

    for i = 1, count do
        local aura = auras[i]
        local name = A.PlainField(aura, "name")
        if name then
            readableAny = true
            local sid = A.PlainField(aura, "spellId")
            local dur = A.PlainField(aura, "duration")
            local exp = A.PlainField(aura, "expirationTime")
            local iid = A.PlainField(aura, "auraInstanceID")
            local icon = A.PlainField(aura, "icon")
            local apps = A.PlainField(aura, "applications")

            if dur and dur > 0 then
                _learnedDurations[name] = dur
                if sid and sid > 0 then
                    _learnedDurations[sid] = dur
                end
                if exp and exp > now then
                    RecordCastAura(sid, name, icon, exp - dur, dur, iid, apps)
                end
            end

            if IsSealName(name) then
                foundSeal = aura
            end
        end
    end

    if readableAny then
        if foundSeal then
            local sid = A.PlainField(foundSeal, "spellId")
            local name = A.PlainField(foundSeal, "name")
            local icon = A.PlainField(foundSeal, "icon") or GetCachedSpellTexture(sid)
            local apps = A.PlainField(foundSeal, "applications") or 1
            local dur = A.PlainField(foundSeal, "duration") or _learnedDurations[sid] or _learnedDurations[name] or A.DEFAULT_SEAL_DURATION
            local exp = A.PlainField(foundSeal, "expirationTime")
            local iid = A.PlainField(foundSeal, "auraInstanceID")
            local start = (exp and dur and dur > 0 and exp > 0) and (exp - dur) or now
            if not exp or exp <= 0 then
                exp = start + dur
            end

            local changed = (not _activeSeal.active)
                or (_activeSeal.spellID ~= sid)
                or (_activeSeal.name ~= name)
                or (_activeSeal.auraInstanceID ~= iid)
                or (math.abs((_activeSeal.expirationTime or 0) - exp) > 0.5)

            _activeSeal.active = true
            _activeSeal.spellID = sid
            _activeSeal.name = name
            _activeSeal.icon = icon
            _activeSeal.applications = apps
            _activeSeal.startTime = start
            _activeSeal.duration = dur
            _activeSeal.expirationTime = exp
            _activeSeal.auraInstanceID = iid
            EnsureDurationObj(_activeSeal, start, dur)

            if changed then
                BumpRevision()
            end
        elseif _activeSeal.active then
            _activeSeal.active = false
            _activeSeal.auraInstanceID = nil
            EnsureDurationObj(_activeSeal, nil, nil)
            BumpRevision()
        end
    end

    _lastHelpfulCount = count
end

local function GetActiveSealForCandidates(cooldownID, candidates)
    if not _activeSeal.active then return nil end
    local now = GetTime()
    if _activeSeal.expirationTime and _activeSeal.expirationTime > 0 and now >= _activeSeal.expirationTime then
        _activeSeal.active = false
        return nil
    end
    if CanAccessUnitAuras() and _activeSeal.auraInstanceID and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
        if C_UnitAuras.GetAuraDataByAuraInstanceID("player", _activeSeal.auraInstanceID) == nil then
            _activeSeal.active = false
            _activeSeal.auraInstanceID = nil
            return nil
        end
    end

    if cooldownID == A.SEALS_COOLDOWN_ID or HasCandidate(candidates, A.SEALS_SPELL_ID) then
        return _activeSeal
    end
    if candidates then
        for i = 1, #candidates do
            local cid = candidates[i]
            if cid == _activeSeal.spellID then
                return _activeSeal
            end
            local cname = GetCachedSpellName(cid)
            if cname and cname == _activeSeal.name then
                return _activeSeal
            end
        end
    end
    return nil
end

local function GetActiveCastAuraForCandidates(candidates)
    if not candidates then return nil end
    local now = GetTime()
    local canAccess = CanAccessUnitAuras()
    for i = 1, #candidates do
        local cid = candidates[i]
        local entry = _castAurasBySpellID[cid]
        if not entry then
            local cname = GetCachedSpellName(cid)
            if cname then
                entry = _castAurasByName[cname]
            end
        end
        if entry and entry.active then
            if entry.expirationTime and entry.expirationTime > 0 and now >= entry.expirationTime then
                entry.active = false
            elseif canAccess and entry.auraInstanceID and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
                and C_UnitAuras.GetAuraDataByAuraInstanceID("player", entry.auraInstanceID) == nil then
                entry.active = false
                entry.auraInstanceID = nil
            else
                return entry
            end
        end
    end
    return nil
end

local function ResolveCombatFallback(cooldownID, candidates)
    local seal = GetActiveSealForCandidates(cooldownID, candidates)
    if seal then
        return seal.auraInstanceID, seal, true
    end
    local castAura = GetActiveCastAuraForCandidates(candidates)
    if castAura then
        return castAura.auraInstanceID, castAura, true
    end
    return nil, nil, false
end

-- returns auraInstanceID, auraData, present
-- when auras are secret in combat, auraData may be a synthetic state table carrying a
-- plain .durationObj, .name, .icon, and .applications so bars and icons work seamlessly.
function A.Resolve(cooldownID, candidates)
    local canAccess = CanAccessUnitAuras()

    -- 1. hidden blizzard viewer item
    local blizz = FindBlizzItem(cooldownID)
    if blizz and blizz.auraDataUnit == "player" and sfui.common.HasAuraInstanceID(blizz.auraInstanceID) then
        local iid = blizz.auraInstanceID
        if canAccess and not issecretvalue(iid) then
            return iid, blizz.auraDataCached, true
        end
        local fbIID, fbAura, fbPresent = ResolveCombatFallback(cooldownID, candidates)
        if fbPresent then
            return fbIID, fbAura, true
        end
        return nil, blizz.auraDataCached, true
    end

    if not canAccess or not C_UnitAuras or not candidates then
        return ResolveCombatFallback(cooldownID, candidates)
    end

    -- 2. by spell id across linked / override / base ids
    local getBySpellID = C_UnitAuras.GetPlayerAuraBySpellID
    if getBySpellID then
        for i = 1, #candidates do
            local aura = getBySpellID(candidates[i])
            if aura then
                local iid = aura.auraInstanceID
                if iid and not issecretvalue(iid) then
                    return iid, aura, true
                end
                local fbIID, fbAura, fbPresent = ResolveCombatFallback(cooldownID, candidates)
                if fbPresent then
                    return fbIID, fbAura, true
                end
                return nil, aura, true
            end
        end
    end

    -- 3. by name: classic ranks share a name but not a spell id (seal rank 1..n)
    local getByName = C_UnitAuras.GetAuraDataBySpellName
    if getByName then
        wipe(_seenAuraNames)
        for i = 1, #candidates do
            local name = GetCachedSpellName(candidates[i])
            if name and not _seenAuraNames[name] then
                _seenAuraNames[name] = true
                local aura = getByName("player", name, "HELPFUL|PLAYER") or getByName("player", name, "HELPFUL")
                if aura and aura.auraInstanceID and not issecretvalue(aura.auraInstanceID) then
                    return aura.auraInstanceID, aura, true
                end
            end
        end
    end

    -- 4. paladin "seals" cover item fallback: catch any active player buff named "Seal of ..."
    --    even if a custom forever seal or rank is missing from linkedSpellIDs
    if C_UnitAuras.GetUnitAuras
        and (cooldownID == A.SEALS_COOLDOWN_ID or HasCandidate(candidates, A.SEALS_SPELL_ID)) then
        local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL")
        if auras then
            for i = 1, #auras do
                local aura = auras[i]
                local name = aura and aura.name
                local iid = aura and aura.auraInstanceID
                if name and not issecretvalue(name) and iid and not issecretvalue(iid)
                    and string.find(name, "^Seal of ") then
                    return iid, aura, true
                end
            end
        end
    end

    -- 5. combat-safe cast/snapshot tracker (handles secret auras in combat + rank mismatches)
    return ResolveCombatFallback(cooldownID, candidates)
end

-- duration object for a resolved aura: uses C_UnitAuras.GetAuraDuration when plain and
-- unrestricted, or falls back to the plain LuaDurationObject built from spellcast / snapshot.
function A.GetDuration(auraInstanceID, aura)
    if CanAccessUnitAuras() and auraInstanceID and not issecretvalue(auraInstanceID)
        and C_UnitAuras and C_UnitAuras.GetAuraDuration then
        local dObj = C_UnitAuras.GetAuraDuration("player", auraInstanceID)
        if dObj then
            return dObj
        end
    end
    if aura and aura.durationObj then
        return aura.durationObj
    end
    return nil
end

-- ─── event wiring for combat-safe seal & self-buff tracking ──────────────────
if sfui.events then
    sfui.events.RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", function(event, unit, castGUID, spellID)
        if not spellID or issecretvalue(spellID) or type(spellID) ~= "number" or spellID <= 0 then
            return
        end
        local name = GetCachedSpellName(spellID)
        local icon = GetCachedSpellTexture(spellID)
        local now = GetTime()

        if IsSealName(name) or spellID == A.SEALS_SPELL_ID then
            local dur = _learnedDurations[spellID] or (name and _learnedDurations[name]) or A.DEFAULT_SEAL_DURATION
            _activeSeal.active = true
            _activeSeal.spellID = spellID
            _activeSeal.name = name
            _activeSeal.icon = icon
            _activeSeal.applications = 1
            _activeSeal.startTime = now
            _activeSeal.duration = dur
            _activeSeal.expirationTime = now + dur
            _activeSeal.auraInstanceID = nil
            EnsureDurationObj(_activeSeal, now, dur)
            NotifyTrackingDirty()
            return
        end

        local dur = _learnedDurations[spellID]
            or (name and _learnedDurations[name])
            or (sfui.common and sfui.common.GetAuraDefaultDuration and sfui.common.GetAuraDefaultDuration(spellID))
        if dur and dur > 0 then
            RecordCastAura(spellID, name, icon, now, dur, nil, 1)
            NotifyTrackingDirty()
        end
    end)

    sfui.events.RegisterUnitEvent("UNIT_AURA", "player", function(event, unit, updateInfo)
        SyncPlayerBuffs(updateInfo)
    end)

    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        SyncPlayerBuffs(nil)
    end)

    sfui.events.RegisterEvent("PLAYER_REGEN_DISABLED", function()
        SyncPlayerBuffs(nil)
    end)

    sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", function()
        SyncPlayerBuffs(nil)
        NotifyTrackingDirty()
    end)
end
