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
local math_floor = math.floor
local math_abs = math.abs
local pairs = _G.pairs
local ipairs = _G.ipairs
local tostring = _G.tostring
local type = _G.type
local tinsert = _G.tinsert
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

-- ─────────────────────────────────────────────────────────────────────────────
--  Screen Alignment Grid Overlay
-- ─────────────────────────────────────────────────────────────────────────────
local gridOverlay = nil

local function UpdateScreenGrid()
    if not gridOverlay then
        local grid = CreateFrame("Frame", "sfui_EditModeGrid", UIParent)
        grid:SetAllPoints(UIParent)
        grid:SetFrameStrata("BACKGROUND")
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
        x = math_floor((left + width / 2) - uiCenterX + 0.5)
        y = math_floor(bottom + 0.5)
    end

    return point, point, x, y
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Universal Snapping Algorithm across All Registered Movers & Grid
-- ─────────────────────────────────────────────────────────────────────────────
function movers.SnapAndSavePosition(self, key)
    local width = self:GetWidth()
    local height = self:GetHeight()
    local left = self:GetLeft()
    local bottom = self:GetBottom()

    if not left or not bottom or not width or not height then return end

    local uiWidth = UIParent:GetWidth()
    local uiHeight = UIParent:GetHeight()
    local uiCenterX = uiWidth / 2
    local uiCenterY = uiHeight / 2

    local targetLeft = left
    local targetBottom = bottom

    local reg = movers.registry[key]

    if movers.snappingEnabled then
        local right = left + width
        local top = bottom + height
        local centerX = left + width / 2
        local centerY = bottom + height / 2

        local SNAP_THRESHOLD = 12
        local GAP = 4

        local snappedX = false
        local snappedY = false
        local bestDiffX = SNAP_THRESHOLD + 1
        local bestDiffY = SNAP_THRESHOLD + 1

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

                    -- Horizontal snaps: gap, flush, center
                    local d = math_abs(left - (oRight + GAP))
                    if d < bestDiffX then
                        bestDiffX = d
                        targetLeft = oRight + GAP
                        snappedX = true
                    end

                    d = math_abs(left - oRight)
                    if d < bestDiffX then
                        bestDiffX = d
                        targetLeft = oRight
                        snappedX = true
                    end

                    d = math_abs(right - (oLeft - GAP))
                    if d < bestDiffX then
                        bestDiffX = d
                        targetLeft = oLeft - GAP - width
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

                    -- Vertical snaps: gap, flush, center
                    d = math_abs(bottom - (oTop + GAP))
                    if d < bestDiffY then
                        bestDiffY = d
                        targetBottom = oTop + GAP
                        snappedY = true
                    end

                    d = math_abs(bottom - oTop)
                    if d < bestDiffY then
                        bestDiffY = d
                        targetBottom = oTop
                        snappedY = true
                    end

                    d = math_abs(top - (oBottom - GAP))
                    if d < bestDiffY then
                        bestDiffY = d
                        targetBottom = oBottom - GAP - height
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

        -- 2. Snap to screen center axes if not snapped to another mover
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

        -- 3. Snap to 8px symmetrical grid if not snapped
        local GRID_STEP = 8
        if not snappedX then
            local offsetFromCenter = (left + width / 2) - uiCenterX
            local gridOffset = math_floor(offsetFromCenter / GRID_STEP + 0.5) * GRID_STEP
            targetLeft = uiCenterX + gridOffset - width / 2
        end

        if not snappedY then
            targetBottom = math_floor(bottom / GRID_STEP + 0.5) * GRID_STEP
        end
    end

    local preferredPoint = (reg and reg.preferredPoint) or "BOTTOM"
    local point, relPoint, offsetX, offsetY = CalculateRelativeCoordinates(targetLeft, targetBottom, width, height, preferredPoint)

    self:ClearAllPoints()
    self:SetPoint(point, UIParent, relPoint, offsetX, offsetY)

    -- Save via custom setter if provided
    if reg and reg.setPoint then
        reg.setPoint(point, UIParent, relPoint, offsetX, offsetY, self)
    end

    -- Save to ActionBars database if it's an action bar
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

function movers.Register(frame, opts)
    opts = opts or {}
    local key = opts.key or (frame and frame.GetName and frame:GetName())
    if not key then return end

    movers.registry[key] = opts

    local mover = movers.list[key]
    local isNew = false

    if not mover then
        local moverName = opts.isActionBar and ("sfui_ActionBarMover_" .. key) or ("sfui_Mover_" .. key)
        mover = CreateFrame("Frame", moverName, UIParent, "BackdropTemplate")
        mover:SetClampedToScreen(true)
        mover:SetMovable(true)
        mover:EnableMouse(false)
        mover:RegisterForDrag("LeftButton")
        mover:SetFrameStrata("HIGH")
        mover:SetFrameLevel(50)

        -- Theme accent colors
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

        local font = (sfui.config and sfui.config.font) or "GameFontNormal"
        local label = mover:CreateFontString(nil, "OVERLAY", font)
        label:SetPoint("CENTER", mover, "CENTER", 0, 0)
        label:SetTextColor(1, 1, 1, 1)
        mover.label = label

        -- Drag Handlers
        mover:SetScript("OnDragStart", function(self)
            if InCombatLockdown() then return end
            self:StartMoving()
        end)

        mover:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            movers.SnapAndSavePosition(self, key)
        end)

        -- Right-click on mover resets its position
        mover:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" and not InCombatLockdown() then
                movers.ResetPosition(key)
            end
        end)

        -- Interactive Hover & Tooltips
        mover:SetScript("OnEnter", function(self)
            if sfui.common and sfui.common.apply_flat_backdrop then
                sfui.common.apply_flat_backdrop(self, { 0.5, 0.1, 1.0, 0.65 }, { 1, 1, 1, 1 })
            end
            local tip = sfui.common and sfui.common.get_tooltip and sfui.common.get_tooltip()
            if tip then
                tip:SetOwner(self, "ANCHOR_TOP")
                tip:SetText(self.label:GetText() or key, 1, 1, 1)
                local pt, _, relPt, x, y = self:GetPoint()
                if pt then
                    tip:AddLine(string_format("anchor: %s (%d, %d)", pt:lower(), math_floor(x or 0), math_floor(y or 0)), 0.7, 0.7, 0.8)
                end
                tip:AddLine("|cff55ff55drag|r to reposition", 0.8, 0.8, 0.8)
                tip:AddLine("|cffffaa00right-click|r to reset to default", 0.8, 0.8, 0.8)
                tip:Show()
            end
        end)

        mover:SetScript("OnLeave", function(self)
            local curApp = sfui.config and sfui.config.appearance
            local cBorder = (curApp and curApp.accentColor) or { 0, 1, 1, 1 }
            local cHl = (curApp and curApp.highlightColor) or { 0.4, 0, 1, 0.4 }
            if sfui.common and sfui.common.apply_flat_backdrop then
                sfui.common.apply_flat_backdrop(self, { cHl[1], cHl[2], cHl[3], 0.5 }, { cBorder[1], cBorder[2], cBorder[3], 1 })
            end
            if sfui.common and sfui.common.hide_tooltip then
                sfui.common.hide_tooltip()
            end
        end)

        movers.list[key] = mover
        isNew = true
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
            mover:ClearAllPoints()
            mover:SetPoint(pt, relTo or UIParent, relPt or pt, x or 0, y or 0)
        end
    elseif frame and frame.GetPoint then
        local pt, relTo, relPt, x, y = frame:GetPoint()
        if pt then
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
--  Floating Top Toolbar Dialog (sfui_EditModeDialog)
-- ─────────────────────────────────────────────────────────────────────────────
local editModeDialog = nil

local function GetOrCreateEditModeDialog()
    if editModeDialog then return editModeDialog end

    local dialog = CreateFrame("Frame", "sfui_EditModeDialog", UIParent, "BackdropTemplate")
    dialog:SetSize(520, 48)
    dialog:SetPoint("TOP", UIParent, "TOP", 0, -25)
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetFrameLevel(100)
    dialog:SetClampedToScreen(true)
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", function(self) self:StartMoving() end)
    dialog:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    dialog:Hide()

    -- Register in UISpecialFrames so pressing ESC cleanly locks and closes edit mode
    tinsert(_G.UISpecialFrames, "sfui_EditModeDialog")

    dialog:SetScript("OnHide", function(self)
        if movers.isUnlocked and not movers._isToggling then
            movers.ToggleMovers(false)
        end
    end)

    -- Visual styling with theme accent border
    local app = sfui.config and sfui.config.appearance
    local borderCol = (app and app.accentColor) or { 0.40, 0.00, 1.00, 1 }
    if sfui.common and sfui.common.apply_flat_backdrop then
        sfui.common.apply_flat_backdrop(dialog, { 0.05, 0.05, 0.07, 0.95 }, { borderCol[1], borderCol[2], borderCol[3], 1 })
    end

    -- Title & Subtitle
    local title = dialog:CreateFontString(nil, "OVERLAY", (sfui.config and sfui.config.font) or "GameFontNormal")
    title:SetPoint("LEFT", dialog, "LEFT", 14, 6)
    title:SetText("|cff9966ffsfui|r |cffffffffedit mode|r")

    local sub = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("LEFT", dialog, "LEFT", 14, -8)
    sub:SetText("|cff777777drag to move • esc to lock|r")

    local CreateButton = sfui.common.create_flat_button

    -- Close 'X' Button
    local closeBtn = CreateButton(dialog, "|cffaaaaaax|r", 18, 18, function()
        movers.ToggleMovers(false)
    end)
    closeBtn:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -5, -5)

    -- Lock & Save Button (Prominent right button)
    local lockBtn = CreateButton(dialog, "|cff55ff55lock & save|r", 95, 24, function()
        movers.ToggleMovers(false)
    end)
    lockBtn:SetPoint("RIGHT", dialog, "RIGHT", -26, 0)
    if lockBtn.SetBackdropBorderColor then
        lockBtn:SetBackdropBorderColor(0.2, 0.8, 0.3, 1)
    end

    -- Reset All Button
    local resetBtn = CreateButton(dialog, "reset all", 70, 22, function()
        movers.ResetAllPositions()
    end)
    resetBtn:SetPoint("RIGHT", lockBtn, "LEFT", -8, 0)

    -- Magnet Snap Button
    local snapBtn = CreateButton(dialog, movers.snappingEnabled and "snap: on" or "snap: off", 68, 22, function(self)
        movers.snappingEnabled = not movers.snappingEnabled
        if SfuiDB then SfuiDB.editMode_snap = movers.snappingEnabled end
        self:SetText(movers.snappingEnabled and "snap: on" or "snap: off")
    end)
    snapBtn:SetPoint("RIGHT", resetBtn, "LEFT", -6, 0)

    -- Alignment Grid Button
    local gridBtn = CreateButton(dialog, movers.gridEnabled and "grid: on" or "grid: off", 68, 22, function(self)
        movers.SetGridShown(not movers.gridEnabled)
        self:SetText(movers.gridEnabled and "grid: on" or "grid: off")
    end)
    gridBtn:SetPoint("RIGHT", snapBtn, "LEFT", -6, 0)

    function dialog:UpdateButtons()
        snapBtn:SetText(movers.snappingEnabled and "snap: on" or "snap: off")
        gridBtn:SetText(movers.gridEnabled and "grid: on" or "grid: off")
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
        if SfuiDB and SfuiDB.editMode_snap ~= nil then
            movers.snappingEnabled = SfuiDB.editMode_snap
        end
        if SfuiDB and SfuiDB.editMode_grid ~= nil then
            movers.gridEnabled = SfuiDB.editMode_grid
        end

        -- Toggle alignment grid
        if movers.gridEnabled then
            local grid = UpdateScreenGrid()
            if grid then grid:Show() end
        else
            if gridOverlay then gridOverlay:Hide() end
        end

        -- Show floating toolbar dialog
        if dialog then
            dialog:Show()
            dialog:UpdateButtons()
        end

        -- Activate all registered movers
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
                        mover:ClearAllPoints()
                        mover:SetPoint(pt, relTo or UIParent, relPt or pt, x or 0, y or 0)
                    end
                end

                mover:EnableMouse(true)
                mover:Show()

                if reg and reg.onEnterEditMode then
                    reg.onEnterEditMode(mover, target)
                end
            else
                mover:EnableMouse(false)
                mover:Hide()
            end
        end

        -- Bring action bars to 100% alpha while positioning
        if sfui.actionbars and sfui.actionbars.mouseover and sfui.actionbars.mouseover.UpdateAllBars then
            sfui.actionbars.mouseover.UpdateAllBars(true)
        end

        if sfui.common and sfui.common.print then
            sfui.common.print("sfui edit mode unlocked. drag frames to align, right-click to reset, press esc to lock.")
        end
    else
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

    if sfui.common and sfui.common.print then
        sfui.common.print("all mover positions reset to defaults.")
    end
end
