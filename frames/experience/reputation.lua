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
local string_format = string.format
local IsShiftKeyDown = _G.IsShiftKeyDown
local InCombatLockdown = _G.InCombatLockdown

local base = sfui.experience.base
local repBarObj = nil
local repContainer = nil
local repBar = nil
local textLeft = nil
local textCenter = nil
local textRight = nil

--- Get the active status bar texture
--- Set status bar texture directly
--- @param tex string|nil
function repModule.SetBarTexture(tex)
    base.SetBarTexture(repBarObj, tex)
end

--- Get reputation container frame
--- @return Frame|nil
function repModule.GetFrame()
    return repContainer
end

local currentRepMode = "AUTO" -- "AUTO", "REP", or "LEGACY"

--- Get active display mode on the secondary/stacked bar ("REP" or "LEGACY")
--- @return string
function repModule.GetActiveMode()
    local hasLegacy = sfui.experience.challenges and sfui.experience.challenges.IsAvailable and sfui.experience.challenges.IsAvailable()
    local repData = sfui.experience.data and sfui.experience.data.GetReputationData and sfui.experience.data.GetReputationData()
    local hasRep = repData and repData.hasRep

    if currentRepMode == "LEGACY" then
        return hasLegacy and "LEGACY" or "REP"
    elseif currentRepMode == "REP" then
        return "REP"
    else -- "AUTO"
        if hasRep then
            return "REP"
        elseif hasLegacy then
            return "LEGACY"
        else
            return "REP"
        end
    end
end

--- Toggle between watched reputation and legacy challenge progress
function repModule.ToggleMode()
    local hasLegacy = sfui.experience.challenges and sfui.experience.challenges.IsAvailable and sfui.experience.challenges.IsAvailable()
    local repData = sfui.experience.data and sfui.experience.data.GetReputationData and sfui.experience.data.GetReputationData()
    local hasRep = repData and repData.hasRep

    if not hasLegacy then
        currentRepMode = "REP"
        repModule.UpdateValues()
        return
    end

    if not hasRep then
        currentRepMode = "LEGACY"
        repModule.UpdateValues()
        return
    end

    local cur = repModule.GetActiveMode()
    if cur == "LEGACY" then
        currentRepMode = "REP"
    else
        currentRepMode = "LEGACY"
    end
    repModule.UpdateValues()
end

local REP_UNLOCK_OPTS = {
    bgColor         = { 0.0, 0.8, 0.5, 0.45 },
    borderColor     = { 0.2, 1, 0.6, 1 },
    label           = "|cff00ff88reputation bar|r |cffaaaaaa(drag to move)|r",
    dragMovesExpBar = true,
    onLockUpdate    = function()
        repModule.UpdateValues()
    end,
}

--- Set unlocked dragging state and toggle visual mover overlay for reputation
--- @param unlocked boolean
function repModule.SetUnlocked(unlocked)
    base.SetUnlocked(repBarObj, unlocked, REP_UNLOCK_OPTS)
end

--- Apply theme styling to the reputation bar
function repModule.ApplyTheme()
    base.ApplyTheme(repBarObj, "xp")
end

--- Update 20-segment tick marks
--- @param innerWidth number
--- @param innerHeight number
local function UpdateTicks(innerWidth, innerHeight)
    base.UpdateTicks(repBarObj, innerWidth, innerHeight)
end

--- Update text visibility based on hover state
local function UpdateTextVisibility(isHovering)
    base.UpdateTextVisibility(repBarObj, isHovering)
end

--- Update layout and docking position relative to experience bar
function repModule.UpdateLayout()
    if not repContainer then return end

    local cfg = sfui.config.experience or {}
    local expBar = sfui.experience.bar and sfui.experience.bar.GetFrame and sfui.experience.bar.GetFrame()
    if not expBar then return end

    local width = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "width", cfg.width or 460)) or 460
    local repHeight = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "repHeight", cfg.repHeight or 8)) or 8
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

    base.AnchorSubBars(repBarObj)

    UpdateTicks(width - 2, repHeight - 2)
    repModule.ApplyTheme()

    if sfui.experience.challenges and sfui.experience.challenges.UpdateLayout then
        sfui.experience.challenges.UpdateLayout()
    end
    if sfui.experience.pet and sfui.experience.pet.UpdateLayout then
        sfui.experience.pet.UpdateLayout()
    end
end

--- Update values and visibility of reputation bar
function repModule.UpdateValues()
    if not repContainer then return end

    local data = sfui.experience.data
    if not data then return end

    local cfg = sfui.config.experience or {}
    local enabled = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "enabled", true))
    if enabled == nil then enabled = true end

    local repEnabled = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "repEnabled", cfg.repEnabled ~= false))
    if repEnabled == nil then
        local repDisabled = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "repDisabled", false))
        repEnabled = not repDisabled
    end

    if not repEnabled and not repContainer._isUnlocked then
        repContainer:Hide()
        return
    end

    if not enabled and not repEnabled and not repContainer._isUnlocked then
        repContainer:Hide()
        return
    end

    local repData = data.GetReputationData()
    local isMax = data.IsMaxLevel() or (data.IsXPDisabled and data.IsXPDisabled())
    local showDual = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "showDualBars", cfg.showDualBars ~= false))
    if showDual == nil then showDual = true end

    local repOnlyAtMaxLevel = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "repOnlyAtMaxLevel", cfg.repOnlyAtMaxLevel ~= false))
    if repOnlyAtMaxLevel and not isMax and not repContainer._isUnlocked then
        repContainer:Hide()
        return
    end

    local activeMode = repModule.GetActiveMode()
    local hasTargetData = (activeMode == "LEGACY") or (repData and repData.hasRep)

    -- Determine visibility:
    -- In dual bar mode:
    -- If no watched reputation and no legacy track -> Hide
    -- If single bar mode (showDual is false) -> Hide (handled by bar.lua)
    if (not showDual or not hasTargetData) and not repContainer._isUnlocked then
        repContainer:Hide()
        return
    end

    repContainer:Show()
    repModule.UpdateLayout()

    local textFormat = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "textFormat", cfg.textFormat or "PERCENT_CURRENT")) or "PERCENT_CURRENT"

    if activeMode == "LEGACY" then
        local ch = sfui.experience.challenges
        if ch and ch.ApplyToBar then
            ch.ApplyToBar(repBar, textLeft, textCenter, textRight, textFormat)
        end
    else
        if not repData or not repData.hasRep then
            if repBar then
                repBar:SetMinMaxValues(0, 100)
                repBar:SetValue(100)
                repBar:SetStatusBarColor(0.0, 0.60, 0.35, 1.0)
            end
            if textLeft then textLeft:SetText("") end
            if textCenter then textCenter:SetText("") end
            if textRight then textRight:SetText("") end
            return
        end

        -- Set statusbar values & color
        repBar:SetMinMaxValues(0, repData.max)
        repBar:SetValue(repData.current)
        repBar:SetStatusBarColor(repData.color[1], repData.color[2], repData.color[3], repData.color[4] or 1.0)

        -- Text formatting
        -- Left: Faction name & Standing
        textLeft:SetText(string_format("%s (%s)", repData.name, repData.standingText))

        -- Center: Progress & Percentage
        textCenter:SetText(base.FormatProgressText(textFormat, repData.current, repData.max, repData.percent, nil, repData.remaining))

        -- Right: Remaining to next rank
        textRight:SetText(string_format("-%s", data.FormatNumber(repData.remaining)))
    end

    UpdateTextVisibility(false)
end

--- Create the stacked reputation status bar
--- @return Frame
function repModule.Create()
    if repContainer then return repContainer end

    repBarObj = base.CreateTrackedBar({
        globalName    = "SfuiReputationBar",
        frameLevel    = 20,
        numSubBars    = 1,
        hasTicks      = true,
        textInset     = 8,
        styleKey      = "xp",
        registerTheme = true,
    })

    repContainer = repBarObj.container
    repBar = repBarObj.mainBar
    textLeft = repBarObj.textLeft
    textCenter = repBarObj.textCenter
    textRight = repBarObj.textRight

    -- Mouse Interactions & Tooltip
    repContainer:SetScript("OnEnter", function(self)
        UpdateTextVisibility(true)
        if sfui.experience.tooltip and sfui.experience.tooltip.OnEnter then
            local activeMode = (repModule.GetActiveMode and repModule.GetActiveMode()) or "REP"
            sfui.experience.tooltip.OnEnter(self, activeMode)
        end
    end)

    repContainer:SetScript("OnLeave", function()
        UpdateTextVisibility(false)
        if sfui.experience.tooltip and sfui.experience.tooltip.OnLeave then
            sfui.experience.tooltip.OnLeave()
        end
    end)

    repContainer:SetScript("OnClick", function(_, button)
        if InCombatLockdown and InCombatLockdown() then return end
        local activeMode = (repModule.GetActiveMode and repModule.GetActiveMode()) or "REP"
        if IsShiftKeyDown() then
            if sfui.experience.tooltip and sfui.experience.tooltip.ShareToChat then
                sfui.experience.tooltip.ShareToChat(activeMode)
            end
        elseif button == "RightButton" then
            if sfui.toggle_options_panel then
                sfui.toggle_options_panel("experience")
            end
        elseif button == "LeftButton" then
            repModule.ToggleMode()
        end
    end)

    base.AttachDragHandlers(repBarObj, true)

    repContainer:HookScript("OnShow", function()
        if sfui.experience.challenges and sfui.experience.challenges.UpdateLayout then
            sfui.experience.challenges.UpdateLayout()
        end
        if sfui.experience.pet and sfui.experience.pet.UpdateLayout then
            sfui.experience.pet.UpdateLayout()
        end
    end)
    repContainer:HookScript("OnHide", function()
        if sfui.experience.challenges and sfui.experience.challenges.UpdateLayout then
            sfui.experience.challenges.UpdateLayout()
        end
        if sfui.experience.pet and sfui.experience.pet.UpdateLayout then
            sfui.experience.pet.UpdateLayout()
        end
    end)

    repModule.ApplyTheme()
    repModule.UpdateLayout()
    UpdateTextVisibility(false)
    repModule.UpdateValues()

    return repContainer
end
