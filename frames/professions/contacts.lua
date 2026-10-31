local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.recipes = sfui.recipes or {}

local g      = sfui.config
local common = sfui.common
local cfg    = g.recipe_catalog or g.recipes or g.professions or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/professions/contacts.lua
--  Dynamic Recipe Contacts & Finds Observer (Camelot / Classic Forever)
--
--  Passively catalogs all visited crafting vendors (MERCHANT_SHOW),
--  profession trainers (TRAINER_SHOW), mob recipe drops (LOOT_OPENED),
--  and quest recipe rewards (QUEST_DETAIL/COMPLETE).
--  Uses sfui.events central dispatcher (zero standalone frames).
-- ══════════════════════════════════════════════════════════════════════════════

if sfui.isRetail then return end

-- Localized APIs
local UnitName                      = _G.UnitName
local UnitGUID                      = _G.UnitGUID
local UnitExists                    = _G.UnitExists
local UnitIsDead                    = _G.UnitIsDead
local UnitIsPlayer                  = _G.UnitIsPlayer
local C_Map                         = _G.C_Map
local C_Item                        = _G.C_Item or {}
local C_Item_GetItemInfoInstant     = sfui.common.get_item_instant_info
local GetMerchantNumItems           = _G.GetMerchantNumItems
local GetMerchantItemInfo           = sfui.api.GetMerchantItemInfo
local GetMerchantItemLink           = _G.GetMerchantItemLink
local GetNumTrainerServices         = _G.GetNumTrainerServices
local GetTrainerServiceInfo         = _G.GetTrainerServiceInfo
local GetTrainerServiceCost         = _G.GetTrainerServiceCost
local GetTrainerServiceSkillReq     = _G.GetTrainerServiceSkillReq
local GetNumLootItems               = _G.GetNumLootItems
local GetLootSlotLink               = _G.GetLootSlotLink
local GetNumQuestRewards            = _G.GetNumQuestRewards
local GetNumQuestChoices            = _G.GetNumQuestChoices
local GetQuestItemLink              = _G.GetQuestItemLink
local GetTitleText                  = _G.GetTitleText
local GetRealZoneText               = _G.GetRealZoneText
local GetSubZoneText                = _G.GetSubZoneText
local strsplit                      = _G.strsplit
local tonumber, tostring            = _G.tonumber, _G.tostring
local pcall, type                   = _G.pcall, _G.type
local pairs, ipairs                 = _G.pairs, _G.ipairs
local math_floor                    = math.floor
local time                          = _G.time
local table_insert                  = table.insert

-- Recipe item class constant (9 = Recipe)
local ITEM_CLASS_RECIPE = 9

local function EnsureStorage()
    SfuiDB = SfuiDB or {}
    SfuiDB.contacts = SfuiDB.contacts or {}
    SfuiDB.contacts.vendors = SfuiDB.contacts.vendors or {}
    SfuiDB.contacts.trainers = SfuiDB.contacts.trainers or {}
    SfuiDB.recipe_finds = SfuiDB.recipe_finds or {}
    SfuiDB.recipe_finds.drops = SfuiDB.recipe_finds.drops or {}
    SfuiDB.recipe_finds.quests = SfuiDB.recipe_finds.quests or {}
end

local function GetNpcID(unit)
    unit = unit or "npc"
    if not UnitExists(unit) then return nil end
    local guid = UnitGUID(unit)
    if not guid or type(guid) ~= "string" then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then
        return tonumber(id)
    end
    return nil
end

local function GetPlayerPosition()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end

    local mapInfo = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    local zoneName = mapInfo and mapInfo.name or (GetRealZoneText and GetRealZoneText()) or ""
    local subzoneName = GetSubZoneText and GetSubZoneText()
    local x, y = nil, nil

    if C_Map.GetPlayerMapPosition then
        local pos = C_Map.GetPlayerMapPosition(mapID, "player")
        if pos then
            local px, py = pos:GetXY()
            if px and py and (px > 0 or py > 0) then
                x = math_floor(px * 10000 + 0.5) / 10000
                y = math_floor(py * 10000 + 0.5) / 10000
            end
        end
    end

    return {
        mapID   = mapID,
        zone    = zoneName:lower(),
        subzone = (subzoneName and subzoneName ~= "" and subzoneName ~= zoneName) and subzoneName:lower() or nil,
        x       = x,
        y       = y,
    }
end

-- ── 1. Merchant Scanner (MERCHANT_SHOW) ───────────────────────────────────────
local function ScanMerchant()
    EnsureStorage()
    local npcID = GetNpcID("npc")
    local npcName = UnitName("npc")
    if not npcID or not npcName then return end

    local pos = GetPlayerPosition()
    local numItems = (GetMerchantNumItems and GetMerchantNumItems()) or 0
    if numItems <= 0 then return end

    local dbRecipes = sfui.recipes_camelot and sfui.recipes_camelot.items or {}
    local vendorEntry = nil

    local C_TooltipInfo = _G.C_TooltipInfo
    local GetMerchantItemCostInfo = _G.GetMerchantItemCostInfo
    local GetMerchantItemCostItem = _G.GetMerchantItemCostItem

    for i = 1, numItems do
        local link = GetMerchantItemLink(i)
        local itemID = link and tonumber(link:match("item:(%d+)"))
        if itemID then
            local classID = nil
            if C_Item_GetItemInfoInstant then
                classID = select(6, C_Item_GetItemInfoInstant(itemID))
            end

            -- Check if item is a recipe or in our camelot recipe scroll database
            if classID == ITEM_CLASS_RECIPE or dbRecipes[itemID] then
                if not vendorEntry then
                    vendorEntry = SfuiDB.contacts.vendors[npcID] or {
                        name    = npcName:lower(),
                        npcID   = npcID,
                        mapID   = pos and pos.mapID,
                        zone    = pos and pos.zone,
                        subzone = pos and pos.subzone,
                        x       = pos and pos.x,
                        y       = pos and pos.y,
                        items   = {},
                    }
                end

                local merchantInfo = GetMerchantItemInfo and GetMerchantItemInfo(i)
                local price = merchantInfo and merchantInfo.price
                local avail = merchantInfo and merchantInfo.numAvailable
                local itemData = {
                    name        = (merchantInfo and merchantInfo.name) or link:match("%[(.-)%]") or "recipe",
                    priceCopper = price,
                    limited     = (avail and avail >= 0) and avail or nil,
                    lastSeen    = time(),
                }

                -- 1. Barter / Alternative Currency Detection (Tokens)
                if GetMerchantItemCostInfo and GetMerchantItemCostItem then
                    local numCosts = GetMerchantItemCostInfo(i) or 0
                    if numCosts > 0 then
                        local tokenParts = {}
                        for cIdx = 1, numCosts do
                            local _, count, itemLink = GetMerchantItemCostItem(i, cIdx)
                            local cName = itemLink and itemLink:match("%[(.-)%]") or "token"
                            if count and count > 1 then
                                table_insert(tokenParts, string.format("%s x%d", cName:lower(), count))
                            else
                                table_insert(tokenParts, cName:lower())
                            end
                        end
                        if #tokenParts > 0 then
                            itemData.tokens = table.concat(tokenParts, ", ")
                        end
                    end
                end

                -- 2. Dynamic Tooltip Scanning for Reputation & Specialization Requirements
                if C_TooltipInfo and C_TooltipInfo.GetMerchantItem then
                    local ok, ttData = pcall(C_TooltipInfo.GetMerchantItem, i)
                    if ok and ttData and ttData.lines then
                        for _, line in ipairs(ttData.lines) do
                            local text = line.leftText or (line.args and line.args[2] and line.args[2].stringVal)
                            if text then
                                local lower = text:lower()
                                -- Match: "Requires <Faction> - <Standing>"
                                local faction, standing = lower:match("requires%s+([%w%s']+.*)%s+%-%s+(%a+)")
                                if faction and standing then
                                    itemData.faction = faction:gsub("^%s+", ""):gsub("%s+$", "")
                                    itemData.standing = standing:gsub("^%s+", ""):gsub("%s+$", "")
                                end
                                -- Match: "Requires <Specialization>"
                                if lower:find("^requires%s+") and (lower:find("engineering") or lower:find("leatherworking") or lower:find("armorsmith") or lower:find("weaponsmith")) then
                                    local spec = lower:match("^requires%s+([%w%s]+)")
                                    if spec then
                                        itemData.spec = spec:gsub("^%s+", ""):gsub("%s+$", "")
                                    end
                                end
                            end
                        end
                    end
                end

                vendorEntry.items[itemID] = itemData
            end
        end
    end

    if vendorEntry then
        SfuiDB.contacts.vendors[npcID] = vendorEntry
        if sfui.recipes and sfui.recipes.InvalidateLiveIndices then
            sfui.recipes.InvalidateLiveIndices()
        end
        if sfui.events and sfui.events.SendMessage then
            sfui.events.SendMessage("SFUI_CONTACTS_UPDATED", "vendor", npcID)
        end
    end
end

-- ── 2. Trainer Scanner (TRAINER_SHOW) ─────────────────────────────────────────
local function ScanTrainer()
    EnsureStorage()
    local npcID = GetNpcID("npc")
    local npcName = UnitName("npc")
    if not npcID or not npcName then return end

    local pos = GetPlayerPosition()
    local numServices = (GetNumTrainerServices and GetNumTrainerServices()) or 0
    if numServices <= 0 then return end

    local trainerEntry = SfuiDB.contacts.trainers[npcID] or {
        name    = npcName:lower(),
        npcID   = npcID,
        mapID   = pos and pos.mapID,
        zone    = pos and pos.zone,
        subzone = pos and pos.subzone,
        x       = pos and pos.x,
        y       = pos and pos.y,
        spells  = {},
    }

    for i = 1, numServices do
        local serviceName, subText, category = GetTrainerServiceInfo(i)
        if category ~= "header" and serviceName and serviceName ~= "" then
            local cost = (GetTrainerServiceCost and GetTrainerServiceCost(i)) or 0
            local skillReq, rankReq = nil, nil
            if GetTrainerServiceSkillReq then
                skillReq, rankReq = GetTrainerServiceSkillReq(i)
            end

            trainerEntry.spells[serviceName:lower()] = {
                name     = serviceName:lower(),
                cost     = cost,
                reqSkill = (skillReq and rankReq and rankReq > 0) and (skillReq .. " " .. rankReq) or nil,
                lastSeen = time(),
            }
        end
    end

    SfuiDB.contacts.trainers[npcID] = trainerEntry
    if sfui.recipes and sfui.recipes.InvalidateLiveIndices then
        sfui.recipes.InvalidateLiveIndices()
    end
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_CONTACTS_UPDATED", "trainer", npcID)
    end
end

-- ── 3. Loot Observer (LOOT_OPENED) ────────────────────────────────────────────
local function ScanLoot()
    EnsureStorage()
    local numItems = (GetNumLootItems and GetNumLootItems()) or 0
    if numItems <= 0 then return end

    local pos = GetPlayerPosition()
    local targetName = nil
    if UnitExists("target") and UnitIsDead("target") and not UnitIsPlayer("target") then
        targetName = UnitName("target")
    end

    local dbRecipes = sfui.recipes_camelot and sfui.recipes_camelot.items or {}
    local updatedDrop = nil

    for i = 1, numItems do
        local link = GetLootSlotLink(i)
        local itemID = link and tonumber(link:match("item:(%d+)"))
        if itemID then
            local classID = nil
            if C_Item_GetItemInfoInstant then
                classID = select(6, C_Item_GetItemInfoInstant(itemID))
            end

            if classID == ITEM_CLASS_RECIPE or dbRecipes[itemID] then
                local rawName = link:match("%[(.-)%]") or ""
                local cleanName = rawName:gsub("^(Recipe|Pattern|Plans|Schematic|Formula|Manual|Book):%s*", ""):lower()

                if cleanName ~= "" then
                    SfuiDB.recipe_finds.drops[cleanName] = SfuiDB.recipe_finds.drops[cleanName] or {}
                    local list = SfuiDB.recipe_finds.drops[cleanName]
                    local found = false

                    for _, entry in ipairs(list) do
                        if entry.mob == (targetName and targetName:lower() or "creature") and entry.zone == (pos and pos.zone) then
                            entry.count = (entry.count or 1) + 1
                            entry.lastSeen = time()
                            found = true
                            break
                        end
                    end

                    if not found then
                        table_insert(list, {
                            mob      = targetName and targetName:lower() or "creature",
                            zone     = pos and pos.zone,
                            mapID    = pos and pos.mapID,
                            x        = pos and pos.x,
                            y        = pos and pos.y,
                            count    = 1,
                            lastSeen = time(),
                        })
                    end
                    updatedDrop = cleanName
                end
            end
        end
    end

    if updatedDrop and sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_CONTACTS_UPDATED", "drop", updatedDrop)
    end
end

-- ── 4. Quest Observer (QUEST_DETAIL / QUEST_COMPLETE) ─────────────────────────
local function ScanQuest()
    EnsureStorage()
    local questTitle = (GetTitleText and GetTitleText()) or nil
    if not questTitle or questTitle == "" then return end

    local giverName = UnitExists("npc") and UnitName("npc") or nil
    local pos = GetPlayerPosition()
    local dbRecipes = sfui.recipes_camelot and sfui.recipes_camelot.items or {}
    local updatedQuest = nil

    for _, kind in ipairs({ "reward", "choice" }) do
        local count = (kind == "reward" and GetNumQuestRewards and GetNumQuestRewards())
                   or (kind == "choice" and GetNumQuestChoices and GetNumQuestChoices())
                   or 0

        for i = 1, count do
            local link = GetQuestItemLink(kind, i)
            local itemID = link and tonumber(link:match("item:(%d+)"))
            if itemID then
                local classID = nil
                if C_Item_GetItemInfoInstant then
                    classID = select(6, C_Item_GetItemInfoInstant(itemID))
                end

                if classID == ITEM_CLASS_RECIPE or dbRecipes[itemID] then
                    local rawName = link:match("%[(.-)%]") or ""
                    local cleanName = rawName:gsub("^(Recipe|Pattern|Plans|Schematic|Formula|Manual|Book):%s*", ""):lower()

                    if cleanName ~= "" then
                        SfuiDB.recipe_finds.quests[cleanName] = SfuiDB.recipe_finds.quests[cleanName] or {}
                        local list = SfuiDB.recipe_finds.quests[cleanName]
                        local found = false

                        for _, entry in ipairs(list) do
                            if entry.title == questTitle:lower() then
                                found = true
                                break
                            end
                        end

                        if not found then
                            table_insert(list, {
                                title    = questTitle:lower(),
                                giver    = giverName and giverName:lower() or nil,
                                zone     = pos and pos.zone,
                                lastSeen = time(),
                            })
                            updatedQuest = cleanName
                        end
                    end
                end
            end
        end
    end

    if updatedQuest and sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_CONTACTS_UPDATED", "quest", updatedQuest)
    end
end

-- ── Central Event Registration (sfui.events) ──────────────────────────────────
if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("MERCHANT_SHOW", ScanMerchant)
    sfui.events.RegisterEvent("TRAINER_SHOW", ScanTrainer)
    sfui.events.RegisterEvent("LOOT_OPENED", ScanLoot)
    sfui.events.RegisterEvent("QUEST_DETAIL", ScanQuest)
    sfui.events.RegisterEvent("QUEST_COMPLETE", ScanQuest)
end
