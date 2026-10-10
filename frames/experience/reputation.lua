local addonName, addon = ...
sfui = sfui or {}
sfui.experience = sfui.experience or {}
sfui.experience.reputation = {}

local repModule = sfui.experience.reputation

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/experience/reputation.lua
--  Dedicated stacked reputation & renown status bar
--  Docks above/below the experience bar while leveling, solo bar at max level
-- ══════════════════════════════════════════════════════════════════════════════

local _G = _G
local CreateFrame = _G.CreateFrame
local math_floor = math.floor
local string_format = string.format
local IsShiftKeyDown = _G.IsShiftKeyDown
local InCombatLockdown = _G.InCombatLockdown

local repContainer = nil
local repBar = nil
local tickFrame = nil
local ticks = {}
local textLeft = nil
local textCenter = nil
local textRight = nil

--- Get the active status bar texture
--- @return string
local function GetBarTexture()
    if sfui.widgets and sfui.widgets.get_bar_texture then
        local tex = sfui.widgets.get_bar_texture()
        if tex then return tex end
    end
    return (sfui.config and sfui.config.barTexture) or "Interface/Buttons/WHITE8X8"
end

--- Set status bar texture directly
--- @param tex string|nil
function repModule.SetBarTexture(tex)
    tex = tex or GetBarTexture()
    if sfui.widgets and sfui.widgets.resolve_statusbar_texture then
        tex = sfui.widgets.resolve_statusbar_texture(tex)
    end
    if repBar then repBar:SetStatusBarTexture(tex) end
end

--- Get reputation container frame
--- @return Frame|nil
function repModule.GetFrame()
    return repContainer
end

--- Apply theme styling to the reputation bar
function repModule.ApplyTheme()
    if not repContainer then return end

    if sfui.theme and sfui.theme.ApplyStatusBarStyle then
        sfui.theme.ApplyStatusBarStyle(repContainer, "xp")
    else
        repContainer:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets   = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        repContainer:SetBackdropColor(0.04, 0.04, 0.04, 0.85)
        repContainer:SetBackdropBorderColor(0.0, 0.0, 0.0, 1.0)
    end

    local tex = GetBarTexture()
    repModule.SetBarTexture(tex)
end

--- Update 20-segment tick marks
--- @param innerWidth number
--- @param innerHeight number
local function UpdateTicks(innerWidth, innerHeight)
    if not tickFrame then return end

    local cfg = sfui.config.experience or {}
    local showTicks = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "showTicks", cfg.showTicks ~= false))
    if showTicks == nil then showTicks = true end

    if not showTicks or innerWidth <= 0 then
        tickFrame:Hide()
        return
    end

    tickFrame:Show()
    tickFrame:ClearAllPoints()
    tickFrame:SetPoint("TOPLEFT", repContainer, "TOPLEFT", 1, -1)
    tickFrame:SetPoint("BOTTOMRIGHT", repContainer, "BOTTOMRIGHT", -1, 1)

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

--- Update text visibility based on hover state
--- @param isHovering boolean
local function UpdateTextVisibility(isHovering)
    if not textLeft or not textCenter or not textRight then return end

    local cfg = sfui.config.experience or {}
    local mode = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "showText", cfg.showText or "MOUSEOVER")) or "MOUSEOVER"

    if mode == "ALWAYS" then
        textLeft:SetAlpha(1.0)
        textCenter:SetAlpha(1.0)
        textRight:SetAlpha(1.0)
    elseif mode == "MOUSEOVER" then
        local alpha = isHovering and 1.0 or 0.0
        textLeft:SetAlpha(alpha)
        textCenter:SetAlpha(alpha)
        textRight:SetAlpha(alpha)
    else
        textLeft:SetAlpha(0.0)
        textCenter:SetAlpha(0.0)
        textRight:SetAlpha(0.0)
    end
end

--- Update layout and docking position relative to experience bar
function repModule.UpdateLayout()
    if not repContainer then return end

    local cfg = sfui.config.experience or {}
    local expBar = sfui.experience.bar and sfui.experience.bar.GetFrame and sfui.experience.bar.GetFrame()
    if not expBar then return end

    local width = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "width", cfg.width or 460)) or 460
    local repHeight = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "repHeight", cfg.repHeight or 12)) or 12
    local repOnTop = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "repOnTop", cfg.repOnTop ~= false))
    if repOnTop == nil then repOnTop = true end

    repContainer:SetSize(width, repHeight)
    repContainer:ClearAllPoints()

    -- Check if experience bar is currently shown
    local isExpShown = expBar:IsShown() and expBar:GetAlpha() > 0

    if isExpShown then
        if repOnTop then
            repContainer:SetPoint("BOTTOMLEFT", expBar, "TOPLEFT", 0, 2)
            repContainer:SetPoint("BOTTOMRIGHT", expBar, "TOPRIGHT", 0, 2)
        else
            repContainer:SetPoint("TOPLEFT", expBar, "BOTTOMLEFT", 0, -2)
            repContainer:SetPoint("TOPRIGHT", expBar, "BOTTOMRIGHT", 0, -2)
        end
    else
        -- Take primary position if XP bar is hidden (e.g. at max level)
        local pos = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "pos", cfg.pos)) or cfg.pos or { point = "BOTTOM", x = 0, y = 4 }
        repContainer:SetPoint(pos.point or "BOTTOM", _G.UIParent, pos.relativePoint or pos.point or "BOTTOM", pos.x or 0, pos.y or 4)
    end

    if repBar then
        repBar:ClearAllPoints()
        repBar:SetPoint("TOPLEFT", repContainer, "TOPLEFT", 1, -1)
        repBar:SetPoint("BOTTOMRIGHT", repContainer, "BOTTOMRIGHT", -1, 1)
    end

    UpdateTicks(width - 2, repHeight - 2)
    repModule.ApplyTheme()
end

--- Update values and visibility of reputation bar
function repModule.UpdateValues()
    if not repContainer then return end

    local data = sfui.experience.data
    if not data then return end

    local cfg = sfui.config.experience or {}
    local enabled = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "enabled", true))
    if enabled == nil then enabled = true end
    if not enabled then
        repContainer:Hide()
        return
    end

    local repData = data.GetReputationData()
    local isMax = data.IsMaxLevel()
    local showDual = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "showDualBars", cfg.showDualBars ~= false))
    if showDual == nil then showDual = true end

    -- Determine visibility:
    -- In dual bar mode:
    -- If no watched reputation -> Hide
    -- If single bar mode (showDual is false) -> Hide (handled by bar.lua)
    if not showDual or not repData or not repData.hasRep then
        repContainer:Hide()
        return
    end

    repContainer:Show()
    repModule.UpdateLayout()

    -- Set statusbar values & color
    repBar:SetMinMaxValues(0, repData.max)
    repBar:SetValue(repData.current)
    repBar:SetStatusBarColor(repData.color[1], repData.color[2], repData.color[3], repData.color[4] or 1.0)

    -- Text formatting
    local textFormat = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "textFormat", cfg.textFormat or "PERCENT_CURRENT")) or "PERCENT_CURRENT"

    -- Left: Faction name & Standing
    textLeft:SetText(string_format("%s (%s)", repData.name, repData.standingText))

    -- Center: Progress & Percentage
    local curStr = data.FormatNumber(repData.current)
    local maxStr = data.FormatNumber(repData.max)
    if textFormat == "PERCENT_CURRENT" then
        textCenter:SetText(string_format("%s / %s (%.1f%%)", curStr, maxStr, repData.percent))
    elseif textFormat == "PERCENT" then
        textCenter:SetText(string_format("%.1f%%", repData.percent))
    elseif textFormat == "REMAINING" then
        textCenter:SetText(string_format("-%s (%.1f%%)", data.FormatNumber(repData.remaining), repData.percent))
    else
        textCenter:SetText(string_format("%s / %s", curStr, maxStr))
    end

    -- Right: Remaining to next rank
    textRight:SetText(string_format("-%s", data.FormatNumber(repData.remaining)))

    UpdateTextVisibility(false)
end

--- Create the stacked reputation status bar
--- @return Frame
function repModule.Create()
    if repContainer then return repContainer end

    repContainer = CreateFrame("Button", "SfuiReputationBar", _G.UIParent, "BackdropTemplate")
    repContainer:SetFrameStrata("HIGH")
    repContainer:SetFrameLevel(20)
    repContainer:SetClampedToScreen(true)
    repContainer:EnableMouse(true)
    repContainer:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Status bar fill
    repBar = CreateFrame("StatusBar", nil, repContainer)
    repBar:SetFrameLevel(repContainer:GetFrameLevel() + 1)
    repBar:EnableMouse(false)

    -- Tick marks frame
    tickFrame = CreateFrame("Frame", nil, repContainer)
    tickFrame:SetFrameLevel(repContainer:GetFrameLevel() + 2)
    tickFrame:EnableMouse(false)

    -- Text overlay frame
    local textFrame = CreateFrame("Frame", nil, repContainer)
    textFrame:SetFrameLevel(repContainer:GetFrameLevel() + 3)
    textFrame:SetAllPoints(repContainer)
    textFrame:EnableMouse(false)

    local font = (sfui.config and sfui.config.font) or "GameFontHighlightSmall"

    textLeft = textFrame:CreateFontString(nil, "OVERLAY", font)
    textLeft:SetPoint("LEFT", textFrame, "LEFT", 8, 0)
    textLeft:SetJustifyH("LEFT")
    textLeft:SetTextColor(0.92, 0.92, 0.92, 1.0)
    textLeft:SetShadowOffset(1, -1)
    textLeft:SetShadowColor(0, 0, 0, 1)

    textCenter = textFrame:CreateFontString(nil, "OVERLAY", font)
    textCenter:SetPoint("CENTER", textFrame, "CENTER", 0, 0)
    textCenter:SetJustifyH("CENTER")
    textCenter:SetTextColor(1.0, 1.0, 1.0, 1.0)
    textCenter:SetShadowOffset(1, -1)
    textCenter:SetShadowColor(0, 0, 0, 1)

    textRight = textFrame:CreateFontString(nil, "OVERLAY", font)
    textRight:SetPoint("RIGHT", textFrame, "RIGHT", -8, 0)
    textRight:SetJustifyH("RIGHT")
    textRight:SetTextColor(0.85, 0.85, 0.85, 1.0)
    textRight:SetShadowOffset(1, -1)
    textRight:SetShadowColor(0, 0, 0, 1)

    -- Mouse Interactions & Tooltip
    repContainer:SetScript("OnEnter", function(self)
        UpdateTextVisibility(true)
        if sfui.experience.tooltip and sfui.experience.tooltip.OnEnterRep then
            sfui.experience.tooltip.OnEnterRep(self)
        end
    end)

    repContainer:SetScript("OnLeave", function(self)
        UpdateTextVisibility(false)
        if sfui.experience.tooltip and sfui.experience.tooltip.OnLeave then
            sfui.experience.tooltip.OnLeave()
        end
    end)

    repContainer:SetScript("OnClick", function(self, button)
        if InCombatLockdown and InCombatLockdown() then return end
        if IsShiftKeyDown() then
            if sfui.experience.tooltip and sfui.experience.tooltip.ShareToChat then
                sfui.experience.tooltip.ShareToChat("REP")
            end
        elseif button == "RightButton" then
            if sfui.toggle_options_panel then
                sfui.toggle_options_panel("experience")
            end
        end
    end)

    -- Dragging support when unlocked
    repContainer:SetMovable(true)
    repContainer:RegisterForDrag("LeftButton")
    repContainer:SetScript("OnDragStart", function(self)
        if repContainer._isUnlocked then
            local expBar = sfui.experience.bar and sfui.experience.bar.GetFrame and sfui.experience.bar.GetFrame()
            local isExpShown = expBar and expBar:IsShown() and expBar:GetAlpha() > 0
            if isExpShown then
                expBar:StartMoving()
            else
                self:StartMoving()
            end
        end
    end)
    repContainer:SetScript("OnDragStop", function(self)
        if repContainer._isUnlocked then
            local expBar = sfui.experience.bar and sfui.experience.bar.GetFrame and sfui.experience.bar.GetFrame()
            local isExpShown = expBar and expBar:IsShown() and expBar:GetAlpha() > 0
            local targetFrame = isExpShown and expBar or self
            targetFrame:StopMovingOrSizing()
            local point, _, relPoint, x, y = targetFrame:GetPoint()
            if sfui.db and sfui.db.Set then
                sfui.db.Set("experience", "pos", {
                    point = point,
                    relativePoint = relPoint,
                    x = math_floor(x + 0.5),
                    y = math_floor(y + 0.5),
                })
            end
        end
    end)

    if sfui.theme and sfui.theme.RegisterBar then
        sfui.theme.RegisterBar(repContainer, "xp")
    end

    repModule.ApplyTheme()
    repModule.UpdateLayout()
    UpdateTextVisibility(false)
    repModule.UpdateValues()

    return repContainer
end
