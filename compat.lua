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
--   WOW_PROJECT_MAINLINE (1) -> Retail
--   WOW_PROJECT_CLASSIC  (2) -> Classic Era / Season of Discovery
--   Warcraft Forever     (?) -> TBD — placeholder updated once API lands
local PROJECT_ID = _G.WOW_PROJECT_ID or 1

local IS_RETAIL      = PROJECT_ID == (_G.WOW_PROJECT_MAINLINE or 1)
local IS_CLASSIC_ERA = PROJECT_ID == (_G.WOW_PROJECT_CLASSIC  or 2)

-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │  WARCRAFT FOREVER — API PENDING                                         │
-- │  WOW_PROJECT_ID value and TOC interface number are not yet published.   │
-- │  This flag will be refined when the API drops.                          │
-- │  Current assumption: any project that is not Retail and not Era.        │
-- └─────────────────────────────────────────────────────────────────────────┘
local IS_WOW_FOREVER = (not IS_RETAIL) and (not IS_CLASSIC_ERA)

-- Expose on sfui.version so any module can read client context at runtime.
sfui.version = {
    retail      = IS_RETAIL,
    classic_era = IS_CLASSIC_ERA,
    wow_forever = IS_WOW_FOREVER,
    project_id  = PROJECT_ID,
}

-- ── Feature capability flags ──────────────────────────────────────────────────
-- Use these in modules instead of raw IS_RETAIL checks — capabilities matter
-- more than the client name (e.g. Warcraft Forever might support some things
-- Classic Era doesn't).
sfui.compat = {
    has = {
        -- Blizzard's C_UnitAuras namespace (retail aura instance IDs)
        unit_auras      = IS_RETAIL,
        -- BuffBarCooldownViewer Blizzard frame (trackedbars.lua depends on this)
        cooldown_viewer = IS_RETAIL,
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
        c_spell         = IS_RETAIL,
        -- C_Item namespace
        c_item          = IS_RETAIL,
        -- Specialisations (talent trees, specs)
        specializations = IS_RETAIL,
        -- ── Warcraft Forever capabilities (fill in when API lands) ──────────
        -- wow_forever_foo = IS_WOW_FOREVER and ???,
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
