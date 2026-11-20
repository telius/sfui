local addonName, addon = ...
sfui = sfui or {}
sfui.options = sfui.options or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/options/tabs/tab_chat.lua
--  Options Tab: Lean Flat Chat Chrome, Tabs, Copy, Links, Fade & Movers
-- ══════════════════════════════════════════════════════════════════════════════

local g = sfui.config
local common = sfui.common
local _G = _G
local ipairs = _G.ipairs
local pairs = _G.pairs
local type = _G.type
local math_floor = math.floor

local refreshTabUI = nil
local chatPanelRef = nil

sfui.options.RegisterTab({
    id = "chat",
    name = "chat",
    icon = "Interface\\Icons\\Spell_Shadow_MindSteal",
    resetDefaults = function()
        local defs = sfui.chat and sfui.chat.DEFAULTS
        if defs and sfui.db and sfui.db.Set then
            for k, v in pairs(defs) do
                if type(v) == "table" then
                    local copy = {}
                    for sk, sv in pairs(v) do copy[sk] = sv end
                    sfui.db.Set("chat", k, copy)
                else
                    sfui.db.Set("chat", k, v)
                end
            end
            sfui.db.Set("chat", "position", nil)
        end
        if sfui.chat and sfui.chat.ResetChatPosition and not (_G.InCombatLockdown and _G.InCombatLockdown()) then
            sfui.chat.ResetChatPosition()
        elseif sfui.chat and sfui.chat.ScheduleRefresh then
            sfui.chat.ScheduleRefresh()
        end
        if refreshTabUI then
            refreshTabUI()
        end
    end,
    onShow = function()
        if refreshTabUI then
            refreshTabUI()
        end
    end,
    build = function(panel)
        chatPanelRef = panel
        local CreateFlatButton = common.create_flat_button
        local create_checkbox = common.create_checkbox
        local create_slider_input = common.create_slider_input
        local create_dropdown = common.create_dropdown
        local white = (sfui.config and sfui.config.colors and sfui.config.colors.white) or { 1, 1, 1 }
        local fontMain = (g and g.font) or "GameFontNormal"
        local fontSmall = (g and g.font_small) or "GameFontHighlightSmall"

        local allCheckboxes = {}
        local allSliders = {}

        local function reg_cb(cb)
            allCheckboxes[#allCheckboxes + 1] = cb
            return cb
        end

        local function reg_slider(s)
            allSliders[#allSliders + 1] = s
            return s
        end

        local function get_chat(key, fallback)
            if sfui.db and sfui.db.Get then
                return sfui.db.Get("chat", key, fallback)
            end
            return fallback
        end

        local function set_chat(key, val)
            if sfui.db and sfui.db.Set then
                sfui.db.Set("chat", key, val)
            end
        end

        -- ─────────────────────────────────────────────────────────────────────
        -- Header & Quick Action Controls
        -- ─────────────────────────────────────────────────────────────────────
        local header = panel:CreateFontString(nil, "OVERLAY", (g and g.font_large) or fontMain)
        header:SetPoint("TOPLEFT", 15, -15)
        header:SetTextColor(white[1], white[2], white[3])
        header:SetText("chat settings")

        local desc = panel:CreateFontString(nil, "OVERLAY", fontSmall)
        desc:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
        desc:SetTextColor(0.72, 0.72, 0.74, 1)
        desc:SetText("flat, lean chat chrome with zero-taint ghost tabs, chat copy, url links, and movers support.")

        local enable_cb = reg_cb(create_checkbox(panel, "enable chat module", function()
            return sfui.IsModuleEnabled("chat")
        end, function(checked)
            if sfui.SetModuleEnabled then
                sfui.SetModuleEnabled("chat", checked)
            end
            if refreshTabUI then refreshTabUI() end
        end, "enables or disables the lean flat chat module at runtime."))
        enable_cb:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -10)

        local reset_pos_btn = CreateFlatButton(panel, "reset position", 110, 22)
        reset_pos_btn:SetPoint("TOPLEFT", enable_cb, "BOTTOMLEFT", 0, -10)
        reset_pos_btn:SetScript("OnClick", function()
            if sfui.chat and sfui.chat.ResetChatPosition then
                sfui.chat.ResetChatPosition()
            end
            if refreshTabUI then refreshTabUI() end
        end)

        local copy_now_btn = CreateFlatButton(panel, "copy chat", 90, 22)
        copy_now_btn:SetPoint("LEFT", reset_pos_btn, "RIGHT", 10, 0)
        copy_now_btn:SetScript("OnClick", function()
            if sfui.chat and sfui.chat.OpenCopyWindow then
                sfui.chat.OpenCopyWindow()
            end
        end)

        -- ─────────────────────────────────────────────────────────────────────
        -- Column 1 (Left): Appearance & Typography
        -- ─────────────────────────────────────────────────────────────────────
        local COL_OFFSET_X = 270
        local SLIDER_W = 230

        local app_header = panel:CreateFontString(nil, "OVERLAY", fontMain)
        app_header:SetPoint("TOPLEFT", reset_pos_btn, "BOTTOMLEFT", 0, -18)
        app_header:SetTextColor(white[1], white[2], white[3])
        app_header:SetText("appearance")

        local theme_cb = reg_cb(create_checkbox(panel, "use sfui theme", function()
            return get_chat("use_theme", true) == true
        end, function(checked)
            set_chat("use_theme", checked and true or false)
        end, "sync chat colors and chrome with the active sfui theme. enabled by default."))
        theme_cb:SetPoint("TOPLEFT", app_header, "BOTTOMLEFT", 0, -10)

        local tabs_cb = reg_cb(create_checkbox(panel, "flat ghost tabs", function()
            return get_chat("ghost_tabs", true) == true
        end, function(checked)
            set_chat("ghost_tabs", checked and true or false)
        end, "renders crisp flat tabs over blizzard tabs while preserving click, drag, and right-click menus."))
        tabs_cb:SetPoint("TOPLEFT", theme_cb, "BOTTOMLEFT", 0, -8)

        local sb_cb = reg_cb(create_checkbox(panel, "slim scrollbar", function()
            return get_chat("custom_scrollbar", true) == true
        end, function(checked)
            set_chat("custom_scrollbar", checked and true or false)
        end, "replaces blizzard's chunky scrollbar with a minimal 3px thumb that appears only when scrolled up."))
        sb_cb:SetPoint("TOPLEFT", tabs_cb, "BOTTOMLEFT", 0, -8)

        local bg_alpha_slider = reg_slider(create_slider_input(panel, "backdrop opacity (%):", function()
            return math_floor((get_chat("bg_alpha", 0.0) * 100) + 0.5)
        end, 0, 100, 5, function(val)
            set_chat("bg_alpha", val / 100)
        end, "opacity of the chat backdrop.", SLIDER_W))
        bg_alpha_slider:SetPoint("TOPLEFT", sb_cb, "BOTTOMLEFT", 0, -14)

        local bd_alpha_slider = reg_slider(create_slider_input(panel, "border opacity (%):", function()
            return math_floor((get_chat("border_alpha", 0.0) * 100) + 0.5)
        end, 0, 100, 5, function(val)
            set_chat("border_alpha", val / 100)
        end, "opacity of the chat panel border.", SLIDER_W))
        bd_alpha_slider:SetPoint("TOPLEFT", bg_alpha_slider, "BOTTOMLEFT", 0, -10)

        local eb_label = panel:CreateFontString(nil, "OVERLAY", fontMain)
        eb_label:SetPoint("TOPLEFT", bd_alpha_slider, "BOTTOMLEFT", 0, -12)
        eb_label:SetTextColor(white[1], white[2], white[3])
        eb_label:SetText("editbox position:")

        local eb_options = {
            { text = "bottom", value = "bottom" },
            { text = "top",    value = "top" },
        }
        local eb_dropdown = create_dropdown(panel, 180, eb_options, function(val)
            set_chat("editbox_pos", val)
        end, get_chat("editbox_pos", "bottom"), nil, 180)
        eb_dropdown:SetPoint("TOPLEFT", eb_label, "BOTTOMLEFT", 0, -6)

        local typo_header = panel:CreateFontString(nil, "OVERLAY", fontMain)
        typo_header:SetPoint("TOPLEFT", eb_dropdown, "BOTTOMLEFT", 0, -16)
        typo_header:SetTextColor(white[1], white[2], white[3])
        typo_header:SetText("typography")

        local font_cb = reg_cb(create_checkbox(panel, "override chat font", function()
            return get_chat("font_override", false) == true
        end, function(checked)
            set_chat("font_override", checked and true or false)
        end, "applies sfui font, size, and outline to chat frames. off by default to preserve native fonts."))
        font_cb:SetPoint("TOPLEFT", typo_header, "BOTTOMLEFT", 0, -10)

        local font_size_slider = reg_slider(create_slider_input(panel, "font size:", function()
            return get_chat("font_size", 13)
        end, 9, 24, 1, function(val)
            set_chat("font_size", val)
        end, "chat text size when font override is enabled.", SLIDER_W))
        font_size_slider:SetPoint("TOPLEFT", font_cb, "BOTTOMLEFT", 0, -12)

        local outline_label = panel:CreateFontString(nil, "OVERLAY", fontMain)
        outline_label:SetPoint("TOPLEFT", font_size_slider, "BOTTOMLEFT", 0, -10)
        outline_label:SetTextColor(white[1], white[2], white[3])
        outline_label:SetText("font outline:")

        local outline_options = {
            { text = "none",          value = "" },
            { text = "outline",       value = "OUTLINE" },
            { text = "thick outline", value = "THICKOUTLINE" },
            { text = "monochrome",    value = "MONOCHROMEOUTLINE" },
        }
        local outline_dropdown = create_dropdown(panel, 180, outline_options, function(val)
            set_chat("font_outline", val)
        end, get_chat("font_outline", "OUTLINE"), nil, 180)
        outline_dropdown:SetPoint("TOPLEFT", outline_label, "BOTTOMLEFT", 0, -6)

        -- ─────────────────────────────────────────────────────────────────────
        -- Column 2 (Right): Size, Copy/Links & Idle Fade
        -- ─────────────────────────────────────────────────────────────────────
        local size_header = panel:CreateFontString(nil, "OVERLAY", fontMain)
        size_header:SetPoint("TOPLEFT", app_header, "TOPLEFT", COL_OFFSET_X, 0)
        size_header:SetTextColor(white[1], white[2], white[3])
        size_header:SetText("layout & size")

        local width_slider = reg_slider(create_slider_input(panel, "custom width (0 = default):", function()
            return get_chat("width", 0)
        end, 0, 800, 10, function(val)
            set_chat("width", val)
        end, "panel width in pixels (0 keeps blizzard edit mode size).", SLIDER_W))
        width_slider:SetPoint("TOPLEFT", size_header, "BOTTOMLEFT", 0, -10)

        local height_slider = reg_slider(create_slider_input(panel, "custom height (0 = default):", function()
            return get_chat("height", 0)
        end, 0, 500, 10, function(val)
            set_chat("height", val)
        end, "panel height in pixels (0 keeps blizzard edit mode size).", SLIDER_W))
        height_slider:SetPoint("TOPLEFT", width_slider, "BOTTOMLEFT", 0, -10)

        local copy_header = panel:CreateFontString(nil, "OVERLAY", fontMain)
        copy_header:SetPoint("TOPLEFT", height_slider, "BOTTOMLEFT", 0, -16)
        copy_header:SetTextColor(white[1], white[2], white[3])
        copy_header:SetText("copy, links & fade")

        local copy_btn_label = panel:CreateFontString(nil, "OVERLAY", fontMain)
        copy_btn_label:SetPoint("TOPLEFT", copy_header, "BOTTOMLEFT", 0, -10)
        copy_btn_label:SetTextColor(white[1], white[2], white[3])
        copy_btn_label:SetText("copy button:")

        local copy_btn_options = {
            { text = "on hover", value = "hover" },
            { text = "always",   value = "always" },
            { text = "hidden",   value = "hidden" },
        }
        local copy_btn_dropdown = create_dropdown(panel, 180, copy_btn_options, function(val)
            set_chat("copy_button", val)
        end, get_chat("copy_button", "hover"), nil, 180)
        copy_btn_dropdown:SetPoint("TOPLEFT", copy_btn_label, "BOTTOMLEFT", 0, -6)

        local url_cb = reg_cb(create_checkbox(panel, "clickable url links", function()
            return get_chat("url_links", true) == true
        end, function(checked)
            set_chat("url_links", checked and true or false)
        end, "turns web links in chat into clickable copy links."))
        url_cb:SetPoint("TOPLEFT", copy_btn_dropdown, "BOTTOMLEFT", 0, -12)

        local hover_cb = reg_cb(create_checkbox(panel, "hyperlink hover tooltips", function()
            return get_chat("hover_tooltips", true) == true
        end, function(checked)
            set_chat("hover_tooltips", checked and true or false)
        end, "shows tooltips when hovering item, spell, quest, and achievement links."))
        hover_cb:SetPoint("TOPLEFT", url_cb, "BOTTOMLEFT", 0, -8)

        local fade_cb = reg_cb(create_checkbox(panel, "idle chrome fade", function()
            return get_chat("idle_fade", false) == true
        end, function(checked)
            set_chat("idle_fade", checked and true or false)
        end, "gently fades chat backdrop and tabs after inactivity, waking on hover or typing."))
        fade_cb:SetPoint("TOPLEFT", hover_cb, "BOTTOMLEFT", 0, -8)

        local fade_delay_slider = reg_slider(create_slider_input(panel, "fade delay (s):", function()
            return get_chat("idle_fade_delay", 15)
        end, 5, 60, 1, function(val)
            set_chat("idle_fade_delay", val)
        end, "seconds before idle chrome fades.", SLIDER_W))
        fade_delay_slider:SetPoint("TOPLEFT", fade_cb, "BOTTOMLEFT", 0, -12)

        local fade_alpha_slider = reg_slider(create_slider_input(panel, "faded opacity (%):", function()
            return math_floor((get_chat("idle_fade_alpha", 0.0) * 100) + 0.5)
        end, 0, 50, 5, function(val)
            set_chat("idle_fade_alpha", val / 100)
        end, "chrome opacity while faded.", SLIDER_W))
        fade_alpha_slider:SetPoint("TOPLEFT", fade_delay_slider, "BOTTOMLEFT", 0, -10)

        refreshTabUI = function()
            for _, cb in ipairs(allCheckboxes) do
                if cb.update then cb:update() end
            end
            for _, s in ipairs(allSliders) do
                if s.update then s:update() end
            end
            if eb_dropdown and eb_dropdown.SetSelectedValue then
                eb_dropdown:SetSelectedValue(get_chat("editbox_pos", "bottom"))
            end
            if outline_dropdown and outline_dropdown.SetSelectedValue then
                outline_dropdown:SetSelectedValue(get_chat("font_outline", "OUTLINE"))
            end
            if copy_btn_dropdown and copy_btn_dropdown.SetSelectedValue then
                copy_btn_dropdown:SetSelectedValue(get_chat("copy_button", "hover"))
            end
        end

        if panel.SetContentHeight then
            panel:SetContentHeight(590)
        else
            panel.customContentHeight = 590
        end
    end,
})

if sfui.events and sfui.events.RegisterMessage then
    sfui.events.RegisterMessage("SFUI_SETTING_CHANGED", function(_, moduleName)
        if moduleName == "chat" and refreshTabUI and chatPanelRef and chatPanelRef:IsShown() then
            refreshTabUI()
        end
    end)
    sfui.events.RegisterMessage("SFUI_MODULE_STATE_CHANGED", function(_, moduleName)
        if moduleName == "chat" and refreshTabUI and chatPanelRef and chatPanelRef:IsShown() then
            refreshTabUI()
        end
    end)
end
