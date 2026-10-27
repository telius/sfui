local addonName, addon = ...
sfui = sfui or {}
sfui.experience = sfui.experience or {}
sfui.experience.bar = {}

local barModule = sfui.experience.bar

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/experience/bar.lua
--  Multi-layer flat experience & reputation status bar
--  Layers: Container -> Rested Bar -> Quest Preview Bar -> Active Bar -> Ticks -> Texts
-- ══════════════════════════════════════════════════════════════════════════════

local _G = _G
local CreateFrame = _G.CreateFrame
local math_min = math.min
local math_max = math.max
local math_floor = math.floor
local string_format = string.format
local IsShiftKeyDown = _G.IsShiftKeyDown

local container = nil
local restedBar = nil
local questBar = nil
local mainBar = nil
local tickFrame = nil
local ticks = {}
local textLeft = nil
local textCenter = nil
local textRight = nil
local currentMode = "XP" -- "XP" or "REP"

--- Set status bar texture directly
--- @param tex string|nil
function barModule.SetBarTexture(tex)
    local resolvedTex = sfui.common.get_bar_texture(tex)
    if mainBar then mainBar:SetStatusBarTexture(resolvedTex) end
    if restedBar then restedBar:SetStatusBarTexture(resolvedTex) end
    if questBar then questBar:SetStatusBarTexture(resolvedTex) end
end

--- Get container frame reference
--- @return Frame|nil
function barModule.GetFrame()
    return container
end

--- Get current display mode ("XP" or "REP")
--- @return string
function barModule.GetMode()
    return currentMode
end

--- Set current display mode
--- @param mode string
function barModule.SetMode(mode)
    currentMode = mode
    barModule.UpdateValues()
end

--- Cycle between XP, Reputation, and Legacy Challenge tracking
function barModule.ToggleMode()
    local data = sfui.experience.data
    local hasLegacy = data and data.HasLegacySystem and data.HasLegacySystem()
    if currentMode == "XP" then
        currentMode = "REP"
    elseif currentMode == "REP" then
        if hasLegacy then
            currentMode = "LEGACY"
        else
            currentMode = "XP"
        end
    else -- "LEGACY"
        currentMode = "XP"
    end
    barModule.UpdateValues()
end

local unlockOverlay = nil

--- Set unlocked dragging state and toggle visual mover overlay
--- @param unlocked boolean
function barModule.SetUnlocked(unlocked)
    if not container then return end
    container._isUnlocked = unlocked

    if unlocked then
        if not unlockOverlay then
            unlockOverlay = CreateFrame("Frame", nil, container, "BackdropTemplate")
            unlockOverlay:SetAllPoints(container)
            unlockOverlay:SetFrameLevel(container:GetFrameLevel() + 30)
            unlockOverlay:EnableMouse(true)
            unlockOverlay:RegisterForDrag("LeftButton")

            local bg = unlockOverlay:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.0, 0.6, 0.9, 0.45)
            unlockOverlay.bg = bg

            if sfui.widgets and sfui.widgets.create_border then
                sfui.widgets.create_border(unlockOverlay, 1, { 0.2, 0.8, 1, 1 })
            end

            local lbl = unlockOverlay:CreateFontString(nil, "OVERLAY", sfui.config and sfui.config.font_small or "GameFontNormalSmall")
            lbl:SetPoint("CENTER", unlockOverlay, "CENTER", 0, 0)
            lbl:SetText("|cff00ffffexperience bar|r |cffaaaaaa(drag to move)|r")
            unlockOverlay.lbl = lbl

            unlockOverlay:SetScript("OnDragStart", function()
                container:StartMoving()
            end)
            unlockOverlay:SetScript("OnDragStop", function()
                container:StopMovingOrSizing()
                local point, _, relPoint, x, y = container:GetPoint()
                if sfui.db and sfui.db.Set then
                    sfui.db.Set("experience", "pos", {
                        point = point,
                        relativePoint = relPoint,
                        x = math_floor(x + 0.5),
                        y = math_floor(y + 0.5),
                    })
                end
            end)
        end
        container:Show()
        container:SetAlpha(1.0)
        unlockOverlay:Show()
    else
        if unlockOverlay then
            unlockOverlay:Hide()
        end
        barModule.UpdateValues()
    end
end

--- Apply theme styling to the container frame
function barModule.ApplyTheme()
    if not container then return end

    if sfui.theme and sfui.theme.ApplyStatusBarStyle then
        sfui.theme.ApplyStatusBarStyle(container, "xp")
    else
        container:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets   = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        container:SetBackdropColor(0.04, 0.04, 0.04, 0.85)
        container:SetBackdropBorderColor(0.0, 0.0, 0.0, 1.0)
    end

    barModule.SetBarTexture()
end

--- Update position and dimensions from config/saved variables
function barModule.UpdateLayout()
    if not container then return end

    local cfg = sfui.config.experience or {}
    local width = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "width", cfg.width or 460)) or 460
    local height = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "height", cfg.height or 14)) or 14
    local pos = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "pos", cfg.pos)) or cfg.pos or { point = "BOTTOM", x = 0, y = 4 }

    container:SetSize(width, height)
    container:ClearAllPoints()
    container:SetPoint(pos.point or "BOTTOM", _G.UIParent, pos.relativePoint or pos.point or "BOTTOM", pos.x or 0, pos.y or 4)

    -- Update sub-bars to fill container inset by 1px
    if restedBar then
        restedBar:ClearAllPoints()
        restedBar:SetPoint("TOPLEFT", container, "TOPLEFT", 1, -1)
        restedBar:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -1, 1)
    end
    if questBar then
        questBar:ClearAllPoints()
        questBar:SetPoint("TOPLEFT", container, "TOPLEFT", 1, -1)
        questBar:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -1, 1)
    end
    if mainBar then
        mainBar:ClearAllPoints()
        mainBar:SetPoint("TOPLEFT", container, "TOPLEFT", 1, -1)
        mainBar:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -1, 1)
    end

    -- Update 20-segment tick marks
    barModule.UpdateTicks(width - 2, height - 2)

    barModule.ApplyTheme()

    if sfui.experience.reputation and sfui.experience.reputation.UpdateLayout then
        sfui.experience.reputation.UpdateLayout()
    end
    if sfui.experience.challenges and sfui.experience.challenges.UpdateLayout then
        sfui.experience.challenges.UpdateLayout()
    end
    if sfui.experience.pet and sfui.experience.pet.UpdateLayout then
        sfui.experience.pet.UpdateLayout()
    end
end

--- Update or create 20-segment tick marks
--- @param innerWidth number
--- @param innerHeight number
function barModule.UpdateTicks(innerWidth, innerHeight)
    if not tickFrame then return end

    local cfg = sfui.config.experience or {}
    local showTicks = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "showTicks", cfg.showTicks == true))
    if showTicks == nil then showTicks = false end

    if not showTicks or innerWidth <= 0 then
        tickFrame:Hide()
        return
    end

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

    -- Hide extra ticks if count was reduced
    for i = numDividers + 1, #ticks do
        ticks[i]:Hide()
    end
end

--- Update text display visibility based on mouseover setting
local function UpdateTextVisibility(isHovering)
    if not textLeft or not textCenter or not textRight then return end
    local data = sfui.experience.data
    local alpha = data and data.GetTextAlpha and data.GetTextAlpha(isHovering) or (isHovering and 1.0 or 0.0)
    textLeft:SetAlpha(alpha)
    textCenter:SetAlpha(alpha)
    textRight:SetAlpha(alpha)
end

--- Refresh all visual values, layering, and text contents
function barModule.UpdateValues()
    if not container then return end

    local cfg = sfui.config.experience or {}
    local data = sfui.experience.data
    if not data then return end

    local xpData = data.GetXPData()
    local repData = data.GetReputationData()
    local showDual = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "showDualBars", cfg.showDualBars ~= false))
    if showDual == nil then showDual = true end

    local autoRep = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "autoReputation", cfg.autoReputation ~= false))
    if autoRep == nil then autoRep = true end

    local isMax = xpData.isMaxLevel or xpData.isXPDisabled
    local repOnlyAtMaxLevel = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "repOnlyAtMaxLevel", cfg.repOnlyAtMaxLevel ~= false))

    local showXP = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "showXP", cfg.showXP ~= false))
    if showXP == nil then showXP = true end

    local repEnabled = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "repEnabled", cfg.repEnabled ~= false))
    if repEnabled == nil then
        local repDisabled = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "repDisabled", false))
        repEnabled = not repDisabled
    end

    if not showXP and not container._isUnlocked then
        if showDual then
            container:Hide()
            UpdateTextVisibility(false)
            if sfui.experience.reputation and sfui.experience.reputation.UpdateValues then
                sfui.experience.reputation.UpdateValues()
            end
            return
        else
            if repEnabled and repData and repData.hasRep then
                currentMode = "REP"
            elseif data.HasLegacySystem and data.HasLegacySystem() then
                currentMode = "LEGACY"
            else
                container:Hide()
                UpdateTextVisibility(false)
                return
            end
        end
    end

    if showDual then
        if isMax and not container._isUnlocked then
            container:Hide()
        else
            container:Show()
        end
        currentMode = "XP"
    else
        -- Single bar mode: toggle between XP, Reputation, and Legacy Challenges
        if isMax then
            if currentMode == "LEGACY" and data.HasLegacySystem and data.HasLegacySystem() then
                container:Show()
            elseif autoRep and repData and repData.hasRep then
                currentMode = "REP"
                container:Show()
            elseif autoRep and data.HasLegacySystem and data.HasLegacySystem() then
                currentMode = "LEGACY"
                container:Show()
            elseif not container._isUnlocked then
                container:Hide()
            else
                container:Show()
            end
        else
            container:Show()
            if repOnlyAtMaxLevel and (not repData or not repData.hasRep) then
                currentMode = "XP"
            elseif currentMode == "REP" and (not repData or not repData.hasRep) then
                if data.HasLegacySystem and data.HasLegacySystem() then
                    currentMode = "LEGACY"
                else
                    currentMode = "XP"
                end
            elseif currentMode == "LEGACY" and (not data.HasLegacySystem or not data.HasLegacySystem()) then
                currentMode = "XP"
            end
        end
    end

    local textFormat = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "textFormat", cfg.textFormat or "PERCENT_CURRENT")) or "PERCENT_CURRENT"
    local showRate = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "showRate", cfg.showRate ~= false))
    local showTTL = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "showTTL", cfg.showTTL ~= false))

    if currentMode == "LEGACY" and data.HasLegacySystem and data.HasLegacySystem() then
        -- ─── Legacy Challenges Mode ───────────────────────────────────────────
        restedBar:Hide()
        questBar:Hide()
        local ch = sfui.experience.challenges
        if ch and ch.ApplyToBar then
            ch.ApplyToBar(mainBar, textLeft, textCenter, textRight, textFormat)
        end

    elseif currentMode == "REP" and repData and repData.hasRep then
        -- ─── Reputation Mode ──────────────────────────────────────────────────
        restedBar:Hide()
        questBar:Hide()
        mainBar:Show()

        mainBar:SetMinMaxValues(0, repData.max)
        mainBar:SetValue(repData.current)
        mainBar:SetStatusBarColor(repData.color[1], repData.color[2], repData.color[3], repData.color[4] or 1.0)

        -- Text: Left = Faction & Standing
        textLeft:SetText(string_format("%s (%s)", repData.name, repData.standingText))

        -- Text: Center = Current / Max (Percent)
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

        -- Text: Right = Remaining rep to next standing
        textRight:SetText(string_format("-%s", data.FormatNumber(repData.remaining)))

    else
        -- ─── Experience Mode ──────────────────────────────────────────────────
        local maxXP = xpData.max
        local currXP = xpData.current

        local showRested = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "showRested", cfg.showRested ~= false))
        if showRested == nil then showRested = true end
        local restedData = showRested and data.GetRestedData(maxXP)

        local showQuestPreview = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "showQuestPreview", cfg.showQuestPreview ~= false))
        if showQuestPreview == nil then showQuestPreview = true end
        local questData = showQuestPreview and data.GetQuestXPData(maxXP)

        local sessionStats = data.GetSessionStats(xpData.remaining)

        mainBar:Show()
        mainBar:SetMinMaxValues(0, maxXP)
        mainBar:SetValue(currXP)

        -- Resolve active XP color (class/spec or custom)
        local useClassColor = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "useClassColor", false))
        if useClassColor == nil then useClassColor = false end

        local activeColor = (cfg.colors and cfg.colors.xp) or { 0.58, 0.0, 0.82, 1.0 }
        if useClassColor and sfui.common and sfui.common.get_class_or_spec_color then
            local specColor = sfui.common.get_class_or_spec_color()
            if specColor then
                activeColor = { specColor[1], specColor[2], specColor[3], 1.0 }
            end
        end
        mainBar:SetStatusBarColor(activeColor[1], activeColor[2], activeColor[3], activeColor[4] or 1.0)

        -- Layer 1: Rested Bar (Cyan/Mint)
        if showRested and restedData and restedData.isRested then
            restedBar:Show()
            restedBar:SetMinMaxValues(0, maxXP)
            local restedTotal = math_min(maxXP, currXP + restedData.restedXP)
            restedBar:SetValue(restedTotal)
            local rc = (cfg.colors and cfg.colors.rested) or { 0.0, 0.65, 0.90, 0.60 }
            restedBar:SetStatusBarColor(rc[1], rc[2], rc[3], rc[4] or 0.60)
        else
            restedBar:Hide()
        end

        -- Layer 2: Completed Quest Preview Bar (Amber/Gold)
        if showQuestPreview and questData and questData.totalQuestXP > 0 then
            questBar:Show()
            questBar:SetMinMaxValues(0, maxXP)
            local questTotal = math_min(maxXP, currXP + questData.totalQuestXP)
            questBar:SetValue(questTotal)
            local qc = (cfg.colors and cfg.colors.questPreview) or { 0.96, 0.65, 0.12, 0.70 }
            questBar:SetStatusBarColor(qc[1], qc[2], qc[3], qc[4] or 0.70)
        else
            questBar:Hide()
        end

        -- Text: Left = Level & TTL
        local leftStr = string_format("lvl %d", xpData.level)
        if showTTL and sessionStats.ttlSeconds then
            leftStr = string_format("lvl %d  •  ttl: %s", xpData.level, data.FormatTime(sessionStats.ttlSeconds))
        end
        textLeft:SetText(leftStr)

        -- Text: Center = Current / Max (Percent) + Quests
        local curStr = data.FormatNumber(currXP)
        local maxStr = data.FormatNumber(maxXP)
        local questAddon = ""
        if questData.totalQuestXP > 0 then
            questAddon = string_format(" |cffffbb33(+%s quests)|r", data.FormatNumber(questData.totalQuestXP))
        end

        if textFormat == "PERCENT_CURRENT" then
            textCenter:SetText(string_format("%s / %s (%.1f%%)%s", curStr, maxStr, xpData.percent, questAddon))
        elseif textFormat == "PERCENT" then
            textCenter:SetText(string_format("%.1f%%%s", xpData.percent, questAddon))
        elseif textFormat == "REMAINING" then
            textCenter:SetText(string_format("-%s (%.1f%%)%s", data.FormatNumber(xpData.remaining), xpData.percent, questAddon))
        else
            textCenter:SetText(string_format("%s / %s%s", curStr, maxStr, questAddon))
        end

        -- Text: Right = Session XP/hr or Kills
        local rightStr = ""
        if showRate and sessionStats.xpHour > 0 then
            rightStr = string_format("%s xp/hr", data.FormatNumber(sessionStats.xpHour))
        elseif sessionStats.killsToLevel then
            rightStr = string_format("~%d kills", sessionStats.killsToLevel)
        else
            rightStr = string_format("-%s", data.FormatNumber(xpData.remaining))
        end
        textRight:SetText(rightStr)
    end

    UpdateTextVisibility(false)

    if sfui.experience.reputation and sfui.experience.reputation.UpdateValues then
        sfui.experience.reputation.UpdateValues()
    end
end

--- Create the experience status bar and component frames
--- @return Frame
function barModule.Create()
    if container then return container end

    -- Container button with BackdropTemplate
    container = CreateFrame("Button", "SfuiExperienceBar", _G.UIParent, "BackdropTemplate")
    container:SetFrameStrata("HIGH")
    container:SetFrameLevel(20)
    container:SetClampedToScreen(true)
    container:EnableMouse(true)
    container:SetMovable(true)
    container:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Layer 1: Rested Bar (bottom-most fill)
    restedBar = CreateFrame("StatusBar", nil, container)
    restedBar:SetFrameLevel(container:GetFrameLevel() + 1)
    restedBar:EnableMouse(false)

    -- Layer 2: Quest Preview Bar (middle fill)
    questBar = CreateFrame("StatusBar", nil, container)
    questBar:SetFrameLevel(container:GetFrameLevel() + 2)
    questBar:EnableMouse(false)

    -- Layer 3: Active Main Bar (top fill)
    mainBar = CreateFrame("StatusBar", nil, container)
    mainBar:SetFrameLevel(container:GetFrameLevel() + 3)
    mainBar:EnableMouse(false)

    -- Layer 4: Segment Tick Marks Frame
    tickFrame = CreateFrame("Frame", nil, container)
    tickFrame:SetFrameLevel(container:GetFrameLevel() + 4)
    tickFrame:EnableMouse(false)

    -- Layer 5: Text Overlays Frame
    local textFrame = CreateFrame("Frame", nil, container)
    textFrame:SetFrameLevel(container:GetFrameLevel() + 5)
    textFrame:SetAllPoints(container)
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
    container:SetScript("OnEnter", function(self)
        UpdateTextVisibility(true)
        if sfui.experience.tooltip and sfui.experience.tooltip.OnEnter then
            sfui.experience.tooltip.OnEnter(self, currentMode)
        end
    end)

    container:SetScript("OnLeave", function(self)
        UpdateTextVisibility(false)
        if sfui.experience.tooltip and sfui.experience.tooltip.OnLeave then
            sfui.experience.tooltip.OnLeave()
        end
    end)

    container:SetScript("OnClick", function(self, button)
        if InCombatLockdown and InCombatLockdown() then return end
        if IsShiftKeyDown() then
            if sfui.experience.tooltip and sfui.experience.tooltip.ShareToChat then
                sfui.experience.tooltip.ShareToChat(currentMode)
            end
        elseif button == "RightButton" then
            if sfui.toggle_options_panel then
                sfui.toggle_options_panel("experience")
            end
        elseif button == "LeftButton" then
            barModule.ToggleMode()
        end
    end)

    -- Dragging support when unlocked
    container:RegisterForDrag("LeftButton")
    container:SetScript("OnDragStart", function(self)
        if container._isUnlocked then
            self:StartMoving()
        end
    end)
    container:SetScript("OnDragStop", function(self)
        if container._isUnlocked then
            self:StopMovingOrSizing()
            local point, _, relPoint, x, y = self:GetPoint()
            if sfui.db and sfui.db.Set then
                sfui.db.Set("experience", "pos", {
                    point = point,
                    relativePoint = relPoint,
                    x = math.floor(x + 0.5),
                    y = math.floor(y + 0.5),
                })
            end
        end
    end)

    -- Register with theme engine
    if sfui.theme and sfui.theme.RegisterBar then
        sfui.theme.RegisterBar(container, "xp")
    end

    -- Hook anchor to floating combat text
    if sfui.experience.floating and sfui.experience.floating.SetAnchor then
        sfui.experience.floating.SetAnchor(container)
    end

    container:HookScript("OnShow", function()
        if sfui.experience.challenges and sfui.experience.challenges.UpdateLayout then
            sfui.experience.challenges.UpdateLayout()
        end
        if sfui.experience.pet and sfui.experience.pet.UpdateLayout then
            sfui.experience.pet.UpdateLayout()
        end
    end)
    container:HookScript("OnHide", function()
        if sfui.experience.challenges and sfui.experience.challenges.UpdateLayout then
            sfui.experience.challenges.UpdateLayout()
        end
        if sfui.experience.pet and sfui.experience.pet.UpdateLayout then
            sfui.experience.pet.UpdateLayout()
        end
    end)

    barModule.ApplyTheme()
    barModule.UpdateLayout()
    UpdateTextVisibility(false)
    barModule.UpdateValues()

    if sfui.movers and sfui.movers.Register then
        sfui.movers.Register(container, {
            key = "experience",
            label = "experience bar",
            preferredPoint = "BOTTOM",
            customSize = function()
                local cfg = sfui.config.experience or {}
                local w = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "width", cfg.width or 460)) or 460
                local h = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "height", cfg.height or 14)) or 14
                return w, h
            end,
            getPoint = function()
                local cfg = sfui.config.experience or {}
                local pos = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "pos", cfg.pos)) or cfg.pos or { point = "BOTTOM", x = 0, y = 4 }
                return pos.point or "BOTTOM", _G.UIParent, pos.relativePoint or pos.point or "BOTTOM", pos.x or 0, pos.y or 4
            end,
            setPoint = function(point, relTo, relPoint, x, y)
                if sfui.db and sfui.db.Set then
                    sfui.db.Set("experience", "pos", {
                        point = point,
                        relativePoint = relPoint,
                        x = x,
                        y = y,
                    })
                end
                barModule.UpdateLayout()
            end,
            resetPosition = function()
                local expMod = sfui.experience
                if expMod and expMod.ResetPosition then
                    expMod.ResetPosition()
                else
                    local cfg = sfui.config.experience or {}
                    local defPos = cfg.pos or { point = "BOTTOM", x = 0, y = 4 }
                    if sfui.db and sfui.db.Set then
                        sfui.db.Set("experience", "pos", defPos)
                    end
                    barModule.UpdateLayout()
                end
            end,
            isEnabled = function()
                return container ~= nil
            end,
            onEnterEditMode = function()
                container:Show()
                container:SetAlpha(1.0)
            end,
            onExitEditMode = function()
                barModule.UpdateValues()
            end,
        })
    end

    return container
end
