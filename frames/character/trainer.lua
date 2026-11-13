sfui = sfui or {}
sfui.character = sfui.character or {}
sfui.character.trainer = {}

local trainerModule = sfui.character.trainer

-- Guard: Camelot / Forever and Classic Era
if not (sfui.isCamelot or sfui.isEra) then
    return
end

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/character/trainer.lua
--  Class Trainer Spells (CharacterFrame Swap Drawer + Embedded Spellbook Tab)
--
--  Surfaces:
--    1. CharacterFrame: SfuiTrainerPanel companion drawer (swaps with SfuiCharacterInfoPanel)
--    2. Forever Spellbook (PlayerSpellsFrame.SpellBookFrame): native square category tab
--       next to specialization tabs + embedded two-page parchment trainer view
--    3. Classic Era fallback: header toggle button on SpellBookFrame / PlayerTalentFrame
--
--  Data pipeline:
--    - Live C_SpellBook FutureSpell + GetSpellBookItemLevelLearned scan
--    - C_SpellBook.GetCurrentLevelSpells(1..maxLevel) enrichment
--    - Passive class-trainer cost & rank snapshot on TRAINER_SHOW / TRAINER_UPDATE
-- ══════════════════════════════════════════════════════════════════════════════

local _G = _G
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local InCombatLockdown = _G.InCombatLockdown
local hooksecurefunc = _G.hooksecurefunc
local UnitLevel = _G.UnitLevel
local UnitClass = _G.UnitClass
local UnitRace = _G.UnitRace
local UnitFactionGroup = _G.UnitFactionGroup
local GetMoney = _G.GetMoney
local IsShiftKeyDown = _G.IsShiftKeyDown
local C_SpellBook = _G.C_SpellBook
local C_Spell = _G.C_Spell
local C_Trainer = _G.C_Trainer
local C_Timer = _G.C_Timer
local Enum = _G.Enum or {}

local math_max = math.max
local math_min = math.min
local math_ceil = math.ceil
local math_floor = math.floor
local string_format = string.format
local string_lower = string.lower
local string_match = string.match
local string_find = string.find
local table_insert = table.insert
local table_sort = table.sort
local tonumber = _G.tonumber
local tostring = _G.tostring
local ipairs = _G.ipairs
local pairs = _G.pairs
local wipe = _G.wipe or (_G.table and _G.table.wipe)

local common = sfui.common
local issecretvalue = sfui.common.issecretvalue

-- ─────────────────────────────────────────────────────────────────────────────
--  Constants
-- ─────────────────────────────────────────────────────────────────────────────

local PANEL_WIDTH = 290
local PANEL_HEIGHT = 420
local DEBOUNCE_KEY = "sfui_trainer_panel_refresh"
local MONEY_DEBOUNCE_KEY = "sfui_trainer_money_refresh"
local DEBOUNCE_DELAY = 0.2
local TRAINER_SCAN_DEBOUNCE_KEY = "sfui_trainer_npc_scan"
local TRAINER_SCAN_DELAY = 0.15

local BOOK_ICON = "Interface\\Icons\\INV_Misc_Book_09"
local BANK_PLAYER = (Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player ~= nil and Enum.SpellBookSpellBank.Player) or 0
local ITEM_TYPE_SPELL = (Enum.SpellBookItemType and Enum.SpellBookItemType.Spell) or 1
local ITEM_TYPE_FUTURE = (Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell) or 2
local SKILL_LINE_GENERAL = (Enum.SpellBookSkillLineIndex and Enum.SpellBookSkillLineIndex.General) or 1
local TRAINER_TYPE_GENERAL = (Enum.TrainerType and Enum.TrainerType.General ~= nil and Enum.TrainerType.General) or 0

local COLORS = {
    READY = { 0.3, 1.0, 0.3 },
    WHITE = { 1.0, 1.0, 1.0 },
    UPCOMING = { 0.85, 0.85, 0.88 },
    DIM = { 0.65, 0.65, 0.68 },
    RED = { 1.0, 0.4, 0.4 },
    GOLD = { 1.0, 0.82, 0.2 },
    ACCENT_FALLBACK = { 0.4, 0.8, 1.0 },
}
local EMPTY_PALETTE = {}

local FILTER_KEYS = { "ready", "upcoming", "all" }

-- ─────────────────────────────────────────────────────────────────────────────
--  State
-- ─────────────────────────────────────────────────────────────────────────────

local panelFrame = nil
local charToggleBtn = nil
local eraSpellBookBtn = nil
local eraTalentBtn = nil

-- Forever Embedded Spellbook Tab & Page state
local sbTabBtn = nil
local sbPageFrame = nil
local isSpellBookTrainerTabActive = false
local maskedNativeTabID = nil
local maskedNativeTabRef = nil
local spellBookCurrentPage = 1
local spellBookMaxPages = 1

local inCombat = false
local activeHostKind = nil   -- "char" | "spells" | nil (Classic Era spells fallback)
local activeHostFrame = nil
local preferredHost = "char" -- remembers the most recently interacted drawer host

local filterMode = "all"     -- "ready" | "upcoming" | "all"
local activeSpecFilter = nil -- nil = all specs, or lowercase category name
local drawerSearchText = ""
local sbSearchText = ""

local playerSpellsHooked = false
local eraSpellBookHooked = false
local eraTalentHooked = false

-- Forward declarations for cross-surface sync
local UpdateSpellBookTabVisual
local RenderSpellBookTrainerPage
local SetSpellBookTrainerTabActive

-- Reusable data buffers (zero table churn across refreshes)
local scratch = {
    knownSpellIDs = {},
    knownNames = {},
    knownMaxRank = {},
    knownExactKey = {},
    seenSpellIDs = {},
    seenExactKeys = {},
    nameCategoryMap = {},
    hasRank1Trainable = {},
    requestedSpellLoads = {},
    futureTemp = {},
    categorySeen = {},
}

local entryPool = sfui.pool.create_table_pool(300)
local activePoolEntries = {}

local catalogDirty = true
local catalogEntries = {}
local drawerFilteredEntries = {}
local sbFilteredEntries = {}
local categoryList = {}

local function AcquireEntry()
    local e = entryPool:Acquire()
    activePoolEntries[#activePoolEntries + 1] = e
    return e
end

local summary = {
    className = "class",
    classFile = "WARRIOR",
    playerLevel = 1,
    readyCount = 0,
    upcomingCount = 0,
    totalCount = 0,
    readyCost = 0,
    readyMissingCosts = 0,
    upcomingCost = 0,
    nextLevel = nil,
}

local function IsInCombat()
    return inCombat or (InCombatLockdown and InCombatLockdown())
end

local function SafeLower(val, fallback)
    if not val or issecretvalue(val) or type(val) ~= "string" then
        return fallback or ""
    end
    return string_lower(val)
end

local function ParseRank(subtext)
    if not subtext or issecretvalue(subtext) or type(subtext) ~= "string" or subtext == "" then
        return 0
    end
    local r = string_match(subtext, "(%d+)")
    return r and tonumber(r) or 0
end

local function FormatCompactSubtext(subtext, isPassive)
    if subtext and not issecretvalue(subtext) and subtext ~= "" then
        local r = ParseRank(subtext)
        if r > 0 then
            return string_format("r%d", r)
        end
        return string_lower(subtext)
    end
    if isPassive then
        return "passive"
    end
    return nil
end

local function FormatMoney(copper)
    if not copper or copper <= 0 then return nil end
    if common and common.SafeGetCoinTextureString then
        return common.SafeGetCoinTextureString(copper)
    end
    if _G.GetCoinTextureString then
        return _G.GetCoinTextureString(copper)
    end
    local g = math_floor(copper / 10000)
    local s = math_floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then
        return string_format("%dg %ds", g, s)
    elseif s > 0 then
        return string_format("%ds %dc", s, c)
    end
    return string_format("%dc", c)
end

local function GetSpellNameSafe(spellID)
    if not spellID then return nil end
    if common and common.get_spell_name then
        local n = common.get_spell_name(spellID)
        if n and not issecretvalue(n) and n ~= "" then return n end
    end
    if C_Spell and C_Spell.GetSpellName then
        local n = C_Spell.GetSpellName(spellID)
        if n and not issecretvalue(n) and n ~= "" then return n end
    end
    if _G.GetSpellInfo then
        local n = _G.GetSpellInfo(spellID)
        if n and not issecretvalue(n) and n ~= "" then return n end
    end
    return nil
end

local function GetSpellIconSafe(spellID)
    if not spellID then return BOOK_ICON end
    if common and common.get_spell_icon then
        local ic = common.get_spell_icon(spellID)
        if ic and not issecretvalue(ic) then return ic end
    end
    if C_Spell and C_Spell.GetSpellTexture then
        local ic = C_Spell.GetSpellTexture(spellID)
        if ic and not issecretvalue(ic) then return ic end
    end
    return BOOK_ICON
end

local function GetSpellSubtextSafe(spellID, rawSubName)
    if rawSubName and not issecretvalue(rawSubName) and rawSubName ~= "" then
        return rawSubName
    end
    if spellID and C_Spell and C_Spell.GetSpellSubtext then
        local sub = C_Spell.GetSpellSubtext(spellID)
        if sub and not issecretvalue(sub) and sub ~= "" then
            return sub
        end
    end
    if spellID and _G.GetSpellSubtext then
        local sub = _G.GetSpellSubtext(spellID)
        if sub and not issecretvalue(sub) and sub ~= "" then
            return sub
        end
    end
    if spellID and not scratch.requestedSpellLoads[spellID] then
        scratch.requestedSpellLoads[spellID] = true
        if common and common.request_spell_load then
            common.request_spell_load(spellID)
        elseif C_Spell and C_Spell.RequestLoadSpellData then
            C_Spell.RequestLoadSpellData(spellID)
        end
    end
    return ""
end

local function GetMaxPlayerLevel()
    if _G.GetMaxLevelForPlayerExpansion then
        local ml = _G.GetMaxLevelForPlayerExpansion()
        if type(ml) == "number" and ml > 0 then return ml end
    end
    if type(_G.MAX_PLAYER_LEVEL) == "number" and _G.MAX_PLAYER_LEVEL > 0 then
        return _G.MAX_PLAYER_LEVEL
    end
    return 60
end

local function GetProfileCatalogKey()
    local _, classFile = UnitClass("player")
    local _, raceFile = UnitRace("player")
    local faction = (UnitFactionGroup and UnitFactionGroup("player")) or "Neutral"
    return string_format("%s_%s_%s", classFile or "UNKNOWN", raceFile or "UNKNOWN", faction)
end

local function BuildExactKey(lowerName, subName)
    local r = ParseRank(subName)
    if r > 0 then
        return string_format("%s|rank %d", lowerName, r)
    end
    return lowerName .. "|"
end

local function LookupCachedCost(classFile, exactKey, lowerName)
    local db = SfuiDB and SfuiDB.trainerCosts and SfuiDB.trainerCosts[classFile]
    if not db then return nil end
    local cost = db[exactKey]
    if cost and cost > 0 then return cost end
    cost = db[lowerName .. "|"]
    if cost and cost > 0 then return cost end
    return nil
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Class Trainer NPC Passive Scanner (Opportunistic Cost & Catalog Cache)
-- ─────────────────────────────────────────────────────────────────────────────

local function IsClassTrainerOpen()
    if not _G.GetNumTrainerServices then return false end
    if C_Trainer and C_Trainer.GetTrainerType then
        return C_Trainer.GetTrainerType() == TRAINER_TYPE_GENERAL
    end
    if _G.IsTradeskillTrainer and _G.IsTradeskillTrainer() then
        return false
    end
    return true
end

local function ScanOpenClassTrainer()
    if IsInCombat() or not IsClassTrainerOpen() then return end
    local numServices = _G.GetNumTrainerServices() or 0
    if numServices <= 0 then return end

    local _, classFile = UnitClass("player")
    if not classFile then return end

    SfuiDB = SfuiDB or {}
    SfuiDB.trainerCosts = SfuiDB.trainerCosts or {}
    SfuiDB.trainerCosts[classFile] = SfuiDB.trainerCosts[classFile] or {}
    SfuiDB.trainerCatalog = SfuiDB.trainerCatalog or {}

    local profileKey = GetProfileCatalogKey()
    SfuiDB.trainerCatalog[profileKey] = SfuiDB.trainerCatalog[profileKey] or {}

    local costBucket = SfuiDB.trainerCosts[classFile]
    local catBucket = SfuiDB.trainerCatalog[profileKey]
    local stepIndex = _G.GetTrainerServiceStepIndex and _G.GetTrainerServiceStepIndex() or nil

    local changed = false
    for idx = 1, numServices do
        if idx ~= stepIndex then
            local serviceName, serviceType, texture, reqLevel, serviceSubText, category = _G.GetTrainerServiceInfo(idx)
            local moneyCost, isProfession = _G.GetTrainerServiceCost(idx)
            if not isProfession and serviceName and not issecretvalue(serviceName)
                and serviceName ~= "" and serviceName ~= _G.UNKNOWN then
                local lowerName = string_lower(serviceName)
                local exactKey = BuildExactKey(lowerName, serviceSubText)

                if moneyCost and not issecretvalue(moneyCost) and moneyCost > 0 then
                    if costBucket[exactKey] ~= moneyCost then
                        costBucket[exactKey] = moneyCost
                        changed = true
                    end
                end

                local reqOther = nil
                if _G.GetTrainerServiceNumAbilityReq and _G.GetTrainerServiceAbilityReq then
                    local numReq = _G.GetTrainerServiceNumAbilityReq(idx) or 0
                    for r = 1, numReq do
                        local abil = _G.GetTrainerServiceAbilityReq(idx, r)
                        if abil and not issecretvalue(abil) and abil ~= "" then
                            local abilLower = string_lower(abil)
                            local baseAbil = string_match(abilLower, "^(.-)%s*%(") or abilLower
                            if baseAbil ~= lowerName then
                                reqOther = baseAbil
                                break
                            end
                        end
                    end
                end

                if serviceType ~= "used" or not catBucket[exactKey] then
                    local catLower = (category and not issecretvalue(category) and category ~= "") and string_lower(category) or nil
                    local existing = catBucket[exactKey]
                    if not existing then
                        existing = {}
                        catBucket[exactKey] = existing
                    end
                    existing.name = serviceName
                    existing.subName = (serviceSubText and not issecretvalue(serviceSubText)) and serviceSubText or ""
                    existing.icon = (texture and not issecretvalue(texture)) and texture or existing.icon or BOOK_ICON
                    existing.reqLevel = (reqLevel and not issecretvalue(reqLevel) and reqLevel > 0) and reqLevel or existing.reqLevel or 1
                    existing.category = catLower or existing.category
                    existing.reqOther = reqOther
                    changed = true
                end
            end
        end
    end

    if changed and trainerModule.RequestRefresh then
        trainerModule.RequestRefresh()
    elseif (panelFrame and panelFrame:IsShown()) or (sbPageFrame and sbPageFrame:IsShown()) then
        trainerModule.RequestRefresh()
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SpellBook + Catalog Resolution
-- ─────────────────────────────────────────────────────────────────────────────

local function IsSpellEntryAlreadyKnown(lowerName, rank, spellID, exactKey)
    if spellID and scratch.knownSpellIDs[spellID] then
        return true
    end
    if exactKey and scratch.knownExactKey[exactKey] then
        return true
    end
    if rank > 0 then
        local maxKnown = scratch.knownMaxRank[lowerName] or 0
        if maxKnown >= rank then
            return true
        end
    else
        if scratch.knownNames[lowerName] then
            return true
        end
    end
    return false
end

local function RebuildCatalog()
    catalogDirty = false
    for i = 1, #activePoolEntries do
        entryPool:Release(activePoolEntries[i])
    end
    wipe(activePoolEntries)
    local futureTemp = scratch.futureTemp
    local knownSpellIDs = scratch.knownSpellIDs
    local knownNames = scratch.knownNames
    local knownMaxRank = scratch.knownMaxRank
    local knownExactKey = scratch.knownExactKey
    local seenSpellIDs = scratch.seenSpellIDs
    local seenExactKeys = scratch.seenExactKeys
    local nameCategoryMap = scratch.nameCategoryMap
    local hasRank1Trainable = scratch.hasRank1Trainable
    local categorySeen = scratch.categorySeen
    wipe(futureTemp)
    wipe(knownSpellIDs)
    wipe(knownNames)
    wipe(knownMaxRank)
    wipe(knownExactKey)
    wipe(seenSpellIDs)
    wipe(seenExactKeys)
    wipe(nameCategoryMap)
    wipe(hasRank1Trainable)
    wipe(catalogEntries)
    wipe(categoryList)
    wipe(categorySeen)

    local classLocalized, classFile = UnitClass("player")
    local pLevel = UnitLevel("player") or 1
    if issecretvalue(pLevel) or type(pLevel) ~= "number" then pLevel = 1 end

    summary.className = SafeLower(classLocalized, SafeLower(classFile, "class"))
    summary.classFile = classFile or "WARRIOR"
    summary.playerLevel = pLevel
    summary.readyCount = 0
    summary.upcomingCount = 0
    summary.totalCount = 0
    summary.readyCost = 0
    summary.readyMissingCosts = 0
    summary.upcomingCost = 0
    summary.nextLevel = nil

    -- Pass 1: Scan C_SpellBook skill lines (both known spells and FutureSpell entries)
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo then
        local numLines = C_SpellBook.GetNumSpellBookSkillLines() or 0
        for lineIdx = 1, numLines do
            local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(lineIdx)
            if lineInfo and not lineInfo.shouldHide and not lineInfo.offSpecID then
                local lineCategory = SafeLower(lineInfo.name, "general")
                local offset = lineInfo.itemIndexOffset or 0
                local count = lineInfo.numSpellBookItems or 0
                for i = 1, count do
                    local slot = offset + i
                    local itemInfo = C_SpellBook.GetSpellBookItemInfo(slot, BANK_PLAYER)
                    if itemInfo and not itemInfo.isOffSpec then
                        local spellID = itemInfo.spellID or itemInfo.actionID
                        local spellName = itemInfo.name or GetSpellNameSafe(spellID)
                        if spellName and not issecretvalue(spellName) and spellName ~= "" then
                            local lowerName = string_lower(spellName)
                            local subName = GetSpellSubtextSafe(spellID, itemInfo.subName)
                            local rank = ParseRank(subName)
                            local exactKey = BuildExactKey(lowerName, subName)

                            if lineIdx ~= SKILL_LINE_GENERAL and lineCategory ~= "" then
                                nameCategoryMap[lowerName] = lineCategory
                            end

                            if itemInfo.itemType == ITEM_TYPE_SPELL then
                                if spellID then knownSpellIDs[spellID] = true end
                                knownNames[lowerName] = true
                                knownExactKey[exactKey] = true
                                if rank > (knownMaxRank[lowerName] or 0) then
                                    knownMaxRank[lowerName] = rank
                                end
                            elseif itemInfo.itemType == ITEM_TYPE_FUTURE then
                                local lvl = (C_SpellBook.GetSpellBookItemLevelLearned and C_SpellBook.GetSpellBookItemLevelLearned(slot, BANK_PLAYER)) or 0
                                if issecretvalue(lvl) or type(lvl) ~= "number" then lvl = 0 end
                                if lineIdx ~= SKILL_LINE_GENERAL or lvl > 0 then
                                    local isPassive = (C_SpellBook.IsSpellBookItemPassive and C_SpellBook.IsSpellBookItemPassive(slot, BANK_PLAYER))
                                        or itemInfo.isPassive or false
                                    local entry = AcquireEntry()
                                    entry.spellID = spellID
                                    entry.slotIndex = slot
                                    entry.spellBank = BANK_PLAYER
                                    entry.name = spellName
                                    entry.lowerName = lowerName
                                    entry.subName = subName
                                    entry.rank = rank
                                    entry.exactKey = exactKey
                                    entry.icon = itemInfo.iconID or GetSpellIconSafe(spellID)
                                    entry.isPassive = isPassive and true or false
                                    entry.levelLearned = lvl > 0 and lvl or pLevel
                                    entry.category = lineCategory
                                    entry.cost = nil
                                    table_insert(futureTemp, entry)
                                    if rank <= 1 then
                                        hasRank1Trainable[lowerName] = true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Fallback Pass 1b: Classic Era GetNumSpellTabs known spells scan
    if not next(knownNames) and _G.GetNumSpellTabs and _G.GetSpellTabInfo then
        local bookType = _G.BOOKTYPE_SPELL or "spell"
        local numTabs = _G.GetNumSpellTabs() or 0
        for tab = 1, numTabs do
            local tabName, _, offset, numSpells, _, offSpecID = _G.GetSpellTabInfo(tab)
            if not offSpecID or offSpecID == 0 then
                local tabCat = SafeLower(tabName, "general")
                for s = (offset or 0) + 1, (offset or 0) + (numSpells or 0) do
                    local spellName, subName = _G.GetSpellBookItemName(s, bookType)
                    local slotType, spellID = _G.GetSpellBookItemInfo(s, bookType)
                    if spellName and not issecretvalue(spellName) and slotType ~= "FUTURESPELL" then
                        local lowerName = string_lower(spellName)
                        local rank = ParseRank(subName)
                        local exactKey = BuildExactKey(lowerName, subName)
                        if spellID then knownSpellIDs[spellID] = true end
                        knownNames[lowerName] = true
                        knownExactKey[exactKey] = true
                        if rank > (knownMaxRank[lowerName] or 0) then
                            knownMaxRank[lowerName] = rank
                        end
                        if tab > 1 and tabCat ~= "" then
                            nameCategoryMap[lowerName] = tabCat
                        end
                    elseif spellName and not issecretvalue(spellName) and slotType == "FUTURESPELL" then
                        local lowerName = string_lower(spellName)
                        local rank = ParseRank(subName)
                        local exactKey = BuildExactKey(lowerName, subName)
                        local lvl = (_G.GetSpellAvailableLevel and _G.GetSpellAvailableLevel(s, bookType)) or pLevel
                        local entry = AcquireEntry()
                        entry.spellID = spellID
                        entry.slotIndex = s
                        entry.spellBank = bookType
                        entry.name = spellName
                        entry.lowerName = lowerName
                        entry.subName = subName or ""
                        entry.rank = rank
                        entry.exactKey = exactKey
                        entry.icon = (_G.GetSpellBookItemTexture and _G.GetSpellBookItemTexture(s, bookType)) or GetSpellIconSafe(spellID)
                        entry.isPassive = (_G.IsPassiveSpell and _G.IsPassiveSpell(s, bookType)) and true or false
                        entry.levelLearned = (type(lvl) == "number" and lvl > 0) and lvl or pLevel
                        entry.category = tabCat
                        entry.cost = nil
                        table_insert(futureTemp, entry)
                        if rank <= 1 then
                            hasRank1Trainable[lowerName] = true
                        end
                    end
                end
            end
        end
    end

    -- Add deduplicated FutureSpell entries
    for i = 1, #futureTemp do
        local e = futureTemp[i]
        if not IsSpellEntryAlreadyKnown(e.lowerName, e.rank, e.spellID, e.exactKey)
            and not seenExactKeys[e.exactKey]
            and (not e.spellID or not seenSpellIDs[e.spellID]) then
            if e.spellID then seenSpellIDs[e.spellID] = true end
            seenExactKeys[e.exactKey] = true
            e.cost = LookupCachedCost(summary.classFile, e.exactKey, e.lowerName)
            table_insert(catalogEntries, e)
        end
    end

    -- Pass 2: C_SpellBook.GetCurrentLevelSpells(1..maxLevel) enrichment
    if C_SpellBook and C_SpellBook.GetCurrentLevelSpells then
        local maxLvl = GetMaxPlayerLevel()
        for lvl = 1, maxLvl do
            local levelSpellIDs = C_SpellBook.GetCurrentLevelSpells(lvl)
            if type(levelSpellIDs) == "table" then
                for j = 1, #levelSpellIDs do
                    local spellID = levelSpellIDs[j]
                    if spellID and not issecretvalue(spellID) and not seenSpellIDs[spellID] and not knownSpellIDs[spellID] then
                        local isKnown = C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(spellID, BANK_PLAYER)
                        if not isKnown then
                            local spellName = GetSpellNameSafe(spellID)
                            if spellName and not issecretvalue(spellName) and spellName ~= "" then
                                local lowerName = string_lower(spellName)
                                local subName = GetSpellSubtextSafe(spellID, nil)
                                local rank = ParseRank(subName)
                                local exactKey = BuildExactKey(lowerName, subName)
                                if not seenExactKeys[exactKey] and not IsSpellEntryAlreadyKnown(lowerName, rank, spellID, exactKey) then
                                    seenSpellIDs[spellID] = true
                                    seenExactKeys[exactKey] = true
                                    if rank <= 1 then
                                        hasRank1Trainable[lowerName] = true
                                    end
                                    local isPassive = (C_Spell and C_Spell.IsSpellPassive and C_Spell.IsSpellPassive(spellID)) or false
                                    local entry = AcquireEntry()
                                    entry.spellID = spellID
                                    entry.slotIndex = nil
                                    entry.spellBank = nil
                                    entry.name = spellName
                                    entry.lowerName = lowerName
                                    entry.subName = subName
                                    entry.rank = rank
                                    entry.exactKey = exactKey
                                    entry.icon = GetSpellIconSafe(spellID)
                                    entry.isPassive = isPassive and true or false
                                    entry.levelLearned = lvl
                                    entry.category = nameCategoryMap[lowerName] or summary.className
                                    entry.cost = LookupCachedCost(summary.classFile, exactKey, lowerName)
                                    table_insert(catalogEntries, entry)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Pass 3: Merge cached trainer catalog services (multi-rank roadmap + Classic Era support)
    local profileKey = GetProfileCatalogKey()
    local cachedCatalog = SfuiDB and SfuiDB.trainerCatalog and SfuiDB.trainerCatalog[profileKey]
    if cachedCatalog then
        for _, info in pairs(cachedCatalog) do
            if type(info) == "table" and info.name then
                local lowerName = string_lower(info.name)
                local rank = ParseRank(info.subName)
                if rank <= 1 then
                    hasRank1Trainable[lowerName] = true
                end
            end
        end

        for exactKey, info in pairs(cachedCatalog) do
            if type(info) == "table" and info.name and not seenExactKeys[exactKey] then
                local lowerName = string_lower(info.name)
                local rank = ParseRank(info.subName)
                if not IsSpellEntryAlreadyKnown(lowerName, rank, nil, exactKey) then
                    -- Guard talent/tome-gated rank 2+ spells (e.g. pyroblast, mortal strike, ice barrier)
                    local prereqMet = true
                    if rank > 1 and not knownNames[lowerName] and not hasRank1Trainable[lowerName] then
                        prereqMet = false
                    end
                    if prereqMet and info.reqOther and not knownNames[info.reqOther] then
                        prereqMet = false
                    end

                    if prereqMet then
                        seenExactKeys[exactKey] = true
                        local cat = info.category or nameCategoryMap[lowerName] or summary.className
                        local entry = AcquireEntry()
                        entry.spellID = nil
                        entry.slotIndex = nil
                        entry.spellBank = nil
                        entry.name = info.name
                        entry.lowerName = lowerName
                        entry.subName = info.subName or ""
                        entry.rank = rank
                        entry.exactKey = exactKey
                        entry.icon = info.icon or BOOK_ICON
                        entry.isPassive = SafeLower(info.subName, "") == "passive"
                        entry.levelLearned = info.reqLevel or 1
                        entry.category = cat
                        entry.cost = LookupCachedCost(summary.classFile, exactKey, lowerName)
                        table_insert(catalogEntries, entry)
                    end
                end
            end
        end
    end

    -- Classify, aggregate summary & collect distinct categories
    for i = 1, #catalogEntries do
        local e = catalogEntries[i]
        e.isReady = (e.levelLearned <= pLevel)
        e.compactSub = FormatCompactSubtext(e.subName, e.isPassive)

        if e.category and e.category ~= "" and not categorySeen[e.category] then
            categorySeen[e.category] = true
            table_insert(categoryList, e.category)
        end

        summary.totalCount = summary.totalCount + 1
        if e.isReady then
            summary.readyCount = summary.readyCount + 1
            if e.cost and e.cost > 0 then
                summary.readyCost = summary.readyCost + e.cost
            else
                summary.readyMissingCosts = summary.readyMissingCosts + 1
            end
        else
            summary.upcomingCount = summary.upcomingCount + 1
            if e.cost and e.cost > 0 then
                summary.upcomingCost = summary.upcomingCost + e.cost
            end
            if not summary.nextLevel or e.levelLearned < summary.nextLevel then
                summary.nextLevel = e.levelLearned
            end
        end
    end

    table_sort(categoryList)
    if activeSpecFilter and not categorySeen[activeSpecFilter] then
        activeSpecFilter = nil
    end

    table_sort(catalogEntries, function(a, b)
        if a.isReady ~= b.isReady then
            return a.isReady
        end
        if a.levelLearned ~= b.levelLearned then
            return a.levelLearned < b.levelLearned
        end
        if a.category ~= b.category then
            return (a.category or "") < (b.category or "")
        end
        if a.lowerName ~= b.lowerName then
            return a.lowerName < b.lowerName
        end
        return (a.rank or 0) < (b.rank or 0)
    end)
end

local function RebuildFilteredEntries(queryStr, outList)
    wipe(outList)
    local query = (queryStr and queryStr ~= "") and string_lower(queryStr) or nil

    for i = 1, #catalogEntries do
        local e = catalogEntries[i]
        local modeMatch = (filterMode == "all")
            or (filterMode == "ready" and e.isReady)
            or (filterMode == "upcoming" and not e.isReady)

        if modeMatch and (not activeSpecFilter or e.category == activeSpecFilter) then
            local searchMatch = true
            if query then
                local inName = string_find(e.lowerName, query, 1, true) ~= nil
                local inCat = e.category and string_find(e.category, query, 1, true) ~= nil
                local inSub = e.compactSub and string_find(e.compactSub, query, 1, true) ~= nil
                local inLvl = string_find(tostring(e.levelLearned), query, 1, true) ~= nil
                searchMatch = inName or inCat or inSub or inLvl
            end
            if searchMatch then
                table_insert(outList, e)
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Host Resolution & Docking Geometry
-- ─────────────────────────────────────────────────────────────────────────────

local function GetVisibleClassicEraHost()
    if _G.PlayerSpellsFrame then
        return nil
    end
    if _G.SpellBookFrame and _G.SpellBookFrame:IsShown() then
        return _G.SpellBookFrame
    end
    if _G.PlayerTalentFrame and _G.PlayerTalentFrame:IsShown() then
        return _G.PlayerTalentFrame
    end
    return nil
end

local function IsForeverSpellBookVisible()
    local psf = _G.PlayerSpellsFrame
    if not psf or not psf:IsShown() then return false end
    if psf.IsInspecting and psf:IsInspecting() then return false end
    local sbf = psf.SpellBookFrame
    return (sbf and sbf:IsShown()) and true or false
end

local function ResolveDesiredHost()
    local charFrame = _G.CharacterFrame
    local charOpen = charFrame and charFrame:IsShown()
    local eraHost = GetVisibleClassicEraHost()

    local charWants = charOpen and (SfuiDB and SfuiDB.showTrainerInfoPanel) and true or false
    local spellsWants = (eraHost ~= nil) and (SfuiDB and SfuiDB.showSpellBookTrainerPanel) and true or false

    if preferredHost == "spells" and spellsWants then
        return "spells", eraHost
    elseif preferredHost == "char" and charWants then
        return "char", charFrame
    elseif charWants then
        return "char", charFrame
    elseif spellsWants then
        return "spells", eraHost
    end
    return nil, nil
end

local function ApplyDefaultCharAnchor(frame, charFrame)
    if not frame or not charFrame then return end
    if sfui.isEra then
        local engraving = _G.EngravingFrame
        local xOffset = (engraving and engraving.IsShown and engraving:IsShown()) and 172 or -30
        frame:SetPoint("TOPLEFT", charFrame, "TOPRIGHT", xOffset, -13)
        frame:SetPoint("BOTTOMLEFT", charFrame, "BOTTOMRIGHT", xOffset, 73)
    else
        frame:SetPoint("TOPLEFT", charFrame, "TOPRIGHT", 2, -12)
    end
end

local function RestorePosition(frame)
    if not frame or IsInCombat() then return end
    frame:ClearAllPoints()
    frame:SetSize(PANEL_WIDTH, PANEL_HEIGHT)

    if activeHostKind == "spells" then
        local pos = SfuiDB and SfuiDB.spellsTrainerPanelPos
        if pos and pos.point and pos.x and pos.y then
            frame:SetPoint(pos.point, UIParent, pos.relPoint or "BOTTOMLEFT", pos.x, pos.y)
        elseif activeHostFrame then
            frame:SetPoint("TOPLEFT", activeHostFrame, "TOPRIGHT", 2, -12)
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", 260, 0)
        end
    else
        local pos = SfuiDB and SfuiDB.characterInfoPanelPos
        if pos and pos.point and pos.x and pos.y then
            frame:SetPoint(pos.point, UIParent, pos.relPoint or "BOTTOMLEFT", pos.x, pos.y)
        elseif _G.CharacterFrame then
            ApplyDefaultCharAnchor(frame, _G.CharacterFrame)
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
        end
    end
end
trainerModule.RestorePosition = RestorePosition

local function SavePosition(frame)
    if not frame or IsInCombat() then return end
    frame:StopMovingOrSizing()
    local left, top = frame:GetLeft(), frame:GetTop()
    if not (left and top) then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    SfuiDB = SfuiDB or {}
    local saved = {
        point = "TOPLEFT",
        relPoint = "BOTTOMLEFT",
        x = math_floor(left + 0.5),
        y = math_floor(top + 0.5),
    }
    if activeHostKind == "spells" then
        SfuiDB.spellsTrainerPanelPos = saved
    else
        SfuiDB.characterInfoPanelPos = saved
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Toggle Button Visuals & Badges
-- ─────────────────────────────────────────────────────────────────────────────

local function StyleSingleToggleBtn(btn, isActive, readyCount)
    if not btn then return end
    if btn.SetBackdropBorderColor then
        if isActive then
            local curPal = (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()) or EMPTY_PALETTE
            local accent = curPal.accentColor or (sfui.config and sfui.config.spec_color) or COLORS.ACCENT_FALLBACK
            btn:SetBackdropBorderColor(accent[1] or 0.4, accent[2] or 0.8, accent[3] or 1.0, 1)
        else
            btn:SetBackdropBorderColor(0, 0, 0, 1)
        end
    end
    if btn.badge then
        if readyCount and readyCount > 0 then
            btn.badge:SetText(readyCount > 99 and "99+" or tostring(readyCount))
            btn.badge:Show()
        else
            btn.badge:SetText("")
            btn.badge:Hide()
        end
    end
end

local function UpdateAllToggleVisuals()
    local shown = panelFrame and panelFrame:IsShown()
    local charActive = shown and activeHostKind == "char"
    local spellsActive = shown and activeHostKind == "spells"
    local ready = summary.readyCount or 0

    StyleSingleToggleBtn(charToggleBtn, charActive, ready)
    StyleSingleToggleBtn(eraSpellBookBtn, spellsActive and activeHostFrame == _G.SpellBookFrame, ready)
    StyleSingleToggleBtn(eraTalentBtn, spellsActive and activeHostFrame == _G.PlayerTalentFrame, ready)

    if UpdateSpellBookTabVisual then
        UpdateSpellBookTabVisual()
    end

    if sfui.character and sfui.character.infopanel and sfui.character.infopanel.UpdateToggleVisual then
        sfui.character.infopanel.UpdateToggleVisual()
    end
end
trainerModule.UpdateToggleVisuals = UpdateAllToggleVisuals

-- ─────────────────────────────────────────────────────────────────────────────
--  Row Pool & List Rendering
-- ─────────────────────────────────────────────────────────────────────────────

local allRows = {}
local activeRowCount = 0
local cursorY = 0
local scrollChild = nil
local pal = EMPTY_PALETTE

local function RowOnEnter(self)
    if self.highlight then self.highlight:Show() end
    local entry = self.entryData
    if not entry then return end

    local tip = common and common.get_tooltip and common.get_tooltip()
    if not tip then return end
    tip:SetOwner(self, "ANCHOR_RIGHT")
    tip:ClearLines()

    local populated = false
    if entry.slotIndex and entry.spellBank ~= nil and tip.SetSpellBookItem then
        tip:SetSpellBookItem(entry.slotIndex, entry.spellBank)
        populated = (tip:NumLines() or 0) > 0
    end
    if not populated and entry.spellID and tip.SetSpellByID then
        tip:SetSpellByID(entry.spellID)
        populated = (tip:NumLines() or 0) > 0
    end
    if not populated then
        tip:AddLine(entry.lowerName, 1, 1, 1)
        if entry.subName and entry.subName ~= "" then
            tip:AddLine(SafeLower(entry.subName, ""), 0.75, 0.75, 0.75)
        end
    end

    tip:AddLine(" ")
    if entry.category and entry.category ~= "" then
        tip:AddLine(string_format("tree: %s", entry.category), 0.72, 0.72, 0.76)
    end
    if entry.isReady then
        tip:AddLine("status: ready to train now", 0.3, 1.0, 0.3)
    else
        tip:AddLine(string_format("status: unlocks at level %d", entry.levelLearned), 1.0, 0.82, 0.2)
    end
    if entry.cost and entry.cost > 0 then
        local moneyStr = FormatMoney(entry.cost)
        if moneyStr then
            local canAfford = ((GetMoney and GetMoney()) or 0) >= entry.cost
            if entry.isReady and not canAfford then
                tip:AddLine("training cost: " .. moneyStr, 1.0, 0.4, 0.4)
            else
                tip:AddLine("training cost: " .. moneyStr, 0.9, 0.9, 0.9)
            end
        end
    end
    if entry.spellID then
        tip:AddLine("shift+left-click to link spell in chat", 0.55, 0.55, 0.6)
    end
    tip:Show()
end

local function RowOnLeave(self)
    if self.highlight then self.highlight:Hide() end
    if common and common.hide_tooltip then
        common.hide_tooltip()
    end
end

local function RowOnClick(self, button)
    if button ~= "LeftButton" or not (IsShiftKeyDown and IsShiftKeyDown()) then return end
    local entry = self.entryData
    if not entry or not entry.spellID then return end
    local link = nil
    if C_Spell and C_Spell.GetSpellLink then
        link = C_Spell.GetSpellLink(entry.spellID)
    elseif _G.GetSpellLink then
        link = _G.GetSpellLink(entry.spellID)
    end
    if link and not issecretvalue(link) and common and common.insert_link_to_chat then
        common.insert_link_to_chat(link)
    end
end

local function AcquireRow()
    activeRowCount = activeRowCount + 1
    local row = allRows[activeRowCount]
    if not row then
        row = CreateFrame("Button", nil, scrollChild)
        row:SetHeight(20)
        row:RegisterForClicks("LeftButtonUp")
        row:SetFrameLevel((scrollChild:GetFrameLevel() or 1) + 1)

        local highlight = row:CreateTexture(nil, "BACKGROUND")
        highlight:SetAllPoints(row)
        highlight:SetColorTexture(1, 1, 1, 0.06)
        highlight:Hide()
        row.highlight = highlight

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.icon = icon

        local value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        value:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        value:SetJustifyH("RIGHT")
        value:SetWordWrap(false)
        row.value = value

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        row.label = label

        local sep = row:CreateTexture(nil, "ARTWORK")
        sep:SetHeight(1)
        sep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 1)
        sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 1)
        sep:Hide()
        row.sep = sep

        row:SetScript("OnEnter", RowOnEnter)
        row:SetScript("OnLeave", RowOnLeave)
        row:SetScript("OnClick", RowOnClick)

        allRows[activeRowCount] = row
    elseif row:GetParent() ~= scrollChild then
        row:SetParent(scrollChild)
        row.currentY = nil
    end
    return row
end

local function PlaceRow(row, isHeader, height)
    local targetLevel = (scrollChild:GetFrameLevel() or 1) + 1
    if row:GetFrameLevel() ~= targetLevel then
        row:SetFrameLevel(targetLevel)
    end
    if row.currentY ~= cursorY or row.isHeader ~= isHeader or row:GetHeight() ~= height then
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, cursorY)
        row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, cursorY)
        row:SetHeight(height)
        row.currentY = cursorY
        row.isHeader = isHeader
    end
    row.label:ClearAllPoints()
    if isHeader then
        row.icon:Hide()
        row.label:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.label:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
    else
        row.icon:Show()
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
        row.label:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
    end
end

local function RenderHeaderRow(titleText, rightText, useReadyColor)
    if activeRowCount > 0 then
        cursorY = cursorY - 4
    end
    local h = AcquireRow()
    PlaceRow(h, true, 21)

    local color
    if useReadyColor then
        color = COLORS.READY
    else
        color = pal.accentColor or (sfui.config and sfui.config.spec_color) or COLORS.ACCENT_FALLBACK
    end
    h.label:SetText(titleText)
    h.label:SetTextColor(color[1] or 0.4, color[2] or 0.8, color[3] or 1.0, 1.0)

    if rightText and rightText ~= "" then
        local dim = pal.dimTextColor or COLORS.DIM
        h.value:SetText(rightText)
        h.value:SetTextColor(dim[1], dim[2], dim[3], 1.0)
    else
        h.value:SetText("")
    end

    local isCamelotTheme = sfui.theme and sfui.theme.IsCamelotActive and sfui.theme.IsCamelotActive()
    local hl = pal.highlightColor
    if isCamelotTheme and hl then
        h.sep:SetColorTexture(hl[1], hl[2], hl[3], 0.35)
    else
        h.sep:SetColorTexture(0.25, 0.25, 0.25, 0.75)
    end
    h.sep:Show()
    h.entryData = nil
    h:EnableMouse(false)
    h:Show()
    cursorY = cursorY - 21
end

local function RenderSpellRow(entry, playerMoney)
    local r = AcquireRow()
    PlaceRow(r, false, 20)
    r.sep:Hide()
    r.entryData = entry
    r:EnableMouse(true)

    r.icon:SetTexture(entry.icon or BOOK_ICON)
    if entry.isReady then
        r.icon:SetDesaturated(false)
        r.icon:SetAlpha(1.0)
    else
        r.icon:SetDesaturated(true)
        r.icon:SetAlpha(0.75)
    end

    local labelText = entry.lowerName
    if entry.compactSub and entry.compactSub ~= "" then
        labelText = string_format("%s |cff808088%s|r", entry.lowerName, entry.compactSub)
    end
    r.label:SetText(labelText)

    if entry.isReady then
        r.label:SetTextColor(COLORS.WHITE[1], COLORS.WHITE[2], COLORS.WHITE[3], 1.0)
    else
        r.label:SetTextColor(COLORS.UPCOMING[1], COLORS.UPCOMING[2], COLORS.UPCOMING[3], 0.9)
    end

    if entry.cost and entry.cost > 0 then
        local coinStr = FormatMoney(entry.cost) or ""
        r.value:SetText(coinStr)
        if entry.isReady and playerMoney < entry.cost then
            r.value:SetTextColor(COLORS.RED[1], COLORS.RED[2], COLORS.RED[3], 1.0)
        else
            r.value:SetTextColor(COLORS.WHITE[1], COLORS.WHITE[2], COLORS.WHITE[3], 1.0)
        end
    elseif entry.isReady then
        r.value:SetText(string_format("lv %d", entry.levelLearned))
        r.value:SetTextColor(COLORS.READY[1], COLORS.READY[2], COLORS.READY[3], 1.0)
    else
        r.value:SetText(entry.category or string_format("lv %d", entry.levelLearned))
        local dim = pal.dimTextColor or COLORS.DIM
        r.value:SetTextColor(dim[1], dim[2], dim[3], 1.0)
    end

    r:Show()
    cursorY = cursorY - 20
end

local function StylePillButton(btn, isSelected, highlightGreen)
    if not btn then return end
    if sfui.theme and sfui.theme.ApplyTabStyle then
        sfui.theme.ApplyTabStyle(btn, isSelected)
        if not isSelected and highlightGreen and btn.fs then
            btn.fs:SetTextColor(COLORS.READY[1], COLORS.READY[2], COLORS.READY[3], 1.0)
        end
    else
        if common and common.apply_flat_backdrop then
            common.apply_flat_backdrop(
                btn,
                isSelected and { 0.22, 0.18, 0.08, 0.9 } or { 0.08, 0.08, 0.10, 0.55 },
                isSelected and { 1.0, 0.82, 0.2, 0.85 } or { 0.22, 0.22, 0.26, 0.6 }
            )
        end
        if btn.fs then
            if isSelected then
                btn.fs:SetTextColor(COLORS.GOLD[1], COLORS.GOLD[2], COLORS.GOLD[3], 1.0)
            elseif highlightGreen then
                btn.fs:SetTextColor(COLORS.READY[1], COLORS.READY[2], COLORS.READY[3], 1.0)
            else
                btn.fs:SetTextColor(0.7, 0.7, 0.72, 1.0)
            end
        end
    end
end

local function UpdateFilterControls()
    if not panelFrame then return end

    local buttons = panelFrame.filterButtons
    if buttons then
        if buttons.ready and buttons.ready.fs then
            buttons.ready.fs:SetText(string_format("ready (%d)", summary.readyCount))
            StylePillButton(buttons.ready, filterMode == "ready", summary.readyCount > 0)
        end
        if buttons.upcoming and buttons.upcoming.fs then
            buttons.upcoming.fs:SetText(string_format("future (%d)", summary.upcomingCount))
            StylePillButton(buttons.upcoming, filterMode == "upcoming", false)
        end
        if buttons.all and buttons.all.fs then
            buttons.all.fs:SetText(string_format("all (%d)", summary.totalCount))
            StylePillButton(buttons.all, filterMode == "all", false)
        end
    end

    local specBtn = panelFrame.specButton
    if specBtn and specBtn.fs then
        if activeSpecFilter then
            specBtn.fs:SetText(activeSpecFilter)
            StylePillButton(specBtn, true, false)
        else
            specBtn.fs:SetText("spec: all")
            StylePillButton(specBtn, false, false)
        end
    end
end

local function UpdateSubtitleAndFooter(playerMoney)
    if not panelFrame then return end
    local dim = pal.dimTextColor or COLORS.DIM

    if panelFrame.subTitle then
        if summary.readyCount > 0 then
            if summary.readyCost > 0 and summary.readyMissingCosts == 0 then
                panelFrame.subTitle:SetText(string_format("%s - %d ready (%s)",
                    summary.className, summary.readyCount, FormatMoney(summary.readyCost) or ""))
            else
                panelFrame.subTitle:SetText(string_format("%s - %d ready to train",
                    summary.className, summary.readyCount))
            end
            panelFrame.subTitle:SetTextColor(COLORS.READY[1], COLORS.READY[2], COLORS.READY[3], 1.0)
        elseif summary.nextLevel then
            panelFrame.subTitle:SetText(string_format("%s - up to date (next: lv %d)",
                summary.className, summary.nextLevel))
            panelFrame.subTitle:SetTextColor(dim[1], dim[2], dim[3], 1.0)
        else
            panelFrame.subTitle:SetText(string_format("%s - all class spells learned", summary.className))
            panelFrame.subTitle:SetTextColor(dim[1], dim[2], dim[3], 1.0)
        end
    end

    if panelFrame.footerLeft then
        panelFrame.footerLeft:SetText(string_format("%d shown", #drawerFilteredEntries))
        panelFrame.footerLeft:SetTextColor(dim[1], dim[2], dim[3], 1.0)
    end

    if panelFrame.footerRight then
        if summary.readyCount > 0 and summary.readyCost > 0 then
            local costStr = FormatMoney(summary.readyCost) or ""
            panelFrame.footerRight:SetText("ready: " .. costStr)
            if playerMoney < summary.readyCost then
                panelFrame.footerRight:SetTextColor(COLORS.RED[1], COLORS.RED[2], COLORS.RED[3], 1.0)
            else
                panelFrame.footerRight:SetTextColor(COLORS.WHITE[1], COLORS.WHITE[2], COLORS.WHITE[3], 1.0)
            end
        elseif summary.readyCount > 0 then
            panelFrame.footerRight:SetText("visit class trainer for prices")
            panelFrame.footerRight:SetTextColor(dim[1], dim[2], dim[3], 1.0)
        elseif filterMode == "upcoming" and summary.upcomingCost > 0 then
            panelFrame.footerRight:SetText("total: " .. (FormatMoney(summary.upcomingCost) or ""))
            panelFrame.footerRight:SetTextColor(dim[1], dim[2], dim[3], 1.0)
        else
            panelFrame.footerRight:SetText("")
        end
    end
end

local function EnsureCatalogFresh()
    if catalogDirty then
        RebuildCatalog()
        UpdateAllToggleVisuals()
    end
end

function trainerModule.RenderView()
    EnsureCatalogFresh()

    if IsInCombat() or not panelFrame or not panelFrame:IsShown() or not panelFrame.scrollChild then
        return
    end

    RebuildFilteredEntries(drawerSearchText, drawerFilteredEntries)
    pal = (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()) or EMPTY_PALETTE
    scrollChild = panelFrame.scrollChild
    activeRowCount = 0
    cursorY = -4

    local playerMoney = (GetMoney and GetMoney()) or 0
    if issecretvalue(playerMoney) or type(playerMoney) ~= "number" then playerMoney = 0 end

    UpdateFilterControls()
    UpdateSubtitleAndFooter(playerMoney)

    if #drawerFilteredEntries == 0 then
        if panelFrame.emptyText then
            if drawerSearchText ~= "" or activeSpecFilter then
                panelFrame.emptyText:SetText("no matching trainer spells")
            elseif filterMode == "ready" then
                panelFrame.emptyText:SetText("no spells ready to train")
            elseif filterMode == "upcoming" then
                panelFrame.emptyText:SetText("no upcoming class spells")
            else
                panelFrame.emptyText:SetText("all class spells learned")
            end
            panelFrame.emptyText:Show()
        end
    else
        if panelFrame.emptyText then
            panelFrame.emptyText:Hide()
        end

        -- Pre-calculate per-group counts & costs for clean section headers
        local readyShownCount = 0
        local readyShownCost = 0
        local readyMissing = false
        for i = 1, #drawerFilteredEntries do
            local e = drawerFilteredEntries[i]
            if e.isReady then
                readyShownCount = readyShownCount + 1
                if e.cost and e.cost > 0 then
                    readyShownCost = readyShownCost + e.cost
                else
                    readyMissing = true
                end
            end
        end

        local renderedReadyHeader = false
        local currentLevelGroup = nil

        for i = 1, #drawerFilteredEntries do
            local e = drawerFilteredEntries[i]
            if e.isReady then
                if not renderedReadyHeader then
                    renderedReadyHeader = true
                    local rightHdr = (readyShownCost > 0 and not readyMissing) and FormatMoney(readyShownCost) or nil
                    RenderHeaderRow(string_format("ready now (%d)", readyShownCount), rightHdr, true)
                end
                RenderSpellRow(e, playerMoney)
            else
                if currentLevelGroup ~= e.levelLearned then
                    currentLevelGroup = e.levelLearned
                    local lvlCount = 0
                    local lvlCost = 0
                    local lvlMissing = false
                    for k = i, #drawerFilteredEntries do
                        local nextE = drawerFilteredEntries[k]
                        if not nextE.isReady and nextE.levelLearned == currentLevelGroup then
                            lvlCount = lvlCount + 1
                            if nextE.cost and nextE.cost > 0 then
                                lvlCost = lvlCost + nextE.cost
                            else
                                lvlMissing = true
                            end
                        else
                            break
                        end
                    end
                    local rightHdr = (lvlCost > 0 and not lvlMissing) and FormatMoney(lvlCost)
                        or string_format("%d %s", lvlCount, lvlCount == 1 and "spell" or "spells")
                    RenderHeaderRow(string_format("level %d", currentLevelGroup), rightHdr, false)
                end
                RenderSpellRow(e, playerMoney)
            end
        end
    end

    for i = activeRowCount + 1, #allRows do
        allRows[i]:Hide()
    end

    local totalHeight = math_max(1, -cursorY + 8)
    if scrollChild:GetHeight() ~= totalHeight then
        scrollChild:SetHeight(totalHeight)
    end
end

local function RefreshOpenTrainerViews()
    if panelFrame and panelFrame:IsShown() then
        trainerModule.RenderView()
    end
    if sbPageFrame and sbPageFrame:IsShown() and RenderSpellBookTrainerPage then
        RenderSpellBookTrainerPage()
    end
end

local function SelectFilterMode(newMode)
    if filterMode == newMode then return end
    filterMode = newMode
    if SfuiDB then SfuiDB.trainerPanelFilter = newMode end
    if panelFrame and panelFrame.scrollFrame then
        panelFrame.scrollFrame:SetVerticalScroll(0)
    end
    spellBookCurrentPage = 1
    RefreshOpenTrainerViews()
end

local function CycleSpecFilter(mouseButton)
    if mouseButton == "RightButton" or #categoryList == 0 then
        activeSpecFilter = nil
    else
        if not activeSpecFilter then
            activeSpecFilter = categoryList[1]
        else
            local nextIdx = nil
            for i = 1, #categoryList do
                if categoryList[i] == activeSpecFilter then
                    nextIdx = i + 1
                    break
                end
            end
            activeSpecFilter = (nextIdx and nextIdx <= #categoryList) and categoryList[nextIdx] or nil
        end
    end
    if panelFrame and panelFrame.scrollFrame then
        panelFrame.scrollFrame:SetVerticalScroll(0)
    end
    spellBookCurrentPage = 1
    RefreshOpenTrainerViews()
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Forever Embedded Spellbook Category Tab & Two-Page Parchment View
-- ─────────────────────────────────────────────────────────────────────────────

local SB_LAYOUT = {
    VIEW_WIDTH = 448,
    VIEW_HEIGHT = 510,
    CARD_WIDTH = 218,
    CARD_HEIGHT = 46,
    CARD_ROW_STEP = 50,
    COL2_X = 230,
    HEADER_HEIGHT = 26,
    HEADER_STEP = 28,
}

local PARCHMENT = {
    INK = { 0.20, 0.12, 0.06 },
    INK_UPCOMING = { 0.34, 0.24, 0.16 },
    INK_DIM = { 0.44, 0.32, 0.21 },
    READY = { 0.08, 0.44, 0.10 },
    RED = { 0.72, 0.12, 0.12 },
}

local sbPools = {
    headers = {},
    activeHeaders = 0,
    cards = {},
    activeCards = 0,
    buckets = {},
    usedBuckets = 0,
    nodes = {},
    usedNodes = 0,
}

local function PlaySoundSafe(soundID)
    if _G.PlaySound and soundID then
        _G.PlaySound(soundID)
    end
end

local function HasAtlas(atlasName)
    if not atlasName then return false end
    if sfui.theme and sfui.theme.HasAtlas then
        return sfui.theme.HasAtlas(atlasName)
    end
    return (_G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo(atlasName) ~= nil) or false
end

local function GetSpellBookInkRGB()
    local c = _G.SPELLBOOK_FONT_COLOR
    if c and c.GetRGB then
        local r, g, b = c:GetRGB()
        if r and g and b then
            return r, g, b
        end
    end
    return PARCHMENT.INK[1], PARCHMENT.INK[2], PARCHMENT.INK[3]
end

local function IsSpellBookParchmentVisible(sbf)
    if not sbf then return false end
    local halved = sbf.BookBGHalved
    local left = sbf.BookBGLeft
    -- Require > 0.5 alpha so dark window skins that dim parchment to ~0.10 watermark fall back to dark mode
    local halvedVis = halved and halved:IsShown() and (halved:GetAlpha() or 1) > 0.5
    local leftVis = left and left:IsShown() and (left:GetAlpha() or 1) > 0.5
    return (halvedVis or leftVis) and true or false
end

local function StyleSpellBookPill(btn, isSelected, highlightReady, useParchment)
    if not btn then return end
    if not useParchment then
        StylePillButton(btn, isSelected, highlightReady)
        return
    end
    if common and common.apply_flat_backdrop then
        common.apply_flat_backdrop(
            btn,
            isSelected and { 0.30, 0.19, 0.09, 0.28 } or { 0.22, 0.14, 0.07, 0.10 },
            isSelected and { 0.44, 0.27, 0.11, 0.85 } or { 0.36, 0.24, 0.13, 0.40 }
        )
    end
    if btn.fs then
        if isSelected then
            btn.fs:SetTextColor(0.14, 0.08, 0.03, 1.0)
        elseif highlightReady then
            btn.fs:SetTextColor(PARCHMENT.READY[1], PARCHMENT.READY[2], PARCHMENT.READY[3], 1.0)
        else
            btn.fs:SetTextColor(PARCHMENT.INK_DIM[1], PARCHMENT.INK_DIM[2], PARCHMENT.INK_DIM[3], 1.0)
        end
    end
end

local function AcquireSbBucket()
    sbPools.usedBuckets = sbPools.usedBuckets + 1
    local b = sbPools.buckets[sbPools.usedBuckets]
    if not b then
        b = { items = {}, height = 0 }
        sbPools.buckets[sbPools.usedBuckets] = b
    else
        wipe(b.items)
        b.height = 0
    end
    return b
end

local function AcquireSbNode()
    sbPools.usedNodes = sbPools.usedNodes + 1
    local n = sbPools.nodes[sbPools.usedNodes]
    if not n then
        n = {}
        sbPools.nodes[sbPools.usedNodes] = n
    end
    return n
end

local function AcquireSbHeader(parentView)
    sbPools.activeHeaders = sbPools.activeHeaders + 1
    local hdr = sbPools.headers[sbPools.activeHeaders]
    if not hdr then
        hdr = CreateFrame("Frame", nil, parentView)
        hdr:SetSize(SB_LAYOUT.VIEW_WIDTH, SB_LAYOUT.HEADER_HEIGHT)

        local titleFs = hdr:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        titleFs:SetPoint("LEFT", hdr, "LEFT", 2, 2)
        titleFs:SetJustifyH("LEFT")
        titleFs:SetWordWrap(false)
        hdr.titleFs = titleFs

        local rightFs = hdr:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        rightFs:SetPoint("RIGHT", hdr, "RIGHT", -4, 2)
        rightFs:SetJustifyH("RIGHT")
        rightFs:SetWordWrap(false)
        hdr.rightFs = rightFs

        titleFs:SetPoint("RIGHT", rightFs, "LEFT", -8, 0)

        local divider = hdr:CreateTexture(nil, "ARTWORK")
        hdr.divider = divider

        sbPools.headers[sbPools.activeHeaders] = hdr
    elseif hdr:GetParent() ~= parentView then
        hdr:SetParent(parentView)
    end
    hdr:SetFrameLevel((parentView:GetFrameLevel() or 120) + 1)
    return hdr
end

local function CardOnEnter(self)
    if self.backplate then
        self.backplate:SetAlpha(self.hoverBackplateAlpha or 0.72)
    end
    RowOnEnter(self)
end

local function CardOnLeave(self)
    if self.backplate then
        self.backplate:SetAlpha(self.defaultBackplateAlpha or 0.26)
    end
    RowOnLeave(self)
end

local function AcquireSbCard(parentView)
    sbPools.activeCards = sbPools.activeCards + 1
    local card = sbPools.cards[sbPools.activeCards]
    if not card then
        card = CreateFrame("Button", nil, parentView)
        card:SetSize(SB_LAYOUT.CARD_WIDTH, SB_LAYOUT.CARD_HEIGHT)
        card:RegisterForClicks("LeftButtonUp")

        local backplate = card:CreateTexture(nil, "BACKGROUND")
        backplate:SetPoint("TOPLEFT", card, "TOPLEFT", -2, 2)
        backplate:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 2, -2)
        card.backplate = backplate

        local iconHolder = CreateFrame("Frame", nil, card)
        iconHolder:SetSize(36, 36)
        iconHolder:SetPoint("LEFT", card, "LEFT", 4, 0)
        iconHolder:EnableMouse(false)
        card.iconHolder = iconHolder

        local trainableShadow = iconHolder:CreateTexture(nil, "BACKGROUND", nil, -1)
        trainableShadow:SetSize(48, 48)
        trainableShadow:SetPoint("CENTER", iconHolder, "CENTER", 0, 0)
        if HasAtlas("spellbook-item-needtrainer-shadow") then
            trainableShadow:SetAtlas("spellbook-item-needtrainer-shadow", false)
        else
            trainableShadow:SetColorTexture(0.2, 0.9, 0.2, 0.18)
        end
        trainableShadow:Hide()
        card.trainableShadow = trainableShadow

        local icon = iconHolder:CreateTexture(nil, "ARTWORK")
        icon:SetSize(34, 34)
        icon:SetPoint("CENTER", iconHolder, "CENTER", 0, 0)
        card.icon = icon

        if iconHolder.CreateMaskTexture and HasAtlas("spellbook-item-spellicon-mask") then
            local mask = iconHolder:CreateMaskTexture(nil, "ARTWORK")
            mask:SetAllPoints(icon)
            mask:SetAtlas("spellbook-item-spellicon-mask", false)
            icon:AddMaskTexture(mask)
            card.iconMask = mask
        else
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end

        local border = iconHolder:CreateTexture(nil, "OVERLAY")
        card.iconBorder = border

        local nameFs = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameFs:SetPoint("TOPLEFT", iconHolder, "TOPRIGHT", 8, -3)
        nameFs:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6, -3)
        nameFs:SetJustifyH("LEFT")
        nameFs:SetWordWrap(false)
        card.nameFs = nameFs

        local costFs = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        costFs:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -6, 5)
        costFs:SetJustifyH("RIGHT")
        costFs:SetWordWrap(false)
        card.costFs = costFs

        local metaFs = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        metaFs:SetPoint("BOTTOMLEFT", iconHolder, "BOTTOMRIGHT", 8, 5)
        metaFs:SetPoint("BOTTOMRIGHT", costFs, "BOTTOMLEFT", -4, 0)
        metaFs:SetJustifyH("LEFT")
        metaFs:SetWordWrap(false)
        card.metaFs = metaFs

        card:SetScript("OnEnter", CardOnEnter)
        card:SetScript("OnLeave", CardOnLeave)
        card:SetScript("OnClick", RowOnClick)

        sbPools.cards[sbPools.activeCards] = card
    elseif card:GetParent() ~= parentView then
        card:SetParent(parentView)
    end
    card:SetFrameLevel((parentView:GetFrameLevel() or 120) + 2)
    return card
end

local function RestoreMaskedNativeTabAlpha()
    if maskedNativeTabRef then
        if maskedNativeTabRef.SquareBackgroundActive then
            maskedNativeTabRef.SquareBackgroundActive:SetAlpha(1)
        end
        if maskedNativeTabRef.SquareBackgroundActiveGlow then
            maskedNativeTabRef.SquareBackgroundActiveGlow:SetAlpha(1)
        end
        maskedNativeTabRef = nil
    end
end

local function SyncActiveNativeTabMask()
    RestoreMaskedNativeTabAlpha()
    if not sbPageFrame or not sbPageFrame.activeTabMaskBtn then return end
    local maskBtn = sbPageFrame.activeTabMaskBtn
    local psf = _G.PlayerSpellsFrame
    local sbf = psf and psf.SpellBookFrame
    if not isSpellBookTrainerTabActive or not sbf or not sbf.CategoryTabSystem then
        maskBtn:Hide()
        return
    end

    local tabID = sbf.GetTab and sbf:GetTab()
    maskedNativeTabID = tabID
    local nativeTab = tabID and sbf.CategoryTabSystem.GetTabButton and sbf.CategoryTabSystem:GetTabButton(tabID)
    if not nativeTab or not nativeTab:IsShown() then
        maskBtn:Hide()
        return
    end

    maskedNativeTabRef = nativeTab
    if nativeTab.SquareBackgroundActive then
        nativeTab.SquareBackgroundActive:SetAlpha(0)
    end
    if nativeTab.SquareBackgroundActiveGlow then
        nativeTab.SquareBackgroundActiveGlow:SetAlpha(0)
    end

    maskBtn:ClearAllPoints()
    maskBtn:SetAllPoints(nativeTab)
    maskBtn:SetFrameLevel((nativeTab:GetFrameLevel() or 102) + 6)
    if maskBtn.icon then
        maskBtn.icon:SetTexture(nativeTab.tabIcon or BOOK_ICON)
    end
    maskBtn.nativeTooltipText = SafeLower(nativeTab.GetTooltipText and nativeTab:GetTooltipText(), "")
    maskBtn:Show()
end

local function SyncSpellBookPageArt()
    if not sbPageFrame then return end
    local psf = _G.PlayerSpellsFrame
    local sbf = psf and psf.SpellBookFrame
    if not sbf then return end

    local isMinimized = sbf.isMinimized and true or false
    local useParchment = IsSpellBookParchmentVisible(sbf)
    sbPageFrame.useParchment = useParchment
    sbPageFrame.isMinimized = isMinimized

    if sbPageFrame.bgHalved then
        sbPageFrame.bgHalved:SetShown(useParchment and isMinimized)
    end
    if sbPageFrame.bgLeft then
        sbPageFrame.bgLeft:SetShown(useParchment and not isMinimized)
    end
    if sbPageFrame.bgRight then
        sbPageFrame.bgRight:SetShown(useParchment and not isMinimized)
    end
    if sbPageFrame.darkFallbackBg then
        sbPageFrame.darkFallbackBg:SetShown(not useParchment)
    end
    if sbPageFrame.view2 then
        sbPageFrame.view2:SetShown(not isMinimized)
    end

    -- Reposition search bar & status label smoothly between 1-page (574px) and 2-page (1148px) spreads
    local sbSearch = sbPageFrame.searchBox
    local specBtn = sbPageFrame.specButton
    if sbSearch and specBtn then
        sbSearch:ClearAllPoints()
        if isMinimized then
            sbSearch:SetPoint("LEFT", specBtn, "RIGHT", 6, 0)
            sbSearch:SetPoint("RIGHT", sbPageFrame, "TOPLEFT", 533, -16)
        else
            sbSearch:SetPoint("TOPRIGHT", sbPageFrame, "TOPRIGHT", -50, -6)
            sbSearch:SetWidth(230)
        end
        if useParchment and common and common.apply_flat_backdrop then
            common.apply_flat_backdrop(sbSearch, { 0.18, 0.12, 0.06, 0.14 }, { 0.38, 0.25, 0.13, 0.55 })
            sbSearch:SetTextColor(0.16, 0.10, 0.04, 1.0)
            if sbPageFrame.searchPlaceholder then
                sbPageFrame.searchPlaceholder:SetTextColor(0.45, 0.34, 0.22, 0.85)
            end
        elseif sfui.theme and sfui.theme.ApplyInputStyle then
            sfui.theme.ApplyInputStyle(sbSearch)
            sbSearch:SetTextColor(1, 1, 1, 1)
            if sbPageFrame.searchPlaceholder then
                sbPageFrame.searchPlaceholder:SetTextColor(0.55, 0.55, 0.58, 1)
            end
        end
    end

    if sbPageFrame.statusTopRight then
        sbPageFrame.statusTopRight:SetShown(not isMinimized)
    end
end

local function BuildSpellBookViewBuckets()
    sbPools.usedBuckets = 0
    sbPools.usedNodes = 0

    if #sbFilteredEntries == 0 then
        return 0
    end

    local currentBucket = AcquireSbBucket()

    local function EnsureSpace(neededHeight)
        if currentBucket.height > 0 and (currentBucket.height + neededHeight > SB_LAYOUT.VIEW_HEIGHT) then
            currentBucket = AcquireSbBucket()
            return true
        end
        return false
    end

    local function AppendGroup(baseTitle, rightText, useReadyColor, startIdx, endIdx)
        local topGap = (currentBucket.height > 0) and 6 or 0
        if currentBucket.height > 0 and (currentBucket.height + topGap + SB_LAYOUT.HEADER_STEP + SB_LAYOUT.CARD_ROW_STEP > SB_LAYOUT.VIEW_HEIGHT) then
            currentBucket = AcquireSbBucket()
            topGap = 0
        end

        currentBucket.height = currentBucket.height + topGap
        local hdrNode = AcquireSbNode()
        hdrNode.isHeader = true
        hdrNode.y = -currentBucket.height
        hdrNode.title = baseTitle
        hdrNode.rightText = rightText
        hdrNode.useReadyColor = useReadyColor
        table_insert(currentBucket.items, hdrNode)
        currentBucket.height = currentBucket.height + SB_LAYOUT.HEADER_STEP

        local col = 0
        local rowTopY = -currentBucket.height
        for idx = startIdx, endIdx do
            if col == 0 and idx > startIdx then
                if currentBucket.height + SB_LAYOUT.CARD_ROW_STEP > SB_LAYOUT.VIEW_HEIGHT then
                    currentBucket = AcquireSbBucket()
                    local contHdr = AcquireSbNode()
                    contHdr.isHeader = true
                    contHdr.y = 0
                    contHdr.title = baseTitle .. " (cont.)"
                    contHdr.rightText = nil
                    contHdr.useReadyColor = useReadyColor
                    table_insert(currentBucket.items, contHdr)
                    currentBucket.height = SB_LAYOUT.HEADER_STEP
                end
                rowTopY = -currentBucket.height
            end

            local cardNode = AcquireSbNode()
            cardNode.isHeader = false
            cardNode.entry = sbFilteredEntries[idx]
            cardNode.x = (col == 0) and 0 or SB_LAYOUT.COL2_X
            cardNode.y = rowTopY
            table_insert(currentBucket.items, cardNode)

            if col == 0 then
                col = 1
                if idx == endIdx then
                    currentBucket.height = currentBucket.height + SB_LAYOUT.CARD_ROW_STEP
                end
            else
                col = 0
                currentBucket.height = currentBucket.height + SB_LAYOUT.CARD_ROW_STEP
            end
        end
    end

    -- Group 1: Ready spells
    local readyEnd = 0
    local readyCost = 0
    local readyMissing = false
    for i = 1, #sbFilteredEntries do
        local e = sbFilteredEntries[i]
        if e.isReady then
            readyEnd = i
            if e.cost and e.cost > 0 then
                readyCost = readyCost + e.cost
            else
                readyMissing = true
            end
        else
            break
        end
    end
    if readyEnd > 0 then
        local rightHdr = (readyCost > 0 and not readyMissing) and FormatMoney(readyCost) or nil
        AppendGroup(string_format("ready now (%d)", readyEnd), rightHdr, true, 1, readyEnd)
    end

    -- Remaining groups: Level buckets
    local idx = readyEnd + 1
    while idx <= #sbFilteredEntries do
        local lvl = sbFilteredEntries[idx].levelLearned
        local groupEnd = idx
        local lvlCost = 0
        local lvlMissing = false
        while groupEnd <= #sbFilteredEntries and sbFilteredEntries[groupEnd].levelLearned == lvl do
            local e = sbFilteredEntries[groupEnd]
            if e.cost and e.cost > 0 then
                lvlCost = lvlCost + e.cost
            else
                lvlMissing = true
            end
            groupEnd = groupEnd + 1
        end
        local lastInGroup = groupEnd - 1
        local count = lastInGroup - idx + 1
        local rightHdr = (lvlCost > 0 and not lvlMissing) and FormatMoney(lvlCost)
            or string_format("%d %s", count, count == 1 and "spell" or "spells")
        EnsureSpace(0)
        AppendGroup(string_format("level %d", lvl), rightHdr, false, idx, lastInGroup)
        idx = groupEnd
    end

    return sbPools.usedBuckets
end

local function RenderSingleSbBucket(parentView, bucket, useParchment, themePal, playerMoney)
    if not parentView or not bucket then return end
    local inkR, inkG, inkB = GetSpellBookInkRGB()
    local dim = themePal.dimTextColor or COLORS.DIM
    local accent = themePal.accentColor or (sfui.config and sfui.config.spec_color) or COLORS.ACCENT_FALLBACK

    for i = 1, #bucket.items do
        local item = bucket.items[i]
        if item.isHeader then
            local hdr = AcquireSbHeader(parentView)
            hdr:ClearAllPoints()
            hdr:SetPoint("TOPLEFT", parentView, "TOPLEFT", 0, item.y)
            hdr:SetPoint("TOPRIGHT", parentView, "TOPRIGHT", 0, item.y)
            hdr.titleFs:SetText(item.title)

            if useParchment then
                if item.useReadyColor then
                    hdr.titleFs:SetTextColor(PARCHMENT.READY[1], PARCHMENT.READY[2], PARCHMENT.READY[3], 1.0)
                else
                    hdr.titleFs:SetTextColor(inkR, inkG, inkB, 1.0)
                end
                hdr.rightFs:SetTextColor(PARCHMENT.INK_DIM[1], PARCHMENT.INK_DIM[2], PARCHMENT.INK_DIM[3], 1.0)
                if HasAtlas("spellbook-divider") then
                    hdr.divider:SetAtlas("spellbook-divider", false)
                    hdr.divider:ClearAllPoints()
                    hdr.divider:SetHeight(8)
                    hdr.divider:SetPoint("BOTTOMLEFT", hdr, "BOTTOMLEFT", 0, -2)
                    hdr.divider:SetPoint("BOTTOMRIGHT", hdr, "BOTTOMRIGHT", 0, -2)
                    hdr.divider:SetAlpha(0.8)
                else
                    hdr.divider:SetColorTexture(0.38, 0.25, 0.13, 0.45)
                    hdr.divider:ClearAllPoints()
                    hdr.divider:SetHeight(1)
                    hdr.divider:SetPoint("BOTTOMLEFT", hdr, "BOTTOMLEFT", 0, 0)
                    hdr.divider:SetPoint("BOTTOMRIGHT", hdr, "BOTTOMRIGHT", 0, 0)
                end
            else
                if item.useReadyColor then
                    hdr.titleFs:SetTextColor(COLORS.READY[1], COLORS.READY[2], COLORS.READY[3], 1.0)
                else
                    hdr.titleFs:SetTextColor(accent[1] or 0.4, accent[2] or 0.8, accent[3] or 1.0, 1.0)
                end
                hdr.rightFs:SetTextColor(dim[1], dim[2], dim[3], 1.0)
                hdr.divider:SetColorTexture(0.28, 0.28, 0.32, 0.75)
                hdr.divider:ClearAllPoints()
                hdr.divider:SetHeight(1)
                hdr.divider:SetPoint("BOTTOMLEFT", hdr, "BOTTOMLEFT", 0, 0)
                hdr.divider:SetPoint("BOTTOMRIGHT", hdr, "BOTTOMRIGHT", 0, 0)
            end

            hdr.rightFs:SetText(item.rightText or "")
            hdr:Show()
        else
            local entry = item.entry
            local card = AcquireSbCard(parentView)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", parentView, "TOPLEFT", item.x, item.y)
            card.entryData = entry

            if useParchment and HasAtlas("spellbook-item-backplate") then
                card.backplate:SetAtlas("spellbook-item-backplate", false)
                card.defaultBackplateAlpha = entry.isReady and 0.34 or 0.22
                card.hoverBackplateAlpha = 0.82
                card.backplate:SetAlpha(card.defaultBackplateAlpha)
            elseif useParchment then
                card.backplate:SetColorTexture(0.26, 0.16, 0.08, 1.0)
                card.defaultBackplateAlpha = 0.10
                card.hoverBackplateAlpha = 0.24
                card.backplate:SetAlpha(card.defaultBackplateAlpha)
            else
                card.backplate:SetColorTexture(1, 1, 1, 1)
                card.defaultBackplateAlpha = 0.04
                card.hoverBackplateAlpha = 0.12
                card.backplate:SetAlpha(card.defaultBackplateAlpha)
            end

            card.icon:SetTexture(entry.icon or BOOK_ICON)
            if card.iconMask then
                local maskAtlas = entry.isPassive and "talents-node-circle-mask" or "spellbook-item-spellicon-mask"
                if HasAtlas(maskAtlas) then
                    card.iconMask:SetAtlas(maskAtlas, false)
                end
            end

            card.trainableShadow:SetShown(entry.isReady)
            if entry.isReady then
                card.icon:SetDesaturated(false)
                card.icon:SetVertexColor(1, 1, 1)
                card.icon:SetAlpha(1.0)
            else
                card.icon:SetDesaturated(true)
                card.icon:SetVertexColor(0.88, 0.84, 0.78)
                card.icon:SetAlpha(0.72)
            end

            local bdr = card.iconBorder
            bdr:ClearAllPoints()
            if entry.isPassive then
                local pAtlas = entry.isReady and "talents-node-circle-gray" or "spellbook-item-iconframe-passive-inactive"
                if HasAtlas(pAtlas) then
                    bdr:SetAtlas(pAtlas, false)
                    bdr:SetPoint("TOPLEFT", card.iconHolder, "TOPLEFT", 0, 0)
                    bdr:SetPoint("BOTTOMRIGHT", card.iconHolder, "BOTTOMRIGHT", 0, 0)
                    bdr:Show()
                else
                    bdr:Hide()
                end
            else
                local sAtlas = entry.isReady and "spellbook-item-iconframe" or "spellbook-item-iconframe-inactive"
                if HasAtlas(sAtlas) then
                    bdr:SetAtlas(sAtlas, false)
                    if entry.isReady then
                        bdr:SetPoint("TOPLEFT", card.iconHolder, "TOPLEFT", -9, 1)
                        bdr:SetPoint("BOTTOMRIGHT", card.iconHolder, "BOTTOMRIGHT", 1, -6)
                    else
                        bdr:SetPoint("TOPLEFT", card.iconHolder, "TOPLEFT", -8, 1)
                        bdr:SetPoint("BOTTOMRIGHT", card.iconHolder, "BOTTOMRIGHT", 2, -4)
                    end
                    bdr:Show()
                else
                    bdr:Hide()
                end
            end

            local subColorHex = useParchment and "6e563f" or "808088"
            local titleStr = entry.lowerName
            if entry.compactSub and entry.compactSub ~= "" then
                titleStr = string_format("%s |cff%s%s|r", entry.lowerName, subColorHex, entry.compactSub)
            end
            card.nameFs:SetText(titleStr)

            if useParchment then
                if entry.isReady then
                    card.nameFs:SetTextColor(0.15, 0.09, 0.04, 1.0)
                else
                    card.nameFs:SetTextColor(PARCHMENT.INK_UPCOMING[1], PARCHMENT.INK_UPCOMING[2], PARCHMENT.INK_UPCOMING[3], 1.0)
                end
            else
                if entry.isReady then
                    card.nameFs:SetTextColor(1.0, 1.0, 1.0, 1.0)
                else
                    card.nameFs:SetTextColor(COLORS.UPCOMING[1], COLORS.UPCOMING[2], COLORS.UPCOMING[3], 0.92)
                end
            end

            if entry.cost and entry.cost > 0 then
                card.costFs:SetText(FormatMoney(entry.cost) or "")
                local unaffordable = entry.isReady and (playerMoney < entry.cost)
                if unaffordable then
                    local rc = useParchment and PARCHMENT.RED or COLORS.RED
                    card.costFs:SetTextColor(rc[1], rc[2], rc[3], 1.0)
                elseif useParchment then
                    card.costFs:SetTextColor(inkR, inkG, inkB, 1.0)
                else
                    card.costFs:SetTextColor(1.0, 1.0, 1.0, 1.0)
                end
            else
                card.costFs:SetText("")
            end

            local catSuffix = (entry.category and entry.category ~= "") and (" - " .. entry.category) or ""
            if entry.isReady then
                card.metaFs:SetText("ready" .. catSuffix)
                local gc = useParchment and PARCHMENT.READY or COLORS.READY
                card.metaFs:SetTextColor(gc[1], gc[2], gc[3], 1.0)
            else
                card.metaFs:SetText(string_format("lv %d%s", entry.levelLearned, catSuffix))
                local dc = useParchment and PARCHMENT.INK_DIM or dim
                card.metaFs:SetTextColor(dc[1], dc[2], dc[3], 1.0)
            end

            card:Show()
        end
    end
end

RenderSpellBookTrainerPage = function()
    if not sbPageFrame or not sbPageFrame:IsShown() then return end

    EnsureCatalogFresh()
    SyncSpellBookPageArt()
    SyncActiveNativeTabMask()

    local useParchment = sbPageFrame.useParchment
    local isMinimized = sbPageFrame.isMinimized
    local themePal = (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()) or EMPTY_PALETTE
    local playerMoney = (GetMoney and GetMoney()) or 0
    if issecretvalue(playerMoney) or type(playerMoney) ~= "number" then playerMoney = 0 end

    RebuildFilteredEntries(sbSearchText, sbFilteredEntries)

    -- Update filter pills & spec pill
    local pills = sbPageFrame.filterButtons
    if pills then
        if pills.ready and pills.ready.fs then
            pills.ready.fs:SetText(string_format("ready (%d)", summary.readyCount))
            StyleSpellBookPill(pills.ready, filterMode == "ready", summary.readyCount > 0, useParchment)
        end
        if pills.upcoming and pills.upcoming.fs then
            pills.upcoming.fs:SetText(string_format("future (%d)", summary.upcomingCount))
            StyleSpellBookPill(pills.upcoming, filterMode == "upcoming", false, useParchment)
        end
        if pills.all and pills.all.fs then
            pills.all.fs:SetText(string_format("all (%d)", summary.totalCount))
            StyleSpellBookPill(pills.all, filterMode == "all", false, useParchment)
        end
    end
    local specBtn = sbPageFrame.specButton
    if specBtn and specBtn.fs then
        if activeSpecFilter then
            specBtn.fs:SetText(activeSpecFilter)
            StyleSpellBookPill(specBtn, true, false, useParchment)
        else
            specBtn.fs:SetText("spec: all")
            StyleSpellBookPill(specBtn, false, false, useParchment)
        end
    end

    local inkR, inkG, inkB = GetSpellBookInkRGB()
    local dim = themePal.dimTextColor or COLORS.DIM

    if sbPageFrame.statusTopRight then
        if summary.readyCount > 0 then
            sbPageFrame.statusTopRight:SetText(string_format("%s - %d ready to train", summary.className, summary.readyCount))
            local gc = useParchment and PARCHMENT.READY or COLORS.READY
            sbPageFrame.statusTopRight:SetTextColor(gc[1], gc[2], gc[3], 1.0)
        elseif summary.nextLevel then
            sbPageFrame.statusTopRight:SetText(string_format("%s - next unlock lv %d", summary.className, summary.nextLevel))
            local dc = useParchment and PARCHMENT.INK_DIM or dim
            sbPageFrame.statusTopRight:SetTextColor(dc[1], dc[2], dc[3], 1.0)
        else
            sbPageFrame.statusTopRight:SetText(string_format("%s - all class spells learned", summary.className))
            local dc = useParchment and PARCHMENT.INK_DIM or dim
            sbPageFrame.statusTopRight:SetTextColor(dc[1], dc[2], dc[3], 1.0)
        end
    end

    sbPools.activeHeaders = 0
    sbPools.activeCards = 0

    local numBuckets = BuildSpellBookViewBuckets()
    local viewsPerSpread = isMinimized and 1 or 2
    spellBookMaxPages = math_max(1, math_ceil(numBuckets / viewsPerSpread))
    if spellBookCurrentPage > spellBookMaxPages then
        spellBookCurrentPage = spellBookMaxPages
    elseif spellBookCurrentPage < 1 then
        spellBookCurrentPage = 1
    end

    if numBuckets == 0 then
        if sbPageFrame.emptyText then
            if sbSearchText ~= "" or activeSpecFilter then
                sbPageFrame.emptyText:SetText("no matching trainer spells")
            elseif filterMode == "ready" then
                sbPageFrame.emptyText:SetText("no spells ready to train")
            elseif filterMode == "upcoming" then
                sbPageFrame.emptyText:SetText("no upcoming class spells")
            else
                sbPageFrame.emptyText:SetText("all class spells learned")
            end
            local dc = useParchment and PARCHMENT.INK_DIM or dim
            sbPageFrame.emptyText:SetTextColor(dc[1], dc[2], dc[3], 1.0)
            sbPageFrame.emptyText:ClearAllPoints()
            sbPageFrame.emptyText:SetPoint("CENTER", sbPageFrame.view1, "CENTER", 0, 10)
            sbPageFrame.emptyText:Show()
        end
    else
        if sbPageFrame.emptyText then
            sbPageFrame.emptyText:Hide()
        end
        local firstBucketIdx = (spellBookCurrentPage - 1) * viewsPerSpread + 1
        RenderSingleSbBucket(sbPageFrame.view1, sbPools.buckets[firstBucketIdx], useParchment, themePal, playerMoney)
        if not isMinimized and sbPools.buckets[firstBucketIdx + 1] then
            RenderSingleSbBucket(sbPageFrame.view2, sbPools.buckets[firstBucketIdx + 1], useParchment, themePal, playerMoney)
        end
    end

    for i = sbPools.activeHeaders + 1, #sbPools.headers do
        sbPools.headers[i]:Hide()
    end
    for i = sbPools.activeCards + 1, #sbPools.cards do
        sbPools.cards[i]:Hide()
    end

    -- Footer summary & paging controls
    if sbPageFrame.footerLeft then
        local footerParts = string_format("%d shown", #sbFilteredEntries)
        if summary.readyCount > 0 and summary.readyCost > 0 then
            footerParts = string_format("%s   |   ready: %s", footerParts, FormatMoney(summary.readyCost) or "")
            if playerMoney < summary.readyCost then
                local rc = useParchment and PARCHMENT.RED or COLORS.RED
                sbPageFrame.footerLeft:SetTextColor(rc[1], rc[2], rc[3], 1.0)
            elseif useParchment then
                sbPageFrame.footerLeft:SetTextColor(inkR, inkG, inkB, 1.0)
            else
                sbPageFrame.footerLeft:SetTextColor(1, 1, 1, 1)
            end
        else
            if summary.readyCount > 0 then
                footerParts = footerParts .. "   |   visit class trainer for prices"
            elseif filterMode == "upcoming" and summary.upcomingCost > 0 then
                footerParts = string_format("%s   |   total: %s", footerParts, FormatMoney(summary.upcomingCost) or "")
            end
            local dc = useParchment and PARCHMENT.INK_DIM or dim
            sbPageFrame.footerLeft:SetTextColor(dc[1], dc[2], dc[3], 1.0)
        end
        sbPageFrame.footerLeft:SetText(footerParts)
    end

    if sbPageFrame.pageText then
        sbPageFrame.pageText:SetText(string_format("page %d / %d", spellBookCurrentPage, spellBookMaxPages))
        if useParchment then
            sbPageFrame.pageText:SetTextColor(inkR, inkG, inkB, 1.0)
        else
            sbPageFrame.pageText:SetTextColor(dim[1], dim[2], dim[3], 1.0)
        end
    end
    if sbPageFrame.prevBtn then
        sbPageFrame.prevBtn:SetEnabled(spellBookCurrentPage > 1)
    end
    if sbPageFrame.nextBtn then
        sbPageFrame.nextBtn:SetEnabled(spellBookCurrentPage < spellBookMaxPages)
    end
    if sbPageFrame.pagingFrame then
        sbPageFrame.pagingFrame:SetShown(spellBookMaxPages > 1 or #sbFilteredEntries > 0)
    end
end

UpdateSpellBookTabVisual = function()
    if not sbTabBtn then return end
    local psf = _G.PlayerSpellsFrame
    local inspecting = psf and psf.IsInspecting and psf:IsInspecting()
    if inspecting then
        sbTabBtn:Hide()
        return
    end

    local sbf = psf and psf.SpellBookFrame
    if sbf and sbf.CategoryTabSystem then
        local anchorTarget = (sbf.NextCategoryIcon and sbf.NextCategoryIcon:IsShown()) and sbf.NextCategoryIcon or sbf.CategoryTabSystem
        if sbTabBtn.currentAnchor ~= anchorTarget then
            sbTabBtn.currentAnchor = anchorTarget
            sbTabBtn:ClearAllPoints()
            sbTabBtn:SetPoint("LEFT", anchorTarget, "RIGHT", 1, 0)
        end
    end
    sbTabBtn:Show()

    local selected = isSpellBookTrainerTabActive and true or false
    if sbTabBtn.squareBg then
        sbTabBtn.squareBg:SetShown(not selected)
    end
    if sbTabBtn.squareBgActive then
        sbTabBtn.squareBgActive:SetShown(selected)
    end
    if sbTabBtn.squareBgActiveGlow then
        sbTabBtn.squareBgActiveGlow:SetShown(selected)
    end

    local ready = summary.readyCount or 0
    if sbTabBtn.badge then
        if ready > 0 then
            sbTabBtn.badge:SetText(ready > 99 and "99+" or tostring(ready))
            sbTabBtn.badge:Show()
        else
            sbTabBtn.badge:SetText("")
            sbTabBtn.badge:Hide()
        end
    end
end

SetSpellBookTrainerTabActive = function(active)
    if active and IsInCombat() then
        active = false
    end
    isSpellBookTrainerTabActive = active and true or false

    if isSpellBookTrainerTabActive then
        if IsForeverSpellBookVisible() and sbPageFrame then
            sbPageFrame:Show()
            RenderSpellBookTrainerPage()
        end
    else
        maskedNativeTabID = nil
        RestoreMaskedNativeTabAlpha()
        if sbPageFrame then
            if sbPageFrame.searchBox and sbPageFrame.searchBox:HasFocus() then
                sbPageFrame.searchBox:ClearFocus()
            end
            if sbPageFrame.activeTabMaskBtn then
                sbPageFrame.activeTabMaskBtn:Hide()
            end
            sbPageFrame:Hide()
        end
    end

    UpdateSpellBookTabVisual()
end

local function ChangeSpellBookTrainerPage(delta)
    local newPage = math_min(spellBookMaxPages, math_max(1, spellBookCurrentPage + delta))
    if newPage ~= spellBookCurrentPage then
        spellBookCurrentPage = newPage
        PlaySoundSafe(_G.SOUNDKIT and _G.SOUNDKIT.IG_ABILITY_PAGE_TURN)
        RenderSpellBookTrainerPage()
    end
end

local function CreateSpellBookTrainerPage(sbf)
    if sbPageFrame or not sbf then return sbPageFrame end

    local baseLevel = (sbf.PagedSpellsFrame and sbf.PagedSpellsFrame.GetFrameLevel and sbf.PagedSpellsFrame:GetFrameLevel()) or 101
    local page = CreateFrame("Frame", "SfuiSpellBookTrainerPage", sbf)
    page:Hide()
    page:SetPoint("TOPLEFT", sbf, "TOPLEFT", 0, -60)
    page:SetPoint("BOTTOMRIGHT", sbf, "BOTTOMRIGHT", 0, 0)
    page:SetFrameLevel(baseLevel + 25)
    page:EnableMouse(true)
    page:EnableMouseWheel(true)
    page:SetScript("OnMouseWheel", function(_, delta)
        if delta > 0 then
            ChangeSpellBookTrainerPage(-1)
        elseif delta < 0 then
            ChangeSpellBookTrainerPage(1)
        end
    end)
    sbPageFrame = page

    -- Clipped background matching SpellBookFrame's exact parchment atlases & anchors
    local bgClip = CreateFrame("Frame", nil, page)
    bgClip:SetAllPoints(page)
    bgClip:SetFrameLevel(page:GetFrameLevel())
    if bgClip.SetClipsChildren then
        bgClip:SetClipsChildren(true)
    end
    page.bgClip = bgClip

    local darkFallback = bgClip:CreateTexture(nil, "BACKGROUND", nil, 0)
    darkFallback:SetAllPoints(page)
    darkFallback:SetColorTexture(0.06, 0.06, 0.08, 0.97)
    darkFallback:Hide()
    page.darkFallbackBg = darkFallback

    if HasAtlas("spellbook-Page-Right-C60") then
        local bgHalved = bgClip:CreateTexture(nil, "BACKGROUND", nil, 1)
        bgHalved:SetAtlas("spellbook-Page-Right-C60", false)
        bgHalved:SetPoint("TOPLEFT", sbf, "TOPLEFT", 0, 0)
        bgHalved:SetPoint("BOTTOMRIGHT", sbf, "BOTTOMRIGHT", 0, 0)
        page.bgHalved = bgHalved

        local bgRight = bgClip:CreateTexture(nil, "BACKGROUND", nil, 1)
        bgRight:SetAtlas("spellbook-Page-Right-C60", false)
        bgRight:SetPoint("TOPLEFT", sbf, "TOP", 0, 0)
        bgRight:SetPoint("BOTTOMRIGHT", sbf, "BOTTOMRIGHT", 0, 0)
        page.bgRight = bgRight
    end
    if HasAtlas("spellbook-Page-Left-C60") then
        local bgLeft = bgClip:CreateTexture(nil, "BACKGROUND", nil, 1)
        bgLeft:SetAtlas("spellbook-Page-Left-C60", false)
        bgLeft:SetPoint("TOPLEFT", sbf, "TOPLEFT", 0, 0)
        bgLeft:SetPoint("BOTTOMRIGHT", sbf, "BOTTOM", 0, 0)
        page.bgLeft = bgLeft
    end

    -- Non-tainting click/visual mask over whichever native CategoryTabSystem tab was selected
    local maskBtn = CreateFrame("Button", nil, page)
    maskBtn:Hide()
    maskBtn:RegisterForClicks("LeftButtonUp")

    local maskBack = maskBtn:CreateTexture(nil, "BACKGROUND")
    maskBack:SetSize(36, 35)
    maskBack:SetPoint("BOTTOM", maskBtn, "BOTTOM", 0, 0)
    maskBack:SetPoint("CENTER", maskBtn, "CENTER", 0, 0)
    maskBack:SetColorTexture(0.08, 0.06, 0.05, 1)

    local maskIcon = maskBtn:CreateTexture(nil, "ARTWORK", nil, 0)
    maskIcon:SetSize(36, 35)
    maskIcon:SetPoint("BOTTOM", maskBtn, "BOTTOM", 0, 0)
    maskIcon:SetPoint("CENTER", maskBtn, "CENTER", 0, 0)
    maskBtn.icon = maskIcon

    local maskHl = maskBtn:CreateTexture(nil, "HIGHLIGHT")
    maskHl:SetAllPoints(maskIcon)
    maskHl:SetColorTexture(1, 1, 1, 0.16)
    maskHl:SetBlendMode("ADD")

    if maskBtn.CreateMaskTexture and HasAtlas("SquareMask") then
        local sqMask = maskBtn:CreateMaskTexture(nil, "ARTWORK")
        sqMask:SetAtlas("SquareMask", false)
        sqMask:SetPoint("TOPLEFT", maskIcon, "TOPLEFT", 0, -2)
        sqMask:SetPoint("BOTTOMRIGHT", maskIcon, "BOTTOMRIGHT", -2, 0)
        maskBack:AddMaskTexture(sqMask)
        maskIcon:AddMaskTexture(sqMask)
        maskHl:AddMaskTexture(sqMask)
    else
        maskIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    if HasAtlas("spellbook-Tab-Frame-C60") then
        local maskFrame = maskBtn:CreateTexture(nil, "ARTWORK", nil, 1)
        maskFrame:SetAtlas("spellbook-Tab-Frame-C60", true)
        maskFrame:SetPoint("BOTTOM", maskBtn, "BOTTOM", 0, 1)
    end

    maskBtn:SetScript("OnClick", function()
        PlaySoundSafe(_G.SOUNDKIT and _G.SOUNDKIT.IG_SPELLBOOK_OPEN)
        SetSpellBookTrainerTabActive(false)
    end)
    maskBtn:SetScript("OnEnter", function(self)
        if not self.nativeTooltipText or self.nativeTooltipText == "" then return end
        local tip = common and common.get_tooltip and common.get_tooltip()
        if not tip then return end
        tip:SetOwner(self, "ANCHOR_RIGHT", -12, -6)
        tip:ClearLines()
        tip:AddLine(self.nativeTooltipText, 1, 0.82, 0)
        tip:Show()
    end)
    maskBtn:SetScript("OnLeave", function()
        if common and common.hide_tooltip then common.hide_tooltip() end
    end)
    page.activeTabMaskBtn = maskBtn

    -- Top Filter Strip (Left Page Margin: x = 85..533, y = -6)
    page.filterButtons = {}
    local pillWidths = { ready = 72, upcoming = 76, all = 64 }
    local prevPill = nil
    for _, key in ipairs(FILTER_KEYS) do
        local btn = CreateFrame("Button", nil, page, "BackdropTemplate")
        btn:SetSize(pillWidths[key] or 70, 20)
        btn:SetFrameLevel(page:GetFrameLevel() + 4)
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
        fs:SetWordWrap(false)
        btn.fs = fs
        if btn.SetFontString then btn:SetFontString(fs) end

        if not prevPill then
            btn:SetPoint("TOPLEFT", page, "TOPLEFT", 85, -6)
        else
            btn:SetPoint("LEFT", prevPill, "RIGHT", 4, 0)
        end
        prevPill = btn
        page.filterButtons[key] = btn

        btn:SetScript("OnClick", function()
            SelectFilterMode(key)
        end)
    end

    local specBtn = CreateFrame("Button", nil, page, "BackdropTemplate")
    specBtn:SetSize(84, 20)
    specBtn:SetPoint("LEFT", prevPill, "RIGHT", 4, 0)
    specBtn:SetFrameLevel(page:GetFrameLevel() + 4)
    specBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local specFs = specBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    specFs:SetPoint("CENTER", specBtn, "CENTER", 0, 0)
    specFs:SetWidth(76)
    specFs:SetWordWrap(false)
    specBtn.fs = specFs
    if specBtn.SetFontString then specBtn:SetFontString(specFs) end
    page.specButton = specBtn

    specBtn:SetScript("OnClick", function(_, button)
        CycleSpecFilter(button)
    end)
    specBtn:SetScript("OnEnter", function(self)
        local tip = common and common.get_tooltip and common.get_tooltip()
        if not tip then return end
        tip:SetOwner(self, "ANCHOR_TOP")
        tip:ClearLines()
        tip:AddLine("tree filter", 1, 1, 1)
        tip:AddLine("left-click to cycle specialization trees.", 0.8, 0.8, 0.8, true)
        tip:AddLine("right-click to reset to all trees.", 0.65, 0.65, 0.68, true)
        tip:Show()
    end)
    specBtn:SetScript("OnLeave", function()
        if common and common.hide_tooltip then common.hide_tooltip() end
    end)

    local statusTopRight = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusTopRight:SetPoint("TOPLEFT", page, "TOPLEFT", 650, -10)
    statusTopRight:SetJustifyH("LEFT")
    statusTopRight:SetWordWrap(false)
    page.statusTopRight = statusTopRight

    local sbSearch = CreateFrame("EditBox", nil, page, "BackdropTemplate")
    sbSearch:SetHeight(20)
    sbSearch:SetFrameLevel(page:GetFrameLevel() + 4)
    sbSearch:SetAutoFocus(false)
    sbSearch:SetFontObject("GameFontHighlightSmall")
    sbSearch:SetTextInsets(6, 18, 0, 0)
    page.searchBox = sbSearch

    local placeholder = sbSearch:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", sbSearch, "LEFT", 6, 0)
    placeholder:SetText("search trainer...")
    page.searchPlaceholder = placeholder

    local clearBtn = CreateFrame("Button", nil, sbSearch)
    clearBtn:SetSize(14, 14)
    clearBtn:SetPoint("RIGHT", sbSearch, "RIGHT", -3, 0)
    local clearFs = clearBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    clearFs:SetPoint("CENTER", clearBtn, "CENTER", 0, 0)
    clearFs:SetText("x")
    clearFs:SetTextColor(0.55, 0.45, 0.35, 1)
    clearBtn:Hide()
    clearBtn:SetScript("OnClick", function()
        sbSearch:SetText("")
        sbSearch:ClearFocus()
    end)

    sbSearch:SetScript("OnTextChanged", function(self)
        local txt = (self:GetText() or ""):match("^%s*(.-)%s*$") or ""
        placeholder:SetShown(txt == "")
        clearBtn:SetShown(txt ~= "")
        if sbSearchText ~= txt then
            sbSearchText = txt
            spellBookCurrentPage = 1
            if page:IsShown() then
                RenderSpellBookTrainerPage()
            end
        end
    end)
    sbSearch:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    sbSearch:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    -- Left & Right Spellbook Page Views (matching Blizzard PagedSpellsView1/2Template coordinates)
    local view1 = CreateFrame("Frame", nil, page)
    view1:SetSize(SB_LAYOUT.VIEW_WIDTH, SB_LAYOUT.VIEW_HEIGHT)
    view1:SetPoint("TOPLEFT", page, "TOPLEFT", 85, -34)
    view1:SetFrameLevel(page:GetFrameLevel() + 2)
    page.view1 = view1

    local view2 = CreateFrame("Frame", nil, page)
    view2:SetSize(SB_LAYOUT.VIEW_WIDTH, SB_LAYOUT.VIEW_HEIGHT)
    view2:SetPoint("TOPRIGHT", page, "TOPRIGHT", -50, -34)
    view2:SetFrameLevel(page:GetFrameLevel() + 2)
    page.view2 = view2

    statusTopRight:ClearAllPoints()
    statusTopRight:SetPoint("BOTTOMLEFT", view2, "TOPLEFT", 0, 10)

    local emptyText = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyText:SetPoint("CENTER", view1, "CENTER", 0, 10)
    emptyText:SetJustifyH("CENTER")
    emptyText:Hide()
    page.emptyText = emptyText

    -- Bottom Footer & Native Spellbook Paging Controls
    local footerLeft = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footerLeft:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 85, 42)
    footerLeft:SetJustifyH("LEFT")
    footerLeft:SetWordWrap(false)
    page.footerLeft = footerLeft

    local pagingFrame = CreateFrame("Frame", nil, page)
    pagingFrame:SetSize(160, 32)
    pagingFrame:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -68, 30)
    pagingFrame:SetFrameLevel(page:GetFrameLevel() + 4)
    page.pagingFrame = pagingFrame

    local nextBtn = CreateFrame("Button", nil, pagingFrame)
    nextBtn:SetSize(28, 28)
    nextBtn:SetPoint("RIGHT", pagingFrame, "RIGHT", 0, 0)
    nextBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    nextBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    nextBtn:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled")
    nextBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    nextBtn:SetScript("OnClick", function()
        ChangeSpellBookTrainerPage(1)
    end)
    page.nextBtn = nextBtn

    local prevBtn = CreateFrame("Button", nil, pagingFrame)
    prevBtn:SetSize(28, 28)
    prevBtn:SetPoint("RIGHT", nextBtn, "LEFT", -4, 0)
    prevBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    prevBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
    prevBtn:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled")
    prevBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    prevBtn:SetScript("OnClick", function()
        ChangeSpellBookTrainerPage(-1)
    end)
    page.prevBtn = prevBtn

    local pageText = pagingFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pageText:SetPoint("RIGHT", prevBtn, "LEFT", -8, 0)
    pageText:SetJustifyH("RIGHT")
    pageText:SetWordWrap(false)
    page.pageText = pageText

    return page
end

local function CreateSpellBookTrainerTab(sbf)
    if sbTabBtn or not sbf or not sbf.CategoryTabSystem then return sbTabBtn end

    local tabBtn = CreateFrame("Button", "SfuiSpellBookTrainerTab", sbf)
    tabBtn:SetSize(44, 32)
    tabBtn:SetFrameLevel((sbf.CategoryTabSystem:GetFrameLevel() or 101) + 2)
    tabBtn:RegisterForClicks("LeftButtonUp")
    tabBtn:SetPoint("LEFT", sbf.CategoryTabSystem, "RIGHT", 1, 0)
    tabBtn.currentAnchor = sbf.CategoryTabSystem

    local icon = tabBtn:CreateTexture(nil, "ARTWORK", nil, 0)
    icon:SetSize(36, 35)
    icon:SetPoint("BOTTOM", tabBtn, "BOTTOM", 0, 0)
    icon:SetPoint("CENTER", tabBtn, "CENTER", 0, 0)
    icon:SetTexture(BOOK_ICON)
    tabBtn.icon = icon

    local hl = tabBtn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(icon)
    hl:SetColorTexture(1, 1, 1, 0.16)
    hl:SetBlendMode("ADD")

    if tabBtn.CreateMaskTexture and HasAtlas("SquareMask") then
        local iconMask = tabBtn:CreateMaskTexture(nil, "ARTWORK")
        iconMask:SetAtlas("SquareMask", false)
        iconMask:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, -2)
        iconMask:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 0)
        icon:AddMaskTexture(iconMask)
        hl:AddMaskTexture(iconMask)
        tabBtn.iconMask = iconMask
    else
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    if HasAtlas("spellbook-Tab-Frame-C60") then
        local sqBg = tabBtn:CreateTexture(nil, "ARTWORK", nil, 1)
        sqBg:SetAtlas("spellbook-Tab-Frame-C60", true)
        sqBg:SetPoint("BOTTOM", tabBtn, "BOTTOM", 0, 1)
        tabBtn.squareBg = sqBg
    end
    if HasAtlas("spellbook-Tab-Frame-Glow-C60") then
        local sqActive = tabBtn:CreateTexture(nil, "ARTWORK", nil, 1)
        sqActive:SetAtlas("spellbook-Tab-Frame-Glow-C60", true)
        sqActive:SetPoint("BOTTOM", tabBtn, "BOTTOM", 0, 1)
        sqActive:Hide()
        tabBtn.squareBgActive = sqActive
    end
    if HasAtlas("spellbook-Tab-Frame-glow-gradient-C60") then
        local sqGlow = tabBtn:CreateTexture(nil, "ARTWORK", nil, 1)
        sqGlow:SetAtlas("spellbook-Tab-Frame-glow-gradient-C60", true)
        sqGlow:SetPoint("BOTTOM", tabBtn, "BOTTOM", 0, 0)
        sqGlow:Hide()
        tabBtn.squareBgActiveGlow = sqGlow
    end

    local badge = tabBtn:CreateFontString(nil, "OVERLAY")
    local fontFile = (common and common.get_font_file and common.get_font_file()) or "Fonts\\FRIZQT__.TTF"
    badge:SetFont(fontFile, 10, "OUTLINE")
    badge:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 2)
    badge:SetTextColor(COLORS.READY[1], COLORS.READY[2], COLORS.READY[3], 1.0)
    badge:Hide()
    tabBtn.badge = badge

    tabBtn:SetScript("OnClick", function()
        if IsInCombat() then
            if common and common.print then
                common.print("class trainer tab is unavailable during combat.")
            end
            return
        end
        if not isSpellBookTrainerTabActive then
            PlaySoundSafe(_G.SOUNDKIT and _G.SOUNDKIT.IG_SPELLBOOK_OPEN)
            SetSpellBookTrainerTabActive(true)
        end
    end)

    tabBtn:SetScript("OnEnter", function(self)
        local tip = common and common.get_tooltip and common.get_tooltip()
        if not tip then return end
        tip:SetOwner(self, "ANCHOR_RIGHT", -12, -6)
        tip:ClearLines()
        tip:AddLine("class trainer", 1, 1, 1)
        if IsInCombat() then
            tip:AddLine("paused during combat.", 1.0, 0.4, 0.4, true)
        elseif summary.readyCount > 0 then
            tip:AddLine(string_format("%d %s ready to train now.",
                summary.readyCount, summary.readyCount == 1 and "spell" or "spells"), 0.3, 1.0, 0.3, true)
        elseif summary.nextLevel then
            tip:AddLine(string_format("next spells unlock at level %d.", summary.nextLevel), 0.8, 0.8, 0.8, true)
        else
            tip:AddLine("all class spells learned.", 0.8, 0.8, 0.8, true)
        end
        tip:Show()
    end)
    tabBtn:SetScript("OnLeave", function()
        if common and common.hide_tooltip then common.hide_tooltip() end
    end)

    sbTabBtn = tabBtn
    UpdateSpellBookTabVisual()
    return tabBtn
end

function trainerModule.UpdateValues()
    catalogDirty = true
    EnsureCatalogFresh()
    UpdateAllToggleVisuals()
    RefreshOpenTrainerViews()
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Panel Construction & Theming
-- ─────────────────────────────────────────────────────────────────────────────

local function ApplyTheme(frame, palette)
    if not frame then return end
    palette = palette or (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()) or EMPTY_PALETTE
    local dim = palette.dimTextColor or COLORS.DIM

    if frame.headerBar and sfui.theme and sfui.theme.ApplyHeaderStyle then
        sfui.theme.ApplyHeaderStyle(frame.headerBar, "class trainer")
    end
    if frame.subTitle and summary.readyCount == 0 then
        frame.subTitle:SetTextColor(dim[1], dim[2], dim[3], 1.0)
    end
    if frame.footerLeft then
        frame.footerLeft:SetTextColor(dim[1], dim[2], dim[3], 1.0)
    end
    if frame.closeBtn and sfui.theme and sfui.theme.ApplyCloseButtonStyle then
        sfui.theme.ApplyCloseButtonStyle(frame.closeBtn)
    end
    if frame.searchBox and sfui.theme and sfui.theme.ApplyInputStyle then
        sfui.theme.ApplyInputStyle(frame.searchBox)
    end
    if frame.content and sfui.theme and sfui.theme.ApplyContainerStyle then
        sfui.theme.ApplyContainerStyle(frame.content)
    end
    if frame.scrollFrame and frame.scrollFrame.ScrollBar and common and common.style_scrollbar then
        common.style_scrollbar(frame.scrollFrame.ScrollBar)
    end
    if sfui.theme and sfui.theme.ElevateWindowContents then
        sfui.theme.ElevateWindowContents(frame)
    end
    UpdateAllToggleVisuals()
    if frame:IsShown() then
        trainerModule.RenderView()
    end
end

function trainerModule.CreatePanel()
    if panelFrame then return panelFrame end

    panelFrame = CreateFrame("Frame", "SfuiTrainerPanel", UIParent, "BackdropTemplate")
    panelFrame:Hide()
    panelFrame:SetFrameStrata("HIGH")
    panelFrame:SetFrameLevel(25)
    panelFrame:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panelFrame:SetClampedToScreen(true)
    panelFrame:SetMovable(true)
    panelFrame:EnableMouse(true)
    panelFrame:RegisterForDrag("LeftButton")

    panelFrame:SetScript("OnDragStart", function(self)
        if IsInCombat() then return end
        self:StartMoving()
    end)
    panelFrame:SetScript("OnDragStop", SavePosition)
    panelFrame:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
        UpdateAllToggleVisuals()
    end)

    -- Header Bar
    local headerBar
    if sfui.theme and sfui.theme.CreateWindowHeader then
        headerBar = sfui.theme.CreateWindowHeader(panelFrame, "class trainer", 210)
    else
        headerBar = CreateFrame("Frame", nil, panelFrame)
        headerBar:SetSize(210, 24)
        headerBar:SetPoint("TOP", panelFrame, "TOP", 0, -8)
    end
    panelFrame.headerBar = headerBar

    headerBar:EnableMouse(true)
    headerBar:RegisterForDrag("LeftButton")
    headerBar:SetScript("OnDragStart", function()
        if IsInCombat() then return end
        panelFrame:StartMoving()
    end)
    headerBar:SetScript("OnDragStop", function()
        SavePosition(panelFrame)
    end)
    headerBar:SetScript("OnMouseUp", function(_, button)
        if button ~= "RightButton" or not (IsShiftKeyDown and IsShiftKeyDown()) or IsInCombat() then return end
        if SfuiDB then
            if activeHostKind == "spells" then
                SfuiDB.spellsTrainerPanelPos = nil
            else
                SfuiDB.characterInfoPanelPos = nil
            end
        end
        RestorePosition(panelFrame)
        if common and common.print then
            common.print("class trainer panel position reset to default.")
        end
    end)
    headerBar:SetScript("OnEnter", function(self)
        local tip = common and common.get_tooltip and common.get_tooltip()
        if not tip then return end
        tip:SetOwner(self, "ANCHOR_TOP")
        tip:ClearLines()
        tip:AddLine("class trainer", 1, 1, 1)
        tip:AddLine("shows ready and upcoming class spells and ranks.", 0.8, 0.8, 0.8, true)
        tip:AddLine("visit any class trainer once to cache exact copper prices.", 0.65, 0.65, 0.68, true)
        tip:AddLine("drag to move | shift+right-click to reset position", 0.7, 0.7, 0.7)
        tip:Show()
    end)
    headerBar:SetScript("OnLeave", function()
        if common and common.hide_tooltip then common.hide_tooltip() end
    end)

    -- Close Button
    local closeBtn = CreateFrame("Button", nil, panelFrame, "UIPanelCloseButton")
    panelFrame.closeBtn = closeBtn
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("TOPRIGHT", panelFrame, "TOPRIGHT", -4, -4)
    closeBtn:SetFrameLevel((panelFrame:GetFrameLevel() or 25) + 20)
    closeBtn:SetScript("OnClick", function()
        if SfuiDB then
            if activeHostKind == "spells" then
                SfuiDB.showSpellBookTrainerPanel = false
            else
                SfuiDB.showTrainerInfoPanel = false
            end
            -- If both hosts happen to be open simultaneously, close cleanly rather than jumping
            if _G.CharacterFrame and _G.CharacterFrame:IsShown() and GetVisibleClassicEraHost() then
                SfuiDB.showTrainerInfoPanel = false
                SfuiDB.showSpellBookTrainerPanel = false
            end
        end
        activeHostKind = nil
        activeHostFrame = nil
        panelFrame:Hide()
        UpdateAllToggleVisuals()
    end)
    if sfui.theme and sfui.theme.ApplyCloseButtonStyle then
        sfui.theme.ApplyCloseButtonStyle(closeBtn)
    end

    -- Overlay Frame for Subtitle & Controls
    local overlay = CreateFrame("Frame", nil, panelFrame)
    overlay:SetAllPoints(panelFrame)
    overlay:SetFrameLevel((panelFrame:GetFrameLevel() or 25) + 4)
    overlay:EnableMouse(false)
    panelFrame.overlayFrame = overlay

    local subTitle = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panelFrame.subTitle = subTitle
    subTitle:SetPoint("TOP", headerBar, "BOTTOM", 0, -2)
    subTitle:SetWidth(270)
    subTitle:SetWordWrap(false)
    subTitle:SetJustifyH("CENTER")

    -- Row 1: Filter Pills (ready / future / all)
    local filterRow = CreateFrame("Frame", nil, panelFrame)
    filterRow:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", 8, -48)
    filterRow:SetPoint("TOPRIGHT", panelFrame, "TOPRIGHT", -8, -48)
    filterRow:SetHeight(20)
    filterRow:SetFrameLevel((panelFrame:GetFrameLevel() or 25) + 6)
    panelFrame.filterRow = filterRow
    panelFrame.filterButtons = {}

    local pillWidth = 88
    local prevPill = nil
    for _, key in ipairs(FILTER_KEYS) do
        local btn = CreateFrame("Button", nil, filterRow, "BackdropTemplate")
        btn:SetSize(pillWidth, 20)
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
        fs:SetWordWrap(false)
        btn.fs = fs
        if btn.SetFontString then btn:SetFontString(fs) end

        if not prevPill then
            btn:SetPoint("LEFT", filterRow, "LEFT", 0, 0)
        else
            btn:SetPoint("LEFT", prevPill, "RIGHT", 5, 0)
        end
        prevPill = btn
        panelFrame.filterButtons[key] = btn

        btn:SetScript("OnClick", function()
            SelectFilterMode(key)
        end)
    end

    -- Row 2: Search Box + Spec Cycle Pill
    local searchRow = CreateFrame("Frame", nil, panelFrame)
    searchRow:SetPoint("TOPLEFT", filterRow, "BOTTOMLEFT", 0, -4)
    searchRow:SetPoint("TOPRIGHT", filterRow, "BOTTOMRIGHT", 0, -4)
    searchRow:SetHeight(20)
    searchRow:SetFrameLevel((panelFrame:GetFrameLevel() or 25) + 6)
    panelFrame.searchRow = searchRow

    local specBtn = CreateFrame("Button", nil, searchRow, "BackdropTemplate")
    specBtn:SetSize(84, 20)
    specBtn:SetPoint("RIGHT", searchRow, "RIGHT", 0, 0)
    specBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local specFs = specBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    specFs:SetPoint("CENTER", specBtn, "CENTER", 0, 0)
    specFs:SetWidth(76)
    specFs:SetWordWrap(false)
    specBtn.fs = specFs
    if specBtn.SetFontString then specBtn:SetFontString(specFs) end
    panelFrame.specButton = specBtn

    specBtn:SetScript("OnClick", function(_, button)
        CycleSpecFilter(button)
    end)
    specBtn:SetScript("OnEnter", function(self)
        local tip = common and common.get_tooltip and common.get_tooltip()
        if not tip then return end
        tip:SetOwner(self, "ANCHOR_TOP")
        tip:ClearLines()
        tip:AddLine("tree filter", 1, 1, 1)
        tip:AddLine("left-click to cycle specialization trees.", 0.8, 0.8, 0.8, true)
        tip:AddLine("right-click to reset to all trees.", 0.65, 0.65, 0.68, true)
        tip:Show()
    end)
    specBtn:SetScript("OnLeave", function()
        if common and common.hide_tooltip then common.hide_tooltip() end
    end)

    local sb = CreateFrame("EditBox", nil, searchRow, "BackdropTemplate")
    sb:SetHeight(20)
    sb:SetPoint("TOPLEFT", searchRow, "TOPLEFT", 0, 0)
    sb:SetPoint("BOTTOMRIGHT", specBtn, "BOTTOMLEFT", -5, 0)
    sb:SetAutoFocus(false)
    sb:SetFontObject("GameFontHighlightSmall")
    sb:SetTextInsets(6, 18, 0, 0)
    if sfui.theme and sfui.theme.ApplyInputStyle then
        sfui.theme.ApplyInputStyle(sb)
    elseif common and common.apply_flat_backdrop then
        common.apply_flat_backdrop(sb, { 0.06, 0.06, 0.08, 0.85 }, { 0.22, 0.22, 0.26, 0.8 })
    end
    panelFrame.searchBox = sb

    local placeholder = sb:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", sb, "LEFT", 6, 0)
    placeholder:SetText("search spells, trees...")

    local clearBtn = CreateFrame("Button", nil, sb)
    clearBtn:SetSize(14, 14)
    clearBtn:SetPoint("RIGHT", sb, "RIGHT", -3, 0)
    local clearFs = clearBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    clearFs:SetPoint("CENTER", clearBtn, "CENTER", 0, 0)
    clearFs:SetText("x")
    clearFs:SetTextColor(0.65, 0.65, 0.68, 1)
    clearBtn:Hide()
    clearBtn:SetScript("OnClick", function()
        sb:SetText("")
        sb:ClearFocus()
    end)

    sb:SetScript("OnTextChanged", function(self)
        local txt = (self:GetText() or ""):match("^%s*(.-)%s*$") or ""
        placeholder:SetShown(txt == "")
        clearBtn:SetShown(txt ~= "")
        if drawerSearchText ~= txt then
            drawerSearchText = txt
            if panelFrame.scrollFrame then
                panelFrame.scrollFrame:SetVerticalScroll(0)
            end
            if panelFrame:IsShown() then
                trainerModule.RenderView()
            end
        end
    end)
    sb:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    sb:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    -- Inset Scrollable Content Container
    local content = CreateFrame("Frame", nil, panelFrame, "BackdropTemplate")
    panelFrame.content = content
    content:SetPoint("TOPLEFT", searchRow, "BOTTOMLEFT", 0, -5)
    content:SetPoint("BOTTOMRIGHT", panelFrame, "BOTTOMRIGHT", -8, 22)
    content:SetFrameLevel((panelFrame:GetFrameLevel() or 25) + 2)
    if sfui.theme and sfui.theme.ApplyContainerStyle then
        sfui.theme.ApplyContainerStyle(content)
    end

    local emptyText = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyText:SetPoint("CENTER", content, "CENTER", -6, 0)
    emptyText:SetJustifyH("CENTER")
    emptyText:Hide()
    panelFrame.emptyText = emptyText

    local sf = CreateFrame("ScrollFrame", "SfuiTrainerPanelScroll", content, "UIPanelScrollFrameTemplate")
    panelFrame.scrollFrame = sf
    sf:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -18, 4)
    sf:SetFrameLevel((content:GetFrameLevel() or 27) + 2)
    sf:EnableMouseWheel(true)
    if sf.ScrollBar and common and common.style_scrollbar then
        common.style_scrollbar(sf.ScrollBar)
    end

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(244)
    sc:SetHeight(1)
    sc:SetFrameLevel((sf:GetFrameLevel() or 29) + 1)
    sf:SetScrollChild(sc)
    panelFrame.scrollChild = sc

    -- Footer Status Line
    local footerLeft = overlay:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footerLeft:SetPoint("BOTTOMLEFT", panelFrame, "BOTTOMLEFT", 10, 6)
    footerLeft:SetJustifyH("LEFT")
    panelFrame.footerLeft = footerLeft

    local footerRight = overlay:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footerRight:SetPoint("BOTTOMRIGHT", panelFrame, "BOTTOMRIGHT", -10, 6)
    footerRight:SetJustifyH("RIGHT")
    panelFrame.footerRight = footerRight

    -- Window Theme Registration
    if sfui.theme and sfui.theme.ApplyWindowStyle then
        sfui.theme.ApplyWindowStyle(panelFrame, { cornerBrackets = true })
    end
    if sfui.theme and sfui.theme.RegisterWindow then
        sfui.theme.RegisterWindow(panelFrame, ApplyTheme, { cornerBrackets = true })
    end

    panelFrame:SetScript("OnShow", function(self)
        if IsInCombat() then
            self:Hide()
            return
        end
        RestorePosition(self)
        if sfui.theme and sfui.theme.ElevateWindowContents then
            sfui.theme.ElevateWindowContents(self)
        end
        UpdateAllToggleVisuals()
        trainerModule.RenderView()
    end)

    panelFrame:Hide()
    return panelFrame
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Visibility & Mutual-Exclusion Orchestration
-- ─────────────────────────────────────────────────────────────────────────────

local function HidePanelOnly()
    activeHostKind = nil
    activeHostFrame = nil
    if panelFrame and panelFrame:IsShown() then
        panelFrame:Hide()
    end
    UpdateAllToggleVisuals()
end

local function IsAnyHostOrPanelShown()
    if panelFrame and panelFrame:IsShown() then return true end
    if sbPageFrame and sbPageFrame:IsShown() then return true end
    if _G.CharacterFrame and _G.CharacterFrame:IsShown() then return true end
    if IsForeverSpellBookVisible() then return true end
    if GetVisibleClassicEraHost() ~= nil then return true end
    return false
end

local function SyncVisibility()
    if IsInCombat() then
        HidePanelOnly()
        return
    end

    if IsAnyHostOrPanelShown() then
        EnsureCatalogFresh()
    end

    local kind, host = ResolveDesiredHost()
    if not kind or not host then
        HidePanelOnly()
        return
    end

    -- Enforce mutual exclusion on CharacterFrame
    if kind == "char" then
        if SfuiDB then SfuiDB.showCombatInfoPanel = false end
        if sfui.character and sfui.character.infopanel and sfui.character.infopanel.HidePanel then
            sfui.character.infopanel.HidePanel()
        end
    end

    if not panelFrame then
        trainerModule.CreatePanel()
    end

    local hostChanged = (activeHostKind ~= kind) or (activeHostFrame ~= host)
    activeHostKind = kind
    activeHostFrame = host

    if panelFrame:IsShown() then
        if hostChanged then
            RestorePosition(panelFrame)
        end
        UpdateAllToggleVisuals()
        trainerModule.RenderView()
    else
        panelFrame:Show()
    end
end
trainerModule.SyncVisibility = SyncVisibility

--- Called by frames/character/infopanel.lua when SfuiCharacterInfoPanel is toggled ON.
function trainerModule.OnCombatPanelShown()
    if SfuiDB then
        SfuiDB.showTrainerInfoPanel = false
    end
    if activeHostKind == "char" then
        preferredHost = "spells"
        SyncVisibility()
    else
        UpdateAllToggleVisuals()
    end
end

--- Called by frames/character/infopanel_classic.lua when EngravingFrame toggles on Classic Era.
function trainerModule.OnEngravingToggle()
    if panelFrame and panelFrame:IsShown() and activeHostKind == "char" then
        RestorePosition(panelFrame)
    end
end

local function DoRefresh()
    if IsInCombat() or not IsAnyHostOrPanelShown() then return end
    trainerModule.UpdateValues()
end

local function RequestRefresh()
    catalogDirty = true
    if IsInCombat() or not IsAnyHostOrPanelShown() then return end
    if common and common.debounce then
        common.debounce(DEBOUNCE_KEY, DEBOUNCE_DELAY, DoRefresh)
    else
        DoRefresh()
    end
end
trainerModule.RequestRefresh = RequestRefresh

local function IsAnyTrainerSurfaceShown()
    return (panelFrame and panelFrame:IsShown()) or (sbPageFrame and sbPageFrame:IsShown()) or false
end

local function DoMoneyRefresh()
    if IsInCombat() or not IsAnyTrainerSurfaceShown() then return end
    RefreshOpenTrainerViews()
end

local function OnPlayerMoney()
    if IsInCombat() or not IsAnyTrainerSurfaceShown() then return end
    if common and common.debounce then
        common.debounce(MONEY_DEBOUNCE_KEY, DEBOUNCE_DELAY, DoMoneyRefresh)
    else
        DoMoneyRefresh()
    end
end

local function OnSpellTextUpdate(_, spellID)
    if not spellID or issecretvalue(spellID) or not scratch.requestedSpellLoads[spellID] then
        return
    end
    RequestRefresh()
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Header Toggle Buttons (CharacterFrame & Spellbook / Talents)
-- ─────────────────────────────────────────────────────────────────────────────

local function CreateSquareHeaderButton(name, parent, tooltipContext)
    local btn = CreateFrame("Button", name, parent, "BackdropTemplate")
    btn:SetSize(16, 16)
    btn:SetHitRectInsets(-2, -2, -2, -2)
    btn:SetNormalTexture(BOOK_ICON)
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    if btn:GetNormalTexture() then
        btn:GetNormalTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    local mult = sfui.pixelScale or 1
    btn:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = mult,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    btn:SetBackdropBorderColor(0, 0, 0, 1)

    local badge = btn:CreateFontString(nil, "OVERLAY")
    local fontFile = (common and common.get_font_file and common.get_font_file()) or "Fonts\\FRIZQT__.TTF"
    badge:SetFont(fontFile, 9, "OUTLINE")
    badge:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
    badge:SetTextColor(COLORS.READY[1], COLORS.READY[2], COLORS.READY[3], 1.0)
    badge:Hide()
    btn.badge = badge

    btn:SetScript("OnEnter", function(self)
        local tip = common and common.get_tooltip and common.get_tooltip()
        if not tip then return end
        tip:SetOwner(self, "ANCHOR_RIGHT")
        tip:ClearLines()
        tip:AddLine("class trainer", 1, 1, 1)
        if IsInCombat() then
            tip:AddLine("class trainer panel is paused during combat.", 1.0, 0.4, 0.4, true)
        else
            if summary.readyCount > 0 then
                tip:AddLine(string_format("%d %s ready to train now.",
                    summary.readyCount, summary.readyCount == 1 and "spell" or "spells"), 0.3, 1.0, 0.3, true)
            elseif summary.nextLevel then
                tip:AddLine(string_format("next spells unlock at level %d.", summary.nextLevel), 0.8, 0.8, 0.8, true)
            end
            tip:AddLine(tooltipContext, 0.8, 0.8, 0.8, true)
            tip:AddLine("drag to move | shift+right-click to reset.", 0.65, 0.65, 0.65, true)
        end
        tip:Show()
    end)
    btn:SetScript("OnLeave", function()
        if common and common.hide_tooltip then common.hide_tooltip() end
    end)

    return btn
end

local function AlignCharHeaderButtons()
    if sfui.character and sfui.character.AlignHeaderButtons then
        sfui.character.AlignHeaderButtons()
    end
end

function trainerModule.CreateCharacterToggleButton()
    if charToggleBtn then return charToggleBtn end
    local charFrame = _G.CharacterFrame
    if not charFrame then return nil end

    charToggleBtn = CreateSquareHeaderButton(
        "SfuiTrainerToggleBtn",
        charFrame,
        "click to swap with combat telemetry panel."
    )

    local closeBtn = _G.CharacterFrameCloseButton
    if closeBtn and closeBtn.GetFrameLevel then
        charToggleBtn:SetFrameLevel((closeBtn:GetFrameLevel() or 500) + 5)
    end

    charToggleBtn:SetScript("OnClick", function()
        if IsInCombat() then
            HidePanelOnly()
            if common and common.print then
                common.print("class trainer panel is unavailable during combat.")
            end
            return
        end
        SfuiDB = SfuiDB or {}
        if panelFrame and panelFrame:IsShown() and activeHostKind == "char" then
            SfuiDB.showTrainerInfoPanel = false
            if GetVisibleClassicEraHost() then
                SfuiDB.showSpellBookTrainerPanel = false
            end
            HidePanelOnly()
        else
            preferredHost = "char"
            SfuiDB.showTrainerInfoPanel = true
            SfuiDB.showCombatInfoPanel = false
            if sfui.character and sfui.character.infopanel and sfui.character.infopanel.HidePanel then
                sfui.character.infopanel.HidePanel()
            end
            SyncVisibility()
        end
    end)

    charToggleBtn:HookScript("OnShow", AlignCharHeaderButtons)
    charToggleBtn:HookScript("OnHide", AlignCharHeaderButtons)

    if sfui.character and sfui.character.HookHeaderButtons then
        sfui.character.HookHeaderButtons()
        sfui.character.AlignHeaderButtons()
    end

    return charToggleBtn
end

local function ToggleSpellsHostPanel(hostFrame)
    if IsInCombat() then
        HidePanelOnly()
        if common and common.print then
            common.print("class trainer panel is unavailable during combat.")
        end
        return
    end
    SfuiDB = SfuiDB or {}
    if panelFrame and panelFrame:IsShown() and activeHostKind == "spells" and activeHostFrame == hostFrame then
        SfuiDB.showSpellBookTrainerPanel = false
        if _G.CharacterFrame and _G.CharacterFrame:IsShown() then
            SfuiDB.showTrainerInfoPanel = false
        end
        HidePanelOnly()
    else
        preferredHost = "spells"
        SfuiDB.showSpellBookTrainerPanel = true
        SyncVisibility()
    end
end

local function HookPlayerSpellsFrame()
    if playerSpellsHooked then return end
    local psf = _G.PlayerSpellsFrame
    local sbf = psf and psf.SpellBookFrame
    if not psf or not sbf then return end
    playerSpellsHooked = true

    CreateSpellBookTrainerPage(sbf)
    CreateSpellBookTrainerTab(sbf)

    local function RefreshSpellBookLayout()
        UpdateSpellBookTabVisual()
        if isSpellBookTrainerTabActive and sbPageFrame and sbPageFrame:IsShown() then
            RenderSpellBookTrainerPage()
        end
    end

    sbf:HookScript("OnShow", function()
        EnsureCatalogFresh()
        UpdateSpellBookTabVisual()

        local inspecting = psf.IsInspecting and psf:IsInspecting()
        if isSpellBookTrainerTabActive and not IsInCombat() and not inspecting then
            if sbPageFrame then
                sbPageFrame:Show()
                RenderSpellBookTrainerPage()
            end
        elseif sbPageFrame then
            RestoreMaskedNativeTabAlpha()
            sbPageFrame:Hide()
        end

        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                UpdateSpellBookTabVisual()
                if isSpellBookTrainerTabActive and sbPageFrame and sbPageFrame:IsShown() then
                    SyncActiveNativeTabMask()
                end
            end)
        end
    end)

    sbf:HookScript("OnHide", function()
        RestoreMaskedNativeTabAlpha()
        if sbPageFrame then
            if sbPageFrame.searchBox and sbPageFrame.searchBox:HasFocus() then
                sbPageFrame.searchBox:ClearFocus()
            end
            if sbPageFrame.activeTabMaskBtn then
                sbPageFrame.activeTabMaskBtn:Hide()
            end
            sbPageFrame:Hide()
        end
    end)

    if sbf.CategoryTabSystem then
        if sbf.CategoryTabSystem.SetTab then
            hooksecurefunc(sbf.CategoryTabSystem, "SetTab", function(_, _, isUserAction)
                if isUserAction and isSpellBookTrainerTabActive then
                    SetSpellBookTrainerTabActive(false)
                end
            end)
        end
        if sbf.CategoryTabSystem.SetTabVisuallySelected then
            hooksecurefunc(sbf.CategoryTabSystem, "SetTabVisuallySelected", function()
                if isSpellBookTrainerTabActive and sbPageFrame and sbPageFrame:IsShown() then
                    SyncActiveNativeTabMask()
                end
            end)
        end
    end

    if sbf.SetTab then
        hooksecurefunc(sbf, "SetTab", function(_, tabID)
            if not isSpellBookTrainerTabActive then return end
            if tabID == nil then
                SetSpellBookTrainerTabActive(false)
            elseif not sbf.isUpdatingAllSpellData and maskedNativeTabID and tabID ~= maskedNativeTabID then
                SetSpellBookTrainerTabActive(false)
            elseif sbPageFrame and sbPageFrame:IsShown() then
                SyncActiveNativeTabMask()
            end
        end)
    end

    if sbf.GoToSpellForGlyph then
        hooksecurefunc(sbf, "GoToSpellForGlyph", function()
            if isSpellBookTrainerTabActive then
                SetSpellBookTrainerTabActive(false)
            end
        end)
    end

    if sbf.SetMinimized then
        hooksecurefunc(sbf, "SetMinimized", RefreshSpellBookLayout)
    end
    if psf.UpdateSize then
        hooksecurefunc(psf, "UpdateSize", RefreshSpellBookLayout)
    end
    if psf.SetTab then
        hooksecurefunc(psf, "SetTab", UpdateSpellBookTabVisual)
    end
    psf:HookScript("OnShow", UpdateSpellBookTabVisual)

    if sbf:IsShown() then
        EnsureCatalogFresh()
        UpdateSpellBookTabVisual()
    end
end

local function HookClassicEraSpellFrames()
    if _G.PlayerSpellsFrame then return end

    local sbf = _G.SpellBookFrame
    if sbf and not eraSpellBookHooked then
        eraSpellBookHooked = true
        eraSpellBookBtn = CreateSquareHeaderButton(
            "SfuiEraSpellBookTrainerBtn",
            sbf,
            "click to toggle class trainer panel."
        )
        local closeBtn = _G.SpellBookCloseButton
        if closeBtn then
            if closeBtn.GetFrameLevel then
                eraSpellBookBtn:SetFrameLevel((closeBtn:GetFrameLevel() or 500) + 5)
            end
            eraSpellBookBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
        else
            eraSpellBookBtn:SetPoint("TOPRIGHT", sbf, "TOPRIGHT", -64, -18)
        end
        eraSpellBookBtn:SetScript("OnClick", function()
            ToggleSpellsHostPanel(sbf)
        end)
        sbf:HookScript("OnShow", function()
            if not IsInCombat() and SfuiDB and SfuiDB.showSpellBookTrainerPanel then
                preferredHost = "spells"
            end
            SyncVisibility()
        end)
        sbf:HookScript("OnHide", SyncVisibility)
        UpdateAllToggleVisuals()
    end

    local ptf = _G.PlayerTalentFrame
    if ptf and not eraTalentHooked then
        eraTalentHooked = true
        eraTalentBtn = CreateSquareHeaderButton(
            "SfuiEraTalentTrainerBtn",
            ptf,
            "click to toggle class trainer panel."
        )
        local closeBtn = _G.PlayerTalentFrameCloseButton
        if closeBtn then
            if closeBtn.GetFrameLevel then
                eraTalentBtn:SetFrameLevel((closeBtn:GetFrameLevel() or 500) + 5)
            end
            eraTalentBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
        else
            eraTalentBtn:SetPoint("TOPRIGHT", ptf, "TOPRIGHT", -64, -18)
        end
        eraTalentBtn:SetScript("OnClick", function()
            ToggleSpellsHostPanel(ptf)
        end)
        ptf:HookScript("OnShow", function()
            if not IsInCombat() and SfuiDB and SfuiDB.showSpellBookTrainerPanel then
                preferredHost = "spells"
            end
            SyncVisibility()
        end)
        ptf:HookScript("OnHide", SyncVisibility)
        UpdateAllToggleVisuals()
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Initialization & Event Wiring
-- ─────────────────────────────────────────────────────────────────────────────

local REFRESH_EVENTS = {
    "SPELLS_CHANGED",
    "LEARNED_SPELL_IN_SKILL_LINE",
    "PLAYER_LEVEL_UP",
    "CHARACTER_POINTS_CHANGED",
}

local function OnCombatStart()
    inCombat = true
    if isSpellBookTrainerTabActive and SetSpellBookTrainerTabActive then
        SetSpellBookTrainerTabActive(false)
    end
    HidePanelOnly()
end

local function OnCombatEnd()
    inCombat = false
    SyncVisibility()
end

local function QueueTrainerScan()
    if IsInCombat() then return end
    if common and common.debounce then
        common.debounce(TRAINER_SCAN_DEBOUNCE_KEY, TRAINER_SCAN_DELAY, ScanOpenClassTrainer)
    else
        ScanOpenClassTrainer()
    end
end

local function Initialize()
    if trainerModule.initialized then return end
    trainerModule.initialized = true

    if SfuiDB and SfuiDB.trainerPanelFilter then
        local saved = SfuiDB.trainerPanelFilter
        if saved == "ready" or saved == "upcoming" or saved == "all" then
            filterMode = saved
        end
    end

    trainerModule.CreatePanel()
    trainerModule.CreateCharacterToggleButton()
    HookPlayerSpellsFrame()
    HookClassicEraSpellFrames()

    local charFrame = _G.CharacterFrame
    if charFrame then
        hooksecurefunc(charFrame, "Show", function()
            AlignCharHeaderButtons()
            if not IsInCombat() and SfuiDB and SfuiDB.showTrainerInfoPanel then
                preferredHost = "char"
            end
            SyncVisibility()
        end)
        hooksecurefunc(charFrame, "Hide", function()
            SyncVisibility()
        end)
    end

    local events = sfui.events
    if events then
        events.RegisterEvent("PLAYER_REGEN_DISABLED", OnCombatStart)
        events.RegisterEvent("PLAYER_REGEN_ENABLED", OnCombatEnd)
        events.RegisterEvent("TRAINER_SHOW", QueueTrainerScan)
        events.RegisterEvent("TRAINER_UPDATE", QueueTrainerScan)
        events.RegisterEvent("PLAYER_MONEY", OnPlayerMoney)
        events.RegisterEvent("SPELL_TEXT_UPDATE", OnSpellTextUpdate)
        events.RegisterEvent("ADDON_LOADED", function(_, loadedAddon)
            if loadedAddon == "Blizzard_PlayerSpells" then
                HookPlayerSpellsFrame()
            elseif loadedAddon == "Blizzard_TalentUI" then
                HookClassicEraSpellFrames()
            end
        end)
        for i = 1, #REFRESH_EVENTS do
            events.RegisterEvent(REFRESH_EVENTS[i], RequestRefresh)
        end
        events.RegisterMessage("SFUI_SPEC_CHANGED", RequestRefresh)
    end

    RebuildCatalog()
    UpdateAllToggleVisuals()
    SyncVisibility()
end

if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("PLAYER_LOGIN", Initialize)
end
