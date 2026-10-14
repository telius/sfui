local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/map/providers/pins_recipes.lua
--  WorldMap Pin Provider: Camelot Recipe Compendium
-- ══════════════════════════════════════════════════════════════════════════════

if sfui.isRetail then return end

local pins = sfui.pins
if not pins then return end

local _G                  = _G
local GameTooltip         = sfui.common.get_tooltip()
local IsControlKeyDown    = _G.IsControlKeyDown
local ipairs              = _G.ipairs
local string_format       = string.format
local table_insert        = _G.table.insert
local table_sort          = _G.table.sort

-- ─── Configuration & Options ──────────────────────────────────────────────────
sfui.recipes = sfui.recipes or {}
sfui.recipes.pins = sfui.recipes.pins or {}

function sfui.recipes.pins.GetOption(key)
    if sfui.db and sfui.db.Get then
        local val = sfui.db.Get("recipe_catalog", key)
        if val ~= nil then return val end
    end
    if key == "showMapPins" and SfuiDB and SfuiDB.recipesShowMapPins ~= nil then
        return SfuiDB.recipesShowMapPins ~= false
    end
    return true
end

function sfui.recipes.pins.SetOption(key, val)
    if sfui.db and sfui.db.Set then
        sfui.db.Set("recipe_catalog", key, val)
    end
    if SfuiDB and key == "showMapPins" then
        SfuiDB.recipesShowMapPins = val and true or false
    end
    pins.RequestRefresh(0)
end

sfui.recipes.GetOption = sfui.recipes.pins.GetOption
sfui.recipes.SetOption = sfui.recipes.pins.SetOption
function sfui.recipes.pins.GetActiveCount() return pins.GetActiveCount("recipes") end
function sfui.recipes.pins.UpdatePins() pins.RequestRefresh(0) end

-- ─── Source Type Color Palette & Icons ────────────────────────────────────────
local SOURCE_COLORS = {
    vendor  = { 0.20, 1.00, 0.55, 1.0 },
    trainer = { 0.20, 0.85, 1.00, 1.0 },
    quest   = { 1.00, 0.85, 0.20, 1.0 },
    drop    = { 1.00, 0.55, 0.20, 1.0 },
}

local SOURCE_ICONS = {
    vendor  = "Interface\\Icons\\INV_Scroll_03",
    trainer = "Interface\\Icons\\INV_Misc_Book_09",
    quest   = "Interface\\GossipFrame\\AvailableQuestIcon",
    drop    = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
}

-- ─── Interactive Tooltip Handlers ─────────────────────────────────────────────
local function OnEnterRecipePin(pin, tooltip, pinData)
    local group = pinData.group
    if not group or not group.recipes or #group.recipes == 0 then return end

    tooltip:SetOwner(pin, "ANCHOR_RIGHT")
    tooltip:ClearLines()

    local col = SOURCE_COLORS[group.type] or { 1, 1, 1, 1 }
    local typeLabel = (group.type or "source"):lower()
    local npcLabel = (group.name or "npc"):lower()

    tooltip:AddLine(string_format("%s  ·  %s", npcLabel, typeLabel), col[1], col[2], col[3])

    local locStr = group.zone or ""
    if group.x and group.y then
        locStr = string_format("%s (%.1f, %.1f)", locStr ~= "" and locStr or "map", group.x * 100, group.y * 100)
    end
    if locStr ~= "" then tooltip:AddLine(locStr, 0.70, 0.70, 0.70) end

    tooltip:AddLine(" ")
    local numRec = #group.recipes
    tooltip:AddLine(string_format("available unlearned %s (%d):", numRec > 1 and "recipes" or "recipe", numRec), 1, 0.85, 0.20)

    local maxDisplay = 10
    for idx, item in ipairs(group.recipes) do
        if idx > maxDisplay then
            local rem = numRec - maxDisplay
            tooltip:AddLine(string_format("  |cff888888... and %d more|r", rem), 0.7, 0.7, 0.7)
            break
        end

        local r = item.recipe
        local s = item.source
        local minSkill = r.minSkill or (r.colors and r.colors[1]) or 0
        local costFormatted = (s and s.cost and sfui.recipes.FormatMoneyShort) and sfui.recipes.FormatMoneyShort(s.cost)
        local costStr = costFormatted and (" - " .. costFormatted) or ""
        local rName = r.name and r.name:lower() or "recipe"
        local isPinned = sfui.recipes.IsRecipePinned and sfui.recipes.IsRecipePinned(r.id)
        local pinTag = isPinned and " |cffffd100[pinned]|r" or ""

        tooltip:AddLine(string_format("  • %s |cff888888(rank %d)%s|r%s", rName, minSkill, costStr, pinTag), 0.90, 0.90, 0.95, true)
    end

    tooltip:AddLine(" ")
    tooltip:AddLine("|cff00ff88left-click: open recipe catalogue|r", 1, 1, 1)
    tooltip:AddLine("|cff80c0ffshift-click: set map waypoint with super-tracking|r", 1, 1, 1)
    tooltip:AddLine("|cff00e5ffctrl-click: track in objective tracker|r", 1, 1, 1)
    tooltip:Show()
end

local function OnClickRecipePin(pin, mouseBtn, pinData)
    local group = pinData.group
    if not group then return end

    if IsControlKeyDown() then
        if group.recipes and #group.recipes > 0 and sfui.recipes and sfui.recipes.TogglePinRecipe then
            local first = group.recipes[1]
            if first and first.recipe and first.recipe.id then
                sfui.recipes.TogglePinRecipe(first.recipe.id)
                if GameTooltip and GameTooltip:IsShown() then
                    OnEnterRecipePin(pin, GameTooltip, pinData)
                end
            end
        end
        return
    end

    if sfui.recipes and sfui.recipes.OpenBrowserForVendor and group.name then
        sfui.recipes.OpenBrowserForVendor(group.name)
    elseif sfui.recipes and sfui.recipes.OpenBrowser then
        sfui.recipes.OpenBrowser()
    end
end

-- ─── Provider Implementation ──────────────────────────────────────────────────
local function GetRecipePins(mapID, playerLevel, playerFaction)
    if not sfui.recipes.pins.GetOption("showMapPins") then return nil end
    local B = sfui.recipes.browser
    local profList = (B and B.GetPlayerProfessionsList and B.GetPlayerProfessionsList()) or {}
    if #profList == 0 then return nil end

    local mapGroups = {}
    local groupOrder = {}

    for _, p in ipairs(profList) do
        local currentRank = p.rank or 0
        local candidates = B and B.GetCandidatesForSkill and B.GetCandidatesForSkill(p.skillID)

        if candidates then
            for _, r in ipairs(candidates) do
                local isLearned = B.IsRecipeLearned and B.IsRecipeLearned(r.id, r)
                if not isLearned then
                    local minSkill = r.minSkill or (r.colors and r.colors[1]) or 0
                    if currentRank >= minSkill then
                        local passSpec = true
                        if r.spec and B.PlayerHasSpec then passSpec = B.PlayerHasSpec(r.spec) end

                        if passSpec then
                            local sources = sfui.recipes.GetAllNonHostileSources and sfui.recipes.GetAllNonHostileSources(r)
                            if sources then
                                for _, s in ipairs(sources) do
                                    if s.mapID == mapID and s.x and s.y then
                                        local groupKey = string_format("%.4f:%.4f:%s", s.x, s.y, s.name or s.desc or s.type or "npc")
                                        local g = mapGroups[groupKey]
                                        if not g then
                                            g = {
                                                mapID   = s.mapID,
                                                x       = s.x,
                                                y       = s.y,
                                                name    = s.name or s.desc or s.type or "source",
                                                type    = s.type or "vendor",
                                                zone    = s.zone,
                                                recipes = {},
                                            }
                                            mapGroups[groupKey] = g
                                            table_insert(groupOrder, g)
                                        end
                                        table_insert(g.recipes, { recipe = r, source = s })
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if #groupOrder == 0 then return nil end
    local out = {}

    for _, g in ipairs(groupOrder) do
        local col = SOURCE_COLORS[g.type] or { 0.20, 0.85, 1.00, 1.0 }
        local iconPath = SOURCE_ICONS[g.type] or SOURCE_ICONS.vendor

        table_sort(g.recipes, function(a, b)
            local skA = a.recipe.minSkill or (a.recipe.colors and a.recipe.colors[1]) or 0
            local skB = b.recipe.minSkill or (b.recipe.colors and b.recipe.colors[1]) or 0
            if skA ~= skB then return skA < skB end
            return (a.recipe.name or "") < (b.recipe.name or "")
        end)

        local numRecipes = #g.recipes
        table_insert(out, {
            id          = "recipe_" .. string_format("%.4f:%.4f:%s", g.x, g.y, g.name or "src"),
            provider    = "recipes",
            mapID       = g.mapID,
            x           = g.x,
            y           = g.y,
            size        = 18,
            icon        = iconPath,
            texCoord    = { 0.08, 0.92, 0.08, 0.92 },
            borderColor = { col[1], col[2], col[3], 0.90 },
            count       = (numRecipes > 1 and numRecipes) or nil,
            title       = g.name or "recipe source",
            group       = g,
            OnEnter     = OnEnterRecipePin,
            OnClick     = OnClickRecipePin,
        })
    end

    return out
end

-- ─── Provider & Menu Registration ─────────────────────────────────────────────
pins.RegisterProvider("recipes", {
    priority    = 25,
    defaultSize = 18,
    enabled     = function() return sfui.recipes.pins.GetOption("showMapPins") end,
    GetPins     = GetRecipePins,
})

pins.RegisterTrackingCategory("recipe catalogue", {
    { text = "available unlearned recipes", get = function() return sfui.recipes.pins.GetOption("showMapPins") end, set = function(v) sfui.recipes.pins.SetOption("showMapPins", v) end },
})

if sfui.events and sfui.events.RegisterMessage then
    sfui.events.RegisterMessage("SFUI_RECIPE_PINNED_CHANGED", function()
        pins.RequestRefresh(0)
    end)
end
