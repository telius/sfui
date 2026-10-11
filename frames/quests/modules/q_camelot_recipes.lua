--[[
    SFUI Tracker Module: Camelot Tracked Recipes & Shopping List
    frames/quests/modules/q_camelot_recipes.lua

    Pluggable tracker module for Warcraft Forever (Camelot) & Classic Era.
    Displays pinned recipes with live reagent bag counts, acquisition source info,
    waypoint tracking, and direct router to the SFUI Recipe Catalog.
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
    return pinned[spellID] == true or pinned[tostring(spellID)] == true
end

function sfui.recipes.TogglePinRecipe(spellID)
    spellID = tonumber(spellID) or spellID
    if not spellID then return false end
    local pinned = GetPinnedStorage()
    local isPinned = not sfui.recipes.IsRecipePinned(spellID)

    if isPinned then
        pinned[spellID] = true
        pinned[tostring(spellID)] = nil
    else
        pinned[spellID] = nil
        pinned[tostring(spellID)] = nil
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
        "BAG_UPDATE",
        "BAG_UPDATE_DELAYED",
        "PLAYER_ENTERING_WORLD",
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
end

function CamelotRecipesModule:BuildBlocks(container)
    local pinned = GetPinnedStorage()
    if not pinned or not next(pinned) then
        return nil
    end

    local db = sfui.recipes_camelot and sfui.recipes_camelot.recipes
    if not db then
        return nil
    end

    local recipeList = {}
    for id, isPinned in pairs(pinned) do
        if isPinned then
            local numID = tonumber(id)
            local r = numID and db[numID]
            if r then
                table_insert(recipeList, r)
            end
        end
    end

    if #recipeList == 0 then
        return nil
    end

    table_sort(recipeList, function(a, b)
        return (a.name or "") < (b.name or "")
    end)

    local blocks = {}

    for _, r in ipairs(recipeList) do
        local spellID = r.id
        local lines = {}
        local allReagentsMet = true
        local hasReagents = false

        -- 1. Source Line
        local firstSource = sfui.recipes.GetFirstNonHostileSource and sfui.recipes.GetFirstNonHostileSource(r)
        if not firstSource and r.sources and r.sources[1] then
            firstSource = r.sources[1]
        end

        if firstSource then
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
        if r.reagents and next(r.reagents) then
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
        local prefix = isComplete and "[ready] " or "[recipe] "
        local displayName = prefix .. (r.name or "unknown recipe"):lower()

        table_insert(blocks, {
            id         = "rec_" .. tostring(spellID),
            title      = displayName,
            titleColor = titleColor,
            lines      = lines,
            OnClick    = function(block, btn)
                if btn == "RightButton" or (IsShiftKeyDown and IsShiftKeyDown()) then
                    sfui.recipes.TogglePinRecipe(spellID)
                    return
                end
                sfui.recipes.OpenBrowserToRecipe(spellID)
            end,
            tooltip    = function(tip, owner, bData)
                tip:AddLine(r.name or "Recipe", titleColor[1], titleColor[2], titleColor[3])
                if r.profession then
                    local minSkill = r.minSkill or (r.colors and r.colors[1]) or 0
                    tip:AddLine(string_format("%s (rank %d)", r.profession:lower(), minSkill), 0.70, 0.70, 0.70)
                end
                if isComplete then
                    tip:AddLine("all required crafting materials collected", 0.20, 1.00, 0.35, true)
                elseif hasReagents then
                    tip:AddLine("crafting materials incomplete", 1.00, 0.72, 0.35, true)
                end
                tip:AddLine(" ")
                tip:AddLine("|cff888888left-click: open in recipe catalog|r", 1, 1, 1)
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
