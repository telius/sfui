local addonName, addon = ...
sfui = sfui or {}
sfui.compare = sfui.compare or {}

local _G = _G
local pcall = _G.pcall
local tonumber = _G.tonumber
local tostring = _G.tostring
local type = _G.type
local InCombatLockdown = _G.InCombatLockdown
local issecretvalue = _G.issecretvalue

local is_initialized = false

local function safe_set_cvar(cvar, val)
    if sfui.common and sfui.common.set_cvar then
        return sfui.common.set_cvar(cvar, val)
    elseif (not InCombatLockdown or not InCombatLockdown()) then
        local c_cvar = _G.C_CVar
        local setCVar = (c_cvar and c_cvar.SetCVar) or _G.SetCVar
        local getCVar = (c_cvar and c_cvar.GetCVar) or _G.GetCVar
        if setCVar then
            local strVal = tostring(val)
            if not getCVar or getCVar(cvar) ~= strVal then
                local ok = pcall(setCVar, cvar, strVal)
                if not ok and tonumber(strVal) ~= nil then
                    pcall(setCVar, cvar, tonumber(strVal))
                end
            end
            return true
        end
    end
    return false
end

local function update_cvar()
    local db = _G.SfuiDB
    if not db then return end
    local should_enable = (db.enableAutoCompare ~= false)
    safe_set_cvar("alwaysCompareItems", should_enable and "1" or "0")
end

local function on_cvar_update(event, cvar_name)
    if not cvar_name or (issecretvalue and issecretvalue(cvar_name)) then return end
    if type(cvar_name) == "string" and cvar_name:lower() == "alwayscompareitems" then
        local c_cvar = _G.C_CVar
        local get = (c_cvar and c_cvar.GetCVar) or _G.GetCVar
        local current = get and get("alwaysCompareItems")
        if current and issecretvalue and issecretvalue(current) then return end
        local db = _G.SfuiDB
        local expected = (db and db.enableAutoCompare ~= false) and "1" or "0"
        if current ~= expected then
            update_cvar()
        end
    end
end

function sfui.compare.init()
    local db = _G.SfuiDB
    if db and db.enableAutoCompare == nil then
        db.enableAutoCompare = true
    end

    update_cvar()

    if not is_initialized then
        is_initialized = true

        -- keep cvar enforced across login, loading screens, and cvar resets
        sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", update_cvar)
        sfui.events.RegisterEvent("VARIABLES_LOADED", update_cvar)
        sfui.events.RegisterEvent("CVAR_UPDATE", on_cvar_update)
    end
end

sfui.compare.update = update_cvar
