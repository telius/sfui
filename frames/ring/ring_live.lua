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

local activeScale = 1
local function update_scale()
    local s = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
    activeScale = (s and s > 0) and s or 1
end

local function get_cursor_pos()
    local curX, curY = GetCursorPosition()
    return (curX or 0) / activeScale, (curY or 0) / activeScale
end

local isOpen = false
local originX = 0
local originY = 0
local activeRingID = nil
local activeSlots = nil
local defaultSlotIndex = nil
local lastHoveredIndex = nil
local lastScaledX = -9999
local lastScaledY = -9999

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

    -- 1. smooth radial animations (opening expansion and hover scale lerp)
    if view and view.update_animations then
        view.update_animations(elapsed)
    end

    -- 2. throttled cooldown updates (20 fps)
    if cdThrottle >= 0.05 then
        cdThrottle = 0
        if view and view.update_live_state then
            view.update_live_state()
        end
    end

    -- 3. cursor tracking & slot selection (throttled to ~60 fps)
    if updateThrottle >= 0.016 then
        updateThrottle = 0

        local curX, curY = GetCursorPosition()
        if curX and curY then
            local scaledX = curX / activeScale
            local scaledY = curY / activeScale

            -- blizzard-style early exit if cursor coordinates have not changed
            if scaledX ~= lastScaledX or scaledY ~= lastScaledY then
                lastScaledX = scaledX
                lastScaledY = scaledY

                local dx = scaledX - originX
                local dy = scaledY - originY

                local total = #activeSlots
                local deadzone = (sfui.db and sfui.db.Get("ring", "deadzone", 28)) or 28

                local rawIdx = geom.point_to_slot(dx, dy, total, deadzone)
                local idx = rawIdx or defaultSlotIndex

                if idx ~= lastHoveredIndex then
                    lastHoveredIndex = idx
                    view.set_active_slot(idx)

                    local soundEnabled = (sfui.db and sfui.db.Get("ring", "sound_cues", true))
                    if soundEnabled and idx and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
                        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON, "Master")
                    end
                end
            end
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

    local sec = sfui.ring.secure
    local defIdx = (sec and sec.get_last_slot_index and sec.get_last_slot_index(ringID)) or nil
    if defIdx and (defIdx < 1 or defIdx > #slots) then
        defIdx = nil
    end

    activeRingID = ringID
    activeSlots = slots
    defaultSlotIndex = defIdx
    lastHoveredIndex = defIdx
    isOpen = true
    updateThrottle = 0
    cdThrottle = 0
    lastScaledX = -9999
    lastScaledY = -9999

    update_scale()
    originX, originY = get_cursor_pos()

    local frame = view.get_frame()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", originX, originY)

    view.render_ring(ringID, slots, title)
    view.set_active_slot(defaultSlotIndex)

    frame:Show()
    frame:SetScript("OnUpdate", on_live_update)
end

function live.sync_default_slot(ringID, idx)
    if not isOpen or activeRingID ~= ringID then return end
    local remember = (sfui.db and sfui.db.Get("ring", "remember_last", true)) ~= false
    if not remember or not activeSlots or not idx or idx < 1 or idx > #activeSlots then
        idx = nil
    end
    defaultSlotIndex = idx
end

--- close the radial ring and stop the cursor tracking loop.
function live.close()
    isOpen = false
    activeRingID = nil
    activeSlots = nil
    defaultSlotIndex = nil
    lastHoveredIndex = nil
    lastScaledX = -9999
    lastScaledY = -9999
    updateThrottle = 0
    cdThrottle = 0

    if sfui.ring.secure and sfui.ring.secure.clear_cancel_bindings then
        sfui.ring.secure.clear_cancel_bindings()
    end

    local frame = view.get_frame()
    if frame then
        frame:SetScript("OnUpdate", nil)
        frame:Hide()
    end
    view.set_active_slot(nil)
    if view and view.on_close then
        view.on_close()
    end
end

--- check if the radial ring is currently open on screen.
--- @return boolean
function live.is_open()
    return isOpen
end

if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("UI_SCALE_CHANGED", function()
        if isOpen then
            update_scale()
        end
    end)
end
