local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.recipes = sfui.recipes or {}

local g      = sfui.config
local common = sfui.common
local cfg    = g.recipes or g.professions or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/professions/tooltips.lua
--  Recipe Source Tooltip & Waypoint Integration (Camelot / Classic Forever)
--
--  Renders "where to get it" source annotations (trainers, vendors, drops, quests)
--  on recipe scrolls, crafted items, and inside Blizzard's ProfessionsFrame.
--  Provides click-to-pin and Ctrl-click map waypoint navigation.
-- ══════════════════════════════════════════════════════════════════════════════

if not sfui.isCamelot then return end

-- Localized APIs
local GameTooltip                   = sfui.common.get_tooltip()
local ItemRefTooltip                = _G.ItemRefTooltip
local TooltipDataProcessor          = _G.TooltipDataProcessor
local Enum                          = _G.Enum or {}
local hooksecurefunc                = _G.hooksecurefunc
local IsControlKeyDown              = _G.IsControlKeyDown
local tonumber, tostring            = _G.tonumber, _G.tostring
local pairs, ipairs                 = _G.pairs, _G.ipairs
local min                           = math.min

local MAX_SOURCE_LINES = 3

--- Check if an item is a recipe scroll or recipe-related item
local function OnItemTooltip(tooltip, data)
    if not tooltip or not tooltip.AddLine then return end
    if tooltip.sfuiRecipeSourceDone then return end

    local itemID = nil
    if data and data.id then
        itemID = data.id
    else
        local _, link = tooltip:GetItem()
        if link then
            itemID = tonumber(link:match("item:(%d+)"))
        end
    end

    if not itemID then return end

    local res = sfui.recipes.GetSource(itemID)
    if not res or not res.sources or #res.sources == 0 then return end

    -- Mark to avoid duplicate runs on the same tooltip display cycle
    tooltip.sfuiRecipeSourceDone = true

    tooltip:AddLine(" ")
    tooltip:AddLine("|cffffd100where to get it:|r", 1, 1, 1)

    if res.spec then
        tooltip:AddLine(string.format("  |cffffa500requires:|r %s", res.spec), 1, 0.8, 0)
    end
    if res.faction and res.standing then
        local repStr = string.format("  |cff80c0ffreputation:|r %s with %s", res.standing, res.faction)
        if res.tokens then
            repStr = repStr .. string.format(" (%s)", res.tokens)
        end
        tooltip:AddLine(repStr, 0.5, 0.8, 1)
    end

    local bestWaypoint = nil
    local count = min(#res.sources, MAX_SOURCE_LINES)

    for i = 1, count do
        local s = res.sources[i]
        local line, hasCoords = sfui.recipes.FormatSourceLine(s, res)
        if line ~= "" then
            tooltip:AddLine("  " .. line, 0.85, 0.85, 0.85, true)
        end
        if hasCoords and not bestWaypoint then
            bestWaypoint = s
        end
    end

    if #res.sources > MAX_SOURCE_LINES then
        tooltip:AddLine(string.format("  |cff888888+%d more locations|r", #res.sources - MAX_SOURCE_LINES), 0.6, 0.6, 0.6)
    end

    if bestWaypoint then
        tooltip._sfuiRecipeWaypoint = bestWaypoint
        tooltip:AddLine("|cff80c0ffctrl-click to set map waypoint|r", 0.5, 0.8, 1)
    end

    tooltip:Show()
end

local function ClearTooltip(tooltip)
    if tooltip then
        tooltip.sfuiRecipeSourceDone = nil
        tooltip._sfuiRecipeWaypoint = nil
        tooltip._sfuiInRecipeBrowser = nil
    end
end

-- ── Tooltip Registration (TooltipDataProcessor & Fallbacks) ───────────────────
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
        OnItemTooltip(tt, data)
    end)
else
    if GameTooltip then
        GameTooltip:HookScript("OnTooltipSetItem", function(tt) OnItemTooltip(tt) end)
        GameTooltip:HookScript("OnTooltipCleared", ClearTooltip)
    end
    if ItemRefTooltip then
        ItemRefTooltip:HookScript("OnTooltipSetItem", function(tt) OnItemTooltip(tt) end)
        ItemRefTooltip:HookScript("OnTooltipCleared", ClearTooltip)
    end
end

if GameTooltip then
    GameTooltip:HookScript("OnTooltipCleared", ClearTooltip)
end
if ItemRefTooltip then
    ItemRefTooltip:HookScript("OnTooltipCleared", ClearTooltip)
end

-- ── Ctrl-Click Item Link -> Waypoint Hook ─────────────────────────────────────
if hooksecurefunc then
    hooksecurefunc("HandleModifiedItemClick", function(link)
        if not link or not IsControlKeyDown() then return end
        local itemID = tonumber(link:match("item:(%d+)"))
        if itemID then
            local res = sfui.recipes.GetSource(itemID)
            if res and res.sources then
                for _, s in ipairs(res.sources) do
                    if s.mapID and s.x and s.y then
                        sfui.recipes.SetWaypoint(s)
                        break
                    end
                end
            end
        end
    end)
end

-- ── ProfessionsFrame / SchematicForm Integration (Camelot) ───────────────────
local function HookSchematicForm()
    local Mixin = _G.ProfessionsRecipeSchematicFormMixin
    if not Mixin or Mixin._sfuiHooked then return end
    Mixin._sfuiHooked = true

    hooksecurefunc(Mixin, "Init", function(self, recipeInfo)
        if not recipeInfo or recipeInfo.learned then return end
        local recipeID = recipeInfo.recipeID
        if not recipeID then return end

        local res = sfui.recipes.GetSource(recipeID)
        if not res or not res.sources or #res.sources == 0 then return end

        if self.RecipeSourceButton then
            if self.RecipeSourceButton.Text then
                self.RecipeSourceButton.Text:SetText("unlearned recipe")
            end
            self.RecipeSourceButton:Show()

            local bestSource = nil
            for _, s in ipairs(res.sources) do
                if s.mapID and s.x and s.y then
                    bestSource = s
                    break
                end
            end
            bestSource = bestSource or res.sources[1]

            self.RecipeSourceButton:SetScript("OnEnter", function(btn)
                GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                GameTooltip:SetCustomWordWrapMinWidth(320)
                GameTooltip:AddLine("|cffffd100where to get it:|r", 1, 1, 1)

                if res.spec then
                    GameTooltip:AddLine(string.format("  |cffffa500requires:|r %s", res.spec), 1, 0.8, 0)
                end
                if res.faction and res.standing then
                    local repStr = string.format("  |cff80c0ffreputation:|r %s with %s", res.standing, res.faction)
                    if res.tokens then
                        repStr = repStr .. string.format(" (%s)", res.tokens)
                    end
                    GameTooltip:AddLine(repStr, 0.5, 0.8, 1)
                end

                local count = min(#res.sources, 4)
                for idx = 1, count do
                    local s = res.sources[idx]
                    local line = sfui.recipes.FormatSourceLine(s, res)
                    if line ~= "" then
                        GameTooltip:AddLine("  " .. line, 0.9, 0.9, 0.9, true)
                    end
                end

                if #res.sources > 4 then
                    GameTooltip:AddLine(string.format("  |cff888888+%d more locations|r", #res.sources - 4), 0.6, 0.6, 0.6)
                end

                if bestSource and bestSource.mapID and bestSource.x and bestSource.y then
                    GameTooltip:AddLine("|cff80c0ffclick to set map waypoint|r", 0.5, 0.8, 1)
                end
                GameTooltip:Show()
            end)

            self.RecipeSourceButton:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            self.RecipeSourceButton:SetScript("OnClick", function()
                if bestSource then
                    sfui.recipes.SetWaypoint(bestSource)
                end
            end)
        end
    end)
end

-- Try immediately if Blizzard_Professions is already loaded
HookSchematicForm()

-- Also hook on ADDON_LOADED via sfui.events
if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("ADDON_LOADED", function(event, loadedAddon)
        if loadedAddon == "Blizzard_Professions" or loadedAddon == "Blizzard_ProfessionsTemplates" then
            HookSchematicForm()
        end
    end)
end
