local addonName, addon = ...
sfui = sfui or {}
sfui.actionbars = sfui.actionbars or {}
sfui.actionbars.paging = {}

local paging = sfui.actionbars.paging
local _G = _G
local UnitClass = _G.UnitClass
local select = _G.select
local table_insert = table.insert
local table_concat = table.concat
local RegisterStateDriver = _G.RegisterStateDriver

-- ─────────────────────────────────────────────────────────────────────────────
--  Paging Condition Generator for Bar 1
-- ─────────────────────────────────────────────────────────────────────────────
function paging.GetBar1Paging()
    local myClass = (sfui.common and sfui.common.get_player_class and sfui.common.get_player_class()) or select(2, UnitClass("player"))
    local conditions = {}

    -- 1. Override, Vehicle & Possess Bars
    if sfui.isRetail then
        table_insert(conditions, "[overridebar] 14")
        table_insert(conditions, "[vehicleui][possessbar] 12")
    else
        table_insert(conditions, "[possessbar] 12")
    end

    -- 2. Class-specific shapeshift & stance paging
    if myClass == "DRUID" then
        table_insert(conditions, "[bonusbar:1,nostealth] 7")
        table_insert(conditions, "[bonusbar:1,stealth] 8")
        table_insert(conditions, "[bonusbar:2] 10")
        table_insert(conditions, "[bonusbar:3] 9")
        table_insert(conditions, "[bonusbar:4] 10")
    elseif myClass == "ROGUE" then
        table_insert(conditions, "[bonusbar:1] 7")
        table_insert(conditions, "[bonusbar:2] 8")
    elseif myClass == "WARRIOR" then
        if not sfui.isRetail then
            table_insert(conditions, "[bonusbar:1] 7")
            table_insert(conditions, "[bonusbar:2] 8")
            table_insert(conditions, "[bonusbar:3] 9")
        end
    elseif myClass == "PRIEST" then
        if sfui.isRetail then
            table_insert(conditions, "[form:1, spec:3] 7")
            table_insert(conditions, "[bonusbar:1] 7")
        else
            table_insert(conditions, "[form:1] 7")
        end
    elseif myClass == "EVOKER" then
        table_insert(conditions, "[bonusbar:1] 7")
    elseif myClass == "MONK" then
        table_insert(conditions, "[bonusbar:1] 7")
        table_insert(conditions, "[bonusbar:2] 8")
    end

    -- 3. General bonusbar, shapeshift, and multi-bar switching
    table_insert(conditions, "[shapeshift] 13")
    table_insert(conditions, "[bar:2] 2")
    table_insert(conditions, "[bar:3] 3")
    table_insert(conditions, "[bar:4] 4")
    table_insert(conditions, "[bar:5] 5")
    table_insert(conditions, "[bar:6] 6")
    table_insert(conditions, "[bonusbar:5] 11")

    -- 4. Default state
    table_insert(conditions, "1")

    return table_concat(conditions, "; ")
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Apply Secure State Driver to Bar 1
-- ─────────────────────────────────────────────────────────────────────────────
function paging.SetupBar1Paging(bar)
    if not bar then return end

    bar:SetAttribute("_onstate-page", [[
        if newstate == 'possess' or newstate == '11' then
            if HasVehicleActionBar and HasVehicleActionBar() then
                newstate = GetVehicleBarIndex()
            elseif HasOverrideActionBar and HasOverrideActionBar() then
                newstate = GetOverrideBarIndex()
            elseif HasTempShapeshiftActionBar and HasTempShapeshiftActionBar() then
                newstate = GetTempShapeshiftBarIndex()
            elseif HasBonusActionBar and HasBonusActionBar() then
                newstate = GetBonusBarIndex()
            else
                newstate = 12
            end
        end

        self:SetAttribute("state", newstate)
        control:ChildUpdate("state", newstate)
    ]])

    local pageString = paging.GetBar1Paging()
    RegisterStateDriver(bar, "page", pageString)
    bar:SetAttribute("pageConditions", pageString)
end
