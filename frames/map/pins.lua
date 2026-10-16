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
local GameTooltip         = sfui.common.get_tooltip()
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

local pinPool             = {}     -- reusable WorldMap Button frames
local activePins          = {}     -- currently visible Button frames on canvas

local minimapPinPool      = {}     -- reusable Minimap Button frames
local activeMinimapPins   = {}     -- currently visible Button frames on minimap

local isPinsDirty         = true
local isMinimapPinsDirty  = true
local updateTicker        = nil

local lastMapID           = nil
local lastCanvasW         = nil
local lastCanvasH         = nil
local lastPlayerLevel     = nil

local lastMinimapPX       = nil
local lastMinimapPY       = nil
local lastMinimapFacing   = nil
local lastMinimapRadius   = nil
local lastMinimapMapID    = nil

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

-- ─── Centralized WorldMap & Minimap Tracking Dropdown Menu Manager ────────────
if sfui.db and sfui.db.RegisterDefaults then
    sfui.db.RegisterDefaults("map_pins", {
        minimapShowPins = true,
    })
end

local function GetMinimapShowPins()
    if sfui.db and sfui.db.Get then
        local val = sfui.db.Get("map_pins", "minimapShowPins")
        if val ~= nil then return val end
    end
    if SfuiDB and SfuiDB.minimapShowPins ~= nil then
        return SfuiDB.minimapShowPins
    end
    return true
end

local function SetMinimapShowPins(val)
    if sfui.db and sfui.db.Set then
        sfui.db.Set("map_pins", "minimapShowPins", val)
    end
    SfuiDB = SfuiDB or {}
    SfuiDB.minimapShowPins = val
    if not val then
        if pins.ReleaseMinimapPins then pins.ReleaseMinimapPins() end
    else
        if pins.RequestMinimapRefresh then pins.RequestMinimapRefresh(0) end
    end
end
pins.GetMinimapShowPins = GetMinimapShowPins
pins.SetMinimapShowPins = SetMinimapShowPins

--- Registers a category section in the WorldMap/Minimap tracking dropdown menu.
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
        local function PopulateTrackingMenu(owner, rootDescription)
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
        end
        pcall(_G.Menu.ModifyMenu, "MENU_WORLD_MAP_TRACKING", PopulateTrackingMenu)
        pcall(_G.Menu.ModifyMenu, "MENU_MINIMAP_TRACKING", PopulateTrackingMenu)
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
    if sfui.map and sfui.map.SetUserWaypoint then
        return sfui.map.SetUserWaypoint(mapID, x, y, label)
    end
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        pcall(function()
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
        end)
        if sfui.map and sfui.map.SetSuperTrackedUserWaypoint then
            sfui.map.SetSuperTrackedUserWaypoint(true)
        elseif C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
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
            if pin.SetRoundBorderColor then
                pin:SetRoundBorderColor(0, 0, 0, 1)
            elseif pin.SetBackdropBorderColor then
                pin:SetBackdropBorderColor(0, 0, 0, 1)
            end
            pin.countText:SetText("")
            pin.countText:SetTextColor(1, 1, 1, 1)
            pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            return pin
        end
    end

    local pin = CreateFrame("Button", nil, parent)
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pin:SetSize(defaultSize, defaultSize)
    pin.baseSize = defaultSize
    pin:SetFrameStrata("HIGH")

    local icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon = icon

    local hi = pin:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetColorTexture(1, 1, 1, 0.25)
    pin.highlightTexture = hi

    if sfui.common and sfui.common.apply_round_icon_style then
        sfui.common.apply_round_icon_style(pin, icon, 1)
    end

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
        else
            sfui.common.hide_tooltip()
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
    isMinimapPinsDirty = true
    pins.RequestRefresh(0.05)
end

--- Unregisters a pin provider.
--- @param name string provider key
function pins.UnregisterProvider(name)
    if providers[name] then
        providers[name] = nil
        SortProviders()
        isPinsDirty = true
        isMinimapPinsDirty = true
        pins.RequestRefresh(0.05)
    end
end

--- Posts a static batch of pins for a category (e.g. dungeon entrances).
--- @param name string category key
--- @param pinList table array of pin tables
function pins.SetPins(name, pinList)
    if not name then return end
    staticPinBatches[name] = pinList or {}
    isPinsDirty = true
    isMinimapPinsDirty = true
    pins.RequestRefresh(0.05)
end

--- Clears static pins for a category.
--- @param name string category key
function pins.ClearPins(name)
    if staticPinBatches[name] then
        staticPinBatches[name] = nil
        isPinsDirty = true
        isMinimapPinsDirty = true
        pins.RequestRefresh(0.05)
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
    local found = false

    local function Pulse(pin)
        local base = pin.baseSize or 20
        local enlarged = targetSize or (base + 6)
        pin:SetSize(enlarged, enlarged)
        C_Timer.After(duration, function()
            if pin and pin.SetSize then
                pin:SetSize(base, base)
            end
        end)
    end

    for _, pin in ipairs(activePins) do
        local pd = pin.pinData
        if pin.customID == pinID or (pd and (pd.id == pinID or pd.dungeonID == pinID)) then
            Pulse(pin)
            found = true
        end
    end

    for _, pin in ipairs(activeMinimapPins) do
        local pd = pin.pinData
        if pin.customID == pinID or (pd and (pd.id == pinID or pd.dungeonID == pinID)) then
            Pulse(pin)
            found = true
        end
    end

    return found
end

--- Returns the count of currently visible pins, optionally filtered by provider/source.
--- @param providerName string|nil
--- @param onMinimap boolean|nil if true, counts active minimap pins instead of world map pins
--- @return number count
function pins.GetActiveCount(providerName, onMinimap)
    local targetList = onMinimap and activeMinimapPins or activePins
    if not providerName then return #targetList end
    local count = 0
    for _, pin in ipairs(targetList) do
        if pin.pinData and (pin.pinData.provider == providerName or pin.pinData.source == providerName) then
            count = count + 1
        end
    end
    return count
end

local reusableCandidateList = {}
local reusablePlayerCandidateList = {}
local scratchParentList = {}

local function SetupPinVisuals(pin, p)
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

    if pin.SetRoundBorderColor then
        pin:SetRoundBorderColor(p.borderColor or { 0, 0, 0, 1 })
    elseif pin.SetBackdropBorderColor then
        local bc = p.borderColor
        pin:SetBackdropBorderColor(bc and bc[1] or 0, bc and bc[2] or 0, bc and bc[3] or 0, bc and bc[4] or 1)
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
end

-- ─── Pin Setup & Visual Application ───────────────────────────────────────────
local function SetupPin(pin, canvas, canvasW, canvasH, p)
    pin.pinData  = p
    pin.customID = p.id
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", canvas, "TOPLEFT", canvasW * p.x, -canvasH * p.y)

    SetupPinVisuals(pin, p)

    pin:Show()
    activePins[#activePins + 1] = pin
end

-- ─── Candidate Pin Collection Engine ──────────────────────────────────────────
local function CollectCandidatePins(mapID, outList)
    local list = outList or reusableCandidateList
    wipe(list)
    if not mapID then return list end

    local playerLevel   = (UnitLevel and UnitLevel("player")) or 1
    local playerFaction = (sfui.common and sfui.common.get_player_faction and sfui.common.get_player_faction()) or "Alliance"

    -- 1. Dynamic Providers in Priority Order
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
                    p.mapID = p.mapID or mapID
                    p.size = p.size or prov.defaultSize or 20
                    list[#list + 1] = p
                end
            end
        end
    end

    -- 2. Static Pin Batches
    for batchName, pinList in pairs(staticPinBatches) do
        if pinList and #pinList > 0 then
            for _, p in ipairs(pinList) do
                if (p.mapID == mapID or not p.mapID) and p.x and p.y then
                    p.provider = p.provider or batchName
                    p.mapID = p.mapID or mapID
                    p.size = p.size or 20
                    list[#list + 1] = p
                end
            end
        end
    end

    return list
end
pins.CollectCandidatePins = CollectCandidatePins

local function CollectCandidatePinsForPlayer()
    local playerMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not playerMapID then
        wipe(reusablePlayerCandidateList)
        return reusablePlayerCandidateList, nil
    end

    CollectCandidatePins(playerMapID, reusablePlayerCandidateList)

    -- Also check parent map if player is currently in a subzone/micro-map
    local mapInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(playerMapID)
    local parentMapID = mapInfo and mapInfo.parentMapID
    if parentMapID and parentMapID > 0 and parentMapID ~= playerMapID then
        CollectCandidatePins(parentMapID, scratchParentList)
        for _, p in ipairs(scratchParentList) do
            reusablePlayerCandidateList[#reusablePlayerCandidateList + 1] = p
        end
    end

    return reusablePlayerCandidateList, playerMapID
end

-- ─── WorldMap Render Pass ─────────────────────────────────────────────────────
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

    local playerLevel = (UnitLevel and UnitLevel("player")) or 1

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

    local canvasOverlay = nil
    if sfui.map and sfui.map.GetCanvas then
        local overlayName = "SfuiWorldMapPinsOverlay"
        canvasOverlay = _G[overlayName]
        if not canvasOverlay or canvasOverlay:GetParent() ~= canvas then
            canvasOverlay = CreateFrame("Frame", overlayName, canvas)
            canvasOverlay:SetAllPoints(canvas)
            canvasOverlay:SetFrameStrata(canvas:GetFrameStrata())
            canvasOverlay:SetFrameLevel(canvas:GetFrameLevel() + 15)
            canvasOverlay:EnableMouse(false)
        end
    end
    local pinParent = canvasOverlay or canvas

    local candidatePins = CollectCandidatePins(mapID)
    for _, p in ipairs(candidatePins) do
        local pin = AcquirePin(pinParent, p.size or 20)
        SetupPin(pin, canvas, canvasW, canvasH, p)
    end
end
pins.UpdatePins = RenderPins

-- ─── Minimap Pin Placement Engine ─────────────────────────────────────────────
local cachedPlayerPins        = nil
local cachedPlayerPinsMapID   = nil
local minimapContainer        = nil

local function InvalidateMinimapPins()
    isMinimapPinsDirty = true
    cachedPlayerPins = nil
    cachedPlayerPinsMapID = nil
end
pins.InvalidateMinimapPins = InvalidateMinimapPins

local function ReleaseMinimapPins()
    for i, pin in ipairs(activeMinimapPins) do
        pin:Hide()
        pin.pinData = nil
        pin.customID = nil
        activeMinimapPins[i] = nil
    end
end
pins.ReleaseMinimapPins = ReleaseMinimapPins

local function GetMinimapViewRadius()
    if _G.C_Minimap and _G.C_Minimap.GetViewRadius then
        local ok, r = pcall(_G.C_Minimap.GetViewRadius)
        if ok and r and r > 0 then
            return r
        end
    end
    local zoom = _G.Minimap and _G.Minimap.GetZoom and _G.Minimap:GetZoom() or 0
    local isInside = (_G.GetCVar and _G.GetCVar("minimapInsideZoom") == "1") or (_G.IsIndoors and _G.IsIndoors())
    local outdoorRadius = { [0] = 116.666, [1] = 100, [2] = 83.333, [3] = 66.666, [4] = 50, [5] = 33.333 }
    local indoorRadius  = { [0] = 50, [1] = 40, [2] = 33.333, [3] = 25, [4] = 16.666, [5] = 10 }
    local t = isInside and indoorRadius or outdoorRadius
    return t[zoom] or 100
end

local function AcquireMinimapPin(parent, defaultSize)
    defaultSize = defaultSize or 14
    for _, pin in ipairs(minimapPinPool) do
        if not pin:IsShown() then
            pin:SetParent(parent)
            pin:SetSize(defaultSize, defaultSize)
            pin.baseSize = defaultSize
            pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            pin.icon:SetDesaturated(false)
            pin.icon:SetVertexColor(1, 1, 1, 1)
            if pin.SetRoundBorderColor then
                pin:SetRoundBorderColor(0, 0, 0, 1)
            elseif pin.SetBackdropBorderColor then
                pin:SetBackdropBorderColor(0, 0, 0, 1)
            end
            pin.countText:SetText("")
            pin.countText:SetTextColor(1, 1, 1, 1)
            pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            return pin
        end
    end

    local pin = CreateFrame("Button", nil, parent)
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pin:SetSize(defaultSize, defaultSize)
    pin.baseSize = defaultSize
    pin:SetFrameStrata(parent:GetFrameStrata())
    pin:SetFrameLevel(parent:GetFrameLevel() + 5)
    pin.isMinimapPin = true

    local icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon = icon

    local hi = pin:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetColorTexture(1, 1, 1, 0.25)
    pin.highlightTexture = hi

    if sfui.common and sfui.common.apply_round_icon_style then
        sfui.common.apply_round_icon_style(pin, icon, 1)
    end

    local countText = pin:CreateFontString(nil, "OVERLAY")
    local fontPath = (sfui.config and sfui.config.fontFile)
        or (_G.STANDARD_TEXT_FONT and _G.STANDARD_TEXT_FONT ~= "" and _G.STANDARD_TEXT_FONT)
        or "Fonts\\FRIZQT__.TTF"
    countText:SetFont(fontPath, 8, "OUTLINE")
    countText:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", 2, -2)
    countText:SetTextColor(1, 1, 1, 1)
    countText:SetShadowColor(0, 0, 0, 1)
    countText:SetShadowOffset(1, -1)
    pin.countText = countText

    pin:SetScript("OnEnter", function(self)
        local pinData = self.pinData
        if not pinData then return end
        if pinData.OnEnter then
            pinData.OnEnter(self, GameTooltip, pinData)
        elseif pinData.title and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
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
        else
            sfui.common.hide_tooltip()
        end
    end)

    pin:SetScript("OnClick", function(self, button)
        local pinData = self.pinData
        if not pinData then return end

        if IsShiftKeyDown() and button == "LeftButton" then
            local mapID = pinData.mapID or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
            if SetWaypoint(mapID, pinData.x, pinData.y, pinData.title or pinData.label or "waypoint") then
                return
            end
        end

        if pinData.OnClick then
            pinData.OnClick(self, button, pinData)
        end
    end)

    minimapPinPool[#minimapPinPool + 1] = pin
    return pin
end

local function SetupMinimapPin(pin, container, pixelX, pixelY, p)
    pin.pinData  = p
    pin.customID = p.id
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", container, "CENTER", pixelX, pixelY)

    SetupPinVisuals(pin, p)

    pin:Show()
    activeMinimapPins[#activeMinimapPins + 1] = pin
end

local mapWorldSizeCache = {}

local function GetMapWorldSizeFast(mapID)
    if not mapID then return nil, nil end
    local cached = mapWorldSizeCache[mapID]
    if cached ~= nil then
        if cached then
            return cached[1], cached[2]
        end
        return nil, nil
    end

    if C_Map and C_Map.GetMapWorldSize then
        local ok, w, h = pcall(C_Map.GetMapWorldSize, mapID)
        if ok and w and w > 0 and h and h > 0 then
            mapWorldSizeCache[mapID] = { w, h }
            return w, h
        end
    end
    mapWorldSizeCache[mapID] = false
    return nil, nil
end

local minimapPosCacheX = {}
local minimapPosCacheY = {}

local function RenderMinimapPins(force)
    local mm = _G.Minimap
    if not mm or not mm:IsShown() then
        ReleaseMinimapPins()
        return
    end

    if not GetMinimapShowPins() then
        ReleaseMinimapPins()
        return
    end

    local container = pins.GetMinimapContainer and pins.GetMinimapContainer()
    if not container then
        ReleaseMinimapPins()
        return
    end

    local playerMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not playerMapID then
        ReleaseMinimapPins()
        lastMinimapMapID = nil
        return
    end

    local mmW, mmH = mm:GetSize()
    if not mmW or mmW <= 0 or not mmH or mmH <= 0 then
        ReleaseMinimapPins()
        return
    end
    local halfW = mmW * 0.5
    local halfH = mmH * 0.5

    local viewRadius = GetMinimapViewRadius()
    if not viewRadius or viewRadius <= 0 then
        ReleaseMinimapPins()
        return
    end

    local isRotated = _G.GetCVarBool and _G.GetCVarBool("rotateMinimap")
    local facing = isRotated and ((_G.GetPlayerFacing and _G.GetPlayerFacing()) or 0) or 0

    if isMinimapPinsDirty or not cachedPlayerPins or cachedPlayerPinsMapID ~= playerMapID then
        cachedPlayerPins, cachedPlayerPinsMapID = CollectCandidatePinsForPlayer()
        isMinimapPinsDirty = false
    end

    if not cachedPlayerPins or #cachedPlayerPins == 0 then
        ReleaseMinimapPins()
        lastMinimapMapID = playerMapID
        return
    end

    local primaryPos = C_Map.GetPlayerMapPosition(playerMapID, "player")
    local primaryPX, primaryPY = 0, 0
    if primaryPos then
        primaryPX, primaryPY = primaryPos:GetXY()
    end

    if not force
        and playerMapID == lastMinimapMapID
        and math_abs(primaryPX - (lastMinimapPX or 0)) < 0.00005
        and math_abs(primaryPY - (lastMinimapPY or 0)) < 0.00005
        and math_abs(facing - (lastMinimapFacing or 0)) < 0.01
        and viewRadius == lastMinimapRadius then
        return
    end

    lastMinimapMapID    = playerMapID
    lastMinimapPX       = primaryPX
    lastMinimapPY       = primaryPY
    lastMinimapFacing   = facing
    lastMinimapRadius   = viewRadius

    local cosF = isRotated and math.cos(facing) or 1
    local sinF = isRotated and math.sin(facing) or 0
    local pixelsPerYard = halfW / viewRadius
    local maxDistYards = viewRadius * 1.15
    local maxDistYardsSq = maxDistYards * maxDistYards
    local defaultPinSize = (sfui.config and sfui.config.minimap and sfui.config.minimap.pinSize) or 14

    wipe(minimapPosCacheX)
    wipe(minimapPosCacheY)
    minimapPosCacheX[playerMapID] = primaryPX
    minimapPosCacheY[playerMapID] = primaryPY

    local visibleCount = 0

    for _, p in ipairs(cachedPlayerPins) do
        local targetMapID = p.mapID or playerMapID
        local px = minimapPosCacheX[targetMapID]
        local py = minimapPosCacheY[targetMapID]
        if px == nil then
            local pPos = C_Map.GetPlayerMapPosition(targetMapID, "player")
            if pPos then
                px, py = pPos:GetXY()
            else
                px, py = false, false
            end
            minimapPosCacheX[targetMapID] = px
            minimapPosCacheY[targetMapID] = py
        end

        if px and py then
            local mapW, mapH = GetMapWorldSizeFast(targetMapID)
            if mapW and mapH then
                local dxYards = (p.x - px) * mapW
                local dyYards = (py - p.y) * mapH
                local distYardsSq = dxYards * dxYards + dyYards * dyYards

                if distYardsSq <= maxDistYardsSq then
                    local rotX, rotY
                    if isRotated then
                        rotX = dxYards * cosF + dyYards * sinF
                        rotY = dyYards * cosF - dxYards * sinF
                    else
                        rotX = dxYards
                        rotY = dyYards
                    end

                    local pixelX = rotX * pixelsPerYard
                    local pixelY = rotY * pixelsPerYard

                    local pinSize = p.size and math.min(p.size, 16) or defaultPinSize
                    local pinRadius = pinSize * 0.5
                    local margin = pinRadius + 1

                    local isSquare = sfui.map and sfui.map.square and sfui.map.square.IsEnabled and sfui.map.square:IsEnabled()
                    local inBounds = false
                    if isSquare then
                        inBounds = math_abs(pixelX) <= (halfW - margin) and math_abs(pixelY) <= (halfH - margin)
                    else
                        local distPixelsSq = pixelX * pixelX + pixelY * pixelY
                        local maxDistPixels = halfW - margin
                        inBounds = distPixelsSq <= (maxDistPixels * maxDistPixels)
                    end

                    if inBounds then
                        visibleCount = visibleCount + 1
                        local pin = activeMinimapPins[visibleCount]
                        if not pin then
                            pin = AcquireMinimapPin(container, pinSize)
                            activeMinimapPins[visibleCount] = pin
                            pin.pinData = p
                            pin.customID = p.id
                            pin:SetSize(pinSize, pinSize)
                            pin:ClearAllPoints()
                            pin:SetPoint("CENTER", container, "CENTER", pixelX, pixelY)
                            SetupPinVisuals(pin, p)
                            pin:Show()
                        else
                            pin:SetSize(pinSize, pinSize)
                            pin:ClearAllPoints()
                            pin:SetPoint("CENTER", container, "CENTER", pixelX, pixelY)
                            if pin.pinData ~= p then
                                pin.pinData = p
                                pin.customID = p.id
                                SetupPinVisuals(pin, p)
                            end
                            if not pin:IsShown() then
                                pin:Show()
                            end
                        end
                    end
                end
            end
        end
    end

    -- Hide any pins that were previously visible but are no longer in view
    for i = visibleCount + 1, #activeMinimapPins do
        local pin = activeMinimapPins[i]
        if pin then
            pin:Hide()
            pin.pinData = nil
            pin.customID = nil
            activeMinimapPins[i] = nil
        end
    end
end
pins.UpdateMinimapPins = RenderMinimapPins

local function GetMinimapContainer()
    if minimapContainer then return minimapContainer end
    local mm = _G.Minimap
    if not mm then return nil end

    minimapContainer = CreateFrame("Frame", "sfuiMinimapPinsContainer", mm)
    minimapContainer:SetAllPoints(mm)
    minimapContainer:SetFrameStrata(mm:GetFrameStrata())
    minimapContainer:SetFrameLevel(mm:GetFrameLevel() + 5)
    minimapContainer:EnableMouse(false)

    local minimapThrottle = 0
    minimapContainer:SetScript("OnUpdate", function(self, elapsed)
        if #providerOrder == 0 and not next(staticPinBatches) then return end
        if not GetMinimapShowPins() then return end
        minimapThrottle = minimapThrottle + elapsed
        if minimapThrottle < 0.1 then return end
        minimapThrottle = 0
        RenderMinimapPins(false)
    end)

    minimapContainer:HookScript("OnHide", function()
        ReleaseMinimapPins()
    end)

    return minimapContainer
end
pins.GetMinimapContainer = GetMinimapContainer

--- Requests an asynchronous re-render pass on the minimap.
--- @param delay number|nil optional debounce delay in seconds (default 0.05)
function pins.RequestMinimapRefresh(delay)
    isMinimapPinsDirty = true
    delay = delay or 0.05
    if common and common.debounce then
        common.debounce("sfui_minimap_pins_refresh", delay, function()
            RenderMinimapPins(true)
        end)
    else
        C_Timer.After(delay, function()
            RenderMinimapPins(true)
        end)
    end
end

--- Requests an asynchronous re-render pass on both the canvas and minimap.
--- @param delay number|nil optional debounce delay in seconds (default 0.05)
function pins.RequestRefresh(delay)
    isPinsDirty = true
    isMinimapPinsDirty = true
    delay = delay or 0.05
    if common and common.debounce then
        common.debounce("sfui_map_pins_refresh", delay, function()
            RenderPins(true)
            RenderMinimapPins(true)
        end)
    else
        C_Timer.After(delay, function()
            RenderPins(true)
            RenderMinimapPins(true)
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
    GetMinimapContainer()

    local wmf = _G.WorldMapFrame
    if wmf then
        wmf:HookScript("OnShow", function()
            StartTicker()
            C_Timer.After(0, function()
                local curWmf = _G.WorldMapFrame
                if curWmf and curWmf:IsShown() then
                    RenderPins(true)
                end
            end)
        end)
        wmf:HookScript("OnHide", function()
            StopTicker()
        end)
        if wmf:IsShown() then
            StartTicker()
            C_Timer.After(0, function()
                local curWmf = _G.WorldMapFrame
                if curWmf and curWmf:IsShown() then
                    RenderPins(true)
                end
            end)
        end
    end

    pins.RegisterTrackingCategory("minimap pins", {
        {
            text = "show pins on minimap",
            get  = GetMinimapShowPins,
            set  = SetMinimapShowPins,
        },
    })

    RenderMinimapPins(true)

    if sfui.events and sfui.events.RegisterEvent then
        local function OnStateChanged()
            InvalidateMinimapPins()
            pins.RequestRefresh(0.1)
        end

        local function OnQuestStateChanged()
            InvalidateQuestCache()
            InvalidateMinimapPins()
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
        sfui.events.RegisterEvent("MINIMAP_UPDATE_ZOOM", function()
            pins.RequestMinimapRefresh(0)
        end)
        sfui.events.RegisterEvent("CVAR_UPDATE", function(cvarName)
            if cvarName == "rotateMinimap" then
                pins.RequestMinimapRefresh(0)
            end
        end)
    end
end

if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("PLAYER_LOGIN", InitPinEngine)
end
