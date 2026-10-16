local addonName, addon = ...
sfui = sfui or {}
sfui.ring = sfui.ring or {}
sfui.ring.secure = sfui.ring.secure or {}

local secure = sfui.ring.secure

local CreateFrame             = _G.CreateFrame
local UIParent                = _G.UIParent
local InCombatLockdown        = _G.InCombatLockdown
local ClearOverrideBindings   = _G.ClearOverrideBindings
local SetOverrideBindingClick = _G.SetOverrideBindingClick
local SecureHandlerSetFrameRef = _G.SecureHandlerSetFrameRef
local SecureHandlerWrapScript  = _G.SecureHandlerWrapScript
local tonumber                = _G.tonumber
local tostring                = _G.tostring
local pairs                   = _G.pairs
local type                    = _G.type
local pcall                   = _G.pcall

local secureHeader
local cancelButton
local secureButtons = {}
local pendingPushes = {}
local pendingBindings = {}
local buttonIndex = 0

local function ensure_secure_header()
    if not secureHeader then
        secureHeader = CreateFrame("Frame", "SfuiRingSecureHeader", UIParent, "SecureHandlerBaseTemplate")

        function secureHeader:OpenLiveRing(ringID)
            if sfui.ring.live and sfui.ring.live.open then
                sfui.ring.live.open(ringID)
            end
        end

        function secureHeader:CloseLiveRing()
            if sfui.ring.live and sfui.ring.live.close then
                sfui.ring.live.close()
            end
        end

        function secureHeader:FireInsecureSlot(ringID, idx)
            idx = tonumber(idx)
            if not idx or not ringID then return end
            local btn = secureButtons[ringID]
            if btn and btn._slots and btn._slots[idx] then
                local slot = btn._slots[idx]
                if slot and slot.insecure_func and type(slot.insecure_func) == "function" then
                    if slot.allow_combat_insecure or not InCombatLockdown or not InCombatLockdown() then
                        pcall(slot.insecure_func, slot)
                    end
                end
            end
        end
    end
    return secureHeader
end

local function ensure_cancel_button()
    if not cancelButton then
        cancelButton = CreateFrame("Button", "SfuiRingCancelButton", UIParent, "SecureActionButtonTemplate")
        cancelButton:EnableMouse(false)
        cancelButton:SetSize(1, 1)
        cancelButton:SetAlpha(0)
        cancelButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -700, 100)
        cancelButton:Show()
        cancelButton:SetScript("PostClick", function()
            if sfui.ring.live and sfui.ring.live.is_open and sfui.ring.live.is_open() then
                sfui.ring.live.close()
            end
        end)
    end
    return cancelButton
end

local SNIPPET_PRE = [==[
    local ui = self:GetFrameRef("ui")
    local cancel = self:GetFrameRef("cancel")
    local h = self:GetFrameRef("header") or control

    if down then
        self:SetAttribute("type", nil)
        self:SetAttribute("typerelease", nil)
        self:SetAttribute("sfui_idx", nil)
        self:SetAttribute("sfui_is_insecure", nil)
        self:SetAttribute("sfui_why", "pressed")
        self:SetAttribute("sfui_ox", nil)
        self:SetAttribute("sfui_oy", nil)
        if ui then
            local x, y = ui:GetMousePosition()
            if x and y then
                self:SetAttribute("sfui_ox", x * ui:GetWidth())
                self:SetAttribute("sfui_oy", y * ui:GetHeight())
            end
        end

        if h then
            h:CallMethod("OpenLiveRing", self:GetAttribute("sfui_ring_id"))
        end

        return false
    end

    -- key up (release)
    local ox = tonumber(self:GetAttribute("sfui_ox"))
    local oy = tonumber(self:GetAttribute("sfui_oy"))
    local numSlots = tonumber(self:GetAttribute("sfui_num_slots")) or 0
    local deadzone = tonumber(self:GetAttribute("sfui_deadzone")) or 24

    if not ui or not ox or not oy or numSlots <= 0 then
        self:SetAttribute("type", nil)
        self:SetAttribute("typerelease", nil)
        self:SetAttribute("sfui_why", "no_origin")
        if h then
            h:CallMethod("CloseLiveRing")
        end
        return false
    end

    local x, y = ui:GetMousePosition()
    if not x or not y then
        self:SetAttribute("type", nil)
        self:SetAttribute("typerelease", nil)
        self:SetAttribute("sfui_why", "offscreen")
        if h then
            h:CallMethod("CloseLiveRing")
        end
        return false
    end

    local cx, cy = x * ui:GetWidth(), y * ui:GetHeight()
    local dx, dy = cx - ox, cy - oy
    local dist = (dx * dx + dy * dy) ^ 0.5

    if dist < deadzone then
        self:SetAttribute("type", nil)
        self:SetAttribute("typerelease", nil)
        self:SetAttribute("sfui_idx", nil)
        self:SetAttribute("sfui_why", "deadzone")
        if h then
            h:CallMethod("CloseLiveRing")
        end
        return false
    end

    local theta = atan2(dx, dy)
    if theta < 0 then theta = theta + 360 end

    local step = 360 / numSlots
    local rel = (theta + step * 0.5) % 360
    local idx = floor(rel / step) + 1
    if idx > numSlots then idx = 1 end

    self:SetAttribute("sfui_idx", idx)

    local actionType = self:GetAttribute("slot" .. idx .. "-type")
    local isInsecure = self:GetAttribute("slot" .. idx .. "-insecure")
    if not actionType and not isInsecure then
        self:SetAttribute("type", nil)
        self:SetAttribute("typerelease", nil)
        self:SetAttribute("sfui_why", "empty")
        if h then
            h:CallMethod("CloseLiveRing")
        end
        return false
    end

    if isInsecure then
        self:SetAttribute("sfui_is_insecure", "1")
    else
        self:SetAttribute("sfui_is_insecure", nil)
    end

    -- clear stale action attributes
    self:SetAttribute("spell", nil)
    self:SetAttribute("item", nil)
    self:SetAttribute("macro", nil)
    self:SetAttribute("macrotext", nil)
    self:SetAttribute("toy", nil)
    self:SetAttribute("action", nil)
    self:SetAttribute("marker", nil)

    local a1_k = self:GetAttribute("slot" .. idx .. "-a1_k")
    if a1_k then
        self:SetAttribute(a1_k, self:GetAttribute("slot" .. idx .. "-a1_v"))
    end
    local a2_k = self:GetAttribute("slot" .. idx .. "-a2_k")
    if a2_k then
        self:SetAttribute(a2_k, self:GetAttribute("slot" .. idx .. "-a2_v"))
    end
    local a3_k = self:GetAttribute("slot" .. idx .. "-a3_k")
    if a3_k then
        self:SetAttribute(a3_k, self:GetAttribute("slot" .. idx .. "-a3_v"))
    end

    if actionType then
        self:SetAttribute("pressAndHoldAction", 1)
        self:SetAttribute("type", actionType)
        self:SetAttribute("typerelease", actionType)
    else
        self:SetAttribute("type", nil)
        self:SetAttribute("typerelease", nil)
    end
    self:SetAttribute("sfui_why", "fire")
    return nil, 1
]==]

local SNIPPET_POST = [==[
    if down then return end
    self:SetAttribute("type", nil)
    self:SetAttribute("typerelease", nil)
    self:SetAttribute("macrotext", nil)
    self:SetAttribute("toy", nil)
    self:SetAttribute("spell", nil)
    self:SetAttribute("item", nil)
    self:SetAttribute("macro", nil)
    self:SetAttribute("action", nil)
    self:SetAttribute("marker", nil)

    local h = self:GetFrameRef("header") or control
    if h then
        h:CallMethod("CloseLiveRing")

        local why = self:GetAttribute("sfui_why")
        local isInsecure = self:GetAttribute("sfui_is_insecure")
        self:SetAttribute("sfui_is_insecure", nil)
        if why == "fire" and isInsecure then
            local idx = self:GetAttribute("sfui_idx")
            if idx then
                h:CallMethod("FireInsecureSlot", self:GetAttribute("sfui_ring_id"), idx)
            end
        end
    end
]==]

--- get or create the secure action button for a given ring.
--- @param ringID string
--- @return Button
function secure.get_or_create_button(ringID)
    if secureButtons[ringID] then
        return secureButtons[ringID]
    end

    buttonIndex = buttonIndex + 1
    local btnName = "SfuiRing_" .. ringID
    local btn = CreateFrame("Button", btnName, UIParent, "SecureActionButtonTemplate")
    btn._ringID = ringID
    btn:SetAttribute("sfui_ring_id", ringID)
    btn:RegisterForClicks("AnyDown", "AnyUp")
    btn:SetAttribute("useOnKeyDown", false)
    btn:EnableMouse(false)
    btn:SetSize(1, 1)
    btn:SetAlpha(0)
    btn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -600 - (buttonIndex * 12), 100)
    btn:Show()

    local header = ensure_secure_header()
    local cancel = ensure_cancel_button()

    SecureHandlerSetFrameRef(btn, "ui", UIParent)
    SecureHandlerSetFrameRef(btn, "cancel", cancel)
    SecureHandlerSetFrameRef(btn, "header", header)
    SecureHandlerWrapScript(btn, "OnClick", header, SNIPPET_PRE, SNIPPET_POST)

    secureButtons[ringID] = btn
    return btn
end

local function apply_slots_to_button(btn, slots)
    local num = slots and #slots or 0
    btn._slots = slots
    btn:SetAttribute("sfui_num_slots", num)

    local deadzone = (sfui.db and sfui.db.Get("ring", "deadzone", 28)) or 28
    btn:SetAttribute("sfui_deadzone", deadzone)

    for i = 1, num do
        local slot = slots[i]
        local attrs = slot.attrs or {}
        btn:SetAttribute("slot" .. i .. "-type", attrs.type)
        btn:SetAttribute("slot" .. i .. "-insecure", (slot.insecure_func and true) or nil)

        local attrIndex = 0
        for k, v in pairs(attrs) do
            if k ~= "type" then
                attrIndex = attrIndex + 1
                if attrIndex <= 3 then
                    btn:SetAttribute("slot" .. i .. "-a" .. attrIndex .. "_k", k)
                    btn:SetAttribute("slot" .. i .. "-a" .. attrIndex .. "_v", v)
                end
            end
        end
        for j = attrIndex + 1, 3 do
            btn:SetAttribute("slot" .. i .. "-a" .. j .. "_k", nil)
            btn:SetAttribute("slot" .. i .. "-a" .. j .. "_v", nil)
        end
    end

    -- clean up leftover slots from previous larger layouts
    local prevNum = tonumber(btn:GetAttribute("sfui_prev_slots")) or 0
    if prevNum > num then
        for i = num + 1, prevNum do
            btn:SetAttribute("slot" .. i .. "-type", nil)
            btn:SetAttribute("slot" .. i .. "-insecure", nil)
            for j = 1, 3 do
                btn:SetAttribute("slot" .. i .. "-a" .. j .. "_k", nil)
                btn:SetAttribute("slot" .. i .. "-a" .. j .. "_v", nil)
            end
        end
    end
    btn:SetAttribute("sfui_prev_slots", num)
end

--- push configured slot definitions to the secure button.
--- defers to out-of-combat if player is currently in combat lockdown.
--- @param ringID string
--- @param slots table
function secure.push_ring_slots(ringID, slots)
    local btn = secure.get_or_create_button(ringID)
    if InCombatLockdown and InCombatLockdown() then
        pendingPushes[ringID] = slots
        return
    end
    apply_slots_to_button(btn, slots)
end

local function apply_button_binding(btn, key)
    ClearOverrideBindings(btn)
    if key and key ~= "" then
        SetOverrideBindingClick(btn, true, key, btn:GetName(), "LeftButton")
    end
end

--- apply an override binding to the ring's secure button.
--- defers to out-of-combat if player is in combat lockdown.
--- @param ringID string
--- @param key string|nil
function secure.apply_binding(ringID, key)
    local btn = secure.get_or_create_button(ringID)
    if InCombatLockdown and InCombatLockdown() then
        pendingBindings[ringID] = key or false
        return
    end
    apply_button_binding(btn, key)
end

--- clear any active override binding for a ring.
--- @param ringID string
function secure.clear_binding(ringID)
    secure.apply_binding(ringID, nil)
end

-- flush any queued slot pushes or bindings when leaving combat
sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    for ringID, slots in pairs(pendingPushes) do
        local btn = secureButtons[ringID]
        if btn then
            apply_slots_to_button(btn, slots)
        end
        pendingPushes[ringID] = nil
    end

    for ringID, key in pairs(pendingBindings) do
        local btn = secureButtons[ringID]
        if btn then
            apply_button_binding(btn, key ~= false and key or nil)
        end
        pendingBindings[ringID] = nil
    end
end)
