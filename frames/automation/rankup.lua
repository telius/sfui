local addonName, addon = ...
sfui = sfui or {}
sfui.rankup = {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/automation/rankup.lua
--  Automatic Spell & Pet Spell Rank Upgrade on Action Bars (Camelot / Classic)
--
--  * Scans slots 1-180 (player + stance/bonus/page bars), skipping macros.
--  * Uses C_SpellBook.IsSpellBookItemLowRank when available (Camelot 16001)
--    with a rank-subtext parser fallback for Classic Era (11509).
--  * Tracks highest seen spellID per character GUID and per pet (family:name)
--    in SfuiDB.spellUprankKnown so intentional downranks stay untouched across
--    reloads and sessions.
--  * Defers bar swaps until out of combat and cursor is empty.
-- ══════════════════════════════════════════════════════════════════════════════

if not (sfui.isCamelot or sfui.isClassic) then return end

local _G               = _G
local InCombatLockdown = _G.InCombatLockdown
local ClearCursor      = _G.ClearCursor
local PlaceAction      = _G.PlaceAction
local GetActionInfo    = _G.GetActionInfo
local GetCursorInfo    = _G.GetCursorInfo
local UnitGUID         = _G.UnitGUID
local UnitCreatureFamily = _G.UnitCreatureFamily
local UnitName         = _G.UnitName
local C_Spell          = _G.C_Spell
local C_SpellBook      = _G.C_SpellBook
local C_Timer          = _G.C_Timer
local Enum             = _G.Enum
local tonumber         = _G.tonumber
local string_format    = _G.string.format
local string_lower     = _G.string.lower
local string_match     = _G.string.match
local next, pairs      = _G.next, _G.pairs

local MAX_ACTION_SLOT  = 180
local SCAN_DEBOUNCE    = 0.15

local BANK_PLAYER = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 1
local BANK_PET    = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet) or 2
local SPELL_ITEM_TYPE = (Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell) or 1

local hasModernLowRank = (C_SpellBook
    and C_SpellBook.IsSpellBookItemLowRank
    and C_SpellBook.GetNumSpellBookSkillLines
    and C_SpellBook.GetSpellBookSkillLineInfo
    and C_SpellBook.GetSpellBookItemInfo) and true or false

local pendingPlayer = {} -- oldSpellID -> newSpellID
local pendingPet    = {} -- oldSpellID -> newSpellID
local petSlots      = {} -- petSpellID -> pet spellbook slotIndex
local scanTimer     = nil
local petDirty      = false
local active        = false

local events = _G.CreateFrame("Frame")

local function GetAccentPrefix()
    local cyan = (sfui.config and sfui.config.colors and sfui.config.colors.cyan) or { 0, 1, 1 }
    return string_format("|cff%02x%02x%02x", (cyan[1] or 0) * 255, (cyan[2] or 1) * 255, (cyan[3] or 1) * 255)
end

local function GetSpellNameSafe(spellID)
    if not spellID then return nil end
    if sfui.common and sfui.common.get_spell_name then
        return sfui.common.get_spell_name(spellID)
    end
    return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
end

local function GetSpellSubtextSafe(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellSubtext then
        local sub = C_Spell.GetSpellSubtext(spellID)
        if sub and sub ~= "" then return sub end
    end
    if _G.GetSpellSubtext then
        local sub = _G.GetSpellSubtext(spellID)
        if sub and sub ~= "" then return sub end
    end
    return nil
end

local function ParseRankNumber(subtext)
    if not subtext or subtext == "" then return 0 end
    local r = string_match(subtext, "(%d+)")
    return tonumber(r) or 0
end

local function GetCharStore()
    local guid = UnitGUID and UnitGUID("player")
    if not guid or not _G.SfuiDB then return nil end
    local root = _G.SfuiDB.spellUprankKnown
    if not root then
        root = {}
        _G.SfuiDB.spellUprankKnown = root
    end
    local charStore = root[guid]
    if not charStore then
        charStore = { player = {}, pets = {} }
        root[guid] = charStore
    elseif not charStore.pets then
        charStore.pets = {}
    end
    return charStore
end

local function GetPetKey()
    local family = UnitCreatureFamily and UnitCreatureFamily("pet")
    local name = UnitName and UnitName("pet")
    local unknown = _G.UNKNOWNOBJECT or "Unknown"
    if not family or family == "" or family == unknown then return nil end
    if not name or name == "" or name == unknown then return nil end
    return family .. ":" .. name
end

local function IsPlayerSpellKnown(spellID)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        return C_SpellBook.IsSpellKnown(spellID)
    end
    if _G.IsPlayerSpell then
        return _G.IsPlayerSpell(spellID)
    end
    if _G.IsSpellKnown then
        return _G.IsSpellKnown(spellID)
    end
    return false
end

local function CollectPlayerBook(highestByName, lowRanksByName)
    if hasModernLowRank then
        local numLines = C_SpellBook.GetNumSpellBookSkillLines()
        for tab = 1, numLines do
            local line = C_SpellBook.GetSpellBookSkillLineInfo(tab)
            if line and not line.isGuild and not line.offSpecID then
                local offset = line.itemIndexOffset or 0
                local numItems = line.numSpellBookItems or 0
                for i = 1, numItems do
                    local slot = offset + i
                    local info = C_SpellBook.GetSpellBookItemInfo(slot, BANK_PLAYER)
                    if info and not info.isPassive and not info.isOffSpec
                        and info.itemType == SPELL_ITEM_TYPE and info.spellID and info.name then
                        if C_SpellBook.IsSpellBookItemLowRank(slot, BANK_PLAYER) then
                            local list = lowRanksByName[info.name]
                            if not list then
                                list = {}
                                lowRanksByName[info.name] = list
                            end
                            list[info.spellID] = true
                        else
                            highestByName[info.name] = info.spellID
                        end
                    end
                end
            end
        end
        return
    end

    if _G.GetNumSpellTabs then
        local bestRankByName = {}
        local allByName = {}
        local bookType = _G.BOOKTYPE_SPELL or "spell"
        local numTabs = _G.GetNumSpellTabs()
        for tab = 1, numTabs do
            local _, _, offset, numSpells = _G.GetSpellTabInfo(tab)
            for slot = (offset or 0) + 1, (offset or 0) + (numSpells or 0) do
                local slotType, spellID = _G.GetSpellBookItemInfo(slot, bookType)
                local spellName, subName = _G.GetSpellBookItemName(slot, bookType)
                if slotType == "SPELL" and spellID and spellName then
                    local rank = ParseRankNumber(subName or GetSpellSubtextSafe(spellID))
                    if rank > 0 then
                        local list = allByName[spellName]
                        if not list then
                            list = {}
                            allByName[spellName] = list
                        end
                        list[spellID] = true
                        if not bestRankByName[spellName] or rank > bestRankByName[spellName] then
                            bestRankByName[spellName] = rank
                            highestByName[spellName] = spellID
                        end
                    end
                end
            end
        end
        for name, bestID in pairs(highestByName) do
            local allIDs = allByName[name]
            if allIDs then
                local lowList = {}
                for sid in pairs(allIDs) do
                    if sid ~= bestID then
                        lowList[sid] = true
                    end
                end
                if next(lowList) then
                    lowRanksByName[name] = lowList
                end
            end
        end
    end
end

local function CollectPetBook(highestByName, lowRanksByName)
    for k in pairs(petSlots) do petSlots[k] = nil end

    local numPet = (C_SpellBook and C_SpellBook.HasPetSpells and C_SpellBook.HasPetSpells())
        or (_G.HasPetSpells and _G.HasPetSpells())
    if not numPet or numPet <= 0 then return false end

    if hasModernLowRank then
        for slot = 1, numPet do
            local info = C_SpellBook.GetSpellBookItemInfo(slot, BANK_PET)
            if info and not info.isPassive and info.spellID and info.name then
                petSlots[info.spellID] = slot
                if C_SpellBook.IsSpellBookItemLowRank(slot, BANK_PET) then
                    local list = lowRanksByName[info.name]
                    if not list then
                        list = {}
                        lowRanksByName[info.name] = list
                    end
                    list[info.spellID] = true
                else
                    highestByName[info.name] = info.spellID
                end
            end
        end
        return true
    end

    if _G.GetSpellBookItemInfo and _G.GetSpellBookItemName then
        local bookType = _G.BOOKTYPE_PET or "pet"
        local bestRankByName = {}
        local allByName = {}
        for slot = 1, numPet do
            local slotType, spellID = _G.GetSpellBookItemInfo(slot, bookType)
            local spellName, subName = _G.GetSpellBookItemName(slot, bookType)
            if (slotType == "PETACTION" or slotType == "SPELL") and spellID and spellName then
                petSlots[spellID] = slot
                local rank = ParseRankNumber(subName or GetSpellSubtextSafe(spellID))
                if rank > 0 then
                    local list = allByName[spellName]
                    if not list then
                        list = {}
                        allByName[spellName] = list
                    end
                    list[spellID] = true
                    if not bestRankByName[spellName] or rank > bestRankByName[spellName] then
                        bestRankByName[spellName] = rank
                        highestByName[spellName] = spellID
                    end
                end
            end
        end
        for name, bestID in pairs(highestByName) do
            local allIDs = allByName[name]
            if allIDs then
                local lowList = {}
                for sid in pairs(allIDs) do
                    if sid ~= bestID then
                        lowList[sid] = true
                    end
                end
                if next(lowList) then
                    lowRanksByName[name] = lowList
                end
            end
        end
        return true
    end

    return false
end

local function ReconcileBook(known, highestByName, lowRanksByName, pending, forceAll)
    local isFirstScan = (next(known) == nil)
    for spellName, bestID in pairs(highestByName) do
        local prevID = known[spellName]
        if isFirstScan or forceAll then
            local lows = lowRanksByName[spellName]
            if lows then
                for lowID in pairs(lows) do
                    pending[lowID] = bestID
                end
            end
        elseif prevID and prevID ~= bestID then
            pending[prevID] = bestID
        end
        known[spellName] = bestID
    end
end

local function ScanBooks(forceAll)
    local store = GetCharStore()
    if not store then return end

    local pHighest, pLows = {}, {}
    CollectPlayerBook(pHighest, pLows)
    ReconcileBook(store.player, pHighest, pLows, pendingPlayer, forceAll)

    local petKey = GetPetKey()
    if petKey then
        local petHighest, petLows = {}, {}
        if CollectPetBook(petHighest, petLows) then
            local petStore = store.pets[petKey]
            if not petStore then
                petStore = {}
                store.pets[petKey] = petStore
            end
            ReconcileBook(petStore, petHighest, petLows, pendingPet, forceAll)
            petDirty = false
        end
    else
        for k in pairs(pendingPet) do pendingPet[k] = nil end
    end
end

local function PickupPlayerSpell(spellID)
    if C_Spell and C_Spell.PickupSpell then
        C_Spell.PickupSpell(spellID)
        return
    end
    if _G.PickupSpell then
        _G.PickupSpell(spellID)
    end
end

local function PickupPetSpell(spellID)
    local slot = petSlots[spellID]
    if not slot then return false end
    if C_SpellBook and C_SpellBook.PickupSpellBookItem then
        C_SpellBook.PickupSpellBookItem(slot, BANK_PET)
        return true
    end
    if _G.PickupSpellBookItem then
        _G.PickupSpellBookItem(slot, _G.BOOKTYPE_PET or "pet")
        return true
    end
    return false
end

local function ReportUpgrade(spellName, slot)
    if sfui.common and sfui.common.print then
        local cc = GetAccentPrefix()
        local label = spellName and string_lower(spellName) or "spell"
        sfui.common.print(string_format("upgraded %s%s|r on action slot %d.", cc, label, slot))
    end
end

local function UpgradeBars()
    if not (next(pendingPlayer) or next(pendingPet)) then
        events:UnregisterEvent("PLAYER_REGEN_ENABLED")
        events:UnregisterEvent("CURSOR_CHANGED")
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end

    if GetCursorInfo and GetCursorInfo() then
        events:RegisterEvent("CURSOR_CHANGED")
        return
    end

    events:UnregisterEvent("PLAYER_REGEN_ENABLED")
    events:UnregisterEvent("CURSOR_CHANGED")

    local hasPet = (C_SpellBook and C_SpellBook.HasPetSpells and C_SpellBook.HasPetSpells())
        or (_G.HasPetSpells and _G.HasPetSpells())

    for action = 1, MAX_ACTION_SLOT do
        local actionType, id = GetActionInfo(action)
        if actionType == "spell" and id and id > 0 then
            local newID = pendingPlayer[id]
            if newID and newID ~= id and IsPlayerSpellKnown(newID) then
                ClearCursor()
                PickupPlayerSpell(newID)
                if GetCursorInfo and GetCursorInfo() == "spell" then
                    PlaceAction(action)
                    ClearCursor()
                    ReportUpgrade(GetSpellNameSafe(newID), action)
                else
                    ClearCursor()
                end
            else
                local petNew = pendingPet[id]
                if petNew and petNew ~= id and not IsPlayerSpellKnown(id) and petSlots[petNew] then
                    ClearCursor()
                    if PickupPetSpell(petNew) then
                        PlaceAction(action)
                        ClearCursor()
                        ReportUpgrade(GetSpellNameSafe(petNew), action)
                    else
                        ClearCursor()
                    end
                end
            end
        end
    end

    for k in pairs(pendingPlayer) do pendingPlayer[k] = nil end
    if not hasPet or not petDirty then
        for k in pairs(pendingPet) do pendingPet[k] = nil end
    end
end

function sfui.rankup.ScanAndUpgrade(forceAll)
    if _G.SfuiDB and _G.SfuiDB.autoRankUp == false then return end
    if not _G.SfuiDB then return end
    ScanBooks(forceAll == true)
    UpgradeBars()
end

local function RequestScan(forceAll)
    if _G.SfuiDB and _G.SfuiDB.autoRankUp == false then return end
    if scanTimer then
        scanTimer:Cancel()
        scanTimer = nil
    end
    scanTimer = C_Timer.NewTimer(SCAN_DEBOUNCE, function()
        scanTimer = nil
        sfui.rankup.ScanAndUpgrade(forceAll)
    end)
end

local function SetActive(enable)
    if enable == active then return end
    active = enable
    if enable then
        events:RegisterEvent("SPELLS_CHANGED")
        events:RegisterEvent("UNIT_PET")
        events:RegisterEvent("PET_BAR_UPDATE")
        RequestScan(false)
    else
        events:UnregisterAllEvents()
        if scanTimer then
            scanTimer:Cancel()
            scanTimer = nil
        end
        for k in pairs(pendingPlayer) do pendingPlayer[k] = nil end
        for k in pairs(pendingPet) do pendingPet[k] = nil end
        petDirty = false
    end
end

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_ENTERING_WORLD" then
        SetActive(not (_G.SfuiDB and _G.SfuiDB.autoRankUp == false))
        if active then RequestScan(false) end
        return
    elseif event == "PLAYER_REGEN_ENABLED" or event == "CURSOR_CHANGED" then
        UpgradeBars()
        return
    elseif event == "UNIT_PET" then
        if arg1 == "player" then
            petDirty = true
            RequestScan(false)
        end
        return
    elseif event == "PET_BAR_UPDATE" then
        if petDirty then RequestScan(false) end
        return
    elseif event == "SPELLS_CHANGED" then
        RequestScan(false)
    end
end)
events:RegisterEvent("PLAYER_ENTERING_WORLD")

sfui.rankup.OnInit = function()
    if _G.SfuiDB and _G.SfuiDB.autoRankUp == nil then
        _G.SfuiDB.autoRankUp = true
    end
end

sfui.rankup.OnEnable = function()
    sfui.rankup.OnInit()
    SetActive(not (_G.SfuiDB and _G.SfuiDB.autoRankUp == false))
end

sfui.rankup.OnSettingsChanged = function()
    SetActive(not (_G.SfuiDB and _G.SfuiDB.autoRankUp == false))
end

local _rankDebug = {}
function sfui.rankup_debug_info()
    _rankDebug.enabled = (_G.SfuiDB and _G.SfuiDB.autoRankUp ~= false) or false
    _rankDebug.isScanning = (scanTimer ~= nil)
    _rankDebug.modernAPI = hasModernLowRank
    return _rankDebug
end
sfui.rankup.GetDebugInfo = sfui.rankup_debug_info

sfui.RegisterModule("rankup", sfui.rankup)
