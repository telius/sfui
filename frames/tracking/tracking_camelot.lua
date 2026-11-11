local addonName, addon = ...
sfui = sfui or {}
sfui.tracking = sfui.tracking or {}
sfui.tracking.camelot = sfui.tracking.camelot or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/tracking/tracking_camelot.lua  [AllowLoadGameType camelot]
--  forever-specific cdm cover spells & paladin seal tracking
--
--  loaded strictly on forever (`camelot`). handles the synthetic umbrella cdm
--  entry ("seals": cooldownID 200340 / spellID 1323522), multi-rank spellbook
--  knowledge fallback, and incremental + spellcast seal duration state.
-- ══════════════════════════════════════════════════════════════════════════════

local C = sfui.tracking.camelot
local A = sfui.tracking.auras

local C_Spell = C_Spell
local C_UnitAuras = C_UnitAuras
local GetTime = GetTime
local tonumber = tonumber
local type = type
local issecretvalue = sfui.common.issecretvalue

C.SEALS_COOLDOWN_ID = 200340
C.SEALS_SPELL_ID = 1323522
C.DEFAULT_SEAL_DURATION = 30

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

function C.IsSealName(name)
    if not name or issecretvalue(name) or type(name) ~= "string" then return false end
    return string.find(name, "^Seal of ") ~= nil
end

function C.IsCoverSpell(cdInfo, cooldownID, spellID)
    local cid = cooldownID or (cdInfo and cdInfo.cooldownID)
    if cid and not issecretvalue(cid) and cid == C.SEALS_COOLDOWN_ID then
        return true
    end
    local sid = spellID or (cdInfo and (cdInfo.overrideSpellID or cdInfo.spellID))
    if sid and not issecretvalue(sid) and sid == C.SEALS_SPELL_ID then
        return true
    end
    return false
end

function C.IsSealSpell(spellID)
    if not spellID or issecretvalue(spellID) or spellID == 0 then return false end
    if spellID == C.SEALS_SPELL_ID then return true end
    local name = A and A.GetCachedSpellName and A.GetCachedSpellName(spellID)
    return C.IsSealName(name)
end

function C.IsForeverSealEntry(entry, cdInfo, activeSpellID)
    local isTbl = type(entry) == "table"
    local cdID = (isTbl and entry.cooldownID)
        or (isTbl and entry.type == "cooldown" and tonumber(entry.id))
        or (cdInfo and cdInfo.cooldownID)
    local sid = activeSpellID
        or (isTbl and entry.spellID)
        or (isTbl and entry.type ~= "cooldown" and entry.type ~= "item" and tonumber(entry.id))
        or (cdInfo and (cdInfo.overrideSpellID or cdInfo.spellID))
    return C.IsCoverSpell(cdInfo, cdID, sid) or C.IsSealSpell(sid)
end

function C.IsCooldownItemKnownFallback(cdInfo, cooldownID)
    if C.IsCoverSpell(cdInfo, cooldownID) then return true end

    local isKnownFn = sfui.common and sfui.common.is_spell_known
    local baseID = cdInfo and (cdInfo.overrideSpellID or cdInfo.spellID)
    if baseID and not issecretvalue(baseID) and baseID > 0 and isKnownFn and isKnownFn(baseID) then
        return true
    end

    local linked = cdInfo and cdInfo.linkedSpellIDs
    if linked and #linked > 0 then
        local getSpellInfo = C_Spell and C_Spell.GetSpellInfo
        for i = 1, #linked do
            local lid = linked[i]
            if lid and not issecretvalue(lid) and lid > 0 then
                if isKnownFn and isKnownFn(lid) then
                    return true
                end
                if getSpellInfo and A and A.GetCachedSpellName then
                    local name = A.GetCachedSpellName(lid)
                    if name and getSpellInfo(name) ~= nil then
                        return true
                    end
                end
            end
        end
    end

    return false
end

function C.ClearActiveSeal()
    local wasActive = _activeSeal.active
    _activeSeal.active = false
    _activeSeal.auraInstanceID = nil
    if A and A.EnsureDurationObj then
        A.EnsureDurationObj(_activeSeal, nil, nil)
    end
    return wasActive
end

function C.IsActiveSealInstance(auraInstanceID)
    return _activeSeal.active and auraInstanceID ~= nil and _activeSeal.auraInstanceID == auraInstanceID
end

function C.OnAuraRemoved(auraInstanceID)
    if _activeSeal.active and auraInstanceID ~= nil and _activeSeal.auraInstanceID == auraInstanceID then
        return C.ClearActiveSeal()
    end
    return false
end

function C.CheckSealExpiration(now)
    if _activeSeal.active and _activeSeal.expirationTime and _activeSeal.expirationTime > 0 and now >= _activeSeal.expirationTime then
        return C.ClearActiveSeal()
    end
    return false
end

function C.UpdateFromAuraData(aura, now)
    if not aura or not A then return false end
    local sid = A.PlainField(aura, "spellId")
    local name = A.PlainField(aura, "name")
    if not C.IsSealName(name) then return false end

    local icon = A.PlainField(aura, "icon") or A.GetCachedSpellTexture(sid)
    local apps = A.PlainField(aura, "applications") or 1
    local dur = A.PlainField(aura, "duration")
    if dur and dur > 0 then
        A.LearnDuration(sid, name, dur)
    else
        dur = A.GetLearnedDuration(sid, name) or C.DEFAULT_SEAL_DURATION
    end
    local exp = A.PlainField(aura, "expirationTime")
    local iid = A.PlainField(aura, "auraInstanceID")
    local start = (exp and dur and dur > 0 and exp > 0) and (exp - dur) or now
    if not exp or exp <= 0 then
        exp = start + dur
    end

    local changed = (not _activeSeal.active)
        or (_activeSeal.spellID ~= sid)
        or (_activeSeal.name ~= name)
        or (_activeSeal.applications ~= apps)
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
    A.EnsureDurationObj(_activeSeal, start, dur)
    return changed
end

function C.SyncSealFromFullScan(foundSealAura, now)
    if foundSealAura then
        return C.UpdateFromAuraData(foundSealAura, now)
    elseif _activeSeal.active then
        return C.ClearActiveSeal()
    end
    return false
end

function C.OnSpellCastSucceeded(spellID, name, icon, now)
    if not (C.IsSealName(name) or spellID == C.SEALS_SPELL_ID) then
        return false
    end
    local dur = (A and A.GetLearnedDuration(spellID, name)) or C.DEFAULT_SEAL_DURATION
    _activeSeal.active = true
    _activeSeal.spellID = spellID
    _activeSeal.name = name
    _activeSeal.icon = icon
    _activeSeal.applications = 1
    _activeSeal.startTime = now
    _activeSeal.duration = dur
    _activeSeal.expirationTime = now + dur
    _activeSeal.auraInstanceID = nil
    if A and A.EnsureDurationObj then
        A.EnsureDurationObj(_activeSeal, now, dur)
    end
    return true
end

function C.GetActiveSealForCandidates(cooldownID, candidates)
    if not _activeSeal.active or not A then return nil end
    local now = GetTime()
    if _activeSeal.expirationTime and _activeSeal.expirationTime > 0 and now >= _activeSeal.expirationTime then
        _activeSeal.active = false
        return nil
    end
    if A.CanAccessUnitAuras() and _activeSeal.auraInstanceID and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
        if C_UnitAuras.GetAuraDataByAuraInstanceID("player", _activeSeal.auraInstanceID) == nil then
            _activeSeal.active = false
            _activeSeal.auraInstanceID = nil
            return nil
        end
    end

    if cooldownID == C.SEALS_COOLDOWN_ID or A.HasCandidate(candidates, C.SEALS_SPELL_ID) then
        return _activeSeal
    end
    if candidates then
        for i = 1, #candidates do
            local cid = candidates[i]
            if cid == _activeSeal.spellID then
                return _activeSeal
            end
            local cname = A.GetCachedSpellName(cid)
            if cname and cname == _activeSeal.name then
                return _activeSeal
            end
        end
    end
    return nil
end

-- wire camelot overrides onto shared sfui.tracking.auras contract
if A then
    A.SEALS_COOLDOWN_ID = C.SEALS_COOLDOWN_ID
    A.SEALS_SPELL_ID = C.SEALS_SPELL_ID
    A.DEFAULT_SEAL_DURATION = C.DEFAULT_SEAL_DURATION
    A.IsCoverSpell = C.IsCoverSpell
    A.IsSealSpell = C.IsSealSpell
    A.IsForeverSealEntry = C.IsForeverSealEntry
end

