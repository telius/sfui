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

local type, ipairs, pairs, tonumber, tostring = type, ipairs, pairs, tonumber, tostring
local table, math, string = table, math, string
local C_Timer = _G.C_Timer
local C_CooldownViewer = _G.C_CooldownViewer
local CooldownViewerSettings = _G.CooldownViewerSettings
local C_ClassTalents = _G.C_ClassTalents
local wipe = _G.wipe or table.wipe

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
                if not (sfui.common.issecretvalue and sfui.common.issecretvalue(cooldownID)) then
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

    if not SfuiDB.cooldownPanelsBySpec or not SfuiDB.cooldownPanelsBySpec[specID] or #SfuiDB.cooldownPanelsBySpec[specID] == 0 or ((sfui.common.get_player_class() == "DRUID" or sfui.common.get_player_class() == "ROGUE") and not SfuiDB.druidMigrationV7) then
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
sfui.common.get_active_panel_entries = sfui.tracking.get_active_panel_entries
sfui.panels.get_active_panel_entries = sfui.tracking.get_active_panel_entries

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
        { key = "center_panel", name = "CENTER",  populateFunc = sfui.tracking.populate_center_panel_from_cdm },
        { key = "utility",      name = "UTILITY", populateFunc = sfui.tracking.populate_utility_panel_from_cdm },
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
        sfui.tracking.set_cooldown_panels(panels)
    else
        -- If no entries were found but population was expected, retry once after a short delay
        -- This handles the race condition on fresh installations/characters on Retail
        local isClassic = not sfui.isRetail

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
                    sfui.tracking.ensure_panels_initialized()
                end)
            end
        end
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
