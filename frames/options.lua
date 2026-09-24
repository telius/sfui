local addonName, addon = ...
local c = sfui.config.options_panel
local g = sfui.config
local common = sfui.common

local wipe = wipe
local LibStub = LibStub
local CreateFrame = CreateFrame
local UIParent = UIParent
local C_Timer = C_Timer
local GameTooltip = sfui.tooltip or _G.GameTooltip
local select = select

local frame
local function select_tab(selected_tab_button)
    if not frame or not frame.tabs then return end

    for _, tab_data in ipairs(frame.tabs) do
        tab_data.button:GetFontString():SetTextColor(c.tabs.color[1], c.tabs.color[2], c.tabs.color[3])
        tab_data.panel:Hide()
    end
    selected_tab_button.panel:Show()
    selected_tab_button:GetFontString():SetTextColor(c.tabs.selected_color[1], c.tabs.selected_color[2],
        c.tabs.selected_color[3])
    frame.selected_tab = selected_tab_button
    if selected_tab_button.panel and selected_tab_button.panel.update_scroll_height then
        C_Timer.After(0.01, selected_tab_button.panel.update_scroll_height)
    end
end

local function notify_setting_changed(moduleName, key, value)
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_SETTING_CHANGED", moduleName, key, value)
    end
    local mod = sfui[moduleName]
    if mod and type(mod.update_settings) == "function" then
        pcall(mod.update_settings)
    end
end

local function notify_spec_colors_updated()
    if common and common.invalidate_spec_color_cache then common.invalidate_spec_color_cache() end
    if sfui.colors and sfui.colors.invalidate_spec_color_cache then sfui.colors.invalidate_spec_color_cache() end
    notify_setting_changed("bars")
    notify_setting_changed("castbar")
    notify_setting_changed("trackedbars")
    if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
    if sfui.gear and sfui.gear.Update then sfui.gear.Update() end
    if sfui.lootviewer and sfui.lootviewer.Rebuild then sfui.lootviewer.Rebuild() end
end

function sfui.create_options_panel()
    if frame then return end

    local CreateFlatButton = common.create_flat_button
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
    frame:Hide(); frame.tabs = {}

    local header_text = frame:CreateFontString(nil, "OVERLAY", g.font_large)
    header_text:SetPoint("TOP", frame, "TOP", 0, -10)
    header_text:SetTextColor(g.header_color[1], g.header_color[2], g.header_color[3])
    local ver = g.version or ""
    if not ver:find("^[vV]") and ver ~= "" then
        ver = "v" .. ver
    end
    header_text:SetText(g.title .. " " .. ver:lower())

    local addon_icon = frame:CreateTexture(nil, "ARTWORK")
    addon_icon:SetSize(32, 32); addon_icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -5)
    addon_icon:SetTexture("Interface\\Icons\\Spell_shadow_deathcoil")

    local close_button = common.create_close_button(frame)

    local create_checkbox = common.create_checkbox


    local create_cvar_checkbox = common.create_cvar_checkbox


    local create_slider_input = common.create_slider_input


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

    local function create_tab(name)
        local tab_button = CreateFrame("Button", "sfui_options_tab_" .. name, frame)
        tab_button:SetSize(c.tabs.width, c.tabs.height)
        tab_button:SetText(name)

        local font_string = tab_button:GetFontString()
        font_string:SetFontObject(g.font)
        font_string:SetJustifyH("LEFT")
        font_string:SetJustifyV("MIDDLE")
        font_string:SetPoint("LEFT", tab_button, "LEFT", 5, 0)
        font_string:SetTextColor(c.tabs.color[1], c.tabs.color[2], c.tabs.color[3])

        local container_panel = CreateFrame("Frame", "sfui_options_container_" .. name, frame, "BackdropTemplate")
        container_panel:SetPoint("TOPLEFT", frame, "TOPLEFT", c.tabs.width + 20, -40)
        container_panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 5)
        container_panel:SetBackdrop({ bgFile = g.textures.white, tile = true, tileSize = 32 })
        container_panel:SetBackdropColor(unpack(sfui.config.appearance.backdropColor))
        container_panel:Hide()

        local scroll_frame = CreateFrame("ScrollFrame", "sfui_options_scroll_" .. name, container_panel, "UIPanelScrollFrameTemplate")
        scroll_frame:SetPoint("TOPLEFT", container_panel, "TOPLEFT", 4, -4)
        scroll_frame:SetPoint("BOTTOMRIGHT", container_panel, "BOTTOMRIGHT", -4, 4)
        scroll_frame:EnableMouseWheel(true)
        common.style_scrollbar(scroll_frame.ScrollBar)

        local content_panel = CreateFrame("Frame", "sfui_options_panel_" .. name, scroll_frame)
        content_panel:SetSize(c.width - c.tabs.width - 35, c.height - 50)
        scroll_frame:SetScrollChild(content_panel)
        content_panel:EnableMouseWheel(true)

        local function on_mouse_wheel(self, delta)
            local scrollBar = scroll_frame.ScrollBar
            if scrollBar then
                local minVal, maxVal = scrollBar:GetMinMaxValues()
                if maxVal and maxVal > (minVal or 0) then
                    local cur = scrollBar:GetValue()
                    scrollBar:SetValue(math.max(minVal, math.min(maxVal, cur - delta * 30)))
                    return
                end
            end
            local cur = scroll_frame:GetVerticalScroll()
            local maxScroll = scroll_frame:GetVerticalScrollRange()
            if maxScroll > 0 then
                scroll_frame:SetVerticalScroll(math.max(0, math.min(maxScroll, cur - delta * 30)))
            end
        end

        scroll_frame:SetScript("OnMouseWheel", on_mouse_wheel)
        content_panel:SetScript("OnMouseWheel", on_mouse_wheel)

        local function update_scroll_height()
            local top = content_panel:GetTop()
            if not top then return end
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
                for _, child in ipairs({ f:GetChildren() }) do
                    checkEl(child)
                    scan(child, depth + 1)
                end
                for _, reg in ipairs({ f:GetRegions() }) do
                    checkEl(reg)
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

        container_panel.update_scroll_height = update_scroll_height
        content_panel.update_scroll_height = update_scroll_height

        container_panel:HookScript("OnShow", function()
            C_Timer.After(0.01, update_scroll_height)
        end)

        tab_button.panel = container_panel

        tab_button:SetScript("OnClick", on_tab_click)
        tab_button:SetScript("OnEnter", on_tab_enter)
        tab_button:SetScript("OnLeave", on_tab_leave)

        table.insert(frame.tabs, { button = tab_button, panel = container_panel })
        return content_panel, tab_button
    end

    local last_tab_button
    local main_panel, main_tab_button = create_tab("main")
    main_tab_button:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -40)
    last_tab_button = main_tab_button

    local automation_panel, automation_tab_button = create_tab("automation")
    automation_tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, -10) -- distinct gap from main
    last_tab_button = automation_tab_button

    local fishing_panel, fishing_tab_button = create_tab("fishing")
    fishing_tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, 5)
    last_tab_button = fishing_tab_button

    local bars_panel, bars_tab_button = create_tab("bars")
    bars_tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, 5)
    last_tab_button = bars_tab_button

    local castbar_panel, castbar_tab_button = create_tab("castbars")
    castbar_tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, 5)
    last_tab_button = castbar_tab_button

    local castbar_header = castbar_panel:CreateFontString(nil, "OVERLAY", g.font)
    castbar_header:SetPoint("TOPLEFT", 15, -15)
    castbar_header:SetTextColor(white[1], white[2], white[3])
    castbar_header:SetText("castbar settings")

    -- Player Castbar --
    local player_header = castbar_panel:CreateFontString(nil, "OVERLAY", g.font)
    player_header:SetPoint("TOPLEFT", castbar_header, "BOTTOMLEFT", 0, -20)
    player_header:SetText("player castbar")

    local enable_player_cb = create_checkbox(castbar_panel, "enable", "castBarEnabled", function(checked)
        notify_setting_changed("castbar", "castBarEnabled", checked)
    end, "toggles the player castbar.")
    enable_player_cb:SetPoint("TOPLEFT", player_header, "BOTTOMLEFT", 0, -10)

    local player_x_slider = create_slider_input(castbar_panel, "x:", "castBarX", -1000, 1000, 1, function(val)
        notify_setting_changed("castbar", "castBarX", val)
    end)
    player_x_slider:SetPoint("TOPLEFT", enable_player_cb, "BOTTOMLEFT", 0, -10)

    local player_y_slider = create_slider_input(castbar_panel, "y:", "castBarY", -1000, 1000, 1, function(val)
        notify_setting_changed("castbar", "castBarY", val)
    end)
    player_y_slider:SetPoint("LEFT", player_x_slider, "RIGHT", 10, 0)

    local reset_player_cast_btn = CreateFlatButton(castbar_panel, "reset position", 120, 20)
    reset_player_cast_btn:SetPoint("TOPLEFT", player_x_slider, "BOTTOMLEFT", 0, -10)
    reset_player_cast_btn:SetScript("OnClick", function()
        local def = sfui.config.castBar.pos
        SfuiDB.castBarX = def.x
        SfuiDB.castBarY = def.y
        player_x_slider:SetSliderValue(def.x)
        player_y_slider:SetSliderValue(def.y)
        notify_setting_changed("castbar", "castBarX", def.x)
        notify_setting_changed("castbar", "castBarY", def.y)
    end)

    -- Target Castbar --
    local target_header = castbar_panel:CreateFontString(nil, "OVERLAY", g.font)
    target_header:SetPoint("TOPLEFT", reset_player_cast_btn, "BOTTOMLEFT", 0, -20)
    target_header:SetText("target castbar")

    local enable_target_cb = create_checkbox(castbar_panel, "enable", "targetCastBarEnabled", function(checked)
        notify_setting_changed("castbar", "targetCastBarEnabled", checked)
    end, "toggles the target castbar.")
    enable_target_cb:SetPoint("TOPLEFT", target_header, "BOTTOMLEFT", 0, -10)

    local target_x_slider = create_slider_input(castbar_panel, "x:", "targetCastBarX", -1000, 1000, 1, function(val)
        notify_setting_changed("castbar", "targetCastBarX", val)
    end)
    target_x_slider:SetPoint("TOPLEFT", enable_target_cb, "BOTTOMLEFT", 0, -10)

    local target_y_slider = create_slider_input(castbar_panel, "y:", "targetCastBarY", -1000, 1000, 1, function(val)
        notify_setting_changed("castbar", "targetCastBarY", val)
    end)
    target_y_slider:SetPoint("LEFT", target_x_slider, "RIGHT", 10, 0)

    local reset_target_cast_btn = CreateFlatButton(castbar_panel, "reset position", 120, 20)
    reset_target_cast_btn:SetPoint("TOPLEFT", target_x_slider, "BOTTOMLEFT", 0, -10)
    reset_target_cast_btn:SetScript("OnClick", function()
        local def = sfui.config.targetCastBar.pos
        SfuiDB.targetCastBarX = def.x
        SfuiDB.targetCastBarY = def.y
        target_x_slider:SetSliderValue(def.x)
        target_y_slider:SetSliderValue(def.y)
        notify_setting_changed("castbar", "targetCastBarX", def.x)
        notify_setting_changed("castbar", "targetCastBarY", def.y)
    end)

    -- Extra Power Bars Settings
    local sct_panel, sct_tab_button = create_tab("combat text")
    sct_tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, 5)
    last_tab_button = sct_tab_button

    local currency_items_panel, currency_tab_button = create_tab("currency/items")
    currency_tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, 5)
    last_tab_button = currency_tab_button

    local merchant_panel, merchant_tab_button = create_tab("merchant")
    merchant_tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, 5)
    last_tab_button = merchant_tab_button

    local minimap_panel, minimap_tab_button = create_tab("minimap")
    minimap_tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, 5)
    last_tab_button = minimap_tab_button

    local gear_panel, gear_tab_button = create_tab("gear swapper")
    gear_tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, 5)
    last_tab_button = gear_tab_button

    local research_panel, research_tab_button
    local isClassic = (sfui.compat and sfui.compat.is_classic)
    if not isClassic then
        research_panel, research_tab_button = create_tab("research")
        research_tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, 5)
        last_tab_button = research_tab_button
    end

    local objectives_panel, objectives_tab_button = create_tab("objectives")
    objectives_tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, 5)
    last_tab_button = objectives_tab_button

    local debug_panel, debug_tab_button = create_tab("debug")
    debug_tab_button:SetPoint("TOPLEFT", last_tab_button, "BOTTOMLEFT", 0, -10) -- distinct gap before debug
    last_tab_button = debug_tab_button

    local main_text = main_panel:CreateFontString(nil, "OVERLAY", g.font)
    main_text:SetPoint("TOPLEFT", 15, -15)
    main_text:SetTextColor(white[1], white[2], white[3])
    main_text:SetText("welcome to sfui. please select a category on the left.")



    local reload_button = CreateFlatButton(main_panel, "reload ui", 100, 22)
    reload_button:SetPoint("TOPLEFT", main_text, "BOTTOMLEFT", 0, -20)
    reload_button:SetScript("OnClick", function()
        if C_UI and C_UI.Reload then
            C_UI.Reload()
        elseif _G.ReloadUI then
            _G.ReloadUI()
        end
    end)

    local open_cv_main = CreateFlatButton(main_panel, "tracking manager", 140, 22)
    open_cv_main:SetPoint("LEFT", reload_button, "RIGHT", 10, 0)
    open_cv_main:SetScript("OnClick", function()
        if sfui.trackedoptions and sfui.trackedoptions.toggle_viewer then
            sfui.trackedoptions.toggle_viewer()

            if SfuiCooldownsViewer and SfuiCooldownsViewer:IsShown() and frame then
                local _, rel = frame:GetPoint()
                if rel == SfuiCooldownsViewer then
                    local left = frame:GetLeft()
                    local top = frame:GetTop()
                    frame:ClearAllPoints()
                    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
                end

                SfuiCooldownsViewer:ClearAllPoints()
                SfuiCooldownsViewer:SetPoint("TOPLEFT", frame, "TOPRIGHT", 5, 0)
            end
        end
    end)

    local enable_tracking_manager_cb = create_checkbox(main_panel, "enable tracking manager", function()
        if SfuiDB.enableTrackingManager ~= nil then return SfuiDB.enableTrackingManager end
        return true
    end, function(checked)
        SfuiDB.enableTrackingManager = checked
        if open_cv_main then
            if checked then open_cv_main:Enable() else open_cv_main:Disable() end
        end
        if not checked and SfuiCooldownsViewer and SfuiCooldownsViewer:IsShown() then
            SfuiCooldownsViewer:Hide()
        end
    end, "Enables or disables the tracking manager module.")
    enable_tracking_manager_cb:SetPoint("LEFT", open_cv_main, "RIGHT", 15, 0)

    if SfuiDB.enableTrackingManager == false then
        open_cv_main:Disable()
    end

    local open_gear_main = CreateFlatButton(main_panel, "gear manager", 110, 22)
    open_gear_main:SetPoint("TOPLEFT", reload_button, "BOTTOMLEFT", 0, -10)
    open_gear_main:SetScript("OnClick", function()
        if sfui.gear and sfui.gear.toggle then
            sfui.gear.toggle()
        end
    end)

    local open_alts_main = CreateFlatButton(main_panel, "alts viewer", 100, 22)
    open_alts_main:SetPoint("LEFT", open_gear_main, "RIGHT", 10, 0)
    open_alts_main:SetScript("OnClick", function()
        if sfui.alts and sfui.alts.Toggle then
            sfui.alts.Toggle()
        end
    end)

    local open_loot_main = CreateFlatButton(main_panel, "loot viewer", 100, 22)
    open_loot_main:SetPoint("LEFT", open_alts_main, "RIGHT", 10, 0)
    open_loot_main:SetScript("OnClick", function()
        if sfui.lootviewer and sfui.lootviewer.Toggle then
            sfui.lootviewer.Toggle()
        end
    end)

    local open_pets_main = CreateFlatButton(main_panel, "pet manager", 100, 22)
    open_pets_main:SetPoint("LEFT", open_loot_main, "RIGHT", 10, 0)
    open_pets_main:SetScript("OnClick", function()
        if sfui.pets and sfui.pets.Toggle then
            sfui.pets.Toggle()
        end
    end)

    local hide_minimap_icon_cb = create_checkbox(main_panel, "hide minimap icon", function()
        return (SfuiDB.minimap_icon and SfuiDB.minimap_icon.hide) or false
    end, function(checked)
        SfuiDB.minimap_icon = SfuiDB.minimap_icon or {}
        SfuiDB.minimap_icon.hide = checked
        local icon = LibStub and LibStub:GetLibrary("LibDBIcon-1.0", true)
        if icon then
            if checked then
                icon:Hide("sfui")
            else
                icon:Show("sfui")
            end
        end
    end, "hides the sfui minimap icon.")
    hide_minimap_icon_cb:SetPoint("TOPLEFT", open_gear_main, "BOTTOMLEFT", 0, -15)

    local enable_questlog_cb = create_checkbox(main_panel, "enable quest log", function()
        if sfui.questlog and sfui.questlog.is_enabled then
            return sfui.questlog.is_enabled()
        end
        if SfuiDB.enableQuestLog ~= nil then return SfuiDB.enableQuestLog end
        return true
    end, function(checked)
        if sfui.questlog and sfui.questlog.set_enabled then
            sfui.questlog.set_enabled(checked)
        else
            SfuiDB.enableQuestLog = checked
        end
    end, "toggles the sfui custom quest log and objectives tracker (enabled by default).")
    enable_questlog_cb:SetPoint("LEFT", hide_minimap_icon_cb, "RIGHT", 150, 0)

    local enable_ring_cursor_cb = create_checkbox(main_panel, "enable ring cursor", "enableCursorRing", function(checked)
        if sfui.cursor and sfui.cursor.toggle then
            sfui.cursor.toggle(checked)
        end
    end, "toggles the ring cursor around the mouse.")
    enable_ring_cursor_cb:SetPoint("TOPLEFT", hide_minimap_icon_cb, "BOTTOMLEFT", 0, -10)

    local cursor_scale_slider = create_slider_input(main_panel, "cursor ring scale:", "cursorRingScale", 0.5, 2.0, 0.05,
        function(val)
            if sfui.cursor and sfui.cursor.update_scale then
                sfui.cursor.update_scale()
            end
        end)
    cursor_scale_slider:SetPoint("LEFT", enable_ring_cursor_cb, "RIGHT", 150, 0)

    local enable_auto_compare_cb = create_checkbox(main_panel, "enable auto compare", "enableAutoCompare",
        function(checked)
            if sfui.compare and sfui.compare.init then
                sfui.compare.init()
            end
        end, "automatically sets 'alwaysCompareItems' cvar.")
    enable_auto_compare_cb:SetPoint("TOPLEFT", enable_ring_cursor_cb, "BOTTOMLEFT", 0, -10)

    local use_spec_color_cb = create_checkbox(main_panel, "use spec color", "useSpecColor", function(checked)
        notify_spec_colors_updated()
    end, "toggles whether the UI uses specialization/class based colors globally.")
    use_spec_color_cb:SetPoint("TOPLEFT", enable_auto_compare_cb, "BOTTOMLEFT", 0, -20)

    local fallback_label = main_panel:CreateFontString(nil, "OVERLAY", g.font)
    fallback_label:SetPoint("LEFT", use_spec_color_cb, "RIGHT", 150, 0)
    fallback_label:SetText("fallback:")

    local fallback_swatch = common.create_color_swatch(main_panel, SfuiDB.specColorFallback or { 1, 1, 1, 1 },
        function(r, green, b)
            SfuiDB.specColorFallback = { r, green, b, 1 }
            notify_spec_colors_updated()
        end)
    fallback_swatch:SetPoint("LEFT", fallback_label, "RIGHT", 5, 0)

    local texture_label = main_panel:CreateFontString(nil, "OVERLAY", g.font)
    texture_label:SetPoint("TOPLEFT", use_spec_color_cb, "BOTTOMLEFT", 0, -30)
    texture_label:SetText("bar texture:")

    local function GetTextureOptions()
        local LSM = LibStub("LibSharedMedia-3.0", true)
        local sortedTextures = {}
        local seen = { ["Flat"] = true }
        table.insert(sortedTextures, { text = "Flat", value = "Flat" })

        if LSM then
            local textures = LSM:HashTable("statusbar")
            if textures then
                local rawNames = {}
                for name, _ in pairs(textures) do
                    if not seen[name] then
                        table.insert(rawNames, name)
                        seen[name] = true
                    end
                end
                table.sort(rawNames)
                for _, name in ipairs(rawNames) do
                    table.insert(sortedTextures, { text = name, value = name })
                end
            end
        end
        return sortedTextures
    end

    local texture_dropdown = common.create_dropdown(main_panel, 140, GetTextureOptions, function(val)
        SfuiDB.barTexture = val
        local LSM = LibStub("LibSharedMedia-3.0", true)
        local texturePath = LSM and LSM:Fetch("statusbar", val) or "Interface/Buttons/WHITE8X8"

        if sfui.bars and sfui.bars.set_bar_texture then
            sfui.bars.set_bar_texture(texturePath)
        end
        if sfui.castbar and sfui.castbar.set_bar_texture then
            sfui.castbar.set_bar_texture(texturePath)
        end
        if sfui.vehicle and sfui.vehicle.set_bar_texture then
            sfui.vehicle.set_bar_texture(texturePath)
        end
        if sfui.tracker and sfui.tracker.blocks and sfui.tracker.blocks.SetBarTexture then
            sfui.tracker.blocks.SetBarTexture(texturePath)
        end
        if sfui.tracker and sfui.tracker.RequestRefresh then
            sfui.tracker.RequestRefresh()
        end
    end, SfuiDB.barTexture or "Flat")
    texture_dropdown:SetPoint("LEFT", texture_label, "RIGHT", 10, 0)

    -- Spec Colors Customization
    local spec_header = main_panel:CreateFontString(nil, "OVERLAY", g.font)
    spec_header:SetPoint("TOPLEFT", texture_label, "BOTTOMLEFT", 0, -25)
    spec_header:SetTextColor(white[1], white[2], white[3])
    spec_header:SetText("specialization colors:")

    local spec_swatches = {}
    local specs, specIDs
    if common.get_spec_color_options then
        specs, specIDs = common.get_spec_color_options()
    elseif common.get_player_specs then
        specs, specIDs = common.get_player_specs()
    end
    local prevAnchor = spec_header

    for i, specID in ipairs(specIDs or {}) do
        local spec = specs and specs[specID]
        local specName = spec and spec.name or ("spec " .. i)
        local icon = spec and spec.icon
        if specID then
            local iconTex = main_panel:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(16, 16)
            if i == 1 then
                iconTex:SetPoint("TOPLEFT", spec_header, "BOTTOMLEFT", 0, -10)
            else
                iconTex:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 0, -8)
            end
            iconTex:SetTexture(icon)
            iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            local specText = main_panel:CreateFontString(nil, "OVERLAY", g.font)
            specText:SetPoint("LEFT", iconTex, "RIGHT", 6, 0)
            specText:SetTextColor(1, 1, 1, 1)
            specText:SetText(specName and string.lower(specName) or "")

            local curCol = (SfuiDB and SfuiDB.spec_colors and SfuiDB.spec_colors[specID])
                or (sfui.config and sfui.config.spec_colors and sfui.config.spec_colors[specID])
                or { 1, 1, 1, 1 }
            local swatch = common.create_color_swatch(main_panel, curCol, function(r, green, b)
                SfuiDB.spec_colors = SfuiDB.spec_colors or {}
                SfuiDB.spec_colors[specID] = { r, green, b, 1 }
                -- Also sync base Classic spec ID if this is tree 1 (e.g. untalented at level < 10)
                if sfui.isClassic and i == 1 then
                    local pClass = common.get_player_class and common.get_player_class()
                    local baseID = pClass and common.CLASS_VANILLA_SPEC_MAP and common.CLASS_VANILLA_SPEC_MAP[pClass]
                    if baseID then
                        SfuiDB.spec_colors[baseID] = { r, green, b, 1 }
                    end
                end
                notify_spec_colors_updated()
            end)
            swatch:SetPoint("LEFT", iconTex, "LEFT", 150, 0)
            spec_swatches[specID] = swatch

            prevAnchor = iconTex
        end
    end

    local reset_spec_btn = CreateFlatButton(main_panel, "reset spec colors", 130, 20)
    if prevAnchor ~= spec_header then
        reset_spec_btn:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 0, -12)
    else
        reset_spec_btn:SetPoint("TOPLEFT", spec_header, "BOTTOMLEFT", 0, -12)
    end
    reset_spec_btn:SetScript("OnClick", function()
        for _, specID in ipairs(specIDs or {}) do
            if specID then
                if SfuiDB.spec_colors then
                    SfuiDB.spec_colors[specID] = nil
                end
                local baseColor = sfui.config and sfui.config.spec_colors and sfui.config.spec_colors[specID]
                local r, green, b = 1, 1, 1
                if baseColor then
                    r, green, b = baseColor[1], baseColor[2], baseColor[3]
                end
                if spec_swatches[specID] then
                    spec_swatches[specID]:SetBackdropColor(r, green, b, 1)
                end
            end
        end
        if sfui.isClassic and SfuiDB.spec_colors then
            local pClass = common.get_player_class and common.get_player_class()
            local baseID = pClass and common.CLASS_VANILLA_SPEC_MAP and common.CLASS_VANILLA_SPEC_MAP[pClass]
            if baseID then
                SfuiDB.spec_colors[baseID] = nil
            end
        end
        notify_spec_colors_updated()
    end)


    -- 2. Bars Panel
    local bars_header = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
    bars_header:SetPoint("TOPLEFT", 15, -15)
    bars_header:SetTextColor(white[1], white[2], white[3])
    bars_header:SetText("bar settings")

    -- Bar Toggles
    local toggles_header = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
    toggles_header:SetPoint("TOPLEFT", bars_header, "BOTTOMLEFT", 0, -20)
    toggles_header:SetTextColor(white[1], white[2], white[3])
    toggles_header:SetText("bar visibility")

    local health_bar_cb = create_checkbox(bars_panel, "enable health bar", "enableHealthBar", function(checked)
        if sfui.bars and sfui.bars.on_state_changed then sfui.bars:on_state_changed() end
    end, "toggles the health bar.")
    health_bar_cb:SetPoint("TOPLEFT", toggles_header, "BOTTOMLEFT", 0, -10)

    local power_bar_cb = create_checkbox(bars_panel, "enable power bar", "enablePowerBar", function(checked)
        if sfui.bars and sfui.bars.on_state_changed then sfui.bars:on_state_changed() end
    end, "toggles the primary power bar.")
    power_bar_cb:SetPoint("TOPLEFT", health_bar_cb, "BOTTOMLEFT", 0, -10)

    local secondary_power_cb = create_checkbox(bars_panel, "enable secondary power bar", "enableSecondaryPowerBar",
        function(checked)
            if sfui.bars and sfui.bars.on_state_changed then sfui.bars:on_state_changed() end
        end, "toggles the secondary power bar (e.g., chi, holy power).")
    secondary_power_cb:SetPoint("TOPLEFT", power_bar_cb, "BOTTOMLEFT", 0, -10)

    local vigor_bar_cb = create_checkbox(bars_panel, "enable vigor bar", "enableVigorBar", function(checked)
        if sfui.bars and sfui.bars.on_state_changed then sfui.bars:on_state_changed() end
    end, "toggles the vigor bar (skyriding).")
    vigor_bar_cb:SetPoint("TOPLEFT", secondary_power_cb, "BOTTOMLEFT", 0, -10)

    local mount_speed_cb = create_checkbox(bars_panel, "enable mount speed bar", "enableMountSpeedBar", function(checked)
        if sfui.bars and sfui.bars.on_state_changed then sfui.bars:on_state_changed() end
    end, "toggles the mount speed bar (skyriding).")
    mount_speed_cb:SetPoint("TOPLEFT", vigor_bar_cb, "BOTTOMLEFT", 0, -10)

    local last_toggle_cb = mount_speed_cb
    local isClassicBars = (sfui.compat and sfui.compat.is_classic) and (sfui.swing ~= nil)
    if isClassicBars then
        local swing_bar_cb = create_checkbox(bars_panel, "enable swing timer bars", "enableSwingBars", function(checked)
            if sfui.bars and sfui.bars.update_bar_visibility then
                sfui.bars.update_bar_visibility()
            elseif sfui.bars and sfui.bars.on_state_changed then
                sfui.bars:on_state_changed()
            end
        end, "toggles the 3-weapon swing timer bars (Classic).")
        swing_bar_cb:SetPoint("TOPLEFT", last_toggle_cb, "BOTTOMLEFT", 0, -10)
        last_toggle_cb = swing_bar_cb
    end

    -- Health Bar Position
    local position_header = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
    position_header:SetPoint("TOPLEFT", last_toggle_cb, "BOTTOMLEFT", 0, -20)
    position_header:SetTextColor(white[1], white[2], white[3])
    position_header:SetText("health bar position")

    local health_x_slider = create_slider_input(bars_panel, "x:", "healthBarX", -1000, 1000, 1, function(val)
        if sfui.bars and sfui.bars.update_health_bar_position then
            sfui.bars:update_health_bar_position()
        end
    end)
    health_x_slider:SetPoint("TOPLEFT", position_header, "BOTTOMLEFT", 0, -10)

    local health_y_slider = create_slider_input(bars_panel, "y:", "healthBarY", -1000, 1000, 1, function(val)
        if sfui.bars and sfui.bars.update_health_bar_position then
            sfui.bars:update_health_bar_position()
        end
    end)
    health_y_slider:SetPoint("LEFT", health_x_slider, "RIGHT", 10, 0)
    -- Actually, side-by-side (200px each) fits in 500px panel? Yes, 200+10+200 = 410 < 500.

    local reset_health_pos_btn = CreateFlatButton(bars_panel, "reset position", 120, 22)
    reset_health_pos_btn:SetPoint("TOPLEFT", health_x_slider, "BOTTOMLEFT", 0, -10)
    reset_health_pos_btn:SetScript("OnClick", function()
        local def = sfui.config.healthBar.pos
        SfuiDB.healthBarX = def.x
        SfuiDB.healthBarY = def.y
        health_x_slider:SetSliderValue(def.x)
        health_y_slider:SetSliderValue(def.y)
        if sfui.bars and sfui.bars.update_health_bar_position then
            sfui.bars:update_health_bar_position()
        end
    end)

    -- Health Bar Colors
    local color_header = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
    color_header:SetPoint("TOPLEFT", reset_health_pos_btn, "BOTTOMLEFT", 0, -20)
    color_header:SetTextColor(white[1], white[2], white[3])
    color_header:SetText("health bar colors")

    local fg_color_label = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
    fg_color_label:SetPoint("TOPLEFT", color_header, "BOTTOMLEFT", 0, -10)
    fg_color_label:SetTextColor(white[1], white[2], white[3])
    fg_color_label:SetText("foreground:")

    local fg_color_swatch
    fg_color_swatch = common.create_color_swatch(bars_panel, SfuiDB.healthBarColor or sfui.config.healthBar.color,
        function(r, green, b)
            SfuiDB.healthBarColor = { r, green, b, 1 }
            if sfui.bars and sfui.bars.on_state_changed then sfui.bars:on_state_changed() end
        end)
    fg_color_swatch:SetPoint("LEFT", fg_color_label, "RIGHT", 5, 0)

    local bg_color_label = bars_panel:CreateFontString(nil, "OVERLAY", g.font)
    bg_color_label:SetPoint("LEFT", fg_color_swatch, "RIGHT", 15, 0)
    bg_color_label:SetTextColor(white[1], white[2], white[3])
    bg_color_label:SetText("backdrop:")

    local bg_color_swatch
    bg_color_swatch = common.create_color_swatch(bars_panel,
        SfuiDB.healthBarBackdropColor or sfui.config.healthBar.backdrop.color, function(r, green, b)
            SfuiDB.healthBarBackdropColor = { r, green, b, 0.5 }
            if sfui.bars and sfui.bars.on_state_changed then sfui.bars:on_state_changed() end
        end)
    bg_color_swatch:SetPoint("LEFT", bg_color_label, "RIGHT", 5, 0)

    -- 3. Combat Text Panel (SCT)
    local sct_header = sct_panel:CreateFontString(nil, "OVERLAY", g.font)
    sct_header:SetPoint("TOPLEFT", 15, -15)
    sct_header:SetTextColor(white[1], white[2], white[3])
    sct_header:SetText("blizzard combat text settings")

    local master_cb = create_cvar_checkbox(sct_panel, "enable floating combat text", "enableFloatingCombatText",
        "master toggle for blizzard's floating combat text.")
    master_cb:SetPoint("TOPLEFT", sct_header, "BOTTOMLEFT", 0, -10)

    local damage_cb = create_cvar_checkbox(sct_panel, "show damage", "floatingCombatTextCombatDamage",
        "toggles display of damage numbers over targets.")
    damage_cb:SetPoint("TOPLEFT", master_cb, "BOTTOMLEFT", 0, -5)

    local periodic_cb = create_cvar_checkbox(sct_panel, "show periodic damage (dots)",
        "floatingCombatTextCombatLogPeriodicSpells", "toggles display of periodic damage (dots) numbers.")
    periodic_cb:SetPoint("TOPLEFT", damage_cb, "BOTTOMLEFT", 0, -5)

    local healing_cb = create_cvar_checkbox(sct_panel, "show healing", "floatingCombatTextCombatHealing",
        "toggles display of healing numbers over targets.")
    healing_cb:SetPoint("TOPLEFT", periodic_cb, "BOTTOMLEFT", 0, -5)

    local pet_melee_cb = create_cvar_checkbox(sct_panel, "show pet melee damage", "floatingCombatTextPetMeleeDamage",
        "toggles display of pet melee damage numbers.")
    pet_melee_cb:SetPoint("TOPLEFT", healing_cb, "BOTTOMLEFT", 0, -5)

    local pet_spell_cb = create_cvar_checkbox(sct_panel, "show pet spell damage", "floatingCombatTextPetSpellDamage",
        "toggles display of pet spell damage numbers.")
    pet_spell_cb:SetPoint("TOPLEFT", pet_melee_cb, "BOTTOMLEFT", 0, -5)

    local avoid_cb = create_cvar_checkbox(sct_panel, "show dodge/parry/miss", "floatingCombatTextDodgeParryMiss_v2",
        "toggles display of avoidances.")
    avoid_cb:SetPoint("TOPLEFT", pet_spell_cb, "BOTTOMLEFT", 0, -5)

    local reduction_cb = create_cvar_checkbox(sct_panel, "show resist/block/absorb", "floatingCombatTextDamageReduction_v2",
        "toggles display of damage reduction.")
    reduction_cb:SetPoint("TOPLEFT", avoid_cb, "BOTTOMLEFT", 0, -5)

    local energy_cb = create_cvar_checkbox(sct_panel, "show energy gains/runes", "floatingCombatTextEnergyGains_v2",
        "toggles display of energy gains and runes.")
    energy_cb:SetPoint("TOPLEFT", reduction_cb, "BOTTOMLEFT", 0, -5)

    local auras_cb = create_cvar_checkbox(sct_panel, "show auras", "floatingCombatTextAuras_v2",
        "toggles display of aura gains/losses.")
    auras_cb:SetPoint("TOPLEFT", energy_cb, "BOTTOMLEFT", 0, -5)

    local state_cb = create_cvar_checkbox(sct_panel, "show combat state", "floatingCombatTextCombatState_v2",
        "toggles display of entering/leaving combat.")
    state_cb:SetPoint("TOPLEFT", auras_cb, "BOTTOMLEFT", 0, -5)

    -- 4. Currency / Items Panel
    local currency_header = currency_items_panel:CreateFontString(nil, "OVERLAY", g.font)
    currency_header:SetPoint("TOPLEFT", 15, -15)
    currency_header:SetTextColor(white[1], white[2], white[3])
    currency_header:SetText("currency display settings")

    local currency_info_text = currency_items_panel:CreateFontString(nil, "OVERLAY", g.font)
    currency_info_text:SetPoint("TOPLEFT", currency_header, "BOTTOMLEFT", 0, -10)
    currency_info_text:SetPoint("RIGHT", -15, 0)
    currency_info_text:SetJustifyH("LEFT")
    currency_info_text:SetText(
        "the currency display is automatic. to add or remove currencies, open the default character panel, go to the currencies tab, and check 'show on backpack' for any currency you wish to track. opening and closing the character panel will also update the display.")

    local item_header = currency_items_panel:CreateFontString(nil, "OVERLAY", g.font)
    item_header:SetPoint("TOPLEFT", currency_info_text, "BOTTOMLEFT", 0, -20)
    item_header:SetTextColor(white[1], white[2], white[3])
    item_header:SetText("item tracking settings")

    local item_id_label = currency_items_panel:CreateFontString(nil, "OVERLAY", g.font)
    item_id_label:SetPoint("TOPLEFT", item_header, "BOTTOMLEFT", 0, -10)
    item_id_label:SetText("add item by id:")

    local item_id_input = CreateFrame("EditBox", nil, currency_items_panel, "InputBoxTemplate")
    item_id_input:SetPoint("LEFT", item_id_label, "RIGHT", 10, 0)
    item_id_input:SetSize(100, 32)
    item_id_input:SetAutoFocus(false)

    local add_button = CreateFlatButton(currency_items_panel, "add", 50, 22)
    add_button:SetPoint("LEFT", item_id_input, "RIGHT", 5, 0)
    add_button:SetScript("OnClick", function()
        local id = tonumber(item_id_input:GetText())
        if id and sfui.add_item then
            sfui.add_item(id)
            item_id_input:SetText("")
        end
    end)

    local drop_frame = CreateFrame("Frame", "sfui_item_drop_frame", currency_items_panel, "BackdropTemplate")
    drop_frame:SetPoint("TOPLEFT", item_id_label, "BOTTOMLEFT", 0, -20)
    drop_frame:SetSize(250, 50)
    local drop_frame_backdrop = {
        bgFile = g.textures.tooltip,
        tile = true,
        tileSize = 16,
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    }
    drop_frame:SetBackdrop(drop_frame_backdrop)
    drop_frame:SetBackdropColor(0.3, 0.3, 0.3, 0.7) -- Lighter background
    drop_frame:SetBackdropBorderColor(0, 0, 0, 1)   -- 100% black border

    local drop_label = drop_frame:CreateFontString(nil, "OVERLAY", g.font)
    drop_label:SetAllPoints()
    drop_label:SetText("drop item here")
    drop_label:EnableMouse(false)

    drop_frame:EnableMouse(true)
    drop_frame:RegisterForDrag("LeftButton")
    local function handle_item_drop()
        local cType, _, link = GetCursorInfo()
        if cType == "item" and link then
            local itemID = GetItemInfoFromHyperlink(link)
            if itemID and sfui.add_item then
                sfui.add_item(itemID)
                if ClearCursor then ClearCursor() end
            end
        end
    end
    drop_frame:SetScript("OnReceiveDrag", handle_item_drop)
    drop_frame:SetScript("OnMouseUp", handle_item_drop)

    -- 5. Merchant Panel
    local merchant_header = merchant_panel:CreateFontString(nil, "OVERLAY", g.font)
    merchant_header:SetPoint("TOPLEFT", 15, -15)
    merchant_header:SetTextColor(white[1], white[2], white[3])
    merchant_header:SetText("merchant settings")

    local enable_merchant_cb = create_checkbox(merchant_panel, "enable merchant frame", "enableMerchant", nil,
        "enables the custom merchant frame.")
    enable_merchant_cb:SetPoint("TOPLEFT", merchant_header, "BOTTOMLEFT", 0, -10)

    local enable_decor_cb = create_checkbox(merchant_panel, "enable decor filter", "enableDecor", function(checked)
        if not checked and SfuiDecorDB then
            wipe(SfuiDecorDB)
            common.print("Decor cache cleared.")
        end
        if sfui.merchant and sfui.merchant.reset_scroll_and_rebuild then
            sfui.merchant.reset_scroll_and_rebuild()
        end
    end, "enables the caching and filtering of housing decor items.")
    enable_decor_cb:SetPoint("TOPLEFT", enable_merchant_cb, "BOTTOMLEFT", 0, -10)

    local decor_cache_label = merchant_panel:CreateFontString(nil, "OVERLAY", g.font)
    decor_cache_label:SetPoint("TOPLEFT", enable_decor_cb, "BOTTOMLEFT", 0, -15)
    decor_cache_label:SetTextColor(white[1], white[2], white[3])
    decor_cache_label:SetText("decor cache status:")

    local decor_cache_value = merchant_panel:CreateFontString(nil, "OVERLAY", g.font)
    decor_cache_value:SetPoint("LEFT", decor_cache_label, "RIGHT", 5, 0)
    decor_cache_value:SetText("N/A")

    merchant_panel:HookScript("OnShow", function()
        if sfui.merchant and sfui.merchant.decorCacheStatus then
            decor_cache_value:SetText(sfui.merchant.decorCacheStatus)
        else
            decor_cache_value:SetText("N/A (Not Populated)")
        end
    end)

    -- 6. automation panel
    local COL_OFFSET_X = 265
    local SECTION_GAP = 22

    -- ── 6.1 General Automation ───────────────────────────────────────────────
    local general_header = automation_panel:CreateFontString(nil, "OVERLAY", g.font)
    general_header:SetPoint("TOPLEFT", 15, -15)
    general_header:SetTextColor(white[1], white[2], white[3])
    general_header:SetText("general automation")

    local auto_role_cb = create_checkbox(automation_panel, "auto confirm role checks", "auto_role_check", nil,
        "automatically selects and accepts the role check when a group leader signs up.")
    auto_role_cb:SetPoint("TOPLEFT", general_header, "BOTTOMLEFT", 0, -10)

    local auto_sell_cb = create_checkbox(automation_panel, "auto-sell greys", "autoSellGreys", nil,
        "automatically sells all grey items when opening a merchant.")
    auto_sell_cb:SetPoint("LEFT", auto_role_cb, "LEFT", COL_OFFSET_X, 0)

    local auto_sign_cb = create_checkbox(automation_panel, "auto sign lfg", "auto_sign_lfg", nil,
        "enables double-click signing for premade groups in the lfg tool. hold shift to bypass.")
    auto_sign_cb:SetPoint("TOPLEFT", auto_role_cb, "BOTTOMLEFT", 0, -10)

    local auto_repair_cb = create_checkbox(automation_panel, "auto-repair", "autoRepair", nil,
        "automatically repairs gear (guild first, skips if blacksmith hammer available).")
    auto_repair_cb:SetPoint("LEFT", auto_sign_cb, "LEFT", COL_OFFSET_X, 0)

    -- ── 6.2 Dungeons, Raids & Grouping ───────────────────────────────────────
    local dungeon_header = automation_panel:CreateFontString(nil, "OVERLAY", g.font)
    dungeon_header:SetPoint("TOPLEFT", auto_sign_cb, "BOTTOMLEFT", 0, -SECTION_GAP)
    dungeon_header:SetTextColor(white[1], white[2], white[3])
    dungeon_header:SetText("dungeons, raids & grouping")

    local auto_log_cb = create_checkbox(automation_panel, "auto combat log", "autoCombatLog", function(checked)
        if sfui.logs and sfui.logs.set_enabled then
            sfui.logs.set_enabled(checked)
        end
    end, isClassic and "automatically start/stop combat logging when entering raids." or "automatically start/stop combat logging when entering mythic+ and raids.")
    auto_log_cb:SetPoint("TOPLEFT", dungeon_header, "BOTTOMLEFT", 0, -10)

    local last_dungeon_anchor = auto_log_cb

    if not isClassic then
        if SfuiDB.keystoneReminder == nil then SfuiDB.keystoneReminder = true end
        local keystone_cb = create_checkbox(automation_panel, "keystone location reminder", "keystoneReminder", nil,
            "prints the dungeon name and key level to chat when a mythic+ invite is accepted, and again when the group fills.")
        keystone_cb:SetPoint("LEFT", auto_log_cb, "LEFT", COL_OFFSET_X, 0)

        if SfuiDB.autoLfgDungeonDefaults == nil then SfuiDB.autoLfgDungeonDefaults = true end
        local lfg_dungeon_cb = create_checkbox(automation_panel, "LFG: auto M+ & Competitive", "autoLfgDungeonDefaults", nil,
            "automatically selects Mythic+ Keystone difficulty and Competitive playstyle when creating a dungeon group in Group Finder.")
        lfg_dungeon_cb:SetPoint("TOPLEFT", auto_log_cb, "BOTTOMLEFT", 0, -10)

        if SfuiDB.ahCurrentExpansionFilter == nil then SfuiDB.ahCurrentExpansionFilter = true end
        local ah_expansion_cb = create_checkbox(automation_panel, "AH: current expansion only", "ahCurrentExpansionFilter", nil,
            "automatically enables the \"current expansion only\" filter every time you open the auction house.")
        ah_expansion_cb:SetPoint("LEFT", lfg_dungeon_cb, "LEFT", COL_OFFSET_X, 0)

        if SfuiDB.autoDungeonPortalPopup == nil then SfuiDB.autoDungeonPortalPopup = true end
        local portal_popup_cb = create_checkbox(automation_panel, "dungeon teleport popup", "autoDungeonPortalPopup", nil,
            "shows a clickable dungeon teleport popup when a mythic+ group is formed.")
        portal_popup_cb:SetPoint("TOPLEFT", lfg_dungeon_cb, "BOTTOMLEFT", 0, -10)

        local test_portal_btn = CreateFlatButton(automation_panel, "test preview", 100, 20)
        test_portal_btn:SetPoint("LEFT", portal_popup_cb, "LEFT", COL_OFFSET_X, 0)
        test_portal_btn:SetScript("OnClick", function()
            if sfui.portals and sfui.portals.TestPortalPopup then
                sfui.portals.TestPortalPopup()
            end
        end)

        if SfuiDB.portalPopupOnlyWhenFull == nil then SfuiDB.portalPopupOnlyWhenFull = true end
        local portal_full_cb = create_checkbox(automation_panel, "only when group is full (5/5)", "portalPopupOnlyWhenFull", nil,
            "when enabled, the teleport popup only appears when the 5th member joins; otherwise it also shows immediately upon accepting an invite.")
        portal_full_cb:SetPoint("TOPLEFT", portal_popup_cb, "BOTTOMLEFT", 16, -8)

        last_dungeon_anchor = portal_full_cb
    end

    -- ── 6.3 Recipes & Professions ────────────────────────────────────────────
    local recipe_header = automation_panel:CreateFontString(nil, "OVERLAY", g.font)
    local recipe_x_offset = (last_dungeon_anchor == auto_log_cb) and 0 or -16
    recipe_header:SetPoint("TOPLEFT", last_dungeon_anchor, "BOTTOMLEFT", recipe_x_offset, -SECTION_GAP)
    recipe_header:SetTextColor(white[1], white[2], white[3])
    recipe_header:SetText("recipes & professions")

    if SfuiDB.recipesShowKnown == nil then SfuiDB.recipesShowKnown = true end
    local recipes_known_cb = create_checkbox(automation_panel, "recipes: show known alts", "recipesShowKnown", nil,
        "shows which alts already know a recipe on its tooltip.")
    recipes_known_cb:SetPoint("TOPLEFT", recipe_header, "BOTTOMLEFT", 0, -10)

    if SfuiDB.recipesShowCanLearn == nil then SfuiDB.recipesShowCanLearn = true end
    local recipes_can_learn_cb = create_checkbox(automation_panel, "recipes: show who can learn", "recipesShowCanLearn", nil,
        "shows which alts have the profession and skill rank to learn a recipe on its tooltip.")
    recipes_can_learn_cb:SetPoint("LEFT", recipes_known_cb, "LEFT", COL_OFFSET_X, 0)

    if SfuiDB.recipesTintIcons == nil then SfuiDB.recipesTintIcons = true end
    local recipes_tint_cb = create_checkbox(automation_panel, "recipes: tint icons (merchant & bags)", "recipesTintIcons", nil,
        "color-tints recipe icons in merchants and bags based on known or learnable status.")
    recipes_tint_cb:SetPoint("TOPLEFT", recipes_known_cb, "BOTTOMLEFT", 0, -10)

    if SfuiDB.recipesShowCraftable == nil then SfuiDB.recipesShowCraftable = true end
    local recipes_craftable_cb = create_checkbox(automation_panel, "recipes: show who can craft on items", "recipesShowCraftable", nil,
        "shows which alts can craft an item on that item's tooltip.")
    recipes_craftable_cb:SetPoint("LEFT", recipes_tint_cb, "LEFT", COL_OFFSET_X, 0)

    -- ── 6.4 Master's Hammer Settings (Retail Only) ───────────────────────────
    if not isClassic then
        local hammer_header = automation_panel:CreateFontString(nil, "OVERLAY", g.font)
        hammer_header:SetPoint("TOPLEFT", recipes_tint_cb, "BOTTOMLEFT", 0, -SECTION_GAP)
        hammer_header:SetTextColor(white[1], white[2], white[3])
        hammer_header:SetText("master's hammer settings")

        local enable_hammer_cb = create_checkbox(automation_panel, "enable master's hammer", "enableMasterHammer", function(checked)
            local hammer = sfui.hammer or sfui.automation
            if hammer and hammer.update_hammer_popup then
                hammer.update_hammer_popup()
            end
        end, "enables the automated Master's Hammer repair popup.")
        enable_hammer_cb:SetPoint("TOPLEFT", hammer_header, "BOTTOMLEFT", 0, -10)

        local lock_hammer_cb = create_checkbox(automation_panel, "lock repair icon", "lockRepairIcon", nil,
            "locks the repair icon in place so it cannot be dragged.")
        lock_hammer_cb:SetPoint("LEFT", enable_hammer_cb, "LEFT", COL_OFFSET_X, 0)

        -- Threshold Slider (Width 220)
        local threshold_slider = create_slider_input(automation_panel, "repair threshold (%):", "repairThreshold", 0, 100, 1,
            function(val)
                local hammer = sfui.hammer or sfui.automation
                if hammer and hammer.update_hammer_popup then
                    hammer.update_hammer_popup()
                end
            end, "durability percentage that triggers the repair popup", 220)
        threshold_slider:SetPoint("TOPLEFT", enable_hammer_cb, "BOTTOMLEFT", 0, -12)

        -- Coordinates Sliders (Side-by-side, Width 220)
        local icon_x_slider = create_slider_input(automation_panel, "icon x:", "repairIconX", -1000, 1000, 1, function(val)
            local hammer = sfui.hammer or sfui.automation
            if hammer and hammer.update_popup_style then
                hammer.update_popup_style()
            end
        end, "horizontal offset of the repair icon", 220)
        icon_x_slider:SetPoint("TOPLEFT", threshold_slider, "BOTTOMLEFT", 0, -12)

        local icon_y_slider = create_slider_input(automation_panel, "icon y:", "repairIconY", -1000, 1000, 1, function(val)
            local hammer = sfui.hammer or sfui.automation
            if hammer and hammer.update_popup_style then
                hammer.update_popup_style()
            end
        end, "vertical offset of the repair icon", 220)
        icon_y_slider:SetPoint("LEFT", icon_x_slider, "LEFT", COL_OFFSET_X, 0)

        -- Action Buttons (Side-by-side)
        local reset_hammer_pos_btn = CreateFlatButton(automation_panel, "reset position", 120, 22)
        reset_hammer_pos_btn:SetPoint("TOPLEFT", icon_x_slider, "BOTTOMLEFT", 0, -12)
        reset_hammer_pos_btn:SetScript("OnClick", function()
            local def = (sfui.config.masterHammer and sfui.config.masterHammer.defaultPosition) or { x = 0, y = 0 }
            SfuiDB.repairIconX = def.x
            SfuiDB.repairIconY = def.y
            icon_x_slider:SetSliderValue(def.x)
            icon_y_slider:SetSliderValue(def.y)
            local hammer = sfui.hammer or sfui.automation
            if hammer and hammer.update_popup_style then
                hammer.update_popup_style()
            end
            if sfui.common and sfui.common.print then
                sfui.common.print("sfui: repair button position reset to center (" .. def.x .. ", " .. def.y .. ").")
            end
        end)

        local test_hammer_btn = CreateFlatButton(automation_panel, "test preview", 120, 22)
        test_hammer_btn:SetPoint("LEFT", reset_hammer_pos_btn, "RIGHT", 10, 0)
        test_hammer_btn:SetScript("OnClick", function(self)
            local hammer = sfui.hammer or sfui.automation
            if hammer and hammer.toggle_test_popup then
                local active = hammer.toggle_test_popup()
                self:SetText(active and "hide preview" or "test preview")
            end
        end)
        test_hammer_btn:SetScript("OnShow", function(self)
            local hammer = sfui.hammer or sfui.automation
            local active = hammer and hammer.is_test_mode and hammer.is_test_mode()
            self:SetText(active and "hide preview" or "test preview")
        end)

        sfui.options = sfui.options or {}
        sfui.options.sync_hammer_sliders = function(x, y)
            if icon_x_slider and icon_x_slider.SetSliderValue then
                icon_x_slider:SetSliderValue(x)
            end
            if icon_y_slider and icon_y_slider.SetSliderValue then
                icon_y_slider:SetSliderValue(y)
            end
        end

        -- Hex Color Customization Row
        local color_label = automation_panel:CreateFontString(nil, "OVERLAY", g.font)
        color_label:SetPoint("TOPLEFT", reset_hammer_pos_btn, "BOTTOMLEFT", 0, -14)
        color_label:SetTextColor(white[1], white[2], white[3])
        color_label:SetText("color (#hex):")

        local color_input = CreateFrame("EditBox", nil, automation_panel, "InputBoxTemplate")
        color_input:SetPoint("LEFT", color_label, "RIGHT", 8, 0)
        color_input:SetSize(75, 20)
        color_input:SetAutoFocus(false)
        color_input:SetScript("OnShow", function(self) self:SetText(SfuiDB.repairIconColor or "00FFFF") end)
        color_input:SetScript("OnEnterPressed", function(self)
            local val = self:GetText()
            SfuiDB.repairIconColor = val
            local hammer = sfui.hammer or sfui.automation
            if hammer and hammer.update_popup_style then
                hammer.update_popup_style()
            end
            self:ClearFocus()
        end)
    end

    -- ─────────────────────────────────────────────────────────────────────────
    --  7. FISHING AUTOMATION TAB
    -- ─────────────────────────────────────────────────────────────────────────
    do
        local p = fishing_panel
        local COL_OFFSET_X = 265
        local SECTION_GAP = 22

        -- Header
        local fishing_header = p:CreateFontString(nil, "OVERLAY", g.font_large)
        fishing_header:SetPoint("TOPLEFT", 15, -15)
        fishing_header:SetTextColor(white[1], white[2], white[3])
        fishing_header:SetText("fishing automation")

        -- ── Section 1: Casting & Interaction ─────────────────────────────────
        local cast_header = p:CreateFontString(nil, "OVERLAY", g.font)
        cast_header:SetPoint("TOPLEFT", fishing_header, "BOTTOMLEFT", 0, -18)
        cast_header:SetTextColor(0, 1, 1, 1)
        cast_header:SetText("casting & interaction")

        if SfuiDB.fishingEnabled == nil then SfuiDB.fishingEnabled = true end
        local fishing_enable_cb = create_checkbox(p, "enable fishing automation", "fishingEnabled", function(checked)
            notify_setting_changed("fishing", "enabled", checked)
        end, "enables 1-key and double-right-click fishing automation.")
        fishing_enable_cb:SetPoint("TOPLEFT", cast_header, "BOTTOMLEFT", 0, -10)

        if SfuiDB.fishingDoubleClick == nil then SfuiDB.fishingDoubleClick = true end
        local fishing_double_cb = create_checkbox(p, "double-click fishing", "fishingDoubleClick", function(checked)
            notify_setting_changed("fishing", "doubleClick", checked)
        end, "double right-click anywhere in the world to cast fishing and catch the bobber.")
        fishing_double_cb:SetPoint("LEFT", fishing_enable_cb, "LEFT", COL_OFFSET_X, 0)

        if SfuiDB.fishingMounted == nil then SfuiDB.fishingMounted = false end
        local fishing_mounted_cb = create_checkbox(p, "allow while mounted", "fishingMounted", function(checked)
            notify_setting_changed("fishing", "doubleClickForce", checked)
        end, "allows double-click fishing attempts while mounted.")
        fishing_mounted_cb:SetPoint("TOPLEFT", fishing_enable_cb, "BOTTOMLEFT", 0, -10)

        if SfuiDB.fishingRecast == nil then SfuiDB.fishingRecast = false end
        local fishing_recast_cb = create_checkbox(p, "recast on double-click", "fishingRecast", function(checked)
            notify_setting_changed("fishing", "recastOnDoubleClick", checked)
        end, "double right-click while casting will recast immediately instead of reeling in.")
        fishing_recast_cb:SetPoint("LEFT", fishing_mounted_cb, "LEFT", COL_OFFSET_X, 0)

        if SfuiDB.fishingDoubleClickSpeed == nil then SfuiDB.fishingDoubleClickSpeed = 0.4 end
        local fishing_speed_slider = create_slider_input(p, "double-click speed (sec):", "fishingDoubleClickSpeed", 0.1, 1.0, 0.05, function(val)
            notify_setting_changed("fishing", "doubleClickSpeed", val)
        end, "maximum delay in seconds between right-clicks to trigger fishing.", 220)
        fishing_speed_slider:SetPoint("TOPLEFT", fishing_mounted_cb, "BOTTOMLEFT", 0, -12)

        -- ── Section 2: Bobber & Audio Enhancements ───────────────────────────
        local bobber_header = p:CreateFontString(nil, "OVERLAY", g.font)
        bobber_header:SetPoint("TOPLEFT", fishing_speed_slider, "BOTTOMLEFT", 0, -SECTION_GAP)
        bobber_header:SetTextColor(0, 1, 1, 1)
        bobber_header:SetText("bobber & audio enhancements")

        if SfuiDB.fishingSoftTarget == nil then SfuiDB.fishingSoftTarget = true end
        local fishing_soft_cb = create_checkbox(p, "soft-target bobber interact", "fishingSoftTarget", function(checked)
            notify_setting_changed("fishing", "softTarget", checked)
        end, "automatically highlights and interacts with the bobber using soft-targeting CVars.")
        fishing_soft_cb:SetPoint("TOPLEFT", bobber_header, "BOTTOMLEFT", 0, -10)

        if SfuiDB.fishingEnhanceSounds == nil then SfuiDB.fishingEnhanceSounds = true end
        local fishing_sound_cb = create_checkbox(p, "enhance fishing audio", "fishingEnhanceSounds", function(checked)
            notify_setting_changed("fishing", "enhanceSounds", checked)
        end, "boosts splash effects and mutes ambience/music during cast.")
        fishing_sound_cb:SetPoint("LEFT", fishing_soft_cb, "LEFT", COL_OFFSET_X, 0)

        if SfuiDB.fishingOverrideLunker == nil then SfuiDB.fishingOverrideLunker = false end
        local fishing_lunker_cb = create_checkbox(p, "override lunker fishing", "fishingOverrideLunker", function(checked)
            notify_setting_changed("fishing", "overrideLunker", checked)
        end, "always use standard fishing cast even when in a lunker fishing pool.")
        fishing_lunker_cb:SetPoint("TOPLEFT", fishing_soft_cb, "BOTTOMLEFT", 0, -10)

        if SfuiDB.fishingSoundScale == nil then SfuiDB.fishingSoundScale = 1.0 end
        local fishing_vol_slider = create_slider_input(p, "sound volume:", "fishingSoundScale", 0.1, 1.0, 0.05, function(val)
            notify_setting_changed("fishing", "enhanceSoundsScale", val)
        end, "volume multiplier for fishing splash sound effects.", 220)
        fishing_vol_slider:SetPoint("LEFT", fishing_lunker_cb, "LEFT", COL_OFFSET_X, 0)

        local sound_reset_btn = sfui.common.create_flat_button(p, "restore sound defaults", 150, 20)
        sound_reset_btn:SetPoint("TOPLEFT", fishing_lunker_cb, "BOTTOMLEFT", 0, -10)
        sound_reset_btn:SetScript("OnClick", function()
            if sfui.fishing and sfui.fishing.RestoreSoundDefaults then
                sfui.fishing.RestoreSoundDefaults()
            end
        end)

        -- ── Section 3: Keybinds & Instructions ───────────────────────────────
        local tips_header = p:CreateFontString(nil, "OVERLAY", g.font)
        tips_header:SetPoint("TOPLEFT", sound_reset_btn, "BOTTOMLEFT", 0, -SECTION_GAP)
        tips_header:SetTextColor(0, 1, 1, 1)
        tips_header:SetText("keybinds & instructions")

        local keybind_status = p:CreateFontString(nil, "OVERLAY", g.font)
        keybind_status:SetPoint("TOPLEFT", tips_header, "BOTTOMLEFT", 0, -8)

        local function update_keybind_display()
            local keys = sfui.fishing and sfui.fishing.get_all_bound_keys and sfui.fishing.get_all_bound_keys() or {}
            if #keys > 0 then
                keybind_status:SetText("Active Keybind: |cff00ff00" .. table.concat(keys, ", ") .. "|r")
            else
                keybind_status:SetText("Active Keybind: |cffff5555None|r |cff888888(bind 'Cast & Catch Fishing' in Keybindings)|r")
            end
        end
        update_keybind_display()

        local keybind_btn = sfui.common.create_flat_button(p, "open keybindings", 140, 20)
        keybind_btn:SetPoint("LEFT", keybind_status, "RIGHT", 15, 0)
        keybind_btn:SetScript("OnClick", function()
            if Settings and Settings.OpenToCategory and Settings.KEYBINDINGS_CATEGORY_ID then
                Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID)
            elseif KeyBindingFrame_LoadUI then
                KeyBindingFrame_LoadUI()
                ShowUIPanel(KeyBindingFrame)
            end
        end)

        local tips_text = p:CreateFontString(nil, "OVERLAY", g.font_small)
        tips_text:SetPoint("TOPLEFT", keybind_status, "BOTTOMLEFT", 0, -12)
        tips_text:SetTextColor(0.7, 0.7, 0.7, 1)
        tips_text:SetWidth(480)
        tips_text:SetJustifyH("LEFT")
        tips_text:SetText(
            "• |cffffffff1-Key Cast & Reel|r: Press your bound key once to cast. When the bobber splashes, press the exact same key to reel in.\n\n" ..
            "• |cffffffffGamepad Fishing|r: Enable controller support via |cff00ffff/console GamePadEnable 1|r. In Keybindings > SFUI, bind your trigger or button (e.g. Right Trigger). You can then fish with just that one controller button!\n\n" ..
            "• |cffffffffDouble-Click Fishing|r: Double right-click anywhere in the world to cast. When the bobber splashes, click again to reel in.\n\n" ..
            "• |cffffffffMacro & Slash|r: Use |cff00ffff/sffish|r or |cff00ffff/click SfuiFishingButton|r in macros or chat."
        )

        p:HookScript("OnShow", function()
            update_keybind_display()
        end)

        sfui.events.RegisterEvent("UPDATE_BINDINGS", function()
            if p:IsVisible() then
                update_keybind_display()
            end
        end)
    end


    local minimap_header = minimap_panel:CreateFontString(nil, "OVERLAY", g.font)
    minimap_header:SetPoint("TOPLEFT", 15, -15)
    minimap_header:SetTextColor(white[1], white[2], white[3])
    minimap_header:SetText("minimap settings")

    local collect_cb = create_checkbox(minimap_panel, "collect buttons", "minimap_collect_buttons", function(checked)
        if sfui.minimap and sfui.minimap.enable_button_manager then
            sfui.minimap.enable_button_manager(checked)
        end
    end, "collects minimap buttons into a bar.")
    collect_cb:SetPoint("TOPLEFT", minimap_header, "BOTTOMLEFT", 0, -10)

    local mouseover_cb = create_checkbox(minimap_panel, "mouseover only", "minimap_buttons_mouseover", function(checked)
        if sfui.minimap and sfui.minimap.enable_button_manager and SfuiDB.minimap_collect_buttons then
            C_Timer.After(0.1, function()
                sfui.minimap.enable_button_manager(false)
                sfui.minimap.enable_button_manager(true)
            end)
        end
    end, "only show the button bar when hovering the minimap. also moves group finder eye to top left.")
    mouseover_cb:SetPoint("TOPLEFT", collect_cb, "BOTTOMLEFT", 0, -10)

    local autozoom_cb = create_checkbox(minimap_panel, "enable autozoom", "minimap_auto_zoom", function(checked)
        if sfui.minimap and sfui.minimap.reset_zoom_timer then
            sfui.minimap.reset_zoom_timer()
        end
    end, "automatically resets minimap zoom after a delay.")
    autozoom_cb:SetPoint("TOPLEFT", mouseover_cb, "BOTTOMLEFT", 0, -10)

    local autozoom_delay = create_slider_input(minimap_panel, "autozoom delay:", "minimap_auto_zoom_delay", 1, 30, 1,
        function(val)
            if sfui.minimap and sfui.minimap.reset_zoom_timer then
                sfui.minimap.reset_zoom_timer()
            end
        end, "seconds to wait before automatically zooming out.")
    autozoom_delay:SetPoint("TOPLEFT", autozoom_cb, "BOTTOMLEFT", 0, -15)

    -- Position X input
    local pos_x_slider = create_slider_input(minimap_panel, "minimap x:", "minimap_button_x", -1000, 1000, 1,
        function(val)
            if sfui.minimap and sfui.minimap.update_button_bar_position then
                sfui.minimap.update_button_bar_position()
            end
        end)
    pos_x_slider:SetPoint("TOPLEFT", autozoom_delay, "BOTTOMLEFT", 0, -15)

    -- Position Y input
    local pos_y_slider = create_slider_input(minimap_panel, "minimap y:", "minimap_button_y", -1000, 1000, 1,
        function(val)
            if sfui.minimap and sfui.minimap.update_button_bar_position then
                sfui.minimap.update_button_bar_position()
            end
        end)
    pos_y_slider:SetPoint("LEFT", pos_x_slider, "RIGHT", 10, 0)

    -- Reset button
    local reset_pos_btn = CreateFlatButton(minimap_panel, "reset position", 120, 22)
    reset_pos_btn:SetPoint("TOPLEFT", pos_x_slider, "BOTTOMLEFT", 0, -10)
    reset_pos_btn:SetScript("OnClick", function()
        local def = sfui.config.minimap.button_bar
        SfuiDB.minimap_button_x = def.defaultX
        SfuiDB.minimap_button_y = def.defaultY
        pos_x_slider:SetSliderValue(def.defaultX)
        pos_y_slider:SetSliderValue(def.defaultY)
        if sfui.minimap and sfui.minimap.update_button_bar_position then
            sfui.minimap.update_button_bar_position()
        end
    end)

    -- Gear Swapper Settings
    local gear_header = gear_panel:CreateFontString(nil, "OVERLAY", g.font)
    gear_header:SetPoint("TOPLEFT", 15, -15)
    gear_header:SetTextColor(white[1], white[2], white[3])
    gear_header:SetText("automatic gear swapper settings")

    local gear_info = gear_panel:CreateFontString(nil, "OVERLAY", g.font)
    gear_info:SetPoint("TOPLEFT", gear_header, "BOTTOMLEFT", 0, -10)
    gear_info:SetPoint("RIGHT", -15, 0)
    gear_info:SetJustifyH("LEFT")
    gear_info:SetText(
        "automatically swap to a configured gear set based on the content. entering pvp instances or warmode world zones will equip the pvp set. everything else will equip the pve set."
    )

    local function GetEquipmentSetOptions()
        local options = { { text = "None", value = "" } }
        if C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs then
            local setIDs = C_EquipmentSet.GetEquipmentSetIDs()
            if setIDs then
                for _, id in ipairs(setIDs) do
                    local name = C_EquipmentSet.GetEquipmentSetInfo(id)
                    if name then table.insert(options, { text = name, value = name }) end
                end
            end
        end
        return options
    end

    local updateFuncs = {}

    gear_panel:SetScript("OnShow", function(self)
        if self.initialized then
            for _, f in ipairs(updateFuncs) do f() end
            return
        end
        self.initialized = true

        local _, gearSpecIDs = common.get_player_specs()

        local open_gear_btn = CreateFlatButton(gear_panel, "open gear manager", 140, 22)
        open_gear_btn:SetPoint("TOPLEFT", gear_info, "BOTTOMLEFT", 0, -10)
        open_gear_btn:SetScript("OnClick", function()
            if sfui.gear and sfui.gear.toggle then
                sfui.gear.toggle()
            end
        end)

        local gear_auto_open_cb = common.create_checkbox(gear_panel, "Auto-show with Character Panel", function()
            if SfuiDB.gear and SfuiDB.gear.auto_open ~= nil then return SfuiDB.gear.auto_open end
            return true
        end, function(checked)
            SfuiDB.gear = SfuiDB.gear or {}
            SfuiDB.gear.auto_open = checked
        end)
        gear_auto_open_cb:SetPoint("TOPLEFT", open_gear_btn, "BOTTOMLEFT", 0, -10)

        local auto_equip_highest_cb = common.create_checkbox(gear_panel,
            "auto-equip best gear (while not max level)", function()
            if SfuiDB.gear and SfuiDB.gear.auto_equip_highest ~= nil then return SfuiDB.gear.auto_equip_highest end
            return true
        end, function(checked)
            SfuiDB.gear = SfuiDB.gear or {}
            SfuiDB.gear.auto_equip_highest = checked
            if SfuiGearManagerFrame and SfuiGearManagerFrame.maxLvlChk then
                SfuiGearManagerFrame.maxLvlChk:SetChecked(checked)
            end
            if checked and sfui.gear and sfui.gear.Update then
                sfui.gear.Update()
            end
        end)
        auto_equip_highest_cb:SetPoint("TOPLEFT", gear_auto_open_cb, "BOTTOMLEFT", 0, -10)

        local pveHeader = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pveHeader:SetPoint("TOPLEFT", auto_equip_highest_cb, "BOTTOMLEFT", 45, -12)
        pveHeader:SetText("PvE Target")

        local pvpHeader = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pvpHeader:SetPoint("LEFT", pveHeader, "RIGHT", 80, 0)
        pvpHeader:SetText("PvP Target")

        local prevRowAnchor
        for i, id in ipairs(gearSpecIDs or {}) do
            local icon = common.get_spec_icon(id)

            local iconTex = self:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(32, 32)
            if i == 1 then
                iconTex:SetPoint("TOPLEFT", auto_equip_highest_cb, "BOTTOMLEFT", 0, -32)
            else
                iconTex:SetPoint("TOPLEFT", prevRowAnchor, "BOTTOMLEFT", 0, -12)
            end
            iconTex:SetTexture(icon)

            local pveDrop = common.create_dropdown(gear_panel, 120, GetEquipmentSetOptions, function(val)
                SfuiDB.gear[id] = SfuiDB.gear[id] or { pve_set = "", pvp_set = "" }
                SfuiDB.gear[id].pve_set = val
                if sfui.gear and sfui.gear.Update then sfui.gear.Update() end
            end, "")
            pveDrop:SetPoint("BOTTOMLEFT", iconTex, "BOTTOMRIGHT", 5, -5)

            local pvpDrop = common.create_dropdown(gear_panel, 120, GetEquipmentSetOptions, function(val)
                SfuiDB.gear[id] = SfuiDB.gear[id] or { pve_set = "", pvp_set = "" }
                SfuiDB.gear[id].pvp_set = val
                if sfui.gear and sfui.gear.Update then sfui.gear.Update() end
            end, "")
            pvpDrop:SetPoint("LEFT", pveDrop, "RIGHT", 5, 0)

            table.insert(updateFuncs, function()
                local db = SfuiDB.gear[id]
                if db then
                    pveDrop:SetText(db.pve_set ~= "" and db.pve_set or "None")
                    pvpDrop:SetText(db.pvp_set ~= "" and db.pvp_set or "None")
                end
            end)

            updateFuncs[#updateFuncs]()
            prevRowAnchor = iconTex
        end
    end)

    -- 8. Research Viewer Panel
    if research_panel then
        local research_header = research_panel:CreateFontString(nil, "OVERLAY", g.font)
        research_header:SetPoint("TOPLEFT", 15, -15)
        research_header:SetTextColor(white[1], white[2], white[3])
        research_header:SetText("research viewer settings")

        local research_info = research_panel:CreateFontString(nil, "OVERLAY", g.font)
        research_info:SetPoint("TOPLEFT", research_header, "BOTTOMLEFT", 0, -10)
        research_info:SetPoint("RIGHT", -15, 0)
        research_info:SetJustifyH("LEFT")
        research_info:SetText(
            "the research viewer allows you to view various talent and research trees (skyriding, delves, etc.) from anywhere. you can also open it by middle-clicking the sfui minimap icon.")

        local toggle_research_button = CreateFlatButton(research_panel, "open research viewer", 160, 22)
        toggle_research_button:SetPoint("TOPLEFT", research_info, "BOTTOMLEFT", 0, -20)
        toggle_research_button:SetScript("OnClick", function()
            if sfui.research and sfui.research.toggle_selection then
                sfui.research.toggle_selection()
                frame:Hide()
            end
        end)

        local custom_header = research_panel:CreateFontString(nil, "OVERLAY", g.font)
        custom_header:SetPoint("TOPLEFT", toggle_research_button, "BOTTOMLEFT", 0, -30)
        custom_header:SetTextColor(white[1], white[2], white[3])
        custom_header:SetText("manual tree entry")

        local custom_id_label = research_panel:CreateFontString(nil, "OVERLAY", g.font)
        custom_id_label:SetPoint("TOPLEFT", custom_header, "BOTTOMLEFT", 0, -10)
        custom_id_label:SetText("enter tree id:")

        local custom_id_input = CreateFrame("EditBox", nil, research_panel, "InputBoxTemplate")
        custom_id_input:SetPoint("LEFT", custom_id_label, "RIGHT", 10, 0)
        custom_id_input:SetSize(80, 32)
        custom_id_input:SetAutoFocus(false)

        local add_trait_button = CreateFlatButton(research_panel, "trait", 60, 22)
        add_trait_button:SetPoint("LEFT", custom_id_input, "RIGHT", 5, 0)
        add_trait_button:SetScript("OnClick", function()
            local id = tonumber(custom_id_input:GetText())
            if id and sfui.research and sfui.research.open_tree then
                sfui.research.open_tree({ id = id, isTraitTree = true, name = "Custom " .. id })
                frame:Hide()
            end
        end)
        add_trait_button:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("trait tree (skyriding, delves, etc.)")
                GameTooltip:Show()
            end
        end)
        add_trait_button:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)

        local add_garr_button = CreateFlatButton(research_panel, "garr", 60, 22)
        add_garr_button:SetPoint("LEFT", add_trait_button, "RIGHT", 5, 0)
        add_garr_button:SetScript("OnClick", function()
            local id = tonumber(custom_id_input:GetText())
            if id and sfui.research and sfui.research.open_tree then
                sfui.research.open_tree({ id = id, isTraitTree = false, type = 111, name = "Custom " .. id })
                frame:Hide()
            end
        end)
        add_garr_button:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("garrison / order hall / covenant tree")
                GameTooltip:Show()
            end
        end)
        add_garr_button:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
    end


    -- ─────────────────────────────────────────────────────────────────────────
    --  OBJECTIVES TAB
    -- ─────────────────────────────────────────────────────────────────────────
    do
        local p = objectives_panel
        local yOff = -15

        -- ── Header ────────────────────────────────────────────────────────────
        local obj_header = p:CreateFontString(nil, "OVERLAY", g.font_large)
        obj_header:SetPoint("TOPLEFT", p, "TOPLEFT", 15, yOff)
        obj_header:SetTextColor(white[1], white[2], white[3])
        obj_header:SetText("objectives & tracker")
        yOff = yOff - 30

        -- ────────────────────────────────────────────────────────────────────
        --  SECTION: Quest Log / Objective Tracker
        -- ────────────────────────────────────────────────────────────────────
        local ql_section = p:CreateFontString(nil, "OVERLAY", g.font)
        ql_section:SetPoint("TOPLEFT", p, "TOPLEFT", 15, yOff)
        ql_section:SetTextColor(0, 1, 1, 1)   -- cyan accent
        ql_section:SetText("quest log / objective tracker")
        yOff = yOff - 22

        local enable_ql_cb = create_checkbox(p, "enable sfui quest log",
            function()
                if sfui.questlog and sfui.questlog.is_enabled then
                    return sfui.questlog.is_enabled()
                end
                if SfuiDB.enableQuestLog ~= nil then return SfuiDB.enableQuestLog end
                return true
            end,
            function(checked)
                if sfui.questlog and sfui.questlog.set_enabled then
                    sfui.questlog.set_enabled(checked)
                else
                    SfuiDB.enableQuestLog = checked
                end
            end,
            "Enables or disables the SFUI custom quest log and objective tracker. " ..
            "When disabled the default Blizzard tracker is shown.")
        enable_ql_cb:SetPoint("TOPLEFT", p, "TOPLEFT", 15, yOff)
        yOff = yOff - 28

        local lock_ql_cb = create_checkbox(p, "lock quest log position",
            function()
                return SfuiDB.questlogUnlocked ~= true
            end,
            function(checked)
                SfuiDB.questlogUnlocked = not checked
                -- Notify quests.lua if it exposes a position-lock function
                if sfui.questlog and sfui.questlog.set_locked then
                    sfui.questlog.set_locked(checked)
                end
            end,
            "When unlocked you can drag the quest log frame to a new position. " ..
            "The position is saved between sessions.")
        lock_ql_cb:SetPoint("TOPLEFT", p, "TOPLEFT", 15, yOff)
        yOff = yOff - 30

        local reset_ql_pos_btn = CreateFlatButton(p, "reset position", 120, 22)
        reset_ql_pos_btn:SetPoint("TOPLEFT", p, "TOPLEFT", 15, yOff)
        reset_ql_pos_btn:SetScript("OnClick", function()
            if sfui.questlog and sfui.questlog.reset_position then
                sfui.questlog.reset_position()
            else
                if SfuiDB then
                    SfuiDB.questlogX = nil
                    SfuiDB.questlogY = nil
                end
            end
        end)
        yOff = yOff - 36

        -- ────────────────────────────────────────────────────────────────────
        --  SECTION: Mythic+ HUD (Retail only)
        -- ────────────────────────────────────────────────────────────────────
        if not isClassic then
            local mplus_section = p:CreateFontString(nil, "OVERLAY", g.font)
            mplus_section:SetPoint("TOPLEFT", p, "TOPLEFT", 15, yOff)
            mplus_section:SetTextColor(0, 1, 1, 1)   -- cyan accent
            mplus_section:SetText("mythic+ timer hud")
            yOff = yOff - 22

            local enable_mhud_cb = create_checkbox(p, "enable mythic+ hud",
                function()
                    if sfui.mythic and sfui.mythic.IsEnabled then return sfui.mythic.IsEnabled() end
                    return SfuiDB.mythicHudEnabled ~= false
                end,
                function(checked)
                    if sfui.mythic and sfui.mythic.SetEnabled then
                        sfui.mythic.SetEnabled(checked)
                    else
                        SfuiDB.mythicHudEnabled = checked
                    end
                end,
                "When enabled, SFUI displays a native Mythic+ HUD with the dungeon timer, " ..
                "death count, boss checkmarks, and enemy forces bar. " ..
                "Disable this if you use an external M+ timer addon.")
            enable_mhud_cb:SetPoint("TOPLEFT", p, "TOPLEFT", 15, yOff)
            yOff = yOff - 28

            local lock_mhud_cb = create_checkbox(p, "lock mythic+ hud position",
                function()
                    return SfuiDB.mythicHudUnlocked ~= true
                end,
                function(checked)
                    SfuiDB.mythicHudUnlocked = not checked
                    if sfui.mythic and sfui.mythic.SetLocked then
                        sfui.mythic.SetLocked(checked)
                    end
                end,
                "When unlocked you can drag the Mythic+ HUD to any position on screen. " ..
                "The position is saved automatically between sessions.")
            lock_mhud_cb:SetPoint("TOPLEFT", p, "TOPLEFT", 15, yOff)
            yOff = yOff - 30

            local reset_mhud_pos_btn = CreateFlatButton(p, "reset position", 120, 22)
            reset_mhud_pos_btn:SetPoint("TOPLEFT", p, "TOPLEFT", 15, yOff)
            reset_mhud_pos_btn:SetScript("OnClick", function()
                if sfui.mythic and sfui.mythic.ResetPosition then
                    sfui.mythic.ResetPosition()
                else
                    if SfuiDB then
                        SfuiDB.mythicHudX = nil
                        SfuiDB.mythicHudY = nil
                    end
                end
            end)
            yOff = yOff - 34

            -- Preview button row
            local preview_hint = p:CreateFontString(nil, "OVERLAY", g.font_small)
            preview_hint:SetPoint("TOPLEFT", p, "TOPLEFT", 15, yOff)
            preview_hint:SetTextColor(0.6, 0.6, 0.6, 1)
            preview_hint:SetText("preview m+ hud with sample data:")
            yOff = yOff - 20

            local preview_btn = CreateFlatButton(p, "show preview", 110, 22)
            preview_btn:SetPoint("TOPLEFT", p, "TOPLEFT", 15, yOff)

            local hide_preview_btn = CreateFlatButton(p, "hide preview", 110, 22)
            hide_preview_btn:SetPoint("LEFT", preview_btn, "RIGHT", 10, 0)

            preview_btn:SetScript("OnClick", function()
                if sfui.mythic and sfui.mythic.ShowPreview then
                    sfui.mythic.ShowPreview()
                end
            end)
            hide_preview_btn:SetScript("OnClick", function()
                if sfui.mythic and sfui.mythic.HidePreview then
                    sfui.mythic.HidePreview()
                end
            end)
            yOff = yOff - 34

            -- Resize hint
            local resize_hint = p:CreateFontString(nil, "OVERLAY", g.font_small)
            resize_hint:SetPoint("TOPLEFT", p, "TOPLEFT", 15, yOff)
            resize_hint:SetTextColor(0.45, 0.45, 0.45, 1)
            resize_hint:SetText("unlock the hud above, then drag the purple handle to reposition it.")
        end
    end

    -- ─────────────────────────────────────────────────────────────────────────
    --  9. DEBUG / DIAGNOSTICS TAB
    -- ─────────────────────────────────────────────────────────────────────────
    local function get_power_type_name(power_enum)
        if not power_enum then return "None" end
        if type(power_enum) ~= "number" then return tostring(power_enum) end
        if Enum and Enum.PowerType then
            for name, value in pairs(Enum.PowerType) do
                if value == power_enum then return name end
            end
        end
        return tostring(power_enum)
    end

    local debug_header = debug_panel:CreateFontString(nil, "OVERLAY", g.font_large)
    debug_header:SetPoint("TOPLEFT", 15, -15)
    debug_header:SetTextColor(white[1], white[2], white[3])
    debug_header:SetText("diagnostics & debug")

    local debug_refresh_button = CreateFlatButton(debug_panel, "refresh", 100, 22)
    debug_refresh_button:SetPoint("TOPLEFT", debug_header, "BOTTOMLEFT", 0, -10)

    local memory_button = CreateFlatButton(debug_panel, "memory profiler", 130, 22)
    memory_button:SetPoint("LEFT", debug_refresh_button, "RIGHT", 10, 0)
    memory_button:SetScript("OnClick", function()
        if sfui.mem and sfui.mem.ToggleGUI then
            sfui.mem.ToggleGUI()
        end
    end)

    -- Column 1: Character & Spec
    local col1_header = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    col1_header:SetPoint("TOPLEFT", debug_refresh_button, "BOTTOMLEFT", 0, -20)
    col1_header:SetTextColor(0, 1, 1, 1)
    col1_header:SetText("character & spec")

    local spec_id_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    spec_id_label:SetPoint("TOPLEFT", col1_header, "BOTTOMLEFT", 0, -12)
    spec_id_label:SetText("spec id:")
    local spec_id_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    spec_id_value:SetPoint("LEFT", spec_id_label, "RIGHT", 5, 0)

    local color_swatch = debug_panel:CreateTexture(nil, "ARTWORK")
    color_swatch:SetSize(16, 16)
    color_swatch:SetPoint("LEFT", spec_id_value, "RIGHT", 8, 0)
    color_swatch:SetTexture("Interface/Buttons/WHITE8X8")

    local primary_power_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    primary_power_label:SetPoint("TOPLEFT", spec_id_label, "BOTTOMLEFT", 0, -12)
    primary_power_label:SetText("primary power:")
    local primary_power_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    primary_power_value:SetPoint("LEFT", primary_power_label, "RIGHT", 5, 0)

    local secondary_power_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    secondary_power_label:SetPoint("TOPLEFT", primary_power_label, "BOTTOMLEFT", 0, -12)
    secondary_power_label:SetText("secondary power:")
    local secondary_power_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    secondary_power_value:SetPoint("LEFT", secondary_power_label, "RIGHT", 5, 0)

    local form_id_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    form_id_label:SetPoint("TOPLEFT", secondary_power_label, "BOTTOMLEFT", 0, -12)
    form_id_label:SetText("current form id:")
    local form_id_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    form_id_value:SetPoint("LEFT", form_id_label, "RIGHT", 5, 0)

    -- Column 2: Modules & Automation
    local col2_header = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    col2_header:SetPoint("TOPLEFT", debug_panel, "TOPLEFT", 280, -78)
    col2_header:SetTextColor(0, 1, 1, 1)
    col2_header:SetText("modules & automation")

    local pet_warning_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    pet_warning_label:SetPoint("TOPLEFT", col2_header, "BOTTOMLEFT", 0, -12)
    pet_warning_label:SetText("pet warning status:")
    local pet_warning_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    pet_warning_value:SetPoint("LEFT", pet_warning_label, "RIGHT", 5, 0)

    local hammer_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    hammer_label:SetPoint("TOPLEFT", pet_warning_label, "BOTTOMLEFT", 0, -12)
    hammer_label:SetText("master's hammer:")
    local hammer_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    hammer_value:SetPoint("LEFT", hammer_label, "RIGHT", 5, 0)

    local hammer_id_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    hammer_id_label:SetPoint("TOPLEFT", hammer_label, "BOTTOMLEFT", 0, -12)
    hammer_id_label:SetText("hammer item id:")
    local hammer_id_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
    hammer_id_value:SetPoint("LEFT", hammer_id_label, "RIGHT", 5, 0)

    local function update_debug_info()
        local specID = common.get_current_spec_id()
        spec_id_value:SetText(specID > 0 and tostring(specID) or "N/A")

        local color = common.get_class_or_spec_color()
        if color then color_swatch:SetColorTexture(color[1], color[2], color[3]) end

        if common.get_primary_resource then
            primary_power_value:SetText(get_power_type_name(common.get_primary_resource()))
        end
        if common.get_secondary_resource then
            secondary_power_value:SetText(get_power_type_name(common.get_secondary_resource()))
        end

        if sfui.reminders and sfui.reminders.get_status then
            pet_warning_value:SetText(sfui.reminders.get_status())
        else
            pet_warning_value:SetText("N/A (Module Missing)")
        end

        local hammer = sfui.hammer or sfui.automation
        if hammer and hammer.has_repair_hammer then
            local found, name, _, itemID = hammer.has_repair_hammer(true)
            if found then
                hammer_value:SetText("|cff00ff00Found|r (" .. (name or "Unknown") .. ")")
                hammer_id_value:SetText(tostring(itemID))
            else
                hammer_value:SetText("|cffff0000Not Found|r")
                hammer_id_value:SetText("None")
            end
        else
            hammer_value:SetText("N/A")
            hammer_id_value:SetText("N/A")
        end

        local formID = (GetShapeshiftFormID and GetShapeshiftFormID()) or (GetShapeshiftForm and GetShapeshiftForm()) or 0
        local isStealthed = (IsStealthed and IsStealthed()) or false
        form_id_value:SetText(tostring(formID) .. (isStealthed and " |cff00ffff(Stealthed)|r" or ""))
    end

    debug_refresh_button:SetScript("OnClick", update_debug_info)

    -- Hook into the debug tab's OnClick to refresh info when selected
    local original_on_click_debug = debug_tab_button:GetScript("OnClick")
    debug_tab_button:SetScript("OnClick", function(self)
        original_on_click_debug(self) -- Call original select_tab logic
        update_debug_info()
    end)

    update_debug_info()
end

function sfui.toggle_options_panel()
    if not frame then sfui.create_options_panel() end

    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        if not frame.selected_tab then select_tab(frame.tabs[1].button) end
    end
end
