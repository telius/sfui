local addonName, addon = ...
sfui = sfui or {}
sfui.alts = sfui.alts or {}
sfui.alts.mail = sfui.alts.mail or {}

local mail = sfui.alts.mail
local common = sfui.common
local widgets = sfui.widgets
local config = sfui.config

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/alts/mail_mailbox.lua
--  Docked Mailbox Sidecar Frame: Pending Manifest Summary & One-Click Dispatch
-- ══════════════════════════════════════════════════════════════════════════════

local sidecarFrame = nil
local rowPool = {}
local activeRows = {}
local iconButtonPool = {}

local C_Timer = _G.C_Timer
local GetItemIcon = _G.GetItemIcon or (C_Item and C_Item.GetItemIconByID)

local function AcquireIconButton(parent)
    local btn = table.remove(iconButtonPool)
    if not btn then
        btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetSize(24, 24)
        common.apply_flat_backdrop(btn, { 0.04, 0.04, 0.06, 0.95 }, { 0.3, 0.3, 0.35, 1 })

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.icon = icon

        local fontFile = common.get_font_file()

        local countText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        countText:SetPoint("BOTTOMRIGHT", -1, 1)
        countText:SetFont(fontFile, 9, "OUTLINE")
        countText:SetTextColor(1, 1, 1, 1)
        countText:SetJustifyH("RIGHT")
        btn.countText = countText

        local badgeText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        badgeText:SetPoint("CENTER", 0, 0)
        badgeText:SetFont(fontFile, 10, "OUTLINE")
        badgeText:SetTextColor(1, 0.85, 0.3, 1)
        badgeText:Hide()
        btn.badgeText = badgeText

        btn:SetScript("OnEnter", function(self)
            local tip = common.get_tooltip()
            if not tip then return end
            tip:SetOwner(self, "ANCHOR_RIGHT")
            if self.isOverflow and self.overflowItems then
                tip:ClearLines()
                tip:AddLine(string.format("%d more queued item(s):", #self.overflowItems), 1, 0.85, 0.3)
                for _, oItem in ipairs(self.overflowItems) do
                    local oLink = oItem.link or ("item " .. tostring(oItem.itemID or ""))
                    local oQual = oItem.quality or 1
                    local oR, oG, oB = common.get_item_quality_color(oQual)
                    if not oR then oR, oG, oB = 0.8, 0.8, 0.8 end
                    local countPrefix = (oItem.count and oItem.count > 1) and string.format("%dx ", oItem.count) or ""
                    tip:AddLine(countPrefix .. oLink, oR, oG, oB)
                end
                tip:Show()
            elseif self.itemLink then
                tip:SetHyperlink(self.itemLink)
                tip:Show()
            end
        end)

        btn:SetScript("OnLeave", function()
            common.hide_tooltip()
        end)

        btn:SetScript("OnClick", function(self)
            if self.itemLink and _G.IsModifiedClick and _G.IsModifiedClick("CHATLINK") and _G.HandleModifiedItemClick then
                _G.HandleModifiedItemClick(self.itemLink)
            end
        end)
    else
        btn:SetParent(parent)
        btn:ClearAllPoints()
        btn:Show()
    end
    return btn
end

local function AcquireRow(parent)
    local r = table.remove(rowPool)
    if not r then
        r = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        r:SetSize(264, 40)
        common.apply_flat_backdrop(r, { 0.06, 0.06, 0.08, 0.8 }, { 0.18, 0.18, 0.22, 1 })

        local classBar = r:CreateTexture(nil, "ARTWORK")
        classBar:SetPoint("TOPLEFT", 1, -1)
        classBar:SetPoint("BOTTOMLEFT", 1, 1)
        classBar:SetWidth(3)
        r.classBar = classBar

        r.nameText = r:CreateFontString(nil, "OVERLAY", sfui.config.font)
        r.nameText:SetPoint("TOPLEFT", 10, -5)
        r.nameText:SetJustifyH("LEFT")
        r.nameText:SetWordWrap(false)

        r.descText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.descText:SetPoint("BOTTOMLEFT", 10, 5)
        r.descText:SetTextColor(0.65, 0.65, 0.65, 1)
        r.descText:SetJustifyH("LEFT")
        r.descText:SetWordWrap(false)

        local sendBtn = common.create_flat_button(r, "send", 36, 20)
        sendBtn:SetPoint("RIGHT", r, "RIGHT", -6, 0)
        r.sendBtn = sendBtn

        r.itemIcons = {}
    else
        r:SetParent(parent)
        r:ClearAllPoints()
        r:Show()
        if r.sendBtn then
            r.sendBtn:Show()
        end
        r.itemIcons = r.itemIcons or {}
    end
    table.insert(activeRows, r)
    return r
end

local function ReleaseRows()
    for _, r in ipairs(activeRows) do
        if r.sendBtn then
            r.sendBtn:Hide()
            r.sendBtn:SetScript("OnClick", nil)
        end
        if r.itemIcons then
            for _, btn in ipairs(r.itemIcons) do
                btn:Hide()
                btn:ClearAllPoints()
                btn:SetParent(UIParent)
                btn.itemLink = nil
                btn.isOverflow = nil
                btn.overflowItems = nil
                table.insert(iconButtonPool, btn)
            end
            r.itemIcons = {}
        end
        r:Hide()
        r:ClearAllPoints()
        r:SetParent(UIParent)
        table.insert(rowPool, r)
    end
    activeRows = {}
end


local function UpdateProgressBar(current, total, label)
    if not sidecarFrame or not sidecarFrame.progressBar then return end
    local bar = sidecarFrame.progressBar
    bar:Show()
    local maxW = math.max(1, (bar:GetWidth() or 264) - 2)
    local pct = math.min(1, math.max(0, current / math.max(total, 1)))
    bar.fill:SetWidth(math.max(1, maxW * pct))
    bar.text:SetText(label or "")
end

local function HideProgressBar()
    if not sidecarFrame or not sidecarFrame.progressBar then return end
    sidecarFrame.progressBar:Hide()
    sidecarFrame.progressBar.fill:SetWidth(0)
    sidecarFrame.progressBar.text:SetText("")
end

--- Update the sidecar manifest display
local function RefreshSidecar()
    if not sidecarFrame or not sidecarFrame:IsShown() then return end

    ReleaseRows()
    local manifest, totalItems = mail.ScanPendingMail()

    local yOffset = 0
    local rowH = 40
    local spacing = 4
    local maxIcons = 4

    -- Sort manifest by alt level descending, with name tie-breaker
    local sortedList = {}
    for _, data in pairs(manifest) do
        table.insert(sortedList, data)
    end
    table.sort(sortedList, function(a, b)
        local lvlA = tonumber(a.level) or 1
        local lvlB = tonumber(b.level) or 1
        if lvlA ~= lvlB then
            return lvlA > lvlB
        end
        return (a.name or ""):lower() < (b.name or ""):lower()
    end)

    for _, data in ipairs(sortedList) do
        local r = AcquireRow(sidecarFrame.content)
        r:SetPoint("TOPLEFT", 0, -yOffset)

        local cr, cg, cb = common.get_class_color(data.class)
        if r.classBar then
            r.classBar:SetColorTexture(cr, cg, cb, 1)
        end

        local iconsTag = (data.iconsMarkup and data.iconsMarkup ~= "") and (" " .. data.iconsMarkup) or ""
        r.nameText:SetText(string.format("%s%s", common.class_color_name(data.name, data.class), iconsTag))

        local boeCount = 0
        local assignedCount = 0
        local catCount = 0
        for _, it in ipairs(data.items) do
            if it.reason == "disenchant_boe" then
                boeCount = boeCount + 1
            elseif it.reason == "assigned_item" then
                assignedCount = assignedCount + 1
            else
                catCount = catCount + 1
            end
        end

        local parts = {}
        if boeCount > 0 then table.insert(parts, string.format("%d boe", boeCount)) end
        if assignedCount > 0 then table.insert(parts, string.format("%d assigned", assignedCount)) end
        if catCount > 0 then table.insert(parts, string.format("%d reagents", catCount)) end
        local detail = #parts > 0 and table.concat(parts, ", ") or "queued"

        r.descText:SetText(string.format("%d item(s) (%s)", #data.items, detail))

        -- Per-alt single dispatch button
        if r.sendBtn then
            r.sendBtn:SetPoint("RIGHT", r, "RIGHT", -6, 0)
            r.sendBtn:Show()
            r.sendBtn:SetText(mail.IsDispatching() and "cancel" or "send")
            r.sendBtn:SetScript("OnClick", function()
                if mail.IsDispatching() then
                    mail.CancelDispatch("user cancelled")
                    HideProgressBar()
                    RefreshSidecar()
                    return
                end

                local started, err = mail.StartDispatch(function(curr, total, recipient)
                    UpdateProgressBar(curr, total, string.format("sending %s (%d/%d)", recipient, curr, total))
                    if sidecarFrame and sidecarFrame.dispatchBtn then
                        sidecarFrame.dispatchBtn:SetText("cancel")
                    end
                end, function(success, reason)
                    HideProgressBar()
                    RefreshSidecar()
                    if C_Timer and C_Timer.After then
                        C_Timer.After(0.8, RefreshSidecar)
                    end
                end, data.guid)

                if not started and common and common.print then
                    common.print(string.format("|cffff3333dispatch error: %s.|r", err or "unknown"))
                end
            end)
        end

        -- ── Build queued item icons aligned to the right (flush to left of r.sendBtn) ──
        local totalQueued = #data.items
        local displayButtons = {}

        if totalQueued > 0 then
            local numToDisplay = math.min(totalQueued, maxIcons)
            local hasOverflow = totalQueued > maxIcons

            for i = 1, numToDisplay do
                local btn = AcquireIconButton(r)
                table.insert(r.itemIcons, btn)
                table.insert(displayButtons, btn)

                if hasOverflow and i == numToDisplay then
                    -- Overflow button indicating remaining items
                    local remaining = totalQueued - (maxIcons - 1)
                    btn.isOverflow = true
                    btn.itemLink = nil
                    btn.overflowItems = {}
                    for oIdx = maxIcons, totalQueued do
                        table.insert(btn.overflowItems, data.items[oIdx])
                    end

                    local leadItem = data.items[maxIcons]
                    local leadTex = leadItem and (leadItem.texture or (GetItemIcon and GetItemIcon(leadItem.itemID)))
                        or "Interface\\Icons\\INV_Misc_QuestionMark"
                    btn.icon:SetTexture(leadTex)
                    btn.icon:SetVertexColor(0.25, 0.25, 0.25, 0.85)

                    btn:SetBackdropBorderColor(0.85, 0.7, 0.2, 0.9)
                    btn.badgeText:SetText("+" .. tostring(remaining))
                    btn.badgeText:Show()
                    btn.countText:Hide()
                else
                    -- Standard queued item button
                    local it = data.items[i]
                    btn.isOverflow = false
                    btn.overflowItems = nil
                    btn.itemLink = it.link

                    local tex = it.texture or (GetItemIcon and it.itemID and GetItemIcon(it.itemID))
                        or "Interface\\Icons\\INV_Misc_QuestionMark"
                    btn.icon:SetTexture(tex)
                    btn.icon:SetVertexColor(1, 1, 1, 1)

                    local q = it.quality or 1
                    local qr, qg, qb = common.get_item_quality_color(q)
                    if not qr then qr, qg, qb = 0.4, 0.4, 0.4 end
                    btn:SetBackdropBorderColor(qr, qg, qb, 0.9)

                    if it.count and it.count > 1 then
                        btn.countText:SetText(tostring(it.count))
                        btn.countText:Show()
                    else
                        btn.countText:SetText("")
                        btn.countText:Hide()
                    end
                    btn.badgeText:Hide()
                end
            end

            -- Anchor all displayed buttons aligned to the right (flush to left of r.sendBtn)
            local btnCount = #displayButtons
            for i = btnCount, 1, -1 do
                local btn = displayButtons[i]
                btn:ClearAllPoints()
                if i == btnCount then
                    btn:SetPoint("RIGHT", r.sendBtn, "LEFT", -4, 0)
                else
                    btn:SetPoint("RIGHT", displayButtons[i + 1], "LEFT", -3, 0)
                end
            end

            -- Constrain text width so it never overlaps the right-aligned icons
            local leftmostBtn = displayButtons[1]
            r.nameText:ClearAllPoints()
            r.nameText:SetPoint("TOPLEFT", 10, -5)
            r.nameText:SetPoint("RIGHT", leftmostBtn, "LEFT", -4, 0)

            r.descText:ClearAllPoints()
            r.descText:SetPoint("BOTTOMLEFT", 10, 5)
            r.descText:SetPoint("RIGHT", leftmostBtn, "LEFT", -4, 0)
        else
            r.nameText:ClearAllPoints()
            r.nameText:SetPoint("TOPLEFT", 10, -5)
            r.nameText:SetPoint("RIGHT", r.sendBtn, "LEFT", -4, 0)

            r.descText:ClearAllPoints()
            r.descText:SetPoint("BOTTOMLEFT", 10, 5)
            r.descText:SetPoint("RIGHT", r.sendBtn, "LEFT", -4, 0)
        end

        yOffset = yOffset + rowH + spacing
    end

    sidecarFrame.content:SetHeight(math.max(yOffset, 150))

    -- 1. Update Dispatch All Button
    if mail.IsDispatching() then
        sidecarFrame.dispatchBtn:SetText("cancel")
        sidecarFrame.dispatchBtn:Enable()
    elseif totalItems > 0 then
        sidecarFrame.emptyText:Hide()
        sidecarFrame.dispatchBtn:SetText(string.format("send all (%d)", totalItems))
        sidecarFrame.dispatchBtn:Enable()
    else
        sidecarFrame.emptyText:Show()
        sidecarFrame.dispatchBtn:SetText("no pending mail")
        sidecarFrame.dispatchBtn:Disable()
    end

    -- 2. Update Open All Button
    local inboxNum = (_G.GetInboxNumItems and _G.GetInboxNumItems()) or 0
    if sidecarFrame.openAllBtn then
        if mail.IsCollectingInbox() then
            sidecarFrame.openAllBtn:SetText("cancel")
            sidecarFrame.openAllBtn:Enable()
        elseif inboxNum > 0 then
            sidecarFrame.openAllBtn:SetText(string.format("open all (%d)", inboxNum))
            sidecarFrame.openAllBtn:Enable()
        else
            sidecarFrame.openAllBtn:SetText("inbox empty")
            sidecarFrame.openAllBtn:Disable()
        end
    end
end

--- Create the mailbox sidecar frame
function mail.CreateMailboxSidecar()
    if sidecarFrame then return sidecarFrame end

    local f = CreateFrame("Frame", "SfuiMailboxSidecar", UIParent, "BackdropTemplate")
    f:SetFrameStrata("HIGH")
    f:SetSize(280, 420)
    f:Hide()

    if sfui.theme and sfui.theme.ApplyWindowStyle then
        sfui.theme.ApplyWindowStyle(f)
        sfui.theme.RegisterWindow(f)
    end

    -- Header
    local headerBar = (sfui.theme and sfui.theme.CreateWindowHeader) and
        sfui.theme.CreateWindowHeader(f, "alts dispatch", 200) or
        widgets.create_window_header(f, "alts dispatch", 200)
    f.headerBar = headerBar

    -- Open Routing Configuration Button (Mail Icon)
    local cfgBtn = common.create_flat_button(f, "", 22, 22)
    cfgBtn:ClearAllPoints()
    cfgBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
    cfgBtn:SetFrameLevel((f:GetFrameLevel() or 1) + 20)
    cfgBtn.tooltip = "alts mail routing"
    cfgBtn:SetScript("OnClick", function()
        sfui.alts.ToggleMailConfig()
    end)
    common.set_button_mail_icon(cfgBtn, 14)
    f.cfgBtn = cfgBtn

    -- Scroll Area for Manifest Rows
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", 8, -32)
    scroll:SetPoint("BOTTOMRIGHT", -8, 60)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = math.max(0, (f.content:GetHeight() or 0) - self:GetHeight())
        local step = 44
        if delta > 0 then
            self:SetVerticalScroll(math.max(0, current - step))
        else
            self:SetVerticalScroll(math.min(maxScroll, current + step))
        end
    end)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(264, 300)
    scroll:SetScrollChild(content)
    f.content = content

    -- Empty placeholder text
    local emptyText = f:CreateFontString(nil, "OVERLAY", sfui.config.font)
    emptyText:SetPoint("CENTER", 0, 10)
    emptyText:SetText("|cff666677no items in bags match\nalt routing rules.|r")
    emptyText:SetJustifyH("CENTER")
    f.emptyText = emptyText

    -- Animated Progress Bar
    local progressBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    progressBar:SetPoint("BOTTOMLEFT", 8, 38)
    progressBar:SetPoint("BOTTOMRIGHT", -8, 38)
    progressBar:SetHeight(16)
    common.apply_flat_backdrop(progressBar, { 0.05, 0.05, 0.07, 0.95 }, { 0.22, 0.22, 0.26, 1 })

    local barFill = progressBar:CreateTexture(nil, "ARTWORK")
    barFill:SetPoint("TOPLEFT", 1, -1)
    barFill:SetPoint("BOTTOMLEFT", 1, 1)
    barFill:SetColorTexture(0.2, 0.75, 0.4, 0.85)
    barFill:SetWidth(0)
    progressBar.fill = barFill

    local barText = progressBar:CreateFontString(nil, "OVERLAY", sfui.config.font)
    barText:SetFont(common.get_font_file(), 9, "OUTLINE")
    barText:SetPoint("CENTER", 0, 0)
    barText:SetTextColor(1, 1, 1, 1)
    progressBar.text = barText
    progressBar:Hide()
    f.progressBar = progressBar

    -- Progress Status Text (fallback)
    local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("BOTTOM", 0, 56)
    statusText:SetTextColor(0.8, 0.8, 0.4, 1)
    statusText:Hide()
    f.statusText = statusText

    -- Open All Button (Collect All Inbox Mail)
    local openAllBtn = common.create_flat_button(f, "open all", 130, 26, function()
        if mail.IsCollectingInbox() then
            mail.CancelInboxCollection("user cancelled")
            HideProgressBar()
            RefreshSidecar()
            return
        end

        local started, err = mail.StartInboxCollection(function(curr, total)
            UpdateProgressBar(curr, total, string.format("opening %d / %d...", curr, total))
            if f.openAllBtn then f.openAllBtn:SetText("cancel") end
        end, function(success, reason)
            HideProgressBar()
            mail.RecordMailboxStatus()
            RefreshSidecar()
            if C_Timer and C_Timer.After then
                C_Timer.After(0.8, function()
                    mail.RecordMailboxStatus()
                    RefreshSidecar()
                end)
            end
        end)

        if not started and common and common.print then
            common.print(string.format("|cffff3333inbox error: %s.|r", err or "unknown"))
        end
    end)
    openAllBtn:ClearAllPoints()
    openAllBtn:SetPoint("BOTTOMLEFT", 8, 8)
    openAllBtn:SetFrameLevel((f:GetFrameLevel() or 1) + 20)
    openAllBtn.tooltip = "collect all incoming mail attachments & money"
    f.openAllBtn = openAllBtn

    -- Dispatch All Button
    local dispatchBtn = common.create_flat_button(f, "send all", 130, 26, function()
        if mail.IsDispatching() then
            mail.CancelDispatch("user cancelled")
            HideProgressBar()
            RefreshSidecar()
            return
        end

        local started, err = mail.StartDispatch(function(curr, total, recipient)
            UpdateProgressBar(curr, total, string.format("sending %d of %d to %s...", curr, total, recipient))
            f.dispatchBtn:SetText("cancel")
        end, function(success, reason)
            HideProgressBar()
            RefreshSidecar()
            if C_Timer and C_Timer.After then
                C_Timer.After(0.8, RefreshSidecar)
            end
        end)

        if not started and common and common.print then
            common.print(string.format("|cffff3333dispatch error: %s.|r", err or "unknown"))
        end
    end)
    dispatchBtn:ClearAllPoints()
    dispatchBtn:SetPoint("BOTTOMRIGHT", -8, 8)
    dispatchBtn:SetFrameLevel((f:GetFrameLevel() or 1) + 20)
    dispatchBtn.tooltip = "dispatch all queued items to matched alts"
    f.dispatchBtn = dispatchBtn

    sidecarFrame = f
    return f
end

--- Dock sidecar to Blizzard MailFrame
local function ShowSidecarAtMailbox()
    local settings = mail.GetSettings()
    if not settings.enabled then return end

    local parent = _G.MailFrame
    if not parent or not parent:IsShown() then return end

    local f = mail.CreateMailboxSidecar()
    f:SetParent(parent)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", parent, "TOPRIGHT", 5, 0)
    f:SetHeight(parent:GetHeight() or 420)
    f:SetFrameStrata(parent:GetFrameStrata() or "HIGH")
    f:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)
    if sfui.theme and sfui.theme.ElevateWindowContents then
        sfui.theme.ElevateWindowContents(f)
    end
    if f.cfgBtn then
        f.cfgBtn:SetFrameLevel(f:GetFrameLevel() + 20)
    end
    if f.openAllBtn then
        f.openAllBtn:SetFrameLevel(f:GetFrameLevel() + 20)
    end
    if f.dispatchBtn then
        f.dispatchBtn:SetFrameLevel(f:GetFrameLevel() + 20)
    end
    f:Show()
    mail.RecordMailboxStatus()
    RefreshSidecar()
end

--- Toggle sidecar docked to Blizzard MailFrame
function mail.ToggleMailboxSidecar()
    local parent = _G.MailFrame
    if not parent or not parent:IsShown() then return end

    local f = mail.CreateMailboxSidecar()
    if f:IsShown() then
        f:Hide()
    else
        ShowSidecarAtMailbox()
    end
end
sfui.alts.ToggleMailSidecar = mail.ToggleMailboxSidecar

--- Setup toggle button on Blizzard MailFrame header
local function SetupMailFrameHook()
    local mailFrame = _G.MailFrame
    if not mailFrame or mailFrame._sfuiMailHooked then return end
    mailFrame._sfuiMailHooked = true

    -- Add toggle button to MailFrame top bar next to close button
    local toggleBtn = common.create_flat_button(mailFrame, "alts", 46, 20, function()
        mail.ToggleMailboxSidecar()
    end)
    mailFrame._sfuiSidecarToggle = toggleBtn

    local closeBtn = _G.MailFrameCloseButton or mailFrame.CloseButton
    if closeBtn then
        toggleBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    else
        toggleBtn:SetPoint("TOPRIGHT", mailFrame, "TOPRIGHT", -32, -4)
    end
    toggleBtn:SetFrameLevel((mailFrame:GetFrameLevel() or 1) + 25)
    toggleBtn.tooltip = "toggle sfui alts mail dispatch sidecar"

    -- Quick alt recipient selector on SendMailFrame
    local sendMailFrame = _G.SendMailFrame
    local nameBox = _G.SendMailNameEditBox
    if sendMailFrame and nameBox and not sendMailFrame._sfuiAltDropdown then
        local function GetQuickAltOptions()
            local alts = mail.GetAlts(false) -- exclude current character
            local opts = {}
            for _, a in ipairs(alts) do
                local recipient = (sfui.alts and sfui.alts.GetMailRecipient and sfui.alts.GetMailRecipient(a)) or a.name
                table.insert(opts, {
                    label = string.format("%s (lvl %d)", common.class_color_name(a.name, a.class), a.level or 1),
                    value = recipient,
                })
            end
            if #opts == 0 then
                table.insert(opts, { label = "no other alts", value = "" })
            end
            return opts
        end

        local function OnQuickAltSelected(name)
            if name and name ~= "" and _G.SendMailNameEditBox then
                _G.SendMailNameEditBox:SetText(name)
                _G.SendMailNameEditBox:SetFocus()
                if _G.SendMailFrame_CanSend then
                    _G.SendMailFrame_CanSend()
                end
            end
        end

        local altDd = widgets.create_dropdown(sendMailFrame, 40, GetQuickAltOptions, OnQuickAltSelected, nil, "alts", 160)
        altDd:ClearAllPoints()
        altDd:SetPoint("LEFT", nameBox, "RIGHT", 4, 0)
        altDd:SetFrameLevel((sendMailFrame:GetFrameLevel() or 1) + 20)
        altDd.tooltip = "quick select recipient alt"
        sendMailFrame._sfuiAltDropdown = altDd
    end

    mailFrame:HookScript("OnShow", function()
        if toggleBtn and toggleBtn.SetFrameLevel then
            toggleBtn:SetFrameLevel((mailFrame:GetFrameLevel() or 1) + 25)
        end
        mail.RecordMailboxStatus()
        local settings = mail.GetSettings()
        if settings.enabled and settings.autoOpenAtMailbox ~= false then
            ShowSidecarAtMailbox()
        end
    end)

    mailFrame:HookScript("OnHide", function()
        if sidecarFrame then
            sidecarFrame:Hide()
        end
    end)

    if mailFrame:IsShown() then
        mail.RecordMailboxStatus()
        local settings = mail.GetSettings()
        if settings.enabled and settings.autoOpenAtMailbox ~= false then
            ShowSidecarAtMailbox()
        end
    end
end

-- Hook immediately if MailFrame already exists
if _G.MailFrame then
    SetupMailFrameHook()
end

-- ─── Event Listeners ─────────────────────────────────────────────────────────
if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("PLAYER_LOGIN", function()
        SetupMailFrameHook()
    end)

    sfui.events.RegisterEvent("ADDON_LOADED", function(_, loadedAddon)
        if loadedAddon == "Blizzard_MailFrame" then
            SetupMailFrameHook()
        end
    end)

    sfui.events.RegisterEvent("MAIL_SHOW", function()
        SetupMailFrameHook()
        mail.RecordMailboxStatus()
        local settings = mail.GetSettings()
        if settings.enabled and settings.autoOpenAtMailbox ~= false then
            C_Timer.After(0.05, ShowSidecarAtMailbox)
        end
    end)

    sfui.events.RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(_, interactionType)
        local mailType = _G.Enum and _G.Enum.PlayerInteractionType and _G.Enum.PlayerInteractionType.MailInfo
        if not interactionType or interactionType == mailType then
            SetupMailFrameHook()
            mail.RecordMailboxStatus()
            local settings = mail.GetSettings()
            if settings.enabled and settings.autoOpenAtMailbox ~= false then
                C_Timer.After(0.05, ShowSidecarAtMailbox)
            end
        end
    end)

    sfui.events.RegisterEvent("MAIL_INBOX_UPDATE", function()
        mail.RecordMailboxStatus()
        if sidecarFrame and sidecarFrame:IsShown() then
            RefreshSidecar()
        end
    end)

    sfui.events.RegisterEvent("MAIL_CLOSED", function()
        if sidecarFrame then
            sidecarFrame:Hide()
        end
    end)

    sfui.events.RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(_, interactionType)
        local mailType = _G.Enum and _G.Enum.PlayerInteractionType and _G.Enum.PlayerInteractionType.MailInfo
        if not interactionType or interactionType == mailType then
            if sidecarFrame then
                sidecarFrame:Hide()
            end
        end
    end)

    sfui.events.RegisterEvent("BAG_UPDATE_DELAYED", function()
        if sidecarFrame and sidecarFrame:IsShown() and not mail.IsDispatching() then
            RefreshSidecar()
        end
    end)
end

