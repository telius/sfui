local addonName, addon = ...
sfui = sfui or {}
sfui.lootviewer = sfui.lootviewer or {}
sfui.is_ready_for_vendor_frame = false

local function default_lootviewer_toggle()
    if not sfui.isRetail then
        local dj = sfui.lootviewer_camelot or sfui.dungeonjournal
        if dj and dj.Toggle and dj.Toggle ~= default_lootviewer_toggle then
            dj.Toggle()
        end
    elseif sfui.lootviewer and sfui.lootviewer.Toggle and sfui.lootviewer.Toggle ~= default_lootviewer_toggle then
        sfui.lootviewer.Toggle()
    end
end
sfui.ToggleLootViewer = default_lootviewer_toggle

if not sfui.lootviewer.Toggle then
    sfui.lootviewer.Toggle = default_lootviewer_toggle
end

-- Localize Globals
local _G = _G
local print = print
local type = type
local tonumber = tonumber
local string_lower = string.lower
local string_match = string.match
local string_gmatch = string.gmatch

local CreateFrame = CreateFrame
local UIParent = UIParent
local IsShiftKeyDown = IsShiftKeyDown
local GetCVar = GetCVar
local C_CVar = C_CVar
local C_UI = C_UI
local C_AddOns = C_AddOns
local LibStub = LibStub

local ipairs = ipairs
local tostring = tostring

local function update_pixel_scale()
    local resolution = GetCVar("gxWindowedResolution")
    if resolution then
        local height = tonumber(string_match(resolution, "%d+x(%d+)"))
        if height then sfui.pixelScale = 768 / (height * UIParent:GetScale()) end
    end
end
sfui.update_pixel_scale = update_pixel_scale

-- Scale updates via central dispatcher
sfui.events.RegisterEvent("UI_SCALE_CHANGED", update_pixel_scale)

-- ────────────────────────────────────────────────────────────────────────────
-- Unified Class Utility Secure Action Button & Keybinding Resolution
-- ────────────────────────────────────────────────────────────────────────────
sfui.keybinds = sfui.keybinds or {}

function sfui.keybinds.format_key(key)
    if not key or key == "" then return "" end
    return key:gsub("SHIFT%-", "S-")
              :gsub("CTRL%-", "C-")
              :gsub("ALT%-", "A-")
              :gsub("NUMPAD", "N")
              :gsub("MOUSEWHEELUP", "WU")
              :gsub("MOUSEWHEELDOWN", "WD")
end

function sfui.keybinds.get_action_key(action)
    if not action then return "" end
    local key = _G.GetBindingKey and _G.GetBindingKey(action)
    return sfui.keybinds.format_key(key)
end

sfui.common = sfui.common or {}
sfui.common.format_keybind = sfui.keybinds.format_key
sfui.common.get_binding_text = sfui.keybinds.get_action_key

local ACTION_CLASS_UTILITY  = "CLICK SfuiClassUtilityBtn:LeftButton"
local ACTION_TRIAGE_DELETE   = "CLICK SfuiTriageDeleteBtn:LeftButton"
local ACTION_TOTEM_SEQUENCE = "CLICK SfuiTotemSequenceBtn:LeftButton"
local ACTION_PURGE_SHARDS   = "CLICK SfuiPurgeSoulShards:LeftButton"
local ACTION_PORTALS_BTN    = "CLICK SfuiPortalsBtn:LeftButton"
local ACTION_PORTALS        = "SFUI_PORTALS"

local portalsBtn = _G.CreateFrame("Button", "SfuiPortalsBtn", UIParent)
portalsBtn:SetScript("OnClick", function()
    if sfui.portals and sfui.portals.Toggle then
        sfui.portals.Toggle()
    end
end)

local classUtilityBtn = _G.CreateFrame("Button", "SfuiClassUtilityBtn", UIParent, "SecureActionButtonTemplate")
classUtilityBtn:RegisterForClicks("AnyUp", "AnyDown")

local purgeShardsBtn = _G.SfuiPurgeSoulShards or _G.CreateFrame("Button", "SfuiPurgeSoulShards", UIParent)
purgeShardsBtn:RegisterForClicks("AnyUp", "AnyDown")
purgeShardsBtn:SetScript("OnClick", function(self, button, down)
    local inCombat = (sfui.common and sfui.common.is_in_combat and sfui.common.is_in_combat())
        or (_G.InCombatLockdown and _G.InCombatLockdown())
        or (_G.UnitAffectingCombat and _G.UnitAffectingCombat("player"))
    if inCombat then
        if _G.SfuiBagTriagePrompt and _G.SfuiBagTriagePrompt:IsShown() then
            _G.SfuiBagTriagePrompt:Hide()
        end
        return
    end
    if _G.SfuiBagTriagePrompt and _G.SfuiBagTriagePrompt:IsShown() and _G.SfuiTriageDeleteBtn then
        _G.SfuiTriageDeleteBtn:Click(button, down)
    elseif sfui.triage and sfui.triage.ExecutePurge then
        sfui.triage.ExecutePurge(nil, down)
    elseif sfui.triage and sfui.triage.PurgeSoulShards then
        sfui.triage.PurgeSoulShards(nil, down)
    end
end)
_G.SfuiPurgeSoulShards = purgeShardsBtn

local function configure_class_utility_button()
    local _, pClass = _G.UnitClass("player")
    if pClass == "SHAMAN" then
        classUtilityBtn:SetAttribute("*type*", "click")
        classUtilityBtn:SetAttribute("*clickbutton*", _G.SfuiTotemSequenceBtn)
        classUtilityBtn:SetAttribute("type", "click")
        if _G.SfuiTotemSequenceBtn then
            classUtilityBtn:SetAttribute("clickbutton", _G.SfuiTotemSequenceBtn)
        end
        classUtilityBtn:SetAttribute("macrotext", nil)
    elseif pClass == "WARLOCK" then
        classUtilityBtn:SetAttribute("*type*", "click")
        classUtilityBtn:SetAttribute("*clickbutton*", purgeShardsBtn)
        classUtilityBtn:SetAttribute("type", "click")
        classUtilityBtn:SetAttribute("clickbutton", purgeShardsBtn)
        classUtilityBtn:SetAttribute("macrotext", nil)
    else
        classUtilityBtn:SetAttribute("type", nil)
        classUtilityBtn:SetAttribute("clickbutton", nil)
        classUtilityBtn:SetAttribute("macrotext", nil)
    end
end
sfui.keybinds.configure_class_utility_button = configure_class_utility_button
configure_class_utility_button()

local function get_primary_class_utility_action()
    local _, pClass = _G.UnitClass("player")
    if pClass == "WARLOCK" then
        return ACTION_CLASS_UTILITY
    elseif pClass == "SHAMAN" then
        return ACTION_TOTEM_SEQUENCE
    end
    return ACTION_CLASS_UTILITY
end

function sfui.keybinds.GetClassUtilityKey()
    local primaryAction = get_primary_class_utility_action()
    local actions = {
        primaryAction,
        ACTION_CLASS_UTILITY,
        ACTION_TRIAGE_DELETE,
        ACTION_TOTEM_SEQUENCE,
        ACTION_PURGE_SHARDS,
    }
    local k1
    for _, action in ipairs(actions) do
        if _G.GetBindingKey then
            local bk1, bk2 = _G.GetBindingKey(action)
            k1 = (bk1 and bk1 ~= "") and bk1 or bk2
            if k1 and k1 ~= "" then break end
        end
    end
    if (not k1 or k1 == "") and SfuiDB then
        k1 = SfuiDB.classUtilityKeybind or (SfuiDB.totembar and SfuiDB.totembar.keybind)
    end
    if not k1 or k1 == "" then return nil, "" end
    local formatted = sfui.keybinds.format_key(k1)
    return k1, formatted
end

function sfui.keybinds.SetClassUtilityKey(newKey)
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        if sfui.common and sfui.common.print then
            sfui.common.print("cannot modify bindings in combat.")
        end
        return false
    end
    if not newKey or newKey == "" then return false end

    newKey = tostring(newKey):upper()
    configure_class_utility_button()
    local primaryAction = get_primary_class_utility_action()

    local actions = {
        ACTION_CLASS_UTILITY,
        ACTION_TRIAGE_DELETE,
        ACTION_TOTEM_SEQUENCE,
        ACTION_PURGE_SHARDS,
    }

    for _, action in ipairs(actions) do
        if _G.GetBindingKey and _G.SetBinding then
            local k1, k2 = _G.GetBindingKey(action)
            if k1 then _G.SetBinding(k1, nil) end
            if k2 then _G.SetBinding(k2, nil) end
        end
    end

    if _G.SetBinding then
        _G.SetBinding(newKey, primaryAction)
    end

    local bindingSet = (_G.GetCurrentBindingSet and _G.GetCurrentBindingSet()) or 1
    if _G.SaveBindings then
        _G.SaveBindings(bindingSet)
    end

    SfuiDB = SfuiDB or {}
    SfuiDB.classUtilityKeybind = newKey
    if SfuiDB.totembar then
        SfuiDB.totembar.keybind = newKey
    end

    if sfui.common and sfui.common.print then
        local formatted = sfui.keybinds.format_key(newKey)
        local _, pClass = _G.UnitClass("player")
        local role = (pClass == "SHAMAN" and "totem sequence")
            or (pClass == "WARLOCK" and "soul shard purge")
            or "class utility"
        sfui.common.print(role .. " bound to " .. formatted:lower() .. ".")
    end
    return true
end

function sfui.keybinds.UnbindClassUtilityKey()
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        if sfui.common and sfui.common.print then
            sfui.common.print("cannot modify bindings in combat.")
        end
        return false
    end

    local actions = {
        ACTION_CLASS_UTILITY,
        ACTION_TRIAGE_DELETE,
        ACTION_TOTEM_SEQUENCE,
        ACTION_PURGE_SHARDS,
    }
    for _, action in ipairs(actions) do
        if _G.GetBindingKey and _G.SetBinding then
            local k1, k2 = _G.GetBindingKey(action)
            if k1 then _G.SetBinding(k1, nil) end
            if k2 then _G.SetBinding(k2, nil) end
        end
    end

    local bindingSet = (_G.GetCurrentBindingSet and _G.GetCurrentBindingSet()) or 1
    if _G.SaveBindings then
        _G.SaveBindings(bindingSet)
    end

    SfuiDB = SfuiDB or {}
    SfuiDB.classUtilityKeybind = nil
    if SfuiDB.totembar then
        SfuiDB.totembar.keybind = nil
    end

    if sfui.common and sfui.common.print then
        sfui.common.print("class utility keybind cleared.")
    end
    return true
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Dedicated Portals & Teleports Keybind (Retail & Camelot)
-- ─────────────────────────────────────────────────────────────────────────────
function sfui.keybinds.GetPortalsKey()
    local actions = {
        ACTION_PORTALS,
        ACTION_PORTALS_BTN,
    }
    local k1
    for _, action in ipairs(actions) do
        if _G.GetBindingKey then
            local bk1, bk2 = _G.GetBindingKey(action)
            k1 = (bk1 and bk1 ~= "") and bk1 or bk2
            if k1 and k1 ~= "" then break end
        end
    end
    if (not k1 or k1 == "") and SfuiDB then
        local dbKey = sfui.isRetail and "portalsKeybind" or "portalsKeybindCamelot"
        k1 = SfuiDB[dbKey]
    end
    if not k1 or k1 == "" then return nil, "" end
    local formatted = sfui.keybinds.format_key(k1)
    return k1, formatted
end

function sfui.keybinds.SetPortalsKey(newKey)
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        if sfui.common and sfui.common.print then
            sfui.common.print("cannot modify bindings in combat.")
        end
        return false
    end
    if not newKey or newKey == "" then return false end

    newKey = tostring(newKey):upper()
    local actions = {
        ACTION_PORTALS,
        ACTION_PORTALS_BTN,
    }

    for _, action in ipairs(actions) do
        if _G.GetBindingKey and _G.SetBinding then
            local k1, k2 = _G.GetBindingKey(action)
            if k1 then _G.SetBinding(k1, nil) end
            if k2 then _G.SetBinding(k2, nil) end
        end
    end

    if _G.SetBinding then
        _G.SetBinding(newKey, ACTION_PORTALS)
    end

    local bindingSet = (_G.GetCurrentBindingSet and _G.GetCurrentBindingSet()) or 1
    if _G.SaveBindings then
        _G.SaveBindings(bindingSet)
    end

    SfuiDB = SfuiDB or {}
    local dbKey = sfui.isRetail and "portalsKeybind" or "portalsKeybindCamelot"
    SfuiDB[dbKey] = newKey

    if sfui.common and sfui.common.print then
        local formatted = sfui.keybinds.format_key(newKey)
        sfui.common.print("portals bound to " .. formatted:lower() .. ".")
    end
    return true
end

function sfui.keybinds.UnbindPortalsKey()
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        if sfui.common and sfui.common.print then
            sfui.common.print("cannot modify bindings in combat.")
        end
        return false
    end

    local actions = {
        ACTION_PORTALS,
        ACTION_PORTALS_BTN,
    }
    for _, action in ipairs(actions) do
        if _G.GetBindingKey and _G.SetBinding then
            local k1, k2 = _G.GetBindingKey(action)
            if k1 then _G.SetBinding(k1, nil) end
            if k2 then _G.SetBinding(k2, nil) end
        end
    end

    local bindingSet = (_G.GetCurrentBindingSet and _G.GetCurrentBindingSet()) or 1
    if _G.SaveBindings then
        _G.SaveBindings(bindingSet)
    end

    SfuiDB = SfuiDB or {}
    local dbKey = sfui.isRetail and "portalsKeybind" or "portalsKeybindCamelot"
    SfuiDB[dbKey] = nil

    if sfui.common and sfui.common.print then
        sfui.common.print("portals keybind cleared.")
    end
    return true
end

-- Sync keybinds on player login
sfui.events.RegisterEvent("PLAYER_LOGIN", function()
    if _G.InCombatLockdown and _G.InCombatLockdown() then return end

    -- Sync class utility keybind (shaman totem sequence / warlock shard purge) - camelot/classic only
    if not sfui.isRetail then
        configure_class_utility_button()
        local k1 = sfui.keybinds.GetClassUtilityKey()
        if k1 and k1 ~= "" and _G.SetBinding then
            local primaryAction = get_primary_class_utility_action()
            local cur = _G.GetBindingKey and _G.GetBindingKey(primaryAction)
            if not cur or cur == "" then
                local actions = {
                    ACTION_CLASS_UTILITY,
                    ACTION_TOTEM_SEQUENCE,
                    ACTION_PURGE_SHARDS,
                }
                for _, act in ipairs(actions) do
                    if act ~= primaryAction and _G.GetBindingKey then
                        local bk1, bk2 = _G.GetBindingKey(act)
                        if bk1 == k1 then _G.SetBinding(bk1, nil) end
                        if bk2 == k1 then _G.SetBinding(bk2, nil) end
                    end
                end
                _G.SetBinding(k1, primaryAction)
            end
        end
    end

    -- Sync portals keybind (retail & camelot)
    local pk1 = sfui.keybinds.GetPortalsKey()
    if pk1 and pk1 ~= "" and _G.SetBinding then
        local cur = _G.GetBindingKey and _G.GetBindingKey(ACTION_PORTALS)
        if not cur or cur == "" then
            local curBtn = _G.GetBindingKey and _G.GetBindingKey(ACTION_PORTALS_BTN)
            if not curBtn or curBtn == "" then
                _G.SetBinding(pk1, ACTION_PORTALS)
            end
        end
    end
end)

local isInitialized = false
local function initialize_sfui()
    if isInitialized then return end
    isInitialized = true

    sfui.common.invalidate_panels_cache()
    local LSM = LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local function register_statusbar_media(name, path)
            if not name or not path then return end
            -- LibSharedMedia only accepts file paths starting with "Interface" or numeric fileIDs.
            -- Atlas element names cannot be registered directly in LSM and cause errors in strict LSM builds.
            local isNumeric = type(path) == "number"
            local isFilePath = type(path) == "string" and path:find("^[iI]nterface[/\\]")
            if not isNumeric and not isFilePath then
                return
            end
            if isFilePath and _G.C_UIFileAsset and _G.C_UIFileAsset.IsKnownFile then
                if not _G.C_UIFileAsset.IsKnownFile(path) then
                    return
                end
            end
            pcall(LSM.Register, LSM, "statusbar", name, path)
        end

        if sfui.config.blizzard_bar_textures then
            for name, path in pairs(sfui.config.blizzard_bar_textures) do
                register_statusbar_media(name, path)
            end
        else
            register_statusbar_media("Flat", "Interface/Buttons/WHITE8X8")
            register_statusbar_media("Blizzard", "Interface/TargetingFrame/UI-StatusBar")
            register_statusbar_media("Blizzard Target Bar", "Interface/TargetingFrame/UI-TargetingFrame-BarFill")
            register_statusbar_media("Blizzard Character Skills Bar", "Interface/PaperDollInfoFrame/UI-Character-Skills-Bar")
            register_statusbar_media("Blizzard Raid Bar", "Interface/RaidFrame/Raid-Bar-Hp-Fill")
            register_statusbar_media("Blizzard Raid Resource", "Interface/RaidFrame/Raid-Bar-Resource-Fill")
            register_statusbar_media("Blizzard Raid Health", "Interface/RaidFrame/UI-RaidFrame-HealthBar")
            register_statusbar_media("Blizzard Shield Fill", "Interface/RaidFrame/Shield-Fill")
            register_statusbar_media("Blizzard Absorb Fill", "Interface/RaidFrame/Absorb-Fill")
            register_statusbar_media("Blizzard Professions", "Interface/Spellbook/Professions-Progress-Fill")
            register_statusbar_media("Blizzard Archaeology", "Interface/Archeology/Arch-Progress-Fill")
        end
    end

    -- Database & Config Sync
    SfuiDB = SfuiDB or {}
    SfuiDB.alts = SfuiDB.alts or {}
    SfuiDB.altsHiddenSections = SfuiDB.altsHiddenSections or {}
    SfuiDB.altsCollapsed = SfuiDB.altsCollapsed or {}
    SfuiDB.minimap_icon = SfuiDB.minimap_icon or {}
    SfuiDB.gear = SfuiDB.gear or {}
    SfuiDB.gear_char = SfuiDB.gear_char or {}
    SfuiDB.trackedBars = SfuiDB.trackedBars or {}
    SfuiDB.iconGlobalSettings = SfuiDB.iconGlobalSettings or {}
    SfuiDB.trackedOptionsWindow = SfuiDB.trackedOptionsWindow or {}
    SfuiDB.currencyCaps = SfuiDB.currencyCaps or {}
    SfuiDB.items = SfuiDB.items or {}
    if sfui.isRetail then
        SfuiDB.mythicBestTimes = SfuiDB.mythicBestTimes or {}
        SfuiDB.lootspec = SfuiDB.lootspec or {}
        SfuiDB.bonusroll = SfuiDB.bonusroll or {}
        SfuiDB.worldevents = SfuiDB.worldevents or {}
    end
    SfuiDB.spec_colors = SfuiDB.spec_colors or {}
    -- Migration: Purge legacy blue or interim orange for Balance Druid (102 and 14841) and Base Druid (1484)
    for _, sID in ipairs({ 102, 14841, 1484 }) do
        local c = SfuiDB.spec_colors[sID]
        if c then
            local r, g, b = c[1] or c.r or 0, c[2] or c.g or 0, c[3] or c.b or 0
            local isLegacyBlue = (r >= 0.18 and r <= 0.22) and (g <= 0.05) and (b >= 0.78 and b <= 0.82)
            local isInterimOrange = (r >= 0.98) and (g >= 0.45 and g <= 0.53) and (b <= 0.06)
            if isLegacyBlue or isInterimOrange then
                SfuiDB.spec_colors[sID] = nil
            end
        end
    end
    -- Migration: Purge legacy generic class blue or interim orange/red-orange for Arcane (62, 14821) and Fire (63, 14822)
    for _, sID in ipairs({ 62, 63, 14821, 14822 }) do
        local c = SfuiDB.spec_colors[sID]
        if c then
            local r, g, b = c[1] or c.r or 0, c[2] or c.g or 0, c[3] or c.b or 0
            local isLegacyClassBlue = (r >= 0.23 and r <= 0.27) and (g >= 0.76 and g <= 0.80) and (b >= 0.90 and b <= 0.94)
            local isInterimOrange = (r >= 0.98) and (g >= 0.38 and g <= 0.55) and (b <= 0.10)
            if isLegacyClassBlue or isInterimOrange then
                SfuiDB.spec_colors[sID] = nil
            end
        end
    end
    SfuiDB.hearthstone = SfuiDB.hearthstone or {}
    SfuiDB.theme = SfuiDB.theme or {}
    if SfuiDB.theme.mode == nil and SfuiDB.themeMode == nil then
        local defMode = sfui.isCamelot and "bronze" or "modern"
        SfuiDB.theme.mode = defMode
        SfuiDB.themeMode = defMode
    end

    sfui.db.Initialize()
    sfui.InitModules()

    sfui.initialize_database()
    sfui.theme.ApplyCurrentTheme()

    -- Migrate cooldown panels to per-spec structure
    sfui.common.migrate_cooldown_panels_to_spec()

    local tocVersion = sfui.common.get_addon_metadata(addonName or "sfui", "Version")
    if tocVersion then
        sfui.config.version = tocVersion
    end

    if sfui.config.cvars_on_load then
        for _, cvar_data in ipairs(sfui.config.cvars_on_load) do
            if sfui.common and sfui.common.set_cvar then
                sfui.common.set_cvar(cvar_data.name, cvar_data.value)
            elseif (not InCombatLockdown or not InCombatLockdown()) then
                local setCVar = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
                local getCVar = (C_CVar and C_CVar.GetCVar) or _G.GetCVar
                if setCVar and (not getCVar or getCVar(cvar_data.name) ~= nil) then
                    setCVar(cvar_data.name, cvar_data.value)
                end
            end
        end
    end

    -- Migrate legacy SCT CVars to _v2
    local legacyCVars = {
        "floatingCombatTextDodgeParryMiss",
        "floatingCombatTextDamageReduction",
        "floatingCombatTextEnergyGains",
        "floatingCombatTextAuras",
        "floatingCombatTextCombatState",
        "floatingCombatTextCombatDamage",
        "floatingCombatTextCombatLogPeriodicSpells",
        "floatingCombatTextCombatHealing",
    }
    for _, legacy in ipairs(legacyCVars) do
        if SfuiDB[legacy] ~= nil and SfuiDB[legacy .. "_v2"] == nil then
            SfuiDB[legacy .. "_v2"] = SfuiDB[legacy]
        end
    end

    -- Enforce Combat Text Settings from DB
    local combatTextCVars = {
        "enableFloatingCombatText",
        "floatingCombatTextCombatDamage",
        "floatingCombatTextCombatDamage_v2",
        "floatingCombatTextCombatLogPeriodicSpells",
        "floatingCombatTextCombatLogPeriodicSpells_v2",
        "floatingCombatTextCombatHealing",
        "floatingCombatTextCombatHealing_v2",
        "floatingCombatTextPetMeleeDamage",
        "floatingCombatTextPetSpellDamage",
        "floatingCombatTextDodgeParryMiss_v2",
        "floatingCombatTextDamageReduction_v2",
        "floatingCombatTextEnergyGains_v2",
        "floatingCombatTextAuras_v2",
        "floatingCombatTextCombatState_v2"
    }
    for _, cvar in ipairs(combatTextCVars) do
        if SfuiDB[cvar] ~= nil then
            if sfui.common and sfui.common.set_cvar then
                sfui.common.set_cvar(cvar, SfuiDB[cvar] and "1" or "0")
            elseif (not InCombatLockdown or not InCombatLockdown()) then
                local setCVar = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
                local getCVar = (C_CVar and C_CVar.GetCVar) or _G.GetCVar
                if setCVar and (not getCVar or getCVar(cvar) ~= nil) then
                    setCVar(cvar, SfuiDB[cvar] and "1" or "0")
                end
            end
        end
    end
end

sfui.events.RegisterEvent("ADDON_LOADED", function(_, name)
    local lname = string_lower(name or "")
    if lname == "sfui" or lname == string_lower(addonName or "") then
        initialize_sfui()
    end
end)

-- Baganator-style check: If sfui has already finished loading, execute immediately
local isAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
if isAddOnLoaded and select(2, isAddOnLoaded(addonName or "sfui")) then
    initialize_sfui()
end

sfui.events.RegisterEvent("PLAYER_LOGIN", function(event)
    sfui.update_pixel_scale()

    sfui.EnableModules()

    sfui.common.hide_blizzard_cooldown_viewers()

    sfui.create_currency_frame()
    sfui.create_item_frame()
    local function is_unregistered(modName)
        return not (sfui.modules and sfui.modules[modName])
    end

    local isRetail = sfui.isRetail
    if is_unregistered("bars") then
        sfui.bars:on_state_changed()
    end
    if is_unregistered("castbar") or not sfui.castbar.bars then
        sfui.castbar.initialize()
    end
    if is_unregistered("compare") then
        sfui.compare.init()
    end
    if is_unregistered("gear") then
        sfui.gear.initialize()
    end
    if isRetail and is_unregistered("hammer") then
        sfui.hammer.initialize()
    end
    if isRetail and is_unregistered("research") then
        sfui.research.initialize()
    end
    if is_unregistered("automation") then
        sfui.automation.initialize()
    end
    if is_unregistered("cursor") or not _G.SfuiCursor then
        sfui.cursor.initialize()
    end
    if is_unregistered("trackedbars") then
        sfui.trackedbars.initialize()
    end
    if is_unregistered("trackedicons") then
        sfui.trackedicons.initialize()
    end
    if is_unregistered("trackedoptions") then
        sfui.trackedoptions.initialize()
    end
    if is_unregistered("alts") then
        sfui.alts.initialize()
    end
    if is_unregistered("portals") and sfui.portals and sfui.portals.initialize then
        sfui.portals.initialize()
    end
    if isRetail and is_unregistered("lootspec") then
        sfui.lootspec.initialize()
    end
    if is_unregistered("lootviewer") and sfui.lootviewer and sfui.lootviewer.initialize then
        sfui.lootviewer.initialize()
    end
    if is_unregistered("questlog") then
        sfui.questlog.initialize()
    end

    sfui.theme.ApplyCurrentTheme()

    if not LibStub then
        sfui.common.print("|cffff0000error:|r libstub global not found!")
        return
    end

    -- Initialize Minimap Menu
    if not SfuiMinimapMenu then
        SfuiMinimapMenu = CreateFrame("Frame", "SfuiMinimapMenu", UIParent, "BackdropTemplate")
        SfuiMinimapMenu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        SfuiMinimapMenu:SetBackdropColor(0, 0, 0, 0.5)
        SfuiMinimapMenu:SetFrameStrata("TOOLTIP")
        SfuiMinimapMenu:SetClampedToScreen(true)

        local menuButtons = {
            {
                text = "|cffffffffoptions|r",
                func = function() sfui.toggle_options_panel() end,
            },
            {
                text = "|cff00ff00tracking manager|r",
                func = function()
                    sfui.trackedoptions.toggle_viewer()
                end,
            },
            {
                text = "|cff9966ffalts|r",
                func = function()
                    sfui.alts.Toggle()
                end,
            },
        }

        if sfui.portals and sfui.portals.Toggle then
            table.insert(menuButtons, {
                text = "|cffff9900portals|r",
                func = function()
                    sfui.portals.Toggle()
                end,
            })
        end

        if isRetail and sfui.lootviewer and sfui.lootviewer.Toggle then
            table.insert(menuButtons, {
                text = "|cff22aaffloot browser|r",
                func = function()
                    sfui.lootviewer.Toggle()
                end,
            })
        elseif not isRetail and sfui.lootviewer_camelot and sfui.lootviewer_camelot.Toggle then
            table.insert(menuButtons, {
                text = "|cffd1a652dungeon journal|r",
                func = function()
                    sfui.lootviewer_camelot.Toggle()
                end,
            })
        end

        if sfui.recipes and sfui.recipes.ToggleBrowser then
            table.insert(menuButtons, {
                text = "|cffffd100recipes|r",
                func = function()
                    sfui.recipes.ToggleBrowser()
                end,
            })
        end

        if _G.C_PetJournal and _G.C_PetJournal.GetNumPets then
            table.insert(menuButtons, {
                text = "|cffff99ccpet manager|r",
                func = function()
                    sfui.pets.Toggle()
                end,
            })
        end

        table.insert(menuButtons, {
            text = "|cff6600ffmemory profiler|r",
            func = function()
                sfui.mem.ToggleGUI()
            end,
        })

        local y = -5
        for _, item in ipairs(menuButtons) do
            local btn = sfui.common.create_flat_button(SfuiMinimapMenu, item.text, 150, 20)
            btn:SetPoint("TOP", 0, y)
            btn:SetScript("OnClick", function()
                SfuiMinimapMenu:Hide()
                if item.func then item.func() end
            end)
            y = y - 25
        end
        SfuiMinimapMenu:SetSize(160, -y + 5)

        local function on_menu_update(self, elapsed)
            self.throttle = self.throttle + elapsed
            if self.throttle < 0.5 then return end
            self.throttle = 0

            if self:IsMouseOver() or (self.anchor and self.anchor:IsMouseOver()) then
                self.hideTimer = 0
            else
                self.hideTimer = (self.hideTimer or 0) + 0.5
                if self.hideTimer > 0.5 then
                    self:Hide()
                end
            end
        end

        SfuiMinimapMenu:SetScript("OnShow", function(self)
            self.throttle = 0
            self.hideTimer = 0
            self:SetScript("OnUpdate", on_menu_update)
        end)
        SfuiMinimapMenu:SetScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
        end)
        SfuiMinimapMenu:Hide()
    end

    local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
    local icon = LibStub and LibStub("LibDBIcon-1.0", true)
    if ldb and icon and icon.Register then
        local broker = ldb:GetDataObjectByName("sfui")
        if not broker then
            broker = ldb:NewDataObject("sfui", {
                type = "launcher",
                text = "sfui",
                icon = sfui.config.appearance.addonIcon,
                OnClick = function(self, button)
                    if button == "LeftButton" then
                        if SfuiMinimapMenu:IsShown() then
                            SfuiMinimapMenu:Hide()
                        else
                            SfuiMinimapMenu.anchor = self
                            SfuiMinimapMenu.throttle = 0
                            SfuiMinimapMenu.hideTimer = 0
                            SfuiMinimapMenu:ClearAllPoints()
                            SfuiMinimapMenu:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, -5)
                            SfuiMinimapMenu:Show()
                        end
                    elseif button == "RightButton" then
                        if IsShiftKeyDown() then
                            if C_UI and C_UI.Reload then C_UI.Reload() elseif _G.ReloadUI then _G.ReloadUI() end
                        else
                            sfui.alts.Toggle()
                        end
                    end
                end,
                OnTooltipShow = function(tooltip)
                    tooltip:AddLine("sfui")
                    tooltip:AddLine("left-click for menu", 0.2, 1, 0.2)
                    tooltip:AddLine("right-click for alts", 0.4, 0.7, 1)
                    tooltip:AddLine("shift+right-click to reload ui", 1, 0.2, 0.2)
                end,
            })
        end
        if broker and (not icon.IsRegistered or not icon:IsRegistered("sfui")) then
            icon:Register("sfui", broker, SfuiDB.minimap_icon)
        end
    end
end)
