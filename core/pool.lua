local addonName, addon = ...
sfui = sfui or {}
sfui.pool = sfui.pool or {}

local pool = sfui.pool

local _G = _G
local CreateFrame = _G.CreateFrame
local type = _G.type
local pairs = _G.pairs
local wipe = _G.wipe or table.wipe
local table_insert = table.insert
local math_max = math.max

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Table Object Pooling (Zero Heap Churn)
-- ─────────────────────────────────────────────────────────────────────────────
local tablePool = {}
local TABLE_POOL_MAX = 500

--- Acquire a clean table from the pool, or allocate a new empty table.
--- @return table
function pool.acquire_table()
    local n = #tablePool
    if n > 0 then
        local t = tablePool[n]
        tablePool[n] = nil
        return t
    end
    return {}
end

--- Return a table to the pool, wiping its contents.
--- @param tbl table|nil
--- @return nil
function pool.release_table(tbl)
    if type(tbl) ~= "table" then return end
    wipe(tbl)
    if #tablePool < TABLE_POOL_MAX then
        tablePool[#tablePool + 1] = tbl
    end
    return nil
end

--- Return a table and all nested tables to the pool.
--- @param tbl table|nil
--- @return nil
function pool.release_table_deep(tbl)
    if type(tbl) ~= "table" then return end
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            pool.release_table_deep(v)
        end
    end
    return pool.release_table(tbl)
end

--- Create an isolated table pool instance.
--- @param maxDepth number|nil
--- @return table
function pool.create_table_pool(maxDepth)
    local localPool = {}
    local maxCap = maxDepth or 200
    local p = {}

    function p:Acquire()
        local n = #localPool
        if n > 0 then
            local t = localPool[n]
            localPool[n] = nil
            return t
        end
        return {}
    end

    function p:Release(tbl)
        if type(tbl) ~= "table" then return end
        wipe(tbl)
        if #localPool < maxCap then
            localPool[#localPool + 1] = tbl
        end
    end

    function p:ReleaseDeep(tbl)
        if type(tbl) ~= "table" then return end
        for k, v in pairs(tbl) do
            if type(v) == "table" then
                p:ReleaseDeep(v)
            end
        end
        p:Release(tbl)
    end

    function p:Wipe()
        wipe(localPool)
    end

    function p:Count()
        return #localPool
    end

    return p
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Frame Pooling (Native Blizzard CreateFramePool with Robust Fallback)
-- ─────────────────────────────────────────────────────────────────────────────

local function DefaultResetter(p, frame)
    if not frame then return end
    frame:Hide()
    frame:ClearAllPoints()
end

--- Create a frame pool.
--- @param parent Frame|nil Parent frame
--- @param frameType string|nil Default "Frame"
--- @param template string|nil Optional template (e.g. "BackdropTemplate")
--- @param onReset function|nil Optional reset callback function(pool, frame)
--- @return table Pool object with Acquire, Release, ReleaseAll, EnumerateActive, GetNumActive
function pool.create_frame_pool(parent, frameType, template, onReset)
    frameType = frameType or "Frame"
    local resetter = onReset or DefaultResetter

    if _G.CreateFramePool then
        local nativePool = _G.CreateFramePool(frameType, parent, template, resetter)
        if nativePool and nativePool.Acquire then
            return nativePool
        end
    end

    -- Standalone Fallback Frame Pool
    local fallbackPool = {
        parent = parent,
        frameType = frameType,
        template = template,
        resetter = resetter,
        activeObjects = {},
        inactiveObjects = {},
        numActive = 0,
    }

    function fallbackPool:Acquire()
        local frame
        local isNew = false
        local nInactive = #self.inactiveObjects
        if nInactive > 0 then
            frame = self.inactiveObjects[nInactive]
            self.inactiveObjects[nInactive] = nil
        else
            frame = CreateFrame(self.frameType, nil, self.parent, self.template)
            isNew = true
        end

        self.activeObjects[frame] = true
        self.numActive = self.numActive + 1

        if self.resetter then
            self.resetter(self, frame)
        end

        return frame, isNew
    end

    function fallbackPool:Release(frame)
        if not frame or not self.activeObjects[frame] then return end

        self.activeObjects[frame] = nil
        self.numActive = math_max(0, self.numActive - 1)

        if self.resetter then
            self.resetter(self, frame)
        else
            frame:Hide()
            frame:ClearAllPoints()
        end

        table_insert(self.inactiveObjects, frame)
    end

    function fallbackPool:ReleaseAll()
        for frame in pairs(self.activeObjects) do
            if self.resetter then
                self.resetter(self, frame)
            else
                frame:Hide()
                frame:ClearAllPoints()
            end
            table_insert(self.inactiveObjects, frame)
        end
        wipe(self.activeObjects)
        self.numActive = 0
    end

    function fallbackPool:EnumerateActive()
        return pairs(self.activeObjects)
    end

    function fallbackPool:GetNumActive()
        return self.numActive
    end

    return fallbackPool
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Generic Object Pool (frames, textures, or custom factory objects)
-- ─────────────────────────────────────────────────────────────────────────────
local objectPoolMethods = {}
objectPoolMethods.__index = objectPoolMethods

function objectPoolMethods:acquire(...)
    local free = self._free
    local n = #free
    local obj, isNew
    if n > 0 then
        obj = free[n]
        free[n] = nil
    else
        obj = self._factory(...)
        isNew = true
    end
    self._active[obj] = true
    self._count = self._count + 1
    return obj, isNew
end

function objectPoolMethods:release(obj)
    if not obj or not self._active[obj] then return end
    self._active[obj] = nil
    self._count = self._count - 1
    local reset = self._reset
    if reset then
        reset(obj)
    elseif type(obj) == "table" and obj.Hide then
        obj:Hide()
    end
    self._free[#self._free + 1] = obj
end

function objectPoolMethods:release_all()
    for obj in pairs(self._active) do
        self:release(obj)
    end
end

function objectPoolMethods:active()
    return pairs(self._active)
end

function objectPoolMethods:num_active()
    return self._count
end

--- Create a custom factory-backed object pool (Acquire -> obj, isNew; release; release_all).
function pool.create_object_pool(factory, reset)
    return setmetatable({
        _factory = factory,
        _reset   = reset,
        _active  = {},
        _free    = {},
        _count   = 0,
    }, objectPoolMethods)
end
pool.create_pool = pool.create_object_pool

-- Export common aliases
sfui.common = sfui.common or {}
sfui.common.acquire_table = pool.acquire_table
sfui.common.release_table = pool.release_table
sfui.common.release_table_deep = pool.release_table_deep
sfui.common.create_frame_pool = pool.create_frame_pool
sfui.common.create_table_pool = pool.create_table_pool
sfui.common.create_object_pool = pool.create_object_pool
sfui.common.create_pool = pool.create_object_pool
