local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
local GameTooltip = sfui.common.get_tooltip()  -- private addon tooltip (methods.md §3.7.2)
sfui.dungeonjournal = sfui.dungeonjournal or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/dungeonjournal/dj_sidebar.lua
--  Scrollable dungeon/raid list sidebar for the Camelot Dungeon Journal.
--
--  Features:
--    - Colored level ranges reflecting player level difficulty
--    - Available quest indicator (! X avail) and in-progress indicator on level line
--    - Right-click context menu to hide dungeons or restore hidden dungeons
--    - Interactive tooltips with complete quest breakdowns
-- ══════════════════════════════════════════════════════════════════════════════

if sfui.isRetail then return end

-- ─── Constants ────────────────────────────────────────────────────────────────
local BTN_H       = 48
local BTN_PAD     = 4
local ICON_SZ     = 32

local theme  = sfui.theme
local common = sfui.common

-- ─── DB & Hidden Dungeons Storage ─────────────────────────────────────────────
local function DJ_DB()
    return (sfui.dungeonjournal and sfui.dungeonjournal.GetDB and sfui.dungeonjournal.GetDB()) or {}
end

local function IsDungeonHidden(dungeonID)
    return (sfui.dungeonjournal and sfui.dungeonjournal.IsDungeonHidden and sfui.dungeonjournal.IsDungeonHidden(dungeonID)) or false
end

-- Forward declaration of RefreshSidebar & search query
local RefreshSidebar = nil
local currentSearchFilter = nil

local function IsDungeonInLevelRange(dungeon, playerLevel)
    if sfui.dungeonjournal and sfui.dungeonjournal.IsDungeonInLevelRange then
        return sfui.dungeonjournal.IsDungeonInLevelRange(dungeon, playerLevel)
    end
    return true
end

local sidebarFrame   = nil
local scrollFrame    = nil
local scrollContent  = nil

-- all sidebar filter toggles route through SetOption; the SFUI_DJ_SETTING_CHANGED
-- listener and SetOption itself refresh button states and the list cleanly.
local function SetShowAll(val)
    sfui.dungeonjournal.SetOption("showAllDungeons", val and true or false)
end

local function SetShowHidden(val)
    sfui.dungeonjournal.SetOption("showHiddenInSidebar", val and true or false)
end

-- ─── Difficulty Color Helper ──────────────────────────────────────────────────
local function GetLevelColorHex(level, playerLevel)
    if not level then return "ffffffff" end
    if _G.GetQuestDifficultyColor then
        local ok, color = pcall(_G.GetQuestDifficultyColor, level)
        if ok and color and color.r and color.g and color.b then
            return string.format("ff%02x%02x%02x", math.floor(color.r * 255 + 0.5), math.floor(color.g * 255 + 0.5), math.floor(color.b * 255 + 0.5))
        end
    end
    -- Fallback difficulty formula matching standard Blizzard curves
    local pLvl = playerLevel or (UnitLevel and UnitLevel("player")) or 1
    local diff = level - pLvl
    if diff >= 5 then
        return "ffff2020" -- Red: way above player level / skull
    elseif diff >= 3 then
        return "ffff7722" -- Orange: challenging / high
    elseif diff >= -2 then
        return "ffffd100" -- Yellow: optimal / matching
    elseif diff >= -6 then
        return "ff40dd40" -- Green: easy
    else
        return "ff808080" -- Gray: trivial / outleveled
    end
end

local function FormatColoredLevelRange(dungeon, playerLevel)
    local pLvl = playerLevel or (UnitLevel and UnitLevel("player")) or 1
    if dungeon._lvlStr and dungeon._lvlStrPlayerLvl == pLvl then
        return dungeon._lvlStr
    end
    local minLvl = dungeon.minLevel
    local maxLvl = dungeon.maxLevel
    local out = ""

    if minLvl and maxLvl then
        local cMin = GetLevelColorHex(minLvl, pLvl)
        local cMax = GetLevelColorHex(maxLvl, pLvl)
        if minLvl == maxLvl then
            out = string.format("|c%s[%d]|r", cMin, minLvl)
        elseif cMin == cMax then
            out = string.format("|c%s[%d - %d]|r", cMin, minLvl, maxLvl)
        else
            out = string.format("|cff666666[|r|c%s%d|r|cff555555 - |r|c%s%d|r|cff666666]|r", cMin, minLvl, cMax, maxLvl)
        end
    elseif dungeon.level then
        local low, high = tostring(dungeon.level):match("^(%d+)%s*-%s*(%d+)$")
        if low and high then
            local nLow, nHigh = tonumber(low), tonumber(high)
            local cMin = GetLevelColorHex(nLow, pLvl)
            local cMax = GetLevelColorHex(nHigh, pLvl)
            if cMin == cMax then
                out = string.format("|c%s[%d - %d]|r", cMin, nLow, nHigh)
            else
                out = string.format("|cff666666[|r|c%s%d|r|cff555555 - |r|c%s%d|r|cff666666]|r", cMin, nLow, cMax, nHigh)
            end
        else
            local single = tonumber(dungeon.level)
            if single then
                local c = GetLevelColorHex(single, pLvl)
                out = string.format("|c%s[%d]|r", c, single)
            else
                out = string.format("|cff888888[%s]|r", dungeon.level)
            end
        end
    end
    dungeon._lvlStrPlayerLvl = pLvl
    dungeon._lvlStr = out
    return out
end

local function GetDungeonSearchBlob(dungeon)
    if dungeon._searchBlob and not dungeon._searchNeedsRebuild then
        return dungeon._searchBlob
    end
    local parts = {}
    if dungeon.name then parts[#parts + 1] = dungeon.name:lower() end
    if dungeon.zone then parts[#parts + 1] = dungeon.zone:lower() end
    local hasUncached = false
    if dungeon.bosses then
        for _, boss in ipairs(dungeon.bosses) do
            if boss.name then parts[#parts + 1] = boss.name:lower() end
            if boss.items then
                for _, itemID in ipairs(boss.items) do
                    local id = type(itemID) == "table" and (itemID.id or itemID[1]) or itemID
                    local name = id and common.get_item_info(id)
                    if not name and id and _G.C_Item and _G.C_Item.GetItemNameByID then
                        name = _G.C_Item.GetItemNameByID(id)
                    end
                    if name then
                        parts[#parts + 1] = name:lower()
                    else
                        hasUncached = true
                    end
                end
            end
        end
    end
    if dungeon.quests then
        for _, q in ipairs(dungeon.quests) do
            if q.name then parts[#parts + 1] = q.name:lower() end
        end
    end
    local blob = table.concat(parts, "\n")
    dungeon._searchBlob = blob
    dungeon._searchHasUncached = hasUncached
    dungeon._searchNeedsRebuild = false
    return blob
end

-- ─── Player Faction & Quest Progress Helpers ─────────────────────────────────
local function GetPlayerFaction()
    local _, faction = sfui.common.get_player_faction()
    return faction == "horde" and "horde" or "alliance"
end

local questProgressCache = {}
local function InvalidateQuestProgressCache()
    for k in pairs(questProgressCache) do
        questProgressCache[k] = nil
    end
end

local function GetDungeonQuestProgress(dungeon)
    if not dungeon or not dungeon.quests or #dungeon.quests == 0 then
        return nil
    end

    if questProgressCache[dungeon.id] ~= nil then
        local cached = questProgressCache[dungeon.id]
        return cached ~= false and cached or nil
    end

    local playerFaction = GetPlayerFaction()
    local playerLevel   = UnitLevel("player") or 1
    local total         = 0
    local inProg        = 0
    local completed     = 0
    local available     = 0
    local locked        = 0

    local db = sfui.dj_camelot or (sfui.data and sfui.data.dj_camelot)

    for _, q in ipairs(dungeon.quests) do
        local f = q.faction and q.faction:lower() or "both"
        if f == "both" or f == playerFaction then
            total = total + 1
            local isDone = sfui.dungeonjournal.IsQuestCompleted(q.id)

            if isDone then
                completed = completed + 1
            else
                local isInLog = sfui.dungeonjournal.IsQuestActive(q.id)

                if isInLog then
                    inProg = inProg + 1
                else
                    local minLvl = q.minLevel or (db and db.questMinLevels and db.questMinLevels[q.id]) or 1
                    if playerLevel >= minLvl then
                        available = available + 1
                    else
                        locked = locked + 1
                    end
                end
            end
        end
    end

    if total == 0 then
        questProgressCache[dungeon.id] = false
        return nil
    end

    -- Notice text on the level line:
    -- - If all quests are completed: nothing (no progress text when completed)
    -- - If 0 progress and 0 available: nothing (no progress text when = 0)
    -- - If quests are available to pick up: show "! X avail"
    -- - If quests are in log: show "p X/T"
    local noticeText = nil
    if completed < total then
        if available > 0 and inProg > 0 then
            noticeText = string.format("|cffffd100! %d|r |cff00e5ffp %d|r", available, inProg)
        elseif available > 0 then
            noticeText = string.format("|cffffd100! %d avail|r", available)
        elseif inProg > 0 then
            noticeText = string.format("|cff00e5ffp %d/%d|r", inProg, total)
        end
    end

    local res = {
        total      = total,
        inProg     = inProg,
        completed  = completed,
        available  = available,
        locked     = locked,
        noticeText = noticeText,
    }
    questProgressCache[dungeon.id] = res
    return res
end

-- ─── Context Menu Frame (Custom Fallback & MenuUtil) ──────────────────────────

local function OpenDungeonContextMenu(owner, dungeon)
    if not dungeon then return end

    local isHidden = sfui.dungeonjournal.IsDungeonHidden(dungeon.id)
    local arePinsHidden = sfui.dungeonjournal.AreDungeonPinsHidden(dungeon.id)
    local _, _, _, totalHidden = sfui.dungeonjournal.GetHiddenCounts()

    local items = {}

    if isHidden then
        table.insert(items, {
            text = "unhide " .. (dungeon.name and dungeon.name:lower() or "dungeon"),
            color = { 0.4, 1.0, 0.4 },
            func = function()
                sfui.dungeonjournal.SetDungeonHidden(dungeon.id, false)
                if sfui.print then
                    sfui.print(string.format("restored |cffffd100%s|r to adventure guide and map.", dungeon.name or "dungeon"))
                end
            end,
        })
    else
        table.insert(items, {
            text = "hide " .. (dungeon.name and dungeon.name:lower() or "dungeon") .. " & pins",
            color = { 1.0, 0.4, 0.4 },
            func = function()
                sfui.dungeonjournal.SetDungeonHidden(dungeon.id, true)
                if sfui.print then
                    sfui.print(string.format("hidden |cffffd100%s|r and its map pins. |cff00ccff|Hsfui_undo:dungeon:%s|h[undo]|h|r", dungeon.name or "dungeon", dungeon.id))
                end
            end,
        })

        if arePinsHidden then
            table.insert(items, {
                text = "unhide map pins",
                color = { 0.4, 1.0, 0.4 },
                func = function()
                    sfui.dungeonjournal.SetDungeonPinsHidden(dungeon.id, false)
                    if sfui.print then
                        sfui.print(string.format("restored map pins for |cffffd100%s|r.", dungeon.name or "dungeon"))
                    end
                end,
            })
        else
            table.insert(items, {
                text = "hide map pins only",
                color = { 1.0, 0.7, 0.4 },
                func = function()
                    sfui.dungeonjournal.SetDungeonPinsHidden(dungeon.id, true)
                    if sfui.print then
                        sfui.print(string.format("hidden map pins for |cffffd100%s|r. |cff00ccff|Hsfui_undo:pins:%s|h[undo]|h|r", dungeon.name or "dungeon", dungeon.id))
                    end
                end,
            })
        end
    end

    if totalHidden > 0 then
        table.insert(items, {
            text = "manage hidden items (" .. totalHidden .. ")...",
            color = { 1.0, 0.82, 0.0 },
            func = function()
                sfui.dungeonjournal.OpenHiddenManager()
            end,
        })
        table.insert(items, {
            text = "restore all hidden (" .. totalHidden .. ")",
            color = { 0.5, 0.8, 1.0 },
            func = function()
                sfui.dungeonjournal.RestoreAllHidden()
            end,
        })
    end

    local showingAll = DJ_DB().showAllDungeons == true
    table.insert(items, {
        text = showingAll and "filter to level range" or "show all dungeons",
        color = { 0.4, 0.8, 1.0 },
        func = function() SetShowAll(not showingAll) end,
    })

    table.insert(items, {
        text = "cancel",
        color = { 0.6, 0.6, 0.6 },
        func = function() end,
    })

    sfui.dungeonjournal.ShowContextMenu(owner, dungeon.name and dungeon.name:lower() or "dungeon", items)
end

-- ─── Pool helpers ─────────────────────────────────────────────────────────────
local sidebarButtons = {}

local dungeonWishlistCache   = {}
local dungeonUpgradeCache    = {}
local dungeonUpgradePending  = {}
local pendingByItemID        = {}
local requestedItemLoads     = {}
local upgradeQueue           = {}
local upgradeQueueHead       = 1
local upgradeQueuedSet       = {}
local upgradeWorkerScheduled = false
local UPGRADE_BATCH_SIZE     = 3
local dirtyRefresh           = false

local function IsSidebarVisible()
    if not sidebarFrame then return false end
    if sidebarFrame.IsVisible then
        return sidebarFrame:IsVisible() == true
    end
    return sidebarFrame:IsShown() == true
end

local function InvalidateWishlistCache()
    for k in pairs(dungeonWishlistCache) do
        dungeonWishlistCache[k] = nil
    end
end

local function InvalidateUpgradeCache()
    for k in pairs(dungeonUpgradeCache) do
        dungeonUpgradeCache[k] = nil
    end
    for k in pairs(dungeonUpgradePending) do
        dungeonUpgradePending[k] = nil
    end
    for k in pairs(pendingByItemID) do
        pendingByItemID[k] = nil
    end
    for i = #upgradeQueue, 1, -1 do
        upgradeQueue[i] = nil
    end
    upgradeQueueHead = 1
    for k in pairs(upgradeQueuedSet) do
        upgradeQueuedSet[k] = nil
    end
end

local function ApplyButtonUpgradeDisplay(btn, upgCount)
    btn.upgCount = upgCount or 0
    local upgSuffix = (btn.upgCount > 0) and string.format("  |cff33ff88+%d upg|r", btn.upgCount) or ""
    if btn.prog and btn.prog.noticeText and btn.prog.noticeText ~= "" then
        if btn.lvlStr ~= "" then
            btn.levelText:SetText(btn.lvlStr .. "  " .. btn.prog.noticeText .. upgSuffix)
        else
            btn.levelText:SetText(btn.prog.noticeText .. upgSuffix)
        end
        btn.levelText:Show()
    elseif btn.lvlStr ~= "" or upgSuffix ~= "" then
        btn.levelText:SetText((btn.lvlStr or "") .. upgSuffix)
        btn.levelText:Show()
    else
        btn.levelText:Hide()
    end
end

local function DungeonHasWishlist(dungeon)
    if not dungeon or not dungeon.bosses or not (sfui.dungeonjournal and sfui.dungeonjournal.IsWishlisted) then
        return false, 0
    end
    local cached = dungeonWishlistCache[dungeon.id]
    if cached ~= nil then
        return cached > 0, cached
    end
    local count = 0
    for _, b in ipairs(dungeon.bosses) do
        for _, it in ipairs(b.items or {}) do
            local id = type(it) == "table" and (it.id or it[1]) or it
            id = tonumber(id)
            if id and sfui.dungeonjournal.IsWishlisted(id) then
                count = count + 1
            end
        end
    end
    dungeonWishlistCache[dungeon.id] = count
    return count > 0, count
end

local function ComputeDungeonUpgradeCount(dungeon)
    if not dungeon or not dungeon.bosses or not (sfui.gear and sfui.gear.EvaluateItemUpgrade) then
        return 0, false
    end
    local activeSpecID = common and common.get_current_spec_id and common.get_current_spec_id()
    if not activeSpecID or activeSpecID == 0 then
        return 0, false
    end
    local count = 0
    local hasUnloaded = false
    local seen = {}
    for _, b in ipairs(dungeon.bosses) do
        for _, it in ipairs(b.items or {}) do
            local id = tonumber(type(it) == "table" and (it.id or it[1]) or it)
            if id and not seen[id] then
                seen[id] = true
                local name, link = common.get_item_info(id)
                if name then
                    local eval = sfui.gear.EvaluateItemUpgrade(link or id, activeSpecID, true)
                    if eval and eval.isUpgrade and not eval.isOffSpec then
                        count = count + 1
                    end
                else
                    hasUnloaded = true
                    pendingByItemID[id] = pendingByItemID[id] or {}
                    pendingByItemID[id][dungeon.id] = true
                    if not requestedItemLoads[id] then
                        requestedItemLoads[id] = true
                        if common.request_item_load then
                            common.request_item_load(id)
                        end
                    end
                end
            end
        end
    end
    return count, hasUnloaded
end

local function UpdateButtonForDungeon(dID, count)
    for _, btn in ipairs(sidebarButtons) do
        if btn:IsShown() and btn.dungeonRef and btn.dungeonRef.id == dID then
            ApplyButtonUpgradeDisplay(btn, count)
            return
        end
    end
end

local function PopUpgradeQueue()
    if upgradeQueueHead > #upgradeQueue then
        for i = #upgradeQueue, 1, -1 do upgradeQueue[i] = nil end
        upgradeQueueHead = 1
        return nil
    end
    local d = upgradeQueue[upgradeQueueHead]
    upgradeQueue[upgradeQueueHead] = nil
    upgradeQueueHead = upgradeQueueHead + 1
    if upgradeQueueHead > #upgradeQueue then
        for i = #upgradeQueue, 1, -1 do upgradeQueue[i] = nil end
        upgradeQueueHead = 1
    end
    return d
end

local function ProcessUpgradeQueue()
    upgradeWorkerScheduled = false
    if not IsSidebarVisible() then
        for i = #upgradeQueue, 1, -1 do
            upgradeQueue[i] = nil
        end
        upgradeQueueHead = 1
        for k in pairs(upgradeQueuedSet) do
            upgradeQueuedSet[k] = nil
        end
        return
    end
    local processed = 0
    while upgradeQueueHead <= #upgradeQueue and processed < UPGRADE_BATCH_SIZE do
        local dungeon = PopUpgradeQueue()
        if dungeon and dungeon.id then
            upgradeQueuedSet[dungeon.id] = nil
            if dungeonUpgradeCache[dungeon.id] == nil then
                local count, hasUnloaded = ComputeDungeonUpgradeCount(dungeon)
                dungeonUpgradeCache[dungeon.id] = count
                dungeonUpgradePending[dungeon.id] = hasUnloaded or nil
                processed = processed + 1
                UpdateButtonForDungeon(dungeon.id, count)
            end
        end
    end
    if upgradeQueueHead <= #upgradeQueue and _G.C_Timer and _G.C_Timer.After and not upgradeWorkerScheduled then
        upgradeWorkerScheduled = true
        _G.C_Timer.After(0, ProcessUpgradeQueue)
    end
end

local function ScheduleUpgradeWorker()
    if upgradeWorkerScheduled or upgradeQueueHead > #upgradeQueue then return end
    if _G.C_Timer and _G.C_Timer.After then
        upgradeWorkerScheduled = true
        _G.C_Timer.After(0, ProcessUpgradeQueue)
    else
        while upgradeQueueHead <= #upgradeQueue do
            local dungeon = PopUpgradeQueue()
            if dungeon and dungeon.id then
                upgradeQueuedSet[dungeon.id] = nil
                if dungeonUpgradeCache[dungeon.id] == nil then
                    local count, hasUnloaded = ComputeDungeonUpgradeCount(dungeon)
                    dungeonUpgradeCache[dungeon.id] = count
                    dungeonUpgradePending[dungeon.id] = hasUnloaded or nil
                    UpdateButtonForDungeon(dungeon.id, count)
                end
            end
        end
    end
end

local function EnqueueUpgradeCalc(dungeon)
    if not dungeon or not dungeon.id or upgradeQueuedSet[dungeon.id] then return end
    if not (sfui.gear and sfui.gear.EvaluateItemUpgrade) then return end
    upgradeQueuedSet[dungeon.id] = true
    upgradeQueue[#upgradeQueue + 1] = dungeon
end

local function GetCachedDungeonUpgradeCount(dungeon)
    if not dungeon or not dungeon.id then return 0 end
    local cached = dungeonUpgradeCache[dungeon.id]
    if cached ~= nil then
        return cached
    end
    if IsSidebarVisible() then
        EnqueueUpgradeCalc(dungeon)
    end
    return 0
end

local function OnSidebarButtonEnter(self)
    local dungeon = self.dungeonRef
    if not dungeon then return end
    local prog = self.prog
    local uc = self.upgCount or 0
    local hasWish = self.hasWish
    local wishCount = self.wishCount or 0
    local isHidden = self._isHidden
    local arePinsHidden = self._arePinsHidden
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(dungeon.name or "dungeon", 1, 0.82, 0)
    if dungeon.level then
        GameTooltip:AddLine("level: " .. dungeon.level, 0.85, 0.85, 0.85)
    end
    if dungeon.zone then
        GameTooltip:AddLine("zone: " .. dungeon.zone, 0.65, 0.65, 0.65)
    end
    if prog then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format("dungeon quests (%d total):", prog.total), 1, 0.82, 0)
        if prog.available > 0 then
            GameTooltip:AddLine(string.format("  - available to pick up: %d", prog.available), 1, 0.82, 0)
        end
        if prog.inProg > 0 then
            GameTooltip:AddLine(string.format("  - in progress (in log): %d", prog.inProg), 0, 0.9, 1)
        end
        if prog.completed > 0 then
            GameTooltip:AddLine(string.format("  - completed: %d", prog.completed), 0, 1, 0)
        end
        if prog.locked > 0 then
            GameTooltip:AddLine(string.format("  - locked (requires higher level): %d", prog.locked), 0.7, 0.4, 0.4)
        end
    end

    if uc > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format("|cff33ff88+%d spec upgrade%s cached|r", uc, uc == 1 and "" or "s"), 0.2, 1, 0.53)
    end

    if hasWish then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:12:12:0:0|t |cffcc44ffwishlist drop%s active (%d)|r", (wishCount > 1 and "s" or ""), wishCount), 1, 1, 1)
    end

    if isHidden then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffff5555[this dungeon is hidden]|r", 1, 0.35, 0.35)
        GameTooltip:AddLine("|cff00ff00<right-click to unhide dungeon>|r", 0, 1, 0)
    elseif arePinsHidden then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffffaa00[map pins for this dungeon are hidden]|r", 1, 0.7, 0.3)
        GameTooltip:AddLine("|cff888888<right-click for hide/unhide options>|r", 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff888888<right-click for hide options>|r", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function OnSidebarButtonLeave()
    GameTooltip:Hide()
end

local function OnSidebarButtonClick(self, mouseButton)
    local dRef = self.dungeonRef
    if not dRef then return end
    if mouseButton == "RightButton" then
        OpenDungeonContextMenu(self, dRef)
    else
        if sfui.dungeonjournal and sfui.dungeonjournal.SelectDungeon then
            sfui.dungeonjournal.SelectDungeon(dRef.id)
        end
    end
end

local function AcquireButton(pool, parent)
    for _, btn in ipairs(pool) do
        if not btn:IsShown() then
            if btn.wishIcon then btn.wishIcon:Hide() end
            return btn
        end
    end
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(BTN_H)
    common.apply_flat_backdrop(btn, nil, { 0, 0, 0, 0 })

    -- Icon
    local ico = btn:CreateTexture(nil, "ARTWORK")
    btn.icon = ico
    ico:SetSize(ICON_SZ, ICON_SZ)
    ico:SetPoint("LEFT", 6, 0)
    ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Wishlist gem icon on the right side of the dungeon button
    local wishIcon = btn:CreateTexture(nil, "OVERLAY")
    btn.wishIcon = wishIcon
    wishIcon:SetSize(14, 14)
    wishIcon:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    wishIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_3")
    wishIcon:Hide()

    -- Name
    local name = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.nameText = name
    name:SetPoint("TOPLEFT", ico, "TOPRIGHT", 6, -6)
    name:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -6, -6)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)

    -- Level badge & Quest Notifier
    local badge = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.levelText = badge
    badge:SetPoint("BOTTOMLEFT", ico, "BOTTOMRIGHT", 6, 6)
    badge:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -4, 6)
    badge:SetJustifyH("LEFT")
    badge:SetWordWrap(false)

    -- Highlight texture
    local hi = btn:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hi:SetBlendMode("ADD")
    hi:SetAlpha(0.25)

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnEnter", OnSidebarButtonEnter)
    btn:SetScript("OnLeave", OnSidebarButtonLeave)
    btn:SetScript("OnClick", OnSidebarButtonClick)

    pool[#pool + 1] = btn
    return btn
end

local function ReleaseAll(pool)
    if sfui.dungeonjournal and sfui.dungeonjournal.ReleaseAll then
        sfui.dungeonjournal.ReleaseAll(pool)
    end
end

-- ─── Main Refresh ─────────────────────────────────────────────────────────────
local isRefreshing = false

local function RefreshSidebarImpl()
    if not sidebarFrame then return end

    if sidebarFrame.UpdateFilterState then
        sidebarFrame.UpdateFilterState()
    end
    if sidebarFrame.UpdateEyeState then
        sidebarFrame.UpdateEyeState()
    end
    dirtyRefresh = false

    ReleaseAll(sidebarButtons)

    local dj         = sfui.dungeonjournal
    local list       = dj and dj.GetItemHelpers and dj.GetItemHelpers().GetList() or {}
    local selectedID = dj and dj.GetSelectedDungeonID and dj.GetSelectedDungeonID()
    local pal        = theme.GetPalette()
    local accent     = pal and pal.accentColor or { 1, 0.78, 0.2, 1 }
    local playerLevel= UnitLevel("player") or 1

    local isFiltering = (currentSearchFilter ~= nil and currentSearchFilter ~= "")
    local showAll     = DJ_DB().showAllDungeons == true
    local currentInst = (not showAll) and dj and dj.GetCurrentInstanceDungeon and dj.GetCurrentInstanceDungeon() or nil

    local displayList = list
    if not showAll then
        local matched = {}
        for _, dungeon in ipairs(list) do
            if IsDungeonInLevelRange(dungeon, playerLevel) or (currentInst and currentInst.id == dungeon.id) then
                matched[#matched + 1] = dungeon
            end
        end
        displayList = matched
    end

    if isFiltering then
        local matched = {}
        for _, dungeon in ipairs(displayList) do
            local blob = GetDungeonSearchBlob(dungeon)
            if blob:find(currentSearchFilter, 1, true) then
                matched[#matched + 1] = dungeon
            end
        end
        displayList = matched
    end

    local showHidden = DJ_DB().showHiddenInSidebar == true

    -- Auto-select first visible dungeon if currently selected is not in results
    if #displayList > 0 then
        local isSelectedVisible = false
        for _, d in ipairs(displayList) do
            if d.id == selectedID and (showHidden or not IsDungeonHidden(d.id)) then
                isSelectedVisible = true
                break
            end
        end
        if not isSelectedVisible then
            selectedID = nil
            for _, d in ipairs(displayList) do
                if showHidden or not IsDungeonHidden(d.id) then
                    selectedID = d.id
                    break
                end
            end
            if not selectedID then
                selectedID = displayList[1].id
            end
            if selectedID then
                if dj and dj.SetSelectedDungeonID then
                    dj.SetSelectedDungeonID(selectedID)
                else
                    DJ_DB().lastDungeon = selectedID
                end
            end
        end
    end

    local y     = 0
    local total = 0

    for _, dungeon in ipairs(displayList) do
        local isHidden = IsDungeonHidden(dungeon.id)
        if showHidden or not isHidden then
            local btn = AcquireButton(sidebarButtons, scrollContent)

            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT",  scrollContent, "TOPLEFT",  0, -y)
            btn:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", 0, -y)
            btn:SetHeight(BTN_H)

            -- Icon
            local textureLoaded = false
            if dungeon.iconStr then
                btn.icon:SetTexture(dungeon.iconStr)
                if btn.icon:GetTexture() then textureLoaded = true end
            end
            if not textureLoaded and dungeon.icon then
                btn.icon:SetTexture(dungeon.icon)
                if btn.icon:GetTexture() then textureLoaded = true end
            end
            if not textureLoaded then
                btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            end

            local arePinsHidden = sfui.dungeonjournal.AreDungeonPinsHidden(dungeon.id)

            if isHidden then
                btn.icon:SetDesaturated(true)
                btn.icon:SetAlpha(0.4)
                btn.nameText:SetText((dungeon.name or "?") .. " |cffff5555[hidden]|r")
                btn.nameText:SetTextColor(0.65, 0.55, 0.55, 0.9)
                btn:SetBackdropColor(0.12, 0.05, 0.05, 0.4)
                btn:SetBackdropBorderColor(0.5, 0.2, 0.2, 0.4)
            else
                btn.icon:SetDesaturated(false)
                btn.icon:SetAlpha(1.0)
                local pinSuffix = arePinsHidden and " |cff888888[pins hidden]|r" or ""
                btn.nameText:SetText((dungeon.name or "?") .. pinSuffix)
                local isSelected = (dungeon.id == selectedID)
                if isSelected then
                    btn.nameText:SetTextColor(accent[1], accent[2], accent[3], 1)
                    btn:SetBackdropColor(0.14, 0.14, 0.18, 0.95)
                    btn:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.6)
                else
                    btn.nameText:SetTextColor(0.85, 0.85, 0.85, 1)
                    btn:SetBackdropColor(0.08, 0.08, 0.10, 0.0)
                    btn:SetBackdropBorderColor(0, 0, 0, 0)
                end
            end

            -- Colored level range & available quest indicator
            local lvlStr = FormatColoredLevelRange(dungeon, playerLevel)
            local prog   = GetDungeonQuestProgress(dungeon)

            -- Wishlist & upgrade indicators
            local hasWish, wishCount = DungeonHasWishlist(dungeon)
            local upgCount = GetCachedDungeonUpgradeCount(dungeon)
            if btn.wishIcon then
                if hasWish then
                    btn.wishIcon:Show()
                    btn.nameText:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -22, -6)
                    btn.levelText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -22, 6)
                else
                    btn.wishIcon:Hide()
                    btn.nameText:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -6, -6)
                    btn.levelText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -4, 6)
                end
            end

            btn.dungeonRef     = dungeon
            btn.lvlStr         = lvlStr
            btn.prog           = prog
            btn.hasWish        = hasWish
            btn.wishCount      = wishCount
            btn._isHidden      = isHidden
            btn._arePinsHidden = arePinsHidden
            ApplyButtonUpgradeDisplay(btn, upgCount)

            btn:Show()
            y     = y + BTN_H + BTN_PAD
            total = total + 1
        end
    end

    if total == 0 then
        if not sidebarFrame.emptyState then
            local empty = CreateFrame("Frame", nil, scrollContent, "BackdropTemplate")
            sidebarFrame.emptyState = empty
            empty:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 6, -20)
            empty:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", -6, -20)
            empty:SetHeight(120)

            local msg = empty:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            empty.msg = msg
            msg:SetPoint("TOP", empty, "TOP", 0, -8)
            msg:SetWidth(168)
            msg:SetJustifyH("CENTER")

            local btn = CreateFrame("Button", nil, empty, "BackdropTemplate")
            empty.btn = btn
            btn:SetSize(130, 24)
            btn:SetPoint("TOP", msg, "BOTTOM", 0, -12)
            common.apply_flat_backdrop(btn, { 0.12, 0.12, 0.16, 0.95 }, { 1, 0.78, 0.2, 0.6 })

            local bText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            btn.text = bText
            bText:SetPoint("CENTER")
            bText:SetTextColor(1, 0.82, 0, 1)

            local hi = btn:CreateTexture(nil, "HIGHLIGHT")
            hi:SetAllPoints()
            hi:SetColorTexture(1, 1, 1, 0.15)
        end

        local empty = sidebarFrame.emptyState
        local db = DJ_DB()
        local hiddenCount = 0
        for _, d in ipairs(displayList) do
            if IsDungeonHidden(d.id) then
                hiddenCount = hiddenCount + 1
            end
        end

        if hiddenCount > 0 and #displayList == hiddenCount then
            empty.msg:SetText(string.format("all dungeons in this list are hidden (%d hidden).", hiddenCount))
            empty.btn:Show()
            if db.showHiddenInSidebar then
                empty.btn.text:SetText("restore all")
                empty.btn:SetScript("OnClick", function()
                    sfui.dungeonjournal.RestoreAllHidden()
                end)
            else
                empty.btn.text:SetText("show hidden")
                empty.btn:SetScript("OnClick", function() SetShowHidden(true) end)
            end
            empty:Show()
        elseif isFiltering then
            if not showAll then
                empty.msg:SetText(string.format("no dungeons matching search in your level range (level %d).", playerLevel))
                empty.btn:Show()
                empty.btn.text:SetText("show all dungeons")
                empty.btn:SetScript("OnClick", function() SetShowAll(true) end)
            else
                empty.msg:SetText("no dungeons found matching search.")
                empty.btn:Show()
                empty.btn.text:SetText("clear search")
                empty.btn:SetScript("OnClick", function()
                    if sidebarFrame.searchBox then
                        sidebarFrame.searchBox:SetText("")
                    end
                end)
            end
            empty:Show()
        elseif not showAll then
            local tabLabel = (dj and dj.GetSelectedTab and dj.GetSelectedTab() == "raids") and "raids" or "dungeons"
            empty.msg:SetText(string.format("no %s found in your level range (level %d).", tabLabel, playerLevel))
            empty.btn:Show()
            empty.btn.text:SetText(string.format("show all %s", tabLabel))
            empty.btn:SetScript("OnClick", function() SetShowAll(true) end)
            empty:Show()
        else
            empty.msg:SetText("no dungeons available.")
            empty.btn:Hide()
            empty:Show()
        end
    else
        if sidebarFrame.emptyState then
            sidebarFrame.emptyState:Hide()
        end
    end


    -- Size the scroll content
    local contentH = math.max(1, y)
    scrollContent:SetHeight(contentH)
    if scrollFrame and scrollFrame.ScrollBar and scrollFrame.ScrollBar.UpdateVisibility then
        scrollFrame.ScrollBar:UpdateVisibility()
    end

    if upgradeQueueHead <= #upgradeQueue and IsSidebarVisible() then
        ScheduleUpgradeWorker()
    end
end

RefreshSidebar = function()
    if not sidebarFrame or isRefreshing then return end
    isRefreshing = true
    local ok, err = pcall(RefreshSidebarImpl)
    isRefreshing = false
    if not ok and sfui.error then
        sfui.error("RefreshSidebar: " .. tostring(err))
    end
end

-- ─── Frame creation ────────────────────────────────────────────────────────────
local function OnFrameCreated(arg1, arg2)
    local payload = (type(arg1) == "table" and arg1) or arg2
    if not payload or not payload.sidebarFrame then return end
    if scrollFrame then return end -- already initialized

    sidebarFrame = payload.sidebarFrame

    -- 1. Eye Button (show/hide hidden dungeons)
    local eyeBtn = common.create_icon_toggle(sidebarFrame, {
        icon   = "Interface\\Icons\\INV_Misc_Eye_01",
        getter = function() return DJ_DB().showHiddenInSidebar == true end,
        setter = function(val) SetShowHidden(val) end,
        tooltip = function(_, tip)
            tip:AddLine("show hidden dungeons", 1, 0.82, 0)
            if DJ_DB().showHiddenInSidebar then
                tip:AddLine("hidden dungeons are currently visible (dimmed with [hidden] badge).\nclick to hide them from the sidebar.", 0.85, 0.85, 0.85, true)
            else
                tip:AddLine("click to reveal hidden dungeons dimmed in the sidebar so you can review or unhide them.", 0.85, 0.85, 0.85, true)
            end
            local _, _, _, total = sfui.dungeonjournal.GetHiddenCounts()
            if total > 0 then
                tip:AddLine(" ")
                tip:AddLine(string.format("|cff00ff00%d hidden item%s currently in database|r", total, total > 1 and "s" or ""), 0, 1, 0)
            end
        end,
    })
    sidebarFrame.eyeBtn = eyeBtn
    eyeBtn:SetPoint("TOPRIGHT", sidebarFrame, "TOPRIGHT", -4, -4)
    sidebarFrame.UpdateEyeState = function() eyeBtn:UpdateState() end

    -- 2. "All" Button (toggle show all dungeons vs level range)
    local allBtn = common.create_icon_toggle(sidebarFrame, {
        width  = 26,
        text   = "all",
        getter = function() return DJ_DB().showAllDungeons == true end,
        setter = function(val) SetShowAll(val) end,
        tooltip = function(_, tip)
            local pLvl = UnitLevel("player") or 1
            tip:AddLine("show all dungeons", 1, 0.82, 0)
            if DJ_DB().showAllDungeons then
                tip:AddLine(string.format("currently showing all dungeons regardless of level.\nclick to filter by your level range (level %d).", pLvl), 0.85, 0.85, 0.85, true)
            else
                tip:AddLine(string.format("currently showing only dungeons within your level range (level %d).\nclick to show all dungeons.", pLvl), 0.85, 0.85, 0.85, true)
            end
        end,
    })
    sidebarFrame.allBtn = allBtn
    allBtn:SetPoint("RIGHT", eyeBtn, "LEFT", -3, 0)
    sidebarFrame.UpdateFilterState = function() allBtn:UpdateState() end

    -- 3. Search Box Container
    local searchContainer = CreateFrame("Frame", nil, sidebarFrame, "BackdropTemplate")
    sidebarFrame.searchContainer = searchContainer
    searchContainer:SetPoint("TOPLEFT",  sidebarFrame, "TOPLEFT",  4, -4)
    searchContainer:SetPoint("TOPRIGHT", allBtn,       "TOPLEFT", -3, 0)
    searchContainer:SetHeight(22)
    common.apply_flat_backdrop(searchContainer, { 0.04, 0.04, 0.06, 0.9 }, { 0.20, 0.20, 0.25, 0.8 })

    local searchIcon = searchContainer:CreateTexture(nil, "ARTWORK")
    searchIcon:SetSize(12, 12)
    searchIcon:SetPoint("LEFT", searchContainer, "LEFT", 5, 0)
    searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    searchIcon:SetVertexColor(0.6, 0.6, 0.6, 0.8)

    local clearBtn = CreateFrame("Button", nil, searchContainer)
    clearBtn:SetSize(14, 14)
    clearBtn:SetPoint("RIGHT", searchContainer, "RIGHT", -3, 0)
    clearBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    clearBtn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
    clearBtn:Hide()

    local searchBox = CreateFrame("EditBox", nil, searchContainer)
    sidebarFrame.searchBox = searchBox
    searchBox:SetPoint("TOPLEFT",  searchIcon, "TOPRIGHT",    4, 0)
    searchBox:SetPoint("BOTTOMRIGHT", clearBtn, "BOTTOMLEFT", -2, 0)
    searchBox:SetFontObject("GameFontHighlightSmall")
    searchBox:SetAutoFocus(false)
    searchBox:SetTextInsets(0, 0, 0, 0)

    local placeholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", searchBox, "LEFT", 0, 0)
    placeholder:SetText("search...")
    placeholder:SetTextColor(0.45, 0.45, 0.5, 0.7)

    clearBtn:SetScript("OnClick", function()
        searchBox:SetText("")
        searchBox:ClearFocus()
    end)

    searchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        if text and text:match("%S") then
            placeholder:Hide()
            clearBtn:Show()
            currentSearchFilter = text:lower():match("^%s*(.-)%s*$")
            if common and common.debounce then
                common.debounce("dj_sidebar_search", 0.15, RefreshSidebar)
            else
                RefreshSidebar()
            end
        else
            placeholder:Show()
            clearBtn:Hide()
            if currentSearchFilter ~= nil then
                currentSearchFilter = nil
                RefreshSidebar()
            end
        end
    end)

    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)

    searchBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then
            placeholder:Show()
        end
    end)

    searchBox:SetScript("OnEditFocusGained", function(self)
        placeholder:Hide()
    end)

    -- ScrollFrame inside the sidebar container (anchored below search box)
    scrollFrame = CreateFrame("ScrollFrame", "SfuiDJSidebarScroll", sidebarFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",    searchContainer, "BOTTOMLEFT",  0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT",sidebarFrame,    "BOTTOMRIGHT", -22, 4)

    local SCROLL_W = 174
    scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetSize(SCROLL_W, 1)
    scrollFrame:SetScrollChild(scrollContent)

    if scrollFrame.ScrollBar and common.style_scrollbar then
        common.style_scrollbar(scrollFrame.ScrollBar)
    end

    -- Register refresh function with orchestrator
    if sfui.dungeonjournal and sfui.dungeonjournal._registerSidebar then
        sfui.dungeonjournal._registerSidebar(RefreshSidebar)
    end

    dirtyRefresh = true
    if sidebarFrame.HookScript then
        sidebarFrame:HookScript("OnShow", function()
            if sidebarFrame._syncItemEvents then
                sidebarFrame._syncItemEvents(true)
            end
            if dirtyRefresh then
                dirtyRefresh = false
                RefreshSidebar()
            elseif upgradeQueueHead <= #upgradeQueue then
                ScheduleUpgradeWorker()
            end
        end)
        sidebarFrame:HookScript("OnHide", function()
            if sidebarFrame._syncItemEvents then
                sidebarFrame._syncItemEvents(false)
            end
        end)
    end
end

sfui.dungeonjournal._initSidebar = OnFrameCreated

local function DebouncedSidebarRefresh()
    if IsSidebarVisible() and RefreshSidebar then
        RefreshSidebar()
    else
        dirtyRefresh = true
    end
end

-- Listen for clear-cache, wishlist, gear, and setting messages
if sfui.events and sfui.events.RegisterMessage then
    sfui.events.RegisterMessage("SFUI_DJ_CLEAR_CACHE", function()
        InvalidateQuestProgressCache()
        InvalidateWishlistCache()
        InvalidateUpgradeCache()
        ReleaseAll(sidebarButtons)
        if IsSidebarVisible() then
            RefreshSidebar()
        else
            dirtyRefresh = true
        end
    end)
    sfui.events.RegisterMessage("SFUI_DJ_WISHLIST_UPDATED", function()
        InvalidateWishlistCache()
        if IsSidebarVisible() then
            RefreshSidebar()
        else
            dirtyRefresh = true
        end
    end)
    sfui.events.RegisterMessage("SFUI_EQUIPMENT_DELTA", function()
        InvalidateUpgradeCache()
        if IsSidebarVisible() then
            common.debounce("dj_sidebar_upgrades", 0.15, DebouncedSidebarRefresh)
        else
            dirtyRefresh = true
        end
    end)
    sfui.events.RegisterMessage("SFUI_ROLE_CONTEXT_CHANGED", function()
        InvalidateUpgradeCache()
        if IsSidebarVisible() then
            common.debounce("dj_sidebar_upgrades", 0.15, DebouncedSidebarRefresh)
        else
            dirtyRefresh = true
        end
    end)
    sfui.events.RegisterMessage("SFUI_DJ_SETTING_CHANGED", function(_, key)
        if key == "showAllDungeons" or key == "showHiddenInSidebar" or key == "hiddenDungeons" or key == "restoreAll" then
            if IsSidebarVisible() then
                if sidebarFrame.UpdateFilterState then sidebarFrame.UpdateFilterState() end
                if sidebarFrame.UpdateEyeState then sidebarFrame.UpdateEyeState() end
                RefreshSidebar()
            else
                dirtyRefresh = true
            end
        end
    end)
end

-- Live update when quests, gear, talents, or item cache change
if sfui.events and sfui.events.RegisterEvent then
    local function OnQuestLogChanged()
        InvalidateQuestProgressCache()
        if IsSidebarVisible() then
            common.debounce("dj_sidebar_quests", 0.15, DebouncedSidebarRefresh)
        else
            dirtyRefresh = true
        end
    end
    local function OnUpgradeContextChanged()
        InvalidateUpgradeCache()
        if IsSidebarVisible() then
            common.debounce("dj_sidebar_upgrades", 0.15, DebouncedSidebarRefresh)
        else
            dirtyRefresh = true
        end
    end
    local function OnUpgradeItemLoaded(_, itemID, success)
        if not itemID or not pendingByItemID[itemID] then return end
        local touched = pendingByItemID[itemID]
        pendingByItemID[itemID] = nil
        if success == false then return end
        for dID in pairs(touched) do
            dungeonUpgradeCache[dID] = nil
            dungeonUpgradePending[dID] = nil
        end
        if not IsSidebarVisible() then
            dirtyRefresh = true
            return
        end
        for _, btn in ipairs(sidebarButtons) do
            local d = btn.dungeonRef
            if btn:IsShown() and d and d.id and touched[d.id] then
                if d._searchHasUncached then
                    d._searchNeedsRebuild = true
                end
                local count, hasUnloaded = ComputeDungeonUpgradeCount(d)
                dungeonUpgradeCache[d.id] = count
                dungeonUpgradePending[d.id] = hasUnloaded or nil
                ApplyButtonUpgradeDisplay(btn, count)
            end
        end
    end
    local itemEventsRegistered = false
    local function SyncSidebarItemEvents(visible)
        if visible and not itemEventsRegistered then
            itemEventsRegistered = true
            sfui.events.RegisterEvent("GET_ITEM_INFO_RECEIVED", OnUpgradeItemLoaded)
            sfui.events.RegisterEvent("ITEM_DATA_LOAD_RESULT",  OnUpgradeItemLoaded)
        elseif not visible and itemEventsRegistered then
            itemEventsRegistered = false
            if sfui.events.UnregisterEvent then
                sfui.events.UnregisterEvent("GET_ITEM_INFO_RECEIVED", OnUpgradeItemLoaded)
                sfui.events.UnregisterEvent("ITEM_DATA_LOAD_RESULT",  OnUpgradeItemLoaded)
            end
        end
    end
    -- Attach to already-created or future sidebarFrame cleanly
    local origInit = sfui.dungeonjournal._initSidebar
    sfui.dungeonjournal._initSidebar = function(...)
        origInit(...)
        if sidebarFrame then
            sidebarFrame._syncItemEvents = SyncSidebarItemEvents
            if IsSidebarVisible() then
                SyncSidebarItemEvents(true)
            end
        end
    end
    sfui.events.RegisterEvent("QUEST_LOG_UPDATE", OnQuestLogChanged)
    sfui.events.RegisterEvent("QUEST_ACCEPTED",   OnQuestLogChanged)
    sfui.events.RegisterEvent("QUEST_REMOVED",    OnQuestLogChanged)
    sfui.events.RegisterEvent("QUEST_TURNED_IN",  OnQuestLogChanged)
    sfui.events.RegisterEvent("PLAYER_LEVEL_UP",  function()
        InvalidateQuestProgressCache()
        InvalidateUpgradeCache()
        if IsSidebarVisible() then
            common.debounce("dj_sidebar_quests", 0.15, DebouncedSidebarRefresh)
        else
            dirtyRefresh = true
        end
    end)
    sfui.events.RegisterEvent("PLAYER_EQUIPMENT_CHANGED",    OnUpgradeContextChanged)
    sfui.events.RegisterEvent("CHARACTER_POINTS_CHANGED",    OnUpgradeContextChanged)
    sfui.events.RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", OnUpgradeContextChanged)
end
