--[[
    SFUI WorldMap Recipe Pins
    frames/professions/pins.lua

    Renders small, sleek pins on the WorldMap for unlearned recipes
    that are currently available to the active character (meeting skill rank).

    Features:
      - Interactive WorldMap pins at exact waypoint coordinates for trainers, vendors, quests, drops
      - Grouping of multiple available recipes at the same NPC/coordinates with count badge
      - Color-coded by source type (vendor = green, trainer = cyan, quest = yellow, drop = orange)
      - Rich tooltip listing unlearned recipes available at that location with rank requirements and prices
      - Left-Click: Opens SFUI Recipe Catalog focused on that vendor/trainer
      - Shift-Click: Places native map waypoint with SuperTracking
      - Ctrl-Click: Pins recipe(s) to the objective tracker shopping list
      - Native WorldMap tracking menu checkbox integration
--]]

local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
local sfui = _G.sfui or {}
sfui.recipes = sfui.recipes or {}
sfui.recipes.pins = sfui.recipes.pins or {}

if sfui.isRetail then return end

local B = sfui.recipes.browser
local common = sfui.common
local GameTooltip = sfui.common.get_tooltip()

local _G = _G
local CreateFrame = _G.CreateFrame
local WorldMapFrame = _G.WorldMapFrame
local C_Map = _G.C_Map
local UnitLevel = _G.UnitLevel
local IsShiftKeyDown = _G.IsShiftKeyDown
local IsControlKeyDown = _G.IsControlKeyDown
local PlaySound = _G.PlaySound
local SOUNDKIT = _G.SOUNDKIT

local ipairs, pairs, type, tonumber, tostring = _G.ipairs, _G.pairs, _G.type, _G.tonumber, _G.tostring
local math_floor = math.floor
local table_insert, table_sort = _G.table.insert, _G.table.sort
local string_format = string.format

-- ─── Configuration & Options ──────────────────────────────────────────────────
local function GetPinsDB()
    SfuiDB = SfuiDB or {}
    if SfuiDB.recipesShowMapPins == nil then
        SfuiDB.recipesShowMapPins = true
    end
    return SfuiDB
end

function sfui.recipes.pins.GetOption(key)
    local db = GetPinsDB()
    if key == "showMapPins" then
        return db.recipesShowMapPins ~= false
    end
    return db[key]
end

function sfui.recipes.pins.SetOption(key, val)
    local db = GetPinsDB()
    if key == "showMapPins" then
        db.recipesShowMapPins = val and true or false
    else
        db[key] = val
    end
    sfui.recipes.pins.isDirty = true
    if WorldMapFrame and WorldMapFrame:IsShown() then
        sfui.recipes.pins.UpdatePins(true)
    end
end

sfui.recipes.GetOption = sfui.recipes.pins.GetOption
sfui.recipes.SetOption = sfui.recipes.pins.SetOption

function sfui.recipes.pins.GetActiveCount()
    return #activePins
end

-- ─── Helper: Get Map Canvas & Map ID ──────────────────────────────────────────
local function GetCanvas()
    if not WorldMapFrame then return nil end
    if type(WorldMapFrame.GetCanvas) == "function" then
        local ok, canvas = pcall(WorldMapFrame.GetCanvas, WorldMapFrame)
        if ok and canvas then return canvas end
    end
    if WorldMapFrame.ScrollContainer then
        return WorldMapFrame.ScrollContainer.Child or WorldMapFrame.ScrollContainer
    end
    return WorldMapFrame
end

local function GetCurrentMapID()
    if WorldMapFrame and WorldMapFrame.GetMapID then
        local ok, id = pcall(WorldMapFrame.GetMapID, WorldMapFrame)
        if ok and id then return id end
    end
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
        if ok and id then return id end
    end
    return nil
end

-- ─── Source Type Color Palette & Icons ────────────────────────────────────────
local SOURCE_COLORS = {
    vendor  = { 0.20, 1.00, 0.55, 1.0 }, -- emerald green
    trainer = { 0.20, 0.85, 1.00, 1.0 }, -- bright cyan
    quest   = { 1.00, 0.85, 0.20, 1.0 }, -- gold/yellow
    drop    = { 1.00, 0.55, 0.20, 1.0 }, -- warm orange
}

local SOURCE_ICONS = {
    vendor  = "Interface\\Icons\\INV_Scroll_03",
    trainer = "Interface\\Icons\\INV_Misc_Book_09",
    quest   = "Interface\\GossipFrame\\AvailableQuestIcon",
    drop    = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
}

-- ─── Pin Frame Factory & Pool ─────────────────────────────────────────────────
local pinPool = {}
local activePins = {}

local function AcquirePin(parent)
    for _, pin in ipairs(pinPool) do
        if not pin:IsShown() then
            pin:SetParent(parent)
            pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            return pin
        end
    end

    local pin = CreateFrame("Button", nil, parent, "BackdropTemplate")
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pin:SetSize(18, 18)
    pin:SetFrameStrata("HIGH")

    local mult = (sfui.pixelScale or 1)
    pin:SetBackdrop({
        bgFile   = [[Interface\Buttons\WHITE8x8]],
        edgeFile = [[Interface\Buttons\WHITE8x8]],
        edgeSize = mult,
    })
    pin:SetBackdropColor(0.04, 0.04, 0.05, 0.95)
    pin:SetBackdropBorderColor(0, 0, 0, 1)

    -- Icon texture
    local icon = pin:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", pin, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    pin.icon = icon

    -- Count Badge (for NPCs with multiple recipes)
    local count = pin:CreateFontString(nil, "OVERLAY")
    local fontPath = (sfui.config and sfui.config.fontFile)
        or (_G.STANDARD_TEXT_FONT and _G.STANDARD_TEXT_FONT ~= "" and _G.STANDARD_TEXT_FONT)
        or "Fonts\\FRIZQT__.TTF"
    count:SetFont(fontPath, 9, "OUTLINE")
    count:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", 2, -2)
    count:SetTextColor(1, 1, 1, 1)
    count:SetShadowColor(0, 0, 0, 1)
    count:SetShadowOffset(1, -1)
    pin.count = count

    -- Mouse highlight
    local hi = pin:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetColorTexture(1, 1, 1, 0.25)

    -- Scripts
    pin:SetScript("OnEnter", function(self)
        local group = self.group
        if not group or not group.recipes or #group.recipes == 0 then return end

        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()

            local col = SOURCE_COLORS[group.type] or { 1, 1, 1, 1 }
            local typeLabel = (group.type or "source"):lower()
            local npcLabel = (group.name or "npc"):lower()

            GameTooltip:AddLine(string_format("%s  ·  %s", npcLabel, typeLabel), col[1], col[2], col[3])

            local locStr = group.zone or ""
            if group.x and group.y then
                locStr = string_format("%s (%.1f, %.1f)", locStr ~= "" and locStr or "map", group.x * 100, group.y * 100)
            end
            if locStr ~= "" then
                GameTooltip:AddLine(locStr, 0.70, 0.70, 0.70)
            end

            GameTooltip:AddLine(" ")
            local numRec = #group.recipes
            GameTooltip:AddLine(string_format("available unlearned %s (%d):", numRec > 1 and "recipes" or "recipe", numRec), 1, 0.85, 0.20)

            -- List up to 10 recipes
            local maxDisplay = 10
            for idx, item in ipairs(group.recipes) do
                if idx > maxDisplay then
                    local rem = numRec - maxDisplay
                    GameTooltip:AddLine(string_format("  |cff888888... and %d more|r", rem), 0.7, 0.7, 0.7)
                    break
                end

                local r = item.recipe
                local s = item.source
                local minSkill = r.minSkill or (r.colors and r.colors[1]) or 0
                local costStr = s.cost and sfui.recipes.FormatMoneyShort and (" - " .. sfui.recipes.FormatMoneyShort(s.cost)) or ""
                local rName = r.name and r.name:lower() or "recipe"

                local isPinned = sfui.recipes.IsRecipePinned and sfui.recipes.IsRecipePinned(r.id)
                local pinTag = isPinned and " |cffffd100[pinned]|r" or ""

                GameTooltip:AddLine(string_format("  • %s |cff888888(rank %d)%s|r%s", rName, minSkill, costStr, pinTag), 0.90, 0.90, 0.95, true)
            end

            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00ff88left-click: open recipe catalog|r", 1, 1, 1)
            GameTooltip:AddLine("|cff80c0ffshift-click: set map waypoint with super-tracking|r", 1, 1, 1)
            GameTooltip:AddLine("|cff00e5ffctrl-click: track in objective tracker|r", 1, 1, 1)

            GameTooltip:Show()
        end
    end)

    pin:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    pin:SetScript("OnClick", function(self, button)
        local group = self.group
        if not group then return end

        -- Shift-Click: Set native map waypoint
        if IsShiftKeyDown() then
            if sfui.recipes and sfui.recipes.SetWaypoint then
                sfui.recipes.SetWaypoint(group)
            end
            return
        end

        -- Ctrl-Click: Pin first recipe (or all) to objective tracker
        if IsControlKeyDown() then
            if group.recipes and #group.recipes > 0 and sfui.recipes and sfui.recipes.TogglePinRecipe then
                local first = group.recipes[1]
                if first and first.recipe and first.recipe.id then
                    sfui.recipes.TogglePinRecipe(first.recipe.id)
                    if GameTooltip and GameTooltip:IsShown() then
                        self:GetScript("OnEnter")(self)
                    end
                end
            end
            return
        end

        -- Left-Click: Open Recipe Catalog
        if sfui.recipes and sfui.recipes.OpenBrowserForVendor and group.name then
            sfui.recipes.OpenBrowserForVendor(group.name)
        elseif sfui.recipes and sfui.recipes.OpenBrowser then
            sfui.recipes.OpenBrowser()
        end
    end)

    pinPool[#pinPool + 1] = pin
    return pin
end

local function ReleasePins()
    for _, pin in ipairs(activePins) do
        pin:Hide()
        pin.group = nil
    end
    _G.wipe(activePins)
end

-- ─── Core: Update Pins on Canvas ──────────────────────────────────────────────
local isPinsDirty   = true
local lastMapID     = nil
local lastCanvasW   = nil
local lastCanvasH   = nil
local lastProfHash  = nil

local function BuildPlayerProfHash(profList)
    if not profList or #profList == 0 then return "none" end
    local parts = {}
    for _, p in ipairs(profList) do
        table_insert(parts, string_format("%d:%d", p.skillID or 0, p.rank or 0))
    end
    return _G.table.concat(parts, "|")
end

local function UpdatePins(force)
    if not WorldMapFrame or not WorldMapFrame:IsShown() then
        ReleasePins()
        lastMapID = nil
        return
    end

    if not sfui.recipes.pins.GetOption("showMapPins") then
        ReleasePins()
        lastMapID = nil
        return
    end

    local canvas = GetCanvas()
    if not canvas then
        ReleasePins()
        lastMapID = nil
        return
    end

    local mapID = GetCurrentMapID()
    if not mapID then
        ReleasePins()
        lastMapID = nil
        return
    end

    local canvasW, canvasH = canvas:GetSize()
    if not canvasW or canvasW <= 0 or not canvasH or canvasH <= 0 then return end

    local profList = (B and B.GetPlayerProfessionsList and B.GetPlayerProfessionsList()) or {}
    local profHash = BuildPlayerProfHash(profList)

    -- Zero-CPU early out if canvas size, map ID, and player ranks are unchanged
    if not force and not isPinsDirty
        and mapID == lastMapID
        and canvasW == lastCanvasW
        and canvasH == lastCanvasH
        and profHash == lastProfHash then
        return
    end

    isPinsDirty = false
    lastMapID = mapID
    lastCanvasW = canvasW
    lastCanvasH = canvasH
    lastProfHash = profHash

    ReleasePins()

    if #profList == 0 then return end

    -- Aggregate available unlearned recipes for this map
    local mapGroups = {}
    local groupOrder = {}

    for _, p in ipairs(profList) do
        local currentRank = p.rank or 0
        local candidates = B and B.GetCandidatesForSkill and B.GetCandidatesForSkill(p.skillID)

        if candidates then
            for _, r in ipairs(candidates) do
                -- 1. Check if already learned
                local isLearned = B.IsRecipeLearned and B.IsRecipeLearned(r.id, r)
                if not isLearned then
                    -- 2. Check skill requirement
                    local minSkill = r.minSkill or (r.colors and r.colors[1]) or 0
                    if currentRank >= minSkill then
                        -- 3. Check specialization
                        local passSpec = true
                        if r.spec and B.PlayerHasSpec then
                            passSpec = B.PlayerHasSpec(r.spec)
                        end

                        if passSpec then
                            -- 4. Check sources for current mapID
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

                                        table_insert(g.recipes, {
                                            recipe = r,
                                            source = s,
                                        })
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if #groupOrder == 0 then return end

    -- Acquire and place pins on canvas
    for _, g in ipairs(groupOrder) do
        local pin = AcquirePin(canvas)
        pin.group = g

        pin:ClearAllPoints()
        pin:SetPoint("CENTER", canvas, "TOPLEFT", canvasW * g.x, -canvasH * g.y)

        -- Style border and icon based on source type
        local col = SOURCE_COLORS[g.type] or { 0.20, 0.85, 1.00, 1.0 }
        pin:SetBackdropBorderColor(col[1], col[2], col[3], 0.90)

        local iconPath = SOURCE_ICONS[g.type] or SOURCE_ICONS.vendor
        pin.icon:SetTexture(iconPath)

        -- Sort recipes by skill requirement ascending
        table_sort(g.recipes, function(a, b)
            local skA = a.recipe.minSkill or (a.recipe.colors and a.recipe.colors[1]) or 0
            local skB = b.recipe.minSkill or (b.recipe.colors and b.recipe.colors[1]) or 0
            if skA ~= skB then return skA < skB end
            return (a.recipe.name or "") < (b.recipe.name or "")
        end)

        local numRecipes = #g.recipes
        if numRecipes > 1 then
            pin.count:SetText(tostring(numRecipes))
            pin.count:Show()
        else
            pin.count:Hide()
        end

        pin:Show()
        table_insert(activePins, pin)
    end
end

sfui.recipes.pins.UpdatePins = UpdatePins

-- ─── WorldMap Tracking Dropdown Menu Integration ──────────────────────────────
local function HookWorldMapTrackingMenu()
    if _G.Menu and _G.Menu.ModifyMenu then
        pcall(_G.Menu.ModifyMenu, "MENU_WORLD_MAP_TRACKING", function(owner, rootDescription)
            rootDescription:CreateDivider()
            rootDescription:CreateTitle("recipe catalog")

            rootDescription:CreateCheckbox("available unlearned recipes",
                function()
                    return sfui.recipes.pins.GetOption("showMapPins")
                end,
                function()
                    local cur = sfui.recipes.pins.GetOption("showMapPins")
                    sfui.recipes.pins.SetOption("showMapPins", not cur)
                end)
        end)
    end
end

-- ─── Event & Lifecycle Hooks ──────────────────────────────────────────────────
local function InitPins()
    HookWorldMapTrackingMenu()

    if WorldMapFrame then
        WorldMapFrame:HookScript("OnShow", function()
            UpdatePins(true)
        end)
        WorldMapFrame:HookScript("OnHide", function()
            ReleasePins()
        end)
    end

    if sfui.events and sfui.events.RegisterMessage then
        sfui.events.RegisterMessage("SFUI_RECIPE_PINNED_CHANGED", function()
            isPinsDirty = true
            if WorldMapFrame and WorldMapFrame:IsShown() then
                UpdatePins(true)
            end
        end)
    end

    if sfui.events and sfui.events.RegisterEvent then
        local function RefreshDirty()
            isPinsDirty = true
            if WorldMapFrame and WorldMapFrame:IsShown() then
                common.debounce("recipe_pins_update", 0.15, function()
                    UpdatePins(true)
                end)
            end
        end

        sfui.events.RegisterEvent("SKILL_LINES_CHANGED", RefreshDirty)
        sfui.events.RegisterEvent("CHAT_MSG_SKILL", RefreshDirty)
        sfui.events.RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
            isPinsDirty = true
            UpdatePins(true)
        end)
        sfui.events.RegisterEvent("ZONE_CHANGED", function()
            isPinsDirty = true
            UpdatePins(true)
        end)
    end

    -- Real-time ticker: keep pins locked to coordinates while scrolling/zooming
    if sfui.events and sfui.events.RegisterUpdate then
        sfui.events.RegisterUpdate("RecipeMapPins", 0.5, function()
            if WorldMapFrame and WorldMapFrame:IsShown() then
                UpdatePins(false)
            end
        end)
    elseif _G.C_Timer and _G.C_Timer.NewTicker then
        _G.C_Timer.NewTicker(0.5, function()
            if WorldMapFrame and WorldMapFrame:IsShown() then
                UpdatePins(false)
            end
        end)
    end
end

if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("PLAYER_LOGIN", InitPins)
end
