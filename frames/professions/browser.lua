local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.professions = sfui.professions or {}
sfui.recipes = sfui.recipes or {}
sfui.recipes.browser = sfui.recipes.browser or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/professions/browser.lua
--  Native Recipe Catalog & Source Browser (Camelot / Classic Forever)
--
--  Searchable, filterable browser populated with the character's professions.
--  Rows display: [ Recipe Link ] - Trainer/Vendor - Location (x, y).
--  Clicking any row sets a map waypoint with super-tracking navigation.
--  Shift-clicking any row inserts the recipe hyperlink directly into chat.
-- ══════════════════════════════════════════════════════════════════════════════

if not sfui.isCamelot then return end

local B = sfui.recipes.browser
local common = sfui.common
local theme  = sfui.theme
local GameTooltip = sfui.common.get_tooltip()

--- Dynamically refresh profession tabs based only on character's learned professions
function B.UpdateProfessionTabs()
    local ui = B.ui
    if not ui.profRow then return end
    B.playerProfessions = B.GetPlayerProfessionsList()

    -- Hide all existing tab frames
    for _, btn in pairs(ui.profButtons) do
        btn:Hide()
    end

    if #B.playerProfessions == 0 then
        B.selectedSkillID = nil
        B.activeSpecFilter = nil
        B.activeCategoryFilter = nil
        if B.UpdateSpecButtons then B.UpdateSpecButtons() end
        B.RebuildFilteredList()
        B.ResetScroll()
        B.UpdateList()
        return
    end

    -- Verify selectedSkillID belongs to this character
    local valid = false
    for _, p in ipairs(B.playerProfessions) do
        if p.skillID == B.selectedSkillID then
            valid = true
            break
        end
    end
    if not valid then
        B.selectedSkillID = B.playerProfessions[1].skillID
        B.activeSpecFilter = nil
        B.activeCategoryFilter = nil
    end

    local prevBtn = nil
    for i, p in ipairs(B.playerProfessions) do
        local btn = ui.profButtons[i]
        if not btn then
            btn = CreateFrame("Button", nil, ui.profRow, "BackdropTemplate")
            btn:SetHeight(22)
            local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn.fs = fs
            if btn.SetFontString then btn:SetFontString(fs) end
            ui.profButtons[i] = btn
        end

        local isSelected = (p.skillID == B.selectedSkillID)
        local tabLabel = string.format("%s (%d/%d)", p.name:lower(), p.rank, p.maxRank)
        btn.fs:SetText(tabLabel)
        btn:SetWidth(btn.fs:GetStringWidth() + 18)

        if theme and theme.ApplyTabStyle then
            theme.ApplyTabStyle(btn, isSelected)
        else
            common.apply_flat_backdrop(btn, isSelected and { 0.25, 0.20, 0.06, 0.85 } or { 0.08, 0.08, 0.10, 0.50 },
                                            isSelected and { 1, 0.82, 0, 0.85 } or { 0.20, 0.20, 0.24, 0.50 })
            btn.fs:SetTextColor(isSelected and 1 or 0.66, isSelected and 0.82 or 0.66, isSelected and 0 or 0.66, 1)
        end

        btn:ClearAllPoints()
        if not prevBtn then
            btn:SetPoint("LEFT", ui.profRow, "LEFT", 4, 0)
        else
            btn:SetPoint("LEFT", prevBtn, "RIGHT", 6, 0)
        end
        prevBtn = btn
        btn.skillID = p.skillID
        btn:Show()

        btn:SetScript("OnClick", function()
            B.selectedSkillID = p.skillID
            B.activeSpecFilter = nil
            B.activeCategoryFilter = nil
            B.UpdateProfessionTabs()
            if B.UpdateSpecButtons then B.UpdateSpecButtons() end
            B.RebuildFilteredList()
            B.ResetScroll()
            B.UpdateList()
        end)
    end
end

--- Update state filter buttons (unlearned, all, learned)
function B.UpdateStateButtons()
    local ui = B.ui
    for sKey, b in pairs(ui.stateButtons) do
        local isSelected = (sKey == B.filterState)
        if theme and theme.ApplyTabStyle then
            theme.ApplyTabStyle(b, isSelected)
        else
            if isSelected then
                b:SetBackdropColor(0.25, 0.20, 0.06, 0.90)
                b:SetBackdropBorderColor(1, 0.82, 0, 0.90)
                b.fs:SetTextColor(1, 0.82, 0, 1)
            else
                b:SetBackdropColor(0.08, 0.08, 0.10, 0.60)
                b:SetBackdropBorderColor(0.20, 0.20, 0.24, 0.60)
                b.fs:SetTextColor(0.66, 0.66, 0.66, 1)
            end
        end
    end
end

--- Update events filter button appearance
function B.UpdateEventsButton()
    local eb = B.ui.eventsButton
    if not eb then return end
    eb.fs:SetText(B.showEventRecipes and "events: show" or "events: hide")
    if theme and theme.ApplyTabStyle then
        theme.ApplyTabStyle(eb, B.showEventRecipes)
    else
        if B.showEventRecipes then
            eb:SetBackdropColor(0.25, 0.20, 0.06, 0.90)
            eb:SetBackdropBorderColor(1, 0.82, 0, 0.90)
            eb.fs:SetTextColor(1, 0.82, 0, 1)
        else
            eb:SetBackdropColor(0.08, 0.08, 0.10, 0.60)
            eb:SetBackdropBorderColor(0.20, 0.20, 0.24, 0.60)
            eb.fs:SetTextColor(0.55, 0.55, 0.55, 1)
        end
    end
end

--- Update current zone filter button appearance
function B.UpdateZoneButton()
    local zb = B.ui.zoneButton
    if not zb then return end
    zb.fs:SetText(B.showCurrentZoneOnly and "zone: current" or "zone: all")
    if theme and theme.ApplyTabStyle then
        theme.ApplyTabStyle(zb, B.showCurrentZoneOnly)
    else
        if B.showCurrentZoneOnly then
            zb:SetBackdropColor(0.25, 0.20, 0.06, 0.90)
            zb:SetBackdropBorderColor(1, 0.82, 0, 0.90)
            zb.fs:SetTextColor(1, 0.82, 0, 1)
        else
            zb:SetBackdropColor(0.08, 0.08, 0.10, 0.60)
            zb:SetBackdropBorderColor(0.20, 0.20, 0.24, 0.60)
            zb.fs:SetTextColor(0.55, 0.55, 0.55, 1)
        end
    end
end

--- Update source filter buttons appearance
function B.UpdateSourceButtons()
    local ui = B.ui
    for _, item in ipairs(B.SOURCE_FILTERS) do
        local b = ui.sourceButtons[item.key]
        if b then
            local isSelected = (B.sourceFilters[item.key] == true)
            if theme and theme.ApplyTabStyle then
                theme.ApplyTabStyle(b, isSelected)
            else
                if isSelected then
                    b:SetBackdropColor(0.25, 0.20, 0.06, 0.90)
                    b:SetBackdropBorderColor(1, 0.82, 0, 0.90)
                    b.fs:SetTextColor(1, 0.82, 0, 1)
                else
                    b:SetBackdropColor(0.08, 0.08, 0.10, 0.60)
                    b:SetBackdropBorderColor(0.20, 0.20, 0.24, 0.60)
                    b.fs:SetTextColor(0.66, 0.66, 0.66, 1)
                end
            end
        end
    end
end

--- Update specialization buttons and category filter pills
function B.UpdateSpecButtons()
    local ui = B.ui
    if not ui.specRow then return end

    for _, b in ipairs(ui.specButtons) do
        b:Hide()
    end
    for _, b in ipairs(ui.categoryButtons) do
        b:Hide()
    end
    if ui.catDivider then
        ui.catDivider:Hide()
    end

    local specs = B.GetSpecsForProfession(B.selectedSkillID)
    local cats = B.PROFESSION_CATEGORIES[B.selectedSkillID]
    local prevBtn = nil

    -- 1. Render Specialization Buttons
    if specs and #specs > 0 then
        ui.specLabel:SetText("|cffaaaaaaspec:|r")
        ui.specLabel:Show()

        local btnDefs = {
            { key = nil,       label = "all specs", isAll = true },
            { key = "general", label = "general" },
        }
        for _, item in ipairs(specs) do
            local isKnown = B.PlayerHasSpec(item.key)
            local displayLabel = isKnown and (item.label .. " *") or item.label
            table.insert(btnDefs, {
                key = item.key,
                label = displayLabel,
                rawLabel = item.label,
                isKnown = isKnown,
            })
        end

        for i, def in ipairs(btnDefs) do
            local btn = ui.specButtons[i]
            if not btn then
                btn = CreateFrame("Button", nil, ui.specRow, "BackdropTemplate")
                btn:SetHeight(20)
                local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
                btn.fs = fs
                if btn.SetFontString then btn:SetFontString(fs) end
                ui.specButtons[i] = btn
            end

            local isSelected = (def.key == B.activeSpecFilter)
            if def.isAll and (B.activeSpecFilter == nil) then
                isSelected = true
            end

            btn.fs:SetText(def.label)
            btn:SetWidth(btn.fs:GetStringWidth() + 14)

            if theme and theme.ApplyTabStyle then
                theme.ApplyTabStyle(btn, isSelected)
            else
                if isSelected then
                    btn:SetBackdropColor(0.25, 0.20, 0.06, 0.90)
                    btn:SetBackdropBorderColor(1, 0.82, 0, 0.90)
                    btn.fs:SetTextColor(1, 0.82, 0, 1)
                else
                    btn:SetBackdropColor(0.08, 0.08, 0.10, 0.60)
                    btn:SetBackdropBorderColor(0.20, 0.20, 0.24, 0.60)
                    btn.fs:SetTextColor(def.isKnown and 0.90 or 0.66, def.isKnown and 0.80 or 0.66, def.isKnown and 0.40 or 0.66, 1)
                end
            end

            btn:ClearAllPoints()
            if not prevBtn then
                btn:SetPoint("LEFT", ui.specLabel, "RIGHT", 6, 0)
            else
                btn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
            end
            prevBtn = btn

            btn:SetScript("OnClick", function()
                if def.isAll then
                    B.activeSpecFilter = nil
                else
                    if B.activeSpecFilter == def.key then
                        B.activeSpecFilter = nil
                    else
                        B.activeSpecFilter = def.key
                    end
                end
                B.UpdateSpecButtons()
                B.RebuildFilteredList()
                B.ResetScroll()
                B.UpdateList()
            end)

            btn:SetScript("OnEnter", function(self)
                if GameTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    if def.isAll then
                        GameTooltip:AddLine("all specializations", 1, 0.82, 0)
                        GameTooltip:AddLine("show all recipes regardless of specialization requirement.", 0.9, 0.9, 0.9, true)
                    elseif def.key == "general" then
                        GameTooltip:AddLine("general recipes", 1, 0.82, 0)
                        GameTooltip:AddLine("show only base recipes that do not require any specialization.", 0.9, 0.9, 0.9, true)
                    else
                        local title = def.rawLabel or def.key
                        if def.isKnown then
                            GameTooltip:AddLine(title .. " |cff40c040(learned)|r", 1, 0.82, 0)
                            GameTooltip:AddLine("this character has learned this specialization.", 0.6, 1, 0.6, true)
                        else
                            GameTooltip:AddLine(title, 1, 0.82, 0)
                        end
                        GameTooltip:AddLine("filter recipes requiring the " .. title .. " specialization.", 0.9, 0.9, 0.9, true)
                        GameTooltip:AddLine("click to toggle filter.", 0.6, 0.8, 1, true)
                    end
                    GameTooltip:Show()
                end
            end)

            btn:SetScript("OnLeave", function()
                if GameTooltip then GameTooltip:Hide() end
            end)

            btn:Show()
        end
    else
        B.activeSpecFilter = nil
    end

    -- 2. Render Sub-Category / Slot Filter Pills
    if cats and #cats > 0 then
        if specs and #specs > 0 then
            ui.catDivider:ClearAllPoints()
            ui.catDivider:SetPoint("LEFT", prevBtn, "RIGHT", 8, 0)
            ui.catDivider:Show()
            prevBtn = ui.catDivider
        else
            ui.specLabel:SetText("|cffaaaaaacategory:|r")
            ui.specLabel:Show()
            prevBtn = ui.specLabel
        end

        for cIdx, cDef in ipairs(cats) do
            local cBtn = ui.categoryButtons[cIdx]
            if not cBtn then
                cBtn = CreateFrame("Button", nil, ui.specRow, "BackdropTemplate")
                cBtn:SetHeight(20)
                local fs = cBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetPoint("CENTER", cBtn, "CENTER", 0, 0)
                cBtn.fs = fs
                if cBtn.SetFontString then cBtn:SetFontString(fs) end
                ui.categoryButtons[cIdx] = cBtn
            end

            local isSelected = (cDef.key == B.activeCategoryFilter)
            if cDef.key == nil and (B.activeCategoryFilter == nil) then
                isSelected = true
            end

            cBtn.fs:SetText(cDef.label)
            cBtn:SetWidth(cBtn.fs:GetStringWidth() + 14)

            if theme and theme.ApplyTabStyle then
                theme.ApplyTabStyle(cBtn, isSelected)
            else
                if isSelected then
                    cBtn:SetBackdropColor(0.25, 0.20, 0.06, 0.90)
                    cBtn:SetBackdropBorderColor(1, 0.82, 0, 0.90)
                    cBtn.fs:SetTextColor(1, 0.82, 0, 1)
                else
                    cBtn:SetBackdropColor(0.08, 0.08, 0.10, 0.60)
                    cBtn:SetBackdropBorderColor(0.20, 0.20, 0.24, 0.60)
                    cBtn.fs:SetTextColor(0.66, 0.66, 0.66, 1)
                end
            end

            cBtn:ClearAllPoints()
            if prevBtn == ui.catDivider then
                cBtn:SetPoint("LEFT", prevBtn, "RIGHT", 6, 0)
            elseif prevBtn == ui.specLabel then
                cBtn:SetPoint("LEFT", prevBtn, "RIGHT", 6, 0)
            else
                cBtn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
            end
            prevBtn = cBtn

            cBtn:SetScript("OnClick", function()
                if cDef.key == nil then
                    B.activeCategoryFilter = nil
                else
                    if B.activeCategoryFilter == cDef.key then
                        B.activeCategoryFilter = nil
                    else
                        B.activeCategoryFilter = cDef.key
                    end
                end
                B.UpdateSpecButtons()
                B.RebuildFilteredList()
                B.ResetScroll()
                B.UpdateList()
            end)

            cBtn:SetScript("OnEnter", function(self)
                if GameTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:AddLine("category: " .. cDef.label, 1, 0.82, 0)
                    GameTooltip:AddLine("filter recipes by " .. cDef.label .. ".", 0.9, 0.9, 0.9, true)
                    GameTooltip:AddLine("click to toggle filter.", 0.6, 0.8, 1, true)
                    GameTooltip:Show()
                end
            end)

            cBtn:SetScript("OnLeave", function()
                if GameTooltip then GameTooltip:Hide() end
            end)

            cBtn:Show()
        end
    else
        B.activeCategoryFilter = nil
        if not specs or #specs == 0 then
            ui.specLabel:SetText("|cff666666filters: none available for this profession|r")
            ui.specLabel:Show()
        end
    end
end

--- Create the main recipe browser frame
--- @return Frame frame
function B.CreateBrowserFrame()
    local ui = B.ui
    local cfg = B.CFG
    if ui.frame then return ui.frame end

    local f = CreateFrame("Frame", "SfuiRecipeBrowserFrame", UIParent, "BackdropTemplate")
    f:SetSize(cfg.FRAME_W, cfg.FRAME_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

    if _G.UISpecialFrames then
        table.insert(_G.UISpecialFrames, "SfuiRecipeBrowserFrame")
    end

    common.apply_flat_backdrop(f, { 0.05, 0.05, 0.07, 0.97 }, { 0.12, 0.12, 0.14, 1 })

    -- ── Header Bar ────────────────────────────────────────────────────────────
    local headerBar = (theme.CreateWindowHeader or sfui.theme.CreateWindowHeader)(f, "recipe catalog")
    f.headerBar = headerBar

    -- ── Close Button ──────────────────────────────────────────────────────────
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.closeBtn = closeBtn
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
    closeBtn:SetSize(28, 28)
    closeBtn:SetFrameLevel((f:GetFrameLevel() or 1) + 20)
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    if theme and theme.ApplyCloseButtonStyle then
        theme.ApplyCloseButtonStyle(closeBtn)
    end

    -- ── Row 1: Profession Tabs & State Filters ────────────────────────────────
    ui.profRow = CreateFrame("Frame", nil, f)
    f.profRow = ui.profRow
    ui.profRow:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -38)
    ui.profRow:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -38)
    ui.profRow:SetHeight(24)
    ui.profRow:SetFrameLevel((f:GetFrameLevel() or 1) + 5)

    -- State filter buttons (all, unlearned, learned)
    local reverseStateFilters = { "learned", "unlearned", "all" }
    local lastStateBtn = nil

    for _, st in ipairs(reverseStateFilters) do
        local btn = CreateFrame("Button", nil, ui.profRow, "BackdropTemplate")
        btn:SetSize(72, 22)
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
        fs:SetText(st)
        btn.fs = fs
        if btn.SetFontString then btn:SetFontString(fs) end

        if not lastStateBtn then
            btn:SetPoint("RIGHT", ui.profRow, "RIGHT", -4, 0)
        else
            btn:SetPoint("RIGHT", lastStateBtn, "LEFT", -5, 0)
        end
        lastStateBtn = btn
        ui.stateButtons[st] = btn

        btn:SetScript("OnClick", function()
            if B.filterState == st then return end
            B.filterState = st
            B.UpdateStateButtons()
            B.RebuildFilteredList()
            B.ResetScroll()
            B.UpdateList()
        end)
    end
    B.UpdateStateButtons()

    -- ── Row 2: Completionist Progress Bar ─────────────────────────────────────
    B.CreateProgressBar(f, ui.profRow)

    -- ── Row 3: Search, Events, Zone & Source Filters ──────────────────────────
    local toolbar = CreateFrame("Frame", nil, f)
    f.toolbar = toolbar
    toolbar:SetPoint("TOPLEFT", ui.progressBar, "BOTTOMLEFT", 0, -4)
    toolbar:SetPoint("TOPRIGHT", ui.progressBar, "BOTTOMRIGHT", 0, -4)
    toolbar:SetHeight(24)
    toolbar:SetFrameLevel((f:GetFrameLevel() or 1) + 5)

    -- Search Box
    local sb = CreateFrame("EditBox", nil, toolbar, "BackdropTemplate")
    sb:SetSize(160, 22)
    sb:SetPoint("LEFT", toolbar, "LEFT", 4, 0)
    sb:SetAutoFocus(false)
    sb:SetFontObject("GameFontHighlightSmall")
    sb:SetTextInsets(6, 6, 0, 0)
    if theme and theme.ApplyInputStyle then
        theme.ApplyInputStyle(sb)
    end
    ui.searchBox = sb

    local placeholder = sb:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", sb, "LEFT", 6, 0)
    placeholder:SetText("search recipes, npcs, zones...")

    sb:SetScript("OnTextChanged", function(self)
        local txt = self:GetText():trim()
        placeholder:SetShown(txt == "")
        B.filterText = txt
        B.RebuildFilteredList()
        B.ResetScroll()
        B.UpdateList()
    end)
    sb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Events Filter Button
    local eb = CreateFrame("Button", nil, toolbar, "BackdropTemplate")
    eb:SetSize(82, 22)
    eb:SetPoint("LEFT", sb, "RIGHT", 5, 0)
    local ebfs = eb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ebfs:SetPoint("CENTER", eb, "CENTER", 0, 0)
    eb.fs = ebfs
    if eb.SetFontString then eb:SetFontString(ebfs) end

    eb:SetScript("OnClick", function()
        B.showEventRecipes = not B.showEventRecipes
        B.UpdateEventsButton()
        B.RebuildFilteredList()
        B.ResetScroll()
        B.UpdateList()
    end)

    eb:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("seasonal event recipes", 1, 0.82, 0)
            GameTooltip:AddLine("toggle display of seasonal and holiday event recipes (e.g. feast of winter veil, lunar festival).", 0.9, 0.9, 0.9, true)
            if B.showEventRecipes then
                GameTooltip:AddLine("currently showing all seasonal event recipes.", 0.6, 0.8, 1, true)
            else
                GameTooltip:AddLine("currently hiding unlearned seasonal recipes (unless their holiday is currently active).", 0.6, 0.8, 1, true)
            end
            GameTooltip:Show()
        end
    end)

    eb:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    ui.eventsButton = eb
    B.UpdateEventsButton()

    -- Zone Filter Button (current zone vs all zones)
    local zb = CreateFrame("Button", nil, toolbar, "BackdropTemplate")
    zb:SetSize(84, 22)
    zb:SetPoint("LEFT", eb, "RIGHT", 5, 0)
    local zbfs = zb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    zbfs:SetPoint("CENTER", zb, "CENTER", 0, 0)
    zb.fs = zbfs
    if zb.SetFontString then zb:SetFontString(zbfs) end

    zb:SetScript("OnClick", function()
        B.showCurrentZoneOnly = not B.showCurrentZoneOnly
        B.UpdateZoneButton()
        B.RebuildFilteredList()
        B.ResetScroll()
        B.UpdateList()
    end)

    zb:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            local zName = (GetZoneText and GetZoneText():lower()) or "current zone"
            GameTooltip:AddLine("current zone filter", 1, 0.82, 0)
            GameTooltip:AddLine("show only recipes obtainable in your current zone (" .. zName .. ").", 0.9, 0.9, 0.9, true)
            if B.showCurrentZoneOnly then
                GameTooltip:AddLine("currently filtering by current zone.", 0.6, 0.8, 1, true)
            else
                GameTooltip:AddLine("currently showing recipes across all zones.", 0.6, 0.8, 1, true)
            end
            GameTooltip:AddLine("click to toggle filter.", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end
    end)

    zb:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    ui.zoneButton = zb
    B.UpdateZoneButton()

    -- Source Filter Buttons
    local lastSrcBtn = nil
    for i = #B.SOURCE_FILTERS, 1, -1 do
        local item = B.SOURCE_FILTERS[i]
        local btn = CreateFrame("Button", nil, toolbar, "BackdropTemplate")
        btn:SetSize(item.width, 22)
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
        fs:SetText(item.label)
        btn.fs = fs
        if btn.SetFontString then btn:SetFontString(fs) end

        if not lastSrcBtn then
            btn:SetPoint("RIGHT", toolbar, "RIGHT", -4, 0)
        else
            btn:SetPoint("RIGHT", lastSrcBtn, "LEFT", -5, 0)
        end
        lastSrcBtn = btn
        ui.sourceButtons[item.key] = btn

        btn:SetScript("OnClick", function()
            local key = item.key
            if IsShiftKeyDown() then
                B.sourceFilters[key] = not B.sourceFilters[key]
            else
                local wasActive = B.sourceFilters[key]
                local activeCount = 0
                for _, it in ipairs(B.SOURCE_FILTERS) do
                    if B.sourceFilters[it.key] then
                        activeCount = activeCount + 1
                    end
                end

                if wasActive and activeCount == 1 then
                    B.sourceFilters[key] = false
                else
                    for _, it in ipairs(B.SOURCE_FILTERS) do
                        B.sourceFilters[it.key] = (it.key == key)
                    end
                end
            end

            B.UpdateSourceButtons()
            B.RebuildFilteredList()
            B.ResetScroll()
            B.UpdateList()
        end)

        btn:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine("filter: " .. item.label, 1, 0.82, 0)
                GameTooltip:AddLine("click to filter recipes by " .. item.label .. ".", 0.9, 0.9, 0.9, true)
                GameTooltip:AddLine("click again to clear filter.", 0.6, 0.8, 1, true)
                GameTooltip:AddLine("shift-click to toggle multi-selection.", 0.6, 0.8, 1, true)
                GameTooltip:Show()
            end
        end)

        btn:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
    end
    B.UpdateSourceButtons()

    -- ── Row 4: Specialization & Sub-Category Filters ─────────────────────────
    ui.specRow = CreateFrame("Frame", nil, f)
    f.specRow = ui.specRow
    ui.specRow:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -4)
    ui.specRow:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", 0, -4)
    ui.specRow:SetHeight(22)
    ui.specRow:SetFrameLevel((f:GetFrameLevel() or 1) + 5)

    ui.specLabel = ui.specRow:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    ui.specLabel:SetPoint("LEFT", ui.specRow, "LEFT", 4, 0)
    ui.specLabel:SetTextColor(0.66, 0.66, 0.66, 1)

    local catDivider = ui.specRow:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    catDivider:SetText("|cff333338|||r |cff888888cat:|r")
    ui.catDivider = catDivider

    B.UpdateSpecButtons()

    -- ── List Container & Rows ────────────────────────────────────────────────
    local lc = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.listContainer = lc
    lc:SetPoint("TOPLEFT", ui.specRow, "BOTTOMLEFT", 0, -6)
    lc:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 26)
    lc:EnableMouseWheel(true)
    lc:SetScript("OnMouseWheel", B.OnListMouseWheel)
    if theme and theme.ApplyContainerStyle then
        theme.ApplyContainerStyle(lc)
    end
    ui.listContainer = lc

    -- ── FauxScrollFrame (Blizzard Virtual Scroll Controller) ─────────────────
    local sf = CreateFrame("ScrollFrame", "SfuiRecipeBrowserScroll", lc, "FauxScrollFrameTemplate")
    sf:SetAllPoints(lc)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", B.OnListMouseWheel)
    ui.scrollFrame = sf

    local scroller = sf.ScrollBar
    if scroller then
        scroller.scrollStep = (cfg.ROW_H + cfg.ROW_PAD) * 3
        if theme and theme.ApplyScrollBarStyle then
            theme.ApplyScrollBarStyle(scroller)
        elseif common and common.style_scrollbar then
            common.style_scrollbar(scroller)
        end
        scroller:ClearAllPoints()
        scroller:SetPoint("TOPRIGHT", lc, "TOPRIGHT", -3, -4)
        scroller:SetPoint("BOTTOMRIGHT", lc, "BOTTOMRIGHT", -3, 4)
        scroller:SetWidth(6)
        scroller:SetHitRectInsets(-8, -8, 0, 0)
    end

    sf:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, cfg.ROW_H + cfg.ROW_PAD, B.UpdateList)
    end)

    -- Pre-create visible rows parented to listContainer
    for i = 1, cfg.VISIBLE_ROWS do
        ui.rows[i] = B.CreateRow(lc, i)
    end

    -- Empty State Banner
    ui.emptyStateText = lc:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    ui.emptyStateText:SetPoint("CENTER", lc, "CENTER", 0, 0)
    ui.emptyStateText:SetJustifyH("CENTER")
    ui.emptyStateText:Hide()

    -- Enable mouse wheel on entire main window
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", B.OnListMouseWheel)

    -- Bottom Status Bar
    ui.statusText = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    ui.statusText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 8)
    ui.statusText:SetText("loading catalog...")

    -- ESC dismiss
    tinsert(UISpecialFrames, "SfuiRecipeBrowserFrame")

    -- Refresh on show
    f:SetScript("OnShow", function()
        B.UpdateProfessionTabs()
        B.UpdateStateButtons()
        B.UpdateEventsButton()
        if B.UpdateZoneButton then B.UpdateZoneButton() end
        B.UpdateSourceButtons()
        if B.UpdateSpecButtons then B.UpdateSpecButtons() end
        B.RebuildFilteredList()
        B.ResetScroll()
        B.UpdateList()
    end)

    -- ── Theme registration ─────────────────────────────────────────────────────
    if theme and theme.ApplyWindowStyle then
        theme.ApplyWindowStyle(f)
    end
    if theme and theme.RegisterWindow then
        theme.RegisterWindow(f, function(frame, pal)
            if not pal and theme.GetPalette then pal = theme.GetPalette() end
            if frame.headerBar and theme.ApplyHeaderStyle then
                theme.ApplyHeaderStyle(frame.headerBar, "recipe catalog")
            end
            if frame.listContainer and theme.ApplyContainerStyle then
                theme.ApplyContainerStyle(frame.listContainer)
            end
            B.UpdateProfessionTabs()
            if sfui.recipes and sfui.recipes.SetBarTexture then
                sfui.recipes.SetBarTexture()
            end
            B.UpdateStateButtons()
            B.UpdateEventsButton()
            if B.UpdateZoneButton then B.UpdateZoneButton() end
            B.UpdateSourceButtons()
            if B.UpdateSpecButtons then B.UpdateSpecButtons() end
        end)
    end

    -- Event listener for item caching
    f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    f:SetScript("OnEvent", function(self, event)
        if event == "GET_ITEM_INFO_RECEIVED" and self:IsShown() then
            if not self.refreshPending then
                self.refreshPending = true
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.15, function()
                        self.refreshPending = false
                        if self:IsShown() then
                            B.UpdateList()
                        end
                    end)
                end
            end
        end
    end)

    ui.frame = f
    return f
end

--- Select a specific profession by name or skill ID
--- @param prof string|number
--- @return boolean success
function B:SelectProfession(prof)
    if not prof then return false end
    local target = tostring(prof):lower()
    B.playerProfessions = B.GetPlayerProfessionsList()
    for _, p in ipairs(B.playerProfessions) do
        if tostring(p.skillID) == target or p.name:lower() == target or p.name:lower():find(target, 1, true) then
            B.selectedSkillID = p.skillID
            return true
        end
    end
    for _, p in ipairs(B.ALL_PROFESSIONS or {}) do
        if tostring(p.skillID) == target or p.name:lower() == target or p.name:lower():find(target, 1, true) then
            B.selectedSkillID = p.skillID
            return true
        end
    end
    return false
end

--- Open the recipe browser window
--- @param optionalProfession string|number?
function sfui.recipes.OpenBrowser(optionalProfession)
    local f = B.CreateBrowserFrame()
    if optionalProfession then
        B:SelectProfession(optionalProfession)
    end

    B.UpdateProfessionTabs()
    if B.UpdateSpecButtons then B.UpdateSpecButtons() end
    B.RebuildFilteredList()
    B.ResetScroll()
    B.UpdateList()
    f:Show()
end

--- Open the recipe browser window pre-filtered to a specific vendor
--- @param vendorName string
function sfui.recipes.OpenBrowserForVendor(vendorName)
    local f = B.CreateBrowserFrame()
    if vendorName and vendorName ~= "" then
        B.sourceFilters.vendor = true
        B.sourceFilters.trainer = false
        B.sourceFilters.quest = false
        B.sourceFilters.drop = false
        B.sourceFilters.reputation = false
        B.sourceFilters.limited_stock = false
        B.sourceFilters.alt_unlearned = false
        B.filterText = vendorName:lower()
        if B.ui.searchBox then
            B.ui.searchBox:SetText(vendorName:lower())
        end
    end

    B.UpdateProfessionTabs()
    B.UpdateSourceButtons()
    if B.UpdateSpecButtons then B.UpdateSpecButtons() end
    B.RebuildFilteredList()
    B.ResetScroll()
    B.UpdateList()
    f:Show()
end

--- Open the recipe browser window pre-filtered to a specific recipe
--- @param spellID number
function sfui.recipes.OpenBrowserToRecipe(spellID)
    spellID = tonumber(spellID) or spellID
    if not spellID then return end

    local db = sfui.recipes_camelot and sfui.recipes_camelot.recipes
    local r = db and db[spellID]
    local f = B.CreateBrowserFrame()

    if r then
        if r.skillID then
            B.selectedSkillID = r.skillID
        elseif r.profession then
            B:SelectProfession(r.profession)
        end
        if r.name then
            B.filterText = r.name:lower()
            if B.ui.searchBox then
                B.ui.searchBox:SetText(r.name:lower())
            end
        end
    end

    B.UpdateProfessionTabs()
    B.UpdateSourceButtons()
    if B.UpdateSpecButtons then B.UpdateSpecButtons() end
    B.RebuildFilteredList()
    B.ResetScroll()
    B.UpdateList()
    f:Show()
end

--- Close the recipe browser window
function sfui.recipes.CloseBrowser()
    if B.ui.frame then
        B.ui.frame:Hide()
    end
end

--- Toggle the recipe browser window
--- @param optionalProfession string|number?
function sfui.recipes.ToggleBrowser(optionalProfession)
    if B.ui.frame and B.ui.frame:IsShown() then
        sfui.recipes.CloseBrowser()
    else
        sfui.recipes.OpenBrowser(optionalProfession)
    end
end

--- Real-time memory & diagnostics stats inspector for sfui.mem
--- @return table stats
function sfui.recipes_debug_info()
    local numRecipes = 0
    if sfui.recipes_camelot and sfui.recipes_camelot.recipes then
        for _ in pairs(sfui.recipes_camelot.recipes) do
            numRecipes = numRecipes + 1
        end
    end
    local numSources = 0
    if sfui.recipes and sfui.recipes.sources then
        for _ in pairs(sfui.recipes.sources) do
            numSources = numSources + 1
        end
    end
    local isShown = (B.ui and B.ui.frame and B.ui.frame:IsShown()) and true or false
    local shownCount = (B.filteredRecipes and #B.filteredRecipes) or 0
    local curProf = "all"
    if B.selectedSkillID and B.playerProfessions then
        for _, p in ipairs(B.playerProfessions) do
            if p.skillID == B.selectedSkillID then
                curProf = p.name or "profession"
                break
            end
        end
    end
    local pinnedCount = 0
    if sfui.recipes.GetPinnedRecipes then
        for _ in pairs(sfui.recipes.GetPinnedRecipes()) do
            pinnedCount = pinnedCount + 1
        end
    end

    return {
        isOpen       = isShown,
        totalRecipes = numRecipes,
        totalSources = numSources,
        activeFilter = curProf:lower(),
        shownCount   = shownCount,
        pinnedCount  = pinnedCount,
        mapPins      = (sfui.recipes.pins and sfui.recipes.pins.GetActiveCount and sfui.recipes.pins.GetActiveCount()) or 0,
        poolSize     = (B.ui and B.ui.rows and #B.ui.rows) or 0,
    }
end

-- ─── Blizzard TradeSkill Frame Hook ───────────────────────────────────────────
local function HookBlizzardFrames()
    local function AttachButton(parentFrame, getProfFunc)
        if not parentFrame or parentFrame._sfuiRecipeBtn then return end
        local closeBtn = parentFrame.CloseButton or _G[parentFrame:GetName() .. "CloseButton"]
        if not closeBtn then return end

        local btn = CreateFrame("Button", nil, parentFrame, "BackdropTemplate")
        parentFrame._sfuiRecipeBtn = btn
        btn:SetSize(20, 20)
        btn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
        btn:SetFrameLevel(closeBtn:GetFrameLevel() + 1)

        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0.10, 0.10, 0.12, 0.85)
        btn:SetBackdropBorderColor(0.25, 0.25, 0.30, 0.85)

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
        icon:SetSize(14, 14)
        icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        btn:SetScript("OnClick", function()
            local prof = getProfFunc and getProfFunc()
            sfui.recipes.OpenBrowser(prof)
        end)

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("recipe browser", 1, 0.82, 0)
            GameTooltip:AddLine("click to open sfui recipe and source browser.", 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    if _G.TradeSkillFrame then
        AttachButton(_G.TradeSkillFrame, _G.GetTradeSkillLine)
    end
    if _G.CraftFrame then
        AttachButton(_G.CraftFrame, _G.GetCraftSkillLine)
    end
    if _G.ProfessionsFrame then
        AttachButton(_G.ProfessionsFrame, function()
            if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
                local p = C_TradeSkillUI.GetBaseProfessionInfo()
                return p and p.professionName
            end
        end)
    end
end

if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", HookBlizzardFrames)
    sfui.events.RegisterEvent("TRADE_SKILL_SHOW", HookBlizzardFrames)
    sfui.events.RegisterEvent("CRAFT_SHOW", HookBlizzardFrames)
    sfui.events.RegisterEvent("ADDON_LOADED", function(_, loadedAddon)
        if loadedAddon == "Blizzard_TradeSkillUI" or loadedAddon == "Blizzard_CraftUI" or loadedAddon == "Blizzard_Professions" then
            HookBlizzardFrames()
        end
    end)
end

-- ─── Live Theme Synchronization ──────────────────────────────────────────────
if sfui.events and sfui.events.RegisterMessage then
    sfui.events.RegisterMessage("SFUI_THEME_CHANGED", function()
        if B.ui.frame and B.ui.frame:IsShown() then
            if sfui.theme and sfui.theme.ApplyWindowStyle then
                sfui.theme.ApplyWindowStyle(B.ui.frame)
            end
            B.UpdateProfessionTabs()
            B.UpdateStateButtons()
            B.UpdateEventsButton()
            if B.UpdateZoneButton then B.UpdateZoneButton() end
            B.UpdateSourceButtons()
            if B.UpdateSpecButtons then B.UpdateSpecButtons() end
            B.UpdateList()
        end
    end)
end
