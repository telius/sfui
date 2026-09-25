local addonName, addon = ...
sfui = sfui or {}
sfui.compare = {}

local active = false

local setCVar = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
local getCVar = (C_CVar and C_CVar.GetCVar) or _G.GetCVar
local function safe_set_cvar(cvar, val)
    if setCVar and (not getCVar or getCVar(cvar) ~= nil) then
        setCVar(cvar, val)
    end
end

local function update_cvar()
    if not SfuiDB or not SfuiDB.enableAutoCompare then
        if active then
            safe_set_cvar("alwaysCompareItems", "0")
            active = false
        end
        return
    end

    if not active then
        safe_set_cvar("alwaysCompareItems", "1")
        active = true
    end
end

function sfui.compare.init()
    if SfuiDB.enableAutoCompare == nil then
        SfuiDB.enableAutoCompare = true
    end

    update_cvar()

    -- Hook into equipment events to ensure the CVar stays set
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", update_cvar)
    sfui.events.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", update_cvar)
end
