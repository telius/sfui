--[[
    SFUI Tracker Module: Camelot Tracked Recipes & Shopping List
    frames/quests/modules/q_camelot_recipes.lua

    Pluggable tracker module for Warcraft Forever (Camelot) & Classic Era.
    Displays pinned recipes with live reagent bag counts, acquisition source info,
    waypoint tracking, Blizzard C_TradeSkillUI integration, and direct router to the SFUI Recipe Catalog.
--]]

local addonName, addon = ...
local sfui = _G.sfui or {}
sfui.tracker = sfui.tracker or {}
sfui.questlog = sfui.questlog or {}
sfui.recipes = sfui.recipes or {}

-- Guard: Classic / Camelot only (Exclude Retail)
local isRetail = sfui.isRetail
if isRetail == nil then
    local projectID = _G.WOW_PROJECT_ID or 1
    local _, _, _, tocVersionNum = _G.GetBuildInfo()
    tocVersionNum = tonumber(tocVersionNum) or 0
    local isCamelot = (tocVersionNum >= 16000 and tocVersionNum < 20000) or (projectID == 18)
    isRetail = (projectID == 1) and not isCamelot
end

if isRetail then
    return
end

local _G = _G
local C_Item = _G.C_Item
local C_TradeSkillUI = _G.C_TradeSkillUI
local GetItemCount = _G.GetItemCount
local GetItemInfo = _G.GetItemInfo
local PlaySound = _G.PlaySound
local SOUNDKIT = _G.SOUNDKIT
local IsShiftKeyDown = _G.IsShiftKeyDown
local InCombatLockdown = _G.InCombatLockdown

local ipairs, pairs, type, tonumber, tostring = _G.ipairs, _G.pairs, _G.type, _G.tonumber, _G.tostring
local table_insert, table_sort = _G.table.insert, _G.table.sort
local string_format = string.format

-- ─────────────────────────────────────────────────────────
--  STORAGE & PUBLIC API
-- ─────────────────────────────────────────────────────────
local function GetPinnedStorage()
    SfuiDB = SfuiDB or {}
    SfuiDB.pinned_recipes = SfuiDB.pinned_recipes or {}
    return SfuiDB.pinned_recipes
end

function sfui.recipes.GetPinnedRecipes()
    return GetPinnedStorage()
end

function sfui.recipes.IsRecipePinned(spellID)
    if not spellID then return false end
    local pinned = GetPinnedStorage()
    if pinned[spellID] == true or pinned[tostring(spellID)] == true then
        return true
    end
    if C_TradeSkillUI and C_TradeSkillUI.IsRecipeTracked then
        local numID = tonumber(spellID)
        if numID and (C_TradeSkillUI.IsRecipeTracked(numID, false) or C_TradeSkillUI.IsRecipeTracked(numID, true)) then
            return true
        end
    end
    return false
end

function sfui.recipes.TogglePinRecipe(spellID)
    spellID = tonumber(spellID) or spellID
    if not spellID then return false end
    local pinned = GetPinnedStorage()
    local isCurrentlyPinned = sfui.recipes.IsRecipePinned(spellID)
    local isPinned = not isCurrentlyPinned

    if isPinned then
        pinned[spellID] = true
        pinned[tostring(spellID)] = nil
        if C_TradeSkillUI and C_TradeSkillUI.SetRecipeTracked and C_TradeSkillUI.IsRecipeProfessionLearned then
            if C_TradeSkillUI.IsRecipeProfessionLearned(spellID) then
                pcall(C_TradeSkillUI.SetRecipeTracked, spellID, true, false)
            end
        end
    else
        pinned[spellID] = nil
        pinned[tostring(spellID)] = nil
        if C_TradeSkillUI and C_TradeSkillUI.SetRecipeTracked and C_TradeSkillUI.IsRecipeTracked then
            if C_TradeSkillUI.IsRecipeTracked(spellID, false) then
                pcall(C_TradeSkillUI.SetRecipeTracked, spellID, false, false)
            end
            if C_TradeSkillUI.IsRecipeTracked(spellID, true) then
                pcall(C_TradeSkillUI.SetRecipeTracked, spellID, false, true)
            end
        end
    end

    if PlaySound and SOUNDKIT then
        if isPinned then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
        else
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or 857)
        end
    end

    if sfui.tracker and sfui.tracker.RequestRefresh then
        sfui.tracker.RequestRefresh(0)
    end

    if sfui.recipes.browser and sfui.recipes.browser.UpdateList then
        sfui.recipes.browser.UpdateList()
    end

    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_RECIPE_PINNED_CHANGED", spellID, isPinned)
    end

    return isPinned
end

function sfui.recipes.OpenBrowserToRecipe(spellID)
    if InCombatLockdown and InCombatLockdown() then return end
    spellID = tonumber(spellID) or spellID
    if not spellID then return end

    local db = sfui.recipes_camelot and sfui.recipes_camelot.recipes
    local r = db and db[spellID]

    if sfui.recipes.browser and sfui.recipes.OpenBrowser then
        sfui.recipes.OpenBrowser()
        if r and r.profession and sfui.recipes.browser.SelectProfession then
            sfui.recipes.browser:SelectProfession(r.profession)
        end
        if r and r.name and sfui.recipes.browser.SetSearch then
            sfui.recipes.browser:SetSearch(r.name:lower())
        end
    end
end

-- ─────────────────────────────────────────────────────────
--  OBJECTIVE TRACKER MODULE
-- ─────────────────────────────────────────────────────────
local CamelotRecipesModule = {
    id       = "camelot_recipes",
    priority = 61,
    events   = {
        "BAG_UPDATE_DELAYED",
        "PLAYER_ENTERING_WORLD",
        "TRACKED_RECIPE_UPDATE",
        "CURRENCY_DISPLAY_UPDATE",
        "GET_ITEM_INFO_RECEIVED",
        "TRADE_SKILL_SHOW",
    },
}

function CamelotRecipesModule:Init(engine)
    self.engine = engine
    if sfui.events and sfui.events.RegisterMessage then
        sfui.events.RegisterMessage("SFUI_RECIPE_PINNED_CHANGED", function()
            self:MarkDirty(0)
            sfui.tracker.RequestRefresh(0)
        end)
    end
end

function CamelotRecipesModule:IsEnabled()
    return true
end

function CamelotRecipesModule:OnEvent(event, ...)
    self:MarkDirty(0.05)
    sfui.tracker.RequestRefresh(0.05)
    if event == "TRACKED_RECIPE_UPDATE" then
        if sfui.recipes.browser and sfui.recipes.browser.UpdateList then
            sfui.recipes.browser.UpdateList()
        end
    end
end

function CamelotRecipesModule:BuildBlocks(container)
    local db = sfui.recipes_camelot and sfui.recipes_camelot.recipes

    -- Gather recipes to track from both SfuiDB.pinned_recipes and C_TradeSkillUI.GetRecipesTracked
    local trackedMap = {}

    local pinned = GetPinnedStorage()
    if pinned then
        for id, isPinned in pairs(pinned) do
            if isPinned then
                local numID = tonumber(id)
                if numID and numID > 0 then
                    trackedMap[numID] = trackedMap[numID] or { recipeID = numID }
                    trackedMap[numID].isSfuiPinned = true
                end
            end
        end
    end

    if C_TradeSkillUI and C_TradeSkillUI.GetRecipesTracked then
        for _, isRecraft in ipairs({ false, true }) do
            local blizzTracked = C_TradeSkillUI.GetRecipesTracked(isRecraft)
            if blizzTracked and #blizzTracked > 0 then
                for _, rID in ipairs(blizzTracked) do
                    local numID = tonumber(rID)
                    if numID and numID > 0 then
                        trackedMap[numID] = trackedMap[numID] or { recipeID = numID }
                        trackedMap[numID].isBlizzTracked = true
                        trackedMap[numID].isRecraft = isRecraft
                    end
                end
            end
        end
    end

    if not next(trackedMap) then
        return nil
    end

    local recipeList = {}
    for numID, entry in pairs(trackedMap) do
        entry.recipeData = db and db[numID]
        table_insert(recipeList, entry)
    end

    if #recipeList == 0 then
        return nil
    end

    table_sort(recipeList, function(a, b)
        local nameA = (a.recipeData and a.recipeData.name) or ""
        local nameB = (b.recipeData and b.recipeData.name) or ""
        if nameA == "" and C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic then
            local schA = C_TradeSkillUI.GetRecipeSchematic(a.recipeID, a.isRecraft or false)
            nameA = (schA and schA.name) or ""
        end
        if nameB == "" and C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic then
            local schB = C_TradeSkillUI.GetRecipeSchematic(b.recipeID, b.isRecraft or false)
            nameB = (schB and schB.name) or ""
        end
        return nameA:lower() < nameB:lower()
    end)

    local blocks = {}

    for _, entry in ipairs(recipeList) do
        local spellID = entry.recipeID
        local r = entry.recipeData
        local isRecraft = entry.isRecraft or false
        local schematic = nil
        if C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic then
            schematic = C_TradeSkillUI.GetRecipeSchematic(spellID, isRecraft)
        end

        local recipeName = (r and r.name)
            or (schematic and schematic.name and schematic.name ~= "" and schematic.name)
            or (C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(spellID) and C_TradeSkillUI.GetRecipeInfo(spellID).name)
            or ("recipe #" .. tostring(spellID))

        local lines = {}
        local allReagentsMet = true
        local hasReagents = false

        -- 1. Source Line (show vendor / trainer / drop if unlearned)
        local isLearned = C_TradeSkillUI and C_TradeSkillUI.IsRecipeProfessionLearned and C_TradeSkillUI.IsRecipeProfessionLearned(spellID)
        local firstSource = r and sfui.recipes.GetFirstNonHostileSource and sfui.recipes.GetFirstNonHostileSource(r)
        if not firstSource and r and r.sources and r.sources[1] then
            firstSource = r.sources[1]
        end

        if firstSource and not isLearned then
            local st = firstSource.type or "source"
            local sName = firstSource.name or firstSource.desc or st
            local loc = firstSource.zone or ""
            local srcText = ""
            if st == "trainer" then
                srcText = "trainer: " .. (sName ~= "trainer" and sName or (loc ~= "" and loc or "major city"))
            elseif st == "vendor" then
                srcText = "vendor: " .. sName .. (loc ~= "" and (" (" .. loc .. ")") or "")
            elseif st == "drop" then
                srcText = "drop: " .. sName .. (loc ~= "" and (" (" .. loc .. ")") or "")
            elseif st == "quest" then
                srcText = "quest: " .. sName
            else
                srcText = st .. ": " .. sName .. (loc ~= "" and (" (" .. loc .. ")") or "")
            end

            table_insert(lines, {
                text  = srcText:lower(),
                color = { 0.70, 0.70, 0.75, 1.0 },
            })

            if firstSource.mapID and firstSource.x and firstSource.y then
                local coordText = string_format("coords: %.1f, %.1f", firstSource.x * 100, firstSource.y * 100)
                table_insert(lines, {
                    text  = coordText,
                    color = { 0.55, 0.80, 0.95, 1.0 },
                })
            end
        end

        -- 2. Reagents List with Live Bag Counts
        if schematic and schematic.reagentSlotSchematics and #schematic.reagentSlotSchematics > 0 then
            for _, slot in ipairs(schematic.reagentSlotSchematics) do
                local req = slot.quantityRequired or 1
                local reagent = slot.reagents and slot.reagents[1]
                if reagent then
                    local itemID = reagent.itemID
                    local currencyID = reagent.currencyID
                    local rName = nil
                    local curCount = 0

                    if itemID then
                        curCount = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(itemID)) or (_G.GetItemCount and _G.GetItemCount(itemID)) or 0
                        if C_Item and C_Item.GetItemNameByID then
                            rName = C_Item.GetItemNameByID(itemID)
                        end
                        if not rName and _G.GetItemInfo then
                            rName = _G.GetItemInfo(itemID)
                        end
                        rName = rName or ("item #" .. tostring(itemID))
                    elseif currencyID then
                        local cInfo = sfui.common.get_currency_info(currencyID)
                        if cInfo then
                            rName = cInfo.name
                            curCount = cInfo.quantity or 0
                        else
                            rName = "currency #" .. tostring(currencyID)
                        end
                    end

                    if rName and rName ~= "" then
                        hasReagents = true
                        local isDone = (curCount >= req)
                        if not isDone then
                            allReagentsMet = false
                        end
                        table_insert(lines, {
                            text      = string_format("%s (%d/%d)", rName:lower(), curCount, req),
                            completed = isDone,
                        })
                    end
                end
            end
        elseif r and r.reagents and next(r.reagents) then
            for matID, reqCount in pairs(r.reagents) do
                hasReagents = true
                local curCount = 0
                if C_Item and C_Item.GetItemCount then
                    curCount = C_Item.GetItemCount(matID)
                elseif GetItemCount then
                    curCount = GetItemCount(matID)
                end

                local matName = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(matID))
                    or (GetItemInfo and GetItemInfo(matID))
                    or ("item #" .. tostring(matID))

                local isDone = (curCount >= reqCount)
                if not isDone then
                    allReagentsMet = false
                end

                table_insert(lines, {
                    text      = string_format("%s (%d/%d)", matName:lower(), curCount, reqCount),
                    completed = isDone,
                })
            end
        end

        local isComplete = (hasReagents and allReagentsMet)
        local titleColor = isComplete and { 0.20, 1.00, 0.35, 1.0 } or { 1.00, 0.72, 0.35, 1.0 }
        local prefix = isComplete and "[ready] " or (isRecraft and "[recraft] " or "[recipe] ")
        local displayName = prefix .. recipeName:lower()

        table_insert(blocks, {
            id         = "rec_" .. tostring(spellID) .. (isRecraft and "_r" or ""),
            title      = displayName,
            titleColor = titleColor,
            lines      = lines,
            OnClick    = function(block, btn)
                if btn == "RightButton" or (IsShiftKeyDown and IsShiftKeyDown()) then
                    if entry.isSfuiPinned then
                        sfui.recipes.TogglePinRecipe(spellID)
                    end
                    if entry.isBlizzTracked and C_TradeSkillUI and C_TradeSkillUI.SetRecipeTracked then
                        C_TradeSkillUI.SetRecipeTracked(spellID, false, isRecraft)
                    end
                    sfui.tracker.RequestRefresh(0.05)
                    return
                end

                if not (InCombatLockdown and InCombatLockdown()) then
                    if isLearned and C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then
                        C_TradeSkillUI.OpenRecipe(spellID)
                    elseif sfui.recipes and sfui.recipes.OpenBrowserToRecipe then
                        sfui.recipes.OpenBrowserToRecipe(spellID)
                    end
                end
            end,
            tooltip    = function(tip, owner, bData)
                tip:AddLine(recipeName, titleColor[1], titleColor[2], titleColor[3])
                if r and r.profession then
                    local minSkill = r.minSkill or (r.colors and r.colors[1]) or 0
                    tip:AddLine(string_format("%s (rank %d)", r.profession:lower(), minSkill), 0.70, 0.70, 0.70)
                end
                if isComplete then
                    tip:AddLine("all required crafting materials collected", 0.20, 1.00, 0.35, true)
                elseif hasReagents then
                    tip:AddLine("crafting materials incomplete", 1.00, 0.72, 0.35, true)
                end
                tip:AddLine(" ")
                tip:AddLine("|cff888888left-click: open recipe / catalogue|r", 1, 1, 1)
                tip:AddLine("|cff888888shift-click or right-click: unpin recipe|r", 1, 1, 1)
            end,
        })
    end

    if #blocks > 0 then
        return {
            {
                id     = "camelot_recipes",
                title  = "tracked recipes",
                color  = { 1.00, 0.75, 0.35 },
                blocks = blocks,
            }
        }
    end

    return nil
end

sfui.tracker.RegisterModule(CamelotRecipesModule)
return CamelotRecipesModule
