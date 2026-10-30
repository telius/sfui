local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.sync = sfui.sync or {}

local sync  = sfui.sync
local codec = sfui.sync.codec
local merge = sfui.sync.merge

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/sync/sync.lua
--  In-Game Multi-Account Content Synchronization Engine (SFUI_SYNC)
--
--  Synchronizes content databases across multiboxed WoW accounts via
--  PARTY/RAID, WHISPER, GUILD, and Battle.net GameData channels.
--  Strictly syncs content modules only (Alts, Recipes, Contacts, Fishing, Mail).
-- ══════════════════════════════════════════════════════════════════════════════

local PREFIX = "SFUI_SYNC"

local type = _G.type
local pairs = _G.pairs
local ipairs = _G.ipairs
local tonumber = _G.tonumber
local tostring = _G.tostring
local table_insert = table.insert
local string_lower = string.lower
local string_match = string.match
local string_format = string.format
local math_random = math.random
local UnitName = _G.UnitName
local UnitGUID = _G.UnitGUID
local UnitExists = _G.UnitExists
local UnitIsPlayer = _G.UnitIsPlayer
local UnitIsConnected = _G.UnitIsConnected
local GetRealmName = _G.GetRealmName
local GetServerTime = _G.GetServerTime
local GetTime = _G.GetTime
local time = _G.time
local IsInGroup = _G.IsInGroup
local IsInRaid = _G.IsInRaid
local IsInGuild = _G.IsInGuild
local GetNumGroupMembers = _G.GetNumGroupMembers
local GetNumGuildMembers = _G.GetNumGuildMembers
local GetGuildRosterInfo = _G.GetGuildRosterInfo
local C_ChatInfo = _G.C_ChatInfo
local C_Timer = _G.C_Timer
local C_FriendList = _G.C_FriendList
local BNGetNumFriends = _G.BNGetNumFriends
local C_BattleNet = _G.C_BattleNet
local ChatFrame_AddMessageEventFilter = _G.ChatFrame_AddMessageEventFilter

sync.stats = sync.stats or {
    packetsSent     = 0,
    packetsReceived = 0,
    bytesSent       = 0,
    bytesReceived   = 0,
    lastSyncTime    = 0,
    lastPeer        = nil,
}

-- Session-scoped online/offline state for peer characters (keyed by lowercase short name)
local onlinePeers  = {}
local offlinePeers = {}

local DEFAULT_SETTINGS = {
    enabled         = true,
    accountLabel    = "",
    passcode        = "",
    accountID       = "",
    syncAlts        = true,
    syncQuests      = true,
    syncWaypoints   = true,
    syncRecipes     = true,
    syncContacts    = true,
    syncFishing     = true,
    syncMail        = true,
    useParty        = true,
    useWhisper      = true,
    useGuild        = false,
    useBNet         = true,
    autoSyncOnLogin = true,
    peers           = {},
}

if sfui.db and sfui.db.RegisterDefaults then
    sfui.db.RegisterDefaults("sync", DEFAULT_SETTINGS)
end

-- ── Settings & Peer Storage ───────────────────────────────────────────────────
function sync.GetSettings()
    SfuiDB = SfuiDB or {}
    if type(SfuiDB.sync) ~= "table" then
        SfuiDB.sync = {}
    end
    local s = SfuiDB.sync
    if s.enabled == nil then s.enabled = true end
    if s.accountLabel == nil then s.accountLabel = "" end
    if s.passcode == nil then s.passcode = "" end
    if not s.accountID or s.accountID == "" then
        local now = (GetServerTime and GetServerTime()) or time()
        s.accountID = string_format("acct-%x-%04x", now, math_random(1, 65535))
    end

    -- Content module toggles
    if s.syncAlts == nil then s.syncAlts = true end
    if s.syncQuests == nil then s.syncQuests = true end
    if s.syncWaypoints == nil then s.syncWaypoints = true end
    if s.syncRecipes == nil then s.syncRecipes = true end
    if s.syncContacts == nil then s.syncContacts = true end
    if s.syncFishing == nil then s.syncFishing = true end
    if s.syncMail == nil then s.syncMail = true end

    -- Transport channel toggles
    if s.useParty == nil then s.useParty = true end
    if s.useWhisper == nil then s.useWhisper = true end
    if s.useGuild == nil then s.useGuild = false end
    if s.useBNet == nil then s.useBNet = true end
    if s.autoSyncOnLogin == nil then s.autoSyncOnLogin = true end

    if type(s.peers) ~= "table" then
        s.peers = {}
    end

    -- Retroactively group any legacy un-grouped peers so offline alts are never whispered individually
    if not s._peersAccountGrouped then
        s._peersAccountGrouped = true
        local maxSeenKey = nil
        local maxSeenTime = -1
        for k, p in pairs(s.peers) do
            if type(p) == "table" then
                if not p.accountID or p.accountID == "" then
                    p.accountID = (p.accountLabel and p.accountLabel ~= "") and ("label:" .. string_lower(p.accountLabel)) or "peer-acct-default"
                end
                local ls = tonumber(p.lastSync) or tonumber(p.lastSeen) or 0
                if ls > maxSeenTime then
                    maxSeenTime = ls
                    maxSeenKey = k
                end
            end
        end
        -- Clear synthetic bulk timestamps on non-active alts from prior roster import
        for k, p in pairs(s.peers) do
            if type(p) == "table" and k ~= maxSeenKey and not p.lastSync then
                p.lastSeen = 0
            end
        end
    end

    return s
end

local function get_current_realm()
    local r = (GetRealmName and GetRealmName()) or ""
    return r:gsub("%s+", "")
end

local function normalize_peer_key(nameOrFull, defaultRealm)
    if type(nameOrFull) ~= "string" then return nil, nil, nil end
    local trimmed = nameOrFull:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" then return nil, nil, nil end

    local shortName, realm = string_match(trimmed, "^([^%-]+)%-(.+)$")
    if not shortName then
        shortName = trimmed
        realm = defaultRealm or get_current_realm()
    else
        realm = realm:gsub("%s+", "")
    end

    local key = string_lower(shortName) .. "-" .. string_lower(realm or "")
    return key, shortName, realm
end

local function get_whisper_target(nameOrFull, peer)
    local _, shortName, realm = normalize_peer_key(nameOrFull, peer and peer.realm)
    if not shortName then return nameOrFull end
    local curRealm = get_current_realm()
    if sfui.isCamelot or not realm or realm == "" or string_lower(realm) == string_lower(curRealm) then
        return shortName
    end
    return shortName .. "-" .. realm
end

local function is_self_character(nameOrFull)
    local myName = UnitName and UnitName("player")
    if not myName then return false end
    local key, shortName = normalize_peer_key(nameOrFull)
    local myKey, myShort = normalize_peer_key(myName)
    if (key and myKey and key == myKey) or (shortName and myShort and string_lower(shortName) == string_lower(myShort)) then
        return true
    end
    local s = sync.GetSettings()
    local myAccountID = s.accountID or ""
    local myLabel = s.accountLabel or ""
    if SfuiDB and SfuiDB.alts and shortName then
        local lowerShort = string_lower(shortName)
        for guid, alt in pairs(SfuiDB.alts) do
            if type(alt) == "table" and alt.name and string_lower(alt.name) == lowerShort then
                if UnitGUID and guid == UnitGUID("player") then
                    return true
                end
                if myAccountID ~= "" and alt.accountID == myAccountID then
                    return true
                end
                if myLabel ~= "" and alt.accountLabel == myLabel then
                    return true
                end
            end
        end
    end
    return false
end

function sync.FindPeer(sender)
    if not sender then return nil, nil end
    local s = sync.GetSettings()
    local key, shortName = normalize_peer_key(sender)
    if key and s.peers[key] then
        return s.peers[key], key
    end
    if shortName then
        local lowerShort = string_lower(shortName)
        for k, p in pairs(s.peers) do
            if type(p) == "table" and p.name and string_lower(p.name) == lowerShort then
                return p, k
            end
        end
    end
    return nil, key
end

function sync.MarkPeerOnline(nameOrFull, peerAccountID)
    local _, shortName = normalize_peer_key(nameOrFull)
    if not shortName then return end
    local lowerShort = string_lower(shortName)
    local now = (GetTime and GetTime()) or 0

    -- A single WoW account only has one character online at a time:
    -- clear online status of other alts on that same peer account
    if peerAccountID and peerAccountID ~= "" then
        local s = sync.GetSettings()
        for _, p in pairs(s.peers) do
            if type(p) == "table" and p.accountID == peerAccountID and p.name then
                local pShort = string_lower(p.name)
                if pShort ~= lowerShort then
                    onlinePeers[pShort] = nil
                end
            end
        end
    end

    onlinePeers[lowerShort] = now
    offlinePeers[lowerShort] = nil
end

function sync.MarkPeerOffline(nameOrFull)
    local _, shortName = normalize_peer_key(nameOrFull)
    if not shortName then return end
    local lowerShort = string_lower(shortName)
    onlinePeers[lowerShort] = nil
    offlinePeers[lowerShort] = (GetTime and GetTime()) or 1
    if codec and codec.CancelWhispersToTarget then
        codec.CancelWhispersToTarget(shortName)
    end
end

-- Check Party/Raid, Friends, BNet, Guild, and session cache to see who is actually online
local function build_live_online_map()
    local map = {}
    for k, ts in pairs(onlinePeers) do
        if not offlinePeers[k] then
            map[k] = ts
        end
    end

    -- 1. Party / Raid
    if IsInGroup and IsInGroup() and GetNumGroupMembers then
        local n = GetNumGroupMembers()
        local prefixUnit = (IsInRaid and IsInRaid()) and "raid" or "party"
        for i = 1, n do
            local u = prefixUnit .. i
            if UnitExists and UnitExists(u) and (not UnitIsConnected or UnitIsConnected(u)) then
                local uName = UnitName(u)
                if uName then
                    local lower = string_lower(uName)
                    map[lower] = true
                    offlinePeers[lower] = nil
                end
            end
        end
    end

    -- 2. WoW Friends List
    if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
        local numFriends = C_FriendList.GetNumFriends() or 0
        for i = 1, numFriends do
            local info = C_FriendList.GetFriendInfoByIndex(i)
            if info and info.connected and info.name then
                local _, shortName = normalize_peer_key(info.name)
                if shortName then
                    local lower = string_lower(shortName)
                    map[lower] = true
                    offlinePeers[lower] = nil
                end
            end
        end
    end

    -- 3. Battle.net Friends
    if C_BattleNet and C_BattleNet.GetFriendGameAccountInfo and BNGetNumFriends then
        local _, numOnline = BNGetNumFriends()
        for i = 1, (numOnline or 0) do
            local numGameAccounts = (C_BattleNet.GetFriendNumGameAccounts and C_BattleNet.GetFriendNumGameAccounts(i)) or 0
            for j = 1, numGameAccounts do
                local gameInfo = C_BattleNet.GetFriendGameAccountInfo(i, j)
                if gameInfo and gameInfo.isOnline and gameInfo.clientProgram == "WoW" and gameInfo.characterName then
                    local lower = string_lower(gameInfo.characterName)
                    map[lower] = true
                    offlinePeers[lower] = nil
                end
            end
        end
    end

    -- 4. Guild Roster
    if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
        local numGuild = GetNumGuildMembers() or 0
        for i = 1, numGuild do
            local fullName, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
            if online and fullName then
                local _, shortName = normalize_peer_key(fullName)
                if shortName then
                    local lower = string_lower(shortName)
                    map[lower] = true
                    offlinePeers[lower] = nil
                end
            end
        end
    end

    return map
end

function sync.AddOrUpdatePeer(nameOrFull, meta)
    if is_self_character(nameOrFull) then return nil end
    local s = sync.GetSettings()
    local key, shortName, realm = normalize_peer_key(nameOrFull, meta and meta.realm)
    if not key or not shortName then return nil end

    local existing = s.peers[key]
    if not existing then
        local lowerShort = string_lower(shortName)
        for k, p in pairs(s.peers) do
            if type(p) == "table" and p.name and string_lower(p.name) == lowerShort then
                existing = p
                key = k
                break
            end
        end
    end

    local now = (GetServerTime and GetServerTime()) or time()
    if not existing then
        existing = {
            name      = shortName,
            realm     = realm or get_current_realm(),
            trusted   = true,
            addedAt   = now,
            lastSeen  = 0,
            accountID = "peer-acct-default",
        }
        s.peers[key] = existing
    end

    if type(meta) == "table" then
        if meta.guid then existing.guid = meta.guid end
        if meta.class then existing.class = meta.class end
        if meta.level then existing.level = meta.level end
        if meta.accountID and meta.accountID ~= "" then
            existing.accountID = meta.accountID
        end
        if meta.accountLabel and meta.accountLabel ~= "" then
            existing.accountLabel = meta.accountLabel
        end
        if meta.lastSeen ~= nil then existing.lastSeen = meta.lastSeen end
        if meta.lastSync ~= nil then existing.lastSync = meta.lastSync end
    end

    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_SYNC_PEERS_UPDATED")
    end
    return existing, key
end

function sync.RemovePeer(keyOrName)
    local s = sync.GetSettings()
    if s.peers[keyOrName] then
        s.peers[keyOrName] = nil
    else
        local _, foundKey = sync.FindPeer(keyOrName)
        if foundKey then
            s.peers[foundKey] = nil
        end
    end
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_SYNC_PEERS_UPDATED")
    end
end

function sync.ImportPeerRoster(roster, peerAccountLabel, peerAccountID, activeSender)
    if type(roster) ~= "table" then return 0 end
    local added = 0
    local now = (GetServerTime and GetServerTime()) or time()
    local _, activeShort = normalize_peer_key(activeSender or "")
    local activeLower = activeShort and string_lower(activeShort) or nil
    local acctID = (peerAccountID and peerAccountID ~= "") and peerAccountID
        or ((peerAccountLabel and peerAccountLabel ~= "") and ("label:" .. string_lower(peerAccountLabel)))
        or (activeLower and ("acct:" .. activeLower))
        or "peer-acct-default"

    for _, entry in ipairs(roster) do
        if type(entry) == "table" and entry.name and entry.name ~= "" then
            local fullName = entry.realm and entry.realm ~= "" and (entry.name .. "-" .. entry.realm:gsub("%s+", "")) or entry.name
            if not is_self_character(fullName) then
                local existing = sync.FindPeer(fullName)
                local isSender = activeLower and (string_lower(entry.name) == activeLower)
                sync.AddOrUpdatePeer(fullName, {
                    guid         = entry.guid,
                    realm        = entry.realm,
                    class        = entry.class,
                    level        = entry.level,
                    accountID    = (entry.accountID and entry.accountID ~= "") and entry.accountID or acctID,
                    accountLabel = (entry.accountLabel and entry.accountLabel ~= "") and entry.accountLabel or peerAccountLabel,
                    -- Only stamp lastSeen = now on the active online sender; keep offline roster alts at 0!
                    lastSeen     = isSender and now or (existing and existing.lastSeen or 0),
                })
                if not existing then
                    added = added + 1
                end
            end
        end
    end
    return added
end

-- ── Transport Helpers ─────────────────────────────────────────────────────────
local function send_to_peer(peerName, msgType, dataTable, replyChannel, bnetIDAccount)
    local s = sync.GetSettings()
    if not s.enabled then return false end

    if replyChannel == "BNET" and bnetIDAccount then
        return codec.SendMessage(PREFIX, msgType, dataTable, "BNET", nil, bnetIDAccount)
    end
    if (replyChannel == "PARTY" or replyChannel == "RAID") and s.useParty and IsInGroup and IsInGroup() then
        local ch = (IsInRaid and IsInRaid()) and "RAID" or "PARTY"
        return codec.SendMessage(PREFIX, msgType, dataTable, ch)
    end
    if replyChannel == "GUILD" and s.useGuild and IsInGuild and IsInGuild() then
        return codec.SendMessage(PREFIX, msgType, dataTable, "GUILD")
    end
    if peerName and peerName ~= "" and s.useWhisper then
        local peer = sync.FindPeer(peerName)
        local target = get_whisper_target(peerName, peer)
        local _, shortName = normalize_peer_key(target)
        if shortName and offlinePeers[string_lower(shortName)] then
            return false
        end
        return codec.SendMessage(PREFIX, msgType, dataTable, "WHISPER", target)
    end
    return false
end

function sync.Broadcast(msgType, dataTable, includeWhisperPeers, forceProbe)
    local s = sync.GetSettings()
    if not s.enabled then return end

    local sentGroup = false
    if s.useParty and IsInGroup and IsInGroup() then
        local ch = (IsInRaid and IsInRaid()) and "RAID" or "PARTY"
        codec.SendMessage(PREFIX, msgType, dataTable, ch)
        sentGroup = true
    end

    local sentGuild = false
    if s.useGuild and IsInGuild and IsInGuild() then
        codec.SendMessage(PREFIX, msgType, dataTable, "GUILD")
        sentGuild = true
    end

    local bnetSentNames = {}
    if s.useBNet and C_BattleNet and C_BattleNet.GetFriendGameAccountInfo and BNGetNumFriends then
        local _, numOnline = BNGetNumFriends()
        for i = 1, (numOnline or 0) do
            local numGameAccounts = (C_BattleNet.GetFriendNumGameAccounts and C_BattleNet.GetFriendNumGameAccounts(i)) or 0
            for j = 1, numGameAccounts do
                local gameInfo = C_BattleNet.GetFriendGameAccountInfo(i, j)
                if gameInfo and gameInfo.isOnline and gameInfo.clientProgram == "WoW" and gameInfo.gameAccountID then
                    local charName = gameInfo.characterName
                    if charName and not is_self_character(charName) and sync.FindPeer(charName) then
                        codec.SendMessage(PREFIX, msgType, dataTable, "BNET", nil, gameInfo.gameAccountID)
                        bnetSentNames[string_lower(charName)] = true
                    end
                end
            end
        end
    end

    if includeWhisperPeers and s.useWhisper and not sentGuild then
        local partyNames = {}
        if sentGroup and GetNumGroupMembers then
            local n = GetNumGroupMembers()
            local prefixUnit = (IsInRaid and IsInRaid()) and "raid" or "party"
            for i = 1, n do
                local u = prefixUnit .. i
                if UnitExists and UnitExists(u) then
                    local uName = UnitName(u)
                    if uName then partyNames[string_lower(uName)] = true end
                end
            end
        end

        local liveOnline = build_live_online_map()

        -- Group all linked characters by their peer account so we never whisper multiple alts on the same account
        local accounts = {}
        for _, peer in pairs(s.peers) do
            if type(peer) == "table" and peer.trusted and peer.name and not is_self_character(peer.name) then
                local acctKey = (peer.accountID and peer.accountID ~= "" and peer.accountID)
                    or (peer.accountLabel and peer.accountLabel ~= "" and ("label:" .. string_lower(peer.accountLabel)))
                    or "peer-acct-default"
                local group = accounts[acctKey]
                if not group then
                    group = {
                        alreadyReached = false,
                        onlinePeer     = nil,
                        bestFallback   = nil,
                    }
                    accounts[acctKey] = group
                end

                local lowerName = string_lower(peer.name)
                if partyNames[lowerName] or bnetSentNames[lowerName] then
                    group.alreadyReached = true
                elseif liveOnline[lowerName] then
                    if not group.onlinePeer or ((tonumber(peer.lastSeen) or 0) > (tonumber(group.onlinePeer.lastSeen) or 0)) then
                        group.onlinePeer = peer
                    end
                elseif forceProbe and not offlinePeers[lowerName] and (tonumber(peer.lastSeen) or 0) > 0 then
                    if not group.bestFallback or ((tonumber(peer.lastSeen) or 0) > (tonumber(group.bestFallback.lastSeen) or 0)) then
                        group.bestFallback = peer
                    end
                end
            end
        end

        for _, group in pairs(accounts) do
            if not group.alreadyReached then
                local chosen = group.onlinePeer or (forceProbe and group.bestFallback) or nil
                if chosen then
                    local target = get_whisper_target(chosen.name, chosen)
                    codec.SendMessage(PREFIX, msgType, dataTable, "WHISPER", target)
                end
            end
        end
    end
end

-- ── Full & Targeted Content Sync Triggers ─────────────────────────────────────
function sync.SendHelloToPeer(peerName, channel, bnetIDAccount)
    local s = sync.GetSettings()
    if not s.enabled then return end
    if sfui.alts and sfui.alts.PerformSync then
        sfui.alts.PerformSync(false)
    end
    local _, shortName = normalize_peer_key(peerName)
    if shortName then
        offlinePeers[string_lower(shortName)] = nil
    end
    local manifest = merge.BuildManifest(s)
    send_to_peer(peerName, "HELLO", manifest, channel or "WHISPER", bnetIDAccount)
end

function sync.SyncAllNow()
    local s = sync.GetSettings()
    if not s.enabled then
        sfui.common.print("sync: multi-account sync is currently disabled.")
        return
    end
    if sfui.alts and sfui.alts.PerformSync then
        sfui.alts.PerformSync(false)
    end
    local manifest = merge.BuildManifest(s)
    sync.Broadcast("HELLO", manifest, true, true)
    sfui.common.print("sync: broadcasting content manifest to linked accounts...")
end

function sync.PairWithCharacter(targetName)
    if not targetName or targetName == "" then
        sfui.common.print("sync: specify a character name to pair with.")
        return false
    end
    if is_self_character(targetName) then
        sfui.common.print("sync: cannot pair with your own character.")
        return false
    end

    local s = sync.GetSettings()
    if sfui.alts and sfui.alts.PerformSync then
        sfui.alts.PerformSync(false)
    end
    local _, shortName = normalize_peer_key(targetName)
    if shortName then
        offlinePeers[string_lower(shortName)] = nil
    end
    local peer = sync.AddOrUpdatePeer(targetName, { lastSeen = (GetServerTime and GetServerTime()) or time() })
    local manifest = merge.BuildManifest(s)
    local whisperTarget = get_whisper_target(targetName, peer)
    codec.SendMessage(PREFIX, "PAIR_REQ", {
        passcode     = s.passcode or "",
        accountID    = s.accountID or "",
        accountLabel = s.accountLabel or "",
        roster       = manifest.roster,
        manifest     = manifest,
    }, "WHISPER", whisperTarget)
    sfui.common.print("sync: sent pairing & roster link request to |cff00ffff" .. whisperTarget:lower() .. "|r.")
    return true
end

function sync.PairWithTarget()
    if not (UnitExists and UnitExists("target") and UnitIsPlayer and UnitIsPlayer("target")) then
        sfui.common.print("sync: target a player character on your other account first.")
        return false
    end
    local name, realm = UnitName("target")
    if not name or name == "" then return false end
    local full = (realm and realm ~= "" and not sfui.isCamelot) and (name .. "-" .. realm:gsub("%s+", "")) or name
    return sync.PairWithCharacter(full)
end

function sync.PairWithParty()
    if not (IsInGroup and IsInGroup()) then
        sfui.common.print("sync: you are not in a party or raid.")
        return false
    end
    local s = sync.GetSettings()
    if sfui.alts and sfui.alts.PerformSync then
        sfui.alts.PerformSync(false)
    end

    local count = 0
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    local prefixUnit = (IsInRaid and IsInRaid()) and "raid" or "party"
    for i = 1, n do
        local u = prefixUnit .. i
        if UnitExists and UnitExists(u) and UnitIsPlayer and UnitIsPlayer(u) then
            local name, realm = UnitName(u)
            if name and name ~= "" then
                local full = (realm and realm ~= "" and not sfui.isCamelot) and (name .. "-" .. realm:gsub("%s+", "")) or name
                if not is_self_character(full) then
                    sync.MarkPeerOnline(full)
                    sync.AddOrUpdatePeer(full, { lastSeen = (GetServerTime and GetServerTime()) or time() })
                    count = count + 1
                end
            end
        end
    end

    local manifest = merge.BuildManifest(s)
    local ch = (IsInRaid and IsInRaid()) and "RAID" or "PARTY"
    codec.SendMessage(PREFIX, "PAIR_REQ", {
        passcode     = s.passcode or "",
        accountID    = s.accountID or "",
        accountLabel = s.accountLabel or "",
        roster       = manifest.roster,
        manifest     = manifest,
    }, ch)
    sfui.common.print(string_format("sync: linked %d party member(s) and broadcasted account roster.", count))
    return true
end

-- ── Manifest Reconciliation & Data Exchange ───────────────────────────────────
local function handle_manifest_from_peer(sender, peer, remoteManifest, replyChannel, bnetIDAccount)
    if type(remoteManifest) ~= "table" then return end
    local s = sync.GetSettings()
    local now = (GetServerTime and GetServerTime()) or time()

    if peer then
        if remoteManifest.accountID and remoteManifest.accountID ~= "" then
            peer.accountID = remoteManifest.accountID
        end
        if remoteManifest.accountLabel and remoteManifest.accountLabel ~= "" then
            peer.accountLabel = remoteManifest.accountLabel
        end
    end
    if remoteManifest.roster then
        sync.ImportPeerRoster(remoteManifest.roster, remoteManifest.accountLabel, remoteManifest.accountID, sender)
    end

    local want = {
        alts       = {},
        quests     = {},
        recipes    = {},
        fishing    = {},
        djWishlist = false,
        contacts   = false,
        mail       = false,
    }
    local hasWant = false

    -- 1. Reconcile Alts
    if s.syncAlts and type(remoteManifest.alts) == "table" then
        SfuiDB.alts = SfuiDB.alts or {}
        for guid, remTime in pairs(remoteManifest.alts) do
            local locAlt = SfuiDB.alts[guid]
            local locTime = locAlt and (tonumber(locAlt.lastUpdate) or 0) or 0
            local rTime = tonumber(remTime) or 0
            if not locAlt or rTime > locTime then
                table_insert(want.alts, guid)
                hasWant = true
            elseif locTime > rTime then
                local payload = merge.BuildAltPayload(guid)
                if payload then
                    send_to_peer(sender, "DATA_ALT", payload, replyChannel, bnetIDAccount)
                end
            end
        end
        for guid, locAlt in pairs(SfuiDB.alts) do
            if type(locAlt) == "table" and remoteManifest.alts[guid] == nil then
                local payload = merge.BuildAltPayload(guid)
                if payload then
                    send_to_peer(sender, "DATA_ALT", payload, replyChannel, bnetIDAccount)
                end
            end
        end
    end

    -- 1b. Reconcile Quests & Dungeon Journal Quests / Wishlists
    if s.syncQuests then
        SfuiDB.alts = SfuiDB.alts or {}
        if type(remoteManifest.quests) == "table" then
            for guid, remRev in pairs(remoteManifest.quests) do
                local locAlt = SfuiDB.alts[guid]
                local locRev = locAlt and (tonumber(locAlt.questsRev) or 0) or 0
                local rRev = tonumber(remRev) or 0
                if not locAlt or rRev > locRev then
                    table_insert(want.quests, guid)
                    hasWant = true
                elseif locRev > rRev then
                    local payload = merge.BuildQuestsPayload(guid)
                    if payload then
                        send_to_peer(sender, "DATA_QUESTS", payload, replyChannel, bnetIDAccount)
                    end
                end
            end
            for guid, locAlt in pairs(SfuiDB.alts) do
                if type(locAlt) == "table" and remoteManifest.quests[guid] == nil
                    and ((locAlt.activeQuests and next(locAlt.activeQuests)) or (locAlt.djQuests and next(locAlt.djQuests))) then
                    local payload = merge.BuildQuestsPayload(guid)
                    if payload then
                        send_to_peer(sender, "DATA_QUESTS", payload, replyChannel, bnetIDAccount)
                    end
                end
            end
        end

        if type(remoteManifest.djWishlist) == "table" then
            local locRevs = (SfuiDB.dungeonjournal and SfuiDB.dungeonjournal.charWishlistRev) or {}
            local locWishes = (SfuiDB.dungeonjournal and SfuiDB.dungeonjournal.charWishlist) or {}
            local needLocalPush = false
            for guid, remRev in pairs(remoteManifest.djWishlist) do
                local lRev = tonumber(locRevs[guid]) or 0
                local rRev = tonumber(remRev) or 0
                if rRev > lRev then
                    want.djWishlist = true
                    hasWant = true
                elseif lRev > rRev then
                    needLocalPush = true
                end
            end
            for guid, items in pairs(locWishes) do
                if type(items) == "table" and next(items) ~= nil and remoteManifest.djWishlist[guid] == nil then
                    needLocalPush = true
                end
            end
            if needLocalPush then
                local wPayload = merge.BuildDJWishlistPayload()
                if wPayload then
                    send_to_peer(sender, "DATA_DJ_WISHLIST", wPayload, replyChannel, bnetIDAccount)
                end
            end
        end
    end

    -- 2. Reconcile Recipes
    if s.syncRecipes and type(remoteManifest.recipes) == "table" then
        for guid, rInfo in pairs(remoteManifest.recipes) do
            if type(rInfo) == "table" and rInfo.r then
                local locKnown = merge.GetCharKnownRecipes(rInfo.r, guid)
                local remCount = tonumber(rInfo.n) or 0
                if remCount > #locKnown then
                    table_insert(want.recipes, { g = guid, r = rInfo.r })
                    hasWant = true
                elseif #locKnown > remCount then
                    local payload = merge.BuildCharRecipesPayload(rInfo.r, guid)
                    if payload then
                        send_to_peer(sender, "DATA_RECIPES", payload, replyChannel, bnetIDAccount)
                    end
                end
            end
        end
        if SfuiDB.alts then
            for guid, locAlt in pairs(SfuiDB.alts) do
                if type(locAlt) == "table" and remoteManifest.recipes[guid] == nil then
                    local realm = locAlt.realm or get_current_realm()
                    local locKnown = merge.GetCharKnownRecipes(realm, guid)
                    if #locKnown > 0 then
                        send_to_peer(sender, "DATA_RECIPES", {
                            realm = realm,
                            guid  = guid,
                            items = locKnown,
                        }, replyChannel, bnetIDAccount)
                    end
                end
            end
        end
    end

    -- 3. Reconcile Fishing
    if s.syncFishing and type(remoteManifest.fishing) == "table" then
        if sfui.fishing and sfui.fishing.EnsureCharLedger then
            sfui.fishing.EnsureCharLedger()
        end
        local locChars = (SfuiDB.fishing and SfuiDB.fishing.chars) or {}
        for guid, remRev in pairs(remoteManifest.fishing) do
            local locEntry = locChars[guid]
            local locRev = locEntry and (tonumber(locEntry.rev) or 0) or 0
            local rRev = tonumber(remRev) or 0
            if not locEntry or rRev > locRev then
                table_insert(want.fishing, guid)
                hasWant = true
            elseif locRev > rRev then
                local payload = merge.BuildFishingCharPayload(guid)
                if payload then
                    send_to_peer(sender, "DATA_FISHING", payload, replyChannel, bnetIDAccount)
                end
            end
        end
        for guid in pairs(locChars) do
            if remoteManifest.fishing[guid] == nil then
                local payload = merge.BuildFishingCharPayload(guid)
                if payload then
                    send_to_peer(sender, "DATA_FISHING", payload, replyChannel, bnetIDAccount)
                end
            end
        end
    end

    -- 4. Reconcile Contacts & Recipe Finds
    if s.syncContacts and type(remoteManifest.contacts) == "table" then
        local locManifest = merge.BuildManifest(s)
        local lc = locManifest.contacts or {}
        local rc = remoteManifest.contacts
        if (tonumber(rc.v) or 0) > (lc.v or 0)
            or (tonumber(rc.t) or 0) > (lc.t or 0)
            or (tonumber(rc.d) or 0) > (lc.d or 0)
            or (tonumber(rc.q) or 0) > (lc.q or 0) then
            want.contacts = true
            hasWant = true
        end
        if (lc.v or 0) > (tonumber(rc.v) or 0)
            or (lc.t or 0) > (tonumber(rc.t) or 0)
            or (lc.d or 0) > (tonumber(rc.d or 0))
            or (lc.q or 0) > (tonumber(rc.q or 0)) then
            local payload = merge.BuildContactsPayload()
            if payload then
                send_to_peer(sender, "DATA_CONTACTS", payload, replyChannel, bnetIDAccount)
            end
        end
    end

    -- 5. Push Mail Routes if enabled
    if s.syncMail then
        local mailPayload = merge.BuildMailPayload()
        if mailPayload and (next(mailPayload.routes or {}) ~= nil or next(mailPayload.ignoredItems or {}) ~= nil) then
            send_to_peer(sender, "DATA_MAIL", mailPayload, replyChannel, bnetIDAccount)
        end
    end

    if hasWant then
        send_to_peer(sender, "WANT", want, replyChannel, bnetIDAccount)
    end

    if peer then
        peer.lastSeen = now
        peer.lastSync = now
    end
    sync.stats.lastSyncTime = now
    sync.stats.lastPeer = sender
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_SYNC_STATUS_UPDATED")
    end
end

local function handle_want_from_peer(sender, want, replyChannel, bnetIDAccount)
    if type(want) ~= "table" then return end
    local s = sync.GetSettings()

    if s.syncAlts and type(want.alts) == "table" then
        for _, guid in ipairs(want.alts) do
            local payload = merge.BuildAltPayload(guid)
            if payload then
                send_to_peer(sender, "DATA_ALT", payload, replyChannel, bnetIDAccount)
            end
        end
    end

    if s.syncQuests and type(want.quests) == "table" then
        for _, guid in ipairs(want.quests) do
            local payload = merge.BuildQuestsPayload(guid)
            if payload then
                send_to_peer(sender, "DATA_QUESTS", payload, replyChannel, bnetIDAccount)
            end
        end
    end

    if s.syncQuests and want.djWishlist then
        local wPayload = merge.BuildDJWishlistPayload()
        if wPayload then
            send_to_peer(sender, "DATA_DJ_WISHLIST", wPayload, replyChannel, bnetIDAccount)
        end
    end

    if s.syncRecipes and type(want.recipes) == "table" then
        for _, req in ipairs(want.recipes) do
            if type(req) == "table" and req.r and req.g then
                local payload = merge.BuildCharRecipesPayload(req.r, req.g)
                if payload then
                    send_to_peer(sender, "DATA_RECIPES", payload, replyChannel, bnetIDAccount)
                end
            end
        end
    end

    if s.syncFishing and type(want.fishing) == "table" then
        for _, guid in ipairs(want.fishing) do
            local payload = merge.BuildFishingCharPayload(guid)
            if payload then
                send_to_peer(sender, "DATA_FISHING", payload, replyChannel, bnetIDAccount)
            end
        end
    end

    if s.syncContacts and want.contacts then
        local payload = merge.BuildContactsPayload()
        if payload then
            send_to_peer(sender, "DATA_CONTACTS", payload, replyChannel, bnetIDAccount)
        end
    end

    if s.syncMail and want.mail then
        local payload = merge.BuildMailPayload()
        if payload then
            send_to_peer(sender, "DATA_MAIL", payload, replyChannel, bnetIDAccount)
        end
    end
end

-- ── Incoming Message Dispatcher ───────────────────────────────────────────────
local function on_decoded_message(sender, msgType, data, channel, bnetIDAccount)
    if not sender or is_self_character(sender) then return end
    local s = sync.GetSettings()
    if not s.enabled then return end

    local now = (GetServerTime and GetServerTime()) or time()
    local peer = sync.FindPeer(sender)

    -- Handle pairing handshake (PAIR_REQ / PAIR_ACK)
    if msgType == "PAIR_REQ" and type(data) == "table" then
        local myPass = s.passcode or ""
        local inPass = data.passcode or ""
        local isTrustedOrMatchingPass = (peer and peer.trusted)
            or (myPass ~= "" and inPass == myPass)
            or (myPass == "" and (channel == "PARTY" or channel == "RAID" or channel == "BNET"))

        if isTrustedOrMatchingPass then
            sync.MarkPeerOnline(sender, data.accountID)
            peer = sync.AddOrUpdatePeer(sender, {
                accountID    = data.accountID,
                accountLabel = data.accountLabel,
                lastSeen     = now,
                lastSync     = now,
            })
            local imported = sync.ImportPeerRoster(data.roster, data.accountLabel, data.accountID, sender)
            local myManifest = merge.BuildManifest(s)
            send_to_peer(sender, "PAIR_ACK", {
                accountID    = s.accountID or "",
                accountLabel = s.accountLabel or "",
                roster       = myManifest.roster,
                manifest     = myManifest,
            }, channel, bnetIDAccount)
            if data.manifest then
                handle_manifest_from_peer(sender, peer, data.manifest, channel, bnetIDAccount)
            end
            sfui.common.print(string_format("sync: linked with |cff00ffff%s|r (%d character(s) registered).",
                sender:lower(), imported + 1))
        end
        return
    elseif msgType == "PAIR_ACK" and type(data) == "table" then
        sync.MarkPeerOnline(sender, data.accountID)
        peer = sync.AddOrUpdatePeer(sender, {
            accountID    = data.accountID,
            accountLabel = data.accountLabel,
            lastSeen     = now,
            lastSync     = now,
        })
        local imported = sync.ImportPeerRoster(data.roster, data.accountLabel, data.accountID, sender)
        if data.manifest then
            handle_manifest_from_peer(sender, peer, data.manifest, channel, bnetIDAccount)
        end
        sfui.common.print(string_format("sync: pairing confirmed by |cff00ffff%s|r (%d character(s) linked).",
            sender:lower(), imported + 1))
        return
    end

    if not peer or not peer.trusted then
        return
    end

    sync.MarkPeerOnline(sender, peer.accountID)
    peer.lastSeen = now
    sync.stats.lastSyncTime = now
    sync.stats.lastPeer = sender

    if msgType == "HELLO" then
        handle_manifest_from_peer(sender, peer, data, channel, bnetIDAccount)
    elseif msgType == "WANT" then
        handle_want_from_peer(sender, data, channel, bnetIDAccount)
    elseif msgType == "DATA_ALT" and s.syncAlts and type(data) == "table" then
        if merge.MergeAlt(data.guid, data.data, peer.accountLabel, peer.accountID) then
            peer.lastSync = now
            if data.data and data.data.name then
                sync.ImportPeerRoster({
                    {
                        guid         = data.guid,
                        name         = data.data.name,
                        realm        = data.data.realm,
                        class        = data.data.class,
                        level        = data.data.level,
                        accountID    = data.data.accountID or peer.accountID,
                        accountLabel = data.data.accountLabel or peer.accountLabel,
                    }
                }, peer.accountLabel, peer.accountID, sender)
            end
        end
    elseif msgType == "DATA_QUESTS" and s.syncQuests and type(data) == "table" then
        if merge.MergeQuests(data.guid, data) then
            peer.lastSync = now
        end
    elseif msgType == "DATA_DJ_WISHLIST" and s.syncQuests and type(data) == "table" then
        if merge.MergeDJWishlist(data) then
            peer.lastSync = now
        end
    elseif msgType == "DELTA_WAYPOINT" and s.syncWaypoints and type(data) == "table" then
        local mapID = tonumber(data.m)
        local x = tonumber(data.x)
        local y = tonumber(data.y)
        local title = data.t
        if mapID and x and y then
            peer.lastSync = now
            if sfui.map and sfui.map.SetUserWaypoint then
                sfui.map.SetUserWaypoint(mapID, x, y, nil, true)
            end
            if _G.TomTom and _G.TomTom.AddWaypoint then
                pcall(_G.TomTom.AddWaypoint, _G.TomTom, mapID, x, y, {
                    title      = title or "synced waypoint",
                    persistent = false,
                    minimap    = true,
                    world      = true,
                })
            end
        end
    elseif msgType == "DATA_RECIPES" and s.syncRecipes and type(data) == "table" then
        if merge.MergeCharRecipes(data.realm, data.guid, data.items) > 0 then
            peer.lastSync = now
        end
    elseif msgType == "DELTA_RECIPE" and s.syncRecipes and type(data) == "table" then
        if merge.MergeSingleRecipe(data.id, data.r, data.g, data.k) then
            peer.lastSync = now
        end
    elseif msgType == "DATA_CONTACTS" and s.syncContacts and type(data) == "table" then
        if merge.MergeContacts(data) > 0 then
            peer.lastSync = now
        end
    elseif msgType == "DATA_FISHING" and s.syncFishing and type(data) == "table" then
        if merge.MergeFishingChar(data.guid, data.data) then
            peer.lastSync = now
        end
    elseif msgType == "DATA_MAIL" and s.syncMail and type(data) == "table" then
        if merge.MergeMail(data) then
            peer.lastSync = now
        end
    end

    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_SYNC_STATUS_UPDATED")
    end
end

-- ── Offline Whisper Error Filter (`ERR_CHAT_PLAYER_NOT_FOUND_S`) ──────────────
local errPlayerNotFoundPattern = nil
local function get_not_found_pattern()
    if errPlayerNotFoundPattern then return errPlayerNotFoundPattern end
    local fmt = _G.ERR_CHAT_PLAYER_NOT_FOUND_S or 'No player named "%s" is currently playing.'
    local escaped = fmt:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    errPlayerNotFoundPattern = "^" .. escaped:gsub("%%%%s", "(.+)") .. "$"
    return errPlayerNotFoundPattern
end

if ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
        if type(msg) ~= "string" then return false end
        local pat = get_not_found_pattern()
        local failedName = string_match(msg, pat)
        if failedName and codec and codec.WasRecentlyWhispered and codec.WasRecentlyWhispered(failedName) then
            sync.MarkPeerOffline(failedName)
            return true
        end
        return false
    end)
end

-- ── Event Handlers & Debounced Live Broadcasts ────────────────────────────────
local function on_chat_msg_addon(event, prefix, text, channel, sender)
    if prefix ~= PREFIX then return end
    if sender and not is_self_character(sender) then
        sync.MarkPeerOnline(sender)
    end
    local msgType, data = codec.FeedChunk(sender, text)
    if msgType then
        on_decoded_message(sender, msgType, data, channel, nil)
    end
end

local function on_bn_chat_msg_addon(event, prefix, text, channel, senderBnetID)
    if prefix ~= PREFIX then return end
    local senderName = "bnet:" .. tostring(senderBnetID)
    if C_BattleNet and C_BattleNet.GetGameAccountInfoByID then
        local info = C_BattleNet.GetGameAccountInfoByID(senderBnetID)
        if info and info.characterName then
            senderName = info.characterName
            sync.MarkPeerOnline(senderName)
        end
    end
    local msgType, data = codec.FeedChunk(senderName, text)
    if msgType then
        on_decoded_message(senderName, msgType, data, "BNET", senderBnetID)
    end
end

local InCombatLockdown = _G.InCombatLockdown
local deferredAfterCombat = {
    alt        = false,
    recipes    = false,
    contacts   = false,
    fishing    = false,
    quests     = false,
    djWishlist = false,
}

local altBroadcastPending = false
local function on_local_alt_synced(event, guid, isLogout)
    if isLogout then return end
    local s = sync.GetSettings()
    if not s.enabled or not s.syncAlts then return end
    if InCombatLockdown and InCombatLockdown() then
        deferredAfterCombat.alt = true
        return
    end
    if altBroadcastPending then return end
    altBroadcastPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(30.0, function()
            altBroadcastPending = false
            if InCombatLockdown and InCombatLockdown() then
                deferredAfterCombat.alt = true
                return
            end
            local myGUID = guid or (UnitGUID and UnitGUID("player"))
            local payload = merge.BuildAltPayload(myGUID)
            if payload then
                sync.Broadcast("DATA_ALT", payload, true, false)
            end
        end)
    else
        altBroadcastPending = false
    end
end

local function on_local_recipe_updated(event, itemID, realm, guid, isKnown)
    local s = sync.GetSettings()
    if not s.enabled or not s.syncRecipes then return end
    if InCombatLockdown and InCombatLockdown() then
        deferredAfterCombat.recipes = true
        return
    end
    sync.Broadcast("DELTA_RECIPE", {
        id = itemID,
        r  = realm,
        g  = guid,
        k  = isKnown and true or false,
    }, true, false)
end

local recipeBatchBroadcastPending = false
local function on_local_recipe_batch_updated(event, realm, guid)
    local s = sync.GetSettings()
    if not s.enabled or not s.syncRecipes then return end
    if InCombatLockdown and InCombatLockdown() then
        deferredAfterCombat.recipes = true
        return
    end
    if recipeBatchBroadcastPending then return end
    recipeBatchBroadcastPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(5.0, function()
            recipeBatchBroadcastPending = false
            if InCombatLockdown and InCombatLockdown() then
                deferredAfterCombat.recipes = true
                return
            end
            local myGUID = guid or (UnitGUID and UnitGUID("player"))
            local myRealm = realm or (GetRealmName and GetRealmName()) or ""
            local payload = merge.BuildCharRecipesPayload(myRealm, myGUID)
            if payload and payload.items and #payload.items > 0 then
                sync.Broadcast("DATA_RECIPES", payload, true, false)
            end
        end)
    else
        recipeBatchBroadcastPending = false
    end
end

local contactsBroadcastPending = false
local function on_local_contacts_updated()
    local s = sync.GetSettings()
    if not s.enabled or not s.syncContacts then return end
    if InCombatLockdown and InCombatLockdown() then
        deferredAfterCombat.contacts = true
        return
    end
    if contactsBroadcastPending then return end
    contactsBroadcastPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(5.0, function()
            contactsBroadcastPending = false
            if InCombatLockdown and InCombatLockdown() then
                deferredAfterCombat.contacts = true
                return
            end
            local payload = merge.BuildContactsPayload()
            if payload then
                sync.Broadcast("DATA_CONTACTS", payload, true, false)
            end
        end)
    else
        contactsBroadcastPending = false
    end
end

local fishingBroadcastPending = false
local function on_local_fishing_updated()
    local s = sync.GetSettings()
    if not s.enabled or not s.syncFishing then return end
    if InCombatLockdown and InCombatLockdown() then
        deferredAfterCombat.fishing = true
        return
    end
    if fishingBroadcastPending then return end
    fishingBroadcastPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(10.0, function()
            fishingBroadcastPending = false
            if InCombatLockdown and InCombatLockdown() then
                deferredAfterCombat.fishing = true
                return
            end
            local myGUID = UnitGUID and UnitGUID("player")
            local payload = merge.BuildFishingCharPayload(myGUID)
            if payload then
                sync.Broadcast("DATA_FISHING", payload, true, false)
            end
        end)
    else
        fishingBroadcastPending = false
    end
end

local questsBroadcastPending = false
local pendingTurnedInQuests = {}
local function on_local_quests_updated(event, arg1)
    if event == "QUEST_TURNED_IN" and tonumber(arg1) then
        pendingTurnedInQuests[tonumber(arg1)] = true
    end
    local s = sync.GetSettings()
    if not s.enabled or s.syncQuests == false then return end
    if InCombatLockdown and InCombatLockdown() then
        deferredAfterCombat.quests = true
        return
    end
    if questsBroadcastPending then return end
    questsBroadcastPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(2.0, function()
            questsBroadcastPending = false
            if InCombatLockdown and InCombatLockdown() then
                deferredAfterCombat.quests = true
                return
            end
            local myGUID = UnitGUID and UnitGUID("player")
            if not myGUID then return end
            if merge.ScanLocalQuestsAndDJ then
                local scanned = false
                for qid in pairs(pendingTurnedInQuests) do
                    merge.ScanLocalQuestsAndDJ(qid)
                    pendingTurnedInQuests[qid] = nil
                    scanned = true
                end
                if not scanned then
                    merge.ScanLocalQuestsAndDJ()
                end
            end
            local payload = merge.BuildQuestsPayload and merge.BuildQuestsPayload(myGUID)
            if payload then
                sync.Broadcast("DATA_QUESTS", payload, true, false)
            end
        end)
    else
        questsBroadcastPending = false
    end
end

local djWishlistBroadcastPending = false
local function on_local_dj_wishlist_updated()
    local s = sync.GetSettings()
    if not s.enabled or s.syncQuests == false then return end
    if InCombatLockdown and InCombatLockdown() then
        deferredAfterCombat.djWishlist = true
        return
    end
    if djWishlistBroadcastPending then return end
    djWishlistBroadcastPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(2.0, function()
            djWishlistBroadcastPending = false
            if InCombatLockdown and InCombatLockdown() then
                deferredAfterCombat.djWishlist = true
                return
            end
            local payload = merge.BuildDJWishlistPayload and merge.BuildDJWishlistPayload()
            if payload then
                sync.Broadcast("DATA_DJ_WISHLIST", payload, true, false)
            end
        end)
    else
        djWishlistBroadcastPending = false
    end
end

local function on_local_waypoint_set(_, mapID, x, y, label)
    local s = sync.GetSettings()
    if not s.enabled or s.syncWaypoints == false then return end
    if not mapID or not x or not y then return end
    sync.Broadcast("DELTA_WAYPOINT", {
        m = tonumber(mapID),
        x = tonumber(x),
        y = tonumber(y),
        t = label and tostring(label) or nil,
    }, true, false)
end

-- ── Cross-Account Quest & Party Helpers ───────────────────────────────────────
local function short_name(s)
    if type(s) ~= "string" then return "" end
    return string_match(s, "^([^%-]+)") or s
end

local function format_colored_char_name(alt, fallbackName)
    local rawName = (alt and alt.name) or fallbackName or "?"
    local cleanName = short_name(rawName):lower()
    local classToken = alt and alt.class
    if classToken and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classToken] then
        local c = _G.RAID_CLASS_COLORS[classToken]
        local hex = c.colorStr or string.format("ff%02x%02x%02x", math.floor((c.r or 1) * 255), math.floor((c.g or 1) * 255), math.floor((c.b or 1) * 255))
        return "|c" .. hex .. cleanName .. "|r", cleanName
    end
    return cleanName, cleanName
end

local function build_party_guid_and_name_maps()
    local guidMap = {}
    local nameMap = {}
    if not (IsInGroup and IsInGroup()) then
        return guidMap, nameMap
    end
    local UnitExists = _G.UnitExists
    local UnitIsUnit = _G.UnitIsUnit
    local UnitGUID   = _G.UnitGUID
    local UnitName   = _G.UnitName
    local isRaid = IsInRaid and IsInRaid()
    local count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    local prefix = isRaid and "raid" or "party"
    local maxIdx = isRaid and count or math.min(4, count)
    for i = 1, maxIdx do
        local u = prefix .. i
        if UnitExists and UnitExists(u) and not (UnitIsUnit and UnitIsUnit(u, "player")) then
            local g = UnitGUID and UnitGUID(u)
            local n = UnitName and UnitName(u)
            if g then guidMap[g] = true end
            if n and n ~= "" then nameMap[short_name(n):lower()] = true end
        end
    end
    return guidMap, nameMap
end

-- Returns an array of class-colored lowercase character names for synced party
-- members who do NOT have `questID` in their active quest log and have not completed it.
function sync.GetPartyMissingQuestPeers(questID)
    questID = tonumber(questID)
    if not questID then return nil end
    local s = sync.GetSettings()
    if not s.enabled or s.syncQuests == false then return nil end
    if not (IsInGroup and IsInGroup()) then return nil end
    if not SfuiDB or type(SfuiDB.alts) ~= "table" then return nil end

    local partyGUIDs, partyNames = build_party_guid_and_name_maps()
    local myGUID = UnitGUID and UnitGUID("player")
    local missing = nil
    local seenNames = {}

    for guid, alt in pairs(SfuiDB.alts) do
        if guid ~= myGUID and type(alt) == "table" and type(alt.activeQuests) == "table" then
            local cleanName = short_name(alt.name or ""):lower()
            if (partyGUIDs[guid] or (cleanName ~= "" and partyNames[cleanName])) and not seenNames[cleanName] then
                seenNames[cleanName] = true
                local hasActive = (alt.activeQuests[questID] ~= nil)
                local hasCompleted = (alt.completedQuests and alt.completedQuests[questID] == true)
                    or (alt.djQuests and alt.djQuests[questID] == 2)
                if not hasActive and not hasCompleted then
                    local colored = format_colored_char_name(alt, cleanName)
                    missing = missing or {}
                    missing[#missing + 1] = colored
                end
            end
        end
    end

    return missing
end

-- Returns an array of status tables for synced peers/alts:
-- { guid, name, coloredName, class, inParty, isOnline, status = "missing"|"active"|"ready"|"completed", objs = { "4/10 ...", ... } }
function sync.GetQuestPeerStatuses(questID, includeAllAlts)
    questID = tonumber(questID)
    if not questID then return nil end
    local s = sync.GetSettings()
    if not s.enabled or s.syncQuests == false then return nil end
    if not SfuiDB or type(SfuiDB.alts) ~= "table" then return nil end

    local partyGUIDs, partyNames = build_party_guid_and_name_maps()
    local liveMap = build_live_online_map()
    local myGUID = UnitGUID and UnitGUID("player")
    local results = nil
    local seenNames = {}

    for guid, alt in pairs(SfuiDB.alts) do
        if guid ~= myGUID and type(alt) == "table" and (type(alt.activeQuests) == "table" or type(alt.djQuests) == "table") then
            local cleanName = short_name(alt.name or ""):lower()
            if cleanName ~= "" and not seenNames[cleanName] then
                local inParty = (partyGUIDs[guid] == true) or (partyNames[cleanName] == true)
                local isOnline = inParty or (liveMap[cleanName] ~= nil)
                if includeAllAlts or inParty or isOnline then
                    seenNames[cleanName] = true
                    local status = "missing"
                    local objs = nil
                    if (alt.completedQuests and alt.completedQuests[questID] == true)
                        or (alt.djQuests and alt.djQuests[questID] == 2) then
                        status = "completed"
                    elseif alt.activeQuests and alt.activeQuests[questID] then
                        local qEntry = alt.activeQuests[questID]
                        objs = qEntry.o
                        if qEntry.c == 1 then
                            status = "ready"
                        else
                            status = "active"
                        end
                    elseif alt.djQuests and alt.djQuests[questID] == 1 then
                        status = "active"
                    end

                    local colored = format_colored_char_name(alt, cleanName)
                    results = results or {}
                    results[#results + 1] = {
                        guid        = guid,
                        name        = cleanName,
                        coloredName = colored,
                        class       = alt.class,
                        inParty     = inParty,
                        isOnline    = isOnline,
                        status      = status,
                        objs        = objs,
                    }
                end
            end
        end
    end

    if results and #results > 1 then
        table.sort(results, function(a, b)
            if a.inParty ~= b.inParty then return a.inParty end
            if a.isOnline ~= b.isOnline then return a.isOnline end
            return (a.name or "") < (b.name or "")
        end)
    end

    return results
end

local function on_regen_enabled()
    if deferredAfterCombat.alt then
        deferredAfterCombat.alt = false
        on_local_alt_synced()
    end
    if deferredAfterCombat.recipes then
        deferredAfterCombat.recipes = false
        on_local_recipe_batch_updated()
    end
    if deferredAfterCombat.contacts then
        deferredAfterCombat.contacts = false
        on_local_contacts_updated()
    end
    if deferredAfterCombat.fishing then
        deferredAfterCombat.fishing = false
        on_local_fishing_updated()
    end
    if deferredAfterCombat.quests then
        deferredAfterCombat.quests = false
        on_local_quests_updated()
    end
    if deferredAfterCombat.djWishlist then
        deferredAfterCombat.djWishlist = false
        on_local_dj_wishlist_updated()
    end
end

local loginSynced = false
local function on_entering_world()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    elseif _G.RegisterAddonMessagePrefix then
        _G.RegisterAddonMessagePrefix(PREFIX)
    end

    if sfui.fishing and sfui.fishing.EnsureCharLedger then
        sfui.fishing.EnsureCharLedger()
    end

    if not loginSynced then
        loginSynced = true
        if C_Timer and C_Timer.After then
            C_Timer.After(4.5, function()
                local s = sync.GetSettings()
                if s.enabled then
                    if s.syncQuests ~= false and merge.ScanLocalQuestsAndDJ then
                        merge.ScanLocalQuestsAndDJ()
                    end
                    if s.autoSyncOnLogin then
                        local manifest = merge.BuildManifest(s)
                        sync.Broadcast("HELLO", manifest, true, true)
                    end
                end
            end)
        end
    end
end

local groupRosterPending = false
local function on_group_roster_update()
    if groupRosterPending then return end
    local s = sync.GetSettings()
    if not s.enabled or not s.useParty or not (IsInGroup and IsInGroup()) then return end
    groupRosterPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(3.0, function()
            groupRosterPending = false
            if IsInGroup and IsInGroup() then
                if s.syncQuests ~= false and merge.ScanLocalQuestsAndDJ then
                    merge.ScanLocalQuestsAndDJ()
                end
                local manifest = merge.BuildManifest(s)
                local ch = (IsInRaid and IsInRaid()) and "RAID" or "PARTY"
                codec.SendMessage(PREFIX, "HELLO", manifest, ch)
            end
            if sfui.tracker and sfui.tracker.RequestRefresh then
                sfui.tracker.RequestRefresh(0.1)
            end
        end)
    else
        groupRosterPending = false
    end
end

-- ── Summary / Diagnostics Helper for UI ───────────────────────────────────────
function sync.GetContentCounts()
    SfuiDB = SfuiDB or {}
    local altsCount = 0
    local remoteAltsCount = 0
    local s = sync.GetSettings()
    local myLabel = s.accountLabel or ""
    local myAcctID = s.accountID or ""
    if type(SfuiDB.alts) == "table" then
        for _, alt in pairs(SfuiDB.alts) do
            altsCount = altsCount + 1
            if type(alt) == "table" then
                if (alt.accountID and alt.accountID ~= "" and alt.accountID ~= myAcctID)
                    or (alt.accountLabel and alt.accountLabel ~= "" and alt.accountLabel ~= myLabel) then
                    remoteAltsCount = remoteAltsCount + 1
                end
            end
        end
    end

    local recipesCount = 0
    if type(SfuiDB.recipes) == "table" then
        for _ in pairs(SfuiDB.recipes) do
            recipesCount = recipesCount + 1
        end
    end

    local contactsCount = 0
    if SfuiDB.contacts then
        for _ in pairs(SfuiDB.contacts.vendors or {}) do contactsCount = contactsCount + 1 end
        for _ in pairs(SfuiDB.contacts.trainers or {}) do contactsCount = contactsCount + 1 end
    end
    if SfuiDB.recipe_finds then
        for _ in pairs(SfuiDB.recipe_finds.drops or {}) do contactsCount = contactsCount + 1 end
        for _ in pairs(SfuiDB.recipe_finds.quests or {}) do contactsCount = contactsCount + 1 end
    end

    local fishSpeciesCount = 0
    if SfuiDB.fishing and type(SfuiDB.fishing.species) == "table" then
        for _ in pairs(SfuiDB.fishing.species) do
            fishSpeciesCount = fishSpeciesCount + 1
        end
    end

    local peersCount = 0
    if SfuiDB.sync and type(SfuiDB.sync.peers) == "table" then
        for _ in pairs(SfuiDB.sync.peers) do
            peersCount = peersCount + 1
        end
    end

    return {
        alts       = altsCount,
        remoteAlts = remoteAltsCount,
        recipes    = recipesCount,
        contacts   = contactsCount,
        fish       = fishSpeciesCount,
        peers      = peersCount,
    }
end

-- ── Telemetry & Module Lifecycle (`core/module.lua` & `frames/mem.lua`) ──────
function sfui.sync_debug_info()
    local s = sync.GetSettings()
    local counts = sync.GetContentCounts()
    local qLen, tickerActive, reassemblyCount = 0, false, 0
    if codec and codec.GetQueueStats then
        qLen, tickerActive, reassemblyCount = codec.GetQueueStats()
    elseif codec and codec.GetQueueLength then
        qLen = codec.GetQueueLength()
    end

    local onlineCount = 0
    local liveMap = build_live_online_map()
    for _ in pairs(liveMap) do
        onlineCount = onlineCount + 1
    end

    return {
        enabled         = s.enabled == true,
        accountLabel    = s.accountLabel or "",
        peersCount      = counts.peers or 0,
        onlinePeers     = onlineCount,
        altsCount       = counts.alts or 0,
        remoteAltsCount = counts.remoteAlts or 0,
        recipesCount    = counts.recipes or 0,
        contactsCount   = counts.contacts or 0,
        fishCount       = counts.fish or 0,
        queueSize       = qLen,
        tickerActive    = tickerActive,
        reassemblyCount = reassemblyCount,
        packetsSent     = (sync.stats and sync.stats.packetsSent) or 0,
        packetsReceived = (sync.stats and sync.stats.packetsReceived) or 0,
        bytesSent       = (sync.stats and sync.stats.bytesSent) or 0,
        bytesReceived   = (sync.stats and sync.stats.bytesReceived) or 0,
        lastSyncTime    = (sync.stats and sync.stats.lastSyncTime) or 0,
        lastPeer        = (sync.stats and sync.stats.lastPeer) or nil,
    }
end

function sync:OnInit()
    sync.GetSettings()
end

function sync:OnEnable()
    on_entering_world()
end

function sync:OnSettingsChanged(key, value)
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_SYNC_STATUS_UPDATED", key, value)
    end
end

sync.GetDebugInfo = sfui.sync_debug_info

if sfui.RegisterModule then
    sfui.RegisterModule("sync", sync)
end

-- ── Register Events ───────────────────────────────────────────────────────────
if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", on_entering_world)
    sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", on_regen_enabled)
    sfui.events.RegisterEvent("CHAT_MSG_ADDON", on_chat_msg_addon)
    sfui.events.RegisterEvent("BN_CHAT_MSG_ADDON", on_bn_chat_msg_addon)
    sfui.events.RegisterEvent("GROUP_ROSTER_UPDATE", on_group_roster_update)
    sfui.events.RegisterEvent("QUEST_ACCEPTED", on_local_quests_updated)
    sfui.events.RegisterEvent("QUEST_TURNED_IN", on_local_quests_updated)
    sfui.events.RegisterEvent("QUEST_REMOVED", on_local_quests_updated)
    sfui.events.RegisterEvent("QUEST_WATCH_UPDATE", on_local_quests_updated)
    sfui.events.RegisterEvent("QUEST_LOG_UPDATE", on_local_quests_updated)
end

if sfui.events and sfui.events.RegisterMessage then
    sfui.events.RegisterMessage("SFUI_ALT_SYNCED", on_local_alt_synced)
    sfui.events.RegisterMessage("SFUI_RECIPE_KNOWN_UPDATED", on_local_recipe_updated)
    sfui.events.RegisterMessage("SFUI_RECIPE_BATCH_UPDATED", on_local_recipe_batch_updated)
    sfui.events.RegisterMessage("SFUI_CONTACTS_UPDATED", on_local_contacts_updated)
    sfui.events.RegisterMessage("SFUI_FISHING_CATCH_RECORDED", on_local_fishing_updated)
    sfui.events.RegisterMessage("SFUI_FISHING_GETAWAY_RECORDED", on_local_fishing_updated)
    sfui.events.RegisterMessage("SFUI_FISHING_CAST_RECORDED", on_local_fishing_updated)
    sfui.events.RegisterMessage("SFUI_DJ_WISHLIST_UPDATED", on_local_dj_wishlist_updated)
    sfui.events.RegisterMessage("SFUI_WAYPOINT_SET", on_local_waypoint_set)
end
