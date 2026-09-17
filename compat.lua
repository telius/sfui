local addonName, addon = ...
sfui = sfui or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/compat.lua
--  Client version detection + unified sfui.api routing layer.
--
--  Loaded immediately after config.lua, before dispatcher.lua and common.lua.
--  All modules MUST call sfui.api.* instead of raw C_* APIs for anything
--  that is not universally available across all supported clients.
--
--  Adding a new client:
--    1. Add a detection flag in the "Version detection" block below.
--    2. Add a branch in every sfui.api.* function that needs different behaviour.
--    3. Add a feature-capability flag in sfui.compat.has.*.
--    4. Create sfui_<clientname>.toc loading only the modules that work.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── Raw client detection ──────────────────────────────────────────────────────
-- WOW_PROJECT_ID is set by the game engine before any Lua runs.
--   WOW_PROJECT_MAINLINE (1) -> Retail & Classic Forever Beta
--   WOW_PROJECT_CLASSIC  (2) -> Classic Era / Season of Discovery
local PROJECT_ID = _G.WOW_PROJECT_ID or 1

-- Inspect client version from GetBuildInfo() to accurately distinguish Classic Forever from Retail
local versionStr, buildStr, dateStr, tocVersionNum = _G.GetBuildInfo()
tocVersionNum = tonumber(tocVersionNum) or 0

-- Classic Forever uses WOW_PROJECT_MAINLINE (1), but has tocVersion 16001 (build 1.60.x)
local IS_WOW_FOREVER = (tocVersionNum >= 16000 and tocVersionNum < 20000) or (versionStr and versionStr:match("^1%.60"))
local IS_CLASSIC_ERA = (PROJECT_ID == (_G.WOW_PROJECT_CLASSIC or 2)) and not IS_WOW_FOREVER
local IS_RETAIL      = (PROJECT_ID == (_G.WOW_PROJECT_MAINLINE or 1)) and not IS_WOW_FOREVER

-- Expose on sfui.version so any module can read client context at runtime.
sfui.version = {
    retail      = IS_RETAIL,
    classic_era = IS_CLASSIC_ERA,
    wow_forever = IS_WOW_FOREVER,
    project_id  = PROJECT_ID,
    toc_version = tocVersionNum,
    build       = buildStr,
    version     = versionStr,
}

-- ── Feature capability flags ──────────────────────────────────────────────────
-- Use these in modules instead of raw IS_RETAIL checks — capabilities matter
-- more than the client name (e.g. Warcraft Forever might support some things
-- Classic Era doesn't).
sfui.compat = {
    has = {
        -- Blizzard's C_UnitAuras namespace (retail aura instance IDs)
        unit_auras      = (_G.C_UnitAuras and _G.C_UnitAuras.GetAuraDataByIndex ~= nil),
        -- BuffBarCooldownViewer Blizzard frame (trackedbars.lua depends on this)
        cooldown_viewer = (_G.BuffBarCooldownViewer ~= nil or _G.C_CooldownViewer ~= nil or IS_RETAIL or IS_WOW_FOREVER),
        -- Toybox / toy APIs (portals.lua travel toys)
        toybox          = IS_RETAIL,
        -- Mythic+ / Challenge Mode APIs
        mythic_plus     = IS_RETAIL,
        -- World Quest APIs (C_TaskQuest, C_QuestLog.IsWorldQuest)
        world_quests    = IS_RETAIL,
        -- Scenario / Delve APIs
        scenarios       = IS_RETAIL,
        -- Gear / loot spec APIs (C_Item.DoesItemContainSpec etc.)
        gear_spec       = IS_RETAIL,
        -- C_Spell namespace
        c_spell         = (_G.C_Spell ~= nil),
        -- C_Item namespace
        c_item          = (_G.C_Item ~= nil),
        -- Specialisations (talent trees, specs)
        specializations = IS_RETAIL,
        -- Warcraft Forever specific capability flag
        wow_forever     = IS_WOW_FOREVER,
    },
}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui.api  — Unified API namespace
--
--  Rule: Every function here MUST behave identically from the caller's point
--  of view regardless of client. Return shapes are documented per function.
--  Returning nil/false on unsupported clients is acceptable and expected.
-- ══════════════════════════════════════════════════════════════════════════════
sfui.api = {}

-- ── Aura queries ──────────────────────────────────────────────────────────────

--- Returns a table of aura data for `unit` at position `index` with `filter`.
--- Retail: C_UnitAuras.GetAuraDataByIndex (returns native table).
--- Classic/Forever: synthesises a compatible table from UnitAura().
--- @return table|nil { name, icon, applications, duration, expirationTime, sourceUnit, spellId, isHarmful, auraInstanceID }
function sfui.api.GetAuraData(unit, index, filter)
    if IS_RETAIL then
        return _G.C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
    end
    local name, icon, count, _, duration, expires, source, _, _, spellID =
        _G.UnitAura(unit, index, filter)
    if not name then return nil end
    return {
        name           = name,
        icon           = icon,
        applications   = count,
        duration       = duration,
        expirationTime = expires,
        sourceUnit     = source,
        spellId        = spellID,
        auraInstanceID = nil,   -- not available pre-Retail; callers must guard
        isHarmful      = (filter == "HARMFUL"),
    }
end

--- Searches the player's aura list for a specific spellID.
--- Retail: C_UnitAuras.GetPlayerAuraBySpellID (O(1) hash lookup).
--- Classic/Forever: linear scan via UnitAura loop (capped at 64 auras).
--- @return table|nil same shape as GetAuraData
function sfui.api.GetPlayerAuraBySpellID(spellID)
    if IS_RETAIL then
        return _G.C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    end
    local function scan(filter)
        for i = 1, 64 do
            local name, icon, count, _, duration, expires, source, _, _, sid =
                _G.UnitAura("player", i, filter)
            if not name then break end
            if sid == spellID then
                return {
                    name = name, icon = icon, applications = count,
                    duration = duration, expirationTime = expires,
                    sourceUnit = source, spellId = sid,
                    auraInstanceID = nil,
                    isHarmful = (filter == "HARMFUL"),
                }
            end
        end
    end
    return scan("HELPFUL") or scan("HARMFUL")
end

-- ── Spell queries ─────────────────────────────────────────────────────────────

--- Returns a normalised spell info table.
--- Retail: C_Spell.GetSpellInfo(spellID) -> table.
--- Classic/Forever: GetSpellInfo(spellID) -> 9-tuple, mapped to table.
--- @return table|nil { name, iconID, castTime, minRange, maxRange, spellID }
function sfui.api.GetSpellInfo(spellID)
    if IS_RETAIL then
        return _G.C_Spell.GetSpellInfo(spellID)
    end
    local name, _, icon, castTime, minRange, maxRange, id = _G.GetSpellInfo(spellID)
    if not name then return nil end
    return {
        name     = name,
        iconID   = icon,
        castTime = castTime,
        minRange = minRange,
        maxRange = maxRange,
        spellID  = id or spellID,
    }
end

--- Returns spell name or nil.
function sfui.api.GetSpellName(spellID)
    if IS_RETAIL then return _G.C_Spell.GetSpellName(spellID) end
    local name = _G.GetSpellInfo(spellID)
    return name
end

--- Returns spell texture path or nil.
function sfui.api.GetSpellTexture(spellID)
    if IS_RETAIL then return _G.C_Spell.GetSpellTexture(spellID) end
    local _, _, icon = _G.GetSpellInfo(spellID)
    return icon
end

--- Returns spell cooldown info.
--- @return table|nil { startTime, duration, isEnabled, modRate }
function sfui.api.GetSpellCooldown(spellID)
    if IS_RETAIL then return _G.C_Spell.GetSpellCooldown(spellID) end
    local start, dur, enabled, modRate = _G.GetSpellCooldown(spellID)
    if start == nil then return nil end
    return {
        startTime = start,
        duration  = dur,
        isEnabled = (enabled == 1),
        modRate   = modRate or 1,
    }
end

--- Returns spell charge info or nil if spell has no charges.
--- @return table|nil { currentCharges, maxCharges, cooldownStartTime, cooldownDuration }
function sfui.api.GetSpellCharges(spellID)
    if IS_RETAIL then return _G.C_Spell.GetSpellCharges(spellID) end
    if not _G.GetSpellCharges then return nil end
    local cur, max, start, dur = _G.GetSpellCharges(spellID)
    if not cur then return nil end
    return {
        currentCharges    = cur,
        maxCharges        = max,
        cooldownStartTime = start,
        cooldownDuration  = dur,
    }
end

--- Returns true if the player knows the spell.
function sfui.api.IsSpellKnown(spellID)
    if IS_RETAIL then return _G.C_Spell.IsSpellKnown(spellID) end
    return _G.IsSpellKnown and _G.IsSpellKnown(spellID) or false
end

-- ── Item queries ──────────────────────────────────────────────────────────────

--- Returns item info table.
--- @return table|nil { itemID, itemName, itemLink, itemQuality, itemLevel, itemTexture, sellPrice }
function sfui.api.GetItemInfo(itemID)
    if IS_RETAIL then return _G.C_Item.GetItemInfo(itemID) end
    local name, link, quality, iLevel, _, iType, iSub, _, _, tex, price =
        _G.GetItemInfo(itemID)
    if not name then return nil end
    return {
        itemID      = itemID,
        itemName    = name,
        itemLink    = link,
        itemQuality = quality,
        itemLevel   = iLevel,
        itemType    = iType,
        itemSubType = iSub,
        itemTexture = tex,
        sellPrice   = price,
    }
end

--- Returns item cooldown: startTime, duration, enable.
--- @return number, number, number
function sfui.api.GetItemCooldown(itemID)
    if IS_RETAIL then return _G.C_Item.GetItemCooldown(itemID) end
    return _G.GetItemCooldown(itemID)
end

--- Returns item stack count in player bags.
function sfui.api.GetItemCount(itemID, includeBank, includeCharges)
    if IS_RETAIL then return _G.C_Item.GetItemCount(itemID, includeBank, includeCharges) end
    return _G.GetItemCount(itemID, includeBank, includeCharges)
end

--- Returns item icon texture path.
function sfui.api.GetItemIconByID(itemID)
    if IS_RETAIL then return _G.C_Item.GetItemIconByID(itemID) end
    local _, _, _, _, _, _, _, _, _, tex = _G.GetItemInfo(itemID)
    return tex
end

-- ── Map queries ───────────────────────────────────────────────────────────────

--- Returns the best map ID for a unit (Retail only; nil elsewhere).
function sfui.api.GetBestMapForUnit(unit)
    if IS_RETAIL and _G.C_Map then return _G.C_Map.GetBestMapForUnit(unit) end
    return nil
end

-- ── Retail-only stubs ─────────────────────────────────────────────────────────
-- Modules MUST check sfui.compat.has.* before calling these.

--- Returns current M+ key info (Retail only).
function sfui.api.GetActiveKeystoneInfo()
    if IS_RETAIL and _G.C_ChallengeMode then
        return _G.C_ChallengeMode.GetActiveKeystoneInfo()
    end
    return nil
end

--- Returns current M+ death count and time lost.
--- @return number, number
function sfui.api.GetDeathCount()
    if IS_RETAIL and _G.C_ChallengeMode and _G.C_ChallengeMode.GetDeathCount then
        local count, timeLost = _G.C_ChallengeMode.GetDeathCount()
        return count or 0, timeLost or 0
    end
    return 0, 0
end

--- Returns whether challenge mode is currently active.
--- @return boolean
function sfui.api.IsChallengeModeActive()
    if IS_RETAIL and _G.C_ChallengeMode and _G.C_ChallengeMode.IsChallengeModeActive then
        return _G.C_ChallengeMode.IsChallengeModeActive() or false
    end
    return false
end

-- Canonical Combat Resurrection spell IDs (Rebirth, Raise Ally, Soulstone, Intercession)
local BRES_SPELLS = { 20484, 61999, 20707, 391054 }
local _cachedBresSpellID = 20484
local _staticResInfo = {
    currentCharges    = 0,
    maxCharges        = 0,
    cooldownStartTime = 0,
    cooldownDuration  = 0,
    timeRemaining     = 0,
}

--- Returns combat resurrection charge info for group in encounters/M+.
--- Zero-allocation: reuses an internal static table on every call.
--- @return table|nil { currentCharges, maxCharges, cooldownStartTime, cooldownDuration, timeRemaining }
function sfui.api.GetCombatResInfo()
    if not IS_RETAIL or not _G.C_Spell or not _G.C_Spell.GetSpellCharges then return nil end
    local ok, chargeInfo = pcall(_G.C_Spell.GetSpellCharges, _cachedBresSpellID)
    if not (ok and chargeInfo and (chargeInfo.currentCharges or chargeInfo.maxCharges)) then
        chargeInfo = nil
        for i = 1, #BRES_SPELLS do
            local sid = BRES_SPELLS[i]
            if sid ~= _cachedBresSpellID then
                local ok2, info = pcall(_G.C_Spell.GetSpellCharges, sid)
                if ok2 and info and (info.currentCharges or info.maxCharges) then
                    chargeInfo = info
                    _cachedBresSpellID = sid
                    break
                end
            end
        end
    end
    if not chargeInfo then return nil end

    local cur = chargeInfo.currentCharges
    local max = chargeInfo.maxCharges
    local start = chargeInfo.cooldownStartTime
    local dur = chargeInfo.cooldownDuration

    local timeRem = 0
    if start and dur and dur > 0 then
        local isSecret = false
        if _G.issecretvalue then
            isSecret = _G.issecretvalue(start) or _G.issecretvalue(dur)
        end
        if not isSecret then
            local now = _G.GetTime()
            local finish = start + dur
            if finish > now then
                timeRem = finish - now
            end
        end
    end

    _staticResInfo.currentCharges    = cur
    _staticResInfo.maxCharges        = max
    _staticResInfo.cooldownStartTime = start
    _staticResInfo.cooldownDuration  = dur
    _staticResInfo.timeRemaining     = timeRem
    return _staticResInfo
end


-- ══════════════════════════════════════════════════════════════════════════════
--  WARCRAFT FOREVER EXTENSION POINT
--  ─────────────────────────────────────────────────────────────────────────────
--  When the API lands, add capability flags to sfui.compat.has and either:
--    a) add an elseif IS_WOW_FOREVER branch in the relevant sfui.api functions
--    b) create compat_forever.lua for larger divergences and dofile/load it here
--
--  Template:
--
--  if IS_WOW_FOREVER then
--      sfui.compat.has.cooldown_viewer = (WarcraftForeverCooldownViewer ~= nil)
--      sfui.compat.has.toybox          = (C_ToyBox ~= nil)
--
--      function sfui.api.GetAuraData(unit, index, filter)
--          -- Warcraft Forever implementation
--      end
--  end
-- ══════════════════════════════════════════════════════════════════════════════
