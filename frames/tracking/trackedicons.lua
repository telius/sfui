local addonName, addon = ...
sfui = sfui or {}
sfui.trackedicons = sfui.trackedicons or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/tracking/trackedicons.lua
--  panel layout, frame pooling, visibility state machine, and event scheduling.
--  delegates static descriptors to entry.lua, aura overlays to icon_aura.lua,
--  and cooldown/charge/usability/glow updates to icon_cooldown.lua.
-- ══════════════════════════════════════════════════════════════════════════════

local entryHelper = sfui.tracking.entry
local auraResolver = sfui.tracking.auras
local iconAura = sfui.trackedicons._aura
local iconCooldown = sfui.trackedicons._cooldown

local C_Spell = C_Spell
local C_Item = C_Item
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame
local UIParent = UIParent
local GetInventoryItemID = GetInventoryItemID
local GetInventoryItemTexture = GetInventoryItemTexture
local GetInventorySlotInfo = GetInventorySlotInfo
local GetShapeshiftForm = GetShapeshiftForm
local GetShapeshiftFormID = GetShapeshiftFormID
local IsStealthed = IsStealthed
local UnitHasVehicleUI = UnitHasVehicleUI
local UnitInVehicle = UnitInVehicle
local wipe = wipe or table.wipe
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local type = type
local issecretvalue = sfui.common.issecretvalue
local IsValidTexture = sfui.common.is_valid_texture or function(tex)
    if issecretvalue(tex) then return true end
    return tex ~= nil and tex ~= 0 and tex ~= ""
end

local panels = {} -- Active icon panels
local _needsStateUpdate = true
local _needsLayoutUpdate = true
local _needsWatchlistSync = false
local _layoutCooldown = 0

local is_in_combat = sfui.common.is_in_combat
sfui.trackedicons.IsInCombat = is_in_combat

local function MarkDirty(needsLayout)
    _needsStateUpdate = true
    if needsLayout then
        _needsLayoutUpdate = true
    end
end
sfui.trackedicons.MarkDirty = MarkDirty

local _iconCounter = 0
local _staticActiveEntries = {}
local _staticActiveIcons = {}
local _watchlistScratch = {}
local _activeGlowCount = 0

local _iconConfigCache = setmetatable({}, { __mode = "k" })
function sfui.trackedicons.InvalidateConfigCache()
    for k in pairs(_iconConfigCache) do
        _iconConfigCache[k] = nil
    end
    if iconCooldown and iconCooldown.InvalidateChargeCache then
        iconCooldown.InvalidateChargeCache()
    end
    if entryHelper and entryHelper.BumpConfigRevision then
        entryHelper.BumpConfigRevision()
    end
    _needsWatchlistSync = true
end

-- Helper: Get value from entry -> panel -> global -> hardcoded default (M+ safe)
local function GetIconValue(entrySettings, panelConfig, key, default)
    local altKey = (key == "textEnabled") and "showText" or ((key == "showText") and "textEnabled" or nil)

    -- 1. Entry override checked in O(1) directly (prevents cross-panel cache aliasing)
    if entrySettings then
        if entrySettings[key] ~= nil then
            return entrySettings[key]
        elseif altKey and entrySettings[altKey] ~= nil then
            return entrySettings[altKey]
        end
    end

    -- 2. Panel -> Panel Defaults -> Global cached per panelConfig
    local cacheKey = panelConfig or "global"
    local cache = _iconConfigCache[cacheKey]
    if not cache then
        cache = {}
        _iconConfigCache[cacheKey] = cache
    end

    local val = cache[key]
    if val ~= nil then
        if val == "__NIL__" then return default end
        return val
    end

    if panelConfig and panelConfig[key] ~= nil then
        val = panelConfig[key]
    elseif altKey and panelConfig and panelConfig[altKey] ~= nil then
        val = panelConfig[altKey]
    else
        local pName = panelConfig and panelConfig.name and string.upper(panelConfig.name)
        local pDef = (pName == "CENTER" or pName == "CAT" or pName == "BEAR" or pName == "MOONKIN" or pName == "STEALTH"
            or pName == "BATTLE" or pName == "DEFENSIVE" or pName == "BERSERKER")
            and sfui.config and sfui.config.cooldown_panel_defaults and sfui.config.cooldown_panel_defaults.center_panel
        if not pDef and pName == "UTILITY" then
            pDef = sfui.config and sfui.config.cooldown_panel_defaults and sfui.config.cooldown_panel_defaults.utility
        end
        if pDef and pDef[key] ~= nil then
            val = pDef[key]
        else
            local globalCfg = SfuiDB and SfuiDB.iconGlobalSettings
            if globalCfg and globalCfg[key] ~= nil then
                val = globalCfg[key]
            else
                local g = sfui.config
                local configDefault = g and g.icon_panel_global_defaults
                if configDefault and configDefault[key] ~= nil then
                    val = configDefault[key]
                end
            end
        end
    end

    if val == nil then
        cache[key] = "__NIL__"
        return default
    end

    cache[key] = val
    return val
end

local SafeGetCooldownViewerCooldownInfo = entryHelper.SafeGetCooldownInfo

local function StopGlow(icon)
    if icon._glowActive then
        if _activeGlowCount > 0 then
            _activeGlowCount = _activeGlowCount - 1
        end
    end
    sfui.glows.stop_glow(icon)
    icon._lastGlowCfg = nil
    icon._lastGlowType = nil
    icon._glowConfigRev = nil
    icon._glowActive = false
end
sfui.trackedicons.StopGlow = StopGlow

local function StartGlow(icon, cfg)
    local wasActive = (icon._glowActive == true)
    sfui.glows.start_glow(icon, cfg)
    if not icon._glowActive then
        return
    end
    if not wasActive then
        _activeGlowCount = _activeGlowCount + 1
    end
    icon._lastGlowType = cfg.glowType
    if not icon._lastGlowCfg then icon._lastGlowCfg = {} end
    local t = icon._lastGlowCfg
    local r, g, b = sfui.common.unpack_color(cfg.glowColor)
    t.glowType = cfg.glowType
    t.r = r
    t.g = g
    t.b = b
    t.glowScale = cfg.glowScale
    t.glowIntensity = cfg.glowIntensity
    t.glowSpeed = cfg.glowSpeed
    t.glowLines = cfg.glowLines
    t.glowThickness = cfg.glowThickness
    t.glowParticles = cfg.glowParticles
end
sfui.trackedicons.StartGlow = StartGlow

local function HidePanelAndStopGlows(panelFrame)
    if not panelFrame then return end
    if panelFrame.icons then
        for _, icon in pairs(panelFrame.icons) do
            if icon._glowActive then
                StopGlow(icon)
            end
        end
    end
    if panelFrame:IsShown() then
        panelFrame:Hide()
    end
end

local function SyncIconAuraWatchlist()
    if not auraResolver or not auraResolver.SetIconWatchlist then return end
    wipe(_watchlistScratch)
    for _, panel in pairs(panels) do
        if panel.config and panel.config.enabled and panel.icons then
            for i = 1, #panel.icons do
                local icon = panel.icons[i]
                if icon and icon.id and icon.entry then
                    local desc = entryHelper.CompileDescriptor(icon, panel.config, GetIconValue, sfui.trackedicons.GetIconTexture)
                    if desc.wantsAura or desc.trackBuffs or desc.glowWhenMissing then
                        _watchlistScratch[#_watchlistScratch + 1] = desc
                    end
                end
            end
        end
    end
    auraResolver.SetIconWatchlist(_watchlistScratch)
    _needsWatchlistSync = false
end

-- Helper to update icon state (visibility, aura override, cooldown, charges, visuals, glows)
local function UpdateIconState(icon, panelConfig, event)
    if not icon.id or not icon.entry then return false end

    local desc = entryHelper.CompileDescriptor(icon, panelConfig, GetIconValue, sfui.trackedicons.GetIconTexture)
    local entrySettings = desc.settings

    -- Visibility Decision (Early Exit to skip cooldown/charge C-API calls when hidden)
    local forceShow = (sfui.movers and sfui.movers.isUnlocked) == true
    if not forceShow then
        local viewer = _G["SfuiCooldownsViewer"]
        if viewer and viewer:IsShown() then
            local tabId = viewer.selectedTabId
            if tabId == 1 or tabId == 3 then
                forceShow = true
            end
        end
    end

    if not forceShow then
        local hideOOC = GetIconValue(nil, panelConfig, "hideOOC", false)
        local inCombat = is_in_combat(event)
        local isStealthPanelActive = (panelConfig and panelConfig.requiredForm == "stealth") and IsStealthed()
        if hideOOC and not inCombat and not isStealthPanelActive then
            if icon:IsShown() then icon:Hide() end
            if icon._glowActive then StopGlow(icon) end
            return false
        end

        if panelConfig then
            if panelConfig.visibility == "combat" and not inCombat and not isStealthPanelActive then
                if icon:IsShown() then icon:Hide() end
                if icon._glowActive then StopGlow(icon) end
                return false
            elseif panelConfig.visibility == "noCombat" and inCombat then
                if icon:IsShown() then icon:Hide() end
                if icon._glowActive then StopGlow(icon) end
                return false
            end
        end

        if not inCombat and not isStealthPanelActive then
            local hideMounted = GetIconValue(nil, panelConfig, "hideMounted", false)
            if hideMounted and sfui.common.is_mounted_or_travel_form() then
                if icon:IsShown() then icon:Hide() end
                if icon._glowActive then StopGlow(icon) end
                return false
            end

            local hideInVehicle = GetIconValue(nil, panelConfig, "hideInVehicle", true)
            if hideInVehicle and (UnitHasVehicleUI("player") or UnitInVehicle("player")) then
                if icon:IsShown() then icon:Hide() end
                if icon._glowActive then StopGlow(icon) end
                return false
            end

            local hideDragonriding = GetIconValue(nil, panelConfig, "hideDragonriding", false)
            if hideDragonriding and sfui.common.IsDragonriding and sfui.common.IsDragonriding() then
                if icon:IsShown() then icon:Hide() end
                if icon._glowActive then StopGlow(icon) end
                return false
            end
        end
    end

    local showCountdown = GetIconValue(entrySettings, panelConfig, "textEnabled", true)
    if icon._lastShowCountdown ~= showCountdown then
        icon._lastShowCountdown = showCountdown
        icon.cooldown:SetHideCountdownNumbers(not showCountdown)
    end

    -- 1. Evaluate revision-gated aura duration, seal icon override, opt-in buff stacks, & missing alert
    local auraActive, auraStacks, missingAlert = iconAura.Evaluate(icon, desc)

    -- 2. Evaluate item/spell cooldown, native charges/display counts, & usability
    local count, isReady, isUsable, notEnoughPower, isOnCooldown = iconCooldown.Evaluate(icon, desc, auraActive)

    if auraActive then
        -- keep icon crisp and full-color while its active aura duration ticks
        isUsable = true
        notEnoughPower = false
        isOnCooldown = false
    elseif desc.isCoverSpell then
        -- synthetic cover spells (forever paladin "seals" 1323522) report IsSpellUsable = false
        isUsable = true
        notEnoughPower = false
    end

    if not icon:IsShown() then
        icon:Show()
    end

    -- 3. Update Count Text (opt-in aura stacks take priority over base count)
    local displayCount = (auraStacks ~= nil) and auraStacks or count
    iconCooldown.UpdateCountText(icon, displayCount)

    -- 4. Update Visuals & Glows
    iconCooldown.UpdateVisuals(icon, entrySettings, panelConfig, GetIconValue, isUsable, isOnCooldown, notEnoughPower)
    iconCooldown.UpdateGlow(icon, entrySettings, panelConfig, GetIconValue, isReady, missingAlert, StartGlow, StopGlow)
    return true
end

-- Shared Helper for Texture Resolution
local function SafeSpellTexture(spellID)
    if not spellID or issecretvalue(spellID) then return nil end
    local tex = sfui.common.get_spell_icon and sfui.common.get_spell_icon(spellID)
    if IsValidTexture(tex) then return tex end
    tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)
    if IsValidTexture(tex) then return tex end
    return nil
end

local function SafeItemTexture(itemID)
    if not itemID or issecretvalue(itemID) then return nil end
    local tex = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
    if IsValidTexture(tex) then return tex end
    if C_Item and C_Item.RequestLoadItemDataByID and type(itemID) == "number" and itemID > 0 then
        C_Item.RequestLoadItemDataByID(itemID)
    end
    return nil
end

function sfui.trackedicons.GetIconTexture(id, iconType, entry, preFetchedCdInfo)
    local activeID = id
    local iconTexture
    local resolvedType = iconType
    local linkedSpellIDs = nil

    local equipSlot = entry and entry.equipSlot
    local spellCategoryID = entry and entry.spellCategoryID
    local cdID = entry and (entry.cooldownID or (iconType == "cooldown" and id)) or (iconType == "cooldown" and id) or nil
    local cdInfo = preFetchedCdInfo or (cdID and SafeGetCooldownViewerCooldownInfo(cdID)) or nil

    if not equipSlot and not spellCategoryID and cdInfo then
        equipSlot = cdInfo.equipSlot
        spellCategoryID = cdInfo.spellCategoryID
        linkedSpellIDs = cdInfo.linkedSpellIDs
        if cdInfo.spellID and cdInfo.spellID > 0 then
            activeID = cdInfo.overrideSpellID or cdInfo.spellID
            resolvedType = "spell"
        elseif cdInfo.itemID and cdInfo.itemID > 0 then
            activeID = cdInfo.itemID
            resolvedType = "item"
        end
    end

    if equipSlot then
        resolvedType = "item"
        local eqItemID = GetInventoryItemID and GetInventoryItemID("player", equipSlot) or nil
        activeID = eqItemID or equipSlot
        iconTexture = GetInventoryItemTexture and GetInventoryItemTexture("player", equipSlot)
        if not IsValidTexture(iconTexture) and eqItemID then
            iconTexture = SafeItemTexture(eqItemID)
        end
        if not IsValidTexture(iconTexture) then
            local slotName = (equipSlot == 14) and "Trinket1Slot" or "Trinket0Slot"
            local _, slotTex = GetInventorySlotInfo(slotName)
            if IsValidTexture(slotTex) then
                iconTexture = slotTex
            end
        end
        local isColdEquip = not IsValidTexture(iconTexture)
        return (not isColdEquip and iconTexture) or 134400, activeID, resolvedType, nil, isColdEquip
    end

    if spellCategoryID then
        resolvedType = "item"
        local catData = (sfui.tracking and sfui.tracking.SPELL_CATEGORY_METADATA and sfui.tracking.SPELL_CATEGORY_METADATA[spellCategoryID])
        activeID = (cdInfo and cdInfo.lastItemIDForCategory) or (entry and entry.itemID) or (catData and catData.fallbackItemID) or id
        if catData and IsValidTexture(catData.icon) then
            iconTexture = catData.icon
        elseif activeID and not issecretvalue(activeID) and type(activeID) == "number" and activeID > 0 then
            iconTexture = SafeItemTexture(activeID)
        end
        local isColdCat = not IsValidTexture(iconTexture)
        return (not isColdCat and iconTexture) or 134400, activeID, resolvedType, nil, isColdCat
    end

    if cdID then
        if cdInfo then
            linkedSpellIDs = cdInfo.linkedSpellIDs
            if cdInfo.spellID and cdInfo.spellID > 0 then
                activeID = cdInfo.overrideSpellID or cdInfo.spellID
                iconTexture = SafeSpellTexture(activeID)
                resolvedType = "spell"
            elseif cdInfo.itemID and cdInfo.itemID > 0 then
                activeID = cdInfo.itemID
                iconTexture = SafeItemTexture(activeID)
                resolvedType = "item"
            end
        elseif entry then
            if entry.spellID and entry.spellID > 0 then
                activeID = entry.spellID
                iconTexture = SafeSpellTexture(activeID)
                resolvedType = "spell"
            elseif entry.itemID and entry.itemID > 0 then
                activeID = entry.itemID
                iconTexture = SafeItemTexture(activeID)
                resolvedType = "item"
            else
                activeID = entry.spellID or id
                iconTexture = SafeSpellTexture(activeID)
                resolvedType = "spell"
                if not IsValidTexture(iconTexture) then
                    iconTexture = SafeItemTexture(activeID)
                    if IsValidTexture(iconTexture) then resolvedType = "item" end
                end
            end
        end
    elseif iconType == "item" then
        activeID = (entry and entry.itemID) or id
        iconTexture = SafeItemTexture(activeID)
        resolvedType = "item"
    else
        -- Plain spell / aura entry (never pass raw spellID to GetCooldownViewerCooldownInfo)
        if sfui.isEra and sfui.tracking and sfui.tracking.ResolveClassicSpellID then
            activeID = sfui.tracking.ResolveClassicSpellID(activeID) or activeID
        end
        iconTexture = SafeSpellTexture(activeID)
        resolvedType = "spell"
        if not IsValidTexture(iconTexture) then
            iconTexture = SafeItemTexture(activeID)
            if IsValidTexture(iconTexture) then resolvedType = "item" end
        end
    end

    if not IsValidTexture(iconTexture) and activeID then
        iconTexture = SafeSpellTexture(activeID) or SafeItemTexture(activeID)
    end

    local isColdIcon = not IsValidTexture(iconTexture)
    return (not isColdIcon and iconTexture) or 134400, activeID, resolvedType, linkedSpellIDs, isColdIcon
end

-- Apply square icon + border style from config
function sfui.trackedicons.ApplyIconBorderStyle(icon, panelConfig)
    if not icon or not icon.texture then return end

    if icon._isMasqued then
        if icon.borderBackdrop then icon.borderBackdrop:Hide() end
        return
    end

    local showBorder = GetIconValue(nil, panelConfig, "showBorder", false)
    local squareIcons = GetIconValue(nil, panelConfig, "squareIcons", false)

    if icon._lastShowBorder == showBorder and icon._lastSquareIcons == squareIcons then
        return
    end
    icon._lastShowBorder = showBorder
    icon._lastSquareIcons = squareIcons

    if squareIcons then
        icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        icon.texture:SetTexCoord(0, 1, 0, 1)
    end

    if icon.borderBackdrop then
        if showBorder then
            icon.borderBackdrop:Show()
            icon.texture:ClearAllPoints()
            icon.texture:SetPoint("TOPLEFT", icon, "TOPLEFT", 2, -2)
            icon.texture:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 2)
        else
            icon.borderBackdrop:Hide()
            icon.texture:ClearAllPoints()
            icon.texture:SetAllPoints()
        end

        if icon.cooldown then
            icon.cooldown:ClearAllPoints()
            icon.cooldown:SetAllPoints(icon.texture)
        end
    end
end

local function SyncIconMasque(icon)
    local regions = icon._masqueRegions
    if not regions then
        regions = { Icon = icon.texture, Cooldown = icon.cooldown }
        icon._masqueRegions = regions
    else
        regions.Icon = icon.texture
        regions.Cooldown = icon.cooldown
    end
    sfui.common.sync_masque(icon, regions)
end

-- Create a single icon frame (Standard Button for Taint Isolation)
local function CreateIconFrame(parent, id, entry, panelConfig)
    if type(entry) == "number" then
        entry = { id = entry, type = "spell" }
    end

    _iconCounter = _iconCounter + 1
    local name = "SfuiIcon" .. _iconCounter
    local f = CreateFrame("Button", name, parent)
    local initialSize = 40
    if panelConfig then
        initialSize = tonumber(panelConfig.size) or 40
    end
    f:SetSize(initialSize, initialSize)

    f.borderBackdrop = f:CreateTexture(nil, "BACKGROUND")
    f.borderBackdrop:SetAllPoints()
    f.borderBackdrop:SetColorTexture(0, 0, 0, 1)
    f.borderBackdrop:Hide()

    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    f.texture = tex

    local iconTexture = sfui.trackedicons.GetIconTexture(id, entry.type, entry)
    tex:SetTexture(iconTexture or 134400)

    sfui.trackedicons.ApplyIconBorderStyle(f, panelConfig)

    local cd = CreateFrame("Cooldown", name .. "_CD", f, "CooldownFrameTemplate")
    cd:SetAllPoints(tex)
    cd:SetDrawEdge(true)
    cd:SetHideCountdownNumbers(false)
    f.cooldown = cd

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

    -- DO NOT register for clicks - keeps frames non-protected and taint-isolated
    f:SetScript("OnEnter", function(self)
        local showTooltips = GetIconValue(self.entry and self.entry.settings, panelConfig, "showTooltips", false)
        if showTooltips and self.id and not (issecretvalue and issecretvalue(self.id)) then
            local tip = sfui.common.get_tooltip()
            if not tip then return end
            tip:SetOwner(self:GetParent(), "ANCHOR_RIGHT")

            local desc = self._desc
            local equipSlot = (desc and desc.equipSlot) or (self.entry and self.entry.equipSlot)
            local spellCategoryID = (desc and desc.spellCategoryID) or (self.entry and self.entry.spellCategoryID)
            local cdID = (desc and desc.cooldownID) or (self.entry and (self.entry.cooldownID or (self.entry.type == "cooldown" and self.id))) or nil

            if not equipSlot and not spellCategoryID and cdID then
                local cdInfo = SafeGetCooldownViewerCooldownInfo(cdID)
                if cdInfo then
                    equipSlot = cdInfo.equipSlot
                    spellCategoryID = cdInfo.spellCategoryID
                end
            end

            if equipSlot then
                local hasItem = tip:SetInventoryItem("player", equipSlot)
                if not hasItem then
                    local slotName = (equipSlot == 14) and "trinket 2" or "trinket 1"
                    tip:SetText(slotName)
                end
            elseif spellCategoryID then
                local catData = (sfui.tracking and sfui.tracking.SPELL_CATEGORY_METADATA and sfui.tracking.SPELL_CATEGORY_METADATA[spellCategoryID])
                local itemID = (self.entry and self.entry.itemID) or (catData and catData.fallbackItemID) or self._lastActiveID
                if itemID and itemID > 0 then
                    tip:SetItemByID(itemID)
                elseif catData and catData.tooltipTitle then
                    tip:SetText(catData.tooltipTitle)
                    if catData.tooltipDescription then
                        tip:AddLine(catData.tooltipDescription, 1, 1, 1, true)
                    end
                else
                    tip:SetText("cooldown category " .. spellCategoryID)
                end
            elseif self._resolvedType == "item" or (self.entry and self.entry.type == "item") then
                tip:SetItemByID(self._lastActiveID or self.id)
            else
                tip:SetSpellByID(self._lastActiveID or self.id)
            end
            tip:Show()
        end
    end)
    f:SetScript("OnLeave", function()
        sfui.common.hide_tooltip()
    end)

    f:SetScript("OnUpdate", nil)
    SyncIconMasque(f)
    return f
end

local PRIMARY_FORM_NAMES = {
    CENTER = true,
    CAT = true,
    BEAR = true,
    MOONKIN = true,
    STEALTH = true,
    BATTLE = true,
    DEFENSIVE = true,
    BERSERKER = true,
}

local function IsPrimaryFormPanel(panelConfig)
    if not panelConfig or not panelConfig.name then return false end
    return PRIMARY_FORM_NAMES[string.upper(panelConfig.name)] == true
end

local function GetPanelIconAnchor(panelConfig)
    local growthH = (panelConfig and panelConfig.growthH) or "Right"
    local growthV = (panelConfig and panelConfig.growthV) or "Down"
    if growthH == "Center" then
        return (growthV == "Up") and "BOTTOM" or "TOP"
    elseif growthH == "Left" then
        return (growthV == "Up") and "BOTTOMRIGHT" or "TOPRIGHT"
    else
        return (growthV == "Up") and "BOTTOMLEFT" or "TOPLEFT"
    end
end

local function MatchesCurrentForm(panelConfig)
    if not panelConfig then return false end

    local isStealthed = IsStealthed()
    local currentForm = GetShapeshiftFormID() or 0
    local playerClass = sfui.common.get_player_class()

    local isClassic = not sfui.isRetail
    if playerClass == "WARRIOR" and isClassic then
        local req = panelConfig.requiredForm
        if req == nil then
            local pName = panelConfig.name and string.upper(panelConfig.name)
            if pName == "BATTLE" or pName == "CENTER" then
                req = 1
            elseif pName == "DEFENSIVE" then
                req = 2
            elseif pName == "BERSERKER" then
                req = 3
            end
        end

        if req ~= nil then
            local activeStance = (GetShapeshiftForm and GetShapeshiftForm()) or 0
            if activeStance == 0 then activeStance = 1 end
            local matchesStance = false

            local function stanceMatches(formReq)
                if activeStance == formReq then return true end
                if currentForm ~= 0 then
                    if currentForm == formReq then return true end
                    if (currentForm == 17 and formReq == 1)
                        or (currentForm == 18 and formReq == 2)
                        or (currentForm == 19 and formReq == 3) then
                        return true
                    end
                end
                return false
            end

            if type(req) == "table" then
                for _, id in ipairs(req) do
                    if stanceMatches(id) then
                        matchesStance = true
                        break
                    end
                end
            elseif stanceMatches(req) then
                matchesStance = true
            end

            if not matchesStance then return false end
        end
    else
        if panelConfig.requiredForm ~= nil then
            if panelConfig.requiredForm == "stealth" then
                if not isStealthed then return false end
                if playerClass == "DRUID" and currentForm ~= 0 and currentForm ~= 1 then
                    return false
                end
            else
                local matchesForm = false
                if type(panelConfig.requiredForm) == "table" then
                    for _, id in ipairs(panelConfig.requiredForm) do
                        if currentForm == id then
                            matchesForm = true; break
                        end
                    end
                elseif currentForm == panelConfig.requiredForm then
                    matchesForm = true
                end

                if not matchesForm then return false end
            end
        end

        if isStealthed and (playerClass == "ROGUE" or currentForm == 0 or currentForm == 1) then
            if panelConfig.requiredForm ~= nil and panelConfig.requiredForm ~= "stealth" then
                return false
            end
        end
    end

    return true
end

local function CheckPanelVisibility(panelConfig, event)
    if not panelConfig or not panelConfig.enabled then return false end

    if sfui.movers and sfui.movers.isUnlocked then
        return MatchesCurrentForm(panelConfig)
    end

    if _G["SfuiCooldownsViewer"] and _G["SfuiCooldownsViewer"]:IsShown() then
        local tabId = _G["SfuiCooldownsViewer"].selectedTabId
        if tabId == 1 or tabId == 3 then
            return true
        end
    end

    if not MatchesCurrentForm(panelConfig) then
        return false
    end

    local isStealthed = IsStealthed()
    local inCombat = is_in_combat(event)
    local isStealthPanelActive = (panelConfig.requiredForm == "stealth" and isStealthed)
    if not isStealthPanelActive and GetIconValue(nil, panelConfig, "hideOOC", false) and not inCombat then return false end

    if not inCombat and not isStealthPanelActive then
        if GetIconValue(nil, panelConfig, "hideMounted", false) and sfui.common.is_mounted_or_travel_form() then return false end
        if GetIconValue(nil, panelConfig, "hideInVehicle", true) and (UnitHasVehicleUI("player") or UnitInVehicle("player")) then return false end
        if panelConfig.hideDragonriding and sfui.common.IsDragonriding and sfui.common.IsDragonriding() then return false end
    end

    local globalVis = SfuiDB and SfuiDB.iconGlobalSettings
    if globalVis and not isStealthPanelActive then
        if globalVis.hideOOC and not inCombat then return false end
        if globalVis.hideDragonriding and sfui.common.IsDragonriding and sfui.common.IsDragonriding() and not inCombat then return false end
    end

    local visMode = panelConfig.visibility
    if not visMode and globalVis then visMode = globalVis.visibility end
    visMode = visMode or "always"

    if visMode == "combat" and not isStealthPanelActive then
        if not inCombat then return false end
    elseif visMode == "noCombat" then
        if inCombat then return false end
    end

    if panelConfig.hideIfEmpty then
        local activeEntries = sfui.common.get_active_panel_entries(panelConfig, _staticActiveEntries)
        if #activeEntries == 0 then
            return false
        end
    end

    return true
end

function sfui.trackedicons.OnVisibilityEvent(_, event)
    for _, panelFrame in pairs(panels) do
        if panelFrame.config then
            local shouldShow = CheckPanelVisibility(panelFrame.config, event)
            if shouldShow then
                if not panelFrame:IsShown() then panelFrame:Show() end
                if panelFrame.icons then
                    for _, icon in pairs(panelFrame.icons) do
                        UpdateIconState(icon, panelFrame.config, event)
                    end
                end
            else
                HidePanelAndStopGlows(panelFrame)
            end
        end
    end
end

local function ApplyAutoSpan(panelConfig, activeIcons, size, spacing, numColumns, _growthH, targetFrame)
    local spanWidth = GetIconValue(nil, panelConfig, "spanWidth", false)
    if spanWidth and activeIcons and #activeIcons >= 4 then
        local targetWidth = (sfui.config and sfui.config.healthBar and sfui.config.healthBar.width) or 300
        if targetFrame and targetFrame ~= UIParent and targetFrame.GetWidth then
            local tw = targetFrame:GetWidth()
            if tw and tw > 1 then targetWidth = tw end
        elseif _G["sfui_bar0_Backdrop"] then
            local bw = _G["sfui_bar0_Backdrop"]:GetWidth()
            if bw and bw > 1 then targetWidth = bw end
        end

        local iconsPerRow = math.min(numColumns, #activeIcons)
        if iconsPerRow < 4 then return size, spacing end

        local currentWidth = (iconsPerRow * size) + (math.max(0, iconsPerRow - 1) * spacing)

        if currentWidth < targetWidth then
            if iconsPerRow > 1 then
                spacing = (targetWidth - (iconsPerRow * size)) / (iconsPerRow - 1)
            end
        else
            local newSize = (targetWidth - (math.max(0, iconsPerRow - 1) * spacing)) / iconsPerRow
            if newSize < 10 then newSize = 10 end
            size = newSize
        end
    end
    return size, spacing
end

local function ApplyPanelAnchor(panelFrame, panelConfig)
    panelFrame:ClearAllPoints()

    local isCenter = IsPrimaryFormPanel(panelConfig)
    if panelConfig.customMover then
        local pt = panelConfig.moverPoint or panelConfig.anchorPoint or GetPanelIconAnchor(panelConfig)
        local relPt = panelConfig.moverRelPoint or pt
        panelFrame:SetPoint(pt, UIParent, relPt, panelConfig.x or 0, panelConfig.y or 0)
        return UIParent
    end

    local anchorTo = panelConfig.anchorTo or (isCenter and "Health Bar" or "UIParent")
    local targetFrame = UIParent
    local targetPoint = panelConfig.relativePoint or "BOTTOM"
    local anchorPoint = panelConfig.anchorPoint or "BOTTOM"

    local isHealthBarAnchor = (anchorTo == "Health Bar")
    local isSwingBarAnchor = (anchorTo == "Swing Bar")

    if isHealthBarAnchor or isSwingBarAnchor then
        local bar0 = _G["sfui_bar0_Backdrop"] or (sfui.bars and sfui.bars.get_bar0 and sfui.bars.get_bar0().backdrop)
        if not bar0 and sfui.bars and sfui.bars.get_bar0 then
            local b0 = sfui.bars.get_bar0()
            bar0 = b0 and b0.backdrop
        end
        if bar0 then
            targetFrame = bar0
            targetPoint = "BOTTOM"
            anchorPoint = "TOP"

            local powerBar = _G["sfui_bar_minus_1_Backdrop"] or _G["sfui_bar-1_Backdrop"]
                or (sfui.bars.get_bar_minus_1 and sfui.bars.get_bar_minus_1().backdrop)
            if powerBar and (powerBar:IsShown() or (SfuiDB == nil or SfuiDB.enablePowerBar ~= false)) then
                targetFrame = powerBar
                targetPoint = "BOTTOM"
            end

            if not sfui.isRetail and sfui.swing and sfui.swing.IsPossible() then
                local swingBar = (sfui.swing.GetLowestPossibleBar and sfui.swing.GetLowestPossibleBar())
                    or (sfui.swing.GetLowestBar and sfui.swing.GetLowestBar(true))
                if swingBar and swingBar:GetNumPoints() > 0 then
                    targetFrame = swingBar
                    targetPoint = "BOTTOM"
                    anchorPoint = "TOP"
                end
            end
        end
    elseif anchorTo == "Tracked Bars" and _G["SfuiTrackedBarsContainer"] then
        targetFrame = _G["SfuiTrackedBarsContainer"]
        targetPoint = "TOP"
        anchorPoint = "BOTTOM"
    elseif anchorTo ~= "UIParent" then
        local searchTarget = anchorTo
        local resolvedTarget = nil

        for _, otherPanel in pairs(panels) do
            if otherPanel.config and otherPanel.config.name == searchTarget then
                if otherPanel:IsShown() or MatchesCurrentForm(otherPanel.config) then
                    resolvedTarget = otherPanel
                    break
                elseif searchTarget == "CENTER" or searchTarget == "BATTLE" then
                    for _, p in pairs(panels) do
                        if p.config and p.config.enabled and IsPrimaryFormPanel(p.config) and (p:IsShown() or MatchesCurrentForm(p.config)) then
                            resolvedTarget = p
                            break
                        end
                    end
                    break
                end
            end
        end

        if resolvedTarget and resolvedTarget ~= panelFrame then
            targetFrame = resolvedTarget
            targetPoint = "BOTTOM"
            anchorPoint = "TOP"
        else
            for _, otherPanel in pairs(panels) do
                if otherPanel.config and otherPanel.config.name == anchorTo then
                    if otherPanel ~= panelFrame then
                        targetFrame = otherPanel
                        targetPoint = "BOTTOM"
                        anchorPoint = "TOP"
                    else
                        targetFrame = UIParent
                        targetPoint = "BOTTOM"
                        anchorPoint = "BOTTOM"
                    end
                    break
                end
            end
        end
    end

    if targetFrame == UIParent and (isHealthBarAnchor or isSwingBarAnchor) then
        anchorPoint = "CENTER"
        targetPoint = "CENTER"
    end

    panelFrame:SetPoint(anchorPoint, targetFrame, targetPoint, panelConfig.x or 0, panelConfig.y or 0)
    return targetFrame
end

function sfui.trackedicons.UpdatePanelLayout(panelFrame, panelConfig, event)
    if not panelFrame or not panelConfig then return end
    panelFrame.config = panelConfig

    if panelFrame.visHandler then
        local onEvent = panelFrame.visHandler:GetScript("OnEvent")
        if onEvent then onEvent(panelFrame.visHandler) end
    end

    local targetFrame = ApplyPanelAnchor(panelFrame, panelConfig)

    if panelFrame.icons then
        for _, icon in pairs(panelFrame.icons) do
            if icon._glowActive then StopGlow(icon) end
            icon:Hide()
            icon:ClearAllPoints()
        end
    else
        panelFrame.icons = {}
    end

    local activeIcons = _staticActiveIcons
    wipe(activeIcons)
    local entries = sfui.common.get_active_panel_entries(panelConfig, _staticActiveEntries)

    for i, entry in ipairs(entries) do
        local id = (type(entry) == "table" and entry.id) or entry
        if id then
            if not panelFrame.icons[i] then
                panelFrame.icons[i] = CreateIconFrame(panelFrame, id, entry, panelConfig)
            end

            local icon = panelFrame.icons[i]
            if icon then
                icon.id = id
                if type(entry) == "table" then
                    icon.type = entry.type
                    icon.entry = entry
                else
                    icon.type = "spell"
                    local fb = icon._fallbackEntry
                    if not fb then
                        fb = { id = id, type = "spell" }
                        icon._fallbackEntry = fb
                    else
                        fb.id = id
                        fb.type = "spell"
                    end
                    icon.entry = fb
                end

                entryHelper.CompileDescriptor(icon, panelConfig, GetIconValue, sfui.trackedicons.GetIconTexture)
                sfui.trackedicons.ApplyIconBorderStyle(icon, panelConfig)
                SyncIconMasque(icon)
                UpdateIconState(icon, panelConfig, event)
                activeIcons[#activeIcons + 1] = icon
            end
        end
    end

    -- Cleanup surplus pooled icons without freeing frames
    if panelFrame.icons then
        for x = #entries + 1, #panelFrame.icons do
            local oldIcon = panelFrame.icons[x]
            if oldIcon then
                if oldIcon._glowActive then StopGlow(oldIcon) end
                if iconAura and iconAura.Reset then iconAura.Reset(oldIcon) end
                oldIcon:Hide()
                oldIcon.id = nil
                oldIcon.entry = nil
                oldIcon._desc = nil
            end
        end
    end

    local numColumns = panelConfig.columns or #activeIcons
    if IsPrimaryFormPanel(panelConfig) then
        numColumns = #activeIcons
    end
    if numColumns < 1 then numColumns = 1 end

    local growthH = panelConfig.growthH or "Right"
    local growthV = panelConfig.growthV or "Down"
    local hSign = (growthH == "Left") and -1 or 1
    local vSign = (growthV == "Up") and 1 or -1
    local iconAnchor = GetPanelIconAnchor(panelConfig)

    local size = tonumber(GetIconValue(nil, panelConfig, "size", 40)) or 40
    local spacing = tonumber(GetIconValue(nil, panelConfig, "spacing", 2)) or 2
    local maxWidth, maxHeight = 0, 0

    size, spacing = ApplyAutoSpan(panelConfig, activeIcons, size, spacing, numColumns, growthH, targetFrame)

    if growthH == "Center" then
        local totalIcons = #activeIcons
        for i, icon in ipairs(activeIcons) do
            icon:ClearAllPoints()
            icon:SetSize(size, size)

            local row = math.floor((i - 1) / numColumns)
            local colInRow = (i - 1) % numColumns
            local startIdx = row * numColumns + 1
            local endIdx = math.min((row + 1) * numColumns, totalIcons)
            local numInRow = endIdx - startIdx + 1

            local centerOffset = colInRow - (numInRow - 1) / 2
            local ox = centerOffset * (size + spacing)
            local oy = row * (size + spacing) * vSign

            icon:SetPoint(iconAnchor, panelFrame, iconAnchor, ox, oy)

            local rowWidth = numInRow * size + math.max(0, numInRow - 1) * spacing
            maxWidth = math.max(maxWidth, rowWidth)
            maxHeight = math.max(maxHeight, (row + 1) * (size + spacing) - spacing)
        end
    else
        for idx, icon in ipairs(activeIcons) do
            icon:ClearAllPoints()
            icon:SetSize(size, size)

            local col = (idx - 1) % numColumns
            local row = math.floor((idx - 1) / numColumns)
            local ox = col * (size + spacing) * hSign
            local oy = row * (size + spacing) * vSign

            icon:SetPoint(iconAnchor, panelFrame, iconAnchor, ox, oy)

            maxWidth = math.max(maxWidth, (col + 1) * size + col * spacing)
            maxHeight = math.max(maxHeight, (row + 1) * size + row * spacing)
        end
    end

    local showBG = GetIconValue(nil, panelConfig, "showBackground", true)
    local bgAlpha = GetIconValue(nil, panelConfig, "backgroundAlpha", 0.5)

    local anyVisible = false
    for _, icon in ipairs(activeIcons) do
        if icon:IsShown() then
            anyVisible = true
            break
        end
    end

    if showBG and anyVisible then
        if not panelFrame.bg then
            panelFrame.bg = CreateFrame("Frame", nil, panelFrame, "BackdropTemplate")
            panelFrame.bg:SetFrameStrata("BACKGROUND")
            panelFrame.bg:SetBackdrop({
                bgFile = "Interface/Buttons/WHITE8X8",
                insets = { left = 0, right = 0, top = 0, bottom = 0 }
            })
            panelFrame.bg:SetBackdropColor(0, 0, 0, bgAlpha)
        else
            panelFrame.bg:SetBackdropColor(0, 0, 0, bgAlpha)
            panelFrame.bg:Show()
        end

        panelFrame.bg:ClearAllPoints()
        panelFrame.bg:SetAllPoints(panelFrame)
    elseif panelFrame.bg then
        panelFrame.bg:Hide()
    end

    if #activeIcons == 0 and sfui.movers and sfui.movers.isUnlocked then
        local spanWidth = GetIconValue(nil, panelConfig, "spanWidth", false)
        if spanWidth then
            local bw = (targetFrame and targetFrame ~= UIParent and targetFrame.GetWidth and targetFrame:GetWidth())
                or (_G["sfui_bar0_Backdrop"] and _G["sfui_bar0_Backdrop"]:GetWidth())
                or (sfui.config and sfui.config.healthBar and sfui.config.healthBar.width)
                or 250
            maxWidth = math.max(size, bw)
        else
            local previewCols = math.max(1, math.min(tonumber(panelConfig.columns) or 4, 4))
            maxWidth = math.max(size, previewCols * size + math.max(0, previewCols - 1) * spacing)
        end
        maxHeight = size
    end

    panelFrame:SetSize(math.max(maxWidth, 1), math.max(maxHeight, 1))
end

function sfui.trackedicons.ForceRefreshGlows()
    for _, panel in pairs(panels) do
        if panel.icons then
            for _, icon in pairs(panel.icons) do
                if icon._glowActive then
                    StopGlow(icon)
                end
            end
        end
    end
end

local function SanitizePanelConfig(panelConfig)
    if not panelConfig then return end

    local keysToPurge = {
        "readyGlow", "useSpecColor", "glowType", "glowColor",
        "glowScale", "glowSpeed", "glowIntensity", "glow_max_duration",
        "glowLines", "glowParticles", "glowThickness",
        "cooldownDesat", "useResourceCheck",
        "textEnabled", "alphaOnCooldown",
        "textColor", "squareIcons", "showBorder"
    }

    local igs = SfuiDB and SfuiDB.iconGlobalSettings
    if igs and igs.alphaOnCooldown == 0 then
        igs.alphaOnCooldown = 1.0
    end

    for _, key in ipairs(keysToPurge) do
        panelConfig[key] = nil
    end

    if panelConfig.entries then
        for _, entry in ipairs(panelConfig.entries) do
            if type(entry) == "table" and entry.settings then
                for _, key in ipairs(keysToPurge) do
                    entry.settings[key] = nil
                end
            end
        end
    end
end

function sfui.trackedicons.ForceLayoutUpdate()
    _layoutCooldown = 0
    _needsLayoutUpdate = false
    _needsStateUpdate = false
    entryHelper.InvalidateCooldownInfoCache()
    sfui.trackedicons.Update()
end

local _editModePrepared = false
local _pendingEditModeSync = false

local function GetPanelMoverLabel(panelConfig, index)
    local rawName = (panelConfig and panelConfig.name) or ("panel " .. tostring(index))
    return "icons: " .. string.lower(rawName)
end

local function SyncSiblingFormPanels(sourceCfg)
    if not IsPrimaryFormPanel(sourceCfg) then return end
    local panelConfigs = sfui.common.get_cooldown_panels()
    if not panelConfigs then return end
    for _, otherCfg in ipairs(panelConfigs) do
        if otherCfg ~= sourceCfg and IsPrimaryFormPanel(otherCfg) then
            otherCfg.customMover = sourceCfg.customMover
            otherCfg.moverPoint = sourceCfg.moverPoint
            otherCfg.moverRelPoint = sourceCfg.moverRelPoint
            otherCfg.anchorTo = sourceCfg.anchorTo
            otherCfg.anchorPoint = sourceCfg.anchorPoint
            otherCfg.relativePoint = sourceCfg.relativePoint
            otherCfg.x = sourceCfg.x
            otherCfg.y = sourceCfg.y
        end
    end
end

local function RefreshDependentPanelAnchors(movedPanelFrame)
    for _, otherFrame in pairs(panels) do
        if otherFrame ~= movedPanelFrame and otherFrame.config and otherFrame.config.enabled and not otherFrame.config.customMover then
            local aTo = otherFrame.config.anchorTo
            if aTo and aTo ~= "UIParent" and aTo ~= "Health Bar" and aTo ~= "Swing Bar" and aTo ~= "Tracked Bars" then
                ApplyPanelAnchor(otherFrame, otherFrame.config)
            end
        end
    end
end

local function ResetPanelPositionConfig(cfg)
    if not cfg then return end
    local defs = sfui.config and sfui.config.cooldown_panel_defaults
    local uName = (cfg.name and string.upper(cfg.name)) or ""

    cfg.customMover = nil
    cfg.moverPoint = nil
    cfg.moverRelPoint = nil
    cfg.relativePoint = nil

    if IsPrimaryFormPanel(cfg) then
        local d = defs and defs.center_panel
        cfg.anchorTo = (d and d.anchorTo) or "Health Bar"
        cfg.anchorPoint = (d and d.anchorPoint) or "TOP"
        cfg.x = (d and d.x) or 0
        cfg.y = (d and d.y) or 0
    elseif uName == "UTILITY" then
        local d = defs and defs.utility
        cfg.anchorTo = (d and d.anchorTo) or "CENTER"
        cfg.anchorPoint = (d and d.anchorPoint) or "TOP"
        cfg.x = (d and d.x) or 0
        cfg.y = (d and d.y) or 0
    elseif uName == "LEFT" then
        local d = defs and defs.left
        cfg.anchorTo = d and d.anchorTo or nil
        cfg.anchorPoint = (d and d.anchorPoint) or "TOPLEFT"
        cfg.x = (d and d.x) or -425
        cfg.y = (d and d.y) or 295
    elseif uName == "RIGHT" then
        local d = defs and defs.right
        cfg.anchorTo = d and d.anchorTo or nil
        cfg.anchorPoint = (d and d.anchorPoint) or "TOPRIGHT"
        cfg.x = (d and d.x) or 425
        cfg.y = (d and d.y) or 295
    else
        local d = defs and defs.utility
        cfg.anchorTo = (d and d.anchorTo) or "CENTER"
        cfg.anchorPoint = (d and d.anchorPoint) or "TOP"
        cfg.x = (d and d.x) or 0
        cfg.y = (d and d.y) or 0
    end
end

function sfui.trackedicons.ResetPanelPosition(panelConfig)
    if not panelConfig then return end
    ResetPanelPositionConfig(panelConfig)
    SyncSiblingFormPanels(panelConfig)
    sfui.trackedicons.Update()
    if sfui.movers and sfui.movers.isUnlocked then
        sfui.trackedicons.SyncMovers()
    end
    if sfui.trackedoptions and sfui.trackedoptions.SyncPanelPositionControls then
        sfui.trackedoptions.SyncPanelPositionControls(panelConfig)
    end
end

local function EnsureEditModePrepared()
    if sfui.movers and sfui.movers.isUnlocked and not _editModePrepared then
        _editModePrepared = true
        sfui.trackedicons.Update()
    end
end

local function EnsurePanelMoverRegistered(index, panelFrame)
    if not panelFrame or not sfui.movers or not sfui.movers.Register then return end
    local key = "trackedicons_" .. tostring(index)
    local cfg = panelFrame.config
    local label = GetPanelMoverLabel(cfg, index)
    local prefPt = GetPanelIconAnchor(cfg)

    if panelFrame._moverRegistered and sfui.movers.registry and sfui.movers.registry[key] then
        local reg = sfui.movers.registry[key]
        reg.label = label
        reg.preferredPoint = prefPt
        local mover = sfui.movers.list and sfui.movers.list[key]
        if mover then
            mover.targetFrame = panelFrame
            if not mover._isDragging and mover.label then
                mover.label:SetText(label)
            end
        end
        return
    end

    panelFrame._moverRegistered = true
    sfui.movers.Register(panelFrame, {
        key = key,
        label = label,
        preferredPoint = prefPt,
        customSize = function()
            local p = panels[index]
            if not p then return 120, 40 end
            return p:GetWidth(), p:GetHeight()
        end,
        getPoint = function()
            local p = panels[index]
            local pCfg = p and p.config
            local pPt = GetPanelIconAnchor(pCfg)
            if pCfg and pCfg.customMover then
                local pt = pCfg.moverPoint or pCfg.anchorPoint or pPt
                local relPt = pCfg.moverRelPoint or pt
                return pt, UIParent, relPt, pCfg.x or 0, pCfg.y or 0
            end
            if p and sfui.movers and sfui.movers.CalculateRelativeCoordinates then
                local left = p:GetLeft()
                local bottom = p:GetBottom()
                local w = p:GetWidth()
                local h = p:GetHeight()
                if left and bottom and w and h and w > 0 and h > 0 then
                    local pt, relPt, x, y = sfui.movers.CalculateRelativeCoordinates(left, bottom, w, h, pPt)
                    return pt, UIParent, relPt, x, y
                end
            end
            return pPt, UIParent, pPt, (pCfg and pCfg.x) or 0, (pCfg and pCfg.y) or 0
        end,
        setPoint = function(point, _relTo, relPoint, x, y)
            local p = panels[index]
            local pCfg = p and p.config
            if not pCfg then return end
            local savedPt = point or GetPanelIconAnchor(pCfg)
            local savedRel = relPoint or savedPt
            pCfg.customMover = true
            pCfg.anchorTo = "UIParent"
            pCfg.moverPoint = savedPt
            pCfg.moverRelPoint = savedRel
            pCfg.anchorPoint = savedPt
            pCfg.relativePoint = savedRel
            pCfg.x = x or 0
            pCfg.y = y or 0

            SyncSiblingFormPanels(pCfg)
            ApplyPanelAnchor(p, pCfg)
            RefreshDependentPanelAnchors(p)
            sfui.trackedicons.SyncMovers()
            if sfui.trackedoptions and sfui.trackedoptions.SyncPanelPositionControls then
                sfui.trackedoptions.SyncPanelPositionControls(pCfg)
            end
        end,
        resetPosition = function()
            local p = panels[index]
            local pCfg = p and p.config
            if not pCfg then return end
            sfui.trackedicons.ResetPanelPosition(pCfg)
        end,
        isEnabled = function()
            EnsureEditModePrepared()
            local p = panels[index]
            local pCfg = p and p.config
            if not p or not pCfg or not pCfg.enabled then return false end
            return MatchesCurrentForm(pCfg)
        end,
        onEnterEditMode = function()
            EnsureEditModePrepared()
            if not _pendingEditModeSync and _G.C_Timer and _G.C_Timer.After then
                _pendingEditModeSync = true
                _G.C_Timer.After(0, function()
                    _pendingEditModeSync = false
                    if sfui.movers and sfui.movers.isUnlocked then
                        sfui.trackedicons.Update()
                        sfui.trackedicons.SyncMovers()
                    end
                end)
            end
        end,
        onExitEditMode = function()
            if _editModePrepared then
                _editModePrepared = false
                sfui.trackedicons.Update()
            end
        end,
    })
end

function sfui.trackedicons.SyncMovers()
    local m = sfui.movers
    if not m or not m.list or not m.registry then return end

    local replacementSelectedKey = nil
    for idx, panelFrame in pairs(panels) do
        local key = "trackedicons_" .. tostring(idx)
        local mover = m.list[key]
        local reg = m.registry[key]
        if mover and reg then
            local cfg = panelFrame.config
            local lbl = GetPanelMoverLabel(cfg, idx)
            reg.label = lbl
            reg.preferredPoint = GetPanelIconAnchor(cfg)
            if not mover._isDragging and mover.label then
                mover.label:SetText(lbl)
            end

            if m.isUnlocked then
                local enabled = (cfg and cfg.enabled and MatchesCurrentForm(cfg)) or false
                if enabled then
                    if not mover._isDragging then
                        if reg.customSize then
                            local w, h = reg.customSize()
                            if w and h and w > 0 and h > 0 then
                                mover:SetSize(w, h)
                            end
                        end
                        if reg.getPoint then
                            local pt, relTo, relPt, x, y = reg.getPoint()
                            if pt then
                                mover._anchorPoint = pt
                                mover._lastSavedPt = pt
                                mover._lastSavedX = x or 0
                                mover._lastSavedY = y or 0
                                mover:ClearAllPoints()
                                mover:SetPoint(pt, relTo or UIParent, relPt or pt, x or 0, y or 0)
                            end
                        end
                    end
                    mover:EnableMouse(true)
                    mover:Show()
                    if not replacementSelectedKey and IsPrimaryFormPanel(cfg) then
                        replacementSelectedKey = key
                    end
                else
                    mover:EnableMouse(false)
                    mover:Hide()
                end
            end
        end
    end

    if m.isUnlocked then
        if m.selectedKey and m.list[m.selectedKey] and not m.list[m.selectedKey]:IsShown() and replacementSelectedKey then
            m.selectedKey = replacementSelectedKey
        end
        if m.RefreshMoverVisuals then
            m.RefreshMoverVisuals()
        end
    end
end

function sfui.trackedicons.Update(event)
    sfui.trackedicons.InvalidateConfigCache()
    local panelConfigs = sfui.common.get_cooldown_panels()
    if not panelConfigs or #panelConfigs == 0 then
        SyncIconAuraWatchlist()
        return
    end

    for i, panelConfig in ipairs(panelConfigs) do
        if panelConfig.enabled then
            if not panels[i] then
                panels[i] = CreateFrame("Frame", "SfuiIconPanel_" .. i, UIParent)
            end
            panels[i].config = panelConfig
        elseif panels[i] then
            panels[i].config = panelConfig
            HidePanelAndStopGlows(panels[i])
        end
    end

    for i = #panelConfigs + 1, #panels do
        if panels[i] then
            panels[i].config = nil
            HidePanelAndStopGlows(panels[i])
        end
    end

    for i, panelConfig in ipairs(panelConfigs) do
        if panelConfig.enabled and panels[i] then
            sfui.trackedicons.UpdatePanelLayout(panels[i], panelConfig, event)

            local shouldShow = CheckPanelVisibility(panelConfig, event)
            if shouldShow then
                panels[i]:Show()
            else
                HidePanelAndStopGlows(panels[i])
            end

            EnsurePanelMoverRegistered(i, panels[i])
        end
    end

    SyncIconAuraWatchlist()

    if sfui.movers and sfui.movers.isUnlocked and not sfui.movers._isToggling then
        sfui.trackedicons.SyncMovers()
    end
end

function sfui.trackedicons.initialize()
    if (sfui.isRetail or sfui.isCamelot) and not sfui.common.is_addon_loaded("Blizzard_CooldownViewer") then
        sfui.common.ensure_addon_loaded("Blizzard_CooldownViewer")
    end

    sfui.common.hide_blizzard_cooldown_viewers()

    local function UpdateAllIconStates()
        if _needsWatchlistSync then
            SyncIconAuraWatchlist()
        end
        for _, panel in pairs(panels) do
            if panel:IsShown() and panel.icons and panel.config then
                local config = panel.config
                for _, icon in pairs(panel.icons) do
                    UpdateIconState(icon, config)
                end
            end
        end
    end

    local _lastCombatState = nil

    sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", function()
        _lastCombatState = false
        sfui.trackedicons.OnVisibilityEvent(nil, "PLAYER_REGEN_ENABLED")
        MarkDirty(false)
    end)
    sfui.events.RegisterEvent("PLAYER_REGEN_DISABLED", function()
        _lastCombatState = true
        sfui.trackedicons.OnVisibilityEvent(nil, "PLAYER_REGEN_DISABLED")
        MarkDirty(false)
    end)
    sfui.events.RegisterUnitEvent("UNIT_FLAGS", "player", function()
        sfui.trackedicons.OnVisibilityEvent(nil, "UNIT_FLAGS")
        MarkDirty(false)
    end)
    sfui.events.RegisterUnitEvent("PLAYER_FLAGS_CHANGED", "player", function()
        sfui.trackedicons.OnVisibilityEvent(nil, "PLAYER_FLAGS_CHANGED")
        MarkDirty(false)
    end)
    sfui.events.RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED", function()
        sfui.trackedicons.OnVisibilityEvent(nil, "PLAYER_MOUNT_DISPLAY_CHANGED")
        MarkDirty(false)
    end)
    sfui.events.RegisterUnitEvents({ "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE" }, "player", function(event)
        sfui.trackedicons.OnVisibilityEvent(nil, event)
        MarkDirty(false)
    end)
    sfui.events.RegisterEvent("UPDATE_BONUS_ACTIONBAR", function()
        sfui.trackedicons.OnVisibilityEvent(nil, "UPDATE_BONUS_ACTIONBAR")
        MarkDirty(false)
    end)
    if sfui.isRetail then
        sfui.events.RegisterEvent("PLAYER_CAN_GLIDE_CHANGED", function()
            sfui.trackedicons.OnVisibilityEvent(nil, "PLAYER_CAN_GLIDE_CHANGED")
            MarkDirty(false)
        end)
    end
    sfui.events.RegisterUnitEvent("UNIT_POWER_BAR_SHOW", "player", function()
        sfui.trackedicons.OnVisibilityEvent(nil, "UNIT_POWER_BAR_SHOW")
    end)
    sfui.events.RegisterUnitEvent("UNIT_POWER_BAR_HIDE", "player", function()
        sfui.trackedicons.OnVisibilityEvent(nil, "UNIT_POWER_BAR_HIDE")
    end)
    sfui.events.RegisterEvent("UPDATE_SHAPESHIFT_FORM", function()
        sfui.trackedicons.Update("UPDATE_SHAPESHIFT_FORM")
    end)
    sfui.events.RegisterEvent("UPDATE_SHAPESHIFT_FORMS", function()
        sfui.trackedicons.Update("UPDATE_SHAPESHIFT_FORMS")
    end)
    sfui.events.RegisterEvent("UPDATE_STEALTH", function()
        sfui.trackedicons.Update("UPDATE_STEALTH")
    end)

    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        sfui.common.ensure_panels_initialized()
        sfui.trackedicons.Update()
    end)

    sfui.events.RegisterEvent("TRAIT_CONFIG_UPDATED", function()
        MarkDirty(not InCombatLockdown())
    end)
    sfui.events.RegisterEvent("PLAYER_TALENT_UPDATE", function()
        MarkDirty(not InCombatLockdown())
    end)
    sfui.events.RegisterEvent("SPELLS_CHANGED", function()
        MarkDirty(not InCombatLockdown())
    end)

    sfui.events.RegisterEvent("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED", function()
        entryHelper.InvalidateCooldownInfoCache()
        entryHelper.BumpConfigRevision()
        _needsWatchlistSync = true
        _needsStateUpdate = true
    end)

    -- Soul fragments, charges, and spell use-count updates (CooldownViewer.lua:805)
    sfui.events.RegisterEvent("SPELL_UPDATE_CHARGES", function()
        _needsStateUpdate = true
    end)
    sfui.events.RegisterEvent("SPELL_UPDATE_USES", function()
        _needsStateUpdate = true
    end)

    -- UNIT_POWER_UPDATE covers resource pools (throttled in combat to 0.25s)
    local _lastCombatPowerTime = 0
    sfui.events.RegisterUnitEvent("UNIT_POWER_UPDATE", "player", function()
        if is_in_combat() then
            local now = GetTime()
            if (now - _lastCombatPowerTime) >= 0.25 then
                _lastCombatPowerTime = now
                _needsStateUpdate = true
            end
        end
    end)

    sfui.events.RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", function()
        _needsStateUpdate = true
    end)

    sfui.events.RegisterEvent("SPELL_UPDATE_COOLDOWN", function()
        _needsStateUpdate = true
    end)

    sfui.events.RegisterEvent("BAG_UPDATE_COOLDOWN", function()
        _needsStateUpdate = true
    end)

    sfui.events.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function()
        entryHelper.BumpConfigRevision()
        MarkDirty(not InCombatLockdown())
        _needsStateUpdate = true
    end)

    sfui.events.RegisterEvent("BAG_UPDATE_DELAYED", function()
        _needsStateUpdate = true
    end)

    local function OnIconAssetLoaded()
        local hasColdIcon = false
        for _, panel in pairs(panels) do
            if panel.icons then
                for _, icon in pairs(panel.icons) do
                    if icon:IsShown() and (
                        (icon._desc and icon._desc._iconCold)
                        or not IsValidTexture(icon._currentTexture)
                        or (icon.texture and not IsValidTexture(icon.texture:GetTexture()))
                    ) then
                        hasColdIcon = true
                        break
                    end
                end
            end
            if hasColdIcon then break end
        end
        if hasColdIcon then
            entryHelper.BumpConfigRevision()
            _needsStateUpdate = true
        end
    end
    sfui.events.RegisterEvent("SPELL_UPDATE_ICON", OnIconAssetLoaded)
    sfui.events.RegisterEvent("SPELL_DATA_LOAD_RESULT", OnIconAssetLoaded)
    sfui.events.RegisterEvent("GET_ITEM_INFO_RECEIVED", OnIconAssetLoaded)

    -- 12.0.5+: Blizzard aura data provider switch (e.g. M+ restricted mode transitions)
    sfui.events.RegisterEvent("AURA_DATA_PROVIDER_SWITCH", function(_event, useRealDataProvider)
        for _, panel in pairs(panels) do
            if panel.icons then
                for _, icon in pairs(panel.icons) do
                    if iconAura and iconAura.Reset then
                        iconAura.Reset(icon)
                    end
                    if not useRealDataProvider then
                        if icon.cooldown then icon.cooldown:Clear() end
                        if icon.count then icon.count:Hide() end
                        icon._lastCount = nil
                        icon._wasOnCooldown = false
                        icon._pendingGlow = false
                    end
                end
            end
        end
        MarkDirty(true)
    end)

    -- OnUpdate: only process when dirty (zero CPU/allocations when idle)
    local _lastStateUpdateTime = 0
    local function _OnTrackedIconsUpdate(elapsed)
        local inCombat = is_in_combat()
        if _lastCombatState == nil then
            _lastCombatState = inCombat
        elseif _lastCombatState ~= inCombat then
            _lastCombatState = inCombat
            sfui.trackedicons.OnVisibilityEvent(nil, inCombat and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
            MarkDirty(false)
        end

        if _layoutCooldown > 0 then
            _layoutCooldown = _layoutCooldown - elapsed
        end

        if _needsLayoutUpdate and _layoutCooldown <= 0 then
            _needsLayoutUpdate = false
            _needsStateUpdate = false
            _layoutCooldown = 0.5
            entryHelper.InvalidateCooldownInfoCache()
            sfui.trackedicons.Update()
        elseif _needsStateUpdate then
            local now = GetTime()
            if not is_in_combat() or (now - _lastStateUpdateTime) >= 0.20 then
                _lastStateUpdateTime = now
                _needsStateUpdate = false
                UpdateAllIconStates()
            end
        elseif _activeGlowCount > 0 then
            for _, panel in pairs(panels) do
                if panel:IsShown() and panel.icons and panel.config then
                    for _, icon in pairs(panel.icons) do
                        if icon._glowActive then
                            iconCooldown.UpdateGlow(
                                icon,
                                icon.entry and icon.entry.settings,
                                panel.config,
                                GetIconValue,
                                true,
                                icon._missingGlow == true,
                                StartGlow,
                                StopGlow
                            )
                        end
                    end
                end
            end
        end
    end

    sfui.events.RegisterUpdate("TrackedIcons", 0.1, _OnTrackedIconsUpdate)

    sfui.common.ensure_panels_initialized()

    if not SfuiDB._panelsSanitizedV2 then
        local panelConfigs = sfui.common.get_cooldown_panels()
        if panelConfigs then
            for _, panelConfig in ipairs(panelConfigs) do
                SanitizePanelConfig(panelConfig)
            end
        end
        SfuiDB._panelsSanitizedV2 = true
    end

    sfui.trackedicons.Update()
end

local _tiDebug = {}
function sfui.trackedicons_debug_info()
    local pCount = 0
    local iCount = 0
    for _, p in pairs(panels) do
        pCount = pCount + 1
        if p.icons then
            for _ in pairs(p.icons) do iCount = iCount + 1 end
        end
    end
    _tiDebug.panels      = pCount
    _tiDebug.icons       = iCount
    _tiDebug.activeGlows = _activeGlowCount
    _tiDebug.cdCache     = entryHelper.GetCooldownInfoCacheCount()
    _tiDebug.auraWatch   = (auraResolver and auraResolver.GetWatchCount and auraResolver.GetWatchCount()) or 0
    _tiDebug.needsState  = _needsStateUpdate
    _tiDebug.needsLayout = _needsLayoutUpdate
    return _tiDebug
end

sfui.trackedicons.OnEnable = function(self) self.initialize() end
sfui.trackedicons.OnSettingsChanged = function(self, _k, _v)
    if self.Update then self.Update() end
end
sfui.trackedicons.OnSpecChanged = function(self, _specID)
    sfui.common.ensure_panels_initialized()
    if self.Update then self.Update() end
end
sfui.trackedicons.GetDebugInfo = sfui.trackedicons_debug_info
sfui.RegisterModule("trackedicons", sfui.trackedicons)
