local addonName, addon = ...
sfui = sfui or {}
sfui.options = sfui.options or {}

local c = sfui.config.options_panel
local g = sfui.config
local common = sfui.common

local wipe = _G.wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
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
        local ok, err = pcall(tabDef.build, content_panel, tab_button, frame)
        if not ok then
            print("|cffff0000[sfui options tab build error]|r", tabDef.id or "tab", err)
        end
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

    local pal = (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()) or sfui.config.appearance
    local normalCol = pal.tabNormal or c.tabs.color
    local selectedCol = pal.tabSelected or c.tabs.selected_color

    for _, tab_data in ipairs(frame.tabs) do
        tab_data.button:GetFontString():SetTextColor(normalCol[1], normalCol[2], normalCol[3])
        if tab_data.button.indicator then tab_data.button.indicator:Hide() end
        tab_data.panel:Hide()
        if tab_data.button.tabDef and tab_data.button.tabDef.onHide then
            pcall(tab_data.button.tabDef.onHide, tab_data.panel, tab_data.button, frame)
        end
    end

    selected_tab_button.panel:Show()
    selected_tab_button:GetFontString():SetTextColor(selectedCol[1], selectedCol[2], selectedCol[3])
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
    if sfui.theme and sfui.theme.ApplyWindowStyle then
        sfui.theme.ApplyWindowStyle(frame)
    else
        frame:SetBackdrop({ bgFile = g.textures.white, tile = true, tileSize = 32 })
        frame:SetBackdropColor(c.backdrop_color[1], c.backdrop_color[2], c.backdrop_color[3], c.backdrop_color[4])
    end
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

    local pal = (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()) or sfui.config.appearance
    local headerCol = pal.headerColor or g.header_color

    local headerFrame = CreateFrame("Frame", "sfui_options_header", frame)
    headerFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    headerFrame:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    headerFrame:SetHeight(40)
    headerFrame:SetFrameLevel((frame:GetFrameLevel() or 1) + 15)
    headerFrame:EnableMouse(false)
    frame.headerFrame = headerFrame

    local header_text = headerFrame:CreateFontString(nil, "OVERLAY", g.font_large)
    header_text:SetPoint("TOP", headerFrame, "TOP", 0, -10)
    header_text:SetTextColor(headerCol[1], headerCol[2], headerCol[3])
    local ver = g.version or ""
    if not ver:find("^[vV]") and ver ~= "" then
        ver = "v" .. ver
    end
    header_text:SetText(g.title .. " " .. ver:lower())
    headerFrame.text = header_text

    local addon_icon = headerFrame:CreateTexture(nil, "ARTWORK")
    addon_icon:SetSize(32, 32)
    addon_icon:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", 5, -5)
    addon_icon:SetTexture("Interface\\Icons\\Spell_shadow_deathcoil")
    headerFrame.icon = addon_icon

    local close_button = common.create_close_button(frame)
    close_button:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)

    local function refresh_frame_levels()
        local base = frame:GetFrameLevel() or 1
        if frame.sfuiThemeLayers and frame.sfuiThemeLayers.borderFrame then
            frame.sfuiThemeLayers.borderFrame:SetFrameLevel(base + 1)
        end
        if frame.tabs then
            for _, tab_data in ipairs(frame.tabs) do
                if tab_data.panel then
                    tab_data.panel:SetFrameLevel(base + 5)
                end
                if tab_data.button then
                    tab_data.button:SetFrameLevel(base + 10)
                end
            end
        end
        if headerFrame then
            headerFrame:SetFrameLevel(base + 15)
        end
        if close_button then
            close_button:SetFrameLevel(base + 20)
        end
    end

    local function on_tab_click(self)
        select_tab(self)
    end

    local function on_tab_enter(self)
        local curPal = (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()) or sfui.config.appearance
        self:GetFontString():SetTextColor(curPal.accentColor[1], curPal.accentColor[2], curPal.accentColor[3])
    end

    local function on_tab_leave(self)
        local curPal = (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()) or sfui.config.appearance
        local normalCol = curPal.tabNormal or c.tabs.color
        local selectedCol = curPal.tabSelected or c.tabs.selected_color
        if self == frame.selected_tab then
            self:GetFontString():SetTextColor(selectedCol[1], selectedCol[2], selectedCol[3])
        else
            self:GetFontString():SetTextColor(normalCol[1], normalCol[2], normalCol[3])
        end
    end

    local function create_tab(id, displayName)
        local tab_button = CreateFrame("Button", "sfui_options_tab_" .. id, frame)
        tab_button:SetSize(c.tabs.width, c.tabs.height)
        tab_button:SetText(displayName or id)
        tab_button.tabID = id
        tab_button:SetFrameLevel((frame:GetFrameLevel() or 1) + 10)

        local curPal = (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()) or sfui.config.appearance
        local accentCol = curPal.accentColor or { 0, 1, 1, 1 }
        local normalCol = curPal.tabNormal or c.tabs.color

        local indicator = tab_button:CreateTexture(nil, "OVERLAY")
        indicator:SetSize(2, c.tabs.height - 8)
        indicator:SetPoint("LEFT", tab_button, "LEFT", 0, 0)
        indicator:SetColorTexture(accentCol[1], accentCol[2], accentCol[3], 1)
        indicator:Hide()
        tab_button.indicator = indicator

        local font_string = tab_button:GetFontString()
        font_string:SetFontObject(g.font)
        font_string:SetJustifyH("LEFT")
        font_string:SetJustifyV("MIDDLE")
        font_string:SetPoint("LEFT", tab_button, "LEFT", 8, 0)
        font_string:SetTextColor(normalCol[1], normalCol[2], normalCol[3])

        local container_panel = CreateFrame("Frame", "sfui_options_container_" .. id, frame, "BackdropTemplate")
        container_panel:SetPoint("TOPLEFT", frame, "TOPLEFT", c.tabs.width + 20, -40)
        container_panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 5)
        container_panel:SetFrameLevel((frame:GetFrameLevel() or 1) + 5)
        if sfui.theme and sfui.theme.ApplyContainerStyle then
            sfui.theme.ApplyContainerStyle(container_panel)
        else
            container_panel:SetBackdrop({ bgFile = g.textures.white, tile = true, tileSize = 32 })
            container_panel:SetBackdropColor(unpack(sfui.config.appearance.backdropColor))
        end
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

    local last_tab_button = nil
    for i, tabDef in ipairs(tabs_to_show) do
        local content_panel, tab_button = create_tab(tabDef.id, tabDef.name or tabDef.id)
        tab_button.tabDef = tabDef
        tab_button.content_panel = content_panel

        if i == 1 then
            tab_button:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -40)
        elseif tabDef.id == "debug" then
            -- Distinct gap before debug at the bottom
            tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, -10)
        elseif last_tab_button and last_tab_button.tabDef and last_tab_button.tabDef.id == "main" then
            -- Distinct gap after main
            tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, -10)
        else
            -- Standard gap
            tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, 5)
        end
        last_tab_button = tab_button
    end

    refresh_frame_levels()
    frame:HookScript("OnShow", refresh_frame_levels)

    if sfui.theme and sfui.theme.RegisterWindow then
        sfui.theme.RegisterWindow(frame, function(f, curPal)
            refresh_frame_levels()
            if header_text then
                header_text:SetTextColor(curPal.headerColor[1], curPal.headerColor[2], curPal.headerColor[3])
            end
            if f.tabs then
                for _, tab_data in ipairs(f.tabs) do
                    local btn = tab_data.button
                    if btn and btn.indicator then
                        btn.indicator:SetColorTexture(curPal.accentColor[1], curPal.accentColor[2], curPal.accentColor[3], 1)
                    end
                    if tab_data.panel and sfui.theme.ApplyContainerStyle then
                        sfui.theme.ApplyContainerStyle(tab_data.panel)
                    end
                    if btn and btn:GetFontString() then
                        if btn == f.selected_tab then
                            btn:GetFontString():SetTextColor(curPal.tabSelected[1], curPal.tabSelected[2], curPal.tabSelected[3])
                        else
                            btn:GetFontString():SetTextColor(curPal.tabNormal[1], curPal.tabNormal[2], curPal.tabNormal[3])
                        end
                    end
                end
            end
        end)
    end
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

-- ─────────────────────────────────────────────────────────────────────────────
--  Blizzard Modern Settings Panel Category Registration
-- ─────────────────────────────────────────────────────────────────────────────
local function register_blizzard_settings()
    if _G.Settings and _G.Settings.RegisterCanvasLayoutCategory and _G.Settings.RegisterAddOnCategory then
        local canvas = CreateFrame("Frame", "SFUIOptionsBlizzardCanvas", UIParent)
        canvas:Hide()

        local title = canvas:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("|cff6600ffsf|rui")

        local desc = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
        desc:SetText("Modular and dynamic UI for World of Warcraft.")

        local openBtn = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
        openBtn:SetSize(180, 26)
        openBtn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -20)
        openBtn:SetText("Open SFUI Options")
        openBtn:SetScript("OnClick", function()
            if _G.SettingsPanel and _G.SettingsPanel:IsShown() then
                _G.SettingsPanel:Hide()
            end
            sfui.open_options_panel()
        end)

        local category = Settings.RegisterCanvasLayoutCategory(canvas, "SFUI")
        Settings.RegisterAddOnCategory(category)
    end
end

if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("PLAYER_LOGIN", register_blizzard_settings)
else
    register_blizzard_settings()
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
