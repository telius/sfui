local addonName, addon = ...
sfui = sfui or {}
sfui.fishing = sfui.fishing or {}
sfui.fishing.atlas = sfui.fishing.atlas or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/fishing/fishing_atlas.lua
--  Native Themed Fishing Atlas & Waters Journal (Camelot & Classic Forever)
--
--  Tab 1: Fish Atlas (searchable card catalog of fish & containers)
--  Tab 2: Waters (all classic & forever zones with skill & species breakdown)
--  Tab 3: Logbook (session metrics, personal records & trainer milestones)
-- ══════════════════════════════════════════════════════════════════════════════

local ATLAS = sfui.fishing.atlas
local common = sfui.common
local theme = sfui.theme
local data = sfui.fishing_data

local _G = _G
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local ipairs, pairs = _G.ipairs, _G.pairs
local table_sort = _G.table.sort
local string_format = _G.string.format
local math_floor = _G.math.floor
local tostring = _G.tostring
local date = _G.date

local atlasFrame = nil
local activeTab = "atlas"
local selectedSpeciesID = nil
local selectedZoneMapID = nil

local speciesFilterText = ""
local speciesCategoryFilter = "all"
local watersFilterText = ""
local watersContinentFilter = "all"

-- ─── Formatting Helpers ──────────────────────────────────────────────────────

local function FormatDate(timestamp)
    if not timestamp or timestamp <= 0 then return "never" end
    return date("%Y-%m-%d %H:%M", timestamp)
end

-- ─── Tab Button Creator ──────────────────────────────────────────────────────

local function CreateTabButton(parent, id, text, icon, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(26)
    btn:SetWidth(120)

    local ico = btn:CreateTexture(nil, "ARTWORK")
    ico:SetSize(16, 16)
    ico:SetPoint("LEFT", btn, "LEFT", 8, 0)
    ico:SetTexture(icon)
    btn.icon = ico

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", ico, "RIGHT", 6, 0)
    label:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(text)
    btn.label = label

    btn:SetScript("OnClick", function()
        onClick(id)
    end)

    return btn
end

-- ─── Forward Declarations for Tab Builders ───────────────────────────────────

local BuildAtlasTab
local BuildWatersTab
local BuildLogbookTab
local RefreshAtlasView
local RefreshWatersView
local RefreshLogbookView

-- ─── Master Window Construction ──────────────────────────────────────────────

local function CreateAtlasWindow()
    if atlasFrame then return atlasFrame end

    local f = CreateFrame("Frame", "SfuiFishingAtlasFrame", UIParent, "BackdropTemplate")
    f:SetSize(840, 540)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)

    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    -- Register special frame so Escape closes it without tainting UISpecialFrames
    if common and common.register_special_frame then
        common.register_special_frame(f)
    end

    -- Native window header bar
    if theme and theme.CreateWindowHeader then
        theme.CreateWindowHeader(f, "fishing atlas", 280)
    end

    -- Close button
    local closeBtn = (common.create_close_button or CreateFrame("Button", nil, f, "UIPanelCloseButton"))(f, function() f:Hide() end, 22)
    closeBtn:ClearAllPoints()
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    if f.headerBar then
        closeBtn:SetFrameLevel(f.headerBar:GetFrameLevel() + 5)
    end
    f.closeBtn = closeBtn

    -- Register with theme engine
    if theme and theme.RegisterWindow then
        theme.RegisterWindow(f, function(frame, pal)
            if frame.tabs then
                for id, btn in pairs(frame.tabs) do
                    local isSelected = (id == activeTab)
                    if theme and theme.ApplyTabStyle then
                        theme.ApplyTabStyle(btn, isSelected)
                    end
                end
            end
        end, { title = "fishing atlas" })
    else
        common.apply_flat_backdrop(f, { 0.06, 0.06, 0.08, 0.96 }, { 0.22, 0.22, 0.26, 0.90 })
    end

    -- Top Tab Row
    local tabContainer = CreateFrame("Frame", nil, f)
    tabContainer:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -36)
    tabContainer:SetSize(600, 28)
    f.tabContainer = tabContainer

    local tabs = {}
    local tabDefs = {
        { id = "atlas",   text = "fish atlas", icon = "Interface\\Icons\\INV_Misc_Fish_02" },
        { id = "waters",  text = "waters",     icon = "Interface\\Icons\\Trade_Fishing" },
        { id = "logbook", text = "logbook",    icon = "Interface\\Icons\\INV_Misc_Book_09" },
    }

    local prevTab = nil
    for _, def in ipairs(tabDefs) do
        local btn = CreateTabButton(tabContainer, def.id, def.text, def.icon, function(pickedID)
            ATLAS.ShowTab(pickedID)
        end)
        if not prevTab then
            btn:SetPoint("LEFT", tabContainer, "LEFT", 0, 0)
        else
            btn:SetPoint("LEFT", prevTab, "RIGHT", 6, 0)
        end
        prevTab = btn
        tabs[def.id] = btn
    end
    f.tabs = tabs

    -- Content Container
    local content = CreateFrame("Frame", nil, f, "BackdropTemplate")
    content:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -66)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
    f.content = content

    -- Build Tab Panels
    f.atlasPanel = BuildAtlasTab(content)
    f.watersPanel = BuildWatersTab(content)
    f.logbookPanel = BuildLogbookTab(content)

    f:Hide()
    atlasFrame = f
    return f
end

-- ─── Shared UI Widget Builders ───────────────────────────────────────────────

local function CreateSearchBox(parent, placeholderText, onChanged, width)
    local searchBox = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    searchBox:SetSize(width or 160, 22)
    searchBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -4)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject("GameFontHighlightSmall")
    searchBox:SetTextInsets(6, 6, 2, 2)
    if theme and theme.ApplyInputStyle then
        theme.ApplyInputStyle(searchBox)
    else
        common.apply_flat_backdrop(searchBox, { 0.1, 0.1, 0.12, 0.8 }, { 0.3, 0.3, 0.35, 0.8 })
    end

    local placeholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", searchBox, "LEFT", 8, 0)
    placeholder:SetText(placeholderText)
    searchBox.placeholder = placeholder

    searchBox:SetScript("OnTextChanged", function(self)
        local txt = self:GetText()
        local val = txt and txt:lower() or ""
        placeholder:SetShown(val == "")
        onChanged(val)
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    return searchBox
end

local function CreateStyledScrollFrame(parent, globalName, childWidth)
    local scrollFrame = CreateFrame("ScrollFrame", globalName, parent, "UIPanelScrollFrameTemplate")
    if theme and theme.ApplyScrollBarStyle and _G[globalName .. "ScrollBar"] then
        theme.ApplyScrollBarStyle(_G[globalName .. "ScrollBar"])
    end
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(childWidth, 1)
    scrollFrame:SetScrollChild(scrollChild)
    return scrollFrame, scrollChild
end

local function CreateInfoCard(parent, titleText, w, h)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if w and h then card:SetSize(w, h) end
    if theme and theme.ApplyCardStyle then
        theme.ApplyCardStyle(card, 1)
    else
        common.apply_flat_backdrop(card, { 0.08, 0.08, 0.10, 0.8 }, { 0.25, 0.25, 0.30, 0.8 })
    end

    local title = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -10)
    title:SetText(titleText)
    title:SetTextColor(0, 1, 1)
    card.title = title

    local text = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    text:SetPoint("RIGHT", card, "RIGHT", -12, 0)
    text:SetJustifyH("LEFT")
    card.text = text

    return card
end

local function ApplyFilterButtonStyles(btns, activeID)
    for _, ob in pairs(btns) do
        local isSelected = (ob.id == activeID)
        if theme and theme.ApplyTabStyle then
            theme.ApplyTabStyle(ob, isSelected)
        else
            common.apply_flat_backdrop(ob, isSelected and { 0.25, 0.20, 0.06, 0.85 } or { 0.1, 0.1, 0.12, 0.5 }, { 0.3, 0.3, 0.35, 0.8 })
        end
    end
end

local function CreateFilterButtons(parent, anchorTo, filters, initialID, onSelect)
    local btns = {}
    local prev = anchorTo
    for _, c in ipairs(filters) do
        local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
        b:SetHeight(22)
        b:SetWidth(c.width or 66)
        b:SetPoint("LEFT", prev, "RIGHT", (prev == anchorTo) and 8 or 4, 0)
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("CENTER", b, "CENTER", 0, 0)
        fs:SetText(c.text)
        b.fs = fs
        b.id = c.id

        b:SetScript("OnClick", function()
            ApplyFilterButtonStyles(btns, c.id)
            onSelect(c.id)
        end)

        btns[c.id] = b
        prev = b
    end
    ApplyFilterButtonStyles(btns, initialID)
    return btns
end

-- ─── Tab 1: Fish Atlas (Species Cards & Details) ─────────────────────────────

BuildAtlasTab = function(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()

    -- Search Bar & Category Filters
    local searchBox = CreateSearchBox(p, "search species...", function(val)
        speciesFilterText = val
        RefreshAtlasView()
    end, 160)
    p.searchBox = searchBox

    -- Filter Buttons: all, fish, containers, caught, missing
    local catFilters = {
        { id = "all",        text = "all",        width = 48 },
        { id = "fish",       text = "fish",       width = 52 },
        { id = "containers", text = "containers", width = 76 },
        { id = "caught",     text = "caught",     width = 58 },
        { id = "missing",    text = "missing",    width = 58 },
    }
    p.catBtns = CreateFilterButtons(p, searchBox, catFilters, speciesCategoryFilter, function(id)
        speciesCategoryFilter = id
        RefreshAtlasView()
    end)

    -- Left Scroll Container (Cards Grid)
    local scrollFrame, scrollChild = CreateStyledScrollFrame(p, "SfuiFishingAtlasScroll", 498)
    scrollFrame:SetPoint("TOPLEFT", p, "TOPLEFT", 4, -32)
    scrollFrame:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 4, 4)
    scrollFrame:SetWidth(498)
    p.scrollChild = scrollChild

    -- Right Detail Panel (aligned below the top filter bar at y = -32)
    local detail = CreateFrame("Frame", nil, p, "BackdropTemplate")
    detail:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 26, 0)
    detail:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -4, 4)
    if theme and theme.ApplyCardStyle then
        theme.ApplyCardStyle(detail, 1)
    else
        common.apply_flat_backdrop(detail, { 0.08, 0.08, 0.10, 0.75 }, { 0.22, 0.22, 0.26, 0.7 })
    end
    p.detail = detail

    -- Detail Elements
    local detIcon = detail:CreateTexture(nil, "ARTWORK")
    detIcon:SetSize(42, 42)
    detIcon:SetPoint("TOPLEFT", detail, "TOPLEFT", 12, -12)
    detail.icon = detIcon

    local detName = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    detName:SetPoint("TOPLEFT", detIcon, "TOPRIGHT", 10, 0)
    detName:SetPoint("RIGHT", detail, "RIGHT", -10, 0)
    detName:SetJustifyH("LEFT")
    detName:SetWordWrap(true)
    detail.name = detName

    local detMeta = detail:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    detMeta:SetPoint("TOPLEFT", detName, "BOTTOMLEFT", 0, -4)
    detMeta:SetPoint("RIGHT", detail, "RIGHT", -10, 0)
    detMeta:SetJustifyH("LEFT")
    detail.meta = detMeta

    -- Detail Stats Section
    local statsHeader = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statsHeader:SetPoint("TOPLEFT", detIcon, "BOTTOMLEFT", 0, -12)
    statsHeader:SetText("catch history:")
    statsHeader:SetTextColor(0, 1, 1)
    detail.statsHeader = statsHeader

    local statsText = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statsText:SetPoint("TOPLEFT", statsHeader, "BOTTOMLEFT", 0, -4)
    statsText:SetPoint("RIGHT", detail, "RIGHT", -10, 0)
    statsText:SetJustifyH("LEFT")
    detail.statsText = statsText

    -- Where It Bites Section
    local watersHeader = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    watersHeader:SetPoint("TOPLEFT", statsText, "BOTTOMLEFT", 0, -12)
    watersHeader:SetText("where it bites (drop rates):")
    watersHeader:SetTextColor(0, 1, 1)
    detail.watersHeader = watersHeader

    local watersScroll, watersChild = CreateStyledScrollFrame(detail, "SfuiFishingDetailWatersScroll", 250)
    watersScroll:SetPoint("TOPLEFT", watersHeader, "BOTTOMLEFT", 0, -4)
    watersScroll:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -20, 10)
    detail.watersChild = watersChild
    detail.watersPool = {}

    p.cardsPool = {}
    return p
end

-- ─── Tab 2: Waters (Zone Directory & Local Species) ──────────────────────────

BuildWatersTab = function(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()

    -- Search Bar & Continent Filters for Zones
    local searchBox = CreateSearchBox(p, "search zones...", function(val)
        watersFilterText = val
        RefreshWatersView()
    end, 160)
    p.searchBox = searchBox

    local continentFilters = {
        { id = "all",              text = "all",              width = 48 },
        { id = "eastern_kingdoms", text = "eastern kingdoms", width = 118 },
        { id = "kalimdor",         text = "kalimdor",         width = 76 },
    }
    p.continentBtns = CreateFilterButtons(p, searchBox, continentFilters, watersContinentFilter, function(id)
        watersContinentFilter = id
        RefreshWatersView()
    end)

    -- Left Column: Zone List ScrollFrame
    local scrollFrame, scrollChild = CreateStyledScrollFrame(p, "SfuiWatersListScroll", 310)
    scrollFrame:SetPoint("TOPLEFT", p, "TOPLEFT", 4, -32)
    scrollFrame:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 4, 4)
    scrollFrame:SetWidth(330)
    p.scrollChild = scrollChild

    -- Right Column: Zone Species Detail (aligned below the top filter bar at y = -32)
    local detail = CreateFrame("Frame", nil, p, "BackdropTemplate")
    detail:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 26, 0)
    detail:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -4, 4)
    if theme and theme.ApplyCardStyle then
        theme.ApplyCardStyle(detail, 1)
    else
        common.apply_flat_backdrop(detail, { 0.08, 0.08, 0.10, 0.75 }, { 0.22, 0.22, 0.26, 0.7 })
    end
    p.detail = detail

    local zoneTitle = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    zoneTitle:SetPoint("TOPLEFT", detail, "TOPLEFT", 12, -12)
    zoneTitle:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    zoneTitle:SetJustifyH("LEFT")
    detail.title = zoneTitle

    local zoneReq = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    zoneReq:SetPoint("TOPLEFT", zoneTitle, "BOTTOMLEFT", 0, -4)
    zoneReq:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    zoneReq:SetJustifyH("LEFT")
    detail.req = zoneReq

    local speciesScroll, speciesChild = CreateStyledScrollFrame(detail, "SfuiWatersSpeciesScroll", 412)
    speciesScroll:SetPoint("TOPLEFT", zoneReq, "BOTTOMLEFT", 0, -10)
    speciesScroll:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -24, 10)
    detail.speciesChild = speciesChild
    detail.speciesPool = {}

    local noFish = speciesChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    noFish:SetPoint("TOPLEFT", speciesChild, "TOPLEFT", 8, -8)
    noFish:SetText("no confirmed fishing species for this zone.")
    noFish:Hide()
    detail.noFishLabel = noFish

    p.zoneRowsPool = {}
    p.continentHeadersPool = {}
    return p
end

-- ─── Tab 3: Logbook (Session & Lifetime Records) ──────────────────────────────

BuildLogbookTab = function(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()

    -- 1. Current Session Card (Top Left)
    local sessionCard = CreateInfoCard(p, "current fishing session", 400, 200)
    sessionCard:SetPoint("TOPLEFT", p, "TOPLEFT", 8, -8)

    local resetBtn = common.create_flat_button(sessionCard, "reset session stats", 140, 22, function()
        sfui.fishing.ResetSession()
    end)
    resetBtn:SetPoint("BOTTOMLEFT", sessionCard, "BOTTOMLEFT", 12, 10)

    -- 2. Lifetime Records Card (Top Right)
    local recordsCard = CreateInfoCard(p, "lifetime records", 400, 200)
    recordsCard:SetPoint("TOPLEFT", sessionCard, "TOPRIGHT", 12, 0)

    -- 3. Milestones Card (Bottom)
    local milestonesCard = CreateInfoCard(p, "trainer milestones")
    milestonesCard:SetPoint("TOPLEFT", sessionCard, "BOTTOMLEFT", 0, -12)
    milestonesCard:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -8, 8)

    p.sessionCard = sessionCard
    p.recordsCard = recordsCard
    p.milestonesCard = milestonesCard
    return p
end

-- ─── Detail View Updates ─────────────────────────────────────────────────────

local function append_species_caught_by_tooltip(tip, speciesID)
    if not tip or not speciesID or not sfui.fishing or not sfui.fishing.GetSpeciesCharBreakdown then return end
    local _, totalCaught, anglers = sfui.fishing.GetSpeciesCharBreakdown(speciesID)
    if totalCaught and totalCaught > 0 and type(anglers) == "table" and #anglers > 0 then
        tip:AddLine(" ")
        tip:AddLine(string_format("caught across accounts (%d):", totalCaught), 0, 1, 1)
        for i = 1, math.min(#anglers, 8) do
            local a = anglers[i]
            local acctTag = a.accountTag or ""
            if tip.AddDoubleLine then
                tip:AddDoubleLine("  " .. (a.coloredName or a.name or "?") .. acctTag, tostring(a.count or 0), 1, 1, 1, 0, 1, 0.53)
            else
                tip:AddLine(string_format("  %s%s: %d", a.coloredName or a.name or "?", acctTag, a.count or 0), 1, 1, 1)
            end
        end
    end
end

local function BindSpeciesTooltip(btn)
    btn:SetScript("OnEnter", function(self)
        if not self.speciesID then return end
        local tip = common.get_tooltip()
        if tip then
            tip._sfuiInFishingAtlas = true
            tip:SetOwner(self, "ANCHOR_RIGHT")
            tip:SetHyperlink("item:" .. self.speciesID)
            append_species_caught_by_tooltip(tip, self.speciesID)
            if sfui.recipes and sfui.recipes.GetRecipesUsingReagent and sfui.recipes.GetRecipesUsingReagent(self.speciesID) then
                tip:AddLine("|cff80c0ffctrl-click to open recipe browser|r", 0.5, 0.8, 1)
            end
            tip:Show()
        end
    end)
    btn:SetScript("OnLeave", function()
        local tip = common.get_tooltip()
        if tip then
            tip._sfuiInFishingAtlas = nil
        end
        common.hide_tooltip()
    end)
end

local function HandleSpeciesButtonModifierClick(speciesID)
    if not speciesID then return false end
    if _G.IsShiftKeyDown and _G.IsShiftKeyDown() then
        local _, link = common.get_item_info(speciesID)
        link = link or ("item:" .. speciesID)
        if common.insert_link_to_chat and common.insert_link_to_chat(link) then
            return true
        end
    end
    if _G.IsControlKeyDown and _G.IsControlKeyDown() and sfui.nav and sfui.nav.OpenRecipeOrFishing then
        if sfui.nav.OpenRecipeOrFishing(speciesID) then
            return true
        end
    end
    return false
end

local function UpdateSpeciesDetail(speciesID)
    if not atlasFrame or not atlasFrame.atlasPanel then return end
    local det = atlasFrame.atlasPanel.detail
    local item = data.GetSpeciesInfo(speciesID)
    if not item then
        det.name:SetText("select a species")
        det.meta:SetText("")
        det.statsText:SetText("")
        return
    end

    local displayText, texture = data.GetSpeciesDisplay(speciesID, true)
    det.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_Fish_02")
    det.name:SetText(displayText)

    local kindLabel = (item.kind == "q" and "quest fish")
        or (item.kind == "t" and "trophy / rare fish")
        or (item.isContainer and "container / trunk")
        or "catchable fish"
    local hab = item.habitat or data.GetSpeciesHabitat(speciesID)
    local habLabel = (hab == "coastal" and " • |cff44bbffcoastal (ocean)|r")
        or (hab == "inland" and " • |cff66dd88inland (freshwater)|r")
        or (hab == "oasis" and " • |cffffcc44oasis pond|r")
        or ""
    det.meta:SetText(string_format("%s%s • min skill: %d", kindLabel, habLabel, item.minSkill or 0))

    -- Catch Statistics
    local savedSpecies = SfuiDB and SfuiDB.fishing and SfuiDB.fishing.species and SfuiDB.fishing.species[speciesID]
    local myCount, totalCaught, anglers = 0, (savedSpecies and savedSpecies.n) or 0, {}
    if sfui.fishing and sfui.fishing.GetSpeciesCharBreakdown then
        myCount, totalCaught, anglers = sfui.fishing.GetSpeciesCharBreakdown(speciesID)
    end
    local firstDate = savedSpecies and FormatDate(savedSpecies.first) or "never"
    local firstZone = (savedSpecies and savedSpecies.fz and data.GetZoneName(savedSpecies.fz)) or "unknown"
    local lastDate = savedSpecies and FormatDate(savedSpecies.last) or "never"
    local lastZone = (savedSpecies and savedSpecies.lz and data.GetZoneName(savedSpecies.lz)) or "unknown"

    local youSuffix = (totalCaught > myCount) and string_format(" |cffaaaaaa(you: %d)|r", myCount) or ""
    local statsLines = {
        string_format("total caught: |cffffffff%d|r%s", totalCaught, youSuffix),
        string_format("first catch: |cffffd100%s|r in %s", firstDate, firstZone),
        string_format("last catch: |cffffd100%s|r in %s", lastDate, lastZone),
    }
    if type(anglers) == "table" and #anglers > 0 then
        local parts = {}
        for i = 1, math.min(#anglers, 4) do
            local a = anglers[i]
            parts[#parts + 1] = string_format("%s%s (|cff00ff88%d|r)", a.coloredName or a.name or "?", a.accountTag or "", a.count or 0)
        end
        if #anglers > 4 then
            parts[#parts + 1] = string_format("+%d more", #anglers - 4)
        end
        statsLines[#statsLines + 1] = "caught by: " .. table.concat(parts, ", ")
    end
    det.statsText:SetText(table.concat(statsLines, "\n"))

    -- Where It Bites (List of Zones)
    local child = det.watersChild
    child:Hide()
    local pool = det.watersPool or {}
    det.watersPool = pool

    local _, _, _, totalSkill = sfui.fishing.GetFishingSkill()
    local ROW_H = 22
    for i, z in ipairs(item.zones) do
        local row = pool[i]
        if not row then
            row = CreateFrame("Frame", nil, child, "BackdropTemplate")
            row:SetSize(250, ROW_H)

            local zLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            zLabel:SetPoint("LEFT", row, "LEFT", 4, 0)
            zLabel:SetJustifyH("LEFT")
            row.zLabel = zLabel

            local rateLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            rateLabel:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            rateLabel:SetJustifyH("RIGHT")
            row.rateLabel = rateLabel

            pool[i] = row
        end

        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * 24)

        local zoneName = data.GetZoneName(z.mapID) or ("map " .. z.mapID)
        local req = z.reqSkill or 0
        local isQualified = totalSkill >= req
        local skillCol = isQualified and "|cff00ff88" or "|cffff4444"

        row.zLabel:SetText(zoneName)
        row.rateLabel:SetText(string_format("%.1f%%  %sskill %d|r", z.share or 0, skillCol, req))
        row:Show()
    end

    for i = #item.zones + 1, #pool do
        pool[i]:Hide()
    end

    child:SetHeight(math.max(#item.zones * 24, 10))
    child:Show()
end

local function UpdateZoneDetail(mapID)
    if not atlasFrame or not atlasFrame.watersPanel then return end
    local det = atlasFrame.watersPanel.detail
    local zoneName = data.GetZoneName(mapID) or ("map " .. tostring(mapID))
    local _, contLabel = data.GetZoneContinent(mapID)
    local reqSkill, subArea = data.GetZoneRequirement(mapID)
    local _, _, _, totalSkill = sfui.fishing.GetFishingSkill()

    det.title:SetText(string_format("%s • |cff88ccff%s|r", zoneName, contLabel))
    if reqSkill then
        local color = (totalSkill >= reqSkill) and "|cff00ff88" or "|cffff4444"
        local subText = subArea and string_format(" • %s: |cffffd100%d|r", subArea.area, subArea.skill) or ""
        local mixText = (data.MIXED_ZONES and data.MIXED_ZONES[mapID]) and " • |cff44bbff[coast]|r & |cff66dd88[inland]|r" or ""
        det.req:SetText(string_format("required skill: %s%d|r (your skill: |cffffffff%d|r)%s%s", color, reqSkill, totalSkill, subText, mixText))
    else
        det.req:SetText("required skill: |cff888888unknown|r")
    end

    local child = det.speciesChild
    child:Hide()
    local pool = det.speciesPool or {}
    det.speciesPool = pool

    local lootEntries = data.GetZoneLoot(mapID)
    local savedZones = SfuiDB and SfuiDB.fishing and SfuiDB.fishing.zones
    local zoneStats = savedZones and savedZones[mapID]
    local caughtCounts = zoneStats and zoneStats.fish or {}

    local numEntries = (lootEntries and #lootEntries) or 0
    if numEntries > 0 then
        if det.noFishLabel then det.noFishLabel:Hide() end
        for i, entry in ipairs(lootEntries) do
            local row = pool[i]
            if not row then
                row = CreateFrame("Button", nil, child, "BackdropTemplate")
                row:SetSize(412, 28)

                local ico = row:CreateTexture(nil, "ARTWORK")
                ico:SetSize(22, 22)
                ico:SetPoint("LEFT", row, "LEFT", 4, 0)
                row.ico = ico

                local shareFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                shareFs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                shareFs:SetJustifyH("RIGHT")
                row.shareFs = shareFs

                local nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                nameFs:SetPoint("LEFT", ico, "RIGHT", 6, 0)
                nameFs:SetPoint("RIGHT", shareFs, "LEFT", -8, 0)
                nameFs:SetJustifyH("LEFT")
                nameFs:SetWordWrap(false)
                row.nameFs = nameFs

                BindSpeciesTooltip(row)
                pool[i] = row
            end

            row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * 32)
            if theme and theme.ApplyCardStyle then
                theme.ApplyCardStyle(row, 2)
            else
                common.apply_flat_backdrop(row, { 0.1, 0.1, 0.12, 0.5 }, { 0.25, 0.25, 0.3, 0.5 })
            end

            local itemID = entry[1]
            local share = entry[2]
            local myCount, count = 0, caughtCounts[itemID] or 0
            if sfui.fishing and sfui.fishing.GetZoneFishCharBreakdown then
                myCount, count = sfui.fishing.GetZoneFishCharBreakdown(mapID, itemID)
            else
                myCount = count
            end

            local baseName, texture = data.GetSpeciesDisplay(itemID, true)
            row.ico:SetTexture(texture or "Interface\\Icons\\INV_Misc_Fish_02")
            local _, habBadge = data.GetSpeciesHabitat(itemID, mapID)
            row.nameFs:SetText(habBadge and (baseName .. " " .. habBadge) or baseName)

            local caughtCol = (count > 0) and "|cff00ff88" or "|cff888888"
            local youTag = (count > myCount) and string_format(" |cffaaaaaa(you: %d)|r", myCount) or ""
            row.shareFs:SetText(string_format("%.1f%%  %scaught %d|r%s", share or 0, caughtCol, count, youTag))

            row.speciesID = itemID
            row:SetScript("OnClick", function()
                if HandleSpeciesButtonModifierClick(itemID) then return end
                ATLAS.ShowTab("atlas")
                selectedSpeciesID = itemID
                UpdateSpeciesDetail(itemID)
            end)

            row:Show()
        end

        for i = numEntries + 1, #pool do
            pool[i]:Hide()
        end

        child:SetHeight(math.max(numEntries * 32, 10))
    else
        for i = 1, #pool do
            pool[i]:Hide()
        end
        if det.noFishLabel then
            det.noFishLabel:Show()
        end
        child:SetHeight(30)
    end

    child:Show()
end

-- ─── Tab View Refreshers ─────────────────────────────────────────────────────

RefreshAtlasView = function()
    if not atlasFrame or not atlasFrame.atlasPanel then return end
    local p = atlasFrame.atlasPanel
    local child = p.scrollChild
    child:Hide()

    local allSpecies = data.GetAllSpecies()
    local savedSpecies = SfuiDB and SfuiDB.fishing and SfuiDB.fishing.species or {}

    local filtered = {}
    for itemID, item in pairs(allSpecies) do
        local name = data.GetSpeciesDisplay(itemID, false)
        local matchSearch = (speciesFilterText == "") or (name:find(speciesFilterText, 1, true) ~= nil)

        local matchCategory = true
        if speciesCategoryFilter == "fish" and item.isContainer then
            matchCategory = false
        elseif speciesCategoryFilter == "containers" and not item.isContainer then
            matchCategory = false
        elseif speciesCategoryFilter == "caught" and (not savedSpecies[itemID] or savedSpecies[itemID].n <= 0) then
            matchCategory = false
        elseif speciesCategoryFilter == "missing" and savedSpecies[itemID] and savedSpecies[itemID].n > 0 then
            matchCategory = false
        end

        if matchSearch and matchCategory then
            filtered[#filtered + 1] = item
        end
    end

    table_sort(filtered, function(a, b)
        if a.minSkill ~= b.minSkill then return a.minSkill < b.minSkill end
        return a.itemID < b.itemID
    end)

    -- Pool and render cards
    local pool = p.cardsPool
    local CARD_W, CARD_H = 246, 46
    local COLS = 2

    for i, item in ipairs(filtered) do
        local card = pool[i]
        if not card then
            card = CreateFrame("Button", nil, child, "BackdropTemplate")
            card:SetSize(CARD_W, CARD_H)

            local ico = card:CreateTexture(nil, "ARTWORK")
            ico:SetSize(32, 32)
            ico:SetPoint("LEFT", card, "LEFT", 6, 0)
            card.ico = ico

            local nameFs = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            nameFs:SetPoint("TOPLEFT", ico, "TOPRIGHT", 6, -2)
            nameFs:SetPoint("RIGHT", card, "RIGHT", -6, 0)
            nameFs:SetJustifyH("LEFT")
            nameFs:SetWordWrap(false)
            card.nameFs = nameFs

            local countFs = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            countFs:SetPoint("BOTTOMLEFT", ico, "BOTTOMRIGHT", 6, 2)
            countFs:SetJustifyH("LEFT")
            card.countFs = countFs

            local skillFs = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            skillFs:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -6, 2)
            skillFs:SetJustifyH("RIGHT")
            card.skillFs = skillFs

            card:SetScript("OnClick", function(self)
                if HandleSpeciesButtonModifierClick(self.speciesID) then return end
                selectedSpeciesID = self.speciesID
                UpdateSpeciesDetail(self.speciesID)
            end)
            BindSpeciesTooltip(card)

            pool[i] = card
        end

        local col = (i - 1) % COLS
        local row = math_floor((i - 1) / COLS)
        card:SetPoint("TOPLEFT", child, "TOPLEFT", col * (CARD_W + 6), -row * (CARD_H + 6))

        local displayText, texture = data.GetSpeciesDisplay(item.itemID, true)
        card.ico:SetTexture(texture or "Interface\\Icons\\INV_Misc_Fish_02")
        card.nameFs:SetText(displayText)

        local myCount, count = 0, (savedSpecies[item.itemID] and savedSpecies[item.itemID].n) or 0
        if sfui.fishing and sfui.fishing.GetSpeciesCharBreakdown then
            myCount, count = sfui.fishing.GetSpeciesCharBreakdown(item.itemID)
        else
            myCount = count
        end
        if count > 0 then
            if count > myCount then
                card.countFs:SetText(string_format("|cff00ff88caught: %d|r |cffaaaaaa(you: %d)|r", count, myCount))
            else
                card.countFs:SetText(string_format("|cff00ff88caught: %d|r", count))
            end
        else
            card.countFs:SetText("|cffff4444not caught|r")
        end
        card.skillFs:SetText(string_format("skill %d", item.minSkill or 0))

        if theme and theme.ApplyCardStyle then
            theme.ApplyCardStyle(card, (item.itemID == selectedSpeciesID) and 2 or 1)
        else
            common.apply_flat_backdrop(card, (item.itemID == selectedSpeciesID) and { 0.25, 0.20, 0.06, 0.85 } or { 0.08, 0.08, 0.10, 0.7 }, { 0.25, 0.25, 0.3, 0.7 })
        end

        card.speciesID = item.itemID
        card:Show()
    end

    for i = #filtered + 1, #pool do
        pool[i]:Hide()
    end

    local totalRows = math.ceil(#filtered / COLS)
    child:SetHeight(math.max(totalRows * (CARD_H + 6), 10))
    child:Show()

    if not selectedSpeciesID and #filtered > 0 then
        selectedSpeciesID = filtered[1].itemID
    end
    if selectedSpeciesID then
        UpdateSpeciesDetail(selectedSpeciesID)
    end
end

local CONTINENT_SECTIONS = {
    { key = "eastern_kingdoms", label = "eastern kingdoms" },
    { key = "kalimdor",         label = "kalimdor" },
}

RefreshWatersView = function()
    if not atlasFrame or not atlasFrame.watersPanel then return end
    local p = atlasFrame.watersPanel
    local child = p.scrollChild
    child:Hide()

    local waters = data.GetAllWaters()
    local savedZones = SfuiDB and SfuiDB.fishing and SfuiDB.fishing.zones or {}
    local _, _, _, totalSkill = sfui.fishing.GetFishingSkill()

    local byContinent = {
        eastern_kingdoms = {},
        kalimdor         = {},
    }
    local filteredAll = {}

    for _, w in ipairs(waters) do
        local contKey = w.continent or (data.GetZoneContinent and data.GetZoneContinent(w.mapID)) or "eastern_kingdoms"
        local matchContinent = (watersContinentFilter == "all") or (contKey == watersContinentFilter)
        if matchContinent then
            local name = data.GetZoneName(w.mapID) or ("map " .. w.mapID)
            if (watersFilterText == "") or (name:find(watersFilterText, 1, true) ~= nil) then
                local bucket = byContinent[contKey] or byContinent.eastern_kingdoms
                bucket[#bucket + 1] = w
                filteredAll[#filteredAll + 1] = w
            end
        end
    end

    local pool = p.zoneRowsPool
    local headerPool = p.continentHeadersPool
    local HEADER_H = 24
    local ROW_H = 32
    local yOffset = 0
    local rowIdx = 0
    local headerIdx = 0

    for _, sec in ipairs(CONTINENT_SECTIONS) do
        local list = byContinent[sec.key]
        if list and #list > 0 then
            headerIdx = headerIdx + 1
            local hdr = headerPool[headerIdx]
            if not hdr then
                hdr = CreateFrame("Frame", nil, child, "BackdropTemplate")
                hdr:SetSize(304, HEADER_H)
                common.apply_flat_backdrop(hdr, { 0.12, 0.16, 0.22, 0.85 }, { 0.25, 0.35, 0.45, 0.8 })

                local titleFs = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                titleFs:SetPoint("LEFT", hdr, "LEFT", 8, 0)
                titleFs:SetJustifyH("LEFT")
                titleFs:SetTextColor(0, 1, 1)
                hdr.titleFs = titleFs

                local countFs = hdr:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                countFs:SetPoint("RIGHT", hdr, "RIGHT", -8, 0)
                countFs:SetJustifyH("RIGHT")
                hdr.countFs = countFs

                headerPool[headerIdx] = hdr
            end

            if yOffset > 0 then
                yOffset = yOffset + 6
            end
            hdr:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -yOffset)

            local fishedZones = 0
            for _, w in ipairs(list) do
                local zStats = savedZones[w.mapID]
                if zStats and (zStats.catches or 0) > 0 then
                    fishedZones = fishedZones + 1
                end
            end
            hdr.titleFs:SetText(sec.label)
            hdr.countFs:SetText(string_format("%d / %d fished", fishedZones, #list))
            hdr:Show()
            yOffset = yOffset + HEADER_H + 4

            for _, w in ipairs(list) do
                rowIdx = rowIdx + 1
                local row = pool[rowIdx]
                if not row then
                    row = CreateFrame("Button", nil, child, "BackdropTemplate")
                    row:SetSize(304, ROW_H)

                    local nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    nameFs:SetPoint("LEFT", row, "LEFT", 10, 0)
                    nameFs:SetJustifyH("LEFT")
                    row.nameFs = nameFs

                    local badge = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    badge:SetPoint("RIGHT", row, "RIGHT", -10, 0)
                    badge:SetJustifyH("RIGHT")
                    row.badge = badge

                    row:SetScript("OnClick", function(self)
                        selectedZoneMapID = self.mapID
                        UpdateZoneDetail(self.mapID)
                    end)

                    pool[rowIdx] = row
                end

                row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -yOffset)

                local zoneName = data.GetZoneName(w.mapID) or ("map " .. w.mapID)
                row.nameFs:SetText(zoneName)

                local isQualified = totalSkill >= w.reqSkill
                local skillCol = isQualified and "|cff00ff88" or "|cffff4444"
                local zStats = savedZones[w.mapID]
                local catchesCount = zStats and zStats.catches or 0

                row.badge:SetText(string_format("%sskill %d|r  (|cffffffff%d caught|r)", skillCol, w.reqSkill, catchesCount))

                if theme and theme.ApplyCardStyle then
                    theme.ApplyCardStyle(row, (w.mapID == selectedZoneMapID) and 2 or 1)
                else
                    common.apply_flat_backdrop(row, (w.mapID == selectedZoneMapID) and { 0.25, 0.20, 0.06, 0.85 } or { 0.08, 0.08, 0.10, 0.7 }, { 0.25, 0.25, 0.3, 0.7 })
                end

                row.mapID = w.mapID
                row:Show()
                yOffset = yOffset + ROW_H + 4
            end
        end
    end

    for i = headerIdx + 1, #headerPool do
        headerPool[i]:Hide()
    end
    for i = rowIdx + 1, #pool do
        pool[i]:Hide()
    end

    child:SetHeight(math.max(yOffset, 10))
    child:Show()

    if not selectedZoneMapID and #filteredAll > 0 then
        selectedZoneMapID = filteredAll[1].mapID
    end
    if selectedZoneMapID then
        UpdateZoneDetail(selectedZoneMapID)
    end
end

RefreshLogbookView = function()
    if not atlasFrame or not atlasFrame.logbookPanel then return end
    local p = atlasFrame.logbookPanel

    -- Current Session
    local s, elapsed, fph = sfui.fishing.GetSessionMetrics()
    if s then
        local lines = {
            string_format("session duration: |cffffffff%s|r", common.format_time and common.format_time(elapsed) or string_format("%d mins", math_floor(elapsed / 60))),
            string_format("total casts: |cffffffff%d|r", s.casts or 0),
            string_format("successful catches: |cff00ff88%d|r", s.catches or 0),
            string_format("getaways (escaped): |cffff4444%d|r", s.getaways or 0),
            string_format("current streak: |cff00ff88%d in a row|r", s.streak or 0),
            string_format("catch rate: |cffffd100%d fish / hour|r", fph),
        }
        p.sessionCard.text:SetText(table.concat(lines, "\n"))
    else
        p.sessionCard.text:SetText("no active session.")
    end

    -- Lifetime Records
    local records = SfuiDB and SfuiDB.fishing and SfuiDB.fishing.records or {}
    local totalCatches = 0
    local totalGetaways = 0
    local totalCasts = 0

    if SfuiDB and SfuiDB.fishing and SfuiDB.fishing.zones then
        for _, z in pairs(SfuiDB.fishing.zones) do
            totalCatches = totalCatches + (z.catches or 0)
            totalGetaways = totalGetaways + (z.getaways or 0)
            totalCasts = totalCasts + (z.casts or 0)
        end
    end

    local escapeRate = (totalCasts > 0) and ((totalGetaways / totalCasts) * 100) or 0
    local rLines = {
        string_format("longest streak without getaway: |cff00ff88%d|r", records.longestStreak or 0),
        string_format("total lifetime catches: |cffffffff%d|r", totalCatches),
        string_format("total lifetime casts: |cffffffff%d|r", totalCasts),
        string_format("total getaways: |cffff4444%d|r (%.1f%% escape rate)", totalGetaways, escapeRate),
    }
    local anglers = sfui.fishing and sfui.fishing.GetSyncedAnglers and sfui.fishing.GetSyncedAnglers() or nil
    if type(anglers) == "table" and #anglers > 0 then
        rLines[#rLines + 1] = ""
        rLines[#rLines + 1] = "|cff00ffffsynced anglers (all accounts):|r"
        for i = 1, math.min(#anglers, 5) do
            local a = anglers[i]
            local skillStr = (a.skill and a.skill > 0)
                and string_format("skill %d/%d • ", a.skill, a.maxSkill or a.skill)
                or ""
            rLines[#rLines + 1] = string_format("• %s%s: %s|cff00ff88%d|r caught (%d spp)",
                a.coloredName or a.name or "?", a.accountTag or "", skillStr, a.totalCatches or 0, a.uniqueSpecies or 0)
        end
    end
    p.recordsCard.text:SetText(table.concat(rLines, "\n"))

    -- Milestones (ordered progression tiers, evaluated against maxRank & rank)
    local rank, maxRank = sfui.fishing.GetFishingSkill()
    local playerLevel = _G.UnitLevel and _G.UnitLevel("player")
    local mLines = {}
    for _, m in ipairs(data.MILESTONES) do
        local st = data.GetMilestoneStatus(m, rank, maxRank, playerLevel)
        local statusBadge
        if st == "learned" then
            statusBadge = "|cff00ff88[learned]|r"
        elseif st == "capped" then
            statusBadge = "|cffff4444[capped!]|r"
        elseif st == "available" then
            statusBadge = "|cffffaa00[available]|r"
        elseif st == "level_locked" then
            statusBadge = string_format("|cffffaa00[need lvl %d]|r", m.reqLevel or 0)
        else
            statusBadge = "|cff888888[locked]|r"
        end
        mLines[#mLines + 1] = string_format("%s |cffffd100%s (cap %d)|r: %s", statusBadge, m.tier or "tier", m.maxRank or 0, m.text)
    end
    p.milestonesCard.text:SetText(table.concat(mLines, "\n\n"))
end

-- ─── Tab Switching & Public API ──────────────────────────────────────────────

local function RefreshActiveTab()
    if activeTab == "atlas" then
        RefreshAtlasView()
    elseif activeTab == "waters" then
        RefreshWatersView()
    elseif activeTab == "logbook" then
        RefreshLogbookView()
    end
end

function ATLAS.ShowTab(tabID)
    activeTab = tabID or "atlas"
    if not atlasFrame then
        CreateAtlasWindow()
    end

    atlasFrame.atlasPanel:SetShown(activeTab == "atlas")
    atlasFrame.watersPanel:SetShown(activeTab == "waters")
    atlasFrame.logbookPanel:SetShown(activeTab == "logbook")

    for id, btn in pairs(atlasFrame.tabs) do
        local isSelected = (id == activeTab)
        if theme and theme.ApplyTabStyle then
            theme.ApplyTabStyle(btn, isSelected)
        else
            common.apply_flat_backdrop(btn, isSelected and { 0.25, 0.20, 0.06, 0.85 } or { 0.1, 0.1, 0.12, 0.5 }, { 0.3, 0.3, 0.35, 0.8 })
        end
    end

    RefreshActiveTab()
end

function ATLAS.Toggle()
    local f = atlasFrame or CreateAtlasWindow()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        ATLAS.ShowTab(activeTab)
    end
end

function ATLAS.OpenToSpecies(itemID)
    local id = tonumber(itemID)
    if not id then return false end
    local f = atlasFrame or CreateAtlasWindow()
    speciesFilterText = ""
    speciesCategoryFilter = "all"
    selectedSpeciesID = id
    if f.atlasPanel and f.atlasPanel.searchBox then
        f.atlasPanel.searchBox:SetText("")
    end
    f:Show()
    ATLAS.ShowTab("atlas")
    return true
end

function ATLAS.OpenToZone(mapID)
    local id = tonumber(mapID)
    if not id then return false end
    local f = atlasFrame or CreateAtlasWindow()
    watersFilterText = ""
    watersContinentFilter = "all"
    selectedZoneMapID = id
    if f.watersPanel and f.watersPanel.searchBox then
        f.watersPanel.searchBox:SetText("")
    end
    f:Show()
    ATLAS.ShowTab("waters")
    return true
end

function ATLAS.Update()
    if atlasFrame and atlasFrame:IsShown() then
        RefreshActiveTab()
    end
end

function ATLAS.GetFrame()
    return atlasFrame
end

function ATLAS.GetPoolStats()
    local p1 = (atlasFrame and atlasFrame.atlasPanel and atlasFrame.atlasPanel.cardsPool) and #atlasFrame.atlasPanel.cardsPool or 0
    local p2 = (atlasFrame and atlasFrame.watersPanel and atlasFrame.watersPanel.zoneRowsPool) and #atlasFrame.watersPanel.zoneRowsPool or 0
    local p3 = (atlasFrame and atlasFrame.atlasPanel and atlasFrame.atlasPanel.detail and atlasFrame.atlasPanel.detail.watersPool) and #atlasFrame.atlasPanel.detail.watersPool or 0
    local p4 = (atlasFrame and atlasFrame.watersPanel and atlasFrame.watersPanel.detail and atlasFrame.watersPanel.detail.speciesPool) and #atlasFrame.watersPanel.detail.speciesPool or 0
    return {
        cards = p1,
        zones = p2,
        detailWaters = p3,
        detailSpecies = p4,
        total = p1 + p2 + p3 + p4,
    }
end

-- ─── Dispatcher Message & Event Wiring ───────────────────────────────────────

local events = sfui.events
if events and events.RegisterMessage then
    events.RegisterMessage("SFUI_FISHING_CATCH_RECORDED", ATLAS.Update)
    events.RegisterMessage("SFUI_FISHING_SESSION_RESET", ATLAS.Update)
    events.RegisterMessage("SFUI_SYNC_STATUS_UPDATED", ATLAS.Update)
end

if events and events.RegisterEvent then
    events.RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
        if not atlasFrame or not atlasFrame:IsShown() then return end
        if common and common.debounce then
            common.debounce("fishing_atlas_item_info", 0.25, ATLAS.Update)
        else
            ATLAS.Update()
        end
    end)
end

-- ─── Item Tooltip Hint Provider ──────────────────────────────────────────────

local function OnFishingItemTooltip(tip, ctxOrData)
    if not tip or not tip.AddLine or tip._sfuiInFishingAtlas or tip._sfuiFishingHintDone then return end
    if not data or not data.GetAllSpecies then return end

    local itemID = (ctxOrData and (ctxOrData.itemID or ctxOrData.id)) or nil
    if not itemID and tip.GetItem then
        local _, link = tip:GetItem()
        if link and type(link) == "string" then
            itemID = _G.tonumber(link:match("item:(%d+)"))
        end
    end
    if not itemID then return end

    local allSpecies = data.GetAllSpecies()
    if not allSpecies or not allSpecies[itemID] then return end

    tip._sfuiFishingHintDone = true
    local totalCaught = 0
    if sfui.fishing and sfui.fishing.GetSpeciesCharBreakdown then
        local _, total = sfui.fishing.GetSpeciesCharBreakdown(itemID)
        totalCaught = total or 0
    elseif SfuiDB and SfuiDB.fishing and SfuiDB.fishing.species and SfuiDB.fishing.species[itemID] then
        totalCaught = SfuiDB.fishing.species[itemID].n or 0
    end

    tip:AddLine(" ")
    if totalCaught > 0 then
        tip:AddLine(string_format("|cff00e5fffishing atlas:|r caught %d · |cff80c0ffctrl-click to open|r", totalCaught), 0.5, 0.8, 1)
    else
        tip:AddLine("|cff80c0ffctrl-click to open fishing atlas|r", 0.5, 0.8, 1)
    end
    if tip:IsShown() then
        tip:Show()
    end
end

local function ClearFishingItemTooltip(tip)
    if tip then
        tip._sfuiFishingHintDone = nil
        tip._sfuiInFishingAtlas = nil
    end
end

if sfui.tooltips and sfui.tooltips.RegisterItemProvider then
    sfui.tooltips.RegisterItemProvider("fishing_atlas", 45, OnFishingItemTooltip)
    sfui.tooltips.RegisterClearCallback("fishing_atlas", ClearFishingItemTooltip)
end
