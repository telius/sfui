local addonName, addon = ...
sfui = sfui or {}
sfui.pets = sfui.pets or {}

local g      = sfui.config
local common = sfui.common
local cfg    = g.pets or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/pets.lua
--  Zero-Allocation Companion Pet Automation & Rotation Manager
--  Auto-resummons lost companions, supports timed rotation, per-character
--  favorites, and intelligent competitive/combat suppression.
-- ══════════════════════════════════════════════════════════════════════════════

-- Guard against game clients without Pet Journal API (e.g. Classic Era / Vanilla / older Camelot)
if not _G.C_PetJournal or not _G.C_PetJournal.GetNumPets then
    sfui.pets.disabled = true
    return
end

-- Localize frequently-called globals for execution performance
local C_PetJournal_PetIsFavorite         = _G.C_PetJournal.PetIsFavorite
local C_PetJournal_GetPetInfoByIndex     = _G.C_PetJournal.GetPetInfoByIndex
local C_PetJournal_GetNumPets            = _G.C_PetJournal.GetNumPets
local C_PetJournal_SummonPetByGUID       = _G.C_PetJournal.SummonPetByGUID
local C_PetJournal_GetSummonedPetGUID    = _G.C_PetJournal.GetSummonedPetGUID
local C_PetJournal_GetPetInfoByPetID     = _G.C_PetJournal.GetPetInfoByPetID
local C_PetJournal_GetPetSummonInfo      = _G.C_PetJournal.GetPetSummonInfo
local C_PetBattles_IsInBattle            = _G.C_PetBattles and _G.C_PetBattles.IsInBattle
local C_UnitAuras_GetPlayerAuraBySpellID = _G.C_UnitAuras and _G.C_UnitAuras.GetPlayerAuraBySpellID
local C_PlayerInfo_GetGlidingInfo        = _G.C_PlayerInfo and _G.C_PlayerInfo.GetGlidingInfo
local C_Map_GetBestMapForUnit            = _G.C_Map and _G.C_Map.GetBestMapForUnit
local InCombatLockdown                   = _G.InCombatLockdown
local IsFlying                           = _G.IsFlying
local IsFalling                          = _G.IsFalling
local UnitOnTaxi                         = _G.UnitOnTaxi
local UnitHasVehicleUI                   = _G.UnitHasVehicleUI
local IsPossessBarVisible                = _G.IsPossessBarVisible
local HasVehicleActionBar                = _G.HasVehicleActionBar
local UnitIsGhost                        = _G.UnitIsGhost
local UnitIsDead                         = _G.UnitIsDead
local UnitChannelInfo                    = _G.UnitChannelInfo
local IsStealthed                        = _G.IsStealthed
local GetInstanceInfo                    = _G.GetInstanceInfo
local UnitFactionGroup                   = _G.UnitFactionGroup
local GetTime                            = _G.GetTime
local C_Timer                            = _G.C_Timer
local math_random                        = math.random
local table_insert                       = table.insert
local table_remove                       = table.remove
local wipe                               = _G.wipe or table.wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
local pcall, ipairs, pairs, type         = _G.pcall, _G.ipairs, _G.pairs, _G.type

-- ─── Configuration & Defaults ───────────────────────────────────────────────

local defaults = {
    enabled = true,
    autoResummon = true,
    rotationTimer = 720, -- Seconds (12 mins, 0 to disable)
    mode = "favs",       -- "favs", "all", "weighted"
    favProbability = 0.5,
    historySize = 4,
    suppressInInstances = true,
}
sfui.db.RegisterDefaults("pets", defaults)

local optionsKeyMap = {
    enabled             = "petsEnabled",
    autoResummon        = "petsAutoResummon",
    rotationTimer       = "petsRotationTimer",
    mode                = "petsMode",
    favProbability      = "petsFavProbability",
    historySize         = "petsHistorySize",
    suppressInInstances = "petsSuppressInInstances",
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
    [3247] = true, -- Pocopoc (handled zone-conditionally)
}

local NoPetDifficulties = {
    [8]  = true, -- Mythic Keystone
    [16] = true, -- Mythic Raid
    [15] = true, -- Heroic Raid
}

-- ─── Zero-Allocation Memory Pools ────────────────────────────────────────────

local _poolAll = {}
local _poolFavs = {}
local _recentHistory = {}
local _lastSummonTime = 0
local _lastRotationTime = 0
local _isDebouncePending = false

local function get_character_key()
    local name, realm = _G.UnitFullName("player")
    if not name or name == "" then return "default" end
    return name .. "-" .. (realm or _G.GetNormalizedRealmName() or "")
end

local function get_char_db()
    SfuiDB = SfuiDB or {}
    SfuiDB.pets_per_char = SfuiDB.pets_per_char or {}
    local key = get_character_key()
    if not SfuiDB.pets_per_char[key] then
        SfuiDB.pets_per_char[key] = {
            charFavsEnabled = false,
            charFavs = {},
            recentPets = {},
        }
    end
    return SfuiDB.pets_per_char[key]
end

-- ─── Environmental & Safety Heuristics ──────────────────────────────────────

local function is_in_air()
    if IsFlying and IsFlying() then return true end
    if IsFalling and IsFalling() then return true end
    if UnitOnTaxi and UnitOnTaxi("player") then return true end
    if C_PlayerInfo_GetGlidingInfo then
        local _, isGliding = C_PlayerInfo_GetGlidingInfo()
        if isGliding then return true end
    end
    return false
end

local function is_instance_forbidden()
    if not get_setting("suppressInInstances", true) then return false end
    local _, instanceType, difficultyID = GetInstanceInfo()
    if instanceType == "arena" then return true end
    if NoPetDifficulties[difficultyID] then return true end
    return false
end

local function has_special_companion_aura()
    -- Daisy backpack aura
    if C_UnitAuras_GetPlayerAuraBySpellID(311796) then return true end
    -- Shoulder parrots: Feathers, Crackers, Cap'n Crackers
    if C_UnitAuras_GetPlayerAuraBySpellID(302954)
        or C_UnitAuras_GetPlayerAuraBySpellID(232871)
        or C_UnitAuras_GetPlayerAuraBySpellID(286268)
    then
        return true
    end
    -- Event mounts/auras (Brewfest rams, forbidden tomes)
    if C_UnitAuras_GetPlayerAuraBySpellID(43880)
        or C_UnitAuras_GetPlayerAuraBySpellID(43883)
        or C_UnitAuras_GetPlayerAuraBySpellID(312993)
    then
        return true
    end
    return false
end

local function can_summon_pet(isAuto)
    if not get_setting("enabled", true) then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    if is_in_air() then return false end
    if UnitIsGhost and UnitIsGhost("player") then return false end
    if UnitIsDead and UnitIsDead("player") then return false end
    if UnitChannelInfo and UnitChannelInfo("player") then return false end
    if IsStealthed and IsStealthed() then return false end
    if C_UnitAuras_GetPlayerAuraBySpellID(32612) or C_UnitAuras_GetPlayerAuraBySpellID(110960) then return false end -- Mage Invis
    if UnitHasVehicleUI and UnitHasVehicleUI("player") then return false end
    if IsPossessBarVisible and IsPossessBarVisible() then return false end
    if HasVehicleActionBar and HasVehicleActionBar() then return false end
    if C_PetBattles_IsInBattle and C_PetBattles_IsInBattle() then return false end
    if is_instance_forbidden() then return false end
    if has_special_companion_aura() then return false end

    -- Throttle auto-summon triggers by 4 seconds
    if isAuto and (GetTime() - _lastSummonTime < 4.0) then
        return false
    end

    return true
end

-- ─── Pet Pool Building (Zero GC Churn) ───────────────────────────────────────

local function is_species_excluded(speciesID)
    if not speciesID then return true end
    if ExcludedSpecies[speciesID] then
        if speciesID == 3247 then -- Pocopoc
            local mapID = C_Map_GetBestMapForUnit and C_Map_GetBestMapForUnit("player")
            if mapID == 1970 then return true end -- Only excluded in Zereth Mortis
            return false
        end
        return true
    end
    return false
end

local function rebuild_pet_pools()
    wipe(_poolAll)
    wipe(_poolFavs)

    if not C_PetJournal_GetNumPets then return end
    local numPets = C_PetJournal_GetNumPets()
    if not numPets or numPets == 0 then return end

    local charDB = get_char_db()
    local useCharFavs = charDB.charFavsEnabled and charDB.charFavs

    for i = 1, numPets do
        local petID, speciesID, isOwned, _, _, _, isFav = C_PetJournal_GetPetInfoByIndex(i)
        if petID and isOwned and not is_species_excluded(speciesID) then
            local isSummonable = C_PetJournal_GetPetSummonInfo and C_PetJournal_GetPetSummonInfo(petID)
            if isSummonable ~= false then
                table_insert(_poolAll, petID)

                local isFavorite = false
                if useCharFavs then
                    isFavorite = (charDB.charFavs[petID] == true)
                else
                    isFavorite = isFav or (C_PetJournal_PetIsFavorite and C_PetJournal_PetIsFavorite(petID))
                end

                if isFavorite then
                    table_insert(_poolFavs, petID)
                end
            end
        end
    end
end

local function is_in_recent_history(petID)
    for _, id in ipairs(_recentHistory) do
        if id == petID then return true end
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
    rebuild_pet_pools()

    local mode = get_setting("mode", "favs")
    local favProb = get_setting("favProbability", 0.5) or 0.5
    if favProb > 1 then favProb = favProb / 100 end
    local pool = _poolFavs

    if mode == "all" or (#_poolFavs == 0) then
        pool = _poolAll
    elseif mode == "weighted" then
        if math_random() > favProb and #_poolAll > 0 then
            pool = _poolAll
        end
    end

    if #pool == 0 then
        pool = _poolAll
    end
    if #pool == 0 then return nil end

    -- Try to pick a pet not recently summoned
    local candidate = nil
    local attempts = 0
    while attempts < 10 do
        attempts = attempts + 1
        local idx = math_random(1, #pool)
        local picked = pool[idx]
        if not is_in_recent_history(picked) or attempts >= 8 then
            candidate = picked
            break
        end
    end

    return candidate or pool[1]
end

local function summon_pet(petID)
    if not petID or not can_summon_pet(false) then return false end
    if not C_PetJournal_SummonPetByGUID then return false end

    _lastSummonTime = GetTime()
    _lastRotationTime = _lastSummonTime
    record_recent_pet(petID)
    C_PetJournal_SummonPetByGUID(petID)
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

    local current = C_PetJournal_GetSummonedPetGUID and C_PetJournal_GetSummonedPetGUID()
    if not current then
        -- Prefer last summoned pet if still summonable, otherwise pick candidate
        local lastPet = _recentHistory[1]
        local isSummonable = lastPet and C_PetJournal_GetPetSummonInfo and C_PetJournal_GetPetSummonInfo(lastPet)
        if isSummonable then
            summon_pet(lastPet)
        else
            sfui.pets.SummonNext(false)
        end
    end
end

local function request_deferred_restore(delay)
    if _isDebouncePending then return end
    _isDebouncePending = true
    C_Timer.After(delay or 2.0, function()
        _isDebouncePending = false
        sfui.pets.RestoreIfMissing()
    end)
end

-- ─── Periodic Rotation Loop ──────────────────────────────────────────────────

local function on_update_tick(elapsed)
    if not get_setting("enabled", true) then return end
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
        cb.text:SetFontObject(g.font_small or "GameFontNormalSmall")
        cb.text:SetText("Char Favs (SFUI)")
    end

    cb:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        local charDB = get_char_db()
        charDB.charFavsEnabled = checked
        if sfui.common and sfui.common.print then
            sfui.common.print("Character-specific companion favorites " .. (checked and "|cff00ff00enabled|r." or "|cffff0000disabled|r."))
        end
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

local PetsModule = sfui.RegisterModule("pets", {
    OnInit = function(self)
        _lastRotationTime = GetTime()
    end,

    OnEnable = function(self)
        -- Movement & Transition Listeners
        sfui.events.RegisterEvent("PLAYER_STARTED_MOVING", function() request_deferred_restore(1.0) end)
        sfui.events.RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED", function() request_deferred_restore(0.5) end)
        sfui.events.RegisterEvent("PLAYER_MAP_CHANGED", function() request_deferred_restore(3.0) end)
        sfui.events.RegisterEvent("LOADING_SCREEN_DISABLED", function() request_deferred_restore(2.0) end)

        -- Pet Status & Journal Updates
        sfui.events.RegisterEvent("COMPANION_UPDATE", function(event, what)
            if what == "CRITTER" then
                local act = C_PetJournal_GetSummonedPetGUID and C_PetJournal_GetSummonedPetGUID()
                if act then
                    record_recent_pet(act)
                end
            end
        end)

        sfui.events.RegisterEvent("PET_JOURNAL_LIST_UPDATE", function()
            rebuild_pet_pools()
        end)

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

        -- Periodic 1.0s update loop for rotation checking
        sfui.events.RegisterUpdate("sfui.pets", 1.0, on_update_tick)
    end,

    OnDisable = function(self)
        -- No permanent bindings to release
    end,

    OnSettingsChanged = function(self, key, value)
        if key == "mode" or key == "favProbability" then
            rebuild_pet_pools()
        end
    end,

    GetDebugInfo = function(self)
        return sfui.pets_debug_info()
    end,
})

function sfui.pets.AddCurrentPetToCharFavs()
    local current = C_PetJournal_GetSummonedPetGUID and C_PetJournal_GetSummonedPetGUID()
    if not current then
        if sfui.common and sfui.common.print then
            sfui.common.print("sfui: No companion pet currently summoned. Summon a pet first, then type /sfpet add.")
        end
        return
    end
    local charDB = get_char_db()
    charDB.charFavs[current] = true
    charDB.charFavsEnabled = true
    rebuild_pet_pools()
    local name = (C_PetJournal_GetPetInfoByPetID and select(8, C_PetJournal_GetPetInfoByPetID(current))) or "Companion"
    if sfui.common and sfui.common.print then
        sfui.common.print(string.format("sfui: Added |cff00ffff%s|r to character favorites (total: %d).", name, #_poolFavs))
    end
end

function sfui.pets.RemoveCurrentPetFromCharFavs()
    local current = C_PetJournal_GetSummonedPetGUID and C_PetJournal_GetSummonedPetGUID()
    if not current then return end
    local charDB = get_char_db()
    charDB.charFavs[current] = nil
    rebuild_pet_pools()
    local name = (C_PetJournal_GetPetInfoByPetID and select(8, C_PetJournal_GetPetInfoByPetID(current))) or "Companion"
    if sfui.common and sfui.common.print then
        sfui.common.print(string.format("sfui: Removed |cff00ffff%s|r from character favorites.", name))
    end
end

function sfui.pets.ListCharFavs()
    local charDB = get_char_db()
    local count = 0
    if sfui.common and sfui.common.print then
        sfui.common.print("sfui: Character favorites for " .. get_character_key() .. ":")
        for guid in pairs(charDB.charFavs) do
            local name = (C_PetJournal_GetPetInfoByPetID and select(8, C_PetJournal_GetPetInfoByPetID(guid))) or guid
            sfui.common.print(" - |cff00ffff" .. tostring(name) .. "|r")
            count = count + 1
        end
        if count == 0 then
            sfui.common.print(" (No character favorites set. Using account Pet Journal favorites.)")
        end
    end
end

function sfui.pets.RemovePetFromCharFavs(petID)
    if not petID then return end
    local charDB = get_char_db()
    charDB.charFavs[petID] = nil
    rebuild_pet_pools()
    local name = (C_PetJournal_GetPetInfoByPetID and select(8, C_PetJournal_GetPetInfoByPetID(petID))) or "Companion"
    if sfui.common and sfui.common.print then
        sfui.common.print(string.format("sfui: Removed |cff00ffff%s|r from character favorites.", name))
    end
end

function sfui.pets.SummonPetByGUID(petID)
    if not petID then return end
    return summon_pet(petID)
end

function sfui.pets.ClearCharFavs()
    local charDB = get_char_db()
    wipe(charDB.charFavs)
    rebuild_pet_pools()
    if sfui.common and sfui.common.print then
        sfui.common.print("sfui: Cleared all character favorites.")
    end
end

sfui.pets.GetCharDB = get_char_db
sfui.pets.GetCharacterKey = get_character_key
sfui.pets.RebuildPools = rebuild_pet_pools
sfui.pets.update_settings = rebuild_pet_pools

_G["SFUI_PET_SUMMON"] = function() sfui.pets.SummonNext(true) end

function sfui.pets_debug_info()
    return {
        enabled = get_setting("enabled", true),
        mode = get_setting("mode", "favs"),
        rotationTimer = get_setting("rotationTimer", 720),
        poolAllCount = #_poolAll,
        poolFavsCount = #_poolFavs,
        historyCount = #_recentHistory,
        currentPet = C_PetJournal_GetSummonedPetGUID and C_PetJournal_GetSummonedPetGUID(),
    }
end
sfui.pets.GetDebugInfo = sfui.pets_debug_info
