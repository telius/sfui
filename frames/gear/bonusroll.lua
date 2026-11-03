local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
local sfui = _G.sfui or {}

-- Guard: Retail-only bonus roll & vault reward chest system
if not sfui.isRetail then
    return
end

sfui.bonusroll = {}

local UnitGUID      = UnitGUID
local UnitFullName  = UnitFullName
local UnitName      = UnitName
local GetRealmName  = GetRealmName
local C_TooltipInfo = C_TooltipInfo
local C_Timer       = C_Timer
local C_Item        = C_Item
local Item          = Item
local tonumber      = tonumber
local pairs         = pairs
local ipairs        = ipairs
local next          = next
local select        = select
local type          = type
local pcall         = pcall
local string        = string
local table         = table
local PlaySound     = PlaySound
local SOUNDKIT      = SOUNDKIT

-- ─── Constants & Configuration ────────────────────────────────────────────────
local POLL_INTERVAL  = 0.3
local EMPTY_ATTEMPTS = 5
local STABLE_NEEDED  = 3
local MAX_ATTEMPTS   = 10

-- ─── Reward Chest Item Database (KeystoneLoot / Voidcore / YetRolled Mappings) ─
local CHEST_DATABASE = {
    -- Dungeons (challengeModeId & instanceID)
    [268465] = { challengeModeId = 402, instanceID = 1201 }, -- Algeth'ar Academy
    [268466] = { challengeModeId = 558, instanceID = 1300 }, -- Magisters' Terrace
    [268467] = { challengeModeId = 559, instanceID = 1316 }, -- Nexus-Point Xenas
    [268468] = { challengeModeId = 556, instanceID = 278 }, -- Pit of Saron
    [268469] = { challengeModeId = 239, instanceID = 945 }, -- Seat of the Triumvirate
    [268470] = { challengeModeId = 161, instanceID = 476 }, -- Skyreach
    [268471] = { challengeModeId = 557, instanceID = 1299 }, -- Windrunner Spire
    [268473] = { challengeModeId = 560, instanceID = 1315 }, -- Maisara Caverns
    [279618] = { challengeModeId = 588, instanceID = 1322 }, -- Altar of Fangs
    [279619] = { challengeModeId = 584, instanceID = 1309 }, -- The Blinding Vale
    [279620] = { challengeModeId = 586, instanceID = 1311 }, -- Den of Nalorakk
    [279621] = { challengeModeId = 249, instanceID = 1041 }, -- Kings' Rest
    [279622] = { challengeModeId = 399, instanceID = 1202 }, -- Ruby Life Pools
    [279623] = { challengeModeId = 587, instanceID = 1304 }, -- Murder Row
    [279624] = { challengeModeId = 250, instanceID = 1030 }, -- Temple of Sethraliss
    [279625] = { challengeModeId = 585, instanceID = 1313 }, -- Voidscar Arena

    -- Raid Bosses (encounterID / bossId & instanceID)
    [262658] = { bossId = 2740, instanceID = 1308 }, -- Midnight Falls
    [267488] = { bossId = 2738, instanceID = 1307 }, -- Crown of the Cosmos
    [268458] = { bossId = 2739, instanceID = 1308 }, -- Belo'ren, Child of Al'ar
    [268459] = { bossId = 2733, instanceID = 1307 }, -- Imperator Averzian
    [268460] = { bossId = 2734, instanceID = 1307 }, -- Vorasius
    [268461] = { bossId = 2736, instanceID = 1307 }, -- Fallen-King Salhadaar
    [268462] = { bossId = 2735, instanceID = 1307 }, -- Vaelgor & Ezzorak
    [268463] = { bossId = 2737, instanceID = 1307 }, -- Lightblinded Vanguard
    [268464] = { bossId = 2795, instanceID = 1314 }, -- Chimaerus the Undreamt God
    [274708] = { bossId = 2849, instanceID = 1317 }, -- Nymrissa Wavecaller
    [275228] = { bossId = 2711, instanceID = 1305 }, -- Rotmire
    [278283] = { bossId = 2874, instanceID = 1320 }, -- Entombed Sentinels
    [278284] = { bossId = 2895, instanceID = 1320 }, -- Ula'tek
    [278285] = { bossId = 2888, instanceID = 1320 }, -- Nek'zali the Soulcoiler
    [278286] = { bossId = 2894, instanceID = 1320 }, -- The Lost Explorers
    [278287] = { bossId = 2882, instanceID = 1320 }, -- Vashnik the Malignant
    [278288] = { bossId = 2871, instanceID = 1320 }, -- Sszorak
    [278289] = { bossId = 2887, instanceID = 1320 }, -- The Twin Fangs
    [278290] = { bossId = 2883, instanceID = 1320 }, -- The Coiled Altar
    [286019] = { bossId = 2896, instanceID = 1324 }, -- Kith'ix
}

local MIRROR_ITEMS = {
    [249806] = 260235, -- Radiant Feather -> Umbral Feather
    [260235] = 249806,
}

local EXCLUDED_ITEMS = {
    [151299] = true, -- Not in the bonus roll chest (Blizzard item pool quirk)
    [260235] = true, -- Umbral Feather
    [258045] = true, -- Duskblade Glaives
    [270909] = true, -- Ula'tek non-Voidcore omni-token / curio
    [281227] = true, -- Rush'kah of the Soulwinder
    [275937] = true, -- Face of the Hexlord
    [275938] = true, -- Gaze of the Hexlord
}

local GetPlayerKey = sfui.common.get_player_unique_key
local SCAN_VERSION = 4

local sessionScannedSpecs = {}
local isScanningAll = false
local pendingScanTimer = nil
local activePrompts = {}
local recentPrompts = {}
local pendingRoll = nil

local issecretvalue = (sfui.common and sfui.common.issecretvalue) or _G.issecretvalue or function() return false end

local function IsPublicValue(val)
    return not issecretvalue(val)
end

local function CleanTooltipText(val)
    if not IsPublicValue(val) or type(val) ~= "string" then return nil end
    return (val:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function GetCurrentSeasonID()
    if _G.C_SeasonInfo and _G.C_SeasonInfo.GetCurrentDisplaySeasonID then
        local sID = _G.C_SeasonInfo.GetCurrentDisplaySeasonID()
        if sID and IsPublicValue(sID) and type(sID) == "number" and sID > 0 then
            return sID
        end
    end
    if _G.C_MythicPlus and _G.C_MythicPlus.GetCurrentSeason then
        local mID = _G.C_MythicPlus.GetCurrentSeason()
        if mID and IsPublicValue(mID) and type(mID) == "number" and mID > 0 then
            return mID
        end
    end
    return nil
end

local function IsPlayerAtMaxLevel()
    local maxLvl = (_G.GetMaxLevelForPlayerExpansion and _G.GetMaxLevelForPlayerExpansion()) or 80
    local curLvl = (_G.UnitLevel and _G.UnitLevel("player")) or 0
    return curLvl >= maxLvl
end

local function GetActiveLootSpecID()
    local lootSpec = _G.GetLootSpecialization and _G.GetLootSpecialization()
    if lootSpec and lootSpec > 0 then
        return lootSpec
    end
    return sfui.common.get_current_spec_id()
end

local function EnsureCharDB(db)
    local prevVersion = tonumber(db.scanVersion) or 0
    if prevVersion ~= SCAN_VERSION then
        db.rolledItems  = db.rolledItems or {}
        db.rolledBySpec = db.rolledBySpec or {}
        db.usedBySpec   = db.usedBySpec or {}
        db.manual       = db.manual or {}

        if prevVersion < 3 and type(db.used) == "table" then
            -- Preserve direct rolls recorded in pre-v1.127 databases where only db.used existed
            for itemID, state in pairs(db.used) do
                local numID = tonumber(itemID)
                if numID and numID > 0 and state == true then
                    db.rolledItems[numID] = true
                end
            end
        elseif prevVersion == 3 then
            -- Clear false-positive uncontextualized offline tooltip scans from SCAN_VERSION 3
            db.usedBySpec = {}
        end

        db.used = {}
        db.checked = false
        db.scanVersion = SCAN_VERSION

        for itemID in pairs(db.rolledItems) do
            db.used[itemID] = true
        end
        for _, specMap in pairs(db.rolledBySpec) do
            if type(specMap) == "table" then
                for itemID in pairs(specMap) do
                    db.used[itemID] = true
                end
            end
        end
        for _, specMap in pairs(db.usedBySpec) do
            if type(specMap) == "table" then
                for itemID in pairs(specMap) do
                    db.used[itemID] = true
                end
            end
        end
        for itemID, state in pairs(db.manual) do
            if state then
                db.used[itemID] = true
            else
                db.used[itemID] = nil
            end
        end
    end

    db.used          = db.used or {}
    db.usedBySpec    = db.usedBySpec or {}
    db.rolledItems   = db.rolledItems or {}
    db.rolledBySpec  = db.rolledBySpec or {}
    db.manual        = db.manual or {}
    db.history       = db.history or {}
    db.poolContexts  = db.poolContexts or {}
    db.learnedChests = db.learnedChests or {}
    db.targets       = db.targets or {}
    db.targets.dungeons = db.targets.dungeons or {}
    db.targets.bosses   = db.targets.bosses or {}
    db.targets.items    = db.targets.items or {}

    for cacheID, src in pairs(db.learnedChests) do
        local numCache = tonumber(cacheID)
        if numCache and type(src) == "table" and not CHEST_DATABASE[numCache] then
            CHEST_DATABASE[numCache] = {
                bossId          = tonumber(src.bossId) or tonumber(src.encounterID),
                instanceID      = tonumber(src.instanceID),
                challengeModeId = tonumber(src.challengeModeId),
            }
        end
    end

    return db
end

local function DB()
    SfuiDB = SfuiDB or {}
    SfuiDB.bonusroll = SfuiDB.bonusroll or {}
    local key = GetPlayerKey()
    if not SfuiDB.bonusroll[key] then
        SfuiDB.bonusroll[key] = {
            used            = {},
            usedBySpec      = {},
            rolledItems     = {},
            rolledBySpec    = {},
            manual          = {},
            history         = {},
            poolContexts    = {},
            learnedChests   = {},
            checked         = false,
            scanVersion     = SCAN_VERSION,
            targets         = {
                dungeons = {},
                bosses   = {},
                items    = {},
            },
        }
    end
    return EnsureCharDB(SfuiDB.bonusroll[key])
end

local function SyncExternalTargets(keyID, isBoss, isTargeted)
    if isBoss then
        local engClass = sfui.common.get_player_class()
        if engClass and SfuiDB and SfuiDB.lootspec and SfuiDB.lootspec.classes and SfuiDB.lootspec.classes[engClass] then
            local bDb = SfuiDB.lootspec.classes[engClass].bosses
            if bDb then
                if bDb[keyID] then
                    if type(bDb[keyID]) == "table" then
                        bDb[keyID].warn = isTargeted or nil
                    elseif type(bDb[keyID]) == "number" then
                        bDb[keyID] = { spec = bDb[keyID], warn = isTargeted or nil }
                    end
                elseif isTargeted then
                    bDb[keyID] = { spec = 0, warn = true }
                end
            end
        end
    else
        local guid = UnitGUID("player")
        if guid and SfuiDB and SfuiDB.alts and SfuiDB.alts[guid] then
            SfuiDB.alts[guid].voidcoreTargets = SfuiDB.alts[guid].voidcoreTargets or {}
            SfuiDB.alts[guid].voidcoreTargets[keyID] = isTargeted or nil
        end
    end
end

-- ─── Target Management API ────────────────────────────────────────────────────

function sfui.bonusroll.GetTargetStatus(keyID, isBoss)
    if not keyID then return false, 0, {} end
    local db = DB()
    local group = isBoss and "bosses" or "dungeons"
    local entry = db.targets[group] and db.targets[group][keyID]

    local isEnabled = entry and entry.enabled or false
    local items = entry and entry.items or {}
    local itemCount = 0
    for _ in pairs(items) do
        itemCount = itemCount + 1
    end

    -- Fallback compatibility: check alts/lootspec if not explicitly targeted in bonusroll
    if not isEnabled and itemCount == 0 then
        if isBoss then
            local engClass = sfui.common.get_player_class()
            local bEntry = engClass and SfuiDB and SfuiDB.lootspec and SfuiDB.lootspec.classes
                and SfuiDB.lootspec.classes[engClass] and SfuiDB.lootspec.classes[engClass].bosses
                and SfuiDB.lootspec.classes[engClass].bosses[keyID]
            if type(bEntry) == "table" and bEntry.warn then
                isEnabled = true
            end
        else
            local guid = UnitGUID("player")
            local altData = guid and SfuiDB and SfuiDB.alts and SfuiDB.alts[guid]
            if altData and altData.voidcoreTargets and altData.voidcoreTargets[keyID] then
                isEnabled = true
            end
        end
    end

    local isTargeted = isEnabled or (itemCount > 0)
    return isTargeted, itemCount, items
end

function sfui.bonusroll.IsTarget(keyID, isBoss)
    local isTargeted = sfui.bonusroll.GetTargetStatus(keyID, isBoss)
    return isTargeted
end

function sfui.bonusroll.IsItemTargeted(itemID)
    if not itemID or itemID <= 0 then return false end
    local db = DB()
    return db.targets.items[itemID] ~= nil
end

function sfui.bonusroll.ToggleTarget(keyID, isBoss)
    if not keyID then return end
    local db = DB()
    local group = isBoss and "bosses" or "dungeons"
    local entry = db.targets[group][keyID]
    local isTargeted = sfui.bonusroll.GetTargetStatus(keyID, isBoss)

    if isTargeted then
        -- Clear card target and any targeted items for this card
        if entry then
            entry.enabled = false
            for itemID in pairs(entry.items or {}) do
                db.targets.items[itemID] = nil
            end
            entry.items = {}
        end
        SyncExternalTargets(keyID, isBoss, nil)
    else
        -- Enable card target
        db.targets[group][keyID] = db.targets[group][keyID] or { enabled = false, items = {} }
        db.targets[group][keyID].enabled = true
        SyncExternalTargets(keyID, isBoss, true)
    end

    if sfui.lootviewer and sfui.lootviewer.frame and sfui.lootviewer.frame:IsShown() and sfui.lootviewer.Rebuild then
        sfui.lootviewer.Rebuild()
    end
    sfui.alts.UpdateUI(true)
end

function sfui.bonusroll.ToggleItemTarget(keyID, isBoss, itemID)
    if not keyID or not itemID then return end
    local db = DB()
    local group = isBoss and "bosses" or "dungeons"
    db.targets[group][keyID] = db.targets[group][keyID] or { enabled = false, items = {} }
    local entry = db.targets[group][keyID]

    if db.targets.items[itemID] then
        -- Untarget item
        db.targets.items[itemID] = nil
        entry.items[itemID] = nil
        local remaining = 0
        for _ in pairs(entry.items) do remaining = remaining + 1 end
        if remaining == 0 and not entry.enabled then
            SyncExternalTargets(keyID, isBoss, nil)
        end
    else
        -- Target item
        db.targets.items[itemID] = { keyID = keyID, isBoss = isBoss }
        entry.items[itemID] = true
        entry.enabled = true
        SyncExternalTargets(keyID, isBoss, true)
    end

    if sfui.lootviewer and sfui.lootviewer.frame and sfui.lootviewer.frame:IsShown() and sfui.lootviewer.Rebuild then
        sfui.lootviewer.Rebuild()
    end
    sfui.alts.UpdateUI(true)
end

function sfui.bonusroll.ClearTarget(keyID, isBoss)
    if not keyID then return end
    local db = DB()
    local group = isBoss and "bosses" or "dungeons"
    local entry = db.targets[group][keyID]
    if entry then
        entry.enabled = false
        for itemID in pairs(entry.items or {}) do
            db.targets.items[itemID] = nil
        end
        entry.items = {}
    end
    SyncExternalTargets(keyID, isBoss, nil)
end

function sfui.bonusroll.AutoclearItemTarget(itemID, itemLink)
    if not itemID or itemID <= 0 then return end
    local db = DB()
    local info = db.targets.items and db.targets.items[itemID]
    if not info then return end

    local keyID = info.keyID
    local isBoss = info.isBoss
    local group = isBoss and "bosses" or "dungeons"

    -- Remove item target
    db.targets.items[itemID] = nil
    if db.targets[group] and db.targets[group][keyID] and db.targets[group][keyID].items then
        db.targets[group][keyID].items[itemID] = nil
    end

    -- Check if any targeted items remain for this card
    local remaining = 0
    if db.targets[group] and db.targets[group][keyID] and db.targets[group][keyID].items then
        for _ in pairs(db.targets[group][keyID].items) do
            remaining = remaining + 1
        end
    end

    if remaining == 0 then
        if db.targets[group] and db.targets[group][keyID] then
            db.targets[group][keyID].enabled = false
        end
        SyncExternalTargets(keyID, isBoss, nil)
    end

    local link = itemLink or select(2, sfui.common.get_item_info(itemID)) or ("item " .. itemID)
    sfui.common.print(string.format("|cff00ff00◆ bonus roll target acquired:|r %s obtained! target cleared.", link))
    PlaySound(SOUNDKIT.UI_EPICLOOT_TOAST or 51570, "Master")

    if sfui.lootviewer and sfui.lootviewer.frame and sfui.lootviewer.frame:IsShown() and sfui.lootviewer.Rebuild then
        sfui.lootviewer.Rebuild()
    end
    sfui.alts.UpdateUI(true)
end

function sfui.bonusroll.NotifyTarget(keyID, isBoss, defaultName)
    local isTargeted, _, itemsMap = sfui.bonusroll.GetTargetStatus(keyID, isBoss)
    if not isTargeted then return end

    local itemLinks = {}
    for id in pairs(itemsMap) do
        local link = select(2, sfui.common.get_item_info(id))
        if not link then
            sfui.common.request_item_load(id)
            local name = select(1, sfui.common.get_item_info(id))
            link = name and ("[" .. name .. "]") or ("item " .. id)
        end
        itemLinks[#itemLinks + 1] = link
    end

    local prefix = "|cffcc44ff◆ bonus roll reminder:|r "
    local name = defaultName or (isBoss and ("boss " .. keyID) or ("dungeon " .. keyID))

    if #itemLinks > 0 then
        if isBoss then
            sfui.common.print(string.format("%s%s — target: %s! use your bonus roll item!", prefix, name, table.concat(itemLinks, ", ")))
        else
            sfui.common.print(string.format("%suse a |cffffcc00nebulous voidcore|r on %s for %s!", prefix, name, table.concat(itemLinks, ", ")))
        end
    else
        if isBoss then
            sfui.common.print(string.format("%s%s — use your bonus roll item!", prefix, name))
        else
            sfui.common.print(string.format("%suse a |cffffcc00nebulous voidcore|r on %s!", prefix, name))
        end
    end

    PlaySound(SOUNDKIT.UI_BONUS_LOOT_ROLL_START or 39516, "Master")
end

-- ─── Item, Token & Spec Eligibility (TheAlmightyBonusRoll + Voidcore) ─────────
local tokenToChildren = {}
local childToToken = {}
local playerSpecSet = nil

local function GetPlayerSpecSet()
    if playerSpecSet and next(playerSpecSet) then return playerSpecSet end
    playerSpecSet = {}
    local numSpecs = _G.GetNumSpecializations and _G.GetNumSpecializations() or 0
    for i = 1, numSpecs do
        local specID = _G.GetSpecializationInfo and _G.GetSpecializationInfo(i)
        if specID then
            playerSpecSet[specID] = true
        end
    end
    return playerSpecSet
end

local function ItemMatchesSpec(itemID, specID, ejSpecs, filteredSpecs)
    if not itemID or not specID or specID <= 0 then return true end
    if type(filteredSpecs) == "table" and next(filteredSpecs) ~= nil then
        if not filteredSpecs[specID] then
            return false
        end
    end
    if C_Item and C_Item.GetItemSpecInfo then
        local ok, specs = pcall(C_Item.GetItemSpecInfo, itemID)
        if ok and type(specs) == "table" and #specs > 0 then
            for _, allowedSpecID in ipairs(specs) do
                if tonumber(allowedSpecID) == tonumber(specID) then
                    return true
                end
            end
            return false
        end
    end
    if type(ejSpecs) == "table" and next(ejSpecs) ~= nil then
        return ejSpecs[specID] == true
    end
    return true
end

local function RegisterTokenLinks(tokenID)
    tokenID = tonumber(tokenID)
    if not tokenID or tokenID <= 0 then return nil end
    if tokenToChildren[tokenID] then return tokenToChildren[tokenID] end
    if not C_Item or not C_Item.GetItemChildInfo then return nil end

    local _, _, _, parentEquipLoc = sfui.common.get_item_instant_info(tokenID)
    if parentEquipLoc and parentEquipLoc ~= "" and parentEquipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" then
        return nil
    end

    local ok, children = pcall(C_Item.GetItemChildInfo, tokenID)
    if not ok or type(children) ~= "table" or #children == 0 then
        return nil
    end

    local pSpecs = GetPlayerSpecSet()
    local matchedChildren = {}
    local allCached = true
    for _, rawChildID in ipairs(children) do
        local childID = tonumber(rawChildID)
        if childID and childID > 0 then
            local _, _, _, equipLoc = sfui.common.get_item_instant_info(childID)
            if equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" then
                local specs = C_Item.GetItemSpecInfo and C_Item.GetItemSpecInfo(childID)
                if type(specs) == "table" and #specs > 0 then
                    for _, allowedSpecID in ipairs(specs) do
                        local sID = tonumber(allowedSpecID)
                        if sID and pSpecs[sID] then
                            matchedChildren[childID] = true
                            childToToken[childID] = tokenID
                            break
                        end
                    end
                else
                    allCached = false
                    sfui.common.request_item_load(childID)
                end
            end
        end
    end

    if next(matchedChildren) then
        if allCached then
            tokenToChildren[tokenID] = matchedChildren
        end
        return matchedChildren
    end
    return nil
end

local function GetLinkedIDs(itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then return nil end
    local linked = {}
    local mirror = MIRROR_ITEMS[itemID]
    if mirror then
        linked[mirror] = true
    end
    local children = RegisterTokenLinks(itemID)
    if children then
        for childID in pairs(children) do
            linked[childID] = true
        end
    end
    local parentToken = childToToken[itemID]
    if parentToken then
        linked[parentToken] = true
    end
    return next(linked) and linked or nil
end

local function IsChestPoolEligible(itemID)
    if not itemID or itemID <= 0 then return false end
    if EXCLUDED_ITEMS[itemID] then return false end
    if C_Item then
        if C_Item.IsCurioItem and C_Item.IsCurioItem(itemID) then return false end
        if C_Item.IsCosmeticItem and C_Item.IsCosmeticItem(itemID) then return false end
    end

    local _, _, _, itemEquipLoc, _, classID, subclassID = sfui.common.get_item_instant_info(itemID)
    if classID == 5 and subclassID == 2 then return false end
    if classID and classID ~= 2 and classID ~= 4 then return false end
    if not itemEquipLoc or itemEquipLoc == "" or itemEquipLoc == "INVTYPE_NON_EQUIP_IGNORE" then
        return false
    end
    if C_Item and C_Item.IsEquippableItem and not C_Item.IsEquippableItem(itemID) then
        return false
    end

    return true
end

function sfui.bonusroll.IsEligible(itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then return false end
    if EXCLUDED_ITEMS[itemID] then return false end
    if IsChestPoolEligible(itemID) then return true end
    if RegisterTokenLinks(itemID) or childToToken[itemID] then return true end
    if C_Item and C_Item.GetItemChildInfo then
        local ok, children = pcall(C_Item.GetItemChildInfo, itemID)
        if ok and type(children) == "table" and #children > 0 then
            return true
        end
    end
    return false
end

local function UpdateEffectiveUsedForSingleID(db, id)
    if db.manual and db.manual[id] ~= nil then
        if db.manual[id] then
            db.used[id] = true
        else
            db.used[id] = nil
        end
        return
    end
    if db.rolledItems and db.rolledItems[id] then
        db.used[id] = true
        return
    end
    if db.rolledBySpec then
        for _, specMap in pairs(db.rolledBySpec) do
            if type(specMap) == "table" and specMap[id] then
                db.used[id] = true
                return
            end
        end
    end
    if db.usedBySpec then
        for _, specMap in pairs(db.usedBySpec) do
            if type(specMap) == "table" and specMap[id] then
                db.used[id] = true
                return
            end
        end
    end
    db.used[id] = nil
end

local function ApplyStateToID(db, id, value, specID, isManual, isDirectRoll)
    if isManual then
        if value then
            db.manual[id] = true
        else
            db.manual[id] = false
        end
    elseif isDirectRoll then
        db.manual[id] = nil
        if specID and specID > 0 then
            db.rolledBySpec[specID] = db.rolledBySpec[specID] or {}
            db.rolledBySpec[specID][id] = value and true or nil
            db.usedBySpec[specID] = db.usedBySpec[specID] or {}
            db.usedBySpec[specID][id] = value and true or nil
        else
            db.rolledItems[id] = value and true or nil
        end
    elseif specID and specID > 0 then
        db.usedBySpec[specID] = db.usedBySpec[specID] or {}
        if value then
            db.usedBySpec[specID][id] = true
        else
            db.usedBySpec[specID][id] = nil
        end
    else
        if value then
            db.rolledItems[id] = true
        else
            db.rolledItems[id] = nil
            for _, specMap in pairs(db.rolledBySpec) do
                if type(specMap) == "table" then specMap[id] = nil end
            end
            for _, specMap in pairs(db.usedBySpec) do
                if type(specMap) == "table" then specMap[id] = nil end
            end
        end
    end
    UpdateEffectiveUsedForSingleID(db, id)
end

local function RecordExternalItem(targetDB, rawID, specID, isManual, isDirectRoll)
    local id = tonumber(rawID)
    if not id or id <= 0 then return end
    ApplyStateToID(targetDB, id, true, specID, isManual, isDirectRoll)
    local linked = GetLinkedIDs(id)
    if linked then
        for linkedID in pairs(linked) do
            ApplyStateToID(targetDB, linkedID, true, specID, isManual, isDirectRoll)
        end
    end
end

local externalSynced = false
local function SyncFromExternalAddons(force)
    if externalSynced and not force then return end

    local name, realm
    if UnitFullName then
        name, realm = UnitFullName("player")
    end
    if issecretvalue(name) or issecretvalue(realm) then return end
    if not name or name == "" then
        name = UnitName and UnitName("player")
        if issecretvalue(name) then return end
    end
    if not name or name == "" then return end

    local rawRealm = GetRealmName and GetRealmName() or ""
    if issecretvalue(rawRealm) then rawRealm = "" end
    realm = (realm and realm ~= "" and realm) or rawRealm
    externalSynced = true

    local db = DB()
    local curSeason = GetCurrentSeasonID()

    -- 1. SimulationCraftDB (char["Name - Realm"].bonusRolls)
    local simcDB = _G.SimulationCraftDB
    if type(simcDB) == "table" and type(simcDB.char) == "table" then
        local function SyncSimcChar(targetDB, charEntry)
            if type(charEntry) ~= "table" or type(charEntry.bonusRolls) ~= "table" then return end
            for _, roll in ipairs(charEntry.bonusRolls) do
                if type(roll) == "table" then
                    local rollSeason = tonumber(roll.season)
                    local rollCurrency = tonumber(roll.currency)
                    if not curSeason or not rollSeason or rollSeason == curSeason or rollCurrency == 3418 then
                        local specID = tonumber(roll.spec) or 0
                        RecordExternalItem(targetDB, roll.itemId, specID, false, true)
                        local cacheID = tonumber(roll.source)
                        local itemCtx = tonumber(roll.context)
                        if cacheID and cacheID > 0 and itemCtx and itemCtx > 0 then
                            targetDB.poolContexts = targetDB.poolContexts or {}
                            targetDB.poolContexts[cacheID] = {
                                itemContext = itemCtx,
                                level       = tonumber(roll.keyLevel) or 0,
                            }
                        end
                    end
                end
            end
        end

        local simcKey1 = name .. " - " .. realm
        local simcKey2 = (rawRealm ~= "" and rawRealm ~= realm) and (name .. " - " .. rawRealm) or nil
        SyncSimcChar(db, simcDB.char[simcKey1])
        if simcKey2 then
            SyncSimcChar(db, simcDB.char[simcKey2])
        end

        -- Also sync known alts in SfuiDB.alts so all characters stay up to date
        if SfuiDB and type(SfuiDB.alts) == "table" and type(SfuiDB.bonusroll) == "table" then
            for altGUID, altInfo in pairs(SfuiDB.alts) do
                if type(altInfo) == "table" and type(altInfo.name) == "string" and type(altInfo.realm) == "string" then
                    local altSimc = simcDB.char[altInfo.name .. " - " .. altInfo.realm]
                    if type(altSimc) == "table" and type(altSimc.bonusRolls) == "table" and SfuiDB.bonusroll[altGUID] then
                        local altDB = EnsureCharDB(SfuiDB.bonusroll[altGUID])
                        SyncSimcChar(altDB, altSimc)
                    end
                end
            end
        end
    end

    -- 2. YetRolledDB (characters[guid] or characters[realm-name])
    local yrDB = _G.YetRolledDB
    if type(yrDB) == "table" and type(yrDB.characters) == "table" then
        local guid = UnitGUID and UnitGUID("player")
        local yrFallbackKey = string.lower((rawRealm ~= "" and rawRealm or realm) .. "-" .. name)
        local yrChar = (guid and yrDB.characters[guid]) or yrDB.characters[yrFallbackKey]
        if type(yrChar) == "table" then
            if type(yrChar.cacheSources) == "table" then
                for _, src in pairs(yrChar.cacheSources) do
                    if type(src) == "table" then
                        -- Learned sources stored under "<season>:<cacheID>"
                        for k, v in pairs(yrChar.cacheSources) do
                            local cID = type(k) == "string" and tonumber(k:match(":(%d+)$"))
                            if cID and type(v) == "table" and not CHEST_DATABASE[cID] then
                                CHEST_DATABASE[cID] = {
                                    bossId     = tonumber(v.encounterID),
                                    instanceID = tonumber(v.instanceID),
                                }
                                db.learnedChests[cID] = CHEST_DATABASE[cID]
                            end
                        end
                        break
                    end
                end
            end
            if type(yrChar.items) == "table" then
                for rawID, rec in pairs(yrChar.items) do
                    if type(rec) == "table" and rec.status == "obtained" then
                        local recSeason = tonumber(rec.seasonID)
                        if not curSeason or not recSeason or recSeason == curSeason then
                            local isManual = rec.source == "manual"
                            RecordExternalItem(db, rawID, tonumber(rec.specID) or 0, isManual, not isManual)
                        end
                    end
                end
            end
            if type(yrChar.contextItems) == "table" then
                for _, records in pairs(yrChar.contextItems) do
                    if type(records) == "table" then
                        for rawID, rec in pairs(records) do
                            if type(rec) == "table" and rec.status == "obtained" then
                                local recSeason = tonumber(rec.seasonID)
                                if not curSeason or not recSeason or recSeason == curSeason then
                                    local isManual = rec.source == "manual"
                                    RecordExternalItem(db, rawID, tonumber(rec.specID) or 0, isManual, not isManual)
                                end
                            end
                        end
                    end
                end
            end
            if type(yrChar.pools) == "table" then
                for _, snapshot in pairs(yrChar.pools) do
                    if type(snapshot) == "table" and type(snapshot.removedIDs) == "table" then
                        local snapSeason = tonumber(snapshot.seasonID)
                        if not curSeason or not snapSeason or snapSeason == curSeason then
                            local sID = tonumber(snapshot.specID) or 0
                            for removedID, isRemoved in pairs(snapshot.removedIDs) do
                                if isRemoved then
                                    RecordExternalItem(db, removedID, sID, false, true)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 3. TheAlmightyBonusRollDB
    local tabrDB = _G.TheAlmightyBonusRollDB
    if type(tabrDB) == "table" and type(tabrDB.history) == "table" then
        local charKey = name .. "-" .. realm
        local altCharKey = (rawRealm ~= "" and rawRealm ~= realm) and (name .. "-" .. rawRealm) or nil
        local seasonKey = nil
        if _G.TheAlmightyBonusRoll and type(_G.TheAlmightyBonusRoll.GetSeasonKey) == "function" then
            local ok, key = pcall(_G.TheAlmightyBonusRoll.GetSeasonKey, _G.TheAlmightyBonusRoll)
            if ok and type(key) == "string" then seasonKey = key end
        end

        for _, entry in ipairs(tabrDB.history) do
            local entryKey = type(entry) == "table" and entry.characterKey
            if entryKey and (entryKey == charKey or (altCharKey and entryKey == altCharKey)) and (not seasonKey or not entry.seasonKey or entry.seasonKey == seasonKey) then
                local specID = tonumber(entry.lootSpecID) or tonumber(entry.serverSpecID) or 0
                local isManual = entry.manual == true
                for _, rawID in ipairs({ entry.itemID, entry.tokenItemID }) do
                    RecordExternalItem(db, rawID, specID, isManual, not isManual)
                end
            end
        end
    end

    -- 4. KeystoneLootCharDB
    local klCharDB = _G.KeystoneLootCharDB
    if type(klCharDB) == "table" and type(klCharDB.voidcore) == "table" then
        for rawID, isUsed in pairs(klCharDB.voidcore) do
            if isUsed == true then
                RecordExternalItem(db, rawID, 0, false, true)
            end
        end
    end
end

function sfui.bonusroll.IsUsed(itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then return false end
    if not IsPlayerAtMaxLevel() then return false end

    SyncFromExternalAddons()

    local db = DB()
    if db.manual and db.manual[itemID] ~= nil then
        return db.manual[itemID] == true
    end
    if db.used and db.used[itemID] == true then
        return true
    end

    local linked = GetLinkedIDs(itemID)
    if linked then
        for linkedID in pairs(linked) do
            if db.manual and db.manual[linkedID] ~= nil then
                return db.manual[linkedID] == true
            end
            if db.used and db.used[linkedID] == true then
                return true
            end
        end
    end

    -- Compatibility: Check KeystoneLoot if loaded
    if _G.KeystoneLoot and _G.KeystoneLoot.Voidcore and _G.KeystoneLoot.Voidcore.IsUsed then
        local ok, used = pcall(_G.KeystoneLoot.Voidcore.IsUsed, _G.KeystoneLoot.Voidcore, itemID)
        if ok and used == true then
            return true
        end
    end

    return false
end

function sfui.bonusroll.SetUsed(itemID, value, itemLink, specID, isManual, isDirectRoll)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then return end
    if value and not IsPlayerAtMaxLevel() then return end

    local db = DB()
    ApplyStateToID(db, itemID, value, specID, isManual, isDirectRoll)

    local linked = GetLinkedIDs(itemID)
    if linked then
        for linkedID in pairs(linked) do
            ApplyStateToID(db, linkedID, value, specID, isManual, isDirectRoll)
        end
    end

    if value and db.used[itemID] then
        sfui.bonusroll.AutoclearItemTarget(itemID, itemLink)
        if linked then
            for linkedID in pairs(linked) do
                sfui.bonusroll.AutoclearItemTarget(linkedID, itemLink)
            end
        end
    end

    -- Compatibility: sync with KeystoneLoot if active
    if _G.KeystoneLoot and _G.KeystoneLoot.Voidcore and _G.KeystoneLoot.Voidcore.SetUsed then
        pcall(_G.KeystoneLoot.Voidcore.SetUsed, _G.KeystoneLoot.Voidcore, itemID, db.used[itemID] or nil)
    end

    if sfui.lootviewer and sfui.lootviewer.frame and sfui.lootviewer.frame:IsShown() and sfui.lootviewer.Rebuild then
        sfui.lootviewer.Rebuild()
    end
end

-- ─── Source Candidate Extraction ──────────────────────────────────────────────
local rawEntriesCache = {}
local failedNameLookups = {}

local SOURCE_STOPWORDS = {
    ["the"] = true, ["of"] = true, ["and"] = true,
    ["in"] = true, ["on"] = true, ["at"] = true,
}

local function NormalizeSourceName(s)
    if not IsPublicValue(s) or type(s) ~= "string" then return nil end
    local norm = s:lower():gsub("^the%s+", ""):gsub("[^%w]+", "")
    return norm ~= "" and norm or nil
end

local function ExtractSourceTokens(s)
    if not IsPublicValue(s) or type(s) ~= "string" then return nil end
    local tokens = {}
    local count = 0
    for word in s:lower():gmatch("%w+") do
        if #word >= 4 and not SOURCE_STOPWORDS[word] then
            tokens[word] = true
            count = count + 1
        end
    end
    return count > 0 and tokens or nil
end

local function CountTokenOverlap(tokensA, tokensB)
    if not tokensA or not tokensB then return 0 end
    local overlap = 0
    for w in pairs(tokensA) do
        if tokensB[w] then
            overlap = overlap + 1
        end
    end
    return overlap
end

local function LearnChestSource(cacheID, instanceID, encounterID, difficultyID, challengeModeId)
    cacheID = tonumber(cacheID)
    if not cacheID or cacheID <= 0 then return nil end
    instanceID = tonumber(instanceID)
    encounterID = tonumber(encounterID)
    difficultyID = tonumber(difficultyID)
    challengeModeId = tonumber(challengeModeId)

    local existing = CHEST_DATABASE[cacheID]
    if existing and (existing.bossId or existing.challengeModeId or existing.instanceID) then
        local updated = false
        if instanceID and instanceID > 0 and not existing.instanceID then
            existing.instanceID = instanceID
            updated = true
        end
        if encounterID and encounterID > 0 and not existing.bossId then
            existing.bossId = encounterID
            updated = true
        end
        if challengeModeId and challengeModeId > 0 and not existing.challengeModeId then
            existing.challengeModeId = challengeModeId
            updated = true
        end
        if updated then
            rawEntriesCache[cacheID] = nil
            local db = DB()
            db.learnedChests[cacheID] = existing
        end
        return existing
    end

    local learned = nil
    if encounterID and encounterID > 0 then
        learned = {
            bossId     = encounterID,
            instanceID = (instanceID and instanceID > 0 and instanceID) or nil,
        }
    elseif (challengeModeId and challengeModeId > 0) or (instanceID and instanceID > 0 and (difficultyID == 8 or difficultyID == 23 or not difficultyID)) then
        learned = {
            challengeModeId = (challengeModeId and challengeModeId > 0 and challengeModeId) or nil,
            instanceID      = (instanceID and instanceID > 0 and instanceID) or nil,
        }
    end

    if learned then
        CHEST_DATABASE[cacheID] = learned
        rawEntriesCache[cacheID] = nil
        local db = DB()
        db.learnedChests[cacheID] = learned
        return learned
    end
    return existing
end

local function InferChestSourceFromName(chestItemId)
    if failedNameLookups[chestItemId] then return nil end

    local itemName = CleanTooltipText(select(1, sfui.common.get_item_info(chestItemId)))
    if not itemName or itemName == "" then
        sfui.common.request_item_load(chestItemId)
        return nil
    end

    local suffix = itemName:match(":%s*(.+)$")
    local targetNorm = NormalizeSourceName(suffix)
    if not targetNorm then
        failedNameLookups[chestItemId] = true
        return nil
    end

    local targetTokens = ExtractSourceTokens(suffix)
    local bestTokenMatch = nil
    local bestTokenScore = 0
    local tokenTied = false

    local function ConsiderTokenMatch(name, candidate)
        local score = CountTokenOverlap(targetTokens, ExtractSourceTokens(name))
        if score > bestTokenScore then
            bestTokenScore = score
            bestTokenMatch = candidate
            tokenTied = false
        elseif score > 0 and score == bestTokenScore then
            tokenTied = true
        end
    end

    if sfui.lootviewer and sfui.lootviewer.GetRaidData then
        local raids = sfui.lootviewer.GetRaidData()
        for _, r in ipairs(raids or {}) do
            for _, b in ipairs(r.bosses or {}) do
                local bNorm = NormalizeSourceName(b.name)
                if bNorm and (bNorm == targetNorm or bNorm:find(targetNorm, 1, true) or targetNorm:find(bNorm, 1, true)) then
                    return LearnChestSource(chestItemId, r.instanceID, b.encounterID, nil, nil)
                end
                ConsiderTokenMatch(b.name, { instanceID = r.instanceID, bossId = b.encounterID })
            end
        end
    end

    if sfui.lootviewer and sfui.lootviewer.GetDungeonData then
        local dungeons = sfui.lootviewer.GetDungeonData()
        for _, d in ipairs(dungeons or {}) do
            local dNorm = NormalizeSourceName(d.name)
            if dNorm and (dNorm == targetNorm or dNorm:find(targetNorm, 1, true) or targetNorm:find(dNorm, 1, true)) then
                return LearnChestSource(chestItemId, d.instanceID, nil, 8, d.mapID)
            end
            ConsiderTokenMatch(d.name, { instanceID = d.instanceID, challengeModeId = d.mapID, diff = 8 })
        end
    end

    if bestTokenMatch and bestTokenScore > 0 and not tokenTied then
        return LearnChestSource(
            chestItemId,
            bestTokenMatch.instanceID,
            bestTokenMatch.bossId,
            bestTokenMatch.diff,
            bestTokenMatch.challengeModeId
        )
    end

    failedNameLookups[chestItemId] = true
    return nil
end

local function InferChestSourceFromTooltip(chestItemId, remainingNames, remainingIDs)
    if not chestItemId or chestItemId <= 0 then return nil end
    local hasNames = remainingNames and next(remainingNames) ~= nil
    local hasIDs = remainingIDs and next(remainingIDs) ~= nil
    if not hasNames and not hasIDs then return nil end

    local bestSource = nil
    local bestScore = 0
    local tied = false

    local function ScoreLootTable(loot, candidateSource)
        local score = 0
        for _, it in ipairs(loot or {}) do
            if type(it) == "table" and it.id then
                local numID = tonumber(it.id)
                local itName = CleanTooltipText(it.name) or CleanTooltipText(select(1, sfui.common.get_item_info(numID)))
                if (numID and remainingIDs and remainingIDs[numID]) or (itName and remainingNames and remainingNames[itName]) then
                    score = score + 1
                end
            end
        end
        if score > bestScore then
            bestScore = score
            bestSource = candidateSource
            tied = false
        elseif score > 0 and score == bestScore then
            tied = true
        end
    end

    if sfui.lootviewer and sfui.lootviewer.GetRaidData then
        local raids = sfui.lootviewer.GetRaidData()
        for _, r in ipairs(raids or {}) do
            for _, b in ipairs(r.bosses or {}) do
                ScoreLootTable(b.loot, { bossId = b.encounterID, instanceID = r.instanceID })
            end
        end
    end

    if sfui.lootviewer and sfui.lootviewer.GetDungeonData then
        local dungeons = sfui.lootviewer.GetDungeonData()
        for _, d in ipairs(dungeons or {}) do
            ScoreLootTable(d.loot, { challengeModeId = d.mapID, instanceID = d.instanceID })
        end
    end

    if bestSource and bestScore > 0 and not tied then
        return LearnChestSource(chestItemId, bestSource.instanceID, bestSource.bossId, nil, bestSource.challengeModeId)
    end
    return nil
end

local function GetChestSource(chestItemId)
    local src = CHEST_DATABASE[chestItemId]
    if src then return src end
    return InferChestSourceFromName(chestItemId)
end

local function GetRawChestEntries(chestItemId)
    local cached = rawEntriesCache[chestItemId]
    if cached then return cached end

    local source = GetChestSource(chestItemId)
    if not source then return {} end

    local entries = {}
    local seen = {}

    local function CollectFromLootTable(loot)
        for _, it in ipairs(loot or {}) do
            if type(it) == "table" and it.id then
                local numID = tonumber(it.id)
                if numID and numID > 0 then
                    if it.isSetToken or it.slot == "token" then
                        RegisterTokenLinks(numID)
                    elseif it.slot ~= "other" and not seen[numID] and IsChestPoolEligible(numID) then
                        seen[numID] = true
                        entries[#entries + 1] = {
                            id      = numID,
                            specs   = it.specs,
                            ejSpecs = it.ejSpecs or it.specs,
                        }
                    end
                end
            end
        end
    end

    if source.challengeModeId or (source.instanceID and not source.bossId) then
        if sfui.lootviewer and sfui.lootviewer.GetDungeonData then
            local dungeons = sfui.lootviewer.GetDungeonData()
            for _, d in ipairs(dungeons or {}) do
                if (source.challengeModeId and d.mapID == source.challengeModeId)
                    or (source.instanceID and d.instanceID == source.instanceID) then
                    CollectFromLootTable(d.loot)
                    break
                end
            end
        end
    elseif source.bossId then
        if sfui.lootviewer and sfui.lootviewer.GetRaidData then
            local raids = sfui.lootviewer.GetRaidData()
            for _, r in ipairs(raids or {}) do
                for _, b in ipairs(r.bosses or {}) do
                    if b.encounterID == source.bossId or b.dungeonEncounterID == source.bossId then
                        CollectFromLootTable(b.loot)
                        break
                    end
                end
            end
        end
    end

    if #entries > 0 then
        rawEntriesCache[chestItemId] = entries
    end
    return entries
end

function sfui.bonusroll.GetSourceItems(chestItemId, specID)
    local activeSpec = (specID and specID > 0 and specID) or GetActiveLootSpecID()
    local rawEntries = GetRawChestEntries(chestItemId)
    if #rawEntries == 0 then return {} end

    local results = {}
    for _, entry in ipairs(rawEntries) do
        if ItemMatchesSpec(entry.id, activeSpec, entry.ejSpecs, entry.specs) then
            results[#results + 1] = entry.id
        end
    end
    return results
end

function sfui.bonusroll.ResetSource(candidates, specID)
    local db = DB()
    for _, itemID in ipairs(candidates) do
        local numID = tonumber(itemID)
        if numID then
            if specID and specID > 0 then
                if db.rolledBySpec and db.rolledBySpec[specID] then
                    db.rolledBySpec[specID][numID] = nil
                end
                sfui.bonusroll.SetUsed(numID, nil, nil, specID)
            else
                sfui.bonusroll.SetUsed(numID, nil)
            end
        end
    end
end

-- ─── Tooltip Parsing & Live Prompt Pool Scanner (YetRolled Method) ────────────
local function GetRemainingNamesFromTooltip(tooltipData)
    local names = {}
    local itemIDs = {}
    if not IsPublicValue(tooltipData) or type(tooltipData) ~= "table" or type(tooltipData.lines) ~= "table" then
        return names, itemIDs
    end

    local heading = CleanTooltipText(_G.PUNCH_LIST_ITEM_CACHE_TOOLTIP)
    if heading and heading ~= "" then
        local foundHeading = false
        for _, line in ipairs(tooltipData.lines) do
            local rawText = line.leftText
            local text = CleanTooltipText(rawText)
            if text then
                if text == heading then
                    if foundHeading then
                        return {}, {}
                    end
                    foundHeading = true
                elseif foundHeading then
                    for part in text:gmatch("[^\r\n]+") do
                        local cleanedPart = CleanTooltipText(part)
                        if cleanedPart and cleanedPart ~= "" then
                            local linkID = tonumber(cleanedPart:match("|Hitem:(%d+)"))
                            local itemName = cleanedPart:match("^%-%s+(.+)") or cleanedPart:match("^•%s*(.+)")
                            if linkID then
                                itemName = cleanedPart:match("|h%[(.-)%]|h") or itemName
                                itemIDs[linkID] = true
                            end
                            itemName = CleanTooltipText(itemName)
                            if itemName and itemName ~= "" then
                                names[itemName] = true
                            elseif not linkID then
                                foundHeading = false
                                break
                            end
                        end
                    end
                end
            elseif foundHeading and not IsPublicValue(rawText) then
                return {}, {}
            end
        end
        if next(names) or next(itemIDs) then
            return names, itemIDs
        end
    end

    -- Fallback: parse trailing bullet/dash lines from bottom of tooltip
    for i = #tooltipData.lines, 1, -1 do
        local text = CleanTooltipText(tooltipData.lines[i].leftText)
        if text and text ~= "" then
            local matchedLine = false
            for part in text:gmatch("[^\r\n]+") do
                local cleanedPart = CleanTooltipText(part)
                if cleanedPart then
                    local linkID = tonumber(cleanedPart:match("|Hitem:(%d+)"))
                    local name = cleanedPart:match("^%-%s*(.+)$") or cleanedPart:match("^•%s*(.+)$")
                    if linkID then
                        name = cleanedPart:match("|h%[(.-)%]|h") or name
                        itemIDs[linkID] = true
                        matchedLine = true
                    end
                    name = CleanTooltipText(name)
                    if name and name ~= "" then
                        names[name] = true
                        matchedLine = true
                    end
                end
            end
            if not matchedLine and (next(names) or next(itemIDs)) then
                break
            end
        end
    end

    return names, itemIDs
end

local function CountMatchesForSpec(entries, resolvedNames, remainingNames, remainingIDs, specID)
    local matched = 0
    local totalForSpec = 0
    local matchedNames = {}
    for _, entry in ipairs(entries) do
        local numID = entry.id
        if ItemMatchesSpec(numID, specID, entry.ejSpecs, entry.specs) then
            totalForSpec = totalForSpec + 1
            local name = resolvedNames[numID]
            local isPresent = (remainingIDs and remainingIDs[numID]) or (name and remainingNames[name])
            if isPresent then
                local key = name or tostring(numID)
                if not matchedNames[key] then
                    matchedNames[key] = true
                    matched = matched + 1
                end
            end
        end
    end
    return matched, totalForSpec
end

function sfui.bonusroll.ApplyResults(candidatesOrEntries, remainingNames, onApplied, explicitSpecID, remainingIDs, isLivePrompt)
    if not isLivePrompt then
        -- Never accept generic/offline uncontextualized tooltips as personal remaining pools
        if onApplied then onApplied(0) end
        return
    end

    local entries = {}
    for _, item in ipairs(candidatesOrEntries or {}) do
        if type(item) == "table" and item.id then
            entries[#entries + 1] = item
        else
            local numID = tonumber(item)
            if numID and numID > 0 then
                entries[#entries + 1] = { id = numID }
            end
        end
    end
    if #entries == 0 then
        if onApplied then onApplied(0) end
        return
    end

    local remainingCount = 0
    for _ in pairs(remainingNames or {}) do
        remainingCount = remainingCount + 1
    end
    for _ in pairs(remainingIDs or {}) do
        remainingCount = remainingCount + 1
    end
    if remainingCount == 0 then
        if onApplied then onApplied(0) end
        return
    end

    local resolvedNames = {}
    local pending = #entries

    local function Finalize()
        for _, entry in ipairs(entries) do
            local name = resolvedNames[entry.id]
            if not name or name == "" then
                if onApplied then onApplied(0) end
                return
            end
        end

        local lootSpecID = (explicitSpecID and explicitSpecID > 0 and explicitSpecID) or GetActiveLootSpecID()
        local curSpecID = sfui.common.get_current_spec_id()
        local tooltipSpecID = lootSpecID

        if curSpecID and curSpecID > 0 and curSpecID ~= lootSpecID then
            local lootMatched = CountMatchesForSpec(entries, resolvedNames, remainingNames, remainingIDs, lootSpecID)
            local curMatched = CountMatchesForSpec(entries, resolvedNames, remainingNames, remainingIDs, curSpecID)
            if curMatched > lootMatched then
                tooltipSpecID = curSpecID
            end
        end

        local specCandidates = {}
        local matchedInTooltip = 0
        local matchedTooltipKeys = {}
        local missingIDs = {}

        for _, entry in ipairs(entries) do
            local numID = entry.id
            if ItemMatchesSpec(numID, tooltipSpecID, entry.ejSpecs, entry.specs) then
                specCandidates[#specCandidates + 1] = numID
                local name = resolvedNames[numID]
                local isPresent = (remainingIDs and remainingIDs[numID]) or (name and remainingNames[name])
                if isPresent then
                    local key = name or tostring(numID)
                    if not matchedTooltipKeys[key] then
                        matchedTooltipKeys[key] = true
                        matchedInTooltip = matchedInTooltip + 1
                    end
                else
                    missingIDs[#missingIDs + 1] = numID
                end
            end
        end

        if matchedInTooltip == 0 then
            if onApplied then onApplied(0) end
            return
        end

        if #missingIDs == 0 then
            -- Full pool for this spec is present in the live prompt tooltip -> cycle reset
            sfui.bonusroll.ResetSource(specCandidates, tooltipSpecID)
            if onApplied then onApplied(0) end
            return
        end

        -- Partial pool in live prompt tooltip -> mark present items as available and missing items as used
        local db = DB()
        for _, numID in ipairs(specCandidates) do
            local name = resolvedNames[numID]
            local isPresent = (remainingIDs and remainingIDs[numID]) or (name and remainingNames[name])
            if isPresent then
                if db.rolledBySpec and db.rolledBySpec[tooltipSpecID] then
                    db.rolledBySpec[tooltipSpecID][numID] = nil
                end
                sfui.bonusroll.SetUsed(numID, nil, nil, tooltipSpecID)
            end
        end

        for _, numID in ipairs(missingIDs) do
            sfui.bonusroll.SetUsed(numID, true, nil, tooltipSpecID)
        end

        if onApplied then onApplied(#missingIDs) end
    end

    for _, entry in ipairs(entries) do
        local numID = entry.id
        if Item and Item.CreateFromItemID then
            local itemObj = Item:CreateFromItemID(numID)
            itemObj:ContinueOnItemLoad(function()
                resolvedNames[numID] = CleanTooltipText(itemObj:GetItemName())
                pending = pending - 1
                if pending == 0 then
                    Finalize()
                end
            end)
        else
            resolvedNames[numID] = CleanTooltipText(select(1, sfui.common.get_item_info(numID)))
            pending = pending - 1
            if pending == 0 then
                Finalize()
            end
        end
    end
end

function sfui.bonusroll.CheckSupply(chestItemId, onDone, itemContext, level, isLivePrompt)
    if not IsPlayerAtMaxLevel() or not isLivePrompt then
        if onDone then onDone(0) end
        return
    end

    chestItemId = tonumber(chestItemId)
    if not chestItemId or chestItemId <= 0 then
        if onDone then onDone(0) end
        return
    end

    local db = DB()
    local savedCtx = db.poolContexts and db.poolContexts[chestItemId]
    local ctx = tonumber(itemContext) or (savedCtx and tonumber(savedCtx.itemContext))
    local lvl = tonumber(level) or (savedCtx and tonumber(savedCtx.level)) or 0
    if not ctx or ctx <= 0 then
        if onDone then onDone(0) end
        return
    end

    local entries = GetRawChestEntries(chestItemId)

    local activeSpecID = GetActiveLootSpecID()
    local attempts   = 0
    local prevCount  = -1
    local stableHits = 0

    local function Poll()
        attempts = attempts + 1

        if C_TooltipInfo and C_TooltipInfo.GetItemByID then
            -- Invalidate the tooltip engine's last-item cache before reading contextualized chest tooltip
            C_TooltipInfo.GetItemByID(6948)
        end
        local data = C_TooltipInfo and C_TooltipInfo.GetItemByID
            and C_TooltipInfo.GetItemByID(chestItemId, nil, ctx, lvl > 0 and lvl or nil)
        local remainingNames, remainingIDs = GetRemainingNamesFromTooltip(data)

        local count = 0
        for _ in pairs(remainingNames) do
            count = count + 1
        end
        if count == 0 then
            for _ in pairs(remainingIDs) do
                count = count + 1
            end
        end

        if count == 0 then
            if attempts >= EMPTY_ATTEMPTS then
                if onDone then onDone(0) end
            else
                C_Timer.After(POLL_INTERVAL, Poll)
            end
            return
        end

        if #entries == 0 then
            InferChestSourceFromTooltip(chestItemId, remainingNames, remainingIDs)
            entries = GetRawChestEntries(chestItemId)
            if #entries == 0 then
                if attempts >= MAX_ATTEMPTS then
                    if onDone then onDone(0) end
                else
                    C_Timer.After(POLL_INTERVAL, Poll)
                end
                return
            end
        end

        if count == prevCount then
            stableHits = stableHits + 1
            if stableHits >= STABLE_NEEDED then
                sfui.bonusroll.ApplyResults(entries, remainingNames, onDone, activeSpecID, remainingIDs, true)
                return
            end
        else
            prevCount = count
            stableHits = 1
        end

        if attempts >= MAX_ATTEMPTS then
            sfui.bonusroll.ApplyResults(entries, remainingNames, onDone, activeSpecID, remainingIDs, true)
            return
        end

        C_Timer.After(POLL_INTERVAL, Poll)
    end

    Poll()
end

-- ─── Live Bonus Roll Prompt Capture (YetRolled Architecture) ──────────────────
local function GetCurrentActivePrompt(cacheID)
    local now = _G.time and _G.time() or 0
    local matched = nil
    for _, prompt in pairs(activePrompts) do
        if prompt.expires > now and (not cacheID or prompt.cacheID == cacheID) then
            if matched then return nil end
            matched = prompt
        end
    end
    return matched
end

local function GetResultPrompt()
    local now = _G.time and _G.time() or 0
    if pendingRoll and pendingRoll.expires >= now and pendingRoll.prompt then
        return pendingRoll.prompt
    end
    local active = GetCurrentActivePrompt()
    if active then return active end

    local candidate = nil
    for _, prompt in pairs(recentPrompts) do
        if prompt.closedAt and (now - prompt.closedAt) <= 10 then
            if candidate then return nil end
            candidate = prompt
        end
    end
    if not candidate and next(activePrompts) then return nil end
    return candidate
end

local function ConsumePrompt()
    local prompt = GetResultPrompt()
    if prompt and prompt.spellID then
        if activePrompts[prompt.spellID] == prompt then
            activePrompts[prompt.spellID] = nil
        end
    else
        activePrompts = {}
    end
    pendingRoll = nil
    recentPrompts = {}
end

local function OnBonusRollPrompt(spellID, duration, cacheID, itemContext, level, difficultyID)
    local function SafeNum(v)
        if IsPublicValue(v) and type(v) == "number" then return v end
        return nil
    end

    spellID      = SafeNum(spellID)
    duration     = SafeNum(duration)
    cacheID      = SafeNum(cacheID)
    itemContext  = SafeNum(itemContext)
    level        = SafeNum(level) or 0
    difficultyID = SafeNum(difficultyID)

    local instanceID, encounterID
    if spellID and _G.GetJournalInfoForSpellConfirmation then
        local inst, enc = _G.GetJournalInfoForSpellConfirmation(spellID)
        instanceID, encounterID = SafeNum(inst), SafeNum(enc)
    end

    local native = _G.BonusRollFrame
    local button = native and native.PromptFrame and native.PromptFrame.EncounterJournalLinkButton
    if native and native.state == "prompt" and SafeNum(native.spellID) == spellID
        and button and SafeNum(button.displayItemID) == cacheID then
        instanceID  = (instanceID and instanceID > 0 and instanceID) or SafeNum(native.instanceID)
        encounterID = (encounterID and encounterID > 0 and encounterID) or SafeNum(native.encounterID)
    end

    if encounterID and encounterID > 0 and (not instanceID or instanceID <= 0) and _G.EJ_GetEncounterInfo then
        local inst = SafeNum(select(6, _G.EJ_GetEncounterInfo(encounterID)))
        if inst and inst > 0 then instanceID = inst end
    end

    local challengeModeId = nil
    if not encounterID or encounterID <= 0 then
        local cm = _G.C_ChallengeMode
        if cm then
            if cm.GetCompletionInfo then
                challengeModeId = SafeNum(select(1, cm.GetCompletionInfo()))
            end
            if (not challengeModeId or challengeModeId <= 0) and cm.GetActiveChallengeMapID then
                challengeModeId = SafeNum(cm.GetActiveChallengeMapID())
            end
        end
        if (not instanceID or instanceID <= 0) and _G.C_Map and _G.C_Map.GetBestMapForUnit and _G.EJ_GetInstanceForMap then
            local uiMapID = SafeNum(_G.C_Map.GetBestMapForUnit("player"))
            if uiMapID and uiMapID > 0 then
                local ejInst = SafeNum(_G.EJ_GetInstanceForMap(uiMapID))
                if ejInst and ejInst > 0 then
                    instanceID = ejInst
                end
            end
        end
    end

    if cacheID and cacheID > 0 then
        LearnChestSource(cacheID, instanceID, encounterID, difficultyID, challengeModeId)
        if not CHEST_DATABASE[cacheID] then
            InferChestSourceFromName(cacheID)
        end
    end

    if not spellID or not cacheID or cacheID <= 0 or not itemContext or itemContext <= 0 then
        return
    end

    local now = _G.time and _G.time() or 0
    local prompt = {
        spellID      = spellID,
        cacheID      = cacheID,
        itemContext  = itemContext,
        level        = level,
        difficultyID = difficultyID,
        instanceID   = instanceID,
        encounterID  = encounterID,
        expires      = now + (duration or 180),
    }
    activePrompts[spellID] = prompt
    recentPrompts[spellID] = nil

    local db = DB()
    db.poolContexts[cacheID] = {
        itemContext  = itemContext,
        level        = level,
        difficultyID = difficultyID,
    }

    -- Scan live personal remaining pool for this prompt
    sfui.bonusroll.CheckSupply(cacheID, nil, itemContext, level, true)
end

local function SyncNativePrompt(attempt)
    local frame = _G.BonusRollFrame
    local button = frame and frame.PromptFrame and frame.PromptFrame.EncounterJournalLinkButton
    if not frame or not button or not frame:IsShown() or frame.state ~= "prompt" then return end

    local now = _G.time and _G.time() or 0
    local endTime = IsPublicValue(frame.endTime) and tonumber(frame.endTime)
    local remaining = endTime and (endTime - now)
    if not remaining or remaining <= 0 then return end

    OnBonusRollPrompt(
        frame.spellID,
        remaining,
        button.displayItemID,
        button.itemContext,
        button.treasureContextLevel,
        frame.difficultyID
    )

    local cacheID = IsPublicValue(button.displayItemID) and tonumber(button.displayItemID)
    if cacheID and not CHEST_DATABASE[cacheID] and (attempt or 1) < MAX_ATTEMPTS then
        local spellID = frame.spellID
        C_Timer.After(POLL_INTERVAL, function()
            if frame.spellID == spellID and button.displayItemID == cacheID then
                SyncNativePrompt((attempt or 1) + 1)
            end
        end)
    end
end

local nativePromptHooked = false
local function HookNativePrompt()
    if not nativePromptHooked and _G.BonusRollFrame_StartBonusRoll and _G.hooksecurefunc then
        nativePromptHooked = true
        _G.hooksecurefunc("BonusRollFrame_StartBonusRoll", function()
            C_Timer.After(0, SyncNativePrompt)
        end)
    end
end

function sfui.bonusroll.CheckAll(rescan)
    if not IsPlayerAtMaxLevel() then
        return
    end
    if isScanningAll then
        return
    end

    isScanningAll = true
    SyncFromExternalAddons(true)
    SyncNativePrompt()

    local scanSpecID = GetActiveLootSpecID()
    if scanSpecID and scanSpecID > 0 then
        sessionScannedSpecs[scanSpecID] = true
    end

    local db = DB()
    local total = 0
    for itemID, state in pairs(db.used or {}) do
        if state == true and tonumber(itemID) then
            total = total + 1
        end
    end

    local activePrompt = GetCurrentActivePrompt()
    local function FinishScan()
        isScanningAll = false
        db.checked = true
        if rescan then
            local printMsg = sfui.common.print
            if total > 0 then
                printMsg(string.format("(bonus roll): %d bonus-rolled item(s) synced.", total))
            else
                printMsg("(bonus roll): bonus roll tracking is up to date.")
            end
        end
        if sfui.lootviewer and sfui.lootviewer.frame and sfui.lootviewer.frame:IsShown() and sfui.lootviewer.Rebuild then
            sfui.lootviewer.Rebuild()
        end
    end

    if activePrompt and activePrompt.cacheID and activePrompt.itemContext then
        sfui.bonusroll.CheckSupply(
            activePrompt.cacheID,
            function() FinishScan() end,
            activePrompt.itemContext,
            activePrompt.level,
            true
        )
    else
        FinishScan()
    end
end

function sfui.bonusroll.EnsureCurrentSpecScanned()
    if not IsPlayerAtMaxLevel() then return end
    SyncFromExternalAddons()
    SyncNativePrompt()
    local specID = GetActiveLootSpecID()
    if specID and specID > 0 and not sessionScannedSpecs[specID] and not isScanningAll then
        sfui.bonusroll.CheckAll(false)
    end
end

local function ScheduleSpecScan(delay)
    if pendingScanTimer then
        pendingScanTimer:Cancel()
        pendingScanTimer = nil
    end
    pendingScanTimer = C_Timer.NewTimer(delay or 1.5, function()
        pendingScanTimer = nil
        sfui.bonusroll.EnsureCurrentSpecScanned()
    end)
end

-- ─── Real-Time Bonus Roll Event Handler ───────────────────────────────────────
local function FindChestForItem(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    local checkIDs = { [itemID] = true }
    local linked = GetLinkedIDs(itemID)
    if linked then
        for linkedID in pairs(linked) do
            checkIDs[linkedID] = true
        end
    end

    for cId in pairs(CHEST_DATABASE) do
        local entries = GetRawChestEntries(cId)
        for _, entry in ipairs(entries) do
            if checkIDs[entry.id] then
                return cId
            end
        end
    end
    return nil
end

function sfui.bonusroll.OnBonusRoll(itemID, rewardLink, serverSpecID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then return end
    if EXCLUDED_ITEMS[itemID] then return end

    local prompt = GetResultPrompt()
    local activeSpecID = (tonumber(serverSpecID) and tonumber(serverSpecID) > 0 and tonumber(serverSpecID))
        or (pendingRoll and tonumber(pendingRoll.specID))
        or GetActiveLootSpecID()

    sfui.bonusroll.SetUsed(itemID, true, rewardLink, activeSpecID, false, true)

    local db = DB()
    local chestItemId = (prompt and prompt.cacheID) or FindChestForItem(itemID)
    db.history = db.history or {}
    db.history[#db.history + 1] = {
        itemID       = itemID,
        itemLink     = rewardLink,
        specID       = activeSpecID,
        seasonID     = GetCurrentSeasonID(),
        cacheID      = chestItemId,
        itemContext  = prompt and prompt.itemContext or nil,
        level        = prompt and prompt.level or nil,
        difficultyID = prompt and prompt.difficultyID or nil,
        encounterID  = prompt and prompt.encounterID or nil,
        instanceID   = prompt and prompt.instanceID or nil,
        timestamp    = _G.time and _G.time() or 0,
    }

    local promptCtx = prompt and prompt.itemContext
    local promptLvl = prompt and prompt.level
    ConsumePrompt()

    if not chestItemId or not promptCtx then return end

    -- Re-verify contextualized chest tooltip shortly after roll (including full-pool cycle reset)
    C_Timer.After(1.5, function()
        sfui.bonusroll.CheckSupply(chestItemId, function()
            if sfui.lootviewer and sfui.lootviewer.frame and sfui.lootviewer.frame:IsShown() and sfui.lootviewer.Rebuild then
                sfui.lootviewer.Rebuild()
            end
        end, promptCtx, promptLvl, true)
    end)
end

-- ─── Event Registrations ──────────────────────────────────────────────────────
HookNativePrompt()

sfui.events.RegisterEvent("ADDON_LOADED", function()
    HookNativePrompt()
end)

sfui.events.RegisterEvent("SPELL_CONFIRMATION_PROMPT", function(_, spellID, _, _, duration, _, _, difficultyID, cacheID, itemContext, level)
    OnBonusRollPrompt(spellID, duration, cacheID, itemContext, level, difficultyID)
end)

sfui.events.RegisterEvent("SPELL_CONFIRMATION_TIMEOUT", function(_, spellID)
    local id = IsPublicValue(spellID) and tonumber(spellID)
    if id and activePrompts[id] then
        local prompt = activePrompts[id]
        prompt.closedAt = _G.time and _G.time() or 0
        recentPrompts[id] = prompt
        activePrompts[id] = nil
    end
end)

sfui.events.RegisterEvent("BONUS_ROLL_STARTED", function()
    local prompt = GetCurrentActivePrompt()
    local now = _G.time and _G.time() or 0
    pendingRoll = prompt and {
        prompt  = prompt,
        specID  = GetActiveLootSpecID(),
        expires = now + 60,
    } or nil
end)

sfui.events.RegisterEvent("BONUS_ROLL_FAILED", function()
    ConsumePrompt()
end)

sfui.events.RegisterEvent("BONUS_ROLL_RESULT", function(_, rewardType, rewardLink, _, serverSpecID)
    if type(rewardLink) ~= "string" or not rewardLink:find("item:", 1, true) then
        if rewardType ~= "item" or not rewardLink then return end
    end
    local itemID = sfui.common.get_item_id(rewardLink) or tonumber(type(rewardLink) == "string" and rewardLink:match("item:(%d+)"))
    if itemID then
        sfui.bonusroll.OnBonusRoll(itemID, rewardLink, serverSpecID)
    end
end)

sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isLogin, isReload)
    C_Timer.After(0, SyncNativePrompt)
    if isLogin or isReload then
        ScheduleSpecScan(2.0)
    end
end)

sfui.events.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function(_, unit)
    if not unit or unit == "player" then
        ScheduleSpecScan(0.5)
    end
end)

sfui.events.RegisterEvent("PLAYER_LOOT_SPEC_UPDATED", function()
    ScheduleSpecScan(0.5)
end)

local _brDebug = {}
function sfui.bonusroll_debug_info()
    local db = DB and DB()
    local pending = 0
    if db and db.pendingRolls then
        for _ in pairs(db.pendingRolls) do pending = pending + 1 end
    end
    _brDebug.enabled = true
    _brDebug.pendingRolls = pending
    _brDebug.checked = db and db.checked or false
    return _brDebug
end

if sfui.RegisterModule then
    sfui.bonusroll.GetDebugInfo = sfui.bonusroll_debug_info
    sfui.RegisterModule("bonusroll", sfui.bonusroll)
end
