local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
if sfui.isRetail then return end

local GameTooltip = (sfui.common and sfui.common.get_tooltip and sfui.common.get_tooltip()) or _G.GameTooltip
sfui.dj_map = {}

local dj_map = sfui.dj_map

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/dungeonjournal/dj_map.lua
--  Interactive Dungeon Map, Travel Route Guide, World Map Polyline Renderer,
--  and World Map (M) In-Dungeon Overlay for Camelot / Forever.
-- ══════════════════════════════════════════════════════════════════════════════

local MEDIA_PATH = "Interface\\AddOns\\sfui\\media\\dungeonmaps\\"
local LADDER_TEX = MEDIA_PATH .. "LevelLadder"
local ENTRANCE_TEX = MEDIA_PATH .. "EntranceArrow"
local WISHLIST_TEX = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3"

local MIN_ZOOM = 1.0
local MAX_ZOOM = 4.0
local ZOOM_STEP = 0.25

local STROKE_OFFSETS = {
    { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 },
    { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 },
}

local QUEST_ACT_TEXT = {
    start   = "quest starts here",
    ["end"] = "turn in here",
    loot    = "loot quest item here",
    use     = "use quest object here",
    explore = "explore here",
}

local QUEST_TEXT_KEYS = {
    MAP_OBJ_BFD_CHEST  = "loot the lorgalis manuscript from the pitted iron chest, underwater in this alcove of the pool.",
    MAP_OBJ_BFD_FATHOM = "click the fathom stone underwater, below the walkway, to get the fathom core (summons baron aquanis).",
}

local WAYPOINT_TITLES = {
    ROUTE_WP_TARREN_MILL_TITLE = "tarren mill flight master",
    ROUTE_WP_MENETHIL_TITLE    = "menethil harbor flight master",
    ROUTE_WP_THELSAMAR_TITLE   = "thelsamar flight master",
    ROUTE_WP_IRONFORGE_TITLE   = "ironforge gryphon master",
    ROUTE_WP_UNDERCITY_TITLE   = "undercity bat handler",
    ROUTE_WP_BRILL_TITLE       = "brill",
}

local WAYPOINT_TEXTS = {
    ROUTE_WP_TARREN_MILL_TEXT = "grab the flight path here along the way",
    ROUTE_WP_MENETHIL_TEXT    = "grab the flight path here before heading south",
    ROUTE_WP_THELSAMAR_TEXT   = "grab the loch modan flight path here",
    ROUTE_WP_IRONFORGE_TEXT   = "grab the ironforge flight path inside the great forge",
}

-- ─── Helpers ──────────────────────────────────────────────────────────────────

local function ApplyBackdrop(f, bgR, bgG, bgB, bgA, brR, brG, brB, brA)
    if not f.SetBackdrop then
        Mixin(f, BackdropTemplateMixin)
    end
    f:SetBackdrop(sfui.widgets.FLAT_BACKDROP)
    f:SetBackdropColor(bgR or 0.05, bgG or 0.05, bgB or 0.07, bgA or 0.95)
    f:SetBackdropBorderColor(brR or 0.15, brG or 0.15, brB or 0.18, brA or 1.0)
end

local function SafePlain(v)
    if type(issecretvalue) == "function" and issecretvalue(v) then return nil end
    return v
end

local function GetSavedFloors()
    SfuiDB = SfuiDB or {}
    SfuiDB.djMapFloors = SfuiDB.djMapFloors or {}
    return SfuiDB.djMapFloors
end

local function GetBossIconScale()
    SfuiDB = SfuiDB or {}
    local s = tonumber(SfuiDB.djMapBossScale)
    if not s or s < 0.5 or s > 1.5 then return 1.0 end
    return s
end

local function SetBossIconScale(s)
    SfuiDB = SfuiDB or {}
    SfuiDB.djMapBossScale = math.max(0.5, math.min(1.5, math.floor(s * 10 + 0.5) / 10))
end

local function GetShowQuestPins()
    SfuiDB = SfuiDB or {}
    if SfuiDB.djMapShowQuests == nil then SfuiDB.djMapShowQuests = true end
    return SfuiDB.djMapShowQuests
end

local function IsQuestCompleted(questID)
    if not questID then return false end
    if C_QuestLog and type(C_QuestLog.IsQuestFlaggedCompleted) == "function" then
        local res = SafePlain(C_QuestLog.IsQuestFlaggedCompleted(questID))
        return res == true
    elseif type(IsQuestFlaggedCompleted) == "function" then
        local res = SafePlain(IsQuestFlaggedCompleted(questID))
        return res == true
    end
    return false
end

local function IsQuestInLog(questID)
    if not questID then return false end
    if C_QuestLog and type(C_QuestLog.IsOnQuest) == "function" then
        local res = SafePlain(C_QuestLog.IsOnQuest(questID))
        return res == true
    elseif type(GetQuestLogIndexByID) == "function" then
        local idx = SafePlain(GetQuestLogIndexByID(questID))
        return type(idx) == "number" and idx > 0
    end
    return false
end

local function StrokeIcon(owner, icon, size)
    if not owner or not icon then return end
    local tex = icon.GetTexture and icon:GetTexture()
    if not tex then return end
    local w = math.max(1, math.floor((size or 22) * 0.06 + 0.5))
    owner.strokeTex = owner.strokeTex or {}
    for i, o in ipairs(STROKE_OFFSETS) do
        local s = owner.strokeTex[i]
        if not s then
            s = owner:CreateTexture(nil, "ARTWORK")
            owner.strokeTex[i] = s
        end
        s:SetTexture(tex)
        s:SetVertexColor(0, 0, 0, 1)
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", icon, "TOPLEFT", o[1] * w, o[2] * w)
        s:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", o[1] * w, o[2] * w)
        s:Show()
    end
end

local function FindSfuiBossData(dungeon, bossPin)
    if not dungeon or not bossPin then return nil, nil end
    local target = (bossPin.targetName or bossPin.name or ""):lower()
    local raw = (bossPin.name or ""):lower()
    for i, b in ipairs(dungeon.bosses or {}) do
        local bn = (b.name or ""):lower()
        if bn == raw or bn == target then
            return b, i
        end
    end
    return nil, nil
end

local function GetBossWishlistItems(sfuiBoss)
    if not sfuiBoss or not sfuiBoss.items then return nil end
    local isWishlisted = sfui.dungeonjournal and sfui.dungeonjournal.IsWishlisted
    if not isWishlisted then return nil end
    local out
    for _, rawID in ipairs(sfuiBoss.items) do
        local id = type(rawID) == "table" and (rawID.id or rawID[1]) or rawID
        id = tonumber(id)
        if id and isWishlisted(id) then
            out = out or {}
            out[#out + 1] = id
        end
    end
    return out
end

local function FindDungeonQuestEntry(dungeon, qPin)
    if not dungeon or not qPin then return nil end
    local wantID = tonumber(qPin.main or qPin.id)
    local rawID = tonumber(qPin.id)
    local wantName = (qPin.name or ""):lower()
    for _, q in ipairs(dungeon.quests or {}) do
        if q.id == wantID or q.id == rawID then
            return q
        end
        if q.chain then
            for _, s in ipairs(q.chain) do
                if s.id == wantID or s.id == rawID then return q end
            end
        end
        if q.chainStart and (q.chainStart.id == wantID or q.chainStart.id == rawID) then
            return q
        end
    end
    if wantName ~= "" then
        for _, q in ipairs(dungeon.quests or {}) do
            if (q.name or ""):lower() == wantName then
                return q
            end
        end
    end
    return nil
end

function dj_map.HasMap(dungeon)
    if not dungeon or not dungeon.id then return false end
    local maps = sfui.dj_camelot and sfui.dj_camelot.maps
    local m = maps and maps[dungeon.id]
    return m ~= nil and m.floors ~= nil and #m.floors > 0
end

function dj_map.FindBossMapSpot(dungeon, bossName)
    if not dungeon or not bossName then return nil end
    local m = sfui.dj_camelot and sfui.dj_camelot.maps and sfui.dj_camelot.maps[dungeon.id]
    if not m then return nil end
    local want = bossName:lower()
    for _, b in ipairs(m.bosses or {}) do
        if (b.name or ""):lower() == want or (b.targetName or ""):lower() == want then
            return b
        end
    end
    return nil
end

function dj_map.FindQuestMapSpot(dungeon, questID, questName)
    if not dungeon then return nil end
    local qid = tonumber(questID)
    local qname = questName and questName:lower() or nil
    local pins = sfui.dj_camelot and sfui.dj_camelot.mapQuestPins and sfui.dj_camelot.mapQuestPins[dungeon.id]
    if pins then
        for _, pin in ipairs(pins) do
            for _, spot in ipairs(pin.spots or {}) do
                for _, q in ipairs(spot.quests or {}) do
                    if (qid and (q.id == qid or q.main == qid))
                        or (qname and (q.name or ""):lower() == qname) then
                        return { floor = pin.floor or 1, x = pin.x, y = pin.y, name = spot.name }
                    end
                end
            end
        end
    end
    local m = sfui.dj_camelot and sfui.dj_camelot.maps and sfui.dj_camelot.maps[dungeon.id]
    if m and qid then
        for _, b in ipairs(m.bosses or {}) do
            if b.quest == qid then
                return { floor = b.floor or 1, x = b.x, y = b.y, name = b.name }
            end
        end
    end
    return nil
end

function dj_map.OpenWorldMapSpot(loc, title)
    if not loc or not loc.mapID or not loc.x or not loc.y then return end
    if not InCombatLockdown or not InCombatLockdown() then
        if C_Map and type(C_Map.OpenWorldMap) == "function" then
            C_Map.OpenWorldMap(loc.mapID)
        elseif WorldMapFrame then
            ShowUIPanel(WorldMapFrame)
            if WorldMapFrame.SetMapID then
                WorldMapFrame:SetMapID(loc.mapID)
            end
        end
    end
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        local canSet = true
        if C_Map.CanSetUserWaypointOnMap then
            canSet = C_Map.CanSetUserWaypointOnMap(loc.mapID)
        end
        if canSet then
            local pt = UiMapPoint.CreateFromCoordinates(loc.mapID, loc.x, loc.y)
            if pt then
                C_Map.SetUserWaypoint(pt)
                if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
                end
            end
        end
    end
    local zoneInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(loc.mapID)
    local zoneName = (zoneInfo and zoneInfo.name) and zoneInfo.name:lower() or ("map " .. tostring(loc.mapID))
    if sfui.common and sfui.common.print then
        sfui.common.print(string.format("waypoint set: %s — %s (%.1f, %.1f)",
            (title or loc.label or "target"):lower(), zoneName, loc.x * 100, loc.y * 100))
    end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  1. Interactive Map Widget Builder (Shared by Journal & WorldMap M Overlay)
-- ══════════════════════════════════════════════════════════════════════════════

local function CreateMapController(parent, isWorldMapOverlay)
    local ctrl = {
        parent = parent,
        isWorldMapOverlay = isWorldMapOverlay,
        zoom = 1.0,
        panX = 0,
        panY = 0,
        floorIndex = 1,
        baseW = 600,
        baseH = 400,
        floorButtons = {},
        wingButtons = {},
        bossPins = {},
        questPins = {},
        ladderPins = {},
        entrancePins = {},
        stepRows = {},
    }

    -- Top toolbar (30px)
    local toolbar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    toolbar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    toolbar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    toolbar:SetHeight(30)
    ApplyBackdrop(toolbar, 0.04, 0.04, 0.06, 0.95, 0.14, 0.14, 0.18, 1.0)
    ctrl.toolbar = toolbar

    -- Floor label when 1 floor
    local singleFloorLabel = toolbar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    singleFloorLabel:SetPoint("LEFT", toolbar, "LEFT", 10, 0)
    singleFloorLabel:SetTextColor(0.65, 0.65, 0.72)
    singleFloorLabel:SetText("dungeon map")
    ctrl.singleFloorLabel = singleFloorLabel

    -- Right-side control buttons in toolbar
    local sizePlusBtn = CreateFrame("Button", nil, toolbar, "BackdropTemplate")
    sizePlusBtn:SetSize(22, 20)
    sizePlusBtn:SetPoint("RIGHT", toolbar, "RIGHT", isWorldMapOverlay and -118 or -8, 0)
    ApplyBackdrop(sizePlusBtn, 0.08, 0.08, 0.12, 1.0, 0.22, 0.22, 0.28, 1.0)
    sizePlusBtn.label = sizePlusBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sizePlusBtn.label:SetPoint("CENTER")
    sizePlusBtn.label:SetText("+")
    sizePlusBtn.label:SetTextColor(0.85, 0.85, 0.90)
    sizePlusBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.55, 0.40, 0.85, 1.0)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("increase boss icon size", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    sizePlusBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.22, 0.22, 0.28, 1.0)
        GameTooltip:Hide()
    end)
    sizePlusBtn:SetScript("OnClick", function()
        SetBossIconScale(GetBossIconScale() + 0.1)
        ctrl:RenderCanvas()
    end)
    ctrl.sizePlusBtn = sizePlusBtn

    local sizeMinusBtn = CreateFrame("Button", nil, toolbar, "BackdropTemplate")
    sizeMinusBtn:SetSize(22, 20)
    sizeMinusBtn:SetPoint("RIGHT", sizePlusBtn, "LEFT", -4, 0)
    ApplyBackdrop(sizeMinusBtn, 0.08, 0.08, 0.12, 1.0, 0.22, 0.22, 0.28, 1.0)
    sizeMinusBtn.label = sizeMinusBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sizeMinusBtn.label:SetPoint("CENTER")
    sizeMinusBtn.label:SetText("-")
    sizeMinusBtn.label:SetTextColor(0.85, 0.85, 0.90)
    sizeMinusBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.55, 0.40, 0.85, 1.0)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("decrease boss icon size", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    sizeMinusBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.22, 0.22, 0.28, 1.0)
        GameTooltip:Hide()
    end)
    sizeMinusBtn:SetScript("OnClick", function()
        SetBossIconScale(GetBossIconScale() - 0.1)
        ctrl:RenderCanvas()
    end)
    ctrl.sizeMinusBtn = sizeMinusBtn

    local questToggleBtn = CreateFrame("Button", nil, toolbar, "BackdropTemplate")
    questToggleBtn:SetSize(76, 20)
    questToggleBtn:SetPoint("RIGHT", sizeMinusBtn, "LEFT", -6, 0)
    ApplyBackdrop(questToggleBtn, 0.08, 0.08, 0.12, 1.0, 0.22, 0.22, 0.28, 1.0)
    questToggleBtn.label = questToggleBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    questToggleBtn.label:SetPoint("CENTER")
    questToggleBtn:SetScript("OnClick", function()
        SfuiDB = SfuiDB or {}
        SfuiDB.djMapShowQuests = not GetShowQuestPins()
        ctrl:UpdateToolbar()
        ctrl:RenderCanvas()
    end)
    ctrl.questToggleBtn = questToggleBtn

    local routeBtn = CreateFrame("Button", nil, toolbar, "BackdropTemplate")
    routeBtn:SetSize(96, 20)
    routeBtn:SetPoint("RIGHT", questToggleBtn, "LEFT", -6, 0)
    ApplyBackdrop(routeBtn, 0.10, 0.08, 0.16, 1.0, 0.45, 0.32, 0.75, 1.0)
    routeBtn.label = routeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    routeBtn.label:SetPoint("CENTER")
    routeBtn.label:SetText("travel route")
    routeBtn.label:SetTextColor(0.85, 0.72, 1.0)
    routeBtn:SetScript("OnClick", function()
        ctrl.showingRoute = not ctrl.showingRoute
        ctrl:RefreshView()
    end)
    routeBtn:Hide()
    ctrl.routeBtn = routeBtn

    -- Clipped viewport for the 3:2 map
    local viewport = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    viewport:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -2)
    viewport:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    ApplyBackdrop(viewport, 0.02, 0.02, 0.03, 1.0, 0.12, 0.12, 0.15, 1.0)
    viewport:SetClipsChildren(true)
    viewport:EnableMouse(true)
    viewport:EnableMouseWheel(true)
    ctrl.viewport = viewport

    -- Map holder frame inside viewport
    local holder = CreateFrame("Frame", nil, viewport)
    holder:SetSize(600, 400)
    holder:SetPoint("CENTER", viewport, "CENTER", 0, 0)
    ctrl.holder = holder

    -- Map texture & tile fallback pool
    local mapTex = holder:CreateTexture(nil, "BACKGROUND")
    mapTex:SetAllPoints(holder)
    ctrl.mapTex = mapTex
    ctrl.mapTiles = {}

    -- Hint label in bottom-right of viewport
    local hintLabel = viewport:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hintLabel:SetPoint("BOTTOMRIGHT", viewport, "BOTTOMRIGHT", -8, 6)
    hintLabel:SetTextColor(0.55, 0.55, 0.62, 0.85)
    hintLabel:SetText(isWorldMapOverlay
        and "scroll: zoom · drag: pan · right-click: world map · click pin: open journal"
        or "scroll: zoom · drag: pan · click boss/quest: view details")
    ctrl.hintLabel = hintLabel

    -- Ping / Focus ring on holder
    local pingFrame = CreateFrame("Frame", nil, holder)
    pingFrame:SetSize(56, 56)
    pingFrame:Hide()
    local pingTex = pingFrame:CreateTexture(nil, "OVERLAY")
    pingTex:SetAllPoints()
    pingTex:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    pingTex:SetTexCoord(0, 0.58, 0, 0.58)
    pingTex:SetVertexColor(1.0, 0.85, 0.20, 1.0)
    local pingAG = pingFrame:CreateAnimationGroup()
    pingAG:SetLooping("REPEAT")
    local s1 = pingAG:CreateAnimation("Scale")
    s1:SetOrder(1)
    s1:SetDuration(0.45)
    s1:SetScale(1.28, 1.28)
    local s2 = pingAG:CreateAnimation("Scale")
    s2:SetOrder(2)
    s2:SetDuration(0.45)
    s2:SetScale(1 / 1.28, 1 / 1.28)
    ctrl.pingFrame = pingFrame
    ctrl.pingAG = pingAG

    function ctrl:ClampPan(px, py, z)
        local maxX = math.max(0, (self.baseW * (z - 1)) * 0.5)
        local maxY = math.max(0, (self.baseH * (z - 1)) * 0.5)
        if px > maxX then px = maxX elseif px < -maxX then px = -maxX end
        if py > maxY then py = maxY elseif py < -maxY then py = -maxY end
        return px, py
    end

    function ctrl:ApplyTransform()
        local vw = self.viewport:GetWidth() or 600
        local vh = self.viewport:GetHeight() or 400
        if vw <= 10 or vh <= 10 then
            vw, vh = 600, 400
        end
        local baseW = vw - 4
        local baseH = baseW * (2 / 3)
        if baseH > vh - 4 then
            baseH = vh - 4
            baseW = baseH * 1.5
        end
        self.baseW = math.max(120, baseW)
        self.baseH = math.max(80, baseH)

        self.panX, self.panY = self:ClampPan(self.panX, self.panY, self.zoom)
        local artW = self.baseW * self.zoom
        local artH = self.baseH * self.zoom
        self.holder:SetSize(artW, artH)
        self.holder:ClearAllPoints()
        self.holder:SetPoint("CENTER", self.viewport, "CENTER", self.panX, self.panY)

        if self.tileGrid and #self.mapTiles > 0 then
            local g = self.tileGrid
            local sx, sy = artW / g.layerW, artH / g.layerH
            for i = 1, g.count do
                local t = self.mapTiles[i]
                if t and t:IsShown() then
                    local col, row = (i - 1) % g.cols, math.floor((i - 1) / g.cols)
                    t:SetSize(g.tileW * sx, g.tileH * sy)
                    t:ClearAllPoints()
                    t:SetPoint("TOPLEFT", self.holder, "TOPLEFT", col * g.tileW * sx, -row * g.tileH * sy)
                end
            end
        end

        -- Reposition pins at current zoom
        for _, pin in ipairs(self.entrancePins) do
            if pin:IsShown() and pin.normX and pin.normY then
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", self.holder, "TOPLEFT", pin.normX * artW, -(pin.normY * artH))
            end
        end
        for _, pin in ipairs(self.ladderPins) do
            if pin:IsShown() and pin.normX and pin.normY then
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", self.holder, "TOPLEFT", pin.normX * artW, -(pin.normY * artH))
            end
        end
        for _, pin in ipairs(self.bossPins) do
            if pin:IsShown() and pin.normX and pin.normY then
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", self.holder, "TOPLEFT", pin.normX * artW, -(pin.normY * artH))
            end
        end
        for _, pin in ipairs(self.questPins) do
            if pin:IsShown() and pin.normX and pin.normY then
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", self.holder, "TOPLEFT", pin.normX * artW, -(pin.normY * artH))
            end
        end
        if self.pingFrame:IsShown() and self.pingFrame.normX and self.pingFrame.normY then
            self.pingFrame:ClearAllPoints()
            self.pingFrame:SetPoint("CENTER", self.holder, "TOPLEFT", self.pingFrame.normX * artW, -(self.pingFrame.normY * artH))
        end
    end

    -- Mousewheel zoom anchored to cursor
    viewport:SetScript("OnMouseWheel", function(_, delta)
        local oldZ = ctrl.zoom
        local newZ = math.max(MIN_ZOOM, math.min(MAX_ZOOM, oldZ + (delta > 0 and ZOOM_STEP or -ZOOM_STEP)))
        if math.abs(newZ - oldZ) < 0.001 then return end
        local cx, cy = GetCursorPosition()
        local scale = viewport:GetEffectiveScale() or 1
        cx, cy = cx / scale, cy / scale
        local vx, vy = viewport:GetCenter()
        if vx and vy then
            local relX = cx - vx
            local relY = cy - vy
            local ratio = newZ / oldZ
            ctrl.panX = relX - (relX - ctrl.panX) * ratio
            ctrl.panY = relY - (relY - ctrl.panY) * ratio
        end
        ctrl.zoom = newZ
        if newZ <= 1.001 then
            ctrl.panX, ctrl.panY = 0, 0
        end
        ctrl:ApplyTransform()
    end)

    -- Left-drag panning & Right-click zoom reset / world map return
    viewport:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and ctrl.zoom > 1.001 then
            local cx, cy = GetCursorPosition()
            local scale = self:GetEffectiveScale() or 1
            ctrl.dragStartX = cx / scale
            ctrl.dragStartY = cy / scale
            ctrl.dragOriginX = ctrl.panX
            ctrl.dragOriginY = ctrl.panY
            self:SetScript("OnUpdate", function(v)
                local mx, my = GetCursorPosition()
                local sc = v:GetEffectiveScale() or 1
                mx, my = mx / sc, my / sc
                ctrl.panX = ctrl.dragOriginX + (mx - ctrl.dragStartX)
                ctrl.panY = ctrl.dragOriginY + (my - ctrl.dragStartY)
                ctrl:ApplyTransform()
            end)
        end
    end)

    viewport:SetScript("OnMouseUp", function(self, button)
        self:SetScript("OnUpdate", nil)
        if button == "RightButton" then
            if ctrl.zoom > 1.001 then
                ctrl.zoom = 1.0
                ctrl.panX, ctrl.panY = 0, 0
                ctrl:ApplyTransform()
            elseif ctrl.isWorldMapOverlay and ctrl.onRightClickOut then
                ctrl.onRightClickOut()
            end
        end
    end)

    viewport:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    viewport:SetScript("OnSizeChanged", function()
        if ctrl.dungeon then
            ctrl:ApplyTransform()
        end
    end)

    -- Travel Route Drawer inside parent
    local routeDrawer = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    routeDrawer:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -2)
    routeDrawer:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    ApplyBackdrop(routeDrawer, 0.04, 0.04, 0.06, 0.98, 0.15, 0.15, 0.20, 1.0)
    routeDrawer:Hide()
    ctrl.routeDrawer = routeDrawer

    local routeHeader = routeDrawer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    routeHeader:SetPoint("TOPLEFT", routeDrawer, "TOPLEFT", 14, -12)
    routeHeader:SetTextColor(1.0, 0.82, 0.25)
    ctrl.routeHeader = routeHeader

    local routeSub = routeDrawer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    routeSub:SetPoint("TOPLEFT", routeHeader, "BOTTOMLEFT", 0, -4)
    routeSub:SetTextColor(0.65, 0.65, 0.72)
    ctrl.routeSub = routeSub

    local routeWorldMapBtn = CreateFrame("Button", nil, routeDrawer, "BackdropTemplate")
    routeWorldMapBtn:SetSize(148, 22)
    routeWorldMapBtn:SetPoint("TOPRIGHT", routeDrawer, "TOPRIGHT", -14, -12)
    ApplyBackdrop(routeWorldMapBtn, 0.12, 0.08, 0.20, 1.0, 0.55, 0.38, 0.90, 1.0)
    routeWorldMapBtn.label = routeWorldMapBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    routeWorldMapBtn.label:SetPoint("CENTER")
    routeWorldMapBtn.label:SetText("draw route on world map")
    routeWorldMapBtn.label:SetTextColor(0.90, 0.80, 1.0)
    routeWorldMapBtn:SetScript("OnClick", function()
        local r = ctrl.dungeon and sfui.dj_camelot.routes and sfui.dj_camelot.routes[ctrl.dungeon.id]
        if r and r.mapRoute then
            dj_map.ShowRouteOnWorldMap(r.mapRoute)
        end
    end)
    ctrl.routeWorldMapBtn = routeWorldMapBtn

    local routeScroll = CreateFrame("ScrollFrame", nil, routeDrawer, "UIPanelScrollFrameTemplate")
    routeScroll:SetPoint("TOPLEFT", routeDrawer, "TOPLEFT", 14, -52)
    routeScroll:SetPoint("BOTTOMRIGHT", routeDrawer, "BOTTOMRIGHT", -28, 10)
    local routeContent = CreateFrame("Frame", nil, routeScroll)
    routeContent:SetSize(520, 1)
    routeScroll:SetScrollChild(routeContent)
    ctrl.routeScroll = routeScroll
    ctrl.routeContent = routeContent

    function ctrl:UpdateToolbar()
        local showQ = GetShowQuestPins()
        self.questToggleBtn.label:SetText(showQ and "quests: on" or "quests: off")
        if showQ then
            self.questToggleBtn.label:SetTextColor(1.0, 0.82, 0.0)
            self.questToggleBtn:SetBackdropBorderColor(0.55, 0.45, 0.15, 1.0)
        else
            self.questToggleBtn.label:SetTextColor(0.50, 0.50, 0.55)
            self.questToggleBtn:SetBackdropBorderColor(0.20, 0.20, 0.25, 1.0)
        end

        local hasRoute = self.dungeon and sfui.dj_camelot.routes and sfui.dj_camelot.routes[self.dungeon.id] ~= nil
        if hasRoute and not self.isWorldMapOverlay then
            self.routeBtn:Show()
            self.routeBtn.label:SetText(self.showingRoute and "back to map" or "travel route")
        else
            self.routeBtn:Hide()
        end

        -- Floor buttons (or Scarlet Monastery wing pills on WorldMap overlay)
        for _, b in ipairs(self.floorButtons) do b:Hide() end
        for _, b in ipairs(self.wingButtons) do b:Hide() end

        local m = self.dungeon and sfui.dj_camelot.maps and sfui.dj_camelot.maps[self.dungeon.id]
        local floors = (m and m.floors) or {}
        local xOff = 8

        if self.isWorldMapOverlay and sfui.dj_camelot.InScarletMonastery() then
            self.singleFloorLabel:Hide()
            for i, w in ipairs(sfui.dj_camelot.scarletWings or {}) do
                local btn = self.wingButtons[i]
                if not btn then
                    btn = CreateFrame("Button", nil, self.toolbar, "BackdropTemplate")
                    btn:SetHeight(20)
                    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    btn.label:SetPoint("CENTER")
                    self.wingButtons[i] = btn
                end
                btn.label:SetText(w.short)
                local bw = math.max(58, math.ceil((btn.label:GetStringWidth() or 44) + 16))
                btn:SetWidth(bw)
                btn:ClearAllPoints()
                btn:SetPoint("LEFT", self.toolbar, "LEFT", xOff, 0)
                xOff = xOff + bw + 4
                local active = (self.dungeon and self.dungeon.id == w.id)
                if active then
                    ApplyBackdrop(btn, 0.16, 0.10, 0.26, 1.0, 0.66, 0.40, 1.0, 1.0)
                    btn.label:SetTextColor(1.0, 1.0, 1.0)
                else
                    ApplyBackdrop(btn, 0.07, 0.07, 0.10, 1.0, 0.20, 0.20, 0.25, 1.0)
                    btn.label:SetTextColor(0.65, 0.65, 0.72)
                end
                btn:SetScript("OnClick", function()
                    sfui.dj_camelot.SetScarletWing(w.id)
                    local d = sfui.dj_camelot.GetDungeonByName(w.id)
                    if d then
                        self:SetDungeon(d, 1)
                    end
                end)
                btn:Show()
            end
        elseif #floors > 1 then
            self.singleFloorLabel:Hide()
            for i, fl in ipairs(floors) do
                local btn = self.floorButtons[i]
                if not btn then
                    btn = CreateFrame("Button", nil, self.toolbar, "BackdropTemplate")
                    btn:SetHeight(20)
                    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    btn.label:SetPoint("CENTER")
                    self.floorButtons[i] = btn
                end
                local text = fl.name and (i .. " · " .. fl.name:lower()) or ("floor " .. i)
                btn.label:SetText(text)
                local bw = math.max(54, math.ceil((btn.label:GetStringWidth() or 40) + 16))
                btn:SetWidth(bw)
                btn:ClearAllPoints()
                btn:SetPoint("LEFT", self.toolbar, "LEFT", xOff, 0)
                xOff = xOff + bw + 4
                local active = (self.floorIndex == i)
                if active then
                    ApplyBackdrop(btn, 0.16, 0.10, 0.26, 1.0, 0.66, 0.40, 1.0, 1.0)
                    btn.label:SetTextColor(1.0, 1.0, 1.0)
                else
                    ApplyBackdrop(btn, 0.07, 0.07, 0.10, 1.0, 0.20, 0.20, 0.25, 1.0)
                    btn.label:SetTextColor(0.65, 0.65, 0.72)
                end
                btn:SetScript("OnClick", function()
                    self:SetFloor(i)
                end)
                btn:Show()
            end
        else
            self.singleFloorLabel:Show()
            self.singleFloorLabel:SetText(self.dungeon and self.dungeon.name:lower() or "dungeon map")
        end
    end

    function ctrl:RenderRouteDrawer()
        local r = self.dungeon and sfui.dj_camelot.routes and sfui.dj_camelot.routes[self.dungeon.id]
        if not r then return end
        self.routeHeader:SetText((r.title or "travel route"):lower())
        self.routeSub:SetText((r.subtitle or (r.faction and (r.faction:lower() .. " route") or "")):lower())
        self.routeWorldMapBtn:SetShown(r.mapRoute ~= nil)

        for _, row in ipairs(self.stepRows) do row:Hide() end
        local cw = math.max(420, (self.routeScroll:GetWidth() or 540) - 12)
        self.routeContent:SetWidth(cw)

        local y = 0
        local stepNum = 0
        for i, step in ipairs(r.steps or {}) do
            local row = self.stepRows[i]
            if not row then
                row = CreateFrame("Frame", nil, self.routeContent, "BackdropTemplate")
                ApplyBackdrop(row, 0.07, 0.07, 0.10, 0.90, 0.16, 0.16, 0.22, 1.0)
                row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -8)
                row.title:SetJustifyH("LEFT")

                row.body = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.body:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -5)
                row.body:SetJustifyH("LEFT")
                row.body:SetWordWrap(true)
                row.body:SetTextColor(0.82, 0.82, 0.88)

                row.btn = CreateFrame("Button", nil, row, "BackdropTemplate")
                row.btn:SetSize(102, 18)
                row.btn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6)
                ApplyBackdrop(row.btn, 0.12, 0.10, 0.20, 1.0, 0.45, 0.32, 0.78, 1.0)
                row.btn.label = row.btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.btn.label:SetPoint("CENTER")
                row.btn.label:SetText("show on map")
                row.btn.label:SetTextColor(0.88, 0.78, 1.0)
                self.stepRows[i] = row
            end

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.routeContent, "TOPLEFT", 0, -y)
            row:SetWidth(cw)

            if step.unnumbered then
                row.title:SetText((step.title or ""):lower())
                row.title:SetTextColor(0.55, 0.82, 1.0)
            else
                stepNum = stepNum + 1
                row.title:SetText(string.format("%d. %s", stepNum, (step.title or ""):lower()))
                row.title:SetTextColor(1.0, 0.82, 0.25)
            end
            row.title:SetWidth(cw - 124)
            row.body:SetWidth(cw - 20)
            row.body:SetText((step.text or ""):lower())

            if step.showRoute and r.mapRoute then
                row.btn:Show()
                row.btn.label:SetText("draw route")
                row.btn:SetScript("OnClick", function()
                    dj_map.ShowRouteOnWorldMap(r.mapRoute)
                end)
            elseif step.map and step.map.mapID then
                row.btn:Show()
                row.btn.label:SetText("show on map")
                row.btn:SetScript("OnClick", function()
                    dj_map.OpenWorldMapSpot(step.map, step.map.label or step.title)
                end)
            else
                row.btn:Hide()
            end

            row:Show()
            local th = math.max(16, row.title:GetStringHeight() or 16)
            local bh = (step.text and step.text ~= "") and math.max(16, row.body:GetStringHeight() or 16) or 0
            local rh = th + (bh > 0 and (bh + 6) or 0) + 18
            row:SetHeight(rh)
            y = y + rh + 6
        end
        self.routeContent:SetHeight(math.max(1, y))
    end

    function ctrl:RenderCanvas()
        for _, p in ipairs(self.entrancePins) do p:Hide() end
        for _, p in ipairs(self.ladderPins) do p:Hide() end
        for _, p in ipairs(self.bossPins) do p:Hide() end
        for _, p in ipairs(self.questPins) do p:Hide() end

        if not self.dungeon then return end
        local m = sfui.dj_camelot and sfui.dj_camelot.maps and sfui.dj_camelot.maps[self.dungeon.id]
        if not m or not m.floors or #m.floors == 0 then return end

        local fIdx = math.max(1, math.min(#m.floors, self.floorIndex or 1))
        self.floorIndex = fIdx
        local fl = m.floors[fIdx]

        if fl.texture then
            self.tileGrid = nil
            for _, t in ipairs(self.mapTiles) do t:Hide() end
            self.mapTex:SetTexture(fl.texture)
            self.mapTex:SetTexCoord(0, fl.texRight or 1, 0, fl.texBottom or 1)
            self.mapTex:Show()
        else
            self.mapTex:Hide()
            local apiLayer, apiTextures
            if fl.uiMapID and C_Map and type(C_Map.GetMapArtLayers) == "function" and type(C_Map.GetMapArtLayerTextures) == "function" then
                local layers = SafePlain(C_Map.GetMapArtLayers(fl.uiMapID))
                if type(layers) == "table" and layers[1] then
                    local textures = SafePlain(C_Map.GetMapArtLayerTextures(fl.uiMapID, 1))
                    if type(textures) == "table" and #textures > 0 then
                        apiLayer, apiTextures = layers[1], textures
                    end
                end
            end
            local layerW = (apiLayer and tonumber(SafePlain(apiLayer.layerWidth))) or 1002
            local layerH = (apiLayer and tonumber(SafePlain(apiLayer.layerHeight))) or 668
            local tileW = (apiLayer and tonumber(SafePlain(apiLayer.tileWidth))) or 256
            local tileH = (apiLayer and tonumber(SafePlain(apiLayer.tileHeight))) or 256
            local cols = math.max(1, math.ceil(layerW / tileW))
            local count = apiTextures and #apiTextures or (fl.tiles and 12 or 0)
            self.tileGrid = count > 0 and { layerW = layerW, layerH = layerH, tileW = tileW, tileH = tileH, cols = cols, count = count } or nil
            for i = 1, math.max(count, #self.mapTiles) do
                local t = self.mapTiles[i]
                if i <= count then
                    if not t then
                        t = self.holder:CreateTexture(nil, "BACKGROUND")
                        self.mapTiles[i] = t
                    end
                    local texSrc = (apiTextures and SafePlain(apiTextures[i])) or (fl.tiles and (fl.tiles .. i))
                    t:SetTexture(texSrc)
                    t:SetTexCoord(0, 1, 0, 1)
                    t:Show()
                elseif t then
                    t:Hide()
                end
            end
        end

        self:ApplyTransform()
        local artW = self.baseW * self.zoom
        local artH = self.baseH * self.zoom

        -- 1. Entrance markers
        local eUsed = 0
        for _, e in ipairs(m.entrances or {}) do
            if (e.floor or 1) == fIdx then
                eUsed = eUsed + 1
                local pin = self.entrancePins[eUsed]
                if not pin then
                    pin = CreateFrame("Button", nil, self.holder)
                    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                    pin.tex = pin:CreateTexture(nil, "OVERLAY")
                    pin.tex:SetAllPoints()
                    pin.tex:SetTexture(ENTRANCE_TEX)
                    self.entrancePins[eUsed] = pin
                end
                local sz = math.max(20, math.floor(self.baseH * 0.055))
                pin:SetSize(sz, sz)
                pin:SetFrameLevel(self.holder:GetFrameLevel() + 8)
                if pin.tex.SetRotation then
                    pin.tex:SetRotation(math.rad(e.angle or 0))
                end
                if e.color then
                    pin.tex:SetVertexColor(e.color[1], e.color[2], e.color[3], 1)
                else
                    pin.tex:SetVertexColor(0.35, 1.0, 0.45, 1)
                end
                pin.normX, pin.normY = e.x, e.y
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", self.holder, "TOPLEFT", e.x * artW, -(e.y * artH))
                pin:SetScript("OnEnter", function(s)
                    GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
                    GameTooltip:SetText((e.label or "entrance"):lower(), 0.35, 1.0, 0.45)
                    if self.dungeon and self.dungeon.entrance then
                        GameTooltip:AddLine("left-click: mark dungeon entrance on world map", 0.65, 0.65, 0.72)
                    end
                    GameTooltip:Show()
                end)
                pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
                pin:SetScript("OnClick", function(_, button)
                    if button == "RightButton" then
                        if self.zoom > 1.001 then
                            self.zoom = 1.0
                            self.panX, self.panY = 0, 0
                            self:ApplyTransform()
                        elseif self.isWorldMapOverlay and self.onRightClickOut then
                            self.onRightClickOut()
                        end
                        return
                    end
                    if self.dungeon and self.dungeon.entrance then
                        dj_map.OpenWorldMapSpot(self.dungeon.entrance, self.dungeon.name .. " entrance")
                    end
                end)
                pin:Show()
            end
        end

        -- 2. Floor transition ladder markers & traversal notes
        local lUsed = 0
        for _, tr in ipairs(m.transitions or {}) do
            local isNote = (tr.note == true)
            local destFloor = (not isNote) and tr.to or nil
            if (tr.floor or 1) == fIdx and (isNote or (destFloor and m.floors[destFloor])) then
                lUsed = lUsed + 1
                local pin = self.ladderPins[lUsed]
                if not pin then
                    pin = CreateFrame("Button", nil, self.holder)
                    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                    pin.tex = pin:CreateTexture(nil, "OVERLAY")
                    pin.tex:SetAllPoints()
                    pin.tex:SetTexture(LADDER_TEX)
                    self.ladderPins[lUsed] = pin
                end
                local sz = math.max(24, math.floor(self.baseH * 0.068))
                pin:SetSize(sz, sz)
                pin:SetFrameLevel(self.holder:GetFrameLevel() + 10)
                pin.normX, pin.normY = tr.x, tr.y
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", self.holder, "TOPLEFT", tr.x * artW, -(tr.y * artH))
                pin:SetScript("OnEnter", function(s)
                    GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
                    if isNote then
                        GameTooltip:SetText((tr.label or "note"):lower(), 0.35, 1.0, 0.45)
                    else
                        local destName = m.floors[destFloor].name
                        local title = tr.label or (destName and ("go to " .. destName:lower()) or ("go to floor " .. destFloor))
                        GameTooltip:SetText(title:lower(), 1.0, 0.82, 0.25)
                        GameTooltip:AddLine("left-click: switch floor", 0.65, 0.65, 0.72)
                    end
                    GameTooltip:Show()
                end)
                pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
                pin:SetScript("OnClick", function(_, button)
                    if button == "RightButton" then
                        if self.zoom > 1.001 then
                            self.zoom = 1.0
                            self.panX, self.panY = 0, 0
                            self:ApplyTransform()
                        elseif self.isWorldMapOverlay and self.onRightClickOut then
                            self.onRightClickOut()
                        end
                        return
                    end
                    if destFloor then
                        GameTooltip:Hide()
                        self:SetFloor(destFloor)
                    end
                end)
                pin:Show()
            end
        end

        -- 3. Boss & quest-target portrait pins
        local bUsed = 0
        local bossScale = GetBossIconScale()
        local pinSize = math.max(22, math.floor(self.baseH * 0.082 * bossScale + 0.5))
        for _, b in ipairs(m.bosses or {}) do
            if (b.floor or 1) == fIdx then
                bUsed = bUsed + 1
                local pin = self.bossPins[bUsed]
                if not pin then
                    pin = CreateFrame("Button", nil, self.holder)
                    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")

                    pin.bg = pin:CreateTexture(nil, "BACKGROUND")
                    pin.bg:SetAllPoints()
                    pin.bg:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
                    pin.bg:SetVertexColor(0.04, 0.04, 0.06, 0.92)

                    pin.portrait = pin:CreateTexture(nil, "ARTWORK")
                    pin.portrait:SetPoint("TOPLEFT", pin, "TOPLEFT", 2, -2)
                    pin.portrait:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -2, 2)

                    pin.wishIcon = pin:CreateTexture(nil, "OVERLAY", nil, 2)
                    pin.wishIcon:SetSize(14, 14)
                    pin.wishIcon:SetPoint("TOPRIGHT", pin, "TOPRIGHT", 3, 3)
                    pin.wishIcon:SetTexture(WISHLIST_TEX)
                    pin.wishIcon:SetTexCoord(0, 1, 0, 1)

                    pin.questBadge = pin:CreateTexture(nil, "OVERLAY", nil, 3)
                    pin.questBadge:SetTexture("Interface\\TargetingFrame\\PortraitQuestBadge")

                    pin.lvlBadge = pin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    pin.lvlBadge:SetPoint("BOTTOM", pin, "BOTTOM", 0, -4)
                    self.bossPins[bUsed] = pin
                end

                pin:SetSize(pinSize, pinSize)
                pin:SetFrameLevel(self.holder:GetFrameLevel() + 18)

                local sfuiBoss = FindSfuiBossData(self.dungeon, b)
                local questEntry = b.quest and FindDungeonQuestEntry(self.dungeon, { id = b.quest }) or nil
                local isQuestMobOnly = (sfuiBoss == nil) and (b.quest ~= nil)

                local dispID = b.displayId or (sfuiBoss and sfuiBoss.displayId) or 0
                if dispID > 0 and type(SetPortraitTextureFromCreatureDisplayID) == "function" then
                    SetPortraitTextureFromCreatureDisplayID(pin.portrait, dispID)
                    pin.portrait:SetTexCoord(0, 1, 0, 1)
                else
                    pin.portrait:SetTexture("Interface\\EncounterJournal\\UI-EJ-Boss-Default")
                end

                if b.quest then
                    local qbSize = math.max(18, math.floor(pinSize * 0.78))
                    pin.questBadge:SetSize(qbSize, qbSize)
                    pin.questBadge:ClearAllPoints()
                    pin.questBadge:SetPoint("CENTER", pin, "TOPRIGHT", -2, -2)
                    if pin.questBadge.SetDesaturated then
                        pin.questBadge:SetDesaturated(IsQuestCompleted(b.quest))
                    end
                    pin.questBadge:Show()
                else
                    pin.questBadge:Hide()
                end

                local wishItems = GetBossWishlistItems(sfuiBoss)
                if wishItems then
                    pin.wishIcon:Show()
                else
                    pin.wishIcon:Hide()
                end

                local lvl = b.level or (sfuiBoss and sfuiBoss.level)
                if lvl and bossScale >= 0.75 then
                    pin.lvlBadge:SetText("|cffffd100" .. tostring(lvl) .. "|r")
                    pin.lvlBadge:Show()
                else
                    pin.lvlBadge:Hide()
                end

                pin.normX, pin.normY = b.x, b.y
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", self.holder, "TOPLEFT", b.x * artW, -(b.y * artH))

                pin:SetScript("OnEnter", function(s)
                    GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
                    GameTooltip:SetText((b.name or "boss"):lower(), 1.0, 0.82, 0.0)
                    if lvl then
                        GameTooltip:AddLine("level " .. tostring(lvl) .. " elite", 0.75, 0.75, 0.82)
                    end
                    if b.quest then
                        local qName = (questEntry and questEntry.name and questEntry.name:lower()) or ("#" .. tostring(b.quest))
                        GameTooltip:AddLine("quest target: " .. qName, 0.55, 0.85, 1.0)
                    end
                    if wishItems then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("wishlisted drops:", 0.66, 0.40, 1.0)
                        for _, itemID in ipairs(wishItems) do
                            local itemName, itemLink = (sfui.common and sfui.common.get_item_info and sfui.common.get_item_info(itemID))
                                or GetItemInfo(itemID)
                            GameTooltip:AddLine("  • " .. (itemLink or (itemName and itemName:lower()) or ("item #" .. itemID)), 1, 1, 1)
                        end
                    end
                    GameTooltip:AddLine(" ")
                    if isQuestMobOnly then
                        GameTooltip:AddLine("left-click: view quest in journal", 0.20, 1.0, 0.20)
                    else
                        GameTooltip:AddLine("left-click: view boss & loot", 0.20, 1.0, 0.20)
                    end
                    GameTooltip:Show()
                end)
                pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
                pin:SetScript("OnClick", function(_, button)
                    if button == "RightButton" then
                        if self.zoom > 1.001 then
                            self.zoom = 1.0
                            self.panX, self.panY = 0, 0
                            self:ApplyTransform()
                        elseif self.isWorldMapOverlay and self.onRightClickOut then
                            self.onRightClickOut()
                        end
                        return
                    end
                    GameTooltip:Hide()
                    if isQuestMobOnly then
                        local qID = (questEntry and questEntry.id) or b.quest
                        if self.isWorldMapOverlay then
                            if sfui.dungeonjournal and sfui.dungeonjournal.SelectQuest then
                                sfui.dungeonjournal.SelectQuest(self.dungeon.id, qID)
                            elseif sfui.dungeonjournal and sfui.dungeonjournal.OpenToDungeon then
                                sfui.dungeonjournal.OpenToDungeon(self.dungeon.id, "quests")
                            end
                            local djFrame = sfui.dungeonjournal and sfui.dungeonjournal.GetFrame and sfui.dungeonjournal.GetFrame()
                            if djFrame then
                                djFrame:SetFrameStrata("FULLSCREEN_DIALOG")
                                if djFrame.Raise then djFrame:Raise() end
                            end
                        elseif sfui.dungeonjournal then
                            sfui.dungeonjournal.SetMode("quests")
                            if qID and sfui.dungeonjournal.FocusQuest then
                                sfui.dungeonjournal.FocusQuest(qID)
                            end
                        end
                        return
                    end
                    local targetBossName = (sfuiBoss and sfuiBoss.name) or b.targetName or b.name
                    if self.isWorldMapOverlay then
                        if sfui.dungeonjournal and sfui.dungeonjournal.OpenToBoss then
                            sfui.dungeonjournal.OpenToBoss(targetBossName, self.dungeon.id)
                        elseif sfui.dungeonjournal and sfui.dungeonjournal.OpenToDungeon then
                            sfui.dungeonjournal.OpenToDungeon(self.dungeon.id, "bosses")
                            if targetBossName and sfui.dungeonjournal.SelectBoss then
                                sfui.dungeonjournal.SelectBoss(targetBossName)
                            end
                        end
                        local djFrame = sfui.dungeonjournal and sfui.dungeonjournal.GetFrame and sfui.dungeonjournal.GetFrame()
                        if djFrame then
                            djFrame:SetFrameStrata("FULLSCREEN_DIALOG")
                            if djFrame.Raise then djFrame:Raise() end
                        end
                    else
                        if sfui.dungeonjournal then
                            sfui.dungeonjournal.SetMode("bosses")
                            if targetBossName and sfui.dungeonjournal.SelectBoss then
                                sfui.dungeonjournal.SelectBoss(targetBossName)
                            end
                        end
                    end
                end)
                pin:Show()
            end
        end

        -- 4. In-dungeon quest & object pins
        if GetShowQuestPins() then
            local qList = sfui.dj_camelot and sfui.dj_camelot.mapQuestPins and sfui.dj_camelot.mapQuestPins[self.dungeon.id] or {}
            local qUsed = 0
            local qSize = math.max(20, math.floor(self.baseH * 0.066))
            for _, qPin in ipairs(qList) do
                if (qPin.floor or 1) == fIdx then
                    local spots = {}
                    local hasStart, hasAvailable, hasLogged = false, false, false
                    local firstQuest, firstLogged = nil, nil
                    for _, spot in ipairs(qPin.spots or {}) do
                        local shown = {}
                        for _, q in ipairs(spot.quests or {}) do
                            shown[#shown + 1] = q
                            firstQuest = firstQuest or q
                            local inLog = IsQuestInLog(q.id)
                            local done = IsQuestCompleted(q.id)
                            for _, act in ipairs(q.acts or {}) do
                                if act == "start" then
                                    hasStart = true
                                    if not inLog and not done then hasAvailable = true end
                                elseif inLog then
                                    hasLogged = true
                                    firstLogged = firstLogged or q
                                end
                            end
                        end
                        if #shown > 0 then
                            spots[#spots + 1] = { name = spot.name, shown = shown }
                        end
                    end
                    if #spots > 0 then
                        qUsed = qUsed + 1
                        local pin = self.questPins[qUsed]
                        if not pin then
                            pin = CreateFrame("Button", nil, self.holder)
                            pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                            pin.icon = pin:CreateTexture(nil, "OVERLAY")
                            pin.icon:SetAllPoints()
                            self.questPins[qUsed] = pin
                        end
                        local isBang = (not hasLogged) and (hasAvailable or hasStart)
                        local isIdle = (not hasLogged) and (not hasAvailable)
                        local targetQ = firstLogged or firstQuest

                        pin:SetSize(qSize, qSize)
                        pin:SetFrameLevel(self.holder:GetFrameLevel() + 15)
                        pin.icon:SetTexture(isBang
                            and "Interface\\GossipFrame\\AvailableQuestIcon"
                            or "Interface\\GossipFrame\\ActiveQuestIcon")
                        if pin.icon.SetDesaturated then
                            pin.icon:SetDesaturated(isIdle)
                        end
                        pin.icon:SetAlpha(isIdle and 0.78 or 1.0)
                        StrokeIcon(pin, pin.icon, qSize)

                        pin.normX, pin.normY = qPin.x, qPin.y
                        pin:ClearAllPoints()
                        pin:SetPoint("CENTER", self.holder, "TOPLEFT", qPin.x * artW, -(qPin.y * artH))

                        pin:SetScript("OnEnter", function(s)
                            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
                            local firstLine = true
                            for sIdx, sp in ipairs(spots) do
                                if sIdx > 1 then GameTooltip:AddLine(" ") end
                                if sp.name and sp.name ~= "" then
                                    if firstLine then
                                        GameTooltip:SetText(sp.name:lower(), 1, 1, 1)
                                        firstLine = false
                                    else
                                        GameTooltip:AddLine(sp.name:lower(), 1, 1, 1)
                                    end
                                end
                                for _, q in ipairs(sp.shown) do
                                    local qTitle = (q.name or "quest"):lower()
                                    if firstLine then
                                        GameTooltip:SetText(qTitle, 1.0, 0.82, 0.0)
                                        firstLine = false
                                    else
                                        GameTooltip:AddLine(qTitle, 1.0, 0.82, 0.0)
                                    end
                                    if q.textKey and QUEST_TEXT_KEYS[q.textKey] then
                                        GameTooltip:AddLine("  • " .. QUEST_TEXT_KEYS[q.textKey], 0.85, 0.85, 0.90, true)
                                    else
                                        for _, act in ipairs(q.acts or {}) do
                                            if act == "loot" and q.itemName then
                                                GameTooltip:AddLine("  • loot: " .. q.itemName:lower(), 0.85, 0.85, 0.90, true)
                                            elseif QUEST_ACT_TEXT[act] then
                                                GameTooltip:AddLine("  • " .. QUEST_ACT_TEXT[act], 0.85, 0.85, 0.90, true)
                                            end
                                        end
                                    end
                                end
                            end
                            GameTooltip:AddLine(" ")
                            GameTooltip:AddLine("left-click: view quest in journal", 0.20, 1.0, 0.20)
                            GameTooltip:Show()
                        end)
                        pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
                        pin:SetScript("OnClick", function(_, button)
                            if button == "RightButton" then
                                if self.zoom > 1.001 then
                                    self.zoom = 1.0
                                    self.panX, self.panY = 0, 0
                                    self:ApplyTransform()
                                elseif self.isWorldMapOverlay and self.onRightClickOut then
                                    self.onRightClickOut()
                                end
                                return
                            end
                            GameTooltip:Hide()
                            local matchedQ = FindDungeonQuestEntry(self.dungeon, targetQ)
                            local qID = (matchedQ and matchedQ.id) or (targetQ and (targetQ.main or targetQ.id))
                            if self.isWorldMapOverlay then
                                if sfui.dungeonjournal and sfui.dungeonjournal.SelectQuest then
                                    sfui.dungeonjournal.SelectQuest(self.dungeon.id, qID)
                                elseif sfui.dungeonjournal and sfui.dungeonjournal.OpenToDungeon then
                                    sfui.dungeonjournal.OpenToDungeon(self.dungeon.id, "quests")
                                end
                                local djFrame = sfui.dungeonjournal and sfui.dungeonjournal.GetFrame and sfui.dungeonjournal.GetFrame()
                                if djFrame then
                                    djFrame:SetFrameStrata("FULLSCREEN_DIALOG")
                                    if djFrame.Raise then pcall(djFrame.Raise, djFrame) end
                                end
                            else
                                if sfui.dungeonjournal then
                                    sfui.dungeonjournal.SetMode("quests")
                                    if qID and sfui.dungeonjournal.FocusQuest then
                                        sfui.dungeonjournal.FocusQuest(qID)
                                    end
                                end
                            end
                        end)
                        pin:Show()
                    end
                end
            end
        end
    end

    function ctrl:SetFloor(floorIdx)
        self.floorIndex = floorIdx or 1
        if self.dungeon and self.dungeon.id then
            GetSavedFloors()[self.dungeon.id] = self.floorIndex
        end
        self.pingFrame:Hide()
        self.pingAG:Stop()
        self:UpdateToolbar()
        self:RenderCanvas()
    end

    function ctrl:RefreshView()
        self:UpdateToolbar()
        if self.showingRoute then
            self.viewport:Hide()
            self.routeDrawer:Show()
            self:RenderRouteDrawer()
        else
            self.routeDrawer:Hide()
            self.viewport:Show()
            self:RenderCanvas()
        end
    end

    function ctrl:SetDungeon(dungeon, forcedFloor)
        local changed = (self.dungeon ~= dungeon)
        self.dungeon = dungeon
        if changed then
            self.zoom = 1.0
            self.panX, self.panY = 0, 0
            self.showingRoute = false
            self.pingFrame:Hide()
            self.pingAG:Stop()
        end
        local m = dungeon and sfui.dj_camelot and sfui.dj_camelot.maps and sfui.dj_camelot.maps[dungeon.id]
        local maxF = (m and m.floors and #m.floors) or 1
        local savedF = dungeon and GetSavedFloors()[dungeon.id]
        self.floorIndex = math.max(1, math.min(maxF, forcedFloor or savedF or 1))
        self:RefreshView()
    end

    function ctrl:FocusSpot(floorIdx, normX, normY)
        self.showingRoute = false
        self:SetFloor(floorIdx or 1)
        if normX and normY then
            local artW = self.baseW * self.zoom
            local artH = self.baseH * self.zoom
            self.pingFrame.normX = normX
            self.pingFrame.normY = normY
            self.pingFrame:ClearAllPoints()
            self.pingFrame:SetPoint("CENTER", self.holder, "TOPLEFT", normX * artW, -(normY * artH))
            self.pingFrame:SetFrameLevel(self.holder:GetFrameLevel() + 28)
            self.pingFrame:Show()
            self.pingAG:Play()
        end
    end

    return ctrl
end

-- ══════════════════════════════════════════════════════════════════════════════
--  2. Dungeon Journal Panel Entry Points
-- ══════════════════════════════════════════════════════════════════════════════

function dj_map.Render(frame, dungeon)
    frame = frame or (sfui.dungeonjournal and sfui.dungeonjournal.GetFrame and sfui.dungeonjournal.GetFrame())
    if not frame or not frame.mapPanel then return end
    if not frame.mapPanel.ctrl then
        frame.mapPanel.ctrl = CreateMapController(frame.mapPanel, false)
    end
    frame.mapPanel.ctrl:SetDungeon(dungeon)
end

function dj_map.FocusBoss(frame, dungeon, bossName)
    frame = frame or (sfui.dungeonjournal and sfui.dungeonjournal.GetFrame and sfui.dungeonjournal.GetFrame())
    if not frame or not dungeon or not bossName then return end
    local spot = dj_map.FindBossMapSpot(dungeon, bossName)
    if not spot then return end
    if sfui.dungeonjournal then
        sfui.dungeonjournal.SetMode("map")
    end
    if frame.mapPanel and frame.mapPanel.ctrl then
        frame.mapPanel.ctrl:SetDungeon(dungeon, spot.floor or 1)
        frame.mapPanel.ctrl:FocusSpot(spot.floor or 1, spot.x, spot.y)
    end
end

function dj_map.FocusQuest(frame, dungeon, questID, questName)
    frame = frame or (sfui.dungeonjournal and sfui.dungeonjournal.GetFrame and sfui.dungeonjournal.GetFrame())
    if not frame or not dungeon then return end
    local spot = dj_map.FindQuestMapSpot(dungeon, questID, questName)
    if not spot then return end
    if sfui.dungeonjournal then
        sfui.dungeonjournal.SetMode("map")
    end
    if frame.mapPanel and frame.mapPanel.ctrl then
        frame.mapPanel.ctrl:SetDungeon(dungeon, spot.floor or 1)
        frame.mapPanel.ctrl:FocusSpot(spot.floor or 1, spot.x, spot.y)
    end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  3. World Map Catmull-Rom Travel Route Overlay
-- ══════════════════════════════════════════════════════════════════════════════

local activeRouteMap = nil
local routeOverlayFrame = nil
local routeLines = {}
local routeShadows = {}
local routeWaypoints = {}
local routeRectCache = {}
local routeAncestorCache = {}
local routeWorldHooked = false

local function MapRectOn(mapID, onMapID)
    if mapID == onMapID then return 0, 1, 0, 1 end
    local key = tostring(mapID) .. ":" .. tostring(onMapID)
    local cached = routeRectCache[key]
    if cached ~= nil then
        if cached == false then return nil end
        return cached[1], cached[2], cached[3], cached[4]
    end
    local res = false
    if C_Map and type(C_Map.GetMapRectOnMap) == "function" then
        local minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(mapID, onMapID)
        minX, maxX, minY, maxY = SafePlain(minX), SafePlain(maxX), SafePlain(minY), SafePlain(maxY)
        if minX and maxX and minY and maxY and maxX > minX and maxY > minY then
            res = { minX, maxX, minY, maxY }
        end
    end
    routeRectCache[key] = res
    if not res then return nil end
    return res[1], res[2], res[3], res[4]
end

local function MapIsAncestorOf(ancestorID, mapID)
    if not ancestorID or not mapID or ancestorID == mapID then return false end
    local key = tostring(ancestorID) .. "<" .. tostring(mapID)
    if routeAncestorCache[key] ~= nil then return routeAncestorCache[key] end
    local found = false
    if C_Map and type(C_Map.GetMapInfo) == "function" then
        local id, guard = mapID, 0
        while id and id ~= 0 and guard < 12 do
            local info = C_Map.GetMapInfo(id)
            if not info then break end
            local parentID = SafePlain(info.parentMapID)
            if parentID == ancestorID then found = true break end
            id = parentID
            guard = guard + 1
        end
    end
    routeAncestorCache[key] = found
    return found
end

local function ProjectRoutePoint(pt, targetMapID, continentID)
    local px, py = tonumber(pt.x), tonumber(pt.y)
    if not pt.mapID or not px or not py then return nil end
    if pt.mapID == targetMapID then return px, py end

    if MapIsAncestorOf(targetMapID, continentID) then
        local aMinX, aMaxX, aMinY, aMaxY = MapRectOn(pt.mapID, continentID)
        local cMinX, cMaxX, cMinY, cMaxY = MapRectOn(continentID, targetMapID)
        if not aMinX or not cMinX then return nil end
        local cx = aMinX + (aMaxX - aMinX) * px
        local cy = aMinY + (aMaxY - aMinY) * py
        return cMinX + (cMaxX - cMinX) * cx, cMinY + (cMaxY - cMinY) * cy
    end

    local aMinX, aMaxX, aMinY, aMaxY = MapRectOn(pt.mapID, continentID)
    local tMinX, tMaxX, tMinY, tMaxY = MapRectOn(targetMapID, continentID)
    if aMinX and tMinX then
        local cx = aMinX + (aMaxX - aMinX) * px
        local cy = aMinY + (aMaxY - aMinY) * py
        return (cx - tMinX) / (tMaxX - tMinX), (cy - tMinY) / (tMaxY - tMinY)
    end

    if C_Map and C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D then
        local vec = CreateVector2D(px, py)
        local contID, worldPos = C_Map.GetWorldPosFromMapPos(pt.mapID, vec)
        if contID and worldPos then
            local _, mapPos = C_Map.GetMapPosFromWorldPos(contID, worldPos, targetMapID)
            if mapPos and mapPos.GetXY then
                local mx, my = mapPos:GetXY()
                return SafePlain(mx), SafePlain(my)
            end
        end
    end
    return nil
end

local function CatmullRomRun(run, out, stepPx)
    local n = #run
    if n == 1 then out[#out + 1] = run[1] return end
    local function P(i)
        if i < 1 then return { x = 2 * run[1].x - run[2].x, y = 2 * run[1].y - run[2].y } end
        if i > n then return { x = 2 * run[n].x - run[n - 1].x, y = 2 * run[n].y - run[n - 1].y } end
        return run[i]
    end
    local function tj(ti, a, b)
        local dx, dy = b.x - a.x, b.y - a.y
        return ti + math.max(math.sqrt(math.sqrt(dx * dx + dy * dy)), 1e-4)
    end
    for i = 1, n - 1 do
        local p0, p1, p2, p3 = P(i - 1), P(i), P(i + 1), P(i + 2)
        local t0 = 0
        local t1 = tj(t0, p0, p1)
        local t2 = tj(t1, p1, p2)
        local t3 = tj(t2, p2, p3)
        local dx, dy = p2.x - p1.x, p2.y - p1.y
        local steps = math.max(1, math.min(20, math.floor(math.sqrt(dx * dx + dy * dy) / stepPx + 0.5)))
        out[#out + 1] = { x = p1.x, y = p1.y }
        for s = 1, steps - 1 do
            local t = t1 + (t2 - t1) * (s / steps)
            local a1x = (t1 - t) / (t1 - t0) * p0.x + (t - t0) / (t1 - t0) * p1.x
            local a1y = (t1 - t) / (t1 - t0) * p0.y + (t - t0) / (t1 - t0) * p1.y
            local a2x = (t2 - t) / (t2 - t1) * p1.x + (t - t1) / (t2 - t1) * p2.x
            local a2y = (t2 - t) / (t2 - t1) * p1.y + (t - t1) / (t2 - t1) * p2.y
            local a3x = (t3 - t) / (t3 - t2) * p2.x + (t - t2) / (t3 - t2) * p3.x
            local a3y = (t3 - t) / (t3 - t2) * p2.y + (t - t2) / (t3 - t2) * p3.y
            local b1x = (t2 - t) / (t2 - t0) * a1x + (t - t0) / (t2 - t0) * a2x
            local b1y = (t2 - t) / (t2 - t0) * a1y + (t - t0) / (t2 - t0) * a2y
            local b2x = (t3 - t) / (t3 - t1) * a2x + (t - t1) / (t3 - t1) * a3x
            local b2y = (t3 - t) / (t3 - t1) * a2y + (t - t1) / (t3 - t1) * a3y
            out[#out + 1] = {
                x = (t2 - t) / (t2 - t1) * b1x + (t - t1) / (t2 - t1) * b2x,
                y = (t2 - t) / (t2 - t1) * b1y + (t - t1) / (t2 - t1) * b2y,
            }
        end
    end
    out[#out + 1] = { x = run[n].x, y = run[n].y }
end

local function ClipSegment(x1, y1, x2, y2, w, h)
    local dx, dy = x2 - x1, y2 - y1
    local t0, t1 = 0, 1
    local p = { -dx, dx, -dy, dy }
    local q = { x1, w - x1, y1, h - y1 }
    for i = 1, 4 do
        if p[i] == 0 then
            if q[i] < 0 then return nil end
        else
            local r = q[i] / p[i]
            if p[i] < 0 then
                if r > t1 then return nil end
                if r > t0 then t0 = r end
            else
                if r < t0 then return nil end
                if r < t1 then t1 = r end
            end
        end
    end
    return x1 + t0 * dx, y1 + t0 * dy, x1 + t1 * dx, y1 + t1 * dy
end

function dj_map.ClearRouteOnWorldMap()
    activeRouteMap = nil
    for _, l in ipairs(routeLines) do l:Hide() end
    for _, l in ipairs(routeShadows) do l:Hide() end
    for _, w in ipairs(routeWaypoints) do w:Hide() end
    if routeOverlayFrame then routeOverlayFrame:Hide() end
end

local function RenderRouteOnWorldMap()
    for _, l in ipairs(routeLines) do l:Hide() end
    for _, l in ipairs(routeShadows) do l:Hide() end
    for _, w in ipairs(routeWaypoints) do w:Hide() end

    if not activeRouteMap or not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    local canvas = (WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas())
        or (WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child)
    local currentMapID = WorldMapFrame.GetMapID and SafePlain(WorldMapFrame:GetMapID())
    if not canvas or not currentMapID then return end

    local width, height = canvas:GetWidth(), canvas:GetHeight()
    if not width or not height or width <= 10 or height <= 10 then return end

    if not routeOverlayFrame then
        routeOverlayFrame = CreateFrame("Frame", nil, canvas)
        routeOverlayFrame:EnableMouse(false)
    elseif routeOverlayFrame:GetParent() ~= canvas then
        routeOverlayFrame:SetParent(canvas)
    end
    routeOverlayFrame:ClearAllPoints()
    routeOverlayFrame:SetAllPoints(canvas)
    routeOverlayFrame:SetFrameStrata("HIGH")
    routeOverlayFrame:SetFrameLevel(math.max((canvas:GetFrameLevel() or 0) + 500, 9995))
    routeOverlayFrame:Show()

    local continentID = activeRouteMap.mapID
    local projected = {}
    for _, pt in ipairs(activeRouteMap.points or {}) do
        local x, y = ProjectRoutePoint(pt, currentMapID, continentID)
        if x and y then
            projected[#projected + 1] = { x = x * width, y = y * height, corner = pt.corner }
        end
    end
    if #projected < 2 then return end

    local smooth = {}
    local run = {}
    for i, p in ipairs(projected) do
        run[#run + 1] = p
        if (p.corner and #run > 1) or i == #projected then
            local seg = {}
            CatmullRomRun(run, seg, 5)
            local startK = (#smooth > 0) and 2 or 1
            for k = startK, #seg do smooth[#smooth + 1] = seg[k] end
            run = { p }
        end
    end

    local used = 0
    for i = 1, #smooth - 1 do
        local a, b = smooth[i], smooth[i + 1]
        local x1, y1, x2, y2 = ClipSegment(a.x, a.y, b.x, b.y, width, height)
        if x1 and ((x2 - x1) ~= 0 or (y2 - y1) ~= 0) then
            used = used + 1
            local sh = routeShadows[used]
            if not sh then
                sh = routeOverlayFrame:CreateLine(nil, "OVERLAY", nil, 5)
                sh:SetColorTexture(0.05, 0.01, 0.01, 0.78)
                sh:SetThickness(6)
                routeShadows[used] = sh
            end
            sh:SetStartPoint("TOPLEFT", routeOverlayFrame, x1, -y1)
            sh:SetEndPoint("TOPLEFT", routeOverlayFrame, x2, -y2)
            sh:Show()

            local ln = routeLines[used]
            if not ln then
                ln = routeOverlayFrame:CreateLine(nil, "OVERLAY", nil, 6)
                ln:SetColorTexture(0.95, 0.12, 0.08, 1.0)
                ln:SetThickness(3)
                routeLines[used] = ln
            end
            ln:SetStartPoint("TOPLEFT", routeOverlayFrame, x1, -y1)
            ln:SetEndPoint("TOPLEFT", routeOverlayFrame, x2, -y2)
            ln:Show()
        end
    end

    -- Waypoint icons along the route (right-click clears the route)
    for i, wp in ipairs(activeRouteMap.waypoints or {}) do
        local wx, wy = ProjectRoutePoint(wp, currentMapID, continentID)
        if wx and wy and wx >= 0 and wx <= 1 and wy >= 0 and wy <= 1 then
            local wf = routeWaypoints[i]
            if not wf then
                wf = CreateFrame("Button", nil, routeOverlayFrame)
                wf:SetSize(22, 22)
                wf:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                wf.icon = wf:CreateTexture(nil, "OVERLAY", nil, 7)
                wf.icon:SetAllPoints()
                wf.icon:SetTexture("Interface\\Minimap\\Tracking\\FlightMaster")
                routeWaypoints[i] = wf
            end
            wf:ClearAllPoints()
            wf:SetPoint("CENTER", routeOverlayFrame, "TOPLEFT", wx * width, -(wy * height))
            wf:SetScript("OnEnter", function(s)
                GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
                local t = WAYPOINT_TITLES[wp.titleKey] or "route waypoint"
                GameTooltip:SetText(t, 1.0, 0.82, 0.0)
                if wp.textKey and WAYPOINT_TEXTS[wp.textKey] then
                    GameTooltip:AddLine(WAYPOINT_TEXTS[wp.textKey], 0.9, 0.9, 0.9, true)
                end
                GameTooltip:AddLine("right-click: clear route overlay", 0.65, 0.65, 0.72)
                GameTooltip:Show()
            end)
            wf:SetScript("OnLeave", function() GameTooltip:Hide() end)
            wf:SetScript("OnClick", function(_, button)
                if button == "RightButton" then
                    GameTooltip:Hide()
                    dj_map.ClearRouteOnWorldMap()
                elseif wp.mapID and wp.mapID ~= currentMapID then
                    GameTooltip:Hide()
                    if InCombatLockdown and InCombatLockdown() then return end
                    if C_Map and type(C_Map.OpenWorldMap) == "function" then
                        C_Map.OpenWorldMap(wp.mapID)
                    elseif WorldMapFrame.SetMapID then
                        WorldMapFrame:SetMapID(wp.mapID)
                    end
                end
            end)
            wf:Show()
        end
    end
end

function dj_map.ShowRouteOnWorldMap(routeMap)
    if not routeMap or not routeMap.mapID or not routeMap.points then return end
    activeRouteMap = routeMap
    if not InCombatLockdown or not InCombatLockdown() then
        if C_Map and type(C_Map.OpenWorldMap) == "function" then
            C_Map.OpenWorldMap(routeMap.mapID)
        elseif WorldMapFrame then
            ShowUIPanel(WorldMapFrame)
            if WorldMapFrame.SetMapID then
                WorldMapFrame:SetMapID(routeMap.mapID)
            end
        end
    end
    RenderRouteOnWorldMap()
    if sfui.common and sfui.common.print then
        sfui.common.print("travel route drawn on world map (right-click a route waypoint to clear).")
    end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  4. World Map (M Key) In-Dungeon Overlay
-- ══════════════════════════════════════════════════════════════════════════════

local wmOverlayHolder = nil
local wmToggleBtn = nil
local wmShowWorld = false
local wmLastInstanceDungeon = nil
local wmAdjustingMap = false

local function EnsureWorldMapOverlay()
    if wmOverlayHolder then return true end
    local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
    if not sc then return false end

    wmOverlayHolder = CreateFrame("Frame", "SfuiWorldMapDungeonOverlay", sc, "BackdropTemplate")
    wmOverlayHolder:SetAllPoints(sc)
    wmOverlayHolder:SetFrameLevel((sc:GetFrameLevel() or 1) + 40)
    ApplyBackdrop(wmOverlayHolder, 0.03, 0.03, 0.05, 0.98, 0.15, 0.15, 0.20, 1.0)
    wmOverlayHolder.ctrl = CreateMapController(wmOverlayHolder, true)
    wmOverlayHolder:Hide()

    wmToggleBtn = CreateFrame("Button", "SfuiWorldMapDungeonToggle", sc, "BackdropTemplate")
    wmToggleBtn:SetSize(104, 20)
    wmToggleBtn:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -8, -5)
    wmToggleBtn:SetFrameLevel(wmOverlayHolder:GetFrameLevel() + 25)
    ApplyBackdrop(wmToggleBtn, 0.12, 0.08, 0.20, 0.96, 0.55, 0.38, 0.90, 1.0)
    wmToggleBtn.label = wmToggleBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wmToggleBtn.label:SetPoint("CENTER")
    wmToggleBtn.label:SetTextColor(0.92, 0.84, 1.0)
    wmToggleBtn:Hide()

    local function ShowWorldMap()
        if InCombatLockdown and InCombatLockdown() then return end
        wmShowWorld = true
        wmOverlayHolder:Hide()
        wmToggleBtn.label:SetText("dungeon map")
        local d = wmOverlayHolder.ctrl.dungeon
        local outMap = (d and d.entrance and d.entrance.mapID) or 1415
        wmAdjustingMap = true
        if C_Map and type(C_Map.OpenWorldMap) == "function" then
            C_Map.OpenWorldMap(outMap)
        elseif WorldMapFrame and WorldMapFrame.SetMapID then
            WorldMapFrame:SetMapID(outMap)
        end
        wmAdjustingMap = false
    end

    local function ShowDungeonMap()
        wmShowWorld = false
        wmToggleBtn.label:SetText("world map")
        wmOverlayHolder:Show()
        local dID, flIdx = sfui.dj_camelot.GetCurrentInstanceDungeon()
        local d = dID and sfui.dj_camelot.GetDungeonByName(dID)
        if d then
            wmOverlayHolder.ctrl:SetDungeon(d, flIdx)
        end
    end

    wmOverlayHolder.ctrl.onRightClickOut = ShowWorldMap

    wmToggleBtn:SetScript("OnClick", function()
        if wmShowWorld then
            ShowDungeonMap()
        else
            ShowWorldMap()
        end
    end)

    return true
end

local function SyncWorldMapOverlay()
    if wmAdjustingMap then return end
    RenderRouteOnWorldMap()

    if not WorldMapFrame or not WorldMapFrame:IsShown() then
        if wmOverlayHolder then wmOverlayHolder:Hide() end
        if wmToggleBtn then wmToggleBtn:Hide() end
        return
    end

    local dID, flIdx = sfui.dj_camelot and sfui.dj_camelot.GetCurrentInstanceDungeon and sfui.dj_camelot.GetCurrentInstanceDungeon()
    local d = dID and sfui.dj_camelot.GetDungeonByName(dID)
    if not d or not dj_map.HasMap(d) then
        wmLastInstanceDungeon = nil
        wmShowWorld = false
        if wmOverlayHolder then wmOverlayHolder:Hide() end
        if wmToggleBtn then wmToggleBtn:Hide() end
        return
    end

    if not EnsureWorldMapOverlay() then return end

    if wmLastInstanceDungeon ~= d.id then
        wmLastInstanceDungeon = d.id
        wmShowWorld = false
    end

    wmToggleBtn:Show()
    if wmShowWorld then
        wmToggleBtn.label:SetText("dungeon map")
        wmOverlayHolder:Hide()
    else
        wmToggleBtn.label:SetText("world map")
        wmOverlayHolder:Show()
        wmOverlayHolder.ctrl:SetDungeon(d, flIdx)
    end
end

function dj_map.InitWorldMapOverlay()
    if routeWorldHooked or not WorldMapFrame then return end
    routeWorldHooked = true

    WorldMapFrame:HookScript("OnShow", function()
        SyncWorldMapOverlay()
    end)
    WorldMapFrame:HookScript("OnHide", function()
        if wmOverlayHolder then wmOverlayHolder:Hide() end
        if wmToggleBtn then wmToggleBtn:Hide() end
    end)
    if type(WorldMapFrame.SetMapID) == "function" then
        hooksecurefunc(WorldMapFrame, "SetMapID", function()
            if WorldMapFrame:IsShown() then
                SyncWorldMapOverlay()
            end
        end)
    end

    if sfui.events then
        local function onWorldMapZoneSync()
            if WorldMapFrame and WorldMapFrame:IsShown() then
                SyncWorldMapOverlay()
            end
        end
        sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", onWorldMapZoneSync)
        sfui.events.RegisterEvent("ZONE_CHANGED", onWorldMapZoneSync)
        sfui.events.RegisterEvent("ZONE_CHANGED_INDOORS", onWorldMapZoneSync)
        sfui.events.RegisterEvent("ZONE_CHANGED_NEW_AREA", onWorldMapZoneSync)
    end
end

if sfui.events then
    sfui.events.RegisterEvent("PLAYER_LOGIN", function()
        dj_map.InitWorldMapOverlay()
    end)
end

if sfui.events and sfui.events.RegisterMessage then
    sfui.events.RegisterMessage("SFUI_DJ_WISHLIST_UPDATED", function()
        local djFrame = sfui.dungeonjournal and sfui.dungeonjournal.GetFrame and sfui.dungeonjournal.GetFrame()
        if djFrame and djFrame.mapPanel and djFrame.mapPanel:IsShown() and djFrame.mapPanel.ctrl then
            djFrame.mapPanel.ctrl:RenderCanvas()
        end
        if wmOverlayHolder and wmOverlayHolder:IsShown() and wmOverlayHolder.ctrl then
            wmOverlayHolder.ctrl:RenderCanvas()
        end
    end)
end
