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
local GetTime = _G.GetTime
local string_match = string.match
local tonumber = _G.tonumber
local type = _G.type
local ipairs = _G.ipairs
local pairs = _G.pairs
local string_lower = string.lower

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
    if sfui.experience.data and sfui.experience.data.ClearFactionCache then
        sfui.experience.data.ClearFactionCache()
    end
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

-- ─── Reputation Gain Detection & Auto-Switching ─────────────────────────────
local compiledRepPatterns = nil
local lastGainFaction = nil
local lastGainTime = 0

local function BuildPatternFromFormat(fmt)
    if not fmt or type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%%d+%$s", "(.+)")
    p = p:gsub("%%%d+%$d", "(%%d+)")
    p = p:gsub("%%s", "(.+)")
    p = p:gsub("%%d", "(%%d+)")
    p = p:gsub("%%%.%*?$", "")
    return p
end

local function GetRepPatterns()
    if compiledRepPatterns then return compiledRepPatterns end
    compiledRepPatterns = {}

    local globalsToCheck = {
        _G.FACTION_STANDING_INCREASED,
        _G.FACTION_STANDING_INCREASED_ACH_BONUS,
        _G.FACTION_STANDING_INCREASED_BONUS,
        _G.FACTION_STANDING_INCREASED_DOUBLE_BONUS,
    }

    for _, fmt in ipairs(globalsToCheck) do
        local pat = BuildPatternFromFormat(fmt)
        if pat then
            compiledRepPatterns[#compiledRepPatterns + 1] = pat
        end
    end

    compiledRepPatterns[#compiledRepPatterns + 1] = "Reputation with (.+) increased by (%d+)"
    compiledRepPatterns[#compiledRepPatterns + 1] = "(.+) reputation increased by (%d+)"

    return compiledRepPatterns
end

local function ParseFactionChatMessage(msg)
    if not msg or type(msg) ~= "string" then return nil, nil end
    if sfui.common and sfui.common.is_secret and sfui.common.is_secret(msg) then return nil, nil end

    local patterns = GetRepPatterns()
    for _, pat in ipairs(patterns) do
        local faction, amount = string_match(msg, pat)
        if faction and amount then
            local val = tonumber(amount)
            if val and val > 0 then
                return faction, val
            end
        end
    end
    return nil, nil
end

local pendingRepGains = {}
local pendingRepCount = 0

local function FlushPendingRepGains()
    if pendingRepCount == 0 then return end

    local bestFaction = nil
    local maxAmount = -1

    -- Check currently watched faction to prefer retaining it on tied gains
    local curRep = sfui.experience.data and sfui.experience.data.GetReputationData and sfui.experience.data.GetReputationData()
    local curClean = (curRep and curRep.hasRep and curRep.name) and string_lower(curRep.name):gsub("^%s*[\"']*(.-)[\"']*%s*$", "%1") or nil

    for fName, amt in pairs(pendingRepGains) do
        if amt > maxAmount then
            maxAmount = amt
            bestFaction = fName
        elseif amt == maxAmount and curClean then
            local cleanName = string_lower(fName):gsub("^%s*[\"']*(.-)[\"']*%s*$", "%1")
            if cleanName == curClean then
                bestFaction = fName
            end
        end
    end

    -- Clear scratch table
    for k in pairs(pendingRepGains) do
        pendingRepGains[k] = nil
    end
    pendingRepCount = 0

    if not bestFaction then return end

    if sfui.experience.data and sfui.experience.data.SetWatchedFactionByName then
        sfui.experience.data.SetWatchedFactionByName(bestFaction)
    end

    -- Activate the reputation bar and refresh visuals
    local showDual = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "showDualBars", true))
    if not showDual then
        if sfui.experience.bar and sfui.experience.bar.SetMode then
            sfui.experience.bar.SetMode("REP")
        end
    else
        if sfui.experience.bar and sfui.experience.bar.UpdateValues then
            sfui.experience.bar.UpdateValues()
        end
    end

    if sfui.experience.reputation and sfui.experience.reputation.UpdateValues then
        sfui.experience.reputation.UpdateValues()
    end
end

local function HandleReputationGain(factionName, amount)
    if not factionName or not amount or amount <= 0 then return end
    if sfui.common and sfui.common.is_secret and sfui.common.is_secret(factionName) then return end

    local enabled = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "autoSwitchRepOnGain", false))
    if not enabled then return end

    pendingRepGains[factionName] = (pendingRepGains[factionName] or 0) + amount
    pendingRepCount = pendingRepCount + 1

    if sfui.common and sfui.common.debounce then
        sfui.common.debounce("sfui_rep_gain_batch", 0.05, FlushPendingRepGains)
    else
        FlushPendingRepGains()
    end
end

local function OnChatMsgCombatFactionChange(event, msg)
    local enabled = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "autoSwitchRepOnGain", false))
    if not enabled then return end

    local faction, amount = ParseFactionChatMessage(msg)
    if faction and amount then
        HandleReputationGain(faction, amount)
    end
end

local function OnCombatTextUpdate(event, arg1, arg2, arg3)
    if arg1 ~= "FACTION" then return end

    local enabled = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "autoSwitchRepOnGain", false))
    if not enabled then return end

    local factionName, amount
    local C_CombatText = _G.C_CombatText
    if C_CombatText and C_CombatText.GetCurrentEventInfo then
        factionName, amount = C_CombatText.GetCurrentEventInfo()
    else
        factionName, amount = arg2, arg3
    end
    if factionName and amount then
        local val = tonumber(amount) or 0
        if val > 0 then
            HandleReputationGain(factionName, val)
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
    reg("CHAT_MSG_COMBAT_FACTION_CHANGE", OnChatMsgCombatFactionChange)
    reg("COMBAT_TEXT_UPDATE", OnCombatTextUpdate)
end

--- Disable and unregister event listeners
function events.Disable()
    for i = 1, #registeredCallbacks do
        local item = registeredCallbacks[i]
        sfui.events.UnregisterEvent(item.event, item.callback)
    end
    registeredCallbacks = {}
end
