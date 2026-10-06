local addonName, addon = ...
---@diagnostic disable: undefined-global
-- frames/merchant/merchant_filter.lua
-- Data modeling, table pooling, usability/spec filtering, and item lock reason caching for sfui merchant

sfui = sfui or {}
sfui.merchant = sfui.merchant or {}

local common = sfui.common
local get_item_id = common.get_item_id_from_link
local cfg = sfui.config.merchant
local NUM_ROWS = cfg.grid.rows
local NUM_COLS = cfg.grid.cols

-- Memory optimization: Table pooling and scratch tables
sfui.merchant.tablePool = sfui.merchant.tablePool or {}
local tablePool = sfui.merchant.tablePool

local function getTable()
    local t = next(tablePool)
    if t then
        tablePool[t] = nil
        return t
    end
    return {}
end
sfui.merchant.getTable = getTable

local function releaseTable(t)
    if not t then return end
    wipe(t)
    tablePool[t] = true
end
sfui.merchant.releaseTable = releaseTable

local function releaseCache(cache)
    if not cache then return end
    for k, t in pairs(cache) do
        releaseTable(t)
        cache[k] = nil
    end
end
sfui.merchant.releaseCache = releaseCache

-- State tracking
sfui.merchant.lootFilterState = 0 -- 0=All, 1=Class, 2=Spec
sfui.merchant.mode = "merchant"   -- "merchant" or "buyback"
sfui.merchant.filterKnown = 1     -- 0=show all, 1=hide known (char), 2=hide known (warband)
sfui.merchant.scrollOffset = 0
sfui.merchant.totalMerchantItems = 0

-- Caches
sfui.merchant.filteredIndices = sfui.merchant.filteredIndices or {}
sfui.merchant.currencyCache = sfui.merchant.currencyCache or {}
sfui.merchant.lockCache = sfui.merchant.lockCache or {}
sfui.merchant.decorXpCache = sfui.merchant.decorXpCache or {}

-- Cache player data for filtering (Performance optimization)
local playerClass, playerClassID = nil, nil
local playerSpecID = nil
local preferredArmor = nil
local isWarlockCamelot = false

local classArmor = {
    ["WARRIOR"] = 4,
    ["PALADIN"] = 4,
    ["DEATHKNIGHT"] = 4,
    ["HUNTER"] = 3,
    ["SHAMAN"] = 3,
    ["EVOKER"] = 3,
    ["DRUID"] = 2,
    ["MONK"] = 2,
    ["ROGUE"] = 2,
    ["DEMONHUNTER"] = 2,
    ["MAGE"] = 1,
    ["PRIEST"] = 1,
    ["WARLOCK"] = 1,
}

local function UpdatePlayerFilterData()
    playerClass, playerClassID = common.get_player_class()
    playerSpecID = common.get_current_spec_id()
    if playerClass then
        preferredArmor = classArmor[playerClass]
    end
    isWarlockCamelot = (sfui.isCamelot or sfui.isClassic) and (playerClass == "WARLOCK")
end
sfui.merchant.UpdatePlayerFilterData = UpdatePlayerFilterData

sfui.events.RegisterEvent("PLAYER_LOGIN", UpdatePlayerFilterData)
sfui.events.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", UpdatePlayerFilterData)

local function AddToCache(id, name, texture, count, type)
    if name and not sfui.merchant.currencyCache[name] then
        local t = getTable()
        t.id = id; t.texture = texture; t.count = count; t.type = type
        sfui.merchant.currencyCache[name] = t
    end
end

--------------------------------------------------------------------------------
-- Warlock Pet Spell & Grimoire Tracking (Camelot / Classic Only)
--------------------------------------------------------------------------------

local function get_num_pet_spells()
    if _G.C_SpellBook and _G.C_SpellBook.HasPetSpells then
        local num, token = _G.C_SpellBook.HasPetSpells()
        if num and type(num) == "number" then return num, token end
        if num then return 50, token end
    end
    if _G.HasPetSpells then
        local num, token = _G.HasPetSpells()
        if num and type(num) == "number" then return num, token end
        if num then return 50, token end
    end
    return 0, nil
end

local function get_pet_spell_name_and_subname(slot)
    local petBank = (_G.Enum and _G.Enum.SpellBookSpellBank and _G.Enum.SpellBookSpellBank.Pet) or 2
    if _G.C_SpellBook and _G.C_SpellBook.GetSpellBookItemName then
        local name, subName = _G.C_SpellBook.GetSpellBookItemName(slot, petBank)
        if name then return name, subName end
    end
    if _G.C_SpellBook and _G.C_SpellBook.GetSpellBookItemInfo then
        local info = _G.C_SpellBook.GetSpellBookItemInfo(slot, petBank)
        if info and info.name then return info.name, info.subName end
    end
    local bookType = _G.BOOKTYPE_PET or "pet"
    if _G.GetSpellBookItemName then
        local name, subName = _G.GetSpellBookItemName(slot, bookType)
        if name then return name, subName end
    end
    return nil, nil
end

function sfui.merchant.scan_pet_spellbook()
    if not isWarlockCamelot then return end
    if not UnitExists("pet") then return end

    local myGUID = UnitGUID("player")
    if not myGUID then return end

    local numSpells = get_num_pet_spells()
    if not numSpells or numSpells <= 0 then return end

    SfuiDB = SfuiDB or {}
    SfuiDB.petSpells = SfuiDB.petSpells or {}
    SfuiDB.petSpells[myGUID] = SfuiDB.petSpells[myGUID] or {}
    local charSpells = SfuiDB.petSpells[myGUID]

    for slot = 1, numSpells do
        local name, subName = get_pet_spell_name_and_subname(slot)
        if not name then break end

        local rank = 1
        if subName and type(subName) == "string" then
            local r = tonumber(string.match(subName, "(%d+)"))
            if r then rank = r end
        end

        local currentRank = charSpells[name] or 0
        if rank > currentRank then
            charSpells[name] = rank
        end
    end
end

function sfui.merchant.record_known_pet_spell(spellName, rank, guid)
    if not isWarlockCamelot or not spellName then return end
    guid = guid or UnitGUID("player")
    if not guid then return end

    rank = tonumber(rank) or 1

    SfuiDB = SfuiDB or {}
    SfuiDB.petSpells = SfuiDB.petSpells or {}
    SfuiDB.petSpells[guid] = SfuiDB.petSpells[guid] or {}

    local currentRank = SfuiDB.petSpells[guid][spellName] or 0
    if rank > currentRank then
        SfuiDB.petSpells[guid][spellName] = rank
    end
end

local function extract_spell_and_rank(str)
    if not str then return nil end
    local spellName, rank = str:match("^(.-)%s*%(%s*[Rr]an[gk]%s*(%d+)%s*%)")
    if spellName and rank then
        return spellName:match("^%s*(.-)%s*$"), tonumber(rank)
    else
        local clean = str:gsub("%.$", ""):match("^%s*(.-)%s*$")
        return clean, 1
    end
end

function sfui.merchant.get_grimoire_spell_info(itemLink)
    if not isWarlockCamelot or not itemLink then return nil end

    -- 1. Try tooltip lines via C_TooltipInfo
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local data = C_TooltipInfo.GetHyperlink(itemLink)
        if data and data.lines then
            for _, line in ipairs(data.lines) do
                local text = line.leftText
                if text and type(text) == "string" then
                    local spellAndRank = text:match("[Tt]eaches your %a+%s+([^%.]+)")
                        or text:match("[Ll]ehrt %a+%s+([^%.]+)")
                        or text:match("[Aa]pprend [àa] votre %a+%s+([^%.]+)")
                    if spellAndRank then
                        return extract_spell_and_rank(spellAndRank)
                    end
                end
            end
        end
    end

    -- 2. Fallback: Parse item name
    local itemName = sfui.common.get_item_info(itemLink)
    if not itemName then
        itemName = itemLink:match("%[(.-)%]")
    end

    if itemName then
        local spellAndRank = itemName:match("Grimoire of%s+(.+)")
            or itemName:match("Grimoire%s*:%s*(.+)")
            or itemName:match("Grimoire%s*-%s*(.+)")
            or itemName:match("Grimoire de%s+(.+)")
        if spellAndRank then
            return extract_spell_and_rank(spellAndRank)
        end
    end

    return nil
end

function sfui.merchant.is_pet_spell_known(itemLink, checkAlts)
    if not isWarlockCamelot or not itemLink then return false end

    local spellName, rank = sfui.merchant.get_grimoire_spell_info(itemLink)
    if not spellName then return false end

    rank = tonumber(rank) or 1
    local myGUID = UnitGUID("player")

    if SfuiDB and SfuiDB.petSpells then
        -- Check current character
        if myGUID and SfuiDB.petSpells[myGUID] then
            local maxRank = SfuiDB.petSpells[myGUID][spellName]
            if maxRank and maxRank >= rank then
                return true
            end
        end

        -- Check other characters if requested (e.g. filterKnown == 2)
        if checkAlts then
            for guid, spells in pairs(SfuiDB.petSpells) do
                if guid ~= myGUID and spells[spellName] and spells[spellName] >= rank then
                    return true
                end
            end
        end
    end

    return false
end

-- Only register pet spellbook scanning events for Warlocks on Camelot
sfui.events.RegisterEvent("PLAYER_LOGIN", function()
    UpdatePlayerFilterData()
    if isWarlockCamelot then
        sfui.merchant.scan_pet_spellbook()
    end
end)

sfui.events.RegisterEvent("PET_SPELL_UPDATE", function()
    if not isWarlockCamelot then return end
    sfui.merchant.scan_pet_spellbook()
    local frame = sfui.merchant.frame
    if frame and frame:IsShown() then
        sfui.merchant.reset_scroll_and_rebuild()
    end
end)

sfui.events.RegisterEvent("UNIT_PET", function(event, unit)
    if not isWarlockCamelot or unit ~= "player" then return end
    sfui.merchant.scan_pet_spellbook()
end)

function sfui.merchant.reset_scroll_and_rebuild()
    sfui.merchant.scrollOffset = 0
    wipe(sfui.merchant.lockCache)
    wipe(sfui.merchant.decorXpCache)
    local frame = sfui.merchant.frame
    if frame and frame.scrollBar then
        frame.scrollBar:SetValue(0)
    end
    sfui.merchant.build_item_list()
end

function sfui.merchant.build_item_list()
    local mode = sfui.merchant.mode
    local numItemsRaw = (mode == "buyback") and GetNumBuybackItems() or GetMerchantNumItems()

    wipe(sfui.merchant.filteredIndices)
    releaseCache(sfui.merchant.currencyCache)

    for i = 1, numItemsRaw do
        local include, link = true, nil
        if mode == "merchant" then
            link = GetMerchantItemLink(i)
        else
            link = GetBuybackItemLink(i)
        end

        local itemID = get_item_id(link)
        if include and mode == "merchant" and sfui.merchant.filterKnown and sfui.merchant.filterKnown ~= 0 and link then
            local isKnown = false
            local isRecipe = itemID and sfui.recipes.IsRecipe(itemID)

            if isRecipe then
                local status = sfui.recipes.GetRecipeStatus(itemID)
                if status == "KNOWN_CURRENT" then
                    isKnown = true
                elseif (sfui.merchant.filterKnown == 2) and (status == "KNOWN_ALT") then
                    isKnown = true
                end
            else
                if common.is_item_known(link) then
                    isKnown = true
                    if isWarlockCamelot and link:find("Grimoire", 1, true) then
                        local sName, rNum = sfui.merchant.get_grimoire_spell_info(link)
                        if sName then
                            sfui.merchant.record_known_pet_spell(sName, rNum)
                        end
                    end
                elseif isWarlockCamelot and link:find("Grimoire", 1, true) then
                    local checkAlts = (sfui.merchant.filterKnown == 2)
                    if sfui.merchant.is_pet_spell_known(link, checkAlts) then
                        isKnown = true
                    end
                elseif itemID and C_PetJournal and C_PetJournal.GetPetInfoByItemID then
                    local _, _, _, _, _, _, _, _, _, _, _, _, speciesID = C_PetJournal.GetPetInfoByItemID(itemID)
                    if speciesID and (C_PetJournal.GetNumCollectedInfo and C_PetJournal.GetNumCollectedInfo(speciesID) or 0) > 0 then
                        isKnown = true
                    end
                end
            end

            if isKnown then
                include = false
            end
        end

        if include and mode == "merchant" and sfui.merchant.lootFilterState > 0 and link then
            local isClassMatch = true
            local info = sfui.api.GetMerchantItemInfo(i)
            if not info or not info.isUsable then
                isClassMatch = false
            else
                local _, _, _, _, _, classID, subclassID = sfui.common.get_item_instant_info(link)
                if not preferredArmor then UpdatePlayerFilterData() end
                -- If it's armor, check preferred armor type
                if classID == 4 and preferredArmor then
                    -- Subclasses: 0=Generic, 1=Cloth, 2=Leather, 3=Mail, 4=Plate, 5=Cosmetic, 6=Shield
                    local isClassic = not sfui.isRetail
                    local playerLvl = UnitLevel("player") or 1
                    local match = (subclassID == preferredArmor)
                    if isClassic then
                        if preferredArmor == 4 and playerLvl <= 50 and (subclassID == 3 or (playerLvl < 40 and subclassID == 2)) then
                            match = true
                        elseif preferredArmor == 3 and playerLvl <= 50 and subclassID == 2 then
                            match = true
                        end
                    end
                    if subclassID >= 1 and subclassID <= 4 and not match then
                        isClassMatch = false
                    end
                end
            end

            if not isClassMatch then
                include = false
            elseif sfui.merchant.lootFilterState == 2 then
                -- Spec Filter (normalize specID to DB2 retail equivalent)
                local curSpec = playerSpecID or common.get_current_spec_id()
                local db2SpecID = common.to_retail_spec_id(curSpec) or curSpec
                if db2SpecID and db2SpecID > 0 and not C_Item.DoesItemContainSpec(link, playerClassID, db2SpecID) then
                    include = false
                end
            end
        end

        if include then table.insert(sfui.merchant.filteredIndices, i) end
        if mode == "merchant" then
            local itemInfo = sfui.api.GetMerchantItemInfo(i)
            if itemInfo then
                if itemInfo.price and itemInfo.price > 0 and not sfui.merchant.currencyCache["Gold"] then
                    local t = getTable()
                    t.texture = 133784
                    t.count = math.floor(GetMoney() / 10000)
                    t.type = "gold"
                    sfui.merchant.currencyCache["Gold"] = t
                end

                if itemInfo.currencyID then
                    local info = common.get_currency_info(itemInfo.currencyID)
                    if info then AddToCache(itemInfo.currencyID, info.name, info.iconFileID, info.quantity, "currency") end
                end

                if itemInfo.hasExtendedCost then
                    for j = 1, GetMerchantItemCostInfo(i) do
                        local texture, amount, costLink, currencyName = GetMerchantItemCostItem(i, j)
                        if costLink then
                            local cID = tonumber(string.match(costLink, "currency:(%d+)"))
                            if not currencyName then
                                currencyName = cID and common.get_currency_name(cID) or
                                    sfui.common.get_item_info(costLink)
                            end
                            local count = cID and common.get_currency_quantity(cID) or
                                common.get_item_count(costLink)
                            AddToCache(cID or get_item_id(costLink), currencyName, texture, count,
                                cID and "currency" or "item")
                        end
                    end
                end
            end
        end
    end

    sfui.merchant.totalMerchantItems = #sfui.merchant.filteredIndices

    local totalRows = math.ceil(sfui.merchant.totalMerchantItems / NUM_COLS)
    local maxOffset = math.max(0, totalRows - NUM_ROWS)
    local frame = sfui.merchant.frame
    if frame and frame.scrollBar then
        frame.scrollBar:SetMinMaxValues(0, maxOffset)
        frame.scrollBar:SetValueStep(1)

        if maxOffset > 0 then
            frame.scrollBar:Show()
        else
            frame.scrollBar:Hide()
        end
    end

    if sfui.merchant.update_merchant then
        sfui.merchant.update_merchant()
    end
    if sfui.merchant.update_currency_display and frame then
        sfui.merchant.update_currency_display(frame)
    end
end

local scratchItemData = {}
local function get_merchant_item_data(index, mode)
    wipe(scratchItemData)
    local d = scratchItemData
    if mode == "buyback" then
        local name, texture, price, qty, _, usable = GetBuybackItemInfo(index)
        if not name then return nil end
        d.name, d.texture, d.price, d.stackCount, d.isUsable = name, texture, price, qty, usable
        d.link = GetBuybackItemLink(index)
    else
        local info = sfui.api.GetMerchantItemInfo(index)
        if not info or not info.name then return nil end
        -- Copy values from C_MerchantFrame result to avoid returning the internal table if it's protected or shared
        for k, v in pairs(info) do d[k] = v end
        d.link = info.hyperlink or GetMerchantItemLink(index)
    end
    if d.link then
        local _, _, q, _, _, _, st, _, el, _, _, ci, sci = sfui.common.get_item_info(d.link)
        d.quality, d.subType, d.equipLoc, d.classID, d.subClassID = q, st, el, ci, sci
    end
    return d
end
sfui.merchant.get_item_data = get_merchant_item_data

function sfui.merchant.get_item_lock_status(index, itemID, isUsable)
    local cachedLock = itemID and sfui.merchant.lockCache[itemID]
    if cachedLock then
        return cachedLock.locked, cachedLock.reason
    end

    local locked, reason = not isUsable, "Unusable"
    local tip = C_TooltipInfo and C_TooltipInfo.GetMerchantItem and C_TooltipInfo.GetMerchantItem(index)
    if tip and tip.lines then
        local reasons = getTable()
        for _, line in ipairs(tip.lines) do
            local clr = line.leftColor
            if clr and clr.r > 0.9 and clr.g < 0.2 and clr.b < 0.2 and line.leftText then
                local text = line.leftText
                if not text:find("Already known") then
                    text = text:gsub("Requires", "R"):gsub("Rank ", ""):gsub("Defeat ", ""):gsub(
                        "Reputation ", "");
                    table.insert(reasons, text)
                    locked = true
                end
            end
        end
        if #reasons > 0 then
            reason = table.concat(reasons, ", ")
        end
        releaseTable(reasons)
    end

    if itemID then
        sfui.merchant.lockCache[itemID] = { locked = locked, reason = reason }
    end

    return locked, reason
end

function sfui.merchant.item_grants_decor_xp(itemID, link)
    if not itemID then return false end
    if sfui.merchant.decorXpCache[itemID] == nil then
        sfui.merchant.decorXpCache[itemID] = common.decor_grants_xp(link) and true or false
    end
    return sfui.merchant.decorXpCache[itemID]
end
