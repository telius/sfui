local addonName, addon = ...
sfui = sfui or {}
sfui.talents = sfui.talents or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/core/talents_standard.lua
--  Retail Specialization, Talent Tree & Trait Inspection Engine
-- ══════════════════════════════════════════════════════════════════════════════

local isRetail = sfui.isRetail
if isRetail == nil then
    local projectID = _G.WOW_PROJECT_ID or 1
    local _, _, _, tocVersionNum = _G.GetBuildInfo()
    tocVersionNum = tonumber(tocVersionNum) or 0
    local isForever = (tocVersionNum >= 16000 and tocVersionNum < 20000)
    isRetail = (projectID == 1) and not isForever
end

if not isRetail then
    return
end

local _G = _G
local C_SpecializationInfo = _G.C_SpecializationInfo or {}
local GetSpecialization         = C_SpecializationInfo.GetSpecialization or _G.GetSpecialization
local GetSpecializationInfo     = C_SpecializationInfo.GetSpecializationInfo or _G.GetSpecializationInfo
local GetSpecializationInfoByID = C_SpecializationInfo.GetSpecializationInfoByID or _G.GetSpecializationInfoByID
local GetSpecializationRole     = C_SpecializationInfo.GetSpecializationRole or _G.GetSpecializationRole
local GetNumSpecializations     = C_SpecializationInfo.GetNumSpecializations or _G.GetNumSpecializations
local GetLootSpecialization     = C_SpecializationInfo.GetLootSpecialization or _G.GetLootSpecialization

-- ────────────────────────────────────────────────────────────────────────────
-- Retail Spec Discovery
-- ────────────────────────────────────────────────────────────────────────────
local function RetailSpecResolver()
    local specIndex = (GetSpecialization and GetSpecialization()) or 0
    if specIndex and specIndex > 0 then
        local specID, name, desc, icon, role, primaryStat = GetSpecializationInfo(specIndex)
        if specID and specID > 0 then
            return specID, specIndex, role
        end
    end

    -- Fallback for low-level characters without a chosen specialization
    local _, pClassID = sfui.talents.get_player_class()
    return 0, 0, "DAMAGER"
end
sfui.talents._specResolver = RetailSpecResolver

local function RetailSpecsCacheBuilder()
    local numSpecs = (GetNumSpecializations and GetNumSpecializations()) or 0
    local specs = {}
    local specIDs = {}

    for i = 1, numSpecs do
        local specID, name, description, icon, role, primaryStat = GetSpecializationInfo(i)
        if specID then
            specs[specID] = {
                id          = specID,
                name        = name,
                description = description,
                icon        = icon,
                role        = role,
                primaryStat = primaryStat,
                index       = i,
            }
            specIDs[#specIDs + 1] = specID
        end
    end

    return specs, specIDs
end
sfui.talents._specsCacheBuilder = RetailSpecsCacheBuilder
sfui.talents._specColorOptionsBuilder = RetailSpecsCacheBuilder

local function RetailLootSpecResolver()
    local lootSpec = GetLootSpecialization and GetLootSpecialization() or 0
    if lootSpec and lootSpec > 0 then
        return lootSpec, false
    end
    return sfui.talents.get_current_spec_id(), true
end
sfui.talents._lootSpecResolver = RetailLootSpecResolver

-- ────────────────────────────────────────────────────────────────────────────
-- Retail Talent & Trait Inspection Engine (C_ClassTalents / C_Traits)
-- ────────────────────────────────────────────────────────────────────────────
local _talentCache = {}
local _talentCacheConfigID = nil

local function RetailTalentKnownResolver(targetSpellID)
    if not targetSpellID or targetSpellID <= 0 then return false end

    -- 1. Direct spellbook / known checks
    if _G.IsPlayerSpell and _G.IsPlayerSpell(targetSpellID) then return true end
    if _G.IsSpellKnownOrOverridesKnown and _G.IsSpellKnownOrOverridesKnown(targetSpellID) then return true end
    if _G.IsSpellKnown and _G.IsSpellKnown(targetSpellID) then return true end
    local C_Spell = _G.C_Spell
    if C_Spell and C_Spell.IsSpellLearned and C_Spell.IsSpellLearned(targetSpellID) then return true end

    -- 2. Trait / Class Talent tree inspection for passive talents
    local C_ClassTalents = _G.C_ClassTalents
    local C_Traits = _G.C_Traits
    if not C_ClassTalents or not C_ClassTalents.GetActiveConfigID or not C_Traits or not C_Traits.GetConfigInfo then
        return false
    end

    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID or configID <= 0 then return false end

    if _talentCacheConfigID ~= configID then
        table.wipe(_talentCache)
        _talentCacheConfigID = configID

        local configInfo = C_Traits.GetConfigInfo(configID)
        if configInfo and configInfo.treeIDs then
            for _, treeID in ipairs(configInfo.treeIDs) do
                local nodes = C_Traits.GetTreeNodes and C_Traits.GetTreeNodes(treeID)
                if nodes then
                    for _, nodeID in ipairs(nodes) do
                        local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
                        if nodeInfo and ((nodeInfo.activeRank and nodeInfo.activeRank > 0) or (nodeInfo.currentRank and nodeInfo.currentRank > 0)) then
                            if nodeInfo.activeEntry then
                                local entryInfo = C_Traits.GetEntryInfo(configID, nodeInfo.activeEntry.entryID)
                                if entryInfo and entryInfo.definitionID then
                                    local defInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
                                    if defInfo and defInfo.spellID and defInfo.spellID > 0 then
                                        _talentCache[defInfo.spellID] = true
                                    end
                                end
                            end
                            if nodeInfo.entryIDsWithCommittedRanks then
                                for _, entryID in ipairs(nodeInfo.entryIDsWithCommittedRanks) do
                                    local entry = C_Traits.GetEntryInfo(configID, entryID)
                                    if entry and entry.definitionID then
                                        local defInfo = C_Traits.GetDefinitionInfo(entry.definitionID)
                                        if defInfo and defInfo.spellID and defInfo.spellID > 0 then
                                            _talentCache[defInfo.spellID] = true
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

    return _talentCache[targetSpellID] == true
end
sfui.talents._talentKnownResolver = RetailTalentKnownResolver
