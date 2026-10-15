local addonName, addon = ...
sfui = sfui or {}
sfui.actionbars = sfui.actionbars or {}
sfui.actionbars.mouseover = {}

local mouseover = sfui.actionbars.mouseover
local _G = _G
local C_Timer = _G.C_Timer
local ipairs = _G.ipairs
local GetCursorInfo = _G.GetCursorInfo

mouseover.isDragging = false

local function get_mod_cfg()
    return (sfui.db and sfui.db.Get and sfui.db.Get("actionbars")) or (sfui.config and sfui.config.actionbars) or {}
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Hover Detection
-- ─────────────────────────────────────────────────────────────────────────────
function mouseover.IsBarHovered(bar)
    if not bar or not bar:IsShown() then return false end
    if bar:IsMouseOver() then return true end

    local buttons = bar.buttons
    if buttons then
        for i = 1, #buttons do
            local btn = buttons[i]
            if btn and btn:IsShown() and btn:IsMouseOver() then
                return true
            end
        end
    end

    return false
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Target Alpha Calculation
-- ─────────────────────────────────────────────────────────────────────────────
function mouseover.GetBarTargetAlpha(bar, restingAlpha, activeAlpha)
    if not bar or not bar:IsShown() then return 1.0 end

    -- Always 100% visible while moving bars or dragging spells/items
    if sfui.actionbars.moversUnlocked or mouseover.isDragging then
        return activeAlpha or 1.0
    end

    local modCfg = get_mod_cfg()
    local isMouseover = (modCfg.allBarsMouseover == true) or (bar.barConfig and bar.barConfig.mouseover)
    if not isMouseover then
        return 1.0
    end

    if not restingAlpha or not activeAlpha then
        restingAlpha = restingAlpha or modCfg.restingAlpha or 0.0
        activeAlpha = activeAlpha or modCfg.activeAlpha or 1.0
    end

    -- Visible when hovered
    if mouseover.IsBarHovered(bar) then
        return activeAlpha
    end

    return restingAlpha
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Instant Alpha Updater
-- ─────────────────────────────────────────────────────────────────────────────
function mouseover.UpdateBar(bar)
    if not bar or not bar:IsShown() then return end
    local targetAlpha = mouseover.GetBarTargetAlpha(bar)
    bar:SetAlpha(targetAlpha)
end

function mouseover.UpdateAllBars()
    local allBars = sfui.actionbars.GetAllBars and sfui.actionbars.GetAllBars()
    if not allBars then return end

    local modCfg = get_mod_cfg()
    local restingAlpha = modCfg.restingAlpha or 0.0
    local activeAlpha = modCfg.activeAlpha or 1.0

    for _, bar in ipairs(allBars) do
        if bar and bar:IsShown() then
            local targetAlpha = mouseover.GetBarTargetAlpha(bar, restingAlpha, activeAlpha)
            bar:SetAlpha(targetAlpha)
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Hook Bar and Buttons for Instant Mouseover
-- ─────────────────────────────────────────────────────────────────────────────
function mouseover.HookBar(bar)
    if not bar or bar._sfuiMouseoverHooked then return end
    bar._sfuiMouseoverHooked = true

    local function on_enter()
        bar._pendingLeave = nil
        local modCfg = get_mod_cfg()
        local activeAlpha = modCfg.activeAlpha or 1.0
        bar:SetAlpha(activeAlpha)
    end

    local function on_leave()
        -- Brief microsecond verification to allow cursor to cross button gaps without strobe flicker
        bar._pendingLeave = true
        C_Timer.After(0.04, function()
            if bar._pendingLeave then
                bar._pendingLeave = nil
                if not mouseover.IsBarHovered(bar) then
                    local targetAlpha = mouseover.GetBarTargetAlpha(bar)
                    bar:SetAlpha(targetAlpha)
                end
            end
        end)
    end

    bar:HookScript("OnEnter", on_enter)
    bar:HookScript("OnLeave", on_leave)

    if bar.buttons then
        for i = 1, #bar.buttons do
            local btn = bar.buttons[i]
            if btn then
                btn:HookScript("OnEnter", on_enter)
                btn:HookScript("OnLeave", on_leave)
            end
        end
    end

    -- Initial instant alpha sync
    mouseover.UpdateBar(bar)
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Drag-and-Drop Auto-Reveal Engine
-- ─────────────────────────────────────────────────────────────────────────────
function mouseover.SetDragging(isDragging)
    isDragging = not not isDragging
    if mouseover.isDragging == isDragging then return end
    mouseover.isDragging = isDragging

    -- Update alpha on all action bars
    mouseover.UpdateAllBars()

    -- Sync empty slot backgrounds and borders across all buttons
    local allBars = sfui.actionbars.GetAllBars and sfui.actionbars.GetAllBars()
    if allBars then
        local modCfg = get_mod_cfg()
        for _, bar in ipairs(allBars) do
            if bar and bar.buttons then
                for i = 1, #bar.buttons do
                    local btn = bar.buttons[i]
                    if btn and sfui.actionbars.style and sfui.actionbars.style.UpdateGrid then
                        sfui.actionbars.style.UpdateGrid(btn, modCfg)
                    end
                end
            end
        end
    end
end

local function OnDragEvent(event)
    if event == "ACTIONBAR_SHOWGRID" then
        mouseover.SetDragging(true)
    elseif event == "ACTIONBAR_HIDEGRID" then
        if not GetCursorInfo or GetCursorInfo() == nil then
            mouseover.SetDragging(false)
        end
    elseif event == "CURSOR_CHANGED" then
        local hasCursor = (GetCursorInfo and GetCursorInfo() ~= nil)
        if hasCursor then
            mouseover.SetDragging(true)
        else
            -- 20ms safety debounce so button receive-drop logic runs first
            C_Timer.After(0.02, function()
                if not GetCursorInfo or GetCursorInfo() == nil then
                    mouseover.SetDragging(false)
                end
            end)
        end
    end
end

if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("ACTIONBAR_SHOWGRID", OnDragEvent)
    sfui.events.RegisterEvent("ACTIONBAR_HIDEGRID", OnDragEvent)
    sfui.events.RegisterEvent("CURSOR_CHANGED", OnDragEvent)
end
