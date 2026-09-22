local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.alts = sfui.alts or {}

-- Guard: Retail only
if not sfui.isRetail then
    return
end

local cfg = sfui.config.alts or {}

-- Localized APIs
local table = table
local math = math
local math_max = math.max
local wipe = _G.wipe or table.wipe
local unpack = _G.unpack or table.unpack
local tostring = tostring
local tonumber = tonumber
local string = string
local ipairs = ipairs
local pairs = pairs
local next = next
local type = type
local GameTooltip = _G.GameTooltip
local NORMAL_FONT_COLOR = _G.NORMAL_FONT_COLOR
local GREEN_FONT_COLOR = _G.GREEN_FONT_COLOR
local RED_FONT_COLOR = _G.RED_FONT_COLOR
local C_ChallengeMode = _G.C_ChallengeMode
local C_MythicPlus = _G.C_MythicPlus
local C_WeeklyRewards = _G.C_WeeklyRewards
local C_CurrencyInfo = _G.C_CurrencyInfo
local C_UIWidgetManager = _G.C_UIWidgetManager
local C_Item = _G.C_Item
local C_TradeSkillUI = _G.C_TradeSkillUI
local C_DateAndTime = _G.C_DateAndTime
local C_QuestLog = _G.C_QuestLog
local InCombatLockdown = _G.InCombatLockdown
local GetServerTime = _G.GetServerTime
local RequestRaidInfo = _G.RequestRaidInfo
local EJ_GetCurrentTier = _G.EJ_GetCurrentTier
local EJ_SelectTier = _G.EJ_SelectTier
local EJ_GetNumTiers = _G.EJ_GetNumTiers
local EJ_GetInstanceByIndex = _G.EJ_GetInstanceByIndex
local EJ_GetEncounterInfoByIndex = _G.EJ_GetEncounterInfoByIndex
local GetSavedInstanceInfo = _G.GetSavedInstanceInfo
local GetSavedInstanceEncounterInfo = _G.GetSavedInstanceEncounterInfo
local GetNumSavedInstances = _G.GetNumSavedInstances
local IsModifiedClick = _G.IsModifiedClick
local ChatEdit_InsertLink = _G.ChatEdit_InsertLink
local ChatFrame_OpenChat = _G.ChatFrame_OpenChat
local securecall = _G.securecall

local AcquireTable = sfui.alts.AcquireTable
local ReleaseTable = sfui.alts.ReleaseTable
local ReleaseTableRecursive = sfui.alts.ReleaseTableRecursive

local PROF_KP_SOURCES = sfui.season and sfui.season.PROF_KP_SOURCES or {}
local CURRENCIES = sfui.season and sfui.season.CURRENCIES or {}

local PROF_SHORT_NAMES = {
    ["Blacksmithing"] = "bs",
    ["Leatherworking"] = "lw",
    ["Tailoring"] = "tailor",
    ["Engineering"] = "engi",
    ["Enchanting"] = "enchant",
    ["Alchemy"] = "alch",
    ["Jewelcrafting"] = "jc",
    ["Inscription"] = "inscr",
    ["Herbalism"] = "herb",
    ["Mining"] = "mining",
    ["Skinning"] = "skin",
}

local function GetShortProfName(name)
    if not name or name == "" then return "prof" end
    if PROF_SHORT_NAMES[name] then return PROF_SHORT_NAMES[name] end
    for fullName, short in pairs(PROF_SHORT_NAMES) do
        if string.find(name, fullName, 1, true) then
            return short
        end
    end
    return name:lower()
end

local BASE_CATEGORIES = {
    { name = "GENERAL",       label = "character",     type = "header" },
    { name = "ILVL",          label = "level / ilvl",  type = "stat",       key = "iLvl",     format = "%.1f" },
    { name = "RATING",        label = "m+ rating",     type = "stat",       key = "rating" },
    { name = "KEYSTONE",      label = "current key",   type = "keystone" },

    { name = "QUESTS_HEADER", label = "weekly quests", type = "header" },
    { name = "QUESTS_GRID",   label = "quests",        type = "quests_grid" },

    { name = "VAULT_HEADER",  label = "great vault",   type = "header" },
    { name = "VAULT_RAID",    label = "raid",          type = "vault_row",  group = "raid" },
    { name = "VAULT_DUNGEON", label = "dungeon",       type = "vault_row",  group = "dungeon" },
    { name = "VAULT_WORLD",   label = "world/delve",   type = "vault_row",  group = "world" },

    { name = "RAID_HEADER",   label = "raid progress", type = "header" },
    { name = "RAID_M",        label = "mythic",        type = "raid_grid",  difficulty = 16 },
    { name = "RAID_H",        label = "heroic",        type = "raid_grid",  difficulty = 15 },
    { name = "RAID_N",        label = "normal",        type = "raid_grid",  difficulty = 14 },
}

local CATEGORIES = {}

local function ReleaseDynamicCategories()
    for i = #CATEGORIES, 1, -1 do
        local cat = table.remove(CATEGORIES, i)
        if cat.isDynamic then
            ReleaseTableRecursive(cat)
        end
    end
end

local categoriesBuilt = false
local function RefreshDynamicCategories(force)
    if categoriesBuilt and not force then
        -- Standard incremental update (professions only)
        for i = #CATEGORIES, 1, -1 do
            if CATEGORIES[i].type == "prof_slot" or CATEGORIES[i].name == "PROFESSION_HEADER" then
                local cat = table.remove(CATEGORIES, i)
                if cat.isDynamic then
                    ReleaseTable(cat)
                end
            end
        end

        local hasProf = false
        for _, data in pairs(SfuiDB.alts or {}) do
            if data.profKP and next(data.profKP) then
                hasProf = true
                break
            end
        end

        if hasProf then
            local h = AcquireTable()
            h.name, h.label, h.type = "PROFESSION_HEADER", "professions", "header"
            table.insert(CATEGORIES, h)

            local p1 = AcquireTable()
            p1.name, p1.label, p1.type, p1.slot = "PROFESSION_1", "", "prof_slot", 1
            table.insert(CATEGORIES, p1)

            local p2 = AcquireTable()
            p2.name, p2.label, p2.type, p2.slot = "PROFESSION_2", "", "prof_slot", 2
            table.insert(CATEGORIES, p2)
        end
        return
    end

    -- Full rebuild
    ReleaseDynamicCategories()
    wipe(CATEGORIES)
    for i, cat in ipairs(BASE_CATEGORIES) do
        CATEGORIES[i] = cat
    end

    if C_ChallengeMode and C_ChallengeMode.GetMapTable then
        local maps = C_ChallengeMode.GetMapTable()
        if maps and #maps > 0 then
            local dh = AcquireTable()
            dh.name, dh.label, dh.type = "DUNGEONS_HEADER", "dungeons", "header"
            table.insert(CATEGORIES, dh)

            if SfuiDB.showM0Dungeons ~= false then
                local m0 = AcquireTable()
                m0.name, m0.label, m0.type = "M0_GRID", "mythic 0", "m0_grid"
                table.insert(CATEGORIES, m0)
            end

            for _, mapID in ipairs(maps) do
                local name = C_ChallengeMode.GetMapUIInfo(mapID)
                if name then
                    local dc = AcquireTable()
                    dc.name, dc.label, dc.type, dc.mapID = "DUNGEON_" .. mapID, name, "dungeon", mapID
                    table.insert(CATEGORIES, dc)
                end
            end
        end
    end

    -- Add Currencies from hardcoded list
    local ch = AcquireTable()
    ch.name, ch.label, ch.type = "CURRENCY_HEADER", "currency", "header"
    table.insert(CATEGORIES, ch)

    for _, currencyDef in ipairs(CURRENCIES) do
        local cc = AcquireTable()
        if currencyDef.isGroup then
            cc.name = "CURRENCY_GROUP_" .. currencyDef.items[1].id
            cc.label = currencyDef.label
            cc.type = "currency_group"
            cc.items = AcquireTable()
            for _, itemDef in ipairs(currencyDef.items) do
                local itemConfig = AcquireTable()
                itemConfig.id = itemDef.id
                itemConfig.isItem = itemDef.isItem
                itemConfig.showSeasonEarned = itemDef.showSeasonEarned
                itemConfig.isSparkDust = itemDef.isSparkDust
                local icon = itemDef.icon
                if not icon or icon == 0 then
                    if itemConfig.isItem and C_Item and C_Item.GetItemIconByID then
                        icon = C_Item.GetItemIconByID(itemConfig.id) or 134400
                    elseif sfui.common and sfui.common.get_currency_icon then
                        icon = sfui.common.get_currency_icon(itemConfig.id) or 134400
                    else
                        icon = 134400
                    end
                end
                itemConfig.icon = icon
                table.insert(cc.items, itemConfig)
            end
        else
            cc.name, cc.label, cc.type = "CURRENCY_" .. currencyDef.id, currencyDef.label, "currency"
            cc.id = currencyDef.id
            cc.isItem = currencyDef.isItem

            local icon = currencyDef.icon
            if not icon or icon == 0 then
                if cc.isItem and C_Item and C_Item.GetItemIconByID then
                    icon = C_Item.GetItemIconByID(cc.id) or 134400
                elseif sfui.common and sfui.common.get_currency_icon then
                    icon = sfui.common.get_currency_icon(cc.id) or 134400
                else
                    icon = 134400
                end
            end
            cc.icon = icon
        end

        table.insert(CATEGORIES, cc)
    end

    local hasProf = false
    for _, data in pairs(SfuiDB.alts or {}) do
        if data.profKP and next(data.profKP) then
            hasProf = true
            break
        end
    end

    if hasProf then
        local h = AcquireTable()
        h.name, h.label, h.type = "PROFESSION_HEADER", "professions", "header"
        table.insert(CATEGORIES, h)

        local p1 = AcquireTable()
        p1.name, p1.label, p1.type, p1.slot = "PROFESSION_1", "", "prof_slot", 1
        table.insert(CATEGORIES, p1)

        local p2 = AcquireTable()
        p2.name, p2.label, p2.type, p2.slot = "PROFESSION_2", "", "prof_slot", 2
        table.insert(CATEGORIES, p2)
    end

    categoriesBuilt = true
end

local ejInstanceCache = nil
local function GetEJInstanceCache()
    if ejInstanceCache and next(ejInstanceCache) then return ejInstanceCache end
    ejInstanceCache = {}
    if not EJ_GetInstanceByIndex then return ejInstanceCache end

    local oldTier = EJ_GetCurrentTier and EJ_GetCurrentTier()
    local numTiers = EJ_GetNumTiers and EJ_GetNumTiers()
    if numTiers and EJ_SelectTier then
        if securecall then
            securecall(EJ_SelectTier, numTiers)
        else
            EJ_SelectTier(numTiers)
        end
    end

    local index = 1
    while true do
        local instanceID, name = EJ_GetInstanceByIndex(index, false)
        if not instanceID then break end
        ejInstanceCache[name] = instanceID
        index = index + 1
    end

    if oldTier and EJ_SelectTier then
        if securecall then
            securecall(EJ_SelectTier, oldTier)
        else
            EJ_SelectTier(oldTier)
        end
    end

    return ejInstanceCache
end

local function CheckWeeklyResets()
    local now = GetServerTime()
    local thirtyDaysSecs = 30 * 24 * 60 * 60
    local secondsToReset = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and
        C_DateAndTime.GetSecondsUntilWeeklyReset() or 0
    local currentNextReset = secondsToReset > 0 and (now + secondsToReset) or nil

    -- Repair any legacy corrupted World/Delve slot 2 that was overwritten by PvP activity 229
    for _, d in pairs(SfuiDB.alts or {}) do
        if d.vault and d.vault.world then
            local w = d.vault.world
            if w[2] and (w[2].id == 229 or w[2].threshold == 3) then
                w[2].id = 208
                w[2].threshold = 4
                if not w[2].level or w[2].level == 0 then
                    local s3 = w[3]
                    local s1 = w[1]
                    if s3 and s3.level and s3.level > 0 then
                        w[2].level = s3.level
                        w[2].itemLevel = w[2].itemLevel or s3.itemLevel
                    elseif s1 and s1.level and s1.level > 0 then
                        w[2].level = s1.level
                        w[2].itemLevel = w[2].itemLevel or s1.itemLevel
                    end
                end
            end
        end
    end

    -- Repair legacy swapped vault data (where Dungeons were saved as Raid, and Raid as World)
    for _, d in pairs(SfuiDB.alts or {}) do
        if d.vault then
            local r = d.vault.raid
            local w = d.vault.world
            -- If raid has slot 1 with threshold == 1, it was actually dungeon data!
            if r and r[1] and r[1].threshold == 1 then
                local realDungeon = r
                local realRaid = nil
                -- If world has slot 3 with threshold == 6 or difficulty level 14..17, it was actually raid data
                if w and ((w[3] and w[3].threshold == 6) or (w[1] and w[1].level and w[1].level >= 14 and w[1].level <= 17)) then
                    realRaid = w
                end
                d.vault.dungeon = realDungeon
                d.vault.raid = realRaid or {}
                d.vault.world = {}
            end
        end
    end

    -- Clean up retired currencies
    local retiredCurrencies = { 3405, 3373, 267051 }
    for _, retID in ipairs(retiredCurrencies) do
        if SfuiDB.currencyCaps and SfuiDB.currencyCaps[retID] then
            SfuiDB.currencyCaps[retID] = nil
        end
        if SfuiDB.altsHiddenSections and SfuiDB.altsHiddenSections["CURRENCY_" .. retID] ~= nil then
            SfuiDB.altsHiddenSections["CURRENCY_" .. retID] = nil
        end
    end
    for _, d in pairs(SfuiDB.alts or {}) do
        if d.currencies then
            for _, retID in ipairs(retiredCurrencies) do
                d.currencies[retID] = nil
            end
        end
    end

    for g, d in pairs(SfuiDB.alts or {}) do
        if d.lastUpdate and (now - d.lastUpdate > thirtyDaysSecs) then
            SfuiDB.alts[g] = nil
        elseif d.nextWeeklyReset and now > d.nextWeeklyReset then
            if d.quests then wipe(d.quests) end
            if d.profKP then
                for _, pData in pairs(d.profKP) do
                    if type(pData) == "table" then
                        pData.done = 0
                        if pData.details then
                            pData.details.treatise = false
                            pData.details.quest = false
                            pData.details.treasures = 0
                        end
                    end
                end
            end
            if d.vault then
                local groups = { "raid", "dungeon", "world" }
                for _, group in ipairs(groups) do
                    if d.vault[group] then
                        for _, slot in pairs(d.vault[group]) do
                            if slot.progress and slot.threshold and slot.threshold > 0 and slot.progress >= slot.threshold then
                                d.vault.hasReward = true
                                break
                            end
                        end
                    end
                    if d.vault.hasReward then break end
                end
                if d.vault.raid then wipe(d.vault.raid) end
                if d.vault.dungeon then wipe(d.vault.dungeon) end
                if d.vault.world then wipe(d.vault.world) end
                if d.vault.dungeonRuns then wipe(d.vault.dungeonRuns) end
            end
            if d.m0 then wipe(d.m0) end
            if d.raids then wipe(d.raids) end

            if currentNextReset then
                d.nextWeeklyReset = currentNextReset
            end
        end
    end

    return currentNextReset
end

local function GetVaultActivityGroup(activityType)
    if not activityType then return nil end
    local T = Enum and Enum.WeeklyRewardChestThresholdType
    if T then
        if activityType == T.Raid then
            return "raid"
        elseif activityType == T.Activities or (T.MythicPlus and activityType == T.MythicPlus) then
            return "dungeon"
        elseif T.World and activityType == T.World then
            return "world"
        end
    end
    -- Numeric fallback based on Retail Blizzard constants:
    -- 1 = Activities / MythicPlus (Dungeons)
    -- 3 = Raid
    -- 4 = World (Delves / World events)
    if activityType == 3 then
        return "raid"
    elseif activityType == 1 then
        return "dungeon"
    elseif activityType == 4 then
        return "world"
    end
    return nil
end

local function recordVaultActivity(d, activity, defaultGroup)
    if not activity or not activity.threshold or activity.threshold <= 0 then return end
    d.vault = d.vault or {}

    local group = GetVaultActivityGroup(activity.type) or defaultGroup
    if not group then return end

    d.vault[group] = d.vault[group] or {}
    local slotIndex = activity.index
    if not slotIndex or slotIndex < 1 or slotIndex > 3 then
        slotIndex = #d.vault[group] + 1
    end

    if slotIndex >= 1 and slotIndex <= 3 then
        local targetSlot = d.vault[group][slotIndex] or {}
        targetSlot.threshold = activity.threshold
        targetSlot.progress = activity.progress or 0
        targetSlot.id = activity.id
        targetSlot.level = activity.level or 0

        if activity.progress and activity.progress >= activity.threshold then
            local ilvl = activity.itemLevel
            if (not ilvl or ilvl == 0) and activity.id and C_WeeklyRewards and C_WeeklyRewards.GetExampleRewardItemHyperlinks then
                local link = C_WeeklyRewards.GetExampleRewardItemHyperlinks(activity.id)
                if link and sfui.common and sfui.common.get_item_level then
                    ilvl = sfui.common.get_item_level(link)
                elseif link and C_Item and C_Item.GetDetailedItemLevelInfo then
                    ilvl = C_Item.GetDetailedItemLevelInfo(link)
                end
            end
            if (not ilvl or ilvl == 0) and activity.exampleItemHyperlink and sfui.common and sfui.common.get_item_level then
                ilvl = sfui.common.get_item_level(activity.exampleItemHyperlink)
            end
            targetSlot.itemLevel = ilvl or 0
        else
            targetSlot.itemLevel = 0
        end

        d.vault[group][slotIndex] = targetSlot
    end
end

local function SyncCurrency(d, cDef)
    d.currencies = d.currencies or {}
    if cDef.isItem then
        local count = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(cDef.id, true)) or 0
        d.currencies[cDef.id] = count
    elseif C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local info = C_CurrencyInfo.GetCurrencyInfo(cDef.id)
        if info then
            local curr = d.currencies[cDef.id] or {}
            curr.val = info.quantity or 0
            curr.earned = info.totalEarned or 0
            curr.max = info.maxWeeklyQuantity or 0
            curr.maxQuantity = info.maxQuantity or 0
            curr.useTotalEarned = info.useTotalEarnedForMaxQty or false

            if info.maxQuantity and info.maxQuantity > 0 then
                SfuiDB.currencyCaps = SfuiDB.currencyCaps or {}
                if not SfuiDB.currencyCaps[cDef.id] or info.maxQuantity > SfuiDB.currencyCaps[cDef.id] then
                    SfuiDB.currencyCaps[cDef.id] = info.maxQuantity
                end
            end

            d.currencies[cDef.id] = curr
        end
    end
end

local function GetCurrentCharacterGUID()
    local guid = UnitGUID and UnitGUID("player")
    if guid then return guid end
    local name, realm = UnitName("player")
    realm = (realm and realm ~= "") and realm or (GetRealmName and GetRealmName())
    if name and realm then
        return string.format("Player-%s-%s", realm, name)
    end
    return nil
end

local function GetQuestStatus(def)
    local isComplete = false
    local inProgress = false
    local progressText = nil
    local pNum = nil
    local doneCount = 0
    local targetCap = def.targetTotal or def.maxCompletion or 1

    -- 1. UI Widget Tracker (e.g. Delve Gilded Stash)
    if def.widgetID and C_UIWidgetManager then
        local wID = def.widgetID
        local itInfo = C_UIWidgetManager.GetIconAndTextWidgetVisualizationInfo and C_UIWidgetManager.GetIconAndTextWidgetVisualizationInfo(wID)
        local sbInfo = C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo and C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo(wID)
        local twInfo = C_UIWidgetManager.GetTextWithStateWidgetVisualizationInfo and C_UIWidgetManager.GetTextWithStateWidgetVisualizationInfo(wID)

        local text = (itInfo and itInfo.text) or (twInfo and twInfo.text)
        if text then
            local curStr, totStr = string.match(text, "(%d+)%s*/%s*(%d+)")
            if curStr then
                doneCount = tonumber(curStr) or 0
                targetCap = tonumber(totStr) or targetCap
            end
        elseif sbInfo and sbInfo.barValue then
            doneCount = sbInfo.barValue or 0
            targetCap = sbInfo.barMax or targetCap
        end

        if doneCount >= targetCap and targetCap > 0 then
            isComplete = true
        elseif doneCount > 0 then
            inProgress = true
        end
        return isComplete, inProgress, progressText, pNum, doneCount, targetCap
    end

    -- 2. Wrapper Quest Check
    if def.wrapperID then
        if not def.skipFlagCheck and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(def.wrapperID) then
            isComplete = true
            doneCount = targetCap
            return isComplete, inProgress, progressText, pNum, doneCount, targetCap
        elseif C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(def.wrapperID) then
            inProgress = true
            if C_QuestLog.GetQuestObjectives then
                local objs = C_QuestLog.GetQuestObjectives(def.wrapperID)
                if objs and objs[1] and objs[1].text then
                    local text = objs[1].text
                    local pVal = string.match(text, "(%d+)%%")
                    if pVal then
                        pNum = tonumber(pVal)
                        progressText = pVal .. "%"
                    else
                        local cur, req = string.match(text, "(%d+)/(%d+)")
                        if cur and req then
                            progressText = cur .. "/" .. req
                        else
                            progressText = text
                        end
                    end
                end
            end
        end
    end

    -- 3. Rotating Pool / Single Quest
    if def.pool then
        for _, pID in ipairs(def.pool) do
            if not def.skipFlagCheck and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(pID) then
                doneCount = doneCount + 1
            elseif C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(pID) then
                inProgress = true
                if not progressText and C_QuestLog.GetQuestObjectives then
                    local objs = C_QuestLog.GetQuestObjectives(pID)
                    if objs and objs[1] and objs[1].text then
                        local text = objs[1].text
                        local pVal = string.match(text, "(%d+)%%")
                        if pVal then
                            pNum = tonumber(pVal)
                            progressText = pVal .. "%"
                        else
                            local cur, req = string.match(text, "(%d+)/(%d+)")
                            if cur and req then
                                progressText = cur .. "/" .. req
                            else
                                progressText = text
                            end
                        end
                    end
                end
            end
        end

        if doneCount >= targetCap then
            isComplete = true
        elseif doneCount > 0 then
            inProgress = true
        end
    elseif def.questID then
        local qID = def.questID
        if not def.skipFlagCheck and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(qID) then
            isComplete = true
            doneCount = targetCap
        elseif C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(qID) then
            inProgress = true
            if C_QuestLog.GetQuestObjectives then
                local objs = C_QuestLog.GetQuestObjectives(qID)
                if objs and objs[1] and objs[1].text then
                    local text = objs[1].text
                    local pVal = string.match(text, "(%d+)%%")
                    if pVal then
                        pNum = tonumber(pVal)
                        progressText = pVal .. "%"
                    else
                        local cur, req = string.match(text, "(%d+)/(%d+)")
                        if cur and req then
                            progressText = cur .. "/" .. req
                        else
                            progressText = text
                        end
                    end
                end
            end
        end
    end

    return isComplete, inProgress, progressText, pNum, doneCount, targetCap
end

local function OnQuestTurnedIn(questID)
    if not questID or not sfui.season or not sfui.season.WEEKLY_QUESTS then return end

    local guid = GetCurrentCharacterGUID()
    if not guid or not SfuiDB or not SfuiDB.alts then return end
    local data = SfuiDB.alts[guid]
    if not data then return end
    data.quests = data.quests or {}

    for _, def in ipairs(sfui.season.WEEKLY_QUESTS) do
        local matched = false
        if def.questID and def.questID == questID then
            matched = true
        elseif def.wrapperID and def.wrapperID == questID then
            matched = true
        elseif def.pool then
            for _, pID in ipairs(def.pool) do
                if pID == questID then
                    matched = true
                    break
                end
            end
        end

        if matched then
            local qData = data.quests[def.key] or {}
            local targetCap = def.targetTotal or def.maxCompletion or 1

            if def.isCount then
                local currentDone = (qData.done or 0) + 1
                qData.done = currentDone
                qData.total = targetCap
                if currentDone >= targetCap then
                    qData.completed = true
                    qData.active = false
                    qData.progressText = nil
                    qData.progress = 100
                else
                    qData.active = true
                    qData.progressText = string.format("%d/%d", currentDone, targetCap)
                end
            else
                qData.completed = true
                qData.active = false
                qData.done = targetCap
                qData.total = targetCap
                qData.progressText = nil
                qData.progress = 100
            end
            data.quests[def.key] = qData
        end
    end
end

local function PerformSync(data, isLogout)
    local currentNextReset = CheckWeeklyResets()
    if currentNextReset then
        data.nextWeeklyReset = currentNextReset
    end

    -- 1. Mythic+ Rating
    if C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore then
        data.rating = C_ChallengeMode.GetOverallDungeonScore() or 0
    end

    -- 2. Keystone
    if C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID then
        local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
        local level = C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()
        if mapID and level and level > 0 then
            local link = C_MythicPlus.GetOwnedKeystoneLink and C_MythicPlus.GetOwnedKeystoneLink()
            if not link and sfui.common and sfui.common.for_each_bag_item then
                sfui.common.for_each_bag_item(function(bag, slot, itemID, itemLink)
                    if itemLink and string.find(itemLink, "keystone") then
                        link = itemLink
                        return true
                    end
                end, true, true, false)
            end
            data.keystone = { mapID = mapID, level = level, link = link }
        else
            data.keystone = nil
        end
    end

    -- 3. Great Vault
    if C_WeeklyRewards and C_WeeklyRewards.GetActivities then
        data.vault = data.vault or {}
        local activities = C_WeeklyRewards.GetActivities()
        if (not activities or #activities == 0) and Enum and Enum.WeeklyRewardChestThresholdType then
            activities = {}
            local types = {
                Enum.WeeklyRewardChestThresholdType.Raid,
                Enum.WeeklyRewardChestThresholdType.Activities,
                Enum.WeeklyRewardChestThresholdType.World,
            }
            for _, t in ipairs(types) do
                local subActs = C_WeeklyRewards.GetActivities(t)
                if subActs then
                    for _, act in ipairs(subActs) do
                        table.insert(activities, act)
                    end
                end
            end
        end

        if activities and #activities > 0 then
            data.vault.raid = data.vault.raid or {}
            data.vault.dungeon = data.vault.dungeon or {}
            data.vault.world = data.vault.world or {}
            for _, act in ipairs(activities) do
                local group = GetVaultActivityGroup(act.type)
                if group then
                    recordVaultActivity(data, act, group)
                end
            end
        end

        if C_WeeklyRewards.HasAvailableRewards then
            data.vault.hasReward = C_WeeklyRewards.HasAvailableRewards()
        end
    end

    -- 3b. Dungeon History for Vault
    if C_MythicPlus and C_MythicPlus.GetRunHistory then
        local weeklyRuns = C_MythicPlus.GetRunHistory(false, true)
        if weeklyRuns and #weeklyRuns > 0 then
            data.vault = data.vault or {}
            data.vault.dungeonRuns = {}
            for _, r in ipairs(weeklyRuns) do
                local dName = (C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(r.mapChallengeModeID)) or ("Map " .. tostring(r.mapChallengeModeID))
                table.insert(data.vault.dungeonRuns, {
                    mapID = r.mapChallengeModeID,
                    level = r.level,
                    name = dName,
                    completed = r.completed,
                    durationSec = r.durationSec or 0,
                })
            end
            table.sort(data.vault.dungeonRuns, function(a, b)
                if a.level ~= b.level then return a.level > b.level end
                return (a.durationSec or 0) < (b.durationSec or 0)
            end)
        end
    end

    -- 4. Mythic+ Season Dungeons
    if C_ChallengeMode and C_ChallengeMode.GetMapTable then
        local maps = C_ChallengeMode.GetMapTable()
        if maps and #maps > 0 then
            data.dungeons = data.dungeons or {}
            local currentRuns = (C_MythicPlus and C_MythicPlus.GetRunHistory and C_MythicPlus.GetRunHistory(true, true)) or {}
            for _, mapID in ipairs(maps) do
                local bestLevel = 0
                local bestTimed = 0
                if C_MythicPlus and C_MythicPlus.GetSeasonBestForMap then
                    local intimeInfo, overtimeInfo = C_MythicPlus.GetSeasonBestForMap(mapID)
                    if intimeInfo and intimeInfo.level then
                        bestLevel = intimeInfo.level
                        bestTimed = intimeInfo.level
                    end
                    if overtimeInfo and overtimeInfo.level and overtimeInfo.level > bestLevel then
                        bestLevel = overtimeInfo.level
                    end
                end

                for _, run in ipairs(currentRuns) do
                    if run.mapChallengeModeID == mapID then
                        if run.level and run.level > bestLevel then
                            bestLevel = run.level
                        end
                        if run.completed and run.level and run.level > bestTimed then
                            bestTimed = run.level
                        end
                    end
                end

                local cur = data.dungeons[mapID] or {}
                cur.level = bestLevel
                cur.timed = bestTimed
                data.dungeons[mapID] = cur
            end
        end
    end

    -- 5. Mythic 0 Lockouts
    data.m0 = data.m0 or {}
    local numSaved = GetNumSavedInstances and GetNumSavedInstances() or 0
    for i = 1, numSaved do
        local name, _, reset, difficulty, locked, _, _, isRaid = GetSavedInstanceInfo(i)
        if not isRaid and locked and reset and reset > 0 and (difficulty == 23 or difficulty == 174) then
            local instanceCache = GetEJInstanceCache()
            local id = instanceCache[name]
            if id then
                data.m0[id] = true
            end
        end
    end

    -- 5b. Raid Boss Lockouts
    data.raids = data.raids or {}
    for diff = 14, 16 do
        data.raids[diff] = {}
    end
    for i = 1, numSaved do
        local _, _, reset, difficulty, locked, _, _, isRaid, _, _, numEncounters = GetSavedInstanceInfo(i)
        if isRaid and locked and reset and reset > 0 and (difficulty == 14 or difficulty == 15 or difficulty == 16) then
            data.raids[difficulty] = data.raids[difficulty] or {}
            local encounters = numEncounters or 8
            for enc = 1, encounters do
                if GetSavedInstanceEncounterInfo then
                    local _, _, isKilled = GetSavedInstanceEncounterInfo(i, enc)
                    if isKilled then
                        data.raids[difficulty][enc] = true
                    end
                end
            end
        end
    end

    -- 6. Currencies
    for _, cDef in ipairs(CURRENCIES) do
        if cDef.isGroup then
            for _, itemDef in ipairs(cDef.items) do
                SyncCurrency(data, itemDef)
            end
        else
            SyncCurrency(data, cDef)
        end
    end

    -- 7. Weekly Quests
    data.quests = data.quests or {}
    if sfui.season and sfui.season.WEEKLY_QUESTS then
        for _, def in ipairs(sfui.season.WEEKLY_QUESTS) do
            local existing = data.quests[def.key]
            local completed, active, progressText, progressNum, doneCount, targetTotal = GetQuestStatus(def)

            -- 1. Weekly completion is irrevocable within the current reset cycle:
            -- Once marked completed on this character, it NEVER reverts to false.
            if existing and existing.completed then
                completed = true
                active = false
                doneCount = targetTotal or (existing.total or (def.targetTotal or 1))
                progressText = nil
                progressNum = 100
            end

            -- 2. Preserve higher count/progress:
            -- Quests with counters (e.g. Special Assignments 1/2, Delve Stash 3/4) must never decrease.
            if existing and existing.done and existing.done > doneCount then
                doneCount = existing.done
                if targetTotal and doneCount >= targetTotal and targetTotal > 0 then
                    completed = true
                    active = false
                end
            end

            -- 3. Preserve existing progress if current query returned nothing
            -- (e.g. away from widget hub, objective API temporarily unavailable, or during logout)
            if not completed and not active and doneCount == 0 and existing then
                if existing.completed then
                    completed = true
                    doneCount = existing.done or targetTotal
                elseif existing.done and existing.done > 0 then
                    doneCount = existing.done
                    active = existing.active
                    progressText = existing.progressText
                    progressNum = existing.progress
                elseif existing.active and isLogout then
                    active = existing.active
                    progressText = existing.progressText
                    progressNum = existing.progress
                end
            end

            targetTotal = targetTotal or (existing and existing.total) or def.targetTotal or 1

            data.quests[def.key] = {
                completed = completed,
                active = active,
                progressText = progressText,
                progress = progressNum,
                done = doneCount,
                total = targetTotal,
            }
        end
    end

    -- 8. Professions
    data.profKP = data.profKP or {}
    local prof1, prof2 = GetProfessions and GetProfessions()
    local profsToCheck = {}
    if prof1 then table.insert(profsToCheck, prof1) end
    if prof2 then table.insert(profsToCheck, prof2) end

    if #profsToCheck > 0 then
        for _, pIndex in ipairs(profsToCheck) do
            local name, icon, skillLevel, _, _, _, skillLine = GetProfessionInfo(pIndex)
            if skillLine then
                local tracking = PROF_KP_SOURCES[skillLine]
                local pData = data.profKP[skillLine] or {}
                pData.name = name
                pData.icon = icon
                pData.skill = skillLevel
                pData.done = 0
                pData.total = 0
                pData.catchUp = 0
                pData.details = pData.details or {}
                local d = pData.details
                d.treatise = false
                d.quest = false
                d.treasures = 0
                d.treasuresMax = 0

                local charLevel = data.level or 90
                local minLevel = (_G.GetMaxPlayerLevel and _G.GetMaxPlayerLevel() - 10) or 70
                if tracking and charLevel >= minLevel then
                    d.treasuresMax = tracking.treasures and #tracking.treasures or 0

                    if tracking.treatise then
                        pData.total = pData.total + 1
                        for _, qid in ipairs(tracking.treatise) do
                            if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(qid) then
                                pData.done = pData.done + 1
                                d.treatise = true
                                break
                            end
                        end
                    end

                    if tracking.quest then
                        pData.total = pData.total + 1
                        for _, qid in ipairs(tracking.quest) do
                            if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(qid) then
                                pData.done = pData.done + 1
                                d.quest = true
                                break
                            end
                        end
                    end

                    if tracking.treasures then
                        pData.total = pData.total + #tracking.treasures
                        for _, tList in ipairs(tracking.treasures) do
                            for _, qid in ipairs(tList) do
                                if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(qid) then
                                    pData.done = pData.done + 1
                                    d.treasures = d.treasures + 1
                                    break
                                end
                            end
                        end
                    end

                    if tracking.catchup and sfui.common and sfui.common.get_currency_info then
                        local currencyInfo = sfui.common.get_currency_info(tracking.catchup)
                        if currencyInfo and currencyInfo.maxQuantity and currencyInfo.quantity then
                            local remaining = currencyInfo.maxQuantity - currencyInfo.quantity
                            if remaining > 0 then
                                pData.catchUp = pData.catchUp + remaining
                            end
                        end
                    end
                end
                data.profKP[skillLine] = pData
            end
        end
    elseif C_TradeSkillUI and C_TradeSkillUI.GetChildProfessionInfos then
        local profInfos = C_TradeSkillUI.GetChildProfessionInfos()
        if profInfos and #profInfos > 0 then
            for _, prof in ipairs(profInfos) do
                if prof.profession and prof.professionID then
                    local pData = data.profKP[prof.professionID] or {}
                    pData.name = prof.professionName or prof.name
                    pData.skill = prof.skillLevel
                    pData.details = pData.details or {}
                    data.profKP[prof.professionID] = pData
                end
            end
        end
    end
end

local function GetVaultColor(g, l, ilvl)
    if g == "raid" then
        if l == 16 or (ilvl and ilvl >= 318) then return { 1.0, 0.5, 0.0, 0.8 } end     -- Mythic (Orange)
        if l == 15 or (ilvl and ilvl >= 305) then return { 0.64, 0.21, 0.93, 0.8 } end  -- Heroic (Purple)
        if l == 14 or (ilvl and ilvl >= 292) then return { 0.0, 0.44, 0.87, 0.8 } end   -- Normal (Blue)
        return { 0.12, 1.0, 0.0, 0.8 }                                                  -- LFR (Green)
    elseif g == "world" then
        if (l and l >= 7) or (ilvl and ilvl >= 305) then return { 0.64, 0.21, 0.93, 0.8 } end   -- Hero (Tier 7-8+ Delves, Purple)
        if (l and l >= 4) or (ilvl and ilvl >= 292) then return { 0.0, 0.44, 0.87, 0.8 } end    -- Champion (Tier 4-6 Delves, Blue)
        return { 0.12, 1.0, 0.0, 0.8 }                                                           -- Veteran (Tier 1-3 Delves, Green)
    else -- dungeon
        if (l and l >= 10) or (ilvl and ilvl >= 318) then return { 1.0, 0.5, 0.0, 0.8 } end     -- Myth (+10+, Orange)
        if (l and l >= 2)  or (ilvl and ilvl >= 305) then return { 0.64, 0.21, 0.93, 0.8 } end  -- Hero (+2 to +9, Purple)
        if (l and l >= 0)  or (ilvl and ilvl >= 292) then return { 0.0, 0.44, 0.87, 0.8 } end   -- Champion (M0, Blue)
        return { 0.12, 1.0, 0.0, 0.8 }                                                           -- Veteran (Heroic Dungeon, Green)
    end
end

local function GetDifficultyName(l)
    if l == 17 then return "LFR" end
    if l == 14 then return "Normal" end
    if l == 15 then return "Heroic" end
    if l == 16 then return "Mythic" end
    return tostring(l)
end

local function GetVaultItemLevel(g, l, vData)
    if vData and vData.itemLevel and vData.itemLevel > 0 then
        return vData.itemLevel
    end
    if vData and vData.id and C_WeeklyRewards and C_WeeklyRewards.GetExampleRewardItemHyperlinks then
        local link = C_WeeklyRewards.GetExampleRewardItemHyperlinks(vData.id)
        if link and sfui.common and sfui.common.get_item_level then
            local ilvl = sfui.common.get_item_level(link)
            if ilvl and ilvl > 0 then return ilvl end
        elseif link and C_Item and C_Item.GetDetailedItemLevelInfo then
            local ilvl = C_Item.GetDetailedItemLevelInfo(link)
            if ilvl and ilvl > 0 then return ilvl end
        end
    end
    if sfui.season and sfui.season.GetVaultBaseline then
        local bIlvl = sfui.season.GetVaultBaseline(g, l)
        if bIlvl then return bIlvl end
    end
    return nil
end

local function GetVaultTrack(g, l, ilvl)
    if sfui.season and sfui.season.GetVaultBaseline then
        local _, track = sfui.season.GetVaultBaseline(g, l)
        if track then return track end
    end
    if ilvl then
        if ilvl >= 318 then return "|cffff8000Myth|r" end
        if ilvl >= 305 then return "|cffa335eeHero|r" end
        if ilvl >= 292 then return "|cff0070ddChampion|r" end
        if ilvl >= 279 then return "|cff1eff00Veteran|r" end
    end
    return nil
end

local function RenderCell(cell, cat, altData, classColor, col, altGuid)
    local text = cell.text
    if not text then return false end

    if cat.type == "stat" then
        local val = altData[cat.key] or 0
        local maxLevel = (_G.GetMaxPlayerLevel and _G.GetMaxPlayerLevel()) or 80
        if cat.key == "iLvl" and (altData.level or 0) < maxLevel then
            text:SetText(altData.level or "-")
            text:SetTextColor(unpack(sfui.config.colors.white))
            if val and val > 0 then
                cell:EnableMouse(true)
                cell:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(string.format("Level %d", altData.level or 0), 1, 1, 1)
                    GameTooltip:AddDoubleLine("item level:", string.format("%.1f", val), NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1, 1, 1)
                    GameTooltip:Show()
                end)
                cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
            else
                cell:SetScript("OnEnter", nil)
                cell:SetScript("OnLeave", nil)
            end
        else
            if cat.key == "iLvl" and (val == 0 or not val) then
                text:SetText("-")
                text:SetTextColor(0.5, 0.5, 0.5)
            else
                text:SetText(cat.format and string.format(cat.format, val) or val)
            end
            if cat.key == "rating" and val > 0 then
                local color = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor and C_ChallengeMode.GetDungeonScoreRarityColor(val)
                if color then
                    text:SetTextColor(color.r, color.g, color.b)
                end
                cell:EnableMouse(true)
                cell:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine("mythic+ rating", 1, 1, 1)
                    local rColor = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor and C_ChallengeMode.GetDungeonScoreRarityColor(val)
                    local rr, rg, rb = 1, 1, 1
                    if rColor then rr, rg, rb = rColor.r, rColor.g, rColor.b end
                    GameTooltip:AddDoubleLine("overall:", tostring(val), 1, 1, 1, rr, rg, rb)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("best keys this season:", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
                    local maps = (C_ChallengeMode and C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapTable()) or {}
                    for _, mID in ipairs(maps) do
                        local mName = C_ChallengeMode.GetMapUIInfo(mID)
                        local dData = altData.dungeons and altData.dungeons[mID]
                        local lvl   = dData and dData.level or 0
                        local timed = dData and dData.timed or 0
                        local lvlStr, lr, lg, lb
                        if lvl > 0 then
                            if lvl > timed then
                                lvlStr = "+" .. lvl .. "†"
                                lr, lg, lb = 0.5, 0.5, 0.5
                            else
                                lvlStr = "+" .. timed
                                local kc = C_ChallengeMode.GetKeystoneLevelRarityColor(timed)
                                if timed >= 12 then
                                    lr, lg, lb = 1, 0.5, 0
                                elseif kc then
                                    lr, lg, lb = kc.r, kc.g, kc.b
                                else
                                    lr, lg, lb = 1, 1, 1
                                end
                            end
                        else
                            lvlStr = "-"
                            lr, lg, lb = 0.4, 0.4, 0.4
                        end
                        GameTooltip:AddDoubleLine(mName or "?", lvlStr, 1, 1, 1, lr, lg, lb)
                    end
                    GameTooltip:Show()
                end)
                cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
            else
                cell:SetScript("OnEnter", nil)
                cell:SetScript("OnLeave", nil)
            end
        end
        return true

    elseif cat.type == "keystone" then
        if altData.keystone then
            local ks   = altData.keystone
            local name = sfui.common and sfui.common.get_short_map_name and sfui.common.get_short_map_name(ks.mapID)
            if name then
                text:SetText(string.format("%s +%d", name, ks.level))
            else
                text:SetText(string.format("+%d", ks.level))
            end

            local color = C_ChallengeMode and C_ChallengeMode.GetKeystoneLevelRarityColor and C_ChallengeMode.GetKeystoneLevelRarityColor(ks.level)
            if ks.level >= 12 then
                text:SetTextColor(1, 0.5, 0)
            elseif color then
                text:SetTextColor(color.r, color.g, color.b)
            else
                text:SetTextColor(unpack(sfui.config.colors.white))
            end

            local ksSnap = ks
            cell:EnableMouse(true)
            cell:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if ksSnap.link then
                    GameTooltip:SetHyperlink(ksSnap.link)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("<shift-click to link>", GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
                else
                    local fullName = C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(ksSnap.mapID)
                    GameTooltip:SetText(fullName or "Keystone")
                    GameTooltip:AddLine("+" .. ksSnap.level, 1, 1, 1)
                end
                GameTooltip:Show()
            end)
            cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
            cell:SetScript("OnMouseUp", function()
                if IsModifiedClick("CHATLINK") and ksSnap.link then
                    if not ChatEdit_InsertLink(ksSnap.link) then
                        ChatFrame_OpenChat(ksSnap.link)
                    end
                end
            end)
        else
            text:SetText("-")
            text:SetTextColor(0.5, 0.5, 0.5)
            cell:SetScript("OnEnter", nil)
            cell:SetScript("OnLeave", nil)
            cell:SetScript("OnMouseUp", nil)
        end
        return true

    elseif cat.type == "dungeon" then
        local best = altData.dungeons and altData.dungeons[cat.mapID]
        local isTargeted = altData.voidcoreTargets and altData.voidcoreTargets[cat.mapID]

        if isTargeted then
            if not cell.diamondIcon then
                cell.diamondIcon = cell:CreateTexture(nil, "OVERLAY")
                cell.diamondIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_3")
                cell.diamondIcon:SetSize(12, 12)
                cell.diamondIcon:SetPoint("RIGHT", cell, "RIGHT", -4, 0)
            end
            cell.diamondIcon:Show()
        end

        local mapID = cat.mapID
        local portalSpell, portalName, isKnown = nil, nil, false
        if sfui.portals and sfui.portals.GetDungeonPortal then
            portalSpell, portalName, isKnown = sfui.portals.GetDungeonPortal(mapID)
        end

        if best and best.level > 0 then
            local timed = best.timed or 0
            local overall = best.level
            local isDepleted = overall > timed

            if isDepleted then
                text:SetText(overall .. "†")
                text:SetTextColor(0.5, 0.5, 0.5)
            else
                text:SetText(tostring(timed))
                local color = C_ChallengeMode and C_ChallengeMode.GetKeystoneLevelRarityColor and C_ChallengeMode.GetKeystoneLevelRarityColor(timed)
                if timed >= 12 then
                    text:SetTextColor(1, 0.5, 0)
                elseif color then
                    text:SetTextColor(color.r, color.g, color.b)
                else
                    text:SetTextColor(unpack(sfui.config.colors.white))
                end
            end
        else
            text:SetText("-")
            text:SetTextColor(0.5, 0.5, 0.5)
        end

        cell:EnableMouse(true)
        cell:SetScript("OnEnter", function(self)
            local fullName = C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(mapID)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(fullName or "Dungeon")
            if best and best.level > 0 then
                local timed = best.timed or 0
                if timed > 0 then
                    local timedColor = C_ChallengeMode and C_ChallengeMode.GetKeystoneLevelRarityColor and C_ChallengeMode.GetKeystoneLevelRarityColor(timed)
                    local tr, tg, tb = 1, 1, 1
                    if timed >= 12 then tr, tg, tb = 1, 0.5, 0
                    elseif timedColor then tr, tg, tb = timedColor.r, timedColor.g, timedColor.b end
                    GameTooltip:AddDoubleLine("timed:", "+" .. timed, 1, 1, 1, tr, tg, tb)
                end
                if best.level > timed then
                    GameTooltip:AddDoubleLine("best (depleted):", "+" .. best.level, 1, 1, 1, 0.5, 0.5, 0.5)
                end
            else
                GameTooltip:AddLine("not yet completed.", 0.5, 0.5, 0.5)
            end
            if isKnown and not InCombatLockdown() then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("<left-click to cast dungeon teleport>", 0.2, 1.0, 0.4)
                if sfui.portals and sfui.portals.ArmDungeon then
                    sfui.portals.ArmDungeon(mapID, self)
                end
            end
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function()
            if sfui.portals and sfui.portals.Disarm then
                sfui.portals.Disarm()
            end
            GameTooltip:Hide()
        end)
        return true

    elseif cat.type == "currency" or cat.type == "currency_group" then
        local isGroup = (cat.type == "currency_group")
        local items = isGroup and cat.items or { cat }

        local displayText = ""
        local tooltipLines = {}

        for _, itemConfig in ipairs(items) do
            local cData = altData.currencies and altData.currencies[itemConfig.id]
            -- Check weekly cap
            local isCapped = false
            local displayMaxQuantity = cData and type(cData) == "table" and cData.maxQuantity or 0
            if SfuiDB and SfuiDB.currencyCaps and SfuiDB.currencyCaps[itemConfig.id] and SfuiDB.currencyCaps[itemConfig.id] > displayMaxQuantity then
                displayMaxQuantity = SfuiDB.currencyCaps[itemConfig.id]
            end

            if cData and type(cData) == "table" then
                if cData.max and cData.max > 0 and cData.earned and cData.earned >= cData.max then
                    isCapped = true
                elseif displayMaxQuantity > 0 then
                    if cData.useTotalEarned and cData.totalEarned and cData.totalEarned >= displayMaxQuantity then
                        isCapped = true
                    elseif not cData.useTotalEarned and cData.val and cData.val >= displayMaxQuantity then
                        isCapped = true
                    end
                end
            end

            local val = cData and (type(cData) == "table" and cData.val or cData) or 0
            local currentEarned = cData and type(cData) == "table" and (cData.useTotalEarned and cData.totalEarned or cData.val) or val
            local displayVal
            if itemConfig.showSeasonEarned and displayMaxQuantity > 0 then
                displayVal = string.format("%d/%d", currentEarned, displayMaxQuantity)
            elseif val >= 1000 then
                displayVal = string.format("%.1fk", val / 1000)
            else
                displayVal = tostring(val)
            end

            if displayText ~= "" then
                displayText = displayText .. "  "
            end

            if itemConfig.isSparkDust and displayMaxQuantity > 0 then
                local colorCode
                if currentEarned >= displayMaxQuantity then
                    colorCode = "|cff00ff88" -- Green: caught up / all dust earned
                elseif currentEarned > 0 then
                    colorCode = "|cffffaa00" -- Orange: partially earned
                else
                    colorCode = "|cffff4444" -- Red: no dust earned yet
                end
                displayText = displayText ..
                    string.format("|T%d:12:12:0:0|t %s%s|r", itemConfig.icon or 134400, colorCode, displayVal)
            elseif isCapped then
                local errCol = (sfui.config and sfui.config.appearance and sfui.config.appearance.errorColor) or { 1, 0.2, 0.2 }
                local r, g, b = unpack(errCol)
                local colorCode = string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
                displayText = displayText ..
                    string.format("|T%d:12:12:0:0|t %s%s|r", itemConfig.icon or 134400, colorCode, displayVal)
            else
                displayText = displayText .. string.format("|T%d:12:12:0:0|t %s", itemConfig.icon or 134400, displayVal)
            end

            table.insert(tooltipLines, {
                itemConfig = itemConfig,
                cData = cData,
                isCapped = isCapped,
                displayMaxQuantity = displayMaxQuantity,
                count = val,
                earned = currentEarned,
                max = displayMaxQuantity,
            })
        end

        text:SetText(displayText)
        text:SetTextColor(unpack(sfui.config.colors.white))

        cell:EnableMouse(true)
        cell:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if not isGroup then
                local tLine = tooltipLines[1]
                if tLine and tLine.itemConfig then
                    local name = tLine.name
                    if not name then
                        if tLine.itemConfig.isItem then
                            name = (C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(tLine.itemConfig.id)) or "Item"
                        else
                            name = (sfui.common and sfui.common.get_currency_name and sfui.common.get_currency_name(tLine.itemConfig.id)) or "Currency"
                        end
                    end

                    GameTooltip:AddLine(string.format("|T%d:16:16:0:0|t %s", tLine.itemConfig.icon or 134400, name))

                    if tLine.cData and type(tLine.cData) == "table" then
                        if tLine.cData.max and tLine.cData.max > 0 then
                            GameTooltip:AddDoubleLine("weekly earned:",
                                string.format("%d / %d", tLine.cData.earned or 0, tLine.cData.max), 1, 1, 1, 1, 1, 1)
                        elseif tLine.displayMaxQuantity > 0 then
                            local currentAmount = tLine.cData.useTotalEarned and tLine.cData.totalEarned or
                                tLine.cData.val
                            GameTooltip:AddDoubleLine("season earned:",
                                string.format("%d / %d", currentAmount or 0, tLine.displayMaxQuantity), 1, 1, 1, 1,
                                1, 1)
                        else
                            local val = tLine.cData.val or 0
                            GameTooltip:AddDoubleLine("total:", tostring(val), 1, 1, 1, 1, 1, 1)
                        end
                        if tLine.isCapped then
                            GameTooltip:AddLine("season/weekly cap reached!", 1, 0, 0)
                        end
                    else
                        local val = tLine.cData or 0
                        GameTooltip:AddDoubleLine("Total:", tostring(val), 1, 1, 1, 1, 1, 1)
                    end
                end
                GameTooltip:Show()
                return
            end

            GameTooltip:AddLine(cat.label or "currencies", 1, 1, 1)
            for _, tLine in ipairs(tooltipLines) do
                local name = tLine.name
                local icon = tLine.itemConfig and tLine.itemConfig.icon
                if not name then
                    if tLine.itemConfig and tLine.itemConfig.isItem then
                        name = (C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(tLine.itemConfig.id)) or (tLine.itemConfig.id == 274476 and "Spark of Tides" or "Item")
                    elseif tLine.itemConfig then
                        name = (sfui.common and sfui.common.get_currency_name and sfui.common.get_currency_name(tLine.itemConfig.id)) or (tLine.itemConfig.id == 3509 and "Tidal Spark Dust" or "Currency")
                    else
                        name = "Currency"
                    end
                end
                local iconPrefix = (icon and icon > 0) and string.format("|T%d:14:14:0:0|t ", icon) or ""
                local cData = tLine.cData
                local val = tLine.count or 0
                local maxQty = tLine.displayMaxQuantity or 0
                local earned = tLine.earned or val

                if tLine.itemConfig and tLine.itemConfig.isSparkDust then
                    GameTooltip:AddDoubleLine(iconPrefix .. name .. ":",
                        string.format("%d in bags", val), 1, 1, 1, 1, 1, 1)
                    if maxQty > 0 then
                        local statusColor = earned >= maxQty and "|cff00ff88" or (earned > 0 and "|cffffaa00" or "|cffff4444")
                        GameTooltip:AddDoubleLine("season earned / cap:",
                            string.format("%s%d / %d|r", statusColor, earned, maxQty), 1, 1, 1, 1, 1, 1)
                    end
                elseif cData and type(cData) == "table" then
                    if cData.max and cData.max > 0 then
                        GameTooltip:AddDoubleLine(iconPrefix .. name .. ":",
                            string.format("%d (weekly: %d / %d)", val, cData.earned or 0, cData.max), 1, 1, 1, 1, 1, 1)
                    elseif maxQty > 0 then
                        GameTooltip:AddDoubleLine(iconPrefix .. name .. ":",
                            string.format("%d (season: %d / %d)", val, earned, maxQty), 1, 1, 1, 1, 1, 1)
                    else
                        GameTooltip:AddDoubleLine(iconPrefix .. name .. ":", tostring(val), 1, 1, 1, 1, 1, 1)
                    end
                    if tLine.isCapped then
                        GameTooltip:AddLine("Season/Weekly cap reached!", 1, 0, 0)
                    end
                else
                    GameTooltip:AddDoubleLine(iconPrefix .. name .. ":", tostring(val), 1, 1, 1, 1, 1, 1)
                end
            end
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return true

    elseif cat.type == "quests_grid" then
        local minLevel = (_G.GetMaxPlayerLevel and _G.GetMaxPlayerLevel() - 10) or 70
        local hasQuestData = altData.quests and next(altData.quests)
        local isEligible = (altData.level and altData.level >= minLevel) or hasQuestData

        if not isEligible then
            text:Show()
            text:SetText("-")
            text:SetTextColor(0.4, 0.4, 0.4)
            for bIdx = 1, 20 do
                if cell["qRect" .. bIdx] then cell["qRect" .. bIdx]:Hide() end
                if cell["qCount" .. bIdx] then cell["qCount" .. bIdx]:Hide() end
            end
            cell:EnableMouse(false)
            cell:SetScript("OnEnter", nil)
            cell:SetScript("OnLeave", nil)
        else
            text:Hide()
            local q = altData.quests

            -- Block definitions sourced from sfui.season.WEEKLY_QUESTS
            local BLOCKS = sfui.season and sfui.season.WEEKLY_QUESTS or {}
            -- Colours: completed / inProgress / available — per group
            local CORE_DONE   = { 0.40, 0.00, 1.00, 0.85 } -- #6600ff vivid purple
            local CORE_PROG   = { 0.18, 0.00, 0.45, 0.85 } -- dark purple
            local BONUS_DONE  = { 0.90, 0.52, 0.00, 0.85 } -- #e68500 amber/gold
            local BONUS_PROG  = { 0.40, 0.22, 0.00, 0.85 } -- dark amber
            local AVAIL_COLOR = { 0.06, 0.06, 0.07, 0.60 } -- near-black

            local CORE_TEXT   = "|cffaa66ff"               -- light purple for tooltip
            local BONUS_TEXT  = "|cffffaa44"               -- light amber for tooltip

            local numBlocks   = #BLOCKS
            local GAP         = 6                          -- px gap between core and bonus group
            local totalW      = cfg.columnWidth - 10
            local blockW      = (totalW - GAP) / math_max(1, numBlocks)

            for bIdx, block in ipairs(BLOCKS) do
                local rect = cell["qRect" .. bIdx] or cell:CreateTexture(nil, "ARTWORK")
                cell["qRect" .. bIdx] = rect
                rect:Show()
                rect:SetSize(math_max(2, blockW - 2), cfg.rowHeight - 12)
                local xOff = (bIdx - 1) * blockW + 5 + (block.group == "bonus" and GAP or 0)
                rect:SetPoint("LEFT", xOff, 0)

                local status   = q and q[block.key]
                local isDone   = status and status.completed
                local isActive = status and (status.active or (status.progress and status.progress > 0) or (status.done and status.done > 0 and not isDone))

                if block.group == "core" then
                    if isDone then
                        rect:SetColorTexture(unpack(CORE_DONE))
                    elseif isActive then
                        rect:SetColorTexture(unpack(CORE_PROG))
                    else
                        rect:SetColorTexture(unpack(AVAIL_COLOR))
                    end
                else -- bonus
                    if isDone then
                        rect:SetColorTexture(unpack(BONUS_DONE))
                    elseif isActive then
                        rect:SetColorTexture(unpack(BONUS_PROG))
                    else
                        rect:SetColorTexture(unpack(AVAIL_COLOR))
                    end
                end

                -- Counter overlay (e.g. Stash 0/4, Special Assignments 0/2)
                if block.isCount then
                    local lbl = cell["qCount" .. bIdx]
                    if not lbl then
                        lbl = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                        cell["qCount" .. bIdx] = lbl
                    end
                    if isDone or not status or (status.done and status.done == 0) then
                        lbl:Hide()
                    else
                        lbl:ClearAllPoints()
                        lbl:SetPoint("CENTER", rect, "CENTER")
                        lbl:Show()
                        local done  = (status and status.done) or 0
                        local total = (status and status.total) or (block.key == "gildedStash" and 4 or 2)
                        lbl:SetText(done .. "/" .. total)
                        lbl:SetTextColor(unpack(sfui.config.colors.white))
                    end
                else
                    local lbl = cell["qCount" .. bIdx]
                    if lbl then lbl:Hide() end
                end
            end

            -- Hide any leftover rectangles from older sizes
            for bIdx = numBlocks + 1, 20 do
                if cell["qRect" .. bIdx] then cell["qRect" .. bIdx]:Hide() end
                if cell["qCount" .. bIdx] then cell["qCount" .. bIdx]:Hide() end
            end

            cell:EnableMouse(true)
            cell:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("weekly quests (champion+ gear)")

                -- Core group header
                GameTooltip:AddLine("|cffaa66ffpinnacle caches (champion track)|r", 1, 1, 1)
                for _, block in ipairs(BLOCKS) do
                    if block.group == "core" then
                        local status = q and q[block.key]
                        local color  = "|cff555555"
                        local valStr = "not started"
                        if status then
                            if status.completed then
                                color  = CORE_TEXT
                                valStr = "completed"
                            elseif status.progressText then
                                color  = "|cff886699"
                                valStr = status.progressText
                            elseif status.progress and status.progress > 0 then
                                color  = "|cff886699"
                                valStr = status.progress .. "%"
                            elseif status.active then
                                color  = "|cff886699"
                                valStr = "in progress"
                            end
                        end
                        GameTooltip:AddDoubleLine(block.label, color .. valStr .. "|r", 1, 1, 1, 1, 1, 1)
                    end
                end

                -- Bonus group header
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cffffaa44delves, prey & event caches (champion / hero)|r", 1, 1, 1)
                for _, block in ipairs(BLOCKS) do
                    if block.group == "bonus" then
                        local status = q and q[block.key]
                        local color  = "|cff555555"
                        local valStr = "not started"
                        if block.key == "twRaid" and not (status and (status.completed or status.active)) then
                            valStr = "no tw event active"
                        elseif block.key == "bonusEvent" and not (status and (status.completed or status.active)) then
                            valStr = "no event quest taken"
                        end
                        if status then
                            if status.completed then
                                color  = BONUS_TEXT
                                valStr = "completed"
                            elseif block.isCount and status.done and status.done > 0 then
                                color  = "|cffcc8833"
                                valStr = string.format("%d / %d", status.done, status.total or 4)
                            elseif status.progressText then
                                color  = "|cffcc8833"
                                valStr = status.progressText
                            elseif status.active or (status.progress and status.progress > 0) then
                                color  = "|cffcc8833"
                                valStr = "in progress"
                            end
                        end
                        GameTooltip:AddDoubleLine(block.label, color .. valStr .. "|r", 1, 1, 1, 1, 1, 1)
                    end
                end

                if q and q.gildedStash and not q.gildedStash.active and not q.gildedStash.completed then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cff888888stash updates near silvermoon delve hub|r")
                end
                GameTooltip:Show()
            end)
            cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        return true

    elseif cat.type == "prof_slot" then
        local pData
        local profs = {}
        if altData.profKP then
            for skillLine, data in pairs(altData.profKP) do
                if type(data) == "table" then
                    table.insert(profs, data)
                end
            end
        end
        table.sort(profs, function(a, b) return (a.name or "") < (b.name or "") end)
        pData = profs[cat.slot]

        if pData then
            local shortName = GetShortProfName(pData.name)

            text:ClearAllPoints()
            text:SetPoint("LEFT", cell, "LEFT", 6, 0)
            text:SetJustifyH("LEFT")
            text:SetWidth(0)
            text:SetText(string.format("%s - %d", shortName, pData.skill or 0))
            text:SetTextColor(unpack(sfui.config.colors.white))

            local rightText = cell.rightText
            if not rightText then
                rightText = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                cell.rightText = rightText
            end
            rightText:Show()
            rightText:ClearAllPoints()
            rightText:SetPoint("RIGHT", cell, "RIGHT", -6, 0)
            rightText:SetJustifyH("RIGHT")
            rightText:SetWidth(0)

            if pData.total and pData.total > 0 then
                rightText:SetText(string.format("%d/%d", pData.done or 0, pData.total))

                local sColors = cfg.statusColors
                if pData.done and pData.done >= pData.total then
                    local cyan = (sfui.config and sfui.config.colors and sfui.config.colors.cyan) or { 0, 1, 1 }
                    rightText:SetTextColor(unpack(cyan))
                elseif pData.done and pData.done > 0 then
                    local c = sColors and sColors.inProgress or { 0, 0.2, 0.2 }
                    rightText:SetTextColor(c[1], c[2], c[3])
                else
                    rightText:SetTextColor(unpack(sfui.config.colors.white))
                end
            else
                rightText:SetText("")
            end

            cell:EnableMouse(true)
            cell:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(((pData.name or "profession") .. " knowledge"):lower())
                GameTooltip:AddDoubleLine("skill level:", string.format("%d", pData.skill or 0), 1, 1, 1, 1, 1, 1)
                if pData.catchUp and pData.catchUp > 0 then
                    GameTooltip:AddDoubleLine("catch-up available:", pData.catchUp, 1, 0.82, 0, 1, 0.82, 0)
                end

                if pData.total and pData.total > 0 then
                    GameTooltip:AddLine("weekly progress", 1, 1, 1)
                    local tStr = (pData.details and pData.details.treatise) and "|cff00ff00Done|r" or "|cffff0000Missing|r"
                    GameTooltip:AddDoubleLine("treatise:", tStr, 1, 1, 1, 1, 1, 1)
                    local qStr = (pData.details and pData.details.quest) and "|cff00ff00Done|r" or "|cffff0000Missing|r"
                    GameTooltip:AddDoubleLine("weekly quest/patron:", qStr, 1, 1, 1, 1, 1, 1)
                    if pData.details and pData.details.treasuresMax and pData.details.treasuresMax > 0 then
                        local gColor = (pData.details.treasures or 0) >= pData.details.treasuresMax and "|cff00ff00" or
                            "|cffff0000"
                        GameTooltip:AddDoubleLine("treasures/drops:",
                            string.format("%s%d / %d|r", gColor, pData.details.treasures or 0,
                                pData.details.treasuresMax), 1, 1, 1, 1, 1, 1)
                    end
                end
                GameTooltip:Show()
            end)
            cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        else
            text:ClearAllPoints()
            text:SetPoint("CENTER", cell, "CENTER", 0, 0)
            text:SetJustifyH("CENTER")
            text:SetWidth(0)
            text:SetText("-")
            text:SetTextColor(0.5, 0.5, 0.5)
            if cell.rightText then cell.rightText:Hide() end
            cell:SetScript("OnEnter", nil)
            cell:SetScript("OnLeave", nil)
        end
        return true

    elseif cat.type == "vault_row" then
        text:Hide()
        local group = cat.group
        local squareSize = (cfg.columnWidth - 10) / 3

        for slotIdx = 1, 3 do
            local rect = cell["rect" .. slotIdx] or cell:CreateTexture(nil, "ARTWORK")
            cell["rect" .. slotIdx] = rect
            rect:Show()
            rect:SetSize(squareSize - 4, cfg.rowHeight - 12)
            rect:SetPoint("LEFT", (slotIdx - 1) * squareSize + 5, 0)

            local vData = altData.vault and altData.vault[group] and altData.vault[group][slotIdx]
            if group == "world" and slotIdx == 2 and vData and (vData.id == 229 or vData.threshold == 3) then
                vData.id = 208
                vData.threshold = 4
                if not vData.level or vData.level == 0 then
                    local s3 = altData.vault[group][3]
                    local s1 = altData.vault[group][1]
                    if s3 and s3.level and s3.level > 0 then
                        vData.level = s3.level
                        vData.itemLevel = vData.itemLevel or s3.itemLevel
                    elseif s1 and s1.level and s1.level > 0 then
                        vData.level = s1.level
                        vData.itemLevel = vData.itemLevel or s1.itemLevel
                    end
                end
            end

            if vData and vData.progress and vData.threshold and vData.progress >= vData.threshold and vData.threshold > 0 then
                rect:SetColorTexture(unpack(GetVaultColor(group, vData.level, vData.itemLevel)))
            else
                local sColors = cfg.statusColors
                rect:SetColorTexture(unpack(sColors and sColors.available or { 0, 0, 0, 0.5 }))
            end

            -- Hide any stale glow texture from previous renders
            if cell["vaultGlow" .. slotIdx] then
                cell["vaultGlow" .. slotIdx]:Hide()
            end
        end

        cell:EnableMouse(true)
        cell:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Great Vault: " .. (cat.label or group))
            local vGroup = altData.vault and altData.vault[group]

            if altData.vault and altData.vault.hasReward then
                GameTooltip:AddLine("✨ reward ready to claim!", 1, 0.82, 0)
                GameTooltip:AddLine(" ")
            end

            for idx = 1, 3 do
                local v = vGroup and vGroup[idx]
                if group == "world" and idx == 2 and v and (v.id == 229 or v.threshold == 3) then
                    v.id = 208
                    v.threshold = 4
                    if not v.level or v.level == 0 then
                        local s3 = vGroup[3]
                        local s1 = vGroup[1]
                        if s3 and s3.level and s3.level > 0 then
                            v.level = s3.level
                            v.itemLevel = v.itemLevel or s3.itemLevel
                        elseif s1 and s1.level and s1.level > 0 then
                            v.level = s1.level
                            v.itemLevel = v.itemLevel or s1.itemLevel
                        end
                    end
                end

                if v and v.threshold and v.threshold > 0 then
                    local isUnlocked = (v.progress or 0) >= v.threshold
                    local statusStr = isUnlocked and "|cff00ff00Unlocked|r" or
                        string.format("%d/%d", v.progress or 0, v.threshold)

                    local detailParts = {}
                    if v.level and v.level > 0 then
                        local diffName
                        if group == "raid" then
                            diffName = GetDifficultyName(v.level)
                        elseif group == "dungeon" then
                            diffName = (v.level >= 2 and string.format("+%d", v.level)) or "M0"
                        else
                            diffName = string.format("Tier %d", v.level)
                        end
                        table.insert(detailParts, diffName)
                    end

                    local ilvl = GetVaultItemLevel(group, v.level, v)
                    local track = GetVaultTrack(group, v.level, ilvl)
                    if ilvl and (isUnlocked or (v.level and v.level > 0)) then
                        if track then
                            table.insert(detailParts, string.format("|cffffd100%d ilvl|r (%s)", ilvl, track))
                        else
                            table.insert(detailParts, string.format("|cffffd100%d ilvl|r", ilvl))
                        end
                    end

                    local extraStr = ""
                    if #detailParts > 0 then
                        extraStr = " (" .. table.concat(detailParts, " — ") .. ")"
                    end

                    GameTooltip:AddDoubleLine("slot " .. idx .. ":", statusStr .. extraStr, 1, 1, 1, 1, 1, 1)
                end
            end

            -- Dungeon Great Vault: list the 10 runs that populate the vault with 1, 4, 10 highlighted
            if group == "dungeon" then
                local runs = altData.vault and altData.vault.dungeonRuns
                local isPlayer = (altGuid and altGuid == UnitGUID("player")) or (altGuid and altGuid == GetCurrentCharacterGUID())
                if (not runs or #runs == 0) and isPlayer and C_MythicPlus and C_MythicPlus.GetRunHistory then
                    local weeklyRuns = C_MythicPlus.GetRunHistory(false, true)
                    if weeklyRuns and #weeklyRuns > 0 then
                        runs = {}
                        for _, r in ipairs(weeklyRuns) do
                            local dName = (C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(r.mapChallengeModeID)) or ("Map " .. tostring(r.mapChallengeModeID))
                            table.insert(runs, {
                                mapID = r.mapChallengeModeID,
                                level = r.level,
                                name = dName,
                                completed = r.completed,
                                durationSec = r.durationSec or 0,
                            })
                        end
                        table.sort(runs, function(a, b)
                            if a.level ~= b.level then return a.level > b.level end
                            return (a.durationSec or 0) < (b.durationSec or 0)
                        end)
                    end
                end

                if runs and #runs > 0 then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("weekly runs (top 10):", 1, 0.82, 0)
                    for rIdx = 1, math.min(10, #runs) do
                        local r = runs[rIdx]
                        local isMilestone = (rIdx == 1 or rIdx == 4 or rIdx == 10)
                        local prefix = string.format("%2d. ", rIdx)
                        local dName = r.name or "Dungeon"
                        local lvlStr = string.format("+%d", r.level or 0)
                        if r.completed == false then
                            lvlStr = lvlStr .. " |cffff5555(Depleted)|r"
                        end

                        if isMilestone then
                            local slotTag = (rIdx == 1 and "  [Slot 1]") or (rIdx == 4 and "  [Slot 2]") or "  [Slot 3]"
                            GameTooltip:AddDoubleLine(
                                string.format("|cff00ffff%s%s%s|r", prefix, dName, slotTag),
                                string.format("|cff00ffff%s|r", lvlStr),
                                0, 1, 1, 0, 1, 1
                            )
                        else
                            GameTooltip:AddDoubleLine(
                                string.format("|cffbbbbbb%s%s|r", prefix, dName),
                                string.format("|cffffffff%s|r", lvlStr),
                                0.7, 0.7, 0.7, 1, 1, 1
                            )
                        end
                    end
                else
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("no mythic+ runs recorded this week.", 0.5, 0.5, 0.5)
                end
            end

            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return true

    elseif cat.type == "m0_grid" then
        text:Hide()
        local m0Data = altData.m0
        local instanceCache = GetEJInstanceCache()
        local ejInstances = {}
        for name, id in pairs(instanceCache) do
            table.insert(ejInstances, { id = id, name = name })
        end
        table.sort(ejInstances, function(a, b) return a.id < b.id end)

        local numDungeons = #ejInstances > 0 and #ejInstances or 8
        local squareSize = (cfg.columnWidth - 10) / numDungeons

        for bIdx, inst in ipairs(ejInstances) do
            local rect = cell["m0Rect" .. bIdx] or cell:CreateTexture(nil, "ARTWORK")
            cell["m0Rect" .. bIdx] = rect
            rect:Show()
            rect:SetSize(squareSize - 2, cfg.rowHeight - 12)
            rect:SetPoint("LEFT", (bIdx - 1) * squareSize + 5, 0)

            local sColors = cfg.statusColors
            if m0Data and m0Data[inst.id] then
                rect:SetColorTexture(unpack(sColors and sColors.completed or { 0, 1, 1, 0.8 }))
            else
                rect:SetColorTexture(unpack(sColors and sColors.available or { 0, 0, 0, 0.5 }))
            end
        end

        for bIdx = #ejInstances + 1, 20 do
            if cell["m0Rect" .. bIdx] then cell["m0Rect" .. bIdx]:Hide() end
        end

        cell:EnableMouse(true)
        cell:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Mythic 0 Lockouts")
            for _, inst in ipairs(ejInstances) do
                local isLocked = m0Data and m0Data[inst.id]
                local status = isLocked and "|cff00ffffCompleted|r" or "|cff888888Available|r"
                GameTooltip:AddDoubleLine(inst.name, status, 1, 1, 1, 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return true

    elseif cat.type == "raid_grid" then
        text:Hide()
        local difficulty = cat.difficulty
        local bossData = altData.raids and altData.raids[difficulty]
        local numBosses = 8 -- Current raid context
        local squareSize = (cfg.columnWidth - 10) / numBosses

        local r, g, b = 1, 0.8, 0      -- Default gold
        if difficulty == 16 then
            r, g, b = 0.64, 0.21, 0.93 -- Mythic Purple
        elseif difficulty == 15 then
            r, g, b = 0, 0.44, 1       -- Heroic Blue
        elseif difficulty == 14 then
            r, g, b = 0.12, 1, 0       -- Normal Green
        end

        for bIdx = 1, numBosses do
            local rect = cell["raidRect" .. bIdx] or cell:CreateTexture(nil, "ARTWORK")
            cell["raidRect" .. bIdx] = rect
            rect:Show()
            rect:SetSize(squareSize - 2, cfg.rowHeight - 12)
            rect:SetPoint("LEFT", (bIdx - 1) * squareSize + 5, 0)

            if bossData and bossData[bIdx] then
                rect:SetColorTexture(r, g, b, 0.8)
            else
                local sColors = cfg.statusColors
                rect:SetColorTexture(unpack(sColors and sColors.available or { 0, 0, 0, 0.5 }))
            end
        end

        cell:EnableMouse(true)
        cell:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local diffName = (difficulty == 16 and "Mythic") or (difficulty == 15 and "Heroic") or "Normal"
            GameTooltip:SetText(cat.label or (diffName .. " Raid"))
            local killed = 0
            if bossData then
                for bIdx = 1, numBosses do
                    if bossData[bIdx] then killed = killed + 1 end
                end
            end
            GameTooltip:AddDoubleLine("progress:", string.format("%d / %d bosses", killed, numBosses), 1, 1, 1, 1, 1, 1)
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return true
    end

    return false
end

local function ResetWeeklies()
    for _, d in pairs(SfuiDB.alts or {}) do
        if d.quests then wipe(d.quests) end
        if d.profKP then
            for _, pData in pairs(d.profKP) do
                if type(pData) == "table" then
                    pData.done = 0
                    if pData.details then
                        pData.details.treatise = false
                        pData.details.quest = false
                        pData.details.treasures = 0
                    end
                end
            end
        end
        if d.vault then
            if d.vault.raid then wipe(d.vault.raid) end
            if d.vault.dungeon then wipe(d.vault.dungeon) end
            if d.vault.world then wipe(d.vault.world) end
            if d.vault.dungeonRuns then wipe(d.vault.dungeonRuns) end
        end
        if d.m0 then wipe(d.m0) end
        if d.raids then wipe(d.raids) end
    end
    sfui.alts.UpdateUI(true)
end

-- Register Retail Provider
sfui.alts.RegisterProvider({
    name = "standard",
    GetCategories = function() return CATEGORIES end,
    RefreshDynamicCategories = RefreshDynamicCategories,
    PerformSync = PerformSync,
    CheckWeeklyResets = CheckWeeklyResets,
    ResetWeeklies = ResetWeeklies,
    RenderCell = RenderCell,
    sortOptions = {
        { text = "Name (A-Z)",  value = "name" },
        { text = "Item Level",  value = "ilvl" },
        { text = "M+ Rating",   value = "rating" },
        { text = "Time Played", value = "timeplayed" },
    },
    SortAlts = function(a, b, sortKey)
        if sortKey == "rating" then
            return (a.data.rating or 0) > (b.data.rating or 0)
        end
    end,
    OnFrameShow = function()
        if C_MythicPlus and C_MythicPlus.RequestMapInfo then C_MythicPlus.RequestMapInfo() end
        if C_MythicPlus and C_MythicPlus.RequestRewards then C_MythicPlus.RequestRewards() end
        if C_WeeklyRewards and C_WeeklyRewards.OnUIInteract then C_WeeklyRewards.OnUIInteract() end
        if RequestRaidInfo then RequestRaidInfo() end
    end,
    RegisterEvents = function()
        local function on_sync()
            sfui.alts.PerformSync()
            if SfuiAltsFrame and SfuiAltsFrame:IsShown() then
                sfui.alts.UpdateUI(true)
            end
        end
        sfui.events.RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE",       on_sync)
        sfui.events.RegisterEvent("CHALLENGE_MODE_LEADERS_UPDATE",    on_sync)
        sfui.events.RegisterEvent("MYTHIC_PLUS_NEW_WEEKLY_RECORD",    on_sync)
        sfui.events.RegisterEvent("MYTHIC_PLUS_CURRENT_AFFIX_UPDATE", on_sync)
        sfui.events.RegisterEvent("WEEKLY_REWARDS_UPDATE",            on_sync)
        sfui.events.RegisterEvent("UPDATE_INSTANCE_INFO",            on_sync)
        sfui.events.RegisterEvent("PLAYER_AVG_ITEM_LEVEL_UPDATE",     on_sync)
        sfui.events.RegisterEvent("PLAYER_EQUIPMENT_CHANGED",          on_sync)
        sfui.events.RegisterThrottledEvent("CURRENCY_DISPLAY_UPDATE", 0.5, on_sync)
        sfui.events.RegisterEvent("QUEST_TURNED_IN", function(_, questID)
            OnQuestTurnedIn(questID)
            on_sync()
        end)
        sfui.events.RegisterEvent("QUEST_ACCEPTED", on_sync)
        sfui.events.RegisterEvent("QUEST_REMOVED",  on_sync)
        sfui.events.RegisterThrottledEvent("QUEST_LOG_UPDATE", 1.0, on_sync)
    end,
})
