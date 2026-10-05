local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}

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
    return sfui.dungeonjournal.GetDB()
end

local function IsDungeonHidden(dungeonID)
    return sfui.dungeonjournal.IsDungeonHidden(dungeonID)
end

-- Forward declaration of RefreshSidebar & search query
local RefreshSidebar = nil
local currentSearchFilter = nil

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
    local minLvl = dungeon.minLevel
    local maxLvl = dungeon.maxLevel

    if minLvl and maxLvl then
        local cMin = GetLevelColorHex(minLvl, pLvl)
        local cMax = GetLevelColorHex(maxLvl, pLvl)
        if minLvl == maxLvl then
            return string.format("|c%s[%d]|r", cMin, minLvl)
        elseif cMin == cMax then
            return string.format("|c%s[%d - %d]|r", cMin, minLvl, maxLvl)
        else
            return string.format("|cff666666[|r|c%s%d|r|cff555555 - |r|c%s%d|r|cff666666]|r", cMin, minLvl, cMax, maxLvl)
        end
    elseif dungeon.level then
        local low, high = tostring(dungeon.level):match("^(%d+)%s*-%s*(%d+)$")
        if low and high then
            local nLow, nHigh = tonumber(low), tonumber(high)
            local cMin = GetLevelColorHex(nLow, pLvl)
            local cMax = GetLevelColorHex(nHigh, pLvl)
            if cMin == cMax then
                return string.format("|c%s[%d - %d]|r", cMin, nLow, nHigh)
            else
                return string.format("|cff666666[|r|c%s%d|r|cff555555 - |r|c%s%d|r|cff666666]|r", cMin, nLow, cMax, nHigh)
            end
        else
            local single = tonumber(dungeon.level)
            if single then
                local c = GetLevelColorHex(single, pLvl)
                return string.format("|c%s[%d]|r", c, single)
            end
            return string.format("|cff888888[%s]|r", dungeon.level)
        end
    end
    return ""
end

-- ─── Player Faction & Quest Progress Helpers ─────────────────────────────────
local function GetPlayerFaction()
    local englishFaction, _ = UnitFactionGroup("player")
    if englishFaction and englishFaction:lower() == "horde" then
        return "horde"
    end
    return "alliance"
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
local contextMenuFrame = nil

local function OpenDungeonContextMenu(owner, dungeon)
    if not dungeon then return end

    local isHidden = sfui.dungeonjournal.IsDungeonHidden(dungeon.id)
    local arePinsHidden = sfui.dungeonjournal.AreDungeonPinsHidden(dungeon.id)
    local _, _, _, totalHidden = sfui.dungeonjournal.GetHiddenCounts()

    local items = {}

    if isHidden then
        table.insert(items, {
            text = "Unhide " .. (dungeon.name or "Dungeon"),
            color = { 0.4, 1.0, 0.4 },
            func = function()
                sfui.dungeonjournal.SetDungeonHidden(dungeon.id, false)
                if sfui.print then
                    sfui.print(string.format("restored |cffffd100%s|r to dungeon journal and map.", dungeon.name or "dungeon"))
                end
            end,
        })
    else
        table.insert(items, {
            text = "Hide " .. (dungeon.name or "Dungeon") .. " & Pins",
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
                text = "Unhide Map Pins",
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
                text = "Hide Map Pins Only",
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
            text = "Manage Hidden Items (" .. totalHidden .. ")...",
            color = { 1.0, 0.82, 0.0 },
            func = function()
                sfui.dungeonjournal.OpenHiddenManager()
            end,
        })
        table.insert(items, {
            text = "Restore All Hidden (" .. totalHidden .. ")",
            color = { 0.5, 0.8, 1.0 },
            func = function()
                sfui.dungeonjournal.RestoreAllHidden()
            end,
        })
    end

    table.insert(items, {
        text = "Cancel",
        color = { 0.6, 0.6, 0.6 },
        func = function() end,
    })

    sfui.dungeonjournal.ShowContextMenu(owner, dungeon.name or "Dungeon", items)
end

-- ─── Pool helpers ─────────────────────────────────────────────────────────────
local sidebarButtons = {}

local function DungeonHasWishlist(dungeon)
    if not dungeon or not dungeon.bosses or not (sfui.dungeonjournal and sfui.dungeonjournal.IsWishlisted) then
        return false, 0
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
    return count > 0, count
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
    btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    btn:SetBackdropBorderColor(0, 0, 0, 0)

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

    pool[#pool + 1] = btn
    return btn
end

local function ReleaseAll(pool)
    sfui.dungeonjournal.ReleaseAll(pool)
end

-- ─── Main Refresh ─────────────────────────────────────────────────────────────
local sidebarFrame   = nil
local scrollFrame    = nil
local scrollContent  = nil

RefreshSidebar = function()
    if not sidebarFrame then return end

    ReleaseAll(sidebarButtons)

    local dj         = sfui.dungeonjournal
    local list       = dj and dj.GetItemHelpers and dj.GetItemHelpers().GetList() or {}
    local selectedID = dj and dj.GetSelectedDungeonID and dj.GetSelectedDungeonID()
    local pal        = theme.GetPalette()
    local accent     = pal and pal.accentColor or { 1, 0.78, 0.2, 1 }
    local playerLevel= UnitLevel("player") or 1

    local isFiltering = (currentSearchFilter ~= nil and currentSearchFilter ~= "")
    local displayList = list
    if isFiltering then
        local matched = {}
        for _, dungeon in ipairs(list) do
            local matchFound = false
            if dungeon.name and dungeon.name:lower():find(currentSearchFilter, 1, true) then
                matchFound = true
            elseif dungeon.zone and dungeon.zone:lower():find(currentSearchFilter, 1, true) then
                matchFound = true
            end

            if not matchFound and dungeon.bosses then
                for _, boss in ipairs(dungeon.bosses) do
                    if boss.name and boss.name:lower():find(currentSearchFilter, 1, true) then
                        matchFound = true
                        break
                    end
                    if boss.items then
                        for _, itemID in ipairs(boss.items) do
                            local name = common.get_item_info(itemID)
                            if not name and common.get_item_instant_info then
                                name = common.get_item_instant_info(itemID)
                            end
                            if name and name:lower():find(currentSearchFilter, 1, true) then
                                matchFound = true
                                break
                            end
                        end
                    end
                    if matchFound then break end
                end
            end

            if not matchFound and dungeon.quests then
                for _, q in ipairs(dungeon.quests) do
                    if q.name and q.name:lower():find(currentSearchFilter, 1, true) then
                        matchFound = true
                        break
                    end
                end
            end

            if matchFound then
                matched[#matched + 1] = dungeon
            end
        end
        displayList = matched

        -- Auto-select first matched dungeon if currently selected is not in results
        if #displayList > 0 then
            local isSelectedVisible = false
            for _, d in ipairs(displayList) do
                if d.id == selectedID then isSelectedVisible = true; break end
            end
            if not isSelectedVisible then
                selectedID = displayList[1].id
                if dj and dj.SelectDungeon then
                    dj.SelectDungeon(selectedID)
                end
            end
        end
    end

    local showHidden = DJ_DB().showHiddenInSidebar == true

    -- If currently selected dungeon is hidden and we're not showing hidden, auto-select first visible dungeon
    if selectedID and IsDungeonHidden(selectedID) and not showHidden then
        for _, d in ipairs(displayList) do
            if not IsDungeonHidden(d.id) then
                if dj and dj.SelectDungeon then
                    dj.SelectDungeon(d.id)
                end
                selectedID = d.id
                break
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

            -- Wishlist indicator
            local hasWish, wishCount = DungeonHasWishlist(dungeon)
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

            if prog and prog.noticeText and prog.noticeText ~= "" then
                if lvlStr ~= "" then
                    btn.levelText:SetText(lvlStr .. "  " .. prog.noticeText)
                else
                    btn.levelText:SetText(prog.noticeText)
                end
                btn.levelText:Show()
            elseif lvlStr ~= "" then
                btn.levelText:SetText(lvlStr)
                btn.levelText:Show()
            else
                btn.levelText:Hide()
            end

            -- Tooltip breakdown
            btn:SetScript("OnEnter", function(self)
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

                if hasWish then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(string.format("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:12:12:0:0|t |cffcc44ffwishlist drop%s active (%d)|r", (wishCount > 1 and "s" or ""), wishCount), 1, 1, 1)
                end

                if isHidden then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cffff5555[This dungeon is hidden]|r", 1, 0.35, 0.35)
                    GameTooltip:AddLine("|cff00ff00<right-click to unhide dungeon>|r", 0, 1, 0)
                elseif arePinsHidden then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cffffaa00[Map pins for this dungeon are hidden]|r", 1, 0.7, 0.3)
                    GameTooltip:AddLine("|cff888888<right-click for hide/unhide options>|r", 0.6, 0.6, 0.6)
                else
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cff888888<right-click for hide options>|r", 0.6, 0.6, 0.6)
                end
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            -- Click handler (Left = select dungeon, Right = open context menu)
            local dRef = dungeon
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            btn:SetScript("OnClick", function(self, mouseButton)
                if mouseButton == "RightButton" then
                    OpenDungeonContextMenu(self, dRef)
                else
                    if sfui.dungeonjournal and sfui.dungeonjournal.SelectDungeon then
                        sfui.dungeonjournal.SelectDungeon(dRef.id)
                    end
                end
            end)

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
            btn:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            btn:SetBackdropColor(0.12, 0.12, 0.16, 0.95)
            btn:SetBackdropBorderColor(1, 0.78, 0.2, 0.6)

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

        if hiddenCount > 0 then
            empty.msg:SetText(string.format("All dungeons in this list are hidden (%d hidden).", hiddenCount))
            empty.btn:Show()
            if db.showHiddenInSidebar then
                empty.btn.text:SetText("Restore All")
                empty.btn:SetScript("OnClick", function()
                    sfui.dungeonjournal.RestoreAllHidden()
                end)
            else
                empty.btn.text:SetText("Show Hidden")
                empty.btn:SetScript("OnClick", function()
                    db.showHiddenInSidebar = true
                    if sidebarFrame.UpdateEyeState then sidebarFrame.UpdateEyeState() end
                    RefreshSidebar()
                end)
            end
            empty:Show()
        elseif isFiltering then
            empty.msg:SetText("No dungeons found matching search.")
            empty.btn:Show()
            empty.btn.text:SetText("Clear Search")
            empty.btn:SetScript("OnClick", function()
                if sidebarFrame.searchBox then
                    sidebarFrame.searchBox:SetText("")
                end
            end)
            empty:Show()
        else
            empty.msg:SetText("No dungeons available.")
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
end

-- ─── Frame creation ────────────────────────────────────────────────────────────
local function OnFrameCreated(arg1, arg2)
    local payload = (type(arg1) == "table" and arg1) or arg2
    if not payload or not payload.sidebarFrame then return end
    if scrollFrame then return end -- already initialized

    sidebarFrame = payload.sidebarFrame

    -- ── Search Box Container at Top of Sidebar ───────────────────────────────
    local searchContainer = CreateFrame("Frame", nil, sidebarFrame, "BackdropTemplate")
    sidebarFrame.searchContainer = searchContainer
    searchContainer:SetPoint("TOPLEFT",  sidebarFrame, "TOPLEFT",  4, -4)
    searchContainer:SetPoint("TOPRIGHT", sidebarFrame, "TOPRIGHT", -30, -4)
    searchContainer:SetHeight(22)

    local eyeBtn = CreateFrame("Button", nil, sidebarFrame, "BackdropTemplate")
    sidebarFrame.eyeBtn = eyeBtn
    eyeBtn:SetSize(22, 22)
    eyeBtn:SetPoint("TOPRIGHT", sidebarFrame, "TOPRIGHT", -4, -4)
    eyeBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    eyeBtn:SetBackdropColor(0.04, 0.04, 0.06, 0.9)

    local eyeIcon = eyeBtn:CreateTexture(nil, "ARTWORK")
    eyeBtn.icon = eyeIcon
    eyeIcon:SetSize(14, 14)
    eyeIcon:SetPoint("CENTER")
    eyeIcon:SetTexture("Interface\\Icons\\INV_Misc_Eye_01")
    eyeIcon:SetTexCoord(0.1, 0.9, 0.1, 0.9)

    local function UpdateEyeState()
        local db = DJ_DB()
        local active = db.showHiddenInSidebar == true
        if active then
            eyeIcon:SetDesaturated(false)
            eyeIcon:SetVertexColor(1, 0.82, 0, 1)
            eyeBtn:SetBackdropBorderColor(1, 0.82, 0, 0.8)
        else
            eyeIcon:SetDesaturated(true)
            eyeIcon:SetVertexColor(0.5, 0.5, 0.5, 0.8)
            eyeBtn:SetBackdropBorderColor(0.20, 0.20, 0.25, 0.8)
        end
    end
    sidebarFrame.UpdateEyeState = UpdateEyeState
    UpdateEyeState()

    eyeBtn:SetScript("OnClick", function()
        local db = DJ_DB()
        db.showHiddenInSidebar = not db.showHiddenInSidebar
        UpdateEyeState()
        RefreshSidebar()
    end)

    eyeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local db = DJ_DB()
        GameTooltip:AddLine("Show Hidden Dungeons", 1, 0.82, 0)
        if db.showHiddenInSidebar then
            GameTooltip:AddLine("Hidden dungeons are currently visible (dimmed with [hidden] badge).\nClick to hide them from the sidebar.", 0.85, 0.85, 0.85, true)
        else
            GameTooltip:AddLine("Click to reveal hidden dungeons dimmed in the sidebar so you can review or unhide them.", 0.85, 0.85, 0.85, true)
        end
        local _, _, _, total = sfui.dungeonjournal.GetHiddenCounts()
        if total > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string.format("|cff00ff00%d hidden item%s currently in database|r", total, total > 1 and "s" or ""), 0, 1, 0)
        end
        GameTooltip:Show()
    end)
    eyeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    searchContainer:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    searchContainer:SetBackdropColor(0.04, 0.04, 0.06, 0.9)
    searchContainer:SetBackdropBorderColor(0.20, 0.20, 0.25, 0.8)

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
    placeholder:SetText("Search...")
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
        else
            placeholder:Show()
            clearBtn:Hide()
            currentSearchFilter = nil
        end
        RefreshSidebar()
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
    sfui.dungeonjournal._registerSidebar(RefreshSidebar)

    RefreshSidebar()
end

sfui.dungeonjournal._initSidebar = OnFrameCreated

-- Listen for frame-created and clear-cache messages
if sfui.events and sfui.events.RegisterMessage then
    sfui.events.RegisterMessage("SFUI_DJ_FRAME_CREATED", OnFrameCreated)
    sfui.events.RegisterMessage("SFUI_DJ_CLEAR_CACHE",   function()
        InvalidateQuestProgressCache()
        sidebarButtons = {}
        RefreshSidebar()
    end)
    sfui.events.RegisterMessage("SFUI_DJ_WISHLIST_UPDATED", function()
        if sidebarFrame and sidebarFrame:IsShown() then
            RefreshSidebar()
        end
    end)
end

-- Live update when quests are accepted, turned in, or player levels up
if sfui.events and sfui.events.RegisterEvent then
    local questDebounceTimer = nil
    local function OnQuestLogChanged()
        InvalidateQuestProgressCache()
        if sidebarFrame and sidebarFrame:IsShown() then
            if questDebounceTimer then
                questDebounceTimer:Cancel()
                questDebounceTimer = nil
            end
            if C_Timer and C_Timer.After then
                questDebounceTimer = C_Timer.After(0.15, function()
                    questDebounceTimer = nil
                    if sidebarFrame and sidebarFrame:IsShown() then
                        RefreshSidebar()
                    end
                end)
            else
                RefreshSidebar()
            end
        end
    end
    sfui.events.RegisterEvent("QUEST_LOG_UPDATE", OnQuestLogChanged)
    sfui.events.RegisterEvent("QUEST_ACCEPTED",   OnQuestLogChanged)
    sfui.events.RegisterEvent("QUEST_REMOVED",    OnQuestLogChanged)
    sfui.events.RegisterEvent("QUEST_TURNED_IN",  OnQuestLogChanged)
    sfui.events.RegisterEvent("PLAYER_LEVEL_UP",  OnQuestLogChanged)
end
