local addonName, addon = ...
sfui = sfui or {}
sfui.cursor = sfui.cursor or {}

local f -- specific frame reference
local BASE_SIZE = 48 -- reduced to 75% of original 64px
local lastX, lastY = 0, 0
local uiparent

function sfui.cursor.initialize()
    if _G.SfuiCursor then
        f = _G.SfuiCursor
        return
    end

    -- Cache UIParent reference
    uiparent = UIParent or _G.UIParent
    local GetCursorPosition = GetCursorPosition

    local function get_scale()
        local s = uiparent and uiparent.GetEffectiveScale and uiparent:GetEffectiveScale()
        if not s or s <= 0 then s = 1 end
        return s
    end
    local cachedScale = get_scale()

    -- Create Frame
    f = CreateFrame("Frame", "SfuiCursor", uiparent)
    f:SetSize(BASE_SIZE, BASE_SIZE)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(9999)
    f:EnableMouse(false)
    f:SetClampedToScreen(false)
    -- Set initial anchor once (never cleared)
    f:SetPoint("CENTER", uiparent, "BOTTOMLEFT", 0, 0)

    -- Create Texture
    local ring = f:CreateTexture(nil, "OVERLAY")
    ring:SetAllPoints(f)
    ring:SetTexture("Interface\\AddOns\\sfui\\ring.tga")

    -- Helper: Update Color
    local function UpdateColor()
        local specID = sfui.common and sfui.common.get_current_spec_id and sfui.common.get_current_spec_id()
        local r, g, b = 1, 1, 1
        if sfui.common and sfui.common.get_spec_color then
            r, g, b = sfui.common.get_spec_color(specID)
        end
        if ring then
            ring:SetVertexColor(r or 1, g or 1, b or 1, 0.8)
        end
    end
    sfui.cursor.UpdateColor = UpdateColor

    -- Event Handler (via central dispatcher)
    local function on_cursor_event(event)
        if event == "UI_SCALE_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
            cachedScale = get_scale()
        end
        if event ~= "UI_SCALE_CHANGED" then
            UpdateColor()
        end
    end
    sfui.events.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", on_cursor_event)
    sfui.events.RegisterEvent("PLAYER_TALENT_UPDATE",         on_cursor_event)
    if sfui.isClassic then
        sfui.events.RegisterEvent("CHARACTER_POINTS_CHANGED", on_cursor_event)
    end
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD",         on_cursor_event)
    sfui.events.RegisterEvent("UI_SCALE_CHANGED",              on_cursor_event)

    local lastRawX, lastRawY = -1, -1
    local function update_cursor_pos()
        if not f or not f:IsShown() then return end
        local x, y = GetCursorPosition()
        if not x or not y then return end
        if x == lastRawX and y == lastRawY then return end
        lastRawX, lastRawY = x, y
        local scale = cachedScale or get_scale()
        local cx = x / scale
        local cy = y / scale
        f:SetPoint("CENTER", uiparent, "BOTTOMLEFT", cx, cy)
    end
    f.OnUpdate = update_cursor_pos

    f:SetScript("OnShow", function()
        if not SfuiDB or SfuiDB.enableCursorRing ~= false then
            sfui.events.RegisterUpdate("CursorRing", 0.016, f.OnUpdate)
            if f.OnUpdate then f.OnUpdate() end
        end
    end)

    f:SetScript("OnHide", function()
        sfui.events.UnregisterUpdate("CursorRing")
    end)

    -- Initialize Color
    UpdateColor()

    -- Apply initial state
    local isEnabled = not SfuiDB or (SfuiDB.enableCursorRing ~= false)
    sfui.cursor.toggle(isEnabled)
end

function sfui.cursor.update_scale()
    if not f then return end
    local scale = (SfuiDB and SfuiDB.cursorRingScale) or 1.0
    if scale <= 0 then scale = 1.0 end
    f:SetSize(BASE_SIZE * scale, BASE_SIZE * scale)
end

function sfui.cursor.toggle(enabled)
    if enabled == nil then
        enabled = not SfuiDB or SfuiDB.enableCursorRing ~= false
    end
    if SfuiDB then
        SfuiDB.enableCursorRing = enabled
    end

    if not f then
        if enabled then
            sfui.cursor.initialize()
        end
        return
    end

    if enabled then
        f:Show()
        sfui.cursor.update_scale()
        sfui.events.RegisterUpdate("CursorRing", 0.016, f.OnUpdate)
        if f.OnUpdate then f.OnUpdate() end
    else
        f:Hide()
        sfui.events.UnregisterUpdate("CursorRing")
    end
end

function sfui.cursor_debug_info()
    return {
        enabled = not SfuiDB or (SfuiDB.enableCursorRing ~= false),
        frameCreated = f ~= nil,
        frameShown = f and f:IsShown() or false,
    }
end

sfui.cursor.OnInit = function(self)
    if SfuiDB then
        if SfuiDB.enableCursorRing == nil then SfuiDB.enableCursorRing = true end
        if SfuiDB.cursorRingScale == nil then SfuiDB.cursorRingScale = 1.0 end
    end
end

sfui.cursor.OnEnable = function(self)
    self.initialize()
end

sfui.cursor.OnDisable = function(self)
    self.toggle(false)
end

sfui.cursor.OnSettingsChanged = function(self, key, value)
    if key == "enableCursorRing" then
        self.toggle(value)
    elseif key == "cursorRingScale" then
        self.update_scale()
    end
end

sfui.cursor.OnSpecChanged = function(self, specID)
    if self.UpdateColor then self.UpdateColor() end
end

sfui.cursor.GetDebugInfo = sfui.cursor_debug_info
sfui.RegisterModule("cursor", sfui.cursor)
