local addonName, addon                        = ...
sfui                                          = sfui or {}
sfui.lootfeed                                 = sfui.lootfeed or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/gear/lootfeed.lua
--  High-Performance, Zero-Allocation Loot & Reward Feed
--
--  Features:
--    - Items, Currency, Gold, Reputation, XP, Skills, and Party Member Loot
--    - Styled to match sfui quest headers (1px border, 3px quality accent bar)
--    - FIFO pending queue for mass reward events (e.g. Delve chests with 40+ items)
--    - Dynamic item stacking & deduplication
--    - Zero CPU footprint when idle (OnUpdate completely unhooked when empty)
--    - Frame pooling & reusable table node buffer (Zero GC churn)
-- ══════════════════════════════════════════════════════════════════════════════

local _G                                      = _G
local CreateFrame, UIParent                   = _G.CreateFrame, _G.UIParent
local GameTooltip                             = sfui.common.get_tooltip()
local hide_tooltip                            = sfui.common.hide_tooltip
local ChatEdit_InsertLink                     = _G.ChatEdit_InsertLink
local HandleModifiedItemClick                 = _G.HandleModifiedItemClick
local DressUpLink                             = _G.DressUpLink
local IsShiftKeyDown                          = _G.IsShiftKeyDown
local IsControlKeyDown                        = _G.IsControlKeyDown
local IsAltKeyDown                            = _G.IsAltKeyDown
local InCombatLockdown                        = _G.InCombatLockdown

local string_format                           = string.format
local string_match                            = string.match
local string_gsub                             = string.gsub
local math_floor                              = math.floor
local math_max                                = math.max
local table_insert                            = table.insert
local table_remove                            = table.remove
local ipairs, pairs, tonumber, tostring, type = ipairs, pairs, tonumber, tostring, type

local C_Item                                  = _G.C_Item
local GetItemInfo                             = sfui.common.get_item_info
local GetItemQualityColor                     = (C_Item and C_Item.GetItemQualityColor) or _G.GetItemQualityColor
local RequestLoadItemDataByID                 = C_Item and C_Item.RequestLoadItemDataByID
local C_CurrencyInfo                          = _G.C_CurrencyInfo

local UnitXP                                  = _G.UnitXP
local UnitXPMax                               = _G.UnitXPMax
local UnitName                                = _G.UnitName
local UnitGUID                                = _G.UnitGUID
local GetMoney                                = _G.GetMoney

local wipe                                    = _G.wipe or function(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

local function IsSecret(v)
    if v == nil then return false end
    if _G.issecretvalue and _G.issecretvalue(v) then return true end
    if sfui.common and sfui.common.issecretvalue and sfui.common.issecretvalue(v) then return true end
    return false
end


-- ─────────────────────────────────────────────────────────────────────────────
--  Constants & Pre-Cached Assets
-- ─────────────────────────────────────────────────────────────────────────────
local COIN_GOLD                               = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:1:0|t"
local COIN_SILVER                             = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:1:0|t"
local COIN_COPPER                             = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:1:0|t"
local VENDOR_ICON                             = "|TInterface\\Icons\\INV_Misc_Bag_10:12:12:1:0:64:64:5:59:5:59|t"
local SPINNER_DOT                             = "○"

local QUALITY_COLORS                          = {
    [0] = { 0.62, 0.62, 0.62 }, -- Poor (Gray)
    [1] = { 1.00, 1.00, 1.00 }, -- Common (White)
    [2] = { 0.12, 1.00, 0.00 }, -- Uncommon (Green)
    [3] = { 0.00, 0.44, 0.87 }, -- Rare (Blue)
    [4] = { 0.64, 0.21, 0.93 }, -- Epic (Purple)
    [5] = { 1.00, 0.50, 0.00 }, -- Legendary (Orange)
    [6] = { 0.90, 0.80, 0.50 }, -- Artifact (Gold)
    [7] = { 0.00, 0.80, 1.00 }, -- Heirloom (Cyan)
}

local COLOR_GOLD                              = { 1.00, 0.84, 0.00 }
local COLOR_SILVER                            = { 0.82, 0.85, 0.90 }
local COLOR_COPPER                            = { 0.85, 0.55, 0.35 }
local COLOR_XP                                = { 0.70, 0.30, 1.00 }
local COLOR_REP                               = { 0.00, 0.75, 1.00 }
local COLOR_SKILL                             = { 1.00, 0.65, 0.15 } -- Warm Amber / Orange (matches WoW skill up)

local ICON_COIN_GOLD                          = "Interface\\Icons\\INV_Misc_Coin_01"
local ICON_COIN_SILVER                        = "Interface\\Icons\\INV_Misc_Coin_03"
local ICON_COIN_COPPER                        = "Interface\\Icons\\INV_Misc_Coin_05"

local SKILL_ICONS                             = {
    -- Secondary
    ["fishing"]           = "Interface\\Icons\\Trade_Fishing",
    ["cooking"]           = "Interface\\Icons\\INV_Misc_Food_15",
    ["first aid"]         = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
    ["archaeology"]       = "Interface\\Icons\\Trade_Archaeology",
    -- Primary Gathering
    ["herbalism"]         = "Interface\\Icons\\Spell_Nature_NatureTouchGrow",
    ["mining"]            = "Interface\\Icons\\Trade_Mining",
    ["skinning"]          = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
    -- Primary Crafting
    ["alchemy"]           = "Interface\\Icons\\Trade_Alchemy",
    ["blacksmithing"]     = "Interface\\Icons\\Trade_BlackSmithing",
    ["enchanting"]        = "Interface\\Icons\\Trade_Engraving",
    ["engineering"]       = "Interface\\Icons\\Trade_Engineering",
    ["leatherworking"]    = "Interface\\Icons\\Trade_LeatherWorking",
    ["tailoring"]         = "Interface\\Icons\\Trade_Tailoring",
    ["inscription"]       = "Interface\\Icons\\INV_Inscription_Tradeskill01",
    ["jewelcrafting"]     = "Interface\\Icons\\INV_Misc_Gem_01",
    -- Weapon & Combat Skills (Classic / Vanilla / Camelot)
    ["swords"]            = "Interface\\Icons\\INV_Sword_04",
    ["two-handed swords"] = "Interface\\Icons\\INV_Sword_05",
    ["axes"]              = "Interface\\Icons\\INV_Axe_02",
    ["two-handed axes"]   = "Interface\\Icons\\INV_Axe_03",
    ["maces"]             = "Interface\\Icons\\INV_Mace_02",
    ["two-handed maces"]  = "Interface\\Icons\\INV_Mace_03",
    ["polearms"]          = "Interface\\Icons\\INV_Spear_02",
    ["staves"]            = "Interface\\Icons\\INV_Staff_08",
    ["daggers"]           = "Interface\\Icons\\INV_Weapon_ShortBlade_05",
    ["bows"]              = "Interface\\Icons\\INV_Weapon_Bow_05",
    ["crossbows"]         = "Interface\\Icons\\INV_Weapon_Crossbow_01",
    ["guns"]              = "Interface\\Icons\\INV_Weapon_Rifle_01",
    ["thrown"]            = "Interface\\Icons\\INV_ThrowingKnife_04",
    ["wands"]             = "Interface\\Icons\\INV_Wand_01",
    ["fist weapons"]      = "Interface\\Icons\\INV_Gauntlets_04",
    ["unarmed"]           = "Interface\\Icons\\Ability_GolemThunderClap",
    ["defense"]           = "Interface\\Icons\\Ability_Defend",
    ["lockpicking"]       = "Interface\\Icons\\Spell_Nature_MoonKey",
    ["poisons"]           = "Interface\\Icons\\Trade_BrewPoison",
    ["riding"]            = "Interface\\Icons\\Spell_Nature_Swiftness",
}

local function GetFont(size)
    local f = (sfui.config and sfui.config.fontFile)
        or (sfui.config and sfui.config.fonts and sfui.config.fonts.regular)
        or (_G.STANDARD_TEXT_FONT and _G.STANDARD_TEXT_FONT ~= "" and _G.STANDARD_TEXT_FONT)
        or "Fonts\\FRIZQT__.TTF"
    return f, size or 48, ""
end

-- ─────────────────────────────────────────────────────────────────────────────
--  State & Pools
-- ─────────────────────────────────────────────────────────────────────────────
local container = nil
local pendingHeader = nil
local rowPool = {}
local activeRows = {}
local activeRowsByKey = {}

local pendingQueue = {}
local nodePool = {}

local waitingItemCache = {}
local skillCache = {}
local lastMoney = 0
local lastXP = 0

local function GetConfig()
    return (SfuiDB and SfuiDB.lootfeed) or (sfui.config and sfui.config.lootfeed) or {}
end

-- ─── Reusable Queue Node Allocator ───────────────────────────────────────────
local function AcquireNode(data)
    local node = table_remove(nodePool) or {}
    for k, v in pairs(data) do
        node[k] = v
    end
    return node
end

local function ReleaseNode(node)
    wipe(node)
    table_insert(nodePool, node)
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Root Container & Frame Factory
-- ─────────────────────────────────────────────────────────────────────────────
local function EnsureContainer()
    if container then return container end
    local cfg = GetConfig()
    container = CreateFrame("Frame", "sfui_lootfeed_container", UIParent)
    local pos = cfg.pos or { point = "TOPRIGHT", relativePoint = "TOPRIGHT", x = -320, y = -200 }
    container:SetPoint(pos.point or "TOPRIGHT", UIParent, pos.relativePoint or "TOPRIGHT", pos.x or -320,
        pos.y or -200)
    container:SetSize(cfg.width or 350, 200)
    container:SetClampedToScreen(true)
    container:SetMovable(true)

    -- Drag Support
    container:EnableMouse(false)
    container:RegisterForDrag("LeftButton")
    container:SetScript("OnDragStart", function(f)
        if not InCombatLockdown or not InCombatLockdown() then
            f:StartMoving()
        end
    end)
    container:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        local point, _, relPoint, x, y = f:GetPoint()
        local c = GetConfig()
        c.pos = c.pos or {}
        c.pos.point = point
        c.pos.relativePoint = relPoint
        c.pos.x = math_floor(x + 0.5)
        c.pos.y = math_floor(y + 0.5)
    end)

    -- Pending Items Header
    pendingHeader = CreateFrame("Frame", nil, container, "BackdropTemplate")
    pendingHeader:SetSize(cfg.width or 280, 18)
    local pText = pendingHeader:CreateFontString(nil, "OVERLAY")
    local pf, ps = GetFont(11)
    pText:SetFont(pf, ps, "")
    pText:SetPoint("CENTER", pendingHeader, "CENTER", 0, 0)
    pText:SetTextColor(0.85, 0.85, 0.90, 0.90)
    pendingHeader.text = pText
    if sfui.theme and sfui.theme.ApplyLootfeedPendingHeaderStyle then
        sfui.theme.ApplyLootfeedPendingHeaderStyle(pendingHeader)
    end
    pendingHeader:Hide()

    return container
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Row Frame Construction (Formatted like sfui quests.lua headers)
-- ─────────────────────────────────────────────────────────────────────────────
local function CreateRowFrame(parent)
    local cfg = GetConfig()
    local rowHeight = cfg.rowHeight or 34
    local iconSize = math_max(16, rowHeight - 6)
    parent = parent or EnsureContainer()
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetSize(cfg.width or 320, rowHeight)
    row:EnableMouse(true)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local mult = sfui.pixelScale or 1
    row:SetBackdrop({
        bgFile   = [[Interface\Buttons\WHITE8x8]],
        edgeFile = [[Interface\Buttons\WHITE8x8]],
        edgeSize = mult,
    })
    row:SetBackdropColor(0, 0, 0, 0.50)
    row:SetBackdropBorderColor(0, 0, 0, 0.50)

    -- Option A: Camelot Sculpted Bronze Card Background (UI-Character-Info-OutfitCard)
    local cardBg = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    cardBg:Hide()
    row.cardBg = cardBg

    -- 1. Left 3px Quality / Type Accent Bar (Modern flat mode)
    local accent = row:CreateTexture(nil, "ARTWORK")
    accent:SetWidth(3)
    accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    accent:SetColorTexture(1, 1, 1, 1)
    row.accent = accent

    -- 2. Sunken Icon Socket (Background, fallback/modern)
    local iconSlot = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    iconSlot:Hide()
    row.iconSlot = iconSlot

    -- 3. Icon Texture (Square cropped 0.08 - 0.92)
    local icon = row:CreateTexture(nil, "ARTWORK", nil, 1)
    icon:SetSize(iconSize, iconSize)
    icon:SetPoint("LEFT", row, "LEFT", 5, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = icon

    -- 4. Icon Quality Border / Bezel Overlay (Option A: UI-Character-Info-OutfitIcon-Frame)
    local iconBorder = row:CreateTexture(nil, "OVERLAY", nil, 1)
    iconBorder:Hide()
    row.iconBorder = iconBorder

    -- 5. Hover Overlay Texture (UI-Character-Info-OutfitCard-Hover)
    local hoverOverlay = row:CreateTexture(nil, "OVERLAY", nil, 2)
    hoverOverlay:SetAllPoints(row)
    hoverOverlay:Hide()
    row.hoverOverlay = hoverOverlay

    -- 6. Right Status Badge FontString (Quantity / Gold / Info)
    local badge = row:CreateFontString(nil, "OVERLAY")
    local bFont, bSize = GetFont(12)
    badge:SetFont(bFont, bSize, "")
    badge:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    badge:SetJustifyH("RIGHT")
    badge:SetWordWrap(false)
    row.badge = badge

    -- 7. Title / Item Name FontString
    local title = row:CreateFontString(nil, "OVERLAY")
    local tFont, tSize = GetFont(12)
    title:SetFont(tFont, tSize, "")
    title:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    title:SetPoint("RIGHT", badge, "LEFT", -4, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    row.title = title

    -- Hover Interaction: pause fade timer and display tooltip
    row:SetScript("OnEnter", function(self)
        self.isPaused = true

        if self.isCamelotRow then
            if self.lootfeedStyle == "architectural" then
                if self.isOther then
                    self:SetBackdropColor(0.26, 0.26, 0.30, 0.95)
                    if self.SetBackdropBorderColor then
                        self:SetBackdropBorderColor(0.65, 0.65, 0.70, 1.0)
                    end
                else
                    self:SetBackdropColor(0.14, 0.11, 0.08, 0.95)
                    if self.SetBackdropBorderColor then
                        self:SetBackdropBorderColor(0.85, 0.70, 0.35, 1.0)
                    end
                end
            else
                if self.hoverOverlay then
                    self.hoverOverlay:Show()
                end
            end
        else
            if self.isOther then
                self:SetBackdropColor(0.28, 0.28, 0.32, 0.85)
                if self.SetBackdropBorderColor then
                    self:SetBackdropBorderColor(0.60, 0.60, 0.68, 1.0)
                end
            else
                self:SetBackdropColor(0.08, 0.08, 0.08, 0.70)
            end
        end

        local anchor = (self:GetRight() and self:GetRight() > (UIParent:GetWidth() or 1000) / 2) and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
        GameTooltip:SetOwner(self, anchor)

        if self.itemLink then
            GameTooltip:SetHyperlink(self.itemLink)
            GameTooltip:Show()
        elseif self.currencyID and GameTooltip.SetCurrencyByID then
            GameTooltip:SetCurrencyByID(self.currencyID)
            GameTooltip:Show()
        elseif self.tooltipTitle then
            GameTooltip:ClearLines()
            GameTooltip:AddLine(self.tooltipTitle, 1, 1, 1)
            if self.tooltipDesc then
                GameTooltip:AddLine(self.tooltipDesc, 0.8, 0.8, 0.8, true)
            end
            GameTooltip:Show()
        end
    end)

    row:SetScript("OnLeave", function(self)
        self.isPaused = false

        if self.isCamelotRow then
            if self.lootfeedStyle == "architectural" then
                if self.isOther then
                    self:SetBackdropColor(0.20, 0.20, 0.23, 0.92)
                    if self.SetBackdropBorderColor then
                        self:SetBackdropBorderColor(0.45, 0.45, 0.48, 0.90)
                    end
                else
                    local pal = (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()) or sfui.config.appearance
                    self:SetBackdropColor(pal.backdropColor[1], pal.backdropColor[2], pal.backdropColor[3], 0.94)
                    if self.SetBackdropBorderColor then
                        self:SetBackdropBorderColor(0.28, 0.22, 0.14, 0.90)
                    end
                end
            else
                if self.hoverOverlay then
                    self.hoverOverlay:Hide()
                end
            end
        else
            if self.isOther then
                self:SetBackdropColor(0.22, 0.22, 0.26, 0.75)
                if self.SetBackdropBorderColor then
                    self:SetBackdropBorderColor(0.42, 0.42, 0.48, 0.85)
                end
            else
                self:SetBackdropColor(0, 0, 0, 0.50)
                if self.SetBackdropBorderColor then
                    self:SetBackdropBorderColor(0, 0, 0, 0.50)
                end
            end
        end
        if hide_tooltip then hide_tooltip() else GameTooltip:Hide() end
    end)

    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            sfui.lootfeed.DismissRow(self)
            return
        end

        if self.itemLink then
            if IsShiftKeyDown and IsShiftKeyDown() then
                if ChatEdit_InsertLink then
                    ChatEdit_InsertLink(self.itemLink)
                end
            elseif IsControlKeyDown and IsControlKeyDown() then
                if DressUpLink then
                    DressUpLink(self.itemLink)
                elseif HandleModifiedItemClick then
                    HandleModifiedItemClick(self.itemLink)
                end
            elseif HandleModifiedItemClick then
                HandleModifiedItemClick(self.itemLink)
            end
        end
    end)

    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", function(self)
        if IsAltKeyDown and IsAltKeyDown() then
            if not InCombatLockdown or not InCombatLockdown() then
                container:StartMoving()
            end
        end
    end)
    row:SetScript("OnDragStop", function(self)
        container:StopMovingOrSizing()
        local point, _, relPoint, x, y = container:GetPoint()
        local c = GetConfig()
        c.pos = c.pos or {}
        c.pos.point = point
        c.pos.relativePoint = relPoint
        c.pos.x = math_floor(x + 0.5)
        c.pos.y = math_floor(y + 0.5)
    end)

    return row
end

local function AcquireRowFrame()
    EnsureContainer()
    local row = table_remove(rowPool)
    if not row then
        row = CreateRowFrame(container)
    end
    row:SetParent(container)
    row:ClearAllPoints()
    row:SetAlpha(1)
    if not row.isCamelotRow then
        row:SetBackdropColor(0, 0, 0, 0.50)
        if row.SetBackdropBorderColor then
            row:SetBackdropBorderColor(0, 0, 0, 0.50)
        end
    end
    row.isOther = false
    row.looter = nil
    row.isPaused = false
    row.itemLink = nil
    row.currencyID = nil
    row.tooltipTitle = nil
    row.tooltipDesc = nil
    if row.hoverOverlay then row.hoverOverlay:Hide() end
    row:Show()
    return row
end

local function ReleaseRowFrame(row)
    row:Hide()
    row:ClearAllPoints()
    if row.key then
        activeRowsByKey[row.key] = nil
        row.key = nil
    end
    row.itemLink = nil
    row.currencyID = nil
    row.tooltipTitle = nil
    row.tooltipDesc = nil
    row.isOther = false
    row.looter = nil
    if row.cardBg then
        row.cardBg:SetDesaturated(false)
        row.cardBg:SetVertexColor(1, 1, 1, 1)
        row.cardBg:Hide()
    end
    if row.hoverOverlay then row.hoverOverlay:Hide() end
    if row.iconSlot then row.iconSlot:Hide() end
    if row.iconBorder then row.iconBorder:Hide() end
    if row.cornerTL then
        row.cornerTL:SetVertexColor(1, 1, 1, 1)
        row.cornerTR:SetVertexColor(1, 1, 1, 1)
        row.cornerBL:SetVertexColor(1, 1, 1, 1)
        row.cornerBR:SetVertexColor(1, 1, 1, 1)
        row.cornerTL:Hide()
        row.cornerTR:Hide()
        row.cornerBL:Hide()
        row.cornerBR:Hide()
    end
    table_insert(rowPool, row)
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Layout & Stacking Engine
-- ─────────────────────────────────────────────────────────────────────────────
local function UpdateLayout()
    if not container then return end

    local cfg = GetConfig()
    local growDown = (cfg.growDirection ~= "UP")
    local rowHeight = cfg.rowHeight or 34
    local spacing = 3
    local rowW = cfg.width or 320
    local iconSize = math_max(16, rowHeight - 6)

    container:SetSize(rowW, (rowHeight + spacing) * (cfg.maxRows or 10) + 20)

    -- Update Pending Header Position
    if pendingHeader then
        pendingHeader:ClearAllPoints()
        if growDown then
            pendingHeader:SetPoint("BOTTOMLEFT", container, "TOPLEFT", 0, 3)
            pendingHeader:SetPoint("BOTTOMRIGHT", container, "TOPRIGHT", 0, 3)
        else
            pendingHeader:SetPoint("TOPLEFT", container, "BOTTOMLEFT", 0, -3)
            pendingHeader:SetPoint("TOPRIGHT", container, "BOTTOMRIGHT", 0, -3)
        end

        local qCount = #pendingQueue
        if qCount > 0 then
            pendingHeader.text:SetText(string_format("%s %d pending item%s", SPINNER_DOT, qCount,
                qCount > 1 and "s" or ""))
            pendingHeader:Show()
        else
            pendingHeader:Hide()
        end
    end

    -- Re-anchor active rows sequentially
    local prevFrame = nil
    for i, row in ipairs(activeRows) do
        row:SetSize(rowW, rowHeight)
        row.icon:SetSize(iconSize, iconSize)
        if row.iconSlot and row.iconSlot:IsShown() then
            row.iconSlot:SetSize(iconSize + 4, iconSize + 4)
        end
        if row.iconBorder and row.iconBorder:IsShown() then
            row.iconBorder:SetSize(iconSize + 8, iconSize + 8)
        end
        row:ClearAllPoints()
        if i == 1 then
            if growDown then
                row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            else
                row:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
            end
        else
            if growDown then
                row:SetPoint("TOPLEFT", prevFrame, "BOTTOMLEFT", 0, -spacing)
            else
                row:SetPoint("BOTTOMLEFT", prevFrame, "TOPLEFT", 0, spacing)
            end
        end
        prevFrame = row
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Master Ticker (Zero CPU When Idle)
-- ─────────────────────────────────────────────────────────────────────────────
local function MasterOnUpdate(self, elapsed)
    local cfg = GetConfig()
    local displayDuration = cfg.displayDuration or 5.0
    local fadeDuration = cfg.fadeDuration or 0.35

    local hasExpired = false

    for i = #activeRows, 1, -1 do
        local row = activeRows[i]
        if not row.isPaused then
            if row.state == "DISPLAY" then
                row.timeRemaining = row.timeRemaining - elapsed
                if row.timeRemaining <= 0 then
                    row.state = "FADING"
                end
            elseif row.state == "FADING" then
                row.fadeRemaining = row.fadeRemaining - elapsed
                if row.fadeRemaining <= 0 then
                    -- Row expired
                    table_remove(activeRows, i)
                    ReleaseRowFrame(row)
                    hasExpired = true
                else
                    row:SetAlpha(row.fadeRemaining / fadeDuration)
                end
            end
        end
    end

    -- If a row expired and items are waiting in the pending queue, pop the next item immediately
    if hasExpired and #pendingQueue > 0 then
        while #activeRows < (cfg.maxRows or 8) and #pendingQueue > 0 do
            local nextItem = table_remove(pendingQueue, 1)
            if nextItem then
                sfui.lootfeed.DisplayLoot(nextItem, true)
                ReleaseNode(nextItem)
            end
        end
        UpdateLayout()
    elseif hasExpired then
        UpdateLayout()
    end

    -- Unhook OnUpdate completely if there are no active rows and no pending items (Zero CPU!)
    if #activeRows == 0 and #pendingQueue == 0 then
        if container then
            container:SetScript("OnUpdate", nil)
        end
        if pendingHeader then pendingHeader:Hide() end
    end
end

local function EnsureTickerRunning()
    if container and not container:GetScript("OnUpdate") then
        container:SetScript("OnUpdate", MasterOnUpdate)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Loot Feed Dispatch & Deduplication
-- ─────────────────────────────────────────────────────────────────────────────
function sfui.lootfeed.DismissRow(row)
    if not row then return end
    for idx, r in ipairs(activeRows) do
        if r == row then
            table_remove(activeRows, idx)
            ReleaseRowFrame(row)
            break
        end
    end

    local cfg = GetConfig()
    while #activeRows < (cfg.maxRows or 8) and #pendingQueue > 0 do
        local nextItem = table_remove(pendingQueue, 1)
        if nextItem then
            sfui.lootfeed.DisplayLoot(nextItem, true)
            ReleaseNode(nextItem)
        end
    end
    UpdateLayout()
end

--- Displays or queues a loot entry.
--- @param data table Contains { key, title, icon, color, quality, quantity, badgeText, itemLink, looter, sellPrice, tooltipTitle, tooltipDesc }
--- @param fromQueue boolean True if called while draining the FIFO queue
function sfui.lootfeed.DisplayLoot(data, fromQueue)
    if not data or not data.key or IsSecret(data.key) then return end
    local cfg = GetConfig()
    if not cfg.enabled then return end

    if data.quantity and IsSecret(data.quantity) then data.quantity = 1 end
    if data.title and IsSecret(data.title) then data.title = "[Protected]" end

    local key = data.key

    -- 1. Deduplication with Active Rows: stack quantity & reset timer
    local existingRow = activeRowsByKey[key]
    if existingRow then
        existingRow.quantity = (existingRow.quantity or 1) + (data.quantity or 1)
        if data.title then
            existingRow.title:SetText(data.title)
        end
        if data.badgeTextFn then
            existingRow.badge:SetText(data.badgeTextFn(existingRow.quantity))
        elseif data.badgeText then
            existingRow.badge:SetText(data.badgeText)
        elseif existingRow.quantity > 1 then
            existingRow.badge:SetText("x" .. tostring(existingRow.quantity))
        end

        if data.tooltipTitle then existingRow.tooltipTitle = data.tooltipTitle end
        if data.tooltipDesc then existingRow.tooltipDesc = data.tooltipDesc end

        existingRow.timeRemaining = cfg.displayDuration or 5.0
        existingRow.fadeRemaining = cfg.fadeDuration or 0.35
        existingRow.state = "DISPLAY"
        existingRow:SetAlpha(1)

        existingRow.isOther = (data.isOther == true) or (data.looter ~= nil and data.looter ~= "")
        if sfui.theme and sfui.theme.ApplyLootfeedRowStyle then
            sfui.theme.ApplyLootfeedRowStyle(existingRow, data.color, data.quality, existingRow.isOther)
        elseif existingRow.accent then
            local c = data.color or { 1, 1, 1 }
            existingRow.accent:SetColorTexture(c[1], c[2], c[3], 1)
        end
        return
    end

    -- 2. Deduplication with Queued Items (not yet displayed)
    if not fromQueue then
        for _, qItem in ipairs(pendingQueue) do
            if qItem.key == key then
                qItem.quantity = (qItem.quantity or 1) + (data.quantity or 1)
                return
            end
        end

        -- Check capacity: if full, enqueue into FIFO pending queue
        if #activeRows >= (cfg.maxRows or 10) then
            local qNode = AcquireNode(data)
            table_insert(pendingQueue, qNode)
            UpdateLayout()
            EnsureTickerRunning()
            return
        end
    end

    -- 3. Acquire a Pooled Row Frame
    local row = AcquireRowFrame()
    row.key = key
    row.quantity = data.quantity or 1
    row.itemLink = data.itemLink
    row.currencyID = data.currencyID
    row.tooltipTitle = data.tooltipTitle
    row.tooltipDesc = data.tooltipDesc
    row.isOther = (data.isOther == true) or (data.looter ~= nil and data.looter ~= "")
    row.looter = data.looter

    -- Colors & Accent
    local col = data.color or { 1, 1, 1 }

    -- Icon
    if data.icon then
        row.icon:SetTexture(data.icon)
        row.icon:Show()
    else
        row.icon:Hide()
    end

    -- Text
    row.title:SetText(data.title or "")
    if col then
        row.title:SetTextColor(col[1] or 1, col[2] or 1, col[3] or 1, 1)
    else
        row.title:SetTextColor(1, 1, 1, 1)
    end

    -- Right Badge
    if data.badgeText then
        row.badge:SetText(data.badgeText)
    elseif data.badgeTextFn then
        row.badge:SetText(data.badgeTextFn(row.quantity))
    elseif row.quantity > 1 then
        row.badge:SetText("x" .. tostring(row.quantity))
    else
        row.badge:SetText("")
    end

    -- Theme Styling (Option D: Sunken Bronze Slot & Loot Toast Glow in Camelot)
    if sfui.theme and sfui.theme.ApplyLootfeedRowStyle then
        sfui.theme.ApplyLootfeedRowStyle(row, col, data.quality, row.isOther)
    else
        row.accent:SetColorTexture(col[1] or 1, col[2] or 1, col[3] or 1, 1)
        if row.isOther then
            row:SetBackdropColor(0.22, 0.22, 0.26, 0.75)
            if row.SetBackdropBorderColor then
                row:SetBackdropBorderColor(0.42, 0.42, 0.48, 0.85)
            end
        else
            row:SetBackdropColor(0, 0, 0, 0.50)
            if row.SetBackdropBorderColor then
                row:SetBackdropBorderColor(0, 0, 0, 0.50)
            end
        end
    end

    -- Dungeon Journal Wishlist Highlight
    if data.isWishlist then
        if row.SetBackdropBorderColor then
            row:SetBackdropBorderColor(0.8, 0.27, 1.0, 1.0)
        end
        if data.badgeText and data.badgeText ~= "" then
            row.badge:SetText(data.badgeText .. " |TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:12:12:0:0|t")
        else
            row.badge:SetText("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:12:12:0:0|t |cffcc44ffWISHLIST|r")
        end
        if _G.PlaySound and _G.SOUNDKIT and _G.SOUNDKIT.UI_EPICLOOT_TOAST then
            pcall(_G.PlaySound, _G.SOUNDKIT.UI_EPICLOOT_TOAST)
        end
    end

    row.timeRemaining = cfg.displayDuration or 5.0
    row.fadeRemaining = cfg.fadeDuration or 0.35
    row.state = "DISPLAY"

    activeRowsByKey[key] = row
    table_insert(activeRows, row)

    UpdateLayout()
    EnsureTickerRunning()
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Event Parsers (Items, Currency, Money, XP, Reputation)
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Money Formatter Helpers
local function FormatCopperString(copper)
    if not copper or IsSecret(copper) then return "0" .. COIN_COPPER end
    local g = math_floor(copper / 10000)
    local s = math_floor((copper % 10000) / 100)
    local c = copper % 100
    local out = ""
    if g > 0 then
        out = out .. tostring(g) .. COIN_GOLD .. " "
    end
    if s > 0 or g > 0 then
        out = out .. tostring(s) .. COIN_SILVER .. " "
    end
    out = out .. tostring(c) .. COIN_COPPER
    return out
end

local function FormatAbbreviatedGold(copper)
    if not copper or IsSecret(copper) then return "0" .. COIN_COPPER end
    local g = math_floor(copper / 10000)
    if g >= 1000000 then
        return string_format("%.2fM", g / 1000000) .. COIN_GOLD
    elseif g >= 1000 then
        return string_format("%.1fK", g / 1000) .. COIN_GOLD
    elseif g > 0 then
        return tostring(g) .. COIN_GOLD
    end
    local s = math_floor((copper % 10000) / 100)
    if s > 0 then
        return tostring(s) .. COIN_SILVER
    end
    return tostring(copper % 100) .. COIN_COPPER
end

-- 2. Item Loot
local function OnItemLoot(msg, looterName)
    local cfg = GetConfig()
    if not msg or IsSecret(msg) then return end
    if looterName and IsSecret(looterName) then looterName = nil end

    local itemLink = string_match(msg, "(|c.-|Hitem:.-|h%[.-%]|h|r)")
    if not itemLink or IsSecret(itemLink) then return end

    local isPartyLoot = (looterName and looterName ~= "")

    -- Drop party loot if party tracking is disabled
    if isPartyLoot and cfg.trackPartyLoot == false then
        return
    end

    -- Quantity
    local qty = tonumber(string_match(msg, "r ?x(%d+)")) or 1

    -- Parse Item Data
    local itemName, _, itemQuality, itemLevel, _, _, _, _, _, itemTexture, sellPrice = GetItemInfo(itemLink)
    local itemID = tonumber(string_match(itemLink, "item:(%d+)"))

    -- Handle asynchronous uncached items
    if not itemName then
        if itemID and RequestLoadItemDataByID then
            waitingItemCache[itemID] = { link = itemLink, qty = qty, looter = looterName }
            RequestLoadItemDataByID(itemID)
        end
        return
    end

    -- Quality Filter (0 = Poor, 1 = Common, etc.)
    local minQual
    if isPartyLoot then
        minQual = cfg.partyMinItemQuality
        if minQual == nil then minQual = cfg.minPartyItemQuality end
        if minQual == nil then minQual = 2 end
    else
        minQual = cfg.minItemQuality or 0
    end

    if itemQuality and itemQuality < minQual then
        return
    end

    local col = (itemQuality and QUALITY_COLORS[itemQuality]) or { 1, 1, 1 }

    -- Badge: quantity and/or vendor sell price for junk/trade items
    local badge = nil
    if qty > 1 then
        badge = "x" .. tostring(qty)
    end
    if cfg.showSellPrice and sellPrice and sellPrice > 0 and (not itemLevel or itemLevel <= 1) then
        local sp = FormatCopperString(sellPrice * qty)
        badge = badge and (badge .. " " .. VENDOR_ICON .. sp) or (VENDOR_ICON .. sp)
    end

    local key = "ITEM_" .. (itemID or itemLink) .. (looterName and ("_" .. looterName) or "")
    local displayTitle = itemLink
    if looterName and looterName ~= "" then
        local cleanLooter = string_match(looterName, "^([^-]+)") or looterName
        local _, classFile = UnitClass(looterName)
        if not classFile and cleanLooter ~= looterName then
            _, classFile = UnitClass(cleanLooter)
        end
        local cColor = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
        local cTag = cColor and string_format("|c%s%s|r", cColor.colorStr or "ffffffff", cleanLooter) or cleanLooter
        displayTitle = string_format("%s (|cffa0a0a0%s|r)", itemLink, cTag)
    end

    local isWishlist = false
    if itemID and sfui.dungeonjournal and sfui.dungeonjournal.IsWishlisted then
        isWishlist = sfui.dungeonjournal.IsWishlisted(itemID)
    end

    sfui.lootfeed.DisplayLoot({
        key = key,
        title = displayTitle,
        icon = itemTexture,
        color = col,
        quality = itemQuality,
        quantity = qty,
        badgeText = badge,
        itemLink = itemLink,
        isWishlist = isWishlist,
        isOther = isPartyLoot,
        looter = looterName,
    })
end

-- 3. Currency Updates
local function OnCurrencyUpdate(currencyType, quantityChange)
    local cfg = GetConfig()
    if not cfg.trackCurrency or not currencyType or not quantityChange or quantityChange <= 0 then
        return
    end
    if IsSecret(currencyType) or IsSecret(quantityChange) then return end

    local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(currencyType)
    if not info or not info.name or IsSecret(info.name) then return end

    local col = (info.quality and QUALITY_COLORS[info.quality]) or COLOR_REP
    local total = (info.quantity and not IsSecret(info.quantity)) and info.quantity or 0

    local badge = string_format("x%d (%d)", quantityChange, total)
    local key = "CURRENCY_" .. tostring(currencyType)

    sfui.lootfeed.DisplayLoot({
        key = key,
        title = info.name,
        icon = not IsSecret(info.iconFileID) and info.iconFileID or nil,
        color = col,
        quality = not IsSecret(info.quality) and info.quality or nil,
        quantity = quantityChange,
        badgeText = badge,
        currencyID = currencyType,
        tooltipTitle = info.name,
        tooltipDesc = not IsSecret(info.description) and info.description or nil,
    })
end

-- 4. Money Update
local function OnMoneyUpdate()
    local cfg = GetConfig()
    if not cfg.trackMoney then return end

    local cur = GetMoney()
    if not cur or IsSecret(cur) then return end
    local delta = cur - lastMoney
    lastMoney = cur

    if delta <= 0 then return end
    if delta < (cfg.minMoneyThreshold or 1) then return end

    local badge = FormatAbbreviatedGold(cur)
    local titleStr = FormatCopperString(delta)

    local icon, col, ttTitle
    if delta >= 10000 then
        icon = ICON_COIN_GOLD
        col = COLOR_GOLD
        ttTitle = "Gold Earned"
    elseif delta >= 100 then
        icon = ICON_COIN_SILVER
        col = COLOR_SILVER
        ttTitle = "Silver Earned"
    else
        icon = ICON_COIN_COPPER
        col = COLOR_COPPER
        ttTitle = "Copper Earned"
    end

    sfui.lootfeed.DisplayLoot({
        key = "MONEY",
        title = titleStr,
        icon = icon,
        color = col,
        quantity = delta,
        badgeText = badge,
        tooltipTitle = ttTitle,
        tooltipDesc = "Total Wealth: " .. FormatCopperString(cur),
    })
end

-- 5. XP Update
local function OnXPUpdate()
    local cfg = GetConfig()
    if not cfg.trackXP then return end

    local curXP = UnitXP("player") or 0
    local maxXP = UnitXPMax("player") or 1
    if IsSecret(curXP) or IsSecret(maxXP) then return end
    local delta = curXP - lastXP
    lastXP = curXP

    if delta <= 0 then return end

    local pct = (maxXP > 0) and math_floor((curXP / maxXP) * 100 + 0.5) or 0
    local badge = string_format("<%d%%>", pct)
    local titleStr = string_format("%d XP", delta)

    sfui.lootfeed.DisplayLoot({
        key = "XP",
        title = titleStr,
        icon = "Interface\\Icons\\Spell_Holy_SurgeOfLight",
        color = COLOR_XP,
        quantity = delta,
        badgeText = badge,
        tooltipTitle = "Experience Gained",
        tooltipDesc = string_format("Current: %d / %d (%d%%)", curXP, maxXP, pct),
    })
end

-- 6. Reputation Update
local function OnFactionCombatMsg(msg)
    local cfg = GetConfig()
    if not cfg.trackReputation or not msg or IsSecret(msg) then return end

    -- Extract faction name and reputation increase
    local faction, amount = string_match(msg, "Reputation with (.+) increased by (%d+)")
    if not faction then
        faction, amount = string_match(msg, "(.+) reputation increased by (%d+)")
    end

    if faction and amount and not IsSecret(faction) and not IsSecret(amount) then
        local delta = tonumber(amount) or 0
        local key = "REP_" .. faction
        local titleStr = string_format("+%d %s", delta, faction)

        sfui.lootfeed.DisplayLoot({
            key = key,
            title = titleStr,
            icon = "Interface\\Icons\\Achievement_Reputation_01",
            color = COLOR_REP,
            quantity = delta,
            badgeText = "Rep",
            tooltipTitle = faction,
            tooltipDesc = string_format("Reputation increased by %d.", delta),
        })
    end
end

-- 7. Skill Updates & Changes
local function ResolveSkillData(skillName)
    local icon = nil
    local curRank, maxRank = nil, nil
    if not skillName or IsSecret(skillName) then
        return "Interface\\Icons\\Spell_Holy_BlessingOfStrength", nil, nil
    end

    local cleanName = skillName:lower():gsub("^%s*(.-)%s*$", "%1")

    -- 1. Try C_SkillInfo (Camelot / Modern API)
    if C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo then
        local num = C_SkillInfo.GetNumSkillLines() or 0
        if not IsSecret(num) then
            for i = 1, num do
                local info = C_SkillInfo.GetSkillLineInfo(i)
                if info and not info.isHeader and info.name and not IsSecret(info.name) and info.name:lower() == cleanName then
                    curRank = not IsSecret(info.rank) and info.rank or nil
                    maxRank = not IsSecret(info.maxRank) and info.maxRank or nil
                    break
                end
            end
        end
    -- 2. Try classic GetSkillLineInfo (Classic Era)
    elseif _G.GetNumSkillLines and _G.GetSkillLineInfo then
        local num = _G.GetNumSkillLines() or 0
        if not IsSecret(num) then
            for i = 1, num do
                local name, isHeader, _, rank, _, _, mRank = _G.GetSkillLineInfo(i)
                if not isHeader and name and not IsSecret(name) and name:lower() == cleanName then
                    curRank = not IsSecret(rank) and rank or nil
                    maxRank = not IsSecret(mRank) and mRank or nil
                    break
                end
            end
        end
    end

    -- 3. Try Retail GetProfessions / GetProfessionInfo if not found
    if not maxRank and _G.GetProfessions and _G.GetProfessionInfo then
        local profs = { _G.GetProfessions() }
        for _, pIdx in ipairs(profs) do
            if pIdx and not IsSecret(pIdx) then
                local pName, pIcon, pRank, pMaxRank = _G.GetProfessionInfo(pIdx)
                if pName and not IsSecret(pName) and pName:lower() == cleanName then
                    curRank = not IsSecret(pRank) and pRank or nil
                    maxRank = not IsSecret(pMaxRank) and pMaxRank or nil
                    icon = not IsSecret(pIcon) and pIcon or nil
                    break
                end
            end
        end
    end

    -- 4. Try spell texture lookup if icon not found yet
    if not icon then
        if C_Spell and C_Spell.GetSpellTexture then
            icon = C_Spell.GetSpellTexture(skillName)
        elseif _G.GetSpellTexture then
            icon = _G.GetSpellTexture(skillName)
        end
        if IsSecret(icon) then icon = nil end
    end

    -- 5. Match against curated SKILL_ICONS dictionary
    if not icon then
        icon = SKILL_ICONS[cleanName]
        if not icon then
            for k, tex in pairs(SKILL_ICONS) do
                if cleanName:find(k, 1, true) then
                    icon = tex
                    break
                end
            end
        end
    end

    -- 6. Fallback icon
    if not icon then
        icon = "Interface\\Icons\\Spell_Holy_BlessingOfStrength"
    end

    return icon, curRank, maxRank
end

local function OnSkillMsg(msg)
    local cfg = GetConfig()
    if not cfg.trackSkills or not msg or IsSecret(msg) then return end

    local skillName, rankStr = nil, nil

    -- 1. Try localized string ERR_SKILL_UP_SI / SKILL_RANK_UP
    local globalFmt = _G.ERR_SKILL_UP_SI or _G.SKILL_RANK_UP
    if globalFmt and not IsSecret(globalFmt) then
        local pat = globalFmt:gsub("([%(%)%[%]%-%+%*%?%^%$%.])", "%%%1")
                             :gsub("%%%d?$?s", "(.+)")
                             :gsub("%%%d?$?d", "(%%d+)")
        skillName, rankStr = string_match(msg, pat)
    end

    -- 2. Common English and localized fallbacks
    if not skillName then
        skillName, rankStr = string_match(msg, "Your skill in (.+) has increased to (%d+)")
    end
    if not skillName then
        skillName, rankStr = string_match(msg, "Your skill in (.+) has decreased to (%d+)")
    end
    if not skillName then
        skillName, rankStr = string_match(msg, "(.+) has increased to (%d+)")
    end
    if not skillName then
        skillName, rankStr = string_match(msg, "(.+) skill increased to (%d+)")
    end
    if not skillName then
        skillName, rankStr = string_match(msg, "(.+) increased to (%d+)")
    end

    -- 3. Check for skill learned (rank 1)
    local isLearned = false
    if not skillName then
        local gainedFmt = _G.ERR_SKILL_GAINED_S
        if gainedFmt and not IsSecret(gainedFmt) then
            local patG = gainedFmt:gsub("([%(%)%[%]%-%+%*%?%^%$%.])", "%%%1")
                                 :gsub("%%%d?$?s", "(.+)")
            skillName = string_match(msg, patG)
        end
        if not skillName then
            skillName = string_match(msg, "You have gained the (.+) skill")
        end
        if skillName then
            isLearned = true
            rankStr = "1"
        end
    end

    if not skillName or IsSecret(skillName) then return end

    -- Clean up trailing punctuation and whitespace
    skillName = string_gsub(skillName, "%.$", "")
    skillName = string_gsub(skillName, "^%s*(.-)%s*$", "%1")
    local newRank = (rankStr and not IsSecret(rankStr) and tonumber(rankStr)) or 1

    local oldData = skillCache[skillName]
    local oldRank = oldData and oldData.rank or (newRank - 1)
    local delta = math_max(1, newRank - oldRank)

    local icon, curRank, maxRank = ResolveSkillData(skillName)
    if curRank and curRank > 0 then
        newRank = curRank
    end

    local now = GetTime()
    skillCache[skillName] = {
        rank = newRank,
        maxRank = maxRank,
        lastNotified = now,
    }

    local key = "SKILL_" .. skillName
    local titleStr
    local badgeStr
    if isLearned then
        titleStr = skillName
        badgeStr = "Learned"
    else
        titleStr = string_format("+%d %s", delta, skillName)
        badgeStr = (maxRank and maxRank > 0) and string_format("%d/%d", newRank, maxRank) or tostring(newRank)
    end

    local descStr
    if isLearned then
        descStr = string_format("Learned %s.", skillName)
    elseif maxRank and maxRank > 0 then
        descStr = string_format("Skill level increased to %d of %d (+%d).", newRank, maxRank, delta)
    else
        descStr = string_format("Skill level increased to %d (+%d).", newRank, delta)
    end

    sfui.lootfeed.DisplayLoot({
        key = key,
        title = titleStr,
        icon = icon,
        color = COLOR_SKILL,
        quantity = delta,
        badgeText = badgeStr,
        tooltipTitle = isLearned and skillName or string_format("%s: %d", skillName, newRank),
        tooltipDesc = descStr,
    })
end

local function OnSkillLinesChanged()
    local cfg = GetConfig()
    if not cfg.trackSkills then return end

    local now = GetTime()

    local function checkSkill(name, rank, maxRank)
        if not name or name == "" or not rank or rank <= 0 or IsSecret(name) or IsSecret(rank) or IsSecret(maxRank) then return end
        local cached = skillCache[name]
        if cached then
            local oldRank = cached.rank or 0
            if rank > oldRank then
                local delta = rank - oldRank
                -- Only notify if CHAT_MSG_SKILL didn't already fire within the last 1.2s
                if not cached.lastNotified or (now - cached.lastNotified) > 1.2 then
                    cached.lastNotified = now
                    cached.rank = rank
                    cached.maxRank = maxRank

                    local icon = ResolveSkillData(name)
                    local key = "SKILL_" .. name
                    local titleStr = string_format("+%d %s", delta, name)
                    local badgeStr = (maxRank and maxRank > 0) and string_format("%d/%d", rank, maxRank) or tostring(rank)

                    sfui.lootfeed.DisplayLoot({
                        key = key,
                        title = titleStr,
                        icon = icon,
                        color = COLOR_SKILL,
                        quantity = delta,
                        badgeText = badgeStr,
                        tooltipTitle = string_format("%s: %d", name, rank),
                        tooltipDesc = (maxRank and maxRank > 0)
                            and string_format("Skill level increased to %d of %d (+%d).", rank, maxRank, delta)
                            or string_format("Skill level increased to %d (+%d).", rank, delta),
                    })
                else
                    cached.rank = rank
                    cached.maxRank = maxRank
                end
            else
                cached.rank = rank
                cached.maxRank = maxRank
            end
        else
            -- First discovery of this skill (startup scan): cache silently
            skillCache[name] = { rank = rank, maxRank = maxRank, lastNotified = now }
        end
    end

    if C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo then
        local num = C_SkillInfo.GetNumSkillLines() or 0
        if not IsSecret(num) then
            for i = 1, num do
                local info = C_SkillInfo.GetSkillLineInfo(i)
                if info and not info.isHeader and info.name and not IsSecret(info.name) then
                    checkSkill(info.name, info.rank, info.maxRank)
                end
            end
        end
    elseif _G.GetNumSkillLines and _G.GetSkillLineInfo then
        local num = _G.GetNumSkillLines() or 0
        if not IsSecret(num) then
            for i = 1, num do
                local name, isHeader, _, rank, _, _, mRank = _G.GetSkillLineInfo(i)
                if not isHeader and name and not IsSecret(name) then
                    checkSkill(name, rank, mRank)
                end
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Module Lifecycle & Event Registration
-- ─────────────────────────────────────────────────────────────────────────────
local M = sfui.RegisterModule("lootfeed", {
    OnInit = function(self)
        SfuiDB.lootfeed = SfuiDB.lootfeed or {}
        local db = SfuiDB.lootfeed
        local cfg = sfui.config.lootfeed or {}

        -- Auto-migrate old smaller defaults to new standard
        if db.width == 280 or db.width == 340 or db.width == 350 then db.width = cfg.width or 320 end
        if db.rowHeight == 22 or db.rowHeight == 26 or db.rowHeight == 40 or db.rowHeight == 48 then db.rowHeight = cfg.rowHeight or 34 end
        if db.displayDuration == 5.0 then db.displayDuration = cfg.displayDuration or 8.0 end
        if db.maxRows == 8 then db.maxRows = cfg.maxRows or 10 end
        if db.fadeDuration == 0.35 then db.fadeDuration = cfg.fadeDuration or 0.5 end
        if db.minItemQuality == nil or db.minItemQuality == 1 then db.minItemQuality = cfg.minItemQuality or 0 end

        for k, v in pairs(cfg) do
            if db[k] == nil then
                if type(v) == "table" then
                    db[k] = {}
                    for subK, subV in pairs(v) do db[k][subK] = subV end
                else
                    db[k] = v
                end
            end
        end
    end,

    OnEnable = function(self)
        local cfg = GetConfig()
        if not cfg.enabled then return end

        lastMoney = GetMoney() or 0
        lastXP = UnitXP("player") or 0
        OnSkillLinesChanged()

        -- 1. Create Root Container Frame
        EnsureContainer()

        -- 2. Register Event Listeners via central dispatcher
        local function on_chat_msg_loot(event, msg, looter, _, _, looter2, _, _, _, _, _, _, guid)
            if not msg or IsSecret(msg) or msg:find("HlootHistory:") then return end

            local myName = UnitName("player")
            local myGUID = UnitGUID("player")

            -- In WoW CHAT_MSG_LOOT, self-loot events have empty sender/guid or match player name/guid
            local shortLooter = (looter and not IsSecret(looter)) and string_match(looter, "^([^-]+)") or looter
            local isMe = false
            if not looter or looter == "" or looter == myName or shortLooter == myName then
                isMe = true
            elseif guid and myGUID and not IsSecret(guid) and guid == myGUID then
                isMe = true
            end

            local targetLooter = nil
            if not isMe then
                local currentCfg = GetConfig()
                if currentCfg.trackPartyLoot == false then return end
                targetLooter = (looter and not IsSecret(looter) and looter ~= "" and looter)
                    or (looter2 and not IsSecret(looter2) and looter2 ~= "" and looter2)
                if not targetLooter or targetLooter == "" then
                    local parsedLooter = string_match(msg, "^([^%s]+)%s+receives")
                    if parsedLooter and parsedLooter ~= myName and parsedLooter ~= "You" then
                        targetLooter = parsedLooter
                    else
                        targetLooter = "Party"
                    end
                end
            end

            OnItemLoot(msg, targetLooter)
        end

        local function on_get_item_info_received(event, itemID, success)
            if success and itemID and not IsSecret(itemID) and waitingItemCache[itemID] then
                local cached = waitingItemCache[itemID]
                waitingItemCache[itemID] = nil
                OnItemLoot(cached.link, cached.looter)
            end
        end

        local function on_player_money()
            OnMoneyUpdate()
        end

        local function on_player_xp_update()
            OnXPUpdate()
        end

        local function on_currency_display_update(event, cType, _, delta)
            if delta and not IsSecret(delta) and delta > 0 and not IsSecret(cType) then
                OnCurrencyUpdate(cType, delta)
            end
        end

        local function on_chat_msg_combat_faction_change(event, msg)
            if msg and not IsSecret(msg) then
                OnFactionCombatMsg(msg)
            end
        end

        local function on_chat_msg_skill(event, msg)
            if msg and not IsSecret(msg) then
                OnSkillMsg(msg)
            end
        end

        local function on_skill_lines_changed()
            OnSkillLinesChanged()
        end

        local function on_player_entering_world()
            local m = GetMoney()
            if m and not IsSecret(m) then lastMoney = m else lastMoney = 0 end
            local xp = UnitXP("player")
            if xp and not IsSecret(xp) then lastXP = xp else lastXP = 0 end
            OnSkillLinesChanged()
        end

        self.eventCallbacks = {
            ["CHAT_MSG_LOOT"] = on_chat_msg_loot,
            ["GET_ITEM_INFO_RECEIVED"] = on_get_item_info_received,
            ["PLAYER_MONEY"] = on_player_money,
            ["PLAYER_XP_UPDATE"] = on_player_xp_update,
            ["CURRENCY_DISPLAY_UPDATE"] = on_currency_display_update,
            ["CHAT_MSG_COMBAT_FACTION_CHANGE"] = on_chat_msg_combat_faction_change,
            ["CHAT_MSG_SKILL"] = on_chat_msg_skill,
            ["SKILL_LINES_CHANGED"] = on_skill_lines_changed,
            ["PLAYER_ENTERING_WORLD"] = on_player_entering_world,
        }

        for ev, cb in pairs(self.eventCallbacks) do
            sfui.events.RegisterEvent(ev, cb)
        end
    end,

    OnDisable = function(self)
        if self.eventCallbacks then
            for ev, cb in pairs(self.eventCallbacks) do
                sfui.events.UnregisterEvent(ev, cb)
            end
            self.eventCallbacks = nil
        end
        if container then
            container:SetScript("OnUpdate", nil)
            for _, r in ipairs(activeRows) do ReleaseRowFrame(r) end
            wipe(activeRows)
            wipe(activeRowsByKey)
            wipe(pendingQueue)
            wipe(skillCache)
            if pendingHeader then pendingHeader:Hide() end
        end
    end,

    OnSettingsChanged = function(self, key, value)
        UpdateLayout()
    end,
})

-- ─────────────────────────────────────────────────────────────────────────────
--  Theme Engine Integration
-- ─────────────────────────────────────────────────────────────────────────────
function sfui.lootfeed.UpdateTheme()
    for _, row in ipairs(activeRows) do
        if sfui.theme and sfui.theme.ApplyLootfeedRowStyle then
            sfui.theme.ApplyLootfeedRowStyle(row, row.lastColor, row.lastQuality)
        end
    end
    for _, row in ipairs(rowPool) do
        if sfui.theme and sfui.theme.ApplyLootfeedRowStyle then
            sfui.theme.ApplyLootfeedRowStyle(row, nil, nil)
        end
    end
    if pendingHeader and sfui.theme and sfui.theme.ApplyLootfeedPendingHeaderStyle then
        sfui.theme.ApplyLootfeedPendingHeaderStyle(pendingHeader)
    end
    if container then
        UpdateLayout()
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Test Preview Trigger for Options Panel
-- ─────────────────────────────────────────────────────────────────────────────
function sfui.lootfeed.TriggerTestFeed()
    local testItems = {
        { key = "TEST_ITEM_1", title = "|cffffffff[Rough Wooden Staff]|r (|cff69ccf0MageMate|r)",           icon = "Interface\\Icons\\INV_Staff_08",                       color = QUALITY_COLORS[1], quality = 1, quantity = 7,         badgeText = "x7",                                        itemLink = "item:4560", isOther = true, looter = "MageMate" },
        { key = "TEST_CURR_1", title = "|cff0070dd[Timewarped Badge]|r",                                     icon = "Interface\\Icons\\pvecurrency-justice",                color = QUALITY_COLORS[3], quality = 3, quantity = 100,       badgeText = "x100 (200)",                                currencyID = 1166,        tooltipTitle = "Timewarped Badge",   tooltipDesc = "Used to purchase rewards from Timewalking vendors." },
        { key = "TEST_ITEM_2", title = "|cffffffff[Paper Zeppelin]|r",                                       icon = "Interface\\Icons\\INV_Misc_Toy_02",                    color = QUALITY_COLORS[1], quality = 1, quantity = 9,         badgeText = "x9",                                        itemLink = "item:44606" },
        { key = "TEST_ITEM_3", title = "|cffa335ee[Xal'atath, Blade of the Black Empire]|r (|cffff7c0aDruidMate|r)", icon = "Interface\\Icons\\INV_Knife_1H_ArtifactXalatath_D_01", color = QUALITY_COLORS[4], quality = 4, quantity = 7, badgeText = "x7",                               itemLink = "item:128827", isOther = true, looter = "DruidMate" },
        { key = "TEST_XP_1",   title = "39727 XP",                                                           icon = "Interface\\Icons\\Spell_Holy_SurgeOfLight",            color = COLOR_XP,          quantity = 39727,     badgeText = "<90%>",                                     tooltipTitle = "Experience Gained", tooltipDesc = "Current: 39,727 / 44,140 (90%)" },
        { key = "TEST_SKILL_1", title = "+1 Fishing",                                                         icon = "Interface\\Icons\\Trade_Fishing",                      color = COLOR_SKILL,       quantity = 1,         badgeText = "75/150",                                    tooltipTitle = "Fishing: 75",       tooltipDesc = "Skill level increased to 75 of 150 (+1)." },
        { key = "TEST_ITEM_4", title = "|cffa335ee[Invincible's Reins]|r",                                   icon = "Interface\\Icons\\Ability_Mount_CelestialHorse",       color = QUALITY_COLORS[4], quality = 4, quantity = 1,         badgeText = "x1",                                        itemLink = "item:50818" },
        { key = "TEST_MONEY",         title = "39467" .. COIN_GOLD .. " 59" .. COIN_SILVER .. " 49" .. COIN_COPPER, icon = ICON_COIN_GOLD,   color = COLOR_GOLD,   quantity = 394675949, badgeText = "208.97K" .. COIN_GOLD, tooltipTitle = "Gold Earned",   tooltipDesc = "Total Wealth: 208,970 Gold 59 Silver" },
        { key = "TEST_MONEY_SILVER",  title = "74" .. COIN_SILVER .. " 12" .. COIN_COPPER,                         icon = ICON_COIN_SILVER, color = COLOR_SILVER, quantity = 7412,      badgeText = "208.97K" .. COIN_GOLD, tooltipTitle = "Silver Earned", tooltipDesc = "Total Wealth: 208,970 Gold 59 Silver" },
        { key = "TEST_ITEM_5", title = "|cffffffff[Linen Cloth]|r",                                          icon = "Interface\\Icons\\INV_Fabric_Linen_01",                color = QUALITY_COLORS[1], quality = 1, quantity = 4,         badgeText = "x4 " .. VENDOR_ICON .. " 52" .. COIN_COPPER, itemLink = "item:2589" },
        { key = "TEST_ITEM_6", title = "|cff9d9d9d[Wool Cloth]|r",                                           icon = "Interface\\Icons\\INV_Fabric_Wool_01",                 color = QUALITY_COLORS[0], quality = 0, quantity = 3,         badgeText = "x3 " .. VENDOR_ICON .. " 99" .. COIN_COPPER, itemLink = "item:2592" },
        { key = "TEST_ITEM_7", title = "|cff0070dd[Torn Journal Entry]|r",                                   icon = "Interface\\Icons\\INV_Misc_Note_01",                   color = QUALITY_COLORS[3], quality = 3, quantity = 1,         badgeText = "x1",                                        itemLink = "item:33009" },
    }

    for _, item in ipairs(testItems) do
        sfui.lootfeed.DisplayLoot(item)
    end
end

-- ─── Diagnostics & Memory Watcher Telemetry ──────────────────────────────────
local _lfDebug = {}
function sfui.lootfeed_debug_info()
    local db = GetConfig()
    _lfDebug.enabled = (db and db.enabled ~= false)
    _lfDebug.containerCreated = (container ~= nil)
    _lfDebug.containerShown = (container ~= nil and container:IsShown() == true)
    _lfDebug.activeRows = #activeRows
    _lfDebug.rowPool = #rowPool
    _lfDebug.queueSize = #pendingQueue
    _lfDebug.nodePool = #nodePool
    return _lfDebug
end
sfui.lootfeed.GetDebugInfo = sfui.lootfeed_debug_info
M.GetDebugInfo = sfui.lootfeed_debug_info
