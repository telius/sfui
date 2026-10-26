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
local UISpecialFrames = _G.UISpecialFrames
local ipairs, pairs = _G.ipairs, _G.pairs
local table_sort = _G.table.sort
local table_insert = _G.table.insert
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

    -- Register with UISpecialFrames so Escape closes it
    table_insert(UISpecialFrames, "SfuiFishingAtlasFrame")

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

    -- Subtitle
    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -26)
    sub:SetText("camelot & classic forever")

    -- Top Tab Row
    local tabContainer = CreateFrame("Frame", nil, f)
    tabContainer:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -44)
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
    content:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -76)
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

-- ─── Tab 1: Fish Atlas (Species Cards & Details) ─────────────────────────────

BuildAtlasTab = function(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()

    -- Search Bar & Category Filters
    local searchBox = CreateFrame("EditBox", nil, p, "BackdropTemplate")
    searchBox:SetSize(180, 22)
    searchBox:SetPoint("TOPLEFT", p, "TOPLEFT", 4, -4)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject("GameFontHighlightSmall")
    searchBox:SetTextInsets(6, 6, 2, 2)
    if theme and theme.ApplyInputStyle then
        theme.ApplyInputStyle(searchBox)
    else
        common.apply_flat_backdrop(searchBox, { 0.1, 0.1, 0.12, 0.8 }, { 0.3, 0.3, 0.35, 0.8 })
    end

    local searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchPlaceholder:SetPoint("LEFT", searchBox, "LEFT", 8, 0)
    searchPlaceholder:SetText("search species...")
    searchBox.placeholder = searchPlaceholder

    searchBox:SetScript("OnTextChanged", function(self)
        local txt = self:GetText()
        speciesFilterText = txt and txt:lower() or ""
        searchPlaceholder:SetShown(speciesFilterText == "")
        RefreshAtlasView()
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    p.searchBox = searchBox

    -- Filter Buttons: all, fish, containers, caught, missing
    local catFilters = {
        { id = "all",        text = "all" },
        { id = "fish",       text = "fish" },
        { id = "containers", text = "containers" },
        { id = "caught",     text = "caught" },
        { id = "missing",    text = "missing" },
    }
    local catBtns = {}
    local prevCat = searchBox
    for _, c in ipairs(catFilters) do
        local b = CreateFrame("Button", nil, p, "BackdropTemplate")
        b:SetHeight(22)
        b:SetWidth(66)
        b:SetPoint("LEFT", prevCat, (prevCat == searchBox) and "RIGHT" or "RIGHT", (prevCat == searchBox) and 8 or 4, 0)
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("CENTER", b, "CENTER", 0, 0)
        fs:SetText(c.text)
        b.fs = fs
        b.id = c.id

        b:SetScript("OnClick", function()
            speciesCategoryFilter = c.id
            for _, ob in pairs(catBtns) do
                if theme and theme.ApplyTabStyle then
                    theme.ApplyTabStyle(ob, ob.id == speciesCategoryFilter)
                else
                    common.apply_flat_backdrop(ob, (ob.id == speciesCategoryFilter) and { 0.25, 0.20, 0.06, 0.85 } or { 0.1, 0.1, 0.12, 0.5 }, { 0.3, 0.3, 0.35, 0.8 })
                end
            end
            RefreshAtlasView()
        end)

        catBtns[c.id] = b
        prevCat = b
    end
    p.catBtns = catBtns

    -- Left Scroll Container (Cards Grid)
    local scrollFrame = CreateFrame("ScrollFrame", "SfuiFishingAtlasScroll", p, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", p, "TOPLEFT", 4, -32)
    scrollFrame:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 4, 4)
    scrollFrame:SetWidth(516)

    if theme and theme.ApplyScrollBarStyle and _G["SfuiFishingAtlasScrollScrollBar"] then
        theme.ApplyScrollBarStyle(_G["SfuiFishingAtlasScrollScrollBar"])
    end

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(500, 1)
    scrollFrame:SetScrollChild(scrollChild)
    p.scrollChild = scrollChild

    -- Right Detail Panel
    local detail = CreateFrame("Frame", nil, p, "BackdropTemplate")
    detail:SetPoint("TOPRIGHT", p, "TOPRIGHT", -4, -4)
    detail:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -4, 4)
    detail:SetWidth(290)
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

    local watersScroll = CreateFrame("ScrollFrame", "SfuiFishingDetailWatersScroll", detail, "UIPanelScrollFrameTemplate")
    watersScroll:SetPoint("TOPLEFT", watersHeader, "BOTTOMLEFT", 0, -4)
    watersScroll:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -20, 10)

    if theme and theme.ApplyScrollBarStyle and _G["SfuiFishingDetailWatersScrollScrollBar"] then
        theme.ApplyScrollBarStyle(_G["SfuiFishingDetailWatersScrollScrollBar"])
    end

    local watersChild = CreateFrame("Frame", nil, watersScroll)
    watersChild:SetSize(250, 1)
    watersScroll:SetScrollChild(watersChild)
    detail.watersChild = watersChild
    detail.watersPool = {}

    p.cardsPool = {}
    return p
end

-- ─── Tab 2: Waters (Zone Directory & Local Species) ──────────────────────────

BuildWatersTab = function(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()

    -- Search Bar for Zones
    local searchBox = CreateFrame("EditBox", nil, p, "BackdropTemplate")
    searchBox:SetSize(180, 22)
    searchBox:SetPoint("TOPLEFT", p, "TOPLEFT", 4, -4)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject("GameFontHighlightSmall")
    searchBox:SetTextInsets(6, 6, 2, 2)
    if theme and theme.ApplyInputStyle then
        theme.ApplyInputStyle(searchBox)
    else
        common.apply_flat_backdrop(searchBox, { 0.1, 0.1, 0.12, 0.8 }, { 0.3, 0.3, 0.35, 0.8 })
    end

    local searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchPlaceholder:SetPoint("LEFT", searchBox, "LEFT", 8, 0)
    searchPlaceholder:SetText("search zones...")
    searchBox.placeholder = searchPlaceholder

    searchBox:SetScript("OnTextChanged", function(self)
        local txt = self:GetText()
        watersFilterText = txt and txt:lower() or ""
        searchPlaceholder:SetShown(watersFilterText == "")
        RefreshWatersView()
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    p.searchBox = searchBox

    -- Left Column: Zone List ScrollFrame
    local scrollFrame = CreateFrame("ScrollFrame", "SfuiWatersListScroll", p, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", p, "TOPLEFT", 4, -32)
    scrollFrame:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 4, 4)
    scrollFrame:SetWidth(440)

    if theme and theme.ApplyScrollBarStyle and _G["SfuiWatersListScrollScrollBar"] then
        theme.ApplyScrollBarStyle(_G["SfuiWatersListScrollScrollBar"])
    end

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(420, 1)
    scrollFrame:SetScrollChild(scrollChild)
    p.scrollChild = scrollChild

    -- Right Column: Zone Species Detail
    local detail = CreateFrame("Frame", nil, p, "BackdropTemplate")
    detail:SetPoint("TOPRIGHT", p, "TOPRIGHT", -4, -4)
    detail:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -4, 4)
    detail:SetPoint("LEFT", scrollFrame, "RIGHT", 14, 0)
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

    local speciesScroll = CreateFrame("ScrollFrame", "SfuiWatersSpeciesScroll", detail, "UIPanelScrollFrameTemplate")
    speciesScroll:SetPoint("TOPLEFT", zoneReq, "BOTTOMLEFT", 0, -10)
    speciesScroll:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -20, 10)

    if theme and theme.ApplyScrollBarStyle and _G["SfuiWatersSpeciesScrollScrollBar"] then
        theme.ApplyScrollBarStyle(_G["SfuiWatersSpeciesScrollScrollBar"])
    end

    local speciesChild = CreateFrame("Frame", nil, speciesScroll)
    speciesChild:SetSize(340, 1)
    speciesScroll:SetScrollChild(speciesChild)
    detail.speciesChild = speciesChild
    detail.speciesPool = {}

    local noFish = speciesChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    noFish:SetPoint("TOPLEFT", speciesChild, "TOPLEFT", 8, -8)
    noFish:SetText("no confirmed fishing species for this zone.")
    noFish:Hide()
    detail.noFishLabel = noFish

    p.zoneRowsPool = {}
    return p
end

-- ─── Tab 3: Logbook (Session & Lifetime Records) ──────────────────────────────

BuildLogbookTab = function(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()

    -- 1. Current Session Card (Top)
    local sessionCard = CreateFrame("Frame", nil, p, "BackdropTemplate")
    sessionCard:SetSize(400, 200)
    sessionCard:SetPoint("TOPLEFT", p, "TOPLEFT", 8, -8)
    if theme and theme.ApplyCardStyle then
        theme.ApplyCardStyle(sessionCard, 1)
    else
        common.apply_flat_backdrop(sessionCard, { 0.08, 0.08, 0.10, 0.8 }, { 0.25, 0.25, 0.30, 0.8 })
    end

    local sTitle = sessionCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sTitle:SetPoint("TOPLEFT", sessionCard, "TOPLEFT", 12, -10)
    sTitle:SetText("current fishing session")
    sTitle:SetTextColor(0, 1, 1)

    local sText = sessionCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sText:SetPoint("TOPLEFT", sTitle, "BOTTOMLEFT", 0, -8)
    sText:SetPoint("RIGHT", sessionCard, "RIGHT", -12, 0)
    sText:SetJustifyH("LEFT")
    sessionCard.text = sText

    local resetBtn = common.create_flat_button(sessionCard, "reset session stats", 140, 22, function()
        sfui.fishing.ResetSession()
    end)
    resetBtn:SetPoint("BOTTOMLEFT", sessionCard, "BOTTOMLEFT", 12, 10)

    -- 2. Lifetime Records Card (Right)
    local recordsCard = CreateFrame("Frame", nil, p, "BackdropTemplate")
    recordsCard:SetSize(400, 200)
    recordsCard:SetPoint("TOPLEFT", sessionCard, "TOPRIGHT", 12, 0)
    if theme and theme.ApplyCardStyle then
        theme.ApplyCardStyle(recordsCard, 1)
    else
        common.apply_flat_backdrop(recordsCard, { 0.08, 0.08, 0.10, 0.8 }, { 0.25, 0.25, 0.30, 0.8 })
    end

    local rTitle = recordsCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    rTitle:SetPoint("TOPLEFT", recordsCard, "TOPLEFT", 12, -10)
    rTitle:SetText("lifetime records")
    rTitle:SetTextColor(0, 1, 1)

    local rText = recordsCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rText:SetPoint("TOPLEFT", rTitle, "BOTTOMLEFT", 0, -8)
    rText:SetPoint("RIGHT", recordsCard, "RIGHT", -12, 0)
    rText:SetJustifyH("LEFT")
    recordsCard.text = rText

    -- 3. Milestones Card (Bottom)
    local milestonesCard = CreateFrame("Frame", nil, p, "BackdropTemplate")
    milestonesCard:SetPoint("TOPLEFT", sessionCard, "BOTTOMLEFT", 0, -12)
    milestonesCard:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -8, 8)
    if theme and theme.ApplyCardStyle then
        theme.ApplyCardStyle(milestonesCard, 1)
    else
        common.apply_flat_backdrop(milestonesCard, { 0.08, 0.08, 0.10, 0.8 }, { 0.25, 0.25, 0.30, 0.8 })
    end

    local mTitle = milestonesCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    mTitle:SetPoint("TOPLEFT", milestonesCard, "TOPLEFT", 12, -10)
    mTitle:SetText("trainer milestones")
    mTitle:SetTextColor(0, 1, 1)

    local mText = milestonesCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mText:SetPoint("TOPLEFT", mTitle, "BOTTOMLEFT", 0, -8)
    mText:SetPoint("RIGHT", milestonesCard, "RIGHT", -12, 0)
    mText:SetJustifyH("LEFT")
    milestonesCard.text = mText

    p.sessionCard = sessionCard
    p.recordsCard = recordsCard
    p.milestonesCard = milestonesCard
    return p
end

-- ─── Detail View Updates ─────────────────────────────────────────────────────

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

    local name, link, quality, _, _, _, _, _, _, texture, sellPrice = common.get_item_info(speciesID)
    det.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_Fish_02")
    det.name:SetText(link or name or ("item:" .. speciesID))

    local kindLabel = item.isContainer and "container / trunk" or "catchable fish"
    det.meta:SetText(string_format("%s • min required skill: %d", kindLabel, item.minSkill or 0))

    -- Catch Statistics
    local savedSpecies = SfuiDB and SfuiDB.fishing and SfuiDB.fishing.species and SfuiDB.fishing.species[speciesID]
    local totalCaught = (savedSpecies and savedSpecies.n) or 0
    local firstDate = savedSpecies and FormatDate(savedSpecies.first) or "never"
    local firstZone = (savedSpecies and savedSpecies.fz and common.get_map_name(savedSpecies.fz)) or "unknown"
    local lastDate = savedSpecies and FormatDate(savedSpecies.last) or "never"
    local lastZone = (savedSpecies and savedSpecies.lz and common.get_map_name(savedSpecies.lz)) or "unknown"

    local statsLines = {
        string_format("total caught: |cffffffff%d|r", totalCaught),
        string_format("first catch: |cffffd100%s|r in %s", firstDate, firstZone:lower()),
        string_format("last catch: |cffffd100%s|r in %s", lastDate, lastZone:lower()),
    }
    if sellPrice and sellPrice > 0 then
        statsLines[#statsLines + 1] = string_format("vendor value: %s", common.format_money(sellPrice))
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

        local zoneName = common.get_map_name(z.mapID) or ("map " .. z.mapID)
        local req = z.reqSkill or 0
        local isQualified = totalSkill >= req
        local skillCol = isQualified and "|cff00ff88" or "|cffff4444"

        row.zLabel:SetText(zoneName:lower())
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
    local zoneName = common.get_map_name(mapID) or ("map " .. tostring(mapID))
    local reqSkill, subArea = data.GetZoneRequirement(mapID)
    local _, _, _, totalSkill = sfui.fishing.GetFishingSkill()

    det.title:SetText(zoneName:lower())
    if reqSkill then
        local color = (totalSkill >= reqSkill) and "|cff00ff88" or "|cffff4444"
        local subText = subArea and string_format(" • %s: |cffffd100%d|r", subArea.area, subArea.skill) or ""
        det.req:SetText(string_format("required skill: %s%d|r (your skill: |cffffffff%d|r)%s", color, reqSkill, totalSkill, subText))
    else
        det.req:SetText("required skill: |cff888888unknown|r")
    end

    local child = det.speciesChild
    child:Hide()
    local pool = det.speciesPool or {}
    det.speciesPool = pool

    local lootEntries, isClassic = data.GetZoneLoot(mapID)
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
                row:SetSize(340, 28)

                local ico = row:CreateTexture(nil, "ARTWORK")
                ico:SetSize(22, 22)
                ico:SetPoint("LEFT", row, "LEFT", 4, 0)
                row.ico = ico

                local nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                nameFs:SetPoint("LEFT", ico, "RIGHT", 6, 0)
                nameFs:SetJustifyH("LEFT")
                row.nameFs = nameFs

                local shareFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                shareFs:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                shareFs:SetJustifyH("RIGHT")
                row.shareFs = shareFs

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
            local count = caughtCounts[itemID] or 0
            local itemName, itemLink, quality, _, _, _, _, _, _, texture = common.get_item_info(itemID)

            row.ico:SetTexture(texture or "Interface\\Icons\\INV_Misc_Fish_02")
            row.nameFs:SetText(itemLink or itemName or ("item:" .. itemID))

            local caughtCol = (count > 0) and "|cff00ff88" or "|cff888888"
            row.shareFs:SetText(string_format("%.1f%%  %scaught %d|r", share or 0, caughtCol, count))

            row:SetScript("OnClick", function()
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
        local name = common.get_item_info(itemID) or ("item:" .. itemID)
        local matchSearch = (speciesFilterText == "") or (name:lower():find(speciesFilterText, 1, true))

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
                selectedSpeciesID = self.speciesID
                UpdateSpeciesDetail(self.speciesID)
            end)

            pool[i] = card
        end

        local col = (i - 1) % COLS
        local row = math_floor((i - 1) / COLS)
        card:SetPoint("TOPLEFT", child, "TOPLEFT", col * (CARD_W + 6), -row * (CARD_H + 6))

        local itemName, itemLink, quality, _, _, _, _, _, _, texture = common.get_item_info(item.itemID)
        card.ico:SetTexture(texture or "Interface\\Icons\\INV_Misc_Fish_02")
        card.nameFs:SetText(itemLink or itemName or ("item:" .. item.itemID))

        local count = savedSpecies[item.itemID] and savedSpecies[item.itemID].n or 0
        if count > 0 then
            card.countFs:SetText(string_format("|cff00ff88caught: %d|r", count))
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

RefreshWatersView = function()
    if not atlasFrame or not atlasFrame.watersPanel then return end
    local p = atlasFrame.watersPanel
    local child = p.scrollChild
    child:Hide()

    local waters = data.GetAllWaters()
    local savedZones = SfuiDB and SfuiDB.fishing and SfuiDB.fishing.zones or {}
    local _, _, _, totalSkill = sfui.fishing.GetFishingSkill()

    local filtered = {}
    for _, w in ipairs(waters) do
        local name = common.get_map_name(w.mapID) or ("map " .. w.mapID)
        if (watersFilterText == "") or (name:lower():find(watersFilterText, 1, true)) then
            filtered[#filtered + 1] = w
        end
    end

    local pool = p.zoneRowsPool
    local ROW_H = 32

    for i, w in ipairs(filtered) do
        local row = pool[i]
        if not row then
            row = CreateFrame("Button", nil, child, "BackdropTemplate")
            row:SetSize(410, ROW_H)

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

            pool[i] = row
        end

        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * (ROW_H + 4))

        local zoneName = common.get_map_name(w.mapID) or ("map " .. w.mapID)
        row.nameFs:SetText(zoneName:lower())

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
    end

    for i = #filtered + 1, #pool do
        pool[i]:Hide()
    end

    child:SetHeight(math.max(#filtered * (ROW_H + 4), 10))
    child:Show()

    if not selectedZoneMapID and #filtered > 0 then
        selectedZoneMapID = filtered[1].mapID
    end
    if selectedZoneMapID then
        UpdateZoneDetail(selectedZoneMapID)
    end
end

RefreshLogbookView = function()
    if not atlasFrame or not atlasFrame.logbookPanel then return end
    local p = atlasFrame.logbookPanel

    -- Current Session
    local s = sfui.fishing.session
    if s then
        local elapsed = GetTime() - (s.startTime or GetTime())
        local fph = (elapsed >= 60 and s.catches and s.catches > 0)
            and math_floor((s.catches / (elapsed / 3600)) + 0.5)
            or 0
        local lines = {
            string_format("session duration: |cffffffff%s|r", common.format_time and common.format_time(elapsed) or string_format("%d mins", math_floor(elapsed / 60))),
            string_format("total casts: |cffffffff%d|r", s.casts or 0),
            string_format("successful catches: |cff00ff88%d|r", s.catches or 0),
            string_format("getaways (escaped): |cffff4444%d|r", s.getaways or 0),
            string_format("current streak: |cff00ff88%d in a row|r", s.streak or 0),
            string_format("catch rate: |cffffd100%d fish / hour|r", fph),
        }
        if s.value and s.value > 0 then
            lines[#lines + 1] = string_format("vendor value: %s", common.format_money(s.value))
        end
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
    p.recordsCard.text:SetText(table.concat(rLines, "\n"))

    -- Milestones
    local rank, maxRank = sfui.fishing.GetFishingSkill()
    local mLines = {}
    for cap, info in pairs(data.MILESTONES) do
        local statusCol = (rank >= cap) and "|cff00ff88[learned]|r" or (rank >= info.from and "|cffffaa00[available]|r" or "|cff888888[locked]|r")
        mLines[#mLines + 1] = string_format("%s |cffffd100cap %d|r: %s", statusCol, cap, info.text)
    end
    p.milestonesCard.text:SetText(table.concat(mLines, "\n\n"))
end

-- ─── Tab Switching & Public API ──────────────────────────────────────────────

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

    if activeTab == "atlas" then
        RefreshAtlasView()
    elseif activeTab == "waters" then
        RefreshWatersView()
    elseif activeTab == "logbook" then
        RefreshLogbookView()
    end
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

function ATLAS.Update()
    if atlasFrame and atlasFrame:IsShown() then
        if activeTab == "atlas" then
            RefreshAtlasView()
        elseif activeTab == "waters" then
            RefreshWatersView()
        elseif activeTab == "logbook" then
            RefreshLogbookView()
        end
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

-- ─── Dispatcher Message Wiring ───────────────────────────────────────────────

local events = sfui.events
if events and events.RegisterMessage then
    events.RegisterMessage("SFUI_FISHING_CATCH_RECORDED", function()
        if atlasFrame and atlasFrame:IsShown() then
            ATLAS.Update()
        end
    end)

    events.RegisterMessage("SFUI_FISHING_SESSION_RESET", function()
        if atlasFrame and atlasFrame:IsShown() then
            ATLAS.Update()
        end
    end)
end
