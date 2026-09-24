local addonName, addon = ...
sfui = sfui or {}
sfui.common = sfui.common or {}

function sfui.common.print(msg, ...)
    if sfui.config and sfui.config.prefix then
        print(sfui.config.prefix .. " " .. tostring(msg), ...)
    else
        print("|cff6600ffsfui:|r " .. tostring(msg), ...)
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- Domain Services Note:
-- Safety, Colors, Talents, and Items have been extracted to /core:
--   sfui/core/safety.lua  (sfui.safety  -> sfui.common)
--   sfui/core/colors.lua  (sfui.colors  -> sfui.common)
--   sfui/core/talents.lua (sfui.talents -> sfui.common)
--   sfui/core/items.lua   (sfui.items   -> sfui.common)
-- All public APIs remain accessible via sfui.common.* for backward compatibility.
-- ────────────────────────────────────────────────────────────────────────────

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

--- Checks if a spell is a known class buff/aura pattern or currently active on the player.
--- @param spellIDOrName number|string
--- @return boolean isAura, string|nil spellName
function sfui.common.is_known_aura_spell(spellIDOrName)
    if not spellIDOrName then return false end
    if type(spellIDOrName) == "number" and sfui.api and sfui.api.IsKnownAuraSpellID and sfui.api.IsKnownAuraSpellID(spellIDOrName) then
        return true, sfui.common.get_spell_name(spellIDOrName)
    end
    local name = type(spellIDOrName) == "string" and spellIDOrName or sfui.common.get_spell_name(spellIDOrName)
    if not name or name == "" then return false end

    if sfui.spells_db and sfui.spells_db.MatchesAuraPattern and sfui.spells_db.MatchesAuraPattern(name) then
        return true, name
    end

    -- Dynamic check: is it already active on the player?
    if sfui.api and sfui.api.GetUnitAuraByNameOrID then
        local aura = sfui.api.GetUnitAuraByNameOrID("player", name)
        if aura then
            return true, name
        end
    end

    return false, name
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

    local isClassic = (sfui.compat and (sfui.compat.has.wow_forever or sfui.compat.is_classic_era or sfui.compat.is_classic))
        or (sfui.version and (sfui.version.classic_era or sfui.version.wow_forever or not sfui.version.retail))
        or not (sfui.compat and sfui.compat.has and sfui.compat.has.specializations)

    for _, entry in ipairs(panelConfig.entries) do
        local isKnown = true
        local typeHint = (type(entry) == "table" and entry.type) or "spell"

        -- ONLY query C_CooldownViewer for entries with an explicit cooldownID or type == "cooldown"
        -- NEVER pass a raw spellID to GetCooldownViewerCooldownInfo!
        if (typeHint == "cooldown" or (type(entry) == "table" and entry.cooldownID)) and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
            local cdID = (type(entry) == "table" and entry.cooldownID) or (type(entry) == "table" and entry.id) or entry
            local ok, cdInfo = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
            if ok and cdInfo and cdInfo.isKnown == false then
                local spellKnown = false
                local sID = (type(entry) == "table" and entry.spellID) or (cdInfo.spellID and cdInfo.spellID > 0 and cdInfo.spellID)
                if sID then
                    spellKnown = (_G.IsPlayerSpell and _G.IsPlayerSpell(sID)) or (_G.C_SpellBook and _G.C_SpellBook.HasSpell and _G.C_SpellBook.HasSpell(sID)) or false
                end
                if not spellKnown then
                    isKnown = false
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

-- Ensure panels exist and are populated (Called once on load/spec/talent change)
function sfui.common.ensure_panels_initialized()
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

    SfuiDB.cooldownPanelsBySpec = SfuiDB.cooldownPanelsBySpec or {}

    -- Clean up legacy/accidental spec 0 panels if real spec is now known
    if SfuiDB.cooldownPanelsBySpec[0] then
        if not SfuiDB.cooldownPanelsBySpec[specID] or #SfuiDB.cooldownPanelsBySpec[specID] == 0 then
            SfuiDB.cooldownPanelsBySpec[specID] = SfuiDB.cooldownPanelsBySpec[0]
        end
        SfuiDB.cooldownPanelsBySpec[0] = nil
    end

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
            if not panel.entries then
                panel.entries = {}
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
        STEALTH = true
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

    if not SfuiDB.iconsInitializedBySpec[specID] then
        SfuiDB.iconsInitializedBySpec[specID] = true
        if migratedEntries then SfuiDB.trackedIcons = nil end -- Clear global migration source once first spec consumes it
        changed = true
    end

    if changed then
        sfui.common.set_cooldown_panels(panels)
    else
        -- If no entries were found but population was expected, retry once after a short delay
        -- This handles the race condition on fresh installations/characters on Retail
        local isClassic = (sfui.compat and (sfui.compat.has.wow_forever or sfui.compat.is_classic_era or sfui.compat.is_classic))
            or (sfui.version and (sfui.version.classic_era or sfui.version.wow_forever or not sfui.version.retail))
            or not (sfui.compat and sfui.compat.has and sfui.compat.has.specializations)

        if not isClassic and not SfuiDB._populationRetryDone then
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
    if sfui.swing and sfui.swing.IsPossible and sfui.swing.IsPossible() then
        table.insert(targets, 3, { text = "Swing Bar", value = "Swing Bar" })
    end

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
    DRUID = { [0] = Enum.PowerType.Mana, [1] = Enum.PowerType.Energy, [5] = Enum.PowerType.Rage, [27] = Enum.PowerType.Mana, [31] = Enum.PowerType.LunarPower, [35] = Enum.PowerType.LunarPower, [1484] = Enum.PowerType.Mana },
    EVOKER = Enum.PowerType.Mana,
    HUNTER = Enum.PowerType.Focus,
    MAGE = Enum.PowerType.Mana,
    MONK = { [0] = Enum.PowerType.Energy, [268] = Enum.PowerType.Energy, [269] = Enum.PowerType.Energy, [270] = Enum.PowerType.Mana },
    PALADIN = Enum.PowerType.Mana,
    PRIEST = { [0] = Enum.PowerType.Mana, [256] = Enum.PowerType.Mana, [257] = Enum.PowerType.Mana, [258] = Enum.PowerType.Insanity, [1487] = Enum.PowerType.Mana },
    ROGUE = Enum.PowerType.Energy,
    SHAMAN = { [0] = Enum.PowerType.Mana, [262] = Enum.PowerType.Maelstrom, [263] = Enum.PowerType.Mana, [264] = Enum.PowerType.Mana, [1489] = Enum.PowerType.Mana },
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

    local isClassic = (sfui.compat and (sfui.compat.has.wow_forever or sfui.compat.is_classic_era or sfui.compat.is_classic))
        or (sfui.version and (sfui.version.classic_era or sfui.version.wow_forever or not sfui.version.retail))

    if isClassic then
        if pClass == "HUNTER" then
            return Enum.PowerType.Mana or 0
        end
        if UnitPowerType then
            local uType = UnitPowerType("player")
            if uType ~= nil then
                return uType
            end
        end
    end

    if pClass == "DRUID" then
        local form = GetShapeshiftFormID and GetShapeshiftFormID() or 0
        local druidCache = primaryResourcesCache[pClass]
        local res = druidCache and druidCache[form]
        if res ~= nil then return res end
        if UnitPowerType then
            return UnitPowerType("player")
        end
        return Enum.PowerType.Mana or 0
    end

    local cache = primaryResourcesCache[pClass]
    local res
    if type(cache) == "table" then
        local specID = sfui.common.get_current_spec_id()
        res = cache[specID]
        if res == nil and cache[0] ~= nil then
            res = cache[0]
        end
    else
        res = cache
    end

    if res == nil and UnitPowerType then
        res = UnitPowerType("player")
    end

    return res or Enum.PowerType.Mana or 0
end

function sfui.common.get_secondary_resource()
    local pClass = sfui.common.get_player_class()
    if not pClass then return nil end

    local isClassic = (sfui.compat and (sfui.compat.has.wow_forever or sfui.compat.is_classic_era or sfui.compat.is_classic))
        or (sfui.version and (sfui.version.classic_era or sfui.version.wow_forever or not sfui.version.retail))

    if isClassic and pClass ~= "ROGUE" and pClass ~= "DRUID" then
        if sfui.bars then
            sfui.bars.bar1_in_use = false
        end
        return nil
    end

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

-- ────────────────────────────────────────────────────────────────────────────
-- UI Widgets & Styling Note:
-- Factory methods (create_bar, create_panel, create_border, create_button,
-- create_flat_button, create_slider_input, create_checkbox, etc.) are located in
-- sfui/core/widgets.lua and bound to sfui.common.*.
-- ────────────────────────────────────────────────────────────────────────────

function sfui.common.set_color(element, colorName, alpha)
    if sfui.colors and sfui.colors.set_color then
        return sfui.colors.set_color(element, colorName, alpha)
    end
    local cfg = sfui.config
    local color = cfg and cfg.colors and cfg.colors[colorName]
    if not color or not element then return end
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
    if sfui.widgets and sfui.widgets.create_font_string then
        return sfui.widgets.create_font_string(parent, font, point, x, y, colorName)
    end
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
    if InCombatLockdown() then return end
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
    if sfui.items and sfui.items.get_item_id then
        return sfui.items.get_item_id(link)
    end
    if not link then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- ========================
-- Utility Helpers
-- ========================



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
    if SfuiDB.enableSwingBars == nil then SfuiDB.enableSwingBars = true end

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

-- Robust player key generator resilient to realmless architectures and first+last names
local _cached_player_key = nil
function sfui.common.get_player_unique_key()
    if _cached_player_key then return _cached_player_key end

    local guid = _G.UnitGUID and _G.UnitGUID("player")
    if guid and guid ~= "" then
        _cached_player_key = guid
        return guid
    end

    local name = _G.UnitName and _G.UnitName("player")
    local getRealm = _G.GetNormalizedRealmName or _G.GetRealmName
    local realm = getRealm and getRealm()
    if (not realm or realm == "") and _G.GetCVar then
        realm = _G.GetCVar("realmName")
    end
    if not realm or realm == "" then
        realm = "Global"
    end

    if name and name ~= "" and name ~= "Unknown Entity" and name ~= "Unknown" then
        local safeName = name:gsub("%s+", "_")
        local key = safeName .. "-" .. realm
        _cached_player_key = key
        return key
    end

    return "player"
end

function sfui.common.get_player_display_name()
    local name = _G.UnitName and _G.UnitName("player")
    return (name and name ~= "" and name ~= "Unknown Entity") and name or "Unknown"
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
    local ccm = _G.C_ChallengeMode
    local name = ccm and ccm.GetMapUIInfo and ccm.GetMapUIInfo(mapID)
    if not name then return nil end
    return sfui.common.get_short_string(name)
end

--- Parse a Mythic+ keystone level from a string (e.g. LFG title, comment, or chat message).
--- Prioritizes explicit "+" notation ("+12", "M+12"), then tagged notation ("key 12", "(12)"),
--- and finally bounded standalone integers (2-40) via frontier pattern.
--- @param str string|number|nil
--- @return number|nil
function sfui.common.parse_keystone_level(str)
    if not str then return nil end
    if type(str) == "number" then
        return (str >= 2 and str <= 40) and str or nil
    end
    if type(str) ~= "string" or str == "" then return nil end

    -- 1. Explicit "+" notation: "+12", "+ 12", "M+12", "m+ 12"
    local plusLevel = str:match("[+]%s*(%d+)")
    if plusLevel then
        local num = tonumber(plusLevel)
        if num and num >= 2 and num <= 40 then
            return num
        end
    end

    -- 2. Explicit keyword notation: "key 12", "keystone 12", "(12)"
    local tagLevel = str:match("[Kk][Ee][Yy]%s*(%d+)") or str:match("%((%d+)%)")
    if tagLevel then
        local num = tonumber(tagLevel)
        if num and num >= 2 and num <= 40 then
            return num
        end
    end

    -- 3. Standalone number between 2 and 40 (keystone levels)
    -- Using frontier patterns %f[%d] and %f[%D] so it doesn't match ilvl (e.g. 615) or score (e.g. 2500)
    for numStr in str:gmatch("%f[%d](%d+)%f[%D]") do
        local num = tonumber(numStr)
        if num and num >= 2 and num <= 40 then
            return num
        end
    end
    return nil
end

--- Authoritative M+ keystone query across bags, C_MythicPlus, and C_LFGList.
--- Prioritizes physical bags for instant reflection of downgrades/rerolls/upgrades.
--- @return table|nil { mapID = number|nil, level = number, link = string|nil, name = string|nil, itemID = number|nil }
function sfui.common.get_owned_keystone_info()
    local C_Item          = _G.C_Item
    local C_MythicPlus    = _G.C_MythicPlus
    local C_LFGList       = _G.C_LFGList
    local C_ChallengeMode = _G.C_ChallengeMode

    -- 1. Query the C_MythicPlus API directly (the exact Blizzard API that powers the in-game M+ Challenges panel)
    local mpMap = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local mpLvl = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()

    local bagMapID, bagLevel, bagLink, bagItemID, linkDungeonName
    if mpLvl and mpLvl > 0 and mpLvl < 100 then
        bagLevel = mpLvl
    end
    if mpMap and mpMap > 0 then
        bagMapID = mpMap
    end

    -- 2. Scan physical bags to retrieve clickable item link (for chat linking & tooltips) or as fallback
    if sfui.common.for_each_bag_item then
        sfui.common.for_each_bag_item(function(bag, slot, itemID, itemLink)
            if not itemLink and _G.C_Container and _G.C_Container.GetContainerItemLink then
                itemLink = _G.C_Container.GetContainerItemLink(bag, slot)
            end
            if itemLink then
                local isKeystone = (itemID and (itemID == 180653 or itemID == 187786 or itemID == 151086 or (C_Item and C_Item.IsItemKeystoneByID and C_Item.IsItemKeystoneByID(itemID))))
                    or string.find(itemLink, "keystone", 1, true)
                    or string.find(itemLink, "item:180653", 1, true)
                    or string.find(itemLink, "item:187786", 1, true)
                    or string.find(itemLink, "item:151086", 1, true)

                if isKeystone then
                    bagItemID = itemID or bagItemID or 180653
                    bagLink   = itemLink

                    -- A. Bracket notation from display link text: [Keystone: Dungeon Name (12)]
                    local rawBracket, bracketLvl = string.match(itemLink, "%[(.-)%s*%((%d+)%)%]")
                    if not bagLevel and bracketLvl then
                        local bl = tonumber(bracketLvl)
                        if bl and bl > 0 and bl < 100 then
                            bagLevel = bl
                        end
                    end
                    if rawBracket then
                        local cleanName = string.match(rawBracket, ":%s*(.+)") or rawBracket
                        linkDungeonName = cleanName:match("^%s*(.-)%s*$")
                    end

                    -- B. Hyperlink payload:
                    -- Modern Retail: keystone:itemID:mapID:level:... (e.g. keystone:180653:587:12:...)
                    -- Legacy:        keystone:mapID:level:... (e.g. keystone:587:12:...)
                    if not bagMapID or not bagLevel then
                        local p1, p2, p3 = string.match(itemLink, "keystone:(%d+):(%d+):?(%d*)")
                        if p1 then
                            local n1 = tonumber(p1)
                            local n2 = tonumber(p2)
                            local n3 = tonumber(p3)
                            if n1 and n1 > 10000 and n2 and n3 then
                                bagItemID = n1
                                if not bagMapID then bagMapID = n2 end
                                if not bagLevel or bagLevel >= 100 then bagLevel = n3 end
                            elseif n1 and n2 then
                                if not bagMapID then bagMapID = n1 end
                                if not bagLevel or bagLevel >= 100 then bagLevel = n2 end
                            end
                        end
                    end

                    -- C. Item hyperlink format: item:180653:... (modifiers 17 = mapID, 18 = level)
                    if (not bagMapID or not bagLevel or bagLevel >= 100) and string.find(itemLink, "item:", 1, true) then
                        local raw = string.match(itemLink, "item:%d+:([^|]+)")
                        if raw then
                            local temp = { strsplit(":", itemLink) }
                            for i = 1, #temp - 1 do
                                if temp[i] == "17" and not bagMapID then
                                    bagMapID = tonumber(temp[i + 1])
                                elseif temp[i] == "18" and (not bagLevel or bagLevel >= 100) then
                                    local l = tonumber(temp[i + 1])
                                    if l and l > 0 and l < 100 then
                                        bagLevel = l
                                    end
                                end
                            end
                        end
                    end

                    -- D. Parenthesized fallback: %(%d+%)
                    if not bagLevel or bagLevel >= 100 then
                        local nameLevel = string.match(itemLink, "%((%d+)%)")
                        if nameLevel then
                            local nl = tonumber(nameLevel)
                            if nl and nl > 0 and nl < 100 then
                                bagLevel = nl
                            end
                        end
                    end

                    -- Validate bagMapID against C_ChallengeMode: if invalid mapID, clear it
                    if bagMapID and bagMapID > 0 and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
                        local testName = C_ChallengeMode.GetMapUIInfo(bagMapID)
                        if not testName then
                            bagMapID = nil
                        end
                    end

                    -- Fallback: resolve mapID from dungeon name against current season maps
                    if not bagMapID and linkDungeonName and C_ChallengeMode and C_ChallengeMode.GetMapTable then
                        local maps = C_ChallengeMode.GetMapTable()
                        if maps then
                            for _, mID in ipairs(maps) do
                                local mName = C_ChallengeMode.GetMapUIInfo(mID)
                                if mName and (mName == linkDungeonName or string.find(mName, linkDungeonName, 1, true) or string.find(linkDungeonName, mName, 1, true)) then
                                    bagMapID = mID
                                    break
                                end
                            end
                        end
                    end

                    if bagLevel and bagLevel > 0 and bagMapID and bagMapID > 0 then
                        return true
                    end
                end
            end
        end, true, true, true)
    end

    -- 3. Fall back to C_LFGList if still missing or out of bounds
    if (not bagMapID or not bagLevel or bagLevel >= 100) and C_LFGList and C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel then
        local activityID, groupID, lfgLevel = C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel()
        if not activityID then
            activityID, groupID, lfgLevel = C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel(true)
        end
        if lfgLevel and lfgLevel > 0 and lfgLevel < 100 then
            if not bagLevel or bagLevel >= 100 then bagLevel = lfgLevel end
            if not bagMapID and activityID then
                local actInfo = C_LFGList.GetActivityInfoTable and C_LFGList.GetActivityInfoTable(activityID)
                if actInfo and actInfo.mapID then
                    bagMapID = actInfo.mapID
                end
            end
        end
    end

    -- 4. If we have a valid keystone level (< 100), resolve name and return full keystone record
    if bagLevel and bagLevel > 0 and bagLevel < 100 then
        local mapName = nil
        if bagMapID and bagMapID > 0 and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
            mapName = C_ChallengeMode.GetMapUIInfo(bagMapID)
        end
        if not mapName and linkDungeonName and linkDungeonName ~= "" then
            mapName = linkDungeonName
        end
        return {
            mapID   = bagMapID,
            level   = bagLevel,
            link    = bagLink,
            name    = mapName,
            itemID  = bagItemID or 180653,
        }
    end

    return nil
end
sfui.items = sfui.items or {}
sfui.items.get_owned_keystone_info = sfui.common.get_owned_keystone_info

-- ────────────────────────────────────────────────────────────────────────────
-- Blizzard 12.1.0 StatusBar & UIWidget Progress Calculation Engine
-- Exact replication of UIWidgetBaseStatusBarTemplateMixin & MathUtil
-- ────────────────────────────────────────────────────────────────────────────
local StatusBarValueTextType = (_G.Enum and _G.Enum.StatusBarValueTextType) or {
    Hidden = 0,
    Percentage = 1,
    Value = 2,
    Time = 3,
    TimeShowOneLevelOnly = 4,
    ValueOverMax = 5,
    ValueOverMaxNormalized = 6,
}

local StatusBarOverrideBarTextShownType = (_G.Enum and _G.Enum.StatusBarOverrideBarTextShownType) or {
    Never = 0,
    Always = 1,
    OnlyOnMouseover = 2,
    OnlyNotOnMouseover = 3,
}

function sfui.common.percentage_between(value, startValue, endValue)
    if not value or not startValue or not endValue then return 0.0 end
    if startValue == endValue then
        return 0.0
    end
    return (value - startValue) / (endValue - startValue)
end

function sfui.common.clamped_percentage_between(value, startValue, endValue)
    local pct = sfui.common.percentage_between(value, startValue, endValue)
    if pct < 0 then return 0.0 elseif pct > 1 then return 1.0 end
    return pct
end

function sfui.common.process_status_bar_widget(barInfo, mouseOver)
    if not barInfo then return 0, "", "Progress", 0, 100 end

    local isSec = (sfui.common and sfui.common.issecretvalue) or _G.issecretvalue or function() return false end
    local val = (barInfo.barValue and not isSec(barInfo.barValue)) and barInfo.barValue or 0
    local minVal = (barInfo.barMin and not isSec(barInfo.barMin)) and barInfo.barMin or 0
    local maxVal = (barInfo.barMax and not isSec(barInfo.barMax)) and barInfo.barMax or 100

    -- Blizzard UIWidgetBaseStatusBarTemplateMixin:SanitizeAndSetStatusBarValues:
    -- If all 3 values are the same and greater than 0, show the bar as full
    if minVal > 0 and minVal == maxVal and val == maxVal then
        minVal, maxVal, val = 0, 1, 1
    end

    if maxVal > minVal then
        val = math.min(maxVal, math.max(minVal, val))
    end

    -- Percentage calculation
    local barPercent = sfui.common.clamped_percentage_between(val, minVal, maxVal)
    local barPct = math.floor(barPercent * 100 + 0.5)

    -- Blizzard UIWidgetBaseStatusBarTemplateMixin:SetBarText
    local barText = ""
    local txtType = barInfo.barValueTextType
    if txtType == StatusBarValueTextType.Time or txtType == StatusBarValueTextType.TimeShowOneLevelOnly then
        local maxTime = (txtType == StatusBarValueTextType.TimeShowOneLevelOnly) and 1 or 2
        barText = (_G.SecondsToTime and _G.SecondsToTime(val, false, true, maxTime, true)) or tostring(val)
    elseif txtType == StatusBarValueTextType.Value then
        barText = tostring(val)
    elseif txtType == StatusBarValueTextType.ValueOverMax then
        barText = string.format("%d/%d", val, maxVal)
    elseif txtType == StatusBarValueTextType.ValueOverMaxNormalized then
        barText = string.format("%d/%d", val - minVal, maxVal - minVal)
    elseif txtType == StatusBarValueTextType.Percentage then
        barText = string.format("%d%%", barPct)
    elseif txtType == StatusBarValueTextType.Hidden then
        barText = ""
    else
        barText = string.format("%d%%", barPct)
    end

    -- Blizzard UIWidgetBaseStatusBarTemplateMixin:UpdateLabel
    local showOverride = (barInfo.overrideBarTextShownType == StatusBarOverrideBarTextShownType.Always)
    if not showOverride then
        if mouseOver then
            showOverride = (barInfo.overrideBarTextShownType == StatusBarOverrideBarTextShownType.OnlyOnMouseover)
        else
            showOverride = (barInfo.overrideBarTextShownType == StatusBarOverrideBarTextShownType.OnlyNotOnMouseover)
        end
    end

    local shownText = (showOverride and barInfo.overrideBarText and barInfo.overrideBarText ~= "" and not isSec(barInfo.overrideBarText)) and barInfo.overrideBarText or barText
    if (not shownText or shownText == "") and txtType ~= StatusBarValueTextType.Hidden then
        shownText = string.format("%d%%", barPct)
    end

    local label = (barInfo.text and barInfo.text ~= "" and not isSec(barInfo.text) and barInfo.text)
               or (barInfo.tooltip and barInfo.tooltip ~= "" and not isSec(barInfo.tooltip) and barInfo.tooltip:match("^[^\n]+"))
               or "Progress"

    return barPct, shownText, label, val, maxVal
end

function sfui.common.process_double_status_bar_widget(dInfo, mouseOver)
    if not dInfo then return 0, "", "Progress", 0, 100 end
    local leftBarInfo = {
        barValue = dInfo.leftBarValue,
        barMin = dInfo.leftBarMin,
        barMax = dInfo.leftBarMax,
        barValueTextType = dInfo.barValueTextType,
        overrideBarText = dInfo.overrideBarText,
        overrideBarTextShownType = dInfo.overrideBarTextShownType,
        text = dInfo.text,
        tooltip = dInfo.leftBarTooltip,
    }
    return sfui.common.process_status_bar_widget(leftBarInfo, mouseOver)
end

function sfui.common.process_capture_bar_widget(cbInfo)
    if not cbInfo then return 50, "50%", "Control Point" end
    local isSec = (sfui.common and sfui.common.issecretvalue) or _G.issecretvalue or function() return false end
    local val = (cbInfo.barValue and not isSec(cbInfo.barValue)) and cbInfo.barValue or 0
    local minVal = (cbInfo.barMinValue and not isSec(cbInfo.barMinValue)) and cbInfo.barMinValue or 0
    local maxVal = (cbInfo.barMaxValue and not isSec(cbInfo.barMaxValue)) and cbInfo.barMaxValue or 100
    local barPercent = sfui.common.clamped_percentage_between(val, minVal, maxVal)
    local barPct = math.floor(barPercent * 100 + 0.5)
    local shownText = string.format("%d%%", barPct)
    local label = (cbInfo.tooltip and cbInfo.tooltip ~= "" and not isSec(cbInfo.tooltip) and cbInfo.tooltip:match("^[^\n]+")) or "Control Point"
    return barPct, shownText, label
end

function sfui.common.process_tug_of_war_widget(towInfo)
    if not towInfo then return 50, "50%", "Tug of War" end
    local isSec = (sfui.common and sfui.common.issecretvalue) or _G.issecretvalue or function() return false end
    local val = (towInfo.currentValue and not isSec(towInfo.currentValue)) and towInfo.currentValue or 0
    local minVal = (towInfo.minValue and not isSec(towInfo.minValue)) and towInfo.minValue or 0
    local maxVal = (towInfo.maxValue and not isSec(towInfo.maxValue)) and towInfo.maxValue or 100
    local barPercent = sfui.common.clamped_percentage_between(val, minVal, maxVal)
    local barPct = math.floor(barPercent * 100 + 0.5)
    local shownText = string.format("%d%%", barPct)
    local label = (towInfo.tooltip and towInfo.tooltip ~= "" and not isSec(towInfo.tooltip) and towInfo.tooltip:match("^[^\n]+")) or "Tug of War"
    return barPct, shownText, label
end

function sfui.common.process_discrete_steps_widget(dpInfo)
    if not dpInfo then return 0, "0/1", "Progress" end
    local isSec = (sfui.common and sfui.common.issecretvalue) or _G.issecretvalue or function() return false end
    local minVal = (dpInfo.progressMin and not isSec(dpInfo.progressMin)) and dpInfo.progressMin or 0
    local maxVal = (dpInfo.progressMax and not isSec(dpInfo.progressMax) and dpInfo.progressMax > 0 and dpInfo.progressMax)
                or (dpInfo.numSteps and not isSec(dpInfo.numSteps) and dpInfo.numSteps > 0 and dpInfo.numSteps)
                or 100
    local val = (dpInfo.progressVal and not isSec(dpInfo.progressVal)) and dpInfo.progressVal or minVal
    local barPercent = sfui.common.clamped_percentage_between(val, minVal, maxVal)
    local barPct = math.floor(barPercent * 100 + 0.5)
    local shownText = string.format("%d/%d", val, maxVal)
    local label = (dpInfo.tooltip and dpInfo.tooltip ~= "" and not isSec(dpInfo.tooltip) and dpInfo.tooltip:match("^[^\n]+")) or "Progress"
    return barPct, shownText, label
end


