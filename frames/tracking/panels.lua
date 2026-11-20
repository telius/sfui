local addonName, addon = ...
sfui = sfui or {}
sfui.tracking = sfui.tracking or {}
sfui.panels = sfui.panels or {}
sfui.common = sfui.common or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/tracking/panels.lua
--  Cooldown Panels, Tracked Bars DB & Per-Spec Persistence Engine
--
--  Extracted from common.lua to modularize the tracking subsystem.
--  All public APIs remain bound to sfui.common.* for backward compatibility.
-- ══════════════════════════════════════════════════════════════════════════════

local type, ipairs, pairs, tonumber = type, ipairs, pairs, tonumber
local table, math, string = table, math, string
local C_Timer = _G.C_Timer
local C_CooldownViewer = _G.C_CooldownViewer
local C_ClassTalents = _G.C_ClassTalents
local C_SpecializationInfo = _G.C_SpecializationInfo
local Enum = _G.Enum
local wipe = _G.wipe or table.wipe

-- Authoritative specID -> English class filename lookup (covers Classic/Camelot and Retail)
local FALLBACK_SPEC_CLASS_MAP = {
    -- Classic / Camelot base class IDs
    [1482] = "MAGE", [1484] = "DRUID", [1485] = "HUNTER",
    [1486] = "PALADIN", [1487] = "PRIEST", [1488] = "ROGUE",
    [1489] = "SHAMAN", [1490] = "WARLOCK", [1491] = "WARRIOR",
    -- Camelot guardian pseudo-spec
    [14844] = "DRUID",
    -- Retail active spec IDs
    [62] = "MAGE", [63] = "MAGE", [64] = "MAGE",
    [65] = "PALADIN", [66] = "PALADIN", [70] = "PALADIN",
    [71] = "WARRIOR", [72] = "WARRIOR", [73] = "WARRIOR",
    [102] = "DRUID", [103] = "DRUID", [104] = "DRUID", [105] = "DRUID",
    [250] = "DEATHKNIGHT", [251] = "DEATHKNIGHT", [252] = "DEATHKNIGHT",
    [253] = "HUNTER", [254] = "HUNTER", [255] = "HUNTER",
    [256] = "PRIEST", [257] = "PRIEST", [258] = "PRIEST",
    [259] = "ROGUE", [260] = "ROGUE", [261] = "ROGUE",
    [262] = "SHAMAN", [263] = "SHAMAN", [264] = "SHAMAN",
    [265] = "WARLOCK", [266] = "WARLOCK", [267] = "WARLOCK",
    [268] = "MONK", [269] = "MONK", [270] = "MONK",
    [577] = "DEMONHUNTER", [581] = "DEMONHUNTER", [1480] = "DEMONHUNTER",
    [1467] = "EVOKER", [1468] = "EVOKER", [1473] = "EVOKER",
    -- Retail initial/starter spec IDs
    [1444] = "SHAMAN", [1446] = "WARRIOR", [1447] = "DRUID",
    [1448] = "HUNTER", [1449] = "MAGE", [1450] = "MONK",
    [1451] = "PALADIN", [1452] = "PRIEST", [1453] = "ROGUE",
    [1454] = "WARLOCK", [1455] = "DEATHKNIGHT", [1456] = "DEMONHUNTER",
    [1465] = "EVOKER",
}

local function GetClassForSpecID(specID)
    local num = tonumber(specID)
    if not num or num == 0 then return nil end

    local bridge = sfui.talents and sfui.talents.SPEC_BRIDGE
    if bridge then
        local b = bridge[num] or bridge[specID]
        if b and (b.classFile or b.class) then
            return b.classFile or b.class
        end
    end

    if FALLBACK_SPEC_CLASS_MAP[num] then
        return FALLBACK_SPEC_CLASS_MAP[num]
    end

    if num >= 10000 then
        local baseID = math.floor(num / 10)
        if FALLBACK_SPEC_CLASS_MAP[baseID] then
            return FALLBACK_SPEC_CLASS_MAP[baseID]
        end
    end

    local getSpecByID = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfoByID) or _G.GetSpecializationInfoByID
    if getSpecByID then
        local _, _, _, _, _, classFile = getSpecByID(num)
        if type(classFile) == "string" and classFile ~= "" then
            return classFile
        end
    end

    if sfui.common.get_current_spec_id and num == sfui.common.get_current_spec_id() then
        return sfui.common.get_player_class and sfui.common.get_player_class()
    end

    return nil
end
sfui.tracking.get_class_for_spec_id = GetClassForSpecID

sfui.tracking.SPELL_CATEGORY_METADATA = {
    [4] = {
        icon = "Interface/ICONS/INV_POTION_114",
        tooltipTitle = "combat potion",
        tooltipDescription = "use combat potion",
        fallbackItemID = nil,
    },
    [30] = {
        icon = "Interface/ICONS/INV_POTION_54",
        tooltipTitle = "health potion",
        tooltipDescription = "use health potion",
        fallbackItemID = nil,
    },
    [1711] = {
        icon = "Interface/ICONS/Warlock_ Healthstone",
        tooltipTitle = "healthstone",
        fallbackItemID = 5512,
    },
    [2566] = {
        icon = "Interface/ICONS/Warlock_ Bloodstone",
        tooltipTitle = "demonic healthstone",
        fallbackItemID = 224464,
    },
}

-- ────────────────────────────────────────────────────────────────────────────
-- 1. Tracked Bar DB Accessors
-- ────────────────────────────────────────────────────────────────────────────

--- Helper to safely ensure tracked bar DB structure exists.
--- Returns the tracked bar entry for the given cooldownID, or the trackedBarsBySpec table if no ID provided.
--- @param cooldownID number|nil
--- @return table
function sfui.tracking.ensure_tracked_bar_db(cooldownID)
    SfuiDB = SfuiDB or {}
    SfuiDB.trackedBars = SfuiDB.trackedBars or {}

    local specID = sfui.common.get_current_spec_id() or 0
    SfuiDB.trackedBarsBySpec = SfuiDB.trackedBarsBySpec or {}
    local specBars = SfuiDB.trackedBarsBySpec[specID]
    if not specBars then
        specBars = {}
        SfuiDB.trackedBarsBySpec[specID] = specBars
    end

    if cooldownID then
        specBars[cooldownID] = specBars[cooldownID] or {}
        return specBars[cooldownID]
    end
    return specBars
end
sfui.common.ensure_tracked_bar_db = sfui.tracking.ensure_tracked_bar_db

function sfui.tracking.get_tracked_bars()
    return sfui.tracking.ensure_tracked_bar_db()
end
sfui.common.get_tracked_bars = sfui.tracking.get_tracked_bars

-- ────────────────────────────────────────────────────────────────────────────
-- 2. Per-Spec Panel Configuration & Migrations
-- ────────────────────────────────────────────────────────────────────────────

--- One-time migration from old flat array to per-spec structure.
function sfui.tracking.migrate_cooldown_panels_to_spec()
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
sfui.common.migrate_cooldown_panels_to_spec = sfui.tracking.migrate_cooldown_panels_to_spec

-- Shared helper to get categorized CDM entries
local function get_all_cdm_entries()
    local cat0 = {} -- Essential + EquipSlotEssential (trinkets)
    local cat1 = {} -- Utility + SpecAgnosticEssential (potions / healthstones)

    local auraResolver = sfui.isCamelot and sfui.tracking and sfui.tracking.auras or nil
    local entryHelper = sfui.tracking and sfui.tracking.entry

    local function categorize(cooldownID, info)
        if not info then return end
        local isItemCooldown = (info.equipSlot ~= nil or info.spellCategoryID ~= nil or (info.itemID and info.itemID > 0))
        local known = isItemCooldown
            or (auraResolver and auraResolver.IsCooldownItemKnown and auraResolver.IsCooldownItemKnown(info, cooldownID))
            or info.isKnown
        if not known then return end

        local entry = {
            type = isItemCooldown and "item" or "cooldown",
            cooldownID = cooldownID,
            spellID = info.spellID,
            itemID = info.itemID,
            equipSlot = info.equipSlot,
            spellCategoryID = info.spellCategoryID,
            id = info.spellID or info.itemID or cooldownID,
            settings = { showText = true }
        }
        if entryHelper and entryHelper.NormalizeEntry then
            entryHelper.NormalizeEntry(entry, info)
        end
        local cat = info.category
        if cat == 0 or cat == 7 or not cat then
            table.insert(cat0, entry)
        elseif cat == 1 or cat == 5 then
            table.insert(cat1, entry)
        end
    end

    -- Query C_CooldownViewer direct C API (avoids calling CooldownViewerSettings:GetDataProvider()
    -- methods which invoke CheckBuildDisplayData() and taint CooldownViewerLayoutManager)
    if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet then
        local cats = {}
        local catEnum = Enum and Enum.CooldownViewerCategory
        if catEnum then
            for _, catKey in ipairs({ "Essential", "Utility", "EquipSlotEssential", "SpecAgnosticEssential" }) do
                local val = catEnum[catKey]
                if type(val) == "number" and val >= 0 then
                    table.insert(cats, val)
                end
            end
        end
        if #cats == 0 then
            cats = { 0, 1 }
        end
        for _, cat in ipairs(cats) do
            local cooldownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true)
            if cooldownIDs then
                for _, cooldownID in ipairs(cooldownIDs) do
                    if not (sfui.common.issecretvalue and sfui.common.issecretvalue(cooldownID)) then
                        categorize(cooldownID, C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID))
                    end
                end
            end
        end
    end

    return cat0, cat1
end

--- Populate CENTER panel with cooldowns from CDM Essential Cooldowns (category 0).
function sfui.tracking.populate_center_panel_from_cdm()
    local cat0, _ = get_all_cdm_entries()
    local entries = {}
    -- CENTER holds 7 max
    for i = 1, math.min(7, #cat0) do
        table.insert(entries, cat0[i])
    end
    return entries
end
sfui.common.populate_center_panel_from_cdm = sfui.tracking.populate_center_panel_from_cdm

--- Populate UTILITY panel with cooldowns from CDM Group 1 (Category 1) + overflow.
function sfui.tracking.populate_utility_panel_from_cdm()
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
sfui.common.populate_utility_panel_from_cdm = sfui.tracking.populate_utility_panel_from_cdm

-- Cached panels reference (invalidated on spec change or panel modification)
local _cachedPanels = nil
local _cachedPanelsSpecID = nil

--- Get panels for current spec (Pure accessor, hot-path safe).
function sfui.tracking.get_cooldown_panels()
    local specID = sfui.common.get_current_spec_id() or 0

    -- Return cached if valid
    if _cachedPanels and _cachedPanelsSpecID == specID and #_cachedPanels > 0 then
        return _cachedPanels
    end

    local playerClass = sfui.common.get_player_class()
    local isClassic = sfui.isCamelot or sfui.isClassic or (sfui.compat and (sfui.compat.is_camelot or sfui.compat.is_classic))
    local needsMigration = not SfuiDB._panelsCrossClassRepairV1
        or ((playerClass == "DRUID" or playerClass == "ROGUE") and not SfuiDB.druidMigrationV7)
        or (playerClass == "ROGUE" and not SfuiDB.rogueStealthMigrationV1)
        or (playerClass == "WARRIOR" and isClassic and not SfuiDB.warriorStanceMigrationV1)

    if not SfuiDB.cooldownPanelsBySpec or not SfuiDB.cooldownPanelsBySpec[specID] or #SfuiDB.cooldownPanelsBySpec[specID] == 0 or needsMigration then
        _cachedPanels = sfui.tracking.ensure_panels_initialized()
    else
        _cachedPanels = SfuiDB.cooldownPanelsBySpec[specID]
    end
    _cachedPanelsSpecID = specID
    return _cachedPanels
end
sfui.common.get_cooldown_panels = sfui.tracking.get_cooldown_panels
sfui.panels.get_cooldown_panels = sfui.tracking.get_cooldown_panels

--- Invalidate panels cache (call when panels are modified).
function sfui.tracking.invalidate_panels_cache()
    _cachedPanels = nil
    _cachedPanelsSpecID = nil
end
sfui.common.invalidate_panels_cache = sfui.tracking.invalidate_panels_cache
sfui.panels.invalidate_panels_cache = sfui.tracking.invalidate_panels_cache

--- Get only the active (available) entries for a panel (reusable destination table support).
function sfui.tracking.get_active_panel_entries(panelConfig, outTable)
    local activeEntries = outTable or {}
    wipe(activeEntries)
    if not panelConfig or type(panelConfig.entries) ~= "table" then return activeEntries end

    local isClassic = not sfui.isRetail
    local auraResolver = sfui.isCamelot and sfui.tracking and sfui.tracking.auras or nil
    local entryHelper = sfui.tracking and sfui.tracking.entry

    for _, entry in ipairs(panelConfig.entries) do
        local isKnown = true
        local typeHint = (type(entry) == "table" and entry.type) or "spell"

        -- ONLY query C_CooldownViewer for entries with an explicit cooldownID or type == "cooldown"
        -- NEVER pass a raw spellID to GetCooldownViewerCooldownInfo!
        if (typeHint == "cooldown" or (type(entry) == "table" and entry.cooldownID)) and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
            local cdID = (type(entry) == "table" and entry.cooldownID) or (type(entry) == "table" and entry.id) or entry
            local cdInfo = (entryHelper and entryHelper.SafeGetCooldownInfo and entryHelper.SafeGetCooldownInfo(cdID))
                or (type(cdID) == "number" and cdID > 0 and C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID))
            if cdInfo then
                local isItemCooldown = (type(entry) == "table" and (entry.equipSlot ~= nil or entry.spellCategoryID ~= nil or (entry.itemID and entry.itemID > 0) or entry.type == "item"))
                    or (cdInfo.equipSlot ~= nil or cdInfo.spellCategoryID ~= nil or (cdInfo.itemID and cdInfo.itemID > 0))

                if sfui.isRetail and not isItemCooldown and (cdInfo.category == 2 or cdInfo.category == 3) then
                    local allowBuff = entryHelper and entryHelper.ShouldTrackBuffs
                        and entryHelper.ShouldTrackBuffs(entry, panelConfig, cdInfo)
                        or false
                    if not allowBuff then
                        isKnown = false
                    end
                end

                if isKnown and not isItemCooldown and cdInfo.isKnown == false then
                    local spellKnown = (auraResolver and auraResolver.IsCooldownItemKnown and auraResolver.IsCooldownItemKnown(cdInfo, cdID)) or false
                    if not spellKnown then
                        local sID = (type(entry) == "table" and entry.spellID) or (cdInfo.spellID and cdInfo.spellID > 0 and cdInfo.spellID)
                        if sID then
                            spellKnown = (_G.IsPlayerSpell and _G.IsPlayerSpell(sID)) or (_G.C_SpellBook and _G.C_SpellBook.HasSpell and _G.C_SpellBook.HasSpell(sID)) or false
                        end
                    end
                    if not spellKnown then
                        isKnown = false
                    end
                end
            end
        end

        -- Hero Talent Filter logic (Only evaluated on Retail)
        if not isClassic and isKnown and type(entry) == "table" and entry.settings then
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
sfui.common.get_active_panel_entries = sfui.tracking.get_active_panel_entries
sfui.panels.get_active_panel_entries = sfui.tracking.get_active_panel_entries

local LAYOUT_INHERIT_KEYS = {
    "customMover", "moverPoint", "moverRelPoint",
    "anchorTo", "anchorPoint", "relativePoint",
    "x", "y", "size", "spacing", "columns",
    "growthH", "growthV", "spanWidth",
    "showBackground", "backgroundAlpha",
    "hideOOC", "hideMounted", "hideInVehicle",
}

local function MergePanelEntries(dstPanel, srcPanel)
    if not dstPanel or not srcPanel or type(srcPanel.entries) ~= "table" or #srcPanel.entries == 0 then
        return false
    end
    dstPanel.entries = dstPanel.entries or {}
    local seen = {}
    for _, existing in ipairs(dstPanel.entries) do
        local eid = (type(existing) == "table" and (existing.cooldownID or existing.id)) or existing
        if eid ~= nil then seen[eid] = true end
    end
    local added = false
    for _, incoming in ipairs(srcPanel.entries) do
        local iid = (type(incoming) == "table" and (incoming.cooldownID or incoming.id)) or incoming
        if iid == nil or not seen[iid] then
            if iid ~= nil then seen[iid] = true end
            table.insert(dstPanel.entries, incoming)
            added = true
        end
    end
    return added
end

local function RestorePanelDefaultPosition(panel, def)
    if not panel or not def then return end
    panel.customMover = nil
    panel.moverPoint = nil
    panel.moverRelPoint = nil
    panel.relativePoint = nil
    panel.anchorTo = def.anchorTo
    panel.anchorPoint = def.anchorPoint
    panel.x = def.x
    panel.y = def.y
end

local function RepairCrossClassPanels()
    local upper = string.upper
    local defs = sfui.config and sfui.config.cooldown_panel_defaults
    local anyChanged = false

    -- Detect legacy numeric layout keys (trackedicons_1..N) before pruning them
    local hadLegacyNumericLayout = false
    if type(SfuiDB.layoutProfiles) == "table" then
        for _, prof in pairs(SfuiDB.layoutProfiles) do
            if type(prof) == "table" and type(prof.positions) == "table" then
                local toDelete
                for k in pairs(prof.positions) do
                    if type(k) == "string" and k:match("^trackedicons_%d+$") then
                        hadLegacyNumericLayout = true
                        toDelete = toDelete or {}
                        toDelete[#toDelete + 1] = k
                    end
                end
                if toDelete then
                    for _, k in ipairs(toDelete) do
                        prof.positions[k] = nil
                    end
                    anyChanged = true
                end
            end
        end
    end

    -- Repair each spec's cooldown panels using its own spec class
    if type(SfuiDB.cooldownPanelsBySpec) == "table" then
        for sID, specPanels in pairs(SfuiDB.cooldownPanelsBySpec) do
            local specClass = GetClassForSpecID(sID)
            if type(specPanels) == "table" and specClass then
                local primaryPanel
                for _, p in ipairs(specPanels) do
                    local uName = p and p.name and upper(p.name)
                    if uName == "CENTER" then
                        primaryPanel = p
                        break
                    elseif uName == "BATTLE" and not primaryPanel then
                        primaryPanel = p
                    end
                end

                local removedCount = 0
                for i = #specPanels, 1, -1 do
                    local p = specPanels[i]
                    local uName = p and p.name and upper(p.name)
                    local shouldRemove = false

                    if specClass ~= "WARRIOR" then
                        if uName == "BATTLE" then
                            p.name = "CENTER"
                            uName = "CENTER"
                            anyChanged = true
                        end
                        if uName == "CENTER" then
                            if specClass == "DRUID" or specClass == "ROGUE" then
                                if p.requiredForm == nil or p.requiredForm == 1 then
                                    p.requiredForm = 0
                                    anyChanged = true
                                end
                            elseif p.requiredForm ~= nil then
                                p.requiredForm = nil
                                anyChanged = true
                            end
                        elseif uName == "DEFENSIVE" or uName == "BERSERKER" then
                            shouldRemove = true
                        end
                    end

                    if not shouldRemove and specClass ~= "ROGUE" and specClass ~= "DRUID" and uName == "STEALTH" then
                        shouldRemove = true
                    end

                    if shouldRemove then
                        if primaryPanel and primaryPanel ~= p then
                            MergePanelEntries(primaryPanel, p)
                        end
                        table.remove(specPanels, i)
                        removedCount = removedCount + 1
                        anyChanged = true
                    end
                end

                -- Heal UTILITY/Left/Right coordinates scrambled by index-shifted layout sync
                if removedCount > 0 and hadLegacyNumericLayout and defs then
                    local defaultMap = {
                        UTILITY = defs.utility,
                        LEFT    = defs.left,
                        RIGHT   = defs.right,
                    }
                    for _, p in ipairs(specPanels) do
                        local uName = p and p.name and upper(p.name)
                        local def = uName and defaultMap[uName]
                        if def and p.customMover == true then
                            RestorePanelDefaultPosition(p, def)
                            anyChanged = true
                        end
                    end
                end
            end
        end
    end

    -- Clean stray anchor keys accidentally written into SfuiDB.trackedBarsBySpec by old mover bug
    if type(SfuiDB.trackedBarsBySpec) == "table" then
        for _, specBars in pairs(SfuiDB.trackedBarsBySpec) do
            if type(specBars) == "table" and specBars.anchor ~= nil then
                local stray = specBars.anchor
                SfuiDB.trackedBars = SfuiDB.trackedBars or {}
                if type(stray) == "table" then
                    SfuiDB.trackedBars.anchor = SfuiDB.trackedBars.anchor or {}
                    local dst = SfuiDB.trackedBars.anchor
                    if not dst.point and stray.point then dst.point = stray.point end
                    if not dst.relPoint and stray.relPoint then dst.relPoint = stray.relPoint end
                    if dst.x == nil and stray.x ~= nil then dst.x = stray.x end
                    if dst.y == nil and stray.y ~= nil then dst.y = stray.y end
                end
                specBars.anchor = nil
                anyChanged = true
            end
        end
    end

    SfuiDB._panelsCrossClassRepairV1 = true
    return anyChanged
end

local function BuildDonorLookup(panelsList)
    local byName = {}
    local primary
    local upper = string.upper
    for _, p in ipairs(panelsList) do
        local uName = p and p.name and upper(p.name)
        if uName then
            if not byName[uName] then
                byName[uName] = p
            end
            if not primary and (uName == "CENTER" or uName == "BATTLE") then
                primary = p
            end
        end
    end
    return byName, primary
end

local function FindSameClassLayoutDonor(targetSpecID, playerClass)
    if not playerClass or type(SfuiDB.cooldownPanelsBySpec) ~= "table" then return nil, nil end
    local bestPanels, bestScore, bestSID = nil, -1, -1
    for sID, otherPanels in pairs(SfuiDB.cooldownPanelsBySpec) do
        local numSID = tonumber(sID) or 0
        if numSID ~= targetSpecID and type(otherPanels) == "table" and #otherPanels > 0 and GetClassForSpecID(sID) == playerClass then
            local score = (numSID >= 10000) and 10 or 0
            for _, p in ipairs(otherPanels) do
                if p.customMover then
                    score = score + 100
                    break
                end
            end
            if score > bestScore or (score == bestScore and numSID > bestSID) then
                bestScore = score
                bestSID = numSID
                bestPanels = otherPanels
            end
        end
    end
    if not bestPanels then return nil, nil end
    return BuildDonorLookup(bestPanels)
end

local function CopyInheritedPanelLayout(newPanel, spec, donorByName, donorPrimary)
    if not donorByName and not donorPrimary then return end
    local upper = string.upper
    local uSpecName = upper(spec.name)
    local donor = donorByName and donorByName[uSpecName]
    local isExactDonor = (donor ~= nil)
    if not donor and spec.key == "center_panel" then
        donor = donorPrimary
    end
    if not donor then return end

    for _, k in ipairs(LAYOUT_INHERIT_KEYS) do
        if k == "hideOOC" and uSpecName == "STEALTH" and not isExactDonor then
            -- Keep stealth panel's default out-of-combat visibility unless copying another STEALTH panel
        elseif donor[k] ~= nil then
            newPanel[k] = donor[k]
        end
    end
end

--- Ensure panels exist and are populated (Called once on load/spec/talent change).
function sfui.tracking.ensure_panels_initialized()
    local specID = sfui.common.get_current_spec_id() or 0
    if specID == 0 and sfui.common.update_cached_spec_id then
        sfui.common.update_cached_spec_id()
        specID = sfui.common.get_current_spec_id() or 0
    end
    if specID == 0 then
        -- Spec not yet determined (early load before player entity exists), return empty without corrupting
        return {}
    end

    local playerClass = sfui.common.get_player_class()
    local isClassic = sfui.isCamelot or sfui.isClassic or (sfui.compat and (sfui.compat.is_camelot or sfui.compat.is_classic))

    SfuiDB.cooldownPanelsBySpec = SfuiDB.cooldownPanelsBySpec or {}

    -- Clean up legacy/accidental spec 0 panels if real spec is now known
    if SfuiDB.cooldownPanelsBySpec[0] then
        if not SfuiDB.cooldownPanelsBySpec[specID] or #SfuiDB.cooldownPanelsBySpec[specID] == 0 then
            SfuiDB.cooldownPanelsBySpec[specID] = SfuiDB.cooldownPanelsBySpec[0]
        end
        SfuiDB.cooldownPanelsBySpec[0] = nil
    end

    SfuiDB.cooldownPanelsBySpec[specID] = SfuiDB.cooldownPanelsBySpec[specID] or {}

    local changed = false
    if not SfuiDB._panelsCrossClassRepairV1 then
        if RepairCrossClassPanels() then
            changed = true
        end
    end

    local panels = SfuiDB.cooldownPanelsBySpec[specID]
    local isNewSpecBucket = (#panels == 0)
    local donorByName, donorPrimary
    if isNewSpecBucket then
        donorByName, donorPrimary = FindSameClassLayoutDonor(specID, playerClass)
    end

    SfuiDB.iconsInitializedBySpec = SfuiDB.iconsInitializedBySpec or {}

    local defaultPanelSpecs = {
        { key = "center_panel", name = "CENTER",  populateFunc = sfui.tracking.populate_center_panel_from_cdm },
        { key = "utility",      name = "UTILITY", populateFunc = sfui.tracking.populate_utility_panel_from_cdm },
        { key = "left",         name = "Left" },
        { key = "right",        name = "Right" },
    }

    if playerClass == "DRUID" or playerClass == "ROGUE" then
        -- Inject druid/rogue specific default forms immediately after the base CENTER panel (index 1)
        defaultPanelSpecs[1].requiredForm = 0
    elseif playerClass == "WARRIOR" and isClassic then
        defaultPanelSpecs[1].name = "BATTLE"
        defaultPanelSpecs[1].requiredForm = 1
    end

    if playerClass == "DRUID" then
        table.insert(defaultPanelSpecs, 2, { key = "center_panel", name = "CAT", requiredForm = 1 })
        table.insert(defaultPanelSpecs, 3, { key = "center_panel", name = "BEAR", requiredForm = 5 })
        table.insert(defaultPanelSpecs, 4, { key = "center_panel", name = "MOONKIN", requiredForm = { 31, 35 } })
        table.insert(defaultPanelSpecs, 5, { key = "center_panel", name = "STEALTH", requiredForm = "stealth" })
    elseif playerClass == "ROGUE" then
        table.insert(defaultPanelSpecs, 2, { key = "center_panel", name = "STEALTH", requiredForm = "stealth" })
    elseif playerClass == "WARRIOR" and isClassic then
        table.insert(defaultPanelSpecs, 2, { key = "center_panel", name = "DEFENSIVE", requiredForm = 2 })
        table.insert(defaultPanelSpecs, 3, { key = "center_panel", name = "BERSERKER", requiredForm = 3 })
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
                -- Also match if the database name is "CENTER" but we are looking for "BATTLE" (and vice versa)
            elseif (uPanelName == "CENTER" and uSpecName == "BATTLE") or (uPanelName == "BATTLE" and uSpecName == "CENTER") then
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
            if spec.name == "STEALTH" then
                newPanel.hideOOC = false
            end
            newPanel.name = spec.name
            newPanel.specID = specID

            if isNewSpecBucket then
                CopyInheritedPanelLayout(newPanel, spec, donorByName, donorPrimary)
            end

            -- Position center form variants right after the base CENTER panel or preceding form variants
            local insertPos = nil
            if spec.key == "center_panel" and spec.name ~= "CENTER" and spec.name ~= "BATTLE" then
                for idx = #panels, 1, -1 do
                    local p = panels[idx]
                    local u = p and p.name and string.upper(p.name)
                    if u == "CENTER" or u == "BATTLE" or u == "DEFENSIVE" or u == "BERSERKER" or u == "CAT" or u == "BEAR" or u == "MOONKIN" or u == "STEALTH" then
                        insertPos = idx + 1
                        break
                    end
                end
            end

            if insertPos and insertPos <= #panels then
                table.insert(panels, insertPos, newPanel)
            else
                table.insert(panels, newPanel)
            end

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
            if not panel.entries then
                panel.entries = {}
            end
            if not SfuiDB.iconsInitializedBySpec[specID] and spec.populateFunc and #panel.entries == 0 then
                local populated = spec.populateFunc()
                if populated and #populated > 0 then
                    panel.entries = populated
                    changed = true
                end
            end
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

    -- Rogue stealth panel migration across all specs
    if playerClass == "ROGUE" and not SfuiDB.rogueStealthMigrationV1 then
        if SfuiDB.cooldownPanelsBySpec then
            local upper = string.upper
            for sID, specPanels in pairs(SfuiDB.cooldownPanelsBySpec) do
                if type(specPanels) == "table" and GetClassForSpecID(sID) == "ROGUE" then
                    local hasStealth = false
                    local centerIdx = nil
                    for idx, p in ipairs(specPanels) do
                        local uname = p.name and upper(p.name)
                        if uname == "CENTER" then
                            centerIdx = idx
                            if p.requiredForm == nil then
                                p.requiredForm = 0
                                changed = true
                            end
                        elseif uname == "STEALTH" then
                            hasStealth = true
                            if p.requiredForm ~= "stealth" then
                                p.requiredForm = "stealth"
                                changed = true
                            end
                        end
                    end

                    if not hasStealth then
                        local stealthPanel = sfui.common.copy(sfui.config.cooldown_panel_defaults.center_panel)
                        stealthPanel.name = "STEALTH"
                        stealthPanel.requiredForm = "stealth"
                        stealthPanel.entries = {}
                        stealthPanel.hideOOC = false
                        stealthPanel.specID = tonumber(sID) or specID
                        if centerIdx and centerIdx < #specPanels then
                            table.insert(specPanels, centerIdx + 1, stealthPanel)
                        else
                            table.insert(specPanels, stealthPanel)
                        end
                        changed = true
                    end
                end
            end
        end
        SfuiDB.rogueStealthMigrationV1 = true
    end

    -- Warrior stance panel migration across warrior specs
    if playerClass == "WARRIOR" and not SfuiDB.warriorStanceMigrationV1 then
        if isClassic and SfuiDB.cooldownPanelsBySpec then
            local upper = string.upper
            for sID, specPanels in pairs(SfuiDB.cooldownPanelsBySpec) do
                if type(specPanels) == "table" and GetClassForSpecID(sID) == "WARRIOR" then
                    local hasDefensive = false
                    local hasBerserker = false
                    local centerIdx = nil

                    for idx, p in ipairs(specPanels) do
                        local uname = p.name and upper(p.name)
                        if uname == "CENTER" or uname == "BATTLE" then
                            centerIdx = idx
                            p.name = "BATTLE"
                            if p.requiredForm == nil then
                                p.requiredForm = 1
                                changed = true
                            end
                        elseif uname == "DEFENSIVE" then
                            hasDefensive = true
                            if p.requiredForm ~= 2 then
                                p.requiredForm = 2
                                changed = true
                            end
                        elseif uname == "BERSERKER" then
                            hasBerserker = true
                            if p.requiredForm ~= 3 then
                                p.requiredForm = 3
                                changed = true
                            end
                        end
                    end

                    if not hasDefensive then
                        local defPanel = sfui.common.copy(sfui.config.cooldown_panel_defaults.center_panel)
                        defPanel.name = "DEFENSIVE"
                        defPanel.requiredForm = 2
                        defPanel.entries = {}
                        defPanel.specID = tonumber(sID) or specID
                        if centerIdx and centerIdx < #specPanels then
                            table.insert(specPanels, centerIdx + 1, defPanel)
                            centerIdx = centerIdx + 1
                        else
                            table.insert(specPanels, defPanel)
                            centerIdx = #specPanels
                        end
                        changed = true
                    end

                    if not hasBerserker then
                        local zerkPanel = sfui.common.copy(sfui.config.cooldown_panel_defaults.center_panel)
                        zerkPanel.name = "BERSERKER"
                        zerkPanel.requiredForm = 3
                        zerkPanel.entries = {}
                        zerkPanel.specID = tonumber(sID) or specID
                        if centerIdx and centerIdx < #specPanels then
                            table.insert(specPanels, centerIdx + 1, zerkPanel)
                        else
                            table.insert(specPanels, zerkPanel)
                        end
                        changed = true
                    end
                end
            end
        end
        SfuiDB.warriorStanceMigrationV1 = true
    end

    -- One-time migration for center panel defaults (hideOOC, hideInVehicle, hideMounted, spanWidth)
    if not SfuiDB.centerDefaultsV2 then
        if SfuiDB.cooldownPanelsBySpec then
            for _, specPanels in pairs(SfuiDB.cooldownPanelsBySpec) do
                if type(specPanels) == "table" then
                    for _, p in ipairs(specPanels) do
                        local uname = p.name and string.upper(p.name)
                        if uname == "CENTER" or uname == "CAT" or uname == "BEAR" or uname == "MOONKIN" or uname == "STEALTH"
                            or uname == "BATTLE" or uname == "DEFENSIVE" or uname == "BERSERKER" then
                            if p.hideOOC == nil then p.hideOOC = true; changed = true end
                            if p.hideInVehicle == nil then p.hideInVehicle = true; changed = true end
                            if p.hideMounted == nil then p.hideMounted = true; changed = true end
                            if p.spanWidth == nil then p.spanWidth = true; changed = true end
                        end
                    end
                end
            end
        end
        SfuiDB.centerDefaultsV2 = true
    end

    -- One-time migration for utility panel defaults (hideOOC, hideInVehicle, hideMounted)
    if not SfuiDB.utilityDefaultsV1 then
        if SfuiDB.cooldownPanelsBySpec then
            for _, specPanels in pairs(SfuiDB.cooldownPanelsBySpec) do
                if type(specPanels) == "table" then
                    for _, p in ipairs(specPanels) do
                        local uname = p.name and string.upper(p.name)
                        if uname == "UTILITY" then
                            if p.hideOOC == nil then p.hideOOC = true; changed = true end
                            if p.hideInVehicle == nil then p.hideInVehicle = true; changed = true end
                            if p.hideMounted == nil then p.hideMounted = true; changed = true end
                        end
                    end
                end
            end
        end
        SfuiDB.utilityDefaultsV1 = true
    end

    -- Cleanup duplicates for the exact target names (case-insensitive)
    -- Crucial: Prefer panels that have user-configured entries, and preserve the first panel
    local seenUpperPanels = {}
    local toRemove = {}
    local upper = string.upper
    local builtins = {
        CENTER = true,
        UTILITY = true,
        LEFT = true,
        RIGHT = true,
        CAT = true,
        BEAR = true,
        MOONKIN = true,
        STEALTH = true,
        BATTLE = true,
        DEFENSIVE = true,
        BERSERKER = true,
    }

    for i = 1, #panels do
        local p = panels[i]
        local pName = p and p.name
        if pName then
            local uName = upper(pName)
            if uName == "BUFFS" then
                toRemove[i] = true
            elseif builtins[uName] then
                local existingIdx = seenUpperPanels[uName]
                if existingIdx then
                    local existingPanel = panels[existingIdx]
                    local existingHasEntries = existingPanel and existingPanel.entries and #existingPanel.entries > 0
                    local currentHasEntries = p.entries and #p.entries > 0

                    if currentHasEntries and not existingHasEntries then
                        toRemove[existingIdx] = true
                        seenUpperPanels[uName] = i
                    else
                        toRemove[i] = true
                    end
                else
                    seenUpperPanels[uName] = i
                end
            end
        end
    end

    for i = #panels, 1, -1 do
        if toRemove[i] then
            table.remove(panels, i)
            changed = true
        end
    end

    local usesCdm = (sfui.isRetail or sfui.isCamelot) == true and C_CooldownViewer ~= nil
    if not SfuiDB.iconsInitializedBySpec[specID] then
        local gotAnyCdmEntries = not usesCdm
        if usesCdm then
            for _, panel in ipairs(panels) do
                local uname = panel.name and upper(panel.name)
                if (uname == "CENTER" or uname == "BATTLE" or uname == "UTILITY") and panel.entries and #panel.entries > 0 then
                    gotAnyCdmEntries = true
                    break
                end
            end
        end

        SfuiDB._populationRetrySpecs = SfuiDB._populationRetrySpecs or {}
        if gotAnyCdmEntries or SfuiDB._populationRetrySpecs[specID] then
            SfuiDB.iconsInitializedBySpec[specID] = true
            if migratedEntries then SfuiDB.trackedIcons = nil end -- Clear global migration source once first spec consumes it
            changed = true
        else
            -- CDM data was not ready yet on early login: arm one-shot retry without locking spec as empty
            if migratedEntries then SfuiDB.trackedIcons = nil end
            if not sfui.tracking._pendingPanelRetries then
                sfui.tracking._pendingPanelRetries = {}
            end
            if not sfui.tracking._pendingPanelRetries[specID] then
                sfui.tracking._pendingPanelRetries[specID] = true
                local function retryPopulate()
                    if not sfui.tracking._pendingPanelRetries[specID] then return end
                    sfui.tracking._pendingPanelRetries[specID] = nil
                    if SfuiDB then
                        SfuiDB._populationRetrySpecs = SfuiDB._populationRetrySpecs or {}
                        SfuiDB._populationRetrySpecs[specID] = true
                    end
                    sfui.tracking.ensure_panels_initialized()
                    if sfui.trackedicons and sfui.trackedicons.Update then
                        sfui.trackedicons.Update()
                    end
                end
                if sfui.events and sfui.events.RegisterEvent then
                    local cb
                    cb = function()
                        if sfui.events.UnregisterEvent then
                            sfui.events.UnregisterEvent("COOLDOWN_VIEWER_DATA_LOADED", cb)
                        end
                        retryPopulate()
                    end
                    sfui.events.RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED", cb)
                end
                if C_Timer and C_Timer.After then
                    C_Timer.After(2, retryPopulate)
                end
            end
        end
    end

    if changed then
        sfui.tracking.set_cooldown_panels(panels)
    end

    return panels
end
sfui.common.ensure_panels_initialized = sfui.tracking.ensure_panels_initialized
sfui.panels.ensure_panels_initialized = sfui.tracking.ensure_panels_initialized

--- Add a new custom icon panel.
--- @param name string
--- @return number|nil index
function sfui.tracking.add_custom_panel(name)
    if not name or name == "" then return end
    local panels = sfui.tracking.get_cooldown_panels()

    -- Prevent creating duplicate builtin panels
    if name == "CENTER" or name == "UTILITY" or name == "Left" or name == "Right" or name == "CAT" or name == "BEAR" or name == "MOONKIN" or name == "STEALTH"
        or name == "BATTLE" or name == "DEFENSIVE" or name == "BERSERKER" then
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
sfui.common.add_custom_panel = sfui.tracking.add_custom_panel
sfui.panels.add_custom_panel = sfui.tracking.add_custom_panel

--- Delete a custom icon panel by index.
--- @param index number
--- @return boolean
function sfui.tracking.delete_custom_panel(index)
    local panels = sfui.tracking.get_cooldown_panels()
    if panels[index] then
        table.remove(panels, index)
        return true
    end
    return false
end
sfui.common.delete_custom_panel = sfui.tracking.delete_custom_panel
sfui.panels.delete_custom_panel = sfui.tracking.delete_custom_panel

--- Set panels for current spec.
--- @param panels table
function sfui.tracking.set_cooldown_panels(panels)
    local specID = sfui.common.get_current_spec_id()
    if not specID or specID == 0 then return end

    SfuiDB.cooldownPanelsBySpec = SfuiDB.cooldownPanelsBySpec or {}
    SfuiDB.cooldownPanelsBySpec[specID] = panels
    sfui.tracking.invalidate_panels_cache()
end
sfui.common.set_cooldown_panels = sfui.tracking.set_cooldown_panels
sfui.panels.set_cooldown_panels = sfui.tracking.set_cooldown_panels

--- Get all available anchor targets for icon panels.
--- @param excludeName string|nil
--- @return table
function sfui.tracking.get_all_anchor_targets(excludeName)
    local targets = {
        { text = "Screen (UIParent)", value = "UIParent" },
        { text = "Health Bar",        value = "Health Bar" },
        { text = "Tracked Bars",      value = "Tracked Bars" },
    }
    if not sfui.isRetail and sfui.swing and sfui.swing.IsPossible() then
        table.insert(targets, 3, { text = "Swing Bar", value = "Swing Bar" })
    end

    -- Add all panels as potential targets
    local panels = sfui.tracking.get_cooldown_panels()
    if panels then
        for _, p in ipairs(panels) do
            if p.name and p.name ~= excludeName then
                table.insert(targets, { text = "Panel: " .. p.name, value = p.name })
            end
        end
    end

    return targets
end
sfui.common.get_all_anchor_targets = sfui.tracking.get_all_anchor_targets
sfui.panels.get_all_anchor_targets = sfui.tracking.get_all_anchor_targets

--- Get panel at index for current spec.
--- @param index number
--- @return table|nil
function sfui.tracking.get_cooldown_panel(index)
    local panels = sfui.tracking.get_cooldown_panels()
    return panels[index]
end
sfui.common.get_cooldown_panel = sfui.tracking.get_cooldown_panel
sfui.panels.get_cooldown_panel = sfui.tracking.get_cooldown_panel

--- Backwards compatibility wrapper - returns per-spec panels.
function sfui.tracking.ensure_tracked_icon_db()
    return sfui.tracking.get_cooldown_panels()
end
sfui.common.ensure_tracked_icon_db = sfui.tracking.ensure_tracked_icon_db
sfui.panels.ensure_tracked_icon_db = sfui.tracking.ensure_tracked_icon_db
