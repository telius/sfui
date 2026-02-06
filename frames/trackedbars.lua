local addonName, addon = ...
sfui.trackedbars = {}

local bars = {} -- Active sfui bars
local container

-- Helper to get tracking config for a specific ID
local function GetTrackedBarConfig(cooldownID)
    -- Check DB first (user customizations)
    if SfuiDB and SfuiDB.trackedBars and SfuiDB.trackedBars[cooldownID] then
        return SfuiDB.trackedBars[cooldownID]
    end

    -- Check config defaults (from config.lua)
    if sfui.config.trackedBars and sfui.config.trackedBars.defaults and sfui.config.trackedBars.defaults[cooldownID] then
        return sfui.config.trackedBars.defaults[cooldownID]
    end

    return nil
end

-- Definition of "Secondary Power Bar" behavior
local function ApplySecondaryBarStyle(bar, config, overrideParams)
    local parentName = "sfui_secondaryPowerBar_Backdrop"
    local fallbackName = "sfui_healthBar_Backdrop"

    local parent = _G[parentName]
    local anchorTarget = parent

    if not (parent and parent:IsShown()) then
        anchorTarget = _G[fallbackName]
    end

    if anchorTarget then
        bar:ClearAllPoints()

        local mult = sfui.pixelScale or 1
        local padding = 2
        local backdropColor = sfui.config.healthBar.backdrop.color or { 0, 0, 0, 0.5 }
        local height = 15 -- Default

        -- Pull from Secondary Power Bar Config
        if sfui.config.secondaryPowerBar then
            height = sfui.config.secondaryPowerBar.height or height
            if sfui.config.secondaryPowerBar.backdrop then
                padding = sfui.config.secondaryPowerBar.backdrop.padding or padding
                backdropColor = sfui.config.secondaryPowerBar.backdrop.color or backdropColor
            end
        end

        local widthRatio = 0.8

        -- Positioning
        if anchorTarget == parent then
            bar:SetPoint("CENTER", anchorTarget, "CENTER", 0, 0)
        else
            -- Fallback: Above Health Bar
            local spacing = sfui.config.barLayout.spacing or 1
            bar:SetPoint("BOTTOM", anchorTarget, "TOP", 0, spacing)
        end

        local w = anchorTarget:GetWidth() * widthRatio
        local scaledPadding = padding * mult

        bar:SetSize(w + (scaledPadding * 2), height + (scaledPadding * 2))
        bar:SetBackdropColor(unpack(backdropColor))

        bar.status:ClearAllPoints()
        bar.status:SetPoint("TOPLEFT", scaledPadding, -scaledPadding)
        bar.status:SetPoint("BOTTOMRIGHT", -scaledPadding, scaledPadding)

        return true -- Applied
    end
    return false
end

local function CreateBar(cooldownID)
    -- Frame is the Backdrop/Container
    local bar = CreateFrame("Frame", nil, container, "BackdropTemplate")
    bar:SetSize(200, 20)

    -- Backdrop styling (Flat, no border)
    bar:SetBackdrop({
        bgFile = sfui.config.textures.white,
        tile = true,
        tileSize = 32,
    })

    local defaultColor = sfui.config.healthBar.backdrop.color or { 0, 0, 0, 0.5 }
    bar:SetBackdropColor(unpack(defaultColor))

    -- Status Bar
    bar.status = CreateFrame("StatusBar", nil, bar)
    bar.status:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
    bar.status:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -1, 1)
    bar.status:SetStatusBarTexture(sfui.config.textures.white)
    bar.status:SetStatusBarColor(unpack(sfui.config.colors.purple))

    -- Icon
    bar.icon = bar:CreateTexture(nil, "ARTWORK")
    bar.icon:SetSize(20, 20)
    bar.icon:SetPoint("RIGHT", bar, "LEFT", -5, 0)

    -- Helper to styling text
    local function StyleText(fs)
        fs:SetTextColor(1, 1, 1, 1)
        local font, size, flags = fs:GetFont()
        fs:SetFont(font, size, "NONE")
        fs:SetShadowOffset(1, -1)
    end

    -- Text
    bar.name = bar.status:CreateFontString(nil, "OVERLAY")
    bar.name:SetFontObject(sfui.config.font_small)
    bar.name:SetPoint("LEFT", 5, 0)
    StyleText(bar.name)

    bar.time = bar.status:CreateFontString(nil, "OVERLAY")
    bar.time:SetFontObject(sfui.config.font_small)
    bar.time:SetPoint("RIGHT", -5, 0)
    StyleText(bar.time)

    -- Stack Count
    bar.count = bar.status:CreateFontString(nil, "OVERLAY")
    bar.count:SetFontObject(sfui.config.font_small)
    bar.count:SetPoint("CENTER", bar.icon, "CENTER", 0, 0)
    StyleText(bar.count)

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

local function ApplyStyle_Compact(bar)
    local padding = 2
    local mult = sfui.pixelScale or 1
    local scaledPadding = padding * mult
    local height = 15
    if sfui.config.secondaryPowerBar then
        height = sfui.config.secondaryPowerBar.height or 15
    end

    -- Compact Style: Hide labels, center Count
    bar.name:Hide()
    bar.time:Hide()
    bar.icon:Hide()

    bar.count:ClearAllPoints()
    bar.count:SetPoint("CENTER", bar.status, "CENTER", 0, 0)
    local fontSize = sfui.config.secondaryPowerBar and sfui.config.secondaryPowerBar.fontSize or 18
    local fontName = bar.count:GetFont()
    bar.count:SetFont(fontName, fontSize, "NONE")

    -- Return height and padding for external sizing
    return height, scaledPadding
end

local function UpdateLayout()
    local healthAnchored = nil
    local secondaryAnchored = {}
    local standardBars = {}

    for _, bar in pairs(bars) do
        if bar:IsShown() then
            local config = GetTrackedBarConfig(bar.cooldownID)

            -- Detect Mode
            if config and config.isSecondary then
                healthAnchored = bar
            elseif config and config.attachSecondary then
                table.insert(secondaryAnchored, bar)
            else
                table.insert(standardBars, bar)
            end
        end
    end

    local mult = sfui.pixelScale or 1

    -- 1. Apply Health Attached
    if healthAnchored then
        local anchor = _G["sfui_healthBar_Backdrop"]
        if anchor and healthAnchored:IsShown() then
            local h, p = ApplyStyle_Compact(healthAnchored)
            local w = anchor:GetWidth() * 0.8
            healthAnchored:SetSize(w + (p * 2), h + (p * 2))
            healthAnchored:ClearAllPoints()
            local spacing = sfui.config.barLayout.spacing or 1
            healthAnchored:SetPoint("BOTTOM", anchor, "TOP", 0, spacing)

            local config = GetTrackedBarConfig(healthAnchored.cooldownID)
            local color = config and config.color or sfui.config.colors.purple
            if color then
                healthAnchored.status:SetStatusBarColor(color.r or color[1], color.g or color[2],
                    color.b or color[3])
            end
        end
    end

    -- 2. Apply Secondary Attached
    if #secondaryAnchored > 0 then
        local anchor = _G["sfui_secondaryPowerBar_Backdrop"]
        if anchor and anchor:IsShown() then
            table.sort(secondaryAnchored, function(a, b) return a.cooldownID < b.cooldownID end)

            local prev = anchor
            for _, bar in ipairs(secondaryAnchored) do
                if bar:IsShown() then
                    local h, p = ApplyStyle_Compact(bar)
                    local w = anchor:GetWidth() -- Match Secondary Bar Width
                    bar:SetSize(w + (p * 2), h + (p * 2))
                    bar:ClearAllPoints()
                    local spacing = sfui.config.barLayout.spacing or 1
                    bar:SetPoint("BOTTOM", prev, "TOP", 0, spacing)

                    local config = GetTrackedBarConfig(bar.cooldownID)
                    local color = config and config.color or sfui.config.colors.purple
                    if color then
                        bar.status:SetStatusBarColor(color.r or color[1], color.g or color[2],
                            color.b or color[3])
                    end

                    prev = bar
                end
            end
        else
            -- Fallback
            for _, bar in ipairs(secondaryAnchored) do
                if bar:IsShown() then
                    table.insert(standardBars, bar)
                end
            end
        end
    end

    -- 3. Apply Standard
    local yOffset = 0
    table.sort(standardBars, function(a, b) return a.cooldownID < b.cooldownID end)

    for _, bar in ipairs(standardBars) do
        if bar:IsShown() then
            -- Standard Style
            bar.name:Show()
            bar.time:Show()
            bar.icon:Show()
            bar.count:ClearAllPoints()
            bar.count:SetPoint("CENTER", bar.icon, "CENTER", 0, 0)
            local font, size = GameFontNormalSmall:GetFont()
            bar.count:SetFont(font, size, "NONE")

            -- Check visibility configs (Standard only)
            local config = GetTrackedBarConfig(bar.cooldownID)
            if config and config.showName == false then bar.name:Hide() end
            if config and config.showDuration == false then bar.time:Hide() end
            if config and config.showStacks == false then bar.count:Hide() end

            -- Apply Color
            local color = config and config.color or sfui.config.colors.purple
            if color then bar.status:SetStatusBarColor(color.r or color[1], color.g or color[2], color.b or color[3]) end

            bar:SetSize(200, 20)
            bar:ClearAllPoints()
            -- Grow Upwards
            bar:SetPoint("BOTTOM", container, "BOTTOM", 0, yOffset)
            yOffset = yOffset + 25

            -- Reset styling
            bar.status:ClearAllPoints()
            bar.status:SetPoint("TOPLEFT", 1, -1)
            bar.status:SetPoint("BOTTOMRIGHT", -1, 1)
            local defaultColor = sfui.config.healthBar.backdrop.color or { 0, 0, 0, 0.5 }
            bar:SetBackdropColor(unpack(defaultColor))
        end
    end
end

-- Update Position External Reference
function sfui.trackedbars.UpdatePosition()
    if not container then return end
    local x = SfuiDB.trackedBarsX or -300
    local y = SfuiDB.trackedBarsY or 300
    container:ClearAllPoints()
    container:SetPoint("BOTTOM", UIParent, "BOTTOM", x, y)
end

function sfui.trackedbars.SetColor(cooldownID, r, g, b)
    if not SfuiDB then SfuiDB = {} end
    if not SfuiDB.trackedBars then SfuiDB.trackedBars = {} end
    if not SfuiDB.trackedBars[cooldownID] then SfuiDB.trackedBars[cooldownID] = {} end

    SfuiDB.trackedBars[cooldownID].color = { r = r, g = g, b = b }
    UpdateLayout() -- Refresh to apply color
end

local activeCooldownIDs = {}
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

local function SyncWithBlizzard()
    if not BuffBarCooldownViewer or not BuffBarCooldownViewer.itemFramePool then return end

    table.wipe(activeCooldownIDs)
    local layoutNeeded = false

    -- Global Hide Check
    -- We use our own OOC logic to avoid touching Blizzard's protected viewer state if it's crashing.
    local mustHide = false
    if SfuiDB and SfuiDB.hideOOC and not InCombatLockdown() then
        mustHide = true
    end

    -- Still respect Blizzard's major hidden state (e.g. Pet Battle) but ignore its internal OOC/Inactive logic
    -- if it's causing secret value errors.
    -- Actually, just use InCombatLockdown for our OOC.

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
    for blizzFrame in BuffBarCooldownViewer.itemFramePool:EnumerateActive() do
        -- Respect our internal "Show Inactive" setting.
        -- If hideInactive is false, we show even if blizzFrame:IsShown() is false.

        if blizzFrame.cooldownID then
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

            -- Sync Visibility
            -- hideInactive = true (default): Only show bars that Blizzard shows (active cooldowns)
            -- hideInactive = false: Show all bars, even if inactive
            local hideInactive = SfuiDB and SfuiDB.hideInactive ~= false -- Default to True if nil
            local shouldShow
            if hideInactive then
                -- Only show if Blizzard shows it (it's active)
                shouldShow = blizzFrame:IsShown()
            else
                -- Show all bars regardless of active state
                shouldShow = true
            end

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

            -- Copy bar values and text from Blizzard
            if blizzFrame.Bar then
                local min, max = blizzFrame.Bar:GetMinMaxValues()
                local val = blizzFrame.Bar:GetValue()
                myBar.status:SetMinMaxValues(min, max)
                myBar.status:SetValue(val)

                if blizzFrame.Bar.Name then
                    myBar.name:SetText(blizzFrame.Bar.Name:GetText())
                end
                if blizzFrame.Bar.Duration then
                    myBar.time:SetText(blizzFrame.Bar.Duration:GetText())
                end
            end

            -- Enhanced: Query C_Spell.GetSpellCharges for multi-charge abilities
            -- This provides more accurate charge info than Blizzard's Applications text
            local spellID = myBar.spellID
            if spellID then
                local chargeInfo = C_Spell.GetSpellCharges(spellID)
                if chargeInfo and chargeInfo.currentCharges then
                    myBar.count:SetText(chargeInfo.currentCharges)
                else
                    -- Fallback to Blizzard's stack display for buffs/debuffs
                    local stacks = ""
                    if blizzFrame.Icon and blizzFrame.Icon.Applications then
                        stacks = blizzFrame.Icon.Applications:GetText() or ""
                    end
                    myBar.count:SetText(stacks)
                end
            else
                -- No spellID, use Blizzard's display
                local stacks = ""
                if blizzFrame.Icon and blizzFrame.Icon.Applications then
                    stacks = blizzFrame.Icon.Applications:GetText() or ""
                end
                myBar.count:SetText(stacks)
            end
        end
    end

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

-- Functions to modify config
function sfui.trackedbars.SetAttachHealth(cooldownID, enable)
    if not SfuiDB then SfuiDB = {} end
    if not SfuiDB.trackedBars then SfuiDB.trackedBars = {} end
    if not SfuiDB.trackedBars[cooldownID] then SfuiDB.trackedBars[cooldownID] = {} end

    if enable then
        -- Enforce exclusivity: Clear other Health attachments
        for k, v in pairs(SfuiDB.trackedBars) do
            if v.isSecondary then v.isSecondary = false end
        end
        SfuiDB.trackedBars[cooldownID].isSecondary = true
        SfuiDB.trackedBars[cooldownID].attachSecondary = false
    else
        SfuiDB.trackedBars[cooldownID].isSecondary = false
    end
    UpdateLayout()
    -- Refresh options UI if open
    if sfui.trackedoptions and sfui.trackedoptions.RefreshList then
        sfui.trackedoptions.RefreshList()
    end
end

function sfui.trackedbars.SetAttachSecondary(cooldownID, enable)
    if not SfuiDB then SfuiDB = {} end
    if not SfuiDB.trackedBars then SfuiDB.trackedBars = {} end
    if not SfuiDB.trackedBars[cooldownID] then SfuiDB.trackedBars[cooldownID] = {} end

    if enable then
        SfuiDB.trackedBars[cooldownID].attachSecondary = true
        SfuiDB.trackedBars[cooldownID].isSecondary = false
    else
        SfuiDB.trackedBars[cooldownID].attachSecondary = false
    end
    UpdateLayout()
end

-- Public function to trigger visibility update from options panel
function sfui.trackedbars.UpdateVisibility()
    if SyncWithBlizzard then
        SyncWithBlizzard()
    end
end

function sfui.trackedbars.initialize()
    if container then return end
    local loaded, reason = C_AddOns.LoadAddOn("Blizzard_CooldownViewer")
    container = CreateFrame("Frame", "SfuiTrackedBarsContainer", UIParent)
    container:SetSize(200, 20)

    if not SfuiDB then SfuiDB = {} end
    if not SfuiDB.trackedBars then SfuiDB.trackedBars = {} end

    -- Set visibility defaults from config if not already set
    local cfg = sfui.config.trackedBars or {}
    if SfuiDB.hideOOC == nil then
        SfuiDB.hideOOC = cfg.hideOOC ~= nil and cfg.hideOOC or false
    end
    if SfuiDB.hideInactive == nil then
        SfuiDB.hideInactive = cfg.hideInactive ~= nil and cfg.hideInactive or true
    end

    -- Position
    sfui.trackedbars.UpdatePosition()

    -- Throttled OnUpdate for smooth bar progress (0.05s = ~20fps)
    local updateThrottle = 0
    container:SetScript("OnUpdate", function(self, elapsed)
        updateThrottle = updateThrottle + elapsed
        if updateThrottle >= 0.05 then
            updateThrottle = 0

            -- Update all visible bars from Blizzard's data
            if BuffBarCooldownViewer and BuffBarCooldownViewer.itemFramePool then
                for blizzFrame in BuffBarCooldownViewer.itemFramePool:EnumerateActive() do
                    if blizzFrame.cooldownID then
                        local myBar = bars[blizzFrame.cooldownID]
                        if myBar and myBar:IsShown() and blizzFrame.Bar then
                            -- Copy current bar values
                            local val = blizzFrame.Bar:GetValue()
                            myBar.status:SetValue(val)

                            -- Update duration text
                            if blizzFrame.Bar.Duration then
                                myBar.time:SetText(blizzFrame.Bar.Duration:GetText())
                            end
                        end
                    end
                end
            end
        end
    end)

    -- Event-driven updates instead of OnUpdate polling
    -- Hook into Blizzard's events to avoid 60+ fps polling
    if BuffBarCooldownViewer then
        -- Register for the same events Blizzard uses
        BuffBarCooldownViewer:HookScript("OnEvent", function(self, event, ...)
            if event == "SPELL_UPDATE_COOLDOWN" or
                event == "UNIT_AURA" or
                event == "UNIT_TARGET" or
                event == "PLAYER_TOTEM_UPDATE" or
                event == "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED" then
                SyncWithBlizzard()
            end
        end)

        -- Also hook the RefreshLayout callback for data changes
        EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", function()
            SyncWithBlizzard()
        end, container)

        -- Initial sync
        C_Timer.After(0.1, function()
            SyncWithBlizzard()
        end)
    end

    -- Hide Blizzard Frame
    if BuffBarCooldownViewer then
        BuffBarCooldownViewer:SetAlpha(0)
        BuffBarCooldownViewer:EnableMouse(false)
        BuffBarCooldownViewer:HookScript("OnShow", function(self)
            self:SetAlpha(0)
            self:EnableMouse(false)
        end)

        C_Timer.After(0, function()
            BuffBarCooldownViewer:SetAlpha(0)
            BuffBarCooldownViewer:EnableMouse(false)
            BuffBarCooldownViewer:SetFrameStrata("BACKGROUND")
            BuffBarCooldownViewer:SetScale(0.001)
            BuffBarCooldownViewer:ClearAllPoints()
            BuffBarCooldownViewer:SetPoint("TOPRIGHT", UIParent, "TOPLEFT", -1000, 1000)
        end)
    end
end
