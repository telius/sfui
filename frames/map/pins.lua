local addonName, addon = ...
sfui = sfui or {}
sfui.pins = sfui.pins or {}
sfui.map = sfui.map or {}
sfui.map.pins = sfui.pins
local pins = sfui.pins

-- Guard: Camelot & Classic only. Retail provides native map data providers.
if sfui.isRetail then return end

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
local UnitPosition        = _G.UnitPosition
local GetPlayerFacing     = _G.GetPlayerFacing
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
local math_cos            = math.cos
local math_sin            = math.sin
local math_min            = math.min
local tostring            = tostring
local wipe                = sfui.common.wipe
local issecretvalue       = sfui.safety.issecretvalue

local DEFAULT_BORDER_COLOR = { 0, 0, 0, 1 }
local OUTDOOR_RADIUS       = { [0] = 116.666, [1] = 100, [2] = 83.333, [3] = 66.666, [4] = 50, [5] = 33.333 }
local INDOOR_RADIUS        = { [0] = 50, [1] = 40, [2] = 33.333, [3] = 25, [4] = 16.666, [5] = 10 }

local common              = sfui.common
local set_square_icon_coords = (common and common.set_square_icon_coords)
    or function(tex) if tex and tex.SetTexCoord then tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) end end

local function can_modify_pin(pin)
    if not pin then return false end
    if not (InCombatLockdown and InCombatLockdown()) then
        return true
    end
    if pin.IsProtected then
        local prot = pin:IsProtected()
        if (issecretvalue and issecretvalue(prot)) or prot then
            return false
        end
    end
    if pin.IsAnchoringRestricted then
        local rest = pin:IsAnchoringRestricted()
        if (issecretvalue and issecretvalue(rest)) or rest then
            return false
        end
    end
    return true
end

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
local tickerActive        = false

local lastMapID           = nil
local lastCanvasW         = nil
local lastCanvasH         = nil
local lastPlayerLevel     = nil

local lastMinimapPX       = nil
local lastMinimapPY       = nil
local lastMinimapWX       = nil
local lastMinimapWY       = nil
local lastMinimapCont     = nil
local lastMinimapFacing   = nil
local lastMinimapRadius   = nil
local lastMinimapRotated  = nil
local lastMinimapMapID    = nil

-- ─── Centralized Quest & Bag Status Lookup ────────────────────────────────────
function pins.InvalidateQuestCache()
end

function pins.IsQuestCompleted(questID)
    if not questID then return false end
    return (sfui.common and sfui.common.is_quest_completed and sfui.common.is_quest_completed(questID)) == true
end

function pins.IsQuestActive(questID)
    if not questID then return false end
    local qs = sfui.queststate
    return (qs and qs.IsActive and qs.IsActive(questID)) == true
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
                    local getFn = opt.get
                    local setFn = opt.set
                    if type(getFn) == "function" and type(setFn) == "function" then
                        rootDescription:CreateCheckbox(opt.text, function()
                            return getFn() == true
                        end, function()
                            local cur = getFn() == true
                            setFn(not cur)
                        end)
                    end
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
            set_square_icon_coords(pin.icon)
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
    local fontPath = sfui.common.get_font_file()
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
        pin._lastSize = enlarged
        pin:SetSize(enlarged, enlarged)
        C_Timer.After(duration, function()
            if pin and pin.SetSize then
                pin._lastSize = base
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
        set_square_icon_coords(pin.icon)
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
        pin:SetRoundBorderColor(p.borderColor or DEFAULT_BORDER_COLOR)
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

    -- Also check parent map only if player is currently in a micro-map or dungeon
    local mapInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(playerMapID)
    local parentMapID = mapInfo and mapInfo.parentMapID
    if parentMapID and parentMapID > 0 and parentMapID ~= playerMapID then
        local uiMapType = _G.Enum and _G.Enum.UIMapType
        if (not uiMapType) or (mapInfo.mapType == nil) or (mapInfo.mapType == uiMapType.Micro) or (mapInfo.mapType == uiMapType.Dungeon) then
            CollectCandidatePins(parentMapID, scratchParentList)
            for _, p in ipairs(scratchParentList) do
                reusablePlayerCandidateList[#reusablePlayerCandidateList + 1] = p
            end
        end
    end

    return reusablePlayerCandidateList, playerMapID
end

-- ─── WorldMap Render Pass ─────────────────────────────────────────────────────
local function RenderPins(force)
    if InCombatLockdown and InCombatLockdown() then return end
    local wmf = _G.WorldMapFrame
    if not wmf or not wmf:IsShown() then
        ReleasePins()
        lastMapID = nil
        return
    end

    local djOverlay = _G.SfuiWorldMapDungeonOverlay
    if djOverlay and djOverlay:IsShown() then
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
local minimapPinsMouseEnabled = true

local function InvalidateMinimapPins()
    isMinimapPinsDirty = true
    cachedPlayerPins = nil
    cachedPlayerPinsMapID = nil
    lastMinimapWX = nil
    lastMinimapWY = nil
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
        local r = _G.C_Minimap.GetViewRadius()
        if r and ((not issecretvalue) or (not issecretvalue(r))) and type(r) == "number" and r > 0 then
            return r
        end
    end
    local zoom = _G.Minimap and _G.Minimap.GetZoom and _G.Minimap:GetZoom() or 0
    local isInside = (_G.GetCVar and _G.GetCVar("minimapInsideZoom") == "1") or (_G.IsIndoors and _G.IsIndoors())
    local t = isInside and INDOOR_RADIUS or OUTDOOR_RADIUS
    return t[zoom] or 100
end

local function AcquireMinimapPin(parent, defaultSize)
    defaultSize = defaultSize or 14
    for _, pin in ipairs(minimapPinPool) do
        if not pin:IsShown() then
            pin:SetParent(parent)
            if pin._lastSize ~= defaultSize then
                pin._lastSize = defaultSize
                pin:SetSize(defaultSize, defaultSize)
            end
            pin.baseSize = defaultSize
            set_square_icon_coords(pin.icon)
            pin.icon:SetDesaturated(false)
            pin.icon:SetVertexColor(1, 1, 1, 1)
            if pin.SetRoundBorderColor then
                pin:SetRoundBorderColor(DEFAULT_BORDER_COLOR)
            elseif pin.SetBackdropBorderColor then
                pin:SetBackdropBorderColor(0, 0, 0, 1)
            end
            pin.countText:SetText("")
            pin.countText:SetTextColor(1, 1, 1, 1)
            pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            if pin._mouseEnabled ~= minimapPinsMouseEnabled and can_modify_pin(pin) and pin.EnableMouse then
                pin._mouseEnabled = minimapPinsMouseEnabled
                pin:EnableMouse(minimapPinsMouseEnabled)
            end
            return pin
        end
    end

    local pin = CreateFrame("Button", nil, parent)
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    if can_modify_pin(pin) and pin.EnableMouse then
        pin._mouseEnabled = minimapPinsMouseEnabled
        pin:EnableMouse(minimapPinsMouseEnabled)
    end
    pin:SetSize(defaultSize, defaultSize)
    pin._lastSize = defaultSize
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
    local fontPath = sfui.common.get_font_file()
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
local cachedRotateMinimap = nil
local cachedMMW = nil
local cachedMMH = nil
local minimapSizeHooked = false
local overlayDrivingMinimapPins = false
local minimapUpdateRegistered = false

local function RenderMinimapPins(force, extMapID, extFacing, extRadius, extRotated)
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

    local playerMapID = extMapID or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    if not playerMapID then
        ReleaseMinimapPins()
        lastMinimapMapID = nil
        return
    end

    local mmW, mmH = cachedMMW, cachedMMH
    if not mmW or mmW <= 0 or not mmH or mmH <= 0 then
        mmW, mmH = mm:GetSize()
        cachedMMW, cachedMMH = mmW, mmH
    end
    if not mmW or mmW <= 0 or not mmH or mmH <= 0 then
        ReleaseMinimapPins()
        return
    end
    local halfW = mmW * 0.5
    local halfH = mmH * 0.5

    local viewRadius = (extRadius and extRadius > 0) and extRadius or GetMinimapViewRadius()
    if not viewRadius or viewRadius <= 0 then
        ReleaseMinimapPins()
        return
    end

    local isRotated
    if extRotated ~= nil then
        isRotated = extRotated and true or false
    else
        if cachedRotateMinimap == nil then
            cachedRotateMinimap = (_G.GetCVarBool and _G.GetCVarBool("rotateMinimap")) and true or false
        end
        isRotated = cachedRotateMinimap
    end
    local facing
    if extFacing ~= nil then
        facing = isRotated and extFacing or 0
    else
        facing = isRotated and ((GetPlayerFacing and GetPlayerFacing()) or 0) or 0
    end

    if isMinimapPinsDirty or not cachedPlayerPins or cachedPlayerPinsMapID ~= playerMapID then
        cachedPlayerPins, cachedPlayerPinsMapID = CollectCandidatePinsForPlayer()
        isMinimapPinsDirty = false
    end

    if not cachedPlayerPins or #cachedPlayerPins == 0 then
        ReleaseMinimapPins()
        lastMinimapMapID = playerMapID
        return
    end

    local wx, wy, ucont
    if UnitPosition then
        local ux, uy, _, uc = UnitPosition("player")
        if ux ~= nil and uy ~= nil and ((not issecretvalue) or (not issecretvalue(ux) and not issecretvalue(uy) and not issecretvalue(uc))) then
            wx, wy, ucont = ux, uy, uc
        end
    end

    if not force
        and playerMapID == lastMinimapMapID
        and isRotated == lastMinimapRotated
        and math_abs(facing - (lastMinimapFacing or 0)) < 0.01
        and viewRadius == lastMinimapRadius
        and wx ~= nil and wy ~= nil
        and lastMinimapWX ~= nil and lastMinimapWY ~= nil
        and ucont == lastMinimapCont
        and math_abs(wx - lastMinimapWX) < 0.05
        and math_abs(wy - lastMinimapWY) < 0.05 then
        return
    end

    local primaryPos = C_Map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(playerMapID, "player")
    local primaryPX, primaryPY = 0, 0
    if primaryPos then
        primaryPX, primaryPY = primaryPos:GetXY()
    end

    if not force
        and playerMapID == lastMinimapMapID
        and isRotated == lastMinimapRotated
        and math_abs(primaryPX - (lastMinimapPX or 0)) < 0.00005
        and math_abs(primaryPY - (lastMinimapPY or 0)) < 0.00005
        and math_abs(facing - (lastMinimapFacing or 0)) < 0.01
        and viewRadius == lastMinimapRadius then
        lastMinimapWX = wx
        lastMinimapWY = wy
        lastMinimapCont = ucont
        return
    end

    lastMinimapMapID    = playerMapID
    lastMinimapPX       = primaryPX
    lastMinimapPY       = primaryPY
    lastMinimapWX       = wx
    lastMinimapWY       = wy
    lastMinimapCont     = ucont
    lastMinimapFacing   = facing
    lastMinimapRotated  = isRotated
    lastMinimapRadius   = viewRadius

    local cosF = isRotated and math_cos(facing) or 1
    local sinF = isRotated and math_sin(facing) or 0
    local pixelsPerYard = halfW / viewRadius
    local maxDistYards = viewRadius * 1.15
    local maxDistYardsSq = maxDistYards * maxDistYards
    local defaultPinSize = (sfui.config and sfui.config.minimap and sfui.config.minimap.pinSize) or 14

    local overlayActive = sfui.map and sfui.map.overlay and sfui.map.overlay.IsActive and sfui.map.overlay:IsActive()
    local isSquare = (not overlayActive) and sfui.map and sfui.map.square and sfui.map.square.IsEnabled and sfui.map.square:IsEnabled()

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
            local pPos = C_Map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(targetMapID, "player")
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

                    local pinSize = p.size and math_min(p.size, 16) or defaultPinSize
                    local pinRadius = pinSize * 0.5
                    local margin = pinRadius + 1

                    local inBounds
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
                            if pin._lastSize ~= pinSize then
                                pin._lastSize = pinSize
                                pin:SetSize(pinSize, pinSize)
                            end
                            pin:SetPoint("CENTER", container, "CENTER", pixelX, pixelY)
                            SetupPinVisuals(pin, p)
                            if pin._mouseEnabled ~= minimapPinsMouseEnabled and can_modify_pin(pin) and pin.EnableMouse then
                                pin._mouseEnabled = minimapPinsMouseEnabled
                                pin:EnableMouse(minimapPinsMouseEnabled)
                            end
                            pin:Show()
                        else
                            if pin._lastSize ~= pinSize then
                                pin._lastSize = pinSize
                                pin:SetSize(pinSize, pinSize)
                            end
                            pin:SetPoint("CENTER", container, "CENTER", pixelX, pixelY)
                            if pin.pinData ~= p then
                                pin.pinData = p
                                pin.customID = p.id
                                SetupPinVisuals(pin, p)
                            end
                            if pin._mouseEnabled ~= minimapPinsMouseEnabled and can_modify_pin(pin) and pin.EnableMouse then
                                pin._mouseEnabled = minimapPinsMouseEnabled
                                pin:EnableMouse(minimapPinsMouseEnabled)
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

local function OnMinimapPinsTick()
    if not minimapContainer or not minimapContainer:IsShown() then return end
    if #providerOrder == 0 and not next(staticPinBatches) then return end
    if not GetMinimapShowPins() then return end
    RenderMinimapPins(false)
end

local function SyncMinimapPinTicker()
    if not sfui.events then return end
    local wantTick = (minimapContainer ~= nil) and (not overlayDrivingMinimapPins)
    if wantTick == minimapUpdateRegistered then return end
    minimapUpdateRegistered = wantTick
    if wantTick then
        if sfui.events.RegisterUpdate then
            sfui.events.RegisterUpdate("SfuiMinimapPins", 0.1, OnMinimapPinsTick)
        end
    else
        if sfui.events.UnregisterUpdate then
            sfui.events.UnregisterUpdate("SfuiMinimapPins")
        end
    end
end

function pins.SetOverlayDriving(enabled)
    local nextDriving = enabled and true or false
    if overlayDrivingMinimapPins == nextDriving then return end
    overlayDrivingMinimapPins = nextDriving
    SyncMinimapPinTicker()
end

local function GetMinimapContainer()
    if minimapContainer then return minimapContainer end
    local mm = _G.Minimap
    if not mm then return nil end

    minimapContainer = CreateFrame("Frame", "sfuiMinimapPinsContainer", mm)
    minimapContainer:SetAllPoints(mm)
    minimapContainer:SetFrameStrata(mm:GetFrameStrata())
    minimapContainer:SetFrameLevel(mm:GetFrameLevel() + 5)
    minimapContainer:EnableMouse(false)

    if not minimapSizeHooked and mm.HookScript then
        minimapSizeHooked = true
        mm:HookScript("OnSizeChanged", function(_, w, h)
            if (issecretvalue and (issecretvalue(w) or issecretvalue(h))) then return end
            cachedMMW = w
            cachedMMH = h
            lastMinimapRadius = nil
        end)
    end
    cachedMMW, cachedMMH = mm:GetSize()

    SyncMinimapPinTicker()

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
local function StopTicker()
    if tickerActive then
        if sfui.events and sfui.events.UnregisterUpdate then
            sfui.events.UnregisterUpdate("SfuiWorldMapPins")
        end
        tickerActive = false
    end
    ReleasePins()
end

local function OnMapPinTick()
    if InCombatLockdown and InCombatLockdown() then return end
    local wmf = _G.WorldMapFrame
    if wmf and wmf:IsShown() then
        RenderPins(false)
    else
        StopTicker()
    end
end

local function StartTicker()
    if InCombatLockdown and InCombatLockdown() then return end
    if tickerActive then return end
    if sfui.events and sfui.events.RegisterUpdate then
        tickerActive = true
        sfui.events.RegisterUpdate("SfuiWorldMapPins", 0.5, OnMapPinTick)
    end
end

local function InitPinEngine()
    HookWorldMapTrackingMenu()
    GetMinimapContainer()

    local wmf = _G.WorldMapFrame
    if wmf then
        wmf:HookScript("OnShow", function()
            if InCombatLockdown and InCombatLockdown() then return end
            StartTicker()
            C_Timer.After(0, function()
                if InCombatLockdown and InCombatLockdown() then return end
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
            InvalidateMinimapPins()
            pins.RequestRefresh(0.15)
        end

        sfui.events.RegisterEvent("ZONE_CHANGED", OnStateChanged)
        sfui.events.RegisterEvent("ZONE_CHANGED_NEW_AREA", OnStateChanged)
        sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", OnStateChanged)
        sfui.events.RegisterEvent("BAG_UPDATE_DELAYED", OnStateChanged)
        if sfui.events.RegisterMessage and sfui.queststate then
            sfui.events.RegisterMessage("SFUI_QUEST_STATE_UPDATED", OnQuestStateChanged)
        else
            sfui.events.RegisterEvent("QUEST_LOG_UPDATE", OnQuestStateChanged)
            sfui.events.RegisterEvent("QUEST_ACCEPTED", OnQuestStateChanged)
            sfui.events.RegisterEvent("QUEST_REMOVED", OnQuestStateChanged)
            sfui.events.RegisterEvent("QUEST_TURNED_IN", OnQuestStateChanged)
        end
        sfui.events.RegisterEvent("PLAYER_LEVEL_UP", OnQuestStateChanged)
        sfui.events.RegisterEvent("SKILL_LINES_CHANGED", OnStateChanged)
        sfui.events.RegisterEvent("CHAT_MSG_SKILL", OnStateChanged)
        sfui.events.RegisterEvent("MINIMAP_UPDATE_ZOOM", function()
            pins.RequestMinimapRefresh(0)
        end)
        sfui.events.RegisterEvent("CVAR_UPDATE", function(_, cvarName)
            if cvarName == "rotateMinimap" then
                cachedRotateMinimap = (_G.GetCVarBool and _G.GetCVarBool("rotateMinimap")) and true or false
                pins.RequestMinimapRefresh(0)
            end
        end)
    end
end

if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("PLAYER_LOGIN", InitPinEngine)
end

local _pinsDebug = {}
function pins.SetMinimapPinsMouseEnabled(enabled)
    minimapPinsMouseEnabled = enabled and true or false
    local gTip = _G.GameTooltip
    for _, pin in ipairs(activeMinimapPins) do
        if pin and can_modify_pin(pin) and pin.EnableMouse then
            pin:EnableMouse(minimapPinsMouseEnabled)
        end
        if not minimapPinsMouseEnabled and pin then
            local owned = (GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(pin))
                or (gTip and gTip.IsOwned and gTip:IsOwned(pin))
            if owned then
                local onLeave = pin.GetScript and pin:GetScript("OnLeave")
                if onLeave then
                    onLeave(pin)
                elseif gTip and gTip.Hide then
                    gTip:Hide()
                end
            end
        end
    end
end

function pins.TriggerHoveredMinimapPinEnter()
    if not minimapPinsMouseEnabled then return false end
    for _, pin in ipairs(activeMinimapPins) do
        if pin and pin:IsShown() and pin.IsMouseOver and pin:IsMouseOver() then
            local onEnter = pin.GetScript and pin:GetScript("OnEnter")
            if onEnter then
                onEnter(pin)
                return true
            end
        end
    end
    return false
end

function sfui.pins_debug_info()
    local wmf = _G.WorldMapFrame
    _pinsDebug.mapShown          = (wmf and wmf:IsShown()) and true or false
    _pinsDebug.activeCount       = #activePins
    _pinsDebug.poolSize          = #pinPool
    _pinsDebug.minimapActive     = #activeMinimapPins
    _pinsDebug.minimapPoolSize   = #minimapPinPool
    _pinsDebug.providersCount    = #providerOrder
    return _pinsDebug
end
pins.GetDebugInfo = sfui.pins_debug_info

if sfui.RegisterModule then
    sfui.RegisterModule("pins", pins)
end
