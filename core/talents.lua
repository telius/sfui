local addonName, addon = ...
sfui = sfui or {}
sfui.talents = sfui.talents or {}
sfui.common = sfui.common or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/core/talents.lua
--  Specialization, Class Discovery & Talent/Trait Inspection Engine
--  Shared Foundation & Central Spec State Coordinator
-- ══════════════════════════════════════════════════════════════════════════════

local _G = _G
local UnitClass = _G.UnitClass
local type, tonumber, tostring = _G.type, _G.tonumber, _G.tostring
local pairs, ipairs = _G.pairs, _G.ipairs
local select = _G.select

local CLASS_NAMES_TO_ID = {
    WARRIOR      = 1,
    PALADIN      = 2,
    HUNTER       = 3,
    ROGUE        = 4,
    PRIEST       = 5,
    DEATHKNIGHT  = 6,
    SHAMAN       = 7,
    MAGE         = 8,
    WARLOCK      = 9,
    MONK         = 10,
    DRUID        = 11,
    DEMONHUNTER  = 12,
    EVOKER       = 13,
}

local cachedPlayerClass   = nil
local cachedPlayerClassID = 0

--- Returns the authoritative player class ID (1..13)
function sfui.talents.get_player_class_id()
    if cachedPlayerClassID > 0 then return cachedPlayerClassID end
    local _, eng, cid = UnitClass("player")
    if cid and cid > 0 then
        cachedPlayerClassID = cid
        cachedPlayerClass   = eng
        return cid
    end
    if eng and CLASS_NAMES_TO_ID[eng] then
        cachedPlayerClassID = CLASS_NAMES_TO_ID[eng]
        cachedPlayerClass   = eng
        return cachedPlayerClassID
    end
    return 0
end
sfui.common.get_player_class_id = sfui.talents.get_player_class_id

--- Returns the cached player class filename and ID (e.g., "WARRIOR", 1)
function sfui.talents.get_player_class()
    if not cachedPlayerClass or cachedPlayerClassID == 0 then
        sfui.talents.get_player_class_id()
    end
    return cachedPlayerClass, cachedPlayerClassID
end
sfui.common.get_player_class = sfui.talents.get_player_class

-- ────────────────────────────────────────────────────────────────────────────
-- Central Specialization State & Provider Registry
-- ────────────────────────────────────────────────────────────────────────────
local cachedSpecID        = 0
local cachedSpecIndex     = 0
local cachedSpecRole      = nil
local cachedPlayerSpecs   = nil
local cachedPlayerSpecIDs = nil

-- Pluggable provider hooks registered by talents_standard.lua and talents_camelot.lua
sfui.talents._specResolver           = nil
sfui.talents._specsCacheBuilder      = nil
sfui.talents._talentKnownResolver    = nil
sfui.talents._specColorOptionsBuilder = nil
sfui.talents._lootSpecResolver       = nil

function sfui.talents.set_cached_spec(specID, specIndex, specRole)
    local oldID = cachedSpecID
    local changed = (cachedSpecID ~= specID) or (cachedSpecIndex ~= specIndex) or (cachedSpecRole ~= specRole)
    cachedSpecID    = specID or 0
    cachedSpecIndex = specIndex or 0
    cachedSpecRole  = specRole
    if changed then
        if sfui.colors and sfui.colors.invalidate_spec_color_cache then
            sfui.colors.invalidate_spec_color_cache()
        elseif sfui.common and sfui.common.invalidate_spec_color_cache then
            sfui.common.invalidate_spec_color_cache()
        end
        if sfui.common and sfui.common.invalidate_panels_cache then
            sfui.common.invalidate_panels_cache()
        end
        if sfui.highest and sfui.highest.ClearValidationCache then
            sfui.highest.ClearValidationCache()
        end
        if sfui.events and sfui.events.SendMessage then
            sfui.events.SendMessage("SFUI_SPEC_CHANGED", cachedSpecID, oldID)
        end
        if sfui.BroadcastSpecChanged then
            sfui.BroadcastSpecChanged(cachedSpecID)
        end
    end
    return changed
end

function sfui.talents.update_cached_spec_id()
    if sfui.talents._specResolver then
        local sID, sIdx, sRole = sfui.talents._specResolver()
        sfui.talents.set_cached_spec(sID, sIdx, sRole)
    end
    return cachedSpecID
end

--- Returns the active specialization ID (e.g. 71 for Arms, 250 for Blood)
--- on both Retail and Camelot/Classic. Instant O(1) hot-path query.
function sfui.talents.get_current_spec_id()
    if cachedSpecID == 0 then
        sfui.talents.update_cached_spec_id()
    end
    return cachedSpecID
end
sfui.common.get_current_spec_id = sfui.talents.get_current_spec_id

--- Returns the dominant specialization ID based on spent talent points in Classic/Camelot,
--- or the active specialization ID in Retail.
function sfui.talents.get_dominant_spec_id()
    return sfui.talents.get_current_spec_id()
end
sfui.common.get_dominant_spec_id = sfui.talents.get_dominant_spec_id

--- Returns the current spec index (1..4 on Retail, or 1..3 dominant tree on Classic)
function sfui.talents.get_current_spec_index()
    if cachedSpecIndex == 0 then
        sfui.talents.update_cached_spec_id()
    end
    return cachedSpecIndex
end
sfui.common.get_current_spec_index = sfui.talents.get_current_spec_index

--- Returns effective loot specialization ID
function sfui.talents.get_effective_loot_spec_id()
    if sfui.talents._lootSpecResolver then
        return sfui.talents._lootSpecResolver()
    end
    return sfui.talents.get_current_spec_id(), true
end
sfui.common.get_effective_loot_spec_id = sfui.talents.get_effective_loot_spec_id

function sfui.talents.invalidate_player_specs_cache()
    cachedPlayerSpecs   = nil
    cachedPlayerSpecIDs = nil
end
sfui.common.invalidate_player_specs_cache = sfui.talents.invalidate_player_specs_cache

function sfui.talents.get_player_specs()
    if cachedPlayerSpecs and cachedPlayerSpecIDs and #cachedPlayerSpecIDs > 0 then
        return cachedPlayerSpecs, cachedPlayerSpecIDs
    end
    if sfui.talents._specsCacheBuilder then
        cachedPlayerSpecs, cachedPlayerSpecIDs = sfui.talents._specsCacheBuilder()
        return cachedPlayerSpecs, cachedPlayerSpecIDs
    end
    return {}, {}
end
sfui.common.get_player_specs = sfui.talents.get_player_specs

--- Returns spec options specifically for spec colors UI.
function sfui.talents.get_spec_color_options()
    if sfui.talents._specColorOptionsBuilder then
        return sfui.talents._specColorOptionsBuilder()
    end
    return sfui.talents.get_player_specs()
end
sfui.common.get_spec_color_options = sfui.talents.get_spec_color_options

local C_Spec = _G.C_SpecializationInfo or {}
local GetSpecializationInfoByID = C_Spec.GetSpecializationInfoByID or _G.GetSpecializationInfoByID

function sfui.talents.get_spec_info(specID)
    if not specID or specID == 0 then return nil end
    local bridge = sfui.talents.SPEC_BRIDGE and sfui.talents.SPEC_BRIDGE[specID]
    if bridge then
        return bridge.retailID or bridge.specID, bridge.name, nil, bridge.icon, (bridge.isTank and "TANK") or (bridge.isHealer and "HEALER") or "DAMAGER", 1
    end
    local specs = sfui.talents.get_player_specs()
    if specs and specs[specID] then
        local s = specs[specID]
        return s.id, s.name, nil, s.icon, s.role, s.primaryStat
    end
    if sfui.talents.CLASSIC_SPEC_LOOKUP and sfui.talents.CLASSIC_SPEC_LOOKUP[specID] then
        local c = sfui.talents.CLASSIC_SPEC_LOOKUP[specID]
        return c.specID, c.name, nil, c.icon, (c.role == "TANK" and "TANK") or (c.role == "HEAL" and "HEALER") or "DAMAGER", 1
    end
    if GetSpecializationInfoByID then
        return GetSpecializationInfoByID(specID)
    end
    return nil
end
sfui.common.get_spec_info = sfui.talents.get_spec_info

function sfui.talents.get_spec_name(specID)
    if not specID or specID == 0 then return "Current Spec" end
    local bridge = sfui.talents.SPEC_BRIDGE and sfui.talents.SPEC_BRIDGE[specID]
    if bridge and bridge.name then return bridge.name end
    local specs = sfui.talents.get_player_specs()
    if specs and specs[specID] and specs[specID].name then
        return specs[specID].name
    end
    if sfui.talents.CLASSIC_SPEC_LOOKUP and sfui.talents.CLASSIC_SPEC_LOOKUP[specID] then
        return sfui.talents.CLASSIC_SPEC_LOOKUP[specID].name
    end
    if GetSpecializationInfoByID then
        local _, name = GetSpecializationInfoByID(specID)
        if name and name ~= "" then return name end
    end
    return "Spec " .. specID
end
sfui.common.get_spec_name = sfui.talents.get_spec_name

function sfui.talents.get_spec_icon(specID)
    if not specID or specID == 0 then return nil end
    local bridge = sfui.talents.SPEC_BRIDGE and sfui.talents.SPEC_BRIDGE[specID]
    if bridge and bridge.icon then return bridge.icon end
    local specs = sfui.talents.get_player_specs()
    if specs and specs[specID] and specs[specID].icon then
        return specs[specID].icon
    end
    if sfui.talents.CLASSIC_SPEC_LOOKUP and sfui.talents.CLASSIC_SPEC_LOOKUP[specID] then
        return sfui.talents.CLASSIC_SPEC_LOOKUP[specID].icon
    end
    if GetSpecializationInfoByID then
        local _, _, _, icon = GetSpecializationInfoByID(specID)
        return icon
    end
    return nil
end
sfui.common.get_spec_icon = sfui.talents.get_spec_icon

local GetSpecializationRole = C_Spec.GetSpecializationRole or _G.GetSpecializationRole
local GetSpecializationInfo = C_Spec.GetSpecializationInfo or _G.GetSpecializationInfo

function sfui.talents.get_spec_role(specIDorIndex)
    if not specIDorIndex or specIDorIndex == 0 or specIDorIndex == "NONE" then
        return cachedSpecRole or "DAMAGER"
    end
    if SfuiDB and SfuiDB.gear and SfuiDB.gear[specIDorIndex] then
        local sdb = SfuiDB.gear[specIDorIndex]
        if sdb.role and sdb.role ~= "" and sdb.role ~= "NONE" then
            return sdb.role
        elseif sdb.classic_role then
            if sdb.classic_role == "TANK" then return "TANK"
            elseif sdb.classic_role == "HEAL" then return "HEALER"
            elseif sdb.classic_role == "DPS" then return "DAMAGER"
            end
        elseif sdb.is_tank or sdb.armor_ilvl_prio then
            return "TANK"
        elseif sdb.is_healer then
            return "HEALER"
        end
    end
    if type(specIDorIndex) == "number" and specIDorIndex <= 4 then
        if GetSpecializationRole then
            local role = GetSpecializationRole(specIDorIndex)
            if role and role ~= "NONE" then return role end
        end
        if GetSpecializationInfo then
            local _, _, _, _, role = GetSpecializationInfo(specIDorIndex)
            if role and role ~= "NONE" then return role end
        end
    else
        local specs = sfui.talents.get_player_specs()
        if specs and specs[specIDorIndex] and specs[specIDorIndex].role then
            return specs[specIDorIndex].role
        end
        if GetSpecializationInfoByID then
            local _, _, _, _, role = GetSpecializationInfoByID(specIDorIndex)
            if role and role ~= "NONE" then return role end
        end
    end
    return "DAMAGER"
end
sfui.common.get_spec_role = sfui.talents.get_spec_role

--- Checks if a talent or spell is active/known by the player.
function sfui.talents.is_talent_known(targetSpellID)
    if not targetSpellID or targetSpellID <= 0 then return false end
    if sfui.talents._talentKnownResolver then
        return sfui.talents._talentKnownResolver(targetSpellID)
    end
    if _G.IsPlayerSpell and _G.IsPlayerSpell(targetSpellID) then return true end
    if _G.IsSpellKnown and _G.IsSpellKnown(targetSpellID) then return true end
    return false
end
sfui.common.is_talent_known = sfui.talents.is_talent_known

-- ────────────────────────────────────────────────────────────────────────────
-- Global Event Routing & Cache Invalidation
-- ────────────────────────────────────────────────────────────────────────────
function sfui.talents.invalidate_spec_cache()
    cachedSpecID    = 0
    cachedSpecIndex = 0
    cachedSpecRole  = nil
    sfui.talents.invalidate_player_specs_cache()
    sfui.talents.update_cached_spec_id()

    if sfui.colors and sfui.colors.invalidate_spec_color_cache then
        sfui.colors.invalidate_spec_color_cache()
    elseif sfui.common and sfui.common.invalidate_spec_color_cache then
        sfui.common.invalidate_spec_color_cache()
    end
    if sfui.common and sfui.common.invalidate_panels_cache then
        sfui.common.invalidate_panels_cache()
    end
    if sfui.highest and sfui.highest.ClearValidationCache then
        sfui.highest.ClearValidationCache()
    end

    if sfui.isClassic then
        sfui.talents.get_player_specs()
        if sfui.gear and sfui.gear.UpdateStatUI then
            sfui.gear.UpdateStatUI()
        end
        if SfuiGearManagerFrame and SfuiGearManagerFrame.tabBtns and sfui.talents.get_spec_icon then
            for id, btn in pairs(SfuiGearManagerFrame.tabBtns) do
                if btn.tex then
                    local ic = sfui.talents.get_spec_icon(id)
                    if ic then
                        btn.tex:SetTexture(ic)
                    end
                end
            end
        end
    end
end

local function on_login_or_enter()
    sfui.talents.get_player_class()
    sfui.talents.invalidate_spec_cache()
end

sfui.events.RegisterEvent("PLAYER_LOGIN", on_login_or_enter)
sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", on_login_or_enter)
sfui.events.RegisterEvent("PLAYER_TALENT_UPDATE", sfui.talents.invalidate_spec_cache)
sfui.events.RegisterEvent("TRAIT_CONFIG_UPDATED", sfui.talents.invalidate_spec_cache)
sfui.events.RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", sfui.talents.invalidate_spec_cache)
sfui.events.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", sfui.talents.invalidate_spec_cache)
sfui.events.RegisterEvent("SPEC_INVOLUNTARILY_CHANGED", sfui.talents.invalidate_spec_cache)
sfui.events.RegisterEvent("CHARACTER_POINTS_CHANGED", sfui.talents.invalidate_spec_cache)
sfui.events.RegisterEvent("TRAIT_TREE_CURRENCY_INFO_UPDATED", sfui.talents.invalidate_spec_cache)
sfui.events.RegisterEvent("ACTIVE_COMBAT_CONFIG_CHANGED", sfui.talents.invalidate_spec_cache)
sfui.events.RegisterEvent("PLAYER_LEVEL_UP", sfui.talents.invalidate_spec_cache)
