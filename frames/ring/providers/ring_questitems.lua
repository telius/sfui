local addonName, addon = ...
sfui = sfui or {}
sfui.ring = sfui.ring or {}

local C_Container             = _G.C_Container
local C_Item                  = _G.C_Item
local C_QuestLog              = _G.C_QuestLog
local C_ToyBox                = _G.C_ToyBox
local C_MountJournal          = _G.C_MountJournal
local C_PetJournal            = _G.C_PetJournal
local C_TooltipInfo           = _G.C_TooltipInfo
local GetQuestLogSpecialItemInfo = _G.GetQuestLogSpecialItemInfo
local GetNumQuestLogEntries   = _G.GetNumQuestLogEntries
local InCombatLockdown        = _G.InCombatLockdown
local PlayerHasToy            = _G.PlayerHasToy
local GetTime                 = _G.GetTime
local tonumber                = _G.tonumber
local tostring                = _G.tostring
local select                  = _G.select
local pcall                   = _G.pcall
local table_sort              = table.sort
local table_wipe              = _G.wipe or table.wipe or function(t) for k in pairs(t) do t[k] = nil end end

-- ── 1. Static Reference Tables & Whitelists ───────────────────────────────────

-- weekly inscription treatises (mapped to their hidden weekly completion quest id)
local TREATISE_QUESTS = {
    -- the war within
    [222546] = 83725, -- alchemy
    [222547] = 83735, -- blacksmithing
    [222548] = 83730, -- enchanting
    [222549] = 83732, -- engineering
    [222550] = 83727, -- herbalism
    [222551] = 83731, -- inscription
    [222552] = 83729, -- jewelcrafting
    [222553] = 83733, -- leatherworking
    [222554] = 83726, -- mining
    [222621] = 83728, -- skinning
    [222649] = 83734, -- tailoring

    -- midnight
    [245755] = 95127,
    [245756] = 95137,
    [245757] = 95131,
    [245758] = 95134,
    [245759] = 95129,
    [245760] = 95133,
    [245761] = 95130,
    [245762] = 95135,
    [245763] = 95128,
    [245809] = 95138,
    [245828] = 95136,
}

-- dragon shards of knowledge, slumbering draconic, titan matrices, knowledge tomes
local KNOWLEDGE_ITEMS = {
    [198798] = true, [198800] = true, [201359] = true, [198675] = true, [198694] = true,
    [198689] = true, [198799] = true, [201358] = true, [201356] = true, [201357] = true,
    [201360] = true, [204990] = true, [205001] = true, [204999] = true, [200939] = true,
    [200940] = true, [200941] = true, [200942] = true, [200943] = true, [200945] = true,
    [200946] = true, [200947] = true, [210231] = true, [210228] = true, [210234] = true,
}

-- knowledge grant spell ids
local KNOWLEDGE_SPELLS = {
    [375806] = true,
    [411602] = true,
    [409074] = true,
    [409490] = true,
    [409643] = true,
}

-- threshold combination items (only include when bag count reaches minimum required)
local THRESHOLD_ITEMS = {
    [229899] = 100, -- coffer key shard (tww season 1)
    [236096] = 100, -- coffer key shard (tww season 2)
    [245653] = 100, -- coffer key shard (tww season 3)
    [254267] = 100, -- fragmented memento
    [253224] = 10,  -- mote of a broken time
    [224292] = 3,   -- radiant fuel shard
}

-- curated expansion caches, lockboxes, satchels, and paragon reward chests
local KNOWN_CACHES = {
    -- tww pinnacle & weekly event caches
    [224784] = true, [239118] = true, [244865] = true, -- pinnacle cache [seasonal]
    [226263] = true, [239128] = true, [250763] = true, -- theater troupe's trove [seasonal]
    [226264] = true, [239126] = true, [250766] = true, -- radiant cache [seasonal]
    [226273] = true, [239121] = true, [250765] = true, -- awakened mechanical cache [seasonal]
    [229129] = true, [229130] = true,                   -- delver's spoils [seasonal]
    [228741] = true,                                     -- lamplighter supply satchel
    [228361] = true, [239120] = true, [235610] = true, [235639] = true, -- seasoned adventurer's cache
    [245280] = true, [244883] = true,                   -- seasoned adventurer's cache s3
    [229354] = true,                                     -- algari adventurer's cache

    -- severed threads pact weeklies
    [225571] = true, [239125] = true, [250769] = true, -- weaver weekly
    [225572] = true, [239122] = true, [250767] = true, -- general weekly
    [225573] = true, [239124] = true, [250768] = true, -- vizier weekly
    [238207] = true, [238208] = true, [250764] = true, -- surge dividends

    -- tww actor / daily / consortium
    [217011] = true, [217012] = true, [217013] = true, -- actor's chest
    [235151] = true,                                     -- distinguished actor's chest
    [227792] = true,                                     -- everyday cache
    [227713] = true,                                     -- art consortium payout
    [225249] = true,                                     -- bag o' gold
    [220152] = true,                                     -- cursed ghoulfish

    -- renown & reputation overflow paragon caches
    [226103] = true, [226045] = true, [226100] = true,
    [225247] = true, [225246] = true, [225239] = true, [225245] = true, [232463] = true,
    [239489] = true, [230032] = true,
    [152102] = true, [152103] = true, [152104] = true, [152105] = true,
    [152106] = true, [152107] = true, [152108] = true, -- legion paragon boxes

    -- siren isle / undermine / nightfall
    [235548] = true, [232372] = true, [234816] = true, -- siren isle cache, bygone riches, bag of iron
    [236756] = true, [236757] = true, [236758] = true, -- undermine tip chests
    [237743] = true, [237759] = true, [237760] = true, -- nightfall participation coffers
    [239004] = true, [239546] = true,                   -- nightfall quest/scenario completion
    [244696] = true,                                     -- overcharged chest
    [245589] = true,                                     -- hellcaller chest
    [244842] = true,                                     -- fabled veteran's cache
    [245611] = true,                                     -- wriggling pinnacle cache [11.2]
    [255676] = true,                                     -- phase diver's cache [11.2]
    [247820] = true,                                     -- cache of k'areshi treasures

    -- legion remix
    [242617] = true,                                     -- curious simulacrum
    [237812] = true, [239303] = true, [245553] = true, [256763] = true, -- cache of infinite treasure
    [248247] = true, [251821] = true,                   -- cache of infinite power
    [246812] = true, [246815] = true, [246814] = true, [246813] = true, -- bronze caches
    [245925] = true, [249891] = true,                   -- artifactium sand
    [246936] = true, [246937] = true,                   -- epoch memento

    -- midnight caches
    [268297] = true,                                     -- bag o' gold
    [264274] = true,                                     -- fabled adventurer's
    [268545] = true, [257023] = true, [257026] = true, [262346] = true, -- preyseeker's
    [265995] = true,                                     -- quel'thalas adventurer's
    [246585] = true,                                     -- consortium payout
    [250116] = true,                                     -- quel'thalas treasures
    [269701] = true, [269702] = true, [269703] = true, -- party favors, abundant, avid learner's
    [270244] = true, [270247] = true,                   -- field pouch / satchel
    [264914] = true,                                     -- ranger's cache
    [254677] = true, [279527] = true,                   -- apex cache
    [263465] = true, [279522] = true,                   -- saltheril's soiree
    [260940] = true, [279526] = true,                   -- stormarion pinnacle
    [263466] = true, [279523] = true,                   -- abundant
    [263467] = true, [279525] = true,                   -- avid learner's
    [260193] = true, [279520] = true,                   -- fabled veteran's
    [282183] = true,                                     -- coiled isle
    [275690] = true, [275691] = true,                   -- riftstalker's cache
    [276389] = true, [276390] = true,                   -- riftstalker's prize

    -- world events & holiday items
    [21746]  = true,                                     -- lucky red envelope
    [37586]  = true,                                     -- handful of treats
    [169219] = true,                                     -- brewfest sampler
    [199192] = true, [204359] = true, [205226] = true, [210549] = true, [227450] = true, -- racer's purses
}

local EXCLUDED_ITEMS = {
    [204561] = true,
    [232466] = true, -- leave the storm, siren isle
    [246808] = true, -- heroic tier instructions, legion remix
}

-- ── 2. Inspection & Detection Helpers ─────────────────────────────────────────

local openableCache = {}
local knowledgeCache = {}

local function get_container_quest_info(bag, slot)
    if C_Container and C_Container.GetContainerItemQuestInfo then
        local iqi = C_Container.GetContainerItemQuestInfo(bag, slot)
        if iqi then
            return iqi.isQuestItem, iqi.questID, iqi.isActive
        end
    end
    return false, nil, false
end

local function is_quest_completed(questID)
    if not questID then return false end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        return C_QuestLog.IsQuestFlaggedCompleted(questID)
    end
    return false
end

local function get_quest_distance(questID)
    if questID and C_QuestLog and C_QuestLog.GetDistanceSqToQuest then
        local distSq, onContinent = C_QuestLog.GetDistanceSqToQuest(questID)
        if distSq and onContinent then
            return distSq
        end
    end
    return 999999999
end

local function is_treatise_available(itemID)
    local qid = TREATISE_QUESTS[itemID]
    if not qid then return false end
    -- if the weekly quest has already been completed this reset, do not show
    if is_quest_completed(qid) then
        return false
    end
    return true
end

local function is_usable_knowledge(bag, slot, itemID)
    if knowledgeCache[itemID] ~= nil then
        return knowledgeCache[itemID]
    end

    if KNOWLEDGE_ITEMS[itemID] then
        knowledgeCache[itemID] = true
        return true
    end

    if C_Item and C_Item.GetItemSpell then
        local spellName, spellID = C_Item.GetItemSpell(itemID)
        if spellID and KNOWLEDGE_SPELLS[spellID] then
            knowledgeCache[itemID] = true
            return true
        end
    end

    if C_TooltipInfo and C_TooltipInfo.GetBagItem and bag and slot then
        local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
        if ok and data and data.lines and #data.lines > 0 then
            for l = 1, #data.lines do
                local line = data.lines[l]
                local lt = line and line.leftText
                if lt then
                    local lower = lt:lower()
                    if lower:find("specialization point")
                       or lower:find("profession knowledge")
                       or lower:find("study to increase")
                       or lower:find("knowledge point") then
                        knowledgeCache[itemID] = true
                        return true
                    end
                end
            end
            knowledgeCache[itemID] = false
        end
    end

    return false
end

local function is_key_or_charm(itemID, itemName)
    if not itemID then return false end

    -- explicit threshold combination items (e.g. coffer key shards) are handled separately
    if THRESHOLD_ITEMS[itemID] then
        return false
    end
    if KNOWN_CACHES[itemID] then
        return false
    end

    local classID = C_Item and C_Item.GetItemInfoInstant and select(6, C_Item.GetItemInfoInstant(itemID))
    if classID == 13 or (_G.Enum and _G.Enum.ItemClass and classID == _G.Enum.ItemClass.Key) then
        return true
    end

    if not itemName and C_Item and C_Item.GetItemNameByID then
        itemName = C_Item.GetItemNameByID(itemID)
    end
    if itemName then
        local lower = itemName:lower()
        if lower:find("key") or lower:find("charm") or lower:find("lockpick") then
            return true
        end
    end

    return false
end

local function is_openable_container(bag, slot, itemID, itemName)
    if openableCache[itemID] ~= nil then
        return openableCache[itemID]
    end

    -- keys, charms, and tools are never openable reward containers
    if is_key_or_charm(itemID, itemName) then
        openableCache[itemID] = false
        return false
    end

    if KNOWN_CACHES[itemID] then
        openableCache[itemID] = true
        return true
    end

    -- equippable weapons and armor are never openable reward containers
    if C_Item and C_Item.IsEquippableItem and C_Item.IsEquippableItem(itemID) then
        openableCache[itemID] = false
        return false
    end

    -- scan tooltip lines for exact ITEM_OPENABLE (<Right Click to Open>) or localized open cues
    if C_TooltipInfo and C_TooltipInfo.GetBagItem and bag and slot then
        local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
        if ok and data and data.lines and #data.lines > 0 then
            for l = 1, #data.lines do
                local line = data.lines[l]
                local lt = line and line.leftText
                if lt then
                    if (_G.ITEM_OPENABLE and lt == _G.ITEM_OPENABLE)
                       or lt:find("<.*[Oo]pen.*>")
                       or lt:find("<.*[kK]lick.*>") then
                        openableCache[itemID] = true
                        return true
                    end
                end
            end
            openableCache[itemID] = false
        end
    end

    return false
end

local function is_uncollected_toy(itemID)
    if C_ToyBox and C_ToyBox.GetToyLink then
        local link = C_ToyBox.GetToyLink(itemID)
        if link and PlayerHasToy and not PlayerHasToy(itemID) then
            return true
        end
    end
    return false
end

local function is_uncollected_mount(itemID)
    if C_MountJournal and C_MountJournal.GetMountFromItem then
        local mountID = C_MountJournal.GetMountFromItem(itemID)
        if mountID and C_MountJournal.GetMountInfoByID then
            local isCollected = select(11, C_MountJournal.GetMountInfoByID(mountID))
            if isCollected == false then
                return true
            end
        end
    end
    return false
end

local function is_uncollected_pet(itemID)
    if C_PetJournal and C_PetJournal.GetPetInfoByItemID and C_PetJournal.GetNumCollectedInfo then
        local speciesID = select(13, C_PetJournal.GetPetInfoByItemID(itemID))
        if speciesID then
            local num, max = C_PetJournal.GetNumCollectedInfo(speciesID)
            if max and num and num < max then
                return true
            end
        end
    end
    return false
end

-- ── 3. Provider Definition & Scanning ─────────────────────────────────────────

local cachedResult = {}
local lastScanTime = 0

sfui.events.RegisterEvent("BAG_UPDATE_DELAYED", function()
    lastScanTime = 0
end)

sfui.events.RegisterEvent("QUEST_LOG_UPDATE", function()
    lastScanTime = 0
end)

sfui.ring.register_provider("questitems", {
    name   = "quest items",
    title  = "quest items",
    events = {
        "QUEST_LOG_UPDATE",
        "BAG_UPDATE_DELAYED",
        "ZONE_CHANGED_NEW_AREA",
        "ZONE_CHANGED",
        "PLAYER_ENTERING_WORLD",
        "TOYS_UPDATED",
        "NEW_MOUNT_ADDED",
        "NEW_PET_ADDED",
        "QUEST_TURNED_IN",
    },
    build  = function(out)
        -- in combat: never perform heavy multi-slot bag scanning or map queries
        if (InCombatLockdown and InCombatLockdown()) or sfui.common.is_in_combat() then
            for i = 1, #cachedResult do
                out[#out + 1] = cachedResult[i]
            end
            return
        end

        -- throttle out-of-combat bag scans to at most once per 0.5s
        local now = GetTime()
        if (now - lastScanTime) < 0.5 and #cachedResult > 0 then
            for i = 1, #cachedResult do
                out[#out + 1] = cachedResult[i]
            end
            return
        end
        lastScanTime = now

        local includeChests       = (sfui.db and sfui.db.Get and sfui.db.Get("ring", "quest_include_chests", true)) ~= false
        local includeKnowledge    = (sfui.db and sfui.db.Get and sfui.db.Get("ring", "quest_include_knowledge", true)) ~= false
        local includeCollectibles = (sfui.db and sfui.db.Get and sfui.db.Get("ring", "quest_include_collectibles", true)) ~= false
        local maxSlices           = (sfui.db and sfui.db.Get and sfui.db.Get("ring", "quest_max_slices", 14)) or 14

        local seen = {}
        local items = {}

        -- 1. scan player bags for usable quest items, chests, knowledge, and collectibles
        local maxBags = (sfui.isRetail or (select(4, _G.GetBuildInfo()) >= 100000)) and 5 or 4
        if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID then
            for bag = 0, maxBags do
                local numSlots = C_Container.GetContainerNumSlots(bag) or 0
                for slot = 1, numSlots do
                    local itemID = C_Container.GetContainerItemID(bag, slot)
                    if itemID and not seen[itemID] and not EXCLUDED_ITEMS[itemID] then
                        local itemName = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)) or ("item " .. itemID)
                        local isKeyOrCharm = is_key_or_charm(itemID, itemName)
                        local count = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(itemID)) or 1

                        local cat = nil
                        local dist = 900000000

                        if not isKeyOrCharm then
                            local isQuest, itemQuestID, isQuestActive = get_container_quest_info(bag, slot)
                            local hasSpell = C_Item and C_Item.GetItemSpell and C_Item.GetItemSpell(itemID)
                            local startsQuest = itemQuestID and not isQuestActive and not is_quest_completed(itemQuestID)
                            local isQuestOnLog = isQuestActive or (itemQuestID and C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(itemQuestID))

                            -- category 1: active usable quest items
                            if isQuest and hasSpell and (isQuestOnLog or not is_quest_completed(itemQuestID)) then
                                cat = 1
                                dist = get_quest_distance(itemQuestID)

                            -- category 2: quest starters
                            elseif startsQuest then
                                cat = 2
                                dist = get_quest_distance(itemQuestID)

                            -- category 3: weekly treatises and profession knowledge
                            elseif includeKnowledge and TREATISE_QUESTS[itemID] then
                                if is_treatise_available(itemID) then
                                    cat = 3
                                end
                            elseif includeKnowledge and is_usable_knowledge(bag, slot, itemID) then
                                cat = 3

                            -- category 4: openable caches/chests
                            elseif includeChests and is_openable_container(bag, slot, itemID, itemName) then
                                cat = 4

                            -- category 5: uncollected toys, mounts, and battle pets
                            elseif includeCollectibles and (is_uncollected_toy(itemID) or is_uncollected_mount(itemID) or is_uncollected_pet(itemID)) then
                                cat = 5
                            end
                        elseif includeChests and THRESHOLD_ITEMS[itemID] and count >= THRESHOLD_ITEMS[itemID] then
                            -- category 4: threshold items (e.g. 100 coffer key shards)
                            cat = 4
                        end

                        if cat then
                            seen[itemID] = true
                            local itemIcon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)) or 134400

                            items[#items + 1] = {
                                id          = "qi_" .. itemID,
                                itemID      = itemID,
                                bag         = bag,
                                slot        = slot,
                                questID     = itemQuestID,
                                startsQuest = (cat == 2) or startsQuest,
                                category    = cat,
                                label       = itemName:lower(),
                                icon        = itemIcon,
                                count       = count,
                                dist        = dist,
                                attrs       = {
                                    type      = "macro",
                                    macrotext = "/use item:" .. itemID,
                                },
                            }
                        end
                    end
                end
            end
        end

        -- 2. scan quest log for quest special action items
        local numQuests = 0
        if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
            numQuests = C_QuestLog.GetNumQuestLogEntries()
        elseif GetNumQuestLogEntries then
            numQuests = GetNumQuestLogEntries()
        end

        if GetQuestLogSpecialItemInfo then
            for i = 1, numQuests do
                local qInfo
                if C_QuestLog and C_QuestLog.GetInfo then
                    qInfo = C_QuestLog.GetInfo(i)
                end

                local isHeader = qInfo and qInfo.isHeader
                local isComplete = qInfo and qInfo.isComplete
                local questID = qInfo and qInfo.questID

                if not isHeader then
                    local link, icon, charges, showWhenComplete = GetQuestLogSpecialItemInfo(i)
                    if link and (showWhenComplete or not isComplete) then
                        local itemID = tonumber(link:match("item:(%d+)"))
                        local rawName = link:match("%[(.-)%]") or ("quest item " .. tostring(itemID))
                        if itemID and not seen[itemID] and not EXCLUDED_ITEMS[itemID] and not is_key_or_charm(itemID, rawName) then
                            seen[itemID] = true
                            local dist = get_quest_distance(questID)

                            local qIndex = i
                            items[#items + 1] = {
                                id            = "qi_" .. itemID,
                                itemID        = itemID,
                                questLogIndex = qIndex,
                                questID       = questID,
                                startsQuest   = false,
                                category      = 1,
                                label         = rawName:lower(),
                                icon          = icon,
                                charges       = charges,
                                count         = (charges and charges > 0) and charges or 0,
                                dist          = dist,
                                attrs         = {
                                    type      = "macro",
                                    macrotext = "/use item:" .. itemID,
                                },
                            }
                        end
                    end
                end
            end
        end

        -- 3. sort items: category priority first, then distance (for quest items) or label
        table_sort(items, function(a, b)
            if a.category ~= b.category then
                return a.category < b.category
            end
            if a.category == 1 and a.dist ~= b.dist then
                return a.dist < b.dist
            end
            if a.label ~= b.label then
                return a.label < b.label
            end
            return a.itemID < b.itemID
        end)

        -- 4. emit to output (capped to configured max items to prevent radial clutter) and update cache
        table_wipe(cachedResult)
        for i = 1, math.min(#items, maxSlices) do
            cachedResult[#cachedResult + 1] = items[i]
            out[#out + 1] = items[i]
        end
    end,
})
