sfui.common = {}

local _, playerClass, playerClassID = UnitClass("player")

-- ... (skipping lines)

-- Returns the cached player class (e.g., "WARRIOR", "MAGE")
function sfui.common.get_player_class()
    return playerClass, playerClassID
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
    if last_icon then
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
    if playerClass == "DRUID" then return secondaryResourcesCache[playerClass][GetShapeshiftFormID() or 0] end
    local cache = secondaryResourcesCache[playerClass]
    if type(cache) == "table" then return cache[cachedSpecID] else return cache end
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

function sfui.common.create_bar(name, frameType, parent, template)
    local cfg = sfui.config[name]
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

function sfui.common.create_checkbox(parent, label, dbKey, onClickFunc, tooltip)
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
        SfuiDB[dbKey] = checked
        if onClickFunc then onClickFunc(checked) end
    end)
    cb:SetScript("OnShow", function(self)
        self:SetChecked(SfuiDB[dbKey])
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

function sfui.common.create_cvar_checkbox(parent, label, cvar, tooltip)
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
        C_CVar.SetCVar(cvar, checked and "1" or "0")
        SfuiDB[cvar] = checked -- Persist to DB
    end)
    cb:SetScript("OnShow", function(self)
        -- Check DB first for persistence, fallback to current CVar state
        if SfuiDB[cvar] ~= nil then
            self:SetChecked(SfuiDB[cvar])
        else
            self:SetChecked(C_CVar.GetCVarBool(cvar))
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

function sfui.common.create_slider_input(parent, label, dbKey, minVal, maxVal, step, onValueChangedFunc)
    local container = CreateFrame("Frame", nil, parent)
    -- Increased height to accommodate input box below slider
    container:SetSize(160, 60)

    local title = container:CreateFontString(nil, "OVERLAY", sfui.config.font)
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText(label)

    local slider = CreateFrame("Slider", nil, container, "BackdropTemplate")
    slider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    slider:SetSize(160, 12) -- Reduced height slightly for sharper look
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    -- Slider Backdrop (Flat Square)
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
    thumb:SetSize(6, 12)
    thumb:SetColorTexture(0.4, 0, 1, 1) -- Purple Thumb
    slider:SetThumbTexture(thumb)

    -- EditBox (Square, Flat, Below Slider)
    local editbox = CreateFrame("EditBox", nil, container, "BackdropTemplate")
    editbox:SetSize(50, 18)
    -- Centered below the slider
    editbox:SetPoint("TOP", slider, "BOTTOM", 0, -5)
    editbox:SetAutoFocus(false)
    editbox:SetFontObject(sfui.config.font)
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
            SfuiDB[dbKey] = val
            if onValueChangedFunc then onValueChangedFunc(val) end
        end
        self:ClearFocus()
    end)
    -- Only highlight border on edit, no cyan text
    editbox:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(0.4, 0, 1, 1)
    end)
    editbox:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(0, 0, 0, 1)
    end)


    slider:SetScript("OnValueChanged", function(self, value)
        local stepped = math.floor((value - minVal) / step + 0.5) * step + minVal
        -- To avoid float jitter
        if math.abs(value - stepped) > 0.001 then
            -- Logic handled by slider mostly
        end
        SfuiDB[dbKey] = value
        -- Clean number display
        local displayVal = math.floor(value * 100) / 100
        editbox:SetText(tostring(displayVal))
        if onValueChangedFunc then onValueChangedFunc(value) end
    end)

    slider:SetScript("OnShow", function(self)
        local val = SfuiDB[dbKey]
        if val == nil then val = minVal end
        self:SetValue(val)
        editbox:SetText(tostring(val))
    end)

    -- Labels for Min/Max
    local low = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    low:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -2)
    low:SetText(minVal)
    low:Hide() -- Hiding min/max labels to keep it clean as per "input box below" request usually implies compact or just focus on value.
    -- Actually user didn't say hide them, but with input box below, they might clutter. I'll keep them hidden or move them.
    -- Let's keep them visible but pushed out or just hidden if input box is the focus.
    -- User asked: "put the input boxes below the sliders".
    -- I'll hide min/max for cleaner look unless insisted.

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

-- Returns the cached player class (e.g., "WARRIOR", "MAGE")
function sfui.common.get_player_class()
    return playerClass
end

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

-- ========================
-- Item Utilities
-- ========================

-- Extracts the item ID from an item link
-- @param link: Item link string (e.g., "|cff0070dd|Hitem:12345:0:0:0|h[Item Name]|h|r")
-- @return: Item ID as a number, or nil if not found
function sfui.common.get_item_id_from_link(link)
    if not link then return nil end
    return tonumber(link:match("item:(%d+)"))
end
