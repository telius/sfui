local addonName, addon = ...
sfui = sfui or {}
sfui.tracker = sfui.tracker or {}
sfui.tracker.blocks = sfui.tracker.blocks or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/quests/engine/blocks.lua
--  High-Performance Zero-Allocation Frame Pools for Tracker UI
-- ══════════════════════════════════════════════════════════════════════════════

local _G = _G
local CreateFrame, UIParent = _G.CreateFrame, _G.UIParent
local GameTooltip = _G.GameTooltip
local table_insert, table_remove = _G.table.insert, _G.table.remove
local ipairs, pairs, unpack = _G.ipairs, _G.pairs, _G.unpack

local Blocks = sfui.tracker.blocks

-- ─── Frame Pools ────────────────────────────────────────────────────────────
local headerPool, activeHeaders = {}, {}
local blockPool,  activeBlocks  = {}, {}
local linePool,   activeLines   = {}, {}
local barPool,    activeBars    = {}, {}

-- ─── UI Markers & Glyphs (Font-safe ASCII & Blizzard Textures) ─────────────
Blocks.ICONS = {
    COLLAPSED = "+",
    EXPANDED  = "-",
    BULLET    = "-",
    COMPLETED = "",
}

-- ─── Helpers ────────────────────────────────────────────────────────────────
local function GetFont(size, flags)
    local f = (sfui.config and sfui.config.fontFile)
        or (sfui.config and sfui.config.fonts and sfui.config.fonts.regular)
        or (_G.STANDARD_TEXT_FONT and _G.STANDARD_TEXT_FONT ~= "" and _G.STANDARD_TEXT_FONT)
        or (_G.GameFontNormal and _G.GameFontNormal.GetFont and _G.GameFontNormal:GetFont())
        or "Fonts\\FRIZQT__.TTF"
    return f, size or 12, flags or ""
end

-- ─── Section Header Factory & Pool ──────────────────────────────────────────
local function CreateHeader(parent)
    local h = CreateFrame("Button", nil, parent, "BackdropTemplate")
    h:SetHeight(20)
    h:EnableMouse(true)
    h:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local mult = (sfui.pixelScale or 1)
    h:SetBackdrop({
        bgFile   = [[Interface\Buttons\WHITE8x8]],
        edgeFile = [[Interface\Buttons\WHITE8x8]],
        edgeSize = mult,
    })
    h:SetBackdropColor(0, 0, 0, 0.50)
    h:SetBackdropBorderColor(0, 0, 0, 0.50)

    -- Left 3px color accent bar
    local accent = h:CreateTexture(nil, "ARTWORK")
    accent:SetWidth(3)
    accent:SetPoint("TOPLEFT",    h, "TOPLEFT",    0, 0)
    accent:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 0)
    accent:SetColorTexture(1, 1, 1, 1)
    h.accent = accent

    -- Section title label (anchored with PAD_X = 8)
    local title = h:CreateFontString(nil, "OVERLAY")
    local fontPath, fontSize = GetFont(12, "")
    title:SetFont(fontPath, fontSize, "")
    title:SetPoint("LEFT", h, "LEFT", 8, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    h.title = title

    -- Count badge on the right (-PAD_X = -8)
    local count = h:CreateFontString(nil, "OVERLAY")
    local cFont, cSize = GetFont(11, "")
    count:SetFont(cFont, cSize, "")
    count:SetPoint("RIGHT", h, "RIGHT", -8, 0)
    count:SetJustifyH("RIGHT")
    h.count = count

    title:SetPoint("RIGHT", count, "LEFT", -4, 0)

    h:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.08, 0.08, 0.08, 0.65)
        local tip = _G.GameTooltip
        if not tip then return end
        tip:SetOwner(self, "ANCHOR_RIGHT")
        tip:ClearLines()
        local col = self.defColor or { 1, 1, 1 }
        tip:AddLine(self.defLabel or (self.title and self.title:GetText()) or "Section", col[1] or 1, col[2] or 1, col[3] or 1)
        if self.capFormatted then
            tip:AddLine("quest log: " .. self.capFormatted, 1, 1, 1)
        end
        tip:AddLine("|cff888888Left-click: Collapse/Expand section|r", 1, 1, 1)
        tip:AddLine("|cff888888Shift-click: Untrack all quests in category|r", 1, 1, 1)
        tip:Show()
    end)

    h:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0, 0, 0, 0.50)
        local tip = _G.GameTooltip
        if tip then tip:Hide() end
    end)

    h:EnableMouseWheel(true)
    h:SetScript("OnMouseWheel", function(self, delta)
        if sfui.tracker and sfui.tracker.OnMouseWheel then
            sfui.tracker.OnMouseWheel(self, delta)
        end
    end)

    return h
end

function Blocks.AcquireHeader(parent)
    local h = table_remove(headerPool)
    if not h then
        h = CreateHeader(parent)
    else
        h:SetParent(parent)
        h:ClearAllPoints()
        h:SetBackdropColor(0, 0, 0, 0.50)
        h:SetBackdropBorderColor(0, 0, 0, 0.50)
        if h.accent then
            h.accent:SetColorTexture(1, 1, 1, 1)
        end
    end
    h:Show()
    table_insert(activeHeaders, h)
    return h
end

-- ─── Block Factory & Pool (Entity Card) ─────────────────────────────────────
local function CreateBlock(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(18)
    b:EnableMouse(true)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Subtle hover-only tint
    local hl = b:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0)
    b.hl = hl

    -- Supertrack dot (purple, 4x4)
    local dot = b:CreateTexture(nil, "OVERLAY")
    dot:SetSize(4, 4)
    dot:SetPoint("LEFT", b, "LEFT", 2, 0)
    dot:SetColorTexture(0.55, 0.35, 1.0, 1)
    dot:Hide()
    b.dot = dot

    -- Left POI / Waypoint Icon
    local poi = b:CreateTexture(nil, "ARTWORK")
    poi:SetSize(16, 16)
    poi:SetPoint("LEFT", b, "LEFT", 0, 0)
    poi:Hide()
    b.poi = poi

    -- SuperTrack glow indicator
    local stGlow = b:CreateTexture(nil, "BACKGROUND")
    stGlow:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
    stGlow:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
    stGlow:SetColorTexture(1.0, 0.82, 0.0, 0.12)
    stGlow:Hide()
    b.stGlow = stGlow

    -- Title FontString
    local title = b:CreateFontString(nil, "OVERLAY")
    local fontPath, fontSize = GetFont(12, "")
    title:SetFont(fontPath, fontSize, "")
    title:SetPoint("LEFT", b, "LEFT", 8, 0)
    title:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    b.title = title

    b:SetScript("OnEnter", function(self)
        if self.hl then self.hl:SetColorTexture(1, 1, 1, 0.04) end
        if self._onEnter then self._onEnter(self) end
    end)
    b:SetScript("OnLeave", function(self)
        if self.hl then self.hl:SetColorTexture(1, 1, 1, 0) end
        if self._onLeave then self._onLeave(self) end
    end)

    -- Sub-element container arrays
    b.lines = {}
    b.bars = {}

    b:EnableMouseWheel(true)
    b:SetScript("OnMouseWheel", function(self, delta)
        if sfui.tracker and sfui.tracker.OnMouseWheel then
            sfui.tracker.OnMouseWheel(self, delta)
        end
    end)

    return b
end

function Blocks.AcquireBlock(parent)
    local b = table_remove(blockPool)
    if not b then
        b = CreateBlock(parent)
    else
        b:SetParent(parent)
        b:ClearAllPoints()
        b.poi:Hide()
        b.dot:Hide()
        b.stGlow:Hide()
        if b.hl then b.hl:SetColorTexture(1, 1, 1, 0) end
        b.title:ClearAllPoints()
        b.title:SetPoint("LEFT", b, "LEFT", 8, 0)
        b.title:SetPoint("RIGHT", b, "RIGHT", -4, 0)
        b.title:SetText("")
        b.title:SetTextColor(1, 1, 1, 1)
    end
    b._onEnter = nil
    b._onLeave = nil
    b.itemButton = nil
    b.timerBarFrame = nil
    b.findGroupBtn = nil
    b:SetScript("OnClick", nil)
    b:Show()
    table_insert(activeBlocks, b)
    return b
end

-- ─── Objective Line Factory & Pool ──────────────────────────────────────────
local function CreateLine(parent)
    local l = CreateFrame("Frame", nil, parent)
    l:SetHeight(14)

    local bullet = l:CreateFontString(nil, "OVERLAY")
    local fontPath, fontSize = GetFont(11, "")
    bullet:SetFont(fontPath, fontSize, "")
    bullet:SetPoint("LEFT", l, "LEFT", 4, 0)
    bullet:SetTextColor(0.6, 0.6, 0.6, 1)
    bullet:SetText(Blocks.ICONS.BULLET)
    l.bullet = bullet

    local text = l:CreateFontString(nil, "OVERLAY")
    text:SetFont(fontPath, fontSize, "")
    text:SetPoint("LEFT", bullet, "RIGHT", 4, 0)
    text:SetPoint("RIGHT", l, "RIGHT", -2, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)
    l.text = text

    l:EnableMouseWheel(true)
    l:SetScript("OnMouseWheel", function(self, delta)
        if sfui.tracker and sfui.tracker.OnMouseWheel then
            sfui.tracker.OnMouseWheel(self, delta)
        end
    end)

    return l
end

function Blocks.AcquireLine(parent)
    local l = table_remove(linePool)
    if not l then
        l = CreateLine(parent)
    else
        l:SetParent(parent)
        l:ClearAllPoints()
        l.bullet:SetText(Blocks.ICONS.BULLET)
        l.bullet:SetTextColor(0.6, 0.6, 0.6, 1)
        l.text:SetText("")
        l.text:SetTextColor(0.85, 0.85, 0.85, 1)
    end
    l:EnableMouse(false)
    l:SetScript("OnEnter", nil)
    l:SetScript("OnLeave", nil)
    l:SetScript("OnMouseUp", nil)
    l:Show()
    table_insert(activeLines, l)
    return l
end

local function GetBarTexture()
    if sfui.widgets and sfui.widgets.get_bar_texture then
        return sfui.widgets.get_bar_texture()
    end
    local textureName = SfuiDB and SfuiDB.barTexture
    local LSM = _G.LibStub and _G.LibStub("LibSharedMedia-3.0", true)
    local texturePath
    if LSM and textureName then
        texturePath = LSM:Fetch("statusbar", textureName)
    end
    if not texturePath or texturePath == "" then
        texturePath = (sfui.config and sfui.config.barTexture) or "Interface/Buttons/WHITE8X8"
    end
    return texturePath
end

-- ─── Status Bar Factory & Pool ──────────────────────────────────────────────
local function CreateBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(10)
    bar:SetStatusBarTexture(GetBarTexture())
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)
    bar:SetStatusBarColor(0.40, 0.00, 1.00, 0.90)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.1, 0.8)
    bar.bg = bg

    -- 1px black border around the progress bar
    local borderTop = bar:CreateTexture(nil, "OVERLAY", nil, 1)
    borderTop:SetColorTexture(0, 0, 0, 1)
    borderTop:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
    borderTop:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 1, 1)
    borderTop:SetHeight(1)
    bar.borderTop = borderTop

    local borderBottom = bar:CreateTexture(nil, "OVERLAY", nil, 1)
    borderBottom:SetColorTexture(0, 0, 0, 1)
    borderBottom:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", -1, -1)
    borderBottom:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
    borderBottom:SetHeight(1)
    bar.borderBottom = borderBottom

    local borderLeft = bar:CreateTexture(nil, "OVERLAY", nil, 1)
    borderLeft:SetColorTexture(0, 0, 0, 1)
    borderLeft:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
    borderLeft:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", -1, -1)
    borderLeft:SetWidth(1)
    bar.borderLeft = borderLeft

    local borderRight = bar:CreateTexture(nil, "OVERLAY", nil, 1)
    borderRight:SetColorTexture(0, 0, 0, 1)
    borderRight:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 1, 1)
    borderRight:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)
    borderRight:SetWidth(1)
    bar.borderRight = borderRight

    local text = bar:CreateFontString(nil, "OVERLAY", nil, 2)
    local fontPath, fontSize = GetFont(10, "")
    text:SetFont(fontPath, fontSize, "")
    text:SetShadowOffset(0, 0)
    text:SetShadowColor(0, 0, 0, 0)
    text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    text:SetTextColor(1, 1, 1, 1)
    bar.text = text

    bar:EnableMouseWheel(true)
    bar:SetScript("OnMouseWheel", function(self, delta)
        if sfui.tracker and sfui.tracker.OnMouseWheel then
            sfui.tracker.OnMouseWheel(self, delta)
        end
    end)

    return bar
end

function Blocks.AcquireBar(parent)
    local bar = table_remove(barPool)
    if not bar then
        bar = CreateBar(parent)
    else
        bar:SetParent(parent)
        bar:ClearAllPoints()
        bar:SetValue(0)
        bar.text:SetText("")
    end
    bar:SetStatusBarTexture(GetBarTexture())
    bar:SetStatusBarColor(0.40, 0.00, 1.00, 0.90)
    bar.text:SetShadowOffset(0, 0)
    bar.text:SetShadowColor(0, 0, 0, 0)
    bar:EnableMouse(false)
    bar:SetScript("OnEnter", nil)
    bar:SetScript("OnLeave", nil)
    bar:SetScript("OnMouseUp", nil)
    bar:Show()
    table_insert(activeBars, bar)
    return bar
end

function Blocks.SetBarTexture(texturePath)
    local tex = texturePath or GetBarTexture()
    for _, b in ipairs(activeBars) do
        b:SetStatusBarTexture(tex)
    end
    for _, b in ipairs(barPool) do
        b:SetStatusBarTexture(tex)
    end
end

-- ─── Frame Recycler / Layout Cleanup ────────────────────────────────────────
function Blocks.ResetAll()
    for i = #activeHeaders, 1, -1 do
        local h = table_remove(activeHeaders, i)
        h:Hide()
        h:ClearAllPoints()
        table_insert(headerPool, h)
    end

    for i = #activeBlocks, 1, -1 do
        local b = table_remove(activeBlocks, i)
        b:Hide()
        b:ClearAllPoints()
        if b.itemButton then
            local itemsHelper = sfui.tracker.helpers and sfui.tracker.helpers.items
            if itemsHelper then
                itemsHelper.ReleaseItemButton(b.itemButton)
            else
                b.itemButton:Hide()
            end
            b.itemButton = nil
        end
        if b.timerBarFrame then
            local timerHelper = sfui.tracker.helpers and sfui.tracker.helpers.timerbars
            if timerHelper then
                timerHelper.ReleaseTimerBar(b.timerBarFrame)
            else
                b.timerBarFrame:Hide()
            end
            b.timerBarFrame = nil
        end
        if b.findGroupBtn then
            local findGroupHelper = sfui.tracker.helpers and sfui.tracker.helpers.findgroup
            if findGroupHelper then
                findGroupHelper.ReleaseFindGroupButton(b.findGroupBtn)
            else
                b.findGroupBtn:Hide()
            end
            b.findGroupBtn = nil
        end
        table_insert(blockPool, b)
    end

    for i = #activeLines, 1, -1 do
        local l = table_remove(activeLines, i)
        l:Hide()
        l:ClearAllPoints()
        table_insert(linePool, l)
    end

    for i = #activeBars, 1, -1 do
        local bar = table_remove(activeBars, i)
        bar:Hide()
        bar:ClearAllPoints()
        table_insert(barPool, bar)
    end
end

function Blocks.GetPoolStats()
    return {
        headersActive = #activeHeaders,
        headersPooled = #headerPool,
        blocksActive  = #activeBlocks,
        blocksPooled  = #blockPool,
        linesActive   = #activeLines,
        linesPooled   = #linePool,
        barsActive    = #activeBars,
        barsPooled    = #barPool,
    }
end
