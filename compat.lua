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

-- Expose on sfui.version and top-level sfui canonical booleans so any module
-- can read client context cleanly (e.g. `if sfui.isClassic then ... end`).
sfui.isRetail   = IS_RETAIL
sfui.isClassic  = not IS_RETAIL
sfui.isForever  = IS_WOW_FOREVER
sfui.isEra      = IS_CLASSIC_ERA

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
    is_classic     = not IS_RETAIL,
    is_classic_era = IS_CLASSIC_ERA,
    is_wow_forever = IS_WOW_FOREVER,
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
sfui.has = sfui.compat.has

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
    if _G.C_UnitAuras and _G.C_UnitAuras.GetAuraDataByIndex then
        return _G.C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
    end
    return nil
end

--- Returns spell name or nil.
--- Cascades C_Spell.GetSpellName -> C_Spell.GetSpellInfo -> legacy GetSpellInfo.
function sfui.api.GetSpellName(spellID)
    if not spellID then return nil end
    if _G.C_Spell and _G.C_Spell.GetSpellName then
        local name = _G.C_Spell.GetSpellName(spellID)
        if name and name ~= "" then return name end
    end
    if _G.C_Spell and _G.C_Spell.GetSpellInfo then
        local info = _G.C_Spell.GetSpellInfo(spellID)
        if info and info.name and info.name ~= "" then return info.name end
    end
    if _G.GetSpellInfo then
        local name = _G.GetSpellInfo(spellID)
        if name and name ~= "" then return name end
    end
    return nil
end

--- Fast query to test if a spell ID is part of a registered aura/rank group
--- @param spellID number
--- @return boolean
function sfui.api.IsKnownAuraSpellID(spellID)
    if not spellID then return false end
    if sfui.spells_db and sfui.spells_db.IsKnownAuraSpellID then
        return sfui.spells_db.IsKnownAuraSpellID(spellID)
    end
    return false
end

--- Searches a unit's aura list for a specific spellID or spell name.
--- Handles Vanilla spell ranks, Seals, Blessings, and Greater blessing equivalence.
--- When in combat: relies strictly on C_UnitAuras.GetPlayerAuraBySpellID with rank group lookup
--- to avoid "Auras cannot be accessed when secret while tainted" errors.
--- When out of combat: allowed to iterate auras by name and dynamically learn new rank mappings.
--- @param unit string UnitId (defaults to "player")
--- @param spellIDOrName number|string Spell ID or Spell Name
--- @param filter string|nil "HELPFUL", "HARMFUL", or nil to check both
--- @return table|nil Normalized aura data table
function sfui.api.GetUnitAuraByNameOrID(unit, spellIDOrName, filter)
    if not spellIDOrName then return nil end
    unit = unit or "player"

    local targetID = tonumber(spellIDOrName)
    local targetName = type(spellIDOrName) == "string" and spellIDOrName or sfui.api.GetSpellName(targetID)
    local targetGreaterName = nil
    if targetName then
        if targetName:find("^Blessing of ") then
            targetGreaterName = "Greater " .. targetName
        elseif targetName:find("^Greater Blessing of ") then
            targetGreaterName = targetName:gsub("^Greater ", "")
        end
    end

    -- 1. Direct O(1) SpellID lookup on player via C_UnitAuras (100% legal in combat/secrecy)
    if unit == "player" and _G.C_UnitAuras and _G.C_UnitAuras.GetPlayerAuraBySpellID then
        if targetID then
            local aura = _G.C_UnitAuras.GetPlayerAuraBySpellID(targetID)
            if aura then return aura end
        end

        -- Sibling rank check (e.g. Blessing of Might Ranks 1-8 / Greater, Seals, Class Buffs)
        local ranks = nil
        if sfui.spells_db then
            if targetID then
                ranks = sfui.spells_db.GetRanksByID(targetID)
            end
            if not ranks and targetName then
                ranks = sfui.spells_db.GetRanksByName(targetName)
                if not ranks and targetGreaterName then
                    ranks = sfui.spells_db.GetRanksByName(targetGreaterName)
                end
            end
        end

        if ranks then
            for _, rankID in ipairs(ranks) do
                if rankID ~= targetID then
                    local aura = _G.C_UnitAuras.GetPlayerAuraBySpellID(rankID)
                    if aura then return aura end
                end
            end
        end
    end

    -- 2. Index-based full scan (ONLY PERMITTED OUT OF COMBAT)
    -- In combat, Blizzard restricts GetAuraDataByIndex with "Auras cannot be accessed when secret while tainted"
    local inCombat = _G.InCombatLockdown and _G.InCombatLockdown()
    local areAurasSecret = inCombat or (_G.C_Secrets and _G.C_Secrets.ShouldAurasBeSecret and _G.C_Secrets.ShouldAurasBeSecret())

    if not areAurasSecret then
        local function MatchesAura(sid, name)
            if targetID and sid and sid == targetID then return true end
            if targetName and name and (name == targetName or name:lower() == targetName:lower()) then return true end
            if targetGreaterName and name and (name == targetGreaterName or name:lower() == targetGreaterName:lower()) then return true end
            return false
        end

        local function LearnAuraMapping(aura)
            if not aura or not aura.spellId then return end
            if sfui.spells_db and sfui.spells_db.LearnAuraMapping then
                sfui.spells_db.LearnAuraMapping(targetID, aura.spellId, aura.name or targetName)
            end
        end

        if _G.C_UnitAuras and _G.C_UnitAuras.GetAuraDataByIndex then
            local function scanAuras(f)
                for i = 1, 64 do
                    local aura = _G.C_UnitAuras.GetAuraDataByIndex(unit, i, f)
                    if not aura then break end
                    if MatchesAura(aura.spellId, aura.name) then
                        LearnAuraMapping(aura)
                        return aura
                    end
                end
            end
            local result = filter and scanAuras(filter) or (scanAuras("HELPFUL") or scanAuras("HARMFUL"))
            if result then return result end
        end
    end

    return nil
end

--- Searches the player's aura list for a specific spellID or spell name.
--- @param spellID number|string
--- @return table|nil same shape as GetAuraData
function sfui.api.GetPlayerAuraBySpellID(spellID)
    return sfui.api.GetUnitAuraByNameOrID("player", spellID)
end

-- ── Spell queries ─────────────────────────────────────────────────────────────

--- Returns a normalised spell info table.
--- Cascades C_Spell.GetSpellInfo -> legacy GetSpellInfo.
--- @return table|nil { name, iconID, castTime, minRange, maxRange, spellID }
function sfui.api.GetSpellInfo(spellID)
    if not spellID then return nil end
    if _G.C_Spell and _G.C_Spell.GetSpellInfo then
        local info = _G.C_Spell.GetSpellInfo(spellID)
        if info then return info end
    end
    if _G.GetSpellInfo then
        local name, _, icon, castTime, minRange, maxRange, id = _G.GetSpellInfo(spellID)
        if name then
            return {
                name     = name,
                iconID   = icon,
                castTime = castTime,
                minRange = minRange,
                maxRange = maxRange,
                spellID  = id or spellID,
            }
        end
    end
    return nil
end

--- Returns spell name or nil.
--- Cascades C_Spell.GetSpellName -> C_Spell.GetSpellInfo.
function sfui.api.GetSpellName(spellID)
    if not spellID then return nil end
    if _G.C_Spell and _G.C_Spell.GetSpellName then
        local name = _G.C_Spell.GetSpellName(spellID)
        if name and name ~= "" then return name end
    end
    if _G.C_Spell and _G.C_Spell.GetSpellInfo then
        local info = _G.C_Spell.GetSpellInfo(spellID)
        if info and info.name and info.name ~= "" then return info.name end
    end
    return nil
end

--- Returns clickable spell link string or nil.
function sfui.api.GetSpellLink(spellID)
    if not spellID then return nil end
    if _G.C_Spell and _G.C_Spell.GetSpellLink then
        return _G.C_Spell.GetSpellLink(spellID) or nil
    end
    return nil
end

--- Returns spell texture path or nil.
--- Cascades C_Spell.GetSpellTexture -> C_Spell.GetSpellInfo.
function sfui.api.GetSpellTexture(spellID)
    if not spellID then return nil end
    if _G.C_Spell and _G.C_Spell.GetSpellTexture then
        local tex = _G.C_Spell.GetSpellTexture(spellID)
        if tex then return tex end
    end
    if _G.C_Spell and _G.C_Spell.GetSpellInfo then
        local info = _G.C_Spell.GetSpellInfo(spellID)
        if info then return info.iconID or info.originalIconID or nil end
    end
    return nil
end

--- Returns spell cooldown info.
--- @return table|nil { startTime, duration, isEnabled, modRate }
function sfui.api.GetSpellCooldown(spellID)
    if not spellID then return nil end
    if _G.C_Spell and _G.C_Spell.GetSpellCooldown then
        local cd = _G.C_Spell.GetSpellCooldown(spellID)
        if cd then
            if type(cd) == "table" then
                return cd
            else
                local start, dur, enabled, modRate = _G.C_Spell.GetSpellCooldown(spellID)
                return {
                    startTime = start,
                    duration  = dur,
                    isEnabled = (enabled ~= 0 and enabled ~= false),
                    modRate   = modRate or 1,
                }
            end
        end
    end
    return nil
end

--- Returns spell charge info or nil if spell has no charges.
--- @return table|nil { currentCharges, maxCharges, cooldownStartTime, cooldownDuration }
function sfui.api.GetSpellCharges(spellID)
    if not spellID then return nil end
    if _G.C_Spell and _G.C_Spell.GetSpellCharges then
        return _G.C_Spell.GetSpellCharges(spellID)
    end
    return nil
end

--- Returns true if the player knows the spell.
function sfui.api.IsSpellKnown(spellID)
    if not spellID then return false end
    if _G.C_Spell and _G.C_Spell.IsSpellKnown then
        return _G.C_Spell.IsSpellKnown(spellID)
    end
    if _G.IsSpellKnown then
        return _G.IsSpellKnown(spellID)
    end
    return false
end

--- Resolves a spellbook slot index to an actual spellID across Retail and Classic/Vanilla.
--- @param slot number Spellbook slot index (from GetCursorInfo arg1)
--- @param bankOrBookType any Spell bank enum (Retail) or bookType string (Classic)
--- @return number|nil
function sfui.api.GetSpellBookItemSpellID(slot, bankOrBookType)
    if not slot or type(slot) ~= "number" then return nil end

    -- 1. Try C_SpellBook.GetSpellBookItemType (Retail 11+ / Camelot)
    if _G.C_SpellBook and _G.C_SpellBook.GetSpellBookItemType then
        local bank = bankOrBookType
        if type(bank) ~= "number" and _G.Enum and _G.Enum.SpellBookSpellBank then
            bank = _G.Enum.SpellBookSpellBank.Player
        end
        local _, actionID, spellID = _G.C_SpellBook.GetSpellBookItemType(slot, bank or 1)
        local resolved = (spellID and spellID > 0 and spellID) or (actionID and actionID > 0 and actionID)
        if resolved then return resolved end
    end

    -- 2. Try C_SpellBook.GetSpellBookItemInfo
    if _G.C_SpellBook and _G.C_SpellBook.GetSpellBookItemInfo then
        local bank = bankOrBookType
        if type(bank) ~= "number" and _G.Enum and _G.Enum.SpellBookSpellBank then
            bank = _G.Enum.SpellBookSpellBank.Player
        end
        local info = _G.C_SpellBook.GetSpellBookItemInfo(slot, bank or 1)
        if info then
            local resolved = (info.spellID and info.spellID > 0 and info.spellID) or (info.actionID and info.actionID > 0 and info.actionID)
            if resolved then return resolved end
        end
    end

    return nil
end

-- ── Item queries ──────────────────────────────────────────────────────────────

--- Returns item info table.
--- @return table|nil { itemID, itemName, itemLink, itemQuality, itemLevel, itemTexture, sellPrice }
function sfui.api.GetItemInfo(itemID)
    if not itemID then return nil end
    if _G.C_Item and _G.C_Item.GetItemInfo then
        return _G.C_Item.GetItemInfo(itemID) or nil
    end
    return nil
end

--- Returns item cooldown: startTime, duration, enable.
--- @return number, number, number
function sfui.api.GetItemCooldown(itemID)
    if not itemID then return 0, 0, 0 end
    if _G.C_Item and _G.C_Item.GetItemCooldown then
        return _G.C_Item.GetItemCooldown(itemID)
    end
    return 0, 0, 0
end

--- Returns item stack count in player bags.
function sfui.api.GetItemCount(itemID, includeBank, includeCharges)
    if not itemID then return 0 end
    if _G.C_Item and _G.C_Item.GetItemCount then
        return _G.C_Item.GetItemCount(itemID, includeBank, includeCharges)
    end
    return 0
end

--- Returns item icon texture path.
function sfui.api.GetItemIconByID(itemID)
    if not itemID then return nil end
    if _G.C_Item and _G.C_Item.GetItemIconByID then
        return _G.C_Item.GetItemIconByID(itemID) or nil
    end
    return nil
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
    -- C_Spell.GetSpellCharges returns nil for unowned/invalid spells, it does not throw.
    local chargeInfo = _G.C_Spell.GetSpellCharges(_cachedBresSpellID)
    if not (chargeInfo and (chargeInfo.currentCharges or chargeInfo.maxCharges)) then
        chargeInfo = nil
        for i = 1, #BRES_SPELLS do
            local sid = BRES_SPELLS[i]
            if sid ~= _cachedBresSpellID then
                local info = _G.C_Spell.GetSpellCharges(sid)
                if info and (info.currentCharges or info.maxCharges) then
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

-- ── Currency & Money compatibility ────────────────────────────────────────────

-- On Classic Forever / Vanilla, GetCoinTextureString is not in _G.
-- Alias it to C_CurrencyInfo.GetCoinTextureString or GetMoneyString.
if not _G.GetCoinTextureString then
    if _G.C_CurrencyInfo and _G.C_CurrencyInfo.GetCoinTextureString then
        _G.GetCoinTextureString = _G.C_CurrencyInfo.GetCoinTextureString
    elseif _G.GetMoneyString then
        _G.GetCoinTextureString = _G.GetMoneyString
    end
end

-- ── Merchant queries ──────────────────────────────────────────────────────────

--- Returns normalized merchant item info table across Retail and Classic/Vanilla.
--- Cascades C_MerchantFrame.GetItemInfo -> legacy GetMerchantItemInfo.
--- @param index number
--- @return table|nil { name, texture, price, stackCount, numAvailable, isPurchasable, isUsable, hasExtendedCost, currencyID, hyperlink }
function sfui.api.GetMerchantItemInfo(index)
    if not index then return nil end
    if _G.C_MerchantFrame and _G.C_MerchantFrame.GetItemInfo then
        local info = _G.C_MerchantFrame.GetItemInfo(index)
        if info and info.name then return info end
    end
    if _G.GetMerchantItemInfo then
        local name, texture, price, stackCount, numAvailable, isPurchasable, isUsable, hasExtendedCost, currencyID =
            _G.GetMerchantItemInfo(index)
        if name then
            return {
                name            = name,
                texture         = texture,
                price           = price or 0,
                stackCount      = stackCount or 1,
                numAvailable    = numAvailable,
                isPurchasable   = isPurchasable,
                isUsable        = isUsable,
                hasExtendedCost = hasExtendedCost,
                currencyID      = currencyID,
                hyperlink       = _G.GetMerchantItemLink and _G.GetMerchantItemLink(index),
            }
        end
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
