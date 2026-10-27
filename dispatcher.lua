local addonName, addon = ...
sfui = sfui or {}

-- ============================================================================
-- SFUI Central Event Dispatcher
--
-- Single-frame event routing and throttled update management for the entire addon.
--
-- Usage:
--   sfui.events.RegisterEvent("EVENT_NAME", function(event, ...) end)
--   sfui.events.UnregisterEvent("EVENT_NAME", callback)
--   sfui.events.RegisterUnitEvent("UNIT_AURA", "player", callback)
--   sfui.events.RegisterUnitEvents({"UNIT_HEALTH", "UNIT_ABSORB_AMOUNT_CHANGED"}, "player", cb)
--   sfui.events.UnregisterUnitEvent("UNIT_AURA", "player", callback)
--   sfui.events.RegisterThrottledEvent("UPDATE_UI_WIDGET", 0.2, callback)
--   sfui.events.RegisterUpdate("name", interval, callback)
--
-- Architecture:
--   * Single Global Frame (`SfuiDispatcherFrame`) for non-unit game events.
--   * Isolated Per-Unit Frames (`SfuiDispatcherUnitFrame_<unit>`) for RegisterUnitEvent.
--   * Snapshot scratch table (`_snap`) prevents mid-dispatch mutation errors.
--   * Zero-overhead dispatch loop with conditional profiling (`_memActive`).
--   * Minimum update interval floor (0.005s ≈ 200fps) on all RegisterUpdate loops.
--
-- Subsystems & Routing Destinations:
--   Core & State:
--     • core.lua                    - Scale recalculation (UI_SCALE_CHANGED), master boot sequence.
--     • common.lua                  - Spec change cache, vehicle/flight state, out-of-combat queue.
--     • commands.lua                - Keybinding synchronization (UPDATE_BINDINGS).
--   Combat & UI Bars:
--     • frames/bars/bars.lua           - Player health, absorbs, power, runes, vigor, form changes.
--     • frames/bars/soulfragments.lua  - Demon Hunter soul fragments, fury changes, void decay.
--     • frames/bars/vehicle.lua        - Vehicle health/energy bars, action button keybinds.
--   Cooldown & Aura Tracking:
--     • frames/tracking/trackedbars.lua - Cooldown & aura status bars, spellcast edge mirrors.
--     • frames/tracking/trackedicons.lua- Cooldown & aura icon grid, charges, glow timeouts.
--   Objectives & Dungeons:
--     • frames/quests/quests.lua       - Quest log, objective tracker, scenario criteria, zone cache.
--     • frames/quests/mythic.lua       - M+ & Delve HUD, keystone receptacle, deaths (UNIT_DIED).
--   Gear & Loot:
--     • frames/gear/compare.lua        - Equipment auto-comparison CVar tracking.
--     • frames/gear/highest.lua        - Highest item level suggestions & weapon proficiencies.
--     • frames/gear/lootspec.lua       - Dynamic loot spec management.
--     • frames/gear/lootviewer.lua     - Encounter journal & mythic+ loot browser, spec/stat filters.
--   Utilities & Automation:
--     • frames/alts/alts.lua           - Warband alt sync, profession KP, recipes, trade skills.
--     • frames/automation/automation.lua - Master's Hammer repair popup, role checks, LFG auto-confirm.
--     • frames/merchant/merchant.lua   - Auto-junk selling & auto-repair vendor triggers.
--     • frames/automation/rankup.lua   - Auto spell rank upgrade on action bars (Camelot / Classic).
--     • frames/automation/transfer.lua - Warband bank transfer helper window.
--     • frames/research.lua            - Trait tree & research currency updates.
--     • frames/portals/portals.lua     - Combat close & portal list synchronization.
--     • frames/mem.lua                 - Real-time memory allocation profiling & watcher hooks.
-- ============================================================================

sfui.events = {}

-- ─── Locals ─────────────────────────────────────────────────────────────────

local eventCallbacks     = {}  -- [eventName] = { cb, cb, ... }
local updateCallbacks    = {}  -- { { name, interval, elapsed, callback }, ... }

local _issecretvalue = _G.issecretvalue

local function _safe_str(val)
    if _issecretvalue and _issecretvalue(val) then return "<secret>" end
    return tostring(val)
end

local function _err(ctx, msg)
    print("|cff6600ffsfui|r dispatcher error (" .. _safe_str(ctx) .. "): " .. _safe_str(msg))
end

-- ─── Callback source metadata & error dispatch ──────────────────────────────
local _cbMeta = setmetatable({}, { __mode = "k" })
local _curDispatchCtx = nil

local function _record_caller(cb, fallbackMod)
    if type(cb) ~= "function" or _cbMeta[cb] then return end
    local stack = debugstack(3, 1, 0)
    if stack and string.find(stack, "dispatcher%.lua") then
        stack = debugstack(4, 1, 0)
    end
    local file, line = string.match(stack or "", "[Aa]dd[Oo]ns/[Ss][Ff][Uu][Ii]/([^:]+%.lua):(%d+)")
    if file then
        local mod = string.match(file, "^frames/([^/]+)")
            or string.match(file, "^core/([^/]+)")
            or string.match(file, "^data/([^/]+)")
            or string.match(file, "^([^/%.]+)%.lua")
        _cbMeta[cb] = {
            module = mod or fallbackMod or "core",
            file = file,
            line = tonumber(line) or 0,
        }
    end
end

local function _dispatcher_error_handler(err)
    local stack = debugstack and debugstack(2, 20, 20)
    if _G.sfuibug and _G.sfuibug.RecordError then
        _G.sfuibug.RecordError(_curDispatchCtx, err, stack)
    elseif _G.CallErrorHandler then
        _G.CallErrorHandler(err)
    elseif _G.geterrorhandler and _G.geterrorhandler() then
        _G.geterrorhandler()(err)
    else
        local label = _curDispatchCtx and (_curDispatchCtx.label or _curDispatchCtx.event) or "dispatcher"
        _err(label, err)
    end
    return err
end


-- ─── Memory profiling ───────────────────────────────────────────────────────
-- Checked lazily: _memActive is false unless sfui.mem turns on the watcher.
-- This avoids 3 table lookups + a function call on every single event fire.
local _memActive = false
local function _mem_tick()
    _memActive = sfui.mem.IsWatcherActive()
end
local function _mem_after(key, before)
    local delta = collectgarbage("count") - before
    sfui.mem.RecordAllocation(key, delta > 0 and delta or 0)
end

-- ─── Re-entrant snapshot scratch pool ─────────────────────────────────────────
-- Pre-allocated stack of scratch tables reused across event and message dispatches.
-- Using a stack guarantees re-entrancy safety: if a callback fires another event,
-- triggers a unit event, or broadcasts a message via SendMessage mid-loop, each
-- nested dispatch level operates on its own isolated snapshot without clobbering
-- the outer dispatch loop.
-- Slots are nilled out immediately upon consumption so no strong references leak.
local _snapPool = {}
local _snapDepth = 0

local function _acquire_snap()
    _snapDepth = _snapDepth + 1
    local s = _snapPool[_snapDepth]
    if not s then
        s = {}
        _snapPool[_snapDepth] = s
    end
    return s
end

local function _release_snap()
    _snapDepth = _snapDepth - 1
end

local _snapUpdates = {}

-- Minimum interval (seconds) enforced on all RegisterUpdate callbacks.
-- Prevents runaway 0s loops while allowing high-refresh loops up to ~144-200fps.
local MIN_UPDATE_INTERVAL = 0.005

-- ─── Global event frame ─────────────────────────────────────────────────────
local ev_frame = CreateFrame("Frame", "SfuiDispatcherFrame")

ev_frame:SetScript("OnEvent", function(_, event, ...)
    local cbs = eventCallbacks[event]
    if not cbs or #cbs == 0 then return end

    local n = #cbs
    local snap = _acquire_snap()
    for i = 1, n do snap[i] = cbs[i] end

    if _memActive then
        local before = collectgarbage("count")
        for i = 1, n do
            local cb = snap[i]
            snap[i] = nil
            if type(cb) == "function" then
                local prevCtx = _curDispatchCtx
                local meta = _cbMeta[cb]
                _curDispatchCtx = meta or { event = event, label = event }
                _curDispatchCtx.event = event
                _curDispatchCtx.label = event
                xpcall(cb, _dispatcher_error_handler, event, ...)
                _curDispatchCtx = prevCtx
            end
        end
        _mem_after(event, before)
    else
        for i = 1, n do
            local cb = snap[i]
            snap[i] = nil
            if type(cb) == "function" then
                local prevCtx = _curDispatchCtx
                local meta = _cbMeta[cb]
                _curDispatchCtx = meta or { event = event, label = event }
                _curDispatchCtx.event = event
                _curDispatchCtx.label = event
                xpcall(cb, _dispatcher_error_handler, event, ...)
                _curDispatchCtx = prevCtx
            end
        end
    end
    _release_snap()
end)

local function _OnDispatcherUpdate(_, elapsed)
    local n = #updateCallbacks
    if n == 0 then return end

    if _memActive then
        for i = 1, n do
            _snapUpdates[i] = updateCallbacks[i]
        end
        for i = 1, n do
            local d = _snapUpdates[i]
            _snapUpdates[i] = nil
            if d and not d.removed and type(d.callback) == "function" then
                d.elapsed = d.elapsed + elapsed
                if d.elapsed >= d.interval then
                    local label = d.name or "UpdateLoop"
                    local before = collectgarbage("count")
                    local prevCtx = _curDispatchCtx
                    local meta = _cbMeta[d.callback]
                    _curDispatchCtx = meta or { label = label, event = "OnUpdate" }
                    _curDispatchCtx.label = label
                    _curDispatchCtx.event = "OnUpdate"
                    xpcall(d.callback, _dispatcher_error_handler, d.elapsed)
                    _curDispatchCtx = prevCtx
                    _mem_after(label, before)
                    d.elapsed = 0
                end
            end
        end
    else
        for i = 1, n do
            local d = updateCallbacks[i]
            if d and not d.removed and type(d.callback) == "function" then
                d.elapsed = d.elapsed + elapsed
                if d.elapsed >= d.interval then
                    local label = d.name or "UpdateLoop"
                    local prevCtx = _curDispatchCtx
                    local meta = _cbMeta[d.callback]
                    _curDispatchCtx = meta or { label = label, event = "OnUpdate" }
                    _curDispatchCtx.label = label
                    _curDispatchCtx.event = "OnUpdate"
                    xpcall(d.callback, _dispatcher_error_handler, d.elapsed)
                    _curDispatchCtx = prevCtx
                    d.elapsed = 0
                end
            end
        end
    end
end

-- ─── Unit event frames (per-unit isolation) ─────────────────────────────────
-- Each unit token (e.g. "player", "vehicle") gets its own dedicated Frame.
-- This is critical: WoW's C-API Frame:RegisterUnitEvent(event, unit) replaces
-- the registered unit for that event on that frame. If multiple units shared
-- a single frame, registering "vehicle" for UNIT_POWER_UPDATE would overwrite
-- and silence "player" for UNIT_POWER_UPDATE across the addon!
local unitFrames = {}         -- [unit] = Frame
local unitEventCallbacks = {} -- [unit] = { [eventName] = { cb1, cb2, ... } }

local function get_or_create_unit_frame(unit)
    local f = unitFrames[unit]
    if not f then
        f = CreateFrame("Frame", "SfuiDispatcherUnitFrame_" .. tostring(unit))
        unitFrames[unit] = f
        f:SetScript("OnEvent", function(_, event, u, ...)
            local eventCbs = unitEventCallbacks[unit] and unitEventCallbacks[unit][event]
            if not eventCbs or #eventCbs == 0 then return end
            local n = #eventCbs
            local snap = _acquire_snap()
            for i = 1, n do snap[i] = eventCbs[i] end

            if _memActive then
                local before = collectgarbage("count")
                for i = 1, n do
                    local cb = snap[i]
                    snap[i] = nil
                    if type(cb) == "function" then
                        local prevCtx = _curDispatchCtx
                        local meta = _cbMeta[cb]
                        _curDispatchCtx = meta or { event = event, label = event .. "/" .. tostring(u) }
                        _curDispatchCtx.event = event
                        _curDispatchCtx.label = event .. "/" .. tostring(u)
                        xpcall(cb, _dispatcher_error_handler, event, u, ...)
                        _curDispatchCtx = prevCtx
                    end
                end
                _mem_after(event, before)
            else
                for i = 1, n do
                    local cb = snap[i]
                    snap[i] = nil
                    if type(cb) == "function" then
                        local prevCtx = _curDispatchCtx
                        local meta = _cbMeta[cb]
                        _curDispatchCtx = meta or { event = event, label = event .. "/" .. tostring(u) }
                        _curDispatchCtx.event = event
                        _curDispatchCtx.label = event .. "/" .. tostring(u)
                        xpcall(cb, _dispatcher_error_handler, event, u, ...)
                        _curDispatchCtx = prevCtx
                    end
                end
            end
            _release_snap()
        end)
    end
    return f
end

-- ─── Public API ─────────────────────────────────────────────────────────────

--- Register a callback for a global game event.
--- If event == "PLAYER_LOGIN" and the player is already logged in, fires immediately.
function sfui.events.RegisterEvent(event, callback)
    if not event or type(callback) ~= "function" then return end
    _record_caller(callback)
    if event == "PLAYER_LOGIN" and IsLoggedIn() then
        local prevCtx = _curDispatchCtx
        _curDispatchCtx = _cbMeta[callback] or { event = "PLAYER_LOGIN", label = "PLAYER_LOGIN immediate" }
        _curDispatchCtx.event = "PLAYER_LOGIN"
        _curDispatchCtx.label = "PLAYER_LOGIN immediate"
        xpcall(callback, _dispatcher_error_handler, event)
        _curDispatchCtx = prevCtx
        return
    end

    if not eventCallbacks[event] then
        local ok = pcall(ev_frame.RegisterEvent, ev_frame, event)
        if not ok then
            -- Unknown or deprecated event in current client build; ignore safely
            return
        end
        eventCallbacks[event] = {}
    end
    local cbs = eventCallbacks[event]
    for i = 1, #cbs do
        if cbs[i] == callback then return end
    end
    cbs[#cbs + 1] = callback
end

--- Unregister a previously-registered callback.
function sfui.events.UnregisterEvent(event, callback)
    local cbs = eventCallbacks[event]
    if not cbs then return end
    for i = #cbs, 1, -1 do
        if cbs[i] == callback then table.remove(cbs, i) end
    end
    if #cbs == 0 then
        ev_frame:UnregisterEvent(event)
        eventCallbacks[event] = nil
    end
end

--- Register a callback for a unit-filtered game event.
--- Only fires when the event's unit argument matches the registered unit.
--- @param event    string     e.g. "UNIT_AURA"
--- @param unit     string     e.g. "player"
--- @param callback function(event, unit, ...)
function sfui.events.RegisterUnitEvent(event, unit, callback)
    if not unit or not event or not callback then return end
    _record_caller(callback)

    if not unitEventCallbacks[unit] then
        unitEventCallbacks[unit] = {}
    end
    if not unitEventCallbacks[unit][event] then
        unitEventCallbacks[unit][event] = {}
    end

    local cbs = unitEventCallbacks[unit][event]
    for i = 1, #cbs do
        if cbs[i] == callback then return end
    end
    cbs[#cbs + 1] = callback

    local f = get_or_create_unit_frame(unit)
    if #cbs == 1 then
        local ok = pcall(f.RegisterUnitEvent, f, event, unit)
        if not ok then
            table.remove(cbs)
            return
        end
    end
end

--- Register the same callback for multiple unit events in one call.
--- Equivalent to calling RegisterUnitEvent for each event individually.
--- Reduces boilerplate when several events share one handler and one unit.
--- @param events   table      e.g. {"UNIT_AURA", "UNIT_SPELLCAST_SUCCEEDED"}
--- @param unit     string     e.g. "player"
--- @param callback function(event, unit, ...)
function sfui.events.RegisterUnitEvents(events, unit, callback)
    for i = 1, #events do
        sfui.events.RegisterUnitEvent(events[i], unit, callback)
    end
end

--- Unregister a unit event callback.
function sfui.events.UnregisterUnitEvent(event, unit, callback)
    local cbs = unitEventCallbacks[unit] and unitEventCallbacks[unit][event]
    if not cbs then return end
    for i = #cbs, 1, -1 do
        if cbs[i] == callback then
            table.remove(cbs, i)
        end
    end
    if #cbs == 0 then
        if unitFrames[unit] then
            unitFrames[unit]:UnregisterEvent(event)
        end
        unitEventCallbacks[unit][event] = nil
    end
end

--- Unregister multiple unit events for a given unit and callback.
--- @param events   table      e.g. {"UNIT_AURA", "UNIT_SPELLCAST_SUCCEEDED"}
--- @param unit     string     e.g. "player"
--- @param callback function(event, unit, ...)
function sfui.events.UnregisterUnitEvents(events, unit, callback)
    for i = 1, #events do
        sfui.events.UnregisterUnitEvent(events[i], unit, callback)
    end
end

--- Register a throttled OnUpdate callback.
--- sfui.events.RegisterUpdate([name,] interval, callback)
--- Intervals below MIN_UPDATE_INTERVAL (0.005s ≈ 200fps) are clamped up.
function sfui.events.RegisterUpdate(arg1, arg2, arg3)
    local name, interval, callback
    if type(arg1) == "string" then
        name, interval, callback = arg1, arg2, arg3
    else
        interval, callback = arg1, arg2
    end
    interval = math.max(interval or 0, MIN_UPDATE_INTERVAL)
    _record_caller(callback)

    if name then
        for i = 1, #updateCallbacks do
            local d = updateCallbacks[i]
            if d and d.name == name then
                d.interval = interval
                d.callback = callback
                d.removed = nil
                return
            end
        end
    end

    updateCallbacks[#updateCallbacks + 1] = {
        name     = name,
        interval = interval,
        elapsed  = 0,
        callback = callback,
    }
    if #updateCallbacks == 1 then
        ev_frame:SetScript("OnUpdate", _OnDispatcherUpdate)
    end
end

--- Unregister an OnUpdate callback by name or function reference.
function sfui.events.UnregisterUpdate(target)
    if not target then return end
    for i = #updateCallbacks, 1, -1 do
        local d = updateCallbacks[i]
        if d and (d.name == target or d.callback == target) then
            d.removed = true
            table.remove(updateCallbacks, i)
        end
    end
    if #updateCallbacks == 0 then
        ev_frame:SetScript("OnUpdate", nil)
    end
end

--- Register an event callback that fires at most once every `interval` seconds.
--- If the event bursts (fires multiple times within the window), intermediate
--- fires are dropped — only the most-recent dispatch goes through.
--- Returns the wrapper function so the caller can pass it to UnregisterEvent.
---
--- Usage:
---   local handle = sfui.events.RegisterThrottledEvent("CURRENCY_DISPLAY_UPDATE", 0.2, myFn)
---   sfui.events.UnregisterEvent("CURRENCY_DISPLAY_UPDATE", handle)  -- to remove
function sfui.events.RegisterThrottledEvent(event, interval, callback)
    local lastFired = 0
    local wrapper = function(ev, ...)
        local now = GetTime()
        if now - lastFired >= interval then
            lastFired = now
            callback(ev, ...)
        end
    end
    sfui.events.RegisterEvent(event, wrapper)
    return wrapper
end

--- Register a unit event callback that fires at most once every `interval` seconds for that unit.
--- If the event bursts within the window, intermediate fires are dropped.
--- Returns the wrapper function so the caller can pass it to UnregisterUnitEvent or UnregisterThrottledUnitEvent.
---
--- Usage:
---   local handle = sfui.events.RegisterThrottledUnitEvent("UNIT_AURA", "player", 0.1, myFn)
---   sfui.events.UnregisterUnitEvent("UNIT_AURA", "player", handle)  -- to remove
function sfui.events.RegisterThrottledUnitEvent(event, unit, interval, callback)
    if not unit or not event or not callback then return end
    local lastFired = 0
    local wrapper = function(ev, u, ...)
        local now = GetTime()
        if now - lastFired >= interval then
            lastFired = now
            callback(ev, u, ...)
        end
    end
    sfui.events.RegisterUnitEvent(event, unit, wrapper)
    return wrapper
end

--- Unregister a throttled unit event callback.
function sfui.events.UnregisterThrottledUnitEvent(event, unit, handle)
    sfui.events.UnregisterUnitEvent(event, unit, handle)
end

--- Register an event callback that is debounced (trailing-edge):
--- When bursts of events occur, the timer resets on each event,
--- and callback(event, ...) executes once after delay seconds of silence.
--- Returns the wrapper function so the caller can pass it to UnregisterEvent.
---
--- Usage:
---   local handle = sfui.events.RegisterDebouncedEvent("SPELLS_CHANGED", 0.25, myFn)
---   sfui.events.UnregisterEvent("SPELLS_CHANGED", handle)  -- to remove
function sfui.events.RegisterDebouncedEvent(event, delay, callback)
    if not event or not callback then return end
    delay = (type(delay) == "number" and delay > 0 and delay) or 0.15
    local timer = nil
    local lastA1, lastA2, lastA3

    local onTimerFired = function()
        timer = nil
        local a, b, c = lastA1, lastA2, lastA3
        lastA1, lastA2, lastA3 = nil, nil, nil
        callback(event, a, b, c)
    end

    local wrapper = function(ev, a1, a2, a3)
        lastA1, lastA2, lastA3 = a1, a2, a3
        if timer then
            timer:Cancel()
            timer = nil
        end
        local C_Timer = _G.C_Timer
        if C_Timer and C_Timer.NewTimer then
            timer = C_Timer.NewTimer(delay, onTimerFired)
        else
            callback(ev, a1, a2, a3)
        end
    end
    sfui.events.RegisterEvent(event, wrapper)
    return wrapper
end

--- Register a unit event callback that is debounced (trailing-edge) for that unit.
function sfui.events.RegisterDebouncedUnitEvent(event, unit, delay, callback)
    if not unit or not event or not callback then return end
    delay = (type(delay) == "number" and delay > 0 and delay) or 0.15
    local timer = nil
    local lastA1, lastA2, lastA3

    local onTimerFired = function()
        timer = nil
        local a, b, c = lastA1, lastA2, lastA3
        lastA1, lastA2, lastA3 = nil, nil, nil
        callback(event, unit, a, b, c)
    end

    local wrapper = function(ev, u, a1, a2, a3)
        lastA1, lastA2, lastA3 = a1, a2, a3
        if timer then
            timer:Cancel()
            timer = nil
        end
        local C_Timer = _G.C_Timer
        if C_Timer and C_Timer.NewTimer then
            timer = C_Timer.NewTimer(delay, onTimerFired)
        else
            callback(ev, u, a1, a2, a3)
        end
    end
    sfui.events.RegisterUnitEvent(event, unit, wrapper)
    return wrapper
end

-- ─── Internal Pub/Sub Messaging ───────────────────────────────────────────
local messageCallbacks = {}   -- [messageName] = { cb1, cb2, ... }

--- Register a callback for an internal addon message.
--- Callback signature: function(message, ...)
function sfui.events.RegisterMessage(message, callback)
    if not message or type(callback) ~= "function" then return end
    _record_caller(callback)
    if not messageCallbacks[message] then
        messageCallbacks[message] = {}
    end
    local cbs = messageCallbacks[message]
    for i = 1, #cbs do
        if cbs[i] == callback then return end
    end
    cbs[#cbs + 1] = callback
end

--- Unregister a previously-registered message callback.
function sfui.events.UnregisterMessage(message, callback)
    local cbs = messageCallbacks[message]
    if not cbs then return end
    for i = #cbs, 1, -1 do
        if cbs[i] == callback then
            table.remove(cbs, i)
        end
    end
    if #cbs == 0 then
        messageCallbacks[message] = nil
    end
end

--- Send an internal addon message to all registered listeners.
--- Uses snapshotting and pcall isolation.
function sfui.events.SendMessage(message, ...)
    local cbs = messageCallbacks[message]
    if not cbs or #cbs == 0 then return end

    local n = #cbs
    local snap = _acquire_snap()
    for i = 1, n do snap[i] = cbs[i] end

    if _memActive then
        local before = collectgarbage("count")
        for i = 1, n do
            local cb = snap[i]
            snap[i] = nil
            if type(cb) == "function" then
                local prevCtx = _curDispatchCtx
                local meta = _cbMeta[cb]
                local label = "Msg:" .. tostring(message)
                _curDispatchCtx = meta or { event = label, label = label }
                _curDispatchCtx.event = label
                _curDispatchCtx.label = label
                xpcall(cb, _dispatcher_error_handler, message, ...)
                _curDispatchCtx = prevCtx
            end
        end
        _mem_after("Msg:" .. tostring(message), before)
    else
        for i = 1, n do
            local cb = snap[i]
            snap[i] = nil
            if type(cb) == "function" then
                local prevCtx = _curDispatchCtx
                local meta = _cbMeta[cb]
                local label = "Msg:" .. tostring(message)
                _curDispatchCtx = meta or { event = label, label = label }
                _curDispatchCtx.event = label
                _curDispatchCtx.label = label
                xpcall(cb, _dispatcher_error_handler, message, ...)
                _curDispatchCtx = prevCtx
            end
        end
    end
    _release_snap()
end

--- Called by sfui.mem when its watcher starts or stops, to update the hot-path flag.
function sfui.events.SetMemProfiling(active)
    _memActive = active and true or false
end

sfui.events.RegisterCallback = sfui.events.RegisterMessage
sfui.RegisterCallback = sfui.events.RegisterMessage
sfui.RegisterMessage = sfui.events.RegisterMessage
sfui.SendMessage = sfui.events.SendMessage

-- Sync flag once on login in case the watcher was enabled during init.
sfui.events.RegisterEvent("PLAYER_LOGIN", _mem_tick)

local _dispDebug = {}
function sfui.dispatcher_debug_info()
    local totalGlobalEvents = 0
    local totalGlobalCbs = 0
    for _, cbs in pairs(eventCallbacks) do
        totalGlobalEvents = totalGlobalEvents + 1
        totalGlobalCbs = totalGlobalCbs + #cbs
    end

    local totalUnitEvents = 0
    local totalUnitCbs = 0
    local totalUnits = 0
    for _, evs in pairs(unitEventCallbacks) do
        totalUnits = totalUnits + 1
        for _, cbs in pairs(evs) do
            totalUnitEvents = totalUnitEvents + 1
            totalUnitCbs = totalUnitCbs + #cbs
        end
    end

    local totalMessages = 0
    local totalMsgCbs = 0
    for _, cbs in pairs(messageCallbacks) do
        totalMessages = totalMessages + 1
        totalMsgCbs = totalMsgCbs + #cbs
    end

    _dispDebug.globalEvents = totalGlobalEvents
    _dispDebug.globalCallbacks = totalGlobalCbs
    _dispDebug.units = totalUnits
    _dispDebug.unitEvents = totalUnitEvents
    _dispDebug.unitCallbacks = totalUnitCbs
    _dispDebug.messages = totalMessages
    _dispDebug.messageCallbacks = totalMsgCbs
    _dispDebug.updateLoops = #updateCallbacks
    _dispDebug.memProfiling = _memActive
    return _dispDebug
end

function sfui.events.GetUpdateCallbacks()
    return updateCallbacks
end

function sfui.events.GetEventCallbacks()
    return eventCallbacks
end

function sfui.events.GetUnitEventCallbacks()
    return unitEventCallbacks
end

function sfui.events.GetDispatcherFrame()
    return ev_frame
end
