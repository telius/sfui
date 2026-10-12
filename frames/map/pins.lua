local addonName, addon = ...
sfui = sfui or {}
sfui.pins = sfui.pins or {}
sfui.map = sfui.map or {}
sfui.map.pins = sfui.pins
local pins = sfui.pins

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/map/pins.lua
--  Unified WorldMap Pin Placement Engine
--
--  Centralized coordinator for interactive canvas pins across sfui modules:
--    - Single pooled allocator of pin button frames (zero frame bloat)
--    - Unified 0.5s pan/zoom sync ticker and OnShow/OnHide map hooks
--    - Automated normalized-to-canvas coordinate projection
--    - Built-in proximity clustering engine and coordinate group helpers
--    - Centralized WorldMap tracking dropdown menu manager
--    - Shared quest completion, active log scanning, and bag count caching
--    - Pin scale highlight and pulse animations
--    - Universal shift-left-click waypoint creation and supertracking
-- ══════════════════════════════════════════════════════════════════════════════

local _G                  = _G
local CreateFrame         = _G.CreateFrame
local InCombatLockdown    = _G.InCombatLockdown
local UnitLevel           = _G.UnitLevel
local IsShiftKeyDown      = _G.IsShiftKeyDown
local C_Timer             = _G.C_Timer
local C_Map               = _G.C_Map
local UiMapPoint          = _G.UiMapPoint
local C_SuperTrack        = _G.C_SuperTrack
local GameTooltip         = _G.GameTooltip
local pcall               = _G.pcall
local type                = _G.type
local ipairs              = _G.ipairs
local pairs               = _G.pairs
local table_insert        = _G.table.insert
local table_sort          = _G.table.sort
local math_abs            = math.abs
local tostring            = tostring
local wipe                = _G.wipe or table.wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

local common              = sfui.common

-- ─── Data Registries & Pools ──────────────────────────────────────────────────
local providers           = {}     -- name -> provider table
local providerOrder       = {}     -- sorted list of provider names
local staticPinBatches    = {}     -- name -> list of static pin tables
local trackingCategories  = {}     -- list of { title = string, options = { { text, get, set } } }

local pinPool             = {}     -- reusable Button frames
local activePins          = {}     -- currently visible Button frames on canvas

local isPinsDirty         = true
local updateTicker        = nil

local lastMapID           = nil
local lastCanvasW         = nil
local lastCanvasH         = nil
local lastPlayerLevel     = nil

-- ─── Centralized Quest & Bag Status Cache ─────────────────────────────────────
local activeQuestCache    = {}
local isQuestCacheValid   = false

local function InvalidateQuestCache()
    isQuestCacheValid = false
    wipe(activeQuestCache)
end
pins.InvalidateQuestCache = InvalidateQuestCache

local function RebuildActiveQuestCache()
    if isQuestCacheValid then return end
    wipe(activeQuestCache)
    local numEntries = 0
    if _G.C_QuestLog and _G.C_QuestLog.GetNumQuestLogEntries then
        local ok, n = pcall(_G.C_QuestLog.GetNumQuestLogEntries)
        if ok and n then numEntries = n end
    elseif _G.GetNumQuestLogEntries then
        local ok, n = pcall(_G.GetNumQuestLogEntries)
        if ok and n then numEntries = n end
    end
    for i = 1, numEntries do
        local qID = nil
        if _G.C_QuestLog and _G.C_QuestLog.GetInfo then
            local info = _G.C_QuestLog.GetInfo(i)
            if info and info.questID and info.questID > 0 then qID = info.questID end
        end
        if not qID and _G.GetQuestLogTitle then
            local _, _, _, isHeader, _, _, _, id = _G.GetQuestLogTitle(i)
            if not isHeader and id and id > 0 then qID = id end
        end
        if qID then
            activeQuestCache[qID] = true
        end
    end
    isQuestCacheValid = true
end

function pins.IsQuestCompleted(questID)
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

function pins.IsQuestActive(questID)
    if not questID then return false end
    if not isQuestCacheValid then
        RebuildActiveQuestCache()
    end
    return activeQuestCache[questID] == true
end

function pins.GetItemCountInBags(itemID)
    if not itemID then return 0 end
    if common and common.get_item_count then
        local ok, count = pcall(common.get_item_count, itemID)
        if ok and count then return count end
    end
    if _G.GetItemCount then
        local ok, count = pcall(_G.GetItemCount, itemID, false)
        if ok and count then return count end
    end
    return 0
end

-- ─── Proximity Coordinate Grouping Helper ─────────────────────────────────────
--- Finds or inserts a coordinate bucket into groups array for proximity clustering.
--- @param groups table array of group buckets
--- @param x number normalized x coordinate
--- @param y number normalized y coordinate
--- @param threshold number|nil coordinate distance threshold (default 0.008)
--- @param mapID number|nil optional map ID
--- @return table group bucket
function pins.FindOrCreateGroup(groups, x, y, threshold, mapID)
    threshold = threshold or 0.008
    for _, g in ipairs(groups) do
        if math_abs(g.x - x) < threshold and math_abs(g.y - y) < threshold then
            return g
        end
    end
    local targetGroup = { mapID = mapID, x = x, y = y, items = {} }
    table_insert(groups, targetGroup)
    return targetGroup
end

-- ─── Centralized WorldMap Tracking Dropdown Menu Manager ──────────────────────
--- Registers a category section in the WorldMap tracking dropdown menu.
--- @param title string section header title
--- @param options table array of { text = string, get = function, set = function }
function pins.RegisterTrackingCategory(title, options)
    if not title or not options then return end
    table_insert(trackingCategories, { title = title, options = options })
end

local isTrackingMenuHooked = false
local function HookWorldMapTrackingMenu()
    if isTrackingMenuHooked then return end
    if _G.Menu and _G.Menu.ModifyMenu then
        isTrackingMenuHooked = true
        pcall(_G.Menu.ModifyMenu, "MENU_WORLD_MAP_TRACKING", function(owner, rootDescription)
            for _, cat in ipairs(trackingCategories) do
                rootDescription:CreateDivider()
                rootDescription:CreateTitle(cat.title)
                for _, opt in ipairs(cat.options) do
                    rootDescription:CreateCheckbox(opt.text, opt.get, function()
                        local cur = opt.get()
                        opt.set(not cur)
                    end)
                end
            end
        end)
    end
end

-- ─── Canvas & Map ID Resolution ───────────────────────────────────────────────
local function GetCanvas()
    if sfui.map and sfui.map.GetCanvas then
        return sfui.map.GetCanvas()
    end
    local wmf = _G.WorldMapFrame
    if not wmf then return nil end
    if type(wmf.GetCanvas) == "function" then
        local ok, canvas = pcall(wmf.GetCanvas, wmf)
        if ok and canvas then return canvas end
    end
    if wmf.ScrollContainer then
        return wmf.ScrollContainer.Child or wmf.ScrollContainer
    end
    return wmf
end

local function GetCurrentMapID()
    if sfui.map and sfui.map.GetCurrentMapID then
        return sfui.map.GetCurrentMapID()
    end
    local wmf = _G.WorldMapFrame
    if wmf and wmf.GetMapID then
        local ok, id = pcall(wmf.GetMapID, wmf)
        if ok and id then return id end
    end
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
        if ok and id then return id end
    end
    return nil
end

-- ─── Universal Shift-Click Waypoint Handler ───────────────────────────────────
local function SetWaypoint(mapID, x, y, label)
    if not mapID or not x or not y then return false end
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        pcall(function()
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
        end)
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
        end
        if label and common and common.print then
            common.print("waypoint set for " .. label)
        end
        return true
    end
    return false
end
pins.SetWaypoint = SetWaypoint

-- ─── Frame Pool Allocator ─────────────────────────────────────────────────────
local function AcquirePin(parent, defaultSize)
    defaultSize = defaultSize or 20
    for _, pin in ipairs(pinPool) do
        if not pin:IsShown() then
            pin:SetParent(parent)
            pin:SetSize(defaultSize, defaultSize)
            pin.baseSize = defaultSize
            pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            pin.icon:SetDesaturated(false)
            pin.icon:SetVertexColor(1, 1, 1, 1)
            pin:SetBackdropBorderColor(0, 0, 0, 1)
            pin.countText:SetText("")
            pin.countText:SetTextColor(1, 1, 1, 1)
            pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            return pin
        end
    end

    local pin = CreateFrame("Button", nil, parent, "BackdropTemplate")
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pin:SetSize(defaultSize, defaultSize)
    pin.baseSize = defaultSize
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
    pin.highlightTexture = hi

    -- Interactive Tooltip Script Handlers
    pin:SetScript("OnEnter", function(self)
        local pinData = self.pinData
        if not pinData then return end
        if pinData.OnEnter then
            pinData.OnEnter(self, GameTooltip, pinData)
        elseif pinData.title and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(pinData.title, 1, 0.82, 0)
            if pinData.description then
                GameTooltip:AddLine(pinData.description, 0.85, 0.85, 0.85, true)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff80c0ffshift-click: set map waypoint|r", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)

    pin:SetScript("OnLeave", function(self)
        local pinData = self.pinData
        if pinData and pinData.OnLeave then
            pinData.OnLeave(self, GameTooltip, pinData)
        elseif GameTooltip then
            GameTooltip:Hide()
        end
    end)

    pin:SetScript("OnClick", function(self, button)
        local pinData = self.pinData
        if not pinData then return end

        if IsShiftKeyDown() and button == "LeftButton" then
            local mapID = pinData.mapID or GetCurrentMapID()
            if SetWaypoint(mapID, pinData.x, pinData.y, pinData.title or pinData.label or "waypoint") then
                return
            end
        end

        if pinData.OnClick then
            pinData.OnClick(self, button, pinData)
        end
    end)

    pinPool[#pinPool + 1] = pin
    return pin
end

local function ReleasePins()
    for _, pin in ipairs(activePins) do
        pin:Hide()
        pin.pinData = nil
        pin.customID = nil
    end
    wipe(activePins)
end

-- ─── Proximity Clustering Engine ──────────────────────────────────────────────
--- Clusters pin objects sitting within threshold proximity (default 0.012).
--- Aggregates items into cluster.items with cluster.count = #items.
--- @param pinList table array of pin tables with {x, y, ...}
--- @param threshold number|nil optional proximity distance (default 0.012)
--- @return table clusteredPins
function pins.ClusterPins(pinList, threshold)
    if not pinList or #pinList == 0 then return {} end
    threshold = threshold or 0.012

    local clusters = {}
    for _, pin in ipairs(pinList) do
        local found = false
        for _, c in ipairs(clusters) do
            local dx = math_abs(c.x - pin.x)
            local dy = math_abs(c.y - pin.y)
            if dx <= threshold and dy <= threshold then
                c.count = c.count + 1
                table_insert(c.items, pin)
                found = true
                break
            end
        end

        if not found then
            local cluster = {
                id          = pin.id,
                mapID       = pin.mapID,
                x           = pin.x,
                y           = pin.y,
                icon        = pin.icon,
                size        = pin.size,
                borderColor = pin.borderColor,
                count       = 1,
                items       = { pin },
                data        = pin.data,
                provider    = pin.provider,
                OnClick     = pin.OnClick,
                OnEnter     = pin.OnEnter,
                OnLeave     = pin.OnLeave,
            }
            table_insert(clusters, cluster)
        end
    end
    return clusters
end

-- ─── Provider & Static Pin Registration APIs ──────────────────────────────────
local function SortProviders()
    wipe(providerOrder)
    for name in pairs(providers) do
        table_insert(providerOrder, name)
    end
    table_sort(providerOrder, function(a, b)
        local pa = providers[a].priority or 10
        local pb = providers[b].priority or 10
        if pa == pb then return a < b end
        return pa < pb
    end)
end

--- Registers a dynamic pin provider.
--- @param name string unique provider key
--- @param config table configuration with GetPins(mapID, playerLevel, playerFaction)
function pins.RegisterProvider(name, config)
    if not name or not config then return end
    config.name = name
    config.priority = config.priority or 10
    providers[name] = config
    SortProviders()
    isPinsDirty = true
end

--- Unregisters a pin provider.
--- @param name string provider key
function pins.UnregisterProvider(name)
    if providers[name] then
        providers[name] = nil
        SortProviders()
        isPinsDirty = true
    end
end

--- Posts a static batch of pins for a category (e.g. dungeon entrances).
--- @param name string category key
--- @param pinList table array of pin tables
function pins.SetPins(name, pinList)
    if not name then return end
    staticPinBatches[name] = pinList or {}
    isPinsDirty = true
end

--- Clears static pins for a category.
--- @param name string category key
function pins.ClearPins(name)
    if staticPinBatches[name] then
        staticPinBatches[name] = nil
        isPinsDirty = true
    end
end

-- ─── Pin Highlighting / Pulse API ─────────────────────────────────────────────
--- Scales up a pin for duration seconds to draw the player's eye when selected.
--- @param pinID any unique identifier matching pin.id, pin.customID, or pinData.dungeonID
--- @param duration number|nil duration in seconds (default 0.5)
--- @param targetSize number|nil enlarged size in pixels (default baseSize + 6)
function pins.HighlightPin(pinID, duration, targetSize)
    if not pinID then return false end
    duration = duration or 0.5
    for _, pin in ipairs(activePins) do
        local pd = pin.pinData
        if pin.customID == pinID or (pd and (pd.id == pinID or pd.dungeonID == pinID)) then
            local base = pin.baseSize or 20
            local enlarged = targetSize or (base + 6)
            pin:SetSize(enlarged, enlarged)
            C_Timer.After(duration, function()
                if pin and pin.SetSize then
                    pin:SetSize(base, base)
                end
            end)
            return true
        end
    end
    return false
end

--- Returns the count of currently visible pins, optionally filtered by provider/source.
--- @param providerName string|nil
--- @return number count
function pins.GetActiveCount(providerName)
    if not providerName then return #activePins end
    local count = 0
    for _, pin in ipairs(activePins) do
        if pin.pinData and (pin.pinData.provider == providerName or pin.pinData.source == providerName) then
            count = count + 1
        end
    end
    return count
end

-- ─── Pin Setup & Visual Application ───────────────────────────────────────────
local function SetupPin(pin, canvas, canvasW, canvasH, p)
    pin.pinData  = p
    pin.customID = p.id
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", canvas, "TOPLEFT", canvasW * p.x, -canvasH * p.y)

    if p.icon then
        pin.icon:SetTexture(p.icon)
    end

    if p.texCoord then
        local tc = p.texCoord
        pin.icon:SetTexCoord(tc[1] or 0, tc[2] or 1, tc[3] or 0, tc[4] or 1)
    else
        pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    if p.desaturated ~= nil then
        pin.icon:SetDesaturated(p.desaturated and true or false)
    else
        pin.icon:SetDesaturated(false)
    end

    if p.vertexColor then
        local vc = p.vertexColor
        pin.icon:SetVertexColor(vc[1] or 1, vc[2] or 1, vc[3] or 1, vc[4] or 1)
    else
        pin.icon:SetVertexColor(1, 1, 1, 1)
    end

    if p.borderColor then
        local bc = p.borderColor
        pin:SetBackdropBorderColor(bc[1] or 0, bc[2] or 0, bc[3] or 0, bc[4] or 1)
    else
        pin:SetBackdropBorderColor(0, 0, 0, 1)
    end

    if p.countText ~= nil then
        pin.countText:SetText(tostring(p.countText))
    elseif p.count and p.count > 1 then
        pin.countText:SetText(tostring(p.count))
    else
        pin.countText:SetText("")
    end

    if p.countColor then
        local cc = p.countColor
        pin.countText:SetTextColor(cc[1] or 1, cc[2] or 1, cc[3] or 1, cc[4] or 1)
    else
        pin.countText:SetTextColor(1, 1, 1, 1)
    end

    pin:Show()
    activePins[#activePins + 1] = pin
end

-- ─── Render Pass & Canvas Placement Loop ──────────────────────────────────────
local function RenderPins(force)
    local wmf = _G.WorldMapFrame
    if not wmf or not wmf:IsShown() then
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

    local playerLevel   = (UnitLevel and UnitLevel("player")) or 1
    local playerFaction = (sfui.common and sfui.common.get_player_faction and sfui.common.get_player_faction()) or "Alliance"

    if not force and not isPinsDirty
        and mapID == lastMapID
        and canvasW == lastCanvasW
        and canvasH == lastCanvasH
        and playerLevel == lastPlayerLevel then
        return
    end

    isPinsDirty     = false
    lastMapID       = mapID
    lastCanvasW     = canvasW
    lastCanvasH     = canvasH
    lastPlayerLevel = playerLevel

    ReleasePins()

    -- 1. Render Dynamic Providers in Priority Order
    for _, name in ipairs(providerOrder) do
        local prov = providers[name]
        local isEnabled = true
        if prov.enabled ~= nil then
            if type(prov.enabled) == "function" then
                isEnabled = prov.enabled()
            else
                isEnabled = prov.enabled and true or false
            end
        end

        if isEnabled and prov.GetPins then
            local pinList = prov.GetPins(mapID, playerLevel, playerFaction)
            if pinList and #pinList > 0 then
                for _, p in ipairs(pinList) do
                    p.provider = p.provider or name
                    local pin = AcquirePin(canvas, p.size or prov.defaultSize or 20)
                    SetupPin(pin, canvas, canvasW, canvasH, p)
                end
            end
        end
    end

    -- 2. Render Static Pin Batches
    for batchName, pinList in pairs(staticPinBatches) do
        if pinList and #pinList > 0 then
            for _, p in ipairs(pinList) do
                if p.mapID == mapID and p.x and p.y then
                    p.provider = p.provider or batchName
                    local pin = AcquirePin(canvas, p.size or 20)
                    SetupPin(pin, canvas, canvasW, canvasH, p)
                end
            end
        end
    end
end
pins.UpdatePins = RenderPins

--- Requests an asynchronous re-render pass on the canvas.
--- @param delay number|nil optional debounce delay in seconds (default 0.05)
function pins.RequestRefresh(delay)
    isPinsDirty = true
    delay = delay or 0.05
    if common and common.debounce then
        common.debounce("sfui_map_pins_refresh", delay, function()
            RenderPins(true)
        end)
    else
        C_Timer.After(delay, function()
            RenderPins(true)
        end)
    end
end

-- ─── Lifecycle & Map Ticker Integration ───────────────────────────────────────
local function StartTicker()
    if updateTicker then return end
    updateTicker = C_Timer.NewTicker(0.5, function()
        local wmf = _G.WorldMapFrame
        if wmf and wmf:IsShown() then
            RenderPins(false)
        else
            if updateTicker then
                updateTicker:Cancel()
                updateTicker = nil
            end
            ReleasePins()
        end
    end)
end

local function StopTicker()
    if updateTicker then
        updateTicker:Cancel()
        updateTicker = nil
    end
    ReleasePins()
end

local function InitPinEngine()
    HookWorldMapTrackingMenu()

    local wmf = _G.WorldMapFrame
    if wmf then
        wmf:HookScript("OnShow", function()
            StartTicker()
            RenderPins(true)
        end)
        wmf:HookScript("OnHide", function()
            StopTicker()
        end)
        if wmf:IsShown() then
            StartTicker()
            RenderPins(true)
        end
    end

    if sfui.events and sfui.events.RegisterEvent then
        local function OnStateChanged()
            pins.RequestRefresh(0.1)
        end

        local function OnQuestStateChanged()
            InvalidateQuestCache()
            pins.RequestRefresh(0.15)
        end

        sfui.events.RegisterEvent("ZONE_CHANGED", OnStateChanged)
        sfui.events.RegisterEvent("ZONE_CHANGED_NEW_AREA", OnStateChanged)
        sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", OnStateChanged)
        sfui.events.RegisterEvent("BAG_UPDATE_DELAYED", OnStateChanged)
        sfui.events.RegisterEvent("QUEST_LOG_UPDATE", OnQuestStateChanged)
        sfui.events.RegisterEvent("QUEST_ACCEPTED", OnQuestStateChanged)
        sfui.events.RegisterEvent("QUEST_REMOVED", OnQuestStateChanged)
        sfui.events.RegisterEvent("QUEST_TURNED_IN", OnQuestStateChanged)
        sfui.events.RegisterEvent("PLAYER_LEVEL_UP", OnQuestStateChanged)
        sfui.events.RegisterEvent("SKILL_LINES_CHANGED", OnStateChanged)
        sfui.events.RegisterEvent("CHAT_MSG_SKILL", OnStateChanged)
    end
end

if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("PLAYER_LOGIN", InitPinEngine)
end
