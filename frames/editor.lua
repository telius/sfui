local addonName, addon = ...
sfui.editor = {}

-- Cached Variables
local editorFrame
local panelScroll, panelContent
local rightScroll, rightContent
local previewFrame
local selectedPanelIndex = 1
local selectedEntryIndex = nil

local function CreateEditorFrame()
    if editorFrame then return editorFrame end

    local f = CreateFrame("Frame", "SfuiEditorFrame", UIParent, "BackdropTemplate")
    f:SetSize(800, 500)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")

    -- Backdrop
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    f:SetBackdropBorderColor(0, 0, 0, 1)

    -- Title
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 10, -10)
    f.title:SetText("SFUI Cooldown Editor")

    -- Close Button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Layout Columns

    -- === LEFT: Panel List (200px) ===
    local leftPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    leftPanel:SetPoint("TOPLEFT", 10, -40)
    leftPanel:SetPoint("BOTTOMLEFT", 10, 10)
    leftPanel:SetWidth(180)
    leftPanel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    leftPanel:SetBackdropColor(0.2, 0.2, 0.2, 0.5)
    leftPanel:SetBackdropBorderColor(0, 0, 0, 1)

    -- ScrollFrame for Panel List
    local scrollFrame = CreateFrame("ScrollFrame", nil, leftPanel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -25, 30) -- Leave room for buttons
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)
    panelScroll = scrollFrame
    panelContent = content

    -- Add Panel Button
    local addBtn = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    addBtn:SetPoint("BOTTOMLEFT", 5, 5)
    addBtn:SetSize(80, 22)
    addBtn:SetText("Add Panel")
    addBtn:SetScript("OnClick", function()
        if not SfuiDB.cooldownPanels then SfuiDB.cooldownPanels = {} end
        table.insert(SfuiDB.cooldownPanels, {
            name = "New Panel " .. (#SfuiDB.cooldownPanels + 1),
            enabled = true,
            entries = {},
            size = 40,
            spacing = 5,
            point = "CENTER",
            x = 0,
            y = 0
        })
        sfui.editor.UpdatePanelList()
        sfui.trackedicons.Update()
    end)

    -- Delete Panel Button
    local delBtn = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    delBtn:SetPoint("BOTTOMRIGHT", -5, 5)
    delBtn:SetSize(80, 22)
    delBtn:SetText("Delete")
    delBtn:SetScript("OnClick", function()
        if selectedPanelIndex and SfuiDB.cooldownPanels[selectedPanelIndex] then
            table.remove(SfuiDB.cooldownPanels, selectedPanelIndex)
            selectedPanelIndex = 1
            selectedEntryIndex = nil
            sfui.editor.UpdatePanelList()
            sfui.editor.UpdatePreview()
            sfui.editor.UpdateSettings()
            sfui.trackedicons.Update()
        end
    end)


    -- === MIDDLE: Preview (Rest) ===
    local middlePanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    middlePanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 10, 0)
    middlePanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -220, 10) -- Leave room for right
    middlePanel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    middlePanel:SetBackdropColor(0, 0, 0, 0.5)
    middlePanel:SetBackdropBorderColor(0, 0, 0, 1)

    -- Preview Header
    local prevHeader = middlePanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    prevHeader:SetPoint("TOPLEFT", 5, -5)
    prevHeader:SetText("Preview (Drag Spells Here)")

    -- Preview Container (Visually represents the panel)
    previewFrame = CreateFrame("Frame", nil, middlePanel, "BackdropTemplate")
    previewFrame:SetPoint("CENTER")
    previewFrame:SetSize(300, 100) -- Initial size
    previewFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    previewFrame:SetBackdropColor(0, 0, 0, 0.2)
    previewFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.5)

    -- Drop Handler
    local function OnReceiveDrag()
        local type, id, _ = GetCursorInfo()
        if type == "spell" or type == "item" or type == "macro" then
            local dragId, dragType = id, type

            if type == "macro" then
                local spellId = GetMacroSpell(id)
                if spellId then
                    dragType = "spell"; dragId = spellId
                else
                    local _, link = GetMacroItem(id)
                    if link then
                        dragId = tonumber(link:match("item:(%d+)"))
                        dragType = "item"
                    end
                end
            end

            if dragId and (dragType == "spell" or dragType == "item") then
                local panel = SfuiDB.cooldownPanels and SfuiDB.cooldownPanels[selectedPanelIndex]
                if panel then
                    if not panel.entries then panel.entries = {} end
                    table.insert(panel.entries, {
                        type = dragType,
                        id = dragId,
                        settings = { showText = true, glow = false }
                    })
                    ClearCursor()
                    sfui.editor.UpdatePreview()
                    sfui.trackedicons.Update()
                    -- Auto select the new entry
                    selectedEntryIndex = #panel.entries
                    sfui.editor.UpdateSettings()
                end
            end
        end
    end

    middlePanel:SetScript("OnMouseUp", OnReceiveDrag)
    middlePanel:SetScript("OnReceiveDrag", OnReceiveDrag)
    previewFrame:SetScript("OnMouseUp", OnReceiveDrag)
    previewFrame:SetScript("OnReceiveDrag", OnReceiveDrag)


    -- === RIGHT: Settings (200px) ===
    local rightPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    rightPanel:SetPoint("TOPRIGHT", -10, -40)
    rightPanel:SetPoint("BOTTOMRIGHT", -10, 10)
    rightPanel:SetWidth(200)
    rightPanel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    rightPanel:SetBackdropColor(0.2, 0.2, 0.2, 0.5)
    rightPanel:SetBackdropBorderColor(0, 0, 0, 1)

    -- Settings Header
    local settHeader = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    settHeader:SetPoint("TOPLEFT", 5, -5)
    settHeader:SetText("Panel Settings")

    -- ScrollFrame for Settings
    local rScroll = CreateFrame("ScrollFrame", nil, rightPanel, "UIPanelScrollFrameTemplate")
    rScroll:SetPoint("TOPLEFT", 5, -25)
    rScroll:SetPoint("BOTTOMRIGHT", -25, 5)
    local rContent = CreateFrame("Frame", nil, rScroll)
    rContent:SetSize(1, 1)
    rScroll:SetScrollChild(rContent)
    rightScroll = rScroll
    rightContent = rContent

    editorFrame = f

    sfui.editor.UpdatePanelList()
    sfui.editor.UpdatePreview()
    sfui.editor.UpdateSettings()

    return f
end


function sfui.editor.Toggle()
    if not editorFrame then CreateEditorFrame() end
    if editorFrame:IsShown() then
        editorFrame:Hide()
    else
        editorFrame:Show()
        sfui.editor.UpdatePanelList()
        sfui.editor.UpdatePreview()
        sfui.editor.UpdateSettings()
    end
end

function sfui.editor.UpdatePanelList()
    if not panelContent then return end

    -- Clear existing
    local kids = { panelContent:GetChildren() }
    for _, kid in ipairs(kids) do kid:Hide() end

    local panels = SfuiDB.cooldownPanels or {}
    local yOffset = 0

    for i, panel in ipairs(panels) do
        local btn = CreateFrame("Button", nil, panelContent, "UIPanelButtonTemplate")
        btn:SetSize(150, 20)
        btn:SetPoint("TOPLEFT", 0, yOffset)
        btn:SetText(panel.name or ("Panel " .. i))

        -- Highlight selected
        if i == selectedPanelIndex then
            btn:SetText(">> " .. (panel.name or ("Panel " .. i)))
            -- Maybe tint it?
            -- btn:GetNormalTexture():SetVertexColor(1, 1, 0) -- Doesn't work well with template
        end

        btn:SetScript("OnClick", function()
            selectedPanelIndex = i
            selectedEntryIndex = nil -- Reset entry selection
            sfui.editor.UpdatePanelList()
            sfui.editor.UpdatePreview()
            sfui.editor.UpdateSettings()
        end)

        yOffset = yOffset - 22
    end

    panelContent:SetHeight(math.abs(yOffset))
end

function sfui.editor.UpdatePreview()
    if not previewFrame then return end

    local panel = SfuiDB.cooldownPanels and SfuiDB.cooldownPanels[selectedPanelIndex]
    if not panel then
        previewFrame:Hide(); return
    end
    previewFrame:Show()

    -- Clear existing
    local kids = { previewFrame:GetChildren() }
    for _, kid in ipairs(kids) do kid:Hide() end

    local entries = panel.entries or {}
    local size = panel.size or 40
    local spacing = panel.spacing or 5
    local width = 0

    -- Layout
    local prevIcon
    for i, entry in ipairs(entries) do
        local icon = CreateFrame("Button", nil, previewFrame, "BackdropTemplate")
        icon:SetSize(size, size)

        -- Texture
        icon.tex = icon:CreateTexture(nil, "ARTWORK")
        icon.tex:SetAllPoints()
        local texture
        if entry.type == "item" then
            texture = C_Item.GetItemIconByID(entry.id)
        else
            texture = C_Spell.GetSpellTexture(entry.id)
        end
        icon.tex:SetTexture(texture or 134400)

        -- Positioning
        local numColumns = panel.columns or 100
        if numColumns < 1 then numColumns = 1 end

        local col = (i - 1) % numColumns
        local row = math.floor((i - 1) / numColumns)
        local x = col * (size + spacing)
        local y = -row * (size + spacing)

        icon:ClearAllPoints()
        local isLeft = (panel.x or 0) < 0
        if isLeft then
            icon:SetPoint("TOPRIGHT", previewFrame, "TOPRIGHT", -x, y)
        else
            icon:SetPoint("TOPLEFT", previewFrame, "TOPLEFT", x, y)
        end

        width = math.max(width, x + size)
        -- prevIcon = icon -- unused in grid logic

        -- Interaction Logic
        icon:RegisterForDrag("LeftButton")
        icon:RegisterForClicks("AnyUp")

        icon:SetScript("OnDragStart", function(self)
            if IsShiftKeyDown() then return end

            sfui.editor.dragSourceIndex = i

            -- Create or Update Ghost
            if not sfui.editor.ghost then
                sfui.editor.ghost = CreateFrame("Frame", nil, UIParent)
                sfui.editor.ghost:SetSize(size, size)
                sfui.editor.ghost:SetFrameStrata("TOOLTIP")
                sfui.editor.ghost.tex = sfui.editor.ghost:CreateTexture(nil, "ARTWORK")
                sfui.editor.ghost.tex:SetAllPoints()
                sfui.editor.ghost.tex:SetAlpha(0.7)
            end

            sfui.editor.ghost.tex:SetTexture(icon.tex:GetTexture())
            sfui.editor.ghost:Show()
            sfui.editor.ghost:SetPoint("CENTER", "UIParent", "BOTTOMLEFT", GetCursorPosition())

            sfui.editor.ghost:SetScript("OnUpdate", function(g)
                local x, y = GetCursorPosition()
                local s = UIParent:GetEffectiveScale()
                g:SetPoint("CENTER", "UIParent", "BOTTOMLEFT", x / s, y / s)
            end)

            self:SetAlpha(0.3) -- Dim original
        end)

        -- We need `icon.customIndex = i` for the logic above to work.
        icon.customIndex = i

        -- Re-implement OnDragStop with full logic now that we have customIndex
        icon:SetScript("OnDragStop", function(self)
            if sfui.editor.ghost then
                sfui.editor.ghost:Hide()
                sfui.editor.ghost:SetScript("OnUpdate", nil)
            end
            self:SetAlpha(1.0)

            if sfui.editor.dragSourceIndex then
                local fromIndex = sfui.editor.dragSourceIndex
                sfui.editor.dragSourceIndex = nil

                -- Check Drop Target by iterating known icons
                local target = nil
                local kids = { previewFrame:GetChildren() }
                for _, kid in ipairs(kids) do
                    if kid:IsVisible() and kid:IsMouseOver() and kid.customIndex then
                        target = kid
                        break
                    end
                end

                if target and target.customIndex then
                    local toIndex = target.customIndex

                    if fromIndex ~= toIndex then
                        local movingEntry = table.remove(panel.entries, fromIndex)

                        -- Fix Index Shift logic when inserting
                        -- If we remove from 5 and insert at 2:
                        -- remove(5) -> list is shorter. insert(2) -> ok.
                        -- If we remove from 2 and insert at 5:
                        -- remove(2) -> list is shorter. index 5 becomes index 4.
                        -- But we want to insert "at the slot where 5 was".
                        -- Actually, `table.insert` inserts BEFORE the index.
                        -- So if we drop on icon #5, we want to insert at #5 (pushing old #5 to #6).
                        -- But if we removed #2, everything shifted down.
                        -- If toIndex > fromIndex, we need to insert at toIndex - 1 ? No.
                        -- Let's trace:
                        -- [A, B, C, D, E]
                        -- Move B (2) to D (4).
                        -- remove(2) -> [A, C, D, E]. D is now at 3.
                        -- If we target D (was 4, user sees it at 4th slot visual? No, user sees it at 3rd slot visual?)
                        -- Wait, layout updates happen AFTER.
                        -- The visual icons haven't moved yet.
                        -- So visual icon #4 is still at x=..., representing entry #4 (which is D).
                        -- So `target.customIndex` is 4.
                        -- We want to insert B at 4.
                        -- insert(At 4, B) -> [A, C, D, B, E].
                        -- Original: [A, B, C, D, E]. Target was D (4).
                        -- Result: A, C, D, B, E.
                        -- B moved after D. That seems right for "Drop ON D"?
                        -- Or drop "Before D"? Usually drop on left half = before, right half = after.
                        -- Simple logic: Insert AT target index.
                        -- But we must account for the removal shift if from < to.

                        if fromIndex < toIndex then
                            -- We want to be at toIndex, but toIndex has shifted down by 1 in the backing table?
                            -- No, table.remove shifts indices > fromIndex down by 1.
                            -- So old index 4 is now index 3.
                            -- If we insert at 4, we insert at (Old 5).
                            -- So if we want to be "At where 4 was", we should insert at 4?
                            -- If we remove 2. 4 becomes 3.
                            -- Insert at 4 means "Insert after 3". So it becomes 4.
                            -- So targetIndex doesn't change?
                            -- Let's stick to toIndex.
                        else
                            -- from > to. Remove 4. 2 is still 2.
                            -- Insert at 2. [A, B, C, D]. Remove D(4). Insert at B(2).
                            -- [A, D, B, C]. D is at 2. B is at 3.
                            -- Seems correct.
                        end

                        table.insert(panel.entries, toIndex, movingEntry)

                        if selectedEntryIndex == fromIndex then
                            selectedEntryIndex = toIndex
                        elseif selectedEntryIndex == toIndex and fromIndex > toIndex then
                            selectedEntryIndex = selectedEntryIndex + 1
                        elseif selectedEntryIndex == toIndex and fromIndex < toIndex then
                            selectedEntryIndex = selectedEntryIndex - 1
                        end

                        sfui.editor.UpdatePreview()
                        sfui.trackedicons.Update()
                        sfui.editor.UpdateSettings()
                    end
                end
            end
        end)

        icon:SetScript("OnReceiveDrag", function(self)
            -- External drags
            local p = previewFrame
            if p and p:GetScript("OnReceiveDrag") then
                p:GetScript("OnReceiveDrag")(p)
            end
        end)

        icon:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                table.remove(panel.entries, i)
                if selectedEntryIndex == i then selectedEntryIndex = nil end
                sfui.editor.UpdatePreview()
                sfui.trackedicons.Update()
                sfui.editor.UpdateSettings()
            else
                selectedEntryIndex = i
                sfui.editor.UpdatePreview() -- To show border
                sfui.editor.UpdateSettings()
            end
        end)

        icon:SetScript("OnMouseUp", nil) -- Clear previous hack


        -- Highlight if selected
        if selectedEntryIndex == i then
            icon:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
            icon:SetBackdropBorderColor(1, 1, 0, 1)
        end
    end

    previewFrame:SetSize(math.max(width, size), size)
end

function sfui.editor.UpdateSettings()
    if not rightContent then return end

    -- Clear
    -- Clear Frames (EditBoxes, Buttons)
    local kids = { rightContent:GetChildren() }
    for _, kid in ipairs(kids) do kid:Hide() end

    -- Clear Regions (FontStrings, Textures)
    local regions = { rightContent:GetRegions() }
    for _, region in ipairs(regions) do region:Hide() end

    local panel = SfuiDB.cooldownPanels and SfuiDB.cooldownPanels[selectedPanelIndex]
    if not panel then return end

    local yOffset = 0

    -- Helper
    local function CreateEditBox(label, w, h, val, callback)
        local l = rightContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l:SetPoint("TOPLEFT", 0, yOffset)
        l:SetText(label)

        local eb = CreateFrame("EditBox", nil, rightContent, "InputBoxTemplate")
        eb:SetSize(w, h)
        eb:SetPoint("TOPLEFT", 0, yOffset - 15)
        eb:SetText(val or "")
        eb:SetAutoFocus(false)
        eb:SetScript("OnEnterPressed", function(self)
            callback(self:GetText())
            self:ClearFocus()
        end)

        yOffset = yOffset - (h + 20)
    end

    local function CreateCheck(label, val, callback)
        local cb = CreateFrame("CheckButton", nil, rightContent, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 0, yOffset)
        cb.text:SetText(label)
        cb:SetChecked(val)
        cb:SetScript("OnClick", function(self)
            callback(self:GetChecked())
        end)
        yOffset = yOffset - 30
    end

    -- Slider Helper
    local function CreateSlider(label, val, min, max, callback, x, y)
        local l = rightContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l:SetPoint("TOPLEFT", x, y)
        l:SetText(label)

        local s = CreateFrame("Slider", nil, rightContent, "OptionsSliderTemplate")
        s:SetPoint("TOPLEFT", x, y - 15)
        s:SetSize(100, 20)
        s:SetMinMaxValues(min, max)
        s:SetValue(val or 0)
        s:SetOrientation("HORIZONTAL")
        s.thumb = s:GetThumbTexture()
        s.thumb:SetSize(10, 20)
        s.thumb:SetColorTexture(1, 1, 1, 1)

        local eb = CreateFrame("EditBox", nil, rightContent, "InputBoxTemplate")
        eb:SetSize(40, 20)
        eb:SetPoint("LEFT", s, "RIGHT", 10, 0)
        eb:SetText(math.floor(val or 0))
        eb:SetAutoFocus(false)
        eb:SetScript("OnEnterPressed", function(self)
            local v = tonumber(self:GetText())
            if v then
                s:SetValue(v) -- Triggers OnValueChanged
            end
            self:ClearFocus()
        end)

        s:SetScript("OnValueChanged", function(self, v)
            v = math.floor(v)
            eb:SetText(v)
            callback(v)
        end)
    end

    -- === Panel Settings ===
    CreateEditBox("Panel Name", 150, 20, panel.name, function(val)
        panel.name = val
        sfui.editor.UpdatePanelList()
    end)

    CreateCheck("Enabled", panel.enabled, function(val)
        panel.enabled = val
        sfui.trackedicons.Update()
    end)

    local startY = yOffset
    CreateEditBox("Size", 50, 20, tostring(panel.size), function(val)
        panel.size = tonumber(val) or 40
        sfui.trackedicons.Update()
        sfui.editor.UpdatePreview()
    end)

    -- X Pos Slider
    CreateSlider("X Position", panel.x, 0, 2000, function(val)
        panel.x = val
        sfui.trackedicons.Update()
    end, 120, startY)

    startY = yOffset
    CreateEditBox("Spacing", 50, 20, tostring(panel.spacing), function(val)
        panel.spacing = tonumber(val) or 5
        sfui.trackedicons.Update()
        sfui.editor.UpdatePreview()
    end)

    -- Y Pos Slider
    CreateSlider("Y Position", panel.y, -1000, 1000, function(val)
        panel.y = val
        sfui.trackedicons.Update()
    end, 120, startY)

    startY = yOffset
    CreateEditBox("Columns (Grid)", 50, 20, tostring(panel.columns or ""), function(val)
        panel.columns = tonumber(val) -- nil if empty -> auto/single row
        sfui.trackedicons.Update()
        sfui.editor.UpdatePreview()
    end)

    -- Separator
    yOffset = yOffset - 10
    local sep = rightContent:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(1, 1, 1, 0.2)
    sep:SetSize(180, 1)
    sep:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - 10

    local l = rightContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    l:SetPoint("TOPLEFT", 0, yOffset)
    l:SetText("Entry Settings")
    yOffset = yOffset - 20

    -- === Entry Settings ===
    if selectedEntryIndex and panel.entries and panel.entries[selectedEntryIndex] then
        local entry = panel.entries[selectedEntryIndex]
        if not entry.settings then entry.settings = {} end

        CreateCheck("Show Cooldown Text", entry.settings.showText ~= false, function(val)
            entry.settings.showText = val
            sfui.trackedicons.Update()
        end)

        CreateCheck("Glow When Ready", entry.settings.glow == true, function(val)
            entry.settings.glow = val
            sfui.trackedicons.Update()
        end)

        CreateCheck("Show Charges", entry.settings.showCharges ~= false, function(val)
            entry.settings.showCharges = val
            sfui.trackedicons.Update()
        end)

        CreateEditBox("Static Text", 80, 20, entry.settings.staticText, function(val)
            entry.settings.staticText = val
            sfui.trackedicons.Update()
        end)

        -- Clean Remove Button
        local del = CreateFrame("Button", nil, rightContent, "UIPanelButtonTemplate")
        del:SetPoint("TOPLEFT", 0, yOffset - 10)
        del:SetSize(100, 22)
        del:SetText("Remove Entry")
        del:SetScript("OnClick", function()
            table.remove(panel.entries, selectedEntryIndex)
            selectedEntryIndex = nil
            sfui.editor.UpdatePreview()
            sfui.trackedicons.Update()
            sfui.editor.UpdateSettings()
        end)
    else
        local help = rightContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        help:SetPoint("TOPLEFT", 0, yOffset)
        help:SetText("Select an icon in preview to edit.")
        help:SetTextColor(0.6, 0.6, 0.6)
    end
end
