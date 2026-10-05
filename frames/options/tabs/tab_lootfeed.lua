sfui = sfui or {}
sfui.options = sfui.options or {}

local g = sfui.config
local common = sfui.common
local _G = _G
local type, pairs, ipairs, pcall = _G.type, _G.pairs, _G.ipairs, _G.pcall

local refreshTabUI = nil

sfui.options.RegisterTab({
    id = "lootfeed",
    name = "loot feed",
    resetDefaults = function()
        if SfuiDB then
            SfuiDB.camelotLootfeedStyle = nil
            if SfuiDB.lootfeed then
                local defaults = sfui.config.lootfeed or {}
                for k, v in pairs(defaults) do
                    if type(v) == "table" then
                        SfuiDB.lootfeed[k] = {}
                        for subK, subV in pairs(v) do SfuiDB.lootfeed[k][subK] = subV end
                    else
                        SfuiDB.lootfeed[k] = v
                    end
                end
                sfui.lootfeed:OnSettingsChanged()
            end
            sfui.lootfeed.UpdateTheme()
            if refreshTabUI then
                refreshTabUI()
            end
        end
    end,
    onShow = function()
        if refreshTabUI then
            refreshTabUI()
        end
    end,
    build = function(feed_panel)
        local CreateFlatButton = common.create_flat_button
        local create_checkbox = common.create_checkbox
        local create_slider_input = common.create_slider_input
        local white = sfui.config.colors.white

        local function GetDB()
            SfuiDB.lootfeed = SfuiDB.lootfeed or {}
            return SfuiDB.lootfeed
        end

        local allCheckboxes = {}
        local allSliders = {}

        local function registerCheckbox(cb)
            allCheckboxes[#allCheckboxes + 1] = cb
            return cb
        end

        local function registerSlider(s)
            allSliders[#allSliders + 1] = s
            return s
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
            sfui.lootfeed.TriggerTestFeed()
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

        -- Forward declarations for dependency linking
        local UpdatePartyQualityState
        local UpdateCamelotStyleControls

        -- Camelot Theme Style (Only shown when playing Camelot)
        local camelot_label = feed_panel:CreateFontString(nil, "OVERLAY", g.font_small or "GameFontHighlightSmall")
        camelot_label:SetPoint("TOPLEFT", test_btn, "BOTTOMLEFT", 0, -12)
        camelot_label:SetTextColor(white[1], white[2], white[3])
        camelot_label:SetText("camelot theme style:")

        local lootfeedStyleButtons = {}

        local btnOptionA = CreateFlatButton(feed_panel, "Architectural Slate", 150, 22)
        btnOptionA:SetPoint("TOPLEFT", camelot_label, "BOTTOMLEFT", 0, -6)
        btnOptionA.styleKey = "architectural"
        btnOptionA.baseLabel = "Architectural Slate"
        lootfeedStyleButtons[#lootfeedStyleButtons + 1] = btnOptionA

        local btnOptionB = CreateFlatButton(feed_panel, "Sculpted Card", 120, 22)
        btnOptionB:SetPoint("LEFT", btnOptionA, "RIGHT", 8, 0)
        btnOptionB.styleKey = "outfit_card"
        btnOptionB.baseLabel = "Sculpted Card"
        lootfeedStyleButtons[#lootfeedStyleButtons + 1] = btnOptionB

        for _, btn in ipairs(lootfeedStyleButtons) do
            btn:SetScript("OnClick", function()
                SfuiDB.camelotLootfeedStyle = btn.styleKey
                sfui.lootfeed.UpdateTheme()
                if UpdateCamelotStyleControls then
                    UpdateCamelotStyleControls()
                end
                local name = (btn.styleKey == "architectural") and "architectural slate" or "sculpted card"
                sfui.common.print("camelot loot feed style set to '" .. name .. "'.")
            end)
        end

        -- ─────────────────────────────────────────────────────────────────────
        -- Column 1: General & Tracking Toggles (Left Column)
        -- ─────────────────────────────────────────────────────────────────────
        local toggles_header = feed_panel:CreateFontString(nil, "OVERLAY", g.font)
        toggles_header:SetPoint("TOPLEFT", test_btn, "BOTTOMLEFT", 0, -18)
        toggles_header:SetTextColor(white[1], white[2], white[3])
        toggles_header:SetText("general & tracking toggles")

        UpdateCamelotStyleControls = function()
            local isCamelot = sfui.theme and sfui.theme.IsCamelotActive and sfui.theme.IsCamelotActive()
            if isCamelot then
                camelot_label:Show()
                btnOptionA:Show()
                btnOptionB:Show()
                toggles_header:ClearAllPoints()
                toggles_header:SetPoint("TOPLEFT", btnOptionA, "BOTTOMLEFT", 0, -18)

                local curStyle = (SfuiDB and (SfuiDB.camelotLootfeedStyle or (SfuiDB.theme and SfuiDB.theme.lootfeedStyle)))
                    or (sfui.config and sfui.config.theme and sfui.config.theme.lootfeedStyle)
                    or "architectural"

                local pal = (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette())
                local hexAccent = "ffcc00"
                if pal and pal.accentColor then
                    hexAccent = string.format("%02x%02x%02x",
                        math.floor(pal.accentColor[1] * 255),
                        math.floor(pal.accentColor[2] * 255),
                        math.floor(pal.accentColor[3] * 255)
                    )
                end

                for _, btn in ipairs(lootfeedStyleButtons) do
                    local isSelected = (btn.styleKey == curStyle)
                    local fs = btn:GetFontString()
                    if btn.SetBackdrop then
                        btn:SetBackdrop({
                            bgFile   = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
                            edgeFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
                            edgeSize = 1,
                            insets   = { left = 0, right = 0, top = 0, bottom = 0 }
                        })
                        if isSelected then
                            btn:SetBackdropColor(0.24, 0.18, 0.10, 0.98)
                            if pal and pal.accentColor then
                                btn:SetBackdropBorderColor(pal.accentColor[1], pal.accentColor[2], pal.accentColor[3], 1)
                            else
                                btn:SetBackdropBorderColor(0.85, 0.70, 0.35, 1)
                            end
                        else
                            btn:SetBackdropColor(0.09, 0.08, 0.06, 0.90)
                            btn:SetBackdropBorderColor(0.22, 0.18, 0.12, 0.8)
                        end
                    end
                    if fs then
                        if isSelected then
                            fs:SetText("|cff" .. hexAccent .. "•|r " .. btn.baseLabel)
                            fs:SetTextColor(1, 1, 1, 1)
                        else
                            fs:SetText(btn.baseLabel)
                            fs:SetTextColor(0.85, 0.85, 0.85, 1)
                        end
                    end
                end

                if feed_panel.SetContentHeight then
                    feed_panel:SetContentHeight(610)
                end
            else
                camelot_label:Hide()
                btnOptionA:Hide()
                btnOptionB:Hide()
                toggles_header:ClearAllPoints()
                toggles_header:SetPoint("TOPLEFT", test_btn, "BOTTOMLEFT", 0, -18)

                if feed_panel.SetContentHeight then
                    feed_panel:SetContentHeight(560)
                end
            end
        end

        local enable_cb = registerCheckbox(create_checkbox(feed_panel, "enable loot feed", function()
            local db = GetDB()
            return db.enabled ~= false
        end, function(checked)
            local db = GetDB()
            db.enabled = checked
            if checked then
                sfui.lootfeed:OnEnable()
            else
                sfui.lootfeed:OnDisable()
            end
            if UpdatePartyQualityState then UpdatePartyQualityState() end
        end, "enable or disable the loot feed completely."))
        enable_cb:SetPoint("TOPLEFT", toggles_header, "BOTTOMLEFT", 0, -10)

        local grow_down_cb = registerCheckbox(create_checkbox(feed_panel, "grow downwards (rows stack down from top)", function()
            local db = GetDB()
            return db.growDirection ~= "UP"
        end, function(checked)
            local db = GetDB()
            db.growDirection = checked and "DOWN" or "UP"
            sfui.lootfeed:OnSettingsChanged("growDirection", db.growDirection)
        end, "when checked, new rows stack downwards with pending count on top. when unchecked, rows grow upwards."))
        grow_down_cb:SetPoint("TOPLEFT", enable_cb, "BOTTOMLEFT", 0, -8)

        local party_cb = registerCheckbox(create_checkbox(feed_panel, "track party member loot", function()
            local db = GetDB()
            return db.trackPartyLoot ~= false
        end, function(checked)
            local db = GetDB()
            db.trackPartyLoot = checked
            if UpdatePartyQualityState then UpdatePartyQualityState() end
        end, "shows items looted by party members with their portrait indicator."))
        party_cb:SetPoint("TOPLEFT", grow_down_cb, "BOTTOMLEFT", 0, -8)

        local money_cb = registerCheckbox(create_checkbox(feed_panel, "track gold & money gains", function()
            local db = GetDB()
            return db.trackMoney ~= false
        end, function(checked)
            local db = GetDB()
            db.trackMoney = checked
        end, "shows money earned with gained coins and total gold."))
        money_cb:SetPoint("TOPLEFT", party_cb, "BOTTOMLEFT", 0, -8)

        local curr_cb = registerCheckbox(create_checkbox(feed_panel, "track currencies", function()
            local db = GetDB()
            return db.trackCurrency ~= false
        end, function(checked)
            local db = GetDB()
            db.trackCurrency = checked
        end, "shows currency gains (valorstones, crests, badges) with delta and total."))
        curr_cb:SetPoint("TOPLEFT", money_cb, "BOTTOMLEFT", 0, -8)

        local xp_cb = registerCheckbox(create_checkbox(feed_panel, "track experience (xp)", function()
            local db = GetDB()
            return db.trackXP ~= false
        end, function(checked)
            local db = GetDB()
            db.trackXP = checked
        end, "shows experience gained and current level progress %."))
        xp_cb:SetPoint("TOPLEFT", curr_cb, "BOTTOMLEFT", 0, -8)

        local rep_cb = registerCheckbox(create_checkbox(feed_panel, "track reputation", function()
            local db = GetDB()
            return db.trackReputation ~= false
        end, function(checked)
            local db = GetDB()
            db.trackReputation = checked
        end, "shows reputation gains with factions."))
        rep_cb:SetPoint("TOPLEFT", xp_cb, "BOTTOMLEFT", 0, -8)

        local skill_cb = registerCheckbox(create_checkbox(feed_panel, "track skills & profession skillups", function()
            local db = GetDB()
            return db.trackSkills ~= false
        end, function(checked)
            local db = GetDB()
            db.trackSkills = checked
        end, "shows skill increases for professions, secondary skills, and weapon skills."))
        skill_cb:SetPoint("TOPLEFT", rep_cb, "BOTTOMLEFT", 0, -8)

        local vendor_cb = registerCheckbox(create_checkbox(feed_panel, "show vendor price on goods & junk", function()
            local db = GetDB()
            return db.showSellPrice ~= false
        end, function(checked)
            local db = GetDB()
            db.showSellPrice = checked
        end, "displays vendor sell value on non-gear items."))
        vendor_cb:SetPoint("TOPLEFT", skill_cb, "BOTTOMLEFT", 0, -8)

        -- ─────────────────────────────────────────────────────────────────────
        -- Column 2: Display & Sizing Sliders (Right Column)
        -- ─────────────────────────────────────────────────────────────────────
        local sliders_header = feed_panel:CreateFontString(nil, "OVERLAY", g.font)
        sliders_header:SetPoint("TOPLEFT", toggles_header, "TOPLEFT", 280, 0)
        sliders_header:SetTextColor(white[1], white[2], white[3])
        sliders_header:SetText("display & sizing limits")

        local max_rows_slider = registerSlider(create_slider_input(feed_panel, "maximum visible rows", function()
            local db = GetDB()
            return db.maxRows or 10
        end, 3, 16, 1, function(val)
            local db = GetDB()
            db.maxRows = val
            sfui.lootfeed:OnSettingsChanged("maxRows", val)
        end, "maximum number of loot rows shown at one time. additional items queue up.", 250))
        max_rows_slider:SetPoint("TOPLEFT", sliders_header, "BOTTOMLEFT", 0, -10)

        local duration_slider = registerSlider(create_slider_input(feed_panel, "display duration (seconds)", function()
            local db = GetDB()
            return db.displayDuration or 8.0
        end, 2.0, 20.0, 0.5, function(val)
            local db = GetDB()
            db.displayDuration = val
            sfui.lootfeed:OnSettingsChanged("displayDuration", val)
        end, "seconds each loot row stays visible on screen before fading out.", 250))
        duration_slider:SetPoint("TOPLEFT", max_rows_slider, "BOTTOMLEFT", 0, -12)

        local width_slider = registerSlider(create_slider_input(feed_panel, "feed width (pixels)", function()
            local db = GetDB()
            return db.width or 320
        end, 240, 500, 10, function(val)
            local db = GetDB()
            db.width = val
            sfui.lootfeed:OnSettingsChanged("width", val)
        end, "width of each loot feed row in pixels.", 250))
        width_slider:SetPoint("TOPLEFT", duration_slider, "BOTTOMLEFT", 0, -12)

        local height_slider = registerSlider(create_slider_input(feed_panel, "row height (pixels)", function()
            local db = GetDB()
            return db.rowHeight or 34
        end, 20, 60, 2, function(val)
            local db = GetDB()
            db.rowHeight = val
            sfui.lootfeed:OnSettingsChanged("rowHeight", val)
        end, "height of each loot row in pixels.", 250))
        height_slider:SetPoint("TOPLEFT", width_slider, "BOTTOMLEFT", 0, -12)

        local quality_slider = registerSlider(create_slider_input(feed_panel, "player minimum item quality (0-4)", function()
                local db = GetDB()
                return db.minItemQuality or 0
            end, 0, 4, 1, function(val)
                local db = GetDB()
                db.minItemQuality = val
                sfui.lootfeed:OnSettingsChanged("minItemQuality", val)
            end,
            "filter out items looted by yourself below this quality:\n0 = poor (gray)\n1 = common (white)\n2 = uncommon (green)\n3 = rare (blue)\n4 = epic (purple)",
            250))
        quality_slider:SetPoint("TOPLEFT", height_slider, "BOTTOMLEFT", 0, -12)

        local party_quality_slider = registerSlider(create_slider_input(feed_panel, "party minimum item quality (0-4)", function()
                local db = GetDB()
                return db.partyMinItemQuality or 2
            end, 0, 4, 1, function(val)
                local db = GetDB()
                db.partyMinItemQuality = val
                sfui.lootfeed:OnSettingsChanged("partyMinItemQuality", val)
            end,
            "filter out items looted by party members below this quality:\n0 = poor (gray)\n1 = common (white)\n2 = uncommon (green)\n3 = rare (blue)\n4 = epic (purple)",
            250))
        party_quality_slider:SetPoint("TOPLEFT", quality_slider, "BOTTOMLEFT", 0, -12)

        UpdatePartyQualityState = function()
            local db = GetDB()
            local enabled = (db.enabled ~= false) and (db.trackPartyLoot ~= false)
            local alpha = enabled and 1.0 or 0.35
            party_quality_slider:SetAlpha(alpha)
            if party_quality_slider.EnableMouse then party_quality_slider:EnableMouse(enabled) end
            if party_quality_slider.slider and party_quality_slider.slider.EnableMouse then
                party_quality_slider.slider:EnableMouse(enabled)
            end
            if party_quality_slider.editbox and party_quality_slider.editbox.EnableMouse then
                party_quality_slider.editbox:EnableMouse(enabled)
            end
        end

        refreshTabUI = function()
            for _, cb in ipairs(allCheckboxes) do
                local onShow = cb:GetScript("OnShow")
                if onShow then pcall(onShow, cb) end
            end
            for _, sl in ipairs(allSliders) do
                if sl.slider then
                    local onShow = sl.slider:GetScript("OnShow")
                    if onShow then pcall(onShow, sl.slider) end
                end
            end
            UpdatePartyQualityState()
            if UpdateCamelotStyleControls then
                UpdateCamelotStyleControls()
            end
        end

        -- Initial dependency sync
        UpdatePartyQualityState()
        if UpdateCamelotStyleControls then
            UpdateCamelotStyleControls()
        end

        -- Auto-refresh if theme changes dynamically while lootfeed panel is open
        sfui.events.RegisterMessage("SFUI_THEME_CHANGED", function()
            if feed_panel:IsVisible() and UpdateCamelotStyleControls then
                UpdateCamelotStyleControls()
            end
        end)

        if feed_panel.SetContentHeight then
            feed_panel:SetContentHeight(560)
        end
    end,
})
