local addonName, addon = ...
sfui = sfui or {}
sfui.options = sfui.options or {}

local c = sfui.config.options_panel
local g = sfui.config
local common = sfui.common

local wipe = _G.wipe or table.wipe
local LibStub = _G.LibStub
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local C_Timer = _G.C_Timer
local select = _G.select
local pcall = _G.pcall
local type = _G.type
local ipairs = _G.ipairs
local table_insert = table.insert
local table_sort = table.sort
local math_min = math.min
local math_max = math.max
local UISpecialFrames = _G.UISpecialFrames

local frame = nil
local registered_tabs = {}

-- ─────────────────────────────────────────────────────────────────────────────
--  Tab Registry API
-- ─────────────────────────────────────────────────────────────────────────────
function sfui.options.RegisterTab(tabDef)
    if not tabDef or not tabDef.id then return end
    for i, t in ipairs(registered_tabs) do
        if t.id == tabDef.id then
            registered_tabs[i] = tabDef
            return
        end
    end
    table_insert(registered_tabs, tabDef)
end

function sfui.options.GetRegisteredTabs()
    return registered_tabs
end

function sfui.options.GetFrame()
    return frame
end

function sfui.options.ResetTab(tabID)
    if not tabID then return false end
    for _, tabDef in ipairs(registered_tabs) do
        if tabDef.id == tabID and type(tabDef.resetDefaults) == "function" then
            pcall(tabDef.resetDefaults)
            if frame and frame.selected_tab and frame.selected_tab.tabDef and frame.selected_tab.tabDef.id == tabID then
                if tabDef.onShow and frame.selected_tab.panel then
                    pcall(tabDef.onShow, frame.selected_tab.panel, frame.selected_tab, frame)
                end
            end
            return true
        end
    end
    return false
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Shared Notification Helpers
-- ─────────────────────────────────────────────────────────────────────────────
function sfui.options.notify_setting_changed(moduleName, key, value)
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_SETTING_CHANGED", moduleName, key, value)
    else
        local mod = sfui.GetModule and sfui.GetModule(moduleName) or sfui[moduleName]
        if mod then
            if type(mod.OnSettingsChanged) == "function" then
                pcall(mod.OnSettingsChanged, mod, key, value)
            elseif type(mod.update_settings) == "function" then
                pcall(mod.update_settings)
            elseif type(mod.UpdateSettings) == "function" then
                pcall(mod.UpdateSettings)
            end
        end
    end
end

function sfui.options.notify_spec_colors_updated()
    if common and common.invalidate_spec_color_cache then common.invalidate_spec_color_cache() end
    if sfui.colors and sfui.colors.invalidate_spec_color_cache then sfui.colors.invalidate_spec_color_cache() end
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_SPEC_COLORS_UPDATED")
    elseif sfui.BroadcastSpecChanged then
        sfui.BroadcastSpecChanged()
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Lazy Tab Construction & Tab Selection
-- ─────────────────────────────────────────────────────────────────────────────
local function ensure_tab_built(tabDef, content_panel, tab_button)
    if not tabDef or tabDef._built then return end
    tabDef._built = true
    if tabDef.build and content_panel then
        pcall(tabDef.build, content_panel, tab_button, frame)
        if content_panel.update_scroll_height then
            C_Timer.After(0.01, content_panel.update_scroll_height)
        end
    end
end

local function select_tab(selected_tab_button)
    if not frame or not frame.tabs or not selected_tab_button then return end

    local tabDef = selected_tab_button.tabDef
    if tabDef and not tabDef._built then
        ensure_tab_built(tabDef, selected_tab_button.content_panel, selected_tab_button)
    end

    for _, tab_data in ipairs(frame.tabs) do
        tab_data.button:GetFontString():SetTextColor(c.tabs.color[1], c.tabs.color[2], c.tabs.color[3])
        if tab_data.button.indicator then tab_data.button.indicator:Hide() end
        tab_data.panel:Hide()
        if tab_data.button.tabDef and tab_data.button.tabDef.onHide then
            pcall(tab_data.button.tabDef.onHide, tab_data.panel, tab_data.button, frame)
        end
    end

    selected_tab_button.panel:Show()
    selected_tab_button:GetFontString():SetTextColor(c.tabs.selected_color[1], c.tabs.selected_color[2],
        c.tabs.selected_color[3])
    if selected_tab_button.indicator then selected_tab_button.indicator:Show() end
    frame.selected_tab = selected_tab_button

    if tabDef and tabDef.id and SfuiDB then
        SfuiDB.lastOptionsTab = tabDef.id
    end

    if tabDef and tabDef.onShow then
        pcall(tabDef.onShow, selected_tab_button.panel, selected_tab_button, frame)
    end

    if selected_tab_button.panel and selected_tab_button.panel.update_scroll_height then
        C_Timer.After(0.01, selected_tab_button.panel.update_scroll_height)
    end
end

function sfui.select_options_tab(tabIDOrName)
    if not frame or not frame.tabs then
        sfui.create_options_panel()
    end
    if not frame or not frame.tabs then return end

    local targetLower = tabIDOrName and tabIDOrName:lower()
    for _, tab_data in ipairs(frame.tabs) do
        local btn = tab_data.button
        local id = tab_data.id or (btn.tabDef and btn.tabDef.id)
        local name = btn:GetText()
        if (id and id:lower() == targetLower) or (name and name:lower() == targetLower) then
            select_tab(btn)
            return
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Options Frame Construction
-- ─────────────────────────────────────────────────────────────────────────────
function sfui.create_options_panel()
    if frame then return end

    local white = sfui.config.colors.white

    frame = CreateFrame("Frame", "sfui_options_frame", UIParent, "BackdropTemplate")
    frame:SetSize(c.width, c.height)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({ bgFile = g.textures.white, tile = true, tileSize = 32 })
    frame:SetBackdropColor(c.backdrop_color[1], c.backdrop_color[2], c.backdrop_color[3], c.backdrop_color[4])
    frame:SetScript("OnHide", function(self)
        if self.selected_tab and self.selected_tab.tabDef and self.selected_tab.tabDef.onHide then
            pcall(self.selected_tab.tabDef.onHide, self.selected_tab.panel, self.selected_tab, self)
        end
    end)
    frame:Hide()
    frame.tabs = {}

    if _G.UISpecialFrames then
        local found = false
        for _, name in ipairs(_G.UISpecialFrames) do
            if name == "sfui_options_frame" then
                found = true
                break
            end
        end
        if not found then
            table_insert(_G.UISpecialFrames, "sfui_options_frame")
        end
    end

    local header_text = frame:CreateFontString(nil, "OVERLAY", g.font_large)
    header_text:SetPoint("TOP", frame, "TOP", 0, -10)
    header_text:SetTextColor(g.header_color[1], g.header_color[2], g.header_color[3])
    local ver = g.version or ""
    if not ver:find("^[vV]") and ver ~= "" then
        ver = "v" .. ver
    end
    header_text:SetText(g.title .. " " .. ver:lower())

    local addon_icon = frame:CreateTexture(nil, "ARTWORK")
    addon_icon:SetSize(32, 32)
    addon_icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -5)
    addon_icon:SetTexture("Interface\\Icons\\Spell_shadow_deathcoil")

    local close_button = common.create_close_button(frame)

    local function on_tab_click(self)
        select_tab(self)
    end

    local function on_tab_enter(self)
        local accent = sfui.config.appearance.accentColor
        self:GetFontString():SetTextColor(accent[1], accent[2], accent[3])
    end

    local function on_tab_leave(self)
        if self == frame.selected_tab then
            self:GetFontString():SetTextColor(c.tabs.selected_color[1], c.tabs.selected_color[2],
                c.tabs.selected_color[3])
        else
            self:GetFontString():SetTextColor(c.tabs.color[1], c.tabs.color[2], c.tabs.color[3])
        end
    end

    -- Search / Filter Box for tabs
    local search_box = CreateFrame("EditBox", "sfui_options_search", frame, "BackdropTemplate")
    search_box:SetSize(c.tabs.width, 22)
    search_box:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -40)
    search_box:SetAutoFocus(false)
    search_box:SetFontObject(g.font)
    search_box:SetTextInsets(6, 6, 0, 0)
    search_box:SetBackdrop({
        bgFile = g.textures.white,
        edgeFile = g.textures.white,
        edgeSize = 1,
    })
    search_box:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
    search_box:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

    local placeholder = search_box:CreateFontString(nil, "OVERLAY", g.font)
    placeholder:SetPoint("LEFT", search_box, "LEFT", 6, 0)
    placeholder:SetTextColor(0.4, 0.4, 0.4, 0.8)
    placeholder:SetText("filter tabs...")

    local function layout_tabs(filterText)
        if not frame or not frame.tabs then return end
        local filter = (filterText and filterText:match("^%s*(.-)%s*$") or ""):lower()
        local prevButton = nil
        for _, tab_data in ipairs(frame.tabs) do
            local btn = tab_data.button
            local tabDef = btn.tabDef
            local tabName = (tabDef and (tabDef.name or tabDef.id) or btn:GetText() or ""):lower()
            local matches = (filter == "") or (tabName:find(filter, 1, true) ~= nil)
            if matches then
                btn:Show()
                btn:ClearAllPoints()
                if not prevButton then
                    btn:SetPoint("TOPLEFT", search_box, "BOTTOMLEFT", 0, -8)
                elseif tabDef and tabDef.id == "debug" and filter == "" then
                    btn:SetPoint("TOPLEFT", prevButton, "BOTTOMLEFT", 0, -10)
                elseif prevButton.tabDef and prevButton.tabDef.id == "main" and filter == "" then
                    btn:SetPoint("TOPLEFT", prevButton, "BOTTOMLEFT", 0, -10)
                else
                    btn:SetPoint("TOPLEFT", prevButton, "BOTTOMLEFT", 0, 4)
                end
                prevButton = btn
            else
                btn:Hide()
            end
        end
    end

    search_box:SetScript("OnTextChanged", function(self)
        local txt = self:GetText()
        if txt == "" then
            placeholder:Show()
        else
            placeholder:Hide()
        end
        layout_tabs(txt)
    end)
    search_box:SetScript("OnEscapePressed", function(self)
        if self:GetText() ~= "" then
            self:SetText("")
            self:ClearFocus()
        else
            self:ClearFocus()
            frame:Hide()
        end
    end)
    search_box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if frame.selected_tab and not frame.selected_tab:IsShown() then
            for _, tab_data in ipairs(frame.tabs) do
                if tab_data.button:IsShown() then
                    select_tab(tab_data.button)
                    break
                end
            end
        end
    end)

    local function create_tab(id, displayName)
        local tab_button = CreateFrame("Button", "sfui_options_tab_" .. id, frame)
        tab_button:SetSize(c.tabs.width, c.tabs.height)
        tab_button:SetText(displayName or id)
        tab_button.tabID = id

        local indicator = tab_button:CreateTexture(nil, "OVERLAY")
        indicator:SetSize(2, c.tabs.height - 8)
        indicator:SetPoint("LEFT", tab_button, "LEFT", 0, 0)
        local accent = (sfui.config.appearance and sfui.config.appearance.accentColor) or { 0, 1, 1, 1 }
        indicator:SetColorTexture(accent[1], accent[2], accent[3], 1)
        indicator:Hide()
        tab_button.indicator = indicator

        local font_string = tab_button:GetFontString()
        font_string:SetFontObject(g.font)
        font_string:SetJustifyH("LEFT")
        font_string:SetJustifyV("MIDDLE")
        font_string:SetPoint("LEFT", tab_button, "LEFT", 8, 0)
        font_string:SetTextColor(c.tabs.color[1], c.tabs.color[2], c.tabs.color[3])

        local container_panel = CreateFrame("Frame", "sfui_options_container_" .. id, frame, "BackdropTemplate")
        container_panel:SetPoint("TOPLEFT", frame, "TOPLEFT", c.tabs.width + 20, -40)
        container_panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 5)
        container_panel:SetBackdrop({ bgFile = g.textures.white, tile = true, tileSize = 32 })
        container_panel:SetBackdropColor(unpack(sfui.config.appearance.backdropColor))
        container_panel:Hide()

        local scroll_frame = CreateFrame("ScrollFrame", "sfui_options_scroll_" .. id, container_panel, "UIPanelScrollFrameTemplate")
        scroll_frame:SetPoint("TOPLEFT", container_panel, "TOPLEFT", 4, -4)
        scroll_frame:SetPoint("BOTTOMRIGHT", container_panel, "BOTTOMRIGHT", -4, 4)
        scroll_frame:EnableMouseWheel(true)
        common.style_scrollbar(scroll_frame.ScrollBar)

        local content_panel = CreateFrame("Frame", "sfui_options_panel_" .. id, scroll_frame)
        content_panel:SetSize(c.width - c.tabs.width - 35, c.height - 50)
        scroll_frame:SetScrollChild(content_panel)
        content_panel:EnableMouseWheel(true)

        local function on_mouse_wheel(self, delta)
            local scrollBar = scroll_frame.ScrollBar
            if scrollBar then
                local minVal, maxVal = scrollBar:GetMinMaxValues()
                if maxVal and maxVal > (minVal or 0) then
                    local cur = scrollBar:GetValue()
                    scrollBar:SetValue(math_max(minVal, math_min(maxVal, cur - delta * 30)))
                    return
                end
            end
            local cur = scroll_frame:GetVerticalScroll()
            local maxScroll = scroll_frame:GetVerticalScrollRange()
            if maxScroll > 0 then
                scroll_frame:SetVerticalScroll(math_max(0, math_min(maxScroll, cur - delta * 30)))
            end
        end

        scroll_frame:SetScript("OnMouseWheel", on_mouse_wheel)
        content_panel:SetScript("OnMouseWheel", on_mouse_wheel)

        local function update_scroll_height()
            local top = content_panel:GetTop()
            if not top then return end
            if content_panel.customContentHeight then
                local minH = container_panel:GetHeight() - 8
                local h = math_max(minH, content_panel.customContentHeight)
                content_panel:SetHeight(h)
                scroll_frame:UpdateScrollChildRect()
                return
            end

            local maxBottomOffset = container_panel:GetHeight() - 8
            local function checkEl(el)
                if el and el.GetBottom then
                    local b = el:GetBottom()
                    if b then
                        local offset = top - b + 25
                        if offset > maxBottomOffset then
                            maxBottomOffset = offset
                        end
                    end
                end
            end
            local function scan(f, depth)
                if depth > 3 then return end
                local numChildren = select("#", f:GetChildren())
                for i = 1, numChildren do
                    local child = select(i, f:GetChildren())
                    if child then
                        checkEl(child)
                        scan(child, depth + 1)
                    end
                end
                local numRegions = select("#", f:GetRegions())
                for i = 1, numRegions do
                    local reg = select(i, f:GetRegions())
                    if reg then
                        checkEl(reg)
                    end
                end
            end
            scan(content_panel, 1)

            local minH = container_panel:GetHeight() - 8
            if maxBottomOffset < minH then maxBottomOffset = minH end
            content_panel:SetHeight(maxBottomOffset)
            scroll_frame:UpdateScrollChildRect()

            if scroll_frame.ScrollBar then
                local minVal, maxVal = scroll_frame.ScrollBar:GetMinMaxValues()
                if not maxVal or maxVal <= (minVal or 0) or scroll_frame:GetVerticalScrollRange() <= 0 then
                    scroll_frame.ScrollBar:Hide()
                else
                    scroll_frame.ScrollBar:Show()
                end
            end
        end

        function content_panel:SetContentHeight(height)
            content_panel.customContentHeight = height
            update_scroll_height()
        end

        container_panel.update_scroll_height = update_scroll_height
        content_panel.update_scroll_height = update_scroll_height

        container_panel:HookScript("OnShow", function()
            C_Timer.After(0.01, update_scroll_height)
        end)

        tab_button.panel = container_panel
        tab_button.content_panel = content_panel
        tab_button:SetScript("OnClick", on_tab_click)
        tab_button:SetScript("OnEnter", on_tab_enter)
        tab_button:SetScript("OnLeave", on_tab_leave)

        table_insert(frame.tabs, { id = id, button = tab_button, panel = container_panel })
        return content_panel, tab_button
    end

    -- ─────────────────────────────────────────────────────────────────────────
    --  Filter & Sort Tabs:
    --  1. "main" is always at the top.
    --  2. "debug" is always at the bottom.
    --  3. All tabs in between are strictly sorted alphabetically by display name.
    -- ─────────────────────────────────────────────────────────────────────────
    local tabs_to_show = {}
    for _, t in ipairs(registered_tabs) do
        local canShow = true
        if t.condition then
            if type(t.condition) == "function" then
                canShow = t.condition()
            else
                canShow = not not t.condition
            end
        end
        if canShow then
            table_insert(tabs_to_show, t)
        end
    end

    table_sort(tabs_to_show, function(a, b)
        if a.id == "main" then return true end
        if b.id == "main" then return false end
        if a.id == "debug" then return false end
        if b.id == "debug" then return true end
        local nameA = (a.name or a.id):lower()
        local nameB = (b.name or b.id):lower()
        return nameA < nameB
    end)

    for _, tabDef in ipairs(tabs_to_show) do
        local content_panel, tab_button = create_tab(tabDef.id, tabDef.name or tabDef.id)
        tab_button.tabDef = tabDef
        tab_button.content_panel = content_panel
    end

    layout_tabs("")
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Toggle & Open API
-- ─────────────────────────────────────────────────────────────────────────────
function sfui.open_options_panel(tabName)
    if not frame then sfui.create_options_panel() end
    frame:Show()
    if tabName then
        sfui.select_options_tab(tabName)
    elseif not frame.selected_tab then
        local savedTab = SfuiDB and SfuiDB.lastOptionsTab
        if savedTab then
            sfui.select_options_tab(savedTab)
        end
        if not frame.selected_tab and frame.tabs and frame.tabs[1] then
            select_tab(frame.tabs[1].button)
        end
    end
end

function sfui.toggle_options_panel(tabName)
    if not frame then sfui.create_options_panel() end

    local currentTabID = frame.selected_tab and (frame.selected_tab.tabID or (frame.selected_tab.tabDef and frame.selected_tab.tabDef.id) or frame.selected_tab:GetText():lower())
    local targetLower = tabName and tabName:lower()

    if frame:IsShown() then
        if not targetLower or currentTabID == targetLower then
            frame:Hide()
        else
            sfui.select_options_tab(targetLower)
        end
    else
        frame:Show()
        if targetLower then
            sfui.select_options_tab(targetLower)
        elseif not frame.selected_tab then
            local savedTab = SfuiDB and SfuiDB.lastOptionsTab
            if savedTab then
                sfui.select_options_tab(savedTab)
            end
            if not frame.selected_tab and frame.tabs and frame.tabs[1] then
                select_tab(frame.tabs[1].button)
            end
        end
    end
end
