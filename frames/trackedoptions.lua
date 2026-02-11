local addonName, addon = ...
sfui.trackedoptions = {}

local frame
local scrollFrame
local scrollChild
local content -- The list of tracked bars
local UpdateCooldownsList
local issecretvalue = sfui.common.issecretvalue
-- Forward declaration
local CreateFlatButton = sfui.common.create_flat_button
local g = sfui.config
local c = g.options_panel

local function select_tab(frame, id)
    if not frame.tabs then return end
    for i, tab in ipairs(frame.tabs) do
        local btn = tab.button
        if i == id then
            tab.panel:Show()
            btn.text:SetTextColor(g.colors.cyan[1], g.colors.cyan[2], g.colors.cyan[3])
        else
            tab.panel:Hide()
            btn.text:SetTextColor(g.colors.purple[1], g.colors.purple[2], g.colors.purple[3])
        end
    end
    frame.selectedTabId = id
    SfuiDB.lastSelectedTabId = id -- Persist tab selection

    if id == 2 then
        sfui.trackedoptions.UpdateEditor()
    end
end

local function CreateNavButton(parent, name, id)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(60, 22)
    local t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("CENTER")
    t:SetText(name)
    b.text = t

    b:SetScript("OnClick", function() select_tab(parent, id) end)
    b:SetScript("OnEnter", function()
        t:SetTextColor(1, 1, 1)
    end)
    b:SetScript("OnLeave", function()
        if parent.selectedTabId == id then
            t:SetTextColor(g.colors.cyan[1], g.colors.cyan[2], g.colors.cyan[3])
        else
            t:SetTextColor(g.colors.purple[1], g.colors.purple[2], g.colors.purple[3])
        end
    end)
    return b
end

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
    local winCfg = sfui.config.trackedOptionsWindow or { width = 1100, height = 650 }
    frame:SetSize(winCfg.width, winCfg.height)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetFrameStrata("DIALOG")
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

    -- CooldownViewer (Header)
    local blizBtn = CreateFlatButton(frame, "cooldownviewer", 100, 22)
    blizBtn:SetPoint("LEFT", optionsBtn, "RIGHT", 5, 0)
    blizBtn:SetScript("OnClick", function()
        if CooldownViewerSettings then
            if CooldownViewerSettings:IsShown() then CooldownViewerSettings:Hide() else CooldownViewerSettings:Show() end
        end
    end)

    -- Tabs Container (Header)
    frame.tabs = {}

    -- Tab 1: Bars
    local barsBtn = CreateNavButton(frame, "bars", 1)
    barsBtn:SetPoint("LEFT", blizBtn, "RIGHT", 5, 0)

    -- Tab 2: Icons
    local iconsBtn = CreateNavButton(frame, "icons", 2)
    iconsBtn:SetPoint("LEFT", barsBtn, "RIGHT", 5, 0)

    sfui.trackedoptions.selectedPanelIndex = 1
    sfui.trackedoptions.selectedEntryIndex = nil

    local header_text = frame:CreateFontString(nil, "OVERLAY", g.font_large)
    header_text:SetPoint("TOP", frame, "TOP", 0, -5)
    header_text:SetTextColor(g.header_color[1], g.header_color[2], g.header_color[3])
    header_text:SetText("tracking manager")

    -- Content Panels
    local barsPanel = CreateFrame("Frame", nil, frame)
    barsPanel:SetPoint("TOPLEFT", 10, -50)
    barsPanel:SetPoint("BOTTOMRIGHT", -10, 10)

    local barsScroll = CreateFrame("ScrollFrame", "SfuiTrackingBarsScroll", barsPanel, "UIPanelScrollFrameTemplate")
    barsScroll:SetPoint("TOPLEFT", 0, 0)
    barsScroll:SetPoint("BOTTOMRIGHT", -25, 0)
    local barsContent = CreateFrame("Frame", nil, barsScroll)
    barsContent:SetSize(800, 1000)
    barsScroll:SetScrollChild(barsContent)

    table.insert(frame.tabs, { button = barsBtn, panel = barsPanel, scrollChild = barsContent })

    local iconsPanel = CreateFrame("Frame", "SfuiIconsTab", frame)
    iconsPanel:SetPoint("TOPLEFT", 10, -50)
    iconsPanel:SetPoint("BOTTOMRIGHT", -10, 10)
    iconsPanel:Hide()

    table.insert(frame.tabs, { button = iconsBtn, panel = iconsPanel })

    -- Global Header within Bars Tab
    local global_header = barsContent:CreateFontString(nil, "OVERLAY", g.font)
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

    local chk_ooc = sfui.common.create_checkbox(barsContent, "hide bar out of combat", nil,
        function(val) UpdateVisibility("hideOOC", val, true) end)
    chk_ooc:SetPoint("TOPLEFT", global_header, "BOTTOMLEFT", 0, -10)
    chk_ooc:SetChecked(SfuiDB and SfuiDB.hideOOC or false)

    local chk_inactive = sfui.common.create_checkbox(barsContent, "hide when inactive", nil,
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
    local sliderX = sfui.common.create_slider_input(barsContent, "posX:", "trackedBarsX", -1000, 1000, 1, function(val)
        if sfui.trackedbars and sfui.trackedbars.UpdatePosition then sfui.trackedbars.UpdatePosition() end
    end)
    sliderX:SetPoint("LEFT", chk_ooc, "RIGHT", 180, 0)

    local sliderY = sfui.common.create_slider_input(barsContent, "posY:", "trackedBarsY", -1000, 1000, 1, function(val)
        if sfui.trackedbars and sfui.trackedbars.UpdatePosition then sfui.trackedbars.UpdatePosition() end
    end)
    sliderY:SetPoint("LEFT", sliderX, "RIGHT", 10, 0)

    local colHeader = CreateFrame("Frame", nil, barsContent)
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

    content = CreateFrame("Frame", "SfuiTrackedBarsContent", barsContent)
    content:SetSize(800, 210)
    content:SetPoint("TOPLEFT", colHeader, "BOTTOMLEFT", 0, 0)

    -- === ICON EDITOR SECTION ===
    -- LEFT: Panel List
    local leftPanel = CreateFrame("Frame", nil, iconsPanel, "BackdropTemplate")
    leftPanel:SetPoint("TOPLEFT", 0, 0)
    leftPanel:SetPoint("BOTTOMLEFT", 0, 0)
    leftPanel:SetWidth(120) -- Reduced from 150
    leftPanel:SetBackdrop({ bgFile = g.textures.white })
    leftPanel:SetBackdropColor(0.05, 0.05, 0.05, 0.9)

    local lpScroll = CreateFrame("ScrollFrame", nil, leftPanel, "UIPanelScrollFrameTemplate")
    lpScroll:SetPoint("TOPLEFT", 5, -5)
    lpScroll:SetPoint("BOTTOMRIGHT", -25, 45)
    local lpContent = CreateFrame("Frame", nil, lpScroll)
    lpContent:SetSize(1, 1)
    lpScroll:SetScrollChild(lpContent)
    sfui.trackedoptions.lpContent = lpContent

    local addBtn = CreateFlatButton(leftPanel, "+ add", 85, 22)
    addBtn:SetPoint("BOTTOMLEFT", 5, 5)
    addBtn:SetScript("OnClick", function()
        SfuiDB.cooldownPanels = SfuiDB.cooldownPanels or {}
        table.insert(SfuiDB.cooldownPanels, {
            name = "Panel " .. (#SfuiDB.cooldownPanels + 1),
            enabled = true,
            entries = {},
            size = 50,
            spacing = 2,
            x = 0,
            y = 250,
            columns = 10,
            textEnabled = true,
            textColor = { r = 1, g = 1, b = 1 },
            readyGlow = true,
            cooldownDesat = true,
            cooldownAlpha = 1.0,
            glowType = "blizzard",
            glowColor = { r = 1, g = 1, b = 0 },
            glowScale = 1.0,
            glowIntensity = 1.0,
            glowSpeed = 0.25
        })
        sfui.trackedoptions.UpdateEditor()
        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
    end)

    local delBtn = CreateFlatButton(leftPanel, "- del", 80, 22)
    delBtn:SetPoint("BOTTOMRIGHT", -5, 5)
    delBtn:SetScript("OnClick", function()
        local idx = sfui.trackedoptions.selectedPanelIndex
        if idx and SfuiDB.cooldownPanels[idx] then
            table.remove(SfuiDB.cooldownPanels, idx)
            sfui.trackedoptions.selectedPanelIndex = 1
            sfui.trackedoptions.selectedEntryIndex = nil
            sfui.trackedoptions.UpdateEditor()
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end
    end)

    -- MIDDLE: Preview / Drop area
    local midPanel = CreateFrame("Frame", nil, iconsPanel, "BackdropTemplate")
    midPanel:SetBackdrop({ bgFile = g.textures.white })
    midPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.6)

    local midHeader = midPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    midHeader:SetPoint("TOPLEFT", 5, -5)
    midHeader:SetText("icon preview / drop area")

    local previewChild = CreateFrame("Frame", nil, midPanel, "BackdropTemplate")
    previewChild:SetPoint("CENTER", midPanel, "CENTER", 0, 0)
    previewChild:SetSize(1, 1)
    previewChild:SetBackdrop({ bgFile = g.textures.white, edgeFile = g.textures.white, edgeSize = 1 })
    previewChild:SetBackdropColor(1, 1, 1, 0.05)
    previewChild:SetBackdropBorderColor(1, 1, 1, 0.05)
    sfui.trackedoptions.previewChild = previewChild

    -- Drop Logic
    local function OnReceiveDrag()
        local infoType, id, _, spellID = GetCursorInfo()
        if not infoType then return end

        local dragId, dragType = id, infoType
        if infoType == "spell" then
            dragId = spellID
        elseif infoType == "macro" then
            local sId = GetMacroSpell(id)
            if sId then
                dragId = sId; dragType = "spell"
            else
                local _, link = GetMacroItem(id)
                if link then
                    dragId = tonumber(link:match("item:(%d+)")); dragType = "item"
                end
            end
        end

        if dragId and (dragType == "spell" or dragType == "item") then
            local idx = sfui.trackedoptions.selectedPanelIndex or 1
            local panel = SfuiDB.cooldownPanels and SfuiDB.cooldownPanels[idx]
            if panel then
                panel.entries = panel.entries or {}
                table.insert(panel.entries, { type = dragType, id = dragId, settings = { showText = true } })
                ClearCursor()
                sfui.trackedoptions.selectedEntryIndex = #panel.entries
                sfui.trackedoptions.UpdateEditor()
                if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
            end
        end
    end
    midPanel:SetScript("OnMouseUp", OnReceiveDrag)
    midPanel:SetScript("OnReceiveDrag", OnReceiveDrag)

    -- RIGHT 1: General Options Panel
    local genPanel = CreateFrame("Frame", nil, iconsPanel, "BackdropTemplate")
    genPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 5, 0)
    genPanel:SetPoint("BOTTOMLEFT", leftPanel, "BOTTOMRIGHT", 5, 0)
    genPanel:SetWidth(235)
    genPanel:SetBackdrop({ bgFile = g.textures.white })
    genPanel:SetBackdropColor(0.05, 0.05, 0.05, 0.9)

    local gpScroll = CreateFrame("ScrollFrame", nil, genPanel, "UIPanelScrollFrameTemplate")
    gpScroll:SetPoint("TOPLEFT", 5, -5)
    gpScroll:SetPoint("BOTTOMRIGHT", -25, 5)
    local gpContent = CreateFrame("Frame", nil, gpScroll)
    gpContent:SetSize(1, 1)
    gpScroll:SetScrollChild(gpContent)
    sfui.trackedoptions.gpContent = gpContent

    -- Anchoring Expanded Preview (midPanel) to the right of General Options
    midPanel:SetPoint("TOPLEFT", genPanel, "TOPRIGHT", 5, 0)
    midPanel:SetPoint("BOTTOMRIGHT", iconsPanel, "BOTTOMRIGHT", 0, 0)
    sfui.trackedoptions.iconsPanel = iconsPanel

    frame.StartMoving = function() frame:StartMoving() end
    frame.StopMovingOrSizing = function() frame:StopMovingOrSizing() end

    frame:SetScript("OnShow", function()
        if InCombatLockdown() then
            print("|cffFF0000SFUI:|r Cannot configure tracked bars in combat.")
            frame:Hide()
            return
        end
        select_tab(frame, SfuiDB.lastSelectedTabId or frame.selectedTabId or 1)
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
        if not issecretvalue(cooldownID) then
            local info = dataProvider:GetCooldownInfoForID(cooldownID)
            if info then
                -- We only care about Default Tracks for this list
                local groupID = info.category or 0
                if not groupedCooldowns[groupID] then groupedCooldowns[groupID] = {} end

                local effectiveSpellID = info.overrideTooltipSpellID or info.overrideSpellID or info.spellID
                if effectiveSpellID and not issecretvalue(effectiveSpellID) then
                    local iconTexture = C_Spell.GetSpellTexture(effectiveSpellID)

                    table.insert(groupedCooldowns[groupID], {
                        cooldownID = cooldownID,
                        name = C_Spell.GetSpellName(effectiveSpellID) or "Unknown",
                        icon = iconTexture,
                        spellID = effectiveSpellID, -- Capture ID for tooltip
                        isKnown = info.isKnown
                    })
                end
            end
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

    content:SetHeight(math.max(math.abs(yOffset), 210)) -- Minimum height for 8 bars
    sfui.trackedoptions.UpdateEditor()
end

function sfui.trackedoptions.UpdateEditor()
    sfui.trackedoptions.UpdatePanelList()
    sfui.trackedoptions.UpdatePreview()
    sfui.trackedoptions.UpdateSettings()

    -- Update Scroll Heights
    if frame and frame.tabs then
        local barsTab = frame.tabs[1]
        if barsTab.scrollChild then
            barsTab.scrollChild:SetHeight(content:GetHeight() + 100)
        end
        -- Icons tab no longer has a main scrollChild to update
    end
end

function sfui.trackedoptions.UpdatePanelList()
    local lpContent = sfui.trackedoptions.lpContent
    if not lpContent then return end
    for _, child in ipairs({ lpContent:GetChildren() }) do
        child:Hide(); child:SetParent(nil)
    end

    local panels = SfuiDB.cooldownPanels or {}
    local y = 0
    for i, panel in ipairs(panels) do
        local btn = CreateFlatButton(lpContent, panel.name or ("Panel " .. i), 120, 20)
        btn:SetPoint("TOPLEFT", 0, y)
        if i == sfui.trackedoptions.selectedPanelIndex then
            btn:SetBackdropBorderColor(g.colors.purple[1], g.colors.purple[2], g.colors.purple[3], 1)
        end
        btn:SetScript("OnClick", function()
            sfui.trackedoptions.selectedPanelIndex = i
            sfui.trackedoptions.selectedEntryIndex = nil
            sfui.trackedoptions.UpdateEditor()
        end)
        y = y - 22
    end
    lpContent:SetHeight(math.abs(y))
end

function sfui.trackedoptions.UpdatePreview()
    local parent = sfui.trackedoptions.previewChild
    if not parent then return end
    for _, child in ipairs({ parent:GetChildren() }) do
        if sfui.trackedicons and sfui.trackedicons.StopGlow then
            sfui.trackedicons.StopGlow(child)
        end
        child:Hide(); child:SetParent(nil)
    end

    local idx = sfui.trackedoptions.selectedPanelIndex or 1
    local panel = SfuiDB.cooldownPanels and SfuiDB.cooldownPanels[idx]
    if not panel then return end

    local entries = panel.entries or {}
    local size = panel.size or 50
    local spacing = panel.spacing or 2
    local maxW, maxH = 0, 0

    for i, entry in ipairs(entries) do
        local icon = CreateFrame("Button", nil, parent, "BackdropTemplate")
        icon:SetSize(size, size)
        icon:RegisterForClicks("AnyUp")
        local tex = icon:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        local iconTexture
        if entry.type == "item" then
            iconTexture = C_Item.GetItemIconByID(entry.id)
        else
            iconTexture = C_Spell.GetSpellTexture(entry.id)
        end
        tex:SetTexture(iconTexture or 134400) -- Fallback to generic question mark if nil

        local col = (i - 1) % (panel.columns or 100)
        local row = math.floor((i - 1) / (panel.columns or 100))
        icon:SetPoint("TOPLEFT", col * (size + spacing), -row * (size + spacing))

        icon:SetScript("OnClick", function(_, btn)
            if btn == "RightButton" then
                table.remove(panel.entries, i)
                sfui.trackedoptions.selectedEntryIndex = nil
            else
                sfui.trackedoptions.selectedEntryIndex = i
            end
            sfui.trackedoptions.UpdateEditor()
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end)

        -- Highlighting selected icons in preview with purple
        if i == sfui.trackedoptions.selectedEntryIndex then
            sfui.common.create_border(icon, 1, { g.colors.purple[1], g.colors.purple[2], g.colors.purple[3], 1 })
        end

        -- Apply Preview Glow if enabled
        local function GetIconValue(key, default)
            if entry.settings and entry.settings[key] ~= nil then return entry.settings[key] end
            if panel[key] ~= nil then return panel[key] end
            return default
        end

        if GetIconValue("readyGlow", true) then
            local glowCfg = {
                glowType = GetIconValue("glowType", "blizzard"),
                glowColor = GetIconValue("glowColor", { r = 1, g = 1, b = 0 }),
                glowScale = GetIconValue("glowScale", 1.0),
                glowIntensity = GetIconValue("glowIntensity", 1.0),
                glowSpeed = GetIconValue("glowSpeed", 0.25)
            }
            if sfui.trackedicons and sfui.trackedicons.StartGlow then
                sfui.trackedicons.StartGlow(icon, glowCfg)
            end
        end

        maxW = math.max(maxW, (col + 1) * (size + spacing))
        maxH = math.max(maxH, (row + 1) * (size + spacing))
    end
    parent:SetSize(math.max(maxW, 10), math.max(maxH, 10))
end

function sfui.trackedoptions.UpdateSettings()
    local gpContent = sfui.trackedoptions.gpContent
    if not gpContent then return end

    -- Clear panel
    for _, child in ipairs({ gpContent:GetChildren() }) do
        child:Hide(); child:SetParent(nil)
    end
    for _, reg in ipairs({ gpContent:GetRegions() }) do reg:Hide() end

    local idx = sfui.trackedoptions.selectedPanelIndex or 1
    local panel = SfuiDB.cooldownPanels and SfuiDB.cooldownPanels[idx]
    if not panel then return end

    -- Panel-wide y-offset
    local gy = -10
    local function AddGeneralHeader(text)
        gy = gy - 5
        local h = gpContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        h:SetPoint("TOPLEFT", 5, gy)
        h:SetText(text)
        h:SetTextColor(g.colors.cyan[1], g.colors.cyan[2], g.colors.cyan[3])
        gy = gy - 20
        return h
    end

    local function AddGeneralLabel(text)
        local l = gpContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        l:SetPoint("TOPLEFT", 5, gy)
        l:SetText(text)
        gy = gy - 15
        return l
    end

    -- POPULATE GENERAL PANEL
    AddGeneralHeader("Panel: " .. (panel.name or "Unnamed"))
    AddGeneralLabel("panel name")
    local nameEB = CreateNumericEditBox(gpContent, 120, 18, function(val) end)
    nameEB:SetScript("OnEnterPressed", function(self)
        panel.name = self:GetText(); sfui.trackedoptions.UpdateEditor()
    end)
    nameEB:SetPoint("TOPLEFT", 5, gy)
    nameEB:SetText(panel.name or "")
    gy = gy - 30

    local xSlider = sfui.common.create_slider_input(gpContent, "pos x", function() return panel.x end, -1000, 1000,
        1, function(v)
            panel.x = v; if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end)
    xSlider:SetPoint("TOPLEFT", 5, gy); xSlider:SetSliderValue(panel.x or 0)
    gy = gy - 40

    local ySlider = sfui.common.create_slider_input(gpContent, "pos y", function() return panel.y end, -1000, 1000,
        1, function(v)
            panel.y = v; if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end)
    ySlider:SetPoint("TOPLEFT", 5, gy); ySlider:SetSliderValue(panel.y or 0)
    gy = gy - 40

    AddGeneralHeader("Layout Defaults")
    local sizeSlider = sfui.common.create_slider_input(gpContent, "icon size", function() return panel.size end, 10,
        100, 1, function(v)
            panel.size = v; sfui.trackedoptions.UpdatePreview()
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end)
    sizeSlider:SetPoint("TOPLEFT", 5, gy); sizeSlider:SetSliderValue(panel.size or 50)
    gy = gy - 40

    local spacingSlider = sfui.common.create_slider_input(gpContent, "spacing", function() return panel.spacing end, 0,
        50, 1, function(v)
            panel.spacing = v; sfui.trackedoptions.UpdatePreview()
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end)
    spacingSlider:SetPoint("TOPLEFT", 5, gy); spacingSlider:SetSliderValue(panel.spacing or 2)
    gy = gy - 40

    local columnsSlider = sfui.common.create_slider_input(gpContent, "columns", function() return panel.columns end, 1,
        20,
        1, function(v)
            panel.columns = v; sfui.trackedoptions.UpdatePreview()
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end)
    columnsSlider:SetPoint("TOPLEFT", 5, gy); columnsSlider:SetSliderValue(panel.columns or 10)
    gy = gy - 40

    AddGeneralHeader("Panel Defaults")
    local resetBtn = CreateFlatButton(gpContent, "reset all overrides", 160, 20)
    resetBtn:SetPoint("TOPLEFT", 5, gy)
    resetBtn:SetScript("OnClick", function()
        for _, entry in ipairs(panel.entries) do
            entry.settings = {} -- Clear all per-icon adjustments
        end
        sfui.trackedoptions.UpdateEditor()
        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
    end)
    gy = gy - 30

    local textCBC = sfui.common.create_checkbox(gpContent, "enable countdown text", function()
        if panel.textEnabled == nil then panel.textEnabled = true end
        return panel.textEnabled
    end, function(v)
        panel.textEnabled = v
        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        sfui.trackedoptions.UpdatePreview()
    end)
    textCBC:SetPoint("TOPLEFT", 5, gy)
    gy = gy - 25

    local colorLabelC = AddGeneralLabel("text color")
    local colorSwatchC = sfui.common.create_color_swatch(gpContent, panel.textColor or { r = 1, g = 1, b = 1 },
        function(r, g, b)
            panel.textColor = { r = r, g = g, b = b }
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end)
    colorSwatchC:SetPoint("LEFT", colorLabelC, "RIGHT", 10, 0)
    gy = gy - 20

    local glowCBC = sfui.common.create_checkbox(gpContent, "enable ready glow", function()
        if panel.readyGlow == nil then panel.readyGlow = true end
        return panel.readyGlow
    end, function(v)
        panel.readyGlow = v
        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        sfui.trackedoptions.UpdatePreview()
    end)
    glowCBC:SetPoint("TOPLEFT", 5, gy)
    gy = gy - 25

    local desatCBC = sfui.common.create_checkbox(gpContent, "desaturate on cooldown", function()
        if panel.cooldownDesat == nil then panel.cooldownDesat = true end
        return panel.cooldownDesat
    end, function(v)
        panel.cooldownDesat = v
        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
    end)
    desatCBC:SetPoint("TOPLEFT", 5, gy)
    gy = gy - 25

    local alphaSliderC = sfui.common.create_slider_input(gpContent, "cooldown alpha",
        function() return panel.cooldownAlpha end, 0, 1, 0.05, function(v)
            panel.cooldownAlpha = v
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end)
    alphaSliderC:SetPoint("TOPLEFT", 5, gy); alphaSliderC:SetSliderValue(panel.cooldownAlpha or 1.0)
    gy = gy - 40

    local glowTypes = { "blizzard", "pixel", "autocast" }
    local typeBtnC = CreateFlatButton(gpContent, "glow type: " .. (panel.glowType or "blizzard"), 160, 20)
    typeBtnC:SetPoint("TOPLEFT", 5, gy)
    typeBtnC:SetScript("OnClick", function(self)
        local cur = panel.glowType or "blizzard"
        local found = 1
        for i, t in ipairs(glowTypes) do
            if t == cur then
                found = i; break
            end
        end
        local nextIdx = (found % #glowTypes) + 1
        panel.glowType = glowTypes[nextIdx]
        self:SetText("glow type: " .. panel.glowType)
        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        sfui.trackedoptions.UpdatePreview()
    end)
    gy = gy - 25

    local colorLabelG = AddGeneralLabel("glow color")
    local colorSwatchG = sfui.common.create_color_swatch(gpContent, panel.glowColor or { r = 1, g = 1, b = 0 },
        function(r, g, b)
            panel.glowColor = { r = r, g = g, b = b }
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
            sfui.trackedoptions.UpdatePreview()
        end)
    colorSwatchG:SetPoint("LEFT", colorLabelG, "RIGHT", 10, 0)
    gy = gy - 10

    local scaleSliderG = sfui.common.create_slider_input(gpContent, "glow scale",
        function() return panel.glowScale end, 0.5, 2.0, 0.1, function(v)
            panel.glowScale = v
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
            sfui.trackedoptions.UpdatePreview()
        end)
    scaleSliderG:SetPoint("TOPLEFT", 5, gy); scaleSliderG:SetSliderValue(panel.glowScale or 1.0)
    gy = gy - 40

    local intensitySliderG = sfui.common.create_slider_input(gpContent, "glow intensity",
        function() return panel.glowIntensity end, 0.1, 2.0, 0.1, function(v)
            panel.glowIntensity = v
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
            sfui.trackedoptions.UpdatePreview()
        end)
    intensitySliderG:SetPoint("TOPLEFT", 5, gy); intensitySliderG:SetSliderValue(panel.glowIntensity or 1.0)
    gy = gy - 40

    local speedSliderG = sfui.common.create_slider_input(gpContent, "glow speed",
        function() return panel.glowSpeed end, -1, 1, 0.05, function(v)
            panel.glowSpeed = v
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
            sfui.trackedoptions.UpdatePreview()
        end)
    speedSliderG:SetPoint("TOPLEFT", 5, gy); speedSliderG:SetSliderValue(panel.glowSpeed or 0.25)
    gy = gy - 40

    gpContent:SetHeight(math.abs(gy) + 20)
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
