local addonName, addon   = ...
local _addonName, _addon = addonName, addon

sfui                     = sfui or {}
sfui.hide                = sfui.hide or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/hide.lua
--  Blizzard Unit & HUD Frame Suppression & UI Error Filtering
--
--  Supports: Retail (Midnight 12.x / TWW 11.x), Camelot (Classic Forever),
--  and Classic Era.
--
--  Features:
--  - Safe Frame Suppression: Uses SetAlpha(0) and EnableMouse(false).
--    Never calls :Hide() inside OnShow hooks to guarantee 100% taint-free execution.
--  - Error Frame Filtering: Suppresses repetitive "spell is not ready yet" spam.
-- ══════════════════════════════════════════════════════════════════════════════

-- Localized APIs
local _G                 = _G
local InCombatLockdown   = _G.InCombatLockdown
local pairs              = _G.pairs
local ipairs             = _G.ipairs
local type               = _G.type
local pcall              = _G.pcall
local table_insert       = table.insert
local hooksecurefunc     = _G.hooksecurefunc
local CreateFrame        = _G.CreateFrame
local UIParent           = _G.UIParent
local GetTime            = _G.GetTime

-- Action Bars One-Time Alpha Recovery (ensures bars are 100% visible and untouched)
local ACTION_BAR_NAMES   = {
    "MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight",
    "MultiBarRight", "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7",
    "PetActionBar", "PetActionBarFrame", "StanceBar", "StanceBarFrame",
    "ShapeshiftBarFrame", "PossessActionBar", "PossessBarFrame",
}

local function RestoreAllBarsAlpha()
    if InCombatLockdown and InCombatLockdown() then return end
    local abMod = sfui.config and sfui.config.actionbars
    if SfuiDB and SfuiDB.actionbars and SfuiDB.actionbars.enabled ~= nil then
        if SfuiDB.actionbars.enabled then return end
    elseif abMod and abMod.enabled then
        return
    end
    for _, name in ipairs(ACTION_BAR_NAMES) do
        local bar = _G[name]
        if bar and bar.SetAlpha and bar.GetAlpha and bar:GetAlpha() ~= 1.0 then
            bar:SetAlpha(1.0)
        end
    end
end
sfui.hide.RefreshActionBars = RestoreAllBarsAlpha

-- Unit & HUD Frame Permanent Suppression Configurations
local HIDE_FRAMES           = {
    { key = "hide_player_frame", name = "PlayerFrame",        unit = "player",                                       label = "Player Frame" },
    { key = "hide_target_frame", name = "TargetFrame",        unit = "target",                                       label = "Target Frame" },
    { key = "hide_pet_frame",    name = "PetFrame",           unit = "pet",                                          label = "Pet Frame" },
    { key = "hide_focus_frame",  name = "FocusFrame",         unit = "focus",                                        label = "Focus Frame" },
    { key = "hide_micromenu",    name = "MicroMenuContainer", altNames = { "MicroMenu", "MainMenuBarMicroButtons" }, label = "Game Menu (Micro Menu)" },
    { key = "hide_bagsbar",      name = "BagsBar",            altNames = { "MainMenuBarBagButtons" },                label = "Bags Bar" },
    { key = "hide_totem_bar",    name = "TotemFrame",         altNames = { "MultiCastActionBarFrame", "TotemBar" },  label = "Totem Bar",             noAutoShow = true },
}

local defaults              = {
    hide_player_frame    = false,
    hide_target_frame    = false,
    hide_pet_frame       = false,
    hide_focus_frame     = false,
    hide_micromenu       = false,
    hide_bagsbar         = false,
    hide_totem_bar       = false,
    hide_cooldown_errors = true,
}

local function InitDB()
    SfuiDB = SfuiDB or {}
    for k, v in pairs(defaults) do
        if SfuiDB[k] == nil then
            SfuiDB[k] = v
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Blizzard Unit & HUD Frames Permanent Suppression (Taint-Free Alpha Pattern)
-- ─────────────────────────────────────────────────────────────────────────────
local HiddenFrame = CreateFrame("Frame", nil, UIParent)
HiddenFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 0, -10000)
HiddenFrame:SetSize(1, 1)
HiddenFrame:Hide()
sfui.hide.HiddenFrame = HiddenFrame

local function GetFramesForEntry(entry)
    local list = {}
    if entry.name and _G[entry.name] then
        table_insert(list, _G[entry.name])
    end
    if entry.altNames then
        for _, n in ipairs(entry.altNames) do
            local f = _G[n]
            if f and f ~= _G[entry.name] then
                table_insert(list, f)
            end
        end
    elseif entry.altName and _G[entry.altName] and _G[entry.altName] ~= _G[entry.name] then
        table_insert(list, _G[entry.altName])
    end
    return list
end

local hookedMultiCast = false
local hookedBarsAndMenu = false
local _savedFrameState = setmetatable({}, { __mode = "k" })
local _hookedOffscreen = setmetatable({}, { __mode = "k" })
local _inOffscreenMove = setmetatable({}, { __mode = "k" })
local _suppressedBySfui = setmetatable({}, { __mode = "k" })

local MICRO_BUTTON_NAMES = {
    "CharacterMicroButton", "ProfessionMicroButton", "PlayerSpellsMicroButton",
    "SpellbookMicroButton", "TalentMicroButton", "AchievementMicroButton",
    "LegacyMicroButton", "QuestLogMicroButton", "HousingMicroButton",
    "GuildMicroButton", "SocialsMicroButton", "WorldMapMicroButton",
    "LFDMicroButton", "LFGMicroButton", "CollectionsMicroButton",
    "EJMicroButton", "HelpMicroButton", "StoreMicroButton",
    "MainMenuMicroButton", "HelpOpenWebTicketButton",
}

local BAG_BUTTON_NAMES = {
    "MainMenuBarBackpackButton", "BagBarExpandToggle", "BagSlotCluster",
    "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
    "CharacterBag3Slot", "CharacterReagentBag0Slot", "KeyRingButton",
}

local function ShouldHide(key)
    if not SfuiDB then return false end
    if key == "hide_target_frame" then
        return (SfuiDB.hide_target_frame == true) or (SfuiDB.enableTargetBar ~= false)
    end
    return SfuiDB[key] == true
end

local function SilenceSelection(selection)
    if not selection then return end
    if selection.SetAlpha then selection:SetAlpha(0) end
    if selection.EnableMouse then selection:EnableMouse(false) end
    if selection.EnableMouseClicks then selection:EnableMouseClicks(false) end
    if selection.EnableMouseMotion then selection:EnableMouseMotion(false) end
end

local function SaveFrameState(frame)
    if not frame or _savedFrameState[frame] then return end
    local parent = frame.GetParent and frame:GetParent() or UIParent
    if parent == HiddenFrame then return end
    local points = {}
    if frame.GetNumPoints and frame.GetPoint then
        for i = 1, frame:GetNumPoints() do
            local p, rel, rp, x, y = frame:GetPoint(i)
            if p and y ~= -10000 then
                points[#points + 1] = { p, rel or UIParent, rp or p, x or 0, y or 0 }
            end
        end
    end
    _savedFrameState[frame] = {
        parent = parent,
        points = points,
    }
end

local function SilenceOrRestoreButton(btn, suppressed, reparentToHidden)
    if not btn then return end
    local isProtected = btn.IsProtected and btn:IsProtected()
    if suppressed then
        SaveFrameState(btn)
        if btn.SetAlpha and (not btn.GetAlpha or btn:GetAlpha() ~= 0) then
            btn:SetAlpha(0)
        end
        if not isProtected and not (InCombatLockdown and InCombatLockdown()) then
            if btn.EnableMouse then pcall(btn.EnableMouse, btn, false) end
            if btn.EnableMouseClicks then pcall(btn.EnableMouseClicks, btn, false) end
            if btn.EnableMouseMotion then pcall(btn.EnableMouseMotion, btn, false) end
            if reparentToHidden and btn.SetParent and btn:GetParent() ~= HiddenFrame then
                pcall(btn.SetParent, btn, HiddenFrame)
            end
        end
    else
        if btn.GetAlpha and btn:GetAlpha() ~= 1.0 then
            btn:SetAlpha(1.0)
        end
        if not isProtected and not (InCombatLockdown and InCombatLockdown()) then
            local saved = _savedFrameState[btn]
            if reparentToHidden and saved and saved.parent and btn.SetParent and btn:GetParent() == HiddenFrame then
                pcall(btn.SetParent, btn, saved.parent)
            end
            if btn.EnableMouse then pcall(btn.EnableMouse, btn, true) end
            if btn.EnableMouseClicks then pcall(btn.EnableMouseClicks, btn, true) end
            if btn.EnableMouseMotion then pcall(btn.EnableMouseMotion, btn, true) end
        end
    end
end

local function UpdateBarChildren(key, suppressed)
    if key == "hide_micromenu" then
        local reparentButtons = (_G.MicroMenuContainer == nil and _G.MicroMenu == nil)
        for _, name in ipairs(MICRO_BUTTON_NAMES) do
            SilenceOrRestoreButton(_G[name], suppressed, reparentButtons)
        end
        local mm = _G.MicroMenu
        if mm and mm.GetChildren then
            for _, child in ipairs({ mm:GetChildren() }) do
                SilenceOrRestoreButton(child, suppressed, false)
            end
        end
    elseif key == "hide_bagsbar" then
        for _, name in ipairs(BAG_BUTTON_NAMES) do
            SilenceOrRestoreButton(_G[name], suppressed, false)
        end
        local bb = _G.BagsBar
        if bb and bb.GetChildren then
            for _, child in ipairs({ bb:GetChildren() }) do
                SilenceOrRestoreButton(child, suppressed, false)
            end
        end
        local cluster = _G.BagSlotCluster
        if cluster and cluster.GetChildren then
            for _, child in ipairs({ cluster:GetChildren() }) do
                SilenceOrRestoreButton(child, suppressed, false)
            end
        end
    end
end

local function ParkFrameOffscreen(frame, key)
    if not frame or (InCombatLockdown and InCombatLockdown()) then return end
    if _inOffscreenMove[frame] then return end
    _inOffscreenMove[frame] = true

    SaveFrameState(frame)

    if frame == _G.MicroMenuContainer and not ShouldHide("hide_bagsbar") then
        local bags = _G.BagsBar
        if bags and bags.GetNumPoints and bags.GetPoint and bags.GetLeft and bags.GetBottom then
            for i = 1, bags:GetNumPoints() do
                local _, rel = bags:GetPoint(i)
                if rel == frame then
                    local l, b = bags:GetLeft(), bags:GetBottom()
                    if l and b and b > -1000 then
                        bags:ClearAllPoints()
                        bags:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
                    end
                    break
                end
            end
        end
    end

    if frame.SetAlpha and (not frame.GetAlpha or frame:GetAlpha() ~= 0) then
        frame:SetAlpha(0)
    end
    local isProtected = frame.IsProtected and frame:IsProtected()
    local isChildMicroMenu = (frame == _G.MicroMenu and _G.MicroMenuContainer ~= nil)
    if not isProtected then
        if frame.EnableMouse then pcall(frame.EnableMouse, frame, false) end
        if frame.EnableMouseClicks then pcall(frame.EnableMouseClicks, frame, false) end
        if frame.EnableMouseMotion then pcall(frame.EnableMouseMotion, frame, false) end
        if isChildMicroMenu then
            if frame.SetParent and frame:GetParent() ~= _G.MicroMenuContainer then
                pcall(frame.SetParent, frame, _G.MicroMenuContainer)
            end
        else
            if frame.SetParent and frame:GetParent() ~= HiddenFrame then
                pcall(frame.SetParent, frame, HiddenFrame)
            end
            if frame.ClearAllPoints and frame.SetPoint then
                pcall(frame.ClearAllPoints, frame)
                pcall(frame.SetPoint, frame, "TOPLEFT", HiddenFrame, "TOPLEFT", 0, -10000)
            end
        end
    end
    if frame.Selection then
        SilenceSelection(frame.Selection)
    end

    if key and hooksecurefunc and not _hookedOffscreen[frame] then
        _hookedOffscreen[frame] = key
        if not isChildMicroMenu and frame.SetPoint then
            hooksecurefunc(frame, "SetPoint", function(self)
                if _inOffscreenMove[self] or not ShouldHide(key) then return end
                if InCombatLockdown and InCombatLockdown() then return end
                ParkFrameOffscreen(self, key)
            end)
        end
        if frame.SetParent then
            hooksecurefunc(frame, "SetParent", function(self, parent)
                if _inOffscreenMove[self] or not ShouldHide(key) then return end
                if parent == HiddenFrame or (self == _G.MicroMenu and parent == _G.MicroMenuContainer) then return end
                if InCombatLockdown and InCombatLockdown() then return end
                ParkFrameOffscreen(self, key)
            end)
        end
        if frame.Show then
            hooksecurefunc(frame, "Show", function(self)
                if _inOffscreenMove[self] or not ShouldHide(key) then return end
                if InCombatLockdown and InCombatLockdown() then return end
                ParkFrameOffscreen(self, key)
            end)
        end
    end

    _inOffscreenMove[frame] = nil
end

local function RestoreFrameFromOffscreen(frame, key)
    if not frame or (InCombatLockdown and InCombatLockdown()) then return end
    _inOffscreenMove[frame] = true

    local saved = _savedFrameState[frame]
    local isProtected = frame.IsProtected and frame:IsProtected()
    if not isProtected then
        if saved and saved.parent and frame.SetParent and frame:GetParent() == HiddenFrame then
            pcall(frame.SetParent, frame, saved.parent)
        elseif frame.SetParent and frame:GetParent() == HiddenFrame then
            local fallbackParent = (frame == _G.MicroMenu and _G.MicroMenuContainer) or UIParent
            pcall(frame.SetParent, frame, fallbackParent)
        end
        if saved and saved.points and #saved.points > 0 and frame.ClearAllPoints and frame.SetPoint then
            pcall(frame.ClearAllPoints, frame)
            for _, pt in ipairs(saved.points) do
                pcall(frame.SetPoint, frame, pt[1], pt[2], pt[3], pt[4], pt[5])
            end
        elseif frame.ApplySystemAnchor then
            pcall(frame.ApplySystemAnchor, frame)
        end
    end

    _inOffscreenMove[frame] = nil
end

local function SuppressFrame(frame, entry)
    if not frame then return end
    _suppressedBySfui[frame] = true
    local key = entry and entry.key
    if key == "hide_micromenu" or key == "hide_bagsbar" then
        ParkFrameOffscreen(frame, key)
        UpdateBarChildren(key, true)
        return
    end
    if frame.SetAlpha and (not frame.GetAlpha or frame:GetAlpha() ~= 0) then
        frame:SetAlpha(0)
    end
    local isProtected = frame.IsProtected and frame:IsProtected()
    if not isProtected and frame.EnableMouse and not (InCombatLockdown and InCombatLockdown()) then
        pcall(frame.EnableMouse, frame, false)
        if frame.EnableMouseClicks then pcall(frame.EnableMouseClicks, frame, false) end
        if frame.EnableMouseMotion then pcall(frame.EnableMouseMotion, frame, false) end
    end
    if frame.Selection then
        SilenceSelection(frame.Selection)
    end
    if frame.totFrame then
        if frame.totFrame.SetAlpha and (not frame.totFrame.GetAlpha or frame.totFrame:GetAlpha() ~= 0) then
            frame.totFrame:SetAlpha(0)
        end
        if not isProtected and frame.totFrame.EnableMouse and not (InCombatLockdown and InCombatLockdown()) then
            pcall(frame.totFrame.EnableMouse, frame.totFrame, false)
            if frame.totFrame.EnableMouseClicks then pcall(frame.totFrame.EnableMouseClicks, frame.totFrame, false) end
            if frame.totFrame.EnableMouseMotion then pcall(frame.totFrame.EnableMouseMotion, frame.totFrame, false) end
        end
        if frame.totFrame.Selection then
            SilenceSelection(frame.totFrame.Selection)
        end
    end
    if sfui.isEra and entry and entry.key == "hide_target_frame" and _G.ComboFrame and _G.ComboFrame.SetParent and _G.ComboFrame:GetParent() ~= frame then
        pcall(_G.ComboFrame.SetParent, _G.ComboFrame, frame)
    end
end

local function RestoreFrame(frame, entry)
    if not frame or not _suppressedBySfui[frame] then return end
    _suppressedBySfui[frame] = nil
    local key = entry and entry.key
    if key == "hide_micromenu" or key == "hide_bagsbar" then
        RestoreFrameFromOffscreen(frame, key)
        UpdateBarChildren(key, false)
    end
    if frame.GetAlpha and frame:GetAlpha() ~= 1.0 then
        frame:SetAlpha(1.0)
    end
    local isProtected = frame.IsProtected and frame:IsProtected()
    if not isProtected and frame.EnableMouse and not (InCombatLockdown and InCombatLockdown()) then
        pcall(frame.EnableMouse, frame, true)
        if frame.EnableMouseClicks then pcall(frame.EnableMouseClicks, frame, true) end
        if frame.EnableMouseMotion then pcall(frame.EnableMouseMotion, frame, true) end
    end
    if key == "hide_micromenu" then
        if frame == _G.MicroMenuContainer and frame.Layout then
            pcall(frame.Layout, frame)
        end
        if _G.UpdateMicroButtons then
            pcall(_G.UpdateMicroButtons)
        end
    elseif key == "hide_bagsbar" then
        if frame == _G.BagsBar and frame.Layout then
            pcall(frame.Layout, frame)
        end
    end
    if frame.totFrame then
        if frame.totFrame.GetAlpha and frame.totFrame:GetAlpha() ~= 1.0 then
            frame.totFrame:SetAlpha(1.0)
        end
        if not isProtected and frame.totFrame.EnableMouse and not (InCombatLockdown and InCombatLockdown()) then
            pcall(frame.totFrame.EnableMouse, frame.totFrame, true)
            if frame.totFrame.EnableMouseClicks then pcall(frame.totFrame.EnableMouseClicks, frame.totFrame, true) end
            if frame.totFrame.EnableMouseMotion then pcall(frame.totFrame.EnableMouseMotion, frame.totFrame, true) end
        end
    end
end

local function ApplyUnitFrame(entry)
    local frames = GetFramesForEntry(entry)
    if #frames == 0 then return end

    local shouldHide = ShouldHide(entry.key)

    for _, frame in ipairs(frames) do
        if shouldHide then
            SuppressFrame(frame, entry)
        else
            RestoreFrame(frame, entry)
        end
    end
end

local function HookUnitFrames()
    -- MultiCastActionBarFrame for Classic / Camelot only
    if not sfui.isRetail and hooksecurefunc and _G.MultiCastActionBarFrame_Update and not hookedMultiCast then
        hookedMultiCast = true
        hooksecurefunc("MultiCastActionBarFrame_Update", function(self)
            if SfuiDB and SfuiDB.hide_totem_bar and self then
                self:SetAlpha(0)
                local isProtected = self.IsProtected and self.IsProtected(self)
                if not isProtected and self.EnableMouse and not InCombatLockdown() then
                    pcall(self.EnableMouse, self, false)
                end
            end
        end)
    end

    if hooksecurefunc and not hookedBarsAndMenu then
        hookedBarsAndMenu = true
        if _G.MicroMenuBar_SetFullScreenFrame then
            hooksecurefunc("MicroMenuBar_SetFullScreenFrame", function()
                if ShouldHide("hide_micromenu") then
                    ApplyUnitFrame(HIDE_FRAMES[5])
                end
            end)
        end
        if _G.MicroMenuBar_ClearFullScreenFrame then
            hooksecurefunc("MicroMenuBar_ClearFullScreenFrame", function()
                if ShouldHide("hide_micromenu") then
                    ApplyUnitFrame(HIDE_FRAMES[5])
                end
            end)
        end
        if _G.UpdateMicroButtons then
            hooksecurefunc("UpdateMicroButtons", function()
                if ShouldHide("hide_micromenu") then
                    UpdateBarChildren("hide_micromenu", true)
                end
            end)
        end
        if _G.ContainerFrame_SetFullScreenFrame then
            hooksecurefunc("ContainerFrame_SetFullScreenFrame", function()
                if ShouldHide("hide_bagsbar") then
                    ApplyUnitFrame(HIDE_FRAMES[6])
                end
            end)
        end
        if _G.ContainerFrame_ClearFullScreenFrame then
            hooksecurefunc("ContainerFrame_ClearFullScreenFrame", function()
                if ShouldHide("hide_bagsbar") then
                    ApplyUnitFrame(HIDE_FRAMES[6])
                end
            end)
        end
    end
end

-- Stubs & helpers for external modules
sfui.hide.SuppressFrame = SuppressFrame
sfui.hide.RestoreFrame = RestoreFrame

function sfui.hide.SuppressTargetFrame()
    local tf = _G.TargetFrame
    if tf then
        SuppressFrame(tf, { key = "hide_target_frame" })
    end
end

function sfui.hide.RestoreTargetFrame()
    local tf = _G.TargetFrame
    if tf then
        RestoreFrame(tf, { key = "hide_target_frame" })
    end
end


function sfui.hide.ApplyAllUnitFrames()
    HookUnitFrames()
    for _, entry in ipairs(HIDE_FRAMES) do
        ApplyUnitFrame(entry)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  UI Errors Frame Filtering (Spell/Ability Cooldown Spam)
-- ─────────────────────────────────────────────────────────────────────────────
function sfui.hide.ApplyErrorFilters()
    local enabled = SfuiDB and (SfuiDB.hide_cooldown_errors ~= false)
    local bl = _G.BLACK_LISTED_MESSAGE_TYPES

    local types = {
        _G.LE_GAME_ERR_SPELL_COOLDOWN,
        _G.LE_GAME_ERR_ABILITY_COOLDOWN,
        _G.LE_GAME_ERR_ITEM_COOLDOWN,
        _G.LE_GAME_ERR_OUT_OF_ENERGY,
    }

    local uie = _G.UIErrorsFrame
    for _, msgType in ipairs(types) do
        if msgType then
            if bl then
                bl[msgType] = enabled or nil
            end
            if uie and uie.SetMessageTypeEnabled then
                uie:SetMessageTypeEnabled(msgType, not enabled)
            end
        end
    end

    if uie and not uie._sfuiFiltered then
        uie._sfuiFiltered = true
        if uie.TryDisplayMessage then
            local origTryDisplay = uie.TryDisplayMessage
            uie.TryDisplayMessage = function(self, messageType, message, r, g, b)
                if SfuiDB and SfuiDB.hide_cooldown_errors then
                    if messageType and (
                            (_G.LE_GAME_ERR_SPELL_COOLDOWN and messageType == _G.LE_GAME_ERR_SPELL_COOLDOWN) or
                            (_G.LE_GAME_ERR_ABILITY_COOLDOWN and messageType == _G.LE_GAME_ERR_ABILITY_COOLDOWN) or
                            (_G.LE_GAME_ERR_ITEM_COOLDOWN and messageType == _G.LE_GAME_ERR_ITEM_COOLDOWN) or
                            (_G.LE_GAME_ERR_OUT_OF_ENERGY and messageType == _G.LE_GAME_ERR_OUT_OF_ENERGY)
                        ) then
                        return
                    end
                    if message and type(message) == "string" then
                        local lower = message:lower()
                        if message == _G.ERR_SPELL_COOLDOWN or
                            message == _G.ERR_ABILITY_COOLDOWN or
                            message == _G.ERR_ITEM_COOLDOWN or
                            message == _G.ERR_OUT_OF_ENERGY or
                            lower:find("not ready yet", 1, true) or
                            lower:find("not enough energy", 1, true) then
                            return
                        end
                    end
                end
                return origTryDisplay(self, messageType, message, r, g, b)
            end
        end

        if uie.AddMessage then
            local origAddMessage = uie.AddMessage
            uie.AddMessage = function(self, msg, r, g, b, a, messageType)
                if SfuiDB and SfuiDB.hide_cooldown_errors then
                    if messageType and (
                            (_G.LE_GAME_ERR_SPELL_COOLDOWN and messageType == _G.LE_GAME_ERR_SPELL_COOLDOWN) or
                            (_G.LE_GAME_ERR_ABILITY_COOLDOWN and messageType == _G.LE_GAME_ERR_ABILITY_COOLDOWN) or
                            (_G.LE_GAME_ERR_ITEM_COOLDOWN and messageType == _G.LE_GAME_ERR_ITEM_COOLDOWN) or
                            (_G.LE_GAME_ERR_OUT_OF_ENERGY and messageType == _G.LE_GAME_ERR_OUT_OF_ENERGY)
                        ) then
                        return
                    end
                    if msg and type(msg) == "string" then
                        local lower = msg:lower()
                        if msg == _G.ERR_SPELL_COOLDOWN or
                            msg == _G.ERR_ABILITY_COOLDOWN or
                            msg == _G.ERR_ITEM_COOLDOWN or
                            msg == _G.ERR_OUT_OF_ENERGY or
                            lower:find("not ready yet", 1, true) or
                            lower:find("not enough energy", 1, true) then
                            return
                        end
                    end
                end
                return origAddMessage(self, msg, r, g, b, a, messageType)
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Blizzard Edit Mode Exit Watcher & Reload Prompt
-- ─────────────────────────────────────────────────────────────────────────────
local _lastEditModeCloseTime = 0
local _pendingReloadPrompt   = false
local reloadPopupFrame       = nil

local function PurgeSfuiBug()
    if _G.sfuibug and _G.sfuibug.Clear then
        _G.sfuibug.Clear()
    elseif _G.SfuiBugDB then
        _G.SfuiBugDB.errors = {}
        _G.SfuiBugDB.order = {}
    end
end
sfui.hide.PurgeSfuiBug = PurgeSfuiBug

if _G.StaticPopupDialogs then
    _G.StaticPopupDialogs["SFUI_EDITMODE_RELOAD"] = {
        text = "blizzard edit mode was closed.\nreload ui to apply layout cleanly and prevent taint?",
        button1 = "reload ui",
        button2 = "later",
        OnAccept = function()
            if _G.C_UI and _G.C_UI.Reload then
                _G.C_UI.Reload()
            elseif _G.ReloadUI then
                _G.ReloadUI()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

local function CreatePopupButton(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, h)
    b:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    b:SetBackdropColor(0.12, 0.12, 0.16, 0.95)
    b:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
    if onClick then b:SetScript("OnClick", onClick) end

    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER")
    fs:SetText(text)
    b.fs = fs

    b:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.20, 0.20, 0.28, 1)
        self:SetBackdropBorderColor(1, 1, 1, 1)
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.12, 0.12, 0.16, 0.95)
        local c = self._borderColor or { 0.3, 0.3, 0.35 }
        self:SetBackdropBorderColor(c[1], c[2], c[3], 1)
    end)

    if sfui.theme and sfui.theme.ApplyButtonStyle then
        pcall(sfui.theme.ApplyButtonStyle, b, false)
    end

    return b
end

local function GetOrCreateReloadPopup()
    if reloadPopupFrame then return reloadPopupFrame end

    local popup = CreateFrame("Frame", "sfui_EditModeReloadPopup", UIParent, "BackdropTemplate")
    popup:SetSize(400, 130)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    popup:SetFrameStrata("DIALOG")
    popup:SetFrameLevel(500)
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:SetMovable(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
    popup:Hide()

    popup:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    popup:SetBackdropColor(0.05, 0.05, 0.07, 0.95)

    local pal = (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()) or sfui.config.appearance or {}
    local accent = pal.accentColor or { 0.40, 0.00, 1.00, 1 }
    popup:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)

    if sfui.common and sfui.common.apply_flat_backdrop then
        pcall(sfui.common.apply_flat_backdrop, popup, { 0.05, 0.05, 0.07, 0.95 }, { accent[1], accent[2], accent[3], 1 })
    end

    if sfui.common and sfui.common.register_special_frame then
        sfui.common.register_special_frame(popup)
    end

    local title = popup:CreateFontString(nil, "OVERLAY", (sfui.config and sfui.config.font) or "GameFontNormal")
    title:SetPoint("TOPLEFT", popup, "TOPLEFT", 14, -12)
    title:SetText("|cff9966ffsfui|r |cffffffffedit mode|r")

    local closeBtn = CreateFrame("Button", nil, popup)
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -6, -6)
    local closeFs = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    closeFs:SetPoint("CENTER")
    closeFs:SetText("|cffaaaaaax|r")
    closeBtn:SetScript("OnClick", function()
        popup:Hide()
    end)

    local msg = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    msg:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    msg:SetPoint("RIGHT", popup, "RIGHT", -14, 0)
    msg:SetJustifyH("LEFT")
    msg:SetSpacing(3)
    msg:SetText("blizzard edit mode was closed.\na ui reload is recommended to apply layout changes cleanly.")

    local reloadBtn = CreatePopupButton(popup, "reload ui", 100, 24, function()
        popup:Hide()
        if _G.C_UI and _G.C_UI.Reload then
            _G.C_UI.Reload()
        elseif _G.ReloadUI then
            _G.ReloadUI()
        end
    end)
    reloadBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -8, 14)
    reloadBtn._borderColor = { 0.2, 0.8, 0.3 }
    reloadBtn:SetBackdropBorderColor(0.2, 0.8, 0.3, 1)

    local laterBtn = CreatePopupButton(popup, "later", 80, 24, function()
        popup:Hide()
    end)
    laterBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOM", 8, 14)

    reloadPopupFrame = popup
    return popup
end

function sfui.hide.ShowEditModeReloadPopup()
    if InCombatLockdown and InCombatLockdown() then
        _pendingReloadPrompt = true
        return
    end

    local popup = GetOrCreateReloadPopup()
    if popup then
        local pal = (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()) or sfui.config.appearance or {}
        local accent = pal.accentColor or { 0.40, 0.00, 1.00, 1 }
        popup:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
        popup:Show()
    elseif _G.StaticPopup_Show then
        _G.StaticPopup_Show("SFUI_EDITMODE_RELOAD")
    end
end

function sfui.hide.OnBlizzardEditModeClosed()
    local now = (GetTime and GetTime()) or 0
    if now - _lastEditModeCloseTime < 0.8 then return end
    _lastEditModeCloseTime = now

    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, function()
            if InCombatLockdown and InCombatLockdown() then
                _pendingReloadPrompt = true
            else
                sfui.hide.ShowEditModeReloadPopup()
            end
        end)
    else
        if InCombatLockdown and InCombatLockdown() then
            _pendingReloadPrompt = true
        else
            sfui.hide.ShowEditModeReloadPopup()
        end
    end
end

local _editModeCallbacksRegistered = false

local function RegisterEditModeCallbacks()
    if _editModeCallbacksRegistered then return end
    if _G.EventRegistry and _G.EventRegistry.RegisterCallback then
        _editModeCallbacksRegistered = true
        _G.EventRegistry:RegisterCallback("EditMode.Enter", function()
            C_Timer.After(0, sfui.hide.ApplyAllUnitFrames)
        end, sfui.hide)
        _G.EventRegistry:RegisterCallback("EditMode.Exit", function()
            C_Timer.After(0, sfui.hide.ApplyAllUnitFrames)
            sfui.hide.OnBlizzardEditModeClosed()
        end, sfui.hide)
    end
end

RegisterEditModeCallbacks()

-- ─────────────────────────────────────────────────────────────────────────────
--  Module Registration & Lifecycle Protocol
-- ─────────────────────────────────────────────────────────────────────────────
sfui.hide.HIDE_FRAMES = HIDE_FRAMES

local function on_regen_enabled()
    -- When leaving combat, apply any deferred unitframe hide/show calls safely
    sfui.hide.ApplyAllUnitFrames()
    if _pendingReloadPrompt then
        _pendingReloadPrompt = false
        sfui.hide.ShowEditModeReloadPopup()
    end
end

local function on_player_entering_world()
    InitDB()
    RestoreAllBarsAlpha()
    HookUnitFrames()
    RegisterEditModeCallbacks()
    sfui.hide.ApplyAllUnitFrames()
    sfui.hide.ApplyErrorFilters()
end

local function init_module(self)
    local _ = self
    InitDB()
    RestoreAllBarsAlpha()
    HookUnitFrames()
    RegisterEditModeCallbacks()
    sfui.hide.ApplyAllUnitFrames()
    sfui.hide.ApplyErrorFilters()

    sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", on_regen_enabled)
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", on_player_entering_world)
    sfui.events.RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", function()
        C_Timer.After(0, function()
            sfui.hide.ApplyAllUnitFrames()
        end)
    end)
    sfui.events.RegisterEvent("ADDON_LOADED", function(event, loadedAddon)
        if loadedAddon == "Blizzard_EditMode" then
            RegisterEditModeCallbacks()
            C_Timer.After(0, function()
                sfui.hide.ApplyAllUnitFrames()
            end)
        elseif loadedAddon == "Blizzard_Minimap" or loadedAddon == "Blizzard_ObjectiveTracker" then
            C_Timer.After(0, function()
                sfui.hide.ApplyAllUnitFrames()
            end)
        end
    end)
end

sfui.hide.OnInit = function(self)
    local _ = self
    InitDB()
end

sfui.hide.OnEnable = function(self)
    init_module(self)
end

sfui.hide.OnSettingsChanged = function(self, key, value)
    local _s, _k, _v = self, key, value
    sfui.hide.ApplyAllUnitFrames()
    sfui.hide.ApplyErrorFilters()
end

local _hideDebug = {}
sfui.hide.GetDebugInfo = function()
    local hiddenUnits = 0
    for _, u in ipairs(HIDE_FRAMES) do
        if SfuiDB and SfuiDB[u.key] then hiddenUnits = hiddenUnits + 1 end
    end
    _hideDebug.hiddenUnitFrames = hiddenUnits
    _hideDebug.errorFilter      = SfuiDB and (SfuiDB.hide_cooldown_errors ~= false)
    return _hideDebug
end
function sfui.hide_debug_info()
    return sfui.hide:GetDebugInfo()
end

if sfui.RegisterModule then
    sfui.RegisterModule("hide", sfui.hide)
end
