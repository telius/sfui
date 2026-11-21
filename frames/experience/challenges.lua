local addonName, addon = ...
sfui = sfui or {}
if not sfui.isCamelot then return end
sfui.experience = sfui.experience or {}
sfui.experience.challenges = {}

local challenges = sfui.experience.challenges

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/experience/challenges.lua
--  Dedicated Camelot legacy challenges & points status bar
--  Tracks: Legacy Points (e.g. 16 / 81), unspent talent points, rank milestones
-- ══════════════════════════════════════════════════════════════════════════════

local _G = _G
local CreateFrame = _G.CreateFrame
local math_min = math.min
local math_max = math.max
local math_floor = math.floor
local string_format = string.format
local string_lower = string.lower
local pcall = _G.pcall
local tostring = _G.tostring
local IsShiftKeyDown = _G.IsShiftKeyDown
local InCombatLockdown = _G.InCombatLockdown
local C_MajorFactions = _G.C_MajorFactions
local C_Traits = _G.C_Traits
local Constants = _G.Constants
local ChatEdit_GetActiveWindow = _G.ChatEdit_GetActiveWindow
local ChatFrame_OpenChat = _G.ChatFrame_OpenChat

local LEGACY_FACTION_ID = 2802
local LEGACY_POINTS_CURRENCY_ID = 4225

-- ─── Static Output Cache Tables (Zero-allocation on hot path) ───────────────
local _challengeData = {}
local _challengeColor = { 0.08, 0.72, 0.22, 1.0 }

local base = sfui.experience.base
local chalBarObj = nil
local challengesContainer = nil
local challengesBar = nil
local textLeft = nil
local textCenter = nil
local textRight = nil

--- Check if the camelot legacy challenge system is supported by the client
--- @return boolean
function challenges.IsSupported()
    return (sfui.isCamelot == true)
        or (sfui.version and sfui.version.camelot == true)
        or (sfui.compat and sfui.compat.is_camelot == true)
        or (_G.ToggleLegacyChallenges ~= nil)
        or (_G.LegacySystemFrame_LoadUI ~= nil)
        or (_G.LegacySystem ~= nil)
        or (_G.Constants and _G.Constants.LegacyConsts ~= nil)
end

--- Check if the camelot legacy challenge system is available and active
--- @return boolean
function challenges.IsAvailable()
    if not challenges.IsSupported() then return false end

    local enabled = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "trackLegacy", false))
    if enabled == false then return false end

    return true
end

--- Query unspent legacy challenge points available to spend
--- @return number
function challenges.GetUnspentPoints()
    if not challenges.IsSupported() then return 0 end

    if C_Traits and C_Traits.GetConfigIDByTreeID and C_Traits.GetTreeCurrencyInfo then
        local treeID = (Constants and Constants.LegacyConsts and Constants.LegacyConsts.LEGACY_TREE_PROFESSIONS_ID) or 1187
        local okConf, configID = pcall(C_Traits.GetConfigIDByTreeID, treeID)
        if okConf and configID then
            local okTree, treeInfo = pcall(C_Traits.GetTreeCurrencyInfo, configID, treeID, false)
            if okTree and treeInfo and treeInfo[1] and treeInfo[1].quantity then
                return treeInfo[1].quantity
            end
        end
    end

    if _G.LegacySystem and _G.LegacySystem.GetCurrencyInfo then
        local ok, cInfo = pcall(_G.LegacySystem.GetCurrencyInfo)
        if ok and cInfo and cInfo.quantity then
            return cInfo.quantity
        end
    end

    return 0
end

--- Query active legacy challenge points progress
--- @return table
function challenges.GetData()
    if not challenges.IsAvailable() then
        _challengeData.hasData = false
        _challengeData.name = nil
        _challengeData.level = 0
        _challengeData.maxLevel = 81
        _challengeData.current = 0
        _challengeData.max = 1
        _challengeData.remaining = 1
        _challengeData.percent = 0
        _challengeData.unspent = 0
        _challengeData.isCapped = false
        _challengeData.standingText = "0 / 0"
        _challengeData.nextRewardName = nil
        _challengeData.nextRewardDesc = nil
        _challengeData.legacyPoints = nil
        return _challengeData
    end

    if not _G.LegacySystem then
        if _G.LegacySystemFrame_LoadUI then
            pcall(_G.LegacySystemFrame_LoadUI)
        elseif C_AddOns and C_AddOns.LoadAddOn then
            pcall(C_AddOns.LoadAddOn, "Blizzard_LegacySystem")
        end
    end

    local fID = (Constants and Constants.LegacyConsts and Constants.LegacyConsts.LEGACY_REWARD_TRACK_FACTION_ID) or LEGACY_FACTION_ID
    local traitCurrencyID = (Constants and Constants.LegacyConsts and Constants.LegacyConsts.LEGACY_POINTS_TRAIT_CURRENCY_ID) or LEGACY_POINTS_CURRENCY_ID

    -- 1. Query earned points (renown level in faction 2802)
    local earned = 0
    if C_MajorFactions and C_MajorFactions.GetCurrentRenownLevel then
        local ok, lvl = pcall(C_MajorFactions.GetCurrentRenownLevel, fID)
        if ok and lvl and lvl > 0 then
            earned = lvl
        end
    end

    -- 2. Query total available points across the legacy system (e.g. 81)
    local totalAvailable = 0
    if C_Traits and C_Traits.GetMaxAvailableTraitCurrency then
        local ok, maxPoints = pcall(C_Traits.GetMaxAvailableTraitCurrency, traitCurrencyID, false)
        if ok and maxPoints and maxPoints > 0 then
            totalAvailable = maxPoints
        end
    end

    -- 3. Query unspent legacy trait points and seasonal cap directly from C_Traits (live C API)
    local unspent = 0
    local hasLiveTraitInfo = false
    if C_Traits and C_Traits.GetConfigIDByTreeID and C_Traits.GetTreeCurrencyInfo then
        local treeID = (Constants and Constants.LegacyConsts and Constants.LegacyConsts.LEGACY_TREE_PROFESSIONS_ID) or 1187
        local okConf, configID = pcall(C_Traits.GetConfigIDByTreeID, treeID)
        if okConf and configID then
            local okTree, treeInfo = pcall(C_Traits.GetTreeCurrencyInfo, configID, treeID, false)
            if okTree and treeInfo and treeInfo[1] then
                hasLiveTraitInfo = true
                if treeInfo[1].quantity then
                    unspent = treeInfo[1].quantity
                end
                if totalAvailable <= 0 and treeInfo[1].maxQuantity and treeInfo[1].maxQuantity > 0 then
                    totalAvailable = treeInfo[1].maxQuantity
                end
            end
        end
    end

    -- Fallback to LegacySystem currency info if C_Traits tree config isn't ready yet
    if not hasLiveTraitInfo and _G.LegacySystem and _G.LegacySystem.GetCurrencyInfo then
        local ok, cInfo = pcall(_G.LegacySystem.GetCurrencyInfo)
        if ok and cInfo then
            if earned <= 0 and cInfo.renownCurrency and cInfo.renownCurrency > 0 then
                earned = cInfo.renownCurrency
            end
            if cInfo.quantity then
                unspent = cInfo.quantity
            end
            if totalAvailable <= 0 and cInfo.maxQuantity and cInfo.maxQuantity > 0 then
                totalAvailable = cInfo.maxQuantity
            end
        end
    end

    if totalAvailable <= 0 then
        totalAvailable = 81
    end

    local isCapped = (earned >= totalAvailable)
    local remaining = math_max(0, totalAvailable - earned)
    local percent = math_min(100, math_max(0, (earned / totalAvailable) * 100))

    local name = "legacy points"
    local standingText = string_format("%d / %d", earned, totalAvailable)

    -- Query next milestone reward if available
    local nextRewardName = nil
    local nextRewardDesc = nil
    if not isCapped and C_MajorFactions and C_MajorFactions.GetRenownRewardsForLevel then
        local ok, rewards = pcall(C_MajorFactions.GetRenownRewardsForLevel, fID, earned + 1)
        if ok and rewards and rewards[1] then
            if rewards[1].name then
                nextRewardName = string_lower(rewards[1].name)
            end
            if rewards[1].description then
                nextRewardDesc = string_lower(rewards[1].description)
            end
        end
    end

    local cfg = sfui.config and sfui.config.experience
    local c = (cfg and cfg.colors and cfg.colors.legacy) or { 0.08, 0.72, 0.22, 1.0 }
    _challengeColor[1], _challengeColor[2], _challengeColor[3], _challengeColor[4] = c[1] or 0.08, c[2] or 0.72, c[3] or 0.22, c[4] or 1.0

    _challengeData.hasData = true
    _challengeData.factionID = fID
    _challengeData.traitCurrencyID = traitCurrencyID
    _challengeData.name = name
    _challengeData.level = earned
    _challengeData.maxLevel = totalAvailable
    _challengeData.current = earned
    _challengeData.max = totalAvailable
    _challengeData.remaining = remaining
    _challengeData.percent = percent
    _challengeData.unspent = unspent
    _challengeData.isCapped = isCapped
    _challengeData.standingText = standingText
    _challengeData.nextRewardName = nextRewardName
    _challengeData.nextRewardDesc = nextRewardDesc
    _challengeData.legacyPoints = unspent
    _challengeData.color = _challengeColor

    return _challengeData
end

--- Set status bar texture directly
--- @param tex string|nil
function challenges.SetBarTexture(tex)
    base.SetBarTexture(chalBarObj, tex)
end

--- Get challenges container frame
--- @return Frame|nil
function challenges.GetFrame()
    return challengesContainer
end

--- Apply theme styling to the challenges bar
function challenges.ApplyTheme()
    base.ApplyTheme(chalBarObj, "xp")
end

local CHAL_UNLOCK_OPTS = {
    bgColor         = { 0.08, 0.72, 0.22, 0.45 },
    borderColor     = { 0.2, 0.9, 0.3, 1 },
    label           = "|cff14b83bchallenges bar|r |cffaaaaaa(drag to move)|r",
    dragMovesExpBar = true,
    onLockUpdate    = function()
        challenges.UpdateValues()
    end,
}

--- Set unlocked dragging state and toggle visual mover overlay for challenges bar
--- @param unlocked boolean
function challenges.SetUnlocked(unlocked)
    base.SetUnlocked(chalBarObj, unlocked, CHAL_UNLOCK_OPTS)
end

--- Update 20-segment tick marks
--- @param innerWidth number
--- @param innerHeight number
local function UpdateTicks(innerWidth, innerHeight)
    base.UpdateTicks(chalBarObj, innerWidth, innerHeight)
end

--- Update text display visibility based on mouseover setting
local function UpdateTextVisibility(isHovering)
    base.UpdateTextVisibility(chalBarObj, isHovering)
end

--- Update layout and docking position relative to experience or reputation bars
function challenges.UpdateLayout()
    if not challengesContainer then
        if challenges.Create then
            challenges.Create()
        else
            return
        end
    end

    local cfg = sfui.config.experience or {}
    local width = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "width", cfg.width or 460)) or 460
    local barHeight = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "challengesHeight", cfg.challengesHeight or 12)) or 12

    challengesContainer:SetSize(width, barHeight)
    challengesContainer:ClearAllPoints()

    local expBar = sfui.experience.bar and sfui.experience.bar.GetFrame and sfui.experience.bar.GetFrame()
    local repBar = sfui.experience.reputation and sfui.experience.reputation.GetFrame and sfui.experience.reputation.GetFrame()

    local isExpShown = expBar and expBar:IsShown() and expBar:GetAlpha() > 0
    local isRepShown = repBar and repBar:IsShown() and repBar:GetAlpha() > 0

    -- Dock dynamically above the topmost active bar
    local anchorFrame = nil
    local repOnTop = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "repOnTop", cfg.repOnTop ~= false))
    if repOnTop == nil then repOnTop = true end

    if repOnTop then
        if isRepShown then
            anchorFrame = repBar
        elseif isExpShown then
            anchorFrame = expBar
        end
    else
        if isExpShown then
            anchorFrame = expBar
        elseif isRepShown then
            anchorFrame = repBar
        end
    end

    if anchorFrame then
        challengesContainer:SetHeight(barHeight)
        challengesContainer:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, 2)
        challengesContainer:SetPoint("BOTTOMRIGHT", anchorFrame, "TOPRIGHT", 0, 2)
    else
        -- Take primary bottom position if XP and Rep bars are both hidden
        challengesContainer:SetSize(width, barHeight)
        local pos = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "pos", cfg.pos)) or cfg.pos or { point = "BOTTOM", x = 0, y = 4 }
        challengesContainer:SetPoint(pos.point or "BOTTOM", _G.UIParent, pos.relativePoint or pos.point or "BOTTOM", pos.x or 0, pos.y or 4)
    end

    base.AnchorSubBars(chalBarObj)

    local actualWidth = challengesContainer:GetWidth()
    if not actualWidth or actualWidth <= 0 then
        actualWidth = width
    end
    UpdateTicks(actualWidth - 2, barHeight - 2)
    challenges.ApplyTheme()

    if sfui.experience.pet and sfui.experience.pet.UpdateLayout then
        sfui.experience.pet.UpdateLayout()
    end
end

--- Update values and visibility of challenges bar
function challenges.UpdateValues()
    if not challengesContainer then
        if challenges.Create then
            challenges.Create()
        else
            return
        end
    end

    local cfg = sfui.config.experience or {}
    local enabled = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "enabled", true))
    if enabled == nil then enabled = true end
    if not enabled then
        challengesContainer:Hide()
        return
    end

    if not challenges.IsAvailable() then
        challengesContainer:Hide()
        return
    end

    local showBar = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "showChallengesBar", false))
    if showBar == nil then showBar = false end

    -- Check if single bar mode is active (showDualBars is false)
    local showDual = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "showDualBars", cfg.showDualBars ~= false))
    if showDual == nil then showDual = true end

    if not showDual and not challengesContainer._isUnlocked then
        -- In single bar mode, challenges are displayed on the main bar when toggled
        challengesContainer:Hide()
        return
    end

    if not showBar and not challengesContainer._isUnlocked then
        challengesContainer:Hide()
        return
    end

    challengesContainer:Show()
    challengesContainer:SetAlpha(1.0)
    challenges.UpdateLayout()

    local textFormat = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "textFormat", cfg.textFormat or "PERCENT_CURRENT")) or "PERCENT_CURRENT"
    challenges.ApplyToBar(challengesBar, textLeft, textCenter, textRight, textFormat)

    UpdateTextVisibility(false)
end

--- Apply legacy challenge progress and styling to any status bar and text labels
--- @param statusBar StatusBar
--- @param tLeft FontString|nil
--- @param tCenter FontString|nil
--- @param tRight FontString|nil
--- @param textFormat string|nil
--- @return boolean success
function challenges.ApplyToBar(statusBar, tLeft, tCenter, tRight, textFormat)
    if not statusBar then return false end

    local data = challenges.GetData()
    if not data or not data.hasData then return false end

    statusBar:Show()
    statusBar:SetMinMaxValues(0, data.max)
    statusBar:SetValue(data.current)
    statusBar:SetStatusBarColor(data.color[1], data.color[2], data.color[3], data.color[4] or 1.0)

    local formatNumber = (sfui.experience.data and sfui.experience.data.FormatNumber) or tostring

    -- Text: Left = Faction name & rank
    if tLeft then
        tLeft:SetText(string_format("%s (%s)", data.name, data.standingText))
    end

    -- Text: Center = Current / Max (Percent)
    if tCenter then
        tCenter:SetText(base.FormatProgressText(textFormat, data.current, data.max, data.percent, nil, data.remaining))
    end

    -- Text: Right = Remaining or completed
    if tRight then
        if data.isCapped then
            tRight:SetText("completed")
        else
            tRight:SetText(string_format("-%s", formatNumber(data.remaining)))
        end
    end

    return true
end

--- Render rich legacy challenge tooltip content
--- @param tip GameTooltip
function challenges.RenderTooltip(tip)
    if not tip then return end

    local data = challenges.GetData()
    if not data or not data.hasData then
        tip:AddLine("legacy challenges", 1, 1, 1)
        tip:AddLine("not unlocked or unavailable on this character", 0.7, 0.7, 0.7)
        tip:Show()
        return
    end

    local formatCommas = (sfui.experience.data and sfui.experience.data.FormatCommas) or tostring
    local col = data.color or { 0.08, 0.72, 0.22 }

    -- Header line: Name & rank
    tip:AddDoubleLine("legacy challenges", string_format("%d / %d points", data.current, data.max), col[1], col[2], col[3], col[1], col[2], col[3])
    tip:AddLine(" ")

    -- Progress details
    local curStr = formatCommas(data.current)
    local maxStr = formatCommas(data.max)
    tip:AddDoubleLine("points earned:", string_format("%s / %s (%.1f%%)", curStr, maxStr, data.percent), 0.85, 0.85, 0.85, 1, 1, 1)

    if data.isCapped then
        tip:AddLine("all legacy points earned!", 0.2, 1.0, 0.2)
    else
        tip:AddDoubleLine("points remaining:", string_format("%s", formatCommas(data.remaining)), 0.85, 0.85, 0.85, 1, 0.8, 0.2)
    end

    -- Unspent talent points
    if data.unspent and data.unspent > 0 then
        tip:AddLine(" ")
        tip:AddDoubleLine("unspent talent points:", tostring(data.unspent), 0.85, 0.85, 0.85, 0.2, 0.85, 1.0)
    end

    -- Next rank reward preview
    if data.nextRewardName then
        tip:AddLine(" ")
        tip:AddDoubleLine("next reward:", data.nextRewardName, 0.85, 0.85, 0.85, 1.0, 0.85, 0.2)
        if data.nextRewardDesc and data.nextRewardDesc ~= "" then
            tip:AddLine(data.nextRewardDesc, 0.7, 0.7, 0.7, true)
        end
    end

    -- Interaction shortcuts
    tip:AddLine(" ")
    tip:AddLine("<shift-click to share progress in chat>", 0.5, 0.5, 0.5)
    tip:AddLine("<left-click to open legacy challenges>", 0.5, 0.5, 0.5)
    tip:AddLine("<right-click to open experience settings>", 0.5, 0.5, 0.5)

    tip:Show()
end

--- Build chat-shareable message string
--- @return string|nil
function challenges.GetShareMessage()
    local data = challenges.GetData()
    if not data or not data.hasData then return nil end

    local formatNumber = (sfui.experience.data and sfui.experience.data.FormatNumber) or tostring

    if data.isCapped then
        return string_format("sfui: legacy challenges — %d / %d points completed!", data.current, data.max)
    else
        return string_format("sfui: legacy challenges — %d / %d points (%.1f%%) — %s remaining",
            data.current,
            data.max,
            data.percent,
            formatNumber(data.remaining)
        )
    end
end

--- Share legacy progress into active chat box
function challenges.ShareToChat()
    local msg = challenges.GetShareMessage()
    if not msg then return end

    local editBox = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
    if editBox and editBox:IsShown() then
        editBox:Insert(msg)
    elseif ChatFrame_OpenChat then
        ChatFrame_OpenChat(msg)
    end
end

--- Create the dedicated challenges status bar
--- @return Frame
function challenges.Create()
    if challengesContainer then return challengesContainer end

    chalBarObj = base.CreateTrackedBar({
        globalName    = "SfuiChallengesBar",
        frameLevel    = 20,
        numSubBars    = 1,
        hasTicks      = true,
        textInset     = 8,
        startHidden   = true,
        styleKey      = "xp",
        registerTheme = true,
    })

    challengesContainer = chalBarObj.container
    challengesBar = chalBarObj.mainBar
    textLeft = chalBarObj.textLeft
    textCenter = chalBarObj.textCenter
    textRight = chalBarObj.textRight

    -- Mouse Interactions & Tooltip
    challengesContainer:SetScript("OnEnter", function(self)
        UpdateTextVisibility(true)
        local tip = (sfui.common and sfui.common.get_tooltip and sfui.common.get_tooltip()) or sfui.tooltip or _G.GameTooltip
        tip:SetOwner(self, "ANCHOR_TOP", 0, 6)
        tip:ClearLines()
        challenges.RenderTooltip(tip)
    end)

    challengesContainer:SetScript("OnLeave", function()
        UpdateTextVisibility(false)
        if sfui.common and sfui.common.hide_tooltip then
            sfui.common.hide_tooltip()
        else
            local tip = _G.GameTooltip
            if tip and tip:IsShown() then tip:Hide() end
        end
    end)

    challengesContainer:SetScript("OnClick", function(_, button)
        if InCombatLockdown and InCombatLockdown() then return end
        if IsShiftKeyDown() then
            challenges.ShareToChat()
        elseif button == "RightButton" then
            if sfui.toggle_options_panel then
                sfui.toggle_options_panel("experience")
            end
        elseif button == "LeftButton" then
            if _G.ToggleLegacyChallenges then
                _G.ToggleLegacyChallenges()
            elseif _G.LegacySystemFrame_LoadUI and _G.LegacySystemFrame_LoadUI() and _G.LegacySystemFrame then
                _G.LegacySystemFrame:ToggleChallenges()
            elseif _G.ToggleLegacySystemUI then
                _G.ToggleLegacySystemUI()
            elseif _G.LegacySystemFrame then
                if _G.LegacySystemFrame:IsShown() then
                    _G.LegacySystemFrame:Hide()
                else
                    _G.LegacySystemFrame:Show()
                end
            end
        end
    end)

    base.AttachDragHandlers(chalBarObj, true)

    challengesContainer:HookScript("OnShow", function()
        if sfui.experience.pet and sfui.experience.pet.UpdateLayout then
            sfui.experience.pet.UpdateLayout()
        end
    end)
    challengesContainer:HookScript("OnHide", function()
        if sfui.experience.pet and sfui.experience.pet.UpdateLayout then
            sfui.experience.pet.UpdateLayout()
        end
    end)

    challenges.ApplyTheme()
    challenges.UpdateLayout()
    UpdateTextVisibility(false)
    challenges.UpdateValues()

    return challengesContainer
end
