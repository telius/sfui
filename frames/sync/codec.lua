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
local C_Timer = _G.C_Timer
local C_ChatInfo = _G.C_ChatInfo
local SendAddonMessageFallback = _G.SendAddonMessage
local BNSendGameData = _G.BNSendGameData

local MAX_CHUNK_BYTES = 225
local SEND_INTERVAL   = 0.12 -- ~8.3 packets/sec (well below WoW chat throttle)
local REASSEMBLY_TTL  = 60   -- seconds before stale partial buffers expire

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

-- ── Outbound Queue & Chunker ──────────────────────────────────────────────────
local sendQueue = {}
local queueTicker = nil
local nextMsgSeq = 1
local reassemblyBuffers = {}
local recentWhispers = {}

local function normalize_short_lower(name)
    if type(name) ~= "string" then return nil end
    local lower = name:lower()
    return lower:match("^([^%-]+)") or lower, lower
end

function codec.RecordWhisperTarget(target)
    local shortName, fullName = normalize_short_lower(target)
    if not shortName then return end
    local now = (GetTime and GetTime()) or 0
    recentWhispers[shortName] = now
    recentWhispers[fullName] = now
end

function codec.WasRecentlyWhispered(target)
    local shortName, fullName = normalize_short_lower(target)
    if not shortName then return false end
    local now = (GetTime and GetTime()) or 0
    local ts = recentWhispers[fullName] or recentWhispers[shortName]
    if ts and (now - ts) <= 10 then
        return true
    end
    return false
end

function codec.CancelWhispersToTarget(target)
    local shortName, fullName = normalize_short_lower(target)
    if not shortName then return end
    for i = #sendQueue, 1, -1 do
        local pkt = sendQueue[i]
        if pkt and pkt.channel == "WHISPER" and pkt.target then
            local pShort, pFull = normalize_short_lower(pkt.target)
            if pShort == shortName or pFull == fullName then
                table_remove(sendQueue, i)
                release_tbl(pkt)
            end
        end
    end
end

local function dispatch_raw_packet(pkt)
    if pkt.channel == "BNET" and pkt.bnetIDAccount then
        if BNSendGameData then
            BNSendGameData(pkt.bnetIDAccount, pkt.prefix, pkt.text)
            return true
        end
        return false
    end

    if pkt.channel == "WHISPER" and pkt.target then
        codec.RecordWhisperTarget(pkt.target)
    end

    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(pkt.prefix, pkt.text, pkt.channel, pkt.target)
        return true
    elseif SendAddonMessageFallback then
        SendAddonMessageFallback(pkt.prefix, pkt.text, pkt.channel, pkt.target)
        return true
    end
    return false
end

local function process_send_queue()
    if #sendQueue == 0 then
        if queueTicker then
            queueTicker:Cancel()
            queueTicker = nil
        end
        return
    end

    local pkt = table_remove(sendQueue, 1)
    if pkt then
        local ok = dispatch_raw_packet(pkt)
        if ok and sfui.sync and sfui.sync.stats then
            sfui.sync.stats.packetsSent = (sfui.sync.stats.packetsSent or 0) + 1
            sfui.sync.stats.bytesSent = (sfui.sync.stats.bytesSent or 0) + string_len(pkt.text or "")
        end
        release_tbl(pkt)
    end

    if #sendQueue == 0 and queueTicker then
        queueTicker:Cancel()
        queueTicker = nil
    end
end

local function ensure_queue_ticker()
    if queueTicker then return end
    if C_Timer and C_Timer.NewTicker then
        queueTicker = C_Timer.NewTicker(SEND_INTERVAL, process_send_queue)
    else
        -- Fallback immediate drain if C_Timer is unavailable
        while #sendQueue > 0 do
            process_send_queue()
        end
    end
end

function codec.GetQueueLength()
    return #sendQueue
end

function codec.GetQueueStats()
    local reassemblyCount = 0
    for _ in pairs(reassemblyBuffers) do
        reassemblyCount = reassemblyCount + 1
    end
    return #sendQueue, queueTicker ~= nil, reassemblyCount
end

function codec.SendMessage(prefix, msgType, dataTable, channel, target, bnetIDAccount)
    local env = acquire_tbl()
    env.t = msgType
    env.d = dataTable
    local payload = codec.Serialize(env)
    release_tbl(env)
    if not payload or payload == "" then return false end

    local totalLen = string_len(payload)
    if totalLen <= MAX_CHUNK_BYTES then
        local pkt = acquire_tbl()
        pkt.prefix        = prefix
        pkt.text          = "0~" .. payload
        pkt.channel       = channel
        pkt.target        = target
        pkt.bnetIDAccount = bnetIDAccount
        table_insert(sendQueue, pkt)
    else
        local msgID = string_format("%x", nextMsgSeq)
        nextMsgSeq = (nextMsgSeq % 65535) + 1
        local totalChunks = math_ceil(totalLen / MAX_CHUNK_BYTES)
        for i = 1, totalChunks do
            local startIdx = (i - 1) * MAX_CHUNK_BYTES + 1
            local endIdx = math_min(i * MAX_CHUNK_BYTES, totalLen)
            local chunk = string_sub(payload, startIdx, endIdx)
            local header = string_format("1~%s~%d~%d~", msgID, i, totalChunks)
            local pkt = acquire_tbl()
            pkt.prefix        = prefix
            pkt.text          = header .. chunk
            pkt.channel       = channel
            pkt.target        = target
            pkt.bnetIDAccount = bnetIDAccount
            table_insert(sendQueue, pkt)
        end
    end

    ensure_queue_ticker()
    return true
end

-- ── Inbound Chunk Reassembly ──────────────────────────────────────────────────
local function cleanup_expired_buffers(now)
    for key, buf in pairs(reassemblyBuffers) do
        if (now - (buf.created or 0)) > REASSEMBLY_TTL then
            reassemblyBuffers[key] = nil
            if buf.chunks then release_tbl(buf.chunks) end
            release_tbl(buf)
        end
    end
end

function codec.FeedChunk(sender, rawText)
    if type(rawText) ~= "string" or rawText == "" then return nil end

    if sfui.sync and sfui.sync.stats then
        sfui.sync.stats.packetsReceived = (sfui.sync.stats.packetsReceived or 0) + 1
        sfui.sync.stats.bytesReceived = (sfui.sync.stats.bytesReceived or 0) + string_len(rawText)
    end

    local mode = string_sub(rawText, 1, 2)
    if mode == "0~" then
        local payload = string_sub(rawText, 3)
        local decoded = codec.Deserialize(payload)
        if type(decoded) == "table" and decoded.t then
            return decoded.t, decoded.d
        end
        return nil
    elseif mode == "1~" then
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

        local key = (sender or "?") .. ":" .. msgID
        local buf = reassemblyBuffers[key]
        if not buf or buf.total ~= total then
            if buf then
                if buf.chunks then release_tbl(buf.chunks) end
                release_tbl(buf)
            end
            buf = acquire_tbl()
            buf.total    = total
            buf.received = 0
            buf.chunks   = acquire_tbl()
            buf.created  = now
            reassemblyBuffers[key] = buf
        end

        if not buf.chunks[idx] then
            buf.chunks[idx] = chunk
            buf.received = buf.received + 1
        end

        if buf.received >= buf.total then
            reassemblyBuffers[key] = nil
            local fullPayload = table_concat(buf.chunks)
            release_tbl(buf.chunks)
            release_tbl(buf)
            local decoded = codec.Deserialize(fullPayload)
            if type(decoded) == "table" and decoded.t then
                return decoded.t, decoded.d
            end
        end
    end

    return nil
end

