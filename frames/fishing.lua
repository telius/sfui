local addonName, addon = ...
sfui = sfui or {}
sfui.fishing = sfui.fishing or {}

local g      = sfui.config
local common = sfui.common
local cfg    = g.fishing or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/fishing.lua
--  Integrated One-Key & Double-Click Fishing Automation
--  Zero-taint secure action handling, soft-targeting bobber interact, and
--  dynamic acoustic enhancement during casts.
--  Cross-version compatible: Retail, Camelot, Classic Era.
-- ══════════════════════════════════════════════════════════════════════════════

-- Localize frequently-called globals for execution performance
local CreateFrame             = _G.CreateFrame
local InCombatLockdown        = _G.InCombatLockdown
local SetOverrideBinding      = _G.SetOverrideBinding
local SetOverrideBindingClick = _G.SetOverrideBindingClick
local SetOverrideBindingSpell = _G.SetOverrideBindingSpell
local ClearOverrideBindings   = _G.ClearOverrideBindings
local GetBindingKey           = _G.GetBindingKey
local GetTime                 = _G.GetTime
local SetCVar                 = _G.SetCVar
local GetCVar                 = _G.GetCVar
local GetCVarBool             = _G.GetCVarBool
local UnitChannelInfo         = _G.UnitChannelInfo
local ChannelInfo             = _G.ChannelInfo
local IsPlayerMoving          = _G.IsPlayerMoving
local IsMounted               = _G.IsMounted
local IsFlying                = _G.IsFlying
local IsFalling               = _G.IsFalling
local IsStealthed             = _G.IsStealthed
local IsSwimming              = _G.IsSwimming
local IsSubmerged             = _G.IsSubmerged
local UnitHasVehicleUI        = _G.UnitHasVehicleUI
local HasFullControl          = _G.HasFullControl
local IsMouseButtonDown       = _G.IsMouseButtonDown
local IsModifierKeyDown       = _G.IsModifierKeyDown
local GetNumLootItems         = _G.GetNumLootItems
local SecureHandlerWrapScript = _G.SecureHandlerWrapScript
local MouselookStart          = _G.MouselookStart
local MouselookStop           = _G.MouselookStop
local C_Spell                 = _G.C_Spell
local C_SpellBook             = _G.C_SpellBook
local C_Timer                 = _G.C_Timer
local C_UnitAuras             = _G.C_UnitAuras
local C_Secrets               = _G.C_Secrets
local pcall, type, ipairs, pairs = _G.pcall, _G.type, _G.ipairs, _G.pairs
local table_insert            = table.insert
local table_remove            = table.remove
local wipe                    = _G.wipe or table.wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

-- Global keybind identifiers
_G["BINDING_NAME_SFUI_FISHING"] = "Cast & Catch Fishing"
_G["BINDING_NAME_BETTERFISHINGKEY"] = "Cast & Catch Fishing" -- Backwards compat with BetterFishing binds

local DOUBLECLICK_MIN_SECONDS = 0.04
local SECURE_BUTTON_NAME = "SfuiFishingButton"

local FishingIDs = {
    [131474]  = true, -- Live/MoP base fishing
    [131490]  = true, -- MoP+ with pole equipped
    [131476]  = true, -- Live/MoP without pole equipped
    [7620]    = true, -- Classic Apprentice Fishing
    [7731]    = true, -- Journeyman
    [7732]    = true, -- Expert
    [18248]   = true, -- Artisan
    [33095]   = true, -- Master
    [51294]   = true, -- Grand Master
    [88868]   = true, -- Illustrious
    [110410]  = true, -- MoP fishing
    [158743]  = true, -- WoD Fishing
    [377895]  = true, -- Ice Fishing
    [1224771] = true, -- Void Fishing
}

local SoundCVars = {
    "Sound_MasterVolume",
    "Sound_SFXVolume",
    "Sound_EnableAmbience",
    "Sound_MusicVolume",
    "Sound_EnableAllSound",
    "Sound_EnablePetSounds",
    "Sound_EnableSoundWhenGameIsInBG",
    "Sound_EnableSFX",
}

local SoftTargetCVars = {
    "SoftTargetInteract",
    "SoftTargetInteractArc",
    "SoftTargetInteractRange",
    "SoftTargetIconGameObject",
    "SoftTargetIconInteract",
}

-- Module State
local _state = {
    secureButton = nil,
    previousClickTime = 0,
    lastCastTime = 0,
    isInteractBinding = false,
    cvarsChanged = false,
    soundsEnhanced = false,
    isRestoringSounds = false,
    soundCache = {},
    interactCVarCache = {},
    pendingTasks = {},
}

-- Register module defaults with sfui.db
local defaults = {
    enabled = true,
    doubleClick = true,
    doubleClickSpeed = 0.4,
    doubleClickForce = false, -- allow when mounted
    enhanceSounds = true,
    enhanceSoundsScale = 1.0,
    softTarget = true,
    recastOnDoubleClick = false,
    overrideLunker = false,
}
sfui.db.RegisterDefaults("fishing", defaults)

local optionsKeyMap = {
    enabled             = "fishingEnabled",
    doubleClick         = "fishingDoubleClick",
    doubleClickSpeed    = "fishingDoubleClickSpeed",
    doubleClickForce    = "fishingMounted",
    enhanceSounds       = "fishingEnhanceSounds",
    enhanceSoundsScale  = "fishingSoundScale",
    softTarget          = "fishingSoftTarget",
    recastOnDoubleClick = "fishingRecast",
    overrideLunker      = "fishingOverrideLunker",
}

local function get_setting(key, fallback)
    local optKey = optionsKeyMap[key]
    if optKey and SfuiDB and SfuiDB[optKey] ~= nil then
        return SfuiDB[optKey]
    end
    return sfui.db.Get("fishing", key, fallback)
end

-- ─── Safe CVar Accessors ─────────────────────────────────────────────────────

local function safe_get_cvar(cvar)
    if not GetCVar then return nil end
    local ok, val = pcall(GetCVar, cvar)
    if ok then return val end
    return nil
end

local function safe_set_cvar(cvar, val)
    if not SetCVar or not GetCVar then return end
    if safe_get_cvar(cvar) ~= nil then
        pcall(SetCVar, cvar, val)
    end
end

-- Cache baseline soft target CVars on load (only if client supports them)
for _, cvar in ipairs(SoftTargetCVars) do
    local val = safe_get_cvar(cvar)
    if val ~= nil then
        _state.interactCVarCache[cvar:lower()] = val
    end
end

-- ─── Skill & Spell Detection (Cross-Client) ──────────────────────────────────

local isClassicEra = (WOW_PROJECT_ID == WOW_PROJECT_CLASSIC)

local function is_spell_known(spellID)
    if not spellID then return false end
    if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook then
        local ok, known = pcall(C_SpellBook.IsSpellKnownOrInSpellBook, spellID)
        if ok and known then return true end
    end
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID)
        if ok and known then return true end
    end
    if C_SpellBook and C_SpellBook.HasSpell then
        local ok, known = pcall(C_SpellBook.HasSpell, spellID)
        if ok and known then return true end
    end
    if _G.IsSpellKnown then
        local ok, known = pcall(_G.IsSpellKnown, spellID)
        if ok and known then return true end
    end
    if _G.IsPlayerSpell then
        local ok, known = pcall(_G.IsPlayerSpell, spellID)
        if ok and known then return true end
    end
    return false
end

local function get_known_fishing_id()
    if isClassicEra then
        for id in pairs(FishingIDs) do
            if is_spell_known(id) then
                return id
            end
        end
        return 7620
    end

    -- Retail / Mainline: check known IDs, default safely to 131474
    for id in pairs(FishingIDs) do
        if is_spell_known(id) then
            return id
        end
    end
    return 131474
end
sfui.fishing.get_known_fishing_id = get_known_fishing_id

local function get_fishing_spell_name()
    local id = get_known_fishing_id()
    if id and C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, id)
        if ok and name and name ~= "" then return name end
    end
    if id and _G.GetSpellInfo then
        local ok, name = pcall(_G.GetSpellInfo, id)
        if ok and name and name ~= "" then return name end
    end
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, 131474)
        if ok and name and name ~= "" then return name end
        ok, name = pcall(C_Spell.GetSpellName, 7620)
        if ok and name and name ~= "" then return name end
    end
    if _G.GetSpellInfo then
        local ok, name = pcall(_G.GetSpellInfo, 131474)
        if ok and name and name ~= "" then return name end
        ok, name = pcall(_G.GetSpellInfo, 7620)
        if ok and name and name ~= "" then return name end
    end
    return "Fishing"
end
sfui.fishing.get_fishing_spell_name = get_fishing_spell_name

local function is_flying_safe()
    if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret and C_Secrets.ShouldSpellAuraBeSecret(125883) then
        return IsFlying and IsFlying()
    end
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and C_UnitAuras.GetPlayerAuraBySpellID(125883) then
        return false
    end
    return IsFlying and IsFlying()
end

local function is_fishing_channel()
    if UnitChannelInfo then
        local ok, name, _, _, _, _, _, _, spellID = pcall(UnitChannelInfo, "player")
        if ok and name and (name == get_fishing_spell_name() or (spellID and FishingIDs[spellID])) then
            return true
        end
    end
    if ChannelInfo then
        local ok, spellName = pcall(ChannelInfo)
        if ok and spellName and spellName == get_fishing_spell_name() then
            return true
        end
    end
    return false
end

local function is_lunker_active()
    if UnitChannelInfo then
        local ok, _, _, _, _, _, _, _, spellID = pcall(UnitChannelInfo, "player")
        if ok and spellID == 392270 then return true end
    end
    return false
end

local function allow_fishing()
    if not get_setting("enabled", true) then return false end

    -- Verify player actually knows fishing on Classic Era
    if isClassicEra and not is_spell_known(get_known_fishing_id()) then
        return false
    end

    if (IsPlayerMoving and IsPlayerMoving())
        or (IsMounted and IsMounted() and not get_setting("doubleClickForce", false))
        or is_flying_safe()
        or (IsFalling and IsFalling())
        or (IsStealthed and IsStealthed())
        or (IsSwimming and IsSwimming())
        or (IsSubmerged and IsSubmerged())
        or (UnitHasVehicleUI and UnitHasVehicleUI("player"))
        or (HasFullControl and not HasFullControl())
    then
        return false
    end

    if not get_setting("overrideLunker", false) and is_lunker_active() then
        return false
    end

    if is_fishing_channel() then
        local recast = get_setting("recastOnDoubleClick", false)
        local mod = IsModifierKeyDown and IsModifierKeyDown()
        return (recast and not mod) or (not recast and mod)
    end

    return true
end

-- ─── Deferred Execution for Combat Safety ────────────────────────────────────

local function defer_action(fn)
    if not InCombatLockdown or not InCombatLockdown() then
        pcall(fn)
    else
        table_insert(_state.pendingTasks, fn)
    end
end

local function run_deferred_tasks()
    if InCombatLockdown and InCombatLockdown() then return end
    for _, fn in ipairs(_state.pendingTasks) do
        pcall(fn)
    end
    wipe(_state.pendingTasks)
end

local function update_button_attributes()
    if _state.secureButton and (not InCombatLockdown or not InCombatLockdown()) then
        local useKeyDowns = false
        if GetCVarBool then
            local ok, val = pcall(GetCVarBool, "ActionButtonUseKeyDown")
            if ok then useKeyDowns = val end
        elseif GetCVar then
            local ok, val = pcall(GetCVar, "ActionButtonUseKeyDown")
            if ok then useKeyDowns = (val == "1") end
        end
        _state.secureButton:SetAttribute("useKeyDowns", useKeyDowns)

        local spellID = get_known_fishing_id() or (isClassicEra and 7620 or 131474)
        _state.secureButton:SetAttribute("spell", spellID)
    end
end

local function get_secure_button()
    if not _state.secureButton then
        local button = CreateFrame("Button", SECURE_BUTTON_NAME, nil, "SecureActionButtonTemplate")
        button:RegisterForClicks("AnyDown", "AnyUp")
        button:SetAttribute("type", "spell")
        button:SetAttribute("spell", get_known_fishing_id() or (isClassicEra and 7620 or 131474))
        button:SetScript("PostClick", function(self, mouse_button, down)
            if MouselookStart then MouselookStart() end
            if down then return end
            if MouselookStop then MouselookStop() end
        end)

        if SecureHandlerWrapScript then
            SecureHandlerWrapScript(button, "PostClick", button, [[
                local useKeyDowns = self:GetAttribute("useKeyDowns")
                if useKeyDowns then
                    if down then
                        self:ClearBindings()
                    end
                else
                    if not down then
                        self:ClearBindings()
                    end
                end
            ]])
        end

        _state.secureButton = button
        defer_action(update_button_attributes)
    end
    return _state.secureButton
end
sfui.fishing.get_secure_button = get_secure_button

-- ─── Sound Enhancement ───────────────────────────────────────────────────────

local function enhance_sounds(enable)
    if not get_setting("enhanceSounds", true) then return end

    if not enable then
        if not _state.soundsEnhanced then return end
        _state.soundsEnhanced = false
        _state.isRestoringSounds = true
        _state.cvarsChanged = true

        for _, cvar in ipairs(SoundCVars) do
            local savedVal = _state.soundCache[cvar]
            if savedVal ~= nil then
                safe_set_cvar(cvar, savedVal)
            end
        end

        if C_Timer and C_Timer.After then
            C_Timer.After(0.5, function()
                _state.isRestoringSounds = false
                _state.cvarsChanged = false
            end)
        else
            _state.isRestoringSounds = false
            _state.cvarsChanged = false
        end
    else
        if _state.soundsEnhanced then return end

        -- Step 1: Snapshot baseline sound CVars BEFORE altering any of them
        for _, cvar in ipairs(SoundCVars) do
            local cur = safe_get_cvar(cvar)
            if cur ~= nil then
                _state.soundCache[cvar] = cur
            end
        end

        if SfuiDB then
            SfuiDB.soundBaseline = SfuiDB.soundBaseline or {}
            for k, v in pairs(_state.soundCache) do
                SfuiDB.soundBaseline[k] = v
            end
        end

        _state.soundsEnhanced = true
        _state.cvarsChanged = true

        -- Step 2: Apply fishing sound enhancements (boost SFX, mute distractions)
        safe_set_cvar("Sound_EnableAmbience", 0)
        safe_set_cvar("Sound_MusicVolume", 0)
        safe_set_cvar("Sound_EnablePetSounds", 0)

        safe_set_cvar("Sound_EnableSFX", 1)
        safe_set_cvar("Sound_EnableSoundWhenGameIsInBG", 1)
        safe_set_cvar("Sound_EnableAllSound", 1)

        local scale = get_setting("enhanceSoundsScale", 1.0) or 1.0
        safe_set_cvar("Sound_SFXVolume", scale)
        safe_set_cvar("Sound_MasterVolume", scale)

        if C_Timer and C_Timer.After then
            C_Timer.After(0.5, function()
                _state.cvarsChanged = false
            end)
        end
    end
end

-- ─── Soft-Targeting & Binding Management ─────────────────────────────────────

local function set_fishing_cvars()
    _state.cvarsChanged = true
    enhance_sounds(true)

    if get_setting("softTarget", true) then
        safe_set_cvar("SoftTargetInteract", 3)
        safe_set_cvar("SoftTargetInteractArc", 2)
        safe_set_cvar("SoftTargetInteractRange", 60)
        safe_set_cvar("SoftTargetIconGameObject", 1)
        safe_set_cvar("SoftTargetIconInteract", 1)
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0.2, function()
            _state.cvarsChanged = false
        end)
    end
end

local function reset_fishing_cvars(isLogout)
    if not isLogout then
        _state.cvarsChanged = true
    end
    enhance_sounds(false)

    if get_setting("softTarget", true) then
        for cvar, val in pairs(_state.interactCVarCache) do
            safe_set_cvar(cvar, val)
        end
    end

    if not isLogout and C_Timer and C_Timer.After then
        C_Timer.After(0.2, function()
            _state.cvarsChanged = false
        end)
    end
end

local function clear_fishing_binds()
    reset_fishing_cvars(false)
    if (not InCombatLockdown or not InCombatLockdown()) and _state.secureButton and ClearOverrideBindings then
        ClearOverrideBindings(_state.secureButton)
    end
end

local function get_all_bound_keys()
    local keys = {}
    local seen = {}
    local function add_keys(binding)
        if not GetBindingKey then return end
        local k1, k2 = GetBindingKey(binding)
        if k1 and not seen[k1] then seen[k1] = true; keys[#keys + 1] = k1 end
        if k2 and not seen[k2] then seen[k2] = true; keys[#keys + 1] = k2 end
    end
    add_keys("SFUI_FISHING")
    add_keys("BETTERFISHINGKEY")
    return keys
end
sfui.fishing.get_all_bound_keys = get_all_bound_keys

-- Pre-arms all bound keys with SetOverrideBindingSpell so the very first keypress casts immediately
local function arm_fishing_keys()
    if InCombatLockdown and InCombatLockdown() then return end
    if not get_setting("enabled", true) then return end
    if is_fishing_channel() then return end

    local keys = get_all_bound_keys()
    if #keys == 0 then return end

    local btn = get_secure_button()
    if not btn then return end

    local spellName = get_fishing_spell_name()
    if SetOverrideBindingSpell and spellName then
        for i = 1, #keys do
            SetOverrideBindingSpell(btn, true, keys[i], spellName)
        end
    end
end
sfui.fishing.arm_fishing_keys = arm_fishing_keys

-- Keybind runner: Can be bound to a key or invoked via /sffish or /sfui fish
function sfui.fishing.RunKeybind(fromSlash)
    if (InCombatLockdown and InCombatLockdown()) or is_flying_safe() then return end
    if GetNumLootItems and GetNumLootItems() ~= 0 then return end
    if not get_setting("overrideLunker", false) and is_lunker_active() then return end

    local keys = get_all_bound_keys()
    local btn = get_secure_button()

    if is_fishing_channel() then
        -- Already fishing: ensure keys are bound to INTERACTTARGET so pressing reels in
        if SetOverrideBinding then
            for i = 1, #keys do
                SetOverrideBinding(btn, true, keys[i], "INTERACTTARGET")
            end
        end
        return
    end

    arm_fishing_keys()

    if fromSlash and sfui.common and sfui.common.print then
        if #keys > 0 then
            sfui.common.print("fishing: armed on |cff00ffff" .. table.concat(keys, ", ") .. "|r. Press your key to cast & catch.")
        else
            sfui.common.print("fishing: no key bound. Use double-right-click in world, or bind a key under Keybindings > SFUI.")
        end
    end
end

-- ─── Event Listeners via sfui.events ──────────────────────────────────────────

local function on_mouse_down(event, button)
    if not get_setting("enabled", true) or not get_setting("doubleClick", true) then return end
    if button ~= "RightButton" or (IsMouseButtonDown and IsMouseButtonDown("LeftButton")) or (InCombatLockdown and InCombatLockdown()) then return end

    if (not GetNumLootItems or GetNumLootItems() == 0) then
        local now = GetTime()
        local lastClick = _state.previousClickTime or 0
        local delta = now - lastClick

        -- 0.5s cast debounce
        if (now - (_state.lastCastTime or 0)) < 0.5 then
            return
        end

        local speed = get_setting("doubleClickSpeed", 0.4) or 0.4
        if delta >= DOUBLECLICK_MIN_SECONDS and delta <= speed then
            if allow_fishing() then
                if SetOverrideBindingClick then
                    SetOverrideBindingClick(get_secure_button(), true, "BUTTON2", SECURE_BUTTON_NAME)
                end
                _state.lastCastTime = now
            elseif is_fishing_channel() then
                _state.isInteractBinding = true
                if SetOverrideBinding then
                    SetOverrideBinding(get_secure_button(), true, "BUTTON2", "INTERACTTARGET")
                end
            end
            _state.previousClickTime = 0
            return
        end
    end
    _state.previousClickTime = GetTime()
end

local function on_mouse_up(event, button)
    if _state.isInteractBinding and button == "RightButton" and (not IsMouseButtonDown or not IsMouseButtonDown("LeftButton")) and (not InCombatLockdown or not InCombatLockdown()) then
        _state.isInteractBinding = false
        if _state.secureButton and ClearOverrideBindings then
            ClearOverrideBindings(_state.secureButton)
        end
    end
end

local function on_channel_start(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    if not (spellID and FishingIDs[spellID]) and not is_fishing_channel() then return end
    if InCombatLockdown and InCombatLockdown() then return end

    set_fishing_cvars()

    local btn = get_secure_button()
    if SetOverrideBinding then
        local keys = get_all_bound_keys()
        for i = 1, #keys do
            SetOverrideBinding(btn, true, keys[i], "INTERACTTARGET")
        end
    end
end

local function on_channel_stop(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    if (spellID and FishingIDs[spellID]) or _state.soundsEnhanced or _state.isInteractBinding or is_fishing_channel() then
        defer_action(function()
            clear_fishing_binds()
            arm_fishing_keys()
        end)
    end
end

local function on_enter_combat()
    clear_fishing_binds()
end

local function on_leave_combat()
    run_deferred_tasks()
    arm_fishing_keys()
end

local function on_bindings_updated()
    if InCombatLockdown and InCombatLockdown() then
        defer_action(arm_fishing_keys)
    else
        clear_fishing_binds()
        arm_fishing_keys()
    end
end

local function on_cvar_update(event, cvarName)
    if cvarName == "ActionButtonUseKeyDown" then
        defer_action(update_button_attributes)
        return
    end

    -- Critical protection: never overwrite soundCache while sounds are enhanced or being restored
    if _state.soundsEnhanced or _state.isRestoringSounds or _state.cvarsChanged or is_fishing_channel() then
        return
    end

    for _, soundCVar in ipairs(SoundCVars) do
        if soundCVar == cvarName then
            _state.soundCache[soundCVar] = safe_get_cvar(cvarName)
            if SfuiDB and SfuiDB.soundBaseline then
                SfuiDB.soundBaseline[soundCVar] = _state.soundCache[soundCVar]
            end
            break
        end
    end

    if not _state.cvarsChanged then
        local lower = cvarName:lower()
        if _state.interactCVarCache[lower] ~= nil then
            _state.interactCVarCache[lower] = safe_get_cvar(cvarName)
        end
    end
end

-- Dedicated manual or auto recovery function to restore normal audio CVars
local function restore_sound_defaults()
    _state.soundsEnhanced = false
    _state.isRestoringSounds = true
    _state.cvarsChanged = true

    local master = safe_get_cvar("Sound_MasterVolume")
    local mus = safe_get_cvar("Sound_MusicVolume")

    local defaults = {
        Sound_MasterVolume = (master == "1" or master == 1) and "0.6" or (master or "0.6"),
        Sound_SFXVolume = "1",
        Sound_EnableAmbience = "1",
        Sound_MusicVolume = (mus == "0" or mus == 0) and "0.5" or (mus or "0.5"),
        Sound_EnableAllSound = "1",
        Sound_EnablePetSounds = "1",
        Sound_EnableSoundWhenGameIsInBG = "1",
        Sound_EnableSFX = "1",
    }

    for cvar, val in pairs(defaults) do
        _state.soundCache[cvar] = tostring(val)
        if SfuiDB then
            SfuiDB.soundBaseline = SfuiDB.soundBaseline or {}
            SfuiDB.soundBaseline[cvar] = tostring(val)
        end
        safe_set_cvar(cvar, val)
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function()
            _state.isRestoringSounds = false
            _state.cvarsChanged = false
        end)
    else
        _state.isRestoringSounds = false
        _state.cvarsChanged = false
    end

    if sfui.common and sfui.common.print then
        sfui.common.print("fishing: sound settings restored to normal (ambience on, music 50%, master 60%).")
    end
end
sfui.fishing.RestoreSoundDefaults = restore_sound_defaults

-- ─── Module Lifecycle Registration ──────────────────────────────────────────

local FishingModule = sfui.RegisterModule("fishing", {
    OnInit = function(self)
        local savedBaseline = SfuiDB and SfuiDB.soundBaseline

        for _, cvar in ipairs(SoundCVars) do
            local val = (savedBaseline and savedBaseline[cvar]) or safe_get_cvar(cvar)
            if val ~= nil then
                _state.soundCache[cvar] = tostring(val)
            end
        end

        -- Auto-healing: If Ambience and Music are 0 and Master is 1, they were corrupted by previous fishing sessions
        local amb = _state.soundCache["Sound_EnableAmbience"]
        local mus = _state.soundCache["Sound_MusicVolume"]
        local master = _state.soundCache["Sound_MasterVolume"]
        if (amb == "0" or amb == 0) and (mus == "0" or mus == 0) and (master == "1" or master == 1) then
            _state.soundCache["Sound_EnableAmbience"] = "1"
            _state.soundCache["Sound_MusicVolume"] = "0.5"
            _state.soundCache["Sound_EnablePetSounds"] = "1"
            _state.soundCache["Sound_MasterVolume"] = "0.6"
            _state.soundCache["Sound_SFXVolume"] = "1"
            _state.soundCache["Sound_EnableAllSound"] = "1"
            _state.soundCache["Sound_EnableSFX"] = "1"
            _state.soundCache["Sound_EnableSoundWhenGameIsInBG"] = "1"
            if SfuiDB then
                SfuiDB.soundBaseline = SfuiDB.soundBaseline or {}
                for k, v in pairs(_state.soundCache) do
                    SfuiDB.soundBaseline[k] = v
                end
            end
            -- Apply healed sound settings right now so user doesn't stay muted
            for cvar, val in pairs(_state.soundCache) do
                safe_set_cvar(cvar, val)
            end
        end
    end,

    OnEnable = function(self)
        get_secure_button()

        sfui.events.RegisterEvent("GLOBAL_MOUSE_DOWN", on_mouse_down)
        sfui.events.RegisterEvent("GLOBAL_MOUSE_UP", on_mouse_up)
        sfui.events.RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player", on_channel_start)
        sfui.events.RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player", on_channel_stop)
        sfui.events.RegisterEvent("PLAYER_REGEN_DISABLED", on_enter_combat)
        sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", on_leave_combat)
        sfui.events.RegisterEvent("UPDATE_BINDINGS", on_bindings_updated)
        sfui.events.RegisterEvent("CVAR_UPDATE", on_cvar_update)
        sfui.events.RegisterEvent("PLAYER_LOGOUT", function() reset_fishing_cvars(true) end)

        defer_action(arm_fishing_keys)
    end,

    OnDisable = function(self)
        clear_fishing_binds()
    end,

    OnSettingsChanged = function(self, key, value)
        if key == "enabled" then
            if not value then
                clear_fishing_binds()
            else
                arm_fishing_keys()
            end
        end
    end,

    GetDebugInfo = function(self)
        return {
            enabled = get_setting("enabled", true),
            hasSkill = get_known_fishing_id() ~= nil,
            knownSpellID = get_known_fishing_id(),
            boundKeys = get_all_bound_keys(),
            doubleClick = get_setting("doubleClick", true),
            enhanceSounds = get_setting("enhanceSounds", true),
            softTarget = get_setting("softTarget", true),
            isFishing = is_fishing_channel(),
            soundsEnhanced = _state.soundsEnhanced,
            pendingCount = #_state.pendingTasks,
        }
    end,
})

_G["SFUI_FISHING_RUN"] = sfui.fishing.RunKeybind
