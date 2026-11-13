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
local wipe = _G.wipe
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
local issecretvalue = (sfui.common and sfui.common.issecretvalue) or _G.issecretvalue or function() return false end

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
    enabled            = true,
    accountLabel       = "",
    passcode           = "",
    accountID          = "",
    syncAlts           = true,
    syncQuests         = true,
    syncWaypoints      = true,
    syncRecipes        = true,
    syncContacts       = true,
    syncFishing        = true,
    syncMail           = true,
    mbAutoFollow       = true,
    mbAutoInvite       = true,
    mbAutoQuest        = true,
    mbAutoTaxi         = true,
    mbAutoTrade        = true,
    mbCorpseAlert      = true,
    mbShowHud          = true,
    mbFollowerPassLoot = false,
    useParty           = true,
    useWhisper         = true,
    useGuild           = false,
    useBNet            = true,
    autoSyncOnLogin    = true,
    peers              = {},
}

if sfui.db and sfui.db.RegisterDefaults then
    sfui.db.RegisterDefaults("sync", DEFAULT_SETTINGS)
end

-- ── Settings & Peer Storage ───────────────────────────────────────────────────
local sanitize_and_merge_peers_table

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

    -- Multibox & levelling helper toggles
    if s.mbAutoFollow == nil then s.mbAutoFollow = true end
    if s.mbAutoInvite == nil then s.mbAutoInvite = true end
    if s.mbAutoQuest == nil then s.mbAutoQuest = true end
    if s.mbAutoTaxi == nil then s.mbAutoTaxi = true end
    if s.mbAutoTrade == nil then s.mbAutoTrade = true end
    if s.mbCorpseAlert == nil then s.mbCorpseAlert = true end
    if s.mbShowHud == nil then s.mbShowHud = true end
    if s.mbFollowerPassLoot == nil then s.mbFollowerPassLoot = false end

    -- Transport channel toggles
    if s.useParty == nil then s.useParty = true end
    if s.useWhisper == nil then s.useWhisper = true end
    if s.useGuild == nil then s.useGuild = false end
    if s.useBNet == nil then s.useBNet = true end
    if s.autoSyncOnLogin == nil then s.autoSyncOnLogin = true end
    if s.settingsRev == nil then s.settingsRev = 0 end

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

    if not sync._peersSanitized and sanitize_and_merge_peers_table then
        sync._peersSanitized = true
        sanitize_and_merge_peers_table(s.peers)
    end

    return s
end

local cachedCurrentRealm = nil
local function get_current_realm()
    if cachedCurrentRealm and cachedCurrentRealm ~= "" then
        return cachedCurrentRealm
    end
    local r = (GetRealmName and GetRealmName()) or ""
    r = r:gsub("%s+", "")
    if r ~= "" then
        cachedCurrentRealm = r
    end
    return r
end

local function is_forever_realm_token(s)
    if type(s) ~= "string" or s == "" then return false end
    if sfui.alts and sfui.alts.IsServerRealmName and sfui.alts.IsServerRealmName(s) then
        return true
    end
    local norm = s:gsub("[%s%-']", ""):lower()
    if norm == "" then return false end
    if norm:find("^camwow") or norm:find("realm") or norm:find("%d") then
        return true
    end
    local cur = string_lower(get_current_realm())
    if cur ~= "" and norm == cur then return true end
    if norm == "forever" or norm == "camelot" or norm == "global" then
        return true
    end
    return false
end

local function resolve_forever_name(rawName, rawSurname, guid)
    if type(rawName) ~= "string" then return nil end
    local trimmed = rawName:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" then return nil end

    if sfui.isRetail then
        return trimmed
    end

    local surname = (type(rawSurname) == "string" and rawSurname ~= "") and rawSurname:gsub("^%s+", ""):gsub("%s+$", "") or nil
    if surname and surname:find("-", 1, true) then
        local sLeft, sRight = string_match(surname, "^([^%-]+)%-(.+)$")
        if sLeft and sLeft ~= "" and (not sRight or is_forever_realm_token(sRight)) then
            surname = sLeft:gsub("^%s+", ""):gsub("%s+$", "")
        end
    end
    if surname and (surname == "" or is_forever_realm_token(surname)) then
        surname = nil
    end

    -- Strip any accidental "-Realm" suffix on Forever
    local base, suffix = string_match(trimmed, "^(.+)%-([^%-]+)$")
    if base and suffix then
        trimmed = base:gsub("^%s+", ""):gsub("%s+$", "")
        local cleanSuffix = suffix:gsub("^%s+", ""):gsub("%s+$", "")
        if not surname and cleanSuffix ~= "" and not is_forever_realm_token(cleanSuffix) then
            surname = cleanSuffix
        end
    end

    -- Check alt record by GUID if available
    if guid and SfuiDB and type(SfuiDB.alts) == "table" and type(SfuiDB.alts[guid]) == "table" then
        local alt = SfuiDB.alts[guid]
        if sfui.alts and sfui.alts.GetDisplayName then
            local disp = sfui.alts.GetDisplayName(alt, guid)
            if disp and disp ~= "" and disp ~= "Unknown" then
                local dClean = disp:match("^([^%-]+)") or disp
                dClean = dClean:gsub("^%s+", ""):gsub("%s+$", "")
                if dClean:find(" ", 1, true) or not trimmed:find(" ", 1, true) then
                    trimmed = dClean
                end
            end
        end
        if not surname and alt.surname and alt.surname ~= "" and not is_forever_realm_token(alt.surname) then
            surname = alt.surname
        end
    end

    if not trimmed:find(" ", 1, true) then
        if surname and surname ~= "" and string_lower(surname) ~= string_lower(trimmed) then
            trimmed = trimmed .. " " .. surname
        elseif guid and _G.UnitNameFromGUID then
            local gFirst, gSecond = _G.UnitNameFromGUID(guid)
            if gSecond and gSecond ~= "" and not is_forever_realm_token(gSecond) and string_lower(gSecond) ~= string_lower(trimmed) then
                trimmed = trimmed .. " " .. gSecond
            elseif gFirst and gFirst:find(" ", 1, true) then
                trimmed = gFirst
            end
        end
    end

    return trimmed
end

local function normalize_peer_key(nameOrFull, defaultRealm)
    if type(nameOrFull) ~= "string" then return nil, nil, nil end
    local trimmed = nameOrFull:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" then return nil, nil, nil end

    local shortName, realm
    if not sfui.isRetail then
        local curRealm = get_current_realm()
        shortName = resolve_forever_name(trimmed, nil, nil)
        if not shortName or shortName == "" then return nil, nil, nil end
        realm = curRealm ~= "" and curRealm or (defaultRealm or "")
        local key = string_lower(shortName)
        return key, shortName, realm
    else
        shortName, realm = string_match(trimmed, "^([^%-]+)%-(.+)$")
        if not shortName then
            shortName = trimmed
            realm = defaultRealm or get_current_realm()
        else
            realm = realm:gsub("%s+", "")
        end
        local key = string_lower(shortName) .. "-" .. string_lower(realm or "")
        return key, shortName, realm
    end
end

local function merge_peer_into(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return end
    if src.name and src.name ~= "" then
        local dstHasSpace = type(dst.name) == "string" and dst.name:find(" ", 1, true) ~= nil
        local srcHasSpace = type(src.name) == "string" and src.name:find(" ", 1, true) ~= nil
        if not dst.name or dst.name == "" or (srcHasSpace and not dstHasSpace) then
            dst.name = src.name
        end
    end
    if src.surname and src.surname ~= "" and (not dst.surname or dst.surname == "") then
        dst.surname = src.surname
    end
    if src.guid and src.guid ~= "" then
        if not dst.guid or dst.guid == "" then
            dst.guid = src.guid
        elseif SfuiDB and type(SfuiDB.alts) == "table" and SfuiDB.alts[src.guid] and not SfuiDB.alts[dst.guid] then
            dst.guid = src.guid
        end
    end
    if src.class and src.class ~= "" and (not dst.class or dst.class == "") then
        dst.class = src.class
    end
    local srcLvl = tonumber(src.level) or 0
    local dstLvl = tonumber(dst.level) or 0
    if srcLvl > dstLvl then
        dst.level = srcLvl
    end
    if src.accountID and src.accountID ~= "" and src.accountID ~= "peer-acct-default" then
        if not dst.accountID or dst.accountID == "" or dst.accountID == "peer-acct-default" then
            dst.accountID = src.accountID
        end
    end
    if src.accountLabel and src.accountLabel ~= "" and (not dst.accountLabel or dst.accountLabel == "") then
        dst.accountLabel = src.accountLabel
    end
    local srcSeen = tonumber(src.lastSeen) or 0
    local dstSeen = tonumber(dst.lastSeen) or 0
    if srcSeen > dstSeen then
        dst.lastSeen = srcSeen
    end
    local srcSync = tonumber(src.lastSync) or 0
    local dstSync = tonumber(dst.lastSync) or 0
    if srcSync > dstSync then
        dst.lastSync = srcSync
    end
    if src.trusted then
        dst.trusted = true
    end
end

local function peers_match_forever(a, b)
    if a.guid and b.guid and a.guid ~= "" and a.guid == b.guid then
        return true
    end
    local na = string_lower(a.name or "")
    local nb = string_lower(b.name or "")
    if na == "" or nb == "" then return false end
    if na == nb then return true end

    local fa = string_match(na, "^(%S+)") or na
    local fb = string_match(nb, "^(%S+)") or nb
    if fa == fb and (na == fa or nb == fb) then
        local la = string_lower(a.accountLabel or "")
        local lb = string_lower(b.accountLabel or "")
        local ida = a.accountID or ""
        local idb = b.accountID or ""
        if (la ~= "" and la == lb)
            or (ida ~= "" and ida ~= "peer-acct-default" and ida == idb)
            or (la == "" or lb == "") then
            return true
        end
    end
    return false
end

sanitize_and_merge_peers_table = function(peersTbl)
    if sfui.isRetail or type(peersTbl) ~= "table" then return end
    local items = {}
    for _, p in pairs(peersTbl) do
        if type(p) == "table" and type(p.name) == "string" and p.name ~= "" then
            p.name = resolve_forever_name(p.name, p.surname, p.guid) or p.name
            if (not p.guid or p.guid == "") and SfuiDB and type(SfuiDB.alts) == "table" then
                local pLower = string_lower(p.name)
                local pFirst = string_match(pLower, "^(%S+)") or pLower
                local matchedGuid, matchedAlt = nil, nil
                local matchCount = 0
                for g, alt in pairs(SfuiDB.alts) do
                    local sameRuleset = not (sfui.alts and sfui.alts.IsSameRuleset) or sfui.alts.IsSameRuleset(alt, g)
                    if type(alt) == "table" and alt.name and sameRuleset then
                        local disp = (sfui.alts and sfui.alts.GetDisplayName and sfui.alts.GetDisplayName(alt, g)) or alt.name
                        local dLower = string_lower(disp)
                        local aFirst = string_lower(string_match(alt.name, "^([^%-]+)") or alt.name)
                        if dLower == pLower then
                            matchedGuid, matchedAlt = g, alt
                            matchCount = 1
                            break
                        elseif aFirst == pFirst then
                            local sameLabel = (p.accountLabel and p.accountLabel ~= "" and alt.accountLabel and string_lower(p.accountLabel) == string_lower(alt.accountLabel))
                            local sameAcct = (p.accountID and p.accountID ~= "" and p.accountID ~= "peer-acct-default" and alt.accountID == p.accountID)
                            if sameLabel or sameAcct then
                                matchedGuid, matchedAlt = g, alt
                                matchCount = matchCount + 1
                            end
                        end
                    end
                end
                if matchCount == 1 and matchedGuid and matchedAlt then
                    p.guid = matchedGuid
                    p.class = p.class or matchedAlt.class
                    p.level = p.level or matchedAlt.level
                    p.name = resolve_forever_name(p.name, matchedAlt.surname, matchedGuid) or p.name
                end
            end
            items[#items + 1] = p
        end
    end

    wipe(peersTbl)
    local merged = {}
    for _, p in ipairs(items) do
        local target = nil
        for _, m in ipairs(merged) do
            if peers_match_forever(m, p) then
                target = m
                break
            end
        end
        if target then
            merge_peer_into(target, p)
        else
            merged[#merged + 1] = p
        end
    end

    local curRealm = get_current_realm()
    for _, m in ipairs(merged) do
        m.name = resolve_forever_name(m.name, m.surname, m.guid) or m.name
        if curRealm ~= "" then
            m.realm = curRealm
        end
        if m.guid and m.name and m.name:find(" ", 1, true) and SfuiDB and type(SfuiDB.alts) == "table" and type(SfuiDB.alts[m.guid]) == "table" then
            local alt = SfuiDB.alts[m.guid]
            local _, sPart = string_match(m.name, "^(%S+)%s+(.+)$")
            if sPart and sPart ~= "" and not is_forever_realm_token(sPart) and (not alt.surname or alt.surname == "") then
                alt.surname = sPart
            end
        end
        local key = normalize_peer_key(m.name, m.realm)
        if key then
            peersTbl[key] = m
        end
    end
end

function sync.SanitizePeers()
    if SfuiDB and type(SfuiDB.sync) == "table" and type(SfuiDB.sync.peers) == "table" then
        sanitize_and_merge_peers_table(SfuiDB.sync.peers)
    end
    local bcs = _G.Blizzard_Console_SavedVars
    if type(bcs) == "table" and type(bcs.sfui_sync) == "table" and type(bcs.sfui_sync.peers) == "table" then
        sanitize_and_merge_peers_table(bcs.sfui_sync.peers)
    end
end

function sync.GetPeerDisplayName(peer)
    if type(peer) ~= "table" then return "unknown" end
    if not sfui.isRetail then
        local resolved = resolve_forever_name(peer.name or "", peer.surname, peer.guid)
        if resolved and resolved ~= "" then
            peer.name = resolved
            return resolved
        end
    end
    return peer.name or "unknown"
end

-- Returns the full player name for a unit token.
-- On Forever/Camelot (`not sfui.isRetail`), resolves the full "First Last" character name with no realm suffix.
function sync.FullName(unit)
    unit = unit or "player"
    local cSecrets = _G.C_Secrets
    if unit ~= "player" and cSecrets and cSecrets.ShouldUnitIdentityBeSecret and cSecrets.ShouldUnitIdentityBeSecret(unit) then
        return nil
    end
    local issecret = (sfui.common and sfui.common.issecretvalue) or _G.issecretvalue
    local isSelf = (unit == "player")
        or (not (cSecrets and cSecrets.ShouldUnitComparisonBeSecret and cSecrets.ShouldUnitComparisonBeSecret(unit, "player"))
            and _G.UnitIsUnit and _G.UnitIsUnit(unit, "player"))
    if not sfui.isRetail then
        if isSelf and sfui.common and sfui.common.get_player_display_name then
            local pName = sfui.common.get_player_display_name()
            if pName and not (issecret and issecret(pName)) and pName ~= "" and pName ~= "Unknown" and pName ~= _G.UNKNOWNOBJECT then
                local pGuid = UnitGUID and UnitGUID("player")
                if issecret and issecret(pGuid) then pGuid = nil end
                return resolve_forever_name(pName, nil, pGuid) or pName
            end
        end
        local uFirst, uSecond
        if UnitName then
            uFirst, uSecond = UnitName(unit)
        end
        if issecret then
            if issecret(uFirst) then uFirst = nil end
            if issecret(uSecond) then uSecond = nil end
        end
        if uFirst and uFirst ~= "" and uFirst ~= _G.UNKNOWNOBJECT then
            local g = UnitGUID and UnitGUID(unit)
            if issecret and issecret(g) then g = nil end
            return resolve_forever_name(uFirst, uSecond, g) or uFirst
        end
    end
    local GetUnitName = _G.GetUnitName
    local n = (GetUnitName and GetUnitName(unit, true)) or (UnitName and UnitName(unit))
    if not n or (issecret and issecret(n)) or n == "" or n == _G.UNKNOWNOBJECT then return nil end
    return n
end

function sync.CommandName(nameOrFull)
    if type(nameOrFull) ~= "string" or nameOrFull == "" then return "" end
    local _, shortName, realm = normalize_peer_key(nameOrFull)
    if not shortName then return nameOrFull end
    if not sfui.isRetail then
        return shortName
    end
    local curRealm = get_current_realm()
    if not realm or realm == "" or string_lower(realm) == string_lower(curRealm) then
        return shortName
    end
    return shortName .. "-" .. realm
end

local function get_whisper_target(nameOrFull, peer)
    local _, shortName, realm = normalize_peer_key(nameOrFull, peer and peer.realm)
    if not shortName then return nameOrFull end
    local curRealm = get_current_realm()
    if not sfui.isRetail or not realm or realm == "" or string_lower(realm) == string_lower(curRealm) then
        return shortName
    end
    return shortName .. "-" .. realm
end

local function is_self_character(nameOrFull)
    local myName = sync.FullName("player") or (UnitName and UnitName("player"))
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
            local sameRuleset = not (sfui.alts and sfui.alts.IsSameRuleset) or sfui.alts.IsSameRuleset(alt, guid)
            if type(alt) == "table" and alt.name and sameRuleset then
                local disp = (sfui.alts and sfui.alts.GetDisplayName and sfui.alts.GetDisplayName(alt, guid)) or alt.name
                if string_lower(disp) == lowerShort or string_lower(alt.name) == lowerShort then
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
    end
    return false
end

-- Machine-wide shared store via `Blizzard_Console_SavedVars` (`SavedVariablesMachine` per PC)
local function sync_machine_store()
    local bcs = _G.Blizzard_Console_SavedVars
    if type(bcs) ~= "table" then return end
    bcs.sfui_sync = type(bcs.sfui_sync) == "table" and bcs.sfui_sync or {}
    local ms = bcs.sfui_sync
    ms.peers = type(ms.peers) == "table" and ms.peers or {}

    local s = sync.GetSettings()
    sanitize_and_merge_peers_table(ms.peers)
    sanitize_and_merge_peers_table(s.peers)

    local myName = sync.FullName("player")
    local myGUID = UnitGUID and UnitGUID("player")
    local _, myClass = _G.UnitClass and _G.UnitClass("player")
    local myLevel = _G.UnitLevel and _G.UnitLevel("player")
    local now = (GetServerTime and GetServerTime()) or time()

    if myName and myName ~= "" then
        local myKey, shortName, realm = normalize_peer_key(myName)
        if myKey and shortName then
            ms.peers[myKey] = {
                name         = shortName,
                realm        = realm or get_current_realm(),
                guid         = myGUID,
                class        = myClass,
                level        = myLevel,
                accountID    = s.accountID,
                accountLabel = s.accountLabel,
                lastSeen     = now,
            }
        end
    end

    -- Import any machine-wide characters from other accounts on this PC
    for _, mp in pairs(ms.peers) do
        if type(mp) == "table" and mp.name and mp.accountID ~= s.accountID and not is_self_character(mp.name) then
            local normKey, shortName, realm = normalize_peer_key(mp.name, mp.realm)
            if normKey and shortName then
                local existing = s.peers[normKey]
                if not existing then
                    s.peers[normKey] = {
                        name         = shortName,
                        surname      = mp.surname,
                        realm        = realm or get_current_realm(),
                        guid         = mp.guid,
                        class        = mp.class,
                        level        = mp.level,
                        trusted      = true,
                        addedAt      = now,
                        lastSeen     = tonumber(mp.lastSeen) or 0,
                        accountID    = mp.accountID or "peer-acct-default",
                        accountLabel = mp.accountLabel,
                    }
                else
                    merge_peer_into(existing, mp)
                end
            end
        end
    end

    sanitize_and_merge_peers_table(s.peers)

    -- Export our known peers to the machine store
    for _, lp in pairs(s.peers) do
        if type(lp) == "table" and lp.name then
            local normKey, shortName, realm = normalize_peer_key(lp.name, lp.realm)
            if normKey and shortName then
                if not ms.peers[normKey] then
                    ms.peers[normKey] = {
                        name         = shortName,
                        surname      = lp.surname,
                        realm        = realm or lp.realm,
                        guid         = lp.guid,
                        class        = lp.class,
                        level        = lp.level,
                        accountID    = lp.accountID,
                        accountLabel = lp.accountLabel,
                        lastSeen     = lp.lastSeen,
                    }
                else
                    merge_peer_into(ms.peers[normKey], lp)
                end
            end
        end
    end

    sanitize_and_merge_peers_table(ms.peers)

    -- Reconcile shared settings across accounts on the same PC
    local locRev = tonumber(s.settingsRev) or 0
    local macSettings = ms.settings
    local macRev = (type(macSettings) == "table" and tonumber(macSettings.rev)) or 0
    if macRev > locRev then
        sync.ApplySharedSettings(macSettings, "machine", true)
    elseif locRev > macRev then
        ms.settings = sync.BuildSharedSettingsPayload(s)
    end

    -- Reconcile per-character fishing ledgers across accounts on the same PC
    if s.syncFishing ~= false and merge and merge.MergeFishingChar then
        if sfui.fishing and sfui.fishing.EnsureCharLedger then
            sfui.fishing.EnsureCharLedger()
        end
        ms.fishing_chars = type(ms.fishing_chars) == "table" and ms.fishing_chars or {}
        for fGuid, mData in pairs(ms.fishing_chars) do
            if type(fGuid) == "string" and type(mData) == "table" then
                if (myGUID and fGuid == myGUID) or (SfuiDB and SfuiDB.alts and SfuiDB.alts[fGuid]) then
                    merge.MergeFishingChar(fGuid, mData, mData.accountLabel, mData.accountID)
                end
            end
        end
        local locChars = SfuiDB and SfuiDB.fishing and SfuiDB.fishing.chars
        if type(locChars) == "table" then
            for fGuid, cData in pairs(locChars) do
                if type(fGuid) == "string" and type(cData) == "table" then
                    local ex = ms.fishing_chars[fGuid]
                    local lRev = tonumber(cData.rev) or 0
                    local mRev = (type(ex) == "table" and tonumber(ex.rev)) or 0
                    if not ex or lRev >= mRev then
                        local payload = merge.BuildFishingCharPayload and merge.BuildFishingCharPayload(fGuid)
                        if payload and payload.data then
                            ms.fishing_chars[fGuid] = payload.data
                        end
                    end
                end
            end
        end
    end
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
        if not sfui.isRetail then
            local probe = { name = shortName }
            local matchedPeer, matchedKey = nil, nil
            local count = 0
            for k, p in pairs(s.peers) do
                if type(p) == "table" and peers_match_forever(probe, p) then
                    matchedPeer, matchedKey = p, k
                    count = count + 1
                end
            end
            if count == 1 then
                return matchedPeer, matchedKey
            end
        end
    end
    return nil, key
end

local liveOnlineCache = {}
local liveOnlineCacheTime = 0

function sync.MarkPeerOnline(nameOrFull, peerAccountID)
    local _, shortName = normalize_peer_key(nameOrFull)
    if not shortName then return end
    local lowerShort = string_lower(shortName)
    local peer = sync.FindPeer(nameOrFull)
    local peerLower = (peer and peer.name and string_lower(peer.name)) or nil
    local now = (GetTime and GetTime()) or 0

    -- A single WoW account only has one character online at a time:
    -- clear online status of other alts on that same peer account
    if peerAccountID and peerAccountID ~= "" then
        local s = sync.GetSettings()
        for _, p in pairs(s.peers) do
            if type(p) == "table" and p.accountID == peerAccountID and p.name then
                local pShort = string_lower(p.name)
                if pShort ~= lowerShort and pShort ~= peerLower then
                    onlinePeers[pShort] = nil
                end
            end
        end
    end

    onlinePeers[lowerShort] = now
    offlinePeers[lowerShort] = nil
    if peerLower and peerLower ~= lowerShort then
        onlinePeers[peerLower] = now
        offlinePeers[peerLower] = nil
    end
    liveOnlineCacheTime = 0
end

function sync.MarkPeerOffline(nameOrFull)
    local _, shortName = normalize_peer_key(nameOrFull)
    if not shortName then return end
    local lowerShort = string_lower(shortName)
    local peer = sync.FindPeer(nameOrFull)
    local peerLower = (peer and peer.name and string_lower(peer.name)) or nil
    local now = (GetTime and GetTime()) or 1
    onlinePeers[lowerShort] = nil
    offlinePeers[lowerShort] = now
    if peerLower and peerLower ~= lowerShort then
        onlinePeers[peerLower] = nil
        offlinePeers[peerLower] = now
    end
    liveOnlineCacheTime = 0
    if codec and codec.CancelWhispersToTarget then
        codec.CancelWhispersToTarget(shortName)
    end
end

-- Check Party/Raid, Friends, BNet, Guild, and session cache to see who is actually online (cached for 2s)
local function build_live_online_map()
    local now = (GetTime and GetTime()) or 0
    if liveOnlineCacheTime > 0 and (now - liveOnlineCacheTime) < 2.0 then
        return liveOnlineCache
    end
    liveOnlineCacheTime = now
    local map = liveOnlineCache
    wipe(map)

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
                local full = sync.FullName(u)
                if full and full ~= "" then
                    local _, shortName = normalize_peer_key(full)
                    local lowerFull = string_lower(shortName or full)
                    map[lowerFull] = true
                    offlinePeers[lowerFull] = nil
                end
                local uName = UnitName(u)
                if uName and uName ~= "" then
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
                local lower = string_lower(shortName or info.name)
                map[lower] = true
                offlinePeers[lower] = nil
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
                    local _, shortName = normalize_peer_key(gameInfo.characterName)
                    local lower = string_lower(shortName or gameInfo.characterName)
                    map[lower] = true
                    offlinePeers[lower] = nil
                end
            end
        end
    end

    -- 4. Guild Roster (only when guild sync is enabled)
    local s = sync.GetSettings()
    if s.useGuild and IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
        local numGuild = GetNumGuildMembers() or 0
        for i = 1, numGuild do
            local fullName, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
            if online and fullName then
                local _, shortName = normalize_peer_key(fullName)
                local lower = string_lower(shortName or fullName)
                map[lower] = true
                offlinePeers[lower] = nil
            end
        end
    end

    -- On Forever, if a source reported only the 1st name (e.g. "lilith"), also mark the full "first last" peer online
    if not sfui.isRetail and type(s.peers) == "table" then
        for _, p in pairs(s.peers) do
            if type(p) == "table" and p.name then
                local pLower = string_lower(p.name)
                if not map[pLower] and not offlinePeers[pLower] then
                    local fLower = string_match(pLower, "^(%S+)")
                    if fLower and fLower ~= pLower and map[fLower] then
                        map[pLower] = map[fLower]
                    end
                end
            end
        end
    end

    return map
end

function sync.IsPeerOnline(nameOrFull)
    if type(nameOrFull) ~= "string" or nameOrFull == "" then return false end
    local _, shortName = normalize_peer_key(nameOrFull)
    local key = string_lower(shortName or nameOrFull)
    if offlinePeers[key] then return false end
    local map = build_live_online_map()
    if map[key] ~= nil then return true end
    if not sfui.isRetail then
        local peer = sync.FindPeer(nameOrFull)
        if peer and peer.name then
            local pKey = string_lower(peer.name)
            if not offlinePeers[pKey] and map[pKey] ~= nil then
                return true
            end
        end
    end
    return false
end

function sync.AddOrUpdatePeer(nameOrFull, meta)
    if not sfui.isRetail then
        nameOrFull = resolve_forever_name(nameOrFull, meta and meta.surname, meta and meta.guid) or nameOrFull
    end
    if is_self_character(nameOrFull) then return nil end
    local s = sync.GetSettings()
    local key, shortName, realm = normalize_peer_key(nameOrFull, meta and meta.realm)
    if not key or not shortName then return nil end

    local existing = s.peers[key]
    local existingKey = existing and key or nil
    if not existing then
        local lowerShort = string_lower(shortName)
        local mGuid = type(meta) == "table" and meta.guid or nil
        for k, p in pairs(s.peers) do
            if type(p) == "table" then
                if (mGuid and mGuid ~= "" and p.guid == mGuid)
                    or (p.name and string_lower(p.name) == lowerShort) then
                    existing = p
                    existingKey = k
                    break
                end
            end
        end
        if not existing and not sfui.isRetail then
            local probe = {
                name         = shortName,
                guid         = mGuid,
                accountID    = type(meta) == "table" and meta.accountID or nil,
                accountLabel = type(meta) == "table" and meta.accountLabel or nil,
            }
            for k, p in pairs(s.peers) do
                if type(p) == "table" and peers_match_forever(probe, p) then
                    existing = p
                    existingKey = k
                    break
                end
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
    else
        if not sfui.isRetail then
            local curHasSpace = type(existing.name) == "string" and existing.name:find(" ", 1, true) ~= nil
            local newHasSpace = shortName:find(" ", 1, true) ~= nil
            if newHasSpace and not curHasSpace then
                existing.name = shortName
                if existingKey and existingKey ~= key then
                    s.peers[existingKey] = nil
                    s.peers[key] = existing
                end
            else
                key = existingKey or key
            end
        else
            key = existingKey or key
        end
    end

    if type(meta) == "table" then
        if meta.surname and meta.surname ~= "" and not is_forever_realm_token(meta.surname) then
            existing.surname = meta.surname
        end
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
        if not sfui.isRetail then
            local upgraded = resolve_forever_name(existing.name, existing.surname, existing.guid)
            if upgraded and upgraded ~= "" and upgraded ~= existing.name then
                local newKey = normalize_peer_key(upgraded, existing.realm)
                existing.name = upgraded
                if newKey and newKey ~= key then
                    s.peers[key] = nil
                    s.peers[newKey] = existing
                    key = newKey
                end
            end
        end
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
    local bcs = _G.Blizzard_Console_SavedVars
    if type(bcs) == "table" and type(bcs.sfui_sync) == "table" and type(bcs.sfui_sync.peers) == "table" then
        local mp = bcs.sfui_sync.peers
        if mp[keyOrName] then
            mp[keyOrName] = nil
        else
            local normKey = normalize_peer_key(keyOrName)
            if normKey and mp[normKey] then
                mp[normKey] = nil
            end
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
    local activeFirst = activeLower and string_match(activeLower, "^(%S+)") or nil
    local acctID = (peerAccountID and peerAccountID ~= "") and peerAccountID
        or ((peerAccountLabel and peerAccountLabel ~= "") and ("label:" .. string_lower(peerAccountLabel)))
        or (activeLower and ("acct:" .. activeLower))
        or "peer-acct-default"

    for _, entry in ipairs(roster) do
        if type(entry) == "table" and entry.name and entry.name ~= "" then
            local fullName
            if not sfui.isRetail then
                fullName = resolve_forever_name(entry.name, entry.surname, entry.guid) or entry.name
            else
                fullName = entry.realm and entry.realm ~= "" and (entry.name .. "-" .. entry.realm:gsub("%s+", "")) or entry.name
            end
            if not is_self_character(fullName) then
                local existing = sync.FindPeer(fullName)
                local entryLower = string_lower(fullName)
                local entryFirst = string_match(entryLower, "^(%S+)") or entryLower
                local isSender = activeLower and (entryLower == activeLower
                    or string_lower(entry.name) == activeLower
                    or (not sfui.isRetail and activeFirst and entryFirst == activeFirst and (entryLower == entryFirst or activeLower == activeFirst)))
                sync.AddOrUpdatePeer(fullName, {
                    guid         = entry.guid,
                    surname      = entry.surname,
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
local pendingOutgoingPairs = {}
local PENDING_PAIR_TTL = 180

local function get_active_group_channel(allowDiscovery)
    local ch = codec and codec.ResolveGroupChannel and codec.ResolveGroupChannel()
    if not ch then return nil end
    local mb = sync.multibox
    if mb and mb.HasSyncedPartyMember and mb.HasSyncedPartyMember() then
        return ch
    end
    if allowDiscovery then
        return ch
    end
    local partyTs = pendingOutgoingPairs["*party*"]
    if partyTs then
        local now = (GetServerTime and GetServerTime()) or time()
        if (now - partyTs) <= PENDING_PAIR_TTL then
            return ch
        end
    end
    return nil
end

local function send_to_peer(peerName, msgType, dataTable, replyChannel, bnetIDAccount)
    local s = sync.GetSettings()
    if not s.enabled then return false end

    if replyChannel == "BNET" and bnetIDAccount then
        return codec.SendMessage(PREFIX, msgType, dataTable, "BNET", nil, bnetIDAccount)
    end
    if (replyChannel == "PARTY" or replyChannel == "RAID" or replyChannel == "INSTANCE_CHAT") and s.useParty then
        local ch = get_active_group_channel(msgType == "PAIR_ACK" or msgType == "HELLO")
        if ch then
            return codec.SendMessage(PREFIX, msgType, dataTable, ch)
        end
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
    if s.useParty then
        local allowDiscovery = (msgType == "HELLO") and (s.passcode and s.passcode ~= "")
        local ch = get_active_group_channel(allowDiscovery)
        if ch then
            codec.SendMessage(PREFIX, msgType, dataTable, ch)
            sentGroup = true
        end
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
                    local peer = charName and not is_self_character(charName) and sync.FindPeer(charName)
                    if peer then
                        codec.SendMessage(PREFIX, msgType, dataTable, "BNET", nil, gameInfo.gameAccountID)
                        bnetSentNames[string_lower(charName)] = true
                        if peer.name then
                            bnetSentNames[string_lower(peer.name)] = true
                        end
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
                    local full = sync.FullName(u)
                    if full and full ~= "" then
                        local _, shortName = normalize_peer_key(full)
                        partyNames[string_lower(shortName or full)] = true
                    end
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

                local peerDisp = sync.GetPeerDisplayName(peer)
                local lowerName = string_lower(peerDisp)
                local firstLower = not sfui.isRetail and string_match(lowerName, "^(%S+)") or nil
                if partyNames[lowerName] or bnetSentNames[lowerName]
                    or (firstLower and (partyNames[firstLower] or bnetSentNames[firstLower])) then
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

local SHARED_SETTING_KEYS = {
    "syncAlts",
    "syncQuests",
    "syncWaypoints",
    "syncRecipes",
    "syncContacts",
    "syncFishing",
    "syncMail",
    "mbAutoFollow",
    "mbAutoInvite",
    "mbAutoQuest",
    "mbAutoTaxi",
    "mbAutoTrade",
    "mbCorpseAlert",
    "mbShowHud",
    "mbFollowerPassLoot",
    "autoSyncOnLogin",
    "useParty",
    "useWhisper",
    "useGuild",
    "useBNet",
}

local SHARED_KEY_LOOKUP = {}
for _, k in ipairs(SHARED_SETTING_KEYS) do
    SHARED_KEY_LOOKUP[k] = true
end

function sync.BuildSharedSettingsPayload(s)
    s = s or sync.GetSettings()
    local cfg = {}
    for _, k in ipairs(SHARED_SETTING_KEYS) do
        cfg[k] = (s[k] == true) and 1 or 0
    end
    return {
        rev = tonumber(s.settingsRev) or 0,
        cfg = cfg,
    }
end

function sync.ApplySharedSettings(payload, sender, silent)
    if type(payload) ~= "table" or type(payload.cfg) ~= "table" then return false end
    local s = sync.GetSettings()
    local inRev = tonumber(payload.rev) or 0
    local changed = false

    sync._applyingRemoteSettings = true
    for _, k in ipairs(SHARED_SETTING_KEYS) do
        local raw = payload.cfg[k]
        if raw ~= nil then
            local newVal = (raw == 1 or raw == true)
            if (s[k] == true) ~= newVal then
                s[k] = newVal
                changed = true
            end
        end
    end
    if inRev > (tonumber(s.settingsRev) or 0) then
        s.settingsRev = inRev
    end
    sync._applyingRemoteSettings = false

    if changed then
        if sfui.events and sfui.events.SendMessage then
            sfui.events.SendMessage("SFUI_SYNC_STATUS_UPDATED")
        end
        if not silent and sfui.common and sfui.common.print and sender then
            sfui.common.print("sync: applied shared sync settings from |cff00ffff" .. string_lower(tostring(sender)) .. "|r.")
        end
    end
    return changed
end

function sync.BroadcastSettingsNow()
    local s = sync.GetSettings()
    if not s.enabled then return end
    s.settingsRev = (GetServerTime and GetServerTime()) or time()
    local payload = sync.BuildSharedSettingsPayload(s)
    sync_machine_store()
    sync.Broadcast("DELTA_SYNC_SETTINGS", payload, true, false)
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
    if (tonumber(s.settingsRev) or 0) == 0 then
        s.settingsRev = (GetServerTime and GetServerTime()) or time()
    end
    sync_machine_store()
    if sfui.alts and sfui.alts.PerformSync then
        sfui.alts.PerformSync(false)
    end
    local manifest = merge.BuildManifest(s)
    sync.Broadcast("HELLO", manifest, true, true)
    sfui.common.print("sync: broadcasting content manifest to linked accounts...")
end

local hwReloadFrame = nil

local function do_raw_reload()
    if _G.C_UI and _G.C_UI.Reload then
        _G.C_UI.Reload()
    elseif _G.ReloadUI then
        _G.ReloadUI()
    end
end

local function arm_hardware_reload_catcher(sender)
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        sync._pendingRemoteReload = tostring(sender or "peer")
        return
    end

    if not hwReloadFrame then
        hwReloadFrame = CreateFrame("Button", "SfuiRemoteReloadCatcher", _G.UIParent, "BackdropTemplate")
        hwReloadFrame:SetAllPoints(_G.UIParent)
        hwReloadFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        hwReloadFrame:SetFrameLevel(9999)
        hwReloadFrame:EnableMouse(true)
        hwReloadFrame:RegisterForClicks("AnyUp")

        local banner = CreateFrame("Frame", nil, hwReloadFrame, "BackdropTemplate")
        banner:SetSize(400, 52)
        banner:SetPoint("TOP", hwReloadFrame, "TOP", 0, -140)
        if sfui.common and sfui.common.apply_flat_backdrop then
            sfui.common.apply_flat_backdrop(banner, { 0.05, 0.05, 0.08, 0.95 }, { 0.0, 0.85, 1.0, 1.0 })
        end

        local line1 = banner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        line1:SetPoint("TOP", banner, "TOP", 0, -10)
        line1:SetTextColor(0.0, 1.0, 1.0)
        hwReloadFrame.line1 = line1

        local line2 = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line2:SetPoint("TOP", line1, "BOTTOM", 0, -4)
        line2:SetTextColor(0.9, 0.9, 0.95)
        line2:SetText("click anywhere to reload ui")
        hwReloadFrame.line2 = line2

        local function trigger_now()
            if _G.InCombatLockdown and _G.InCombatLockdown() then
                sync._pendingRemoteReload = hwReloadFrame.senderName or "peer"
                hwReloadFrame:Hide()
                return
            end
            sync._pendingRemoteReload = false
            do_raw_reload()
            hwReloadFrame:Hide()
        end

        hwReloadFrame:SetScript("OnClick", trigger_now)
        if sfui.events and sfui.events.RegisterEvent then
            sfui.events.RegisterEvent("PLAYER_REGEN_DISABLED", function()
                if hwReloadFrame and hwReloadFrame:IsShown() then
                    sync._pendingRemoteReload = hwReloadFrame.senderName or "peer"
                    hwReloadFrame:Hide()
                end
            end)
        end
    end

    local cleanSender = string_lower(tostring(sender or "linked account"))
    hwReloadFrame.senderName = cleanSender
    if hwReloadFrame.line1 then
        hwReloadFrame.line1:SetText("sync: reload requested by " .. cleanSender)
    end
    hwReloadFrame:Show()
end

local function execute_local_reload(isRemote, sender)
    if isRemote then
        arm_hardware_reload_catcher(sender)
        return
    end
    do_raw_reload()
end

function sync.ReloadAllClients()
    local s = sync.GetSettings()
    if s.enabled then
        sync_machine_store()
        local payload = {
            pass = (s.passcode ~= "" and s.passcode) or nil,
            t    = (GetServerTime and GetServerTime()) or time(),
        }
        sync.Broadcast("CMD_RELOAD", payload, true, true)
        if not s.useParty then
            local ch = get_active_group_channel(false)
            if ch then
                codec.SendMessage(PREFIX, "CMD_RELOAD", payload, ch)
            end
        end
        if codec and codec.FlushQueue then
            codec.FlushQueue()
        end
    end
    execute_local_reload(false)
end

local function mark_pending_outgoing_pair(nameOrKey)
    local now = (GetServerTime and GetServerTime()) or time()
    if not nameOrKey or nameOrKey == "" then return end
    local normKey, shortName = normalize_peer_key(nameOrKey)
    if normKey then
        pendingOutgoingPairs[string_lower(normKey)] = now
    end
    if shortName then
        pendingOutgoingPairs[string_lower(shortName)] = now
    end
end

local function is_pending_outgoing_pair(sender)
    local now = (GetServerTime and GetServerTime()) or time()
    local partyTs = pendingOutgoingPairs["*party*"]
    if partyTs and (now - partyTs) <= PENDING_PAIR_TTL then
        return true
    end
    local normKey, shortName = normalize_peer_key(sender)
    if normKey then
        local ts = pendingOutgoingPairs[string_lower(normKey)]
        if ts and (now - ts) <= PENDING_PAIR_TTL then
            return true
        end
    end
    if shortName then
        local ts = pendingOutgoingPairs[string_lower(shortName)]
        if ts and (now - ts) <= PENDING_PAIR_TTL then
            return true
        end
    end
    return false
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
    if (tonumber(s.settingsRev) or 0) == 0 then
        s.settingsRev = (GetServerTime and GetServerTime()) or time()
    end
    if sfui.alts and sfui.alts.PerformSync then
        sfui.alts.PerformSync(false)
    end
    local _, shortName = normalize_peer_key(targetName)
    if shortName then
        offlinePeers[string_lower(shortName)] = nil
    end
    mark_pending_outgoing_pair(targetName)
    local existingPeer = sync.FindPeer(targetName)
    local manifest = merge.BuildManifest(s)
    local whisperTarget = get_whisper_target(targetName, existingPeer)
    codec.SendMessage(PREFIX, "PAIR_REQ", {
        passcode     = s.passcode or "",
        accountID    = s.accountID or "",
        accountLabel = s.accountLabel or "",
        roster       = manifest.roster,
        manifest     = manifest,
    }, "WHISPER", whisperTarget)
    sfui.common.print("sync: sent pair request to |cff00ffff" .. whisperTarget:lower() .. "|r (awaiting confirmation)...")
    return true
end

function sync.PairWithTarget()
    if not (UnitExists and UnitExists("target") and UnitIsPlayer and UnitIsPlayer("target")) then
        sfui.common.print("sync: target a player character on your other account first.")
        return false
    end
    local full = sync.FullName("target")
    if not full or full == "" then return false end
    return sync.PairWithCharacter(full)
end

function sync.PairWithParty()
    local ch = get_active_group_channel(true)
    if not ch then
        sfui.common.print("sync: you are not in a party or raid.")
        return false
    end
    local s = sync.GetSettings()
    if (tonumber(s.settingsRev) or 0) == 0 then
        s.settingsRev = (GetServerTime and GetServerTime()) or time()
    end
    if sfui.alts and sfui.alts.PerformSync then
        sfui.alts.PerformSync(false)
    end

    local now = (GetServerTime and GetServerTime()) or time()
    pendingOutgoingPairs["*party*"] = now
    local count = 0
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    local prefixUnit = (IsInRaid and IsInRaid()) and "raid" or "party"
    for i = 1, n do
        local u = prefixUnit .. i
        if UnitExists and UnitExists(u) and UnitIsPlayer and UnitIsPlayer(u) then
            local full = sync.FullName(u)
            if full and full ~= "" and not is_self_character(full) then
                mark_pending_outgoing_pair(full)
                count = count + 1
            end
        end
    end

    local manifest = merge.BuildManifest(s)
    codec.SendMessage(PREFIX, "PAIR_REQ", {
        passcode     = s.passcode or "",
        accountID    = s.accountID or "",
        accountLabel = s.accountLabel or "",
        roster       = manifest.roster,
        manifest     = manifest,
    }, ch)
    sfui.common.print(string_format("sync: sent pair request to %d party member(s) (awaiting confirmation)...", count))
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
    if type(remoteManifest.settings) == "table" then
        local remRev = tonumber(remoteManifest.settings.rev) or 0
        local locRev = tonumber(s.settingsRev) or 0
        if remRev > locRev then
            sync.ApplySharedSettings(remoteManifest.settings, sender, true)
        elseif locRev > remRev then
            send_to_peer(sender, "DELTA_SYNC_SETTINGS", sync.BuildSharedSettingsPayload(s), replyChannel, bnetIDAccount)
        end
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
            for guid, remInfo in pairs(remoteManifest.quests) do
                local locAlt = SfuiDB.alts[guid]
                local locRev = locAlt and (tonumber(locAlt.questsRev) or 0) or 0
                local rRev = 0
                local rActive = nil
                local rDone = nil
                if type(remInfo) == "table" then
                    rRev = tonumber(remInfo.r) or 0
                    rActive = tonumber(remInfo.a)
                    rDone = tonumber(remInfo.c)
                else
                    rRev = tonumber(remInfo) or 0
                end

                local locActive = 0
                local locDone = 0
                local hasPartial = false
                if type(locAlt) == "table" then
                    if type(locAlt.activeQuests) == "table" then
                        for _, qv in pairs(locAlt.activeQuests) do
                            if type(qv) == "table" and qv._partial == 1 then
                                hasPartial = true
                            else
                                locActive = locActive + 1
                            end
                        end
                    end
                    if type(locAlt.completedQuests) == "table" then
                        for _, cv in pairs(locAlt.completedQuests) do
                            if cv and cv ~= 0 then
                                locDone = locDone + 1
                            end
                        end
                    end
                end

                local wantThis = (not locAlt)
                    or (rRev > locRev)
                    or hasPartial
                    or (rRev == locRev and ((rActive and rActive ~= locActive) or (rDone and rDone > locDone)))
                local pushThis = (not wantThis) and (
                    (locRev > rRev)
                    or (locRev == rRev and not hasPartial and ((rActive and locActive > rActive) or (rDone and locDone > rDone)))
                )

                if wantThis then
                    table_insert(want.quests, guid)
                    hasWant = true
                elseif pushThis then
                    local payload = merge.BuildQuestsPayload(guid)
                    if payload then
                        send_to_peer(sender, "DATA_QUESTS", payload, replyChannel, bnetIDAccount)
                    end
                end
            end
            for guid, locAlt in pairs(SfuiDB.alts) do
                if type(locAlt) == "table" and remoteManifest.quests[guid] == nil
                    and ((locAlt.activeQuests and next(locAlt.activeQuests))
                        or (locAlt.completedQuests and next(locAlt.completedQuests))
                        or (locAlt.djQuests and next(locAlt.djQuests))) then
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
        local lc = (merge.GetContactsCounts and merge.GetContactsCounts()) or {}
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
        sfui.events.SendMessage("SFUI_SYNC_STATUS_UPDATED", "MANIFEST")
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

    if sfui.camelot_skills and sfui.camelot_skills.BroadcastTrackedSkills then
        sfui.camelot_skills.BroadcastTrackedSkills(true)
    end
    if sfui.recipes and sfui.recipes.BroadcastPinnedRecipes then
        sfui.recipes.BroadcastPinnedRecipes(true)
    end
end

local pendingIncomingPairReq = nil

local function accept_incoming_pair_request(req)
    if type(req) ~= "table" or not req.sender or type(req.data) ~= "table" then return end
    local s = sync.GetSettings()
    local now = (GetServerTime and GetServerTime()) or time()
    local sender = req.sender
    local data = req.data
    local channel = req.channel
    local bnetIDAccount = req.bnetIDAccount

    sync.MarkPeerOnline(sender, data.accountID)
    local peer = sync.AddOrUpdatePeer(sender, {
        accountID    = data.accountID,
        accountLabel = data.accountLabel,
        lastSeen     = now,
        lastSync     = now,
    })
    local imported = sync.ImportPeerRoster(data.roster, data.accountLabel, data.accountID, sender)
    sync_machine_store()

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
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_SYNC_STATUS_UPDATED")
    end
end

if _G.StaticPopupDialogs then
    _G.StaticPopupDialogs["SFUI_SYNC_PAIR_CONFIRM"] = {
        text = "sfui sync: |cff00ffff%s|r%s wants to link accounts and sync character data with you.\n\ndo you want to accept this pairing request?",
        button1 = "accept & link",
        button2 = "decline",
        OnAccept = function(self, reqData)
            local req = reqData or pendingIncomingPairReq
            pendingIncomingPairReq = nil
            accept_incoming_pair_request(req)
        end,
        OnCancel = function(self, reqData)
            local req = reqData or pendingIncomingPairReq
            pendingIncomingPairReq = nil
            if req and req.sender and sfui.common and sfui.common.print then
                sfui.common.print("sync: declined pairing request from |cff00ffff" .. string_lower(tostring(req.sender)) .. "|r.")
            end
        end,
        timeout = 60,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

-- ── Incoming Message Dispatcher ───────────────────────────────────────────────
local on_local_quests_updated
local notify_peer_quest_completed

local function on_decoded_message(sender, msgType, data, channel, bnetIDAccount)
    if not sender or is_self_character(sender) then return end
    local s = sync.GetSettings()
    if not s.enabled then return end

    local now = (GetServerTime and GetServerTime()) or time()
    local peer = sync.FindPeer(sender)

    -- Handle pairing handshake (PAIR_REQ / PAIR_ACK)
    if msgType == "PAIR_REQ" and type(data) == "table" then
        if peer and peer.trusted then
            accept_incoming_pair_request({
                sender        = sender,
                data          = data,
                channel       = channel,
                bnetIDAccount = bnetIDAccount,
            })
            return
        end

        local myPass = s.passcode or ""
        local inPass = data.passcode or ""
        if myPass ~= "" and inPass ~= myPass then
            sfui.common.print("sync: ignored pair request from |cff00ffff" .. sender:lower() .. "|r (passcode mismatch).")
            return
        end

        local req = {
            sender        = sender,
            data          = data,
            channel       = channel,
            bnetIDAccount = bnetIDAccount,
        }
        pendingIncomingPairReq = req
        local labelTag = (data.accountLabel and data.accountLabel ~= "")
            and (" |cff888888[" .. string_lower(tostring(data.accountLabel)) .. "]|r")
            or ""
        if _G.StaticPopup_Show then
            local dlg = _G.StaticPopup_Show("SFUI_SYNC_PAIR_CONFIRM", string_lower(tostring(sender)), labelTag)
            if dlg then
                dlg.data = req
            end
        end
        return
    elseif msgType == "PAIR_ACK" and type(data) == "table" then
        if not (peer and peer.trusted) and not is_pending_outgoing_pair(sender) then
            return
        end
        sync.MarkPeerOnline(sender, data.accountID)
        peer = sync.AddOrUpdatePeer(sender, {
            accountID    = data.accountID,
            accountLabel = data.accountLabel,
            lastSeen     = now,
            lastSync     = now,
        })
        local imported = sync.ImportPeerRoster(data.roster, data.accountLabel, data.accountID, sender)
        sync_machine_store()
        if data.manifest then
            handle_manifest_from_peer(sender, peer, data.manifest, channel, bnetIDAccount)
        end
        sfui.common.print(string_format("sync: pairing confirmed by |cff00ffff%s|r (%d character(s) linked).",
            sender:lower(), imported + 1))
        if sfui.events and sfui.events.SendMessage then
            sfui.events.SendMessage("SFUI_SYNC_STATUS_UPDATED")
        end
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
                        surname      = data.data.surname,
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
        local merged, localCompChanged = merge.MergeQuests(data.guid, data)
        if merged then
            peer.lastSync = now
            if localCompChanged and on_local_quests_updated then
                on_local_quests_updated("PEER_QUEST_SYNC")
            end
        end
    elseif msgType == "DELTA_QUEST_PROG" and s.syncQuests and type(data) == "table" then
        if merge.MergeQuestProgDelta then
            local merged, missingDetails, localCompChanged, completedEvents = merge.MergeQuestProgDelta(data)
            if merged then
                peer.lastSync = now
                if completedEvents and notify_peer_quest_completed then
                    notify_peer_quest_completed(sender, data.g, completedEvents)
                end
                if missingDetails and type(data.g) == "string" and data.g ~= "" then
                    send_to_peer(sender, "WANT", { quests = { data.g } }, channel, bnetIDAccount)
                end
                if localCompChanged and on_local_quests_updated then
                    on_local_quests_updated("PEER_QUEST_SYNC")
                end
            end
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
        if merge.MergeFishingChar(data.guid, data.data, peer.accountLabel, peer.accountID) then
            peer.lastSync = now
            sync_machine_store()
        end
    elseif msgType == "DELTA_FISHING_CATCH" and s.syncFishing and type(data) == "table" then
        if merge.MergeFishingCatchDelta and merge.MergeFishingCatchDelta(data, peer.accountLabel, peer.accountID) then
            peer.lastSync = now
            sync_machine_store()
        end
    elseif msgType == "DATA_MAIL" and s.syncMail and type(data) == "table" then
        if merge.MergeMail(data) then
            peer.lastSync = now
        end
    elseif msgType == "DELTA_SYNC_SETTINGS" and type(data) == "table" then
        if sync.ApplySharedSettings(data, sender, false) then
            peer.lastSync = now
        end
    elseif msgType == "DATA_LAYOUT_PROFILE" and type(data) == "table" and type(data.payload) == "string" then
        if sfui.movers and sfui.movers.ImportProfileString then
            local ok, importedName = sfui.movers.ImportProfileString(data.payload, data.name, true, true)
            if ok then
                peer.lastSync = now
                if sfui.common and sfui.common.print then
                    sfui.common.print(string_format("sync: applied layout profile '%s' from |cff00ffff%s|r.",
                        tostring(importedName or data.name or "default"):lower(), string_lower(tostring(sender))))
                end
            end
        end
    elseif msgType == "CMD_RELOAD" then
        sync_machine_store()
        if _G.InCombatLockdown and _G.InCombatLockdown() then
            if sfui.common and sfui.common.print then
                sfui.common.print("sync: reload request from |cff00ffff" .. string_lower(tostring(sender)) .. "|r deferred until combat ends.")
            end
            sync._pendingRemoteReload = tostring(sender or "peer")
        else
            execute_local_reload(true, sender)
        end
    elseif sync.multibox and sync.multibox.HandleSyncMessage then
        sync.multibox.HandleSyncMessage(sender, msgType, data)
    end

    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_SYNC_STATUS_UPDATED", "PACKET")
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
    sync_machine_store()
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

local function on_local_fishing_catch_recorded(_, itemID, quantity, quality, mapID)
    local s = sync.GetSettings()
    if not s.enabled or not s.syncFishing then return end
    sync_machine_store()
    if InCombatLockdown and InCombatLockdown() then
        deferredAfterCombat.fishing = true
        return
    end
    local myGUID = UnitGUID and UnitGUID("player")
    if merge.BuildFishingCatchDelta then
        local delta = merge.BuildFishingCatchDelta(myGUID, itemID, mapID)
        if delta then
            sync.Broadcast("DELTA_FISHING_CATCH", delta, true, false)
            return
        end
    end
    on_local_fishing_updated()
end

local questDeltaPending = false
local questsBroadcastPending = false
local pendingTurnedInQuests = {}
local pendingAcceptedQuests = {}
on_local_quests_updated = function(event, arg1, arg2)
    if event == "UNIT_QUEST_LOG_CHANGED" then
        if not issecretvalue(arg1) and arg1 ~= "player" then
            if sfui.tracker and sfui.tracker.RequestRefresh then
                sfui.tracker.RequestRefresh(0.05)
            end
            return
        end
    elseif event == "QUEST_TURNED_IN" and not issecretvalue(arg1) and tonumber(arg1) then
        pendingTurnedInQuests[tonumber(arg1)] = true
    elseif event == "QUEST_ACCEPTED" then
        local qID = (not issecretvalue(arg2) and tonumber(arg2))
            or (not issecretvalue(arg1) and tonumber(arg1))
        if qID and qID > 0 then
            pendingAcceptedQuests[qID] = true
        end
    end
    local s = sync.GetSettings()
    if not s.enabled or s.syncQuests == false then return end

    -- 1. Fast active-quest objective delta (runs even in combat so party members see live objective progress)
    if not questDeltaPending and C_Timer and C_Timer.After then
        questDeltaPending = true
        C_Timer.After(0.35, function()
            questDeltaPending = false
            if merge.ScanActiveQuestsDelta then
                local delta = merge.ScanActiveQuestsDelta(pendingTurnedInQuests, pendingAcceptedQuests)
                if delta then
                    sync.Broadcast("DELTA_QUEST_PROG", delta, true, false)
                    if sfui.tracker and sfui.tracker.RequestRefresh then
                        sfui.tracker.RequestRefresh(0.05)
                    end
                end
            end
        end)
    end

    -- 2. Full DJ / completed-quest scan (deferred until out of combat)
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
            local myGUID = (sfui.alts and sfui.alts.GetCurrentCharacterGUID and sfui.alts.GetCurrentCharacterGUID())
                or (UnitGUID and UnitGUID("player"))
            if not myGUID or issecretvalue(myGUID) then return end
            local anyChanged = false
            if merge.ScanLocalQuestsAndDJ then
                local scanned = false
                for qid in pairs(pendingTurnedInQuests) do
                    local _, chg = merge.ScanLocalQuestsAndDJ(qid, pendingAcceptedQuests)
                    if chg then anyChanged = true end
                    pendingTurnedInQuests[qid] = nil
                    scanned = true
                end
                if not scanned then
                    local _, chg = merge.ScanLocalQuestsAndDJ(nil, pendingAcceptedQuests)
                    if chg then anyChanged = true end
                end
            end
            if not anyChanged then return end
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

local function alt_display_name(alt, guid)
    if type(alt) ~= "table" then return "" end
    if not sfui.isRetail then
        local disp = (sfui.alts and sfui.alts.GetDisplayName and sfui.alts.GetDisplayName(alt, guid)) or alt.name or ""
        local resolved = resolve_forever_name(disp, alt.surname, guid)
        if resolved and resolved ~= "" then
            return resolved
        end
    end
    return short_name(alt.name or "")
end

local function format_colored_char_name(alt, fallbackName, guid)
    local rawName = alt_display_name(alt, guid)
    if rawName == "" then
        rawName = fallbackName or "?"
    end
    local cleanName = short_name(rawName):lower()
    local classToken = alt and alt.class
    if classToken and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classToken] then
        local c = _G.RAID_CLASS_COLORS[classToken]
        local hex = c.colorStr or string.format("ff%02x%02x%02x", math.floor((c.r or 1) * 255), math.floor((c.g or 1) * 255), math.floor((c.b or 1) * 255))
        return "|c" .. hex .. cleanName .. "|r"
    end
    return cleanName
end

notify_peer_quest_completed = function(sender, guid, completedEvents)
    if type(completedEvents) ~= "table" or #completedEvents == 0 then return end
    local s = sync.GetSettings()
    if not s or not s.enabled or s.mbAutoQuest == false then return end
    if sync.IsAway and sync.IsAway() then return end

    local alt = (SfuiDB and type(SfuiDB.alts) == "table" and guid) and SfuiDB.alts[guid] or nil
    local coloredPeer = format_colored_char_name(alt, sender, guid)
    local myGUID = (sfui.alts and sfui.alts.GetCurrentCharacterGUID and sfui.alts.GetCurrentCharacterGUID())
        or (UnitGUID and UnitGUID("player"))
    local myAlt = (SfuiDB and type(SfuiDB.alts) == "table" and myGUID and not issecretvalue(myGUID)) and SfuiDB.alts[myGUID] or nil
    local anyNotified = false

    for _, ev in ipairs(completedEvents) do
        local qID = tonumber(ev and ev.id)
        local title = ev and ev.title
        if qID and type(title) == "string" and title ~= "" then
            local suppress = false
            if ev.kind == "turnin" then
                if pendingTurnedInQuests[qID]
                    or (myAlt and myAlt.completedQuests and myAlt.completedQuests[qID] == 1)
                    or (_G.C_QuestLog and _G.C_QuestLog.IsQuestFlaggedCompleted and _G.C_QuestLog.IsQuestFlaggedCompleted(qID))
                    or (sfui.common and sfui.common.is_quest_completed and sfui.common.is_quest_completed(qID)) then
                    suppress = true
                end
            end
            if not suppress then
                local action = (ev.kind == "turnin") and "turned in quest" or "completed quest"
                local msg = string_format("%s %s: |cffffd100%s|r", coloredPeer, action, string_lower(title))
                if _G.UIErrorsFrame and _G.UIErrorsFrame.AddMessage then
                    _G.UIErrorsFrame:AddMessage(msg, 0.25, 1.0, 0.45, 1.0)
                end
                if sfui.common and sfui.common.print then
                    sfui.common.print("sync: " .. msg)
                end
                anyNotified = true
            end
        end
    end

    if anyNotified and (not sync.IsLead or sync.IsLead()) and _G.PlaySound then
        _G.PlaySound((_G.SOUNDKIT and _G.SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01) or 6199, "Master")
    end
end

local cachedPartyGuidMap = {}
local cachedPartyNameMap = {}
local partyMapCacheTime = 0

local function build_party_guid_and_name_maps()
    local now = (GetTime and GetTime()) or 0
    if partyMapCacheTime > 0 and (now - partyMapCacheTime) < 1.0 then
        return cachedPartyGuidMap, cachedPartyNameMap
    end
    partyMapCacheTime = now
    wipe(cachedPartyGuidMap)
    wipe(cachedPartyNameMap)
    if not (IsInGroup and IsInGroup()) then
        return cachedPartyGuidMap, cachedPartyNameMap
    end
    local safeUnitIsUnit = sfui.safety and sfui.safety.SafeUnitIsUnit
    local isRaid = IsInRaid and IsInRaid()
    local count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    local prefix = isRaid and "raid" or "party"
    local maxIdx = isRaid and count or math.min(4, count)
    for i = 1, maxIdx do
        local u = prefix .. i
        local isSelf = (safeUnitIsUnit and safeUnitIsUnit(u, "player"))
            or (not (_G.C_Secrets and _G.C_Secrets.ShouldUnitComparisonBeSecret and _G.C_Secrets.ShouldUnitComparisonBeSecret(u, "player")) and _G.UnitIsUnit and _G.UnitIsUnit(u, "player"))
        if UnitExists and UnitExists(u) and not isSelf then
            local g = UnitGUID and UnitGUID(u)
            local full = sync.FullName(u)
            local n = UnitName and UnitName(u)
            if g and not issecretvalue(g) then
                cachedPartyGuidMap[g] = u
            end
            if full and not issecretvalue(full) and full ~= "" then
                cachedPartyNameMap[short_name(full):lower()] = u
            end
            if n and not issecretvalue(n) and n ~= "" then
                cachedPartyNameMap[short_name(n):lower()] = u
            end
        end
    end
    return cachedPartyGuidMap, cachedPartyNameMap
end

local function is_alt_quest_done(alt, questID)
    if not alt then return false end
    local cq = alt.completedQuests and alt.completedQuests[questID]
    if cq ~= nil and cq ~= false and cq ~= 0 then
        return true
    end
    return (alt.djQuests and alt.djQuests[questID] == 2) or false
end

local function is_party_unit_on_quest(partyUnit, questID)
    if type(partyUnit) ~= "string" or partyUnit == "" or not questID then
        return false
    end
    local C_QuestLog = _G.C_QuestLog
    if UnitExists and UnitExists(partyUnit) and C_QuestLog and C_QuestLog.IsUnitOnQuest then
        local onQ = C_QuestLog.IsUnitOnQuest(partyUnit, questID)
        if not issecretvalue(onQ) and onQ == true then
            return true
        end
    end
    return false
end

local function is_objective_text_finished(txt, isFinFlag)
    if isFinFlag == 1 or isFinFlag == true then return true end
    if type(txt) ~= "string" then return false end
    local cur, max = string_match(txt, "(%d+)%s*/%s*(%d+)")
    if cur and max then
        local nCur, nMax = tonumber(cur), tonumber(max)
        if nCur and nMax and nMax > 0 and nCur >= nMax then
            return true
        end
    end
    return false
end

local function has_objective_text_progress(txt, isFinFlag)
    if is_objective_text_finished(txt, isFinFlag) then return true end
    if type(txt) ~= "string" then return false end
    local cur = string_match(txt, "(%d+)%s*/%s*%d+")
    if cur and (tonumber(cur) or 0) > 0 then
        return true
    end
    local pct = string_match(txt, "(%d+)%%")
    if pct and (tonumber(pct) or 0) > 0 then
        return true
    end
    return false
end

local function is_synced_alt_party_or_online(guid, alt, s, partyGUIDs, partyNames, liveMap, firstNameCounts)
    if type(alt) ~= "table" then return false, false, "", nil end
    -- Another alt on the local account cannot be online/in-party while we are logged into myGUID
    if s and s.accountID and s.accountID ~= "" and alt.accountID and alt.accountID == s.accountID then
        local cleanName = alt_display_name(alt, guid):lower()
        return false, false, cleanName, nil
    end
    local cleanName = alt_display_name(alt, guid):lower()
    if cleanName == "" then return false, false, "", nil end
    local firstOnly = short_name(alt.name or ""):lower()
    if firstOnly == "" then
        firstOnly = string_match(cleanName, "^(%S+)") or cleanName
    end
    local allowFirstFallback = (firstOnly ~= "") and (
        cleanName == firstOnly
        or not firstNameCounts
        or (firstNameCounts[firstOnly] or 0) <= 1
    )
    local partyUnit = (type(partyGUIDs[guid]) == "string" and partyGUIDs[guid])
        or (type(partyNames[cleanName]) == "string" and partyNames[cleanName])
        or (allowFirstFallback and type(partyNames[firstOnly]) == "string" and partyNames[firstOnly])
        or nil
    local inParty = (partyUnit ~= nil)
        or (partyGUIDs[guid] ~= nil)
        or (partyNames[cleanName] ~= nil)
        or (allowFirstFallback and partyNames[firstOnly] ~= nil)
    local isOnline = inParty
        or (liveMap[cleanName] ~= nil)
        or (allowFirstFallback and liveMap[firstOnly] ~= nil)
    return inParty, isOnline, cleanName, partyUnit
end

local function is_better_alt_candidate(cand, existing, partyGUIDs)
    local candExact = (partyGUIDs and partyGUIDs[cand.guid] ~= nil) and true or false
    local exExact = (partyGUIDs and partyGUIDs[existing.guid] ~= nil) and true or false
    if candExact ~= exExact then return candExact end
    if cand.inParty ~= existing.inParty then return cand.inParty end
    if cand.isOnline ~= existing.isOnline then return cand.isOnline end
    local candQRev = tonumber(cand.alt.questsRev) or 0
    local exQRev = tonumber(existing.alt.questsRev) or 0
    if candQRev ~= exQRev then return candQRev > exQRev end
    local candUpd = tonumber(cand.alt.lastUpdate) or 0
    local exUpd = tonumber(existing.alt.lastUpdate) or 0
    if candUpd ~= exUpd then return candUpd > exUpd end
    local candHasQ = (type(cand.alt.activeQuests) == "table" and next(cand.alt.activeQuests) ~= nil)
    local exHasQ = (type(existing.alt.activeQuests) == "table" and next(existing.alt.activeQuests) ~= nil)
    if candHasQ ~= exHasQ then return candHasQ end
    return false
end

local function collect_deduped_synced_alts(s, partyGUIDs, partyNames, liveMap, requireActiveOnly)
    local myGUID = (sfui.alts and sfui.alts.GetCurrentCharacterGUID and sfui.alts.GetCurrentCharacterGUID())
        or (UnitGUID and UnitGUID("player"))
    if issecretvalue(myGUID) then myGUID = nil end

    local firstNameCounts = {}
    local seenCleanByFirst = {}
    for guid, alt in pairs(SfuiDB.alts) do
        if guid ~= myGUID and type(alt) == "table" then
            if not (s and s.accountID and s.accountID ~= "" and alt.accountID and alt.accountID == s.accountID) then
                local cleanName = alt_display_name(alt, guid):lower()
                if cleanName ~= "" then
                    local firstOnly = short_name(alt.name or ""):lower()
                    if firstOnly == "" then
                        firstOnly = string_match(cleanName, "^(%S+)") or cleanName
                    end
                    if firstOnly ~= "" then
                        local byClean = seenCleanByFirst[firstOnly]
                        if not byClean then
                            byClean = {}
                            seenCleanByFirst[firstOnly] = byClean
                        end
                        if not byClean[cleanName] then
                            byClean[cleanName] = true
                            firstNameCounts[firstOnly] = (firstNameCounts[firstOnly] or 0) + 1
                        end
                    end
                end
            end
        end
    end

    local byName = {}
    for guid, alt in pairs(SfuiDB.alts) do
        if guid ~= myGUID and type(alt) == "table" then
            local hasQuestTables = false
            if requireActiveOnly then
                hasQuestTables = (type(alt.activeQuests) == "table" or type(alt.completedQuests) == "table")
            else
                hasQuestTables = (type(alt.activeQuests) == "table" or type(alt.completedQuests) == "table" or type(alt.djQuests) == "table")
            end
            if hasQuestTables then
                local inParty, isOnline, cleanName, partyUnit = is_synced_alt_party_or_online(
                    guid, alt, s, partyGUIDs, partyNames, liveMap, firstNameCounts
                )
                if cleanName ~= "" then
                    local cand = {
                        guid      = guid,
                        alt       = alt,
                        cleanName = cleanName,
                        inParty   = inParty,
                        isOnline  = isOnline,
                        partyUnit = partyUnit,
                    }
                    local prev = byName[cleanName]
                    if not prev or is_better_alt_candidate(cand, prev, partyGUIDs) then
                        byName[cleanName] = cand
                    end
                end
            end
        end
    end

    return byName
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
    local liveMap = build_live_online_map()
    local byName = collect_deduped_synced_alts(s, partyGUIDs, partyNames, liveMap, false)
    local missing = nil

    for cleanName, entry in pairs(byName) do
        if entry.inParty then
            local alt = entry.alt
            local guid = entry.guid
            local hasActive = (type(alt.activeQuests) == "table" and alt.activeQuests[questID] ~= nil)
                or (type(alt.djQuests) == "table" and alt.djQuests[questID] == 1)
                or is_party_unit_on_quest(entry.partyUnit, questID)
            local hasCompleted = is_alt_quest_done(alt, questID)
            if not hasActive and not hasCompleted then
                local colored = format_colored_char_name(alt, cleanName, guid)
                missing = missing or {}
                missing[#missing + 1] = colored
            end
        end
    end

    return missing
end

-- Returns an array of status tables for synced peers/alts:
-- { guid, name, coloredName, class, inParty, isOnline, status = "missing"|"active"|"ready"|"completed",
--   objs = { "4/10 ...", ... }, objFinished = { 0, 1, ... }, unfinishedObjs = { ... }, hasProgress = bool }
function sync.GetQuestPeerStatuses(questID, includeAllAlts)
    questID = tonumber(questID)
    if not questID then return nil end
    local s = sync.GetSettings()
    if not s.enabled or s.syncQuests == false then return nil end
    if not SfuiDB or type(SfuiDB.alts) ~= "table" then return nil end

    local partyGUIDs, partyNames = build_party_guid_and_name_maps()
    local liveMap = build_live_online_map()
    local byName = collect_deduped_synced_alts(s, partyGUIDs, partyNames, liveMap, false)
    local results = nil

    for cleanName, entry in pairs(byName) do
        local inParty = entry.inParty
        local isOnline = entry.isOnline
        if includeAllAlts or inParty or isOnline then
            local alt = entry.alt
            local guid = entry.guid
            local status = "missing"
            local objs = nil
            local objFinished = nil
            local unfinishedObjs = nil
            local hasProgress = false

            if is_alt_quest_done(alt, questID) then
                status = "completed"
                hasProgress = true
            elseif alt.activeQuests and alt.activeQuests[questID] then
                local qEntry = alt.activeQuests[questID]
                objs = qEntry.o
                objFinished = qEntry.f
                if qEntry.c == 1 then
                    status = "ready"
                    hasProgress = true
                else
                    status = "active"
                    if type(objs) == "table" and #objs > 0 then
                        for idx, oTxt in ipairs(objs) do
                            local finFlag = type(objFinished) == "table" and objFinished[idx] or nil
                            local isFin = is_objective_text_finished(oTxt, finFlag)
                            if has_objective_text_progress(oTxt, finFlag) then
                                hasProgress = true
                            end
                            if not isFin then
                                unfinishedObjs = unfinishedObjs or {}
                                unfinishedObjs[#unfinishedObjs + 1] = oTxt
                            end
                        end
                    end
                end
            elseif (alt.djQuests and alt.djQuests[questID] == 1) or is_party_unit_on_quest(entry.partyUnit, questID) then
                status = "active"
            end

            local colored = format_colored_char_name(alt, cleanName, guid)
            results = results or {}
            results[#results + 1] = {
                guid           = guid,
                name           = cleanName,
                coloredName    = colored,
                class          = alt.class,
                inParty        = inParty,
                isOnline       = isOnline,
                status         = status,
                objs           = objs,
                objFinished    = objFinished,
                unfinishedObjs = unfinishedObjs,
                hasProgress    = hasProgress,
            }
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

-- Returns active class quests (`qEntry.cl == 1`) held by online or in-party synced characters.
function sync.GetSyncedPeerClassQuests()
    local s = sync.GetSettings()
    if not s.enabled or s.syncQuests == false then return nil end
    if not SfuiDB or type(SfuiDB.alts) ~= "table" then return nil end

    local partyGUIDs, partyNames = build_party_guid_and_name_maps()
    local liveMap = build_live_online_map()
    local byName = collect_deduped_synced_alts(s, partyGUIDs, partyNames, liveMap, true)

    local activePeers = {}
    for cleanName, entry in pairs(byName) do
        if (entry.inParty or entry.isOnline) and type(entry.alt.activeQuests) == "table" then
            activePeers[#activePeers + 1] = {
                guid        = entry.guid,
                alt         = entry.alt,
                name        = cleanName,
                coloredName = format_colored_char_name(entry.alt, cleanName, entry.guid),
                class       = entry.alt.class,
                inParty     = entry.inParty,
                isOnline    = entry.isOnline,
                partyUnit   = entry.partyUnit,
            }
        end
    end

    if #activePeers == 0 then return nil end
    table.sort(activePeers, function(a, b)
        if a.inParty ~= b.inParty then return a.inParty end
        return (a.name or "") < (b.name or "")
    end)

    local questsByKey = {}
    local questOrder = {}

    for _, p in ipairs(activePeers) do
        local classToken = p.class or "UNKNOWN"
        for rawQID, qEntry in pairs(p.alt.activeQuests) do
            local qID = tonumber(rawQID)
            if qID and type(qEntry) == "table" and qEntry.cl == 1 then
                local mapKey = classToken .. ":" .. tostring(qID)
                local qGroup = questsByKey[mapKey]
                if not qGroup then
                    qGroup = {
                        questID            = qID,
                        title              = qEntry.t or ("Quest " .. tostring(qID)),
                        level              = tonumber(qEntry.l) or 0,
                        suggestedGroup     = tonumber(qEntry.g) or 1,
                        classToken         = classToken,
                        hasProgress        = false,
                        hasIncompletePeers = false,
                        peerObjLines       = nil,
                        objByKey           = nil,
                        readyPeers         = nil,
                    }
                    questsByKey[mapKey] = qGroup
                    questOrder[#questOrder + 1] = qGroup
                else
                    if (not qGroup.title or qGroup.title == "") and qEntry.t then
                        qGroup.title = qEntry.t
                    end
                    if qGroup.level == 0 and tonumber(qEntry.l) and tonumber(qEntry.l) > 0 then
                        qGroup.level = tonumber(qEntry.l)
                    end
                    if qGroup.suggestedGroup <= 1 and tonumber(qEntry.g) and tonumber(qEntry.g) > 1 then
                        qGroup.suggestedGroup = tonumber(qEntry.g)
                    end
                end

                local pLabel = p.coloredName or p.name or "?"
                if qEntry.c == 1 then
                    qGroup.hasProgress = true
                    qGroup.readyPeers = qGroup.readyPeers or {}
                    qGroup.readyPeers[#qGroup.readyPeers + 1] = pLabel
                else
                    qGroup.hasIncompletePeers = true
                    local objs = qEntry.o
                    local objFin = qEntry.f
                    local addedAnyObj = false
                    if type(objs) == "table" and #objs > 0 then
                        for idx, oTxt in ipairs(objs) do
                            local finFlag = type(objFin) == "table" and objFin[idx] or nil
                            local isFin = is_objective_text_finished(oTxt, finFlag)
                            if has_objective_text_progress(oTxt, finFlag) then
                                qGroup.hasProgress = true
                            end
                            if not isFin then
                                local clean = tostring(oTxt or ""):gsub(" / ", "/")
                                if clean ~= "" then
                                    addedAnyObj = true
                                    local oKey = clean:lower()
                                    qGroup.peerObjLines = qGroup.peerObjLines or {}
                                    qGroup.objByKey = qGroup.objByKey or {}
                                    local entry = qGroup.objByKey[oKey]
                                    if not entry then
                                        entry = {
                                            text  = clean,
                                            names = { pLabel },
                                        }
                                        qGroup.objByKey[oKey] = entry
                                        qGroup.peerObjLines[#qGroup.peerObjLines + 1] = entry
                                    else
                                        entry.names[#entry.names + 1] = pLabel
                                    end
                                end
                            end
                        end
                    end
                    if not addedAnyObj then
                        local oKey = "in progress"
                        qGroup.peerObjLines = qGroup.peerObjLines or {}
                        qGroup.objByKey = qGroup.objByKey or {}
                        local entry = qGroup.objByKey[oKey]
                        if not entry then
                            entry = {
                                text  = "in progress",
                                names = { pLabel },
                            }
                            qGroup.objByKey[oKey] = entry
                            qGroup.peerObjLines[#qGroup.peerObjLines + 1] = entry
                        else
                            entry.names[#entry.names + 1] = pLabel
                        end
                    end
                end
            end
        end
    end

    if #questOrder == 0 then return nil end

    -- Check if any same-class synced party peer is missing a class quest held by another peer of that class
    for _, qGroup in ipairs(questOrder) do
        qGroup.objByKey = nil
        local missingPeers = nil
        for _, p in ipairs(activePeers) do
            if p.inParty and p.class == qGroup.classToken then
                local hasActive = (p.alt.activeQuests and p.alt.activeQuests[qGroup.questID] ~= nil)
                    or is_party_unit_on_quest(p.partyUnit, qGroup.questID)
                local hasCompleted = is_alt_quest_done(p.alt, qGroup.questID)
                if not hasActive and not hasCompleted then
                    missingPeers = missingPeers or {}
                    missingPeers[#missingPeers + 1] = p.coloredName or p.name
                end
            end
        end
        qGroup.missingPeers = missingPeers
        qGroup.hasMissingParty = (missingPeers ~= nil and #missingPeers > 0)
    end

    table.sort(questOrder, function(a, b)
        if a.classToken ~= b.classToken then
            return (a.classToken or "") < (b.classToken or "")
        end
        if a.level ~= b.level then
            return (a.level or 0) < (b.level or 0)
        end
        return (a.title or "") < (b.title or "")
    end)

    return questOrder
end

local function on_regen_enabled()
    if sync._pendingRemoteReload then
        local pendingSender = sync._pendingRemoteReload
        sync._pendingRemoteReload = false
        execute_local_reload(true, pendingSender)
        return
    end
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

    sync_machine_store()

    if not loginSynced then
        loginSynced = true
        if C_Timer and C_Timer.After then
            C_Timer.After(4.5, function()
                local s = sync.GetSettings()
                if s.enabled then
                    sync_machine_store()
                    if s.syncQuests ~= false and merge.ScanLocalQuestsAndDJ then
                        merge.ScanLocalQuestsAndDJ()
                    end
                    if s.autoSyncOnLogin then
                        local manifest = merge.BuildManifest(s)
                        sync.Broadcast("HELLO", manifest, true, true)
                    end
                    if sfui.tracker and sfui.tracker.RequestRefresh then
                        sfui.tracker.RequestRefresh(0.1)
                    end
                end
            end)
        end
    end
end

local groupRosterPending = false
local function on_group_roster_update()
    partyMapCacheTime = 0
    liveOnlineCacheTime = 0
    if sfui.tracker and sfui.tracker.RequestRefresh then
        sfui.tracker.RequestRefresh(0.1)
    end
    if not (codec and codec.ResolveGroupChannel and codec.ResolveGroupChannel()) then
        if codec and codec.PurgeGroupQueue then
            codec.PurgeGroupQueue()
        end
        return
    end
    if groupRosterPending then return end
    local s = sync.GetSettings()
    if not s.enabled or not s.useParty then return end
    local allowDiscovery = (s.passcode and s.passcode ~= "")
    if not get_active_group_channel(allowDiscovery) then return end
    groupRosterPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(3.0, function()
            groupRosterPending = false
            local ch = get_active_group_channel(allowDiscovery)
            if ch then
                if s.syncQuests ~= false and merge.ScanLocalQuestsAndDJ then
                    merge.ScanLocalQuestsAndDJ()
                end
                local manifest = merge.BuildManifest(s)
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

    local contactsCount = (merge and merge.GetContactsCounts and merge.GetContactsCounts()) or 0

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
local _syncDebug = {}
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

    _syncDebug.enabled         = s.enabled == true
    _syncDebug.accountLabel    = s.accountLabel or ""
    _syncDebug.peersCount      = counts.peers or 0
    _syncDebug.onlinePeers     = onlineCount
    _syncDebug.altsCount       = counts.alts or 0
    _syncDebug.remoteAltsCount = counts.remoteAlts or 0
    _syncDebug.recipesCount    = counts.recipes or 0
    _syncDebug.contactsCount   = counts.contacts or 0
    _syncDebug.fishCount       = counts.fish or 0
    _syncDebug.queueSize       = qLen
    _syncDebug.tickerActive    = tickerActive
    _syncDebug.reassemblyCount = reassemblyCount
    _syncDebug.packetsSent     = (sync.stats and sync.stats.packetsSent) or 0
    _syncDebug.packetsReceived = (sync.stats and sync.stats.packetsReceived) or 0
    _syncDebug.bytesSent       = (sync.stats and sync.stats.bytesSent) or 0
    _syncDebug.bytesReceived   = (sync.stats and sync.stats.bytesReceived) or 0
    _syncDebug.lastSyncTime    = (sync.stats and sync.stats.lastSyncTime) or 0
    _syncDebug.lastPeer        = (sync.stats and sync.stats.lastPeer) or nil
    return _syncDebug
end

function sync:OnInit()
    sync.GetSettings()
end

function sync:OnEnable()
    on_entering_world()
end

function sync:OnSettingsChanged(key, value)
    if SHARED_KEY_LOOKUP[key] and not sync._applyingRemoteSettings then
        sync.BroadcastSettingsNow()
    end
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_SYNC_STATUS_UPDATED", key, value)
    end
end

sync.GetDebugInfo = sfui.sync_debug_info

function sync.GetPeerWishlistOwners(itemID)
    local id = tonumber(itemID)
    if not id or not SfuiDB or not SfuiDB.dungeonjournal or type(SfuiDB.dungeonjournal.charWishlist) ~= "table" then
        return nil
    end
    local myGUID = _G.UnitGUID and _G.UnitGUID("player")
    local peersTbl = SfuiDB.sync and SfuiDB.sync.peers
    local out = nil
    local seen = {}
    for guid, charMap in pairs(SfuiDB.dungeonjournal.charWishlist) do
        if guid ~= myGUID and type(charMap) == "table" and charMap[id] == true then
            local alt = SfuiDB.alts and SfuiDB.alts[guid]
            -- Only return peers NOT already surfaced by local SfuiDB.alts (or surface peer entries)
            if not alt and type(peersTbl) == "table" then
                for peerKey, p in pairs(peersTbl) do
                    if type(p) == "table" and p.guid == guid then
                        local raw = p.name or peerKey
                        local clean = (tostring(raw):match("^([^%-]+)") or tostring(raw)):lower()
                        if clean ~= "" and not seen[clean] then
                            seen[clean] = true
                            local colored = (common and common.class_color_name and p.class and common.class_color_name(clean, p.class)) or clean
                            out = out or {}
                            out[#out + 1] = colored
                        end
                        break
                    end
                end
            end
        end
    end
    return out
end

function sync.IsItemWishlistedByChar(itemID, targetGUID, targetName)
    local id = tonumber(itemID)
    if not id or not SfuiDB or not SfuiDB.dungeonjournal or type(SfuiDB.dungeonjournal.charWishlist) ~= "table" then
        return false
    end
    local cw = SfuiDB.dungeonjournal.charWishlist
    if targetGUID and cw[targetGUID] and cw[targetGUID][id] == true then
        return true
    end
    if targetName and targetName ~= "" then
        local shortTarget = (tostring(targetName):match("^([^%-]+)") or tostring(targetName)):lower()
        for guid, charMap in pairs(cw) do
            if type(charMap) == "table" and charMap[id] == true then
                local alt = SfuiDB.alts and SfuiDB.alts[guid]
                local sameRuleset = not alt or not (sfui.alts and sfui.alts.IsSameRuleset) or sfui.alts.IsSameRuleset(alt, guid)
                if sameRuleset then
                    local aName = alt and alt.name and (tostring(alt.name):match("^([^%-]+)") or tostring(alt.name)):lower()
                    if aName and aName == shortTarget then
                        return true
                    end
                end
            end
        end
    end
    return false
end

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
    sfui.events.RegisterEvent("QUEST_WATCH_LIST_CHANGED", on_local_quests_updated)
    sfui.events.RegisterEvent("QUEST_LOG_CRITERIA_UPDATE", on_local_quests_updated)
    sfui.events.RegisterEvent("UNIT_QUEST_LOG_CHANGED", on_local_quests_updated)
    sfui.events.RegisterEvent("QUEST_LOG_UPDATE", on_local_quests_updated)
end

if sfui.events and sfui.events.RegisterMessage then
    sfui.events.RegisterMessage("SFUI_ALT_SYNCED", on_local_alt_synced)
    sfui.events.RegisterMessage("SFUI_RECIPE_KNOWN_UPDATED", on_local_recipe_updated)
    sfui.events.RegisterMessage("SFUI_RECIPE_BATCH_UPDATED", on_local_recipe_batch_updated)
    sfui.events.RegisterMessage("SFUI_CONTACTS_UPDATED", on_local_contacts_updated)
    sfui.events.RegisterMessage("SFUI_FISHING_CATCH_RECORDED", on_local_fishing_catch_recorded)
    sfui.events.RegisterMessage("SFUI_FISHING_GETAWAY_RECORDED", on_local_fishing_updated)
    sfui.events.RegisterMessage("SFUI_DJ_WISHLIST_UPDATED", on_local_dj_wishlist_updated)
    sfui.events.RegisterMessage("SFUI_WAYPOINT_SET", on_local_waypoint_set)
end
