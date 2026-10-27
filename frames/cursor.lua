local addonName, addon = ...
sfui = sfui or {}
sfui.cursor = sfui.cursor or {}

local f -- specific frame reference
local BASE_SIZE = 48 -- reduced to 75% of original 64px
local uiparent
local ring
local cachedScale = 1
local lastX, lastY = -9999, -9999

local function update_scale_cache()
    local s = uiparent and uiparent.GetEffectiveScale and uiparent:GetEffectiveScale()
    cachedScale = (s and s > 0) and s or 1
end

local function get_update_interval()
    if SfuiDB and SfuiDB.cursorRing144hz then
        return 0.0069
    end
    return 0.016
end

local function update_cursor_pos()
    if not f or not f:IsShown() then return end
    local x, y = GetCursorPosition()
    if not x or not y then return end
    if cachedScale <= 0 then update_scale_cache() end
    local cx = math.floor(x / cachedScale + 0.5)
    local cy = math.floor(y / cachedScale + 0.5)
    if cx ~= lastX or cy ~= lastY then
        lastX, lastY = cx, cy
        f:SetPoint("CENTER", uiparent, "BOTTOMLEFT", cx, cy)
    end
end

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

function sfui.cursor.initialize()
    if _G.SfuiCursor then
        f = _G.SfuiCursor
        local isEnabled = not SfuiDB or (SfuiDB.enableCursorRing ~= false)
        sfui.cursor.toggle(isEnabled)
        return
    end

    -- Cache UIParent reference
    uiparent = UIParent or _G.UIParent
    update_scale_cache()

    -- Create Frame (start hidden so f:Show() cleanly triggers OnShow)
    f = CreateFrame("Frame", "SfuiCursor", uiparent)
    f:Hide()
    f:SetSize(BASE_SIZE, BASE_SIZE)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(9999)
    f:EnableMouse(false)
    f:SetClampedToScreen(false)

    -- Immediately position at current cursor or off-screen
    local x, y = GetCursorPosition()
    if x and y then
        local cx = math.floor(x / cachedScale + 0.5)
        local cy = math.floor(y / cachedScale + 0.5)
        lastX, lastY = cx, cy
        f:SetPoint("CENTER", uiparent, "BOTTOMLEFT", cx, cy)
    else
        f:SetPoint("CENTER", uiparent, "BOTTOMLEFT", -9999, -9999)
    end

    -- Create Texture
    ring = f:CreateTexture(nil, "OVERLAY")
    ring:SetAllPoints(f)
    ring:SetTexture("Interface\\AddOns\\sfui\\ring.tga")
    f.ring = ring

    -- Event Handler (via central dispatcher)
    local function on_cursor_event(event)
        if event == "UI_SCALE_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
            update_scale_cache()
            update_cursor_pos()
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

    f.OnUpdate = update_cursor_pos

    f:SetScript("OnShow", function()
        lastX, lastY = -9999, -9999
        update_scale_cache()
        if not SfuiDB or SfuiDB.enableCursorRing ~= false then
            sfui.events.RegisterUpdate("CursorRing", get_update_interval(), update_cursor_pos)
            update_cursor_pos()
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

function sfui.cursor.set_high_refresh(enabled)
    if SfuiDB then
        SfuiDB.cursorRing144hz = enabled and true or false
    end
    if f and f:IsShown() and (not SfuiDB or SfuiDB.enableCursorRing ~= false) then
        sfui.events.RegisterUpdate("CursorRing", get_update_interval(), update_cursor_pos)
    end
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
        sfui.cursor.update_scale()
        f:Show()
        update_scale_cache()
        update_cursor_pos()
        sfui.events.RegisterUpdate("CursorRing", get_update_interval(), update_cursor_pos)
    else
        f:Hide()
        sfui.events.UnregisterUpdate("CursorRing")
    end
end

function sfui.cursor_debug_info()
    return {
        enabled = not SfuiDB or (SfuiDB.enableCursorRing ~= false),
        highRefresh = (SfuiDB and SfuiDB.cursorRing144hz) or false,
        frameCreated = f ~= nil,
        frameShown = f and f:IsShown() or false,
    }
end

sfui.cursor.OnInit = function(self)
    if SfuiDB then
        if SfuiDB.enableCursorRing == nil then SfuiDB.enableCursorRing = true end
        if SfuiDB.cursorRingScale == nil then SfuiDB.cursorRingScale = 1.0 end
        if SfuiDB.cursorRing144hz == nil then SfuiDB.cursorRing144hz = false end
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
    elseif key == "cursorRing144hz" then
        self.set_high_refresh(value)
    end
end

sfui.cursor.OnSpecChanged = function(self, specID)
    if self.UpdateColor then self.UpdateColor() end
end

sfui.cursor.GetDebugInfo = sfui.cursor_debug_info
sfui.RegisterModule("cursor", sfui.cursor)
