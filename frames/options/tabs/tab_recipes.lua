local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.options = sfui.options or {}

local g      = sfui.config
local common = sfui.common

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/options/tabs/tab_recipes.lua
--  Recipes, Professions & Reagent Tooltip Options Panel
-- ══════════════════════════════════════════════════════════════════════════════

local CreateFrame   = _G.CreateFrame
local pairs         = _G.pairs
local ipairs        = _G.ipairs
local type          = _G.type
local tonumber      = _G.tonumber
local table_insert  = table.insert
local table_concat  = table.concat
local string_format = string.format

local function create_section_divider(parent, anchorFrame, offsetY)
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, offsetY or -12)
    sep:SetPoint("RIGHT", parent, "RIGHT", -15, 0)
    sep:SetColorTexture(0.2, 0.2, 0.28, 0.9)
    return sep
end

local function invalidate_all_recipe_caches()
    if sfui.recipes then
        if sfui.recipes.InvalidateCache then
            sfui.recipes.InvalidateCache()
        end
        if sfui.recipes.InvalidateReagentCache then
            sfui.recipes.InvalidateReagentCache()
        end
        if sfui.recipes.RequestUpdateAllItems then
            sfui.recipes.RequestUpdateAllItems()
        end
    end
end

local function count_table_keys(tbl)
    if type(tbl) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(tbl) do n = n + 1 end
    return n
end

local function count_pinned_recipes()
    local count = 0
    if SfuiDB and type(SfuiDB.pinned_recipes) == "table" then
        for _, v in pairs(SfuiDB.pinned_recipes) do
            if v then count = count + 1 end
        end
    end
    return count
end

sfui.options.RegisterTab({
    id   = "recipes",
    name = "recipes",
    icon = "Interface\\Icons\\INV_Scroll_03",
    build = function(panel)
        SfuiDB = SfuiDB or {}
        local create_checkbox     = common.create_checkbox
        local create_slider_input = common.create_slider_input
        local create_flat_button  = common.create_flat_button
        local white              = g.colors.white
        local accent             = g.appearance.highlightColor
        local isRetail           = sfui.isRetail

        local COL_OFFSET_X = 265

        -- ── 1. Header & Quick Actions ─────────────────────────────────────────
        local header = panel:CreateFontString(nil, "OVERLAY", g.font_large or g.font)
        header:SetPoint("TOPLEFT", 15, -14)
        header:SetTextColor(white[1], white[2], white[3])
        header:SetText("recipes & professions")

        local subtext = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        subtext:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
        subtext:SetTextColor(0.65, 0.65, 0.72)
        subtext:SetText("controls cross-alt recipe knowledge, reagent usage tooltips, acquisition sources & world map pins.")

        local first_btn = nil
        local prev_btn  = nil

        if not isRetail then
            local open_browser_btn = create_flat_button(panel, "open recipe browser", 136, 20, function()
                if sfui.recipes and sfui.recipes.ToggleBrowser then
                    sfui.recipes.ToggleBrowser()
                end
            end)
            open_browser_btn:SetPoint("TOPLEFT", subtext, "BOTTOMLEFT", 0, -10)
            open_browser_btn.tooltip = "opens the searchable recipe catalogue with trainer, vendor, quest, and drop locations (/recipes)."
            first_btn = open_browser_btn
            prev_btn  = open_browser_btn
        end

        local rescan_btn = create_flat_button(panel, "rescan professions", 128, 20, function()
            if sfui.recipes then
                if sfui.recipes.PruneOrphanCrafts then
                    sfui.recipes.PruneOrphanCrafts()
                end
                if sfui.recipes.ScanKnownRecipesFromCatalog then
                    sfui.recipes.ScanKnownRecipesFromCatalog()
                end
                if sfui.recipes.ScanCurrentTradeSkills then
                    sfui.recipes.ScanCurrentTradeSkills(true)
                end
            end
            invalidate_all_recipe_caches()
            if panel.RefreshRecipesUI then panel.RefreshRecipesUI() end
            if common and common.print then
                common.print("professions & recipe caches rescanned.")
            end
        end)
        if prev_btn then
            rescan_btn:SetPoint("LEFT", prev_btn, "RIGHT", 7, 0)
        else
            rescan_btn:SetPoint("TOPLEFT", subtext, "BOTTOMLEFT", 0, -10)
            first_btn = rescan_btn
        end
        rescan_btn.tooltip = "rescans learned professions and recipes on the active character and clears cached tooltip lines."
        prev_btn = rescan_btn

        if not isRetail then
            local clear_pins_btn = create_flat_button(panel, "clear pinned recipes", 128, 20, function()
                local cleared = 0
                if sfui.recipes and sfui.recipes.ClearPinnedRecipes then
                    cleared = sfui.recipes.ClearPinnedRecipes() or 0
                elseif SfuiDB and type(SfuiDB.pinned_recipes) == "table" then
                    for k in pairs(SfuiDB.pinned_recipes) do
                        SfuiDB.pinned_recipes[k] = nil
                        cleared = cleared + 1
                    end
                end
                if panel.RefreshRecipesUI then panel.RefreshRecipesUI() end
                if common and common.print then
                    common.print(string_format("cleared %d pinned recipe(s).", cleared))
                end
            end)
            clear_pins_btn:SetPoint("LEFT", prev_btn, "RIGHT", 7, 0)
            clear_pins_btn.tooltip = "unpins all locally tracked recipes from the objective tracker shopping list."
            prev_btn = clear_pins_btn
        end

        local reset_btn = create_flat_button(panel, "reset defaults", 104, 20, function()
            if panel.ResetRecipeDefaults then
                panel.ResetRecipeDefaults()
            end
        end)
        reset_btn:SetPoint("LEFT", prev_btn, "RIGHT", 7, 0)
        reset_btn.tooltip = "restores all recipe, reagent tooltip, and world map pin settings to their defaults."

        -- Live Status Summary Card
        local status_box = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        status_box:SetPoint("TOPLEFT", first_btn, "BOTTOMLEFT", 0, -8)
        status_box:SetPoint("RIGHT", panel, "RIGHT", -15, 0)
        status_box:SetHeight(42)
        common.apply_flat_backdrop(status_box, { 0.05, 0.05, 0.08, 0.85 }, { 0.2, 0.2, 0.28, 1 })

        local status_line1 = status_box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        status_line1:SetPoint("TOPLEFT", status_box, "TOPLEFT", 10, -7)
        status_line1:SetPoint("RIGHT", status_box, "RIGHT", -10, 0)
        status_line1:SetJustifyH("LEFT")

        local status_line2 = status_box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        status_line2:SetPoint("TOPLEFT", status_line1, "BOTTOMLEFT", 0, -5)
        status_line2:SetPoint("RIGHT", status_box, "RIGHT", -10, 0)
        status_line2:SetJustifyH("LEFT")

        local anchor_after_status = status_box

        -- ── 2. Reagent Usage Tooltips (Camelot / Classic) ─────────────────────
        local cb_reagent_uses, cb_reagent_alts, cb_reagent_learn, sl_reagent_max
        if not isRetail then
            local sep_reag = create_section_divider(panel, anchor_after_status, -10)

            local reag_header = panel:CreateFontString(nil, "OVERLAY", g.font)
            reag_header:SetPoint("TOPLEFT", sep_reag, "BOTTOMLEFT", 0, -10)
            reag_header:SetTextColor(accent[1], accent[2], accent[3])
            reag_header:SetText("reagent usage tooltips ('used in')")

            cb_reagent_uses = create_checkbox(panel, "show reagent usage in tooltips",
                function() return SfuiDB.recipesShowReagentUses ~= false end,
                function(v)
                    SfuiDB.recipesShowReagentUses = v
                    invalidate_all_recipe_caches()
                end,
                "shows which recipes consume a reagent item on item tooltips, grouped by profession with difficulty colors and stack counts.")
            cb_reagent_uses:SetPoint("TOPLEFT", reag_header, "BOTTOMLEFT", 0, -8)

            cb_reagent_alts = create_checkbox(panel, "include synced alts' professions",
                function() return SfuiDB.recipesReagentShowAlts ~= false end,
                function(v)
                    SfuiDB.recipesReagentShowAlts = v
                    invalidate_all_recipe_caches()
                end,
                "includes professions and recipe knowledge from all characters in your alt roster (local and synced accounts) on reagent tooltips.")
            cb_reagent_alts:SetPoint("LEFT", cb_reagent_uses, "LEFT", COL_OFFSET_X, 0)

            cb_reagent_learn = create_checkbox(panel, "show 'can learn' without holding shift",
                function() return SfuiDB.recipesReagentShowCanLearn ~= false end,
                function(v)
                    SfuiDB.recipesReagentShowCanLearn = v
                    invalidate_all_recipe_caches()
                end,
                "shows unlearned recipes that your characters already have the skill rank to learn in the default collapsed view. holding shift always expands all recipes.")
            cb_reagent_learn:SetPoint("TOPLEFT", cb_reagent_uses, "BOTTOMLEFT", 0, -6)

            sl_reagent_max = create_slider_input(panel, "max recipes per profession:",
                function() return tonumber(SfuiDB.recipesReagentMaxLines) or 4 end,
                1, 15, 1,
                function(v)
                    SfuiDB.recipesReagentMaxLines = v
                    invalidate_all_recipe_caches()
                end,
                "maximum number of recipes shown per profession on a reagent tooltip before holding shift to expand.",
                230)
            sl_reagent_max:SetPoint("TOPLEFT", cb_reagent_learn, "BOTTOMLEFT", 0, -8)

            anchor_after_status = sl_reagent_max
        end

        -- ── 3. Recipe Scrolls, Crafted Items & Bag Icons ──────────────────────
        local sep_rec = create_section_divider(panel, anchor_after_status, -10)

        local rec_header = panel:CreateFontString(nil, "OVERLAY", g.font)
        rec_header:SetPoint("TOPLEFT", sep_rec, "BOTTOMLEFT", 0, -10)
        rec_header:SetTextColor(accent[1], accent[2], accent[3])
        rec_header:SetText("recipe scrolls, crafted items & bag icons")

        local cb_known = create_checkbox(panel, "show 'known by' on recipes",
            function() return SfuiDB.recipesShowKnown ~= false end,
            function(v) SfuiDB.recipesShowKnown = v end,
            "shows which characters already know a recipe when hovering recipe scrolls.")
        cb_known:SetPoint("TOPLEFT", rec_header, "BOTTOMLEFT", 0, -8)

        local cb_can_learn = create_checkbox(panel, "show 'can learn' on recipes",
            function() return SfuiDB.recipesShowCanLearn ~= false end,
            function(v) SfuiDB.recipesShowCanLearn = v end,
            "shows which characters have the profession and required skill rank to learn a recipe immediately.")
        cb_can_learn:SetPoint("LEFT", cb_known, "LEFT", COL_OFFSET_X, 0)

        local cb_needs_skill = create_checkbox(panel, "show 'needs skill' on recipes",
            function() return SfuiDB.recipesShowNeedsSkill ~= false end,
            function(v) SfuiDB.recipesShowNeedsSkill = v end,
            "shows which characters have the matching profession for a recipe but need a higher skill rank.")
        cb_needs_skill:SetPoint("TOPLEFT", cb_known, "BOTTOMLEFT", 0, -6)

        local cb_craftable = create_checkbox(panel, "show 'craftable by' on crafted items",
            function() return SfuiDB.recipesShowCraftable ~= false end,
            function(v) SfuiDB.recipesShowCraftable = v end,
            "shows which of your characters can craft an item when hovering the finished item.")
        cb_craftable:SetPoint("LEFT", cb_needs_skill, "LEFT", COL_OFFSET_X, 0)

        local cb_tint = create_checkbox(panel, "tint recipe icons in bags & merchants",
            function() return SfuiDB.recipesTintIcons ~= false end,
            function(v)
                SfuiDB.recipesTintIcons = v
                invalidate_all_recipe_caches()
            end,
            "tints recipe scroll icons in bags and merchant frames by learnability (green = learnable now, cyan = alt can learn, orange = needs skill, grey = already known).")
        cb_tint:SetPoint("TOPLEFT", cb_needs_skill, "BOTTOMLEFT", 0, -6)

        local sl_max_alts = create_slider_input(panel, "max characters per tooltip line:",
            function() return tonumber(SfuiDB.recipesMaxAlts) or 4 end,
            1, 10, 1,
            function(v) SfuiDB.recipesMaxAlts = v end,
            "maximum character names shown on 'known by', 'can learn', 'needs skill', and 'craftable by' lines before '+n more'.",
            230)
        sl_max_alts:SetPoint("TOPLEFT", cb_tint, "BOTTOMLEFT", 0, -8)

        -- ── 4. Sources, World Map & Objective Tracker (Camelot / Classic) ─────
        local cb_sources, cb_map_pins, cb_track_pinned, cb_sync_recipes
        if not isRetail then
            local sep_map = create_section_divider(panel, sl_max_alts, -10)

            local map_header = panel:CreateFontString(nil, "OVERLAY", g.font)
            map_header:SetPoint("TOPLEFT", sep_map, "BOTTOMLEFT", 0, -10)
            map_header:SetTextColor(accent[1], accent[2], accent[3])
            map_header:SetText("acquisition sources, world map & objective tracker")

            cb_sources = create_checkbox(panel, "show 'where to get it' on tooltips",
                function() return SfuiDB.recipesShowSources ~= false end,
                function(v) SfuiDB.recipesShowSources = v end,
                "shows vendor, trainer, quest, and drop locations on recipe tooltips and inside the profession window (ctrl-click to open in recipe browser).")
            cb_sources:SetPoint("TOPLEFT", map_header, "BOTTOMLEFT", 0, -8)

            cb_map_pins = create_checkbox(panel, "show unlearned recipe pins on world map",
                function()
                    if sfui.recipes and sfui.recipes.pins and sfui.recipes.pins.GetOption then
                        return sfui.recipes.pins.GetOption("showMapPins")
                    end
                    return SfuiDB.recipesShowMapPins ~= false
                end,
                function(v)
                    SfuiDB.recipesShowMapPins = v
                    if sfui.recipes and sfui.recipes.pins and sfui.recipes.pins.SetOption then
                        sfui.recipes.pins.SetOption("showMapPins", v)
                    end
                end,
                "displays icons on the world map for trainers, vendors, quests, and drops offering unlearned recipes your character can currently learn.")
            cb_map_pins:SetPoint("LEFT", cb_sources, "LEFT", COL_OFFSET_X, 0)

            cb_track_pinned = create_checkbox(panel, "track pinned recipes in objective tracker",
                function() return SfuiDB.recipesTrackPinned ~= false end,
                function(v)
                    SfuiDB.recipesTrackPinned = v
                    if sfui.tracker and sfui.tracker.RequestRefresh then
                        sfui.tracker.RequestRefresh(0)
                    end
                end,
                "displays pinned recipes and live reagent shopping lists in the sfui objective tracker.")
            cb_track_pinned:SetPoint("TOPLEFT", cb_sources, "BOTTOMLEFT", 0, -6)

            cb_sync_recipes = create_checkbox(panel, "sync recipes & shopping list with peers",
                function()
                    if sfui.sync and sfui.sync.GetSettings then
                        return sfui.sync.GetSettings().syncRecipes ~= false
                    end
                    return true
                end,
                function(v)
                    if sfui.db and sfui.db.Set then
                        sfui.db.Set("sync", "syncRecipes", v)
                    elseif sfui.sync and sfui.sync.GetSettings then
                        sfui.sync.GetSettings().syncRecipes = v
                    end
                    if sfui.tracker and sfui.tracker.RequestRefresh then
                        sfui.tracker.RequestRefresh(0.02)
                    end
                end,
                "synchronizes known recipes and pinned recipe reagent shopping lists across linked accounts.")
            cb_sync_recipes:SetPoint("LEFT", cb_track_pinned, "LEFT", COL_OFFSET_X, 0)
        end

        -- ── 5. Refresh & Reset Handlers ───────────────────────────────────────
        function panel.RefreshRecipesUI()
            -- Line 1: Active character professions + pinned recipe count
            local profParts = {}
            local B = sfui.recipes and sfui.recipes.browser
            local profs = (B and B.GetPlayerProfessionsList and B.GetPlayerProfessionsList()) or nil
            if profs and #profs > 0 then
                for _, p in ipairs(profs) do
                    local pName = (p.name or "profession"):lower()
                    if (p.maxRank or 0) > 0 then
                        table_insert(profParts, string_format("|cff00e5ff%s|r (%d/%d)", pName, p.rank or 0, p.maxRank or 0))
                    else
                        table_insert(profParts, string_format("|cff00e5ff%s|r", pName))
                    end
                end
            else
                local myGUID = _G.UnitGUID and _G.UnitGUID("player")
                local myAlt = myGUID and SfuiDB.alts and SfuiDB.alts[myGUID]
                if myAlt and type(myAlt.professions) == "table" then
                    for _, prof in pairs(myAlt.professions) do
                        if type(prof) == "table" and prof.name then
                            table_insert(profParts, string_format("|cff00e5ff%s|r (%d/%d)", prof.name:lower(), prof.rank or 0, prof.maxRank or 0))
                        end
                    end
                end
            end

            local profSummary = (#profParts > 0) and table_concat(profParts, ", ") or "|cff888888none learned|r"
            local pinnedCount = count_pinned_recipes()
            status_line1:SetText(string_format("active professions: %s   |cff555566·|r   pinned recipes: |cffffd100%d|r", profSummary, pinnedCount))

            -- Line 2: Alt roster, reagent index & discovered contacts
            local altCount = count_table_keys(SfuiDB.alts)
            local knownRecs = count_table_keys(SfuiDB.recipes)
            local dbg = sfui.recipes and sfui.recipes.reagents and sfui.recipes.reagents.GetDebugInfo and sfui.recipes.reagents.GetDebugInfo()
            local reagText = (dbg and dbg.indexBuilt) and string_format("%d items", dbg.reagents or 0) or "lazy (on hover)"
            local vendors = SfuiDB.contacts and count_table_keys(SfuiDB.contacts.vendors) or 0
            local trainers = SfuiDB.contacts and count_table_keys(SfuiDB.contacts.trainers) or 0

            status_line2:SetText(string_format(
                "tracked characters: |cff00ff88%d|r   |cff555566·|r   known recipe ids: |cff00ff88%d|r   |cff555566·|r   reagent index: |cff80c0ff%s|r   |cff555566·|r   contacts: |cffcccccc%dv / %dt|r",
                altCount, knownRecs, reagText, vendors, trainers
            ))

            -- Sync widget states
            if cb_reagent_uses then cb_reagent_uses:SetChecked(SfuiDB.recipesShowReagentUses ~= false) end
            if cb_reagent_alts then cb_reagent_alts:SetChecked(SfuiDB.recipesReagentShowAlts ~= false) end
            if cb_reagent_learn then cb_reagent_learn:SetChecked(SfuiDB.recipesReagentShowCanLearn ~= false) end
            if sl_reagent_max and sl_reagent_max.SetSliderValue then
                sl_reagent_max:SetSliderValue(tonumber(SfuiDB.recipesReagentMaxLines) or 4)
            end

            cb_known:SetChecked(SfuiDB.recipesShowKnown ~= false)
            cb_can_learn:SetChecked(SfuiDB.recipesShowCanLearn ~= false)
            cb_needs_skill:SetChecked(SfuiDB.recipesShowNeedsSkill ~= false)
            cb_craftable:SetChecked(SfuiDB.recipesShowCraftable ~= false)
            cb_tint:SetChecked(SfuiDB.recipesTintIcons ~= false)
            if sl_max_alts and sl_max_alts.SetSliderValue then
                sl_max_alts:SetSliderValue(tonumber(SfuiDB.recipesMaxAlts) or 4)
            end

            if cb_sources then cb_sources:SetChecked(SfuiDB.recipesShowSources ~= false) end
            if cb_map_pins then
                local mapOn = (sfui.recipes and sfui.recipes.pins and sfui.recipes.pins.GetOption and sfui.recipes.pins.GetOption("showMapPins"))
                if mapOn == nil then mapOn = (SfuiDB.recipesShowMapPins ~= false) end
                cb_map_pins:SetChecked(mapOn)
            end
            if cb_track_pinned then cb_track_pinned:SetChecked(SfuiDB.recipesTrackPinned ~= false) end
            if cb_sync_recipes and sfui.sync and sfui.sync.GetSettings then
                cb_sync_recipes:SetChecked(sfui.sync.GetSettings().syncRecipes ~= false)
            end
        end

        function panel.ResetRecipeDefaults()
            SfuiDB.recipesShowReagentUses     = true
            SfuiDB.recipesReagentShowAlts     = true
            SfuiDB.recipesReagentShowCanLearn = true
            SfuiDB.recipesReagentMaxLines     = 4
            SfuiDB.recipesShowKnown           = true
            SfuiDB.recipesShowCanLearn        = true
            SfuiDB.recipesShowNeedsSkill      = true
            SfuiDB.recipesShowCraftable       = true
            SfuiDB.recipesTintIcons           = true
            SfuiDB.recipesMaxAlts             = 4
            SfuiDB.recipesShowSources         = true
            SfuiDB.recipesShowMapPins         = true
            SfuiDB.recipesTrackPinned         = true
            if sfui.recipes and sfui.recipes.pins and sfui.recipes.pins.SetOption then
                sfui.recipes.pins.SetOption("showMapPins", true)
            end
            invalidate_all_recipe_caches()
            if sfui.tracker and sfui.tracker.RequestRefresh then
                sfui.tracker.RequestRefresh(0)
            end
            panel.RefreshRecipesUI()
            if common and common.print then
                common.print("recipe & profession options reset to defaults.")
            end
        end

        panel.RefreshRecipesUI()
    end,
    onShow = function(panel)
        if panel and panel.RefreshRecipesUI then
            panel.RefreshRecipesUI()
        end
    end,
    resetDefaults = function(panel)
        if panel and panel.ResetRecipeDefaults then
            panel.ResetRecipeDefaults()
        end
    end,
})

