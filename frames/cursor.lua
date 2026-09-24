local addonName, addon = ...
sfui = sfui or {}
sfui.cursor = {}

local f -- specific frame reference
local lastX, lastY = 0, 0
local uiparent

function sfui.cursor.initialize()
    if _G.SfuiCursor then return end

    -- Cache UIParent reference
    uiparent = UIParent
    local GetCursorPosition = GetCursorPosition
    local GetEffectiveScale = uiparent.GetEffectiveScale

    -- Create Frame
    f = CreateFrame("Frame", "SfuiCursor", uiparent)
    f:SetSize(64, 64)
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
        local specID = sfui.common.get_current_spec_id()
        local r, g, b = sfui.common.get_spec_color(specID)
        ring:SetVertexColor(r, g, b, 0.8)
    end

    -- Event Handler (via central dispatcher)
    local cachedScale = GetEffectiveScale(uiparent)

    local function on_cursor_event(event)
        if event == "UI_SCALE_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
            cachedScale = GetEffectiveScale(uiparent)
        end
        if event ~= "UI_SCALE_CHANGED" then
            UpdateColor()
        end
    end
    sfui.events.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", on_cursor_event)
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD",         on_cursor_event)
    sfui.events.RegisterEvent("UI_SCALE_CHANGED",              on_cursor_event)

    local function update_cursor_pos()
        if not f or not f:IsShown() then return end
        local x, y = GetCursorPosition()
        local cx = x / cachedScale
        local cy = y / cachedScale

        if cx ~= lastX or cy ~= lastY then
            lastX, lastY = cx, cy
            f:SetPoint("CENTER", uiparent, "BOTTOMLEFT", cx, cy)
        end
    end
    f.OnUpdate = update_cursor_pos

    f:SetScript("OnHide", function()
        if sfui.events and sfui.events.UnregisterUpdate then
            sfui.events.UnregisterUpdate("CursorRing")
        end
    end)

    -- Initialize Color
    UpdateColor()

    -- Apply initial state
    sfui.cursor.toggle(SfuiDB.enableCursorRing)
end

function sfui.cursor.update_scale()
    if not f then return end
    local scale = SfuiDB.cursorRingScale or 1.0
    f:SetSize(64 * scale, 64 * scale)
end

function sfui.cursor.toggle(enabled)
    SfuiDB.enableCursorRing = enabled
    if not f then return end

    if enabled then
        f:Show()
        sfui.cursor.update_scale() -- Ensure scale is correct when shown
        if sfui.events and sfui.events.RegisterUpdate then
            sfui.events.RegisterUpdate("CursorRing", 0.016, f.OnUpdate)
        else
            f:SetScript("OnUpdate", f.OnUpdate)
        end
    else
        f:Hide()
        if sfui.events and sfui.events.UnregisterUpdate then
            sfui.events.UnregisterUpdate("CursorRing")
        end
        f:SetScript("OnUpdate", nil)
    end
end

function sfui.cursor_debug_info()
    return {
        enabled = SfuiDB and SfuiDB.enableCursorRing or false,
        frameCreated = f ~= nil,
        frameShown = f and f:IsShown() or false,
    }
end

if sfui.RegisterModule then
    sfui.cursor = sfui.cursor or {}
    sfui.cursor.GetDebugInfo = sfui.cursor_debug_info
    sfui.RegisterModule("cursor", sfui.cursor)
end
