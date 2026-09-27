sfui                                = sfui or {}
sfui.fishing                        = sfui.fishing or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/fishing.lua
--  Integrated One-Key Fishing Automation & Auto-Loot
--  Zero-taint secure action handling, soft-targeting bobber interact, and
--  dynamic acoustic enhancement during casts.
--  Cross-version compatible: Retail, Camelot, Classic Era.
-- ══════════════════════════════════════════════════════════════════════════════

-- Localize frequently-called globals for execution performance
local CreateFrame                   = _G.CreateFrame
local InCombatLockdown              = _G.InCombatLockdown
local SetOverrideBinding            = _G.SetOverrideBinding
local SetOverrideBindingSpell       = _G.SetOverrideBindingSpell
local ClearOverrideBindings         = _G.ClearOverrideBindings
local SetBinding                    = _G.SetBinding
local SaveBindings                  = _G.SaveBindings
local GetCurrentBindingSet          = _G.GetCurrentBindingSet
local C_KeyBindings                 = _G.C_KeyBindings
local GetBindingKey                 = _G.GetBindingKey
local GetTime                       = _G.GetTime
local tostring                      = _G.tostring
local SetCVar                       = _G.SetCVar
local GetCVar                       = _G.GetCVar
local GetNumLootItems               = _G.GetNumLootItems
local LootSlot                      = _G.LootSlot
local IsSpellKnown                  = _G.IsSpellKnown
local IsPlayerSpell                 = _G.IsPlayerSpell
local C_Spell                       = _G.C_Spell
local C_SpellBook                   = _G.C_SpellBook
local ipairs, pairs                 = _G.ipairs, _G.pairs
local wipe                          = _G.wipe or table.wipe or
    function(t)
        for k in pairs(t) do t[k] = nil end
        return t
    end

-- Global keybind identifiers
_G["BINDING_NAME_SFUI_FISHING"]     = "cast & catch fishing"
_G["BINDING_NAME_BETTERFISHINGKEY"] = "cast & catch fishing (better fishing compat)"

local SECURE_BUTTON_NAME            = "SfuiFishingButton"

local FishingIDs                    = {
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

local SoundCVars                    = {
    "Sound_MasterVolume",
    "Sound_SFXVolume",
    "Sound_EnableAmbience",
    "Sound_MusicVolume",
    "Sound_EnableAllSound",
    "Sound_EnablePetSounds",
    "Sound_EnableSoundWhenGameIsInBG",
    "Sound_EnableSFX",
}

local SoftTargetCVars               = {
    "SoftTargetInteract",
    "SoftTargetInteractArc",
    "SoftTargetInteractRange",
    "SoftTargetInteractRangeIsHard",
    "SoftTargetInteractOnlyInRange",
    "SoftTargetIconGameObject",
    "SoftTargetIconInteract",
    "SoftTargetLowPriorityIcons",
    "SoftTargetWithLocked",
    "SoftTargetMatchLocked",
    "SoftTargetNameplateInteract",
    "SoftTargetWorldtextFarDist",
    "GamePadVibrationStrength",
}

-- Module State
local _state                        = {
    secureButton = nil,
    isFishing = false,
    wasFishing = false,
    lastChannelStopTime = 0,
    soundsEnhanced = false,
    soundCache = {},
    interactCVarCache = {},
    pendingTasks = {},
    sessionActive = false,
    lastActionTime = 0,
    sessionTimer = nil,
    previousWeapons = nil,
    poleWasEquipped = false,
}

-- Register module defaults with sfui.db
local defaults                      = {
    enabled = true,
    autoLoot = true,
    enhanceSounds = true,
    enhanceSoundsScale = 1.0,
    softTarget = true,
}
sfui.db.RegisterDefaults("fishing", defaults)

local optionsKeyMap = {
    enabled            = "fishingEnabled",
    autoLoot           = "fishingAutoLoot",
    enhanceSounds      = "fishingEnhanceSounds",
    enhanceSoundsScale = "fishingSoundScale",
    softTarget         = "fishingSoftTarget",
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

local clear_fishing_binds
local arm_fishing_keys

local function set_fishing_cvars()
    enhance_sounds(true)

    if get_setting("softTarget", true) then
        -- Adopt the gamepad targeting suite so keyboard users never lose the bobber interact icon:
        safe_set_cvar("SoftTargetInteract", 3)            -- 3 = Any (enables soft-target interact for both KBM and Gamepad)
        safe_set_cvar("SoftTargetInteractArc", 2)         -- 2 = Widest arc (anywhere in targeting area, no narrow yaw restriction)
        safe_set_cvar("SoftTargetInteractRange", 60)      -- 60 yards (covers max fishing line casts without pulling distant objects)
        safe_set_cvar("SoftTargetInteractRangeIsHard", 0) -- Soft distance cutoff rather than rigid hard cutoff
        safe_set_cvar("SoftTargetInteractOnlyInRange", 0) -- CRITICAL FOR CAMELOT: don't restrict soft interact to melee range!
        safe_set_cvar("SoftTargetIconGameObject", 1)      -- Show interact icon on GameObjects (bobbers)
        safe_set_cvar("SoftTargetIconInteract", 1)        -- Show interact icon
        safe_set_cvar("SoftTargetLowPriorityIcons", 1)    -- CRITICAL: forces icon on low-priority objects (bobbers!)
        safe_set_cvar("SoftTargetWithLocked", 1)          -- CRITICAL: keeps soft-target active even if player has a target
        safe_set_cvar("SoftTargetMatchLocked", 1)         -- Synchronizes soft-target with locked targets
        safe_set_cvar("SoftTargetNameplateInteract", 0)   -- Renders 3D world icon directly over object (not 2D nameplate)
        safe_set_cvar("SoftTargetWorldtextFarDist", 60)   -- Distance cutoff for 3D world icon
        safe_set_cvar("GamePadVibrationStrength", 1)      -- Controller rumble on fish bite if gamepad connected
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

clear_fishing_binds = function()
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
        if k1 and not seen[k1] then
            seen[k1] = true; _boundKeys[#_boundKeys + 1] = k1
        end
        if k2 and not seen[k2] then
            seen[k2] = true; _boundKeys[#_boundKeys + 1] = k2
        end
    end
    add_keys("SFUI_FISHING")
    add_keys("BETTERFISHINGKEY")
end

local function get_all_bound_keys()
    return _boundKeys
end
sfui.fishing.get_all_bound_keys = get_all_bound_keys

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

-- ─── Fishing Pole & Session Management ───────────────────────────────────────

--- Determines if an item is a fishing pole by itemID or itemLink
--- Authoritatively uses Item Class (Weapon = 2, Profession = 19) and Item Subclass (Fishingpole = 20, Fishing = 9).
local function is_fishing_pole_item(itemID, itemLink)
    if not itemID and itemLink then
        itemID = tonumber(itemLink:match("item:(%d+)"))
    end
    if not itemID and not itemLink then return false end

    local function is_pole_class(classID, subclassID)
        if not classID or not subclassID then return false end
        -- Weapon -> Fishingpole (Class 2, Subclass 20)
        if classID == 2 and (subclassID == 20 or (Enum and Enum.ItemWeaponSubclass and subclassID == Enum.ItemWeaponSubclass.Fishingpole)) then
            return true
        end
        -- Profession -> Fishing (Class 19, Subclass 9)
        if classID == 19 and (subclassID == 9 or (Enum and Enum.ItemProfessionSubclass and subclassID == Enum.ItemProfessionSubclass.Fishing)) then
            return true
        end
        return false
    end

    if _G.C_Item and _G.C_Item.GetItemInfoInstant then
        local _, _, _, _, _, cID, scID = _G.C_Item.GetItemInfoInstant(itemID or itemLink)
        if is_pole_class(cID, scID) then return true end
    end

    if _G.GetItemInfoInstant then
        local _, _, _, _, _, cID, scID = _G.GetItemInfoInstant(itemID or itemLink)
        if is_pole_class(cID, scID) then return true end
    end

    if _G.GetItemInfo then
        local _, _, _, _, _, _, subType, _, _, _, _, cID, scID = _G.GetItemInfo(itemLink or itemID)
        if is_pole_class(cID, scID) then return true end
        if subType then
            local sLower = subType:lower()
            if sLower:find("fishing") or sLower:find("angel") or sLower:find("peche") or sLower:find("pesca") then
                return true
            end
        end
    end

    if sfui.common and sfui.common.get_item_instant_info then
        local _, _, _, _, _, cID, scID = sfui.common.get_item_instant_info(itemID or itemLink)
        if is_pole_class(cID, scID) then return true end
    end

    if itemLink then
        local bracketName = itemLink:match("%[(.-)%]")
        if bracketName then
            local bLower = bracketName:lower()
            if bLower:find("fishing") or bLower:find("angel") or bLower:find("peche") or bLower:find("pesca") or bLower:find("angler") then
                return true
            end
        end
    end

    return false
end
sfui.fishing.IsFishingPoleItem = is_fishing_pole_item

local function is_fishing_pole_equipped()
    local itemID = _G.GetInventoryItemID and _G.GetInventoryItemID("player", 16)
    local itemLink = _G.GetInventoryItemLink and _G.GetInventoryItemLink("player", 16)
    return is_fishing_pole_item(itemID, itemLink)
end
sfui.fishing.IsFishingPoleEquipped = is_fishing_pole_equipped

local function find_fishing_pole_in_bags()
    local bestBag, bestSlot, bestLink = nil, nil, nil
    local bestIlvl = -1

    local numBags = _G.NUM_BAG_SLOTS or 4
    for bag = 0, numBags do
        local numSlots = (_G.C_Container and _G.C_Container.GetContainerNumSlots and _G.C_Container.GetContainerNumSlots(bag))
            or (_G.GetContainerNumSlots and _G.GetContainerNumSlots(bag)) or 0
        for slot = 1, numSlots do
            local link = (_G.C_Container and _G.C_Container.GetContainerItemLink and _G.C_Container.GetContainerItemLink(bag, slot))
                or (_G.GetContainerItemLink and _G.GetContainerItemLink(bag, slot))
            if link then
                local itemID = tonumber(link:match("item:(%d+)"))
                if is_fishing_pole_item(itemID, link) then
                    local ilvl = (sfui.common and sfui.common.get_item_level and sfui.common.get_item_level(link)) or 0
                    if ilvl > bestIlvl then
                        bestIlvl = ilvl
                        bestBag = bag
                        bestSlot = slot
                        bestLink = link
                    end
                end
            end
        end
    end

    if bestBag and bestSlot then
        return { bag = bestBag, slot = bestSlot, link = bestLink }
    end
    return nil
end

local SESSION_TIMEOUT = 30

local function is_session_active()
    return _state.sessionActive == true
end
sfui.fishing.IsSessionActive = is_session_active

local function end_session(equipWeapons)
    if not _state.sessionActive and not _state.isFishing and not is_fishing_pole_equipped() then return end

    _state.sessionActive = false
    _state.isFishing = false
    _state.wasFishing = false
    _state.sessionTimer = nil

    clear_fishing_binds()
    arm_fishing_keys()

    if equipWeapons and not (_G.InCombatLockdown and _G.InCombatLockdown()) then
        -- Restore previous weapons if saved
        if _state.previousWeapons and _state.previousWeapons.mainHand then
            local mh = _state.previousWeapons.mainHand
            local oh = _state.previousWeapons.offHand
            _state.previousWeapons = nil
            if mh and mh ~= "" and _G.EquipItemByName then
                _G.EquipItemByName(mh, 16)
                if oh and oh ~= "" then
                    _G.C_Timer.After(0.12, function()
                        if _G.EquipItemByName and not (_G.InCombatLockdown and _G.InCombatLockdown()) then
                            _G.EquipItemByName(oh, 17)
                        end
                    end)
                end
            end
        end

        -- Trigger auto-gear to equip best combat weapons
        if sfui.gear and sfui.gear.Update then
            sfui.gear.Update(true)
        elseif sfui.highest and sfui.highest.EquipHighestILvl then
            local isPvP = (sfui.gear and sfui.gear.isCurrentlyPvP and sfui.gear.isCurrentlyPvP()) or false
            sfui.highest.EquipHighestILvl(isPvP, true)
        end
    end
end
sfui.fishing.EndSession = end_session

local function check_session_timeout()
    if not _state.sessionActive then return end
    if _state.isFishing then
        -- Actively channeling fishing: postpone timeout check so it never cancels an active cast
        _state.sessionTimer = _G.C_Timer.After(SESSION_TIMEOUT, check_session_timeout)
        return
    end
    local now = GetTime()
    local elapsed = now - (_state.lastActionTime or 0)
    if elapsed >= SESSION_TIMEOUT then
        end_session(true)
    else
        local remaining = SESSION_TIMEOUT - elapsed
        _state.sessionTimer = _G.C_Timer.After(remaining > 0.5 and remaining or 0.5, check_session_timeout)
    end
end

local function refresh_session()
    _state.sessionActive = true
    _state.lastActionTime = GetTime()
    if not _state.sessionTimer then
        _state.sessionTimer = _G.C_Timer.After(SESSION_TIMEOUT, check_session_timeout)
    end
end
sfui.fishing.RefreshSession = refresh_session
sfui.fishing.StartSession = refresh_session

local function equip_fishing_pole_from_bags()
    if InCombatLockdown and InCombatLockdown() then return false end
    local pole = find_fishing_pole_in_bags()
    if not pole then return false end

    -- Save previous weapons before swapping
    if _G.GetInventoryItemLink then
        local mh = _G.GetInventoryItemLink("player", 16)
        local oh = _G.GetInventoryItemLink("player", 17)
        if mh and not is_fishing_pole_item(nil, mh) then
            _state.previousWeapons = { mainHand = mh, offHand = oh }
        end
    end

    if _G.C_Container and _G.C_Container.PickupContainerItem and _G.EquipCursorItem then
        if _G.ClearCursor then _G.ClearCursor() end
        _G.C_Container.PickupContainerItem(pole.bag, pole.slot)
        _G.EquipCursorItem(16)
        if _G.ClearCursor then _G.ClearCursor() end
    elseif _G.PickupContainerItem and _G.EquipCursorItem then
        if _G.ClearCursor then _G.ClearCursor() end
        _G.PickupContainerItem(pole.bag, pole.slot)
        _G.EquipCursorItem(16)
        if _G.ClearCursor then _G.ClearCursor() end
    elseif _G.EquipItemByName then
        _G.EquipItemByName(pole.link, 16)
    end

    refresh_session()
    print_message("fishing: equipped " .. (pole.link or "fishing pole") .. ".")
    return true
end
sfui.fishing.EquipFishingPole = equip_fishing_pole_from_bags

-- Pre-arms all bound keys with SetOverrideBindingSpell so the very first keypress casts immediately
arm_fishing_keys = function()
    if InCombatLockdown and InCombatLockdown() then return end
    if not get_setting("enabled", true) then return end
    if isClassicEra and not is_spell_known(get_known_fishing_id()) then return end
    if _state.isFishing then return end

    local btn = get_secure_button()
    if not btn then return end

    local isClassic = sfui.isClassic or (sfui.gear and sfui.gear.isClassicOrVanilla and sfui.gear.isClassicOrVanilla()) or isClassicEra
    -- In Classic/Vanilla, if no fishing pole is equipped, clear overrides so pressing the key triggers RunKeybind to auto-equip!
    if isClassic and not is_fishing_pole_equipped() then
        if ClearOverrideBindings then
            ClearOverrideBindings(btn)
        end
        return
    end

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
            local key = keys[i]
            SetOverrideBindingSpell(btn, true, key, spellName)
            if SetOverrideBinding and not key:find("SHIFT") and not key:find("-") then
                SetOverrideBinding(btn, true, "SHIFT-" .. key, "SFUI_FISHING")
            end
        end
    end
end
sfui.fishing.arm_fishing_keys = arm_fishing_keys

local function unbind_keybinds()
    if InCombatLockdown and InCombatLockdown() then
        print_message("cannot modify bindings in combat.")
        return false
    end

    local bindingContext = C_KeyBindings and C_KeyBindings.GetBindingContextForAction and
        C_KeyBindings.GetBindingContextForAction("SFUI_FISHING") or nil

    if GetBindingKey and SetBinding then
        for _, action in ipairs({ "SFUI_FISHING", "BETTERFISHINGKEY" }) do
            local k1, k2 = GetBindingKey(action)
            if k1 then
                if bindingContext then SetBinding(k1, nil, bindingContext) else SetBinding(k1, nil) end
            end
            if k2 then
                if bindingContext then SetBinding(k2, nil, bindingContext) else SetBinding(k2, nil) end
            end
        end
    end

    local bindingSet = (GetCurrentBindingSet and GetCurrentBindingSet()) or 1
    if SaveBindings then
        SaveBindings(bindingSet)
    end

    update_bound_keys()
    if clear_fishing_binds then
        clear_fishing_binds()
    end
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
    local bindingContext = C_KeyBindings and C_KeyBindings.GetBindingContextForAction and
        C_KeyBindings.GetBindingContextForAction("SFUI_FISHING") or nil

    -- Unbind previous keys for fishing action to avoid duplicate / conflicting binds
    if GetBindingKey and SetBinding then
        for _, action in ipairs({ "SFUI_FISHING", "BETTERFISHINGKEY" }) do
            local k1, k2 = GetBindingKey(action)
            if k1 then
                if bindingContext then SetBinding(k1, nil, bindingContext) else SetBinding(k1, nil) end
            end
            if k2 then
                if bindingContext then SetBinding(k2, nil, bindingContext) else SetBinding(k2, nil) end
            end
        end
    end

    if SetBinding then
        if bindingContext then
            SetBinding(newKey, "SFUI_FISHING", bindingContext)
        else
            SetBinding(newKey, "SFUI_FISHING")
        end
    end

    local bindingSet = (GetCurrentBindingSet and GetCurrentBindingSet()) or 1
    if SaveBindings then
        SaveBindings(bindingSet)
    end

    update_bound_keys()
    if not (InCombatLockdown and InCombatLockdown()) then
        if clear_fishing_binds then
            clear_fishing_binds()
        end
        if arm_fishing_keys then
            arm_fishing_keys()
        end
    end

    print_message("fishing: bound to |cff00ffff" .. newKey .. "|r.")
    return true
end
sfui.fishing.set_keybind = set_keybind

-- Keybind runner: Can be bound to a key or invoked via /sffish or /sfui fish
function sfui.fishing.RunKeybind(fromSlash)
    if InCombatLockdown and InCombatLockdown() then return end

    -- 0. Check for Shift key modifier (Manual Exit: restore combat weapons immediately)
    if _G.IsShiftKeyDown and _G.IsShiftKeyDown() then
        end_session(true)
        print_message("fishing: session ended, restoring combat weapons.")
        return
    end

    -- 1. If loot is open, loot it on pressing the keybind
    if loot_all_items() then
        refresh_session()
        return
    end

    local keys = get_all_bound_keys()
    local btn = get_secure_button()

    -- 2. If actively channeling fishing, ensure keys are bound to INTERACTTARGET to reel in
    if _state.isFishing then
        refresh_session()
        if SetOverrideBinding and btn then
            for i = 1, #keys do
                local key = keys[i]
                SetOverrideBinding(btn, true, key, "INTERACTTARGET")
                if not key:find("SHIFT") and not key:find("-") then
                    SetOverrideBinding(btn, true, "SHIFT-" .. key, "SFUI_FISHING")
                end
            end
        end
        return
    end

    -- 3. In Classic/Vanilla, if no fishing pole is equipped, auto-equip it from bags!
    local isClassic = sfui.isClassic or (sfui.gear and sfui.gear.isClassicOrVanilla and sfui.gear.isClassicOrVanilla()) or isClassicEra
    if isClassic and not is_fishing_pole_equipped() then
        local equipped = equip_fishing_pole_from_bags()
        if equipped then
            refresh_session()
            _G.C_Timer.After(0.2, function()
                if not (InCombatLockdown and InCombatLockdown()) then
                    arm_fishing_keys()
                end
            end)
            return
        else
            print_message("fishing: no fishing pole found in bags.")
            return
        end
    end

    -- 4. Otherwise refresh session and arm fishing keys to cast
    refresh_session()
    arm_fishing_keys()

    if fromSlash then
        if #keys > 0 then
            print_message("fishing: armed on |cff00ffff" ..
                table.concat(keys, ", ") .. "|r. press your key to cast, reel in, and loot.")
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
    refresh_session()
    set_fishing_cvars()

    local btn = get_secure_button()
    if SetOverrideBinding and btn then
        local keys = get_all_bound_keys()
        for i = 1, #keys do
            local key = keys[i]
            SetOverrideBinding(btn, true, key, "INTERACTTARGET")
            if not key:find("SHIFT") and not key:find("-") then
                SetOverrideBinding(btn, true, "SHIFT-" .. key, "SFUI_FISHING")
            end
        end
    end
end

local function finish_channel_stop()
    clear_fishing_binds()
    if get_setting("autoLoot", true) then
        loot_all_items()
    end
    refresh_session()
    arm_fishing_keys()
end

local function on_channel_stop(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    if (spellID and FishingIDs[spellID]) or _state.isFishing or _state.wasFishing or _state.soundsEnhanced then
        _state.isFishing = false
        _state.lastChannelStopTime = GetTime()
        refresh_session()
        defer_action(finish_channel_stop)
    end
end

local function on_loot_ready(event)
    if not get_setting("enabled", true) then return end
    local now = GetTime()
    if _state.wasFishing or _state.isFishing or (now - (_state.lastChannelStopTime or 0)) < 4 then
        refresh_session()
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
    refresh_session()
    defer_action(arm_fishing_keys)
end

local function on_enter_combat()
    _state.isFishing = false
    _state.sessionActive = false
    _state.sessionTimer = nil
    clear_fishing_binds()
end

local function on_leave_combat()
    run_deferred_tasks()
    arm_fishing_keys()
    if not _state.sessionActive and is_fishing_pole_equipped() then
        if sfui.gear and sfui.gear.Update then
            sfui.gear.Update(true)
        elseif sfui.highest and sfui.highest.EquipHighestILvl then
            local isPvP = (sfui.gear and sfui.gear.isCurrentlyPvP and sfui.gear.isCurrentlyPvP()) or false
            sfui.highest.EquipHighestILvl(isPvP, true)
        end
    end
end

local function check_mount_or_taxi()
    if (_G.IsMounted and _G.IsMounted()) or (_G.UnitOnTaxi and _G.UnitOnTaxi("player")) then
        if _state.sessionActive or is_fishing_pole_equipped() then
            end_session(true)
        end
    end
end

local function on_equipment_changed(event, slotID)
    if slotID == 16 or not slotID then
        local isEquipped = is_fishing_pole_equipped()
        if isEquipped and not _state.poleWasEquipped then
            _state.poleWasEquipped = true
            refresh_session()
            defer_action(arm_fishing_keys)
        elseif not isEquipped and _state.poleWasEquipped then
            _state.poleWasEquipped = false
            if _state.sessionActive then
                end_session(false)
            end
        end
    end
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
        sfui.events.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", on_equipment_changed)
        sfui.events.RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED", check_mount_or_taxi)
        sfui.events.RegisterEvent("TAXIMAP_OPENED", check_mount_or_taxi)
        sfui.events.RegisterUnitEvent("UNIT_AURA", "player", check_mount_or_taxi)

        defer_action(arm_fishing_keys)
    end,

    OnDisable = function(self)
        end_session(false)
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
        sessionActive = _state.sessionActive or false,
        poleEquipped = is_fishing_pole_equipped(),
        soundsEnhanced = _state.soundsEnhanced,
        pendingCount = #_state.pendingTasks,
    }
end

sfui.fishing.GetDebugInfo = sfui.fishing_debug_info
