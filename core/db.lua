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
local _isInitialized = false

--- Register default configuration table for a module.
--- @param moduleName string
--- @param defaults table
function sfui.db.RegisterDefaults(moduleName, defaults)
    if not moduleName or type(defaults) ~= "table" then return end
    moduleDefaults[moduleName] = defaults

    if _isInitialized and SfuiDB then
        if SfuiDB[moduleName] == nil then
            SfuiDB[moduleName] = {}
        end
        for k, v in pairs(defaults) do
            if SfuiDB[moduleName][k] == nil then
                if type(v) == "table" then
                    SfuiDB[moduleName][k] = CopyTable and CopyTable(v) or (sfui.common and sfui.common.copy and sfui.common.copy(v)) or {}
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
    if not moduleName or not key then return fallback end
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
    for moduleName, defs in pairs(moduleDefaults) do
        if SfuiDB[moduleName] == nil then
            SfuiDB[moduleName] = {}
        end
        for k, v in pairs(defs) do
            if SfuiDB[moduleName][k] == nil then
                if type(v) == "table" then
                    SfuiDB[moduleName][k] = CopyTable and CopyTable(v) or (sfui.common and sfui.common.copy and sfui.common.copy(v)) or {}
                else
                    SfuiDB[moduleName][k] = v
                end
            end
        end
    end
end

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

