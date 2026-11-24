local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.sync = sfui.sync or {}
sfui.sync.codec = sfui.sync.codec or {}

local codec = sfui.sync.codec

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/sync/codec.lua
--  Safe, Zero-Loadstring Table Serializer, Chunker & Throttled Transport Queue
--  Compatible with Retail (12.1.0+) and Camelot / Classic Forever (1.60.1+)
-- ══════════════════════════════════════════════════════════════════════════════

local type = _G.type
local pairs = _G.pairs
local tostring = _G.tostring
local tonumber = _G.tonumber
local table_insert = table.insert
local table_concat = table.concat
local table_remove = table.remove
local string_sub = string.sub
local string_find = string.find
local string_len = string.len
local string_format = string.format
local math_ceil = math.ceil
local math_min = math.min
local GetTime = _G.GetTime
local C_ChatInfo = _G.C_ChatInfo
local SendAddonMessageFallback = _G.SendAddonMessage
local C_BattleNet = _G.C_BattleNet
local BNSendGameData = _G.BNSendGameData

local MAX_CHUNK_BYTES    = 225
local SEND_INTERVAL      = 0.16 -- ~6.25 packets/sec (stays well below WoW addon throttle)
local REASSEMBLY_TTL     = 60   -- seconds before stale partial buffers expire
local MAX_THROTTLE_RETRIES = 25

local HIGH_PRIORITY_MSG_TYPES = {
    DELTA_QUEST_PROG    = true,
    DATA_ACTIVE_QUESTS  = true,
    QUEST_DIGEST        = true,
    DELTA_HUD_STATS     = true,
    DELTA_DIALOG        = true,
    DELTA_WAYPOINT      = true,
    DELTA_QUEST_ABANDON = true,
    WANT                = true,
}

local COALESCABLE_SINGLETON_TYPES = {
    HELLO                 = true,
    DELTA_HUD_STATS       = true,
    DELTA_TRACKED_SKILLS  = true,
    DELTA_PINNED_RECIPES  = true,
    DATA_CONTACTS         = true,
    DATA_MAIL             = true,
    DATA_DJ_WISHLIST      = true,
}

local CompressionMethod = _G.Enum and _G.Enum.CompressionMethod
local CompressionLevel  = _G.Enum and _G.Enum.CompressionLevel
local Base64Variant     = _G.Enum and _G.Enum.Base64Variant
local DEFLATE_METHOD    = (CompressionMethod and CompressionMethod.Deflate) or 0
local COMP_LEVEL        = (CompressionLevel and CompressionLevel.Default) or 0
local B64_STANDARD      = (Base64Variant and Base64Variant.Standard) or 0
local CBOR_OPTIONS      = { ignoreSerializationErrors = true }

local SendAddonMessageResult = _G.Enum and _G.Enum.SendAddonMessageResult
local RESULT_SUCCESS          = (SendAddonMessageResult and SendAddonMessageResult.Success) or 0
local RESULT_ADDON_THROTTLE   = (SendAddonMessageResult and SendAddonMessageResult.AddonMessageThrottle) or 3
local RESULT_CHANNEL_THROTTLE = (SendAddonMessageResult and SendAddonMessageResult.ChannelThrottle) or 8
local RESULT_LOCKDOWN         = (SendAddonMessageResult and SendAddonMessageResult.AddOnMessageLockdown) or 11
local TARGET_OFFLINE_RESULT   = (SendAddonMessageResult and SendAddonMessageResult.TargetOffline) or 12

local function is_retryable_result(res)
    return res == RESULT_ADDON_THROTTLE
        or res == RESULT_CHANNEL_THROTTLE
        or res == RESULT_LOCKDOWN
end

local function acquire_tbl()
    if sfui.pool and sfui.pool.acquire_table then
        return sfui.pool.acquire_table()
    end
    return {}
end

local function release_tbl(t)
    if sfui.pool and sfui.pool.release_table then
        sfui.pool.release_table(t)
    end
end

-- ── String Escaping (safe for SendAddonMessage & BNSendGameData) ──────────────
local function escape_string(s)
    s = s:gsub("~", "~~")
    s = s:gsub("%z", "~0")
    s = s:gsub("\n", "~n")
    s = s:gsub("\r", "~r")
    s = s:gsub("|", "~p")
    return s
end

local function unescape_string(s)
    s = s:gsub("~p", "|")
    s = s:gsub("~r", "\r")
    s = s:gsub("~n", "\n")
    s = s:gsub("~0", "\0")
    s = s:gsub("~~", "~")
    return s
end

-- ── Deterministic Safe Serializer ─────────────────────────────────────────────
local function serialize_value(val, out, visited)
    local t = type(val)
    if t == "nil" then
        table_insert(out, "Z")
    elseif t == "boolean" then
        table_insert(out, val and "T" or "F")
    elseif t == "number" then
        -- Guard against NaN / Inf
        if val ~= val or val == math.huge or val == -math.huge then
            table_insert(out, "N0;")
        else
            table_insert(out, "N")
            table_insert(out, tostring(val))
            table_insert(out, ";")
        end
    elseif t == "string" then
        local esc = escape_string(val)
        table_insert(out, "S")
        table_insert(out, tostring(string_len(esc)))
        table_insert(out, ":")
        table_insert(out, esc)
    elseif t == "table" then
        if visited[val] then
            table_insert(out, "Z")
            return
        end
        visited[val] = true
        table_insert(out, "{")
        for k, v in pairs(val) do
            local kt = type(k)
            local vt = type(v)
            if (kt == "string" or kt == "number" or kt == "boolean")
                and (vt == "string" or vt == "number" or vt == "boolean" or vt == "table") then
                serialize_value(k, out, visited)
                serialize_value(v, out, visited)
            end
        end
        table_insert(out, "}")
        visited[val] = nil
    else
        table_insert(out, "Z")
    end
end

function codec.Serialize(val)
    local out = acquire_tbl()
    local visited = acquire_tbl()
    serialize_value(val, out, visited)
    local res = table_concat(out)
    release_tbl(visited)
    release_tbl(out)
    return res
end

-- ── Safe Recursive-Descent Deserializer (Zero loadstring) ─────────────────────
local function deserialize_at(str, pos, len)
    if pos > len then return nil, pos end
    local tag = string_sub(str, pos, pos)
    pos = pos + 1

    if tag == "Z" then
        return nil, pos
    elseif tag == "T" then
        return true, pos
    elseif tag == "F" then
        return false, pos
    elseif tag == "N" then
        local semi = string_find(str, ";", pos, true)
        if not semi then return nil, len + 1 end
        local num = tonumber(string_sub(str, pos, semi - 1))
        return num or 0, semi + 1
    elseif tag == "S" then
        local colon = string_find(str, ":", pos, true)
        if not colon then return nil, len + 1 end
        local slen = tonumber(string_sub(str, pos, colon - 1))
        if not slen or slen < 0 then return nil, len + 1 end
        local startPos = colon + 1
        local endPos = startPos + slen - 1
        if endPos > len then return nil, len + 1 end
        local raw = string_sub(str, startPos, endPos)
        return unescape_string(raw), endPos + 1
    elseif tag == "{" then
        local tbl = {}
        while pos <= len do
            local nextChar = string_sub(str, pos, pos)
            if nextChar == "}" then
                return tbl, pos + 1
            end
            local k, nextPos = deserialize_at(str, pos, len)
            if nextPos > len then break end
            local v
            v, pos = deserialize_at(str, nextPos, len)
            if k ~= nil and v ~= nil then
                tbl[k] = v
            end
        end
        return tbl, pos
    end

    return nil, len + 1
end

function codec.Deserialize(str)
    if type(str) ~= "string" or str == "" then return nil end
    local val = deserialize_at(str, 1, string_len(str))
    return val
end

local function get_encoding_util()
    local eu = _G.C_EncodingUtil
    if type(eu) == "table"
        and eu.SerializeCBOR and eu.DeserializeCBOR
        and eu.CompressString and eu.DecompressString
        and eu.EncodeBase64 and eu.DecodeBase64 then
        return eu
    end
    return nil
end

function codec.EncodeEnvelope(msgType, dataTable)
    local env = acquire_tbl()
    env.t = msgType
    env.d = dataTable

    local eu = get_encoding_util()
    if eu then
        local cbor = eu.SerializeCBOR(env, CBOR_OPTIONS)
        if type(cbor) == "string" and cbor ~= "" then
            local compressed = eu.CompressString(cbor, DEFLATE_METHOD, COMP_LEVEL)
            if type(compressed) == "string" and compressed ~= "" then
                local b64 = eu.EncodeBase64(compressed, B64_STANDARD)
                if type(b64) == "string" and b64 ~= "" then
                    release_tbl(env)
                    return b64, true
                end
            end
        end
    end

    local payload = codec.Serialize(env)
    release_tbl(env)
    return payload, false
end

local function decode_compressed_envelope(b64Payload)
    if type(b64Payload) ~= "string" or b64Payload == "" then return nil end
    local eu = get_encoding_util()
    if not eu then return nil end
    local raw = eu.DecodeBase64(b64Payload, B64_STANDARD)
    if type(raw) ~= "string" or raw == "" then return nil end
    local inflated = eu.DecompressString(raw, DEFLATE_METHOD)
    if type(inflated) ~= "string" or inflated == "" then return nil end
    return eu.DeserializeCBOR(inflated)
end

-- ── Outbound Queue & Chunker ──────────────────────────────────────────────────
local highPriorityQueue = {}
local sendQueue = {}
local queueTickerActive = false
local lastSendTime = -SEND_INTERVAL
local throttleBackoffUntil = 0
local isFlushingQueue = false
local nextMsgSeq = 1
local reassemblyBuffers = {}
local recentWhispers = {}
local lastAnyWhisperTime = 0
local cancelMatchKeys = {}
local coalesceCounts = {}
local coalesceExpected = {}

local function release_packet(pkt)
    if not pkt then return end
    pkt._cKey        = nil
    pkt._msgSeq      = nil
    pkt._totalChunks = nil
    pkt._retries     = nil
    release_tbl(pkt)
end

local function remove_matching_packets(q, predicate)
    for i = #q, 1, -1 do
        local pkt = q[i]
        if pkt and predicate(pkt) then
            table_remove(q, i)
            release_packet(pkt)
        end
    end
end

local function for_each_name_key(name, fn)
    if type(name) ~= "string" then return false end
    local trimmed = name:match("^%s*(.-)%s*$")
    if not trimmed or trimmed == "" then return false end
    local lower = trimmed:lower()
    if fn(lower) then return true end
    local shortName = (sfui.common and sfui.common.short_name and sfui.common.short_name(lower))
        or lower:gsub("%-.+$", "")
    if shortName ~= "" and shortName ~= lower then
        if fn(shortName) then return true end
    end
    local firstWord = shortName:match("^(%S+)")
    if firstWord and firstWord ~= "" and firstWord ~= shortName and firstWord ~= lower then
        if fn(firstWord) then return true end
    end
    local firstToken = lower:match("^([^%s%-]+)")
    if firstToken and firstToken ~= "" and firstToken ~= firstWord and firstToken ~= shortName and firstToken ~= lower then
        if fn(firstToken) then return true end
    end
    return false
end

function codec.RecordWhisperTarget(target, aliasName)
    local now = (GetTime and GetTime()) or 0
    local recorded = false
    local function stamp(k)
        recentWhispers[k] = now
        recorded = true
        return false
    end
    if target then for_each_name_key(target, stamp) end
    if aliasName and aliasName ~= target then for_each_name_key(aliasName, stamp) end
    if recorded then
        lastAnyWhisperTime = now
    end
end

function codec.WasRecentlyWhispered(target, windowSec)
    local now = (GetTime and GetTime()) or 0
    local win = windowSec or 15
    return for_each_name_key(target, function(k)
        local ts = recentWhispers[k]
        return ts ~= nil and (now - ts) <= win
    end)
end

function codec.HadRecentWhisper(windowSec)
    if lastAnyWhisperTime <= 0 then return false end
    local now = (GetTime and GetTime()) or 0
    return (now - lastAnyWhisperTime) <= (windowSec or 15)
end

function codec.CancelWhispersToTarget(target)
    if type(target) ~= "string" or target == "" then return end
    for k in pairs(cancelMatchKeys) do cancelMatchKeys[k] = nil end
    local any = false
    for_each_name_key(target, function(k)
        cancelMatchKeys[k] = true
        any = true
        return false
    end)
    if not any then return end

    local function keyMatches(k)
        return cancelMatchKeys[k] == true
    end
    local function matchesWhisper(pkt)
        if pkt.channel ~= "WHISPER" then return false end
        if pkt.target and for_each_name_key(pkt.target, keyMatches) then
            return true
        end
        if pkt.alias and for_each_name_key(pkt.alias, keyMatches) then
            return true
        end
        return false
    end
    remove_matching_packets(highPriorityQueue, matchesWhisper)
    remove_matching_packets(sendQueue, matchesWhisper)
    for k in pairs(cancelMatchKeys) do cancelMatchKeys[k] = nil end
end

local IsInGroup = _G.IsInGroup
local IsInRaid = _G.IsInRaid
local IsInGuild = _G.IsInGuild
local GetNumGroupMembers = _G.GetNumGroupMembers
local UnitExists = _G.UnitExists
local UnitIsPlayer = _G.UnitIsPlayer
local UnitIsUnit = _G.UnitIsUnit
local LE_PARTY_CATEGORY_HOME = _G.LE_PARTY_CATEGORY_HOME or 1
local LE_PARTY_CATEGORY_INSTANCE = _G.LE_PARTY_CATEGORY_INSTANCE or 2

local function has_other_human_member(prefix, maxIdx)
    for i = 1, maxIdx do
        local u = prefix .. i
        if UnitExists and UnitExists(u)
            and (not UnitIsPlayer or UnitIsPlayer(u))
            and not (UnitIsUnit and UnitIsUnit(u, "player")) then
            return true
        end
    end
    return false
end

-- Returns the active valid group addon chat channel ("RAID", "PARTY", or "INSTANCE_CHAT"),
-- or nil when solo, in a pending invite, or in a companion/NPC-only scenario (Delve/Follower).
function codec.ResolveGroupChannel()
    if not IsInGroup or not IsInGroup() then return nil end

    -- 1. Home Raid
    if IsInRaid and IsInRaid(LE_PARTY_CATEGORY_HOME) then
        local n = (GetNumGroupMembers and GetNumGroupMembers(LE_PARTY_CATEGORY_HOME)) or 0
        if n > 1 and has_other_human_member("raid", n) then
            return "RAID"
        end
    end

    -- 2. Home Party
    if IsInGroup(LE_PARTY_CATEGORY_HOME) then
        local n = (GetNumGroupMembers and GetNumGroupMembers(LE_PARTY_CATEGORY_HOME)) or 0
        if n > 1 and has_other_human_member("party", math_min(4, n)) then
            return "PARTY"
        end
    end

    -- 3. Instance Group (LFD / LFR / Battleground / Brawl)
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        local n = (GetNumGroupMembers and GetNumGroupMembers(LE_PARTY_CATEGORY_INSTANCE)) or 0
        if n > 1 then
            local inInstRaid = IsInRaid and IsInRaid(LE_PARTY_CATEGORY_INSTANCE)
            local prefix = inInstRaid and "raid" or "party"
            local maxIdx = inInstRaid and n or math_min(4, n)
            if has_other_human_member(prefix, maxIdx) then
                return "INSTANCE_CHAT"
            end
        end
    end

    return nil
end

function codec.PurgeGroupQueue()
    local function isGroupPacket(pkt)
        return pkt.channel == "PARTY" or pkt.channel == "RAID" or pkt.channel == "INSTANCE_CHAT"
    end
    remove_matching_packets(highPriorityQueue, isGroupPacket)
    remove_matching_packets(sendQueue, isGroupPacket)
end

local function dispatch_raw_packet(pkt)
    if pkt.channel == "BNET" and pkt.bnetIDAccount then
        if C_BattleNet and C_BattleNet.SendGameData then
            local res = C_BattleNet.SendGameData(pkt.bnetIDAccount, pkt.prefix, pkt.text)
            if is_retryable_result(res) then
                return false, true
            end
            if res == TARGET_OFFLINE_RESULT then
                return false, false
            end
            return (res == nil or res == RESULT_SUCCESS or res == true), false
        elseif BNSendGameData then
            BNSendGameData(pkt.bnetIDAccount, pkt.prefix, pkt.text)
            return true, false
        end
        return false, false
    end

    if pkt.channel == "PARTY" or pkt.channel == "RAID" or pkt.channel == "INSTANCE_CHAT" then
        local liveCh = codec.ResolveGroupChannel()
        if not liveCh then
            codec.PurgeGroupQueue()
            return false, false
        end
        pkt.channel = liveCh
    elseif pkt.channel == "GUILD" then
        if not (IsInGuild and IsInGuild()) then
            return false, false
        end
    elseif pkt.channel == "WHISPER" and pkt.target then
        codec.RecordWhisperTarget(pkt.target, pkt.alias)
    end

    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        local res = C_ChatInfo.SendAddonMessage(pkt.prefix, pkt.text, pkt.channel, pkt.target)
        if is_retryable_result(res) then
            return false, true
        end
        if pkt.channel == "WHISPER" and res == TARGET_OFFLINE_RESULT then
            local targetName = pkt.target
            local aliasName = pkt.alias
            if targetName then
                codec.CancelWhispersToTarget(targetName)
            end
            if aliasName and aliasName ~= targetName then
                codec.CancelWhispersToTarget(aliasName)
            end
            if sfui.sync and sfui.sync.MarkPeerOffline then
                sfui.sync.MarkPeerOffline(aliasName or targetName)
            end
            return false, false
        end
        return (res == nil or res == RESULT_SUCCESS or res == true), false
    elseif SendAddonMessageFallback then
        local res = SendAddonMessageFallback(pkt.prefix, pkt.text, pkt.channel, pkt.target)
        return (res ~= false), false
    end

    return false, false
end

local function stop_queue_ticker()
    if queueTickerActive then
        if sfui.events and sfui.events.UnregisterUpdate then
            sfui.events.UnregisterUpdate("SfuiSyncCodecQueue")
        end
        queueTickerActive = false
    end
end

local function process_send_queue()
    if #highPriorityQueue == 0 and #sendQueue == 0 then
        stop_queue_ticker()
        return
    end

    local now = (GetTime and GetTime()) or 0
    if not isFlushingQueue and throttleBackoffUntil > now then
        return
    end

    local srcQueue = (#highPriorityQueue > 0) and highPriorityQueue or sendQueue
    local pkt = table_remove(srcQueue, 1)
    if pkt then
        local ok, shouldRetry = dispatch_raw_packet(pkt)
        if shouldRetry and not isFlushingQueue then
            local retries = (pkt._retries or 0) + 1
            if retries <= MAX_THROTTLE_RETRIES then
                pkt._retries = retries
                table_insert(srcQueue, 1, pkt)
                throttleBackoffUntil = now + math_min(2.0, 0.35 * retries)
                return
            end
        end
        if ok then
            throttleBackoffUntil = 0
            lastSendTime = now
            if sfui.sync and sfui.sync.stats then
                sfui.sync.stats.packetsSent = (sfui.sync.stats.packetsSent or 0) + 1
                sfui.sync.stats.bytesSent = (sfui.sync.stats.bytesSent or 0) + string_len(pkt.text or "")
            end
        end
        release_packet(pkt)
    end

    if #highPriorityQueue == 0 and #sendQueue == 0 then
        stop_queue_ticker()
    end
end

local function ensure_queue_ticker()
    if queueTickerActive then return end
    if sfui.events and sfui.events.RegisterUpdate then
        queueTickerActive = true
        sfui.events.RegisterUpdate("SfuiSyncCodecQueue", SEND_INTERVAL, process_send_queue)
    else
        -- Fallback bounded synchronous drain if event update scheduler is unavailable
        codec.FlushQueue()
    end
end

function codec.GetQueueLength()
    return #highPriorityQueue + #sendQueue
end

function codec.GetQueueStats()
    local reassemblyCount = 0
    for _ in pairs(reassemblyBuffers) do
        reassemblyCount = reassemblyCount + 1
    end
    return #highPriorityQueue + #sendQueue, queueTickerActive, reassemblyCount
end

function codec.FlushQueue()
    if isFlushingQueue then return end
    isFlushingQueue = true
    local maxSteps = #highPriorityQueue + #sendQueue + 4
    local steps = 0
    while (#highPriorityQueue > 0 or #sendQueue > 0) and steps < maxSteps do
        steps = steps + 1
        process_send_queue()
    end
    isFlushingQueue = false
end

function codec.GetCoalesceSubKey(msgType, dataTable)
    if COALESCABLE_SINGLETON_TYPES[msgType] then
        return ""
    end
    if (msgType == "DATA_ALT" or msgType == "DATA_QUESTS" or msgType == "DATA_ACTIVE_QUESTS")
        and type(dataTable) == "table" and type(dataTable.guid) == "string" and dataTable.guid ~= "" then
        return dataTable.guid
    end
    if msgType == "QUEST_DIGEST"
        and type(dataTable) == "table" and type(dataTable.g) == "string" and dataTable.g ~= "" then
        return dataTable.g
    end
    return nil
end

local function make_coalesce_key(msgType, subKey, channel, target, bnetIDAccount)
    if subKey == nil then return nil end
    local dest = (channel == "BNET" and tostring(bnetIDAccount or ""))
        or (type(target) == "string" and target:lower())
        or ""
    return tostring(msgType) .. ":" .. tostring(subKey) .. ":" .. tostring(channel or "") .. ":" .. dest
end

local function coalesce_unsent_in_queue(q, cKey)
    if not cKey or #q == 0 then return end
    for k in pairs(coalesceCounts) do coalesceCounts[k] = nil end
    for k in pairs(coalesceExpected) do coalesceExpected[k] = nil end

    for i = 1, #q do
        local pkt = q[i]
        if pkt and pkt._cKey == cKey and pkt._msgSeq then
            local seq = pkt._msgSeq
            coalesceCounts[seq] = (coalesceCounts[seq] or 0) + 1
            coalesceExpected[seq] = pkt._totalChunks or 1
        end
    end

    for i = #q, 1, -1 do
        local pkt = q[i]
        local seq = pkt and pkt._msgSeq
        if pkt and pkt._cKey == cKey and seq
            and coalesceCounts[seq] and coalesceCounts[seq] == coalesceExpected[seq] then
            table_remove(q, i)
            release_packet(pkt)
        end
    end

    for k in pairs(coalesceCounts) do coalesceCounts[k] = nil end
    for k in pairs(coalesceExpected) do coalesceExpected[k] = nil end
end

function codec.SendEncoded(prefix, msgType, payload, isCompressed, channel, target, bnetIDAccount, highPriority,
                           whisperAlias, coalesceSubKey)
    if type(payload) ~= "string" or payload == "" then return false end

    local wasEmpty = (#highPriorityQueue == 0 and #sendQueue == 0)
    local targetQueue = (highPriority == true or HIGH_PRIORITY_MSG_TYPES[msgType])
        and highPriorityQueue
        or sendQueue

    local cKey = make_coalesce_key(msgType, coalesceSubKey, channel, target, bnetIDAccount)
    if cKey then
        coalesce_unsent_in_queue(targetQueue, cKey)
    end

    local seqId = nextMsgSeq
    nextMsgSeq = (nextMsgSeq % 65535) + 1

    local totalLen = string_len(payload)
    if totalLen <= MAX_CHUNK_BYTES then
        local modePrefix = isCompressed and "2~" or "0~"
        local pkt = acquire_tbl()
        pkt.prefix        = prefix
        pkt.text          = modePrefix .. payload
        pkt.channel       = channel
        pkt.target        = target
        pkt.alias         = whisperAlias
        pkt.bnetIDAccount = bnetIDAccount
        pkt._retries      = nil
        pkt._cKey         = cKey
        pkt._msgSeq       = seqId
        pkt._totalChunks  = 1
        table_insert(targetQueue, pkt)
    else
        local msgID = string_format("%x", seqId)
        local chunkMode = isCompressed and "3~" or "1~"
        local totalChunks = math_ceil(totalLen / MAX_CHUNK_BYTES)
        for i = 1, totalChunks do
            local startIdx = (i - 1) * MAX_CHUNK_BYTES + 1
            local endIdx = math_min(i * MAX_CHUNK_BYTES, totalLen)
            local chunk = string_sub(payload, startIdx, endIdx)
            local header = string_format("%s%s~%d~%d~", chunkMode, msgID, i, totalChunks)
            local pkt = acquire_tbl()
            pkt.prefix        = prefix
            pkt.text          = header .. chunk
            pkt.channel       = channel
            pkt.target        = target
            pkt.alias         = whisperAlias
            pkt.bnetIDAccount = bnetIDAccount
            pkt._retries      = nil
            pkt._cKey         = cKey
            pkt._msgSeq       = seqId
            pkt._totalChunks  = totalChunks
            table_insert(targetQueue, pkt)
        end
    end

    local now = (GetTime and GetTime()) or 0
    if wasEmpty and (now - lastSendTime) >= SEND_INTERVAL then
        process_send_queue()
    end
    if #highPriorityQueue > 0 or #sendQueue > 0 then
        ensure_queue_ticker()
    end
    return true
end

function codec.SendMessage(prefix, msgType, dataTable, channel, target, bnetIDAccount, highPriority, whisperAlias)
    local payload, isCompressed = codec.EncodeEnvelope(msgType, dataTable)
    if not payload or payload == "" then return false end
    local subKey = codec.GetCoalesceSubKey(msgType, dataTable)
    return codec.SendEncoded(prefix, msgType, payload, isCompressed, channel, target, bnetIDAccount, highPriority,
        whisperAlias, subKey)
end

-- ── Inbound Chunk Reassembly ──────────────────────────────────────────────────
local function cleanup_expired_buffers(now)
    for key, buf in pairs(reassemblyBuffers) do
        if (now - (buf.created or 0)) > REASSEMBLY_TTL then
            reassemblyBuffers[key] = nil
            if buf.chunks then release_tbl(buf.chunks) end
            buf.compressed = nil
            release_tbl(buf)
        end
    end
end

function codec.FeedChunk(sender, rawText, channel)
    if type(rawText) ~= "string" or rawText == "" then return nil end

    if sfui.sync and sfui.sync.stats then
        sfui.sync.stats.packetsReceived = (sfui.sync.stats.packetsReceived or 0) + 1
        sfui.sync.stats.bytesReceived = (sfui.sync.stats.bytesReceived or 0) + string_len(rawText)
    end

    local mode = string_sub(rawText, 1, 2)
    if mode == "0~" or mode == "2~" then
        local payload = string_sub(rawText, 3)
        local decoded = (mode == "2~") and decode_compressed_envelope(payload) or codec.Deserialize(payload)
        if type(decoded) == "table" and decoded.t then
            return decoded.t, decoded.d
        end
        return nil
    elseif mode == "1~" or mode == "3~" then
        local isCompressed = (mode == "3~")
        local p1 = string_find(rawText, "~", 3, true)
        if not p1 then return nil end
        local p2 = string_find(rawText, "~", p1 + 1, true)
        if not p2 then return nil end
        local p3 = string_find(rawText, "~", p2 + 1, true)
        if not p3 then return nil end

        local msgID = string_sub(rawText, 3, p1 - 1)
        local idx = tonumber(string_sub(rawText, p1 + 1, p2 - 1))
        local total = tonumber(string_sub(rawText, p2 + 1, p3 - 1))
        local chunk = string_sub(rawText, p3 + 1)

        if not idx or not total or total < 1 or total > 512 or idx < 1 or idx > total then
            return nil
        end

        local now = (GetTime and GetTime()) or 0
        cleanup_expired_buffers(now)

        local chPrefix = (type(channel) == "string" and channel ~= "") and (channel .. ":") or ""
        local key = chPrefix .. (sender or "?") .. ":" .. msgID
        local buf = reassemblyBuffers[key]
        if not buf or buf.total ~= total or buf.compressed ~= isCompressed then
            if buf then
                if buf.chunks then release_tbl(buf.chunks) end
                buf.compressed = nil
                release_tbl(buf)
            end
            buf = acquire_tbl()
            buf.total      = total
            buf.received   = 0
            buf.chunks     = acquire_tbl()
            buf.created    = now
            buf.compressed = isCompressed
            reassemblyBuffers[key] = buf
        end

        if not buf.chunks[idx] then
            buf.chunks[idx] = chunk
            buf.received = buf.received + 1
        end

        if buf.received >= buf.total then
            reassemblyBuffers[key] = nil
            local fullPayload = table_concat(buf.chunks)
            local useCompressed = (buf.compressed == true)
            release_tbl(buf.chunks)
            buf.compressed = nil
            release_tbl(buf)
            local decoded = useCompressed and decode_compressed_envelope(fullPayload) or codec.Deserialize(fullPayload)
            if type(decoded) == "table" and decoded.t then
                return decoded.t, decoded.d
            end
        end
    end

    return nil
end

