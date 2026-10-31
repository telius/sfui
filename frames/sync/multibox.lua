local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.sync = sfui.sync or {}
sfui.sync.multibox = sfui.sync.multibox or {}

local sync     = sfui.sync
local multibox = sfui.sync.multibox

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/sync/multibox.lua
--  Synced-Party Coordinator, Lead Management, Away Mode, Smart Follow & Alerts
--
--  All party-sync helpers (follow alerts, quest/dialog sync, trade routing,
--  corpse quest-item alerts, and the team status hud) remain dormant with zero
--  active event listeners or UI frames until the player is actively in a group
--  with at least one synced character (`multibox.IsActiveSyncParty()`).
-- ══════════════════════════════════════════════════════════════════════════════

local type = _G.type
local next = _G.next
local pairs = _G.pairs
local ipairs = _G.ipairs
local tonumber = _G.tonumber
local tostring = _G.tostring
local string_lower = string.lower
local string_match = string.match
local string_format = string.format
local table_insert = table.insert
local table_sort = table.sort
local table_concat = table.concat
local wipe = _G.wipe
local GetTime = _G.GetTime
local UnitGUID = _G.UnitGUID
local UnitExists = _G.UnitExists
local UnitIsUnit = _G.UnitIsUnit
local UnitIsConnected = _G.UnitIsConnected
local UnitIsVisible = _G.UnitIsVisible
local UnitIsDead = _G.UnitIsDead
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local UnitOnTaxi = _G.UnitOnTaxi
local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo
local UnitIsGroupLeader = _G.UnitIsGroupLeader
local CheckInteractDistance = _G.CheckInteractDistance
local IsInGroup = _G.IsInGroup
local IsInRaid = _G.IsInRaid
local GetNumGroupMembers = _G.GetNumGroupMembers
local InCombatLockdown = _G.InCombatLockdown
local IsShiftKeyDown = _G.IsShiftKeyDown
local FollowUnit = _G.FollowUnit
local C_Timer = _G.C_Timer
local GetSubZoneText = _G.GetSubZoneText
local GetZoneText = _G.GetZoneText

-- ── Name Helpers (Forever "First Last" + Retail "Name-Realm" Safe) ────────────
local cleanKeyCache = {}
local full_name = sync.FullName
local cmd_name = sync.CommandName

local function clean_key(name)
    if type(name) ~= "string" or name == "" then return "" end
    local cached = cleanKeyCache[name]
    if cached then return cached end
    local k = string_lower(cmd_name(name) or "")
    cleanKeyCache[name] = k
    return k
end

local function same_char(a, b)
    if not a or not b or a == "" or b == "" then return false end
    return clean_key(a) == clean_key(b)
end

multibox.FullName    = full_name
multibox.CommandName = cmd_name
multibox.CleanKey    = clean_key
multibox.SameChar    = same_char

-- ── Synced Peer, Party Unit, Away Mode & Explicit Lead Discovery ──────────────
local explicitLead      = nil
local awayMap           = {} -- [cleanKey] = true
local peerCacheValid    = false
local syncedByGUID      = {}
local syncedByCleanKey  = {}
local altGUIDByCleanKey = {}

function multibox.InvalidatePeerCache()
    peerCacheValid = false
end

local function ensure_peer_cache()
    if peerCacheValid then return end
    local myGUID = UnitGUID and UnitGUID("player")
    local myClean = clean_key(full_name("player") or "")
    if myClean == "" then return end

    wipe(syncedByGUID)
    wipe(syncedByCleanKey)
    wipe(altGUIDByCleanKey)
    peerCacheValid = true

    if SfuiDB and type(SfuiDB.alts) == "table" then
        for guid, alt in pairs(SfuiDB.alts) do
            if type(alt) == "table" then
                local c = clean_key(alt.name or "")
                if c ~= "" then
                    altGUIDByCleanKey[c] = guid
                    if guid ~= myGUID and c ~= myClean then
                        syncedByGUID[guid] = true
                        syncedByCleanKey[c] = true
                    end
                end
            end
        end
    end

    local s = sync.GetSettings and sync.GetSettings()
    if s and type(s.peers) == "table" then
        for _, p in pairs(s.peers) do
            if type(p) == "table" and p.trusted and p.name then
                local c = clean_key(p.name)
                if c ~= "" and c ~= myClean then
                    syncedByCleanKey[c] = true
                    if p.guid then syncedByGUID[p.guid] = true end
                end
            end
        end
    end

    local bcs = _G.Blizzard_Console_SavedVars
    if type(bcs) == "table" and type(bcs.sfui_sync) == "table" and type(bcs.sfui_sync.peers) == "table" then
        for _, mp in pairs(bcs.sfui_sync.peers) do
            if type(mp) == "table" and mp.name then
                local c = clean_key(mp.name)
                if c ~= "" and c ~= myClean then
                    syncedByCleanKey[c] = true
                    if mp.guid then syncedByGUID[mp.guid] = true end
                end
            end
        end
    end
end

function multibox.GetAltByCleanKey(cleanKeyStr)
    if not cleanKeyStr or cleanKeyStr == "" then return nil, nil end
    ensure_peer_cache()
    local guid = altGUIDByCleanKey[cleanKeyStr]
    if guid and SfuiDB and type(SfuiDB.alts) == "table" then
        return SfuiDB.alts[guid], guid
    end
    return nil, nil
end

function multibox.IsSyncedCharacter(nameOrGUID)
    if not nameOrGUID or nameOrGUID == "" then return false end
    ensure_peer_cache()
    if syncedByGUID[nameOrGUID] then
        return true
    end
    local clean = clean_key(nameOrGUID)
    if clean ~= "" and syncedByCleanKey[clean] then
        return true
    end
    return false
end

function multibox.FindPartyUnitByName(targetName)
    if not targetName or targetName == "" then return nil, nil end
    if same_char(targetName, full_name("player")) then
        return "player", full_name("player")
    end
    if not (IsInGroup and IsInGroup()) then return nil, nil end
    local isRaid = IsInRaid and IsInRaid()
    local count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    local prefix = isRaid and "raid" or "party"
    local maxIdx = isRaid and count or math.min(4, count)
    for i = 1, maxIdx do
        local u = prefix .. i
        if UnitExists and UnitExists(u) and not (UnitIsUnit and UnitIsUnit(u, "player")) then
            local n = full_name(u)
            if n and same_char(n, targetName) then
                return u, cmd_name(n)
            end
        end
    end
    return nil, nil
end

function multibox.HasSyncedPartyMember()
    if not (IsInGroup and IsInGroup()) then return false end
    local isRaid = IsInRaid and IsInRaid()
    local count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    local prefix = isRaid and "raid" or "party"
    local maxIdx = isRaid and count or math.min(4, count)
    for i = 1, maxIdx do
        local u = prefix .. i
        if UnitExists and UnitExists(u) and not (UnitIsUnit and UnitIsUnit(u, "player")) then
            local g = UnitGUID and UnitGUID(u)
            local n = full_name(u)
            if (g and multibox.IsSyncedCharacter(g)) or (n and multibox.IsSyncedCharacter(n)) then
                return true
            end
        end
    end
    return false
end

function multibox.IsActiveSyncParty()
    local s = sync.GetSettings and sync.GetSettings()
    if not s or not s.enabled then return false end
    return multibox.HasSyncedPartyMember()
end

-- ── Per-Character "Away / Paused" Mode (`Mama/Team.lua:196-226`) ─────────────
function sync.IsAway(name)
    local target = name or full_name("player")
    if not target or target == "" then return false end
    local key = clean_key(target)
    local s = sync.GetSettings and sync.GetSettings()
    if s and type(s.awayPeers) == "table" and s.awayPeers[key] ~= nil then
        return s.awayPeers[key] == true
    end
    return awayMap[key] == true
end

function sync.SetAway(name, isAway, announce)
    local target = name or full_name("player")
    if not target or target == "" then return end
    local key = clean_key(target)
    local val = isAway and true or nil
    awayMap[key] = val

    local s = sync.GetSettings and sync.GetSettings()
    if s then
        s.awayPeers = type(s.awayPeers) == "table" and s.awayPeers or {}
        s.awayPeers[key] = val
    end
    local bcs = _G.Blizzard_Console_SavedVars
    if type(bcs) == "table" then
        bcs.sfui_sync = type(bcs.sfui_sync) == "table" and bcs.sfui_sync or {}
        bcs.sfui_sync.awayPeers = type(bcs.sfui_sync.awayPeers) == "table" and bcs.sfui_sync.awayPeers or {}
        bcs.sfui_sync.awayPeers[key] = val
    end

    if announce ~= false and multibox.HasSyncedPartyMember() then
        sync.Broadcast("DELTA_AWAY", {
            pass = (s and s.passcode ~= "" and s.passcode) or nil,
            name = cmd_name(target),
            away = val and 1 or 0,
        }, false, false)
    end
    if sfui.common and sfui.common.print and announce ~= false then
        sfui.common.print(string_format("sync: |cff00ffff%s|r is now %s.",
            key, val and "|cff8099bfaway (paused)|r" or "|cff00ff88back (active)|r"))
    end
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_SYNC_STATUS_UPDATED")
    end
end

function sync.ToggleAway(name)
    local target = name or full_name("player")
    if not target or target == "" then return end
    sync.SetAway(target, not sync.IsAway(target), true)
end

-- ── Synced Leader Resolution ──────────────────────────────────────────────────
function multibox.GetSyncedLeaderUnit(preferName)
    if not (IsInGroup and IsInGroup()) then return nil, nil end
    local isRaid = IsInRaid and IsInRaid()
    local count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    local prefix = isRaid and "raid" or "party"
    local maxIdx = isRaid and count or math.min(4, count)

    local preferred = preferName or explicitLead
    if preferred and preferred ~= "" and not same_char(preferred, full_name("player")) then
        local pUnit, pName = multibox.FindPartyUnitByName(preferred)
        if pUnit then
            return pUnit, pName
        end
    end

    local leaderUnit, leaderName = nil, nil
    local fallbackUnit, fallbackName = nil, nil
    local anyLeaderUnit, anyLeaderName = nil, nil
    local anyPartyUnit, anyPartyName = nil, nil

    for i = 1, maxIdx do
        local u = prefix .. i
        if UnitExists and UnitExists(u) and not (UnitIsUnit and UnitIsUnit(u, "player")) then
            local g = UnitGUID and UnitGUID(u)
            local n = full_name(u)
            local cName = cmd_name(n)
            if UnitIsGroupLeader and UnitIsGroupLeader(u) then
                anyLeaderUnit = u
                anyLeaderName = cName
            elseif not anyPartyUnit and not isRaid and count <= 2 then
                anyPartyUnit = u
                anyPartyName = cName
            end
            if (g and multibox.IsSyncedCharacter(g)) or (n and multibox.IsSyncedCharacter(n)) then
                if UnitIsGroupLeader and UnitIsGroupLeader(u) then
                    leaderUnit = u
                    leaderName = cName
                elseif not fallbackUnit and not sync.IsAway(cName) then
                    fallbackUnit = u
                    fallbackName = cName
                end
            end
        end
    end

    if leaderUnit then return leaderUnit, leaderName end
    if fallbackUnit then return fallbackUnit, fallbackName end
    if anyLeaderUnit then return anyLeaderUnit, anyLeaderName end
    return anyPartyUnit, anyPartyName
end

local function load_saved_lead()
    if explicitLead and explicitLead ~= "" then return explicitLead end
    local bcs = _G.Blizzard_Console_SavedVars
    if type(bcs) == "table" and type(bcs.sfui_sync) == "table" then
        if type(bcs.sfui_sync.awayPeers) == "table" then
            for k, v in pairs(bcs.sfui_sync.awayPeers) do
                awayMap[k] = v and true or nil
            end
        end
        if type(bcs.sfui_sync.lead) == "string" and bcs.sfui_sync.lead ~= "" then
            explicitLead = bcs.sfui_sync.lead
            return explicitLead
        end
    end
    local s = sync.GetSettings and sync.GetSettings()
    if s and type(s.lead) == "string" and s.lead ~= "" then
        explicitLead = s.lead
        return explicitLead
    end
    return nil
end

local function save_lead_state(leadName)
    explicitLead = (leadName and leadName ~= "") and cmd_name(leadName) or nil
    local s = sync.GetSettings and sync.GetSettings()
    if s then
        s.lead = explicitLead
    end
    local bcs = _G.Blizzard_Console_SavedVars
    if type(bcs) == "table" then
        bcs.sfui_sync = type(bcs.sfui_sync) == "table" and bcs.sfui_sync or {}
        bcs.sfui_sync.lead = explicitLead
    end
end

function sync.GetLead()
    local saved = load_saved_lead()
    if saved and saved ~= "" then
        if same_char(saved, full_name("player")) then
            return cmd_name(full_name("player"))
        end
        local u, uName = multibox.FindPartyUnitByName(saved)
        if u and uName then
            return uName
        end
    end
    if IsInGroup and IsInGroup() then
        if UnitIsGroupLeader and UnitIsGroupLeader("player") then
            return cmd_name(full_name("player"))
        end
        local _, lName = multibox.GetSyncedLeaderUnit()
        if lName and lName ~= "" then
            return lName
        end
    end
    return saved or cmd_name(full_name("player"))
end

function sync.IsLead()
    local lead = sync.GetLead()
    local me = full_name("player")
    if not lead or not me then return true end
    return same_char(lead, me)
end

local function try_promote_to_leader(targetName)
    if not targetName or targetName == "" then return end
    if same_char(targetName, full_name("player")) then return end
    if not (IsInGroup and IsInGroup() and UnitIsGroupLeader and UnitIsGroupLeader("player")) then return end
    local u, uName = multibox.FindPartyUnitByName(targetName)
    if not u or not (UnitIsConnected and UnitIsConnected(u)) then return end
    local promoteFn = (_G.C_PartyInfo and _G.C_PartyInfo.PromoteToLeader) or _G.PromoteToLeader
    if promoteFn then
        promoteFn(uName or cmd_name(targetName))
    end
end

function sync.SetLead(name, announce)
    if not name or name == "" then return end
    local cleanLead = cmd_name(name)
    save_lead_state(cleanLead)
    if announce then
        local s = sync.GetSettings and sync.GetSettings()
        sync.Broadcast("CMD_LEAD", {
            pass = (s and s.passcode ~= "" and s.passcode) or nil,
            lead = cleanLead,
        }, true, false)
    end
    try_promote_to_leader(cleanLead)
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_SYNC_STATUS_UPDATED")
    end
end

function sync.MakeMeLead()
    local me = cmd_name(full_name("player"))
    if not me or me == "" then return end
    sync.SetLead(me, true)
    if sfui.common and sfui.common.print then
        sfui.common.print("sync: |cff00ffff" .. string_lower(me) .. "|r is now the multibox lead (all followers retargeted).")
    end
end

-- ── 1. Follow Range Alerts & Suppression (`Mama/Alerts.lua:45-149`) ───────────
local isCurrentlyFollowing = false
local lastFollowedName     = nil
local followStartTimer     = nil
local followBrokenTicker   = nil
local lastFollowLostSent   = 0
local lastCombatEndTime    = 0
local lastGraceTime        = 0
local followHookInstalled  = false

local function get_current_subzone()
    local sub = GetSubZoneText and GetSubZoneText()
    if sub and sub ~= "" then return sub end
    local z = GetZoneText and GetZoneText()
    if z and z ~= "" then return z end
    return ""
end

-- Suppress false-positive follow alerts when dead/ghost, on a flight path,
-- casting/channeling, within 5s after combat ends (looting), within 15s of a
-- loading screen / resurrect, or when either character is marked Away.
local function should_suppress_follow_alert(leaderUnit, leaderName)
    if sync.IsAway() then return true end
    if leaderName and sync.IsAway(leaderName) then return true end
    if InCombatLockdown and InCombatLockdown() then return true end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return true end
    if UnitOnTaxi and UnitOnTaxi("player") then return true end
    if UnitCastingInfo and UnitCastingInfo("player") then return true end
    if UnitChannelInfo and UnitChannelInfo("player") then return true end

    if leaderUnit and UnitExists and UnitExists(leaderUnit) then
        if UnitIsDeadOrGhost and UnitIsDeadOrGhost(leaderUnit) then return true end
        if UnitOnTaxi and UnitOnTaxi(leaderUnit) then return true end
    end

    local now = (GetTime and GetTime()) or 0
    if (now - lastCombatEndTime) < 5.0 then return true end
    if (now - lastGraceTime) < 15.0 then return true end
    return false
end

local function send_follow_lost_alert(reason, targetName)
    local now = (GetTime and GetTime()) or 0
    if (now - lastFollowLostSent) < 3.0 then return end
    lastFollowLostSent = now
    local s = sync.GetSettings and sync.GetSettings()
    if not s or not s.enabled or s.mbAutoFollow == false then return end
    sync.Broadcast("DELTA_FOLLOW_LOST", {
        pass   = (s.passcode ~= "" and s.passcode) or nil,
        target = targetName or lastFollowedName,
        reason = reason or "stopped",
        zone   = get_current_subzone(),
    }, false, false)
end

local function cancel_follow_timers()
    if followStartTimer and followStartTimer.Cancel then
        followStartTimer:Cancel()
    end
    followStartTimer = nil
    if followBrokenTicker and followBrokenTicker.Cancel then
        followBrokenTicker:Cancel()
    end
    followBrokenTicker = nil
end

local function ensure_follow_hook()
    if followHookInstalled then return end
    followHookInstalled = true
    if FollowUnit and _G.hooksecurefunc then
        _G.hooksecurefunc("FollowUnit", function(unitOrName)
            if not multibox.IsActiveSyncParty() then return end
            if not unitOrName or unitOrName == "player" or same_char(tostring(unitOrName), full_name("player")) then
                return
            end
            if followStartTimer and followStartTimer.Cancel then
                followStartTimer:Cancel()
            end
            if C_Timer and C_Timer.NewTimer then
                followStartTimer = C_Timer.NewTimer(1.0, function()
                    followStartTimer = nil
                    if isCurrentlyFollowing then return end
                    local s = sync.GetSettings and sync.GetSettings()
                    if not s or not s.enabled or s.mbAutoFollow == false then return end
                    if not multibox.IsActiveSyncParty() then return end
                    local u, uName = multibox.GetSyncedLeaderUnit()
                    if should_suppress_follow_alert(u, uName) then return end
                    if u and ((CheckInteractDistance and not CheckInteractDistance(u, 4)) or (UnitIsVisible and not UnitIsVisible(u))) then
                        if _G.UIErrorsFrame and _G.UIErrorsFrame.AddMessage then
                            _G.UIErrorsFrame:AddMessage("|cffff4444! out of follow range!|r", 1.0, 0.25, 0.25, 1.0)
                        end
                        send_follow_lost_alert("cant_follow", uName)
                    end
                end)
            end
        end)
    end
end

local function on_autofollow_begin(_, name)
    isCurrentlyFollowing = true
    cancel_follow_timers()
    if name and name ~= "" then
        lastFollowedName = cmd_name(name)
    end
end

local function on_autofollow_end()
    if not isCurrentlyFollowing then return end
    isCurrentlyFollowing = false
    cancel_follow_timers()

    local s = sync.GetSettings and sync.GetSettings()
    if not s or not s.enabled or s.mbAutoFollow == false then return end
    if not multibox.IsActiveSyncParty() then return end
    if sync.IsAway() then return end

    if (_G.GossipFrame and _G.GossipFrame:IsShown())
        or (_G.QuestFrame and _G.QuestFrame:IsShown())
        or (_G.MerchantFrame and _G.MerchantFrame:IsShown())
        or (_G.TaxiFrame and _G.TaxiFrame:IsShown())
        or (_G.FlightMapFrame and _G.FlightMapFrame:IsShown())
        or (_G.ClassTrainerFrame and _G.ClassTrainerFrame:IsShown())
        or (_G.TradeFrame and _G.TradeFrame:IsShown()) then
        return
    end

    if C_Timer and C_Timer.NewTicker then
        followBrokenTicker = C_Timer.NewTicker(1.0, function()
            if isCurrentlyFollowing then
                cancel_follow_timers()
                return
            end
            local u, uName = multibox.GetSyncedLeaderUnit(lastFollowedName)
            if not u then
                cancel_follow_timers()
                return
            end
            if should_suppress_follow_alert(u, uName) then
                return
            end
            local outOfRange = (CheckInteractDistance and not CheckInteractDistance(u, 4))
                or (UnitIsVisible and not UnitIsVisible(u))
            if outOfRange then
                cancel_follow_timers()
                send_follow_lost_alert("stopped", uName or lastFollowedName)
            end
        end, 10)
    end
end

-- ── 2. Party Assembly, Invite, Summon & Resurrect ─────────────────────────────
function sync.FormSyncedParty()
    local s = sync.GetSettings and sync.GetSettings()
    if not s or not s.enabled then
        if sfui.common and sfui.common.print then
            sfui.common.print("sync: multi-account sync is disabled.")
        end
        return
    end

    local inviteFn = (_G.C_PartyInfo and _G.C_PartyInfo.InviteUnit) or _G.InviteUnit
    if not inviteFn then return end

    local partyNames = {}
    if IsInGroup and IsInGroup() then
        local isRaid = IsInRaid and IsInRaid()
        local count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
        local prefix = isRaid and "raid" or "party"
        local maxIdx = isRaid and count or math.min(4, count)
        for i = 1, maxIdx do
            local n = full_name(prefix .. i)
            if n then partyNames[clean_key(n)] = true end
        end
    end

    local myClean = clean_key(full_name("player") or "")
    local invited = 0
    local accounts = {}

    local function consider_peer(p)
        if type(p) ~= "table" or not p.name then return end
        local clean = clean_key(p.name)
        if clean ~= "" and clean ~= myClean and not partyNames[clean] and not sync.IsAway(clean) then
            local acctKey = (p.accountID and p.accountID ~= "" and p.accountID)
                or (p.accountLabel and p.accountLabel ~= "" and ("label:" .. string_lower(p.accountLabel)))
                or clean
            local best = accounts[acctKey]
            if not best or ((tonumber(p.lastSeen) or 0) > (tonumber(best.lastSeen) or 0)) then
                accounts[acctKey] = p
            end
        end
    end

    for _, p in pairs(s.peers or {}) do
        if type(p) == "table" and p.trusted then
            consider_peer(p)
        end
    end
    local bcs = _G.Blizzard_Console_SavedVars
    if type(bcs) == "table" and type(bcs.sfui_sync) == "table" and type(bcs.sfui_sync.peers) == "table" then
        for _, mp in pairs(bcs.sfui_sync.peers) do
            consider_peer(mp)
        end
    end

    for _, p in pairs(accounts) do
        inviteFn(cmd_name(p.name))
        invited = invited + 1
    end

    if sfui.common and sfui.common.print then
        if invited > 0 then
            sfui.common.print(string_format("sync: sent party invites to %d linked account(s).", invited))
        else
            sfui.common.print("sync: all active linked accounts are already in the party (or none linked).")
        end
    end
end

local function on_party_invite_request(_, inviterName)
    local s = sync.GetSettings and sync.GetSettings()
    if not s or not s.enabled or s.mbAutoInvite == false then return end
    if sync.IsAway() then return end
    if IsShiftKeyDown and IsShiftKeyDown() then return end
    if not inviterName or not multibox.IsSyncedCharacter(inviterName) then return end

    if _G.AcceptGroup then
        _G.AcceptGroup()
    end
    if _G.StaticPopup_Hide then
        _G.StaticPopup_Hide("PARTY_INVITE")
        _G.StaticPopup_Hide("PARTY_INVITE_XREALM")
    end
    if sfui.common and sfui.common.print then
        sfui.common.print("sync: auto-accepted party invite from |cff00ffff" .. clean_key(inviterName) .. "|r.")
    end
end

local function on_confirm_summon()
    local s = sync.GetSettings and sync.GetSettings()
    if not s or not s.enabled or s.mbAutoInvite == false then return end
    if sync.IsAway() then return end
    if IsShiftKeyDown and IsShiftKeyDown() then return end
    if InCombatLockdown and InCombatLockdown() then return end

    local summoner = (_G.C_SummonInfo and _G.C_SummonInfo.GetSummonConfirmSummoner and _G.C_SummonInfo.GetSummonConfirmSummoner())
        or (_G.GetSummonConfirmSummoner and _G.GetSummonConfirmSummoner())
    if not multibox.HasSyncedPartyMember() and not (summoner and multibox.IsSyncedCharacter(summoner)) then
        return
    end

    if _G.C_SummonInfo and _G.C_SummonInfo.ConfirmSummon then
        _G.C_SummonInfo.ConfirmSummon()
    elseif _G.ConfirmSummon then
        _G.ConfirmSummon()
    end
    if _G.StaticPopup_Hide then
        _G.StaticPopup_Hide("CONFIRM_SUMMON")
    end
    if sfui.common and sfui.common.print then
        sfui.common.print("sync: auto-accepted summon.")
    end
end

local function on_resurrect_request(_, resserName)
    local s = sync.GetSettings and sync.GetSettings()
    if not s or not s.enabled or s.mbAutoInvite == false then return end
    if sync.IsAway() then return end
    if IsShiftKeyDown and IsShiftKeyDown() then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if not multibox.HasSyncedPartyMember() and not (resserName and multibox.IsSyncedCharacter(resserName)) then
        return
    end

    if _G.AcceptResurrect then
        _G.AcceptResurrect()
    end
    if _G.StaticPopup_Hide then
        _G.StaticPopup_Hide("RESURRECT")
        _G.StaticPopup_Hide("RESURRECT_NO_SICKNESS")
        _G.StaticPopup_Hide("RESURRECT_NO_TIMER")
    end
    if sfui.common and sfui.common.print then
        sfui.common.print("sync: auto-accepted resurrection.")
    end
end

-- ── 3. Synchronized Flight Master Destinations (TakeTaxiNode) ─────────────────
local isAutoTakingTaxi = false
local taxiHookInstalled = false
local taxiNodeNames = {}
local lastSyncedTaxi = {
    name   = nil,
    sender = nil,
    time   = 0,
}

local function cache_taxi_nodes()
    wipe(taxiNodeNames)
    local numNodes = (_G.NumTaxiNodes and _G.NumTaxiNodes()) or 0
    for i = 1, numNodes do
        local nName = _G.TaxiNodeName and _G.TaxiNodeName(i)
        if nName and nName ~= "" then
            taxiNodeNames[i] = nName
        end
    end
    if _G.C_TaxiMap and _G.C_TaxiMap.GetAllTaxiNodes and _G.GetTaxiMapID then
        local mapID = _G.GetTaxiMapID()
        if mapID then
            for _, node in ipairs(_G.C_TaxiMap.GetAllTaxiNodes(mapID) or {}) do
                if node.slotIndex and node.name and node.name ~= "" then
                    taxiNodeNames[node.slotIndex] = node.name
                end
            end
        end
    end
end

local function ensure_taxi_hook()
    if taxiHookInstalled then return end
    taxiHookInstalled = true
    if _G.TakeTaxiNode and _G.hooksecurefunc then
        _G.hooksecurefunc("TakeTaxiNode", function(slotIndex)
            if isAutoTakingTaxi then return end
            if not multibox.IsActiveSyncParty() then return end
            local s = sync.GetSettings and sync.GetSettings()
            if not s or not s.enabled or s.mbAutoTaxi == false then return end
            local nodeName = taxiNodeNames[slotIndex] or (_G.TaxiNodeName and _G.TaxiNodeName(slotIndex))
            if nodeName and nodeName ~= "" then
                sync.Broadcast("DELTA_TAXI", {
                    pass = (s.passcode ~= "" and s.passcode) or nil,
                    name = nodeName,
                }, true, false)
            end
        end)
    end
end

local function try_take_synced_taxi()
    if isAutoTakingTaxi then return false end
    local s = sync.GetSettings and sync.GetSettings()
    if not s or not s.enabled or s.mbAutoTaxi == false then return false end
    if sync.IsAway() then return false end
    if IsShiftKeyDown and IsShiftKeyDown() then return false end
    local now = (GetTime and GetTime()) or 0
    local targetName = lastSyncedTaxi.name
    if not targetName or targetName == "" or (now - lastSyncedTaxi.time) > 45.0 then return false end

    local numNodes = (_G.NumTaxiNodes and _G.NumTaxiNodes()) or 0
    if numNodes <= 0 then return false end

    local targetLower = string_lower(targetName)
    for i = 1, numNodes do
        local nName = (_G.TaxiNodeName and _G.TaxiNodeName(i)) or taxiNodeNames[i]
        if nName and (nName == targetName or string_lower(nName) == targetLower) then
            local nType = _G.TaxiNodeGetType and _G.TaxiNodeGetType(i)
            if (nType == "REACHABLE" or nType == "DISTANT") and _G.TakeTaxiNode then
                local senderLabel = lastSyncedTaxi.sender or "party"
                lastSyncedTaxi.name = nil
                isAutoTakingTaxi = true
                if _G.GetNumRoutes then
                    _G.GetNumRoutes(i) -- required by C++ before taking a multi-hop node that wasn't hovered
                end
                _G.TakeTaxiNode(i)
                isAutoTakingTaxi = false
                if sfui.common and sfui.common.print then
                    sfui.common.print(string_format("sync: auto-flying to |cff00ffff%s|r (synced with %s).",
                        string_lower(nName), string_lower(senderLabel)))
                end
                return true
            end
        end
    end
    return false
end

local function on_taximap_opened()
    cache_taxi_nodes()
    if not try_take_synced_taxi() and C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            cache_taxi_nodes()
            try_take_synced_taxi()
        end)
    end
end

-- ── 4. Follower Loot-Roll Auto-Pass ───────────────────────────────────────────
local function on_start_loot_roll(_, rollID)
    local s = sync.GetSettings and sync.GetSettings()
    if not s or not s.enabled or not s.mbFollowerPassLoot then return end
    if IsShiftKeyDown and IsShiftKeyDown() then return end
    if not rollID or not _G.RollOnLoot then return end
    if not multibox.IsActiveSyncParty() then return end
    if sync.IsLead() then return end

    local link = _G.GetLootRollItemLink and _G.GetLootRollItemLink(rollID)
    local itemID = link and tonumber(string_match(link, "item:(%d+)"))
    if itemID and sfui.dungeonjournal and sfui.dungeonjournal.IsWishlisted and sfui.dungeonjournal.IsWishlisted(itemID) then
        if sfui.common and sfui.common.print then
            sfui.common.print("sync: keeping loot roll open for wishlisted item " .. (link or ("#" .. itemID)) .. ".")
        end
        return
    end

    _G.RollOnLoot(rollID, 0) -- 0 = Pass
end

-- ── 5. Corpse Shared Quest-Item Alert (`Mama/Loot.lua:360-475, 593-617`) ─────
local pendingCorpseReminders = {} -- [itemName] = { char1, char2, ... }

local function strip_objective_counts(text)
    if type(text) ~= "string" then return nil end
    local clean = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local have, need = clean:match("(%d+)%s*/%s*(%d+)")
    if not have or not need then return nil, nil, nil end
    local itemName = clean:gsub("%s*:?%s*%d+%s*/%s*%d+%s*", "", 1):gsub("^[%s%-]+", ""):gsub("%s+$", "")
    return (itemName ~= "" and itemName or nil), tonumber(have), tonumber(need)
end

local function get_party_member_lookup()
    local byName = {}
    local myShort = cmd_name(full_name("player") or "")
    if myShort ~= "" then
        byName[string_lower(myShort)] = myShort
    end
    if IsInGroup and IsInGroup() then
        local isRaid = IsInRaid and IsInRaid()
        local count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
        local prefix = isRaid and "raid" or "party"
        local maxIdx = isRaid and count or math.min(4, count)
        for i = 1, maxIdx do
            local u = prefix .. i
            if UnitExists and UnitExists(u) then
                local g = UnitGUID and UnitGUID(u)
                local n = full_name(u)
                if (g and multibox.IsSyncedCharacter(g)) or (n and multibox.IsSyncedCharacter(n)) then
                    local short = cmd_name(n)
                    if short ~= "" and not sync.IsAway(short) then
                        byName[string_lower(short)] = short
                    end
                end
            end
        end
    end
    return byName
end

local CORPSE_UNIT_TOKENS = { "softinteract", "mouseover", "target" }

local function scan_tooltip_lines_for_quest_item(lines, targetItemLower, byName, needsMap, myShort)
    if type(lines) ~= "table" then return false end
    local currentWho = nil
    local foundTargetItem = false
    local LINE_TYPE = _G.Enum and _G.Enum.TooltipDataLineType
    for _, line in ipairs(lines) do
        local raw = (line and line.leftText) or ""
        local clean = raw:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")
        local cleanLower = string_lower(clean)
        local itemName, have, need = strip_objective_counts(clean)
        if LINE_TYPE and line.type == LINE_TYPE.QuestTitle then
            currentWho = myShort
        elseif not have and byName[cleanLower] then
            currentWho = byName[cleanLower]
        elseif itemName and have and need and string_lower(itemName) == targetItemLower then
            foundTargetItem = true
            if currentWho and currentWho ~= myShort and have < need and not sync.IsAway(currentWho) then
                needsMap[string_lower(currentWho)] = true
            end
        end
    end
    return foundTargetItem
end

local function find_others_needing_quest_item(slot, itemName, questID)
    local byName = get_party_member_lookup()
    local myShort = cmd_name(full_name("player") or "")
    local myShortLower = string_lower(myShort)
    local targetItemLower = string_lower(itemName or "")
    local needsMap = {}

    local C_TooltipInfo = _G.C_TooltipInfo
    if C_TooltipInfo then
        local guid = _G.GetLootSourceInfo and _G.GetLootSourceInfo(slot)
        for _, u in ipairs(CORPSE_UNIT_TOKENS) do
            if UnitExists and UnitExists(u) and UnitIsDead and UnitIsDead(u) and (not guid or (UnitGUID and UnitGUID(u) == guid)) then
                if C_TooltipInfo.GetUnit then
                    local data = C_TooltipInfo.GetUnit(u)
                    if data and data.lines then
                        scan_tooltip_lines_for_quest_item(data.lines, targetItemLower, byName, needsMap, myShort)
                    end
                end
                break
            end
        end

        if C_TooltipInfo.GetQuestPartyProgress then
            if questID and questID > 0 then
                local data = C_TooltipInfo.GetQuestPartyProgress(questID, true)
                if data and data.lines then
                    scan_tooltip_lines_for_quest_item(data.lines, targetItemLower, byName, needsMap, myShort)
                end
            elseif _G.C_QuestLog and _G.C_QuestLog.GetNumQuestLogEntries then
                local numEntries = _G.C_QuestLog.GetNumQuestLogEntries() or 0
                for i = 1, numEntries do
                    local info = _G.C_QuestLog.GetInfo and _G.C_QuestLog.GetInfo(i)
                    if info and not info.isHeader and info.questID then
                        local data = C_TooltipInfo.GetQuestPartyProgress(info.questID, true)
                        if data and data.lines and scan_tooltip_lines_for_quest_item(data.lines, targetItemLower, byName, needsMap, myShort) then
                            break
                        end
                    end
                end
            end
        end
    end

    -- Fallback check against synced quest logs in `SfuiDB.alts[guid].activeQuests`
    for cleanPeer in pairs(byName) do
        if cleanPeer ~= myShortLower and not needsMap[cleanPeer] then
            local alt = multibox.GetAltByCleanKey(cleanPeer)
            if type(alt) == "table" and type(alt.activeQuests) == "table" then
                if questID and questID > 0 then
                    local qEntry = alt.activeQuests[questID]
                    if type(qEntry) == "table" and qEntry.c ~= 1 then
                        needsMap[cleanPeer] = true
                    end
                elseif targetItemLower ~= "" then
                    for _, qEntry in pairs(alt.activeQuests) do
                        if type(qEntry) == "table" and qEntry.c ~= 1 and type(qEntry.o) == "table" then
                            for _, objStr in ipairs(qEntry.o) do
                                local objItem, have, need = strip_objective_counts(objStr)
                                if objItem and have and need and have < need and string_lower(objItem) == targetItemLower then
                                    needsMap[cleanPeer] = true
                                    break
                                end
                            end
                        end
                        if needsMap[cleanPeer] then break end
                    end
                end
            end
        end
    end

    local others = {}
    for who in pairs(needsMap) do
        table_insert(others, who)
    end
    table_sort(others)
    return others
end

local function show_corpse_quest_alert(msg)
    if not msg or msg == "" then return end
    local text = "|cffff4444! " .. string_lower(msg) .. "|r"
    if _G.RaidNotice_AddMessage and _G.RaidWarningFrame and _G.ChatTypeInfo then
        _G.RaidNotice_AddMessage(_G.RaidWarningFrame, text, _G.ChatTypeInfo["RAID_WARNING"])
    elseif _G.UIErrorsFrame and _G.UIErrorsFrame.AddMessage then
        _G.UIErrorsFrame:AddMessage(text, 1.0, 0.25, 0.25, 1.0)
    end
    if _G.PlaySound then
        _G.PlaySound((_G.SOUNDKIT and _G.SOUNDKIT.RAID_WARNING) or 8959, "Master")
    end
    if sfui.common and sfui.common.print then
        sfui.common.print("sync: " .. text)
    end
end

local function on_loot_opened()
    local s = sync.GetSettings and sync.GetSettings()
    if not s or not s.enabled or s.mbCorpseAlert == false then return end
    if not multibox.IsActiveSyncParty() then return end

    wipe(pendingCorpseReminders)
    local numLoot = (_G.GetNumLootItems and _G.GetNumLootItems()) or 0
    local GetItemInfo = (sfui.common and sfui.common.get_item_info) or _G.GetItemInfo
    local questClass = (_G.Enum and _G.Enum.ItemClass and _G.Enum.ItemClass.Questitem) or 12

    for slot = 1, numLoot do
        local link = _G.GetLootSlotLink and _G.GetLootSlotLink(slot)
        local _, itemName, _, _, _, _, isQuestItem, questId = nil, nil, nil, nil, nil, nil, false, nil
        if _G.GetLootSlotInfo then
            _, itemName, _, _, _, _, isQuestItem, questId = _G.GetLootSlotInfo(slot)
        end
        if link and itemName then
            local _, _, _, _, _, _, _, maxStack, _, _, _, classID = GetItemInfo(link)
            local isQuest = isQuestItem or (questId and questId > 0) or (classID == questClass)
            if isQuest and (not maxStack or maxStack <= 1) then
                local others = find_others_needing_quest_item(slot, itemName, questId)
                if #others > 0 then
                    pendingCorpseReminders[string_lower(itemName)] = others
                end
            end
        end
    end
end

local function on_loot_closed()
    if not next(pendingCorpseReminders) then return end
    local parts = {}
    for itemName, names in pairs(pendingCorpseReminders) do
        table_insert(parts, string_format("%s (%s)", itemName, table_concat(names, ", ")))
    end
    wipe(pendingCorpseReminders)
    if #parts == 0 then return end
    table_sort(parts)

    local msg = "loot quest copy from corpse: " .. table_concat(parts, "; ")
    if sync.IsLead() then
        show_corpse_quest_alert(msg)
    else
        local s = sync.GetSettings and sync.GetSettings()
        sync.Broadcast("DELTA_CORPSE_QUEST", {
            pass = (s and s.passcode ~= "" and s.passcode) or nil,
            msg  = msg,
        }, false, false)
        show_corpse_quest_alert(msg)
    end
end

-- ── Incoming Sync Message Handler Hook ────────────────────────────────────────
function multibox.HandleSyncMessage(sender, msgType, data)
    local s = sync.GetSettings and sync.GetSettings()
    if not s or not s.enabled then return end

    if msgType == "CMD_LEAD" and type(data) == "table" and data.lead then
        local newLead = cmd_name(data.lead)
        save_lead_state(newLead)
        lastFollowedName = newLead
        try_promote_to_leader(newLead)
        if sfui.common and sfui.common.print then
            sfui.common.print("sync: |cff00ffff" .. string_lower(newLead) .. "|r is now the multibox lead.")
        end
    elseif msgType == "DELTA_FOLLOW_LOST" and s.mbAutoFollow ~= false then
        local cleanSender = clean_key(sender)
        local reason = (type(data) == "table" and data.reason == "cant_follow") and "can't follow" or "stopped following"
        local zone = (type(data) == "table" and type(data.zone) == "string" and data.zone ~= "")
            and (" near " .. string_lower(data.zone))
            or ""
        local warnText = "|cffff4444! " .. cleanSender .. " " .. reason .. zone .. "!|r"
        if _G.UIErrorsFrame and _G.UIErrorsFrame.AddMessage then
            _G.UIErrorsFrame:AddMessage(warnText, 1.0, 0.25, 0.25, 1.0)
        end
        if _G.PlaySound then
            _G.PlaySound((_G.SOUNDKIT and _G.SOUNDKIT.RAID_WARNING) or 8959, "Master")
        end
        if sfui.common and sfui.common.print then
            sfui.common.print("sync: " .. warnText)
        end
    elseif msgType == "DELTA_AWAY" and type(data) == "table" then
        local target = data.name or sender
        local isAway = (tonumber(data.away) == 1)
        sync.SetAway(target, isAway, false)
    elseif msgType == "DELTA_CORPSE_QUEST" and s.mbCorpseAlert ~= false and type(data) == "table" then
        if sync.IsLead() and data.msg then
            show_corpse_quest_alert(data.msg)
        end
    elseif msgType == "DELTA_TAXI" and s.mbAutoTaxi ~= false and type(data) == "table" then
        lastSyncedTaxi.name   = data.name
        lastSyncedTaxi.sender = cmd_name(sender)
        lastSyncedTaxi.time   = (GetTime and GetTime()) or 0
        if not try_take_synced_taxi() and C_Timer and C_Timer.After then
            C_Timer.After(0, try_take_synced_taxi)
        end
    elseif (msgType == "DELTA_DIALOG" or msgType == "DELTA_GOSSIP" or msgType == "DELTA_QUEST_ABANDON")
        and sync.quests and sync.quests.HandleSyncMessage then
        sync.quests.HandleSyncMessage(sender, msgType, data)
    elseif msgType == "DELTA_HUD_STATS" and sync.hud and sync.hud.HandleSyncMessage then
        sync.hud.HandleSyncMessage(sender, msgType, data)
    end
end

-- ── Lazy Party-Sync Lifecycle Coordinator ─────────────────────────────────────
local partySubmodules = {}
local partyListenersActive = false

local function on_player_regen_enabled()
    lastCombatEndTime = (GetTime and GetTime()) or 0
end

local function on_grace_event()
    lastGraceTime = (GetTime and GetTime()) or 0
end

local PARTY_ONLY_EVENTS = {
    { "AUTOFOLLOW_BEGIN",      on_autofollow_begin },
    { "AUTOFOLLOW_END",        on_autofollow_end },
    { "CONFIRM_SUMMON",        on_confirm_summon },
    { "RESURRECT_REQUEST",     on_resurrect_request },
    { "TAXIMAP_OPENED",        on_taximap_opened },
    { "START_LOOT_ROLL",       on_start_loot_roll },
    { "LOOT_OPENED",           on_loot_opened },
    { "LOOT_CLOSED",           on_loot_closed },
    { "PLAYER_REGEN_ENABLED",  on_player_regen_enabled },
    { "PLAYER_ALIVE",          on_grace_event },
    { "PLAYER_UNGHOST",        on_grace_event },
    { "PLAYER_CONTROL_GAINED", on_grace_event },
}

function multibox.UpdatePartySyncState()
    local shouldBeActive = multibox.IsActiveSyncParty()
    if shouldBeActive and not partyListenersActive then
        partyListenersActive = true
        lastGraceTime = (GetTime and GetTime()) or 0
        ensure_follow_hook()
        ensure_taxi_hook()
        if sfui.events and sfui.events.RegisterEvent then
            for _, entry in ipairs(PARTY_ONLY_EVENTS) do
                sfui.events.RegisterEvent(entry[1], entry[2])
            end
        end
        for _, mod in ipairs(partySubmodules) do
            if mod.Enable then
                mod.Enable()
            end
        end
    elseif not shouldBeActive and partyListenersActive then
        partyListenersActive = false
        cancel_follow_timers()
        wipe(pendingCorpseReminders)
        if sfui.events and sfui.events.UnregisterEvent then
            for _, entry in ipairs(PARTY_ONLY_EVENTS) do
                sfui.events.UnregisterEvent(entry[1], entry[2])
            end
        end
        for _, mod in ipairs(partySubmodules) do
            if mod.Disable then
                mod.Disable()
            end
        end
    elseif shouldBeActive then
        for _, mod in ipairs(partySubmodules) do
            if mod.Refresh then
                mod.Refresh()
            end
        end
    end
end

function multibox.RegisterPartySubmodule(mod)
    if type(mod) ~= "table" then return end
    table_insert(partySubmodules, mod)
    if partyListenersActive and mod.Enable then
        mod.Enable()
    end
end

-- Minimal bootstrap: only watches roster/login/invite so party submodules load on demand
if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        lastGraceTime = (GetTime and GetTime()) or 0
        multibox.InvalidatePeerCache()
        load_saved_lead()
        multibox.UpdatePartySyncState()
    end)
    sfui.events.RegisterEvent("GROUP_ROSTER_UPDATE", function()
        multibox.UpdatePartySyncState()
    end)
    sfui.events.RegisterEvent("PARTY_INVITE_REQUEST", on_party_invite_request)
end

if sfui.events and sfui.events.RegisterMessage then
    sfui.events.RegisterMessage("SFUI_SYNC_PEERS_UPDATED", function()
        multibox.InvalidatePeerCache()
        multibox.UpdatePartySyncState()
    end)
    sfui.events.RegisterMessage("SFUI_ALT_SYNCED", function()
        multibox.InvalidatePeerCache()
    end)
    sfui.events.RegisterMessage("SFUI_SYNC_STATUS_UPDATED", function(_, key)
        if key == "PACKET" or key == "MANIFEST" then return end
        multibox.InvalidatePeerCache()
        multibox.UpdatePartySyncState()
    end)
end
