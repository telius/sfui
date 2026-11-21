local addonName, addon = ...
sfui = sfui or {}
sfui.experience = sfui.experience or {}
sfui.experience.base = {}

local base = sfui.experience.base

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/experience/bar_base.lua
--  Shared StatusBar Creation, Tick Marks, Mover Overlay, Theme & Text Helpers
-- ══════════════════════════════════════════════════════════════════════════════

local _G = _G
local CreateFrame = _G.CreateFrame
local math_floor = math.floor
local string_format = string.format
local unpack = _G.unpack or table.unpack
local type = _G.type
local tostring = _G.tostring
local ipairs = ipairs

local function get_drag_target(container, dragMovesExpBar)
    if dragMovesExpBar then
        local expBar = sfui.experience.bar and sfui.experience.bar.GetFrame and sfui.experience.bar.GetFrame()
        if expBar and expBar:IsShown() and expBar:GetAlpha() > 0 then
            return expBar
        end
    end
    return container
end

local function save_bar_position(targetFrame)
    if not targetFrame or not targetFrame.GetPoint then return end
    local point, _, relPoint, x, y = targetFrame:GetPoint()
    if point and sfui.db and sfui.db.Set then
        sfui.db.Set("experience", "pos", {
            point = point,
            relativePoint = relPoint,
            x = math_floor((x or 0) + 0.5),
            y = math_floor((y or 0) + 0.5),
        })
    end
end

--- Create a standardized experience/reputation/pet/challenge bar bundle.
--- @param opts table
--- @return table barObj
function base.CreateTrackedBar(opts)
    opts = opts or {}
    local frameLevel = opts.frameLevel or 20
    local numSubBars = opts.numSubBars or 1
    local hasTicks = opts.hasTicks ~= false
    local textInset = opts.textInset or 8
    local styleKey = opts.styleKey or "xp"

    local container = CreateFrame("Button", opts.globalName, opts.parent or _G.UIParent, "BackdropTemplate")
    if opts.startHidden then
        container:Hide()
    end
    container:SetFrameStrata("HIGH")
    container:SetFrameLevel(frameLevel)
    container:SetClampedToScreen(true)
    container:EnableMouse(true)
    if opts.movable ~= false then
        container:SetMovable(true)
    end
    if type(opts.clicks) == "table" then
        container:RegisterForClicks(unpack(opts.clicks))
    elseif opts.clicks then
        container:RegisterForClicks(opts.clicks)
    else
        container:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end

    local subBars = {}
    for i = 1, numSubBars do
        local sb = CreateFrame("StatusBar", nil, container)
        sb:SetFrameLevel(frameLevel + i)
        sb:SetPoint("TOPLEFT", container, "TOPLEFT", 1, -1)
        sb:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -1, 1)
        sb:EnableMouse(false)
        subBars[i] = sb
    end

    local nextLevel = frameLevel + numSubBars + 1
    local tickFrame = nil
    if hasTicks then
        tickFrame = CreateFrame("Frame", nil, container)
        tickFrame:SetFrameLevel(nextLevel)
        tickFrame:EnableMouse(false)
        nextLevel = nextLevel + 1
    end

    local textFrame = CreateFrame("Frame", nil, container)
    textFrame:SetFrameLevel(nextLevel)
    textFrame:SetAllPoints(container)
    textFrame:EnableMouse(false)

    local fontObj = (sfui.config and sfui.config.font) or "GameFontHighlightSmall"

    local textLeft = textFrame:CreateFontString(nil, "OVERLAY", fontObj)
    textLeft:SetPoint("LEFT", textFrame, "LEFT", textInset, 0)
    textLeft:SetJustifyH("LEFT")
    textLeft:SetTextColor(opts.leftR or 0.92, opts.leftG or 0.92, opts.leftB or 0.92, 1.0)
    textLeft:SetShadowOffset(1, -1)
    textLeft:SetShadowColor(0, 0, 0, 1)

    local textCenter = textFrame:CreateFontString(nil, "OVERLAY", fontObj)
    textCenter:SetPoint("CENTER", textFrame, "CENTER", 0, 0)
    textCenter:SetJustifyH("CENTER")
    textCenter:SetTextColor(1.0, 1.0, 1.0, 1.0)
    textCenter:SetShadowOffset(1, -1)
    textCenter:SetShadowColor(0, 0, 0, 1)

    local textRight = textFrame:CreateFontString(nil, "OVERLAY", fontObj)
    textRight:SetPoint("RIGHT", textFrame, "RIGHT", -textInset, 0)
    textRight:SetJustifyH("RIGHT")
    textRight:SetTextColor(0.85, 0.85, 0.85, 1.0)
    textRight:SetShadowOffset(1, -1)
    textRight:SetShadowColor(0, 0, 0, 1)

    if opts.registerTheme ~= false and sfui.theme and sfui.theme.RegisterBar then
        sfui.theme.RegisterBar(container, styleKey)
    end

    return {
        container  = container,
        subBars    = subBars,
        mainBar    = subBars[numSubBars],
        tickFrame  = tickFrame,
        ticks      = {},
        textFrame  = textFrame,
        textLeft   = textLeft,
        textCenter = textCenter,
        textRight  = textRight,
        styleKey   = styleKey,
    }
end

--- Apply bar texture to every sub-bar on a tracked bar bundle.
--- @param barObj table|nil
--- @param tex string|nil
function base.SetBarTexture(barObj, tex)
    if not barObj or not barObj.subBars then return end
    local resolvedTex = sfui.common.get_bar_texture(tex)
    for _, sb in ipairs(barObj.subBars) do
        if sb and sb.SetStatusBarTexture then
            sb:SetStatusBarTexture(resolvedTex)
        end
    end
end

--- Re-anchor every sub-bar cleanly inside container (1px border inset).
--- @param barObj table|nil
function base.AnchorSubBars(barObj)
    if not barObj or not barObj.container or not barObj.subBars then return end
    local container = barObj.container
    for _, sb in ipairs(barObj.subBars) do
        sb:ClearAllPoints()
        sb:SetPoint("TOPLEFT", container, "TOPLEFT", 1, -1)
        sb:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -1, 1)
    end
end

--- Apply theme backdrop & status bar textures to a tracked bar bundle.
--- @param barObj table|nil
--- @param styleKey string|nil
function base.ApplyTheme(barObj, styleKey)
    if not barObj or not barObj.container then return end
    local container = barObj.container
    local key = styleKey or barObj.styleKey or "xp"
    if sfui.theme and sfui.theme.ApplyStatusBarStyle then
        sfui.theme.ApplyStatusBarStyle(container, key)
    else
        container:SetBackdrop(sfui.widgets.FLAT_BACKDROP)
        container:SetBackdropColor(0.04, 0.04, 0.04, 0.85)
        container:SetBackdropBorderColor(0.0, 0.0, 0.0, 1.0)
    end
    base.SetBarTexture(barObj)
end

--- Update or hide segment tick marks across a tracked bar.
--- @param barObj table|nil
--- @param innerWidth number
--- @param _innerHeight number|nil
function base.UpdateTicks(barObj, innerWidth, _innerHeight)
    local tickFrame = barObj and barObj.tickFrame
    if not tickFrame then return end

    local cfg = (sfui.config and sfui.config.experience) or {}
    local showTicks = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "showTicks", cfg.showTicks == true))
    if showTicks == nil then showTicks = false end

    if not showTicks or not innerWidth or innerWidth <= 0 then
        tickFrame:Hide()
        return
    end

    local container = barObj.container
    local ticks = barObj.ticks
    tickFrame:Show()
    tickFrame:ClearAllPoints()
    tickFrame:SetPoint("TOPLEFT", container, "TOPLEFT", 1, -1)
    tickFrame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -1, 1)

    local numSegments = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "tickCount", 20)) or 20
    local numDividers = numSegments - 1

    for i = 1, numDividers do
        local tick = ticks[i]
        if not tick then
            tick = tickFrame:CreateTexture(nil, "OVERLAY")
            tick:SetTexture("Interface\\Buttons\\WHITE8X8")
            tick:SetVertexColor(0, 0, 0, 0.45)
            ticks[i] = tick
        end

        local xPos = (innerWidth / numSegments) * i
        tick:ClearAllPoints()
        tick:SetPoint("TOPLEFT", tickFrame, "TOPLEFT", xPos - 0.5, 0)
        tick:SetPoint("BOTTOMLEFT", tickFrame, "BOTTOMLEFT", xPos - 0.5, 0)
        tick:SetWidth(1)
        tick:Show()
    end

    for i = numDividers + 1, #ticks do
        ticks[i]:Hide()
    end
end

--- Update left/center/right text visibility alpha based on hover/mode setting.
--- @param barObj table|nil
--- @param isHovering boolean
--- @param hideCenter boolean|nil
function base.UpdateTextVisibility(barObj, isHovering, hideCenter)
    if not barObj then return end
    local textLeft, textCenter, textRight = barObj.textLeft, barObj.textCenter, barObj.textRight
    if not textLeft or not textCenter or not textRight then return end
    local data = sfui.experience.data
    local alpha = (data and data.GetTextAlpha and data.GetTextAlpha(isHovering)) or (isHovering and 1.0 or 0.0)
    textLeft:SetAlpha(alpha)
    textCenter:SetAlpha(hideCenter and 0 or alpha)
    textRight:SetAlpha(alpha)
end

--- Format center bar progress text consistently across XP, Rep, and Challenges.
--- @param formatMode string|nil
--- @param cur number
--- @param max number
--- @param pct number
--- @param suffix string|nil
--- @param remaining number|nil
--- @return string
function base.FormatProgressText(formatMode, cur, max, pct, suffix, remaining)
    local formatNumber = (sfui.experience.data and sfui.experience.data.FormatNumber) or tostring
    local curStr = formatNumber(cur or 0)
    local maxStr = formatNumber(max or 0)
    local rem = remaining
    if rem == nil then
        rem = (max or 0) - (cur or 0)
        if rem < 0 then rem = 0 end
    end
    local remStr = formatNumber(rem)
    local tail = suffix or ""
    local p = pct or 0

    if formatMode == "PERCENT_CURRENT" or formatMode == nil then
        return string_format("%s / %s (%.1f%%)%s", curStr, maxStr, p, tail)
    elseif formatMode == "PERCENT" then
        return string_format("%.1f%%%s", p, tail)
    elseif formatMode == "REMAINING" then
        return string_format("-%s (%.1f%%)%s", remStr, p, tail)
    end
    return string_format("%s / %s%s", curStr, maxStr, tail)
end

--- Attach standard unlocked drag handlers onto a bar container.
--- @param barObj table
--- @param dragMovesExpBar boolean|nil
function base.AttachDragHandlers(barObj, dragMovesExpBar)
    local container = barObj and barObj.container
    if not container then return end
    container:RegisterForDrag("LeftButton")
    container:SetScript("OnDragStart", function(self)
        if self._isUnlocked then
            get_drag_target(self, dragMovesExpBar):StartMoving()
        end
    end)
    container:SetScript("OnDragStop", function(self)
        if self._isUnlocked then
            local target = get_drag_target(self, dragMovesExpBar)
            target:StopMovingOrSizing()
            save_bar_position(target)
        end
    end)
end

--- Toggle mover unlock overlay on a tracked bar.
--- @param barObj table|nil
--- @param unlocked boolean
--- @param opts table|nil
function base.SetUnlocked(barObj, unlocked, opts)
    local container = barObj and barObj.container
    if not container then return end
    opts = opts or {}
    container._isUnlocked = unlocked

    if unlocked then
        local overlay = barObj.unlockOverlay
        if not overlay then
            overlay = CreateFrame("Frame", nil, container, "BackdropTemplate")
            overlay:SetAllPoints(container)
            overlay:SetFrameLevel(container:GetFrameLevel() + 30)
            overlay:EnableMouse(true)
            overlay:RegisterForDrag("LeftButton")

            local bgCol = opts.bgColor or { 0.0, 0.6, 0.9, 0.45 }
            local bg = overlay:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(bgCol[1], bgCol[2], bgCol[3], bgCol[4] or 0.45)
            overlay.bg = bg

            if sfui.widgets and sfui.widgets.create_border then
                sfui.widgets.create_border(overlay, 1, opts.borderColor or { 0.2, 0.8, 1, 1 })
            end

            local lbl = overlay:CreateFontString(nil, "OVERLAY", (sfui.config and sfui.config.font_small) or "GameFontNormalSmall")
            lbl:SetPoint("CENTER", overlay, "CENTER", 0, 0)
            lbl:SetText(opts.label or "|cff00ffffexperience bar|r |cffaaaaaa(drag to move)|r")
            overlay.lbl = lbl

            local dragMovesExp = opts.dragMovesExpBar
            overlay:SetScript("OnDragStart", function()
                get_drag_target(container, dragMovesExp):StartMoving()
            end)
            overlay:SetScript("OnDragStop", function()
                local target = get_drag_target(container, dragMovesExp)
                target:StopMovingOrSizing()
                save_bar_position(target)
            end)
            barObj.unlockOverlay = overlay
        end
        container:Show()
        container:SetAlpha(1.0)
        overlay:Show()
    else
        if barObj.unlockOverlay then
            barObj.unlockOverlay:Hide()
        end
        if opts.onLockUpdate then
            opts.onLockUpdate()
        end
    end
end
