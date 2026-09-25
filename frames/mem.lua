local addonName, addon = ...
sfui = sfui or {}
sfui.mem = {}

local cfg = sfui.config
local common = sfui.common

local _G = _G
local print = print
local pairs = pairs
local ipairs = ipairs
local type = type
local tostring = tostring
local tonumber = tonumber
local string_format = string.format
local table_sort = table.sort
local table_insert = table.insert
local math_max = math.max
local math_min = math.min
local math_floor = math.floor
local math_ceil = math.ceil
local GetTime = GetTime
local collectgarbage = collectgarbage
local UpdateAddOnMemoryUsage = UpdateAddOnMemoryUsage
local GetAddOnMemoryUsage = GetAddOnMemoryUsage
local CreateFrame = CreateFrame
local UIParent = UIParent
local UISpecialFrames = UISpecialFrames
local C_Timer = C_Timer
local wipe = table.wipe or _G.wipe or function(t) for k in pairs(t) do t[k] = nil end end

local PREFIX = "|cff6600ff[sfui memory]|r "

-- Helper: Format memory size in lowercase
local function FormatKB(kb)
    if not kb then return "0 kb" end
    if kb >= 1024 then
        return string_format("%.2f mb", kb / 1024)
    else
        return string_format("%.1f kb", kb)
    end
end

-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- 1. COMPREHENSIVE MODULE POOL & CACHE INSPECTOR (All Lowercase)
-- ---------------------------------------------------------------------------
local function GetDebug(globalName, modName)
    local fn = sfui[globalName]
    if fn and type(fn) == "function" then
        local ok, res = pcall(fn)
        if ok and type(res) == "table" then
            return res
        end
    end
    if sfui.modules and modName and sfui.modules[modName] and sfui.modules[modName].GetDebugInfo then
        local ok, res = pcall(function() return sfui.modules[modName]:GetDebugInfo() end)
        if ok and type(res) == "table" then
            return res
        end
    end
    return nil
end

function sfui.mem.GetModuleStats()
    local stats = {}

    -- Quests Module (Unified Tracker Engine)
    local qStats = {
        name = "quests tracker",
        status = "|cff888888idle|r",
        line1 = "blocks: 0 act / 0 pool • lines: 0 act / 0 pool",
        line2 = "headers: 0 act / 0 pool • bars: 0 act • 0 mods",
    }
    local q = GetDebug("questlog_debug_info", "quests") or GetDebug("questlog_debug_info", "questlog")
    if q then
        local bAct   = tonumber(q.blocksActive  or q.activeRows) or 0
        local bPool  = tonumber(q.blocksPooled  or q.rowPool) or 0
        local lAct   = tonumber(q.linesActive   or q.activeObjs) or 0
        local lPool  = tonumber(q.linesPooled   or q.objPool) or 0
        local hAct   = tonumber(q.headersActive) or 0
        local hPool  = tonumber(q.headersPooled) or 0
        local barAct = tonumber(q.barsActive) or 0
        local barPool= tonumber(q.barsPooled) or 0
        local items  = tonumber(q.itemsActive) or 0
        local numMods= tonumber(q.activeModules or q.modules) or 0

        if q.isSuppressed then
            qStats.status = "|cffff9900suppressed|r"
        elseif bAct > 0 then
            qStats.status = "|cff00ff88active|r"
        else
            qStats.status = "|cff888888idle|r"
        end

        qStats.line1 = string_format("blocks: %d act / %d pool • lines: %d act / %d pool", bAct, bPool, lAct, lPool)
        qStats.line2 = string_format("headers: %d/%d • bars: %d/%d • items: %d • %d mods", hAct, hPool, barAct, barPool, items, numMods)
    end
    stats["quests"] = qStats

    -- Mythic & Delves Module
    local mythicStats = {
        name = "mythic+ & delves",
        status = "|cff888888idle|r",
        line1 = "pools: spell=0, curr=0, death=0",
        line2 = "roster: 0 tracked • badges: 0 pool",
    }
    local m = GetDebug("mythic_debug_info", "mythic")
    if m then
        local inDungeon = (tonumber(m.playerList) or 0) > 0
        mythicStats.status = inDungeon and "|cff00ff88in instance|r" or "|cff888888idle|r"
        mythicStats.line1 = string_format("pools: spell=%d, curr=%d, death=%d", tonumber(m.spellPool) or 0, tonumber(m.currencyPool) or 0, tonumber(m.deathPool) or 0)
        mythicStats.line2 = string_format("roster: %d • badges: %d • spells: %d", tonumber(m.playerList) or 0, tonumber(m.badgePool) or 0, tonumber(m.spellTooltips) or 0)
    end
    stats["mythic"] = mythicStats

    -- Tracked Bars Module
    local tbStats = {
        name = "tracked bars",
        status = "|cff888888idle|r",
        line1 = "bars: 0 active / 0 shown",
        line2 = "pools: 0 frames, 0 configs",
    }
    local tb = GetDebug("trackedbars_debug_info", "trackedbars")
    if tb then
        tbStats.status = tb.loopActive and "|cff00ff88combat loop|r" or "|cff888888paused (ooc)|r"
        tbStats.line1 = string_format("bars: %d active / %d shown", tonumber(tb.activeBars) or 0, tonumber(tb.shownBars) or 0)
        tbStats.line2 = string_format("pools: frames=%d, cfg=%d • dirty=%s", tonumber(tb.barPool) or 0, tonumber(tb.configPool) or 0, tb.isDirty and "yes" or "no")
    end
    stats["trackedbars"] = tbStats

    -- Tracked Icons Module
    local tiStats = {
        name = "tracked icons",
        status = "|cff888888idle|r",
        line1 = "panels: 0 • icons: 0",
        line2 = "glows: 0 • cd cache: 0",
    }
    local ti = GetDebug("trackedicons_debug_info", "trackedicons")
    if ti then
        tiStats.status = (tonumber(ti.icons) or 0) > 0 and "|cff00ff88active|r" or "|cff888888idle|r"
        tiStats.line1 = string_format("panels: %d • total icons: %d", tonumber(ti.panels) or 0, tonumber(ti.icons) or 0)
        tiStats.line2 = string_format("glows: %d • cd cache: %d • dirty=%s", tonumber(ti.activeGlows) or 0, tonumber(ti.cdCache) or 0, (ti.needsState or ti.needsLayout) and "yes" or "no")
    end
    stats["trackedicons"] = tiStats


    -- World Events Module
    local weStats = {
        name = "world events",
        status = "|cff888888idle|r",
        line1 = "events: 0 active • reminders: 0",
        line2 = "pois: 0 on map • engine: unified",
    }
    local w = GetDebug("worldevents_debug_info", "worldevents")
    if w then
        weStats.status = (w.activeEvents or 0) > 0 and "|cff00ff88active|r" or "|cff888888idle|r"
        weStats.line1 = string_format("events: %d active • reminders: %d", w.activeEvents or 0, w.reminders or 0)
        weStats.line2 = string_format("pois: %d on map • engine: unified", w.poiCount or 0)
    end
    stats["worldevents"] = weStats

    -- Unit Bars Module
    local barsStats = {
        name = "unit health & power",
        status = "|cff00ff88active|r",
        line1 = "health: shown • power: shown",
        line2 = "mount ticker: idle • events: filtered",
    }
    local b = GetDebug("bars_debug_info", "bars")
    if b then
        barsStats.line1 = string_format("bar0: %s • bar1: %s • runes: %s", b.bar0Shown and "shown" or "off", b.bar1Shown and "shown" or "off", b.runeBarCreated and "ready" or "off")
        barsStats.line2 = string_format("mount ticker: %s • unit filtered", b.mountSpeedActive and "|cff00ff88gliding|r" or "sleeping")
    end
    stats["bars"] = barsStats


    -- Gear Manager Module
    local gearStats = {
        name = "gear manager",
        status = "|cff00ff88active|r",
        line1 = "equipped cache: 18 slots",
        line2 = "tracked items: 18 • zero churn",
    }
    local gInfo = GetDebug("gear_debug_info", "gear")
    if gInfo then
        gearStats.line1 = string_format("equipped cache: %d slots", tonumber(gInfo.equippedCache) or 0)
        gearStats.line2 = string_format("tracked items: %d • static closures", tonumber(gInfo.lastEquipped) or 0)
    end
    stats["gear"] = gearStats

    -- Stats Module
    local statsMod = {
        name = "stat summary",
        status = "|cff00ff88ready|r",
        line1 = "spec priority caches: 0",
        line2 = "pawn stat strings: 0",
    }
    local s = GetDebug("stats_debug_info", "stats")
    if s then
        statsMod.line1 = string_format("spec priority caches: %d", tonumber(s.cachedSpecOrders) or 0)
        statsMod.line2 = string_format("pawn stat strings: %d", tonumber(s.pawnOrders) or 0)
    end
    stats["stats"] = statsMod

    -- Alts Manager Module
    local altsMod = {
        name = "alts & vault",
        status = "|cff888888closed|r",
        line1 = "tracked characters: 0",
        line2 = "pools: col=0, cell=0, tab=0",
    }
    local a = GetDebug("alts_debug_info", "alts")
    if a then
        altsMod.status = a.frameShown and "|cff00ff88open|r" or "|cff888888closed|r"
        altsMod.line1 = string_format("tracked characters: %d", tonumber(a.trackedAlts) or 0)
        altsMod.line2 = string_format("pools: col=%d, cell=%d, tab=%d", tonumber(a.columnPool) or 0, tonumber(a.cellPool) or 0, tonumber(a.tablePool) or 0)
    end
    stats["alts"] = altsMod

    -- Merchant & Junk Module
    local merchMod = {
        name = "merchant 4x7 grid",
        status = "|cff888888closed|r",
        line1 = "frame: ready",
        line2 = "table pool: 0",
    }
    local m = GetDebug("merchant_debug_info", "merchant")
    if m then
        merchMod.status = m.frameShown and "|cff00ff88open|r" or "|cff888888closed|r"
        merchMod.line1 = string_format("frame: %s", m.frameCreated and "ready" or "none")
        merchMod.line2 = string_format("table pool: %d tables", tonumber(m.tablePool) or 0)
    end
    stats["merchant"] = merchMod

    -- Portals Module
    local portMod = {
        name = "portals & flyouts",
        status = "|cff888888closed|r",
        line1 = "panel: ready",
        line2 = "action overlays: static",
    }
    local p = GetDebug("portals_debug_info", "portals")
    if p then
        portMod.status = p.frameShown and "|cff00ff88open|r" or "|cff888888closed|r"
        portMod.line1 = string_format("panel: %s", p.frameCreated and "ready" or "none")
        portMod.line2 = "overlays: static shared frame"
    end
    stats["portals"] = portMod

    -- Castbars Module
    local cbMod = {
        name = "castbars",
        status = "|cff00ff88ready|r",
        line1 = "player: idle • target: idle",
        line2 = "engine: curve animation",
    }
    local cb = GetDebug("castbar_debug_info", "castbar")
    if cb then
        cbMod.line1 = string_format("player: %s • target: %s", cb.playerBarShown and "|cff00ff88casting|r" or "idle", cb.targetBarShown and "|cff00ff88casting|r" or "idle")
        cbMod.line2 = "haste cache: secret-safe"
    end
    stats["castbars"] = cbMod

    -- Minimap Module
    local miniMod = {
        name = "minimap collector",
        status = "|cff00ff88active|r",
        line1 = "buttons collected: 0",
        line2 = "auto-zoom: idle",
    }
    local mm = GetDebug("minimap_debug_info", "minimap")
    if mm then
        miniMod.line1 = string_format("buttons collected: %d", tonumber(mm.buttonCount) or 0)
        miniMod.line2 = string_format("auto-zoom: %s", mm.autoZoomActive and "|cff00ff88running|r" or "idle")
    end
    stats["minimap"] = miniMod

    -- Glow Effects Module
    local glowMod = {
        name = "glow engine",
        status = "|cff00ff88ready|r",
        line1 = "libcustomglow: ready",
        line2 = "active glow tracker: gated",
    }
    local gInfo = GetDebug("glows_debug_info", "glows")
    if gInfo then
        glowMod.line1 = string_format("libcustomglow-1.0: %s", gInfo.lcgAvailable and "|cff00ff88ok|r" or "|cffff0000missing|r")
        glowMod.line2 = "idle loop gating: enabled"
    end
    stats["glows"] = glowMod

    -- Automation Module
    local autoMod = {
        name = "automation",
        status = "|cff00ff88active|r",
        line1 = "auto-release: off • auto-role: off",
        line2 = "auto-sign: off • skip cine: off",
    }
    local a = GetDebug("automation_debug_info", "automation")
    if a then
        autoMod.line1 = string_format("auto-release: %s • auto-role: %s", a.autoRelease and "|cff00ff88on|r" or "off", a.autoRoleCheck and "|cff00ff88on|r" or "off")
        autoMod.line2 = string_format("auto-sign: %s • skip cine: %s", a.autoSignLfg and "|cff00ff88on|r" or "off", a.skipCinematics and "|cff00ff88on|r" or "off")
    end
    stats["automation"] = autoMod

    -- Cursor Ring Module
    local curMod = {
        name = "cursor ring",
        status = "|cff888888disabled|r",
        line1 = "frame: none",
        line2 = "scale: 1.0",
    }
    local cur = GetDebug("cursor_debug_info", "cursor")
    if cur then
        curMod.status = cur.enabled and "|cff00ff88enabled|r" or "|cff888888disabled|r"
        curMod.line1 = string_format("frame: %s (shown: %s)", cur.frameCreated and "ready" or "none", cur.frameShown and "yes" or "no")
        curMod.line2 = "scale cache: cached uiparent"
    end
    stats["cursor"] = curMod

    -- Vehicle Module
    local vehMod = {
        name = "vehicle action bar",
        status = "|cff888888idle|r",
        line1 = "frame: ready • btns: 0",
        line2 = "health: off • power: off • cast: off",
    }
    local v = GetDebug("vehicle_debug_info", "vehicle")
    if v then
        vehMod.status = v.frameShown and "|cff00ff88active|r" or "|cff888888idle|r"
        vehMod.line1 = string_format("frame: %s • btns: %d • unit: %s", v.frameCreated and "ready" or "none", tonumber(v.visibleButtons) or 0, tostring(v.currentUnit or "none"))
        vehMod.line2 = string_format("health: %s • power: %s • cast: %s", v.healthShown and "|cff00ff88on|r" or "off", v.powerShown and "|cff00ff88on|r" or "off", v.castShown and "|cff00ff88on|r" or "off")
    end
    stats["vehicle"] = vehMod

    -- Currency Transfer Module
    local transMod = {
        name = "currency transfer",
        status = "|cff888888idle|r",
        line1 = "queue: 0 tasks",
        line2 = "ticker: inactive",
    }
    local t = GetDebug("transfer_debug_info", "transfer")
    if t then
        transMod.status = t.active and "|cff00ff88active|r" or "|cff888888idle|r"
        transMod.line1 = string_format("scan queue: %d tasks", tonumber(t.queueSize) or 0)
        transMod.line2 = string_format("ticker: %s", t.active and "|cff00ff88processing|r" or "inactive")
    end
    stats["transfer"] = transMod

    -- Soul Fragments (Demon Hunter) Module
    local sfStats = {
        name = "soul fragments",
        status = "|cff888888idle|r",
        line1 = "bar: none • binder: none",
        line2 = "stacks: 0 • cap: 0",
    }
    local sf = GetDebug("soulfragments_debug_info", "soulfragments")
    if sf then
        sfStats.status = sf.frameShown and "|cff00ff88active|r" or (sf.frameCreated and "|cff888888hidden|r" or "|cff888888disabled|r")
        sfStats.line1 = string_format("bar: %s • binder: %s", sf.frameShown and "shown" or (sf.frameCreated and "ready" or "off"), sf.engineBound and "|cff00ff88c++ engine|r" or (sf.cdmCached and "cdm cached" or "lua multi-tier"))
        sfStats.line2 = string_format("stacks: %s • cap: %d • dividers: %d", tostring(sf.lastStacks or 0), tonumber(sf.maxCap) or 0, tonumber(sf.dividers) or 0)
    end
    stats["soulfragments"] = sfStats

    -- Event Dispatcher Module
    local dispMod = {
        name = "event dispatcher",
        status = "|cff00ff88active|r",
        line1 = "events: 0 global • 0 unit",
        line2 = "update tickers: 0 loops • zero churn",
    }
    local d = GetDebug("dispatcher_debug_info", "dispatcher")
    if d then
        dispMod.line1 = string_format("events: %d global (%d cbs) • %d unit (%d cbs)", tonumber(d.globalEvents) or 0, tonumber(d.globalCallbacks) or 0, tonumber(d.unitEvents) or 0, tonumber(d.unitCallbacks) or 0)
        dispMod.line2 = string_format("update tickers: %d loops • unit frames: %d", tonumber(d.updateLoops) or 0, tonumber(d.units) or 0)
    end
    stats["dispatcher"] = dispMod

    -- Currency & Item Trackers Module
    local currMod = {
        name = "currency & item bars",
        status = "|cff888888idle|r",
        line1 = "currency: none • item: none",
        line2 = "backpack anchor: character frame",
    }
    local cInfo = GetDebug("currency_debug_info", "currency")
    if cInfo then
        local ready = cInfo.currencyFrameCreated or cInfo.itemFrameCreated
        currMod.status = ready and "|cff00ff88ready|r" or "|cff888888idle|r"
        currMod.line1 = string_format("currency bar: %s • item bar: %s", cInfo.currencyFrameCreated and "ready" or "none", cInfo.itemFrameCreated and "ready" or "none")
    end
    stats["currency"] = currMod

    -- Loot Spec & Browser Module
    local lootMod = {
        name = "loot spec & browser",
        status = "|cff888888idle|r",
        line1 = "auto-swap: off • default: current",
        line2 = "browser: none • cards: 0 • icons: 0",
    }
    local l = GetDebug("lootspec_debug_info", "lootspec")
    if l then
        lootMod.status = l.enabled and "|cff00ff88enabled|r" or "|cff888888disabled|r"
        local defName = "current"
        if l.defaultSpec and l.defaultSpec ~= 0 then
            local n = sfui.common and sfui.common.get_spec_name and sfui.common.get_spec_name(l.defaultSpec)
            if n then defName = n end
        end
        lootMod.line1 = string_format("auto-swap: %s • default: %s", l.enabled and "|cff00ff88on|r" or "|cff888888off|r", defName)
        lootMod.line2 = string_format("browser: %s • cards: %d • icons: %d", l.frameShown and "|cff00ff88open|r" or (l.frameCreated and "ready" or "none"), tonumber(l.cardPoolCount) or 0, tonumber(l.iconPoolCount) or 0)
    end
    stats["lootspec"] = lootMod

    -- Location & Keystone Reminder Module
    local locMod = {
        name = "keystone reminder",
        status = "|cff888888idle|r",
        line1 = "roster watcher: idle",
        line2 = "dungeon status: ready",
    }
    local loc = GetDebug("location_debug_info", "location")
    if loc then
        locMod.status = loc.enabled and (loc.watchingRoster and "|cff00ff88watching|r" or "|cff888888idle|r") or "|cff888888disabled|r"
        locMod.line1 = string_format("roster watcher: %s", loc.watchingRoster and "|cff00ff88active|r" or "idle")
        locMod.line2 = string_format("pending group: %s • reminder: %s", loc.pendingDungeon and "yes" or "none", loc.enabled and "on" or "off")
    end
    stats["location"] = locMod

    -- Cooldown Manager (CDM) Drag-Drop Module
    local cdmMod = {
        name = "cdm layout manager",
        status = "|cff888888idle|r",
        line1 = "editor: closed",
        line2 = "active drop zones: 0",
    }
    local cdm = GetDebug("cdm_debug_info", "cdm")
    if cdm then
        cdmMod.status = cdm.frameShown and "|cff00ff88editor open|r" or (cdm.frameCreated and "|cff888888ready|r" or "|cff888888idle|r")
        cdmMod.line1 = string_format("editor frame: %s (shown: %s)", cdm.frameCreated and "ready" or "none", cdm.frameShown and "yes" or "no")
        local blizzHidden = sfui.common and sfui.common.are_blizzard_cooldown_viewers_hidden and sfui.common.are_blizzard_cooldown_viewers_hidden()
        cdmMod.line2 = string_format("active zones: %d • blizz hidden: %s", tonumber(cdm.activeZones) or 0, blizzHidden and "|cff00ff88yes|r" or "|cffff4444no|r")
    end
    stats["cdm"] = cdmMod

    -- Research & Talent Trees Module
    local resMod = {
        name = "research tree browser",
        status = "|cff888888closed|r",
        line1 = "side frame: none",
        line2 = "trees: 4 expansions",
    }
    local r = GetDebug("research_debug_info", "research")
    if r then
        resMod.status = r.frameShown and "|cff00ff88open|r" or "|cff888888closed|r"
        resMod.line1 = string_format("side frame: %s", r.frameCreated and "ready" or "none")
    end
    stats["research"] = resMod

    -- Fishing Automation Module
    local fishStats = {
        name = "fishing automation",
        status = "|cff888888idle|r",
        line1 = "keys: unarm • skill: none",
        line2 = "audio boost: off • soft target: off",
    }
    local f = GetDebug("fishing_debug_info", "fishing")
    if f then
        fishStats.status = f.isFishing and "|cff00ff88casting / reeling|r" or (f.enabled and "|cff00ff88armed|r" or "|cff888888disabled|r")
        local keyList = {}
        if type(f.boundKeys) == "table" then
            for _, k in ipairs(f.boundKeys) do
                if type(k) == "string" or type(k) == "number" then
                    keyList[#keyList + 1] = tostring(k)
                end
            end
        end
        local keysStr = #keyList > 0 and table.concat(keyList, ",") or "none"
        fishStats.line1 = string_format("skill: %s (id: %s) • keys: %s", f.hasSkill and "|cff00ff88learned|r" or "|cff888888unlearned|r", tostring(f.knownSpellID or "none"), keysStr)
        fishStats.line2 = string_format("audio: %s • soft: %s • auto-loot: %s", f.enhanceSounds and (f.soundsEnhanced and "|cff00ff88active|r" or "on") or "off", f.softTarget and "on" or "off", f.autoLoot and "on" or "off")
    end
    stats["fishing"] = fishStats

    -- Companion Pet Manager Module
    local petStats = {
        name = "companion pet manager",
        status = "|cff888888idle|r",
        line1 = "favs: 0 • hist: 0",
        line2 = "rot: 720s • summoned: none",
    }
    local p = GetDebug("pets_debug_info", "pets")
    if p then
        petStats.status = p.enabled and "|cff00ff88active|r" or "|cff888888disabled|r"
        local poolType = p.isCharFavs and "char (" .. (p.charFavsCount or 0) .. ")" or "account"
        petStats.line1 = string_format("favs: %d [%s] • hist: %d", tonumber(p.poolFavsCount) or 0, poolType, tonumber(p.historyCount) or 0)
        petStats.line2 = string_format("rot: %ds • summoned: %s", tonumber(p.rotationTimer) or 720, p.currentPet and "|cff00ff88yes|r" or "none")
    end
    stats["pets"] = petStats

    -- Auto Combat Log Module
    local logStats = {
        name = "combat logging",
        status = "|cff888888idle|r",
        line1 = "auto log: off • current: no",
        line2 = "instance: none • engine: loggingcombat",
    }
    local l = GetDebug("logs_debug_info", "logs")
    if l then
        logStats.status = l.isLogging and "|cff00ff88logging active|r" or (l.enabled and "|cff00ff88monitoring|r" or "|cff888888disabled|r")
        logStats.line1 = string_format("auto log: %s • current: %s", l.enabled and "on" or "off", l.isLogging and "|cff00ff88yes|r" or "no")
        logStats.line2 = string_format("instance: %s • sfui started: %s", tostring(l.instanceType or "none"), l.sfuiStarted and "yes" or "no")
    end
    stats["logs"] = logStats

    -- Master's Hammer Module
    local hamStats = {
        name = "master's hammer",
        status = "|cff888888idle|r",
        line1 = "hammer: none",
        line2 = "carried: 0 hammers",
    }
    local h = GetDebug("hammer_debug_info", "hammer")
    if h then
        hamStats.status = h.hasHammer and "|cff00ff88ready|r" or "|cff888888not found|r"
        hamStats.line1 = string_format("hammer: %s (id: %s)", h.hasHammer and "|cff00ff88found|r" or "none", tostring(h.hammerItemID or "none"))
        hamStats.line2 = string_format("carried: %d • popup: %s", tonumber(h.carriedCount) or 0, h.popupShown and "|cff00ff88open|r" or "closed")
    end
    stats["hammer"] = hamStats

    -- Bonus Roll & Vault Module
    local brStats = {
        name = "bonus roll & vault",
        status = "|cff888888idle|r",
        line1 = "pending rolls: 0",
        line2 = "engine: keystone/loot mappings",
    }
    local br = GetDebug("bonusroll_debug_info", "bonusroll")
    if br then
        brStats.status = "|cff00ff88ready|r"
        brStats.line1 = string_format("pending rolls: %d • checked: %s", tonumber(br.pendingRolls) or 0, br.checked and "yes" or "no")
    end
    stats["bonusroll"] = brStats

    return stats
end

-- ---------------------------------------------------------------------------
-- 2. REAL-TIME ALLOCATION WATCHER BACKEND & MEMORY SCAN THROTTLER
-- ---------------------------------------------------------------------------
local watcherActive = false
local watcherTimer = nil
local watcherData = {}
local watcherStartTime = 0
local watcherDuration = 10
local watcherStartAddonMem = 0
local watcherStartLuaMem = 0
local watcherLastReport = nil

local lastMemoryScanTime = 0
local cachedAddonMem = 0

local function RefreshAddonMemory(force)
    local now = GetTime()
    -- Only trigger Blizzard's synchronous heap traversal if explicitly requested by manual refresh
    -- AND throttled to at least 10s between scans.
    if force and (now - lastMemoryScanTime >= 10 or cachedAddonMem == 0) then
        if UpdateAddOnMemoryUsage then
            UpdateAddOnMemoryUsage()
        end
        lastMemoryScanTime = now
    end
    if GetAddOnMemoryUsage then
        cachedAddonMem = GetAddOnMemoryUsage("sfui") or cachedAddonMem or 0
    end
    return cachedAddonMem
end
sfui.mem.RefreshAddonMemory = RefreshAddonMemory

local function RecordAllocation(sourceName, kbDelta)
    if not watcherActive then return end
    if not sourceName or sourceName == "MemGUI" or sourceName == "memgui" then return end
    local rec = watcherData[sourceName]
    if not rec then
        rec = { count = 0, totalKB = 0, maxKB = 0 }
        watcherData[sourceName] = rec
    end
    rec.count = rec.count + 1
    if kbDelta and kbDelta > 0 then
        rec.totalKB = rec.totalKB + kbDelta
        if kbDelta > rec.maxKB then
            rec.maxKB = kbDelta
        end
    end
end
sfui.mem.RecordAllocation = RecordAllocation

local function StopWatcher()
    if not watcherActive then return end
    watcherActive = false
    if sfui.events and sfui.events.SetMemProfiling then
        sfui.events.SetMemProfiling(false)
    end
    if watcherTimer then
        watcherTimer:Cancel()
        watcherTimer = nil
    end

    local duration = GetTime() - watcherStartTime
    local endAddonMem = GetAddOnMemoryUsage and (GetAddOnMemoryUsage("sfui") or watcherStartAddonMem) or watcherStartAddonMem
    local endLuaMem = collectgarbage("count")

    local addonDelta = endAddonMem - watcherStartAddonMem
    local luaDelta = endLuaMem - watcherStartLuaMem
    local addonRate = duration > 0 and (addonDelta / duration) or 0

    local list = {}
    for name, data in pairs(watcherData) do
        table_insert(list, { name = name, count = data.count, totalKB = data.totalKB, maxKB = data.maxKB })
    end

    table_sort(list, function(a, b)
        if a.totalKB ~= b.totalKB then
            return a.totalKB > b.totalKB
        end
        return a.count > b.count
    end)

    watcherLastReport = {
        duration = duration,
        addonDelta = addonDelta,
        luaDelta = luaDelta,
        addonRate = addonRate,
        list = list,
        timestamp = GetTime()
    }

    if sfui.mem.gui and sfui.mem.gui:IsShown() then
        sfui.mem.UpdateGUI(false)
        if sfui.mem.SelectTab then
            sfui.mem.SelectTab("profiler")
        end
    end

    print(" ")
    print(PREFIX .. "|cffffffff========================================|r")
    print(PREFIX .. string_format("|cff00ffffallocation profiling report (%d seconds)|r", math_floor(duration + 0.5)))
    print(PREFIX .. string_format("addon delta: |cffffffff%s|r (rate: |cff%s%.2f kb/s|r)",
        FormatKB(addonDelta),
        addonRate > 10 and "ff4444" or (addonRate > 1 and "ffaa00" or "00ff88"),
        addonRate
    ))
    print(PREFIX .. string_format("lua memory delta: |cffffffff%s|r", FormatKB(luaDelta)))
    print(PREFIX .. "|cffffffff----------------------------------------|r")

    if #list == 0 then
        print(PREFIX .. "|cff00ff88zero events / updates recorded during sample! perfectly idle.|r")
    else
        print(PREFIX .. "|cff00fffftop dispatched events & allocation leaderboard:|r")
        local count = 0
        for _, item in ipairs(list) do
            count = count + 1
            if count <= 10 then
                local color = "00ff88"
                if item.totalKB > 50 then color = "ff4444"
                elseif item.totalKB > 5 then color = "ffaa00"
                elseif item.totalKB > 0 then color = "ffffaa" end

                print(string_format("  #%d |cffffffff%s|r: |cff%s%s|r (|cffaaaaaa%d calls|r, max: %.1f kb)",
                    count, item.name:lower(), color, FormatKB(item.totalKB), item.count, item.maxKB
                ))
            end
        end
    end
    print(PREFIX .. "|cffffffff========================================|r")
    print(" ")
end
sfui.mem.StopWatcher = StopWatcher

function sfui.mem.StartWatcher(duration)
    if watcherActive then
        StopWatcher()
        return
    end

    duration = tonumber(duration) or 10
    if duration < 3 then duration = 3 end
    if duration > 120 then duration = 120 end
    watcherDuration = duration

    wipe(watcherData)
    local startMem = GetAddOnMemoryUsage and (GetAddOnMemoryUsage("sfui") or cachedAddonMem or 0) or 0
    watcherStartAddonMem = startMem
    watcherStartLuaMem = collectgarbage("count")
    watcherStartTime = GetTime()
    watcherActive = true
    if sfui.events and sfui.events.SetMemProfiling then
        sfui.events.SetMemProfiling(true)
    end

    print(PREFIX .. string_format("|cff00ff88starting memory allocation watcher for %d seconds...|r", duration))

    watcherTimer = C_Timer.NewTimer(duration, StopWatcher)

    if sfui.mem.gui and sfui.mem.gui:IsShown() then
        sfui.mem.UpdateGUI(false)
    end
end

function sfui.mem.IsWatcherActive()
    return watcherActive
end

-- ---------------------------------------------------------------------------
-- 3. FORCED GARBAGE COLLECTION
-- ---------------------------------------------------------------------------
function sfui.mem.RunGC()
    local beforeAddon = GetAddOnMemoryUsage and (GetAddOnMemoryUsage("sfui") or cachedAddonMem or 0) or 0
    local beforeLua = collectgarbage("count")

    collectgarbage("collect")

    local afterLua = collectgarbage("count")
    local afterAddon = GetAddOnMemoryUsage and (GetAddOnMemoryUsage("sfui") or beforeAddon) or beforeAddon

    local freedLua = math_max(0, beforeLua - afterLua)
    local freedAddon = math_max(0, beforeAddon - afterAddon)

    local msg = string_format("gc collected: freed %s lua memory", FormatKB(freedLua))
    print(PREFIX .. "|cff00ff88" .. msg .. "|r")

    if sfui.mem.gui and sfui.mem.gui:IsShown() then
        if sfui.mem.gui.actionStatusText then
            sfui.mem.gui.actionStatusText:SetText("|cff00ff88" .. msg .. "|r")
        end
        sfui.mem.UpdateGUI(false)
    end
end

-- ---------------------------------------------------------------------------
-- 4. SLEEK, FLAT & MINIMALIST MEMORY GUI (All Lowercase)
-- ---------------------------------------------------------------------------
local frame
local moduleCards = {}
local leaderboardRows = {}
local activeTab = "modules"

local MODULE_ORDER = {
    "dispatcher", "quests", "mythic", "trackedbars", "trackedicons", "bars",
    "soulfragments", "gear", "worldevents", "alts", "merchant", "portals",
    "castbars", "minimap", "glows", "automation", "fishing", "pets",
    "cursor", "vehicle", "currency", "lootspec", "location", "cdm",
    "research", "transfer", "logs", "hammer", "bonusroll", "stats"
}

function sfui.mem.create_mem_panel()
    if frame then return frame end

    local CreateFlatButton = common.create_flat_button
    local FRAME_W, FRAME_H = 650, 460

    frame = CreateFrame("Frame", "sfui_mem_frame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    -- Flat minimalist backdrop without outer border
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        tile = true,
        tileSize = 32,
    })
    frame:SetBackdropColor(0.04, 0.04, 0.06, 0.94)
    frame:Hide()
    table_insert(UISpecialFrames, "sfui_mem_frame")

    -- Header Title (Lowercase)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    title:SetPoint("TOPLEFT", 12, -8)
    title:SetText("|cff6600ffsfui|r  |cffffffffmemory & diagnostics|r")

    -- Close Button
    local close_btn = CreateFlatButton(frame, "✕", 20, 20)
    close_btn:SetPoint("TOPRIGHT", -6, -6)
    close_btn:SetScript("OnClick", function() frame:Hide() end)

    -- -----------------------------------------------------------------------
    -- Row 1: 3 Flat Metric KPI Cards (Lowercase)
    -- -----------------------------------------------------------------------
    local cardW = (FRAME_W - 20 - 12) / 3
    local cardH = 42

    local function CreateKPICard(xOffset, titleText)
        local card = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        card:SetSize(cardW, cardH)
        card:SetPoint("TOPLEFT", 10 + xOffset, -32)
        card:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        card:SetBackdropColor(0.08, 0.08, 0.11, 0.8)
        card:SetBackdropBorderColor(0.18, 0.18, 0.24, 0.7)

        local lbl = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", 8, -5)
        lbl:SetText(titleText:lower())
        lbl:SetTextColor(0.55, 0.55, 0.62, 1)

        local val = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        val:SetPoint("BOTTOMLEFT", 8, 5)
        val:SetText("--")

        card.valText = val
        return card
    end

    local cardAddon = CreateKPICard(0, "addon memory")
    local cardLua = CreateKPICard(cardW + 6, "lua environment")
    local cardRate = CreateKPICard((cardW + 6) * 2, "allocation rate")
    frame.val_addon = cardAddon.valText
    frame.val_lua = cardLua.valText
    frame.val_rate = cardRate.valText

    -- -----------------------------------------------------------------------
    -- Row 2: Dedicated Button Action Bar (All Lowercase)
    -- -----------------------------------------------------------------------
    local tab_modules = CreateFlatButton(frame, "modules & pools (" .. #MODULE_ORDER .. ")", 135, 22)
    tab_modules:SetPoint("TOPLEFT", 10, -78)

    local tab_profiler = CreateFlatButton(frame, "allocation leaderboard", 135, 22)
    tab_profiler:SetPoint("LEFT", tab_modules, "RIGHT", 4, 0)

    local btn_refresh = CreateFlatButton(frame, "refresh", 60, 22)
    btn_refresh:SetPoint("TOPRIGHT", -10, -78)
    btn_refresh:SetScript("OnClick", function() sfui.mem.UpdateGUI(true) end)


    local btn_gc = CreateFlatButton(frame, "collect gc", 76, 22)
    btn_gc:SetPoint("RIGHT", btn_refresh, "LEFT", -4, 0)
    btn_gc:SetScript("OnClick", function() sfui.mem.RunGC() end)

    local btn_watch30 = CreateFlatButton(frame, "watch 30s", 70, 22)
    btn_watch30:SetPoint("RIGHT", btn_gc, "LEFT", -4, 0)
    btn_watch30:SetScript("OnClick", function() sfui.mem.StartWatcher(30) end)

    local btn_watch10 = CreateFlatButton(frame, "watch 10s", 70, 22)
    btn_watch10:SetPoint("RIGHT", btn_watch30, "LEFT", -4, 0)
    btn_watch10:SetScript("OnClick", function() sfui.mem.StartWatcher(10) end)

    -- -----------------------------------------------------------------------
    -- Row 3: Dedicated Full-Width Status Bar (Unobstructed Room for GC & Profiler Logs)
    -- -----------------------------------------------------------------------
    local statusBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    statusBar:SetPoint("TOPLEFT", 10, -104)
    statusBar:SetPoint("TOPRIGHT", -10, -104)
    statusBar:SetHeight(20)
    statusBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    statusBar:SetBackdropColor(0.06, 0.06, 0.09, 0.85)
    statusBar:SetBackdropBorderColor(0.16, 0.16, 0.22, 0.6)

    local statusPrefix = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusPrefix:SetPoint("LEFT", 8, 0)
    statusPrefix:SetText("status:")
    statusPrefix:SetTextColor(0.55, 0.55, 0.62, 1)

    local actionStatus = statusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    actionStatus:SetPoint("LEFT", statusPrefix, "RIGHT", 6, 0)
    actionStatus:SetPoint("RIGHT", -8, 0)
    actionStatus:SetJustifyH("LEFT")
    actionStatus:SetText("|cff00ff88ready|r")
    frame.actionStatusText = actionStatus

    -- -----------------------------------------------------------------------
    -- Row 4: Main Content Area (Flat Cards Grid & Flat Table)
    -- -----------------------------------------------------------------------
    local contentBox = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    contentBox:SetPoint("TOPLEFT", 10, -128)
    contentBox:SetPoint("BOTTOMRIGHT", -10, 10)
    contentBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    contentBox:SetBackdropColor(0.06, 0.06, 0.08, 0.85)
    contentBox:SetBackdropBorderColor(0.14, 0.14, 0.18, 0.7)

    -- -----------------------------------------------------------------------
    -- View 1: Modules Grid (2 Columns, Clean Compact Cards)
    -- -----------------------------------------------------------------------
    local modScroll = CreateFrame("ScrollFrame", "SfuiMemScroll", contentBox, "UIPanelScrollFrameTemplate")
    modScroll:SetPoint("TOPLEFT", 4, -4)
    modScroll:SetPoint("BOTTOMRIGHT", -22, 4)
    modScroll:EnableMouseWheel(true)
    if common and common.style_scrollbar and modScroll.ScrollBar then
        common.style_scrollbar(modScroll.ScrollBar)
    end
    modScroll:SetScript("OnMouseWheel", function(self, delta)
        local sb = self.ScrollBar
        if sb then
            local minVal, maxVal = sb:GetMinMaxValues()
            if maxVal and maxVal > (minVal or 0) then
                local cur = sb:GetValue()
                sb:SetValue(math_max(minVal, math_min(maxVal, cur - delta * 30)))
            end
        end
    end)

    local modChild = CreateFrame("Frame", nil, modScroll)
    local cardGridW = FRAME_W - 48
    modChild:SetSize(cardGridW, 600)
    modChild:SetPoint("TOPLEFT", 0, 0)
    modScroll:SetScrollChild(modChild)
    contentBox.modView = modScroll

    local cardW = (cardGridW - 6) / 2
    local cardH = 58

    for idx, key in ipairs(MODULE_ORDER) do
        local card = CreateFrame("Frame", nil, modChild, "BackdropTemplate")
        local col = (idx - 1) % 2
        local row = math_floor((idx - 1) / 2)
        card:SetSize(cardW, cardH)
        card:SetPoint("TOPLEFT", col * (cardW + 6), -row * (cardH + 4))
        card:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        card:SetBackdropColor(0.09, 0.09, 0.12, 0.7)
        card:SetBackdropBorderColor(0.18, 0.18, 0.22, 0.6)

        card.status = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        card.status:SetPoint("TOPRIGHT", -6, -4)
        card.status:SetJustifyH("RIGHT")
        card.status:SetText("|cff888888idle|r")

        card.title = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        card.title:SetPoint("TOPLEFT", 6, -4)
        card.title:SetPoint("RIGHT", card.status, "LEFT", -4)
        card.title:SetJustifyH("LEFT")
        card.title:SetText("|cff00ffff" .. key .. "|r")

        card.line1 = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        card.line1:SetPoint("TOPLEFT", 6, -20)
        card.line1:SetPoint("RIGHT", -6, 0)
        card.line1:SetJustifyH("LEFT")
        card.line1:SetTextColor(0.8, 0.8, 0.85, 1)
        card.line1:SetText("telemetry active")

        card.line2 = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        card.line2:SetPoint("TOPLEFT", 6, -36)
        card.line2:SetPoint("RIGHT", -6, 0)
        card.line2:SetJustifyH("LEFT")
        card.line2:SetTextColor(0.55, 0.55, 0.6, 1)
        card.line2:SetText("pools: ready")

        card:Show()
        moduleCards[key] = card
    end
    modChild:SetHeight(math_ceil(#MODULE_ORDER / 2) * (cardH + 4) + 10)

    -- -----------------------------------------------------------------------
    -- View 2: Leaderboard View (Lowercase Headers)
    -- -----------------------------------------------------------------------
    local lbFrame = CreateFrame("Frame", nil, contentBox)
    lbFrame:SetAllPoints(contentBox)
    lbFrame:Hide()
    contentBox.lbView = lbFrame

    -- Table Header
    local th = CreateFrame("Frame", nil, lbFrame, "BackdropTemplate")
    th:SetPoint("TOPLEFT", 4, -4)
    th:SetPoint("TOPRIGHT", -4, -4)
    th:SetHeight(22)
    th:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    th:SetBackdropColor(0.12, 0.12, 0.16, 0.9)

    local hRank = th:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hRank:SetPoint("LEFT", 8, 0)
    hRank:SetText("#")
    hRank:SetTextColor(0.6, 0.6, 0.65, 1)

    local hSource = th:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hSource:SetPoint("LEFT", 36, 0)
    hSource:SetText("event / update loop")
    hSource:SetTextColor(0.6, 0.6, 0.65, 1)

    local hCalls = th:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hCalls:SetPoint("LEFT", 260, 0)
    hCalls:SetText("calls")
    hCalls:SetTextColor(0.6, 0.6, 0.65, 1)

    local hTotal = th:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hTotal:SetPoint("LEFT", 380, 0)
    hTotal:SetText("total allocated")
    hTotal:SetTextColor(0.6, 0.6, 0.65, 1)

    local hMax = th:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hMax:SetPoint("LEFT", 510, 0)
    hMax:SetText("max spike")
    hMax:SetTextColor(0.6, 0.6, 0.65, 1)

    for i = 1, 12 do
        local row = CreateFrame("Frame", nil, lbFrame, "BackdropTemplate")
        row:SetPoint("TOPLEFT", 4, -28 - ((i - 1) * 22))
        row:SetPoint("TOPRIGHT", -4, -28 - ((i - 1) * 22))
        row:SetHeight(20)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        row:SetBackdropColor(i % 2 == 0 and 0.08 or 0.06, i % 2 == 0 and 0.08 or 0.06, i % 2 == 0 and 0.1 or 0.08, 0.7)

        row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.rank:SetPoint("LEFT", 8, 0)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 36, 0)

        row.calls = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.calls:SetPoint("LEFT", 260, 0)

        row.total = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.total:SetPoint("LEFT", 380, 0)

        row.max = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.max:SetPoint("LEFT", 510, 0)

        row:Hide()
        leaderboardRows[i] = row
    end

    local emptyHint = lbFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    emptyHint:SetPoint("CENTER", 0, 0)
    emptyHint:SetTextColor(0.55, 0.55, 0.62, 1)
    emptyHint:SetText("click 'watch 10s' or 'watch 30s' above to profile memory allocations")
    lbFrame.emptyHint = emptyHint
    frame.emptyHint = emptyHint

    -- Tab Switching
    local function SelectTab(tabName)
        activeTab = tabName
        if tabName == "modules" then
            contentBox.modView:Show()
            contentBox.lbView:Hide()
            tab_modules:SetBackdropColor(0.4, 0.0, 1.0, 0.9)
            tab_profiler:SetBackdropColor(0.12, 0.12, 0.16, 0.8)
        else
            contentBox.modView:Hide()
            contentBox.lbView:Show()
            tab_profiler:SetBackdropColor(0.4, 0.0, 1.0, 0.9)
            tab_modules:SetBackdropColor(0.12, 0.12, 0.16, 0.8)
        end
        if frame and frame:IsShown() then
            sfui.mem.UpdateGUI(false)
        end
    end
    sfui.mem.SelectTab = SelectTab

    tab_modules:SetScript("OnClick", function() SelectTab("modules") end)
    tab_profiler:SetScript("OnClick", function() SelectTab("profiler") end)
    SelectTab("modules")

    frame:SetScript("OnShow", function()
        -- Ensure modules tab is active unless profiler is currently watching
        if not watcherActive and sfui.mem.SelectTab then
            sfui.mem.SelectTab("modules")
        else
            sfui.mem.UpdateGUI(false)
        end

        -- Register lightweight 1.0s periodic update (non-blocking, force=false)
        if sfui.events and sfui.events.RegisterUpdate then
            sfui.events.RegisterUpdate("MemGUI", 1.0, function()
                sfui.mem.UpdateGUI(false)
            end)
        end
    end)

    frame:SetScript("OnHide", function()
        if sfui.events and sfui.events.UnregisterUpdate then
            sfui.events.UnregisterUpdate("MemGUI")
        end
    end)

    sfui.mem.gui = frame
    return frame
end

function sfui.mem.UpdateGUI(force)
    if not frame or not frame:IsShown() then return end

    local addonMem = RefreshAddonMemory(force)
    local totalLua = collectgarbage("count")

    local memColor = addonMem < 10240 and "|cff00ff88" or (addonMem <= 15360 and "|cffffaa00" or "|cffff4444")
    if frame.val_addon then
        frame.val_addon:SetText(memColor .. FormatKB(addonMem) .. "|r")
    end
    if frame.val_lua then
        frame.val_lua:SetText("|cffffffff" .. FormatKB(totalLua) .. "|r")
    end

    if watcherActive then
        local elapsed = GetTime() - watcherStartTime
        local remain = math_max(0, watcherDuration - elapsed)
        if frame.val_rate then frame.val_rate:SetText(string_format("|cff00ffffprofiling (%ds)...|r", math_ceil(remain))) end
        if frame.actionStatusText then frame.actionStatusText:SetText(string_format("|cff00ffffprofiling in progress (%ds left)...|r", math_ceil(remain))) end
        -- While actively profiling, return early to avoid observer effect table allocations
        return
    elseif watcherLastReport then
        local rate = watcherLastReport.addonRate
        local rateColor = rate > 10 and "ff4444" or (rate > 1 and "ffaa00" or "00ff88")
        if frame.val_rate then frame.val_rate:SetText(string_format("|cff%s%.2f kb/s|r", rateColor, rate)) end
        if frame.actionStatusText then frame.actionStatusText:SetText(string_format("|cffaaaaaalast sample: %ds duration|r", math_floor(watcherLastReport.duration + 0.5))) end
    else
        if frame.val_rate then frame.val_rate:SetText("|cff00ff880.00 kb/s|r") end
    end

    -- Update Modules Grid only when modules tab is active
    if activeTab == "modules" then
        local ok, modStats = pcall(sfui.mem.GetModuleStats)
        if ok and type(modStats) == "table" then
            for _, key in ipairs(MODULE_ORDER) do
                local card = moduleCards[key]
                local data = modStats[key]
                if card and data then
                    card.title:SetText("|cff00ffff" .. key .. "|r " .. (data.name and data.name:lower() or ""))
                    card.status:SetText(data.status or "")
                    card.line1:SetText(data.line1 or "")
                    card.line2:SetText(data.line2 or "")
                end
            end
        end
    end

    -- Update Leaderboard only when profiler tab is active
    if activeTab == "profiler" then
        local list = watcherLastReport and watcherLastReport.list or {}
        local hasItems = #list > 0
        if frame and frame.emptyHint then
            local hint = frame.emptyHint
            if hasItems then
                hint:SetText("")
                if hint.Hide then hint:Hide() end
            else
                hint:SetText(watcherLastReport and "|cff00ff88zero allocations recorded during sample (system idle)|r" or "click 'watch 10s' or 'watch 30s' above to profile memory allocations")
                if hint.Show then hint:Show() end
            end
        end

        for i = 1, 12 do
            local row = leaderboardRows[i]
            local item = list[i]
            if item then
                row.rank:SetText("#" .. i)
                row.name:SetText(item.name and item.name:lower() or "")
                row.calls:SetText(string_format("%d", item.count))

                local color = "00ff88"
                if item.totalKB > 50 then color = "ff4444"
                elseif item.totalKB > 5 then color = "ffaa00"
                elseif item.totalKB > 0 then color = "ffffaa" end

                row.total:SetText(string_format("|cff%s%s|r", color, FormatKB(item.totalKB)))
                row.max:SetText(string_format("%.1f kb", item.maxKB))
                row:Show()
            else
                row:Hide()
            end
        end
    end
end


function sfui.mem.ToggleGUI()
    local f = sfui.mem.create_mem_panel()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
    end
end

-- ---------------------------------------------------------------------------
-- 5. SLASH COMMAND HANDLER
-- ---------------------------------------------------------------------------
function sfui.mem.HandleSlash(msg)
    local clean = msg and _G.strtrim and _G.strtrim(msg):lower() or (msg and msg:lower() or "")
    local cmd, arg = clean:match("^(%S+)%s*(.*)$")
    cmd = cmd or clean

    if cmd == "gc" or cmd == "clean" or cmd == "collect" then
        sfui.mem.RunGC()
    elseif cmd == "watch" or cmd == "profile" or cmd == "trace" then
        sfui.mem.StartWatcher(arg)
        local f = sfui.mem.create_mem_panel()
        f:Show()
        if sfui.mem.SelectTab then sfui.mem.SelectTab("profiler") end
    elseif cmd == "stop" then
        if watcherActive then StopWatcher() else print(PREFIX .. "watcher is not running.") end
    elseif cmd == "print" or cmd == "dump" then
        UpdateAddOnMemoryUsage()
        local addonMem = GetAddOnMemoryUsage("sfui")
        local totalLuaMem = collectgarbage("count")
        local memColor = addonMem < 10240 and "|cff00ff88" or (addonMem <= 15360 and "|cffffaa00" or "|cffff4444")
        print(" ")
        print(PREFIX .. "|cffffffff========================================|r")
        print(PREFIX .. string_format("|cff00ffffaddon total memory:|r %s%s|r", memColor, FormatKB(addonMem)))
        print(PREFIX .. string_format("|cffaaaaaatotal lua environment:|r |cffffffff%s|r", FormatKB(totalLuaMem)))
        print(PREFIX .. "|cffffffff----------------------------------------|r")
        local modStats = sfui.mem.GetModuleStats()
        for _, key in ipairs(MODULE_ORDER) do
            local info = modStats[key]
            if info then
                print(string_format("|cff6600ff[%s]|r |cffffffff%s|r (%s)", key, info.name and info.name:lower() or "", info.status or ""))
                if info.line1 then print("   |cff888888•|r " .. info.line1) end
                if info.line2 then print("   |cff888888•|r " .. info.line2) end
            end
        end
        print(PREFIX .. "|cffffffff========================================|r")
        print(" ")
    else
        sfui.mem.ToggleGUI()
    end
end

if sfui.RegisterModule then
    sfui.mem.OnSettingsChanged = function(self, k, v)
        if sfui.mem.gui and sfui.mem.gui:IsShown() then
            sfui.mem.UpdateGUI()
        end
    end
    sfui.RegisterModule("mem", sfui.mem)
end

