local addonName, addon = ...
sfui = sfui or {}
sfui.ring = sfui.ring or {}

local ring = sfui.ring

local GetBindingKey           = _G.GetBindingKey
local SetBinding              = _G.SetBinding
local SaveBindings            = _G.SaveBindings
local GetCurrentBindingSet    = _G.GetCurrentBindingSet
local InCombatLockdown        = _G.InCombatLockdown
local C_Timer                 = _G.C_Timer
local pairs                   = _G.pairs
local next                    = _G.next
local wipe                    = _G.wipe

local providers = {}
local cachedSlots = {}
local registeredEvents = {}

local function is_hunter_in_camelot()
    local isCam = (sfui.isCamelot or (sfui.compat and sfui.compat.is_camelot))
    local pClass = (sfui.common and sfui.common.get_player_class and sfui.common.get_player_class())
                   or (_G.UnitClass and select(2, _G.UnitClass("player")))
    return not not (isCam and pClass == "HUNTER")
end

-- ── 1. Configuration & Module Registration ──────────────────────────────────
local defaults = {
    enabled     = true,
    animations  = true,
    radius      = 95,
    deadzone    = 28,
    slot_size   = 40,
    show_labels = true,
    show_cooldowns = true,
    sound_cues  = true,
    quest_include_chests       = true,
    quest_include_knowledge    = true,
    quest_include_collectibles = true,
    quest_max_slices           = 14,
    custom_slots = {},
    bindings    = {
        specs         = "ALT-X",
        utility       = "ALT-C",
        tracking      = "ALT-F",
        professions   = "ALT-T",
        questitems    = "ALT-Q",
        targetmarkers = "ALT-R",
        worldmarkers  = "ALT-Y",
    },
}
sfui.db.RegisterDefaults("ring", defaults)

-- ── 2. Provider Registry ────────────────────────────────────────────────────
local pendingRebuilds = {}
local rebuildTimer = nil

local function do_flush_rebuilds()
    rebuildTimer = nil
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    for rID in pairs(pendingRebuilds) do
        pendingRebuilds[rID] = nil
        ring.rebuild(rID)
    end
end

--- schedule a debounced rebuild for a ring, coalescing rapid events.
--- in combat, rebuilds are paused until combat ends.
--- @param ringID string|nil
function ring.request_rebuild(ringID)
    if ringID then
        pendingRebuilds[ringID] = true
    else
        for id in pairs(providers) do
            pendingRebuilds[id] = true
        end
    end

    if InCombatLockdown and InCombatLockdown() then
        return
    end

    if not rebuildTimer and C_Timer and C_Timer.After then
        rebuildTimer = C_Timer.After(0.35, do_flush_rebuilds)
    end
end

--- register a content provider for radial rings.
--- @param id string unique ring provider identifier (e.g. "targetmarkers")
--- @param def table provider definition with name, title, events, build function
function ring.register_provider(id, def)
    if not id or not def or not def.build then return end
    def.id = id
    providers[id] = def

    -- register automatic rebuild listeners for declared events
    if def.events then
        for i = 1, #def.events do
            local evt = def.events[i]
            if not registeredEvents[evt] then
                registeredEvents[evt] = {}
                sfui.events.RegisterEvent(evt, function()
                    for rID in pairs(registeredEvents[evt]) do
                        ring.request_rebuild(rID)
                    end
                end)
            end
            registeredEvents[evt][id] = true
        end
    end
end

--- retrieve a list of all registered provider definitions.
--- @return table
function ring.get_providers()
    return providers
end

-- ── 3. Slot Cache & Rebuilding ──────────────────────────────────────────────
--- rebuild slot contents for a specific ring or all rings.
--- @param ringID string|nil
function ring.rebuild(ringID)
    if ringID then
        local def = providers[ringID]
        if def and def.build then
            local slots = cachedSlots[ringID] or {}
            wipe(slots)
            def.build(slots)
            cachedSlots[ringID] = slots
            if ring.secure and ring.secure.push_ring_slots then
                ring.secure.push_ring_slots(ringID, slots)
            end
        end
    else
        for id in pairs(providers) do
            ring.rebuild(id)
        end
    end
end

--- get the current slot array and display title for a ring.
--- @param ringID string
--- @return table, string
function ring.get_ring_slots(ringID)
    if not cachedSlots[ringID] then
        ring.rebuild(ringID)
    end
    local def = providers[ringID]
    local title = (def and def.title) or ringID
    return cachedSlots[ringID] or {}, title
end

-- ── 4. Keybinding Synchronization ───────────────────────────────────────────
local function get_button_binding_action(ringID)
    return "CLICK SfuiRing_" .. ringID .. ":LeftButton"
end

--- get the active keybinding for a given ring.
--- checks class/context overrides, sfui saved variables, and defaults.
--- @param ringID string
--- @return string|nil rawKey, string|nil formattedKey
function ring.get_binding(ringID)
    local isHunter = is_hunter_in_camelot()
    local dbBindings = sfui.db.Get("ring", "bindings", {}) or {}

    -- 1. Non-hunters in Camelot (and all non-hunters):
    -- Pet ring is NEVER active or bound.
    if not isHunter and ringID == "pet" then
        return nil, nil
    end

    -- 2. Non-hunters in Camelot (and all non-hunters):
    -- Specs MUST stay the default ALT-X keybind!
    if not isHunter and ringID == "specs" then
        local userKey = dbBindings["specs"]
        -- If unconfigured, or set to hunter default SHIFT-ALT-X, return ALT-X
        if userKey == nil or userKey == "" or userKey == "SHIFT-ALT-X" or userKey == "ALT-X" then
            return "ALT-X", "ALT-X"
        end
        if userKey == false then
            return nil, nil
        end
        return userKey, userKey
    end

    -- 3. Hunters in Camelot:
    -- Pet defaults to ALT-X, specs defaults to SHIFT-ALT-X
    if isHunter then
        if ringID == "pet" then
            local petKey = dbBindings["hunter_pet"]
            if petKey == nil then petKey = dbBindings["pet"] end
            if petKey == nil or petKey == "" or petKey == "ALT-X" then
                return "ALT-X", "ALT-X"
            end
            if petKey == false then
                return nil, nil
            end
            return petKey, petKey
        elseif ringID == "specs" then
            local hunterSpecsKey = dbBindings["hunter_specs"]
            if hunterSpecsKey == nil or hunterSpecsKey == "" or hunterSpecsKey == "SHIFT-ALT-X" then
                return "SHIFT-ALT-X", "SHIFT-ALT-X"
            end
            if hunterSpecsKey == false then
                return nil, nil
            end
            return hunterSpecsKey, hunterSpecsKey
        end
    end

    -- 4. Other rings: check dbBindings first
    local dbKey = dbBindings[ringID]
    if dbKey ~= nil and dbKey ~= "" then
        if dbKey == false then
            return nil, nil
        end
        return dbKey, dbKey
    end

    -- 5. Fallback to Blizzard native binding if set
    local action = get_button_binding_action(ringID)
    local blizzKey = GetBindingKey and GetBindingKey(action)
    if blizzKey and blizzKey ~= "" then
        return blizzKey, blizzKey
    end

    -- 6. Module defaults
    local defBindings = defaults.bindings
    if defBindings and defBindings[ringID] and defBindings[ringID] ~= "" then
        return defBindings[ringID], defBindings[ringID]
    end

    return nil, nil
end

--- assign a keybinding to a ring, syncing with blizzard bindings and override clicks.
--- @param ringID string
--- @param key string
function ring.set_binding(ringID, key)
    if not ringID or not key or key == "" then return end

    local isHunter = is_hunter_in_camelot()
    local dbBindings = sfui.db.Get("ring", "bindings", {}) or {}

    if isHunter then
        if ringID == "pet" then
            dbBindings["hunter_pet"] = key
            dbBindings["pet"] = key
        elseif ringID == "specs" then
            dbBindings["hunter_specs"] = key
        else
            dbBindings[ringID] = key
        end
    else
        if ringID == "specs" then
            dbBindings["specs"] = key
        elseif ringID ~= "pet" then
            dbBindings[ringID] = key
        end
    end

    sfui.db.Set("ring", "bindings", dbBindings)

    local effectiveKey = ring.get_binding(ringID)
    if ring.secure and ring.secure.apply_binding then
        ring.secure.apply_binding(ringID, effectiveKey)
    end
end

--- clear the keybinding for a ring.
--- @param ringID string
function ring.unbind(ringID)
    if not ringID then return end

    local isHunter = is_hunter_in_camelot()
    local dbBindings = sfui.db.Get("ring", "bindings", {}) or {}

    if isHunter then
        if ringID == "pet" then
            dbBindings["hunter_pet"] = false
            dbBindings["pet"] = false
        elseif ringID == "specs" then
            dbBindings["hunter_specs"] = false
        else
            dbBindings[ringID] = false
        end
    else
        if ringID == "specs" then
            dbBindings["specs"] = false
        elseif ringID ~= "pet" then
            dbBindings[ringID] = false
        end
    end

    sfui.db.Set("ring", "bindings", dbBindings)

    if ring.secure and ring.secure.clear_binding then
        ring.secure.clear_binding(ringID)
    end
end

--- apply all configured keybindings to their respective secure buttons.
function ring.apply_all_bindings()
    local isHunter = is_hunter_in_camelot()

    -- Clean up any conflicting Blizzard bindings on non-hunters
    if not isHunter and GetBindingKey and SetBinding then
        local petAction = get_button_binding_action("pet")
        local pk1, pk2 = GetBindingKey(petAction)
        if pk1 then SetBinding(pk1, nil) end
        if pk2 then SetBinding(pk2, nil) end

        local specsAction = get_button_binding_action("specs")
        local sk1, sk2 = GetBindingKey(specsAction)
        if sk1 == "SHIFT-ALT-X" then SetBinding(sk1, nil) end
        if sk2 == "SHIFT-ALT-X" then SetBinding(sk2, nil) end
    end

    for id in pairs(providers) do
        local key = ring.get_binding(id)
        if ring.secure and ring.secure.apply_binding then
            ring.secure.apply_binding(id, key)
        end
    end
end

-- ── 5. Module Lifecycle Registration ────────────────────────────────────────
sfui.RegisterModule("ring", {
    OnInit = function()
        ring.rebuild()
    end,
    OnEnable = function()
        ring.rebuild()
        ring.apply_all_bindings()
    end,
    OnSettingsChanged = function(_, moduleName, key, value)
        if moduleName == "ring" then
            ring.rebuild()
            ring.apply_all_bindings()
        end
    end,
})

sfui.events.RegisterEvent("UPDATE_BINDINGS", function()
    ring.apply_all_bindings()
end)

sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    ring.rebuild()
    ring.apply_all_bindings()
end)

sfui.events.RegisterEvent("PLAYER_REGEN_DISABLED", function()
    rebuildTimer = nil
    for rID in pairs(pendingRebuilds) do
        pendingRebuilds[rID] = nil
        ring.rebuild(rID)
    end
    if providers["questitems"] then
        ring.rebuild("questitems")
    end
end)

sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if next(pendingRebuilds) then
        do_flush_rebuilds()
    end
end)

-- ── 6. Debug & Memory Monitoring ────────────────────────────────────────────
function sfui.ring_debug_info()
    local provCount = 0
    for _ in pairs(providers) do
        provCount = provCount + 1
    end

    local activeSlotsCount = 0
    if ring.view and ring.view.get_active_slots_count then
        activeSlotsCount = ring.view.get_active_slots_count()
    end

    local isShown = (ring.view and ring.view.get_frame and ring.view.get_frame():IsShown()) or false
    local currentRing = ring.view and ring.view.get_current_ring_id and ring.view.get_current_ring_id()
    local pendingCount = 0
    for _ in pairs(pendingRebuilds) do
        pendingCount = pendingCount + 1
    end

    local boundCount = 0
    for id in pairs(providers) do
        local b = ring.get_binding(id)
        if b and b ~= "" then
            boundCount = boundCount + 1
        end
    end

    return {
        enabled = (sfui.db and sfui.db.Get and sfui.db.Get("ring", "enabled", true)) ~= false,
        providersCount = provCount,
        activeSlotsCount = activeSlotsCount,
        isShown = isShown,
        currentRing = currentRing,
        pendingCount = pendingCount,
        boundCount = boundCount,
    }
end
sfui.ring.GetDebugInfo = sfui.ring_debug_info
