local addonName, addon = ...
sfui.trackedoptions = {}

local frame
local scrollFrame
local scrollChild
local content             -- The list of tracked bars
local UpdateCooldownsList -- Forward declaration
local CreateFlatButton = sfui.common.create_flat_button
local c = sfui.config.options_panel
local g = sfui.config

local function CreateNumericEditBox(parent, w, h, callback)
    local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    eb:SetSize(w, h)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetAutoFocus(false)
    eb:SetJustifyH("CENTER")
    eb:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    eb:SetBackdropColor(0.2, 0.2, 0.2, 1)
    eb:SetBackdropBorderColor(0, 0, 0, 1)
    eb:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if callback then callback(val) end
        self:ClearFocus()
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return eb
end

local function CreateCooldownsFrame()
    if frame then return end

    local create_slider_input = sfui.common.create_slider_input

    frame = CreateFrame("Frame", "SfuiCooldownsViewer", UIParent, "BackdropTemplate")
    local winCfg = sfui.config.trackedOptionsWindow or { width = 850, height = 600 }
    frame:SetSize(winCfg.width, winCfg.height)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    frame:SetBackdrop({ bgFile = g.textures.white, tile = true, tileSize = 32 })
    frame:SetBackdropColor(c.backdrop_color.r, c.backdrop_color.g, c.backdrop_color.b, c.backdrop_color.a)

    -- Close (X)
    local close_button = CreateFlatButton(frame, "X", 24, 24)
    close_button:SetPoint("TOPRIGHT", -5, -5)
    close_button:SetScript("OnClick", function() frame:Hide() end)

    -- Reset (Right)
    local resetBtn = CreateFlatButton(frame, "reset", 60, 22)
    resetBtn:SetPoint("TOPRIGHT", -34, -5) -- Aligned with options/cooldownviewer Y offset
    resetBtn:SetScript("OnClick", function()
        if sfui.trackedbars and sfui.trackedbars.RequestReset then
            sfui.trackedbars.RequestReset()
        end
    end)

    -- Options (Left)
    local optionsBtn = CreateFlatButton(frame, "options", 80, 22)
    optionsBtn:SetPoint("TOPLEFT", 10, -5)
    optionsBtn:SetScript("OnClick", function()
        if sfui.toggle_options_panel then
            sfui.toggle_options_panel()

            -- Cycle breaker: Ensure 'frame' (Tracking Manager) is not dependent on options frame
            local left = frame:GetLeft()
            local top = frame:GetTop()
            if left and top then
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            end

            -- Attach options frame to the LEFT of this tracking manager frame
            if sfui_options_frame and sfui_options_frame:IsShown() then
                sfui_options_frame:ClearAllPoints()
                sfui_options_frame:SetPoint("TOPRIGHT", frame, "TOPLEFT", -5, 0)
            end
        end
    end)

    -- CooldownViewer (Left)
    local blizBtn = CreateFlatButton(frame, "cooldownviewer", 100, 22)
    blizBtn:SetPoint("LEFT", optionsBtn, "RIGHT", 5, 0)
    blizBtn:SetScript("OnClick", function()
        if CooldownViewerSettings then
            if CooldownViewerSettings:IsShown() then
                CooldownViewerSettings:Hide()
            else
                CooldownViewerSettings:Show()
            end
        end
    end)

    local header_text = frame:CreateFontString(nil, "OVERLAY", g.font_large)
    header_text:SetPoint("TOP", frame, "TOP", 0, -5)
    header_text:SetTextColor(g.header_color[1], g.header_color[2], g.header_color[3])
    header_text:SetText("tracking manager")

    scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -50)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(800, 1000)
    scrollFrame:SetScrollChild(scrollChild)

    local global_header = scrollChild:CreateFontString(nil, "OVERLAY", g.font)
    global_header:SetPoint("TOPLEFT", 10, -10)
    global_header:SetTextColor(1, 1, 1)
    global_header:SetText("visibility and positioning")

    local function UpdateVisibility(key, val, syncBlizzard)
        SfuiDB = SfuiDB or {}
        SfuiDB[key] = val
        if syncBlizzard and BuffBarCooldownViewer and BuffBarCooldownViewer.SetHideWhenInactive then
            BuffBarCooldownViewer:SetHideWhenInactive(val)
        end
        if sfui.trackedbars and sfui.trackedbars.UpdateVisibility then sfui.trackedbars.UpdateVisibility() end
    end

    local chk_ooc = sfui.common.create_checkbox(scrollChild, "hide bar out of combat", nil,
        function(val) UpdateVisibility("hideOOC", val, true) end)
    chk_ooc:SetPoint("TOPLEFT", global_header, "BOTTOMLEFT", 0, -10)
    chk_ooc:SetChecked(SfuiDB and SfuiDB.hideOOC or false)

    local chk_inactive = sfui.common.create_checkbox(scrollChild, "hide when inactive", nil,
        function(val) UpdateVisibility("hideInactive", val, true) end)
    chk_inactive:SetPoint("TOPLEFT", chk_ooc, "BOTTOMLEFT", 0, -5)
    local inactiveState = true
    if SfuiDB and SfuiDB.hideInactive ~= nil then
        inactiveState = SfuiDB.hideInactive
    elseif BuffBarCooldownViewer and BuffBarCooldownViewer.GetHideWhenInactive then
        inactiveState = BuffBarCooldownViewer:GetHideWhenInactive()
    end
    chk_inactive:SetChecked(inactiveState)

    -- Positioning Sliders (stay on top line, anchored to first checkbox)
    local sliderX = sfui.common.create_slider_input(scrollChild, "posX:", "trackedBarsX", -1000, 1000, 1, function(val)
        if sfui.trackedbars and sfui.trackedbars.UpdatePosition then sfui.trackedbars.UpdatePosition() end
    end)
    sliderX:SetPoint("LEFT", chk_ooc, "RIGHT", 180, 0)

    local sliderY = sfui.common.create_slider_input(scrollChild, "posY:", "trackedBarsY", -1000, 1000, 1, function(val)
        if sfui.trackedbars and sfui.trackedbars.UpdatePosition then sfui.trackedbars.UpdatePosition() end
    end)
    sliderY:SetPoint("LEFT", sliderX, "RIGHT", 10, 0)

    local colHeader = CreateFrame("Frame", nil, scrollChild)
    colHeader:SetSize(800, 25)
    colHeader:SetPoint("TOPLEFT", chk_inactive, "BOTTOMLEFT", 0, -25)

    local tableHeader = colHeader:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    tableHeader:SetPoint("TOPLEFT", 0, 0)
    tableHeader:SetTextColor(0.8, 0.8, 0.8)
    tableHeader:SetText("tracked bars")

    local function CreateHeader(point, text, subText)
        local h = colHeader:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", point, 0)
        h:SetTextColor(0.7, 0.7, 0.7)
        h:SetText(text)
        if subText then
            local s = colHeader:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            s:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -2)
            s:SetTextColor(0.5, 0.5, 0.5)
            s:SetText(subText)
            sfui.common.style_text(s, nil, 9, nil)
        end
        return h
    end

    -- Align headers starting after "tracked bars" title
    CreateHeader(320, "attach", "to hp")
    CreateHeader(400, "mode", "stack bar")
    CreateHeader(480, "max", "stacks")
    CreateHeader(560, "text", "show stacks")
    CreateHeader(640, "text", "show title")
    CreateHeader(720, "color")

    content = CreateFrame("Frame", nil, scrollChild)
    content:SetPoint("TOPLEFT", colHeader, "BOTTOMLEFT", 0, 0)
    content:SetWidth(800)

    frame.StartMoving = function() frame:StartMoving() end
    frame.StopMovingOrSizing = function() frame:StopMovingOrSizing() end

    frame:SetScript("OnShow", function()
        if InCombatLockdown() then
            print("|cffFF0000SFUI:|r Cannot configure tracked bars in combat.")
            frame:Hide()
            return
        end
        UpdateCooldownsList() -- Updates content list
        if not C_AddOns.IsAddOnLoaded("Blizzard_CooldownViewer") then C_AddOns.LoadAddOn("Blizzard_CooldownViewer") end
    end)
end

UpdateCooldownsList = function()
    if not frame then return end
    if not CooldownViewerSettings then return end

    local dataProvider = CooldownViewerSettings:GetDataProvider()
    if not dataProvider then return end

    local cooldownIDs = dataProvider:GetOrderedCooldownIDs()
    local groupedCooldowns = {}

    for _, cooldownID in ipairs(cooldownIDs) do
        local info = dataProvider:GetCooldownInfoForID(cooldownID)
        if info then
            -- We only care about Default Tracks for this list
            local groupID = info.category or 0
            if not groupedCooldowns[groupID] then groupedCooldowns[groupID] = {} end

            local effectiveSpellID = info.overrideTooltipSpellID or info.overrideSpellID or info.spellID
            local iconTexture
            if effectiveSpellID then iconTexture = C_Spell.GetSpellTexture(effectiveSpellID) end

            table.insert(groupedCooldowns[groupID], {
                cooldownID = cooldownID,
                name = C_Spell.GetSpellName(effectiveSpellID or 0) or "Unknown",
                icon = iconTexture,
                spellID = effectiveSpellID, -- Capture ID for tooltip
                isKnown = info.isKnown
            })
        end
    end

    for _, child in ipairs({ content:GetChildren() }) do
        child:Hide(); child:SetParent(nil)
    end

    local yOffset = 0
    local sortedGroups = {}
    for groupID in pairs(groupedCooldowns) do
        if groupID == 3 then table.insert(sortedGroups, groupID) end
    end
    table.sort(sortedGroups)

    for _, groupID in ipairs(sortedGroups) do
        for i, cd in ipairs(groupedCooldowns[groupID]) do
            local row = CreateFrame("Frame", nil, content)
            row:SetSize(780, 24) -- Use more width
            row:SetPoint("TOPLEFT", 0, yOffset)

            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(20, 20)
            icon:SetPoint("LEFT", 0, 0) -- Leftmost column
            icon:SetTexture(cd.icon or 134400)
            if not cd.isKnown then icon:SetDesaturated(true) end



            local nameText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            nameText:SetPoint("LEFT", icon, "RIGHT", 5, 0)
            nameText:SetJustifyH("LEFT")
            nameText:SetText(cd.name)

            -- Tooltip (HIT RECT) - must be after nameText exists
            local hitRect = CreateFrame("Frame", nil, row)
            hitRect:SetPoint("TOPLEFT", icon, "TOPLEFT")
            hitRect:SetPoint("BOTTOMRIGHT", nameText, "BOTTOMRIGHT")
            hitRect:EnableMouse(true)
            hitRect:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetSpellByID(cd.spellID or 0)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("CooldownID: " .. (cd.cooldownID or "nil"), 1, 1, 1)
                GameTooltip:AddLine("SpellID: " .. (cd.spellID or "nil"), 1, 1, 1)
                GameTooltip:Show()
            end)
            hitRect:SetScript("OnLeave", function() GameTooltip:Hide() end)

            local attachChk = sfui.common.create_checkbox(row, "", nil, function(val)
                local barDB = sfui.common.ensure_tracked_bar_db(cd.cooldownID)
                SfuiDB.trackedBars[cd.cooldownID].stackAboveHealth = val
                if sfui.trackedbars and sfui.trackedbars.ForceLayoutUpdate then sfui.trackedbars.ForceLayoutUpdate() end
            end)
            attachChk:SetPoint("LEFT", row, "LEFT", 320, 0)
            local attachVal = false
            if sfui.trackedbars and sfui.trackedbars.GetConfig then
                local cfg = sfui.trackedbars.GetConfig(cd.cooldownID)
                if cfg and cfg.stackAboveHealth then attachVal = true end
            end
            attachChk:SetChecked(attachVal)

            local stackChk = sfui.common.create_checkbox(row, "", nil, function(val)
                local barDB = sfui.common.ensure_tracked_bar_db(cd.cooldownID)
                SfuiDB.trackedBars[cd.cooldownID].stackMode = val
                if sfui.trackedbars and sfui.trackedbars.ForceLayoutUpdate then sfui.trackedbars.ForceLayoutUpdate() end
            end)
            stackChk:SetPoint("LEFT", row, "LEFT", 400, 0)
            local stackVal = false
            if sfui.trackedbars and sfui.trackedbars.GetConfig then
                local cfg = sfui.trackedbars.GetConfig(cd.cooldownID)
                if cfg and cfg.stackMode then stackVal = true end
            end
            stackChk:SetChecked(stackVal)

            local maxInput = CreateNumericEditBox(row, 30, 18, function(val)
                local barDB = sfui.common.ensure_tracked_bar_db(cd.cooldownID)
                if val and val > 0 then SfuiDB.trackedBars[cd.cooldownID].maxStacks = val else SfuiDB.trackedBars[cd.cooldownID].maxStacks = nil end
                if sfui.trackedbars and sfui.trackedbars.ForceLayoutUpdate then sfui.trackedbars.ForceLayoutUpdate() end
            end)
            maxInput:SetPoint("LEFT", row, "LEFT", 480, 0)
            local dbVal = SfuiDB.trackedBars and SfuiDB.trackedBars[cd.cooldownID] and
            SfuiDB.trackedBars[cd.cooldownID].maxStacks
            if dbVal then maxInput:SetText(dbVal) end


            local textChk = sfui.common.create_checkbox(row, "", nil, function(val)
                local barDB = sfui.common.ensure_tracked_bar_db(cd.cooldownID)
                SfuiDB.trackedBars[cd.cooldownID].showStacksText = val
                if sfui.trackedbars and sfui.trackedbars.ForceLayoutUpdate then sfui.trackedbars.ForceLayoutUpdate() end
            end)
            textChk:SetPoint("LEFT", row, "LEFT", 560, 0)
            local showStacksTextVal = false
            if sfui.trackedbars and sfui.trackedbars.GetConfig then
                local cfg = sfui.trackedbars.GetConfig(cd.cooldownID)
                if cfg and cfg.showStacksText then showStacksTextVal = true end
            end
            textChk:SetChecked(showStacksTextVal)

            local titleChk = sfui.common.create_checkbox(row, "", nil, function(val)
                local barDB = sfui.common.ensure_tracked_bar_db(cd.cooldownID)
                SfuiDB.trackedBars[cd.cooldownID].showName = val
                if sfui.trackedbars and sfui.trackedbars.ForceLayoutUpdate then sfui.trackedbars.ForceLayoutUpdate() end
            end)
            titleChk:SetPoint("LEFT", row, "LEFT", 640, 0)
            local showNameVal = true
            if sfui.trackedbars and sfui.trackedbars.GetConfig then
                local cfg = sfui.trackedbars.GetConfig(cd.cooldownID)
                if cfg and cfg.showName == false then showNameVal = false end
            end
            titleChk:SetChecked(showNameVal)

            local initialColor = sfui.config.colors.purple
            if sfui.trackedbars and sfui.trackedbars.GetConfig then
                local cfg = sfui.trackedbars.GetConfig(cd.cooldownID)
                if cfg and cfg.color then initialColor = cfg.color end
            end
            local swatch = sfui.common.create_color_swatch(row, initialColor, function(r, g, b)
                if sfui.trackedbars and sfui.trackedbars.SetColor then sfui.trackedbars.SetColor(cd.cooldownID, r, g, b) end
            end)
            swatch:SetPoint("LEFT", row, "LEFT", 720, 0)

            yOffset = yOffset - 26
        end
    end

    content:SetHeight(math.abs(yOffset) + 20)
    scrollChild:SetHeight(content:GetHeight() + 200) -- Clean height
end

function sfui.trackedoptions.toggle_viewer()
    if not frame then
        CreateCooldownsFrame()
        frame:Show()
        UpdateCooldownsList()
        return
    end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        UpdateCooldownsList()
    end
end

function sfui.trackedoptions.RefreshList()
    if frame and frame:IsShown() then UpdateCooldownsList() end
end
