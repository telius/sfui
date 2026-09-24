--[[
    SFUI Tracker Module: Profession Recipes
    frames/quests/modules/recipes.lua

    Pluggable tracker module for tracked crafting and recrafting recipes and reagents.
]]

local addonName, addon = ...
sfui = sfui or {}
sfui.tracker = sfui.tracker or {}
sfui.questlog = sfui.questlog or {}

local _G = _G
local C_TradeSkillUI = _G.C_TradeSkillUI
local C_Item = _G.C_Item
local InCombatLockdown = _G.InCombatLockdown
local IsShiftKeyDown = _G.IsShiftKeyDown

local ipairs, pairs, type, tonumber, tostring = _G.ipairs, _G.pairs, _G.type, _G.tonumber, _G.tostring
local table_insert = _G.table.insert
local string_format = string.format

local RECRAFT_MODES = { false, true }

local function GetQLState()
    if not SfuiDB then SfuiDB = {} end
    if not SfuiDB.questlog then
        SfuiDB.questlog = {
            collapsed      = {},
            expandedQuests = {},
            hiddenQuests   = {},
            hidden         = false,
        }
    end
    return SfuiDB.questlog
end

local RecipesModule = {
    id       = "recipes",
    priority = 60,
    events   = {
        "TRACKED_RECIPE_UPDATE",
        "BAG_UPDATE",
        "CURRENCY_DISPLAY_UPDATE",
    },
}

function RecipesModule:Init(engine)
    self.engine = engine
end

function RecipesModule:IsEnabled()
    return (C_TradeSkillUI ~= nil and C_TradeSkillUI.GetRecipesTracked ~= nil)
end

function RecipesModule:BuildBlocks(container)
    if not C_TradeSkillUI or not C_TradeSkillUI.GetRecipesTracked or not C_TradeSkillUI.GetRecipeSchematic then
        return nil
    end

    local blocks = {}
    local state = GetQLState()
    local expandedQuests = state.expandedQuests or {}

    for _, isRecraft in ipairs(RECRAFT_MODES) do
        local recipes = C_TradeSkillUI.GetRecipesTracked(isRecraft)
        if recipes and #recipes > 0 then
            for _, recipeID in ipairs(recipes) do
                if type(recipeID) == "number" and recipeID > 0 then
                    local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, isRecraft)
                    if schematic and schematic.name and schematic.name ~= "" then
                        local lines = {}
                        local allReagentsMet = true
                        local hasAnyReagent = false
                        local key = "rec_" .. tostring(recipeID) .. (isRecraft and "_r" or "")
                        local isExpanded = (expandedQuests[key] ~= false)

                        if schematic.reagentSlotSchematics then
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
                                        rName = rName or ("Item #" .. tostring(itemID))
                                    elseif currencyID then
                                        local cInfo = sfui.common and sfui.common.get_currency_info and sfui.common.get_currency_info(currencyID)
                                        if cInfo then
                                            rName = cInfo.name
                                            curCount = cInfo.quantity or 0
                                        end
                                    end

                                    if rName and rName ~= "" then
                                        hasAnyReagent = true
                                        local isDone = (curCount >= req)
                                        if not isDone then allReagentsMet = false end

                                        if isExpanded then
                                            table_insert(lines, {
                                                text      = string_format("%s (%d/%d)", rName, curCount, req),
                                                completed = isDone,
                                            })
                                        end
                                    end
                                end
                            end
                        end

                        local isComplete = (hasAnyReagent and allReagentsMet)
                        local recPrefix = isRecraft and "[Recraft] " or "[Recipe] "

                        table_insert(blocks, {
                            title      = recPrefix .. schematic.name,
                            titleColor = isComplete and { 0.2, 1.0, 0.2, 1 } or { 1.0, 0.70, 0.40, 1 },
                            isRecipe   = true,
                            recipeID   = recipeID,
                            isRecraft  = isRecraft,
                            lines      = lines,
                            OnClick    = function(block, btn)
                                -- Shift-Click: Untrack
                                if IsShiftKeyDown and IsShiftKeyDown() then
                                    if C_TradeSkillUI.SetRecipeTracked then
                                        C_TradeSkillUI.SetRecipeTracked(recipeID, false, isRecraft)
                                    end
                                    if sfui.tracker and sfui.tracker.RequestRefresh then
                                        sfui.tracker.RequestRefresh(0.05)
                                    end
                                    return
                                end

                                -- Right-Click: Toggle Criteria
                                if btn == "RightButton" then
                                    local st = GetQLState()
                                    st.expandedQuests = st.expandedQuests or {}
                                    st.expandedQuests[key] = not st.expandedQuests[key]
                                    if sfui.tracker and sfui.tracker.RequestRefresh then
                                        sfui.tracker.RequestRefresh(0.05)
                                    end
                                    return
                                end

                                -- Left-Click: Open Recipe Frame
                                if not (InCombatLockdown and InCombatLockdown()) then
                                    if _G.ProfessionsUtil and _G.ProfessionsUtil.OpenProfessionFrameToRecipe then
                                        _G.ProfessionsUtil.OpenProfessionFrameToRecipe(recipeID)
                                    elseif C_TradeSkillUI.OpenRecipe then
                                        C_TradeSkillUI.OpenRecipe(recipeID)
                                    end
                                end
                            end,
                        })
                    end
                end
            end
        end
    end

    if #blocks > 0 then
        return {
            {
                id     = "recipes",
                title  = "recipes",
                color  = { 1.00, 0.65, 0.35 },
                blocks = blocks,
            }
        }
    end

    return nil
end

sfui.tracker.RegisterModule(RecipesModule)
return RecipesModule
