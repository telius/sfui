local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.sync = sfui.sync or {}
sfui.sync.hud = sfui.sync.hud or {}

local sync     = sfui.sync
local multibox = sfui.sync.multibox
local hud      = sfui.sync.hud
local common   = sfui.common

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/sync/hud.lua
--  Synced-Party Team Status Bar, Away Mode Toggle & Live Bag/Gold HUD
--
--  Loaded and active ONLY when in a party with a synced character:
--    • Shows each synced party member (and online linked accounts) with live
--      free bag slots (orange < 5, red at 0) and combined team gold.
--    • Secure row click-to-target (LeftClick), unit menu (RightClick),
--      Alt+LeftClick to toggle Away/Paused mode, Shift+LeftClick to set Lead.
-- ══════════════════════════════════════════════════════════════════════════════

local type = _G.type
local pairs = _G.pairs
local ipairs = _G.ipairs
local tonumber = _G.tonumber
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local string_lower = string.lower
local string_format = string.format
local table_insert = table.insert
local table_concat = table.concat
local CreateFrame = _G.CreateFrame
local C_Container = _G.C_Container
local C_Timer = _G.C_Timer
local GetMoney = _G.GetMoney
local GetInventoryItemDurability = _G.GetInventoryItemDurability
local issecretvalue = _G.issecretvalue
local UnitGUID = _G.UnitGUID
local UnitClass = _G.UnitClass
local UnitExists = _G.UnitExists
local UnitIsUnit = _G.UnitIsUnit
local IsInGroup = _G.IsInGroup
local IsInRaid = _G.IsInRaid
local GetNumGroupMembers = _G.GetNumGroupMembers
local InCombatLockdown = _G.InCombatLockdown
local IsAltKeyDown = _G.IsAltKeyDown
local IsShiftKeyDown = _G.IsShiftKeyDown
local wipe = _G.wipe

local ROW_H = 18
local HUD_W = 218
local PAD_X = 4
local PAD_Y = 4

local isActive           = false
local hudFrame           = nil
local hudRows            = {}
local liveStats          = {} -- [cleanKey] = { free, slots, money, dur }
local lastSentFree       = nil
local lastSentSlots      = nil
local lastSentMoney      = nil
local lastSentDur        = nil
local statsBroadcastPend = false
local pendingRefresh     = false

local function get_palette()
    return (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette())
        or (sfui.config and sfui.config.appearance)
        or {}
end

local function rgb_to_hex(col, dr, dg, db)
    if type(col) ~= "table" or not col[1] then
        if type(dr) == "string" then return dr end
    end
    local r = math_floor(math_max(0, math_min(1, tonumber(col and col[1]) or tonumber(dr) or 1)) * 255 + 0.5)
    local g = math_floor(math_max(0, math_min(1, tonumber(col and col[2]) or tonumber(dg) or 1)) * 255 + 0.5)
    local b = math_floor(math_max(0, math_min(1, tonumber(col and col[3]) or tonumber(db) or 1)) * 255 + 0.5)
    return string_format("%02x%02x%02x", r, g, b)
end

local HEADER_TOOLTIP_LINES = {
    "|cff00ffffleft-click header:|r invite missing linked accounts",
    "|cff00ffffshift+right-click header:|r toggle compact bar",
    "|cff00ffffright-click header:|r open sync options",
    "|cff00ffffmousewheel:|r scale hud   •   |cff00ffffdrag:|r move hud",
    " ",
    "|cff00ffffleft-click row:|r target character (or invite if ungrouped)",
    "|cff00ffffright-click row:|r unit menu",
    "|cff00ffffalt+left-click row:|r toggle away / paused mode",
    "|cff00ffffshift+left-click row:|r make multibox lead",
}

local function format_gold(copper)
    copper = tonumber(copper) or 0
    local g = math_floor(copper / 10000)
    local s = math_floor((copper % 10000) / 100)
    if g >= 1000 then
        return string_format("|cffffd100%dg|r", g)
    elseif g > 0 then
        return string_format("|cffffd100%dg|r |cffc7c7cf%ds|r", g, s)
    end
    return string_format("|cffc7c7cf%ds|r", s)
end

local function compute_local_durability()
    local lowest = 100
    if GetInventoryItemDurability then
        for slot = 1, 18 do
            local cur, maxD = GetInventoryItemDurability(slot)
            if cur and maxD and not (issecretvalue and (issecretvalue(cur) or issecretvalue(maxD))) and maxD > 0 then
                local pct = (cur / maxD) * 100
                if pct < lowest then
                    lowest = pct
                end
            end
        end
    end
    return math_floor(lowest)
end

local function compute_local_bag_stats()
    local free, total = 0, 0
    local maxBag = (_G.NUM_BAG_SLOTS and _G.NUM_BAG_SLOTS) or 4
    if C_Container then
        for bag = 0, maxBag do
            local numSlots = (C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag)) or 0
            if numSlots > 0 then
                local bagFree, bagFamily = 0, 0
                if C_Container.GetContainerNumFreeSlots then
                    bagFree, bagFamily = C_Container.GetContainerNumFreeSlots(bag)
                end
                if not bagFamily or bagFamily == 0 then
                    total = total + numSlots
                    free  = free + (tonumber(bagFree) or 0)
                end
            end
        end
    end
    local money = (GetMoney and GetMoney()) or 0
    local dur   = compute_local_durability()
    local myKey = multibox.CleanKey(multibox.FullName("player") or "")
    if myKey ~= "" then
        liveStats[myKey] = {
            free  = free,
            slots = total,
            money = money,
            dur   = dur,
        }
    end
    local myGUID = UnitGUID and UnitGUID("player")
    if myGUID and SfuiDB and type(SfuiDB.alts) == "table" and type(SfuiDB.alts[myGUID]) == "table" then
        SfuiDB.alts[myGUID].money      = money
        SfuiDB.alts[myGUID].bagsFree   = free
        SfuiDB.alts[myGUID].bagsTotal  = total
        SfuiDB.alts[myGUID].durability = dur
    end
    return free, total, money, dur
end

local function broadcast_local_stats(force)
    if not isActive or not multibox.IsActiveSyncParty() then return end
    local free, slots, money, dur = compute_local_bag_stats()
    if not force and free == lastSentFree and slots == lastSentSlots and money == lastSentMoney and dur == lastSentDur then
        return
    end
    lastSentFree  = free
    lastSentSlots = slots
    lastSentMoney = money
    lastSentDur   = dur
    local s = sync.GetSettings and sync.GetSettings()
    sync.Broadcast("DELTA_HUD_STATS", {
        pass = (s and s.passcode ~= "" and s.passcode) or nil,
        f    = free,
        s    = slots,
        m    = money,
        d    = dur,
    }, true, false)
end

local function schedule_stats_broadcast()
    compute_local_bag_stats()
    if hud.RefreshStatsOnly then
        hud.RefreshStatsOnly()
    end
    if statsBroadcastPend then return end
    statsBroadcastPend = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function()
            statsBroadcastPend = false
            broadcast_local_stats(false)
        end)
    else
        statsBroadcastPend = false
        broadcast_local_stats(false)
    end
end

local fallbackStatsScratch = {}
local teamMembersPool = {}
local teamMembersOut  = {}
local seenMembers     = {}

local function get_stats_for_char(name)
    local key = multibox.CleanKey(name or "")
    if key == "" then return nil end
    if not liveStats[key] and key == multibox.CleanKey(multibox.FullName("player") or "") then
        compute_local_bag_stats()
    end
    if liveStats[key] then
        return liveStats[key]
    end
    local alt = multibox.GetAltByCleanKey and multibox.GetAltByCleanKey(key)
    if type(alt) == "table" then
        fallbackStatsScratch.free  = tonumber(alt.bagsFree)
        fallbackStatsScratch.slots = tonumber(alt.bagsTotal)
        fallbackStatsScratch.money = tonumber(alt.money) or 0
        fallbackStatsScratch.dur   = tonumber(alt.durability)
        return fallbackStatsScratch
    end
    return nil
end

local function find_alt_guid_and_class(name, unit)
    if unit and UnitExists and UnitExists(unit) and UnitClass then
        local _, cls = UnitClass(unit)
        local g = UnitGUID and UnitGUID(unit)
        if cls then return g, cls end
    end
    local key = multibox.CleanKey(name or "")
    if multibox.GetAltByCleanKey then
        local alt, guid = multibox.GetAltByCleanKey(key)
        if type(alt) == "table" then
            return guid, alt.class
        end
    end
    local s = sync.GetSettings and sync.GetSettings()
    if s and type(s.peers) == "table" then
        for _, p in pairs(s.peers) do
            if type(p) == "table" and multibox.CleanKey(p.name or "") == key and p.class then
                return nil, p.class
            end
        end
    end
    return nil, nil
end

local function format_bag_free_badge(st)
    if not st or st.free == nil then return "" end
    local free = tonumber(st.free) or 0
    local color = (free == 0 and "ff3333") or (free < 5 and "ff9933") or "9999a5"
    return string_format("|cff%s%d|r", color, free)
end

local function format_durability_badge(st)
    if not st or st.dur == nil then return "" end
    local dur = tonumber(st.dur) or 100
    local color = (dur <= 10 and "ff3333")
        or (dur < 30 and "ff8833")
        or (dur < 60 and "ffcc33")
        or "8899aa"
    return string_format("|cff%s%d%%|r", color, dur)
end

local function push_member(idx, name, key, unit, isMe, inGrp, guid, class)
    local entry = teamMembersPool[idx]
    if not entry then
        entry = {}
        teamMembersPool[idx] = entry
    end
    entry.name  = name
    entry.key   = key
    entry.unit  = unit
    entry.isMe  = isMe
    entry.inGrp = inGrp
    entry.guid  = guid
    entry.class = class
    teamMembersOut[idx] = entry
end

local function collect_team_members()
    wipe(teamMembersOut)
    wipe(seenMembers)
    local nMembers = 0
    local myFull = multibox.FullName("player") or ""
    local myShort = multibox.CommandName(myFull)
    local myKey = multibox.CleanKey(myShort)

    if myKey ~= "" then
        seenMembers[myKey] = true
        local myGUID, myClass = find_alt_guid_and_class(myShort, "player")
        nMembers = nMembers + 1
        push_member(nMembers, myShort, myKey, "player", true, true, myGUID, myClass)
    end

    if IsInGroup and IsInGroup() then
        local isRaid = IsInRaid and IsInRaid()
        local count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
        local prefix = isRaid and "raid" or "party"
        local maxIdx = isRaid and count or math_min(4, count)
        for i = 1, maxIdx do
            local u = prefix .. i
            if UnitExists and UnitExists(u) and not (UnitIsUnit and UnitIsUnit(u, "player")) then
                local g = UnitGUID and UnitGUID(u)
                local n = multibox.FullName(u)
                if (g and multibox.IsSyncedCharacter(g)) or (n and multibox.IsSyncedCharacter(n)) then
                    local short = multibox.CommandName(n)
                    local key = multibox.CleanKey(short)
                    if key ~= "" and not seenMembers[key] then
                        seenMembers[key] = true
                        local altGUID, cls = find_alt_guid_and_class(short, u)
                        nMembers = nMembers + 1
                        push_member(nMembers, short, key, u, false, true, altGUID or g, cls)
                    end
                end
            end
        end
    end

    local s = sync.GetSettings and sync.GetSettings()
    for _, p in pairs((s and s.peers) or {}) do
        if type(p) == "table" and p.trusted and p.name then
            local short = multibox.CommandName(p.name)
            local key = multibox.CleanKey(short)
            if key ~= "" and not seenMembers[key] and sync.IsPeerOnline and sync.IsPeerOnline(short) then
                seenMembers[key] = true
                local altGUID, cls = find_alt_guid_and_class(short, nil)
                nMembers = nMembers + 1
                push_member(nMembers, short, key, nil, false, false, altGUID, cls or p.class)
            end
        end
    end

    return teamMembersOut
end

local function show_footer_tooltip(owner)
    local tip = (common and common.get_tooltip and common.get_tooltip()) or _G.GameTooltip
    if not tip then return end
    tip:SetOwner(owner, "ANCHOR_BOTTOM")
    tip:ClearLines()
    local pal = get_palette()
    local ac = pal.accentColor or { 0.4, 0.85, 1.0 }
    local hc = pal.headerColor or { 1, 0.82, 0 }
    local dt = pal.dimTextColor or { 0.75, 0.75, 0.82 }
    local dtHex = rgb_to_hex(dt, "888899")
    tip:AddLine("sync party gold, durability & bag space", ac[1] or 0.4, ac[2] or 0.85, ac[3] or 1.0)

    local members = collect_team_members()
    local partyGold = 0
    for _, m in ipairs(members) do
        local st = get_stats_for_char(m.name)
        local money = (st and tonumber(st.money)) or 0
        partyGold = partyGold + money
        local durStr = (st and st.dur ~= nil)
            and (" " .. format_durability_badge(st))
            or ""
        local bagStr = (st and st.free ~= nil and st.slots and st.slots > 0)
            and string_format(" |cff%s(%d/%d free)|r", dtHex, st.free, st.slots)
            or ""
        local nameStr = string_lower(m.name)
        if m.class and common and common.class_color_name then
            nameStr = common.class_color_name(nameStr, m.class)
        end
        if m.unit and m.unit ~= "" then
            nameStr = nameStr .. " |cff" .. dtHex .. "(" .. string_lower(m.unit) .. ")|r"
        end
        tip:AddDoubleLine(nameStr .. durStr .. bagStr, format_gold(money), 1, 1, 1, 1, 1, 1)
    end

    tip:AddLine(" ")
    tip:AddDoubleLine("party total", format_gold(partyGold), hc[1] or 1, hc[2] or 0.82, hc[3] or 0, 1, 1, 1)

    if SfuiDB and type(SfuiDB.alts) == "table" then
        local allAltsGold = 0
        for _, alt in pairs(SfuiDB.alts) do
            if type(alt) == "table" and tonumber(alt.money) then
                allAltsGold = allAltsGold + tonumber(alt.money)
            end
        end
        if allAltsGold > partyGold then
            tip:AddDoubleLine("all synced alts", format_gold(allAltsGold), dt[1] or 0.75, dt[2] or 0.75, dt[3] or 0.82, 1, 1, 1)
        end
    end
    tip:Show()
end

local style_hud_row

local function acquire_hud_row(index)
    if hudRows[index] then return hudRows[index] end
    local row = CreateFrame("Button", "SfuiSyncPartyHudRow" .. index, hudFrame, "SecureActionButtonTemplate")
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", PAD_X, -ROW_H * index - PAD_Y)
    row:SetPoint("TOPRIGHT", hudFrame, "TOPRIGHT", -PAD_X, -ROW_H * index - PAD_Y)
    if row.SetAttribute then
        row:SetAttribute("useOnKeyDown", false)
        row:SetAttribute("type1", "target")
        row:SetAttribute("type2", "togglemenu")
    end
    row:RegisterForClicks("AnyUp", "AnyDown")

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:Hide()

    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0.14)

    row.markFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.markFs:SetPoint("LEFT", row, "LEFT", 5, 0)
    row.markFs:SetWidth(10)
    row.markFs:SetJustifyH("CENTER")

    row.bagsFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.bagsFs:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.bagsFs:SetWidth(20)
    row.bagsFs:SetJustifyH("RIGHT")

    row.durFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.durFs:SetPoint("RIGHT", row.bagsFs, "LEFT", -6, 0)
    row.durFs:SetWidth(34)
    row.durFs:SetJustifyH("RIGHT")

    row.nameFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameFs:SetPoint("LEFT", row.markFs, "RIGHT", 2, 0)
    row.nameFs:SetPoint("RIGHT", row.durFs, "LEFT", -4, 0)
    row.nameFs:SetJustifyH("LEFT")
    row.nameFs:SetWordWrap(false)

    row:SetScript("PreClick", function(self, button, down)
        if down then return end
        if button == "LeftButton" and IsAltKeyDown and IsAltKeyDown() then
            if self.memberName then
                sync.ToggleAway(self.memberName)
            end
        elseif button == "LeftButton" and IsShiftKeyDown and IsShiftKeyDown() then
            if self.memberName then
                sync.SetLead(self.memberName, true)
            end
        elseif button == "LeftButton" and not self.unit and self.memberName then
            local inviteFn = (_G.C_PartyInfo and _G.C_PartyInfo.InviteUnit) or _G.InviteUnit
            if inviteFn then
                inviteFn(self.memberName)
            end
        end
    end)

    row:SetScript("OnEnter", function(self)
        local tip = (common and common.get_tooltip and common.get_tooltip()) or _G.GameTooltip
        if not tip or not self.memberName then return end
        local pal = get_palette()
        local acHex = rgb_to_hex(pal.accentColor, "00ffff")
        local dtHex = rgb_to_hex(pal.dimTextColor, "8899aa")
        tip:SetOwner(self, "ANCHOR_RIGHT")
        tip:ClearLines()
        local lowerName = string_lower(self.memberName)
        local title = self.class and common and common.class_color_name and common.class_color_name(lowerName, self.class) or lowerName
        if self.unit and self.unit ~= "" then
            title = title .. " |cff" .. dtHex .. "(" .. string_lower(self.unit) .. ")|r"
        end
        tip:AddLine(title, 1, 1, 1)

        if self.guid and sfui.alts and sfui.alts.mail and sfui.alts.mail.GetAltProfessionHandles then
            local _, profStr = sfui.alts.mail.GetAltProfessionHandles(self.guid)
            if profStr and profStr ~= "" then
                tip:AddLine("professions: " .. string_lower(profStr), 0.75, 0.75, 0.85)
            end
        end

        local st = get_stats_for_char(self.memberName)
        if st then
            local durPart = (st.dur ~= nil)
                and ("   •   durability: " .. format_durability_badge(st))
                or ""
            local bagPart = (st.free ~= nil and st.slots and st.slots > 0)
                and string_format("   •   %d/%d bag slots free", st.free, st.slots)
                or ""
            tip:AddLine(format_gold(st.money or 0) .. durPart .. bagPart, 0.85, 0.85, 0.9)
        end

        if sync.IsAway(self.memberName) then
            tip:AddLine("status: away / paused (automation bypassed)", 0.5, 0.65, 0.85)
        end

        tip:AddLine(" ")
        tip:AddLine(string_format("|cff%sleft-click:|r target   •   |cff%sright-click:|r unit menu", acHex, acHex), 0.8, 0.8, 0.8)
        tip:AddLine(string_format("|cff%salt+left-click:|r toggle away   •   |cff%sshift+left-click:|r make lead", acHex, acHex), 0.8, 0.8, 0.8)
        tip:Show()
    end)

    row:SetScript("OnLeave", function()
        if common and common.hide_tooltip then
            common.hide_tooltip()
        elseif _G.GameTooltip_Hide then
            _G.GameTooltip_Hide()
        end
    end)

    style_hud_row(row, index, get_palette())
    hudRows[index] = row
    return row
end

style_hud_row = function(row, index, pal)
    if not row then return end
    pal = pal or get_palette()
    if not (InCombatLockdown and InCombatLockdown()) and hudFrame then
        row:SetFrameLevel((hudFrame:GetFrameLevel() or 1) + 10)
    end
    if row.bg then
        if index % 2 == 0 then
            local cc = pal.containerColor or { 0.08, 0.08, 0.12 }
            row.bg:SetColorTexture(cc[1] or 0.08, cc[2] or 0.08, cc[3] or 0.12, 0.28)
            row.bg:Show()
        else
            row.bg:Hide()
        end
    end
    if row.hl then
        local hlc = pal.highlightColor or pal.accentColor or { 1, 1, 1 }
        row.hl:SetColorTexture(hlc[1] or 1, hlc[2] or 1, hlc[3] or 1, 0.14)
    end
end

function hud.ApplyTheme(frame, pal)
    frame = frame or hudFrame
    if not frame then return end
    pal = pal or get_palette()

    if not (sfui.theme and sfui.theme.RegisterWindow) and common and common.apply_flat_backdrop then
        local bgCol = pal.backdropColor or { 0.04, 0.04, 0.06, 0.90 }
        local bdCol = pal.borderColor or { 0.18, 0.18, 0.25, 1 }
        common.apply_flat_backdrop(frame, bgCol, bdCol)
    end

    local baseLevel = frame:GetFrameLevel() or 1
    local isCamelot = sfui.theme and sfui.theme.IsCamelotActive and sfui.theme.IsCamelotActive()
    local acc = pal.accentColor or (isCamelot and { 0.85, 0.65, 0.20 } or { 0.0, 1.0, 1.0 })
    local cc  = pal.containerColor or { 0.08, 0.08, 0.12 }
    local divCol = isCamelot and { 0.45, 0.34, 0.16, 0.60 }
        or (pal.borderColor and { pal.borderColor[1] or 0.2, pal.borderColor[2] or 0.2, pal.borderColor[3] or 0.28, 0.75 })
        or { 0.20, 0.20, 0.28, 0.75 }

    if frame.header then
        frame.header:SetFrameLevel(baseLevel + 15)
        if frame.header.bg then
            frame.header.bg:SetColorTexture(cc[1] or 0.08, cc[2] or 0.08, cc[3] or 0.12, isCamelot and 0.45 or 0.80)
        end
        if frame.header.accent then
            frame.header.accent:SetColorTexture(acc[1] or 0, acc[2] or 1, acc[3] or 1, 0.95)
        end
        if frame.header.divider then
            frame.header.divider:SetColorTexture(divCol[1], divCol[2], divCol[3], divCol[4])
        end
    end

    if frame.footer then
        frame.footer:SetFrameLevel(baseLevel + 10)
        if frame.footer.bg then
            frame.footer.bg:SetColorTexture(cc[1] or 0.06, cc[2] or 0.06, cc[3] or 0.09, isCamelot and 0.35 or 0.55)
        end
        if frame.footer.divider then
            frame.footer.divider:SetColorTexture(divCol[1], divCol[2], divCol[3], divCol[4])
        end
    end

    for i, row in ipairs(hudRows) do
        style_hud_row(row, i, pal)
    end

    if frame:IsShown() then
        if InCombatLockdown and InCombatLockdown() then
            hud.RefreshStatsOnly()
        else
            hud.Refresh()
        end
    end
end

local function ensure_hud_frame()
    if hudFrame then return hudFrame end
    local s = sync.GetSettings and sync.GetSettings()

    local f = CreateFrame("Frame", "SfuiSyncPartyHUD", _G.UIParent, "BackdropTemplate")
    f:SetSize(HUD_W, 56)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:SetScale((s and tonumber(s.hudScale)) or 1.0)

    if s and type(s.hudPos) == "table" and #s.hudPos >= 4 then
        f:SetPoint(s.hudPos[1], _G.UIParent, s.hudPos[2], s.hudPos[3], s.hudPos[4])
    else
        f:SetPoint("TOP", _G.UIParent, "TOP", 220, -6)
    end

    f:SetScript("OnMouseWheel", function(self, delta)
        if InCombatLockdown and InCombatLockdown() then return end
        local cfg = sync.GetSettings and sync.GetSettings()
        local cur = (cfg and tonumber(cfg.hudScale)) or 1.0
        local nextScale = math_max(0.6, math_min(2.2, cur * (delta > 0 and 1.05 or 0.95)))
        if cfg then cfg.hudScale = nextScale end
        self:SetScale(nextScale)
    end)

    local header = CreateFrame("Button", nil, f)
    header:SetPoint("TOPLEFT", f, "TOPLEFT", PAD_X, -PAD_Y)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD_X, -PAD_Y)
    header:SetHeight(ROW_H)
    header:RegisterForClicks("AnyUp")
    header:RegisterForDrag("LeftButton")

    local headerBg = header:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints()
    header.bg = headerBg

    local headerAccent = header:CreateTexture(nil, "BORDER")
    headerAccent:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
    headerAccent:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    headerAccent:SetWidth(2)
    header.accent = headerAccent

    local headerDiv = header:CreateTexture(nil, "BORDER")
    headerDiv:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    headerDiv:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    headerDiv:SetHeight(1)
    header.divider = headerDiv

    header.text = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    header.text:SetPoint("LEFT", header, "LEFT", 7, 0)
    header.text:SetJustifyH("LEFT")

    header:SetScript("OnDragStart", function()
        f:StartMoving()
    end)
    header:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local p, _, rp, x, y = f:GetPoint()
        local cfg = sync.GetSettings and sync.GetSettings()
        if cfg then
            cfg.hudPos = { p, rp, x, y }
        end
    end)

    header:SetScript("OnClick", function(_, button)
        local shift = IsShiftKeyDown and IsShiftKeyDown()
        if button == "LeftButton" then
            if sync.FormSyncedParty then sync.FormSyncedParty() end
        elseif button == "RightButton" then
            if shift then
                local cfg = sync.GetSettings and sync.GetSettings()
                if cfg then
                    cfg.hudCompact = not cfg.hudCompact
                    hud.Refresh()
                end
            elseif sfui.options and sfui.options.OpenTab then
                sfui.options.OpenTab("sync")
            elseif sfui.options and sfui.options.Toggle then
                sfui.options.Toggle()
            end
        end
    end)

    header:SetScript("OnEnter", function(self)
        local tip = (common and common.get_tooltip and common.get_tooltip()) or _G.GameTooltip
        if not tip then return end
        local pal = get_palette()
        local hc = pal.headerColor or pal.accentColor or { 0.4, 0.85, 1.0 }
        tip:SetOwner(self, "ANCHOR_BOTTOM")
        tip:ClearLines()
        tip:AddLine("sfui sync party hud", hc[1] or 0.4, hc[2] or 0.85, hc[3] or 1.0)
        for _, line in ipairs(HEADER_TOOLTIP_LINES) do
            tip:AddLine(line, 0.9, 0.9, 0.95)
        end
        tip:Show()
    end)
    header:SetScript("OnLeave", function()
        if common and common.hide_tooltip then
            common.hide_tooltip()
        elseif _G.GameTooltip_Hide then
            _G.GameTooltip_Hide()
        end
    end)
    f.header = header

    local footer = CreateFrame("Frame", nil, f)
    footer:SetHeight(ROW_H)
    footer:EnableMouse(true)

    local footerBg = footer:CreateTexture(nil, "BACKGROUND")
    footerBg:SetAllPoints()
    footer.bg = footerBg

    local footerDiv = footer:CreateTexture(nil, "BORDER")
    footerDiv:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
    footerDiv:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
    footerDiv:SetHeight(1)
    footer.divider = footerDiv

    footer.text = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer.text:SetPoint("LEFT", footer, "LEFT", 6, 0)
    footer.text:SetJustifyH("LEFT")
    footer:SetScript("OnEnter", function(self)
        show_footer_tooltip(self)
    end)
    footer:SetScript("OnLeave", function()
        if common and common.hide_tooltip then
            common.hide_tooltip()
        elseif _G.GameTooltip_Hide then
            _G.GameTooltip_Hide()
        end
    end)
    f.footer = footer

    hudFrame = f

    if sfui.theme and sfui.theme.RegisterWindow then
        sfui.theme.RegisterWindow(f, hud.ApplyTheme, { cornerBrackets = true })
    else
        hud.ApplyTheme(f)
    end

    if sfui.movers and sfui.movers.Register then
        sfui.movers.Register(f, {
            key = "syncpartyhud",
            label = "sync party hud",
            preferredPoint = "TOP",
            customSize = function()
                return f:GetWidth(), f:GetHeight()
            end,
            getPoint = function()
                local cfg = sync.GetSettings and sync.GetSettings()
                local p = cfg and cfg.hudPos
                if type(p) == "table" and #p >= 4 then
                    return p[1], _G.UIParent, p[2], p[3], p[4]
                end
                return "TOP", _G.UIParent, "TOP", 220, -6
            end,
            setPoint = function(point, _, relPoint, x, y)
                local cfg = sync.GetSettings and sync.GetSettings()
                if cfg then
                    cfg.hudPos = { point, relPoint or point, x, y }
                end
                f:ClearAllPoints()
                f:SetPoint(point, _G.UIParent, relPoint or point, x, y)
            end,
            resetPosition = function()
                local cfg = sync.GetSettings and sync.GetSettings()
                if cfg then
                    cfg.hudPos = { "TOP", "TOP", 220, -6 }
                end
                f:ClearAllPoints()
                f:SetPoint("TOP", _G.UIParent, "TOP", 220, -6)
            end,
            isEnabled = function()
                local cfg = sync.GetSettings and sync.GetSettings()
                return (cfg and cfg.enabled and cfg.mbShowHud ~= false) and true or false
            end,
        })
    end

    return f
end

function hud.RefreshStatsOnly()
    if not hudFrame or not hudFrame:IsShown() then return end
    local pal = get_palette()
    local dimHex = rgb_to_hex(pal.dimTextColor, 0.60, 0.60, 0.65)
    local totalGold = 0
    for _, row in ipairs(hudRows) do
        if row:IsShown() and row.memberName then
            local st = get_stats_for_char(row.memberName)
            row.durFs:SetText(format_durability_badge(st))
            row.bagsFs:SetText(format_bag_free_badge(st))
            if st and tonumber(st.money) then
                totalGold = totalGold + tonumber(st.money)
            end
        end
    end
    if hudFrame.footer and hudFrame.footer.text then
        hudFrame.footer.text:SetText("|cff" .. dimHex .. "team gold:|r " .. format_gold(totalGold))
    end
end

function hud.Refresh()
    local s = sync.GetSettings and sync.GetSettings()
    if not isActive or not s or not s.enabled or s.mbShowHud == false or not multibox.IsActiveSyncParty() then
        if hudFrame and not (InCombatLockdown and InCombatLockdown()) then
            hudFrame:Hide()
        end
        return
    end

    ensure_hud_frame()
    if InCombatLockdown and InCombatLockdown() then
        pendingRefresh = true
        hud.RefreshStatsOnly()
        return
    end

    local pal = get_palette()
    local accHex = rgb_to_hex(pal.accentColor, 0, 1, 1)
    local hdrHex = rgb_to_hex(pal.headerColor or pal.accentColor, 0, 1, 1)
    local dimHex = rgb_to_hex(pal.dimTextColor, 0.60, 0.60, 0.65)

    local members = collect_team_members()
    local leadName = sync.GetLead and sync.GetLead()
    local groupedCount, activeCount = 0, 0
    local totalGold = 0
    local compactParts = {}
    local isCompact = (s.hudCompact == true)

    for i, m in ipairs(members) do
        local row = acquire_hud_row(i)
        style_hud_row(row, i, pal)
        local isAway = sync.IsAway(m.name)
        local isLead = leadName and multibox.SameChar(m.name, leadName)

        if not isAway then
            activeCount = activeCount + 1
            if m.inGrp then
                groupedCount = groupedCount + 1
            end
        end

        row.memberName = m.name
        row.unit       = m.unit
        row.guid       = m.guid
        row.class      = m.class
        if row.SetAttribute then
            row:SetAttribute("unit", m.unit)
        end

        row.markFs:SetText(m.isMe and ("|cff" .. accHex .. ">|r") or (isLead and "|cffffd100*|r" or ""))

        local dispName = string_lower(m.name)
        if isAway then
            dispName = "|cff8099bf" .. dispName .. " (away)|r"
        elseif not m.inGrp then
            dispName = "|cffffd91a" .. dispName .. "|r"
        elseif m.class and common and common.class_color_name then
            dispName = common.class_color_name(dispName, m.class)
        end
        if isLead and m.isMe then
            dispName = dispName .. " |cffffd100*|r"
        end
        row.nameFs:SetText(dispName)

        local st = get_stats_for_char(m.name)
        row.durFs:SetText(format_durability_badge(st))
        row.bagsFs:SetText(format_bag_free_badge(st))
        if st and tonumber(st.money) then
            totalGold = totalGold + tonumber(st.money)
        end
        row:SetShown(not isCompact)

        table_insert(compactParts, dispName)
    end

    for i = #members + 1, #hudRows do
        hudRows[i]:Hide()
    end

    local countBadge = string_format("|cffffd100(%d/%d)|r", groupedCount, math_max(1, activeCount))
    if isCompact then
        hudFrame.header.text:SetText("|cff" .. hdrHex .. "sync|r " .. countBadge .. "  " .. table_concat(compactParts, " "))
        if hudFrame.header.divider then hudFrame.header.divider:Hide() end
        hudFrame.footer:Hide()
        hudFrame:SetSize(HUD_W, ROW_H + PAD_Y * 2)
    else
        hudFrame.header.text:SetText("|cff" .. hdrHex .. "sync party|r  " .. countBadge)
        if hudFrame.header.divider then hudFrame.header.divider:Show() end
        hudFrame.footer:ClearAllPoints()
        hudFrame.footer:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", PAD_X, -ROW_H * (#members + 1) - PAD_Y)
        hudFrame.footer:SetPoint("TOPRIGHT", hudFrame, "TOPRIGHT", -PAD_X, -ROW_H * (#members + 1) - PAD_Y)
        if hudFrame.footer.text then
            hudFrame.footer.text:SetText("|cff" .. dimHex .. "team gold:|r " .. format_gold(totalGold))
        end
        hudFrame.footer:Show()
        hudFrame:SetSize(HUD_W, ROW_H * (#members + 2) + PAD_Y * 2)
    end

    hudFrame:Show()
end

function hud.HandleSyncMessage(sender, msgType, data)
    if msgType ~= "DELTA_HUD_STATS" or type(data) ~= "table" then return end
    local key = multibox.CleanKey(sender or "")
    if key == "" then return end
    local free  = tonumber(data.f)
    local slots = tonumber(data.s)
    local money = tonumber(data.m) or 0
    local dur   = tonumber(data.d)
    liveStats[key] = {
        free  = free,
        slots = slots,
        money = money,
        dur   = dur,
    }
    if multibox.GetAltByCleanKey then
        local alt = multibox.GetAltByCleanKey(key)
        if type(alt) == "table" then
            if free ~= nil then alt.bagsFree = free end
            if slots ~= nil then alt.bagsTotal = slots end
            if data.m ~= nil then alt.money = money end
            if dur ~= nil then alt.durability = dur end
        end
    end
    hud.RefreshStatsOnly()
end

local function on_player_regen_enabled()
    if pendingRefresh then
        pendingRefresh = false
        hud.Refresh()
    end
end

local HUD_EVENTS = {
    { "BAG_UPDATE_DELAYED",          schedule_stats_broadcast },
    { "PLAYER_MONEY",                schedule_stats_broadcast },
    { "UPDATE_INVENTORY_DURABILITY", schedule_stats_broadcast },
    { "PLAYER_REGEN_ENABLED",        on_player_regen_enabled },
}

function hud.Enable()
    if isActive then return end
    isActive = true
    compute_local_bag_stats()
    if sfui.events and sfui.events.RegisterEvent then
        for _, entry in ipairs(HUD_EVENTS) do
            sfui.events.RegisterEvent(entry[1], entry[2])
        end
    end
    hud.Refresh()
    if C_Timer and C_Timer.After then
        C_Timer.After(1.0, function()
            if isActive then
                broadcast_local_stats(true)
            end
        end)
    end
end

function hud.Disable()
    if not isActive then return end
    isActive = false
    pendingRefresh = false
    if sfui.events and sfui.events.UnregisterEvent then
        for _, entry in ipairs(HUD_EVENTS) do
            sfui.events.UnregisterEvent(entry[1], entry[2])
        end
    end
    if hudFrame and not (InCombatLockdown and InCombatLockdown()) then
        hudFrame:Hide()
    end
end

if multibox and multibox.RegisterPartySubmodule then
    multibox.RegisterPartySubmodule(hud)
end

