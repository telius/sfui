local addonName, addon = ...
sfui = sfui or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/core/module.lua
--  Unified Module Lifecycle Protocol & Registry
--
--  Usage:
--    local MyMod = sfui.RegisterModule("bars", {
--        OnInit = function(self) ... end,             -- ADDON_LOADED (defaults, tables)
--        OnEnable = function(self) ... end,           -- PLAYER_LOGIN (frames, events)
--        OnDisable = function(self) ... end,          -- User disabled in options
--        OnSettingsChanged = function(self, k, v) ... end, -- Broadcast from options
--        OnSpecChanged = function(self, specID) ... end,   -- Talent / spec update
--        GetDebugInfo = function(self) ... end,       -- Telemetry for sfui.mem
--    })
-- ══════════════════════════════════════════════════════════════════════════════

sfui.modules = sfui.modules or {}
local modules = sfui.modules

local _isAddonLoaded = false
local _isPlayerLoggedIn = false

local function _safe_call(mod, method, ...)
    if mod and type(mod[method]) == "function" then
        local ok, err = pcall(mod[method], mod, ...)
        if not ok then
            print("|cffff0000[sfui module error]|r " .. tostring(mod.name) .. ":" .. method .. "(): " .. tostring(err))
        end
    end
end

--- Register a module with standard lifecycle hooks.
--- @param name string Unique module identifier (e.g. "bars", "castbar", "gear")
--- @param def table Table containing module definition and lifecycle methods
--- @return table The registered module table
function sfui.RegisterModule(name, def)
    if not name or type(name) ~= "string" then return def end
    def = def or {}
    def.name = name

    -- If sfui[name] was already declared as a namespace, preserve existing fields
    if sfui[name] and type(sfui[name]) == "table" and sfui[name] ~= def then
        for k, v in pairs(sfui[name]) do
            if def[k] == nil then
                def[k] = v
            end
        end
    end
    sfui[name] = def
    modules[name] = def

    -- Automatic late-binding if registered after lifecycle triggers
    if _isAddonLoaded and not def._initRan then
        def._initRan = true
        _safe_call(def, "OnInit")
    end
    if _isPlayerLoggedIn and not def._enabledRan then
        def._enabledRan = true
        _safe_call(def, "OnEnable")
    end

    return def
end

--- Retrieve a registered module by name.
--- @param name string
--- @return table|nil
function sfui.GetModule(name)
    return modules[name]
end

--- Execute OnInit() across all registered modules (called during ADDON_LOADED).
function sfui.InitModules()
    _isAddonLoaded = true
    for name, mod in pairs(modules) do
        if not mod._initRan then
            mod._initRan = true
            _safe_call(mod, "OnInit")
        end
    end
end

--- Execute OnEnable() across all registered modules (called during PLAYER_LOGIN).
function sfui.EnableModules()
    _isPlayerLoggedIn = true
    for name, mod in pairs(modules) do
        if not mod._enabledRan then
            mod._enabledRan = true
            _safe_call(mod, "OnEnable")
        end
    end
end

-- Listen for settings changes dispatched from options.lua or slash commands
sfui.events.RegisterMessage("SFUI_SETTING_CHANGED", function(_, moduleName, key, value)
    if not moduleName then return end
    local mod = modules[moduleName] or sfui[moduleName]
    if mod then
        if type(mod.OnSettingsChanged) == "function" then
            _safe_call(mod, "OnSettingsChanged", key, value)
        elseif type(mod.update_settings) == "function" then
            pcall(mod.update_settings)
        elseif type(mod.UpdateSettings) == "function" then
            pcall(mod.UpdateSettings)
        end
    end
end)

-- Listen for spec changes and forward to modules implementing OnSpecChanged
local function _on_spec_changed()
    local specID = sfui.common and sfui.common.get_current_spec_id and sfui.common.get_current_spec_id()
    for _, mod in pairs(modules) do
        if type(mod.OnSpecChanged) == "function" then
            _safe_call(mod, "OnSpecChanged", specID)
        end
    end
end

sfui.events.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", _on_spec_changed)
sfui.events.RegisterEvent("PLAYER_TALENT_UPDATE", _on_spec_changed)
