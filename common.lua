local addonName, addon = ...
sfui = sfui or {}
sfui.common = {}


-- Static pcall targets (Performance optimization: no closures in hot paths)
local function pcall_issecret(val) return val == val end
local function pcall_num_pos(val) return type(val) == "number" and val > 0 end
local function pcall_gt(v1, v2) return v1 > (v2 or 0) end
local function pcall_identity(val) return val end

-- Internal helper to detect restricted data in Mythic+
-- Comparing "Secret Values" to anything (including themselves) throws a Lua error.
-- WoW 11.x+ has a built-in issecretvalue global; we use it if present.
local function issecretvalue(val)
    if _G.issecretvalue then return _G.issecretvalue(val) end
    if val == nil then return false end
    local success = pcall(pcall_issecret, val)
    return not success
end
sfui.common.issecretvalue = issecretvalue

-- Robust helper to check if an aura/ID is present, even if it's a secret value
function sfui.common.HasAuraInstanceID(value)
    if value == nil then return false end
    if issecretvalue(value) then return true end
    if type(value) == "number" and value == 0 then return false end
    return true
end

-- Safe numeric comparison
function sfui.common.IsNumericAndPositive(value)
    if value == nil then return false end
    local ok, result = pcall(pcall_num_pos, value)
    return ok and result
end

-- Reusable buffer for string.format
local fmt_cache = "%.0f"
local function pcall_format(val, decimals)
    local fmt = (decimals == 0) and "%.0f" or ("%." .. (decimals or 0) .. "f")
    return string.format(fmt, val)
end

-- Safe duration formatting
function sfui.common.SafeFormatDuration(value, decimals)
    if value == nil then return "" end
    local ok, formatted = pcall(pcall_format, tonumber(value), decimals or 0)
    return ok and formatted or tostring(value)
end

-- Helper: Check for Dragonriding state (Vigor)
function sfui.common.IsDragonriding()
    if not IsMounted() then return false end

    -- Check for Vigor (Enum.PowerType.AlternateMount = 29)
    -- This resource is only active/max > 0 when on a Dragonriding/Skyriding mount
    if UnitPowerMax("player", 29) > 0 then
        return true
    end

    -- Fallback: Check for Gliding Info
    local isDragonriding = false
    pcall(function()
        if C_PlayerInfo and C_PlayerInfo.GetGlidingInfo then
            local _, canGlide = C_PlayerInfo.GetGlidingInfo()
            if canGlide then isDragonriding = true end
        end
    end)
    return isDragonriding
end

-- Safe helper to check if player is on GCD and get the duration
function sfui.common.GetGCDInfo()
    local ok, ci = pcall(C_Spell.GetSpellCooldown, 61304)
    if ok and ci and ci.duration and ci.duration > 0 then
        return true, ci.duration
    end
    return false, 0
end

-- Reusable cooldown lookups
local function pcall_charge_dur(id) return C_Spell.GetSpellChargeDuration(id) end
local function pcall_spell_dur(id) return C_Spell.GetSpellCooldownDuration(id) end

-- Safe helper to get a duration object for a spell (nil check is non-secret)
function sfui.common.GetCooldownDurationObj(spellID)
    if not spellID then return nil end
    local ok, obj
    if C_Spell.GetSpellChargeDuration then
        ok, obj = pcall(pcall_charge_dur, spellID)
    end
    if not ok or not obj then
        if C_Spell.GetSpellCooldownDuration then
            ok, obj = pcall(pcall_spell_dur, spellID)
        end
    end
    -- Return object as-is, let caller handle GCD
    return obj
end

-- Check if a cooldown frame is showing an active cooldown
-- Uses frame methods that work with secret values
function sfui.common.IsCooldownFrameActive(cooldownFrame)
    if not cooldownFrame then return false end

    -- GetCooldownDuration returns duration in milliseconds
    -- Can be secret, but we can pass it to comparison via pcall
    local ok, duration = pcall(function() return cooldownFrame:GetCooldownDuration() end)

    if not ok then return false end

    -- If duration is secret, check if it's just GCD
    if issecretvalue(duration) then
        local onGCD, gcdDur = sfui.common.GetGCDInfo()
        -- If player is on GCD, assume this is GCD and not a real cooldown
        if onGCD then return false end
        -- Otherwise assume it's a real cooldown (secret in M+)
        return true
    end

    -- Non-secret: check if > 1510ms (exclude GCD + small buffer)
    if not duration or duration == 0 then
        return false
    end

    local onGCD, gcdDur = sfui.common.GetGCDInfo()
    if onGCD and duration <= (gcdDur * 1000 + 10) then
        return false
    end

    return duration > 1510
end

-- Safe comparison helpers (Crash-proof against Secret Values in M+)
function sfui.common.SafeGT(val, target)
    if val == nil then return false end
    if issecretvalue(val) then return true end -- Secret = exists/active
    local ok, result = pcall(pcall_gt, val, target)
    return ok and result
end

function sfui.common.SafeValue(val, fallback)
    if val == nil then return fallback end
    if issecretvalue(val) then return val end
    local ok, result = pcall(pcall_identity, val)
    return ok and result or fallback
end

function sfui.common.SafeNotFalse(val)
    if val == nil then return true end
    if issecretvalue(val) then return true end
    return val ~= false
end

-- Safely set text on a fontstring (SetText accepts secret values)
function sfui.common.SafeSetText(fontString, text, decimals)
    if not fontString then return end
    -- if decimals is nil and text is a string, skip duration formatting to avoid 0.0 suffix
    if decimals == nil and type(text) == "string" then
        fontString:SetText(text)
    else
        fontString:SetText(sfui.common.SafeFormatDuration(text, decimals) or "")
    end
end

-- Safely set value on a statusbar (SetValue accepts secret values)
function sfui.common.SafeSetValue(bar, value)
    if not bar or not bar.SetValue then return end
    bar:SetValue(value or 0)
end

-- Safely compare units (UnitIsUnit crashes on secret values if execution is tainted)
function sfui.common.SafeUnitIsUnit(unit1, unit2)
    if not unit1 or not unit2 then return false end
    if issecretvalue(unit1) or issecretvalue(unit2) then
        -- In secret context, we can't safely use UnitIsUnit.
        -- We fall back to direct string comparison if they are strings.
        if type(unit1) == "string" and type(unit2) == "string" then
            return unit1 == unit2
        end
        return false
    end
    local success, result = pcall(UnitIsUnit, unit1, unit2)
    return success and result
end

function sfui.common.copy(t)
    if type(t) ~= "table" then return t end
    local res = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            res[k] = sfui.common.copy(v)
        else
            res[k] = v
        end
    end
    return res
end

local _, playerClass, playerClassID = UnitClass("player")

-- ... (skipping lines)

-- Safe Direct Lookup Tables (TWW / Dragonflight)
sfui.common.FLASK_IDS = {
    -- The War Within (Phials / Flasks)
    431972, -- Flask of Alchemical Chaos
    431973, -- Flask of Tempered Aggression
    431974, -- Flask of Tempered Swiftness
    431971, -- Flask of Tempered Mastery
    431970, -- Flask of Tempered Versatility
    432029, -- Crystalline Phial of Perception (Gathering)
    -- Dragonflight (Phials)
    370661, -- Phial of Elemental Chaos
    370652, -- Phial of Static Empowerment
    373257, -- Phial of Glacial Fury
    371038, -- Phial of Icy Preservation
    371172, -- Phial of Tepid Versatility
    371339, -- Phial of Tobacious Versatility -> likely typo in source, checking IDs later if needed
    371204, -- Phial of Still Air
    371354, -- Phial of the Eye in the Storm
    371386, -- Phial of Charged Isolation
    371339, -- Phial of Corrupting Rage
}

sfui.common.AUGMENT_RUNE_IDS = {
    -- The War Within
    444583, -- Crystallized Augment Rune
    -- Dragonflight
    393438, -- Draconic Augment Rune
    410332, -- Dreambound Augment Rune
}

sfui.common.VANTUS_RUNE_IDS = {
    -- The War Within
    444266, -- Vantus Rune: Nerub-ar Palace
    -- Dragonflight
    410337, -- Vantus Rune: Amirdrassil
    400305, -- Vantus Rune: Aberrus
    394148, -- Vantus Rune: Vault of the Incarnates
}

sfui.common.WEAPON_ENCHANT_IDS = {
    -- The War Within (Oils / Stones)
    432321, -- Algari Mana Oil
    432323, -- Oil of Beledar's Grace
    432328, -- Ironclaw Whetstone
    432327, -- Ironclaw Weightstone
    -- Dragonflight
    394017, -- Howling Rune
    394018, -- Buzzing Rune
}

-- Note: Food is often best checked by "Well Fed" name, but specific IDs can be added here if language-agnosticism is required.
-- For now, we'll stick to the "Well Fed" check in reminders.lua which is already safe via GetAuraDataBySpellName.

local wipe = wipe

-- Returns the cached player class (e.g., "WARRIOR", "MAGE")
function sfui.common.get_player_class()
    return playerClass, playerClassID
end

-- Helper to safely ensure tracked bar DB structure exists
-- Returns the tracked bar entry for the given cooldownID, or the trackedBars table if no ID provided
function sfui.common.ensure_tracked_bar_db(cooldownID)
    SfuiDB = SfuiDB or {}
    SfuiDB.trackedBars = SfuiDB.trackedBars or {}
    if cooldownID then
        SfuiDB.trackedBars[cooldownID] = SfuiDB.trackedBars[cooldownID] or {}
        return SfuiDB.trackedBars[cooldownID]
    end
    return SfuiDB.trackedBars
end

-- ========================================
-- Per-Spec Panel Configuration Helpers
-- ========================================

-- One-time migration from old flat array to per-spec structure
function sfui.common.migrate_cooldown_panels_to_spec()
    -- Skip if already migrated or nothing to migrate
    if SfuiDB.cooldownPanelsBySpec or not SfuiDB.cooldownPanels then
        return
    end

    -- Get current spec
    local currentSpecID = sfui.common.get_current_spec_id()
    if not currentSpecID or currentSpecID == 0 then
        -- No spec yet (low level character), defer migration
        return
    end

    -- Migrate existing panels to current spec
    SfuiDB.cooldownPanelsBySpec = {
        [currentSpecID] = SfuiDB.cooldownPanels
    }

    -- Mark old format as migrated (keep for reference but don't use)
    SfuiDB._cooldownPanelsMigrated = true
end

-- Populate CENTER panel with cooldowns from CDM Essential Cooldowns (category 0)
function sfui.common.populate_center_panel_from_cdm()
    local entries = {}

    -- Try using CooldownViewerSettings DataProvider (source of truth for the list)
    if CooldownViewerSettings and CooldownViewerSettings.GetDataProvider then
        local dataProvider = CooldownViewerSettings:GetDataProvider()
        if dataProvider then
            local cooldownIDs = dataProvider:GetOrderedCooldownIDs()
            if cooldownIDs then
                for _, cooldownID in ipairs(cooldownIDs) do
                    if not sfui.common.issecretvalue(cooldownID) then
                        local info = dataProvider:GetCooldownInfoForID(cooldownID)
                        -- Category 0 is Essential Cooldowns
                        if info and info.isKnown and (info.category == 0 or not info.category) then
                            table.insert(entries, {
                                type = "cooldown",
                                cooldownID = cooldownID,
                                spellID = info.spellID,
                                id = info.spellID,
                                settings = { showText = true }
                            })
                        end
                    end
                end
            end
        end
    end

    -- Fallback: use C_CooldownViewer direct API if provider not ready or empty
    if #entries == 0 and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet then
        local cooldownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(0, false)
        if cooldownIDs then
            for _, cooldownID in ipairs(cooldownIDs) do
                local cdInfo = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
                if cdInfo and cdInfo.isKnown then
                    table.insert(entries, {
                        type = "cooldown",
                        cooldownID = cooldownID,
                        spellID = cdInfo.spellID,
                        id = cdInfo.spellID,
                        settings = { showText = true }
                    })
                end
            end
        end
    end

    return entries
end

-- Populate UTILITY panel with cooldowns from CDM Group 1 (Category 1)
function sfui.common.populate_utility_panel_from_cdm()
    local entries = {}

    -- Try using CooldownViewerSettings DataProvider
    if CooldownViewerSettings and CooldownViewerSettings.GetDataProvider then
        local dataProvider = CooldownViewerSettings:GetDataProvider()
        if dataProvider then
            local cooldownIDs = dataProvider:GetOrderedCooldownIDs()
            if cooldownIDs then
                for _, cooldownID in ipairs(cooldownIDs) do
                    if not sfui.common.issecretvalue(cooldownID) then
                        local info = dataProvider:GetCooldownInfoForID(cooldownID)
                        -- Category 1 is Utility / Group 1
                        if info and info.isKnown and info.category == 1 then
                            table.insert(entries, {
                                type = "cooldown",
                                cooldownID = cooldownID,
                                spellID = info.spellID,
                                id = info.spellID,
                                settings = { showText = true }
                            })
                        end
                    end
                end
            end
        end
    end

    -- Fallback: C_CooldownViewer direct API
    if #entries == 0 and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet then
        local cooldownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(1, false) -- Category 1
        if cooldownIDs then
            for _, cooldownID in ipairs(cooldownIDs) do
                local cdInfo = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
                if cdInfo and cdInfo.isKnown then
                    table.insert(entries, {
                        type = "cooldown",
                        cooldownID = cooldownID,
                        spellID = cdInfo.spellID,
                        id = cdInfo.spellID,
                        settings = { showText = true }
                    })
                end
            end
        end
    end

    return entries
end

-- Get panels for current spec
function sfui.common.get_cooldown_panels()
    local specID = sfui.common.get_current_spec_id()
    if not specID or specID == 0 then
        -- Fallback to empty table if no spec
        return {}
    end

    SfuiDB.cooldownPanelsBySpec = SfuiDB.cooldownPanelsBySpec or {}
    SfuiDB.cooldownPanelsBySpec[specID] = SfuiDB.cooldownPanelsBySpec[specID] or {}

    local panels = SfuiDB.cooldownPanelsBySpec[specID]

    -- Auto-create CENTER panel if it doesn't exist (one-time population)
    local centerPanelIdx = nil
    for i, panel in ipairs(panels) do
        if panel.name == "CENTER" then
            centerPanelIdx = i
            break
        end
    end

    if not centerPanelIdx then
        local centerPanel = {
            name = "CENTER",
            enabled = true,
            x = 0,
            y = 0,
            size = 50,
            columns = 10,
            spacing = 0,
            spanWidth = true,
            showBackground = true,
            backgroundAlpha = 0.5,
            placement = "center",
            anchor = "center",
            growthV = "Down",
            anchorTo = "Health Bar",
            entries = sfui.common.populate_center_panel_from_cdm()
        }
        table.insert(panels, 1, centerPanel) -- Insert at beginning
        sfui.common.set_cooldown_panels(panels)
    else
        -- If it exists but is empty, try to populate it now (handles early load race condition)
        local panel = panels[centerPanelIdx]
        if not panel.entries or #panel.entries == 0 then
            panel.entries = sfui.common.populate_center_panel_from_cdm()
            if #panel.entries > 0 then
                sfui.common.set_cooldown_panels(panels)
            end
        end
    end

    -- Auto-create UTILITY panel if it doesn't exist
    local utilityPanelIdx = nil
    for i, panel in ipairs(panels) do
        if panel.name == "UTILITY" then
            utilityPanelIdx = i
            break
        end
    end

    if not utilityPanelIdx then
        local utilityPanel = {
            name = "UTILITY",
            enabled = true,
            x = 0,
            y = 0,
            size = 32,
            columns = 9,
            spacing = 0,
            showBackground = false,
            backgroundAlpha = 0.5,
            placement = "center",
            anchor = "top",
            anchorTo = "CENTER",
            growthV = "Down",
            growthH = "Center", -- Default to Center growth
            entries = sfui.common.populate_utility_panel_from_cdm()
        }
        -- Insert after CENTER if possible, or just append
        local insertPos = centerPanelIdx and (centerPanelIdx + 1) or (#panels + 1)
        table.insert(panels, insertPos, utilityPanel)
        sfui.common.set_cooldown_panels(panels)
    else
        -- Populate if empty
        local panel = panels[utilityPanelIdx]
        if not panel.entries or #panel.entries == 0 then
            panel.entries = sfui.common.populate_utility_panel_from_cdm()
            if #panel.entries > 0 then
                sfui.common.set_cooldown_panels(panels)
            end
        end
    end

    return panels
end

-- Set panels for current spec
function sfui.common.set_cooldown_panels(panels)
    local specID = sfui.common.get_current_spec_id()
    if not specID or specID == 0 then return end

    SfuiDB.cooldownPanelsBySpec = SfuiDB.cooldownPanelsBySpec or {}
    SfuiDB.cooldownPanelsBySpec[specID] = panels
end

-- Get panel at index for current spec
function sfui.common.get_cooldown_panel(index)
    local panels = sfui.common.get_cooldown_panels()
    return panels[index]
end

-- Backwards compatibility wrapper - now returns per-spec panels
function sfui.common.ensure_tracked_icon_db()
    return sfui.common.get_cooldown_panels()
end

local powerTypeToName = {}
for name, value in pairs(Enum.PowerType) do
    powerTypeToName[value] = name
end

local primaryResourcesCache = {
    DEATHKNIGHT = Enum.PowerType.RunicPower,
    DEMONHUNTER = Enum.PowerType.Fury,
    DRUID = { [0] = Enum.PowerType.Mana, [1] = Enum.PowerType.Energy, [5] = Enum.PowerType.Rage, [27] = Enum.PowerType.Mana, [31] = Enum.PowerType.LunarPower },
    EVOKER = Enum.PowerType.Mana,
    HUNTER = Enum.PowerType.Focus,
    MAGE = Enum.PowerType.Mana,
    MONK = { [268] = Enum.PowerType.Energy, [270] = Enum.PowerType.Energy, [269] = Enum.PowerType.Mana },
    PALADIN = Enum.PowerType.Mana,
    PRIEST = { [256] = Enum.PowerType.Mana, [257] = Enum.PowerType.Mana, [258] = Enum.PowerType.Insanity },
    ROGUE = Enum.PowerType.Energy,
    SHAMAN = { [262] = Enum.PowerType.Maelstrom, [263] = Enum.PowerType.Mana, [264] = Enum.PowerType.Mana },
    WARLOCK = Enum.PowerType.Mana,
    WARRIOR = Enum.PowerType.Rage
}

local secondaryResourcesCache = {
    DEATHKNIGHT = Enum.PowerType.Runes,
    DEMONHUNTER = { [1480] = "DEVOURER_FRAGMENTS" },
    DRUID = { [1] = Enum.PowerType.ComboPoints, [31] = Enum.PowerType.Mana },
    EVOKER = Enum.PowerType.Essence,
    HUNTER = nil,
    MAGE = { [62] = Enum.PowerType.ArcaneCharges },
    MONK = { [268] = "STAGGER", [269] = Enum.PowerType.Chi, [270] = nil },
    PALADIN = Enum.PowerType.HolyPower,
    PRIEST = { [258] = Enum.PowerType.Mana },
    ROGUE = Enum.PowerType.ComboPoints,
    SHAMAN = { [262] = Enum.PowerType.Mana },
    WARLOCK = Enum.PowerType.SoulShards,
    WARRIOR = nil
}

local resourceColorsCache = {
    ["STAGGER"] = { r = 1, g = 0.5, b = 0 },
    ["SOUL_SHARDS"] = { r = 0.58, g = 0.51, b = 0.79 },
    ["RUNES"] = { r = 0.77, g = 0.12, b = 0.23 },
    ["ESSENCE"] = { r = 0.20, g = 0.58, b = 0.50 },
    ["COMBO_POINTS"] = { r = 1.00, g = 0.96, b = 0.41 },
    ["CHI"] = { r = 0.00, g = 1.00, b = 0.59 },
    ["HOLY_POWER"] = { r = 0.96, g = 0.91, b = 0.55 },
    ["ARCANE_CHARGES"] = { r = 0.6, g = 0.8, b = 1.0 },
}

local cachedSpecID = 0
local common_event_frame = CreateFrame("Frame")

local function update_cached_spec_id()
    local spec = C_SpecializationInfo.GetSpecialization()
    cachedSpecID = spec and select(1, C_SpecializationInfo.GetSpecializationInfo(spec)) or 0
end

common_event_frame:RegisterEvent("PLAYER_LOGIN")
common_event_frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
common_event_frame:RegisterEvent("PLAYER_TALENT_UPDATE")

common_event_frame:SetScript("OnEvent", function(self, event)
    update_cached_spec_id()
end)

function sfui.common.get_current_spec_id()
    if cachedSpecID == 0 then update_cached_spec_id() end
    return cachedSpecID
end

function sfui.common.update_widget_bar(widget_frame, icons_pool, labels_pool, source_data, get_details_func)
    if not widget_frame then return end
    local cfg = sfui.config.widget_bar
    local last_icon = nil
    local i = 1
    for _, itemID in ipairs(source_data) do
        local details = get_details_func(itemID)
        if details then
            local icon = icons_pool[i]
            if not icon then
                icon = CreateFrame("Button", nil, widget_frame)
                icon:SetSize(cfg.icon_size, cfg.icon_size)
                local texture = icon:CreateTexture(nil, "ARTWORK")
                texture:SetAllPoints(icon)
                icon.texture = texture
                icon:SetScript("OnEnter", details.on_enter)
                icon:SetScript("OnLeave", details.on_leave)
                icon:SetScript("OnMouseUp", details.on_mouseup)
                icons_pool[i] = icon
            end
            local label = labels_pool[i]
            if not label then
                label = widget_frame:CreateFontString(nil, "OVERLAY", sfui.config.font_small)
                label:SetPoint("TOP", icon, "BOTTOM", 0, cfg.label_offset_y)
                label:SetTextColor(cfg.label_color[1], cfg.label_color[2], cfg.label_color[3])
                labels_pool[i] = label
            end
            icon.id = itemID
            icon.texture:SetTexture(details.texture or sfui.config.textures.gold_icon)
            label:SetText(details.quantity)
            if i == 1 then
                icon:SetPoint("TOPLEFT", 5, -5)
            elseif last_icon then
                icon:SetPoint("TOPLEFT", last_icon, "TOPRIGHT", cfg.icon_spacing, 0)
            end
            icon:Show()
            label:Show()
            last_icon = icon
            i = i + 1
        end
    end
    for j = i, #icons_pool do icons_pool[j]:Hide() end
    for j = i, #labels_pool do labels_pool[j]:Hide() end
    if last_icon and not InCombatLockdown() then
        local left = widget_frame:GetLeft()
        if left then
            widget_frame:SetWidth(last_icon:GetRight() - left + 5)
        end
        if CharacterFrame:IsShown() then widget_frame:Show() end
    else
        widget_frame:Hide()
    end
end

function sfui.common.get_primary_resource()
    if playerClass == "DRUID" then return primaryResourcesCache[playerClass][GetShapeshiftFormID() or 0] end
    local cache = primaryResourcesCache[playerClass]
    if type(cache) == "table" then return cache[cachedSpecID] else return cache end
end

function sfui.common.get_secondary_resource()
    local res
    if playerClass == "DRUID" then
        res = secondaryResourcesCache[playerClass][GetShapeshiftFormID() or 0]
    else
        local cache = secondaryResourcesCache[playerClass]
        if type(cache) == "table" then
            res = cache[cachedSpecID]
        else
            res = cache
        end
    end

    if sfui.bars then
        sfui.bars.bar1_in_use = (res ~= nil)
    end
    return res
end

function sfui.common.get_class_or_spec_color()
    local color
    if cachedSpecID and sfui.config.spec_colors[cachedSpecID] then
        local custom_color = sfui.config.spec_colors[cachedSpecID]
        color = { r = custom_color.r, g = custom_color.g, b = custom_color.b }
    end
    if not color and playerClass then
        local classColor = C_ClassColor and C_ClassColor.GetClassColor(playerClass) or
            (RAID_CLASS_COLORS and RAID_CLASS_COLORS[playerClass])
        if classColor then
            color = { r = classColor.r, g = classColor.g, b = classColor.b }
        end
    end
    return color
end

function sfui.common.create_bar(name, frameType, parent, template, configName)
    local cfg = sfui.config[configName or name]
    local mult = sfui.pixelScale or 1
    local backdrop = CreateFrame("Frame", "sfui_" .. name .. "_Backdrop", parent, "BackdropTemplate")
    backdrop:SetFrameStrata("MEDIUM")
    local padding = cfg.backdrop.padding * mult
    backdrop:SetSize(cfg.width + padding * 2, cfg.height + padding * 2)

    backdrop:SetBackdrop({
        bgFile = sfui.config.textures.white,
        tile = true,
        tileSize = 32,
    })
    backdrop:SetBackdropColor(cfg.backdrop.color[1], cfg.backdrop.color[2], cfg.backdrop.color[3], cfg.backdrop.color[4])
    local bar = CreateFrame(frameType, "sfui_" .. name, backdrop, template)
    bar:SetSize(cfg.width, cfg.height)
    bar:SetPoint("CENTER")
    if bar.SetStatusBarTexture then
        local textureName = SfuiDB.barTexture
        local LSM = LibStub("LibSharedMedia-3.0", true)
        local texturePath
        if LSM then
            texturePath = LSM:Fetch("statusbar", textureName)
        end

        if not texturePath or texturePath == "" then
            texturePath = sfui.config.barTexture
        end
        bar:SetStatusBarTexture(texturePath)
    end
    bar.backdrop = backdrop
    bar.fadeInAnim, bar.fadeOutAnim = sfui.common.create_fade_animations(backdrop)
    return bar
end

function sfui.common.create_fade_animations(frame)
    local fadeInGroup = frame:CreateAnimationGroup()
    local fadeIn = fadeInGroup:CreateAnimation("Alpha")
    fadeIn:SetDuration(0.5)
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetScript("OnPlay", function() frame:Show() end)
    local fadeOutGroup = frame:CreateAnimationGroup()
    local fadeOut = fadeOutGroup:CreateAnimation("Alpha")
    fadeOut:SetDuration(0.5)
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetScript("OnFinished", function() frame:Hide() end)
    return fadeInGroup, fadeOutGroup
end

function sfui.common.get_resource_color(resource)
    local colorInfo = GetPowerBarColor(resource)
    if colorInfo then return colorInfo end
    local powerName = ""
    if type(resource) == "number" then
        powerName = powerTypeToName[resource]
    end
    return resourceColorsCache[powerName] or GetPowerBarColor("MANA")
end

function sfui.common.create_border(frame, thickness, color)
    local mult = sfui.pixelScale or 1
    thickness = (thickness or 1) * mult

    if not frame.borders then
        frame.borders = {}
        for i = 1, 4 do
            frame.borders[i] = frame:CreateTexture(nil, "BACKGROUND")
            frame.borders[i]:SetTexture("Interface\\Buttons\\WHITE8x8")
        end
    end

    local top, bottom, left, right = unpack(frame.borders)
    local r, g, b, a = 0, 0, 0, 1
    if color then r, g, b, a = unpack(color) end

    for _, border in ipairs(frame.borders) do
        border:SetVertexColor(r, g, b, a)
    end

    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0); top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0); top:SetHeight(
        thickness)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0); bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0); bottom
        :SetHeight(thickness)
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0); left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0); left
        :SetWidth(thickness)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0); right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0); right
        :SetWidth(thickness)
end

function sfui.common.create_flat_button(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)

    local mult = sfui.pixelScale or 1
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = mult,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    btn:SetBackdropColor(0, 0, 0, 1)
    local gray = sfui.config.colors.gray
    btn:SetBackdropBorderColor(gray[1], gray[2], gray[3], 1)

    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER")
    fs:SetText(text)
    local white = sfui.config.colors.white
    fs:SetTextColor(white[1], white[2], white[3], 1)
    btn:SetFontString(fs)

    local cyan = sfui.config.colors.cyan
    btn:SetScript("OnEnter", function(self)
        self:GetFontString():SetTextColor(cyan[1], cyan[2], cyan[3], 1)
        self:SetBackdropBorderColor(cyan[1], cyan[2], cyan[3], 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:GetFontString():SetTextColor(white[1], white[2], white[3], 1)
        self:SetBackdropBorderColor(gray[1], gray[2], gray[3], 1)
    end)

    return btn
end

function sfui.common.create_checkbox(parent, label, dbKeyOrGetter, onClickFunc, tooltip)
    local cb = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
    cb:SetSize(20, 20)

    -- Custom Backdrop
    cb:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    cb:SetBackdropColor(0.2, 0.2, 0.2, 1)
    cb:SetBackdropBorderColor(0, 0, 0, 1)

    -- Checked Texture (Purple)
    cb:SetCheckedTexture("Interface/Buttons/WHITE8X8")
    cb:GetCheckedTexture():SetVertexColor(0.4, 0, 1, 1)
    cb:GetCheckedTexture():SetPoint("TOPLEFT", 2, -2)
    cb:GetCheckedTexture():SetPoint("BOTTOMRIGHT", -2, 2)

    -- Highlight
    cb:SetHighlightTexture("Interface/Buttons/WHITE8X8")
    cb:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.1)

    -- Text
    cb.text = cb:CreateFontString(nil, "OVERLAY", sfui.config.font)
    cb.text:SetPoint("LEFT", cb, "RIGHT", 5, 0)
    cb.text:SetText(label)

    local function updateChecked()
        if type(dbKeyOrGetter) == "string" then
            if SfuiDB[dbKeyOrGetter] ~= nil then cb:SetChecked(SfuiDB[dbKeyOrGetter]) end
        elseif type(dbKeyOrGetter) == "function" then
            cb:SetChecked(dbKeyOrGetter())
        end
    end

    cb:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        if type(dbKeyOrGetter) == "string" then SfuiDB[dbKeyOrGetter] = checked end
        if onClickFunc then onClickFunc(checked) end
    end)
    cb:SetScript("OnShow", updateChecked)
    updateChecked() -- Initialize state immediately

    if tooltip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
    end
    return cb
end

function sfui.common.style_text(fs, fontObj, size, flags)
    if not fs then return end
    if fontObj then fs:SetFontObject(fontObj) end
    if size or flags then
        local font, curSize, curFlags = fs:GetFont()
        fs:SetFont(font, size or curSize, flags or "")
    end
    -- Standard Shadow
    fs:SetShadowOffset(0, 0)
    fs:SetTextColor(1, 1, 1, 1)
end

function sfui.common.create_color_swatch(parent, initialColor, onSetFunc)
    local swatch = CreateFrame("Button", nil, parent, "BackdropTemplate")
    swatch:SetSize(16, 16)

    swatch:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    swatch:SetBackdropBorderColor(0, 0, 0, 1)

    local function SetColor(r, g, b)
        swatch:SetBackdropColor(r, g, b, 1)
        if onSetFunc then onSetFunc(r, g, b) end
    end

    if initialColor then
        local r = initialColor.r or initialColor[1] or 0.4
        local g = initialColor.g or initialColor[2] or 0
        local b = initialColor.b or initialColor[3] or 1
        swatch:SetBackdropColor(r, g, b, 1)
    else
        swatch:SetBackdropColor(0.4, 0, 1, 1)
    end

    swatch:SetScript("OnClick", function()
        local r, g, b = swatch:GetBackdropColor()

        if ColorPickerFrame.SetupColorPickerAndShow then
            local info = {
                r = r,
                g = g,
                b = b,
                hasOpacity = false,
                swatchFunc = function()
                    local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                    SetColor(nr, ng, nb)
                end,
                cancelFunc = function() SetColor(r, g, b) end,
            }
            ColorPickerFrame:SetupColorPickerAndShow(info)
        else
            ColorPickerFrame:SetColorRGB(r, g, b)
            ColorPickerFrame.hasOpacity = false
            ColorPickerFrame.func = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                SetColor(nr, ng, nb)
            end
            ColorPickerFrame.cancelFunc = function() SetColor(r, g, b) end
            ColorPickerFrame:Hide()
            ColorPickerFrame:Show()
        end
    end)
    return swatch
end

function sfui.common.create_cvar_checkbox(parent, label, cvar, tooltip)
    return sfui.common.create_checkbox(parent, label, function()
        if SfuiDB[cvar] ~= nil then
            return SfuiDB[cvar]
        else
            return C_CVar.GetCVarBool(cvar)
        end
    end, function(checked)
        C_CVar.SetCVar(cvar, checked and "1" or "0")
        SfuiDB[cvar] = checked
    end, tooltip)
end

function sfui.common.create_slider_input(parent, label, dbKeyOrGetter, minVal, maxVal, step, onValueChangedFunc, width)
    local container = CreateFrame("Frame", nil, parent)
    local w = width or 160
    container:SetSize(w, 40) -- Compact height

    local title = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText(label)
    title:SetTextColor(1, 1, 1, 0.8)

    local slider = CreateFrame("Slider", nil, container, "BackdropTemplate")
    slider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    slider:SetSize(w - 60, 10) -- Dynamic width
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    -- Slider Backdrop
    slider:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    slider:SetBackdropColor(0.1, 0.1, 0.1, 1)
    slider:SetBackdropBorderColor(0, 0, 0, 1)

    -- Thumb
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(6, 10)
    thumb:SetColorTexture(0.4, 0, 1, 1)
    slider:SetThumbTexture(thumb)

    -- EditBox (Square, Flat, RIGHT of Slider)
    local editbox = CreateFrame("EditBox", nil, container, "BackdropTemplate")
    editbox:SetSize(45, 16)
    editbox:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    editbox:SetAutoFocus(false)
    editbox:SetFontObject("GameFontHighlightSmall")
    editbox:SetJustifyH("CENTER")

    editbox:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    editbox:SetBackdropColor(0.15, 0.15, 0.15, 1)
    editbox:SetBackdropBorderColor(0, 0, 0, 1)

    editbox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editbox:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then
            if val < minVal then val = minVal end
            if val > maxVal then val = maxVal end
            slider:SetValue(val)
            if type(dbKeyOrGetter) == "string" then SfuiDB[dbKeyOrGetter] = val end
            if onValueChangedFunc then onValueChangedFunc(val) end
        end
        self:ClearFocus()
    end)
    editbox:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(0.4, 0, 1, 1) end)
    editbox:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(0, 0, 0, 1) end)


    slider:SetScript("OnValueChanged", function(self, value)
        local stepped = math.floor((value - minVal) / step + 0.5) * step + minVal
        if type(dbKeyOrGetter) == "string" then SfuiDB[dbKeyOrGetter] = stepped end
        -- Clean number display
        local displayVal = math.floor(stepped * 100) / 100
        editbox:SetText(tostring(displayVal))
        if onValueChangedFunc then onValueChangedFunc(stepped) end
    end)

    slider:SetScript("OnShow", function(self)
        local val
        if type(dbKeyOrGetter) == "string" then
            val = SfuiDB[dbKeyOrGetter]
        elseif type(dbKeyOrGetter) == "function" then
            val = dbKeyOrGetter()
        end
        if val == nil then val = minVal end
        self:SetValue(val)
        editbox:SetText(math.floor(val * 100) / 100)
    end)

    -- Expose method to set value programmatically
    function container:SetSliderValue(val)
        slider:SetValue(val)
        editbox:SetText(tostring(val))
    end

    return container
end

function sfui.common.set_color(element, colorName, alpha)
    local color = sfui.config.colors[colorName]
    if not color then return end
    alpha = alpha or 1

    if element.SetTextColor then
        element:SetTextColor(color[1], color[2], color[3], alpha)
    elseif element.SetBackdropBorderColor then
        element:SetBackdropBorderColor(color[1], color[2], color[3], alpha)
    elseif element.SetBackdropColor then
        element:SetBackdropColor(color[1], color[2], color[3], alpha)
    end
end

function sfui.common.create_font_string(parent, font, point, x, y, colorName)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    if point then
        fs:SetPoint(point, x or 0, y or 0)
    end
    if colorName then
        sfui.common.set_color(fs, colorName)
    end
    return fs
end

function sfui.common.is_item_known(itemLink)
    if not itemLink then return false end

    local data = C_TooltipInfo.GetHyperlink(itemLink)
    if data and data.lines then
        for _, line in ipairs(data.lines) do
            local text = line.leftText
            if text then
                if text == ITEM_SPELL_KNOWN or text == "Already known" then
                    return true
                end
                if string.find(text, "You've collected this appearance") then
                    return true
                end
            end
        end
    end

    local itemID = tonumber(string.match(itemLink, "item:(%d+)"))
    if itemID then
        local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(itemID)
        if sourceID then
            local categoryID, visualID, canEnchant, icon, isCollected = C_TransmogCollection.GetAppearanceSourceInfo(
                sourceID)
            if isCollected then
                return true
            end
        end

        if C_ToyBox and C_ToyBox.GetToyInfo then
            local toyID = C_ToyBox.GetToyInfo(itemID)
            if toyID and PlayerHasToy(itemID) then return true end
        end
    end

    return false
end

function sfui.common.shorten_name(name, length)
    if not name or type(name) ~= "string" then return "" end
    length = length or 25
    if strlenutf8(name) <= length then return name end
    return strsub(name, 1, length - 3) .. "..."
end

function sfui.common.get_masque_group(subGroupName)
    local Masque = LibStub and LibStub("Masque", true)
    if not Masque then return nil end
    return Masque:Group("sfui", subGroupName)
end

-- ========================
-- Player & Group Utilities
-- ========================

-- (get_player_class removed, used at top)

-- Returns a table of unit IDs for all group members (including player)
-- Returns {"player"} if not in a group
function sfui.common.get_group_units()
    local units = {}
    if not IsInGroup() then
        return { "player" }
    end

    local numMembers = GetNumGroupMembers()
    local isRaid = IsInRaid()

    if isRaid then
        for i = 1, numMembers do
            table.insert(units, "raid" .. i)
        end
    else
        table.insert(units, "player")
        for i = 1, numMembers - 1 do
            table.insert(units, "party" .. i)
        end
    end

    return units
end

-- Checks if a specific class is present in the current group
-- @param className: The class to check for (e.g., "WARRIOR", "PRIEST")
-- @return: true if the class is present, false otherwise
function sfui.common.is_class_in_group(className)
    if playerClass == className then return true end
    if not IsInGroup() then return false end

    for _, unit in ipairs(sfui.common.get_group_units()) do
        if UnitExists(unit) then
            local _, class = UnitClass(unit)
            if class == className then return true end
        end
    end
    return false
end

-- Checks if a unit has a specific aura (buff)
-- @param spellID: The spell ID to check for
-- @param unit: The unit ID to check (default: "player")
-- @param threshold: (Optional) Only return true if duration remaining > threshold (seconds). Pass explicit nil or 0 to ignore.
-- @return: true if cached, false otherwise
function sfui.common.has_aura(spellID, unit, threshold)
    unit = unit or "player"
    local spellName
    if C_Spell and C_Spell.GetSpellName then
        spellName = C_Spell.GetSpellName(spellID)
    elseif GetSpellInfo then
        spellName = GetSpellInfo(spellID)
    end

    if spellName then
        local aura = C_UnitAuras.GetAuraDataBySpellName(unit, spellName)
        if aura then
            if not threshold or not sfui.common.IsNumericAndPositive(threshold) then return true end
            if issecretvalue(aura.expirationTime) then return true end
            return sfui.common.SafeGT(aura.expirationTime - GetTime(), threshold)
        end
    end

    return false
end

-- ========================
-- Item Utilities
-- ========================

-- Checks if an item link corresponds to a housing decor item
function sfui.common.is_housing_decor(link)
    local itemID = sfui.common.get_item_id_from_link(link)
    if itemID and C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByItem then
        local info = C_HousingCatalog.GetCatalogEntryInfoByItem(itemID, false)
        return info and info.entryID and info.entryID.entryType == 1
    end
    return false
end

-- Extracts the item ID from an item link
-- @param link: Item link string (e.g., "|cff0070dd|Hitem:12345:0:0:0|h[Item Name]|h|r")
-- @return: Item ID as a number, or nil if not found
function sfui.common.get_item_id_from_link(link)
    if not link then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- ========================
-- Utility Helpers
-- ========================

-- Scans player auras (buffs) and applies a filter function
-- @param filterFunc: Function that receives aura data and returns true to include
-- @return: true if any matching aura found, false otherwise
function sfui.common.scan_player_auras(filterFunc)
    if not filterFunc then return false end

    -- Scanning all auras is unsafe in instances due to secret values
    local inInstance, instanceType = IsInInstance()
    if inInstance and (instanceType == "party" or instanceType == "raid" or instanceType == "arena") then
        return false
    end

    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        if filterFunc(aura) then
            return true
        end
    end
    return false
end

-- Creates a styled button consistent with sfui design
-- @param parent: Parent frame
-- @param text: Button text
-- @param width: Button width
-- @param height: Button height
-- @return: Button frame
function sfui.common.create_styled_button(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 120, height or 25)
    btn:SetBackdrop({
        bgFile = sfui.config.textures.white,
        edgeFile = sfui.config.textures.white,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    btn:SetBackdropColor(0.2, 0.2, 0.2, 1)
    btn:SetBackdropBorderColor(0, 0, 0, 1)

    -- Hover effect
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(sfui.config.colors.purple[1], sfui.config.colors.purple[2],
            sfui.config.colors.purple[3], 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0, 0, 0, 1)
    end)

    -- Text
    btn.text = btn:CreateFontString(nil, "OVERLAY", sfui.config.font)
    btn.text:SetPoint("CENTER")
    btn.text:SetText(text or "")
    sfui.common.style_text(btn.text)

    return btn
end

-- Vehicle action bar keybind text map
sfui.common.VEHICLE_KEYBIND_MAP = {
    [10] = "0",
    [11] = "-",
    [12] = "="
}

-- Moved from config.lua to clean up that file
function sfui.initialize_database()
    if type(SfuiDB) ~= "table" then SfuiDB = {} end
    if type(SfuiDecorDB) ~= "table" then SfuiDecorDB = {} end
    SfuiDecorDB.items = SfuiDecorDB.items or {}

    if type(SfuiDB.barTexture) ~= "string" or SfuiDB.barTexture == "" then SfuiDB.barTexture = "Flat" end
    SfuiDB.absorbBarColor = SfuiDB.absorbBarColor or sfui.config.absorbBarColor

    SfuiDB.minimap_icon = SfuiDB.minimap_icon or { hide = false }
    SfuiDB.minimap_collect_buttons = (SfuiDB.minimap_collect_buttons == nil) and true or SfuiDB.minimap_collect_buttons
    if SfuiDB.minimap_rearrange == nil then SfuiDB.minimap_rearrange = true end
    SfuiDB.minimap_buttons_mouseover = (SfuiDB.minimap_buttons_mouseover == nil) and false or
        SfuiDB.minimap_buttons_mouseover
    if SfuiDB.minimap_masque == nil then SfuiDB.minimap_masque = true end
    if SfuiDB.minimap_button_x == nil then SfuiDB.minimap_button_x = 0 end
    if SfuiDB.minimap_button_y == nil then SfuiDB.minimap_button_y = 35 end
    if SfuiDB.autoSellGreys == nil then SfuiDB.autoSellGreys = true end
    if SfuiDB.autoRepair == nil then SfuiDB.autoRepair = true end
    if SfuiDB.repairThreshold == nil then SfuiDB.repairThreshold = 90 end
    if SfuiDB.enableMasterHammer == nil then SfuiDB.enableMasterHammer = true end
    if SfuiDB.enableMerchant == nil then SfuiDB.enableMerchant = true end
    if SfuiDB.enableDecor == nil then SfuiDB.enableDecor = false end -- Opt-in feature
    if SfuiDB.enableVehicle == nil then SfuiDB.enableVehicle = true end
    if SfuiDB.enableCursorRing == nil then SfuiDB.enableCursorRing = true end

    -- Bar settings
    if SfuiDB.healthBarX == nil then SfuiDB.healthBarX = 0 end
    if SfuiDB.healthBarY == nil then SfuiDB.healthBarY = 300 end
    if SfuiDB.enableHealthBar == nil then SfuiDB.enableHealthBar = true end
    if SfuiDB.enablePowerBar == nil then SfuiDB.enablePowerBar = true end
    if SfuiDB.enableSecondaryPowerBar == nil then SfuiDB.enableSecondaryPowerBar = true end
    if SfuiDB.enableVigorBar == nil then SfuiDB.enableVigorBar = true end
    if SfuiDB.enableMountSpeedBar == nil then SfuiDB.enableMountSpeedBar = true end

    -- Castbar settings
    if SfuiDB.castBarEnabled == nil then SfuiDB.castBarEnabled = sfui.config.castBar.enabled end
    if SfuiDB.castBarX == nil then SfuiDB.castBarX = sfui.config.castBar.pos.x end
    if SfuiDB.castBarY == nil then SfuiDB.castBarY = sfui.config.castBar.pos.y end
    sfui.config.castBar.enabled = SfuiDB.castBarEnabled
    sfui.config.castBar.pos.x = SfuiDB.castBarX
    sfui.config.castBar.pos.y = SfuiDB.castBarY

    if SfuiDB.targetCastBarEnabled == nil then SfuiDB.targetCastBarEnabled = sfui.config.targetCastBar.enabled end
    if SfuiDB.targetCastBarX == nil then SfuiDB.targetCastBarX = sfui.config.targetCastBar.pos.x end
    if SfuiDB.targetCastBarY == nil then SfuiDB.targetCastBarY = sfui.config.targetCastBar.pos.y end
    sfui.config.targetCastBar.enabled = SfuiDB.targetCastBarEnabled
    sfui.config.targetCastBar.pos.x = SfuiDB.targetCastBarX
    sfui.config.targetCastBar.pos.y = SfuiDB.targetCastBarY

    if SfuiDB.enableReminders == nil then SfuiDB.enableReminders = true end
    if SfuiDB.remindersX == nil then SfuiDB.remindersX = 0 end
    if SfuiDB.remindersY == nil then SfuiDB.remindersY = 10 end
    if SfuiDB.remindersSolo == nil then SfuiDB.remindersSolo = true end
    if SfuiDB.enableConsumablesSolo == nil then SfuiDB.enableConsumablesSolo = true end
    if SfuiDB.remindersEverywhere == nil then SfuiDB.remindersEverywhere = true end
    if SfuiDB.enablePetWarning == nil then SfuiDB.enablePetWarning = true end
    if SfuiDB.enableRuneWarning == nil then SfuiDB.enableRuneWarning = true end

    -- automation settings
    if SfuiDB.auto_role_check == nil then SfuiDB.auto_role_check = true end
    if SfuiDB.auto_sign_lfg == nil then SfuiDB.auto_sign_lfg = true end

    -- Tracked Bars
    SfuiDB.trackedBars = SfuiDB.trackedBars or {}
    if SfuiDB.trackedBarsX == nil then SfuiDB.trackedBarsX = -300 end
    if SfuiDB.trackedBarsY == nil then SfuiDB.trackedBarsY = 300 end
end

-- Helper to systematically hide specific Blizzard CooldownViewer frames
function sfui.common.hide_blizzard_cooldown_viewers()
    -- Ensure the addon is loaded first
    if not C_AddOns.IsAddOnLoaded("Blizzard_CooldownViewer") then
        C_AddOns.LoadAddOn("Blizzard_CooldownViewer")
    end

    local viewers = {
        "EssentialCooldownViewer",
        "UtilityCooldownViewer",
    }

    for _, viewerName in ipairs(viewers) do
        local viewer = _G[viewerName]
        if viewer then
            viewer:SetAlpha(0)
            viewer:EnableMouse(false)
            viewer:Hide()
            viewer:UnregisterAllEvents()

            if not viewer._sfui_hooked then
                hooksecurefunc(viewer, "Show", function(self)
                    self:SetAlpha(0)
                    self:EnableMouse(false)
                    self:Hide()
                end)
                viewer._sfui_hooked = true
            end
        end
    end
    -- Ensure the CVar is set to 1 so Blizzard's internal data systems are active.
    -- We hide the frames visually, but we need the data provider to function.
    if GetCVar("cooldownViewerEnabled") == "0" then
        SetCVar("cooldownViewerEnabled", 1)
    end
end
