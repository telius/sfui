local addonName, addon = ...
sfui = sfui or {}
sfui.actionbars = sfui.actionbars or {}
sfui.actionbars.movers = {}

local movers = sfui.actionbars.movers
local _G = _G
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local InCombatLockdown = _G.InCombatLockdown
local math_floor = math.floor
local math_abs = math.abs
local pairs = _G.pairs
local ipairs = _G.ipairs
local tostring = _G.tostring
local type = _G.type

movers.list = {}
sfui.actionbars.moversUnlocked = false

-- ─────────────────────────────────────────────────────────────────────────────
--  Screen Alignment Grid Overlay
-- ─────────────────────────────────────────────────────────────────────────────
local gridOverlay = nil

local function UpdateScreenGrid()
    if not gridOverlay then
        local grid = CreateFrame("Frame", "sfui_ActionBarGrid", UIParent)
        grid:SetAllPoints(UIParent)
        grid:SetFrameStrata("BACKGROUND")
        grid:Hide()
        grid.lines = {}
        gridOverlay = grid
    end

    local uiWidth = UIParent:GetWidth()
    local uiHeight = UIParent:GetHeight()
    if gridOverlay._lastW == uiWidth and gridOverlay._lastH == uiHeight then
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

    -- Vertical lines: center axis, positive X, negative X
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

    -- Horizontal lines: center axis, positive Y, negative Y
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

-- ─────────────────────────────────────────────────────────────────────────────
--  Snapping Algorithm: Snap to Other Bars, Screen Center, and 8px Grid
-- ─────────────────────────────────────────────────────────────────────────────
function movers.SnapAndSavePosition(self, barKey)
    local width = self:GetWidth()
    local height = self:GetHeight()
    local left = self:GetLeft()
    local bottom = self:GetBottom()

    if not left or not bottom or not width or not height then return end

    local uiWidth = UIParent:GetWidth()
    local uiHeight = UIParent:GetHeight()
    local uiCenterX = uiWidth / 2
    local uiCenterY = uiHeight / 2

    local right = left + width
    local top = bottom + height
    local centerX = left + width / 2
    local centerY = bottom + height / 2

    local SNAP_THRESHOLD = 12
    local BAR_GAP = 4 -- standard button spacing gap

    local targetLeft = left
    local targetBottom = bottom
    local snappedX = false
    local snappedY = false
    local bestDiffX = SNAP_THRESHOLD + 1
    local bestDiffY = SNAP_THRESHOLD + 1

    -- 1. Check snapping against all other active movers
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

                -- Horizontal snaps
                local d = math_abs(left - (oRight + BAR_GAP))
                if d < bestDiffX then
                    bestDiffX = d
                    targetLeft = oRight + BAR_GAP
                    snappedX = true
                end

                d = math_abs(left - oRight)
                if d < bestDiffX then
                    bestDiffX = d
                    targetLeft = oRight
                    snappedX = true
                end

                d = math_abs(right - (oLeft - BAR_GAP))
                if d < bestDiffX then
                    bestDiffX = d
                    targetLeft = oLeft - BAR_GAP - width
                    snappedX = true
                end

                d = math_abs(right - oLeft)
                if d < bestDiffX then
                    bestDiffX = d
                    targetLeft = oLeft - width
                    snappedX = true
                end

                d = math_abs(left - oLeft)
                if d < bestDiffX then
                    bestDiffX = d
                    targetLeft = oLeft
                    snappedX = true
                end

                d = math_abs(right - oRight)
                if d < bestDiffX then
                    bestDiffX = d
                    targetLeft = oRight - width
                    snappedX = true
                end

                d = math_abs(centerX - oCenterX)
                if d < bestDiffX then
                    bestDiffX = d
                    targetLeft = oCenterX - width / 2
                    snappedX = true
                end

                -- Vertical snaps
                d = math_abs(bottom - (oTop + BAR_GAP))
                if d < bestDiffY then
                    bestDiffY = d
                    targetBottom = oTop + BAR_GAP
                    snappedY = true
                end

                d = math_abs(bottom - oTop)
                if d < bestDiffY then
                    bestDiffY = d
                    targetBottom = oTop
                    snappedY = true
                end

                d = math_abs(top - (oBottom - BAR_GAP))
                if d < bestDiffY then
                    bestDiffY = d
                    targetBottom = oBottom - BAR_GAP - height
                    snappedY = true
                end

                d = math_abs(top - oBottom)
                if d < bestDiffY then
                    bestDiffY = d
                    targetBottom = oBottom - height
                    snappedY = true
                end

                d = math_abs(bottom - oBottom)
                if d < bestDiffY then
                    bestDiffY = d
                    targetBottom = oBottom
                    snappedY = true
                end

                d = math_abs(top - oTop)
                if d < bestDiffY then
                    bestDiffY = d
                    targetBottom = oTop - height
                    snappedY = true
                end

                d = math_abs(centerY - oCenterY)
                if d < bestDiffY then
                    bestDiffY = d
                    targetBottom = oCenterY - height / 2
                    snappedY = true
                end
            end
        end
    end

    -- 2. Snap to screen center axes if not snapped to another bar
    if not snappedX then
        local d = math_abs(centerX - uiCenterX)
        if d < SNAP_THRESHOLD then
            targetLeft = uiCenterX - width / 2
            snappedX = true
        end
    end

    if not snappedY then
        local d = math_abs(centerY - uiCenterY)
        if d < SNAP_THRESHOLD then
            targetBottom = uiCenterY - height / 2
            snappedY = true
        end
    end

    -- 3. Snap to 8px symmetrical grid if not snapped to another bar or center
    local GRID_STEP = 8
    if not snappedX then
        local offsetFromCenter = (left + width / 2) - uiCenterX
        local gridOffset = math_floor(offsetFromCenter / GRID_STEP + 0.5) * GRID_STEP
        targetLeft = uiCenterX + gridOffset - width / 2
    end

    if not snappedY then
        targetBottom = math_floor(bottom / GRID_STEP + 0.5) * GRID_STEP
    end

    -- Calculate clean coordinates relative to screen BOTTOM
    local finalCenterX = targetLeft + width / 2
    local offsetX = math_floor(finalCenterX - uiCenterX + 0.5)
    local offsetY = math_floor(targetBottom + 0.5)

    self:ClearAllPoints()
    self:SetPoint("BOTTOM", UIParent, "BOTTOM", offsetX, offsetY)

    -- Save to database
    if SfuiDB and SfuiDB.actionbars and SfuiDB.actionbars.bars and SfuiDB.actionbars.bars[barKey] then
        local bCfg = SfuiDB.actionbars.bars[barKey]
        bCfg.point = "BOTTOM"
        bCfg.relPoint = "BOTTOM"
        bCfg.x = offsetX
        bCfg.y = offsetY
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Create Mover for a Bar
-- ─────────────────────────────────────────────────────────────────────────────
function movers.CreateMover(bar, barIndex, barKey)
    if not bar or not barKey then return end

    local moverName = "sfui_ActionBarMover_" .. barKey
    local mover = CreateFrame("Frame", moverName, UIParent, "BackdropTemplate")
    mover:SetClampedToScreen(true)
    mover:SetMovable(true)
    mover:EnableMouse(false)
    mover:RegisterForDrag("LeftButton")
    mover:SetFrameStrata("HIGH")
    mover:SetFrameLevel(50)

    -- Stylish mover overlay with theme accent
    local app = sfui.config and sfui.config.appearance
    local hlCol = (app and app.highlightColor) or { 0.4, 0, 1, 0.4 }
    local borderCol = (app and app.accentColor) or { 0, 1, 1, 1 }
    local moverBg = { hlCol[1], hlCol[2], hlCol[3], 0.5 }
    local moverBorder = { borderCol[1], borderCol[2], borderCol[3], 1 }
    if sfui.common and sfui.common.apply_flat_backdrop then
        sfui.common.apply_flat_backdrop(mover, moverBg, moverBorder)
    else
        mover:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false,
            tileSize = 0,
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        mover:SetBackdropColor(moverBg[1], moverBg[2], moverBg[3], moverBg[4])
        mover:SetBackdropBorderColor(moverBorder[1], moverBorder[2], moverBorder[3], moverBorder[4])
    end

    local label = mover:CreateFontString(nil, "OVERLAY", (sfui.config and sfui.config.font) or "GameFontNormal")
    label:SetPoint("CENTER", mover, "CENTER", 0, 0)
    local title = tostring(barKey)
    if barIndex then
        title = string.format("bar %d", barIndex)
    elseif barKey == "pet" then
        title = "pet bar"
    end
    label:SetText(title)
    label:SetTextColor(1, 1, 1, 1)
    mover.label = label

    -- Drag Handlers with Snapping
    mover:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        self:StartMoving()
    end)

    mover:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        movers.SnapAndSavePosition(self, barKey)
    end)

    -- Initial position from DB or defaults
    local cfg = sfui.actionbars.GetBarConfig(barKey)
    local point = (cfg and cfg.point) or "BOTTOM"
    local relPoint = (cfg and cfg.relPoint) or "BOTTOM"
    local x = (cfg and cfg.x) or 0
    local y = (cfg and cfg.y) or 50

    mover:SetSize(bar:GetSize())
    mover:ClearAllPoints()
    mover:SetPoint(point, UIParent, relPoint, x, y)
    mover:Hide()

    -- Anchor bar to mover
    bar:ClearAllPoints()
    bar:SetPoint("CENTER", mover, "CENTER", 0, 0)

    bar.mover = mover
    movers.list[barKey] = mover

    return mover
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Toggle Movers Unlocked / Locked
-- ─────────────────────────────────────────────────────────────────────────────
function movers.ToggleMovers(forceState)
    if InCombatLockdown() then
        if sfui.common and sfui.common.print then
            sfui.common.print("cannot unlock action bar movers during combat lockdown.")
        end
        return
    end

    if forceState ~= nil then
        sfui.actionbars.moversUnlocked = forceState
    else
        sfui.actionbars.moversUnlocked = not sfui.actionbars.moversUnlocked
    end

    local unlocked = sfui.actionbars.moversUnlocked

    -- Toggle screen alignment grid
    if unlocked then
        local grid = UpdateScreenGrid()
        if grid then grid:Show() end
    else
        if gridOverlay then gridOverlay:Hide() end
    end

    for barKey, mover in pairs(movers.list) do
        local bar = sfui.actionbars.barsByKey and sfui.actionbars.barsByKey[barKey]
        local isEnabled = bar and bar.barConfig and bar.barConfig.enabled

        if unlocked and isEnabled then
            mover:SetSize(bar:GetSize())
            mover:EnableMouse(true)
            mover:Show()
        else
            mover:EnableMouse(false)
            mover:Hide()
        end
    end

    -- Trigger mouseover update to bring bars to 100% alpha while moving
    if sfui.actionbars.mouseover and sfui.actionbars.mouseover.UpdateAllBars then
        sfui.actionbars.mouseover.UpdateAllBars(true)
    end

    if sfui.common and sfui.common.print then
        if unlocked then
            sfui.common.print("action bar movers unlocked with grid & bar snapping. drag to reposition, type /sfui lock to save.")
        else
            sfui.common.print("action bar movers locked.")
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Reset Bar Position to Defaults
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
