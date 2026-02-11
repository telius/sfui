local addonName, addon = ...
sfui = sfui or {}
sfui.common = {}


-- Internal helper to detect restricted data in Mythic+
-- Comparing "Secret Values" to anything (including themselves) throws a Lua error.
-- WoW 11.x+ has a built-in issecretvalue global; we use it if present.
local function issecretvalue(val)
    if _G.issecretvalue then return _G.issecretvalue(val) end
    if val == nil then return false end
    local success = pcall(function() return val == val end)
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

-- Safe numeric comparison (ArcUI pattern)
function sfui.common.IsNumericAndPositive(value)
    if value == nil then return false end
    local ok, result = pcall(function() return type(value) == "number" and value > 0 end)
    return ok and result
end

-- Safe duration formatting (ArcUI pattern)
function sfui.common.SafeFormatDuration(value, decimals)
    if value == nil then return "" end
    -- Default to 0 decimals for clean counts (e.g. "5" instead of "5.0")
    decimals = decimals or 0
    local ok, formatted = pcall(function()
        local num = tonumber(value)
        if num then return string.format("%." .. decimals .. "f", num) end
        return value
    end)
    return ok and formatted or value
end

-- Safe helper to get a duration object for a spell (nil check is non-secret)
function sfui.common.GetCooldownDurationObj(spellID)
    if not spellID then return nil end
    local obj
    if C_Spell.GetSpellChargeDuration then
        pcall(function() obj = C_Spell.GetSpellChargeDuration(spellID) end)
    end
    if not obj and C_Spell.GetSpellCooldownDuration then
        pcall(function() obj = C_Spell.GetSpellCooldownDuration(spellID) end)
    end
    if issecretvalue(obj) then return nil end
    return obj
end

-- Safe comparison helpers (Crash-proof against Secret Values in M+)
function sfui.common.SafeGT(val, target)
    if val == nil then return false end
    if issecretvalue(val) then return true end -- Secret = exists/active
    local ok, result = pcall(function() return val > (target or 0) end)
    return ok and result
end

function sfui.common.SafeValue(val, fallback)
    if val == nil then return fallback end
    if issecretvalue(val) then return val end
    local ok, result = pcall(function() return val end)
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

-- Helper to safely ensure tracked icon DB structure exists
function sfui.common.ensure_tracked_icon_db()
    SfuiDB = SfuiDB or {}
    SfuiDB.cooldownPanels = SfuiDB.cooldownPanels or {}
    return SfuiDB.cooldownPanels
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

    cb:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        if type(dbKeyOrGetter) == "string" then SfuiDB[dbKeyOrGetter] = checked end
        if onClickFunc then onClickFunc(checked) end
    end)
    cb:SetScript("OnShow", function(self)
        if type(dbKeyOrGetter) == "string" then
            if SfuiDB[dbKeyOrGetter] ~= nil then self:SetChecked(SfuiDB[dbKeyOrGetter]) end
        elseif type(dbKeyOrGetter) == "function" then
            self:SetChecked(dbKeyOrGetter())
        end
    end)

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

function sfui.common.create_slider_input(parent, label, dbKeyOrGetter, minVal, maxVal, step, onValueChangedFunc)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(160, 40) -- Compact height

    local title = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText(label)
    title:SetTextColor(1, 1, 1, 0.8)

    local slider = CreateFrame("Slider", nil, container, "BackdropTemplate")
    slider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    slider:SetSize(100, 10) -- Smaller width
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
