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

local _curModuleCtx = nil

local function _module_error_handler(err)
    local stack = debugstack and debugstack(2, 20, 20)
    if _G.sfuibug and _G.sfuibug.RecordError then
        _G.sfuibug.RecordError(_curModuleCtx, err, stack)
    elseif _G.CallErrorHandler then
        _G.CallErrorHandler(err)
    elseif _G.geterrorhandler and _G.geterrorhandler() then
        _G.geterrorhandler()(err)
    else
        local lbl = _curModuleCtx and _curModuleCtx.label or "module"
        print("|cffff0000[sfui module error]|r " .. tostring(lbl) .. ": " .. tostring(err))
    end
    return err
end

local function _safe_call(mod, method, ...)
    if mod and type(mod[method]) == "function" then
        local prevCtx = _curModuleCtx
        _curModuleCtx = {
            module = mod.name or "core",
            file = "core/module.lua",
            label = tostring(mod.name) .. ":" .. method .. "()",
        }
        xpcall(mod[method], _module_error_handler, mod, ...)
        _curModuleCtx = prevCtx
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
local _lastBroadcastSpecID = nil
local function _on_spec_changed(specID, force)
    specID = specID or sfui.common.get_current_spec_id()
    if not force and specID == _lastBroadcastSpecID then
        return
    end
    _lastBroadcastSpecID = specID

    for _, mod in pairs(modules) do
        if type(mod.OnSpecChanged) == "function" then
            _safe_call(mod, "OnSpecChanged", specID)
        end
    end
end

function sfui.BroadcastSpecChanged(specID, force)
    _on_spec_changed(specID, force)
end

sfui.events.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function() _on_spec_changed() end)
sfui.events.RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", function() _on_spec_changed() end)
sfui.events.RegisterEvent("ACTIVE_COMBAT_CONFIG_CHANGED", function() _on_spec_changed() end)

sfui.events.RegisterMessage("SFUI_SPEC_COLORS_UPDATED", function(_, specID)
    _on_spec_changed(specID, true)
end)


if sfui.dispatcher_debug_info then
    sfui.events = sfui.events or {}
    sfui.events.GetDebugInfo = sfui.dispatcher_debug_info
    sfui.RegisterModule("dispatcher", sfui.events)
end

if sfui.stats then
    sfui.RegisterModule("stats", sfui.stats)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Declarative Module Taxonomy & Dynamic Discovery
-- ─────────────────────────────────────────────────────────────────────────────

local DEFAULT_TAXONOMY = {
    -- bars & combat
    bars           = { category = "bars & combat", client = "all", order = 10 },
    actionbars     = { category = "bars & combat", client = "all", order = 20 },
    castbars       = { category = "bars & combat", client = "all", order = 30 },
    vehicle        = { category = "bars & combat", client = "all", order = 40 },
    soulfragments  = { category = "bars & combat", client = "retail", order = 50 },
    threat         = { category = "bars & combat", client = "classic", order = 60 },
    target         = { category = "bars & combat", client = "classic", order = 70 },
    swing          = { category = "bars & combat", client = "classic", order = 80 },
    totembar       = { category = "bars & combat", client = "classic", order = 90 },
    experience     = { category = "bars & combat", client = "all", order = 100 },

    -- tracking & cooldowns
    trackedbars    = { category = "tracking & cooldowns", client = "all", order = 10 },
    trackedicons   = { category = "tracking & cooldowns", client = "all", order = 20 },
    trackedbuffs   = { category = "tracking & cooldowns", client = "retail", order = 30 },
    cdm            = { category = "tracking & cooldowns", client = "all", order = 40 },
    glows          = { category = "tracking & cooldowns", client = "all", order = 50 },

    -- objectives
    quests         = { category = "objectives", client = "all", order = 10 },
    mythic         = { category = "objectives", client = "retail", order = 20 },
    dungeonjournal = { category = "objectives", client = "classic", order = 30 },
    worldevents    = { category = "objectives", client = "retail", order = 40 },
    location       = { category = "objectives", client = "all", order = 50 },
    pins           = { category = "objectives", client = "all", order = 60 },
    research       = { category = "objectives", client = "retail", order = 70 },

    -- automation
    automation     = { category = "automation", client = "all", order = 10 },
    fishing        = { category = "automation", client = "all", order = 20 },
    merchant       = { category = "automation", client = "all", order = 30 },
    triage         = { category = "automation", client = "all", order = 40 },
    transfer       = { category = "automation", client = "retail", order = 50 },
    rankup         = { category = "automation", client = "classic", order = 60 },
    pets           = { category = "automation", client = "all", order = 70 },
    hammer         = { category = "automation", client = "retail", order = 80 },
    bonusroll      = { category = "automation", client = "retail", order = 90 },
    lootspec       = { category = "automation", client = "retail", order = 100 },
    recipes        = { category = "automation", client = "classic", order = 110 },
    mail           = { category = "automation", client = "all", order = 120 },

    -- general & utilities
    alts           = { category = "general & utilities", client = "all", order = 10 },
    buffs          = { category = "general & utilities", client = "classic", order = 20 },
    currency       = { category = "general & utilities", client = "all", order = 30 },
    cursor         = { category = "general & utilities", client = "all", order = 40 },
    dispatcher     = { category = "general & utilities", client = "all", order = 50 },
    gear           = { category = "general & utilities", client = "all", order = 60 },
    hide           = { category = "general & utilities", client = "all", order = 70 },
    logs           = { category = "general & utilities", client = "all", order = 80 },
    lootfeed       = { category = "general & utilities", client = "all", order = 90 },
    minimap        = { category = "general & utilities", client = "all", order = 100 },
    portals        = { category = "general & utilities", client = "retail", order = 110 },
    ring           = { category = "general & utilities", client = "all", order = 120 },
    stats          = { category = "general & utilities", client = "all", order = 130 },
    sync           = { category = "general & utilities", client = "all", order = 140 },
}

local CATEGORY_ORDER = {
    ["bars & combat"]        = 1,
    ["tracking & cooldowns"] = 2,
    ["objectives"]           = 3,
    ["automation"]           = 4,
    ["general & utilities"]  = 5,
}

local function is_module_client_eligible(client)
    if not client or client == "all" then return true end
    if client == "retail" then return sfui.isRetail == true end
    if client == "classic" then return sfui.isRetail ~= true end
    if client == "camelot" then return sfui.isCamelot == true end
    return true
end

--- Get dynamic module sections filtered by active client flavor.
--- @return table Array of { title = string, modules = { string, ... } }
function sfui.GetModuleSections()
    local sections = {}
    local secMap = {}

    local function get_or_create_section(catName)
        if not secMap[catName] then
            local sec = { title = catName, modules = {} }
            secMap[catName] = sec
            sections[#sections + 1] = sec
        end
        return secMap[catName]
    end

    local seen = {}
    local allKeys = {}

    for name in pairs(DEFAULT_TAXONOMY) do
        if not seen[name] then
            seen[name] = true
            allKeys[#allKeys + 1] = name
        end
    end
    for name in pairs(modules) do
        if not seen[name] then
            seen[name] = true
            allKeys[#allKeys + 1] = name
        end
    end

    for _, name in ipairs(allKeys) do
        local mod = modules[name]
        local def = DEFAULT_TAXONOMY[name]
        local client = (mod and mod.client) or (def and def.client) or "all"
        if is_module_client_eligible(client) then
            local cat = (mod and mod.category) or (def and def.category) or "general & utilities"
            local sec = get_or_create_section(cat)
            table.insert(sec.modules, name)
        end
    end

    -- Sort modules within each section: by order if defined, then alphabetical
    for _, sec in ipairs(sections) do
        table.sort(sec.modules, function(a, b)
            local modA, modB = modules[a], modules[b]
            local defA, defB = DEFAULT_TAXONOMY[a], DEFAULT_TAXONOMY[b]
            local orderA = (modA and modA.order) or (defA and defA.order)
            local orderB = (modB and modB.order) or (defB and defB.order)
            if orderA and orderB and orderA ~= orderB then
                return orderA < orderB
            elseif orderA and not orderB then
                return true
            elseif not orderA and orderB then
                return false
            end
            return a < b
        end)
    end

    -- Sort sections by predefined category order
    table.sort(sections, function(a, b)
        local oA = CATEGORY_ORDER[a.title] or 99
        local oB = CATEGORY_ORDER[b.title] or 99
        if oA ~= oB then return oA < oB end
        return a.title < b.title
    end)

    return sections
end

--- Get flattened list of module keys in display order.
--- @return table Array of module key strings
function sfui.GetModuleOrder()
    local sections = sfui.GetModuleSections()
    local order = {}
    for _, sec in ipairs(sections) do
        for _, modKey in ipairs(sec.modules) do
            table.insert(order, modKey)
        end
    end
    return order
end

