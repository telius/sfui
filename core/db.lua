local addonName, addon = ...
sfui = sfui or {}
sfui.db = {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/core/db.lua
--  Centralized SavedVariables Manager & Persistence Guards
--
--  Prevents state loss on logout/reload, manages defaults fallback,
--  and provides pub/sub notification on setting updates.
-- ══════════════════════════════════════════════════════════════════════════════

local moduleDefaults = {}
local moduleVersions = {}
local moduleMigrations = {}
local _isInitialized = false

local function run_migration(moduleName, targetVersion, migrationFunc)
    if not _isInitialized or not SfuiDB or not targetVersion or not migrationFunc then return end
    SfuiDB.__versions = SfuiDB.__versions or {}
    local curVersion = SfuiDB.__versions[moduleName] or 0
    if curVersion < targetVersion then
        if SfuiDB[moduleName] then
            pcall(migrationFunc, SfuiDB[moduleName], curVersion, targetVersion)
        end
        SfuiDB.__versions[moduleName] = targetVersion
    end
end

--- Register default configuration table for a module with optional schema version and migration.
--- @param moduleName string
--- @param defaults table
--- @param schemaVersion number|nil Optional schema version integer
--- @param migrationFunc function|nil Optional migration callback function(currentDB, oldVersion, newVersion)
function sfui.db.RegisterDefaults(moduleName, defaults, schemaVersion, migrationFunc)
    if not moduleName or type(defaults) ~= "table" then return end
    moduleDefaults[moduleName] = defaults
    if schemaVersion then
        moduleVersions[moduleName] = schemaVersion
        moduleMigrations[moduleName] = migrationFunc
    end

    if _isInitialized and SfuiDB then
        if schemaVersion and migrationFunc then
            run_migration(moduleName, schemaVersion, migrationFunc)
        end
        if SfuiDB[moduleName] == nil then
            SfuiDB[moduleName] = {}
        end
        for k, v in pairs(defaults) do
            if SfuiDB[moduleName][k] == nil then
                if type(v) == "table" then
                    SfuiDB[moduleName][k] = CopyTable and CopyTable(v) or sfui.common.copy(v)
                else
                    SfuiDB[moduleName][k] = v
                end
            end
        end
    end
end

--- Get a setting value with fallback to defaults or user fallback.
--- @param moduleName string
--- @param key string
--- @param fallback any
--- @return any
function sfui.db.Get(moduleName, key, fallback)
    if not moduleName then return fallback end
    if not key then
        if SfuiDB and SfuiDB[moduleName] ~= nil then
            return SfuiDB[moduleName]
        end
        if moduleDefaults[moduleName] ~= nil then
            return moduleDefaults[moduleName]
        end
        if sfui.config and sfui.config[moduleName] ~= nil then
            return sfui.config[moduleName]
        end
        return fallback
    end
    if SfuiDB and SfuiDB[moduleName] and SfuiDB[moduleName][key] ~= nil then
        return SfuiDB[moduleName][key]
    end
    if moduleDefaults[moduleName] and moduleDefaults[moduleName][key] ~= nil then
        return moduleDefaults[moduleName][key]
    end
    if sfui.config and sfui.config[moduleName] and sfui.config[moduleName][key] ~= nil then
        return sfui.config[moduleName][key]
    end
    return fallback
end

--- Set a setting value and broadcast change via internal message bus.
--- @param moduleName string
--- @param key string
--- @param value any
function sfui.db.Set(moduleName, key, value)
    if not moduleName or not key then return end
    SfuiDB = SfuiDB or {}
    if SfuiDB[moduleName] == nil then
        SfuiDB[moduleName] = {}
    end
    local prev = SfuiDB[moduleName][key]
    if prev ~= value then
        SfuiDB[moduleName][key] = value
        sfui.events.SendMessage("SFUI_SETTING_CHANGED", moduleName, key, value)
    end
end

--- Initialize and synchronize defaults across all registered modules.
function sfui.db.Initialize()
    if _isInitialized then return end
    _isInitialized = true

    SfuiDB = SfuiDB or {}
    SfuiDB.__versions = SfuiDB.__versions or {}

    -- Run registered schema migrations
    for moduleName, targetVersion in pairs(moduleVersions) do
        local migrationFunc = moduleMigrations[moduleName]
        if targetVersion and migrationFunc then
            run_migration(moduleName, targetVersion, migrationFunc)
        end
    end

    for moduleName, defs in pairs(moduleDefaults) do
        if SfuiDB[moduleName] == nil then
            SfuiDB[moduleName] = {}
        end
        for k, v in pairs(defs) do
            if SfuiDB[moduleName][k] == nil then
                if type(v) == "table" then
                    SfuiDB[moduleName][k] = CopyTable and CopyTable(v) or sfui.common.copy(v)
                else
                    SfuiDB[moduleName][k] = v
                end
            end
        end
    end
end

sfui.db.get = sfui.db.Get
sfui.db.set = sfui.db.Set
sfui.db.register_defaults = sfui.db.RegisterDefaults
sfui.common.db_get = sfui.db.Get
sfui.common.db_set = sfui.db.Set

-- ─── Safe Logout Persistence Guard ──────────────────────────────────────────
-- On client shutdown or reload, broadcast flush intent to modules.
-- Alt data and other character state are continuously saved into SfuiDB
-- in real-time as events occur during gameplay. We intentionally do NOT
-- trigger an API re-scan here because WoW C-APIs are in a teardown state
-- during logout and will return nil/empty, risking data corruption.
local function OnLogoutPersistenceFlush()
    sfui.events.SendMessage("SFUI_PERSISTENCE_FLUSH")
end

-- PLAYER_LOGOUT fires on clean /quit or /logout.
sfui.events.RegisterEvent("PLAYER_LOGOUT", OnLogoutPersistenceFlush)

