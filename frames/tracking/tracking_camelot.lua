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
local C_SpellBook = _G.C_SpellBook
local C_UnitAuras = C_UnitAuras
local Enum = _G.Enum
local GetTime = GetTime
local next = next
local string_lower = string.lower
local tonumber = tonumber
local type = type
local wipe = wipe or table.wipe
local issecretvalue = sfui.common.issecretvalue

local BANK_PLAYER = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
local ITEM_SPELL = (Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell) or 1
local ITEM_FLYOUT = (Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Flyout) or 3

local SEAL_SEEDS = {
    20154, 21084,   -- seal of righteousness
    21082,          -- seal of the crusader
    20375,          -- seal of command
    20164,          -- seal of justice
    20165,          -- seal of light
    20166,          -- seal of wisdom
    20163, 1311649, -- seal of fury (classic + forever)
}

C.SEALS_COOLDOWN_ID = 200340
C.SEALS_COOLDOWN_ID_HOLY = 200339
C.SEALS_SPELL_ID = 1323522
C.DEFAULT_SEAL_DURATION = 30

local SEAL_DEFS = {
    {
        key = "righteousness",
        label = "seal of righteousness",
        spellID = 20154,
        spellIDs = { 20154, 21084, 20287, 20288, 20289, 20290, 20291, 20292, 20293 },
        icon = 132325,
        defaultColor = { 1.00, 0.82, 0.18, 1 },
    },
    {
        key = "crusader",
        label = "seal of the crusader",
        spellID = 21082,
        spellIDs = { 21082, 20162, 20305, 20306, 20307, 20308 },
        icon = 135924,
        defaultColor = { 1.00, 0.56, 0.14, 1 },
    },
    {
        key = "command",
        label = "seal of command",
        spellID = 20375,
        spellIDs = { 20375, 20915, 20918, 20919, 20920 },
        icon = 132347,
        defaultColor = { 0.90, 0.22, 0.26, 1 },
    },
    {
        key = "justice",
        label = "seal of justice",
        spellID = 20164,
        spellIDs = { 20164 },
        icon = 135971,
        defaultColor = { 0.72, 0.36, 0.95, 1 },
    },
    {
        key = "light",
        label = "seal of light",
        spellID = 20165,
        spellIDs = { 20165, 20347, 20348, 20349 },
        icon = 135917,
        defaultColor = { 0.28, 0.88, 0.48, 1 },
    },
    {
        key = "wisdom",
        label = "seal of wisdom",
        spellID = 20166,
        spellIDs = { 20166, 20356, 20357 },
        icon = 135960,
        defaultColor = { 0.24, 0.62, 1.00, 1 },
    },
    {
        key = "fury",
        label = "seal of fury",
        spellID = 1311649,
        spellIDs = { 1311649, 20163 },
        icon = 135969,
        defaultColor = { 0.96, 0.38, 0.12, 1 },
    },
}

local _sealDefByKey = {}
local _sealKeyBySpellID = {}
local _sealKeyByLowerName = {}
local _sealKeyByRawName = {}
local _sealKeyByIcon = {}

for i = 1, #SEAL_DEFS do
    local def = SEAL_DEFS[i]
    _sealDefByKey[def.key] = def
    _sealKeyByLowerName[def.label] = def.key
    _sealKeyByIcon[def.icon] = def.key
    for j = 1, #def.spellIDs do
        _sealKeyBySpellID[def.spellIDs[j]] = def.key
    end
end

local _knownSealSpellIDs = {}
local _knownSealSpellList = {}
local _knownSealsDirty = true
local _knownSealsRev = 1
local _sealBookEventsRegistered = false

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

local function AddKnownSealID(sid)
    if sid and not issecretvalue(sid) and type(sid) == "number" and sid > 0 and not _knownSealSpellIDs[sid] then
        _knownSealSpellIDs[sid] = true
        _knownSealSpellList[#_knownSealSpellList + 1] = sid
    end
end

local function RecordSealAndOverride(sid)
    if not sid or issecretvalue(sid) or type(sid) ~= "number" or sid <= 0 then
        return
    end
    AddKnownSealID(sid)
    if C_Spell and C_Spell.GetOverrideSpell then
        local oid = C_Spell.GetOverrideSpell(sid)
        AddKnownSealID(oid)
    end
end

local function InvalidateKnownSeals()
    _knownSealsDirty = true
    _knownSealsRev = _knownSealsRev + 1
end

local function EnsureSealBookEvents()
    if _sealBookEventsRegistered or not (sfui.events and sfui.events.RegisterEvent) then
        return
    end
    _sealBookEventsRegistered = true
    sfui.events.RegisterEvent("SPELLS_CHANGED", InvalidateKnownSeals)
    sfui.events.RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE", InvalidateKnownSeals)
    sfui.events.RegisterEvent("TRAIT_CONFIG_UPDATED", InvalidateKnownSeals)
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", InvalidateKnownSeals)
end

local function ResolveItemSpellName(spellID, rawName)
    if rawName and not issecretvalue(rawName) and type(rawName) == "string" and rawName ~= "" then
        return rawName
    end
    return A and A.GetCachedSpellName and A.GetCachedSpellName(spellID) or nil
end

local function EnsureKnownSeals()
    EnsureSealBookEvents()
    if not _knownSealsDirty then
        return
    end
    wipe(_knownSealSpellIDs)
    wipe(_knownSealSpellList)

    local numLines = (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetNumSpellBookSkillLines()) or 0
    if C_SpellBook and C_SpellBook.GetSpellBookSkillLineInfo and C_SpellBook.GetSpellBookItemInfo then
        for line = 1, numLines do
            local li = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if li and not li.shouldHide and not li.isGuild then
                local offset = li.itemIndexOffset or 0
                local numItems = li.numSpellBookItems or 0
                for idx = 1, numItems do
                    local info = C_SpellBook.GetSpellBookItemInfo(offset + idx, BANK_PLAYER)
                    if info and not info.isPassive then
                        if info.itemType == ITEM_SPELL then
                            local itemName = ResolveItemSpellName(info.spellID or info.actionID, info.name)
                            if C.IsSealName(itemName) then
                                RecordSealAndOverride(info.spellID)
                                RecordSealAndOverride(info.actionID)
                            end
                        elseif info.itemType == ITEM_FLYOUT and info.actionID and not issecretvalue(info.actionID) then
                            local getFlyoutInfo = _G.GetFlyoutInfo
                            local getFlyoutSlotInfo = _G.GetFlyoutSlotInfo
                            if getFlyoutInfo and getFlyoutSlotInfo then
                                local _, _, numSlots, isFlyoutKnown = getFlyoutInfo(info.actionID)
                                if isFlyoutKnown and type(numSlots) == "number" and numSlots > 0 then
                                    for fSlot = 1, numSlots do
                                        local fSpellID, fOverrideID, fIsKnown, fSpellName = getFlyoutSlotInfo(info.actionID, fSlot)
                                        if fIsKnown then
                                            local fName = ResolveItemSpellName(fSpellID, fSpellName)
                                            if C.IsSealName(fName) then
                                                RecordSealAndOverride(fSpellID)
                                                RecordSealAndOverride(fOverrideID)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if numLines > 0 then
        _knownSealsDirty = false
    end
end

function C.IsSealName(name)
    if not name or issecretvalue(name) or type(name) ~= "string" then return false end
    return string.find(name, "^Seal of ") ~= nil
end

function C.GetKnownSealsRev()
    EnsureSealBookEvents()
    return _knownSealsRev
end

function C.AppendKnownSealCandidates(addFn, list, seen)
    if not addFn or not list or not seen then return end
    EnsureKnownSeals()
    for i = 1, #SEAL_SEEDS do
        addFn(list, seen, SEAL_SEEDS[i])
    end
    for i = 1, #_knownSealSpellList do
        addFn(list, seen, _knownSealSpellList[i])
    end
end

function C.IsCastableSealSpell(spellID, name)
    if not spellID or issecretvalue(spellID) or type(spellID) ~= "number" or spellID <= 0 then
        return false
    end
    if spellID == C.SEALS_SPELL_ID then
        return true
    end
    local resolvedName = name or (A and A.GetCachedSpellName and A.GetCachedSpellName(spellID))
    if not C.IsSealName(resolvedName) then
        return false
    end
    EnsureKnownSeals()
    if next(_knownSealSpellIDs) ~= nil then
        return _knownSealSpellIDs[spellID] == true
    end
    if C_SpellBook then
        if C_SpellBook.IsSpellInSpellBook and C_SpellBook.IsSpellInSpellBook(spellID, BANK_PLAYER, true) then
            return true
        end
        if C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(spellID, BANK_PLAYER) then
            return true
        end
    end
    return false
end

function C.IsCoverSpell(cdInfo, cooldownID, spellID)
    local cid = cooldownID or (cdInfo and cdInfo.cooldownID)
    if cid and not issecretvalue(cid) and (cid == C.SEALS_COOLDOWN_ID or cid == C.SEALS_COOLDOWN_ID_HOLY) then
        return true
    end
    local sid = spellID or (cdInfo and (cdInfo.overrideSpellID or cdInfo.spellID))
    if sid and not issecretvalue(sid) and sid == C.SEALS_SPELL_ID then
        return true
    end
    return false
end

local function MatchSealName(name)
    if not name or issecretvalue(name) or type(name) ~= "string" or name == "" then
        return nil
    end
    local cached = _sealKeyByRawName[name]
    if cached ~= nil then
        return cached or nil
    end
    local resolved = _sealKeyByLowerName[string_lower(name)]
    _sealKeyByRawName[name] = resolved or false
    return resolved
end

function C.GetSealDefs()
    return SEAL_DEFS
end

function C.GetSealDef(sealKey)
    if not sealKey or issecretvalue(sealKey) then return nil end
    return _sealDefByKey[sealKey]
end

function C.ResolveSealKey(spellID, name, icon)
    local validSID = (spellID and not issecretvalue(spellID) and type(spellID) == "number" and spellID > 0) and spellID or nil
    if validSID and _sealKeyBySpellID[validSID] then
        return _sealKeyBySpellID[validSID]
    end

    local key = MatchSealName(name)
    if not key and validSID and A and A.GetCachedSpellName then
        key = MatchSealName(A.GetCachedSpellName(validSID))
    end
    if not key and icon and not issecretvalue(icon) then
        key = _sealKeyByIcon[icon]
    end

    if key and validSID then
        _sealKeyBySpellID[validSID] = key
    end
    return key
end

function C.GetSealColor(sealKey)
    if not sealKey or issecretvalue(sealKey) then
        return nil, false
    end
    local dbCols = SfuiDB and SfuiDB.trackedBars and SfuiDB.trackedBars.sealColors
    local custom = dbCols and dbCols[sealKey]
    if type(custom) == "table" then
        return custom, true
    end
    local cfgCols = sfui.config and sfui.config.trackedBars and sfui.config.trackedBars.sealColors
    local cfgCol = cfgCols and cfgCols[sealKey]
    if type(cfgCol) == "table" then
        return cfgCol, false
    end
    local def = _sealDefByKey[sealKey]
    return def and def.defaultColor or nil, false
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
    if A.PlainField(aura, "isHarmful") == true then return false end
    local src = A.PlainField(aura, "sourceUnit")
    if src and src ~= "player" then return false end
    local sid = A.PlainField(aura, "spellId")
    local name = A.PlainField(aura, "name")
    if not C.IsSealName(name) then return false end
    if _activeSeal.active and sid and not C.IsCastableSealSpell(sid, name)
        and C.IsCastableSealSpell(_activeSeal.spellID, _activeSeal.name) then
        return false
    end

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
    if not C.IsCastableSealSpell(spellID, name) then
        return false
    end
    local resolvedName = name or (A and A.GetCachedSpellName and A.GetCachedSpellName(spellID))
    local dur = (A and A.GetLearnedDuration(spellID, resolvedName)) or C.DEFAULT_SEAL_DURATION
    _activeSeal.active = true
    _activeSeal.spellID = spellID
    _activeSeal.name = resolvedName
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

    if cooldownID == C.SEALS_COOLDOWN_ID or cooldownID == C.SEALS_COOLDOWN_ID_HOLY or A.HasCandidate(candidates, C.SEALS_SPELL_ID) then
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

