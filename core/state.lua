local addonName, addon = ...
sfui = sfui or {}
sfui.state = sfui.state or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/core/state.lua
--  single reactive player & hud context store (`sfui.state`).
--  evaluates combat, mount/travel/gliding, vehicle, pet battle, resting, dead,
--  stealth, shapeshift form, instance, spec, and role transitions once per event
--  and emits `SFUI_STATE_CHANGED(changedFlags, current)` only on real deltas.
-- ══════════════════════════════════════════════════════════════════════════════

local _G = _G
local wipe = _G.wipe or table.wipe
local InCombatLockdown = _G.InCombatLockdown
local UnitAffectingCombat = _G.UnitAffectingCombat
local IsMounted = _G.IsMounted
local IsResting = _G.IsResting
local IsStealthed = _G.IsStealthed
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local UnitInVehicle = _G.UnitInVehicle
local UnitHasVehicleUI = _G.UnitHasVehicleUI
local GetShapeshiftForm = _G.GetShapeshiftForm
local GetShapeshiftFormID = _G.GetShapeshiftFormID
local IsInInstance = _G.IsInInstance
local UnitPowerMax = _G.UnitPowerMax
local C_PetBattles = _G.C_PetBattles
local C_PlayerInfo = _G.C_PlayerInfo
local C_UnitAuras = _G.C_UnitAuras

local issecretvalue = (sfui.common and sfui.common.issecretvalue) or _G.issecretvalue or function() return false end

local S = sfui.state
S.hidden = true

local current = {
    revision          = 0,
    inCombat          = false,
    isMounted         = false,
    isTravelForm      = false,
    isMountedOrTravel = false,
    isDragonriding    = false,
    inVehicle         = false,
    inPetBattle       = false,
    isResting         = false,
    isDeadOrGhost     = false,
    isStealthed       = false,
    shapeshiftForm    = 0,
    shapeshiftFormID  = 0,
    inInstance        = false,
    instanceType      = "none",
    specID            = nil,
    role              = "dps",
    classicRole       = "dps",
    playerClass       = (sfui.common and sfui.common.get_player_class and sfui.common.get_player_class()) or "",
}
S.current = current

local _changedFlags = {}
local _debugInfo = {}

local function ComputeTravelForm()
    if current.playerClass == "" and sfui.common and sfui.common.get_player_class then
        current.playerClass = sfui.common.get_player_class() or ""
    end
    if current.playerClass ~= "DRUID" then
        return false
    end
    if GetShapeshiftFormID then
        local formID = GetShapeshiftFormID()
        if not issecretvalue(formID) and (formID == 3 or formID == 4 or formID == 27 or formID == 29) then
            return true
        end
    end
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(783)
        if not issecretvalue(aura) and aura ~= nil then
            return true
        end
    end
    return false
end

local function ComputeDragonriding(mountedOrTravel)
    if not mountedOrTravel then return false end
    if UnitPowerMax then
        local maxVigor = UnitPowerMax("player", 29)
        if not issecretvalue(maxVigor) and type(maxVigor) == "number" and maxVigor > 0 then
            return true
        end
    end
    if C_PlayerInfo and C_PlayerInfo.GetGlidingInfo then
        local _, canGlide = C_PlayerInfo.GetGlidingInfo()
        if not issecretvalue(canGlide) and canGlide == true then
            return true
        end
    end
    return false
end

local function ResolveSpecAndRoles()
    local specID = sfui.common and sfui.common.get_current_spec_id and sfui.common.get_current_spec_id() or nil
    local classicRole = "dps"
    local canonicalRole = "dps"

    if sfui.gear and sfui.gear.GetClassicRole then
        local db = sfui.gear.GetSpecDB and sfui.gear.GetSpecDB(specID) or nil
        classicRole = sfui.gear.GetClassicRole(specID, db) or "dps"
        if sfui.gear.IsTankSpec and sfui.gear.IsTankSpec(specID, db) then
            canonicalRole = "tank"
        elseif classicRole == "resto" or classicRole == "holy" or classicRole == "disc" or classicRole == "heal" or classicRole == "healer" then
            canonicalRole = "healer"
        else
            local bridge = sfui.talents and sfui.talents.SPEC_BRIDGE and specID and sfui.talents.SPEC_BRIDGE[specID]
            if bridge and bridge.role then
                local r = bridge.role:lower()
                if r == "tank" then
                    canonicalRole = "tank"
                elseif r == "healer" or r == "heal" then
                    canonicalRole = "healer"
                end
            end
        end
    end

    return specID, canonicalRole, classicRole
end

local function RefreshState(combatEvent)
    wipe(_changedFlags)
    local anyChanged = false

    local function setField(key, val)
        if current[key] ~= val then
            current[key] = val
            _changedFlags[key] = true
            anyChanged = true
        end
    end

    if current.playerClass == "" and sfui.common and sfui.common.get_player_class then
        setField("playerClass", sfui.common.get_player_class() or "")
    end

    local inCombat
    if combatEvent == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif combatEvent == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    elseif sfui.common and sfui.common.is_in_combat then
        inCombat = sfui.common.is_in_combat() == true
    else
        inCombat = ((InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))) and true or false
    end
    setField("inCombat", inCombat)

    local mounted = (IsMounted and IsMounted()) and true or false
    local travel = ComputeTravelForm()
    local mountedOrTravel = mounted or travel
    setField("isMounted", mounted)
    setField("isTravelForm", travel)
    setField("isMountedOrTravel", mountedOrTravel)
    setField("isDragonriding", ComputeDragonriding(mountedOrTravel))

    local inVeh = ((UnitInVehicle and UnitInVehicle("player")) or (UnitHasVehicleUI and UnitHasVehicleUI("player"))) and true or false
    setField("inVehicle", inVeh)

    local inPet = (C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle()) and true or false
    setField("inPetBattle", inPet)

    local resting = (IsResting and IsResting()) and true or false
    setField("isResting", resting)

    local dead = (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) and true or false
    setField("isDeadOrGhost", dead)

    local stealthed = (IsStealthed and IsStealthed()) and true or false
    setField("isStealthed", stealthed)

    local form = (GetShapeshiftForm and GetShapeshiftForm()) or 0
    if issecretvalue(form) or type(form) ~= "number" then form = 0 end
    setField("shapeshiftForm", form)

    local formID = (GetShapeshiftFormID and GetShapeshiftFormID()) or 0
    if issecretvalue(formID) or type(formID) ~= "number" then formID = 0 end
    setField("shapeshiftFormID", formID)

    if IsInInstance then
        local inInst, instType = IsInInstance()
        setField("inInstance", inInst and true or false)
        setField("instanceType", (not issecretvalue(instType) and type(instType) == "string" and instType) or "none")
    end

    local specID, role, classicRole = ResolveSpecAndRoles()
    setField("specID", specID)
    setField("role", role)
    setField("classicRole", classicRole)

    if anyChanged then
        current.revision = current.revision + 1
        if sfui.events and sfui.events.SendMessage then
            sfui.events.SendMessage("SFUI_STATE_CHANGED", _changedFlags, current)
        end
    end

    return anyChanged
end

function S.Refresh(combatEvent)
    return RefreshState(combatEvent)
end

function S.Get()
    return current
end

function S.Is(flag)
    return current[flag]
end

--- Evaluate declarative HUD visibility rules against canonical player state.
--- @param rules table|nil { combatOnly, hideOOC, hideInCombat, hideMounted, hideInVehicle, hideInPetBattle, hideResting, hideDead, instanceOnly }
--- @param forceShow boolean|nil True during movers/edit/preview modes
--- @return boolean shouldShow
function S.EvaluateVisibility(rules, forceShow)
    if forceShow then return true end
    if not rules then return true end

    if rules.hideInPetBattle and current.inPetBattle then
        return false
    end
    if rules.hideInVehicle and current.inVehicle then
        return false
    end
    if rules.hideDead and current.isDeadOrGhost then
        return false
    end
    if (rules.combatOnly or rules.hideOOC) and not current.inCombat then
        return false
    end
    if rules.hideInCombat and current.inCombat then
        return false
    end
    if rules.hideMounted and current.isMountedOrTravel and not current.inCombat then
        return false
    end
    if rules.hideResting and current.isResting and not current.inCombat then
        return false
    end
    if rules.instanceOnly and not current.inInstance then
        return false
    end

    return true
end

function S.GetDebugInfo()
    _debugInfo.revision = current.revision
    _debugInfo.inCombat = current.inCombat
    _debugInfo.mounted = current.isMountedOrTravel
    _debugInfo.vehicle = current.inVehicle
    _debugInfo.role = current.role
    _debugInfo.instance = current.instanceType
    return _debugInfo
end

if sfui.events then
    local function onStateEvent(event)
        RefreshState(event)
    end

    sfui.events.RegisterEvent("PLAYER_LOGIN", onStateEvent)
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", onStateEvent)
    sfui.events.RegisterEvent("ZONE_CHANGED_NEW_AREA", onStateEvent)
    sfui.events.RegisterEvent("PLAYER_REGEN_DISABLED", onStateEvent)
    sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", onStateEvent)
    sfui.events.RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED", onStateEvent)
    sfui.events.RegisterEvent("UPDATE_SHAPESHIFT_FORM", onStateEvent)
    sfui.events.RegisterEvent("UPDATE_SHAPESHIFT_FORMS", onStateEvent)
    sfui.events.RegisterEvent("UPDATE_STEALTH", onStateEvent)
    sfui.events.RegisterEvent("PLAYER_UPDATE_RESTING", onStateEvent)
    sfui.events.RegisterEvent("PLAYER_ALIVE", onStateEvent)
    sfui.events.RegisterEvent("PLAYER_DEAD", onStateEvent)
    sfui.events.RegisterEvent("PLAYER_UNGHOST", onStateEvent)
    sfui.events.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", onStateEvent)
    sfui.events.RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", onStateEvent)
    sfui.events.RegisterEvent("PLAYER_TALENT_UPDATE", onStateEvent)
    if sfui.isRetail then
        sfui.events.RegisterEvent("PLAYER_CAN_GLIDE_CHANGED", onStateEvent)
        sfui.events.RegisterEvent("PET_BATTLE_OPENING_START", onStateEvent)
        sfui.events.RegisterEvent("PET_BATTLE_CLOSE", onStateEvent)
    end
    if sfui.events.RegisterUnitEvents then
        sfui.events.RegisterUnitEvents({ "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE" }, "player", onStateEvent)
    end
    if sfui.events.RegisterMessage then
        sfui.events.RegisterMessage("SFUI_SPEC_CHANGED", function() RefreshState() end)
        sfui.events.RegisterMessage("SFUI_GEAR_ROLE_CHANGED", function() RefreshState() end)
        sfui.events.RegisterMessage("SFUI_ROLE_CONTEXT_CHANGED", function() RefreshState() end)
    end
end

if sfui.RegisterModule then
    sfui.RegisterModule("state", S)
end

