local addonName, addon = ...
sfui.trackedoptions = {}

local frame
local scrollFrame
local content
local c = sfui.config.options_panel
local g = sfui.config

local GROUP_NAMES = {
    [0] = "Essential",
    [1] = "Utility Cooldowns",
    [2] = "Tracked Buffs",
    [3] = "Tracked Bars",
    [-1] = "Disabled Cooldowns",
    [-2] = "Disabled Buffs",
    [-3] = "Unknown / Not Learned"
}

local function CreateCustomCheckbox(parent, xPos, label, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
    cb:SetSize(20, 20)
    cb:SetPoint("LEFT", parent, "LEFT", xPos, 0)

    cb:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    cb:SetBackdropColor(0.2, 0.2, 0.2, 1)
    cb:SetBackdropBorderColor(0, 0, 0, 1)

    cb:SetCheckedTexture("Interface/Buttons/WHITE8X8")
    cb:GetCheckedTexture():SetVertexColor(0.4, 0, 1, 1)
    cb:GetCheckedTexture():SetPoint("TOPLEFT", 2, -2)
    cb:GetCheckedTexture():SetPoint("BOTTOMRIGHT", -2, 2)

    cb:SetHighlightTexture("Interface/Buttons/WHITE8X8")
    cb:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.1)

    if label then
        cb.text = cb:CreateFontString(nil, "OVERLAY", g.font or "GameFontHighlightSmall")
        cb.text:SetPoint("LEFT", cb, "RIGHT", 5, 0)
        cb.text:SetText(label)
        cb.text:SetTextColor(1, 1, 1, 1)
    end

    cb:SetScript("OnClick", function(self)
        if onClick then onClick(self:GetChecked()) end
    end)
    return cb
end

local function CreateCooldownsFrame()
    if frame then return end

    local CreateFlatButton = sfui.common.create_flat_button
    local create_slider_input = sfui.common.create_slider_input

    frame = CreateFrame("Frame", "SfuiCooldownsViewer", UIParent, "BackdropTemplate")
    frame:SetSize(600, 500)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    -- Apply SFUI aesthetics
    frame:SetBackdrop({ bgFile = g.textures.white, tile = true, tileSize = 32 })
    frame:SetBackdropColor(c.backdrop_color.r, c.backdrop_color.g, c.backdrop_color.b, c.backdrop_color.a)

    -- Close Button
    local close_button = CreateFlatButton(frame, "X", 24, 24)
    close_button:SetPoint("TOPRIGHT", -5, -5)
    close_button:SetScript("OnClick", function()
        frame:Hide()
    end)

    -- Title
    local header_text = frame:CreateFontString(nil, "OVERLAY", g.font_large)
    header_text:SetPoint("TOP", frame, "TOP", 0, -10)
    header_text:SetTextColor(g.header_color[1], g.header_color[2], g.header_color[3])
    header_text:SetText("tracking manager")

    -- Position Controls
    local pos_header = frame:CreateFontString(nil, "OVERLAY", g.font)
    pos_header:SetPoint("TOPLEFT", 15, -40)
    pos_header:SetTextColor(1, 1, 1)
    pos_header:SetText("tracking frame position")

    local slider_x = create_slider_input(frame, "x:", "trackedBarsX", -1000, 1000, 1, function(val)
        if sfui.trackedbars and sfui.trackedbars.UpdatePosition then
            sfui.trackedbars.UpdatePosition()
        end
    end)
    slider_x:SetPoint("TOPLEFT", pos_header, "BOTTOMLEFT", 0, -15)

    local slider_y = create_slider_input(frame, "y:", "trackedBarsY", -1000, 1000, 1, function(val)
        if sfui.trackedbars and sfui.trackedbars.UpdatePosition then
            sfui.trackedbars.UpdatePosition()
        end
    end)
    slider_y:SetPoint("LEFT", slider_x, "RIGHT", 10, 0)

    -- Global Frame Options (Blizzard Mirror)
    local global_header = frame:CreateFontString(nil, "OVERLAY", g.font)
    global_header:SetPoint("TOPLEFT", slider_x, "BOTTOMLEFT", 0, -20)
    global_header:SetTextColor(1, 1, 1)
    global_header:SetText("visibility")

    -- Helper: Update visibility setting and sync with Blizzard API
    local function UpdateVisibility(key, val, syncBlizzard)
        SfuiDB = SfuiDB or {}
        SfuiDB[key] = val

        if syncBlizzard and BuffBarCooldownViewer and BuffBarCooldownViewer.SetHideWhenInactive then
            BuffBarCooldownViewer:SetHideWhenInactive(val)
        end

        if sfui.trackedbars and sfui.trackedbars.UpdateVisibility then
            sfui.trackedbars.UpdateVisibility()
        end
    end

    -- Checkbox: Hide Out of Combat
    local chk_ooc = CreateCustomCheckbox(frame, 15, "hide out of combat", function(val)
        UpdateVisibility("hideOOC", val)
    end)
    chk_ooc:SetPoint("TOPLEFT", global_header, "BOTTOMLEFT", 0, -10)
    chk_ooc:SetChecked(SfuiDB and SfuiDB.hideOOC or false)

    -- Checkbox: Hide When Inactive
    local chk_inactive = CreateCustomCheckbox(frame, 150, "hide when inactive", function(val)
        UpdateVisibility("hideInactive", val, true)
    end)
    chk_inactive:SetPoint("LEFT", chk_ooc, "RIGHT", 200, 0)

    -- Initialize from SfuiDB or Blizzard API
    local inactiveState = true
    if SfuiDB and SfuiDB.hideInactive ~= nil then
        inactiveState = SfuiDB.hideInactive
    elseif BuffBarCooldownViewer and BuffBarCooldownViewer.GetHideWhenInactive then
        inactiveState = BuffBarCooldownViewer:GetHideWhenInactive()
    end
    chk_inactive:SetChecked(inactiveState)

    -- Table Header for cooldown list
    local tableHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    tableHeader:SetPoint("TOPLEFT", chk_ooc, "BOTTOMLEFT", 0, -20)
    tableHeader:SetTextColor(0.8, 0.8, 0.8)
    tableHeader:SetText("tracked cooldowns")

    -- Column Headers
    local colHeader = CreateFrame("Frame", nil, frame)
    colHeader:SetSize(600, 20)
    colHeader:SetPoint("TOPLEFT", tableHeader, "BOTTOMLEFT", 0, -5)

    local col1 = colHeader:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    col1:SetPoint("LEFT", 30, 0)
    col1:SetTextColor(0.7, 0.7, 0.7)
    col1:SetText("ability")

    local col2 = colHeader:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    col2:SetPoint("LEFT", 300, 0)
    col2:SetTextColor(0.7, 0.7, 0.7)
    col2:SetText("attach")

    local col3 = colHeader:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    col3:SetPoint("LEFT", 500, 0)
    col3:SetTextColor(0.7, 0.7, 0.7)
    col3:SetText("color")

    -- Content Frame (Direct child, no scrollbar)
    content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", colHeader, "BOTTOMLEFT", 0, -5)
    content:SetPoint("BOTTOMRIGHT", -10, 10)
end

local function CreateColorSwatch(parent, xPos, initialColor, onSet)
    local swatch = CreateFrame("Button", nil, parent, "BackdropTemplate")
    swatch:SetSize(16, 16)
    swatch:SetPoint("LEFT", parent, "LEFT", xPos, 0)
    swatch:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    swatch:SetBackdropBorderColor(0, 0, 0, 1)

    local function SetColor(r, g, b)
        swatch:SetBackdropColor(r, g, b, 1)
        if onSet then onSet(r, g, b) end
    end

    if initialColor then
        swatch:SetBackdropColor(initialColor.r or initialColor[1], initialColor.g or initialColor[2],
            initialColor.b or initialColor[3], 1)
    else
        swatch:SetBackdropColor(0.4, 0, 1, 1) -- Default Purple
    end

    swatch:SetScript("OnClick", function()
        local r, g, b = swatch:GetBackdropColor()

        -- ColorPickerFrame Setup
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
                cancelFunc = function()
                    SetColor(r, g, b)
                end,
            }
            ColorPickerFrame:SetupColorPickerAndShow(info)
        else
            -- Fallback
            ColorPickerFrame:SetColorRGB(r, g, b)
            ColorPickerFrame.hasOpacity = false
            ColorPickerFrame.func = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                SetColor(nr, ng, nb)
            end
            ColorPickerFrame.cancelFunc = function()
                SetColor(r, g, b)
            end
            ColorPickerFrame:Hide()
            ColorPickerFrame:Show()
        end
    end)
    return swatch
end

local function UpdateCooldownsList()
    if not frame then return end

    -- Clear previous content
    for _, child in ipairs({ content:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
    end

    if not CooldownViewerSettings then
        if C_AddOns.LoadAddOn("Blizzard_CooldownViewer") then
            -- Try to show it if global is still missing
        else
            local text = content:CreateFontString(nil, "ARTWORK")
            text:SetFontObject(g.font)
            text:SetPoint("TOPLEFT", 10, -10)
            text:SetText("Blizzard_CooldownViewer addon not found or failed to load.")
            return
        end
    end

    if not CooldownViewerSettings then
        local text = content:CreateFontString(nil, "ARTWORK")
        text:SetFontObject(g.font)
        text:SetPoint("TOPLEFT", 10, -10)
        text:SetText("CooldownViewerSettings global not found.")
        return
    end

    if not sfui.trackedoptions.hookInstalled then
        hooksecurefunc(CooldownViewerSettings, "RefreshLayout", function()
            if frame and frame:IsShown() then
                UpdateCooldownsList()
            end
        end)
        sfui.trackedoptions.hookInstalled = true
    end

    local dataProvider = CooldownViewerSettings:GetDataProvider()
    if not dataProvider then return end

    local cooldownIDs = dataProvider:GetOrderedCooldownIDs()
    local groupedCooldowns = {}

    for _, cooldownID in ipairs(cooldownIDs) do
        local info = dataProvider:GetCooldownInfoForID(cooldownID)
        if info then
            local groupID = info.category or 0
            if not groupedCooldowns[groupID] then
                groupedCooldowns[groupID] = {}
            end

            -- Determine effective SpellID (Override > Base)
            local effectiveSpellID = info.overrideTooltipSpellID or info.overrideSpellID or info.spellID

            local iconTexture
            if effectiveSpellID then
                iconTexture = C_Spell.GetSpellTexture(effectiveSpellID)
            end

            table.insert(groupedCooldowns[groupID], {
                cooldownID = cooldownID,
                spellID = info.spellID,
                effectiveSpellID = effectiveSpellID,
                overrideSpellID = info.overrideSpellID,
                overrideTooltipSpellID = info.overrideTooltipSpellID,
                linkedSpellID = info.linkedSpellID,
                linkedSpellIDs = info.linkedSpellIDs,
                isKnown = info.isKnown,
                name = C_Spell.GetSpellName(effectiveSpellID or 0) or "Unknown",
                icon = iconTexture
            })
        end
    end

    local yOffset = -10
    local sortedGroups = {}
    for groupID in pairs(groupedCooldowns) do
        -- Only show Tracked Bars (Group 3)
        if groupID == 3 then
            table.insert(sortedGroups, groupID)
        end
    end
    table.sort(sortedGroups, function(a, b)
        if a == 3 then return true end
        if b == 3 then return false end
        return a < b
    end)

    for _, groupID in ipairs(sortedGroups) do
        -- No Group Header Title logic needed as per user request
        for _, cd in ipairs(groupedCooldowns[groupID]) do
            local row = CreateFrame("Frame", nil, content)
            row:SetSize(580, 24)
            row:SetPoint("TOPLEFT", 10, yOffset)

            -- Icon Button (for Tooltip)
            local iconButton = CreateFrame("Button", nil, row)
            iconButton:SetSize(20, 20)
            iconButton:SetPoint("LEFT", 0, 0)

            local icon = iconButton:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            if cd.icon then
                icon:SetTexture(cd.icon)
            else
                icon:SetColorTexture(0.3, 0.3, 0.3, 0.5)
            end
            if not cd.isKnown then icon:SetDesaturated(true) end

            iconButton:SetScript("OnEnter", function(self)
                if cd.effectiveSpellID then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetSpellByID(cd.effectiveSpellID)
                    GameTooltip:Show()
                end
            end)
            iconButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

            -- Spell Name (Left Aligned)
            local nameText = row:CreateFontString(nil, "ARTWORK")
            nameText:SetFontObject(g.font)
            nameText:SetPoint("LEFT", iconButton, "RIGHT", 10, 0)
            nameText:SetWidth(270) -- Restore width to 270
            nameText:SetJustifyH("LEFT")
            nameText:SetWordWrap(false)
            nameText:SetText(cd.name)
            nameText:SetTextColor(1, 1, 1, 1)
            -- Simplified attachment checkbox creation
            local function CreateAttachCheckbox(row, label, settingKey, onToggle)
                local chk = CreateCustomCheckbox(row, 300, label, function(val)
                    if onToggle then onToggle(cd.cooldownID, val) end
                end)
                local val = SfuiDB and SfuiDB.trackedBars and SfuiDB.trackedBars[cd.cooldownID] and
                SfuiDB.trackedBars[cd.cooldownID][settingKey] or false
                chk:SetChecked(val)
                return chk
            end

            if groupID == 3 then
                -- Determine Context (Has Secondary Power Bar?)
                local specID = sfui.common.get_current_spec_id and sfui.common.get_current_spec_id() or 0
                local hasSecondary = false
                if sfui.common.get_secondary_resource and sfui.common.get_secondary_resource() then
                    -- Check if hidden spec
                    if not (sfui.config.secondaryPowerBar.hiddenSpecs and sfui.config.secondaryPowerBar.hiddenSpecs[specID]) then
                        hasSecondary = true
                    end
                end

                if hasSecondary then
                    -- Option: attach to secondary powerbar (Stacking)
                    local chk = CreateCustomCheckbox(row, 300, "secondary", function(val)
                        if sfui.trackedbars and sfui.trackedbars.SetAttachSecondary then
                            sfui.trackedbars.SetAttachSecondary(cd.cooldownID, val)
                        end
                    end)
                    local val = false
                    if SfuiDB and SfuiDB.trackedBars and SfuiDB.trackedBars[cd.cooldownID] then
                        val = SfuiDB.trackedBars[cd.cooldownID].attachSecondary or false
                    end
                    chk:SetChecked(val)
                else
                    -- Option: attach to healthbar (Exclusive 'Secondary' replacement)
                    local chk = CreateCustomCheckbox(row, 300, "health", function(val)
                        if sfui.trackedbars and sfui.trackedbars.SetAttachHealth then
                            sfui.trackedbars.SetAttachHealth(cd.cooldownID, val)
                        end
                    end)
                    local val = false
                    if SfuiDB and SfuiDB.trackedBars and SfuiDB.trackedBars[cd.cooldownID] then
                        val = SfuiDB.trackedBars[cd.cooldownID].isSecondary or false
                    end
                    chk:SetChecked(val)
                end

                -- REMOVED Per-Bar HideOOC/Inactive Checkboxes

                -- Color Swatch
                local initialColor = sfui.config.colors.purple
                if SfuiDB and SfuiDB.trackedBars and SfuiDB.trackedBars[cd.cooldownID] and SfuiDB.trackedBars[cd.cooldownID].color then
                    initialColor = SfuiDB.trackedBars[cd.cooldownID].color
                end

                CreateColorSwatch(row, 500, initialColor, function(r, g, b)
                    if sfui.trackedbars and sfui.trackedbars.SetColor then
                        sfui.trackedbars.SetColor(cd.cooldownID, r, g, b)
                    end
                end)
            end

            yOffset = yOffset - 26
        end
        yOffset = yOffset - 10
    end

    content:SetHeight(math.abs(yOffset) + 20)
end

function sfui.trackedoptions.toggle_viewer()
    -- Create frame if it doesn't exist
    if not frame then
        CreateCooldownsFrame()
        -- Show immediately after creation (first-time open)
        frame:Show()
        UpdateCooldownsList()
        return
    end

    -- Toggle visibility for subsequent calls
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        UpdateCooldownsList()
    end
end

-- Public function to refresh the list (e.g. when exclusive health attachment changes)
function sfui.trackedoptions.RefreshList()
    if frame and frame:IsShown() then
        UpdateCooldownsList()
    end
end
