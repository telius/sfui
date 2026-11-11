local addonName, addon = ...
sfui = sfui or {}
sfui.tracking = sfui.tracking or {}
sfui.tracking.auras = sfui.tracking.auras or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/tracking/auras.lua
--  watchlist-driven, incremental cdm aura engine for tracked icons & bars
--
--  mirrors blizzard's CooldownViewerMixin:OnUnitAura (CooldownViewer.lua:1812) and
--  CheckCacheCooldownValuesFromAura (CooldownViewer.lua:854):
--    - completely dormant (0 registered events, 0.00 ms) when watchlist is empty.
--    - processes incremental UNIT_AURA UnitAuraUpdateInfo (removedAuraInstanceIDs,
--      updatedAuraInstanceIDs, addedAuras) in O(1) without allocating GetUnitAuras
--      tables, bumping revision ONLY when a watched aura changes.
--    - combat-safe: never touches secret values or RequiresUnitAuraAccess APIs when
--      C_Secrets.ShouldAurasBeSecret() is true; falls back to UNIT_SPELLCAST_SUCCEEDED
--      plain LuaDurationObjects.
--    - forever-specific paladin seal cover mechanics live in tracking_camelot.lua.
-- ══════════════════════════════════════════════════════════════════════════════

local A = sfui.tracking.auras

local C_Spell = C_Spell
local C_UnitAuras = C_UnitAuras
local C_Secrets = _G.C_Secrets
local C_DurationUtil = _G.C_DurationUtil
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local pairs = pairs
local type = type
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
local _castAurasList = {}
local _watchedByInstanceID = {} -- [auraInstanceID] = castAuraEntry

-- weak O(1) cache for hidden blizzard cooldown viewer item frames
local _blizzItemByCooldownID = setmetatable({}, { __mode = "v" })
local _blizzItemIsAuraViewer = {}
local _lastBlizzHasInstance = {}

-- separate icon vs bar watchlists merged into combined lookup tables
local _iconWatchedSpells = {}
local _iconWatchedNames = {}
local _iconWatchedCooldowns = {}
local _iconWatchSeals = false
local _iconWatchCount = 0

local _barWatchedSpells = {}
local _barWatchedNames = {}
local _barWatchedCooldowns = {}
local _barWatchSeals = false
local _barWatchCount = 0

local _watchedSpellIDs = {}
local _watchedNames = {}
local _watchedCooldownIDs = {}
local _prevWatchedSpellIDs = {}
local _prevWatchedNames = {}
local _prevWatchedCooldowns = {}
local _watchSeals = false
local _watchCount = 0
local _watchedSpellCount = 0
local _watchedNameCount = 0
local _watchedCooldownCount = 0

local _eventsRegistered = false
local _revision = 1

-- RequiresUnitAuraAccess (FailureMode = "Error") throws a Lua error if tainted code calls
-- GetAuraDataByIndex, GetAuraDataByAuraInstanceID, or GetAuraDuration when auras are secret.
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
A.BumpRevision = BumpRevision

function A.GetRevision()
    return _revision
end

local function NotifyTrackingDirty()
    BumpRevision()
    if _barWatchCount > 0 and sfui.trackedbars
        and (not sfui.trackedbars.HasSelfDrivenBars or sfui.trackedbars.HasSelfDrivenBars()) then
        sfui.trackedbars.isDirty = true
    end
    if _iconWatchCount > 0 and sfui.trackedicons and sfui.trackedicons.MarkDirty then
        sfui.trackedicons.MarkDirty(false)
    end
end
A.NotifyTrackingDirty = NotifyTrackingDirty

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
A.GetCachedSpellName = GetCachedSpellName

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
A.GetCachedSpellTexture = GetCachedSpellTexture

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
A.EnsureDurationObj = EnsureDurationObj

function A.LearnDuration(spellID, name, dur)
    if not dur or dur <= 0 then return end
    if name then _learnedDurations[name] = dur end
    if spellID and spellID > 0 then _learnedDurations[spellID] = dur end
end

function A.GetLearnedDuration(spellID, name)
    return (spellID and _learnedDurations[spellID]) or (name and _learnedDurations[name]) or nil
end

-- plain (non-secret) field read from aura data, or nil
function A.PlainField(aura, key)
    local v = aura and aura[key]
    if v ~= nil and not issecretvalue(v) then
        return v
    end
    return nil
end

-- default stubs on retail / classic era (overridden by tracking_camelot.lua on forever)
function A.IsCoverSpell(_cdInfo, _cooldownID, _spellID)
    return false
end

function A.IsSealSpell(_spellID)
    return false
end

function A.IsForeverSealEntry(_entry, _cdInfo, _activeSpellID)
    return false
end

function A.IsCooldownItemKnown(cdInfo, cooldownID)
    if not cdInfo then return true end
    if cdInfo.equipSlot ~= nil or cdInfo.spellCategoryID ~= nil or (cdInfo.itemID and cdInfo.itemID > 0) then
        return true
    end
    if cdInfo.isKnown ~= false then return true end
    local camelot = sfui.tracking.camelot
    if camelot and camelot.IsCooldownItemKnownFallback then
        return camelot.IsCooldownItemKnownFallback(cdInfo, cooldownID)
    end
    return false
end

-- blizzard viewers whose item frames keep a live auraInstanceID (updated by secure code,
-- even while sfui keeps the viewers hidden). indices 1-2 are dedicated aura viewers.
local BLIZZ_VIEWERS = {
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
}

local function FindBlizzItem(cooldownID)
    if not cooldownID then return nil, false end
    local cached = _blizzItemByCooldownID[cooldownID]
    if cached and cached.cooldownID == cooldownID then
        return cached, _blizzItemIsAuraViewer[cooldownID] == true
    end
    for i = 1, #BLIZZ_VIEWERS do
        local viewer = _G[BLIZZ_VIEWERS[i]]
        local pool = viewer and viewer.itemFramePool
        if pool then
            for itemFrame in pool:EnumerateActive() do
                if itemFrame.cooldownID == cooldownID then
                    local isAuraViewer = (i <= 2)
                    _blizzItemByCooldownID[cooldownID] = itemFrame
                    _blizzItemIsAuraViewer[cooldownID] = isAuraViewer
                    return itemFrame, isAuraViewer
                end
            end
        end
    end
    _blizzItemByCooldownID[cooldownID] = nil
    _blizzItemIsAuraViewer[cooldownID] = nil
    return nil, false
end
A.FindBlizzItem = FindBlizzItem

function A.WantsAura(cdInfo, forceAura, linkedSpellIDs, spellID, cooldownID)
    local checkID = spellID or (cdInfo and (cdInfo.overrideSpellID or cdInfo.spellID))
    local wants = forceAura
        or A.IsCoverSpell(cdInfo, cooldownID, checkID)
        or A.IsSealSpell(checkID)
        or (cdInfo and (cdInfo.selfAura or cdInfo.hasAura or (linkedSpellIDs and #linkedSpellIDs > 0)))
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
A.HasCandidate = HasCandidate

local function RecordCastAura(spellID, name, icon, startTime, duration, auraInstanceID, applications)
    if not duration or duration <= 0 then return nil, false end
    local entry = (spellID and _castAurasBySpellID[spellID]) or (name and _castAurasByName[name])
    if not entry then
        entry = {}
        _castAurasList[#_castAurasList + 1] = entry
    elseif entry.auraInstanceID and entry.auraInstanceID ~= auraInstanceID then
        _watchedByInstanceID[entry.auraInstanceID] = nil
    end

    local exp = startTime + duration
    local apps = applications or 1
    local changed = (not entry.active)
        or (entry.spellID ~= (spellID or entry.spellID))
        or (entry.applications ~= apps)
        or (entry.auraInstanceID ~= auraInstanceID)
        or (math.abs((entry.expirationTime or 0) - exp) > 0.5)

    entry.active = true
    entry.spellID = spellID or entry.spellID
    entry.name = name or entry.name
    entry.icon = icon or entry.icon
    entry.applications = apps
    entry.startTime = startTime
    entry.duration = duration
    entry.expirationTime = exp
    entry.auraInstanceID = auraInstanceID
    EnsureDurationObj(entry, startTime, duration)

    if spellID then _castAurasBySpellID[spellID] = entry end
    if name then _castAurasByName[name] = entry end
    if auraInstanceID then _watchedByInstanceID[auraInstanceID] = entry end
    return entry, changed
end

local function UpdateFromReadableAura(aura, now)
    local name = A.PlainField(aura, "name")
    local sid = A.PlainField(aura, "spellId")
    if not name and not sid then return nil, false end

    local dur = A.PlainField(aura, "duration")
    local exp = A.PlainField(aura, "expirationTime")
    local iid = A.PlainField(aura, "auraInstanceID")
    local icon = A.PlainField(aura, "icon")
    local apps = A.PlainField(aura, "applications")

    if dur and dur > 0 then
        A.LearnDuration(sid, name, dur)
        if exp and exp > now then
            return RecordCastAura(sid, name, icon, exp - dur, dur, iid, apps)
        end
    end
    return nil, false
end

local function CheckWatchedBlizzInstances()
    local changed = false
    for cdID in pairs(_watchedCooldownIDs) do
        local blizz = FindBlizzItem(cdID)
        local hasInst = (blizz and blizz.auraDataUnit ~= "target" and sfui.common.HasAuraInstanceID(blizz.auraInstanceID)) and true or false
        if _lastBlizzHasInstance[cdID] ~= hasInst then
            _lastBlizzHasInstance[cdID] = hasInst
            changed = true
        end
    end
    return changed
end

local function CheckCombatExpirations(now)
    local changed = false
    local camelot = sfui.tracking.camelot
    if _watchSeals and camelot and camelot.CheckSealExpiration and camelot.CheckSealExpiration(now) then
        changed = true
    end
    for i = 1, #_castAurasList do
        local entry = _castAurasList[i]
        if entry.active and entry.expirationTime and entry.expirationTime > 0 and now >= entry.expirationTime then
            entry.active = false
            if entry.auraInstanceID then
                _watchedByInstanceID[entry.auraInstanceID] = nil
                entry.auraInstanceID = nil
            end
            EnsureDurationObj(entry, nil, nil)
            changed = true
        end
    end
    if CheckWatchedBlizzInstances() then
        changed = true
    end
    return changed
end

-- full watched-only resync (entering world, leaving combat, watchlist changes, or isFullUpdate)
local _seenEntries = {}
local function SyncFullPlayerBuffs()
    local now = GetTime()
    if not CanAccessUnitAuras() then
        return CheckCombatExpirations(now)
    end
    if not C_UnitAuras then return false end

    local changed = CheckWatchedBlizzInstances()
    wipe(_seenEntries)
    wipe(_watchedByInstanceID)

    local camelot = sfui.tracking.camelot
    if _watchSeals and camelot and C_UnitAuras.GetAuraDataByIndex then
        local foundSeal = nil
        local checkIndexSecret = C_Secrets and C_Secrets.ShouldUnitAuraIndexBeSecret
        for i = 1, 40 do
            if not (checkIndexSecret and checkIndexSecret("player", i, "HELPFUL")) then
                local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
                if not aura then break end
                local name = A.PlainField(aura, "name")
                local sid = A.PlainField(aura, "spellId")
                if camelot.IsSealName(name) then
                    foundSeal = aura
                end
                if (sid and _watchedSpellIDs[sid]) or (name and _watchedNames[name]) then
                    local entry, entryChanged = UpdateFromReadableAura(aura, now)
                    if entry then _seenEntries[entry] = true end
                    if entryChanged then changed = true end
                end
            end
        end
        if camelot.SyncSealFromFullScan(foundSeal, now) then
            changed = true
        end
    else
        -- zero-scan path: query only explicitly watched spell ids and names
        local getBySpellID = C_UnitAuras.GetPlayerAuraBySpellID
        local checkSpellSecret = C_Secrets and C_Secrets.ShouldSpellAuraBeSecret
        wipe(_seenAuraNames)
        if getBySpellID then
            for sid in pairs(_watchedSpellIDs) do
                if not (checkSpellSecret and checkSpellSecret(sid)) then
                    local aura = getBySpellID(sid)
                    if aura then
                        local entry, entryChanged = UpdateFromReadableAura(aura, now)
                        if entry then
                            _seenEntries[entry] = true
                            if entry.name then _seenAuraNames[entry.name] = true end
                        end
                        if entryChanged then changed = true end
                    end
                end
            end
        end
        local getByName = C_UnitAuras.GetAuraDataBySpellName
        if getByName then
            for name in pairs(_watchedNames) do
                if not _seenAuraNames[name] then
                    _seenAuraNames[name] = true
                    local aura = getByName("player", name, "HELPFUL|PLAYER") or getByName("player", name, "HELPFUL")
                    if aura then
                        local entry, entryChanged = UpdateFromReadableAura(aura, now)
                        if entry then _seenEntries[entry] = true end
                        if entryChanged then changed = true end
                    end
                end
            end
        end
    end

    for i = 1, #_castAurasList do
        local entry = _castAurasList[i]
        if entry.active and not _seenEntries[entry] then
            entry.active = false
            entry.auraInstanceID = nil
            EnsureDurationObj(entry, nil, nil)
            changed = true
        end
    end

    return changed
end

-- incremental UNIT_AURA handler mirroring CooldownViewerMixin:OnUnitAura
local function OnUnitAura(_event, _unit, updateInfo)
    if _watchCount == 0 then return end
    local now = GetTime()

    if not CanAccessUnitAuras() then
        if CheckCombatExpirations(now) then
            NotifyTrackingDirty()
        end
        return
    end

    if not updateInfo or issecretvalue(updateInfo) or A.PlainField(updateInfo, "isFullUpdate") then
        if SyncFullPlayerBuffs() then
            NotifyTrackingDirty()
        end
        return
    end

    local changed = CheckWatchedBlizzInstances()
    local camelot = sfui.tracking.camelot

    local removed = A.PlainField(updateInfo, "removedAuraInstanceIDs")
    if removed then
        for i = 1, #removed do
            local iid = removed[i]
            if iid and not issecretvalue(iid) then
                local entry = _watchedByInstanceID[iid]
                if entry then
                    _watchedByInstanceID[iid] = nil
                    entry.active = false
                    entry.auraInstanceID = nil
                    EnsureDurationObj(entry, nil, nil)
                    changed = true
                end
                if _watchSeals and camelot and camelot.OnAuraRemoved and camelot.OnAuraRemoved(iid) then
                    changed = true
                end
            end
        end
    end

    local updated = A.PlainField(updateInfo, "updatedAuraInstanceIDs")
    if updated and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
        for i = 1, #updated do
            local iid = updated[i]
            if iid and not issecretvalue(iid) then
                local entry = _watchedByInstanceID[iid]
                local isSeal = _watchSeals and camelot and camelot.IsActiveSealInstance and camelot.IsActiveSealInstance(iid)
                if entry or isSeal then
                    local aura = C_UnitAuras.GetAuraDataByAuraInstanceID("player", iid)
                    if aura then
                        if isSeal and camelot.UpdateFromAuraData(aura, now) then
                            changed = true
                        end
                        if entry then
                            local _, entryChanged = UpdateFromReadableAura(aura, now)
                            if entryChanged then changed = true end
                        end
                    else
                        if entry then
                            _watchedByInstanceID[iid] = nil
                            entry.active = false
                            entry.auraInstanceID = nil
                            EnsureDurationObj(entry, nil, nil)
                            changed = true
                        end
                        if isSeal and camelot.OnAuraRemoved(iid) then
                            changed = true
                        end
                    end
                end
            end
        end
    end

    local added = A.PlainField(updateInfo, "addedAuras")
    if added then
        for i = 1, #added do
            local aura = added[i]
            if aura and not issecretvalue(aura) then
                local name = A.PlainField(aura, "name")
                local sid = A.PlainField(aura, "spellId")
                if _watchSeals and camelot and camelot.IsSealName(name) then
                    if camelot.UpdateFromAuraData(aura, now) then
                        changed = true
                    end
                end
                if (sid and _watchedSpellIDs[sid]) or (name and _watchedNames[name]) then
                    local _, entryChanged = UpdateFromReadableAura(aura, now)
                    if entryChanged then
                        changed = true
                    end
                end
            end
        end
    end

    if changed then
        NotifyTrackingDirty()
    end
end

local function OnUnitSpellCastSucceeded(_event, _unit, _castGUID, spellID)
    if _watchCount == 0 then return end
    if not spellID or issecretvalue(spellID) or type(spellID) ~= "number" or spellID <= 0 then
        return
    end

    local name = GetCachedSpellName(spellID)
    local now = GetTime()
    local camelot = sfui.tracking.camelot

    if _watchSeals and camelot and camelot.OnSpellCastSucceeded then
        local icon = GetCachedSpellTexture(spellID)
        if camelot.OnSpellCastSucceeded(spellID, name, icon, now) then
            NotifyTrackingDirty()
            return
        end
    end

    if not _watchedSpellIDs[spellID] and not (name and _watchedNames[name]) then
        return
    end

    local dur = _learnedDurations[spellID]
        or (name and _learnedDurations[name])
        or (sfui.common and sfui.common.GetAuraDefaultDuration and sfui.common.GetAuraDefaultDuration(spellID))
    if dur and dur > 0 then
        local icon = GetCachedSpellTexture(spellID)
        RecordCastAura(spellID, name, icon, now, dur, nil, 1)
        NotifyTrackingDirty()
    end
end

local function OnFullSyncEvent()
    if _watchCount == 0 then return end
    if SyncFullPlayerBuffs() then
        NotifyTrackingDirty()
    end
end

local function OnAuraDataProviderSwitch(_event, useRealDataProvider)
    if _watchCount == 0 then return end
    wipe(_watchedByInstanceID)
    wipe(_lastBlizzHasInstance)
    if useRealDataProvider then
        SyncFullPlayerBuffs()
    end
    NotifyTrackingDirty()
end

local function UpdateEventSubscriptions(signatureChanged)
    if not sfui.events then return end
    if _watchCount > 0 then
        if not _eventsRegistered then
            _eventsRegistered = true
            sfui.events.RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", OnUnitSpellCastSucceeded)
            sfui.events.RegisterUnitEvent("UNIT_AURA", "player", OnUnitAura)
            sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", OnFullSyncEvent)
            sfui.events.RegisterEvent("PLAYER_REGEN_DISABLED", OnFullSyncEvent)
            sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", OnFullSyncEvent)
            sfui.events.RegisterEvent("AURA_DATA_PROVIDER_SWITCH", OnAuraDataProviderSwitch)
            if SyncFullPlayerBuffs() then
                BumpRevision()
            end
        elseif signatureChanged then
            if SyncFullPlayerBuffs() then
                BumpRevision()
            end
        end
    elseif _eventsRegistered then
        _eventsRegistered = false
        sfui.events.UnregisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", OnUnitSpellCastSucceeded)
        sfui.events.UnregisterUnitEvent("UNIT_AURA", "player", OnUnitAura)
        sfui.events.UnregisterEvent("PLAYER_ENTERING_WORLD", OnFullSyncEvent)
        sfui.events.UnregisterEvent("PLAYER_REGEN_DISABLED", OnFullSyncEvent)
        sfui.events.UnregisterEvent("PLAYER_REGEN_ENABLED", OnFullSyncEvent)
        sfui.events.UnregisterEvent("AURA_DATA_PROVIDER_SWITCH", OnAuraDataProviderSwitch)
        wipe(_watchedByInstanceID)
        wipe(_lastBlizzHasInstance)
        for i = 1, #_castAurasList do
            local entry = _castAurasList[i]
            entry.active = false
            entry.auraInstanceID = nil
            EnsureDurationObj(entry, nil, nil)
        end
        local camelot = sfui.tracking.camelot
        if camelot and camelot.ClearActiveSeal then
            camelot.ClearActiveSeal()
        end
        BumpRevision()
    end
end

local function RebuildCombinedWatchlist()
    _watchedSpellIDs, _prevWatchedSpellIDs = _prevWatchedSpellIDs, _watchedSpellIDs
    _watchedNames, _prevWatchedNames = _prevWatchedNames, _watchedNames
    _watchedCooldownIDs, _prevWatchedCooldowns = _prevWatchedCooldowns, _watchedCooldownIDs
    wipe(_watchedSpellIDs)
    wipe(_watchedNames)
    wipe(_watchedCooldownIDs)

    local spellCount, nameCount, cdCount = 0, 0, 0
    local membershipChanged = false

    for sid in pairs(_iconWatchedSpells) do
        _watchedSpellIDs[sid] = true
        spellCount = spellCount + 1
        if not _prevWatchedSpellIDs[sid] then membershipChanged = true end
    end
    for sid in pairs(_barWatchedSpells) do
        if not _watchedSpellIDs[sid] then
            _watchedSpellIDs[sid] = true
            spellCount = spellCount + 1
            if not _prevWatchedSpellIDs[sid] then membershipChanged = true end
        end
    end
    for name in pairs(_iconWatchedNames) do
        _watchedNames[name] = true
        nameCount = nameCount + 1
        if not _prevWatchedNames[name] then membershipChanged = true end
    end
    for name in pairs(_barWatchedNames) do
        if not _watchedNames[name] then
            _watchedNames[name] = true
            nameCount = nameCount + 1
            if not _prevWatchedNames[name] then membershipChanged = true end
        end
    end
    for cdID in pairs(_iconWatchedCooldowns) do
        _watchedCooldownIDs[cdID] = true
        cdCount = cdCount + 1
        if not _prevWatchedCooldowns[cdID] then membershipChanged = true end
    end
    for cdID in pairs(_barWatchedCooldowns) do
        if not _watchedCooldownIDs[cdID] then
            _watchedCooldownIDs[cdID] = true
            cdCount = cdCount + 1
            if not _prevWatchedCooldowns[cdID] then membershipChanged = true end
        end
    end

    local prevSeals = _watchSeals
    _watchSeals = _iconWatchSeals or _barWatchSeals

    if spellCount ~= _watchedSpellCount or nameCount ~= _watchedNameCount or cdCount ~= _watchedCooldownCount or prevSeals ~= _watchSeals then
        membershipChanged = true
    end
    _watchedSpellCount = spellCount
    _watchedNameCount = nameCount
    _watchedCooldownCount = cdCount

    _watchCount = _iconWatchCount + _barWatchCount
    UpdateEventSubscriptions(membershipChanged)
end

local function AddCandidatesToSet(candidates, spellSet, nameSet)
    if not candidates then return end
    for i = 1, #candidates do
        local cid = candidates[i]
        if cid and not issecretvalue(cid) and cid > 0 then
            spellSet[cid] = true
            local cname = GetCachedSpellName(cid)
            if cname then
                nameSet[cname] = true
            end
        end
    end
end

function A.SetIconWatchlist(descriptors)
    wipe(_iconWatchedSpells)
    wipe(_iconWatchedNames)
    wipe(_iconWatchedCooldowns)
    _iconWatchSeals = false
    _iconWatchCount = 0

    if descriptors then
        for i = 1, #descriptors do
            local desc = descriptors[i]
            if desc and (desc.wantsAura or desc.trackBuffs or desc.glowWhenMissing) then
                _iconWatchCount = _iconWatchCount + 1
                if desc.isForeverSeal then
                    _iconWatchSeals = true
                end
                if desc.cooldownID then
                    _iconWatchedCooldowns[desc.cooldownID] = true
                end
                AddCandidatesToSet(desc.auraCandidates, _iconWatchedSpells, _iconWatchedNames)
            end
        end
    end

    RebuildCombinedWatchlist()
end

function A.SetBarWatchlist(barEntries)
    wipe(_barWatchedSpells)
    wipe(_barWatchedNames)
    wipe(_barWatchedCooldowns)
    _barWatchSeals = false
    _barWatchCount = 0

    if barEntries then
        for i = 1, #barEntries do
            local b = barEntries[i]
            if b then
                _barWatchCount = _barWatchCount + 1
                if b.isForeverSeal then
                    _barWatchSeals = true
                end
                if b.cooldownID then
                    _barWatchedCooldowns[b.cooldownID] = true
                end
                AddCandidatesToSet(b.candidates, _barWatchedSpells, _barWatchedNames)
            end
        end
    end

    RebuildCombinedWatchlist()
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
                _watchedByInstanceID[entry.auraInstanceID] = nil
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
    local camelot = sfui.tracking.camelot
    if camelot and camelot.GetActiveSealForCandidates then
        local seal = camelot.GetActiveSealForCandidates(cooldownID, candidates)
        if seal then
            return seal.auraInstanceID, seal, true
        end
    end
    local castAura = GetActiveCastAuraForCandidates(candidates)
    if castAura then
        return castAura.auraInstanceID, castAura, true
    end
    return nil, nil, false
end

-- returns auraInstanceID, auraData, present
function A.Resolve(cooldownID, candidates)
    local canAccess = CanAccessUnitAuras()

    -- 1. hidden blizzard viewer item (O(1) weak-cached lookup)
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
    local checkSpellSecret = C_Secrets and C_Secrets.ShouldSpellAuraBeSecret
    if getBySpellID then
        for i = 1, #candidates do
            local cid = candidates[i]
            if not (checkSpellSecret and checkSpellSecret(cid)) then
                local aura = getBySpellID(cid)
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
    end

    -- 3. by name: classic ranks share a name but not a spell id (rank 1..n)
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

    -- 4. combat-safe cast / incremental seal snapshot tracker
    return ResolveCombatFallback(cooldownID, candidates)
end

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

function A.IsEnabled()
    return _eventsRegistered
end

function A.Enable()
    if _eventsRegistered and SyncFullPlayerBuffs() then
        BumpRevision()
    end
end

function A.GetWatchCount()
    return _watchCount
end
