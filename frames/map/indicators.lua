local addonName, addon = ...
sfui = sfui or {}
sfui.minimap = sfui.minimap or {}

-- ========================
-- Localization
-- ========================
local _G = _G
local math_max = _G.math.max
local InCombatLockdown = _G.InCombatLockdown
local hooksecurefunc = _G.hooksecurefunc
local UIParent = _G.UIParent
local Minimap = _G.Minimap
local MinimapCluster = _G.MinimapCluster

-- ------------------------------------------------------------------------------
-- Mail & Crafting Order Indicator Management
-- ------------------------------------------------------------------------------
local isRepositioning = {}
local indicatorHooked = false
local mailHooked = false

local function on_indicator_anchor_changed(self)
    if isRepositioning[self] then return end
    isRepositioning[self] = true
    C_Timer.After(0, function()
        isRepositioning[self] = nil
        sfui.minimap.update_indicator_positions()
    end)
end

local function hook_indicator_frame(frame)
    if not frame or indicatorHooked then return end
    indicatorHooked = true

    if frame.SetPoint then
        hooksecurefunc(frame, "SetPoint", on_indicator_anchor_changed)
    end
    if frame.ClearAllPoints then
        hooksecurefunc(frame, "ClearAllPoints", on_indicator_anchor_changed)
    end
end

local function hook_mail_frame(frame)
    if not frame or mailHooked then return end
    mailHooked = true

    if frame.SetPoint then
        hooksecurefunc(frame, "SetPoint", on_indicator_anchor_changed)
    end
    if frame.ClearAllPoints then
        hooksecurefunc(frame, "ClearAllPoints", on_indicator_anchor_changed)
    end
end

local function hook_mail_visibility(frame)
    if not frame or frame.sfuiVisibilityHooked then return end
    frame.sfuiVisibilityHooked = true

    if frame.HookScript then
        frame:HookScript("OnShow", function()
            if sfui.minimap.arrange_buttons then
                sfui.minimap.arrange_buttons()
            end
        end)
        frame:HookScript("OnHide", function()
            if sfui.minimap.arrange_buttons then
                sfui.minimap.arrange_buttons()
            end
        end)
    end
end

function sfui.minimap.update_indicator_positions()
    local map = _G.Minimap
    if not map then return end

    local dockMail = true
    if SfuiDB and SfuiDB.minimap_dock_mail ~= nil then
        dockMail = SfuiDB.minimap_dock_mail
    elseif sfui.config and sfui.config.minimap and sfui.config.minimap.dock_mail ~= nil then
        dockMail = sfui.config.minimap.dock_mail
    end

    local button_bar = sfui.minimap.button_bar or _G.sfui_minimap_button_bar
    local isCollectActive = (SfuiDB and SfuiDB.minimap_collect_buttons ~= false)
    local isButtonBarActive = button_bar and button_bar:IsShown() and isCollectActive

    local indicator = (MinimapCluster and MinimapCluster.IndicatorFrame) or _G.MinimapIndicatorFrame
    local mail = _G.MiniMapMailFrame

    if dockMail and isButtonBarActive then
        local targetParent = button_bar
        local strata = button_bar:GetFrameStrata()
        local level = button_bar:GetFrameLevel() + 5
        local basePadX = (sfui.config and sfui.config.minimap and sfui.config.minimap.button_bar and sfui.config.minimap.button_bar.pad_x) or 8

        if indicator then
            isRepositioning[indicator] = true
            indicator:SetParent(targetParent)
            indicator:ClearAllPoints()
            indicator:SetPoint("LEFT", button_bar, "LEFT", basePadX, 0)
            indicator:SetFrameStrata(strata)
            indicator:SetFrameLevel(level)
            indicator:SetScale(0.85)
            isRepositioning[indicator] = nil
            hook_indicator_frame(indicator)
            hook_mail_visibility(indicator)
            if indicator.MailFrame then
                hook_mail_visibility(indicator.MailFrame)
            end
            if indicator.CraftingOrderFrame then
                hook_mail_visibility(indicator.CraftingOrderFrame)
            end
        end

        if mail and (not indicator or mail:GetParent() ~= indicator) then
            isRepositioning[mail] = true
            mail:SetParent(targetParent)
            mail:ClearAllPoints()
            mail:SetPoint("LEFT", button_bar, "LEFT", basePadX, 0)
            mail:SetFrameStrata(strata)
            mail:SetFrameLevel(level)
            mail:SetScale(0.85)
            isRepositioning[mail] = nil
            hook_mail_frame(mail)
            hook_mail_visibility(mail)
        end
    else
        local isSquare = (sfui.minimap and sfui.minimap.square and sfui.minimap.square:IsEnabled())
        local posX = isSquare and 6 or 18
        local posY = isSquare and -6 or -18

        if indicator then
            isRepositioning[indicator] = true
            indicator:SetParent(map)
            indicator:ClearAllPoints()
            indicator:SetPoint("TOPLEFT", map, "TOPLEFT", posX, posY)
            indicator:SetFrameStrata("MEDIUM")
            indicator:SetFrameLevel(math_max(25, indicator:GetFrameLevel()))
            indicator:SetScale(0.75)
            isRepositioning[indicator] = nil
            hook_indicator_frame(indicator)
        end

        if mail and (not indicator or mail:GetParent() ~= indicator) then
            isRepositioning[mail] = true
            mail:SetParent(map)
            mail:ClearAllPoints()
            mail:SetPoint("TOPLEFT", map, "TOPLEFT", posX, posY)
            mail:SetFrameStrata("MEDIUM")
            mail:SetFrameLevel(math_max(25, mail:GetFrameLevel()))
            mail:SetScale(0.75)
            isRepositioning[mail] = nil
            hook_mail_frame(mail)
        end
    end

    -- Ensure Camelot day/night diel cycle indicator stays elevated in LOW strata above map but never intercepts mouse
    if MinimapCluster and MinimapCluster.DielFrame then
        MinimapCluster.DielFrame:SetFrameStrata("LOW")
        MinimapCluster.DielFrame:SetFrameLevel(math_max(5, MinimapCluster.DielFrame:GetFrameLevel()))
        MinimapCluster.DielFrame:EnableMouse(false)
        MinimapCluster.DielFrame:SetAlpha(1)
        MinimapCluster.DielFrame:Show()
    end

    if sfui.minimap.arrange_buttons then
        sfui.minimap.arrange_buttons()
    end
end

if _G.MiniMapIndicatorFrame_UpdatePosition then
    hooksecurefunc("MiniMapIndicatorFrame_UpdatePosition", function()
        C_Timer.After(0, function()
            sfui.minimap.update_indicator_positions()
        end)
    end)
end

-- ------------------------------------------------------------------------------
-- QueueStatus (Dungeon Finder / LFG Eye) Management
-- ------------------------------------------------------------------------------
function sfui.minimap.update_queue_status_position()
    local btn = _G.QueueStatusButton
    local map = _G.Minimap
    if not btn or not map then return end

    if InCombatLockdown() then return end

    if btn:GetParent() ~= UIParent and btn:GetParent() ~= map then
        btn:SetParent(UIParent)
    end
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(25)
    btn:SetScale(0.85)

    btn:ClearAllPoints()
    btn:SetPoint("BOTTOMLEFT", map, "BOTTOMLEFT", -2, -2)
end

local function on_queue_status_anchor_changed(self)
    if isRepositioning[self] then return end
    isRepositioning[self] = true
    C_Timer.After(0, function()
        isRepositioning[self] = nil
        sfui.minimap.update_queue_status_position()
    end)
end

local queueStatusHooked = false
function sfui.minimap.hook_queue_status()
    if queueStatusHooked then return end

    local btn = _G.QueueStatusButton
    if not btn then return end
    queueStatusHooked = true

    if btn.SetPoint then
        hooksecurefunc(btn, "SetPoint", on_queue_status_anchor_changed)
    end

    if btn.ClearAllPoints then
        hooksecurefunc(btn, "ClearAllPoints", on_queue_status_anchor_changed)
    end

    if _G.QueueStatusFrame_UpdatePosition then
        hooksecurefunc("QueueStatusFrame_UpdatePosition", function()
            C_Timer.After(0, function()
                sfui.minimap.update_queue_status_position()
            end)
        end)
    end

    sfui.minimap.update_queue_status_position()
end
