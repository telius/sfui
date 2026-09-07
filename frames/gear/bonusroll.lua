local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.bonusroll = {}

local CreateFrame               = CreateFrame
local UIParent                  = UIParent
local UnitClass                 = UnitClass
local UnitGUID                  = UnitGUID
local UnitName                  = UnitName
local GetRealmName              = GetRealmName
local GetSpecialization         = GetSpecialization
local GetSpecializationInfo     = GetSpecializationInfo
local C_TooltipInfo             = C_TooltipInfo
local C_Timer                   = C_Timer
local C_Item                    = C_Item
local Item                      = Item
local tonumber                  = tonumber
local tostring                  = tostring
local pairs                     = pairs
local ipairs                    = ipairs
local print                     = print
local string                    = string
local table                     = table

-- ─── Constants & Configuration ────────────────────────────────────────────────
local POLL_INTERVAL  = 0.3
local EMPTY_ATTEMPTS = 5
local STABLE_NEEDED  = 3
local MAX_ATTEMPTS   = 10
local OTHER_SLOT     = 14

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
}

local EXCLUDED_ITEMS = {
    [151299] = true, -- Not in the bonus roll chest (Blizzard item pool quirk)
    [260235] = true, -- Umbral Feather
    [258045] = true, -- Duskblade Glaives
    [281227] = true, -- Rush'kah of the Soulwinder
    [275937] = true, -- Face of the Hexlord
    [275938] = true, -- Gaze of the Hexlord
}

-- ─── Database Access Helpers ──────────────────────────────────────────────────
local function GetPlayerKey()
    local guid = UnitGUID("player")
    if guid and guid ~= "" then return guid end
    local name = UnitName("player")
    local realm = GetRealmName()
    if name and realm and name ~= "" and realm ~= "" then
        return name .. "-" .. realm
    end
    return "player"
end

local function DB()
    SfuiDB = SfuiDB or {}
    SfuiDB.bonusroll = SfuiDB.bonusroll or {}
    local key = GetPlayerKey()
    if not SfuiDB.bonusroll[key] then
        SfuiDB.bonusroll[key] = {
            used    = {},
            checked = false,
        }
    end
    return SfuiDB.bonusroll[key]
end

-- ─── Item & Spec Eligibility ──────────────────────────────────────────────────
local itemToChestMap = nil
local function BuildItemToChestMap()
    if itemToChestMap then return itemToChestMap end
    itemToChestMap = {}
    return itemToChestMap
end

function sfui.bonusroll.IsEligible(itemID)
    if not itemID or itemID <= 0 then return false end
    if EXCLUDED_ITEMS[itemID] then return false end

    -- Check if item is non-equipment / generic "Other" slot
    local _, _, _, itemEquipLoc, _, classID, subclassID = GetItemInfoInstant(itemID)
    if classID == 5 and subclassID == 2 then return false end
    if not itemEquipLoc or itemEquipLoc == "" or itemEquipLoc == "INVTYPE_NON_EQUIP_IGNORE" then
        return false
    end

    return true
end

function sfui.bonusroll.IsUsed(itemID)
    if not itemID or itemID <= 0 then return false end

    -- Check local database
    local db = DB()
    if db.used and db.used[itemID] == true then
        return true
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

function sfui.bonusroll.SetUsed(itemID, value)
    if not itemID or itemID <= 0 then return end
    local db = DB()
    db.used = db.used or {}
    if value then
        db.used[itemID] = true
    else
        db.used[itemID] = nil
    end

    local mirror = MIRROR_ITEMS[itemID]
    if mirror then
        if value then
            db.used[mirror] = true
        else
            db.used[mirror] = nil
        end
    end

    -- Compatibility: sync with KeystoneLoot if active
    if _G.KeystoneLoot and _G.KeystoneLoot.Voidcore and _G.KeystoneLoot.Voidcore.SetUsed then
        pcall(_G.KeystoneLoot.Voidcore.SetUsed, _G.KeystoneLoot.Voidcore, itemID, value)
    end

    if sfui.lootviewer and sfui.lootviewer.frame and sfui.lootviewer.frame:IsShown() then
        sfui.lootviewer.Rebuild()
    end
end

-- ─── Source Candidate Extraction ──────────────────────────────────────────────
local function GetChestSource(chestItemId)
    return CHEST_DATABASE[chestItemId]
end

local function GetLootTableForChest(chestItemId)
    local source = GetChestSource(chestItemId)
    if not source then return {} end

    local lootList = {}

    if source.challengeModeId then
        -- Look up dungeon loot in sfui.lootviewer cache or challenge mode table
        if sfui.lootviewer and sfui.lootviewer.GetDungeonData then
            local dungeons = sfui.lootviewer.GetDungeonData()
            for _, d in ipairs(dungeons) do
                if d.mapID == source.challengeModeId then
                    for _, it in ipairs(d.loot or {}) do
                        lootList[#lootList + 1] = it.id
                    end
                    break
                end
            end
        end
        -- Fallback: check KeystoneLoot database if available
        if #lootList == 0 and _G.KeystoneLoot and _G.KeystoneLoot.Query and _G.KeystoneLoot.Query.GetDungeons then
            local ok, dList = pcall(_G.KeystoneLoot.Query.GetDungeons, _G.KeystoneLoot.Query)
            if ok and dList then
                for _, d in ipairs(dList) do
                    if d.challengeModeId == source.challengeModeId and d.lootTable then
                        for _, id in ipairs(d.lootTable) do
                            lootList[#lootList + 1] = id
                        end
                        break
                    end
                end
            end
        end
    elseif source.bossId then
        -- Look up raid boss loot in sfui.lootviewer
        if sfui.lootviewer and sfui.lootviewer.GetRaidData then
            local raids = sfui.lootviewer.GetRaidData()
            for _, r in ipairs(raids) do
                for _, b in ipairs(r.bosses or {}) do
                    if b.encounterID == source.bossId or b.dungeonEncounterID == source.bossId then
                        for _, it in ipairs(b.loot or {}) do
                            lootList[#lootList + 1] = it.id
                        end
                        break
                    end
                end
            end
        end
        -- Fallback: check KeystoneLoot raid database
        if #lootList == 0 and _G.KeystoneLoot and _G.KeystoneLoot.Query and _G.KeystoneLoot.Query.GetRaids then
            local ok, rList = pcall(_G.KeystoneLoot.Query.GetRaids, _G.KeystoneLoot.Query)
            if ok and rList then
                for _, r in ipairs(rList) do
                    for _, b in ipairs(r.bossList or {}) do
                        if b.bossId == source.bossId and b.lootTable then
                            local mythicTable = b.lootTable[16] or b.lootTable[DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.PrimaryRaidMythic or 16] or b.lootTable[1]
                            if mythicTable then
                                for _, id in ipairs(mythicTable) do
                                    lootList[#lootList + 1] = id
                                end
                            end
                            break
                        end
                    end
                end
            end
        end
    end

    return lootList
end

function sfui.bonusroll.GetSourceItems(chestItemId, specID)
    local lootTable = GetLootTableForChest(chestItemId)
    if not lootTable or #lootTable == 0 then return {} end

    local activeSpec = specID
    if not activeSpec or activeSpec == 0 then
        local spec = GetSpecialization()
        activeSpec = spec and select(1, GetSpecializationInfo(spec)) or 0
    end

    local results = {}
    for _, itemID in ipairs(lootTable) do
        if sfui.bonusroll.IsEligible(itemID) then
            results[#results + 1] = itemID
        end
    end

    return results
end

function sfui.bonusroll.ResetSource(candidates)
    for _, itemID in ipairs(candidates) do
        sfui.bonusroll.SetUsed(itemID, nil)
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

function sfui.bonusroll.ApplyResults(candidates, remainingNames)
    for _, itemID in ipairs(candidates) do
        if Item and Item.CreateFromItemID then
            local itemObj = Item.CreateFromItemID(itemID)
            itemObj:ContinueOnItemLoad(function()
                local name = itemObj:GetItemName()
                local obtained = (name ~= nil and not remainingNames[name])
                if obtained then
                    sfui.bonusroll.SetUsed(itemID, true)
                end
            end)
        else
            local name = select(1, C_Item.GetItemInfo(itemID)) or select(1, GetItemInfo(itemID))
            if name and not remainingNames[name] then
                sfui.bonusroll.SetUsed(itemID, true)
            end
        end
    end
end

function sfui.bonusroll.CheckSupply(chestItemId, onDone)
    local spec = GetSpecialization()
    local activeSpecID = spec and select(1, GetSpecializationInfo(spec)) or 0
    local candidates = sfui.bonusroll.GetSourceItems(chestItemId, activeSpecID)

    if #candidates == 0 then
        if onDone then onDone(0) end
        return
    end

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
                if count >= #candidates then
                    -- Full pool visible in tooltip -> fresh character or reset, clear source items
                    sfui.bonusroll.ResetSource(candidates)
                    if onDone then onDone(0) end
                else
                    sfui.bonusroll.ApplyResults(candidates, remaining)
                    if onDone then onDone(#candidates - count) end
                end
                return
            end
        else
            prevCount = count
            stableHits = 1
        end

        if attempts >= MAX_ATTEMPTS then
            if onDone then onDone(0) end
            return
        end

        C_Timer.After(POLL_INTERVAL, Poll)
    end

    Poll()
end

function sfui.bonusroll.CheckAll(rescan)
    local chestIds = {}
    for chestItemId in pairs(CHEST_DATABASE) do
        chestIds[#chestIds + 1] = chestItemId
    end

    local prefix = "|cff00ccffSFUI|r (Bonus Roll): "
    if rescan then
        print(prefix .. "Rescanning server bonus roll history...")
    else
        print(prefix .. "Checking past bonus rolls...")
    end

    local total = 0
    local index = 0

    local function Next(obtained)
        total = total + (obtained or 0)
        index = index + 1
        local chestItemId = chestIds[index]
        if not chestItemId then
            if total > 0 then
                print(prefix .. string.format("%d past bonus roll(s) detected and synced.", total))
            else
                print(prefix .. "Bonus roll tracking is up to date.")
            end
            DB().checked = true
            if sfui.lootviewer and sfui.lootviewer.frame and sfui.lootviewer.frame:IsShown() then
                sfui.lootviewer.Rebuild()
            end
            return
        end

        sfui.bonusroll.CheckSupply(chestItemId, Next)
    end

    Next()
end

-- ─── Real-Time Bonus Roll Event Handler ───────────────────────────────────────
function sfui.bonusroll.OnBonusRoll(itemID)
    if not sfui.bonusroll.IsEligible(itemID) then return end

    sfui.bonusroll.SetUsed(itemID, true)

    -- Look up chest item ID for this item
    local chestItemId = nil
    for cId in pairs(CHEST_DATABASE) do
        local sourceItems = sfui.bonusroll.GetSourceItems(cId)
        for _, id in ipairs(sourceItems) do
            if id == itemID then
                chestItemId = cId
                break
            end
        end
        if chestItemId then break end
    end

    if not chestItemId then return end

    -- If all candidates for this chest are now used, Blizzard resets the chest pool -> reset source
    local spec = GetSpecialization()
    local activeSpecID = spec and select(1, GetSpecializationInfo(spec)) or 0
    local candidates = sfui.bonusroll.GetSourceItems(chestItemId, activeSpecID)

    for _, candId in ipairs(candidates) do
        if not sfui.bonusroll.IsUsed(candId) then
            return
        end
    end

    sfui.bonusroll.ResetSource(candidates)
end

-- ─── Event Registrations ──────────────────────────────────────────────────────
sfui.events.RegisterEvent("BONUS_ROLL_RESULT", function(_, rewardType, rewardLink)
    if rewardType ~= "item" or not rewardLink then return end
    local itemID = tonumber(string.match(rewardLink, "item:(%d+)"))
    if itemID then
        sfui.bonusroll.OnBonusRoll(itemID)
    end
end)

sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isLogin, isReload)
    if isLogin or isReload then
        C_Timer.After(4.0, function()
            local db = DB()
            if not db.checked then
                sfui.bonusroll.CheckAll(false)
            end
        end)
    end
end)
