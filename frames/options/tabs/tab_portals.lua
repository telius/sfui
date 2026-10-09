local addonName, addon = ...
sfui = sfui or {}
sfui.options = sfui.options or {}

local g = sfui.config
local common = sfui.common
local _G = _G

sfui.options.RegisterTab({
    id = "portals",
    name = "portals",
    build = function(p, tab_button, options_frame)
        local CreateFlatButton = common.create_flat_button
        local white = sfui.config.colors.white

        local isRetail = sfui.isRetail

        -- ── Header ──────────────────────────────────────────────────────────
        local main_header = p:CreateFontString(nil, "OVERLAY", g.font_large)
        main_header:SetPoint("TOPLEFT", 15, -15)
        main_header:SetTextColor(white[1], white[2], white[3])
        main_header:SetText("portals & teleports")

        local main_desc = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
        main_desc:SetPoint("TOPLEFT", main_header, "BOTTOMLEFT", 0, -4)
        main_desc:SetTextColor(0.7, 0.7, 0.7)
        if isRetail then
            main_desc:SetText("quick-access travel hub for hearthstones, toys, dungeon portals, and class teleports.")
        else
            main_desc:SetText("quick-access travel hub for hearthstones, class travel, engineering gadgets, and mage portals.")
        end

        -- ── Section 1: Dedicated Hardware Keybind ─────────────────────────────
        local keybind_header = p:CreateFontString(nil, "OVERLAY", g.font)
        keybind_header:SetPoint("TOPLEFT", main_desc, "BOTTOMLEFT", 0, -18)
        keybind_header:SetTextColor(0, 1, 1, 1)
        keybind_header:SetText("travel hub keybind")

        local keybind_desc = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
        keybind_desc:SetPoint("TOPLEFT", keybind_header, "BOTTOMLEFT", 0, -4)
        keybind_desc:SetTextColor(0.7, 0.7, 0.7)
        keybind_desc:SetText("dedicated hardware keybind to toggle the quick travel hub without consuming action bar slots.")

        local keybind_bullets = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
        keybind_bullets:SetPoint("TOPLEFT", keybind_desc, "BOTTOMLEFT", 0, -6)
        keybind_bullets:SetTextColor(0.6, 0.6, 0.6)
        if isRetail then
            keybind_bullets:SetText("• hearthstones & toys: covenant, dalaran, garrison, and seasonal hearthstones\n• dungeon & raid portals: active seasonal mythic+ teleports and raid shortcuts\n• class travel: mage portals, druid dreamwalk, death knight death gate\n• quick cast: left-click to cast teleport, right-click to cast party portal")
        else
            keybind_bullets:SetText("• hearthstone: instant cast with real-time inn bind location display\n• class travel: shaman astral recall and druid teleport: moonglade\n• engineering gadgets: dimensional ripper (everlook) and ultrasafe transporter (gadgetzan)\n• mage travel: left-click for self-teleport, right-click for group portal\n• reagent tracking: live bag counts for rune of teleportation and rune of portals")
        end

        local keybind_widget = common.create_keybind_input(
            p,
            "portals keybind:",
            function() return sfui.keybinds.GetPortalsKey() end,
            function(key) return sfui.keybinds.SetPortalsKey(key) end,
            function() return sfui.keybinds.UnbindPortalsKey() end,
            "portals keybind",
            "toggles the travel hub and portals window."
        )
        keybind_widget:SetPoint("TOPLEFT", keybind_bullets, "BOTTOMLEFT", 0, -10)

        local macro_hint = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
        macro_hint:SetPoint("TOPLEFT", keybind_widget, "BOTTOMLEFT", 0, -8)
        macro_hint:SetTextColor(0.5, 0.75, 0.85)
        macro_hint:SetText("slash commands: /portals, /sfportals, /sfui portals · macro: /click SfuiPortalsBtn")

        local portals_toggle_btn = CreateFlatButton(p, "toggle travel hub", 140, 22)
        portals_toggle_btn:SetPoint("TOPLEFT", macro_hint, "BOTTOMLEFT", 0, -14)
        portals_toggle_btn:SetScript("OnClick", function()
            if sfui.portals and sfui.portals.Toggle then
                sfui.portals.Toggle()
            end
        end)

        local portals_hint = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
        portals_hint:SetPoint("LEFT", portals_toggle_btn, "RIGHT", 10, 0)
        portals_hint:SetTextColor(0.65, 0.65, 0.65, 1)
        portals_hint:SetText("preview or toggle the travel window")

        p.customContentHeight = 330
    end,
})
