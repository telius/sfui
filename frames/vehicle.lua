sfui.vehicle = {}

local frame = CreateFrame("Frame", "SfuiVehicleBar", UIParent, "SecureHandlerStateTemplate")
sfui.vehicle.frame = frame

local cfg = sfui.config.vehicle
local g = sfui.config
local mult = sfui.pixelScale or 1
local msqGroup = sfui.common.get_masque_group("Vehicle")

frame:SetSize(cfg.width, cfg.height)
frame:SetPoint(cfg.anchor.point, cfg.anchor.x, cfg.anchor.y)

-- Background
frame.bg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
frame.bg:SetAllPoints()
frame.bg:SetBackdrop({
    bgFile = g.textures.white,
    edgeFile = g.textures.white,
    edgeSize = mult,
})
frame.bg:SetBackdropColor(0, 0, 0, 0.5)
frame.bg:SetBackdropBorderColor(g.colors.gray[1], g.colors.gray[2], g.colors.gray[3], 1)

-- Buttons
local buttons = {}
for i = 1, 12 do
    local btn = CreateFrame("CheckButton", "SfuiVehicleButton" .. i, frame,
        "SecureActionButtonTemplate, ActionButtonTemplate")
    btn:SetSize(cfg.button_size, cfg.button_size)
    btn:SetID(i)

    -- Style
    if _G[btn:GetName() .. "Icon"] then _G[btn:GetName() .. "Icon"]:SetAlpha(0) end
    if btn.Flash then btn.Flash:SetAlpha(0) end
    if btn.NewActionTexture then btn.NewActionTexture:SetAlpha(0) end
    if btn.Border then btn.Border:SetAlpha(0) end
    if btn.HotKey then btn.HotKey:SetAlpha(0) end
    if btn.Count then btn.Count:SetAlpha(0) end

    btn:SetNormalTexture("")
    btn:SetPushedTexture("")
    btn:SetHighlightTexture("")
    btn:SetCheckedTexture("")

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)

    btn.border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    btn.border:SetAllPoints()
    btn.border:SetBackdrop({
        edgeFile = g.textures.white,
        edgeSize = mult,
    })
    btn.border:SetBackdropBorderColor(g.colors.gray[1], g.colors.gray[2], g.colors.gray[3], 1)

    -- Keybind
    btn.kb = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.kb:SetPoint("TOPRIGHT", -2, -2)
    local kbText = sfui.common.VEHICLE_KEYBIND_MAP[i] or tostring(i)
    btn.kb:SetText(kbText)

    if i == 1 then
        btn:SetPoint("LEFT", cfg.button_spacing, 0)
    else
        btn:SetPoint("LEFT", buttons[i - 1], "RIGHT", cfg.button_spacing, 0)
    end

    if msqGroup then
        msqGroup:AddButton(btn)
    end

    btn:SetScript("OnEnter", function(self)
        if self:GetAttribute("action") then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetAction(self:GetAttribute("action"))
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    buttons[i] = btn
end

-- Leave Button
local leaveBtn = CreateFrame("Button", "SfuiVehicleLeaveButton", frame, "SecureActionButtonTemplate")
leaveBtn:SetSize(cfg.button_size, cfg.button_size) -- Match size for consistency
leaveBtn:SetPoint("LEFT", buttons[12], "RIGHT", cfg.button_spacing * 2, 0)
leaveBtn:RegisterForClicks("AnyUp")

local leaveIcon = leaveBtn:CreateTexture(nil, "ARTWORK")
leaveIcon:SetAllPoints()
-- Use the standard modern Atlas for vehicle exit
if not leaveIcon:SetAtlas("actionbar-vehicle-exit") then
    leaveIcon:SetTexture("Interface\\Buttons\\UI-Panel-ExitButton-Up")
end
leaveBtn.Icon = leaveIcon
leaveBtn.icon = leaveIcon -- For internal script compatibility if needed

leaveBtn.border = CreateFrame("Frame", nil, leaveBtn, "BackdropTemplate")
leaveBtn.border:SetAllPoints()
leaveBtn.border:SetBackdrop({
    edgeFile = g.textures.white,
    edgeSize = mult,
})
leaveBtn.border:SetBackdropBorderColor(g.colors.gray[1], g.colors.gray[2], g.colors.gray[3], 1)

-- Keybind for Leave
leaveBtn.kb = leaveBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
leaveBtn.kb:SetPoint("TOPRIGHT", -2, -2)
leaveBtn.kb:SetText("=")

if msqGroup then
    msqGroup:AddButton(leaveBtn)
end

leaveBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(LEAVE_VEHICLE)
    GameTooltip:Show()
end)
leaveBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

leaveBtn:SetScript("OnClick", function()
    if UnitOnTaxi("player") then
        TaxiRequestEarlyLanding()
    else
        VehicleExit()
    end
end)

-- Handle Vehicle State
-- Suppress during Dragonriding (skyriding) but only when on a mount
-- This avoids suppressing quest vehicles that might trigger dragonriding
RegisterStateDriver(frame, "visibility",
    "[petbattle] hide; [mounted,bonusbar:5] hide; [vehicleui][possessbar][overridebar][bonusbar:5] show; hide")

local function UpdateActionButtons()
    if InCombatLockdown() then
        frame.needsUpdate = true
        return
    end
    frame.needsUpdate = false

    local barIndex
    if C_ActionBar.HasVehicleActionBar() then
        barIndex = C_ActionBar.GetVehicleBarIndex()
    elseif C_ActionBar.HasOverrideActionBar() then
        barIndex = C_ActionBar.GetOverrideBarIndex()
    elseif C_ActionBar.HasTempShapeshiftActionBar() then
        barIndex = C_ActionBar.GetTempShapeshiftBarIndex()
    elseif C_ActionBar.HasBonusActionBar() then
        barIndex = C_ActionBar.GetBonusBarIndex()
    else
        barIndex = C_ActionBar.GetActionBarPage()
    end

    if not barIndex or barIndex == 0 then barIndex = 1 end

    local lastIdx = 0
    for i = 1, 12 do
        local btn = buttons[i]
        local actionID = (barIndex - 1) * 12 + i
        btn:SetAttribute("action", actionID)

        local icon = C_ActionBar.GetActionTexture(actionID)
        if icon then
            btn.icon:SetTexture(icon)
            btn:Show()
            lastIdx = i
        else
            btn:Hide()
        end
    end

    -- Ensure Leave button is visible and correctly anchored
    if lastIdx > 0 then
        local totalWidth = (cfg.button_size + cfg.button_spacing) * (lastIdx + 1) + cfg.button_spacing
        frame:SetWidth(totalWidth)
        leaveBtn:SetPoint("LEFT", buttons[lastIdx], "RIGHT", cfg.button_spacing, 0)
        leaveBtn:Show()
    else
        -- Don't Hide() here, let the state driver handle main frame visibility
    end
end

frame:RegisterEvent("UNIT_ENTERED_VEHICLE")
frame:RegisterEvent("UNIT_EXITED_VEHICLE")
frame:RegisterEvent("VEHICLE_UPDATE")
frame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
frame:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
frame:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR")
frame:RegisterEvent("UPDATE_POSSESS_BAR")
frame:RegisterEvent("ACTIONBAR_UPDATE_STATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

frame:SetScript("OnEvent", function(self, event, ...)
    if not SfuiDB.enableVehicle then
        self:Hide()
        if UnregisterStateDriver then UnregisterStateDriver(self, "visibility") end
        if OverrideActionBar then
            OverrideActionBar:SetAlpha(1); OverrideActionBar:EnableMouse(true)
        end
        if MainMenuBarVehicleLeaveButton then
            MainMenuBarVehicleLeaveButton:SetAlpha(1); MainMenuBarVehicleLeaveButton:EnableMouse(true)
        end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" or event == "UPDATE_BONUS_ACTIONBAR" or event == "VEHICLE_UPDATE"
        or event == "UPDATE_VEHICLE_ACTIONBAR" or event == "UPDATE_OVERRIDE_ACTIONBAR" or event == "UPDATE_POSSESS_BAR"
        or event == "UNIT_ENTERED_VEHICLE" or (event == "PLAYER_REGEN_ENABLED" and self.needsUpdate) then
        UpdateActionButtons()
    end
end)

-- Suppress Blizzard
if OverrideActionBar then
    OverrideActionBar:SetAlpha(0)
    OverrideActionBar:EnableMouse(false)
end
if MainMenuBarVehicleLeaveButton then
    MainMenuBarVehicleLeaveButton:SetAlpha(0)
    MainMenuBarVehicleLeaveButton:EnableMouse(false)
end
