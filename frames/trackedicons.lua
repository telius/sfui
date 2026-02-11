local addonName, addon = ...
sfui.trackedicons = {}

local panels = {} -- Active icon panels
local issecretvalue = sfui.common.issecretvalue

local function GetLCG()
    if LibStub then
        return LibStub("LibCustomGlow-1.0", true)
    end
end
sfui.trackedicons.GetLCG = GetLCG

local function StopGlow(icon)
    if ActionButton_HideOverlayGlow then
        ActionButton_HideOverlayGlow(icon)
    end
    local lcg = GetLCG()
    if lcg then
        pcall(lcg.PixelGlow_Stop, icon)
        pcall(lcg.AutoCastGlow_Stop, icon)
        pcall(lcg.ButtonGlow_Stop, icon)
    end
    icon._glowActive = false
    icon._lastGlowType = nil
    icon._lastGlowCfg = nil
end
sfui.trackedicons.StopGlow = StopGlow

local function StartGlow(icon, cfg)
    local gType = cfg.glowType or "blizzard"
    local color = cfg.glowColor or { r = 1, g = 1, b = 0 }
    local scale = cfg.glowScale or 1.0
    local intensity = cfg.glowIntensity or 1.0
    local speed = cfg.glowSpeed or 0.25
    local lcg = GetLCG()
    local frameLevel = icon:GetFrameLevel() + 30

    if gType == "pixel" and lcg then
        -- PixelGlow args: (frame, color, N, frequency, length, th, xOffset, yOffset, border, key, frameLevel)
        pcall(lcg.PixelGlow_Start, icon, { color.r, color.g, color.b, intensity }, nil, speed, nil, scale, nil, nil, nil,
            nil, frameLevel)
    elseif gType == "autocast" and lcg then
        pcall(lcg.AutoCastGlow_Start, icon, { color.r, color.g, color.b, intensity }, nil, speed, scale, nil, nil, nil,
            frameLevel)
    elseif lcg then
        -- Use LCG's version of Blizzard glow for better frame level control
        pcall(lcg.ButtonGlow_Start, icon, { color.r, color.g, color.b, intensity }, speed, frameLevel)
    else
        -- Fallback to Blizzard or if LCG is missing
        if ActionButton_ShowOverlayGlow then
            ActionButton_ShowOverlayGlow(icon)
        end
    end
    icon._glowActive = true
    icon._lastGlowType = gType
    icon._lastGlowCfg = sfui.common.copy(cfg) -- Need a shallow/deep copy for comparison
end
sfui.trackedicons.StartGlow = StartGlow


-- Cooldown text (timers) now uses Blizzard's native SetHideCountdownNumbers(false)
-- and SetCooldownFromDurationObject for max compatibility with Mythic+


-- Helper to create count text (stacks/charges)
local function CreateCountText(icon)
    if icon.count then return end

    local count = icon:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    count:SetPoint("BOTTOMRIGHT", -2, 2)
    count:SetJustifyH("RIGHT")
    icon.count = count
end

-- Helper to update count text value
local function UpdateCountText(icon, count)
    if not icon.count then CreateCountText(icon) end

    local isSecret = issecretvalue(count)
    local hasCount = sfui.common.SafeGT(count, 1)

    if isSecret or hasCount then
        sfui.common.SafeSetText(icon.count, count)
        icon.count:Show()
    else
        icon.count:Hide()
    end
end

-- Helper to update icon state (visibility, cooldown, charges)
local function UpdateIconState(icon, panelConfig)
    if not icon.id or not icon.entry then return false end
    panelConfig = panelConfig or {}
    local entrySettings = icon.entry.settings or {}

    -- Merge Logic: Entry Settings > Panel Config
    local function GetValue(key, default)
        if entrySettings[key] ~= nil then return entrySettings[key] end
        if panelConfig[key] ~= nil then return panelConfig[key] end
        return default
    end

    local durObj = nil
    local count = 0
    local isEnabled = true

    if icon.type == "item" then
        pcall(function()
            local s, d, e = C_Item.GetItemCooldown(icon.id)
            icon._start, icon._duration, icon._isEnabled = s, d, e
            isEnabled = e
            count = C_Item.GetItemCount(icon.id)
            -- Item fallback: use manual SetCooldown as no DurationObject exists for items
            CooldownFrame_Set(icon.cooldown, s, d, e)
            if icon.shadowCooldown then
                icon.shadowCooldown:SetCooldown(s, d)
            end
        end)
    else
        -- Pass 4/7: Spell Logic using DurationObject
        durObj = sfui.common.GetCooldownDurationObj(icon.id)

        pcall(function()
            local ci = C_Spell.GetSpellCooldown(icon.id)
            if ci then
                icon._start, icon._duration, icon._isEnabled, icon._modRate = ci.startTime, ci.duration, ci
                    .isEnabled, ci.modRate
                isEnabled = ci.isEnabled
            end

            if not issecretvalue(icon.id) then
                local charges = C_Spell.GetSpellCharges(icon.id)
                if charges then
                    count = sfui.common.SafeValue(charges.currentCharges, 0)
                end
            end

            -- Native Sync Swipe
            if durObj and not issecretvalue(durObj) then
                pcall(function()
                    icon.cooldown:SetCooldownFromDurationObject(durObj)
                    if icon.shadowCooldown then
                        icon.shadowCooldown:SetCooldownFromDurationObject(durObj)
                    end
                end)
            else
                -- No duration object = Ready (Clear cooldown)
                icon.cooldown:Clear()
                if icon.shadowCooldown then icon.shadowCooldown:Clear() end
            end
        end)
    end

    icon._isItem = (icon.type == "item")

    -- Readiness Logic (Native Safe)
    local isReady = true
    local safeEnabled = sfui.common.SafeNotFalse(isEnabled)

    if icon.type == "item" then
        local s, d = icon._start or 0, icon._duration or 0
        local safeS = sfui.common.SafeValue(s, 0)
        local safeD = sfui.common.SafeValue(d, 0)
        isReady = (safeS == 0 or (GetTime() - safeS) >= safeD or safeD <= 1.5) and safeEnabled
    else
        local countSafe = sfui.common.SafeGT(count, 0)
        isReady = (durObj == nil or countSafe) and safeEnabled
    end

    -- Visibility Decision: Icons are always shown if they exist in the panel,
    -- but they might be desaturated or have alpha.
    local shouldShow = true
    local isVisible = shouldShow -- In simple panel mode, all icons are visible holders

    if isVisible then
        if not icon:IsShown() then
            if not InCombatLockdown() then
                icon:Show()
            end
            icon:SetAlpha(1)
        end


        -- Update Count Text
        UpdateCountText(icon, count)

        -- Visibility / Settings check
        icon.cooldown:SetHideCountdownNumbers(not GetValue("textEnabled", true))


        -- Visuals
        local showGlow = GetValue("readyGlow", true)
        local useDesat = GetValue("cooldownDesat", true)
        local cdAlpha = GetValue("cooldownAlpha", 1.0)
        local glowType = GetValue("glowType", "blizzard")

        -- Desaturation Logic (Mirror Cooldown State)
        local desatState = not isReady
        if icon.texture then
            icon.texture:SetDesaturated(useDesat and desatState)
            icon.texture:SetAlpha(isReady and 1 or cdAlpha)
        end

        -- Glow Logic
        if isReady and showGlow then
            -- Resolved config for glow
            local currentGlowCfg = {
                glowType = glowType,
                glowColor = GetValue("glowColor", { r = 1, g = 1, b = 0 }),
                glowScale = GetValue("glowScale", 1.0),
                glowIntensity = GetValue("glowIntensity", 1.0),
                glowSpeed = GetValue("glowSpeed", 0.25)
            }

            -- Restart if type or parameters changed
            local needsRestart = false
            if not icon._glowActive then
                needsRestart = true
            elseif icon._lastGlowType ~= glowType then
                needsRestart = true
            elseif not icon._lastGlowCfg then
                needsRestart = true
            else
                local prev = icon._lastGlowCfg
                if math.abs(prev.glowColor.r - currentGlowCfg.glowColor.r) > 0.01 or
                    math.abs(prev.glowColor.g - currentGlowCfg.glowColor.g) > 0.01 or
                    math.abs(prev.glowColor.b - currentGlowCfg.glowColor.b) > 0.01 or
                    math.abs(prev.glowScale - currentGlowCfg.glowScale) > 0.01 or
                    math.abs(prev.glowIntensity - currentGlowCfg.glowIntensity) > 0.01 or
                    math.abs(prev.glowSpeed - currentGlowCfg.glowSpeed) > 0.01 then
                    needsRestart = true
                end
            end

            if needsRestart then
                if icon._glowActive then StopGlow(icon) end
                StartGlow(icon, currentGlowCfg)
            end
        else
            if icon._glowActive then
                StopGlow(icon)
            end
        end
    else
        if InCombatLockdown() then
            icon:SetAlpha(0)
        else
            icon:Hide()
        end
    end

    return isVisible
end


-- Create a single icon frame (Standard Button for Taint Isolation)
local function CreateIconFrame(parent, id, entry)
    local name = "SfuiTrackedIcon_" .. (entry.type or "spell") .. "_" .. id .. "_" .. GetTime() -- Unique basic name
    local f = CreateFrame("Button", name, parent)
    f:SetSize(50, 50)

    -- Icon Texture
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    f.texture = tex

    local iconTexture
    if entry.type == "item" then
        iconTexture = C_Item.GetItemIconByID(id)
    else
        iconTexture = C_Spell.GetSpellTexture(id)
    end
    tex:SetTexture(iconTexture or 134400)

    -- Main Cooldown Frame (Blizzard Native Countdown)
    local cd = CreateFrame("Cooldown", name .. "_CD", f, "CooldownFrameTemplate")
    cd:SetAllPoints(tex)
    cd:SetDrawEdge(true)
    cd:SetHideCountdownNumbers(false) -- SHOW NATIVE COUNTDOWN
    f.cooldown = cd

    -- Shadow Cooldown Frame (Invisible, drives desaturation safely)
    local shadow = CreateFrame("Cooldown", name .. "_ShadowCD", f, "CooldownFrameTemplate")
    shadow:SetAllPoints(tex)
    shadow:SetDrawSwipe(false)
    shadow:SetDrawEdge(false)
    shadow:SetDrawBling(false)
    shadow:SetHideCountdownNumbers(true)
    shadow:SetAlpha(0)
    f.shadowCooldown = shadow

    -- Main cooldown frames handle countdown numbers natively

    -- Border/Overlay (optional visual polish)
    f.PushedTexture = f:CreateTexture(nil, "OVERLAY")
    f.PushedTexture:SetTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    f.PushedTexture:SetAllPoints()
    f:SetPushedTexture(f.PushedTexture)

    f.HighlightTexture = f:CreateTexture(nil, "HIGHLIGHT")
    f.HighlightTexture:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    f.HighlightTexture:SetAllPoints()
    f:SetHighlightTexture(f.HighlightTexture)

    f.id = id
    f.entry = entry

    f:RegisterForClicks("AnyUp", "AnyDown")

    f:SetScript("OnEnter", function(self)
        if GameTooltip and self.id and not issecretvalue(self.id) then
            pcall(function()
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if self.entry.type == "item" then
                    GameTooltip:SetItemByID(self.id)
                else
                    GameTooltip:SetSpellByID(self.id)
                end
                GameTooltip:Show()
            end)
        end
    end)
    f:SetScript("OnLeave", function()
        if GameTooltip then pcall(GameTooltip.Hide, GameTooltip) end
    end)

    -- Initial State
    if InCombatLockdown() then
        f:SetAlpha(1)
        -- Cannot Show() in combat if hidden, so we assume created visible or managed before combat
    else
        f:Show()
    end

    -- Event-Driven Update (OnUpdate no longer needed for text)
    -- But we keep it for desat/glow logic if needed, or remove to save cycles
    f:SetScript("OnUpdate", nil)

    return f
end

function sfui.trackedicons.UpdatePanelLayout(panelFrame, panelConfig)
    if not panelFrame or not panelConfig then return end
    if InCombatLockdown() then return end -- Pass 8: Block heavy layout mid-combat to prevent ActionBlocked
    panelFrame.config = panelConfig

    -- PROTECT: Cannot move frames in combat!
    if InCombatLockdown() then return end

    local size = panelConfig.size or 50
    local spacing = panelConfig.spacing or 5

    -- Ensure panel position is updated from Config with Dynamic Anchoring
    panelFrame:ClearAllPoints()
    local isLeft = (panelConfig.x or 0) < 0
    local anchor = isLeft and "TOPRIGHT" or "TOPLEFT"

    panelFrame:SetPoint(anchor, UIParent, "BOTTOM", panelConfig.x or 0, panelConfig.y or 0)

    -- Hide all known icons first (full redraw of state)
    -- Safe out of combat
    if panelFrame.icons then
        for _, icon in pairs(panelFrame.icons) do
            if icon._glowActive then StopGlow(icon) end
            icon:Hide()
            icon:ClearAllPoints()
        end
    else
        panelFrame.icons = {}
    end

    local activeIcons = {}
    local entries = panelConfig.entries or {}

    for i, entry in ipairs(entries) do
        local id = entry.id
        if id then
            if not panelFrame.icons[i] then
                panelFrame.icons[i] = CreateIconFrame(panelFrame, id, entry)
            end

            local icon = panelFrame.icons[i]
            if icon then
                -- Update attributes (safe out of combat)
                icon.id = id
                icon.type = entry.type
                icon.entry = entry


                local isVisibleValue = UpdateIconState(icon, panelConfig)
                if isVisibleValue then
                    table.insert(activeIcons, icon)
                end
            end
        end
    end

    -- Layout Active Icons
    local numColumns = panelConfig.columns or #activeIcons
    if numColumns < 1 then numColumns = 1 end

    local maxWidth, maxHeight = 0, 0

    for i, icon in ipairs(activeIcons) do
        icon:ClearAllPoints()
        icon:SetSize(size, size)

        local col = (i - 1) % numColumns
        local row = math.floor((i - 1) / numColumns)

        local x = col * (size + spacing)
        local y = -row * (size + spacing)

        if isLeft then
            icon:SetPoint("TOPRIGHT", panelFrame, "TOPRIGHT", -x, y)
        else
            icon:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", x, y)
        end

        maxWidth = math.max(maxWidth, (col + 1) * (size + spacing) - spacing)
        maxHeight = math.max(maxHeight, (row + 1) * (size + spacing) - spacing)
    end

    panelFrame:SetSize(math.max(maxWidth, 1), math.max(maxHeight, 1))
end

function sfui.trackedicons.Update()
    -- DB Migration / Initialization
    if not SfuiDB.cooldownPanels or not SfuiDB.iconsInitialized then
        SfuiDB.cooldownPanels = SfuiDB.cooldownPanels or {}
        SfuiDB.iconsInitialized = true

        local leftEntries = {}

        -- Migrate legacy trackedIcons if present
        if SfuiDB.trackedIcons then
            for id, cfg in pairs(SfuiDB.trackedIcons) do
                if type(id) == "number" then
                    table.insert(leftEntries, { id = id, settings = cfg })
                end
            end
            SfuiDB.trackedIcons = nil -- Clear old
        end

        -- Default Left Panel
        table.insert(SfuiDB.cooldownPanels, {
            name = "Left Panel",
            point = "BOTTOM",
            relativePoint = "BOTTOM",
            x = -300,
            y = 250,
            size = 40,
            spacing = 5,
            enabled = true,
            entries = leftEntries -- Put migrated icons here
        })

        -- Default Right Panel
        table.insert(SfuiDB.cooldownPanels, {
            name = "Right Panel",
            point = "BOTTOM",
            relativePoint = "BOTTOM",
            x = 300,
            y = 250,
            size = 40,
            spacing = 5,
            enabled = true,
            entries = {}
        })
    end

    if not SfuiDB or not SfuiDB.cooldownPanels then return end

    -- Render Panels
    for i, panelConfig in ipairs(SfuiDB.cooldownPanels) do
        if panelConfig.enabled then
            if not panels[i] then
                panels[i] = CreateFrame("Frame", "SfuiIconPanel_" .. i, UIParent)
            end
            sfui.trackedicons.UpdatePanelLayout(panels[i], panelConfig)
        elseif panels[i] then
            if not InCombatLockdown() then
                panels[i]:Hide()
            end
        end
    end
end

function sfui.trackedicons.initialize()
    -- sfui.common.ensure_tracked_icon_db() -- Removed to allow Update() to detect empty state

    -- Event handling
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED") -- To retry layout updates
    eventFrame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_ENABLED" then
            sfui.trackedicons.Update()
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- Force a sync of spell data before UI refresh
            if sfui.common.SyncTrackedSpells then
                sfui.common.SyncTrackedSpells()
            end
            sfui.trackedicons.Update()
        else
            -- For visual updates (cooldowns), we can run in combat
            -- But layout updates (add/remove) must be skipped
            if InCombatLockdown() then
                -- Iterate existing panels and just update states/cooldowns
                for i, panel in pairs(panels) do
                    local config = SfuiDB.cooldownPanels[i]
                    if panel.icons then
                        for _, icon in pairs(panel.icons) do
                            UpdateIconState(icon, config)
                        end
                    end
                end
            else
                sfui.trackedicons.Update()
            end
        end
    end)

    -- Throttled OnUpdate to ensure snappy "Ready" state transitions (Glow/Alpha)
    local lastUpdate = 0
    eventFrame:SetScript("OnUpdate", function(self, elapsed)
        lastUpdate = lastUpdate + elapsed
        if lastUpdate > 0.1 then
            lastUpdate = 0
            if not InCombatLockdown() or SfuiDB.cooldownPanels then
                for i, panel in pairs(panels) do
                    local config = SfuiDB.cooldownPanels[i]
                    if panel.icons then
                        for _, icon in pairs(panel.icons) do
                            UpdateIconState(icon, config)
                        end
                    end
                end
            end
        end
    end)

    sfui.trackedicons.Update()
end
