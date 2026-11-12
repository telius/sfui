local addonName, addon = ...
sfui = sfui or {}
sfui.movers = sfui.movers or {}
sfui.actionbars = sfui.actionbars or {}
sfui.actionbars.movers = sfui.movers

local movers = sfui.movers
local _G = _G
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local InCombatLockdown = _G.InCombatLockdown
local GetCursorPosition = _G.GetCursorPosition
local IsShiftKeyDown = _G.IsShiftKeyDown
local IsControlKeyDown = _G.IsControlKeyDown
local math_floor = math.floor
local math_abs = math.abs
local math_max = math.max
local math_min = math.min
local pairs = _G.pairs
local ipairs = _G.ipairs
local tostring = _G.tostring
local type = _G.type
local string_format = string.format

-- ─────────────────────────────────────────────────────────────────────────────
--  State & Registry
-- ─────────────────────────────────────────────────────────────────────────────
movers.list = {}
movers.registry = {}
movers.isUnlocked = false
sfui.actionbars.moversUnlocked = false
movers.snappingEnabled = true
movers.gridEnabled = true
movers.snapThreshold = 14
movers.anchorGap = 4
movers.selectedKey = nil

local ANCHOR_POINTS = {
    "BOTTOM",
    "TOP",
    "CENTER",
    "LEFT",
    "RIGHT",
    "BOTTOMLEFT",
    "BOTTOMRIGHT",
    "TOPLEFT",
    "TOPRIGHT",
}

local GAP_PRESETS = { 4, 2, 0, 6, 8 }
local SNAP_PRESETS = { 14, 18, 10 }

local editModeDialog = nil
local gridOverlay = nil
local guideOverlay = nil
local activeNeighbors = {}

-- ─────────────────────────────────────────────────────────────────────────────
--  Screen Alignment Grid Overlay
-- ─────────────────────────────────────────────────────────────────────────────
local function UpdateScreenGrid()
    if not gridOverlay then
        local grid = CreateFrame("Frame", "sfui_EditModeGrid", UIParent)
        grid:SetAllPoints(UIParent)
        grid:SetFrameStrata("BACKGROUND")
        grid:EnableMouse(false)
        grid:Hide()
        grid.lines = {}
        gridOverlay = grid
    end

    local uiWidth = UIParent:GetWidth()
    local uiHeight = UIParent:GetHeight()
    if gridOverlay._lastW == uiWidth and gridOverlay._lastH == uiHeight and #gridOverlay.lines > 0 then
        return gridOverlay
    end
    gridOverlay._lastW = uiWidth
    gridOverlay._lastH = uiHeight

    for _, line in ipairs(gridOverlay.lines) do
        line:Hide()
    end
    gridOverlay.lines = {}

    local centerX = math_floor(uiWidth / 2 + 0.5)
    local centerY = math_floor(uiHeight / 2 + 0.5)
    local step = 32

    local function addVLine(posX, isCenter)
        local line = gridOverlay:CreateTexture(nil, "BACKGROUND")
        if isCenter then
            line:SetColorTexture(0, 1, 1, 0.45)
            line:SetSize(2, uiHeight)
        else
            line:SetColorTexture(0.2, 0.6, 1.0, 0.08)
            line:SetSize(1, uiHeight)
        end
        line:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", posX - (isCenter and 1 or 0), 0)
        gridOverlay.lines[#gridOverlay.lines + 1] = line
    end

    local function addHLine(posY, isCenter)
        local line = gridOverlay:CreateTexture(nil, "BACKGROUND")
        if isCenter then
            line:SetColorTexture(0, 1, 1, 0.45)
            line:SetSize(uiWidth, 2)
        else
            line:SetColorTexture(0.2, 0.6, 1.0, 0.08)
            line:SetSize(uiWidth, 1)
        end
        line:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, posY - (isCenter and 1 or 0))
        gridOverlay.lines[#gridOverlay.lines + 1] = line
    end

    addVLine(centerX, true)
    local x = centerX + step
    while x < uiWidth do
        addVLine(x, false)
        x = x + step
    end
    x = centerX - step
    while x > 0 do
        addVLine(x, false)
        x = x - step
    end

    addHLine(centerY, true)
    local y = centerY + step
    while y < uiHeight do
        addHLine(y, false)
        y = y + step
    end
    y = centerY - step
    while y > 0 do
        addHLine(y, false)
        y = y - step
    end

    return gridOverlay
end

function movers.SetGridShown(show)
    movers.gridEnabled = show
    if SfuiDB then SfuiDB.editMode_grid = show end
    if show and movers.isUnlocked then
        local g = UpdateScreenGrid()
        if g then g:Show() end
    else
        if gridOverlay then gridOverlay:Hide() end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Dynamic Snap Guide Lines & Neighbor Highlighting
-- ─────────────────────────────────────────────────────────────────────────────
local function GetOrCreateGuideOverlay()
    if guideOverlay then return guideOverlay end

    local f = CreateFrame("Frame", "sfui_EditModeSnapGuides", UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(80)
    f:EnableMouse(false)
    f:Hide()

    local vLine = f:CreateTexture(nil, "OVERLAY")
    vLine:SetColorTexture(0.0, 1.0, 0.85, 0.85)
    vLine:SetWidth(2)
    vLine:Hide()
    f.vLine = vLine

    local hLine = f:CreateTexture(nil, "OVERLAY")
    hLine:SetColorTexture(0.0, 1.0, 0.85, 0.85)
    hLine:SetHeight(2)
    hLine:Hide()
    f.hLine = hLine

    guideOverlay = f
    return f
end

local function ApplyMoverBackdropStyle(mover, key)
    if not mover then return end
    local app = sfui.config and sfui.config.appearance
    local hlCol = (app and app.highlightColor) or { 0.4, 0, 1, 0.4 }
    local borderCol = (app and app.accentColor) or { 0, 1, 1, 1 }

    local bg = { hlCol[1], hlCol[2], hlCol[3], 0.48 }
    local border = { borderCol[1], borderCol[2], borderCol[3], 0.9 }

    if mover._isDragging or mover._isHovered then
        bg = { 0.55, 0.15, 1.0, 0.68 }
        border = { 1.0, 1.0, 1.0, 1.0 }
    elseif activeNeighbors[mover] then
        bg = { 0.10, 0.65, 0.45, 0.58 }
        border = { 0.20, 1.0, 0.65, 1.0 }
    elseif movers.selectedKey == key then
        bg = { 0.48, 0.12, 0.95, 0.62 }
        border = { 1.0, 0.82, 0.20, 1.0 }
    end

    if sfui.common and sfui.common.apply_flat_backdrop then
        sfui.common.apply_flat_backdrop(mover, bg, border)
    elseif mover.SetBackdropColor then
        mover:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
        mover:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
    end
end

function movers.RefreshMoverVisuals()
    for k, m in pairs(movers.list) do
        if m:IsShown() then
            ApplyMoverBackdropStyle(m, k)
        end
    end
end

local function HideSnapGuides()
    local hadNeighbors = false
    for k in pairs(activeNeighbors) do
        activeNeighbors[k] = nil
        hadNeighbors = true
    end
    if guideOverlay then
        guideOverlay.vLine:Hide()
        guideOverlay.hLine:Hide()
        guideOverlay:Hide()
    end
    if hadNeighbors then
        movers.RefreshMoverVisuals()
    end
end

local function UpdateSnapGuides(snapInfo)
    local f = GetOrCreateGuideOverlay()
    local uiWidth = UIParent:GetWidth()
    local uiHeight = UIParent:GetHeight()

    for k in pairs(activeNeighbors) do
        activeNeighbors[k] = nil
    end

    local anyGuide = false
    if snapInfo then
        if snapInfo.neighborX then activeNeighbors[snapInfo.neighborX] = true end
        if snapInfo.neighborY then activeNeighbors[snapInfo.neighborY] = true end

        if snapInfo.snappedX and snapInfo.guideX then
            f.vLine:ClearAllPoints()
            f.vLine:SetSize(2, uiHeight)
            f.vLine:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", math_floor(snapInfo.guideX + 0.5) - 1, 0)
            f.vLine:Show()
            anyGuide = true
        else
            f.vLine:Hide()
        end

        if snapInfo.snappedY and snapInfo.guideY then
            f.hLine:ClearAllPoints()
            f.hLine:SetSize(uiWidth, 2)
            f.hLine:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, math_floor(snapInfo.guideY + 0.5) - 1)
            f.hLine:Show()
            anyGuide = true
        else
            f.hLine:Hide()
        end
    else
        f.vLine:Hide()
        f.hLine:Hide()
    end

    if anyGuide then
        f:Show()
    else
        f:Hide()
    end

    movers.RefreshMoverVisuals()
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Coordinate Calculations Relative to Screen Anchors
-- ─────────────────────────────────────────────────────────────────────────────
local function CalculateRelativeCoordinates(left, bottom, width, height, anchorPoint)
    local uiWidth = UIParent:GetWidth()
    local uiHeight = UIParent:GetHeight()
    local uiCenterX = uiWidth / 2
    local uiCenterY = uiHeight / 2

    local point = anchorPoint or "BOTTOM"
    local x, y

    if point == "TOPRIGHT" then
        x = math_floor((left + width) - uiWidth + 0.5)
        y = math_floor((bottom + height) - uiHeight + 0.5)
    elseif point == "TOPLEFT" then
        x = math_floor(left + 0.5)
        y = math_floor((bottom + height) - uiHeight + 0.5)
    elseif point == "TOP" then
        x = math_floor((left + width / 2) - uiCenterX + 0.5)
        y = math_floor((bottom + height) - uiHeight + 0.5)
    elseif point == "BOTTOMRIGHT" then
        x = math_floor((left + width) - uiWidth + 0.5)
        y = math_floor(bottom + 0.5)
    elseif point == "BOTTOMLEFT" then
        x = math_floor(left + 0.5)
        y = math_floor(bottom + 0.5)
    elseif point == "LEFT" then
        x = math_floor(left + 0.5)
        y = math_floor((bottom + height / 2) - uiCenterY + 0.5)
    elseif point == "RIGHT" then
        x = math_floor((left + width) - uiWidth + 0.5)
        y = math_floor((bottom + height / 2) - uiCenterY + 0.5)
    elseif point == "CENTER" then
        x = math_floor((left + width / 2) - uiCenterX + 0.5)
        y = math_floor((bottom + height / 2) - uiCenterY + 0.5)
    else -- "BOTTOM" default
        point = "BOTTOM"
        x = math_floor((left + width / 2) - uiCenterX + 0.5)
        y = math_floor(bottom + 0.5)
    end

    return point, point, x, y
end
movers.CalculateRelativeCoordinates = CalculateRelativeCoordinates

local function GetMoverAnchorPoint(key, mover)
    if mover and mover._anchorPoint then
        return mover._anchorPoint
    end
    local reg = key and movers.registry[key]
    if reg and reg.getPoint then
        local pt = reg.getPoint()
        if pt and type(pt) == "string" then
            return pt
        end
    end
    if mover and mover.GetPoint then
        local pt = mover:GetPoint()
        if pt and type(pt) == "string" then
            return pt
        end
    end
    return (reg and reg.preferredPoint) or "BOTTOM"
end

-- ─────────────────────────────────────────────────────────────────────────────
--  14px Magnet Snapping & 4px Anchor Gap Engine
-- ─────────────────────────────────────────────────────────────────────────────
local function ComputeSnappedPosition(self, key, rawLeft, rawBottom, width, height)
    local uiWidth = UIParent:GetWidth()
    local uiHeight = UIParent:GetHeight()
    local uiCenterX = uiWidth / 2
    local uiCenterY = uiHeight / 2

    rawLeft = math_max(0, math_min(rawLeft, uiWidth - width))
    rawBottom = math_max(0, math_min(rawBottom, uiHeight - height))

    local targetLeft = rawLeft
    local targetBottom = rawBottom

    local bypassSnap = IsShiftKeyDown and IsShiftKeyDown()
    if not movers.snappingEnabled or bypassSnap then
        return targetLeft, targetBottom, nil
    end

    local SNAP = movers.snapThreshold or 14
    local GAP = movers.anchorGap or 4
    local DOCK_MAX_DIST = SNAP + GAP + 28
    local ALIGN_MAX_DIST = 300

    local right = rawLeft + width
    local top = rawBottom + height
    local centerX = rawLeft + width / 2
    local centerY = rawBottom + height / 2

    local snappedX = false
    local snappedY = false
    local bestDiffX = SNAP + 0.001
    local bestDiffY = SNAP + 0.001
    local guideX, guideY = nil, nil
    local neighborX, neighborY = nil, nil
    local labelX, labelY = nil, nil

    -- 1. Check snapping against all other active shown movers
    for otherKey, other in pairs(movers.list) do
        if other ~= self and other:IsShown() then
            local oLeft = other:GetLeft()
            local oBottom = other:GetBottom()
            local oWidth = other:GetWidth()
            local oHeight = other:GetHeight()

            if oLeft and oBottom and oWidth and oHeight then
                local oRight = oLeft + oWidth
                local oTop = oBottom + oHeight
                local oCenterX = oLeft + oWidth / 2
                local oCenterY = oBottom + oHeight / 2

                -- Perpendicular span distances (0 when spans overlap)
                local vDist = 0
                if rawBottom > oTop then
                    vDist = rawBottom - oTop
                elseif oBottom > top then
                    vDist = oBottom - top
                end

                local hDist = 0
                if rawLeft > oRight then
                    hDist = rawLeft - oRight
                elseif oLeft > right then
                    hDist = oLeft - right
                end

                -- A. Horizontal Adjacent Edge Docking (4px gap default)
                -- Only dock side-by-side when frames share or nearly share vertical span
                if vDist <= DOCK_MAX_DIST then
                    local d = math_abs(rawLeft - (oRight + GAP))
                    if d < bestDiffX then
                        bestDiffX = d
                        targetLeft = oRight + GAP
                        snappedX = true
                        guideX = oRight + GAP / 2
                        neighborX = other
                        labelX = string_format("%dpx gap", GAP)
                    end

                    d = math_abs(right - (oLeft - GAP))
                    if d < bestDiffX then
                        bestDiffX = d
                        targetLeft = oLeft - GAP - width
                        snappedX = true
                        guideX = oLeft - GAP / 2
                        neighborX = other
                        labelX = string_format("%dpx gap", GAP)
                    end
                end

                -- B. Horizontal Parallel Edge & Center Alignment (0px flush)
                if vDist <= ALIGN_MAX_DIST then
                    local d = math_abs(rawLeft - oLeft)
                    if d < bestDiffX then
                        bestDiffX = d
                        targetLeft = oLeft
                        snappedX = true
                        guideX = oLeft
                        neighborX = other
                        labelX = "align left"
                    end

                    d = math_abs(right - oRight)
                    if d < bestDiffX then
                        bestDiffX = d
                        targetLeft = oRight - width
                        snappedX = true
                        guideX = oRight
                        neighborX = other
                        labelX = "align right"
                    end

                    d = math_abs(centerX - oCenterX)
                    if d < bestDiffX then
                        bestDiffX = d
                        targetLeft = oCenterX - width / 2
                        snappedX = true
                        guideX = oCenterX
                        neighborX = other
                        labelX = "center x"
                    end
                end

                -- C. Vertical Adjacent Edge Docking (4px gap default)
                -- Only stack top-to-bottom when frames share or nearly share horizontal span
                if hDist <= DOCK_MAX_DIST then
                    local d = math_abs(rawBottom - (oTop + GAP))
                    if d < bestDiffY then
                        bestDiffY = d
                        targetBottom = oTop + GAP
                        snappedY = true
                        guideY = oTop + GAP / 2
                        neighborY = other
                        labelY = string_format("%dpx gap", GAP)
                    end

                    d = math_abs(top - (oBottom - GAP))
                    if d < bestDiffY then
                        bestDiffY = d
                        targetBottom = oBottom - GAP - height
                        snappedY = true
                        guideY = oBottom - GAP / 2
                        neighborY = other
                        labelY = string_format("%dpx gap", GAP)
                    end
                end

                -- D. Vertical Parallel Edge & Center Alignment (0px flush)
                if hDist <= ALIGN_MAX_DIST then
                    local d = math_abs(rawBottom - oBottom)
                    if d < bestDiffY then
                        bestDiffY = d
                        targetBottom = oBottom
                        snappedY = true
                        guideY = oBottom
                        neighborY = other
                        labelY = "align bottom"
                    end

                    d = math_abs(top - oTop)
                    if d < bestDiffY then
                        bestDiffY = d
                        targetBottom = oTop - height
                        snappedY = true
                        guideY = oTop
                        neighborY = other
                        labelY = "align top"
                    end

                    d = math_abs(centerY - oCenterY)
                    if d < bestDiffY then
                        bestDiffY = d
                        targetBottom = oCenterY - height / 2
                        snappedY = true
                        guideY = oCenterY
                        neighborY = other
                        labelY = "center y"
                    end
                end
            end
        end
    end

    -- 2. Snap to screen center axes and screen borders (with GAP margin)
    local dCenterX = math_abs(centerX - uiCenterX)
    if dCenterX < bestDiffX then
        bestDiffX = dCenterX
        targetLeft = uiCenterX - width / 2
        snappedX = true
        guideX = uiCenterX
        neighborX = nil
        labelX = "screen center"
    end

    local dLeftEdge = math_abs(rawLeft - GAP)
    if dLeftEdge < bestDiffX then
        bestDiffX = dLeftEdge
        targetLeft = GAP
        snappedX = true
        guideX = GAP
        neighborX = nil
        labelX = "screen edge"
    end

    local dRightEdge = math_abs(right - (uiWidth - GAP))
    if dRightEdge < bestDiffX then
        bestDiffX = dRightEdge
        targetLeft = uiWidth - GAP - width
        snappedX = true
        guideX = uiWidth - GAP
        neighborX = nil
        labelX = "screen edge"
    end

    local dCenterY = math_abs(centerY - uiCenterY)
    if dCenterY < bestDiffY then
        bestDiffY = dCenterY
        targetBottom = uiCenterY - height / 2
        snappedY = true
        guideY = uiCenterY
        neighborY = nil
        labelY = "screen center"
    end

    local dBottomEdge = math_abs(rawBottom - GAP)
    if dBottomEdge < bestDiffY then
        bestDiffY = dBottomEdge
        targetBottom = GAP
        snappedY = true
        guideY = GAP
        neighborY = nil
        labelY = "screen edge"
    end

    local dTopEdge = math_abs(top - (uiHeight - GAP))
    if dTopEdge < bestDiffY then
        bestDiffY = dTopEdge
        targetBottom = uiHeight - GAP - height
        snappedY = true
        guideY = uiHeight - GAP
        neighborY = nil
        labelY = "screen edge"
    end

    targetLeft = math_max(0, math_min(targetLeft, uiWidth - width))
    targetBottom = math_max(0, math_min(targetBottom, uiHeight - height))

    return targetLeft, targetBottom, {
        snappedX = snappedX,
        snappedY = snappedY,
        guideX = guideX,
        guideY = guideY,
        neighborX = neighborX,
        neighborY = neighborY,
        labelX = labelX,
        labelY = labelY,
    }
end

local function SaveMoverPosition(self, key, point, relPoint, offsetX, offsetY)
    local reg = movers.registry[key]
    self._anchorPoint = point
    self._lastSavedPt = point
    self._lastSavedX = offsetX
    self._lastSavedY = offsetY

    if reg and reg.setPoint then
        reg.setPoint(point, UIParent, relPoint, offsetX, offsetY, self)
    end

    if (reg and reg.isActionBar) or (key and (key:match("^bar%d+") or key == "pet" or key == "vehicle")) then
        if SfuiDB and SfuiDB.actionbars and SfuiDB.actionbars.bars then
            SfuiDB.actionbars.bars[key] = SfuiDB.actionbars.bars[key] or {}
            local bCfg = SfuiDB.actionbars.bars[key]
            bCfg.point = point
            bCfg.relPoint = relPoint
            bCfg.x = offsetX
            bCfg.y = offsetY
        end
    end
end

function movers.ApplyLivePosition(self, key, rawLeft, rawBottom, isFinal)
    local width = self:GetWidth()
    local height = self:GetHeight()
    if not rawLeft or not rawBottom or not width or not height then return end

    local reg = movers.registry[key]
    local targetLeft, targetBottom, snapInfo = ComputeSnappedPosition(self, key, rawLeft, rawBottom, width, height)
    self._lastTargetLeft = targetLeft
    self._lastTargetBottom = targetBottom

    local anchorPoint = GetMoverAnchorPoint(key, self)
    local point, relPoint, offsetX, offsetY = CalculateRelativeCoordinates(targetLeft, targetBottom, width, height, anchorPoint)

    self:ClearAllPoints()
    self:SetPoint(point, UIParent, relPoint, offsetX, offsetY)

    local baseTitle = (reg and reg.label) or tostring(key)
    if not isFinal then
        UpdateSnapGuides(snapInfo)
        local snapTag = ""
        if snapInfo and (snapInfo.labelX or snapInfo.labelY) then
            local tagText = snapInfo.labelX or snapInfo.labelY
            if snapInfo.labelX and snapInfo.labelY and snapInfo.labelX ~= snapInfo.labelY then
                tagText = snapInfo.labelX .. " • " .. snapInfo.labelY
            end
            snapTag = " |cff55ff55[" .. tagText .. "]|r"
        end
        self.label:SetText(string_format("%s\n|cff00ffff%d, %d|r%s", baseTitle, offsetX, offsetY, snapTag))
    else
        HideSnapGuides()
        self.label:SetText(baseTitle)
    end

    if isFinal or point ~= self._lastSavedPt or offsetX ~= self._lastSavedX or offsetY ~= self._lastSavedY then
        SaveMoverPosition(self, key, point, relPoint, offsetX, offsetY)
        if editModeDialog and editModeDialog.UpdateInspector then
            editModeDialog:UpdateInspector()
        end
    end
end

function movers.SnapAndSavePosition(self, key)
    local left = self:GetLeft()
    local bottom = self:GetBottom()
    if not left or not bottom then return end
    movers.ApplyLivePosition(self, key, left, bottom, true)
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Selection, Precision Nudging & Anchor Cycling
-- ─────────────────────────────────────────────────────────────────────────────
function movers.SelectMover(key)
    if not key or not movers.list[key] then return end
    movers.selectedKey = key
    movers.RefreshMoverVisuals()
    if editModeDialog and editModeDialog.UpdateInspector then
        editModeDialog:UpdateInspector()
    end
end

function movers.NudgeMover(key, dx, dy)
    if InCombatLockdown() then return end
    key = key or movers.selectedKey
    if not key then return end
    local mover = movers.list[key]
    if not mover or not mover:IsShown() then return end

    local pt, _, relPt, x, y = mover:GetPoint()
    if not pt then
        pt = GetMoverAnchorPoint(key, mover)
        relPt = pt
        x, y = 0, 0
    end

    local newX = math_floor((x or 0) + (dx or 0) + 0.5)
    local newY = math_floor((y or 0) + (dy or 0) + 0.5)

    mover:ClearAllPoints()
    mover:SetPoint(pt, UIParent, relPt or pt, newX, newY)
    SaveMoverPosition(mover, key, pt, relPt or pt, newX, newY)

    if editModeDialog and editModeDialog.UpdateInspector then
        editModeDialog:UpdateInspector()
    end
end

function movers.CycleMoverAnchor(key, reverse)
    if InCombatLockdown() then return end
    key = key or movers.selectedKey
    if not key then return end
    local mover = movers.list[key]
    if not mover or not mover:IsShown() then return end

    local left = mover:GetLeft()
    local bottom = mover:GetBottom()
    local width = mover:GetWidth()
    local height = mover:GetHeight()
    if not left or not bottom or not width or not height then return end

    local curPoint = GetMoverAnchorPoint(key, mover)
    local curIdx = 1
    for i, pt in ipairs(ANCHOR_POINTS) do
        if pt == curPoint then
            curIdx = i
            break
        end
    end

    local nextIdx
    if reverse then
        nextIdx = curIdx - 1
        if nextIdx < 1 then nextIdx = #ANCHOR_POINTS end
    else
        nextIdx = (curIdx % #ANCHOR_POINTS) + 1
    end

    local nextPoint = ANCHOR_POINTS[nextIdx]
    local point, relPoint, offsetX, offsetY = CalculateRelativeCoordinates(left, bottom, width, height, nextPoint)

    mover:ClearAllPoints()
    mover:SetPoint(point, UIParent, relPoint, offsetX, offsetY)
    SaveMoverPosition(mover, key, point, relPoint, offsetX, offsetY)

    if editModeDialog and editModeDialog.UpdateInspector then
        editModeDialog:UpdateInspector()
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Universal Mover Registration & Creation
-- ─────────────────────────────────────────────────────────────────────────────
local function ResolveCustomSize(customSize)
    if not customSize then return nil, nil end
    if type(customSize) == "function" then
        return customSize()
    elseif type(customSize) == "table" then
        return customSize[1] or customSize.width, customSize[2] or customSize.height
    end
end

local function RefreshMoverTooltip(self, key)
    local tip = sfui.common and sfui.common.get_tooltip and sfui.common.get_tooltip()
    if not tip then return end
    local reg = movers.registry[key]
    local baseTitle = (reg and reg.label) or tostring(key)
    tip:SetOwner(self, "ANCHOR_TOP")
    tip:SetText(baseTitle, 1, 1, 1)
    local pt, _, _, x, y = self:GetPoint()
    if pt then
        tip:AddLine(string_format("anchor: %s (%d, %d)", pt:lower(), math_floor((x or 0) + 0.5), math_floor((y or 0) + 0.5)), 0.0, 1.0, 1.0)
    end
    tip:AddLine(string_format("|cff55ff55drag|r to snap (%dpx magnet, %dpx gap)", movers.snapThreshold or 14, movers.anchorGap or 4), 0.8, 0.8, 0.8)
    tip:AddLine("|cff55ff55hold shift|r while dragging for 1px free move", 0.8, 0.8, 0.8)
    tip:AddLine("|cff55ff55scroll wheel|r to nudge 1px (shift: x, ctrl: gap)", 0.8, 0.8, 0.8)
    tip:AddLine("|cffffaa00right-click|r to reset to default", 0.8, 0.8, 0.8)
    tip:Show()
end

function movers.Register(frame, opts)
    opts = opts or {}
    local key = opts.key or (frame and frame.GetName and frame:GetName())
    if not key then return end

    movers.registry[key] = opts

    local mover = movers.list[key]

    if not mover then
        local moverName = opts.isActionBar and ("sfui_ActionBarMover_" .. key) or ("sfui_Mover_" .. key)
        mover = CreateFrame("Frame", moverName, UIParent, "BackdropTemplate")
        mover:SetClampedToScreen(true)
        mover:SetMovable(true)
        mover:EnableMouse(false)
        mover:EnableMouseWheel(true)
        mover:RegisterForDrag("LeftButton")
        mover:SetFrameStrata("HIGH")
        mover:SetFrameLevel(50)

        ApplyMoverBackdropStyle(mover, key)

        local font = (sfui.config and sfui.config.font) or "GameFontNormal"
        local label = mover:CreateFontString(nil, "OVERLAY", font)
        label:SetPoint("CENTER", mover, "CENTER", 0, 0)
        label:SetTextColor(1, 1, 1, 1)
        mover.label = label

        -- Live Cursor-Delta Drag Controller
        mover:SetScript("OnDragStart", function(self)
            if InCombatLockdown() then return end
            movers.SelectMover(key)

            local scale = UIParent:GetEffectiveScale() or 1
            local cx, cy = GetCursorPosition()
            self._dragStartCursorX = cx / scale
            self._dragStartCursorY = cy / scale
            self._dragStartLeft = self:GetLeft() or 0
            self._dragStartBottom = self:GetBottom() or 0
            self._lastTargetLeft = self._dragStartLeft
            self._lastTargetBottom = self._dragStartBottom
            self._isDragging = true
            ApplyMoverBackdropStyle(self, key)

            if sfui.common and sfui.common.hide_tooltip then
                sfui.common.hide_tooltip()
            end

            self:SetScript("OnUpdate", function(m)
                if InCombatLockdown() then
                    m:SetScript("OnUpdate", nil)
                    m._isDragging = false
                    HideSnapGuides()
                    ApplyMoverBackdropStyle(m, key)
                    return
                end
                local s = UIParent:GetEffectiveScale() or 1
                local curX, curY = GetCursorPosition()
                local dx = (curX / s) - (m._dragStartCursorX or 0)
                local dy = (curY / s) - (m._dragStartCursorY or 0)
                local rawLeft = (m._dragStartLeft or 0) + dx
                local rawBottom = (m._dragStartBottom or 0) + dy
                movers.ApplyLivePosition(m, key, rawLeft, rawBottom, false)
            end)
        end)

        mover:SetScript("OnDragStop", function(self)
            self:SetScript("OnUpdate", nil)
            self._isDragging = false
            local finalLeft = self._lastTargetLeft or self:GetLeft()
            local finalBottom = self._lastTargetBottom or self:GetBottom()
            if finalLeft and finalBottom then
                movers.ApplyLivePosition(self, key, finalLeft, finalBottom, true)
            else
                HideSnapGuides()
            end
            ApplyMoverBackdropStyle(self, key)
        end)

        mover:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" and not InCombatLockdown() then
                movers.SelectMover(key)
            end
        end)

        -- Right-click on mover resets its position
        mover:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" and not InCombatLockdown() then
                movers.SelectMover(key)
                movers.ResetPosition(key)
                if self._isHovered then
                    RefreshMoverTooltip(self, key)
                end
            end
        end)

        -- Mousewheel 1px precision nudging (Shift: X axis, Ctrl: anchorGap step)
        mover:SetScript("OnMouseWheel", function(self, delta)
            if InCombatLockdown() then return end
            movers.SelectMover(key)
            local step = (IsControlKeyDown and IsControlKeyDown()) and math_max(1, movers.anchorGap or 4) or 1
            if IsShiftKeyDown and IsShiftKeyDown() then
                movers.NudgeMover(key, delta * step, 0)
            else
                movers.NudgeMover(key, 0, delta * step)
            end
            if self._isHovered then
                RefreshMoverTooltip(self, key)
            end
        end)

        -- Interactive Hover & Tooltips
        mover:SetScript("OnEnter", function(self)
            self._isHovered = true
            ApplyMoverBackdropStyle(self, key)
            if not self._isDragging then
                RefreshMoverTooltip(self, key)
            end
        end)

        mover:SetScript("OnLeave", function(self)
            self._isHovered = false
            ApplyMoverBackdropStyle(self, key)
            if sfui.common and sfui.common.hide_tooltip then
                sfui.common.hide_tooltip()
            end
        end)

        movers.list[key] = mover
    end

    mover.targetFrame = frame

    local title = opts.label or tostring(key)
    mover.label:SetText(title)

    -- Determine initial size
    if opts.customSize then
        local w, h = ResolveCustomSize(opts.customSize)
        if w and h and w > 0 and h > 0 then
            mover:SetSize(w, h)
        end
    elseif frame and frame.GetWidth then
        local w, h = frame:GetWidth(), frame:GetHeight()
        if w and h and w > 0 and h > 0 then
            mover:SetSize(w, h)
        else
            mover:SetSize(120, 36)
        end
    end

    -- Determine initial position
    if opts.getPoint then
        local pt, relTo, relPt, x, y = opts.getPoint()
        if pt then
            mover._anchorPoint = pt
            mover:ClearAllPoints()
            mover:SetPoint(pt, relTo or UIParent, relPt or pt, x or 0, y or 0)
        end
    elseif frame and frame.GetPoint then
        local pt, relTo, relPt, x, y = frame:GetPoint()
        if pt then
            mover._anchorPoint = pt
            mover:ClearAllPoints()
            mover:SetPoint(pt, relTo or UIParent, relPt or pt, x or 0, y or 0)
        end
    end

    mover:Hide()
    return mover
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Action Bar Mover Factory (Backwards Compatibility)
-- ─────────────────────────────────────────────────────────────────────────────
function movers.CreateMover(bar, barIndex, barKey)
    if not bar or not barKey then return end

    local title = tostring(barKey)
    if barIndex then
        title = string_format("bar %d", barIndex)
    elseif barKey == "pet" then
        title = "pet bar"
    elseif barKey == "vehicle" then
        title = "vehicle leave button"
    end

    local mover = movers.Register(bar, {
        key = barKey,
        label = title,
        isActionBar = true,
        barIndex = barIndex,
        preferredPoint = "BOTTOM",
        getPoint = function()
            local cfg = sfui.actionbars.GetBarConfig(barKey)
            local point = (cfg and cfg.point) or "BOTTOM"
            local relPoint = (cfg and cfg.relPoint) or "BOTTOM"
            local x = (cfg and cfg.x) or 0
            local y = (cfg and cfg.y) or 50
            return point, UIParent, relPoint, x, y
        end,
        setPoint = function(point, relTo, relPoint, x, y, m)
            if SfuiDB and SfuiDB.actionbars and SfuiDB.actionbars.bars then
                SfuiDB.actionbars.bars[barKey] = SfuiDB.actionbars.bars[barKey] or {}
                local bCfg = SfuiDB.actionbars.bars[barKey]
                bCfg.point = point
                bCfg.relPoint = relPoint
                bCfg.x = x
                bCfg.y = y
            end
        end,
        resetPosition = function()
            movers.ResetBarPosition(barKey)
        end,
        isEnabled = function()
            local b = sfui.actionbars.barsByKey and sfui.actionbars.barsByKey[barKey]
            return b and b.barConfig and b.barConfig.enabled
        end,
        onEnterEditMode = function(m, b)
            if barKey == "vehicle" then
                b.isInEditMode = true
                b:Show()
                b:SetAlpha(1)
            elseif barKey == "pet" then
                if _G.UnregisterStateDriver then
                    _G.UnregisterStateDriver(b, "visibility")
                end
                b:Show()
                b:SetAlpha(1)
                if b.buttons then
                    for i = 1, 10 do
                        local btn = b.buttons[i]
                        if btn then
                            btn:Show()
                            btn:SetAlpha(1)
                        end
                    end
                end
            end
        end,
        onExitEditMode = function(m, b)
            if barKey == "vehicle" then
                b.isInEditMode = false
                if b.UpdateShownState then
                    b:UpdateShownState()
                elseif b.Update then
                    b:Update()
                end
            elseif barKey == "pet" then
                if b and _G.RegisterStateDriver then
                    _G.RegisterStateDriver(b, "visibility", "[pet,nooverridebar,nopossessbar] show; hide")
                end
            end
        end,
    })

    -- Anchor bar to mover for live synchronized repositioning
    bar:ClearAllPoints()
    bar:SetPoint("CENTER", mover, "CENTER", 0, 0)
    bar.mover = mover

    return mover
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Floating Top Toolbar Dialog & Inspector (sfui_EditModeDialog)
-- ─────────────────────────────────────────────────────────────────────────────
local function GetOrCreateEditModeDialog()
    if editModeDialog then return editModeDialog end

    local dialog = CreateFrame("Frame", "sfui_EditModeDialog", UIParent, "BackdropTemplate")
    dialog:SetSize(580, 104)
    dialog:SetPoint("TOP", UIParent, "TOP", 0, -22)
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetFrameLevel(100)
    dialog:SetClampedToScreen(true)
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", function(self) self:StartMoving() end)
    dialog:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    dialog:Hide()

    if sfui.common and sfui.common.register_special_frame then
        sfui.common.register_special_frame(dialog)
    end

    dialog:SetScript("OnHide", function(self)
        self._resetAllConfirm = nil
        if movers.isUnlocked and not movers._isToggling then
            movers.ToggleMovers(false)
        end
    end)

    local app = sfui.config and sfui.config.appearance
    local borderCol = (app and app.accentColor) or { 0.40, 0.00, 1.00, 1 }
    if sfui.common and sfui.common.apply_flat_backdrop then
        sfui.common.apply_flat_backdrop(dialog, { 0.05, 0.05, 0.07, 0.96 }, { borderCol[1], borderCol[2], borderCol[3], 1 })
    end

    -- ─── Row 1: Global Edit Mode Controls ────────────────────────────────────
    local title = dialog:CreateFontString(nil, "OVERLAY", (sfui.config and sfui.config.font) or "GameFontNormal")
    title:SetPoint("TOPLEFT", dialog, "TOPLEFT", 12, -8)
    title:SetText("|cff9966ffsfui|r |cffffffffedit mode|r")

    local sub = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", dialog, "TOPLEFT", 12, -24)
    sub:SetText("|cff777777shift: free • wheel: 1px|r")

    local CreateButton = sfui.common.create_flat_button

    -- Close 'X' Button
    local closeBtn = CreateButton(dialog, "|cffaaaaaax|r", 20, 22, function()
        movers.ToggleMovers(false)
    end)
    closeBtn:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -8, -10)

    -- Lock & Save Button
    local lockBtn = CreateButton(dialog, "|cff55ff55lock & save|r", 86, 22, function()
        movers.ToggleMovers(false)
    end)
    lockBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    if lockBtn.SetBackdropBorderColor then
        lockBtn:SetBackdropBorderColor(0.2, 0.8, 0.3, 1)
    end

    -- Reset All Button (with 2-click confirmation guard)
    local resetBtn = CreateButton(dialog, "reset all", 68, 22, function(self)
        local now = (_G.GetTime and _G.GetTime()) or 0
        if dialog._resetAllConfirm and (now - dialog._resetAllConfirm) < 3.5 then
            dialog._resetAllConfirm = nil
            self:SetText("reset all")
            movers.ResetAllPositions()
            if dialog.UpdateInspector then dialog:UpdateInspector() end
        else
            dialog._resetAllConfirm = now
            self:SetText("|cffff5555confirm?|r")
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(3.5, function()
                    if dialog._resetAllConfirm and self:IsShown() then
                        dialog._resetAllConfirm = nil
                        self:SetText("reset all")
                    end
                end)
            end
        end
    end)
    resetBtn:SetPoint("RIGHT", lockBtn, "LEFT", -6, 0)
    resetBtn.tooltip = "click twice to reset all frames to default positions"

    -- Anchor Gap Button (4px default; left-click cycles 4/2/0/6/8px, right-click resets to 4px)
    local gapBtn = CreateButton(dialog, string_format("gap: %dpx", movers.anchorGap or 4), 62, 22)
    gapBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    gapBtn:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            movers.anchorGap = 4
        else
            local cur = movers.anchorGap or 4
            local nextVal = 4
            for i, v in ipairs(GAP_PRESETS) do
                if v == cur then
                    nextVal = GAP_PRESETS[(i % #GAP_PRESETS) + 1]
                    break
                end
            end
            movers.anchorGap = nextVal
        end
        if SfuiDB then SfuiDB.editMode_anchorGap = movers.anchorGap end
        self:SetText(string_format("gap: %dpx", movers.anchorGap))
    end)
    gapBtn:SetPoint("RIGHT", resetBtn, "LEFT", -6, 0)
    gapBtn.tooltip = "edge-to-edge anchor gap (left-click: cycle, right-click: 4px default)"

    -- Magnet Snap Button (14px default; left-click toggles on/off, right-click cycles 14/18/10px)
    local snapBtn = CreateButton(dialog, movers.snappingEnabled and string_format("snap: %dpx", movers.snapThreshold or 14) or "snap: off", 74, 22)
    snapBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    snapBtn:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            movers.snappingEnabled = true
            local cur = movers.snapThreshold or 14
            local nextVal = 14
            for i, v in ipairs(SNAP_PRESETS) do
                if v == cur then
                    nextVal = SNAP_PRESETS[(i % #SNAP_PRESETS) + 1]
                    break
                end
            end
            movers.snapThreshold = nextVal
            if SfuiDB then
                SfuiDB.editMode_snap = true
                SfuiDB.editMode_snapThreshold = movers.snapThreshold
            end
        else
            movers.snappingEnabled = not movers.snappingEnabled
            if SfuiDB then SfuiDB.editMode_snap = movers.snappingEnabled end
        end
        self:SetText(movers.snappingEnabled and string_format("snap: %dpx", movers.snapThreshold or 14) or "snap: off")
    end)
    snapBtn:SetPoint("RIGHT", gapBtn, "LEFT", -6, 0)
    snapBtn.tooltip = "magnet snapping (left-click: toggle, right-click: cycle 14px/18px/10px)"

    -- Alignment Grid Button
    local gridBtn = CreateButton(dialog, movers.gridEnabled and "grid: on" or "grid: off", 64, 22, function(self)
        movers.SetGridShown(not movers.gridEnabled)
        self:SetText(movers.gridEnabled and "grid: on" or "grid: off")
    end)
    gridBtn:SetPoint("RIGHT", snapBtn, "LEFT", -6, 0)
    gridBtn.tooltip = "toggle background alignment grid"

    -- ─── Divider Line ────────────────────────────────────────────────────────
    local divider = dialog:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", dialog, "TOPLEFT", 10, -41)
    divider:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -10, -41)
    divider:SetHeight(1)
    divider:SetColorTexture(1, 1, 1, 0.08)

    -- ─── Row 2: Selected Mover Inspector & 1px Nudge Controls ────────────────
    local selText = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    selText:SetPoint("TOPLEFT", dialog, "TOPLEFT", 12, -50)
    selText:SetJustifyH("LEFT")
    selText:SetText("|cff777777click or drag any frame to inspect & nudge|r")

    local selResetBtn = CreateButton(dialog, "reset", 50, 20, function()
        if movers.selectedKey then
            movers.ResetPosition(movers.selectedKey)
            dialog:UpdateInspector()
        end
    end)
    selResetBtn:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -8, -46)
    selResetBtn.tooltip = "reset selected frame to default position"

    local function getNudgeStep()
        if IsShiftKeyDown and IsShiftKeyDown() then
            return math_max(1, movers.anchorGap or 4)
        end
        return 1
    end

    local nudgeRightBtn = CreateButton(dialog, ">", 22, 20, function()
        movers.NudgeMover(movers.selectedKey, getNudgeStep(), 0)
    end)
    nudgeRightBtn:SetPoint("RIGHT", selResetBtn, "LEFT", -6, 0)
    nudgeRightBtn.tooltip = "nudge right 1px (hold shift for gap step)"

    local nudgeDownBtn = CreateButton(dialog, "v", 22, 20, function()
        movers.NudgeMover(movers.selectedKey, 0, -getNudgeStep())
    end)
    nudgeDownBtn:SetPoint("RIGHT", nudgeRightBtn, "LEFT", -3, 0)
    nudgeDownBtn.tooltip = "nudge down 1px (hold shift for gap step)"

    local nudgeUpBtn = CreateButton(dialog, "^", 22, 20, function()
        movers.NudgeMover(movers.selectedKey, 0, getNudgeStep())
    end)
    nudgeUpBtn:SetPoint("RIGHT", nudgeDownBtn, "LEFT", -3, 0)
    nudgeUpBtn.tooltip = "nudge up 1px (hold shift for gap step)"

    local nudgeLeftBtn = CreateButton(dialog, "<", 22, 20, function()
        movers.NudgeMover(movers.selectedKey, -getNudgeStep(), 0)
    end)
    nudgeLeftBtn:SetPoint("RIGHT", nudgeUpBtn, "LEFT", -3, 0)
    nudgeLeftBtn.tooltip = "nudge left 1px (hold shift for gap step)"

    local anchorBtn = CreateButton(dialog, "anchor: bottom", 108, 20)
    anchorBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    anchorBtn:SetScript("OnClick", function(_, button)
        movers.CycleMoverAnchor(movers.selectedKey, button == "RightButton")
    end)
    anchorBtn:SetPoint("RIGHT", nudgeLeftBtn, "LEFT", -6, 0)
    anchorBtn.tooltip = "cycle anchor point without moving frame (left/right click)"

    -- ─── Row 3: Layout Profiles, Import/Export & Multibox Sync ───────────────
    local divider2 = dialog:CreateTexture(nil, "ARTWORK")
    divider2:SetPoint("TOPLEFT", dialog, "TOPLEFT", 10, -72)
    divider2:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -10, -72)
    divider2:SetHeight(1)
    divider2:SetColorTexture(1, 1, 1, 0.08)

    local profBtn = CreateButton(dialog, "profile: default", 156, 20)
    profBtn:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 10, 7)
    profBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    profBtn.tooltip = "left-click: cycle & load saved profile • right-click: overwrite active profile"
    profBtn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            local cur = movers.GetActiveProfile()
            movers.SaveProfile(cur)
            dialog:UpdateButtons()
        else
            local names = movers.GetProfileNames()
            if #names == 0 then
                movers.SaveProfile("default")
                dialog:UpdateButtons()
                return
            end
            local cur = movers.GetActiveProfile()
            local nextIdx = 1
            for i = 1, #names do
                if names[i] == cur then
                    nextIdx = (i % #names) + 1
                    break
                end
            end
            movers.LoadProfile(names[nextIdx])
            dialog:UpdateButtons()
        end
    end)

    local saveAsBtn = CreateButton(dialog, "save as", 62, 20, function()
        movers.OpenProfileStringModal("save")
    end)
    saveAsBtn:SetPoint("LEFT", profBtn, "RIGHT", 6, 0)
    saveAsBtn.tooltip = "save current hud positions under a new profile name"

    local exportBtn = CreateButton(dialog, "export", 58, 20, function()
        movers.OpenProfileStringModal("export")
    end)
    exportBtn:SetPoint("LEFT", saveAsBtn, "RIGHT", 6, 0)
    exportBtn.tooltip = "export active layout profile as a shareable text string"

    local importBtn = CreateButton(dialog, "import", 58, 20, function()
        movers.OpenProfileStringModal("import")
    end)
    importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 6, 0)
    importBtn.tooltip = "import a layout profile string and apply positions"

    local syncLayoutBtn = CreateButton(dialog, "sync layout", 84, 20, function()
        movers.BroadcastLayoutProfile(movers.GetActiveProfile())
    end)
    syncLayoutBtn:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -8, 7)
    syncLayoutBtn.tooltip = "broadcast active layout profile to trusted synced multibox accounts"

    local delProfBtn = CreateButton(dialog, "delete", 54, 20, function()
        local cur = movers.GetActiveProfile()
        if cur and cur ~= "default" then
            movers.DeleteProfile(cur)
            dialog:UpdateButtons()
        elseif sfui.common and sfui.common.print then
            sfui.common.print("cannot delete default profile.")
        end
    end)
    delProfBtn:SetPoint("RIGHT", syncLayoutBtn, "LEFT", -6, 0)
    delProfBtn.tooltip = "delete active non-default layout profile"

    function dialog:UpdateInspector()
        local key = movers.selectedKey
        local mover = key and movers.list[key]
        if mover and mover:IsShown() then
            local reg = movers.registry[key]
            local label = (reg and reg.label) or tostring(key)
            local pt, _, _, x, y = mover:GetPoint()
            pt = pt or GetMoverAnchorPoint(key, mover)
            local ix = math_floor((x or 0) + 0.5)
            local iy = math_floor((y or 0) + 0.5)
            selText:SetText(string_format("|cffffd100%s|r   |cff00ffffx: %d   y: %d|r", label:lower(), ix, iy))
            anchorBtn:SetText(string_format("anchor: %s", pt:lower()))
            anchorBtn:Show()
            nudgeLeftBtn:Show()
            nudgeUpBtn:Show()
            nudgeDownBtn:Show()
            nudgeRightBtn:Show()
            selResetBtn:Show()
        else
            selText:SetText("|cff777777click or drag any frame to inspect & nudge|r")
            anchorBtn:Hide()
            nudgeLeftBtn:Hide()
            nudgeUpBtn:Hide()
            nudgeDownBtn:Hide()
            nudgeRightBtn:Hide()
            selResetBtn:Hide()
        end
    end

    function dialog:UpdateButtons()
        self._resetAllConfirm = nil
        resetBtn:SetText("reset all")
        snapBtn:SetText(movers.snappingEnabled and string_format("snap: %dpx", movers.snapThreshold or 14) or "snap: off")
        gapBtn:SetText(string_format("gap: %dpx", movers.anchorGap or 4))
        gridBtn:SetText(movers.gridEnabled and "grid: on" or "grid: off")
        profBtn:SetText("profile: " .. (movers.GetActiveProfile() or "default"))
        self:UpdateInspector()
    end

    editModeDialog = dialog
    return dialog
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Toggle SFUI Edit Mode (Master Toggle)
-- ─────────────────────────────────────────────────────────────────────────────
function movers.ToggleMovers(forceState)
    if InCombatLockdown() then
        if sfui.common and sfui.common.print then
            sfui.common.print("cannot toggle edit mode during combat lockdown.")
        end
        return
    end

    if movers._isToggling then return end
    movers._isToggling = true

    local newState
    if forceState ~= nil then
        newState = forceState
    else
        newState = not movers.isUnlocked
    end

    movers.isUnlocked = newState
    sfui.actionbars.moversUnlocked = newState

    local dialog = GetOrCreateEditModeDialog()

    if newState then
        -- Read saved settings
        if SfuiDB then
            if SfuiDB.editMode_snap ~= nil then
                movers.snappingEnabled = SfuiDB.editMode_snap
            end
            if SfuiDB.editMode_grid ~= nil then
                movers.gridEnabled = SfuiDB.editMode_grid
            end
            if type(SfuiDB.editMode_snapThreshold) == "number" then
                movers.snapThreshold = SfuiDB.editMode_snapThreshold
            end
            if type(SfuiDB.editMode_anchorGap) == "number" then
                movers.anchorGap = SfuiDB.editMode_anchorGap
            end
        end

        -- Toggle alignment grid
        if movers.gridEnabled then
            local grid = UpdateScreenGrid()
            if grid then grid:Show() end
        else
            if gridOverlay then gridOverlay:Hide() end
        end

        -- Activate all registered movers
        local firstShownKey = nil
        for key, mover in pairs(movers.list) do
            local reg = movers.registry[key]
            local isEnabled = not reg or not reg.isEnabled or reg.isEnabled()
            local target = mover.targetFrame

            if isEnabled then
                if reg and reg.customSize then
                    local w, h = ResolveCustomSize(reg.customSize)
                    if w and h and w > 0 and h > 0 then
                        mover:SetSize(w, h)
                    end
                elseif target and target.GetWidth then
                    local w, h = target:GetWidth(), target:GetHeight()
                    if w and h and w > 0 and h > 0 then
                        mover:SetSize(w, h)
                    end
                end

                if reg and reg.getPoint then
                    local pt, relTo, relPt, x, y = reg.getPoint()
                    if pt then
                        mover._anchorPoint = pt
                        mover._lastSavedPt = pt
                        mover._lastSavedX = x or 0
                        mover._lastSavedY = y or 0
                        mover:ClearAllPoints()
                        mover:SetPoint(pt, relTo or UIParent, relPt or pt, x or 0, y or 0)
                    end
                end

                mover:EnableMouse(true)
                mover:Show()

                if not firstShownKey or key == "healthbar" then
                    firstShownKey = key
                end

                if reg and reg.onEnterEditMode then
                    reg.onEnterEditMode(mover, target)
                end
            else
                mover:EnableMouse(false)
                mover:Hide()
            end
        end

        if not movers.selectedKey or not movers.list[movers.selectedKey] or not movers.list[movers.selectedKey]:IsShown() then
            movers.selectedKey = firstShownKey
        end
        movers.RefreshMoverVisuals()

        -- Show floating toolbar dialog
        if dialog then
            dialog:Show()
            dialog:UpdateButtons()
        end

        -- Bring action bars to 100% alpha while positioning
        if sfui.actionbars and sfui.actionbars.mouseover and sfui.actionbars.mouseover.UpdateAllBars then
            sfui.actionbars.mouseover.UpdateAllBars(true)
        end

        if sfui.common and sfui.common.print then
            sfui.common.print("sfui edit mode unlocked. drag frames to snap (14px magnet, 4px gap), scroll to nudge 1px, press esc to lock.")
        end
    else
        HideSnapGuides()

        -- Hide alignment grid
        if gridOverlay then gridOverlay:Hide() end

        -- Hide dialog
        if dialog and dialog:IsShown() then
            dialog:Hide()
        end

        -- Deactivate all registered movers
        for key, mover in pairs(movers.list) do
            local reg = movers.registry[key]
            local target = mover.targetFrame

            mover:SetScript("OnUpdate", nil)
            mover._isDragging = false
            mover._isHovered = false
            if reg and reg.label then
                mover.label:SetText(reg.label)
            end
            mover:EnableMouse(false)
            mover:Hide()

            if reg and reg.onExitEditMode then
                reg.onExitEditMode(mover, target)
            end
        end

        -- Restore action bars alpha
        if sfui.actionbars and sfui.actionbars.mouseover and sfui.actionbars.mouseover.UpdateAllBars then
            sfui.actionbars.mouseover.UpdateAllBars(false)
        end

        if sfui.common and sfui.common.print then
            sfui.common.print("sfui edit mode locked and positions saved.")
        end
    end

    movers._isToggling = false
end

movers.Toggle = movers.ToggleMovers

-- ─────────────────────────────────────────────────────────────────────────────
--  Reset Positions
-- ─────────────────────────────────────────────────────────────────────────────
function movers.ResetBarPosition(barIndexOrKey)
    if InCombatLockdown() then return end
    local barKey
    if type(barIndexOrKey) == "number" then
        barKey = "bar" .. tostring(barIndexOrKey)
    else
        barKey = tostring(barIndexOrKey)
    end
    local mover = movers.list[barKey]
    local defaultCfg = sfui.config and sfui.config.actionbars and sfui.config.actionbars.bars and sfui.config.actionbars.bars[barKey]

    if mover and defaultCfg then
        local point = defaultCfg.point or "BOTTOM"
        local relPoint = defaultCfg.relPoint or "BOTTOM"
        local x = defaultCfg.x or 0
        local y = defaultCfg.y or 50

        mover._anchorPoint = point
        mover._lastSavedPt = point
        mover._lastSavedX = x
        mover._lastSavedY = y
        mover:ClearAllPoints()
        mover:SetPoint(point, UIParent, relPoint, x, y)

        if SfuiDB and SfuiDB.actionbars and SfuiDB.actionbars.bars and SfuiDB.actionbars.bars[barKey] then
            SfuiDB.actionbars.bars[barKey].point = point
            SfuiDB.actionbars.bars[barKey].relPoint = relPoint
            SfuiDB.actionbars.bars[barKey].x = x
            SfuiDB.actionbars.bars[barKey].y = y
        end
    end
end

function movers.ResetPosition(key)
    if InCombatLockdown() then return end
    local reg = movers.registry[key]
    if reg and reg.resetPosition then
        reg.resetPosition()
        local mover = movers.list[key]
        if mover and reg.getPoint then
            local pt, relTo, relPt, x, y = reg.getPoint()
            if pt then
                mover._anchorPoint = pt
                mover._lastSavedPt = pt
                mover._lastSavedX = x or 0
                mover._lastSavedY = y or 0
                mover:ClearAllPoints()
                mover:SetPoint(pt, relTo or UIParent, relPt or pt, x or 0, y or 0)
            end
        end
        if sfui.common and sfui.common.print then
            sfui.common.print(string_format("reset position for %s.", reg.label or key))
        end
    elseif key and (key:match("^bar%d+") or key == "pet" or key == "vehicle") then
        movers.ResetBarPosition(key)
        if sfui.common and sfui.common.print then
            sfui.common.print(string_format("reset position for %s.", key))
        end
    end
    if editModeDialog and editModeDialog.UpdateInspector then
        editModeDialog:UpdateInspector()
    end
end

function movers.ResetAllPositions()
    if InCombatLockdown() then return end
    for key, reg in pairs(movers.registry) do
        if reg.resetPosition then
            reg.resetPosition()
            local mover = movers.list[key]
            if mover and reg.getPoint then
                local pt, relTo, relPt, x, y = reg.getPoint()
                if pt then
                    mover._anchorPoint = pt
                    mover._lastSavedPt = pt
                    mover._lastSavedX = x or 0
                    mover._lastSavedY = y or 0
                    mover:ClearAllPoints()
                    mover:SetPoint(pt, relTo or UIParent, relPt or pt, x or 0, y or 0)
                end
            end
        end
    end

    -- Reset all action bars
    for i = 1, 10 do
        movers.ResetBarPosition("bar" .. i)
    end
    movers.ResetBarPosition("pet")
    movers.ResetBarPosition("vehicle")

    if editModeDialog and editModeDialog.UpdateInspector then
        editModeDialog:UpdateInspector()
    end

    if sfui.common and sfui.common.print then
        sfui.common.print("all mover positions reset to defaults.")
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Named Layout Profiles, Import/Export Strings & Multibox Layout Broadcast
-- ─────────────────────────────────────────────────────────────────────────────
local function normalizeProfileName(name)
    if type(name) ~= "string" then return "default" end
    local clean = name:match("^%s*(.-)%s*$") or ""
    clean = clean:gsub("[|;:]+", ""):lower()
    if clean == "" then return "default" end
    return clean
end

local function ensureLayoutDB()
    SfuiDB = SfuiDB or {}
    SfuiDB.layoutProfiles = SfuiDB.layoutProfiles or {}
    return SfuiDB.layoutProfiles
end

function movers.GetActiveProfile()
    local p = SfuiDB and SfuiDB.activeLayoutProfile
    if type(p) == "string" and p ~= "" then
        return p:lower()
    end
    return "default"
end

function movers.GetProfileNames()
    local profiles = SfuiDB and SfuiDB.layoutProfiles
    local out = {}
    if type(profiles) == "table" then
        for name in pairs(profiles) do
            if type(name) == "string" and name ~= "" then
                out[#out + 1] = name
            end
        end
    end
    table.sort(out)
    return out
end

function movers.SaveProfile(name, silent)
    local pName = normalizeProfileName(name or movers.GetActiveProfile())
    local profiles = ensureLayoutDB()
    local positions = {}
    local count = 0

    for key, reg in pairs(movers.registry) do
        if reg and reg.getPoint then
            local pt, _, relPt, x, y = reg.getPoint()
            if pt and type(pt) == "string" then
                positions[key] = {
                    point    = pt,
                    relPoint = (type(relPt) == "string" and relPt) or pt,
                    x        = math_floor((tonumber(x) or 0) + 0.5),
                    y        = math_floor((tonumber(y) or 0) + 0.5),
                }
                count = count + 1
            end
        end
    end

    profiles[pName] = {
        updatedAt = (_G.time and _G.time()) or 0,
        positions = positions,
    }
    SfuiDB.activeLayoutProfile = pName

    if not silent and sfui.common and sfui.common.print then
        sfui.common.print(string_format("saved layout profile '%s' (%d frames).", pName, count))
    end
    if editModeDialog and editModeDialog.UpdateButtons then
        editModeDialog:UpdateButtons()
    end
    return pName, count
end

local function applyProfileImmediate(pName, prof, silent)
    local positions = prof and prof.positions
    if type(positions) ~= "table" then return false end

    local applied = 0
    for key, pos in pairs(positions) do
        local reg = movers.registry[key]
        if reg and reg.setPoint and type(pos) == "table" and pos.point then
            local pt = tostring(pos.point)
            local rPt = tostring(pos.relPoint or pt)
            local x = tonumber(pos.x) or 0
            local y = tonumber(pos.y) or 0
            local mover = movers.list[key]
            reg.setPoint(pt, UIParent, rPt, x, y, mover)
            if mover then
                mover._anchorPoint = pt
                mover._lastSavedPt = pt
                mover._lastSavedX = x
                mover._lastSavedY = y
                mover:ClearAllPoints()
                mover:SetPoint(pt, UIParent, rPt, x, y)
            end
            applied = applied + 1
        end
    end

    SfuiDB = SfuiDB or {}
    SfuiDB.activeLayoutProfile = pName

    if sfui.bars and sfui.bars.update_bar_positions then
        sfui.bars.update_bar_positions()
    end
    if editModeDialog and editModeDialog.UpdateButtons then
        editModeDialog:UpdateButtons()
    end
    if not silent and sfui.common and sfui.common.print then
        sfui.common.print(string_format("loaded layout profile '%s' (%d frames applied).", pName, applied))
    end
    return true
end

function movers.LoadProfile(name, silent)
    local pName = normalizeProfileName(name)
    local profiles = SfuiDB and SfuiDB.layoutProfiles
    local prof = profiles and profiles[pName]
    if not prof or type(prof.positions) ~= "table" then
        if not silent and sfui.common and sfui.common.print then
            sfui.common.print(string_format("layout profile '%s' not found.", pName))
        end
        return false
    end

    if sfui.safety and sfui.safety.DeferOutOfCombat then
        sfui.safety.DeferOutOfCombat("movers_load_profile", sfui.safety.OOC_P0, applyProfileImmediate, pName, prof, silent)
        return true
    end
    if InCombatLockdown() then
        if not silent and sfui.common and sfui.common.print then
            sfui.common.print("cannot load layout profile during combat lockdown.")
        end
        return false
    end
    return applyProfileImmediate(pName, prof, silent)
end

function movers.DeleteProfile(name)
    local pName = normalizeProfileName(name)
    local profiles = SfuiDB and SfuiDB.layoutProfiles
    if not profiles or not profiles[pName] then return false end
    profiles[pName] = nil
    if SfuiDB.activeLayoutProfile == pName then
        SfuiDB.activeLayoutProfile = "default"
    end
    if sfui.common and sfui.common.print then
        sfui.common.print(string_format("deleted layout profile '%s'.", pName))
    end
    if editModeDialog and editModeDialog.UpdateButtons then
        editModeDialog:UpdateButtons()
    end
    return true
end

function movers.ExportProfileString(name)
    local pName = normalizeProfileName(name or movers.GetActiveProfile())
    local profiles = ensureLayoutDB()
    if not profiles[pName] then
        movers.SaveProfile(pName, true)
    end
    local prof = profiles[pName]
    if not prof or type(prof.positions) ~= "table" then return "" end

    local keys = {}
    for k in pairs(prof.positions) do
        keys[#keys + 1] = k
    end
    table.sort(keys)

    local parts = {}
    for i = 1, #keys do
        local k = keys[i]
        local p = prof.positions[k]
        if p and p.point then
            parts[#parts + 1] = string_format("%s:%s,%s,%d,%d",
                tostring(k),
                tostring(p.point),
                tostring(p.relPoint or p.point),
                math_floor((tonumber(p.x) or 0) + 0.5),
                math_floor((tonumber(p.y) or 0) + 0.5)
            )
        end
    end

    return "sfui1:" .. pName .. "|" .. table.concat(parts, ";")
end

function movers.ImportProfileString(rawStr, overrideName, autoLoad, silent)
    if type(rawStr) ~= "string" then return false end
    local trimmed = rawStr:match("^%s*(.-)%s*$") or ""
    local embeddedName, body = trimmed:match("^sfui1:([^|]+)|(.*)$")
    if not embeddedName or not body then
        if not silent and sfui.common and sfui.common.print then
            sfui.common.print("invalid layout string (expected sfui1:... format).")
        end
        return false
    end

    local targetName = normalizeProfileName((overrideName and overrideName ~= "" and overrideName) or embeddedName)
    local positions = {}
    local count = 0

    for token in body:gmatch("[^;]+") do
        local key, pt, rPt, xs, ys = token:match("^([^:]+):([^,]+),([^,]+),([%-?%d]+),([%-?%d]+)$")
        if key and pt then
            positions[key] = {
                point    = pt,
                relPoint = rPt or pt,
                x        = tonumber(xs) or 0,
                y        = tonumber(ys) or 0,
            }
            count = count + 1
        end
    end

    if count == 0 then
        if not silent and sfui.common and sfui.common.print then
            sfui.common.print("layout string contained no valid frame positions.")
        end
        return false
    end

    local profiles = ensureLayoutDB()
    profiles[targetName] = {
        updatedAt = (_G.time and _G.time()) or 0,
        positions = positions,
    }

    if not silent and sfui.common and sfui.common.print then
        sfui.common.print(string_format("imported layout profile '%s' (%d frames).", targetName, count))
    end

    if autoLoad ~= false then
        movers.LoadProfile(targetName, silent)
    elseif editModeDialog and editModeDialog.UpdateButtons then
        editModeDialog:UpdateButtons()
    end
    return true, targetName, count
end

function movers.BroadcastLayoutProfile(name)
    if not (sfui.sync and sfui.sync.Broadcast) then
        if sfui.common and sfui.common.print then
            sfui.common.print("sync module unavailable.")
        end
        return false
    end
    local pName = normalizeProfileName(name or movers.GetActiveProfile())
    movers.SaveProfile(pName, true)
    local payload = movers.ExportProfileString(pName)
    if payload == "" then return false end
    sfui.sync.Broadcast("DATA_LAYOUT_PROFILE", { name = pName, payload = payload }, true, false)
    if sfui.common and sfui.common.print then
        sfui.common.print(string_format("broadcasted layout profile '%s' to synced peers.", pName))
    end
    return true
end

local profileModal = nil
function movers.OpenProfileStringModal(mode)
    if not profileModal then
        local m = CreateFrame("Frame", "sfui_LayoutProfileModal", UIParent, "BackdropTemplate")
        m:SetSize(440, 138)
        m:SetPoint("TOP", UIParent, "TOP", 0, -134)
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:SetFrameLevel(120)
        m:EnableMouse(true)
        m:SetMovable(true)
        m:RegisterForDrag("LeftButton")
        m:SetScript("OnDragStart", function(self) self:StartMoving() end)
        m:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        if sfui.common and sfui.common.register_special_frame then
            sfui.common.register_special_frame(m)
        end

        local app = sfui.config and sfui.config.appearance
        local borderCol = (app and app.accentColor) or { 0.40, 0.00, 1.00, 1 }
        if sfui.common and sfui.common.apply_flat_backdrop then
            sfui.common.apply_flat_backdrop(m, { 0.05, 0.05, 0.07, 0.98 }, { borderCol[1], borderCol[2], borderCol[3], 1 })
        end

        m.title = m:CreateFontString(nil, "OVERLAY", (sfui.config and sfui.config.font) or "GameFontNormal")
        m.title:SetPoint("TOPLEFT", m, "TOPLEFT", 12, -10)
        m.title:SetText("layout profile")

        m.hint = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        m.hint:SetPoint("TOPLEFT", m, "TOPLEFT", 12, -28)
        m.hint:SetText("|cff888888enter profile name or string|r")

        local ebBg = CreateFrame("Frame", nil, m, "BackdropTemplate")
        ebBg:SetPoint("TOPLEFT", m, "TOPLEFT", 12, -48)
        ebBg:SetPoint("TOPRIGHT", m, "TOPRIGHT", -12, -48)
        ebBg:SetHeight(34)
        if sfui.common and sfui.common.apply_flat_backdrop then
            sfui.common.apply_flat_backdrop(ebBg, { 0.02, 0.02, 0.03, 0.95 }, { 0.25, 0.25, 0.30, 1 })
        end

        local eb = CreateFrame("EditBox", nil, ebBg)
        eb:SetPoint("TOPLEFT", ebBg, "TOPLEFT", 8, -6)
        eb:SetPoint("BOTTOMRIGHT", ebBg, "BOTTOMRIGHT", -8, 6)
        eb:SetFontObject("ChatFontNormal")
        eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function() m:Hide() end)
        m.editBox = eb

        local CreateButton = sfui.common.create_flat_button
        local cancelBtn = CreateButton(m, "close", 68, 22, function() m:Hide() end)
        cancelBtn:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", -12, 10)

        local actionBtn = CreateButton(m, "apply", 88, 22, function()
            local txt = m.editBox:GetText() or ""
            if m._mode == "save" then
                movers.SaveProfile(txt)
                m:Hide()
            elseif m._mode == "import" then
                if movers.ImportProfileString(txt, nil, true, false) then
                    m:Hide()
                end
            else
                m:Hide()
            end
        end)
        actionBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -8, 0)
        m.actionBtn = actionBtn

        eb:SetScript("OnEnterPressed", function()
            actionBtn:Click()
        end)

        profileModal = m
    end

    profileModal._mode = mode or "export"
    if profileModal._mode == "save" then
        profileModal.title:SetText("|cff9966ffsave layout profile|r")
        profileModal.hint:SetText("|cff888888enter a lowercase profile name (e.g. raid, mplus, leveling)|r")
        profileModal.editBox:SetText(movers.GetActiveProfile())
        profileModal.actionBtn:SetText("save")
        profileModal.actionBtn:Show()
    elseif profileModal._mode == "import" then
        profileModal.title:SetText("|cff9966ffimport layout string|r")
        profileModal.hint:SetText("|cff888888paste an sfui1:... layout string below and press enter|r")
        profileModal.editBox:SetText("")
        profileModal.actionBtn:SetText("import")
        profileModal.actionBtn:Show()
    else
        local cur = movers.GetActiveProfile()
        local exported = movers.ExportProfileString(cur)
        profileModal.title:SetText("|cff9966ffexport layout string|r")
        profileModal.hint:SetText("|cff888888press ctrl+c to copy layout profile '" .. cur .. "'|r")
        profileModal.editBox:SetText(exported)
        profileModal.actionBtn:SetText("done")
        profileModal.actionBtn:Show()
    end

    profileModal:Show()
    profileModal.editBox:SetFocus()
    profileModal.editBox:HighlightText()
end
