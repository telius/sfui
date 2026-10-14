local addonName, addon = ...
sfui = sfui or {}
sfui.ring = sfui.ring or {}
sfui.ring.geom = sfui.ring.geom or {}

local geom = sfui.ring.geom

local math_rad = math.rad
local math_sin = math.sin
local math_cos = math.cos
local math_floor = math.floor
local math_sqrt = math.sqrt
local math_atan2 = math.atan2
local math_deg = math.deg

-- wow's global atan2(dx, dy) returns degrees clockwise from 12 o'clock.
-- provide a fallback using math.atan2 if invoked outside the wow client.
local function get_theta_deg(dx, dy)
    if _G.atan2 then
        local t = _G.atan2(dx, dy)
        if t < 0 then t = t + 360 end
        return t
    end
    local rad = math_atan2(dx, dy)
    local deg = math_deg(rad)
    if deg < 0 then deg = deg + 360 end
    return deg
end

--- calculate the center angle (in degrees, 0 = 12 o'clock, clockwise) for a given slot index.
--- @param index number 1-based slot index
--- @param total number total slots in ring
--- @return number angle in degrees [0, 360)
function geom.get_slot_angle(index, total)
    if not total or total <= 0 then return 0 end
    local step = 360 / total
    return ((index - 1) * step) % 360
end

--- calculate the cartesian (x, y) offset for a slot relative to the ring center.
--- @param index number 1-based slot index
--- @param total number total slots in ring
--- @param radius number radius in pixels
--- @return number dx, number dy
function geom.get_slot_offset(index, total, radius)
    if not total or total <= 0 then return 0, 0 end
    radius = radius or 90
    local angle = geom.get_slot_angle(index, total)
    local rad = math_rad(angle)
    -- dx is positive right (sin), dy is positive up (cos)
    local dx = radius * math_sin(rad)
    local dy = radius * math_cos(rad)
    return dx, dy
end

--- map an angle in degrees [0, 360) to the corresponding slot index.
--- @param theta number angle in degrees
--- @param total number total slots in ring
--- @return number 1-based slot index
function geom.angle_to_slot(theta, total)
    if not total or total <= 0 then return 1 end
    if total == 1 then return 1 end
    local step = 360 / total
    local rel = (theta + step * 0.5) % 360
    local idx = math_floor(rel / step) + 1
    if idx > total then idx = 1 end
    return idx
end

--- determine the active slot from mouse delta (dx, dy) relative to ring center.
--- @param dx number x delta in ui units
--- @param dy number y delta in ui units
--- @param total number total slots in ring
--- @param deadzone number minimum distance before slot is active
--- @return number|nil slotIndex (nil if inside deadzone), number dist, number theta
function geom.point_to_slot(dx, dy, total, deadzone)
    deadzone = deadzone or 24
    local dist = math_sqrt(dx * dx + dy * dy)
    if dist < deadzone then
        return nil, dist, 0
    end
    if not total or total <= 0 then
        return nil, dist, 0
    end
    local theta = get_theta_deg(dx, dy)
    local idx = geom.angle_to_slot(theta, total)
    return idx, dist, theta
end
