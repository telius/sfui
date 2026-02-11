local addonName, addon = ...
sfui.trackedbars = {}

local bars = {} -- Active sfui bars
local container
local issecretvalue = sfui.common.issecretvalue

-- Reusable tables (performance optimization)
local standardBars = {}
local activeCooldownIDs = {}

-- Helper to get tracking config for a specific ID
local configCache = {}
local function GetTrackedBarConfig(cooldownID)
    if configCache[cooldownID] then return configCache[cooldownID] end

    local proxy = setmetatable({}, {
        __index = function(_, k)
            -- 1. Check DB (User Customization)
            if SfuiDB and SfuiDB.trackedBars then
                local entry = SfuiDB.trackedBars[cooldownID]
                if not entry then entry = SfuiDB.trackedBars[tonumber(cooldownID)] end

                if entry then
                    local v = entry[k]
                    if v ~= nil then return v end
                end
            end

            -- 2. Check Defaults
            if sfui.config.trackedBars and sfui.config.trackedBars.defaults then
                local defaults = sfui.config.trackedBars.defaults
                local entry = defaults[cooldownID]
                if not entry then entry = defaults[tonumber(cooldownID)] end

                if entry then
                    local v = entry[k]
                    if v ~= nil then return v end
                end
            end
            return nil
        end
    })

    configCache[cooldownID] = proxy
    return proxy
end
sfui.trackedbars.GetConfig = GetTrackedBarConfig

-- Helper to determine max stacks for a bar
-- Checks in order: special cases -> user config -> charge info -> default
local function GetMaxStacksForBar(cooldownID, config, spellID)
    local cfg = sfui.config.trackedBars
    local maxStacks = cfg.defaultMaxStacks

    -- 1. Check user config override (highest priority)
    if config and config.maxStacks then
        return config.maxStacks
    end

    -- 2. Check for special case overrides
    if cfg.specialCases and cfg.specialCases[cooldownID] and cfg.specialCases[cooldownID].maxStacks then
        return cfg.specialCases[cooldownID].maxStacks
    end

    -- 3. Try to get from charge info (for charge-based abilities)
    if spellID and not issecretvalue(spellID) then
        pcall(function()
            local chargeInfo = C_Spell.GetSpellCharges(spellID)
            if chargeInfo and chargeInfo.maxCharges then
                maxStacks = chargeInfo.maxCharges
            end
        end)
    end

    return maxStacks
end
sfui.trackedbars.GetMaxStacks = GetMaxStacksForBar



local function CreateBar(cooldownID)
    local cfg = sfui.config.trackedBars
    -- Frame is the Backdrop/Container
    local bar = CreateFrame("Frame", nil, container, "BackdropTemplate")
    bar:SetSize(cfg.width, cfg.height)

    -- Backdrop styling (Flat, no border)
    bar:SetBackdrop({
        bgFile = sfui.config.textures.white,
        tile = true,
        tileSize = 32,
    })

    -- Status Bar
    local defaultColor = cfg.backdrop.color
    bar:SetBackdropColor(unpack(defaultColor))

    -- Status Bar
    bar.status = CreateFrame("StatusBar", nil, bar)
    bar.status:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
    bar.status:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -1, 1)
    bar.status:SetStatusBarTexture(sfui.config.textures.white)
    bar.status:SetStatusBarColor(unpack(sfui.config.colors.purple))

    -- Icon
    bar.icon = bar:CreateTexture(nil, "ARTWORK")
    bar.icon:SetSize(cfg.icon_size, cfg.icon_size)
    bar.icon:SetPoint("RIGHT", bar, "LEFT", cfg.icon_offset, 0)

    -- Text
    bar.name = bar.status:CreateFontString(nil, "OVERLAY")
    bar.name:SetFontObject(sfui.config.font_small)
    bar.name:SetPoint("LEFT", 5, 0)
    sfui.common.style_text(bar.name, nil, nil, "")

    bar.time = bar.status:CreateFontString(nil, "OVERLAY")
    bar.time:SetFontObject(sfui.config.font_small)
    bar.time:SetPoint("RIGHT", -5, 0)
    sfui.common.style_text(bar.time, nil, nil, "")

    -- Stack Count
    bar.count = bar.status:CreateFontString(nil, "OVERLAY")
    bar.count:SetFontObject(sfui.config.font_small)
    bar.count:SetPoint("CENTER", bar.icon, "CENTER", 0, 0)
    sfui.common.style_text(bar.count, nil, nil, "")

    -- Stack Segments (for stack mode display)
    bar.segments = {}
    for i = 1, cfg.maxSegments do
        local seg = CreateFrame("StatusBar", nil, bar)
        seg:SetStatusBarTexture(sfui.config.textures.white)
        seg:SetStatusBarColor(unpack(sfui.config.colors.purple))
        seg:SetMinMaxValues(0, 1)
        seg:SetValue(1)
        seg:Hide()

        -- Segment background
        seg.bg = seg:CreateTexture(nil, "BACKGROUND")
        seg.bg:SetAllPoints(seg)
        seg.bg:SetColorTexture(0, 0, 0, 0.5)

        bar.segments[i] = seg
    end

    bar.cooldownID = cooldownID

    bar:EnableMouse(true)
    bar:SetScript("OnEnter", function(self)
        if GameTooltip and self.spellID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self.spellID)
            GameTooltip:Show()
        end
    end)
    bar:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    return bar
end

-- Helper function to apply common bar styling and positioning
-- Reduces duplicate code between stack mode and standard mode
-- Helper function to setup bar content (text, icons, stack mode logic) state
local function SetupBarState(bar, config, cfg)
    local isStackMode = config and config.stackMode or false
    local isAttached = config and config.stackAboveHealth or false
    local showStacksText = config and config.showStacksText or false

    if isStackMode then
        for i = 1, cfg.maxSegments do bar.segments[i]:Hide() end
        bar.status:Show(); bar.name:Show(); bar.time:Show(); bar.icon:Show(); bar.count:Hide()
        local currentStacks = tonumber(bar.count:GetText()) or 0
        local maxStacks = GetMaxStacksForBar(bar.cooldownID, config, bar.spellID)
        bar.status:SetMinMaxValues(0, maxStacks)
        bar.status:SetValue(currentStacks)

        -- Center time in Stack Mode
        bar.time:ClearAllPoints()
        bar.time:SetPoint("CENTER", bar.status, "CENTER", 0, 0)
        sfui.common.style_text(bar.time, nil, cfg.fonts.stackModeDurationSize, "")

        if config and config.showName == false then bar.name:Hide() end
    else
        for i = 1, cfg.maxSegments do bar.segments[i]:Hide() end
        -- Standard Mode
        bar.status:Show(); bar.name:Show(); bar.time:Show(); bar.icon:Show()
        bar.count:ClearAllPoints()
        bar.count:SetPoint("CENTER", bar.icon, "CENTER", 0, 0)
        sfui.common.style_text(bar.count, nil, nil)

        if config and config.showName == false then bar.name:Hide() end
        if config and config.showDuration == false then bar.time:Hide() end
        if config and config.showStacks == false then bar.count:Hide() end

        -- Text Position Logic: Center if Attached or Stacks Text, Right if Standard
        bar.time:ClearAllPoints()
        if isAttached or showStacksText then
            bar.time:SetPoint("CENTER", bar.status, "CENTER", 0, 0)
            sfui.common.style_text(bar.time, nil, cfg.fonts.stackModeDurationSize, "")
        else
            bar.time:SetPoint("RIGHT", -5, 0)
            -- Use default small font style implicitly or re-apply if needed (assuming CreateBar set it)
        end
    end

    -- Icon Visibility Override for Attached bars
    if isAttached then
        bar.icon:Hide()
        bar.count:Hide()                            -- Hide count on icon position
    else
        if not isStackMode then bar.icon:Show() end -- Restore
    end

    -- Hide count if showing stacks as main text (redundant)
    if showStacksText then
        bar.count:Hide()
    end

    local color = config and config.color or sfui.config.colors.purple
    if color then
        bar.status:SetStatusBarColor(color.r or color[1], color.g or color[2], color.b or color[3])
    end
end

-- Helper for Standard Bar Positioning
local function ApplyBarStyling(bar, yOffset, config, cfg)
    bar:SetSize(cfg.width, cfg.height)
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOM", container, "BOTTOM", 0, yOffset)
    local pad = cfg.backdrop.padding
    bar.status:ClearAllPoints()
    bar.status:SetPoint("TOPLEFT", pad, -pad)
    bar.status:SetPoint("BOTTOMRIGHT", -pad, pad)
    bar:SetBackdropColor(unpack(cfg.backdrop.color))
    return yOffset + (cfg.height + cfg.spacing)
end

-- Helper to get sort index removed


local function UpdateLayout()
    local cfg = sfui.config.trackedBars
    wipe(standardBars)
    local attachedBars = {}

    for _, bar in pairs(bars) do
        if bar:IsShown() then
            local config = GetTrackedBarConfig(bar.cooldownID)
            SetupBarState(bar, config, cfg)

            if config and config.stackAboveHealth then
                table.insert(attachedBars, bar)
            else
                table.insert(standardBars, bar)
            end
        end
    end

    -- Simple Sort (Priority > Name)
    local function SimpleSort(a, b)
        local cA = GetTrackedBarConfig(a.cooldownID)
        local cB = GetTrackedBarConfig(b.cooldownID)
        local pA = (cA and cA.priority) or 0
        local pB = (cB and cB.priority) or 0
        if pA ~= pB then return pA < pB end

        local nA = C_Spell.GetSpellName(a.cooldownID) or ""
        local nB = C_Spell.GetSpellName(b.cooldownID) or ""
        return nA < nB
    end

    -- 1. Standard Layout
    table.sort(standardBars, SimpleSort)
    local yOffset = 0
    for _, bar in ipairs(standardBars) do
        local config = GetTrackedBarConfig(bar.cooldownID)
        bar:SetParent(container)
        yOffset = ApplyBarStyling(bar, yOffset, config, cfg)
    end

    -- 2. Attached Layout
    if #attachedBars > 0 then
        table.sort(attachedBars, SimpleSort)

        local spacing = sfui.config.barLayout.spacing or 1
        local anchor = _G["sfui_bar0_Backdrop"]
        local isBar1 = false

        if _G["sfui_bar1_Backdrop"] and _G["sfui_bar1_Backdrop"]:IsShown() then
            anchor = _G["sfui_bar1_Backdrop"]
            isBar1 = true
        elseif _G["sfui_runeBar"] then
            anchor = _G["sfui_runeBar"]
            isBar1 = true
        end

        if anchor then
            for _, bar in ipairs(attachedBars) do
                bar:SetParent(UIParent)
                bar:ClearAllPoints()

                local width, height = cfg.width, cfg.height
                if not isBar1 then
                    -- Acting as Bar1
                    width = sfui.config.healthBar.width * 0.8
                    height = 20
                    isBar1 = true -- Stack next ones normally
                end

                bar:SetSize(width, height)
                bar:SetPoint("BOTTOM", anchor, "TOP", 0, spacing)

                -- Style Fix
                local pad = cfg.backdrop.padding
                bar.status:ClearAllPoints()
                bar.status:SetPoint("TOPLEFT", pad, -pad)
                bar.status:SetPoint("BOTTOMRIGHT", -pad, pad)
                bar:SetBackdropColor(unpack(cfg.backdrop.color))

                anchor = bar
            end
        end
    end
end

-- Update Position External Reference
function sfui.trackedbars.UpdatePosition()
    if not container then return end
    local x = (SfuiDB and SfuiDB.trackedBarsX) or (sfui.config.trackedBars.anchor and sfui.config.trackedBars.anchor.x) or
        -300
    local y = (SfuiDB and SfuiDB.trackedBarsY) or (sfui.config.trackedBars.anchor and sfui.config.trackedBars.anchor.y) or
        300

    container:ClearAllPoints()
    container:SetPoint("BOTTOM", UIParent, "BOTTOM", x, y)
end

function sfui.trackedbars.SetColor(cooldownID, r, g, b)
    local barDB = sfui.common.ensure_tracked_bar_db(cooldownID)
    barDB.color = { r = r, g = g, b = b }
    UpdateLayout() -- Refresh to apply color
end

local barPool = {}

local function RecycleBar(bar)
    bar:Hide()
    bar:ClearAllPoints()
    bar:SetParent(nil)
    bar.cooldownID = nil
    table.insert(barPool, bar)
end

local function GetBarFromPool(cooldownID)
    local bar = table.remove(barPool)
    if bar then
        bar:SetParent(container)
        bar.cooldownID = cooldownID
        return bar
    end
    return nil
end

function sfui.trackedbars.RemoveBar(cooldownID, suppressLayout)
    if bars and bars[cooldownID] then
        RecycleBar(bars[cooldownID])
        bars[cooldownID] = nil
        if not suppressLayout then
            UpdateLayout()
        end
    end
end

-- Helper: Determine if bar should be visible based on settings
local function ShouldBarBeVisible(config, blizzFrame, isStackModeWithStacks, hideInactive)
    if isStackModeWithStacks then
        -- Always show stack mode bars with active stacks
        return true
    elseif hideInactive then
        -- Only show if Blizzard shows it (it's active)
        return blizzFrame:IsShown()
    else
        -- Show all bars regardless of active state
        return true
    end
end

-- Helper: Sync bar data from Blizzard frame
local function SyncBarData(myBar, blizzFrame, config, isStackMode, id)
    local cfg = sfui.config.trackedBars

    myBar.spellID = blizzFrame.spellID or (blizzFrame.info and blizzFrame.info.spellID)

    -- Mirror Icon and Desaturation
    if blizzFrame.Icon and blizzFrame.Icon.Icon then
        myBar.icon:SetTexture(blizzFrame.Icon.Icon:GetTexture())

        -- Detect Desaturation (Inactive State)
        if blizzFrame.Icon.Icon.GetDesaturated and blizzFrame.Icon.Icon:GetDesaturated() then
            myBar.icon:SetDesaturated(true)
        else
            myBar.icon:SetDesaturated(false)
        end
    end

    -- Stack data gathering
    local currentStacks = nil
    local maxStacks = GetMaxStacksForBar(id, config, myBar.spellID)

    -- 1. Try Aura Data (Always preferred over scraping text)
    if sfui.common.HasAuraInstanceID(blizzFrame.auraInstanceID) then
        local unit = blizzFrame.auraDataUnit or "player"
        local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, blizzFrame.auraInstanceID)
        if auraData then
            if sfui.common.IsNumericAndPositive(auraData.applications) then
                currentStacks = auraData.applications
            end
            -- Update name safely
            if auraData.name then myBar.name:SetText(auraData.name) end
        end
    end

    -- 2. Fallback to Text (Blizzard's Display) - ONLY IF SAFE
    -- Text access on restricted frames returns "secret value" which crashes on comparison
    if not currentStacks and not InCombatLockdown() and not IsInInstance() then
        pcall(function()
            if blizzFrame.Icon and blizzFrame.Icon.Applications then
                local text = blizzFrame.Icon.Applications:GetText()
                -- Avoid 'secret value' errors by removing comparison
                if text and not issecretvalue(text) and type(text) == "string" then
                    currentStacks = tonumber(text)
                end
            end
        end)
    end

    -- Set Name (Config > Aura Data > Blizzard Text)
    if config and config.name then
        sfui.common.SafeSetText(myBar.name, config.name)
    elseif not blizzFrame.auraInstanceID and blizzFrame.Bar and blizzFrame.Bar.Name then -- Only use blizz text if no aura data
        local bName = blizzFrame.Bar.Name:GetText()
        if bName and not issecretvalue(bName) then
            sfui.common.SafeSetText(myBar.name, bName)
        end
    end

    -- Default to 0 and Ensure Safety
    -- Force sanitize currentStacks to be a clean number to prevent secret value crashes
    if sfui.common.IsNumericAndPositive(currentStacks) then
        currentStacks = tonumber(tostring(currentStacks)) or 0
    else
        currentStacks = 0
    end
    myBar.currentStacks = currentStacks -- Store for OnUpdate access

    -- MAIN BAR UPDATE LOGIC
    if isStackMode then
        -- STACK MODE: Bar represents Stack Count
        myBar.status:SetMinMaxValues(0, maxStacks)
        myBar.status:SetValue(currentStacks)
        myBar.count:SetText(currentStacks) -- Hidden but used for visibility logic

        -- FORCE HIDE BLIZZ BAR COMPONENTS if strict
        if blizzFrame.Bar then blizzFrame.Bar:SetAlpha(0) end

        -- Sync Time Text
        if blizzFrame.Bar then
            local text = ""
            pcall(function()
                text = blizzFrame.Bar.Duration and blizzFrame.Bar.Duration:GetText() or ""
            end)
            if config and config.showStacksText then
                text = sfui.common.SafeFormatDuration(currentStacks, 0)
            end
            sfui.common.SafeSetText(myBar.time, text)
        end
    else
        -- NORMAL MODE: Bar represents Duration (Copy from Blizzard)
        if blizzFrame.Bar then
            pcall(function()
                local min, max = blizzFrame.Bar:GetMinMaxValues()
                local val = blizzFrame.Bar:GetValue()
                myBar.status:SetMinMaxValues(min, max)
                sfui.common.SafeSetValue(myBar.status, val)

                local text = blizzFrame.Bar.Duration and blizzFrame.Bar.Duration:GetText() or ""
                if config and config.showStacksText then
                    text = sfui.common.SafeFormatDuration(currentStacks, 0)
                end
                sfui.common.SafeSetText(myBar.time, text)
            end)
        end

        if sfui.common.IsNumericAndPositive(currentStacks) then
            myBar.count:SetText(sfui.common.SafeFormatDuration(currentStacks, 0))
        else
            myBar.count:SetText("")
        end
    end
end

local function SyncWithBlizzard()
    if not BuffBarCooldownViewer or not BuffBarCooldownViewer.itemFramePool then return end

    wipe(activeCooldownIDs)
    local layoutNeeded = false

    -- Global Hide Check
    -- We use our own OOC logic to avoid touching Blizzard's protected viewer state if it's crashing.
    local mustHide = false
    if SfuiDB and SfuiDB.hideOOC and not InCombatLockdown() then
        mustHide = true
    end

    if mustHide then
        for id, bar in pairs(bars) do
            if bar:IsShown() then
                bar:Hide()
                layoutNeeded = true
            end
        end
        if layoutNeeded then UpdateLayout() end
        return -- Skip processing updates if everything is hidden globally
    end

    -- Process Blizzard Frames
    pcall(function()
        for blizzFrame in BuffBarCooldownViewer.itemFramePool:EnumerateActive() do
            if blizzFrame.cooldownID then
                blizzFrame:SetAlpha(0) -- Hide Blizzard frame so only ours is visible
                local id = blizzFrame.cooldownID
                activeCooldownIDs[id] = true

                if not bars[id] then
                    local pooledBar = GetBarFromPool(id)
                    if pooledBar then
                        bars[id] = pooledBar
                    else
                        bars[id] = CreateBar(id)
                    end
                    layoutNeeded = true
                end

                local myBar = bars[id]
                local config = GetTrackedBarConfig(id) -- Cache config lookup once
                local isStackMode = config and config.stackMode or false

                -- Sync Visibility
                local hideInactive = SfuiDB and SfuiDB.hideInactive ~= false -- Default to True if nil

                -- Check if this is a stack mode bar with active stacks
                local isStackModeWithStacks = false
                if isStackMode then
                    local currentStacks = tonumber(myBar.count:GetText()) or 0
                    if currentStacks > 0 then
                        isStackModeWithStacks = true
                    end
                end

                local shouldShow = ShouldBarBeVisible(config, blizzFrame, isStackModeWithStacks, hideInactive)

                if shouldShow then
                    if not myBar:IsShown() then
                        myBar:Show()
                        layoutNeeded = true
                    end
                else
                    if myBar:IsShown() then
                        myBar:Hide()
                        layoutNeeded = true
                    end
                end

                -- Sync all bar data from Blizzard
                SyncBarData(myBar, blizzFrame, config, isStackMode, id)
            end
        end
    end)

    -- Cleanup
    for id, bar in pairs(bars) do
        if not activeCooldownIDs[id] then
            sfui.trackedbars.RemoveBar(id, true)
            layoutNeeded = true
        end
    end

    if layoutNeeded then
        UpdateLayout()
    end
end



-- Public function to trigger visibility update from options panel
function sfui.trackedbars.UpdateVisibility()
    if SyncWithBlizzard then
        SyncWithBlizzard()
    end
end

-- Hook-based updates (v2.10.0 pattern from ArcUI)
local hookedFrames = {}
local function HookBlizzardFrame(frame)
    if not frame or hookedFrames[frame] then return end
    hookedFrames[frame] = true

    if frame.RefreshData then
        hooksecurefunc(frame, "RefreshData", function() SyncWithBlizzard() end)
    end
    if frame.RefreshApplications then
        hooksecurefunc(frame, "RefreshApplications", function() SyncWithBlizzard() end)
    end
    if frame.SetAuraInstanceInfo then
        hooksecurefunc(frame, "SetAuraInstanceInfo", function() SyncWithBlizzard() end)
    end
end

-- Public function to force layout update (e.g., when settings change)
function sfui.trackedbars.ForceLayoutUpdate()
    UpdateLayout()
end

function sfui.trackedbars.initialize()
    if container then return end
    local loaded, reason = C_AddOns.LoadAddOn("Blizzard_CooldownViewer")
    container = CreateFrame("Frame", "SfuiTrackedBarsContainer", UIParent)
    local cfg = sfui.config.trackedBars
    container:SetSize(cfg.width, cfg.height)

    sfui.common.ensure_tracked_bar_db() -- Initialize DB structure

    -- Set visibility defaults from config if not already set
    if SfuiDB.hideOOC == nil then
        SfuiDB.hideOOC = cfg.hideOOC ~= nil and cfg.hideOOC or false
    end
    if SfuiDB.hideInactive == nil then
        SfuiDB.hideInactive = cfg.hideInactive ~= nil and cfg.hideInactive or true
    end

    -- Position
    sfui.trackedbars.UpdatePosition()

    -- Throttled OnUpdate for smooth bar progress
    local updateThrottle = 0
    container:SetScript("OnUpdate", function(self, elapsed)
        updateThrottle = updateThrottle + elapsed
        if updateThrottle >= cfg.updateThrottle then
            updateThrottle = 0

            -- Update all visible bars from Blizzard's data
            if BuffBarCooldownViewer and BuffBarCooldownViewer.itemFramePool then
                pcall(function()
                    for blizzFrame in BuffBarCooldownViewer.itemFramePool:EnumerateActive() do
                        if blizzFrame.cooldownID then
                            local myBar = bars[blizzFrame.cooldownID]
                            -- Only update if bar exists AND is shown (performance optimization)
                            if myBar and myBar:IsShown() and blizzFrame.Bar then
                                -- Check Stack Mode
                                local config = GetTrackedBarConfig(blizzFrame.cooldownID) -- Cache config
                                local isStackMode = config and config.stackMode or false

                                -- Only copy bar animation values if NOT in stack mode
                                if not isStackMode then
                                    local val = blizzFrame.Bar:GetValue()
                                    sfui.common.SafeSetValue(myBar.status, val)
                                end

                                -- Update duration/name text (always safe to sync text)
                                -- Note: Name is set in SyncBarData from config, avoiding frame scraping
                                if blizzFrame.Bar.Duration then
                                    local text = blizzFrame.Bar.Duration:GetText() or ""
                                    if config and config.showStacksText then
                                        text = tostring(myBar.currentStacks or 0)
                                    end
                                    sfui.common.SafeSetText(myBar.time, text)
                                end
                            end
                        end
                    end
                end)
            end
        end
    end)

    -- Event-driven updates instead of OnUpdate polling
    -- Hook into Blizzard's frames for instant updates (ArcUI approach)
    if BuffBarCooldownViewer and BuffBarCooldownViewer.itemFramePool then
        hooksecurefunc(BuffBarCooldownViewer.itemFramePool, "Acquire", function(_, frame)
            HookBlizzardFrame(frame)
        end)
        -- Hook existing frames
        for frame in BuffBarCooldownViewer.itemFramePool:EnumerateActive() do
            HookBlizzardFrame(frame)
        end
    end

    -- Hide Blizzard Frame
    if BuffBarCooldownViewer then
        -- Only hide, don't aggressively move/scale/strata it.
        -- The alpha(0) is enough to make it invisible.
        BuffBarCooldownViewer:SetAlpha(0)
        BuffBarCooldownViewer:EnableMouse(false)
        hooksecurefunc(BuffBarCooldownViewer, "Show", function(self)
            self:SetAlpha(0)
            self:EnableMouse(false)
        end)
        if BuffBarCooldownViewer:IsShown() then
            BuffBarCooldownViewer:SetAlpha(0)
            BuffBarCooldownViewer:EnableMouse(false)
        end
    end

    -- Hook into bars state for attachment updates
    if sfui.bars then
        hooksecurefunc(sfui.bars, "on_state_changed", function()
            -- Delay slightly to ensure bars have hidden/shown
            C_Timer.After(0.05, function()
                if sfui.trackedbars and sfui.trackedbars.ForceLayoutUpdate then
                    sfui.trackedbars.ForceLayoutUpdate()
                end
            end)
        end)
    end
end
