local addonName, addon = ...
sfui = sfui or {}
sfui.nav = sfui.nav or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/core/navigation.lua
--  Unified Cross-Window Deep-Link & Ctrl-Click Navigation Router
-- ══════════════════════════════════════════════════════════════════════════════

local _G = _G
local issecretvalue = _G.issecretvalue or function() return false end
local type = _G.type
local tonumber = _G.tonumber
local tostring = _G.tostring
local pairs = _G.pairs
local ipairs = _G.ipairs

local nav = sfui.nav

local _questRewardCache = nil
local _craftedItemCache = nil

local function extract_item_id(itemLinkOrID)
    if itemLinkOrID == nil or issecretvalue(itemLinkOrID) then
        return nil
    end
    if type(itemLinkOrID) == "number" then
        return itemLinkOrID > 0 and itemLinkOrID or nil
    end
    if type(itemLinkOrID) == "string" then
        local direct = tonumber(itemLinkOrID)
        if direct and direct > 0 then
            return direct
        end
        local fromLink = itemLinkOrID:match("item:(%d+)")
        if fromLink then
            return tonumber(fromLink)
        end
    end
    return nil
end

local function ensure_quest_reward_cache()
    if _questRewardCache then return _questRewardCache end
    _questRewardCache = {}
    local dj = sfui.dj_camelot or (sfui.data and sfui.data.dj_camelot)
    if not dj then return _questRewardCache end

    local lists = { dj.dungeons or {}, dj.raids or {} }
    for _, list in ipairs(lists) do
        for _, dungeon in ipairs(list) do
            for _, quest in ipairs(dungeon.quests or {}) do
                local rewardGroups = { quest.rewards, quest.choiceRewards, quest.items }
                for _, grp in ipairs(rewardGroups) do
                    if type(grp) == "table" then
                        for _, entry in ipairs(grp) do
                            local rawID = type(entry) == "table" and (entry.id or entry.itemID or entry[1]) or entry
                            local numID = tonumber(rawID)
                            if numID and not _questRewardCache[numID] then
                                _questRewardCache[numID] = {
                                    dungeonID = dungeon.id,
                                    questID   = quest.id,
                                }
                            end
                        end
                    end
                end
            end
        end
    end
    return _questRewardCache
end

local function ensure_crafted_item_cache()
    if _craftedItemCache then return _craftedItemCache end
    _craftedItemCache = {}
    local rdb = sfui.recipes_camelot
    if not rdb then
        return _craftedItemCache
    end
    if type(rdb._raw) == "table" then
        for spellID, raw in pairs(rdb._raw) do
            if type(raw) == "table" then
                local outID = tonumber(raw[5])
                if outID and outID > 0 and not _craftedItemCache[outID] then
                    _craftedItemCache[outID] = spellID
                end
                local recItemID = tonumber(raw[6])
                if recItemID and recItemID > 0 and not _craftedItemCache[recItemID] then
                    _craftedItemCache[recItemID] = spellID
                end
            end
        end
    elseif type(rdb.IterateRecipes) == "function" then
        for spellID, r in rdb.IterateRecipes() do
            if type(r) == "table" then
                local outID = tonumber(r.output or r.itemID or r.createdItemID or r.outputItemID)
                if outID and outID > 0 and not _craftedItemCache[outID] then
                    _craftedItemCache[outID] = spellID
                end
                local recItemID = tonumber(r.recipeItemID)
                if recItemID and recItemID > 0 and not _craftedItemCache[recItemID] then
                    _craftedItemCache[recItemID] = spellID
                end
            end
        end
    end
    return _craftedItemCache
end

local function find_recipe_spell_for_item(itemID)
    local rdb = sfui.recipes_camelot
    if not rdb then return nil end
    if rdb.recipes and rdb.recipes[itemID] then
        return itemID
    end
    if rdb.items and rdb.items[itemID] then
        local mapped = rdb.items[itemID]
        if type(mapped) == "table" then
            return mapped[1] or mapped.spellID
        end
        return tonumber(mapped) or mapped
    end
    local crafted = ensure_crafted_item_cache()
    return crafted[itemID]
end

local function is_dressable_item(itemID, itemLink)
    if itemID and _G.C_Item and _G.C_Item.IsDressableItemByID then
        if _G.C_Item.IsDressableItemByID(itemID) then
            return true
        end
    end
    if _G.IsDressableItem then
        local arg = itemLink or itemID
        if arg and not issecretvalue(arg) and _G.IsDressableItem(arg) then
            return true
        end
    end
    return false
end

local _lastCtrlNavID = nil
local _lastCtrlNavTime = 0
local _lastCtrlNavResult = false

function nav.OpenOption(tabKey)
    if sfui.open_options_panel then
        sfui.open_options_panel(tabKey)
        return true
    elseif sfui.toggle_options_panel then
        sfui.toggle_options_panel(tabKey)
        return true
    end
    return false
end

function nav.OpenDungeon(dungeonID, mode, targetID)
    local dj = sfui.dungeonjournal
    if not dj then
        if sfui.isRetail and sfui.lootviewer and sfui.lootviewer.Toggle then
            sfui.lootviewer.Toggle()
            return true
        end
        return false
    end

    if (mode == "boss" or mode == "bosses") and targetID and dj.OpenToBoss then
        return dj.OpenToBoss(targetID, dungeonID)
    elseif (mode == "quest" or mode == "quests") and targetID and dj.SelectQuest then
        return dj.SelectQuest(dungeonID, targetID)
    elseif dungeonID and dj.OpenToDungeon then
        dj.OpenToDungeon(dungeonID, mode or "bosses")
        return true
    elseif dj.Open then
        dj.Open()
        return true
    end
    return false
end

function nav.OpenRecipe(spellOrItemID)
    if not sfui.recipes or not sfui.recipes.OpenBrowserToRecipe then
        return false
    end
    local id = extract_item_id(spellOrItemID) or tonumber(spellOrItemID)
    if not id then
        if sfui.recipes.ToggleBrowser then
            sfui.recipes.ToggleBrowser()
            return true
        end
        return false
    end
    local spellID = find_recipe_spell_for_item(id) or id
    sfui.recipes.OpenBrowserToRecipe(spellID)
    return true
end

function nav.OpenFishingSpecies(itemID)
    local atlas = sfui.fishing and sfui.fishing.atlas
    if not atlas then return false end
    if itemID and atlas.OpenToSpecies then
        return atlas.OpenToSpecies(itemID)
    elseif atlas.Toggle then
        atlas.Toggle()
        return true
    end
    return false
end

function nav.OpenFishingWater(mapID)
    local atlas = sfui.fishing and sfui.fishing.atlas
    if not atlas then return false end
    if mapID and atlas.OpenToZone then
        return atlas.OpenToZone(mapID)
    elseif atlas.ShowTab then
        local f = atlas.GetFrame and atlas.GetFrame()
        if not f or not f:IsShown() then
            atlas.Toggle()
        end
        atlas.ShowTab("waters")
        return true
    end
    return false
end

function nav.OpenAlts()
    if not sfui.alts then return false end
    if sfui.alts.Open then
        sfui.alts.Open()
        return true
    elseif sfui.alts.GetFrame then
        local f = sfui.alts.GetFrame()
        if f and f:IsShown() then return true end
    end
    if sfui.alts.Toggle then
        sfui.alts.Toggle()
        return true
    end
    return false
end

function nav.OpenItemSource(itemLinkOrID)
    local id = extract_item_id(itemLinkOrID)
    if not id then return false end

    local djFrame = sfui.dungeonjournal and sfui.dungeonjournal.GetFrame and sfui.dungeonjournal.GetFrame()
    local djOpen = djFrame and djFrame:IsShown()
    local recSpell = find_recipe_spell_for_item(id)

    -- If Dungeon Journal is currently open and the clicked item is a recipe or crafted item, jump to Recipe Browser first
    if djOpen and recSpell and sfui.recipes and sfui.recipes.OpenBrowserToRecipe then
        sfui.recipes.OpenBrowserToRecipe(recSpell)
        return true
    end

    -- 1. Recipe scroll item -> Recipe Browser (unless Recipe Browser is already open, then prefer drop source)
    local isRecipeScroll = sfui.recipes_camelot and sfui.recipes_camelot.items and sfui.recipes_camelot.items[id] ~= nil
    local recInfo = sfui.recipes_debug_info and sfui.recipes_debug_info()
    local recOpen = recInfo and recInfo.isBrowserOpen
    if isRecipeScroll and not recOpen and recSpell and sfui.recipes and sfui.recipes.OpenBrowserToRecipe then
        sfui.recipes.OpenBrowserToRecipe(recSpell)
        return true
    end

    -- 2. Dungeon Journal encounter drop source
    local djData = sfui.dj_camelot
    if djData and djData.GetItemSource and sfui.dungeonjournal then
        local src = djData.GetItemSource(id)
        if src and src.dungeonID then
            return nav.OpenDungeon(src.dungeonID, "bosses", src.bossName)
        end
    end

    -- 3. Dungeon Journal quest reward source
    if sfui.dungeonjournal then
        local qRewards = ensure_quest_reward_cache()
        local qSrc = qRewards[id]
        if qSrc and qSrc.dungeonID then
            return nav.OpenDungeon(qSrc.dungeonID, "quests", qSrc.questID)
        end
    end

    -- 4. Recipe Browser (crafted output or recipe scroll fallback)
    if recSpell and sfui.recipes and sfui.recipes.OpenBrowserToRecipe then
        sfui.recipes.OpenBrowserToRecipe(recSpell)
        return true
    end

    -- 5. Fishing Atlas species
    local fData = sfui.fishing_data
    if fData and fData.GetAllSpecies then
        local allSpecies = fData.GetAllSpecies()
        if allSpecies and allSpecies[id] then
            return nav.OpenFishingSpecies(id)
        end
    end

    return false
end

function nav.OpenRecipeOrFishing(itemLinkOrID)
    local id = extract_item_id(itemLinkOrID)
    if not id then return false end

    local now = (_G.GetTime and _G.GetTime()) or 0
    if _lastCtrlNavID == id and (now - _lastCtrlNavTime) < 0.15 then
        return _lastCtrlNavResult
    end

    local linkStr = (type(itemLinkOrID) == "string" and not issecretvalue(itemLinkOrID)) and itemLinkOrID or nil
    local recSpell = find_recipe_spell_for_item(id)
    local isRecipeScroll = sfui.recipes_camelot and sfui.recipes_camelot.items and sfui.recipes_camelot.items[id] ~= nil
    local hasReagentUses = sfui.recipes and sfui.recipes.GetRecipesUsingReagent and sfui.recipes.GetRecipesUsingReagent(id) ~= nil

    local fData = sfui.fishing_data
    local allSpecies = fData and fData.GetAllSpecies and fData.GetAllSpecies()
    local isFishingSpecies = (allSpecies and allSpecies[id] ~= nil) or false

    local handled = false

    -- 1. Explicit recipe scrolls always open the Recipe Browser
    if isRecipeScroll and recSpell then
        handled = nav.OpenRecipe(recSpell)
    -- 2. Catchable fish & fishing containers: open Fishing Atlas (or cross-jump to Recipe Browser when Fishing Atlas is already open)
    elseif isFishingSpecies then
        local atlasFrame = sfui.fishing and sfui.fishing.atlas and sfui.fishing.atlas.GetFrame and sfui.fishing.atlas.GetFrame()
        local atlasOpen = atlasFrame and atlasFrame:IsShown()
        local recInfo = sfui.recipes_debug_info and sfui.recipes_debug_info()
        local recOpen = recInfo and recInfo.isBrowserOpen
        if atlasOpen and not recOpen and (recSpell or hasReagentUses) then
            if recSpell then
                handled = nav.OpenRecipe(recSpell)
            elseif sfui.recipes and sfui.recipes.OpenBrowserForReagent then
                handled = sfui.recipes.OpenBrowserForReagent(id)
            end
        end
        if not handled then
            handled = nav.OpenFishingSpecies(id)
        end
    -- 3. Preserve native WoW Dressing Room preview for dressable weapons & armor
    elseif not is_dressable_item(id, linkStr) then
        -- 4. Non-dressable crafted outputs -> Recipe Browser
        if recSpell then
            handled = nav.OpenRecipe(recSpell)
        -- 5. Crafting reagents -> Recipe Browser filtered by reagent
        elseif hasReagentUses and sfui.recipes and sfui.recipes.OpenBrowserForReagent then
            handled = sfui.recipes.OpenBrowserForReagent(id)
        end
    end

    _lastCtrlNavID = id
    _lastCtrlNavTime = now
    _lastCtrlNavResult = handled and true or false
    return _lastCtrlNavResult
end

function nav.HandleCtrlClickItem(itemID, itemLink)
    if not (_G.IsControlKeyDown and _G.IsControlKeyDown()) then return false end
    if (_G.IsShiftKeyDown and _G.IsShiftKeyDown()) or (_G.IsAltKeyDown and _G.IsAltKeyDown()) then
        return false
    end
    return nav.OpenRecipeOrFishing(itemLink or itemID)
end

if _G.hooksecurefunc and _G.HandleModifiedItemClick then
    _G.hooksecurefunc("HandleModifiedItemClick", function(link)
        if not link or issecretvalue(link) then return end
        if not (_G.IsControlKeyDown and _G.IsControlKeyDown()) then return end
        if (_G.IsShiftKeyDown and _G.IsShiftKeyDown()) or (_G.IsAltKeyDown and _G.IsAltKeyDown()) then return end
        nav.OpenRecipeOrFishing(link)
    end)
end

