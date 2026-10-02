local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.dungeonjournal = sfui.dungeonjournal or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/dungeonjournal/dungeonjournal.lua
--  Classic Forever / Camelot Dungeon Journal — main window orchestrator.
--
--  Layout (860 × 600 px):
--    Left sidebar   (200 px)  – scrollable dungeon/raid list, level badges
--    Right content  (640 px)  – tab-switched boss view / quest view
--      Each view: left sub-panel (list) + right detail pane
--
--  Public API:
--    sfui.dungeonjournal.Toggle()
--    sfui.dungeonjournal.Open()
--    sfui.dungeonjournal.SelectDungeon(dungeonID)
--    sfui.dungeonjournal.Rebuild()
--    sfui.dungeonjournal.ClearCache()
--
--  Theme: sfui.theme.ApplyWindowStyle / ApplyHeaderStyle / RegisterWindow
--  DB:    sfui.db.RegisterDefaults  / SfuiDB.dungeonjournal
--  Data:  sfui.dj_camelot  (data/dj_camelot.lua)
-- ══════════════════════════════════════════════════════════════════════════════

-- Guard: Camelot / Classic only
if sfui.isRetail then
    return
end

-- ─── Constants ────────────────────────────────────────────────────────────────
local FRAME_W       = 860
local FRAME_H       = 600
local SIDEBAR_W     = 200
local CONTENT_X     = SIDEBAR_W + 10
local CONTENT_W     = FRAME_W - SIDEBAR_W - 24 -- ~636
local HEADER_H      = 46
local TAB_H         = 28
local INNER_PAD     = 10

-- ─── Locals ───────────────────────────────────────────────────────────────────
local pairs, ipairs, type, tostring = pairs, ipairs, type, tostring
local math_max, math_floor          = math.max, math.floor
local table_insert, table_sort      = table.insert, table.sort

local common  = sfui.common
local theme   = sfui.theme

local frame            = nil   -- main window (lazy-created)
local sidebarFrame     = nil
local bossPanel        = nil
local questPanel       = nil

local selectedDungeonID = nil  -- dungeon id string
local selectedMode      = "bosses"  -- "bosses" | "quests"
local selectedTab       = "dungeons" -- "dungeons" | "raids"

-- ─── SavedVariables helpers ───────────────────────────────────────────────────
sfui.db.RegisterDefaults("dungeonjournal", {
    lastDungeon        = nil,
    lastMode           = "bosses",
    lastTab            = "dungeons",
    questFaction       = "all",
    lastBoss           = 1,
    lastQuest          = 1,
    autoDetectInstance = true,
    showItemTooltips   = true,
    wishlist           = {},
})

local function DJ_DB()
    SfuiDB.dungeonjournal = SfuiDB.dungeonjournal or {}
    SfuiDB.dungeonjournal.wishlist = SfuiDB.dungeonjournal.wishlist or {}
    return SfuiDB.dungeonjournal
end

function sfui.dungeonjournal.IsWishlisted(itemID)
    if not itemID then return false end
    local id = tonumber(itemID)
    if not id then return false end
    local db = DJ_DB()
    return db.wishlist and db.wishlist[id] == true
end

function sfui.dungeonjournal.ToggleWishlist(itemID)
    if not itemID then return false end
    local id = tonumber(itemID)
    if not id then return false end
    local db = DJ_DB()
    db.wishlist = db.wishlist or {}
    local newState = not db.wishlist[id]
    if newState then
        db.wishlist[id] = true
    else
        db.wishlist[id] = nil
    end
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_DJ_WISHLIST_UPDATED", id, newState)
    end
    if sfui.print then
        local _, link = common.get_item_info(id)
        local name = link or ("Item #" .. id)
        if newState then
            sfui.print("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:14:14:0:0|t |cffcc44ffWishlist Added:|r " .. name)
        else
            sfui.print("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:14:14:0:0|t |cff888888Wishlist Removed:|r " .. name)
        end
    end
    return newState
end

function sfui.dungeonjournal.GetWishlist()
    local db = DJ_DB()
    return db.wishlist or {}
end

-- ─── Data access ─────────────────────────────────────────────────────────────
local function GetDB()
    return sfui.dj_camelot
        or (sfui.data and sfui.data.dj_camelot)
        or {}
end

local function GetList()
    local db = GetDB()
    if selectedTab == "raids" then
        return db.raids or {}
    end
    return db.dungeons or {}
end

local function FindDungeon(id)
    local db = GetDB()
    for _, d in ipairs(db.dungeons or {}) do
        if d.id == id then return d, "dungeons" end
    end
    for _, r in ipairs(db.raids or {}) do
        if r.id == id then return r, "raids" end
    end
    return nil, nil
end

-- ─── Item loading helpers ─────────────────────────────────────────────────────
-- Use the project's compat wrapper — never call _G.GetItemInfo directly.
local function GetItemInfo(itemID)
    return common.get_item_info(itemID)
end

local function GetItemInstantInfo(itemID)
    return common.get_item_instant_info(itemID)
end

local function RequestItemLoad(itemID)
    if common and common.request_item_load then
        common.request_item_load(itemID)
    elseif _G.C_Item and _G.C_Item.RequestLoadItemDataByID then
        pcall(_G.C_Item.RequestLoadItemDataByID, itemID)
    end
end

local function GetItemQuality(itemID)
    return common.get_item_quality(itemID) or 3
end

-- ─── Forwarded submodule functions (set by dj_sidebar, dj_bosses, dj_quests) ─
local RefreshSidebar   = nil
local RefreshBossView  = nil
local RefreshQuestView = nil

function sfui.dungeonjournal._registerSidebar(fn)  RefreshSidebar  = fn  end
function sfui.dungeonjournal._registerBosses(fn)   RefreshBossView  = fn  end
function sfui.dungeonjournal._registerQuests(fn)   RefreshQuestView = fn  end

local function SetTabButtonTextColor(btn, color)
    if not btn or not color then return end
    local fs = btn.fs or (btn.GetFontString and btn:GetFontString())
    if fs and fs.SetTextColor then
        fs:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end
end

local function UpdateTabHighlights()
    if not frame then return end
    local pal    = theme.GetPalette()
    local accent = pal and pal.accentColor or { 1, 0.78, 0.2, 1 }
    local dim    = pal and pal.tabNormal   or { 0.6, 0.6, 0.6, 1 }

    if frame.dungeonTabBtn then
        local da = (selectedTab == "dungeons") and accent or dim
        SetTabButtonTextColor(frame.dungeonTabBtn, da)
    end
    if frame.raidTabBtn then
        local ra = (selectedTab == "raids") and accent or dim
        SetTabButtonTextColor(frame.raidTabBtn, ra)
    end
    if frame.bossesTab then
        local ba = (selectedMode == "bosses") and accent or dim
        SetTabButtonTextColor(frame.bossesTab, ba)
    end
    if frame.questsTab then
        local qa = (selectedMode == "quests") and accent or dim
        SetTabButtonTextColor(frame.questsTab, qa)
    end
end

-- ─── Mode switching ──────────────────────────────────────────────────────────
local function SetMode(mode)
    selectedMode = mode or "bosses"
    DJ_DB().lastMode = selectedMode

    if not frame then return end

    if bossPanel  then bossPanel:SetShown(selectedMode == "bosses")  end
    if questPanel then questPanel:SetShown(selectedMode == "quests") end

    UpdateTabHighlights()

    if selectedMode == "bosses" and RefreshBossView then
        RefreshBossView()
    elseif selectedMode == "quests" and RefreshQuestView then
        RefreshQuestView()
    end
end

local function SetTab(tab)
    selectedTab = tab or "dungeons"
    DJ_DB().lastTab = selectedTab

    -- Only reset selectedDungeonID if it does not belong to the newly selected tab
    local currentEntry = selectedDungeonID and FindDungeon(selectedDungeonID)
    local list = GetList()
    local isValidInTab = false
    if currentEntry then
        for _, entry in ipairs(list) do
            if entry.id == selectedDungeonID then
                isValidInTab = true
                break
            end
        end
    end
    if not isValidInTab then
        selectedDungeonID = (list and list[1] and list[1].id) or nil
        DJ_DB().lastDungeon = selectedDungeonID
    end

    UpdateTabHighlights()

    if RefreshSidebar then RefreshSidebar() end
    if selectedMode == "bosses" and RefreshBossView then
        RefreshBossView()
    elseif selectedMode == "quests" and RefreshQuestView then
        RefreshQuestView()
    end
end

local function GetCurrentInstanceDungeon()
    if not IsInInstance then return nil end
    local inInstance, instanceType = IsInInstance()
    if not inInstance or (instanceType ~= "party" and instanceType ~= "raid") then
        return nil
    end

    local instName = GetInstanceInfo()
    if not instName or instName == "" then return nil end

    if sfui.dj_camelot and sfui.dj_camelot.GetDungeonByName then
        return sfui.dj_camelot.GetDungeonByName(instName)
    end
    return nil
end
sfui.dungeonjournal.GetCurrentInstanceDungeon = GetCurrentInstanceDungeon

-- ─── Public SelectDungeon & Navigation ───────────────────────────────────────
function sfui.dungeonjournal.SelectDungeon(dungeonID, mode)
    local entry, tab = FindDungeon(dungeonID)
    if tab and tab ~= selectedTab then
        selectedTab = tab
        DJ_DB().lastTab = tab
    end

    if mode and (mode == "bosses" or mode == "quests") then
        selectedMode = mode
        DJ_DB().lastMode = mode
    end

    selectedDungeonID   = dungeonID
    DJ_DB().lastDungeon = dungeonID
    DJ_DB().lastBoss    = 1
    DJ_DB().lastQuest   = 1

    if not frame then sfui.dungeonjournal.CreateFrame() end
    if not frame:IsShown() then frame:Show() end

    UpdateTabHighlights()
    if bossPanel  then bossPanel:SetShown(selectedMode == "bosses")  end
    if questPanel then questPanel:SetShown(selectedMode == "quests") end

    if RefreshSidebar then RefreshSidebar() end
    if selectedMode == "bosses" and RefreshBossView then
        RefreshBossView()
    elseif selectedMode == "quests" and RefreshQuestView then
        RefreshQuestView()
    end
end

function sfui.dungeonjournal.OpenToDungeon(dungeonID, mode)
    sfui.dungeonjournal.SelectDungeon(dungeonID, mode)
end

function sfui.dungeonjournal.OpenToQuest(questID)
    local qData = sfui.dj_camelot and sfui.dj_camelot.GetQuestDungeon and sfui.dj_camelot.GetQuestDungeon(questID)
    if qData and qData.dungeon then
        sfui.dungeonjournal.SelectDungeon(qData.dungeon.id, "quests")
    end
end

function sfui.dungeonjournal.GetSelectedDungeonID()
    return selectedDungeonID
end

function sfui.dungeonjournal.GetSelectedMode()
    return selectedMode
end

sfui.dungeonjournal.SetMode = SetMode

function sfui.dungeonjournal.SelectQuest(dungeonID, questID)
    if not dungeonID and questID then
        local dj = sfui.dj_camelot or (sfui.data and sfui.data.dj_camelot)
        if dj and dj.GetQuestDungeon then
            local qData = dj.GetQuestDungeon(questID)
            if qData and qData.dungeon then
                dungeonID = qData.dungeon.id
            end
        end
    end

    if not dungeonID and not questID then return false end

    if dungeonID then
        sfui.dungeonjournal.SelectDungeon(dungeonID, "quests")
    else
        if not frame then sfui.dungeonjournal.CreateFrame() end
        if not frame:IsShown() then frame:Show() end
        SetMode("quests")
    end

    if sfui.dungeonjournal.FocusQuest and questID then
        sfui.dungeonjournal.FocusQuest(questID)
    end
    return true
end

function sfui.dungeonjournal.GetSelectedTab()
    return selectedTab
end

local itemHelpers = {
    GetItemInfo        = GetItemInfo,
    GetItemInstantInfo = GetItemInstantInfo,
    RequestItemLoad    = RequestItemLoad,
    GetItemQuality     = GetItemQuality,
    FindDungeon        = FindDungeon,
    GetList            = GetList,
}

function sfui.dungeonjournal.GetItemHelpers()
    return itemHelpers
end

-- ─── Frame Creation ──────────────────────────────────────────────────────────
function sfui.dungeonjournal.CreateFrame()
    if frame then return frame end

    local saved = DJ_DB()
    selectedDungeonID = saved.lastDungeon or nil
    selectedMode      = saved.lastMode    or "bosses"
    selectedTab       = saved.lastTab     or "dungeons"

    -- ── Main window ───────────────────────────────────────────────────────────
    frame = CreateFrame("Frame", "SfuiDungeonJournalFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)

    if _G.UISpecialFrames then
        table.insert(_G.UISpecialFrames, "SfuiDungeonJournalFrame")
    end

    frame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.05, 0.05, 0.07, 0.97)
    frame:SetBackdropBorderColor(0.12, 0.12, 0.14, 1)

    -- ── Header bar ────────────────────────────────────────────────────────────
    local headerBar = CreateFrame("Frame", nil, frame)
    frame.headerBar = headerBar
    headerBar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0,  0)
    headerBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0,  0)
    headerBar:SetHeight(HEADER_H)
    headerBar:EnableMouse(false)

    theme.ApplyHeaderStyle(headerBar, "dungeon journal")

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.closeBtn = closeBtn
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
    closeBtn:SetSize(28, 28)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    theme.ApplyCloseButtonStyle(closeBtn)

    -- ── Map Pin Options Button & Dropdown Menu ────────────────────────────────
    local mapOptBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    frame.mapOptBtn = mapOptBtn
    mapOptBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    mapOptBtn:SetSize(22, 22)
    mapOptBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    mapOptBtn:SetBackdropColor(0.08, 0.08, 0.10, 0.9)
    mapOptBtn:SetBackdropBorderColor(0.2, 0.2, 0.24, 1)

    local mapIco = mapOptBtn:CreateTexture(nil, "ARTWORK")
    mapIco:SetSize(14, 14)
    mapIco:SetPoint("CENTER")
    mapIco:SetTexture("Interface\\Icons\\INV_Misc_Map02")
    mapIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local mapHi = mapOptBtn:CreateTexture(nil, "HIGHLIGHT")
    mapHi:SetAllPoints()
    mapHi:SetColorTexture(1, 1, 1, 0.2)

    mapOptBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine("Map Pin Options", 1, 0.82, 0)
        GameTooltip:AddLine("Configure dungeon entrance and quest icons on the World Map.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff00ff00<click to toggle pin options>|r", 0, 1, 0)
        GameTooltip:Show()
    end)
    mapOptBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ── Navigation: Set Waypoint Button ───────────────────────────────────────
    local navWpBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    frame.navWpBtn = navWpBtn
    navWpBtn:SetPoint("RIGHT", mapOptBtn, "LEFT", -4, 0)
    navWpBtn:SetSize(22, 22)
    navWpBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    navWpBtn:SetBackdropColor(0.08, 0.08, 0.10, 0.9)
    navWpBtn:SetBackdropBorderColor(0.2, 0.2, 0.24, 1)

    local navWpIco = navWpBtn:CreateTexture(nil, "ARTWORK")
    navWpIco:SetSize(14, 14)
    navWpIco:SetPoint("CENTER")
    navWpIco:SetTexture("Interface\\Minimap\\TRACKING\\FlightMaster")
    navWpIco:SetTexCoord(0.1, 0.9, 0.1, 0.9)

    local navWpHi = navWpBtn:CreateTexture(nil, "HIGHLIGHT")
    navWpHi:SetAllPoints()
    navWpHi:SetColorTexture(1, 1, 1, 0.2)

    navWpBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine("Set Waypoint", 1, 0.82, 0)
        GameTooltip:AddLine("Set an in-game navigation waypoint and supertrack the entrance to this dungeon.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff00ff00<click to set navigation waypoint>|r", 0, 1, 0)
        GameTooltip:Show()
    end)
    navWpBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    navWpBtn:SetScript("OnClick", function()
        local dungeon = FindDungeon(selectedDungeonID)
        if not dungeon or not dungeon.entrance or not dungeon.entrance.mapID or not dungeon.entrance.x or not dungeon.entrance.y then
            if common and common.print then common.print("No waypoint coordinates found for this dungeon.") end
            return
        end
        if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
            pcall(function()
                C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(dungeon.entrance.mapID, dungeon.entrance.x, dungeon.entrance.y))
            end)
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
            end
            if common and common.print then
                common.print("Waypoint set for " .. (dungeon.name or "dungeon entrance"))
            end
        end
    end)

    -- ── Navigation: Show on World Map Button ──────────────────────────────────
    local showMapBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    frame.showMapBtn = showMapBtn
    showMapBtn:SetPoint("RIGHT", navWpBtn, "LEFT", -4, 0)
    showMapBtn:SetSize(22, 22)
    showMapBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    showMapBtn:SetBackdropColor(0.08, 0.08, 0.10, 0.9)
    showMapBtn:SetBackdropBorderColor(0.2, 0.2, 0.24, 1)

    local showMapIco = showMapBtn:CreateTexture(nil, "ARTWORK")
    showMapIco:SetSize(14, 14)
    showMapIco:SetPoint("CENTER")
    showMapIco:SetTexture("Interface\\Icons\\INV_Misc_Map08")
    showMapIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local showMapHi = showMapBtn:CreateTexture(nil, "HIGHLIGHT")
    showMapHi:SetAllPoints()
    showMapHi:SetColorTexture(1, 1, 1, 0.2)

    showMapBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine("Show on World Map", 1, 0.82, 0)
        GameTooltip:AddLine("Open the World Map centered on this dungeon's entrance pin and zone.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff00ff00<click to view map>|r", 0, 1, 0)
        GameTooltip:Show()
    end)
    showMapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    showMapBtn:SetScript("OnClick", function()
        if InCombatLockdown and InCombatLockdown() then return end
        local dungeon = FindDungeon(selectedDungeonID)
        local mapID = dungeon and dungeon.entrance and dungeon.entrance.mapID
        if not mapID then
            if common and common.print then common.print("No map zone registered for this dungeon.") end
            return
        end
        if not WorldMapFrame:IsShown() then
            ShowUIPanel(WorldMapFrame)
        end
        if WorldMapFrame.SetMapID then
            WorldMapFrame:SetMapID(mapID)
        end
        if sfui.dungeonjournal and sfui.dungeonjournal.HighlightEntrancePin then
            sfui.dungeonjournal.HighlightEntrancePin(dungeon.id)
        end
    end)

    local mapMenu = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.mapMenu = mapMenu
    mapMenu:SetFrameStrata("DIALOG")
    mapMenu:SetFrameLevel(frame:GetFrameLevel() + 20)
    mapMenu:SetSize(230, 130)
    mapMenu:SetPoint("TOPRIGHT", mapOptBtn, "BOTTOMRIGHT", 2, -4)
    mapMenu:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    mapMenu:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
    mapMenu:SetBackdropBorderColor(0.24, 0.24, 0.28, 1)
    mapMenu:Hide()

    local menuDismiss = CreateFrame("Button", nil, UIParent)
    menuDismiss:SetFrameStrata("DIALOG")
    menuDismiss:SetFrameLevel(mapMenu:GetFrameLevel() - 1)
    menuDismiss:SetAllPoints()
    menuDismiss:Hide()
    menuDismiss:SetScript("OnClick", function()
        mapMenu:Hide()
        menuDismiss:Hide()
    end)
    mapMenu:SetScript("OnHide", function()
        menuDismiss:Hide()
    end)

    local mTitle = mapMenu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mTitle:SetPoint("TOPLEFT", mapMenu, "TOPLEFT", 10, -8)
    mTitle:SetText("world map pin options")
    mTitle:SetTextColor(1, 0.82, 0, 1)

    local function MakeMenuCheckbox(label, key, tipText, yOffset)
        local row = CreateFrame("Button", nil, mapMenu)
        row:SetSize(210, 22)
        row:SetPoint("TOPLEFT", mapMenu, "TOPLEFT", 10, yOffset)

        local check = row:CreateTexture(nil, "ARTWORK")
        check:SetSize(14, 14)
        check:SetPoint("LEFT", row, "LEFT", 0, 0)
        check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")

        local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", check, "RIGHT", 6, 0)
        text:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        text:SetJustifyH("LEFT")
        text:SetText(label)

        local hi = row:CreateTexture(nil, "HIGHLIGHT")
        hi:SetAllPoints()
        hi:SetColorTexture(1, 1, 1, 0.08)

        local function RefreshState()
            local enabled = sfui.dungeonjournal.GetOption(key)
            if enabled then
                check:Show()
                text:SetTextColor(0.95, 0.95, 0.95, 1)
            else
                check:Hide()
                text:SetTextColor(0.5, 0.5, 0.5, 1)
            end
        end
        row.RefreshState = RefreshState

        row:SetScript("OnClick", function()
            local cur = sfui.dungeonjournal.GetOption(key)
            sfui.dungeonjournal.SetOption(key, not cur)
            RefreshState()
        end)

        row:SetScript("OnEnter", function(self)
            if tipText then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(label, 1, 0.82, 0)
                GameTooltip:AddLine(tipText, 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        return row
    end

    local rowEnt = MakeMenuCheckbox("Dungeon Entrances", "showEntrancePins", "Show dungeon and raid entrance icons on the World Map.", -28)
    local rowQ   = MakeMenuCheckbox("Dungeon Quests", "showQuestPins", "Show quest pickup icons on the World Map.", -50)
    local rowLvl = MakeMenuCheckbox("Filter Quests by Level", "questPinsRequireLevel", "When enabled (default), quest icons only appear if your character meets the level requirement. Uncheck (opt out) to show all quest icons on the map.", -72)

    local btnSettings = CreateFrame("Button", nil, mapMenu, "BackdropTemplate")
    btnSettings:SetSize(210, 20)
    btnSettings:SetPoint("TOPLEFT", mapMenu, "TOPLEFT", 10, -96)
    btnSettings:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    btnSettings:SetBackdropColor(0.12, 0.12, 0.15, 0.9)
    btnSettings:SetBackdropBorderColor(0.24, 0.24, 0.28, 1)
    local sText = btnSettings:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sText:SetPoint("CENTER")
    sText:SetText("Open SFUI Options...")
    sText:SetTextColor(0.8, 0.8, 0.8, 1)
    local sHi = btnSettings:CreateTexture(nil, "HIGHLIGHT")
    sHi:SetAllPoints()
    sHi:SetColorTexture(1, 1, 1, 0.15)
    btnSettings:SetScript("OnClick", function()
        mapMenu:Hide()
        menuDismiss:Hide()
        if sfui.select_options_tab then
            sfui.select_options_tab("objectives")
        elseif sfui.open_options_panel then
            sfui.open_options_panel()
        end
    end)

    mapOptBtn:SetScript("OnClick", function()
        if mapMenu:IsShown() then
            mapMenu:Hide()
            menuDismiss:Hide()
        else
            rowEnt:RefreshState()
            rowQ:RefreshState()
            rowLvl:RefreshState()
            mapMenu:Show()
            menuDismiss:Show()
        end
    end)

    -- ── Dungeon / Raids top-level tabs (left group) ───────────────────────────
    local function MakeTopTab(text, anchor, anchorRef)
        local btn = CreateFrame("Button", nil, frame, "BackdropTemplate")
        btn:SetSize(90, TAB_H)
        if anchorRef then
            btn:SetPoint("LEFT", anchorRef, "RIGHT", 4, 0)
        else
            btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -(HEADER_H + 4))
        end
        btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        btn:SetBackdropColor(0.08, 0.08, 0.10, 0.9)
        btn:SetBackdropBorderColor(0.18, 0.18, 0.20, 1)
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("CENTER")
        fs:SetText(text)
        fs:SetTextColor(0.6, 0.6, 0.6, 1)
        btn.fs = fs
        if btn.SetFontString then btn:SetFontString(fs) end
        return btn
    end

    frame.dungeonTabBtn = MakeTopTab("dungeons", "TOPLEFT")
    frame.raidTabBtn    = MakeTopTab("raids", "LEFT", frame.dungeonTabBtn)

    frame.dungeonTabBtn:SetScript("OnClick", function() SetTab("dungeons") end)
    frame.raidTabBtn:SetScript("OnClick",    function() SetTab("raids")    end)

    -- ── Boss / Quest mode tabs (right group, top aligned with dungeon tabs) ───
    local function MakeModeTab(text, anchorRef, width)
        local btn = CreateFrame("Button", nil, frame, "BackdropTemplate")
        btn:SetSize(width or 100, TAB_H)
        if anchorRef then
            btn:SetPoint("LEFT", anchorRef, "RIGHT", 4, 0)
        else
            btn:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDEBAR_W + 16, -(HEADER_H + 4))
        end
        btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        btn:SetBackdropColor(0.08, 0.08, 0.10, 0.9)
        btn:SetBackdropBorderColor(0.18, 0.18, 0.20, 1)
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("CENTER")
        fs:SetText(text)
        fs:SetTextColor(0.6, 0.6, 0.6, 1)
        btn.fs = fs
        if btn.SetFontString then btn:SetFontString(fs) end
        return btn
    end

    frame.bossesTab = MakeModeTab("bosses & loot", nil, 106)
    frame.questsTab = MakeModeTab("quests", frame.bossesTab, 80)

    frame.bossesTab:SetScript("OnClick", function() SetMode("bosses") end)
    frame.questsTab:SetScript("OnClick", function() SetMode("quests") end)

    -- ── Sidebar (dungeon list) ─────────────────────────────────────────────────
    local sidebarY = -(HEADER_H + TAB_H + 8)
    sidebarFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.sidebarFrame = sidebarFrame
    sidebarFrame:SetPoint("TOPLEFT",    frame, "TOPLEFT",    8,  sidebarY)
    sidebarFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8,  8)
    sidebarFrame:SetWidth(SIDEBAR_W)
    theme.ApplyContainerStyle(sidebarFrame)

    -- ── Content area ──────────────────────────────────────────────────────────
    local contentArea = CreateFrame("Frame", nil, frame)
    frame.contentArea = contentArea
    contentArea:SetPoint("TOPLEFT",     frame, "TOPLEFT",     SIDEBAR_W + 16, sidebarY)
    contentArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)

    -- ── Boss panel container ───────────────────────────────────────────────────
    bossPanel = CreateFrame("Frame", nil, contentArea)
    frame.bossPanel = bossPanel
    bossPanel:SetAllPoints(contentArea)
    bossPanel:Show()

    -- ── Quest panel container ──────────────────────────────────────────────────
    questPanel = CreateFrame("Frame", nil, contentArea)
    frame.questPanel = questPanel
    questPanel:SetAllPoints(contentArea)
    questPanel:Hide()

    -- ── Theme registration ─────────────────────────────────────────────────────
    theme.ApplyWindowStyle(frame)
    theme.RegisterWindow(frame, function(f, pal)
        if not pal then pal = theme.GetPalette() end
        if f.headerBar then
            theme.ApplyHeaderStyle(f.headerBar, "dungeon journal")
        end
        if f.sidebarFrame then
            theme.ApplyContainerStyle(f.sidebarFrame)
        end
        UpdateTabHighlights()
    end)

    frame:Hide()
    sfui.dungeonjournal.frame = frame

    -- Signal submodules to bind to these panels
    local payload = {
        frame        = frame,
        sidebarFrame = sidebarFrame,
        bossPanel    = bossPanel,
        questPanel   = questPanel,
    }

    if sfui.dungeonjournal._initSidebar then sfui.dungeonjournal._initSidebar(payload) end
    if sfui.dungeonjournal._initBosses  then sfui.dungeonjournal._initBosses(payload)  end
    if sfui.dungeonjournal._initQuests  then sfui.dungeonjournal._initQuests(payload)  end

    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_DJ_FRAME_CREATED", payload)
    end

    return frame
end

-- ─── Public API ───────────────────────────────────────────────────────────────
function sfui.dungeonjournal.Toggle()
    if not frame then sfui.dungeonjournal.CreateFrame() end
    if not frame then return end

    -- Self-heal in case submodules were not initialized
    if not RefreshSidebar then
        local payload = {
            frame        = frame,
            sidebarFrame = frame.sidebarFrame or sidebarFrame,
            bossPanel    = frame.bossPanel or bossPanel,
            questPanel   = frame.questPanel or questPanel,
        }
        if sfui.dungeonjournal._initSidebar then sfui.dungeonjournal._initSidebar(payload) end
        if sfui.dungeonjournal._initBosses  then sfui.dungeonjournal._initBosses(payload)  end
        if sfui.dungeonjournal._initQuests  then sfui.dungeonjournal._initQuests(payload)  end
    end

    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()

        -- In-Instance Auto-Detection
        if DJ_DB().autoDetectInstance ~= false then
            local activeDungeon = GetCurrentInstanceDungeon()
            if activeDungeon then
                selectedDungeonID = activeDungeon.id
                selectedTab = (activeDungeon.category == "camelot_raid" or activeDungeon.category == "classic_raid") and "raids" or "dungeons"
                DJ_DB().lastDungeon = selectedDungeonID
                DJ_DB().lastTab     = selectedTab
            end
        end

        local list = GetList()
        local currentEntry = selectedDungeonID and FindDungeon(selectedDungeonID)
        local isValidInTab = false
        if currentEntry then
            for _, entry in ipairs(list) do
                if entry.id == selectedDungeonID then
                    isValidInTab = true
                    break
                end
            end
        end
        if not isValidInTab then
            selectedDungeonID = (list and list[1] and list[1].id) or nil
            DJ_DB().lastDungeon = selectedDungeonID
        end

        UpdateTabHighlights()
        if bossPanel  then bossPanel:SetShown(selectedMode == "bosses")  end
        if questPanel then questPanel:SetShown(selectedMode == "quests") end

        if RefreshSidebar then RefreshSidebar() end
        if selectedMode == "bosses" and RefreshBossView then
            RefreshBossView()
        elseif selectedMode == "quests" and RefreshQuestView then
            RefreshQuestView()
        end
    end
end

function sfui.dungeonjournal.Open()
    if not frame then sfui.dungeonjournal.CreateFrame() end
    if not frame then return end

    -- Self-heal in case submodules were not initialized
    if not RefreshSidebar then
        local payload = {
            frame        = frame,
            sidebarFrame = frame.sidebarFrame or sidebarFrame,
            bossPanel    = frame.bossPanel or bossPanel,
            questPanel   = frame.questPanel or questPanel,
        }
        if sfui.dungeonjournal._initSidebar then sfui.dungeonjournal._initSidebar(payload) end
        if sfui.dungeonjournal._initBosses  then sfui.dungeonjournal._initBosses(payload)  end
        if sfui.dungeonjournal._initQuests  then sfui.dungeonjournal._initQuests(payload)  end
    end

    if not frame:IsShown() then
        frame:Show()

        -- In-Instance Auto-Detection
        if DJ_DB().autoDetectInstance ~= false then
            local activeDungeon = GetCurrentInstanceDungeon()
            if activeDungeon then
                selectedDungeonID = activeDungeon.id
                selectedTab = (activeDungeon.category == "camelot_raid" or activeDungeon.category == "classic_raid") and "raids" or "dungeons"
                DJ_DB().lastDungeon = selectedDungeonID
                DJ_DB().lastTab     = selectedTab
            end
        end

        local list = GetList()
        local currentEntry = selectedDungeonID and FindDungeon(selectedDungeonID)
        local isValidInTab = false
        if currentEntry then
            for _, entry in ipairs(list) do
                if entry.id == selectedDungeonID then
                    isValidInTab = true
                    break
                end
            end
        end
        if not isValidInTab then
            selectedDungeonID = (list and list[1] and list[1].id) or nil
            DJ_DB().lastDungeon = selectedDungeonID
        end

        UpdateTabHighlights()
        if bossPanel  then bossPanel:SetShown(selectedMode == "bosses")  end
        if questPanel then questPanel:SetShown(selectedMode == "quests") end

        if RefreshSidebar then RefreshSidebar() end
        if selectedMode == "bosses" and RefreshBossView then
            RefreshBossView()
        elseif selectedMode == "quests" and RefreshQuestView then
            RefreshQuestView()
        end
    end
end

function sfui.dungeonjournal.GetOption(key)
    local saved = DJ_DB()
    if key == "showEntrancePins" then
        return saved.showEntrancePins ~= false
    elseif key == "showQuestPins" then
        return saved.showQuestPins ~= false
    elseif key == "questPinsRequireLevel" then
        return saved.questPinsRequireLevel ~= false
    elseif key == "autoDetectInstance" then
        return saved.autoDetectInstance ~= false
    elseif key == "showItemTooltips" then
        return saved.showItemTooltips ~= false
    end
    return saved[key]
end

function sfui.dungeonjournal.SetOption(key, val)
    local saved = DJ_DB()
    saved[key] = val
    if sfui.dungeonjournal.UpdatePins then
        sfui.dungeonjournal.UpdatePins()
    end
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_DJ_SETTING_CHANGED", key, val)
    end
end

function sfui.dungeonjournal.GetFrame()
    return frame
end

function sfui.dungeonjournal.Close()
    if frame and frame:IsShown() then
        frame:Hide()
    end
end

function sfui.dungeonjournal.ClearCache()
    -- Forwarded to submodules via message
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_DJ_CLEAR_CACHE")
    end
end

function sfui.dungeonjournal.Rebuild()
    if RefreshSidebar  then RefreshSidebar()  end
    if selectedMode == "bosses" and RefreshBossView then
        RefreshBossView()
    elseif selectedMode == "quests" and RefreshQuestView then
        RefreshQuestView()
    end
end

-- ─── Backward compatibility aliases ──────────────────────────────────────────
sfui.lootviewer_camelot = sfui.dungeonjournal
sfui.ToggleLootViewer   = sfui.dungeonjournal.Toggle

-- ─── Module telemetry & registration ──────────────────────────────────────────
local _djDebug = {}
function sfui.dungeonjournal_debug_info()
    _djDebug.isCreated       = (frame ~= nil)
    _djDebug.isShown         = (frame ~= nil and frame:IsShown() == true)
    _djDebug.selectedMode    = selectedMode
    _djDebug.selectedTab     = selectedTab
    _djDebug.selectedDungeon = selectedDungeonID
    return _djDebug
end
sfui.dungeonjournal.GetDebugInfo = sfui.dungeonjournal_debug_info

if sfui.RegisterModule then
    sfui.dungeonjournal.OnSpecChanged = function(self)
        if self.Rebuild then self.Rebuild() end
    end
    sfui.RegisterModule("dungeonjournal", sfui.dungeonjournal)
end

-- ─── Live Theme Synchronization ──────────────────────────────────────────────
if sfui.events and sfui.events.RegisterMessage then
    sfui.events.RegisterMessage("SFUI_THEME_CHANGED", function()
        if frame and frame:IsShown() then
            UpdateTabHighlights()
            if sfui.theme and sfui.theme.ApplyWindowStyle then
                sfui.theme.ApplyWindowStyle(frame)
            end
            if RefreshSidebar then RefreshSidebar() end
            if selectedMode == "bosses" and RefreshBossView then
                RefreshBossView()
            elseif selectedMode == "quests" and RefreshQuestView then
                RefreshQuestView()
            end
        end
    end)
end
