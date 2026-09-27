local addonName, addon = ...
sfui = sfui or {}
sfui.options = sfui.options or {}

local g = sfui.config
local common = sfui.common
local _G = _G
local type, pairs = type, pairs

sfui.options.RegisterTab({
    id = "lootfeed",
    name = "loot feed",
    resetDefaults = function()
        if SfuiDB and SfuiDB.lootfeed then
            local defaults = sfui.config.lootfeed or {}
            for k, v in pairs(defaults) do
                if type(v) == "table" then
                    SfuiDB.lootfeed[k] = {}
                    for subK, subV in pairs(v) do SfuiDB.lootfeed[k][subK] = subV end
                else
                    SfuiDB.lootfeed[k] = v
                end
            end
            if sfui.lootfeed and sfui.lootfeed.OnSettingsChanged then
                sfui.lootfeed:OnSettingsChanged()
            end
        end
    end,
    build = function(feed_panel, tab_button, options_frame)
        local CreateFlatButton = common.create_flat_button
        local create_checkbox = common.create_checkbox
        local create_slider_input = common.create_slider_input
        local white = sfui.config.colors.white

        local function GetDB()
            SfuiDB.lootfeed = SfuiDB.lootfeed or {}
            return SfuiDB.lootfeed
        end

        -- Header & Description
        local header = feed_panel:CreateFontString(nil, "OVERLAY", g.font_large or g.font)
        header:SetPoint("TOPLEFT", 15, -15)
        header:SetTextColor(white[1], white[2], white[3])
        header:SetText("loot & reward feed")

        local info = feed_panel:CreateFontString(nil, "OVERLAY", g.font)
        info:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
        info:SetPoint("RIGHT", -15, 0)
        info:SetJustifyH("LEFT")
        info:SetTextColor(0.85, 0.85, 0.85, 1)
        info:SetText(
            "streamlined, lightweight feed for items, currencies, gold, xp, reputation, and skills. mass rewards automatically buffer in a pending queue."
        )

        -- Quick Controls / Shortcuts Guide
        local tips = feed_panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tips:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -8)
        tips:SetPoint("RIGHT", -15, 0)
        tips:SetJustifyH("LEFT")
        tips:SetText(
            "|cff00ffffhover|r: pause fade timer & show tooltip (|cff00ff00shift|r compares gear)  •  |cff00ffffalt+drag|r: move feed\n" ..
            "|cff00ffffshift+click|r: link item to chat  •  |cff00ffffctrl+click|r: preview in dressing room  •  |cff00ffffright-click|r: dismiss row"
        )

        -- Action Buttons
        local test_btn = CreateFlatButton(feed_panel, "trigger test feed (10 items)", 180, 22)
        test_btn:SetPoint("TOPLEFT", tips, "BOTTOMLEFT", 0, -12)
        test_btn:SetScript("OnClick", function()
            if sfui.lootfeed and sfui.lootfeed.TriggerTestFeed then
                sfui.lootfeed.TriggerTestFeed()
            end
        end)

        local reset_pos_btn = CreateFlatButton(feed_panel, "reset feed position", 140, 22)
        reset_pos_btn:SetPoint("LEFT", test_btn, "RIGHT", 10, 0)
        reset_pos_btn:SetScript("OnClick", function()
            local db = GetDB()
            local defaults = (sfui.config.lootfeed and sfui.config.lootfeed.pos) or
                { point = "TOPRIGHT", relativePoint = "TOPRIGHT", x = -320, y = -200 }
            db.pos = db.pos or {}
            db.pos.point = defaults.point
            db.pos.relativePoint = defaults.relativePoint
            db.pos.x = defaults.x
            db.pos.y = defaults.y
            local container = _G["sfui_lootfeed_container"]
            if container then
                container:ClearAllPoints()
                container:SetPoint(defaults.point, _G.UIParent, defaults.relativePoint, defaults.x, defaults.y)
            end
        end)

        -- ─────────────────────────────────────────────────────────────────────
        -- Column 1: General & Tracking Toggles (Left Column)
        -- ─────────────────────────────────────────────────────────────────────
        local toggles_header = feed_panel:CreateFontString(nil, "OVERLAY", g.font)
        toggles_header:SetPoint("TOPLEFT", test_btn, "BOTTOMLEFT", 0, -18)
        toggles_header:SetTextColor(white[1], white[2], white[3])
        toggles_header:SetText("general & tracking toggles")

        local enable_cb = create_checkbox(feed_panel, "enable loot feed", function()
            local db = GetDB()
            return db.enabled ~= false
        end, function(checked)
            local db = GetDB()
            db.enabled = checked
            if sfui.lootfeed then
                if checked and sfui.lootfeed.OnEnable then
                    sfui.lootfeed:OnEnable()
                elseif not checked and sfui.lootfeed.OnDisable then
                    sfui.lootfeed:OnDisable()
                end
            end
        end, "enable or disable the loot feed completely.")
        enable_cb:SetPoint("TOPLEFT", toggles_header, "BOTTOMLEFT", 0, -10)

        local grow_down_cb = create_checkbox(feed_panel, "grow downwards (rows stack down from top)", function()
            local db = GetDB()
            return db.growDirection ~= "UP"
        end, function(checked)
            local db = GetDB()
            db.growDirection = checked and "DOWN" or "UP"
            if sfui.lootfeed and sfui.lootfeed.OnSettingsChanged then
                sfui.lootfeed:OnSettingsChanged("growDirection", db.growDirection)
            end
        end, "when checked, new rows stack downwards with pending count on top. when unchecked, rows grow upwards.")
        grow_down_cb:SetPoint("TOPLEFT", enable_cb, "BOTTOMLEFT", 0, -8)

        local party_cb = create_checkbox(feed_panel, "track party member loot", function()
            local db = GetDB()
            return db.trackPartyLoot ~= false
        end, function(checked)
            local db = GetDB()
            db.trackPartyLoot = checked
        end, "shows items looted by party members with their portrait indicator.")
        party_cb:SetPoint("TOPLEFT", grow_down_cb, "BOTTOMLEFT", 0, -8)

        local money_cb = create_checkbox(feed_panel, "track gold & money gains", function()
            local db = GetDB()
            return db.trackMoney ~= false
        end, function(checked)
            local db = GetDB()
            db.trackMoney = checked
        end, "shows money earned with gained coins and total gold.")
        money_cb:SetPoint("TOPLEFT", party_cb, "BOTTOMLEFT", 0, -8)

        local curr_cb = create_checkbox(feed_panel, "track currencies", function()
            local db = GetDB()
            return db.trackCurrency ~= false
        end, function(checked)
            local db = GetDB()
            db.trackCurrency = checked
        end, "shows currency gains (valorstones, crests, badges) with delta and total.")
        curr_cb:SetPoint("TOPLEFT", money_cb, "BOTTOMLEFT", 0, -8)

        local xp_cb = create_checkbox(feed_panel, "track experience (xp)", function()
            local db = GetDB()
            return db.trackXP ~= false
        end, function(checked)
            local db = GetDB()
            db.trackXP = checked
        end, "shows experience gained and current level progress %.")
        xp_cb:SetPoint("TOPLEFT", curr_cb, "BOTTOMLEFT", 0, -8)

        local rep_cb = create_checkbox(feed_panel, "track reputation", function()
            local db = GetDB()
            return db.trackReputation ~= false
        end, function(checked)
            local db = GetDB()
            db.trackReputation = checked
        end, "shows reputation gains with factions.")
        rep_cb:SetPoint("TOPLEFT", xp_cb, "BOTTOMLEFT", 0, -8)

        local skill_cb = create_checkbox(feed_panel, "track skills & profession skillups", function()
            local db = GetDB()
            return db.trackSkills ~= false
        end, function(checked)
            local db = GetDB()
            db.trackSkills = checked
        end, "shows skill increases for professions, secondary skills, and weapon skills.")
        skill_cb:SetPoint("TOPLEFT", rep_cb, "BOTTOMLEFT", 0, -8)

        local vendor_cb = create_checkbox(feed_panel, "show vendor price on goods & junk", function()
            local db = GetDB()
            return db.showSellPrice ~= false
        end, function(checked)
            local db = GetDB()
            db.showSellPrice = checked
        end, "displays vendor sell value on non-gear items.")
        vendor_cb:SetPoint("TOPLEFT", skill_cb, "BOTTOMLEFT", 0, -8)

        -- ─────────────────────────────────────────────────────────────────────
        -- Column 2: Display & Sizing Sliders (Right Column)
        -- ─────────────────────────────────────────────────────────────────────
        local sliders_header = feed_panel:CreateFontString(nil, "OVERLAY", g.font)
        sliders_header:SetPoint("TOPLEFT", toggles_header, "TOPLEFT", 280, 0)
        sliders_header:SetTextColor(white[1], white[2], white[3])
        sliders_header:SetText("display & sizing limits")

        local max_rows_slider = create_slider_input(feed_panel, "maximum visible rows", function()
            local db = GetDB()
            return db.maxRows or 10
        end, 3, 16, 1, function(val)
            local db = GetDB()
            db.maxRows = val
            if sfui.lootfeed and sfui.lootfeed.OnSettingsChanged then
                sfui.lootfeed:OnSettingsChanged("maxRows", val)
            end
        end, "maximum number of loot rows shown at one time. additional items queue up.", 250)
        max_rows_slider:SetPoint("TOPLEFT", sliders_header, "BOTTOMLEFT", 0, -10)

        local duration_slider = create_slider_input(feed_panel, "display duration (seconds)", function()
            local db = GetDB()
            return db.displayDuration or 8.0
        end, 2.0, 20.0, 0.5, function(val)
            local db = GetDB()
            db.displayDuration = val
            if sfui.lootfeed and sfui.lootfeed.OnSettingsChanged then
                sfui.lootfeed:OnSettingsChanged("displayDuration", val)
            end
        end, "seconds each loot row stays visible on screen before fading out.", 250)
        duration_slider:SetPoint("TOPLEFT", max_rows_slider, "BOTTOMLEFT", 0, -12)

        local width_slider = create_slider_input(feed_panel, "feed width (pixels)", function()
            local db = GetDB()
            return db.width or 320
        end, 240, 500, 10, function(val)
            local db = GetDB()
            db.width = val
            if sfui.lootfeed and sfui.lootfeed.OnSettingsChanged then
                sfui.lootfeed:OnSettingsChanged("width", val)
            end
        end, "width of each loot feed row in pixels.", 250)
        width_slider:SetPoint("TOPLEFT", duration_slider, "BOTTOMLEFT", 0, -12)

        local height_slider = create_slider_input(feed_panel, "row height (pixels)", function()
            local db = GetDB()
            return db.rowHeight or 34
        end, 20, 60, 2, function(val)
            local db = GetDB()
            db.rowHeight = val
            if sfui.lootfeed and sfui.lootfeed.OnSettingsChanged then
                sfui.lootfeed:OnSettingsChanged("rowHeight", val)
            end
        end, "height of each loot row in pixels.", 250)
        height_slider:SetPoint("TOPLEFT", width_slider, "BOTTOMLEFT", 0, -12)

        local quality_slider = create_slider_input(feed_panel, "minimum item quality (0-4)", function()
                local db = GetDB()
                return db.minItemQuality or 0
            end, 0, 4, 1, function(val)
                local db = GetDB()
                db.minItemQuality = val
                if sfui.lootfeed and sfui.lootfeed.OnSettingsChanged then
                    sfui.lootfeed:OnSettingsChanged("minItemQuality", val)
                end
            end,
            "filter out items below this quality:\n0 = poor (gray)\n1 = common (white)\n2 = uncommon (green)\n3 = rare (blue)\n4 = epic (purple)",
            250)
        quality_slider:SetPoint("TOPLEFT", height_slider, "BOTTOMLEFT", 0, -12)

        if feed_panel.SetContentHeight then
            feed_panel:SetContentHeight(500)
        end
    end,
})
