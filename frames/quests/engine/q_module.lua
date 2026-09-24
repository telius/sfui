local addonName, addon = ...
sfui = sfui or {}
sfui.tracker = sfui.tracker or {}
sfui.tracker.modules = {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/quests/engine/module.lua
--  Unified Objective Tracker Module Protocol & Registration System
-- ══════════════════════════════════════════════════════════════════════════════

local _G = _G
local table_insert, table_sort = _G.table.insert, _G.table.sort
local ipairs, pairs, type = _G.ipairs, _G.pairs, _G.type

--- Base Module Mixin defining the lifecycle and contract for tracker modules
local ModuleMixin = {}

function ModuleMixin:MarkDirty(delay)
    self.isDirty = true
    if sfui.tracker and sfui.tracker.RequestRefresh then
        sfui.tracker.RequestRefresh(delay)
    end
end

function ModuleMixin:IsDirty()
    return self.isDirty
end

function ModuleMixin:ClearDirty()
    self.isDirty = false
end

function ModuleMixin:IsEnabled()
    if self.enabled ~= nil then return self.enabled end
    return true
end

function ModuleMixin:SetEnabled(enabled)
    self.enabled = (enabled ~= false)
    self:MarkDirty()
end

--- Register a content module with the tracker engine
--- @param moduleDef table Module definition conforming to ModuleMixin contract
function sfui.tracker.RegisterModule(moduleDef)
    if not moduleDef or type(moduleDef) ~= "table" then return end
    if not moduleDef.id then
        error("sfui.tracker.RegisterModule: Module definition requires a unique 'id'")
        return
    end

    -- Inherit base mixin
    for k, v in pairs(ModuleMixin) do
        if moduleDef[k] == nil then
            moduleDef[k] = v
        end
    end

    moduleDef.order = moduleDef.order or moduleDef.priority or 100
    moduleDef.isDirty = true

    -- Insert into module list
    local existingIndex = nil
    for i, m in ipairs(sfui.tracker.modules) do
        if m.id == moduleDef.id then
            existingIndex = i
            break
        end
    end

    if existingIndex then
        sfui.tracker.modules[existingIndex] = moduleDef
    else
        table_insert(sfui.tracker.modules, moduleDef)
    end

    -- Sort modules by display order
    table_sort(sfui.tracker.modules, function(a, b)
        return (a.order or 100) < (b.order or 100)
    end)

    -- Register Blizzard events declared by the module
    if moduleDef.events and sfui.events and sfui.events.RegisterEvent then
        for _, event in ipairs(moduleDef.events) do
            sfui.events.RegisterEvent(event, function(ev, ...)
                if moduleDef.OnEvent then
                    moduleDef:OnEvent(ev, ...)
                else
                    moduleDef:MarkDirty()
                end
            end)
        end
    end

    -- One-time initialization if tracker is already live
    if sfui.tracker.isInitialized and moduleDef.Init and not moduleDef._initialized then
        moduleDef._initialized = true
        moduleDef:Init(sfui.tracker)
    end

    return moduleDef
end

--- Retrieve a registered module by its ID
--- @param id string
--- @return table|nil
function sfui.tracker.GetModule(id)
    for _, m in ipairs(sfui.tracker.modules) do
        if m.id == id then return m end
    end
    return nil
end

--- Initialize all registered modules
function sfui.tracker.InitModules()
    for _, m in ipairs(sfui.tracker.modules) do
        if m.Init and not m._initialized then
            m._initialized = true
            m:Init(sfui.tracker)
        end
    end
end
