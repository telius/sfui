local addonName, addon = ...
sfui = sfui or {}
sfui.triage = sfui.triage or {}
local triage = sfui.triage

local common = sfui.common
local issecretvalue = common.issecretvalue or _G.issecretvalue

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/automation/triage.lua
--  Automated Bag Triage & Overflow Discard Confirmation System
--
--  Monitors regular bag space while leveling/questing. When free slots drop
--  to 1 or 0, analyzes lowest-value grey junk (or outdated consumables)
--  and prompts the player with a safe, confirmed one-click drop action.
-- ══════════════════════════════════════════════════════════════════════════════

-- Localize frequently called globals
local CreateFrame              = _G.CreateFrame
local UIParent                 = _G.UIParent
local InCombatLockdown         = _G.InCombatLockdown
local PlaySound                = _G.PlaySound
local SOUNDKIT                 = _G.SOUNDKIT
local UnitLevel                = _G.UnitLevel
local UnitIsDeadOrGhost        = _G.UnitIsDeadOrGhost
local C_Timer                  = _G.C_Timer
local C_Container              = _G.C_Container
local Enum                     = _G.Enum

-- Container API compatibility (Classic Era, Camelot, Retail)
local GetContainerNumSlots     = (C_Container and C_Container.GetContainerNumSlots) or _G.GetContainerNumSlots
local GetContainerNumFreeSlots = (C_Container and C_Container.GetContainerNumFreeSlots) or _G.GetContainerNumFreeSlots
local GetContainerItemInfo     = (C_Container and C_Container.GetContainerItemInfo) or _G.GetContainerItemInfo
local GetContainerItemID       = (C_Container and C_Container.GetContainerItemID) or _G.GetContainerItemID
local GetContainerItemLink     = (C_Container and C_Container.GetContainerItemLink) or _G.GetContainerItemLink
local PickupContainerItem      = (C_Container and C_Container.PickupContainerItem) or _G.PickupContainerItem
local DeleteCursorItem         = _G.DeleteCursorItem
local ClearCursor              = _G.ClearCursor
local CursorHasItem            = _G.CursorHasItem

local math_max                 = math.max
local math_min                 = math.min
local table_sort               = table.sort
local table_insert             = table.insert
local ipairs                   = ipairs
local string_format            = string.format
local wipe                     = _G.wipe or table.wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

local UnitCastingInfo          = _G.UnitCastingInfo
local UnitChannelInfo          = _G.UnitChannelInfo
local SpellIsTargeting         = _G.SpellIsTargeting
local GetCursorInfo            = _G.GetCursorInfo

local _, playerClass           = _G.UnitClass("player")
local isWarlock                = (playerClass == "WARLOCK")

local SOUL_SHARD_ID            = 6265
local get_soul_shard_data
local check_and_delete_excess_soul_shards
local execute_purge_candidate

-- Scratch tables for soul shard calculations (eliminates garbage churn)
local _shardAll       = {}
local _shardRegular   = {}
local _shardSpecialty = {}
local _shardEligible  = {}
local _shardDataResult = {
    allShards = _shardAll,
    regularShards = _shardRegular,
    specialtyShards = _shardSpecialty,
    totalCount = 0,
    maxShards = 20,
    preserveSoulBag = true,
    excessCount = 0,
    eligibleShards = _shardEligible,
}


-- Essential / Protected Item IDs (Never recommend dropping these)
local PROTECTED_ITEM_IDS = {
    -- Hearthstones & Teleportation Gadgets
    [6948]   = true, -- Hearthstone
    [140192] = true, -- Dalaran Hearthstone
    [110560] = true, -- Garrison Hearthstone
    [128353] = true, -- Admiral's Compass
    [141605] = true, -- Flight Master's Whistle

    -- Class Reagents & Consumable Tools
    [6265]   = true, -- Soul Shard (Warlock)
    [17030]  = true, -- Ankh (Shaman)
    [17057]  = true, -- Shiny Fish Scales (Shaman)
    [17058]  = true, -- Fish Oil (Shaman)
    [5140]   = true, -- Flash Powder (Rogue)
    [8924]   = true, -- Blinding Powder (Rogue)
    [5060]   = true, -- Thieves' Tools (Rogue)
    [17020]  = true, -- Arcane Powder (Mage)
    [17031]  = true, -- Rune of Teleportation (Mage)
    [17032]  = true, -- Rune of Portals (Mage)
    [17034]  = true, -- Wild Thornroot (Druid)
    [17035]  = true, -- Ironwood Seed (Druid)
    [17028]  = true, -- Sacred Candle (Priest)
    [17029]  = true, -- Holy Candle (Priest)
    [17033]  = true, -- Symbol of Divinity (Paladin)
    [21177]  = true, -- Symbol of Kings (Paladin)

    -- Profession Tools & Gadgets
    [5956]   = true, -- Blacksmith Hammer
    [2901]   = true, -- Mining Pick
    [7005]   = true, -- Skinning Knife
    [6256]   = true, -- Fishing Pole
    [4470]   = true, -- Simple Wood
    [4471]   = true, -- Flint and Tinder
    [6218]   = true, -- Copper Rod
    [6219]   = true, -- Silver Rod
    [6339]   = true, -- Golden Rod
    [11130]  = true, -- Truesilver Rod
    [11145]  = true, -- Arcanite Rod
    [22461]  = true, -- Fel Iron Rod
    [22462]  = true, -- Adamantite Rod
    [22463]  = true, -- Eternium Rod
    [9149]   = true, -- Philosopher's Stone
    [13503]  = true, -- Alchemist's Stone
    [4075]   = true, -- Arclight Spanner
    [4077]   = true, -- Gyromatic Micro-Adjustor
    [20815]  = true, -- Jeweler's Kit
    [20824]  = true, -- Simple Grinder
}

-- Runtime state
local promptFrame           = nil
local currentCandidates     = {}
local currentCandidateIndex = 1
local currentCandidate      = nil
local ignoredInSession      = {}
local isTestMode            = false
local scanTimer             = nil
local lastFreeSlots         = -1
local isEnabled             = true

-- ─────────────────────────────────────────────────────────────────────────────
--  Inventory Scanning & Candidate Analysis
-- ─────────────────────────────────────────────────────────────────────────────

--- Determines whether an equipped container is a standard, general-purpose inventory bag
--- (strictly excluding profession bags, herb/mining/gem/enchanting pouches, soul bags, quivers, ammo pouches, reagent bags)
--- @param bag number
--- @return boolean isRegular, number freeSlots
local function is_regular_inventory_bag(bag)
    local getNumFreeSlots = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
    local getNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots

    if bag == 0 then
        -- Bag 0 is always the primary backpack
        local freeSlots = getNumFreeSlots and getNumFreeSlots(0) or 0
        return true, freeSlots or 0
    end

    -- Strictly restrict to equipped character bags 1 to NUM_BAG_SLOTS (excludes keyring -2, bank bags, and retail reagent bag)
    if bag < 1 or bag > (_G.NUM_BAG_SLOTS or 4) then
        return false, 0
    end

    local numSlots = getNumSlots and getNumSlots(bag) or 0
    if not numSlots or numSlots == 0 then
        return false, 0
    end

    local freeSlots, bagFamily = getNumFreeSlots and getNumFreeSlots(bag)
    if not freeSlots then
        return false, 0
    end

    -- If bagFamily is non-zero, it is a specialty bag (e.g. soul bag, quiver, ammo, herb, mining, engineering)
    if bagFamily and bagFamily ~= 0 then
        return false, 0
    end

    -- Additional check: query the equipped container item itself
    local invID = (C_Container and C_Container.ContainerIDToInventoryID and C_Container.ContainerIDToInventoryID(bag))
        or (_G.ContainerIDToInventoryID and _G.ContainerIDToInventoryID(bag))
    if invID then
        local bagLink = _G.GetInventoryItemLink and _G.GetInventoryItemLink("player", invID)
        if bagLink then
            local itemFamily = _G.GetItemFamily and _G.GetItemFamily(bagLink)
            if itemFamily and itemFamily ~= 0 then
                return false, 0
            end
            if _G.IsInventoryItemProfessionBag and _G.IsInventoryItemProfessionBag("player", invID) then
                return false, 0
            end
        end
    end

    return true, freeSlots
end
triage.IsRegularInventoryBag = is_regular_inventory_bag

--- Counts total free slots across regular inventory bags (strictly ignoring specialty containers)
--- @return number freeSlots
local function get_num_free_regular_slots()
    local free = 0
    local maxBag = _G.NUM_BAG_SLOTS or 4
    for bag = 0, maxBag do
        local isRegular, freeSlots = is_regular_inventory_bag(bag)
        if isRegular then
            free = free + (freeSlots or 0)
        end
    end
    return free
end
triage.GetNumFreeRegularSlots = get_num_free_regular_slots

--- Checks whether an item is protected from deletion (Hearthstone, tools, quest items)
--- @param itemID number
--- @param itemLink string|nil
--- @param info table|nil
--- @return boolean isProtected
local function is_item_protected(itemID, itemLink, info)
    if not itemID then return true end
    if PROTECTED_ITEM_IDS[itemID] then return true end
    if ignoredInSession[itemID] then return true end

    -- Check if quest item, quest starter, or locked container
    if info and info.isQuestItem then return true end
    if info and info.hasLoot then return true end

    if itemLink or itemID then
        local _, _, _, _, _, _, _, _, _, _, _, classID, _, bindType = common.get_item_info(itemLink or itemID)
        if bindType == 4 then return true end -- Quest item bind
        -- Class 1 = Container (bags inside bags)
        if classID == 1 or (Enum and Enum.ItemClass and classID == Enum.ItemClass.Container) then
            return true
        end
        -- Class 11 = Quiver / Ammo Pouch
        if classID == 11 or (Enum and Enum.ItemClass and classID == Enum.ItemClass.Quiver) then
            return true
        end
        -- Class 12 = Quest Item
        if classID == 12 or (Enum and Enum.ItemClass and classID == Enum.ItemClass.Questitem) then
            return true
        end
        -- Class 13 = Key
        if classID == 13 or (Enum and Enum.ItemClass and classID == Enum.ItemClass.Key) then
            return true
        end
        -- Class 18 = Profession equipment / curios
        if classID == 18 or (Enum and Enum.ItemClass and classID == Enum.ItemClass.Profession) then
            return true
        end
    end

    return false
end

--- Collects and ranks discard candidates from regular bags 0 to 4 (ignoring specialty containers)
--- @param skipInventoryScan boolean|nil if true, skips grey and consumable scan (used when bag slots > threshold)
--- @return table candidates, string candidateType ("grey", "consumable", or "none")
local function find_candidates(skipInventoryScan)
    local greyCandidates = {}
    local consumableCandidates = {}

    local cfg = sfui.config.triage or {}
    local checkConsumables = (sfui.db and sfui.db.Get and sfui.db.Get("triage", "checkConsumables", cfg.checkConsumables ~= false))
    if checkConsumables == nil then checkConsumables = true end

    local protectFoodWater = (sfui.db and sfui.db.Get and sfui.db.Get("triage", "protectFoodWater", cfg.protectFoodWater ~= false))
    if protectFoodWater == nil then protectFoodWater = true end

    local playerLevel = UnitLevel("player") or 1
    local maxBag = _G.NUM_BAG_SLOTS or 4

    if not skipInventoryScan then
        for bag = 0, maxBag do
            local isRegular = is_regular_inventory_bag(bag)
            -- Only scan regular inventory containers (backpack bag 0 or normal bags)
            -- Discarding items from specialty bags (quiver, herb, mining, soul bag) does not free regular space
            if isRegular then
                local numSlots = GetContainerNumSlots and GetContainerNumSlots(bag) or 0
                for slot = 1, numSlots do
                    local itemID = GetContainerItemID and GetContainerItemID(bag, slot)
                    local itemLink = GetContainerItemLink and GetContainerItemLink(bag, slot)

                    if itemID and itemLink then
                        local rawInfo = GetContainerItemInfo and GetContainerItemInfo(bag, slot)
                        local info = (type(rawInfo) == "table") and rawInfo or nil
                        local isLocked = info and info.isLocked

                        if not isLocked and not is_item_protected(itemID, itemLink, info) then
                            local quality = info and info.quality
                            local stackCount = (info and info.stackCount) or 1
                            local icon = (info and info.iconFileID)

                            local name, _, itemQuality, _, itemMinLevel, _, _, _, _, itemTexture, itemSellPrice, classID, subClassID = common.get_item_info(itemLink)
                            quality = quality or itemQuality or 0
                            icon = icon or itemTexture

                            local sellPrice = (info and info.noValue) and 0 or (itemSellPrice or 0)
                            local totalValue = sellPrice * stackCount

                            -- Phase 1: Grey Quality Items (Quality 0)
                            if quality == 0 then
                                greyCandidates[#greyCandidates + 1] = {
                                    bag = bag,
                                    slot = slot,
                                    itemID = itemID,
                                    itemLink = itemLink,
                                    itemName = name or "junk item",
                                    icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
                                    quality = 0,
                                    stackCount = stackCount,
                                    sellPrice = sellPrice,
                                    totalValue = totalValue,
                                    category = "grey junk",
                                }
                            -- Phase 2: Consumables (Common/White Quality 1) - ONLY Food & Drink (subclass 5)
                            -- Life-saving potions (1), elixirs (2), flasks (3), and bandages (7) are strictly protected
                            elseif checkConsumables and quality == 1 then
                                local isConsumableClass = (classID == 0) or (Enum and Enum.ItemClass and classID == Enum.ItemClass.Consumable)
                                local isFoodDrink = (subClassID == 5) or (Enum and Enum.ItemConsumableSubclass and subClassID == Enum.ItemConsumableSubclass.Fooddrink)
                                local isExcludedSubclass = (subClassID == 1 or subClassID == 2 or subClassID == 3 or subClassID == 4 or subClassID == 7)
                                    or (Enum and Enum.ItemConsumableSubclass and (
                                        subClassID == Enum.ItemConsumableSubclass.Potion
                                        or subClassID == Enum.ItemConsumableSubclass.Elixir
                                        or subClassID == Enum.ItemConsumableSubclass.Flasksphials
                                        or subClassID == Enum.ItemConsumableSubclass.Bandage
                                    ))

                                if isConsumableClass and isFoodDrink and not isExcludedSubclass then
                                    local reqLevel = itemMinLevel or 0
                                    local levelDiff = math_max(0, playerLevel - reqLevel)
                                    local isOutdated = (playerLevel >= 15 and reqLevel <= 5)
                                        or (playerLevel >= 25 and reqLevel <= 15)
                                        or (playerLevel >= 35 and reqLevel <= 25)
                                        or (levelDiff >= 15)

                                    local isFood, isDrink, hasWellFed = false, false, false
                                    if sfui.items and sfui.items.get_food_drink_info then
                                        isFood, isDrink, hasWellFed = sfui.items.get_food_drink_info(bag, slot, itemID, itemLink)
                                    elseif sfui.items and sfui.items.is_buff_food then
                                        hasWellFed = sfui.items.is_buff_food(bag, slot, itemID, itemLink)
                                        isFood = true
                                    end

                                    local canSuggest = true
                                    if hasWellFed then
                                        -- Food WITH Well Fed grants stat buffs; protect when protectFoodWater is enabled
                                        if protectFoodWater then
                                            canSuggest = false
                                        end
                                    elseif isDrink and not isFood then
                                        -- Pure drink (water): protect level-appropriate mana water for mana-using classes
                                        local isManaUser = (playerClass ~= "WARRIOR" and playerClass ~= "ROGUE" and playerClass ~= "DEATHKNIGHT")
                                        if protectFoodWater and isManaUser and not isOutdated and (reqLevel >= playerLevel - 10) then
                                            canSuggest = false
                                        end
                                    else
                                        -- Food WITHOUT Well Fed: eligible for bag triage discard
                                        -- Even if player is current level, plain food without well fed can be safely discarded
                                        canSuggest = true
                                    end

                                    if canSuggest then
                                        local category
                                        if isOutdated then
                                            category = isFood and "outdated food" or "outdated drink"
                                        elseif not hasWellFed and isFood then
                                            category = "food (no well fed)"
                                        elseif hasWellFed then
                                            category = "buff food"
                                        else
                                            category = "low-value consumable"
                                        end

                                        consumableCandidates[#consumableCandidates + 1] = {
                                            bag = bag,
                                            slot = slot,
                                            itemID = itemID,
                                            itemLink = itemLink,
                                            itemName = name or "food/water",
                                            icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
                                            quality = 1,
                                            stackCount = stackCount,
                                            sellPrice = sellPrice,
                                            totalValue = totalValue,
                                            reqLevel = reqLevel,
                                            isOutdated = isOutdated,
                                            hasWellFed = hasWellFed,
                                            isFoodWithoutWellFed = (isFood and not hasWellFed),
                                            category = category,
                                        }
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Check if prompt-mode excess soul shards exist (Warlock only)
    local soulShardCandidate = nil
    local deleteSoulShards = isWarlock and (sfui.db and sfui.db.Get and sfui.db.Get("triage", "deleteSoulShards", cfg.deleteSoulShards or false))
    if deleteSoulShards and not ignoredInSession[SOUL_SHARD_ID] and get_soul_shard_data then
        local sData = get_soul_shard_data()
        if sData and sData.excessCount > 0 and sData.eligibleShards and #sData.eligibleShards > 0 then
            local targetShard = sData.eligibleShards[1]

            soulShardCandidate = {
                isSoulShardPurge = true,
                bag = targetShard.bag,
                slot = targetShard.slot,
                itemID = SOUL_SHARD_ID,
                itemName = "Soul Shard",
                itemLink = targetShard.itemLink or "item:6265",
                displayName = string_format("|cff9933ffSoul Shards|r (|cffffffff%d excess|r)", sData.excessCount),
                icon = 134075,
                stackCount = 1,
                sellPrice = 0,
                totalValue = 0,
                category = "excess soul shards",
                deleteButtonText = "purge",
                totalCount = sData.totalCount,
                maxShards = sData.maxShards,
                locationText = sData.preserveSoulBag and string_format("pruning regular bag spillover (%d/%d)", sData.totalCount, sData.maxShards) or string_format("pruning %d excess shards (%d/%d)", sData.excessCount, sData.totalCount, sData.maxShards),
                onKeep = function()
                    ignoredInSession[SOUL_SHARD_ID] = true
                    common.print("|cffaaaaaasfui triage:|r keeping soul shards for this session.")
                end,
            }
        end
    end

    -- Sort grey candidates (lowest total value, lowest unit price, smallest stack)
    if #greyCandidates > 0 then
        table_sort(greyCandidates, function(a, b)
            if a.totalValue ~= b.totalValue then
                return a.totalValue < b.totalValue
            end
            if a.sellPrice ~= b.sellPrice then
                return a.sellPrice < b.sellPrice
            end
            if a.stackCount ~= b.stackCount then
                return a.stackCount < b.stackCount
            end
            if a.bag ~= b.bag then
                return a.bag > b.bag
            end
            return a.slot > b.slot
        end)
    end

    -- Sort consumable candidates:
    -- 1. Outdated consumables first
    -- 2. Food items without well fed next
    -- 3. Lowest total value, lowest unit price, smallest stack
    if #consumableCandidates > 0 then
        table_sort(consumableCandidates, function(a, b)
            if a.isOutdated ~= b.isOutdated then
                return a.isOutdated
            end
            if a.isFoodWithoutWellFed ~= b.isFoodWithoutWellFed then
                return a.isFoodWithoutWellFed
            end
            if a.totalValue ~= b.totalValue then
                return a.totalValue < b.totalValue
            end
            if a.sellPrice ~= b.sellPrice then
                return a.sellPrice < b.sellPrice
            end
            if a.stackCount ~= b.stackCount then
                return a.stackCount < b.stackCount
            end
            return a.slot > b.slot
        end)
    end

    -- Assemble all candidates so triage cycles through soul shards, greys, and food items without well fed
    local allCandidates = {}

    -- 1. Soul Shards (Warlock excess)
    if soulShardCandidate then
        allCandidates[#allCandidates + 1] = soulShardCandidate
    end

    -- 2. Grey junk items
    for i = 1, #greyCandidates do
        allCandidates[#allCandidates + 1] = greyCandidates[i]
    end

    -- 3. Consumable candidates (outdated food/drink, food items without well fed)
    for i = 1, #consumableCandidates do
        allCandidates[#allCandidates + 1] = consumableCandidates[i]
    end

    if #allCandidates > 0 then
        local primaryType = "grey"
        if soulShardCandidate and #allCandidates == 1 then
            primaryType = "soulshard"
        elseif #greyCandidates == 0 and #consumableCandidates > 0 then
            primaryType = "consumable"
        end
        return allCandidates, primaryType
    end

    return {}, "none"
end
triage.FindCandidates = find_candidates

-- ─────────────────────────────────────────────────────────────────────────────
--  Confirmation Prompt UI
-- ─────────────────────────────────────────────────────────────────────────────

local function refresh_triage_frame_levels(f)
    if not f then return end
    local base = f:GetFrameLevel() or 100
    if sfui.theme and sfui.theme.ElevateWindowContents then
        sfui.theme.ElevateWindowContents(f)
    end
    if f.headerFrame then f.headerFrame:SetFrameLevel(base + 15) end
    if f.contentFrame then f.contentFrame:SetFrameLevel(base + 10) end
    if f.iconFrame then f.iconFrame:SetFrameLevel(base + 12) end
    local actBtn = f.deleteBtn or f.dropBtn
    if actBtn then actBtn:SetFrameLevel(base + 15) end
    if f.nextBtn then f.nextBtn:SetFrameLevel(base + 15) end
    if f.keepBtn then f.keepBtn:SetFrameLevel(base + 15) end
    if f.closeBtn then f.closeBtn:SetFrameLevel(base + 20) end
end

local function apply_triage_theme(f, pal)
    if not f then return end
    pal = pal or (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()) or {}
    refresh_triage_frame_levels(f)

    if f.title and pal.headerColor then
        f.title:SetTextColor(pal.headerColor[1], pal.headerColor[2], pal.headerColor[3], 1)
    end

    if f.slotText and pal.dimTextColor then
        f.slotText:SetTextColor(pal.dimTextColor[1], pal.dimTextColor[2], pal.dimTextColor[3], 1)
    end

    if f.iconFrame and sfui.theme and sfui.theme.ApplyCardStyle then
        sfui.theme.ApplyCardStyle(f.iconFrame, 2)
    end

    if sfui.theme and sfui.theme.ApplyButtonStyle then
        local actBtn = f.deleteBtn or f.dropBtn
        if actBtn then sfui.theme.ApplyButtonStyle(actBtn, false) end
        if f.nextBtn then sfui.theme.ApplyButtonStyle(f.nextBtn, false) end
        if f.keepBtn then sfui.theme.ApplyButtonStyle(f.keepBtn, false) end
    end

    if f.closeBtn and sfui.theme and sfui.theme.ApplyCloseButtonStyle then
        sfui.theme.ApplyCloseButtonStyle(f.closeBtn)
    end
end

local function create_triage_prompt()
    if promptFrame then return promptFrame end

    local f = CreateFrame("Frame", "SfuiBagTriagePrompt", UIParent, "BackdropTemplate")
    f:SetSize(280, 118)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(100)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnMouseWheel", function(self, delta)
        if #currentCandidates <= 1 then return end
        if delta < 0 then
            currentCandidateIndex = (currentCandidateIndex % #currentCandidates) + 1
        else
            currentCandidateIndex = (currentCandidateIndex - 2 + #currentCandidates) % #currentCandidates + 1
        end
        triage.DisplayCandidate(currentCandidates[currentCandidateIndex])
    end)

    -- Clean fallback backdrop with 1px border
    local pScale = sfui.pixelScale or 1
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = pScale,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    f:SetBackdropColor(0.06, 0.06, 0.06, 0.96)
    f:SetBackdropBorderColor(0, 0, 0, 1)

    -- Apply theme styling (Camelot sculpted bronze, NineSlice, or Modern flat)
    if sfui.theme and sfui.theme.ApplyWindowStyle then
        sfui.theme.ApplyWindowStyle(f, { cornerBrackets = true })
    end
    if sfui.theme and sfui.theme.RegisterWindow then
        sfui.theme.RegisterWindow(f, apply_triage_theme, { cornerBrackets = true })
    end
    f:HookScript("OnShow", refresh_triage_frame_levels)
    f:HookScript("OnHide", function()
        currentCandidate = nil
    end)

    -- Drag repositioning
    f:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then
            self:StartMoving()
        end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local pt, _, relPt, x, y = self:GetPoint()
        if SfuiDB then
            SfuiDB.triagePos = { point = pt or "BOTTOM", relPoint = relPt or "BOTTOM", x = x or 0, y = y or 220 }
        end
    end)

    -- Position restoration
    local savedPos = SfuiDB and SfuiDB.triagePos
    if savedPos and savedPos.point and savedPos.x and savedPos.y then
        f:SetPoint(savedPos.point, UIParent, savedPos.relPoint or savedPos.point, savedPos.x, savedPos.y)
    else
        local defPos = (sfui.config.triage and sfui.config.triage.pos) or { point = "BOTTOM", x = 0, y = 220 }
        f:SetPoint(defPos.point, UIParent, defPos.relativePoint or defPos.point, defPos.x, defPos.y)
    end

    -- Elevated header frame & title
    local headerFrame = CreateFrame("Frame", nil, f)
    headerFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    headerFrame:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    headerFrame:SetHeight(26)
    headerFrame:SetFrameLevel((f:GetFrameLevel() or 100) + 15)
    headerFrame:EnableMouse(false)
    f.headerFrame = headerFrame

    local pal = (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()) or {}
    local headerR, headerG, headerB = 1, 0.82, 0
    if pal.headerColor then
        headerR, headerG, headerB = pal.headerColor[1], pal.headerColor[2], pal.headerColor[3]
    end

    local title = headerFrame:CreateFontString(nil, "OVERLAY", sfui.config.font_small or "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetTextColor(headerR, headerG, headerB, 1)
    title:SetText("bag triage")
    f.title = title

    local statusText = headerFrame:CreateFontString(nil, "OVERLAY", sfui.config.font_small or "GameFontHighlightSmall")
    statusText:SetPoint("LEFT", title, "RIGHT", 6, 0)
    statusText:SetTextColor(0.8, 0.8, 0.8, 1)
    f.statusText = statusText

    -- Close button [x]
    local closeBtn = common.create_close_button(f, function() f:Hide() end, 18)
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
    closeBtn:SetFrameLevel((f:GetFrameLevel() or 100) + 20)
    f.closeBtn = closeBtn

    -- Content frame (elevated above theme background/border layers)
    local content = CreateFrame("Frame", nil, f)
    content:SetAllPoints(f)
    content:SetFrameLevel((f:GetFrameLevel() or 100) + 10)
    content:EnableMouse(false)
    f.contentFrame = content

    -- Item icon container
    local iconFrame = CreateFrame("Button", nil, content, "BackdropTemplate")
    iconFrame:SetSize(36, 36)
    iconFrame:SetPoint("TOPLEFT", 10, -28)
    iconFrame:SetFrameLevel((f:GetFrameLevel() or 100) + 12)
    if sfui.theme and sfui.theme.ApplyCardStyle then
        sfui.theme.ApplyCardStyle(iconFrame, 2)
    else
        iconFrame:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets   = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        iconFrame:SetBackdropColor(0.04, 0.04, 0.04, 1)
        iconFrame:SetBackdropBorderColor(0, 0, 0, 1)
    end
    f.iconFrame = iconFrame

    local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
    iconTex:SetPoint("TOPLEFT", 2, -2)
    iconTex:SetPoint("BOTTOMRIGHT", -2, 2)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.iconTex = iconTex

    local countText = iconFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    countText:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -2, 2)
    countText:SetTextColor(1, 1, 1, 1)
    f.countText = countText

    -- Tooltip on icon hover
    iconFrame:SetScript("OnEnter", function(self)
        local tip = sfui.tooltip or _G.SfuiGameTooltip
        if not tip or not currentCandidate then return end
        tip:SetOwner(self, "ANCHOR_RIGHT")
        if currentCandidate.isSoulShardPurge then
            tip:SetHyperlink("item:6265")
        elseif currentCandidate.bag and currentCandidate.slot and not isTestMode then
            tip:SetBagItem(currentCandidate.bag, currentCandidate.slot)
        else
            tip:SetHyperlink(currentCandidate.itemLink or "item:4865")
        end
        tip:Show()
    end)
    iconFrame:SetScript("OnLeave", function()
        local tip = sfui.tooltip or _G.SfuiGameTooltip
        if tip and tip:IsShown() then
            tip:Hide()
        end
    end)

    -- Item details labels
    local nameText = content:CreateFontString(nil, "OVERLAY", sfui.config.font or "GameFontNormal")
    nameText:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 8, 0)
    nameText:SetPoint("RIGHT", content, "RIGHT", -10, 0)
    nameText:SetJustifyH("LEFT")
    f.nameText = nameText

    local infoText = content:CreateFontString(nil, "OVERLAY", sfui.config.font_small or "GameFontHighlightSmall")
    infoText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -3)
    infoText:SetPoint("RIGHT", content, "RIGHT", -10, 0)
    infoText:SetJustifyH("LEFT")
    infoText:SetTextColor(0.7, 0.7, 0.7, 1)
    f.infoText = infoText

    local dimR, dimG, dimB = 0.5, 0.5, 0.5
    if pal.dimTextColor then
        dimR, dimG, dimB = pal.dimTextColor[1], pal.dimTextColor[2], pal.dimTextColor[3]
    end

    local slotText = content:CreateFontString(nil, "OVERLAY", sfui.config.font_small or "GameFontHighlightSmall")
    slotText:SetPoint("TOPLEFT", infoText, "BOTTOMLEFT", 0, -2)
    slotText:SetJustifyH("LEFT")
    slotText:SetTextColor(dimR, dimG, dimB, 1)
    f.slotText = slotText

    -- ── Action Buttons ──
    local CreateFlatButton = common.create_flat_button

    -- [delete] action button (instant deletion on click, also clicked by class utility keybind)
    local deleteBtn = CreateFrame("Button", "SfuiTriageDeleteBtn", f, "BackdropTemplate")
    deleteBtn:SetSize(68, 20)
    deleteBtn:SetPoint("BOTTOMLEFT", 10, 8)
    deleteBtn:SetFrameLevel((f:GetFrameLevel() or 100) + 15)
    deleteBtn:SetNormalFontObject("GameFontHighlightSmall")
    deleteBtn:SetText("delete")
    local dfs = deleteBtn:GetFontString()
    if dfs then
        local fontFile = (sfui.config and sfui.config.fontFile) or "Fonts\\FRIZQT__.TTF"
        dfs:SetFont(fontFile, 11, "")
        dfs:SetTextColor(1, 1, 1, 1)
    end
    if sfui.theme and sfui.theme.ApplyButtonStyle then
        sfui.theme.ApplyButtonStyle(deleteBtn, false)
        sfui.theme.RegisterButton(deleteBtn, false)
    end
    _G.SfuiTriageDeleteBtn = deleteBtn

    deleteBtn:RegisterForClicks("AnyUp", "AnyDown")
    deleteBtn:SetScript("OnClick", function(self, button, down)
        if down == false and (GetTime() - lastPurgeSuccessTime) < 0.45 then
            return
        end
        if execute_purge_candidate then
            execute_purge_candidate(currentCandidate, down)
        end
    end)
    f.deleteBtn = deleteBtn
    f.dropBtn = deleteBtn -- alias for theme engine and backwards compatibility

    -- [next candidate] button
    local nextBtn = CreateFlatButton(f, "next", 64, 20)
    nextBtn:SetPoint("LEFT", deleteBtn, "RIGHT", 6, 0)
    nextBtn:SetFrameLevel((f:GetFrameLevel() or 100) + 15)
    nextBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    nextBtn:SetScript("OnClick", function(self, button)
        if #currentCandidates <= 1 then return end
        if button == "RightButton" then
            currentCandidateIndex = (currentCandidateIndex - 2 + #currentCandidates) % #currentCandidates + 1
        else
            currentCandidateIndex = (currentCandidateIndex % #currentCandidates) + 1
        end
        triage.DisplayCandidate(currentCandidates[currentCandidateIndex])
    end)
    f.nextBtn = nextBtn

    -- [keep] button
    local keepBtn = CreateFlatButton(f, "keep", 64, 20)
    keepBtn:SetPoint("LEFT", nextBtn, "RIGHT", 6, 0)
    keepBtn:SetFrameLevel((f:GetFrameLevel() or 100) + 15)
    keepBtn:SetScript("OnClick", function()
        if currentCandidate and currentCandidate.onKeep then
            currentCandidate.onKeep()
        elseif currentCandidate and currentCandidate.itemID then
            ignoredInSession[currentCandidate.itemID] = true
            common.print(string_format("|cffaaaaaasfui triage:|r keeping %s for this session.", currentCandidate.itemLink or currentCandidate.itemName))
        end
        f:Hide()
    end)
    f.keepBtn = keepBtn

    f:Hide()
    promptFrame = f
    return f
end

--- Updates prompt contents with a candidate's information
--- @param cand table
function triage.DisplayCandidate(cand)
    if not cand then return end
    currentCandidate = cand

    local f = create_triage_prompt()
    local free = get_num_free_regular_slots()

    if isTestMode then
        f.statusText:SetText("|cff00ffff[test preview]|r")
    elseif cand.isSoulShardPurge then
        f.statusText:SetText(string_format("|cff9933ffexcess shards (%d/%d)|r", cand.totalCount or 0, cand.maxShards or 0))
    elseif free == 0 then
        f.statusText:SetText("|cffff4444bags full (0 free)|r")
    else
        f.statusText:SetText(string_format("|cffffcc00bags almost full (%d free)|r", free))
    end

    f.iconTex:SetTexture(cand.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    if cand.stackCount and cand.stackCount > 1 then
        f.countText:SetText(tostring(cand.stackCount))
        f.countText:Show()
    else
        f.countText:SetText("")
        f.countText:Hide()
    end

    if cand.isSoulShardPurge then
        f.nameText:SetText(cand.displayName or cand.itemLink or cand.itemName)
        f.infoText:SetText(string_format("retains %d shards |cff888888(%s)|r", cand.maxShards or 20, cand.category or "soul shards"))
        f.slotText:SetText(cand.locationText or "pruning regular bag spillover")
    else
        f.nameText:SetText(cand.itemLink or cand.itemName)

        local valStr = (cand.totalValue and cand.totalValue > 0)
            and common.SafeGetCoinTextureString(cand.totalValue)
            or "0c (no sell value)"
        f.infoText:SetText(string_format("value: %s |cff888888(%s)|r", valStr, cand.category or "junk"))

        if cand.bag and cand.slot then
            f.slotText:SetText(string_format("location: bag %d, slot %d", cand.bag + 1, cand.slot))
        else
            f.slotText:SetText("")
        end
    end

    local actBtn = f.deleteBtn or f.dropBtn
    if actBtn then
        actBtn:SetText(cand.deleteButtonText or "delete")
    end

    if #currentCandidates > 1 then
        f.nextBtn:SetText(string_format("next (%d/%d)", currentCandidateIndex, #currentCandidates))
        f.nextBtn:Enable()
        f.nextBtn:SetAlpha(1.0)
    else
        f.nextBtn:SetText("next")
        f.nextBtn:Disable()
        f.nextBtn:SetAlpha(0.4)
    end

    f:Show()

    local cfg = sfui.config.triage or {}
    local soundAlert = (sfui.db and sfui.db.Get and sfui.db.Get("triage", "soundAlert", cfg.soundAlert ~= false))
    if soundAlert ~= false and PlaySound and not isTestMode then
        PlaySound(SOUNDKIT.RAID_WARNING or 8959)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Automated Soul Shard Pruning (Opt-In)
-- ─────────────────────────────────────────────────────────────────────────────



--- Check if cursor is actively being used by player (moving item, spell targeting, etc.)
local function is_cursor_busy()
    if CursorHasItem and CursorHasItem() then
        return true
    end
    if SpellIsTargeting and SpellIsTargeting() then
        return true
    end
    if GetCursorInfo and GetCursorInfo() ~= nil then
        return true
    end
    return false
end

--- Check if player is busy with actions that should not be interrupted
local function is_player_busy()
    if sfui.common.is_in_combat() or InCombatLockdown() then
        return true
    end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
        return true
    end
    if UnitChannelInfo and UnitChannelInfo("player") then
        return true
    end
    if UnitCastingInfo and UnitCastingInfo("player") then
        return true
    end
    if _G.MerchantFrame and _G.MerchantFrame:IsShown() then
        return true
    end
    if _G.BankFrame and _G.BankFrame:IsShown() then
        return true
    end
    if _G.TradeFrame and _G.TradeFrame:IsShown() then
        return true
    end
    if _G.MailFrame and _G.MailFrame:IsShown() then
        return true
    end
    return false
end

--- Check if player is in combat, dead, or actively casting/trading
local function is_player_combat_or_dead()
    if sfui.common.is_in_combat() or InCombatLockdown() then
        return true
    end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
        return true
    end
    if UnitChannelInfo and UnitChannelInfo("player") then
        return true
    end
    if UnitCastingInfo and UnitCastingInfo("player") then
        return true
    end
    if _G.TradeFrame and _G.TradeFrame:IsShown() then
        return true
    end
    return false
end

--- Retrieves the itemID of a specific bag and slot with multi-API fallbacks
--- @param bag number
--- @param slot number
--- @return number|nil itemID
local function get_slot_item_id(bag, slot)
    local id = (C_Container and C_Container.GetContainerItemID and C_Container.GetContainerItemID(bag, slot))
        or (GetContainerItemID and GetContainerItemID(bag, slot))
    if id then return id end
    local getInfo = (C_Container and C_Container.GetContainerItemInfo) or GetContainerItemInfo
    if getInfo then
        local rawInfo = getInfo(bag, slot)
        if type(rawInfo) == "table" and rawInfo.itemID then
            return rawInfo.itemID
        end
    end
    local getLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
    if getLink then
        local link = getLink(bag, slot)
        if link then
            local parsedID = link:match("item:(%d+)")
            if parsedID then return tonumber(parsedID) end
        end
    end
    return nil
end

--- Scans all bags and categorizes soul shards into regular spillover and specialty soul bag slots.
--- @return table data
get_soul_shard_data = function()
    if not isWarlock then
        _shardDataResult.totalCount = 0
        _shardDataResult.excessCount = 0
        wipe(_shardDataResult.eligibleShards)
        return _shardDataResult
    end

    local cfg = sfui.config.triage or {}
    local maxShards = (sfui.db and sfui.db.Get and sfui.db.Get("triage", "maxSoulShards", cfg.maxSoulShards or 20))
    if maxShards == nil then maxShards = (cfg.maxSoulShards or 20) end
    maxShards = tonumber(maxShards) or 20
    if maxShards < 0 then maxShards = 0 end

    local preserveSoulBag = (sfui.db and sfui.db.Get and sfui.db.Get("triage", "preserveSoulBag", cfg.preserveSoulBag ~= false))
    if preserveSoulBag == nil then preserveSoulBag = true end

    wipe(_shardAll)
    wipe(_shardRegular)
    wipe(_shardSpecialty)
    wipe(_shardEligible)

    local getNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local getItemInfo = (C_Container and C_Container.GetContainerItemInfo) or GetContainerItemInfo
    local getItemLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink

    local maxBag = _G.NUM_BAG_SLOTS or 4
    for bag = 0, maxBag do
        local numSlots = (getNumSlots and getNumSlots(bag)) or 0
        if numSlots > 0 then
            local isRegular = is_regular_inventory_bag(bag)
            for slot = 1, numSlots do
                local itemID = get_slot_item_id(bag, slot)
                if itemID == SOUL_SHARD_ID then
                    local rawInfo = getItemInfo and getItemInfo(bag, slot)
                    local info = (type(rawInfo) == "table") and rawInfo or nil
                    local item = {
                        bag = bag,
                        slot = slot,
                        isRegular = isRegular,
                        isLocked = (info and info.isLocked) or false,
                        itemLink = (info and info.hyperlink) or (getItemLink and getItemLink(bag, slot)) or "soul shard",
                    }
                    table_insert(_shardAll, item)
                    if isRegular then
                        table_insert(_shardRegular, item)
                    else
                        table_insert(_shardSpecialty, item)
                    end
                end
            end
        end
    end

    local totalCount = #_shardAll
    local totalExcess = totalCount - maxShards
    if totalExcess < 0 then totalExcess = 0 end

    if totalExcess > 0 then
        if preserveSoulBag then
            -- Only regular bag spillover is eligible for deletion
            -- Sort regular shards: higher bag index first, then higher slot index (end of bags first)
            for _, item in ipairs(_shardRegular) do
                -- Exclude locked slots so rapid purging never selects a slot currently pending deletion
                if not item.isLocked then
                    table_insert(_shardEligible, item)
                end
            end
            table_sort(_shardEligible, function(a, b)
                if a.bag ~= b.bag then return a.bag > b.bag end
                return a.slot > b.slot
            end)
            while #_shardEligible > totalExcess do
                table.remove(_shardEligible)
            end
        else
            -- All shards eligible, regular inventory bags pruned before dedicated soul bags
            for _, item in ipairs(_shardAll) do
                if not item.isLocked then
                    table_insert(_shardEligible, item)
                end
            end
            table_sort(_shardEligible, function(a, b)
                if a.isRegular ~= b.isRegular then
                    return a.isRegular -- true before false
                end
                if a.bag ~= b.bag then
                    return a.bag > b.bag
                end
                return a.slot > b.slot
            end)
            while #_shardEligible > totalExcess do
                table.remove(_shardEligible)
            end
        end
    end

    _shardDataResult.totalCount = totalCount
    _shardDataResult.maxShards = maxShards
    _shardDataResult.preserveSoulBag = preserveSoulBag
    _shardDataResult.excessCount = #_shardEligible
    return _shardDataResult
end

local lastNoExcessNoticeTime = 0
local lastPurgeSuccessTime   = 0

--- Purges the active triage candidate (soul shard or item) or next excess soul shard.
--- This is the core function of the purge button, shared across the UI prompt, keybind, and macros.
--- @param cand table|nil optional candidate; defaults to currentCandidate or next excess soul shard
--- @param isDown boolean|nil optional flag indicating if click originated from key-down
--- @return boolean success
execute_purge_candidate = function(cand, isDown)
    if is_player_combat_or_dead() then return false end

    -- Guard non-table arguments (e.g. PurgeSoulShards(true) called by old callers)
    if type(cand) ~= "table" then
        cand = nil
    end

    local now = GetTime and GetTime() or 0

    -- Hardware key-up guard: ignore key-up release if a purge was already triggered on key-down
    if isDown == false and (now - lastPurgeSuccessTime) < 0.45 then
        return false
    end

    if (now - lastPurgeSuccessTime) < 0.30 then
        return false
    end

    -- Safety: never touch cursor if player is moving an item or targeting a spell
    if is_cursor_busy() then
        return false
    end

    -- Active prompt candidate or passed candidate
    cand = cand or currentCandidate

    -- If no candidate currently active, check if excess soul shards exist to purge
    if not cand and isWarlock and get_soul_shard_data then
        local sData = get_soul_shard_data()
        if sData and sData.excessCount > 0 and sData.eligibleShards and #sData.eligibleShards > 0 then
            local targetShard = sData.eligibleShards[1]
            cand = {
                isSoulShardPurge = true,
                bag = targetShard.bag,
                slot = targetShard.slot,
                itemID = SOUL_SHARD_ID,
                itemName = "Soul Shard",
                itemLink = targetShard.itemLink or "item:6265",
                displayName = string_format("|cff9933ffSoul Shards|r (|cffffffff%d excess|r)", sData.excessCount),
                totalCount = sData.totalCount,
                maxShards = sData.maxShards,
            }
        end
    end

    if not cand then
        local now = GetTime and GetTime() or 0
        if (now - lastNoExcessNoticeTime) > 1.5 then
            lastNoExcessNoticeTime = now
            if get_soul_shard_data then
                local data = get_soul_shard_data()
                if data and data.totalCount and data.maxShards and data.totalCount > data.maxShards and data.preserveSoulBag then
                    common.print(string_format("|cffaaaaaasfui triage:|r %d shards found (%d excess), but preserved in dedicated soul bag (uncheck 'preserve soul bag slots' to delete from soul bag).", data.totalCount, data.totalCount - data.maxShards))
                elseif data and data.totalCount and data.maxShards then
                    common.print(string_format("|cffaaaaaasfui triage:|r %d soul shard(s) (max %d), none to purge.", data.totalCount, data.maxShards))
                else
                    common.print("|cffaaaaaasfui triage:|r no excess soul shards to delete.")
                end
            end
        end
        if promptFrame and promptFrame:IsShown() then
            promptFrame:Hide()
        end
        return false
    end

    if cand.onDelete then
        if promptFrame and promptFrame:IsShown() then
            promptFrame:Hide()
        end
        cand.onDelete()
        return true
    end

    if isTestMode then
        common.print(string_format("|cff00ffffsfui triage:|r [test preview] deleted %s simulated.", cand.itemLink or cand.itemName))
        if promptFrame and promptFrame:IsShown() then
            promptFrame:Hide()
        end
        isTestMode = false
        return true
    end

    -- Race condition guard: verify slot still holds the exact candidate item
    local curID = get_slot_item_id and get_slot_item_id(cand.bag, cand.slot)
    if not curID and GetContainerItemID then
        curID = GetContainerItemID(cand.bag, cand.slot)
    end
    if curID ~= cand.itemID then
        common.print("|cffff8800sfui triage:|r item moved or changed, cancel delete.")
        if promptFrame and promptFrame:IsShown() then
            promptFrame:Hide()
        end
        triage.EvaluateTriage()
        return false
    end

    -- Verify item is not locked by bag operations or server activity
    local getItemInfo = (C_Container and C_Container.GetContainerItemInfo) or GetContainerItemInfo
    local rawInfo = getItemInfo and getItemInfo(cand.bag, cand.slot)
    local info = (type(rawInfo) == "table") and rawInfo or nil
    if info and info.isLocked then
        if (now - lastPurgeSuccessTime) > 0.8 then
            common.print("|cffff8800sfui triage:|r item is currently locked, try again in a moment.")
        end
        return false
    end

    -- Safety: ensure cursor is clear before picking up
    if ClearCursor then ClearCursor() end

    local doPickup = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem or _G.PickupContainerItem
    local doDelete = DeleteCursorItem or _G.DeleteCursorItem
    local doClear  = ClearCursor or _G.ClearCursor

    if doPickup then
        doPickup(cand.bag, cand.slot)
    end

    if doDelete then
        doDelete()
    end

    if doClear then
        doClear()
    end

    lastPurgeSuccessTime = GetTime and GetTime() or 0

    -- Cursor safety cleanup: if native popup is not shown and item is still on cursor, clear it
    if CursorHasItem and CursorHasItem() then
        C_Timer.After(0.2, function()
            if CursorHasItem and CursorHasItem() then
                local popupVisible = (_G.StaticPopup_Visible and (_G.StaticPopup_Visible("DELETE_ITEM") or _G.StaticPopup_Visible("DELETE_GOOD_ITEM")))
                if not popupVisible then
                    ClearCursor()
                end
            end
        end)
    end

    if cand.isSoulShardPurge then
        local data = get_soul_shard_data()
        local remaining = data and data.totalCount or 0
        local cfg = sfui.config.triage or {}
        local chatSummary = (sfui.db and sfui.db.Get and sfui.db.Get("triage", "soulShardChat", cfg.soulShardChat ~= false))
        if chatSummary ~= false and common and common.print then
            common.print(string_format("|cff00ffffsfui triage:|r deleted 1 excess soul shard (%d retained).", remaining))
        end
    else
        local coinStr = (cand.totalValue and cand.totalValue > 0)
            and common.SafeGetCoinTextureString(cand.totalValue)
            or "0c"
        common.print(string_format("|cff00ffffsfui triage:|r deleted %s%s (%s).",
            cand.itemLink or cand.itemName,
            (cand.stackCount and cand.stackCount > 1) and (" x" .. cand.stackCount) or "",
            coinStr
        ))
    end

    if PlaySound then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
    end

    if promptFrame and promptFrame:IsShown() then
        promptFrame:Hide()
    end

    -- Re-evaluate after 0.4s once bag updates settle
    C_Timer.After(0.4, function()
        triage.EvaluateTriage()
    end)

    return true
end
triage.ExecutePurge = execute_purge_candidate
triage.PurgeCandidate = execute_purge_candidate
triage.PurgeSingleExcessSoulShard = execute_purge_candidate
triage.PurgeSoulShards = execute_purge_candidate
triage.PickUpExcessSoulShard = execute_purge_candidate

--- Checks soul shard counts and triggers triage evaluation if excess exists.
check_and_delete_excess_soul_shards = function()
    if not isEnabled then return end
    if is_player_busy() then return end

    local cfg = sfui.config.triage or {}
    local deleteEnabled = (sfui.db and sfui.db.Get and sfui.db.Get("triage", "deleteSoulShards", cfg.deleteSoulShards or false))
    if not deleteEnabled then return end

    local data = get_soul_shard_data()
    if data.excessCount <= 0 then
        if promptFrame and promptFrame:IsShown() and currentCandidate and currentCandidate.isSoulShardPurge then
            promptFrame:Hide()
        end
        return
    end

    triage.EvaluateTriage()
end
triage.CheckSoulShards = check_and_delete_excess_soul_shards

-- Macro-clickable / keybind fallback button to purge shards via /click SfuiPurgeSoulShards
local purgeShardsBtn = _G.SfuiPurgeSoulShards or _G.CreateFrame("Button", "SfuiPurgeSoulShards", UIParent)
purgeShardsBtn:RegisterForClicks("AnyUp", "AnyDown")
purgeShardsBtn:SetScript("OnClick", function(self, button, down)
    if down == false and (GetTime() - lastPurgeSuccessTime) < 0.45 then
        return
    end
    if promptFrame and promptFrame:IsShown() and promptFrame.deleteBtn then
        promptFrame.deleteBtn:Click(button, down)
    else
        execute_purge_candidate(nil, down)
    end
end)
_G.SfuiPurgeSoulShards = purgeShardsBtn

-- ─────────────────────────────────────────────────────────────────────────────
--  Triage Evaluation Loop
-- ─────────────────────────────────────────────────────────────────────────────

--- Evaluates bag space and displays the triage prompt if free slots <= threshold
function triage.EvaluateTriage()
    if not isEnabled then return end
    if isTestMode then return end

    -- Safety: never prompt during combat
    if sfui.common.is_in_combat() or InCombatLockdown() then
        return
    end

    -- Safety: player dead/ghost
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
        if promptFrame and promptFrame:IsShown() then
            promptFrame:Hide()
        end
        return
    end

    -- Safety: at merchant window (selling items is preferred over dropping)
    if _G.MerchantFrame and _G.MerchantFrame:IsShown() then
        if promptFrame and promptFrame:IsShown() then
            promptFrame:Hide()
        end
        return
    end

    local cfg = sfui.config.triage or {}
    local defThresh = (cfg.threshold ~= nil) and cfg.threshold or 1
    local threshold = (sfui.db and sfui.db.Get and sfui.db.Get("triage", "threshold", defThresh))
    if threshold == nil then threshold = defThresh end
    threshold = tonumber(threshold) or defThresh
    local free = get_num_free_regular_slots()
    lastFreeSlots = free

    -- Fast short-circuit: if regular inventory has plenty of free slots
    if free > threshold then
        -- Only warlock with excess shard deletion enabled could possibly need a triage prompt
        local deleteSoulShards = isWarlock and (sfui.db and sfui.db.Get and sfui.db.Get("triage", "deleteSoulShards", cfg.deleteSoulShards or false))
        if not deleteSoulShards or ignoredInSession[SOUL_SHARD_ID] then
            if promptFrame and promptFrame:IsShown() then
                promptFrame:Hide()
            end
            return
        end

        -- Check soul shards only (skips heavy 140-slot grey and consumable scan)
        local sData = get_soul_shard_data()
        if not sData or sData.excessCount <= 0 then
            if promptFrame and promptFrame:IsShown() then
                promptFrame:Hide()
            end
            return
        end

        -- Soul shard excess exists: find candidates with inventory scan skipped
        local candidates = find_candidates(true)
        if not candidates or #candidates == 0 then
            if promptFrame and promptFrame:IsShown() then
                promptFrame:Hide()
            end
            return
        end

        currentCandidates = candidates
        currentCandidateIndex = 1
        triage.DisplayCandidate(candidates[1])
        return
    end

    -- Free slots <= threshold: full inventory triage scan
    local candidates, cType = find_candidates(false)
    if not candidates or #candidates == 0 then
        if promptFrame and promptFrame:IsShown() then
            promptFrame:Hide()
        end
        return
    end

    currentCandidates = candidates
    currentCandidateIndex = 1
    triage.DisplayCandidate(candidates[1])
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Test Preview & Positioning Helper
-- ─────────────────────────────────────────────────────────────────────────────

function triage.ToggleTestMode()
    local f = create_triage_prompt()
    if isTestMode and f:IsShown() then
        f:Hide()
        isTestMode = false
        return false
    end

    isTestMode = true
    currentCandidates = {
        {
            itemID = 4865,
            itemLink = "|cff9d9d9d|Hitem:4865::::::::1:1447::1::::|h[Broken Boar Tusk]|h|r",
            itemName = "Broken Boar Tusk",
            icon = 134075,
            quality = 0,
            stackCount = 4,
            sellPrice = 1,
            totalValue = 4,
            category = "grey junk",
            bag = 1,
            slot = 3,
        },
        {
            itemID = 4536,
            itemLink = "|cffffffff|Hitem:4536::::::::1:1447::1::::|h[Shiny Red Apple]|h|r",
            itemName = "Shiny Red Apple",
            icon = 133984,
            quality = 1,
            stackCount = 5,
            sellPrice = 2,
            totalValue = 10,
            category = "outdated food/drink",
            bag = 2,
            slot = 1,
        },
        {
            isSoulShardPurge = true,
            itemID = SOUL_SHARD_ID,
            itemLink = "|cff9933ffSoul Shards|r (|cffffffff4 excess|r)",
            itemName = "Soul Shards",
            icon = 134075,
            stackCount = 4,
            sellPrice = 0,
            totalValue = 0,
            category = "excess soul shards",
            deleteButtonText = "purge",
            totalCount = 24,
            maxShards = 20,
            locationText = "pruning regular bag spillover",
            onDelete = function()
                common.print("|cff00ffffsfui triage:|r [test preview] purged 4 excess soul shards simulated.")
            end,
            onKeep = function()
                common.print("|cffaaaaaasfui triage:|r [test preview] keeping soul shards for this session.")
            end,
        },
    }
    currentCandidateIndex = 1
    triage.DisplayCandidate(currentCandidates[1])
    return true
end

function triage.IsTestMode()
    return isTestMode and promptFrame and promptFrame:IsShown()
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Event Listeners & Dispatcher Wiring
-- ─────────────────────────────────────────────────────────────────────────────

local function on_bag_update()
    if not isEnabled or sfui.common.is_in_combat() then return end
    if scanTimer then return end
    scanTimer = C_Timer.After(0.3, function()
        scanTimer = nil
        if not isEnabled or sfui.common.is_in_combat() then return end
        triage.EvaluateTriage()
    end)
end

local function on_ui_error(event, errorType, msg)
    if not isEnabled or sfui.common.is_in_combat() then return end
    -- Immediately evaluate if inventory full error fires
    if msg == _G.ERR_INV_FULL or (msg and msg:find("Inventory is full", 1, true)) then
        triage.EvaluateTriage()
    end
end

local function on_combat_leave()
    if not isEnabled then return end
    -- Check if bags filled while fighting
    C_Timer.After(0.4, function()
        triage.EvaluateTriage()
    end)
end

local function on_combat_enter()
    -- Always hide prompt in combat to avoid obstruction
    if promptFrame and promptFrame:IsShown() and not isTestMode then
        promptFrame:Hide()
    end
end

local function on_merchant_show()
    -- Always hide prompt at merchant (sell greys at vendor instead)
    if promptFrame and promptFrame:IsShown() and not isTestMode then
        promptFrame:Hide()
    end
end

local function on_channel_stop(event, unit)
    if not isEnabled or sfui.common.is_in_combat() then return end
    C_Timer.After(0.2, function()
        if not isEnabled or sfui.common.is_in_combat() then return end
        triage.EvaluateTriage()
    end)
end

local function on_cast_succeeded(event, unit)
    if not isEnabled or sfui.common.is_in_combat() then return end
    C_Timer.After(0.25, function()
        if not isEnabled or sfui.common.is_in_combat() then return end
        triage.EvaluateTriage()
    end)
end

function triage.Enable()
    isEnabled = true
    if sfui.events and sfui.events.RegisterEvent then
        sfui.events.RegisterEvent("BAG_UPDATE_DELAYED", on_bag_update)
        sfui.events.RegisterEvent("UI_ERROR_MESSAGE", on_ui_error)
        sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", on_combat_leave)
        sfui.events.RegisterEvent("PLAYER_REGEN_DISABLED", on_combat_enter)
        sfui.events.RegisterEvent("MERCHANT_SHOW", on_merchant_show)
        sfui.events.RegisterEvent("LOOT_OPENED", on_bag_update)
        if isWarlock then
            sfui.events.RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player", on_channel_stop)
            sfui.events.RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", on_cast_succeeded)
        end
    end
    triage.EvaluateTriage()
end

function triage.Disable()
    isEnabled = false
    if promptFrame and promptFrame:IsShown() then
        promptFrame:Hide()
    end
    if sfui.events and sfui.events.UnregisterEvent then
        sfui.events.UnregisterEvent("BAG_UPDATE_DELAYED", on_bag_update)
        sfui.events.UnregisterEvent("UI_ERROR_MESSAGE", on_ui_error)
        sfui.events.UnregisterEvent("PLAYER_REGEN_ENABLED", on_combat_leave)
        sfui.events.UnregisterEvent("PLAYER_REGEN_DISABLED", on_combat_enter)
        sfui.events.UnregisterEvent("MERCHANT_SHOW", on_merchant_show)
        sfui.events.UnregisterEvent("LOOT_OPENED", on_bag_update)
        if isWarlock then
            sfui.events.UnregisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player", on_channel_stop)
            sfui.events.UnregisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", on_cast_succeeded)
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SFUI Module Protocol Registration
-- ─────────────────────────────────────────────────────────────────────────────

local _debugInfo = {}
function triage.GetDebugInfo()
    _debugInfo.enabled = isEnabled
    _debugInfo.freeRegularSlots = lastFreeSlots
    _debugInfo.threshold = (sfui.db and sfui.db.Get and sfui.db.Get("triage", "threshold", (sfui.config.triage and sfui.config.triage.threshold) or 1)) or 1
    _debugInfo.candidateCount = #currentCandidates
    _debugInfo.isPromptShown = promptFrame and promptFrame:IsShown() or false
    _debugInfo.deleteSoulShards = (sfui.db and sfui.db.Get and sfui.db.Get("triage", "deleteSoulShards", false))
    _debugInfo.maxSoulShards = (sfui.db and sfui.db.Get and sfui.db.Get("triage", "maxSoulShards", 20))
    _debugInfo.preserveSoulBag = (sfui.db and sfui.db.Get and sfui.db.Get("triage", "preserveSoulBag", true))
    _debugInfo.soulShardMode = (sfui.db and sfui.db.Get and sfui.db.Get("triage", "soulShardMode", "auto"))
    _debugInfo.soulShardChat = (sfui.db and sfui.db.Get and sfui.db.Get("triage", "soulShardChat", true))
    return _debugInfo
end

local TriageModule = sfui.RegisterModule("triage", {
    OnInit = function(self)
        if sfui.db and sfui.db.RegisterDefaults and sfui.config and sfui.config.triage then
            sfui.db.RegisterDefaults("triage", sfui.config.triage)
        end
        if SfuiDB and not SfuiDB.triageThresholdDefaultV1 then
            if SfuiDB.triage and (SfuiDB.triage.threshold == 0 or SfuiDB.triage.threshold == nil) then
                SfuiDB.triage.threshold = 1
            end
            SfuiDB.triageThresholdDefaultV1 = true
        end
    end,

    OnEnable = function(self)
        local enabled = (sfui.db and sfui.db.Get and sfui.db.Get("triage", "enabled", true))
        if enabled == nil then enabled = true end
        if enabled then
            triage.Enable()
        else
            triage.Disable()
        end
    end,

    OnDisable = function(self)
        triage.Disable()
    end,

    OnSettingsChanged = function(self, key, value)
        if key == "enabled" then
            if value then
                triage.Enable()
            else
                triage.Disable()
            end
        elseif key == "threshold" or key == "checkConsumables" or key == "protectFoodWater" then
            triage.EvaluateTriage()
        elseif key == "deleteSoulShards" or key == "maxSoulShards" or key == "preserveSoulBag" or key == "soulShardMode" or key == "soulShardChat" then
            triage.EvaluateTriage()
        end
    end,

    GetDebugInfo = function(self)
        return triage.GetDebugInfo()
    end,
})

sfui.triage.module = TriageModule

-- Ensure triage prompt and its named delete button exist early for keybind delegation
local earlyPrompt = create_triage_prompt()
if earlyPrompt then
    earlyPrompt:Hide()
end
if sfui.keybinds and sfui.keybinds.configure_class_utility_button then
    sfui.keybinds.configure_class_utility_button()
end
