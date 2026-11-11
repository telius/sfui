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

local _emptyTable = {}
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
    local cacheKey = entrySettings or panelConfig or "global"
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

    local altKey = (key == "textEnabled") and "showText" or ((key == "showText") and "textEnabled" or nil)

    if entrySettings and entrySettings[key] ~= nil then
        val = entrySettings[key]
    elseif altKey and entrySettings and entrySettings[altKey] ~= nil then
        val = entrySettings[altKey]
    elseif panelConfig and panelConfig[key] ~= nil then
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

sfui.trackedicons.StopGlow = sfui.glows.stop_glow

local function StopGlow(icon)
    if icon._glowActive then
        if _activeGlowCount > 0 then
            _activeGlowCount = _activeGlowCount - 1
        end
    end
    sfui.glows.stop_glow(icon)
    icon._lastGlowCfg = nil
    icon._lastGlowType = nil
    icon._glowActive = false
end

local function StartGlow(icon, cfg)
    if not icon._glowActive then
        _activeGlowCount = _activeGlowCount + 1
    end
    sfui.glows.start_glow(icon, cfg)
    icon._glowActive = true
    icon._lastGlowType = cfg.glowType
    if not icon._lastGlowCfg then icon._lastGlowCfg = {} end
    local t = icon._lastGlowCfg
    t.glowType = cfg.glowType
    t.glowColor = cfg.glowColor
    t.glowScale = cfg.glowScale
    t.glowIntensity = cfg.glowIntensity
    t.glowSpeed = cfg.glowSpeed
    t.glowLines = cfg.glowLines
    t.glowThickness = cfg.glowThickness
    t.glowParticles = cfg.glowParticles
end
sfui.trackedicons.StartGlow = StartGlow

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
function sfui.trackedicons.GetIconTexture(id, iconType, entry)
    local activeID = id
    local iconTexture
    local resolvedType = iconType
    local linkedSpellIDs = nil

    local equipSlot = entry and entry.equipSlot
    local spellCategoryID = entry and entry.spellCategoryID
    local cdID = entry and (entry.cooldownID or (iconType == "cooldown" and id)) or nil

    if not equipSlot and not spellCategoryID and cdID then
        local cdInfo = SafeGetCooldownViewerCooldownInfo(cdID)
        if cdInfo then
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
    end

    if equipSlot then
        resolvedType = "item"
        activeID = GetInventoryItemID and GetInventoryItemID("player", equipSlot) or equipSlot
        iconTexture = GetInventoryItemTexture and GetInventoryItemTexture("player", equipSlot)
        if not iconTexture then
            local slotName = (equipSlot == 14) and "Trinket1Slot" or "Trinket0Slot"
            local _, slotTex = GetInventorySlotInfo(slotName)
            iconTexture = slotTex
        end
        return iconTexture or 134400, activeID, resolvedType, nil
    end

    if spellCategoryID then
        resolvedType = "item"
        local catData = (sfui.tracking and sfui.tracking.SPELL_CATEGORY_METADATA and sfui.tracking.SPELL_CATEGORY_METADATA[spellCategoryID])
        local cdInfo = cdID and SafeGetCooldownViewerCooldownInfo(cdID)
        activeID = (cdInfo and cdInfo.lastItemIDForCategory) or (entry and entry.itemID) or (catData and catData.fallbackItemID) or id
        if catData and catData.icon then
            iconTexture = catData.icon
        elseif activeID and activeID > 0 then
            iconTexture = C_Item.GetItemIconByID(activeID)
        end
        return iconTexture or 134400, activeID, resolvedType, nil
    end

    if (iconType == "cooldown" or (entry and entry.cooldownID)) and entry and entry.cooldownID then
        local cdInfo = SafeGetCooldownViewerCooldownInfo(entry.cooldownID)
        if cdInfo then
            linkedSpellIDs = cdInfo.linkedSpellIDs
            if cdInfo.spellID and cdInfo.spellID > 0 then
                activeID = cdInfo.overrideSpellID or cdInfo.spellID
                iconTexture = C_Spell.GetSpellTexture(activeID)
                resolvedType = "spell"
            elseif cdInfo.itemID and cdInfo.itemID > 0 then
                activeID = cdInfo.itemID
                iconTexture = C_Item.GetItemIconByID(activeID)
                resolvedType = "item"
            end
        else
            if entry.spellID and entry.spellID > 0 then
                activeID = entry.spellID
                iconTexture = C_Spell.GetSpellTexture(activeID)
                resolvedType = "spell"
            elseif entry.itemID and entry.itemID > 0 then
                activeID = entry.itemID
                iconTexture = C_Item.GetItemIconByID(activeID)
                resolvedType = "item"
            else
                activeID = entry.spellID or id
                iconTexture = C_Spell.GetSpellTexture(activeID)
                resolvedType = "spell"
                if not iconTexture then
                    iconTexture = C_Item.GetItemIconByID(activeID)
                    if iconTexture then resolvedType = "item" end
                end
            end
        end
    elseif iconType == "item" then
        activeID = (entry and entry.itemID) or id
        iconTexture = C_Item.GetItemIconByID(activeID)
        resolvedType = "item"
    else
        local cdInfo = SafeGetCooldownViewerCooldownInfo(activeID)
        if cdInfo then
            if cdInfo.equipSlot then
                resolvedType = "item"
                activeID = GetInventoryItemID and GetInventoryItemID("player", cdInfo.equipSlot) or cdInfo.equipSlot
                iconTexture = GetInventoryItemTexture and GetInventoryItemTexture("player", cdInfo.equipSlot)
                if not iconTexture then
                    local slotName = (cdInfo.equipSlot == 14) and "Trinket1Slot" or "Trinket0Slot"
                    local _, slotTex = GetInventorySlotInfo(slotName)
                    iconTexture = slotTex
                end
                return iconTexture or 134400, activeID, resolvedType, nil
            elseif cdInfo.spellCategoryID then
                resolvedType = "item"
                local catData = (sfui.tracking and sfui.tracking.SPELL_CATEGORY_METADATA and sfui.tracking.SPELL_CATEGORY_METADATA[cdInfo.spellCategoryID])
                activeID = cdInfo.lastItemIDForCategory or (catData and catData.fallbackItemID) or id
                iconTexture = catData and catData.icon or (activeID and C_Item.GetItemIconByID(activeID))
                return iconTexture or 134400, activeID, resolvedType, nil
            elseif cdInfo.spellID and cdInfo.spellID > 0 then
                activeID = cdInfo.overrideSpellID or cdInfo.spellID
                iconTexture = C_Spell.GetSpellTexture(activeID)
                resolvedType = "spell"
            elseif cdInfo.itemID and cdInfo.itemID > 0 then
                activeID = cdInfo.itemID
                iconTexture = C_Item.GetItemIconByID(activeID)
                resolvedType = "item"
            end
        else
            if sfui.isEra and sfui.tracking and sfui.tracking.ResolveClassicSpellID then
                activeID = sfui.tracking.ResolveClassicSpellID(activeID) or activeID
            end
            iconTexture = C_Spell.GetSpellTexture(activeID)
            resolvedType = "spell"
            if not iconTexture then
                iconTexture = C_Item.GetItemIconByID(activeID)
                resolvedType = "item"
            end
        end
    end

    if not iconTexture and activeID then
        iconTexture = C_Spell.GetSpellTexture(activeID) or C_Item.GetItemIconByID(activeID) or 134400
    end

    return iconTexture, activeID, resolvedType, linkedSpellIDs
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
        if icon.shadowCooldown then
            icon.shadowCooldown:ClearAllPoints()
            icon.shadowCooldown:SetAllPoints(icon.texture)
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

    local shadow = CreateFrame("Cooldown", name .. "_ShadowCD", f, "CooldownFrameTemplate")
    shadow:SetAllPoints(tex)
    shadow:SetDrawSwipe(false)
    shadow:SetDrawEdge(false)
    shadow:SetDrawBling(false)
    shadow:SetHideCountdownNumbers(true)
    shadow:SetAlpha(0)
    f.shadowCooldown = shadow

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

local function CheckPanelVisibility(panelConfig, event)
    if not panelConfig or not panelConfig.enabled then return false end

    if _G["SfuiCooldownsViewer"] and _G["SfuiCooldownsViewer"]:IsShown() then
        local tabId = _G["SfuiCooldownsViewer"].selectedTabId
        if tabId == 1 or tabId == 3 then
            return true
        end
    end

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

    local inCombat = is_in_combat(event)
    local isStealthPanelActive = (panelConfig.requiredForm == "stealth" and isStealthed)
    if not isStealthPanelActive and GetIconValue(nil, panelConfig, "hideOOC", false) and not inCombat then return false end

    if not inCombat and not isStealthPanelActive then
        if GetIconValue(nil, panelConfig, "hideMounted", false) and sfui.common.is_mounted_or_travel_form() then return false end
        if GetIconValue(nil, panelConfig, "hideInVehicle", true) and (UnitHasVehicleUI("player") or UnitInVehicle("player")) then return false end
        if panelConfig.hideDragonriding and sfui.common.is_dragonflying and sfui.common.is_dragonflying() then return false end
    end

    local globalVis = SfuiDB and SfuiDB.iconGlobalSettings
    if globalVis and not isStealthPanelActive then
        if globalVis.hideOOC and not inCombat then return false end
        if globalVis.hideDragonriding and sfui.common.is_dragonflying and sfui.common.is_dragonflying() and not inCombat then return false end
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
                if panelFrame:IsShown() then panelFrame:Hide() end
            end
        end
    end
end

local function ApplyAutoSpan(panelConfig, activeIcons, size, spacing, numColumns, _growthH, targetFrame)
    local spanWidth = GetIconValue(nil, panelConfig, "spanWidth", false)
    if spanWidth and activeIcons and #activeIcons >= 4 then
        local targetWidth = (sfui.config and sfui.config.healthBar and sfui.config.healthBar.width) or 300
        if targetFrame and targetFrame ~= UIParent and targetFrame.GetWidth then
            targetWidth = targetFrame:GetWidth()
        elseif _G["sfui_bar0_Backdrop"] then
            targetWidth = _G["sfui_bar0_Backdrop"]:GetWidth()
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

function sfui.trackedicons.UpdatePanelLayout(panelFrame, panelConfig, event)
    if not panelFrame or not panelConfig then return end
    panelFrame.config = panelConfig

    if panelFrame.visHandler then
        local onEvent = panelFrame.visHandler:GetScript("OnEvent")
        if onEvent then onEvent(panelFrame.visHandler) end
    end

    panelFrame:ClearAllPoints()

    local anchorTo = panelConfig.anchorTo or "UIParent"
    local targetFrame = UIParent
    local targetPoint = "BOTTOM"
    local anchorPoint = panelConfig.anchorPoint or "BOTTOM"

    local uName = panelConfig.name and string.upper(panelConfig.name)
    local isCenter = (uName == "CENTER" or uName == "CAT" or uName == "BEAR" or uName == "MOONKIN" or uName == "STEALTH"
        or uName == "BATTLE" or uName == "DEFENSIVE" or uName == "BERSERKER")
    local isHealthBarAnchor = (anchorTo == "Health Bar")
    local isSwingBarAnchor = (anchorTo == "Swing Bar")

    if isCenter or isHealthBarAnchor or isSwingBarAnchor then
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
                if otherPanel:IsShown() then
                    resolvedTarget = otherPanel
                    break
                elseif searchTarget == "CENTER" or searchTarget == "BATTLE" then
                    for _, p in pairs(panels) do
                        if p:IsShown() and p.config and p.config.anchorTo == "Health Bar" then
                            resolvedTarget = p
                            break
                        end
                    end
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

    if targetFrame == UIParent and (isCenter or isHealthBarAnchor or isSwingBarAnchor) then
        anchorPoint = "CENTER"
        targetPoint = "CENTER"
    end
    local anchor = anchorPoint
    panelFrame:SetPoint(anchorPoint, targetFrame, targetPoint, panelConfig.x or 0, panelConfig.y or 0)

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
    if numColumns < 1 then numColumns = 1 end

    local pName = panelConfig.name and string.upper(panelConfig.name)
    if pName == "CENTER" or pName == "CAT" or pName == "BEAR" or pName == "MOONKIN" or pName == "STEALTH"
        or pName == "BATTLE" or pName == "DEFENSIVE" or pName == "BERSERKER" then
        numColumns = #activeIcons
    end

    local growthH = panelConfig.growthH or "Right"
    local growthV = panelConfig.growthV or "Down"
    local hSign = (growthH == "Left") and -1 or 1
    local vSign = (growthV == "Up") and 1 or -1

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

            icon:SetPoint(anchor, panelFrame, anchor, ox, oy)

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

            icon:SetPoint(anchor, panelFrame, anchor, ox, oy)

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

            sfui.trackedicons.UpdatePanelLayout(panels[i], panelConfig, event)

            local shouldShow = CheckPanelVisibility(panelConfig, event)
            if shouldShow then
                panels[i]:Show()
            else
                panels[i]:Hide()
            end
        elseif panels[i] then
            panels[i].config = panelConfig
            if not InCombatLockdown() then
                panels[i]:Hide()
            end
        end
    end

    for i = #panelConfigs + 1, #panels do
        if panels[i] then
            panels[i].config = nil
            if not InCombatLockdown() then
                panels[i]:Hide()
            end
        end
    end

    SyncIconAuraWatchlist()
end

function sfui.trackedicons.initialize()
    if sfui.isRetail and not sfui.common.is_addon_loaded("Blizzard_CooldownViewer") then
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

    sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", function()
        sfui.trackedicons.OnVisibilityEvent(nil, "PLAYER_REGEN_ENABLED")
        MarkDirty(false)
    end)
    sfui.events.RegisterEvent("PLAYER_REGEN_DISABLED", function()
        sfui.trackedicons.OnVisibilityEvent(nil, "PLAYER_REGEN_DISABLED")
        MarkDirty(false)
    end)
    sfui.events.RegisterUnitEvent("UNIT_FLAGS", "player", function()
        sfui.trackedicons.OnVisibilityEvent(nil, "UNIT_FLAGS")
        MarkDirty(false)
    end)
    sfui.events.RegisterEvent("PLAYER_FLAGS_CHANGED", function()
        sfui.trackedicons.OnVisibilityEvent(nil, "PLAYER_FLAGS_CHANGED")
        MarkDirty(false)
    end)
    sfui.events.RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED", function()
        sfui.trackedicons.OnVisibilityEvent(nil, "PLAYER_MOUNT_DISPLAY_CHANGED")
        MarkDirty(false)
    end)
    sfui.events.RegisterUnitEvent("UNIT_POWER_BAR_SHOW", "player", function()
        sfui.trackedicons.OnVisibilityEvent(nil, "UNIT_POWER_BAR_SHOW")
    end)
    sfui.events.RegisterUnitEvent("UNIT_POWER_BAR_HIDE", "player", function()
        sfui.trackedicons.OnVisibilityEvent(nil, "UNIT_POWER_BAR_HIDE")
    end)
    sfui.events.RegisterEvent("UPDATE_SHAPESHIFT_FORM", function()
        sfui.trackedicons.Update("UPDATE_SHAPESHIFT_FORM")
        MarkDirty(true)
    end)
    sfui.events.RegisterEvent("UPDATE_SHAPESHIFT_FORMS", function()
        sfui.trackedicons.Update("UPDATE_SHAPESHIFT_FORMS")
        MarkDirty(true)
    end)
    sfui.events.RegisterEvent("UPDATE_STEALTH", function()
        sfui.trackedicons.Update("UPDATE_STEALTH")
        MarkDirty(true)
    end)

    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        sfui.common.ensure_panels_initialized()
        sfui.trackedicons.Update()
        MarkDirty(true)
    end)

    local specDebounceTimer = nil
    local function on_tracked_icons_spec_changed()
        if specDebounceTimer then
            specDebounceTimer:Cancel()
            specDebounceTimer = nil
        end
        local cTimer = _G.C_Timer
        if cTimer and cTimer.NewTimer then
            specDebounceTimer = cTimer.NewTimer(0.15, function()
                specDebounceTimer = nil
                sfui.common.ensure_panels_initialized()
                sfui.trackedicons.Update()
                MarkDirty(true)
            end)
        else
            sfui.common.ensure_panels_initialized()
            sfui.trackedicons.Update()
            MarkDirty(true)
        end
    end
    sfui.events.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", on_tracked_icons_spec_changed)
    sfui.events.RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", on_tracked_icons_spec_changed)
    sfui.events.RegisterEvent("TRAIT_CONFIG_UPDATED", on_tracked_icons_spec_changed)
    sfui.events.RegisterEvent("PLAYER_TALENT_UPDATE", on_tracked_icons_spec_changed)
    sfui.events.RegisterEvent("SPEC_INVOLUNTARILY_CHANGED", on_tracked_icons_spec_changed)
    sfui.events.RegisterEvent("SPELLS_CHANGED", function() MarkDirty(true) end)

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

    sfui.events.RegisterEvent("TRAIT_CONFIG_UPDATED", function()
        MarkDirty(not InCombatLockdown())
    end)

    -- 12.0.5+: Blizzard aura data provider switch (e.g. M+ restricted mode transitions)
    sfui.events.RegisterEvent("AURA_DATA_PROVIDER_SWITCH", function(useRealDataProvider)
        for _, panel in pairs(panels) do
            if panel.icons then
                for _, icon in pairs(panel.icons) do
                    if iconAura and iconAura.Reset then
                        iconAura.Reset(icon)
                    end
                    if not useRealDataProvider then
                        if icon.cooldown then icon.cooldown:Clear() end
                        if icon.shadowCooldown then icon.shadowCooldown:Clear() end
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
    local _lastCombatState = nil
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
                if panel.icons and panel.config then
                    for _, icon in pairs(panel.icons) do
                        if icon._glowActive then
                            iconCooldown.UpdateGlow(
                                icon,
                                (icon.entry and icon.entry.settings) or _emptyTable,
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
    if self.Update then self.Update() end
end
sfui.trackedicons.GetDebugInfo = sfui.trackedicons_debug_info
sfui.RegisterModule("trackedicons", sfui.trackedicons)
