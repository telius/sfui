local addonName, addon = ...
sfui = sfui or {}
sfui.ring = sfui.ring or {}
sfui.ring.view = sfui.ring.view or {}

local view = sfui.ring.view
local geom = sfui.ring.geom

local CreateFrame  = _G.CreateFrame
local UIParent     = _G.UIParent
local type         = _G.type
local pairs        = _G.pairs
local ipairs       = _G.ipairs
local unpack       = _G.unpack

local rootFrame
local slotPool
local activeSlots = {}
local activeSlotIndex = nil
local currentRingID = nil
local currentSlotsData = nil

local function get_config()
    local db = sfui.db and sfui.db.Get
    local radius   = (db and db("ring", "radius", 95)) or 95
    local deadzone = (db and db("ring", "deadzone", 28)) or 28
    local slotSize = (db and db("ring", "slot_size", 40)) or 40
    local labels   = (db and db("ring", "show_labels", true))
    if labels == nil then labels = true end
    return radius, deadzone, slotSize, labels
end

local function create_slot_frame(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(40, 40)

    -- icon texture
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(f)
    f.icon = icon

    -- round icon style
    sfui.widgets.apply_round_icon_style(f, icon, 1.5, { 0, 0, 0, 0.85 })

    -- cooldown frame
    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetAllPoints(f)
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    if cd.SetSwipeColor then
        cd:SetSwipeColor(0, 0, 0, 0.65)
    end
    f.cooldown = cd

    -- count text
    local count = f:CreateFontString(nil, "OVERLAY", sfui.config.font_small or "GameFontHighlightSmall")
    count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    count:SetTextColor(1, 1, 1, 1)
    f.count = count

    -- slice label text
    local label = f:CreateFontString(nil, "OVERLAY", sfui.config.font_small or "GameFontHighlightSmall")
    label:SetPoint("TOP", f, "BOTTOM", 0, -4)
    label:SetTextColor(0.85, 0.85, 0.85, 1)
    label:SetWidth(80)
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)
    f.label = label

    return f
end

local function reset_slot_frame(f)
    f:Hide()
    f:ClearAllPoints()
    f:SetScale(1.0)
    f.icon:SetTexture(nil)
    f.icon:SetTexCoord(0, 1, 0, 1)
    f.icon:SetVertexColor(1, 1, 1, 1)
    f.count:SetText("")
    f.label:SetText("")
    f.label:Hide()
    if f.roundBorder then
        f.roundBorder:SetColorTexture(0, 0, 0, 0.85)
    end
    f._slotData = nil
    f._index = nil
end

local function ensure_root_frame()
    if rootFrame then return rootFrame end

    rootFrame = CreateFrame("Frame", "SfuiRingView", UIParent)
    rootFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    rootFrame:SetSize(400, 400)
    rootFrame:EnableMouse(false)
    rootFrame:Hide()

    rootFrame:HookScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        if sfui.ring.live and sfui.ring.live.is_open and sfui.ring.live.is_open() then
            sfui.ring.live.close()
        end
    end)

    -- center deadzone disc
    local dz = CreateFrame("Frame", nil, rootFrame)
    dz:SetPoint("CENTER", rootFrame, "CENTER", 0, 0)
    sfui.widgets.apply_round_icon_style(dz, nil, 1, { 0.3, 0.3, 0.3, 0.4 })
    if dz.roundBg then
        dz.roundBg:SetColorTexture(0.05, 0.05, 0.05, 0.55)
    end
    rootFrame.deadzoneDisc = dz

    -- center active action label
    local activeText = rootFrame:CreateFontString(nil, "OVERLAY", sfui.config.font or "GameFontNormal")
    activeText:SetPoint("CENTER", rootFrame, "CENTER", 0, 0)
    activeText:SetTextColor(1, 1, 1, 1)
    activeText:SetWidth(120)
    activeText:SetJustifyH("CENTER")
    rootFrame.activeText = activeText

    -- title label at top of ring
    local titleText = rootFrame:CreateFontString(nil, "OVERLAY", sfui.config.font_small or "GameFontHighlightSmall")
    titleText:SetPoint("BOTTOM", dz, "TOP", 0, 10)
    titleText:SetTextColor(0, 0.8, 1, 0.8)
    titleText:SetJustifyH("CENTER")
    rootFrame.titleText = titleText

    slotPool = sfui.common.create_pool(function()
        return create_slot_frame(rootFrame)
    end, reset_slot_frame)

    return rootFrame
end

--- clear all active slot frames back to the pool.
function view.clear_slots()
    if slotPool then
        slotPool:release_all()
    end
    for k in pairs(activeSlots) do
        activeSlots[k] = nil
    end
    activeSlotIndex = nil
end

--- render a ring definition around the center point.
--- @param ringID string
--- @param slots table list of slot definition tables
--- @param title string|nil optional title text
function view.render_ring(ringID, slots, title)
    local root = ensure_root_frame()
    view.clear_slots()

    currentRingID = ringID
    currentSlotsData = slots or {}
    local num = #currentSlotsData
    if num == 0 then return end

    local radius, deadzone, slotSize, showLabels = get_config()
    if num > 10 then
        local minCircumference = num * (slotSize + 8)
        local minRadius = math.floor(minCircumference / (2 * math.pi))
        if minRadius > radius then
            radius = minRadius
        end
    end

    -- update deadzone circle size
    local dzSize = deadzone * 2
    root.deadzoneDisc:SetSize(dzSize, dzSize)
    if root.deadzoneDisc.roundInnerMask then
        root.deadzoneDisc.roundInnerMask:SetPoint("TOPLEFT", root.deadzoneDisc, "TOPLEFT", 1, -1)
        root.deadzoneDisc.roundInnerMask:SetPoint("BOTTOMRIGHT", root.deadzoneDisc, "BOTTOMRIGHT", -1, 1)
    end

    -- update title
    root.titleText:SetText(title and title:lower() or ringID:lower())
    root.activeText:SetText("|cff666666cancel|r")

    -- position each slot
    for i = 1, num do
        local data = currentSlotsData[i]
        local frame = slotPool:acquire(root)
        frame._index = i
        frame._slotData = data
        frame:SetSize(slotSize, slotSize)

        local dx, dy = geom.get_slot_offset(i, num, radius)
        frame:SetPoint("CENTER", root, "CENTER", dx, dy)

        -- set icon
        if data.icon then
            frame.icon:SetTexture(data.icon)
            if data.texCoords then
                frame.icon:SetTexCoord(unpack(data.texCoords))
            else
                frame.icon:SetTexCoord(0, 1, 0, 1)
            end
        else
            frame.icon:SetTexture(nil)
        end

        -- set vertex tint if specified
        if data.color then
            frame.icon:SetVertexColor(data.color[1] or 1, data.color[2] or 1, data.color[3] or 1)
        else
            frame.icon:SetVertexColor(1, 1, 1)
        end

        -- set count
        if data.count and data.count > 1 then
            frame.count:SetText(data.count)
        else
            frame.count:SetText("")
        end

        -- set label
        if showLabels and data.label then
            frame.label:SetText(data.label:lower())
            frame.label:Show()
        else
            frame.label:Hide()
        end

        frame:Show()
        activeSlots[i] = frame
    end
end

--- highlight the currently selected slot, or cancel state if nil.
--- @param index number|nil 1-based slot index or nil
function view.set_active_slot(index)
    if activeSlotIndex == index then return end
    activeSlotIndex = index

    local root = ensure_root_frame()

    for i, frame in pairs(activeSlots) do
        if i == index then
            frame:SetScale(1.18)
            if frame.roundBorder then
                frame.roundBorder:SetColorTexture(0, 0.9, 1, 1)
            end
        else
            frame:SetScale(1.0)
            if frame.roundBorder then
                frame.roundBorder:SetColorTexture(0, 0, 0, 0.85)
            end
        end
    end

    if index and currentSlotsData and currentSlotsData[index] then
        local slot = currentSlotsData[index]
        local label = slot.label or slot.id or ""
        root.activeText:SetText("|cffffffff" .. label:lower() .. "|r")
        if root.deadzoneDisc.roundBorder then
            root.deadzoneDisc.roundBorder:SetColorTexture(0, 0.7, 1, 0.5)
        end
    else
        root.activeText:SetText("|cff666666cancel|r")
        if root.deadzoneDisc.roundBorder then
            root.deadzoneDisc.roundBorder:SetColorTexture(0.3, 0.3, 0.3, 0.4)
        end
    end
end

--- get the root view frame.
--- @return Frame
function view.get_frame()
    return ensure_root_frame()
end

--- get currently rendered ring ID.
--- @return string|nil
function view.get_current_ring_id()
    return currentRingID
end
