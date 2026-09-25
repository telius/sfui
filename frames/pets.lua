local addonName, addon = ...
sfui = sfui or {}
sfui.pets = sfui.pets or {}

local function print_message(msg)
    if sfui.common and sfui.common.print then
        sfui.common.print(msg)
    end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/pets.lua
--  Zero-Allocation Companion Pet Automation & Rotation Manager
--  Auto-resummons lost companions, supports timed rotation, per-character
--  favorites, and intelligent competitive/combat suppression.
-- ══════════════════════════════════════════════════════════════════════════════

-- Guard against game clients without Pet Journal API (e.g. Classic Era / Vanilla / older Camelot)
local C_PetJournal = _G.C_PetJournal
if not C_PetJournal or not C_PetJournal.GetNumPets then
    sfui.pets.disabled = true
    return
end

local C_UnitAuras             = _G.C_UnitAuras
local C_PlayerInfo            = _G.C_PlayerInfo
local C_PetBattles            = _G.C_PetBattles
local InCombatLockdown        = _G.InCombatLockdown
local IsFlying                = _G.IsFlying
local IsFalling               = _G.IsFalling
local IsMounted               = _G.IsMounted
local UnitOnTaxi              = _G.UnitOnTaxi
local UnitHasVehicleUI        = _G.UnitHasVehicleUI
local IsPossessBarVisible     = _G.IsPossessBarVisible
local HasVehicleActionBar     = _G.HasVehicleActionBar
local UnitIsGhost             = _G.UnitIsGhost
local UnitIsDead              = _G.UnitIsDead
local UnitChannelInfo         = _G.UnitChannelInfo
local UnitCastingInfo         = _G.UnitCastingInfo
local IsStealthed             = _G.IsStealthed
local GetTime                 = _G.GetTime
local C_Timer                 = _G.C_Timer
local math_random             = math.random
local table_insert            = table.insert
local table_remove            = table.remove
local wipe                    = _G.wipe or table.wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
local pairs                   = _G.pairs

-- ─── Configuration & Defaults ───────────────────────────────────────────────

local defaults = {
    enabled = true,
    autoResummon = true,
    rotationTimer = 720, -- Seconds (12 mins, 0 to disable)
    historySize = 4,
}
sfui.db.RegisterDefaults("pets", defaults)

local optionsKeyMap = {
    enabled             = "petsEnabled",
    autoResummon        = "petsAutoResummon",
    rotationTimer       = "petsRotationTimer",
    historySize         = "petsHistorySize",
}

local function get_setting(key, fallback)
    local optKey = optionsKeyMap[key]
    if optKey and SfuiDB and SfuiDB[optKey] ~= nil then
        return SfuiDB[optKey]
    end
    return sfui.db.Get("pets", key, fallback)
end

-- ─── Static Exclusion Lists ──────────────────────────────────────────────────

local ExcludedSpecies = {
    [280]  = true, -- Guild Page (Alliance)
    [281]  = true, -- Guild Page (Horde)
    [282]  = true, -- Guild Herald (Alliance)
    [283]  = true, -- Guild Herald (Horde)
    [1349] = true, -- Rotten Little Helper
    [117]  = true, -- Tiny Snowman
    [119]  = true, -- Father Winter's Helper
    [120]  = true, -- Winter's Little Helper
    [3247] = true, -- Pocopoc
}

local SpecialAuras = { 311796, 302954, 232871, 286268, 43880, 43883, 312993 }

-- ─── Zero-Allocation Memory Pools ────────────────────────────────────────────

local _poolFavs = {}
local _poolDirty = true
local _recentHistory = {}
local _lastSummonTime = 0
local _lastRotationTime = 0
local _isDebouncePending = false

local _charDB = nil
local _charKey = nil

local function get_character_key()
    local name, realm = _G.UnitFullName("player")
    local getRealm = _G.GetNormalizedRealmName or _G.GetRealmName
    local r = realm or (getRealm and getRealm())
    if (not r or r == "") and _G.GetCVar then
        r = _G.GetCVar("realmName")
    end
    if name and name ~= "" and r and r ~= "" then
        _charKey = name .. "-" .. r
        return _charKey
    end
    if _charKey and not _charKey:find("%-$") and not _charKey:find("%-unknown$") then
        return _charKey
    end
    return (name and name ~= "") and (name .. "-unknown") or "default"
end

local function get_char_db()
    local key = get_character_key()
    SfuiDB = SfuiDB or {}
    SfuiDB.pets_per_char = SfuiDB.pets_per_char or {}

    local isValidKey = key and key ~= "default" and not key:find("%-unknown$") and not key:find("%-$")
    if isValidKey then
        -- Clean up/migrate any bogus "Name-" entry if the real "Name-Realm" entry exists
        local prefix = key:match("^(.-)%-")
        if prefix and SfuiDB.pets_per_char[prefix .. "-"] then
            local badEntry = SfuiDB.pets_per_char[prefix .. "-"]
            if not SfuiDB.pets_per_char[key] then
                if badEntry.charFavs and next(badEntry.charFavs) then
                    SfuiDB.pets_per_char[key] = badEntry
                end
            end
            SfuiDB.pets_per_char[prefix .. "-"] = nil
        end

        if not SfuiDB.pets_per_char[key] then
            SfuiDB.pets_per_char[key] = { charFavsEnabled = false, charFavs = {} }
        end
        _charDB = SfuiDB.pets_per_char[key]
        _charDB.charFavs = _charDB.charFavs or {}
        return _charDB
    end

    if _charDB then return _charDB end
    if not SfuiDB.pets_per_char[key] then
        SfuiDB.pets_per_char[key] = { charFavsEnabled = false, charFavs = {} }
    end
    return SfuiDB.pets_per_char[key]
end

-- ─── Environmental & Safety Heuristics ──────────────────────────────────────

local function is_in_air()
    return (IsFlying and IsFlying())
        or (IsFalling and IsFalling())
        or (UnitOnTaxi and UnitOnTaxi("player"))
        or (C_PlayerInfo and C_PlayerInfo.GetGlidingInfo and C_PlayerInfo.GetGlidingInfo())
end

local function has_special_companion_aura()
    if not C_UnitAuras or not C_UnitAuras.GetPlayerAuraBySpellID then return false end
    for i = 1, #SpecialAuras do
        if C_UnitAuras.GetPlayerAuraBySpellID(SpecialAuras[i]) then return true end
    end
    return false
end

local function can_summon_pet(isAuto)
    if not get_setting("enabled", true)
        or (InCombatLockdown and InCombatLockdown())
        or (IsMounted and IsMounted())
        or (UnitIsDead and UnitIsDead("player"))
        or (UnitIsGhost and UnitIsGhost("player"))
        or (UnitChannelInfo and UnitChannelInfo("player"))
        or (UnitCastingInfo and UnitCastingInfo("player"))
        or (IsStealthed and IsStealthed())
        or is_in_air()
        or (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and (C_UnitAuras.GetPlayerAuraBySpellID(32612) or C_UnitAuras.GetPlayerAuraBySpellID(110960)))
        or (UnitHasVehicleUI and UnitHasVehicleUI("player"))
        or (IsPossessBarVisible and IsPossessBarVisible())
        or (HasVehicleActionBar and HasVehicleActionBar())
        or (C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle())
        or has_special_companion_aura()
    then
        return false
    end

    if isAuto and (GetTime() - _lastSummonTime < 4.0) then
        return false
    end

    return true
end

-- ─── Pet Pool Building (Zero GC Churn) ───────────────────────────────────────

local function is_species_excluded(speciesID)
    return (speciesID and ExcludedSpecies[speciesID]) and true or false
end

local function is_pet_usable(petID, speciesID)
    if not petID then return false end
    if is_species_excluded(speciesID) then return false end
    if C_PetJournal and C_PetJournal.GetPetSummonInfo then
        local _, err = C_PetJournal.GetPetSummonInfo(petID)
        if err and Enum and Enum.PetJournalError and err == Enum.PetJournalError.InvalidFaction then
            return false
        end
    end
    return true
end

local function rebuild_pet_pools()
    wipe(_poolFavs)
    _poolDirty = false

    local charDB = get_char_db()
    if charDB.charFavsEnabled and charDB.charFavs and next(charDB.charFavs) then
        for petID in pairs(charDB.charFavs) do
            local speciesID = C_PetJournal.GetPetInfoByPetID and C_PetJournal.GetPetInfoByPetID(petID)
            if is_pet_usable(petID, speciesID) then
                _poolFavs[#_poolFavs + 1] = petID
            end
        end
        return
    end

    local numPets = C_PetJournal.GetNumPets and C_PetJournal.GetNumPets()
    if not numPets or numPets == 0 then return end

    for i = 1, numPets do
        local petID, speciesID, isOwned, _, _, _, isFav = C_PetJournal.GetPetInfoByIndex(i)
        if petID and isOwned and is_pet_usable(petID, speciesID) then
            if isFav or (C_PetJournal.PetIsFavorite and C_PetJournal.PetIsFavorite(petID)) then
                _poolFavs[#_poolFavs + 1] = petID
            end
        end
    end
end

local function is_in_recent_history(petID)
    for i = 1, #_recentHistory do
        if _recentHistory[i] == petID then return true end
    end
    return false
end

local function record_recent_pet(petID)
    if not petID then return end
    table_insert(_recentHistory, 1, petID)
    local maxHistory = get_setting("historySize", 4) or 4
    while #_recentHistory > maxHistory do
        table_remove(_recentHistory)
    end
end

-- ─── Summon Execution ────────────────────────────────────────────────────────

local function select_candidate_pet()
    if _poolDirty or #_poolFavs == 0 then
        rebuild_pet_pools()
    end
    local count = #_poolFavs
    if count == 0 then return nil end
    if count == 1 then return _poolFavs[1] end

    -- Try to pick a pet not recently summoned
    local candidate = nil
    local attempts = 0
    while attempts < 10 do
        attempts = attempts + 1
        local idx = math_random(1, count)
        local picked = _poolFavs[idx]
        if not is_in_recent_history(picked) or attempts >= 8 then
            candidate = picked
            break
        end
    end

    return candidate or _poolFavs[1]
end

local function summon_pet(petID)
    if not petID or not can_summon_pet(false) then return false end
    if not (C_PetJournal and C_PetJournal.SummonPetByGUID) then return false end

    _lastSummonTime = GetTime()
    _lastRotationTime = _lastSummonTime
    record_recent_pet(petID)
    C_PetJournal.SummonPetByGUID(petID)
    return true
end

function sfui.pets.SummonNext(force)
    if not can_summon_pet(not force) then return end
    local pet = select_candidate_pet()
    if pet then
        summon_pet(pet)
    end
end

function sfui.pets.RestoreIfMissing()
    if not get_setting("autoResummon", true) then return end
    if not can_summon_pet(true) then return end

    local current = C_PetJournal and C_PetJournal.GetSummonedPetGUID and C_PetJournal.GetSummonedPetGUID()
    if not current then
        -- Prefer last summoned pet if still summonable, otherwise pick candidate
        local lastPet = _recentHistory[1]
        local isSummonable = lastPet and is_pet_usable(lastPet)
        if isSummonable then
            summon_pet(lastPet)
        else
            sfui.pets.SummonNext(false)
        end
    end
end

local function on_deferred_restore()
    _isDebouncePending = false
    sfui.pets.RestoreIfMissing()
end

local function request_deferred_restore(delay)
    if _isDebouncePending then return end
    _isDebouncePending = true
    C_Timer.After(delay or 2.0, on_deferred_restore)
end

-- ─── Periodic Rotation Loop ──────────────────────────────────────────────────

local function on_update_tick(elapsed)
    if not get_setting("enabled", true) then return end

    -- Keep companion summoned when missing (e.g. standing still in town or after dismiss)
    if get_setting("autoResummon", true) then
        local current = C_PetJournal and C_PetJournal.GetSummonedPetGUID and C_PetJournal.GetSummonedPetGUID()
        if not current then
            if can_summon_pet(true) then
                sfui.pets.RestoreIfMissing()
            end
            return
        end
    end

    if #_poolFavs <= 1 then return end

    local rotSecs = get_setting("rotationTimer", 720) or 720
    if rotSecs <= 0 then return end

    local now = GetTime()
    if (now - _lastRotationTime) >= rotSecs then
        if can_summon_pet(true) then
            sfui.pets.SummonNext(false)
        end
    end
end

-- ─── Collections Journal Integration ─────────────────────────────────────────

local _cfavsCheckbox = nil

local function hook_collections_journal()
    if _cfavsCheckbox or not _G.CollectionsJournal then return end

    local cb = CreateFrame("CheckButton", "SfuiCharFavsCheckbox", _G.CollectionsJournal, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("BOTTOMLEFT", _G.CollectionsJournal, "BOTTOMLEFT", 20, 14)
    if cb.text then
        cb.text:SetFontObject("GameFontNormalSmall")
        cb.text:SetText("char favs (sfui)")
    end

    cb:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        local charDB = get_char_db()
        charDB.charFavsEnabled = checked
        print_message("character-specific companion favorites " .. (checked and "|cff00ff00enabled|r." or "|cffff0000disabled|r."))
        rebuild_pet_pools()
    end)

    local function update_cb_visibility()
        if not _G.CollectionsJournal then return end
        local selected = _G.PanelTemplates_GetSelectedTab(_G.CollectionsJournal)
        if selected == 2 then -- Pet Journal Tab
            local charDB = get_char_db()
            cb:SetChecked(charDB.charFavsEnabled)
            cb:Show()
        else
            cb:Hide()
        end
    end

    if _G.CollectionsJournal_UpdateSelectedTab then
        hooksecurefunc("CollectionsJournal_UpdateSelectedTab", update_cb_visibility)
    end
    update_cb_visibility()

    _cfavsCheckbox = cb
end

-- ─── Module Lifecycle Registration ──────────────────────────────────────────

local function on_mount_changed() request_deferred_restore(0.5) end
local function on_zone_changed() request_deferred_restore(2.0) end
local function on_combat_leave() request_deferred_restore(1.5) end

local function on_companion_update(event, what)
    if what == "CRITTER" then
        local act = C_PetJournal.GetSummonedPetGUID and C_PetJournal.GetSummonedPetGUID()
        if act then
            record_recent_pet(act)
        end
    end
end

local function on_journal_update()
    _poolDirty = true
end

local PetsModule = sfui.RegisterModule("pets", {
    OnInit = function(self)
        _lastRotationTime = GetTime()
        _poolDirty = true
        _charDB = nil
        _charKey = nil
    end,

    OnEnable = function(self)
        _poolDirty = true
        _charDB = nil
        _charKey = nil
        rebuild_pet_pools()

        -- Transition & Life Event Listeners
        sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", function()
            _poolDirty = true
            _charDB = nil
            _charKey = nil
            rebuild_pet_pools()
            request_deferred_restore(2.0)
        end)
        sfui.events.RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED", on_mount_changed)
        sfui.events.RegisterEvent("PLAYER_MAP_CHANGED", on_zone_changed)
        sfui.events.RegisterEvent("LOADING_SCREEN_DISABLED", on_zone_changed)
        sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", on_combat_leave)

        -- Pet Status & Journal Updates
        sfui.events.RegisterEvent("COMPANION_UPDATE", on_companion_update)
        sfui.events.RegisterEvent("PET_JOURNAL_LIST_UPDATE", on_journal_update)

        -- Collections UI Integration
        if _G.CollectionsJournal then
            hook_collections_journal()
        else
            sfui.events.RegisterEvent("ADDON_LOADED", function(event, loadedAddon)
                if loadedAddon == "Blizzard_Collections" then
                    hook_collections_journal()
                end
            end)
        end

        -- Periodic 5.0s update loop for rotation checking and missing pet restoration
        sfui.events.RegisterUpdate("sfui.pets", 5.0, on_update_tick)

        -- Initial restore on startup
        request_deferred_restore(1.0)
    end,

    OnDisable = function(self)
        sfui.events.UnregisterUpdate("sfui.pets")
    end,

    OnSettingsChanged = function(self, key, value)
        if key == "charFavsEnabled" or key == "enabled" or key == "autoResummon" then
            _poolDirty = true
            rebuild_pet_pools()
            if value then
                request_deferred_restore(0.5)
            end
        end
    end,

    GetDebugInfo = function(self)
        return sfui.pets_debug_info()
    end,
})

local function get_pet_name(petID)
    return (petID and C_PetJournal.GetPetInfoByPetID and select(8, C_PetJournal.GetPetInfoByPetID(petID))) or "companion"
end

function sfui.pets.AddCurrentPetToCharFavs()
    local current = C_PetJournal.GetSummonedPetGUID and C_PetJournal.GetSummonedPetGUID()
    if not current then
        print_message("sfui: no companion pet currently summoned. summon a pet first, then type /sfpet add.")
        return
    end
    local charDB = get_char_db()
    charDB.charFavs[current] = true
    charDB.charFavsEnabled = true
    rebuild_pet_pools()
    print_message(string.format("sfui: added |cff00ffff%s|r to character favorites (total: %d).", get_pet_name(current), #_poolFavs))
end

function sfui.pets.RemoveCurrentPetFromCharFavs()
    local current = C_PetJournal.GetSummonedPetGUID and C_PetJournal.GetSummonedPetGUID()
    if not current then return end
    local charDB = get_char_db()
    charDB.charFavs[current] = nil
    rebuild_pet_pools()
    print_message(string.format("sfui: removed |cff00ffff%s|r from character favorites.", get_pet_name(current)))
end

function sfui.pets.ListCharFavs()
    local charDB = get_char_db()
    local count = 0
    print_message("sfui: character favorites for " .. get_character_key() .. ":")
    for guid in pairs(charDB.charFavs) do
        print_message(" - |cff00ffff" .. tostring(get_pet_name(guid)) .. "|r")
        count = count + 1
    end
    if count == 0 then
        print_message(" (no character favorites set. using account pet journal favorites.)")
    end
end

function sfui.pets.RemovePetFromCharFavs(petID)
    if not petID then return end
    local charDB = get_char_db()
    charDB.charFavs[petID] = nil
    rebuild_pet_pools()
    print_message(string.format("sfui: removed |cff00ffff%s|r from character favorites.", get_pet_name(petID)))
end

function sfui.pets.SummonPetByGUID(petID)
    if not petID then return end
    return summon_pet(petID)
end

function sfui.pets.ClearCharFavs()
    local charDB = get_char_db()
    wipe(charDB.charFavs)
    rebuild_pet_pools()
    print_message("sfui: cleared all character favorites.")
end

sfui.pets.GetCharDB = get_char_db
sfui.pets.GetCharacterKey = get_character_key
sfui.pets.RebuildPools = rebuild_pet_pools
sfui.pets.update_settings = rebuild_pet_pools

_G["SFUI_PET_SUMMON"] = function() sfui.pets.SummonNext(true) end

function sfui.pets_debug_info()
    local charDB = get_char_db()
    local charCount = 0
    if charDB.charFavs then
        for _ in pairs(charDB.charFavs) do charCount = charCount + 1 end
    end
    local useCharFavs = charDB.charFavsEnabled and charCount > 0
    return {
        enabled = get_setting("enabled", true),
        rotationTimer = get_setting("rotationTimer", 720),
        poolFavsCount = #_poolFavs,
        historyCount = #_recentHistory,
        charFavsCount = charCount,
        isCharFavs = useCharFavs and true or false,
        currentPet = C_PetJournal and C_PetJournal.GetSummonedPetGUID and C_PetJournal.GetSummonedPetGUID(),
    }
end
sfui.pets.GetDebugInfo = sfui.pets_debug_info
