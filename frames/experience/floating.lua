local addonName, addon = ...
sfui = sfui or {}
sfui.experience = sfui.experience or {}
sfui.experience.floating = {}

local floating = sfui.experience.floating

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/experience/floating.lua
--  Floating micro-text notifications on experience gain using AnimationGroups
-- ══════════════════════════════════════════════════════════════════════════════

local _G = _G
local CreateFrame = _G.CreateFrame
local table_insert = table.insert
local table_remove = table.remove
local string_format = string.format

local pool = {}
local activeFrames = {}
local parentAnchor = nil

--- Set the anchor parent frame above which floating text will appear
--- @param frame Frame
function floating.SetAnchor(frame)
    parentAnchor = frame
end

--- Get current floating frame pool statistics
--- @return number activeCount, number poolCount
function floating.GetPoolStats()
    return #activeFrames, #pool
end

--- Create a new pooled floating text frame
--- @return Frame
local function CreateFloatingFrame()
    local f = CreateFrame("Frame", nil, parentAnchor or _G.UIParent)
    f:SetSize(200, 20)
    f:SetFrameStrata("HIGH")

    local text = f:CreateFontString(nil, "OVERLAY", sfui.config and sfui.config.font or "GameFontNormal")
    text:SetAllPoints(f)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    text:SetShadowOffset(1, -1)
    text:SetShadowColor(0, 0, 0, 1)
    f.text = text

    -- AnimationGroup for pure GPU-accelerated motion (zero OnUpdate CPU overhead)
    local animGroup = f:CreateAnimationGroup()

    -- Translation upward
    local translation = animGroup:CreateAnimation("Translation")
    translation:SetOffset(0, 26)
    translation:SetDuration(1.2)
    translation:SetOrder(1)
    translation:SetSmoothing("OUT")

    -- Alpha fadeout
    local alpha = animGroup:CreateAnimation("Alpha")
    alpha:SetFromAlpha(1.0)
    alpha:SetToAlpha(0.0)
    alpha:SetStartDelay(0.7)
    alpha:SetDuration(0.5)
    alpha:SetOrder(1)

    animGroup:SetScript("OnFinished", function()
        f:Hide()
        table_insert(pool, f)
        for i = #activeFrames, 1, -1 do
            if activeFrames[i] == f then
                table_remove(activeFrames, i)
                break
            end
        end
    end)

    f.animGroup = animGroup
    return f
end

--- Acquire a floating text frame from pool or create new
--- @return Frame
local function AcquireFrame()
    local f = table_remove(pool)
    if not f then
        f = CreateFloatingFrame()
    end
    table_insert(activeFrames, f)
    return f
end

--- Spawn floating XP text above the experience bar
--- @param amount number
function floating.Spawn(amount)
    if not amount or amount <= 0 then return end
    if sfui.db and sfui.db.Get and not sfui.db.Get("experience", "showFloatingText", true) then
        return
    end

    local anchor = parentAnchor or (sfui.experience.bar and sfui.experience.bar.GetFrame and sfui.experience.bar.GetFrame())
    if not anchor or not anchor:IsShown() then return end

    local f = AcquireFrame()
    f:SetParent(anchor)
    f:ClearAllPoints()

    -- Stagger multiple simultaneous gains slightly
    local offsetIndex = (#activeFrames - 1) % 3
    local xOffset = (offsetIndex == 1 and -30) or (offsetIndex == 2 and 30) or 0
    f:SetPoint("BOTTOM", anchor, "TOP", xOffset, 4)

    local formatted = (sfui.experience.data and sfui.experience.data.FormatNumber and sfui.experience.data.FormatNumber(amount)) or tostring(amount)
    f.text:SetText(string_format("|cff66ff66+%s xp|r", formatted))
    f:SetAlpha(1.0)
    f:Show()

    f.animGroup:Stop()
    f.animGroup:Play()
end

--- Cancel all active floating animations and return frames to pool
function floating.Reset()
    for i = #activeFrames, 1, -1 do
        local f = activeFrames[i]
        if f then
            if f.animGroup then f.animGroup:Stop() end
            f:Hide()
            table_insert(pool, f)
            table_remove(activeFrames, i)
        end
    end
end
