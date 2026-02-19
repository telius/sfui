local addonName, addon = ...
local CreateFrame = CreateFrame
sfui = sfui or {}
sfui.trackedoptions = {}

local CreateFlatButton = sfui.common.create_flat_button
local g = sfui.config
local c = g.options_panel

-- Forward declarations
local select_tab
local UpdateCooldownsList
local wipe = wipe
local tinsert = tinsert
local _emptyTable = {}
local glowTypes = {
    { text = "Pixel",    value = "pixel" },
    { text = "Autocast", value = "autocast" },
    { text = "Proc",     value = "proc" },
    { text = "Button",   value = "button" }
}
local ReloadUI = ReloadUI or C_UI.Reload
local C_AddOns = C_AddOns

-- Main Options Frame
local frame = CreateFrame("Frame", "SfuiCooldownsViewer", UIParent, "BackdropTemplate")
frame:SetSize(SfuiDB.trackedOptionsWindow and SfuiDB.trackedOptionsWindow.width or 800,
    SfuiDB.trackedOptionsWindow and SfuiDB.trackedOptionsWindow.height or 500)
frame:SetPoint("CENTER")
frame:SetFrameStrata("HIGH")
frame:SetToplevel(true)
frame:EnableMouse(true)
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    -- Save Size
    if not SfuiDB.trackedOptionsWindow then SfuiDB.trackedOptionsWindow = {} end
    SfuiDB.trackedOptionsWindow.width = self:GetWidth()
    SfuiDB.trackedOptionsWindow.height = self:GetHeight()
end)

-- Make resizable
frame:SetResizable(true)
frame:SetResizeBounds(600, 400, 1200, 800)
local resizeBtn = CreateFrame("Button", nil, frame)
resizeBtn:SetSize(16, 16)
resizeBtn:SetPoint("BOTTOMRIGHT")
resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
resizeBtn:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
resizeBtn:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    if not SfuiDB.trackedOptionsWindow then SfuiDB.trackedOptionsWindow = {} end
    SfuiDB.trackedOptionsWindow.width = frame:GetWidth()
    SfuiDB.trackedOptionsWindow.height = frame:GetHeight()
end)

frame:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8X8",
    edgeFile = "Interface/Buttons/WHITE8X8",
    edgeSize = 1,
})
frame:SetBackdropColor(c.backdrop_color[1], c.backdrop_color[2], c.backdrop_color[3], c.backdrop_color[4])
frame:SetBackdropBorderColor(0, 0, 0, 1)
frame:Hide()
tinsert(UISpecialFrames, "SfuiCooldownsViewer")

-- (Title removed for better space efficiency)

local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", -5, -5)

-- === UX Section Container ===
-- Creates a visually distinct section with dark bg, purple left accent, title, and content area.
-- Returns (section, contentFrame, sectionHeight) where contentFrame is the inner area for child widgets.
local function CreateSection(parent, title, subtitle, yOffset, width)
    local PADDING = 10
    local ACCENT_W = 3
    local TITLE_H = 18
    local SUB_H = subtitle and 14 or 0
    local HEADER_H = PADDING + TITLE_H + (SUB_H > 0 and (SUB_H + 4) or 0) + 4

    local section = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    section:SetPoint("TOPLEFT", 0, yOffset)
    section:SetWidth(width or (parent:GetWidth() - 20))
    section:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
    })
    section:SetBackdropColor(0.06, 0.06, 0.06, 0.9)

    -- Purple left accent stripe
    local accent = section:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMLEFT", 0, 0)
    accent:SetWidth(ACCENT_W)
    accent:SetColorTexture(0.4, 0, 1, 1) -- #6600FF

    -- Title
    local titleFS = section:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFS:SetPoint("TOPLEFT", ACCENT_W + PADDING, -PADDING)
    titleFS:SetTextColor(0.4, 0, 1, 1) -- Purple accent
    titleFS:SetText(title or "")

    -- Subtitle (optional dim description)
    if subtitle then
        local subFS = section:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        subFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -4)
        subFS:SetTextColor(0.5, 0.5, 0.5, 1)
        subFS:SetText(subtitle)
    end

    -- Content frame (where child widgets go) - fills section body
    local content = CreateFrame("Frame", nil, section)
    content:SetPoint("TOPLEFT", ACCENT_W + PADDING, -HEADER_H)
    content:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)
    section.content = content
    section._headerH = HEADER_H

    -- Auto-sizing: call section:SetHeight() after adding children
    return section, content, HEADER_H
end

-- Tactical UI Helpers
local function CreateAnchorGrid(parent, panel, key, onUpdate)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(75, 75)

    local points = {
        { "TOPLEFT",    "TOP",    "TOPRIGHT" },
        { "LEFT",       "CENTER", "RIGHT" },
        { "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
    }

    container.btns = {}
    for r, row in ipairs(points) do
        for c, point in ipairs(row) do
            local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
            btn:SetSize(22, 22)
            btn:SetPoint("TOPLEFT", (c - 1) * 25, -(r - 1) * 25)
            btn:SetBackdrop({
                bgFile = "Interface/Buttons/WHITE8X8",
                edgeFile = "Interface/Buttons/WHITE8X8",
                edgeSize = 1,
            })
            btn:SetBackdropColor(0.1, 0.1, 0.1, 1)
            btn:SetBackdropBorderColor(0, 0, 0, 1)

            btn.point = point
            btn:SetScript("OnClick", function()
                panel[key] = point
                for _, b in ipairs(container.btns) do
                    if b.point == panel[key] then
                        b:SetBackdropBorderColor(0, 1, 1, 1)
                        b:SetBackdropColor(0.2, 0.2, 0.2, 1)
                    else
                        b:SetBackdropBorderColor(0, 0, 0, 1)
                        b:SetBackdropColor(0.1, 0.1, 0.1, 1)
                    end
                end
                if onUpdate then onUpdate() end
            end)

            if panel[key] == point then
                btn:SetBackdropBorderColor(0, 1, 1, 1)
                btn:SetBackdropColor(0.2, 0.2, 0.2, 1)
            end
            table.insert(container.btns, btn)
        end
    end
    return container
end

local function CreateGrowthCross(parent, panel, onUpdate)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(75, 75)

    local btns = {
        { point = "Up",     x = 25, y = 0,   label = "U" },
        { point = "Left",   x = 0,  y = -25, label = "L" },
        { point = "Center", x = 25, y = -25, label = "C" },
        { point = "Right",  x = 50, y = -25, label = "R" },
        { point = "Down",   x = 25, y = -50, label = "D" }
    }

    container.btnRefs = {}
    for _, info in ipairs(btns) do
        local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
        btn:SetSize(22, 22)
        btn:SetPoint("TOPLEFT", info.x, info.y)
        btn:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8X8",
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0.1, 0.1, 0.1, 1)
        btn:SetBackdropBorderColor(0, 0, 0, 1)

        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER")
        text:SetText(info.label)

        btn.growth = info.point
        btn:SetScript("OnClick", function()
            if info.point == "Up" or info.point == "Down" then
                panel.growthV = info.point
            else
                panel.growthH = info.point
            end

            for _, b in ipairs(container.btnRefs) do
                local active = false
                if b.growth == "Up" or b.growth == "Down" then
                    active = (panel.growthV == b.growth)
                else
                    active = (panel.growthH == b.growth)
                end

                if active then
                    b:SetBackdropBorderColor(0, 1, 1, 1)
                    b:SetBackdropColor(0.2, 0.2, 0.2, 1)
                else
                    b:SetBackdropBorderColor(0, 0, 0, 1)
                    b:SetBackdropColor(0.1, 0.1, 0.1, 1)
                end
            end
            if onUpdate then onUpdate() end
        end)

        local active = false
        if info.point == "Up" or info.point == "Down" then
            active = (panel.growthV == info.point)
        else
            active = (panel.growthH == info.point)
        end
        if active then
            btn:SetBackdropBorderColor(0, 1, 1, 1)
            btn:SetBackdropColor(0.2, 0.2, 0.2, 1)
        end
        table.insert(container.btnRefs, btn)
    end
    return container
end

-- Top Left Buttons (Options & Blizzard)
local headerBtnX = 140
local optBtn = CreateFlatButton(frame, "Main Options", 100, 20)
optBtn:SetPoint("TOPLEFT", 10, -5)
optBtn:SetScript("OnClick", function()
    if sfui.toggle_options_panel then
        sfui.toggle_options_panel()

        -- Attach logic
        if sfui_options_frame and sfui_options_frame:IsShown() then
            SfuiCooldownsViewer:ClearAllPoints()
            SfuiCooldownsViewer:SetPoint("CENTER") -- Back to center default before re-anchoring if needed

            sfui_options_frame:ClearAllPoints()
            sfui_options_frame:SetPoint("TOPRIGHT", SfuiCooldownsViewer, "TOPLEFT", -5, 0)
        end
    end
end)

local blizzBtn = CreateFlatButton(frame, "Blizzard Manager", 120, 20)
blizzBtn:SetPoint("LEFT", optBtn, "RIGHT", 5, 0)
blizzBtn:SetScript("OnClick", function()
    if CooldownViewerSettings then
        if CooldownViewerSettings:IsShown() then
            HideUIPanel(CooldownViewerSettings)
        else
            ShowUIPanel(CooldownViewerSettings)
        end
    end
end)


-- Tab logic
select_tab = function(frame, id)
    if not frame.tabs then return end
    for i, tab in ipairs(frame.tabs) do
        local btn = tab.button
        if i == id then
            -- Selected state
            tab.panel:Show()
            btn.text:SetTextColor(g.colors.cyan[1], g.colors.cyan[2], g.colors.cyan[3])
            -- btn:SetBackdropColor(c.tabs.selected_color[1], c.tabs.selected_color[2], c.tabs.selected_color[3], 0.2)
        else
            -- Deselected state
            tab.panel:Hide()
            btn.text:SetTextColor(g.colors.purple[1], g.colors.purple[2], g.colors.purple[3])
            -- btn:SetBackdropColor(0, 0, 0, 0)
        end
    end
    frame.selectedTabId = id
    SfuiDB.lastSelectedTabId = id -- Persist tab selection
end

function sfui.trackedoptions.toggle_viewer()
    local isShown = frame:IsShown()
    if not isShown then
        if not C_AddOns.IsAddOnLoaded("Blizzard_CooldownViewer") then
            C_AddOns.LoadAddOn("Blizzard_CooldownViewer")
        end
        frame:Show()
    else
        frame:Hide()
    end
end

-- Initialization
function sfui.trackedoptions.initialize()
    if not SfuiDB then SfuiDB = {} end
    if not SfuiDB.trackedBars then SfuiDB.trackedBars = {} end

    -- Load Saved Size
    if SfuiDB.trackedOptionsWindow then
        frame:SetSize(SfuiDB.trackedOptionsWindow.width, SfuiDB.trackedOptionsWindow.height)
    end

    -- Tab Container
    frame.tabs = {}
    local TAB_HEIGHT = 30
    local TAB_WIDTH = 120

    local g = sfui.config

    local lastBtn
    local function CreateTabButton(text, id)
        local btn = CreateFrame("Button", nil, frame, "BackdropTemplate")
        btn:SetSize(TAB_WIDTH, TAB_HEIGHT)
        btn:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8X8",
        })
        btn:SetBackdropColor(0, 0, 0, 0)

        local t = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
        t:SetPoint("CENTER")
        t:SetText(text)
        btn.text = t

        btn:SetScript("OnClick", function() select_tab(frame, id) end)

        -- Positioning
        if not lastBtn then
            btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -30)
        else
            btn:SetPoint("LEFT", lastBtn, "RIGHT", 5, 0)
        end
        lastBtn = btn

        return btn
    end

    -- Create Tabs
    local assignBtn   = CreateTabButton("Assignments", 1)
    local globalBtn   = CreateTabButton("Global", 2)
    local barsBtn     = CreateTabButton("Bars", 3)
    local iconsBtn    = CreateTabButton("Icons", 4)

    -- Content Panels
    local assignPanel = CreateFrame("Frame", "SfuiAssignmentsTab", frame)
    assignPanel:SetPoint("TOPLEFT", 10, -65)
    assignPanel:SetPoint("BOTTOMRIGHT", -10, 10)
    assignPanel:Hide()

    local globalPanel = CreateFrame("Frame", "SfuiGlobalTab", frame)
    globalPanel:SetPoint("TOPLEFT", 10, -65)
    globalPanel:SetPoint("BOTTOMRIGHT", -10, 10)
    globalPanel:Hide()

    local barsPanel = CreateFrame("Frame", "SfuiBarsTab", frame)
    barsPanel:SetPoint("TOPLEFT", 10, -65)
    barsPanel:SetPoint("BOTTOMRIGHT", -10, 10)
    barsPanel:Hide()

    local iconsPanel = CreateFrame("Frame", "SfuiIconsTab", frame)
    iconsPanel:SetPoint("TOPLEFT", 10, -65)
    iconsPanel:SetPoint("BOTTOMRIGHT", -10, 10)
    iconsPanel:Hide()

    -- Populate Tabs Table
    table.insert(frame.tabs, { button = assignBtn, panel = assignPanel })
    table.insert(frame.tabs, { button = globalBtn, panel = globalPanel })
    table.insert(frame.tabs, { button = barsBtn, panel = barsPanel })
    table.insert(frame.tabs, { button = iconsBtn, panel = iconsPanel })

    -- === TAB 1: ASSIGNMENTS (CDM) ===
    if sfui.cdm and sfui.cdm.create_panel then
        sfui.cdm.create_panel(assignPanel)
    end

    -- === TAB 2: GLOBAL SETTINGS ===
    local globScroll = CreateFrame("ScrollFrame", "SfuiGlobalScroll", globalPanel, "UIPanelScrollFrameTemplate")
    globScroll:SetPoint("TOPLEFT", 0, 0)
    globScroll:SetPoint("BOTTOMRIGHT", -25, 0)
    local globContent = CreateFrame("Frame", nil, globScroll)
    globContent:SetSize(750, 800)
    globScroll:SetScrollChild(globContent)
    sfui.trackedoptions.globContent = globContent

    local resetGlobalBtn = CreateFlatButton(globContent, "reset defaults", 100, 22)
    resetGlobalBtn:SetPoint("TOPRIGHT", globContent, "TOPRIGHT", -10, -10)
    resetGlobalBtn:SetScript("OnClick", function()
        if SfuiDB.iconGlobalSettings then wipe(SfuiDB.iconGlobalSettings) end
        sfui.trackedoptions.UpdateSettings() -- Re-init widgets
        if sfui.trackedicons and sfui.trackedicons.ForceRefreshGlows then sfui.trackedicons.ForceRefreshGlows() end
        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
    end)


    -- === TAB 3: BARS SETTINGS ===
    local barsScroll = CreateFrame("ScrollFrame", "SfuiBarsScroll", barsPanel, "UIPanelScrollFrameTemplate")
    barsScroll:SetPoint("TOPLEFT", 0, 0)
    barsScroll:SetPoint("BOTTOMRIGHT", -25, 0)
    local barsContent = CreateFrame("Frame", nil, barsScroll)
    barsContent:SetSize(750, 600)
    barsScroll:SetScrollChild(barsContent)

    -- Update Bars Panel when shown
    barsPanel:SetScript("OnShow", function()
        sfui.trackedoptions.UpdateBarsPanel(barsContent)
    end)


    -- === TAB 4: ICONS SETTINGS (PANELS) ===
    local iconsScroll = CreateFrame("ScrollFrame", "SfuiIconsScroll", iconsPanel, "UIPanelScrollFrameTemplate")
    iconsScroll:SetPoint("TOPLEFT", 0, 0)
    iconsScroll:SetPoint("BOTTOMRIGHT", -25, 40)
    local iconsContent = CreateFrame("Frame", nil, iconsScroll)
    iconsContent:SetSize(750, 1000)
    iconsScroll:SetScrollChild(iconsContent)
    sfui.trackedoptions.gpContent = iconsContent -- Alias for existing editor code

    local addPanelBtn = CreateFlatButton(iconsPanel, "New Panel", 90, 22)
    addPanelBtn:SetPoint("BOTTOMLEFT", 10, 10)
    addPanelBtn:SetScript("OnClick", function()
        local idx = sfui.common.add_custom_panel("New Panel")
        if idx then
            if sfui.cdm and sfui.cdm.RefreshZones then sfui.cdm.RefreshZones() end
            sfui.trackedoptions.selectedPanelIndex = idx
            sfui.trackedoptions.UpdateEditor()
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end
    end)

    local reloadBtn = CreateFlatButton(iconsPanel, "Save/Reload", 90, 22)
    reloadBtn:SetPoint("LEFT", addPanelBtn, "RIGHT", 10, 0)
    reloadBtn:SetScript("OnClick", ReloadUI)


    -- Initialize Default Selection
    sfui.trackedoptions.selectedPanelIndex = 1

    -- Initialize Editor (for Tabs 2 and 4)
    sfui.trackedoptions.UpdateEditor()


    frame:SetScript("OnShow", function()
        if InCombatLockdown() then
            print("|cffFF0000SFUI:|r Cannot configure tracked bars in combat.")
            frame:Hide()
            return
        end
        local startTab = SfuiDB.lastSelectedTabId or 1
        -- Ensure valid range
        if startTab < 1 or startTab > 4 then startTab = 1 end
        select_tab(frame, startTab)

        if not C_AddOns.IsAddOnLoaded("Blizzard_CooldownViewer") then C_AddOns.LoadAddOn("Blizzard_CooldownViewer") end
    end)
end

function sfui.trackedoptions.UpdateBarsPanel(content)
    if not content then return end

    -- Clear existing widgets for full rebuild
    local kids = { content:GetChildren() }
    for _, kid in ipairs(kids) do kid:Hide() end
    local regions = { content:GetRegions() }
    for _, region in ipairs(regions) do region:Hide() end

    SfuiDB.trackedBars = SfuiDB.trackedBars or {}
    local db = SfuiDB.trackedBars
    local yPos = -10
    local SEC_W = 460

    -- === Section 1: Visibility ===
    local sec1, sec1c, h1 = CreateSection(content, "Visibility", "Hide bars based on player state.", yPos, SEC_W)
    local s1y = 0

    local cbOOC = sfui.common.create_checkbox(sec1c, "Hide OOC Bars", function() return db.hideOOC end,
        function(checked)
            db.hideOOC = checked
            if sfui.trackedbars and sfui.trackedbars.UpdateVisibility then sfui.trackedbars.UpdateVisibility() end
        end, "Hide the bars container when you are not in combat.")
    cbOOC:SetPoint("TOPLEFT", 0, s1y)
    s1y = s1y - 28

    local cbInactive = sfui.common.create_checkbox(sec1c, "Hide Inactive Bars", function() return db.hideInactive end,
        function(checked)
            db.hideInactive = checked
            if sfui.trackedbars and sfui.trackedbars.UpdateVisibility then sfui.trackedbars.UpdateVisibility() end
        end, "Hide bars that are not currently tracking an active cooldown.")
    cbInactive:SetPoint("TOPLEFT", 0, s1y)
    s1y = s1y - 10

    sec1:SetHeight(h1 + math.abs(s1y) + 10) -- header + content + padding
    yPos = yPos - sec1:GetHeight() - 12

    -- === Section 2: Position & Size ===
    local sec2, sec2c, h2 = CreateSection(content, "Position & Size", "Adjust bar container position and dimensions.",
        yPos,
        SEC_W)
    local s2y = 0

    if not db.anchor then db.anchor = { x = 0, y = 0 } end

    -- Row 1: X / Y side by side
    local sliderX = sfui.common.create_slider_input(sec2c, "X Position", function() return db.anchor.x end, -1000, 1000,
        1, function(value)
            db.anchor.x = value
            if sfui.trackedbars and sfui.trackedbars.ForceLayoutUpdate then sfui.trackedbars.ForceLayoutUpdate() end
        end)
    sliderX:SetWidth(200)
    sliderX:SetPoint("TOPLEFT", 0, s2y)

    local sliderY = sfui.common.create_slider_input(sec2c, "Y Position", function() return db.anchor.y end, -1000, 1000,
        1, function(value)
            db.anchor.y = value
            if sfui.trackedbars and sfui.trackedbars.ForceLayoutUpdate then sfui.trackedbars.ForceLayoutUpdate() end
        end)
    sliderY:SetWidth(200)
    sliderY:SetPoint("TOPLEFT", 220, s2y)
    s2y = s2y - 50

    -- Row 2: Width / Height side by side
    local sliderW = sfui.common.create_slider_input(sec2c, "Width", function() return db.width or 200 end, 50, 400, 1,
        function(value)
            db.width = value
            if sfui.trackedbars and sfui.trackedbars.ForceLayoutUpdate then sfui.trackedbars.ForceLayoutUpdate() end
        end)
    sliderW:SetWidth(200)
    sliderW:SetPoint("TOPLEFT", 0, s2y)

    local sliderH = sfui.common.create_slider_input(sec2c, "Height", function() return db.height or 20 end, 10, 50, 1,
        function(value)
            db.height = value
            if sfui.trackedbars and sfui.trackedbars.ForceLayoutUpdate then sfui.trackedbars.ForceLayoutUpdate() end
        end)
    sliderH:SetWidth(200)
    sliderH:SetPoint("TOPLEFT", 220, s2y)
    s2y = s2y - 50

    sec2:SetHeight(h2 + math.abs(s2y) + 10)
    yPos = yPos - sec2:GetHeight() - 12

    -- === Section 3: Appearance ===
    local sec3, sec3c, h3 = CreateSection(content, "Appearance", "Customize bar colors and style. (Coming soon)", yPos,
        SEC_W)

    local placeholder = sec3c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    placeholder:SetPoint("TOPLEFT", 0, 0)
    placeholder:SetTextColor(0.4, 0.4, 0.4, 1)
    placeholder:SetText("Per-bar color customization will be available in a future update.")

    sec3:SetHeight(h3 + 20 + 10)
    yPos = yPos - sec3:GetHeight() - 12
end

-- === SETTINGS GENERATORS ===

function sfui.trackedoptions.UpdateEditor()
    if sfui.trackedoptions.globContent then
        sfui.trackedoptions.GenerateGlobalSettingsControls(sfui.trackedoptions.globContent)
    end
    if sfui.trackedoptions.gpContent then
        sfui.trackedoptions.GenerateGlobalIconsControls(sfui.trackedoptions.gpContent)
    end
end

function sfui.trackedoptions.GenerateGlobalSettingsControls(parent)
    if not parent then return end

    -- Clear frames and regions to prevent font string accumulation
    if sfui.trackedoptions.ReleaseSettingsWidgets then
        sfui.trackedoptions.ReleaseSettingsWidgets(parent)
    else
        local kids = { parent:GetChildren() }
        for _, kid in ipairs(kids) do kid:Hide() end
    end
    local regions = { parent:GetRegions() }
    for _, region in ipairs(regions) do region:Hide() end

    SfuiDB.iconGlobalSettings = SfuiDB.iconGlobalSettings or {}
    local igs = SfuiDB.iconGlobalSettings
    local defaults = sfui.config.icon_panel_global_defaults
    local yPos = -10
    local SEC_W = 520

    -- Global Glow Preview Logic
    local function UpdateGlobalGlowPreview()
        local pf = parent.glowPreview
        if not pf or not pf.icon then return end

        -- Use shared resolver for perfect parity with active icons
        local config = sfui.glows.resolve_config(nil, igs)

        -- Resolve the toggle state (not handled by the visual resolver)
        local isEnabled = igs.readyGlow
        if isEnabled == nil then isEnabled = defaults.readyGlow end

        if isEnabled then
            sfui.glows.start_glow(pf.icon, config)
        else
            sfui.glows.stop_glow(pf.icon)
        end
    end

    local function UpdateAll()
        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        UpdateGlobalGlowPreview()
    end

    -- Reusable factories scoped to current section content frame
    local function MakeCheck(secContent, label, key, tooltip, x, y)
        local cb = sfui.common.create_checkbox(secContent, label, function()
            if igs[key] ~= nil then return igs[key] else return defaults[key] end
        end, function(val)
            igs[key] = val
            UpdateAll()
        end, tooltip)
        cb:SetPoint("TOPLEFT", x or 0, y)
        return cb
    end

    local function MakeSlider(secContent, label, key, minVal, maxVal, step, x, y, w)
        local s = sfui.common.create_slider_input(secContent, label, function()
            if igs[key] ~= nil then return igs[key] else return defaults[key] end
        end, minVal, maxVal, step or 1, function(val)
            igs[key] = val
            UpdateAll()
        end)
        if w then s:SetWidth(w) end
        s:SetPoint("TOPLEFT", x or 0, y)
        return s
    end

    -- ═══════════════════════════════════
    -- SECTION 1: GLOW EFFECTS
    -- ═══════════════════════════════════
    local sec1, s1c, h1 = CreateSection(parent, "Glow Effects", "Configure the ready glow animation on icons.", yPos,
        SEC_W)
    local s1y = 0

    MakeCheck(s1c, "Enable Ready Glow", "readyGlow", "Play a glow effect when a cooldown finishes.", 0, s1y)
    MakeCheck(s1c, "Use Spec Color", "useSpecColor", "Use specialization-based color for glows.", 240, s1y)
    s1y = s1y - 30

    -- Glow Type & Color inline
    local lGT = s1c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lGT:SetPoint("TOPLEFT", 0, s1y); lGT:SetText("Type:")
    local gtDropDown = sfui.common.create_dropdown(s1c, 100, glowTypes, function(val)
        igs.glowType = val
        UpdateAll()
    end)
    gtDropDown:SetPoint("LEFT", lGT, "RIGHT", 5, 0)

    local lGC = s1c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lGC:SetPoint("LEFT", gtDropDown, "RIGHT", 15, 0); lGC:SetText("Color:")
    local gcSwatch = sfui.common.create_color_swatch(s1c, igs.glowColor or defaults.glowColor, function(r, g, b)
        igs.glowColor = { r, g, b, 1 }
        UpdateAll()
    end)
    gcSwatch:SetPoint("LEFT", lGC, "RIGHT", 5, 0)
    s1y = s1y - 35

    -- Sliders in 2-column grid
    MakeSlider(s1c, "Duration (max)", "glow_max_duration", 1, 30, 0.5, 0, s1y, 230)
    MakeSlider(s1c, "Scale", "glowScale", 0.5, 3.0, 0.1, 250, s1y, 230)
    s1y = s1y - 48
    MakeSlider(s1c, "Intensity", "glowIntensity", 0.1, 2.0, 0.1, 0, s1y, 230)
    MakeSlider(s1c, "Speed", "glowSpeed", 0.1, 2.0, 0.1, 250, s1y, 230)
    s1y = s1y - 48
    MakeSlider(s1c, "Lines (Pixel)", "glowLines", 1, 10, 1, 0, s1y, 150)
    MakeSlider(s1c, "Particles", "glowParticles", 1, 10, 1, 170, s1y, 150)
    MakeSlider(s1c, "Thickness", "glowThickness", 1, 5, 1, 340, s1y, 140)
    s1y = s1y - 48

    sec1:SetHeight(h1 + math.abs(s1y) + 8)
    yPos = yPos - sec1:GetHeight() - 10

    -- ═══════════════════════════════════
    -- SECTION 2: VISUAL STATES
    -- ═══════════════════════════════════
    local sec2, s2c, h2 = CreateSection(parent, "Visual States", "How icons look when on cooldown or unusable.", yPos,
        SEC_W)
    local s2y = 0

    MakeCheck(s2c, "Desaturate on Cooldown", "cooldownDesat", "Turn icons black and white while on cooldown.", 0, s2y)
    MakeCheck(s2c, "Resource Check Tint", "useResourceCheck", "Tint icons blue when out of mana/power.", 240, s2y)
    s2y = s2y - 28
    MakeCheck(s2c, "Show Background", "showBackground", "Show a dark background behind the icon panel.", 0, s2y)
    s2y = s2y - 35

    MakeSlider(s2c, "Alpha on Cooldown", "alphaOnCooldown", 0, 1, 0.05, 0, s2y, 230)
    MakeSlider(s2c, "Background Alpha", "backgroundAlpha", 0, 1, 0.05, 250, s2y, 230)
    s2y = s2y - 48

    sec2:SetHeight(h2 + math.abs(s2y) + 8)
    yPos = yPos - sec2:GetHeight() - 10

    -- ═══════════════════════════════════
    -- SECTION 3: TEXT & MISC
    -- ═══════════════════════════════════
    local sec3, s3c, h3 = CreateSection(parent, "Text & Misc", "Countdown text, Masque support, and text color.", yPos,
        SEC_W)
    local s3y = 0

    MakeCheck(s3c, "Show Cooldown Text", "textEnabled", "Show the numerical countdown on icons.", 0, s3y)
    MakeCheck(s3c, "Enable Masque Support", "enableMasque", "Requires Masque addon and reload.", 240, s3y)
    s3y = s3y - 35

    local lTC = s3c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lTC:SetPoint("TOPLEFT", 0, s3y); lTC:SetText("Text Color:")
    local tcSwatch = sfui.common.create_color_swatch(s3c, igs.textColor or defaults.textColor, function(r, g, b)
        igs.textColor = { r, g, b, 1 }
        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
    end)
    tcSwatch:SetPoint("LEFT", lTC, "RIGHT", 5, 0)
    s3y = s3y - 28

    sec3:SetHeight(h3 + math.abs(s3y) + 8)
    yPos = yPos - sec3:GetHeight() - 10

    -- ═══════════════════════════════════
    -- SECTION 4: HOTKEYS & STYLE
    -- ═══════════════════════════════════
    local sec4, s4c, h4 = CreateSection(parent, "Hotkeys & Style", "Keybinding display and icon shape.", yPos, SEC_W)
    local s4y = 0

    MakeCheck(s4c, "Show Hotkeys", "showHotkeys", "Display keybinding text on icons.", 0, s4y)
    s4y = s4y - 35
    MakeSlider(s4c, "Hotkey Font Size", "hotkeyFontSize", 8, 24, 1, 0, s4y, 230)
    s4y = s4y - 48

    -- Hotkey Anchor & Outline dropdowns side by side
    local lHA = s4c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lHA:SetPoint("TOPLEFT", 0, s4y); lHA:SetText("Anchor:")
    local anchorOpts = {
        { text = "Top Left",     value = "TOPLEFT" },
        { text = "Top Right",    value = "TOPRIGHT" },
        { text = "Bottom Left",  value = "BOTTOMLEFT" },
        { text = "Bottom Right", value = "BOTTOMRIGHT" },
        { text = "Center",       value = "CENTER" },
    }
    local haDropDown = sfui.common.create_dropdown(s4c, 110, anchorOpts, function(val)
        igs.hotkeyAnchor = val
        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
    end)
    haDropDown:SetPoint("LEFT", lHA, "RIGHT", 5, 0)

    local lHO = s4c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lHO:SetPoint("LEFT", haDropDown, "RIGHT", 15, 0); lHO:SetText("Outline:")
    local outlineOpts = {
        { text = "Outline",       value = "OUTLINE" },
        { text = "Thick Outline", value = "THICKOUTLINE" },
        { text = "None",          value = "" },
    }
    local hoDropDown = sfui.common.create_dropdown(s4c, 110, outlineOpts, function(val)
        igs.hotkeyOutline = val
        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
    end)
    hoDropDown:SetPoint("LEFT", lHO, "RIGHT", 5, 0)
    s4y = s4y - 35

    -- Icon Style checkboxes
    MakeCheck(s4c, "Square Icons", "squareIcons", "Crop round icon edges to make them square.", 0, s4y)
    MakeCheck(s4c, "Show Border", "showBorder", "Show a 2px black border around each icon.", 240, s4y)
    s4y = s4y - 28

    sec4:SetHeight(h4 + math.abs(s4y) + 8)
    yPos = yPos - sec4:GetHeight() - 10

    -- ═══════════════════════════════════
    -- GLOW PREVIEW FRAME (Right Side)
    -- ═══════════════════════════════════
    if not parent.glowPreview then
        local pf = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        pf:SetSize(150, 150)
        pf:SetPoint("TOPLEFT", SEC_W + 30, -40)
        pf:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8X8",
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 1,
        })
        pf:SetBackdropColor(0, 0, 0, 0.5)
        pf:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

        local iconFrame = CreateFrame("Frame", nil, pf)
        iconFrame:SetSize(64, 64)
        iconFrame:SetPoint("CENTER")

        local tex = iconFrame:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture(sfui.config.appearance.addonIcon or "Interface/Icons/Spell_Holy_FlashHeal")

        pf.icon = iconFrame

        local label = pf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("BOTTOM", 0, 10)
        label:SetText("GLOW PREVIEW")

        parent.glowPreview = pf
    end
    parent.glowPreview:Show()
    UpdateGlobalGlowPreview()
end

local function CreatePreviewGrid(parent, panel)
    if not parent or not panel then return end

    -- Clear preview
    if parent.icons then
        for _, icon in pairs(parent.icons) do icon:Hide() end
    else
        parent.icons = {}
    end

    local numMockIcons = 12
    local size = panel.size or 40
    local spacing = panel.spacing or 2
    local numColumns = panel.columns or 4
    local growthH = panel.growthH or "Right"
    local growthV = panel.growthV or "Down"
    local spanWidth = panel.spanWidth

    -- Mock AutoSpan for preview (use parent width)
    if spanWidth then
        local targetWidth = parent:GetWidth() - 20
        local iconsPerRow = math.min(numColumns, numMockIcons)
        if iconsPerRow > 0 then
            local currentWidth = (iconsPerRow * size) + (math.max(0, iconsPerRow - 1) * spacing)
            if currentWidth < targetWidth then
                if iconsPerRow > 1 then spacing = (targetWidth - (iconsPerRow * size)) / (iconsPerRow - 1) end
            else
                size = (targetWidth - (math.max(0, iconsPerRow - 1) * spacing)) / iconsPerRow
            end
        end
    end

    local hSign = (growthH == "Left") and -1 or 1
    local vSign = (growthV == "Up") and 1 or -1

    for i = 1, numMockIcons do
        if not parent.icons[i] then
            parent.icons[i] = parent:CreateTexture(nil, "OVERLAY")
            parent.icons[i]:SetTexture("Interface\\Icons\\Spell_Holy_FlashHeal")
        end
        local icon = parent.icons[i]
        icon:Show()
        icon:SetSize(size, size)

        -- Mirror visual states in preview
        local mockOnCD = (i > (numMockIcons / 2))   -- Half icons "on cooldown"
        local useDesat = panel.cooldownDesat
        if useDesat == nil then useDesat = true end -- fallback same as icon_panel_global_defaults
        icon:SetDesaturated(mockOnCD and useDesat)

        local alpha = 1.0
        if mockOnCD then
            alpha = tonumber(panel.alphaOnCooldown) or 1.0
        end
        icon:SetAlpha(alpha)

        local col = (i - 1) % numColumns
        local row = math.floor((i - 1) / numColumns)

        icon:ClearAllPoints()
        if growthH == "Center" then
            local startIdx = row * numColumns + 1
            local endIdx = math.min((row + 1) * numColumns, numMockIcons)
            local numInRow = endIdx - startIdx + 1
            local colInRow = (i - 1) % numColumns
            local centerOffset = colInRow - (numInRow - 1) / 2
            icon:SetPoint("CENTER", parent, "CENTER", centerOffset * (size + spacing), -row * (size + spacing) * vSign)
        else
            icon:SetPoint("TOPLEFT", parent, "TOPLEFT", 10 + col * (size + spacing) * hSign,
                -10 + row * (size + spacing) * vSign)
        end
    end
end

function sfui.trackedoptions.GenerateGlobalIconsControls(parent)
    if not parent then return end

    -- Clear parent first
    local kids = { parent:GetChildren() }
    for _, kid in ipairs(kids) do kid:Hide() end
    local regions = { parent:GetRegions() }
    for _, region in ipairs(regions) do region:Hide() end

    local panels = sfui.common.get_cooldown_panels()
    local selIdx = sfui.trackedoptions.selectedPanelIndex or 1
    local panel = panels[selIdx]
    if not panel then return end

    -- SELF-HEALING: Reset corrupted alpha if detected
    if panel.alphaOnCooldown == 0 then
        panel.alphaOnCooldown = 1.0
    end

    -- 1. Navigation Pane (Left)
    if not parent.navFrame then
        parent.navFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        parent.navFrame:SetWidth(140)
        parent.navFrame:SetPoint("TOPLEFT", 0, 0)
        parent.navFrame:SetPoint("BOTTOMLEFT", 0, 0)
        parent.navFrame:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8" })
        parent.navFrame:SetBackdropColor(0, 0, 0, 0.3)
    end
    parent.navFrame:Show()

    -- Rebuild nav buttons (clear old first)
    local navKids = { parent.navFrame:GetChildren() }
    for _, kid in ipairs(navKids) do
        if kid ~= parent.delBtn then kid:Hide() end
    end

    local navY = -10
    for i, p in ipairs(panels) do
        local btn = sfui.common.create_styled_button(parent.navFrame, p.name or "Panel", 120, 22)
        btn:SetPoint("TOPLEFT", 10, navY)
        navY = navY - 25
        if i == selIdx then btn:SetBackdropBorderColor(0, 1, 1, 1) end
        btn:SetScript("OnClick", function()
            sfui.trackedoptions.selectedPanelIndex = i
            sfui.trackedoptions.GenerateGlobalIconsControls(parent)
        end)
    end

    -- 2. Settings Pane (Middle)
    if not parent.settingsScroll then
        local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 150, -10)
        scroll:SetPoint("BOTTOMRIGHT", -300, 10)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(330, 1600)
        scroll:SetScrollChild(content)
        parent.settingsScroll = scroll
        parent.settingsContent = content
    end
    parent.settingsScroll:Show()
    local content = parent.settingsContent
    local cKids = { content:GetChildren() }
    for _, kid in ipairs(cKids) do kid:Hide() end
    local cRegions = { content:GetRegions() }
    for _, region in ipairs(cRegions) do region:Hide() end

    local SEC_W = 310

    -- Reusable factories for panel-specific controls
    local function PCheck(secContent, label, key, tooltip, x, y)
        local cb = sfui.common.create_checkbox(secContent, label, function() return panel[key] end, function(val)
            panel[key] = val
            sfui.trackedoptions.UpdatePreview()
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end, tooltip)
        cb:SetPoint("TOPLEFT", x or 0, y)
        return cb
    end

    local function PSlider(secContent, label, key, minVal, maxVal, step, x, y, w)
        local s = sfui.common.create_slider_input(secContent, label, function()
            if panel[key] ~= nil then return panel[key] end
            local igs = SfuiDB.iconGlobalSettings or _emptyTable
            if igs[key] ~= nil then return igs[key] end
            local defaults = sfui.config.icon_panel_global_defaults or _emptyTable
            return defaults[key] or 0
        end, minVal, maxVal, step or 1, function(val)
            panel[key] = val
            sfui.trackedoptions.UpdatePreview()
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        end)
        if w then s:SetWidth(w) end
        s:SetPoint("TOPLEFT", x or 0, y)
        return s
    end

    local yPos = -5

    -- ═══════════════════════════════════
    -- SECTION 1: GENERAL
    -- ═══════════════════════════════════
    local sec1, s1c, h1 = CreateSection(content, panel.name or "Panel", "Enable, size, and visibility mode.", yPos, SEC_W)
    local s1y = 0

    PCheck(s1c, "Enabled", "enabled", "Enable or disable this icon panel.", 0, s1y)
    PSlider(s1c, "Icon Size", "size", 10, 100, 1, 150, s1y, 140)
    s1y = s1y - 48

    local lVis = s1c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lVis:SetPoint("TOPLEFT", 0, s1y); lVis:SetText("Visibility:")
    local visOpts = {
        { text = "Always Show",   value = "always" },
        { text = "Combat Only",   value = "combat" },
        { text = "Out of Combat", value = "noCombat" },
    }
    local visDropDown = sfui.common.create_dropdown(s1c, 130, visOpts, function(val)
        panel.visibility = val
        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
    end)
    visDropDown:SetPoint("LEFT", lVis, "RIGHT", 5, 0)
    s1y = s1y - 35

    sec1:SetHeight(h1 + math.abs(s1y) + 10)
    yPos = yPos - sec1:GetHeight() - 8

    -- ═══════════════════════════════════
    -- SECTION 2: LAYOUT
    -- ═══════════════════════════════════
    local sec2, s2c, h2 = CreateSection(content, "Layout", "Grid size, spacing, and growth direction.", yPos, SEC_W)
    local s2y = 0

    PSlider(s2c, "Spacing", "spacing", -20, 40, 1, 0, s2y, 140)
    PSlider(s2c, "Columns", "columns", 1, 20, 1, 155, s2y, 140)
    s2y = s2y - 48

    PCheck(s2c, "Span Width", "spanWidth", "Auto-scale icons to fill the target frame width.", 0, s2y)
    s2y = s2y - 35

    -- Growth & Anchor widgets side by side
    local lG = s2c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lG:SetPoint("TOPLEFT", 0, s2y); lG:SetText("Growth:")
    local lAP = s2c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lAP:SetPoint("TOPLEFT", 130, s2y); lAP:SetText("Anchor Point:")
    s2y = s2y - 18

    local growthCross = CreateGrowthCross(s2c, panel, function()
        sfui.trackedoptions.UpdatePreview()
        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
    end)
    growthCross:SetPoint("TOPLEFT", 0, s2y)

    local anchorGrid = CreateAnchorGrid(s2c, panel, "anchorPoint", function()
        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
    end)
    anchorGrid:SetPoint("TOPLEFT", 130, s2y)
    s2y = s2y - 85

    sec2:SetHeight(h2 + math.abs(s2y) + 8)
    yPos = yPos - sec2:GetHeight() - 8

    -- ═══════════════════════════════════
    -- SECTION 3: ANCHORING
    -- ═══════════════════════════════════
    local sec3, s3c, h3 = CreateSection(content, "Anchoring", "Where this panel attaches and its offset.", yPos, SEC_W)
    local s3y = 0

    local lA = s3c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lA:SetPoint("TOPLEFT", 0, s3y); lA:SetText("Anchor To:")
    local anchorTargets = sfui.common.get_all_anchor_targets(panel.name)
    local anchorTo = sfui.common.create_dropdown(s3c, 130, anchorTargets, function(val)
        panel.anchorTo = val
        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
    end)
    anchorTo:SetPoint("LEFT", lA, "RIGHT", 5, 0)

    local lRP = s3c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lRP:SetPoint("TOPLEFT", 0, s3y - 30); lRP:SetText("Relative Pt:")
    local points = {
        { text = "Top",  value = "TOP" }, { text = "Bottom", value = "BOTTOM" },
        { text = "Left", value = "LEFT" }, { text = "Right", value = "RIGHT" },
        { text = "Center",   value = "CENTER" }, { text = "TopLeft", value = "TOPLEFT" },
        { text = "TopRight", value = "TOPRIGHT" }, { text = "BottomLeft", value = "BOTTOMLEFT" },
        { text = "BottomRight", value = "BOTTOMRIGHT" }
    }
    local rPoint = sfui.common.create_dropdown(s3c, 130, points, function(val)
        panel.relativePoint = val
        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
    end)
    rPoint:SetPoint("LEFT", lRP, "RIGHT", 5, 0)
    s3y = s3y - 65

    PSlider(s3c, "Offset X", "x", -1000, 1000, 1, 0, s3y, 140)
    PSlider(s3c, "Offset Y", "y", -1000, 1000, 1, 155, s3y, 140)
    s3y = s3y - 48

    sec3:SetHeight(h3 + math.abs(s3y) + 8)
    yPos = yPos - sec3:GetHeight() - 8

    -- 3. Preview Pane (Right)
    if not parent.previewFrame then
        parent.previewFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        parent.previewFrame:SetSize(280, 280)
        parent.previewFrame:SetPoint("TOPRIGHT", -10, -40)
        parent.previewFrame:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8X8",
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 1,
        })
        parent.previewFrame:SetBackdropColor(0, 0, 0, 0.5)
        parent.previewFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

        local pl = parent.previewFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pl:SetPoint("BOTTOM", 0, 5); pl:SetText("LIVE PREVIEW")
    end
    parent.previewFrame:Show()
    sfui.trackedoptions.UpdatePreview = function() CreatePreviewGrid(parent.previewFrame, panel) end
    sfui.trackedoptions.UpdatePreview()

    -- 4. Delete Panel Button (Bottom of Nav)
    if not parent.delBtn then
        parent.delBtn = sfui.common.create_styled_button(parent.navFrame, "Delete Panel", 120, 22)
        parent.delBtn:SetPoint("BOTTOM", parent.navFrame, "BOTTOM", 0, 10)
        parent.delBtn:SetBackdropColor(0.5, 0, 0, 1)
    end
    parent.delBtn:Show()
    parent.delBtn:SetScript("OnClick", function()
        local isBuiltIn = (panel.name == "CENTER" or panel.name == "UTILITY" or panel.name == "Left" or panel.name == "Right")
        if isBuiltIn then
            print("|cffFF0000SFUI:|r Cannot delete built-in panels.")
            return
        end
        if sfui.common.delete_custom_panel(selIdx) then
            sfui.trackedoptions.selectedPanelIndex = 1
            sfui.trackedoptions.GenerateGlobalIconsControls(parent)
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
            if sfui.cdm and sfui.cdm.RefreshZones then sfui.cdm.RefreshZones() end
        end
    end)
end

function sfui.trackedoptions.ReleaseSettingsWidgets(parent)
    if not parent then return end
    local kids = { parent:GetChildren() }
    for _, kid in ipairs(kids) do
        kid:Hide()
    end
    local regions = { parent:GetRegions() }
    for _, region in ipairs(regions) do
        region:Hide()
    end
end
