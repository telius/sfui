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
local math_min = math.min
local string_format = string.format
local tostring = _G.tostring
local IsShiftKeyDown = _G.IsShiftKeyDown
local InCombatLockdown = _G.InCombatLockdown

local base = sfui.experience.base
local barObj = nil
local container = nil
local restedBar = nil
local questBar = nil
local mainBar = nil
local textLeft = nil
local textCenter = nil
local textRight = nil
local challengePointsText = nil
local currentMode = "XP" -- "XP" or "REP"

--- Set status bar texture directly
--- @param tex string|nil
function barModule.SetBarTexture(tex)
    base.SetBarTexture(barObj, tex)
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

local EXP_UNLOCK_OPTS = {
    bgColor     = { 0.0, 0.6, 0.9, 0.45 },
    borderColor = { 0.2, 0.8, 1, 1 },
    label       = "|cff00ffffexperience bar|r |cffaaaaaa(drag to move)|r",
    onLockUpdate = function()
        barModule.UpdateValues()
    end,
}

--- Set unlocked dragging state and toggle visual mover overlay
--- @param unlocked boolean
function barModule.SetUnlocked(unlocked)
    base.SetUnlocked(barObj, unlocked, EXP_UNLOCK_OPTS)
end

--- Apply theme styling to the container frame
function barModule.ApplyTheme()
    if not barObj then return end
    base.ApplyTheme(barObj, "xp")

    if challengePointsText then
        local fontFile = sfui.common.get_font_file()
        challengePointsText:SetFont(fontFile, 10, "")
        challengePointsText:SetShadowOffset(0, 0)
        challengePointsText:SetShadowColor(0, 0, 0, 0)
    end
end

--- Update position and dimensions from config/saved variables
function barModule.UpdateLayout()
    if not container then return end

    local cfg = sfui.config.experience or {}
    local width = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "width", cfg.width or 460)) or 460
    local height = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "height", cfg.height or 8)) or 8
    local pos = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "pos", cfg.pos)) or cfg.pos or { point = "BOTTOM", x = 0, y = 4 }

    container:SetSize(width, height)
    container:ClearAllPoints()
    container:SetPoint(pos.point or "BOTTOM", _G.UIParent, pos.relativePoint or pos.point or "BOTTOM", pos.x or 0, pos.y or 4)

    base.AnchorSubBars(barObj)
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
    base.UpdateTicks(barObj, innerWidth, innerHeight)
end

--- Update text display visibility based on mouseover setting
local function UpdateTextVisibility(isHovering)
    local hideCenter = (challengePointsText and challengePointsText:IsShown()) and true or false
    base.UpdateTextVisibility(barObj, isHovering, hideCenter)
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
        textCenter:SetText(base.FormatProgressText(textFormat, repData.current, repData.max, repData.percent, nil, repData.remaining))

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
        local questAddon = ""
        if questData.totalQuestXP > 0 then
            questAddon = string_format(" |cffffbb33(+%s quests)|r", data.FormatNumber(questData.totalQuestXP))
        end

        textCenter:SetText(base.FormatProgressText(textFormat, currXP, maxXP, xpData.percent, questAddon, xpData.remaining))

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

    if challengePointsText then
        local unspent = 0
        if sfui.isCamelot and sfui.experience.challenges and sfui.experience.challenges.GetUnspentPoints then
            unspent = sfui.experience.challenges.GetUnspentPoints() or 0
        end
        if unspent > 0 then
            challengePointsText:SetText(tostring(unspent))
            challengePointsText:Show()
        else
            challengePointsText:SetText("")
            challengePointsText:Hide()
        end
    end

    UpdateTextVisibility(container:IsMouseOver())

    if sfui.experience.reputation and sfui.experience.reputation.UpdateValues then
        sfui.experience.reputation.UpdateValues()
    end
end

--- Create the experience status bar and component frames
--- @return Frame
function barModule.Create()
    if container then return container end

    barObj = base.CreateTrackedBar({
        globalName    = "SfuiExperienceBar",
        frameLevel    = 20,
        numSubBars    = 3,
        hasTicks      = true,
        textInset     = 8,
        styleKey      = "xp",
        registerTheme = true,
    })

    container = barObj.container
    restedBar = barObj.subBars[1]
    questBar = barObj.subBars[2]
    mainBar = barObj.subBars[3]
    textLeft = barObj.textLeft
    textCenter = barObj.textCenter
    textRight = barObj.textRight

    local fontFile = sfui.common.get_font_file()
    challengePointsText = barObj.textFrame:CreateFontString(nil, "OVERLAY")
    challengePointsText:SetFont(fontFile, 10, "")
    challengePointsText:SetPoint("CENTER", barObj.textFrame, "CENTER", 0, 0)
    challengePointsText:SetJustifyH("CENTER")
    challengePointsText:SetTextColor(1.0, 1.0, 1.0, 1.0)
    challengePointsText:SetShadowOffset(0, 0)
    challengePointsText:SetShadowColor(0, 0, 0, 0)
    challengePointsText:Hide()

    -- Mouse Interactions & Tooltip
    container:SetScript("OnEnter", function(self)
        UpdateTextVisibility(true)
        if sfui.experience.tooltip and sfui.experience.tooltip.OnEnter then
            sfui.experience.tooltip.OnEnter(self, currentMode)
        end
    end)

    container:SetScript("OnLeave", function()
        UpdateTextVisibility(false)
        if sfui.experience.tooltip and sfui.experience.tooltip.OnLeave then
            sfui.experience.tooltip.OnLeave()
        end
    end)

    container:SetScript("OnClick", function(_, button)
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

    base.AttachDragHandlers(barObj, false)

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
                local h = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "height", cfg.height or 8)) or 8
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
