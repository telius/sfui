local addonName, addon = ...
sfui = sfui or {}
sfui.alts = sfui.alts or {}
sfui.alts.mail = sfui.alts.mail or {}

local mail = sfui.alts.mail
local common = sfui.common
local widgets = sfui.widgets
local config = sfui.config

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/alts/mail_ui.lua
--  Account-wide routing configuration window, alt item assignment, and drop box
-- ══════════════════════════════════════════════════════════════════════════════

local configFrame = nil
local selectedGUID = nil
local centerMode = "assigned"
local altButtons = {}
local itemSlotPool = {}
local activeItemSlots = {}

local GetCursorInfo = _G.GetCursorInfo
local ClearCursor = _G.ClearCursor
local GameTooltip = common and common.get_tooltip and common.get_tooltip() or _G.GameTooltip
local UnitGUID = _G.UnitGUID

local function GetCategoryDefinitions()
    local isCamelot = sfui.isCamelot or (sfui.compat and sfui.compat.is_camelot)
    local defs = {
        { key = "sendHerbs",       label = "herbs",                 desc = "automatically route all herbs to this alt" },
        { key = "sendOre",         label = "ore & stone",           desc = "automatically route all ore, stone & bars to this alt" },
        { key = "sendCloth",       label = "cloth",                 desc = "automatically route all cloth to this alt" },
        { key = "sendLeather",     label = "leather & hides",       desc = "automatically route all leather & hides to this alt" },
        { key = "sendEnchanting",  label = "enchanting materials",  desc = "automatically route all enchanting dust, shards & essences to this alt" },
        { key = "sendGems",        label = "gems",                  desc = "automatically route all gems to this alt" },
        { key = "sendElemental",   label = "elemental reagents",    desc = "automatically route all elemental reagents to this alt" },
        { key = "sendCooking",     label = "cooking ingredients",   desc = "automatically route all cooking ingredients to this alt" },
        { key = "sendEngineering", label = "engineering parts",     desc = "automatically route all engineering parts & explosives to this alt" },
    }
    if isCamelot then
        table.insert(defs, {
            key   = "sendComprehension",
            label = "mage scrolls",
            desc  = "automatically route untranslated mage comprehension scrolls to this alt",
        })
    else
        table.insert(defs, {
            key   = "sendInscription",
            label = "pigments & inks",
            desc  = "automatically route all milling pigments & inks to this alt",
        })
    end

    table.sort(defs, function(a, b)
        return (a.label or ""):lower() < (b.label or ""):lower()
    end)

    return defs
end

local function AcquireItemSlot(parent)
    local btn = table.remove(itemSlotPool)
    if not btn then
        btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetSize(34, 34)
        common.apply_flat_backdrop(btn, { 0.08, 0.08, 0.1, 0.9 }, { 0.2, 0.2, 0.2, 1 })

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 2, -2)
        icon:SetPoint("BOTTOMRIGHT", -2, 2)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.icon = icon

        local del = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        del:SetPoint("TOPRIGHT", 2, 2)
        del:SetText("x")
        del:SetTextColor(1, 0.3, 0.3, 1)
        del:Hide()
        btn.del = del

        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    else
        btn:SetParent(parent)
        btn:ClearAllPoints()
        btn:Show()
    end
    table.insert(activeItemSlots, btn)
    return btn
end

local function ReleaseItemSlots()
    for _, btn in ipairs(activeItemSlots) do
        btn:Hide()
        btn:ClearAllPoints()
        btn:SetParent(UIParent)
        btn.itemID = nil
        table.insert(itemSlotPool, btn)
    end
    activeItemSlots = {}
end

--- Forward declaration for refresh
local RefreshUI

--- Build or refresh the center item grid for selected alt or blacklist
local function RefreshItemGrid(contentFrame)
    ReleaseItemSlots()
    if not contentFrame then return end

    local items
    if centerMode == "ignored" then
        items = mail.GetIgnoredItems()
    else
        if not selectedGUID then return end
        local route = mail.GetRoute(selectedGUID)
        items = route.items or {}
    end

    local cols = 7
    local slotSize = 34
    local spacing = 6
    local colIdx = 0
    local rowIdx = 0

    for itemID in pairs(items) do
        local btn = AcquireItemSlot(contentFrame)
        btn.itemID = itemID

        local _, link, quality, _, _, _, _, _, _, texture = (common.get_item_info or _G.GetItemInfo)(itemID)
        btn.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")

        if quality and quality > 1 then
            local r, g, b = common.get_item_quality_color(quality)
            btn:SetBackdropBorderColor(r, g, b, 1)
        else
            btn:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
        end

        btn:SetScript("OnEnter", function(self)
            self.del:Show()
            local tip = common.get_tooltip()
            if tip then
                tip:SetOwner(self, "ANCHOR_RIGHT")
                if link then
                    tip:SetHyperlink(link)
                else
                    tip:SetItemByID(self.itemID)
                end
                tip:AddLine(" ")
                if centerMode == "ignored" then
                    tip:AddLine("|cffffaa55never send: item stays on character|r", 1, 0.8, 0.2)
                    tip:AddLine("|cffff5555right-click to remove from blacklist|r", 0.8, 0.8, 0.8)
                else
                    tip:AddLine("|cffff5555right-click to unassign item|r", 0.8, 0.8, 0.8)
                end
                tip:Show()
            end
        end)

        btn:SetScript("OnLeave", function(self)
            self.del:Hide()
            common.hide_tooltip()
        end)

        btn:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                if centerMode == "ignored" then
                    mail.SetItemIgnored(self.itemID, false)
                else
                    mail.RemoveItemFromRoute(selectedGUID, self.itemID)
                end
                common.hide_tooltip()
                RefreshUI()
            end
        end)

        btn:SetPoint("TOPLEFT", colIdx * (slotSize + spacing), -(rowIdx * (slotSize + spacing)))
        colIdx = colIdx + 1
        if colIdx >= cols then
            colIdx = 0
            rowIdx = rowIdx + 1
        end
    end
end


--- Generate options table for the assigned disenchanter dropdown
local function GetDEOptions()
    local deOptions = { { label = "none (disabled)", value = "none" } }
    local allAlts = mail.GetAlts(true)
    for _, a in ipairs(allAlts) do
        table.insert(deOptions, {
            label = string.format("%s (lvl %d)", common.class_color_name(a.name, a.class), a.level or 1),
            value = a.guid,
        })
    end
    return deOptions
end

--- Create the main routing configuration frame
function mail.CreateConfigFrame()
    if configFrame then return configFrame end

    local f = CreateFrame("Frame", "SfuiAltMailConfigFrame", UIParent, "BackdropTemplate")
    table.insert(_G.UISpecialFrames, "SfuiAltMailConfigFrame")
    f:SetFrameStrata("DIALOG")
    f:SetSize(800, 480)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    if sfui.theme and sfui.theme.ApplyWindowStyle then
        sfui.theme.ApplyWindowStyle(f)
        sfui.theme.RegisterWindow(f)
    end

    -- Header
    local headerBar = (sfui.theme and sfui.theme.CreateWindowHeader) and
        sfui.theme.CreateWindowHeader(f, "alts mail routing", 200) or
        widgets.create_window_header(f, "alts mail routing", 200)
    f.headerBar = headerBar

    -- Close Button
    local close = (common.create_close_button or common.create_flat_button)(f, function() f:Hide() end, 24)
    close:ClearAllPoints()
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    close:SetFrameLevel((f:GetFrameLevel() or 1) + 20)
    close.tooltip = "close"
    f.close = close

    -- Alts Manager Button (Opens Alts Manager and closes Mail Routing)
    local altsBtn = common.create_flat_button(f, "", 24, 24)
    altsBtn:ClearAllPoints()
    altsBtn:SetPoint("TOPRIGHT", close, "TOPLEFT", -5, 0)
    altsBtn:SetFrameLevel((f:GetFrameLevel() or 1) + 20)
    altsBtn.tooltip = "alts manager"
    altsBtn:SetScript("OnClick", function()
        f:Hide()
        if sfui.alts.Open then
            sfui.alts.Open()
        elseif sfui.alts.Toggle then
            sfui.alts.Toggle()
        end
    end)
    common.set_button_alts_icon(altsBtn, 16)
    f.altsBtn = altsBtn

    -- ─── Top Bar: Assigned Disenchanter & Quality Filter ────────────────────────
    local topBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    topBar:SetPoint("TOPLEFT", 12, -36)
    topBar:SetPoint("TOPRIGHT", -12, -36)
    topBar:SetHeight(48)
    common.apply_flat_backdrop(topBar, { 0.04, 0.04, 0.05, 0.85 }, { 0.15, 0.15, 0.18, 1 })

    local deLabel = topBar:CreateFontString(nil, "OVERLAY", sfui.config.font)
    deLabel:SetPoint("LEFT", 12, 0)
    deLabel:SetText("assigned disenchanter:")
    deLabel:SetTextColor(0.8, 0.8, 0.8, 1)

    -- Disenchanter Dropdown
    local currentDE = mail.GetSettings().disenchanterGUID or "none"
    local deDropdown = widgets.create_dropdown(topBar, 145, GetDEOptions, function(val)
        mail.SetAssignedDisenchanter(val ~= "none" and val or nil)
        RefreshUI()
    end, currentDE, nil, 165)
    deDropdown:SetPoint("LEFT", deLabel, "RIGHT", 6, 0)
    f.deDropdown = deDropdown

    -- Quality Filter Dropdown
    local qLabel = topBar:CreateFontString(nil, "OVERLAY", sfui.config.font)
    qLabel:SetPoint("LEFT", deDropdown, "RIGHT", 10, 0)
    qLabel:SetText("quality:")
    qLabel:SetTextColor(0.8, 0.8, 0.8, 1)

    local deQualityDropdown = widgets.create_dropdown(topBar, 115, function()
        return {
            { label = "all boe (green+)",   value = "all" },
            { label = "green only",         value = "green" },
            { label = "green & blue",       value = "green_blue" },
            { label = "rare+ (blue & epic)", value = "rare_epic" },
        }
    end, function(val)
        mail.SetDisenchantQualityMode(val)
        RefreshUI()
    end, mail.GetDisenchantQualityMode(), nil, 135)
    deQualityDropdown:SetPoint("LEFT", qLabel, "RIGHT", 6, 0)
    deQualityDropdown.tooltip = "maximum quality of boe gear to automatically route to the disenchanter"
    f.deQualityDropdown = deQualityDropdown

    -- Disenchant Filters
    local wepCb = widgets.create_checkbox(topBar, "boe weapons", function()
        return mail.GetSettings().disenchantWeapons ~= false
    end, function(checked)
        mail.GetSettings().disenchantWeapons = (checked == true)
        RefreshUI()
    end, "automatically route bind-on-equip weapons to the disenchanter")
    wepCb:SetPoint("LEFT", deQualityDropdown, "RIGHT", 14, 0)
    f.wepCb = wepCb

    local armCb = widgets.create_checkbox(topBar, "boe armor", function()
        return mail.GetSettings().disenchantArmor ~= false
    end, function(checked)
        mail.GetSettings().disenchantArmor = (checked == true)
        RefreshUI()
    end, "automatically route bind-on-equip armor to the disenchanter")
    armCb:SetPoint("LEFT", wepCb, "RIGHT", 96, 0)
    f.armCb = armCb

    -- ─── Left Column: Alt Selector (width: 196) ──────────────────────────────────
    local altPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    altPanel:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 0, -8)
    altPanel:SetPoint("BOTTOMLEFT", 12, 12)
    altPanel:SetWidth(196)
    common.apply_flat_backdrop(altPanel, { 0.03, 0.03, 0.04, 0.8 }, { 0.12, 0.12, 0.15, 1 })

    local altTitle = altPanel:CreateFontString(nil, "OVERLAY", sfui.config.font)
    altTitle:SetPoint("TOPLEFT", 8, -8)
    altTitle:SetText("select alt")
    altTitle:SetTextColor(0.6, 0.6, 0.7, 1)

    local altScroll = CreateFrame("ScrollFrame", nil, altPanel)
    altScroll:SetPoint("TOPLEFT", 4, -26)
    altScroll:SetPoint("BOTTOMRIGHT", -4, 4)
    altScroll:EnableMouseWheel(true)
    altScroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = math.max(0, (f.altContent:GetHeight() or 0) - self:GetHeight())
        local step = 42
        if delta > 0 then
            self:SetVerticalScroll(math.max(0, current - step))
        else
            self:SetVerticalScroll(math.min(maxScroll, current + step))
        end
    end)
    local altContent = CreateFrame("Frame", nil, altScroll)
    altContent:SetSize(188, 400)
    altScroll:SetScrollChild(altContent)
    f.altContent = altContent

    -- ─── Center Column: Assigned Items, Ignored Blacklist & Bag Exclusions ─────────
    local centerPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    centerPanel:SetPoint("TOPLEFT", altPanel, "TOPRIGHT", 8, 0)
    centerPanel:SetPoint("BOTTOMLEFT", altPanel, "BOTTOMRIGHT", 8, 0)
    centerPanel:SetWidth(360)
    common.apply_flat_backdrop(centerPanel, { 0.03, 0.03, 0.04, 0.8 }, { 0.12, 0.12, 0.15, 1 })

    local centerTitle = centerPanel:CreateFontString(nil, "OVERLAY", sfui.config.font)
    centerTitle:SetPoint("TOPLEFT", 10, -8)
    centerTitle:SetText("assigned items")
    centerTitle:SetTextColor(0.6, 0.6, 0.7, 1)
    f.centerTitle = centerTitle

    -- Center Panel Mode Tabs
    local ignoredTab = common.create_flat_button(centerPanel, "blacklist", 76, 18, function()
        centerMode = "ignored"
        RefreshUI()
    end)
    ignoredTab:SetPoint("TOPRIGHT", centerPanel, "TOPRIGHT", -10, -6)
    ignoredTab.tooltip = "items to always keep on this character (never mail)"
    f.ignoredTab = ignoredTab

    local assignedTab = common.create_flat_button(centerPanel, "assigned", 68, 18, function()
        centerMode = "assigned"
        RefreshUI()
    end)
    assignedTab:SetPoint("RIGHT", ignoredTab, "LEFT", -4, 0)
    assignedTab.tooltip = "items specifically routed to the selected alt"
    f.assignedTab = assignedTab

    -- Drag-and-Drop Target Box
    local dropBox = CreateFrame("Button", nil, centerPanel, "BackdropTemplate")
    dropBox:SetPoint("TOPLEFT", 10, -28)
    dropBox:SetPoint("TOPRIGHT", -10, -28)
    dropBox:SetHeight(38)
    common.apply_flat_backdrop(dropBox, { 0.07, 0.07, 0.1, 0.9 }, { 0.3, 0.3, 0.5, 0.8 })

    local dropText = dropBox:CreateFontString(nil, "OVERLAY", sfui.config.font)
    dropText:SetPoint("CENTER")
    dropText:SetText("|cff88aaff+ drag inventory item here to assign|r")
    dropBox.text = dropText
    f.dropBox = dropBox

    local function HandleItemDrop()
        local infoType, itemID = GetCursorInfo()
        if infoType == "item" and itemID then
            if centerMode == "ignored" then
                mail.SetItemIgnored(itemID, true)
            elseif selectedGUID then
                mail.AddItemToRoute(selectedGUID, itemID)
            end
            ClearCursor()
            RefreshUI()
        end
    end

    dropBox:SetScript("OnReceiveDrag", HandleItemDrop)
    dropBox:SetScript("OnClick", HandleItemDrop)
    dropBox:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.5, 0.5, 1.0, 1)
    end)
    dropBox:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.3, 0.3, 0.5, 0.8)
    end)

    -- Item Grid Scroll Area
    local itemScroll = CreateFrame("ScrollFrame", nil, centerPanel)
    itemScroll:SetPoint("TOPLEFT", dropBox, "BOTTOMLEFT", 0, -8)
    itemScroll:SetPoint("BOTTOMRIGHT", -8, 8)
    local itemContent = CreateFrame("Frame", nil, itemScroll)
    itemContent:SetSize(340, 400)
    itemScroll:SetScrollChild(itemContent)
    f.itemContent = itemContent


    -- ─── Right Column: Category Toggles (width: 190) ─────────────────────────────
    local rightPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    rightPanel:SetPoint("TOPLEFT", centerPanel, "TOPRIGHT", 8, 0)
    rightPanel:SetPoint("BOTTOMRIGHT", -12, 12)
    common.apply_flat_backdrop(rightPanel, { 0.03, 0.03, 0.04, 0.8 }, { 0.12, 0.12, 0.15, 1 })

    local rightTitle = rightPanel:CreateFontString(nil, "OVERLAY", sfui.config.font)
    rightTitle:SetPoint("TOPLEFT", 10, -8)
    rightTitle:SetText("automatic categories")
    rightTitle:SetTextColor(0.6, 0.6, 0.7, 1)

    f.categoryCheckboxes = {}

    -- Scrollable container for automatic category rows
    local catScroll = CreateFrame("ScrollFrame", nil, rightPanel)
    catScroll:SetPoint("TOPLEFT", 4, -28)
    catScroll:SetPoint("BOTTOMRIGHT", -4, 4)
    catScroll:EnableMouseWheel(true)
    catScroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = math.max(0, (f.catContent:GetHeight() or 0) - self:GetHeight())
        local step = 44
        if delta > 0 then
            self:SetVerticalScroll(math.max(0, current - step))
        else
            self:SetVerticalScroll(math.min(maxScroll, current + step))
        end
    end)

    local catDefs = GetCategoryDefinitions()
    local catContent = CreateFrame("Frame", nil, catScroll)
    catContent:SetSize(184, (#catDefs * 44) + 12)
    catScroll:SetScrollChild(catContent)
    f.catContent = catContent

    local startY = -4
    local rowSpacing = 44
    for i, def in ipairs(catDefs) do
        local cb = widgets.create_checkbox(catContent, def.label, function()
            if not selectedGUID then return false end
            return mail.GetRoute(selectedGUID)[def.key] == true
        end, function(checked)
            if selectedGUID then
                mail.ToggleCategory(selectedGUID, def.key, checked)
                RefreshUI()
            end
        end, def.desc or string.format("automatically route all %s to this alt", def.label))

        local yPos = startY - ((i - 1) * rowSpacing)
        cb:SetPoint("TOPLEFT", 8, yPos)

        local routedText = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        routedText:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 25, -2)
        routedText:SetPoint("RIGHT", catContent, "RIGHT", -4, 0)
        routedText:SetJustifyH("LEFT")
        routedText:SetText("|cff888888routed to:|r |cff555555none|r")
        cb.routedText = routedText

        cb:SetScript("OnEnter", function(self)
            local tip = common.get_tooltip()
            if tip then
                tip:SetOwner(self, "ANCHOR_RIGHT")
                tip:ClearLines()
                tip:AddLine(def.label, 1, 1, 1)
                tip:AddLine(def.desc or string.format("automatically route all %s to this alt", def.label), 0.7, 0.7, 0.7, true)
                local name, class, guid = mail.GetCategoryRecipient(def.key)
                if name then
                    local curTag = (guid == UnitGUID("player")) and " (current character)" or ""
                    tip:AddLine(string.format("currently routed to: %s%s", common.class_color_name(name, class), curTag), 0.85, 0.85, 0.45)
                else
                    tip:AddLine("currently routed to: none", 0.5, 0.5, 0.5)
                end
                tip:Show()
            end
        end)
        cb:SetScript("OnLeave", function()
            common.hide_tooltip()
        end)

        f.categoryCheckboxes[def.key] = cb
    end

    f:SetScript("OnShow", function()
        RefreshUI()
    end)

    configFrame = f
    return f
end

--- Refresh all data and lists in the configuration frame
RefreshUI = function()
    if not configFrame or not configFrame:IsShown() then return end

    local alts = mail.GetAlts(true)
    local found = false
    for _, a in ipairs(alts) do
        if a.guid == selectedGUID then
            found = true
            break
        end
    end
    if not found then
        selectedGUID = alts[1] and alts[1].guid
    end

    -- 1. Populate Disenchanter Dropdown options
    local deOptions = GetDEOptions()
    local currentDE = mail.GetSettings().disenchanterGUID or "none"
    if configFrame.deDropdown and configFrame.deDropdown.SetOptions then
        configFrame.deDropdown:SetOptions(deOptions, currentDE)
    elseif configFrame.deDropdown and configFrame.deDropdown.SetSelectedValue then
        configFrame.deDropdown:SetSelectedValue(currentDE)
    end

    if configFrame.wepCb and configFrame.wepCb.SetChecked then
        configFrame.wepCb:SetChecked(mail.GetSettings().disenchantWeapons ~= false)
    end
    if configFrame.armCb and configFrame.armCb.SetChecked then
        configFrame.armCb:SetChecked(mail.GetSettings().disenchantArmor ~= false)
    end

    -- 2. Populate Alt List
    local btnH = 38
    local totalH = #alts * (btnH + 4)
    configFrame.altContent:SetHeight(math.max(totalH, 200))

    for i, a in ipairs(alts) do
        local btn = altButtons[i]
        if not btn then
            btn = CreateFrame("Button", nil, configFrame.altContent, "BackdropTemplate")
            btn:SetSize(184, btnH)
            common.apply_flat_backdrop(btn, { 0.05, 0.05, 0.07, 0.75 }, { 0.14, 0.14, 0.17, 0.8 })

            local classBar = btn:CreateTexture(nil, "ARTWORK")
            classBar:SetPoint("TOPLEFT", 1, -1)
            classBar:SetPoint("BOTTOMLEFT", 1, 1)
            classBar:SetWidth(3)
            btn.classBar = classBar

            local nameText = btn:CreateFontString(nil, "OVERLAY", sfui.config.font)
            nameText:SetPoint("TOPLEFT", 10, -5)
            nameText:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
            nameText:SetJustifyH("LEFT")
            nameText:SetWordWrap(false)
            btn.nameText = nameText

            local noProfText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            noProfText:SetPoint("BOTTOMLEFT", 10, 5)
            noProfText:SetJustifyH("LEFT")
            noProfText:SetTextColor(0.45, 0.45, 0.52, 1)
            noProfText:SetText("no professions")
            btn.noProfText = noProfText

            btn.profIcons = {}
            for pIdx = 1, 2 do
                local iconBtn = CreateFrame("Button", nil, btn, "BackdropTemplate")
                iconBtn:SetSize(16, 16)
                common.apply_flat_backdrop(iconBtn, { 0.04, 0.04, 0.06, 0.9 }, { 0.25, 0.25, 0.3, 0.9 })

                local tex = iconBtn:CreateTexture(nil, "ARTWORK")
                tex:SetPoint("TOPLEFT", 1, -1)
                tex:SetPoint("BOTTOMRIGHT", -1, 1)
                tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                iconBtn.texture = tex

                local rankText = iconBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                rankText:SetPoint("LEFT", iconBtn, "RIGHT", 3, 0)
                rankText:SetTextColor(0.65, 0.65, 0.72, 1)
                iconBtn.rankText = rankText

                iconBtn:SetScript("OnEnter", function(self)
                    if not self.profData then return end
                    local tip = common.get_tooltip()
                    if tip then
                        tip:SetOwner(self, "ANCHOR_RIGHT")
                        tip:ClearLines()
                        tip:AddLine(self.profData.name or "profession", 1, 1, 1)
                        if self.profData.rank and self.profData.rank > 0 then
                            local maxR = (self.profData.maxRank and self.profData.maxRank > 0) and self.profData.maxRank or 300
                            tip:AddLine(string.format("rank: %d / %d", self.profData.rank, maxR), 0.7, 0.8, 1)
                        end
                        tip:Show()
                    end
                end)

                iconBtn:SetScript("OnLeave", function()
                    common.hide_tooltip()
                end)

                iconBtn:SetScript("OnClick", function()
                    btn:Click()
                end)

                btn.profIcons[pIdx] = iconBtn
            end

            btn:SetScript("OnClick", function(self)
                selectedGUID = self.guid
                RefreshUI()
            end)

            btn:SetScript("OnEnter", function(self)
                if self.guid ~= selectedGUID and self.classR then
                    self:SetBackdropBorderColor(self.classR * 0.7, self.classG * 0.7, self.classB * 0.7, 0.9)
                end
            end)

            btn:SetScript("OnLeave", function(self)
                if self.guid ~= selectedGUID then
                    self:SetBackdropBorderColor(0.14, 0.14, 0.17, 0.8)
                end
            end)

            altButtons[i] = btn
        end

        btn.guid = a.guid
        btn:SetPoint("TOPLEFT", 2, -((i - 1) * (btnH + 4)))

        local cr, cg, cb = common.get_class_color(a.class)
        btn.classR = cr
        btn.classG = cg
        btn.classB = cb
        btn.classBar:SetColorTexture(cr, cg, cb, 1)

        local isSelected = (a.guid == selectedGUID)
        if isSelected then
            btn:SetBackdropColor(cr * 0.18, cg * 0.18, cb * 0.18, 0.95)
            btn:SetBackdropBorderColor(cr, cg, cb, 1)
        else
            btn:SetBackdropColor(0.05, 0.05, 0.07, 0.75)
            btn:SetBackdropBorderColor(0.14, 0.14, 0.17, 0.8)
        end

        local dispName = (sfui.alts and sfui.alts.GetDisplayName and sfui.alts.GetDisplayName(a)) or a.name
        local enchTag = a.hasEnchanting and " |cff00ff88*|r" or ""
        local lvlTag = string.format(" |cff777788%d|r", a.level or 1)
        btn.nameText:SetText(string.format("%s%s%s", common.class_color_name(dispName, a.class), lvlTag, enchTag))

        local profs = a.professions or {}
        if #profs == 0 then
            btn.noProfText:Show()
            for _, iconBtn in ipairs(btn.profIcons) do
                iconBtn:Hide()
                iconBtn.profData = nil
                iconBtn.rankText:SetText("")
            end
        else
            btn.noProfText:Hide()
            for pIdx = 1, 2 do
                local iconBtn = btn.profIcons[pIdx]
                local prof = profs[pIdx]
                if prof then
                    iconBtn.profData = prof
                    iconBtn.texture:SetTexture(prof.icon)
                    iconBtn:ClearAllPoints()
                    if pIdx == 1 then
                        iconBtn:SetPoint("BOTTOMLEFT", 10, 5)
                    else
                        local prevBtn = btn.profIcons[1]
                        if prevBtn.rankText:GetText() and prevBtn.rankText:GetText() ~= "" then
                            iconBtn:SetPoint("LEFT", prevBtn.rankText, "RIGHT", 8, 0)
                        else
                            iconBtn:SetPoint("LEFT", prevBtn, "RIGHT", 6, 0)
                        end
                    end

                    if prof.rank and prof.rank > 0 then
                        iconBtn.rankText:SetText(tostring(prof.rank))
                    else
                        iconBtn.rankText:SetText("")
                    end

                    iconBtn:Show()
                else
                    iconBtn:Hide()
                    iconBtn.profData = nil
                    iconBtn.rankText:SetText("")
                end
            end
        end

        btn:Show()
    end

    for i = #alts + 1, #altButtons do
        altButtons[i]:Hide()
    end

    -- 3. Update Mode Tabs, Quality Dropdown & Bag Exclusions
    local hl = (sfui.config and sfui.config.appearance and sfui.config.appearance.highlightColor) or { 0.4, 0, 1, 1 }
    if configFrame.assignedTab then
        if centerMode == "assigned" then
            configFrame.assignedTab:SetBackdropColor(hl[1] * 0.45, hl[2] * 0.45, hl[3] * 0.45, 0.95)
            configFrame.assignedTab:SetBackdropBorderColor(hl[1], hl[2], hl[3], 1)
        else
            configFrame.assignedTab:SetBackdropColor(0.06, 0.06, 0.08, 0.8)
            configFrame.assignedTab:SetBackdropBorderColor(0.2, 0.2, 0.24, 0.9)
        end
    end
    if configFrame.ignoredTab then
        if centerMode == "ignored" then
            configFrame.ignoredTab:SetBackdropColor(hl[1] * 0.45, hl[2] * 0.45, hl[3] * 0.45, 0.95)
            configFrame.ignoredTab:SetBackdropBorderColor(hl[1], hl[2], hl[3], 1)
        else
            configFrame.ignoredTab:SetBackdropColor(0.06, 0.06, 0.08, 0.8)
            configFrame.ignoredTab:SetBackdropBorderColor(0.2, 0.2, 0.24, 0.9)
        end
    end

    if configFrame.dropBox and configFrame.dropBox.text then
        if centerMode == "ignored" then
            configFrame.dropBox.text:SetText("|cffffaa55+ drag item here to never send (keep on character)|r")
        else
            configFrame.dropBox.text:SetText("|cff88aaff+ drag inventory item here to assign|r")
        end
    end

    if configFrame.deQualityDropdown and configFrame.deQualityDropdown.SetSelectedValue then
        configFrame.deQualityDropdown:SetSelectedValue(mail.GetDisenchantQualityMode())
    end

    -- 4. Update Center Title & Items Grid
    if centerMode == "ignored" then
        configFrame.centerTitle:SetText("never send (blacklist)")
    else
        local selectedAltData = selectedGUID and SfuiDB and SfuiDB.alts and SfuiDB.alts[selectedGUID]
        if selectedAltData then
            local curSuffix = (selectedGUID == UnitGUID("player")) and " |cff888888(current character)|r" or ""
            configFrame.centerTitle:SetText(string.format("%s assigned items%s", common.class_color_name(selectedAltData.name, selectedAltData.class), curSuffix))
        else
            configFrame.centerTitle:SetText("assigned items")
        end
    end
    RefreshItemGrid(configFrame.itemContent)

    -- 5. Update Category Checkboxes & Routed Alt Display
    local route = selectedGUID and mail.GetRoute(selectedGUID) or {}
    for key, cb in pairs(configFrame.categoryCheckboxes or {}) do
        cb:SetChecked(route[key] == true)
        if cb.routedText then
            local name, class, guid = mail.GetCategoryRecipient(key)
            if name then
                local curTag = (guid == UnitGUID("player")) and " |cff888888(current)|r" or ""
                cb.routedText:SetText(string.format("|cff888888routed to:|r %s%s", common.class_color_name(name, class), curTag))
            else
                cb.routedText:SetText("|cff888888routed to:|r |cff555555none|r")
            end
        end
    end

end

--- Open the configuration frame (guaranteed show)
function sfui.alts.OpenMailConfig()
    local f = mail.CreateConfigFrame()
    if not f:IsShown() then
        f:Show()
    end
    RefreshUI()
end

--- Toggle the configuration frame
function sfui.alts.ToggleMailConfig()
    local f = mail.CreateConfigFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        RefreshUI()
    end
end

-- ─── Shift-Click Inventory Assignment ─────────────────────────────────────────
if not mail._shiftClickHooked and _G.hooksecurefunc then
    mail._shiftClickHooked = true
    hooksecurefunc("HandleModifiedItemClick", function(link)
        if not configFrame or not configFrame:IsShown() then return end
        if not _G.IsShiftKeyDown or not _G.IsShiftKeyDown() then return end
        if _G.ChatEdit_GetActiveWindow and _G.ChatEdit_GetActiveWindow() then return end
        if not link then return end

        local itemID = (common and common.get_item_instant_info and select(1, common.get_item_instant_info(link)))
            or (_G.GetItemInfoInstant and select(1, _G.GetItemInfoInstant(link)))
            or tonumber(link:match("item:(%d+)"))
        if not itemID then return end

        if centerMode == "ignored" then
            mail.SetItemIgnored(itemID, true)
            RefreshUI()
            if common and common.print then
                common.print(string.format("|cff00ff88added %s to never send list.|r", link))
            end
        elseif selectedGUID then
            mail.AddItemToRoute(selectedGUID, itemID)
            RefreshUI()
            local alt = SfuiDB.alts and SfuiDB.alts[selectedGUID]
            local aName = alt and alt.name or "alt"
            if common and common.print then
                common.print(string.format("|cff00ff88assigned %s to %s.|r", link, aName))
            end
        end
    end)
end

