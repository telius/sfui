--[[
    SFUI Library Book Map Pins
    frames/map/library_pins.lua

    Renders interactive canvas pins on the WorldMap for library books
    and faction librarians in Camelot / Classic Forever.

    Features:
      - Interactive WorldMap pins at exact coordinates
      - Faction librarian pins (Stormwind City / Undercity) with turn-in badge
      - Multi-book grouping with count badge for shared coordinates
      - Automatic status tracking (uncollected, in bags, completed)
      - Shift-Click: Places native map waypoint with SuperTracking
      - Native WorldMap tracking menu checkbox integration
      - Hide collected books by default
--]]

local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
local sfui = _G.sfui or {}
sfui.library_pins = sfui.library_pins or {}

if not sfui.isCamelot then return end

local common = sfui.common
local GameTooltip = sfui.common.get_tooltip()

local _G = _G
local CreateFrame = _G.CreateFrame
local WorldMapFrame = _G.WorldMapFrame
local C_Map = _G.C_Map
local C_SuperTrack = _G.C_SuperTrack
local UiMapPoint = _G.UiMapPoint
local IsShiftKeyDown = _G.IsShiftKeyDown
local pcall = _G.pcall
local ipairs, pairs, type, tostring = _G.ipairs, _G.pairs, _G.type, _G.tostring
local math_abs = math.abs
local table_insert, table_remove = _G.table.insert, _G.table.remove
local string_format = string.format

-- ─── Configuration & Options ──────────────────────────────────────────────────
local activePins = {}
local pinPool = {}
local activeGroups = {}
local groupPool = {}

local isPinsDirty = true
local lastMapID = nil
local lastCanvasW = nil
local lastCanvasH = nil

local function GetOption(key)
    if SfuiDB and SfuiDB.libraryBooks and SfuiDB.libraryBooks[key] ~= nil then
        return SfuiDB.libraryBooks[key]
    end
    if key == "hideCompleted" then
        return true -- hide collected by default
    end
    if key == "showPins" then
        return true
    end
    if key == "showLibrarians" then
        return true
    end
    return true
end

local function SetOption(key, val)
    SfuiDB = SfuiDB or {}
    SfuiDB.libraryBooks = SfuiDB.libraryBooks or {}
    SfuiDB.libraryBooks[key] = val
    isPinsDirty = true
    if WorldMapFrame and WorldMapFrame:IsShown() then
        sfui.library_pins.UpdatePins(true)
    end
end

sfui.library_pins.GetOption = GetOption
sfui.library_pins.SetOption = SetOption

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

-- ─── Book Status Helpers ──────────────────────────────────────────────────────
local function IsQuestCompleted(questID)
    if not questID then return false end
    if _G.C_QuestLog and _G.C_QuestLog.IsQuestFlaggedCompleted then
        local ok, done = pcall(_G.C_QuestLog.IsQuestFlaggedCompleted, questID)
        if ok and done then return true end
    end
    if _G.IsQuestFlaggedCompleted then
        local ok, done = pcall(_G.IsQuestFlaggedCompleted, questID)
        if ok and done then return true end
    end
    return false
end

local function GetItemCountInBags(itemID)
    if not itemID then return 0 end
    if sfui.common and sfui.common.get_item_count then
        local ok, count = pcall(sfui.common.get_item_count, itemID)
        if ok and count then return count end
    end
    if _G.GetItemCount then
        local ok, count = pcall(_G.GetItemCount, itemID, false)
        if ok and count then return count end
    end
    return 0
end

local function GetBookStatus(book)
    if not book then return "unknown" end

    -- Check quest completion
    if book.questID and IsQuestCompleted(book.questID) then
        return "completed"
    end

    -- Check saved collection status in DB
    if SfuiDB and SfuiDB.libraryBooksCollected then
        if SfuiDB.libraryBooksCollected[book.id] or (book.itemID and SfuiDB.libraryBooksCollected[book.itemID]) then
            return "completed"
        end
    end

    -- Check if in bags ready to turn in
    if book.itemID and GetItemCountInBags(book.itemID) > 0 then
        return "in_bags"
    end

    return "uncollected"
end

local function GetOverallProgress()
    local db = sfui.books_camelot
    if not db or not db.books then return 0, 0, 0 end

    local tracked = {}
    local completed = 0
    local inBags = 0
    local total = 0

    for _, b in ipairs(db.books) do
        local key = b.questID or b.title
        if not tracked[key] then
            tracked[key] = true
            total = total + 1
            local status = GetBookStatus(b)
            if status == "completed" then
                completed = completed + 1
            elseif status == "in_bags" then
                inBags = inBags + 1
            end
        end
    end

    return completed, inBags, total
end

-- ─── Group Pooling ────────────────────────────────────────────────────────────
local function ReleaseGroups()
    for _, g in ipairs(activeGroups) do
        _G.wipe(g.books)
        g.librarian = nil
        table_insert(groupPool, g)
    end
    _G.wipe(activeGroups)
end

local function AcquireGroup(mapID, x, y, isLibrarian)
    local g = table_remove(groupPool)
    if not g then
        g = { mapID = mapID, x = x, y = y, isLibrarian = isLibrarian, books = {} }
    else
        g.mapID = mapID
        g.x = x
        g.y = y
        g.isLibrarian = isLibrarian
        _G.wipe(g.books)
    end
    table_insert(activeGroups, g)
    return g
end

local function FindOrCreateBookGroup(mapID, x, y)
    for _, g in ipairs(activeGroups) do
        if not g.isLibrarian and math_abs(g.x - x) < 0.008 and math_abs(g.y - y) < 0.008 then
            return g
        end
    end
    return AcquireGroup(mapID, x, y, false)
end

-- ─── Pin Frame Factory & Pool ─────────────────────────────────────────────────
local function ReleasePins()
    for _, pin in ipairs(activePins) do
        pin:Hide()
        pin.group = nil
    end
    _G.wipe(activePins)
    ReleaseGroups()
end

local function AcquirePin(parent)
    for _, pin in ipairs(pinPool) do
        if not pin:IsShown() then
            pin:SetParent(parent)
            pin.icon:SetDesaturated(false)
            pin.icon:SetVertexColor(1, 1, 1, 1)
            pin:SetBackdropBorderColor(0, 0, 0, 1)
            pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            return pin
        end
    end

    local pin = CreateFrame("Button", nil, parent, "BackdropTemplate")
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pin:SetSize(20, 20)
    pin:SetFrameStrata("HIGH")

    local mult = (sfui.pixelScale or 1)
    pin:SetBackdrop({
        bgFile   = [[Interface\Buttons\WHITE8x8]],
        edgeFile = [[Interface\Buttons\WHITE8x8]],
        edgeSize = mult,
    })
    pin:SetBackdropColor(0.04, 0.04, 0.05, 0.95)
    pin:SetBackdropBorderColor(0, 0, 0, 1)

    local icon = pin:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", pin, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    pin.icon = icon

    local countText = pin:CreateFontString(nil, "OVERLAY")
    local fontPath = (sfui.config and sfui.config.fontFile)
        or (_G.STANDARD_TEXT_FONT and _G.STANDARD_TEXT_FONT ~= "" and _G.STANDARD_TEXT_FONT)
        or "Fonts\\FRIZQT__.TTF"
    countText:SetFont(fontPath, 9, "OUTLINE")
    countText:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", 2, -2)
    countText:SetTextColor(1, 1, 1, 1)
    countText:SetShadowColor(0, 0, 0, 1)
    countText:SetShadowOffset(1, -1)
    pin.countText = countText

    local hi = pin:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetColorTexture(1, 1, 1, 0.25)

    -- Interactive Tooltip
    pin:SetScript("OnEnter", function(self)
        local group = self.group
        if not group then return end

        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()

            local completedCount, inBagsCount, totalBooks = GetOverallProgress()

            if group.isLibrarian then
                local lib = group.librarian
                GameTooltip:AddLine(string_format("%s  ·  faction librarian", lib.name or "librarian"), 0.20, 0.85, 1.00)
                GameTooltip:AddLine(string_format("%s, %s", lib.location or "library", lib.zone or "capital"), 0.70, 0.70, 0.70)
                GameTooltip:AddLine(" ")

                if inBagsCount > 0 then
                    GameTooltip:AddLine(string_format("|cff00ff00%d book%s in bags ready to hand in!|r", inBagsCount, inBagsCount > 1 and "s" or ""))
                else
                    GameTooltip:AddLine("|cff888888no books in bags to hand in|r")
                end

                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("milestone rewards:", 1, 0.82, 0)
                local db = sfui.books_camelot
                if db and db.milestones then
                    for _, m in ipairs(db.milestones) do
                        local done = IsQuestCompleted(m.questID)
                        local statusColor = done and "|cff888888[completed]|r" or (completedCount >= m.count and "|cff00ff00[ready]|r" or string_format("|cff888888[%d/%d]|r", completedCount, m.count))
                        GameTooltip:AddLine(string_format("  • %d books: %s %s", m.count, m.title, statusColor), 0.90, 0.90, 0.95)
                    end
                end

                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(string_format("overall progress: %d / 25 books completed", completedCount), 1, 0.85, 0.20)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cff80c0ffshift-click: set map waypoint with super-tracking|r", 1, 1, 1)
            else
                local numBooks = #group.books
                if numBooks == 1 then
                    local b = group.books[1]
                    local status = GetBookStatus(b)
                    local titleColor = (status == "in_bags" and { 0.20, 1.00, 0.55 })
                        or (status == "completed" and { 0.60, 0.60, 0.60 })
                        or { 1.00, 0.82, 0.00 }

                    GameTooltip:AddLine(b.title or "library book", titleColor[1], titleColor[2], titleColor[3])
                    GameTooltip:AddLine(string_format("container: %s  ·  %s", b.container or "book", b.location or b.zone or "world"), 0.70, 0.70, 0.70)
                    GameTooltip:AddLine(" ")

                    if status == "in_bags" then
                        GameTooltip:AddLine("|cff00ff00status: in bags (ready to hand in)|r")
                    elseif status == "completed" then
                        GameTooltip:AddLine("|cff888888status: completed (turned in)|r")
                    else
                        GameTooltip:AddLine("|cffffcc00status: uncollected|r")
                    end

                    if b.notes and b.notes ~= "" then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine(b.notes, 0.85, 0.85, 0.85, true)
                    end

                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(string_format("overall progress: %d / 25 books completed", completedCount), 1, 0.85, 0.20)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cff80c0ffshift-click: set map waypoint with super-tracking|r", 1, 1, 1)
                else
                    GameTooltip:AddLine(string_format("library books (%d)", numBooks), 1.00, 0.82, 0.00)
                    local first = group.books[1]
                    GameTooltip:AddLine(string_format("%s, %s", first.location or "location", first.zone or "zone"), 0.70, 0.70, 0.70)
                    GameTooltip:AddLine(" ")

                    for _, b in ipairs(group.books) do
                        local status = GetBookStatus(b)
                        local tag = (status == "in_bags" and " |cff00ff00[in bags]|r")
                            or (status == "completed" and " |cff888888[completed]|r")
                            or " |cffffcc00[uncollected]|r"
                        GameTooltip:AddLine(string_format("  • %s%s", b.title, tag), 0.90, 0.90, 0.95, true)
                    end

                    if first.notes and first.notes ~= "" then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine(first.notes, 0.85, 0.85, 0.85, true)
                    end

                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(string_format("overall progress: %d / 25 books completed", completedCount), 1, 0.85, 0.20)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cff80c0ffshift-click: set map waypoint with super-tracking|r", 1, 1, 1)
                end
            end

            GameTooltip:Show()
        end
    end)

    pin:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    -- Click Handler
    pin:SetScript("OnClick", function(self, button)
        local group = self.group
        if not group then return end

        if IsShiftKeyDown() then
            if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
                pcall(function()
                    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(group.mapID, group.x, group.y))
                end)
                if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                    pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
                end
                local label = group.isLibrarian and (group.librarian.name or "faction librarian")
                    or (group.books[1] and group.books[1].title or "library book")
                if sfui.print then
                    sfui.print("waypoint set for " .. label)
                end
            end
        end
    end)

    table_insert(pinPool, pin)
    return pin
end

-- ─── Update Pins on Canvas ────────────────────────────────────────────────────
local function UpdatePins(force)
    if not WorldMapFrame or not WorldMapFrame:IsShown() then
        ReleasePins()
        lastMapID = nil
        return
    end

    if not GetOption("showPins") then
        ReleasePins()
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

    if not force and not isPinsDirty
        and mapID == lastMapID
        and canvasW == lastCanvasW
        and canvasH == lastCanvasH then
        return
    end

    isPinsDirty = false
    lastMapID = mapID
    lastCanvasW = canvasW
    lastCanvasH = canvasH

    ReleasePins()

    local db = sfui.books_camelot
    if not db then return end

    local playerFaction = sfui.common and sfui.common.get_player_faction and sfui.common.get_player_faction() or "Alliance"
    local hideCompleted = GetOption("hideCompleted")

    -- ── 1. Process Librarian Pins ─────────────────────────────────────────────
    if GetOption("showLibrarians") and db.librarians then
        for _, lib in ipairs(db.librarians) do
            if lib.mapID == mapID and (lib.faction == "Both" or lib.faction == playerFaction) then
                local g = AcquireGroup(lib.mapID, lib.x, lib.y, true)
                g.librarian = lib

                local pin = AcquirePin(canvas)
                pin.group = g
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", canvas, "TOPLEFT", canvasW * g.x, -canvasH * g.y)

                pin.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_06")
                pin.icon:SetDesaturated(false)
                pin.icon:SetVertexColor(1, 1, 1, 1)

                local _, inBags = GetOverallProgress()
                if inBags > 0 then
                    pin:SetBackdropBorderColor(0.20, 1.00, 0.40, 1.0)
                    pin.countText:SetText(tostring(inBags))
                    pin.countText:SetTextColor(0.20, 1.00, 0.40, 1.0)
                else
                    pin:SetBackdropBorderColor(0.20, 0.85, 1.00, 1.0)
                    pin.countText:SetText("")
                end

                pin:Show()
                table_insert(activePins, pin)
            end
        end
    end

    -- ── 2. Process Book Locations ─────────────────────────────────────────────
    if db.books then
        for _, b in ipairs(db.books) do
            if b.mapID == mapID then
                local factionEligible = not b.faction or b.faction == "Both" or b.faction == playerFaction
                if factionEligible then
                    local status = GetBookStatus(b)
                    if not hideCompleted or status ~= "completed" then
                        local g = FindOrCreateBookGroup(b.mapID, b.x, b.y)
                        table_insert(g.books, b)
                    end
                end
            end
        end
    end

    -- ── 3. Render Book Group Pins ─────────────────────────────────────────────
    for _, g in ipairs(activeGroups) do
        if not g.isLibrarian and #g.books > 0 then
            local pin = AcquirePin(canvas)
            pin.group = g
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", canvas, "TOPLEFT", canvasW * g.x, -canvasH * g.y)

            local first = g.books[1]
            local iconTexture = first.icon or "Interface\\Icons\\INV_Misc_Book_09"
            pin.icon:SetTexture(iconTexture)

            -- Determine visual state across grouped books
            local hasInBags = false
            local allCompleted = true
            local uncollectedCount = 0

            for _, b in ipairs(g.books) do
                local st = GetBookStatus(b)
                if st == "in_bags" then
                    hasInBags = true
                    allCompleted = false
                elseif st == "uncollected" then
                    allCompleted = false
                    uncollectedCount = uncollectedCount + 1
                end
            end

            if hasInBags then
                pin.icon:SetDesaturated(false)
                pin.icon:SetVertexColor(1, 1, 1, 1)
                pin:SetBackdropBorderColor(0.20, 1.00, 0.40, 1.0)
            elseif allCompleted then
                pin.icon:SetDesaturated(true)
                pin.icon:SetVertexColor(0.7, 0.7, 0.7, 0.8)
                pin:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.8)
            else
                pin.icon:SetDesaturated(false)
                pin.icon:SetVertexColor(1, 1, 1, 1)
                pin:SetBackdropBorderColor(1.00, 0.82, 0.00, 1.0)
            end

            if #g.books > 1 then
                pin.countText:SetText(tostring(#g.books))
                pin.countText:SetTextColor(1, 0.82, 0, 1)
            else
                pin.countText:SetText("")
            end

            pin:Show()
            table_insert(activePins, pin)
        end
    end
end

sfui.library_pins.UpdatePins = UpdatePins

-- ─── Native WorldMap Tracking Dropdown Menu Integration ───────────────────────
local function HookWorldMapTrackingMenu()
    if _G.Menu and _G.Menu.ModifyMenu then
        pcall(_G.Menu.ModifyMenu, "MENU_WORLD_MAP_TRACKING", function(owner, rootDescription)
            rootDescription:CreateDivider()
            rootDescription:CreateTitle("library books")

            rootDescription:CreateCheckbox("library book pins",
                function()
                    return GetOption("showPins")
                end,
                function()
                    SetOption("showPins", not GetOption("showPins"))
                end)

            rootDescription:CreateCheckbox("hide collected books",
                function()
                    return GetOption("hideCompleted")
                end,
                function()
                    SetOption("hideCompleted", not GetOption("hideCompleted"))
                end)

            rootDescription:CreateCheckbox("show faction librarian",
                function()
                    return GetOption("showLibrarians")
                end,
                function()
                    SetOption("showLibrarians", not GetOption("showLibrarians"))
                end)
        end)
    end
end

-- ─── Event Registrations & Lifecycle ──────────────────────────────────────────
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

    if sfui.events and sfui.events.RegisterEvent then
        local function RefreshPinsDelayed()
            isPinsDirty = true
            if WorldMapFrame and WorldMapFrame:IsShown() then
                common.debounce("library_pins_update", 0.15, function()
                    UpdatePins(true)
                end)
            end
        end

        sfui.events.RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
            isPinsDirty = true
            UpdatePins(true)
        end)
        sfui.events.RegisterEvent("ZONE_CHANGED", function()
            isPinsDirty = true
            UpdatePins(true)
        end)
        sfui.events.RegisterEvent("BAG_UPDATE_DELAYED", RefreshPinsDelayed)
        sfui.events.RegisterEvent("QUEST_TURNED_IN", function(questID)
            -- Mark corresponding book in collected cache
            if questID and sfui.books_camelot and sfui.books_camelot.books then
                SfuiDB = SfuiDB or {}
                SfuiDB.libraryBooksCollected = SfuiDB.libraryBooksCollected or {}
                for _, b in ipairs(sfui.books_camelot.books) do
                    if b.questID == questID then
                        SfuiDB.libraryBooksCollected[b.id] = true
                        if b.itemID then
                            SfuiDB.libraryBooksCollected[b.itemID] = true
                        end
                    end
                end
            end
            RefreshPinsDelayed()
        end)
        sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", RefreshPinsDelayed)
    end

    -- Real-time ticker for map zoom/pan synchronization
    if sfui.events and sfui.events.RegisterUpdate then
        sfui.events.RegisterUpdate("LibraryBookPins", 0.5, function()
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
