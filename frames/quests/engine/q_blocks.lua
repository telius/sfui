local addonName, addon           = ...
sfui                             = sfui or {}
sfui.tracker                     = sfui.tracker or {}
sfui.tracker.blocks              = sfui.tracker.blocks or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/quests/engine/blocks.lua
--  High-Performance Zero-Allocation Frame Pools for Tracker UI
-- ══════════════════════════════════════════════════════════════════════════════

local _G                         = _G
local CreateFrame = _G.CreateFrame
local table_insert, table_remove = _G.table.insert, _G.table.remove
local ipairs = _G.ipairs

local Blocks                     = sfui.tracker.blocks

-- ─── Frame Pools ────────────────────────────────────────────────────────────
local headerPool, activeHeaders  = {}, {}
local blockPool, activeBlocks    = {}, {}
local linePool, activeLines      = {}, {}
local barPool, activeBars        = {}, {}

-- ─── UI Markers & Glyphs (Font-safe ASCII & Blizzard Textures) ─────────────
Blocks.ICONS                     = {
    COLLAPSED = "+",
    EXPANDED  = "-",
    BULLET    = "-",
    COMPLETED = "",
}

-- ─── Helpers ────────────────────────────────────────────────────────────────
local function GetFont(size, flags)
    local f = (sfui.config and sfui.config.fonts and sfui.config.fonts.regular)
        or sfui.common.get_font_file()
    return f, size or 12, flags or ""
end

local function Tracker_OnMouseWheel(self, delta)
    sfui.tracker.OnMouseWheel(self, delta)
end

local function Header_OnEnter(self)
    if not self.isCamelotHeader then
        self:SetBackdropColor(0.08, 0.08, 0.08, 0.65)
    end
    local tip = sfui.common.get_tooltip()
    if not tip then return end
    tip:SetOwner(self, "ANCHOR_RIGHT")
    tip:ClearLines()
    local col = self.defColor or { 1, 1, 1 }
    tip:AddLine(self.defLabel or (self.title and self.title:GetText()) or "Section", col[1] or 1, col[2] or 1,
        col[3] or 1)
    if self.capFormatted then
        tip:AddLine("quest log: " .. self.capFormatted, 1, 1, 1)
    end
    tip:AddLine("|cff888888left-click: collapse/expand section|r", 1, 1, 1)
    local secID = self.secID
    local itemWord = "items"
    if secID == "challenges" or secID == "camelot_challenges" then
        itemWord = "challenges"
    elseif secID == "achievements" then
        itemWord = "achievements"
    elseif secID == "recipes" then
        itemWord = "recipes"
    elseif secID == "activities" then
        itemWord = "activities"
    elseif secID == "collectables" then
        itemWord = "collectables"
    elseif secID == "skills" then
        itemWord = "skills"
    elseif secID == "world" or secID == "worldquests" then
        itemWord = "world quests"
    elseif secID == "campaign" or secID == "important" or secID == "meta" or secID == "zone" or secID == "quests" or secID == "class" or secID == "dungeons" or secID == "professions" or (type(secID) == "string" and secID:find("^zone")) then
        itemWord = "quests"
    end
    if secID == "challenges" or secID == "camelot_challenges" then
        tip:AddLine("|cff888888right-click: open legacy challenges|r", 1, 1, 1)
    elseif secID == "achievements" then
        tip:AddLine("|cff888888right-click: open achievements|r", 1, 1, 1)
    end
    tip:AddLine("|cff888888shift-click: untrack all " .. itemWord .. " in category|r", 1, 1, 1)
    local layout = sfui.tracker and sfui.tracker.layout
    if layout and layout.CanAbandonSection and layout.CanAbandonSection(self._sec) then
        tip:AddLine("|cff888888ctrl-click: abandon all quests in section|r", 1, 1, 1)
    end
    tip:Show()
end

local function Header_OnLeave(self)
    if not self.isCamelotHeader then
        self:SetBackdropColor(0, 0, 0, 0.50)
    end
    local tip = sfui.common.get_tooltip()
    if tip then tip:Hide() end
end

local function Header_OnClick(self, button)
    if InCombatLockdown and InCombatLockdown() then return end
    local secID = self.secID
    local currentSec = self._sec
    if not secID or not currentSec then return end

    if button == "RightButton" then
        if secID == "challenges" or secID == "camelot_challenges" then
            if _G.ToggleLegacyChallenges then
                _G.ToggleLegacyChallenges()
            elseif _G.LegacySystemFrame_LoadUI then
                pcall(_G.LegacySystemFrame_LoadUI)
                if _G.LegacySystemFrame then
                    _G.LegacySystemFrame:Show()
                end
            end
            return
        elseif secID == "achievements" then
            if _G.ToggleAchievementFrame then
                _G.ToggleAchievementFrame()
            end
            return
        end
    end

    local IsControlKeyDown = _G.IsControlKeyDown
    local IsShiftKeyDown = _G.IsShiftKeyDown
    local IsAltKeyDown = _G.IsAltKeyDown
    if button ~= "RightButton" and IsControlKeyDown and IsControlKeyDown()
        and not (IsShiftKeyDown and IsShiftKeyDown())
        and not (IsAltKeyDown and IsAltKeyDown()) then
        local layout = sfui.tracker and sfui.tracker.layout
        if layout and layout.AbandonSection then
            layout.AbandonSection(currentSec)
        end
        return
    end

    if IsShiftKeyDown and IsShiftKeyDown() then
        local layout = sfui.tracker and sfui.tracker.layout
        if layout and layout.UntrackSection then
            layout.UntrackSection(currentSec)
        end
        for _, mod in ipairs(sfui.tracker.modules or {}) do
            if mod.MarkDirty then mod:MarkDirty() end
        end
        sfui.tracker.RequestRefresh(0.01)
        return
    end
    SfuiDB.questlogSectionsCollapsed = SfuiDB.questlogSectionsCollapsed or {}
    local curCollapsed
    if self._isZoneSec then
        if currentSec.isCurrentZone then
            curCollapsed = (SfuiDB.questlogSectionsCollapsed[secID] == true)
        else
            curCollapsed = (SfuiDB.questlogSectionsCollapsed[secID] ~= false)
        end
    else
        curCollapsed = (SfuiDB.questlogSectionsCollapsed[secID] == true)
    end
    SfuiDB.questlogSectionsCollapsed[secID] = not curCollapsed
    sfui.tracker.RequestRefresh(0.01)
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
    accent:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)
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

    sfui.theme.ApplyQuestHeaderStyle(h)

    h:SetScript("OnEnter", Header_OnEnter)
    h:SetScript("OnLeave", Header_OnLeave)
    h:SetScript("OnClick", Header_OnClick)
    h:EnableMouseWheel(true)
    h:SetScript("OnMouseWheel", Tracker_OnMouseWheel)

    return h
end

function Blocks.AcquireHeader(parent)
    local h = table_remove(headerPool)
    if not h then
        h = CreateHeader(parent)
    else
        h:SetParent(parent)
        h:ClearAllPoints()
        h.secID = nil
        h._sec = nil
        h._isZoneSec = nil
        sfui.theme.ApplyQuestHeaderStyle(h)
    end
    h:Show()
    table_insert(activeHeaders, h)
    return h
end

local function Block_OnClick(self, btn)
    if InCombatLockdown and InCombatLockdown() then return end
    local bData = self._bData
    if bData and bData.OnClick then
        bData.OnClick(self, btn)
    end
end

local function Block_OnEnter(self)
    if self.hl then self.hl:SetColorTexture(1, 1, 1, 0.05) end
    local bData = self._bData
    if bData then
        local tooltipHelper = sfui.tracker and sfui.tracker.helpers and sfui.tracker.helpers.tooltip
        if tooltipHelper and tooltipHelper.ShowBlockTooltip then
            tooltipHelper.ShowBlockTooltip(self, bData)
        end
        if bData.OnEnter then
            bData.OnEnter(self)
        end
    elseif self._onEnter then
        self._onEnter(self)
    end
end

local function Block_OnLeave(self)
    if self.hl then self.hl:SetColorTexture(1, 1, 1, 0) end
    local bData = self._bData
    if bData then
        local tooltipHelper = sfui.tracker and sfui.tracker.helpers and sfui.tracker.helpers.tooltip
        if tooltipHelper and tooltipHelper.HideBlockTooltip then
            tooltipHelper.HideBlockTooltip(self, bData)
        else
            local tip = sfui.common.get_tooltip()
            if tip then tip:Hide() end
        end
        if bData.OnLeave then
            bData.OnLeave(self)
        end
    elseif self._onLeave then
        self._onLeave(self)
    end
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

    b:SetScript("OnClick", Block_OnClick)
    b:SetScript("OnEnter", Block_OnEnter)
    b:SetScript("OnLeave", Block_OnLeave)

    -- Sub-element container arrays
    b.lines = {}
    b.bars = {}

    b:EnableMouseWheel(true)
    b:SetScript("OnMouseWheel", Tracker_OnMouseWheel)

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
    b._bData = nil
    b._onEnter = nil
    b._onLeave = nil
    b.itemButton = nil
    b.timerBarFrame = nil
    b.findGroupBtn = nil
    b:Show()
    table_insert(activeBlocks, b)
    return b
end

local function ChildBlock_OnEnter(self)
    local block = self._block
    local bData = self._bData
    if block and block.hl then block.hl:SetColorTexture(1, 1, 1, 0.05) end
    if block and bData then
        local tooltipHelper = sfui.tracker and sfui.tracker.helpers and sfui.tracker.helpers.tooltip
        if tooltipHelper and tooltipHelper.ShowBlockTooltip then
            tooltipHelper.ShowBlockTooltip(block, bData)
        end
    end
end

local function ChildBlock_OnLeave(self)
    local block = self._block
    local bData = self._bData
    if block and block.hl then block.hl:SetColorTexture(1, 1, 1, 0) end
    local tooltipHelper = sfui.tracker and sfui.tracker.helpers and sfui.tracker.helpers.tooltip
    if block and bData and tooltipHelper and tooltipHelper.HideBlockTooltip then
        tooltipHelper.HideBlockTooltip(block, bData)
    else
        local tip = sfui.common.get_tooltip()
        if tip then tip:Hide() end
    end
end

local function Line_OnMouseUp(self, btn)
    if InCombatLockdown and InCombatLockdown() then return end
    local bData = self._bData
    if bData and bData.OnClick then
        bData.OnClick(self._block, btn)
    end
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
    l:SetScript("OnMouseWheel", Tracker_OnMouseWheel)
    l:SetScript("OnEnter", ChildBlock_OnEnter)
    l:SetScript("OnLeave", ChildBlock_OnLeave)
    l:SetScript("OnMouseUp", Line_OnMouseUp)

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
    l._block = nil
    l._bData = nil
    l:EnableMouse(false)
    l:Show()
    table_insert(activeLines, l)
    return l
end

local function Bar_OnMouseUp(self, btn)
    if InCombatLockdown and InCombatLockdown() then return end
    local bData = self._bData
    if bData and bData.OnClick then
        bData.OnClick(self._block, btn, self._barData)
    end
end

local GetBarTexture = sfui.widgets.get_bar_texture

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
    bar:SetScript("OnMouseWheel", Tracker_OnMouseWheel)
    bar:SetScript("OnEnter", ChildBlock_OnEnter)
    bar:SetScript("OnLeave", ChildBlock_OnLeave)
    bar:SetScript("OnMouseUp", Bar_OnMouseUp)

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
    bar._block = nil
    bar._bData = nil
    bar._barData = nil
    bar:EnableMouse(false)
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
        h._sec = nil
        h._isZoneSec = nil
        h:Hide()
        h:ClearAllPoints()
        table_insert(headerPool, h)
    end

    for i = #activeBlocks, 1, -1 do
        local b = table_remove(activeBlocks, i)
        b._bData = nil
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
        l._block = nil
        l._bData = nil
        l:Hide()
        l:ClearAllPoints()
        table_insert(linePool, l)
    end

    for i = #activeBars, 1, -1 do
        local bar = table_remove(activeBars, i)
        bar._block = nil
        bar._bData = nil
        bar._barData = nil
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
