local addonName, addon = ...
sfui = sfui or {}
sfui.tracking = sfui.tracking or {}
sfui.tracking.entry = sfui.tracking.entry or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/tracking/entry.lua
--  canonical tracking entry normalization, cooldown info cache, and static
--  per-icon descriptors (`icon._desc`) compiled once per config/layout revision.
-- ══════════════════════════════════════════════════════════════════════════════

local E = sfui.tracking.entry

local C_CooldownViewer = C_CooldownViewer
local wipe = wipe or table.wipe
local tonumber = tonumber
local type = type
local issecretvalue = sfui.common.issecretvalue
local IsValidTexture = sfui.common.is_valid_texture or function(tex)
    if issecretvalue(tex) then return true end
    return tex ~= nil and tex ~= 0 and tex ~= ""
end

local _cdInfoCache = {}
local _cdInfoCacheCount = 0
local _configRev = 1

function E.InvalidateCooldownInfoCache()
    wipe(_cdInfoCache)
    _cdInfoCacheCount = 0
end

function E.GetCooldownInfoCacheCount()
    return _cdInfoCacheCount
end

function E.BumpConfigRevision()
    _configRev = _configRev + 1
end

function E.GetConfigRevision()
    return _configRev
end

function E.SafeGetCooldownInfo(id)
    if not id or issecretvalue(id) or not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCooldownInfo then
        return nil
    end
    local cid = tonumber(id)
    if cid and cid >= -2147483648 and cid <= 2147483647 then
        local cached = _cdInfoCache[cid]
        if cached == nil then
            _cdInfoCacheCount = _cdInfoCacheCount + 1
            if _cdInfoCacheCount > 500 then
                wipe(_cdInfoCache)
                _cdInfoCacheCount = 1
            end
            local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cid)
            cached = info or false
            _cdInfoCache[cid] = cached
        end
        return cached or nil
    end
    return nil
end

function E.IsItemCooldownInfo(entry, cdInfo)
    if type(entry) == "table" then
        if entry.equipSlot ~= nil or entry.spellCategoryID ~= nil or (entry.itemID and entry.itemID > 0) or entry.type == "item" then
            return true
        end
    end
    if cdInfo then
        if cdInfo.equipSlot ~= nil or cdInfo.spellCategoryID ~= nil or (cdInfo.itemID and cdInfo.itemID > 0) then
            return true
        end
    end
    return false
end

function E.GetEntryCooldownID(entry, fallbackID)
    if type(entry) == "table" then
        local cid = entry.cooldownID
        if cid and not issecretvalue(cid) then
            return tonumber(cid)
        end
        if entry.type == "cooldown" and entry.id and not issecretvalue(entry.id) then
            return tonumber(entry.id)
        end
    end
    if fallbackID and not issecretvalue(fallbackID) then
        return tonumber(fallbackID)
    end
    return nil
end

function E.IsForeverSeal(entry, cdInfo, activeSpellID)
    if not sfui.isCamelot then return false end
    local camelot = sfui.tracking.camelot
    if camelot and camelot.IsForeverSealEntry then
        return camelot.IsForeverSealEntry(entry, cdInfo, activeSpellID)
    end
    local auras = sfui.tracking.auras
    if auras and auras.IsForeverSealEntry then
        return auras.IsForeverSealEntry(entry, cdInfo, activeSpellID)
    end
    return false
end

-- canonicalize a saved/seeded/dragged tracking entry table in-place
function E.NormalizeEntry(raw, cdInfo, defaultSettings)
    local entry
    if type(raw) == "table" then
        entry = raw
    else
        entry = { id = raw, type = "spell" }
    end

    local cdID = E.GetEntryCooldownID(entry)
    if not cdInfo and cdID then
        cdInfo = E.SafeGetCooldownInfo(cdID)
    end

    local isItem = E.IsItemCooldownInfo(entry, cdInfo)
    if cdID then
        entry.cooldownID = cdID
        entry.type = isItem and "item" or "cooldown"
    elseif isItem then
        entry.type = "item"
    elseif not entry.type then
        entry.type = "spell"
    end

    if cdInfo then
        if entry.equipSlot == nil and cdInfo.equipSlot ~= nil then
            entry.equipSlot = cdInfo.equipSlot
        end
        if entry.spellCategoryID == nil and cdInfo.spellCategoryID ~= nil then
            entry.spellCategoryID = cdInfo.spellCategoryID
        end
        if not entry.spellID and cdInfo.spellID and cdInfo.spellID > 0 then
            entry.spellID = cdInfo.spellID
        end
        if not entry.itemID and cdInfo.itemID and cdInfo.itemID > 0 then
            entry.itemID = cdInfo.itemID
        end
    end

    if defaultSettings and not entry.settings then
        entry.settings = {}
        for k, v in pairs(defaultSettings) do
            entry.settings[k] = v
        end
    end

    if not isItem and E.IsForeverSeal(entry, cdInfo) then
        entry.settings = entry.settings or { textEnabled = true, showText = true }
        if entry.settings.trackBuffs == nil then
            entry.settings.trackBuffs = true
        end
    end

    return entry
end

-- resolves effective `trackBuffs` boolean for an entry across entry -> forever seal -> panel -> global
function E.ShouldTrackBuffs(entry, panelConfig, cdInfo, activeSpellID, getIconValueFn)
    local settings = (type(entry) == "table" and entry.settings) or nil
    if settings and settings.trackBuffs ~= nil then
        return settings.trackBuffs == true
    end
    if E.IsForeverSeal(entry, cdInfo, activeSpellID) then
        return true
    end
    if getIconValueFn then
        return getIconValueFn(settings, panelConfig, "trackBuffs", false) == true
    end
    if panelConfig and panelConfig.trackBuffs ~= nil then
        return panelConfig.trackBuffs == true
    end
    local igs = SfuiDB and SfuiDB.iconGlobalSettings
    if igs and igs.trackBuffs ~= nil then
        return igs.trackBuffs == true
    end
    local def = sfui.config and sfui.config.icon_panel_global_defaults
    if def and def.trackBuffs ~= nil then
        return def.trackBuffs == true
    end
    return false
end

-- compiles (or returns cached) static per-icon metadata descriptor `icon._desc`
function E.CompileDescriptor(icon, panelConfig, getIconValueFn, getIconTextureFn)
    local desc = icon._desc
    if desc
        and desc._configRev == _configRev
        and desc.entry == icon.entry
        and desc.id == icon.id
        and desc.panelConfig == panelConfig
        and not desc._iconCold
        and IsValidTexture(icon._currentTexture)
        and (not icon.texture or IsValidTexture(icon.texture:GetTexture())) then
        return desc
    end

    if not desc then
        desc = {}
        icon._desc = desc
    end

    local entry = icon.entry
    local settings = (entry and entry.settings) or nil
    local cdID = E.GetEntryCooldownID(entry, (icon.type == "cooldown" and icon.id) or nil)
    local cdInfo = cdID and E.SafeGetCooldownInfo(cdID) or nil
    local iconTexture, aID, rType, lIDs, isColdIcon = getIconTextureFn(icon.id, icon.type, entry, cdInfo)

    local activeID = aID or icon.id
    local resolvedType = rType or icon.type
    local isItem = (resolvedType == "item" or icon.type == "item")
    local isAuraType = (icon.type == "buff" or icon.type == "debuff"
        or (entry and (entry.type == "buff" or entry.type == "debuff"))) and true or false

    local linkedSpellIDs = lIDs or (cdInfo and cdInfo.linkedSpellIDs) or nil

    icon._lastActiveID = activeID
    icon._resolvedType = resolvedType
    icon._linkedSpellIDs = linkedSpellIDs
    if icon.texture and IsValidTexture(iconTexture) then
        if icon._currentTexture ~= iconTexture or not IsValidTexture(icon.texture:GetTexture()) then
            icon.texture:SetTexture(iconTexture)
            icon._currentTexture = iconTexture
        end
    end
    desc._iconCold = (isColdIcon == true)

    local auras = sfui.tracking.auras
    local isForeverSeal = false
    local isCoverSpell = false
    if sfui.isCamelot and not isItem then
        isForeverSeal = E.IsForeverSeal(entry, cdInfo, activeID)
        if isForeverSeal and auras and auras.IsCoverSpell then
            isCoverSpell = auras.IsCoverSpell(cdInfo, cdID, activeID)
        end
    end

    local trackBuffs = false
    if not isItem and activeID and activeID ~= 0 then
        trackBuffs = E.ShouldTrackBuffs(entry, panelConfig, cdInfo, activeID, getIconValueFn)
    end

    local wantsAura = false
    if trackBuffs and auras and auras.WantsAura then
        local forceEntryAura = (settings and settings.trackBuffs == true) or isAuraType or
            (not cdInfo and trackBuffs == true)
        wantsAura = isForeverSeal or auras.WantsAura(cdInfo, forceEntryAura, linkedSpellIDs, activeID, cdID)
    end

    local glowWhenMissing = (not isItem) and (settings and settings.glowWhenMissing == true)
        and (sfui.isRetail or sfui.isCamelot or (sfui.isEra and sfui.tracking.FindClassicAura ~= nil)) or false

    desc._configRev = _configRev
    desc._rebuilt = true
    desc.id = icon.id
    desc.entry = entry
    desc.panelConfig = panelConfig
    desc.settings = settings
    desc.activeID = activeID
    desc.resolvedType = resolvedType
    desc.isItem = isItem
    desc.isAuraType = isAuraType
    desc.cooldownID = cdID
    desc.cdInfo = cdInfo
    desc.equipSlot = (entry and entry.equipSlot) or (cdInfo and cdInfo.equipSlot) or nil
    desc.spellCategoryID = (entry and entry.spellCategoryID) or (cdInfo and cdInfo.spellCategoryID) or nil
    local itemID = entry and entry.itemID
    if itemID == cdID then itemID = nil end
    if not itemID and cdInfo and cdInfo.itemID and cdInfo.itemID > 0 then
        itemID = cdInfo.itemID
    end
    desc.itemID = itemID
    desc.linkedSpellIDs = linkedSpellIDs
    desc.isForeverSeal = isForeverSeal
    desc.isCoverSpell = isCoverSpell
    desc.trackBuffs = trackBuffs
    desc.wantsAura = wantsAura
    desc.glowWhenMissing = glowWhenMissing

    if (wantsAura or trackBuffs or glowWhenMissing) and auras and auras.GetCandidates then
        desc.auraCandidates = auras.GetCandidates(icon, activeID, linkedSpellIDs, cdInfo)
    else
        desc.auraCandidates = nil
    end

    return desc
end
