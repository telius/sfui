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
        return SfuiDB.actionbars.bars[barKey]
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
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Pet Bar Layout & Creation
-- ─────────────────────────────────────────────────────────────────────────────
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

                local modCfg = (sfui.db and sfui.db.Get and sfui.db.Get("actionbars")) or (sfui.config and sfui.config.actionbars) or {}
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
    bar.barKey = "pet"
    bar.buttons = {}
    sfui.actionbars.petBar = bar
    sfui.actionbars.barsByKey["pet"] = bar

    -- Gather PetActionButton1 through PetActionButton10
    for i = 1, 10 do
        local btn = _G["PetActionButton" .. i]
        if btn then
            btn:SetParent(bar)
            bar.buttons[i] = btn
            if sfui.actionbars.style and sfui.actionbars.style.SkinButton then
                sfui.actionbars.style.SkinButton(btn)
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

    sfui.actionbars.ApplyPetBarLayout()
end

-- ─────────────────────────────────────────────────────────────────────────────
--  3x4 Grid Preset Helper
-- ─────────────────────────────────────────────────────────────────────────────
function sfui.actionbars.Apply3x4Preset(barIndex)
    local barKey = "bar" .. tostring(barIndex)
    if SfuiDB and SfuiDB.actionbars and SfuiDB.actionbars.bars and SfuiDB.actionbars.bars[barKey] then
        local cfg = SfuiDB.actionbars.bars[barKey]
        cfg.buttons = 12
        cfg.buttonsPerRow = 3
        cfg.buttonSize = 28
        cfg.spacing = 4
    end
    sfui.actionbars.ApplyBarLayout(barIndex)
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
            button._sfuiBindingTargets = candidateTargets

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
                -- Bar 1: Paging across 14 pages (stances, forms, possess, vehicle, bar pages)
                for page = 1, 14 do
                    local slot = (page - 1) * 12 + i
                    button:SetState(page, "action", slot)
                end
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

    -- Synchronize and override all hardware keybindings
    sfui.actionbars.UpdateAllBindings()
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Hardware Keybinding Override & Routing Engine (ElvUI Pattern)
-- ─────────────────────────────────────────────────────────────────────────────
local SetOverrideBindingClick = _G.SetOverrideBindingClick
local ClearOverrideBindings   = _G.ClearOverrideBindings
local GetBindingKey           = _G.GetBindingKey

function sfui.actionbars.OverrideBarBindings(bar)
    if not bar or not bar.buttons or not SetOverrideBindingClick then return end

    if bar == sfui.actionbars.petBar then
        for i = 1, 10 do
            local btn = bar.buttons[i]
            if btn and btn.GetName then
                local keys = { GetBindingKey("BONUSACTIONBUTTON" .. i) }
                for _, key in ipairs(keys) do
                    if key and key ~= "" then
                        SetOverrideBindingClick(bar, false, key, btn:GetName(), "LeftButton")
                    end
                end
            end
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
end

-- Hook binding updates and combat regen
local function OnBindingEvent(event)
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
        end)
    end

    if type(_G.ActionButtonUp) == "function" then
        hooksecurefunc("ActionButtonUp", function(id)
            local bar = sfui.actionbars.bars and sfui.actionbars.bars[1]
            local btn = bar and bar.buttons and bar.buttons[id]
            if btn and btn.AnimateUp then
                btn:AnimateUp()
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

    local function on_pet_update()
        local bar = sfui.actionbars.petBar
        if bar and bar.buttons then
            for i = 1, #bar.buttons do
                local btn = bar.buttons[i]
                if btn and sfui.actionbars.style and sfui.actionbars.style.UpdateGrid then
                    sfui.actionbars.style.UpdateGrid(btn)
                end
            end
        end
    end
    sfui.events.RegisterEvent("PET_BAR_UPDATE", on_pet_update)
    sfui.events.RegisterEvent("PET_UI_UPDATE", on_pet_update)
end
