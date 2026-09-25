local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.alts = sfui.alts or {}

local cfg = sfui.config.alts or {}

-- Localized APIs
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local UnitGUID = _G.UnitGUID
local UnitName = _G.UnitName
local UnitClass = _G.UnitClass
local UnitRace = _G.UnitRace
local UnitLevel = _G.UnitLevel
local GetAverageItemLevel = _G.GetAverageItemLevel
local GetServerTime = _G.GetServerTime
local GetMoney = _G.GetMoney
local table = _G.table
local math = _G.math
local math_max = math.max
local wipe = _G.wipe
local C_Timer = _G.C_Timer
local unpack = _G.unpack or table.unpack
local tostring = _G.tostring
local tonumber = _G.tonumber
local string = _G.string
local ipairs = _G.ipairs
local pairs = _G.pairs
local type = _G.type
local GameTooltip = _G.GameTooltip
local RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS
local NORMAL_FONT_COLOR = _G.NORMAL_FONT_COLOR
local GREEN_FONT_COLOR = _G.GREEN_FONT_COLOR
local RED_FONT_COLOR = _G.RED_FONT_COLOR
local CloseDropDownMenus = _G.CloseDropDownMenus
local GetGuildInfo = _G.GetGuildInfo
local RequestTimePlayed = _G.RequestTimePlayed
local GetRealmName = _G.GetNormalizedRealmName or _G.GetRealmName
local StaticPopupDialogs = _G.StaticPopupDialogs
local StaticPopup_Show = _G.StaticPopup_Show

-- Frame & Table Pooling
local columnPool = {}
local cellPool = {}
local tablePool = {}

local function AcquireTable()
    local t = table.remove(tablePool) or {}
    t.isDynamic = true
    return t
end

local function ReleaseTable(t)
    if not t then return end
    wipe(t)
    tablePool[#tablePool + 1] = t
end

local function ReleaseTableRecursive(t)
    if not t then return end
    for k, v in pairs(t) do
        if type(v) == "table" then
            ReleaseTableRecursive(v)
        end
    end
    ReleaseTable(t)
end

local function AcquireColumn(parent)
    local f = table.remove(columnPool)
    if not f then
        f = CreateFrame("Frame", nil, parent)
    else
        f:SetParent(parent)
        f:Show()
    end
    return f
end

local function ReleaseColumn(f)
    f:Hide()
    f:SetParent(nil)
    f:ClearAllPoints()
    columnPool[#columnPool + 1] = f
end

local function AcquireCell(parent)
    local f = table.remove(cellPool)
    if not f then
        f = CreateFrame("Frame", nil, parent)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.text:SetPoint("CENTER")
        f.text:SetJustifyH("CENTER")
        f.text:SetWidth(0)
    else
        f:SetParent(parent)
        f:Show()
        if f.text then
            f.text:Show()
            f.text:ClearAllPoints()
            f.text:SetText("")
            f.text:SetTextColor(unpack(sfui.config.colors.white))
            f.text:SetFontObject("GameFontHighlightSmall")
            f.text:SetPoint("CENTER")
            f.text:SetJustifyH("CENTER")
            f.text:SetWidth(0)
            f.text:SetWordWrap(true)
        end
        if f.rightText then
            f.rightText:Hide()
            f.rightText:ClearAllPoints()
            f.rightText:SetText("")
            f.rightText:SetJustifyH("RIGHT")
            f.rightText:SetWidth(0)
        end
        local regions = { f:GetRegions() }
        for _, r in ipairs(regions) do
            if r ~= f.text and r ~= f.rightText then
                if r:IsObjectType("Texture") or r:IsObjectType("FontString") then
                    r:Hide()
                end
            end
        end
        local children = { f:GetChildren() }
        for _, c in ipairs(children) do
            c:Hide()
        end
    end
    return f
end

local function ReleaseCell(f)
    f:Hide()
    f:SetParent(nil)
    f:ClearAllPoints()
    f:EnableMouse(false)
    f:SetScript("OnEnter", nil)
    f:SetScript("OnLeave", nil)
    f:SetScript("OnMouseUp", nil)
    if f.text then
        f.text:ClearAllPoints()
        f.text:SetWidth(0)
        f.text:SetJustifyH("CENTER")
        f.text:SetText("")
    end
    if f.rightText then
        f.rightText:Hide()
        f.rightText:ClearAllPoints()
        f.rightText:SetWidth(0)
        f.rightText:SetText("")
    end
    if f.del then
        f.del:SetScript("OnClick", nil)
        f.del:SetScript("OnEnter", nil)
        f.del:SetScript("OnLeave", nil)
        f.del:Hide()
    end
    if f.diamondIcon then
        f.diamondIcon:Hide()
    end
    cellPool[#cellPool + 1] = f
end

-- Expose pooling utilities to providers
sfui.alts.AcquireTable = AcquireTable
sfui.alts.ReleaseTable = ReleaseTable
sfui.alts.ReleaseTableRecursive = ReleaseTableRecursive
sfui.alts.AcquireCell = AcquireCell
sfui.alts.ReleaseCell = ReleaseCell
sfui.alts.AcquireColumn = AcquireColumn
sfui.alts.ReleaseColumn = ReleaseColumn

local function GetCurrentCharacterGUID()
    local guid = UnitGUID("player")
    if guid then return guid end
    local name, realm = UnitName("player")
    realm = (realm and realm ~= "") and realm or (GetRealmName and GetRealmName())
    if name and realm then
        return string.format("Player-%s-%s", realm, name)
    end
    return nil
end

-- Expose canonical GUID resolver so providers don't duplicate the logic
sfui.alts.GetCurrentCharacterGUID = GetCurrentCharacterGUID

-- Provider Architecture
sfui.alts.provider = nil
function sfui.alts.RegisterProvider(provider)
    sfui.alts.provider = provider
    if sfui.alts.provider and sfui.alts.provider.RegisterEvents and sfui.alts._initialized then
        sfui.alts.provider.RegisterEvents()
    end
end

local DEFAULT_CATEGORIES = {
    { name = "GENERAL",   label = "Character",    type = "header" },
    { name = "ILVL",      label = "Level / iLvl", type = "stat",   key = "iLvl", format = "%.1f" },
}

local function GetCategories()
    if sfui.alts.provider and sfui.alts.provider.GetCategories then
        return sfui.alts.provider.GetCategories() or DEFAULT_CATEGORIES
    end
    return DEFAULT_CATEGORIES
end

function sfui.alts.RefreshDynamicCategories(force)
    if sfui.alts.provider and sfui.alts.provider.RefreshDynamicCategories then
        sfui.alts.provider.RefreshDynamicCategories(force)
    end
end

local syncTimer = nil
local needsSync = true
local leavingWorld = false

function sfui.alts.SyncCurrentCharacter()
    if syncTimer then return end
    needsSync = true
    syncTimer = C_Timer.NewTimer(1.0, function()
        syncTimer = nil
        if not needsSync then return end
        needsSync = false
        sfui.alts.PerformSync()
        sfui.alts.UpdateUI()
    end)
end

function sfui.alts.CheckWeeklyResets()
    if sfui.alts.provider and sfui.alts.provider.CheckWeeklyResets then
        return sfui.alts.provider.CheckWeeklyResets()
    end
    return nil
end

function sfui.alts.PerformSync(isLogout)
    if not isLogout and leavingWorld then return end

    if syncTimer then
        syncTimer:Cancel()
        syncTimer = nil
    end

    local guid = GetCurrentCharacterGUID()
    if not guid then return end

    local name, realm = UnitName("player")
    if not name or name == "Unknown" then return end

    SfuiDB.alts = SfuiDB.alts or {}
    local d = SfuiDB.alts[guid] or {}

    d.name = name
    d.realm = (realm and realm ~= "") and realm or (GetRealmName and GetRealmName())
    local _, englishClass = UnitClass("player")
    d.class = englishClass
    local _, englishRace = UnitRace("player")
    d.race = englishRace
    d.level = UnitLevel("player")
    d.money = GetMoney()
    d.lastUpdate = GetServerTime()
    d.lastSeen = GetServerTime()

    if GetGuildInfo then
        d.guild = GetGuildInfo("player")
    end

    if GetAverageItemLevel then
        local avg, avgEquipped = GetAverageItemLevel()
        local curIlvl = (avgEquipped and avgEquipped > 0 and avgEquipped) or (avg and avg > 0 and avg)
        if curIlvl and curIlvl > 0 then
            d.iLvl = curIlvl
        end
    end

    -- Hook into client provider for flavor-specific data sync
    if sfui.alts.provider and sfui.alts.provider.PerformSync then
        sfui.alts.provider.PerformSync(d, isLogout)
    end

    SfuiDB.alts[guid] = d
end

-- UI Implementation
local frame = nil
local sortDropdown = nil

local function GetSortOptions()
    return (sfui.alts.provider and sfui.alts.provider.sortOptions) or {
        { text = "Name (A-Z)",  value = "name" },
        { text = "Item Level",  value = "ilvl" },
        { text = "Time Played", value = "timeplayed" },
    }
end

-- Confirmation Dialog for Removing Characters
if StaticPopupDialogs then
    StaticPopupDialogs["SFUI_ALTS_REMOVE_CHARACTER"] = {
        text = "Are you sure you want to remove |cff9966ff%s|r from the Alts list? This will delete all saved data for this character.",
        button1 = "Remove",
        button2 = "Cancel",
        OnAccept = function(self, data)
            if SfuiDB.alts and data and data.guid then
                SfuiDB.alts[data.guid] = nil
                sfui.alts.UpdateUI()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

function sfui.alts.CreateFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "SfuiAltsFrame", UIParent, "BackdropTemplate")
    table.insert(_G.UISpecialFrames, "SfuiAltsFrame")
    frame:SetFrameStrata("DIALOG")
    frame:SetSize(cfg.width or 1000, cfg.height or 650)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnHide", function() CloseDropDownMenus() end)
    frame:SetScript("OnShow", function()
        if sfui.alts.provider and sfui.alts.provider.OnFrameShow then
            sfui.alts.provider.OnFrameShow()
        end
        sfui.alts.RefreshDynamicCategories()
        sfui.alts.PerformSync()
        sfui.alts.UpdateUI(true)
    end)

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(unpack(cfg.backdropColor or { 0.05, 0.05, 0.05, 0.9 }))
    frame:SetBackdropBorderColor(unpack(cfg.borderColor or { 0, 0, 0, 1 }))

    local CreateFlatButton = sfui.common.create_flat_button

    local close = CreateFlatButton(frame, "X", 24, 24)
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- Sort Dropdown
    sortDropdown = sfui.common.create_dropdown(frame, 24, GetSortOptions, function(val)
        SfuiDB.altsSort = val
        sfui.alts.UpdateUI()
    end, SfuiDB.altsSort or "name", "≣")
    sortDropdown:SetPoint("TOPRIGHT", close, "TOPLEFT", -5, 0)

    -- Character Manager Dropdown (=)
    local function populateManagerOptions()
        local options = {}
        for guid, data in pairs(SfuiDB.alts or {}) do
            table.insert(options, {
                guid = guid,
                data = data,
                keepOpen = true,
                onRender = function(parent, opt)
                    local name = opt.data.name or "Unknown"
                    local classColor = RAID_CLASS_COLORS[opt.data.class] or NORMAL_FONT_COLOR
                    local colorStr = classColor and classColor.colorStr or "ffffffff"

                    local t = parent.textString
                    t:SetText(string.format("|c%s%s|r", colorStr, name))

                    -- Remove button [X]
                    parent.xBtn = parent.xBtn or sfui.common.create_flat_button(parent, "X", 18, 16)
                    local xBtn = parent.xBtn
                    xBtn:Show()
                    xBtn:SetPoint("RIGHT", -5, 0)
                    xBtn:SetScript("OnClick", function()
                        if StaticPopup_Show then
                            StaticPopup_Show("SFUI_ALTS_REMOVE_CHARACTER", name, nil, { guid = opt.guid })
                        end
                    end)

                    -- Hide button [H]
                    parent.hBtn = parent.hBtn or sfui.common.create_flat_button(parent, "", 18, 16)
                    local hBtn = parent.hBtn
                    hBtn:Show()
                    local hStatus = opt.data.isHidden and "|cff00ff00H|r" or "|cffccccccH|r"
                    hBtn:SetText(hStatus)
                    hBtn:SetPoint("RIGHT", xBtn, "LEFT", -2, 0)
                    hBtn:SetScript("OnClick", function()
                        opt.data.isHidden = not opt.data.isHidden
                        sfui.alts.UpdateUI()
                        hBtn:SetText(opt.data.isHidden and "|cff00ff00H|r" or "|cffccccccH|r")
                    end)
                end
            })
        end
        return options
    end

    local managerDropdown = sfui.common.create_dropdown(frame, 24, populateManagerOptions, nil, nil, "=", 200)
    managerDropdown:SetPoint("TOPRIGHT", sortDropdown, "TOPLEFT", -5, 0)

    -- Section Manager Dropdown (⚙)
    local function populateSectionsOptions()
        local options = {}
        local cats = GetCategories()
        for _, cat in ipairs(cats) do
            if cat.type == "header" and cat.name ~= "GENERAL" then
                table.insert(options, {
                    catName = cat.name,
                    label = cat.label,
                    keepOpen = true,
                    onRender = function(parent, opt)
                        local t = parent.textString
                        t:SetText(opt.label)

                        if parent.xBtn then parent.xBtn:Hide() end

                        local isHidden = SfuiDB.altsHiddenSections and SfuiDB.altsHiddenSections[opt.catName]
                        local hStatus = isHidden and "|cffff0000H|r" or "|cff00ff00V|r"
                        parent.hBtn = parent.hBtn or sfui.common.create_flat_button(parent, "", 18, 16)
                        local hBtn = parent.hBtn
                        hBtn:Show()
                        hBtn:SetText(hStatus)
                        hBtn:SetPoint("RIGHT", -5, 0)
                        hBtn:SetScript("OnClick", function()
                            SfuiDB.altsHiddenSections = SfuiDB.altsHiddenSections or {}
                            SfuiDB.altsHiddenSections[opt.catName] = not SfuiDB.altsHiddenSections[opt.catName]
                            sfui.alts.UpdateUI()
                            hBtn:SetText(SfuiDB.altsHiddenSections[opt.catName] and "|cffff0000H|r" or "|cff00ff00V|r")
                        end)
                    end
                })
            end
        end

        -- Add M0 Toggle manually if retail/standard provider
        if sfui.alts.provider and sfui.alts.provider.name == "standard" then
            table.insert(options, {
                label = "M0 Dungeons",
                keepOpen = true,
                onRender = function(parent, opt)
                    local t = parent.textString
                    t:SetText(opt.label)
                    if parent.xBtn then parent.xBtn:Hide() end

                    local isHidden = SfuiDB.showM0Dungeons == false
                    local hStatus = isHidden and "|cffff0000H|r" or "|cff00ff00V|r"
                    parent.hBtn = parent.hBtn or sfui.common.create_flat_button(parent, "", 18, 16)
                    local hBtn = parent.hBtn
                    hBtn:Show()
                    hBtn:SetText(hStatus)
                    hBtn:SetPoint("RIGHT", -5, 0)
                    hBtn:SetScript("OnClick", function()
                        SfuiDB.showM0Dungeons = not (SfuiDB.showM0Dungeons ~= false)
                        sfui.alts.RefreshDynamicCategories(true)
                        sfui.alts.UpdateUI()
                        hBtn:SetText(SfuiDB.showM0Dungeons == false and "|cffff0000H|r" or "|cff00ff00V|r")
                    end)
                end
            })
        end

        return options
    end

    local sectionsDropdown = sfui.common.create_dropdown(frame, 24, populateSectionsOptions, nil, nil, "⚙", 150)
    sectionsDropdown:SetPoint("TOPRIGHT", managerDropdown, "TOPLEFT", -5, 0)

    -- Sidebar (Category labels)
    local sidebar = CreateFrame("Frame", nil, frame)
    sidebar:SetPoint("TOPLEFT", 10, -35)
    sidebar:SetPoint("BOTTOMLEFT", 10, 10)
    sidebar:SetWidth(140)
    frame.sidebar = sidebar

    -- Scrollable Content Area for Alt Columns
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame)
    scrollFrame:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 10, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -10, 10)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetHorizontalScroll()
        local maxScroll = self:GetHorizontalScrollRange()
        local step = cfg.columnWidth or 140
        self:SetHorizontalScroll(math.max(0, math.min(maxScroll, cur - (delta * step))))
    end)
    frame.scrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)
    frame.content = content

    frame:Hide()
    return frame
end

local altsList = {}
local visibleCats = {}

local function SortAlts(a, b)
    local sortKey = SfuiDB.altsSort or "name"
    if sfui.alts.provider and sfui.alts.provider.SortAlts then
        local customResult = sfui.alts.provider.SortAlts(a, b, sortKey)
        if customResult ~= nil then return customResult end
    end

    if sortKey == "ilvl" then
        return (a.data.iLvl or 0) > (b.data.iLvl or 0)
    elseif sortKey == "timeplayed" then
        return (a.data.timeplayed or 0) > (b.data.timeplayed or 0)
    else
        return (a.data.name or "") < (b.data.name or "")
    end
end

local updateRequested = false
function sfui.alts.UpdateUI(force)
    if not frame or (not force and not frame:IsVisible()) then return end

    if not force then
        if updateRequested then return end
        updateRequested = true
        C_Timer.After(0, function()
            updateRequested = false
            if frame and frame:IsVisible() then
                sfui.alts.UpdateUI(true)
            end
        end)
        return
    end

    local cats = GetCategories()
    wipe(visibleCats)
    local currentHeader = nil
    SfuiDB.altsHiddenSections = SfuiDB.altsHiddenSections or {}
    SfuiDB.altsCollapsed = SfuiDB.altsCollapsed or {}

    for _, cat in ipairs(cats) do
        if cat.type == "header" then
            if not SfuiDB.altsHiddenSections[cat.name] then
                currentHeader = cat.name
                table.insert(visibleCats, cat)
            else
                currentHeader = nil
            end
        else
            if currentHeader and not SfuiDB.altsCollapsed[currentHeader] then
                table.insert(visibleCats, cat)
            end
        end
    end

    -- Update Sidebar
    if frame.sidebar then
        local children = { frame.sidebar:GetChildren() }
        for _, cell in ipairs(children) do
            ReleaseCell(cell)
        end
        local visY = 0
        for _, cat in ipairs(visibleCats) do
            local row = AcquireCell(frame.sidebar)
            row:SetSize(140, cfg.rowHeight or 25)
            row:SetPoint("TOPLEFT", 0, -visY)

            local text = row.text
            text:Show()
            text:ClearAllPoints()
            text:SetPoint("LEFT", 5, 0)

            if cat.type == "header" then
                text:SetFontObject("GameFontNormal")
                text:SetTextColor(unpack(sfui.config.appearance.highlightColor or { 0.4, 0, 1, 1 }))
                text:SetText(cat.label)

                row:EnableMouse(true)
                row:SetScript("OnMouseUp", function()
                    SfuiDB.altsCollapsed[cat.name] = not SfuiDB.altsCollapsed[cat.name]
                    sfui.alts.UpdateUI(true)
                end)

                if cat.name == "GENERAL" then
                    row:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:AddLine("all characters", 1, 0.82, 0)
                        GameTooltip:AddLine(" ")

                        local totalGold = 0
                        local totalPlayed = 0
                        for _, entry in ipairs(altsList) do
                            totalGold = totalGold + (entry.data.money or 0)
                            totalPlayed = totalPlayed + (entry.data.timeplayed or 0)
                        end

                        if totalGold > 0 then
                            GameTooltip:AddDoubleLine("total gold:", _G.GetMoneyString(totalGold, true),
                                NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1, 0.82, 0)
                        end
                        if totalPlayed > 0 and (not sfui.alts.provider or sfui.alts.provider.showTimePlayedTooltip ~= false) then
                            local hours = math.floor(totalPlayed / 3600)
                            GameTooltip:AddDoubleLine("total time played:", string.format("%d hours", hours),
                                NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1, 1, 1)
                        end

                        GameTooltip:Show()
                    end)
                    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
                else
                    row:SetScript("OnEnter", nil)
                    row:SetScript("OnLeave", nil)
                end
            else
                text:SetFontObject("GameFontHighlightSmall")
                text:SetTextColor(unpack(sfui.config.colors.white))
                text:SetText(cat.label)
                row:EnableMouse(false)
                row:SetScript("OnMouseUp", nil)
                row:SetScript("OnEnter", nil)
                row:SetScript("OnLeave", nil)

                if sfui.alts.provider and sfui.alts.provider.OnSidebarRow then
                    sfui.alts.provider.OnSidebarRow(row, cat)
                end
            end
            visY = visY + (cfg.rowHeight or 25)
        end
    end

    -- Release existing columns
    if not frame.content then return end
    local columns = { frame.content:GetChildren() }
    for _, col in ipairs(columns) do
        local cells = { col:GetChildren() }
        for _, cell in ipairs(cells) do
            ReleaseCell(cell)
        end
        ReleaseColumn(col)
    end

    for i = #altsList, 1, -1 do
        local entry = table.remove(altsList, i)
        ReleaseTable(entry)
    end
    for guid, data in pairs(SfuiDB.alts or {}) do
        if not data.isHidden then
            local entry = AcquireTable()
            entry.guid = guid
            entry.data = data
            altsList[#altsList + 1] = entry
        end
    end

    table.sort(altsList, SortAlts)

    local xOffset = 0
    local curGUID = GetCurrentCharacterGUID()
    local colW = cfg.columnWidth or 140
    local rowH = cfg.rowHeight or 25

    for _, alt in ipairs(altsList) do
        local col = AcquireColumn(frame.content)
        col:SetSize(colW, #visibleCats * rowH)
        col:SetPoint("TOPLEFT", xOffset, 0)

        local classColor = RAID_CLASS_COLORS[alt.data.class] or NORMAL_FONT_COLOR
        local y = 0

        for _, cat in ipairs(visibleCats) do
            local cell = AcquireCell(col)
            cell:SetSize(colW, rowH)
            cell:SetPoint("TOPLEFT", 0, -y)

            local text = cell.text
            text:ClearAllPoints()
            text:SetPoint("CENTER")
            text:SetJustifyH("CENTER")
            text:SetWidth(0)
            text:Show()

            local handled = false
            if sfui.alts.provider and sfui.alts.provider.RenderCell then
                handled = sfui.alts.provider.RenderCell(cell, cat, alt.data, classColor, col, alt.guid)
            end

            if not handled then
                if cat.type == "header" then
                    if cat.name == "GENERAL" then
                        text:SetFontObject("GameFontNormal")
                        text:SetWidth(colW - 6)
                        text:SetWordWrap(false)
                        text:SetText(alt.data.name or "Unknown")
                        text:SetTextColor(classColor.r, classColor.g, classColor.b)

                        if cell.del then cell.del:Hide() end

                        local altSnap = alt
                        cell:EnableMouse(true)
                        cell:SetScript("OnEnter", function(self)
                            local d = altSnap.data
                            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                            local cc = RAID_CLASS_COLORS[d.class] or NORMAL_FONT_COLOR
                            GameTooltip:AddLine(string.format("|c%s%s|r", cc.colorStr or "ffffffff", d.name or "?"), 1, 1, 1)
                            if d.realm then
                                GameTooltip:AddLine(d.realm, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
                            end
                            if d.guild then
                                GameTooltip:AddLine(string.format("<%s>", d.guild), 0.2, 1.0, 0.4)
                            end
                            if d.money and d.money > 0 then
                                GameTooltip:AddLine(" ")
                                GameTooltip:AddLine(_G.GetMoneyString(d.money, true), 1, 0.82, 0)
                            end
                            if sfui.alts.provider and sfui.alts.provider.showTimePlayedTooltip ~= false and d.timeplayed and d.timeplayed > 0 then
                                local hours = math.floor(d.timeplayed / 3600)
                                GameTooltip:AddLine(string.format("time played: %d hours", hours), 0.7, 0.7, 0.7)
                            end

                            GameTooltip:Show()

                            -- Show delete button for non-current characters on hover
                            if altSnap.guid ~= curGUID then
                                if not cell.del then
                                    local del = sfui.common.create_flat_button(cell, "×", 14, 14)
                                    del:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -2, -2)
                                    cell.del = del
                                end
                                cell.del:Show()
                                cell.del:SetScript("OnClick", function()
                                    local charName = altSnap.data.name or "Character"
                                    if StaticPopup_Show then
                                        StaticPopup_Show("SFUI_ALTS_REMOVE_CHARACTER", charName, nil, { guid = altSnap.guid })
                                    else
                                        SfuiDB.alts[altSnap.guid] = nil
                                        sfui.alts.UpdateUI(true)
                                    end
                                end)
                                cell.del:SetScript("OnEnter", function(dSelf)
                                    GameTooltip:SetOwner(dSelf, "ANCHOR_TOP")
                                    GameTooltip:SetText("delete character data", RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b)
                                    GameTooltip:Show()
                                end)
                                cell.del:SetScript("OnLeave", function() GameTooltip:Hide() end)
                            end
                        end)
                        cell:SetScript("OnLeave", function()
                            GameTooltip:Hide()
                            if cell.del and not cell.del:IsMouseOver() then
                                cell.del:Hide()
                            end
                        end)
                    else
                        text:Hide()
                        local line = cell.line or cell:CreateTexture(nil, "BACKGROUND")
                        cell.line = line
                        line:Show()
                        line:SetHeight(1)
                        line:SetPoint("LEFT", 5, -5)
                        line:SetPoint("RIGHT", -5, -5)
                        line:SetColorTexture(0.2, 0.2, 0.2, 0.5)
                    end
                elseif cat.type == "stat" then
                    local val = alt.data[cat.key] or 0
                    text:SetText(cat.format and string.format(cat.format, val) or tostring(val))
                    text:SetTextColor(unpack(sfui.config.colors.white))
                else
                    text:SetText("-")
                    text:SetTextColor(0.5, 0.5, 0.5)
                end
            end

            y = y + rowH
        end

        xOffset = xOffset + colW
    end

    local totalWidth = 140 + 20 + xOffset + 10
    local totalHeight = 35 + (#visibleCats * rowH) + 10
    frame:SetSize(totalWidth, totalHeight)
end

function sfui.alts.Toggle()
    sfui.alts.RefreshDynamicCategories()
    if not frame then
        frame = sfui.alts.CreateFrame()
    end
    if frame:IsShown() then
        frame:Hide()
    else
        sfui.alts.CheckWeeklyResets()
        if sfui.alts.provider and sfui.alts.provider.OnFrameShow then
            sfui.alts.provider.OnFrameShow()
        end
        sfui.alts.PerformSync()
        needsSync = false
        frame:Show()
        sfui.alts.UpdateUI(true)
    end
end

function sfui.alts.ResetWeeklies()
    if sfui.alts.provider and sfui.alts.provider.ResetWeeklies then
        sfui.alts.provider.ResetWeeklies()
    else
        for _, d in pairs(SfuiDB.alts or {}) do
            if d.quests then wipe(d.quests) end
            if d.vault then wipe(d.vault) end
            if d.m0 then wipe(d.m0) end
            if d.raids then wipe(d.raids) end
        end
        sfui.alts.UpdateUI(true)
    end
end

function sfui.alts.initialize()
    if sfui.alts._initialized then return end
    sfui.alts._initialized = true

    SfuiDB.alts = SfuiDB.alts or {}
    SfuiDB.altsCollapsed = SfuiDB.altsCollapsed or {}
    SfuiDB.altsHiddenSections = SfuiDB.altsHiddenSections or {}

    sfui.alts.RefreshDynamicCategories()
    sfui.alts.SyncCurrentCharacter()

    -- Central Event Dispatcher
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        leavingWorld = false
        sfui.alts.SyncCurrentCharacter()
    end)

    sfui.events.RegisterEvent("PLAYER_LEAVING_WORLD", function()
        leavingWorld = true
        local guid = GetCurrentCharacterGUID()
        if guid and SfuiDB.alts and SfuiDB.alts[guid] then
            SfuiDB.alts[guid].lastSeen = GetServerTime()
            if GetMoney then
                SfuiDB.alts[guid].money = GetMoney()
            end
        end
    end)


    sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", function()
        sfui.alts.SyncCurrentCharacter()
    end)

    sfui.events.RegisterEvent("TIME_PLAYED_MSG", function(_, totalTime, currentLevelTime)
        local guid = GetCurrentCharacterGUID()
        if guid and SfuiDB.alts and SfuiDB.alts[guid] then
            SfuiDB.alts[guid].timeplayed = totalTime or 0
        end
    end)

    if RequestTimePlayed and (not sfui.alts.provider or sfui.alts.provider.showTimePlayedTooltip ~= false) then
        RequestTimePlayed()
    end

    local function on_sync_event()
        sfui.alts.SyncCurrentCharacter()
    end
    sfui.events.RegisterEvent("PLAYER_LEVEL_UP",              on_sync_event)
    sfui.events.RegisterEvent("PLAYER_EQUIPMENT_CHANGED",     on_sync_event)
    sfui.events.RegisterEvent("PLAYER_AVG_ITEM_LEVEL_UPDATE", on_sync_event)
    sfui.events.RegisterEvent("PLAYER_MONEY",                 on_sync_event)

    -- Register flavor-specific events from provider
    if sfui.alts.provider and sfui.alts.provider.RegisterEvents then
        sfui.alts.provider.RegisterEvents()
    end
end

function sfui.alts_debug_info()
    local altCount = 0
    if SfuiDB and SfuiDB.alts then
        for _ in pairs(SfuiDB.alts) do altCount = altCount + 1 end
    end
    return {
        columnPool = #columnPool,
        cellPool = #cellPool,
        tablePool = #tablePool,
        trackedAlts = altCount,
        frameCreated = frame ~= nil,
        frameShown = frame and frame:IsShown() or false,
        provider = sfui.alts.provider and sfui.alts.provider.name or "none",
    }
end

-- Stable alias: external code (db.lua, slash commands) may call SaveCurrentCharacter
-- to request a forced logout-safe flush without knowing the internal API.
sfui.alts.SaveCurrentCharacter = function()
    sfui.alts.PerformSync(false)
end


if sfui.RegisterModule then
    sfui.alts.OnEnable = function(self) self.initialize() end
    sfui.alts.GetDebugInfo = sfui.alts_debug_info
    sfui.RegisterModule("alts", sfui.alts)
end

