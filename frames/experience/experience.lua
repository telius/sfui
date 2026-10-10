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

        if sfui.events and sfui.events.RegisterMessage then
            sfui.events.RegisterMessage("SFUI_THEME_CHANGED", function()
                if exp.bar and exp.bar.ApplyTheme then
                    exp.bar.ApplyTheme()
                end
                if exp.reputation and exp.reputation.ApplyTheme then
                    exp.reputation.ApplyTheme()
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
        elseif exp.reputation then
            if key == "width" or key == "repHeight" or key == "repOnTop" or key == "showTicks" or key == "tickCount" then
                exp.reputation.UpdateLayout()
            end
            exp.reputation.UpdateValues()
        end

        if key == "hideBlizzardBar" and exp.events then
            exp.events.SuppressBlizzardBar()
        end
    end,

    OnSpecChanged = function(self, specID)
        if exp.bar and exp.bar.UpdateValues then
            exp.bar.UpdateValues()
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
    local showTicks = true
    local tickCount = 20
    if sfui.db and sfui.db.Get then
        isEnabled = sfui.db.Get("experience", "enabled", true)
        showTicks = sfui.db.Get("experience", "showTicks", true)
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

    return debugCache
end

exp.GetDebugInfo = sfui.experience_debug_info

sfui.RegisterModule("experience", modDef)

-- ─── Public API ───────────────────────────────────────────────────────────────

--- Trigger an immediate visual update of the experience bar
function exp.Update()
    if exp.bar then
        exp.bar.UpdateLayout()
        exp.bar.UpdateValues()
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
end

--- Reset experience bar position to default
function exp.ResetPosition()
    local cfg = sfui.config and sfui.config.experience
    local defaultPos = (cfg and cfg.pos) or { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 4 }
    if sfui.db and sfui.db.Set then
        sfui.db.Set("experience", "pos", defaultPos)
    end
    if exp.bar and exp.bar.UpdateLayout then
        exp.bar.UpdateLayout()
    end
    if exp.reputation and exp.reputation.UpdateLayout then
        exp.reputation.UpdateLayout()
    end
end

--- Toggle unlocked drag state for moving the experience bar
--- @return boolean
function exp.ToggleUnlock()
    local f = exp.bar and exp.bar.GetFrame and exp.bar.GetFrame()
    local rf = exp.reputation and exp.reputation.GetFrame and exp.reputation.GetFrame()
    if not f and not rf then return false end

    local target = f or rf
    target._isUnlocked = not target._isUnlocked
    local isUnlocked = target._isUnlocked
    if f then f._isUnlocked = isUnlocked end
    if rf then rf._isUnlocked = isUnlocked end

    if isUnlocked then
        print("|cff6600ffsf|rui: experience bar unlocked. drag to reposition.")
    else
        print("|cff6600ffsf|rui: experience bar locked.")
    end
    return isUnlocked
end

--- Switch between XP and Reputation display
--- @param mode string|nil "XP" or "REP"
function exp.SetBarMode(mode)
    if not exp.bar then return end
    if mode == "XP" or mode == "REP" then
        exp.bar.SetMode(mode)
    else
        exp.bar.ToggleMode()
    end
end
