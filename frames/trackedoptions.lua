local addonName, addon = ...
sfui.trackedoptions = {}

local frame
local scrollFrame
local content
local c = sfui.config.options_panel
local g = sfui.config





local function CreateCooldownsFrame()
    if frame then return end

    local CreateFlatButton = sfui.common.create_flat_button
    local create_slider_input = sfui.common.create_slider_input

    frame = CreateFrame("Frame", "SfuiCooldownsViewer", UIParent, "BackdropTemplate")
    local winCfg = sfui.config.trackedOptionsWindow or { width = 600, height = 500 }
    frame:SetSize(winCfg.width, winCfg.height)
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
    local chk_ooc = sfui.common.create_checkbox(frame, "hide out of combat", nil, function(val)
        UpdateVisibility("hideOOC", val)
    end)
    chk_ooc:SetPoint("LEFT", frame, "LEFT", 15, 0)
    chk_ooc:SetPoint("TOPLEFT", global_header, "BOTTOMLEFT", 0, -10)
    chk_ooc:SetChecked(SfuiDB and SfuiDB.hideOOC or false)

    -- Checkbox: Hide When Inactive
    local chk_inactive = sfui.common.create_checkbox(frame, "hide when inactive", nil, function(val)
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
    tableHeader:SetText("tracked bars")

    -- Column Headers
    local colHeader = CreateFrame("Frame", nil, frame)
    colHeader:SetSize(600, 20)
    colHeader:SetPoint("TOPLEFT", tableHeader, "BOTTOMLEFT", 0, -5)

    local col1 = colHeader:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    col1:SetPoint("LEFT", 30, 0)
    col1:SetTextColor(0.7, 0.7, 0.7)
    col1:SetText("ability")

    local col2 = colHeader:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    col2:SetPoint("LEFT", 420, 0)
    col2:SetTextColor(0.7, 0.7, 0.7)
    col2:SetText("stacks")

    local col3 = colHeader:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    col3:SetPoint("LEFT", 500, 0)
    col3:SetTextColor(0.7, 0.7, 0.7)
    col3:SetText("color")

    -- Content Frame (Direct child, no scrollbar)
    content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", colHeader, "BOTTOMLEFT", 0, -5)
    content:SetPoint("BOTTOMRIGHT", -10, 10)
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
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if cd.effectiveSpellID then
                    GameTooltip:SetSpellByID(cd.effectiveSpellID)
                end
                -- Add debug info
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("IDs:", 0.5, 0.5, 0.5)
                GameTooltip:AddDoubleLine("cooldownID:", tostring(cd.cooldownID), 1, 1, 1, 0.8, 0.8, 1)
                if cd.spellID then
                    GameTooltip:AddDoubleLine("spellID:", tostring(cd.spellID), 1, 1, 1, 0.8, 0.8, 1)
                end
                if cd.effectiveSpellID then
                    GameTooltip:AddDoubleLine("effectiveSpellID:", tostring(cd.effectiveSpellID), 1, 1, 1, 0.8, 0.8, 1)
                end
                GameTooltip:Show()
            end)
            iconButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

            -- Spell Name (Left Aligned)
            local nameText = row:CreateFontString(nil, "ARTWORK")
            nameText:SetFontObject(g.font)
            nameText:SetPoint("LEFT", iconButton, "RIGHT", 10, 0)
            nameText:SetWidth(400) -- Increased width as attachment options are gone
            nameText:SetJustifyH("LEFT")
            nameText:SetWordWrap(false)
            nameText:SetText(cd.name)
            nameText:SetTextColor(1, 1, 1, 1)

            if groupID == 3 then
                -- Stack Mode Checkbox
                local stackChk = sfui.common.create_checkbox(row, "", nil, function(val)
                    local barDB = sfui.common.ensure_tracked_bar_db(cd.cooldownID)
                    SfuiDB.trackedBars[cd.cooldownID].stackMode = val

                    -- Force immediate layout update
                    if sfui.trackedbars and sfui.trackedbars.ForceLayoutUpdate then
                        sfui.trackedbars.ForceLayoutUpdate()
                    end
                end)
                stackChk:SetPoint("LEFT", row, "LEFT", 420, 0)

                local stackVal = false
                if SfuiDB and SfuiDB.trackedBars and SfuiDB.trackedBars[cd.cooldownID] then
                    stackVal = SfuiDB.trackedBars[cd.cooldownID].stackMode or false
                end
                stackChk:SetChecked(stackVal)

                -- Color Swatch
                local initialColor = sfui.config.colors.purple
                if SfuiDB and SfuiDB.trackedBars and SfuiDB.trackedBars[cd.cooldownID] and SfuiDB.trackedBars[cd.cooldownID].color then
                    initialColor = SfuiDB.trackedBars[cd.cooldownID].color
                end

                local swatch = sfui.common.create_color_swatch(row, initialColor, function(r, g, b)
                    if sfui.trackedbars and sfui.trackedbars.SetColor then
                        sfui.trackedbars.SetColor(cd.cooldownID, r, g, b)
                    end
                end)
                swatch:SetPoint("LEFT", row, "LEFT", 500, 0)
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
