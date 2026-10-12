local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/map/providers/pins_library.lua
--  WorldMap Pin Provider: Camelot Library Books & Faction Librarians
-- ══════════════════════════════════════════════════════════════════════════════

if sfui.isRetail then return end

local pins = sfui.pins
if not pins then return end

local _G                  = _G
local ipairs              = _G.ipairs
local tostring            = _G.tostring
local string_format       = string.format
local table_insert        = _G.table.insert

-- ─── Configuration & Options ──────────────────────────────────────────────────
local function GetLibraryOption(key)
    if SfuiDB and SfuiDB.libraryBooks and SfuiDB.libraryBooks[key] ~= nil then
        return SfuiDB.libraryBooks[key]
    end
    if key == "hideCompleted" then return true end
    if key == "showPins" then return true end
    if key == "showLibrarians" then return true end
    return true
end

local function SetLibraryOption(key, val)
    SfuiDB = SfuiDB or {}
    SfuiDB.libraryBooks = SfuiDB.libraryBooks or {}
    SfuiDB.libraryBooks[key] = val
    pins.RequestRefresh(0)
end

sfui.library_pins = sfui.library_pins or {}
sfui.library_pins.GetOption = GetLibraryOption
sfui.library_pins.SetOption = SetLibraryOption
function sfui.library_pins.UpdatePins() pins.RequestRefresh(0) end

-- ─── Book Status & Progress Helpers ───────────────────────────────────────────
local function GetBookStatus(book)
    if not book then return "unknown" end
    if book.questID and pins.IsQuestCompleted(book.questID) then
        return "completed"
    end
    if SfuiDB and SfuiDB.libraryBooksCollected then
        if SfuiDB.libraryBooksCollected[book.id] or (book.itemID and SfuiDB.libraryBooksCollected[book.itemID]) then
            return "completed"
        end
    end
    if book.itemID and pins.GetItemCountInBags(book.itemID) > 0 then
        return "in_bags"
    end
    return "uncollected"
end

local function GetOverallLibraryProgress()
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

-- ─── Interactive Tooltip Handlers ─────────────────────────────────────────────
local function OnEnterLibrarian(pin, tooltip, data)
    local lib = data.librarian
    local completedCount, inBagsCount = GetOverallLibraryProgress()
    tooltip:SetOwner(pin, "ANCHOR_RIGHT")
    tooltip:ClearLines()
    tooltip:AddLine(string_format("%s  ·  faction librarian", lib.name or "librarian"), 0.20, 0.85, 1.00)
    tooltip:AddLine(string_format("%s, %s", lib.location or "library", lib.zone or "capital"), 0.70, 0.70, 0.70)
    tooltip:AddLine(" ")

    if inBagsCount > 0 then
        tooltip:AddLine(string_format("|cff00ff00%d book%s in bags ready to hand in!|r", inBagsCount, inBagsCount > 1 and "s" or ""))
    else
        tooltip:AddLine("|cff888888no books in bags to hand in|r")
    end

    tooltip:AddLine(" ")
    tooltip:AddLine("milestone rewards:", 1, 0.82, 0)
    local db = sfui.books_camelot
    if db and db.milestones then
        for _, m in ipairs(db.milestones) do
            local done = pins.IsQuestCompleted(m.questID)
            local statusColor = done and "|cff888888[completed]|r" or (completedCount >= m.count and "|cff00ff00[ready]|r" or string_format("|cff888888[%d/%d]|r", completedCount, m.count))
            tooltip:AddLine(string_format("  • %d books: %s %s", m.count, m.title, statusColor), 0.90, 0.90, 0.95)
        end
    end

    tooltip:AddLine(" ")
    tooltip:AddLine(string_format("overall progress: %d / 25 books completed", completedCount), 1, 0.85, 0.20)
    tooltip:AddLine(" ")
    tooltip:AddLine("|cff80c0ffshift-click: set map waypoint with super-tracking|r", 1, 1, 1)
    tooltip:Show()
end

local function OnEnterBookGroup(pin, tooltip, data)
    local group = data.group
    local numBooks = #group.books
    local completedCount = GetOverallLibraryProgress()
    tooltip:SetOwner(pin, "ANCHOR_RIGHT")
    tooltip:ClearLines()

    if numBooks == 1 then
        local b = group.books[1]
        local status = GetBookStatus(b)
        local titleColor = (status == "in_bags" and { 0.20, 1.00, 0.55 })
            or (status == "completed" and { 0.60, 0.60, 0.60 })
            or { 1.00, 0.82, 0.00 }

        tooltip:AddLine(b.title or "library book", titleColor[1], titleColor[2], titleColor[3])
        tooltip:AddLine(string_format("container: %s  ·  %s", b.container or "book", b.location or b.zone or "world"), 0.70, 0.70, 0.70)
        tooltip:AddLine(" ")

        if status == "in_bags" then
            tooltip:AddLine("|cff00ff00status: in bags (ready to hand in)|r")
        elseif status == "completed" then
            tooltip:AddLine("|cff888888status: completed (turned in)|r")
        else
            tooltip:AddLine("|cffffcc00status: uncollected|r")
        end

        if b.notes and b.notes ~= "" then
            tooltip:AddLine(" ")
            tooltip:AddLine(b.notes, 0.85, 0.85, 0.85, true)
        end

        tooltip:AddLine(" ")
        tooltip:AddLine(string_format("overall progress: %d / 25 books completed", completedCount), 1, 0.85, 0.20)
        tooltip:AddLine(" ")
        tooltip:AddLine("|cff80c0ffshift-click: set map waypoint with super-tracking|r", 1, 1, 1)
    else
        tooltip:AddLine(string_format("library books (%d)", numBooks), 1.00, 0.82, 0.00)
        local first = group.books[1]
        tooltip:AddLine(string_format("%s, %s", first.location or "location", first.zone or "zone"), 0.70, 0.70, 0.70)
        tooltip:AddLine(" ")

        for _, b in ipairs(group.books) do
            local status = GetBookStatus(b)
            local tag = (status == "in_bags" and " |cff00ff00[in bags]|r")
                or (status == "completed" and " |cff888888[completed]|r")
                or " |cffffcc00[uncollected]|r"
            tooltip:AddLine(string_format("  • %s%s", b.title, tag), 0.90, 0.90, 0.95, true)
        end

        if first.notes and first.notes ~= "" then
            tooltip:AddLine(" ")
            tooltip:AddLine(first.notes, 0.85, 0.85, 0.85, true)
        end

        tooltip:AddLine(" ")
        tooltip:AddLine(string_format("overall progress: %d / 25 books completed", completedCount), 1, 0.85, 0.20)
        tooltip:AddLine(" ")
        tooltip:AddLine("|cff80c0ffshift-click: set map waypoint with super-tracking|r", 1, 1, 1)
    end

    tooltip:Show()
end

-- ─── Provider Implementation ──────────────────────────────────────────────────
local function GetLibraryPins(mapID, playerLevel, playerFaction)
    local db = sfui.books_camelot
    if not db then return nil end
    local out = {}

    if GetLibraryOption("showLibrarians") and db.librarians then
        for _, lib in ipairs(db.librarians) do
            if lib.mapID == mapID and (lib.faction == "Both" or lib.faction == playerFaction) then
                local _, inBags = GetOverallLibraryProgress()
                local pinData = {
                    id          = "librarian_" .. (lib.id or lib.name or "lib"),
                    provider    = "library_books",
                    mapID       = lib.mapID,
                    x           = lib.x,
                    y           = lib.y,
                    size        = 20,
                    icon        = "Interface\\Icons\\INV_Misc_Book_06",
                    borderColor = (inBags > 0 and { 0.20, 1.00, 0.40, 1.0 }) or { 0.20, 0.85, 1.00, 1.0 },
                    countText   = (inBags > 0 and tostring(inBags)) or "",
                    countColor  = { 0.20, 1.00, 0.40, 1.0 },
                    title       = lib.name or "faction librarian",
                    librarian   = lib,
                    OnEnter     = OnEnterLibrarian,
                }
                table_insert(out, pinData)
            end
        end
    end

    if db.books then
        local hideCompleted = GetLibraryOption("hideCompleted")
        local groups = {}

        for _, b in ipairs(db.books) do
            if b.mapID == mapID then
                local factionEligible = not b.faction or b.faction == "Both" or b.faction == playerFaction
                if factionEligible then
                    local status = GetBookStatus(b)
                    if not hideCompleted or status ~= "completed" then
                        local g = pins.FindOrCreateGroup(groups, b.x, b.y, 0.008, mapID)
                        g.books = g.books or {}
                        table_insert(g.books, b)
                    end
                end
            end
        end

        for _, g in ipairs(groups) do
            if g.books and #g.books > 0 then
                local first = g.books[1]
                local iconTexture = first.icon or "Interface\\Icons\\INV_Misc_Book_09"
                local hasInBags = false
                local allCompleted = true

                for _, b in ipairs(g.books) do
                    local st = GetBookStatus(b)
                    if st == "in_bags" then
                        hasInBags = true
                        allCompleted = false
                    elseif st == "uncollected" then
                        allCompleted = false
                    end
                end

                local borderColor
                local desaturated = false
                local vertexColor = { 1, 1, 1, 1 }

                if hasInBags then
                    borderColor = { 0.20, 1.00, 0.40, 1.0 }
                elseif allCompleted then
                    borderColor = { 0.35, 0.35, 0.35, 0.8 }
                    desaturated = true
                    vertexColor = { 0.7, 0.7, 0.7, 0.8 }
                else
                    borderColor = { 1.00, 0.82, 0.00, 1.0 }
                end

                local pinData = {
                    id          = "book_" .. (first.id or first.questID or "group"),
                    provider    = "library_books",
                    mapID       = g.mapID,
                    x           = g.x,
                    y           = g.y,
                    size        = 20,
                    icon        = iconTexture,
                    desaturated = desaturated,
                    vertexColor = vertexColor,
                    borderColor = borderColor,
                    count       = (#g.books > 1 and #g.books) or nil,
                    countColor  = { 1, 0.82, 0, 1 },
                    title       = first.title or "library book",
                    group       = g,
                    OnEnter     = OnEnterBookGroup,
                }
                table_insert(out, pinData)
            end
        end
    end

    return out
end

-- ─── Provider & Menu Registration ─────────────────────────────────────────────
pins.RegisterProvider("library_books", {
    priority    = 20,
    defaultSize = 20,
    enabled     = function() return GetLibraryOption("showPins") end,
    GetPins     = GetLibraryPins,
})

pins.RegisterTrackingCategory("library books", {
    { text = "library book pins", get = function() return GetLibraryOption("showPins") end, set = function(v) SetLibraryOption("showPins", v) end },
    { text = "hide collected books", get = function() return GetLibraryOption("hideCompleted") end, set = function(v) SetLibraryOption("hideCompleted", v) end },
    { text = "show faction librarian", get = function() return GetLibraryOption("showLibrarians") end, set = function(v) SetLibraryOption("showLibrarians", v) end },
})

if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("QUEST_TURNED_IN", function(questID)
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
    end)
end
