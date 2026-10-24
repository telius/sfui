sfui = sfui or {}
sfui.options = sfui.options or {}

local g = sfui.config
local common = sfui.common
local _G = _G
local type, pairs = _G.type, _G.pairs
local ipairs = _G.ipairs

local refreshTabUI = nil

sfui.options.RegisterTab({
    id = "experience",
    name = "experience",
    icon = "Interface\\Icons\\Spell_DeathKnight_EmpowerRuneblade",
    resetDefaults = function()
        if SfuiDB and SfuiDB.experience then
            local defaults = sfui.config.experience or {}
            for k, v in pairs(defaults) do
                if type(v) == "table" then
                    SfuiDB.experience[k] = {}
                    for subK, subV in pairs(v) do SfuiDB.experience[k][subK] = subV end
                else
                    SfuiDB.experience[k] = v
                end
            end
            if sfui.experience and sfui.experience.Update then
                sfui.experience.Update()
            end
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
    build = function(exp_panel)
        local CreateFlatButton = common.create_flat_button
        local create_checkbox = common.create_checkbox
        local create_slider_input = common.create_slider_input
        local create_dropdown = common.create_dropdown
        local white = sfui.config.colors.white

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
        local header = exp_panel:CreateFontString(nil, "OVERLAY", g.font_large or g.font)
        header:SetPoint("TOPLEFT", 15, -15)
        header:SetTextColor(white[1], white[2], white[3])
        header:SetText("experience & reputation bar")

        local info = exp_panel:CreateFontString(nil, "OVERLAY", g.font)
        info:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
        info:SetPoint("RIGHT", -15, 0)
        info:SetJustifyH("LEFT")
        info:SetTextColor(0.85, 0.85, 0.85, 1)
        info:SetText(
            "multi-layer flat status bar tracking experience, rested bonus, completed quest turn-ins, and reputation progress."
        )

        -- Quick Controls / Shortcuts Guide
        local tips = exp_panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        tips:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -8)
        tips:SetPoint("RIGHT", -15, 0)
        tips:SetJustifyH("LEFT")
        tips:SetText(
            "|cff00ffffhover|r: detailed progress & session analytics card  •  |cff00ffffshift+click|r: share progress to chat\n" ..
            "|cff00ffffright-click|r: open experience settings  •  |cff00ffffunlock button|r: drag to reposition"
        )

        -- ─────────────────────────────────────────────────────────────────────
        -- Quick Action Buttons
        -- ─────────────────────────────────────────────────────────────────────
        local function getUnlockText()
            local isUnlocked = (sfui.experience and sfui.experience.IsUnlocked and sfui.experience.IsUnlocked()) or false
            return isUnlocked and "lock bar" or "unlock bar"
        end

        local function getModeText()
            local mode = (sfui.experience and sfui.experience.GetBarMode and sfui.experience.GetBarMode()) or "XP"
            if mode == "DUAL" then
                return "bar mode: dual stacked"
            elseif mode == "REP" then
                return "bar mode: single (rep)"
            elseif mode == "LEGACY" then
                return "bar mode: single (legacy)"
            else
                return "bar mode: single (xp)"
            end
        end

        local unlock_btn = CreateFlatButton(exp_panel, getUnlockText(), 120, 22)
        unlock_btn:SetPoint("TOPLEFT", tips, "BOTTOMLEFT", 0, -12)
        unlock_btn:SetScript("OnClick", function()
            if sfui.experience and sfui.experience.ToggleUnlock then
                sfui.experience.ToggleUnlock()
                if refreshTabUI then
                    refreshTabUI()
                end
            end
        end)

        local reset_pos_btn = CreateFlatButton(exp_panel, "reset position", 120, 22)
        reset_pos_btn:SetPoint("LEFT", unlock_btn, "RIGHT", 10, 0)
        reset_pos_btn:SetScript("OnClick", function()
            if sfui.experience and sfui.experience.ResetPosition then
                sfui.experience.ResetPosition()
            end
        end)

        local toggle_mode_btn = CreateFlatButton(exp_panel, getModeText(), 160, 22)
        toggle_mode_btn:SetPoint("LEFT", reset_pos_btn, "RIGHT", 10, 0)
        toggle_mode_btn:SetScript("OnClick", function()
            if sfui.experience and sfui.experience.CycleBarMode then
                sfui.experience.CycleBarMode()
                if refreshTabUI then
                    refreshTabUI()
                end
            end
        end)

        -- ─────────────────────────────────────────────────────────────────────
        -- Column 1 (Left): General Settings & Leveling Progress
        -- ─────────────────────────────────────────────────────────────────────
        local COL_OFFSET_X = 280

        -- Section 1: General Settings
        local general_header = exp_panel:CreateFontString(nil, "OVERLAY", g.font)
        general_header:SetPoint("TOPLEFT", unlock_btn, "BOTTOMLEFT", 0, -18)
        general_header:SetTextColor(white[1], white[2], white[3])
        general_header:SetText("general settings")

        local enable_cb = registerCheckbox(create_checkbox(exp_panel, "enable experience bar", function()
            return sfui.db.Get("experience", "enabled", true)
        end, function(checked)
            sfui.db.Set("experience", "enabled", checked)
        end, "enable or disable the sfui experience and reputation bar."))
        enable_cb:SetPoint("TOPLEFT", general_header, "BOTTOMLEFT", 0, -10)

        local blizz_cb = registerCheckbox(create_checkbox(exp_panel, "suppress default blizzard bar", function()
            return sfui.db.Get("experience", "hideBlizzardBar", true)
        end, function(checked)
            sfui.db.Set("experience", "hideBlizzardBar", checked)
        end, "safely hides blizzard's native status tracking bar manager without taint."))
        blizz_cb:SetPoint("TOPLEFT", enable_cb, "BOTTOMLEFT", 0, -8)

        local combat_cb = registerCheckbox(create_checkbox(exp_panel, "hide bar during combat", function()
            return sfui.db.Get("experience", "hideInCombat", false)
        end, function(checked)
            sfui.db.Set("experience", "hideInCombat", checked)
        end, "hides the experience bar completely while in combat to reduce clutter."))
        combat_cb:SetPoint("TOPLEFT", blizz_cb, "BOTTOMLEFT", 0, -8)

        local float_cb = registerCheckbox(create_checkbox(exp_panel, "floating combat xp gain text", function()
            return sfui.db.Get("experience", "showFloatingText", true)
        end, function(checked)
            sfui.db.Set("experience", "showFloatingText", checked)
        end, "animates smooth floating text (+xp) above the bar whenever experience is gained from kills or quests."))
        float_cb:SetPoint("TOPLEFT", combat_cb, "BOTTOMLEFT", 0, -8)

        -- Section 2: Experience & Leveling Progress
        local exp_prog_header = exp_panel:CreateFontString(nil, "OVERLAY", g.font)
        exp_prog_header:SetPoint("TOPLEFT", float_cb, "BOTTOMLEFT", 0, -16)
        exp_prog_header:SetTextColor(white[1], white[2], white[3])
        exp_prog_header:SetText("experience & leveling progress")

        local class_col_cb = registerCheckbox(create_checkbox(exp_panel, "use class / spec color for active xp", function()
            return sfui.db.Get("experience", "useClassColor", false)
        end, function(checked)
            sfui.db.Set("experience", "useClassColor", checked)
        end, "colors the main xp bar dynamically using your class or specialization color (disabled by default)."))
        class_col_cb:SetPoint("TOPLEFT", exp_prog_header, "BOTTOMLEFT", 0, -10)

        local rested_cb = registerCheckbox(create_checkbox(exp_panel, "show rested xp bonus layer", function()
            return sfui.db.Get("experience", "showRested", true)
        end, function(checked)
            sfui.db.Set("experience", "showRested", checked)
        end, "displays a soft cyan fill extending past your current progress showing banked rested xp."))
        rested_cb:SetPoint("TOPLEFT", class_col_cb, "BOTTOMLEFT", 0, -8)

        local quest_cb = registerCheckbox(create_checkbox(exp_panel, "show completed quest xp preview", function()
            return sfui.db.Get("experience", "showQuestPreview", true)
        end, function(checked)
            sfui.db.Set("experience", "showQuestPreview", checked)
        end, "displays an amber fill showing how much progress you will jump when turning in completed quests in your log."))
        quest_cb:SetPoint("TOPLEFT", rested_cb, "BOTTOMLEFT", 0, -8)

        local ticks_cb = registerCheckbox(create_checkbox(exp_panel, "show 20-segment tick dividers", function()
            return sfui.db.Get("experience", "showTicks", false)
        end, function(checked)
            if SfuiDB then
                SfuiDB._expCustomizedTicks = true
            end
            sfui.db.Set("experience", "showTicks", checked)
        end, "overlays subtle vertical hash lines every 5% for classic segment orientation."))
        ticks_cb:SetPoint("TOPLEFT", quest_cb, "BOTTOMLEFT", 0, -8)

        local rate_cb = registerCheckbox(create_checkbox(exp_panel, "show session rate (xp/hr)", function()
            return sfui.db.Get("experience", "showRate", true)
        end, function(checked)
            sfui.db.Set("experience", "showRate", checked)
        end, "displays your current session experience rate on the right side of the bar."))
        rate_cb:SetPoint("TOPLEFT", ticks_cb, "BOTTOMLEFT", 0, -8)

        local ttl_cb = registerCheckbox(create_checkbox(exp_panel, "show estimated time-to-level (ttl)", function()
            return sfui.db.Get("experience", "showTTL", true)
        end, function(checked)
            sfui.db.Set("experience", "showTTL", checked)
        end, "displays estimated time until next level on the left side of the bar."))
        ttl_cb:SetPoint("TOPLEFT", rate_cb, "BOTTOMLEFT", 0, -8)

        -- ─────────────────────────────────────────────────────────────────────
        -- Column 2 (Right): Reputation Tracking & Dimensions
        -- ─────────────────────────────────────────────────────────────────────

        -- Section 3: Reputation & Faction Tracking
        local rep_header = exp_panel:CreateFontString(nil, "OVERLAY", g.font)
        rep_header:SetPoint("TOPLEFT", general_header, "TOPLEFT", COL_OFFSET_X, 0)
        rep_header:SetTextColor(white[1], white[2], white[3])
        rep_header:SetText("reputation & faction tracking")

        local rep_max_level_cb = registerCheckbox(create_checkbox(exp_panel, "only show reputation bar at max level", function()
            return sfui.db.Get("experience", "repOnlyAtMaxLevel", true)
        end, function(checked)
            sfui.db.Set("experience", "repOnlyAtMaxLevel", checked)
            if SfuiDB then SfuiDB._expCustomizedRepMaxLevel = true end
            if sfui.experience and sfui.experience.Update then
                sfui.experience.Update()
            end
        end, "hides the reputation bar entirely while leveling, and only displays it once maximum level or xp disable is reached."))
        rep_max_level_cb:SetPoint("TOPLEFT", rep_header, "BOTTOMLEFT", 0, -10)

        local rep_auto_cb = registerCheckbox(create_checkbox(exp_panel, "auto-switch to reputation at max level", function()
            return sfui.db.Get("experience", "autoReputation", true)
        end, function(checked)
            sfui.db.Set("experience", "autoReputation", checked)
        end, "automatically switches the bar to tracked reputation or major faction renown when at maximum level."))
        rep_auto_cb:SetPoint("TOPLEFT", rep_max_level_cb, "BOTTOMLEFT", 0, -8)

        local dual_cb = registerCheckbox(create_checkbox(exp_panel, "enable dual stacked bars (xp & rep together)", function()
            return sfui.db.Get("experience", "showDualBars", true)
        end, function(checked)
            sfui.db.Set("experience", "showDualBars", checked)
            if sfui.experience and sfui.experience.Update then
                sfui.experience.Update()
            end
            if refreshTabUI then
                refreshTabUI()
            end
        end, "docks the reputation bar directly with the experience bar so you can track both simultaneously while leveling."))
        dual_cb:SetPoint("TOPLEFT", rep_auto_cb, "BOTTOMLEFT", 0, -8)

        local rep_top_cb = registerCheckbox(create_checkbox(exp_panel, "dock reputation bar on top (above xp)", function()
            return sfui.db.Get("experience", "repOnTop", true)
        end, function(checked)
            sfui.db.Set("experience", "repOnTop", checked)
        end, "when checked, the reputation bar stacks directly on top of the xp bar. when unchecked, it stacks below."))
        rep_top_cb:SetPoint("TOPLEFT", dual_cb, "BOTTOMLEFT", 0, -8)

        local rep_gain_cb = registerCheckbox(create_checkbox(exp_panel, "auto-switch to gained reputation", function()
            return sfui.db.Get("experience", "autoSwitchRepOnGain", true)
        end, function(checked)
            sfui.db.Set("experience", "autoSwitchRepOnGain", checked)
            if SfuiDB then SfuiDB._expCustomizedAutoSwitchRep = true end
        end, "automatically activates and switches the watched reputation bar to any faction whenever reputation is gained."))
        rep_gain_cb:SetPoint("TOPLEFT", rep_top_cb, "BOTTOMLEFT", 0, -8)

        local disable_rep_btn = CreateFlatButton(exp_panel, "disable reputation tracking", 200, 22)
        disable_rep_btn:SetPoint("TOPLEFT", rep_gain_cb, "BOTTOMLEFT", 0, -10)
        disable_rep_btn.tooltip = "stops watching the current faction, disables auto-switching on reputation gains, and hides the reputation bar."
        disable_rep_btn:SetScript("OnClick", function()
            if sfui.experience and sfui.experience.DisableReputationTracking then
                sfui.experience.DisableReputationTracking()
                if refreshTabUI then
                    refreshTabUI()
                end
            end
        end)

        local lastRepAnchor = disable_rep_btn
        local isCamelotClient = sfui.isCamelot or (sfui.experience and sfui.experience.challenges and ((sfui.experience.challenges.IsSupported and sfui.experience.challenges.IsSupported()) or (sfui.experience.challenges.IsAvailable and sfui.experience.challenges.IsAvailable())))
        if isCamelotClient then
            local legacy_cb = registerCheckbox(create_checkbox(exp_panel, "track legacy challenges progress", function()
                return sfui.db.Get("experience", "trackLegacy", false)
            end, function(checked)
                sfui.db.Set("experience", "trackLegacy", checked)
                if SfuiDB then SfuiDB._expCustomizedTrackLegacy = true end
                if sfui.experience and sfui.experience.Update then
                    sfui.experience.Update()
                end
            end, "camelot only: tracks legacy challenges and points progress on the status bar."))
            legacy_cb:SetPoint("TOPLEFT", disable_rep_btn, "BOTTOMLEFT", 0, -8)

            local legacy_bar_cb = registerCheckbox(create_checkbox(exp_panel, "show dedicated legacy challenges bar", function()
                return sfui.db.Get("experience", "showChallengesBar", false)
            end, function(checked)
                sfui.db.Set("experience", "showChallengesBar", checked)
                if SfuiDB then SfuiDB._expCustomizedChallengesBar = true end
                if sfui.experience and sfui.experience.Update then
                    sfui.experience.Update()
                end
            end, "camelot only: displays an emerald status bar docked above the experience and reputation bars."))
            legacy_bar_cb:SetPoint("TOPLEFT", legacy_cb, "BOTTOMLEFT", 0, -8)
            lastRepAnchor = legacy_bar_cb
        end

        -- Section 4: Dimensions & Text Display
        local dim_header = exp_panel:CreateFontString(nil, "OVERLAY", g.font)
        dim_header:SetPoint("TOPLEFT", lastRepAnchor, "BOTTOMLEFT", 0, -14)
        dim_header:SetTextColor(white[1], white[2], white[3])
        dim_header:SetText("dimensions & text display")

        local width_slider = registerSlider(create_slider_input(exp_panel, "bar width (pixels)", function()
            return sfui.db.Get("experience", "width", 460)
        end, 200, 1200, 10, function(val)
            sfui.db.Set("experience", "width", val)
        end, "width of the experience bar in pixels.", 250))
        width_slider:SetPoint("TOPLEFT", dim_header, "BOTTOMLEFT", 0, -10)

        local height_slider = registerSlider(create_slider_input(exp_panel, "xp bar height (pixels)", function()
            return sfui.db.Get("experience", "height", 14)
        end, 6, 32, 1, function(val)
            sfui.db.Set("experience", "height", val)
        end, "thickness / height of the experience status bar in pixels.", 250))
        height_slider:SetPoint("TOPLEFT", width_slider, "BOTTOMLEFT", 0, -12)

        local rep_height_slider = registerSlider(create_slider_input(exp_panel, "reputation bar height (pixels)", function()
            return sfui.db.Get("experience", "repHeight", 12)
        end, 6, 32, 1, function(val)
            sfui.db.Set("experience", "repHeight", val)
        end, "thickness / height of the stacked reputation status bar in pixels.", 250))
        rep_height_slider:SetPoint("TOPLEFT", height_slider, "BOTTOMLEFT", 0, -12)

        local lastHeightAnchor = rep_height_slider
        if isCamelotClient then
            local challenges_height_slider = registerSlider(create_slider_input(exp_panel, "challenges bar height (pixels)", function()
                return sfui.db.Get("experience", "challengesHeight", 12)
            end, 6, 32, 1, function(val)
                sfui.db.Set("experience", "challengesHeight", val)
            end, "thickness / height of the stacked legacy challenges status bar in pixels.", 250))
            challenges_height_slider:SetPoint("TOPLEFT", rep_height_slider, "BOTTOMLEFT", 0, -12)
            lastHeightAnchor = challenges_height_slider
        end

        -- Text Visibility Dropdown
        local textVisOptions = {
            { text = "always visible",  value = "ALWAYS" },
            { text = "mouseover only",  value = "MOUSEOVER" },
            { text = "never (hidden)",  value = "NEVER" },
        }

        local vis_label = exp_panel:CreateFontString(nil, "OVERLAY", g.font)
        vis_label:SetPoint("TOPLEFT", lastHeightAnchor, "BOTTOMLEFT", 0, -14)
        vis_label:SetTextColor(white[1], white[2], white[3])
        vis_label:SetText("text visibility mode:")

        local vis_dropdown = create_dropdown(exp_panel, 250, textVisOptions, function(val)
            sfui.db.Set("experience", "showText", val)
        end, sfui.db.Get("experience", "showText", "MOUSEOVER"), nil, 250)
        vis_dropdown:SetPoint("TOPLEFT", vis_label, "BOTTOMLEFT", 0, -6)

        -- Text Format Dropdown
        local textFormatOptions = {
            { text = "current / max (percentage)", value = "PERCENT_CURRENT" },
            { text = "percentage only",           value = "PERCENT" },
            { text = "remaining to level",        value = "REMAINING" },
            { text = "raw numbers (current / max)",value = "FRACTION" },
        }

        local format_label = exp_panel:CreateFontString(nil, "OVERLAY", g.font)
        format_label:SetPoint("TOPLEFT", vis_dropdown, "BOTTOMLEFT", 0, -14)
        format_label:SetTextColor(white[1], white[2], white[3])
        format_label:SetText("center text format:")

        local format_dropdown = create_dropdown(exp_panel, 250, textFormatOptions, function(val)
            sfui.db.Set("experience", "textFormat", val)
        end, sfui.db.Get("experience", "textFormat", "PERCENT_CURRENT"), nil, 250)
        format_dropdown:SetPoint("TOPLEFT", format_label, "BOTTOMLEFT", 0, -6)

        refreshTabUI = function()
            for _, cb in ipairs(allCheckboxes) do
                if cb.update then cb:update() end
            end
            for _, s in ipairs(allSliders) do
                if s.update then s:update() end
            end
            if vis_dropdown and vis_dropdown.SetSelectedValue then
                vis_dropdown:SetSelectedValue(sfui.db.Get("experience", "showText", "MOUSEOVER"))
            end
            if format_dropdown and format_dropdown.SetSelectedValue then
                format_dropdown:SetSelectedValue(sfui.db.Get("experience", "textFormat", "PERCENT_CURRENT"))
            end
            if unlock_btn and unlock_btn.SetText then
                unlock_btn:SetText(getUnlockText())
            end
            if toggle_mode_btn and toggle_mode_btn.SetText then
                toggle_mode_btn:SetText(getModeText())
            end
        end

        if exp_panel.SetContentHeight then
            exp_panel:SetContentHeight(760)
        end
    end,
})
