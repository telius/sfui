local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.upgrades = sfui.upgrades or {}

-- Guard: Forever / Camelot only (never load on Retail)
if sfui.isRetail then
    return
end

local U               = sfui.upgrades
local common          = sfui.common
local theme           = sfui.theme

local _G              = _G
local CreateFrame     = _G.CreateFrame
local UIParent        = _G.UIParent
local UnitName        = _G.UnitName
local UnitLevel       = _G.UnitLevel
local UnitClass       = _G.UnitClass
local UnitRace        = _G.UnitRace
local UnitFactionGroup= _G.UnitFactionGroup
local GetRealmName    = _G.GetNormalizedRealmName or _G.GetRealmName
local InCombatLockdown= _G.InCombatLockdown
local IsShiftKeyDown  = _G.IsShiftKeyDown
local GetTime         = _G.GetTime
local GetInventoryItemLink    = _G.GetInventoryItemLink
local GetInventoryItemTexture = _G.GetInventoryItemTexture
local C_Timer         = _G.C_Timer
local C_Map           = _G.C_Map
local C_QuestLog      = _G.C_QuestLog
local debugprofilestop= _G.debugprofilestop

local coroutine       = _G.coroutine
local math            = _G.math
local table           = _G.table
local string          = _G.string
local pairs           = _G.pairs
local ipairs          = _G.ipairs
local type            = _G.type
local tonumber        = _G.tonumber
local tostring        = _G.tostring
local select          = _G.select
local wipe            = _G.wipe or function(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

local issecretvalue = (sfui.safety and sfui.safety.issecretvalue)
    or (sfui.common and sfui.common.issecretvalue)
    or _G.issecretvalue
    or function() return false end

local LEVEL_FILTER_OPTIONS = {
    { value = "all_equippable", text = "all equippable",        below = nil, above = 0,  equippableOnly = true  },
    { value = "equippable_20",  text = "equippable (-20 lvls)", below = 20,  above = 0,  equippableOnly = true  },
    { value = "range_20_4",     text = "lvl -20 to +4",         below = 20,  above = 4,  equippableOnly = false },
    { value = "range_10_6",     text = "lvl -10 to +6",         below = 10,  above = 6,  equippableOnly = false },
    { value = "range_5_4",      text = "lvl -5 to +4",          below = 5,   above = 4,  equippableOnly = false },
    { value = "range_20_10",    text = "lvl -20 to +10",        below = 20,  above = 10, equippableOnly = false },
}

local LEVEL_FILTER_BY_ID = {}
for _, opt in ipairs(LEVEL_FILTER_OPTIONS) do
    LEVEL_FILTER_BY_ID[opt.value] = opt
end

-- ─── SavedVariables Defaults ──────────────────────────────────────────────────
if sfui.db and sfui.db.RegisterDefaults then
    sfui.db.RegisterDefaults("upgrades", {
        levelFilter  = "range_20_4",
        sources      = { dungeon = true, quest = true, vendor = true },
        selectedSlot = "all",
        showHidden   = false,
        hiddenByChar = {},
        pos          = nil,
    }, 3, function(cur)
        if type(cur) == "table" and not LEVEL_FILTER_BY_ID[cur.levelFilter] then
            if cur.equippableOnly == true then
                cur.levelFilter = "equippable_20"
            else
                cur.levelFilter = "range_20_4"
            end
        end
    end)
end

local function DB()
    _G.SfuiDB = _G.SfuiDB or {}
    local root = _G.SfuiDB
    if type(root.upgrades) ~= "table" then
        root.upgrades = {}
    end
    local db = root.upgrades
    if not LEVEL_FILTER_BY_ID[db.levelFilter] then
        db.levelFilter = (db.equippableOnly == true) and "equippable_20" or "range_20_4"
    end
    if type(db.sources) ~= "table" then
        db.sources = { dungeon = true, quest = true, vendor = true }
    else
        if db.sources.dungeon == nil then db.sources.dungeon = true end
        if db.sources.quest == nil then db.sources.quest = true end
        if db.sources.vendor == nil then db.sources.vendor = true end
    end
    if type(db.selectedSlot) ~= "string" then db.selectedSlot = "all" end
    if db.showHidden == nil then db.showHidden = false end
    if type(db.hiddenByChar) ~= "table" then db.hiddenByChar = {} end
    return db
end

local function GetCharKey()
    if common and common.get_player_unique_key then
        local key = common.get_player_unique_key()
        if key and key ~= "" then return key end
    end
    local pName = (UnitName and UnitName("player")) or "player"
    local pRealm = (GetRealmName and GetRealmName()) or "realm"
    return tostring(pName) .. "-" .. tostring(pRealm)
end

local function GetCharHidden()
    local db = DB()
    local key = GetCharKey()
    if type(db.hiddenByChar[key]) ~= "table" then
        db.hiddenByChar[key] = {}
    end
    return db.hiddenByChar[key]
end

local function CountHidden()
    local count = 0
    for _ in pairs(GetCharHidden()) do
        count = count + 1
    end
    return count
end

local function IsItemHidden(itemID)
    if not itemID then return false end
    return GetCharHidden()[itemID] == true
end

-- ─── Constants & Lookups ──────────────────────────────────────────────────────
local CONST = {
    FRAME_W            = 760,
    FRAME_H            = 540,
    RAIL_W             = 188,
    SLOT_BTN_H         = 26,
    SLOT_BTN_GAP       = 1,
    ROW_H              = 46,
    ROW_GAP            = 2,
    SCAN_BUDGET_MS     = 2.5,
    SCAN_FALLBACK_STEP = 120,
    LOAD_BATCH_SIZE    = 25,
    LOAD_BATCH_DELAY   = 0.10,
    LOAD_TIMEOUT_SEC   = 4.0,
}

local SLOT_DEFS = {
    { key = "all",      label = "all slots", slotIDs = nil },
    { key = "head",     label = "head",      slotIDs = { 1 } },
    { key = "neck",     label = "neck",      slotIDs = { 2 } },
    { key = "shoulder", label = "shoulder",  slotIDs = { 3 } },
    { key = "back",     label = "back",      slotIDs = { 15 } },
    { key = "chest",    label = "chest",     slotIDs = { 5 } },
    { key = "wrist",    label = "wrist",     slotIDs = { 9 } },
    { key = "hands",    label = "hands",     slotIDs = { 10 } },
    { key = "waist",    label = "waist",     slotIDs = { 6 } },
    { key = "legs",     label = "legs",      slotIDs = { 7 } },
    { key = "feet",     label = "feet",      slotIDs = { 8 } },
    { key = "finger",   label = "finger",    slotIDs = { 11, 12 } },
    { key = "trinket",  label = "trinket",   slotIDs = { 13, 14 } },
    { key = "mainhand", label = "main hand", slotIDs = { 16 } },
    { key = "offhand",  label = "off hand",  slotIDs = { 17 } },
    { key = "ranged",   label = "ranged",    slotIDs = { 18 } },
}

local SLOT_ID_TO_KEY = {}
local SLOT_KEY_TO_DEF = {}
for _, def in ipairs(SLOT_DEFS) do
    SLOT_KEY_TO_DEF[def.key] = def
    if def.slotIDs then
        for _, sID in ipairs(def.slotIDs) do
            SLOT_ID_TO_KEY[sID] = def.key
        end
    end
end

local EQUIP_LOC_VALID = {
    INVTYPE_HEAD           = true,
    INVTYPE_NECK           = true,
    INVTYPE_SHOULDER       = true,
    INVTYPE_CLOAK          = true,
    INVTYPE_CHEST          = true,
    INVTYPE_ROBE           = true,
    INVTYPE_WRIST          = true,
    INVTYPE_HAND           = true,
    INVTYPE_WAIST          = true,
    INVTYPE_LEGS           = true,
    INVTYPE_FEET           = true,
    INVTYPE_FINGER         = true,
    INVTYPE_TRINKET        = true,
    INVTYPE_WEAPON         = true,
    INVTYPE_2HWEAPON       = true,
    INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND  = true,
    INVTYPE_HOLDABLE       = true,
    INVTYPE_SHIELD         = true,
    INVTYPE_RANGED         = true,
    INVTYPE_RANGEDRIGHT    = true,
    INVTYPE_THROWN         = true,
    INVTYPE_RELIC          = true,
}

local ACCESSORY_EQUIP_LOCS = {
    INVTYPE_CLOAK    = true,
    INVTYPE_FINGER   = true,
    INVTYPE_TRINKET  = true,
    INVTYPE_NECK     = true,
    INVTYPE_HOLDABLE = true,
    INVTYPE_SHIELD   = true,
    INVTYPE_RELIC    = true,
}

-- Matches QuestieDB/src/corrections/enum/expansions.lua (Forever bits 32/33 for Skyborne)
local RACE_MASK_BY_ID = {
    [1]  = 1,
    [2]  = 2,
    [3]  = 4,
    [4]  = 8,
    [5]  = 16,
    [6]  = 32,
    [7]  = 64,
    [8]  = 128,
    [9]  = 256,
    [10] = 512,
    [11] = 1024,
    [22] = 2097152,
    [24] = 8388608,
    [25] = 16777216,
    [26] = 33554432,
    [95] = 4294967296,
    [96] = 8589934592,
}

local CLASS_MASK_BY_FILE = {
    WARRIOR     = 1,
    PALADIN     = 2,
    HUNTER      = 4,
    ROGUE       = 8,
    PRIEST      = 16,
    DEATHKNIGHT = 32,
    SHAMAN      = 64,
    MAGE        = 128,
    WARLOCK     = 256,
    MONK        = 512,
    DRUID       = 1024,
}

local CLASS_MAX_ARMOR = {
    MAGE        = 1,
    PRIEST      = 1,
    WARLOCK     = 1,
    ROGUE       = 2,
    DRUID       = 2,
    HUNTER      = 3,
    SHAMAN      = 3,
    WARRIOR     = 4,
    PALADIN     = 4,
    DEATHKNIGHT = 4,
}

local SHIELD_CLASSES = {
    WARRIOR = true,
    PALADIN = true,
    SHAMAN  = true,
}

local RELIC_SUBCLASS_BY_CLASS = {
    PALADIN     = 7,
    DRUID       = 8,
    SHAMAN      = 9,
    DEATHKNIGHT = 10,
}

-- ─── Runtime State ────────────────────────────────────────────────────────────
local state = {
    scanSerial         = 0,
    isDirty            = true,
    isScanning         = false,
    scanProgress       = 0,
    scanTotal          = 0,
    scanPhase          = "idle",
    lastContextSig     = nil,
    lastFilterSig      = nil,
    candidates         = {},
    sourceDedup        = {},
    evaluatedInScan    = {},
    pendingLoadQueue   = {},
    pendingLoadSet     = {},
    pendingLoadCount   = 0,
    loadDrainCompleted = false,
    results            = { bySlot = {}, all = {}, bestBySlot = {} },
    coroutine          = nil,
    loadPumpActive     = false,
    refreshPending     = false,
    rescanPending      = false,
    lastContext        = nil,
    lastMinLvl         = 1,
    lastMaxLvl         = 60,
    lastEquipOnly      = false,
}

local ui = {
    frame      = nil,
    slotBtns   = {},
    rowPool    = {},
    filterBtns = {},
    driver     = nil,
}

-- ─── Low-level Bitmask, DB, & Coordinate Helpers ──────────────────────────────
local function BitHas(mask, bitVal)
    if type(mask) ~= "number" or mask <= 0 or type(bitVal) ~= "number" or bitVal <= 0 then
        return false
    end
    return math.floor(mask / bitVal) % 2 == 1
end

local function LowerText(val)
    if val == nil or issecretvalue(val) then return "" end
    return string.lower(tostring(val))
end

local function HasQuestieDB()
    return type(_G.ItemDB) == "table"
        and type(_G.ItemDB.GetAllIds) == "function"
        and type(_G.QuestDB) == "table"
        and type(_G.NpcDB) == "table"
end

local function IsQuestCompleted(questID)
    if not questID or issecretvalue(questID) or type(questID) ~= "number" or questID <= 0 then
        return false
    end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        local done = C_QuestLog.IsQuestFlaggedCompleted(questID)
        if not issecretvalue(done) then
            return done == true
        end
    elseif _G.IsQuestFlaggedCompleted then
        return _G.IsQuestFlaggedCompleted(questID) == true
    end
    if sfui.queststate and sfui.queststate.IsCompleted then
        return sfui.queststate.IsCompleted(questID) == true
    end
    return false
end

local function NormalizeCoords(x, y)
    if type(x) ~= "number" or type(y) ~= "number" then return nil, nil end
    if x <= 0 or y <= 0 then return nil, nil end
    if x > 1 or y > 1 then
        x = x / 100
        y = y / 100
    end
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil, nil end
    return x, y
end

local function ResolveZoneAndMap(areaID)
    if type(areaID) ~= "number" or areaID <= 0 then return nil, nil end
    local uiMapID = nil
    local loader = _G.QuestieLoader
    if type(loader) == "table" and type(loader._modules) == "table" then
        local zdb = loader._modules["ZoneDB"]
        if type(zdb) == "table" and type(zdb.GetUiMapIdByAreaId) == "function" then
            local m = zdb:GetUiMapIdByAreaId(areaID)
            if type(m) == "number" and m > 0 then
                uiMapID = m
            end
        end
    end
    local zoneName = nil
    if C_Map and type(C_Map.GetAreaInfo) == "function" then
        local z = C_Map.GetAreaInfo(areaID)
        if z and not issecretvalue(z) and type(z) == "string" and z ~= "" then
            zoneName = LowerText(z)
        end
    end
    return uiMapID, zoneName
end

local function ExtractSpawnCoords(spawns)
    if type(spawns) ~= "table" then return nil end
    local fallback = nil
    for areaID, points in pairs(spawns) do
        if type(points) == "table" then
            for _, pt in ipairs(points) do
                if type(pt) == "table" then
                    local nx, ny = NormalizeCoords(pt[1], pt[2])
                    if nx and ny then
                        local mapID, zoneName = ResolveZoneAndMap(areaID)
                        local info = { mapID = mapID, x = nx, y = ny, areaID = areaID, zoneName = zoneName }
                        if mapID then
                            return info
                        elseif not fallback then
                            fallback = info
                        end
                    end
                end
            end
        end
    end
    return fallback
end

local function SafeGetItemInfoInstant(itemID)
    if common and common.get_item_instant_info then
        return common.get_item_instant_info(itemID)
    end
    if _G.C_Item and _G.C_Item.GetItemInfoInstant then
        return _G.C_Item.GetItemInfoInstant(itemID)
    end
    if _G.GetItemInfoInstant then
        return _G.GetItemInfoInstant(itemID)
    end
    return nil
end

local function SafeGetItemInfo(itemID)
    if common and common.get_item_info then
        return common.get_item_info(itemID)
    end
    if _G.C_Item and _G.C_Item.GetItemInfo then
        return _G.C_Item.GetItemInfo(itemID)
    end
    if _G.GetItemInfo then
        return _G.GetItemInfo(itemID)
    end
    return nil
end

local function SafeGetItemLevel(itemLinkOrID, baseIlvl)
    local ilvl = common and common.get_item_level and common.get_item_level(itemLinkOrID) or 0
    if not ilvl or ilvl <= 0 then ilvl = baseIlvl or 0 end
    return ilvl
end

-- ─── Player Context & Filter Signatures ───────────────────────────────────────
local function GetPlayerContext()
    local playerLevel = (UnitLevel and UnitLevel("player")) or 1
    if issecretvalue(playerLevel) or type(playerLevel) ~= "number" or playerLevel < 1 then
        playerLevel = 1
    end

    local classFile, classID
    if sfui.talents and sfui.talents.get_player_class then
        classFile, classID = sfui.talents.get_player_class()
    end
    if not classFile and UnitClass then
        local _, eng, cid = UnitClass("player")
        classFile = eng
        classID = cid
    end
    classFile = classFile and string.upper(tostring(classFile)) or "WARRIOR"
    local classMask = CLASS_MASK_BY_FILE[classFile] or (classID and (2 ^ (classID - 1))) or 0

    local raceID = UnitRace and select(3, UnitRace("player")) or nil
    local raceMask = (type(raceID) == "number" and RACE_MASK_BY_ID[raceID]) or 0

    local faction = UnitFactionGroup and UnitFactionGroup("player") or "Alliance"
    local factionLetter = (faction == "Horde") and "H" or "A"

    local activeSpecID = (common and common.get_current_spec_id and common.get_current_spec_id()) or 0
    local roleLabel = nil
    local specDB = _G.SfuiDB and _G.SfuiDB.gear and _G.SfuiDB.gear[activeSpecID]
    if sfui.gear and sfui.gear.GetClassicRole then
        roleLabel = sfui.gear.GetClassicRole(activeSpecID, specDB)
    elseif specDB and specDB.classic_role then
        roleLabel = specDB.classic_role
    end
    roleLabel = roleLabel and LowerText(roleLabel) or "dps"

    local eqParts = {}
    for sID = 1, 18 do
        if sID ~= 4 then
            local link = GetInventoryItemLink and GetInventoryItemLink("player", sID)
            if link and not issecretvalue(link) then
                eqParts[#eqParts + 1] = tostring(sID) .. "=" .. tostring(link)
            else
                eqParts[#eqParts + 1] = tostring(sID) .. "=0"
            end
        end
    end

    local weightSig = ""
    if specDB then
        local orderStr = type(specDB.stat_order) == "table" and table.concat(specDB.stat_order, ",") or ""
        local pawnStr = tostring(specDB.pawn_string or "")
        weightSig = tostring(specDB.classic_role or "") .. ":" .. orderStr .. ":" .. pawnStr
    end

    local equippedSig = table.concat(eqParts, ";")
    local contextSig = string.format("%d|%s|%s|%s|%s|%s",
        playerLevel, tostring(activeSpecID), roleLabel, factionLetter, weightSig, equippedSig)

    return {
        playerLevel   = playerLevel,
        classFile     = classFile,
        classID       = classID,
        classMask     = classMask,
        raceID        = raceID,
        raceMask      = raceMask,
        faction       = faction,
        factionLetter = factionLetter,
        activeSpecID  = activeSpecID,
        roleLabel     = roleLabel,
        contextSig    = contextSig,
    }
end

local function GetLevelWindow(db, playerLevel)
    local maxCap = (_G.GetMaxPlayerLevel and _G.GetMaxPlayerLevel()) or 60
    local mode = LEVEL_FILTER_BY_ID[db and db.levelFilter] or LEVEL_FILTER_BY_ID.range_20_4
    local minLvl = mode.below and math.max(1, playerLevel - mode.below) or 1
    local equipOnly = (mode.equippableOnly == true)
    local maxLvl = equipOnly and playerLevel or math.min(maxCap, playerLevel + (mode.above or 4))
    if maxLvl < minLvl then maxLvl = minLvl end
    return minLvl, maxLvl, equipOnly, mode
end

local function MakeFilterSig(db)
    return string.format("%s:%s:%s:%s",
        tostring((db and db.levelFilter) or "range_20_4"),
        (db.sources and db.sources.dungeon) and "1" or "0",
        (db.sources and db.sources.quest) and "1" or "0",
        (db.sources and db.sources.vendor) and "1" or "0"
    )
end

-- ─── Instant Pre-filter (C++ GetItemInfoInstant) ─────────────────────────────
local function CanClassWearInstant(itemID, classFile, activeSpecID)
    local _, _, _, equipLoc, _, classID, subClassID = SafeGetItemInfoInstant(itemID)
    if (classID ~= 2 and classID ~= 4) or not EQUIP_LOC_VALID[equipLoc] then
        return false
    end

    if classID == 4 then
        if equipLoc == "INVTYPE_SHIELD" then
            if not SHIELD_CLASSES[classFile] then return false end
        elseif equipLoc == "INVTYPE_RELIC" then
            local allowedRelic = RELIC_SUBCLASS_BY_CLASS[classFile]
            if not allowedRelic then return false end
            if subClassID and subClassID ~= allowedRelic and subClassID ~= 11 and subClassID ~= 0 then
                return false
            end
        elseif not ACCESSORY_EQUIP_LOCS[equipLoc] then
            local maxArmor = CLASS_MAX_ARMOR[classFile] or 4
            if subClassID and subClassID ~= 5 and subClassID > maxArmor then
                return false
            end
        end
    elseif classID == 2 and activeSpecID and activeSpecID ~= 0 and sfui.highest and sfui.highest.GetRule then
        local rule = sfui.highest.GetRule(activeSpecID)
        if rule and rule.allowedWeapons and subClassID and not rule.allowedWeapons[subClassID] then
            return false
        end
    end

    return true, equipLoc, classID, subClassID
end

-- ─── Candidate Aggregation & Deduplication ───────────────────────────────────
local function BuildSourceDedupKey(itemID, src)
    if src.kind == "dungeon" then
        return tostring(itemID) .. "|d|" .. tostring(src.dungeonID or "") .. "|" .. tostring(src.bossName or "")
    elseif src.kind == "quest" then
        return tostring(itemID) .. "|q|" .. tostring(src.questID or src.questName or "")
    elseif src.kind == "vendor" then
        return tostring(itemID) .. "|v|" .. tostring(src.npcID or src.npcName or "")
    end
    return tostring(itemID) .. "|x|" .. tostring(src.kind or "")
end

local function AddCandidateSource(candidates, dedupMap, itemID, src)
    if not itemID or not src then return false end
    local dKey = BuildSourceDedupKey(itemID, src)
    if dedupMap[dKey] then return false end
    dedupMap[dKey] = true

    local cand = candidates[itemID]
    if not cand then
        cand = {
            itemID      = itemID,
            sources     = {},
            sourceKinds = {},
        }
        candidates[itemID] = cand
    end

    if src.kind == "vendor" then
        local vCount = 0
        for _, existing in ipairs(cand.sources) do
            if existing.kind == "vendor" then vCount = vCount + 1 end
        end
        if vCount >= 3 then return false end
    end

    cand.sources[#cand.sources + 1] = src
    cand.sourceKinds[src.kind] = true
    return true
end

-- ─── Stage A: SFUI Dungeon Journal Indexer ────────────────────────────────────
local function BuildDungeonCandidates(ctx, db, minLvl, maxLvl, equipOnly, candidates, dedupMap, djQuestSeen)
    local dj = sfui.dj_camelot
    if not dj or type(dj.dungeons) ~= "table" then return end

    local wantDungeon = db.sources.dungeon == true
    local wantQuest   = db.sources.quest == true
    local maxCap      = (_G.GetMaxPlayerLevel and _G.GetMaxPlayerLevel()) or 60
    local questMaxLvl = equipOnly and math.min(maxCap, ctx.playerLevel + 5) or maxLvl
    local bossMaxLvl  = equipOnly and math.min(maxCap, ctx.playerLevel + 5) or maxLvl

    for _, dungeon in ipairs(dj.dungeons) do
        local dMin = tonumber(dungeon.minLevel) or 1
        local dMax = tonumber(dungeon.maxLevel) or dMin

        if wantDungeon and type(dungeon.bosses) == "table" then
            if dMax >= (minLvl - 3) and dMin <= (bossMaxLvl + 3) then
                for _, boss in ipairs(dungeon.bosses) do
                    if type(boss.items) == "table" then
                        for _, itemID in ipairs(boss.items) do
                            if CanClassWearInstant(itemID, ctx.classFile, ctx.activeSpecID) then
                                AddCandidateSource(candidates, dedupMap, itemID, {
                                    kind        = "dungeon",
                                    dungeonID   = dungeon.id,
                                    dungeonName = LowerText(dungeon.name or dungeon.id),
                                    bossName    = LowerText(boss.name or "boss"),
                                    bossLevel   = tonumber(boss.level) or dMax,
                                    dropRate    = boss.dropRates and boss.dropRates[itemID] or nil,
                                    entrance    = dungeon.entrance,
                                    isRaid      = (dungeon.category == "raid"),
                                })
                            end
                        end
                    end
                end
            end
        end

        if wantQuest and type(dungeon.quests) == "table" then
            for _, quest in ipairs(dungeon.quests) do
                local qID = quest.id
                if qID then
                    djQuestSeen[qID] = true
                end
                if qID and type(quest.rewardItems) == "table" and #quest.rewardItems > 0 then
                    if not IsQuestCompleted(qID) then
                        local qFaction = quest.faction
                        local factionOK = (not qFaction or qFaction == "Both" or qFaction == ctx.faction)
                        local qLvl = tonumber(quest.level) or dMax
                        local qMin = tonumber(quest.minLevel) or 0
                        local levelOK = (qLvl >= minLvl and qLvl <= questMaxLvl and qMin <= (equipOnly and ctx.playerLevel or maxLvl))
                        if factionOK and levelOK then
                            local coords = (quest.chainStart and quest.chainStart.coords)
                                or (quest.chain and quest.chain[1] and quest.chain[1].coords)
                                or dungeon.entrance
                            for _, itemID in ipairs(quest.rewardItems) do
                                if CanClassWearInstant(itemID, ctx.classFile, ctx.activeSpecID) then
                                    AddCandidateSource(candidates, dedupMap, itemID, {
                                        kind        = "quest",
                                        fromDJ      = true,
                                        questID     = qID,
                                        questName   = LowerText(quest.name or ("quest #" .. tostring(qID))),
                                        questLevel  = qLvl,
                                        reqLevel    = qMin,
                                        dungeonID   = dungeon.id,
                                        dungeonName = LowerText(dungeon.name or ""),
                                        pickup      = quest.pickup and LowerText(quest.pickup) or nil,
                                        hasPrereq   = quest.hasPrereq == true,
                                        coords      = coords,
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ─── Stage B: QuestieDB Open-World Quests & Vendor Indexer ────────────────────
local function IsAnyQuestCompleted(questList)
    if type(questList) ~= "table" then return false end
    for _, qID in ipairs(questList) do
        if IsQuestCompleted(qID) then return true end
    end
    return false
end

local function EvaluateQuestieQuest(questID, ctx, equipOnly, minLvl, maxLvl, questEvalCache)
    if questEvalCache[questID] ~= nil then
        return questEvalCache[questID] or nil
    end

    local QuestDB = _G.QuestDB
    local NpcDB   = _G.NpcDB
    local ObjectDB= _G.ObjectDB

    if IsQuestCompleted(questID) then
        questEvalCache[questID] = false
        return nil
    end

    local reqRaces = QuestDB.requiredRaces and QuestDB.requiredRaces(questID)
    if reqRaces and reqRaces > 0 and ctx.raceMask and ctx.raceMask > 0 and not BitHas(reqRaces, ctx.raceMask) then
        questEvalCache[questID] = false
        return nil
    end

    local reqClasses = QuestDB.requiredClasses and QuestDB.requiredClasses(questID)
    if reqClasses and reqClasses > 0 and ctx.classMask and ctx.classMask > 0 and not BitHas(reqClasses, ctx.classMask) then
        questEvalCache[questID] = false
        return nil
    end

    local reqMaxLvl = QuestDB.requiredMaxLevel and QuestDB.requiredMaxLevel(questID)
    if reqMaxLvl and reqMaxLvl > 0 and ctx.playerLevel > reqMaxLvl then
        questEvalCache[questID] = false
        return nil
    end

    local availUntil = QuestDB.availableUntilCompleted and QuestDB.availableUntilCompleted(questID)
    if availUntil and availUntil > 0 and IsQuestCompleted(availUntil) then
        questEvalCache[questID] = false
        return nil
    end

    local nextInChain = QuestDB.nextQuestInChain and QuestDB.nextQuestInChain(questID)
    if nextInChain and nextInChain > 0 and IsQuestCompleted(nextInChain) then
        questEvalCache[questID] = false
        return nil
    end

    local excl = QuestDB.exclusiveTo and QuestDB.exclusiveTo(questID)
    if IsAnyQuestCompleted(excl) then
        questEvalCache[questID] = false
        return nil
    end

    local qReq = (QuestDB.requiredLevel and QuestDB.requiredLevel(questID)) or 0
    local qLvl = (QuestDB.questLevel and QuestDB.questLevel(questID)) or 0
    if qLvl == -1 then
        qLvl = (qReq > 0) and qReq or ctx.playerLevel
    elseif qLvl <= 0 then
        qLvl = qReq
    end
    local maxCap = (_G.GetMaxPlayerLevel and _G.GetMaxPlayerLevel()) or 60
    local questMaxLvl = equipOnly and math.min(maxCap, ctx.playerLevel + 5) or maxLvl
    if qLvl <= 0 or qLvl < minLvl or qLvl > questMaxLvl or qReq > (equipOnly and ctx.playerLevel or maxLvl) then
        questEvalCache[questID] = false
        return nil
    end

    local hasPrereq = false
    local preSingle = QuestDB.preQuestSingle and QuestDB.preQuestSingle(questID)
    if type(preSingle) == "table" and #preSingle > 0 and not IsAnyQuestCompleted(preSingle) then
        hasPrereq = true
    end
    if not hasPrereq then
        local preGroup = QuestDB.preQuestGroup and QuestDB.preQuestGroup(questID)
        if type(preGroup) == "table" and #preGroup > 0 then
            for _, pq in ipairs(preGroup) do
                if not IsQuestCompleted(pq) then
                    hasPrereq = true
                    break
                end
            end
        end
    end

    local giverName = nil
    local coords = nil
    local zoneName = nil

    local startedBy = QuestDB.startedBy and QuestDB.startedBy(questID)
    if type(startedBy) == "table" then
        if type(startedBy[1]) == "table" and NpcDB then
            for _, npcID in ipairs(startedBy[1]) do
                local friendly = NpcDB.friendlyToFaction and NpcDB.friendlyToFaction(npcID)
                local fOK = (not friendly) or friendly:find(ctx.factionLetter, 1, true)
                if fOK then
                    giverName = giverName or (NpcDB.name and NpcDB.name(npcID))
                    local spawns = NpcDB.spawns and NpcDB.spawns(npcID)
                    coords = ExtractSpawnCoords(spawns)
                    if coords then
                        zoneName = coords.zoneName
                        break
                    end
                end
            end
        end
        if not coords and type(startedBy[2]) == "table" and ObjectDB then
            for _, objID in ipairs(startedBy[2]) do
                giverName = giverName or (ObjectDB.name and ObjectDB.name(objID))
                local spawns = ObjectDB.spawns and ObjectDB.spawns(objID)
                coords = ExtractSpawnCoords(spawns)
                if coords then
                    zoneName = coords.zoneName
                    break
                end
            end
        end
    end

    if not zoneName and QuestDB.zoneOrSort then
        local zOrS = QuestDB.zoneOrSort(questID)
        if type(zOrS) == "number" and zOrS > 0 then
            local _, z = ResolveZoneAndMap(zOrS)
            zoneName = z
        end
    end

    local qName = QuestDB.name and QuestDB.name(questID)
    local src = {
        kind       = "quest",
        fromDJ     = false,
        questID    = questID,
        questName  = LowerText(qName or ("quest #" .. tostring(questID))),
        questLevel = qLvl,
        reqLevel   = qReq,
        giverName  = giverName and LowerText(giverName) or nil,
        zoneName   = zoneName and LowerText(zoneName) or nil,
        hasPrereq  = hasPrereq,
        coords     = coords,
    }
    questEvalCache[questID] = src
    return src
end

local function EvaluateQuestieVendor(npcID, ctx, vendorEvalCache)
    if vendorEvalCache[npcID] ~= nil then
        return vendorEvalCache[npcID] or nil
    end

    local NpcDB = _G.NpcDB
    local friendly = NpcDB.friendlyToFaction and NpcDB.friendlyToFaction(npcID)
    if type(friendly) ~= "string" or not friendly:find(ctx.factionLetter, 1, true) then
        vendorEvalCache[npcID] = false
        return nil
    end

    local spawns = NpcDB.spawns and NpcDB.spawns(npcID)
    local coords = ExtractSpawnCoords(spawns)
    if not coords then
        vendorEvalCache[npcID] = false
        return nil
    end

    local npcName = NpcDB.name and NpcDB.name(npcID)
    local src = {
        kind     = "vendor",
        npcID    = npcID,
        npcName  = LowerText(npcName or ("vendor #" .. tostring(npcID))),
        zoneName = coords.zoneName,
        coords   = coords,
    }
    vendorEvalCache[npcID] = src
    return src
end

-- ─── Stage C: Scoring, Grouping, & Async Item Load ────────────────────────────
local function HasEmptyTrinketSlot()
    if not GetInventoryItemLink then return false end
    local l13 = GetInventoryItemLink("player", 13)
    local l14 = GetInventoryItemLink("player", 14)
    return (not l13 or l13 == "") or (not l14 or l14 == "")
end

local function IsItemCurrentlyEquipped(itemID, slotIDs)
    if not itemID or not GetInventoryItemLink or not slotIDs then return false end
    for _, sID in ipairs(slotIDs) do
        local link = GetInventoryItemLink("player", sID)
        if link and not issecretvalue(link) then
            local eqID = (common and common.get_item_id and common.get_item_id(link))
                or tonumber(tostring(link):match("item:(%d+)"))
            if eqID == itemID then
                return true
            end
        end
    end
    return false
end

local function CompareTrinkets(a, b)
    if a.requiresHigherLevel ~= b.requiresHigherLevel then
        return not a.requiresHigherLevel
    end
    if (a.ilvl or 0) ~= (b.ilvl or 0) then
        return (a.ilvl or 0) > (b.ilvl or 0)
    end
    if (a.quality or 0) ~= (b.quality or 0) then
        return (a.quality or 0) > (b.quality or 0)
    end
    return (a.itemID or 0) < (b.itemID or 0)
end

local function BuildUpgradeEntry(itemID, ctx, minLvl, maxLvl, equipOnly)
    local name, link, quality, baseIlvl, reqLvl, _, _, _, equipLoc, icon = SafeGetItemInfo(itemID)
    if not name then
        return nil, true -- uncached
    end

    local exactReq = tonumber(reqLvl) or 0
    if exactReq > 0 then
        if exactReq > maxLvl then return nil, false end
        if equipOnly and exactReq > ctx.playerLevel then return nil, false end
        if exactReq < (minLvl - 3) then return nil, false end
    end

    if ctx.playerLevel >= 12 and quality and quality < 2 then
        return nil, false
    end

    if not equipLoc or equipLoc == "" then
        local _, _, _, eqLoc = SafeGetItemInfoInstant(itemID)
        equipLoc = eqLoc
    end

    if equipLoc == "INVTYPE_TRINKET" then
        if IsItemCurrentlyEquipped(itemID, { 13, 14 }) then
            return nil, false
        end
        if sfui.highest and sfui.highest.CanPlayerUseItem then
            if not sfui.highest.CanPlayerUseItem(link, itemID, true) then
                return nil, false
            end
        end
        local ilvl = SafeGetItemLevel(link or itemID, baseIlvl)
        local cand = state.candidates[itemID]
        return {
            itemID              = itemID,
            link                = link or ("item:" .. tostring(itemID)),
            name                = LowerText(name),
            quality             = quality or 1,
            ilvl                = ilvl,
            reqLevel            = exactReq,
            icon                = icon or 134400,
            slotID              = 13,
            slotKey             = "trinket",
            isUnrated           = true,
            pctGain             = nil,
            scoreDelta          = 0,
            ilvlDelta           = 0,
            requiresHigherLevel = exactReq > ctx.playerLevel,
            roleLabel           = ctx.roleLabel,
            sources             = cand and cand.sources or {},
        }, false
    end

    if not (sfui.gear and sfui.gear.EvaluateItemUpgrade) then
        return nil, false
    end

    local specArg = (ctx.activeSpecID and ctx.activeSpecID ~= 0) and ctx.activeSpecID or nil
    local res = sfui.gear.EvaluateItemUpgrade(itemID, specArg, true)
    if not res or not res.isUpgrade or (res.pctGain or 0) <= 0 or not res.slotID then
        return nil, false
    end

    local slotKey = SLOT_ID_TO_KEY[res.slotID]
    if not slotKey then return nil, false end

    local ilvl = SafeGetItemLevel(link or itemID, baseIlvl)
    local cand = state.candidates[itemID]
    return {
        itemID              = itemID,
        link                = link or ("item:" .. tostring(itemID)),
        name                = LowerText(name),
        quality             = quality or 1,
        ilvl                = ilvl,
        reqLevel            = exactReq,
        icon                = icon or 134400,
        slotID              = res.slotID,
        slotKey             = slotKey,
        isUnrated           = false,
        pctGain             = res.pctGain,
        scoreDelta          = res.scoreDelta or 0,
        ilvlDelta           = res.ilvlDelta or 0,
        requiresHigherLevel = res.requiresHigherLevel == true or (exactReq > ctx.playerLevel),
        roleLabel           = res.roleLabel or ctx.roleLabel,
        sources             = cand and cand.sources or {},
    }, false
end

local function CompareUpgrades(a, b)
    if (a.isUnrated == true) ~= (b.isUnrated == true) then
        return not a.isUnrated
    end
    if a.isUnrated and b.isUnrated then
        return CompareTrinkets(a, b)
    end
    if math.abs((a.pctGain or 0) - (b.pctGain or 0)) > 0.05 then
        return (a.pctGain or 0) > (b.pctGain or 0)
    end
    if a.requiresHigherLevel ~= b.requiresHigherLevel then
        return not a.requiresHigherLevel
    end
    if (a.ilvl or 0) ~= (b.ilvl or 0) then
        return (a.ilvl or 0) > (b.ilvl or 0)
    end
    return (a.itemID or 0) < (b.itemID or 0)
end

local function RebuildGroupedResults()
    local db = DB()
    local hidden = GetCharHidden()
    local showHidden = (db.showHidden == true)
    local emptyTrinket = HasEmptyTrinketSlot()

    local bySlot = {}
    local all = {}
    local bestBySlot = {}

    for _, def in ipairs(SLOT_DEFS) do
        if def.key ~= "all" then
            bySlot[def.key] = {}
        end
    end

    for _, entry in pairs(state.resultsByID or {}) do
        local isHidden = (hidden[entry.itemID] == true)
        if showHidden or not isHidden then
            entry.isHidden = isHidden
            local list = bySlot[entry.slotKey]
            if list then
                list[#list + 1] = entry
            end
            if not entry.isUnrated or emptyTrinket then
                all[#all + 1] = entry
            end
        end
    end

    for k, list in pairs(bySlot) do
        if k == "trinket" then
            table.sort(list, CompareTrinkets)
        else
            table.sort(list, CompareUpgrades)
            if list[1] then
                bestBySlot[k] = list[1]
            end
        end
    end
    table.sort(all, CompareUpgrades)

    state.results.bySlot = bySlot
    state.results.all = all
    state.results.bestBySlot = bestBySlot
end

local function QueueMissingItemLoad(itemID)
    if state.pendingLoadSet[itemID] then return end
    state.pendingLoadSet[itemID] = true
    state.pendingLoadCount = state.pendingLoadCount + 1
    state.pendingLoadQueue[#state.pendingLoadQueue + 1] = itemID
end

local function EvaluateCandidateItem(itemID, ctx, minLvl, maxLvl, equipOnly)
    local entry, needsLoad = BuildUpgradeEntry(itemID, ctx, minLvl, maxLvl, equipOnly)
    if needsLoad then
        QueueMissingItemLoad(itemID)
        return false
    end
    state.evaluatedInScan[itemID] = true
    state.resultsByID = state.resultsByID or {}
    if entry then
        state.resultsByID[itemID] = entry
        return true
    else
        state.resultsByID[itemID] = nil
        return false
    end
end

local RefreshUI

local function SetItemHidden(itemID, hide)
    if not itemID then return end
    local hidden = GetCharHidden()
    if hide then
        hidden[itemID] = true
    else
        hidden[itemID] = nil
    end
    RebuildGroupedResults()
    if RefreshUI and ui.frame and ui.frame:IsShown() then
        RefreshUI()
    end
end

local function ClearAllHidden()
    local hidden = GetCharHidden()
    wipe(hidden)
    DB().showHidden = false
    RebuildGroupedResults()
    if RefreshUI and ui.frame and ui.frame:IsShown() then
        RefreshUI()
    end
end

local function ScheduleUIRefresh()
    if state.refreshPending then return end
    state.refreshPending = true
    local flush = function()
        state.refreshPending = false
        RebuildGroupedResults()
        if RefreshUI and ui.frame and ui.frame:IsShown() then
            RefreshUI()
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.15, flush)
    else
        flush()
    end
end

local function PumpPendingItemLoads(serial)
    if state.scanSerial ~= serial or state.loadPumpActive then return end
    local queue = state.pendingLoadQueue
    if not queue or #queue == 0 then
        state.loadDrainCompleted = true
        return
    end

    state.loadPumpActive = true
    local cursor = 1
    local function Step()
        if state.scanSerial ~= serial then
            state.loadPumpActive = false
            return
        end
        if InCombatLockdown and InCombatLockdown() then
            if C_Timer and C_Timer.After then
                C_Timer.After(0.5, Step)
            end
            return
        end
        local sent = 0
        while cursor <= #queue and sent < CONST.LOAD_BATCH_SIZE do
            local itemID = queue[cursor]
            cursor = cursor + 1
            if state.pendingLoadSet[itemID] then
                if common and common.request_item_load then
                    common.request_item_load(itemID)
                elseif _G.C_Item and _G.C_Item.RequestLoadItemDataByID then
                    _G.C_Item.RequestLoadItemDataByID(itemID)
                end
                sent = sent + 1
            end
        end
        if cursor <= #queue and C_Timer and C_Timer.After then
            C_Timer.After(CONST.LOAD_BATCH_DELAY, Step)
        else
            state.loadPumpActive = false
            state.loadDrainCompleted = true
            if state.pendingLoadCount > 0 and C_Timer and C_Timer.After then
                C_Timer.After(CONST.LOAD_TIMEOUT_SEC, function()
                    if state.scanSerial == serial and state.pendingLoadCount > 0 then
                        wipe(state.pendingLoadSet)
                        state.pendingLoadCount = 0
                        state.scanPhase = "done"
                        if RefreshUI and ui.frame and ui.frame:IsShown() then
                            RefreshUI()
                        end
                    end
                end)
            end
        end
    end
    Step()
end

-- ─── Coroutine Driver for QuestieDB Time-Sliced Pass ─────────────────────────
local function EnsureDriverFrame()
    if ui.driver then return ui.driver end
    local drv = CreateFrame("Frame", nil, UIParent)
    drv:Hide()
    drv:SetScript("OnUpdate", function(self)
        local co = state.coroutine
        if not co then
            self:Hide()
            return
        end
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        local ok, err = coroutine.resume(co)
        if not ok then
            state.coroutine = nil
            state.isScanning = false
            state.scanPhase = "error"
            self:Hide()
            if common and common.print and err then
                common.print("upgrades scan error: " .. LowerText(err))
            end
            return
        end
        if coroutine.status(co) == "dead" then
            state.coroutine = nil
            state.isScanning = false
            state.scanPhase = (state.pendingLoadCount > 0) and "loading" or "done"
            self:Hide()
            RebuildGroupedResults()
            if state.pendingLoadCount > 0 then
                PumpPendingItemLoads(state.scanSerial)
            end
            if RefreshUI and ui.frame and ui.frame:IsShown() then
                RefreshUI()
            end
        end
    end)
    ui.driver = drv
    return drv
end

local function RunQuestiePass(serial, ctx, db, minLvl, maxLvl, equipOnly, djQuestSeen)
    local ItemDB = _G.ItemDB
    local allIds = ItemDB.GetAllIds()
    if type(allIds) ~= "table" or #allIds == 0 then return end

    state.scanTotal = #allIds
    state.scanProgress = 0
    state.scanPhase = "scanning"

    local wantQuest  = db.sources.quest == true
    local wantVendor = db.sources.vendor == true
    local questEvalCache  = {}
    local vendorEvalCache = {}

    local sliceStart = debugprofilestop and debugprofilestop() or 0
    local processedInSlice = 0
    local batchHits = 0

    for i = 1, #allIds do
        if state.scanSerial ~= serial then return end
        local itemID = allIds[i]
        state.scanProgress = i
        processedInSlice = processedInSlice + 1

        if CanClassWearInstant(itemID, ctx.classFile, ctx.activeSpecID) then
            local itemReq = (ItemDB.requiredLevel and ItemDB.requiredLevel(itemID)) or 0
            local itemIlvl = (ItemDB.itemLevel and ItemDB.itemLevel(itemID)) or 0

            local reqOK = true
            if itemReq > 0 then
                if itemReq > maxLvl or itemReq < (minLvl - 3) then
                    reqOK = false
                elseif equipOnly and itemReq > ctx.playerLevel then
                    reqOK = false
                end
            elseif itemIlvl > 0 then
                if itemIlvl < (minLvl - 8) or itemIlvl > (maxLvl + 14) then
                    reqOK = false
                end
            end

            if reqOK then
                local added = false

                if wantQuest and ItemDB.questRewards then
                    local qIds = ItemDB.questRewards(itemID)
                    if type(qIds) == "table" then
                        for _, qID in ipairs(qIds) do
                            if not djQuestSeen[qID] then
                                local qSrc = EvaluateQuestieQuest(qID, ctx, equipOnly, minLvl, maxLvl, questEvalCache)
                                if qSrc then
                                    if AddCandidateSource(state.candidates, state.sourceDedup, itemID, qSrc) then
                                        added = true
                                    end
                                end
                            end
                        end
                    end
                end

                if wantVendor and ItemDB.vendors then
                    local vendorLvlOK = (itemReq > 0 and itemReq >= minLvl and itemReq <= maxLvl)
                        or (itemReq == 0 and itemIlvl >= minLvl and itemIlvl <= (maxLvl + 5))
                    if vendorLvlOK then
                        local vIds = ItemDB.vendors(itemID)
                        if type(vIds) == "table" then
                            for _, npcID in ipairs(vIds) do
                                local vSrc = EvaluateQuestieVendor(npcID, ctx, vendorEvalCache)
                                if vSrc then
                                    if AddCandidateSource(state.candidates, state.sourceDedup, itemID, vSrc) then
                                        added = true
                                    end
                                end
                            end
                        end
                    end
                end

                if added and not state.evaluatedInScan[itemID] and not state.pendingLoadSet[itemID] then
                    if EvaluateCandidateItem(itemID, ctx, minLvl, maxLvl, equipOnly) then
                        batchHits = batchHits + 1
                    end
                end
            end
        end

        local shouldYield = false
        if debugprofilestop then
            if (debugprofilestop() - sliceStart) >= CONST.SCAN_BUDGET_MS then
                shouldYield = true
            end
        elseif processedInSlice >= CONST.SCAN_FALLBACK_STEP then
            shouldYield = true
        end

        if shouldYield and i < #allIds then
            if batchHits > 0 then
                batchHits = 0
                RebuildGroupedResults()
            end
            if RefreshUI and ui.frame and ui.frame:IsShown() then
                RefreshUI()
            end
            coroutine.yield()
            if state.scanSerial ~= serial then return end
            sliceStart = debugprofilestop and debugprofilestop() or 0
            processedInSlice = 0
        end
    end
end

local function StartScan(force)
    if InCombatLockdown and InCombatLockdown() then
        state.isDirty = true
        if RefreshUI and ui.frame and ui.frame:IsShown() then
            RefreshUI()
        end
        return
    end

    local db = DB()
    local ctx = GetPlayerContext()
    local filterSig = MakeFilterSig(db)

    if not force and not state.isDirty and state.lastContextSig == ctx.contextSig and state.lastFilterSig == filterSig then
        if RefreshUI and ui.frame and ui.frame:IsShown() then
            RefreshUI()
        end
        return
    end

    state.scanSerial = state.scanSerial + 1
    local serial = state.scanSerial

    state.isDirty = false
    state.lastContextSig = ctx.contextSig
    state.lastFilterSig = filterSig
    state.lastContext = ctx

    local minLvl, maxLvl, equipOnly = GetLevelWindow(db, ctx.playerLevel)
    state.lastMinLvl = minLvl
    state.lastMaxLvl = maxLvl
    state.lastEquipOnly = equipOnly

    state.candidates = {}
    state.sourceDedup = {}
    state.evaluatedInScan = {}
    state.resultsByID = {}
    state.pendingLoadQueue = {}
    state.pendingLoadSet = {}
    state.pendingLoadCount = 0
    state.loadDrainCompleted = false
    state.loadPumpActive = false
    state.coroutine = nil
    state.results = { bySlot = {}, all = {}, bestBySlot = {} }

    local djQuestSeen = {}
    BuildDungeonCandidates(ctx, db, minLvl, maxLvl, equipOnly, state.candidates, state.sourceDedup, djQuestSeen)

    for itemID in pairs(state.candidates) do
        EvaluateCandidateItem(itemID, ctx, minLvl, maxLvl, equipOnly)
    end
    RebuildGroupedResults()

    if HasQuestieDB() and (db.sources.quest or db.sources.vendor) then
        state.isScanning = true
        state.scanPhase = "scanning"
        state.coroutine = coroutine.create(function()
            RunQuestiePass(serial, ctx, db, minLvl, maxLvl, equipOnly, djQuestSeen)
        end)
        EnsureDriverFrame():Show()
    else
        state.isScanning = false
        state.scanPhase = (state.pendingLoadCount > 0) and "loading" or "done"
        if state.pendingLoadCount > 0 then
            PumpPendingItemLoads(serial)
        end
    end

    if RefreshUI and ui.frame and ui.frame:IsShown() then
        RefreshUI()
    end
end

-- ─── Formatting & Source Actions ──────────────────────────────────────────────
local function FormatPct(pct)
    if not pct then return "" end
    if pct >= 10 then
        return string.format("+%d%%", math.floor(pct + 0.5))
    end
    return string.format("+%.1f%%", pct)
end

local function FormatSourceSummary(src)
    if not src then return "" end
    if src.kind == "dungeon" then
        local text = "dungeon · " .. tostring(src.dungeonName or "?") .. " · " .. tostring(src.bossName or "boss")
        if src.dropRate and src.dropRate > 0 then
            text = text .. string.format(" (%d%%)", src.dropRate)
        end
        return text
    elseif src.kind == "quest" then
        local text = "quest · " .. tostring(src.questName or "?")
        if src.questLevel and src.questLevel > 0 then
            text = text .. " · lvl " .. tostring(src.questLevel)
        end
        if src.fromDJ and src.dungeonName and src.dungeonName ~= "" then
            text = text .. " (" .. src.dungeonName .. ")"
        elseif src.zoneName and src.zoneName ~= "" then
            text = text .. " (" .. src.zoneName .. ")"
        end
        if src.hasPrereq then
            text = text .. " · chain"
        end
        return text
    elseif src.kind == "vendor" then
        local text = "vendor · " .. tostring(src.npcName or "vendor")
        if src.zoneName and src.zoneName ~= "" then
            text = text .. " · " .. src.zoneName
        end
        return text
    end
    return LowerText(src.kind or "")
end

local function CanRunAction(src)
    if not src then return false, nil end
    if src.kind == "dungeon" and sfui.dungeonjournal and (sfui.dungeonjournal.OpenToBoss or sfui.dungeonjournal.SelectDungeon) then
        return true, "journal"
    end
    if src.kind == "quest" and src.fromDJ and sfui.dungeonjournal and (sfui.dungeonjournal.OpenToQuest or sfui.dungeonjournal.SelectDungeon) then
        return true, "journal"
    end
    local wp = src.coords or src.entrance
    if wp and wp.mapID and wp.x and wp.y and sfui.map and sfui.map.SetUserWaypoint then
        return true, "way"
    end
    return false, nil
end

local function ExecuteSourceAction(src, mouseButton)
    if not src then return false end
    local wp = src.coords or src.entrance
    if mouseButton == "RightButton" then
        if wp and wp.mapID and wp.x and wp.y and sfui.map and sfui.map.SetUserWaypoint then
            local lbl = (src.kind == "dungeon" and (src.dungeonName or src.bossName))
                or src.questName or src.npcName or "upgrade"
            sfui.map.SetUserWaypoint(wp.mapID, wp.x, wp.y, LowerText(lbl))
            return true
        end
        return false
    end

    if src.kind == "dungeon" and sfui.dungeonjournal then
        if sfui.dungeonjournal.OpenToBoss and src.bossName and src.dungeonID then
            if sfui.dungeonjournal.OpenToBoss(src.bossName, src.dungeonID) then
                return true
            end
        end
        if sfui.dungeonjournal.SelectDungeon and src.dungeonID then
            sfui.dungeonjournal.SelectDungeon(src.dungeonID, "bosses", true)
            return true
        end
    elseif src.kind == "quest" and src.fromDJ and sfui.dungeonjournal then
        if sfui.dungeonjournal.OpenToQuest and src.questID then
            sfui.dungeonjournal.OpenToQuest(src.questID)
            return true
        elseif sfui.dungeonjournal.SelectDungeon and src.dungeonID then
            sfui.dungeonjournal.SelectDungeon(src.dungeonID, "quests", true)
            return true
        end
    end

    if wp and wp.mapID and wp.x and wp.y and sfui.map and sfui.map.SetUserWaypoint then
        local lbl = src.questName or src.npcName or src.dungeonName or "upgrade"
        sfui.map.SetUserWaypoint(wp.mapID, wp.x, wp.y, LowerText(lbl))
        return true
    end
    return false
end

-- ─── Theme & Visual Styling ───────────────────────────────────────────────────
local function GetFontPath()
    return (sfui.config and sfui.config.fontFile) or "Fonts\\FRIZQT__.TTF"
end

local function ApplyRowTheme(frame, pal)
    if not frame or not pal then return end
    local acc = pal.accentColor or { 0.85, 0.72, 0.42 }
    if ui.contextLabel and ui.contextLabel.SetTextColor then
        ui.contextLabel:SetTextColor(acc[1], acc[2], acc[3], 1)
    end
    for _, pane in ipairs({ ui.leftRail, ui.rightPane }) do
        if pane and theme and theme.ApplyContainerStyle then
            theme.ApplyContainerStyle(pane)
        end
    end
    local db = DB()
    if ui.sourceBtns then
        for kind, btn in pairs(ui.sourceBtns) do
            local on = (db.sources[kind] == true)
            if theme and theme.SetButtonSelected then
                theme.SetButtonSelected(btn, on)
            end
        end
    end
    if ui.hiddenBtn and theme and theme.SetButtonSelected then
        theme.SetButtonSelected(ui.hiddenBtn, db.showHidden == true)
    end
end

local function UpdateFilterVisuals()
    local db = DB()
    local hasQDB = HasQuestieDB()

    if ui.levelDrop and ui.levelDrop.SetSelectedValue then
        ui.levelDrop:SetSelectedValue(db.levelFilter)
    end

    if ui.hiddenBtn then
        local hiddenCount = CountHidden()
        ui.hiddenBtn:SetText(hiddenCount > 0 and ("hidden (" .. tostring(hiddenCount) .. ")") or "hidden")
        if theme and theme.SetButtonSelected then
            theme.SetButtonSelected(ui.hiddenBtn, db.showHidden == true)
        end
        ui.hiddenBtn:SetAlpha((hiddenCount == 0 and not db.showHidden) and 0.65 or 1.0)
    end

    if ui.sourceBtns then
        for kind, btn in pairs(ui.sourceBtns) do
            local on = (db.sources[kind] == true)
            local available = (kind == "dungeon") or (kind == "quest") or hasQDB
            if theme and theme.SetButtonSelected then
                theme.SetButtonSelected(btn, on and available)
            end
            btn:SetAlpha(available and 1.0 or 0.45)
        end
    end
end

local function AcquireRow(idx)
    if ui.rowPool[idx] then
        return ui.rowPool[idx]
    end

    local row = CreateFrame("Button", nil, ui.scrollChild, "BackdropTemplate")
    row:SetHeight(CONST.ROW_H)
    if common and common.apply_flat_backdrop then
        common.apply_flat_backdrop(row, { 0.06, 0.06, 0.08, 0.72 }, { 0.14, 0.14, 0.18, 0.7 })
    end

    local hi = row:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetColorTexture(1, 1, 1, 0.05)

    local icoFrame = CreateFrame("Frame", nil, row, "BackdropTemplate")
    icoFrame:SetSize(36, 36)
    icoFrame:SetPoint("LEFT", row, "LEFT", 6, 0)
    if common and common.apply_flat_backdrop then
        common.apply_flat_backdrop(icoFrame, { 0.03, 0.03, 0.04, 0.95 }, { 0.35, 0.35, 0.35, 1 })
    end
    local ico = icoFrame:CreateTexture(nil, "ARTWORK")
    ico:SetPoint("TOPLEFT", icoFrame, "TOPLEFT", 1, -1)
    ico:SetPoint("BOTTOMRIGHT", icoFrame, "BOTTOMRIGHT", -1, 1)
    ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icoFrame = icoFrame
    row.icon = ico

    local actionBtn = common.create_flat_button(row, "way", 56, 20)
    actionBtn:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.actionBtn = actionBtn

    local pctFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pctFS:SetFont(GetFontPath(), 12, "")
    pctFS:SetShadowOffset(0, 0)
    pctFS:SetPoint("RIGHT", actionBtn, "LEFT", -8, 0)
    pctFS:SetJustifyH("RIGHT")
    pctFS:SetWidth(54)
    row.pctText = pctFS

    local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameFS:SetFont(GetFontPath(), 11, "")
    nameFS:SetShadowOffset(0, 0)
    nameFS:SetPoint("TOPLEFT", icoFrame, "TOPRIGHT", 8, -3)
    nameFS:SetPoint("RIGHT", pctFS, "LEFT", -6, 0)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(false)
    row.nameText = nameFS

    local srcFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    srcFS:SetFont(GetFontPath(), 10, "")
    srcFS:SetShadowOffset(0, 0)
    srcFS:SetPoint("BOTTOMLEFT", icoFrame, "BOTTOMRIGHT", 8, 3)
    srcFS:SetPoint("RIGHT", pctFS, "LEFT", -6, 0)
    srcFS:SetJustifyH("LEFT")
    srcFS:SetWordWrap(false)
    srcFS:SetTextColor(0.68, 0.68, 0.72, 1)
    row.srcText = srcFS

    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, mouseBtn)
        local entry = self.entry
        if not entry then return end
        if mouseBtn == "RightButton" then
            SetItemHidden(entry.itemID, not IsItemHidden(entry.itemID))
            if common and common.hide_tooltip then common.hide_tooltip() end
            return
        end
        if IsShiftKeyDown and IsShiftKeyDown() and entry.link and _G.ChatEdit_InsertLink then
            _G.ChatEdit_InsertLink(entry.link)
        end
    end)

    row:SetScript("OnEnter", function(self)
        local entry = self.entry
        if not entry or not entry.itemID then return end
        local tip = (common and common.get_tooltip and common.get_tooltip()) or _G.GameTooltip
        if not tip then return end
        tip:SetOwner(self, "ANCHOR_RIGHT")
        if entry.link and entry.link:find("|H", 1, true) and tip.SetHyperlink then
            tip:SetHyperlink(entry.link)
        elseif tip.SetItemByID then
            tip:SetItemByID(entry.itemID)
        elseif tip.SetHyperlink then
            tip:SetHyperlink("item:" .. tostring(entry.itemID))
        end
        tip:AddLine(" ")
        if entry.isUnrated then
            tip:AddLine("trinket · ilvl " .. tostring(entry.ilvl or 0) .. " (unrated)", 0.75, 0.82, 0.95)
        else
            tip:AddLine("upgrade: " .. FormatPct(entry.pctGain) .. " (" .. LowerText(entry.roleLabel or "dps") .. ")", 0.35, 0.95, 0.45)
        end
        for i = 1, math.min(#entry.sources, 5) do
            tip:AddLine(FormatSourceSummary(entry.sources[i]), 0.78, 0.78, 0.82, true)
        end
        if #entry.sources > 5 then
            tip:AddLine("+" .. tostring(#entry.sources - 5) .. " more sources", 0.6, 0.6, 0.6)
        end
        tip:AddLine("shift-click to link in chat", 0.5, 0.75, 0.95)
        if entry.isHidden then
            tip:AddLine("right-click to restore item", 0.55, 0.90, 0.55)
        else
            tip:AddLine("right-click to hide item", 0.85, 0.60, 0.60)
        end
        tip:Show()
    end)
    row:SetScript("OnLeave", function()
        if common and common.hide_tooltip then common.hide_tooltip() end
    end)

    actionBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    actionBtn:SetScript("OnClick", function(self, btn)
        local src = self.src
        if src then
            ExecuteSourceAction(src, btn)
        end
    end)
    actionBtn:SetScript("OnEnter", function(self)
        local src = self.src
        if not src then return end
        local tip = (common and common.get_tooltip and common.get_tooltip()) or _G.GameTooltip
        if not tip then return end
        tip:SetOwner(self, "ANCHOR_TOP")
        if self.actionKind == "journal" then
            tip:AddLine("open in dungeon journal", 1, 0.82, 0.2)
            tip:AddLine("left-click: view in sfui dungeon journal", 0.8, 0.8, 0.8)
            local wp = src.coords or src.entrance
            if wp and wp.mapID then
                tip:AddLine("right-click: set navigation waypoint", 0.4, 0.85, 1.0)
            end
        else
            tip:AddLine("set navigation waypoint", 1, 0.82, 0.2)
            tip:AddLine("left-click: track location on map & compass", 0.8, 0.8, 0.8)
        end
        tip:Show()
    end)
    actionBtn:SetScript("OnLeave", function()
        if common and common.hide_tooltip then common.hide_tooltip() end
    end)

    ui.rowPool[idx] = row
    return row
end

RefreshUI = function()
    if not ui.frame or not ui.frame:IsShown() then return end
    local db = DB()
    local pal = (theme and theme.GetPalette and theme.GetPalette()) or {}
    local acc = pal.accentColor or { 0.85, 0.72, 0.42 }
    local ctx = state.lastContext or GetPlayerContext()

    UpdateFilterVisuals()

    if ui.contextLabel then
        ui.contextLabel:SetText("lvl " .. tostring(ctx.playerLevel) .. " · " .. LowerText(ctx.roleLabel or "dps"))
    end

    if ui.statusLabel then
        if InCombatLockdown and InCombatLockdown() and state.isDirty then
            ui.statusLabel:SetText("|cffff9944in combat — scan paused until combat ends|r")
        elseif state.isScanning and state.scanTotal > 0 then
            local pct = math.floor((state.scanProgress / state.scanTotal) * 100)
            ui.statusLabel:SetText(string.format("|cff88ccffscanning questiedb... %d%% (%d upgrades)|r", pct, #state.results.all))
        elseif state.pendingLoadCount > 0 then
            ui.statusLabel:SetText(string.format("|cff88ccffloading %d items... (%d upgrades)|r", state.pendingLoadCount, #state.results.all))
        else
            local suffix = HasQuestieDB() and "" or " · questiedb not loaded (dungeon journal only)"
            local rangeDesc = (db.levelFilter == "all_equippable")
                and string.format("all equippable (lvl 1-%d)", state.lastMaxLvl)
                or string.format("lvl %d-%d", state.lastMinLvl, state.lastMaxLvl)
            ui.statusLabel:SetText(string.format("%d upgrades · %s · %s%s",
                #state.results.all, rangeDesc, LowerText(ctx.roleLabel or "dps"), suffix))
        end
    end

    local selectedSlot = db.selectedSlot
    if not SLOT_KEY_TO_DEF[selectedSlot] then
        selectedSlot = "all"
        db.selectedSlot = "all"
    end

    for _, def in ipairs(SLOT_DEFS) do
        local btn = ui.slotBtns[def.key]
        if btn then
            local isSel = (def.key == selectedSlot)
            if isSel then
                btn:SetBackdropBorderColor(acc[1], acc[2], acc[3], 1)
                btn:SetBackdropColor(acc[1] * 0.22, acc[2] * 0.22, acc[3] * 0.22, 0.92)
            else
                btn:SetBackdropBorderColor(0.16, 0.16, 0.20, 0.65)
                btn:SetBackdropColor(0.06, 0.06, 0.08, 0.72)
            end

            if def.key == "all" then
                btn.badgeText:SetText("(" .. tostring(#state.results.all) .. ")")
                if #state.results.all > 0 then
                    btn.badgeText:SetTextColor(acc[1], acc[2], acc[3], 1)
                else
                    btn.badgeText:SetTextColor(0.5, 0.5, 0.55, 1)
                end
            else
                local eqTex, eqIlvl = nil, 0
                if def.slotIDs then
                    local bestEqIlvl = nil
                    for _, sID in ipairs(def.slotIDs) do
                        local link = GetInventoryItemLink and GetInventoryItemLink("player", sID)
                        local tex = GetInventoryItemTexture and GetInventoryItemTexture("player", sID)
                        local ilvl = link and SafeGetItemLevel(link, 0) or 0
                        if not bestEqIlvl or ilvl < bestEqIlvl then
                            bestEqIlvl = ilvl
                            eqIlvl = ilvl
                            eqTex = tex
                        end
                    end
                end
                if eqTex then
                    btn.icon:SetTexture(eqTex)
                    btn.icon:SetAlpha(1.0)
                else
                    btn.icon:SetTexture(nil)
                    btn.icon:SetAlpha(0.15)
                end
                if eqIlvl > 0 then
                    btn.ilvlText:SetText("i" .. tostring(eqIlvl))
                else
                    btn.ilvlText:SetText("")
                end

                if def.key == "trinket" then
                    local tCount = #(state.results.bySlot.trinket or {})
                    if tCount > 0 then
                        btn.badgeText:SetText("(" .. tostring(tCount) .. ")")
                        if HasEmptyTrinketSlot() then
                            btn.badgeText:SetTextColor(0.32, 0.95, 0.42, 1)
                        else
                            btn.badgeText:SetTextColor(acc[1], acc[2], acc[3], 1)
                        end
                    else
                        btn.badgeText:SetText("-")
                        btn.badgeText:SetTextColor(0.45, 0.45, 0.50, 1)
                    end
                else
                    local best = state.results.bestBySlot[def.key]
                    if best then
                        btn.badgeText:SetText(FormatPct(best.pctGain))
                        if best.requiresHigherLevel then
                            btn.badgeText:SetTextColor(0.65, 0.85, 0.45, 1)
                        else
                            btn.badgeText:SetTextColor(0.32, 0.95, 0.42, 1)
                        end
                    else
                        btn.badgeText:SetText("-")
                        btn.badgeText:SetTextColor(0.45, 0.45, 0.50, 1)
                    end
                end
            end
        end
    end

    local list = (selectedSlot == "all") and state.results.all or (state.results.bySlot[selectedSlot] or {})
    local yOfs = 0
    local showSlotTag = (selectedSlot == "all")

    for i = 1, #list do
        local entry = list[i]
        local row = AcquireRow(i)
        row.entry = entry
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", ui.scrollChild, "TOPLEFT", 2, -yOfs)
        row:SetPoint("TOPRIGHT", ui.scrollChild, "TOPRIGHT", -2, -yOfs)

        local altBg = (i % 2 == 0) and 0.08 or 0.055
        row:SetBackdropColor(altBg, altBg, altBg + 0.02, 0.78)
        row:SetAlpha(entry.isHidden and 0.50 or 1.0)

        row.icon:SetTexture(entry.icon or 134400)
        local qr, qg, qb = 1, 1, 1
        if common and common.get_item_quality_color then
            qr, qg, qb = common.get_item_quality_color(entry.quality or 1)
        end
        row.icoFrame:SetBackdropBorderColor(qr, qg, qb, 0.95)

        local title = string.format("|cff%02x%02x%02x%s|r",
            math.floor(qr * 255), math.floor(qg * 255), math.floor(qb * 255),
            entry.name or ("item #" .. tostring(entry.itemID)))

        if showSlotTag then
            local slotDef = SLOT_KEY_TO_DEF[entry.slotKey]
            local sLbl = (slotDef and slotDef.label) or entry.slotKey or ""
            title = title .. "  |cff7a99bb[" .. sLbl .. "]|r"
        end
        if entry.reqLevel and entry.reqLevel > 0 then
            if entry.requiresHigherLevel then
                title = title .. "  |cffffbb44lvl " .. tostring(entry.reqLevel) .. "|r"
            else
                title = title .. "  |cff888888lvl " .. tostring(entry.reqLevel) .. "|r"
            end
        end
        if entry.isHidden then
            title = title .. "  |cffaa6666[hidden]|r"
        end
        row.nameText:SetText(title)

        local primarySrc = entry.sources and entry.sources[1]
        local srcLine = primarySrc and FormatSourceSummary(primarySrc) or "unknown source"
        if entry.sources and #entry.sources > 1 then
            srcLine = srcLine .. " |cff88aacc(+" .. tostring(#entry.sources - 1) .. ")|r"
        end
        row.srcText:SetText(srcLine)

        if entry.isUnrated then
            row.pctText:SetText("ilvl " .. tostring(entry.ilvl or 0))
            if entry.requiresHigherLevel then
                row.pctText:SetTextColor(0.78, 0.70, 0.48, 1)
            else
                row.pctText:SetTextColor(0.75, 0.82, 0.95, 1)
            end
        else
            row.pctText:SetText(FormatPct(entry.pctGain))
            if entry.requiresHigherLevel then
                row.pctText:SetTextColor(0.65, 0.85, 0.45, 1)
            else
                row.pctText:SetTextColor(0.32, 0.95, 0.42, 1)
            end
        end

        local canAct, actLabel = CanRunAction(primarySrc)
        if canAct then
            row.actionBtn.src = primarySrc
            row.actionBtn.actionKind = actLabel
            row.actionBtn:SetText(actLabel)
            row.actionBtn:Show()
        else
            row.actionBtn.src = nil
            row.actionBtn.actionKind = nil
            row.actionBtn:Hide()
        end

        row:Show()
        yOfs = yOfs + CONST.ROW_H + CONST.ROW_GAP
    end

    for i = #list + 1, #ui.rowPool do
        ui.rowPool[i]:Hide()
    end

    ui.scrollChild:SetHeight(math.max(1, yOfs))

    if ui.emptyText then
        if #list == 0 then
            if state.isScanning or state.pendingLoadCount > 0 then
                ui.emptyText:SetText("scanning for upgrades in your level range...")
            elseif not db.sources.dungeon and not db.sources.quest and not db.sources.vendor then
                ui.emptyText:SetText("all upgrade sources are disabled")
            elseif selectedSlot == "trinket" then
                ui.emptyText:SetText("no available trinkets in this level range")
            else
                ui.emptyText:SetText("no upgrades found in this slot / level range")
            end
            ui.emptyText:Show()
        else
            ui.emptyText:Hide()
        end
    end
end

-- ─── Window Construction ──────────────────────────────────────────────────────
local function CreateUpgradesWindow()
    if ui.frame then return ui.frame end

    local db = DB()
    local f
    if theme and theme.create_window then
        f = theme.create_window("SfuiGearUpgradesFrame", CONST.FRAME_W, CONST.FRAME_H, "gear upgrades", { closeSize = 22 })
    else
        f = CreateFrame("Frame", "SfuiGearUpgradesFrame", UIParent, "BackdropTemplate")
        f:SetSize(CONST.FRAME_W, CONST.FRAME_H)
        f:SetPoint("CENTER")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        if common and common.register_special_frame then common.register_special_frame(f) end
    end

    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    if db.pos and db.pos.point then
        f:ClearAllPoints()
        f:SetPoint(db.pos.point, UIParent, db.pos.relPoint or "CENTER", db.pos.x or 0, db.pos.y or 0)
    end
    f:HookScript("OnDragStop", function(self)
        local point, _, relPoint, x, y = self:GetPoint()
        if point then
            DB().pos = { point = point, relPoint = relPoint, x = x, y = y }
        end
    end)

    -- ── Filter Bar ──
    local filterBar = CreateFrame("Frame", nil, f)
    filterBar:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -38)
    filterBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -38)
    filterBar:SetHeight(26)
    filterBar:SetFrameLevel((f:GetFrameLevel() or 1) + 5)

    local contextLabel = filterBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    contextLabel:SetFont(GetFontPath(), 11, "")
    contextLabel:SetShadowOffset(0, 0)
    contextLabel:SetPoint("LEFT", filterBar, "LEFT", 2, 0)
    ui.contextLabel = contextLabel

    local levelDrop = common.create_dropdown(filterBar, 148, LEVEL_FILTER_OPTIONS, function(val)
        if LEVEL_FILTER_BY_ID[val] then
            DB().levelFilter = val
            StartScan(true)
        end
    end, db.levelFilter, nil, 176)
    levelDrop:SetPoint("LEFT", contextLabel, "RIGHT", 10, 0)
    levelDrop.tooltip = "choose which character level range to search for upgrades"
    ui.levelDrop = levelDrop

    local scanBtn = common.create_flat_button(filterBar, "scan", 46, 20)
    scanBtn:SetPoint("RIGHT", filterBar, "RIGHT", -2, 0)
    scanBtn:SetScript("OnClick", function()
        StartScan(true)
    end)
    ui.scanBtn = scanBtn

    ui.sourceBtns = {}
    local sourceDefs = {
        { kind = "vendor",  w = 56, desc = "vendors from questiedb" },
        { kind = "quest",   w = 50, desc = "dungeon & world quest rewards" },
        { kind = "dungeon", w = 64, desc = "boss drops from sfui dungeon journal" },
    }
    local anchorRight = scanBtn
    for _, sDef in ipairs(sourceDefs) do
        local sBtn = common.create_flat_button(filterBar, sDef.kind, sDef.w, 20)
        sBtn:SetPoint("RIGHT", anchorRight, "LEFT", -4, 0)
        sBtn:SetScript("OnClick", function()
            local udb = DB()
            udb.sources[sDef.kind] = not udb.sources[sDef.kind]
            StartScan(true)
        end)
        sBtn:SetScript("OnEnter", function(self)
            local tip = (common and common.get_tooltip and common.get_tooltip()) or _G.GameTooltip
            if not tip then return end
            tip:SetOwner(self, "ANCHOR_TOP")
            tip:AddLine(sDef.kind .. " source", 1, 0.82, 0.2)
            tip:AddLine(sDef.desc, 0.8, 0.8, 0.8)
            if sDef.kind == "vendor" and not HasQuestieDB() then
                tip:AddLine("requires questiedb addon", 1, 0.35, 0.35)
            end
            tip:Show()
        end)
        sBtn:SetScript("OnLeave", function()
            if common and common.hide_tooltip then common.hide_tooltip() end
        end)
        ui.sourceBtns[sDef.kind] = sBtn
        anchorRight = sBtn
    end

    local hiddenBtn = common.create_flat_button(filterBar, "hidden", 78, 20)
    hiddenBtn:SetPoint("RIGHT", ui.sourceBtns.dungeon, "LEFT", -8, 0)
    hiddenBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    hiddenBtn:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" then
            ClearAllHidden()
        else
            local udb = DB()
            udb.showHidden = not udb.showHidden
            RebuildGroupedResults()
            RefreshUI()
        end
    end)
    hiddenBtn:SetScript("OnEnter", function(self)
        local tip = (common and common.get_tooltip and common.get_tooltip()) or _G.GameTooltip
        if not tip then return end
        tip:SetOwner(self, "ANCHOR_TOP")
        tip:AddLine("hidden items", 1, 0.82, 0.2)
        tip:AddLine("left-click: toggle showing hidden items", 0.8, 0.8, 0.8)
        tip:AddLine("right-click: restore all hidden items", 0.8, 0.8, 0.8)
        tip:Show()
    end)
    hiddenBtn:SetScript("OnLeave", function()
        if common and common.hide_tooltip then common.hide_tooltip() end
    end)
    ui.hiddenBtn = hiddenBtn

    -- ── Status Line ──
    local statusLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusLabel:SetFont(GetFontPath(), 10, "")
    statusLabel:SetShadowOffset(0, 0)
    statusLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -66)
    statusLabel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -66)
    statusLabel:SetJustifyH("LEFT")
    statusLabel:SetWordWrap(false)
    statusLabel:SetTextColor(0.68, 0.68, 0.72, 1)
    ui.statusLabel = statusLabel

    -- ── Left Slot Rail ──
    local leftRail = CreateFrame("Frame", nil, f, "BackdropTemplate")
    leftRail:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -84)
    leftRail:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)
    leftRail:SetWidth(CONST.RAIL_W)
    leftRail:SetFrameLevel((f:GetFrameLevel() or 1) + 2)
    if theme and theme.ApplyContainerStyle then
        theme.ApplyContainerStyle(leftRail)
    elseif common and common.apply_flat_backdrop then
        common.apply_flat_backdrop(leftRail, { 0.04, 0.04, 0.05, 0.9 }, { 0.18, 0.18, 0.22, 1 })
    end
    ui.leftRail = leftRail

    local ySlot = 4
    for _, def in ipairs(SLOT_DEFS) do
        local sBtn = CreateFrame("Button", nil, leftRail, "BackdropTemplate")
        sBtn:SetHeight(CONST.SLOT_BTN_H)
        sBtn:SetPoint("TOPLEFT", leftRail, "TOPLEFT", 4, -ySlot)
        sBtn:SetPoint("TOPRIGHT", leftRail, "TOPRIGHT", -4, -ySlot)
        if common and common.apply_flat_backdrop then
            common.apply_flat_backdrop(sBtn, { 0.06, 0.06, 0.08, 0.72 }, { 0.16, 0.16, 0.20, 0.65 })
        end

        local sHi = sBtn:CreateTexture(nil, "HIGHLIGHT")
        sHi:SetAllPoints()
        sHi:SetColorTexture(1, 1, 1, 0.05)

        if def.key ~= "all" then
            local ico = sBtn:CreateTexture(nil, "ARTWORK")
            ico:SetSize(18, 18)
            ico:SetPoint("LEFT", sBtn, "LEFT", 5, 0)
            ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            sBtn.icon = ico
        end

        local badge = sBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        badge:SetFont(GetFontPath(), 10, "")
        badge:SetShadowOffset(0, 0)
        badge:SetPoint("RIGHT", sBtn, "RIGHT", -6, 0)
        badge:SetJustifyH("RIGHT")
        sBtn.badgeText = badge

        local ilvlFS = sBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ilvlFS:SetFont(GetFontPath(), 10, "")
        ilvlFS:SetShadowOffset(0, 0)
        ilvlFS:SetPoint("RIGHT", badge, "LEFT", -6, 0)
        ilvlFS:SetTextColor(0.55, 0.55, 0.60, 1)
        sBtn.ilvlText = ilvlFS

        local lbl = sBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetFont(GetFontPath(), 11, "")
        lbl:SetShadowOffset(0, 0)
        if sBtn.icon then
            lbl:SetPoint("LEFT", sBtn.icon, "RIGHT", 6, 0)
        else
            lbl:SetPoint("LEFT", sBtn, "LEFT", 8, 0)
        end
        lbl:SetPoint("RIGHT", ilvlFS, "LEFT", -4, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)
        lbl:SetText(def.label)
        lbl:SetTextColor(0.92, 0.92, 0.95, 1)

        sBtn:SetScript("OnClick", function()
            DB().selectedSlot = def.key
            RefreshUI()
        end)
        sBtn:SetScript("OnEnter", function(self)
            local tip = (common and common.get_tooltip and common.get_tooltip()) or _G.GameTooltip
            if not tip then return end
            tip:SetOwner(self, "ANCHOR_RIGHT")
            if def.key == "all" or not def.slotIDs then
                tip:AddLine("all equipment slots", 1, 0.82, 0.2)
                tip:AddLine("shows highest % upgrades across every slot", 0.8, 0.8, 0.8)
            else
                local shownItem = false
                if tip.SetInventoryItem then
                    for _, sID in ipairs(def.slotIDs) do
                        local link = GetInventoryItemLink and GetInventoryItemLink("player", sID)
                        if link then
                            if not shownItem then
                                tip:SetInventoryItem("player", sID)
                                shownItem = true
                            else
                                local n2 = SafeGetItemInfo(link)
                                tip:AddLine("second slot: " .. LowerText(n2 or link), 0.78, 0.78, 0.82)
                            end
                        end
                    end
                end
                if not shownItem then
                    tip:AddLine(def.label .. ": empty", 0.8, 0.8, 0.8)
                end
            end
            tip:Show()
        end)
        sBtn:SetScript("OnLeave", function()
            if common and common.hide_tooltip then common.hide_tooltip() end
        end)

        ui.slotBtns[def.key] = sBtn
        ySlot = ySlot + CONST.SLOT_BTN_H + CONST.SLOT_BTN_GAP
    end

    -- ── Right Upgrade Pane ──
    local rightPane = CreateFrame("Frame", nil, f, "BackdropTemplate")
    rightPane:SetPoint("TOPLEFT", leftRail, "TOPRIGHT", 8, 0)
    rightPane:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
    rightPane:SetFrameLevel((f:GetFrameLevel() or 1) + 2)
    if theme and theme.ApplyContainerStyle then
        theme.ApplyContainerStyle(rightPane)
    elseif common and common.apply_flat_backdrop then
        common.apply_flat_backdrop(rightPane, { 0.04, 0.04, 0.05, 0.9 }, { 0.18, 0.18, 0.22, 1 })
    end
    ui.rightPane = rightPane

    local scroll, scrollChild = common.create_scroll_frame(rightPane, "SfuiGearUpgradesScroll", 520, 400)
    scroll:SetPoint("TOPLEFT", rightPane, "TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", rightPane, "BOTTOMRIGHT", -24, 6)
    scroll:SetScript("OnSizeChanged", function(self, w)
        if w and w > 0 then
            scrollChild:SetWidth(w)
        end
    end)
    ui.scroll = scroll
    ui.scrollChild = scrollChild

    local emptyText = rightPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyText:SetFont(GetFontPath(), 11, "")
    emptyText:SetShadowOffset(0, 0)
    emptyText:SetPoint("CENTER", rightPane, "CENTER", 0, 0)
    emptyText:SetTextColor(0.55, 0.55, 0.60, 1)
    emptyText:Hide()
    ui.emptyText = emptyText

    if theme and theme.RegisterWindow then
        theme.RegisterWindow(f, function(win, pal)
            if win.headerBar and theme.ApplyHeaderStyle then
                theme.ApplyHeaderStyle(win.headerBar, "gear upgrades")
            end
            if win.closeBtn and theme.ApplyCloseButtonStyle then
                theme.ApplyCloseButtonStyle(win.closeBtn)
            end
            ApplyRowTheme(win, pal)
            if win:IsShown() then
                RefreshUI()
            end
        end)
    end

    f:SetScript("OnShow", function()
        StartScan(false)
        RefreshUI()
    end)

    f:Hide()
    ui.frame = f
    U.frame = f
    return f
end

-- ─── Public API ───────────────────────────────────────────────────────────────
function U.MarkDirty()
    state.isDirty = true
    if ui.frame and ui.frame:IsShown() and not state.rescanPending then
        state.rescanPending = true
        local run = function()
            state.rescanPending = false
            if ui.frame and ui.frame:IsShown() then
                StartScan(true)
            end
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0.20, run)
        else
            run()
        end
    end
end

function U.Refresh()
    StartScan(true)
end

function U.Open(slotArg)
    if slotArg and type(slotArg) == "string" and slotArg ~= "" then
        local clean = LowerText(slotArg):gsub("^%s*(.-)%s*$", "%1")
        if SLOT_KEY_TO_DEF[clean] then
            DB().selectedSlot = clean
        end
    end
    local f = CreateUpgradesWindow()
    if f then
        f:Show()
    end
end

function U.Close()
    if ui.frame and ui.frame:IsShown() then
        ui.frame:Hide()
    end
end

function U.Toggle(slotArg)
    if ui.frame and ui.frame:IsShown() and not slotArg then
        ui.frame:Hide()
    else
        U.Open(slotArg)
    end
end

function U.GetResults()
    return state.results
end

function U.HideItem(itemID)
    SetItemHidden(itemID, true)
end

function U.UnhideItem(itemID)
    SetItemHidden(itemID, false)
end

function U.ClearHidden()
    ClearAllHidden()
end

function U.IsItemHidden(itemID)
    return IsItemHidden(itemID)
end

-- ─── Events & Messages (Zero Idle CPU When Closed) ────────────────────────────
local function OnGameEvent(event, arg1, arg2)
    if event == "ITEM_DATA_LOAD_RESULT" then
        local itemID = arg1
        local success = arg2
        if issecretvalue(itemID) or type(itemID) ~= "number" then return end
        if not state.pendingLoadSet[itemID] then return end
        state.pendingLoadSet[itemID] = nil
        state.pendingLoadCount = math.max(0, state.pendingLoadCount - 1)
        if state.pendingLoadCount == 0 and state.loadDrainCompleted and not state.isScanning then
            state.scanPhase = "done"
        end
        if success == true and state.candidates[itemID] and ui.frame and ui.frame:IsShown() and state.lastContext then
            EvaluateCandidateItem(itemID, state.lastContext, state.lastMinLvl, state.lastMaxLvl, state.lastEquipOnly)
            ScheduleUIRefresh()
        elseif ui.frame and ui.frame:IsShown() and (state.pendingLoadCount == 0 or state.pendingLoadCount % 5 == 0) then
            ScheduleUIRefresh()
        end
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if state.isDirty and ui.frame and ui.frame:IsShown() then
            StartScan(false)
        end
        return
    end

    if event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_LEVEL_UP"
        or event == "QUEST_TURNED_IN" or event == "PLAYER_TALENT_UPDATE" then
        U.MarkDirty()
    end
end

if sfui.events then
    if sfui.events.RegisterEvent then
        sfui.events.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", OnGameEvent)
        sfui.events.RegisterEvent("PLAYER_LEVEL_UP", OnGameEvent)
        sfui.events.RegisterEvent("QUEST_TURNED_IN", OnGameEvent)
        sfui.events.RegisterEvent("PLAYER_TALENT_UPDATE", OnGameEvent)
        sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", OnGameEvent)
        sfui.events.RegisterEvent("ITEM_DATA_LOAD_RESULT", OnGameEvent)
    end
    if sfui.events.RegisterMessage then
        sfui.events.RegisterMessage("SFUI_GEAR_ROLE_CHANGED", function() U.MarkDirty() end)
        sfui.events.RegisterMessage("SFUI_SPEC_CHANGED", function() U.MarkDirty() end)
    end
end

-- Expose internal helpers for verification
U._internals = {
    BitHas                 = BitHas,
    NormalizeCoords        = NormalizeCoords,
    HasQuestieDB           = HasQuestieDB,
    CanClassWearInstant    = CanClassWearInstant,
    GetLevelWindow         = GetLevelWindow,
    GetPlayerContext       = GetPlayerContext,
    BuildDungeonCandidates = BuildDungeonCandidates,
    EvaluateQuestieQuest   = EvaluateQuestieQuest,
    EvaluateQuestieVendor  = EvaluateQuestieVendor,
    EvaluateCandidateItem  = EvaluateCandidateItem,
    RebuildGroupedResults  = RebuildGroupedResults,
    StartScan              = StartScan,
    ExecuteSourceAction    = ExecuteSourceAction,
    FormatSourceSummary    = FormatSourceSummary,
    OnGameEvent            = OnGameEvent,
    CountHidden            = CountHidden,
    SetItemHidden          = SetItemHidden,
    ClearAllHidden         = ClearAllHidden,
    HasEmptyTrinketSlot    = HasEmptyTrinketSlot,
    SLOT_DEFS              = SLOT_DEFS,
    SLOT_ID_TO_KEY         = SLOT_ID_TO_KEY,
    state                  = state,
}
