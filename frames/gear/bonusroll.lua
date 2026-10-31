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

-- ─── Reward Chest Item Database (KeystoneLoot / Retail Voidcore Mappings) ─────
local CHEST_DATABASE = {
    -- Dungeons (challengeModeId)
    [268470] = { challengeModeId = 161 }, -- Skyreach (Die Himmelsnadel)
    [268469] = { challengeModeId = 239 }, -- Seat of the Triumvirate (Sitz des Triumvirats)
    [268465] = { challengeModeId = 402 }, -- Algeth'ar Academy (Akademie von Algeth'ar)
    [268468] = { challengeModeId = 556 }, -- Pit of Saron (Grube von Saron)
    [268471] = { challengeModeId = 557 }, -- Windrunner Spire (Windlaeuferturm)
    [268466] = { challengeModeId = 558 }, -- Magisters' Terrace (Terrasse der Magister)
    [268467] = { challengeModeId = 559 }, -- Nexus-Point Xenas (Nexuspunkt Xenas)
    [268473] = { challengeModeId = 560 }, -- Maisara Caverns (Maisarakavernen)
    [279621] = { challengeModeId = 249 }, -- Kings' Rest (Die Königsruh)
    [279624] = { challengeModeId = 250 }, -- Temple of Sethraliss (Der Tempel von Sethraliss)
    [279622] = { challengeModeId = 399 }, -- Ruby Life Pools (Rubinlebensbecken)
    [279619] = { challengeModeId = 584 }, -- The Dazzling Valley (Das blendende Tal)
    [279625] = { challengeModeId = 585 }, -- Voidscar Arena (Arena der Leerennarbe)
    [279620] = { challengeModeId = 586 }, -- Nalorakk's Den (Nalorakks Bau)
    [279623] = { challengeModeId = 587 }, -- Murder Row (Mördergasse)
    [279618] = { challengeModeId = 588 }, -- Altar of the Fangs (Altar der Fänge)

    -- Raid Bosses (encounterID / bossId)
    [268459] = { bossId = 2733 }, -- Imperator Averzian
    [268460] = { bossId = 2734 }, -- Vorasius
    [268462] = { bossId = 2735 }, -- Vaelgor & Ezzorak
    [268461] = { bossId = 2736 }, -- Fallen King Salhadaar
    [268463] = { bossId = 2737 }, -- Lightblind Vanguard
    [268458] = { bossId = 2739 }, -- Belo'ren, Child of Al'ar
    [268464] = { bossId = 2795 }, -- Chimaerus, the Undreamt God
    [267488] = { bossId = 2738 }, -- Crown of the Cosmos
    [262658] = { bossId = 2740 }, -- Midnight Falls
    [275228] = { bossId = 2711 }, -- Rottmoor
    [274708] = { bossId = 2849 }, -- Nymrissa Wavespeaker
    [278285] = { bossId = 2888 }, -- Nek'zali the Soulwinder
    [278283] = { bossId = 2874 }, -- Trapped Sentinels
    [278286] = { bossId = 2894 }, -- The Lost Explorers
    [278287] = { bossId = 2882 }, -- Vashnik the Vicious
    [278288] = { bossId = 2871 }, -- Sszorak
    [278289] = { bossId = 2887 }, -- The Twin Fangs
    [278290] = { bossId = 2883 }, -- The Winding Altar
    [278284] = { bossId = 2895 }, -- Ula'tek
}

local MIRROR_ITEMS = {
    [249806] = 260235, -- Radiant Feather -> Umbral Feather
    [260235] = 249806,
}

local EXCLUDED_ITEMS = {
    [151299] = true, -- Not in the bonus roll chest (Blizzard item pool quirk)
    [260235] = true, -- Umbral Feather
    [258045] = true, -- Duskblade Glaives
    [281227] = true, -- Rush'kah of the Soulwinder
    [275937] = true, -- Face of the Hexlord
    [275938] = true, -- Gaze of the Hexlord
}

local GetPlayerKey = sfui.common.get_player_unique_key
local SCAN_VERSION = 3

local sessionScannedSpecs = {}
local isScanningAll = false
local pendingScanTimer = nil

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
            checked         = false,
            scanVersion     = SCAN_VERSION,
            targets         = {
                dungeons = {},
                bosses   = {},
                items    = {},
            },
        }
    end
    local db = SfuiDB.bonusroll[key]
    if db.scanVersion ~= SCAN_VERSION then
        db.used         = {}
        db.usedBySpec   = db.usedBySpec or {}
        db.rolledItems  = db.rolledItems or {}
        db.rolledBySpec = db.rolledBySpec or {}
        db.manual       = db.manual or {}
        db.checked      = false
        db.scanVersion  = SCAN_VERSION
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
    db.used         = db.used or {}
    db.usedBySpec   = db.usedBySpec or {}
    db.rolledItems  = db.rolledItems or {}
    db.rolledBySpec = db.rolledBySpec or {}
    db.manual       = db.manual or {}
    db.targets      = db.targets or {}
    db.targets.dungeons = db.targets.dungeons or {}
    db.targets.bosses   = db.targets.bosses or {}
    db.targets.items    = db.targets.items or {}
    return db
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

local function ItemMatchesSpec(itemID, specID, ejSpecs)
    if not itemID or not specID or specID <= 0 then return true end
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

    local _, _, _, itemEquipLoc, _, classID, subclassID = sfui.common.get_item_instant_info(itemID)
    if classID == 5 and subclassID == 2 then return false end
    if not itemEquipLoc or itemEquipLoc == "" or itemEquipLoc == "INVTYPE_NON_EQUIP_IGNORE" then
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

local externalSynced = false
local function SyncFromExternalAddons()
    if externalSynced then return end
    local tabrDB = _G.TheAlmightyBonusRollDB
    if type(tabrDB) ~= "table" or type(tabrDB.history) ~= "table" then return end
    externalSynced = true

    local name, realm = UnitFullName and UnitFullName("player")
    if not name or name == "" then name = UnitName and UnitName("player") end
    realm = (realm and realm ~= "" and realm) or (GetRealmName and GetRealmName()) or ""
    if not name or name == "" then return end
    local charKey = name .. "-" .. realm

    local seasonKey = nil
    if _G.TheAlmightyBonusRoll and type(_G.TheAlmightyBonusRoll.GetSeasonKey) == "function" then
        local ok, key = pcall(_G.TheAlmightyBonusRoll.GetSeasonKey, _G.TheAlmightyBonusRoll)
        if ok and type(key) == "string" then seasonKey = key end
    end

    local db = DB()
    for _, entry in ipairs(tabrDB.history) do
        if type(entry) == "table" and entry.characterKey == charKey and (not seasonKey or not entry.seasonKey or entry.seasonKey == seasonKey) then
            local specID = tonumber(entry.lootSpecID) or tonumber(entry.serverSpecID) or 0
            local isManual = entry.manual == true
            for _, rawID in ipairs({ entry.itemID, entry.tokenItemID }) do
                local id = tonumber(rawID)
                if id and id > 0 then
                    ApplyStateToID(db, id, true, specID, isManual, not isManual)
                    local linked = GetLinkedIDs(id)
                    if linked then
                        for linkedID in pairs(linked) do
                            ApplyStateToID(db, linkedID, true, specID, isManual, not isManual)
                        end
                    end
                end
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
local function GetChestSource(chestItemId)
    return CHEST_DATABASE[chestItemId]
end

local function GetRawChestEntries(chestItemId)
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
                            ejSpecs = it.ejSpecs or it.specs,
                        }
                    end
                end
            end
        end
    end

    if source.challengeModeId then
        if sfui.lootviewer and sfui.lootviewer.GetDungeonData then
            local dungeons = sfui.lootviewer.GetDungeonData()
            for _, d in ipairs(dungeons or {}) do
                if d.mapID == source.challengeModeId then
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

    return entries
end

function sfui.bonusroll.GetSourceItems(chestItemId, specID)
    local activeSpec = (specID and specID > 0 and specID) or GetActiveLootSpecID()
    local rawEntries = GetRawChestEntries(chestItemId)
    if #rawEntries == 0 then return {} end

    local results = {}
    for _, entry in ipairs(rawEntries) do
        if ItemMatchesSpec(entry.id, activeSpec, entry.ejSpecs) then
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

-- ─── Tooltip Parsing & Server History Scanner ─────────────────────────────────
local function GetRemainingNamesFromTooltip(tooltipData)
    local names = {}
    if not tooltipData or not tooltipData.lines then return names end

    for i = #tooltipData.lines, 1, -1 do
        local lineText = tooltipData.lines[i].leftText or ""
        local name = lineText:match("^%s*%-%s*(.+)$")
        if name and name ~= "" then
            names[name] = true
        elseif next(names) then
            break
        end
    end

    return names
end

local function CountMatchesForSpec(entries, resolvedNames, remainingNames, specID)
    local matched = 0
    local totalForSpec = 0
    local matchedNames = {}
    for _, entry in ipairs(entries) do
        local numID = entry.id
        if ItemMatchesSpec(numID, specID, entry.ejSpecs) then
            totalForSpec = totalForSpec + 1
            local name = resolvedNames[numID]
            if name and remainingNames[name] and not matchedNames[name] then
                matchedNames[name] = true
                matched = matched + 1
            end
        end
    end
    return matched, totalForSpec
end

function sfui.bonusroll.ApplyResults(candidatesOrEntries, remainingNames, onApplied, explicitSpecID)
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
            local lootMatched = CountMatchesForSpec(entries, resolvedNames, remainingNames, lootSpecID)
            local curMatched = CountMatchesForSpec(entries, resolvedNames, remainingNames, curSpecID)
            if curMatched > lootMatched then
                tooltipSpecID = curSpecID
            end
        end

        local specCandidates = {}
        local matchedInTooltip = 0
        local matchedTooltipNames = {}
        local missingIDs = {}

        for _, entry in ipairs(entries) do
            local numID = entry.id
            if ItemMatchesSpec(numID, tooltipSpecID, entry.ejSpecs) then
                specCandidates[#specCandidates + 1] = numID
                local name = resolvedNames[numID]
                if remainingNames[name] then
                    if not matchedTooltipNames[name] then
                        matchedTooltipNames[name] = true
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
            -- Full pool for this spec is present in the chest tooltip -> clear spec state
            sfui.bonusroll.ResetSource(specCandidates, tooltipSpecID)
            if onApplied then onApplied(0) end
            return
        end

        -- Partial pool in tooltip -> mark present items as available for this spec and missing items as used
        local db = DB()
        for _, numID in ipairs(specCandidates) do
            local name = resolvedNames[numID]
            if remainingNames[name] then
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
                resolvedNames[numID] = itemObj:GetItemName()
                pending = pending - 1
                if pending == 0 then
                    Finalize()
                end
            end)
        else
            resolvedNames[numID] = select(1, sfui.common.get_item_info(numID))
            pending = pending - 1
            if pending == 0 then
                Finalize()
            end
        end
    end
end

function sfui.bonusroll.CheckSupply(chestItemId, onDone)
    if not IsPlayerAtMaxLevel() then
        if onDone then onDone(0) end
        return
    end

    local entries = GetRawChestEntries(chestItemId)
    if #entries == 0 then
        if onDone then onDone(0) end
        return
    end

    local activeSpecID = GetActiveLootSpecID()
    local attempts   = 0
    local prevCount  = -1
    local stableHits = 0

    local function Poll()
        attempts = attempts + 1

        local data = C_TooltipInfo and C_TooltipInfo.GetItemByID and C_TooltipInfo.GetItemByID(chestItemId)
        local remaining = GetRemainingNamesFromTooltip(data)

        local count = 0
        for _ in pairs(remaining) do
            count = count + 1
        end

        if count == 0 then
            if attempts >= EMPTY_ATTEMPTS then
                if onDone then onDone(0) end
            else
                C_Timer.After(POLL_INTERVAL, Poll)
            end
            return
        end

        if count == prevCount then
            stableHits = stableHits + 1
            if stableHits >= STABLE_NEEDED then
                sfui.bonusroll.ApplyResults(entries, remaining, onDone, activeSpecID)
                return
            end
        else
            prevCount = count
            stableHits = 1
        end

        if attempts >= MAX_ATTEMPTS then
            sfui.bonusroll.ApplyResults(entries, remaining, onDone, activeSpecID)
            return
        end

        C_Timer.After(POLL_INTERVAL, Poll)
    end

    Poll()
end

function sfui.bonusroll.CheckAll(rescan)
    if not IsPlayerAtMaxLevel() then
        return
    end
    if isScanningAll then
        return
    end

    SyncFromExternalAddons()

    local scanSpecID = GetActiveLootSpecID()
    isScanningAll = true

    local chestIds = {}
    for chestItemId in pairs(CHEST_DATABASE) do
        chestIds[#chestIds + 1] = chestItemId
    end

    local printMsg = sfui.common.print
    if rescan then
        printMsg("(bonus roll): rescanning server bonus roll history...")
    end

    local total = 0
    local index = 0

    local function Next(obtained)
        total = total + (obtained or 0)
        index = index + 1
        local chestItemId = chestIds[index]
        if not chestItemId then
            isScanningAll = false
            if scanSpecID and scanSpecID > 0 then
                sessionScannedSpecs[scanSpecID] = true
            end
            if rescan then
                if total > 0 then
                    printMsg(string.format("(bonus roll): %d bonus-rolled item(s) detected and synced.", total))
                else
                    printMsg("(bonus roll): bonus roll tracking is up to date.")
                end
            end
            DB().checked = true
            if sfui.lootviewer and sfui.lootviewer.frame and sfui.lootviewer.frame:IsShown() and sfui.lootviewer.Rebuild then
                sfui.lootviewer.Rebuild()
            end
            return
        end

        sfui.bonusroll.CheckSupply(chestItemId, Next)
    end

    Next()
end

function sfui.bonusroll.EnsureCurrentSpecScanned()
    if not IsPlayerAtMaxLevel() then return end
    SyncFromExternalAddons()
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
    if not sfui.bonusroll.IsEligible(itemID) then return end

    local activeSpecID = (tonumber(serverSpecID) and tonumber(serverSpecID) > 0 and tonumber(serverSpecID)) or GetActiveLootSpecID()
    sfui.bonusroll.SetUsed(itemID, true, rewardLink, activeSpecID, false, true)

    local chestItemId = FindChestForItem(itemID)
    if not chestItemId then return end

    -- Re-verify chest tooltip shortly after roll to sync exact server pool state (including full-pool reset)
    C_Timer.After(2.0, function()
        sfui.bonusroll.CheckSupply(chestItemId, function()
            if sfui.lootviewer and sfui.lootviewer.frame and sfui.lootviewer.frame:IsShown() and sfui.lootviewer.Rebuild then
                sfui.lootviewer.Rebuild()
            end
        end)
    end)
end

-- ─── Event Registrations ──────────────────────────────────────────────────────
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
    if isLogin or isReload then
        ScheduleSpecScan(4.0)
    end
end)

sfui.events.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function(_, unit)
    if not unit or unit == "player" then
        ScheduleSpecScan(1.5)
    end
end)

sfui.events.RegisterEvent("PLAYER_LOOT_SPEC_UPDATED", function()
    ScheduleSpecScan(1.5)
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
