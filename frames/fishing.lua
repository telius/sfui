sfui = sfui or {}
sfui.fishing = sfui.fishing or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/fishing.lua
--  Integrated One-Key Fishing Automation & Auto-Loot
--  Zero-taint secure action handling, soft-targeting bobber interact, and
--  dynamic acoustic enhancement during casts.
--  Cross-version compatible: Retail, Camelot, Classic Era.
-- ══════════════════════════════════════════════════════════════════════════════

-- Localize frequently-called globals for execution performance
local CreateFrame             = _G.CreateFrame
local InCombatLockdown        = _G.InCombatLockdown
local SetOverrideBinding      = _G.SetOverrideBinding
local SetOverrideBindingSpell = _G.SetOverrideBindingSpell
local ClearOverrideBindings   = _G.ClearOverrideBindings
local SetBinding              = _G.SetBinding
local SaveBindings            = _G.SaveBindings
local GetCurrentBindingSet    = _G.GetCurrentBindingSet
local C_KeyBindings           = _G.C_KeyBindings
local GetBindingKey           = _G.GetBindingKey
local GetTime                 = _G.GetTime
local tostring                = _G.tostring
local SetCVar                 = _G.SetCVar
local GetCVar                 = _G.GetCVar
local GetNumLootItems         = _G.GetNumLootItems
local LootSlot                = _G.LootSlot
local IsSpellKnown            = _G.IsSpellKnown
local IsPlayerSpell           = _G.IsPlayerSpell
local C_Spell                 = _G.C_Spell
local C_SpellBook             = _G.C_SpellBook
local ipairs, pairs           = _G.ipairs, _G.pairs
local wipe                    = _G.wipe or table.wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

-- Global keybind identifiers
_G["BINDING_NAME_SFUI_FISHING"] = "cast & catch fishing"
_G["BINDING_NAME_BETTERFISHINGKEY"] = "cast & catch fishing (better fishing compat)"

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
    isFishing = false,
    wasFishing = false,
    lastChannelStopTime = 0,
    soundsEnhanced = false,
    soundCache = {},
    interactCVarCache = {},
    pendingTasks = {},
}

-- Register module defaults with sfui.db
local defaults = {
    enabled = true,
    autoLoot = true,
    enhanceSounds = true,
    enhanceSoundsScale = 1.0,
    softTarget = true,
}
sfui.db.RegisterDefaults("fishing", defaults)

local optionsKeyMap = {
    enabled             = "fishingEnabled",
    autoLoot            = "fishingAutoLoot",
    enhanceSounds       = "fishingEnhanceSounds",
    enhanceSoundsScale  = "fishingSoundScale",
    softTarget          = "fishingSoftTarget",
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
    return GetCVar(cvar)
end

local function safe_set_cvar(cvar, val)
    if SetCVar and GetCVar and GetCVar(cvar) ~= nil then
        SetCVar(cvar, val)
    end
end

-- Cache baseline soft target CVars on load (only if client supports them)
for _, cvar in ipairs(SoftTargetCVars) do
    local val = safe_get_cvar(cvar)
    if val ~= nil then
        _state.interactCVarCache[cvar] = val
    end
end

-- ─── Skill & Spell Detection (Cross-Client) ──────────────────────────────────

local isClassicEra = (_G.WOW_PROJECT_ID ~= nil and _G.WOW_PROJECT_CLASSIC ~= nil and _G.WOW_PROJECT_ID == _G.WOW_PROJECT_CLASSIC)

local cachedFishingID
local cachedSpellName

local function is_spell_known(spellID)
    if not spellID then return false end
    if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook then
        return C_SpellBook.IsSpellKnownOrInSpellBook(spellID) or false
    end
    if IsPlayerSpell then
        return IsPlayerSpell(spellID) or false
    end
    return (IsSpellKnown and IsSpellKnown(spellID)) or false
end

local function get_known_fishing_id()
    if cachedFishingID then return cachedFishingID end
    for id in pairs(FishingIDs) do
        if is_spell_known(id) then
            cachedFishingID = id
            return id
        end
    end
    cachedFishingID = isClassicEra and 7620 or 131474
    return cachedFishingID
end
sfui.fishing.get_known_fishing_id = get_known_fishing_id

local function get_fishing_spell_name()
    if cachedSpellName then return cachedSpellName end
    local id = get_known_fishing_id()
    if id then
        local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id))
            or (_G.GetSpellInfo and _G.GetSpellInfo(id))
        if name and name ~= "" then
            cachedSpellName = name
            return name
        end
    end
    cachedSpellName = "Fishing"
    return cachedSpellName
end
sfui.fishing.get_fishing_spell_name = get_fishing_spell_name


-- ─── Deferred Execution for Combat Safety ────────────────────────────────────

local function print_message(msg)
    if sfui.common and sfui.common.print then
        sfui.common.print(msg)
    end
end

local function defer_action(fn)
    if not InCombatLockdown or not InCombatLockdown() then
        fn()
    else
        _state.pendingTasks[#_state.pendingTasks + 1] = fn
    end
end

local function run_deferred_tasks()
    if InCombatLockdown and InCombatLockdown() then return end
    for _, fn in ipairs(_state.pendingTasks) do
        fn()
    end
    wipe(_state.pendingTasks)
end

local function get_secure_button()
    if not _state.secureButton then
        local button = CreateFrame("Button", SECURE_BUTTON_NAME, nil, "SecureActionButtonTemplate")
        button:RegisterForClicks("AnyDown", "AnyUp")
        button:SetAttribute("type", "spell")
        button:SetAttribute("spell", get_known_fishing_id() or (isClassicEra and 7620 or 131474))
        _state.secureButton = button
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

        for _, cvar in ipairs(SoundCVars) do
            local savedVal = _state.soundCache[cvar]
            if savedVal ~= nil then
                safe_set_cvar(cvar, savedVal)
            end
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
    end
end

-- ─── Soft-Targeting & Binding Management ─────────────────────────────────────

local function set_fishing_cvars()
    enhance_sounds(true)

    if get_setting("softTarget", true) then
        safe_set_cvar("SoftTargetInteract", 3)
        safe_set_cvar("SoftTargetInteractArc", 2)
        safe_set_cvar("SoftTargetInteractRange", 60)
        safe_set_cvar("SoftTargetIconGameObject", 1)
        safe_set_cvar("SoftTargetIconInteract", 1)
    end
end

local function reset_fishing_cvars(isLogout)
    enhance_sounds(false)

    if get_setting("softTarget", true) then
        for cvar, val in pairs(_state.interactCVarCache) do
            safe_set_cvar(cvar, val)
        end
    end
end

local function clear_fishing_binds()
    reset_fishing_cvars(false)
    if (not InCombatLockdown or not InCombatLockdown()) and _state.secureButton and ClearOverrideBindings then
        ClearOverrideBindings(_state.secureButton)
    end
end

local _boundKeys = {}

local function update_bound_keys()
    wipe(_boundKeys)
    local seen = {}
    local function add_keys(binding)
        if not GetBindingKey then return end
        local k1, k2 = GetBindingKey(binding)
        if k1 and not seen[k1] then seen[k1] = true; _boundKeys[#_boundKeys + 1] = k1 end
        if k2 and not seen[k2] then seen[k2] = true; _boundKeys[#_boundKeys + 1] = k2 end
    end
    add_keys("SFUI_FISHING")
    add_keys("BETTERFISHINGKEY")
end

local function get_all_bound_keys()
    return _boundKeys
end
sfui.fishing.get_all_bound_keys = get_all_bound_keys

local function unbind_keybinds()
    if InCombatLockdown and InCombatLockdown() then
        print_message("cannot modify bindings in combat.")
        return false
    end

    local bindingContext = C_KeyBindings and C_KeyBindings.GetBindingContextForAction and C_KeyBindings.GetBindingContextForAction("SFUI_FISHING") or nil

    if GetBindingKey and SetBinding then
        for _, action in ipairs({ "SFUI_FISHING", "BETTERFISHINGKEY" }) do
            local k1, k2 = GetBindingKey(action)
            if k1 then SetBinding(k1, nil, bindingContext) end
            if k2 then SetBinding(k2, nil, bindingContext) end
        end
    end

    local bindingSet = (GetCurrentBindingSet and GetCurrentBindingSet()) or 1
    if SaveBindings then
        SaveBindings(bindingSet)
    end

    update_bound_keys()
    clear_fishing_binds()
    print_message("fishing: keybinds cleared.")
    return true
end
sfui.fishing.unbind_keybinds = unbind_keybinds

local function set_keybind(newKey)
    if InCombatLockdown and InCombatLockdown() then
        print_message("cannot modify bindings in combat.")
        return false
    end
    if not newKey or newKey == "" then return false end

    newKey = tostring(newKey):upper()
    local bindingContext = C_KeyBindings and C_KeyBindings.GetBindingContextForAction and C_KeyBindings.GetBindingContextForAction("SFUI_FISHING") or nil

    -- Unbind previous keys for fishing action to avoid duplicate / conflicting binds
    if GetBindingKey and SetBinding then
        for _, action in ipairs({ "SFUI_FISHING", "BETTERFISHINGKEY" }) do
            local k1, k2 = GetBindingKey(action)
            if k1 then SetBinding(k1, nil, bindingContext) end
            if k2 then SetBinding(k2, nil, bindingContext) end
        end
    end

    if SetBinding then
        SetBinding(newKey, "SFUI_FISHING", bindingContext)
    end

    local bindingSet = (GetCurrentBindingSet and GetCurrentBindingSet()) or 1
    if SaveBindings then
        SaveBindings(bindingSet)
    end

    update_bound_keys()
    if not (InCombatLockdown and InCombatLockdown()) then
        clear_fishing_binds()
        arm_fishing_keys()
    end

    print_message("fishing: bound to |cff00ffff" .. newKey .. "|r.")
    return true
end
sfui.fishing.set_keybind = set_keybind

local function loot_all_items()
    if not get_setting("enabled", true) then return false end
    local num = GetNumLootItems and GetNumLootItems() or 0
    if num > 0 then
        for i = num, 1, -1 do
            if LootSlot then
                LootSlot(i)
            end
        end
        return true
    end
    return false
end
sfui.fishing.loot_all_items = loot_all_items

-- Pre-arms all bound keys with SetOverrideBindingSpell so the very first keypress casts immediately
local function arm_fishing_keys()
    if InCombatLockdown and InCombatLockdown() then return end
    if not get_setting("enabled", true) then return end
    if isClassicEra and not is_spell_known(get_known_fishing_id()) then return end
    if _state.isFishing then return end

    local btn = get_secure_button()
    if not btn then return end

    -- If auto-loot is disabled and loot window is open, let keypress loot first
    if not get_setting("autoLoot", true) then
        local numLoot = GetNumLootItems and GetNumLootItems() or 0
        if numLoot > 0 then
            if ClearOverrideBindings then
                ClearOverrideBindings(btn)
            end
            return
        end
    end

    local keys = get_all_bound_keys()
    if #keys == 0 then return end

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
    if InCombatLockdown and InCombatLockdown() then return end

    -- 1. If loot is open, loot it on pressing the keybind
    if loot_all_items() then
        return
    end

    local keys = get_all_bound_keys()
    local btn = get_secure_button()

    -- 2. If actively channeling fishing, ensure keys are bound to INTERACTTARGET to reel in
    if _state.isFishing then
        if SetOverrideBinding and btn then
            for i = 1, #keys do
                SetOverrideBinding(btn, true, keys[i], "INTERACTTARGET")
            end
        end
        return
    end

    -- 3. Otherwise pre-arm fishing keys to cast
    arm_fishing_keys()

    if fromSlash then
        if #keys > 0 then
            print_message("fishing: armed on |cff00ffff" .. table.concat(keys, ", ") .. "|r. press your key to cast, reel in, and loot.")
        else
            print_message("fishing: no key bound. bind a key under options > keybindings > sfui.")
        end
    end
end

-- ─── Event Listeners via sfui.events ──────────────────────────────────────────

local function on_channel_start(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    if not (spellID and FishingIDs[spellID]) then return end
    if InCombatLockdown and InCombatLockdown() then return end

    _state.isFishing = true
    _state.wasFishing = true
    set_fishing_cvars()

    local btn = get_secure_button()
    if SetOverrideBinding and btn then
        local keys = get_all_bound_keys()
        for i = 1, #keys do
            SetOverrideBinding(btn, true, keys[i], "INTERACTTARGET")
        end
    end
end

local function finish_channel_stop()
    clear_fishing_binds()
    if get_setting("autoLoot", true) then
        loot_all_items()
    end
    arm_fishing_keys()
end

local function on_channel_stop(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    if (spellID and FishingIDs[spellID]) or _state.isFishing or _state.wasFishing or _state.soundsEnhanced then
        _state.isFishing = false
        _state.lastChannelStopTime = GetTime()
        defer_action(finish_channel_stop)
    end
end

local function on_loot_ready(event)
    if not get_setting("enabled", true) then return end
    local now = GetTime()
    if _state.wasFishing or _state.isFishing or (now - (_state.lastChannelStopTime or 0)) < 4 then
        if get_setting("autoLoot", true) then
            loot_all_items()
            arm_fishing_keys()
        else
            local btn = get_secure_button()
            if ClearOverrideBindings and btn and (not InCombatLockdown or not InCombatLockdown()) then
                ClearOverrideBindings(btn)
            end
        end
    end
end

local function on_loot_closed(event)
    _state.wasFishing = false
    defer_action(arm_fishing_keys)
end

local function on_enter_combat()
    _state.isFishing = false
    clear_fishing_binds()
end

local function on_leave_combat()
    run_deferred_tasks()
    arm_fishing_keys()
end

local function on_bindings_updated()
    update_bound_keys()
    if InCombatLockdown and InCombatLockdown() then
        defer_action(arm_fishing_keys)
    else
        clear_fishing_binds()
        arm_fishing_keys()
    end
end

-- Dedicated manual or auto recovery function to restore normal audio CVars
local function restore_sound_defaults()
    _state.soundsEnhanced = false

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

    print_message("fishing: sound settings restored to normal (ambience on, music 50%, master 60%).")
end
sfui.fishing.RestoreSoundDefaults = restore_sound_defaults

-- ─── Module Lifecycle Registration ──────────────────────────────────────────

sfui.RegisterModule("fishing", {
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
            restore_sound_defaults()
        end
    end,

    OnEnable = function(self)
        update_bound_keys()
        get_secure_button()

        sfui.events.RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player", on_channel_start)
        sfui.events.RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player", on_channel_stop)
        sfui.events.RegisterEvent("LOOT_READY", on_loot_ready)
        sfui.events.RegisterEvent("LOOT_OPENED", on_loot_ready)
        sfui.events.RegisterEvent("LOOT_CLOSED", on_loot_closed)
        sfui.events.RegisterEvent("PLAYER_REGEN_DISABLED", on_enter_combat)
        sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", on_leave_combat)
        sfui.events.RegisterEvent("UPDATE_BINDINGS", on_bindings_updated)
        sfui.events.RegisterEvent("PLAYER_LOGOUT", reset_fishing_cvars)

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
        return sfui.fishing_debug_info()
    end,
})

_G["SFUI_FISHING_RUN"] = sfui.fishing.RunKeybind

function sfui.fishing_debug_info()
    return {
        enabled = get_setting("enabled", true),
        hasSkill = get_known_fishing_id() ~= nil,
        knownSpellID = get_known_fishing_id(),
        boundKeys = get_all_bound_keys(),
        autoLoot = get_setting("autoLoot", true),
        enhanceSounds = get_setting("enhanceSounds", true),
        softTarget = get_setting("softTarget", true),
        isFishing = _state.isFishing or false,
        soundsEnhanced = _state.soundsEnhanced,
        pendingCount = #_state.pendingTasks,
    }
end
sfui.fishing.GetDebugInfo = sfui.fishing_debug_info
