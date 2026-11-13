local addonName, addon = ...
sfui = sfui or {}
sfui.buffs = sfui.buffs or {}
sfui.buffs.party = sfui.buffs.party or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/reminders/buffs_party.lua
--  Ultra-Lean Party Buff & Smart Paladin Blessing Engine (Camelot / Classic)
--
--  CPU Design Principles:
--    1. Zero polling / zero OnUpdate loops: strictly event-driven via C-filtered
--       unit events ("party1".."party4") and group roster / role updates.
--    2. Single-pass aura inspection: inspects each party unit's helpful auras
--       at most once per scan, simultaneously extracting active blessings,
--       other paladins' blessings, and spec-identifying aura/shapeshift signatures.
--    3. O(1) integer spellID hash lookups and pre-allocated record pools (zero
--       per-scan table garbage).
-- ══════════════════════════════════════════════════════════════════════════════

local _G = _G
local type = _G.type
local tonumber = _G.tonumber
local string_lower = string.lower
local wipe = _G.wipe

local UnitExists = _G.UnitExists
local UnitIsConnected = _G.UnitIsConnected
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local UnitIsVisible = _G.UnitIsVisible
local UnitClass = _G.UnitClass
local UnitGUID = _G.UnitGUID
local UnitName = _G.UnitName
local UnitGroupRolesAssigned = _G.UnitGroupRolesAssigned
local UnitHealthMax = _G.UnitHealthMax
local UnitPowerMax = _G.UnitPowerMax
local IsInGroup = _G.IsInGroup
local IsInRaid = _G.IsInRaid
local C_UnitAuras = _G.C_UnitAuras
local C_Secrets = _G.C_Secrets
local C_SpecializationInfo = _G.C_SpecializationInfo
local issecretvalue = sfui.common.issecretvalue

local PARTY_UNITS = { "party1", "party2", "party3", "party4" }

local function IsSafeValue(v)
    return v ~= nil and not (issecretvalue and issecretvalue(v))
end

local function IsUnitAuraRestricted(unit, index)
    if not C_Secrets then return false end
    if C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
        return true
    end
    if index and C_Secrets.ShouldUnitAuraIndexBeSecret and C_Secrets.ShouldUnitAuraIndexBeSecret(unit, index, "HELPFUL") then
        return true
    end
    return false
end

-- ──────────────────────────────────────────────────────────────────────────────
--  1. O(1) SPELL ID & NAME LOOKUP TABLES FOR PALADIN BLESSINGS
--     Maps both normal and greater blessings to their canonical blessing key
--     so we never overwrite another Paladin's blessing of the same type.
-- ──────────────────────────────────────────────────────────────────────────────
local BLESSING_SPELL_TO_KEY = {
    -- Blessing of Might + Greater Blessing of Might
    [19740] = "might", [19834] = "might", [19835] = "might", [19836] = "might",
    [19837] = "might", [19838] = "might", [25291] = "might", [27140] = "might",
    [25782] = "might", [25916] = "might", [27141] = "might",
    -- Blessing of Wisdom + Greater Blessing of Wisdom
    [19742] = "wisdom", [19850] = "wisdom", [19852] = "wisdom", [19853] = "wisdom",
    [19854] = "wisdom", [25290] = "wisdom", [27142] = "wisdom",
    [25894] = "wisdom", [25918] = "wisdom", [27143] = "wisdom",
    -- Blessing of Kings + Greater Blessing of Kings
    [20217] = "kings", [25898] = "kings",
    -- Blessing of Sanctuary + Greater Blessing of Sanctuary
    [20911] = "sanctuary", [20912] = "sanctuary", [20913] = "sanctuary",
    [20914] = "sanctuary", [27168] = "sanctuary", [25899] = "sanctuary", [27169] = "sanctuary",
    -- Blessing of Light + Greater Blessing of Light
    [19977] = "light", [19978] = "light", [19979] = "light", [27144] = "light",
    [25890] = "light", [27145] = "light",
    -- Blessing of Salvation + Greater Blessing of Salvation
    [1038] = "salvation", [25895] = "salvation",
}

local BLESSING_NAME_TO_KEY = {
    ["blessing of might"] = "might",
    ["greater blessing of might"] = "might",
    ["blessing of wisdom"] = "wisdom",
    ["greater blessing of wisdom"] = "wisdom",
    ["blessing of kings"] = "kings",
    ["greater blessing of kings"] = "kings",
    ["blessing of sanctuary"] = "sanctuary",
    ["greater blessing of sanctuary"] = "sanctuary",
    ["blessing of light"] = "light",
    ["greater blessing of light"] = "light",
    ["blessing of salvation"] = "salvation",
    ["greater blessing of salvation"] = "salvation",
}

-- ──────────────────────────────────────────────────────────────────────────────
--  2. O(1) SPEC DETECTION FOR PALADIN / SHAMAN / DRUID / HYBRID PARTY MEMBERS
-- ──────────────────────────────────────────────────────────────────────────────
-- Maps Spec IDs (both Retail/Camelot numeric specIDs and 148xx tree IDs) to
-- { archetype = "tank"|"healer"|"caster"|"melee", label = "..." }
local SPEC_ID_ARCHETYPES = {
    -- Paladin
    [65]    = { archetype = "healer", label = "holy" },
    [14861] = { archetype = "healer", label = "holy" },
    [66]    = { archetype = "tank",   label = "protection" },
    [14862] = { archetype = "tank",   label = "protection" },
    [70]    = { archetype = "melee",  label = "retribution" },
    [14863] = { archetype = "melee",  label = "retribution" },
    -- Shaman
    [262]   = { archetype = "caster", label = "elemental" },
    [14891] = { archetype = "caster", label = "elemental" },
    [263]   = { archetype = "melee",  label = "enhancement" },
    [14892] = { archetype = "melee",  label = "enhancement" },
    [264]   = { archetype = "healer", label = "restoration" },
    [14893] = { archetype = "healer", label = "restoration" },
    -- Druid
    [102]   = { archetype = "caster", label = "balance" },
    [14841] = { archetype = "caster", label = "balance" },
    [103]   = { archetype = "melee",  label = "feral" },
    [14842] = { archetype = "melee",  label = "feral" },
    [104]   = { archetype = "tank",   label = "guardian" },
    [14844] = { archetype = "tank",   label = "guardian" },
    [105]   = { archetype = "healer", label = "restoration" },
    [14843] = { archetype = "healer", label = "restoration" },
    -- Warrior
    [71]    = { archetype = "melee",  label = "arms" },
    [14911] = { archetype = "melee",  label = "arms" },
    [72]    = { archetype = "melee",  label = "fury" },
    [14912] = { archetype = "melee",  label = "fury" },
    [73]    = { archetype = "tank",   label = "protection" },
    [14913] = { archetype = "tank",   label = "protection" },
    -- Priest
    [256]   = { archetype = "healer", label = "discipline" },
    [14871] = { archetype = "healer", label = "discipline" },
    [257]   = { archetype = "healer", label = "holy" },
    [14872] = { archetype = "healer", label = "holy" },
    [258]   = { archetype = "caster", label = "shadow" },
    [14873] = { archetype = "caster", label = "shadow" },
}

-- O(1) Active Buff / Shapeshift Form -> Spec Signature Lookup
local SPEC_SIGNATURE_AURAS = {
    -- Druid Forms & Auras
    [5487]  = { archetype = "tank",   label = "guardian" },    -- Bear Form
    [9634]  = { archetype = "tank",   label = "guardian" },    -- Dire Bear Form
    [768]   = { archetype = "melee",  label = "feral" },       -- Cat Form
    [17007] = { archetype = "melee",  label = "feral" },       -- Leader of the Pack
    [24932] = { archetype = "melee",  label = "feral" },       -- Leader of the Pack (Aura)
    [24858] = { archetype = "caster", label = "balance" },     -- Moonkin Form
    [24907] = { archetype = "caster", label = "balance" },     -- Moonkin Aura
    [33891] = { archetype = "healer", label = "restoration" }, -- Tree of Life
    [34123] = { archetype = "healer", label = "restoration" }, -- Tree of Life (Aura)
    -- Paladin Buffs / Seals / Auras
    [25780] = { archetype = "tank",   label = "protection" },  -- Righteous Fury
    [20925] = { archetype = "tank",   label = "protection" },  -- Holy Shield R1
    [20927] = { archetype = "tank",   label = "protection" },  -- Holy Shield R2
    [20928] = { archetype = "tank",   label = "protection" },  -- Holy Shield R3
    [27179] = { archetype = "tank",   label = "protection" },  -- Holy Shield R4
    [20218] = { archetype = "melee",  label = "retribution" }, -- Sanctity Aura
    [20375] = { archetype = "melee",  label = "retribution" }, -- Seal of Command R1
    [20915] = { archetype = "melee",  label = "retribution" }, -- Seal of Command R2
    [20918] = { archetype = "melee",  label = "retribution" }, -- Seal of Command R3
    [20919] = { archetype = "melee",  label = "retribution" }, -- Seal of Command R4
    [20920] = { archetype = "melee",  label = "retribution" }, -- Seal of Command R5
    [27170] = { archetype = "melee",  label = "retribution" }, -- Seal of Command R6
    [20050] = { archetype = "melee",  label = "retribution" }, -- Vengeance R1
    [20052] = { archetype = "melee",  label = "retribution" }, -- Vengeance R2
    [20053] = { archetype = "melee",  label = "retribution" }, -- Vengeance R3
    [20054] = { archetype = "melee",  label = "retribution" }, -- Vengeance R4
    [20055] = { archetype = "melee",  label = "retribution" }, -- Vengeance R5
    [20216] = { archetype = "healer", label = "holy" },        -- Divine Favor
    [31834] = { archetype = "healer", label = "holy" },        -- Light's Grace
    -- Shaman Buffs / Shields / Procs
    [30802] = { archetype = "melee",  label = "enhancement" }, -- Unleashed Rage
    [30803] = { archetype = "melee",  label = "enhancement" },
    [30804] = { archetype = "melee",  label = "enhancement" },
    [30805] = { archetype = "melee",  label = "enhancement" },
    [30807] = { archetype = "melee",  label = "enhancement" },
    [30823] = { archetype = "melee",  label = "enhancement" }, -- Shamanistic Rage
    [16256] = { archetype = "melee",  label = "enhancement" }, -- Flurry R1
    [16277] = { archetype = "melee",  label = "enhancement" }, -- Flurry R2
    [16278] = { archetype = "melee",  label = "enhancement" }, -- Flurry R3
    [16279] = { archetype = "melee",  label = "enhancement" }, -- Flurry R4
    [16280] = { archetype = "melee",  label = "enhancement" }, -- Flurry R5
    [974]   = { archetype = "healer", label = "restoration" }, -- Earth Shield R1
    [32593] = { archetype = "healer", label = "restoration" }, -- Earth Shield R2
    [32594] = { archetype = "healer", label = "restoration" }, -- Earth Shield R3
    [24398] = { archetype = "healer", label = "restoration" }, -- Water Shield R1
    [33736] = { archetype = "healer", label = "restoration" }, -- Water Shield R2
    [16191] = { archetype = "healer", label = "restoration" }, -- Mana Tide
    [16166] = { archetype = "caster", label = "elemental" },   -- Elemental Mastery
    [30706] = { archetype = "caster", label = "elemental" },   -- Totem of Wrath
    [30708] = { archetype = "caster", label = "elemental" },   -- Totem of Wrath (Aura)
    [16246] = { archetype = "caster", label = "elemental" },   -- Elemental Focus (Clearcasting)
    -- Priest
    [15473] = { archetype = "caster", label = "shadow" },      -- Shadowform
    [15286] = { archetype = "caster", label = "shadow" },      -- Vampiric Embrace
    -- Warrior
    [71]    = { archetype = "tank",   label = "protection" },  -- Defensive Stance
}

-- Persistent O(1) per-GUID spec cache: guidSpecCache[guid] = { archetype = ..., label = ... }
local guidSpecCache = {}

function sfui.buffs.party.InvalidateSpecCache()
    wipe(guidSpecCache)
end

--- Resolves a party unit's spec archetype ("tank", "healer", "caster", "melee") and label
--- using zero-allocation O(1) tiers.
local function ResolvePartyUnitSpec(unit, guid, classFile, auraSignature)
    -- Tier 1: Live aura / shapeshift form signature seen during the current aura scan
    if auraSignature then
        if guid then
            guidSpecCache[guid] = auraSignature
        end
        return auraSignature.archetype, auraSignature.label
    end

    -- Tier 2: SFUI synced alt / multibox peer database (`SfuiDB.alts[guid]`)
    local SfuiDB = _G.SfuiDB
    if guid and SfuiDB and type(SfuiDB.alts) == "table" then
        local alt = SfuiDB.alts[guid]
        if alt and alt.spec then
            local info = SPEC_ID_ARCHETYPES[tonumber(alt.spec)]
            if info then
                guidSpecCache[guid] = info
                return info.archetype, info.label
            end
        end
    end

    -- Tier 3: Previously cached aura/inspect spec for this GUID
    if guid and guidSpecCache[guid] then
        local cached = guidSpecCache[guid]
        return cached.archetype, cached.label
    end

    -- Tier 4: Native C_SpecializationInfo.GetInspectSpecialization (if already available in C++)
    if C_SpecializationInfo and C_SpecializationInfo.GetInspectSpecialization then
        local restrictId = C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret and C_Secrets.ShouldUnitIdentityBeSecret(unit)
        if not restrictId then
            local inspectSpecID = C_SpecializationInfo.GetInspectSpecialization(unit)
            if IsSafeValue(inspectSpecID) and inspectSpecID > 0 then
                local info = SPEC_ID_ARCHETYPES[inspectSpecID]
                if info then
                    if guid then guidSpecCache[guid] = info end
                    return info.archetype, info.label
                end
            end
        end
    end

    -- Tier 5: Group Assigned Role (`UnitGroupRolesAssigned`)
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
    if IsSafeValue(role) then
        if role == "TANK" then
            local label = (classFile == "DRUID" and "guardian") or (classFile == "SHAMAN" and "enhancement") or "protection"
            return "tank", label
        elseif role == "HEALER" then
            local label = (classFile == "PALADIN" or classFile == "PRIEST") and "holy" or "restoration"
            return "healer", label
        end
    end

    -- Tier 6: Pure Class Defaults & Hybrid Mana-to-Health Gear Ratio
    if classFile == "WARRIOR" or classFile == "ROGUE" then
        return "melee", classFile:lower()
    elseif classFile == "HUNTER" then
        return "ranged", "hunter"
    elseif classFile == "MAGE" or classFile == "WARLOCK" then
        return "caster", classFile:lower()
    elseif classFile == "PRIEST" then
        return "healer", "priest"
    elseif classFile == "PALADIN" or classFile == "SHAMAN" or classFile == "DRUID" then
        local maxHP = UnitHealthMax and UnitHealthMax(unit)
        local maxMana = UnitPowerMax and UnitPowerMax(unit, 0)
        if IsSafeValue(maxHP) and IsSafeValue(maxMana) and maxHP > 0 and maxMana > 0 then
            -- Caster/Healer specs stack Intellect; their max mana pool is >= 85% of max health.
            -- Retribution / Enhancement / Feral wear Str/Agi gear with a much smaller base mana pool.
            if maxMana >= (maxHP * 0.85) then
                if classFile == "PALADIN" then
                    return "healer", "holy"
                elseif classFile == "SHAMAN" then
                    return "caster", "elemental/resto"
                else
                    return "caster", "balance/resto"
                end
            else
                if classFile == "PALADIN" then
                    return "melee", "retribution"
                elseif classFile == "SHAMAN" then
                    return "melee", "enhancement"
                else
                    return "melee", "feral"
                end
            end
        end
    end

    return "melee", (classFile and classFile:lower()) or "party"
end
sfui.buffs.party.ResolvePartyUnitSpec = ResolvePartyUnitSpec

-- ──────────────────────────────────────────────────────────────────────────────
--  3. PALADIN BLESSING PRIORITY MATRICES BY CLASS + SPEC ARCHETYPE
-- ──────────────────────────────────────────────────────────────────────────────
local BLESSING_PRIORITIES = {
    WARRIOR = {
        tank    = { "might", "kings", "sanctuary" },
        default = { "might", "kings" },
    },
    ROGUE = {
        default = { "might", "kings" },
    },
    HUNTER = {
        default = { "might", "kings", "wisdom" },
    },
    MAGE = {
        default = { "wisdom", "kings" },
    },
    WARLOCK = {
        default = { "wisdom", "kings" },
    },
    PRIEST = {
        caster  = { "wisdom", "kings" },
        default = { "wisdom", "kings" },
    },
    PALADIN = {
        tank    = { "sanctuary", "kings", "wisdom", "might" },
        healer  = { "wisdom", "kings" },
        melee   = { "might", "kings", "wisdom" },
        default = { "might", "wisdom", "kings" },
    },
    SHAMAN = {
        melee   = { "might", "kings", "wisdom" },
        caster  = { "wisdom", "kings" },
        healer  = { "wisdom", "kings" },
        default = { "wisdom", "might", "kings" },
    },
    DRUID = {
        tank    = { "kings", "might", "sanctuary" },
        melee   = { "might", "kings", "wisdom" },
        caster  = { "wisdom", "kings" },
        healer  = { "wisdom", "kings" },
        default = { "kings", "wisdom", "might" },
    },
}
local FALLBACK_PRIORITY = { "kings", "might", "wisdom" }

local function GetPriorityList(classFile, archetype)
    local classTable = classFile and BLESSING_PRIORITIES[classFile]
    if not classTable then
        return FALLBACK_PRIORITY
    end
    return (archetype and classTable[archetype]) or classTable.default or FALLBACK_PRIORITY
end

-- Pre-allocated scratch tables (reused across every scan to avoid GC allocations)
local otherBlessingsScratch = {}
local knownBlessingsByKey = {}
local partyEntryPool = {}
for i = 1, 4 do
    partyEntryPool[i] = {
        key = "party_blessing_" .. i,
        name = "party blessing",
        type = "party_blessing",
        isPartyBuff = true,
        unit = PARTY_UNITS[i],
    }
end

--- Cycles manual blessing override for a specific party member (via mouse wheel on their reminder icon)
function sfui.buffs.party.CyclePartyBlessing(unit, delta)
    if not unit or not sfui.buffs.paladin or not sfui.buffs.paladin.GetAvailableBlessings then
        return nil
    end
    local all = sfui.buffs.paladin.GetAvailableBlessings()
    if (not all or #all <= 1) and sfui.buffs.paladin.InvalidateCache then
        sfui.buffs.paladin.InvalidateCache()
        all = sfui.buffs.paladin.GetAvailableBlessings()
    end
    if not all or #all <= 1 then return nil end

    local guid = UnitGUID and UnitGUID(unit)
    if not IsSafeValue(guid) then
        guid = unit
    end

    local targetEntry = nil
    for i = 1, 4 do
        if partyEntryPool[i].unit == unit then
            targetEntry = partyEntryPool[i]
            break
        end
    end

    local SfuiDB = _G.SfuiDB or {}
    _G.SfuiDB = SfuiDB
    SfuiDB.buffReminders = SfuiDB.buffReminders or {}
    SfuiDB.buffReminders.partyBlessingOverrides = SfuiDB.buffReminders.partyBlessingOverrides or {}

    local curKey = SfuiDB.buffReminders.partyBlessingOverrides[guid] or (targetEntry and targetEntry.blessingKey)
    local curIdx = 1
    if curKey then
        for i = 1, #all do
            if all[i].key == curKey then
                curIdx = i
                break
            end
        end
    end

    local nextIdx = curIdx + (delta > 0 and 1 or -1)
    if nextIdx > #all then
        nextIdx = 1
    elseif nextIdx < 1 then
        nextIdx = #all
    end

    local chosen = all[nextIdx]
    if chosen then
        SfuiDB.buffReminders.partyBlessingOverrides[guid] = chosen.key
        if targetEntry then
            targetEntry.blessingKey = chosen.key
            targetEntry.castSpellName = chosen.spellName
            targetEntry.castSpellID = chosen.id
            targetEntry.castIcon = chosen.icon
            targetEntry.name = chosen.displayName .. " -> " .. (targetEntry.unitName or unit)
        end
        if sfui.buffs.scan and sfui.buffs.scan.GetResults then
            local results = sfui.buffs.scan.GetResults()
            if results then
                for i = 1, #results do
                    local rec = results[i]
                    if rec and (rec.entry == targetEntry or rec.unit == unit) then
                        rec.icon = chosen.icon
                    end
                end
            end
        end
        if sfui.buffs.UpdateDisplay then
            sfui.buffs.UpdateDisplay()
        end
        if sfui.ring and sfui.ring.request_rebuild then
            sfui.ring.request_rebuild("specs")
        end
        return chosen
    end
    return nil
end

-- ──────────────────────────────────────────────────────────────────────────────
--  4. SINGLE-PASS PARTY SCANNER (APPENDED TO `buffs_scan.lua` RESULTS)
-- ──────────────────────────────────────────────────────────────────────────────
function sfui.buffs.party.AppendPartyReminders(activeResults, count, now, cfg)
    if cfg and cfg.partyBuffs == false then
        return count
    end
    if sfui.buffs.playerClass ~= "PALADIN" then
        return count
    end
    if not IsInGroup or not IsInGroup() or (IsInRaid and IsInRaid()) then
        return count
    end
    if not sfui.buffs.paladin or not sfui.buffs.paladin.GetAvailableBlessings then
        return count
    end

    local available = sfui.buffs.paladin.GetAvailableBlessings()
    if not available or #available == 0 then
        return count
    end

    wipe(knownBlessingsByKey)
    for i = 1, #available do
        local b = available[i]
        knownBlessingsByKey[b.key] = b
    end

    local allowExpiring = not cfg or (cfg.showExpiring ~= false)
    local thresholdShort = (cfg and cfg.thresholdShort) or 60
    local thresholdLong = (cfg and cfg.thresholdLong) or 300
    local overrides = cfg and cfg.partyBlessingOverrides

    local paladinRank, totalPaladins = 1, 1
    if sfui.buffs.paladin.GetPartyPaladinRank then
        paladinRank, totalPaladins = sfui.buffs.paladin.GetPartyPaladinRank()
    end
    local hasOtherPaladin = (totalPaladins > 1)
    if not hasOtherPaladin then
        for idx = 1, 4 do
            local u = PARTY_UNITS[idx]
            local isSelf = (sfui.safety and sfui.safety.SafeUnitIsUnit and sfui.safety.SafeUnitIsUnit(u, "player")) or false
            if UnitExists and UnitExists(u) and not isSelf then
                local _, uClass = UnitClass(u)
                if IsSafeValue(uClass) and uClass == "PALADIN" then
                    hasOtherPaladin = true
                    break
                end
            end
        end
    end

    for idx = 1, 4 do
        local unit = PARTY_UNITS[idx]
        local isSelf = (sfui.safety and sfui.safety.SafeUnitIsUnit and sfui.safety.SafeUnitIsUnit(unit, "player")) or false
        if UnitExists and UnitExists(unit)
            and not isSelf
            and (not UnitIsConnected or UnitIsConnected(unit))
            and not (UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit))
            and (not UnitIsVisible or UnitIsVisible(unit))
            and not IsUnitAuraRestricted(unit, nil) then

            wipe(otherBlessingsScratch)
            local myBlessingKey = nil
            local myDuration = 0
            local myExpTime = 0
            local myIcon = nil
            local auraSignature = nil

            -- Single-pass scan over party unit's helpful auras
            if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
                for aIdx = 1, 40 do
                    if not IsUnitAuraRestricted(unit, aIdx) then
                        local aura = C_UnitAuras.GetAuraDataByIndex(unit, aIdx, "HELPFUL")
                        if not aura then break end

                        local sID = IsSafeValue(aura.spellId) and aura.spellId or nil
                        local aName = IsSafeValue(aura.name) and aura.name or nil

                        if sID and not auraSignature then
                            auraSignature = SPEC_SIGNATURE_AURAS[sID]
                        end

                        local bKey = (sID and BLESSING_SPELL_TO_KEY[sID])
                            or (aName and BLESSING_NAME_TO_KEY[string_lower(aName)])

                        if bKey then
                            local src = IsSafeValue(aura.sourceUnit) and aura.sourceUnit or nil
                            local fromPlayer = (src == "player")
                                or (IsSafeValue(aura.isFromPlayerOrPlayerPet) and aura.isFromPlayerOrPlayerPet == true)
                                or (not hasOtherPaladin and src == nil)
                            if fromPlayer then
                                myBlessingKey = bKey
                                myDuration = (IsSafeValue(aura.duration) and aura.duration) or 0
                                myExpTime = (IsSafeValue(aura.expirationTime) and aura.expirationTime) or 0
                                myIcon = IsSafeValue(aura.icon) and aura.icon or nil
                            else
                                otherBlessingsScratch[bKey] = true
                            end
                        end
                    end
                end
            end

            local isMissing = (myBlessingKey == nil)
            local isExpiring = false
            local effectiveThreshold = (myDuration and myDuration > 300) and thresholdLong or thresholdShort
            if not isMissing and allowExpiring and myExpTime > 0 and effectiveThreshold > 0 then
                local rem = myExpTime - now
                if rem > 0 and rem <= effectiveThreshold then
                    isExpiring = true
                end
            end

            if isMissing or isExpiring then
                local _, classFile = UnitClass(unit)
                if not IsSafeValue(classFile) then classFile = nil end
                local rawGuid = UnitGUID and UnitGUID(unit)
                local guid = IsSafeValue(rawGuid) and rawGuid or unit
                local archetype, specLabel = ResolvePartyUnitSpec(unit, guid, classFile, auraSignature)

                -- Determine best non-conflicting blessing for this party member
                local chosenBlessing = nil
                local overrideKey = overrides and overrides[guid]
                if overrideKey and knownBlessingsByKey[overrideKey] then
                    chosenBlessing = knownBlessingsByKey[overrideKey]
                end

                if not chosenBlessing and not isMissing and myBlessingKey and knownBlessingsByKey[myBlessingKey] and not otherBlessingsScratch[myBlessingKey] then
                    chosenBlessing = knownBlessingsByKey[myBlessingKey]
                end

                if not chosenBlessing then
                    local prioList = GetPriorityList(classFile, archetype)
                    local targetSlot = (totalPaladins > 1) and paladinRank or 1
                    local matchedCount = 0
                    local firstValid = nil
                    for p = 1, #prioList do
                        local k = prioList[p]
                        if knownBlessingsByKey[k] and not otherBlessingsScratch[k] then
                            if not firstValid then firstValid = knownBlessingsByKey[k] end
                            matchedCount = matchedCount + 1
                            if matchedCount == targetSlot then
                                chosenBlessing = knownBlessingsByKey[k]
                                break
                            end
                        end
                    end
                    if not chosenBlessing then
                        chosenBlessing = firstValid
                    end
                end

                if not chosenBlessing then
                    for p = 1, #FALLBACK_PRIORITY do
                        local k = FALLBACK_PRIORITY[p]
                        if knownBlessingsByKey[k] and not otherBlessingsScratch[k] then
                            chosenBlessing = knownBlessingsByKey[k]
                            break
                        end
                    end
                end

                if chosenBlessing then
                    local rawName = UnitName and UnitName(unit)
                    local unitName = (IsSafeValue(rawName) and rawName) or unit
                    local shortName = unitName:match("^([^%-]+)") or unitName

                    local pEntry = partyEntryPool[idx]
                    pEntry.unit = unit
                    pEntry.unitName = shortName:lower()
                    pEntry.unitClass = classFile
                    pEntry.unitSpecLabel = specLabel
                    pEntry.blessingKey = chosenBlessing.key
                    pEntry.castSpellName = chosenBlessing.spellName
                    pEntry.castSpellID = chosenBlessing.id
                    pEntry.castIcon = chosenBlessing.icon
                    pEntry.name = chosenBlessing.displayName .. " -> " .. pEntry.unitName

                    count = count + 1
                    local rec = activeResults[count]
                    if not rec then
                        rec = {}
                        activeResults[count] = rec
                    end

                    rec.entry = pEntry
                    rec.unit = unit
                    rec.unitName = pEntry.unitName
                    rec.unitClass = classFile
                    rec.unitSpecLabel = specLabel
                    rec.hasBuff = not isMissing
                    rec.isMissing = isMissing
                    rec.isExpiring = isExpiring
                    rec.expirationTime = myExpTime or 0
                    rec.duration = myDuration or 0
                    rec.charges = 0
                    rec.icon = chosenBlessing.icon or myIcon
                    rec.activeEnchant = nil
                end
            end
        end
    end

    return count
end

-- ──────────────────────────────────────────────────────────────────────────────
--  5. PARTY BLESSING PROVIDER REGISTRATION
-- ──────────────────────────────────────────────────────────────────────────────
local P = sfui.buffs.providers
if P and P.Register then
    P.Register("party_blessing", {
        cycle = function(rec, delta, btn)
            local entry = rec and rec.entry
            if not entry or not entry.unit then return false end
            local chosen = sfui.buffs.party.CyclePartyBlessing(entry.unit, delta)
            if chosen and btn then
                btn._needsScanOnLeave = true
            end
            return chosen ~= nil
        end,
        populateTooltip = function(tip, rec, _, isTestMode)
            local entry = rec and rec.entry
            if not entry then return end
            local coloredUnit = entry.unitName or entry.unit or "party"
            if entry.unitClass and sfui.common and sfui.common.class_color_name then
                coloredUnit = sfui.common.class_color_name(coloredUnit, entry.unitClass)
            end
            local specSuffix = (entry.unitSpecLabel and entry.unitSpecLabel ~= "") and (" |cffaaaaaa(" .. entry.unitSpecLabel .. ")|r") or ""
            local bLabel = (entry.castSpellName and entry.castSpellName:lower()) or "blessing"
            P.AddStatusHeader(tip, rec, bLabel .. " -> " .. coloredUnit .. specSuffix)
            P.AddClickPrompt(tip, "cast", bLabel .. " on " .. coloredUnit, isTestMode)
            local allBlessings = sfui.buffs.paladin and sfui.buffs.paladin.GetAvailableBlessings and sfui.buffs.paladin.GetAvailableBlessings()
            P.AddSpellChoiceList(tip, "scroll wheel to override blessing:", allBlessings, "key", entry.blessingKey)
        end,
    })
end


