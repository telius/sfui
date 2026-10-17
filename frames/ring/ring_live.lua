local addonName, addon = ...
sfui = sfui or {}
sfui.ring = sfui.ring or {}
sfui.ring.live = sfui.ring.live or {}

local live = sfui.ring.live
local geom = sfui.ring.geom
local view = sfui.ring.view

local GetCursorPosition = _G.GetCursorPosition
local UIParent          = _G.UIParent
local PlaySound         = _G.PlaySound
local SOUNDKIT          = _G.SOUNDKIT

local function get_cursor_pos()
    local curX, curY
    if _G.GetCursorCenterPosition then
        curX, curY = _G.GetCursorCenterPosition()
    elseif _G.C_Input and _G.C_Input.GetCursorCenterPosition then
        curX, curY = _G.C_Input.GetCursorCenterPosition()
    elseif GetCursorPosition then
        curX, curY = GetCursorPosition()
    else
        curX, curY = 0, 0
    end
    local scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    return (curX or 0) / scale, (curY or 0) / scale
end

local function is_cursor_visible()
    if _G.IsCursorVisible then
        return _G.IsCursorVisible()
    elseif _G.C_Input and _G.C_Input.IsCursorVisible then
        return _G.C_Input.IsCursorVisible()
    elseif _G.IsMouselooking then
        return not _G.IsMouselooking()
    end
    return true
end

local isOpen = false
local originX = 0
local originY = 0
local activeRingID = nil
local activeSlots = nil
local lastHoveredIndex = nil

local updateThrottle = 0
local cdThrottle = 0
local function on_live_update(self, elapsed)
    elapsed = elapsed or 0
    updateThrottle = updateThrottle + elapsed
    cdThrottle = cdThrottle + elapsed

    if not isOpen or not activeSlots or #activeSlots == 0 then
        self:SetScript("OnUpdate", nil)
        return
    end

    if cdThrottle >= 0.05 then
        cdThrottle = 0
        if view and view.update_live_state then
            view.update_live_state()
        end
    end

    if updateThrottle < 0.016 then return end
    updateThrottle = 0

    if not is_cursor_visible() then
        return
    end

    local scaledX, scaledY = get_cursor_pos()
    local dx = scaledX - originX
    local dy = scaledY - originY

    local total = #activeSlots
    local deadzone = (sfui.db and sfui.db.Get("ring", "deadzone", 28)) or 28

    local idx = geom.point_to_slot(dx, dy, total, deadzone)

    if idx ~= lastHoveredIndex then
        lastHoveredIndex = idx
        view.set_active_slot(idx)

        local soundEnabled = (sfui.db and sfui.db.Get("ring", "sound_cues", true))
        if soundEnabled and idx and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON, "Master")
        end
    end
end

--- open the radial ring for a given ring ID at the current mouse position.
--- @param ringID string
function live.open(ringID)
    if isOpen and activeRingID == ringID then return end

    local enabled = (sfui.db and sfui.db.Get("ring", "enabled", true))
    if enabled == false then return end

    local slots, title = sfui.ring.get_ring_slots(ringID)
    if not slots or #slots == 0 then return end

    activeRingID = ringID
    activeSlots = slots
    lastHoveredIndex = nil
    isOpen = true
    updateThrottle = 0
    cdThrottle = 0

    originX, originY = get_cursor_pos()

    local frame = view.get_frame()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", originX, originY)

    view.render_ring(ringID, slots, title)
    view.set_active_slot(nil)

    frame:Show()
    frame:SetScript("OnUpdate", on_live_update)
end

--- close the radial ring and stop the cursor tracking loop.
function live.close()
    isOpen = false
    activeRingID = nil
    activeSlots = nil
    lastHoveredIndex = nil

    local frame = view.get_frame()
    if frame then
        frame:SetScript("OnUpdate", nil)
        frame:Hide()
    end
    view.set_active_slot(nil)
end

--- check if the radial ring is currently open on screen.
--- @return boolean
function live.is_open()
    return isOpen
end
