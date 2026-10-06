local addonName, addon = ...
sfui = sfui or {}
sfui.experience = sfui.experience or {}
sfui.experience.events = {}

local events = sfui.experience.events

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/experience/events.lua
--  Event management, debouncing, and safe Blizzard bar suppression
-- ══════════════════════════════════════════════════════════════════════════════

local _G = _G
local UnitXP = _G.UnitXP

local lastPlayerXP = nil
local registeredCallbacks = {}

--- Request a debounced bar update via sfui.common.debounce
local function RequestDebouncedUpdate()
    if sfui.common and sfui.common.debounce then
        sfui.common.debounce("sfui_experience_update", 0.05, function()
            if sfui.experience.bar and sfui.experience.bar.UpdateValues then
                sfui.experience.bar.UpdateValues()
            end
        end)
    else
        if sfui.experience.bar and sfui.experience.bar.UpdateValues then
            sfui.experience.bar.UpdateValues()
        end
    end
end

local function DisableFrameMouse(f)
    if not f then return end
    if f.EnableMouse then f:EnableMouse(false) end
    if f.barContainers then
        for _, bContainer in ipairs(f.barContainers) do
            if bContainer.EnableMouse then bContainer:EnableMouse(false) end
            if bContainer.bars then
                for _, b in ipairs(bContainer.bars) do
                    if b.EnableMouse then b:EnableMouse(false) end
                end
            end
        end
    end
end

--- Suppress Blizzard's default StatusTrackingBarManager safely without taint
function events.SuppressBlizzardBar()
    local hideBlizz = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "hideBlizzardBar", true))
    if hideBlizz == nil then hideBlizz = true end
    if not hideBlizz then return end

    local mgr = _G.StatusTrackingBarManager
    if mgr then
        mgr:SetAlpha(0)
        DisableFrameMouse(mgr)
        if _G.MainStatusTrackingBarContainer then DisableFrameMouse(_G.MainStatusTrackingBarContainer) end
        if _G.SecondaryStatusTrackingBarContainer then DisableFrameMouse(_G.SecondaryStatusTrackingBarContainer) end
        if not mgr._sfuiHooked then
            mgr._sfuiHooked = true
            mgr:HookScript("OnShow", function(self)
                local shouldHide = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "hideBlizzardBar", true))
                if shouldHide ~= false then
                    self:SetAlpha(0)
                    DisableFrameMouse(self)
                    if _G.MainStatusTrackingBarContainer then DisableFrameMouse(_G.MainStatusTrackingBarContainer) end
                    if _G.SecondaryStatusTrackingBarContainer then DisableFrameMouse(_G.SecondaryStatusTrackingBarContainer) end
                end
            end)
        end
    end

    local oldExpBar = _G.MainMenuExpBar
    if oldExpBar then
        oldExpBar:SetAlpha(0)
        if oldExpBar.EnableMouse then oldExpBar:EnableMouse(false) end
        if not oldExpBar._sfuiHooked then
            oldExpBar._sfuiHooked = true
            oldExpBar:HookScript("OnShow", function(self)
                local shouldHide = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "hideBlizzardBar", true))
                if shouldHide ~= false then
                    self:SetAlpha(0)
                    if self.EnableMouse then self:EnableMouse(false) end
                end
            end)
        end
    end
end

-- ─── Event Callbacks ────────────────────────────────────────────────────────

local function OnEnteringWorld()
    events.SuppressBlizzardBar()
    lastPlayerXP = UnitXP("player") or 0
    if sfui.experience.data and sfui.experience.data.InitSession then
        sfui.experience.data.InitSession()
    end
    if sfui.experience.bar then
        sfui.experience.bar.UpdateLayout()
        sfui.experience.bar.UpdateValues()
    end
end

local function OnPlayerXPUpdate()
    local currentXP = UnitXP("player") or 0
    if lastPlayerXP and currentXP > lastPlayerXP then
        local gained = currentXP - lastPlayerXP
        if sfui.experience.data and sfui.experience.data.RecordXPGain then
            sfui.experience.data.RecordXPGain(gained, true)
        end
        if sfui.experience.floating and sfui.experience.floating.Spawn then
            sfui.experience.floating.Spawn(gained)
        end
    end
    lastPlayerXP = currentXP
    RequestDebouncedUpdate()
end

local function OnExhaustionOrLevelUp()
    lastPlayerXP = UnitXP("player") or 0
    RequestDebouncedUpdate()
end

local function OnQuestOrFactionUpdate()
    RequestDebouncedUpdate()
end

local function OnCombatStateChanged(event)
    local hideInCombat = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "hideInCombat", false))
    if hideInCombat then
        local alpha = (event == "PLAYER_REGEN_DISABLED") and 0 or 1.0
        if sfui.experience.bar then
            local f = sfui.experience.bar.GetFrame()
            if f then f:SetAlpha(alpha) end
        end
        if sfui.experience.reputation then
            local rf = sfui.experience.reputation.GetFrame()
            if rf then rf:SetAlpha(alpha) end
        end
    end
end

--- Initialize event listeners using central sfui.events dispatcher
function events.Initialize()
    if #registeredCallbacks > 0 then return end

    local function reg(eventName, callback)
        sfui.events.RegisterEvent(eventName, callback)
        registeredCallbacks[#registeredCallbacks + 1] = { event = eventName, callback = callback }
    end

    local function regThrottled(eventName, interval, callback)
        local handle = sfui.events.RegisterThrottledEvent(eventName, interval, callback)
        registeredCallbacks[#registeredCallbacks + 1] = { event = eventName, callback = handle }
    end

    reg("PLAYER_ENTERING_WORLD", OnEnteringWorld)
    reg("PLAYER_XP_UPDATE", OnPlayerXPUpdate)
    reg("UPDATE_EXHAUSTION", OnExhaustionOrLevelUp)
    reg("PLAYER_LEVEL_UP", OnExhaustionOrLevelUp)
    regThrottled("QUEST_LOG_UPDATE", 0.1, OnQuestOrFactionUpdate)
    regThrottled("QUEST_WATCH_LIST_CHANGED", 0.1, OnQuestOrFactionUpdate)
    regThrottled("UPDATE_FACTION", 0.1, OnQuestOrFactionUpdate)
    regThrottled("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", 0.1, OnQuestOrFactionUpdate)
    reg("PLAYER_REGEN_DISABLED", OnCombatStateChanged)
    reg("PLAYER_REGEN_ENABLED", OnCombatStateChanged)
end

--- Disable and unregister event listeners
function events.Disable()
    for i = 1, #registeredCallbacks do
        local item = registeredCallbacks[i]
        sfui.events.UnregisterEvent(item.event, item.callback)
    end
    registeredCallbacks = {}
end
