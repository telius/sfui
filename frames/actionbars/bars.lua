local addonName, addon = ...
sfui = sfui or {}
sfui.actionbars = sfui.actionbars or {}

local _G = _G
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local LibStub = _G.LibStub
local hooksecurefunc = _G.hooksecurefunc
local pairs = _G.pairs
local math_min = math.min
local math_max = math.max
local math_ceil = math.ceil
local math_floor = math.floor
local format = string.format
local InCombatLockdown = _G.InCombatLockdown

local wipe = _G.wipe

sfui.actionbars.bars = {}
sfui.actionbars.barsByKey = {}

-- sfui bar N displays action page N (slots (N-1)*12+1 .. N*12); map to the Blizzard binding that fires that page.
-- Page 2 has no Blizzard binding, so bar 2 only resolves its own click binding.
local PAGE_BINDING_PREFIX = {
    [1] = "ACTIONBUTTON",
    [3] = "MULTIACTIONBAR3BUTTON", -- MultiBarRight (RIGHT_ACTIONBAR_PAGE = 3)
    [4] = "MULTIACTIONBAR4BUTTON", -- MultiBarLeft (LEFT_ACTIONBAR_PAGE = 4)
    [5] = "MULTIACTIONBAR2BUTTON", -- MultiBarBottomRight (BOTTOMRIGHT_ACTIONBAR_PAGE = 5)
    [6] = "MULTIACTIONBAR1BUTTON", -- MultiBarBottomLeft (BOTTOMLEFT_ACTIONBAR_PAGE = 6)
    [7] = "MULTIACTIONBAR6BUTTON", -- MultiBar6 (Action Bar 7 in Blizzard Keybindings)
    [8] = "MULTIACTIONBAR7BUTTON", -- MultiBar7 (Action Bar 8 in Blizzard Keybindings)
}

local BONUS_KEYS = {
    [1] = "BONUSACTIONBUTTON1",
    [2] = "BONUSACTIONBUTTON2",
    [3] = "BONUSACTIONBUTTON3",
    [4] = "BONUSACTIONBUTTON4",
    [5] = "BONUSACTIONBUTTON5",
    [6] = "BONUSACTIONBUTTON6",
    [7] = "BONUSACTIONBUTTON7",
    [8] = "BONUSACTIONBUTTON8",
    [9] = "BONUSACTIONBUTTON9",
    [10] = "BONUSACTIONBUTTON10",
}

-- ─────────────────────────────────────────────────────────────────────────────
--  All Active Bars Enumeration (Zero Allocation)
-- ─────────────────────────────────────────────────────────────────────────────
local allBarsList = {}

function sfui.actionbars.GetAllBars()
    wipe(allBarsList)
    if sfui.actionbars.bars then
        for i = 1, 10 do
            local b = sfui.actionbars.bars[i]
            if b then
                allBarsList[#allBarsList + 1] = b
            end
        end
    end
    if sfui.actionbars.petBar then
        allBarsList[#allBarsList + 1] = sfui.actionbars.petBar
    end
    return allBarsList
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Configuration Retrieval
-- ─────────────────────────────────────────────────────────────────────────────
function sfui.actionbars.GetBarConfig(barKey)
    if SfuiDB and SfuiDB.actionbars and SfuiDB.actionbars.bars and SfuiDB.actionbars.bars[barKey] then
        local dbCfg = SfuiDB.actionbars.bars[barKey]
        if barKey == "vehicle" and dbCfg.x == -120 and dbCfg.y == 35 then
            dbCfg.x = 0
            dbCfg.y = 210
            dbCfg.buttonSize = 34
        end
        return dbCfg
    end
    if sfui.config and sfui.config.actionbars and sfui.config.actionbars.bars and sfui.config.actionbars.bars[barKey] then
        return sfui.config.actionbars.bars[barKey]
    end
    if barKey == "pet" then
        return {
            enabled = true,
            mouseover = false,
            buttons = 10,
            buttonsPerRow = 10,
            buttonSize = 28,
            spacing = 4,
            point = "BOTTOM",
            relPoint = "BOTTOM",
            x = 0,
            y = 168,
        }
    end
    if barKey == "vehicle" then
        return {
            enabled = true,
            buttonSize = 34,
            point = "BOTTOM",
            relPoint = "BOTTOM",
            x = 0,
            y = 210,
        }
    end
    return {
        enabled = true,
        mouseover = false,
        buttons = 12,
        buttonsPerRow = 3,
        buttonSize = 28,
        spacing = 4,
        point = "BOTTOM",
        relPoint = "BOTTOM",
        x = 0,
        y = 50,
    }
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Button Locking & Shift-to-Drag Management
-- ─────────────────────────────────────────────────────────────────────────────
function sfui.actionbars.AreButtonsLocked()
    if SfuiDB and SfuiDB.actionbars and SfuiDB.actionbars.lockButtons ~= nil then
        return SfuiDB.actionbars.lockButtons
    end
    if sfui.config and sfui.config.actionbars and sfui.config.actionbars.lockButtons ~= nil then
        return sfui.config.actionbars.lockButtons
    end
    return true
end

function sfui.actionbars.SetButtonsLocked(isLocked)
    if isLocked == nil then
        isLocked = sfui.actionbars.AreButtonsLocked()
    end

    if SfuiDB then
        SfuiDB.actionbars = SfuiDB.actionbars or {}
        SfuiDB.actionbars.lockButtons = isLocked
    end

    local mod = (SfuiDB and SfuiDB.actionbars and SfuiDB.actionbars.movementModifier)
        or (sfui.config and sfui.config.actionbars and sfui.config.actionbars.movementModifier)
        or "SHIFT"

    -- Sync Blizzard's lockActionBars CVar so native PetActionBar & flyouts require Shift
    sfui.common.set_cvar("lockActionBars", isLocked and 1 or 0)
    if _G.Settings and _G.Settings.SetValue then
        pcall(_G.Settings.SetValue, "lockActionBars", isLocked)
    end

    -- ElvUI Pattern: Enforce movementModifier on PICKUPACTION (in-memory only, matching ElvUI)
    if _G.SetModifiedClick then
        _G.SetModifiedClick("PICKUPACTION", mod)
    end

    -- Secure button attribute updates must happen outside combat lockdown
    if InCombatLockdown and InCombatLockdown() then
        if sfui.common and sfui.common.run_after_combat then
            sfui.common.run_after_combat(function()
                sfui.actionbars.SetButtonsLocked(isLocked)
            end)
        end
        return
    end

    local LAB = LibStub and LibStub("LibActionButton-1.0", true)
    if LAB and LAB.buttonRegistry then
        for button in pairs(LAB.buttonRegistry) do
            if button and button.SetAttribute then
                button:SetAttribute("buttonlock", isLocked or nil)
                button:SetAttribute("unlockedpreventdrag", true)
            end
        end
    end
    if sfui.actionbars.bars then
        for barIndex = 1, 10 do
            local bar = sfui.actionbars.bars[barIndex]
            if bar and bar.buttons then
                for _, button in ipairs(bar.buttons) do
                    if button and button.SetAttribute then
                        button:SetAttribute("buttonlock", isLocked or nil)
                        button:SetAttribute("unlockedpreventdrag", true)
                    end
                end
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Layout Application (3x4 Grid & Custom Shapes)
-- ─────────────────────────────────────────────────────────────────────────────
function sfui.actionbars.ApplyBarLayout(barIndex)
    local bar = sfui.actionbars.bars[barIndex]
    if not bar then return end

    if InCombatLockdown and InCombatLockdown() then
        bar._needsLayout = true
        return
    end
    bar._needsLayout = nil

    local barKey = "bar" .. tostring(barIndex)
    local cfg = sfui.actionbars.GetBarConfig(barKey)
    bar.barConfig = cfg

    if not cfg.enabled then
        bar:Hide()
        if bar.mover then bar.mover:Hide() end
        if _G.ClearOverrideBindings then _G.ClearOverrideBindings(bar) end
        return
    end

    bar:Show()
    if not InCombatLockdown or not InCombatLockdown() then
        if _G.ClearOverrideBindings then _G.ClearOverrideBindings(bar) end
        if sfui.actionbars.OverrideBarBindings then
            sfui.actionbars.OverrideBarBindings(bar)
        end
    end

    local numButtons = cfg.buttons or 12
    local buttonsPerRow = cfg.buttonsPerRow or 3 -- default 3 columns for 3x4 grid
    local buttonSize = cfg.buttonSize or 28
    local spacing = cfg.spacing or 4

    local cols = math_min(numButtons, buttonsPerRow)
    local rows = math_ceil(numButtons / cols)
    local barWidth = cols * buttonSize + math_max(0, cols - 1) * spacing
    local barHeight = rows * buttonSize + math_max(0, rows - 1) * spacing

    bar:SetSize(barWidth, barHeight)
    if bar.mover then
        bar.mover:SetSize(barWidth, barHeight)
    end

    local modCfg = (sfui.db and sfui.db.Get and sfui.db.Get("actionbars")) or (sfui.config and sfui.config.actionbars) or {}

    for i = 1, 12 do
        local btn = bar.buttons[i]
        if btn then
            if i <= numButtons then
                local col = (i - 1) % cols
                local row = math_floor((i - 1) / cols)

                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", bar, "TOPLEFT", col * (buttonSize + spacing), -row * (buttonSize + spacing))
                btn:SetSize(buttonSize, buttonSize)
                btn:Show()

                -- Apply styling & element visibility
                if sfui.actionbars.style and sfui.actionbars.style.UpdateElements then
                    sfui.actionbars.style.UpdateElements(btn, modCfg)
                end
            else
                btn:Hide()
            end
        end
    end

    if sfui.actionbars.mouseover and sfui.actionbars.mouseover.UpdateAllBars then
        sfui.actionbars.mouseover.UpdateAllBars(true)
    end

    if barIndex == 1 and sfui.actionbars.UpdateVehicleLeaveButtonLayout then
        sfui.actionbars.UpdateVehicleLeaveButtonLayout()
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Pet Bar Layout & Creation
-- ─────────────────────────────────────────────────────────────────────────────
local petUpdatePending = false

function sfui.actionbars.RequestPetBarUpdate()
    if petUpdatePending then return end
    petUpdatePending = true
    _G.C_Timer.After(0, function()
        petUpdatePending = false
        if sfui.actionbars.UpdatePetBar then
            sfui.actionbars.UpdatePetBar()
        end
    end)
end

function sfui.actionbars.UpdatePetCooldowns()
    local bar = sfui.actionbars.petBar
    if not bar or not bar.buttons then return end
    if not _G.PetHasActionBar or not _G.PetHasActionBar() or not _G.GetPetActionCooldown then return end

    local CooldownFrame_Set = _G.CooldownFrame_Set
    local GetPetActionCooldown = _G.GetPetActionCooldown
    for i = 1, 10 do
        local btn = bar.buttons[i]
        local cd = btn and btn.cooldown
        if cd then
            local start, duration, enable = GetPetActionCooldown(i)
            if CooldownFrame_Set then
                CooldownFrame_Set(cd, start, duration, enable)
            elseif cd.SetCooldown then
                cd:SetCooldown(start, duration)
            end
        end
    end
end

function sfui.actionbars.UpdatePetUsable()
    local bar = sfui.actionbars.petBar
    if not bar or not bar.buttons then return end
    if not _G.PetHasActionBar or not _G.PetHasActionBar() or not _G.GetPetActionSlotUsable then return end

    local GetPetActionSlotUsable = _G.GetPetActionSlotUsable
    for i = 1, 10 do
        local btn = bar.buttons[i]
        local icon = btn and (btn.icon or btn.Icon)
        if icon and icon:IsShown() then
            if GetPetActionSlotUsable(i) then
                icon:SetVertexColor(1, 1, 1)
            else
                icon:SetVertexColor(0.4, 0.4, 0.4)
            end
        end
    end
end

function sfui.actionbars.UpdatePetHotkeys()
    local bar = sfui.actionbars.petBar
    if not bar or not bar.buttons then return end

    local modCfg = (sfui.db and sfui.db.Get and sfui.db.Get("actionbars")) or (sfui.config and sfui.config.actionbars) or {}
    local showHotkeys = (modCfg.showHotkeys ~= false)
    local formatHotkey = sfui.actionbars.style and sfui.actionbars.style.FormatHotkeyText
    local GetBindingKey = _G.GetBindingKey
    local GetBindingText = _G.GetBindingText

    for i = 1, 10 do
        local btn = bar.buttons[i]
        local hotkey = btn and (btn.HotKey or (btn.GetName and _G[btn:GetName() .. "HotKey"]))
        if hotkey then
            if not showHotkeys then
                hotkey:Hide()
            else
                local key = GetBindingKey(BONUS_KEYS[i])
                if key and key ~= "" then
                    local text = GetBindingText(key, true)
                    local formatted = (formatHotkey and formatHotkey(text)) or text
                    hotkey:SetText(formatted)
                    hotkey:Show()
                else
                    hotkey:SetText("")
                    hotkey:Hide()
                end
            end
        end
    end
end

function sfui.actionbars.UpdatePetBar()
    local bar = sfui.actionbars.petBar
    if not bar or not bar.buttons then return end

    local hasPetBar = _G.PetHasActionBar and _G.PetHasActionBar()
    if not hasPetBar then
        if not bar._isCleared then
            bar._isCleared = true
            for i = 1, 10 do
                local btn = bar.buttons[i]
                if btn then
                    local icon = btn.icon or btn.Icon
                    if icon then
                        icon:SetTexture(nil)
                        icon:Hide()
                    end
                    btn.tooltipName = nil
                    btn:SetChecked(false)
                    if btn.StopFlash then btn:StopFlash() end
                    local autoCast = btn.AutoCastOverlay or btn.AutoCastable
                    if autoCast then autoCast:Hide() end
                    local hotkey = btn.HotKey or (btn.GetName and _G[btn:GetName() .. "HotKey"])
                    if hotkey then hotkey:Hide() end
                    if sfui.actionbars.style and sfui.actionbars.style.UpdateGrid then
                        sfui.actionbars.style.UpdateGrid(btn)
                    end
                end
            end
        end
        return
    end
    bar._isCleared = nil

    local modCfg = (sfui.db and sfui.db.Get and sfui.db.Get("actionbars")) or (sfui.config and sfui.config.actionbars) or {}
    local showHotkeys = (modCfg.showHotkeys ~= false)
    local formatHotkey = sfui.actionbars.style and sfui.actionbars.style.FormatHotkeyText
    local updateGrid = sfui.actionbars.style and sfui.actionbars.style.UpdateGrid
    local GetPetActionInfo = _G.GetPetActionInfo
    local GetPetActionSlotUsable = _G.GetPetActionSlotUsable
    local GetPetActionCooldown = _G.GetPetActionCooldown
    local CooldownFrame_Set = _G.CooldownFrame_Set
    local IsPetAttackAction = _G.IsPetAttackAction
    local PetActionButton_StartFlash = _G.PetActionButton_StartFlash
    local PetActionButton_StopFlash = _G.PetActionButton_StopFlash
    local SharedActionButton_RefreshSpellHighlight = _G.SharedActionButton_RefreshSpellHighlight
    local HasPetActionHighlightMark = _G.HasPetActionHighlightMark
    local GetBindingKey = _G.GetBindingKey
    local GetBindingText = _G.GetBindingText

    for i = 1, 10 do
        local btn = bar.buttons[i]
        if btn then
            local icon = btn.icon or btn.Icon
            local autoCast = btn.AutoCastOverlay or btn.AutoCastable
            local cd = btn.cooldown

            local name, texture, isToken, isActive, autoCastAllowed, autoCastEnabled, spellID, checksRange, inRange = GetPetActionInfo(i)

            if texture then
                if icon then
                    if not isToken then
                        icon:SetTexture(texture)
                        btn.tooltipName = name
                    else
                        icon:SetTexture(_G[texture] or texture)
                        btn.tooltipName = _G[name] or name
                    end

                    local isUsable = not GetPetActionSlotUsable or GetPetActionSlotUsable(i)
                    if isUsable then
                        icon:SetVertexColor(1, 1, 1)
                    else
                        icon:SetVertexColor(0.4, 0.4, 0.4)
                    end
                    icon:Show()
                end

                btn.isToken = isToken
                if spellID and spellID ~= btn.spellDataSpellID and _G.Spell and _G.Spell.CreateFromSpellID then
                    btn.spellDataSpellID = spellID
                    local spell = _G.Spell:CreateFromSpellID(spellID)
                    if spell and spell.ContinueWithCancelOnSpellLoad then
                        btn.spellDataLoadedCancelFunc = spell:ContinueWithCancelOnSpellLoad(function()
                            btn.tooltipSubtext = spell:GetSpellSubtext()
                        end)
                    end
                end

                if isActive and name ~= "PET_ACTION_FOLLOW" then
                    btn:SetChecked(true)
                    local checkedTex = btn.GetCheckedTexture and btn:GetCheckedTexture()
                    if checkedTex then
                        local isAttack = IsPetAttackAction and IsPetAttackAction(i)
                        checkedTex:SetAlpha(isAttack and 0.5 or 1.0)
                    end
                else
                    btn:SetChecked(false)
                end

                if PetActionButton_StartFlash and PetActionButton_StopFlash then
                    if isActive and IsPetAttackAction and IsPetAttackAction(i) then
                        PetActionButton_StartFlash(btn)
                    else
                        PetActionButton_StopFlash(btn)
                    end
                elseif btn.StartFlash and btn.StopFlash then
                    if isActive and IsPetAttackAction and IsPetAttackAction(i) then
                        btn:StartFlash()
                    else
                        btn:StopFlash()
                    end
                end

                if autoCast then
                    autoCast:SetShown(autoCastAllowed)
                    if autoCast.ShowAutoCastEnabled then
                        autoCast:ShowAutoCastEnabled(autoCastEnabled)
                    end
                end

                if cd and GetPetActionCooldown then
                    local start, duration, enable = GetPetActionCooldown(i)
                    if CooldownFrame_Set then
                        CooldownFrame_Set(cd, start, duration, enable)
                    elseif cd.SetCooldown then
                        cd:SetCooldown(start, duration)
                    end
                end

                if _G.ActionButton_UpdateRangeIndicator and checksRange ~= nil then
                    _G.ActionButton_UpdateRangeIndicator(btn, checksRange, inRange)
                end

                if HasPetActionHighlightMark and SharedActionButton_RefreshSpellHighlight then
                    SharedActionButton_RefreshSpellHighlight(btn, HasPetActionHighlightMark(i))
                end

                if _G.GameTooltip and _G.GameTooltip:GetOwner() == btn and btn.OnEnter then
                    pcall(btn.OnEnter, btn)
                end
            else
                if icon then
                    icon:SetTexture(nil)
                    icon:Hide()
                end
                btn.tooltipName = nil
                btn:SetChecked(false)
                if btn.StopFlash then btn:StopFlash() end
                if autoCast then autoCast:Hide() end
            end

            -- Update hotkey text from precomputed binding keys
            local hotkey = btn.HotKey or (btn.GetName and _G[btn:GetName() .. "HotKey"])
            if hotkey then
                if not showHotkeys then
                    hotkey:Hide()
                else
                    local key = GetBindingKey(BONUS_KEYS[i])
                    if key and key ~= "" then
                        local text = GetBindingText(key, true)
                        local formatted = (formatHotkey and formatHotkey(text)) or text
                        hotkey:SetText(formatted)
                        hotkey:Show()
                    else
                        hotkey:SetText("")
                        hotkey:Hide()
                    end
                end
            end

            -- Update slot grid backdrop and borders with pre-fetched modCfg
            if updateGrid then
                updateGrid(btn, modCfg)
            end
        end
    end
end

function sfui.actionbars.ApplyPetBarLayout()
    local bar = sfui.actionbars.petBar
    if not bar then return end

    if InCombatLockdown and InCombatLockdown() then
        bar._needsLayout = true
        return
    end
    bar._needsLayout = nil

    local cfg = sfui.actionbars.GetBarConfig("pet")
    bar.barConfig = cfg

    if not cfg.enabled then
        _G.UnregisterStateDriver(bar, "visibility")
        bar:Hide()
        if bar.mover then bar.mover:Hide() end
        if _G.ClearOverrideBindings then _G.ClearOverrideBindings(bar) end
        return
    else
        _G.RegisterStateDriver(bar, "visibility", "[pet,nooverridebar,nopossessbar] show; hide")
        if not InCombatLockdown or not InCombatLockdown() then
            if _G.ClearOverrideBindings then _G.ClearOverrideBindings(bar) end
            if sfui.actionbars.OverrideBarBindings then
                sfui.actionbars.OverrideBarBindings(bar)
            end
        end
    end

    local numButtons = cfg.buttons or 10
    local buttonsPerRow = cfg.buttonsPerRow or 10
    local buttonSize = cfg.buttonSize or 28
    local spacing = cfg.spacing or 4

    local cols = math_min(numButtons, buttonsPerRow)
    local rows = math_ceil(numButtons / cols)
    local barWidth = cols * buttonSize + math_max(0, cols - 1) * spacing
    local barHeight = rows * buttonSize + math_max(0, rows - 1) * spacing

    bar:SetSize(barWidth, barHeight)
    if bar.mover then
        bar.mover:SetSize(barWidth, barHeight)
    end

    local modCfg = (sfui.db and sfui.db.Get and sfui.db.Get("actionbars")) or (sfui.config and sfui.config.actionbars) or {}

    for i = 1, 10 do
        local btn = bar.buttons[i]
        if btn then
            if i <= numButtons then
                local col = (i - 1) % cols
                local row = math_floor((i - 1) / cols)

                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", bar, "TOPLEFT", col * (buttonSize + spacing), -row * (buttonSize + spacing))
                btn:SetSize(buttonSize, buttonSize)
                btn:Show()

                -- Adjust pet action icon & auto-cast overlay sizing
                local icon = btn.icon or btn.Icon
                if icon then
                    icon:ClearAllPoints()
                    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
                    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
                    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    icon:SetDrawLayer("ARTWORK", 0)
                end
                if btn.AutoCastOverlay then
                    btn.AutoCastOverlay:SetAllPoints(btn)
                end
                if btn.SpellHighlightTexture then
                    btn.SpellHighlightTexture:SetAllPoints(btn)
                end

                if sfui.actionbars.style and sfui.actionbars.style.UpdateElements then
                    sfui.actionbars.style.UpdateElements(btn, modCfg)
                end
            else
                btn:Hide()
            end
        end
    end

    if sfui.actionbars.UpdatePetBar then
        sfui.actionbars.UpdatePetBar()
    end

    if sfui.actionbars.mouseover and sfui.actionbars.mouseover.UpdateAllBars then
        sfui.actionbars.mouseover.UpdateAllBars(true)
    end
end

function sfui.actionbars.ProcessDeferredLayouts()
    if InCombatLockdown and InCombatLockdown() then return end
    for i = 1, 10 do
        local bar = sfui.actionbars.bars and sfui.actionbars.bars[i]
        if bar and bar._needsLayout then
            bar._needsLayout = nil
            sfui.actionbars.ApplyBarLayout(i)
        end
    end
    local petBar = sfui.actionbars.petBar
    if petBar and petBar._needsLayout then
        petBar._needsLayout = nil
        sfui.actionbars.ApplyPetBarLayout()
    end
end

function sfui.actionbars.CreatePetBar()
    if sfui.actionbars.petBar then return end

    if sfui.actionbars.HookPetActionBar then
        sfui.actionbars.HookPetActionBar()
    end

    local bar = CreateFrame("Frame", "sfui_PetBar", UIParent, "SecureHandlerStateTemplate")
    sfui.common.set_pixel_snapping(bar)
    bar.barKey = "pet"
    bar.buttons = {}
    sfui.actionbars.petBar = bar
    sfui.actionbars.barsByKey["pet"] = bar

    -- Gather PetActionButton1 through PetActionButton10
    for i = 1, 10 do
        local btn = _G["PetActionButton" .. i]
        if btn then
            btn:SetParent(bar)
            btn.bar = nil
            btn.index = i
            btn.barKey = "pet"
            btn.commandName = "BONUSACTIONBUTTON" .. i
            if btn.SetID then btn:SetID(i) end
            bar.buttons[i] = btn
            if sfui.actionbars.style and sfui.actionbars.style.SkinButton then
                sfui.actionbars.style.SkinButton(btn)
            end
            if sfui.actionbars.bind and sfui.actionbars.bind.RegisterButton then
                sfui.actionbars.bind.RegisterButton(btn)
            end
        end
    end

    -- Hook mouseover
    if sfui.actionbars.mouseover and sfui.actionbars.mouseover.HookBar then
        sfui.actionbars.mouseover.HookBar(bar)
    end

    -- Create mover
    if sfui.actionbars.movers and sfui.actionbars.movers.CreateMover then
        sfui.actionbars.movers.CreateMover(bar, nil, "pet")
    end

    -- Visibility driver: show when pet exists and not in vehicle/override
    _G.RegisterStateDriver(bar, "visibility", "[pet,nooverridebar,nopossessbar] show; hide")

    if bar.HookScript then
        bar:HookScript("OnShow", function()
            if sfui.actionbars.UpdatePetBar then
                sfui.actionbars.UpdatePetBar()
            end
        end)
        bar:HookScript("OnHide", function(self)
            if self.buttons then
                for _, btn in ipairs(self.buttons) do
                    if btn.spellDataLoadedCancelFunc then
                        btn.spellDataLoadedCancelFunc()
                        btn.spellDataLoadedCancelFunc = nil
                        btn.spellDataSpellID = nil
                    end
                end
            end
        end)
    end

    -- Range check ticker on sfui_PetBar
    local rangeElapsed = 0
    bar:SetScript("OnUpdate", function(self, elapsed)
        rangeElapsed = rangeElapsed + elapsed
        if rangeElapsed >= 0.2 then
            rangeElapsed = 0
            if not _G.GetPetActionInfo or not _G.PetHasActionBar or not _G.PetHasActionBar() then return end
            for i = 1, 10 do
                local btn = self.buttons[i]
                if btn and btn:IsShown() then
                    local _, _, _, _, _, _, _, checksRange, inRange = _G.GetPetActionInfo(i)
                    if _G.ActionButton_UpdateRangeIndicator and checksRange ~= nil then
                        _G.ActionButton_UpdateRangeIndicator(btn, checksRange, inRange)
                    end
                end
            end
        end
    end)

    sfui.actionbars.ApplyPetBarLayout()
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Vehicle Leave Button (Action Bar 1 Companion)
-- ─────────────────────────────────────────────────────────────────────────────
function sfui.actionbars.GetVehicleExitHotkey()
    local key = (_G.GetBindingKey and _G.GetBindingKey("VEHICLEEXIT"))
        or (_G.GetBindingKey and _G.GetBindingKey("CLICK sfui_ActionBarVehicleLeaveButton:LeftButton"))
    if not key or key == "" then
        return ""
    end
    local KeyBound = _G.LibStub and _G.LibStub("LibKeyBound-1.0", true)
    if KeyBound and KeyBound.ToShortKey then
        return KeyBound:ToShortKey(key)
    elseif sfui.actionbars and sfui.actionbars.style and sfui.actionbars.style.FormatHotkeyText then
        return sfui.actionbars.style.FormatHotkeyText(key)
    end
    return key
end

function sfui.actionbars.UpdateVehicleLeaveHotkey()
    local btn = sfui.actionbars.vehicleLeaveButton
    if not btn or not btn.kb then return end
    btn.kb:SetText(sfui.actionbars.GetVehicleExitHotkey())
end

function sfui.actionbars.UpdateVehicleLeaveButtonLayout()
    local btn = sfui.actionbars.vehicleLeaveButton
    if not btn or (InCombatLockdown and InCombatLockdown()) then return end
    local cfg = sfui.actionbars.GetBarConfig("vehicle")
    local bSize = (cfg and cfg.buttonSize) or 34
    btn:SetSize(bSize, bSize)
    if btn.mover then
        btn.mover:SetSize(bSize, bSize)
    end
end

function sfui.actionbars.CreateVehicleLeaveButton()
    if sfui.actionbars.vehicleLeaveButton then return sfui.actionbars.vehicleLeaveButton end

    local cfg = sfui.actionbars.GetBarConfig("vehicle")
    local buttonSize = (cfg and cfg.buttonSize) or 34

    local btn = _G.MainMenuBarVehicleLeaveButton
    if btn then
        -- Reparent Blizzard's default vehicle exit button directly to UIParent
        btn:SetParent(UIParent)
        sfui.common.set_pixel_snapping(btn)
        btn:SetFrameStrata("MEDIUM")
        btn:SetFrameLevel(25)
        btn:SetSize(buttonSize, buttonSize)
        btn.barKey = "vehicle"
        btn.barConfig = cfg
        btn.commandName = "VEHICLEEXIT"
        if sfui.actionbars.bind and sfui.actionbars.bind.RegisterButton then
            sfui.actionbars.bind.RegisterButton(btn)
        end

        -- 1px black backdrop border to match SFUI theme
        if not btn.borderBackdrop then
            btn.borderBackdrop = btn:CreateTexture(nil, "BACKGROUND")
            btn.borderBackdrop:SetAllPoints()
            btn.borderBackdrop:SetColorTexture(0, 0, 0, 1)
        end

        -- Hotkey text
        if not btn.kb then
            btn.kb = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.kb:SetPoint("TOPRIGHT", -2, -2)
        end
        btn.kb:SetText(sfui.actionbars.GetVehicleExitHotkey())

        -- Enhance CanExitVehicle to recognize passenger seats, VehicleSeatIndicator, and taxis
        local origCanExit = btn.CanExitVehicle
        btn.CanExitVehicle = function(self)
            if _G.CanExitVehicle and _G.CanExitVehicle() then return true end
            if _G.UnitOnTaxi and _G.UnitOnTaxi("player") then return true end
            if _G.VehicleSeatIndicator and _G.VehicleSeatIndicator:IsShown() then return true end
            if _G.UnitInVehicle and _G.UnitInVehicle("player") then return true end
            if _G.UnitControllingVehicle and _G.UnitControllingVehicle("player") then return true end
            if _G.UnitHasVehicleUI and _G.UnitHasVehicleUI("player") then return true end
            if origCanExit then
                local ok, val = pcall(origCanExit, self)
                if ok and val then return true end
            end
            return false
        end

        -- Ensure button updates when VehicleSeatIndicator toggles
        if _G.VehicleSeatIndicator and not sfui.actionbars._hookedSeatIndicator then
            sfui.actionbars._hookedSeatIndicator = true
            hooksecurefunc(_G.VehicleSeatIndicator, "Show", function()
                if btn.Update then btn:Update() end
            end)
            hooksecurefunc(_G.VehicleSeatIndicator, "Hide", function()
                if btn.Update then btn:Update() end
            end)
        end

        -- Register additional vehicle and world events
        btn:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
        btn:RegisterEvent("ACTIONBAR_UPDATE_STATE")
        btn:RegisterEvent("PLAYER_ENTERING_WORLD")

        -- Register mover
        if sfui.actionbars.movers and sfui.actionbars.movers.CreateMover then
            sfui.actionbars.movers.CreateMover(btn, nil, "vehicle")
        end

        -- Initial update
        if btn.Update then
            btn:Update()
        elseif btn.UpdateShownState then
            btn:UpdateShownState()
        end

        sfui.actionbars.vehicleLeaveButton = btn
        sfui.actionbars.barsByKey["vehicle"] = btn
        return btn
    end

    -- Fallback button if MainMenuBarVehicleLeaveButton is unavailable
    local fallbackBtn = CreateFrame("Button", "sfui_VehicleLeaveButton", UIParent, "BackdropTemplate")
    _G.sfui_ActionBarVehicleLeaveButton = fallbackBtn
    sfui.common.set_pixel_snapping(fallbackBtn)
    fallbackBtn:SetFrameStrata("MEDIUM")
    fallbackBtn:SetFrameLevel(25)
    fallbackBtn:SetSize(buttonSize, buttonSize)
    fallbackBtn.barKey = "vehicle"
    fallbackBtn.barConfig = cfg

    fallbackBtn:RegisterForClicks("AnyUp", "AnyDown")
    fallbackBtn:SetScript("OnClick", function()
        if _G.UnitOnTaxi and _G.UnitOnTaxi("player") then
            if _G.TaxiRequestEarlyLanding then _G.TaxiRequestEarlyLanding() end
        else
            if _G.VehicleExit then _G.VehicleExit() end
        end
    end)

    fallbackBtn.borderBackdrop = fallbackBtn:CreateTexture(nil, "BACKGROUND")
    fallbackBtn.borderBackdrop:SetAllPoints()
    fallbackBtn.borderBackdrop:SetColorTexture(0, 0, 0, 1)

    fallbackBtn.icon = fallbackBtn:CreateTexture(nil, "ARTWORK")
    fallbackBtn.icon:SetTexCoord(0.140625, 0.859375, 0.140625, 0.859375)
    fallbackBtn.icon:SetPoint("TOPLEFT", fallbackBtn, "TOPLEFT", 1, -1)
    fallbackBtn.icon:SetPoint("BOTTOMRIGHT", fallbackBtn, "BOTTOMRIGHT", -1, 1)
    fallbackBtn.icon:SetTexture("Interface\\Vehicles\\UI-Vehicles-Button-Exit-Up")

    fallbackBtn.kb = fallbackBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fallbackBtn.kb:SetPoint("TOPRIGHT", -2, -2)
    fallbackBtn.kb:SetText(sfui.actionbars.GetVehicleExitHotkey())

    function fallbackBtn:UpdateShownState()
        local canExit = (_G.CanExitVehicle and _G.CanExitVehicle())
            or (_G.UnitOnTaxi and _G.UnitOnTaxi("player"))
            or (_G.VehicleSeatIndicator and _G.VehicleSeatIndicator:IsShown())
            or (_G.UnitInVehicle and _G.UnitInVehicle("player"))
        self:SetShown(self.isInEditMode or canExit)
    end
    function fallbackBtn:Update()
        self:UpdateShownState()
    end

    if sfui.actionbars.movers and sfui.actionbars.movers.CreateMover then
        sfui.actionbars.movers.CreateMover(fallbackBtn, nil, "vehicle")
    end
    fallbackBtn:UpdateShownState()

    sfui.actionbars.vehicleLeaveButton = fallbackBtn
    sfui.actionbars.barsByKey["vehicle"] = fallbackBtn
    return fallbackBtn
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Bar Creation & Engine Initialization
-- ─────────────────────────────────────────────────────────────────────────────
function sfui.actionbars.CreateBars()
    local LAB = LibStub and LibStub("LibActionButton-1.0", true)
    if not LAB then
        if sfui.common and sfui.common.print then
            sfui.common.print("warning: LibActionButton-1.0 not found.")
        end
        return
    end

    local modCfg = (sfui.db and sfui.db.Get and sfui.db.Get("actionbars")) or (sfui.config and sfui.config.actionbars) or {}

    -- Dynamic slot grid sync when actions are dragged or updated
    if not sfui.actionbars._labCallbacksRegistered and LAB.RegisterCallback then
        sfui.actionbars._labCallbacksRegistered = true
        local function on_button_changed(_, button)
            if sfui.actionbars.style and sfui.actionbars.style.UpdateGrid then
                sfui.actionbars.style.UpdateGrid(button)
            end
        end
        LAB.RegisterCallback(sfui.actionbars, "OnButtonUpdate", on_button_changed)
        LAB.RegisterCallback(sfui.actionbars, "OnButtonContentsChanged", on_button_changed)
    end

    for barIndex = 1, 10 do
        local barKey = "bar" .. tostring(barIndex)
        local barName = "sfui_ActionBar" .. barIndex
        local bar = CreateFrame("Frame", barName, UIParent, "SecureHandlerStateTemplate")
        sfui.common.set_pixel_snapping(bar)
        bar.barIndex = barIndex
        bar.barKey = barKey
        bar.buttons = {}

        local barCfg = sfui.actionbars.GetBarConfig(barKey)
        bar.barConfig = barCfg

        -- Generate 12 buttons per bar
        for i = 1, 12 do
            local buttonName = format("sfui_ActionBar%d_Button%d", barIndex, i)
            local btnCfg = {
                actionButtonUI = true, -- connects to modern C_ActionBar for procs & overlays
                outOfRangeColoring = modCfg.outOfRangeColoring or "button",
                showGrid = modCfg.showGrid or false,
                hideElements = {
                    macro = not modCfg.showMacroNames,
                    hotkey = not modCfg.showHotkeys,
                },
            }

            -- Set keybind targets from the action page this bar displays (slot = (barIndex - 1) * 12 + i).
            -- Blizzard bindings fire the slots of their own page, so only that page's binding is valid here:
            --   page 1 (1-12)  ACTIONBUTTON        page 3 (25-36) MULTIACTIONBAR3 (right)
            --   page 4 (37-48) MULTIACTIONBAR4     page 5 (49-60) MULTIACTIONBAR2 (bottom right)
            --   page 6 (61-72) MULTIACTIONBAR1 (bottom left / "action bar 2")
            --   page 2 (13-24) has no blizzard binding (click binding only)
            local candidateTargets = {}
            local pageBinding = PAGE_BINDING_PREFIX[barIndex]
            if pageBinding then
                table.insert(candidateTargets, pageBinding .. i)
            end
            table.insert(candidateTargets, "CLICK " .. buttonName .. ":LeftButton")
            btnCfg.keyBoundTarget = candidateTargets[1]

            local button = LAB:CreateButton(i, buttonName, bar, btnCfg)
            button.barIndex = barIndex
            button.buttonIndex = i
            button.commandName = candidateTargets[1]
            button._sfuiBindingTargets = candidateTargets

            if sfui.actionbars.bind and sfui.actionbars.bind.RegisterButton then
                sfui.actionbars.bind.RegisterButton(button)
            end

            local isLocked = sfui.actionbars.AreButtonsLocked()
            button:SetAttribute("buttonlock", isLocked or nil)
            button:SetAttribute("unlockedpreventdrag", true)

            -- Custom GetHotkey to resolve key from candidate targets
            button.GetHotkey = function(self)
                local targets = self._sfuiBindingTargets
                if targets then
                    for _, target in ipairs(targets) do
                        local key = _G.GetBindingKey(target)
                        if key then
                            local KeyBound = _G.LibStub and _G.LibStub("LibKeyBound-1.0", true)
                            if KeyBound and KeyBound.ToShortKey then
                                return KeyBound:ToShortKey(key)
                            elseif sfui.actionbars and sfui.actionbars.style and sfui.actionbars.style.FormatHotkeyText then
                                return sfui.actionbars.style.FormatHotkeyText(key)
                            end
                            return key
                        end
                    end
                end
                local name = ("CLICK %s:%s"):format(self:GetName(), (self.config and self.config.keyBoundClickButton) or "LeftButton")
                local key = _G.GetBindingKey((self.config and self.config.keyBoundTarget) or name)
                if not key and self.config and self.config.keyBoundTarget then
                    key = _G.GetBindingKey(name)
                end
                if key then
                    local KeyBound = _G.LibStub and _G.LibStub("LibKeyBound-1.0", true)
                    if KeyBound and KeyBound.ToShortKey then
                        return KeyBound:ToShortKey(key)
                    elseif sfui.actionbars and sfui.actionbars.style and sfui.actionbars.style.FormatHotkeyText then
                        return sfui.actionbars.style.FormatHotkeyText(key)
                    end
                    return key
                end
            end

            -- State and Action Mapping
            if barIndex == 1 then
                -- Bar 1: Paging across 18 pages (stances, forms, possess, vehicle, bar pages)
                for page = 1, 18 do
                    local slot = (page - 1) * 12 + i
                    button:SetState(page, "action", slot)
                end
                local overrideIndex = (_G.GetOverrideBarIndex and _G.GetOverrideBarIndex()) or 14
                button:SetState("possess", "action", (12 - 1) * 12 + i)
                button:SetState("override", "action", (overrideIndex - 1) * 12 + i)
                button:SetState(0, "action", i)
            else
                -- Bars 2-10: Standard action bar pages
                local slot = (barIndex - 1) * 12 + i
                button:SetState(0, "action", slot)
            end

            -- Skinning with 1px border, cropping, and tactile press animation
            if sfui.actionbars.style and sfui.actionbars.style.SkinButton then
                sfui.actionbars.style.SkinButton(button)
            end

            bar.buttons[i] = button
        end

        -- Setup Bar 1 Stance / Form / Possess / Vehicle Paging
        if barIndex == 1 and sfui.actionbars.paging and sfui.actionbars.paging.SetupBar1Paging then
            sfui.actionbars.paging.SetupBar1Paging(bar)
        end

        -- Create draggable mover
        if sfui.actionbars.movers and sfui.actionbars.movers.CreateMover then
            sfui.actionbars.movers.CreateMover(bar, barIndex, barKey)
        end

        -- Hook mouseover fader
        if sfui.actionbars.mouseover and sfui.actionbars.mouseover.HookBar then
            sfui.actionbars.mouseover.HookBar(bar)
        end

        sfui.actionbars.bars[barIndex] = bar
        sfui.actionbars.barsByKey[barKey] = bar

        -- Apply initial 3x4 layout
        sfui.actionbars.ApplyBarLayout(barIndex)
    end

    -- Create Pet Bar
    sfui.actionbars.CreatePetBar()

    -- Create Vehicle Leave Button
    sfui.actionbars.CreateVehicleLeaveButton()

    -- Synchronize and override all hardware keybindings
    sfui.actionbars.UpdateAllBindings()

    -- Synchronize button lock state and CVars
    sfui.actionbars.SetButtonsLocked(sfui.actionbars.AreButtonsLocked())
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Hardware Keybinding Override & Routing Engine (ElvUI Pattern)
-- ─────────────────────────────────────────────────────────────────────────────
local SetOverrideBindingClick = _G.SetOverrideBindingClick
local ClearOverrideBindings   = _G.ClearOverrideBindings
local GetBindingKey           = _G.GetBindingKey

function sfui.actionbars.OverrideBarBindings(bar)
    if InCombatLockdown and InCombatLockdown() then return end
    if not bar or not bar.buttons or not SetOverrideBindingClick then return end

    if bar == sfui.actionbars.petBar then
        if ClearOverrideBindings then
            ClearOverrideBindings(bar)
        end
        return
    end

    for _, button in ipairs(bar.buttons) do
        if button and button.GetName then
            local targets = button._sfuiBindingTargets
            if targets then
                for _, target in ipairs(targets) do
                    local keys = { GetBindingKey(target) }
                    for _, key in ipairs(keys) do
                        if key and key ~= "" then
                            SetOverrideBindingClick(bar, false, key, button:GetName(), "LeftButton")
                        end
                    end
                end
            elseif button.keyBoundTarget then
                local keys = { GetBindingKey(button.keyBoundTarget) }
                for _, key in ipairs(keys) do
                    if key and key ~= "" then
                        SetOverrideBindingClick(bar, false, key, button:GetName(), "LeftButton")
                    end
                end
            end
        end
    end
end

function sfui.actionbars.UpdateAllBindings()
    if InCombatLockdown and InCombatLockdown() then
        sfui.actionbars._needsUpdateBindings = true
        return
    end
    sfui.actionbars._needsUpdateBindings = nil

    local allBars = sfui.actionbars.GetAllBars and sfui.actionbars.GetAllBars()
    if allBars and ClearOverrideBindings then
        for _, bar in ipairs(allBars) do
            if bar then
                ClearOverrideBindings(bar)
                if bar:IsShown() then
                    sfui.actionbars.OverrideBarBindings(bar)
                end
            end
        end
    end

    if sfui.actionbars.UpdatePetHotkeys then
        sfui.actionbars.UpdatePetHotkeys()
    elseif sfui.actionbars.UpdatePetBar then
        sfui.actionbars.UpdatePetBar()
    end

    if sfui.actionbars.UpdateVehicleLeaveHotkey then
        sfui.actionbars.UpdateVehicleLeaveHotkey()
    end
end

-- Hook binding updates and combat regen
local function OnBindingEvent(event)
    if sfui.actionbars.HookPetActionBar then
        sfui.actionbars.HookPetActionBar()
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if sfui.actionbars._needsUpdateBindings then
            sfui.actionbars.UpdateAllBindings()
        end
    else
        sfui.actionbars.UpdateAllBindings()
    end
end

if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("UPDATE_BINDINGS", OnBindingEvent)
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", OnBindingEvent)
    sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", OnBindingEvent)
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Keydown & Keyup Animation Hooks for Blizzard Bindings
-- ─────────────────────────────────────────────────────────────────────────────
-- Blizzard multibar -> sfui bar showing the same action page (see PAGE_BINDING_PREFIX)
local barNameMap = {
    MultiBarBottomLeft = 6,  -- page 6 (MULTIACTIONBAR1BUTTON)
    MultiBarBottomRight = 5, -- page 5 (MULTIACTIONBAR2BUTTON)
    MultiBarRight = 3,       -- page 3 (MULTIACTIONBAR3BUTTON)
    MultiBarLeft = 4,        -- page 4 (MULTIACTIONBAR4BUTTON)
    MultiBar6 = 7,           -- MultiBar6 (bar 7)
    MultiBar7 = 8,           -- MultiBar7 (bar 8)
}

if hooksecurefunc then
    if type(_G.ActionButtonDown) == "function" then
        hooksecurefunc("ActionButtonDown", function(id)
            local bar = sfui.actionbars.bars and sfui.actionbars.bars[1]
            local btn = bar and bar.buttons and bar.buttons[id]
            if btn and btn.AnimateDown then
                btn:AnimateDown()
            end
            if sfui.vehicle and sfui.vehicle.AnimateButtonDown then
                sfui.vehicle.AnimateButtonDown(id)
            end
        end)
    end

    if type(_G.ActionButtonUp) == "function" then
        hooksecurefunc("ActionButtonUp", function(id)
            local bar = sfui.actionbars.bars and sfui.actionbars.bars[1]
            local btn = bar and bar.buttons and bar.buttons[id]
            if btn and btn.AnimateUp then
                btn:AnimateUp()
            end
            if sfui.vehicle and sfui.vehicle.AnimateButtonUp then
                sfui.vehicle.AnimateButtonUp(id)
            end
        end)
    end

    if type(_G.MultiActionButtonDown) == "function" then
        hooksecurefunc("MultiActionButtonDown", function(barName, id)
            local barIdx = barNameMap[barName]
            local bar = barIdx and sfui.actionbars.bars and sfui.actionbars.bars[barIdx]
            local btn = bar and bar.buttons and bar.buttons[id]
            if btn and btn.AnimateDown then
                btn:AnimateDown()
            end
        end)
    end

    if type(_G.MultiActionButtonUp) == "function" then
        hooksecurefunc("MultiActionButtonUp", function(barName, id)
            local barIdx = barNameMap[barName]
            local bar = barIdx and sfui.actionbars.bars and sfui.actionbars.bars[barIdx]
            local btn = bar and bar.buttons and bar.buttons[id]
            if btn and btn.AnimateUp then
                btn:AnimateUp()
            end
        end)
    end

    if type(_G.VehicleExit) == "function" then
        hooksecurefunc("VehicleExit", function()
            local btn = sfui.actionbars.vehicleLeaveButton
            if btn and btn.AnimateDown then
                btn:AnimateDown()
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0.1, function()
                        if btn.AnimateUp then btn:AnimateUp() end
                    end)
                end
            end
            if sfui.vehicle and sfui.vehicle.exitButton and sfui.vehicle.exitButton.AnimateDown then
                sfui.vehicle.exitButton:AnimateDown()
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0.1, function()
                        if sfui.vehicle.exitButton.AnimateUp then sfui.vehicle.exitButton:AnimateUp() end
                    end)
                end
            end
        end)
    end

    if type(_G.TaxiRequestEarlyLanding) == "function" then
        hooksecurefunc("TaxiRequestEarlyLanding", function()
            local btn = sfui.actionbars.vehicleLeaveButton
            if btn and btn.AnimateDown then
                btn:AnimateDown()
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0.1, function()
                        if btn.AnimateUp then btn:AnimateUp() end
                    end)
                end
            end
            if sfui.vehicle and sfui.vehicle.exitButton and sfui.vehicle.exitButton.AnimateDown then
                sfui.vehicle.exitButton:AnimateDown()
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0.1, function()
                        if sfui.vehicle.exitButton.AnimateUp then sfui.vehicle.exitButton:AnimateUp() end
                    end)
                end
            end
        end)
    end

    local hookedPetBar = false
    local function TryHookPetActionBar()
        if hookedPetBar then return end

        if _G.PetActionBar and type(_G.PetActionBar.PetActionButtonDown) == "function" then
            hookedPetBar = true
            hooksecurefunc(_G.PetActionBar, "PetActionButtonDown", function(_, id)
                local bar = sfui.actionbars.petBar
                local btn = bar and bar.buttons and bar.buttons[id]
                if btn and btn.AnimateDown then
                    btn:AnimateDown()
                end
            end)
            hooksecurefunc(_G.PetActionBar, "PetActionButtonUp", function(_, id)
                local bar = sfui.actionbars.petBar
                local btn = bar and bar.buttons and bar.buttons[id]
                if btn and btn.AnimateUp then
                    btn:AnimateUp()
                end
            end)
        elseif _G.PetActionBarMixin and type(_G.PetActionBarMixin.PetActionButtonDown) == "function" then
            hookedPetBar = true
            hooksecurefunc(_G.PetActionBarMixin, "PetActionButtonDown", function(_, id)
                local bar = sfui.actionbars.petBar
                local btn = bar and bar.buttons and bar.buttons[id]
                if btn and btn.AnimateDown then
                    btn:AnimateDown()
                end
            end)
            hooksecurefunc(_G.PetActionBarMixin, "PetActionButtonUp", function(_, id)
                local bar = sfui.actionbars.petBar
                local btn = bar and bar.buttons and bar.buttons[id]
                if btn and btn.AnimateUp then
                    btn:AnimateUp()
                end
            end)
        elseif type(_G.PetActionButtonDown) == "function" then
            hookedPetBar = true
            hooksecurefunc("PetActionButtonDown", function(id)
                local bar = sfui.actionbars.petBar
                local btn = bar and bar.buttons and bar.buttons[id]
                if btn and btn.AnimateDown then
                    btn:AnimateDown()
                end
            end)
            hooksecurefunc("PetActionButtonUp", function(id)
                local bar = sfui.actionbars.petBar
                local btn = bar and bar.buttons and bar.buttons[id]
                if btn and btn.AnimateUp then
                    btn:AnimateUp()
                end
            end)
        end
    end

    sfui.actionbars.HookPetActionBar = TryHookPetActionBar
    TryHookPetActionBar()
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Dynamic Spell Activation Overlay Glow Listener
--  Routes proc glows through sfui.events and LibCustomGlow without private frames.
-- ─────────────────────────────────────────────────────────────────────────────
if sfui.events and sfui.events.RegisterEvent then
    local function on_overlay_glow(event, spellID)
        local bars = sfui.actionbars.bars
        if not bars or not spellID then return end
        local isShow = (event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
        local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

        for barIdx = 1, 10 do
            local bar = bars[barIdx]
            if bar and bar:IsShown() and bar.buttons then
                for btnIdx = 1, #bar.buttons do
                    local btn = bar.buttons[btnIdx]
                    if btn and btn:HasAction() then
                        local btnSpellId = btn.GetSpellId and btn:GetSpellId()
                        if btnSpellId and btnSpellId == spellID then
                            if isShow then
                                if LCG and LCG.ButtonGlow_Start then
                                    LCG.ButtonGlow_Start(btn)
                                end
                            else
                                if LCG and LCG.ButtonGlow_Stop then
                                    LCG.ButtonGlow_Stop(btn)
                                end
                            end
                            if btn.UpdateOverlayGlow then
                                btn:UpdateOverlayGlow()
                            end
                        end
                    end
                end
            end
        end
    end

    sfui.events.RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", on_overlay_glow)
    sfui.events.RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", on_overlay_glow)

    local function on_pet_event(event, arg1)
        if (event == "UNIT_FLAGS" and arg1 ~= "pet") or (event == "UNIT_PET" and arg1 ~= "player") then
            return
        end
        if event == "PET_BAR_UPDATE_COOLDOWN" then
            if sfui.actionbars.UpdatePetCooldowns then
                sfui.actionbars.UpdatePetCooldowns()
            end
            return
        elseif event == "PET_BAR_UPDATE_USABLE" then
            if sfui.actionbars.UpdatePetUsable then
                sfui.actionbars.UpdatePetUsable()
            end
            return
        end
        if sfui.actionbars.RequestPetBarUpdate then
            sfui.actionbars.RequestPetBarUpdate()
        elseif sfui.actionbars.UpdatePetBar then
            sfui.actionbars.UpdatePetBar()
        end
    end
    sfui.events.RegisterEvent("PET_BAR_UPDATE", on_pet_event)
    sfui.events.RegisterEvent("PET_UI_UPDATE", on_pet_event)
    sfui.events.RegisterEvent("UNIT_PET", on_pet_event)
    sfui.events.RegisterEvent("UNIT_FLAGS", on_pet_event)
    sfui.events.RegisterEvent("PET_BAR_UPDATE_COOLDOWN", on_pet_event)
    sfui.events.RegisterEvent("PET_BAR_UPDATE_USABLE", on_pet_event)
    sfui.events.RegisterEvent("PLAYER_CONTROL_LOST", on_pet_event)
    sfui.events.RegisterEvent("PLAYER_CONTROL_GAINED", on_pet_event)
    sfui.events.RegisterEvent("PLAYER_FARSIGHT_FOCUS_CHANGED", on_pet_event)
    sfui.events.RegisterEvent("SPELLS_CHANGED", on_pet_event)
    sfui.events.RegisterEvent("UPDATE_VEHICLE_ACTIONBAR", on_pet_event)
end
