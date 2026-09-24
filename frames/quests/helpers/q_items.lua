--[[
    SFUI Tracker Helper: Usable Items Engine
    frames/quests/helpers/items.lua

    Modular usable item controller for quest tracker rows.
    Handles:
      - Item detection & charges formatting
      - Throttled range checking via sfui.events.RegisterUpdate
      - Quest blob inside-state glow animation
      - Cooldown updates on BAG_UPDATE_COOLDOWN
      - Shift-Click chat linking & tooltip integration
]]

local addonName, addon = ...
sfui = sfui or {}
sfui.tracker = sfui.tracker or {}
sfui.tracker.helpers = sfui.tracker.helpers or {}

local Items = {}
sfui.tracker.helpers.items = Items

-- Backward compatibility aliases
sfui.questlog = sfui.questlog or {}
sfui.questlog.items = Items

local _G = _G
local CreateFrame = _G.CreateFrame
local GetQuestLogSpecialItemInfo = _G.GetQuestLogSpecialItemInfo
local GetQuestLogSpecialItemCooldown = _G.GetQuestLogSpecialItemCooldown
local IsQuestLogSpecialItemInRange = _G.IsQuestLogSpecialItemInRange
local UseQuestLogSpecialItem = _G.UseQuestLogSpecialItem
local C_Minimap = _G.C_Minimap
local IsShiftKeyDown = _G.IsShiftKeyDown
local ChatEdit_GetActiveWindow = _G.ChatEdit_GetActiveWindow
local ChatEdit_InsertLink = _G.ChatEdit_InsertLink
local ChatFrameUtil = _G.ChatFrameUtil
local pairs, next, tostring = _G.pairs, _G.next, _G.tostring
local table_insert, table_remove = _G.table.insert, _G.table.remove

local issecretvalue = (sfui.common and sfui.common.issecretvalue) or _G.issecretvalue or function() return false end

-- Active tracked item buttons for throttled range checking
local activeButtons = {}
local itemButtonPool = {}
local isRangeWatcherActive = false

-- ─────────────────────────────────────────────────────────
--  RANGE CHECK UPDATE LOOP (Throttled at 5Hz / 0.20s)
-- ─────────────────────────────────────────────────────────
local function OnRangeUpdate()
    if not next(activeButtons) then
        if isRangeWatcherActive then
            sfui.events.UnregisterUpdate("QuestItemRange")
            isRangeWatcherActive = false
        end
        return
    end

    if not IsQuestLogSpecialItemInRange then return end

    for btn in pairs(activeButtons) do
        if not btn:IsShown() or not btn.questLogIndex then
            activeButtons[btn] = nil
        else
            local inRange = IsQuestLogSpecialItemInRange(btn.questLogIndex)
            local dot = btn.RangeDot
            if inRange == 0 then
                -- Out of range: Red dot
                dot:SetColorTexture(1.0, 0.2, 0.2, 0.95)
                dot:Show()
            elseif inRange == 1 then
                -- In range with valid target: Gray dot
                dot:SetColorTexture(0.7, 0.7, 0.7, 0.85)
                dot:Show()
            else
                -- No target or range check not applicable
                dot:Hide()
            end
        end
    end
end

local function StartRangeWatcher()
    if not isRangeWatcherActive then
        sfui.events.RegisterUpdate("QuestItemRange", 0.20, OnRangeUpdate)
        isRangeWatcherActive = true
    end
end

-- ─────────────────────────────────────────────────────────
--  COOLDOWN UPDATES
-- ─────────────────────────────────────────────────────────
local function UpdateButtonCooldown(btn)
    if not btn or not btn.questLogIndex or not GetQuestLogSpecialItemCooldown then return end
    local start, duration, enable = GetQuestLogSpecialItemCooldown(btn.questLogIndex)
    if start and duration and duration > 0 and enable ~= 0 then
        btn.Cooldown:SetCooldown(start, duration)
    else
        btn.Cooldown:Clear()
    end
end

local function UpdateAllCooldowns()
    for btn in pairs(activeButtons) do
        if btn:IsShown() then
            UpdateButtonCooldown(btn)
        end
    end
end

-- ─────────────────────────────────────────────────────────
--  BLOB GLOW PULSE
-- ─────────────────────────────────────────────────────────
local function UpdateBlobGlow(btn)
    if not btn or not btn.questID or not C_Minimap or not C_Minimap.IsInsideQuestBlob then return end
    local inside = C_Minimap.IsInsideQuestBlob(btn.questID)
    if inside and not btn.isGlowing then
        btn.isGlowing = true
        if btn.GlowTex then btn.GlowTex:Show() end
    elseif not inside and btn.isGlowing then
        btn.isGlowing = false
        if btn.GlowTex then btn.GlowTex:Hide() end
    end
end

-- ─────────────────────────────────────────────────────────
--  ITEM INFO RESOLVER
-- ─────────────────────────────────────────────────────────
function Items.GetQuestItemInfo(questLogIndex, isComplete)
    if not questLogIndex or not GetQuestLogSpecialItemInfo then return nil end
    local link, itemTex, charges, showItemWhenComplete = GetQuestLogSpecialItemInfo(questLogIndex)
    if not itemTex or issecretvalue(itemTex) then return nil end

    if isComplete and not showItemWhenComplete then
        return nil
    end

    return {
        link             = link,
        texture          = itemTex,
        charges          = (charges and not issecretvalue(charges) and charges > 0) and charges or 0,
        showWhenComplete = showItemWhenComplete,
    }
end

-- ─────────────────────────────────────────────────────────
--  BUTTON FACTORY
-- ─────────────────────────────────────────────────────────
function Items.CreateItemButton(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(16, 16)

    -- Background frame
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.08, 0.90)
    btn.BG = bg

    -- Icon texture (cropped square)
    local icon = btn:CreateTexture(nil, "BORDER")
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.Icon = icon

    -- 1px Border
    if sfui.common and sfui.common.create_border then
        sfui.common.create_border(btn, 1, { 0.25, 0.25, 0.25, 0.9 })
    end

    -- Cooldown frame
    local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    cd:SetAllPoints(icon)
    cd:SetDrawEdge(true)
    cd:SetDrawBling(false)
    cd:SetSwipeColor(0, 0, 0, 0.75)
    btn.Cooldown = cd

    -- Charge Count FontString
    local count = btn:CreateFontString(nil, "OVERLAY")
    local fontPath = (sfui.config and sfui.config.fontFile)
        or (_G.STANDARD_TEXT_FONT and _G.STANDARD_TEXT_FONT ~= "" and _G.STANDARD_TEXT_FONT)
        or (_G.GameFontNormal and _G.GameFontNormal.GetFont and _G.GameFontNormal:GetFont())
        or "Fonts\\FRIZQT__.TTF"
    count:SetFont(fontPath, 10, "OUTLINE")
    count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
    count:SetTextColor(1, 1, 1, 1)
    btn.Count = count

    -- Range Indicator Dot
    local rangeDot = btn:CreateTexture(nil, "OVERLAY")
    rangeDot:SetSize(4, 4)
    rangeDot:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -1)
    rangeDot:SetColorTexture(1.0, 0.2, 0.2, 0.95)
    rangeDot:Hide()
    btn.RangeDot = rangeDot

    -- Blob highlight / pulse glow
    local glow = btn:CreateTexture(nil, "OVERLAY")
    glow:SetPoint("TOPLEFT", btn, "TOPLEFT", -2, 2)
    glow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -2)
    glow:SetColorTexture(1.0, 0.85, 0.1, 0.35)
    glow:Hide()
    btn.GlowTex = glow

    -- Highlight Texture on Hover
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(icon)
    hl:SetColorTexture(1, 1, 1, 0.15)

    -- Scripts
    btn:RegisterForClicks("AnyUp")
    btn:SetScript("OnClick", function(self, button)
        local qlIndex = self.questLogIndex
        if not qlIndex then return end

        if IsShiftKeyDown and IsShiftKeyDown() then
            local activeChat = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
            if activeChat and activeChat:IsShown() and activeChat:HasFocus() then
                local link = self.itemLink or (GetQuestLogSpecialItemInfo and GetQuestLogSpecialItemInfo(qlIndex))
                if link and ChatFrameUtil and ChatFrameUtil.InsertLink then
                    if ChatFrameUtil.InsertLink(link) then return end
                end
                if link and ChatEdit_InsertLink then
                    if ChatEdit_InsertLink(link) then return end
                end
            end
        end

        if UseQuestLogSpecialItem then
            UseQuestLogSpecialItem(qlIndex)
        end
    end)

    btn:SetScript("OnEnter", function(self)
        local qlIndex = self.questLogIndex
        local tip = (sfui.common and sfui.common.get_tooltip and sfui.common.get_tooltip()) or _G.GameTooltip
        if tip and qlIndex then
            local anchor = (sfui.tracker and sfui.tracker.helpers and sfui.tracker.helpers.tooltip and sfui.tracker.helpers.tooltip.PickAnchor and sfui.tracker.helpers.tooltip.PickAnchor(self)) or "ANCHOR_RIGHT"
            tip:SetOwner(self, anchor)
            if tip.SetQuestLogSpecialItem then
                tip:SetQuestLogSpecialItem(qlIndex)
            end
            tip:Show()
        end
    end)

    btn:SetScript("OnLeave", function()
        local tip = (sfui.common and sfui.common.get_tooltip and sfui.common.get_tooltip()) or _G.GameTooltip
        if tip then tip:Hide() end
    end)

    btn:EnableMouseWheel(true)
    btn:SetScript("OnMouseWheel", function(self, delta)
        if sfui.tracker and sfui.tracker.OnMouseWheel then
            sfui.tracker.OnMouseWheel(self, delta)
        end
    end)

    btn:Hide()
    return btn
end

function Items.AcquireItemButton(parent)
    local btn = table_remove(itemButtonPool)
    if not btn then
        btn = Items.CreateItemButton(parent)
    else
        btn:SetParent(parent)
        btn:ClearAllPoints()
    end
    return btn
end

-- ─────────────────────────────────────────────────────────
--  BUTTON SETUP & RELEASE
-- ─────────────────────────────────────────────────────────
function Items.SetupItemButton(btn, questLogIndex, questID, itemInfo)
    if not btn or not itemInfo then return end

    btn.questLogIndex = questLogIndex
    btn.questID = questID
    btn.itemLink = itemInfo.link

    btn.Icon:SetTexture(itemInfo.texture)

    if itemInfo.charges and itemInfo.charges > 1 then
        btn.Count:SetText(tostring(itemInfo.charges))
        btn.Count:Show()
    else
        btn.Count:SetText("")
        btn.Count:Hide()
    end

    UpdateButtonCooldown(btn)
    UpdateBlobGlow(btn)

    btn:Show()
    activeButtons[btn] = true
    StartRangeWatcher()
end

function Items.ReleaseItemButton(btn)
    if not btn then return end
    activeButtons[btn] = nil
    btn.questLogIndex = nil
    btn.questID = nil
    btn.itemLink = nil
    btn.isGlowing = false
    if btn.GlowTex then btn.GlowTex:Hide() end
    if btn.RangeDot then btn.RangeDot:Hide() end
    btn:Hide()
    btn:ClearAllPoints()
    table_insert(itemButtonPool, btn)

    if not next(activeButtons) and isRangeWatcherActive then
        sfui.events.UnregisterUpdate("QuestItemRange")
        isRangeWatcherActive = false
    end
end

function Items.GetPoolStats()
    local act = 0
    for btn in pairs(activeButtons) do
        if btn and btn:IsShown() then
            act = act + 1
        end
    end
    return {
        activeButtons   = act,
        pooledButtons   = #itemButtonPool,
        isWatcherActive = isRangeWatcherActive,
    }
end

-- ─────────────────────────────────────────────────────────
--  EVENT LISTENERS
-- ─────────────────────────────────────────────────────────
if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("BAG_UPDATE_COOLDOWN", UpdateAllCooldowns)
    sfui.events.RegisterEvent("PLAYER_TARGET_CHANGED", function()
        if isRangeWatcherActive then
            OnRangeUpdate()
        end
    end)
    sfui.events.RegisterEvent("PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED", function(event, questID, inside)
        for btn in pairs(activeButtons) do
            if btn.questID == questID then
                UpdateBlobGlow(btn)
            end
        end
    end)
end

return Items
