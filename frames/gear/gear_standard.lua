local addonName, addon = ...
sfui = sfui or {}
sfui.gear = sfui.gear or {}

-- Guard: Retail only
if not sfui.isRetail then
    return
end

local common = sfui.common
local _G = _G
local CreateFrame = _G.CreateFrame
local ipairs = _G.ipairs
local pairs = _G.pairs
local type = _G.type
local table = _G.table
local tostring = _G.tostring

local function show_tooltip(owner, anchor, title, lines)
    local tip = sfui.common.get_tooltip()
    if not tip or not owner then return end
    tip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    if title then
        tip:SetText(tostring(title):lower())
    end
    if lines then
        for _, line in ipairs(lines) do
            if type(line) == "table" then
                local txt = line[1] and tostring(line[1]):lower() or ""
                tip:AddLine(txt, line[2], line[3], line[4], line[5])
            else
                tip:AddLine(tostring(line):lower())
            end
        end
    end
    tip:Show()
end

local hide_tooltip = sfui.common.hide_tooltip

-- Header height for Retail (accommodates spec tabs row)
function sfui.gear.GetHeaderHeight()
    return 56
end

-- -------------------------------------------------------------------------
-- RETAIL HEADER SPEC TABS
-- -------------------------------------------------------------------------
function sfui.gear.SetupHeaderTabs(gearFrame, specIDs)
    if not gearFrame then return end
    gearFrame.tabBtns = gearFrame.tabBtns or {}

    local startX = 12
    for _, id in ipairs(specIDs or {}) do
        local icon = common.get_spec_icon(id)
        if id and icon then
            local btn = CreateFrame("Button", nil, gearFrame, "BackdropTemplate")
            btn:SetSize(22, 22)
            btn:SetPoint("TOPLEFT", gearFrame, "TOPLEFT", startX, -30)
            local t = btn:CreateTexture(nil, "ARTWORK")
            t:SetAllPoints()
            t:SetTexture(icon)
            t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn.tex = t
            btn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            btn:SetBackdropColor(0, 0, 0, 0.7)
            btn:SetBackdropBorderColor(0, 0, 0, 0.8)
            btn:SetScript("OnClick", function() gearFrame:SelectSpecTab(id) end)
            btn:SetScript("OnEnter", function(b)
                b:SetAlpha(1.0)
                local specName = common.get_spec_name(id)
                show_tooltip(b, "ANCHOR_TOP", (specName and specName:lower()) or "specialization")
            end)
            btn:SetScript("OnLeave", function(b)
                if gearFrame.activeSpecID ~= id then
                    b:SetAlpha(0.40)
                end
                hide_tooltip()
            end)
            gearFrame.tabBtns[id] = btn
            startX = startX + 26
        end
    end
end

-- -------------------------------------------------------------------------
-- CARD MODIFIERS BUILDER (2s, 4s, 2e, ilvl buttons on Row 2B)
-- -------------------------------------------------------------------------
function sfui.gear.BuildCardModifiers(card, ui, specID, curLockX)
    local btn2S = common.create_flat_button(card, "2s", 26, 20)
    btn2S:SetPoint("TOPLEFT", card, "TOPLEFT", 260, -57)
    btn2S:SetScript("OnClick", function()
        SfuiDB.gear[specID] = SfuiDB.gear[specID] or {}
        SfuiDB.gear[specID].force_2set = not SfuiDB.gear[specID].force_2set
        if SfuiDB.gear[specID].force_2set then SfuiDB.gear[specID].force_4set = false end
        sfui.gear.UpdateStatUI()
        sfui.gear.Update()
    end)
    btn2S:SetScript("OnEnter", function(b)
        if sfui.theme and sfui.theme.IsAuctionHouseButtonActive and sfui.theme.IsAuctionHouseButtonActive() then
            if b._sfuiAHHighlight then b._sfuiAHHighlight:Show() end
        end
        show_tooltip(b, "ANCHOR_TOP", "force 2-piece tier set", {
            { "drafts 2 set pieces into your highest ilvl build, prioritizing lowest ilvl sacrifice.", 0.8, 0.8, 0.8, true }
        })
    end)
    btn2S:SetScript("OnLeave", function(b)
        if sfui.theme and sfui.theme.IsAuctionHouseButtonActive and sfui.theme.IsAuctionHouseButtonActive() then
            if b._sfuiAHHighlight then b._sfuiAHHighlight:Hide() end
        end
        hide_tooltip()
    end)
    ui.btn2S = btn2S

    local btn4S = common.create_flat_button(card, "4s", 26, 20)
    btn4S:SetPoint("TOPLEFT", btn2S, "TOPRIGHT", 4, 0)
    btn4S:SetScript("OnClick", function()
        SfuiDB.gear[specID] = SfuiDB.gear[specID] or {}
        local cur = (SfuiDB.gear[specID].force_4set ~= false) and not SfuiDB.gear[specID].force_2set
        SfuiDB.gear[specID].force_4set = not cur
        if SfuiDB.gear[specID].force_4set then SfuiDB.gear[specID].force_2set = false end
        sfui.gear.UpdateStatUI()
        sfui.gear.Update()
    end)
    btn4S:SetScript("OnEnter", function(b)
        if sfui.theme and sfui.theme.IsAuctionHouseButtonActive and sfui.theme.IsAuctionHouseButtonActive() then
            if b._sfuiAHHighlight then b._sfuiAHHighlight:Show() end
        end
        show_tooltip(b, "ANCHOR_TOP", "force 4-piece tier set", {
            { "drafts 4 set pieces into your highest ilvl build, prioritizing lowest ilvl sacrifice.", 0.8, 0.8, 0.8, true }
        })
    end)
    btn4S:SetScript("OnLeave", function(b)
        if sfui.theme and sfui.theme.IsAuctionHouseButtonActive and sfui.theme.IsAuctionHouseButtonActive() then
            if b._sfuiAHHighlight then b._sfuiAHHighlight:Hide() end
        end
        hide_tooltip()
    end)
    ui.btn4S = btn4S

    local btn2E = common.create_flat_button(card, "2e", 26, 20)
    btn2E:SetPoint("TOPLEFT", btn4S, "TOPRIGHT", 4, 0)
    btn2E:SetScript("OnClick", function()
        SfuiDB.gear[specID] = SfuiDB.gear[specID] or {}
        local cur = SfuiDB.gear[specID].force_embellishment or SfuiDB.gear[specID].force_2emb or SfuiDB.gear[specID].force_2embellishments
        local newVal = not cur
        SfuiDB.gear[specID].force_embellishment = newVal
        SfuiDB.gear[specID].force_2emb = newVal
        sfui.gear.UpdateStatUI()
        sfui.gear.Update()
    end)
    btn2E:SetScript("OnEnter", function(b)
        if sfui.theme and sfui.theme.IsAuctionHouseButtonActive and sfui.theme.IsAuctionHouseButtonActive() then
            if b._sfuiAHHighlight then b._sfuiAHHighlight:Show() end
        end
        show_tooltip(b, "ANCHOR_TOP", "force 2 embellishments", {
            { "drafts up to 2 unique embellished items into your gear set.", 0.8, 0.8, 0.8, true }
        })
    end)
    btn2E:SetScript("OnLeave", function(b)
        if sfui.theme and sfui.theme.IsAuctionHouseButtonActive and sfui.theme.IsAuctionHouseButtonActive() then
            if b._sfuiAHHighlight then b._sfuiAHHighlight:Hide() end
        end
        hide_tooltip()
    end)
    ui.btn2E = btn2E

    local btnILvl = common.create_flat_button(card, "ilvl", 32, 20)
    btnILvl:SetPoint("TOPLEFT", btn2E, "TOPRIGHT", 4, 0)
    btnILvl:SetScript("OnClick", function()
        SfuiDB.gear[specID] = SfuiDB.gear[specID] or {}
        SfuiDB.gear[specID].force_ilvl = not SfuiDB.gear[specID].force_ilvl
        sfui.gear.UpdateStatUI()
        sfui.gear.Update()
    end)
    btnILvl:SetScript("OnEnter", function(b)
        if sfui.theme and sfui.theme.IsAuctionHouseButtonActive and sfui.theme.IsAuctionHouseButtonActive() then
            if b._sfuiAHHighlight then b._sfuiAHHighlight:Show() end
        end
        show_tooltip(b, "ANCHOR_TOP", "highest ilvl override", {
            { "strictly maximizes overall average item level, overriding stat-weighting tradeoffs.", 0.8, 0.8, 0.8, true }
        })
    end)
    btnILvl:SetScript("OnLeave", function(b)
        if sfui.theme and sfui.theme.IsAuctionHouseButtonActive and sfui.theme.IsAuctionHouseButtonActive() then
            if b._sfuiAHHighlight then b._sfuiAHHighlight:Hide() end
        end
        hide_tooltip()
    end)
    ui.btnILvl = btnILvl
end

-- -------------------------------------------------------------------------
-- UI FLAVOR REFRESH (Retail 2s, 4s, 2e, ilvl buttons and tab buttons)
-- -------------------------------------------------------------------------
function sfui.gear.UpdateFlavorUI(ui, specID, db)
    if not ui then return end

    local useAH = sfui.theme and sfui.theme.IsAuctionHouseButtonActive and sfui.theme.IsAuctionHouseButtonActive()
    local pal = sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()
    local activeColor = pal and pal.accentColor or { 0.95, 0.85, 0.55 }

    if ui.btn2S then
        local force2 = db and db.force_2set
        if useAH then
            sfui.theme.SetButtonSelected(ui.btn2S, force2)
            ui.btn2S:SetBackdropColor(0, 0, 0, 0)
            ui.btn2S:SetBackdropBorderColor(0, 0, 0, 0)
        else
            if force2 then
                ui.btn2S:SetBackdropColor(activeColor[1] * 0.25, activeColor[2] * 0.25, activeColor[3] * 0.25, 0.9)
                ui.btn2S:SetBackdropBorderColor(activeColor[1], activeColor[2], activeColor[3], 1)
            else
                ui.btn2S:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
                ui.btn2S:SetBackdropBorderColor(0, 0, 0, 1)
            end
        end
    end

    if ui.btn4S then
        local force4 = db and (db.force_4set ~= false) and not db.force_2set
        if useAH then
            sfui.theme.SetButtonSelected(ui.btn4S, force4)
            ui.btn4S:SetBackdropColor(0, 0, 0, 0)
            ui.btn4S:SetBackdropBorderColor(0, 0, 0, 0)
        else
            if force4 then
                ui.btn4S:SetBackdropColor(activeColor[1] * 0.25, activeColor[2] * 0.25, activeColor[3] * 0.25, 0.9)
                ui.btn4S:SetBackdropBorderColor(activeColor[1], activeColor[2], activeColor[3], 1)
            else
                ui.btn4S:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
                ui.btn4S:SetBackdropBorderColor(0, 0, 0, 1)
            end
        end
    end

    if ui.btn2E then
        local force2e = db and (db.force_embellishment or db.force_2emb or db.force_2embellishments)
        if useAH then
            sfui.theme.SetButtonSelected(ui.btn2E, force2e)
            ui.btn2E:SetBackdropColor(0, 0, 0, 0)
            ui.btn2E:SetBackdropBorderColor(0, 0, 0, 0)
        else
            if force2e then
                ui.btn2E:SetBackdropColor(activeColor[1] * 0.25, activeColor[2] * 0.25, activeColor[3] * 0.25, 0.9)
                ui.btn2E:SetBackdropBorderColor(activeColor[1], activeColor[2], activeColor[3], 1)
            else
                ui.btn2E:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
                ui.btn2E:SetBackdropBorderColor(0, 0, 0, 1)
            end
        end
    end

    if ui.btnILvl then
        local forceIlvl = db and db.force_ilvl
        if useAH then
            sfui.theme.SetButtonSelected(ui.btnILvl, forceIlvl)
            ui.btnILvl:SetBackdropColor(0, 0, 0, 0)
            ui.btnILvl:SetBackdropBorderColor(0, 0, 0, 0)
        else
            if forceIlvl then
                ui.btnILvl:SetBackdropColor(activeColor[1] * 0.25, activeColor[2] * 0.25, activeColor[3] * 0.25, 0.9)
                ui.btnILvl:SetBackdropBorderColor(activeColor[1], activeColor[2], activeColor[3], 1)
            else
                ui.btnILvl:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
                ui.btnILvl:SetBackdropBorderColor(0, 0, 0, 1)
            end
        end
    end

    if SfuiGearManagerFrame and SfuiGearManagerFrame.tabBtns then
        local curSpec = SfuiGearManagerFrame.activeSpecID or common.get_current_spec_id()
        for id, btn in pairs(SfuiGearManagerFrame.tabBtns) do
            if id == curSpec then
                btn:SetAlpha(1.0)
                btn:SetBackdropBorderColor(activeColor[1], activeColor[2], activeColor[3], 1.0)
            else
                btn:SetAlpha(0.40)
                btn:SetBackdropBorderColor(0, 0, 0, 0.8)
            end
        end
    end
end
