local addonName, addon = ...
sfui = sfui or {}
sfui.logs = {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/automation/logs.lua
--  Smart Auto Combat Logging
--
--  * Filters instances & difficulties so legacy transmog/farm runs don't bloat logs:
--    - Retail: M+ (diff 8 / current+legacy M+ pool diff 23), current raids
--      by difficulty (mythic/heroic/normal/lfr), arena, and rated BGs.
--    - Camelot / Classic: separate raid and 5-man dungeon toggles.
--  * Automatically enables advancedCombatLogging when starting a log.
--  * Optional 30s zone-out grace delay prevents brief zoning / corpse runs
--    from splitting a combat log file.
--  * Never stops a combat log that the player started manually.
-- ══════════════════════════════════════════════════════════════════════════════

local _G            = _G
local CreateFrame   = _G.CreateFrame
local GetInstanceInfo = _G.GetInstanceInfo
local IsInInstance  = _G.IsInInstance
local LoggingCombat = _G.LoggingCombat
local C_Timer       = _G.C_Timer
local C_CVar        = _G.C_CVar
local C_PvP         = _G.C_PvP
local tonumber      = _G.tonumber

local STOP_DELAY = 30
local EVAL_DEBOUNCE = 1.5

-- Current Midnight retail raids (plus dynamic mapID >= 2800 check).
local CURRENT_RAID_MAP_IDS = {
    [2912] = true,
    [2913] = true,
    [2939] = true,
}

-- Legacy dungeons that belong to Mythic+ rotations (plus dynamic >= 2652 check).
local LEGACY_MPLUS_MAP_IDS = {
    [657]  = true, -- The Vortex Pinnacle
    [643]  = true, -- Throne of the Tides
    [670]  = true, -- Grim Batol
    [960]  = true, -- Temple of the Jade Serpent
    [1176] = true, -- Shadowmoon Burial Grounds
    [1209] = true, -- Skyreach
    [1279] = true, -- The Everbloom
    [1458] = true, -- Neltharion's Lair
    [1477] = true, -- Halls of Valor
    [1753] = true, -- Seat of the Triumvirate
    [1594] = true, -- The MOTHERLODE!!
    [1763] = true, -- Atal'Dazar
    [1822] = true, -- Siege of Boralus
    [2097] = true, -- Operation: Mechagon
    [2286] = true, -- The Necrotic Wake
    [2287] = true, -- Halls of Atonement
    [2290] = true, -- Mists of Tirna Scithe
    [2293] = true, -- Theater of Pain
    [2441] = true, -- Tazavesh, the Veiled Market
    [2516] = true, -- The Nokhud Offensive
    [2526] = true, -- Algeth'ar Academy
}

local sfui_started_log = false
local stopTimer = nil
local evalTimer = nil
local eventsRegistered = false

local eventFrame = CreateFrame("Frame")

local function GetDefaultsTable()
    return (sfui.config and sfui.config.logs) or {}
end

function sfui.logs.get_setting(key)
    local settings = _G.SfuiDB and _G.SfuiDB.autoCombatLogSettings
    if settings and settings[key] ~= nil then
        return settings[key]
    end
    local def = GetDefaultsTable()
    if def[key] ~= nil then
        return def[key]
    end
    return false
end

function sfui.logs.set_setting(key, val)
    _G.SfuiDB = _G.SfuiDB or {}
    _G.SfuiDB.autoCombatLogSettings = _G.SfuiDB.autoCombatLogSettings or {}
    _G.SfuiDB.autoCombatLogSettings[key] = val and true or false
    sfui.logs.refresh()
end

local function EnsureAdvancedLogging()
    local getCVar = (C_CVar and C_CVar.GetCVar) or _G.GetCVar
    local setCVar = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
    if getCVar and setCVar and getCVar("advancedCombatLogging") ~= "1" then
        setCVar("advancedCombatLogging", "1")
    end
end

local function ShouldLog()
    if not (_G.SfuiDB and _G.SfuiDB.autoCombatLog) then
        return false, nil
    end

    if not GetInstanceInfo then
        local _, fallbackType = IsInInstance()
        if fallbackType == "raid" and sfui.logs.get_setting("logRaid") then
            return true, "raid"
        end
        return false, nil
    end

    local _, instanceType, difficulty, _, _, _, _, instanceID = GetInstanceInfo()
    local mapID = tonumber(instanceID) or 0

    if sfui.isCamelot or sfui.isClassic then
        if instanceType == "raid" and sfui.logs.get_setting("logRaid") then
            return true, "raid"
        elseif instanceType == "party" and sfui.logs.get_setting("logDungeon") then
            return true, "dungeon"
        end
        return false, nil
    end

    -- Retail ruleset
    if instanceType == "raid" then
        local isCurrentRaid = CURRENT_RAID_MAP_IDS[mapID] or mapID >= 2800
        if isCurrentRaid then
            if difficulty == 16 and sfui.logs.get_setting("logMythic") then
                return true, "mythic raid"
            elseif difficulty == 15 and sfui.logs.get_setting("logHeroic") then
                return true, "heroic raid"
            elseif difficulty == 14 and sfui.logs.get_setting("logNormal") then
                return true, "normal raid"
            elseif difficulty == 17 and sfui.logs.get_setting("logLFR") then
                return true, "lfr raid"
            end
        end
    elseif instanceType == "party" then
        if difficulty == 8 and sfui.logs.get_setting("log5pp") then
            return true, "mythic+"
        elseif difficulty == 23 and (LEGACY_MPLUS_MAP_IDS[mapID] or mapID >= 2652) and sfui.logs.get_setting("log5pp") then
            return true, "mythic dungeon"
        end
    elseif instanceType == "arena" and sfui.logs.get_setting("logArena") then
        return true, "arena"
    elseif instanceType == "pvp" and C_PvP and C_PvP.IsRatedBattleground and C_PvP.IsRatedBattleground()
        and sfui.logs.get_setting("logRBG") then
        return true, "rated bg"
    end

    return false, nil
end

local function CancelStopTimer()
    if stopTimer then
        stopTimer:Cancel()
        stopTimer = nil
    end
end

local function StopLogNow()
    CancelStopTimer()
    if LoggingCombat and LoggingCombat() and sfui_started_log then
        LoggingCombat(false)
        sfui_started_log = false
        if sfui.common and sfui.common.print then
            sfui.common.print("combat logging |cffff4444stopped|r.")
        end
    end
end

local function EvaluateLogging()
    if evalTimer then
        evalTimer:Cancel()
        evalTimer = nil
    end

    local wantLog, reason = ShouldLog()
    if wantLog then
        CancelStopTimer()
        EnsureAdvancedLogging()
        if LoggingCombat and not LoggingCombat() then
            LoggingCombat(true)
            sfui_started_log = true
            if sfui.common and sfui.common.print then
                sfui.common.print("combat logging |cff00ff00started|r (" .. (reason or "instance") .. ").")
            end
        end
    elseif LoggingCombat and LoggingCombat() and sfui_started_log then
        if sfui.logs.get_setting("delayStop") then
            if not stopTimer then
                stopTimer = C_Timer.NewTimer(STOP_DELAY, function()
                    stopTimer = nil
                    if not ShouldLog() then
                        StopLogNow()
                    end
                end)
            end
        else
            StopLogNow()
        end
    end
end

local function ScheduleEvaluate(immediate)
    if evalTimer then
        evalTimer:Cancel()
        evalTimer = nil
    end
    if immediate then
        EvaluateLogging()
        return
    end
    evalTimer = C_Timer.NewTimer(EVAL_DEBOUNCE, function()
        evalTimer = nil
        EvaluateLogging()
    end)
end

local function SyncEventRegistration()
    local enabled = (_G.SfuiDB and _G.SfuiDB.autoCombatLog == true)
    if enabled and not eventsRegistered then
        eventsRegistered = true
        eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        eventFrame:RegisterEvent("RAID_INSTANCE_WELCOME")
        if sfui.isRetail then
            eventFrame:RegisterEvent("CHALLENGE_MODE_START")
            eventFrame:RegisterEvent("PVP_MATCH_ACTIVE")
        end
    elseif not enabled and eventsRegistered then
        eventsRegistered = false
        eventFrame:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
        eventFrame:UnregisterEvent("RAID_INSTANCE_WELCOME")
        eventFrame:UnregisterEvent("CHALLENGE_MODE_START")
        eventFrame:UnregisterEvent("PVP_MATCH_ACTIVE")
    end
end

function sfui.logs.is_enabled()
    return (_G.SfuiDB and _G.SfuiDB.autoCombatLog == true) or false
end

function sfui.logs.refresh()
    SyncEventRegistration()
    if not sfui.logs.is_enabled() then
        StopLogNow()
    else
        EvaluateLogging()
    end
end

function sfui.logs.set_enabled(enabled)
    _G.SfuiDB = _G.SfuiDB or {}
    _G.SfuiDB.autoCombatLog = enabled and true or false
    sfui.logs.refresh()
end

eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        SyncEventRegistration()
        if sfui.logs.is_enabled() then
            ScheduleEvaluate(false)
        end
        return
    end
    if not sfui.logs.is_enabled() then return end
    if event == "CHALLENGE_MODE_START" then
        ScheduleEvaluate(true)
    else
        ScheduleEvaluate(false)
    end
end)
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

local _logsDebug = {}
function sfui.logs_debug_info()
    local _, instanceType = IsInInstance()
    _logsDebug.enabled = sfui.logs.is_enabled()
    _logsDebug.isLogging = (LoggingCombat and LoggingCombat()) and true or false
    _logsDebug.instanceType = instanceType or "none"
    _logsDebug.sfuiStarted = sfui_started_log
    _logsDebug.delayPending = (stopTimer ~= nil)
    return _logsDebug
end

if sfui.RegisterModule then
    sfui.logs.GetDebugInfo = sfui.logs_debug_info
    sfui.RegisterModule("logs", sfui.logs)
end
