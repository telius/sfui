local addonName, addon = ...
sfui.trackedbars = {}

local cfg = sfui.config
local common = sfui.common
local bars = {} -- Active sfui bars
sfui.trackedbars._bars = bars
local container
local issecretvalue = common.issecretvalue
local CreateFrame = CreateFrame
local UIParent = UIParent
local GameTooltip = sfui.common.get_tooltip()
local C_Spell = C_Spell
local InCombatLockdown = InCombatLockdown
local wipe = table.wipe or wipe
local hooksecurefunc = hooksecurefunc
local C_UnitAuras = C_UnitAuras
local C_CooldownViewer = C_CooldownViewer
local C_Timer = C_Timer
local GetTime = GetTime
local C_Secrets = _G.C_Secrets -- 12.0.5+: secrecy predicate API

local unpack = unpack
local math_floor = math.floor

local function GetBuffBarViewer()
    return _G.BuffBarCooldownViewer
end

-- Reusable tables & constants (performance optimization)
local _emptyTable = {}
local standardBars = {}
local attachedBars = {}
local activeCooldownIDs = {}
local _checkedAttached = {}
local _maxStacksCache = {}
local DEFAULT_PANDEMIC_COLOR = { 1, 0, 1, 1 }
local PANDEMIC_GLOW_OPTS = {
    glowType = "pixel",
    glowColor = { 1, 0.85, 0.2, 1 },
    glowThickness = 2,
    glowLines = 6,
    glowSpeed = 0.35,
}

-- Pandemic state is read from Blizzard's own item field: CooldownViewerItemMixin sets
-- `PandemicIcon` in ShowPandemicStateFrame and nils it in HidePandemicStateFrame.
-- Do NOT hooksecurefunc those methods or reparent PandemicIcon (owned by Blizzard's pandemicIconPool).
local function IsBlizzardItemInPandemic(blizzFrame)
    local icon = blizzFrame and blizzFrame.PandemicIcon
    if not icon or not icon.IsShown then return false end
    local shown = icon:IsShown()
    if issecretvalue and issecretvalue(shown) then return false end
    return shown == true
end

-- Helper to get tracking config for a specific ID
local configCache = {}
local _cdViewerInfoCache = {}
-- Pool of wiped config tables recycled from InvalidateConfigCache, avoiding
-- per-spec-change allocations when the same ~N bars are re-resolved.
local configPool = {}
local function GetTrackedBarConfig(cooldownID)
    if not cooldownID then return nil end
    local cached = configCache[cooldownID]
    if cached then return cached end

    -- Reuse a pooled (already-wiped) table if one is available
    local cfg = table.remove(configPool) or {}
    cfg._id = cooldownID

    -- 1. Base Defaults (lowest priority)
    local trackedBarsCfg = sfui.config.trackedBars
    if trackedBarsCfg and trackedBarsCfg.defaults then
        local defaults = trackedBarsCfg.defaults
        local entry = defaults[cooldownID] or defaults[tonumber(cooldownID)]
        if entry then
            local match = true
            if entry.specID then
                local currentSpec = common.get_current_spec_id and common.get_current_spec_id()
                if currentSpec and not (common.is_spec_match and common.is_spec_match(entry.specID, currentSpec) or entry.specID == currentSpec) then
                    match = false
                end
            end
            if match then
                for k, v in pairs(entry) do cfg[k] = v end
            end
        end
    end

    -- 2. User DB Overrides (highest priority)
    local specBars = common.get_tracked_bars()
    if specBars then
        local entry = specBars[cooldownID] or specBars[tonumber(cooldownID)]
        if type(entry) == "table" then
            for k, v in pairs(entry) do cfg[k] = v end
        end
    end

    configCache[cooldownID] = cfg
    return cfg
end
sfui.trackedbars.GetConfig = GetTrackedBarConfig

-- Public: Get all known spells (active or configured) for the settings panel
function sfui.trackedbars.GetKnownSpells()
    local known = {}

    local function GetInfo(id)
        local name, icon
        if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
            local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(id)
            if info then
                if info.spellID then
                    name = common.get_spell_name(info.spellID)
                    icon = common.get_spell_icon(info.spellID)
                elseif info.itemID then
                    name = C_Item.GetItemNameByID(info.itemID)
                    icon = C_Item.GetItemIconByID(info.itemID)
                end
            end
        end
        -- Fallback to direct spell lookup if info failed
        if not name then name = common.get_spell_name(id) end
        if not icon then icon = common.get_spell_icon(id) end

        return name or ("Unknown (" .. id .. ")"), icon or cfg.textures.white
    end

    -- Only add configured bars from DB to ensure synchronization with assignments
    local specBars = common.get_tracked_bars()
    if specBars then
        for id, cfg in pairs(specBars) do
            if type(id) == "number" and not known[id] then
                local n, i = GetInfo(id)
                known[id] = {
                    id = id,
                    name = n,
                    icon = i,
                    active = bars[id] ~= nil
                }
            end
        end
    end

    -- Sort by name
    local sorted = {}
    for _, info in pairs(known) do table.insert(sorted, info) end
    table.sort(sorted, function(a, b) return (a.name or "") < (b.name or "") end)

    return sorted
end

-- Cache invalidation (call when settings change).
-- Wipes and recycles config tables into configPool so the next
-- GetTrackedBarConfig call can reuse them without allocating.
function sfui.trackedbars.InvalidateConfigCache()
    for _, v in pairs(configCache) do
        wipe(v)
        configPool[#configPool + 1] = v
    end
    wipe(configCache)
    wipe(_cdViewerInfoCache)
    wipe(_maxStacksCache)
end

-- Helper to determine max stacks for a bar
-- Checks in order: user config -> special cases -> cached charge info -> default
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
    if spellID and not (issecretvalue and issecretvalue(spellID)) and type(spellID) == "number" and spellID > 0 then
        local cachedMax = _maxStacksCache[spellID]
        if cachedMax then
            return cachedMax
        end
        if C_Spell and C_Spell.GetSpellCharges then
            local chargeInfo = C_Spell.GetSpellCharges(spellID)
            local mc = chargeInfo and chargeInfo.maxCharges
            if mc and not (issecretvalue and issecretvalue(mc)) and type(mc) == "number" and mc > 0 then
                _maxStacksCache[spellID] = mc
                maxStacks = mc
            end
        end
    end

    return maxStacks
end
sfui.trackedbars.GetMaxStacks = GetMaxStacksForBar

-- Helper for Masque Sync
local function SyncBarMasque(bar)
    if not bar._masqueSubElements then
        bar._masqueSubElements = { Icon = bar.icon }
    end
    common.sync_masque(bar.iconFrame, bar._masqueSubElements)
end



local function CreateBar(cooldownID)
    local cfg = sfui.config.trackedBars
    -- Frame is the Backdrop/Container
    local barName = "sfui_bar" .. tostring(cooldownID) .. "_Backdrop"
    local bar = CreateFrame("Frame", barName, container, "BackdropTemplate")
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
    local pad = cfg.backdrop.padding
    bar.status:SetPoint("TOPLEFT", bar, "TOPLEFT", pad, -pad)
    bar.status:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -pad, pad)
    local statusTex = (sfui.widgets and sfui.widgets.get_bar_texture and sfui.widgets.get_bar_texture()) or sfui.config.textures.white
    bar.status:SetStatusBarTexture(statusTex)
    bar.status:SetStatusBarColor(unpack(sfui.config.colors.purple))

    -- Icon
    bar.iconFrame = CreateFrame("Button", nil, bar)
    bar.iconFrame:SetSize(cfg.icon_size, cfg.icon_size)
    bar.iconFrame:SetPoint("RIGHT", bar, "LEFT", cfg.icon_offset, 0)

    bar.icon = bar.iconFrame:CreateTexture(nil, "ARTWORK")
    bar.icon:SetAllPoints()

    common.apply_square_icon_style(bar.iconFrame, bar.icon)

    local msq = common.get_masque_group()
    if msq then
        msq:AddButton(bar.iconFrame, { Icon = bar.icon })
        bar._isMasqued = true
    end

    -- Text (spell names use standard font; numeric timers & stacks use tabular NumberFontNormalSmall)
    local fontsCfg = cfg.fonts or _emptyTable
    local nameFont = fontsCfg.standard or sfui.config.font_small
    local numFont = fontsCfg.number or "NumberFontNormalSmall"
    local nameSize = fontsCfg.nameSize or 10
    local numSize = fontsCfg.standardSize or 11

    bar.name = bar.status:CreateFontString(nil, "OVERLAY")
    bar.name:SetDrawLayer("OVERLAY", 7)
    bar.name:SetWordWrap(false)
    bar.name:SetJustifyH("LEFT")
    bar.name:SetPoint("LEFT", bar.status, "LEFT", cfg.spacing or 5, 0)
    common.style_text(bar.name, nameFont, nameSize, "")

    bar.time = bar.status:CreateFontString(nil, "OVERLAY")
    bar.time:SetDrawLayer("OVERLAY", 7)
    bar.time:SetWordWrap(false)
    bar.time:SetJustifyH("CENTER")
    bar.time:SetPoint("CENTER", bar.status, "CENTER", 0, 0)
    common.style_text(bar.time, numFont, numSize, "")

    -- Stack Count
    bar.count = bar.status:CreateFontString(nil, "OVERLAY")
    bar.count:SetDrawLayer("OVERLAY", 7)
    bar.count:SetWordWrap(false)
    bar.count:SetJustifyH("CENTER")
    bar.count:SetPoint("CENTER", bar.icon, "CENTER", 0, 0)
    common.style_text(bar.count, numFont, numSize, "")

    bar.cooldownID = cooldownID

    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        if self.spellID then
            if C_Spell and C_Spell.PickupSpell then
                C_Spell.PickupSpell(self.spellID)
            else
                PickupSpell(self.spellID)
            end
        elseif self.itemID then
            PickupItem(self.itemID)
        end
    end)
    bar:SetScript("OnEnter", function(self)
        if GameTooltip and self.spellID then
            local secureSpell = self.spellID
            if issecretvalue and issecretvalue(secureSpell) then
                if type(self.cooldownID) == "number" then
                    secureSpell = self.cooldownID
                else
                    return
                end
            end
            if type(secureSpell) == "number" and secureSpell > 0 then
                GameTooltip:SetOwner(self:GetParent(), "ANCHOR_RIGHT")
                GameTooltip:SetSpellByID(secureSpell)
                GameTooltip:Show()
            end
        end
    end)
    bar:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    bar:SetScript("OnHide", function(self)
        if self._inPandemic then
            self._inPandemic = false
            if sfui.glows and sfui.glows.stop_glow then
                sfui.glows.stop_glow(self.iconFrame)
            end
        end
    end)

    return bar
end

-- Helper to resolve a bar's normal (non-pandemic) display color
local function GetBarNormalColor(config)
    if config then
        if config.customColor then
            return config.customColor
        elseif config.useSpecColor then
            return common.get_spec_color_table()
        elseif SfuiDB and SfuiDB.trackedBars and SfuiDB.trackedBars.defaultBarColor then
            return SfuiDB.trackedBars.defaultBarColor
        elseif config.color then
            return config.color
        end
    elseif SfuiDB and SfuiDB.trackedBars and SfuiDB.trackedBars.defaultBarColor then
        return SfuiDB.trackedBars.defaultBarColor
    end
    return sfui.config.colors.purple
end
sfui.trackedbars.GetBarNormalColor = GetBarNormalColor

local function ResolveBarTextFlags(config)
    local db = (SfuiDB and SfuiDB.trackedBars) or _emptyTable
    local isStackMode = (config and config.stackMode) or false
    local isAttached = (config and config.stackAboveHealth) or false
    local showStacksText = (config and config.showStacksText) or false
    local showDurationEnabled = not (db.showDuration == false or (config and config.showDuration == false))
    local showNameCfg = (config and config.showName ~= nil) and config.showName or db.showName
    local showNameEnabled = (showNameCfg ~= false)
    local showStacks = (config and config.showStacks ~= nil) and config.showStacks or (db.showStacks == true)
    local wantCenteredStacks = isStackMode or showStacksText
    local isTimerAndStacks = wantCenteredStacks and showDurationEnabled
    return isStackMode, isAttached, showStacksText, showDurationEnabled, showNameEnabled, showStacks, wantCenteredStacks, isTimerAndStacks
end
sfui.trackedbars.ResolveTextFlags = ResolveBarTextFlags

-- Helper function to setup bar content (text, icons, stack mode logic)
local function SetupBarState(bar, config, cfg)
    local isStackMode, isAttached, showStacksText, showDurationEnabled, showNameEnabled, showStacks, wantCenteredStacks, isTimerAndStacks = ResolveBarTextFlags(config)

    local fontsCfg = (cfg and cfg.fonts) or _emptyTable
    local nameFont = fontsCfg.standard or sfui.config.font_small
    local numFont = fontsCfg.number or "NumberFontNormalSmall"
    local nameSize = fontsCfg.nameSize or 10
    local numSize = fontsCfg.standardSize or 11
    local largeNumSize = fontsCfg.stackModeDurationSize or 14
    local padX = (cfg and cfg.spacing) or 5

    -- Invalidate cached display strings so fresh layout/mode re-applies text immediately
    bar._lastDurationText = nil
    bar._lastStackNameText = nil
    bar._lastStackTimeText = nil
    bar._lastAuraName = nil

    bar.count:ClearAllPoints()
    bar.count:SetPoint("CENTER", bar.icon, "CENTER", 0, 0)
    bar.count:SetJustifyH("CENTER")
    common.style_text(bar.count, numFont, numSize, "")

    if isAttached then
        bar.icon:Hide()
        bar.count:Hide()
    else
        bar.icon:Show()
        if not showStacks or isStackMode or showStacksText then
            bar.count:Hide()
        end
    end

    -- Text Position, Justification & Explicit Tabular/Standard Font Sizing
    if isTimerAndStacks then
        -- Centered stacks via bar.name (tabular digits), timer on side via bar.time (tabular digits)
        bar.name:ClearAllPoints()
        bar.name:SetPoint("CENTER", bar.status, "CENTER", 0, 0)
        bar.name:SetJustifyH("CENTER")
        common.style_text(bar.name, numFont, largeNumSize, "")
        bar.name:Show()

        bar.time:ClearAllPoints()
        if isAttached then
            bar.time:SetPoint("RIGHT", bar.status, "RIGHT", -padX, 0)
            bar.time:SetJustifyH("RIGHT")
        else
            bar.time:SetPoint("LEFT", bar.status, "LEFT", padX, 0)
            bar.time:SetJustifyH("LEFT")
        end
        common.style_text(bar.time, numFont, numSize, "")
        bar.time:Show()
    elseif wantCenteredStacks then
        -- Duration disabled: spell name on LEFT via bar.name, centered stacks via bar.time
        bar.name:ClearAllPoints()
        bar.name:SetPoint("LEFT", bar.status, "LEFT", padX, 0)
        bar.name:SetJustifyH("LEFT")
        common.style_text(bar.name, nameFont, nameSize, "")
        if showNameEnabled then bar.name:Show() else bar.name:Hide() end

        bar.time:ClearAllPoints()
        bar.time:SetPoint("CENTER", bar.status, "CENTER", 0, 0)
        bar.time:SetJustifyH("CENTER")
        common.style_text(bar.time, numFont, largeNumSize, "")
        if showStacksText then bar.time:Show() else bar.time:Hide() end
    else
        -- Standard duration bar: Time CENTER (if attached) or RIGHT (if standard), Name LEFT
        bar.time:ClearAllPoints()
        if isAttached then
            bar.time:SetPoint("CENTER", bar.status, "CENTER", 0, 0)
            bar.time:SetJustifyH("CENTER")
            common.style_text(bar.time, numFont, largeNumSize, "")
        else
            bar.time:SetPoint("RIGHT", bar.status, "RIGHT", -padX, 0)
            bar.time:SetJustifyH("RIGHT")
            common.style_text(bar.time, numFont, numSize, "")
        end
        if showDurationEnabled then bar.time:Show() else bar.time:Hide() end

        bar.name:ClearAllPoints()
        bar.name:SetPoint("LEFT", bar.status, "LEFT", padX, 0)
        if not isAttached and showDurationEnabled then
            bar.name:SetPoint("RIGHT", bar.time, "LEFT", -4, 0)
        end
        bar.name:SetJustifyH("LEFT")
        common.style_text(bar.name, nameFont, nameSize, "")
        if showNameEnabled then bar.name:Show() else bar.name:Hide() end
    end

    -- Color Logic
    local color = GetBarNormalColor(config)
    bar.status:SetStatusBarColor(common.unpack_color(color))

    -- If the bar is currently in the pandemic window, restore the pandemic color.
    local tBarsCfg = (sfui.config and sfui.config.trackedBars) or _emptyTable
    local shouldRecolor = (config and config.pandemicEnabled ~= nil) and config.pandemicEnabled or (tBarsCfg.pandemicRecolor ~= false)
    if shouldRecolor and bar._inPandemic then
        local pColor = (config and config.pandemicColor) or tBarsCfg.pandemicColor or DEFAULT_PANDEMIC_COLOR
        bar.status:SetStatusBarColor(common.unpack_color(pColor))
    end
end

-- Helper for Standard Bar Positioning
local function ApplyBarStyling(bar, yOffset, config, cfg, globalDB)
    local width = math_floor((globalDB.width or cfg.width) + 0.5)
    local height = math_floor((globalDB.height or cfg.height) + 0.5)
    local spacing = globalDB.spacing or cfg.spacing or 5

    bar:SetSize(width, height)
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOM", container, "BOTTOM", 0, yOffset)
    local pad = cfg.backdrop.padding
    bar.status:ClearAllPoints()
    bar.status:SetPoint("TOPLEFT", pad, -pad)
    bar.status:SetPoint("BOTTOMRIGHT", -pad, pad)
    bar:SetBackdropColor(unpack(cfg.backdrop.color))
    return yOffset + (height + spacing)
end


-- Normal Sort (Normal Index > Name)
local function NormalSort(a, b)
    local cA = GetTrackedBarConfig(a.cooldownID)
    local cB = GetTrackedBarConfig(b.cooldownID)

    -- Default to 100 or legacy priority if unassigned, so they sit below manually bumped bars.
    local nA = (cA and cA.normalIndex) or (cA and cA.priority) or 100
    local nB = (cB and cB.normalIndex) or (cB and cB.priority) or 100

    if nA ~= nB then return nA < nB end

    local nA_name = common.get_spell_name(a.cooldownID) or ""
    local nB_name = common.get_spell_name(b.cooldownID) or ""
    return nA_name < nB_name
end

-- Attached Sort (Attached Index > Name)
local function AttachedSort(a, b)
    local cA = GetTrackedBarConfig(a.cooldownID)
    local cB = GetTrackedBarConfig(b.cooldownID)

    local aA = (cA and cA.attachedIndex) or (cA and cA.priority) or 100
    local aB = (cB and cB.attachedIndex) or (cB and cB.priority) or 100

    if aA ~= aB then return aA < aB end

    local nA_name = common.get_spell_name(a.cooldownID) or ""
    local nB_name = common.get_spell_name(b.cooldownID) or ""
    return nA_name < nB_name
end

local _numShownBars = 0

local function UpdateLayout()
    local cfg = sfui.config.trackedBars
    local globalDB = SfuiDB and SfuiDB.trackedBars or {}
    wipe(standardBars)
    wipe(attachedBars)

    for _, bar in pairs(bars) do
        if bar:IsShown() then
            local config = GetTrackedBarConfig(bar.cooldownID)
            SetupBarState(bar, config, cfg)
            SyncBarMasque(bar)

            if config and config.stackAboveHealth then
                table.insert(attachedBars, bar)
            else
                table.insert(standardBars, bar)
            end
        end
    end

    _numShownBars = #standardBars + #attachedBars

    -- Update container/child icon sizes if changed globally
    local iconSize = globalDB.iconSize or cfg.icon_size or 20

    -- 1. Standard Layout
    table.sort(standardBars, NormalSort)
    local yOffset = 0
    for _, bar in ipairs(standardBars) do
        local config = GetTrackedBarConfig(bar.cooldownID)
        if bar:GetParent() ~= container then bar:SetParent(container) end
        bar.iconFrame:Show()
        bar.iconFrame:SetSize(iconSize, iconSize) -- Apply global icon size override
        if bar.iconFrame.borderBackdrop then bar.iconFrame.borderBackdrop:Hide() end
        yOffset = ApplyBarStyling(bar, yOffset, config, cfg, globalDB)
    end

    -- 2. Attached Layout
    if #attachedBars > 0 then
        table.sort(attachedBars, AttachedSort)

        local spacing = sfui.config.barLayout.spacing or 1
        local anchor = _G["sfui_bar0_Backdrop"]

        if _G["SfuiSoulFragmentsBar"] and _G["SfuiSoulFragmentsBar"]:IsShown() then
            anchor = _G["SfuiSoulFragmentsBar"]
        elseif _G["sfui_bar1_Backdrop"] and _G["sfui_bar1_Backdrop"]:IsShown() then
            anchor = _G["sfui_bar1_Backdrop"]
        elseif _G["sfui_runeBar"] and _G["sfui_runeBar"]:IsShown() then
            anchor = _G["sfui_runeBar"]
        elseif not sfui.isRetail and sfui.threat and sfui.threat.IsShown and sfui.threat.IsShown() and sfui.threat.GetAnchorFrame and sfui.threat.GetAnchorFrame() then
            anchor = sfui.threat.GetAnchorFrame()
        elseif _G["SfuiThreatBar_Backdrop"] and _G["SfuiThreatBar_Backdrop"]:IsShown() then
            anchor = _G["SfuiThreatBar_Backdrop"]
        end

        if anchor and anchor:IsShown() then
            for _, bar in ipairs(attachedBars) do
                if bar:GetParent() ~= UIParent then bar:SetParent(UIParent) end
                bar:ClearAllPoints()

                local width = math_floor((sfui.config.healthBar.width * (cfg.attachedWidthMultiplier or 0.8)) + 0.5)
                local height = math_floor((cfg.attachedHeight or 20) + 0.5)

                bar:SetSize(width, height)
                bar:SetPoint("BOTTOM", anchor, "TOP", 0, spacing)

                -- Style Fix
                local pad = cfg.backdrop.padding
                bar.status:ClearAllPoints()
                bar.status:SetPoint("TOPLEFT", pad, -pad)
                bar.status:SetPoint("BOTTOMRIGHT", -pad, pad)
                bar:SetBackdropColor(unpack(cfg.backdrop.color))

                -- Hide Icon for Attached Bars
                bar.iconFrame:Hide()
                if bar.iconFrame.borderBackdrop then bar.iconFrame.borderBackdrop:Hide() end

                anchor = bar
            end
        else
            for _, bar in ipairs(attachedBars) do
                bar:Hide()
            end
        end
    end

    if sfui.trackedbars.UpdateTopAnchor then
        sfui.trackedbars.UpdateTopAnchor()
    end
end

-- Top Anchor Management (Static anchor positioned at the highest tracked bar slot)
local topAnchor

local function GetBaseAttachedAnchor()
    local anchor = _G["sfui_bar0_Backdrop"]
    if _G["SfuiSoulFragmentsBar"] and (_G["SfuiSoulFragmentsBar"]:IsShown() or (SfuiDB and SfuiDB.enableSoulFragments ~= false)) then
        anchor = _G["SfuiSoulFragmentsBar"]
    elseif _G["sfui_bar1_Backdrop"] and (_G["sfui_bar1_Backdrop"]:IsShown() or (common.get_secondary_resource and common.get_secondary_resource() and (SfuiDB == nil or SfuiDB.enableSecondaryPowerBar ~= false))) then
        anchor = _G["sfui_bar1_Backdrop"]
    elseif _G["sfui_runeBar"] and (_G["sfui_runeBar"]:IsShown() or (SfuiDB and SfuiDB.enableRuneBar ~= false)) then
        anchor = _G["sfui_runeBar"]
    elseif not sfui.isRetail and sfui.threat and sfui.threat.IsShown and sfui.threat.IsShown() and sfui.threat.GetAnchorFrame and sfui.threat.GetAnchorFrame() then
        anchor = sfui.threat.GetAnchorFrame()
    elseif _G["SfuiThreatBar_Backdrop"] and _G["SfuiThreatBar_Backdrop"]:IsShown() then
        anchor = _G["SfuiThreatBar_Backdrop"]
    end
    return anchor or _G["sfui_bar0_Backdrop"]
end
sfui.trackedbars.GetBaseAttachedAnchor = GetBaseAttachedAnchor

local function GetNumConfiguredAttachedBars()
    local count = 0
    local specBars = common.get_tracked_bars and common.get_tracked_bars()
    wipe(_checkedAttached)
    if specBars then
        for id, _ in pairs(specBars) do
            if type(id) == "number" then
                _checkedAttached[id] = true
                local bCfg = GetTrackedBarConfig(id)
                if bCfg and bCfg.stackAboveHealth then
                    count = count + 1
                end
            end
        end
    end
    local tCfg = sfui.config.trackedBars
    if tCfg and tCfg.defaults then
        local currentSpec = common.get_current_spec_id and common.get_current_spec_id()
        for id, def in pairs(tCfg.defaults) do
            if not _checkedAttached[id] and (not def.specID or def.specID == currentSpec) then
                if def.stackAboveHealth then
                    count = count + 1
                end
            end
        end
    end
    return count
end
sfui.trackedbars.GetNumConfiguredAttachedBars = GetNumConfiguredAttachedBars

local function UpdateTopAnchor()
    if not topAnchor then
        topAnchor = CreateFrame("Frame", "SfuiTrackedBarsTopAnchor", UIParent)
        topAnchor:SetSize(1, 1)
    end

    local base = GetBaseAttachedAnchor()
    if not base then
        base = _G["sfui_bar0_Backdrop"]
    end
    if not base then return topAnchor end

    local tBarsCfg = sfui.config.trackedBars or {}
    local spacing = sfui.config.barLayout and sfui.config.barLayout.spacing or 1
    local height = tBarsCfg.attachedHeight or 20
    local numConfigured = GetNumConfiguredAttachedBars()
    local numActive = attachedBars and #attachedBars or 0
    local numBars = math.max(numConfigured, numActive)

    local totalOffset = 0
    if numBars > 0 then
        totalOffset = numBars * (height + spacing)
    end

    topAnchor:ClearAllPoints()
    topAnchor:SetPoint("TOP", base, "TOP", 0, totalOffset)
    topAnchor:Show()

    if sfui.trackedbuffs and sfui.trackedbuffs.UpdatePosition then
        sfui.trackedbuffs.UpdatePosition()
    end

    return topAnchor
end
sfui.trackedbars.UpdateTopAnchor = UpdateTopAnchor

function sfui.trackedbars.GetTopAnchor()
    if not topAnchor then UpdateTopAnchor() end
    return topAnchor
end

-- Update Position External Reference
function sfui.trackedbars.UpdatePosition()
    if not container then return end
    local db = SfuiDB and SfuiDB.trackedBars
    local defX = (cfg.trackedBars and cfg.trackedBars.anchor and cfg.trackedBars.anchor.x) or (SfuiDB and SfuiDB.trackedBarsX) or -300
    local defY = (cfg.trackedBars and cfg.trackedBars.anchor and cfg.trackedBars.anchor.y) or (SfuiDB and SfuiDB.trackedBarsY) or 300

    local point = (db and db.anchor and db.anchor.point) or "BOTTOM"
    local relPoint = (db and db.anchor and db.anchor.relPoint) or point
    local x = db and db.anchor and db.anchor.x
    local y = db and db.anchor and db.anchor.y

    -- Heal corrupted 0, 0 position from legacy options bug
    if (x == 0 and y == 0) or (x == nil and y == nil) then
        x = defX
        y = defY
        if db and db.anchor then
            db.anchor.point = point
            db.anchor.relPoint = relPoint
            db.anchor.x = x
            db.anchor.y = y
        end
    end

    x = x or defX
    y = y or defY

    container:ClearAllPoints()
    container:SetPoint(point, UIParent, relPoint, x, y)
end

function sfui.trackedbars.SetColor(cooldownID, r, g, b)
    local barDB = common.ensure_tracked_bar_db(cooldownID)
    barDB.color = { r = r, g = g, b = b }
    UpdateLayout() -- Refresh to apply color
end

local barPool = {}

function sfui.trackedbars.SetBarTexture(texturePath)
    if not texturePath or texturePath == "" then
        texturePath = sfui.widgets and sfui.widgets.get_bar_texture and sfui.widgets.get_bar_texture()
    end
    if not texturePath then return end
    if bars then
        for _, bar in pairs(bars) do
            if bar.status then
                bar.status:SetStatusBarTexture(texturePath)
            end
        end
    end
    for _, bar in ipairs(barPool) do
        if bar.status then
            bar.status:SetStatusBarTexture(texturePath)
        end
    end
end
sfui.trackedbars.UpdateAppearance = function() sfui.trackedbars.SetBarTexture() end

-- ─── self-driven bars (cdm items blizzard won't give a buff bar frame) ───────
-- cover-spell items such as forever's paladin "seals" (cooldown id 200340, linked to
-- every seal) live in the essential/utility categories, so BuffBarCooldownViewer never
-- creates a frame to mirror. these bars are driven by the shared aura resolver instead:
-- the aura's duration object feeds StatusBar:SetTimerDuration and a DurationTextBinding,
-- so the bar and timer text animate natively and secret values are never inspected.
local auraResolver = sfui.isCamelot and sfui.tracking and sfui.tracking.auras or nil
local _selfDrivenBarCount = 0
local _selfDrivenWatchlist = {}
local _durationFormatter
local _zeroDuration

function sfui.trackedbars.HasSelfDrivenBars()
    return _selfDrivenBarCount > 0
end

local function GetZeroDuration()
    if _zeroDuration == nil then
        _zeroDuration = (C_DurationUtil and C_DurationUtil.CreateDuration and C_DurationUtil.CreateDuration()) or false
    end
    return _zeroDuration or nil
end

local function GetDurationFormatter()
    if _durationFormatter == nil then
        local f = C_StringUtil and C_StringUtil.CreateSecondsFormatter and C_StringUtil.CreateSecondsFormatter()
        if f then
            local E = Enum
            if f.SetDefaultAbbreviation and E and E.SecondsFormatterAbbreviation then
                f:SetDefaultAbbreviation(E.SecondsFormatterAbbreviation.OneLetter)
            end
            if f.SetRounding and E and E.SecondsFormatterRounding then
                f:SetRounding(E.SecondsFormatterRounding.Truncate)
            end
            if f.SetCanRoundUpLastUnit then f:SetCanRoundUpLastUnit(true) end
            if f.SetMinInterval and E and E.SecondsFormatterInterval then
                f:SetMinInterval(E.SecondsFormatterInterval.Seconds)
            end
            if f.SetDesiredUnitCount then f:SetDesiredUnitCount(1) end
        end
        _durationFormatter = f or false
    end
    return _durationFormatter or nil
end

local function GetBarTextBinding(bar)
    if bar._durationBinding == nil then
        local b = C_DurationUtil and C_DurationUtil.CreateDurationTextBinding and C_DurationUtil.CreateDurationTextBinding()
        if b then
            if b.SetToDefaults then b:SetToDefaults() end
            local fmt = GetDurationFormatter()
            if fmt then b:SetFormatter(fmt) end
            b:SetFontString(bar.time)
            if b.SetZeroDurationText then b:SetZeroDurationText("") end
            if b.SetExpiredText then b:SetExpiredText("") end
        end
        bar._durationBinding = b or false
    end
    return bar._durationBinding or nil
end

-- stops native bar-fill timer driving so manual SetValue calls take over again
local function StopBarTimer(bar)
    if bar._timerDriven then
        bar._timerDriven = nil
        local zero = GetZeroDuration()
        if zero and bar.status.SetTimerDuration then
            bar.status:SetTimerDuration(zero)
        end
    end
end

-- stops native timer/text driving so manual SetValue / SetText calls take over again
local function StopSelfDrivenTimer(bar)
    local b = bar._durationBinding
    if b and bar._bindingEnabled then
        b:SetEnabled(false)
        bar._bindingEnabled = nil
        bar.time:SetText("")
    end
    StopBarTimer(bar)
end

local function ResetSelfDrivenBar(bar)
    StopSelfDrivenTimer(bar)
    bar._selfDriven = nil
    bar._auraActive = nil
    bar._auraRev = nil
    bar._auraExpTime = nil
    bar._auraDurationObj = nil
    bar._auraName = nil
    bar._auraIcon = nil
    bar._auraStacks = nil
    bar._auraCandidates = nil
    bar._auraCandActive = nil
    bar._auraCandLinked = nil
end

local function SyncSelfDrivenBar(myBar, config, isStackMode, id, info)
    myBar._selfDriven = true
    myBar._config = config

    local spellID = info and (info.overrideSpellID or info.spellID)
    if spellID and issecretvalue(spellID) then spellID = nil end
    myBar.spellID = spellID or id

    local candidates, rebuilt = auraResolver.GetCandidates(myBar, spellID, info and info.linkedSpellIDs, info)
    local rev = auraResolver.GetRevision and auraResolver.GetRevision() or 0
    local expiredFallback = myBar._auraActive and myBar._auraExpTime and myBar._auraExpTime > 0 and GetTime() >= myBar._auraExpTime

    if rebuilt or myBar._auraRev ~= rev or expiredFallback or myBar._auraActive == nil then
        myBar._auraRev = rev
        local iid, aura, present = auraResolver.Resolve(id, candidates)
        if aura or iid then
            local dObj = auraResolver.GetDuration(iid, aura)
            if dObj then
                myBar._auraDurationObj = dObj
            end
            local exp = auraResolver.PlainField(aura, "expirationTime")
            myBar._auraExpTime = (exp and exp > 0) and exp or nil
            myBar._auraName = auraResolver.PlainField(aura, "name") or myBar._auraName
            myBar._auraIcon = auraResolver.PlainField(aura, "icon") or myBar._auraIcon
            myBar._auraStacks = auraResolver.PlainField(aura, "applications") or myBar._auraStacks
            myBar._auraActive = true
        elseif present and not rebuilt and myBar._auraActive then
            -- aura up but restricted: keep the last duration object ticking
        else
            myBar._auraDurationObj = nil
            myBar._auraExpTime = nil
            myBar._auraName = nil
            myBar._auraIcon = nil
            myBar._auraStacks = nil
            myBar._auraActive = false
        end
    end
    local active = myBar._auraActive

    -- icon & name: show the active aura (e.g. the current seal), else the cdm item itself
    local tex = myBar._auraIcon or (spellID and C_Spell.GetSpellTexture(spellID)) or 134400
    myBar.icon:SetTexture(tex)
    myBar.icon:SetDesaturated(not active)

    local _, isAttached, showStacksText, showDur, showNameEnabled, showStacks, wantCenteredStacks, isTimerAndStacks = ResolveBarTextFlags(config)

    local stacks = tonumber(myBar._auraStacks) or 0
    if active and stacks < 1 then stacks = 1 end
    if not active then stacks = 0 end
    myBar.currentStacks = stacks

    if isTimerAndStacks then
        myBar.name:SetText(stacks > 0 and tostring(stacks) or "")
        myBar.name:Show()
    else
        local displayName = (config and config.name) or myBar._auraName or (spellID and C_Spell.GetSpellName(spellID)) or ""
        common.SafeSetText(myBar.name, displayName)
        if showNameEnabled then myBar.name:Show() else myBar.name:Hide() end
    end

    if showStacks and not isStackMode and not isAttached and not showStacksText and stacks > 1 then
        myBar.count:SetText(tostring(stacks))
        myBar.count:Show()
    else
        myBar.count:Hide()
    end

    local dObj = myBar._auraDurationObj
    local timed = false
    if active and dObj then
        if dObj.HasSecretValues and dObj:HasSecretValues() then
            timed = true
        else
            timed = not dObj:IsZero()
        end
    end

    if isStackMode then
        StopBarTimer(myBar)
        local maxVal = GetMaxStacksForBar(id, config, spellID)
        maxVal = (type(maxVal) == "number" and maxVal > 0) and maxVal or 5
        myBar.status:SetMinMaxValues(0, maxVal)
        myBar.status:SetValue(math.min(stacks, maxVal))
    elseif timed and myBar.status.SetTimerDuration then
        local interp = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0
        local dir = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime or 1
        myBar.status:SetTimerDuration(dObj, interp, dir)
        myBar._timerDriven = true
    else
        StopBarTimer(myBar)
        myBar.status:SetMinMaxValues(0, 1)
        myBar.status:SetValue(active and 1 or 0) -- permanent aura: full bar
    end

    -- timer / centered-stack text
    local binding = GetBarTextBinding(myBar)
    if showStacksText and not isTimerAndStacks then
        if binding and myBar._bindingEnabled then
            binding:SetEnabled(false)
            myBar._bindingEnabled = nil
        end
        myBar.time:SetText(stacks > 0 and tostring(stacks) or "")
        myBar.time:Show()
    elseif timed and showDur and binding then
        binding:SetDuration(dObj)
        if not myBar._bindingEnabled then
            binding:SetEnabled(true)
            myBar._bindingEnabled = true
        end
        myBar.time:Show()
    else
        if binding and myBar._bindingEnabled then
            binding:SetEnabled(false)
            myBar._bindingEnabled = nil
        end
        myBar.time:SetText("")
        if not showDur and not wantCenteredStacks then
            myBar.time:Hide()
        end
    end
end

local function RecycleBar(bar)
    ResetSelfDrivenBar(bar)
    bar:Hide()
    bar:ClearAllPoints()
    bar:SetParent(UIParent)
    bar.cooldownID = nil
    bar.spellID = nil
    bar._config = nil
    bar.currentStacks = nil
    bar._missingTime = nil
    bar._lastDurationText = nil
    bar._lastStackNameText = nil
    bar._lastStackTimeText = nil
    bar._lastAuraName = nil
    bar._lastCount = nil
    bar._appliedMaxVal = nil
    bar._maxStacks = nil
    if bar._inPandemic then
        bar._inPandemic = false
        if sfui.glows and sfui.glows.stop_glow then
            sfui.glows.stop_glow(bar.iconFrame)
        end
    end
    bar._inPandemic = false
    bar._auraStackCache = nil
    bar._auraStackTimer = nil
    bar._stackPeakVal = nil
    bar._stackPeakTimer = nil
    table.insert(barPool, bar)
end

local function GetBarFromPool(cooldownID)
    local bar = table.remove(barPool)
    if bar then
        bar:SetParent(container)
        bar.cooldownID = cooldownID
        local tex = (sfui.widgets and sfui.widgets.get_bar_texture and sfui.widgets.get_bar_texture()) or sfui.config.textures.white
        if bar.status and tex then
            bar.status:SetStatusBarTexture(tex)
        end
        return bar
    end
    return nil
end

function sfui.trackedbars.AcquireBar(cooldownID)
    return GetBarFromPool(cooldownID) or CreateBar(cooldownID)
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

-- Helper: Determine if bar should be visible based on settings.
-- EUI pattern: IsActive() = plain Lua bool from self.isActive, never secret.
-- In M+, Blizzard's IsExpired() crashes on expirationTime<=GetTime() which flips
-- isActive to false. EUI's fix: if IsActive() is false, fall back to
-- GetPlayerAuraBySpellID to confirm the aura is genuinely still present.
local function ShouldBarBeVisible(config, blizzFrame, isStackModeWithStacks, hideInactive, spellID)
    if isStackModeWithStacks then
        return true
    elseif hideInactive then
        -- IsActive() reads self.isActive: plain Lua bool, never secret.
        if blizzFrame.IsActive and blizzFrame:IsActive() then
            return true
        end
        -- Fallback: Blizzard's isActive may have been flipped to false by the
        -- IsExpired() secret crash in M+. Confirm via GetPlayerAuraBySpellID
        -- (works for player's own spells even in restricted combat).
        if spellID and not (issecretvalue and issecretvalue(spellID)) and type(spellID) == "number" and spellID > 0 and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
            local fbAura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
            if fbAura then return true end
        end
        return false
    else
        return true
    end
end

-- Helper: Perform protected blizzard frame scraping
local function _get_blizz_duration_text(blizzFrame)
    if blizzFrame.Bar and blizzFrame.Bar.Duration then
        return blizzFrame.Bar.Duration:GetText()
    end
    return nil
end

local function _apply_stack_text_to_fs(fs, myBar, cacheKey, currentStacks, hideZero)
    if currentStacks == nil then
        if myBar[cacheKey] ~= "" then
            myBar[cacheKey] = ""
            fs:SetText("")
        end
        return
    end
    if issecretvalue and issecretvalue(currentStacks) then
        myBar[cacheKey] = nil
        fs:SetText(currentStacks)
    else
        local n = tonumber(currentStacks)
        local str = (hideZero and n and n <= 0) and "" or tostring(currentStacks)
        if myBar[cacheKey] ~= str then
            myBar[cacheKey] = str
            fs:SetText(str)
        end
    end
end

local function _apply_duration_text_to_bar(myBar, blizzFrame)
    local durText = _get_blizz_duration_text(blizzFrame)
    if issecretvalue and issecretvalue(durText) then
        myBar._lastDurationText = nil
        myBar.time:SetText(durText)
    else
        durText = durText or ""
        if durText ~= myBar._lastDurationText then
            myBar._lastDurationText = durText
            myBar.time:SetText(durText)
        end
    end
end

-- Helper: Sync bar data from Blizzard frame
local function SyncBarData(myBar, blizzFrame, config, isStackMode, id, info)
    local cfg = sfui.config.trackedBars
    myBar._config = config

    local _, isAttached, showStacksText, showDurationEnabled, showNameEnabled, showStacks, wantCenteredStacks, isTimerAndStacks = ResolveBarTextFlags(config)
    local needStacks = isStackMode or showStacksText or (showStacks and not isAttached)

    if config and config.spellID then
        myBar.spellID = config.spellID
    elseif cfg and cfg.specialCases and cfg.specialCases[id] and cfg.specialCases[id].spellID then
        myBar.spellID = cfg.specialCases[id].spellID
    elseif info and info.spellID and not (issecretvalue and issecretvalue(info.spellID)) and type(info.spellID) == "number" and info.spellID > 0 then
        myBar.spellID = info.spellID
    elseif C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local cdInfo = _cdViewerInfoCache[id] or C_CooldownViewer.GetCooldownViewerCooldownInfo(id)
        if cdInfo then
            _cdViewerInfoCache[id] = cdInfo
            if cdInfo.spellID and not (issecretvalue and issecretvalue(cdInfo.spellID)) and type(cdInfo.spellID) == "number" and cdInfo.spellID > 0 then
                myBar.spellID = cdInfo.spellID
            end
        end
    end

    if not myBar.spellID and blizzFrame.GetSpellID then
        local bSpell = blizzFrame:GetSpellID()
        if bSpell and not (issecretvalue and issecretvalue(bSpell)) and type(bSpell) == "number" and bSpell > 0 then
            myBar.spellID = bSpell
        end
    end
    if not myBar.spellID and blizzFrame.auraSpellID and not (issecretvalue and issecretvalue(blizzFrame.auraSpellID)) and type(blizzFrame.auraSpellID) == "number" and blizzFrame.auraSpellID > 0 then
        myBar.spellID = blizzFrame.auraSpellID
    end
    if not myBar.spellID and (blizzFrame.spellID or (blizzFrame.info and blizzFrame.info.spellID)) then
        local candidate = blizzFrame.spellID or (blizzFrame.info and blizzFrame.info.spellID)
        if candidate and not (issecretvalue and issecretvalue(candidate)) and type(candidate) == "number" and candidate > 0 then
            myBar.spellID = candidate
        end
    end

    -- Mirror Icon and Desaturation
    if blizzFrame.Icon and blizzFrame.Icon.Icon then
        myBar.icon:SetTexture(blizzFrame.Icon.Icon:GetTexture())
        if blizzFrame.Icon.Icon.GetDesaturated and blizzFrame.Icon.Icon:GetDesaturated() then
            myBar.icon:SetDesaturated(true)
        else
            myBar.icon:SetDesaturated(false)
        end
    end

    -- Resolve Aura Name & Stack Data
    local resolvedAuraName = nil
    local currentStacks = nil
    local maxStacks = isStackMode and GetMaxStacksForBar(id, config, myBar.spellID) or (myBar._maxStacks or cfg.defaultMaxStacks)
    myBar._maxStacks = maxStacks

    if needStacks then
        -- Primary: Direct Unrestricted Player Aura query (clean number when accessible)
        if myBar.spellID and not (issecretvalue and issecretvalue(myBar.spellID)) and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
            local auraData = C_UnitAuras.GetPlayerAuraBySpellID(myBar.spellID)
            if auraData then
                if auraData.applications ~= nil then
                    currentStacks = auraData.applications
                end
                if auraData.name and not (issecretvalue and issecretvalue(auraData.name)) then
                    resolvedAuraName = auraData.name
                end
            end
        end

        -- Secondary: Read cached aura data directly off the Blizzard frame
        if currentStacks == nil then
            local ad = blizzFrame.auraDataCached
            if ad then
                if ad.applications ~= nil then
                    currentStacks = ad.applications
                end
                if not resolvedAuraName and ad.name and not (issecretvalue and issecretvalue(ad.name)) then
                    resolvedAuraName = ad.name
                end
            end
        end

        -- Fallback 2: Try Aura Data via Instance ID
        if currentStacks == nil and common.HasAuraInstanceID(blizzFrame.auraInstanceID)
            and not (issecretvalue and issecretvalue(blizzFrame.auraInstanceID))
            and not (C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret())
            and (not auraResolver or not auraResolver.CanAccessUnitAuras or auraResolver.CanAccessUnitAuras())
            and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
            local unit = blizzFrame.auraDataUnit or "player"
            local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, blizzFrame.auraInstanceID)
            if auraData then
                if auraData.applications ~= nil then
                    currentStacks = auraData.applications
                end
                if not resolvedAuraName and auraData.name and not (issecretvalue and issecretvalue(auraData.name)) then
                    resolvedAuraName = auraData.name
                end
            end
        end

        -- EUI Floor rule: If active but applications reads nil/0 (1-stack buff where count is omitted), floor clean numbers at 1
        if currentStacks ~= nil then
            if not (issecretvalue and issecretvalue(currentStacks)) then
                local n = tonumber(currentStacks)
                if n and n < 1 and blizzFrame.IsActive and blizzFrame:IsActive() then
                    currentStacks = 1
                end
            end
        elseif blizzFrame.IsActive and blizzFrame:IsActive() then
            currentStacks = 1
        end

        -- Fallback 3: Try Spell Display Count (native action bar representation)
        if currentStacks == nil and myBar.spellID and not (issecretvalue and issecretvalue(myBar.spellID)) and C_Spell and C_Spell.GetSpellDisplayCount then
            local dc = C_Spell.GetSpellDisplayCount(myBar.spellID)
            if dc ~= nil then
                if issecretvalue and issecretvalue(dc) then
                    currentStacks = dc
                else
                    local num = tonumber(dc)
                    if num and num > 0 then
                        currentStacks = num
                    elseif type(dc) == "string" and dc ~= "" and dc ~= "0" then
                        currentStacks = dc
                    end
                end
            end
        end

        -- Fallback 4: Try Spell Charges (for charge-based spells missing auraInstanceID)
        if currentStacks == nil and myBar.spellID and not (issecretvalue and issecretvalue(myBar.spellID)) and C_Spell and C_Spell.GetSpellCharges then
            local chargeInfo = C_Spell.GetSpellCharges(myBar.spellID)
            if chargeInfo and chargeInfo.currentCharges ~= nil and chargeInfo.maxCharges
                and not (issecretvalue and issecretvalue(chargeInfo.maxCharges))
                and chargeInfo.maxCharges > 1 then
                local cc = chargeInfo.currentCharges
                if (issecretvalue and issecretvalue(cc)) or type(cc) == "number" then
                    currentStacks = cc
                end
            end
        end

        -- Debounce: prevent 1-frame combat flicker during aura refresh
        if currentStacks ~= nil then
            myBar._auraStackCache = currentStacks
            myBar._auraStackTimer = GetTime()
        elseif myBar._auraStackCache ~= nil and myBar._auraStackTimer then
            if GetTime() - myBar._auraStackTimer < 0.05 then
                currentStacks = myBar._auraStackCache
            else
                myBar._auraStackCache = nil
            end
        end
    elseif not isTimerAndStacks and showNameEnabled and not (config and config.name) then
        local ad = blizzFrame.auraDataCached
        if ad and ad.name and not (issecretvalue and issecretvalue(ad.name)) then
            resolvedAuraName = ad.name
        end
    end

    -- Handle text visibility toggles (Global and Per-Bar options)
    if isTimerAndStacks then
        myBar.name:Show()
        myBar.time:Show()
    else
        if showNameEnabled then
            myBar.name:Show()
        else
            myBar.name:Hide()
        end

        if not showDurationEnabled and not wantCenteredStacks then
            myBar.time:Hide()
        else
            myBar.time:Show()
        end
    end

    if not showStacks or isStackMode or isAttached or showStacksText then
        myBar.count:Hide()
    else
        myBar.count:Show()
    end

    -- Set Spell Name only when bar.name is NOT displaying centered stacks
    if not isTimerAndStacks and showNameEnabled then
        local desiredName = (config and config.name) or resolvedAuraName
        if not desiredName and blizzFrame.Bar and blizzFrame.Bar.Name then
            local bName = blizzFrame.Bar.Name:GetText()
            if bName and not (issecretvalue and issecretvalue(bName)) and bName ~= "" then
                desiredName = bName
            end
        end
        if not desiredName and myBar.spellID and not (issecretvalue and issecretvalue(myBar.spellID)) then
            desiredName = common.get_spell_name(myBar.spellID)
        end
        if desiredName and myBar._lastAuraName ~= desiredName then
            myBar._lastAuraName = desiredName
            common.SafeSetText(myBar.name, desiredName)
        end
    end

    if currentStacks == nil then
        currentStacks = 0
    end

    -- Peak Sustain Guard (Stack Mode only)
    local tempVal = nil
    local isSecret = issecretvalue and issecretvalue(currentStacks)
    if not isSecret then
        tempVal = tonumber(currentStacks)
    end

    local skipSetValue = false
    if isStackMode then
        if isSecret then
            myBar._stackPeakVal = currentStacks
            myBar._stackPeakTimer = GetTime()
        elseif tempVal and tempVal > 0 then
            myBar._stackPeakVal = tempVal
            myBar._stackPeakTimer = GetTime()
        elseif tempVal == 0 and myBar._stackPeakVal and myBar._stackPeakTimer then
            if GetTime() - myBar._stackPeakTimer < 0.05 then
                currentStacks = myBar._stackPeakVal
                skipSetValue = true
            else
                myBar._stackPeakVal = nil
            end
        end
    end

    myBar.currentStacks = currentStacks

    -- MAIN BAR UPDATE LOGIC
    if isStackMode then
        local maxVal = (type(maxStacks) == "number" and maxStacks > 0) and maxStacks or 12
        if myBar._appliedMaxVal ~= maxVal then
            myBar._appliedMaxVal = maxVal
            myBar.status:SetMinMaxValues(0, maxVal)
        end

        if not skipSetValue then
            if issecretvalue and issecretvalue(currentStacks) then
                local interp = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
                myBar.status:SetValue(currentStacks, interp)
            else
                local num = tonumber(currentStacks)
                if num and num >= 0 and num <= maxVal then
                    myBar.status:SetValue(num)
                else
                    myBar.status:SetValue(0)
                end
            end
        end
    elseif blizzFrame.Bar then
        myBar._appliedMaxVal = nil
        myBar.status:SetMinMaxValues(blizzFrame.Bar:GetMinMaxValues())
        myBar.status:SetValue(blizzFrame.Bar:GetValue())
    end

    -- Unified Stack & Duration Text Updates
    if isTimerAndStacks then
        _apply_stack_text_to_fs(myBar.name, myBar, "_lastStackNameText", currentStacks, not isStackMode)
    end

    if showStacksText and not isTimerAndStacks then
        _apply_stack_text_to_fs(myBar.time, myBar, "_lastStackTimeText", currentStacks, not isStackMode)
    elseif showDurationEnabled and blizzFrame.Bar then
        _apply_duration_text_to_bar(myBar, blizzFrame)
    end

    if showStacks and not isStackMode and not isAttached and not showStacksText then
        _apply_stack_text_to_fs(myBar.count, myBar, "_lastCount", currentStacks, true)
    end

    -- Pandemic recolor if bar is active in pandemic window
    local tBarsCfg = (sfui.config and sfui.config.trackedBars) or _emptyTable
    local shouldRecolor = (config and config.pandemicEnabled ~= nil) and config.pandemicEnabled or (tBarsCfg.pandemicRecolor ~= false)
    if shouldRecolor and myBar:IsShown() and myBar._inPandemic then
        local pColor = (config and config.pandemicColor) or tBarsCfg.pandemicColor or DEFAULT_PANDEMIC_COLOR
        myBar.status:SetStatusBarColor(common.unpack_color(pColor))
    end
end

local function SyncWithBlizzard()
    sfui.trackedbars.isDirty = true
end



local function ProcessBlizzardSync()
    local viewer = GetBuffBarViewer()
    if not viewer or not viewer.itemFramePool then
        if sfui.isEra and sfui.trackedbars.ClassicSync then
            sfui.trackedbars.ClassicSync()
        end
        return
    end

    wipe(activeCooldownIDs)
    local layoutNeeded = false

    -- Global Hide Check
    -- We use our own OOC logic to avoid touching Blizzard's protected viewer state if it's crashing.
    local mustHide = false
    local db = (SfuiDB and SfuiDB.trackedBars) or
        (cfg and cfg.trackedBars and cfg.trackedBars.defaults) or _emptyTable

    local inCombat = common.is_in_combat()
    local isMoving = (sfui.movers and sfui.movers.isUnlocked) == true
    if not isMoving then
        if db.hideOOC and not inCombat then
            mustHide = true
        elseif not inCombat then
            if db.hideMounted and common.is_mounted_or_travel_form() then
                mustHide = true
            elseif db.hideInVehicle and (UnitHasVehicleUI("player") or UnitInVehicle("player")) then
                mustHide = true
            elseif SfuiDB and SfuiDB.hideDragonriding and common.IsDragonriding() then
                mustHide = true
            end
        end
    end

    if mustHide then
        for _, bar in pairs(bars) do
            if bar:IsShown() then
                bar:Hide()
                layoutNeeded = true
            end
        end
        if layoutNeeded then UpdateLayout() end
        return -- Skip processing updates if everything is hidden globally
    end

    -- Process Blizzard Frames
    for blizzFrame in viewer.itemFramePool:EnumerateActive() do
        if blizzFrame.cooldownID then
            local id = blizzFrame.cooldownID
            local info = _cdViewerInfoCache[id]
            if not info and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                info = C_CooldownViewer.GetCooldownViewerCooldownInfo(id)
                if info then _cdViewerInfoCache[id] = info end
            end

            -- Every frame in BuffBarCooldownViewer.itemFramePool is an active TrackedBar (Category 3);
            -- avoid calling CooldownViewerSettings:GetDataProvider():GetCooldownInfoForID() which taints LayoutManager
            local specBars = common.get_tracked_bars()
            local isManuallyTracked = specBars and specBars[id]
            local isCoverSpell = auraResolver and auraResolver.IsCoverSpell and auraResolver.IsCoverSpell(info, id)
            local isValidTrackedBar = not isCoverSpell

            if isValidTrackedBar then
                local isSpecRestricted = false

                local isKnown = not info
                    or (auraResolver and auraResolver.IsCooldownItemKnown and auraResolver.IsCooldownItemKnown(info, id))
                    or info.isKnown ~= false
                if not isKnown then
                    isSpecRestricted = true
                end

                if not isSpecRestricted and not isManuallyTracked and cfg.trackedBars and cfg.trackedBars.defaults then
                    local def = cfg.trackedBars.defaults[id]
                    if def and def.specID then
                        local currentSpec = common.get_current_spec_id and common.get_current_spec_id()
                        if currentSpec and not (common.is_spec_match and common.is_spec_match(def.specID, currentSpec) or def.specID == currentSpec) then
                            isSpecRestricted = true
                        end
                    end
                end

                if not isSpecRestricted then
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
                    if myBar._selfDriven then
                        -- blizzard now provides a frame for this item: hand back to mirroring
                        ResetSelfDrivenBar(myBar)
                    end

                    local config = GetTrackedBarConfig(id) -- Cache config lookup once
                    local isStackMode = config and config.stackMode or false

                    -- IMPORTANT: Sync bar data BEFORE the visibility check so that
                    -- stack count text is always fresh. If we check isStackModeWithStacks
                    -- on stale count text (from the previous tick) we get a Hide→SyncData→Show
                    -- sequence on every aura refresh, which is exactly the Bone Shield flash.
                    SyncBarData(myBar, blizzFrame, config, isStackMode, id, info)

                    -- Sync Visibility
                    local db = SfuiDB and SfuiDB.trackedBars or {}
                    local hideInactive = db.hideInactive ~= false -- Default to True if nil

                    -- Check if this is a stack mode bar with active stacks
                    -- (count state is now populated by SyncBarData above)
                    local isStackModeWithStacks = false
                    if isStackMode then
                        local cStacks = myBar.currentStacks
                        if issecretvalue(cStacks) then
                            isStackModeWithStacks = true
                        else
                            local nStacks = tonumber(cStacks) or 0
                            if nStacks > 0 then
                                isStackModeWithStacks = true
                            end
                        end
                    end

                    local shouldShow = ShouldBarBeVisible(config, blizzFrame, isStackModeWithStacks, hideInactive, myBar.spellID)

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
                end
            end
        end
    end

    -- Self-driven bars: tracked entries blizzard has no buff bar frame for (e.g. "seals")
    _selfDrivenBarCount = 0
    if auraResolver then
        wipe(_selfDrivenWatchlist)
        local specBars = common.get_tracked_bars()
        if specBars then
            local barDB = SfuiDB and SfuiDB.trackedBars or {}
            local hideInactive = barDB.hideInactive ~= false
            for rawID, entryCfg in pairs(specBars) do
                local id = tonumber(rawID)
                if id and entryCfg and not activeCooldownIDs[id] then
                    local info = _cdViewerInfoCache[id]
                    if not info and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                        info = C_CooldownViewer.GetCooldownViewerCooldownInfo(id)
                        if info then _cdViewerInfoCache[id] = info end
                    end
                    local isKnown = not info or auraResolver.IsCooldownItemKnown(info, id)
                    if isKnown and auraResolver.WantsAura(info, false, info and info.linkedSpellIDs, info and info.spellID, id) then
                        activeCooldownIDs[id] = true
                        _selfDrivenBarCount = _selfDrivenBarCount + 1

                        if not bars[id] then
                            bars[id] = GetBarFromPool(id) or CreateBar(id)
                            layoutNeeded = true
                        end

                        local myBar = bars[id]
                        local config = GetTrackedBarConfig(id)
                        local isStackMode = config and config.stackMode or false
                        SyncSelfDrivenBar(myBar, config, isStackMode, id, info)

                        local watchSlot = myBar._watchDescriptor
                        if not watchSlot then
                            watchSlot = {}
                            myBar._watchDescriptor = watchSlot
                        end
                        watchSlot.cooldownID = id
                        watchSlot.candidates = myBar._auraCandidates
                        watchSlot.isForeverSeal = auraResolver.IsForeverSealEntry and auraResolver.IsForeverSealEntry(nil, info, myBar.spellID) or false
                        _selfDrivenWatchlist[_selfDrivenBarCount] = watchSlot

                        local shouldShow = myBar._auraActive or not hideInactive
                        if shouldShow then
                            if not myBar:IsShown() then
                                myBar:Show()
                                layoutNeeded = true
                            end
                        elseif myBar:IsShown() then
                            myBar:Hide()
                            layoutNeeded = true
                        end
                    end
                end
            end
        end
        if auraResolver.SetBarWatchlist then
            auraResolver.SetBarWatchlist(_selfDrivenWatchlist)
        end
    end

    -- Cleanup with 0.08s graceful death to absorb Blizzard UI frame recreation blinking
    for id, bar in pairs(bars) do
        if not activeCooldownIDs[id] then
            if not bar._missingTime then
                bar._missingTime = GetTime()
            end
            if GetTime() - bar._missingTime > 0.08 then
                sfui.trackedbars.RemoveBar(id, true)
                layoutNeeded = true
            end
        else
            bar._missingTime = nil
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


-- Public function to force layout update (e.g., when settings change)
function sfui.trackedbars.ForceLayoutUpdate()
    UpdateLayout()
end


-- Static update loop for bars (Eliminates OnUpdate closure churn)
local function UpdateBarsState()
    if _numShownBars == 0 then return end
    local viewer = GetBuffBarViewer()
    if not viewer or not viewer.itemFramePool then return end
    local tBarsCfg = (sfui.config and sfui.config.trackedBars) or _emptyTable

    for blizzFrame in viewer.itemFramePool:EnumerateActive() do
        if blizzFrame.cooldownID then
            local myBar = bars[blizzFrame.cooldownID]
            if myBar and not myBar._selfDriven and myBar:IsShown() and blizzFrame.Bar then
                local config = myBar._config or GetTrackedBarConfig(blizzFrame.cooldownID)
                local isStackMode, isAttached, showStacksText, showDurationEnabled, _, showStacks, _, isTimerAndStacks = ResolveBarTextFlags(config)
                local needLiveStacks = isStackMode or showStacksText or (showStacks and not isAttached)

                -- Live stack refresh from Blizzard's cached auraData with active-floor & peak-sustain guards
                if needLiveStacks then
                    local ad = blizzFrame.auraDataCached
                    local apps = ad and ad.applications
                    if apps ~= nil then
                        if issecretvalue and issecretvalue(apps) then
                            myBar.currentStacks = apps
                            if isStackMode then
                                myBar._stackPeakVal = apps
                                myBar._stackPeakTimer = GetTime()
                            end
                        else
                            local nApps = tonumber(apps) or 0
                            if nApps < 1 and blizzFrame.IsActive and blizzFrame:IsActive() then
                                nApps = 1
                            end
                            if isStackMode then
                                if nApps > 0 then
                                    myBar._stackPeakVal = nApps
                                    myBar._stackPeakTimer = GetTime()
                                elseif myBar._stackPeakVal and myBar._stackPeakTimer and (GetTime() - myBar._stackPeakTimer < 0.05) then
                                    nApps = myBar._stackPeakVal
                                else
                                    myBar._stackPeakVal = nil
                                end
                            end
                            myBar.currentStacks = nApps
                        end
                    end
                end

                -- StatusBar progression
                if not isStackMode then
                    myBar.status:SetMinMaxValues(blizzFrame.Bar:GetMinMaxValues())
                    myBar.status:SetValue(blizzFrame.Bar:GetValue())
                elseif myBar.currentStacks ~= nil then
                    local maxVal = myBar._maxStacks or GetMaxStacksForBar(blizzFrame.cooldownID, config, myBar.spellID) or 12
                    if myBar._appliedMaxVal ~= maxVal then
                        myBar._appliedMaxVal = maxVal
                        myBar.status:SetMinMaxValues(0, maxVal)
                    end
                    if issecretvalue and issecretvalue(myBar.currentStacks) then
                        local interp = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
                        myBar.status:SetValue(myBar.currentStacks, interp)
                    else
                        local num = tonumber(myBar.currentStacks)
                        if num and num >= 0 and num <= maxVal then
                            myBar.status:SetValue(num)
                        else
                            myBar.status:SetValue(0)
                        end
                    end
                end

                -- Unified text updates (supports both stackMode and showStacksText duration bars)
                if isTimerAndStacks then
                    _apply_stack_text_to_fs(myBar.name, myBar, "_lastStackNameText", myBar.currentStacks, not isStackMode)
                end

                if showStacksText and not isTimerAndStacks then
                    _apply_stack_text_to_fs(myBar.time, myBar, "_lastStackTimeText", myBar.currentStacks, not isStackMode)
                elseif showDurationEnabled then
                    _apply_duration_text_to_bar(myBar, blizzFrame)
                end

                if showStacks and not isStackMode and not isAttached and not showStacksText then
                    _apply_stack_text_to_fs(myBar.count, myBar, "_lastCount", myBar.currentStacks, true)
                end

                -- Pandemic state read-only check (never reparent Blizzard's pooled PandemicIcon)
                local inPandemic = IsBlizzardItemInPandemic(blizzFrame)
                local wasPandemic = myBar._inPandemic == true

                local showGlow = (tBarsCfg.pandemicGlow ~= false) and (not config or config.pandemicGlow ~= false)
                if inPandemic and showGlow then
                    if not wasPandemic and sfui.glows and sfui.glows.start_glow then
                        sfui.glows.start_glow(myBar.iconFrame, PANDEMIC_GLOW_OPTS)
                    end
                elseif wasPandemic and not inPandemic then
                    if sfui.glows and sfui.glows.stop_glow then
                        sfui.glows.stop_glow(myBar.iconFrame)
                    end
                end

                -- Pandemic bar recolor (transition-gated to avoid 20Hz SetStatusBarColor spam)
                local shouldRecolor = (config and config.pandemicEnabled ~= nil) and config.pandemicEnabled or (tBarsCfg.pandemicRecolor ~= false)
                if shouldRecolor then
                    if inPandemic and not wasPandemic then
                        local pColor = (config and config.pandemicColor) or tBarsCfg.pandemicColor or DEFAULT_PANDEMIC_COLOR
                        myBar.status:SetStatusBarColor(common.unpack_color(pColor))
                    elseif wasPandemic and not inPandemic then
                        local defColor = GetBarNormalColor(config)
                        myBar.status:SetStatusBarColor(common.unpack_color(defColor))
                    end
                end
                myBar._inPandemic = inPandemic
            end
        end
    end
end

local _syncTimer = 0
local _lastOOCSyncTime = 0
local function _OnTrackedBarsUpdate(elapsed)
    local inCombat = common.is_in_combat()

    -- Fast out-of-combat sleep path: when no bars are active, sleep until dirty or periodic check
    if not inCombat and _numShownBars == 0 and not sfui.trackedbars.isDirty then
        _syncTimer = _syncTimer + elapsed
        if _syncTimer < 2.5 then
            return
        end
        _syncTimer = 0
        _lastOOCSyncTime = GetTime()
        ProcessBlizzardSync()
        return
    end

    local syncInterval = inCombat and 0.5 or 1.0
    _syncTimer = _syncTimer + elapsed

    -- 1. Structure / Visibility Sync
    if sfui.trackedbars.isDirty then
        local now = GetTime()
        -- On Forever, keep self-driven seal switches responsive; on Retail, use lean OOC/combat throttle.
        local minCooldown = sfui.isCamelot and (inCombat and 0.15 or 0.1) or (inCombat and 0.25 or 1.0)
        if _numShownBars == 0 or (now - _lastOOCSyncTime) >= minCooldown then
            sfui.trackedbars.isDirty = false
            _lastOOCSyncTime = now
            _syncTimer = 0
            ProcessBlizzardSync()
        end
    elseif _syncTimer >= syncInterval then
        _syncTimer = 0
        _lastOOCSyncTime = GetTime()
        ProcessBlizzardSync()
    end

    -- 2. Visual Updates (Smooth status bar progression and duration text)
    if _numShownBars > 0 then
        local viewer = GetBuffBarViewer()
        if viewer and viewer.itemFramePool then
            UpdateBarsState()
        elseif sfui.isEra and sfui.trackedbars.ClassicUpdateState then
            sfui.trackedbars.ClassicUpdateState()
        end
    end
end

local _viewerHooked = false
local _registryHooked = false
local function HookBuffBarViewer()
    local viewer = GetBuffBarViewer()
    if viewer then
        viewer:SetAlpha(0)
        if not _viewerHooked then
            _viewerHooked = true
            if viewer.RefreshLayout then
                hooksecurefunc(viewer, "RefreshLayout", SyncWithBlizzard)
            end
            if viewer.RefreshData then
                hooksecurefunc(viewer, "RefreshData", SyncWithBlizzard)
            end
        end
    end
    if not _registryHooked and _G.EventRegistry and _G.EventRegistry.RegisterCallback then
        _registryHooked = true
        _G.EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", function()
            sfui.trackedbars.InvalidateConfigCache()
            SyncWithBlizzard()
        end, sfui.trackedbars)
    end
end

function sfui.trackedbars.initialize()
    if container then return end
    if (sfui.isRetail or sfui.isCamelot) and not sfui.common.is_addon_loaded("Blizzard_CooldownViewer") then
        sfui.common.ensure_addon_loaded("Blizzard_CooldownViewer")
    end

    container = CreateFrame("Frame", "SfuiTrackedBarsContainer", UIParent)
    local cfg = sfui.config.trackedBars
    container:SetSize(cfg.width, cfg.height)

    common.ensure_tracked_bar_db() -- Initialize DB structure

    -- Set visibility defaults from config if not already set
    if SfuiDB.trackedBars.hideOOC == nil then
        SfuiDB.trackedBars.hideOOC = cfg.hideOOC ~= nil and cfg.hideOOC or false
    end
    if SfuiDB.trackedBars.hideInactive == nil then
        SfuiDB.trackedBars.hideInactive = cfg.hideInactive ~= nil and cfg.hideInactive or false
    end
    if SfuiDB.trackedBars.hideMounted == nil then
        SfuiDB.trackedBars.hideMounted = cfg.hideMounted ~= nil and cfg.hideMounted or true
    end

    -- Position
    sfui.trackedbars.UpdatePosition()

    if sfui.movers and sfui.movers.Register then
        sfui.movers.Register(container, {
            key = "trackedbars",
            label = "tracked cooldown bars",
            preferredPoint = "BOTTOM",
            customSize = function()
                return container:GetWidth(), container:GetHeight()
            end,
            getPoint = function()
                local db = SfuiDB and SfuiDB.trackedBars
                local pt = (db and db.anchor and db.anchor.point) or "BOTTOM"
                local relPt = (db and db.anchor and db.anchor.relPoint) or pt
                local x = (db and db.anchor and db.anchor.x) or -300
                local y = (db and db.anchor and db.anchor.y) or 300
                return pt, UIParent, relPt, x, y
            end,
            setPoint = function(point, relTo, relPoint, x, y)
                local db = common.ensure_tracked_bar_db()
                db.anchor = db.anchor or {}
                db.anchor.point = point
                db.anchor.relPoint = relPoint
                db.anchor.x = x
                db.anchor.y = y
                sfui.trackedbars.UpdatePosition()
                if sfui.movers and sfui.movers.isUnlocked and sfui.trackedicons and sfui.trackedicons.SyncMovers then
                    sfui.trackedicons.SyncMovers()
                end
            end,
            resetPosition = function()
                local db = common.ensure_tracked_bar_db()
                db.anchor = db.anchor or {}
                db.anchor.point = "BOTTOM"
                db.anchor.relPoint = "BOTTOM"
                db.anchor.x = -300
                db.anchor.y = 300
                sfui.trackedbars.UpdatePosition()
                if sfui.movers and sfui.movers.isUnlocked and sfui.trackedicons and sfui.trackedicons.SyncMovers then
                    sfui.trackedicons.SyncMovers()
                end
            end,
            isEnabled = function()
                return container ~= nil
            end,
            onEnterEditMode = function()
                container:Show()
                container:SetAlpha(1)
            end,
            onExitEditMode = function()
                -- normal visibility update logic will manage it
            end,
        })
    end

    -- Event listener for visibility updates
    sfui.events.RegisterEvent("PLAYER_REGEN_DISABLED", SyncWithBlizzard)
    sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", SyncWithBlizzard)
    sfui.events.RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED", SyncWithBlizzard)
    if sfui.events.RegisterUnitEvent then
        sfui.events.RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player", SyncWithBlizzard)
        sfui.events.RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player", SyncWithBlizzard)
    end
    sfui.events.RegisterEvent("UPDATE_BONUS_ACTIONBAR", SyncWithBlizzard)
    sfui.events.RegisterEvent("PLAYER_CAN_GLIDE_CHANGED", SyncWithBlizzard)

    -- 12.0.5+: fires when Blizzard switches the aura data provider to/from obfuscated mode
    sfui.events.RegisterEvent("AURA_DATA_PROVIDER_SWITCH", function(_event, useRealDataProvider)
        if not useRealDataProvider then
            for _, bar in pairs(bars) do
                bar._auraStackCache = nil
                bar._auraStackTimer = nil
                if bar._inPandemic then
                    bar._inPandemic = false
                    if sfui.glows and sfui.glows.stop_glow then
                        sfui.glows.stop_glow(bar.iconFrame)
                    end
                end
            end
        end
        sfui.trackedbars.isDirty = true
    end)

    -- Throttled OnUpdate for smooth bar progress AND structure updates
    sfui.events.RegisterUpdate("TrackedBars", cfg.updateThrottle or 0.05, _OnTrackedBarsUpdate)

    -- Real-time events for instant reaction with relaxed OOC pacing and combat throttling
    local _lastAuraEvent = 0
    sfui.events.RegisterUnitEvent("UNIT_AURA", "player", function()
        local inCombat = common.is_in_combat()
        local now = GetTime()
        local interval = inCombat and 0.25 or 1.0
        if (now - _lastAuraEvent) >= interval then
            _lastAuraEvent = now
            SyncWithBlizzard()
        else
            sfui.trackedbars.isDirty = true
        end
    end)

    local _lastCdEvent = 0
    sfui.events.RegisterEvent("SPELL_UPDATE_CHARGES", function()
        local inCombat = common.is_in_combat()
        local now = GetTime()
        local interval = inCombat and 0.25 or 1.0
        if (now - _lastCdEvent) >= interval then
            _lastCdEvent = now
            SyncWithBlizzard()
        else
            sfui.trackedbars.isDirty = true
        end
    end)

    sfui.events.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function()
        sfui.trackedbars.InvalidateConfigCache()
        if sfui.trackedbars.UpdateTopAnchor then sfui.trackedbars.UpdateTopAnchor() end
        SyncWithBlizzard()
    end)
    sfui.events.RegisterEvent("PLAYER_TALENT_UPDATE", function()
        sfui.trackedbars.InvalidateConfigCache()
        SyncWithBlizzard()
    end)
    sfui.events.RegisterEvent("TRAIT_CONFIG_UPDATED", function()
        sfui.trackedbars.InvalidateConfigCache()
        SyncWithBlizzard()
    end)
    sfui.events.RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED", function()
        HookBuffBarViewer()
        sfui.trackedbars.InvalidateConfigCache()
        SyncWithBlizzard()
    end)
    sfui.events.RegisterEvent("ADDON_LOADED", function(_event, loadedName)
        if loadedName == "Blizzard_CooldownViewer" then
            HookBuffBarViewer()
            SyncWithBlizzard()
        end
    end)

    sfui.events.RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", function(_, _, _, castSid)
        if not castSid or (issecretvalue and issecretvalue(castSid)) then return end
        SyncWithBlizzard()
    end)

    HookBuffBarViewer()

    -- Hide Blizzard Cooldown Frames
    common.hide_blizzard_cooldown_viewers()

    -- Hook into bars state for attachment updates
    local _pendingLayoutTimer = false
    hooksecurefunc(sfui.bars, "on_state_changed", function()
        if _pendingLayoutTimer then return end
        _pendingLayoutTimer = true
        -- Delay slightly to ensure bars have hidden/shown
        C_Timer.After(0.05, function()
            _pendingLayoutTimer = false
            sfui.trackedbars.ForceLayoutUpdate()
        end)
    end)
end

local _tbDebug = {}
function sfui.trackedbars_debug_info()
    local barCount = 0
    for _ in pairs(bars) do barCount = barCount + 1 end
    local cacheCount = 0
    for _ in pairs(configCache) do cacheCount = cacheCount + 1 end
    _tbDebug.activeBars  = barCount
    _tbDebug.shownBars   = _numShownBars
    _tbDebug.barPool     = #barPool
    _tbDebug.configPool  = #configPool
    _tbDebug.configCache = cacheCount
    _tbDebug.isDirty     = sfui.trackedbars.isDirty or false
    _tbDebug.loopActive  = ((common and common.is_in_combat and common.is_in_combat()) or (_numShownBars > 0)) and true or false
    return _tbDebug
end

sfui.trackedbars.OnEnable = function(self) self.initialize() end
sfui.trackedbars.OnSettingsChanged = function(self, k, v)
        if self.UpdatePosition then self.UpdatePosition() end
        if self.UpdateAppearance then self.UpdateAppearance() end
        if self.ForceLayoutUpdate then self.ForceLayoutUpdate() end
    end
    sfui.trackedbars.OnSpecChanged = function(self, specID)
        if self.InvalidateConfigCache then self.InvalidateConfigCache() end
        if self.UpdateAppearance then self.UpdateAppearance() end
        if self.ForceLayoutUpdate then self.ForceLayoutUpdate() end
    end
    sfui.trackedbars.GetDebugInfo = sfui.trackedbars_debug_info
    sfui.RegisterModule("trackedbars", sfui.trackedbars)

