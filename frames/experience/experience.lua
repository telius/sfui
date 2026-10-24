local addonName, addon = ...
sfui = sfui or {}
sfui.experience = sfui.experience or {}

local exp = sfui.experience

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/experience/experience.lua
--  Module Entry Point & Public API Protocol
-- ══════════════════════════════════════════════════════════════════════════════

local modDef = {
    OnInit = function(self)
        if sfui.db and sfui.db.RegisterDefaults and sfui.config and sfui.config.experience then
            sfui.db.RegisterDefaults("experience", sfui.config.experience)
        end

        -- Auto-migrate default text visibility to MOUSEOVER for existing profiles
        if SfuiDB and SfuiDB.experience and not SfuiDB._expTextMouseoverDefault then
            if SfuiDB.experience.showText == "ALWAYS" then
                SfuiDB.experience.showText = "MOUSEOVER"
            end
            SfuiDB._expTextMouseoverDefault = true
        end

        -- Auto-migrate new experience defaults for existing profiles:
        -- - hide dedicated legacy challenges bar by default
        -- - enable only show reputation at max level by default
        -- - enable auto-switch to gained reputation by default
        if SfuiDB and not SfuiDB._expDefaultsV2 then
            if SfuiDB.experience then
                if not SfuiDB._expCustomizedChallengesBar then
                    SfuiDB.experience.showChallengesBar = false
                end
                if not SfuiDB._expCustomizedRepMaxLevel then
                    SfuiDB.experience.repOnlyAtMaxLevel = true
                end
                if not SfuiDB._expCustomizedAutoSwitchRep then
                    SfuiDB.experience.autoSwitchRepOnGain = true
                end
            end
            SfuiDB._expDefaultsV2 = true
        end

        -- Auto-migrate disable showTicks by default for existing profiles:
        if SfuiDB and not SfuiDB._expDefaultsV3 then
            if SfuiDB.experience then
                if not SfuiDB._expCustomizedTicks then
                    SfuiDB.experience.showTicks = false
                end
            end
            SfuiDB._expDefaultsV3 = true
        end

        -- Auto-migrate disable challenge bar & trackLegacy by default for existing profiles:
        if SfuiDB and not SfuiDB._expDefaultsV4 then
            if SfuiDB.experience then
                if not SfuiDB._expCustomizedTrackLegacy then
                    SfuiDB.experience.trackLegacy = false
                end
                if not SfuiDB._expCustomizedChallengesBar then
                    SfuiDB.experience.showChallengesBar = false
                end
            end
            SfuiDB._expDefaultsV4 = true
        end

        if sfui.events and sfui.events.RegisterMessage then
            sfui.events.RegisterMessage("SFUI_THEME_CHANGED", function()
                if exp.bar and exp.bar.ApplyTheme then
                    exp.bar.ApplyTheme()
                end
                if exp.reputation and exp.reputation.ApplyTheme then
                    exp.reputation.ApplyTheme()
                end
                if exp.pet and exp.pet.ApplyTheme then
                    exp.pet.ApplyTheme()
                end
            end)
        end
    end,

    OnEnable = function(self)
        local enabled = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "enabled", true))
        if enabled == nil then enabled = true end
        if not enabled then return end

        if exp.bar and exp.bar.Create then
            local f = exp.bar.Create()
            if f then f:Show() end
        end

        if exp.reputation and exp.reputation.Create then
            local rf = exp.reputation.Create()
            if rf then rf:Show() end
        end

        if exp.challenges and exp.challenges.Create then
            local cf = exp.challenges.Create()
            if cf then cf:Show() end
        end

        if exp.pet and exp.pet.Create then
            local pf = exp.pet.Create()
            if pf and exp.pet.UpdateValues then exp.pet.UpdateValues() end
        end

        if exp.events and exp.events.Initialize then
            exp.events.Initialize()
        end

        if exp.events and exp.events.SuppressBlizzardBar then
            exp.events.SuppressBlizzardBar()
        end

        local tex = (sfui.widgets and sfui.widgets.get_bar_texture and sfui.widgets.get_bar_texture()) or (sfui.config and sfui.config.barTexture)
        if tex then
            exp.SetBarTexture(tex)
        end
    end,

    OnDisable = function(self)
        if exp.events and exp.events.Disable then
            exp.events.Disable()
        end
        if exp.floating and exp.floating.Reset then
            exp.floating.Reset()
        end
        if exp.bar and exp.bar.GetFrame then
            local f = exp.bar.GetFrame()
            if f then f:Hide() end
        end
        if exp.reputation and exp.reputation.GetFrame then
            local rf = exp.reputation.GetFrame()
            if rf then rf:Hide() end
        end
        if exp.challenges and exp.challenges.GetFrame then
            local cf = exp.challenges.GetFrame()
            if cf then cf:Hide() end
        end
        if exp.pet and exp.pet.GetFrame then
            local pf = exp.pet.GetFrame()
            if pf then pf:Hide() end
        end
    end,

    OnSettingsChanged = function(self, key, value)
        if key == "enabled" then
            if value then
                self:OnEnable()
            else
                self:OnDisable()
            end
            return
        end

        if key == "barTexture" then
            exp.SetBarTexture(value)
            return
        end

        if exp.bar then
            if key == "width" or key == "height" or key == "pos" or key == "showTicks" or key == "tickCount" or key == "repHeight" or key == "repOnTop" then
                exp.bar.UpdateLayout()
            end
            exp.bar.UpdateValues()
        end
        if exp.reputation then
            if key == "width" or key == "repHeight" or key == "repOnTop" or key == "showTicks" or key == "tickCount" then
                exp.reputation.UpdateLayout()
            end
            exp.reputation.UpdateValues()
        end
        if exp.challenges then
            if key == "width" or key == "challengesHeight" or key == "repOnTop" or key == "showTicks" or key == "tickCount" or key == "trackLegacy" or key == "showChallengesBar" or key == "repHeight" or key == "height" then
                exp.challenges.UpdateLayout()
            end
            exp.challenges.UpdateValues()
        end
        if exp.pet then
            if key == "width" or key == "petHeight" or key == "challengesHeight" or key == "repHeight" or key == "height" or key == "pos" or key == "petBarAlwaysShow" then
                if exp.pet.UpdateLayout then exp.pet.UpdateLayout() end
            end
            if exp.pet.UpdateValues then exp.pet.UpdateValues() end
        end

        if key == "hideBlizzardBar" and exp.events then
            exp.events.SuppressBlizzardBar()
        end
    end,

    OnSpecChanged = function(self, specID)
        if exp.bar and exp.bar.UpdateValues then
            exp.bar.UpdateValues()
        end
        if exp.reputation and exp.reputation.UpdateValues then
            exp.reputation.UpdateValues()
        end
        if exp.challenges and exp.challenges.UpdateValues then
            exp.challenges.UpdateValues()
        end
        if exp.pet and exp.pet.UpdateValues then
            exp.pet.UpdateValues()
        end
    end,

    GetDebugInfo = function(self)
        return sfui.experience_debug_info()
    end,
}

local debugCache = {}

--- Public debug telemetry info for memory profiler and /sfui mem
--- @return table
function sfui.experience_debug_info()
    local data = exp.data
    local xp = data and data.GetXPData and data.GetXPData()
    local rep = data and data.GetReputationData and data.GetReputationData()
    local barFrame = exp.bar and exp.bar.GetFrame and exp.bar.GetFrame()
    local repFrame = exp.reputation and exp.reputation.GetFrame and exp.reputation.GetFrame()

    local activeFloat, poolFloat = 0, 0
    if exp.floating and exp.floating.GetPoolStats then
        activeFloat, poolFloat = exp.floating.GetPoolStats()
    end

    local isEnabled = true
    local showTicks = false
    local tickCount = 20
    if sfui.db and sfui.db.Get then
        isEnabled = sfui.db.Get("experience", "enabled", true)
        showTicks = sfui.db.Get("experience", "showTicks", false)
        tickCount = sfui.db.Get("experience", "tickCount", 20)
    end

    debugCache.isEnabled = (isEnabled ~= false)
    debugCache.barCreated = (barFrame ~= nil)
    debugCache.barShown = (barFrame and barFrame:IsShown()) and true or false
    debugCache.repBarCreated = (repFrame ~= nil)
    debugCache.repBarShown = (repFrame and repFrame:IsShown()) and true or false
    debugCache.level = xp and xp.level or 0
    debugCache.isMaxLevel = xp and xp.isMaxLevel or false
    debugCache.xpCurrent = xp and xp.current or 0
    debugCache.xpMax = xp and xp.max or 0
    debugCache.xpPercent = xp and xp.percent or 0
    debugCache.hasRep = rep and rep.hasRep or false
    debugCache.repName = rep and rep.name or nil
    debugCache.repPercent = rep and rep.percent or 0
    debugCache.floatingActive = activeFloat
    debugCache.floatingPool = poolFloat
    debugCache.showTicks = showTicks
    debugCache.tickCount = tickCount

    local ch = exp.challenges
    local chData = ch and ch.GetData and ch.GetData()
    local chFrame = ch and ch.GetFrame and ch.GetFrame()
    debugCache.hasLegacy = chData and chData.hasData or false
    debugCache.legacyRank = chData and chData.level or 0
    debugCache.challengesBarCreated = (chFrame ~= nil)
    debugCache.challengesBarShown = (chFrame and chFrame:IsShown()) and true or false

    return debugCache
end

exp.GetDebugInfo = sfui.experience_debug_info

sfui.RegisterModule("experience", modDef)

-- ─── Public API ───────────────────────────────────────────────────────────────

--- Trigger an immediate visual update of the experience bar
--- Trigger an immediate visual update of the experience and reputation bars
function exp.Update()
    if exp.bar then
        exp.bar.UpdateLayout()
        exp.bar.UpdateValues()
    end
    if exp.reputation then
        exp.reputation.UpdateLayout()
        exp.reputation.UpdateValues()
    end
    if exp.challenges then
        exp.challenges.UpdateLayout()
        exp.challenges.UpdateValues()
    end
    if exp.pet and exp.pet.UpdateValues then
        exp.pet.UpdateValues()
    end
end

--- Set status bar texture across experience and reputation bars
--- @param texturePath string|nil
function exp.SetBarTexture(texturePath)
    if exp.bar and exp.bar.SetBarTexture then
        exp.bar.SetBarTexture(texturePath)
    end
    if exp.reputation and exp.reputation.SetBarTexture then
        exp.reputation.SetBarTexture(texturePath)
    end
    if exp.challenges and exp.challenges.SetBarTexture then
        exp.challenges.SetBarTexture(texturePath)
    end
    if exp.pet and exp.pet.ApplyTheme then
        exp.pet.ApplyTheme()
    end
end

--- Reset experience bar position to default
function exp.ResetPosition()
    local cfg = sfui.config and sfui.config.experience
    local defaultPos = (cfg and cfg.pos) or { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 4 }
    local newPos = {
        point = defaultPos.point or "BOTTOM",
        relativePoint = defaultPos.relativePoint or defaultPos.point or "BOTTOM",
        x = defaultPos.x or 0,
        y = defaultPos.y or 4,
    }
    if sfui.db and sfui.db.Set then
        sfui.db.Set("experience", "pos", newPos)
    end
    if exp.bar and exp.bar.UpdateLayout then
        exp.bar.UpdateLayout()
    end
    if exp.reputation and exp.reputation.UpdateLayout then
        exp.reputation.UpdateLayout()
    end
    if exp.challenges and exp.challenges.UpdateLayout then
        exp.challenges.UpdateLayout()
    end
    if exp.pet and exp.pet.UpdateLayout then
        exp.pet.UpdateLayout()
    end
    if sfui.common and sfui.common.print then
        sfui.common.print("experience bar position reset to default.")
    end
end

--- Toggle unlocked drag state for moving the experience and reputation bars
--- @return boolean
function exp.ToggleUnlock()
    if not exp.bar or not exp.bar.GetFrame or not exp.bar.GetFrame() then
        if exp.bar and exp.bar.Create then exp.bar.Create() end
    end
    if not exp.reputation or not exp.reputation.GetFrame or not exp.reputation.GetFrame() then
        if exp.reputation and exp.reputation.Create then exp.reputation.Create() end
    end
    if not exp.challenges or not exp.challenges.GetFrame or not exp.challenges.GetFrame() then
        if exp.challenges and exp.challenges.Create then exp.challenges.Create() end
    end

    exp._isUnlocked = not exp._isUnlocked
    local isUnlocked = exp._isUnlocked

    if exp.bar and exp.bar.SetUnlocked then
        exp.bar.SetUnlocked(isUnlocked)
    end
    if exp.reputation and exp.reputation.SetUnlocked then
        exp.reputation.SetUnlocked(isUnlocked)
    end
    if exp.challenges and exp.challenges.SetUnlocked then
        exp.challenges.SetUnlocked(isUnlocked)
    end

    if sfui.common and sfui.common.print then
        if isUnlocked then
            sfui.common.print("experience bar unlocked (drag to reposition).")
        else
            sfui.common.print("experience bar locked.")
        end
    end
    return isUnlocked
end

--- Check if experience bar is currently unlocked for dragging
--- @return boolean
function exp.IsUnlocked()
    return exp._isUnlocked or false
end

--- Get current bar mode ("DUAL", "XP", "REP")
--- @return string
function exp.GetBarMode()
    local cfg = sfui.config and sfui.config.experience or {}
    local showDual = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "showDualBars", cfg.showDualBars ~= false))
    if showDual == nil then showDual = true end
    if showDual then
        return "DUAL"
    end
    local currentMode = (exp.bar and exp.bar.GetMode and exp.bar.GetMode()) or "XP"
    return currentMode
end

--- Cycle through bar modes: DUAL -> XP -> REP -> (LEGACY) -> DUAL
--- @return string newMode
function exp.CycleBarMode()
    local curMode = exp.GetBarMode()
    local hasLegacy = exp.challenges and exp.challenges.IsAvailable and exp.challenges.IsAvailable()
    local nextMode
    if curMode == "DUAL" then
        nextMode = "XP"
    elseif curMode == "XP" then
        nextMode = "REP"
    elseif curMode == "REP" then
        if hasLegacy then
            nextMode = "LEGACY"
        else
            nextMode = "DUAL"
        end
    else -- "LEGACY"
        nextMode = "DUAL"
    end
    exp.SetBarMode(nextMode)
    return nextMode
end

--- Switch between Dual, XP, Reputation, and Legacy display
--- @param mode string|nil "DUAL", "XP", "REP", or "LEGACY"
function exp.SetBarMode(mode)
    if not exp.bar then return end
    if mode == "DUAL" then
        if sfui.db and sfui.db.Set then
            sfui.db.Set("experience", "showDualBars", true)
        end
        if exp.bar.SetMode then
            exp.bar.SetMode("XP")
        end
    elseif mode == "REP" then
        if sfui.db and sfui.db.Set then
            sfui.db.Set("experience", "showDualBars", false)
        end
        if exp.bar.SetMode then
            exp.bar.SetMode("REP")
        end
    elseif mode == "LEGACY" then
        if sfui.db and sfui.db.Set then
            sfui.db.Set("experience", "showDualBars", false)
        end
        if exp.bar.SetMode then
            exp.bar.SetMode("LEGACY")
        end
    elseif mode == "XP" then
        if sfui.db and sfui.db.Set then
            sfui.db.Set("experience", "showDualBars", false)
        end
        if exp.bar.SetMode then
            exp.bar.SetMode("XP")
        end
    else
        exp.CycleBarMode()
        return
    end

    if exp.Update then
        exp.Update()
    end
end

--- Disable reputation tracking: unwatch active faction and disable auto-switch on gain
function exp.DisableReputationTracking()
    if exp.data and exp.data.SetWatchedFaction then
        exp.data.SetWatchedFaction(0)
    end
    if sfui.db and sfui.db.Set then
        sfui.db.Set("experience", "autoSwitchRepOnGain", false)
    end
    if SfuiDB then
        SfuiDB._expCustomizedAutoSwitchRep = true
    end
    if exp.reputation and exp.reputation.GetFrame then
        local rf = exp.reputation.GetFrame()
        if rf and not rf._isUnlocked then
            rf:Hide()
        end
    end
    local mode = exp.GetBarMode()
    if mode == "REP" then
        exp.SetBarMode("XP")
    elseif exp.Update then
        exp.Update()
    end
    if sfui.common and sfui.common.print then
        sfui.common.print("reputation tracking disabled and cleared.")
    end
end

exp.ClearWatchedReputation = exp.DisableReputationTracking
exp.UntrackReputation = exp.DisableReputationTracking

