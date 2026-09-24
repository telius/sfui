local addonName, addon = ...
sfui = sfui or {}
sfui.tracker = sfui.tracker or {}
sfui.questlog = sfui.questlog or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/quests/engine/tracker.lua
--  Master Tracker Container, Refresh Throttle, Raid Auto-Hide & Public Facade
-- ══════════════════════════════════════════════════════════════════════════════

local _G = _G
local CreateFrame, UIParent = _G.CreateFrame, _G.UIParent
local C_Timer = _G.C_Timer
local InCombatLockdown = _G.InCombatLockdown
local ipairs, pairs, type = _G.ipairs, _G.pairs, _G.type
local table_insert, table_sort = _G.table.insert, _G.table.sort

local Tracker = sfui.tracker
local Layout  = sfui.tracker.layout
local Blocks  = sfui.tracker.blocks

local container = nil
local refreshTimer = nil
local isRefreshing = false
local isRaidSuppressed = false
local isPetBattleSuppressed = false
local isMythicSuppressed = false

local SuppressBlizzardTrackers, RestoreBlizzardTrackers

-- ─── Throttled Update Loop ──────────────────────────────────────────────────
local function ExecuteLayout()
    refreshTimer = nil
    if not container or not container:IsShown() then return end
    if SuppressBlizzardTrackers then SuppressBlizzardTrackers() end

    if isRaidSuppressed or isPetBattleSuppressed or isMythicSuppressed then
        container:SetAlpha(0)
        return
    else
        container:SetAlpha(1)
    end

    if isRefreshing then return end
    isRefreshing = true

    -- Collect sections from all enabled modules and merge sections with the same ID
    local allSections = {}
    local sectionMap = {}
    for _, mod in ipairs(Tracker.modules or {}) do
        if mod:IsEnabled() and mod.BuildBlocks then
            local modSections = mod:BuildBlocks(container)
            if modSections then
                for _, s in ipairs(modSections) do
                    if s.id and sectionMap[s.id] then
                        local existing = sectionMap[s.id]
                        if s.blocks then
                            for _, b in ipairs(s.blocks) do
                                table_insert(existing.blocks, b)
                            end
                        end
                        if s.count then
                            existing.count = (existing.count or #existing.blocks) + s.count
                        end
                    else
                        table_insert(allSections, s)
                        if s.id then
                            sectionMap[s.id] = s
                        end
                    end
                end
            end
            mod:ClearDirty()
        end
    end

    -- In Retail, sort sections by canonical hierarchy (scenario -> events -> important -> campaign -> meta -> world -> activities -> zone -> etc.)
    local isCamelot = sfui.isForever or (sfui.compat and (sfui.compat.is_wow_forever or sfui.compat.is_classic_era or sfui.compat.is_classic))
    if not isCamelot then
        local sectionRanks = {
            scenario     = 10,
            events       = 20,
            worldevents  = 20,
            event        = 20,
            important    = 30,
            campaign     = 40,
            meta         = 50,
            world        = 60,
            worldquests  = 60,
            activities   = 70,
            zone         = 80,
            achievements = 90,
            recipes      = 100,
            collectables = 110,
        }
        table_sort(allSections, function(a, b)
            local rA = sectionRanks[a.id] or 99
            local rB = sectionRanks[b.id] or 99
            return rA < rB
        end)
    end

    -- Run vertical stack layout
    Layout.BuildLayout(container, allSections)

    isRefreshing = false
end

function Tracker.RequestRefresh(delay)
    local cfg = (sfui.config and sfui.config.questlog) or {}
    local throttle = delay or cfg.throttle or 0.25

    if refreshTimer then
        if delay and delay <= 0.05 then
            if refreshTimer.Cancel then
                refreshTimer:Cancel()
            end
            refreshTimer = nil
        else
            return
        end
    end

    refreshTimer = C_Timer.NewTimer(throttle, ExecuteLayout)
end

-- ─── Container Frame Factory ────────────────────────────────────────────────
local function CreateTrackerContainer()
    if container then return container end

    local cfg = (sfui.config and sfui.config.questlog) or {}
    local width = cfg.width or 280

    local f = CreateFrame("Frame", "SfuiQuestTrackerFrame", UIParent)
    f:SetSize(width, 100)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(false)

    -- Saved position restoration (default: TOPRIGHT -4, -4 from UIParent)
    local point = SfuiDB and (SfuiDB.questlogPoint or SfuiDB.mythicHudPoint)
    local relPoint = SfuiDB and (SfuiDB.questlogRelativePoint or SfuiDB.mythicHudRelativePoint)
    local x = SfuiDB and (SfuiDB.questlogX or SfuiDB.mythicHudX)
    local y = SfuiDB and (SfuiDB.questlogY or SfuiDB.mythicHudY)

    if not point and x and x > 0 then
        -- Handle legacy position saved from StopMovingOrSizing (which sets BOTTOMLEFT)
        point = "BOTTOMLEFT"
        relPoint = "BOTTOMLEFT"
    end

    f:ClearAllPoints()
    if x and y then
        f:SetPoint(point or "TOPRIGHT", UIParent, relPoint or "TOPRIGHT", x, y)
    else
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -4, -4)
    end

    -- Drag handling when unlocked
    local function OnTrackerDragStart()
        if not (SfuiDB and SfuiDB.questlogLocked) then
            f:StartMoving()
        end
    end
    local function OnTrackerDragStop()
        f:StopMovingOrSizing()
        local p, _, relP, posX, posY = f:GetPoint()
        if p and SfuiDB then
            SfuiDB.questlogPoint = p
            SfuiDB.questlogRelativePoint = relP
            SfuiDB.questlogX = math.floor(posX + 0.5)
            SfuiDB.questlogY = math.floor(posY + 0.5)
            SfuiDB.mythicHudPoint = p
            SfuiDB.mythicHudRelativePoint = relP
            SfuiDB.mythicHudX = SfuiDB.questlogX
            SfuiDB.mythicHudY = SfuiDB.questlogY
        end
    end

    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", OnTrackerDragStart)
    f:SetScript("OnDragStop", OnTrackerDragStop)

    -- Scrollbar (Slider)
    local scrollBar = CreateFrame("Slider", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    scrollBar:SetOrientation("VERTICAL")
    scrollBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, 0)
    scrollBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    scrollBar:SetWidth(6)
    if scrollBar.SetBackdrop then
        scrollBar:SetBackdrop({ bgFile = [[Interface\Buttons\WHITE8x8]] })
        scrollBar:SetBackdropColor(0, 0, 0, 0.15)
    end
    scrollBar:SetMinMaxValues(0, 0)
    scrollBar:SetValue(0)

    local sbThumb = scrollBar:CreateTexture(nil, "ARTWORK")
    sbThumb:SetSize(3, 36)
    sbThumb:SetColorTexture(0.40, 0.00, 1.00, 1.0) -- SFUI signature purple (#6600ff)
    scrollBar:SetThumbTexture(sbThumb)
    scrollBar:Hide()

    -- Scroll clip (clips children)
    local scrollClip = CreateFrame("Frame", nil, f)
    scrollClip:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    scrollClip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    if scrollClip.SetClipsChildren then
        scrollClip:SetClipsChildren(true)
    end

    -- Content frame (hosts headers, blocks, lines, bars)
    local content = CreateFrame("Frame", nil, scrollClip)
    content:SetPoint("TOPLEFT", scrollClip, "TOPLEFT", 0, 0)
    content:SetWidth(width)
    content:SetHeight(100)

    -- Scrolling logic
    local function OnTrackerMouseWheel(_, delta)
        if not scrollBar:IsShown() then return end
        local cur = scrollBar:GetValue() or 0
        local lo, hi = scrollBar:GetMinMaxValues()
        scrollBar:SetValue(math.max(lo, math.min(hi, cur - delta * 24)))
    end

    scrollClip:EnableMouseWheel(true)
    scrollClip:SetScript("OnMouseWheel", OnTrackerMouseWheel)
    scrollBar:EnableMouseWheel(true)
    scrollBar:SetScript("OnMouseWheel", OnTrackerMouseWheel)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", OnTrackerMouseWheel)
    content:EnableMouseWheel(true)
    content:SetScript("OnMouseWheel", OnTrackerMouseWheel)

    scrollBar:SetScript("OnValueChanged", function(_, val)
        local rounded = math.floor(val + 0.5)
        content:SetPoint("TOPLEFT", scrollClip, "TOPLEFT", 0, rounded)
    end)

    scrollClip:RegisterForDrag("LeftButton")
    scrollClip:SetScript("OnDragStart", OnTrackerDragStart)
    scrollClip:SetScript("OnDragStop", OnTrackerDragStop)
    content:RegisterForDrag("LeftButton")
    content:SetScript("OnDragStart", OnTrackerDragStart)
    content:SetScript("OnDragStop", OnTrackerDragStop)

    f.scrollBar = scrollBar
    f.scrollClip = scrollClip
    f.content = content
    Tracker.OnMouseWheel = OnTrackerMouseWheel

    container = f
    Tracker.container = f
    return f
end

-- ─── Blizzard Tracker Suppression (Vanilla, Camelot, Classic, Retail) ───────
local hookedTrackers = {}
local questWatchUpdateHooked = false

local function EnsureQuestWatchHook()
    if questWatchUpdateHooked then return end
    if _G.hooksecurefunc and _G.QuestWatch_Update then
        questWatchUpdateHooked = true
        _G.hooksecurefunc("QuestWatch_Update", function()
            if sfui.questlog and sfui.questlog.is_enabled and sfui.questlog.is_enabled() then
                local qwf = _G.QuestWatchFrame
                if qwf then
                    if qwf.SetAlpha then qwf:SetAlpha(0) end
                    if qwf.EnableMouse then qwf:EnableMouse(false) end
                    if qwf.Hide then qwf:Hide() end
                end
            end
        end)
    end
end

local function SuppressBlizzardTrackers()
    if not (sfui.questlog and sfui.questlog.is_enabled and sfui.questlog.is_enabled()) then
        return
    end

    EnsureQuestWatchHook()

    -- 1. Classic Vanilla / Classic Era / Camelot (QuestWatchFrame)
    local qwf = _G.QuestWatchFrame
    if qwf then
        if qwf.SetAlpha then qwf:SetAlpha(0) end
        if qwf.EnableMouse then qwf:EnableMouse(false) end
        if qwf.Hide then qwf:Hide() end
        if not hookedTrackers[qwf] and qwf.HookScript then
            hookedTrackers[qwf] = true
            qwf:HookScript("OnShow", function(self)
                if sfui.questlog and sfui.questlog.is_enabled and sfui.questlog.is_enabled() then
                    if self.SetAlpha then self:SetAlpha(0) end
                    if self.EnableMouse then self:EnableMouse(false) end
                    if self.Hide then self:Hide() end
                end
            end)
        end
    end

    -- 2. Classic Expansions (WatchFrame)
    local wf = _G.WatchFrame
    if wf then
        if wf.SetAlpha then wf:SetAlpha(0) end
        if wf.EnableMouse then wf:EnableMouse(false) end
        if wf.Hide then wf:Hide() end
        if not hookedTrackers[wf] and wf.HookScript then
            hookedTrackers[wf] = true
            wf:HookScript("OnShow", function(self)
                if sfui.questlog and sfui.questlog.is_enabled and sfui.questlog.is_enabled() then
                    if self.SetAlpha then self:SetAlpha(0) end
                    if self.EnableMouse then self:EnableMouse(false) end
                    if self.Hide then self:Hide() end
                end
            end)
        end
    end

    -- 3. Modern / Retail / Camelot (ObjectiveTrackerFrame & BlocksFrame)
    local otf = _G.ObjectiveTrackerFrame
    if otf then
        if otf.SetAlpha then otf:SetAlpha(0) end
        if otf.EnableMouse then otf:EnableMouse(false) end
        if otf.Header and otf.Header.SetAlpha then otf.Header:SetAlpha(0) end
    end

    local otbf = _G.ObjectiveTrackerBlocksFrame
    if otbf then
        if otbf.SetAlpha then otbf:SetAlpha(0) end
        if otbf.EnableMouse then otbf:EnableMouse(false) end
    end
end

local function RestoreBlizzardTrackers()
    local qwf = _G.QuestWatchFrame
    if qwf then
        if qwf.SetAlpha then qwf:SetAlpha(1) end
        if qwf.EnableMouse then qwf:EnableMouse(true) end
        if qwf.Show then qwf:Show() end
    end

    local wf = _G.WatchFrame
    if wf then
        if wf.SetAlpha then wf:SetAlpha(1) end
        if wf.EnableMouse then wf:EnableMouse(true) end
        if wf.Show then wf:Show() end
    end

    local otf = _G.ObjectiveTrackerFrame
    if otf then
        if otf.SetAlpha then otf:SetAlpha(1) end
        if otf.EnableMouse then otf:EnableMouse(true) end
        if otf.Header and otf.Header.SetAlpha then otf.Header:SetAlpha(1) end
    end

    local otbf = _G.ObjectiveTrackerBlocksFrame
    if otbf then
        if otbf.SetAlpha then otbf:SetAlpha(1) end
        if otbf.EnableMouse then otbf:EnableMouse(true) end
    end
end

-- ─── Suppression & Event Routing ────────────────────────────────────────────
local function SetupEventRouting()
    if not sfui.events or not sfui.events.RegisterEvent then return end

    -- Auto-hide in Raid Boss encounters
    sfui.events.RegisterEvent("ENCOUNTER_START", function()
        local inRaid = IsInRaid and IsInRaid()
        if inRaid then
            isRaidSuppressed = true
            if container then container:SetAlpha(0) end
        end
    end)

    sfui.events.RegisterEvent("ENCOUNTER_END", function()
        isRaidSuppressed = false
        if container then
            container:SetAlpha(1)
            Tracker.RequestRefresh(0.1)
        end
    end)

    -- Auto-hide in Pet Battles
    sfui.events.RegisterEvent("PET_BATTLE_OPENING_START", function()
        isPetBattleSuppressed = true
        if container then container:SetAlpha(0) end
    end)

    sfui.events.RegisterEvent("PET_BATTLE_CLOSE", function()
        isPetBattleSuppressed = false
        if container then
            container:SetAlpha(1)
            Tracker.RequestRefresh(0.1)
        end
    end)

    -- Zone & Map changes
    sfui.events.RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
        SuppressBlizzardTrackers()
        Tracker.RequestRefresh(0.2)
    end)
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        EnsureQuestWatchHook()
        SuppressBlizzardTrackers()
        C_Timer.After(0.5, SuppressBlizzardTrackers)
        C_Timer.After(1.5, function()
            SuppressBlizzardTrackers()
            Tracker.RequestRefresh(0.1)
        end)
    end)
    sfui.events.RegisterEvent("QUEST_LOG_UPDATE", function()
        SuppressBlizzardTrackers()
    end)
    sfui.events.RegisterEvent("QUEST_WATCH_LIST_CHANGED", function()
        SuppressBlizzardTrackers()
    end)
    sfui.events.RegisterEvent("ADDON_LOADED", function(event, loadedAddon)
        if loadedAddon == "Blizzard_ObjectiveTracker" or loadedAddon == "Blizzard_UIPanels_Game" then
            EnsureQuestWatchHook()
            SuppressBlizzardTrackers()
        end
    end)
end

-- ─── Initialization ─────────────────────────────────────────────────────────
function Tracker.Initialize()
    if Tracker.isInitialized then return end
    Tracker.isInitialized = true

    SfuiDB = SfuiDB or {}
    SfuiDB.questlogEnabled = (SfuiDB.questlogEnabled ~= false)
    SfuiDB.questlogLocked  = (SfuiDB.questlogLocked ~= false)
    SfuiDB.questlogSectionsCollapsed = SfuiDB.questlogSectionsCollapsed or {}

    CreateTrackerContainer()
    SetupEventRouting()
    Tracker.InitModules()

    if SfuiDB.questlogEnabled then
        container:Show()
        SuppressBlizzardTrackers()
        Tracker.RequestRefresh(0.1)
    else
        container:Hide()
    end
end

-- ─── Public Backward-Compatible Facade (`sfui.questlog`) ────────────────────
sfui.questlog.initialize = Tracker.Initialize
sfui.questlog.RequestRefresh = Tracker.RequestRefresh

function sfui.questlog.toggle()
    if not container then Tracker.Initialize() end
    if container:IsShown() then
        container:Hide()
        SfuiDB.questlogEnabled = false
        if RestoreBlizzardTrackers then RestoreBlizzardTrackers() end
    else
        container:Show()
        SfuiDB.questlogEnabled = true
        if SuppressBlizzardTrackers then SuppressBlizzardTrackers() end
        Tracker.RequestRefresh(0.05)
    end
end

function sfui.questlog.is_enabled()
    return SfuiDB and SfuiDB.questlogEnabled ~= false
end

function sfui.questlog.set_enabled(enabled)
    SfuiDB.questlogEnabled = (enabled ~= false)
    if container then
        if SfuiDB.questlogEnabled then
            container:Show()
            if SuppressBlizzardTrackers then SuppressBlizzardTrackers() end
            Tracker.RequestRefresh(0.05)
        else
            container:Hide()
            if RestoreBlizzardTrackers then RestoreBlizzardTrackers() end
        end
    end
end

function sfui.questlog.set_locked(locked)
    SfuiDB.questlogLocked = (locked ~= false)
    if container then
        container:EnableMouse(not SfuiDB.questlogLocked)
        if container.scrollClip then
            container.scrollClip:EnableMouse(not SfuiDB.questlogLocked)
        end
    end
end

function sfui.questlog.reset_position()
    if container then
        if SfuiDB then
            SfuiDB.questlogPoint = nil
            SfuiDB.questlogRelativePoint = nil
            SfuiDB.questlogX = nil
            SfuiDB.questlogY = nil
            SfuiDB.mythicHudPoint = nil
            SfuiDB.mythicHudRelativePoint = nil
            SfuiDB.mythicHudX = nil
            SfuiDB.mythicHudY = nil
        end
        container:ClearAllPoints()
        container:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -4, -4)
    end
end

function Tracker.RestorePosition()
    if not container then return end
    local point = SfuiDB and (SfuiDB.questlogPoint or SfuiDB.mythicHudPoint)
    local relPoint = SfuiDB and (SfuiDB.questlogRelativePoint or SfuiDB.mythicHudRelativePoint)
    local x = SfuiDB and (SfuiDB.questlogX or SfuiDB.mythicHudX)
    local y = SfuiDB and (SfuiDB.questlogY or SfuiDB.mythicHudY)

    if not point and x and x > 0 then
        point = "BOTTOMLEFT"
        relPoint = "BOTTOMLEFT"
    end

    container:ClearAllPoints()
    if x and y then
        container:SetPoint(point or "TOPRIGHT", UIParent, relPoint or "TOPRIGHT", x, y)
    else
        container:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -4, -4)
    end
end
sfui.questlog.UpdateAnchor = Tracker.RestorePosition

function sfui.questlog.unhide_all()
    if SfuiDB then
        SfuiDB.questlogSectionsCollapsed = {}
        Tracker.RequestRefresh(0.05)
    end
end

-- Refresh and state compatibility
sfui.questlog.Refresh = {
    Request = function(self, delay)
        Tracker.RequestRefresh(delay or 0.05)
    end,
}

function sfui.questlog.GetState()
    if not SfuiDB then SfuiDB = {} end
    if not SfuiDB.questlog then
        SfuiDB.questlog = {
            collapsed      = {},
            expandedQuests = {},
            hiddenQuests   = {},
            hidden         = false,
        }
    end
    return SfuiDB.questlog
end

function sfui.questlog.UpdateAnchor()
    Tracker.RestorePosition()
    Tracker.RequestRefresh(0.05)
end

function sfui.questlog.on_mythic_start()
    isMythicSuppressed = true
    if container then
        container:SetAlpha(0)
    end
end

function sfui.questlog.on_mythic_end()
    isMythicSuppressed = false
    if container then
        container:SetAlpha(1)
        Tracker.RequestRefresh(0.05)
    end
end

function sfui.questlog_debug_info()
    local poolStats = Blocks.GetPoolStats()
    local itemsHelper = sfui.tracker.helpers and sfui.tracker.helpers.items
    local itemsStats = itemsHelper and itemsHelper.GetPoolStats and itemsHelper.GetPoolStats()
    local timerHelper = sfui.tracker.helpers and sfui.tracker.helpers.timerbars
    local timerStats = timerHelper and timerHelper.GetPoolStats and timerHelper.GetPoolStats()

    local activeMods = 0
    for _, mod in ipairs(Tracker.modules or {}) do
        if mod:IsEnabled() then
            activeMods = activeMods + 1
        end
    end

    return {
        enabled        = sfui.questlog.is_enabled(),
        modules        = #(Tracker.modules or {}),
        activeModules  = activeMods,
        headersActive  = poolStats.headersActive,
        headersPooled  = poolStats.headersPooled,
        blocksActive   = poolStats.blocksActive,
        blocksPooled   = poolStats.blocksPooled,
        linesActive    = poolStats.linesActive,
        linesPooled    = poolStats.linesPooled,
        barsActive     = poolStats.barsActive,
        barsPooled     = poolStats.barsPooled,
        itemsActive    = itemsStats and itemsStats.activeButtons or 0,
        timersActive   = timerStats and timerStats.activeBars or 0,
        isSuppressed   = isRaidSuppressed or isPetBattleSuppressed or isMythicSuppressed,
        isRefreshing   = isRefreshing,
        -- Backward-compatibility fields
        activeRows     = poolStats.blocksActive,
        rowPool        = poolStats.blocksPooled,
        activeObjs     = poolStats.linesActive,
        objPool        = poolStats.linesPooled,
    }
end

-- Register module with sfui central module system
if sfui.RegisterModule then
    sfui.questlog.OnEnable = function(self) Tracker.Initialize() end
    sfui.questlog.GetDebugInfo = sfui.questlog_debug_info
    sfui.RegisterModule("questlog", sfui.questlog)
end
