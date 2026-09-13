local addonName, addon = ...
sfui = sfui or {}
sfui.common = {}

function sfui.common.print(msg, ...)
    if sfui.config and sfui.config.prefix then
        print(sfui.config.prefix .. " " .. tostring(msg), ...)
    else
        print("|cff6600ffsfui:|r " .. tostring(msg), ...)
    end
end

local _issecretvalue = _G.issecretvalue
local C_Secrets      = _G.C_Secrets

local function issecretvalue(val)
    if val == nil then return false end
    if _issecretvalue then
        return _issecretvalue(val)
    end
    if C_Secrets and C_Secrets.HasSecretRestrictions and not C_Secrets.HasSecretRestrictions() then
        return false
    end
    return false
end
sfui.common.issecretvalue = issecretvalue

-- Dedicated Addon Tooltip (Zero global GameTooltip taint, zero UIWidgetManager registration)
local sfuiTooltip = CreateFrame("GameTooltip", "SfuiGameTooltip", UIParent, "TooltipBackdropTemplate")
if _G.TooltipDataHandlerMixin then
    Mixin(sfuiTooltip, _G.TooltipDataHandlerMixin)
elseif _G.GameTooltipDataMixin then
    Mixin(sfuiTooltip, _G.GameTooltipDataMixin)
end
sfuiTooltip:SetFrameStrata("TOOLTIP")
sfui.tooltip = sfuiTooltip
sfui.common.tooltip = sfuiTooltip

-- Robust helper to check if an aura/ID is present, even if it's a secret value
function sfui.common.HasAuraInstanceID(value)
    if value == nil then return false end
    if issecretvalue(value) then return true end
    if type(value) == "number" and value == 0 then return false end
    return true
end

-- Safe numeric comparison
function sfui.common.IsNumericAndPositive(value)
    if value == nil then return false end
    return type(value) == "number" and value > 0
end

-- ────────────────────────────────────────────────────────────────────────────
-- Pre-computed String Lookup Tables (Zero-Allocation Hot Path)
-- ────────────────────────────────────────────────────────────────────────────
local INT_STR_LUT = {}
for i = 0, 200 do
    INT_STR_LUT[i] = tostring(i)
end

local DEC_STR_LUT = {}
for i = 1, 50 do
    DEC_STR_LUT[i] = string.format("%.1f", i / 10)
end

local FMT_PATTERNS = {
    [0] = "%.0f",
    [1] = "%.1f",
    [2] = "%.2f",
}

--- Fast zero-allocation integer-to-string lookup for numbers 0-200.
--- Falls back to tostring for larger values and handles secret values safely.
function sfui.common.get_cached_int_string(val)
    if val == nil then return "" end
    local t = type(val)
    if t == "number" then
        local floorVal = math.floor(val)
        return INT_STR_LUT[floorVal] or tostring(floorVal)
    elseif t == "string" then
        return val
    end
    if issecretvalue(val) then return val end
    return tostring(val)
end

--- Safe zero-allocation duration formatting.
--- Utilizes pre-computed LUT for integer seconds (0-200s) and fast sub-5s decimals (0.1-5.0s).
function sfui.common.SafeFormatDuration(value, decimals)
    if value == nil then return "" end
    if issecretvalue(value) then return value end

    local num = tonumber(value)
    if not num then return tostring(value) end

    decimals = decimals or 0
    if decimals == 0 then
        local intVal = math.floor(num + 0.5)
        if intVal >= 0 and intVal <= 200 then
            return INT_STR_LUT[intVal]
        end
    elseif decimals == 1 and num >= 0.1 and num <= 5.0 then
        local decKey = math.floor(num * 10 + 0.5)
        if decKey >= 1 and decKey <= 50 then
            return DEC_STR_LUT[decKey]
        end
    end

    local fmt = FMT_PATTERNS[decimals] or ("%." .. decimals .. "f")
    return string.format(fmt, num)
end

-- Helper: Check if Mounted OR in Druid Travel Form (Spell 783)
function sfui.common.is_mounted_or_travel_form()
    if IsMounted() then return true end
    if sfui.common.get_player_class() == "DRUID" and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        return C_UnitAuras.GetPlayerAuraBySpellID(783) ~= nil
    end
    return false
end

-- Helper: Check for Dragonriding state (Vigor)
function sfui.common.IsDragonriding()
    if not sfui.common.is_mounted_or_travel_form() then return false end

    -- Check for Vigor (Enum.PowerType.AlternateMount = 29)
    -- This resource is only active/max > 0 when on a Dragonriding/Skyriding mount
    if UnitPowerMax("player", 29) > 0 then
        return true
    end

    -- Fallback: Check for Gliding Info
    if C_PlayerInfo and C_PlayerInfo.GetGlidingInfo then
        local _, canGlide = C_PlayerInfo.GetGlidingInfo()
        if canGlide then return true end
    end
    return false
end

-- Safe helper to check if player is on GCD and get the duration
function sfui.common.GetGCDInfo()
    if C_Spell and C_Spell.GetSpellCooldown then
        local ci = C_Spell.GetSpellCooldown(61304)
        if ci and ci.duration and ci.duration > 0 then
            return true, ci.duration
        end
    end
    return false, 0
end

-- Safe helper to get a duration object for a spell (nil check is non-secret)
function sfui.common.GetCooldownDurationObj(spellID)
    if not spellID then return nil end
    local obj
    if C_Spell and C_Spell.GetSpellChargeDuration then
        obj = C_Spell.GetSpellChargeDuration(spellID)
    end
    if not obj and C_Spell and C_Spell.GetSpellCooldownDuration then
        obj = C_Spell.GetSpellCooldownDuration(spellID)
    end
    return obj
end

-- Check if a cooldown frame is showing an active cooldown
function sfui.common.IsCooldownFrameActive(cooldownFrame)
    if not cooldownFrame or not cooldownFrame.GetCooldownDuration then return false end

    local duration = cooldownFrame:GetCooldownDuration()
    if not duration then return false end

    -- If duration is secret, check if it's just GCD
    if issecretvalue(duration) then
        local onGCD = sfui.common.GetGCDInfo()
        if onGCD then return false end
        return true
    end

    if duration == 0 then
        return false
    end

    local onGCD, gcdDur = sfui.common.GetGCDInfo()
    if onGCD and duration <= (gcdDur * 1000 + 10) then
        return false
    end

    local threshold = (sfui.config and sfui.config.castBar and sfui.config.castBar.gcdThreshold) or 1510
    return duration > threshold
end

-- Safe comparison helpers (Crash-proof against Secret Values in M+)
function sfui.common.SafeGT(val, target)
    if val == nil or target == nil then return false end
    if issecretvalue(val) or issecretvalue(target) then return false end
    if type(val) == "number" and type(target) == "number" then
        return val > target
    end
    return false
end

-- Safe comparison helpers (Crash-proof against Secret Values in M+)
function sfui.common.SafeLT(val, target)
    if val == nil or target == nil then return false end
    if issecretvalue(val) or issecretvalue(target) then return false end
    if type(val) == "number" and type(target) == "number" then
        return val < target
    end
    return false
end

-- Safe arithmetic to bypass "arithmetic on secret number" errors when tainted.
function sfui.common.SafeArithmetic(op, v1, v2)
    if v1 == nil or v2 == nil then return 0 end
    if issecretvalue(v1) or issecretvalue(v2) then return 0 end
    if op == "+" then return v1 + v2 end
    if op == "-" then return v1 - v2 end
    if op == "*" then return v1 * v2 end
    if op == "/" then return (v2 ~= 0) and (v1 / v2) or 0 end
    return 0
end

function sfui.common.SafeValue(val, fallback)
    if val == nil then return fallback end
    if issecretvalue(val) then return val end
    return val
end

function sfui.common.SafeNotFalse(val)
    if val == nil then return true end
    if issecretvalue(val) then return true end
    return val ~= false
end

-- Safely set text on a fontstring (SetText accepts secret values)
function sfui.common.SafeSetText(fontString, text, decimals)
    if not fontString then return end
    -- if decimals is nil and text is a string, skip duration formatting to avoid 0.0 suffix
    if decimals == nil and type(text) == "string" then
        fontString:SetText(text)
    else
        fontString:SetText(sfui.common.SafeFormatDuration(text, decimals) or "")
    end
end

-- Safely set value on a statusbar (SetValue accepts secret values)
function sfui.common.SafeSetValue(bar, value)
    if not bar or not bar.SetValue then return end
    bar:SetValue(value or 0)
end

-- Safely set money display in a tooltip using securecall to avoid arithmetic taint.
function sfui.common.SafeSetTooltipMoney(tooltip, amount, label)
    if not tooltip or amount == nil then return end

    local coinStr = sfui.common.SafeGetCoinTextureString(amount)

    if label then
        tooltip:AddDoubleLine(label, coinStr, 1, 1, 1, 1, 1, 1)
    else
        tooltip:AddLine(coinStr)
    end
end

-- Safely add a money line using GetCoinTextureString
function sfui.common.SafeAddMoneyLine(tooltip, label, amount)
    if not tooltip or amount == nil then return end

    if issecretvalue(amount) then
        tooltip:AddLine((label or "") .. "|cff00ffff[Protected Data]|r")
        return
    end

    if type(amount) == "number" and GetCoinTextureString then
        local coinStr = GetCoinTextureString(amount)
        if coinStr then
            tooltip:AddLine((label or "") .. coinStr)
            return
        end
    end
    tooltip:AddLine((label or "") .. "|cff00ffff[Protected Data]|r")
end

-- Safely get a coin texture string
function sfui.common.SafeGetCoinTextureString(amount)
    if amount == nil then return "" end
    if issecretvalue(amount) then return "|cff00ffff[Protected]|r" end
    if type(amount) == "number" and GetCoinTextureString then
        return GetCoinTextureString(amount) or ""
    end
    return "|cff00ffff[Protected]|r"
end

-- Safely compare units (UnitIsUnit crashes on secret values if execution is tainted)
function sfui.common.SafeUnitIsUnit(unit1, unit2)
    if not unit1 or not unit2 then return false end
    if issecretvalue(unit1) or issecretvalue(unit2) then
        if type(unit1) == "string" and type(unit2) == "string" then
            return unit1 == unit2
        end
        return false
    end
    if UnitIsUnit then
        return UnitIsUnit(unit1, unit2) or false
    end
    return false
end

function sfui.common.copy(t)
    if type(t) ~= "table" then return t end
    local res = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            res[k] = sfui.common.copy(v)
        else
            res[k] = v
        end
    end
    return res
end

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

local wipe = wipe
local C_Timer = C_Timer

-- Returns the authoritative player class ID (1..13)
function sfui.common.get_player_class_id()
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

-- Returns the cached player class filename and ID (e.g., "WARRIOR", 1)
function sfui.common.get_player_class()
    if not cachedPlayerClass or cachedPlayerClassID == 0 then
        sfui.common.get_player_class_id()
    end
    return cachedPlayerClass, cachedPlayerClassID
end

-- ────────────────────────────────────────────────────────────────────────────
-- Specialization & Class Engine (C_SpecializationInfo Modernization)
-- ────────────────────────────────────────────────────────────────────────────
local C_Spec                    = _G.C_SpecializationInfo or {}
local GetSpecialization         = C_Spec.GetSpecialization or _G.GetSpecialization
local GetSpecializationInfo     = C_Spec.GetSpecializationInfo or _G.GetSpecializationInfo
local GetSpecializationInfoByID = C_Spec.GetSpecializationInfoByID or _G.GetSpecializationInfoByID
local GetSpecializationRole     = C_Spec.GetSpecializationRole or _G.GetSpecializationRole
local GetNumSpecializations     = C_Spec.GetNumSpecializations or _G.GetNumSpecializations
local GetLootSpecialization     = C_Spec.GetLootSpecialization or _G.GetLootSpecialization

local cachedSpecID        = 0
local cachedSpecIndex     = 0
local cachedPlayerSpecs   = nil
local cachedPlayerSpecIDs = nil

local function build_player_specs_cache()
    if cachedPlayerSpecs and cachedPlayerSpecIDs and #cachedPlayerSpecIDs > 0 then
        return cachedPlayerSpecs, cachedPlayerSpecIDs
    end

    cachedPlayerSpecs   = {}
    cachedPlayerSpecIDs = {}

    local n = (GetNumSpecializations and GetNumSpecializations()) or 0
    for i = 1, n do
        local specID, name, desc, icon, role, primaryStat = GetSpecializationInfo(i)
        if specID and specID > 0 then
            cachedPlayerSpecs[specID] = {
                id          = specID,
                name        = name or ("Spec " .. specID),
                icon        = icon or 134400,
                role        = role or "DAMAGER",
                primaryStat = primaryStat,
                index       = i,
            }
            cachedPlayerSpecIDs[#cachedPlayerSpecIDs + 1] = specID
        end
    end
    return cachedPlayerSpecs, cachedPlayerSpecIDs
end

local function update_cached_spec_id()
    local spec = GetSpecialization and GetSpecialization()
    cachedSpecIndex = spec or 0
    if spec and spec > 0 then
        local specID = select(1, GetSpecializationInfo(spec))
        if specID and specID > 0 then
            if specID ~= cachedSpecID then
                cachedSpecID = specID
                if sfui.common and sfui.common.invalidate_spec_color_cache then
                    sfui.common.invalidate_spec_color_cache()
                end
            end
            return
        end
    end
    cachedSpecID = 0
end

sfui.events.RegisterEvent("PLAYER_LOGIN", function()
    sfui.common.get_player_class()
    update_cached_spec_id()
    build_player_specs_cache()
    if sfui.common and sfui.common.invalidate_panels_cache then
        sfui.common.invalidate_panels_cache()
    end
end)

sfui.events.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function()
    update_cached_spec_id()
    build_player_specs_cache()
    if sfui.common and sfui.common.invalidate_panels_cache then
        sfui.common.invalidate_panels_cache()
    end
    if SfuiDB then SfuiDB._populationRetryDone = nil end
end)

sfui.events.RegisterEvent("SPEC_INVOLUNTARILY_CHANGED", function()
    update_cached_spec_id()
    build_player_specs_cache()
    if sfui.common and sfui.common.invalidate_panels_cache then
        sfui.common.invalidate_panels_cache()
    end
end)

sfui.events.RegisterEvent("PLAYER_TALENT_UPDATE", function()
    update_cached_spec_id()
    build_player_specs_cache()
    if sfui.common and sfui.common.invalidate_panels_cache then
        sfui.common.invalidate_panels_cache()
    end
end)

function sfui.common.get_current_spec_id()
    if cachedSpecID == 0 then update_cached_spec_id() end
    return cachedSpecID
end

function sfui.common.get_current_spec_index()
    if cachedSpecIndex == 0 then update_cached_spec_id() end
    return cachedSpecIndex
end

function sfui.common.get_effective_loot_spec_id()
    local lootSpec = GetLootSpecialization and GetLootSpecialization() or 0
    if lootSpec and lootSpec > 0 then
        return lootSpec, false
    end
    return sfui.common.get_current_spec_id(), true
end

function sfui.common.get_player_specs()
    local specs, specIDs = build_player_specs_cache()
    return specs, specIDs
end

function sfui.common.get_spec_info(specID)
    if not specID or specID == 0 then return nil end
    local specs = sfui.common.get_player_specs()
    if specs and specs[specID] then
        local s = specs[specID]
        return s.id, s.name, nil, s.icon, s.role, s.primaryStat
    end
    return GetSpecializationInfoByID(specID)
end

function sfui.common.get_spec_name(specID)
    if not specID or specID == 0 then return "Current Spec" end
    local specs = sfui.common.get_player_specs()
    if specs and specs[specID] and specs[specID].name then
        return specs[specID].name
    end
    local _, name = GetSpecializationInfoByID(specID)
    return name or ("Spec " .. specID)
end

function sfui.common.get_spec_icon(specID)
    if not specID or specID == 0 then return nil end
    local specs = sfui.common.get_player_specs()
    if specs and specs[specID] and specs[specID].icon then
        return specs[specID].icon
    end
    local _, _, _, icon = GetSpecializationInfoByID(specID)
    return icon
end

function sfui.common.get_spec_role(specIDorIndex)
    if not specIDorIndex or specIDorIndex == 0 or specIDorIndex == "NONE" then
        return "DAMAGER"
    end
    if type(specIDorIndex) == "number" and specIDorIndex <= 4 then
        if GetSpecializationRole then
            local role = GetSpecializationRole(specIDorIndex)
            if role and role ~= "NONE" then return role end
        end
        local _, _, _, _, role = GetSpecializationInfo(specIDorIndex)
        if role and role ~= "NONE" then return role end
    else
        local specs = sfui.common.get_player_specs()
        if specs and specs[specIDorIndex] and specs[specIDorIndex].role then
            return specs[specIDorIndex].role
        end
        local _, _, _, _, role = GetSpecializationInfoByID(specIDorIndex)
        if role and role ~= "NONE" then return role end
    end
    return "DAMAGER"
end

-- ────────────────────────────────────────────────────────────────────────────
-- Spec Color Cache (Zero table allocation in high-frequency update loops)
-- ────────────────────────────────────────────────────────────────────────────
local _specColorTableCache = {}

function sfui.common.invalidate_spec_color_cache()
    table.wipe(_specColorTableCache)
end

sfui.events.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", sfui.common.invalidate_spec_color_cache)
sfui.events.RegisterEvent("SPEC_INVOLUNTARILY_CHANGED", sfui.common.invalidate_spec_color_cache)

-- Returns cached { r, g, b, a } table for a specialization ID (zero allocations)
function sfui.common.get_spec_color_table(specID)
    specID = (specID and specID > 0 and specID) or sfui.common.get_current_spec_id() or 0
    local cached = _specColorTableCache[specID]
    if cached then return cached end

    local r, g, b, a = 0.0, 0.8, 1.0, 1.0
    if not specID or specID == 0 then
        r, g, b, a = 0.35, 0.35, 0.35, 1.0
    else
        local specColor = (SfuiDB and SfuiDB.spec_colors and SfuiDB.spec_colors[specID])
            or (sfui.config and sfui.config.spec_colors and sfui.config.spec_colors[specID])
        if specColor then
            r, g, b, a = specColor[1], specColor[2], specColor[3], specColor[4] or 1.0
        else
            local _, _, _, _, _, classFile = GetSpecializationInfoByID(specID)
            local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
            if cc then
                r, g, b, a = cc.r, cc.g, cc.b, 1.0
            end
        end
    end

    local t = { r, g, b, a }
    _specColorTableCache[specID] = t
    return t
end

-- Returns RGB(A) color for a specialization ID, falling back to class color or cyan
function sfui.common.get_spec_color(specID)
    local t = sfui.common.get_spec_color_table(specID)
    return t[1], t[2], t[3], t[4]
end

-- ────────────────────────────────────────────────────────────────────────────
-- Talent & Trait Inspection Engine
-- ────────────────────────────────────────────────────────────────────────────
local _talentCache = {}
local _talentCacheConfigID = nil

local function invalidate_talent_cache()
    table.wipe(_talentCache)
    _talentCacheConfigID = nil
    if sfui.highest and sfui.highest.ClearValidationCache then
        sfui.highest.ClearValidationCache()
    end
end

sfui.events.RegisterEvent("PLAYER_TALENT_UPDATE", invalidate_talent_cache)
sfui.events.RegisterEvent("TRAIT_CONFIG_UPDATED", invalidate_talent_cache)
sfui.events.RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", invalidate_talent_cache)
sfui.events.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", invalidate_talent_cache)
sfui.events.RegisterEvent("SPEC_INVOLUNTARILY_CHANGED", invalidate_talent_cache)

--- Checks if a talent or spell is active/known by the player.
--- Handles active spells, passives in the spellbook, and talent tree passives (Not In Spellbook) via C_Traits.
--- @param targetSpellID number
--- @return boolean
function sfui.common.is_talent_known(targetSpellID)
    if not targetSpellID or targetSpellID <= 0 then return false end

    -- 1. Direct spellbook / known checks
    if IsPlayerSpell and IsPlayerSpell(targetSpellID) then return true end
    if IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(targetSpellID) then return true end
    if IsSpellKnown and IsSpellKnown(targetSpellID) then return true end
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

-- ────────────────────────────────────────────────────────────────────────────
-- Item & Slot Engine (C_Item Modernization & Unified Constants)
-- ────────────────────────────────────────────────────────────────────────────
local C_Item                          = _G.C_Item or {}
local C_Item_GetItemInfo              = C_Item.GetItemInfo or _G.GetItemInfo
local C_Item_GetItemInfoInstant       = C_Item.GetItemInfoInstant or _G.GetItemInfoInstant
local C_Item_GetDetailedItemLevelInfo = C_Item.GetDetailedItemLevelInfo or _G.GetDetailedItemLevelInfo
local C_Item_GetItemStats             = C_Item.GetItemStats or _G.GetItemStats
local C_Item_GetItemQualityColor      = C_Item.GetItemQualityColor or _G.GetItemQualityColor
local C_Item_GetItemQualityByID       = C_Item.GetItemQualityByID
local C_Item_RequestLoadItemDataByID  = C_Item.RequestLoadItemDataByID
local C_Item_GetItemCount             = C_Item.GetItemCount or _G.GetItemCount
local C_Item_GetItemSpecInfo          = C_Item.GetItemSpecInfo

local INVENTORY_SLOT_NAMES = {
    [1]  = "Head",
    [2]  = "Neck",
    [3]  = "Shoulders",
    [4]  = "Shirt",
    [5]  = "Chest",
    [6]  = "Waist",
    [7]  = "Legs",
    [8]  = "Feet",
    [9]  = "Wrists",
    [10] = "Hands",
    [11] = "Ring 1",
    [12] = "Ring 2",
    [13] = "Trinket 1",
    [14] = "Trinket 2",
    [15] = "Back",
    [16] = "Main Hand",
    [17] = "Off Hand",
    [19] = "Tabard",
}

local SLOT_KEY_NAMES = {
    head = "Head", neck = "Neck", shoulder = "Shoulder", back = "Back",
    chest = "Chest", wrist = "Wrist", hands = "Hands", waist = "Waist",
    legs = "Legs", feet = "Feet", weapon = "Weapon", ring = "Ring",
    trinket = "Trinket", other = "Other", token = "Other",
}

local STAT_NAME_MAP = {
    [1] = "ITEM_MOD_STRENGTH_SHORT",
    [2] = "ITEM_MOD_AGILITY_SHORT",
    [4] = "ITEM_MOD_INTELLECT_SHORT",
}

-- Returns localized display name or fallback for a numeric slot ID or slot string key
function sfui.common.get_slot_name(slot)
    if type(slot) == "number" then
        return INVENTORY_SLOT_NAMES[slot] or ("Slot " .. slot)
    elseif type(slot) == "string" then
        return SLOT_KEY_NAMES[slot:lower()] or slot
    end
    return "Unknown"
end

-- Returns localized short stat name (e.g. "Str", "Agi", "Int")
function sfui.common.get_stat_name(statID)
    local key = STAT_NAME_MAP[statID]
    return key and _G[key] or nil
end

-- Returns global constant key for a primary stat (e.g. "ITEM_MOD_STRENGTH_SHORT")
function sfui.common.get_stat_key(statID)
    return STAT_NAME_MAP[statID]
end

-- Maps itemEquipLoc (INVTYPE_*) to target inventory slot(s).
-- Returns: numSlots, slot1, slot2 (zero table allocations)
function sfui.common.get_slots_for_invtype(equipLoc, canDualWield1H, canDualWield2H)
    if not equipLoc then return 0 end
    if equipLoc == "INVTYPE_HEAD" then return 1, 1
    elseif equipLoc == "INVTYPE_NECK" then return 1, 2
    elseif equipLoc == "INVTYPE_SHOULDER" then return 1, 3
    elseif equipLoc == "INVTYPE_BODY" or equipLoc == "INVTYPE_SHIRT" then return 1, 4
    elseif equipLoc == "INVTYPE_CHEST" or equipLoc == "INVTYPE_ROBE" then return 1, 5
    elseif equipLoc == "INVTYPE_WAIST" then return 1, 6
    elseif equipLoc == "INVTYPE_LEGS" then return 1, 7
    elseif equipLoc == "INVTYPE_FEET" then return 1, 8
    elseif equipLoc == "INVTYPE_WRIST" then return 1, 9
    elseif equipLoc == "INVTYPE_HAND" or equipLoc == "INVTYPE_HANDS" then return 1, 10
    elseif equipLoc == "INVTYPE_FINGER" then return 2, 11, 12
    elseif equipLoc == "INVTYPE_TRINKET" then return 2, 13, 14
    elseif equipLoc == "INVTYPE_CLOAK" then return 1, 15
    elseif equipLoc == "INVTYPE_WEAPON" then
        if canDualWield1H then return 2, 16, 17 else return 1, 16 end
    elseif equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" or equipLoc == "INVTYPE_WEAPONOFFHAND" then
        return 1, 17
    elseif equipLoc == "INVTYPE_2HWEAPON" then
        if canDualWield2H then return 2, 16, 17 else return 1, 16 end
    elseif equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT" or equipLoc == "INVTYPE_THROWN" then
        return 1, 16
    elseif equipLoc == "INVTYPE_WEAPONMAINHAND" then
        return 1, 16
    elseif equipLoc == "INVTYPE_TABARD" then
        return 1, 19
    end
    return 0
end

-- Populates a target array with resolved slots (avoiding allocations) and returns numSlots, s1, s2
function sfui.common.populate_slots_for_invtype(targetTable, equipLoc, canDualWield1H, canDualWield2H)
    local n, s1, s2 = sfui.common.get_slots_for_invtype(equipLoc, canDualWield1H, canDualWield2H)
    if targetTable then
        targetTable[1] = s1
        targetTable[2] = s2
    end
    return n, s1, s2
end

-- Extracts numeric item ID from item ID, string ID, or hyperlink
function sfui.common.get_item_id(item)
    if not item then return nil end
    if type(item) == "number" then return item end
    if type(item) == "string" then
        local id = tonumber(item:match("item:(%d+)"))
        if id then return id end
        local numeric = tonumber(item)
        if numeric then return numeric end
        if C_Item_GetItemInfoInstant then
            local instantID = C_Item_GetItemInfoInstant(item)
            if instantID then return instantID end
        end
    end
    return nil
end
sfui.common.get_item_id_from_link = sfui.common.get_item_id

-- Resolves effective item level via C_Item with fallback to GetItemInfo
function sfui.common.get_item_level(itemLinkOrID)
    if not itemLinkOrID then return 0 end
    local ilvl = C_Item_GetDetailedItemLevelInfo and C_Item_GetDetailedItemLevelInfo(itemLinkOrID)
    if not ilvl or ilvl == 0 then
        if C_Item_GetItemInfo then
            ilvl = select(4, C_Item_GetItemInfo(itemLinkOrID))
        end
    end
    return ilvl or 0
end

-- Safe wrapper for C_Item.GetItemInfoInstant
function sfui.common.get_item_instant_info(item)
    if not item then return end
    if C_Item_GetItemInfoInstant then
        return C_Item_GetItemInfoInstant(item)
    end
end

-- Safe wrapper for C_Item.GetItemInfo
function sfui.common.get_item_info(item)
    if not item then return end
    if C_Item_GetItemInfo then
        return C_Item_GetItemInfo(item)
    end
end

-- Safe wrapper for C_Item.GetItemStats
function sfui.common.get_item_stats(itemLink)
    if not itemLink then return nil end
    if C_Item_GetItemStats then
        return C_Item_GetItemStats(itemLink)
    end
    return nil
end

-- Returns item quality integer (0..8)
function sfui.common.get_item_quality(item)
    if not item then return 1 end
    local itemID = type(item) == "number" and item or tonumber(type(item) == "string" and item:match("item:(%d+)"))
    if itemID and C_Item_GetItemQualityByID then
        local q = C_Item_GetItemQualityByID(itemID)
        if q then return q end
    end
    if C_Item_GetItemInfo then
        local _, _, quality = C_Item_GetItemInfo(item)
        if quality then return quality end
    end
    return 1
end

-- Returns r, g, b, hex for an item quality
function sfui.common.get_item_quality_color(quality)
    quality = tonumber(quality) or 1
    if C_Item_GetItemQualityColor then
        local r, g, b, hex = C_Item_GetItemQualityColor(quality)
        if r then return r, g, b, hex end
    end
    return 1, 1, 1, "ffffffff"
end

-- Safely preloads item data into client cache
function sfui.common.request_item_load(item)
    local itemID = sfui.common.get_item_id(item)
    if itemID and C_Item_RequestLoadItemDataByID then
        C_Item_RequestLoadItemDataByID(itemID)
    end
end

-- Safe wrapper for C_Item.GetItemCount
function sfui.common.get_item_count(item, includeBank)
    if not item then return 0 end
    if C_Item_GetItemCount then
        return C_Item_GetItemCount(item, includeBank) or 0
    end
    return 0
end

-- Safe wrapper for C_Item.GetItemSpecInfo (consolidated native query)
-- Accepts itemLink, string itemID, or numeric itemID
function sfui.common.get_item_spec_info(itemLinkOrID)
    if not itemLinkOrID then return nil end
    if not C_Item_GetItemSpecInfo then return nil end

    local specList = C_Item_GetItemSpecInfo(itemLinkOrID)
    if (not specList or #specList == 0) and type(itemLinkOrID) ~= "number" then
        local itemID = sfui.common.get_item_id(itemLinkOrID)
        if itemID and itemID > 0 then
            specList = C_Item_GetItemSpecInfo(itemID)
        end
    end
    return (specList and #specList > 0) and specList or nil
end

--- Classifies a trinket's intended combat role ("TANK", "HEALER", "DAMAGER", or "GENERIC")
--- based on Blizzard's C_Item.GetItemStats and consolidated C_Item.GetItemSpecInfo.
--- @param itemLinkOrID any
--- @return string roleType ("TANK", "HEALER", "DAMAGER", or "GENERIC")
function sfui.common.get_trinket_role_type(itemLinkOrID)
    if not itemLinkOrID then return "GENERIC" end

    -- 1. Explicit clean stat signatures
    local stats = sfui.common.get_item_stats(itemLinkOrID)
    if stats then
        if stats["ITEM_MOD_EXTRA_ARMOR_SHORT"] or stats["ITEM_MOD_ARMOR_SHORT"]
            or stats["ITEM_MOD_PARRY_RATING_SHORT"] or stats["ITEM_MOD_DODGE_RATING_SHORT"]
            or stats["ITEM_MOD_BLOCK_RATING_SHORT"] then
            return "TANK"
        end
        if stats["ITEM_MOD_MANA_REGENERATION_SHORT"] or stats["ITEM_MOD_SPIRIT_SHORT"] then
            return "HEALER"
        end
    end

    -- 2. Blizzard native spec list inspection
    local specList = sfui.common.get_item_spec_info(itemLinkOrID)
    if specList and #specList > 0 then
        local hasTank, hasHealer, hasDamager = false, false, false
        for _, sID in ipairs(specList) do
            local role = sfui.common.get_spec_role(sID)
            if role == "TANK" then
                hasTank = true
            elseif role == "HEALER" then
                hasHealer = true
            elseif role == "DAMAGER" then
                hasDamager = true
            end
        end

        if hasTank and not hasHealer and not hasDamager then
            return "TANK"
        elseif hasHealer and not hasTank and not hasDamager then
            return "HEALER"
        elseif hasDamager and not hasTank and not hasHealer then
            return "DAMAGER"
        end
    end

    return "GENERIC"
end

--- Returns the scoring multiplier for a trinket on a given spec.
--- Healers use DPS int-based trinkets at half value (0.5).
--- All other eligible trinket configurations use full value (1.0).
--- @param itemLinkOrID any
--- @param specID number
--- @return number multiplier
function sfui.common.get_trinket_value_multiplier(itemLinkOrID, specID)
    if not itemLinkOrID or not specID then return 1.0 end
    local role = sfui.common.get_spec_role(specID)
    if role == "HEALER" then
        local tRole = sfui.common.get_trinket_role_type(itemLinkOrID)
        if tRole == "DAMAGER" or tRole == "GENERIC" then
            -- Healers evaluate DPS int-based trinkets at half value
            return 0.5
        end
    end
    return 1.0
end

--- Checks if a trinket is eligible for the specified specID based on native clean APIs:
--- - Tanks can use DPS trinkets (matching their primary stat); cannot use healing trinkets.
--- - Healers can use DPS Int-based trinkets at half value; cannot use tanking trinkets.
--- - DPS cannot use tanking or healing trinkets.
--- Completely self-contained with zero external addon dependencies.
--- @param itemLinkOrID any
--- @param specID number
--- @return boolean
function sfui.common.is_trinket_valid_for_spec(itemLinkOrID, specID)
    if not itemLinkOrID or not specID or specID <= 0 then return true end

    local targetRole = sfui.common.get_spec_role(specID)
    local trinketRole = sfui.common.get_trinket_role_type(itemLinkOrID)
    local specList = sfui.common.get_item_spec_info(itemLinkOrID)

    -- Case 1: Target spec is DPS (DAMAGER)
    -- Rule: DPS cannot use tanking or healing trinkets
    if targetRole == "DAMAGER" then
        if trinketRole == "TANK" or trinketRole == "HEALER" then
            return false
        end
        -- If Blizzard tagged with a specific spec list, check if spec is included
        if specList then
            for _, sID in ipairs(specList) do
                if sID == specID then return true end
            end
            return false
        end
        return true
    end

    -- Case 2: Target spec is TANK
    -- Rule: Tanks can use DPS trinkets; Tanks CANNOT use healing trinkets
    if targetRole == "TANK" then
        if trinketRole == "HEALER" then
            return false
        end
        -- If it's a dedicated Tank trinket, check if Blizzard specList contains specID
        if trinketRole == "TANK" then
            if specList then
                for _, sID in ipairs(specList) do
                    if sID == specID then return true end
                end
                return false
            end
            return true
        end
        -- If it's a DPS or GENERIC trinket: Tanks CAN use DPS trinkets!
        -- Verify primary stat alignment (reject pure Intellect trinkets for Tanks)
        local stats = sfui.common.get_item_stats(itemLinkOrID)
        if stats and (stats["ITEM_MOD_INTELLECT_SHORT"] or 0) > 0
            and not stats["ITEM_MOD_STRENGTH_SHORT"] and not stats["ITEM_MOD_AGILITY_SHORT"] then
            return false
        end
        return true
    end

    -- Case 3: Target spec is HEALER
    -- Rule: Healers can use DPS int-based trinkets at half value; Healers CANNOT use tanking trinkets
    if targetRole == "HEALER" then
        if trinketRole == "TANK" then
            return false
        end
        -- Genuine healing trinket
        if trinketRole == "HEALER" then
            if specList then
                for _, sID in ipairs(specList) do
                    if sID == specID then return true end
                end
                return false
            end
            return true
        end

        -- DPS or GENERIC trinket: Healers can use DPS int-based trinkets
        local stats = sfui.common.get_item_stats(itemLinkOrID)
        local hasInt = stats and (stats["ITEM_MOD_INTELLECT_SHORT"] or 0) > 0
        local hasStr = stats and (stats["ITEM_MOD_STRENGTH_SHORT"] or 0) > 0
        local hasAgi = stats and (stats["ITEM_MOD_AGILITY_SHORT"] or 0) > 0
        if hasStr or hasAgi then
            return false -- Strength or Agility DPS trinkets cannot be used by Healers
        end

        if hasInt then
            return true
        end

        -- If statless or dynamic, check if specList contains any Intellect caster spec
        if specList then
            for _, sID in ipairs(specList) do
                if sID == specID then return true end
                local r = sfui.common.get_spec_role(sID)
                if r == "DAMAGER" then
                    local sRule = sfui.highest and sfui.highest.rules and sfui.highest.rules[sID]
                    if sRule and sRule.stat == 4 then -- 4 = Intellect
                        return true
                    end
                end
            end
            return false
        end

        return true
    end

    return true
end

-- ────────────────────────────────────────────────────────────────────────────
-- Spell Engine (C_Spell Modernization & Normalization)
-- ────────────────────────────────────────────────────────────────────────────
local C_Spell                         = _G.C_Spell or {}
local C_Spell_GetSpellInfo            = C_Spell.GetSpellInfo
local C_Spell_GetSpellName            = C_Spell.GetSpellName
local C_Spell_GetSpellTexture         = C_Spell.GetSpellTexture or _G.GetSpellTexture
local C_Spell_GetSpellCooldown        = C_Spell.GetSpellCooldown or _G.GetSpellCooldown
local C_Spell_GetSpellCooldownDuration = C_Spell.GetSpellCooldownDuration
local C_Spell_RequestLoadSpellData    = C_Spell.RequestLoadSpellData

-- Returns unified spell info table or nil
-- Compatible with both modern C_Spell.GetSpellInfo (table) and legacy _G.GetSpellInfo (multi-return)
function sfui.common.get_spell_info(spellID)
    if not spellID then return nil end
    if C_Spell_GetSpellInfo then
        local info = C_Spell_GetSpellInfo(spellID)
        if info then
            return {
                name     = info.name,
                icon     = info.iconID or info.originalIconID,
                castTime = info.castTime,
                minRange = info.minRange,
                maxRange = info.maxRange,
                spellID  = info.spellID or spellID,
            }
        end
    end
    if _G.GetSpellInfo then
        local name, _, icon, castTime, minRange, maxRange, id = _G.GetSpellInfo(spellID)
        if name then
            return {
                name     = name,
                icon     = icon,
                castTime = castTime,
                minRange = minRange,
                maxRange = maxRange,
                spellID  = id or spellID,
            }
        end
    end
    return nil
end

-- Returns spell name string or nil
function sfui.common.get_spell_name(spellID)
    if not spellID then return nil end
    if C_Spell_GetSpellName then
        local name = C_Spell_GetSpellName(spellID)
        if name and name ~= "" then return name end
    end
    if C_Spell_GetSpellInfo then
        local info = C_Spell_GetSpellInfo(spellID)
        if info and info.name and info.name ~= "" then return info.name end
    end
    if _G.GetSpellInfo then
        local name = _G.GetSpellInfo(spellID)
        if name and name ~= "" then return name end
    end
    return nil
end

-- Returns spell icon texture (fileID/path) or nil
function sfui.common.get_spell_icon(spellID)
    if not spellID then return nil end
    if C_Spell_GetSpellTexture then
        local icon = C_Spell_GetSpellTexture(spellID)
        if icon then return icon end
    end
    if C_Spell_GetSpellInfo then
        local info = C_Spell_GetSpellInfo(spellID)
        if info and (info.iconID or info.originalIconID) then
            return info.iconID or info.originalIconID
        end
    end
    if _G.GetSpellTexture then
        local icon = _G.GetSpellTexture(spellID)
        if icon then return icon end
    end
    return nil
end

-- Returns normalized cooldown info: startTime, duration, isEnabled, modRate
function sfui.common.get_spell_cooldown(spellID)
    if not spellID then return 0, 0, false, 1 end
    if C_Spell_GetSpellCooldown then
        local cd = C_Spell_GetSpellCooldown(spellID)
        if cd then
            if type(cd) == "table" then
                return cd.startTime or 0, cd.duration or 0, cd.isEnabled ~= false, cd.modRate or 1
            else
                local start, dur, enabled, modRate = C_Spell_GetSpellCooldown(spellID)
                return start or 0, dur or 0, enabled ~= 0 and enabled ~= false, modRate or 1
            end
        end
    end
    if _G.GetSpellCooldown then
        local start, dur, enabled, modRate = _G.GetSpellCooldown(spellID)
        return start or 0, dur or 0, enabled ~= 0 and enabled ~= false, modRate or 1
    end
    return 0, 0, false, 1
end

-- Safely requests async spell data loading
function sfui.common.request_spell_load(spellID)
    if spellID and C_Spell_RequestLoadSpellData then
        C_Spell_RequestLoadSpellData(spellID)
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- Container & Bag Engine (C_Container Modernization)
-- ────────────────────────────────────────────────────────────────────────────
local C_Container                      = _G.C_Container or {}
local C_Container_GetContainerNumSlots = C_Container.GetContainerNumSlots or _G.GetContainerNumSlots
local C_Container_GetContainerItemInfo = C_Container.GetContainerItemInfo or _G.GetContainerItemInfo
local C_Container_GetContainerItemLink = C_Container.GetContainerItemLink or _G.GetContainerItemLink
local C_Container_GetContainerItemID   = C_Container.GetContainerItemID or _G.GetContainerItemID

--- Iterates over the player's equipped bags and invokes callback for each item.
--- Stops iteration early if callback returns true.
--- @param callback fun(bag: number, slot: number, itemID: number|nil, itemLink: string|nil, itemInfo: table|nil): boolean|nil
--- @param includeReagent boolean|nil If true or nil, includes reagent bag (index 5)
--- @param skipEmpty boolean|nil If true or nil, only calls callback on non-empty slots
--- @param needInfo boolean|nil If false, avoids calling C_Container.GetContainerItemInfo (zero table allocations)
--- @return boolean Returns true if iteration was terminated early by callback
function sfui.common.for_each_bag_item(callback, includeReagent, skipEmpty, needInfo)
    if type(callback) ~= "function" then return false end
    if not C_Container_GetContainerNumSlots then return false end

    local maxBag = (includeReagent ~= false) and (_G.NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5) or (_G.NUM_BAG_SLOTS or 4)
    local shouldSkipEmpty = (skipEmpty ~= false)

    for bag = 0, maxBag do
        local numSlots = C_Container_GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            -- Fast path: Query numeric itemID first (zero table allocation)
            local itemID = C_Container_GetContainerItemID and C_Container_GetContainerItemID(bag, slot)
            local itemLink = nil
            local info = nil

            if itemID or not shouldSkipEmpty then
                itemLink = C_Container_GetContainerItemLink and C_Container_GetContainerItemLink(bag, slot)

                -- Only query heavy itemInfo table if caller needs it or didn't explicitly opt out
                if needInfo ~= false then
                    info = C_Container_GetContainerItemInfo and C_Container_GetContainerItemInfo(bag, slot)
                    if not itemID and info then
                        itemID = info.itemID or sfui.common.get_item_id(info.hyperlink)
                    end
                    if not itemLink and info then
                        itemLink = info.hyperlink
                    end
                end

                if not shouldSkipEmpty or itemID or itemLink or info then
                    if callback(bag, slot, itemID, itemLink, info) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- ────────────────────────────────────────────────────────────────────────────
-- Map & Zone Engine (C_Map Modernization)
-- ────────────────────────────────────────────────────────────────────────────
local C_Map                   = _G.C_Map or {}
local C_Map_GetBestMapForUnit = C_Map.GetBestMapForUnit
local C_Map_GetMapInfo        = C_Map.GetMapInfo

--- Returns the player's current best uiMapID, or 0
--- @return number
function sfui.common.get_player_map_id()
    if C_Map_GetBestMapForUnit then
        return C_Map_GetBestMapForUnit("player") or 0
    end
    return 0
end

--- Returns map info table for the given uiMapID or nil
--- @param mapID number
--- @return table|nil
function sfui.common.get_map_info(mapID)
    if not mapID or mapID <= 0 then return nil end
    if C_Map_GetMapInfo then
        return C_Map_GetMapInfo(mapID)
    end
    return nil
end

--- Returns map info table for the player's current best map or nil
--- @return table|nil
function sfui.common.get_player_map_info()
    local mapID = sfui.common.get_player_map_id()
    return sfui.common.get_map_info(mapID)
end

--- Returns the localized name of the specified uiMapID or nil
--- @param mapID number
--- @return string|nil
function sfui.common.get_map_name(mapID)
    local info = sfui.common.get_map_info(mapID)
    return info and info.name or nil
end

--- Returns the localized name of the player's current zone/map or nil
--- @return string|nil
function sfui.common.get_player_map_name()
    local info = sfui.common.get_player_map_info()
    return info and info.name or nil
end

-- ────────────────────────────────────────────────────────────────────────────
-- Currency Engine (C_CurrencyInfo Modernization)
-- ────────────────────────────────────────────────────────────────────────────
local C_CurrencyInfo                 = _G.C_CurrencyInfo or {}
local C_CurrencyInfo_GetCurrencyInfo = C_CurrencyInfo.GetCurrencyInfo or _G.GetCurrencyInfo

--- Returns currency info table or nil
--- @param currencyID number
--- @return table|nil
function sfui.common.get_currency_info(currencyID)
    if not currencyID then return nil end
    local cID = tonumber(currencyID)
    if not cID or cID <= 0 then return nil end
    if C_CurrencyInfo_GetCurrencyInfo then
        return C_CurrencyInfo_GetCurrencyInfo(cID)
    end
    return nil
end

--- Returns current quantity of the specified currency, or 0
--- Zero garbage allocation (no fallback table allocation).
--- @param currencyID number
--- @return number
function sfui.common.get_currency_quantity(currencyID)
    local info = sfui.common.get_currency_info(currencyID)
    return (info and info.quantity) or 0
end

--- Returns localized name of the specified currency, or nil
--- @param currencyID number
--- @return string|nil
function sfui.common.get_currency_name(currencyID)
    local info = sfui.common.get_currency_info(currencyID)
    return info and info.name or nil
end

--- Returns icon fileID/path for the specified currency, or nil
--- @param currencyID number
--- @return number|string|nil
function sfui.common.get_currency_icon(currencyID)
    local info = sfui.common.get_currency_info(currencyID)
    return info and (info.iconFileID or info.icon) or nil
end


-- Helper to safely ensure tracked bar DB structure exists
-- Returns the tracked bar entry for the given cooldownID, or the trackedBarsBySpec table if no ID provided
function sfui.common.ensure_tracked_bar_db(cooldownID)
    SfuiDB = SfuiDB or {}
    SfuiDB.trackedBars = SfuiDB.trackedBars or {}

    local specID = sfui.common.get_current_spec_id() or 0
    SfuiDB.trackedBarsBySpec = SfuiDB.trackedBarsBySpec or {}
    SfuiDB.trackedBarsBySpec[specID] = SfuiDB.trackedBarsBySpec[specID] or {}

    local specBars = SfuiDB.trackedBarsBySpec[specID]

    if cooldownID then
        specBars[cooldownID] = specBars[cooldownID] or {}
        return specBars[cooldownID]
    end
    return specBars
end

function sfui.common.get_tracked_bars()
    local specID = sfui.common.get_current_spec_id() or 0
    SfuiDB = SfuiDB or {}
    SfuiDB.trackedBarsBySpec = SfuiDB.trackedBarsBySpec or {}
    SfuiDB.trackedBarsBySpec[specID] = SfuiDB.trackedBarsBySpec[specID] or {}
    return SfuiDB.trackedBarsBySpec[specID]
end

-- ========================================
-- Per-Spec Configuration Migrations
-- ========================================

function sfui.common.migrate_tracked_bars_to_spec()
    SfuiDB = SfuiDB or {}
    SfuiDB.trackedBars = SfuiDB.trackedBars or {}

    local specID = sfui.common.get_current_spec_id() or 0
    SfuiDB.trackedBarsBySpec = SfuiDB.trackedBarsBySpec or {}

    -- If current spec is already populated, assume migration ran previously for this spec
    if SfuiDB.trackedBarsBySpec[specID] and next(SfuiDB.trackedBarsBySpec[specID]) then
        return
    end

    SfuiDB.trackedBarsBySpec[specID] = {}
    local specBars = SfuiDB.trackedBarsBySpec[specID]
    local keysToRemove = {}

    -- Extract numeric IDs (Population) to the per-Spec array
    for k, v in pairs(SfuiDB.trackedBars) do
        if type(k) == "number" then
            specBars[k] = v
            table.insert(keysToRemove, k)
        end
    end

    -- Remove the numeric IDs from the global settings root
    for _, k in ipairs(keysToRemove) do
        SfuiDB.trackedBars[k] = nil
    end
end

-- ========================================
-- Per-Spec Panel Configuration Helpers
-- ========================================

-- One-time migration from old flat array to per-spec structure
function sfui.common.migrate_cooldown_panels_to_spec()
    -- Skip if already migrated or nothing to migrate
    if SfuiDB.cooldownPanelsBySpec or not SfuiDB.cooldownPanels then
        return
    end

    -- Get current spec
    local currentSpecID = sfui.common.get_current_spec_id()
    if not currentSpecID or currentSpecID == 0 then
        -- No spec yet (low level character), defer migration
        return
    end

    -- Migrate existing panels to current spec
    SfuiDB.cooldownPanelsBySpec = {
        [currentSpecID] = SfuiDB.cooldownPanels
    }

    -- Mark old format as migrated (keep for reference but don't use)
    SfuiDB._cooldownPanelsMigrated = true
end

-- Shared helper to get categorized CDM entries
local function get_all_cdm_entries()
    local cat0 = {} -- Essential
    local cat1 = {} -- Utility

    local function categorize(cooldownID, info)
        if not info or not info.isKnown then return end
        local entry = {
            type = "cooldown",
            cooldownID = cooldownID,
            spellID = info.spellID,
            id = info.spellID or cooldownID,
            settings = { showText = true }
        }
        local cat = info.category
        if cat == 0 or not cat then
            table.insert(cat0, entry)
        elseif cat == 1 then
            table.insert(cat1, entry)
        end
    end

    -- Try using CooldownViewerSettings DataProvider
    if CooldownViewerSettings and CooldownViewerSettings.GetDataProvider then
        local dataProvider = CooldownViewerSettings:GetDataProvider()
        local cooldownIDs = dataProvider and dataProvider:GetOrderedCooldownIDs()
        if cooldownIDs then
            for _, cooldownID in ipairs(cooldownIDs) do
                if not sfui.common.issecretvalue(cooldownID) then
                    categorize(cooldownID, dataProvider:GetCooldownInfoForID(cooldownID))
                end
            end
        end
    end

    -- Fallback: use C_CooldownViewer direct API if provider not ready or empty
    if #cat0 == 0 and #cat1 == 0 and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet then
        for cat = 0, 1 do
            local cooldownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(cat, false)
            if cooldownIDs then
                for _, cooldownID in ipairs(cooldownIDs) do
                    categorize(cooldownID, C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID))
                end
            end
        end
    end

    return cat0, cat1
end

-- Populate CENTER panel with cooldowns from CDM Essential Cooldowns (category 0)
function sfui.common.populate_center_panel_from_cdm()
    local cat0, _ = get_all_cdm_entries()
    local entries = {}
    -- CENTER holds 7 max
    for i = 1, math.min(7, #cat0) do
        table.insert(entries, cat0[i])
    end
    return entries
end

-- Populate UTILITY panel with cooldowns from CDM Group 1 (Category 1) + overflow
function sfui.common.populate_utility_panel_from_cdm()
    local cat0, cat1 = get_all_cdm_entries()
    local entries = {}

    -- 1. Add overflow from cat 0 (index 8+)
    if #cat0 > 7 then
        for i = 8, #cat0 do
            table.insert(entries, cat0[i])
        end
    end

    -- 2. Add cat 1
    for _, entry in ipairs(cat1) do
        table.insert(entries, entry)
    end

    return entries
end

-- Cached panels reference (invalidated on spec change or panel modification)
local _cachedPanels = nil
local _cachedPanelsSpecID = nil

-- Get panels for current spec (Pure accessor, hot-path safe)
function sfui.common.get_cooldown_panels()
    local specID = sfui.common.get_current_spec_id() or 0

    -- Return cached if valid
    if _cachedPanels and _cachedPanelsSpecID == specID and #_cachedPanels > 0 then
        return _cachedPanels
    end

    if not SfuiDB.cooldownPanelsBySpec or not SfuiDB.cooldownPanelsBySpec[specID] or #SfuiDB.cooldownPanelsBySpec[specID] == 0 or ((sfui.common.get_player_class() == "DRUID" or sfui.common.get_player_class() == "ROGUE") and not SfuiDB.druidMigrationV7) then
        _cachedPanels = sfui.common.ensure_panels_initialized()
    else
        _cachedPanels = SfuiDB.cooldownPanelsBySpec[specID]
    end
    _cachedPanelsSpecID = specID
    return _cachedPanels
end

-- Invalidate panels cache (call when panels are modified)
function sfui.common.invalidate_panels_cache()
    _cachedPanels = nil
    _cachedPanelsSpecID = nil
end

-- Get only the active (available) entries for a panel (reusable destination table support)
function sfui.common.get_active_panel_entries(panelConfig, outTable)
    local activeEntries = outTable or {}
    _G.wipe(activeEntries)
    if not panelConfig or type(panelConfig.entries) ~= "table" then return activeEntries end
    for _, entry in ipairs(panelConfig.entries) do
        local isKnown = true
        local typeHint = (type(entry) == "table" and entry.type) or "spell"

        if (typeHint == "spell" or typeHint == "cooldown") and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
            local id = (type(entry) == "table" and entry.id) or entry
            local cdID = (type(entry) == "table" and entry.cooldownID) or id
            local cdInfo = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
            if cdInfo and cdInfo.isKnown == false then
                isKnown = false
            end
        end

        -- Hero Talent Filter logic
        -- Hero Talent Filter logic
        if isKnown and type(entry) == "table" and entry.settings then
            -- Fallback for legacy single-item filter setting to new table format
            if entry.settings.heroTalentFilter and entry.settings.heroTalentFilter ~= "Any" and entry.settings.heroTalentFilter ~= 0 then
                if not entry.settings.heroTalentWhitelist then
                    entry.settings.heroTalentWhitelist = {}
                end
                entry.settings.heroTalentWhitelist[entry.settings.heroTalentFilter] = true
                entry.settings.heroTalentFilter = nil
            end

            if entry.settings.heroTalentsDisabled then
                entry.settings.heroTalentsDisabled = nil
            end

            if entry.settings.heroTalentWhitelist then
                local hasWhitelistItems = false
                for k, v in pairs(entry.settings.heroTalentWhitelist) do
                    if v then
                        hasWhitelistItems = true
                        break
                    end
                end

                if hasWhitelistItems then
                    local activeHeroSpec = C_ClassTalents and C_ClassTalents.GetActiveHeroTalentSpec and
                        C_ClassTalents.GetActiveHeroTalentSpec()
                    if not activeHeroSpec or not entry.settings.heroTalentWhitelist[activeHeroSpec] then
                        isKnown = false
                    end
                end
            end
        end

        if isKnown then
            table.insert(activeEntries, entry)
        end
    end
    return activeEntries
end

-- Ensure panels exist and are populated (Called once on load/spec/talent change)
function sfui.common.ensure_panels_initialized()
    local specID = sfui.common.get_current_spec_id() or 0
    local playerClass = sfui.common.get_player_class()

    SfuiDB.cooldownPanelsBySpec = SfuiDB.cooldownPanelsBySpec or {}
    SfuiDB.cooldownPanelsBySpec[specID] = SfuiDB.cooldownPanelsBySpec[specID] or {}

    local panels = SfuiDB.cooldownPanelsBySpec[specID]
    local changed = false

    SfuiDB.iconsInitializedBySpec = SfuiDB.iconsInitializedBySpec or {}

    local defaultPanelSpecs = {
        { key = "center_panel", name = "CENTER",  populateFunc = sfui.common.populate_center_panel_from_cdm },
        { key = "utility",      name = "UTILITY", populateFunc = sfui.common.populate_utility_panel_from_cdm },
        { key = "left",         name = "Left" },
        { key = "right",        name = "Right" },
    }

    if playerClass == "DRUID" or playerClass == "ROGUE" then
        -- Inject druid/rogue specific default forms immediately after the base CENTER panel (index 1)
        defaultPanelSpecs[1].requiredForm = 0
    end

    if playerClass == "DRUID" then
        table.insert(defaultPanelSpecs, 2, { key = "center_panel", name = "CAT", requiredForm = 1 })
        table.insert(defaultPanelSpecs, 3, { key = "center_panel", name = "BEAR", requiredForm = 5 })
        table.insert(defaultPanelSpecs, 4, { key = "center_panel", name = "MOONKIN", requiredForm = { 31, 35 } })
        table.insert(defaultPanelSpecs, 5, { key = "center_panel", name = "STEALTH", requiredForm = "stealth" })
    end

    -- Migrate legacy trackedIcons if not already done for this spec
    local migratedEntries = nil
    if not SfuiDB.iconsInitializedBySpec[specID] and SfuiDB.trackedIcons then
        migratedEntries = {}
        for id, cfg in pairs(SfuiDB.trackedIcons) do
            if type(id) == "number" then
                table.insert(migratedEntries, { id = id, settings = cfg, type = "spell" })
            end
        end
    end

    for _, spec in ipairs(defaultPanelSpecs) do
        local panelIdx = nil
        local uSpecName = string.upper(spec.name)
        for i, panel in ipairs(panels) do
            local uPanelName = string.upper(panel.name or "")
            if uPanelName == uSpecName then
                panelIdx = i
                break
                -- Also match if the database name is "CENTER" but we are looking for "CENTER" (we rename visually only in cdm)
            elseif uPanelName == "CENTER" and uSpecName == "CENTER" and spec.requiredForm == 0 then
                panelIdx = i
                break
            end
        end

        if not panelIdx then
            local newPanel = sfui.common.copy(sfui.config.cooldown_panel_defaults[spec.key])
            if spec.populateFunc then
                if not SfuiDB.iconsInitializedBySpec[specID] then
                    newPanel.entries = spec.populateFunc()
                else
                    newPanel.entries = {}
                end
            elseif spec.name == "Left" and migratedEntries then
                newPanel.entries = migratedEntries
            else
                newPanel.entries = {}
            end
            if spec.requiredForm ~= nil then
                newPanel.requiredForm = spec.requiredForm
            end
            newPanel.name = spec.name
            newPanel.specID = specID
            table.insert(panels, newPanel)

            -- Ensure "utility" and "center_panel" get their specific defaults applied robustly
            if spec.key == "utility" or spec.key == "center_panel" then
                local defaults = sfui.config.cooldown_panel_defaults[spec.key]
                for k, v in pairs(defaults) do
                    if newPanel[k] == nil then newPanel[k] = v end
                end
            end
            changed = true
        else
            -- Ensure all default keys exist in existing panel (merge missing)
            local panel = panels[panelIdx]
            local default = sfui.config.cooldown_panel_defaults[spec.key]
            if type(default) == "table" then
                for k, v in pairs(default) do
                    if panel[k] == nil then
                        panel[k] = v
                        changed = true
                    end
                end
            end

            -- Removing automatic population of existing empty panels to give user full control.
        end
    end

    -- Fast migration fallback and cleanup
    if (playerClass == "DRUID" or playerClass == "ROGUE") and not SfuiDB.druidMigrationV7 then
        local hasBareCenter = false
        local upper = string.upper
        for _, p in ipairs(panels) do
            if p.name and upper(p.name) == "CENTER" then
                hasBareCenter = true; break
            end
        end

        for i = #panels, 1, -1 do
            local p = panels[i]
            local uname = upper(p.name)
            -- Retroactively apply requiredForm to bare 'CENTER' panels if missing
            if uname == "CENTER" and p.requiredForm == nil then
                p.requiredForm = 0
                changed = true
            end

            if playerClass == "DRUID" then
                -- Rename legacy named panels if we don't have a bare CENTER yet, otherwise purge ghosts
                if uname == "CENTER (BASE FORM)" then
                    if not hasBareCenter then
                        p.name = "CENTER"
                        p.requiredForm = 0
                        hasBareCenter = true
                        changed = true
                    else
                        table.remove(panels, i)
                        changed = true
                    end
                elseif uname == "CENTER (CAT FORM)" or uname == "CENTER (BEAR FORM)" or uname == "CENTER (MOONKIN FORM)" then
                    table.remove(panels, i)
                    changed = true
                end
            end
        end
        SfuiDB.druidMigrationV7 = true
    end

    -- Cleanup duplicates generated by bug for the exact target names (case-insensitive)
    local seenUpperNames = {}
    local upper = string.upper
    local builtins = {
        CENTER = true,
        UTILITY = true,
        LEFT = true,
        RIGHT = true,
        CAT = true,
        BEAR = true,
        MOONKIN = true,
        STEALTH = true
    }

    for i = #panels, 1, -1 do
        local pName = panels[i].name
        if pName then
            local uName = upper(pName)
            if uName == "BUFFS" then
                table.remove(panels, i)
                changed = true
            elseif builtins[uName] then
                if seenUpperNames[uName] then
                    table.remove(panels, i)
                    changed = true
                else
                    seenUpperNames[uName] = true
                end
            end
        end
    end

    if not SfuiDB.iconsInitializedBySpec[specID] then
        SfuiDB.iconsInitializedBySpec[specID] = true
        if migratedEntries then SfuiDB.trackedIcons = nil end -- Clear global migration source once first spec consumes it
        changed = true
    end

    if changed then
        sfui.common.set_cooldown_panels(panels)
    else
        -- If no entries were found but population was expected, retry once after a short delay
        -- This handles the race condition on fresh installations/characters
        if not SfuiDB._populationRetryDone then
            local needsRetry = false
            for _, panel in ipairs(panels) do
                if (panel.name == "CENTER" or panel.name == "UTILITY") and (#panel.entries == 0) then
                    needsRetry = true
                    break
                end
            end

            if needsRetry then
                SfuiDB._populationRetryDone = true
                C_Timer.After(2, function()
                    sfui.common.ensure_panels_initialized()
                end)
            end
        end
    end

    return panels
end

function sfui.common.add_custom_panel(name)
    if not name or name == "" then return end
    local panels = sfui.common.get_cooldown_panels()

    -- Prevent creating duplicate builtin panels
    if name == "CENTER" or name == "UTILITY" or name == "Left" or name == "Right" or name == "CAT" or name == "BEAR" or name == "MOONKIN" or name == "STEALTH" then
        for _, p in ipairs(panels) do
            if p.name == name then return #panels end
        end
    end

    -- Use 'utility' as a template for custom panels since it's a good middle ground
    local newPanel = sfui.common.copy(sfui.config.cooldown_panel_defaults.utility)
    newPanel.name = name
    newPanel.entries = {}
    newPanel.specID = sfui.common.get_current_spec_id()

    table.insert(panels, newPanel)
    return #panels
end

function sfui.common.delete_custom_panel(index)
    local panels = sfui.common.get_cooldown_panels()
    if panels[index] then
        table.remove(panels, index)
        return true
    end
    return false
end

-- Set panels for current spec
function sfui.common.set_cooldown_panels(panels)
    local specID = sfui.common.get_current_spec_id()
    if not specID or specID == 0 then return end

    SfuiDB.cooldownPanelsBySpec = SfuiDB.cooldownPanelsBySpec or {}
    SfuiDB.cooldownPanelsBySpec[specID] = panels
    sfui.common.invalidate_panels_cache()
end

-- Get all available anchor targets for icon panels
function sfui.common.get_all_anchor_targets(excludeName)
    local targets = {
        { text = "Screen (UIParent)", value = "UIParent" },
        { text = "Health Bar",        value = "Health Bar" },
        { text = "Tracked Bars",      value = "Tracked Bars" },
    }

    -- Add all panels as potential targets
    local panels = sfui.common.get_cooldown_panels()
    if panels then
        for _, p in ipairs(panels) do
            if p.name and p.name ~= excludeName then
                table.insert(targets, { text = "Panel: " .. p.name, value = p.name })
            end
        end
    end

    return targets
end

-- Get panel at index for current spec
function sfui.common.get_cooldown_panel(index)
    local panels = sfui.common.get_cooldown_panels()
    return panels[index]
end

-- Backwards compatibility wrapper - now returns per-spec panels
function sfui.common.ensure_tracked_icon_db()
    return sfui.common.get_cooldown_panels()
end

local powerTypeToName = {}
for name, value in pairs(Enum.PowerType) do
    powerTypeToName[value] = name
end

local primaryResourcesCache = {
    DEATHKNIGHT = Enum.PowerType.RunicPower,
    DEMONHUNTER = Enum.PowerType.Fury,
    DRUID = { [0] = Enum.PowerType.Mana, [1] = Enum.PowerType.Energy, [5] = Enum.PowerType.Rage, [27] = Enum.PowerType.Mana, [31] = Enum.PowerType.LunarPower, [35] = Enum.PowerType.LunarPower },
    EVOKER = Enum.PowerType.Mana,
    HUNTER = Enum.PowerType.Focus,
    MAGE = Enum.PowerType.Mana,
    MONK = { [268] = Enum.PowerType.Energy, [269] = Enum.PowerType.Energy, [270] = Enum.PowerType.Mana },
    PALADIN = Enum.PowerType.Mana,
    PRIEST = { [256] = Enum.PowerType.Mana, [257] = Enum.PowerType.Mana, [258] = Enum.PowerType.Insanity },
    ROGUE = Enum.PowerType.Energy,
    SHAMAN = { [262] = Enum.PowerType.Maelstrom, [263] = Enum.PowerType.Mana, [264] = Enum.PowerType.Mana },
    WARLOCK = Enum.PowerType.Mana,
    WARRIOR = Enum.PowerType.Rage
}

local secondaryResourcesCache = {
    DEATHKNIGHT = Enum.PowerType.Runes,
    DEMONHUNTER = nil,
    DRUID = { [1] = Enum.PowerType.ComboPoints },
    EVOKER = Enum.PowerType.Essence,
    HUNTER = nil,
    MAGE = { [62] = Enum.PowerType.ArcaneCharges },
    MONK = { [268] = "STAGGER", [269] = Enum.PowerType.Chi, [270] = nil },
    PALADIN = Enum.PowerType.HolyPower,
    PRIEST = { [258] = Enum.PowerType.Mana },
    ROGUE = Enum.PowerType.ComboPoints,
    SHAMAN = { [262] = Enum.PowerType.Mana },
    WARLOCK = Enum.PowerType.SoulShards,
    WARRIOR = nil
}

local resourceColorsCache = {
    ["STAGGER"] = { r = 1, g = 0.5, b = 0 },
    ["SOUL_SHARDS"] = { r = 0.58, g = 0.51, b = 0.79 },
    ["RUNES"] = { r = 0.77, g = 0.12, b = 0.23 },
    ["ESSENCE"] = { r = 0.20, g = 0.58, b = 0.50 },
    ["COMBO_POINTS"] = { r = 1.00, g = 0.96, b = 0.41 },
    ["CHI"] = { r = 0.00, g = 1.00, b = 0.59 },
    ["HOLY_POWER"] = { r = 0.96, g = 0.91, b = 0.55 },
    ["ARCANE_CHARGES"] = { r = 0.6, g = 0.8, b = 1.0 },
}

-- ────────────────────────────────────────────────────────────────────────────
-- Central Out-of-Combat Action Queue
-- ────────────────────────────────────────────────────────────────────────────
local _oocQueue = {}
local _oocProcessing = false

--- Enqueue a callback to be executed when the player is out of combat lockdown.
--- If not currently in combat lockdown, the callback executes immediately.
--- Callbacks are executed inside pcall to prevent errors from breaking the queue.
--- @param callback function
function sfui.common.run_after_combat(callback)
    if type(callback) ~= "function" then return end
    if not InCombatLockdown() then
        local ok, err = pcall(callback)
        if not ok then
            print("|cff6600ffsfui|r run_after_combat error: " .. tostring(err))
        end
    else
        _oocQueue[#_oocQueue + 1] = callback
    end
end

local function flush_ooc_queue()
    if _oocProcessing or #_oocQueue == 0 then return end
    _oocProcessing = true
    local count = #_oocQueue
    for i = 1, count do
        local fn = _oocQueue[i]
        _oocQueue[i] = nil
        if fn then
            local ok, err = pcall(fn)
            if not ok then
                print("|cff6600ffsfui|r ooc callback error: " .. tostring(err))
            end
        end
    end
    -- Compact any items enqueued during callback execution
    local remaining = #_oocQueue
    if remaining > 0 then
        local writeIdx = 1
        for i = count + 1, remaining do
            _oocQueue[writeIdx] = _oocQueue[i]
            _oocQueue[i] = nil
            writeIdx = writeIdx + 1
        end
    end
    _oocProcessing = false
end

sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", flush_ooc_queue)

-- ------------------------------------------------------------
-- Central Vehicle and Dragonflying / Skyriding State Cache
-- ------------------------------------------------------------
local _dragonflyingCache = nil
local _getBonusIdx = C_ActionBar and C_ActionBar.GetBonusBarIndex or GetBonusBarIndex
local _getBonusOff = C_ActionBar and C_ActionBar.GetBonusBarOffset or GetBonusBarOffset

function sfui.common.invalidate_dragonflying_cache()
    _dragonflyingCache = nil
end

function sfui.common.is_dragonflying()
    if _dragonflyingCache ~= nil then return _dragonflyingCache end
    if not (C_PlayerInfo and C_PlayerInfo.GetGlidingInfo) then
        _dragonflyingCache = false
        return false
    end
    local isFlying, canGlide = C_PlayerInfo.GetGlidingInfo()
    local hasSkyridingBar = _getBonusIdx and _getBonusOff and
        (_getBonusIdx() == 11 and _getBonusOff() == 5) or false
    _dragonflyingCache = (isFlying or (canGlide and hasSkyridingBar)) and true or false
    return _dragonflyingCache
end

function sfui.common.is_in_vehicle()
    if sfui.common.is_dragonflying() then return false end
    if UnitInVehicle("player") or UnitHasVehicleUI("player") then return true end
    if UnitExists("vehicle") and UnitVehicleSkin and UnitVehicleSkin("player") ~= nil then return true end
    if C_ActionBar and C_ActionBar.HasVehicleActionBar and C_ActionBar.HasVehicleActionBar() then return true end
    return false
end

local function on_glide_or_vehicle_event()
    sfui.common.invalidate_dragonflying_cache()
end

sfui.events.RegisterEvent("PLAYER_CAN_GLIDE_CHANGED",     on_glide_or_vehicle_event)
sfui.events.RegisterEvent("PLAYER_IS_GLIDING_CHANGED",    on_glide_or_vehicle_event)
sfui.events.RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED", on_glide_or_vehicle_event)
sfui.events.RegisterEvent("UPDATE_SHAPESHIFT_FORM",       on_glide_or_vehicle_event)
sfui.events.RegisterUnitEvents({"UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE"}, "player", on_glide_or_vehicle_event)
sfui.events.RegisterEvent("VEHICLE_UPDATE",               on_glide_or_vehicle_event)
sfui.events.RegisterEvent("UPDATE_VEHICLE_ACTIONBAR",     on_glide_or_vehicle_event)
sfui.events.RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR",    on_glide_or_vehicle_event)
sfui.events.RegisterEvent("UPDATE_POSSESS_BAR",           on_glide_or_vehicle_event)
sfui.events.RegisterEvent("UPDATE_BONUS_ACTIONBAR",       on_glide_or_vehicle_event)
sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD",        on_glide_or_vehicle_event)


function sfui.common.update_widget_bar(widget_frame, icons_pool, labels_pool, source_data, get_details_func)
    if not widget_frame then return end
    local cfg = sfui.config.widget_bar
    local last_icon = nil
    local i = 1
    for _, itemID in ipairs(source_data) do
        local details = get_details_func(itemID)
        if details then
            local icon = icons_pool[i]
            if not icon then
                icon = CreateFrame("Button", nil, widget_frame)
                icon:SetSize(cfg.icon_size, cfg.icon_size)
                local texture = icon:CreateTexture(nil, "ARTWORK")
                texture:SetAllPoints(icon)
                icon.texture = texture
                icon:SetScript("OnEnter", details.on_enter)
                icon:SetScript("OnLeave", details.on_leave)
                icon:SetScript("OnMouseUp", details.on_mouseup)
                icons_pool[i] = icon
            end
            local label = labels_pool[i]
            if not label then
                label = widget_frame:CreateFontString(nil, "OVERLAY", sfui.config.font_small)
                label:SetPoint("TOP", icon, "BOTTOM", 0, cfg.label_offset_y)
                label:SetTextColor(cfg.label_color[1], cfg.label_color[2], cfg.label_color[3])
                labels_pool[i] = label
            end
            icon.id = itemID
            icon.texture:SetTexture(details.texture or sfui.config.textures.gold_icon)
            label:SetText(details.quantity)
            if i == 1 then
                icon:SetPoint("TOPLEFT", cfg.spacing or 5, -(cfg.spacing or 5))
            elseif last_icon then
                icon:SetPoint("TOPLEFT", last_icon, "TOPRIGHT", cfg.icon_spacing, 0)
            end
            icon:Show()
            label:Show()
            last_icon = icon
            i = i + 1
        end
    end
    for j = i, #icons_pool do icons_pool[j]:Hide() end
    for j = i, #labels_pool do labels_pool[j]:Hide() end
    if last_icon and not InCombatLockdown() then
        local left = widget_frame:GetLeft()
        if left then
            widget_frame:SetWidth(last_icon:GetRight() - left + (cfg.spacing or 5))
        end
        if CharacterFrame:IsShown() then widget_frame:Show() end
    else
        widget_frame:Hide()
    end
end

function sfui.common.get_primary_resource()
    local pClass = sfui.common.get_player_class()
    if not pClass then return nil end
    if pClass == "DRUID" then
        local form = GetShapeshiftFormID and GetShapeshiftFormID() or 0
        local druidCache = primaryResourcesCache[pClass]
        return (druidCache and druidCache[form]) or Enum.PowerType.Mana
    end
    local cache = primaryResourcesCache[pClass]
    if type(cache) == "table" then
        local specID = sfui.common.get_current_spec_id()
        return cache[specID]
    else
        return cache
    end
end

function sfui.common.get_secondary_resource()
    local pClass = sfui.common.get_player_class()
    if not pClass then return nil end
    local res
    if pClass == "DRUID" then
        local form = GetShapeshiftFormID and GetShapeshiftFormID() or 0
        local druidCache = secondaryResourcesCache[pClass]
        res = druidCache and druidCache[form]
    else
        local cache = secondaryResourcesCache[pClass]
        if type(cache) == "table" then
            local specID = sfui.common.get_current_spec_id()
            res = cache[specID]
        else
            res = cache
        end
    end

    if sfui.bars then
        sfui.bars.bar1_in_use = (res ~= nil)
    end
    return res
end

-- Reuse table to avoid per-call allocations in bar update loops.
-- Rebuilt lazily when spec/class changes via invalidate_spec_color_cache().
local _specColorCache = { 1, 1, 1, 1 }
local _specColorDirty = true

function sfui.common.invalidate_spec_color_cache()
    _specColorDirty = true
end

function sfui.common.get_class_or_spec_color()
    -- Global Override: if spec colors are disabled, use the fallback color
    if SfuiDB and SfuiDB.useSpecColor == false then
        return SfuiDB.specColorFallback or { 1, 1, 1, 1 }
    end

    if not _specColorDirty then
        return _specColorCache
    end

    -- Rebuild the cached table in-place (no new allocation)
    _specColorCache[1], _specColorCache[2], _specColorCache[3], _specColorCache[4] = 1, 1, 1, 1
    local specID = sfui.common.get_current_spec_id()
    local pClass = sfui.common.get_player_class()

    local specColor = (specID and specID > 0) and ((SfuiDB and SfuiDB.spec_colors and SfuiDB.spec_colors[specID])
        or (sfui.config and sfui.config.spec_colors and sfui.config.spec_colors[specID]))

    if specColor then
        _specColorCache[1], _specColorCache[2], _specColorCache[3], _specColorCache[4] =
            specColor[1] or specColor.r or 1,
            specColor[2] or specColor.g or 1,
            specColor[3] or specColor.b or 1,
            specColor[4] or specColor.a or 1
    elseif pClass then
        local classColor = C_ClassColor and C_ClassColor.GetClassColor(pClass) or
            (RAID_CLASS_COLORS and RAID_CLASS_COLORS[pClass])
        if classColor then
            _specColorCache[1], _specColorCache[2], _specColorCache[3], _specColorCache[4] =
                classColor.r, classColor.g, classColor.b, 1
        end
    end

    _specColorDirty = false
    return _specColorCache
end

function sfui.common.unpack_color(color, defaultR, defaultG, defaultB, defaultA)
    if not color then return defaultR or 1, defaultG or 1, defaultB or 1, defaultA or 1 end
    local r = color[1] or color.r or defaultR or 1
    local g = color[2] or color.g or defaultG or 1
    local b = color[3] or color.b or defaultB or 1
    local a = color[4] or color.a or defaultA or 1
    return r, g, b, a
end

function sfui.common.create_bar(name, frameType, parent, template, configName)
    local cfg = sfui.config[configName or name]
    local mult = sfui.pixelScale or 1
    local backdrop = CreateFrame("Frame", "sfui_" .. name .. "_Backdrop", parent, "BackdropTemplate")
    backdrop:SetFrameStrata("MEDIUM")
    local padding = cfg.backdrop.padding * mult
    backdrop:SetSize(cfg.width + padding * 2, cfg.height + padding * 2)

    backdrop:SetBackdrop({
        bgFile = sfui.config.textures.white,
        tile = true,
        tileSize = 32,
    })
    backdrop:SetBackdropColor(cfg.backdrop.color[1], cfg.backdrop.color[2], cfg.backdrop.color[3], cfg.backdrop.color[4])
    local bar = CreateFrame(frameType, "sfui_" .. name, backdrop, template)
    bar:SetSize(cfg.width, cfg.height)
    bar:SetPoint("CENTER")
    if bar.SetStatusBarTexture then
        local textureName = SfuiDB.barTexture
        local LSM = LibStub("LibSharedMedia-3.0", true)
        local texturePath
        if LSM then
            texturePath = LSM:Fetch("statusbar", textureName)
        end

        if not texturePath or texturePath == "" then
            texturePath = sfui.config.barTexture
        end
        bar:SetStatusBarTexture(texturePath)
    end
    bar.backdrop = backdrop
    bar.fadeInAnim, bar.fadeOutAnim = sfui.common.create_fade_animations(backdrop)
    return bar
end

function sfui.common.create_fade_animations(frame)
    local fadeInGroup = frame:CreateAnimationGroup()
    local fadeIn = fadeInGroup:CreateAnimation("Alpha")
    fadeIn:SetDuration(0.5)
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetScript("OnPlay", function() frame:Show() end)
    local fadeOutGroup = frame:CreateAnimationGroup()
    local fadeOut = fadeOutGroup:CreateAnimation("Alpha")
    fadeOut:SetDuration(0.5)
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetScript("OnFinished", function() frame:Hide() end)
    return fadeInGroup, fadeOutGroup
end

function sfui.common.get_resource_color(resource)
    local colorInfo = GetPowerBarColor(resource)
    if colorInfo then return colorInfo end
    local powerName = ""
    if type(resource) == "number" then
        powerName = powerTypeToName[resource]
    end
    return resourceColorsCache[powerName] or GetPowerBarColor("MANA")
end

function sfui.common.create_border(frame, thickness, color)
    local mult = sfui.pixelScale or 1
    thickness = (thickness or 1) * mult

    if not frame.borders then
        frame.borders = {}
        for i = 1, 4 do
            frame.borders[i] = frame:CreateTexture(nil, "BACKGROUND")
            frame.borders[i]:SetTexture("Interface\\Buttons\\WHITE8x8")
        end
    end

    local top, bottom, left, right = unpack(frame.borders)
    local r, g, b, a = 0, 0, 0, 1
    if color then r, g, b, a = unpack(color) end

    for _, border in ipairs(frame.borders) do
        border:SetVertexColor(r, g, b, a)
    end

    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0); top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0); top:SetHeight(
        thickness)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0); bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0); bottom
        :SetHeight(thickness)
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0); left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0); left
        :SetWidth(thickness)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0); right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0); right
        :SetWidth(thickness)
end

function sfui.common.apply_square_icon_style(frame, texture)
    if not frame or not texture then return end

    -- Crop WoW's default rounded edges to make it a perfect square
    texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Inset the texture slightly off the frame edges
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    texture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)

    -- Create a solid black backdrop to serve as the border behind the inset texture
    if not frame.borderBackdrop then
        frame.borderBackdrop = _G.CreateFrame("Frame", nil, frame, "BackdropTemplate")
        frame.borderBackdrop:SetAllPoints(frame)
        -- Ensure it renders strictly behind the texture
        frame.borderBackdrop:SetFrameLevel(math.max(1, frame:GetFrameLevel() - 1))

        frame.borderBackdrop:SetBackdrop({
            bgFile = sfui.config.textures.white,
            edgeFile = "",
            tile = false,
            tileSize = 0,
            edgeSize = 0,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        })
        frame.borderBackdrop:SetBackdropColor(0, 0, 0, 1)
    end
    frame.borderBackdrop:Show()
end

function sfui.common.create_flat_button(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)

    local mult = sfui.pixelScale or 1
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = mult,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    btn:SetBackdropColor(0, 0, 0, 1)
    local gray = sfui.config.colors.gray
    btn:SetBackdropBorderColor(gray[1], gray[2], gray[3], 1)

    btn:SetNormalFontObject("GameFontHighlightSmall")
    btn:SetText(text)
    local fs = btn:GetFontString()
    local white = sfui.config.colors.white
    if fs then fs:SetTextColor(white[1], white[2], white[3], 1) end

    local cyan = sfui.config.colors.cyan
    btn:SetScript("OnEnter", function(self)
        if self:GetFontString() then
            self:GetFontString():SetTextColor(cyan[1], cyan[2], cyan[3], 1)
        end
        self:SetBackdropBorderColor(cyan[1], cyan[2], cyan[3], 1)
    end)
    btn:SetScript("OnLeave", function(self)
        if self:GetFontString() then
            self:GetFontString():SetTextColor(white[1], white[2], white[3], 1)
        end
        self:SetBackdropBorderColor(gray[1], gray[2], gray[3], 1)
    end)

    return btn
end

function sfui.common.create_checkbox(parent, label, dbKeyOrGetter, onClickFunc, tooltip)
    local cb = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
    cb:SetSize(20, 20)

    -- Custom Backdrop
    cb:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    local app = sfui.config.appearance
    cb:SetBackdropColor(app.widgetBackdropColor[1], app.widgetBackdropColor[2], app.widgetBackdropColor[3],
        app.widgetBackdropColor[4])
    cb:SetBackdropBorderColor(0, 0, 0, 1)

    -- Checked Texture (Highlight Purple/Custom)
    cb:SetCheckedTexture("Interface/Buttons/WHITE8X8")
    cb:GetCheckedTexture():SetVertexColor(app.highlightColor[1], app.highlightColor[2], app.highlightColor[3], 1)
    cb:GetCheckedTexture():SetPoint("TOPLEFT", 2, -2)
    cb:GetCheckedTexture():SetPoint("BOTTOMRIGHT", -2, 2)

    -- Highlight
    cb:SetHighlightTexture("Interface/Buttons/WHITE8X8")
    cb:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.1)

    -- Text
    cb.text = cb:CreateFontString(nil, "OVERLAY", sfui.config.font)
    cb.text:SetPoint("LEFT", cb, "RIGHT", 5, 0)
    cb.text:SetText(label)
    cb.label = cb.text -- Alias for consistency

    local function updateChecked()
        if type(dbKeyOrGetter) == "string" then
            if SfuiDB[dbKeyOrGetter] ~= nil then cb:SetChecked(SfuiDB[dbKeyOrGetter]) end
        elseif type(dbKeyOrGetter) == "function" then
            cb:SetChecked(dbKeyOrGetter())
        end
    end

    cb:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        if type(dbKeyOrGetter) == "string" then SfuiDB[dbKeyOrGetter] = checked end
        if onClickFunc then onClickFunc(checked) end
    end)
    cb:SetScript("OnShow", updateChecked)
    updateChecked() -- Initialize state immediately

    if tooltip then
        cb:SetScript("OnEnter", function(self)
            local tip = sfui.tooltip or _G.GameTooltip
            if tip then
                tip:SetOwner(self, "ANCHOR_RIGHT")
                tip:SetText(tooltip)
                tip:Show()
            end
        end)
        cb:SetScript("OnLeave", function(self)
            local tip = sfui.tooltip or _G.GameTooltip
            if tip then tip:Hide() end
        end)
    end
    return cb
end

function sfui.common.style_text(fs, fontObj, size, flags)
    if not fs then return end
    if fontObj then fs:SetFontObject(fontObj) end
    if size or flags then
        local font, curSize, curFlags = fs:GetFont()
        fs:SetFont(font, size or curSize, flags or "")
    end
    -- Standard Shadow
    fs:SetShadowOffset(0, 0)
    fs:SetTextColor(1, 1, 1, 1)
end

function sfui.common.create_color_swatch(parent, initialColor, onSetFunc)
    local swatch = CreateFrame("Button", nil, parent, "BackdropTemplate")
    swatch:SetSize(16, 16)

    swatch:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    swatch:SetBackdropBorderColor(0, 0, 0, 1)

    local function SetColor(r, g, b)
        swatch:SetBackdropColor(r, g, b, 1)
        if onSetFunc then onSetFunc(r, g, b) end
    end

    local app = sfui.config.appearance
    if initialColor then
        local r = initialColor.r or initialColor[1] or app.highlightColor[1]
        local g = initialColor.g or initialColor[2] or app.highlightColor[2]
        local b = initialColor.b or initialColor[3] or app.highlightColor[3]
        swatch:SetBackdropColor(r, g, b, 1)
    else
        swatch:SetBackdropColor(app.highlightColor[1], app.highlightColor[2], app.highlightColor[3], 1)
    end

    swatch:SetScript("OnClick", function()
        local r, g, b = swatch:GetBackdropColor()

        if ColorPickerFrame.SetupColorPickerAndShow then
            local info = {
                r = r,
                g = g,
                b = b,
                hasOpacity = false,
                swatchFunc = function()
                    local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                    SetColor(nr, ng, nb)
                end,
                cancelFunc = function() SetColor(r, g, b) end,
            }
            ColorPickerFrame:SetupColorPickerAndShow(info)
        else
            ColorPickerFrame:SetColorRGB(r, g, b)
            ColorPickerFrame.hasOpacity = false
            ColorPickerFrame.func = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                SetColor(nr, ng, nb)
            end
            ColorPickerFrame.cancelFunc = function() SetColor(r, g, b) end
            ColorPickerFrame:Hide()
            ColorPickerFrame:Show()
        end
    end)
    return swatch
end

function sfui.common.create_cvar_checkbox(parent, label, cvar, tooltip)
    return sfui.common.create_checkbox(parent, label, function()
        if SfuiDB[cvar] ~= nil then
            return SfuiDB[cvar]
        else
            return C_CVar.GetCVarBool(cvar)
        end
    end, function(checked)
        C_CVar.SetCVar(cvar, checked and "1" or "0")
        SfuiDB[cvar] = checked
    end, tooltip)
end

function sfui.common.create_slider_input(parent, label, dbKeyOrGetter, minVal, maxVal, step, onValueChangedFunc, tooltip,
                                         width)
    local container = CreateFrame("Frame", nil, parent)

    -- Detect if 'tooltip' was actually 'width' (legacy support check)
    local w = 160
    if type(width) == "number" then
        w = width
    elseif type(tooltip) == "number" then
        w = tooltip
        tooltip = nil
    end

    container:SetSize(w, 40) -- Compact height

    if tooltip then
        container:SetScript("OnEnter", function(self)
            local tip = sfui.tooltip or _G.GameTooltip
            if tip then
                tip:SetOwner(self, "ANCHOR_RIGHT")
                tip:SetText(tooltip)
                tip:Show()
            end
        end)
        container:SetScript("OnLeave", function(self)
            local tip = sfui.tooltip or _G.GameTooltip
            if tip then tip:Hide() end
        end)
    end

    local title = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText(label)
    title:SetTextColor(1, 1, 1, 0.8)

    local slider = CreateFrame("Slider", nil, container, "BackdropTemplate")
    slider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    slider:SetSize(w - 60, 10) -- Dynamic width
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    local app = sfui.config.appearance
    slider:SetBackdropColor(app.sliderBackdropColor[1], app.sliderBackdropColor[2], app.sliderBackdropColor[3],
        app.sliderBackdropColor[4])
    slider:SetBackdropBorderColor(0, 0, 0, 1)

    -- Thumb
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(6, 10)
    thumb:SetColorTexture(app.highlightColor[1], app.highlightColor[2], app.highlightColor[3], 1)
    slider:SetThumbTexture(thumb)

    -- EditBox (Square, Flat, RIGHT of Slider)
    local editbox = CreateFrame("EditBox", nil, container, "BackdropTemplate")
    editbox:SetSize(45, 16)
    editbox:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    editbox:SetAutoFocus(false)
    editbox:SetFontObject("GameFontHighlightSmall")
    editbox:SetJustifyH("CENTER")

    editbox:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    editbox:SetBackdropColor(app.editBoxColor[1], app.editBoxColor[2], app.editBoxColor[3], app.editBoxColor[4])
    editbox:SetBackdropBorderColor(0, 0, 0, 1)

    editbox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editbox:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then
            if val < minVal then val = minVal end
            if val > maxVal then val = maxVal end
            slider:SetValue(val)
            if type(dbKeyOrGetter) == "string" then SfuiDB[dbKeyOrGetter] = val end
            if onValueChangedFunc then onValueChangedFunc(val) end
        end
        self:ClearFocus()
    end)
    editbox:SetScript("OnEditFocusGained",
        function(self) self:SetBackdropBorderColor(app.highlightColor[1], app.highlightColor[2], app.highlightColor[3], 1) end)
    editbox:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(0, 0, 0, 1) end)


    local lastUpdate = 0
    local throttle = 0.05 -- 50ms throttle

    slider:SetScript("OnValueChanged", function(self, value)
        local stepped = math.floor((value - minVal) / step + 0.5) * step + minVal
        if type(dbKeyOrGetter) == "string" then SfuiDB[dbKeyOrGetter] = stepped end
        -- Clean number display
        local displayVal = math.floor(stepped * 100) / 100
        editbox:SetText(tostring(displayVal))

        local now = GetTime()
        if now - lastUpdate > throttle then
            lastUpdate = now
            if onValueChangedFunc then onValueChangedFunc(stepped) end
        end
    end)

    -- Ensure final value is sent on mouse up and persisted
    slider:SetScript("OnMouseUp", function(self)
        local value = self:GetValue()
        local stepped = math.floor((value - minVal) / step + 0.5) * step + minVal
        if type(dbKeyOrGetter) == "string" then SfuiDB[dbKeyOrGetter] = stepped end
        if onValueChangedFunc then onValueChangedFunc(stepped) end
        lastUpdate = GetTime() -- Prevent immediate double-fire from Drag logic
    end)

    -- Expose components for pooling
    container.slider = slider
    container.editbox = editbox
    container.label = title

    slider:SetScript("OnShow", function(self)
        local val
        if type(dbKeyOrGetter) == "string" then
            val = SfuiDB[dbKeyOrGetter]
        elseif type(dbKeyOrGetter) == "function" then
            val = dbKeyOrGetter()
        end
        if val == nil then val = minVal end
        self:SetValue(val)
        editbox:SetText(math.floor(val * 100) / 100)
    end)

    -- Expose method to set value programmatically
    function container:SetSliderValue(val)
        slider:SetValue(val)
        editbox:SetText(tostring(val))
    end

    return container
end

function sfui.common.create_input_field(parent, label, dbKeyOrGetter, width, onValueChangedFunc, tooltip)
    local container = CreateFrame("Frame", nil, parent)
    local w = width or 100
    container:SetSize(w, 40)

    if tooltip then
        container:SetScript("OnEnter", function(self)
            local tip = sfui.tooltip or _G.GameTooltip
            if tip then
                tip:SetOwner(self, "ANCHOR_RIGHT")
                tip:SetText(tooltip)
                tip:Show()
            end
        end)
        container:SetScript("OnLeave", function(self)
            local tip = sfui.tooltip or _G.GameTooltip
            if tip then tip:Hide() end
        end)
    end

    local title = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText(label)
    title:SetTextColor(1, 1, 1, 0.8)

    local editbox = CreateFrame("EditBox", nil, container, "BackdropTemplate")
    editbox:SetSize(w - 10, 20)
    editbox:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    editbox:SetAutoFocus(false)
    editbox:SetFontObject("GameFontHighlightSmall")
    editbox:SetJustifyH("LEFT")
    editbox:SetTextInsets(5, 0, 0, 0)

    local app = sfui.config.appearance
    editbox:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    editbox:SetBackdropColor(app.editBoxColor[1], app.editBoxColor[2], app.editBoxColor[3], app.editBoxColor[4])
    editbox:SetBackdropBorderColor(0, 0, 0, 1)

    editbox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editbox:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then
            if type(dbKeyOrGetter) == "string" then
                -- Support nested keys like "healthBarX"
                local keys = {}
                for key in string.gmatch(dbKeyOrGetter, "([^.]+)") do
                    table.insert(keys, key)
                end

                local current = SfuiDB
                for i = 1, #keys - 1 do
                    if not current[keys[i]] then current[keys[i]] = {} end
                    current = current[keys[i]]
                end
                current[keys[#keys]] = val
            end
            if onValueChangedFunc then onValueChangedFunc(val) end
        end
        self:ClearFocus()
    end)
    editbox:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(app.highlightColor[1], app.highlightColor[2], app.highlightColor[3], 1)
    end)
    editbox:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(0, 0, 0, 1)
        -- Reset value to DB on focus lost and invalid input
        local val = tonumber(self:GetText())
        if not val then
            if type(dbKeyOrGetter) == "string" then
                local keys = {}
                for key in string.gmatch(dbKeyOrGetter, "([^.]+)") do
                    table.insert(keys, key)
                end
                local current = SfuiDB
                for i = 1, #keys do
                    if current then current = current[keys[i]] end
                end
                self:SetText(tostring(current or 0))
            elseif type(dbKeyOrGetter) == "function" then
                self:SetText(tostring(dbKeyOrGetter() or 0))
            end
        end
    end)

    editbox:SetScript("OnShow", function(self)
        local val
        if type(dbKeyOrGetter) == "string" then
            val = SfuiDB[dbKeyOrGetter]
        elseif type(dbKeyOrGetter) == "function" then
            val = dbKeyOrGetter()
        end
        self:SetText(tostring(val or 0))
    end)

    container.editbox = editbox
    container.label = title
    return container
end

function sfui.common.set_color(element, colorName, alpha)
    local color = sfui.config.colors[colorName]
    if not color then return end
    alpha = alpha or 1

    if element.SetTextColor then
        element:SetTextColor(color[1], color[2], color[3], alpha)
    elseif element.SetBackdropBorderColor then
        element:SetBackdropBorderColor(color[1], color[2], color[3], alpha)
    elseif element.SetBackdropColor then
        element:SetBackdropColor(color[1], color[2], color[3], alpha)
    end
end

function sfui.common.create_font_string(parent, font, point, x, y, colorName)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    if point then
        fs:SetPoint(point, x or 0, y or 0)
    end
    if colorName then
        sfui.common.set_color(fs, colorName)
    end
    return fs
end

function sfui.common.is_item_known(itemLink)
    if not itemLink then return false end

    local data = C_TooltipInfo.GetHyperlink(itemLink)
    if data and data.lines then
        for _, line in ipairs(data.lines) do
            local text = line.leftText
            if text then
                if text == ITEM_SPELL_KNOWN or text == "Already known" then
                    return true
                end
                if string.find(text, "You've collected this appearance") then
                    return true
                end
            end
        end
    end

    local itemID = tonumber(string.match(itemLink, "item:(%d+)"))
    if itemID then
        local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(itemID)
        if sourceID then
            local categoryID, visualID, canEnchant, icon, isCollected = C_TransmogCollection.GetAppearanceSourceInfo(
                sourceID)
            if isCollected then
                return true
            end
        end

        if C_ToyBox and C_ToyBox.GetToyInfo then
            local toyID = C_ToyBox.GetToyInfo(itemID)
            if toyID and PlayerHasToy(itemID) then return true end
        end
    end

    return false
end

function sfui.common.shorten_name(name, length)
    if not name or type(name) ~= "string" then return "" end
    length = length or 25
    if string.len(name) <= length then return name end
    return string.sub(name, 1, length - 3) .. "..."
end

-- Shared Masque group for all sfui buttons
function sfui.common.get_masque_group()
    -- Check global setting
    local enabled = sfui.config.icon_panel_global_defaults.enableMasque
    if SfuiDB and SfuiDB.iconGlobalSettings and SfuiDB.iconGlobalSettings.enableMasque ~= nil then
        enabled = SfuiDB.iconGlobalSettings.enableMasque
    end

    if not enabled then
        return nil
    end

    local Masque = LibStub and LibStub("Masque", true)
    if not Masque then return nil end
    local group = Masque:Group("sfui")
    if group and not group._sfui_init then
        -- Set "Dream" as the preferred default skin with safety checks
        if group.Skin then
            group:Skin("Dream")
        elseif group.SetSkin then
            group:SetSkin("Dream")
        end
        group._sfui_init = true
    end
    return group
end

-- Centralized Helper to Sync Frame with Masque State
function sfui.common.sync_masque(frame, subElements)
    if not frame then return end
    local Masque = LibStub and LibStub("Masque", true)
    if not Masque then return end
    local group = Masque:Group("sfui")
    if not group then return end

    local enabled = sfui.config.icon_panel_global_defaults.enableMasque
    if SfuiDB and SfuiDB.iconGlobalSettings and SfuiDB.iconGlobalSettings.enableMasque ~= nil then
        enabled = SfuiDB.iconGlobalSettings.enableMasque
    end

    if enabled then
        if not frame._isMasqued then
            group:AddButton(frame, subElements)
            frame._isMasqued = true
        end
    else
        if frame._isMasqued then
            group:RemoveButton(frame)
            frame._isMasqued = false
        end
    end
end

-- ========================
-- Item Utilities
-- ========================

-- Checks if an item link corresponds to a housing decor item
function sfui.common.is_housing_decor(link)
    local itemID = sfui.common.get_item_id_from_link(link)
    if itemID and C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByItem then
        local info = C_HousingCatalog.GetCatalogEntryInfoByItem(itemID, false)
        return info and info.entryID and info.entryID.entryType == 1
    end
    return false
end

-- Checks if the player is currently in a Player Housing zone (Razorwind Shores, Founder's Point, houses, plots, neighborhoods)
function sfui.common.is_housing_zone()
    -- 1. Official C_Housing APIs (Patch 12.0+)
    if C_Housing then
        if C_Housing.IsOnNeighborhoodMap and C_Housing.IsOnNeighborhoodMap() then return true end
        if C_Housing.IsInsideHouseOrPlot and C_Housing.IsInsideHouseOrPlot() then return true end
        if C_Housing.IsInsideHouse and C_Housing.IsInsideHouse() then return true end
        if C_Housing.IsInsidePlot and C_Housing.IsInsidePlot() then return true end
        if C_Housing.GetCurrentNeighborhoodGUID and C_Housing.GetCurrentNeighborhoodGUID() then return true end
    end
    if C_HousingNeighborhood and C_HousingNeighborhood.GetNeighborhoodMapData then
        local ok, data = pcall(C_HousingNeighborhood.GetNeighborhoodMapData)
        if ok and data and #data > 0 then return true end
    end

    -- 2. Instance Info Name check (Razorwind Shores, Founder's Point, etc.)
    if _G.GetInstanceInfo then
        local instName = _G.GetInstanceInfo()
        if instName and instName ~= "" then
            local lower = instName:lower()
            if lower:find("razorwind") or lower:find("founder") or lower:find("housing") or lower:find("neighborhood") then
                return true
            end
        end
    end

    -- 3. Area and Subzone text checks
    local zone = (_G.GetRealZoneText and _G.GetRealZoneText()) or (_G.GetZoneText and _G.GetZoneText()) or ""
    if zone ~= "" then
        local lower = zone:lower()
        if lower:find("razorwind") or lower:find("founder") or lower:find("housing") or lower:find("neighborhood") then
            return true
        end
    end

    local subzone = (_G.GetSubZoneText and _G.GetSubZoneText()) or (_G.GetMinimapZoneText and _G.GetMinimapZoneText()) or ""
    if subzone ~= "" then
        local lower = subzone:lower()
        if lower:find("razorwind") or lower:find("founder") then
            return true
        end
    end

    -- 4. Map Name check via C_Map
    local mapName = sfui.common.get_player_map_name()
    if mapName then
        local lower = mapName:lower()
        if lower:find("razorwind") or lower:find("founder") or lower:find("housing") or lower:find("neighborhood") then
            return true
        end
    end

    return false
end

-- Extracts the item ID from an item link
-- @param link: Item link string (e.g., "|cff0070dd|Hitem:12345:0:0:0|h[Item Name]|h|r")
-- @return: Item ID as a number, or nil if not found
function sfui.common.get_item_id_from_link(link)
    if not link then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- ========================
-- Utility Helpers
-- ========================



-- @param parent: Parent frame
-- @param text: Button text
-- @param width: Button width
-- @param height: Button height
-- @return: Button frame
function sfui.common.create_styled_button(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 120, height or 25)
    btn:SetBackdrop({
        bgFile = sfui.config.textures.white,
        edgeFile = sfui.config.textures.white,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    btn:SetBackdropColor(0.2, 0.2, 0.2, 1)
    btn:SetBackdropBorderColor(0, 0, 0, 1)

    -- Hover effect
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(sfui.config.colors.purple[1], sfui.config.colors.purple[2],
            sfui.config.colors.purple[3], 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0, 0, 0, 1)
    end)

    -- Text
    btn.text = btn:CreateFontString(nil, "OVERLAY", sfui.config.font)
    btn.text:SetPoint("CENTER")
    btn.text:SetText(text or "")
    sfui.common.style_text(btn.text)

    return btn
end

-- Moved from config.lua to clean up that file
function sfui.initialize_database()
    if type(SfuiDB) ~= "table" then SfuiDB = {} end
    if type(SfuiDecorDB) ~= "table" then SfuiDecorDB = {} end
    SfuiDecorDB.items = SfuiDecorDB.items or {}
    SfuiDB.iconGlobalSettings = SfuiDB.iconGlobalSettings or {}
    local igs = SfuiDB.iconGlobalSettings
    local g = sfui.config.icon_panel_global_defaults
    if igs.enableMasque == nil then igs.enableMasque = g.enableMasque end
    if igs.readyGlow == nil then igs.readyGlow = g.readyGlow end
    if igs.glowType == nil then igs.glowType = g.glowType or "pixel" end

    if type(SfuiDB.barTexture) ~= "string" or SfuiDB.barTexture == "" then SfuiDB.barTexture = "Flat" end
    SfuiDB.absorbBarColor = SfuiDB.absorbBarColor or sfui.config.absorbBarColor

    SfuiDB.minimap_icon = SfuiDB.minimap_icon or { hide = false }
    SfuiDB.minimap_collect_buttons = (SfuiDB.minimap_collect_buttons == nil) and true or SfuiDB.minimap_collect_buttons
    if SfuiDB.minimap_rearrange == nil then SfuiDB.minimap_rearrange = true end
    SfuiDB.minimap_buttons_mouseover = (SfuiDB.minimap_buttons_mouseover == nil) and false or
        SfuiDB.minimap_buttons_mouseover
    if SfuiDB.minimap_masque == nil then SfuiDB.minimap_masque = true end
    if SfuiDB.minimap_auto_zoom == nil then SfuiDB.minimap_auto_zoom = true end
    if SfuiDB.minimap_auto_zoom_delay == nil then SfuiDB.minimap_auto_zoom_delay = 5 end
    if SfuiDB.minimap_button_x == nil then SfuiDB.minimap_button_x = sfui.config.minimap.button_bar.defaultX end
    if SfuiDB.minimap_button_y == nil then SfuiDB.minimap_button_y = sfui.config.minimap.button_bar.defaultY end
    if SfuiDB.autoSellGreys == nil then SfuiDB.autoSellGreys = true end
    if SfuiDB.autoRepair == nil then SfuiDB.autoRepair = true end
    if SfuiDB.repairThreshold == nil then SfuiDB.repairThreshold = 90 end
    if SfuiDB.enableMasterHammer == nil then SfuiDB.enableMasterHammer = true end
    if SfuiDB.enableMerchant == nil then SfuiDB.enableMerchant = true end
    if SfuiDB.enableDecor == nil then SfuiDB.enableDecor = false end -- Opt-in feature
    if SfuiDB.repairIconColor == nil then SfuiDB.repairIconColor = sfui.config.masterHammer.defaultColor end
    if SfuiDB.enableCursorRing == nil then SfuiDB.enableCursorRing = true end
    if SfuiDB.cursorRingScale == nil then SfuiDB.cursorRingScale = 1.0 end
    if SfuiDB.useSpecColor == nil then SfuiDB.useSpecColor = true end
    if SfuiDB.specColorFallback == nil then SfuiDB.specColorFallback = { 1, 1, 1, 1 } end

    -- Bar settings
    if SfuiDB.healthBarX == nil then SfuiDB.healthBarX = 0 end
    if SfuiDB.healthBarY == nil then SfuiDB.healthBarY = 300 end
    if SfuiDB.enableHealthBar == nil then SfuiDB.enableHealthBar = true end
    if SfuiDB.enablePowerBar == nil then SfuiDB.enablePowerBar = true end
    if SfuiDB.enableSecondaryPowerBar == nil then SfuiDB.enableSecondaryPowerBar = true end
    if SfuiDB.enableVigorBar == nil then SfuiDB.enableVigorBar = true end
    if SfuiDB.enableMountSpeedBar == nil then SfuiDB.enableMountSpeedBar = true end

    -- Castbar settings
    if SfuiDB.castBarEnabled == nil then SfuiDB.castBarEnabled = sfui.config.castBar.enabled end
    if SfuiDB.castBarX == nil then SfuiDB.castBarX = sfui.config.castBar.pos.x end
    if SfuiDB.castBarY == nil then SfuiDB.castBarY = sfui.config.castBar.pos.y end
    sfui.config.castBar.enabled = SfuiDB.castBarEnabled
    sfui.config.castBar.pos.x = SfuiDB.castBarX
    sfui.config.castBar.pos.y = SfuiDB.castBarY

    if SfuiDB.targetCastBarEnabled == nil then SfuiDB.targetCastBarEnabled = sfui.config.targetCastBar.enabled end
    if SfuiDB.targetCastBarX == nil then SfuiDB.targetCastBarX = sfui.config.targetCastBar.pos.x end
    if SfuiDB.targetCastBarY == nil then SfuiDB.targetCastBarY = sfui.config.targetCastBar.pos.y end
    sfui.config.targetCastBar.enabled = SfuiDB.targetCastBarEnabled
    sfui.config.targetCastBar.pos.x = SfuiDB.targetCastBarX
    sfui.config.targetCastBar.pos.y = SfuiDB.targetCastBarY

    -- automation settings
    if SfuiDB.auto_role_check == nil then SfuiDB.auto_role_check = true end
    if SfuiDB.auto_sign_lfg == nil then SfuiDB.auto_sign_lfg = true end
    if SfuiDB.autoDungeonPortalPopup == nil then SfuiDB.autoDungeonPortalPopup = true end
    if SfuiDB.portalPopupOnlyWhenFull == nil then SfuiDB.portalPopupOnlyWhenFull = true end

    -- Tracked Bars
    SfuiDB.trackedBars = SfuiDB.trackedBars or {}
    if SfuiDB.trackedBarsX == nil then SfuiDB.trackedBarsX = -300 end
    if SfuiDB.trackedBarsY == nil then SfuiDB.trackedBarsY = 300 end
end

-- Helper to systematically hide specific Blizzard CooldownViewer frames
local cooldownViewersInitialized = false

function sfui.common.hide_blizzard_cooldown_viewers()
    -- Ensure the addon is loaded first
    if not C_AddOns.IsAddOnLoaded("Blizzard_CooldownViewer") then
        C_AddOns.LoadAddOn("Blizzard_CooldownViewer")
    end

    local viewers = {
        "EssentialCooldownViewer",
        "UtilityCooldownViewer",
        "BuffBarCooldownViewer",
    }

    -- Ensure BuffIconCooldownViewer (Blizzard Tracked Buffs stack) remains visible and interactive
    local buffViewer = _G["BuffIconCooldownViewer"]
    if buffViewer then
        buffViewer._sfui_setting_alpha = true
        buffViewer:SetAlpha(1)
        buffViewer._sfui_setting_alpha = false
        buffViewer:EnableMouse(true)
    end

    for _, viewerName in ipairs(viewers) do
        local viewer = _G[viewerName]
        if viewer then
            viewer:SetAlpha(0)
            viewer:EnableMouse(false)

            -- Suppress UNIT_AURA on hidden cooldown viewers (Essential & Utility).
            -- Blizzard's CooldownViewer items invoke ActionButtonSpellAlertManager:ShowAlert
            -- in their OnUnitAura glow-check. Masque's global hooksecurefunc on ShowAlert runs,
            -- tainting the execution context with 'Masque'. When Blizzard then attempts to
            -- inspect unitAuraUpdateInfo.addedAuras (a restricted C SecretTable in combat)
            -- at line 1865 (CheckAuraAddedAlertTriggers), the game errors with:
            -- "attempted to index a table that cannot be accessed while tainted (execution tainted by 'Masque')".
            -- Since SFUI handles action cooldown tracking independently, suppressing UNIT_AURA here
            -- eliminates this taint vector completely and saves CPU cycles in combat.
            if viewerName == "EssentialCooldownViewer" or viewerName == "UtilityCooldownViewer" then
                if viewer.UnregisterEvent then
                    viewer:UnregisterEvent("UNIT_AURA")
                end
            end

            if not viewer._sfui_alpha_hooked then
                viewer._sfui_alpha_hooked = true
                hooksecurefunc(viewer, "SetAlpha", function(self, alpha)
                    if self == _G["BuffIconCooldownViewer"] then return end
                    if alpha > 0 and not self._sfui_setting_alpha then
                        self._sfui_setting_alpha = true
                        self:SetAlpha(0)
                        self._sfui_setting_alpha = false
                    end
                end)
            end

            if not viewer._sfui_show_hooked then
                viewer._sfui_show_hooked = true
                viewer:HookScript("OnShow", function(self)
                    self:SetAlpha(0)
                    self:EnableMouse(false)
                    if (viewerName == "EssentialCooldownViewer" or viewerName == "UtilityCooldownViewer") and self.UnregisterEvent then
                        self:UnregisterEvent("UNIT_AURA")
                    end
                end)
            end

            if not viewer._sfui_opacity_hooked and viewer.UpdateSystemSettingOpacity then
                viewer._sfui_opacity_hooked = true
                hooksecurefunc(viewer, "UpdateSystemSettingOpacity", function(self)
                    self:SetAlpha(0)
                end)
            end
        end
    end

    if not cooldownViewersInitialized then
        cooldownViewersInitialized = true

        -- Cinematic and cutscene frame OnHide hooks
        if _G.CinematicFrame then
            _G.CinematicFrame:HookScript("OnHide", function()
                sfui.common.hide_blizzard_cooldown_viewers()
            end)
        end
        if _G.MovieFrame then
            _G.MovieFrame:HookScript("OnHide", function()
                sfui.common.hide_blizzard_cooldown_viewers()
            end)
        end

        -- Blizzard EventRegistry callbacks (strictly non-panel events)
        if EventRegistry and EventRegistry.RegisterCallback then
            EventRegistry:RegisterCallback("CinematicFrame.CinematicStopped", function()
                sfui.common.hide_blizzard_cooldown_viewers()
            end)
            EventRegistry:RegisterCallback("EditMode.Exit", function()
                sfui.common.hide_blizzard_cooldown_viewers()
            end)
        end

        -- Game events for cinematics, movies, challenge mode, and layout updates
        if sfui.events and sfui.events.RegisterEvent then
            sfui.events.RegisterEvent("CINEMATIC_STOP", function()
                sfui.common.hide_blizzard_cooldown_viewers()
            end)
            sfui.events.RegisterEvent("STOP_MOVIE", function()
                sfui.common.hide_blizzard_cooldown_viewers()
            end)
            sfui.events.RegisterEvent("CHALLENGE_MODE_START", function()
                sfui.common.hide_blizzard_cooldown_viewers()
            end)
            sfui.events.RegisterEvent("CHALLENGE_MODE_RESET", function()
                sfui.common.hide_blizzard_cooldown_viewers()
            end)
            sfui.events.RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", function()
                sfui.common.hide_blizzard_cooldown_viewers()
            end)
            sfui.events.RegisterEvent("ADDON_LOADED", function(event, loadedAddon)
                if loadedAddon == "Blizzard_CooldownViewer" then
                    sfui.common.hide_blizzard_cooldown_viewers()
                end
            end)
        end
    end

    -- Ensure the CVar is set to 1 so Blizzard's internal data systems are active.
    -- We hide the frames visually, but we need the data provider to function.
    if GetCVar("cooldownViewerEnabled") == "0" then
        SetCVar("cooldownViewerEnabled", 1)
    end
end

function sfui.common.are_blizzard_cooldown_viewers_hidden()
    local viewers = {
        "EssentialCooldownViewer",
        "UtilityCooldownViewer",
        "BuffBarCooldownViewer",
    }
    for _, name in ipairs(viewers) do
        local f = _G[name]
        if f and (f:GetAlpha() > 0 or f:IsMouseEnabled()) then
            return false
        end
    end
    return true
end

-- Standard SFUI Close Button ("✕" icon with hover highlight)
function sfui.common.create_close_button(parent, onClickFunc, size)
    size = size or 20
    local btn = sfui.common.create_flat_button(parent, "✕", size, size)
    btn:SetPoint("TOPRIGHT", -6, -6)
    btn:SetScript("OnClick", onClickFunc or function()
        if parent and parent.Hide then parent:Hide() end
    end)
    return btn
end

-- Styles a scrollbar with SFUI minimal flat design
function sfui.common.style_scrollbar(scrollBar)
    if not scrollBar then return end

    local name = scrollBar.GetName and scrollBar:GetName()
    local upBtn = (name and _G[name .. "ScrollUpButton"]) or scrollBar.ScrollUpButton
    local downBtn = (name and _G[name .. "ScrollDownButton"]) or scrollBar.ScrollDownButton

    if upBtn and upBtn.Hide then
        upBtn:Hide()
        upBtn:SetAlpha(0)
        upBtn:EnableMouse(false)
    end
    if downBtn and downBtn.Hide then
        downBtn:Hide()
        downBtn:SetAlpha(0)
        downBtn:EnableMouse(false)
    end

    if scrollBar.Track and scrollBar.Track.Hide then
        scrollBar.Track:Hide()
    end

    -- Hide default background/marble regions
    if scrollBar.GetNumRegions then
        for i = 1, scrollBar:GetNumRegions() do
            local region = select(i, scrollBar:GetRegions())
            if region and region:IsObjectType("Texture") and region ~= scrollBar:GetThumbTexture() then
                region:SetTexture(nil)
            end
        end
    end

    scrollBar:SetWidth(6)

    if not scrollBar.SetBackdrop and BackdropTemplateMixin then
        Mixin(scrollBar, BackdropTemplateMixin)
    end
    if scrollBar.SetBackdrop then
        scrollBar:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
        })
        scrollBar:SetBackdropColor(0, 0, 0, 0.3)
    end

    local thumb = scrollBar:GetThumbTexture()
    if not thumb and scrollBar.CreateTexture then
        thumb = scrollBar:CreateTexture(nil, "ARTWORK")
        scrollBar:SetThumbTexture(thumb)
    end
    if thumb then
        thumb:SetSize(6, 30)
        thumb:SetColorTexture(1, 1, 1, 0.75)
    end

    local parent = scrollBar:GetParent()
    if parent and scrollBar.ClearAllPoints then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, -2)
        scrollBar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -2, 2)
    end
end

-- Centralized Dropdown Menu Widget
local activeDropdown = nil
function sfui.common.create_dropdown(parent, width, options, onSelectFunc, initialValue, fixedText, menuWidth)
    local actualOptions = (type(options) == "function") and options() or options
    local initialText = fixedText or "Select..."
    if not fixedText then
        if initialValue ~= nil then
            for _, opt in ipairs(actualOptions) do
                if opt.value == initialValue then
                    initialText = opt.text
                    break
                end
            end
        elseif actualOptions and #actualOptions > 0 then
            initialText = actualOptions[1].text
        end
    end

    local btn = sfui.common.create_flat_button(parent, initialText, width or 80, 18)

    local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -2)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetFrameLevel(100)
    menu:Hide()

    menu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    menu:SetBackdropColor(0, 0, 0, 0.9)
    menu:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

    local scrollFrame = CreateFrame("ScrollFrame", nil, menu, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -4, 4)
    scrollFrame:EnableMouseWheel(true)
    sfui.common.style_scrollbar(scrollFrame.ScrollBar)

    local scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(scrollContent)

    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, cur - delta * 20)))
    end)

    btn.menu = menu
    btn:HookScript("OnHide", function()
        if menu:IsShown() then
            menu:Hide()
            activeDropdown = nil
        end
    end)

    btn.SetSelectedValue = function(self, val)
        local currentOptions = (type(options) == "function") and options() or options
        for _, opt in ipairs(currentOptions) do
            if opt.value == val then
                if not fixedText then
                    if self.GetFontString and self:GetFontString() then
                        self:GetFontString():SetText(opt.text)
                    else
                        self:SetText(opt.text)
                    end
                end
                break
            end
        end
    end

    local function updateMenuSize()
        local currentOptions = (type(options) == "function") and options() or options
        local maxW = menuWidth or width or 80

        if not menuWidth then
            for _, opt in ipairs(currentOptions) do
                if opt.text then
                    local textWidth = #opt.text * 7
                    if textWidth > maxW then maxW = textWidth end
                end
            end
        end

        local totalH = #currentOptions * 20
        local maxH = 260
        local displayH = math.min(maxH, totalH)
        local needsScroll = totalH > maxH
        local extraW = needsScroll and 12 or 0

        menu:SetSize(maxW + 20 + extraW, displayH + 8)
        scrollContent:SetSize(maxW + 12, totalH)

        if scrollFrame.ScrollBar then
            if needsScroll then
                scrollFrame.ScrollBar:Show()
                scrollFrame:SetPoint("BOTTOMRIGHT", -12, 4)
            else
                scrollFrame.ScrollBar:Hide()
                scrollFrame:SetPoint("BOTTOMRIGHT", -4, 4)
            end
        end
    end

    local function fillOptions()
        local currentOptions = (type(options) == "function") and options() or options
        local y = 0

        scrollFrame:SetVerticalScroll(0)
        scrollContent.buttons = scrollContent.buttons or {}
        for _, optBtn in ipairs(scrollContent.buttons) do
            optBtn:Hide()
        end

        for i, opt in ipairs(currentOptions) do
            local optBtn = scrollContent.buttons[i]
            if not optBtn then
                optBtn = CreateFrame("Button", nil, scrollContent)
                scrollContent.buttons[i] = optBtn
                optBtn.textString = optBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                optBtn.textString:SetPoint("LEFT", 4, 0)
            end

            optBtn:SetSize(scrollContent:GetWidth(), 20)
            optBtn:SetPoint("TOPLEFT", 0, y)

            if opt.onRender then
                opt.onRender(optBtn, opt)
            else
                local t = optBtn.textString
                t:SetText(opt.text)

                optBtn:SetScript("OnEnter", function(self) t:SetTextColor(0, 1, 1) end)
                optBtn:SetScript("OnLeave", function(self) t:SetTextColor(1, 1, 1) end)

                optBtn:SetScript("OnClick", function()
                    if not fixedText then
                        btn:GetFontString():SetText(opt.text)
                    end
                    if onSelectFunc then onSelectFunc(opt.value) end

                    if not opt.keepOpen then
                        menu:Hide()
                        activeDropdown = nil
                    end
                end)
            end
            optBtn:Show()
            y = y - 20
        end
    end

    btn:SetScript("OnClick", function()
        if menu:IsShown() then
            menu:Hide()
            activeDropdown = nil
        else
            if activeDropdown then activeDropdown:Hide() end
            updateMenuSize()
            fillOptions()
            menu:Show()
            activeDropdown = menu
        end
    end)

    return btn
end

function sfui.common.create_panel(parent, width, height)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetSize(width, height)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    panel:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    panel:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    return panel
end

function sfui.common.create_label(parent, text, font, r, g, b)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    label:SetText(text)
    if r and g and b then
        label:SetTextColor(r, g, b)
    else
        label:SetTextColor(1, 1, 1)
    end
    label:SetShadowOffset(0, 0)
    return label
end

function sfui.common.get_short_string(name)
    if not name then return "" end

    local overrides = sfui.portals_db and sfui.portals_db.SHORT_STRINGS or {}

    if overrides[name] then return overrides[name] end

    local abbrev = ""
    for word in name:gmatch("%a+") do
        if word:upper() ~= "OF" and word:upper() ~= "THE" then
            local first = word:sub(1, 1)
            if first == first:upper() then
                abbrev = abbrev .. first
            end
        end
    end
    if abbrev:len() > 0 and abbrev:len() <= 4 then return abbrev end

    return name:sub(1, 4):upper()
end

function sfui.common.get_short_map_name(mapID)
    if not mapID then return nil end
    local name = C_ChallengeMode.GetMapUIInfo(mapID)
    if not name then return nil end
    return sfui.common.get_short_string(name)
end
